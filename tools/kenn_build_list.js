// node tools/kenn_build_list.js <branch> — строит tools/assets_in/kenn_dl.tsv (список для asset_get.js).
'use strict';
const fs = require('fs');
const branch = process.argv[2];
const base = 'https://raw.githubusercontent.com/AceTM/kenney-1/' + branch + '/';
const dst = 'tools/assets_in/kenney_roguelike';
const packs = {
  'Art/Roguelike pack (1700 assets)/Spritesheet': ['roguelikeSheet_transparent.png', 'spritesheetInfo.txt'],
  'Art/Roguelike pack (1700 assets)': ['Sample.png'],
  'Art/Roguelike characters (450 assets)/Spritesheet': ['roguelikeChar_transparent.png', 'spritesheetInfo.txt'],
  'Art/Roguelike characters (450 assets)': ['Sample.png'],
  'Art/Roguelike cave & dungeon pack (520 assets)/Spritesheet': ['roguelikeDungeon_transparent.png', 'spritesheetInfo.txt'],
  'Art/Roguelike cave & dungeon pack (520 assets)': ['Sample.png'],
  'Art/Archive (2650 assets)/Roguelike pack 15x (retired, 2125 assets)': ['roguelikeSheet_transparent.png', 'spritesheetInfo.txt'],
};
const lines = [];
let n = 0;
for (const [dir, files] of Object.entries(packs)) {
  for (let f of files) {
    n++;
    const tag = dir.split('/').pop().replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '');
    lines.push(base + dir.split('/').map(encodeURIComponent).join('/') + '/' + encodeURIComponent(f) +
      '\t' + dst + '/' + tag + '/' + String(n).padStart(2, '0') + '_' + f);
  }
}
fs.writeFileSync('tools/assets_in/kenn_dl.tsv', lines.join('\n') + '\n');
console.log('list ready:', n, 'files, branch=' + branch);
