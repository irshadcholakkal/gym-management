// End-to-end export checks with simulated data. All backend traffic is intercepted.
import { chromium } from 'playwright';
import http from 'node:http';
import path from 'node:path';
import { readFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = path.resolve(fileURLToPath(new URL('../../build/web/', import.meta.url)));
const config = JSON.parse(await readFile(new URL('../../config.local.json', import.meta.url), 'utf8'));
const backend = new URL(config.SUPABASE_URL).origin;
const fixture = JSON.parse(await readFile(new URL('../../artifacts/period-report-preview.json', import.meta.url), 'utf8'));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.ttf': 'font/ttf', '.otf': 'font/otf', '.png': 'image/png' };
const server = http.createServer(async (req, res) => {
  try {
    const pathname = new URL(req.url, 'http://localhost').pathname;
    const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : decodeURIComponent(pathname)));
    if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' }).end(await readFile(file));
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(8100, '127.0.0.1', resolve));
const id = number => `00000000-0000-4000-8000-${String(number).padStart(12, '0')}`;
const now = new Date().toISOString();
const user = { id: id(2), aud: 'authenticated', role: 'authenticated', email: 'report@example.test', email_confirmed_at: now, created_at: now, app_metadata: { provider: 'email', providers: ['email'] }, user_metadata: { full_name: 'Report Owner' } };
const jwt = [Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url'), Buffer.from(JSON.stringify({ sub: user.id, aud: 'authenticated', role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url'), 'test-signature'].join('.');
const session = { access_token: jwt, refresh_token: 'report-test-refresh', token_type: 'bearer', expires_in: 3600, user };
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const errors = [], requests = [];
page.on('pageerror', error => errors.push(error.message));
try {
  await page.routeWebSocket(backend.replace('https:', 'wss:') + '/**', socket => socket.close());
  await page.route(backend + '/**', async route => {
    const request = route.request(), url = new URL(request.url());
    if (request.method() === 'OPTIONS') { await route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } }); return; }
    let data = [];
    if (url.pathname === '/auth/v1/token') data = session;
    else if (url.pathname === '/auth/v1/user') data = user;
    else if (url.pathname === '/rest/v1/gym_users') data = [{ gym_id: id(1), user_id: user.id, role: 'owner', active: true, gyms: { name: 'Report Gym' } }];
    else if (url.pathname === '/rest/v1/rpc/pull_changes') data = { changes: [], cursor: 1, has_more: false };
    else if (url.pathname === '/rest/v1/rpc/get_period_report') {
      const args = request.postDataJSON(); requests.push(args);
      data = structuredClone(fixture);
      data.start_date = `${args.p_year}-${String(args.p_month || 1).padStart(2, '0')}-01`;
      data.end_exclusive = new Date(Date.UTC(args.p_year + (args.p_month ? 0 : 1), args.p_month || 0, 1)).toISOString().slice(0, 10);
      for (const key of ['invoices', 'payments', 'reversals', 'receipts', 'members', 'memberships']) {
        for (const row of data[key]) row.date = data.start_date;
      }
    }
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(data) });
  });
  await page.goto('http://127.0.0.1:8100');
  await page.waitForFunction(() => document.querySelector('flutter-view'), null, { timeout: 60000 });
  const accessibility = page.locator('flt-semantics-placeholder');
  if (await accessibility.count()) await accessibility.evaluate(node => node.click());
  const typeInto = async (locator, value) => { await locator.click(); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.type(value); await page.keyboard.press('Tab'); };
  await typeInto(page.getByRole('textbox', { name: 'Email, employee ID or username', exact: true }), 'report@example.test');
  await typeInto(page.getByLabel('Password', { exact: true }), 'test-password');
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await page.getByRole('button', { name: 'Reports', exact: true }).first().click();
  await page.getByRole('button', { name: 'Generate report', exact: true }).click();
  await page.getByRole('button', { name: 'Download PDF', exact: true }).waitFor();
  assert.notEqual(requests[0].p_month, null);
  for (const [label, extension, signature] of [['Download PDF', 'pdf', '%PDF-'], ['Export Excel', 'xlsx', 'PK'], ['Export CSV', 'csv', '\uFEFF']]) {
    const pending = page.waitForEvent('download');
    await page.getByRole('button', { name: label, exact: true }).click();
    const download = await pending;
    assert.ok(download.suggestedFilename().endsWith('.' + extension));
    const bytes = await readFile(await download.path());
    assert.ok(bytes.toString('utf8').startsWith(signature), `${extension} signature`);
  }
  await page.getByText('Yearly', { exact: true }).click();
  await page.getByRole('button', { name: 'Generate report', exact: true }).click();
  await page.getByRole('button', { name: 'Download PDF', exact: true }).waitFor();
  assert.equal(requests.at(-1).p_month, null);
  await mkdir(new URL('../../artifacts/', import.meta.url), { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL('../../artifacts/reports-desktop.png', import.meta.url)) });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: 'Generate report', exact: true }).waitFor();
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= 390));
  await page.screenshot({ path: fileURLToPath(new URL('../../artifacts/reports-mobile.png', import.meta.url)) });
  assert.deepEqual(errors, []);
  console.log('PASS Monthly/yearly reporting, real PDF/Excel/CSV downloads, and desktop/mobile layout with simulated backend.');
} catch (error) {
  await mkdir(new URL('../../artifacts/', import.meta.url), { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL('../../artifacts/reports-browser-failure.png', import.meta.url)) });
  throw error;
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
