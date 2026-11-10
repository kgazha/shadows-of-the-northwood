// ============================================================================
// gen_assets3.js — ФИНАЛЬНЫЙ АРТ-ПАСС v3 «тёмное фэнтези» — «Тени Северного Леса»
// Перезаписывает ВСЕ PNG в pixel-rpg/assets/ в той же раскладке/размерах,
// что gen_assets.js + gen_assets2.js (индексы тайлов, слоты атласов, ряды/колонки
// листов персонажей — 1-в-1). Меняется ТОЛЬКО стиль:
//  - без жирных чёрных обводок и «зефирных» градиентов — объём ступенчатыми
//    тонами материала (5-7 оттенков на материал);
//  - единый свет: верх-лево тёплый, тени холодные (низ-право);
//  - приглушённая «дорогая» палитра: оливково-зелёный лес, сланцево-серый
//    камень с ржавыми прожилками, вестерн-дуб, тёмно-бордовая кровь,
//    ядовито-бирюзовая/фиолетовая магия;
//  - deterministic-шум/дизеринг на больших плоскостях; НИКАКОГО Math.random.
// PNG-энкодер и Img скопированы из gen_assets2.js.
// ============================================================================
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
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return null;
    const i = (y * this.w + x) * 4;
    if (this.d[i + 3] === 0) return null;
    return [this.d[i], this.d[i + 1], this.d[i + 2], this.d[i + 3]];
  }
  save(name) { savePng(name, this.w, this.h, this.d); }
}

// ---------- Детерминированный шум: ((x*a + y*b + c) % 9973)*13+7 % 65521 % n ----------
function nz(x, y, a, b, c, n) {
  let v = (x * a + y * b + c) % 9973;
  v = (v * 13 + 7) % 65521;
  return v % n;
}
// смесь цветов и затемнение (цветная линия = shadeC(c, ~.38), не чёрная)
function mixC(a, b, t) {
  return [Math.round(a[0] + (b[0] - a[0]) * t), Math.round(a[1] + (b[1] - a[1]) * t), Math.round(a[2] + (b[2] - a[2]) * t)];
}
function shadeC(c, k) { return [Math.round(c[0] * (1 - k)), Math.round(c[1] * (1 - k)), Math.round(c[2] * (1 - k))]; }
const WARM = [236, 214, 178];  // тон тёплого верхне-левого света
const COOL = [38, 42, 62];     // тон холодных нижне-правых теней
function lite(c, t = .4) { return mixC(c, WARM, t); }   // тёплый свет
function cool(c, t = .4) { return mixC(c, COOL, t); }   // холодная тень

// ===========================================================================
// ПАЛИТРА v3 «тёмное фэнтези» — приглушённая, 5-7 оттенков на материал
// ===========================================================================
const C = {
  // --- кожа/лицо (приглушённая, кровянистая) ---
  skin: [198, 150, 116], skinL: [226, 182, 146], skinD: [160, 116, 90], skinDD: [124, 88, 74], skinSh: [110, 82, 78],
  eye: [36, 30, 42], eyeW: [206, 210, 222], mouth: [122, 62, 62],
  // --- волосы ---
  hairP: [96, 64, 40], hairPD: [66, 44, 30], hairD: [52, 36, 28],
  gray: [176, 176, 186], grayD: [128, 128, 142], grayL: [210, 212, 220], wWhite: [220, 222, 228],
  // --- ткани героя: пыльно-синий дублет, пыльно-фиолетовая мантия ---
  tunic: [64, 84, 128], tunicL: [94, 116, 158], tunicD: [44, 60, 96], tunicDD: [30, 42, 70],
  robe: [104, 84, 130], robeL: [136, 114, 162], robeD: [76, 58, 100], robeDD: [52, 40, 72],
  // --- кожа/пояса/штаны/сапоги (тёмный низ для «веса») ---
  leather: [92, 64, 42], leatherD: [64, 44, 30], leatherL: [120, 88, 60],
  pants: [62, 62, 82], pantsL: [84, 84, 108], pantsD: [44, 44, 62],
  boot: [46, 36, 34], bootD: [28, 22, 24], bootL: [70, 56, 50],
  apron: [176, 158, 120], apronD: [128, 112, 82],
  // --- металлы (матовая сталь, кованое железо, тусклая бронза, ржавчина) ---
  steel: [148, 156, 172], steelL: [200, 210, 228], steelD: [100, 108, 126], steelDD: [64, 70, 88],
  iron: [92, 96, 108], ironL: [134, 140, 154], ironD: [62, 66, 78], ironDD: [40, 44, 54],
  gold: [176, 142, 70], goldL: [222, 188, 110], goldXL: [244, 220, 150], goldD: [124, 96, 44], goldDD: [82, 62, 30],
  rust: [148, 92, 54], rustL: [190, 126, 74], rustD: [104, 62, 38],
  // --- кровь/акценты: тёмный бордо ---
  blood: [122, 42, 46], bloodL: [162, 66, 62], bloodD: [82, 26, 32],
  // --- деревенская зелень: глубокая оливково-зелёная с холодным подтоном ---
  grass: [64, 88, 58], grassL: [86, 112, 72], grassXL: [112, 136, 90],
  grassD: [46, 68, 46], grassDD: [34, 52, 38], grassDK: [52, 74, 50], grassSh: [26, 40, 32],
  moss: [70, 96, 62], mossL: [98, 124, 80], mossD: [48, 70, 46],
  leaf: [44, 72, 46], leafL: [66, 96, 60], leafXL: [92, 120, 72], leafD: [28, 50, 36], leafDD: [18, 34, 26],
  flowerR: [168, 74, 74], flowerRL: [204, 116, 108], flowerY: [198, 164, 84], flowerYL: [228, 198, 122], flowerW: [206, 208, 200],
  // --- тропа: приглушённо-серая земля ---
  dirt: [104, 92, 74], dirtL: [128, 114, 92], dirtXL: [152, 138, 112], dirtD: [80, 70, 56], dirtDD: [60, 52, 42], dirtCr: [48, 42, 34],
  // --- вода: тёмный тил ---
  water: [38, 66, 86], waterL: [62, 98, 120], waterXL: [112, 150, 168], waterD: [28, 50, 68], waterDD: [20, 38, 54],
  // --- дерево: вестерн-дуб с потёмками ---
  trunk: [84, 62, 42], trunkD: [60, 44, 30], trunkDD: [40, 30, 22], trunkL: [110, 82, 56], trunkXL: [138, 106, 72],
  wood: [96, 70, 46], woodD: [68, 48, 32], woodL: [124, 94, 62], woodHL: [152, 120, 82], woodIn: [26, 19, 14],
  woodRing: [150, 118, 80], woodRingD: [112, 86, 56], woodRingL: [180, 148, 104],
  // --- стены дома: выветренный холодный камень, тёплая кромка ---
  wall: [136, 128, 116], wallHL: [172, 164, 148], wallL: [154, 146, 130], wallD: [104, 96, 86], wallM: [68, 62, 58],
  // --- крыша: тёмный сланец с рыжим ---
  roof: [102, 62, 54], roofL: [132, 86, 70], roofD: [74, 44, 40], roofDD: [54, 32, 30],
  // --- валуны: сланцево-серый с ржавыми прожилками ---
  rock: [110, 112, 124], rockL: [142, 144, 156], rockXL: [172, 174, 186], rockD: [80, 82, 96], rockDD: [58, 60, 72],
  // --- трава-зелье/ягоды ---
  herbG: [72, 104, 64], herbGL: [100, 134, 84], herbGD: [50, 76, 48], berry: [142, 48, 52], berryL: [190, 90, 84],
  // --- декор ---
  maple: [168, 96, 48], mapleD: [128, 68, 36], mapleDD: [92, 48, 28],
  reed: [84, 110, 68], reedD: [58, 84, 52], reedTip: [124, 144, 92], spikeB: [96, 72, 46],
  spikeP: [124, 84, 150], spikePL: [164, 126, 192], spikePD: [88, 56, 112],
  decoBerry: [142, 48, 52], decoBerryL: [190, 90, 84],
  mushCap: [148, 62, 54], mushCapD: [104, 40, 40], mushStem: [196, 188, 170], mushStemD: [156, 148, 132], mushDot: [222, 214, 196],
  cloud: [104, 110, 128], cloudD: [74, 80, 98], cloudL: [142, 148, 166],
  quiverC: [104, 72, 44], quiverD: [74, 50, 32], featherW: [206, 200, 184], featherD: [150, 144, 130],
  arrowShaft: [118, 90, 58],
  // --- слайм: ядовито-оливковый, не «зефирный» ---
  slimeG: [72, 108, 66], slimeL: [100, 140, 88], slimeXL: [164, 196, 142], slimeD: [46, 76, 50], slimeDD: [30, 52, 40],
  // --- магия: ядовитый бирюзовый + отравленный фиолетовый ---
  tox: [72, 196, 184], toxL: [148, 238, 224], toxD: [38, 126, 120], healT: [150, 206, 188],
  glow: [166, 120, 208], glowL: [214, 182, 244], glowD: [112, 74, 152], glowTint: [84, 72, 104],
  ice: [120, 176, 208], iceL: [190, 224, 240], iceXL: [232, 246, 252], iceD: [74, 128, 166], iceDD: [48, 88, 124],
  // --- огонь: угольки, не мультяшные ---
  fire: [230, 138, 60], fireL: [255, 204, 120], fireXL: [255, 236, 180], fireD: [180, 80, 40], fireDD: [116, 46, 30],
  // --- подземелье: холодный сланец ---
  floor: [56, 56, 68], floorD: [44, 44, 56], floorS: [34, 34, 44], floorL: [72, 72, 86], floorXL: [90, 90, 104], floorDD: [24, 24, 34],
  brick: [48, 48, 60], brickL: [62, 62, 76], brickTop: [86, 86, 102], mortar: [26, 26, 36],
  stone: [72, 74, 88], stoneL: [96, 98, 112], stoneXL: [126, 128, 142], stoneD: [50, 52, 66], stoneDD: [36, 38, 50],
  rg: [88, 90, 104], rgL: [122, 124, 138], rgD: [60, 62, 76],
  step: [66, 68, 82], stepL: [106, 108, 124], stepD: [42, 44, 56],
  openDark: [14, 14, 20],
  bone: [206, 200, 182], boneD: [156, 150, 136], boneEye: [34, 32, 42], boneDim: [96, 98, 108],
  mCap: [132, 96, 158], mCapD: [88, 60, 112], mCapL: [174, 142, 198], mStem: [196, 192, 176], mStemD: [156, 150, 136], spore: [208, 190, 226],
  cMoss: [54, 82, 62], cMossL: [82, 116, 78], cMossD: [36, 58, 46],
  bandM: [86, 88, 102], bandML: [122, 126, 142], bandMD: [58, 60, 74],
  leverStick: [96, 70, 44], leverStickD: [68, 48, 32],
  voidB: [9, 9, 12], voidP: [22, 16, 30], voidP2: [32, 22, 42],
  // --- босс: осквернённый гром — десатурированная оливковая кожа, язвы фиолетовые ---
  brute: [74, 92, 64], bruteL: [102, 120, 84], bruteXL: [134, 152, 110], bruteD: [52, 68, 48], bruteDD: [34, 46, 32],
  bruteSpot: [150, 104, 188], bruteBrow: [28, 38, 26], bruteMouth: [34, 28, 34], tooth: [216, 212, 196], monOut: [24, 34, 26],
  // --- отшельник ---
  hermSkin: [206, 178, 150], hermSkinD: [168, 140, 116],
  hermRobe: [84, 76, 66], hermRobeD: [58, 52, 46], hermRobeL: [112, 102, 88],
  // --- иконки/курсоры ---
  iconBg: [36, 38, 50], iconDark: [16, 16, 24], iconEdge: [70, 74, 94],
  curW: [238, 240, 246], curY: [226, 196, 90], curYL: [255, 232, 150], curR: [186, 58, 54], curRL: [232, 110, 96],
  // --- сердце HP: алый, классический (иконка проекта) ---
  heart: [196, 48, 58], heartL: [234, 118, 122], heartHL: [250, 168, 168], heartD: [140, 28, 42], heartDD: [96, 16, 30],
  keyDark: [42, 32, 20],
};

// ---------- ручной AA + «color line» (как в v2, кромка = своё затемнение, не чёрная) ----------
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

// заполнение тоновой палитрой по шуму: tones[] + кумулятивные веса cum[]
function toneFill(t, tones, cum, seed, a = 7, b = 11) {
  const N = cum[cum.length - 1];
  for (let y = 0; y < t.h; y++) for (let x = 0; x < t.w; x++) {
    const v = nz(x, y, a, b, seed, N);
    let i = 0; while (v >= cum[i]) i++;
    t.set(x, y, tones[i]);
  }
}

// ===========================================================================
// tiles.png — 256x16, 16 клеток. Индексы НЕ МЕНЯТЬ:
// 0 трава, 1 трава кустистая, 2 трава с цветами, 3 тропа, 4 вода, 5 дерево,
// 6 стена дома, 7 крыша, 8 дверь, 9 изгородь, 10 сундук, 11 зелье-трава,
// 12 валун, 13 указатель, 14 сундук открытый, 15 тёмная трава (окантовка)
// ===========================================================================
function grassBase(t, seed, T) {
  T = T || { dd: C.grassDD, d: C.grassD, m: C.grass, l: C.grassL, sp: C.grassXL };
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const n = nz(x, y + seed * 7, 3, 5, 1, 100);
    let c = n < 8 ? T.dd : n < 32 ? T.d : n < 72 ? T.m : n < 94 ? T.l : T.sp;
    if (nz(x, y + seed * 7, 11, 17, 5, 61) === 0) c = T.sp;             // светлые крапинки
    if (nz(x + seed, y, 21, 9, 3, 53) === 0) c = T.dd;                  // прогалины
    t.set(x, y, c);
  }
}
function blades(t, pts, d, l) { for (const [x, y] of pts) { t.set(x, y, d); t.set(x, y - 1, l); } }
function tufts(t, pts, d, m, l) {
  for (const [x, y] of pts) { t.set(x, y + 1, d); t.set(x, y, m); t.set(x + 1, y, l); t.set(x + 1, y + 1, d); }
}
function genTiles() {
  const s = new Img(256, 16);
  const put = () => new Img(16, 16);
  let t;
  // 0 — трава: оливковая глубина, травины
  t = put(); grassBase(t, 0);
  blades(t, [[3, 9], [11, 5], [14, 12], [6, 13], [2, 3], [9, 2]], C.grassDD, C.grassL);
  tufts(t, [[12, 8], [5, 5]], C.grassDD, C.grassD, C.grassL);
  s.blit(t, 0);
  // 1 — трава кустистее
  t = put(); grassBase(t, 3);
  tufts(t, [[3, 4], [11, 2], [7, 9], [13, 11], [2, 12]], C.grassDD, C.grassD, C.grassXL);
  blades(t, [[5, 14], [9, 6], [14, 7]], C.grassDD, C.grassL);
  s.blit(t, 16);
  // 2 — трава с приглушёнными цветами (тёмная серединка, стебли в тени)
  t = put(); grassBase(t, 1);
  const flower = (x, y, petal, petalL) => {
    t.set(x, y, mixC(petal, C.grassDD, .45));            // сердцевина тёмная
    t.set(x, y - 1, petalL); t.set(x - 1, y, petal); t.set(x + 1, y, mixC(petal, C.leafDD, .3)); t.set(x, y + 1, petal);
    t.set(x, y + 2, C.grassDD); t.set(x, y + 3, C.grassD);
  };
  flower(4, 4, C.flowerR, C.flowerRL); flower(11, 9, C.flowerY, C.flowerYL);
  t.set(12, 3, C.flowerW); t.set(13, 3, mixC(C.flowerW, C.grassL, .4)); t.set(12, 4, mixC(C.flowerW, C.grassDD, .35)); t.set(12, 5, C.grassD);
  s.blit(t, 32);
  // 3 — тропа: укатанная земля, камни-сланец, трещины
  t = put();
  toneFill(t, [C.dirtDD, C.dirtD, C.dirt, C.dirtL], [5, 24, 64, 100], 2, 2, 3);
  for (const [x, y] of [[3, 4], [10, 9], [13, 3], [6, 12]]) {
    t.set(x, y, C.rockL); t.set(x + 1, y, C.rock); t.set(x, y + 1, C.rockD);
    t.set(x + 1, y + 1, mixC(C.dirt, C.rockDD, .55));    // холодная тень под камнем
  }
  for (const [x, y] of [[7, 2], [8, 3], [8, 4], [11, 12], [12, 13], [12, 14]]) t.set(x, y, C.dirtCr);
  for (const [x, y] of [[4, 6], [5, 10], [11, 5]]) t.set(x, y, mixC(C.dirt, C.rustD, .5));   // ржавые вкрапления
  s.blit(t, 48);
  // 4 — вода (статичный кадр; цикл в anim_tiles.png)
  const m8 = (v) => ((v % 8) + 8) % 8;
  const waterFrame = (tt, p) => {
    const wave = (row, off, col, len) => { for (let x = 0; x < 16; x++) if (m8(x + off) < len) tt.set(x, row, col); };
    tt.rect(0, 0, 16, 16, C.water);
    toneFill(tt, [C.waterD, C.water, C.waterL], [18, 76, 100], 3 + p * 5, 5, 3);
    tt.rect(0, 0, 16, 1, mixC(C.water, C.waterL, .45));
    wave(1, 5 - p * 2, C.waterL, 2); wave(4, 2 + p * 2, C.waterL, 2);
    wave(8, 1 - p * 2, C.waterL, 2); wave(12, 6 + p * 2, C.waterL, 2);
    wave(2, -p * 2, C.waterD, 3); wave(6, 4 + p * 2, C.waterD, 3); wave(10, 2 - p * 2, C.waterD, 3);
    const sx = [13, 15, 2, 6][p], sy = [3, 9, 5, 11][p];
    tt.set(sx, sy, C.waterXL); tt.set(m8(sx + 1), sy, mixC(C.water, C.waterXL, .5));          // бегущий блик
    tt.rect(0, 15, 16, 1, C.waterDD);
  };
  t = put(); waterFrame(t, 0); s.blit(t, 64);
  // 5 — дерево: кряжистое, дупло, сухие сучья. Фикс «невидимых стен»: крона
  // обведена тёмным контуром leafDD и несёт светлую макушку — на тёмном
  // лесном полу (тайл 15) блокирующее дерево обязано читаться СИЛУЭТОМ.
  t = put(); grassBase(t, 5);
  for (const [x, y] of [[12, 1], [13, 0], [4, 1], [3, 0]]) t.set(x, y, C.trunkDD);            // сухие сучья
  const HW = [3, 5, 6, 6, 6, 6, 6, 5, 3, 1];
  for (let y = 0; y < 10; y++) {
    const hw = HW[y];
    for (let x = 8 - hw; x < 8 + hw; x++) {
      const n = nz(x, y, 5, 9, 1, 29);
      let c = n < 6 ? C.leafD : n > 24 ? C.leafL : C.leaf;
      if (y <= 1 && n > 10) c = C.leafXL;                             // светлая макушка
      else if (x < 7 && y < 4 && n > 14) c = C.leafL;                 // свет верх-лево
      if (x > 9 && y > 5) c = mixC(c, C.leafDD, .55);                 // тень низ-право
      if (y >= 2 && (x === 8 - hw || x === 8 + hw - 1 || y === 9)) c = C.leafDD;  // контур
      t.set(x, y, c);
    }
  }
  t.rect(7, 10, 3, 5, C.trunk); t.set(7, 10, C.trunkL); t.set(7, 11, C.trunkL);
  t.set(9, 10, C.trunkD); t.set(9, 11, C.trunkD); t.set(9, 13, C.trunkDD);                    // тёмная кора справа
  t.rect(8, 11, 1, 2, C.woodIn); t.set(8, 13, mixC(C.woodIn, C.trunkDD, .5));                 // дупло
  t.set(6, 14, C.trunkD); t.set(10, 14, C.trunkDD);                                           // корни
  for (const [x, y] of [[6, 14], [9, 14], [5, 15], [6, 15], [10, 15], [9, 15], [7, 15], [8, 15]]) t.set(x, y, C.grassSh);
  s.blit(t, 80);
  // 6 — стена дома: тёсаный холодный камень, ржавая прожилка
  const wallStone = (tt) => {
    for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
      const band = Math.floor(y / 4), off = (band % 2) * 4;
      const mRow = y % 4 === 3, mCol = (x + off) % 8 === 7 && !mRow;
      let c;
      if (mRow || mCol) c = C.wallM;
      else if (y % 4 === 0) c = mixC(C.wallHL, WARM, .15);
      else c = nz(x, y, 3, 7, band + 1, 13) < 3 ? mixC(C.wall, C.wallHL, .5)
           : nz(x, y, 5, 3, band, 11) < 2 ? C.wallD : C.wall;
      tt.set(x, y, c);
    }
    for (const [x, y] of [[10, 2], [11, 3], [11, 4], [12, 5]]) tt.set(x, y, mixC(C.wall, C.rustD, .5)); // ржавая прожилка
    tt.set(10, 3, C.rustD);
  };
  t = put(); wallStone(t); s.blit(t, 96);
  // 7 — крыша: тёмный сланец, ряд с тенью, лишайник
  t = put();
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const band = Math.floor(y / 4), inRow = y % 4, off = (band % 2) * 4;
    const joint = (x + off) % 8 === 7;
    let c;
    if (inRow === 3) c = C.roofDD;
    else if (inRow === 0) c = mixC(C.roofL, WARM, .18);
    else if (joint) c = C.roofD;
    else if ((x + off) % 8 === 6) c = mixC(C.roof, C.roofD, .55);
    else c = nz(x, y, 3, 9, 2, 23) === 0 ? mixC(C.roof, C.roofL, .35) : C.roof;
    if (nz(x, y, 13, 7, 6, 97) === 0 && inRow !== 0) c = mixC(c, C.mossD, .5);                 // лишайник
    t.set(x, y, c);
  }
  s.blit(t, 112);
  // 8 — дверь: арочная дубовая на кладке, кованые петли, ring-handle
  t = put(); wallStone(t);
  for (let x = 5; x <= 10; x++) t.set(x, 2, mixC(C.wall, C.wallM, .6));                        // притолока в тени
  t.rect(6, 3, 4, 1, C.wood); t.rect(5, 4, 6, 12, C.wood);
  t.rect(5, 4, 1, 12, C.woodD); t.rect(10, 4, 1, 12, cool(C.wood, .5)); t.rect(5, 15, 6, 1, C.woodD);
  t.set(6, 3, C.woodD); t.set(9, 3, C.woodD);
  t.rect(7, 4, 1, 11, C.woodD); t.rect(9, 5, 1, 4, C.woodD); t.set(9, 9, C.woodD);             // доски/стык
  t.set(6, 4, C.woodHL); t.set(7, 3, C.woodHL); t.set(6, 5, mixC(C.wood, C.woodHL, .5));       // свет левый край
  t.rect(5, 6, 6, 1, C.ironD); t.set(5, 6, C.iron); t.set(6, 6, C.ironL);                      // верхняя петля
  t.rect(5, 11, 6, 1, C.ironD); t.set(5, 11, C.iron); t.set(6, 11, C.ironL);                   // нижняя петля
  t.set(9, 8, C.ironL); t.rect(8, 9, 1, 1, C.iron); t.set(9, 9, C.iron); t.set(9, 10, C.ironD); // кольцевая ручка
  t.set(6, 3, mixC(C.wood, C.wall, .35));
  s.blit(t, 128);
  // 9 — изгородь: потемневшее дерево, кованые гвозди
  t = put(); grassBase(t, 9);
  t.rect(0, 6, 16, 1, mixC(C.wood, WARM, .12)); t.rect(0, 7, 16, 1, C.woodD);
  t.rect(0, 11, 16, 1, C.wood); t.rect(0, 12, 16, 1, cool(C.wood, .45));
  for (const px of [2, 12]) {
    t.rect(px, 4, 2, 11, C.wood); t.rect(px + 1, 4, 1, 11, C.woodD);
    t.set(px, 4, C.woodHL); t.set(px, 14, C.grassSh);
    t.set(px, 6, C.ironL); t.set(px, 11, C.ironL);                                             // гвозди
  }
  s.blit(t, 144);
  // 10 — сундук: дуб с коваными углами и замком, тень на земле
  t = put(); grassBase(t, 2);
  t.rect(3, 14, 10, 1, C.grassSh); t.set(2, 14, C.grassSh); t.set(13, 14, C.grassSh);
  t.rect(4, 5, 8, 1, C.trunkL); t.rect(3, 6, 10, 2, C.trunk);                                  // крышка светлее сверху
  t.set(4, 5, C.trunkXL); t.set(3, 6, C.trunkL); t.set(12, 6, C.trunkD); t.set(11, 5, C.trunkD);
  t.rect(3, 8, 10, 6, C.wood);
  for (let y = 8; y < 14; y++) { t.set(3, y, C.woodL); t.set(12, y, cool(C.wood, .55)); }      // бока
  t.rect(3, 13, 10, 1, C.woodD);
  for (let y = 5; y < 14; y++) { t.set(4, y, C.bandM); t.set(11, y, C.bandMD); }               // кованые полосы
  t.set(4, 6, C.bandML); t.set(4, 10, C.bandML); t.set(11, 12, C.bandMD);
  t.rect(3, 8, 10, 1, C.bandM); t.set(3, 8, C.bandML); t.set(12, 8, C.bandMD);                 // пояс ковки
  t.rect(7, 9, 2, 3, C.iron); t.frame(7, 9, 2, 3, C.ironDD); t.set(7, 9, C.ironL);             // замковая пластина
  t.set(7, 10, C.woodIn); t.set(8, 10, C.woodIn);                                              // скважина
  s.blit(t, 160);
  // 11 — зелье-трава: тёмные листья, бордовые ягоды
  t = put(); grassBase(t, 7);
  t.rect(7, 8, 1, 5, C.herbGD); t.set(7, 8, C.herbG);
  t.rect(4, 6, 2, 1, C.herbG); t.set(4, 6, C.herbGL);
  t.rect(10, 6, 2, 1, C.herbGD); t.set(10, 6, C.herbG);
  t.rect(5, 4, 2, 2, C.herbG); t.set(5, 4, C.herbGL); t.set(6, 5, C.herbGD);
  t.rect(9, 4, 2, 2, C.herbGD); t.set(9, 4, C.herbG); t.set(10, 5, C.herbGD);
  t.set(6, 3, C.berry); t.set(9, 3, C.berry); t.set(7, 6, C.berry);
  t.set(6, 2, C.berryL); t.set(9, 2, C.berryL);
  s.blit(t, 176);
  // 12 — валун: сланец, ржавая прожилка, мох у основания. Тёмная обводка —
  // фикс «невидимых стен»: силуэт камня не должен сливаться с тёмной землёй.
  t = put(); grassBase(t, 4);
  t.rect(3, 14, 10, 1, C.grassSh); t.set(2, 14, C.grassSh); t.set(13, 14, C.grassSh);
  for (let y = 7; y <= 13; y++) { t.set(3, y, C.rockDD); t.set(12, y, C.rockDD); }            // боковая обводка
  t.rect(5, 4, 6, 1, C.rockDD); t.set(4, 5, C.rockDD); t.set(11, 5, C.rockDD);                // верхняя обводка
  t.set(5, 6, C.rockDD); t.set(10, 6, C.rockDD);                                               // грани шапки
  t.rect(4, 7, 8, 7, C.rock); t.rect(6, 5, 4, 2, C.rock);
  t.rect(6, 5, 3, 1, C.rockXL); t.set(5, 7, C.rockL); t.set(6, 6, C.rockL);                    // верх-лево свет
  for (let y = 7; y <= 13; y++) {
    t.set(4, y, mixC(C.rock, C.rockL, .4));
    t.set(11, y, cool(C.rock, .5));
    for (let x = 5; x <= 10; x++) if (nz(x, y, 9, 5, 4, 23) === 0) t.set(x, y, mixC(C.rock, C.rockD, .6));
  }
  for (const [x, y] of [[7, 6], [8, 7], [8, 8], [9, 9]]) t.set(x, y, C.rustD);                 // ржавая прожилка
  t.set(7, 7, C.rust);
  t.rect(4, 13, 8, 1, C.rockDD); t.rect(6, 6, 4, 1, mixC(C.rock, C.rockD, .45));
  t.set(4, 12, C.mossD); t.set(5, 13, C.moss); t.set(4, 11, C.mossD);                          // мох у земли
  t.set(3, 13, C.grassD); t.set(12, 13, C.grassD);
  s.blit(t, 192);
  // 13 — указатель: потемневшая доска с резьбой и кованым уголком, тень у земли
  t = put(); grassBase(t, 6);
  t.rect(5, 15, 6, 1, C.grassSh); t.rect(6, 14, 4, 1, C.grassSh);                             // тень под столбом
  t.rect(6, 8, 3, 6, C.trunk); t.set(8, 10, C.trunkD); t.set(8, 13, C.trunkDD); t.set(6, 9, C.trunkL);
  for (const [x, y] of [[6, 14], [9, 14]]) t.set(x, y, C.grassSh);
  t.rect(3, 3, 10, 5, C.wood); t.rect(3, 3, 10, 1, C.woodHL); t.rect(3, 7, 10, 1, C.woodD);
  t.set(3, 3, C.woodHL); t.set(12, 3, C.woodD); t.set(12, 7, C.woodD);
  t.rect(5, 4, 6, 1, C.woodD); t.set(5, 5, mixC(C.wood, C.woodHL, .5));                        // резьба-канавка
  t.rect(5, 6, 4, 1, C.woodD); t.set(5, 6, mixC(C.woodD, C.woodHL, .35));
  t.set(3, 7, C.bandMD); t.set(4, 7, C.bandM); t.set(12, 7, C.bandMD);                         // уголок
  s.blit(t, 208);
  // 14 — сундук открытый: тёмное нутро, тусклое золото
  t = put(); grassBase(t, 8);
  t.rect(3, 14, 10, 1, C.grassSh);
  t.rect(4, 3, 8, 1, C.trunkL); t.rect(3, 4, 10, 2, C.trunk); t.rect(3, 5, 10, 1, C.trunkD);
  t.set(4, 3, C.trunkXL); t.set(3, 4, C.trunkL); t.set(12, 4, C.trunkDD);
  t.rect(3, 7, 10, 7, C.wood);
  for (let y = 7; y < 14; y++) { t.set(3, y, C.woodL); t.set(12, y, cool(C.wood, .55)); }
  t.rect(3, 13, 10, 1, C.woodD);
  t.rect(5, 8, 6, 3, C.woodIn); t.rect(5, 8, 6, 1, mixC(C.woodIn, C.woodD, .4));               // нутро
  t.set(6, 9, C.gold); t.set(8, 10, C.gold); t.set(9, 9, C.goldD);
  t.set(6, 8, C.goldL); t.set(8, 9, C.goldL); t.set(7, 10, C.goldDD);
  for (let y = 7; y < 14; y++) { t.set(4, y, C.bandM); t.set(11, y, C.bandMD); }
  s.blit(t, 224);
  // 15 — тёмная трава (окантовка карты)
  t = put(); grassBase(t, 2, { dd: [26, 40, 30], d: C.grassDD, m: C.grassDK, l: C.grassD, sp: C.grass });
  blades(t, [[4, 8], [12, 5], [9, 13], [2, 12]], [26, 40, 30], C.grassD);
  s.blit(t, 240);
  s.save('tiles.png');
  waterFrameCache = waterFrame;
}
let waterFrameCache = null;

// ===========================================================================
// anim_tiles.png — 128x16: 0-3 вода (цикл), 4-5 факел, 6-7 светящийся мох
// ===========================================================================
function genAnimTiles() {
  const s = new Img(128, 16);
  for (let p = 0; p < 4; p++) {
    const t = new Img(16, 16);
    waterFrameCache(t, p);
    s.blit(t, p * 16);
  }
  const torchBase = (t) => {
    t.rect(7, 9, 2, 6, C.trunk);
    for (let y = 9; y <= 14; y++) t.set(8, y, C.trunkD);
    t.set(7, 13, C.trunkL);
    t.rect(6, 8, 4, 1, C.iron); t.set(6, 8, C.ironL); t.set(9, 8, C.ironDD);                   // кованая чаша
    t.rect(7, 9, 2, 1, C.ironD);                                                                // обмотка
  };
  // 4 — факел, кадр 1: высокое пламя
  let t = new Img(16, 16); torchBase(t);
  t.set(8, 1, C.fireDD);
  t.rect(7, 2, 2, 1, C.fireD); t.set(8, 2, C.fire);
  t.rect(7, 3, 3, 1, C.fireD); t.set(8, 3, C.fire);
  t.rect(6, 4, 5, 1, C.fireDD); t.rect(7, 4, 3, 1, C.fireD); t.rect(7, 4, 2, 1, C.fire); t.set(8, 4, C.fireL);
  t.rect(6, 5, 5, 1, C.fireDD); t.rect(7, 5, 3, 1, C.fireD); t.rect(7, 5, 2, 1, C.fire); t.set(8, 5, C.fireL);
  t.rect(7, 6, 3, 1, C.fire); t.set(8, 6, C.fireXL); t.set(7, 7, C.fireD); t.set(8, 7, C.fire);
  t.set(5, 2, C.fireD); t.set(11, 4, C.fireL);
  outlineAA(t);
  s.blit(t, 64);
  // 5 — факел, кадр 2: низкое раздвоенное пламя
  t = new Img(16, 16); torchBase(t);
  t.set(7, 2, C.fireD); t.set(7, 3, C.fire);
  t.set(9, 3, C.fireDD); t.set(9, 4, C.fireD);
  t.rect(6, 4, 2, 1, C.fireD); t.set(7, 4, C.fire);
  t.rect(6, 5, 5, 1, C.fireDD); t.rect(7, 5, 3, 1, C.fireD); t.set(8, 5, C.fire);
  t.rect(6, 6, 5, 1, C.fireD); t.rect(7, 6, 3, 1, C.fire); t.set(8, 6, C.fireL);
  t.set(7, 7, C.fire); t.set(8, 7, C.fireD);
  t.set(11, 2, C.fireD); t.set(4, 4, C.fireL);
  outlineAA(t);
  s.blit(t, 80);
  // 6..7 — светящийся мох с грибами: 6 тусклый, 7 яркий (пульс фиолетового свечения)
  for (let g = 0; g < 2; g++) {
    const lit = g === 1;
    t = new Img(16, 16);
    const tone = (x, y) => {
      const n = nz(x, y, 5, 9, g, 11);
      return n < 3 ? mixC(C.cMoss, C.leafDD, .4) : n < 6 ? C.cMoss : lit ? C.cMossL : mixC(C.cMoss, C.cMossL, .4);
    };
    for (const [x0, x1, y] of [[6, 9, 11], [4, 11, 12], [3, 12, 13], [2, 13, 14], [2, 13, 15]])
      for (let x = x0; x <= x1; x++) t.set(x, y, tone(x, y));
    const cap = lit ? C.glow : C.glowD;
    const capHi = lit ? C.glowL : C.glow;
    const capD = lit ? C.glowD : mixC(C.glowD, C.stoneDD, .5);
    t.rect(9, 9, 2, 2, C.mStem); t.set(10, 9, C.mStemD);
    t.rect(8, 6, 4, 1, cap); t.rect(7, 7, 6, 1, cap); t.rect(7, 8, 6, 1, capD);
    t.set(8, 6, capHi); t.set(9, 6, capHi);
    t.rect(4, 11, 1, 2, C.mStem);
    t.rect(3, 9, 3, 1, cap); t.rect(3, 10, 3, 1, capD);
    if (lit) {
      for (const [x, y] of [[8, 5], [9, 4], [11, 5], [13, 6], [3, 8], [6, 7], [12, 9]]) t.set(x, y, capHi);
      t.set(9, 6, C.glowL); t.set(10, 7, C.glowL);
    } else {
      for (const [x, y] of [[9, 4], [3, 8]]) t.set(x, y, C.glow);
    }
    outlineAA(t, { skipDown: true });
    s.blit(t, (6 + g) * 16);
  }
  s.save('anim_tiles.png');
}

// ===========================================================================
// dungeon_tiles.png — 256x16. Индексы НЕ МЕНЯТЬ:
// 0 пол, 1 пол с трещиной, 2 стена, 3 запертая дверь, 4 открытый проём,
// 5 лестница, 6 колонна (с цепью), 7 обломки, 8 кости, 9 гриб, 10 алтарь,
// 11 сундук, 12 сундук открытый, 13 рычаг вниз, 14 рычаг вверх, 15 пустота
// ===========================================================================
function floorBase(t) {
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const n = nz(x, y, 7, 11, 5, 100);
    let c = n < 7 ? C.floorS : n < 30 ? C.floorD : n < 78 ? C.floor : C.floorL;
    if (nz(x, y, 7, 11, 3, 97) === 0) c = C.floorXL;
    if (nz(x, y, 3, 13, 77, 89) === 0) c = C.floorDD;
    if (nz(x, y, 23, 29, 31, 151) === 0) c = mixC(C.floor, C.rustD, .5);
    if ((y % 8 === 7 && x % 8 !== 7 && nz(x, y, 3, 13, 1, 3) === 0) ||
        (x % 8 === 7 && y % 8 !== 7 && nz(x, y, 13, 3, 2, 3) === 0)) c = C.floorS;   // рваные швы плит
    t.set(x, y, c);
  }
}
function brickBase(t) {
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const band = Math.floor(y / 4);
    let c = nz(x, y, 3, 7, 2, 17) < 3 ? C.brickL : C.brick;
    if (y % 4 === 0) c = C.mortar;
    if ((x + (band % 2) * 4) % 8 === 0 && y % 4 !== 0) c = C.mortar;
    if (y % 4 === 1 && nz(x, y, 5, 11, band + 3, 19) === 0) c = C.brickTop;                    // тёплая кромка камня
    if (y % 4 === 3) c = mixC(c, C.mortar, .35);                                                // тень под камнем
    t.set(x, y, c);
  }
  t.rect(0, 0, 16, 1, C.brickTop); t.rect(0, 1, 16, 1, C.stoneL);
  t.rect(0, 15, 16, 1, C.mortar);
  for (let x = 0; x < 16; x++) {                                                               // мох на нижних камнях
    if (nz(x, 13, 9, 7, 4, 5) === 0) t.set(x, 13, C.cMossD);
    if (nz(x, 12, 9, 7, 9, 7) === 0) t.set(x, 12, C.cMoss);
    if (nz(x, 14, 9, 7, 2, 6) === 0) t.set(x, 14, C.cMoss);
  }
  for (const [x, y] of [[0, 2], [1, 2], [2, 2], [0, 3], [1, 3], [0, 4]]) t.set(x, y, C.boneDim); // паутина в углу
  for (const [x, y] of [[0, 2], [1, 3]]) t.set(x, y, C.bone);
}
function genDungeonTiles() {
  const s = new Img(256, 16);
  const put = () => new Img(16, 16);
  let t;
  // 0 — каменный пол
  t = put(); floorBase(t); s.blit(t, 0);
  // 1 — гнилостная трещина с фиолетовым свечением
  t = put(); floorBase(t);
  const cOff = [1, 0, 0, 1, 2, 2, 1, 1, 0, -1, -1, 0, 0, 1, 1, 0];
  for (let y = 0; y < 16; y++) {
    const cx = 8 + cOff[y];
    t.set(cx, y, y < 2 || y > 13 ? C.glowL : C.glow);
    if (nz(cx, y, 19, 29, 9, 3) < 2) t.set(cx - 1, y, C.glowD);
    if (nz(cx, y, 19, 29, 21, 3) < 2) t.set(cx + 1, y, C.glowD);
    if (nz(cx + 2, y, 19, 29, 13, 4) === 0) t.set(cx + 2, y, C.glowTint);
    if (nz(cx - 2, y, 19, 29, 11, 4) === 0) t.set(cx - 2, y, C.glowTint);
  }
  t.set(10, 4, C.glow); t.set(11, 5, C.glow); t.set(12, 5, C.glowD);
  t.set(6, 11, C.glow); t.set(5, 12, C.glowD);
  t.set(9, 8, C.glowL); t.set(7, 3, C.glowL);
  s.blit(t, 16);
  // 2 — каменная стена
  t = put(); brickBase(t); s.blit(t, 32);
  // 3 — запертая дверь: ржавая пластина с заклёпками, руны, скважина
  t = put(); brickBase(t);
  t.rect(5, 4, 6, 9, C.rust); t.frame(5, 4, 6, 9, C.rustD);
  t.set(6, 5, C.rustL); t.set(7, 5, C.rustL); t.set(6, 6, C.rustL);
  t.set(9, 11, C.rustD); t.set(10, 11, C.rustD); t.set(10, 10, C.rustD);
  t.set(5, 4, C.rustL); t.set(9, 4, C.rustD); t.set(5, 12, C.rustD);                           // заклёпки
  t.set(7, 4, C.rustL);
  t.rect(7, 6, 2, 2, C.openDark); t.rect(7, 8, 2, 3, C.openDark);                              // скважина
  t.set(6, 10, C.glowD); t.set(7, 10, C.glow); t.set(9, 10, C.glowD);                          // руна под пластиной
  t.set(8, 11, C.glowD);
  s.blit(t, 48);
  // 4 — открытый проём: тёмный ход со слабыми отблесками
  t = put(); brickBase(t);
  t.rect(3, 1, 10, 1, C.openDark); t.rect(2, 2, 12, 1, C.openDark); t.rect(1, 3, 14, 13, C.openDark);
  for (let y = 4; y < 16; y++) for (let x = 2; x < 14; x++)
    if (nz(x, y, 23, 17, 5, 9) === 0) t.set(x, y, mixC(C.openDark, C.glowD, .5));
  t.rect(1, 3, 1, 13, C.stone); t.rect(14, 3, 1, 13, C.stone);
  t.rect(0, 3, 1, 13, C.stoneD); t.rect(15, 3, 1, 13, cool(C.stone, .5));
  t.rect(2, 2, 12, 1, C.stoneXL);
  t.set(1, 3, C.stoneXL); t.set(14, 3, C.stoneXL);
  s.blit(t, 64);
  // 5 — лестница вверх
  t = put();
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c = nz(x, y, 3, 7, 2, 17) < 3 ? C.stoneL : C.step;
    if (y % 4 === 0) c = mixC(C.stepL, WARM, .2);
    if (y % 4 === 3) c = C.stepD;
    if (nz(x, y, 5, 13, 9, 61) === 0) c = C.stepD;
    t.set(x, y, c);
  }
  t.rect(0, 0, 3, 2, C.floorS); t.rect(13, 0, 3, 2, C.floorS);
  t.rect(0, 0, 1, 16, C.stoneDD); t.rect(15, 0, 1, 16, C.stoneDD);
  s.blit(t, 80);
  // 6 — колонна с обвитой цепью
  t = put();
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++)
    t.set(x, y, nz(x, y, 13, 29, 3, 13) < 2 ? C.floorS : C.floorD);
  t.rect(3, 0, 10, 2, C.stoneL); t.rect(3, 1, 10, 1, C.stone);
  t.set(3, 0, C.stoneXL); t.set(12, 1, C.stoneD);
  for (let y = 2; y < 13; y++) for (let x = 5; x < 11; x++) {
    let c = C.stone;
    if (nz(x, y, 11, 17, 4, 29) === 0) c = C.stoneD;
    t.set(x, y, c);
  }
  t.rect(5, 2, 1, 11, C.stoneXL); t.rect(10, 2, 1, 11, cool(C.stone, .55));
  t.rect(5, 4, 6, 1, C.ironD);                                                                  // звенья цепи
  for (let x = 5; x <= 10; x += 2) t.set(x, 4, C.iron);
  t.set(5, 5, C.ironL); t.set(6, 5, C.ironD); t.set(5, 6, C.iron); t.set(6, 6, C.ironDD);      // висящее звено
  t.set(9, 7, C.rustD); t.set(10, 8, C.rust);                                                  // потёки ржавчины
  t.rect(3, 13, 10, 3, C.stoneL); t.rect(3, 15, 10, 1, C.stoneD);
  t.set(3, 13, C.stoneXL); t.set(12, 14, C.stoneD);
  s.blit(t, 96);
  // 7 — обломки
  t = put(); floorBase(t);
  const lump = (x, y, w, h) => {
    t.rect(x, y, w, h, C.rg); t.rect(x + 1, y - 1, w - 2, 1, C.rg);
    t.set(x, y, C.rgL); t.set(x + 1, y - 1, C.rgL); t.set(x + 2, y - 1, C.rgL);
    t.rect(x, y + h - 1, w, 1, cool(C.rg, .5)); t.set(x + w - 1, y, C.rgD);
  };
  lump(3, 9, 5, 4); lump(9, 6, 5, 4); lump(11, 12, 3, 2); lump(2, 4, 3, 2);
  t.set(7, 5, C.rgD); t.set(8, 11, C.rgD); t.set(14, 9, C.rgL);
  s.blit(t, 112);
  // 8 — кости: череп с трещиной, бедро, рёбра
  t = put(); floorBase(t);
  t.rect(6, 2, 4, 1, C.bone); t.rect(5, 3, 6, 3, C.bone); t.rect(6, 6, 4, 1, C.bone);
  t.set(6, 4, C.boneEye); t.set(8, 4, C.boneEye);
  t.set(7, 2, C.boneD); t.set(8, 3, C.boneD);                                                  // трещина
  t.set(10, 5, C.boneD); t.set(5, 6, mixC(C.bone, C.floor, .4));                               // грязь/тень
  t.rect(2, 11, 5, 1, C.bone); t.set(2, 10, C.bone); t.set(3, 10, C.bone);
  t.set(5, 12, C.bone); t.set(6, 12, C.bone); t.set(3, 12, C.boneD);
  t.set(10, 9, C.bone); t.set(11, 10, C.bone); t.set(12, 11, C.bone); t.set(12, 12, C.boneD);
  t.set(13, 8, C.boneD); t.set(10, 10, C.boneD);
  s.blit(t, 128);
  // 9 — грибница: фиолетовые шляпки со свечением
  t = put(); floorBase(t);
  t.rect(7, 8, 2, 4, C.mStem); t.rect(8, 9, 1, 3, C.mStemD);
  t.rect(6, 4, 4, 1, C.mCapL); t.rect(5, 5, 6, 1, C.mCap); t.rect(4, 6, 8, 1, C.mCap);
  t.rect(4, 7, 8, 1, C.mCapD);
  t.set(4, 6, C.mCapD); t.set(11, 6, C.mCapD); t.set(6, 5, C.glowL); t.set(8, 4, C.glowL);
  t.set(5, 6, C.mCapD); t.set(9, 6, C.mCapD);
  t.rect(12, 11, 1, 3, C.mStem); t.rect(11, 9, 3, 1, C.mCap); t.rect(11, 10, 3, 1, C.mCapD);
  t.rect(2, 12, 1, 2, C.mStem); t.rect(1, 10, 3, 1, C.mCap); t.rect(1, 11, 3, 1, C.mCapD);
  for (const [x, y] of [[3, 4], [12, 4], [5, 2], [13, 7], [2, 8], [10, 2]]) t.set(x, y, C.spore);
  s.blit(t, 144);
  // 10 — алтарь: руны, свечи, парящее фиолетовое ядро
  t = put(); floorBase(t);
  t.rect(3, 11, 10, 4, C.stone); t.rect(3, 14, 10, 1, C.stoneDD);                              // нижняя ступень
  t.set(3, 11, C.stoneXL); t.set(12, 12, C.stoneD);
  t.rect(5, 8, 6, 3, C.stoneL); t.rect(9, 8, 2, 3, cool(C.stone, .5));
  t.rect(4, 6, 8, 2, C.stoneXL); t.rect(4, 7, 8, 1, C.stoneL);                                 // плита
  t.set(5, 9, C.glowD); t.set(6, 9, C.glow); t.set(7, 10, C.glowD); t.set(9, 9, C.glowD); t.set(10, 9, C.glow); // руны
  t.rect(7, 3, 2, 2, C.glowL); t.rect(6, 3, 1, 2, C.glow); t.rect(9, 3, 1, 2, C.glow);         // ядро
  t.set(7, 2, C.glow); t.set(8, 2, C.glow);
  t.set(6, 2, C.glowD); t.set(9, 2, C.glowD); t.set(5, 4, C.glowD); t.set(10, 4, C.glowD);
  t.set(4, 2, C.glow); t.set(11, 1, C.glow); t.set(6, 0, C.glowD); t.set(9, 0, C.glowD);       // вспышки
  t.rect(2, 5, 1, 3, C.bone); t.set(2, 4, C.fireL); t.set(2, 3, C.fire);                       // свеча слева
  t.rect(13, 6, 1, 2, C.bone); t.set(13, 5, C.fireL); t.set(13, 4, C.fire);                    // свеча справа
  s.blit(t, 160);
  // 11 — алтарный сундук: кованый, с замком
  t = put(); floorBase(t);
  t.rect(2, 5, 12, 3, C.trunk); t.rect(3, 5, 10, 1, C.trunkL); t.rect(2, 7, 12, 1, C.trunkD);  // крышка
  t.rect(2, 8, 12, 7, C.wood); t.frame(2, 8, 12, 7, C.woodD);
  t.rect(2, 14, 12, 1, cool(C.wood, .55));
  for (let y = 5; y < 15; y++) { t.set(3, y, C.bandM); t.set(12, y, C.bandMD); }
  t.rect(2, 8, 12, 1, C.bandM); t.rect(2, 9, 12, 1, C.bandMD);
  t.set(3, 5, C.bandML); t.set(2, 8, C.bandML); t.set(12, 8, C.bandMD);
  t.set(3, 10, C.bandML); t.set(12, 12, C.bandMD);                                             // заклёпки
  t.rect(7, 9, 2, 4, C.goldD); t.frame(7, 9, 2, 4, C.goldDD); t.set(7, 9, C.goldL);            // латунный замок
  t.set(7, 11, C.openDark); t.set(8, 11, C.openDark);
  s.blit(t, 176);
  // 12 — алтарный сундук открыт: фиолетовое свечение внутри
  t = put(); floorBase(t);
  t.rect(2, 1, 12, 3, C.trunk); t.frame(2, 1, 12, 3, C.trunkD);
  t.rect(2, 3, 12, 1, C.trunkD);
  t.rect(3, 4, 10, 1, C.bandMD);
  for (let y = 1; y < 4; y++) { t.set(3, y, C.bandM); t.set(12, y, C.bandMD); }
  t.rect(3, 5, 10, 3, C.woodIn);
  t.rect(4, 6, 8, 2, C.glowD); t.rect(6, 6, 4, 2, C.glow); t.rect(7, 6, 2, 2, C.glowL);        // свечение
  t.set(5, 5, C.glowD); t.set(10, 5, C.glowD); t.set(7, 5, C.glow); t.set(8, 5, C.glow);
  t.rect(2, 8, 12, 7, C.wood); t.frame(2, 8, 12, 7, C.woodD);
  t.rect(2, 14, 12, 1, cool(C.wood, .55));
  for (let y = 8; y < 15; y++) { t.set(3, y, C.bandM); t.set(12, y, C.bandMD); }
  t.rect(2, 8, 12, 1, C.bandM);
  t.set(3, 8, C.bandML); t.set(2, 8, C.bandML);
  s.blit(t, 192);
  // 13/14 — рычаг на постаменте
  const lever = (up) => {
    const v = put(); floorBase(v);
    v.rect(5, 11, 6, 4, C.stone); v.rect(5, 14, 6, 1, C.stoneDD);
    v.rect(6, 10, 4, 1, C.stoneXL); v.set(10, 12, C.stoneD);
    v.rect(7, 9, 2, 2, C.iron); v.set(7, 9, C.ironL);
    if (up) {
      for (const [x, y] of [[9, 8], [10, 7], [11, 6], [12, 5]]) { v.set(x, y, C.leverStick); v.set(x, y + 1, C.leverStickD); }
      v.rect(12, 3, 2, 2, C.iron); v.set(12, 3, C.ironL); v.set(8, 9, C.ironDD);
    } else {
      for (const [x, y] of [[9, 10], [10, 11], [11, 12], [11, 13]]) { v.set(x, y, C.leverStick); v.set(x - 1, y, C.leverStickD); }
      v.rect(11, 12, 2, 2, C.iron); v.set(11, 12, C.ironL); v.set(8, 10, C.ironDD);
    }
    return v;
  };
  s.blit(lever(false), 13 * 16);
  s.blit(lever(true), 14 * 16);
  // 15 — пустота: почти чёрная, едва различимые фиолетовые прожилки
  t = put();
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c = C.voidB;
    const v = nz(x, y, 13, 29, 7, 31);
    if (v < 4) c = C.voidP;
    if (v === 0 && nz(x, y, 31, 41, 11, 7) < 2) c = C.voidP2;
    t.set(x, y, c);
  }
  s.blit(t, 15 * 16);
  s.save('dungeon_tiles.png');
}

// ===========================================================================
// Персонажи 16x16. Тот же скелет позы и опорные точки (стопы y12/13), что в
// gen_assets2: ряды 0=down 1=left 2=right 3=up; col0=стойка, col1/col2=шаги.
// Лицо с чертами: брови, нос, рот; тёмный низ силуэта; материалы с тонами.
// ===========================================================================
function drawChar(opts, dir, step) {
  const f = new Img(16, 16);
  const hair = opts.hair;
  const skin = opts.skin || C.skin, skinD = opts.skinD || C.skinD;
  const hood = opts.hood || null;
  const hoodD = opts.hoodD || cool(hood || C.robeD, .35);
  const tunic = opts.tunic, tunicL = opts.tunicL || lite(tunic, .3), tunicD = opts.tunicD || cool(tunic, .5);
  // --- голова ---
  if (hood) {
    f.rect(5, 2, 6, 1, mixC(hood, hoodD, .4));
    f.set(5, 2, lite(hood, .22));
    f.rect(4, 3, 8, 1, hood);
    f.rect(4, 4, 1, 3, hoodD); f.rect(11, 4, 1, 3, cool(hood, .55));
    f.set(4, 3, lite(hood, .25));
    if (dir === 3) { f.rect(5, 3, 6, 3, hoodD); f.rect(5, 3, 6, 1, mixC(hood, hoodD, .45)); }
    else {
      f.rect(5, 4, 6, 2, skin);
      f.rect(5, 4, 6, 1, mixC(skin, skinD, .7));                    // глубокая тень капюшона
    }
  } else {
    f.rect(5, 2, 6, 1, mixC(hair, [216, 198, 168], .35));
    f.rect(6, 2, 4, 1, hair);
    f.rect(4, 3, 8, 1, hair);
    f.set(4, 3, mixC(hair, [216, 198, 168], .3)); f.set(11, 3, cool(hair, .4));
    if (dir === 3) f.rect(5, 4, 6, 2, hair);
    else {
      f.rect(4, 4, 1, 2, mixC(hair, COOL, .3)); f.rect(11, 4, 1, 2, cool(hair, .5));
      f.rect(5, 4, 6, 2, skin);
      f.set(5, 4, mixC(skin, C.skinL, .45)); f.set(5, 5, mixC(skin, C.skinL, .25));
      f.set(10, 4, skinD); f.set(10, 5, mixC(skinD, C.skinDD, .6));
      f.set(6, 4, C.skinSh); f.set(9, 4, C.skinSh);                 // брови
      if (dir === 0) { f.set(6, 5, C.eye); f.set(9, 5, C.eye); f.set(7, 5, C.skinD); f.set(8, 5, C.skinD); }
      if (dir === 1) { f.set(6, 5, C.eye); f.set(7, 5, C.skinD); }
      if (dir === 2) { f.set(9, 5, C.eye); f.set(8, 5, C.skinD); }
    }
  }
  f.rect(6, 6, 4, 1, skin);
  f.set(9, 6, skinD);
  if (dir === 0 && !opts.beard) { f.set(7, 6, C.mouth); f.set(8, 6, mixC(C.mouth, C.skinDD, .4)); }
  if (opts.trimBeard && dir !== 3) { f.set(7, 6, mixC(hair, C.skinDD, .25)); f.set(8, 6, cool(hair, .3)); }
  // --- тело: кольца кольчуги или ткань с тонами, свет левый ---
  if (opts.mail) {
    for (let y = 7; y <= 8; y++) for (let x = 6; x <= 9; x++)
      f.set(x, y, (x + y) % 2 === 0 ? C.steelD : (x === 6 && y === 7 ? C.steelL : C.steel));
    f.rect(5, 7, 1, 2, C.steelDD); f.rect(10, 7, 1, 2, cool(C.steel, .55));
    f.set(5, 7, C.steel); f.set(10, 7, C.steelD);                   // наплечники
    if (opts.trim) { f.set(6, 7, opts.trim); f.set(9, 7, opts.trim); }
  } else {
    f.rect(6, 7, 4, 2, tunic);
    f.rect(5, 7, 1, 2, tunicD); f.rect(10, 7, 1, 2, cool(tunic, .6));
    f.set(6, 7, tunicL); f.set(6, 8, mixC(tunic, tunicL, .5));
    f.set(9, 7, mixC(tunic, tunicD, .5)); f.set(9, 8, mixC(tunic, tunicD, .3));
    if (opts.trim) { f.set(6, 7, opts.trim); f.set(9, 7, mixC(opts.trim, COOL, .4)); }
  }
  const belt = opts.belt || C.leather;
  f.rect(6, 9, 4, 1, belt);
  f.set(6, 9, lite(belt, .2)); f.set(9, 9, cool(belt, .45));
  // руки/кисти (шаг меняет фазу)
  const aUp = step === 1, aDn = step === 2;
  f.set(4, 8, skin); f.set(11, 8, skinD);
  if (aUp) { f.set(4, 7, skin); f.set(11, 9, skinD); }
  if (aDn) { f.set(4, 9, skin); f.set(11, 7, skinD); }
  if (opts.apron) { f.rect(6, 8, 4, 1, opts.apron); f.set(9, 8, mixC(opts.apron, C.apronD, .6)); }
  // --- ноги + тёмные ботинки (вес) ---
  const pants = opts.pants || C.pants, pantsD = opts.pantsD || cool(pants, .45);
  const pantsL = mixC(pants, [226, 222, 238], .18);
  const boot = opts.boot || C.boot, bootD = opts.bootD || C.bootD;
  if (step === 0) {
    f.rect(6, 10, 2, 2, pants); f.rect(8, 10, 2, 2, pantsD); f.set(6, 10, pantsL);
    f.rect(6, 12, 2, 1, boot); f.rect(8, 12, 2, 1, mixC(boot, bootD, .5));
  } else if (step === 1) {
    f.rect(6, 10, 2, 2, pants); f.rect(8, 10, 2, 1, pantsD);
    f.rect(6, 12, 2, 1, boot); f.set(8, 11, mixC(boot, bootD, .5));
  } else {
    f.rect(6, 10, 2, 1, pants); f.rect(8, 10, 2, 2, pantsD);
    f.set(6, 11, boot); f.rect(8, 12, 2, 1, mixC(boot, bootD, .5));
  }
  // --- длинные волосы / борода ---
  if (opts.longHair && dir !== 3) { f.rect(4, 6, 1, 2, hair); f.rect(11, 6, 1, 2, cool(hair, .4)); }
  if (opts.beard && dir !== 3) {
    f.rect(5, 6, 6, 1, hair); f.rect(6, 7, 4, 1, hair);
    f.set(6, 6, mixC(hair, [226, 228, 234], .45)); f.set(6, 7, mixC(hair, [226, 228, 234], .25));
    f.set(9, 7, cool(hair, .45));
  }
  // --- снаряжение ---
  if (opts.sword) { f.set(12, 4, C.steelL); f.rect(12, 5, 1, 4, C.steel); f.set(12, 9, C.leatherD); }
  if (opts.quiver) {
    if (dir === 2) { f.rect(3, 4, 1, 4, C.quiverC); f.set(3, 7, C.quiverD); f.set(3, 3, C.featherW); }
    else if (dir === 3) { f.rect(7, 4, 2, 4, C.quiverC); f.rect(7, 7, 2, 1, C.quiverD); f.set(7, 3, C.featherW); f.set(8, 3, C.featherW); }
    else { f.rect(12, 4, 1, 4, C.quiverC); f.set(12, 7, C.quiverD); f.set(12, 3, C.featherW); }
  }
  return f;
}

// лист 48x64: 4 ряда (down,left,right,up) x 3 колонки (idle, шаг1, шаг2)
function genClass(name, opts) {
  const sheet = new Img(48, 64);
  for (let row = 0; row < 4; row++) {
    for (let col = 0; col < 3; col++) {
      const fr = drawChar(opts, row, col);
      outlineAA(fr, { skipDown: true });
      sheet.blit(fr, col * 16, row * 16);
    }
  }
  sheet.save(name);
}
function genAllCharacters() {
  genClass('player.png', { hair: C.hairD, tunic: C.tunic, tunicD: C.tunicD, sword: true });
  genClass('class_warrior.png', {
    hair: C.hairD, mail: true, trim: C.blood, tunic: C.leatherD, belt: C.ironD,
    pants: C.pantsD, boot: C.boot, sword: true,
  });
  genClass('class_archer.png', {
    hair: C.hairD, hood: C.leafD, hoodD: C.leafDD, tunic: C.leather, tunicD: C.leatherD, trim: C.leaf,
    belt: C.leatherD, pants: [78, 74, 56], boot: C.boot, quiver: true,
  });
  genClass('class_mage.png', {
    hair: C.hairD, hood: C.robe, hoodD: C.robeD, tunic: C.robe, tunicL: C.robeL, tunicD: C.robeD,
    trim: C.gold, belt: C.goldD, pants: C.robeDD, boot: [42, 34, 66], trimBeard: true,
  });
  genNpc('npc_elder', { hair: C.gray, tunic: C.robe, tunicD: C.robeD, beard: true, longHair: true });
  genNpc('npc_merchant', { hair: C.hairP, tunic: C.wood, tunicD: C.woodD, apron: C.apron });
  genNpc('npc_farmer', { hair: C.hairD, tunic: [118, 88, 62], tunicD: [86, 62, 44], pants: [84, 74, 54] });
  genNpc('npc_hermit', {
    hair: C.wWhite, tunic: C.hermRobe, tunicD: C.hermRobeD, tunicL: C.hermRobeL,
    skin: C.hermSkin, skinD: C.hermSkinD, pants: C.hermRobeD, belt: C.leatherD,
    beard: true, longHair: true,
  });
}
function genNpc(name, opts) {
  const f = drawChar(opts, 0, 0);
  outlineAA(f, { skipDown: true });
  f.save(name + '.png');
}

// ===========================================================================
// slime.png 32x16 — 2 кадра 16x16: squash с тем же центром массы
// ===========================================================================
function genSlime() {
  const sheet = new Img(32, 16);
  const blob = (ox, base, top, w) => {
    const f = new Img(16, 16);
    for (let y = top; y <= base; y++) {
      const t = (y - top) / Math.max(1, base - top);
      const hw = Math.round((w / 2) * (0.45 + 0.55 * t));
      for (let x = 8 - hw; x < 8 + hw; x++) {
        let c = C.slimeG;
        const n = nz(x, y, 7, 5, ox, 17);
        if (n < 4) c = C.slimeD; else if (n > 13) c = C.slimeL;
        if (t > 0.72) c = mixC(c, C.slimeDD, .5);
        if (x === 8 - hw) c = mixC(c, C.slimeL, .4);
        if (x === 8 + hw - 1) c = mixC(c, C.slimeDD, .6);
        f.set(x, y, c);
      }
    }
    const cy = base - 2;                                    // ядовитое ядро
    f.set(7, cy, C.tox); f.set(8, cy, C.toxD); f.set(7, cy - 1, C.toxD); f.set(8, cy - 1, C.tox);
    f.rect(5, top + 1, 2, 1, C.slimeXL);                    // блик верх-лево
    f.set(5, top + 2, mixC(C.slimeL, C.slimeXL, .5));
    const ey = top + Math.round((base - top) * 0.45);
    f.set(6, ey, C.eye); f.set(10, ey, C.eye);
    f.set(6, ey + 1, mixC(C.eye, C.slimeDD, .4)); f.set(10, ey + 1, mixC(C.eye, C.slimeDD, .4));
    f.set(5, ey - 1, C.slimeDD); f.set(11, ey - 1, C.slimeDD);          // сердитые брови
    f.set(7, ey + 3, C.slimeDD); f.set(8, ey + 3, mixC(C.slimeDD, C.eye, .4)); f.set(9, ey + 3, C.slimeDD);
    outlineAA(f, { skipDown: true });
    sheet.blit(f, ox, 0);
  };
  blob(0, 13, 6, 12);
  blob(16, 14, 9, 14);
  sheet.save('slime.png');
}

// ===========================================================================
// brute.png 64x32 — 2 кадра 32x32, крупный босс заполняет кадр.
// Кадр 2 — присевший (ниже на 3px, шире на 2px), стабильная линия опоры.
// ===========================================================================
function genBrute() {
  const s = new Img(64, 32);
  const frame = (ox, top, base, maxHW) => {
    const f = new Img(32, 32), cx = 16;
    const hwAt = (y) => Math.round(maxHW * (0.38 + 0.62 * (y - top) / Math.max(1, base - top)));
    // тело: ступенчатые тона, свет слева, тень справа, сегменты брюха
    for (let y = top; y <= base; y++) {
      const hw = hwAt(y);
      const t = (y - top) / Math.max(1, base - top);
      for (let x = cx - hw; x <= cx + hw; x++) {
        let c = C.brute;
        const n = nz(x, y, 9, 17, ox, 29);
        if (n < 5) c = C.bruteD; else if (n > 24) c = C.bruteL;
        if (t >= 0.5 && Math.abs(x - cx) <= hw - 4) {
          c = C.bruteL;
          if ((y - top) % 3 === 0) c = mixC(C.bruteL, C.bruteD, .6);
          if (n < 4) c = C.brute;
        }
        if (x === cx - hw) c = mixC(c, C.bruteL, .4);
        else if (x === cx + hw) c = mixC(c, C.bruteDD, .7);
        if (y === top) c = mixC(c, C.bruteD, .55);
        f.set(x, y, c);
      }
    }
    for (const dx of [-8, -4, 0, 4, 8]) f.set(cx + dx, top - 1, C.bruteDD);     // хребтовые наросты
    for (let dx = -maxHW; dx <= maxHW; dx++) f.set(cx + dx, base, C.bruteDD);   // линия опоры
    f.set(cx - 5, top + 3, C.bruteXL); f.set(cx - 4, top + 3, C.bruteXL); f.set(cx - 5, top + 4, C.bruteXL);
    // осквернённые язвы (детерминированный шум, в стороне от глаз), светлая сердцевина
    const ey = top + Math.round((base - top) * 0.35);
    const inEye = (x, y) => (x >= 9 && x <= 13 || x >= 19 && x <= 23) && y >= ey - 3 && y <= ey + 3;
    for (let y = top + 2; y <= top + 8; y++) {
      const hw = hwAt(y);
      for (let dx = -(hw - 2); dx <= hw - 2; dx++) {
        const x = cx + dx;
        if (inEye(x, y) || nz(x, y, 17, 29, 5 + ox, 23) !== 0) continue;
        f.set(x, y, C.bruteSpot);
        if (nz(x, y + 1, 17, 29, 6 + ox, 11) === 0 && y + 1 <= top + 9 && !inEye(x, y + 1)) {
          f.set(x, y + 1, C.bruteSpot); f.set(x, y, C.glowL);
        }
      }
    }
    // гнилые потёки снизу
    for (const dx of [-7, -2, 4, 8]) {
      const h = 2 + Math.abs(dx * 13 + top * 7) % 3;
      for (let i = 0; i < h; i++) f.set(cx + dx, base - i, C.bruteDD);
      if (h >= 4 && base < 27) f.set(cx + dx, base + 1, C.bruteDD);
    }
    // глаза: фиолетовые светящиеся с вертикальным зрачком, тяжёлые брови
    f.rect(10, ey, 3, 3, C.glowL); f.rect(20, ey, 3, 3, C.glowL);
    f.rect(11, ey, 1, 3, C.eye); f.rect(21, ey, 1, 3, C.eye);
    for (const [x, y] of [[9, ey - 3], [10, ey - 2], [11, ey - 2], [12, ey - 1],
                          [23, ey - 3], [22, ey - 2], [21, ey - 2], [20, ey - 1]]) {
      if (x >= cx - hwAt(y) && x <= cx + hwAt(y)) f.set(x, y, C.bruteBrow);
    }
    // рот с клыками и кровью у уголков
    const yM = ey + 6;
    f.rect(cx - 4, yM, 9, 1, C.bruteMouth);
    f.set(cx - 2, yM + 1, C.tooth); f.set(cx - 1, yM + 1, C.tooth);
    f.set(cx + 2, yM + 1, C.tooth); f.set(cx + 3, yM + 1, C.tooth);
    f.set(cx - 5, yM, C.bloodD); f.set(cx + 4, yM, C.bloodD);
    outlineAA(f, { skipDown: true });
    s.blit(f, ox, 0);
  };
  frame(0, 7, 26, 12);
  frame(32, 10, 27, 13);
  s.save('brute.png');
}

// ===========================================================================
// Портреты 120x40 (3 слота по 40px). portraits.png: герой/старейшина/торговец
// portraits2.png: герой/отшельник/босс. Слоты и размеры — по константам hud.gd.
// ===========================================================================
function bigHead(img, ox, opts) {
  const hair = opts.hair, skin = opts.skin || C.skin;
  const hairD = cool(hair, .5), hairHL = mixC(hair, [226, 206, 172], .5);
  const collar = opts.collar || C.tunicD;
  const collarL = lite(collar, .2), collarD = cool(collar, .5);
  // плечи/бюст
  img.rect(ox + 6, 30, 28, 10, collar);
  img.rect(ox + 6, 30, 28, 1, collarL);
  img.rect(ox + 6, 31, 2, 9, mixC(collar, collarL, .4));
  img.rect(ox + 32, 31, 2, 9, collarD);
  img.rect(ox + 18, 32, 4, 8, mixC(collar, collarD, .6));
  // «шлем» волос + лицо
  img.rect(ox + 6, 4, 28, 20, hair);
  img.rect(ox + 9, 8, 22, 22, skin);
  img.rect(ox + 6, 4, 28, 6, hair);
  img.rect(ox + 6, 8, 4, 14, hair);
  img.rect(ox + 30, 8, 4, 14, hair);
  for (let y = 5; y <= 7; y++) for (let x = 8; x <= 17; x++)
    img.set(ox + x, y, nz(x, y, 3, 5, 1, 7) < 3 ? hairHL : mixC(hair, hairHL, .35));   // пряди света
  for (let y = 4; y <= 24; y++) {                                                       // правая прядь в тени
    img.set(ox + 32, y, hairD);
    if (nz(0, y, 3, 9, 4, 3) === 0) img.set(ox + 31, y, hairD);
  }
  // притенение левой височной зоны (свет всё же сверху)
  for (let y = 9; y <= 27; y++) img.set(ox + 10, y, y % 2 ? mixC(skin, C.skinL, .55) : skin);
  // холодные тени щёк справа, ступенчато
  const ch1 = mixC(skin, C.skinSh, .55), ch2 = mixC(skin, C.skinSh, .28);
  for (let y = 11; y <= 28; y++) { img.set(ox + 29, y, ch1); img.set(ox + 28, y, ch2); }
  // лоб: тёплый свет ступенчатый
  const fh1 = mixC(skin, C.skinL, .5);
  for (let x = 13; x <= 24; x++) img.set(ox + x, 9, x % 2 ? fh1 : mixC(skin, fh1, .5));
  // глаза: веко, белок, радужка, блик, тень под глазом
  img.rect(ox + 13, 18, 4, 1, mixC(skin, C.skinDD, .45));
  img.rect(ox + 23, 18, 4, 1, mixC(skin, C.skinDD, .45));
  img.rect(ox + 13, 19, 4, 4, C.eyeW);
  img.rect(ox + 23, 19, 4, 4, C.eyeW);
  img.rect(ox + 14, 20, 2, 3, C.eye);
  img.rect(ox + 24, 20, 2, 3, C.eye);
  img.set(ox + 13, 20, mixC(C.eyeW, [255, 255, 255], .7));
  img.set(ox + 23, 20, mixC(C.eyeW, [255, 255, 255], .7));
  img.rect(ox + 13, 23, 4, 1, mixC(skin, C.skinDD, .35));
  img.rect(ox + 23, 23, 4, 1, mixC(skin, C.skinDD, .35));
  // нахмуренные брови (внутренние концы ниже)
  img.rect(ox + 12, 16, 5, 1, hairD); img.rect(ox + 15, 17, 2, 1, hairD);
  img.rect(ox + 23, 16, 5, 1, hairD); img.rect(ox + 23, 17, 2, 1, hairD);
  // нос: спинка, свет слева, тень справа, ноздри
  img.rect(ox + 19, 21, 2, 5, mixC(skin, C.skinD, .35));
  img.set(ox + 19, 24, mixC(skin, C.skinL, .3)); img.set(ox + 19, 25, mixC(skin, C.skinL, .3));
  img.rect(ox + 20, 24, 1, 3, C.skinD);
  img.set(ox + 18, 26, C.skinDD); img.set(ox + 21, 26, C.skinDD);
  // рот / борода
  if (opts.beard) {
    img.rect(ox + 12, 27, 16, 5, hair);
    for (let y = 28; y <= 31; y += 2) for (let x = 13; x <= 26; x += 3)
      img.set(ox + x, y, nz(x, y, 5, 3, 2, 5) < 2 ? mixC(hair, hairHL, .5) : hair);
    img.rect(ox + 24, 28, 3, 4, hairD);
    img.rect(ox + 17, 27, 6, 2, mixC(C.mouth, C.skinDD, .3));
  } else {
    img.rect(ox + 17, 27, 6, 1, C.mouth);
    img.set(ox + 17, 27, mixC(C.mouth, C.skinDD, .5)); img.set(ox + 22, 27, mixC(C.mouth, C.skinDD, .5));
    img.rect(ox + 18, 28, 4, 1, mixC(skin, C.skinD, .55));
    img.rect(ox + 17, 29, 6, 1, mixC(skin, C.skinDD, .35));      // тень подбородка
  }
  // тень шеи под подбородком
  img.rect(ox + 15, 29, 10, 1, mixC(skin, C.skinDD, .55));
  // головной убор (платок торговца)
  if (opts.hat) {
    img.rect(ox + 4, 2, 32, 4, opts.hat); img.rect(ox + 10, 0, 20, 3, opts.hat);
    img.rect(ox + 4, 5, 32, 1, cool(opts.hat, .5));
    img.rect(ox + 10, 0, 10, 2, lite(opts.hat, .22));
    img.rect(ox + 32, 3, 4, 2, cool(opts.hat, .35));
  }
}
function monsterHead(img, ox) {
  const rows = [];
  const R = (y0, y1, x0, x1) => rows.push([y0, y1, x0, x1]);
  R(1, 1, 15, 24); R(2, 2, 11, 28); R(3, 3, 9, 30); R(4, 4, 7, 32); R(5, 5, 6, 33);
  R(6, 8, 5, 34); R(9, 12, 4, 35); R(13, 24, 3, 36); R(25, 30, 4, 35); R(31, 33, 7, 32);
  R(34, 35, 10, 29); R(36, 39, 6, 33);
  for (const [y0, y1, x0, x1] of rows)
    for (let y = y0; y <= y1; y++) {
      const neck = y >= 34;
      for (let x = x0; x <= x1; x++) {
        let c = neck ? C.bruteD : C.brute;
        if (!neck && y >= 30) c = C.bruteDD;
        if (!neck && nz(x, y, 9, 13, 3, 19) > 15) c = C.bruteL;
        img.set(ox + x, y, c);
      }
      img.set(ox + x0, y, C.monOut); img.set(ox + x1, y, C.monOut);
      if (!neck && x1 - x0 > 8) img.set(ox + x0 + 1, y, C.bruteXL);            // тёплый rim-light слева
      if (!neck && x1 - x0 > 8) img.set(ox + x1 - 1, y, C.bruteDD);
    }
  for (const [x, y] of [[6, 12], [8, 8], [30, 10], [32, 16], [28, 32], [10, 36]]) {
    img.set(ox + x, y, C.bruteSpot); img.set(ox + x + 1, y, C.bruteSpot); img.set(ox + x, y + 1, C.glow);
  }
  for (const [x, y] of [[14, 3], [24, 2], [4, 20], [34, 26]]) { img.set(ox + x, y, C.bruteDD); img.set(ox + x + 1, y, C.bruteDD); }
  // глаза: фиолетовые, светящиеся
  img.rect(ox + 9, 14, 6, 5, C.glowL); img.rect(ox + 25, 14, 6, 5, C.glowL);
  img.rect(ox + 12, 16, 2, 3, C.eye); img.rect(ox + 26, 16, 2, 3, C.eye);
  img.rect(ox + 9, 11, 5, 1, C.bruteBrow); img.rect(ox + 12, 12, 4, 1, C.bruteBrow); img.rect(ox + 14, 13, 3, 1, C.bruteBrow);
  img.rect(ox + 26, 11, 5, 1, C.bruteBrow); img.rect(ox + 24, 12, 4, 1, C.bruteBrow); img.rect(ox + 23, 13, 3, 1, C.bruteBrow);
  img.rect(ox + 11, 26, 17, 3, C.bruteMouth);
  img.rect(ox + 14, 26, 2, 2, C.tooth); img.rect(ox + 24, 26, 2, 2, C.tooth);
  img.rect(ox + 19, 28, 2, 1, C.tooth);
  img.set(ox + 10, 27, C.bloodD); img.set(ox + 28, 27, C.bloodD);
}
function genPortraits() {
  const s = new Img(120, 40);
  bigHead(s, 0, { hair: C.hairD, collar: C.tunicD });
  bigHead(s, 40, { hair: C.gray, beard: true, collar: C.robeD });
  bigHead(s, 80, { hair: C.hairP, hat: C.apronD, collar: C.apron });
  outlineAA(s, { skipDown: true });
  s.save('portraits.png');
  const s2 = new Img(120, 40);
  bigHead(s2, 0, { hair: C.hairD, collar: C.tunicD });
  bigHead(s2, 40, { hair: C.wWhite, beard: true, collar: C.hermRobe, skin: C.hermSkin });
  monsterHead(s2, 80);
  outlineAA(s2, { skipDown: true });
  s2.save('portraits2.png');
}

// ===========================================================================
// key.png 16x16 — диагональный латунный ключ: свет кромки слева-сверху,
// тёмные кромки справа-снизу, тёмная (не чёрная) обводка
// ===========================================================================
function genKey() {
  const f = new Img(16, 16);
  const gold = new Set();
  const add = (x, y) => { if (x >= 0 && y >= 0 && x < 16 && y < 16) gold.add(x + ',' + y); };
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const d = (x - 11.5) * (x - 11.5) + (y - 3.5) * (y - 3.5);
    if (d >= 1.5 && d <= 6.5) add(x, y);
  }
  for (let x = 4; x <= 10; x++) add(x, 15 - x);
  add(8, 5); add(10, 7);
  for (const [x, y] of [[6, 11], [7, 12], [5, 12], [6, 13]]) add(x, y);
  const has = (x, y) => gold.has(x + ',' + y);
  for (const k of gold) {
    const [x, y] = k.split(',').map(Number);
    let c = C.gold;
    if (!has(x - 1, y) || !has(x, y - 1)) c = C.goldL;
    if (!has(x + 1, y) || !has(x, y + 1)) c = C.goldD;
    if (!has(x - 1, y) && !has(x, y - 1)) c = C.goldL;
    f.set(x, y, c);
  }
  for (const [x, y] of [[11, 2], [9, 6]]) f.set(x, y, C.goldXL);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    if (gold.has(x + ',' + y)) continue;
    let near = false;
    for (let dy = -1; dy <= 1 && !near; dy++) for (let dx = -1; dx <= 1; dx++)
      if (gold.has((x + dx) + ',' + (y + dy))) { near = true; break; }
    if (near) f.set(x, y, x >= 10 && y <= 5 ? C.goldDD : C.keyDark);
  }
  outlineAA(f, { skipDown: true, aaOnly: true });
  f.save('key.png');
}

// ===========================================================================
// heart.png 7x6 — алый классический (иконка проекта): объём ступенчатыми
// тонами — тёплый верх-лево, холодный низ-право. Левая половина (0..3) —
// полноценный «половинчатый» харт для HUD.
// ===========================================================================
function genHeart() {
  const t = new Img(7, 6);
  t.rect(1, 0, 2, 1, C.heart); t.rect(4, 0, 2, 1, C.heart);
  t.rect(0, 1, 7, 2, C.heart);
  t.rect(1, 3, 5, 1, C.heart); t.rect(2, 4, 3, 1, C.heart); t.rect(3, 5, 1, 1, C.heart);
  outlineAA(t, {});
  t.set(1, 1, C.heartHL); t.set(2, 1, C.heartL); t.set(2, 2, C.heartL); t.set(1, 2, C.heartHL); t.set(0, 1, C.heartL);
  t.set(5, 0, C.heartD); t.set(6, 1, C.heartD); t.set(6, 2, C.heartD);
  t.set(5, 3, C.heartD); t.set(4, 4, C.heartD); t.set(3, 5, C.heartDD);
  t.save('heart.png');
}

// ===========================================================================
// skill_icons.png — 192x16, 12 слотов: 0-3 воин, 4-7 лучник, 8-11 маг
// (порядок по classes_data.gd: power_strike, whirlwind, second_wind, execute,
//  pierce, volley, mark, rain, firebolt, frost_nova, siphon, firestorm)
// ===========================================================================
function iconBase() {
  const im = new Img(16, 16);
  const span = (y) => (y === 0 || y === 15) ? [2, 13] : (y === 1 || y === 14) ? [1, 14] : [0, 15];
  for (let y = 0; y < 16; y++) { const [x0, x1] = span(y); im.rect(x0, y, x1 - x0 + 1, 1, C.iconBg); }
  const dk = C.iconDark;
  im.rect(2, 0, 12, 1, dk); im.rect(2, 15, 12, 1, dk);
  im.rect(0, 2, 1, 12, dk); im.rect(15, 2, 1, 12, dk);
  for (const [x, y] of [[1, 1], [14, 1], [1, 14], [14, 14]]) im.set(x, y, dk);
  return im;
}
function autoOutline(im) {
  const bgk = C.iconBg.join(','), dkk = C.iconDark.join(',');
  const key = (x, y) => { const c = im.get(x, y); return c ? c[0] + ',' + c[1] + ',' + c[2] : ''; };
  const lit = [];
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    if (key(x, y) !== bgk) continue;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]])
      { const k = key(x + dx, y + dy); if (k && k !== bgk && k !== dkk) { lit.push([x, y]); break; } }
  }
  for (const [x, y] of lit) im.set(x, y, C.iconDark);
}
function bevel(im) {                       // фаска плитки: свет верх/лево, тень низ/право
  for (let x = 3; x <= 12; x++) { im.set(x, 2, C.iconEdge); im.set(x, 13, [12, 12, 18]); }
  for (let y = 3; y <= 12; y++) { im.set(2, y, mixC(C.iconEdge, C.iconBg, .45)); im.set(13, y, [12, 12, 18]); }
}
const gPowerStrike = (im) => {
  im.set(8, 2, C.steelL); im.rect(7, 3, 2, 6, C.steel);
  for (let y = 3; y <= 8; y++) im.set(7, y, C.steelL);
  im.set(8, 8, C.steelD);
  im.rect(5, 9, 6, 1, C.gold); im.set(5, 9, C.goldL); im.set(10, 9, C.goldD);
  im.rect(7, 10, 2, 3, C.leatherD); im.set(7, 10, C.leather);
  im.rect(7, 13, 2, 1, C.goldD);
  for (const [x, y] of [[4, 4], [11, 4], [3, 7], [12, 7], [4, 11], [11, 11]]) im.set(x, y, C.fireL);
};
const gWhirlwind = (im) => {
  for (const [x, y] of [[8, 8], [8, 7]]) im.set(x, y, C.steelD);
  for (const [x, y] of [[7, 7], [6, 8], [7, 9], [9, 9], [10, 8], [10, 6], [9, 5]]) im.set(x, y, C.steel);
  for (const [x, y] of [[7, 5], [5, 6], [5, 8], [5, 10], [7, 11], [9, 11], [11, 10], [12, 8], [12, 5], [11, 3]]) im.set(x, y, C.steelL);
  for (const [x, y] of [[3, 4], [4, 3], [12, 12], [11, 13]]) im.set(x, y, C.steelDD);
};
const gSecondWind = (im) => {
  im.rect(7, 4, 2, 8, C.wWhite); im.rect(4, 7, 8, 2, C.wWhite);
  im.rect(8, 4, 1, 8, C.steelD); im.rect(4, 8, 8, 1, C.steelD);
  im.rect(7, 4, 1, 8, mixC(C.wWhite, C.healT, .5)); im.rect(4, 7, 8, 1, mixC(C.wWhite, C.healT, .5));
  for (const [x, y] of [[7, 2], [8, 2], [7, 13], [8, 13], [2, 7], [2, 8], [13, 7], [13, 8], [5, 5], [10, 5], [5, 10], [10, 10]]) im.set(x, y, C.healT);
};
const gExecute = (im) => {
  im.rect(5, 4, 6, 5, C.bone); im.rect(6, 9, 4, 2, C.bone);
  im.rect(6, 6, 1, 2, C.boneEye); im.rect(9, 6, 1, 2, C.boneEye);
  im.rect(5, 8, 6, 1, C.boneD); im.set(8, 4, C.boneD);
  im.set(7, 10, C.boneEye); im.set(8, 10, C.boneEye);
  im.set(7, 12, C.blood); im.set(9, 11, C.bloodD); im.set(6, 13, C.bloodD);
};
const arrowH = (im, y) => {
  im.rect(4, y, 8, 1, C.arrowShaft); im.set(4, y, C.leatherD);
  im.set(12, y, C.steel); im.set(13, y, C.steelL);
  im.set(3, y - 1, C.featherW); im.set(3, y, C.featherW); im.set(3, y + 1, C.featherW); im.set(2, y, C.featherW);
  im.set(3, y + 1, C.featherD);
};
const gPierce = (im) => { arrowH(im, 6); arrowH(im, 10); };
const gVolley = (im) => {
  im.rect(8, 5, 1, 7, C.arrowShaft); im.set(8, 3, C.steelL); im.set(8, 4, C.steel);
  im.set(7, 12, C.featherW); im.set(9, 12, C.featherW);
  im.set(4, 4, C.steelL); im.set(3, 5, C.steel);
  for (const [x, y] of [[4, 6], [4, 7], [3, 8], [3, 9], [3, 10]]) im.set(x, y, C.arrowShaft);
  im.set(2, 11, C.featherW); im.set(4, 11, C.featherW); im.set(3, 10, C.featherD);
  im.set(11, 4, C.steelL); im.set(12, 5, C.steel);
  for (const [x, y] of [[11, 6], [11, 7], [12, 8], [12, 9], [12, 10]]) im.set(x, y, C.arrowShaft);
  im.set(13, 11, C.featherW); im.set(10, 11, C.featherW); im.set(12, 10, C.featherD);
};
const gMark = (im) => {
  im.rect(6, 6, 4, 1, C.eyeW); im.rect(5, 7, 6, 1, C.eyeW); im.rect(6, 8, 4, 1, C.eyeW);
  im.set(7, 7, C.blood); im.set(8, 7, C.bloodD);
  im.set(6, 6, mixC(C.eyeW, C.skinDD, .4)); im.set(9, 8, mixC(C.eyeW, C.skinDD, .4));
  for (const [x, y] of [[7, 3], [8, 3], [7, 12], [8, 12], [2, 7], [3, 7], [12, 7], [13, 7]]) im.set(x, y, C.gold);
  for (const [x, y] of [[2, 7], [13, 7]]) im.set(x, y, C.goldL);
};
const gRain = (im) => {
  im.rect(6, 3, 4, 1, C.cloudL); im.rect(4, 4, 8, 1, C.cloud); im.rect(3, 5, 10, 1, C.cloud); im.rect(3, 6, 10, 1, C.cloudD);
  for (const [sx, ty] of [[5, 10], [8, 11], [11, 10]]) {
    im.set(sx, 8, C.featherD); im.set(sx, 9, C.steelD); im.set(sx, ty, C.steel);
  }
  im.set(8, 10, C.steelD);
};
const gFirebolt = (im) => {
  im.set(10, 1, C.fireDD); im.set(9, 2, C.fireD); im.set(8, 3, C.fireD);
  const drop = [[7, 9, 4], [6, 10, 5], [6, 10, 6], [5, 10, 7], [5, 10, 8], [5, 10, 9], [6, 10, 10], [7, 9, 11]];
  for (const [x0, x1, y] of drop) {
    im.rect(x0, y, x1 - x0 + 1, 1, C.fire);
    im.set(x0, y, C.fireDD); im.set(x1, y, C.fireDD);
  }
  im.rect(7, 7, 3, 2, C.fireL); im.set(8, 6, C.fireXL); im.set(6, 8, C.fireD);
};
const gFrostNova = (im) => {
  const sp = [];
  for (let y = 3; y <= 6; y++) sp.push([7, y], [8, y]);
  for (let y = 9; y <= 12; y++) sp.push([7, y], [8, y]);
  for (const [x, y] of [[9, 5], [10, 4], [11, 3], [6, 5], [5, 4], [4, 3], [9, 10], [10, 11], [11, 12], [6, 10], [5, 11], [4, 12]]) sp.push([x, y]);
  for (const [x, y] of sp) im.set(x, y, C.ice);
  im.rect(7, 7, 2, 2, C.iceXL);
  for (const [x, y] of [[7, 3], [8, 3], [7, 12], [8, 12], [11, 3], [4, 3], [11, 12], [4, 12]]) im.set(x, y, C.iceL);
  for (const [x, y] of [[8, 5], [6, 9]]) im.set(x, y, C.iceDD);
};
const gSiphon = (im) => {
  im.set(5, 3, C.blood); im.rect(4, 4, 3, 2, C.blood); im.set(5, 6, C.blood); im.set(4, 4, C.bloodL);
  im.rect(6, 8, 3, 1, C.blood); im.set(7, 7, C.blood); im.set(7, 9, C.blood); im.set(8, 8, C.bloodL);
  for (const [x, y] of [[9, 6], [10, 6], [12, 6], [13, 6], [8, 7], [14, 7], [9, 9], [13, 9], [10, 10], [12, 10], [11, 11]]) im.set(x, y, C.bloodD);
};
const gFirestorm = (im) => {
  const rows = [[2, 4, 11], [3, 4, 12], [4, 3, 11], [5, 4, 11], [6, 4, 10], [7, 5, 11], [8, 5, 10], [9, 6, 10], [10, 6, 9], [11, 6, 9], [12, 7, 8]];
  for (const [y, x0, x1] of rows) for (let x = x0; x <= x1; x++) {
    const e = (x === x0 || x === x1 || y === 12) ? C.fireDD
      : nz(x, y, 5, 9, 3, 4) === 0 ? C.fireD
      : nz(x, y, 7, 13, 5, 4) < 1 ? C.fireL : C.fire;
    im.set(x, y, e);
  }
  im.set(12, 1, C.fireL); im.set(3, 1, C.fireD); im.set(2, 4, C.fireDD);
};
function genSkillIcons() {
  const s = new Img(192, 16);
  const glyphs = [gPowerStrike, gWhirlwind, gSecondWind, gExecute, gPierce, gVolley,
                  gMark, gRain, gFirebolt, gFrostNova, gSiphon, gFirestorm];
  glyphs.forEach((g, i) => { const im = iconBase(); g(im); autoOutline(im); bevel(im); s.blit(im, i * 16); });
  s.save('skill_icons.png');
}

// ===========================================================================
// projectiles.png 64x16: 0 стрела, 1 огненный шар, 2 ледяной осколок,
// 3 призрачная стрела (полупрозрачная, бирюзоватая)
// ===========================================================================
function genProjectiles() {
  const s = new Img(64, 16);
  const arrow = (ox, a, shaft, head, headL, feather, featherD) => {
    s.rect(ox + 4, 8, 8, 1, shaft);
    s.set(ox + 12, 7, head); s.set(ox + 12, 8, headL); s.set(ox + 12, 9, head); s.set(ox + 13, 8, headL);
    s.set(ox + 2, 7, feather); s.set(ox + 3, 7, feather); s.set(ox + 2, 9, feather); s.set(ox + 3, 9, featherD);
    s.set(ox + 2, 8, a);
  };
  arrow(0, C.bloodD, C.arrowShaft, C.steel, C.steelL, C.featherW, C.featherD);
  // 1 — огненный шар: уголёк с горячим ядром и гаснущим хвостом
  const ball = [[9, 11, 4], [8, 13, 5], [8, 13, 6], [8, 13, 7], [8, 13, 8], [8, 13, 9], [9, 11, 10]];
  for (const [x0, x1, y] of ball) {
    s.rect(16 + x0, y, x1 - x0 + 1, 1, C.fire);
    s.set(16 + x0, y, C.fireDD); s.set(16 + x1, y, C.fireDD);
  }
  s.rect(25, 6, 3, 3, C.fireL); s.set(26, 7, C.fireXL);
  s.rect(24, 7, 1, 1, C.fire);
  s.set(22, 7, C.fireD); s.set(22, 8, C.fireD); s.set(21, 9, C.fireD);
  s.set(20, 8, C.fireDD); s.set(19, 7, C.fireDD); s.set(18, 8, C.fireDD);
  s.set(21, 5, C.fireL);
  // 2 — ледяной осколок: ромб с гранями
  const dia = [[8, 8, 4], [7, 9, 5], [6, 10, 6], [5, 11, 7], [5, 11, 8], [6, 10, 9], [7, 9, 10], [8, 8, 11]];
  for (const [x0, x1, y] of dia) s.rect(32 + x0, y, x1 - x0 + 1, 1, C.ice);
  for (const [x, y] of [[8, 4], [9, 5], [10, 6], [11, 7], [11, 8], [10, 9], [9, 10], [8, 11]]) s.set(32 + x, y, C.iceD);
  for (const [x, y] of [[7, 5], [6, 6], [6, 7], [7, 6]]) s.set(32 + x, y, C.iceL);
  s.set(39, 7, C.iceXL); s.set(40, 8, C.iceXL);
  s.set(37, 9, C.iceDD); s.set(38, 10, C.iceDD);
  // 3 — призрачная стрела (полупрозрачная, холодный бирюзовый призрак)
  arrow(48, [190, 238, 226, 150], [150, 220, 208, 120], [150, 220, 208, 120], [222, 248, 240, 160], [205, 240, 232, 110], [150, 200, 190, 100]);
  s.save('projectiles.png');
}

// ===========================================================================
// Курсоры 16x16: читаемые силуэты с белой контрастной обводкой (горячая
// точка — центр (8,8), как задаёт world.gd hot spot (8,8))
// ===========================================================================
function whiteEdge(f) {
  const occ = (x, y) => x >= 0 && y >= 0 && x < f.w && y < f.h && f.d[(y * f.w + x) * 4 + 3] !== 0;
  const add = [];
  for (let y = 0; y < f.h; y++) for (let x = 0; x < f.w; x++)
    if (!occ(x, y) && (occ(x - 1, y) || occ(x + 1, y) || occ(x, y - 1) || occ(x, y + 1))) add.push([x, y]);
  for (const [x, y] of add) f.set(x, y, C.curW);
}
function genCursors() {
  let im = new Img(16, 16);                 // «идти»: янтарное кольцо + засечки сторон + точка
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const d2 = (x - 7.5) ** 2 + (y - 7.5) ** 2;
    if (d2 >= 12 && d2 <= 26) im.set(x, y, (x + y) % 2 ? C.curY : C.curYL);
  }
  for (const [x, y] of [[7, 0], [8, 0], [7, 15], [8, 15], [0, 7], [0, 8], [15, 7], [15, 8]]) im.set(x, y, C.curY);
  im.rect(7, 7, 2, 2, C.curY); im.set(7, 7, C.curYL);
  whiteEdge(im);
  im.save('cursor_move.png');
  im = new Img(16, 16);                     // «атака»: красное прицельное кольцо + крест + точка
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const d2 = (x - 7.5) ** 2 + (y - 7.5) ** 2;
    if (d2 >= 26 && d2 <= 42) im.set(x, y, C.curR);
  }
  for (const [x, y] of [[7, 3], [8, 3], [7, 12], [8, 12], [3, 7], [3, 8], [12, 7], [12, 8]]) im.set(x, y, C.curR);
  for (const [x, y] of [[7, 4], [8, 4], [7, 11], [8, 11], [4, 7], [4, 8], [11, 7], [11, 8]]) im.set(x, y, C.curRL);
  im.rect(7, 7, 2, 2, C.curRL);
  whiteEdge(im);
  im.save('cursor_enemy.png');
}

// ===========================================================================
// decor.png — 128x16, 8 слотов 16x16 (по atmosphere.gd):
// 0 куст+ягоды, 1 папоротник, 2 кленовый лист, 3 поганка, 4 пенёк,
// 5 камыш, 6 рогоз, 7 камни. Прозрачный фон.
// ===========================================================================
function genDecor() {
  const s = new Img(128, 16);
  let f = new Img(16, 16);
  // 0 — куст: тёмный купол с ягодами
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const dx = x - 7.5, dy = (y - 10.6) * 1.18;
    if (dx * dx + dy * dy > 33) continue;
    let c = C.leaf;
    if (nz(x, y, 5, 11, 3, 13) < 4) c = C.leafL;
    if (nz(x, y, 7, 3, 8, 15) < 4) c = C.leafD;
    if (dx < -2 && dy < 2 && nz(x, y, 3, 3, 1, 9) < 3) c = C.leafXL;
    if (y >= 12 && nz(x, y, 9, 13, 2, 7) < 3) c = C.leafDD;
    f.set(x, y, c);
  }
  for (const [x, y] of [[4, 9], [10, 7], [12, 11], [6, 13], [9, 10]]) { f.set(x, y, C.decoBerry); f.set(x, y - 1, C.decoBerryL); }
  outlineAA(f, { skipDown: true });
  s.blit(f, 0);
  // 1 — папоротник
  f = new Img(16, 16);
  const frond = (pts, tone, leaflets) => {
    pts.forEach(([x, y], i) => {
      f.set(x, y, i >= pts.length - 2 ? C.leafXL : tone);
      if (leaflets && i > 1 && i < pts.length - 3 && i % 2 === 0) f.set(x - 1, y, C.leafDD);
    });
  };
  frond([[5, 15], [5, 14], [4, 13], [4, 12], [3, 11], [3, 10], [2, 9], [2, 8], [2, 7], [2, 6]], C.leafD, true);
  frond([[8, 15], [8, 14], [8, 13], [7, 12], [7, 11], [7, 10], [7, 9], [7, 8], [7, 7], [8, 6], [8, 5]], C.leaf, true);
  frond([[11, 15], [11, 14], [12, 13], [12, 12], [12, 11], [13, 10], [13, 9], [13, 8], [14, 7]], C.leafL, false);
  outlineAA(f, { skipDown: true });
  s.blit(f, 16);
  // 2 — опавший кленовый лист
  f = new Img(16, 16);
  const mp = (pts, c) => { for (const [x, y] of pts) f.set(x, y, c); };
  mp([[8, 8], [7, 9], [9, 9], [7, 10], [9, 10], [7, 11], [9, 11]], C.maple);
  f.set(8, 8, C.mapleDD);
  f.set(8, 9, C.mapleD); f.set(8, 10, C.mapleD); f.set(8, 11, C.mapleD);
  mp([[6, 10], [10, 10], [5, 11], [11, 11]], C.mapleD);
  mp([[7, 12], [8, 12], [9, 12]], C.mapleD);
  mp([[8, 13], [8, 14]], C.mapleDD);
  mp([[7, 14], [9, 14]], C.grassSh);
  outlineAA(f, { skipDown: true, aaOnly: true });
  s.blit(f, 32);
  // 3 — поганка: приглушённо-красная шляпка, cream точки
  f = new Img(16, 16);
  f.rect(7, 8, 2, 8, C.mushStem);
  for (let y = 10; y <= 15; y++) f.set(8, y, C.mushStemD);
  f.set(6, 15, C.mushStem); f.set(9, 15, C.mushStemD);
  f.rect(7, 4, 3, 1, C.mushCap); f.rect(6, 5, 5, 1, C.mushCap); f.rect(5, 6, 7, 1, C.mushCap);
  f.rect(5, 7, 7, 1, C.mushCapD);
  f.set(5, 6, C.mushCapD); f.set(11, 6, C.mushCapD);
  f.set(7, 5, C.mushDot); f.set(9, 6, C.mushDot); f.set(6, 6, mixC(C.mushCap, C.mushDot, .5));
  f.set(6, 4, mixC(C.mushCap, C.leafDD, .3));
  outlineAA(f, { skipDown: true });
  s.blit(f, 48);
  // 4 — пенёк: кольца, трещины коры, мох
  f = new Img(16, 16);
  f.rect(3, 10, 10, 6, C.trunk);
  for (let y = 10; y <= 15; y++) { f.set(3, y, C.trunkL); f.set(12, y, cool(C.trunk, .55)); }
  for (const [x, y] of [[6, 11], [6, 12], [9, 13], [9, 14], [5, 14]]) f.set(x, y, C.trunkDD);
  for (const [x, y] of [[4, 10], [7, 10], [10, 11]]) f.set(x, y, C.trunkXL);
  f.rect(6, 6, 4, 1, C.woodRingL); f.rect(5, 7, 6, 1, C.woodRing);
  f.rect(4, 8, 8, 1, C.woodRing); f.rect(3, 9, 10, 1, C.woodRing);
  for (const [x, y] of [[7, 6], [8, 6], [6, 7], [9, 7], [5, 8], [10, 8], [6, 9], [9, 9]]) f.set(x, y, C.woodRingD);
  for (const [x, y] of [[7, 7], [8, 7], [6, 8], [9, 8], [7, 9], [8, 9]]) f.set(x, y, C.woodRingD);
  for (const [x, y] of [[7, 8], [8, 8]]) f.set(x, y, mixC(C.woodRing, C.woodRingL, .6));
  f.set(5, 6, C.mossD); f.set(4, 7, C.moss); f.set(3, 8, C.mossD); f.set(11, 7, C.mossD);   // мох на срезе
  outlineAA(f, { skipDown: true });
  s.blit(f, 64);
  // 5 — камыш
  f = new Img(16, 16);
  const rl = [[[3, 15], [3, 14], [2, 13], [2, 12], [2, 11], [2, 10], [1, 9]],
              [[6, 15], [6, 14], [6, 13], [5, 12], [5, 11], [5, 10], [5, 9], [5, 8], [4, 7]],
              [[9, 15], [9, 14], [9, 13], [9, 12], [10, 11], [10, 10], [10, 9], [10, 8], [11, 7]],
              [[12, 15], [12, 14], [13, 13], [13, 12], [13, 11], [14, 10], [14, 9]]];
  rl.forEach((p, i) => p.forEach(([x, y], k) => f.set(x, y, k === p.length - 1 ? C.reedTip : (i % 2 ? C.reedD : C.reed))));
  f.set(4, 6, C.spikeB); f.set(4, 5, C.spikeB); f.set(4, 4, C.reedTip);
  f.set(11, 6, C.spikeB); f.set(11, 5, mixC(C.spikeB, C.trunkDD, .4)); f.set(11, 4, C.reedTip);
  outlineAA(f, { skipDown: true });
  s.blit(f, 80);
  // 6 — цветущие колоски (приглушённая сирень)
  f = new Img(16, 16);
  for (let y = 7; y <= 15; y++) f.set(6, y, C.reed);
  for (let y = 9; y <= 15; y++) f.set(10, y, C.reedD);
  for (const [x, y] of [[5, 12], [7, 10], [5, 8]]) f.set(x, y, C.reedD);
  for (const [x, y] of [[11, 13], [9, 11]]) f.set(x, y, C.reed);
  for (let y = 2; y <= 6; y++) f.set(6, y, y % 2 ? C.spikePL : C.spikeP);
  f.set(6, 1, C.spikePL); f.set(6, 4, C.spikePD);
  for (let y = 5; y <= 8; y++) f.set(10, y, y % 2 ? C.spikeP : C.spikePD);
  f.set(10, 4, C.spikePL);
  outlineAA(f, { skipDown: true });
  s.blit(f, 96);
  // 7 — кучка камней: сланец, ржавые вкрапления
  f = new Img(16, 16);
  const stone = (rows) => {
    rows.forEach(([x0, x1, y], i) => {
      const c = i === 0 ? C.rockL : i >= rows.length - 1 ? C.rockD : C.rock;
      f.rect(x0, y, x1 - x0 + 1, 1, c);
    });
  };
  stone([[3, 5, 12], [2, 6, 13], [2, 6, 14], [2, 6, 15]]);
  stone([[8, 9, 11], [7, 10, 12], [7, 10, 13], [7, 10, 14], [7, 10, 15]]);
  stone([[12, 13, 13], [12, 14, 14], [12, 14, 15]]);
  f.set(2, 13, C.rock); f.set(7, 12, C.rockXL); f.set(12, 14, mixC(C.rock, C.rockL, .5));
  f.set(4, 13, C.rustD); f.set(9, 13, C.rustD);                                   // ржавые вкрапления
  outlineAA(f, { skipDown: true });
  s.blit(f, 112);
  s.save('decor.png');
}

// ===========================================================================
// shadow.png 32x16 — тень героя Rect(0,0,16,8), тень босса Rect(8,7,24,9):
// мягкие эллипсы, ступенчатый alpha, чуть смещены вправо (свет сверху-слева)
// ===========================================================================
function genShadow() {
  const s = new Img(32, 16);
  const ell = (cx, cy, rx, ry, core) => {
    for (let y = 0; y < 16; y++) for (let x = 0; x < 32; x++) {
      const dx = (x + .5 - cx) / rx, dy = (y + .5 - cy) / ry;
      const d = dx * dx + dy * dy;
      if (d <= .5) s.set(x, y, [8, 8, 14, core]);
      else if (d <= .72) s.set(x, y, [8, 8, 14, core - 18]);
      else if (d <= .9) s.set(x, y, [8, 8, 14, core - 38]);
      else if (d <= 1) s.set(x, y, [8, 8, 14, core - 60]);
      else if (d <= 1.26) s.set(x, y, [8, 8, 14, 16]);
    }
  };
  ell(8.5, 3.5, 6, 2.5, 96);
  ell(20.5, 11.5, 11.5, 4, 110);
  s.save('shadow.png');
}

// ---------- запуск ----------
genTiles();
genAnimTiles();
genDungeonTiles();
genAllCharacters();
genSlime();
genBrute();
genPortraits();
genKey();
genHeart();
genSkillIcons();
genProjectiles();
genCursors();
genDecor();
genShadow();

console.log('--- verification v3 ---');
for (const [name, w, h] of [['dungeon_tiles.png', 256, 16], ['brute.png', 64, 32],
                            ['npc_hermit.png', 16, 16], ['portraits2.png', 120, 40], ['key.png', 16, 16],
                            ['class_warrior.png', 48, 64], ['class_archer.png', 48, 64], ['class_mage.png', 48, 64],
                            ['skill_icons.png', 192, 16], ['projectiles.png', 64, 16],
                            ['cursor_move.png', 16, 16], ['cursor_enemy.png', 16, 16],
                            ['tiles.png', 256, 16], ['slime.png', 32, 16],
                            ['npc_elder.png', 16, 16], ['npc_merchant.png', 16, 16], ['npc_farmer.png', 16, 16],
                            ['portraits.png', 120, 40], ['heart.png', 7, 6],
                            ['decor.png', 128, 16], ['anim_tiles.png', 128, 16], ['shadow.png', 32, 16],
                            ['player.png', 48, 64]]) {
  const b = fs.readFileSync(path.join(OUT, name));
  const sig = [...b.slice(0, 8)].map(v => v.toString(16).padStart(2, '0').toUpperCase()).join(' ');
  const ihdrW = b.readUInt32BE(16), ihdrH = b.readUInt32BE(20);
  const ok = ihdrW === w && ihdrH === h && sig === '89 50 4E 47 0D 0A 1A 0A';
  console.log(name, ihdrW + 'x' + ihdrH, ok ? 'OK' : 'FAIL');
}
console.log('DONE v3');
