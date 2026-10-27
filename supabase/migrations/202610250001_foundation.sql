create extension if not exists btree_gist;
create schema if not exists private;
revoke all on schema private from public;

create type public.gym_role as enum ('owner','admin','manager','trainer','receptionist','staff');
create table public.gyms (
  id uuid primary key default gen_random_uuid(), name text not null check(length(name)>0),
  currency text not null default 'AED' check(currency ~ '^[A-Z]{3}$'), timezone text not null default 'Asia/Dubai',
  address text not null default '', phone text not null default '', logo_path text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1
);
create table public.gym_branches (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1, unique(gym_id,id)
);
create table public.user_profiles (
  id uuid primary key references auth.users(id), full_name text not null, avatar_path text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.gym_users (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id),
  user_id uuid not null references auth.users(id), role public.gym_role not null, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1,
  unique(gym_id,user_id)
);
create function private.has_role(p_gym uuid, p_roles public.gym_role[] default null) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.gym_users where gym_id=p_gym and user_id=auth.uid() and active and (p_roles is null or role=any(p_roles)))
$$;
create function public.can_administer(p_gym uuid) returns boolean language sql stable security definer set search_path='' as $$
  select private.has_role(p_gym,array['owner','admin']::public.gym_role[])
$$;
create table public.role_permissions (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), role public.gym_role not null,
  permission text not null, allowed boolean not null default false, unique(gym_id,role,permission)
);
create table public.employees (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), branch_id uuid,
  user_id uuid not null references auth.users(id), full_name text not null, email text not null, phone text not null default '',
  address text not null default '', designation text not null default '', profile_image text, joining_date date not null default current_date,
  status text not null default 'active' check(status in ('active','inactive','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1,
  unique(gym_id,id), unique(gym_id,user_id), foreign key(gym_id,branch_id) references public.gym_branches(gym_id,id)
);
create table public.members (
  id uuid primary key, gym_id uuid not null references public.gyms(id), branch_id uuid,
  member_number bigint generated always as identity,
  full_name text not null check(length(trim(full_name))>0), phone text not null check(phone ~ '^\+[1-9][0-9]{7,14}$'),
  whatsapp text, email text not null default '', gender text, date_of_birth date, address text not null default '', profile_image text,
  emergency_contact_name text, emergency_contact_phone text, joining_date date not null, assigned_trainer uuid,
  notes text not null default '', status text not null default 'active' check(status in ('active','inactive','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1, actor_id uuid references auth.users(id),
  unique(gym_id,id), foreign key(gym_id,branch_id) references public.gym_branches(gym_id,id), foreign key(gym_id,assigned_trainer) references public.employees(gym_id,id)
);
create table public.membership_packages (
  id uuid primary key, gym_id uuid not null references public.gyms(id), branch_id uuid,
  name text not null check(length(trim(name))>0), description text not null default '', duration_value int not null check(duration_value>0),
  duration_unit text not null check(duration_unit in ('days','weeks','months','years')), price_minor bigint not null check(price_minor>=0),
  currency text not null default 'AED' check(currency ~ '^[A-Z]{3}$'), enrollment_fee_minor bigint not null default 0 check(enrollment_fee_minor>=0),
  tax_basis_points int not null default 0 check(tax_basis_points between 0 and 10000), allowed_pause_days int not null default 0 check(allowed_pause_days>=0),
  status text not null default 'active' check(status in ('active','inactive','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1, actor_id uuid references auth.users(id),
  unique(gym_id,id), foreign key(gym_id,branch_id) references public.gym_branches(gym_id,id)
);
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), branch_id uuid,
  member_id uuid not null, package_id uuid not null, package_snapshot jsonb not null,
  start_date date not null, original_end_exclusive date not null, end_exclusive date not null,
  status text not null check(status in ('draft','pending_activation','active','paused','expired','cancelled','scheduled_renewal')),
  pause_allowance int not null check(pause_allowance>=0), extension_days int not null default 0 check(extension_days>=0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1, actor_id uuid references auth.users(id),
  unique(gym_id,id), foreign key(gym_id,member_id) references public.members(gym_id,id), foreign key(gym_id,package_id) references public.membership_packages(gym_id,id),
  foreign key(gym_id,branch_id) references public.gym_branches(gym_id,id), check(end_exclusive>start_date),
  exclude using gist(gym_id with =, member_id with =, daterange(start_date,end_exclusive,'[)') with &&)
    where(status in ('active','paused','pending_activation','scheduled_renewal'))
);
create table public.subscription_pauses (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), subscription_id uuid not null,
  start_date date not null, resume_date date, intended_resume_date date, reason text not null check(length(trim(reason))>0),
  actor_id uuid not null references auth.users(id), resumed_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1,
  foreign key(gym_id,subscription_id) references public.subscriptions(gym_id,id), check(resume_date is null or resume_date>=start_date),
  exclude using gist(subscription_id with =, daterange(start_date,resume_date,'[)') with &&)
);
create table public.subscription_plan_changes (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), subscription_id uuid not null,
  old_package_id uuid not null, new_package_id uuid not null, effective_date date not null, adjustment_minor bigint not null,
  reason text not null, actor_id uuid not null references auth.users(id), created_at timestamptz not null default now(),
  foreign key(gym_id,subscription_id) references public.subscriptions(gym_id,id), foreign key(gym_id,old_package_id) references public.membership_packages(gym_id,id), foreign key(gym_id,new_package_id) references public.membership_packages(gym_id,id)
);
create table public.invoices (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), member_id uuid not null, subscription_id uuid,
  currency text not null check(currency ~ '^[A-Z]{3}$'), total_minor bigint not null check(total_minor>=0), paid_minor bigint not null default 0 check(paid_minor>=0),
  tax_minor bigint not null default 0, credit_minor bigint not null default 0 check(credit_minor>=0), due_date date not null, status text not null default 'unpaid' check(status in ('unpaid','partially_paid','paid','overdue','voided')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1, actor_id uuid references auth.users(id),
  unique(gym_id,id), foreign key(gym_id,member_id) references public.members(gym_id,id), foreign key(gym_id,subscription_id) references public.subscriptions(gym_id,id), check(paid_minor+credit_minor<=total_minor)
);
create table public.invoice_items (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), invoice_id uuid not null,
  description text not null, amount_minor bigint not null, tax_minor bigint not null default 0,
  created_at timestamptz not null default now(), foreign key(gym_id,invoice_id) references public.invoices(gym_id,id)
);
create table public.payments (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), member_id uuid not null,
  amount_minor bigint not null check(amount_minor>0), currency text not null, method text not null check(method in ('cash','bank_transfer','credit_card','debit_card','cheque','online','other')),
  reference text not null default '', idempotency_key uuid not null, actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1,
  unique(gym_id,id), unique(gym_id,idempotency_key), foreign key(gym_id,member_id) references public.members(gym_id,id)
);
create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), payment_id uuid not null, invoice_id uuid not null,
  amount_minor bigint not null check(amount_minor>0), created_at timestamptz not null default now(), version bigint not null default 1,
  foreign key(gym_id,payment_id) references public.payments(gym_id,id), foreign key(gym_id,invoice_id) references public.invoices(gym_id,id), unique(payment_id,invoice_id)
);
create table public.credit_adjustments (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), invoice_id uuid not null,
  amount_minor bigint not null, reason text not null check(length(trim(reason))>0), actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(), version bigint not null default 1, foreign key(gym_id,invoice_id) references public.invoices(gym_id,id)
);
create table public.receipts (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), payment_id uuid not null,
  receipt_number bigint generated always as identity, snapshot jsonb not null, status text not null default 'issued' check(status in ('issued','voided')), created_at timestamptz not null default now(), version bigint not null default 1,
  foreign key(gym_id,payment_id) references public.payments(gym_id,id), unique(gym_id,payment_id), unique(receipt_number)
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), recipient_id uuid not null references auth.users(id),
  subscription_id uuid, expiry_date date, expiry_version bigint, type text not null, title text not null, body text not null,
  read_at timestamptz, superseded_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1,
  foreign key(gym_id,subscription_id) references public.subscriptions(gym_id,id), unique(subscription_id,expiry_date,expiry_version,type,recipient_id)
);
create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), user_id uuid not null references auth.users(id),
  endpoint text not null check(endpoint like 'https://%'), keys jsonb not null, enabled boolean not null default true,
  created_at timestamptz not null default now(), unique(gym_id,user_id,endpoint)
);
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), actor_id uuid references auth.users(id),
  action text not null, record_id uuid not null, before_data jsonb, after_data jsonb, created_at timestamptz not null default now()
);
create table public.gym_settings (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null unique references public.gyms(id),
  allow_offline_unlock boolean not null default false, allow_prorating boolean not null default true,
  reminder_days int[] not null default array[7], created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version bigint not null default 1
);
-- Software billing is independent of member invoices.
create table public.software_billing (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id), provider_reference text,
  status text not null default 'trial', period_end timestamptz, created_at timestamptz not null default now()
);
create table public.tenant_change_log (
  cursor bigint generated always as identity primary key, gym_id uuid not null references public.gyms(id),
  kind text not null, record_id uuid not null, payload jsonb not null, created_at timestamptz not null default now()
);
create index changes_tenant_cursor on public.tenant_change_log(gym_id,cursor);
create table public.sync_operation_receipts (
  id uuid primary key, gym_id uuid not null references public.gyms(id), user_id uuid not null references auth.users(id),
  request jsonb not null, result jsonb not null, created_at timestamptz not null default now()
);

-- All application writes pass through checked RPCs. No client table writes.
do $$ declare t text; begin
  foreach t in array array['gyms','gym_branches','gym_users','role_permissions','employees','members','membership_packages','subscriptions','subscription_pauses','subscription_plan_changes','invoices','invoice_items','payments','payment_allocations','credit_adjustments','receipts','notifications','push_subscriptions','audit_logs','gym_settings','tenant_change_log','sync_operation_receipts','software_billing'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    if t not in ('gyms','gym_users') then execute format('create index on public.%I(gym_id)',t); end if;
  end loop;
end $$;
alter table public.user_profiles enable row level security;
revoke all on public.user_profiles from anon,authenticated;
grant select on public.user_profiles to authenticated;
create policy own_profile on public.user_profiles for select to authenticated using(id=auth.uid());
create policy tenant_gyms on public.gyms for select to authenticated using(private.has_role(id));
create policy own_membership on public.gym_users for select to authenticated using(user_id=auth.uid() or public.can_administer(gym_id));
create policy member_visibility on public.members for select to authenticated using (
  private.has_role(gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]) or
  (private.has_role(gym_id,array['trainer']::public.gym_role[]) and exists(select 1 from public.employees e where e.gym_id=members.gym_id and e.id=members.assigned_trainer and e.user_id=auth.uid() and e.status='active'))
);
create policy employee_visibility on public.employees for select to authenticated using(user_id=auth.uid() or public.can_administer(gym_id));
create policy packages_visibility on public.membership_packages for select to authenticated using(private.has_role(gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]));
create policy subscription_visibility on public.subscriptions for select to authenticated using(private.has_role(gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]));
do $$ declare t text; begin
  foreach t in array array['invoices','invoice_items','payments','payment_allocations','credit_adjustments','receipts'] loop
    execute format('create policy finance_visibility on public.%I for select to authenticated using(private.has_role(gym_id,array[''owner'',''admin'',''manager'',''receptionist'']::public.gym_role[]))',t);
  end loop;
  foreach t in array array['gym_branches','role_permissions','audit_logs','gym_settings','software_billing'] loop
    execute format('create policy admin_visibility on public.%I for select to authenticated using(public.can_administer(gym_id))',t);
  end loop;
end $$;
create policy pauses_visibility on public.subscription_pauses for select to authenticated using(exists(select 1 from public.subscriptions s where s.gym_id=subscription_pauses.gym_id and s.id=subscription_pauses.subscription_id));
create policy plan_change_visibility on public.subscription_plan_changes for select to authenticated using(private.has_role(gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]));
create policy own_notifications on public.notifications for select to authenticated using(recipient_id=auth.uid() and private.has_role(gym_id));
create policy own_push on public.push_subscriptions for select to authenticated using(user_id=auth.uid() and private.has_role(gym_id));
grant usage on schema private to authenticated;
grant execute on function private.has_role(uuid,public.gym_role[]) to authenticated;

create function private.log_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.tenant_change_log(gym_id,kind,record_id,payload) values(new.gym_id,tg_table_name,new.id,to_jsonb(new));
  insert into public.audit_logs(gym_id,actor_id,action,record_id,before_data,after_data)
    values(new.gym_id,auth.uid(),tg_table_name||':'||tg_op,new.id,case when tg_op='UPDATE' then to_jsonb(old) end,to_jsonb(new));
  perform realtime.send(jsonb_build_object('invalidate',true),'changed','gym:'||new.gym_id::text,true);
  return new;
end $$;
do $$ declare t text; begin
  foreach t in array array['employees','members','membership_packages','subscriptions','subscription_pauses','invoices','payments','payment_allocations','credit_adjustments','receipts','notifications'] loop
    execute format('create trigger record_change after insert or update on public.%I for each row execute function private.log_change()',t);
  end loop;
end $$;
create policy private_tenant_channel on realtime.messages for select to authenticated using (
  extension='broadcast' and exists(select 1 from public.gym_users gu where gu.user_id=auth.uid() and gu.active and realtime.topic()='gym:'||gu.gym_id::text)
);
-- Serialize every tenant mutation before any identity cursor is allocated, so
-- cursor order equals commit order. Future write RPCs must acquire this lock.
create function private.lock_gym(p_gym uuid) returns void language plpgsql set search_path='' as $$
begin perform pg_advisory_xact_lock(hashtextextended(p_gym::text,0)); end $$;

create function public.apply_sync_operation(p_gym uuid,p_operation uuid,p_kind text,p_id uuid,p_expected bigint,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous public.sync_operation_receipts; result jsonb; current_version bigint; request jsonb;
begin
  if not private.has_role(p_gym,array['owner','admin','manager','receptionist']::public.gym_role[]) then raise insufficient_privilege; end if;
  if p_kind not in ('members','membership_packages') then raise exception 'Unsupported operation'; end if;
  if p_kind='membership_packages' and not public.can_administer(p_gym) then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  request=jsonb_build_object('kind',p_kind,'id',p_id,'expected',p_expected,'data',p_data);
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  execute format('select version from public.%I where gym_id=$1 and id=$2 for update',p_kind) into current_version using p_gym,p_id;
  if coalesce(current_version,0)<>p_expected then raise exception using errcode='40001',message='This record changed on another device. Review before retrying.'; end if;
  if p_kind='members' then
    insert into public.members(id,gym_id,full_name,phone,email,address,notes,status,joining_date,actor_id)
    values(p_id,p_gym,trim(p_data->>'full_name'),p_data->>'phone',lower(trim(coalesce(p_data->>'email',''))),coalesce(p_data->>'address',''),coalesce(p_data->>'notes',''),p_data->>'status',(p_data->>'joining_date')::date,auth.uid())
    on conflict(id) do update set full_name=excluded.full_name,phone=excluded.phone,email=excluded.email,address=excluded.address,notes=excluded.notes,status=excluded.status,updated_at=now(),version=members.version+1,actor_id=auth.uid()
    where members.gym_id=p_gym returning to_jsonb(members.*) into result;
  else
    insert into public.membership_packages(id,gym_id,name,description,duration_value,duration_unit,price_minor,currency,allowed_pause_days,status,actor_id)
    values(p_id,p_gym,trim(p_data->>'name'),coalesce(p_data->>'description',''),(p_data->>'duration_value')::int,p_data->>'duration_unit',(p_data->>'price_minor')::bigint,p_data->>'currency',(p_data->>'allowed_pause_days')::int,p_data->>'status',auth.uid())
    on conflict(id) do update set name=excluded.name,description=excluded.description,duration_value=excluded.duration_value,duration_unit=excluded.duration_unit,price_minor=excluded.price_minor,currency=excluded.currency,allowed_pause_days=excluded.allowed_pause_days,status=excluded.status,updated_at=now(),version=membership_packages.version+1,actor_id=auth.uid()
    where membership_packages.gym_id=p_gym returning to_jsonb(membership_packages.*) into result;
  end if;
  if result is null then raise insufficient_privilege; end if;
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,result);
  return result;
end $$;

-- SECURITY INVOKER views the current row through RLS, never historical payloads
-- which could disclose a member after a trainer reassignment.
create function public.pull_changes(p_gym uuid,p_cursor bigint default 0) returns jsonb language plpgsql security invoker set search_path='' as $$
declare batch jsonb; last_cursor bigint; more boolean;
begin
  if not private.has_role(p_gym) then raise insufficient_privilege; end if;
  return private.pull_authorized_changes(p_gym,p_cursor);
end $$;
create function private.pull_authorized_changes(p_gym uuid,p_cursor bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare changes jsonb='[]'; row record; payload jsonb; last_cursor bigint=p_cursor; n int=0;
begin
  if not private.has_role(p_gym) then raise insufficient_privilege; end if;
  for row in select * from public.tenant_change_log where gym_id=p_gym and cursor>p_cursor order by cursor limit 250 loop
    last_cursor=row.cursor; n=n+1; payload=null;
    if row.kind='members' and (private.has_role(p_gym,array['owner','admin','manager','receptionist']::public.gym_role[]) or private.has_role(p_gym,array['trainer']::public.gym_role[]) and exists(select 1 from public.members m join public.employees e on e.id=m.assigned_trainer and e.gym_id=m.gym_id where m.id=row.record_id and m.gym_id=p_gym and e.user_id=auth.uid() and e.status='active')) then
      select to_jsonb(m.*) into payload from public.members m where m.gym_id=p_gym and m.id=row.record_id;
    elsif row.kind='membership_packages' and private.has_role(p_gym,array['owner','admin','manager','receptionist']::public.gym_role[]) then
      select to_jsonb(p.*) into payload from public.membership_packages p where p.gym_id=p_gym and p.id=row.record_id;
    elsif row.kind in ('subscriptions','subscription_pauses','invoices','payments','payment_allocations','credit_adjustments','receipts','payment_reversals') and private.has_role(p_gym,array['owner','admin','manager','receptionist']::public.gym_role[]) then
      execute format('select to_jsonb(t.*) from public.%I t where t.gym_id=$1 and t.id=$2',row.kind) into payload using p_gym,row.record_id;
    elsif row.kind='employees' and public.can_administer(p_gym) then
      select to_jsonb(e.*) into payload from public.employees e where e.gym_id=p_gym and e.id=row.record_id;
    elsif row.kind='notifications' then
      select to_jsonb(no.*) into payload from public.notifications no where no.gym_id=p_gym and no.id=row.record_id and no.recipient_id=auth.uid();
    end if;
    if row.kind='subscriptions' and private.has_role(p_gym,array['trainer']::public.gym_role[]) then
      select (to_jsonb(s.*)-'package_snapshot')||jsonb_build_object('package_snapshot',jsonb_build_object('name',s.package_snapshot->>'name')) into payload
      from public.subscriptions s join public.members m on m.id=s.member_id and m.gym_id=s.gym_id
      join public.employees e on e.id=m.assigned_trainer and e.gym_id=m.gym_id
      where s.gym_id=p_gym and s.id=row.record_id and e.user_id=auth.uid() and e.status='active';
    end if;
    if row.kind='members' and payload is null then
      changes=changes||jsonb_build_array(jsonb_build_object('kind','members','record_id',row.record_id,'deleted',true));
      changes=changes||coalesce((select jsonb_agg(jsonb_build_object('kind','subscriptions','record_id',s.id,'deleted',true)) from public.subscriptions s where s.gym_id=p_gym and s.member_id=row.record_id),'[]');
    end if;
    if payload is not null then changes=changes||jsonb_build_array(jsonb_build_object('kind',row.kind,'record_id',row.record_id,'payload',payload)); end if;
  end loop;
  return jsonb_build_object('changes',changes,'cursor',last_cursor,'has_more',n=250);
end $$;
grant execute on function private.pull_authorized_changes(uuid,bigint) to authenticated;

-- Remove PostgreSQL's default PUBLIC EXECUTE from privileged entry points.
revoke all on all functions in schema private from public,anon;
revoke all on function public.apply_sync_operation(uuid,uuid,text,uuid,bigint,jsonb),public.pull_changes(uuid,bigint),public.can_administer(uuid) from public,anon;
grant execute on function public.apply_sync_operation(uuid,uuid,text,uuid,bigint,jsonb),public.pull_changes(uuid,bigint),public.can_administer(uuid) to authenticated;
