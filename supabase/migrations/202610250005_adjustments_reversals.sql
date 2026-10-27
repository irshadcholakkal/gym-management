create table public.payment_reversals (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), payment_id uuid not null,
  kind text not null check(kind in ('reversal','refund')), reason text not null check(length(trim(reason))>0),
  actor_id uuid not null references auth.users(id), operation_id uuid not null unique, created_at timestamptz not null default now(), version bigint not null default 1,
  foreign key(gym_id,payment_id) references public.payments(gym_id,id), unique(payment_id)
);
alter table public.payment_reversals enable row level security;
revoke all on public.payment_reversals from public,anon,authenticated;
grant select on public.payment_reversals to authenticated;
create policy reversal_visibility on public.payment_reversals for select to authenticated using(private.has_role(gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]));
create index on public.payment_reversals(gym_id);
create trigger record_change after insert on public.payment_reversals for each row execute function private.log_change();

create function public.reverse_payment(p_gym uuid,p_payment uuid,p_kind text,p_reason text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.payments; alloc record; result jsonb; previous public.sync_operation_receipts; request jsonb;
begin
  if not public.can_administer(p_gym) then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  request=jsonb_build_object('payment',p_payment,'kind',p_kind,'reason',p_reason);
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  select * into strict p from public.payments where gym_id=p_gym and id=p_payment for update;
  insert into public.payment_reversals(gym_id,payment_id,kind,reason,actor_id,operation_id) values(p_gym,p_payment,p_kind,p_reason,auth.uid(),p_operation) returning to_jsonb(payment_reversals.*) into result;
  for alloc in select * from public.payment_allocations where gym_id=p_gym and payment_id=p_payment loop
    update public.invoices set paid_minor=paid_minor-alloc.amount_minor,version=version+1,updated_at=now(),
      status=case when paid_minor-alloc.amount_minor+credit_minor=0 then 'unpaid' else 'partially_paid' end where gym_id=p_gym and id=alloc.invoice_id;
  end loop;
  update public.receipts set status='voided',version=version+1 where gym_id=p_gym and payment_id=p_payment;
  insert into public.audit_logs(gym_id,actor_id,action,record_id,after_data) values(p_gym,auth.uid(),'payment:'||p_kind,p_payment,result);
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,result);
  return result;
end $$;

create function public.change_package(p_gym uuid,p_subscription uuid,p_expected bigint,p_package uuid,p_policy text,p_reason text,p_operation uuid,p_adjustment bigint default null)
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
  delta=round((p.price_minor::numeric/new_term-(s.package_snapshot->>'price_minor')::numeric/term)*remaining)::bigint;
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
revoke all on function public.reverse_payment(uuid,uuid,text,text,uuid),public.change_package(uuid,uuid,bigint,uuid,text,text,uuid,bigint) from public,anon;
grant execute on function public.reverse_payment(uuid,uuid,text,text,uuid),public.change_package(uuid,uuid,bigint,uuid,text,text,uuid,bigint) to authenticated;
