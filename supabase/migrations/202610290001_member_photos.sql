insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('member-photos','member-photos',false,153600,array['image/jpeg']);

create policy member_photo_read on storage.objects for select to authenticated using (
  bucket_id='member-photos' and exists(select 1 from public.members m
    where m.gym_id::text=(storage.foldername(name))[1] and m.id::text=(storage.foldername(name))[2])
);
create policy member_photo_upload on storage.objects for insert to authenticated with check (
  bucket_id='member-photos' and (storage.foldername(name))[3]=auth.uid()::text
  and exists(select 1 from public.members m where m.gym_id::text=(storage.foldername(name))[1]
    and m.id::text=(storage.foldername(name))[2]
    and private.has_role(m.gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]))
);
create policy member_photo_delete on storage.objects for delete to authenticated using (
  bucket_id='member-photos' and exists(select 1 from public.members m
    where m.gym_id::text=(storage.foldername(name))[1] and m.id::text=(storage.foldername(name))[2]
    and private.has_role(m.gym_id,array['owner','admin','manager','receptionist']::public.gym_role[]))
  and not exists(select 1 from public.members m where m.profile_image=name)
);

create function public.set_member_photo(p_gym uuid,p_member uuid,p_expected integer,p_path text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.members; previous public.sync_operation_receipts; request_data jsonb; result_data jsonb;
begin
  perform private.require_finance(p_gym);
  request_data=jsonb_build_object('member_photo',p_member,'path',p_path,'expected',p_expected);
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request_data then
      raise exception 'Operation ID reused with different details';
    end if;
    return previous.result;
  end if;
  if p_path is null or split_part(p_path,'/',1)<>p_gym::text or split_part(p_path,'/',2)<>p_member::text
    or split_part(p_path,'/',3)<>auth.uid()::text or not exists(
      select 1 from storage.objects o where o.bucket_id='member-photos' and o.name=p_path
      and o.owner_id=auth.uid()::text and o.metadata->>'mimetype'='image/jpeg'
      and (o.metadata->>'size')::bigint between 1 and 153600
    ) then raise exception 'Invalid member photo upload'; end if;
  update public.members set profile_image=p_path,version=version+1,updated_at=now(),actor_id=auth.uid()
    where gym_id=p_gym and id=p_member and version=p_expected returning * into m;
  if not found then raise exception 'Member changed. Sync and retry your photo.' using errcode='40001'; end if;
  result_data=to_jsonb(m);
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result)
    values(p_operation,p_gym,auth.uid(),request_data,result_data);
  return result_data;
end $$;
revoke all on function public.set_member_photo(uuid,uuid,integer,text,uuid) from public,anon;
grant execute on function public.set_member_photo(uuid,uuid,integer,text,uuid) to authenticated;
