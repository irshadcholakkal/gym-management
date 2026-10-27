create function public.check_operation(p_gym uuid,p_operation uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
  if not private.has_role(p_gym) then raise insufficient_privilege; end if;
  return exists(select 1 from public.sync_operation_receipts where id=p_operation and gym_id=p_gym and user_id=auth.uid());
end $$;
revoke all on function public.check_operation(uuid,uuid) from public,anon;
grant execute on function public.check_operation(uuid,uuid) to authenticated;
