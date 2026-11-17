// Инспекция web-загрузчика: ищет опции предварительной компрессии (.br/.gz/brotli).
const fs = require('fs');
const s = fs.readFileSync('build/web/index.js', 'latin1');
const count = (re) => (s.match(re) || []).length;
console.log('dot_br:', count(/\.br/g));
console.log('brotli:', count(/brotli/gi));
console.log('dot_gz:', count(/\.gz["']/g));
console.log('pck_refs:', count(/\.pck/g));
console.log('wasm_refs:', count(/\.wasm/g));
