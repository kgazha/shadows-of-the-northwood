#!/usr/bin/env node
'use strict';
/*
 * gen_ui_sfx.js — детерминированный синтез UI-звуков для «Теней Северного Леса».
 *
 *Original, CC0. Гипер-короткие 16-bit mono WAV 44100 Гц, пик ровно -3 dBFS.
 * Никаких внешних файлов: тот же seed -> тот же побайтовый результат.
 *
 * Запуск:  node tools/gen_ui_sfx.js [исходящая_папка]
 * По умолчанию: <папка со скриптом>/assets_in/sfx_ui/
 *
 * Файлы:
 *   ui_click.wav    — щелчок: шум 8 мс, экспоненциальное затухание, полосовой
 *                     фильтр ~2 кГц (biquad BQF, Q~2.2)
 *   ui_confirm.wav  — «динь-дон»: две восходящие ноты мажорной терции (C5->E5),
 *                     синус + чуть треугольника, ~150 мс нота+хвост
 *   ui_deny.wav     — низкий короткий гул 120 мс (110 Гц со съездом, лёгкая AM)
 *   ui_levelup.wav  — мажорное арпеджио C5-E5-G5-C6, ~400 мс
 */
const fs = require('fs');
const path = require('path');

const SR = 44100;
const PEAK = Math.pow(10, -3 / 20); // -3 dBFS от полного масштаба

// --- Детерминированный PRNG (mulberry32): шум клика одинаков на любой машине ---
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), 1 | t);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// --- Biquad band-pass (Audio EQ Cookbook), состояния обнулены вызывающим ---
function bandpass(f0, q) {
  const w0 = (2 * Math.PI * f0) / SR;
  const cw = Math.cos(w0);
  const sw = Math.sin(w0);
  const alpha = sw / (2 * q);
  const b0 = alpha, b1 = 0, b2 = -alpha;
  const a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
  return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
}
function runBiquad(f, x, st) {
  const y = f.b0 * x + f.b1 * st.x1 + f.b2 * st.x2 - f.a1 * st.y1 - f.a2 * st.y2;
  st.x2 = st.x1; st.x1 = x;
  st.y2 = st.y1; st.y1 = y;
  return y;
}

const tri = (ph) => (2 / Math.PI) * Math.asin(Math.sin(2 * Math.PI * ph)); // треугольник без аллиасинга высших, кроме мягких
const NOTE = { C5: 523.2511, E5: 659.2550, G5: 783.9909, C6: 1046.5023 };

// --- Генераторы (возвращают Float64Array ненормализованных отсчётов) ---

function genClick() {
  const dur = 0.045, n = Math.round(dur * SR); // 8 мс ядро + экспохвост
  const out = new Float64Array(n);
  const rnd = mulberry32(0xC11C10DE);
  const f = bandpass(2000, 2.2), st = { x1: 0, x2: 0, y1: 0, y2: 0 };
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const noise = rnd() * 2 - 1;
    // шум только в ядре 8 мс, затухание — экспонентой по всему окну
    const core = t < 0.008 ? 1 : 0;
    const env = Math.exp(-t / 0.006);
    out[i] = runBiquad(f, noise * core, st) * env;
  }
  return out;
}

// Нота «колокольчика»: синус + немного треугольника, экспоненциальный хвост.
function bellNote(out, startS, durS, freq, amp, tau) {
  const s0 = Math.round(startS * SR), n = Math.round(durS * SR);
  for (let i = 0; i < n && s0 + i < out.length; i++) {
    const t = i / SR;
    const atk = Math.min(1, t / 0.004);
    const env = atk * Math.exp(-t / tau);
    const s = 0.78 * Math.sin(2 * Math.PI * freq * t) + 0.22 * tri(freq * t);
    out[s0 + i] += amp * env * s;
  }
}

function genConfirm() {
  const n = Math.round(0.23 * SR);
  const out = new Float64Array(n);
  bellNote(out, 0.0, 0.16, NOTE.C5, 1.0, 0.055);  // восходящая мажорная терция
  bellNote(out, 0.075, 0.155, NOTE.E5, 0.9, 0.06); // «динь-дон», сумма ~150 мс значимо
  return out;
}

function genDeny() {
  const dur = 0.12, n = Math.round(dur * SR);
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const f = 110 - 18 * (t / dur); // лёгкий съезд вниз — «нельзя»
    const atk = Math.min(1, t / 0.005);
    const rel = Math.exp(-Math.max(0, t - 0.08) / 0.02);
    const env = atk * rel;
    const am = 1 + 0.18 * Math.sin(2 * Math.PI * 28 * t);
    out[i] = env * am * (Math.sin(2 * Math.PI * f * t) + 0.28 * Math.sin(2 * Math.PI * 2 * f * t));
  }
  return out;
}

function genLevelup() {
  const notes = [NOTE.C5, NOTE.E5, NOTE.G5, NOTE.C6];
  const n = Math.round(0.46 * SR);
  const out = new Float64Array(n);
  notes.forEach((f, k) => {
    const last = k === notes.length - 1;
    bellNote(out, k * 0.09, last ? 0.2 : 0.14, f, 0.95, last ? 0.07 : 0.05);
  });
  return out;
}

// --- Вывод: нормализация к -3 dBFS, PCM 16-bit mono + заголовок WAV ---

function toWav(samples) {
  let mx = 0;
  for (let i = 0; i < samples.length; i++) {
    const a = Math.abs(samples[i]);
    if (a > mx) mx = a;
  }
  const g = mx > 0 ? PEAK / mx : 0;
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + n * 2, 4);
  buf.write('WAVE', 8);
  buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16);          // PCM
  buf.writeUInt16LE(1, 20);           // PCM
  buf.writeUInt16LE(1, 22);           // mono
  buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * 2, 28);      // байт/с
  buf.writeUInt16LE(2, 32);           // блок align
  buf.writeUInt16LE(16, 34);          // бит/сэмпл
  buf.write('data', 36);
  buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    let s = samples[i] * g;
    s = Math.max(-1, Math.min(1, s));
    buf.writeInt16LE(Math.round(s * 32767), 44 + i * 2);
  }
  return buf;
}

// --- Самопроверка: перечитать файл, разобрать заголовок, посчитать пик/RMS ---

function verify(file) {
  const buf = fs.readFileSync(file);
  const errs = [];
  if (buf.toString('ascii', 0, 4) !== 'RIFF') errs.push('нет RIFF');
  if (buf.toString('ascii', 8, 12) !== 'WAVE') errs.push('нет WAVE');
  if (buf.toString('ascii', 12, 16) !== 'fmt ') errs.push('нет fmt');
  const fmt = buf.readUInt16LE(20), ch = buf.readUInt16LE(22), sr = buf.readUInt32LE(24), bits = buf.readUInt16LE(34);
  if (fmt !== 1) errs.push('не PCM (' + fmt + ')');
  if (ch !== 1) errs.push('не mono');
  if (sr !== 44100) errs.push('sr=' + sr);
  if (bits !== 16) errs.push('bits=' + bits);
  if (buf.toString('ascii', 36, 40) !== 'data') errs.push('нет data');
  const dlen = buf.readUInt32LE(40);
  if (buf.length !== 44 + dlen) errs.push('длина файла не бьётся с data');
  let mx = 0, sum = 0;
  const n = Math.floor(dlen / 2);
  for (let i = 0; i < n; i++) {
    const s = buf.readInt16LE(44 + i * 2) / 32768;
    const a = Math.abs(s);
    if (a > mx) mx = a;
    sum += s * s;
  }
  const rms = Math.sqrt(sum / Math.max(1, n));
  return {
    errs,
    durMs: Math.round((n / sr) * 1000),
    peakDb: 20 * Math.log10(mx),
    rmsDb: 20 * Math.log10(rms),
  };
}

function main() {
  const outDir = process.argv[2]
    ? path.resolve(process.argv[2])
    : path.join(__dirname, 'assets_in', 'sfx_ui');
  fs.mkdirSync(outDir, { recursive: true });
  const jobs = [
    ['ui_click.wav', genClick()],
    ['ui_confirm.wav', genConfirm()],
    ['ui_deny.wav', genDeny()],
    ['ui_levelup.wav', genLevelup()],
  ];
  let fail = 0;
  for (const [name, samples] of jobs) {
    const file = path.join(outDir, name);
    fs.writeFileSync(file, toWav(samples));
    const v = verify(file);
    const ok = v.errs.length === 0 && v.peakDb > -3.05 && v.peakDb < -2.95;
    if (!ok) fail++;
    console.log(
      (ok ? 'OK  ' : 'FAIL') + ' ' + name.padEnd(14) +
      v.durMs + ' мс  пик ' + v.peakDb.toFixed(2) + ' dBFS  RMS ' + v.rmsDb.toFixed(2) +
      ' dBFS' + (v.errs.length ? '  [' + v.errs.join('; ') + ']' : '')
    );
  }
  console.log('Выход: ' + outDir);
  process.exit(fail ? 1 : 0);
}

main();
