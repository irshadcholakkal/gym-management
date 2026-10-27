import { spawn } from 'node:child_process';
import { access, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
process.chdir(root);

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: 'inherit', shell: false });
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(new Error(`${path.basename(command)} exited with code ${code}`)));
  });
}

export function publicConfig(env) {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_PUBLISHABLE_KEY || env.SUPABASE_ANON_KEY;
  if (!url || !key) throw new Error('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in Vercel Project Settings > Environment Variables, then redeploy.');
  const parsedUrl = new URL(url);
  if (parsedUrl.protocol !== 'https:') throw new Error('SUPABASE_URL must use HTTPS.');
  if (!key.startsWith('sb_publishable_')) {
    let role;
    try { role = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role; } catch { /* rejected below */ }
    if (role !== 'anon') throw new Error('Only a public publishable/anonymous key may be included in Flutter. Server secret keys are forbidden.');
  }
  const config = { SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: key };
  const origin = env.VERCEL_PROJECT_PRODUCTION_URL || env.VERCEL_URL;
  if (env.AUTH_REDIRECT_URL || origin) config.AUTH_REDIRECT_URL = env.AUTH_REDIRECT_URL || `https://${origin}/#/recovery`;
  if (env.VAPID_PUBLIC_KEY) config.VAPID_PUBLIC_KEY = env.VAPID_PUBLIC_KEY;
  return config;
}

async function main() {
  // Read only explicitly public settings. Never export process.env or .env.
  const config = publicConfig(process.env);
  const flutterVersion = '3.47.2';
  const sdk = process.env.FLUTTER_SDK_PATH || path.join(root, '.vercel-flutter');
  if (process.platform === 'win32' && !process.env.FLUTTER_SDK_PATH) throw new Error('For local Windows validation, set FLUTTER_SDK_PATH to your initialized Flutter SDK. Vercel installs its own Linux SDK.');
  const flutter = path.join(sdk, 'bin', process.platform === 'win32' ? 'flutter.bat' : 'flutter');
  try { await access(flutter); }
  catch {
    await run('git', ['clone', '--depth', '1', '--branch', flutterVersion, 'https://github.com/flutter/flutter.git', sdk]);
  }
  const runFlutter = args => process.platform === 'win32'
    ? run(path.join(sdk, 'bin', 'cache', 'dart-sdk', 'bin', 'dart.exe'), [
      `--packages=${path.join(sdk, 'packages', 'flutter_tools', '.dart_tool', 'package_config.json')}`,
      path.join(sdk, 'bin', 'cache', 'flutter_tools.snapshot'), ...args,
    ])
    : run(flutter, args);
  await runFlutter(['config', '--no-analytics']);
  await runFlutter(['--version']);
  await runFlutter(['pub', 'get']);
  const configPath = path.join(root, '.dart_tool', 'vercel-public-config.json');
  await mkdir(path.dirname(configPath), { recursive: true });
  await writeFile(configPath, JSON.stringify(config));
  await runFlutter(['build', 'web', '--release', '--pwa-strategy=none', '--no-web-resources-cdn', '--no-wasm-dry-run', `--dart-define-from-file=${configPath}`]);
  await run(process.execPath, ['tool/prepare_web.mjs']);
  await access(path.join(root, 'build', 'web', 'index.html'));
  console.log('Vercel static output ready: build/web');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
