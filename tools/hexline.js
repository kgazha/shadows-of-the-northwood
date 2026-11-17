// утилита: hex-дампа первой строки .gitignore (проверка реального кодирования)
const fs = require('fs');
const b = fs.readFileSync(process.argv[2] || '.gitignore');
const nl = b.indexOf(0x0a);
const line = b.subarray(0, nl < 0 ? b.length : nl);
console.log('bytes:', [...line].map(x => x.toString(16).padStart(2, '0')).join(' '));
console.log('as utf8 :', Buffer.from(line).toString('utf8'));
console.log('bom:', b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf);
