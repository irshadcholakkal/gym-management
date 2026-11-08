import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

// Real PostgreSQL WASM execution. Auth, Storage and Realtime are minimal test
// adapters; their hosted services still require Supabase acceptance testing.
const db = new PGlite({ extensions: { btree_gist } });
await db.exec(`
  create role anon; create role authenticated; create role service_role bypassrls;
  create schema auth; create table auth.users(id uuid primary key,email text,invited_at timestamptz,created_at timestamptz not null default now(),email_confirmed_at timestamptz,raw_user_meta_data jsonb not null default '{}');
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
  create schema realtime; create table realtime.messages(extension text);
  alter table realtime.messages enable row level security;
  create function realtime.topic() returns text language sql stable as $$ select current_setting('realtime.topic',true) $$;
  create function realtime.send(jsonb,text,text,boolean) returns void language sql as $$ select $$;
  create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
  create table storage.objects(id uuid primary key,bucket_id text,name text,owner_id text,metadata jsonb); alter table storage.objects enable row level security;
  grant usage on schema storage to authenticated; grant select,insert,delete on storage.objects to authenticated;
  create function storage.foldername(text) returns text[] language sql as $$ select string_to_array($1,'/') $$;
`);
const migrations = new URL('../../supabase/migrations/', import.meta.url);
for (const name of (await readdir(migrations)).filter(n => n.endsWith('.sql')).sort()) {
  try { await db.exec(await readFile(new URL(name,migrations),'utf8')); console.log(`Migration OK: ${name}`); }
  catch (e) { console.error(`Migration FAILED: ${name}: ${e.message}`); throw e; }
}
let passed = 0;
const check = async (name, fn) => { await fn(); passed++; console.log(`PASS ${name}`); };
const a=randomUUID(), b=randomUUID(), trainer=randomUUID(), gymA=randomUUID(), gymB=randomUUID(), member=randomUUID(), packageId=randomUUID();
await db.query('insert into auth.users(id) values($1),($2),($3)',[a,b,trainer]);
await db.query("insert into public.gyms(id,name) values($1,'Gym A'),($2,'Gym B')",[gymA,gymB]);
await db.query("insert into public.gym_users(gym_id,user_id,role) values($1,$2,'owner'),($3,$4,'owner'),($1,$5,'trainer')",[gymA,a,gymB,b,trainer]);
async function login(id) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); }
await login(a);
async function rpc(name, args) {
  const placeholders=args.map((_,i)=>`$${i+1}`).join(',');
  return (await db.query(`select public.${name}(${placeholders}) as result`,args)).rows[0].result;
}
await check('Offline-created member accepted with client UUID and retry is idempotent',async()=>{
  const op=randomUUID(),data={full_name:'Amina',phone:'+971501234567',email:'A@EXAMPLE.COM',joining_date:'2026-01-01',status:'active'};
  const one=await rpc('apply_sync_operation',[gymA,op,'members',member,0,data]);
  const two=await rpc('apply_sync_operation',[gymA,op,'members',member,0,data]);
  assert.deepEqual(one,two); assert.equal(one.email,'a@example.com');
});
await rpc('apply_sync_operation',[gymA,randomUUID(),'membership_packages',packageId,0,{name:'Three months',description:'',duration_value:3,duration_unit:'months',price_minor:30000,currency:'AED',allowed_pause_days:40,status:'active'}]);
await check('Concurrent stale member edit is rejected',async()=>{
  await assert.rejects(()=>rpc('apply_sync_operation',[gymA,randomUUID(),'members',member,0,{full_name:'Stale'}]),e=>e.code==='40001');
});
let subscription,invoice,receipt;
await check('Three calendar months end exclusively on April 1',async()=>{
  const result=await rpc('create_subscription',[gymA,member,packageId,'2026-01-01',randomUUID()]);
  subscription=result.subscription; invoice=result.invoice;
  assert.equal(subscription.end_exclusive,'2026-04-01'); assert.equal(invoice.total_minor,30000);
});
await check('20-day pause restores exactly 20 paid days',async()=>{
  subscription=await rpc('transition_subscription',[gymA,subscription.id,subscription.version,'pause','2026-02-01','Travel',randomUUID(),0]);
  subscription=await rpc('transition_subscription',[gymA,subscription.id,subscription.version,'resume','2026-02-21','Returned',randomUUID(),0]);
  assert.equal(subscription.end_exclusive,'2026-04-21');
});
await check('Overlapping historical pauses are rejected by database',async()=>{
  await assert.rejects(()=>rpc('transition_subscription',[gymA,subscription.id,subscription.version,'pause','2026-02-10','Overlap',randomUUID(),0]),e=>e.code==='23P01');
});
await check('Multiple pauses preserve history and accumulate dates',async()=>{
  subscription=await rpc('transition_subscription',[gymA,subscription.id,subscription.version,'pause','2026-03-01','Travel',randomUUID(),0]);
  subscription=await rpc('transition_subscription',[gymA,subscription.id,subscription.version,'resume','2026-03-06','Returned',randomUUID(),0]);
  assert.equal(subscription.end_exclusive,'2026-04-26');
});
await check('Partial payment and retry yield one immutable receipt',async()=>{
  const op=randomUUID();
  const first=await rpc('post_payment',[gymA,invoice.id,10000,'cash','Desk collection',op]);
  const retry=await rpc('post_payment',[gymA,invoice.id,10000,'cash','Desk collection',op]);
  assert.deepEqual(first,retry); assert.equal(first.invoice.paid_minor,10000);
  assert.equal(first.receipt.snapshot.balance_minor,20000); receipt=first.receipt;
  assert.equal((await db.query('select count(*)::int as n from public.payments')).rows[0].n,1);
  await assert.rejects(()=>db.query("update public.receipts set snapshot='{}' where id=$1",[receipt.id]),e=>e.code==='42501');
});
await check('Payment idempotency key cannot be reused for another amount',async()=>{
  const op=randomUUID(); await rpc('post_payment',[gymA,invoice.id,1000,'cash','',op]);
  await assert.rejects(()=>rpc('post_payment',[gymA,invoice.id,2000,'cash','',op]),/Idempotency/);
});
await check('Trainer cannot retrieve or post financial records',async()=>{
  await login(trainer);
  assert.equal((await db.query('select * from public.invoices')).rows.length,0);
  await assert.rejects(()=>rpc('post_payment',[gymA,invoice.id,100,'cash','',randomUUID()]),e=>e.code==='42501');
  const changes=await rpc('pull_changes',[gymA,0]);
  assert.equal(changes.changes.filter(c=>['payments','invoices','receipts'].includes(c.kind)).length,0);
});
await check('Other gym cannot read member, delta payload, or issue payment',async()=>{
  await login(b);
  assert.equal((await db.query('select * from public.members where id=$1',[member])).rows.length,0);
  await assert.rejects(()=>rpc('pull_changes',[gymA,0]),e=>e.code==='42501');
  await assert.rejects(()=>rpc('post_payment',[gymA,invoice.id,100,'cash','',randomUUID()]),e=>e.code==='42501');
});
await check('Leap-day and month-end calculations match client contract',async()=>{
  await login(a);
  assert.equal((await rpc('membership_end',['2024-02-29',1,'years'])).toISOString().slice(0,10),'2025-02-28');
  assert.equal((await rpc('membership_end',['2026-01-31',1,'months'])).toISOString().slice(0,10),'2026-02-28');
});
await check('Authorized cursor catches all committed changes with stable replay',async()=>{
  const changes=await rpc('pull_changes',[gymA,0]);
  assert.ok(changes.changes.some(c=>c.record_id===member));
  assert.ok(changes.changes.some(c=>c.record_id===receipt.id));
  const next=await rpc('pull_changes',[gymA,changes.cursor]);
  assert.equal(next.changes.length,0);
});
let activeSub,activeInvoice,activePayment;
const today=(await db.query("select (now() at time zone 'Asia/Dubai')::date::text as d")).rows[0].d;
const upgradePackage=randomUUID(),activeMember=randomUUID();
await rpc('apply_sync_operation',[gymA,randomUUID(),'members',activeMember,0,{full_name:'Omar',phone:'+971501234568',email:'',joining_date:today,status:'active'}]);
await rpc('apply_sync_operation',[gymA,randomUUID(),'membership_packages',upgradePackage,0,{name:'Premium',description:'',duration_value:3,duration_unit:'months',price_minor:45000,currency:'AED',allowed_pause_days:40,status:'active'}]);
await check('Approved upgrade keeps original invoice and adds AED 150; balance becomes AED 350',async()=>{
  const created=await rpc('create_subscription',[gymA,activeMember,packageId,today,randomUUID()]); activeSub=created.subscription; activeInvoice=created.invoice;
  const payment=await rpc('post_payment',[gymA,activeInvoice.id,10000,'cash','',randomUUID()]); activePayment=payment.payment;
  const result=await rpc('change_package',[gymA,activeSub.id,activeSub.version,upgradePackage,'immediate','Approved upgrade',randomUUID(),15000]); activeSub=result.subscription;
  assert.equal(result.adjustment_minor,15000);
  const balance=(await db.query('select sum(total_minor-paid_minor-credit_minor)::int as due from public.invoices where subscription_id=$1',[activeSub.id])).rows[0].due;
  assert.equal(balance,35000);
  assert.equal((await db.query('select total_minor::int from public.invoices where id=$1',[activeInvoice.id])).rows[0].total_minor,30000);
});
await check('Payment reversal restores receivable and voids receipt without deleting payment',async()=>{
  const op=randomUUID(); const first=await rpc('reverse_payment',[gymA,activePayment.id,'reversal','Collection entered twice',op]);
  assert.deepEqual(await rpc('reverse_payment',[gymA,activePayment.id,'reversal','Collection entered twice',op]),first);
  assert.equal((await db.query('select paid_minor::int from public.invoices where id=$1',[activeInvoice.id])).rows[0].paid_minor,0);
  assert.equal((await db.query('select status from public.receipts where payment_id=$1',[activePayment.id])).rows[0].status,'voided');
  assert.equal((await db.query('select count(*)::int n from public.payments where id=$1',[activePayment.id])).rows[0].n,1);
});
await check('Next renewal preserves current plan and supports safe retry',async()=>{
  const op=randomUUID(); const first=await rpc('change_package',[gymA,activeSub.id,activeSub.version,packageId,'next_renewal','Next term',op,null]);
  assert.equal(first.subscription.start_date,activeSub.end_exclusive);
  assert.equal(first.subscription.status,'scheduled_renewal');
  assert.deepEqual(await rpc('change_package',[gymA,activeSub.id,activeSub.version,packageId,'next_renewal','Next term',op,null]),first);
});
await check('Seven-day reminder deduplicates and pause supersedes stale reminder',async()=>{
  const reminderMember=randomUUID();
  await rpc('apply_sync_operation',[gymA,randomUUID(),'members',reminderMember,0,{full_name:'Reminder',phone:'+971501234569',joining_date:today,status:'active'}]);
  const result=await rpc('create_subscription',[gymA,reminderMember,packageId,today,randomUUID()]);
  await db.exec('reset role');
  await db.query("update public.subscriptions set original_end_exclusive=$2::date+8,end_exclusive=$2::date+8 where id=$1",[result.subscription.id,today]);
  await db.exec('select public.process_expiry_reminders(); select public.process_expiry_reminders()');
  assert.equal((await db.query('select count(*)::int n from public.notifications where subscription_id=$1',[result.subscription.id])).rows[0].n,1);
  await login(a);
  await rpc('transition_subscription',[gymA,result.subscription.id,result.subscription.version,'pause',today,'Travel',randomUUID(),0]);
  assert.ok((await db.query('select superseded_at from public.notifications where subscription_id=$1',[result.subscription.id])).rows[0].superseded_at);
});
await check('Verified account can create only its own new gym, with idempotent retries',async()=>{
  await db.exec('reset role');
  const owner=randomUUID();
  await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[owner]);
  await login(owner);
  const ownGym=await rpc('create_own_gym',['New gym']);
  assert.equal(await rpc('create_own_gym',['Retry after timeout']),ownGym);
  const memberships=(await db.query('select gym_id,role from public.gym_users')).rows;
  assert.equal(memberships.length,1); assert.equal(memberships[0].gym_id,ownGym);assert.equal(memberships[0].role,'owner');
  assert.equal((await db.query('select * from public.members where gym_id=$1',[gymA])).rows.length,0);
});
await check('Unconfirmed and anonymous accounts cannot create gyms',async()=>{
  await db.exec('reset role');
  const unconfirmed=randomUUID(); await db.query('insert into auth.users(id) values($1)',[unconfirmed]);
  await login(unconfirmed);
  await assert.rejects(()=>rpc('create_own_gym',['Forbidden']),e=>e.code==='42501');
  await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub','',false)");await db.exec('set role anon');
  await assert.rejects(()=>rpc('create_own_gym',['Forbidden']),e=>e.code==='42501');
});
await check('Existing staff cannot promote themselves through owner onboarding',async()=>{
  await db.exec('reset role');await db.query('update auth.users set email_confirmed_at=now() where id=$1',[trainer]);
  await login(trainer);
  await assert.rejects(()=>rpc('create_own_gym',['Forbidden']),e=>e.code==='42501');
});
let discountedSubscription,discountedInvoice,discountMember,discountPackage;
await check('Special discount is audited, applied before tax and does not change package price',async()=>{
  await login(a);discountMember=randomUUID();discountPackage=randomUUID();
  await rpc('apply_sync_operation',[gymA,randomUUID(),'members',discountMember,0,{full_name:'Discount member',phone:'+971501234570',joining_date:today,status:'active'}]);
  await rpc('apply_sync_operation',[gymA,randomUUID(),'membership_packages',discountPackage,0,{name:'Discount test plan',description:'',duration_value:1,duration_unit:'months',price_minor:30000,currency:'AED',allowed_pause_days:10,status:'active'}]);
  await db.exec('reset role');await db.query('update public.membership_packages set enrollment_fee_minor=1000,tax_basis_points=500 where id=$1',[discountPackage]);await login(a);
  const op=randomUUID(),args=[gymA,discountMember,discountPackage,today,op,5000,'Loyalty discount'];
  const first=await rpc('create_subscription_discounted',args);
  assert.deepEqual(await rpc('create_subscription_discounted',args),first);
  discountedSubscription=first.subscription;discountedInvoice=first.invoice;
  assert.equal(first.invoice.subtotal_minor,31000);assert.equal(first.invoice.discount_minor,5000);assert.equal(first.invoice.tax_minor,1300);assert.equal(first.invoice.total_minor,27300);
  assert.equal(first.invoice.discount_actor_id,a);assert.ok(first.invoice.discount_granted_at);assert.equal(first.subscription.package_snapshot.price_minor,30000);assert.equal(first.subscription.package_snapshot.agreed_price_minor,25000);
  await assert.rejects(()=>rpc('create_subscription_discounted',[gymA,discountMember,discountPackage,today,op,6000,'Changed discount']),/Idempotency/);
  assert.equal((await db.query('select count(*)::int n from public.invoices where subscription_id=$1',[discountedSubscription.id])).rows[0].n,1);
});
await check('Partial collection and official receipt retain the granted discount',async()=>{
  const result=await rpc('post_payment',[gymA,discountedInvoice.id,10000,'cash','Discount payment',randomUUID()]);
  assert.equal(result.receipt.snapshot.discount_minor,5000);assert.equal(result.receipt.snapshot.subtotal_minor,31000);assert.equal(result.receipt.snapshot.balance_minor,17300);assert.equal(result.receipt.snapshot.issuer,'Team member');
});
await check('Renewal can have a different discount while historical invoice stays unchanged',async()=>{
  const result=await rpc('create_subscription_discounted',[gymA,discountMember,discountPackage,discountedSubscription.end_exclusive,randomUUID(),2500,'Renewal offer']);
  assert.equal(result.invoice.discount_minor,2500);assert.equal(result.invoice.total_minor,29925);
  assert.equal((await db.query('select discount_minor::int from public.invoices where id=$1',[discountedInvoice.id])).rows[0].discount_minor,5000);
  assert.equal((await db.query('select sum(discount_minor)::int n from public.invoices where gym_id=$1',[gymA])).rows[0].n,7500);
});
await check('Invalid discounts and discounts without reasons are rejected',async()=>{
  await assert.rejects(()=>rpc('create_subscription_discounted',[gymA,discountMember,discountPackage,today,randomUUID(),-1,'Invalid']),/negative/);
  await assert.rejects(()=>rpc('create_subscription_discounted',[gymA,discountMember,discountPackage,today,randomUUID(),30001,'Too much']),/exceed/);
  await assert.rejects(()=>rpc('create_subscription_discounted',[gymA,discountMember,discountPackage,today,randomUUID(),100,'']),/reason/);
});
await check('Paused membership must be resumed before scheduling another membership',async()=>{
  const paused=(await db.query("select member_id from public.subscriptions where gym_id=$1 and status='paused' limit 1",[gymA])).rows[0];
  await assert.rejects(()=>rpc('create_subscription_discounted',[gymA,paused.member_id,discountPackage,today,randomUUID(),0,'']),/Resume the current membership/);
});
await check('Receptionist cannot grant discounts but can create a full-price membership',async()=>{
  await db.exec('reset role');const reception=randomUUID(),memberId=randomUUID();await db.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[reception]);await db.query("insert into public.gym_users(gym_id,user_id,role) values($1,$2,'receptionist')",[gymA,reception]);
  await login(a);await rpc('apply_sync_operation',[gymA,randomUUID(),'members',memberId,0,{full_name:'Full-price member',phone:'+971501234571',joining_date:today,status:'active'}]);await login(reception);
  await assert.rejects(()=>rpc('create_subscription_discounted',[gymA,memberId,discountPackage,today,randomUUID(),100,'Not authorized']),e=>e.code==='42501');
  const result=await rpc('create_subscription_discounted',[gymA,memberId,discountPackage,today,randomUUID(),0,'']);assert.equal(result.invoice.total_minor,32550);assert.equal(result.invoice.discount_minor,0);
});
await check('Member photo attachment is versioned, private and idempotent', async()=>{
  await db.exec('reset role');
  const path=gymA+'/'+member+'/'+a+'/'+randomUUID()+'.jpg';
  await db.query("insert into storage.objects(id,bucket_id,name,owner_id,metadata) values($1,'member-photos',$2,$3,$4)",[randomUUID(),path,a,{size:25000,mimetype:'image/jpeg'}]);
  await login(a);
  const version=(await db.query('select version from public.members where id=$1',[member])).rows[0].version;
  const op=randomUUID(),args=[gymA,member,version,path,op];
  const result=await rpc('set_member_photo',args);
  assert.equal(result.profile_image,path);assert.equal(result.version,version+1);
  assert.deepEqual(await rpc('set_member_photo',args),result);
  assert.equal((await db.query('select name from storage.objects where name=$1',[path])).rows.length,1);
  assert.equal((await db.query('delete from storage.objects where name=$1 returning name',[path])).rows.length,0);
  await assert.rejects(()=>rpc('set_member_photo',[gymA,member,version,path,randomUUID()]),e=>e.code==='40001');
  await login(b);assert.equal((await db.query('select name from storage.objects where name=$1',[path])).rows.length,0);await assert.rejects(()=>rpc('set_member_photo',[gymA,member,version+1,path,randomUUID()]));
  await login(trainer);await assert.rejects(()=>rpc('set_member_photo',[gymA,member,version+1,path,randomUUID()]));
  await login(a);await assert.rejects(()=>rpc('set_member_photo',[gymA,member,version+1,gymB+'/'+member+'/'+a+'/fake.jpg',randomUUID()]),/Invalid member photo/);
  await db.exec('reset role');await db.query("update storage.objects set metadata=$1 where name=$2",[{size:160000,mimetype:'image/jpeg'},path]);await login(a);
  await assert.rejects(()=>rpc('set_member_photo',[gymA,member,version+1,path,randomUUID()]),/Invalid member photo/);
});
await check('Member occupation persists, edits, clears, and survives older clients', async () => {
  await login(a);
  const id=randomUUID(), data={full_name:'Occupation test',phone:'+971501234569',joining_date:'2026-01-01',status:'active',occupation:'  Teacher  '};
  let record=await rpc('apply_sync_operation',[gymA,randomUUID(),'members',id,0,data]);
  assert.equal(record.occupation,'Teacher');
  const operation=randomUUID(), args=[gymA,operation,'members',id,record.version,{...data,occupation:'Engineer'}];
  record=await rpc('apply_sync_operation',args);
  assert.equal(record.occupation,'Engineer');
  assert.deepEqual(await rpc('apply_sync_operation',args),record);
  const legacy={...data}; delete legacy.occupation;
  record=await rpc('apply_sync_operation',[gymA,randomUUID(),'members',id,record.version,legacy]);
  assert.equal(record.occupation,'Engineer');
  record=await rpc('apply_sync_operation',[gymA,randomUUID(),'members',id,record.version,{...data,occupation:''}]);
  assert.equal(record.occupation,'');
  await login(b);
  await assert.rejects(()=>rpc('apply_sync_operation',[gymA,randomUUID(),'members',id,record.version,{...data,occupation:'Unauthorized'}]),e=>e.code==='42501');
});

const employeeUser=randomUUID(), otherEmployee=randomUUID();
await db.exec('reset role');
await db.query('insert into auth.users(id) values($1),($2)',[employeeUser,otherEmployee]);
await db.query("insert into public.gym_users(gym_id,user_id,role) values($1,$2,'manager'),($1,$3,'trainer')",[gymA,employeeUser,otherEmployee]);
await db.query("insert into public.employees(gym_id,user_id,full_name,email) values($1,$2,'Employee','employee@example.com'),($1,$3,'Other','other@example.com')",[gymA,employeeUser,otherEmployee]);
await check('Only an administrator of the same gym can set employee roles and options',async()=>{
  await login(b);await assert.rejects(()=>rpc('set_employee_access',[gymA,employeeUser,'admin','employee.test',{}]),e=>e.code==='42501');
  await login(employeeUser);await assert.rejects(()=>rpc('set_employee_access',[gymA,employeeUser,'admin','employee.test',{}]),e=>e.code==='42501');
  await login(a);await assert.rejects(()=>rpc('set_employee_access',[gymA,employeeUser,'owner','employee.test',{}]),e=>e.code==='42501');
  await rpc('set_employee_access',[gymA,employeeUser,'manager','employee.test',{edit_members:false,discounts:false}]);
  const row=(await db.query('select * from public.employees where user_id=$1',[employeeUser])).rows[0];
  assert.equal(row.access_role,'manager');assert.equal(row.username,'employee.test');assert.equal(row.access_options.edit_members,false);
});
await check('Custom member-edit and discount restrictions are enforced by business RPCs',async()=>{
  await login(employeeUser);
  await assert.rejects(()=>rpc('apply_sync_operation',[gymA,randomUUID(),'members',randomUUID(),0,{full_name:'Blocked',phone:'+971501234568',joining_date:'2026-01-01',status:'active'}]),e=>e.code==='42501');
  await assert.rejects(()=>rpc('create_subscription_discounted',[gymA,member,packageId,'2029-01-01',randomUUID(),100,'Blocked']),e=>e.code==='42501');
  assert.equal((await db.query('select id from public.invoices')).rows.length>0,true);
});
await check('Disabling operations removes finance reads and delta payloads and blocks payment writes',async()=>{
  await login(a);await rpc('set_employee_access',[gymA,employeeUser,'manager','employee.test',{operations:false}]);
  await login(employeeUser);assert.equal((await db.query('select id from public.invoices')).rows.length,0);
  const delta=await rpc('pull_changes',[gymA,0]);assert.equal(delta.changes.some(c=>['invoices','payments','receipts','membership_packages'].includes(c.kind)),false);
  await assert.rejects(()=>rpc('post_payment',[gymA,randomUUID(),100,'cash','',randomUUID()]),e=>e.code==='42501');
});
await check('Usernames are unique, reserved employee IDs cannot be claimed, and aliases are private',async()=>{
  await login(a);await assert.rejects(()=>rpc('set_employee_access',[gymA,otherEmployee,'trainer','employee.test',{}]),e=>e.code==='23505');
  await assert.rejects(()=>rpc('set_employee_access',[gymA,otherEmployee,'trainer','emp-123',{}]));
  await assert.rejects(()=>rpc('set_employee_access',[gymA,otherEmployee,'trainer','other.test',{operations:'yes'}]));
  await assert.rejects(()=>rpc('resolve_employee_login',['employee.test']),e=>e.code==='42501');
  await db.exec('reset role');await db.exec('set role anon');await assert.rejects(()=>rpc('resolve_employee_login',['employee.test']),e=>e.code==='42501');
  await db.exec('reset role');const number=(await db.query('select employee_number from public.employees where user_id=$1',[employeeUser])).rows[0].employee_number;await db.exec('set role service_role');
  assert.equal(await rpc('resolve_employee_login',['EMP-'+number]),employeeUser);
  assert.equal(await rpc('resolve_employee_login',['EMPLOYEE.TEST']),employeeUser);
  await db.exec('reset role');await db.query("update public.gym_users set active=false where user_id=$1",[employeeUser]);await db.exec('set role service_role');
  assert.equal(await rpc('resolve_employee_login',['employee.test']),null);
});
await check('Alias login rate limiter rejects repeated attempts',async()=>{
  await db.exec('reset role');await db.exec('set role service_role');
  for(let i=0;i<10;i++)assert.equal(await rpc('allow_employee_login',['test-hash']),true);
  assert.equal(await rpc('allow_employee_login',['test-hash']),false);
});

await check('Invitations attach role, username and restrictions atomically',async()=>{
  await db.exec('reset role');const fresh=randomUUID();await db.query('insert into auth.users(id) values($1)',[fresh]);await db.exec('set role service_role');
  await rpc('attach_invited_employee_access',[gymA,a,fresh,'Fresh','fresh@example.com','manager','','','fresh.employee',{edit_members:false,discounts:false}]);
  await db.exec('reset role');const row=(await db.query('select * from public.employees where user_id=$1',[fresh])).rows[0];
  assert.equal(row.access_role,'manager');assert.equal(row.username,'fresh.employee');assert.equal(row.access_options.discounts,false);
  const failed=randomUUID();await db.query('insert into auth.users(id) values($1)',[failed]);await db.exec('set role service_role');
  await assert.rejects(()=>rpc('attach_invited_employee_access',[gymA,a,failed,'Failed','failed@example.com','admin','','','fresh.employee',{}]),e=>e.code==='23505');
  await db.exec('reset role');assert.equal((await db.query('select id from public.gym_users where user_id=$1',[failed])).rows.length,0);
});
await check('Disabling administration blocks team access even for the admin role',async()=>{
  await login(a);await rpc('set_employee_access',[gymA,otherEmployee,'admin','other.admin',{administration:false}]);
  await login(otherEmployee);assert.equal(await rpc('can_administer',[gymA]),false);
  await assert.rejects(()=>rpc('set_employee_access',[gymA,otherEmployee,'admin','other.admin',{}]),e=>e.code==='42501');
});

await check('Receipt HTML design persists per gym, with role checks and concurrent edit protection',async()=>{
  const html='<h1>{{receipt_number}}</h1><p>Custom receipt</p>';
  await login(a);let design=await rpc('save_receipt_design',[gymA,html,0]);assert.equal(design.html,html);assert.equal(design.version,1);
  await assert.rejects(()=>rpc('save_receipt_design',[gymA,html,0]),e=>e.code==='40001');
  design=await rpc('save_receipt_design',[gymA,html+'<!-- updated -->',1]);assert.equal(design.version,2);
  await login(b);assert.equal((await db.query('select * from public.receipt_designs where gym_id=$1',[gymA])).rows.length,0);
  await assert.rejects(()=>rpc('save_receipt_design',[gymA,'Other gym',2]),e=>e.code==='42501');
  await login(trainer);await assert.rejects(()=>rpc('save_receipt_design',[gymA,'Trainer',2]),e=>e.code==='42501');
  await login(a);await assert.rejects(()=>rpc('save_receipt_design',[gymA,'',2]));
});
await check('Orphaned invitations cannot create a gym and can be repaired only by an authorized administrator',async()=>{
  await db.exec('reset role');
  const invited=randomUUID();
  await db.query("insert into auth.users(id,email,invited_at,email_confirmed_at) values($1,'invited@example.com',now(),now())",[invited]);
  await login(invited);
  await assert.rejects(()=>rpc('create_own_gym',['Accidental gym']),e=>e.code==='42501');
  await assert.rejects(()=>rpc('find_invited_employee',[gymA,a,'invited@example.com']),e=>e.code==='42501');
  await db.exec('reset role');await db.exec('set role service_role');
  await assert.rejects(()=>rpc('find_invited_employee',[gymA,trainer,'invited@example.com']),e=>e.code==='42501');
  assert.equal(await rpc('find_invited_employee',[gymA,a,'INVITED@example.com']),invited);
  await rpc('attach_invited_employee_access',[gymA,a,invited,'Invited employee','invited@example.com','trainer','','','invited.employee',{}]);
  assert.equal(await rpc('find_invited_employee',[gymA,a,'invited@example.com']),null);
  await db.exec('reset role');
  const attached=(await db.query('select g.role,e.access_role from public.gym_users g join public.employees e using(gym_id,user_id) where g.gym_id=$1 and g.user_id=$2',[gymA,invited])).rows[0];
  assert.equal(attached.role,'trainer');assert.equal(attached.access_role,'trainer');
});
await check('Bulk collection is atomic, idempotent, tenant-scoped, reversible and rejects stale balances',async()=>{
  await db.exec('reset role');
  const person=randomUUID(),one=randomUUID(),two=randomUUID(),voided=randomUUID(),op=randomUUID();
  await db.query("insert into public.members(id,gym_id,full_name,phone,joining_date) values($1,$2,'Bulk payer','+971501234599',current_date)",[person,gymA]);
  await db.query("insert into public.invoices(id,gym_id,member_id,currency,total_minor,subtotal_minor,paid_minor,credit_minor,status,due_date) values($1,$4,$5,'AED',10000,10000,2000,1000,'partially_paid',current_date),($2,$4,$5,'AED',20000,20000,0,0,'unpaid',current_date),($3,$4,$5,'AED',30000,30000,0,0,'voided',current_date)",[one,two,voided,gymA,person]);
  await login(a);
  const items=q=>q.invoices.map(({id,balance_minor,currency})=>({id,balance_minor,currency}));
  const quote=await rpc('member_invoice_payment_quote',[gymA,person]);assert.equal(quote.invoices.length,2);
  const args=[gymA,person,items(quote),'cash','One collection',op];
  const paid=await rpc('pay_member_invoices',args);
  assert.equal(paid.payment.amount_minor,27000);assert.equal(paid.invoice_count,2);
  assert.equal(paid.receipt.snapshot.invoices.length,2);assert.equal(paid.receipt.snapshot.balance_minor,0);
  assert.deepEqual(await rpc('pay_member_invoices',args),paid);
  assert.equal((await rpc('member_invoice_payment_quote',[gymA,person])).invoices.length,0);
  await db.exec('reset role');
  assert.equal((await db.query('select count(*)::int as n from public.payments where idempotency_key=$1',[op])).rows[0].n,1);
  assert.equal((await db.query('select count(*)::int as n from public.payment_allocations where payment_id=$1',[paid.payment.id])).rows[0].n,2);
  assert.equal((await db.query('select status from public.invoices where id=$1',[voided])).rows[0].status,'voided');
  await login(a);await rpc('reverse_payment',[gymA,paid.payment.id,'reversal','Test reversal',randomUUID()]);
  const stale=await rpc('member_invoice_payment_quote',[gymA,person]);
  assert.equal(stale.invoices.reduce((n,i)=>n+i.balance_minor,0),27000);
  await db.exec('reset role');await db.query('update public.invoices set credit_minor=credit_minor+1 where id=$1',[one]);await login(a);
  await assert.rejects(()=>rpc('pay_member_invoices',[gymA,person,items(stale),'cash','',randomUUID()]),e=>e.code==='40001');
  await login(b);await assert.rejects(()=>rpc('member_invoice_payment_quote',[gymA,person]),e=>e.code==='42501');
  await login(trainer);await assert.rejects(()=>rpc('pay_member_invoices',args),e=>e.code==='42501');
  await db.exec('reset role');await db.query("update public.invoices set currency='USD' where id=$1",[two]);await login(a);
  const mixed=await rpc('member_invoice_payment_quote',[gymA,person]);
  await assert.rejects(()=>rpc('pay_member_invoices',[gymA,person,items(mixed),'cash','',randomUUID()]),/different currencies/);
});
await check('Accidental memberships delete and restore without erasing history; paid records are protected',async()=>{
  await db.exec('reset role');const person=randomUUID();
  await db.query("insert into public.members(id,gym_id,full_name,phone,joining_date) values($1,$2,'Accidental member','+971501234588',current_date)",[person,gymA]);
  await login(a);const created=await rpc('create_subscription',[gymA,person,packageId,today,randomUUID()]);
  const args=[gymA,created.subscription.id,created.subscription.version,true,'Wrong plan selected',randomUUID()];
  const deleted=await rpc('set_membership_deleted',args);
  assert.ok(deleted.subscription.deleted_at);assert.equal(deleted.subscription.status,'cancelled');
  assert.deepEqual(await rpc('set_membership_deleted',args),deleted);
  assert.equal((await rpc('member_invoice_payment_quote',[gymA,person])).invoices.length,0);
  await assert.rejects(()=>rpc('transition_subscription',[gymA,created.subscription.id,deleted.subscription.version,'extend',today,'Not restored',randomUUID(),1]),/Restore this deleted membership/);
  await db.exec('reset role');
  const invoice=(await db.query('select * from public.invoices where id=$1',[created.invoice.id])).rows[0];
  assert.equal(invoice.status,'voided');assert.equal(invoice.deleted_with_membership,created.subscription.id);
  await login(b);await assert.rejects(()=>rpc('set_membership_deleted',[gymA,created.subscription.id,deleted.subscription.version,false,'Not my gym',randomUUID()]),e=>e.code==='42501');
  await login(a);const restored=await rpc('set_membership_deleted',[gymA,created.subscription.id,deleted.subscription.version,false,'Correct plan after review',randomUUID()]);
  assert.equal(restored.subscription.deleted_at,null);assert.equal(restored.subscription.status,created.subscription.status);
  await rpc('post_payment',[gymA,created.invoice.id,100,'cash','Paid test',randomUUID()]);
  await assert.rejects(()=>rpc('set_membership_deleted',[gymA,created.subscription.id,restored.subscription.version,true,'Cannot erase payment',randomUUID()]),/payment, credit or activity history/);
  await db.exec('reset role');const scheduledMember=randomUUID();
  await db.query("insert into public.members(id,gym_id,full_name,phone,joining_date) values($1,$2,'Scheduled member','+971501234587',current_date)",[scheduledMember,gymA]);
  await login(a);const scheduled=await rpc('create_subscription',[gymA,scheduledMember,packageId,'2099-01-01',randomUUID()]);
  const cancelled=await rpc('transition_subscription',[gymA,scheduled.subscription.id,scheduled.subscription.version,'cancel',today,'Cancelled before start',randomUUID(),0]);
  assert.equal(cancelled.status,'cancelled');
});
await check('Stored invoices generate complete numbered documents without creating new charges; designs are isolated and permission checked',async()=>{
  await db.exec('reset role');const person=randomUUID();
  await db.query("insert into public.members(id,gym_id,full_name,phone,joining_date) values($1,$2,'Invoice recipient','+971501234586',current_date)",[person,gymA]);
  await login(a);const created=await rpc('create_subscription_discounted',[gymA,person,packageId,today,randomUUID(),1000,'Invoice test']);
  await rpc('post_payment',[gymA,created.invoice.id,1000,'cash','Invoice test payment',randomUUID()]);
  const first=await rpc('get_invoice_document',[gymA,created.invoice.id]);
  const second=await rpc('get_invoice_document',[gymA,created.invoice.id]);
  assert.equal(first.invoice_number,second.invoice_number);
  assert.ok(first.invoice_number>0);assert.ok(first.items.length>0);
  assert.equal(first.snapshot.paid_minor,1000);
  assert.equal(first.snapshot.balance_minor,first.snapshot.total_minor-1000);
  const html='<h1>Invoice {{invoice_number}}</h1>';
  const saved=await rpc('save_invoice_design',[gymA,html,0]);assert.equal(saved.version,1);
  await assert.rejects(()=>rpc('save_invoice_design',[gymA,'Stale design',0]),e=>e.code==='40001');
  await login(b);
  await assert.rejects(()=>rpc('get_invoice_document',[gymA,created.invoice.id]),e=>e.code==='42501');
  await assert.rejects(()=>rpc('save_invoice_design',[gymA,html,1]),e=>e.code==='42501');
  await login(trainer);await assert.rejects(()=>rpc('get_invoice_document',[gymA,created.invoice.id]),e=>e.code==='42501');
  await login(a);assert.equal((await rpc('get_invoice_document',[gymA,created.invoice.id])).snapshot.total_minor,first.snapshot.total_minor);
});
await check('Monthly and yearly reports use gym-local dates, include full results and preserve cross-period reversals',async()=>{
  const gym=randomUUID(),person=randomUUID(),janInvoice=randomUUID(),febInvoice=randomUUID(),oldPayment=randomUUID(),janPayment=randomUUID();
  await db.exec('reset role');
  await db.query("insert into public.gyms(id,name,timezone) values($1,'Report gym','Asia/Dubai')",[gym]);
  await db.query("insert into public.gym_users(gym_id,user_id,role) values($1,$2,'owner')",[gym,a]);
  await db.query("insert into public.members(id,gym_id,full_name,phone,joining_date) values($1,$2,'Report member','+971501234567','2026-01-01')",[person,gym]);
  await db.query("insert into public.members(id,gym_id,full_name,phone,joining_date) select gen_random_uuid(),$1,'Member '||n,'+971501234567','2026-01-01' from generate_series(1,1005) n",[gym]);
  await db.query("insert into public.invoices(id,gym_id,member_id,currency,total_minor,due_date,created_at) values($1,$2,$3,'AED',10000,'2026-01-31','2026-01-31 19:59:59+00'),($4,$2,$3,'AED',20000,'2026-02-01','2026-01-31 20:00:00+00')",[janInvoice,gym,person,febInvoice]);
  await db.query("insert into public.payments(id,gym_id,member_id,amount_minor,currency,method,idempotency_key,actor_id,created_at) values($1,$2,$3,2000,'AED','cash',gen_random_uuid(),$4,'2025-12-31 12:00+00'),($5,$2,$3,5000,'AED','cash',gen_random_uuid(),$4,'2026-01-31 19:59:59+00')",[oldPayment,gym,person,a,janPayment]);
  await db.query("insert into public.payment_reversals(gym_id,payment_id,kind,reason,actor_id,operation_id,created_at) values($1,$2,'refund','Older payment',$3,gen_random_uuid(),'2026-01-15 12:00+00'),($1,$4,'reversal','Later reversal',$3,gen_random_uuid(),'2026-02-15 12:00+00')",[gym,oldPayment,a,janPayment]);
  await login(a);
  const jan=await rpc('get_period_report',[gym,2026,1]);
  assert.equal(jan.start_date,'2026-01-01');assert.equal(jan.end_exclusive,'2026-02-01');
  assert.equal(jan.members.length,1006);assert.equal(jan.invoices.length,1);
  assert.equal(jan.invoices[0].id,janInvoice);assert.equal(jan.invoices[0].date,'2026-01-31');
  assert.equal(jan.payments.length,1);assert.equal(jan.payments[0].amount_minor,5000);assert.equal(jan.payments[0].reversed,true);
  assert.equal(jan.reversals.length,1);assert.equal(jan.reversals[0].amount_minor,2000);
  const feb=await rpc('get_period_report',[gym,2026,2]);
  assert.equal(feb.invoices[0].id,febInvoice);assert.equal(feb.payments.length,0);assert.equal(feb.reversals[0].amount_minor,5000);
  const annual=await rpc('get_period_report',[gym,2026,null]);
  assert.equal(annual.end_exclusive,'2027-01-01');assert.equal(annual.invoices.length,2);assert.equal(annual.reversals.length,2);
  const leap=await rpc('get_period_report',[gym,2024,2]);assert.equal(leap.end_exclusive,'2024-03-01');assert.deepEqual(leap.invoices,[]);
  await assert.rejects(()=>rpc('get_period_report',[gym,2026,13]));
  await assert.rejects(()=>rpc('get_period_report',[gym,null,1]));
  await login(b);await assert.rejects(()=>rpc('get_period_report',[gym,2026,null]),e=>e.code==='42501');
  await login(trainer);await assert.rejects(()=>rpc('get_period_report',[gym,2026,null]),e=>e.code==='42501');
  await db.exec('reset role');
  await db.query("insert into public.gym_users(gym_id,user_id,role,access_options) values($1,$2,'manager','{\"operations\":false}')",[gym,b]);
  await login(b);await assert.rejects(()=>rpc('get_period_report',[gym,2026,null]),e=>e.code==='42501');
  await login(a);
});
console.log(`${passed} database integration checks passed. Hosted Auth, Realtime and Storage were stubbed.`);
await db.close();
