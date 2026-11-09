// Генератор ассетов зоны «Пещера осквернения» — «Тени Северного Леса»
// Чистый Node.js (zlib), без внешних зависимостей. PNG-энкодер скопирован из gen_assets.js.
// Результат: pixel-rpg/assets/{dungeon_tiles,brute,npc_hermit,portraits2,key}.png
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

// ---------- Палитра (база из gen_assets.js + расширение для пещеры) ----------
const C = {
  skin: [240, 180, 140], skinD: [214, 152, 116],
  eye: [40, 30, 45], mouth: [170, 90, 80],
  hairP: [120, 70, 40], hairD: [70, 45, 30], gray: [205, 205, 210], grayD: [160, 160, 168],
  tunic: [60, 110, 200], tunicD: [44, 82, 160],
  robe: [130, 95, 160], robeD: [100, 70, 128],
  wood: [142, 96, 56], woodD: [106, 70, 40], gold: [236, 196, 80],
  rock: [152, 152, 162], rockD: [112, 112, 122], rockL: [182, 182, 190],
  // --- пещера осквернения ---
  floor: [70, 70, 80], floorD: [56, 56, 68], floorL: [84, 84, 96], floorS: [44, 44, 54],
  brick: [54, 54, 64], brickL: [64, 64, 76], brickTop: [92, 92, 104], mortar: [34, 34, 44],
  crackG: [120, 200, 110], crackD: [88, 150, 84], crackL: [165, 230, 150], crackTint: [78, 96, 82],
  rust: [172, 118, 52], rustD: [122, 80, 36], rustL: [214, 158, 74],
  dark: [13, 13, 17], darkL: [22, 24, 28],
  step: [78, 78, 90], stepL: [128, 128, 142], stepD: [46, 46, 56],
  stone: [78, 78, 90], stoneXL: [118, 118, 132], stoneL: [96, 96, 108], stoneD: [50, 50, 62],
  rg: [128, 128, 138], rgD: [92, 92, 104], rgL: [158, 158, 168],
  bone: [220, 215, 200], boneD: [168, 163, 150], boneEye: [60, 62, 70],
  mCap: [120, 215, 95], mCapD: [58, 130, 62], mStem: [225, 220, 205], mStemD: [190, 185, 170],
  spore: [200, 240, 160],
  glowG: [110, 200, 110], glowL: [180, 245, 160], mossStone: [92, 116, 96],
  woodC: [90, 60, 40], woodCD: [62, 40, 26], woodCL: [112, 78, 52], woodIn: [46, 30, 20],
  bandG: [82, 134, 88], bandGD: [54, 92, 62], bandGL: [108, 164, 112],
  lockG: [210, 170, 80], lockGD: [150, 110, 40],
  leverStick: [120, 84, 48], leverStickD: [88, 60, 34], iron: [130, 130, 140], ironD: [86, 86, 96],
  voidB: [10, 10, 12], voidG: [18, 30, 20], voidG2: [24, 42, 26],
  brute: [60, 140, 70], bruteD: [45, 105, 52], bruteL: [95, 175, 95], bruteXL: [140, 210, 130],
  bruteSpot: [150, 235, 100], rot: [38, 90, 46], bruteBrow: [28, 62, 36], bruteMouth: [30, 45, 34],
  wWhite: [228, 228, 228],
  hermSkin: [235, 210, 185], hermSkinD: [208, 182, 158],
  hermRobe: [100, 80, 60], hermRobeD: [76, 60, 44],
  keyDark: [74, 54, 18], keyL: [252, 224, 140],
  monSkin: [70, 150, 80], monSkinD: [52, 122, 62], monSkinDD: [48, 112, 58], monOut: [30, 75, 40],
  monBrow: [22, 55, 30], monMouth: [38, 26, 32], tooth: [235, 232, 220],
};

// детерминированный шум: ((x*a + y*b + c) % N), без Math.random
function nz(x, y, a, b, c, n) {
  let v = (x * a + y * b + c) % 9973;
  v = (v * 13 + 7) % 65521;
  return v % n;
}

// ---------- Тайлы подземелья 16x16, лист 256x16 ----------
// Индексы: 0 floor, 1 crack, 2 wall, 3 locked, 4 open, 5 stairs, 6 pillar, 7 rubble,
//          8 bones, 9 mushroom, 10 altar, 11 chest, 12 chest open, 13 lever dn, 14 lever up, 15 void
function floorBase(t) {
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c = C.floor;
    if (nz(x, y, 7, 11, 5, 19) < 2) c = C.floorL;
    if (nz(x, y, 7, 11, 17, 17) < 2) c = C.floorD;
    if (nz(x, y, 7, 11, 3, 31) === 0) c = C.floorS;
    // рваные швы каменных плит (шум вдоль линий сетки 8px)
    if ((y % 8 === 7 && x % 8 !== 7 && nz(x, y, 3, 13, 1, 3) === 0) ||
        (x % 8 === 7 && y % 8 !== 7 && nz(x, y, 13, 3, 2, 3) === 0)) c = C.floorD;
    t.set(x, y, c);
  }
}
function brickBase(t) {
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const band = Math.floor(y / 4);
    let c = nz(x, y, 3, 7, 2, 17) < 3 ? C.brickL : C.brick;
    if (y % 4 === 0) c = C.mortar;
    if ((x + (band % 2) * 4) % 8 === 0 && y % 4 !== 0) c = C.mortar;
    t.set(x, y, c);
  }
  t.rect(0, 0, 16, 1, C.brickTop);   // верхняя кромка светлее — объём
  t.rect(0, 1, 16, 1, C.stoneL);
  t.rect(0, 15, 16, 1, C.mortar);    // низ темнее
}
function genDungeonTiles() {
  const s = new Img(256, 16);
  const put = () => new Img(16, 16);
  // 0 stone_floor — каменный пол с шумом щелей
  let t = put(); floorBase(t); s.blit(t, 0);
  // 1 floor_crack — зелёная гнилостная трещина
  t = put(); floorBase(t);
  const cOff = [1, 0, 0, 1, 2, 2, 1, 1, 0, -1, -1, 0, 0, 1, 1, 0];
  for (let y = 0; y < 16; y++) {
    const cx = 8 + cOff[y];
    t.set(cx, y, y < 2 || y > 13 ? C.crackL : C.crackG);
    if (nz(cx, y, 19, 29, 9, 3) < 2) t.set(cx - 1, y, C.crackD);
    if (nz(cx, y, 19, 29, 21, 3) < 2) t.set(cx + 1, y, C.crackD);
    if (nz(cx + 2, y, 19, 29, 13, 4) === 0) t.set(cx + 2, y, C.crackTint);
    if (nz(cx - 2, y, 19, 29, 11, 4) === 0) t.set(cx - 2, y, C.crackTint);
  }
  t.set(10, 4, C.crackG); t.set(11, 5, C.crackG); t.set(12, 5, C.crackD); // отводок
  t.set(6, 11, C.crackG); t.set(5, 12, C.crackD);                          // отводок
  s.blit(t, 16);
  // 2 stone_wall — кирпич темнее пола, светлая верхняя кромка
  t = put(); brickBase(t); s.blit(t, 32);
  // 3 door_locked — стена с ржаво-золотой замочной скважиной
  t = put(); brickBase(t);
  t.rect(5, 4, 6, 9, C.rust); t.frame(5, 4, 6, 9, C.rustD);
  t.set(6, 5, C.rustL); t.set(7, 5, C.rustL); t.set(6, 6, C.rustL);       // блик пластины
  t.set(9, 11, C.rustD); t.set(10, 11, C.rustD); t.set(10, 10, C.rustD);  // тень
  t.rect(7, 6, 2, 2, C.dark);                                            // скважина: круг
  t.rect(7, 8, 2, 3, C.dark);                                            // скважина: щель
  s.blit(t, 48);
  // 4 door_open — тёмный проём с каменной арматурой по краям
  t = put(); brickBase(t);
  t.rect(3, 1, 10, 1, C.dark); t.rect(2, 2, 12, 1, C.dark); t.rect(1, 3, 14, 13, C.dark);
  for (let y = 4; y < 16; y++) for (let x = 2; x < 14; x++)
    if (nz(x, y, 23, 17, 5, 7) === 0) t.set(x, y, C.darkL);              // едва тёплые отблески
  t.rect(1, 3, 1, 13, C.stone); t.rect(14, 3, 1, 13, C.stone);           // арматура
  t.rect(0, 3, 1, 13, C.stoneD); t.rect(15, 3, 1, 13, C.stoneD);
  t.rect(2, 2, 12, 1, C.stoneXL);                                        // светлая верхняя дуга
  t.set(1, 3, C.stoneXL); t.set(14, 3, C.stoneXL);
  s.blit(t, 64);
  // 5 stairs_out — каменные ступени «лесенка вверх»
  t = put();
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c = nz(x, y, 3, 7, 2, 17) < 3 ? C.stoneL : C.step;
    if (y % 4 === 0) c = C.stepL;      // светлая бровка ступени
    if (y % 4 === 3) c = C.stepD;      // тень под ступенью
    t.set(x, y, c);
  }
  t.rect(0, 0, 3, 2, C.floorS); t.rect(13, 0, 3, 2, C.floorS);           // уход в стену вверху
  s.blit(t, 80);
  // 6 pillar — колонна: блик слева, тень справа
  t = put();
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++)
    t.set(x, y, nz(x, y, 13, 29, 3, 13) < 2 ? C.floorS : C.floorD);
  t.rect(3, 0, 10, 2, C.stoneL); t.rect(3, 1, 10, 1, C.stone);           // капитель
  t.set(3, 0, C.stoneXL); t.set(12, 1, C.stoneD);
  for (let y = 2; y < 13; y++) for (let x = 5; x < 11; x++) {
    let c = C.stone;
    if (nz(x, y, 11, 17, 4, 29) === 0) c = C.stoneD;                     // трещинки
    t.set(x, y, c);
  }
  t.rect(5, 2, 1, 11, C.stoneXL);                                        // блик слева
  t.rect(10, 2, 1, 11, C.stoneD);                                        // тень справа
  t.rect(3, 13, 10, 3, C.stoneL); t.rect(3, 15, 10, 1, C.stoneD);        // база
  t.set(3, 13, C.stoneXL); t.set(12, 14, C.stoneD);
  s.blit(t, 96);
  // 7 rubble — пол + обломки камней (серее rock-а)
  t = put(); floorBase(t);
  const lump = (x, y, w, h) => {
    t.rect(x, y, w, h, C.rg); t.rect(x + 1, y - 1, w - 2, 1, C.rg);
    t.set(x, y, C.rgD); t.set(x + 1, y - 1, C.rgL); t.set(x + 2, y - 1, C.rgL);
    t.rect(x, y + h - 1, w, 1, C.rgD); t.set(x + w - 1, y, C.rgD);
  };
  lump(3, 9, 5, 4); lump(9, 6, 5, 4); lump(11, 12, 3, 2); lump(2, 4, 3, 2);
  t.set(7, 5, C.rgD); t.set(8, 11, C.rgD); t.set(14, 9, C.rgL);          // щебень
  s.blit(t, 112);
  // 8 bones — череп + кости
  t = put(); floorBase(t);
  t.rect(5, 3, 5, 3, C.bone);                                            // череп
  t.rect(6, 6, 3, 1, C.bone);                                            // челюсть
  t.set(6, 5, C.boneEye); t.set(8, 5, C.boneEye);                        // глазницы
  t.set(7, 7, C.boneD); t.set(7, 3, C.boneD);                            // трещина/тень
  t.rect(2, 11, 5, 1, C.bone); t.set(2, 10, C.bone); t.set(3, 10, C.bone);
  t.set(5, 12, C.bone); t.set(6, 12, C.bone);                            // кость с головками
  t.set(10, 10, C.bone); t.set(11, 11, C.bone); t.set(12, 12, C.bone);   // ребро
  t.set(13, 8, C.boneD);
  s.blit(t, 128);
  // 9 mushroom — гнилушечный гриб
  t = put(); floorBase(t);
  t.rect(7, 9, 2, 5, C.mStem); t.rect(8, 10, 1, 4, C.mStemD);            // ножка
  t.rect(6, 6, 4, 1, C.mCap); t.rect(5, 7, 6, 1, C.mCap); t.rect(4, 8, 8, 1, C.mCap);
  t.rect(4, 9, 8, 1, C.mCapD);                                           // пластинки снизу
  t.set(4, 8, C.mCapD); t.set(11, 8, C.mCapD);                           // тёмные края
  t.set(6, 7, C.mCapD); t.set(9, 8, C.mCapD);                            // тёмные пятна
  t.set(8, 6, C.spore); t.set(5, 6, C.mCapD);
  for (const [x, y] of [[3, 4], [12, 4], [5, 2], [12, 10], [2, 9], [13, 6]]) t.set(x, y, C.spore);
  t.rect(12, 13, 1, 2, C.mStem); t.rect(11, 12, 3, 1, C.mCap); t.set(11, 12, C.mCapD); // малыш
  s.blit(t, 144);
  // 10 altar — алтарь со свечением
  t = put(); floorBase(t);
  t.rect(3, 11, 10, 4, C.stone); t.rect(3, 14, 10, 1, C.stoneD);         // нижняя ступень
  t.rect(5, 8, 6, 3, C.stoneL); t.rect(10, 8, 1, 3, C.stoneD);
  t.rect(4, 6, 8, 2, C.stoneXL); t.rect(4, 7, 8, 1, C.stoneL);           // плита
  t.rect(6, 6, 4, 1, C.mossStone);                                       // зелёная подсветка плиты
  t.rect(7, 3, 2, 2, C.glowL); t.rect(6, 3, 1, 2, C.glowG); t.rect(9, 3, 1, 2, C.glowG);
  t.set(7, 2, C.glowG); t.set(8, 2, C.glowG);                            // ядро свечения
  t.set(6, 2, C.crackD); t.set(9, 2, C.crackD); t.set(5, 4, C.crackD); t.set(10, 4, C.crackD);
  t.set(4, 2, C.glowG); t.set(11, 1, C.glowG); t.set(6, 0, C.crackD); t.set(9, 0, C.crackD); // споры
  s.blit(t, 160);
  // 11 chest_big_closed — большой сундук, зелёные кованые полосы
  t = put(); floorBase(t);
  t.rect(2, 5, 12, 3, C.woodC); t.rect(3, 5, 10, 1, C.woodCL);           // крышка
  t.rect(2, 7, 12, 1, C.woodCD);
  t.rect(2, 8, 12, 7, C.woodC); t.frame(2, 8, 12, 7, C.woodCD);          // корпус
  t.rect(2, 14, 12, 1, C.woodCD);
  for (let y = 5; y < 15; y++) { t.set(3, y, C.bandG); t.set(12, y, C.bandGD); }
  t.rect(2, 8, 12, 1, C.bandG); t.rect(2, 9, 12, 1, C.bandGD);           // пояс ковки
  t.set(3, 5, C.bandGL); t.set(2, 8, C.bandGL); t.set(12, 8, C.bandGD);
  t.rect(7, 7, 2, 4, C.lockG); t.frame(7, 7, 2, 4, C.lockGD);            // замок
  t.set(7, 9, C.woodCD); t.set(8, 9, C.woodCD);
  s.blit(t, 176);
  // 12 chest_big_open — крышка открыта, зелёное свечение внутри
  t = put(); floorBase(t);
  t.rect(2, 1, 12, 3, C.woodC); t.frame(2, 1, 12, 3, C.woodCD);          // поднятая крышка
  t.rect(2, 3, 12, 1, C.woodCD);
  t.rect(3, 4, 10, 1, C.bandGD);
  for (let y = 1; y < 4; y++) { t.set(3, y, C.bandG); t.set(12, y, C.bandGD); }
  t.rect(3, 5, 10, 3, C.woodIn);                                         // нутро
  t.rect(4, 6, 8, 2, C.glowG); t.rect(6, 6, 4, 2, C.glowL);              // свечение
  t.set(5, 5, C.glowG); t.set(10, 5, C.glowG); t.set(7, 5, C.glowL); t.set(8, 5, C.glowL);
  t.rect(2, 8, 12, 7, C.woodC); t.frame(2, 8, 12, 7, C.woodCD);          // передняя стенка
  t.rect(2, 14, 12, 1, C.woodCD);
  for (let y = 8; y < 15; y++) { t.set(3, y, C.bandG); t.set(12, y, C.bandGD); }
  t.rect(2, 8, 12, 1, C.bandG);
  t.set(3, 8, C.bandGL); t.set(2, 8, C.bandGL);
  s.blit(t, 192);
  // 13 lever_down / 14 lever_up — рычаг на постаменте
  const lever = (up) => {
    const v = put(); floorBase(v);
    v.rect(5, 11, 6, 4, C.stone); v.rect(5, 14, 6, 1, C.stoneD);         // постамент
    v.rect(6, 10, 4, 1, C.stoneXL); v.set(10, 12, C.stoneD);
    v.rect(7, 9, 2, 2, C.iron); v.set(7, 9, C.rockL);                    // кронштейн-ось
    if (up) {
      for (const [x, y] of [[9, 8], [10, 7], [11, 6], [12, 5]]) { v.set(x, y, C.leverStick); v.set(x, y + 1, C.leverStickD); }
      v.rect(12, 3, 2, 2, C.iron); v.set(12, 3, C.rockL);                // рукоять
      v.set(8, 9, C.ironD);
    } else {
      for (const [x, y] of [[9, 10], [10, 11], [11, 12], [11, 13]]) { v.set(x, y, C.leverStick); v.set(x - 1, y, C.leverStickD); }
      v.rect(11, 12, 2, 2, C.iron); v.set(11, 12, C.rockL);
      v.set(8, 10, C.ironD);
    }
    return v;
  };
  s.blit(lever(false), 13 * 16);
  s.blit(lever(true), 14 * 16);
  // 15 void_black — почти чёрный, едва различимая гниль
  t = put();
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c = C.voidB;
    const v = nz(x, y, 13, 29, 7, 31);
    if (v < 4) c = C.voidG;
    if (v === 0 && nz(x, y, 31, 41, 11, 7) < 2) c = C.voidG2;
    t.set(x, y, c);
  }
  s.blit(t, 15 * 16);
  s.save('dungeon_tiles.png');
}

// ---------- Персонаж 16x16 (скелет позы из drawChar образца) ----------
// dirs: 0=down 1=left 2=right 3=up ; step: 0=idle,1,2=шаг
function drawChar(opts, dir, step) {
  const f = new Img(16, 16);
  const hair = opts.hair, tunic = opts.tunic, tunicD = opts.tunicD;
  const skin = opts.skin || C.skin, skinD = opts.skinD || C.skinD;
  // --- голова ---
  f.rect(5, 2, 6, 1, hair);
  f.rect(4, 3, 8, 1, hair);
  if (dir === 3) {
    f.rect(5, 4, 6, 2, hair);
  } else {
    f.rect(4, 4, 1, 2, hair);
    f.rect(11, 4, 1, 2, hair);
    f.rect(5, 4, 6, 2, skin);
    f.set(5, 5, skinD); f.set(10, 5, skinD);
    if (dir === 0) { f.set(6, 5, C.eye); f.set(9, 5, C.eye); }
    if (dir === 1) { f.set(6, 5, C.eye); }
    if (dir === 2) { f.set(9, 5, C.eye); }
  }
  f.rect(6, 6, 4, 1, skin);
  if (dir === 0 && !opts.beard) { f.set(7, 6, C.mouth); f.set(8, 6, C.mouth); }
  // --- тело ---
  f.rect(6, 7, 4, 2, tunic);
  f.rect(5, 7, 1, 1, tunicD); f.rect(10, 7, 1, 1, tunicD);
  f.rect(6, 9, 4, 1, opts.belt || C.heroBelt);
  const aUp = step === 1, aDn = step === 2;
  f.set(4, 8, skin); f.set(11, 8, skin);
  if (aUp) { f.set(4, 7, skin); f.set(11, 9, skin); }
  if (aDn) { f.set(4, 9, skin); f.set(11, 7, skin); }
  // --- ноги ---
  if (step === 0) {
    f.rect(6, 10, 2, 2, opts.pants || C.heroPants); f.rect(8, 10, 2, 2, opts.pants || C.heroPants);
    f.rect(6, 12, 2, 1, opts.boot || C.woodCD); f.rect(8, 12, 2, 1, opts.boot || C.woodCD);
  } else if (step === 1) {
    f.rect(6, 10, 2, 2, opts.pants || C.heroPants); f.rect(8, 10, 2, 1, opts.pants || C.heroPants);
    f.rect(6, 12, 2, 1, opts.boot || C.woodCD); f.set(8, 11, opts.boot || C.woodCD);
  } else {
    f.rect(6, 10, 2, 1, opts.pants || C.heroPants); f.rect(8, 10, 2, 2, opts.pants || C.heroPants);
    f.set(6, 11, opts.boot || C.woodCD); f.rect(8, 12, 2, 1, opts.boot || C.woodCD);
  }
  // --- длинные волосы и борода (расширения скелета) ---
  if (opts.longHair && dir !== 3) { f.rect(4, 6, 1, 2, hair); f.rect(11, 6, 1, 2, hair); }
  if (opts.beard && dir !== 3) { f.rect(5, 6, 6, 1, hair); f.rect(6, 7, 4, 1, hair); }
  if (opts.trimBeard && dir !== 3) { f.set(6, 6, C.beardL); f.set(9, 6, C.beardL); f.set(7, 7, C.beardL); f.set(8, 7, C.beardL); }
  // меч за спиной (как у героя из образца)
  if (opts.sword) { f.set(12, 4, C.rockL); f.rect(12, 5, 1, 4, C.rock); f.set(12, 9, C.woodD); }
  // колчан лучника: сзади (dir left — справа, dir right — слева, up — по центру спины)
  if (opts.quiver) {
    if (dir === 2) { f.rect(3, 4, 1, 4, C.quiverC); f.set(3, 7, C.quiverD); f.set(3, 3, C.featherW); }
    else if (dir === 3) { f.rect(7, 4, 2, 4, C.quiverC); f.rect(7, 7, 2, 1, C.quiverD); f.set(7, 3, C.featherW); f.set(8, 3, C.featherW); }
    else { f.rect(12, 4, 1, 4, C.quiverC); f.set(12, 7, C.quiverD); f.set(12, 3, C.featherW); }
  }
  return f;
}
function genHermit() {
  const f = drawChar({
    hair: C.wWhite, tunic: C.hermRobe, tunicD: C.hermRobeD,
    skin: C.hermSkin, skinD: C.hermSkinD, pants: C.hermRobeD, belt: C.woodCD,
    beard: true, longHair: true,
  }, 0, 0);
  f.save('npc_hermit.png');
}

// ---------- Босс «Осквернённый гром» 32x32 x2 кадра ----------
function genBrute() {
  const s = new Img(64, 32);
  const frame = (ox, top, base, maxHW) => {
    const f = new Img(32, 32), cx = 16;
    const hwAt = (y) => Math.round(maxHW * (0.38 + 0.62 * (y - top) / Math.max(1, base - top)));
    // тело
    for (let y = top; y <= base; y++) {
      const hw = hwAt(y);
      f.rect(cx - hw, y, hw * 2 + 1, 1, C.brute);
      f.set(cx - hw, y, C.bruteD); f.set(cx + hw, y, C.bruteD);
      const t = (y - top) / Math.max(1, base - top);
      if (t >= 0.55) {                                  // светлое брюхо
        const bhw = Math.max(0, hw - 4);
        for (let x = cx - bhw; x <= cx + bhw; x++) f.set(x, y, C.bruteL);
      }
    }
    for (let dx = -maxHW; dx <= maxHW; dx++) f.set(cx + dx, base, C.bruteD); // нижняя кромка
    // блик
    f.set(cx - 5, top + 3, C.bruteXL); f.set(cx - 4, top + 3, C.bruteXL); f.set(cx - 5, top + 4, C.bruteXL);
    // ядовито-зелёные пятна (детерминированный шум, в стороне от глаз)
    const ey = top + Math.round((base - top) * 0.35);
    const inEye = (x, y) => (x >= 9 && x <= 13 || x >= 19 && x <= 23) && y >= ey - 3 && y <= ey + 3;
    for (let y = top + 2; y <= top + 7; y++) {
      const hw = hwAt(y);
      for (let dx = -(hw - 2); dx <= hw - 2; dx++) {
        const x = cx + dx;
        if (inEye(x, y) || nz(x, y, 17, 29, 5, 23) !== 0) continue;
        f.set(x, y, C.bruteSpot);
        if (nz(x, y + 1, 17, 29, 6, 11) === 0 && y + 1 <= top + 8 && !inEye(x, y + 1)) f.set(x, y + 1, C.bruteSpot);
      }
    }
    // тёмные подтёки гнили снизу
    for (const dx of [-7, -2, 4, 8]) {
      const h = 2 + Math.abs(dx * 13 + top * 7) % 3;
      for (let i = 0; i < h; i++) f.set(cx + dx, base - i, C.rot);
      if (h >= 4 && base < 27) f.set(cx + dx, base + 1, C.rot); // капает не ниже линии земли y=27
    }
    // глаза: белые, крупные, со злыми бровями
    f.rect(10, ey, 3, 3, [255, 255, 255]); f.rect(20, ey, 3, 3, [255, 255, 255]);
    f.rect(11, ey + 1, 2, 2, C.eye);      f.rect(20, ey + 1, 2, 2, C.eye);
    for (const [x, y] of [[9, ey - 3], [10, ey - 2], [11, ey - 2], [12, ey - 1],
                          [23, ey - 3], [22, ey - 2], [21, ey - 2], [20, ey - 1]]) {
      if (x >= cx - hwAt(y) && x <= cx + hwAt(y)) f.set(x, y, C.bruteBrow);
    }
    // злой рот с клыками
    const yM = ey + 6;
    f.rect(cx - 4, yM, 9, 1, C.bruteMouth);
    f.set(cx - 2, yM + 1, C.tooth); f.set(cx - 1, yM + 1, C.tooth);
    f.set(cx + 2, yM + 1, C.tooth); f.set(cx + 3, yM + 1, C.tooth);
    s.blit(f, ox, 0);
  };
  frame(0, 7, 26, 12);    // кадр 1: обычный
  frame(32, 10, 27, 13);  // кадр 2: присевший — шире на 2px, ниже на 3px
  s.save('brute.png');
}

// ---------- Портреты 40x40 (bigHead из образца) + морда босса ----------
function bigHead(img, ox, opts) {
  const hair = opts.hair, skin = opts.skin || C.skin;
  img.rect(ox + 6, 4, 28, 20, hair);
  img.rect(ox + 9, 8, 22, 22, skin);
  img.rect(ox + 6, 4, 28, 6, hair);
  img.rect(ox + 6, 8, 4, 14, hair);
  img.rect(ox + 30, 8, 4, 14, hair);
  img.rect(ox + 9, 30, 22, 3, opts.collar || C.tunicD);
  img.rect(ox + 13, 18, 4, 5, [255, 255, 255]);
  img.rect(ox + 23, 18, 4, 5, [255, 255, 255]);
  img.rect(ox + 14, 20, 2, 3, C.eye); img.rect(ox + 24, 20, 2, 3, C.eye);
  img.rect(ox + 12, 16, 5, 1, hair); img.rect(ox + 23, 16, 5, 1, hair);
  img.rect(ox + 20, 24, 2, 4, C.skinD);
  if (opts.beard) { img.rect(ox + 12, 27, 16, 5, hair); img.rect(ox + 17, 27, 6, 2, C.mouth); }
  else img.rect(ox + 17, 27, 6, 2, C.mouth);
  if (opts.hat) { img.rect(ox + 4, 2, 32, 4, opts.hat); img.rect(ox + 10, 0, 20, 3, opts.hat); }
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
        let c = neck ? C.monSkinD : C.monSkin;
        if (!neck && y >= 30) c = C.monSkinDD;
        img.set(ox + x, y, c);
      }
      img.set(ox + x0, y, C.monOut); img.set(ox + x1, y, C.monOut);       // контур
      if (!neck && x1 - x0 > 8) img.set(ox + x0 + 1, y, C.bruteL);        // блик слева
      if (!neck && x1 - x0 > 8) img.set(ox + x1 - 1, y, C.monSkinD);      // тень справа
    }
  for (const [x, y] of [[6, 12], [8, 8], [30, 10], [32, 16], [28, 32], [10, 36]]) {
    img.set(ox + x, y, C.bruteSpot); img.set(ox + x + 1, y, C.bruteSpot);
  }
  for (const [x, y] of [[14, 3], [24, 2], [4, 20], [34, 26]]) img.set(ox + x, y, [45, 100, 52]);
  // глаза
  img.rect(ox + 9, 14, 6, 5, [255, 255, 255]); img.rect(ox + 25, 14, 6, 5, [255, 255, 255]);
  img.rect(ox + 12, 16, 3, 3, C.eye); img.rect(ox + 25, 16, 3, 3, C.eye);
  // злые брови (к центру опускаются)
  img.rect(ox + 9, 11, 5, 1, C.monBrow); img.rect(ox + 12, 12, 4, 1, C.monBrow); img.rect(ox + 14, 13, 3, 1, C.monBrow);
  img.rect(ox + 26, 11, 5, 1, C.monBrow); img.rect(ox + 24, 12, 4, 1, C.monBrow); img.rect(ox + 23, 13, 3, 1, C.monBrow);
  // злой пасть с клыками
  img.rect(ox + 11, 26, 17, 3, C.monMouth);
  img.rect(ox + 14, 26, 2, 2, C.tooth); img.rect(ox + 24, 26, 2, 2, C.tooth);
  img.rect(ox + 19, 28, 2, 1, C.tooth);
}
function genPortraits2() {
  const s = new Img(120, 40);
  bigHead(s, 0, { hair: C.hairD });                                             // герой — как в portraits.png
  bigHead(s, 40, { hair: C.wWhite, beard: true, collar: C.hermRobe, skin: C.hermSkin }); // отшельник
  monsterHead(s, 80);                                                            // Осквернённый гром
  s.save('portraits2.png');
}

// ---------- Ключ 16x16, по диагонали, прозрачный фон ----------
function genKey() {
  const f = new Img(16, 16);
  const gold = new Set();
  const add = (x, y) => { if (x >= 0 && y >= 0 && x < 16 && y < 16) gold.add(x + ',' + y); };
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {         // ушко-кольцо
    const d = (x - 11.5) * (x - 11.5) + (y - 3.5) * (y - 3.5);
    if (d >= 1.5 && d <= 6.5) add(x, y);
  }
  for (let x = 4; x <= 10; x++) add(x, 15 - x);                       // стержень
  add(8, 5); add(10, 7);                                              // воротничок
  for (const [x, y] of [[6, 11], [7, 12], [5, 12], [6, 13]]) add(x, y); // зубцы
  for (const k of gold) { const [x, y] = k.split(',').map(Number); f.set(x, y, C.gold); }
  for (const [x, y] of [[11, 2], [12, 2], [9, 6], [8, 7]]) f.set(x, y, C.keyL); // блик
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {         // тёмный обвод
    if (gold.has(x + ',' + y)) continue;
    let near = false;
    for (let dy = -1; dy <= 1 && !near; dy++) for (let dx = -1; dx <= 1; dx++)
      if (gold.has((x + dx) + ',' + (y + dy))) { near = true; break; }
    if (near) f.set(x, y, C.keyDark);
  }
  f.save('key.png');
}

// ================= СПРИНТ 2: классы, иконки скиллов, снаряды, курсоры =================
Object.assign(C, {
  heroBelt: [90, 60, 35], heroPants: [72, 72, 95], beardL: [210, 210, 220],
  quiverC: [110, 75, 45], quiverD: [80, 54, 32], featherW: [225, 220, 205],
  steel: [210, 215, 228], steelL: [232, 238, 248], steelD: [150, 155, 175],
  gold2: [240, 200, 90], white4: [225, 230, 240], healG: [170, 235, 200],
  fire: [255, 160, 60], fireL: [255, 220, 120], fireD: [220, 90, 40],
  ice: [120, 220, 240], iceL: [200, 245, 255], iceD: [70, 150, 190],
  red2: [230, 80, 70], redL: [255, 140, 130], redD2: [170, 50, 50],
  cloud: [160, 166, 185], cloudD: [120, 126, 148],
  iconBg: [40, 40, 55], iconDark: [20, 20, 28],
  curY: [240, 210, 90], curYL: [255, 240, 150], curR: [220, 70, 60], curRL: [255, 140, 130],
  arrowW: [150, 110, 60],
});

// ---------- Листы классов 48x64 (тот же скелет drawChar, что и player.png) ----------
function genClass(name, opts) {
  const sheet = new Img(48, 64);
  for (let row = 0; row < 4; row++)          // ряды: down,left,right,up
    for (let col = 0; col < 3; col++)        // кадры: idle,шаг1,idle... (0,1,0,2)
      sheet.blit(drawChar(opts, row, col), col * 16, row * 16);
  sheet.save(name);
}
function genClasses() {
  genClass('class_warrior.png', { hair: C.hairD, tunic: [170, 60, 55], tunicD: [150, 150, 160], belt: [150, 150, 160], pants: [110, 110, 122], boot: [70, 55, 50], sword: true });
  genClass('class_archer.png', { hair: C.hairD, tunic: [70, 120, 60], tunicD: [50, 88, 44], belt: C.heroBelt, pants: [96, 80, 58], quiver: true });
  genClass('class_mage.png', { hair: C.hairD, tunic: [90, 80, 180], tunicD: [64, 56, 140], belt: [200, 170, 80], pants: [64, 56, 140], boot: [46, 40, 96], trimBeard: true });
}

// ---------- Иконки скиллов 192x16 (12 слотов 16x16, порядок фиксирован) ----------
// 0 power_strike, 1 whirlwind, 2 second_wind, 3 execute, 4 pierce, 5 volley,
// 6 mark, 7 rain, 8 firebolt, 9 frost_nova, 10 siphon, 11 firestorm
function iconBase() {
  const im = new Img(16, 16);
  const span = (y) => (y === 0 || y === 15) ? [2, 13] : (y === 1 || y === 14) ? [1, 14] : [0, 15];
  for (let y = 0; y < 16; y++) { const [x0, x1] = span(y); im.rect(x0, y, x1 - x0 + 1, 1, C.iconBg); }
  const dk = C.iconDark;                    // тёмная обводка скруглённой плитки
  im.rect(2, 0, 12, 1, dk); im.rect(2, 15, 12, 1, dk);
  im.rect(0, 2, 1, 12, dk); im.rect(15, 2, 1, 12, dk);
  for (const [x, y] of [[1, 1], [14, 1], [1, 14], [14, 14]]) im.set(x, y, dk);
  return im;
}
function autoOutline(im) {                  // глиф -> тёмная обводка [20,20,28]
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
const gPowerStrike = (im) => {              // меч + искры
  im.set(8, 2, C.steelL); im.rect(7, 3, 2, 6, C.steel);
  for (let y = 3; y <= 8; y++) im.set(7, y, C.steelL);
  im.rect(5, 9, 6, 1, C.gold2); im.rect(7, 10, 2, 3, [120, 80, 45]); im.rect(7, 13, 2, 1, C.gold2);
  for (const [x, y] of [[4, 4], [11, 4], [3, 7], [12, 7], [4, 11], [11, 11]]) im.set(x, y, C.gold2);
};
const gWhirlwind = (im) => {                // спираль
  for (const [x, y] of [[8, 8], [8, 7]]) im.set(x, y, C.steelD);
  for (const [x, y] of [[7, 7], [6, 8], [7, 9], [9, 9], [10, 8], [10, 6], [9, 5]]) im.set(x, y, C.steel);
  for (const [x, y] of [[7, 5], [5, 6], [5, 8], [5, 10], [7, 11], [9, 11], [11, 10], [12, 8], [12, 5], [11, 3]]) im.set(x, y, C.steelL);
  for (const [x, y] of [[3, 4], [4, 3], [12, 12], [11, 13]]) im.set(x, y, C.steelD);
};
const gSecondWind = (im) => {               // белый крест + свечение
  im.rect(7, 4, 2, 8, C.white4); im.rect(4, 7, 8, 2, C.white4);
  im.rect(8, 4, 1, 8, C.steelD); im.rect(4, 8, 8, 1, C.steelD); // тень креста
  im.rect(7, 4, 1, 8, C.white4); im.rect(4, 7, 8, 1, C.white4);
  for (const [x, y] of [[7, 2], [8, 2], [7, 13], [8, 13], [2, 7], [2, 8], [13, 7], [13, 8], [5, 5], [10, 5], [5, 10], [10, 10]]) im.set(x, y, C.healG);
};
const gExecute = (im) => {                  // череп
  im.rect(5, 4, 6, 5, C.bone); im.rect(6, 9, 4, 2, C.bone);
  im.rect(6, 6, 1, 2, C.iconDark); im.rect(9, 6, 1, 2, C.iconDark);
  im.rect(5, 8, 6, 1, C.boneD); im.set(8, 4, C.boneD);
  im.set(7, 10, C.iconDark); im.set(8, 10, C.iconDark);
};
const arrowH = (im, y) => {
  im.rect(4, y, 8, 1, C.arrowW);
  im.set(12, y, C.steel); im.set(13, y, C.steelL);
  im.set(3, y - 1, C.featherW); im.set(3, y, C.featherW); im.set(3, y + 1, C.featherW); im.set(2, y, C.featherW);
};
const gPierce = (im) => { arrowH(im, 6); arrowH(im, 10); };      // двойная стрела
const gVolley = (im) => {                                        // 3 стрелы веером
  im.rect(8, 5, 1, 7, C.arrowW); im.set(8, 3, C.steelL); im.set(8, 4, C.steel);
  im.set(7, 12, C.featherW); im.set(9, 12, C.featherW);
  im.set(4, 4, C.steelL); im.set(3, 5, C.steel);
  for (const [x, y] of [[4, 6], [4, 7], [3, 8], [3, 9], [3, 10]]) im.set(x, y, C.arrowW);
  im.set(2, 11, C.featherW); im.set(4, 11, C.featherW);
  im.set(11, 4, C.steelL); im.set(12, 5, C.steel);
  for (const [x, y] of [[11, 6], [11, 7], [12, 8], [12, 9], [12, 10]]) im.set(x, y, C.arrowW);
  im.set(13, 11, C.featherW); im.set(10, 11, C.featherW);
};
const gMark = (im) => {                                            // глаз в прицеле
  im.rect(6, 6, 4, 1, C.white4); im.rect(5, 7, 6, 1, C.white4); im.rect(6, 8, 4, 1, C.white4);
  im.set(7, 7, C.red2); im.set(8, 7, C.red2);
  for (const [x, y] of [[7, 3], [8, 3], [7, 12], [8, 12], [2, 7], [3, 7], [12, 7], [13, 7]]) im.set(x, y, C.gold2);
};
const gRain = (im) => {                                            // туча + стрелы вниз
  im.rect(6, 3, 4, 1, C.cloud); im.rect(4, 4, 8, 1, C.cloud); im.rect(3, 5, 10, 1, C.cloud); im.rect(3, 6, 10, 1, C.cloudD);
  for (const [sx, ty] of [[5, 10], [8, 11], [11, 10]]) {
    im.set(sx, 8, C.featherW); im.set(sx, 9, C.steel); im.set(sx, ty, C.steelL);
  }
  im.set(8, 10, C.steel);
};
const gFirebolt = (im) => {                                        // капля огня
  im.set(10, 1, C.fireD); im.set(9, 2, C.fire); im.set(8, 3, C.fire);
  const drop = [[7, 9, 4], [6, 10, 5], [6, 10, 6], [5, 10, 7], [5, 10, 8], [5, 10, 9], [6, 10, 10], [7, 9, 11]];
  for (const [x0, x1, y] of drop) {
    im.rect(x0, y, x1 - x0 + 1, 1, C.fire);
    im.set(x0, y, C.fireD); im.set(x1, y, C.fireD);
  }
  im.rect(7, 7, 3, 2, C.fireL); im.set(8, 6, C.fireL);
};
const gFrostNova = (im) => {                                       // снежинка 6 лучей
  const sp = [];
  for (let y = 3; y <= 6; y++) sp.push([7, y], [8, y]);
  for (let y = 9; y <= 12; y++) sp.push([7, y], [8, y]);
  for (const [x, y] of [[9, 5], [10, 4], [11, 3], [6, 5], [5, 4], [4, 3], [9, 10], [10, 11], [11, 12], [6, 10], [5, 11], [4, 12]]) sp.push([x, y]);
  for (const [x, y] of sp) im.set(x, y, C.ice);
  im.rect(7, 7, 2, 2, C.iceL);
  for (const [x, y] of [[7, 3], [8, 3], [7, 12], [8, 12], [11, 3], [4, 3], [11, 12], [4, 12]]) im.set(x, y, C.iceL);
};
const gSiphon = (im) => {                                          // капля + стрелка к контуру сердца
  im.set(5, 3, C.red2); im.rect(4, 4, 3, 2, C.red2); im.set(5, 6, C.red2); im.set(4, 4, C.redL);
  im.rect(6, 8, 3, 1, C.red2); im.set(7, 7, C.red2); im.set(7, 9, C.red2); im.set(8, 8, C.redL);
  for (const [x, y] of [[9, 6], [10, 6], [12, 6], [13, 6], [8, 7], [14, 7], [9, 9], [13, 9], [10, 10], [12, 10], [11, 11]]) im.set(x, y, C.redD2);
};
const gFirestorm = (im) => {                                       // огненный вихрь
  const rows = [[2, 4, 11], [3, 4, 12], [4, 3, 11], [5, 4, 11], [6, 4, 10], [7, 5, 11], [8, 5, 10], [9, 6, 10], [10, 6, 9], [11, 6, 9], [12, 7, 8]];
  for (const [y, x0, x1] of rows) for (let x = x0; x <= x1; x++) {
    const e = (x === x0 || x === x1 || y === 12) ? C.fireD
      : nz(x, y, 5, 9, 3, 4) === 0 ? C.fireD
      : nz(x, y, 7, 13, 5, 4) < 1 ? C.fireL : C.fire;
    im.set(x, y, e);
  }
  im.set(12, 1, C.fireL); im.set(3, 1, C.fire); im.set(2, 4, C.fireD);
};
function genSkillIcons() {
  const s = new Img(192, 16);
  const glyphs = [gPowerStrike, gWhirlwind, gSecondWind, gExecute, gPierce, gVolley,
                  gMark, gRain, gFirebolt, gFrostNova, gSiphon, gFirestorm];
  glyphs.forEach((g, i) => { const im = iconBase(); g(im); autoOutline(im); s.blit(im, i * 16); });
  s.save('skill_icons.png');
}

// ---------- Снаряды 64x16: 0 стрела, 1 файербол, 2 осколок льда, 3 стрела-призрак ----------
function genProjectiles() {
  const s = new Img(64, 16);
  const arrow = (ox, a, shaft, head, headL, feather) => {           // горизонтальная, центр y=8
    s.rect(ox + 4, 8, 8, 1, shaft);
    s.set(ox + 12, 7, head); s.set(ox + 12, 8, headL); s.set(ox + 12, 9, head); s.set(ox + 13, 8, headL);
    s.set(ox + 2, 7, feather); s.set(ox + 3, 7, feather); s.set(ox + 2, 9, feather); s.set(ox + 3, 9, feather);
    s.set(ox + 2, 8, a);
  };
  arrow(0, C.red2, C.arrowW, C.steel, C.steelL, C.featherW);
  // 1 файербол: шар со светлым ядром, хвост влево
  const ball = [[9, 11, 4], [8, 13, 5], [8, 13, 6], [8, 13, 7], [8, 13, 8], [8, 13, 9], [9, 11, 10]];
  for (const [x0, x1, y] of ball) {
    s.rect(16 + x0, y, x1 - x0 + 1, 1, C.fire);
    s.set(16 + x0, y, C.fireD); s.set(16 + x1, y, C.fireD);
  }
  s.rect(26, 6, 3, 3, C.fireL);
  s.set(22, 7, C.fire); s.set(22, 8, C.fire); s.set(21, 9, C.fire); s.set(20, 8, C.fireD); s.set(19, 7, C.fireD); s.set(18, 8, C.fireD);
  // 2 осколок льда: ромб с бликом
  const dia = [[8, 8, 4], [7, 9, 5], [6, 10, 6], [5, 11, 7], [5, 11, 8], [6, 10, 9], [7, 9, 10], [8, 8, 11]];
  for (const [x0, x1, y] of dia) s.rect(32 + x0, y, x1 - x0 + 1, 1, C.ice);
  for (const [x, y] of [[8, 4], [9, 5], [10, 6], [11, 7], [11, 8], [10, 9], [9, 10], [8, 11]]) s.set(32 + x, y, C.iceD);
  for (const [x, y] of [[7, 5], [6, 6], [6, 7], [7, 6]]) s.set(32 + x, y, C.iceL);
  // 3 стрела-призрак (alpha ~120)
  arrow(48, [235, 245, 255, 150], [200, 230, 255, 120], [200, 230, 255, 120], [235, 245, 255, 150], [225, 235, 250, 110]);
  s.save('projectiles.png');
}

// ---------- Курсоры 16x16 ----------
function genCursors() {
  let im = new Img(16, 16);                    // жёлтая точка-кольцо
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const d2 = (x - 7.5) ** 2 + (y - 7.5) ** 2;
    if (d2 >= 9 && d2 <= 16) im.set(x, y, C.curY);
  }
  im.rect(7, 7, 2, 2, C.curY); im.set(7, 7, C.curYL);
  im.save('cursor_move.png');
  im = new Img(16, 16);                        // красный прицел: кольцо r~6 + 4 засечки
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const d2 = (x - 7.5) ** 2 + (y - 7.5) ** 2;
    if (d2 >= 30 && d2 <= 42) im.set(x, y, C.curR);
  }
  for (const [x, y] of [[7, 4], [8, 4], [7, 11], [8, 11], [4, 7], [4, 8], [11, 7], [11, 8]]) im.set(x, y, C.curRL);
  im.save('cursor_enemy.png');
}

// ---------- запуск ----------
genDungeonTiles();
genBrute();
genHermit();
genPortraits2();
genKey();
genClasses();
genSkillIcons();
genProjectiles();
genCursors();

console.log('--- verification ---');
for (const [name, w, h] of [['dungeon_tiles.png', 256, 16], ['brute.png', 64, 32],
                            ['npc_hermit.png', 16, 16], ['portraits2.png', 120, 40], ['key.png', 16, 16],
                            ['class_warrior.png', 48, 64], ['class_archer.png', 48, 64], ['class_mage.png', 48, 64],
                            ['skill_icons.png', 192, 16], ['projectiles.png', 64, 16],
                            ['cursor_move.png', 16, 16], ['cursor_enemy.png', 16, 16]]) {
  const b = fs.readFileSync(path.join(OUT, name));
  const sig = [...b.slice(0, 8)].map(v => v.toString(16).padStart(2, '0').toUpperCase()).join(' ');
  const ihdrW = b.readUInt32BE(16), ihdrH = b.readUInt32BE(20);
  const ok = ihdrW === w && ihdrH === h && sig === '89 50 4E 47 0D 0A 1A 0A';
  console.log(name, ihdrW + 'x' + ihdrH, 'sig=' + sig.slice(0, 11), ok ? 'OK' : 'FAIL');
}
console.log('DONE');
