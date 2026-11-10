// alpha-раскладка shadow.png + якоря спрайтов
const fs = require('fs'), zlib = require('zlib');
function decode(path) {
  const b = fs.readFileSync(path);
  let p = 8, w = 0, h = 0, idat = Buffer.alloc(0);
  while (p < b.length) {
    const len = b.readUInt32BE(p), type = b.toString('ascii', p + 4, p + 8);
    if (type === 'IHDR') { w = b.readUInt32BE(p + 8); h = b.readUInt32BE(p + 12); }
    if (type === 'IDAT') idat = Buffer.concat([idat, b.slice(p + 8, p + 8 + len)]);
    p += 12 + len;
  }
  const raw = zlib.inflateSync(idat), bpp = 4, stride = w * bpp;
  const px = Buffer.alloc(h * stride); let q = 0;
  for (let y = 0; y < h; y++) {
    const f = raw[q++], line = raw.slice(q, q + stride); q += stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? px[(y - 1) * stride + x - bpp] : 0, b2 = y > 0 ? px[(y - 1) * stride + x] : 0, c = (x >= bpp && y > 0) ? px[(y - 1) * stride + x - bpp] : 0;
      let v = line[x];
      if (f === 1) v += a; else if (f === 2) v += b2; else if (f === 3) v += (a + b2) >> 1;
      else if (f === 4) { const pp = a + b2 - c, pa = Math.abs(pp - a), pb = Math.abs(pp - b2), pc = Math.abs(pp - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b2 : c); }
      px[y * stride + x] = v & 255;
    }
  }
  return { w, h, px, stride };
}
const { w, h, px, stride } = decode(process.argv[2]);
let minx = w, miny = h, maxx = -1, maxy = -1; const rows = [];
for (let y = 0; y < h; y++) {
  let r = '';
  for (let x = 0; x < w; x++) {
    const al = px[y * stride + x * 4 + 3];
    if (al > 20) { if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y; r += '#'; } else r += '.';
  }
  rows.push(r);
}
console.log('size ' + w + 'x' + h + '  alpha>20 box ' + [minx, miny, maxx, maxy].join(','));
console.log(rows.join('\n'));
