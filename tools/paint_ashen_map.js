// paint_ashen_map.js — рисует data/map_ashen.json для зоны «Пепелище».
// Сетка 40x30; тайл-логика ashen_zone.gd: '.'',''c''a' — пол, 'T','K','#' —
// блокировщики, 'P' — портал. Детерминированный шум (nz), коридоры и арены
// заданы вручную; на выходе — JSON с meta (spawn/portal/boss/mobs/chests/herbs).
'use strict';
const fs = require('fs');
const path = require('path');
const W = 40, H = 30;
function nz(x, y, n) { let v = (x * 2654435761 + y * 40503) % 9973; v = (v * 13 + 7) % 65521; return v % n; }
const g = [];
for (let y = 0; y < H; y++) g.push(new Array(W).fill('.'));

// --- каёмка: глухая стена мёртвых деревьев + второй подряд вразброс ---
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  if (x === 0 || y === 0 || x === W - 1 || y === H - 1) g[y][x] = 'T';
  else if ((x === 1 || y === 1 || x === W - 2 || y === H - 2) && nz(x, y, 2) === 0)
    g[y][x] = ['T', 'T', 'K', '#'][nz(x + 3, y + 7, 4)];
}

// --- пятна осыпи и трещин ---
const blobs = [
  [10, 6, 5, 3, ','], [30, 5, 6, 3, ','], [36, 15, 3, 5, ','],
  [14, 24, 6, 3, ','], [22, 19, 4, 2, 'c'], [8, 10, 3, 3, 'c'], [34, 25, 4, 2, 'c'],
];
for (const [cx, cy, rx, ry, ch] of blobs)
  for (let y = cy - ry; y <= cy + ry; y++) for (let x = cx - rx; x <= cx + rx; x++) {
    if (x < 2 || y < 2 || x > W - 3 || y > H - 3) continue;
    const dx = (x - cx) / rx, dy = (y - cy) / ry;
    if (dx * dx + dy * dy <= 1 && g[y][x] === '.' && nz(x * 5, y * 7, 4) !== 0) g[y][x] = ch;
  }

// --- редкий лес внутри ---
for (let y = 3; y < H - 3; y++) for (let x = 3; x < W - 3; x++) {
  if (g[y][x] !== '.') continue;
  const r = nz(x * 11 + 5, y * 17 + 3, 100);
  if (r < 7) g[y][x] = 'T';
  else if (r < 10) g[y][x] = 'K';
  else if (r === 10) g[y][x] = '#';
}

const clear = (x0, y0, x1, y1, ch) => {
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++)
    if (x > 0 && y > 0 && x < W - 1 && y < H - 1 && g[y][x] !== '.') g[y][x] = ch || '.';
};
const clearDot = (x0, y0, x1, y1) => clear(x0, y0, x1, y1, '.');

// --- западная поляна выхода + восточный коридор ---
clearDot(2, 13, 8, 17);          // поляна спавна
clearDot(9, 14, 21, 16);         // центральный коридор восток
clearDot(20, 8, 22, 14);         // северная тропа (лучник)
clearDot(15, 11, 17, 18);        // расщелина стаи (крысы)
clearDot(24, 20, 28, 28);        // южная дорога к поле сундука
clearDot(28, 22, 36, 24);        // подъезд к арене сундука
clearDot(31, 8, 36, 10);         // восточная тропа (тенеплёт/травы)

// --- арена Ведьмы: круг 'a' + частокол по краю, южный и западный входы ---
const A1 = [26, 14, 5.5];
for (let y = A1[1] - 7; y <= A1[1] + 7; y++) for (let x = A1[0] - 7; x <= A1[0] + 7; x++) {
  if (x < 2 || y < 2 || x > W - 3 || y > H - 3) continue;
  const d = Math.hypot(x - A1[0], y - A1[1]);
  if (d <= A1[2]) g[y][x] = 'a';
  else if (d <= A1[2] + 1.1 && nz(x * 3, y * 13, 3) !== 1) g[y][x] = ['T', 'K', '#'][nz(x, y, 3)];
}
clearDot(24, 19, 28, 21);        // южный вход
clearDot(18, 13, 21, 16);        // западный вход (слиян с коридором)
// --- арена сундука ---
const A2 = [30, 24, 3.2];
for (let y = A2[1] - 5; y <= A2[1] + 5; y++) for (let x = A2[0] - 5; x <= A2[0] + 5; x++) {
  if (x < 2 || y < 2 || x > W - 3 || y > H - 3) continue;
  const d = Math.hypot(x - A2[0], y - A2[1]);
  if (d <= A2[2]) g[y][x] = 'a';
  else if (d <= A2[2] + 1.0 && nz(x * 7, y * 5, 3) !== 1) g[y][x] = ['K', 'T'][nz(x, y, 2)];
}
clearDot(29, 19, 31, 21);        // северный вход

// --- POI: чистые клетки и маркеры ---
const put = (x, y, ch) => { g[y][x] = ch; };
put(2, 15, 'P'); put(5, 15, '.');
// гарантируем проходы у POI
for (const [x, y] of [[3, 15], [4, 15], [2, 14], [2, 16], [5, 14], [5, 16], [26, 14], [26, 13],
  [20, 8], [18, 22], [24, 23], [33, 23], [30, 24], [13, 12], [16, 11], [12, 17], [15, 18],
  [8, 20], [34, 9], [21, 26]]) if (g[y][x] !== 'P' && 'TK#'.includes(g[y][x])) g[y][x] = (y >= 11 && y <= 17 && x < 22) ? '.' : (Math.hypot(x - 26, y - 14) < 6 || Math.hypot(x - 30, y - 24) < 4 ? 'a' : '.');

// --- POI-лист (синхронно с meta) ---
const POI = {
  spawn: [5, 15],
  exit_portal: [2, 15],
  boss: [26, 13],
  chests: [[30, 24]],
  herbs: [[8, 20], [34, 9], [21, 26]],
  mobs: { archers: [[20, 8], [18, 22]], wraiths: [[24, 23], [33, 23]], swarm: [[13, 12], [16, 11], [12, 17], [15, 18]] },
};
// мобам нужен чистый пол под ногами и рядом — расчистить кресты
const flat = (x, y) => {
  for (const [dx, dy] of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]) {
    const nx = x + dx, ny = y + dy;
    if (nx > 0 && ny > 0 && nx < W - 1 && ny < H - 1 && 'TK#'.includes(g[ny][nx])) g[ny][nx] = '.';
  }
};
flat(...POI.spawn); flat(...POI.exit_portal); flat(...POI.boss);
for (const c of POI.chests) flat(...c);
for (const c of POI.herbs) flat(...c);
for (const k of Object.keys(POI.mobs)) for (const m of POI.mobs[k]) flat(...m);

// --- BFS-проверяемость от спавна до всех POI ---
const BLOCK = new Set(['T', 'K', '#']);
function bfs(sx, sy) {
  const seen = new Set([sx + ',' + sy]); const q = [[sx, sy]];
  while (q.length) {
    const [x, y] = q.shift();
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy, k = nx + ',' + ny;
      if (nx < 0 || ny < 0 || nx >= W || ny >= H || seen.has(k) || BLOCK.has(g[ny][nx])) continue;
      seen.add(k); q.push([nx, ny]);
    }
  }
  return seen;
}
const all = [POI.spawn, POI.exit_portal, POI.boss, ...POI.chests, ...POI.herbs];
for (const k of Object.keys(POI.mobs)) all.push(...POI.mobs[k]);
const seen = bfs(...POI.spawn);
const unreach = all.filter(([x, y]) => !seen.has(x + ',' + y));
if (unreach.length) { console.error('НЕДОСТУПНО из спавна:', JSON.stringify(unreach)); process.exit(1); }

const map = {
  width: W, height: H, tile: 16,
  grid: g.map(r => r.join('')),
  meta: {
    spawn: POI.spawn,
    exit_portal: POI.exit_portal,
    boss: POI.boss,
    chests: POI.chests,
    herbs: POI.herbs,
    mobs: POI.mobs,
  },
};
const out = path.join(__dirname, '..', 'sand_z2', 'pixel-rpg', 'data', 'map_ashen.json');
fs.writeFileSync(out, JSON.stringify(map, null, 1) + '\n');
console.log('wrote', out);
console.log(g.map(r => r.join('')).join('\n'));
