// Аудит некириллических символов в строковых литералах (риск тофу в шрифте Godot).
'use strict';
const fs = require('fs');
const files = [
  ...fs.readdirSync('pixel-rpg/scripts').filter(f => f.endsWith('.gd')).map(f => 'pixel-rpg/scripts/' + f),
  ...fs.readdirSync('pixel-rpg/data').filter(f => f.endsWith('.json')).map(f => 'pixel-rpg/data/' + f),
];
const chars = {};
for (const f of files) {
  const s = fs.readFileSync(f, 'utf8');
  // только содержимое строковых литералов
  const lits = [...s.matchAll(/"([^"\n]*)"/g)].map(m => m[1]);
  for (const l of lits) {
    for (const ch of l) {
      const cp = ch.codePointAt(0);
      if (cp > 127 && !/[\u0400-\u04FF]/.test(ch)) {
        (chars[ch] = chars[ch] || { n: 0, where: new Set() });
        chars[ch].n++;
        chars[ch].where.add(f.split('/').pop());
      }
    }
  }
}
const out = Object.entries(chars).sort((a, b) => b[1].n - a[1].n);
for (const [c, info] of out) {
  console.log('U+' + c.codePointAt(0).toString(16).toUpperCase().padStart(4, '0'), JSON.stringify(c), 'x' + info.n, [...info.where].slice(0, 5).join(', '));
}
console.log('TOTAL distinct:', out.length);
