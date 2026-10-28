const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [svg, png, w] = process.argv.slice(2);
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: +(w||1600), height: 1200 } });
  const data = fs.readFileSync(svg, 'utf8');
  await p.setContent(`<html><body style="margin:0;background:#fff">${data.replace(/<svg /,'<svg style="width:100%;height:auto;display:block" ')}</body></html>`);
  const el = await p.$('svg'); await el.screenshot({ path: png }); await b.close();
})();
