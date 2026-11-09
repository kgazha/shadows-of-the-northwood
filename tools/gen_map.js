// Генератор карты деревни Морхейм -> pixel-rpg/data/map_village.json
'use strict';
const fs = require('fs'), path = require('path');
const W = 48, H = 30;
const OUT = path.join(__dirname, '..', 'pixel-rpg', 'data');
fs.mkdirSync(OUT, { recursive: true });

// шум
const nz = (x, y, a, b, m) => (((x * 7 + a) * (y * 13 + b) + x * 3 + y * 11) % m + m) % m;

// 1. фон
const g = Array.from({ length: H }, () => Array(W).fill('g'));

// 2. лесная подложка и деревья (юг)
for (let y = 15; y <= 26; y++) for (let x = 2; x <= 45; x++) g[y][x] = 'T';
for (let y = 15; y <= 26; y++) for (let x = 2; x <= 45; x++) {
  if (nz(x, y, 5, 3, 6) === 0) g[y][x] = 't';
  else if (nz(x, y, 11, 17, 29) === 0) g[y][x] = 'r';
}
// поляна в центре леса
for (let y = 17; y <= 25; y++) for (let x = 12; x <= 30; x++) {
  const dx = (x - 21) / 9.5, dy = (y - 21) / 4.2;
  if (dx * dx + dy * dy < 1 && g[y][x] === 't' && nz(x, y, 1, 1, 10) < 8) g[y][x] = 'T';
}
// 3. границы-лес
for (let x = 0; x < W; x++) { g[0][x] = 't'; g[1][x] = 't'; g[28][x] = 't'; g[29][x] = 't'; }
for (let y = 0; y < H; y++) { g[y][0] = 't'; g[y][1] = 't'; g[y][46] = 't'; g[y][47] = 't'; }

// 4. цветы в деревне
for (let y = 3; y <= 13; y++) for (let x = 3; x <= 44; x++)
  if (g[y][x] === 'g' && nz(x, y, 13, 7, 19) === 0) g[y][x] = 'f';

// 5. пруд
for (let y = 4; y <= 9; y++) for (let x = 36; x <= 44; x++) g[y][x] = 'w';
g[5][35] = 'r'; g[8][35] = 'r';

// 6. дом (крыша 3-4, стены 5-6, дверь)
for (let y = 3; y <= 4; y++) for (let x = 6; x <= 11; x++) g[y][x] = 'R';
for (let y = 5; y <= 6; y++) for (let x = 6; x <= 11; x++) g[y][x] = 'W';
g[6][8] = 'D';

// 7. дороги
for (let y = 7; y <= 12; y++) g[y][8] = 'd';
for (let x = 4; x <= 44; x++) g[12][x] = 'd';
for (let y = 13; y <= 18; y++) g[y][22] = 'd';

// 8. поляна с сундуком
for (let y = 20; y <= 22; y++) for (let x = 34; x <= 40; x++) if (g[y][x] !== 'w') g[y][x] = 'T';

// 9. указатели
g[11][10] = 's';
g[15][23] = 's';

// сущности
const spawn = [8, 10];
const npcs = [['elder', 10, 8], ['merchant', 22, 13], ['farmer', 29, 13]];
const herbs = [[14, 19], [26, 20], [17, 24], [30, 24], [24, 17], [12, 17]];
const chests = [[37, 21]];
const slimes = [[16, 21], [24, 22], [30, 19], [20, 25], [33, 22], [27, 24]];

// валидация: сущности не должны стоять на непроходимых тайлах
const BLOCK = new Set('twWRD#rs');
const free = new Set();
const key = (x, y) => x + ',' + y;
function fix(x, y, base) {
  if (!BLOCK.has(g[y][x]) && !free.has(key(x, y))) { free.add(key(x, y)); return [x, y]; }
  for (let r = 1; r <= 4; r++)
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
      const nx = x + dx, ny = y + dy;
      if (nx < 2 || ny < 2 || nx > 45 || ny > 27) continue;
      if (!BLOCK.has(g[ny][nx]) && !free.has(key(nx, ny))) { free.add(key(nx, ny)); return [nx, ny]; }
    }
  g[y][x] = base; free.add(key(x, y)); return [x, y];
}
const base = (y) => (y >= 15 ? 'T' : 'g');
const sp = fix(spawn[0], spawn[1], 'd');
const fixAll = (list) => list.map((e) => { const b = e[0] === 'elder' || e[0] === 'merchant' || e[0] === 'farmer' ? e : [null, ...e]; const [x, y] = fix(b[1], b[2], base(b[2])); return b[0] ? [b[0], x, y] : [x, y]; });
const npcsFixed = fixAll(npcs);
const herbsFixed = fixAll(herbs);
const chestsFixed = fixAll(chests);
const slimesFixed = fixAll(slimes);

const grid = g.map((row) => row.join(''));
const json = {
  width: W, height: H, tile: 16, grid,
  spawn: sp, npcs: npcsFixed, herbs: herbsFixed, chests: chestsFixed, slimes: slimesFixed,
};
fs.writeFileSync(path.join(OUT, 'map_village.json'), JSON.stringify(json, null, 1));
console.log('map written: rows=' + grid.length + ' cols=' + grid[0].length);
console.log(grid.slice(0, 13).join('\n'));
