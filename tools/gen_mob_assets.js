// ============================================================================
// gen_mob_assets.js — арт-лист THREE боевых архетипов мобов («моб-волна»).
// Рисует в ПЕСОЧНИЦУ sand_m/pixel-rpg/assets/:
//   mobs_archer.png     — «Лесокров-лучник»   (48x64: 4 ряда x 3 кадра, клетка 16x16)
//   mobs_wraith.png     — «Тенеплёт»          (48x64, та же раскладка)
//   mobs_swarmling.png  — «Мглокрыс»          (48x64, та же раскладка)
// Раскладка — как лист героя (gen_assets3.js): ряды down/left/right/up,
// колонки: 0 = покой, 1 = шаг, 2 = действие (натяжка лука / материализация / укус).
// PNG-энкодер, Img, nz, палитра и outlineAA скопированы из gen_assets3.js
// (финальный арт-пасс v3 «тёмное фэнтези»): те же тона леса/камня/магии,
// индивидуальный акцент каждого моба: лучник — кровь (blood), тенеплёт —
// void/glow, мглокрыс — ядовитый бирюзовый (tox). Deterministic: Math.random
// не используется. Скрипт живёт ВНЕ репо (W/tools), в дифф не попадает.
// ============================================================================
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const OUT = path.join(__dirname, '..', 'sand_m', 'pixel-rpg', 'assets');
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
  get(x, y) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return null;
    const i = (y * this.w + x) * 4;
    if (this.d[i + 3] === 0) return null;
    return [this.d[i], this.d[i + 1], this.d[i + 2], this.d[i + 3]];
  }
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
function shadeC(c, k) { return [Math.round(c[0] * (1 - k)), Math.round(c[1] * (1 - k)), Math.round(c[2] * (1 - k))]; }
const WARM = [236, 214, 178];
const COOL = [38, 42, 62];
function lite(c, t = .4) { return mixC(c, WARM, t); }
function cool(c, t = .4) { return mixC(c, COOL, t); }

// ---------- Палитра v3 «тёмное фэнтези» (подмножество gen_assets3.js) + акценты ----------
const C = {
  skin: [198, 150, 116], skinL: [226, 182, 146], skinD: [160, 116, 90], skinDD: [124, 88, 74],
  eye: [36, 30, 42],
  leaf: [44, 72, 46], leafL: [66, 96, 60], leafXL: [92, 120, 72], leafD: [28, 50, 36], leafDD: [18, 34, 26],
  trunk: [84, 62, 42], trunkD: [60, 44, 30], trunkDD: [40, 30, 22], trunkL: [110, 82, 56],
  leather: [92, 64, 42], leatherD: [64, 44, 30], leatherL: [120, 88, 60],
  boot: [46, 36, 34], bootD: [28, 22, 24],
  blood: [122, 42, 46], bloodL: [162, 66, 62], bloodD: [82, 26, 32],
  steel: [148, 156, 172], steelL: [200, 210, 228], steelD: [100, 108, 126], steelDD: [64, 70, 88],
  quiverC: [104, 72, 44], quiverD: [74, 50, 32], featherW: [206, 200, 184], featherD: [150, 144, 130],
  arrowShaft: [118, 90, 58],
  wood: [96, 70, 46], woodD: [68, 48, 32], woodL: [124, 94, 62], woodHL: [152, 120, 82],
  bone: [206, 200, 182], boneD: [156, 150, 136], tooth: [216, 212, 196],
  voidB: [9, 9, 12], voidP: [22, 16, 30], voidP2: [32, 22, 42],
  glow: [166, 120, 208], glowL: [214, 182, 244], glowD: [112, 74, 152], glowTint: [84, 72, 104],
  tox: [72, 196, 184], toxL: [148, 238, 224], toxD: [38, 126, 120],
  cloud: [104, 110, 128], cloudD: [74, 80, 98], cloudL: [142, 148, 166],
  // --- мглокрыс: серо-бурая крысиная шкурка (свой материал, тон в духе bandM/rg) ---
  rat: [108, 92, 78], ratL: [138, 120, 102], ratXL: [170, 154, 134], ratD: [76, 62, 52], ratDD: [50, 40, 34],
  ratBelly: [150, 134, 116],
};

// ---------- ручной AA + «color line» — как gen_assets3.js ----------
function outlineAA(f, opt = {}) {
  const occ = (x, y) => x >= 0 && y >= 0 && x < f.w && y < f.h && f.d[(y * f.w + x) * 4 + 3] !== 0;
  const at = (x, y) => (x < 0 || y < 0 || x >= f.w || y >= f.h) ? null : f.get(x, y);
  const limitBottom = opt.limitBottom !== false;
  let maxRow = -1;
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) if (occ(x, y)) maxRow = y;
  const add = new Map();
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) {
    if (occ(x, y) || (limitBottom && y > maxRow)) continue;
    const l = occ(x - 1, y), r = occ(x + 1, y), u = occ(x, y - 1), d = occ(x, y + 1);
    let c = null;
    if (l && u && !r && !d) c = mixC(at(x - 1, y), at(x, y - 1), .5);
    else if (l && d && !r && !u) c = mixC(at(x - 1, y), at(x, y + 1), .5);
    else if (r && u && !l && !d) c = mixC(at(x + 1, y), at(x, y - 1), .5);
    else if (r && d && !l && !u) c = mixC(at(x + 1, y), at(x, y + 1), .5);
    if (c) add.set(x + ',' + y, shadeC(c, .1));
  }
  const inShape = (x, y) => occ(x, y) || add.has(x + ',' + y);
  if (!opt.aaOnly) {
    const dirs = opt.skipDown ? [[1, 0], [-1, 0], [0, -1]] : [[1, 0], [-1, 0], [0, -1], [0, 1]];
    const dk = [];
    for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++) {
      if (!occ(x, y)) continue;
      if (dirs.some(([dx, dy]) => !inShape(x + dx, y + dy))) dk.push([x, y, shadeC(at(x, y), .38)]);
    }
    for (const [x, y, c] of dk) f.set(x, y, c);
  }
  for (const [k, c] of add) { const [x, y] = k.split(',').map(Number); f.set(x, y, c); }
}
function hflip(s) {
  const o = new Img(s.w, s.h);
  for (let y = 0; y < s.h; y++) for (let x = 0; x < s.w; x++) o.set(s.w - 1 - x, y, s.get(x, y));
  return o;
}
function ell(f, cx, cy, rx, ry, c) {
  for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++)
    for (let x = Math.floor(cx - rx); x <= Math.ceil(cx + rx); x++) {
      const dx = (x - cx) / rx, dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1.02) f.set(x, y, c);
    }
}
// мех/кожа: тон по шуму между base и светлой/тёмной гранью
function furTone(x, y, base, l, d, seed) {
  const n = nz(x, y, 7, 11, seed, 100);
  if (n < 14) return l;
  if (n > 86) return d;
  return base;
}

// ============================================================================
// mobs_archer.png — «Лесокров-лучник»: корковый капюшон + лиственный плащ,
// акцент — кровь (кровавые прожилки на колчане и оперении, алые глаза).
// Клетка 16x16: ряды down/left/right/up; кол.0 покой, 1 шаг, 2 натяжка лука.
// ============================================================================
function archerCell(anim, dir) {
  // рисуем facing-left профиль и зеркалим; down/up — анфас/с спины
  const f = new Img(16, 16);
  const bob = anim === 1 ? -1 : 0;          // шаг: подскок корпуса
  const draw = anim === 2;
  const hood = C.leafD, hoodL = C.leafL, hoodLL = C.leafXL, hoodD = C.leafDD;
  const cloak = C.leaf, cloakD = C.leafD;
  const skin = dir === 'up' ? C.skinDD : C.skin;

  if (dir === 'down' || dir === 'up') {
    // ---- анфас / со спины ----
    const cx = 8, y0 = 2 + bob;
    // плащ-корпус
    for (let y = 0; y < 6; y++) {
      const w = 2 + Math.floor(y / 2);
      for (let x = cx - w; x <= cx + w; x++) {
        let c = furTone(x, y + y0, cloak, cloakD, hoodD, 5);
        if (x === cx - w) c = mixC(c, hoodLL, .35);       // тёплый rim-свет слева
        if (x === cx + w) c = cool(c, .35);               // холодная кромка справа
        f.set(x, y0 + 6 + y, c);
      }
    }
    // капюшон
    ell(f, cx, y0 + 3, 3.4, 3.2, hood);
    for (let x = cx - 3; x <= cx + 3; x++) f.set(x, y0 + 1, mixC(hood, hoodLL, .5));
    f.set(cx - 3, y0 + 2, hoodLL);
    if (dir === 'down') {
      // лицо в капюшоне: тень + алые глаза (акцент «лесокров»)
      f.rect(cx - 2, y0 + 3, 5, 3, C.eye);
      f.set(cx - 2, y0 + 4, C.bloodL); f.set(cx + 2, y0 + 4, C.bloodL);
      f.set(cx - 1, y0 + 6, skin); f.set(cx, y0 + 6, skin); f.set(cx + 1, y0 + 6, skin);
    } else {
      // спина: шов плаща + колчан с кроваво-красными кончиками стрел
      f.rect(cx, y0 + 6, 1, 6, hoodD);
      f.rect(cx - 5, y0 + 4, 2, 6, C.quiverC); f.rect(cx - 5, y0 + 9, 2, 1, C.quiverD);
      f.set(cx - 5, y0 + 3, C.blood); f.set(cx - 4, y0 + 3, C.bloodL);
      f.set(cx - 5, y0 + 2, C.arrowShaft); f.set(cx - 4, y0 + 2, C.arrowShaft);
      f.rect(cx + 4, y0 + 5, 1, 6, C.woodD);               // лук за спиной
      f.set(cx + 4, y0 + 4, C.woodL); f.set(cx + 4, y0 + 11, C.woodL);
    }
    // пояс с кровавым ремешком
    f.rect(cx - 4, y0 + 9, 9, 1, C.leatherD);
    f.set(cx, y0 + 9, C.blood);
    // ноги / сапоги
    const ly = y0 + 12;
    if (anim === 1) {
      f.rect(cx - 3, ly, 2, 2, C.boot); f.rect(cx + 1, ly - 1, 2, 2, C.boot);
      f.rect(cx - 3, ly + 1, 2, 1, C.bootD); f.rect(cx + 1, ly, 2, 1, C.bootD);
    } else {
      f.rect(cx - 2, ly, 2, 2, C.boot); f.rect(cx + 1, ly, 2, 2, C.boot);
      f.rect(cx - 2, ly + 1, 2, 1, C.bootD); f.rect(cx + 1, ly + 1, 2, 1, C.bootD);
    }
    // лук в руке (анфас: справа от корпуса; в натяжке — поднят)
    const bx = cx + 5, by = draw ? y0 + 1 : y0 + 5;
    for (let i = 0; i < 6; i++) f.set(bx, by + i, i === 0 || i === 5 ? C.woodL : C.wood);
    f.rect(bx - 1, by + 2, 1, 3, draw ? C.bone : C.featherD);   // тетива
    if (draw) {
      f.rect(bx - 3, by + 2, 4, 1, C.arrowShaft); f.set(bx - 4, by + 2, C.steelL);
      f.set(bx, by + 3, C.bloodD);
    }
    outlineAA(f);
    return f;
  }

  // ---- профиль (рисуем лицом влево; right = зеркало) ----
  const bx = 8;                                   // ось корпуса
  // ноги шага
  const ly = 12 + bob;
  if (anim === 1) {
    f.rect(bx - 3, ly, 2, 2, C.boot); f.rect(bx + 1, ly - 1, 2, 2, C.boot);
    f.rect(bx - 3, ly + 1, 2, 1, C.bootD); f.rect(bx + 1, ly, 2, 1, C.bootD);
  } else {
    f.rect(bx - 1, ly, 2, 2, C.boot); f.rect(bx + 1, ly, 2, 2, C.bootD);
  }
  // корпус-плащ (наклон назад в натяжке)
  const lean = draw ? 1 : 0;
  for (let y = 0; y < 7; y++) {
    const w = y < 3 ? 2 : 3;
    const ox = lean;
    for (let x = bx - w + ox; x <= bx + w + ox; x++) {
      let c = furTone(x, y, cloak, lite(cloak, .3), cloakD, 9);
      if (x === bx + w + ox) c = cool(c, .4);
      f.set(x, 5 + bob + y - (anim === 1 ? 1 : 0), c);
    }
  }
  // пояс
  f.rect(bx - 2 + lean, 10 + bob, 6, 1, C.leatherD);
  f.set(bx + lean, 10 + bob, C.blood);
  // капюшон профилем (нос книзу-влево)
  ell(f, bx + lean, 3 + bob, 3.1, 2.8, hood);
  f.rect(bx - 3 + lean, 3 + bob, 2, 2, hoodD);     // свес над лицом
  f.set(bx - 3 + lean, 2 + bob, mixC(hood, hoodLL, .6));
  f.rect(bx - 2 + lean, 4 + bob, 2, 2, C.eye);     // лицо в тени
  f.set(bx - 2 + lean, 4 + bob, C.bloodL);         // алый глаз — акцент
  // колчан за спиной (справа), оперение с кровавыми кончиками
  f.rect(bx + 4 + lean, 4 + bob, 2, 5, C.quiverC);
  f.rect(bx + 4 + lean, 8 + bob, 2, 1, C.quiverD);
  f.set(bx + 4, 3 + bob + lean, C.bloodL); f.set(bx + 5, 2 + bob + lean, C.blood);
  f.set(bx + 4, 2 + bob + lean, C.arrowShaft); f.set(bx + 5, 1 + bob + lean, C.arrowShaft);
  // ЛУК: дуга слева; в покое опущен, в натяжке поднят горизонтально
  if (!draw) {
    const ax = bx - 5;
    for (let i = 0; i < 7; i++) {
      const bulge = i === 0 || i === 6 ? 0 : i === 3 ? -1 : 0;
      f.set(ax + bulge, 6 + bob + i, i === 0 || i === 6 ? C.woodL : C.wood);
    }
    for (let i = 0; i < 7; i++) f.set(ax + 1, 6 + bob + i, C.featherD); // тетива прямая
    f.set(ax + 1, 9 + bob, C.boneD);
  } else {
    const ay = 4 + bob;
    for (let i = 0; i < 7; i++) {
      const bulge = i === 0 || i === 6 ? 0 : i === 3 ? -1 : 0;
      f.set(1 + bulge, ay + i, i === 0 || i === 6 ? C.woodL : C.wood);
    }
    f.rect(3, ay, 1, 7, C.featherD);                      // тетива
    f.rect(3, ay + 3, 5, 1, C.arrowShaft);                // стрела в натяг
    f.set(2, ay + 3, C.steelL); f.set(8, ay + 3, C.bloodL); // остриё / оперение
    f.set(bx - 1 + lean, ay + 3, C.skinL);                // рука-натяг у щеки
    f.set(bx - 2 + lean, 4 + bob, C.bloodL);              // алый глаз вспыхнул
  }
  outlineAA(f, { skipDown: false });
  return f;
}
function genArcher() {
  const sheet = new Img(48, 64);
  const rows = ['down', 'left', 'right', 'up'];
  for (let r = 0; r < 4; r++) for (let c = 0; c < 3; c++) {
    const dir = rows[r];
    const cell = dir === 'right' ? hflip(archerCell(c, 'left')) : archerCell(c, dir);
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) sheet.set(c * 16 + x, r * 16 + y, cell.get(x, y));
  }
  sheet.save('mobs_archer.png');
}

// ============================================================================
// mobs_wraith.png — «Тенеплёт»: клочья void-ткани, фиолетовое свечение (glow),
// парит (нет ног, рваный подол), в «материализации» (кол.2) плотнее и со светлыми
// когтями. Клетка 16x16: ряды down/left/right/up.
// ============================================================================
function wraithCell(anim, dir) {
  const f = new Img(16, 16);
  const mat = anim === 2;
  const hover = anim === 1 ? -1 : 0;
  const body = mat ? C.glowTint : C.voidP;
  const bodyD = mat ? shadeC(C.glowTint, .25) : C.voidB;
  const edge = mat ? C.glowD : C.voidP2;
  const eye = mat ? C.glowL : C.glow;
  const cx = 8;
  // капюшон + плечи (перевернутая капля), лёгкая асимметрия по анимации
  const wob = anim === 1 ? 1 : 0;
  for (let y = 0; y < 9; y++) {
    const w = y < 2 ? 2 : y < 4 ? 3 : 4;
    for (let x = cx - w; x <= cx + w; x++) {
      if (Math.abs(x - cx) === w && y < 2) continue;    // скругление макушки
      let c = nz(x, y, 5, 9, 3 + anim, 100) < 16 ? edge : body;
      if (x === cx - w) c = mixC(c, mat ? C.glow : C.glowD, .45);       // rim-свет слева
      if (x === cx + w) c = mixC(c, bodyD, .6);                          // тень справа
      f.set(x, 1 + hover + y + (y > 5 ? wob : 0), c);
    }
  }
  // подол-клочья: зубцы разной высоты, дрожат по кадру (deterministic-шум)
  const hemY = 10 + hover;
  for (let i = 0; i < 9; i++) {
    const x = cx - 4 + i;
    const h = 2 + nz(x, anim, 7, 3, 11, 3);
    for (let j = 0; j < h; j++) {
      const fade = j === h - 1 ? edge : body;
      f.set(x, hemY + j, fade);
    }
  }
  // дымные отростки по бокам (клакоться, дёргается по кадрам)
  for (const [sx, sy] of [[cx - 5, 5], [cx + 5, 6], [cx - 6, 8], [cx + 6, 9]]) {
    const on = nz(sx, sy + anim * 4, 13, 5, 7, 3) !== 0;
    if (on) f.set(sx + (anim === 1 ? 1 : 0), sy + hover, mat ? C.glowD : C.voidP2);
  }
  // лицо: пустая ниша + глаза; спина (up) — ниши нет, только шов свечения
  if (dir === 'down' || dir === 'left' || dir === 'right') {
    const ex = dir === 'down' ? 0 : -1;              // профиль: глаза к носу
    const ey = 4 + hover;
    f.rect(cx - 2 + (dir === 'down' ? 0 : 0), ey, 5, 3, bodyD);
    if (dir === 'down') {
      f.set(cx - 2, ey + 1, eye); f.set(cx + 2, ey + 1, eye);
      if (mat) { f.set(cx - 2, ey + 1, C.glowL); f.set(cx + 2, ey + 1, C.glowL); }
    } else {
      f.set(cx - 1 + ex, ey + 1, eye); f.set(cx + ex, ey + 1, eye);
    }
    // светящееся «сердце» — ядро материализации
    if (mat) { f.set(cx, 7 + hover, C.glowL); f.set(cx - 1, 7 + hover, C.glow); f.set(cx + 1, 7 + hover, C.glow); }
  } else {
    f.rect(cx, 4 + hover, 1, 5, mixC(C.voidP2, C.glowD, .4));
  }
  // когти: материализация выбрасывает бледные конечности
  if (mat) {
    if (dir === 'down' || dir === 'up') {
      f.rect(cx - 6, 7 + hover, 2, 1, C.glowL); f.rect(cx + 5, 7 + hover, 2, 1, C.glowL);
      f.set(cx - 7, 7 + hover, C.bone); f.set(cx + 7, 7 + hover, C.bone);
    } else {
      f.rect(cx - 7, 6 + hover, 3, 1, C.glowL); f.set(cx - 8, 6 + hover, C.bone);
      f.rect(cx - 7, 8 + hover, 2, 1, C.glowD);
    }
  } else if (dir === 'left' || dir === 'right') {
    f.set(cx - 5, 7 + hover, bodyD);
  }
  outlineAA(f, { limitBottom: false });
  return f;
}
function genWraith() {
  const sheet = new Img(48, 64);
  const rows = ['down', 'left', 'right', 'up'];
  for (let r = 0; r < 4; r++) for (let c = 0; c < 3; c++) {
    const dir = rows[r];
    const cell = dir === 'right' ? hflip(wraithCell(c, 'left')) : wraithCell(c, dir);
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) sheet.set(c * 16 + x, r * 16 + y, cell.get(x, y));
  }
  sheet.save('mobs_wraith.png');
}

// ============================================================================
// mobs_swarmling.png — «Мглокрыс»: мелкий (тело ~9x5 px), серо-бурая шкурка,
// ядовито-бирюзовые глаза (tox), длинный хвост, клочья мглы у лап.
// Клетка 16x16: ряды down/left/right/up; кол.2 — укус (оскал).
// ============================================================================
function ratCell(anim, dir) {
  const f = new Img(16, 16);
  const hop = anim === 1 ? -1 : 0;
  const bite = anim === 2;
  const fur = (x, y) => furTone(x, y, C.rat, C.ratL, C.ratD, 17);
  const glow = bite ? C.toxL : C.tox;

  if (dir === 'down' || dir === 'up') {
    const cx = 8, cy = 11 + hop;
    // тело-капля
    ell(f, cx, cy, bite ? 4.2 : 3.8, bite ? 2.8 : 3.2, C.rat);
    for (let y = cy - 3; y <= cy + 3; y++) for (let x = cx - 4; x <= cx + 4; x++) {
      if (!f.get(x, y)) continue;
      let c = fur(x, y);
      if (y >= cy + 1 && dir === 'down' && Math.abs(x - cx) <= 2) c = mixC(c, C.ratBelly, .5);
      if (x === cx - 4 || x === cx + 4) c = cool(c, .3);
      f.set(x, y, c);
    }
    // уши
    ell(f, cx - 3, cy - 3 + hop, 1.3, 1.3, C.ratD); ell(f, cx + 3, cy - 3 + hop, 1.3, 1.3, C.ratD);
    f.set(cx - 3, cy - 3 + hop, mixC(C.ratDD, C.skinD, .5)); f.set(cx + 3, cy - 3 + hop, mixC(C.ratDD, C.skinD, .5));
    if (dir === 'down') {
      // Морда анфас: светящиеся глаза + усики + оскал на укусе
      f.set(cx - 2, cy - 1, glow); f.set(cx + 2, cy - 1, glow);
      if (bite) { f.set(cx - 2, cy - 2, C.toxL); f.set(cx + 2, cy - 2, C.toxL); }
      f.set(cx - 4, cy, C.cloudD); f.set(cx + 4, cy, C.cloudD);
      f.set(cx - 5, cy - 1, C.cloud); f.set(cx + 5, cy - 1, C.cloud);
      if (bite) {
        f.rect(cx - 1, cy + 1, 3, 1, C.eye);
        f.set(cx - 1, cy + 1, C.tooth); f.set(cx + 1, cy + 1, C.tooth);
      } else {
        f.set(cx, cy + 1, mixC(C.skinD, C.blood, .4));
      }
    } else {
      // спина: тёмный хребет + хвост к зрителю кольцом
      f.rect(cx, cy - 2, 1, 4, C.ratD);
      f.set(cx, cy + 3, C.ratDD); f.set(cx + 1, cy + 4, C.ratD); f.set(cx - 1, cy + 4, C.ratDD);
    }
    // лапки
    f.set(cx - 2, cy + 3, C.ratDD); f.set(cx + 2, cy + 3, C.ratDD);
    // мгла под носом (пиксельные клочья, дёргаются по кадру)
    for (let i = 0; i < 5; i++) {
      const x = cx - 3 + i * 2 - 1 + (anim === 1 ? 1 : 0);
      if (nz(x, anim, 9, 3, 5, 3) !== 0) f.set(x, 15, C.cloudD);
    }
    outlineAA(f);
    return f;
  }

  // ---- профиль влево ----
  const cy = 11 + hop;
  // тело
  ell(f, 9, cy, 3.4, 2.6, C.rat);
  // голова
  ell(f, 4, cy - 1, 2.4, 2.1, C.rat);
  for (let y = cy - 4; y <= cy + 3; y++) for (let x = 1; x <= 13; x++) {
    const g = f.get(x, y);
    if (!g) continue;
    let c = fur(x, y);
    if (y >= cy + 1 && x >= 3 && x <= 9) c = mixC(c, C.ratBelly, .45);
    if (x === 13 || (y === cy + 3 && x < 13)) c = cool(c, .25);
    f.set(x, y, c);
  }
  // морда: нос-кнопка + усики из мглы
  f.set(1, cy - 1, bite ? C.toxL : C.ratDD);
  f.set(1, cy - 2, C.cloudD); f.set(2, cy + 1, C.cloud);
  // глаз светится
  f.set(4, cy - 2, glow);
  if (bite) f.set(5, cy - 2, C.tox);
  // оскал
  if (bite) { f.set(2, cy, C.eye); f.set(2, cy - 1, C.tooth); f.set(3, cy, C.tooth); }
  // ухо
  ell(f, 5, cy - 3, 1.2, 1.2, C.ratD); f.set(5, cy - 3, mixC(C.ratDD, C.skinD, .4));
  // лапы: чередование шага
  if (anim === 1) {
    f.set(5, cy + 3, C.ratDD); f.set(10, cy + 2, C.ratDD);
    f.set(7, cy + 3, C.ratDD);
  } else {
    f.set(5, cy + 3, C.ratDD); f.set(9, cy + 3, C.ratDD);
  }
  // хвост: дуга вправо-вверх, кончик дрожит
  const ty = cy - 2 - (anim === 1 ? 1 : 0);
  f.rect(13, cy, 1, 1, C.ratD); f.set(14, cy - 1, C.ratD); f.set(14, ty, C.ratDD); f.set(15, ty, C.ratDD);
  // мгла у лап
  for (let i = 0; i < 4; i++) {
    const x = 3 + i * 3 + (anim === 1 ? 1 : 0);
    if (nz(x, anim + 3, 9, 3, 5, 3) !== 0) f.set(x, 15, C.cloudD);
  }
  outlineAA(f);
  return f;
}
function genSwarmling() {
  const sheet = new Img(48, 64);
  const rows = ['down', 'left', 'right', 'up'];
  for (let r = 0; r < 4; r++) for (let c = 0; c < 3; c++) {
    const dir = rows[r];
    const cell = dir === 'right' ? hflip(ratCell(c, 'left')) : ratCell(c, dir);
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) sheet.set(c * 16 + x, r * 16 + y, cell.get(x, y));
  }
  sheet.save('mobs_swarmling.png');
}

genArcher();
genWraith();
genSwarmling();

console.log('--- verification mob wave ---');
for (const [name, w, h] of [['mobs_archer.png', 48, 64], ['mobs_wraith.png', 48, 64], ['mobs_swarmling.png', 48, 64]]) {
  const b = fs.readFileSync(path.join(OUT, name));
  const sig = [...b.slice(0, 8)].map(v => v.toString(16).padStart(2, '0').toUpperCase()).join(' ');
  const ihdrW = b.readUInt32BE(16), ihdrH = b.readUInt32BE(20);
  const ok = ihdrW === w && ihdrH === h && sig === '89 50 4E 47 0D 0A 1A 0A';
  console.log(name, ihdrW + 'x' + ihdrH, ok ? 'OK' : 'FAIL');
}
console.log('DONE mob wave');
