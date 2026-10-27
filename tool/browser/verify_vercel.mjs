import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const origin = process.argv[2] || 'https://gym-management-indol.vercel.app';
for (const pathname of ['/', '/members', '/flutter_bootstrap.js', '/main.dart.js', '/sqlite3.wasm', '/drift_worker.dart.js', '/gympro-sw.js']) {
  const response = await fetch(new URL(pathname, origin));
  assert.equal(response.status, 200, `${pathname} must be served by the production deployment`);
  if (pathname.endsWith('.wasm')) assert.match(response.headers.get('content-type'), /application\/wasm/);
  await response.arrayBuffer();
  console.log(`PASS HTTP 200 ${pathname}`);
}
assert.equal((await fetch(new URL('/missing-test-asset.wasm', origin))).status, 404, 'Missing assets must not receive the HTML application shell');

const browser = await chromium.launch({ channel: 'chrome', headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(origin, { waitUntil: 'domcontentloaded' });
  await page.getByRole('textbox', { name: /Work email/ }).waitFor({ timeout: 60000 });
  await page.getByRole('button', { name: 'Sign in', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Create account', exact: true }).click();
  await page.getByRole('textbox', { name: 'Full name', exact: true }).waitFor();
  await mkdir(new URL('../../artifacts/', import.meta.url), { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL('../../artifacts/vercel-registration.png', import.meta.url)), fullPage: true });
  await page.getByRole('button', { name: 'Already have an account? Sign in', exact: true }).click();
  await page.getByRole('button', { name: 'Sign in', exact: true }).waitFor();
  assert.deepEqual(errors, [], 'Production must load without uncaught browser errors');
  await mkdir(new URL('../../artifacts/', import.meta.url), { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL('../../artifacts/vercel-login.png', import.meta.url)), fullPage: true });
  console.log('PASS Production sign-in and create-account navigation rendered in Chrome.');
} finally { await browser.close(); }
