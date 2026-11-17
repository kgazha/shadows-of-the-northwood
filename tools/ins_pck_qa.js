// QA-аудит pck (клони инструментов ins_pck.js, параметризованный путь + расширенный чек-лист).
// Uso: node tools/ins_pck_qa.js <path/to/index.pck>
const fs = require('fs');
const p = process.argv[2] || 'build/web/index.pck';
const b = fs.readFileSync(p);
const s = b.toString('latin1');
const uniq = (re) => [...new Set((s.match(re) || []))].sort();

const reqMaps = ['map_ashen.json', 'map_cave.json', 'map_village.json'];
const reqPngs = ['ashen_tiles.png'];
const reqScripts = ['ash', 'achv', 'achv_catalog', 'minimap', 'ashen_zone', 'mob_boss2',
  'mob_swarmling', 'mob_archer', 'save_vault', 'meta_hud', 'click_move', 'shop', 'journal'];

const found = uniq(/res:\/\/[\w\/\.\-]+/g);
// в файловой таблице pck пути лежат без префикса res:// (напр. data/map_ashen.json)
const has = (frag) => found.some((f) => f.includes(frag)) || s.includes(frag);

console.log('PCK:', p, 'bytes=', b.length);
let fails = 0;
const chk = (name, ok, detail) => {
  console.log((ok ? 'PASS' : 'FAIL') + ': ' + name + (detail ? ' [' + detail + ']' : ''));
  if (!ok) fails++;
};

for (const m of reqMaps) chk('map ' + m, has('/' + m), found.filter((f) => f.includes(m))[0] || '');
for (const t of reqPngs) chk('tiles ' + t, has('/' + t), found.filter((f) => f.includes(t))[0] || '');
for (const sc of reqScripts) {
  const re = new RegExp('/scripts/' + sc + '\\.(gd|gdc)$');
  const hit = found.filter((f) => re.test(f));
  chk('script ' + sc + ' (.gd|.gdc)', hit.length > 0, hit[0] || '');
}
const wavs = uniq(/[\w\/\.\-]+\.wav/g);
chk('ноль .wav в pck', wavs.length === 0, wavs.slice(0, 5).join(','));
const oggs = uniq(/[\w\/\.\-]+\.ogg/g);
chk('SFX .ogg присутствуют', oggs.length > 0, 'n=' + oggs.length);
const mus = oggs.filter((o) => /music|muz|theme/i.test(o));
chk('music .ogg присутствуют', mus.length > 0, mus.slice(0, 3).join(','));
console.log('ogg_list:', oggs.slice(0, 40));
console.log('png_count:', (s.match(/\.png/g) || []).length);
console.log('total_res_paths:', found.length);
console.log(fails === 0 ? 'AUDIT_RESULT: OK' : 'AUDIT_RESULT: FAIL ' + fails);
process.exit(fails === 0 ? 0 : 1);
