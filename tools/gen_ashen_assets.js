// ============================================================================
// gen_ashen_assets.js — тайл-атлас зоны «Пепелище» (зона-2).
// Рисует в ПЕСОЧНИЦУ sand_z2/pixel-rpg/assets/:
//   ashen_tiles.png — 128x16, 8 тайлов 16x16 в одну строку:
//     0 '.' пепельная земля (пол)
//     1 ',' золистая осыпь с тлеющими угольками (пол)
//     2 'c' потрескавшаяся земля (пол)
//     3 'a' утрамбованный пол арены (пол)
//     4 'T' сухое мёртвое дерево (блокировщик: тёмный контур + светлый верх)
//     5 'K' обгоревший пень (блокировщик: светлый срез сверху)
//     6 '#' упавшее обугленное бревно (блокировщик)
//     7 'P' пепельный портал — кольцо из костей + фиолетовая руна (проходим)
// PNG-энкодер, Img, nz, mixC скопированы из gen_mob_assets.js (он — из
// gen_assets3.js, финальный арт-пасс v3 «тёмное фэнтези»): та же техника,
// палитра расширена «пепельным» подмножеством (серые земли + уголь + угли).
// Правило силуэта: у блокировщика тёмный контур (lum<50, >=14 px) и светлая
// верхняя кромка (lum>115 в верхней половине) на фоне светлого пола.
// Deterministic: Math.random не используется.
// ============================================================================
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const OUT = path.join(__dirname, '..', 'pixel-rpg', 'assets');
fs.mkdirSync(OUT, { recursive: true });

// ---------- PNG encoder (RGBA, 8-bit, no interlace) — как gen_assets3.js ----------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) crc = CRC_TABLE[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const t = Buffer.from(type, 'ascii');
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}
function savePng(name, w, h, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; // 8-bit RGBA
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  const png = Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
  fs.writeFileSync(path.join(OUT, name), png);
  console.log('wrote', name, w + 'x' + h, png.length + 'B');
}

// ---------- Canvas helper — как gen_assets3.js ----------
class Img {
  constructor(w, h) { this.w = w; this.h = h; this.d = Buffer.alloc(w * h * 4); }
  set(x, y, c) {
    if (!c || x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const i = (y * this.w + x) * 4;
    this.d[i] = c[0]; this.d[i + 1] = c[1]; this.d[i + 2] = c[2];
    this.d[i + 3] = c.length > 3 ? c[3] : 255;
  }
  rect(x, y, w, h, c) { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, c); }
  save(name) { savePng(name, this.w, this.h, this.d); }
}
function nz(x, y, a, b, c, n) {
  let v = (x * a + y * b + c) % 9973;
  v = (v * 13 + 7) % 65521;
  return v % n;
}
function mixC(a, b, t) {
  return [Math.round(a[0] + (b[0] - a[0]) * t), Math.round(a[1] + (b[1] - a[1]) * t), Math.round(a[2] + (b[2] - a[2]) * t)];
}

// ---------- Пепельная палитра (дух v3 «тёмное фэнтези», холодное северя) ----------
const C = {
  ash0: [92, 90, 100],      // база пепельной земли
  ash1: [106, 104, 114],    // светлое зерно
  ashXL: [122, 120, 132],   // вспышки золы
  ashD: [72, 70, 80],       // тёмное зерно
  ashDD: [56, 54, 64],      // галька/тени на земле
  arena: [82, 80, 90],      // утрамбованный пол арены (чуть темнее поля)
  cinder: [44, 42, 52],     // золистая осыпь
  cinderD: [34, 32, 42],
  char: [34, 30, 40],       // обугленное дерево (тело блокировщиков)
  charL: [56, 50, 64],      // обгорелая кора, блики
  charDD: [22, 20, 28],     // контур блокировщика
  litTop: [150, 144, 156],  // светлая кромка сверху (холодный свет)
  cut: [132, 126, 116],     // светлый спил пня
  cutD: [100, 94, 88],
  ember: [232, 150, 84],    // тлеющий уголёк
  emberM: [196, 92, 48],
  emberD: [140, 54, 34],
  bone: [206, 200, 182],    // кость (из v3)
  boneD: [156, 150, 136],
  violet: [146, 110, 186],  // руна портала
  violetD: [70, 60, 84],    // выжженный круг под руной
};

// отрисовать точку тайла t (0..7) в общий лист
function P(img, t, x, y, c) { img.set(t * 16 + x, y, c); }

// детерминированная линия Брезенхера в тайле
function line(img, t, x0, y0, x1, y1, c) {
  let dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0);
  let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy;
  for (;;) {
    P(img, t, x0, y0, c);
    if (x0 === x1 && y0 === y1) break;
    const e2 = 2 * err;
    if (e2 >= dy) { err += dy; x0 += sx; }
    if (e2 <= dx) { err += dx; y0 += sy; }
  }
}

// выжженная земля вокруг блокировщика — тёмная «лужа» пепла (читаемость силуэта)
function scorch(img, t, x0, y0, x1, y1, seed) {
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    if (nz(x + seed, y * 2 + seed, 89, 61, 13, 4) === 0) continue; // дырочки — не клякса
    P(img, t, x, y, nz(x + seed, y + seed, 31, 17, 7, 3) === 0 ? C.cinder : C.ashDD);
  }
}

// базовый пепельный пол тайла (семя seed сдвигает узор, тайлы не близнецы)
function ashFloor(img, t, seed, base) {
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c = base || C.ash0;
    if (nz(x + seed, y * 2 + seed, 91, 53, 7, 13) === 0) c = C.ashD;
    else if (nz(x * 2 + seed, y + seed, 37, 97, 5, 11) === 0) c = C.ash1;
    else if (nz(x + seed, y + seed, 13, 29, 3, 29) === 0) c = C.ashXL;
    else if (nz(x * 3 + seed, y * 2 + seed, 101, 67, 17, 37) === 0) c = C.ashDD;
    else if (nz(x + seed, y * 3 + seed, 211, 173, 9, 89) === 0) c = C.emberD; // единичные угольки
    P(img, t, x, y, c);
  }
}

// ---- 0 '.' пепельная земля ----
function tileAsh(img) { ashFloor(img, 0, 1); }

// ---- 1 ',' золистая осыпь с углями ----
function tileCinder(img) {
  ashFloor(img, 1, 5);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const dx = (x - 8) / 6.2, dy = (y - 10.5) / 3.6;
    const r = dx * dx + dy * dy;
    if (r <= 1.0) {
      let c = C.cinder;
      if (r > 0.72) c = C.cinderD;
      if (nz(x + 31, y + 17, 71, 43, 3, 9) === 0) c = C.char;
      P(img, 1, x, y, c);
    }
  }
  // тлеющие угольки по краю осыпи
  P(img, 1, 4, 10, C.emberM); P(img, 1, 5, 10, C.ember);
  P(img, 1, 11, 12, C.emberM); P(img, 1, 8, 8, C.emberD);
  P(img, 1, 12, 9, C.emberM); P(img, 1, 3, 12, C.emberD);
}

// ---- 2 'c' потрескавшаяся земля ----
function tileCracked(img) {
  ashFloor(img, 2, 9);
  const crack = (pts) => {
    for (let i = 0; i < pts.length - 1; i++) line(img, 2, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], C.ashDD);
    for (let i = 0; i < pts.length - 1; i++) line(img, 2, pts[i][0], pts[i][1] + 1, pts[i + 1][0], pts[i + 1][1] + 1, mixC(C.ash0, C.ash1, 0.6));
  };
  crack([[1, 3], [5, 5], [7, 9], [12, 11], [15, 14]]);
  crack([[10, 1], [11, 4], [14, 6]]);
  crack([[2, 9], [4, 12]]);
}

// ---- 3 'a' пол арены ----
function tileArena(img) {
  ashFloor(img, 3, 13, C.arena);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    if (nz(x + 41, y + 23, 59, 83, 11, 17) === 0) P(img, 3, x, y, mixC(C.arena, C.ashDD, 0.5));
    if (nz(x + 7, y + 61, 127, 31, 5, 59) === 0) P(img, 3, x, y, C.boneD); // костяшки
  }
}

// ---- 4 'T' мёртвое дерево (блокировщик) ----
function tileTree(img) {
  ashFloor(img, 4, 21);
  scorch(img, 4, 3, 12, 12, 15, 2); // выжженная земля у корней
  const D = C.charDD, B = C.char, L = C.charL, T = C.litTop;
  // ствол (утолщён книзу)
  for (let y = 4; y <= 15; y++) for (let x = 7; x <= 8; x++) P(img, 4, x, y, B);
  for (let y = 9; y <= 15; y++) for (let x = 6; x <= 9; x++) P(img, 4, x, y, B);
  for (let y = 13; y <= 15; y++) for (let x = 5; x <= 10; x++) P(img, 4, x, y, B);
  for (let y = 5; y <= 14; y += 3) P(img, 4, 7, y, L);
  for (let y = 13; y <= 15; y++) { P(img, 4, 5, y, D); P(img, 4, 10, y, D); } // корни в контур
  // ветви
  line(img, 4, 7, 9, 3, 5, B); line(img, 4, 7, 8, 3, 4, B);
  line(img, 4, 8, 7, 12, 3, B); line(img, 4, 8, 6, 12, 2, B);
  line(img, 4, 6, 11, 2, 10, B); line(img, 4, 9, 10, 13, 9, B);
  line(img, 4, 3, 4, 2, 2, B); line(img, 4, 3, 4, 4, 1, B);
  line(img, 4, 12, 2, 11, 0, B); line(img, 4, 12, 2, 14, 1, B); line(img, 4, 12, 3, 14, 0, B);
  line(img, 4, 7, 4, 6, 1, B); line(img, 4, 8, 4, 9, 0, B); line(img, 4, 8, 4, 10, 2, B);
  // обвес — свисающая обугальная прядь
  line(img, 4, 10, 4, 10, 8, C.char);
  // тёмный контур низа ствола
  for (let x = 5; x <= 10; x++) P(img, 4, x, 15, D);
  // СВЕТЛАЯ кромка: верхушки ветвей освещены холодным светом
  line(img, 4, 2, 2, 2, 1, T); P(img, 4, 4, 1, T); P(img, 4, 3, 3, T);
  line(img, 4, 11, 0, 14, 0, T); P(img, 4, 14, 1, T); P(img, 4, 12, 1, T);
  P(img, 4, 6, 1, T); P(img, 4, 9, 0, T); P(img, 4, 10, 2, T); P(img, 4, 7, 3, T);
  // тление у корней
  P(img, 4, 5, 14, C.emberM); P(img, 4, 10, 14, C.emberD); P(img, 4, 5, 13, C.emberD);
}

// ---- 5 'K' обгоревший пень (блокировщик, светлый спил) ----
function tileStump(img) {
  ashFloor(img, 5, 33);
  scorch(img, 5, 2, 12, 13, 15, 8); // выжженная земля вокруг пня
  const D = C.charDD, B = C.char, L = C.charL;
  for (let y = 9; y <= 15; y++) for (let x = 3; x <= 12; x++) {
    let c = B;
    if (x === 3 || x === 12) c = D;
    else if ((x + 4) % 3 === 0 && y > 10) c = C.charDD;
    else if (nz(x + 3, y, 73, 29, 5, 7) === 0) c = L;
    P(img, 5, x, y, c);
  }
  // спил — светлая верхушка (акцент силуэта)
  for (let x = 4; x <= 11; x++) P(img, 5, x, 8, D);
  for (let x = 3; x <= 12; x++) P(img, 5, x, 9, C.cut);
  for (let x = 4; x <= 11; x++) P(img, 5, x, 9, C.cut);
  P(img, 5, 5, 9, C.cutD); P(img, 5, 6, 9, C.cut); P(img, 5, 7, 9, C.cutD);
  P(img, 5, 3, 10, D); P(img, 5, 12, 10, D);
  for (let x = 3; x <= 12; x++) P(img, 5, x, 15, D);
  // уголёк на спиле и у основания
  P(img, 5, 8, 9, C.emberM); P(img, 5, 2, 14, C.emberD); P(img, 5, 13, 14, C.emberM);
}

// ---- 6 '#' упавшее обугленное бревно (блокировщик) ----
function tileBeam(img) {
  ashFloor(img, 6, 45);
  scorch(img, 6, 2, 9, 13, 14, 14); // выжженная борозда под бревном
  const D = C.charDD, B = C.char, T = C.litTop;
  // бревно по диагонали (2,11) -> (13,3), толщина 3, низ в контур, верх светлый
  const pts = [[2, 11], [5, 9], [9, 6], [13, 3]];
  for (let i = 0; i < pts.length - 1; i++) {
    const a = pts[i], b = pts[i + 1];
    line(img, 6, a[0], a[1] - 1, b[0], b[1] - 1, T);   // светлая верхняя кромка
    line(img, 6, a[0], a[1], b[0], b[1], B);
    line(img, 6, a[0], a[1] + 1, b[0], b[1] + 1, B);
    line(img, 6, a[0] + 1, a[1] + 2, b[0] + 1, b[1] + 2, C.charDD);
    line(img, 6, a[0], a[1] + 3, b[0], b[1] + 3, D);   // тёмный низ
  }
  // щепастые концы
  line(img, 6, 13, 3, 15, 1, B); line(img, 6, 13, 4, 15, 4, C.charDD);
  line(img, 6, 2, 11, 0, 12, B);
  // трещина с тлением
  P(img, 6, 7, 7, C.emberM); P(img, 6, 8, 6, C.emberD);
  // обломки и второе короткое полено («завал»)
  for (let x = 3; x <= 8; x++) { P(img, 6, x, 13, B); P(img, 6, x, 14, x == 3 || x == 8 ? D : C.charDD); }
  P(img, 6, 3, 12, T); P(img, 6, 4, 12, mixC(B, T, 0.4));
  P(img, 6, 13, 12, C.ashDD); P(img, 6, 14, 12, C.ashDD); P(img, 6, 3, 6, C.ashDD);
  P(img, 6, 11, 12, D); P(img, 6, 12, 13, D);
}

// ---- 7 'P' пепельный портал (проходимый, читаемый маркер) ----
function tilePortal(img) {
  ashFloor(img, 7, 57);
  const cx = 8, cy = 8;
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const dx = x - cx, dy = y - cy;
    const r = Math.sqrt(dx * dx + dy * dy);
    if (r <= 6.6) P(img, 7, x, y, mixC(C.ash0, C.violetD, r <= 5.4 ? 0.85 : 0.45));
    // кольцо из костей — прерывистое
    if (r >= 5.8 && r <= 6.8 && (x + 2 * y) % 3 !== 0) P(img, 7, x, y, C.bone);
    if (r >= 5.8 && r <= 6.8 && (x + 2 * y) % 3 === 0) P(img, 7, x, y, C.boneD);
  }
  // руна — ромб
  const run = [[0, -3], [-1, -2], [1, -2], [-2, -1], [2, -1], [-2, 0], [2, 0], [-1, 1], [1, 1], [0, 2], [0, 0], [-1, 0], [1, 0], [0, -1]];
  for (const p of run) P(img, 7, cx + p[0], cy + p[1], C.violet);
  P(img, 7, cx, cy, mixC(C.violet, C.bone, 0.5));
  // угли-стороны
  P(img, 7, 8, 1, C.ember); P(img, 7, 8, 14, C.emberM);
  P(img, 7, 1, 8, C.emberM); P(img, 7, 14, 8, C.ember);
}

// ---------- сборка листа ----------
const img = new Img(128, 16);
tileAsh(img);
tileCinder(img);
tileCracked(img);
tileArena(img);
tileTree(img);
tileStump(img);
tileBeam(img);
tilePortal(img);
img.save('ashen_tiles.png');
console.log('OK: 8 тайлов Пепелища ->', OUT);
