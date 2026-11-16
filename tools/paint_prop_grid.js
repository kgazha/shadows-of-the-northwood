// tools/paint_prop_grid.js — t58: клеточная сетка приводится в согласие с
// физическим коллайдером пропа. Правка in-place по принятой map_village.json
// (прецедент инструментов отрисовки paint_*), а НЕ перезапуском gen_map.js:
// генератор устарел — в нём нет куртины «G» (c9), восточной дороги row20 и
// аршины «A», планировка леса правилась обходами d07c86a/4eb485c; его запуск
// сносит принятую планировку и ломает пины qa_vlg.
//
// Что чинит (пункт 2 t58). Блок «избы» W/R/D = 6×4 = 24 клетки: сетка считает
// их стеной для BFS мобов, обходов «усов», маркеров и миникарты, но с t54
// физика стоит под спрайтом избы: VillageArt HUT_SOLID 35×32, стопа
// hut_foot = ((6 + 6·0.5)·16, (3 + 4)·16) = (144, 112) → прямоугольник
// x 126.5..161.5, y 80..112. Целиком внутрь него попадают только 4 клетки:
// (8,5),(9,5),(8,6),(9,6). Остальные 20 (82 % площади блока) были «невидимой
// скалой» посреди луга: моб их обходит, герой там проходит.
// Картинку правка не меняет: W/R/D рисуются тем же слотом пола, что и «g»
// (world.gd:313-316 — «под ними обычная трава»), поэтому для тайлмапа замена
// байтово нейтральна.
//
// Файл правится точечно: заменяются только строки сетки, остальной JSON (порядок
// ключей, отступы, ручные правки спавнов) остаётся байт-в-байт. Инструмент
// идемпотентен: повторный запуск ничего не меняет.
'use strict';
const fs = require('fs'), path = require('path');

// Зеркало pixel-rpg/scripts/village_art.gd: HUT_BLOCK + HUT_SOLID + стоп-логика
// hut_foot. Клетки выводятся из геометрии, а не хардкодом: если арт изменится,
// инструмент пересчитает footprint сам.
const HUT_BLOCK = { x: 6, y: 3, w: 6, h: 4 };
const HUT_SOLID = { w: 35, h: 32 };
const TILE = 16;
const foot = {
  x: (HUT_BLOCK.x + HUT_BLOCK.w * 0.5) * TILE,
  y: (HUT_BLOCK.y + HUT_BLOCK.h) * TILE,
};
const rect = { x0: foot.x - HUT_SOLID.w / 2, x1: foot.x + HUT_SOLID.w / 2, y0: foot.y - HUT_SOLID.h, y1: foot.y };
const DOOR = [8, 6];                      // «D» остаётся на своей клетке

const MAP = path.join(__dirname, '..', 'pixel-rpg', 'data', 'map_village.json');
const raw = fs.readFileSync(MAP, 'utf8');
const json = JSON.parse(raw);
const W = json.width, H = json.height;
const rows = json.grid.slice();

const solidCells = [];
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const x0 = x * TILE, y0 = y * TILE;
    if (x0 >= rect.x0 - 1e-9 && x0 + TILE <= rect.x1 + 1e-9 &&
        y0 >= rect.y0 - 1e-9 && y0 + TILE <= rect.y1 + 1e-9) solidCells.push([x, y]);
  }
}
if (!solidCells.length) throw new Error('под коллайдером нет ни одной целой клетки — проверьте константы');

const target = rows.slice();
for (let y = HUT_BLOCK.y; y < HUT_BLOCK.y + HUT_BLOCK.h; y++) {
  let r = target[y].split('');
  for (let x = HUT_BLOCK.x; x < HUT_BLOCK.x + HUT_BLOCK.w; x++) r[x] = 'g';
  target[y] = r.join('');
}
for (const [x, y] of solidCells) {
  const r = target[y].split('');
  r[x] = (x === DOOR[0] && y === DOOR[1]) ? 'D' : 'W';
  target[y] = r.join('');
}

const changes = [];
for (let y = 0; y < H; y++) {
  if (rows[y] === target[y]) continue;
  const a = rows[y].split(''), b = target[y].split('');
  for (let x = 0; x < W; x++) if (a[x] !== b[x]) changes.push(`(${x},${y}) ${a[x]}->${b[x]}`);
  rows[y] = target[y];
}
if (!changes.length) {
  console.log('paint_prop_grid: сетка уже согласована с коллайдером избы — файл не изменён (идемпотентно)');
  process.exit(0);
}

// Точечная замена строк сетки построчно (по индексу строки, а не поиском: строки
// в сетке повторяются): отступ и запятая сохраняются, остальной файл — порядок
// ключей, отступы, ручные правки спавнов — не трогается.
const lines = raw.split('\n');
let done = 0, inGrid = false, rowIdx = 0;
for (let i = 0; i < lines.length && rowIdx < H; i++) {
  if (!inGrid) { if (lines[i].includes('"grid"')) inGrid = true; continue; }
  const m = lines[i].match(/^(\s*)"([A-Za-z.#]+)"(,?)\s*$/);
  if (!m) continue;
  if (m[2] === json.grid[rowIdx] && m[2] !== rows[rowIdx]) {
    lines[i] = m[1] + JSON.stringify(rows[rowIdx]) + m[3];
    done++;
  }
  rowIdx++;
}
if (done === 0) throw new Error('ни одна строка сетки не заменена — формат файла не распознан');
const out = lines.join('\n');
fs.writeFileSync(MAP, out);
const wCount = rows.join('').split('').filter((c) => c === 'W' || c === 'D').length;
console.log('paint_prop_grid: клеток под коллайдером избы ' + solidCells.length + ' (было 24), правок ' +
  changes.length + '; всего W/D в карте ' + wCount);
console.log(changes.join('\n'));
