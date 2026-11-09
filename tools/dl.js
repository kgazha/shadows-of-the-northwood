// Простой загрузчик с редиректами: node dl.js <url> <dest>
'use strict';
const https = require('https');
const fs = require('fs');
function get(url, dest, depth) {
  return new Promise((resolve, reject) => {
    if (depth > 6) return reject(new Error('too many redirects'));
    https.get(url, { headers: { 'user-agent': 'Mozilla/5.0 (dsh-downloader)' } }, (r) => {
      if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location) {
        r.resume();
        return resolve(get(new URL(r.headers.location, url).toString(), dest, depth + 1));
      }
      if (r.statusCode !== 200) { r.resume(); return reject(new Error('HTTP ' + r.statusCode)); }
      const f = fs.createWriteStream(dest);
      r.pipe(f);
      f.on('finish', () => f.close(() => resolve(dest)));
      f.on('error', reject);
    }).on('error', reject);
  });
}
const [, , url, dest] = process.argv;
get(url, dest, 0)
  .then(() => { const n = fs.statSync(dest).size; console.log('OK ' + n + ' bytes'); })
  .catch((e) => { console.error('FAIL: ' + e.message); process.exit(1); });
