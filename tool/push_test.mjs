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
function browser({ existing = null, error = null, permission = 'default' } = {}) {
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
    navigator: { serviceWorker: { ready: Promise.resolve({ pushManager: manager }), getRegistration: async () => ({ pushManager: manager }) } },
    Notification: { permission, requestPermission: async () => { calls.permissions++; return 'granted'; } },
    crypto: webcrypto, Uint8Array, atob,
  });
  vm.runInContext(readFileSync(new URL('../web/pwa.js', import.meta.url), 'utf8'), context);
  return { subscribe: context.window.gymproPushSubscribe, status: context.window.gymproPushStatus, calls };
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

test('Reading push state does not request permission or create a subscription', async () => {
  const app = browser({ permission: 'granted', existing: { toJSON: () => ({ endpoint: 'existing-device' }) } });
  const state = JSON.parse(await app.status());
  assert.equal(state.permission, 'granted');
  assert.equal(state.subscription.endpoint, 'existing-device');
  assert.equal(app.calls.permissions, 0);
  assert.equal(app.calls.subscribe, 0);
  assert.equal(JSON.parse(await browser({ permission: 'denied' }).status()).permission, 'denied');
  assert.equal(JSON.parse(await browser().status()).subscription, null);
});

test('Service worker displays a distinct test notification from a server test payload', async () => {
  const events = {}, shown = [];
  const context = vm.createContext({
    self: { location: { href: 'https://gym.example/gympro-sw.js' }, addEventListener: (name, handler) => events[name] = handler,
      registration: { showNotification: async (title, options) => shown.push({ title, options }) } },
    URL, URLSearchParams,
  });
  vm.runInContext(readFileSync(new URL('../web/gympro-sw.js', import.meta.url), 'utf8'), context);
  let pending;
  events.push({ data: { json: () => ({ type: 'test', gym_id: '00000000-0000-0000-0000-000000000001' }) }, waitUntil: promise => pending = promise });
  await pending;
  assert.equal(shown.length, 1);
  assert.match(shown[0].options.body, /Test successful/);
  assert.match(shown[0].options.data.url, /notifications/);
});

test('Device display check uses the active worker without creating a subscription', async () => {
  const shown = [];
  const context = vm.createContext({
    window: { Notification: {}, isSecureContext: true, addEventListener() {} },
    Notification: { permission: 'granted' },
    navigator: { serviceWorker: { getRegistration: async () => ({
      active: {}, scope: 'https://gym.example/app/',
      showNotification: async (title, options) => shown.push({ title, options }),
    }) } }, URL,
  });
  vm.runInContext(readFileSync(new URL('../web/pwa.js', import.meta.url), 'utf8'), context);
  await context.window.gymproPushTestDisplay();
  assert.equal(shown.length, 1);
  assert.match(shown[0].options.body, /Device display test/);
  assert.equal(shown[0].options.data.url, 'https://gym.example/app/#/notifications');
  context.Notification.permission = 'denied';
  await assert.rejects(context.window.gymproPushTestDisplay(), /Allow notifications/);
  assert.equal(shown.length, 1);
});
