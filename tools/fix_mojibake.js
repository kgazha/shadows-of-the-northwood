// Детерминированный ремонт двойного перекодирования UTF-8->CP1252->UTF-8.
// Использование: node tools/fix_mojibake.js <file...> [--write]
// Заменяет только те последовательности, которые декодируются в кириллицу/типографику;
// чистые ASCII/Cyrillic-строки не трогаем.
'use strict';
const fs = require('fs');

// CP1252: байты 0x80-0x9F -> Unicode (обратимая часть таблицы).
const C1252_HIGH = {
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
  0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
  0x9E: 0x017E, 0x9F: 0x0178,
};
const REV = {}; // unicode -> byte
for (const [b, u] of Object.entries(C1252_HIGH)) REV[u] = +b;

function cp1252Code(ch) {
  const c = ch.codePointAt(0);
  if (c <= 0xff) return c;
  return REV[c] !== undefined ? REV[c] : null;
}

// Строка -> Buffer в CP1252 или null, если не представима.
function toCp1252(s) {
  const out = [];
  for (const ch of s) {
    const b = cp1252Code(ch);
    if (b === null) return null;
    out.push(b);
  }
  return Buffer.from(out);
}

// Строгая проверка UTF-8: декодируем и обратно кодируем.
function utf8Roundtrip(buf) {
  const s = buf.toString('utf8');
  if (Buffer.from(s, 'utf8').equals(buf)) return s;
  return null;
}

const CYR_OR_TYPO = /[\u0400-\u04FF\u2013\u2014\u2018-\u201E\u00AB\u00BB\u2026]/;
// Кандидат: mojibake-символ (U+00A0..U+00FF либо из CP1252-верхов) + продолжения.
const MOJI_CHARS = /[\u00A0-\u00FF\u20AC\u201A\u0192\u201E\u2026\u2020\u2021\u02C6\u2030\u0160\u2039\u0152\u017D\u2018\u2019\u201C\u201D\u2022\u2013\u2014\u02DC\u2122\u0161\u203A\u0153\u017E\u0178]/;

function fixLine(line) {
  let out = '';
  let i = 0;
  while (i < line.length) {
    if (!MOJI_CHARS.test(line[i])) { out += line[i++]; continue; }
    // набираем максимальный runs: mojibake + возможные ASCII-продолжения
    let j = i;
    let run = '';
    while (j < line.length) {
      const ch = line[j];
      if (MOJI_CHARS.test(ch)) { run += ch; j++; continue; }
      // продолжает ли предыдущий mojibake-байт многобайтовую последовательность?
      if (run.length > 0) {
        const prev = cp1252Code(run[run.length - 1]);
        const cc = ch.codePointAt(0);
        const isFollow = ch === ' ' ||
          (prev >= 0xC2 && prev <= 0xDF && ((cc >= 0x40 && cc <= 0x4F) || (cc >= 0x60 && cc <= 0x7E))) ||
          (prev >= 0xE0 && prev <= 0xEF && (cc >= 0x30 && cc <= 0x39));
        if (isFollow) { run += ch; j++; continue; }
      }
      break;
    }
    // усекаем с конца, пока не получим валидную UTF-8 с кириллицей
    let replaced = false;
    for (let cut = run.length; cut > 0; cut--) {
      const head = run.slice(0, cut);
      const buf = toCp1252(head);
      if (!buf) continue;
      const dec = utf8Roundtrip(buf);
      if (dec && CYR_OR_TYPO.test(dec)) {
        out += dec;
        // хвост, который не вошёл, обрабатываем заново
        const rest = run.slice(cut);
        if (rest) out += fixLine(rest);
        replaced = true;
        break;
      }
    }
    if (!replaced) { out += run; }
    i = j;
  }
  return out;
}

let changed = 0;
const write = process.argv.includes('--write');
for (const f of process.argv.slice(2).filter(a => a !== '--write')) {
  const raw = fs.readFileSync(f, 'utf8');
  const lines = raw.split('\n');
  const fixedLines = lines.map(fixLine);
  const fixed = fixedLines.join('\n');
  const nChanged = lines.filter((l, k) => l !== fixedLines[k]).length;
  console.log(`${f}: changed lines ${nChanged}${write ? ' (WRITTEN)' : ' (dry-run)'}`);
  if (nChanged && write) fs.writeFileSync(f, fixed, 'utf8');
  changed += nChanged;
}
console.log(`TOTAL ${changed} lines ${write ? 'repaired' : 'need repair'}`);
