#!/usr/bin/env node
/* ============================================================================
 * «Тени Северного Леса» — процедурный саундтрек для тёмной пиксельной RPG.
 *
 * ПОЛНАЯ ОРИГИНАЛЬНОСТЬ: все ноты, ритмы и тембры генерируются этим скриптом
 * (собственный PRNG mulberry32 с фиксированными seed'ами + гармонические и
 * мотивические конструкции, заложенные в код). Никаких семплов, сторонних
 * библиотек или сети — только fs, path и Math. Материал — CC0.
 *
 * Выход (16-bit PCM WAV, stereo):
 *   theme_forest.wav   22050 Hz, 72 с   — A Aeolian, 80 BPM (24 такта)
 *   theme_cave.wav     22050 Hz, 60 с   — дрон 55/55.35/82.5/82.85 Гц + капли
 *   theme_tension.wav  44100 Hz, 58.91 с — D Aeolian, ровно 110 BPM (27 тактов)
 *
 * БЕЗЩЕЛЧКОВЫЙ ЛУП: «loop-tail со сдвигом» вместо наивного оверлея головы и
 * хвоста (наивный 0.5-с оверлей удваивал бы атаки на быстром бите):
 *   1) Буфер рендерится на [0, T+W], W=0.5 с («кроссфейдный хвост»).
 *   2) СобытияNear границы T рендерятся и в продолжение [T, T+W] (копии
 *      головных событий цикла + хвосты собственных событий), т.е. кроссфейд
 *      хвоста с началом встроен в рендер математически точно.
 *   3) Файл = кадры [W, T+W): последние 0.5 с файла — это continuation,
 *      побитово равный продолжению сигнала после T ⇒ x(T+W−)=x(W−), шов
 *      непрерывен. Модуляции (LFO/дрон) — на целое число периодов на T,
 *      шумовые слои — циклический шум (буфер длины T) через рекурсивные
 *      фильтры, прогретые до установившегося периодического режима.
 *   4) В конце мэрится «шов» |x[W+T]−x[W+T−1]| против медианы соседних дельт.
 *
 * Громкость: нормализация к пику −3 dBFS → мягкий лимитер tanh →
 * перенормировка к −3 dBFS. Клиппинга нет (ни одного full-scale сэмгла).
 *
 * Детерминизм: mulberry32, фиксированные seed, без Math.random/Date.now.
 * Повторный запуск даёт побайтово идентичные файлы.
 *
 * Запуск: node gen_music.js [выходная_папка]
 * ==========================================================================*/
'use strict';
const fs = require('fs');
const path = require('path');

/* ---------------- PRNG (mulberry32) ---------------- */
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* ---------------- DSP ---------------- */
const TAU = Math.PI * 2;
const PEAK = 0.7079458; // −3 dBFS
function midiF(m) { return 440 * Math.pow(2, (m - 69) / 12); }
function adsr(t, A, D, S, R, dur) { // dur — полная длительность, включая релиз
  if (t < 0 || t >= dur) return 0;
  if (t < A) return t / A;
  if (t < A + D) return 1 - (1 - S) * ((t - A) / D);
  if (t < dur - R) return S;
  return S * (dur - t) / R;
}
function lpCoef(fc, sr) { return 1 - Math.exp(-TAU * Math.min(fc, sr * 0.45) / sr); }

// Одна «нота»: аддитивный тон + вибрато + ADSR + до 2 ФНЧ тембра, стерио-пан.
// t0 может быть < 0 (хвосты предыдущего цикла) — отсечка по нулевому индексу.
function addTone(L, R, t0, dur, f0, o) {
  if (!isFinite(f0) || f0 <= 0) throw new Error('addTone: некорректная частота ' + f0);
  const sr = o.sr, N = L.length;
  const n0 = Math.round(t0 * sr), n1 = Math.min(N, Math.round((t0 + dur) * sr));
  if (n0 >= N || n1 <= 0) return;
  const vibR = o.vibR || 0, vibC = o.vibC || 0, vt = o.vibIn == null ? 0.25 : o.vibIn;
  const lp1 = o.lp || 0, lp2 = o.lp2 || 0;
  const a1 = lp1 ? lpCoef(lp1, sr) : 0, a2 = lp2 ? lpCoef(lp2, sr) : 0;
  let c1 = 0, c2 = 0, ph = 0;
  const parts = o.partials || [[1, 1]];
  const gl = o.gl == null ? 1 : o.gl, gr = o.gr == null ? 1 : o.gr;
  for (let n = Math.max(0, n0); n < n1; n++) {
    const u = n / sr - t0;
    let f = f0;
    if (vibC) f = f * Math.pow(2, (vibC * Math.sin(TAU * vibR * u) * Math.min(1, u / vt)) / 1200);
    ph += TAU * f / sr;
    let s = 0;
    for (const pr of parts) s += pr[1] * Math.sin(pr[0] * ph);
    if (a1) { c1 += a1 * (s - c1); s = c1; }
    if (a2) { c2 += a2 * (s - c2); s = c2; }
    const v = s * adsr(u, o.A, o.D, o.S, o.R, dur) * (o.g || 1);
    L[n] += v * gl; R[n] += v * gr;
  }
}

// Циклический белый шум длины n (периодичен => лупится без щелчка).
function makeCycNoise(n, rnd) { const a = new Float64Array(n); for (let i = 0; i < n; i++) a[i] = rnd() * 2 - 1; return a; }
// ФНЧ 1-го порядка кольцевым прогоном (несколько проходов до установившегося
// периодического режима): выход периодичен на n и непрерывен на стыке.
function cycLP(x, sr, fc, passes) {
  const a = lpCoef(fc, sr), n = x.length, y = Float64Array.from(x);
  for (let p = 0; p < passes; p++) { let s = y[0]; for (let i = 0; i < n; i++) { s += a * (y[i] - s); y[i] = s; } }
  return y;
}
// Циклический ФВЧ (с той же прогревкой).
function cycHP(x, sr, fc, passes) {
  const a = lpCoef(fc, sr), n = x.length, y = Float64Array.from(x);
  for (let p = 0; p < passes; p++) { let lp = 0, px = 0, py = 0;
    for (let i = 0; i < n; i++) { const v = y[i]; lp += a * (v - lp); const out = 0.75 * (py + v - px); if (p === passes - 1) y[i] = out; px = v; py = out; } }
  return y;
}

function softClip(x) { return Math.tanh(1.2 * x) / Math.tanh(1.2); }

// Финальная обработка: нормализация → tanh → перенормировка; файл = [W, W+T).
function finishTrack(name, outDir, sr, T, W, L, R) {
  const N = L.length;
  let nanAt = -1;
  for (let i = 0; i < N; i++) if (!isFinite(L[i]) || !isFinite(R[i])) { nanAt = i; break; }
  if (nanAt >= 0) throw new Error(name + ': NaN/Inf в буфере на индексе ' + nanAt + ' (t=' + (nanAt / sr).toFixed(4) + ' с)');
  let mx = 0;
  for (let i = 0; i < N; i++) { const v = Math.max(Math.abs(L[i]), Math.abs(R[i])); if (v > mx) mx = v; }
  if (!(mx > 0)) throw new Error(name + ': пустой буфер');
  let g = PEAK / mx;
  for (let i = 0; i < N; i++) { L[i] *= g; R[i] *= g; L[i] = softClip(L[i]); R[i] = softClip(R[i]); }
  let mx2 = 0;
  for (let i = 0; i < N; i++) { const v = Math.max(Math.abs(L[i]), Math.abs(R[i])); if (v > mx2) mx2 = v; }
  g = PEAK / mx2;
  for (let i = 0; i < N; i++) { L[i] *= g; R[i] *= g; }

  const Lw = L.slice(W, W + T), Rw = R.slice(W, W + T); // файл — ровно T кадров
  let peak = 0, sq = 0, sqL = 0, sqR = 0, atFull = 0;
  for (let i = 0; i < T; i++) {
    const a = Math.abs(Lw[i]), b = Math.abs(Rw[i]), m = a > b ? a : b;
    if (m > peak) peak = m;
    if (m >= 0.99995) atFull++;
    sq += (Lw[i] * Lw[i] + Rw[i] * Rw[i]) * 0.5; sqL += Lw[i] * Lw[i]; sqR += Rw[i] * Rw[i];
  }
  const rms = Math.sqrt(sq / T), rmsL = Math.sqrt(sqL / T), rmsR = Math.sqrt(sqR / T);
  // Шов при воспроизведении: последний кадр файла L[W+T−1] сменяется первым L[W].
  const seam = Math.max(Math.abs(L[W] - L[W + T - 1]), Math.abs(R[W] - R[W + T - 1]));
  // Контроль периодичности рендера: x(T+W) обязан равняться x(W).
  const period = Math.max(Math.abs(L[W + T] - L[W]), Math.abs(R[W + T] - R[W]));
  const dd = new Float64Array(T - 1);
  for (let i = 1; i < T; i++) dd[i - 1] = Math.abs(Lw[i] - Lw[i - 1]) + Math.abs(Rw[i] - Rw[i - 1]);
  const ds = Float64Array.from(dd); ds.sort();
  const med = ds[(T - 1) >> 1], p99 = ds[Math.floor((T - 1) * 0.99)];
  const bytes = writeWav(path.join(outDir, name), Lw, Rw, sr);
  const db = v => (v > 0 ? 20 * Math.log10(v) : -999).toFixed(2);
  console.log(`\n=== ${name} ===`);
  console.log(`  sr=${sr}  frames=${T}  dur=${(T / sr).toFixed(3)}s  stereo 16-bit  ${bytes} bytes (${(bytes / 1048576).toFixed(2)} MB)`);
  console.log(`  peak=${db(peak)} dBFS  RMS=${db(rms)} dBFS (L ${db(rmsL)} / R ${db(rmsR)})  full-scale сэмплов=${atFull}`);
  console.log(`  шов (последний→первый кадр): ${seam.toExponential(2)}  vs медиана дельт=${med.toExponential(2)}, p99=${p99.toExponential(2)} → ` +
    (seam <= p99 * 1.5 ? 'OK, щелчка на стыке нет' : 'ВНИМАНИЕ: аномальный шов'));
  console.log(`  периодичность рендера |x(T+W)−x(W)| = ${period.toExponential(2)} (стремится к 0)`);
  return { name, bytes, peak, rms, seam, med, p99 };
}

function writeWav(file, L, R, sr) {
  const T = L.length, dataLen = T * 4;
  const b = Buffer.alloc(44 + dataLen);
  b.write('RIFF', 0); b.writeUInt32LE(36 + dataLen, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20);
  b.writeUInt16LE(2, 22); b.writeUInt32LE(sr, 24); b.writeUInt32LE(sr * 4, 28);
  b.writeUInt16LE(4, 32); b.writeUInt16LE(16, 34);
  b.write('data', 36); b.writeUInt32LE(dataLen, 40);
  for (let i = 0; i < T; i++) {
    let l = Math.round(L[i] * 32767), r = Math.round(R[i] * 32767);
    if (l > 32767) l = 32767; else if (l < -32768) l = -32768;
    if (r > 32767) r = 32767; else if (r < -32768) r = -32768;
    b.writeInt16LE(l, 44 + 4 * i); b.writeInt16LE(r, 44 + 4 * i + 2);
  }
  fs.writeFileSync(file, b);
  return b.length;
}

/* ============================================================================
 * ТРЕК 1 — theme_forest.wav — главная тема.
 * A Aeolian (A B C D E F G), 24 такта × 4 доли, T=72 с ⇒ такт 3 с, BPM=80.
 * Форма: три 8-тактовых блока-фразы (Am F C G / Am Dm F G / Am F C G).
 * Слои: тихий бас (синус+2-я гармоника, ФНЧ 260 Гц, ADSR); редкая
 * флейтоподобная мелодия (синус+гармоники, вибрато 5.2 Гц/14 центов, ADSR,
 * шум «дыхания»); очень тихий арфовый перебор; очень тихий «ветер» —
 * циклический шум через ФНЧ-полосы с медленными LFO; суб-дрон A1 в блоках 1 и 3.
 * ==========================================================================*/
function genForest(outDir) {
  const sr = 22050, T = 72 * sr, W = Math.round(0.5 * sr), N = W + T + 4096;
  const rnd = mulberry32(20261110);
  const bar = 3.0, beat = 0.75; // секунды; 80 BPM
  const L = new Float64Array(N), R = new Float64Array(N);

  const P1 = [{ r: 57, q: 'm' }, { r: 53, q: 'm' }, { r: 48, q: 'M' }, { r: 55, q: 'M' }]; // Am F C G
  const P2 = [{ r: 57, q: 'm' }, { r: 50, q: 'm' }, { r: 53, q: 'm' }, { r: 55, q: 'M' }]; // Am Dm F G
  const progOf = b => (b % 2 === 1 ? P2 : P1);
  const thirdOff = ch => (ch.q === 'm' ? 3 : 4);
  const isCT = (p, ch) => { const o = (((p - ch.r) % 12) + 12) % 12; return o === 0 || o === thirdOff(ch) || o === 7; };
  const scale = [57, 59, 60, 62, 64, 65, 67];

  // --- генерация мелодии: три фразы по 32 доли; разрешение каждой — тоника A4.
  const TPL = [
    [4, 2, 2, 3, 1, 4, 2, 2, 4, 2, 2, 2, 2],   // сумма 32
    [2, 2, 2, 2, 4, 4, 2, 2, 2, 2, 4, 6],      // сумма 32 (реже, ниже)
    [4, 2, 2, 4, 4, 2, 2, 4, 4, 8],            // сумма 32 (кульминация)
  ];
  const STARTP = [72, 76, 64];
  const mel = [];
  for (let b = 0; b < 3; b++) {
    const tpl = TPL[b]; let tb = 0, cur = STARTP[b];
    for (let i = 0; i < tpl.length; i++) {
      const dur = tpl[i], last = i === tpl.length - 1;
      let p;
      if (last) p = 69; // A4
      else {
        const absB = b * 32 + tb, barI = Math.floor(absB / 4), beatInBar = absB % 4;
        const ch = progOf(b)[Math.floor((barI % 8) / 2)];
        const strong = beatInBar === 0 || beatInBar === 2;
        let best = cur, bestS = -1e9;
        for (const cd of scale) for (const oct of [0, 12]) {
          const pp = cd + oct;
          if (pp < 57 || pp > 81) continue;
          if (i !== 0 && Math.abs(pp - cur) > 7) continue;
          let s = -Math.abs(pp - cur) * 0.22;
          if (i !== 0 && Math.abs(pp - cur) >= 5 && rnd() > 0.22) s -= 2.2;
          if (strong && isCT(pp, ch)) s += 2.0;
          if (pp === 69 || pp === 72 || pp === 76) s += 0.35;
          if (pp === 68 || pp === 80) s -= 1.5;
          s += rnd() * 0.9;
          if (s > bestS) { bestS = s; best = pp; }
        }
        p = best;
      }
      if (!(i > 0 && !last && rnd() < 0.1)) { // иногда — пауза
        const t0 = (b * 32 + tb) * beat, d = dur * beat - 0.06, v = 0.62 + rnd() * 0.2;
        mel.push({ t0, d, p, v });
      }
      cur = p; tb += dur;
    }
  }

  // --- духовые/бас/арфы: рендерим цикл + копии головных событий в хвост [T, T+W]
  const renderMelodyNote = e => {
    addTone(L, R, e.t0, e.d, midiF(e.p), {
      sr, A: 0.14, D: 0.3, S: 0.8, R: 0.35, g: 0.14 * e.v,
      vibR: 5.2, vibC: 14, vibIn: 0.3,
      parts: [[1, 1], [2, 0.22], [3, 0.07]],
    });
    // «дыхание» флейты — шумовой хвостик, детерминированный по фазе ноты в
    // цикле (оригинал и хвостовая копия обязаны совпадать для периодичности)
    const brnd = mulberry32((0xbeef ^ Math.round((e.t0 % (T / sr)) * 1e6)) >>> 0);
    const n0 = Math.max(0, Math.round(e.t0 * sr)), n1 = Math.min(N, Math.round((e.t0 + e.d) * sr));
    let bp = 0; const ab = lpCoef(1800, sr);
    for (let n = n0; n < n1; n++) {
      const u = n / sr - e.t0;
      bp += ab * ((brnd() * 2 - 1) - bp);
      const en = adsr(u, 0.1, 0.25, 0.5, 0.3, e.d) * 0.016 * e.v;
      L[n] += bp * en; R[n] += bp * en * 0.9;
    }
  };
  const renderBar = bi => { // бас + арфа на такте bi (bi может относиться к следующему циклу)
    const b = Math.floor(bi / 8) % 3, ch = progOf(b)[Math.floor((bi % 8) / 2)];
    const t0 = bi * bar;
    if (t0 >= W + T) return;
    addTone(L, R, t0 + 0.02, bar - 0.10, midiF(ch.r - 12), {
      sr, A: 0.35, D: 0.4, S: 0.75, R: 0.45, g: 0.15, lp: 260, parts: [[1, 1], [2, 0.16]],
    });
    if (bi % 2 === 0) {
      const tri = [ch.r + 12, ch.r + 19, ch.r + 12 + thirdOff(ch)];
      const ts = [0, 1.5, 3];
      for (let k = 0; k < 3; k++)
        addTone(L, R, t0 + ts[k] * beat, 2.2, midiF(tri[k]), {
          sr, A: 0.004, D: 0.9, S: 0.05, R: 1.2, g: 0.048, parts: [[1, 1], [2, 0.4], [3, 0.15]],
        });
    }
    if ((b === 0 || b === 2) && (bi % 8 === 0 || bi % 8 === 5))
      addTone(L, R, t0, bar * (bi % 8 === 0 ? 4 : 3) - 0.2, midiF(45), {
        sr, A: 0.8, D: 0.5, S: 0.8, R: 0.8, g: 0.085, parts: [[1, 1]],
      });
  };
  for (let bi = 0; bi < 26; bi++) renderBar(bi);            // 24 такта + 2 «хвостовых»
  for (const e of mel) renderMelodyNote(e);
  for (const e of mel) if (e.t0 < 0.5) renderMelodyNote({ ...e, t0: e.t0 + T / sr });

  // --- «ветер»: циклический шум, ФНЧ-полосы, целые периоды LFO на T
  const nL = cycLP(cycLP(makeCycNoise(T, rnd), sr, 1500, 2), sr, 520, 2);
  const nR = cycLP(cycLP(makeCycNoise(T, rnd), sr, 1400, 2), sr, 620, 2);
  const hL = cycLP(makeCycNoise(T, rnd), sr, 5200, 1), hR = cycLP(makeCycNoise(T, rnd), sr, 5200, 1);
  const bL = new Float64Array(T), bR = new Float64Array(T); // полоса ~160–560 Гц
  { const a1 = lpCoef(560, sr), a2 = lpCoef(160, sr);
    let p1L = 0, p2L = 0, p1R = 0, p2R = 0;
    for (const pass of [0, 1, 2]) for (let i = 0; i < T; i++) {
      p1L += a1 * (nL[i] - p1L); p2L += a2 * (nL[i] - p2L); if (pass === 2) bL[i] = p1L - p2L;
      p1R += a1 * (nR[i] - p1R); p2R += a2 * (nR[i] - p2R); if (pass === 2) bR[i] = p1R - p2R;
    } }
  for (let i = 0; i <= W + T; i++) {
    const p = (i % T) / T;
    const gA = 0.55 + 0.45 * Math.sin(TAU * (3 * p + 0.13));
    const gB = 0.5 + 0.5 * Math.sin(TAU * (7 * p + 0.41));
    const gC = 0.5 + 0.5 * Math.sin(TAU * (5 * p + 0.71));
    L[i] += 0.017 * gB * bL[i % T] + 0.030 * gA * nL[i % T] + 0.008 * gC * hL[i % T];
    R[i] += 0.017 * gB * bR[i % T] + 0.030 * gA * nR[i % T] + 0.008 * gC * hR[i % T];
  }
  return finishTrack('theme_forest.wav', outDir, sr, T, W, L, R);
}

/* ============================================================================
 * ТРЕК 2 — theme_cave.wav — пещера, 60 с.
 * Почти без мелодии: низкий дрон — расстроенные пары синусов 55+55.35 Гц
 * (биения ~2.9 с) и квинтовый слой 82.5+82.85 Гц с медленной амплитудной
 * модуляцией; все частоты — целое число периодов на 60 с ⇒ идеальный луп.
 * Низкий гул — циклический шум, трижды ФНЧ 90 Гц. Редкие капли — короткие
 * затухающие синусы 600–1200 Гц со спадом высоты, случайной панорамой и
 * эхом; капли у конца цикла не переходят границу файла (правило по хвосту).
 * ==========================================================================*/
function genCave(outDir) {
  const sr = 22050, T = 60 * sr, W = Math.round(0.5 * sr), N = W + T + 4096;
  const rnd = mulberry32(1357);
  const L = new Float64Array(N), R = new Float64Array(N);

  // дрон (55·60=3300, 55.35·60=3321, 82.5·60=4950, 82.85·60=4971 — целые периоды)
  for (let i = 0; i <= W + T; i++) {
    const p = (i % T) / T;
    const l1 = 0.55 + 0.45 * Math.sin(TAU * 2 * p), l2 = 0.5 + 0.5 * Math.sin(TAU * 3 * p + 1.7);
    const ii = i % T;
    const s = 0.30 * Math.sin(TAU * 55 * ii / sr) + 0.26 * Math.sin(TAU * 55.35 * ii / sr)
      + 0.15 * l1 * Math.sin(TAU * 82.5 * ii / sr) + 0.12 * l2 * Math.sin(TAU * 82.85 * ii / sr);
    L[i] += s; R[i] += s;
  }
  // гул + «воздушность пещеры»
  const rL = cycLP(cycLP(cycLP(makeCycNoise(T, rnd), sr, 90, 1), sr, 90, 1), sr, 90, 1);
  const rR = cycLP(cycLP(cycLP(makeCycNoise(T, rnd), sr, 90, 1), sr, 90, 1), sr, 90, 1);
  const aL = cycLP(makeCycNoise(T, rnd), sr, 2400, 2), aR = cycLP(makeCycNoise(T, rnd), sr, 2600, 2);
  let rmax = 0; for (let i = 0; i < T; i++) rmax = Math.max(rmax, Math.abs(rL[i]), Math.abs(rR[i]));
  rmax = rmax || 1;
  for (let i = 0; i <= W + T; i++) {
    const p = (i % T) / T;
    const g = 0.09 * (0.4 + 0.6 * (0.5 + 0.5 * Math.sin(TAU * (2 * p + 0.3)))) / rmax;
    L[i] += g * rL[i % T] + 0.012 * aL[i % T];
    R[i] += g * rR[i % T] + 0.012 * aR[i % T];
  }
  // капли
  function dripAt(t0, f0, tau, v, pan, dur) {
    const n0 = Math.max(0, Math.round(t0 * sr)), n1 = Math.min(N, Math.round((t0 + dur) * sr));
    const gl = Math.sqrt(1 - pan), gr = Math.sqrt(pan);
    let ph = 0;
    for (let n = n0; n < n1; n++) {
      const u = n / sr - t0;
      const f = f0 * (0.78 + 0.22 * Math.exp(-u / 0.015)); // короткий спад высоты
      ph += TAU * f / sr;
      const e = Math.min(1, u / 0.004) * Math.exp(-u / tau);
      const s = (Math.sin(ph) + 0.28 * Math.sin(1.5 * ph + 0.5)) * e * v;
      L[n] += s * gl; R[n] += s * gr;
    }
  }
  let tt = -1.2 + rnd() * 3;
  while (tt < 60 + 0.5 - 1.7) { // хвост капель не пересекает конец файла
    const f0 = 600 + rnd() * 600, tau = 0.08 + rnd() * 0.1, v = 0.25 + rnd() * 0.25;
    const pan = 0.1 + rnd() * 0.8, dly = 0.18 + rnd() * 0.28;
    dripAt(tt, f0, tau, v, pan, 0.8);
    dripAt(tt + dly, f0 * 0.92, tau * 0.8, v * 0.35, 1 - pan, 0.5);       // эхо
    if (rnd() < 0.5) dripAt(tt + 2 * dly, f0 * 0.88, tau * 0.7, v * 0.13, pan, 0.4);
    tt += 1.6 + rnd() * 4.4;
  }
  return finishTrack('theme_cave.wav', outDir, sr, T, W, L, R);
}

/* ============================================================================
 * ТРЕК 3 — theme_tension.wav — бой/тревога, D Aeolian, ровно 110 BPM.
 * 27 тактов × 4 доли ⇒ T = 27·240/110 = 58.909 с (45–60 с ✓).
 * Пульс: «бочка» восьмыми (синус 115→44 Гц + шумовой клик + низкочастотный
 * шумовой удар; шум циклический) + шумовые акценты и 16-е хэты.
 * Остинато «виол»: сплошные 16-е (136 мс), пилы с вибрато, два ФНЧ ~430 Гц,
 * акцентная огибающая; низкий sustained корень. Гармония (27 тактов):
 * Dm Dm Bb Bb | Dm Dm Gm A | ... (×3) | Dm Dm Gm A | Gm A A → разрешение
 * в Dm на старте лупа. Кульминация: медный накат A2 в последних 7 тактах +
 * диссонантные аккорды-«жало». Сетка фазозахвачена циклом ⇒ луп без щелчка.
 * ==========================================================================*/
function genTension(outDir) {
  const sr = 44100, BPM = 110;
  const barS = 4 * 60 / BPM;             // такт = 2.181818 с
  const T = Math.round(27 * barS * sr);  // кадры цикла (27 тактов)
  const W = Math.round(0.5 * sr), N = W + T + 4096;
  const rnd = mulberry32(24680);
  const L = new Float64Array(N), R = new Float64Array(N);
  const sixS = barS / 16;                // 16-я = 0.13636 с
  const CHORDS = [50, 50, 46, 46, 50, 50, 43, 57, 50, 50, 46, 46, 50, 50, 43, 57,
    50, 50, 46, 46, 50, 50, 43, 57, 43, 57, 57]; // Dm Dm Bb Bb ... Gm A A
  const OST = { 50: [50, 53, 57, 53], 46: [46, 50, 53, 50], 43: [43, 46, 50, 46], 57: [57, 61, 64, 61] };
  const ACC = [1.0, 0.62, 0.9, 0.62];

  const nLP = cycLP(makeCycNoise(T, rnd), sr, 900, 3);
  const nHP = cycHP(makeCycNoise(T, rnd), sr, 4200, 3);
  const nHP2 = cycHP(makeCycNoise(T, rnd), sr, 6500, 3);

  function kick(i0, v) {
    const n1 = Math.min(N, i0 + Math.round(0.32 * sr)); let ph = 0;
    for (let n = Math.max(0, i0); n < n1; n++) {
      const u = (n - i0) / sr;
      ph += TAU * (44 + 71 * Math.exp(-u / 0.028)) / sr;
      const w = (0.55 * Math.sin(ph) * Math.exp(-u / 0.085)
        + 0.05 * nHP2[n % T] * Math.exp(-u / 0.006)) * v;
      L[n] += w; R[n] += w;
    }
  }
  function noiseHit(i0, durS, buf, amp, panL, panR) {
    const n1 = Math.min(N, i0 + Math.round(durS * sr));
    for (let n = Math.max(0, i0); n < n1; n++) {
      const u = (n - i0) / sr;
      const e = Math.min(1, u / 0.002) * Math.exp(-u / (durS * 0.35));
      const y = buf[n % T] * e * amp;
      L[n] += y * panL; R[n] += y * panR;
    }
  }
  const K = Math.ceil((T + W) / (sixS * sr)) + 4;
  for (let k = 0; k < K; k++) {
    const t0 = k * sixS, i0 = Math.round(t0 * sr);
    const barI = Math.floor(t0 / barS) % 27, ch = CHORDS[barI], pos16 = k % 16;
    if (pos16 % 2 === 0) { // восьмые: бочка + низкий шумовой удар
      kick(i0, pos16 === 0 ? 0.26 : (pos16 % 4 === 0 ? 0.20 : 0.16));
      noiseHit(i0, 0.09, nLP, pos16 === 0 ? 0.10 : 0.045, 1, 1);
    }
    if (pos16 % 4 === 2) noiseHit(i0, 0.05, nHP, 0.055, 0.9, 1);
    if (pos16 % 2 === 1) noiseHit(i0, 0.028, nHP2, 0.02, 0.85, 1);
    const o = OST[ch][pos16 % 4]; // остинато виол — все 16-е (паттерн на долю)
    addTone(L, R, t0, sixS * 0.92, midiF(o), {
      sr, A: 0.006, D: 0.04, S: 0.75, R: 0.05, g: 0.13 * ACC[pos16 % 4],
      vibR: 5.4, vibC: 8, vibIn: 0.15, lp: 430, lp2: 430,
      parts: [[1, 1], [2, 0.55], [3, 0.35], [4, 0.22]],
    });
    if (pos16 === 0) addTone(L, R, t0, barS * 0.98, midiF(o - 12), { // низкий корень
      sr, A: 0.03, D: 0.12, S: 0.85, R: 0.15, g: 0.11, parts: [[1, 1], [2, 0.25]], lp: 300,
    });
  }
  // медный накат A2: последние 7 тактов, заканчивается ровно на T
  addTone(L, R, 20 * barS, 7 * barS, midiF(45), {
    sr, A: 3.5, D: 1, S: 1, R: 2.6, g: 0.10, lp: 620, lp2: 620,
    parts: [[1, 1], [2, 0.6], [3, 0.4], [4, 0.25], [5, 0.15]], vibR: 0.7, vibC: 5, vibIn: 1,
  });
  // диссонантные аккорды-жало (Bb4+D5), сильные доли тактов 8 и 16
  for (const k16 of [7 * 16 + 8, 15 * 16 + 8]) {
    const t0 = k16 * sixS;
    const stab = [[70, 0.06, 0.8], [74, 0.05, 1.0]];
    for (const s of stab)
      addTone(L, R, t0, 0.42, midiF(s[0]), {
        sr, A: 0.01, D: 0.12, S: 0.3, R: 0.28, g: s[1], gl: s[2] * 0.7, gr: s[2],
        lp: 2400, parts: [[1, 1], [2, 0.7], [3, 0.5]], vibR: 6, vibC: 12, vibIn: 0.1,
      });
  }
  return finishTrack('theme_tension.wav', outDir, sr, T, W, L, R);
}

/* ---------------- main ---------------- */
function main() {
  const outDir = process.argv[2] ? path.resolve(process.argv[2]) : process.cwd();
  fs.mkdirSync(outDir, { recursive: true });
  const t0 = Date.now();
  const res = [genForest(outDir), genCave(outDir), genTension(outDir)];
  console.log(`\nГенерация: ${((Date.now() - t0) / 1000).toFixed(1)} с. Итог:`);
  let tot = 0;
  for (const r of res) { tot += r.bytes; console.log(`  ${r.name}: ${(r.bytes / 1048576).toFixed(2)} MB`); }
  console.log(`  всего: ${(tot / 1048576).toFixed(2)} MB`);
}
main();
