// tools/scan_ashen.js — проверка читаемости силуэтов атласа Пепелища.
// Использование: node tools/scan_ashen.js <file.png> <groundIdx,...> <blockerIdx,...>
// Для каждого тайла: средняя яркость (Rec.601), счётчик тёмных контурных px
// (lum<50), светлых px в верхней половине (lum>115). Правила блокировщика:
// darkPx>=14, topLightPx>=3, |avg-groundAvg|>=15.
const fs = require("fs");
const zlib = require("zlib");
function decode(path) {
  const buf = fs.readFileSync(path);
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not PNG: " + path);
  let p = 8, w = 0, h = 0, bitDepth = 0, colorType = 0, idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p); const type = buf.toString("ascii", p + 4, p + 8);
    const data = buf.subarray(p + 8, p + 8 + len);
    if (type === "IHDR") { w = data.readUInt32BE(0); h = data.readUInt32BE(4); bitDepth = data[8]; colorType = data[9]; }
    else if (type === "IDAT") idat.push(data);
    p += 12 + len;
  }
  if (bitDepth !== 8 || colorType !== 6) throw new Error(path + ": ожидаем RGBA8");
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const bpp = 4, stride = w * bpp, out = Buffer.alloc(h * stride);
  const paeth = (a, b, c) => { const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c); return pa <= pb && pa <= pc ? a : pb <= pc ? b : c; };
  for (let y = 0; y < h; y++) {
    const ft = raw[y * (stride + 1)], line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? out[y * stride + x - bpp] : 0;
      const b = y > 0 ? out[(y - 1) * stride + x] : 0;
      const c = x >= bpp && y > 0 ? out[(y - 1) * stride + x - bpp] : 0;
      let v = line[x];
      if (ft === 1) v += a; else if (ft === 2) v += b; else if (ft === 3) v += (a + b) >> 1; else if (ft === 4) v += paeth(a, b, c);
      out[y * stride + x] = v & 255;
    }
  }
  return { w, h, px: out };
}
const file = process.argv[2];
const ground = (process.argv[3] || "0,1,2,3,7").split(",").map(Number);
const blockers = (process.argv[4] || "4,5,6").split(",").map(Number);
const img = decode(file);
const TS = 16, cols = Math.floor(img.w / TS);
const lum = (i) => 0.299 * img.px[i] + 0.587 * img.px[i + 1] + 0.114 * img.px[i + 2];
const stats = [];
for (let t = 0; t < cols; t++) {
  let sum = 0, n = 0, dark = 0, topLight = 0;
  for (let y = 0; y < TS; y++) for (let x = 0; x < TS; x++) {
    const i = ((y * img.w) + t * TS + x) * 4;
    const l = lum(i);
    sum += l; n++;
    if (l < 50) dark++;
    if (y < 8 && l > 115) topLight++;
  }
  stats.push({ t, avg: Math.round(sum / n), dark, topLight });
}
const gAvg = Math.round(ground.reduce((s, t) => s + stats[t].avg, 0) / ground.length);
console.log(`${file}: средняя яркость пола = ${gAvg}`);
let fails = 0;
for (const s of stats) {
  const role = blockers.includes(s.t) ? "BLOCK" : "floor ";
  let ok = true, why = "";
  if (blockers.includes(s.t)) {
    if (s.dark < 14) { ok = false; why += " dark<14;"; }
    if (s.topLight < 3) { ok = false; why += " topLight<3;"; }
    if (Math.abs(s.avg - gAvg) < 15) { ok = false; why += " dAvg<15;"; }
  }
  if (!ok) fails++;
  console.log(`  [${role}] tile ${s.t}: avg=${s.avg} (d=${s.avg - gAvg}) darkPx=${s.dark} topLightPx=${s.topLight}${ok ? "" : "  <<< FAIL:" + why}`);
}
console.log(fails === 0 ? "СИЛУЭТЫ OK" : `FAILS: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
