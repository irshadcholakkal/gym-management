create function public.attach_invited_employee(p_gym uuid,p_actor uuid,p_user uuid,p_name text,p_email text,p_role public.gym_role,p_phone text,p_designation text)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.gym_users where gym_id=p_gym and user_id=p_actor and active and role in ('owner','admin')) or p_role='owner' then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  insert into public.gym_users(gym_id,user_id,role) values(p_gym,p_user,p_role);
  insert into public.employees(gym_id,user_id,full_name,email,phone,designation) values(p_gym,p_user,p_name,p_email,p_phone,p_designation);
  insert into public.audit_logs(gym_id,actor_id,action,record_id,after_data) values(p_gym,p_actor,'employee:invite',p_user,jsonb_build_object('role',p_role));
end $$;
revoke all on function public.attach_invited_employee(uuid,uuid,uuid,text,text,public.gym_role,text,text) from public,anon,authenticated;
grant execute on function public.attach_invited_employee(uuid,uuid,uuid,text,text,public.gym_role,text,text) to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('gym-profiles','gym-profiles',false,5242880,array['image/png','image/jpeg','image/webp']) on conflict(id) do nothing;
create policy profile_read on storage.objects for select to authenticated using(bucket_id='gym-profiles' and exists(select 1 from public.gym_users where gym_id::text=(storage.foldername(name))[1] and user_id=auth.uid() and active and role in ('owner','admin','manager','receptionist')));
create policy profile_upload on storage.objects for insert to authenticated with check(bucket_id='gym-profiles' and exists(select 1 from public.gym_users where gym_id::text=(storage.foldername(name))[1] and user_id=auth.uid() and active and role in ('owner','admin','manager','receptionist')));
