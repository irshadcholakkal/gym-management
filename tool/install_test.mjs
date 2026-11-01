import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
function app(nav = {}, standalone = false) {
  const events = {};
  const window = { addEventListener: (name, handler) => events[name] = handler, matchMedia: () => ({ matches: standalone }) };
  vm.runInNewContext(readFileSync(new URL('../web/pwa.js', import.meta.url), 'utf8'), { window, navigator: nav });
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
