import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
function app(nav = {}, standalone = false) {
  const events = {};
  const window = { addEventListener: (name, handler) => events[name] = handler, matchMedia: () => ({ matches: standalone }) };
  vm.runInNewContext(readFileSync(new URL('../web/pwa.js', import.meta.url), 'utf8'), { window, navigator: nav, setTimeout, clearTimeout });
  return { window, events };
}
test('install prompt is captured and used once; dismissal allows manual guidance', async () => {
  const { window, events } = app();
  let prevented = false, prompted = 0;
  events.beforeinstallprompt({ preventDefault: () => prevented = true, prompt: async () => prompted++, userChoice: Promise.resolve({ outcome: 'dismissed' }) });
  assert.equal(prevented, true);
  assert.equal(window.gymproInstallState(), 'ready');
  assert.equal(await window.gymproInstallApp(), 'dismissed');
  assert.equal(prompted, 1);
  assert.equal(await window.gymproInstallApp(), 'manual');
});
test('installed and standalone apps do not offer another installation', async () => {
  const a = app({}, true);
  assert.equal(a.window.gymproInstallState(), 'installed');
  assert.equal(await a.window.gymproInstallApp(), 'installed');
  const b = app(); b.events.appinstalled();
  assert.equal(b.window.gymproInstallState(), 'installed');
});
test('manual installation guidance matches iPhone, desktop-mode iPad, Android and Mac', async () => {
  for (const [nav, expected] of [[{ userAgent: 'iPhone' }, 'ios'], [{ platform: 'MacIntel', maxTouchPoints: 5 }, 'ios'], [{ userAgent: 'Android' }, 'android'], [{ platform: 'MacIntel' }, 'mac']]) {
    assert.equal(await app(nav).window.gymproInstallApp(), expected);
  }
});

test('Checking an update never activates it until the user chooses install', async () => {
  let activated = 0;
  const registration = { waiting: null, installing: null, update: async () => {} };
  const { window } = app({ serviceWorker: { getRegistration: async () => registration } });
  assert.equal(await window.gymproAppUpdate(false), 'current');
  registration.waiting = { postMessage: message => { assert.equal(message.type, 'ACTIVATE_UPDATE'); activated++; } };
  assert.equal(await window.gymproAppUpdate(false), 'ready');
  assert.equal(activated, 0);
  assert.equal(await window.gymproAppUpdate(true), 'applying');
  assert.equal(activated, 1);
});
test('Update check handles missing support and surfaces connectivity failures', async () => {
  assert.equal(await app().window.gymproAppUpdate(false), 'unsupported');
  assert.equal(await app({ serviceWorker: { getRegistration: async () => undefined } }).window.gymproAppUpdate(false), 'unavailable');
  const { window } = app({ serviceWorker: { getRegistration: async () => ({ update: async () => { throw new Error('offline'); } }) } });
  await assert.rejects(window.gymproAppUpdate(false), /offline/);
});
