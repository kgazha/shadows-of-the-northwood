class_name CaveArt
extends RefCounted
## c3 «Пещера v1»: интеграция кодоген-арта пещеры по вердикту пользователя
## «1 внедряем; 2 сундук широкий» (docs/PIXEL_STYLE.md, docs/SCALE_CANON.md).
##
## Единственный источник арта — КОД-ГЕН атласы листа «Пещера v1», запечённые
## res://tools_art/sheet_cave.gd (режим bake, генератор cave_paint.gd):
##   assets/cave/cave_floor_v1.png — пол 16 px (обычный/трещины/у алтаря/мох),
##   assets/cave/cave_wall_v1.png  — стена 16 px (тело/свод/подошва/углы L,R),
##   assets/cave/cave_props_v1.png — пропы (алтарь 13×25, широкий сундук 33×16,
##                                   сталактиты/сталагмиты 0.5/0.75/1.2H).
## REGIONS — источник истины и для игры, и для bake-режима инструмента; кадры
## alpha-trim’лены до силуэта (аудит c2 F2), стопа на нижней границе кадра.
##
## Инварианты (пин qa_lp T16):
##  - сетка map_cave.json, CHAR_TO_TILE/BLOCKING, коллайдеры и BFS — бит-в-бит:
##    новые тайл-источники меняют ТОЛЬКО рисунок клетки (source/coords),
##    «C» остаётся клеточным коллайдером — широкий сундук это визуальный слой;
##  - направленные кромки стены (подошва/углы) ставятся однократно по
##    соседям и по вертикали не повторяются (аудит c2 F4);
##  - глубина — общая шкала V-01: пропы в реестр дима _ys_props_dim, стопа на
##    нижней границе якорной клетки; сталактиты — осознанное исключение:
##    висят НАД актёров (z = Z_STALC), т.к. это «потолок» и он обязан
##    перекрывать проходящего героя (вердикт/указание капитана);
##  - размещение детерминировано FNV-1a по клетке (копия world._env4_hash),
##    randi нет — мир воспроизводится бит-в-бит;
##  - кострище-мох (BRAZIER) НЕ размещается: акцент ждёт отдельного вердикта.

const ATLAS_PATH := "res://assets/cave/cave_props_v1.png"
const FLOOR_PATH := "res://assets/cave/cave_floor_v1.png"
const WALL_PATH := "res://assets/cave/cave_wall_v1.png"

## Регионы атласа пропов — alpha-trim кадры (лист 128×64). Ноги нижнего яруса
## на y=64, «с потолка» — ярусы сталактитов выровнены по своей верхней кромке.
const REGIONS := {
	"ALTAR": Rect2(0, 39, 13, 25),
	"CHEST": Rect2(14, 48, 33, 16),
	"BRAZIER": Rect2(48, 47, 17, 17),
	"STALC3": Rect2(66, 45, 9, 19),
	"STALAG3": Rect2(76, 45, 13, 19),
	"STALC2": Rect2(89, 52, 7, 12),
	"STALAG2": Rect2(97, 52, 11, 12),
	"STALC1": Rect2(108, 56, 5, 8),
	"STALAG1": Rect2(114, 56, 9, 8),
}
const ATLAS_SIZE := Vector2i(128, 64)
const FLOOR_SIZE := Vector2i(64, 16)
const WALL_SIZE := Vector2i(80, 16)

## Слоты тайл-атласов (индекс = порядковый номер в cave_paint*_tile_set).
const F_TILES := 4      # 0 пол, 1 трещины, 2 у алтаря, 3 мох
const W_TILES := 5      # 0 тело, 1 свод, 2 подошва, 3 угол L, 4 угол R
const S_FLOOR := 0
const S_CRACK := 1
const S_ALTAR := 2
const S_MOSS := 3
const W_BODY := 0
const W_TOP := 1
const W_BOT := 2
const W_CORNER_L := 3
const W_CORNER_R := 4

## Тайл-источники пещерного tilemap’а: 0 — легаси-dungeon_tiles (дверь/лестницы/
## отшельник/босс/состояния сундука), 1 — пол v1, 2 — стена v1.
const SRC_LEGACY := 0
const SRC_FLOOR := 1
const SRC_WALL := 2

## Сталактиты — «потолок»: z выше максимального z актёров любой зоны
## (max ≈ высота зоны 480 + bias); осознанное исключение из V-01 по вердикту.
const Z_STALC := 1024

## Плотности размещения (доли, FNV-хэш по клетке — детерминизм без randi).
const P_MOSS := 0.12      # мшистая плитка среди обычного пола
const P_STALC := 0.30     # сталактит под сводом (клетка '#' с полом снизу)
const P_STALAG := 0.20    # сталагмит на полу под сводом

## Копия FNV-1a из world._env4_hash (каноническая копия — паттерн procgen):
## мир воспроизводится бит-в-бит, randi не используется.
static func hash_xy(x: int, y: int) -> int:
	var h := 2166136261
	for b in [x & 0xFF, (x >> 8) & 0xFF, y & 0xFF, (y >> 8) & 0xFF]:
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return h


static func frac(x: int, y: int, salt: int) -> float:
	return float(hash_xy(x * 31 + salt, y * 17 + salt * 7)) / 4294967295.0


## Символ карты ("" — за рамками/за длиной строки). rows — Array[String].
static func char_at(rows: Array, x: int, y: int) -> String:
	if y < 0 or y >= rows.size():
		return ""
	var row := String(rows[y])
	if x < 0 or x >= row.length():
		return ""
	return row[x]


static func is_solid_wall(rows: Array, x: int, y: int) -> bool:
	return char_at(rows, x, y) == "#"


## Слот стены v1 по соседям (только визуальная вариация; геометрия не меняется):
## подошва/углы — направленные кромки, ставятся однократно => по вертикали не
## повторяются (аудит c2 F4: WALL_BOT/CORNER_* только на открытой грани).
static func wall_slot(rows: Array, x: int, y: int) -> int:
	if not is_solid_wall(rows, x, y + 1):
		return W_BOT                    # низ массива (над проходимой клеткой)
	if not is_solid_wall(rows, x, y - 1):
		return W_TOP                    # свод (под проходимой клеткой сверху)
	if not is_solid_wall(rows, x + 1, y):
		return W_CORNER_L               # массив слева, пол справа
	if not is_solid_wall(rows, x - 1, y):
		return W_CORNER_R               # массив справа, пол слева
	return W_BODY


## Слот пола v1 для клетки с индексами CHAR_TO_TILE idx ∈ {0,1,10,11,12}.
static func floor_slot(rows: Array, x: int, y: int, idx: int) -> int:
	if idx == S_CRACK:
		return S_CRACK
	if idx == 10 or idx == 11 or idx == 12:  # алтарь/сундук (закрыт/открыт)
		return S_ALTAR
	# обычный пол: кольцо освящённых плит вокруг алтаря, иначе редкий мох
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if char_at(rows, x + dx, y + dy) == "A":
				return S_ALTAR
	if frac(x, y, 11) < P_MOSS:
		return S_MOSS
	return S_FLOOR


## Пол должен быть доступен построителю тайлмапа как «есть ли v1-атласы».
static func have_art() -> bool:
	return ResourceLoader.exists(FLOOR_PATH) and ResourceLoader.exists(WALL_PATH)


static func load_atlas() -> Texture2D:
	return load(ATLAS_PATH)


static func _region(atlas: Texture2D, key: String) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = atlas
	at.region = REGIONS[key]
	at.filter_clip = true  # LINEAR-мир: не хватать пиксели соседей по атласу
	return at


## Спрайт с стопой (нижним краем) в foot; центр — геометрия региона.
static func _spr(parent: Node2D, atlas: Texture2D, key: String, foot: Vector2) -> Sprite2D:
	var at := _region(atlas, key)
	var spr := Sprite2D.new()
	spr.texture = at
	spr.position = Vector2(foot.x, foot.y - float(at.get_size().y) * 0.5)
	parent.add_child(spr)
	return spr


## Строит слой CaveV1 в контейнере пещеры; возвращает слой (или null, если
## v1-атласов нет — игра остаётся на легаси-dungeon_tiles). world — мир
## (duck-typed): нужны cave_zone, dungeon_zone, _ys_prop(), _ys_props_dim.
static func build(world) -> Node2D:
	var dz = world.dungeon_zone
	if dz == null or not have_art():
		return null
	var layer := Node2D.new()
	layer.name = "CaveV1"
	world.cave_zone.add_child(layer)
	var atlas := load_atlas()
	var rows: Array = dz.map_rows
	# алтари: стопа на нижнюю границу клетки 'A' (1.6H, SCALE_CANON)
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if row[x] != "A":
				continue
			var foot := Vector2(float(x) * 16.0 + 8.0, float(y + 1) * 16.0)
			var altar := _spr(layer, atlas, "ALTAR", foot)
			world._ys_prop(altar)
			world._ys_props_dim.append(altar)
	# широкий сундук поверх стандартного клеточного коллайдера «C»:
	# стопа на нижнюю границу клетки; в открытом состоянии (амулет взят)
	# визуал не меняется — состояние держат тайл 12 и снятие фантома.
	if dz.chest_tile.x >= 0:
		var cfoot := Vector2(float(dz.chest_tile.x) * 16.0 + 8.0,
				float(dz.chest_tile.y + 1) * 16.0)
		var chest := _spr(layer, atlas, "CHEST", cfoot)
		world._ys_prop(chest)
		world._ys_props_dim.append(chest)
	# декор свода: сталагмиты (на полу под «#», в реестр дима) и сталактиты
	# (под сводом, над актёров). Ярусы 0.5/0.75/1.2H — по хэшу клетки.
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			var ch := row[x]
			if (ch == "." or ch == ",") and is_solid_wall(rows, x, y - 1) \
					and ch != "" and frac(x, y, 3) < P_STALAG:
				var gfoot := Vector2(float(x) * 16.0 + 8.0, float(y + 1) * 16.0)
				var gkey := _stalag_key(x, y)
				var g := _spr(layer, atlas, gkey, gfoot)
				world._ys_prop(g)
				world._ys_props_dim.append(g)
			elif ch == "#" and _floorish(char_at(rows, x, y + 1)) \
					and frac(x, y, 5) < P_STALC:
				var ckey := _stalc_key(x, y)
				var at := _region(atlas, ckey)
				var c := Sprite2D.new()
				c.texture = at
				# висит с верхней границы клетки свода, остриём вниз
				c.position = Vector2(float(x) * 16.0 + 8.0,
						float(y) * 16.0 + float(at.get_size().y) * 0.5)
				c.z_as_relative = false
				c.z_index = Z_STALC
				layer.add_child(c)
	return layer


static func _floorish(ch: String) -> bool:
	return ch == "." or ch == "," or ch == "A" or ch == "C"


static func _stalag_key(x: int, y: int) -> String:
	var r := frac(x, y, 13)
	if r < 0.55:
		return "STALAG1"
	if r < 0.85:
		return "STALAG2"
	return "STALAG3"


static func _stalc_key(x: int, y: int) -> String:
	var r := frac(x, y, 17)
	if r < 0.55:
		return "STALC1"
	if r < 0.85:
		return "STALC2"
	return "STALC3"
