create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id),
  notification_id uuid not null references public.notifications(id), push_subscription_id uuid not null references public.push_subscriptions(id),
  attempts int not null default 0, state text not null default 'pending' check(state in ('pending','sending','sent','failed','cancelled')),
  next_attempt timestamptz not null default now(), locked_until timestamptz, last_error text, delivered_at timestamptz,
  created_at timestamptz not null default now(), unique(notification_id,push_subscription_id)
);
alter table public.notification_deliveries enable row level security;
revoke all on public.notification_deliveries from public,anon,authenticated;
grant select on public.notification_deliveries to authenticated;
create policy delivery_admin_read on public.notification_deliveries for select to authenticated using(public.can_administer(gym_id));
create index notification_delivery_due on public.notification_deliveries(state,next_attempt);

create function public.register_push(p_gym uuid,p_endpoint text,p_keys jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
  if not private.has_role(p_gym) then raise insufficient_privilege; end if;
  if p_endpoint not like 'https://%' or length(p_endpoint)>4096 or not (p_keys ? 'p256dh' and p_keys ? 'auth') then raise exception 'Invalid push subscription'; end if;
  perform private.lock_gym(p_gym);
  insert into public.push_subscriptions(gym_id,user_id,endpoint,keys) values(p_gym,auth.uid(),p_endpoint,p_keys)
    on conflict(gym_id,user_id,endpoint) do update set keys=excluded.keys,enabled=true;
end $$;
create function public.remove_push(p_gym uuid,p_endpoint text) returns void language plpgsql security definer set search_path='' as $$
begin
  if not private.has_role(p_gym) then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  update public.push_subscriptions set enabled=false where gym_id=p_gym and user_id=auth.uid() and endpoint=p_endpoint;
end $$;

create function public.claim_push_deliveries() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  insert into public.notification_deliveries(gym_id,notification_id,push_subscription_id)
  select n.gym_id,n.id,p.id from public.notifications n join public.push_subscriptions p on p.gym_id=n.gym_id and p.user_id=n.recipient_id and p.enabled
  join public.gym_users gu on gu.gym_id=n.gym_id and gu.user_id=n.recipient_id and gu.active
  where n.superseded_at is null and n.created_at>now()-interval '1 day' on conflict do nothing;
  update public.notification_deliveries d set state='cancelled' where state in ('pending','sending') and exists(select 1 from public.notifications n where n.id=d.notification_id and n.superseded_at is not null);
  with candidates as (
    select d.id from public.notification_deliveries d
    join public.push_subscriptions p on p.id=d.push_subscription_id and p.enabled
    join public.notifications n on n.id=d.notification_id and n.superseded_at is null
    join public.gym_users gu on gu.gym_id=n.gym_id and gu.user_id=n.recipient_id and gu.active
    where d.attempts<8 and d.next_attempt<=now() and (d.state='pending' or d.state='sending' and d.locked_until<now())
    order by d.created_at limit 50 for update of d skip locked
  ), claimed as (
    update public.notification_deliveries d set state='sending',attempts=attempts+1,locked_until=now()+interval '2 minutes'
    from candidates c where d.id=c.id returning d.*
  ) select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'attempt',c.attempts,'subscription',jsonb_build_object('endpoint',p.endpoint,'keys',p.keys))),'[]') into result
  from claimed c join public.push_subscriptions p on p.id=c.push_subscription_id;
  return result;
end $$;
create function public.complete_push_delivery(p_id uuid,p_attempt int,p_success boolean,p_gone boolean,p_error text) returns void language plpgsql security definer set search_path='' as $$
begin
  update public.notification_deliveries set state=case when p_success then 'sent' when p_gone or attempts>=8 then 'failed' else 'pending' end,
    delivered_at=case when p_success then now() end,last_error=left(p_error,200),locked_until=null,
    next_attempt=now()+make_interval(secs=>least(3600,power(2,attempts)::int*30)) where id=p_id and attempts=p_attempt and state='sending';
  if p_gone then update public.push_subscriptions set enabled=false where id=(select push_subscription_id from public.notification_deliveries where id=p_id); end if;
end $$;
revoke all on function public.register_push(uuid,text,jsonb),public.remove_push(uuid,text) from public,anon;
grant execute on function public.register_push(uuid,text,jsonb),public.remove_push(uuid,text) to authenticated;
revoke all on function public.claim_push_deliveries(),public.complete_push_delivery(uuid,int,boolean,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_push_deliveries(),public.complete_push_delivery(uuid,int,boolean,boolean,text) to service_role;

do $$ begin
  if exists(select 1 from pg_available_extensions where name='pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('gympro-expiry-hourly','5 * * * *','select public.process_expiry_reminders()');
  end if;
end $$;
