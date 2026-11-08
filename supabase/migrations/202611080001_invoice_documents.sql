-- Number existing and future invoices without changing financial balances.
alter table public.invoices add column invoice_number bigint generated always as identity;
create unique index invoice_number_unique on public.invoices(invoice_number);
-- Publish the assigned numbers through the existing tenant change stream.
update public.invoices set version=version+1,updated_at=now();

create table public.invoice_designs (
  gym_id uuid primary key references public.gyms(id),
  html text not null check(length(html) between 1 and 100000),
  version bigint not null default 1, updated_at timestamptz not null default now()
);
alter table public.invoice_designs enable row level security;
create policy invoice_design_read on public.invoice_designs for select to authenticated using(
  public.can_administer(gym_id) or private.has_role(gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]));
grant select on public.invoice_designs to authenticated;
create function public.save_invoice_design(p_gym uuid,p_html text,p_expected bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare existing public.invoice_designs; result public.invoice_designs;
begin
  if not public.can_administer(p_gym) then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  if p_html is null or length(trim(p_html))=0 or length(p_html)>100000 then raise exception 'Invoice HTML must contain 1 to 100000 characters'; end if;
  select * into existing from public.invoice_designs where gym_id=p_gym;
  if coalesce(existing.version,0)<>p_expected then raise sqlstate '40001' using message='Invoice design changed. Reload before saving.'; end if;
  insert into public.invoice_designs(gym_id,html) values(p_gym,p_html)
    on conflict(gym_id) do update set html=excluded.html,version=invoice_designs.version+1,updated_at=now() returning * into result;
  insert into public.audit_logs(gym_id,actor_id,action,record_id,after_data)
    values(p_gym,auth.uid(),'invoice:design',p_gym,jsonb_build_object('version',result.version));
  return to_jsonb(result);
end $$;

-- Preview/printing reads the stored invoice and its current balance; it never creates a new invoice or payment.
create function public.get_invoice_document(p_gym uuid,p_invoice uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.invoices; m public.members; g public.gyms; s public.subscriptions; lines jsonb;
begin
  perform private.require_finance(p_gym);
  select * into strict i from public.invoices where gym_id=p_gym and id=p_invoice;
  select * into strict m from public.members where gym_id=p_gym and id=i.member_id;
  select * into strict g from public.gyms where id=p_gym;
  select * into s from public.subscriptions where gym_id=p_gym and id=i.subscription_id;
  select coalesce(jsonb_agg(to_jsonb(item) order by item.created_at,item.id),'[]') into lines
    from public.invoice_items item where item.gym_id=p_gym and item.invoice_id=i.id;
  return to_jsonb(i)||jsonb_build_object('items',lines,'snapshot',jsonb_build_object(
    'gym_name',g.name,'gym_address',g.address,'gym_phone',g.phone,
    'member_name',m.full_name,'member_number',m.member_number,'member_email',m.email,'member_phone',m.phone,
    'package_name',s.package_snapshot->>'name','start_date',s.start_date,'end_exclusive',s.end_exclusive,
    'subtotal_minor',i.subtotal_minor,'discount_minor',i.discount_minor,'discount_reason',i.discount_reason,
    'tax_minor',i.tax_minor,'total_minor',i.total_minor,'paid_minor',i.paid_minor,'credit_minor',i.credit_minor,
    'balance_minor',case when i.status='voided' then 0 else i.total_minor-i.paid_minor-i.credit_minor end,'currency',i.currency));
end $$;
revoke all on function public.save_invoice_design(uuid,text,bigint),public.get_invoice_document(uuid,uuid) from public,anon;
grant execute on function public.save_invoice_design(uuid,text,bigint),public.get_invoice_document(uuid,uuid) to authenticated;
