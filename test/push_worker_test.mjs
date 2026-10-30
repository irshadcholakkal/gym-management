import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../web/gympro-sw.js', import.meta.url), 'utf8');
function worker(windows = []) {
  const handlers = {}, shown = [], opened = [];
  const self = {
    location: { href: 'https://gym.example/app/gympro-sw.js' },
    addEventListener: (type, handler) => handlers[type] = handler,
    registration: { showNotification: async (title, options) => shown.push({ title, ...options }) },
    clients: { matchAll: async () => windows, openWindow: async url => opened.push(url) },
  };
  vm.runInNewContext(source, { self, URL, URLSearchParams });
  async function dispatch(type, event) {
    let completion;
    handlers[type]({ ...event, waitUntil: promise => completion = promise });
    await completion;
  }
  return { shown, opened, dispatch };
}
test('push warning carries a distinct authenticated inbox deep link', async () => {
  const w = worker();
  const id = '11111111-1111-4111-8111-111111111111';
  await w.dispatch('push', { data: { json: () => ({ type: 'expiry_1', notification_id: id, gym_id: id, body: 'Private member name' }) } });
  assert.match(w.shown[0].body, /tomorrow/);
  assert.ok(!w.shown[0].body.includes('Private'));
  assert.equal(w.shown[0].tag, `gympro-${id}`);
  assert.equal(w.shown[0].data.url, `https://gym.example/app/#/notifications?notification=${id}&gym=${id}`);
});
test('malformed push still shows a generic notification', async () => {
  const w = worker();
  await w.dispatch('push', { data: { json: () => { throw Error('bad JSON'); } } });
  assert.equal(w.shown.length, 1);
  assert.equal(w.shown[0].data.url, 'https://gym.example/app/#/notifications');
});
test('notification click reuses app window and preserves notification route', async () => {
  let navigated, focused = false;
  const w = worker([{ url: 'https://gym.example/app/#/', navigate: async url => navigated = url, focus: async () => focused = true }]);
  const target = 'https://gym.example/app/#/notifications?notification=abc';
  await w.dispatch('notificationclick', { notification: { close() {}, data: { url: target } } });
  assert.equal(navigated, target);
  assert.equal(focused, true);
  assert.equal(w.opened.length, 0);
});
test('unsafe click URL falls back to inbox', async () => {
  const w = worker();
  await w.dispatch('notificationclick', { notification: { close() {}, data: { url: 'https://evil.example/' } } });
  assert.equal(w.opened[0], 'https://gym.example/app/#/notifications');
});
test('failed window navigation opens a new app window', async () => {
  const w = worker([{ url: 'https://gym.example/app/', navigate: async () => { throw Error('closed'); } }]);
  await w.dispatch('notificationclick', { notification: { close() {}, data: {} } });
  assert.equal(w.opened.length, 1);
});
