import { chromium } from 'playwright';
import { readFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const browser=await chromium.launch({channel:'chrome',headless:true});
try {
  const page=await browser.newPage({viewport:{width:390,height:844}});
  await page.route('https://receipt.test/',route=>route.fulfill({contentType:'text/html',body:'<button id="original">Receipt</button>'}));
  await page.goto('https://receipt.test/');
  await page.addScriptTag({content:await readFile(new URL('../../web/receipt_preview.js',import.meta.url),'utf8')});
  await page.evaluate(()=>window.gymproReceiptPreview('<html><head><style>body{font:14px Arial;color:#08152f;padding:20px}h1{color:#397de5}table{width:100%;border-collapse:collapse}td{padding:12px;border-bottom:1px solid #ddd}</style></head><body><h1>GymPro UAE</h1><p>SAMPLE RECEIPT</p><p>Sample Member</p><table><tr><td>Total</td><td>AED 300.00</td></tr><tr><td>Paid</td><td>AED 200.00</td></tr></table><script>parent.pwned=true</script><img src="https://evil.test/leak"><a href="https://evil.test" onclick="alert(1)">link</a><iframe src="https://evil.test"></iframe></body></html>','Receipt design preview'));
  const frame=page.frameLocator('#gympro-receipt-preview iframe');
  await frame.getByText('GymPro UAE').waitFor();
  assert.equal(await frame.locator('script,iframe').count(),0);
  assert.equal(await frame.locator('a').getAttribute('href'),null);
  assert.equal(await frame.locator('a').getAttribute('onclick'),null);
  assert.equal(await frame.locator('img').getAttribute('src'),null);
  assert.equal(await page.evaluate(()=>window.pwned),undefined);
  assert.equal(await page.locator('iframe').getAttribute('sandbox'),'allow-same-origin allow-modals');
  await mkdir(new URL('../../artifacts/',import.meta.url),{recursive:true});
  await page.screenshot({path:fileURLToPath(new URL('../../artifacts/receipt-html-preview.png',import.meta.url))});
  const download=page.waitForEvent('download');await page.getByRole('button',{name:'Download HTML',exact:true}).click();
  assert.equal((await download).suggestedFilename(),'receipt-design-preview.html');
  await page.getByRole('button',{name:'Close',exact:true}).click();
  assert.equal(await page.locator('#gympro-receipt-preview').count(),0);
  console.log('PASS Receipt preview renders at mobile width, blocks active content, downloads HTML and closes.');
}finally{await browser.close();}
