-- A single server snapshot for monthly/yearly exports, without REST row limits.
create function public.get_period_report(p_gym uuid, p_year integer, p_month integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  g public.gyms; first_day date; next_day date;
  first_instant timestamptz; next_instant timestamptz; result jsonb;
begin
  perform private.require_finance(p_gym);
  if p_year is null or p_year < 1900 or p_year > 9998 or
     (p_month is not null and (p_month < 1 or p_month > 12)) then
    raise exception 'Choose a valid report year and month';
  end if;
  select * into strict g from public.gyms where id=p_gym;
  first_day=make_date(p_year,coalesce(p_month,1),1);
  next_day=(first_day + case when p_month is null then interval '1 year' else interval '1 month' end)::date;
  first_instant=first_day::timestamp at time zone g.timezone;
  next_instant=next_day::timestamp at time zone g.timezone;
  select jsonb_build_object(
    'gym_name',g.name,'currency',g.currency,'timezone',g.timezone,
    'generated_at',to_char(now() at time zone g.timezone,'YYYY-MM-DD HH24:MI'),
    'start_date',first_day,'end_exclusive',next_day,
    'invoices',coalesce((select jsonb_agg(to_jsonb(r) order by r.date,r.id) from (
      select i.id,i.invoice_number,(i.created_at at time zone g.timezone)::date as date,
        i.due_date,m.full_name as member_name,m.member_number,
        i.currency,i.subtotal_minor,i.discount_minor,i.tax_minor,i.total_minor,
        i.paid_minor,i.credit_minor,
        case when i.status='voided' then 0 else i.total_minor-i.paid_minor-i.credit_minor end as balance_minor,
        i.status
      from public.invoices i join public.members m on m.gym_id=i.gym_id and m.id=i.member_id
      where i.gym_id=p_gym and i.created_at>=first_instant and i.created_at<next_instant
    ) r),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(r) order by r.date,r.id) from (
      select p.id,(p.created_at at time zone g.timezone)::date as date,
        m.full_name as member_name,m.member_number,p.amount_minor,p.currency,p.method,p.reference,
        rc.receipt_number,(rv.id is not null) as reversed
      from public.payments p join public.members m on m.gym_id=p.gym_id and m.id=p.member_id
      left join public.receipts rc on rc.gym_id=p.gym_id and rc.payment_id=p.id
      left join public.payment_reversals rv on rv.gym_id=p.gym_id and rv.payment_id=p.id
      where p.gym_id=p_gym and p.created_at>=first_instant and p.created_at<next_instant
    ) r),'[]'::jsonb),
    'reversals',coalesce((select jsonb_agg(to_jsonb(r) order by r.date,r.id) from (
      select rv.id,rv.payment_id,(rv.created_at at time zone g.timezone)::date as date,
        m.full_name as member_name,m.member_number,p.amount_minor,p.currency,rv.kind,rv.reason
      from public.payment_reversals rv
      join public.payments p on p.gym_id=rv.gym_id and p.id=rv.payment_id
      join public.members m on m.gym_id=p.gym_id and m.id=p.member_id
      where rv.gym_id=p_gym and rv.created_at>=first_instant and rv.created_at<next_instant
    ) r),'[]'::jsonb),
    'receipts',coalesce((select jsonb_agg(to_jsonb(r) order by r.date,r.id) from (
      select rc.id,rc.receipt_number,(rc.created_at at time zone g.timezone)::date as date,
        rc.snapshot->>'member_name' as member_name,rc.snapshot->>'member_number' as member_number,
        p.amount_minor,p.currency,rc.status
      from public.receipts rc join public.payments p on p.gym_id=rc.gym_id and p.id=rc.payment_id
      where rc.gym_id=p_gym and rc.created_at>=first_instant and rc.created_at<next_instant
    ) r),'[]'::jsonb),
    'members',coalesce((select jsonb_agg(to_jsonb(r) order by r.date,r.id) from (
      select m.id,m.joining_date as date,m.member_number,m.full_name as member_name,m.phone,m.email,m.status
      from public.members m where m.gym_id=p_gym and m.joining_date>=first_day and m.joining_date<next_day
    ) r),'[]'::jsonb),
    'memberships',coalesce((select jsonb_agg(to_jsonb(r) order by r.date,r.id) from (
      select s.id,s.start_date as date,s.end_exclusive-1 as valid_through,
        m.full_name as member_name,m.member_number,s.package_snapshot->>'name' as package_name,
        case when s.deleted_at is not null then 'deleted' else s.status end as status
      from public.subscriptions s join public.members m on m.gym_id=s.gym_id and m.id=s.member_id
      where s.gym_id=p_gym and s.start_date>=first_day and s.start_date<next_day
    ) r),'[]'::jsonb),
    'invoice_credits',coalesce((select jsonb_agg(to_jsonb(r) order by r.date,r.id) from (
      select c.id,(c.created_at at time zone g.timezone)::date as date,i.invoice_number,
        m.full_name as member_name,c.amount_minor,i.currency,c.reason
      from public.credit_adjustments c join public.invoices i on i.gym_id=c.gym_id and i.id=c.invoice_id
      join public.members m on m.gym_id=i.gym_id and m.id=i.member_id
      where c.gym_id=p_gym and c.created_at>=first_instant and c.created_at<next_instant
    ) r),'[]'::jsonb),
    'member_credits',coalesce((select jsonb_agg(to_jsonb(r) order by r.date,r.id) from (
      select c.id,(c.created_at at time zone g.timezone)::date as date,
        m.full_name as member_name,c.amount_minor,c.currency,
        case when c.amount_minor>0 then 'Credit issued' else 'Credit used' end as kind
      from public.member_credit_ledger c join public.members m on m.gym_id=c.gym_id and m.id=c.member_id
      where c.gym_id=p_gym and c.created_at>=first_instant and c.created_at<next_instant
    ) r),'[]'::jsonb)
  ) into result;
  return result;
end $$;
revoke all on function public.get_period_report(uuid,integer,integer) from public,anon;
grant execute on function public.get_period_report(uuid,integer,integer) to authenticated;
