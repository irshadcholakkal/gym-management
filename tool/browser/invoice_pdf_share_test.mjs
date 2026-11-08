import { chromium } from 'playwright';
import { readFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const browser = await chromium.launch({ channel: 'chrome', headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.route('https://invoice.test/', route => route.fulfill({
    contentType: 'text/html', body: '<button>GymPro</button>',
  }));
  await page.goto('https://invoice.test/');
  for (const name of ['vendor/html2pdf.bundle.min.js', 'receipt_preview.js']) {
    await page.addScriptTag({ content: await readFile(new URL(`../../web/${name}`, import.meta.url), 'utf8') });
  }
  const source = await readFile(new URL('../../lib/features/receipts/domain/invoice_html.dart', import.meta.url), 'utf8');
  const values = {
    gym_name: 'My Gym', member_name: 'Sample Member', invoice_number: 'INV-0001',
    invoice_status: 'INVOICE', items: '<tr><td>Monthly membership</td><td>AED 300.00</td></tr>',
    total: 'AED 315.00', paid: 'AED 100.00', balance: 'AED 215.00',
  };
  const html = source.match(/defaultDesign = '''([\s\S]*?)''';/)[1]
    .replace(/\{\{(\w+)\}\}/g, (_, key) => values[key] || '');
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'canShare', { configurable: true, value: () => false });
  });
  await page.evaluate(html => window.gymproReceiptSharePdf(html, 'INV-0001'), html);
  await page.getByRole('button', { name: 'Download PDF', exact: true }).waitFor();
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download PDF', exact: true }).click();
  const download = await downloadPromise;
  assert.equal(download.suggestedFilename(), 'INV-0001.pdf');
  const bytes = await readFile(await download.path());
  assert.equal(bytes.subarray(0, 5).toString(), '%PDF-');
  assert.ok(bytes.length > 10000, 'PDF contains rendered invoice content');
  await mkdir(new URL('../../artifacts/', import.meta.url), { recursive: true });
  await download.saveAs(fileURLToPath(new URL('../../artifacts/invoice-share-preview.pdf', import.meta.url)));
  await page.screenshot({ path: fileURLToPath(new URL('../../artifacts/invoice-pdf-share.png', import.meta.url)) });
  await page.getByRole('button', { name: 'Close', exact: true }).click();
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'canShare', { configurable: true, value: ({ files }) => files[0].type === 'application/pdf' });
    Object.defineProperty(navigator, 'share', { configurable: true, value: async ({ files }) => {
      window.sharedFile = { name: files[0].name, type: files[0].type, size: files[0].size };
    } });
  });
  await page.evaluate(html => window.gymproReceiptSharePdf(html, 'INV-0001'), html);
  await page.getByRole('button', { name: 'Share PDF via WhatsApp', exact: true }).click();
  assert.deepEqual(await page.evaluate(() => ({ name: window.sharedFile.name, type: window.sharedFile.type })),
    { name: 'INV-0001.pdf', type: 'application/pdf' });
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'share', { configurable: true, value: async () => {
      throw new DOMException('Cancelled', 'AbortError');
    } });
  });
  await page.getByRole('button', { name: 'Share PDF via WhatsApp', exact: true }).click();
  assert.equal(await page.getByRole('button', { name: 'Download PDF', exact: true }).count(), 0);
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'share', { configurable: true, value: async () => {
      throw new Error('Share unavailable');
    } });
  });
  await page.getByRole('button', { name: 'Share PDF via WhatsApp', exact: true }).click();
  await page.getByRole('button', { name: 'Download PDF', exact: true }).waitFor();
  console.log('PASS HTML invoice generates a real PDF, downloads on unsupported browsers, and shares a PDF file.');
} finally {
  await browser.close();
}
