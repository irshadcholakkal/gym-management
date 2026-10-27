import { chromium } from 'playwright';
import http from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../build/web/',import.meta.url));
const mime={'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.png':'image/png','.otf':'font/otf'};
const server=http.createServer(async(req,res)=>{
  try{
    const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    const file=path.resolve(root,'.'+(pathname==='/'?'/index.html':pathname));
    if(!file.startsWith(root)) {res.writeHead(403).end();return;}
    const data=await readFile(file);res.writeHead(200,{'Content-Type':mime[path.extname(file)]??'application/octet-stream','Cache-Control':'no-cache'}).end(data);
  }catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(8097,'127.0.0.1',resolve));
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1000}});
const page=await context.newPage();
const errors=[];page.on('pageerror',e=>errors.push(e.message));
await mkdir(new URL('../../artifacts/',import.meta.url),{recursive:true});
page.on('console',m=>{if(m.type()==='error')console.log('Browser console:',m.text());});
try{
  await page.goto('http://127.0.0.1:8097');
  await page.waitForFunction(()=>document.querySelector('flutter-view'),null,{timeout:60000});
  // Flutter renders through canvas. Enable its semantics tree for accessibility.
  await page.getByLabel(/Welcome to GymPro UAE/).first().waitFor({timeout:30000});
  await page.evaluate(async()=>{await navigator.serviceWorker.ready;});
  await page.waitForTimeout(1000);
  const shell=await page.evaluate(async()=>{
    const names=await caches.keys(); const cache=await caches.open(names.find(n=>n.startsWith('gympro-shell-')));
    return (await cache.keys()).map(r=>new URL(r.url).pathname);
  });
  assert.ok(shell.includes('/main.dart.js')); assert.ok(shell.includes('/sqlite3.wasm')); assert.ok(shell.includes('/drift_worker.dart.js'));
  await mkdir(new URL('../../artifacts/',import.meta.url),{recursive:true});
  await page.screenshot({path:fileURLToPath(new URL('../../artifacts/setup-desktop.png',import.meta.url)),fullPage:true});
  await context.setOffline(true);
  await page.reload({waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>document.querySelector('flutter-view'),null,{timeout:60000});
  await page.getByLabel(/Welcome to GymPro UAE/).first().waitFor({timeout:30000});
  console.log('PASS Installed shell reopens offline; SQLite assets are precached.');
  await page.setViewportSize({width:390,height:844});
  await page.waitForFunction(()=>document.querySelector('flutter-view')?.getBoundingClientRect().width===390);
  await page.waitForTimeout(250);
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=390),'Mobile layout must not overflow horizontally');
  await page.screenshot({path:fileURLToPath(new URL('../../artifacts/setup-mobile.png',import.meta.url)),fullPage:true});
  assert.deepEqual(errors,[]);console.log('PASS Desktop/mobile setup loads without uncaught browser errors.');
} catch(error) {
  await page.screenshot({path:fileURLToPath(new URL('../../artifacts/browser-failure.png',import.meta.url)),fullPage:true});
  console.error('Uncaught browser errors:',errors);
  console.error((await page.content()).slice(-8000));
  throw error;
} finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
