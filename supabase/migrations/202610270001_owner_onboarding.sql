-- A verified account may explicitly create its own new tenant, never join or
-- promote itself within an existing tenant. Serialize retries per account.
create function public.create_own_gym(p_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare owner_id uuid=auth.uid(); existing public.gym_users; gym uuid;
begin
  if owner_id is null or not exists(select 1 from auth.users where id=owner_id and email_confirmed_at is not null) then
    raise insufficient_privilege using message='Confirm your email before setting up a gym';
  end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>120 then
    raise exception 'Enter a gym name between 1 and 120 characters';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('gym-onboarding:'||owner_id::text,0));
  select * into existing from public.gym_users where user_id=owner_id order by created_at,id limit 1;
  if found then
    if existing.active and existing.role='owner' then return existing.gym_id; end if;
    raise insufficient_privilege using message='Your account already has gym membership. Contact your gym administrator to restore access.';
  end if;
  gym=public.bootstrap_gym(owner_id,trim(p_name));
  return gym;
end $$;
revoke all on function public.create_own_gym(text) from public,anon;
grant execute on function public.create_own_gym(text) to authenticated;
