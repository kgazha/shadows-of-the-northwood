#!/usr/bin/env node
/* Проверка WAV-файлов: заголовки RIFF/WAVE/fmt/data, честность размеров,
 * RMS, пик, отсутствие тишины и клиппинга. Выход: 0 = OK, 1 = ошибки.
 * Запуск: node verify_wav.js <файл.wav> [еще.wav ...] */
'use strict';
const fs = require('fs');

function verify(file) {
  const b = fs.readFileSync(file);
  const errs = [];
  const ok = (cond, msg) => { if (!cond) errs.push(msg); };
  const name = file.replace(/\\/g, '/').split('/').pop();

  ok(b.length >= 44, 'файл меньше заголовка WAV');
  ok(b.toString('ascii', 0, 4) === 'RIFF', 'нет магии RIFF');
  ok(b.toString('ascii', 8, 12) === 'WAVE', 'нет WAVE');
  const riffSize = b.readUInt32LE(4);
  ok(riffSize + 8 === b.length, `размер RIFF ${riffSize} + 8 ≠ размеру файла ${b.length}`);
  ok(b.toString('ascii', 12, 16) === 'fmt ', 'нет чанка fmt');
  ok(b.readUInt32LE(16) === 16, 'нестандартный размер fmt');
  ok(b.readUInt16LE(20) === 1, 'не PCM (expected audioFormat=1)');
  const ch = b.readUInt16LE(22);
  const sr = b.readUInt32LE(24);
  const byteRate = b.readUInt32LE(28);
  const align = b.readUInt16LE(32);
  const bits = b.readUInt16LE(34);
  ok(ch === 1 || ch === 2, `каналы=${ch}`);
  ok(bits === 16, `битность=${bits}, ожидалось 16`);
  ok(byteRate === sr * ch * 2, `byteRate ${byteRate} ≠ sr*ch*2`);
  ok(align === ch * 2, `blockAlign ${align}`);
  ok(b.toString('ascii', 36, 40) === 'data', 'нет чанка data');
  const dataLen = b.readUInt32LE(40);
  ok(44 + dataLen === b.length, `data ${dataLen} + 44 ≠ размеру файла ${b.length}`);
  ok(dataLen % (ch * 2) === 0, 'data не кратен размеру кадра');

  const frames = dataLen / (ch * 2);
  let peak = 0, sq = 0, atFull = 0, min16 = 32767, max16 = -32768;
  for (let i = 0; i < dataLen / 2; i++) {
    const v = b.readInt16LE(44 + i * 2);
    const a = Math.abs(v);
    if (a > peak) peak = a;
    if (v < min16) min16 = v;
    if (v > max16) max16 = v;
    if (a >= 32766) atFull++;
    sq += (v / 32768) * (v / 32768);
  }
  const rms = Math.sqrt(sq / (dataLen / 2));
  const peakF = peak / 32768;
  const db = v => (v > 0 ? (20 * Math.log10(v)).toFixed(2) + ' dBFS' : '-inf');
  const dur = frames / sr;

  ok(rms > 0.0015, `похоже на тишину: RMS=${rms.toFixed(6)}`);            // < −55 dBFS
  ok(peakF >= 0.6 && peakF <= 0.999, `пик вне ожидаемого окна [−4.4..0] дБ: ${db(peakF)}`);
  ok(peakF < 1.0, 'пик достиг полной шкалы — возможный клиппинг');
  ok(atFull === 0, `${atFull} сэмплов на полной шкале (клиппинг)`);

  console.log(`${name}: ${ch === 2 ? 'stereo' : 'mono'} ${sr} Hz 16-bit, ${frames} кадров, ${dur.toFixed(3)} с, ${b.length} B`);
  console.log(`  пик=${db(peakF)} (мин=${min16}, макс=${max16}, full-scale=${atFull})  RMS=${db(rms)}  заголовки OK=${errs.length === 0}`);
  errs.forEach(e => console.log('  ОШИБКА: ' + e));
  return errs.length === 0;
}

const files = process.argv.slice(2);
if (!files.length) { console.error('укажите WAV-файлы'); process.exit(2); }
let bad = 0;
for (const f of files) if (!verify(f)) bad++;
console.log(bad ? `\nПРОВАЛ: ${bad} файл(ов) с ошибками` : '\nВсе проверки пройдены ✓');
process.exit(bad ? 1 : 0);
