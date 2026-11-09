// tools/png_check.js — декодирует PNG (RGBA8, color type 6) и считает непрозрачные пиксели по ячейкам.
// Использование: node tools/png_check.js <file.png> [cellW cellH]
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
  if (bitDepth !== 8 || colorType !== 6) throw new Error(path + ": ожидаем RGBA8 (depth=" + bitDepth + " type=" + colorType + ")");
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
const cw = parseInt(process.argv[3] || "16"), chh = parseInt(process.argv[4] || "16");
const img = decode(file);
const cols = Math.ceil(img.w / cw), rows = Math.ceil(img.h / chh);
const cells = [];
for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
  let op = 0; const colors = new Set();
  for (let y = r * chh; y < Math.min(img.h, (r + 1) * chh); y++) for (let x = c * cw; x < Math.min(img.w, (c + 1) * cw); x++) {
    const i = (y * img.w + x) * 4;
    if (img.px[i + 3] > 0) { op++; colors.add(img.px[i] + "," + img.px[i + 1] + "," + img.px[i + 2]); }
  }
  cells.push({ cell: r * cols + c, op, colors: colors.size });
}
const bad = cells.filter(x => x.op < 3);
console.log(`${file} ${img.w}x${img.h} — ${cells.length} ячеек ${cw}x${chh}; пустых(<3px): ${bad.length ? JSON.stringify(bad.map(b => b.cell)) : 0}`);
console.log("  непрозрачных пикселей по ячейкам:", cells.map(c => c.op).join(","));
