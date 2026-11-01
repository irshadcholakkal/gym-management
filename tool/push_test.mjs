import test from 'node:test';
import assert from 'node:assert/strict';
import { createECDH, webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { validateVapidPublicKey } from './validate_vapid.mjs';
import { publicConfig } from './vercel_build.mjs';

function keyPair() {
  const ec = createECDH('prime256v1');
  ec.generateKeys();
  return ec.getPublicKey().toString('base64url');
}
const key = keyPair();
function browser({ existing = null, error = null } = {}) {
  const calls = { permissions: 0, subscribe: 0 };
  const manager = {
    getSubscription: async () => existing,
    subscribe: async options => {
      calls.subscribe++;
      assert.deepEqual(Buffer.from(options.applicationServerKey), Buffer.from(key, 'base64url'));
      if (error) throw error;
      return { toJSON: () => ({ endpoint: 'https://push.example/subscription' }) };
    },
  };
  const context = vm.createContext({
    window: { PushManager: {}, Notification: {}, isSecureContext: true, addEventListener() {} },
    navigator: { serviceWorker: { ready: Promise.resolve({ pushManager: manager }) } },
    Notification: { permission: 'default', requestPermission: async () => { calls.permissions++; return 'granted'; } },
    crypto: webcrypto, Uint8Array, atob,
  });
  vm.runInContext(readFileSync(new URL('../web/pwa.js', import.meta.url), 'utf8'), context);
  return { subscribe: context.window.gymproPushSubscribe, calls };
}

test('build accepts valid public keys and rejects placeholders, private keys, and invalid curve points', () => {
  assert.equal(validateVapidPublicKey(` ${key}\n`), key);
  assert.equal(validateVapidPublicKey(''), '');
  for (const bad of ['YOUR_PUBLIC_VAPID_KEY', Buffer.alloc(32).toString('base64url'), Buffer.concat([Buffer.from([4]), Buffer.alloc(64)]).toString('base64url')]) {
    assert.throws(() => validateVapidPublicKey(bad), /VAPID_PUBLIC_KEY/);
    assert.throws(() => publicConfig({ SUPABASE_URL: 'https://test.supabase.co', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_example', VAPID_PUBLIC_KEY: bad }), /VAPID_PUBLIC_KEY/);
  }
});
test('browser rejects invalid key before asking permission or subscribing', async () => {
  for (const bad of ['', 'YOUR_PUBLIC_VAPID_KEY', Buffer.concat([Buffer.from([4]), Buffer.alloc(64)]).toString('base64url')]) {
    const app = browser();
    await assert.rejects(app.subscribe(bad), /configured/);
    assert.equal(app.calls.permissions, 0);
    assert.equal(app.calls.subscribe, 0);
  }
});
test('browser subscribes with decoded public key', async () => {
  const app = browser();
  assert.equal(JSON.parse(await app.subscribe(` ${key} `)).endpoint, 'https://push.example/subscription');
  assert.equal(app.calls.subscribe, 1);
});
test('browser reuses a subscription for the configured key', async () => {
  const app = browser({ existing: { options: { applicationServerKey: Buffer.from(key, 'base64url') }, toJSON: () => ({ endpoint: 'existing' }) } });
  assert.equal(JSON.parse(await app.subscribe(key)).endpoint, 'existing');
  assert.equal(app.calls.subscribe, 0);
});
test('browser replaces subscriptions from a previous key', async () => {
  let removed = false;
  const app = browser({ existing: { options: { applicationServerKey: Buffer.from(keyPair(), 'base64url') }, unsubscribe: async () => { removed = true; return true; } } });
  await app.subscribe(key);
  assert.equal(removed, true);
  assert.equal(app.calls.subscribe, 1);
});
test('browser translates InvalidAccessError to actionable configuration message', async () => {
  const app = browser({ error: Object.assign(new Error('browser internals'), { name: 'InvalidAccessError' }) });
  await assert.rejects(app.subscribe(key), /valid VAPID public key and rebuild/);
});
