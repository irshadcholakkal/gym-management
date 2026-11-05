// PWA regression with a simulated backend; no production requests or accounts.
import { chromium } from 'playwright';
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../build/web/',import.meta.url));
const config=JSON.parse(await readFile(new URL('../../config.local.json',import.meta.url),'utf8'));
const backend=new URL(config.SUPABASE_URL).origin;
const mime={'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.png':'image/png','.otf':'font/otf','.ttf':'font/ttf'};
const server=http.createServer(async(req,res)=>{
 try { const url=new URL(req.url,'http://localhost'); const file=path.resolve(root,'.'+(url.pathname==='/'?'/index.html':url.pathname));
  if(!file.startsWith(root)){res.writeHead(403).end();return;}
  res.writeHead(200,{'Content-Type':mime[path.extname(file)]??'application/octet-stream'}).end(await readFile(file));
 } catch {res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(8099,'127.0.0.1',resolve));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const gym=id(1), userId=id(2), now=new Date().toISOString();
const user={id:userId,aud:'authenticated',role:'authenticated',email:'owner@example.test',created_at:now,app_metadata:{provider:'email',providers:['email']},user_metadata:{full_name:'Test Owner'}};
const jwt=[{alg:'HS256',typ:'JWT'},{sub:userId,aud:'authenticated',role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}].map(v=>Buffer.from(JSON.stringify(v)).toString('base64url')).join('.')+'.test-signature';
const session={access_token:jwt,refresh_token:'test-refresh-token',token_type:'bearer',expires_in:3600,user};
const records=Array.from({length:3000},(_,i)=>({kind:'members',record_id:id(i+10),payload:{id:id(i+10),gym_id:gym,full_name:`Member ${String(i).padStart(4,'0')}`,phone:'+971501234567',joining_date:'2026-01-01',status:'active',version:1}}));
let logins=0,refreshes=0,pulls=0,expired=false,offline=false;
const errors=[];
const browser=await chromium.launch({channel:'chrome',headless:true});
let page;
try {
 page=await browser.newPage({viewport:{width:1280,height:900}});
 page.on('pageerror',e=>errors.push(e.message));
 page.on('console',m=>{if(m.type()==='error')console.error('Browser:',m.text());});
 const text=value=>page.getByText(value,{exact:true}).or(page.getByLabel(value,{exact:true})).first();
 const typeInto=async(locator,value)=>{await locator.click();await page.waitForTimeout(150);await page.keyboard.press('ControlOrMeta+A');await page.keyboard.type(value);await page.keyboard.press('Tab');};
 await page.routeWebSocket(backend.replace('https:','wss:')+'/**',ws=>ws.close());
 await page.route(backend+'/**',async route=>{
  const req=route.request(),url=new URL(req.url());
  const fulfill=(body,status=200)=>route.fulfill({status,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify(body)});
  if(req.method()==='OPTIONS'){await route.fulfill({status:204,headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*'}});return;}
  if(url.pathname==='/auth/v1/token') {if(url.searchParams.get('grant_type')==='refresh_token')refreshes++;else logins++;await fulfill(session);}
  else if(url.pathname==='/auth/v1/user')await fulfill(user);
  else if(url.pathname==='/rest/v1/gym_users')await fulfill([{gym_id:gym,user_id:userId,role:'owner',active:true,gyms:{name:'Stress Test Gym'}}]);
  else if(url.pathname==='/rest/v1/rpc/pull_changes'){
   pulls++;
   if(offline){offline=false;await route.abort('internetdisconnected');return;}
   if(expired){expired=false;await fulfill({code:'PGRST303',message:'JWT expired'},401);return;}
   const cursor=req.postDataJSON().p_cursor;
   await fulfill({changes:records.slice(cursor,cursor+250),cursor:Math.min(cursor+250,records.length),has_more:cursor+250<records.length});
  } else await fulfill([]);
 });
 await page.goto('http://127.0.0.1:8099');
 await page.waitForSelector('flt-semantics-placeholder', {state:'attached',timeout:60000});
 await page.evaluate(()=>document.querySelector('flt-semantics-placeholder').click());
 await typeInto(page.getByRole('textbox',{name:'Email, employee ID or username',exact:true}),'owner@example.test');
 await typeInto(page.getByLabel('Password',{exact:true}),'test-password');
 await page.getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByRole('button',{name:'Members',exact:true}).first().waitFor({timeout:60000});
 console.log('Signed in; testing member navigation.');
 page.setDefaultTimeout(10000);
 await page.waitForFunction(()=>true);
 await page.evaluate(()=>{window.__ticks=[];let last=performance.now();window.__heartbeat=setInterval(()=>{const now=performance.now();window.__ticks.push(now-last);last=now;},20);});
 for(let i=0;i<3;i++){
  console.log('Opening members',i);
  await page.getByRole('button',{name:'Members',exact:true}).first().click();
  await text('3000 records - Page 1').waitFor({timeout:60000});
  console.log('Paging forward',i);
  await page.getByRole('button',{name:'Next page',exact:true}).click();
  await text('3000 records - Page 2').waitFor();
  console.log('Paging back',i);
  await page.getByRole('button',{name:'Previous page',exact:true}).click();
  await text('3000 records - Page 1').waitFor();
  console.log('Opening overview',i);
  await page.getByRole('button',{name:'Overview',exact:true}).first().click();
 }
 console.log('Navigation passed; testing token recovery.');
 const before=pulls;
 expired=true;
 await page.evaluate(()=>window.dispatchEvent(new Event('online')));
 await page.waitForFunction(()=>true);
 await new Promise(async(resolve,reject)=>{const start=Date.now();const timer=setInterval(()=>{if(refreshes>0&&pulls>=before+2){clearInterval(timer);resolve();}else if(Date.now()-start>30000){clearInterval(timer);reject(Error('Token refresh did not resume sync'));}},50);});
 const afterRefresh=pulls;
 offline=true;
 await page.evaluate(()=>window.dispatchEvent(new Event('online')));
 const offlineUntil=Date.now()+30000;
 while(pulls===afterRefresh&&Date.now()<offlineUntil)await new Promise(r=>setTimeout(r,50));
 assert.ok(pulls>afterRefresh,'Offline sync attempt was not started');
 await page.waitForTimeout(500);
 await page.evaluate(()=>window.dispatchEvent(new Event('online')));
 const until=Date.now()+30000;
 while(pulls<afterRefresh+2&&Date.now()<until)await new Promise(r=>setTimeout(r,50));
 assert.ok(pulls>=afterRefresh+2,'Sync must recover after connectivity returns');
 assert.equal(logins,1,'Recovery must not need another login');
 await page.getByRole('button',{name:'Members',exact:true}).first().click();
 await text('3000 records - Page 1').waitFor();
 const maxGap=await page.evaluate(()=>{clearInterval(window.__heartbeat);return Math.max(...window.__ticks);});
 assert.ok(maxGap<5000,`Main thread stalled for ${Math.round(maxGap)}ms`);
 assert.deepEqual(errors,[]);
 console.log(JSON.stringify({members:3000,navigationCycles:3,logins,refreshes,pulls,maxHeartbeatGapMs:Math.round(maxGap),errors}));
} catch(error) { console.error('Browser failure:',error,'Requests:',{logins,refreshes,pulls},'Errors:',errors); throw error; } finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
