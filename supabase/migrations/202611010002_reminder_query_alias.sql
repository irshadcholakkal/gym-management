-- Avoid a SQL alias colliding with the unassigned PL/pgSQL loop record.
create or replace function public.process_expiry_reminders() returns int
language plpgsql security definer set search_path='' as $$
declare g record; s record; today date; expiry date; remaining int;
  alert_type text; alert_title text; alert_body text; count_created int=0; affected int;
begin
  for g in select * from public.gyms order by id loop
    perform private.lock_gym(g.id);
    today=(now() at time zone g.timezone)::date;
    update public.subscriptions set status='active',updated_at=now(),version=version+1
      where gym_id=g.id and status='scheduled_renewal' and start_date<=today and end_exclusive>today;
    update public.subscriptions set status='expired',updated_at=now(),version=version+1
      where gym_id=g.id and status='active' and end_exclusive<=today;
    -- Retire reminders when dates or membership states have changed.
    update public.notifications n set superseded_at=now(),updated_at=now(),version=n.version+1
      from public.subscriptions current_subscription where current_subscription.gym_id=g.id and n.gym_id=g.id and n.subscription_id=current_subscription.id
      and n.superseded_at is null and n.type in ('expiry_7','expiry_3','expiry_1','expiry_0','expired')
      and (n.expiry_date<>current_subscription.end_exclusive-1 or current_subscription.status not in ('active','expired')
        or (n.type<>'expired' and current_subscription.end_exclusive<=today)
        or exists(select 1 from public.subscriptions renewed where renewed.gym_id=current_subscription.gym_id
          and renewed.member_id=current_subscription.member_id and renewed.id<>current_subscription.id and renewed.status in ('active','scheduled_renewal')
          and renewed.start_date>=current_subscription.end_exclusive and renewed.end_exclusive>current_subscription.end_exclusive));
    for s in select * from public.subscriptions where gym_id=g.id
      and (status='active' or status='expired' and end_exclusive>=today-7)
      and not exists(select 1 from public.subscriptions renewed where renewed.gym_id=subscriptions.gym_id
        and renewed.member_id=subscriptions.member_id and renewed.id<>subscriptions.id
        and renewed.status in ('active','scheduled_renewal') and renewed.start_date>=subscriptions.end_exclusive
        and renewed.end_exclusive>subscriptions.end_exclusive) loop
      expiry=s.end_exclusive-1;
      remaining=expiry-today;
      alert_type=null;
      if s.status='expired' then
        alert_type='expired'; alert_title='Membership expired';
        alert_body='A membership has expired. Review the member and contact them about renewal.';
      elsif remaining in (7,3,1,0) then
        alert_type='expiry_'||remaining;
        alert_title=case when remaining=0 then 'Membership expires today' else 'Membership renewal reminder' end;
        alert_body=case when remaining=0 then 'Today is the last membership day. Open the membership to arrange renewal.'
          else 'A membership expires in '||remaining||' calendar days. Open the membership to arrange renewal.' end;
      end if;
      if alert_type is not null then
        insert into public.notifications(gym_id,recipient_id,subscription_id,expiry_date,expiry_version,type,title,body)
        select g.id,gu.user_id,s.id,expiry,s.version,alert_type,alert_title,alert_body
        from public.gym_users gu where gu.gym_id=g.id and gu.active
          and gu.role in ('owner','admin','manager','receptionist')
          and not exists(select 1 from public.notifications n where n.subscription_id=s.id
            and n.recipient_id=gu.user_id and n.expiry_date=expiry and n.type=alert_type and n.superseded_at is null)
        on conflict do nothing;
        get diagnostics affected=row_count;
        count_created=count_created+affected;
      end if;
    end loop;
  end loop;
  return count_created;
end $$;
