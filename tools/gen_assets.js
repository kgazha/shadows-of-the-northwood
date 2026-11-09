// Генератор пиксель-арт ассетов для "Тени Северного Леса" (Godot 4)
// Чистый Node.js (zlib), без внешних зависимостей.
// Результат: pixel-rpg/assets/*.png
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const OUT = path.join(__dirname, '..', 'pixel-rpg', 'assets');
fs.mkdirSync(OUT, { recursive: true });

// ---------- PNG encoder (RGBA, 8-bit, no interlace) ----------
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
    raw[y * (stride + 1)] = 0; // filter: None
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  const png = Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
  fs.writeFileSync(path.join(OUT, name), png);
  console.log('wrote', name, w + 'x' + h, png.length + 'B');
}

// ---------- Canvas helper ----------
class Img {
  constructor(w, h) { this.w = w; this.h = h; this.d = Buffer.alloc(w * h * 4); }
  set(x, y, c) {
    if (!c || x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const i = (y * this.w + x) * 4;
    this.d[i] = c[0]; this.d[i + 1] = c[1]; this.d[i + 2] = c[2];
    this.d[i + 3] = c.length > 3 ? c[3] : 255;
  }
  rect(x, y, w, h, c) { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, c); }
  frame(x, y, w, h, c) {
    for (let i = 0; i < w; i++) { this.set(x + i, y, c); this.set(x + i, y + h - 1, c); }
    for (let j = 0; j < h; j++) { this.set(x, y + j, c); this.set(x + w - 1, y + j, c); }
  }
  blit(src, ox, oy = 0) {
    for (let j = 0; j < src.h; j++) for (let i = 0; i < src.w; i++) this.set(ox + i, oy + j, src.get(i, j));
  }
  get(x, y) {
    const i = (y * this.w + x) * 4;
    if (this.d[i + 3] === 0) return null;
    return [this.d[i], this.d[i + 1], this.d[i + 2], this.d[i + 3]];
  }
  save(name) { savePng(name, this.w, this.h, this.d); }
}

// ---------- Палитра ----------
const C = {
  skin: [240, 180, 140], skinD: [214, 152, 116],
  eye: [40, 30, 45], mouth: [170, 90, 80],
  hairP: [120, 70, 40], hairD: [70, 45, 30], gray: [205, 205, 210], grayD: [160, 160, 168],
  tunic: [60, 110, 200], tunicD: [44, 82, 160],
  robe: [130, 95, 160], robeD: [100, 70, 128],
  apron: [215, 190, 110], apronD: [175, 150, 85],
  belt: [90, 60, 35], pants: [72, 72, 95], boot: [62, 42, 32],
  grass: [88, 160, 70], grassL: [104, 178, 84], grassD: [70, 136, 58],
  flowerR: [230, 90, 90], flowerY: [240, 210, 90], flowerW: [240, 240, 240],
  dirt: [190, 160, 110], dirtD: [162, 132, 90], dirtL: [205, 180, 135],
  water: [72, 132, 222], waterD: [55, 108, 190], waterL: [135, 185, 245],
  trunk: [122, 82, 52], trunkD: [95, 62, 40],
  leaf: [44, 122, 58], leafL: [74, 152, 76], leafD: [32, 96, 46],
  wall: [224, 204, 170], wallD: [188, 168, 138],
  roof: [172, 72, 60], roofD: [140, 55, 48],
  wood: [142, 96, 56], woodD: [106, 70, 40], gold: [236, 196, 80],
  rock: [152, 152, 162], rockD: [112, 112, 122], rockL: [182, 182, 190],
  slimeG: [92, 200, 92], slimeD: [52, 150, 58], slimeL: [172, 240, 152],
  herbG: [62, 150, 72], herbR: [222, 62, 62],
  heart: [222, 52, 62], heartD: [150, 32, 44],
};

// детерминированный шум
function noise(x, y, a, b) { return ((x * a + y * b * 7 + 13) * 2654435761 % 4294967296) % 23; }

// ---------- Персонаж 16x16 ----------
// dirs: 0=down 1=left 2=right 3=up ; frames: 0=idle,1=шаг левой,2=шаг правой
function drawChar(opts, dir, step) {
  const f = new Img(16, 16);
  const hair = opts.hair, tunic = opts.tunic, tunicD = opts.tunicD, skin = C.skin;
  // --- голова ---
  f.rect(5, 2, 6, 1, hair);           // макушка
  f.rect(4, 3, 8, 1, hair);           // волосы
  if (dir === 3) {                    // спиной: волосы целиком
    f.rect(5, 4, 6, 2, hair);
  } else {
    f.rect(4, 4, 1, 2, hair);         // виски
    f.rect(11, 4, 1, 2, hair);
    f.rect(5, 4, 6, 2, skin);         // лицо
    f.set(5, 5, C.skinD); f.set(10, 5, C.skinD);
    if (dir === 0) { f.set(6, 5, C.eye); f.set(9, 5, C.eye); }
    if (dir === 1) { f.set(6, 5, C.eye); }
    if (dir === 2) { f.set(9, 5, C.eye); }
  }
  f.rect(6, 6, 4, 1, C.skin);         // подбородок
  if (dir === 0) f.set(7, 6, C.mouth), f.set(8, 6, C.mouth);
  // --- тело ---
  f.rect(6, 7, 4, 2, tunic);
  f.rect(5, 7, 1, 1, tunicD); f.rect(10, 7, 1, 1, tunicD); // плечи
  f.rect(6, 9, 4, 1, C.belt);
  // руки: в шаге раскачиваются
  const aUp = step === 1, aDn = step === 2;
  f.set(4, 8, skin); f.set(11, 8, skin);
  if (aUp) { f.set(4, 7, skin); f.set(11, 9, skin); }
  if (aDn) { f.set(4, 9, skin); f.set(11, 7, skin); }
  if (opts.apron) f.rect(6, 8, 4, 1, opts.apron);
  // --- ноги ---
  if (step === 0) {
    f.rect(6, 10, 2, 2, C.pants); f.rect(8, 10, 2, 2, C.pants);
    f.rect(6, 12, 2, 1, C.boot);  f.rect(8, 12, 2, 1, C.boot);
  } else if (step === 1) {
    f.rect(6, 10, 2, 2, C.pants); f.rect(8, 10, 2, 1, C.pants);
    f.rect(6, 12, 2, 1, C.boot);  f.set(8, 11, C.boot);
  } else {
    f.rect(6, 10, 2, 1, C.pants); f.rect(8, 10, 2, 2, C.pants);
    f.set(6, 11, C.boot);         f.rect(8, 12, 2, 1, C.boot);
  }
  // меч за спиной у героя
  if (opts.sword) { f.set(12, 4, C.rockL); f.rect(12, 5, 1, 4, C.rock); f.set(12, 9, C.woodD); }
  return f;
}

// лист героя: 3 кадра x 4 ряда (down,left,right,up) = 48x64
function genPlayer() {
  const sheet = new Img(48, 64);
  const opts = { hair: C.hairD, tunic: C.tunic, tunicD: C.tunicD, sword: true };
  for (let row = 0; row < 4; row++)
    for (let col = 0; col < 3; col++)
      sheet.blit(drawChar(opts, row, col), col * 16, row * 16);
  sheet.save('player.png');
}
function genNpc(name, opts) {
  const f = drawChar(opts, 0, 0);
  f.save(name + '.png');
}

// ---------- Слайм 16x16 x2 кадра ----------
function genSlime() {
  const sheet = new Img(32, 16);
  const blob = (ox, base, top, w) => {
    const f = new Img(16, 16);
    for (let y = top; y <= base; y++) {
      const t = (y - top) / Math.max(1, base - top);
      const hw = Math.round((w / 2) * (0.45 + 0.55 * t));
      f.rect(8 - hw, y, hw * 2, 1, C.slimeG);
      f.set(8 - hw, y, C.slimeD); f.set(8 + hw - 1, y, C.slimeD);
    }
    f.rect(5, top + 1, 2, 1, C.slimeL); // блик
    const ey = top + Math.round((base - top) * 0.45);
    f.set(6, ey, [255, 255, 255]); f.set(10, ey, [255, 255, 255]);
    f.set(6, ey + 1, C.eye); f.set(10, ey + 1, C.eye);
    sheet.blit(f, ox, 0);
  };
  blob(0, 13, 6, 12);  // обычный
  blob(16, 14, 9, 14); // приплюснутый (прыжок)
  sheet.save('slime.png');
}

// ---------- Тайлы 16x16, лист 256x16 (16 тайлов) ----------
const TILE = { GRASS: 0, GRASS2: 1, FLOWER: 2, PATH: 3, WATER: 4, TREE: 5, WALL: 6, ROOF: 7, DOOR: 8, FENCE: 9, CHEST: 10, HERB: 11, ROCK: 12, SIGN: 13, CHEST_OPEN: 14 };

function grassBase(t, ox = 0) {
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const n = noise(ox + x, y, 3, 5);
    t.set(x + ox, y, n < 3 ? C.grassL : n < 5 ? C.grassD : C.grass);
  }
}
function genTiles() {
  const s = new Img(256, 16);
  const put = (i) => { const t = new Img(16, 16); return t; };
  // 0 grass
  let t = put(0); grassBase(t); s.blit(t, 0 * 16);
  // 1 grass2: пышные кустики
  t = put(1); grassBase(t);
  for (const [x, y] of [[3, 4], [11, 2], [7, 9], [13, 11], [2, 12]]) {
    t.set(x, y, C.grassL); t.set(x + 1, y, C.grassL); t.set(x, y + 1, C.grassD);
  }
  s.blit(t, 1 * 16);
  // 2 flower
  t = put(2); grassBase(t);
  t.set(4, 4, C.flowerR); t.set(4, 5, C.grassD);
  t.set(11, 9, C.flowerY); t.set(11, 10, C.grassD);
  t.set(12, 3, C.flowerW);
  s.blit(t, 2 * 16);
  // 3 path
  t = put(3);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const n = noise(x, y, 2, 3);
    t.set(x, y, n < 3 ? C.dirtL : n < 6 ? C.dirtD : C.dirt);
  }
  s.blit(t, 3 * 16);
  // 4 water
  t = put(4);
  t.rect(0, 0, 16, 16, C.water);
  for (let x = 0; x < 16; x++) { if ((x + 2) % 8 < 2) t.set(x, 0, C.waterL); }
  for (let x = 0; x < 16; x++) { if ((x + 5) % 8 < 2) { t.set(x, 6, C.waterL); t.set(x, 12, C.waterD); } }
  t.rect(0, 15, 16, 1, C.waterD);
  s.blit(t, 4 * 16);
  // 5 tree
  t = put(5); grassBase(t);
  t.rect(7, 10, 2, 5, C.trunk); t.set(7, 14, C.trunkD); t.set(8, 10, C.trunkD);
  for (let y = 0; y < 10; y++) {
    const hw = [3, 5, 6, 6, 6, 6, 6, 5, 3, 1][y];
    for (let x = 8 - hw; x < 8 + hw; x++) {
      const n = noise(x, y, 5, 9);
      t.set(x, y, n < 3 ? C.leafL : n < 17 ? C.leaf : C.leafD);
    }
  }
  s.blit(t, 5 * 16);
  // 6 wall (брус)
  t = put(6);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    t.set(x, y, y % 4 === 0 ? C.wallD : C.wall);
    if (x % 8 === 0 && y % 4 !== 0) t.set(x, y, C.wallD);
  }
  s.blit(t, 6 * 16);
  // 7 roof (черепица)
  t = put(7);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    t.set(x, y, y % 4 === 3 ? C.roofD : (x + (Math.floor(y / 4) % 2) * 4) % 8 === 0 ? C.roofD : C.roof);
  }
  s.blit(t, 7 * 16);
  // 8 door (в стене)
  t = put(8);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) t.set(x, y, y % 4 === 0 ? C.wallD : C.wall);
  t.rect(5, 3, 6, 13, C.wood); t.frame(5, 3, 6, 13, C.woodD);
  t.rect(6, 4, 4, 11, C.trunk); t.set(9, 10, C.gold);
  s.blit(t, 8 * 16);
  // 9 fence
  t = put(9); grassBase(t);
  t.rect(0, 6, 16, 2, C.wood); t.rect(0, 11, 16, 2, C.wood);
  t.rect(2, 4, 2, 11, C.woodD); t.rect(12, 4, 2, 11, C.woodD);
  t.set(3, 4, C.rockL); t.set(13, 4, C.rockL);
  s.blit(t, 9 * 16);
  // 10 chest closed
  t = put(10); grassBase(t);
  t.rect(3, 6, 10, 8, C.wood); t.frame(3, 6, 10, 8, C.woodD);
  t.rect(3, 6, 10, 3, C.trunk); t.rect(7, 6, 2, 8, C.gold); t.set(7, 10, C.woodD); t.set(8, 10, C.woodD);
  s.blit(t, 10 * 16);
  // 11 herb plant
  t = put(11); grassBase(t);
  t.rect(7, 8, 1, 5, C.herbG);
  t.rect(4, 6, 2, 1, C.herbG); t.rect(10, 6, 2, 1, C.herbG);
  t.rect(5, 4, 2, 2, C.herbG); t.rect(9, 4, 2, 2, C.herbG);
  t.set(6, 3, C.herbR); t.set(9, 3, C.herbR); t.set(7, 6, C.herbR);
  s.blit(t, 11 * 16);
  // 12 rock
  t = put(12); grassBase(t);
  t.rect(4, 7, 8, 7, C.rock); t.rect(6, 5, 4, 2, C.rock);
  t.set(5, 7, C.rockD); t.set(6, 6, C.rockD); t.frame(4, 7, 8, 7, null);
  t.set(5, 8, C.rockL); t.set(6, 8, C.rockL); t.set(11, 12, C.rockD);
  s.blit(t, 12 * 16);
  // 13 sign
  t = put(13); grassBase(t);
  t.rect(7, 8, 2, 7, C.trunk);
  t.rect(3, 3, 10, 5, C.wood); t.frame(3, 3, 10, 5, C.woodD);
  t.rect(5, 4, 6, 1, C.wall); t.rect(5, 6, 4, 1, C.wall);
  s.blit(t, 13 * 16);
  // 14 chest open
  t = put(14); grassBase(t);
  t.rect(3, 3, 10, 3, C.trunk); t.frame(3, 3, 10, 3, C.woodD);
  t.rect(3, 7, 10, 7, C.wood); t.frame(3, 7, 10, 7, C.woodD);
  t.rect(5, 8, 6, 3, [40, 25, 18]);
  t.set(6, 9, C.gold); t.set(8, 10, C.gold); t.set(9, 9, C.gold);
  s.blit(t, 14 * 16);
  // 15 тёмная трава (окантовка)
  t = put(15);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const n = noise(x, y, 11, 13);
    t.set(x, y, n < 4 ? C.grass : n < 7 ? C.grassD : [52, 110, 44]);
  }
  s.blit(t, 15 * 16);
  s.save('tiles.png');
}

// ---------- Сердце HP 7x6 ----------
function genHeart() {
  const t = new Img(7, 6);
  t.rect(1, 0, 2, 1, C.heart); t.rect(4, 0, 2, 1, C.heart);
  t.rect(0, 1, 7, 2, C.heart);
  t.rect(1, 3, 5, 1, C.heart); t.rect(2, 4, 3, 1, C.heart); t.rect(3, 5, 1, 1, C.heart);
  t.set(1, 1, C.heartD); t.set(0, 2, C.heartD); t.set(1, 3, C.heartD);
  t.set(1, 1, [250, 140, 150]); t.set(2, 1, [250, 140, 150]);
  t.save('heart.png');
}

// ---------- Портреты 40x40 x3 ----------
function bigHead(img, ox, opts) {
  const hair = opts.hair, skin = C.skin;
  img.rect(ox + 6, 4, 28, 20, hair);            // волосы фон
  img.rect(ox + 9, 8, 22, 22, skin);            // лицо
  img.rect(ox + 6, 4, 28, 6, hair);             // чёлка
  img.rect(ox + 6, 8, 4, 14, hair);             // виски
  img.rect(ox + 30, 8, 4, 14, hair);
  img.rect(ox + 9, 30, 22, 3, opts.collar || C.tunicD); // плечи/воротник
  img.rect(ox + 13, 18, 4, 5, [255, 255, 255]); // белки
  img.rect(ox + 23, 18, 4, 5, [255, 255, 255]);
  img.rect(ox + 14, 20, 2, 3, C.eye); img.rect(ox + 24, 20, 2, 3, C.eye);
  img.rect(ox + 12, 16, 5, 1, hair); img.rect(ox + 23, 16, 5, 1, hair); // брови
  img.rect(ox + 20, 24, 2, 4, C.skinD);         // нос
  if (opts.beard) img.rect(ox + 12, 27, 16, 5, hair), img.rect(ox + 17, 27, 6, 2, C.mouth);
  else img.rect(ox + 17, 27, 6, 2, C.mouth);
  if (opts.hat) img.rect(ox + 4, 2, 32, 4, opts.hat), img.rect(ox + 10, 0, 20, 3, opts.hat);
}
function genPortraits() {
  const s = new Img(120, 40);
  bigHead(s, 0, { hair: C.hairD });                                        // герой
  bigHead(s, 40, { hair: C.gray, beard: true, collar: C.robeD });          // старейшина
  bigHead(s, 80, { hair: C.hairP, hat: C.apronD, collar: C.apron });       // торговец
  s.save('portraits.png');
}

// ---------- запуск ----------
genPlayer();
genNpc('npc_elder', { hair: C.gray, tunic: C.robe, tunicD: C.robeD, beard: true });
genNpc('npc_merchant', { hair: C.hairP, tunic: C.apron, tunicD: C.apronD, apron: C.apron });
genNpc('npc_farmer', { hair: C.hairD, tunic: C.roof, tunicD: C.roofD });
genSlime();
genTiles();
genHeart();
genPortraits();
console.log('DONE');
