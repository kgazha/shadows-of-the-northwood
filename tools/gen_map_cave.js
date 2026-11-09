// Генератор карты пещеры «Осквернение» -> pixel-rpg/data/map_cave.json
// Формат тот же, что у gen_map.js: {width, height, tile, grid, spawn, ...}.
// Буквы тайлов: "."=stone_floor(0) ","=floor_crack(1) "#"=stone_wall(2) "L"=door_locked(3)
// "S"=stairs_out(5) "P"=pillar(6) "R"=rubble(7) "B"=bones(8) "M"=mushroom(9)
// "A"=altar(10) "C"=chest_big_closed(11) "V"=void_black(15)
'use strict';
const fs = require('fs'), path = require('path');
const W = 30, H = 22;
const OUT = path.join(__dirname, '..', 'pixel-rpg', 'data');
fs.mkdirSync(OUT, { recursive: true });

// детерминированный шум (тот же, что в gen_map.js)
const nz = (x, y, a, b, m) => (((x * 7 + a) * (y * 13 + b) + x * 3 + y * 11) % m + m) % m;

// 1. фон — пустота
const g = Array.from({ length: H }, () => Array(W).fill('V'));
const set = (x, y, ch) => { g[y][x] = ch; };
const room = (x0, y0, x1, y1) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(x, y, '.'); };
const carve = (list) => list.forEach(([x, y]) => set(x, y, '.'));

// 2. помещения и коридоры
room(12, 1, 17, 4);                                    // входная камера (север)
carve([[13, 5], [13, 6], [12, 6], [12, 7], [12, 8], [13, 8]]); // извилистый спуск от камеры
for (let x = 14; x <= 21; x++) set(x, 8, '.');         // восточный коридор -> отшельник
room(22, 6, 27, 12);                                   // комната отшельника
for (let x = 10; x <= 11; x++) set(x, 8, '.');         // западная ветка от развилки
carve([[10, 9], [10, 10], [10, 11], [10, 12], [11, 12], [11, 13]]); // спуск к алтарному залу
room(5, 14, 20, 19);                                   // алтарный зал

// 3. ключевые точки
const spawn = [13, 2];
const stairs_out = [13, 1];                            // лестница обратно в деревню (север камеры)
const hermit = [24, 9];                                // отшельник у грибов
const boss = [12, 16];                                 // босс в центре алтарного зала — ДОСТУПЕН БЕЗ КЛЮЧА
const boss_trigger = [11, 14];                         // вход в зал — триггер "boss_intro"
const chest = [18, 18];                                // сундук в ЗАПЕРТОЙ НИШЕ восточнее алтаря
const doors = [[17, 18]];                              // запертая дверь "L" — только в нишу сундука
// NOTE: дверь НЕ должна перекрывать вход в алтарный зал — ключ выдаётся за убийство
// босса, и если босс заперт вместе с сундуком, финаль недостижим (deadlock).

set(stairs_out[0], stairs_out[1], 'S');
doors.forEach(([x, y]) => set(x, y, 'L'));
[[12, 19], [13, 19], [14, 19]].forEach(([x, y]) => set(x, y, 'A')); // алтарь (южная стена зала)
set(chest[0], chest[1], 'C');

// 3б. ниша сундука: стена севернее и западнее, вход — дверь (17,18)
[[17, 17], [19, 17], [20, 17], [17, 19]].forEach(([x, y]) => set(x, y, '#'));

// 4. декор: колонны и завалы непроходимы, кости и грибы — проходимы
[[7, 15], [7, 17], [18, 15], [18, 17]].forEach(([x, y]) => set(x, y, 'P'));
[[5, 14], [5, 19], [20, 19], [22, 6], [16, 3]].forEach(([x, y]) => set(x, y, 'R'));
[[8, 16], [15, 17], [6, 18], [19, 15], [24, 7], [13, 3]].forEach(([x, y]) => set(x, y, 'B'));
[[26, 6], [26, 8], [26, 10], [23, 12], [25, 12]].forEach(([x, y]) => set(x, y, 'M'));

// трещины в полу
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++)
  if (g[y][x] === '.' && nz(x, y, 3, 5, 7) === 0) set(x, y, ',');

// 5. каменные стены: пустота, граничащая с проходимой клеткой, становится "#"
const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  if (g[y][x] !== 'V') continue;
  const nearOpen = dirs.some(([dx, dy]) => {
    const nx = x + dx, ny = y + dy;
    return nx >= 0 && ny >= 0 && nx < W && ny < H && g[ny][nx] !== 'V' && g[ny][nx] !== '#';
  });
  if (nearOpen) g[y][x] = '#';
}

// 6. валидация: проходимость и связность (образец fix() из gen_map.js)
// непроходимые тайлы (совпадает с BLOCKING в dungeon_zone.gd); запертая дверь "L"
// считается проходимой — иначе сундук за дверью никогда не «пройдёт» валидацию
const SOLID = new Set(['V', '#', 'P', 'R', 'A', 'C']);
const walk = (x, y) => x >= 0 && y >= 0 && x < W && y < H && !SOLID.has(g[y][x]);
function fix(x, y, name) {
  if (walk(x, y)) return [x, y];
  for (let r = 1; r <= 4; r++)
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
      const nx = x + dx, ny = y + dy;
      if (walk(nx, ny)) { console.log('fix: точка ' + name + ' сдвинута в ' + nx + ',' + ny); return [nx, ny]; }
    }
  throw new Error('fix: нет проходимой точки рядом с ' + name + ' (' + x + ',' + y + ')');
}
function bfs(sx, sy) {
  const seen = new Set([sx + ',' + sy]);
  const q = [[sx, sy]];
  while (q.length) {
    const [x, y] = q.shift();
    for (const [dx, dy] of dirs) {
      const nx = x + dx, ny = y + dy, k = nx + ',' + ny;
      if (!seen.has(k) && walk(nx, ny)) { seen.add(k); q.push([nx, ny]); }
    }
  }
  return seen;
}
const sp = fix(spawn[0], spawn[1], 'spawn');
const hermitF = fix(hermit[0], hermit[1], 'hermit');
const bossF = fix(boss[0], boss[1], 'boss');
const trigF = fix(boss_trigger[0], boss_trigger[1], 'boss_trigger');
const stairsF = fix(stairs_out[0], stairs_out[1], 'stairs_out');
const reach = bfs(sp[0], sp[1]);
[['spawn', sp], ['hermit', hermitF], ['boss', bossF], ['boss_trigger', trigF], ['stairs_out', stairsF]]
  .forEach(([name, [x, y]]) => {
    if (!reach.has(x + ',' + y)) throw new Error('Недостижимо от спавна: ' + name + ' (' + x + ',' + y + ')');
  });
// РЕГРЕССИЯ deadlock: с ЗАКРЫТОЙ дверью босс, герой и выход обязаны быть достижимы
// (ключ — награда за босса, поэтому путь к боссу не может вести через дверь).
{
  const saved = doors.map(([x, y]) => { const c = g[y][x]; g[y][x] = '#'; return [x, y, c]; });
  const reachClosed = bfs(sp[0], sp[1]);
  for (const [name, [x, y]] of [['boss', bossF], ['boss_trigger', trigF], ['hermit', hermitF], ['stairs_out', stairsF]]) {
    if (!reachClosed.has(x + ',' + y)) throw new Error('DEADLOCK: ' + name + ' недостижим с закрытой дверью (' + x + ',' + y + ')');
  }
  saved.forEach(([x, y, c]) => { g[y][x] = c; });
}
{ // сундук сам по себе непроходим — проверим, что к нему можно подойти
  const ok = dirs.some(([dx, dy]) => {
    const nx = chest[0] + dx, ny = chest[1] + dy;
    return walk(nx, ny) && reach.has(nx + ',' + ny);
  });
  if (!ok) throw new Error('Нельзя подойти к сундуку (' + chest[0] + ',' + chest[1] + ')');
}

const grid = g.map((row) => row.join(''));
const json = {
  width: W, height: H, tile: 16, grid,
  spawn: sp, stairs_out: stairsF, hermit: hermitF, boss: bossF,
  boss_trigger: trigF, chest, door: doors,
};
fs.writeFileSync(path.join(OUT, 'map_cave.json'), JSON.stringify(json, null, 1));
console.log('cave map written: rows=' + grid.length + ' cols=' + grid[0].length);
console.log(grid.join('\n'));
