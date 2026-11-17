// Проверка pck: какие ресурсы внутри (ogg/wav/muz), без внешних библиотек.
const fs = require('fs');
const b = fs.readFileSync('build/web/index.pck');
const s = b.toString('latin1');
const uniq = (re) => [...new Set((s.match(re) || []))].sort();
console.log('ogg:', uniq(/[\w\/\.\-]*\.ogg/g).slice(0, 40));
console.log('wav:', uniq(/[\w\/\.\-]*\.wav/g).slice(0, 40));
console.log('png_count:', (s.match(/\.png/g) || []).length);
