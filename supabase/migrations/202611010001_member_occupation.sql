-- Optional occupation for existing and new members.
alter table public.members add column occupation text not null default '';

-- Keep tenant locking, permissions, version checks, and idempotent retries unchanged.
-- Older clients omitting occupation preserve the existing value on updates.
create or replace function public.apply_sync_operation(p_gym uuid,p_operation uuid,p_kind text,p_id uuid,p_expected bigint,p_data jsonb)
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
    insert into public.members(id,gym_id,full_name,phone,email,occupation,address,notes,status,joining_date,actor_id)
    values(p_id,p_gym,trim(p_data->>'full_name'),p_data->>'phone',lower(trim(coalesce(p_data->>'email',''))),trim(coalesce(p_data->>'occupation','')),coalesce(p_data->>'address',''),coalesce(p_data->>'notes',''),p_data->>'status',(p_data->>'joining_date')::date,auth.uid())
    on conflict(id) do update set full_name=excluded.full_name,phone=excluded.phone,email=excluded.email,occupation=case when p_data ? 'occupation' then excluded.occupation else members.occupation end,address=excluded.address,notes=excluded.notes,status=excluded.status,updated_at=now(),version=members.version+1,actor_id=auth.uid()
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
