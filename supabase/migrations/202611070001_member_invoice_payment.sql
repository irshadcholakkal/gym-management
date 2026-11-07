-- One server-verified payment, with a separate allocation for every invoice.
create function public.member_invoice_payment_quote(p_gym uuid,p_member uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare items jsonb;
begin
  perform private.require_finance(p_gym);
  if not exists(select 1 from public.members where gym_id=p_gym and id=p_member) then raise exception 'Member unavailable'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'balance_minor',i.total_minor-i.paid_minor-i.credit_minor,
    'currency',i.currency,'due_date',i.due_date,'package_name',s.package_snapshot->>'name') order by i.due_date,i.id),'[]')
    into items from public.invoices i left join public.subscriptions s on s.gym_id=i.gym_id and s.id=i.subscription_id
    where i.gym_id=p_gym and i.member_id=p_member and i.status<>'voided' and i.total_minor>i.paid_minor+i.credit_minor;
  return jsonb_build_object('invoices',items);
end $$;

create function public.pay_member_invoices(p_gym uuid,p_member uuid,p_invoices jsonb,p_method text,p_reference text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous public.sync_operation_receipts; request jsonb; expected jsonb; actual jsonb;
  i public.invoices; p public.payments; r public.receipts; m public.members; g public.gyms;
  total bigint=0; invoice_total bigint=0; subtotal bigint=0; discounts bigint=0; tax bigint=0;
  currency text; lines jsonb='[]'; result jsonb;
begin
  perform private.require_finance(p_gym);
  request=jsonb_build_object('member',p_member,'invoices',p_invoices,'method',p_method,'reference',coalesce(p_reference,''));
  select * into previous from public.sync_operation_receipts where id=p_operation;
  if found then
    if previous.gym_id<>p_gym or previous.user_id<>auth.uid() or previous.request<>request then raise exception 'Idempotency key reused'; end if;
    return previous.result;
  end if;
  if jsonb_typeof(p_invoices)<>'array' or jsonb_array_length(p_invoices)=0 then raise exception 'No outstanding invoices selected'; end if;
  select * into strict m from public.members where gym_id=p_gym and id=p_member;
  select * into strict g from public.gyms where id=p_gym;
  select jsonb_agg(jsonb_build_object('id',x->>'id','balance_minor',(x->>'balance_minor')::bigint,'currency',x->>'currency') order by x->>'id')
    into expected from jsonb_array_elements(p_invoices) x;
  perform 1 from public.invoices where gym_id=p_gym and member_id=p_member order by id for update;
  select jsonb_agg(jsonb_build_object('id',inv.id,'balance_minor',inv.total_minor-inv.paid_minor-inv.credit_minor,'currency',inv.currency) order by inv.id::text)
    into actual from public.invoices inv where inv.gym_id=p_gym and inv.member_id=p_member and inv.status<>'voided' and inv.total_minor>inv.paid_minor+inv.credit_minor;
  if actual is distinct from expected then
    raise exception using errcode='40001',message='Outstanding invoices changed. Close this window and review the updated total.';
  end if;
  if (select count(distinct inv.currency) from public.invoices inv where inv.gym_id=p_gym and inv.member_id=p_member
    and inv.status<>'voided' and inv.total_minor>inv.paid_minor+inv.credit_minor)<>1 then raise exception 'Pay invoices in different currencies separately'; end if;
  for i in select * from public.invoices where gym_id=p_gym and member_id=p_member and status<>'voided'
    and total_minor>paid_minor+credit_minor order by due_date,id loop
    total=total+i.total_minor-i.paid_minor-i.credit_minor;
    invoice_total=invoice_total+i.total_minor; subtotal=subtotal+i.subtotal_minor;
    discounts=discounts+i.discount_minor; tax=tax+i.tax_minor; currency=i.currency;
    lines=lines||jsonb_build_array(jsonb_build_object('invoice_id',i.id,'due_date',i.due_date,
      'amount_minor',i.total_minor-i.paid_minor-i.credit_minor,'currency',i.currency));
  end loop;
  insert into public.payments(gym_id,member_id,amount_minor,currency,method,reference,idempotency_key,actor_id)
    values(p_gym,p_member,total,currency,p_method,coalesce(p_reference,''),p_operation,auth.uid()) returning * into p;
  insert into public.payment_allocations(gym_id,payment_id,invoice_id,amount_minor)
    select p_gym,p.id,id,total_minor-paid_minor-credit_minor from public.invoices where gym_id=p_gym and member_id=p_member
      and status<>'voided' and total_minor>paid_minor+credit_minor;
  update public.invoices set paid_minor=total_minor-credit_minor,status='paid',updated_at=now(),version=version+1
    where gym_id=p_gym and member_id=p_member and status<>'voided' and total_minor>paid_minor+credit_minor;
  insert into public.receipts(gym_id,payment_id,snapshot) values(p_gym,p.id,jsonb_build_object(
    'gym_name',g.name,'gym_address',g.address,'gym_phone',g.phone,'member_name',m.full_name,'member_number',m.member_number,
    'package_name','All outstanding invoices ('||jsonb_array_length(lines)||')','invoices',lines,
    'subtotal_minor',subtotal,'discount_minor',discounts,'total_minor',invoice_total,'tax_minor',tax,
    'paid_minor',total,'balance_minor',0,'currency',currency,'method',p_method,'reference',p_reference,
    'payment_date',p.created_at,'issuer',coalesce((select raw_user_meta_data->>'full_name' from auth.users where id=auth.uid()),'Team member'),
    'issuer_id',auth.uid())) returning * into r;
  result=jsonb_build_object('payment',to_jsonb(p),'receipt',to_jsonb(r),'invoice_count',jsonb_array_length(lines));
  insert into public.audit_logs(gym_id,actor_id,action,record_id,after_data) values(p_gym,auth.uid(),'payment:member_invoices',p.id,result);
  insert into public.sync_operation_receipts(id,gym_id,user_id,request,result) values(p_operation,p_gym,auth.uid(),request,result);
  return result;
end $$;
revoke all on function public.member_invoice_payment_quote(uuid,uuid),public.pay_member_invoices(uuid,uuid,jsonb,text,text,uuid) from public,anon;
grant execute on function public.member_invoice_payment_quote(uuid,uuid),public.pay_member_invoices(uuid,uuid,jsonb,text,text,uuid) to authenticated;
