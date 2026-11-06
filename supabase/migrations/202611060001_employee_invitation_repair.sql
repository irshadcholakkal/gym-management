-- Only the invitation service may resolve an orphaned invited account.
-- The gym administrator must explicitly supply the role again when retrying.
create function public.find_invited_employee(p_gym uuid,p_actor uuid,p_email text)
returns uuid language plpgsql security definer set search_path='' as $$
declare invited uuid;
begin
  if not exists(select 1 from public.gym_users where gym_id=p_gym and user_id=p_actor and active
    and role in ('owner','admin') and (role='owner' or coalesce((access_options->>'administration')::boolean,true))) then
    raise insufficient_privilege;
  end if;
  select u.id into invited from auth.users u
  where lower(u.email)=lower(trim(p_email)) and u.invited_at is not null
    and not exists(select 1 from public.gym_users g where g.gym_id=p_gym and g.user_id=u.id)
  order by u.created_at limit 1;
  return invited;
end $$;
revoke all on function public.find_invited_employee(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.find_invited_employee(uuid,uuid,text) to service_role;

-- Invited employees with a failed assignment must never create a new tenant.
create or replace function public.create_own_gym(p_name text) returns uuid
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
  if exists(select 1 from auth.users where id=owner_id and invited_at is not null) then
    raise insufficient_privilege using message='Your employee invitation is waiting for gym access. Ask your gym administrator to add your email in Team again.';
  end if;
  gym=public.bootstrap_gym(owner_id,trim(p_name));
  return gym;
end $$;
