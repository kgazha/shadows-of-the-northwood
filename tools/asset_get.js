// node tools/asset_get.js <listfile> — listfile: строки "URL\tКУДА". HTTPS, редиректы, прогресс.
'use strict';
const fs = require('fs');
const https = require('https');

function get(url, dest, depth = 0) {
  return new Promise((resolve, reject) => {
    if (depth > 4) return reject(new Error('redirect loop'));
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, timeout: 60000 }, res => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode)) {
        res.resume();
        return resolve(get(new URL(res.headers.location, url).href, dest, depth + 1));
      }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error('HTTP ' + res.statusCode + ' ' + url)); }
      const out = fs.createWriteStream(dest);
      res.pipe(out);
      out.on('finish', () => out.close(() => resolve(dest)));
      out.on('error', reject);
    }).on('error', reject).on('timeout', function () { this.destroy(new Error('timeout ' + url)); });
  });
}

(async () => {
  const lines = fs.readFileSync(process.argv[2], 'utf8').split(/\r?\n/).filter(l => l.trim());
  for (const l of lines) {
    const [url, dest] = l.split('\t');
    fs.mkdirSync(require('path').dirname(dest), { recursive: true });
    try { await get(url.trim(), dest.trim()); console.log('OK  ' + dest.trim()); }
    catch (e) { console.log('FAIL ' + dest.trim() + ' :: ' + e.message); process.exitCode = 1; }
  }
})();
