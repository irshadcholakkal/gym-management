-- Server-generated alerts work even when the PWA is closed.
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
      from public.subscriptions s where s.gym_id=g.id and n.gym_id=g.id and n.subscription_id=s.id
      and n.superseded_at is null and n.type in ('expiry_7','expiry_3','expiry_1','expiry_0','expired')
      and (n.expiry_date<>s.end_exclusive-1 or s.status not in ('active','expired')
        or (n.type<>'expired' and s.end_exclusive<=today)
        or exists(select 1 from public.subscriptions renewed where renewed.gym_id=s.gym_id
          and renewed.member_id=s.member_id and renewed.id<>s.id and renewed.status in ('active','scheduled_renewal')
          and renewed.start_date>=s.end_exclusive and renewed.end_exclusive>s.end_exclusive));
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

-- Include only routing IDs and category in push jobs; member data stays in the authenticated app.
create or replace function public.claim_push_deliveries() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  insert into public.notification_deliveries(gym_id,notification_id,push_subscription_id)
  select n.gym_id,n.id,p.id from public.notifications n
    join public.push_subscriptions p on p.gym_id=n.gym_id and p.user_id=n.recipient_id and p.enabled
    join public.gym_users gu on gu.gym_id=n.gym_id and gu.user_id=n.recipient_id and gu.active
    where n.superseded_at is null and n.read_at is null and n.created_at>now()-interval '1 day'
    on conflict do nothing;
  update public.notification_deliveries d set state='cancelled' where state in ('pending','sending')
    and exists(select 1 from public.notifications n where n.id=d.notification_id and (n.superseded_at is not null or n.read_at is not null));
  with candidates as (
    select d.id from public.notification_deliveries d
      join public.push_subscriptions p on p.id=d.push_subscription_id and p.enabled
      join public.notifications n on n.id=d.notification_id and n.superseded_at is null and n.read_at is null
      join public.gym_users gu on gu.gym_id=n.gym_id and gu.user_id=n.recipient_id and gu.active
    where d.attempts<8 and d.next_attempt<=now() and (d.state='pending' or d.state='sending' and d.locked_until<now())
    order by d.created_at limit 50 for update of d skip locked
  ), claimed as (
    update public.notification_deliveries d set state='sending',attempts=attempts+1,locked_until=now()+interval '2 minutes'
    from candidates c where d.id=c.id returning d.*
  ) select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'attempt',c.attempts,
      'notification_id',n.id,'gym_id',n.gym_id,'type',n.type,
      'subscription',jsonb_build_object('endpoint',p.endpoint,'keys',p.keys))),'[]') into result
    from claimed c join public.push_subscriptions p on p.id=c.push_subscription_id
    join public.notifications n on n.id=c.notification_id;
  return result;
end $$;
revoke all on function public.process_expiry_reminders(),public.claim_push_deliveries() from public,anon,authenticated;
grant execute on function public.process_expiry_reminders(),public.claim_push_deliveries() to service_role;
