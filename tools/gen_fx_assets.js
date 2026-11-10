// Генератор PNG частиц для VFX-системы «Тени Северного Леса» (assets/fx).
// Белый RGB + форма через альфу -> тон CPUParticles2D.color задаёт код (fx.gd).
// Собственная CC0-публикация (сеть была закрыта, Kenney Particle Pack не скачан).
// Запуск: node tools/gen_fx_assets.js [outdir]
'use strict';
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const OUT = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(__dirname, '..', 'sand_fx', 'pixel-rpg', 'assets', 'fx');
fs.mkdirSync(OUT, { recursive: true });

// ---------- PNG encoder (RGBA 8-bit) + .import генератор ----------
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
function encodePng(w, h, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}
function writeImport(pngPath) {
  const md5 = crypto.createHash('md5').update(fs.readFileSync(pngPath)).digest('hex');
  const base = path.basename(pngPath);
  const rel = 'res://assets/fx/' + base;
  const ctex = 'res://.godot/imported/' + base + '-' + md5 + '.ctex';
  const txt = `[remap]

importer="texture"
type="CompressedTexture2D"
path="${ctex}"
metadata={
"vram_texture": false
}

[deps]

source_file="${rel}"
dest_files=["${ctex}"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
`;
  fs.writeFileSync(pngPath + '.import', txt);
}

// ----------Shapes: ASCII-map, символы -> alpha (W=255 B=200 S=140 D=80 .=0)
const A = { W: 255, B: 200, S: 140, D: 80, '.': 0 };
function fromMap(rows) {
  const h = rows.length, w = rows[0].length;
  const buf = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const a = A[rows[y][x]] || 0;
      const i = (y * w + x) * 4;
      buf[i] = 255; buf[i + 1] = 255; buf[i + 2] = 255; buf[i + 3] = a;
    }
  }
  return { w, h, buf };
}
function save(name, rows) {
  const { w, h, buf } = fromMap(rows);
  const p = path.join(OUT, name);
  fs.writeFileSync(p, encodePng(w, h, buf));
  writeImport(p);
  console.log('wrote', name, w + 'x' + h);
}

// 4x4 «горошина»: искры, хил, угли
save('fx_dot.png', [
  '.WW.',
  'WWWW',
  'WWWW',
  '.WW.',
]);
// 6x6 мягкая горошина (двойная альфа-кромка): свечение хила/левелапа
save('fx_dot_soft.png', [
  '.DDDD.',
  'DSSSSD',
  'DSWWSD',
  'DSWWSD',
  'DSSSSD',
  '.DDDD.',
]);
// 7x7 четырёхлучевая искра
save('fx_spark.png', [
  '...B...',
  '..WWW..',
  '..WWW..',
  'BWWWWWB',
  '..WWW..',
  '..WWW..',
  '...B...',
]);
// 5x5 звездокрест (левелап)
save('fx_star.png', [
  'W...W',
  '.W.W.',
  '.WWW.',
  '.W.W.',
  'W...W',
]);
// 6x8 пламя (капля, низ прозрачнее)
save('fx_flame.png', [
  '..W...',
  '.WWW..',
  '.WWWW.',
  'WWWWWW',
  'WWWWWW',
  'WWWWWW',
  'BSWWWB',
  '..SS..',
]);
// 8x8 дымок (низкая альфа, дырчатый ком)
save('fx_smoke.png', [
  '..SSSS..',
  '.SDDSSS.',
  'SSD..SDS',
  'SSSSDSSS',
  'SS.DSSSS',
  'SSSSSS.D',
  '.SSSSSS.',
  '..S.SS..',
]);
// 5x7 ледяной осколок
save('fx_shard.png', [
  '..W..',
  '..W..',
  '.WWW.',
  '.WWW.',
  '.WWW.',
  '..B..',
  '..B..',
]);
console.log('OK ->', OUT);
