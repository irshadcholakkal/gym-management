create function public.membership_end(p_start date,p_value int,p_unit text) returns date
language plpgsql immutable set search_path='' as $$
begin
  if p_value<=0 then raise exception 'Duration must be positive'; end if;
  case p_unit
    when 'days' then return p_start+p_value;
    when 'weeks' then return p_start+7*p_value;
    when 'months' then return (p_start+make_interval(months=>p_value))::date;
    when 'years' then return (p_start+make_interval(years=>p_value))::date;
    else raise exception 'Invalid duration unit';
  end case;
end $$;
create function private.require_finance(p_gym uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if not private.has_role(p_gym,array['owner','admin','manager','receptionist']::public.gym_role[]) then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
end $$;

create function public.create_subscription(p_gym uuid,p_member uuid,p_package uuid,p_start date,p_operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.membership_packages; s public.subscriptions; i public.invoices; previous public.sync_operation_receipts; request jsonb; total bigint; tax bigint;
begin
  perform private.require_finance(p_gym);
  request=jsonb_build_object('member',p_member,'package',p_package,'start',p_start);
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  select * into strict p from public.membership_packages where gym_id=p_gym and id=p_package and status='active';
  if not exists(select 1 from public.members where gym_id=p_gym and id=p_member and status='active') then raise exception 'Active member required'; end if;
  if p_start<(now() at time zone (select timezone from public.gyms where id=p_gym))::date and not public.can_administer(p_gym) then raise insufficient_privilege using message='Backdating requires administrator permission'; end if;
  insert into public.subscriptions(gym_id,member_id,package_id,package_snapshot,start_date,original_end_exclusive,end_exclusive,status,pause_allowance,actor_id)
  values(p_gym,p_member,p_package,to_jsonb(p),p_start,public.membership_end(p_start,p.duration_value,p.duration_unit),public.membership_end(p_start,p.duration_value,p.duration_unit),
    case when p_start>(now() at time zone (select timezone from public.gyms where id=p_gym))::date then 'scheduled_renewal' else 'active' end,p.allowed_pause_days,auth.uid()) returning * into s;
  tax=((p.price_minor+p.enrollment_fee_minor)*p.tax_basis_points+5000)/10000;
  total=p.price_minor+p.enrollment_fee_minor+tax;
  insert into public.invoices(gym_id,member_id,subscription_id,currency,total_minor,tax_minor,due_date,actor_id,status)
    values(p_gym,p_member,s.id,p.currency,total,tax,p_start,auth.uid(),case when total=0 then 'paid' else 'unpaid' end) returning * into i;
  insert into public.invoice_items(gym_id,invoice_id,description,amount_minor,tax_minor) values(p_gym,i.id,p.name,p.price_minor+p.enrollment_fee_minor,tax);
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,jsonb_build_object('subscription',to_jsonb(s),'invoice',to_jsonb(i)));
  return jsonb_build_object('subscription',to_jsonb(s),'invoice',to_jsonb(i));
end $$;

create function public.effective_subscription_end(p_gym uuid,p_subscription uuid,p_asof date default null) returns date
language plpgsql stable security definer set search_path='' as $$
declare s public.subscriptions; d date; paused int;
begin
  if not private.has_role(p_gym) then raise insufficient_privilege; end if;
  select * into strict s from public.subscriptions where gym_id=p_gym and id=p_subscription;
  if not private.has_role(p_gym,array['owner','admin','manager','receptionist']::public.gym_role[]) and not exists(select 1 from public.members m join public.employees e on e.id=m.assigned_trainer and e.gym_id=m.gym_id where m.gym_id=p_gym and m.id=s.member_id and e.user_id=auth.uid() and e.status='active') then raise insufficient_privilege; end if;
  d=coalesce(p_asof,(now() at time zone (select timezone from public.gyms where id=p_gym))::date);
  select coalesce(sum(greatest(0,coalesce(resume_date,d)-start_date)),0)::int into paused from public.subscription_pauses where gym_id=p_gym and subscription_id=p_subscription;
  return s.original_end_exclusive+paused+s.extension_days;
end $$;

create function public.transition_subscription(p_gym uuid,p_subscription uuid,p_expected bigint,p_action text,p_date date,p_reason text,p_operation uuid,p_days int default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.subscriptions; pause public.subscription_pauses; today date; used_days int; previous public.sync_operation_receipts; request jsonb; result jsonb;
begin
  perform private.require_finance(p_gym);
  request=jsonb_build_object('subscription',p_subscription,'expected',p_expected,'action',p_action,'date',p_date,'reason',p_reason,'days',p_days);
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  select * into strict s from public.subscriptions where gym_id=p_gym and id=p_subscription for update;
  if s.version<>p_expected then raise exception using errcode='40001',message='Membership changed; refresh before retrying'; end if;
  today=(now() at time zone (select timezone from public.gyms where id=p_gym))::date;
  if nullif(trim(p_reason),'') is null then raise exception 'A reason is required'; end if;
  if p_date>today or p_date<s.start_date then raise exception 'Transition date is outside the allowed range'; end if;
  if p_date<today and not public.can_administer(p_gym) then raise insufficient_privilege using message='Backdating requires administrator permission'; end if;
  if p_action='pause' then
    if (s.status<>'active' and not (s.status='expired' and public.can_administer(p_gym) and p_date<today)) or p_date>=public.effective_subscription_end(p_gym,s.id,p_date) then raise exception 'Only active unexpired memberships may pause; historical corrections require an administrator'; end if;
    select coalesce(sum(resume_date-start_date),0)::int into used_days from public.subscription_pauses where gym_id=p_gym and subscription_id=s.id;
    if used_days>=s.pause_allowance then raise exception 'Pause allowance exhausted'; end if;
    insert into public.subscription_pauses(gym_id,subscription_id,start_date,reason,actor_id) values(p_gym,s.id,p_date,p_reason,auth.uid());
    update public.subscriptions set status='paused' where id=s.id;
  elsif p_action='resume' then
    if s.status<>'paused' then raise exception 'Membership is not paused'; end if;
    select * into strict pause from public.subscription_pauses where gym_id=p_gym and subscription_id=s.id and resume_date is null for update;
    if p_date<pause.start_date then raise exception 'Resume precedes pause'; end if;
    select coalesce(sum(resume_date-start_date),0)::int into used_days from public.subscription_pauses where gym_id=p_gym and subscription_id=s.id and resume_date is not null;
    if used_days+p_date-pause.start_date>s.pause_allowance and not public.can_administer(p_gym) then raise exception 'Pause allowance exceeded; administrator approval required'; end if;
    update public.subscription_pauses set resume_date=p_date,resumed_by=auth.uid(),updated_at=now(),version=version+1 where id=pause.id;
    update public.subscriptions set status=case when public.effective_subscription_end(p_gym,s.id,today)<=today then 'expired' else 'active' end where id=s.id;
  elsif p_action='extend' then
    if not public.can_administer(p_gym) or p_days<=0 or s.status in ('cancelled','draft') then raise insufficient_privilege; end if;
    update public.subscriptions set extension_days=extension_days+p_days where id=s.id;
  elsif p_action='cancel' then
    if not public.can_administer(p_gym) then raise insufficient_privilege; end if;
    if s.status='cancelled' then raise exception 'Already cancelled'; end if;
    update public.subscriptions set status='cancelled' where id=s.id;
  else raise exception 'Unsupported transition'; end if;
  update public.subscriptions set end_exclusive=public.effective_subscription_end(p_gym,s.id,today),version=version+1,updated_at=now(),actor_id=auth.uid() where id=s.id returning to_jsonb(subscriptions.*) into result;
  update public.notifications set superseded_at=now(),updated_at=now(),version=version+1 where gym_id=p_gym and subscription_id=s.id and superseded_at is null;
  insert into public.audit_logs(gym_id,actor_id,action,record_id,before_data,after_data) values(p_gym,auth.uid(),'subscription:'||p_action,s.id,to_jsonb(s),jsonb_build_object('record',result,'reason',p_reason));
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,result);
  return result;
end $$;

create function public.post_payment(p_gym uuid,p_invoice uuid,p_amount bigint,p_method text,p_reference text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare i public.invoices; p public.payments; r public.receipts; m public.members; g public.gyms; s public.subscriptions; previous public.sync_operation_receipts; request jsonb; result jsonb;
begin
  perform private.require_finance(p_gym);
  request=jsonb_build_object('invoice',p_invoice,'amount',p_amount,'method',p_method,'reference',p_reference);
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  select * into strict i from public.invoices where gym_id=p_gym and id=p_invoice for update;
  if p_amount<=0 or p_amount>i.total_minor-i.paid_minor-i.credit_minor or i.status='voided' then raise exception 'Payment exceeds balance or invoice is void'; end if;
  insert into public.payments(gym_id,member_id,amount_minor,currency,method,reference,idempotency_key,actor_id) values(p_gym,i.member_id,p_amount,i.currency,p_method,coalesce(p_reference,''),p_operation,auth.uid()) returning * into p;
  insert into public.payment_allocations(gym_id,payment_id,invoice_id,amount_minor) values(p_gym,p.id,i.id,p_amount);
  update public.invoices set paid_minor=paid_minor+p_amount,status=case when paid_minor+p_amount+credit_minor=total_minor then 'paid' else 'partially_paid' end,updated_at=now(),version=version+1 where id=i.id returning * into i;
  select * into strict m from public.members where gym_id=p_gym and id=i.member_id;
  select * into strict g from public.gyms where id=p_gym;
  select * into s from public.subscriptions where gym_id=p_gym and id=i.subscription_id;
  insert into public.receipts(gym_id,payment_id,snapshot) values(p_gym,p.id,jsonb_build_object(
    'gym_name',g.name,'gym_address',g.address,'gym_phone',g.phone,'member_name',m.full_name,'member_number',m.member_number,
    'package_name',s.package_snapshot->>'name','start_date',s.start_date,'end_exclusive',s.end_exclusive,
    'total_minor',i.total_minor,'tax_minor',i.tax_minor,'paid_minor',p_amount,'balance_minor',i.total_minor-i.paid_minor-i.credit_minor,
    'currency',i.currency,'method',p_method,'reference',p_reference,'payment_date',p.created_at,'issuer',auth.uid()
  )) returning * into r;
  result=jsonb_build_object('payment',to_jsonb(p),'receipt',to_jsonb(r),'invoice',to_jsonb(i));
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,result);
  return result;
end $$;

create function public.set_notification_read(p_gym uuid,p_notification uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if not private.has_role(p_gym) then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  update public.notifications set read_at=coalesce(read_at,now()),updated_at=now(),version=version+1 where gym_id=p_gym and id=p_notification and recipient_id=auth.uid();
end $$;

create function public.deactivate_employee(p_gym uuid,p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.can_administer(p_gym) or p_user=auth.uid() then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  if exists(select 1 from public.gym_users where gym_id=p_gym and user_id=p_user and role='owner') then raise exception 'Owner access must be transferred explicitly'; end if;
  update public.gym_users set active=false,version=version+1,updated_at=now() where gym_id=p_gym and user_id=p_user;
  update public.employees set status='inactive',version=version+1,updated_at=now() where gym_id=p_gym and user_id=p_user;
end $$;

create function public.process_expiry_reminders() returns int language plpgsql security definer set search_path='' as $$
declare g record; s record; today date; expiry date; count_created int=0; affected int;
begin
  for g in select * from public.gyms order by id loop
    perform private.lock_gym(g.id);
    today=(now() at time zone g.timezone)::date;
    update public.subscriptions set status='active',updated_at=now(),version=version+1 where gym_id=g.id and status='scheduled_renewal' and start_date<=today and end_exclusive>today;
    update public.subscriptions set status='expired',updated_at=now(),version=version+1 where gym_id=g.id and status='active' and end_exclusive<=today;
    for s in select * from public.subscriptions where gym_id=g.id and status='active' loop
      expiry=s.end_exclusive-1;
      if expiry-today=7 then
        insert into public.notifications(gym_id,recipient_id,subscription_id,expiry_date,expiry_version,type,title,body)
        select g.id,gu.user_id,s.id,expiry,s.version,'expiry_7','Membership renewal due','A membership expires in 7 calendar days. Open GymPro to review.'
        from public.gym_users gu where gu.gym_id=g.id and gu.active and gu.role in ('owner','admin') on conflict do nothing;
        get diagnostics affected=row_count;
        count_created=count_created+affected;
      end if;
    end loop;
  end loop;
  return count_created;
end $$;
revoke all on function public.process_expiry_reminders() from public,anon,authenticated;
grant execute on function public.process_expiry_reminders() to service_role;

revoke all on function private.require_finance(uuid) from public,anon,authenticated;
revoke all on function public.create_subscription(uuid,uuid,uuid,date,uuid),public.transition_subscription(uuid,uuid,bigint,text,date,text,uuid,int),public.post_payment(uuid,uuid,bigint,text,text,uuid),public.effective_subscription_end(uuid,uuid,date),public.deactivate_employee(uuid,uuid),public.set_notification_read(uuid,uuid) from public,anon;
grant execute on function public.create_subscription(uuid,uuid,uuid,date,uuid),public.transition_subscription(uuid,uuid,bigint,text,date,text,uuid,int),public.post_payment(uuid,uuid,bigint,text,text,uuid),public.effective_subscription_end(uuid,uuid,date),public.deactivate_employee(uuid,uuid),public.set_notification_read(uuid,uuid) to authenticated;

-- Cron is enabled explicitly during deployment after validating the migration.
-- select cron.schedule('gympro-expiry-hourly','5 * * * *', 'select public.process_expiry_reminders()');
