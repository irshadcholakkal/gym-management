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
  create schema auth; create table auth.users(id uuid primary key,email_confirmed_at timestamptz,raw_user_meta_data jsonb not null default '{}');
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
console.log(`${passed} database integration checks passed. Hosted Auth, Realtime and Storage were stubbed.`);
await db.close();
