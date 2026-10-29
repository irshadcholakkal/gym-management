// Browser regression/visual QA against an explicitly simulated backend. No
// production accounts are used and every Supabase HTTP/WebSocket is intercepted.
import { chromium } from 'playwright';
import http from 'node:http';
import { readFile,mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../build/web/',import.meta.url));
const config=JSON.parse(await readFile(new URL('../../config.local.json',import.meta.url),'utf8'));
const backend=new URL(config.SUPABASE_URL).origin;
const mime={'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.png':'image/png','.otf':'font/otf','.ttf':'font/ttf'};
const server=http.createServer(async(req,res)=>{
 try {const p=decodeURIComponent(new URL(req.url,'http://localhost').pathname),file=path.resolve(root,'.'+(p==='/'?'/index.html':p));if(!file.startsWith(root)){res.writeHead(403).end();return;}res.writeHead(200,{'Content-Type':mime[path.extname(file)]??'application/octet-stream'}).end(await readFile(file));}
 catch {res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(8098,'127.0.0.1',resolve));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const gym=id(1),userId=id(2),member=id(3),plan=id(4),subscription=id(5),invoice=id(6);
const today=new Date(Date.now()+4*3600000).toISOString().slice(0,10),now=new Date().toISOString();
const end=new Date(Date.now()+34*86400000).toISOString().slice(0,10);
const records=[
 ['members',{id:member,gym_id:gym,full_name:'Amina Ali',phone:'+971501234567',joining_date:today,status:'active'}],
 ['membership_packages',{id:plan,gym_id:gym,name:'Monthly Fitness',description:'Full gym access',price_minor:15000,currency:'AED',duration_value:1,duration_unit:'months',enrollment_fee_minor:0,tax_basis_points:0,status:'active'}],
 ['subscriptions',{id:subscription,gym_id:gym,member_id:member,package_id:plan,package_snapshot:{name:'Monthly Fitness'},start_date:today,end_exclusive:end,status:'active'}],
 ['invoices',{id:invoice,gym_id:gym,member_id:member,subscription_id:subscription,total_minor:10000,subtotal_minor:15000,discount_minor:5000,discount_reason:'Loyalty discount',discount_granted_at:now,paid_minor:0,credit_minor:0,currency:'AED',due_date:today,created_at:now,status:'unpaid'}],
].map(([kind,payload])=>({kind,record_id:payload.id,payload:{...payload,version:1}}));
const user={id:userId,aud:'authenticated',role:'authenticated',email:'owner@example.test',email_confirmed_at:now,created_at:now,app_metadata:{provider:'email',providers:['email']},user_metadata:{full_name:'Test Owner'}};
const jwt=[{alg:'HS256',typ:'JWT'},{sub:userId,aud:'authenticated',role:'authenticated',exp:Math.floor(Date.now()/1000)+3600},'test-signature'].map((v,i)=>i===2?v:Buffer.from(JSON.stringify(v)).toString('base64url')).join('.');
const session={access_token:jwt,refresh_token:'test-refresh-token',token_type:'bearer',expires_in:3600,user};
const browser=await chromium.launch({channel:'chrome',headless:true});
let submitted,failNext=true, photoBytes=0;
let page;const errors=[];
try {
 page=await browser.newPage({viewport:{width:1600,height:1200}});
 const typeInto=async(locator,value)=>{await locator.click();await page.keyboard.press('ControlOrMeta+A');await page.keyboard.type(value);await page.keyboard.press('Tab');};
 page.on('pageerror',e=>errors.push(e.message));
 await page.routeWebSocket(backend.replace('https:','wss:')+'/**',ws=>ws.close());
 await page.route(backend+'/**',async route=>{
  const request=route.request(),url=new URL(request.url());let data;
  if(request.method()==='OPTIONS'){await route.fulfill({status:204,headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*'}});return;}
  if(url.pathname==='/auth/v1/token')data=session;
  else if(url.pathname==='/auth/v1/user')data=user;
  else if(url.pathname==='/rest/v1/gym_users')data=[{gym_id:gym,user_id:userId,role:'owner',active:true,gyms:{name:'Community Fitness'}}];
  else if(url.pathname==='/rest/v1/rpc/pull_changes')data={changes:request.postDataJSON().p_cursor===0?records:[],cursor:1,has_more:false};
  else if(url.pathname.startsWith('/storage/v1/object/member-photos/')) { photoBytes=request.postDataBuffer()?.length??0; data={Key:'photo'}; }
  else if(url.pathname.startsWith('/storage/v1/object/sign/member-photos/') && request.method()==='GET') { await route.fulfill({status:200,contentType:'image/png',headers:{'access-control-allow-origin':'*'},body:await readFile(path.join(root,'icons/Icon-192.png'))});return; }
  else if(url.pathname.startsWith('/storage/v1/object/sign/member-photos/')) data={signedURL:'/object/sign/member-photos/test.jpg?token=test'};
  else if(url.pathname==='/rest/v1/rpc/set_member_photo') { const args=request.postDataJSON(); data={...records[0].payload,profile_image:args.p_path,version:2}; records[0].payload=data; }
  else if(url.pathname==='/rest/v1/rpc/create_subscription_discounted') {
   submitted=request.postDataJSON();
   if(failNext){failNext=false;await route.fulfill({status:400,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify({code:'P0001',message:'Enter a reason for the discount'})});return;}
   data={subscription:records[2].payload,invoice:records[3].payload};
  }else data=[];
  await route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify(data)});
 });
 await page.goto('http://127.0.0.1:8098');
 await typeInto(page.getByRole('textbox',{name:'Work email',exact:true}),'owner@example.test');
 await typeInto(page.getByLabel('Password',{exact:true}),'test-password');
 await page.getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByText(/Discounts given this month/).first().waitFor({timeout:30000});
 await page.getByText(/AED 50.00/).first().waitFor({timeout:30000});
 await mkdir(new URL('../../artifacts/',import.meta.url),{recursive:true});
 await page.screenshot({path:fileURLToPath(new URL('../../artifacts/dashboard-updated.png',import.meta.url)),fullPage:true});
 await page.getByRole('button',{name:'Memberships',exact:true}).first().click();
 await page.getByText(/Amina Ali.*Monthly Fitness/).or(page.getByLabel(/Amina Ali.*Monthly Fitness/)).first().waitFor();
 await page.screenshot({path:fileURLToPath(new URL('../../artifacts/memberships-updated.png',import.meta.url)),fullPage:true});
 await page.getByRole('button',{name:'Payments',exact:true}).first().click();
 await page.getByText(/Invoice.*Amina Ali/).or(page.getByLabel(/Invoice.*Amina Ali/)).first().waitFor();
 await page.screenshot({path:fileURLToPath(new URL('../../artifacts/invoices-updated.png',import.meta.url)),fullPage:true});
 await page.getByRole('button',{name:'Memberships',exact:true}).first().click();
 await page.getByRole('button',{name:'Renew membership',exact:true}).click();
 await typeInto(page.getByRole('textbox',{name:/Special discount/}),'25.00');
 await typeInto(page.getByRole('textbox',{name:'Discount reason',exact:true}),'Loyalty offer');
 await page.getByText(/Total due: AED 125.00/).first().waitFor();
 await page.screenshot({path:fileURLToPath(new URL('../../artifacts/renewal-discount.png',import.meta.url)),fullPage:true});
 await page.getByRole('button',{name:'Renew membership',exact:true}).click();
 await page.getByText(/Enter a reason for the discount/).first().waitFor();
 assert.ok(await page.getByRole('textbox',{name:/Special discount/}).isEnabled(),'Definitive errors must leave fields editable');
 await page.getByRole('button',{name:'Renew membership',exact:true}).click();
 await page.getByRole('textbox',{name:/Special discount/}).waitFor({state:'detached'});
 assert.equal(submitted.p_discount_minor,2500);assert.equal(submitted.p_discount_reason,'Loyalty offer');assert.equal(submitted.p_start,end);
 await page.getByRole('button',{name:'Members',exact:true}).first().click();
 await page.getByText(/Amina Ali/).or(page.getByLabel(/Amina Ali/)).first().click();
 await page.getByRole('button',{name:'Add profile photo',exact:true}).waitFor();
 const chooser=page.waitForEvent('filechooser');
 await page.getByRole('button',{name:'Add profile photo',exact:true}).click();
 await (await chooser).setFiles({name:'profile.png',mimeType:'image/png',buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==','base64')});
 await page.getByText(/Photo saved/).waitFor({timeout:30000});
 assert.ok(photoBytes>0 && photoBytes<153600);
 await page.getByRole('button',{name:'Change profile photo',exact:true}).waitFor();
 await page.waitForTimeout(500);
 await page.screenshot({path:fileURLToPath(new URL('../../artifacts/member-photo.png',import.meta.url)),fullPage:true});
 await page.getByRole('button',{name:'Close',exact:true}).click();
 await page.setViewportSize({width:390,height:844});await page.waitForTimeout(500);
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=390),'Mobile layout must not overflow');
 await page.screenshot({path:fileURLToPath(new URL('../../artifacts/memberships-mobile.png',import.meta.url)),fullPage:true});
 assert.deepEqual(errors,[]);
 console.log('PASS Simulated authenticated dashboard, names, renewal discount payload, editable server errors, compressed profile photo upload, and responsive layout.');
} catch(error){if(page){await page.screenshot({path:fileURLToPath(new URL('../../artifacts/workspace-failure.png',import.meta.url)),fullPage:true});console.error('Page:',page.url(),'Errors:',errors);console.error((await page.content()).slice(-12000));}throw error;}
finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
