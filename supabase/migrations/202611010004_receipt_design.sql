-- Optional receipt presentation; finalized financial snapshots remain immutable.
create table public.receipt_designs (
  gym_id uuid primary key references public.gyms(id),
  html text not null check(length(html) between 1 and 100000),
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);
alter table public.receipt_designs enable row level security;
create policy receipt_design_read on public.receipt_designs for select to authenticated using(
  public.can_administer(gym_id) or private.has_role(gym_id,array['owner','admin','manager','receptionist']::public.gym_role[])
);
grant select on public.receipt_designs to authenticated;
create function public.save_receipt_design(p_gym uuid,p_html text,p_expected bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare existing public.receipt_designs; result public.receipt_designs;
begin
  if not public.can_administer(p_gym) then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  if p_html is null or length(trim(p_html))=0 or length(p_html)>100000 then raise exception 'Receipt HTML must contain 1 to 100000 characters'; end if;
  select * into existing from public.receipt_designs where gym_id=p_gym;
  if coalesce(existing.version,0)<>p_expected then raise sqlstate '40001' using message='Receipt design changed. Reload before saving.'; end if;
  insert into public.receipt_designs(gym_id,html) values(p_gym,p_html)
  on conflict(gym_id) do update set html=excluded.html,version=receipt_designs.version+1,updated_at=now()
  returning * into result;
  insert into public.audit_logs(gym_id,actor_id,action,record_id,after_data) values(p_gym,auth.uid(),'receipt:design',p_gym,jsonb_build_object('version',result.version));
  return to_jsonb(result);
end $$;
revoke all on function public.save_receipt_design(uuid,text,bigint) from public,anon;
grant execute on function public.save_receipt_design(uuid,text,bigint) to authenticated;
