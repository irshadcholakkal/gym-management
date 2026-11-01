import { testPushHandler } from './handler.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
const gym='00000000-0000-0000-0000-000000000001';
const endpoint='https://fcm.googleapis.com/fcm/send/test-device';
function assert(value:unknown,message='Assertion failed'): asserts value { if(!value)throw new Error(message); }
function setup({exists=true,expired=false,authenticated=true,target=endpoint}={}) {
  let sent=0,removed=0;
  const filters:Record<string,unknown>={};
  const subscription={endpoint:target,keys:{auth:'test-auth',p256dh:'test-key'}};
  const query={select(){return query;},eq(key:string,value:unknown){filters[key]=value;return query;},maybeSingle:async()=>({data:exists?subscription:null,error:null})};
  const client={auth:{getUser:async()=>({data:{user:authenticated?{id:'user-one'}:null},error:null})},from:()=>query,rpc:async(name:string,args:Record<string,unknown>)=>{assert(name==='remove_push');assert(args.p_gym===gym);assert(args.p_endpoint===endpoint);removed++;return {error:null};}};
  const handler=testPushHandler({
    createClient:(()=>client) as unknown as typeof createClient,
    push:{...webpush,setVapidDetails:()=>{},sendNotification:async(_subscription:unknown,payload?:string)=>{sent++;assert(JSON.parse(payload!).type==='test');if(expired)throw {statusCode:410};return {} as never;}},
    env:name=>({SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'public-test',VAPID_PUBLIC_KEY:'public',VAPID_PRIVATE_KEY:'private',VAPID_SUBJECT:'mailto:test@example.com'} as Record<string,string>)[name],
  });
  const request=(authorized=true)=>handler(new Request('https://example.test',{method:'POST',headers:authorized?{Authorization:'Bearer test'}:{},body:JSON.stringify({gym_id:gym,endpoint})}));
  return {request,filters,sent:()=>sent,removed:()=>removed};
}
Deno.test('Push test requires an authenticated user',async()=>{
  const a=setup();assert((await a.request(false)).status===401);assert(a.sent()===0);
  const b=setup({authenticated:false});assert((await b.request()).status===401);assert(b.sent()===0);
});
Deno.test('Push test targets only this account and its registered device',async()=>{
  const app=setup();assert((await app.request()).status===200);assert(app.sent()===1);
  assert(app.filters.user_id==='user-one');assert(app.filters.gym_id===gym);assert(app.filters.endpoint===endpoint);assert(app.filters.enabled===true);
});
Deno.test('Unregistered devices and unsupported providers do not receive a test',async()=>{
  const missing=setup({exists:false});assert((await missing.request()).status===409);assert(missing.sent()===0);
  const unsafe=setup({target:'https://example.com/private'});assert((await unsafe.request()).status===400);assert(unsafe.sent()===0);
});
Deno.test('Expired push subscriptions are disabled for the same account',async()=>{
  const app=setup({expired:true});assert((await app.request()).status===410);assert(app.removed()===1);
});
