create function public.bootstrap_gym(p_owner uuid,p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare gym uuid;
begin
  if nullif(trim(p_name),'') is null then raise exception 'Gym name is required'; end if;
  if not exists(select 1 from auth.users where id=p_owner) then raise exception 'Create the owner Auth account first'; end if;
  insert into public.gyms(name) values(trim(p_name)) returning id into gym;
  perform private.lock_gym(gym);
  insert into public.gym_users(gym_id,user_id,role) values(gym,p_owner,'owner');
  insert into public.gym_settings(gym_id) values(gym);
  insert into public.audit_logs(gym_id,actor_id,action,record_id) values(gym,p_owner,'gym:bootstrap',gym);
  return gym;
end $$;
revoke all on function public.bootstrap_gym(uuid,text) from public,anon,authenticated;
grant execute on function public.bootstrap_gym(uuid,text) to service_role;
