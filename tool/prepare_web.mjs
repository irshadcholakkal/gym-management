import { readFile,writeFile,readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
const root=new URL('../build/web/',import.meta.url);
async function files(dir) {
  const entries=await readdir(new URL(dir,root),{withFileTypes:true});
  const output=[];
  for(const entry of entries) {
    const name=dir+entry.name;
    if(entry.isDirectory()) output.push(...await files(name+'/'));
    else output.push(name);
  }
  return output;
}
const assets=['index.html','flutter_bootstrap.js','flutter.js','main.dart.js','manifest.json','favicon.png','pwa.js','sqlite3.wasm','drift_worker.dart.js',
  ...await files('assets/'),...await files('icons/'),
  'canvaskit/canvaskit.js','canvaskit/canvaskit.wasm','canvaskit/chromium/canvaskit.js','canvaskit/chromium/canvaskit.wasm'];
const worker=new URL('gympro-sw.js',root);
let source=await readFile(worker,'utf8');
source=source.replace(/const CACHE = '[^']+';/,`const CACHE = 'gympro-shell-${Date.now()}-${randomUUID().slice(0,8)}';`)
  .replace(/const ASSETS = \[[\s\S]*?\];/,`const ASSETS = ${JSON.stringify(assets)};`);
await writeFile(worker,source);
console.log(`Prepared versioned offline shell with ${assets.length} public assets.`);
