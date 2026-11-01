-- Per-employee restrictions can narrow, never expand, the chosen role.
alter table public.gym_users add column access_options jsonb not null default '{}'
  check (jsonb_typeof(access_options)='object');
alter table public.employees add column employee_number bigint generated always as identity;
alter table public.employees add column username text;
alter table public.employees add column access_role public.gym_role;
alter table public.employees add column access_options jsonb not null default '{}';
create unique index employee_number_unique on public.employees(employee_number);
create unique index employee_username_unique on public.employees(lower(username)) where username is not null;
alter table public.employees add constraint employee_username_format check(username is null or
  (username ~ '^[a-z][a-z0-9_.-]{2,31}$' and username not like 'emp-%'));
update public.employees e set access_role=g.role from public.gym_users g where g.gym_id=e.gym_id and g.user_id=e.user_id;

create or replace function private.has_role(p_gym uuid, p_roles public.gym_role[] default null) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.gym_users g where g.gym_id=p_gym and g.user_id=auth.uid() and g.active
    and (p_roles is null or g.role=any(p_roles))
    and (g.role='owner' or case
      when cardinality(p_roles)=2 and p_roles @> array['owner','admin']::public.gym_role[] then coalesce((g.access_options->>'administration')::boolean,true)
      when cardinality(p_roles)=3 and p_roles @> array['owner','admin','manager']::public.gym_role[] then coalesce((g.access_options->>'discounts')::boolean,true)
      when cardinality(p_roles)=4 and p_roles @> array['owner','admin','manager','receptionist']::public.gym_role[] then coalesce((g.access_options->>'operations')::boolean,true)
      else true end))
$$;

create function private.employee_access_mirror() returns trigger language plpgsql security definer set search_path='' as $$
begin
  update public.employees set access_role=new.role,access_options=new.access_options,version=version+1,updated_at=now()
  where gym_id=new.gym_id and user_id=new.user_id;
  return new;
end $$;
create trigger employee_access_mirror after update of role,access_options on public.gym_users
for each row execute function private.employee_access_mirror();
create function private.employee_initial_access() returns trigger language plpgsql security definer set search_path='' as $$
begin
  select role,access_options into new.access_role,new.access_options from public.gym_users where gym_id=new.gym_id and user_id=new.user_id;
  return new;
end $$;
create trigger employee_initial_access before insert on public.employees for each row execute function private.employee_initial_access();

create function public.set_employee_access(p_gym uuid,p_user uuid,p_role public.gym_role,p_username text,p_options jsonb default '{}')
returns void language plpgsql security definer set search_path='' as $$
declare normalized text=nullif(lower(trim(p_username)),'');
begin
  perform private.lock_gym(p_gym);
  if not public.can_administer(p_gym) or p_role='owner' then raise insufficient_privilege; end if;
  if exists(select 1 from public.gym_users where gym_id=p_gym and user_id=p_user and role='owner') then raise exception 'Owner access cannot be changed here'; end if;
  if jsonb_typeof(p_options) <> 'object' or p_options is null or exists(
    select 1 from jsonb_each(p_options) where key not in ('edit_members','operations','discounts','administration') or jsonb_typeof(value)<>'boolean'
  ) then raise exception 'Invalid access options'; end if;
  if normalized is not null and (normalized !~ '^[a-z][a-z0-9_.-]{2,31}$' or normalized like 'emp-%') then raise exception 'Username must be 3–32 characters, start with a letter, and cannot start with emp-'; end if;
  if not exists(select 1 from public.employees where gym_id=p_gym and user_id=p_user) then raise exception 'Employee not found'; end if;
  update public.gym_users set role=p_role,access_options=p_options,version=version+1,updated_at=now() where gym_id=p_gym and user_id=p_user;
  update public.employees set username=normalized,version=version+1,updated_at=now() where gym_id=p_gym and user_id=p_user;
  insert into public.audit_logs(gym_id,actor_id,action,record_id,after_data)
  values(p_gym,auth.uid(),'employee:access',p_user,jsonb_build_object('role',p_role,'username',normalized,'options',p_options));
end $$;
revoke all on function public.set_employee_access(uuid,uuid,public.gym_role,text,jsonb) from public,anon;
grant execute on function public.set_employee_access(uuid,uuid,public.gym_role,text,jsonb) to authenticated;

-- This guard also applies to writes through SECURITY DEFINER business RPCs.
create function private.guard_employee_member_edit() returns trigger language plpgsql security definer set search_path='' as $$
declare gym uuid;
begin
  gym=case when tg_op='DELETE' then old.gym_id else new.gym_id end;
  if exists(select 1 from public.gym_users where gym_id=gym and user_id=auth.uid() and role<>'owner'
    and coalesce((access_options->>'edit_members')::boolean,true)=false) then raise insufficient_privilege; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
create trigger guard_employee_member_edit before insert or update or delete on public.members
for each row execute function private.guard_employee_member_edit();

-- Alias resolution and throttling are server-only: never expose employee emails anonymously.
create function public.resolve_employee_login(p_identifier text) returns uuid language sql stable security definer set search_path='' as $$
  select e.user_id from public.employees e join public.gym_users g on g.gym_id=e.gym_id and g.user_id=e.user_id
  where e.status='active' and g.active and (lower(e.username)=lower(trim(p_identifier))
    or lower(trim(p_identifier))='emp-'||e.employee_number::text or e.id::text=lower(trim(p_identifier))) limit 1
$$;
create table private.employee_login_attempts (key text primary key,started_at timestamptz not null,attempts int not null);
create function public.allow_employee_login(p_key text) returns boolean language plpgsql security definer set search_path='' as $$
declare count int;
begin
  delete from private.employee_login_attempts where started_at<now()-interval '1 day';
  insert into private.employee_login_attempts values(p_key,now(),1) on conflict(key) do update
  set attempts=case when employee_login_attempts.started_at<now()-interval '15 minutes' then 1 else employee_login_attempts.attempts+1 end,
      started_at=case when employee_login_attempts.started_at<now()-interval '15 minutes' then now() else employee_login_attempts.started_at end
  returning attempts into count;
  return count<=10;
end $$;
revoke all on function public.resolve_employee_login(text),public.allow_employee_login(text) from public,anon,authenticated;
grant execute on function public.resolve_employee_login(text),public.allow_employee_login(text) to service_role;
revoke all on function private.employee_access_mirror(),private.employee_initial_access(),private.guard_employee_member_edit() from public,anon,authenticated;

-- Assign invitation permissions atomically with tenant attachment.
create function public.attach_invited_employee_access(p_gym uuid,p_actor uuid,p_user uuid,p_name text,p_email text,p_role public.gym_role,p_phone text,p_designation text,p_username text,p_options jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare normalized text=nullif(lower(trim(p_username)),'');
begin
  if not exists(select 1 from public.gym_users where gym_id=p_gym and user_id=p_actor and active and role in ('owner','admin')
    and (role='owner' or coalesce((access_options->>'administration')::boolean,true))) then raise insufficient_privilege; end if;
  if jsonb_typeof(p_options)<>'object' or p_options is null or exists(select 1 from jsonb_each(p_options)
    where key not in ('edit_members','operations','discounts','administration') or jsonb_typeof(value)<>'boolean') then raise exception 'Invalid access options'; end if;
  if normalized is not null and (normalized !~ '^[a-z][a-z0-9_.-]{2,31}$' or normalized like 'emp-%') then raise exception 'Invalid username'; end if;
  perform public.attach_invited_employee(p_gym,p_actor,p_user,p_name,p_email,p_role,p_phone,p_designation);
  update public.gym_users set access_options=p_options,version=version+1,updated_at=now() where gym_id=p_gym and user_id=p_user;
  update public.employees set username=normalized,version=version+1,updated_at=now() where gym_id=p_gym and user_id=p_user;
end $$;
revoke all on function public.attach_invited_employee_access(uuid,uuid,uuid,text,text,public.gym_role,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.attach_invited_employee_access(uuid,uuid,uuid,text,text,public.gym_role,text,text,text,jsonb) to service_role;
