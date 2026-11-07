-- Reversible removal for accidental, unused memberships. Financial history is retained.
alter table public.subscriptions add column deleted_at timestamptz;
alter table public.subscriptions add column deletion_state jsonb;
alter table public.invoices add column deleted_with_membership uuid;

create function public.set_membership_deleted(p_gym uuid,p_subscription uuid,p_expected bigint,p_delete boolean,p_reason text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.subscriptions; previous public.sync_operation_receipts; request jsonb; result jsonb; invoice_states jsonb;
begin
  if not public.can_administer(p_gym) then raise insufficient_privilege; end if;
  perform private.lock_gym(p_gym);
  request=jsonb_build_object('subscription',p_subscription,'expected',p_expected,'delete',p_delete,'reason',p_reason);
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  select * into strict s from public.subscriptions where gym_id=p_gym and id=p_subscription for update;
  if s.version<>p_expected then raise exception using errcode='40001',message='Membership changed. Refresh and try again.'; end if;
  if p_delete is null or nullif(trim(p_reason),'') is null then raise exception 'A reason is required'; end if;
  if exists(select 1 from public.payment_allocations a join public.invoices i on i.gym_id=a.gym_id and i.id=a.invoice_id
    where i.gym_id=p_gym and i.subscription_id=s.id)
    or exists(select 1 from public.invoices where gym_id=p_gym and subscription_id=s.id and (paid_minor>0 or credit_minor>0))
    or exists(select 1 from public.subscription_pauses where gym_id=p_gym and subscription_id=s.id)
    or exists(select 1 from public.subscription_plan_changes where gym_id=p_gym and subscription_id=s.id) then
    raise exception 'This membership has payment, credit or activity history. Use Cancel membership instead; payment history must be retained.';
  end if;
  if p_delete then
    if s.deleted_at is not null then raise exception 'Membership is already deleted'; end if;
    select coalesce(jsonb_object_agg(id::text,status),'{}') into invoice_states from public.invoices where gym_id=p_gym and subscription_id=s.id;
    update public.invoices set status='voided',deleted_with_membership=s.id,updated_at=now(),version=version+1
      where gym_id=p_gym and subscription_id=s.id;
    update public.subscriptions set status='cancelled',deleted_at=now(),
      deletion_state=jsonb_build_object('status',s.status,'invoices',invoice_states,'reason',trim(p_reason),'actor',auth.uid()),
      updated_at=now(),version=version+1,actor_id=auth.uid() where gym_id=p_gym and id=s.id returning to_jsonb(subscriptions.*) into result;
  else
    if s.deleted_at is null then raise exception 'Membership is not deleted'; end if;
    update public.subscriptions set status=s.deletion_state->>'status',deleted_at=null,deletion_state=null,
      updated_at=now(),version=version+1,actor_id=auth.uid() where gym_id=p_gym and id=s.id returning to_jsonb(subscriptions.*) into result;
    update public.invoices i set status=coalesce(s.deletion_state->'invoices'->>i.id::text,'unpaid'),deleted_with_membership=null,
      updated_at=now(),version=version+1 where i.gym_id=p_gym and i.deleted_with_membership=s.id;
  end if;
  update public.notifications set superseded_at=now(),updated_at=now(),version=version+1
    where gym_id=p_gym and subscription_id=s.id and superseded_at is null;
  insert into public.audit_logs(gym_id,actor_id,action,record_id,before_data,after_data)
    values(p_gym,auth.uid(),case when p_delete then 'subscription:delete' else 'subscription:restore' end,s.id,to_jsonb(s),
      jsonb_build_object('record',result,'reason',trim(p_reason)));
  result=jsonb_build_object('subscription',result);
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,result);
  return result;
end $$;
revoke all on function public.set_membership_deleted(uuid,uuid,bigint,boolean,text,uuid) from public,anon;
grant execute on function public.set_membership_deleted(uuid,uuid,bigint,boolean,text,uuid) to authenticated;

-- A scheduled membership can be cancelled today without backdating its start.
do $migration$
declare definition text;
begin
  select pg_get_functiondef('public.transition_subscription(uuid,uuid,bigint,text,date,text,uuid,integer)'::regprocedure) into definition;
  definition=replace(definition,'if p_date>today or p_date<s.start_date then',
    'if p_action<>''cancel'' and (p_date>today or p_date<s.start_date) then');
  definition=replace(definition,'if s.version<>p_expected then',
    'if s.deleted_at is not null then raise exception ''Restore this deleted membership before making changes''; end if; if s.version<>p_expected then');
  execute definition;
end $migration$;
