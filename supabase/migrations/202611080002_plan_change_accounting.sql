alter table public.invoices add column plan_changes jsonb not null default '[]';
alter table public.invoices add column document_kind text not null default 'invoice';
alter table public.subscription_plan_changes add column details jsonb not null default '{}';
alter table public.subscription_plan_changes add unique(gym_id,id);
create table public.member_credit_ledger (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id),
  member_id uuid not null, currency text not null, amount_minor bigint not null check(amount_minor<>0),
  source_change uuid not null, invoice_id uuid, actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(), version bigint not null default 1,
  foreign key(gym_id,member_id) references public.members(gym_id,id),
  foreign key(gym_id,source_change) references public.subscription_plan_changes(gym_id,id),
  foreign key(gym_id,invoice_id) references public.invoices(gym_id,id)
);
alter table public.member_credit_ledger enable row level security;
revoke all on public.member_credit_ledger from public,anon,authenticated;
grant select on public.member_credit_ledger to authenticated;
create policy member_credit_read on public.member_credit_ledger for select to authenticated using(
  private.has_role(gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]));
create index member_credit_balance on public.member_credit_ledger(gym_id,member_id,currency);
create trigger record_change after insert on public.member_credit_ledger for each row execute function private.log_change();
do $migration$
declare definition text; updated text;
begin
  select pg_get_functiondef('private.pull_authorized_changes(uuid,bigint)'::regprocedure) into definition;
  updated=replace(definition,'''credit_adjustments'',''receipts''','''credit_adjustments'',''member_credit_ledger'',''receipts''');
  if updated=definition then raise exception 'Member credit synchronization hook was not installed'; end if;
  execute updated;
end $migration$;

create function private.member_credit_balance(p_gym uuid,p_member uuid,p_currency text) returns bigint
language sql stable security definer set search_path='' as $$
  select coalesce(sum(amount_minor),0)::bigint from public.member_credit_ledger
  where gym_id=p_gym and member_id=p_member and currency=p_currency
$$;

create function private.apply_member_credit(p_gym uuid,p_invoice uuid) returns bigint
language plpgsql security definer set search_path='' as $$
declare bill public.invoices; bucket record; used bigint; applied bigint=0; context jsonb;
begin
  perform private.lock_gym(p_gym);
  select * into strict bill from public.invoices where gym_id=p_gym and id=p_invoice for update;
  if bill.status='voided' then return 0; end if;
  for bucket in select source_change,sum(amount_minor)::bigint as available,min(created_at) as first_created
    from public.member_credit_ledger where gym_id=p_gym and member_id=bill.member_id and currency=bill.currency
    group by source_change having sum(amount_minor)>0 order by min(created_at),source_change loop
    used=least(bucket.available,bill.total_minor-bill.paid_minor-bill.credit_minor);
    exit when used<=0;
    insert into public.member_credit_ledger(gym_id,member_id,currency,amount_minor,source_change,invoice_id,actor_id)
      values(p_gym,bill.member_id,bill.currency,-used,bucket.source_change,bill.id,auth.uid());
    insert into public.credit_adjustments(gym_id,invoice_id,amount_minor,reason,actor_id)
      values(p_gym,bill.id,-used,'Member credit applied from plan change',auth.uid());
    select details into context from public.subscription_plan_changes where gym_id=p_gym and id=bucket.source_change;
    if not exists(select 1 from jsonb_array_elements(bill.plan_changes) item where item->>'change_id'=bucket.source_change::text) then
      bill.plan_changes=bill.plan_changes||jsonb_build_array(context);
    end if;
    update public.invoices set credit_minor=credit_minor+used,plan_changes=bill.plan_changes,
      status=case when paid_minor+credit_minor+used=total_minor then 'paid' else status end,
      version=version+1,updated_at=now() where gym_id=p_gym and id=bill.id returning * into bill;
    applied=applied+used;
  end loop;
  return applied;
end $$;
revoke all on function private.member_credit_balance(uuid,uuid,text),private.apply_member_credit(uuid,uuid) from public,anon,authenticated;

create function public.quote_plan_change(p_gym uuid,p_subscription uuid,p_package uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.subscriptions; p public.membership_packages; today date; rate_date date;
  remaining int; old_term int; new_term int; old_price bigint; old_value bigint; new_value bigint;
  old_tax bigint; new_tax bigint; delta bigint; available bigint; outstanding bigint; tax_rate int;
begin
  perform private.require_finance(p_gym);
  select * into strict s from public.subscriptions where gym_id=p_gym and id=p_subscription;
  today=(now() at time zone (select timezone from public.gyms where id=p_gym))::date;
  if s.deleted_at is not null or s.status<>'active' or s.start_date>today or s.end_exclusive<=today then
    raise exception 'An immediate plan change requires a current, unpaused membership'; end if;
  select * into strict p from public.membership_packages where gym_id=p_gym and id=p_package and status='active';
  if p.id=s.package_id then raise exception 'Choose a different plan'; end if;
  if p.currency<>s.package_snapshot->>'currency' then raise exception 'Plans with different currencies require a separate membership'; end if;
  tax_rate=coalesce((s.package_snapshot->>'tax_basis_points')::int,0);
  if tax_rate<>p.tax_basis_points then raise exception 'Plans with different tax rates require a separate membership'; end if;
  if exists(select 1 from public.gym_settings where gym_id=p_gym and not allow_prorating) then raise exception 'Immediate plan changes require proration to be enabled in gym settings'; end if;
  select effective_date into rate_date from public.subscription_plan_changes where gym_id=p_gym and subscription_id=s.id order by created_at desc,id desc limit 1;
  rate_date=coalesce(rate_date,s.start_date);
  old_term=coalesce((s.package_snapshot->>'rate_term_days')::int,
    case when s.package_snapshot->>'duration_value' is not null and s.package_snapshot->>'duration_unit' is not null then
      public.membership_end(rate_date,(s.package_snapshot->>'duration_value')::int,s.package_snapshot->>'duration_unit')-rate_date end,
    s.original_end_exclusive-s.start_date);
  new_term=public.membership_end(today,p.duration_value,p.duration_unit)-today;
  if old_term<=0 or new_term<=0 then raise exception 'Invalid plan duration'; end if;
  remaining=s.end_exclusive-today;
  old_price=coalesce(s.package_snapshot->>'agreed_price_minor',s.package_snapshot->>'price_minor')::bigint;
  if old_price is null or old_price<0 then raise exception 'The previous plan price is unavailable'; end if;
  old_value=round(old_price::numeric*remaining/old_term)::bigint;
  new_value=round(p.price_minor::numeric*remaining/new_term)::bigint;
  old_tax=round(old_value::numeric*tax_rate/10000)::bigint;
  new_tax=round(new_value::numeric*tax_rate/10000)::bigint;
  delta=new_value+new_tax-old_value-old_tax;
  available=private.member_credit_balance(p_gym,s.member_id,p.currency);
  select coalesce(sum(total_minor-paid_minor-credit_minor),0)::bigint into outstanding from public.invoices
    where gym_id=p_gym and member_id=s.member_id and currency=p.currency and status<>'voided' and total_minor>paid_minor+credit_minor;
  return jsonb_build_object('subscription_id',s.id,'version',s.version,'member_id',s.member_id,'old_plan_id',s.package_id,'new_plan_id',p.id,
    'new_plan_version',p.version,'old_plan_name',s.package_snapshot->>'name','new_plan_name',p.name,'effective_date',today,
    'end_exclusive',s.end_exclusive,'remaining_days',remaining,'old_term_days',old_term,'new_term_days',new_term,
    'old_price_minor',old_price,'new_price_minor',p.price_minor,'old_unused_minor',old_value,'new_unused_minor',new_value,
    'old_tax_minor',old_tax,'new_tax_minor',new_tax,'delta_minor',delta,'currency',p.currency,
    'member_credit_before_minor',available,'outstanding_before_minor',outstanding,
    'credit_applied_minor',case when delta<0 then least(-delta,greatest(outstanding-available,0)) else least(available,delta) end,
    'member_credit_after_minor',case when delta<0 then greatest(available-delta-outstanding,0) else greatest(available-delta,0) end,
    'additional_payment_minor',greatest(delta-available,0),'requires_admin',delta<0 and not public.can_administer(p_gym));
end $$;

create function public.apply_plan_change(p_gym uuid,p_subscription uuid,p_package uuid,p_quote jsonb,p_reason text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q jsonb; request jsonb; previous public.sync_operation_receipts; s public.subscriptions; p public.membership_packages;
  change public.subscription_plan_changes; bill public.invoices; invoice_row record; delta bigint; result jsonb;
begin
  perform private.require_finance(p_gym);
  request=jsonb_build_object('subscription',p_subscription,'package',p_package,'quote',p_quote,'reason',p_reason,'policy','immediate');
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  q=public.quote_plan_change(p_gym,p_subscription,p_package);
  if q is distinct from p_quote then raise exception using errcode='40001',message='The plan, prices or balances changed. Reopen the plan change and review the latest calculation.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'A reason is required'; end if;
  delta=(q->>'delta_minor')::bigint;
  if delta<0 and not public.can_administer(p_gym) then raise insufficient_privilege using message='A downgrade credit requires administrator approval'; end if;
  select * into strict s from public.subscriptions where gym_id=p_gym and id=p_subscription for update;
  select * into strict p from public.membership_packages where gym_id=p_gym and id=p_package;
  insert into public.subscription_plan_changes(gym_id,subscription_id,old_package_id,new_package_id,effective_date,adjustment_minor,reason,actor_id)
    values(p_gym,s.id,s.package_id,p.id,(q->>'effective_date')::date,delta,trim(p_reason),auth.uid()) returning * into change;
  q=q||jsonb_build_object('change_id',change.id,'reason',trim(p_reason));
  update public.subscription_plan_changes set details=q where id=change.id;
  if delta>0 then
    insert into public.invoices(gym_id,member_id,subscription_id,currency,subtotal_minor,tax_minor,total_minor,due_date,actor_id,plan_changes)
      values(p_gym,s.member_id,s.id,p.currency,(q->>'new_unused_minor')::bigint-(q->>'old_unused_minor')::bigint,
        (q->>'new_tax_minor')::bigint-(q->>'old_tax_minor')::bigint,delta,(q->>'effective_date')::date,auth.uid(),jsonb_build_array(q)) returning * into bill;
    insert into public.invoice_items(gym_id,invoice_id,description,amount_minor,tax_minor)
      values(p_gym,bill.id,'Immediate plan change: '||(q->>'old_plan_name')||' to '||p.name,
        bill.subtotal_minor,bill.tax_minor);
    perform private.apply_member_credit(p_gym,bill.id);
  elsif delta<0 then
    insert into public.invoices(gym_id,member_id,subscription_id,currency,total_minor,subtotal_minor,due_date,actor_id,status,document_kind,plan_changes)
      values(p_gym,s.member_id,s.id,p.currency,0,0,(q->>'effective_date')::date,auth.uid(),'paid','plan_change_credit',jsonb_build_array(q)) returning * into bill;
    insert into public.invoice_items(gym_id,invoice_id,description,amount_minor)
      values(p_gym,bill.id,'Plan change credit: '||(q->>'old_plan_name')||' to '||p.name||'. Credit is applied to unpaid invoices or retained for future invoices.',0);
    insert into public.member_credit_ledger(gym_id,member_id,currency,amount_minor,source_change,invoice_id,actor_id)
      values(p_gym,s.member_id,p.currency,-delta,change.id,bill.id,auth.uid());
    for invoice_row in select id from public.invoices where gym_id=p_gym and member_id=s.member_id and currency=p.currency
      and status<>'voided' and total_minor>paid_minor+credit_minor order by (subscription_id=s.id) desc,due_date,id loop
      perform private.apply_member_credit(p_gym,invoice_row.id);
    end loop;
  end if;
  update public.subscriptions set package_id=p.id,
    package_snapshot=to_jsonb(p)||jsonb_build_object('agreed_price_minor',p.price_minor,'rate_term_days',(q->>'new_term_days')::int),
    version=version+1,updated_at=now(),actor_id=auth.uid() where gym_id=p_gym and id=s.id returning * into s;
  update public.notifications set superseded_at=now(),version=version+1,updated_at=now()
    where gym_id=p_gym and subscription_id=s.id and superseded_at is null;
  if bill.id is not null then select * into bill from public.invoices where gym_id=p_gym and id=bill.id; end if;
  result=jsonb_build_object('subscription',to_jsonb(s),'invoice',case when bill.id is null then null else to_jsonb(bill) end,
    'adjustment_minor',delta,'quote',q,'member_credit_minor',private.member_credit_balance(p_gym,s.member_id,p.currency));
  insert into public.audit_logs(gym_id,actor_id,action,record_id,after_data) values(p_gym,auth.uid(),'subscription:plan_change',s.id,result);
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,result);
  return result;
end $$;
revoke all on function public.quote_plan_change(uuid,uuid,uuid),public.apply_plan_change(uuid,uuid,uuid,jsonb,text,uuid) from public,anon;
grant execute on function public.quote_plan_change(uuid,uuid,uuid),public.apply_plan_change(uuid,uuid,uuid,jsonb,text,uuid) to authenticated;

-- Keep the old API for existing clients and explicit administrator overrides.
alter function public.change_package(uuid,uuid,bigint,uuid,text,text,uuid,bigint) set schema private;
revoke all on function private.change_package(uuid,uuid,bigint,uuid,text,text,uuid,bigint) from public,anon,authenticated;
create function public.change_package(p_gym uuid,p_subscription uuid,p_expected bigint,p_package uuid,p_policy text,p_reason text,p_operation uuid,p_adjustment bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q jsonb; previous public.sync_operation_receipts;
begin
  perform private.require_finance(p_gym);
  if p_policy<>'immediate' or p_adjustment is not null then
    if p_adjustment<0 then raise exception 'Use the calculated plan change to issue member credit'; end if;
    return private.change_package(p_gym,p_subscription,p_expected,p_package,p_policy,p_reason,p_operation,p_adjustment);
  end if;
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request->>'subscription'<>p_subscription::text
      or previous.request->>'package'<>p_package::text or previous.request->>'reason'<>p_reason then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  q=public.quote_plan_change(p_gym,p_subscription,p_package);
  if (q->>'version')::bigint<>p_expected then raise sqlstate '40001' using message='Membership changed. Review it again.'; end if;
  return public.apply_plan_change(p_gym,p_subscription,p_package,q,p_reason,p_operation);
end $$;
revoke all on function public.change_package(uuid,uuid,bigint,uuid,text,text,uuid,bigint) from public,anon;
grant execute on function public.change_package(uuid,uuid,bigint,uuid,text,text,uuid,bigint) to authenticated;

-- Apply carried credit after final pricing, not before the discount wrapper finishes.
do $migration$
declare definition text; updated text;
begin
  select pg_get_functiondef('public.create_subscription(uuid,uuid,uuid,date,uuid)'::regprocedure) into definition;
  updated=replace(definition,'  insert into public.sync_operation_receipts(',
    '  if coalesce(current_setting(''gympro.defer_member_credit'',true),''false'')<>''true'' then perform private.apply_member_credit(p_gym,i.id); select * into i from public.invoices where gym_id=p_gym and id=i.id; end if; insert into public.sync_operation_receipts(');
  if updated=definition then raise exception 'Membership creation credit hook was not installed'; end if;
  execute updated;
  select pg_get_functiondef('public.create_subscription_discounted(uuid,uuid,uuid,date,uuid,bigint,text)'::regprocedure) into definition;
  updated=replace(definition,'result_data=public.create_subscription(p_gym,p_member,p_package,p_start,p_operation);',
    'perform set_config(''gympro.defer_member_credit'',''true'',true); result_data=public.create_subscription(p_gym,p_member,p_package,p_start,p_operation); perform set_config(''gympro.defer_member_credit'',''false'',true);');
  updated=replace(updated,'result_data=jsonb_build_object(''subscription'',to_jsonb(s),''invoice'',to_jsonb(i));',
    'perform private.apply_member_credit(p_gym,i.id); select * into i from public.invoices where gym_id=p_gym and id=i.id; result_data=jsonb_build_object(''subscription'',to_jsonb(s),''invoice'',to_jsonb(i));');
  if updated=definition then raise exception 'Discounted membership credit hook was not installed'; end if;
  execute updated;
end $migration$;

-- Add adjustment context when a new receipt is issued. Previously issued snapshots are untouched.
create function private.receipt_plan_change_context() returns trigger
language plpgsql security definer set search_path='' as $$
declare p public.payments; contexts jsonb; credited bigint;
begin
  select * into strict p from public.payments where gym_id=new.gym_id and id=new.payment_id;
  select coalesce(jsonb_agg(distinct item),'[]') into contexts from public.payment_allocations a
    join public.invoices i on i.gym_id=a.gym_id and i.id=a.invoice_id
    cross join lateral jsonb_array_elements(i.plan_changes) item where a.gym_id=new.gym_id and a.payment_id=new.payment_id;
  select coalesce(sum(i.credit_minor),0)::bigint into credited from public.payment_allocations a
    join public.invoices i on i.gym_id=a.gym_id and i.id=a.invoice_id where a.gym_id=new.gym_id and a.payment_id=new.payment_id;
  new.snapshot=new.snapshot||jsonb_build_object('plan_changes',contexts,'credit_minor',credited,
    'member_credit_balance_minor',private.member_credit_balance(new.gym_id,p.member_id,p.currency));
  return new;
end $$;
revoke all on function private.receipt_plan_change_context() from public,anon,authenticated;
create trigger receipt_plan_change_context before insert on public.receipts for each row execute function private.receipt_plan_change_context();

do $migration$
declare definition text; updated text;
begin
  select pg_get_functiondef('public.get_invoice_document(uuid,uuid)'::regprocedure) into definition;
  updated=replace(definition,'''currency'',i.currency));',
    '''currency'',i.currency,''plan_changes'',i.plan_changes,''document_kind'',i.document_kind,''member_credit_balance_minor'',private.member_credit_balance(p_gym,i.member_id,i.currency)));');
  if updated=definition then raise exception 'Invoice plan-change context hook was not installed'; end if;
  execute updated;
end $migration$;
