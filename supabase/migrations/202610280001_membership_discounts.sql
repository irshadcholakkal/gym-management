alter table public.invoices
  add column subtotal_minor bigint,
  add column discount_minor bigint not null default 0,
  add column discount_reason text not null default '',
  add column discount_actor_id uuid references auth.users(id),
  add column discount_granted_at timestamptz;

update public.invoices set subtotal_minor=total_minor-tax_minor,
  version=version+1,updated_at=now();

create function private.invoice_subtotal_default() returns trigger language plpgsql set search_path='' as $$
begin
  if new.subtotal_minor is null then new.subtotal_minor=new.total_minor-new.tax_minor+new.discount_minor; end if;
  return new;
end $$;
create trigger invoice_subtotal_default before insert on public.invoices for each row execute function private.invoice_subtotal_default();
alter table public.invoices alter column subtotal_minor set not null;
alter table public.invoices add constraint invoice_discount_bounds check(discount_minor>=0 and subtotal_minor>=discount_minor);
alter table public.invoices add constraint invoice_discount_total check(total_minor=subtotal_minor-discount_minor+tax_minor);
alter table public.invoices add constraint invoice_discount_audit check(discount_minor=0 or (length(trim(discount_reason))>0 and discount_actor_id is not null and discount_granted_at is not null));
revoke all on function private.invoice_subtotal_default() from public,anon,authenticated;

create function public.create_subscription_discounted(
  p_gym uuid,p_member uuid,p_package uuid,p_start date,p_operation uuid,
  p_discount_minor bigint default 0,p_discount_reason text default ''
) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.membership_packages; s public.subscriptions; i public.invoices;
  previous public.sync_operation_receipts; base_request jsonb; request_data jsonb; result_data jsonb;
  taxable bigint; tax bigint;
begin
  perform private.require_finance(p_gym);
  base_request=jsonb_build_object('member',p_member,'package',p_package,'start',p_start);
  request_data=base_request||jsonb_build_object('discount_minor',p_discount_minor,'discount_reason',trim(coalesce(p_discount_reason,'')));
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or
      (previous.request<>request_data and not (p_discount_minor=0 and coalesce(trim(p_discount_reason),'')='' and previous.request=base_request)) then
      raise exception 'Idempotency key reused with different membership details';
    end if;
    return previous.result;
  end if;
  if p_discount_minor is null or p_discount_minor<0 then raise exception 'Discount cannot be negative'; end if;
  if p_discount_minor>0 and not private.has_role(p_gym,array['owner','admin','manager']::public.gym_role[]) then
    raise insufficient_privilege using message='Only an owner, administrator or manager can grant a membership discount';
  end if;
  if p_discount_minor>0 and nullif(trim(p_discount_reason),'') is null then raise exception 'Enter a reason for the discount'; end if;
  if length(coalesce(p_discount_reason,''))>500 then raise exception 'Discount reason must be 500 characters or fewer'; end if;
  select * into p from public.membership_packages where gym_id=p_gym and id=p_package and status='active';
  if not found then raise exception 'Select an active membership package'; end if;
  if p_discount_minor>p.price_minor then raise exception 'Discount cannot exceed the membership package price'; end if;
  if exists(select 1 from public.subscriptions where gym_id=p_gym and member_id=p_member and status='paused') then
    raise exception 'Resume the current membership before creating or renewing a membership for this member';
  end if;

  result_data=public.create_subscription(p_gym,p_member,p_package,p_start,p_operation);
  taxable=p.price_minor-p_discount_minor+p.enrollment_fee_minor;
  tax=floor((taxable::numeric*p.tax_basis_points+5000)/10000)::bigint;
  update public.invoices set subtotal_minor=p.price_minor+p.enrollment_fee_minor,
    discount_minor=p_discount_minor,discount_reason=case when p_discount_minor>0 then trim(p_discount_reason) else '' end,
    discount_actor_id=case when p_discount_minor>0 then auth.uid() end,
    discount_granted_at=case when p_discount_minor>0 then now() end,
    tax_minor=tax,total_minor=taxable+tax,status=case when taxable+tax=0 then 'paid' else 'unpaid' end,
    updated_at=now(),version=version+1
    where gym_id=p_gym and id=(result_data->'invoice'->>'id')::uuid returning * into i;
  update public.invoice_items set tax_minor=tax where gym_id=p_gym and invoice_id=i.id;
  if p_discount_minor>0 then
    insert into public.invoice_items(gym_id,invoice_id,description,amount_minor)
      values(p_gym,i.id,'Special discount: '||trim(p_discount_reason),-p_discount_minor);
  end if;
  update public.subscriptions set package_snapshot=package_snapshot||jsonb_build_object(
    'discount_minor',p_discount_minor,'agreed_price_minor',p.price_minor-p_discount_minor),
    updated_at=now(),version=version+1
    where gym_id=p_gym and id=(result_data->'subscription'->>'id')::uuid returning * into s;
  result_data=jsonb_build_object('subscription',to_jsonb(s),'invoice',to_jsonb(i));
  update public.sync_operation_receipts set request=request_data,result=result_data where id=p_operation;
  return result_data;
end $$;
revoke all on function public.create_subscription_discounted(uuid,uuid,uuid,date,uuid,bigint,text) from public,anon;
grant execute on function public.create_subscription_discounted(uuid,uuid,uuid,date,uuid,bigint,text) to authenticated;

create index invoice_discounts_by_month on public.invoices(gym_id,discount_granted_at) where discount_minor>0;

create or replace function public.post_payment(p_gym uuid,p_invoice uuid,p_amount bigint,p_method text,p_reference text,p_operation uuid)
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
    'subtotal_minor',i.subtotal_minor,'discount_minor',i.discount_minor,'discount_reason',i.discount_reason,'total_minor',i.total_minor,'tax_minor',i.tax_minor,'paid_minor',p_amount,'balance_minor',i.total_minor-i.paid_minor-i.credit_minor,
    'currency',i.currency,'method',p_method,'reference',p_reference,'payment_date',p.created_at,'issuer',coalesce((select full_name from public.employees where gym_id=p_gym and user_id=auth.uid()),(select raw_user_meta_data->>'full_name' from auth.users where id=auth.uid()),'Team member'),'issuer_id',auth.uid()
  )) returning * into r;
  result=jsonb_build_object('payment',to_jsonb(p),'receipt',to_jsonb(r),'invoice',to_jsonb(i));
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,result);
  return result;
end $$;

create or replace function public.change_package(p_gym uuid,p_subscription uuid,p_expected bigint,p_package uuid,p_policy text,p_reason text,p_operation uuid,p_adjustment bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.subscriptions; p public.membership_packages; today date; remaining int; term int; new_term int; delta bigint; collected bigint; due_invoice public.invoices; new_invoice public.invoices; previous public.sync_operation_receipts; request jsonb; result jsonb;
begin
  perform private.require_finance(p_gym);
  request=jsonb_build_object('subscription',p_subscription,'expected',p_expected,'package',p_package,'policy',p_policy,'reason',p_reason,'adjustment',p_adjustment);
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  select * into strict s from public.subscriptions where gym_id=p_gym and id=p_subscription for update;
  if s.version<>p_expected then raise exception using errcode='40001',message='Membership version changed'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'A reason is required'; end if;
  select * into strict p from public.membership_packages where gym_id=p_gym and id=p_package and status='active';
  if p.currency<>s.package_snapshot->>'currency' then raise exception 'Currency change requires a separate subscription'; end if;
  today=(now() at time zone (select timezone from public.gyms where id=p_gym))::date;
  if p_policy='next_renewal' then
    result=public.create_subscription(p_gym,s.member_id,p.id,s.end_exclusive,p_operation);
    -- create_subscription has already recorded this operation; replace its request
    -- with this wrapper's identity while retaining its committed result.
    update public.sync_operation_receipts r set request=jsonb_build_object('subscription',p_subscription,'expected',p_expected,'package',p_package,'policy',p_policy,'reason',p_reason,'adjustment',p_adjustment) where r.id=p_operation;
    return result;
  end if;
  if p_policy<>'immediate' or s.status<>'active' or s.end_exclusive<=today then raise exception 'Immediate change requires an active membership'; end if;
  term=s.original_end_exclusive-s.start_date;
  remaining=least(term,s.end_exclusive-today);
  new_term=public.membership_end(today,p.duration_value,p.duration_unit)-today;
  -- Prorate exact numeric daily rates, round only once to integer minor units.
  delta=round((p.price_minor::numeric/new_term-coalesce(s.package_snapshot->>'agreed_price_minor',s.package_snapshot->>'price_minor')::numeric/term)*remaining)::bigint;
  if p_adjustment is not null then
    if not public.can_administer(p_gym) then raise insufficient_privilege; end if;
    delta=p_adjustment;
  elsif exists(select 1 from public.gym_settings where gym_id=p_gym and not allow_prorating) then
    raise exception 'Prorating disabled; an administrator must approve an adjustment';
  end if;
  if delta>0 then
    insert into public.invoices(gym_id,member_id,subscription_id,currency,total_minor,due_date,actor_id) values(p_gym,s.member_id,s.id,p.currency,delta,today,auth.uid()) returning * into new_invoice;
    insert into public.invoice_items(gym_id,invoice_id,description,amount_minor) values(p_gym,new_invoice.id,'Package change adjustment: '||p.name,delta);
  elsif delta<0 then
    if not public.can_administer(p_gym) then raise insufficient_privilege using message='Downgrades require administrator approval'; end if;
    select coalesce(sum(a.amount_minor),0) into collected from public.payment_allocations a join public.invoices i on i.id=a.invoice_id and i.gym_id=a.gym_id where a.gym_id=p_gym and i.subscription_id=s.id and not exists(select 1 from public.payment_reversals pr where pr.payment_id=a.payment_id);
    collected=greatest(0,collected+coalesce((select sum(c.amount_minor) from public.credit_adjustments c join public.invoices i on i.id=c.invoice_id and i.gym_id=c.gym_id where c.gym_id=p_gym and i.subscription_id=s.id),0));
    select * into due_invoice from public.invoices where gym_id=p_gym and subscription_id=s.id and total_minor>paid_minor+credit_minor order by created_at limit 1 for update;
    -- Credits are capped at cash actually collected and remaining receivables;
    -- cash refunds require an explicit reversal of the corresponding payment.
    delta=-least(-delta,collected,coalesce(due_invoice.total_minor-due_invoice.paid_minor-due_invoice.credit_minor,0));
    if delta<0 then
      insert into public.credit_adjustments(gym_id,invoice_id,amount_minor,reason,actor_id) values(p_gym,due_invoice.id,delta,p_reason,auth.uid());
      update public.invoices set credit_minor=credit_minor-delta,status=case when paid_minor+credit_minor-delta=total_minor then 'paid' else status end,version=version+1,updated_at=now() where id=due_invoice.id;
    end if;
  end if;
  insert into public.subscription_plan_changes(gym_id,subscription_id,old_package_id,new_package_id,effective_date,adjustment_minor,reason,actor_id) values(p_gym,s.id,s.package_id,p.id,today,delta,p_reason,auth.uid());
  update public.subscriptions set package_id=p.id,package_snapshot=to_jsonb(p),updated_at=now(),version=version+1,actor_id=auth.uid() where id=s.id returning to_jsonb(subscriptions.*) into result;
  update public.notifications set superseded_at=now(),updated_at=now(),version=version+1 where gym_id=p_gym and subscription_id=s.id and superseded_at is null;
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,jsonb_build_object('subscription',result,'adjustment_minor',delta));
  return jsonb_build_object('subscription',result,'adjustment_minor',delta);
end $$;
