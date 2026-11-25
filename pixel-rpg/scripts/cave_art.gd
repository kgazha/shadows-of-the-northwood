class_name CaveArt
extends RefCounted
## c3 «Пещера v1»: интеграция кодоген-арта пещеры по вердикту пользователя
## «1 внедряем; 2 сундук широкий» (docs/PIXEL_STYLE.md, docs/SCALE_CANON.md).
##
## Единственный источник арта — КОД-ГЕН атласы листа «Пещера v1», запечённые
## res://tools_art/sheet_cave.gd (режим bake, генератор cave_paint.gd):
##   assets/cave/cave_floor_v1.png — пол 16 px (обычный/трещины/у алтаря/мох),
##   assets/cave/cave_wall_v1.png  — стена 16 px (тело/свод/подошва/углы L,R),
##   assets/cave/cave_props_v1.png — пропы (алтарь 13×25, сундук 26×13 ~0.8H
##                                   (вердикт c10 «сундук уменьши»),
##                                   сталактиты/сталагмиты 0.5/0.75/1.2H,
##                                   факел 9×10 в 2 кадрах — c5,
##                                   арка входа 16×24 ~1.5H — c12).
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
##  - кострище-мох (BRAZIER) НЕ размещается: по вердикту c5 («факелы лучше»)
##    тёплый акцент пещеры — настенные факелы; кадр BRAZIER остаётся в атласе
##    неиспользуемым искус (пин qa_lp: в дереве пещеры его нет).

## Факел (c5 «факелы лучше» + «Среда v1» t11 вердикт 25.11): состав и
## расстановка прежние (TORCH_MAX <= 5/уровень, якоря сундук/вход/дверь/алтари);
## ПОВЕДЕНИЕ ИНВЕРТИРОВАННЫЙ ВЕРДИКТОМ: легаси «2 кадра + PointLight2D с
## пульсом» ЗАМЕНЁН на 4-кадровый ночной цикл листа (250 мс, пульс — модуляция
## тона внутри рампы FIRE, БЕЗ PointLight2D — gl_compatibility, свет у якорей
## факелов снят решением пользователя). Тик — счётчик кадров, не wall-time.
const TORCH_MAX := 5               # верх по составу (acceptance: 3..5)
const ENV := preload("res://scripts/env_art.gd")
## Порядок кандидатов вокруг якоря (сундук/вход/дверь/алтари): стена с
## проходимой клеткой под нею; кольцо радиуса 3 (стена алтарного зала стоит
## не ближе 2 клеток от «A»); фиксированный список => детерминизм без сида.
const TORCH_DIRS := [
	Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(0, -1), Vector2i(2, -1), Vector2i(-2, -1), Vector2i(2, 0),
	Vector2i(-2, 0), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(3, -1),
	Vector2i(-3, -1), Vector2i(3, 0), Vector2i(-3, 0), Vector2i(2, -2),
	Vector2i(-2, -2), Vector2i(3, -2), Vector2i(-3, -2), Vector2i(0, -2),
	Vector2i(0, -3),
]

const ATLAS_PATH := "res://assets/cave/cave_props_v1.png"
const FLOOR_PATH := "res://assets/cave/cave_floor_v1.png"
const WALL_PATH := "res://assets/cave/cave_wall_v1.png"
const P := preload("res://scripts/pixel_palette.gd")

## Регионы атласа пропов — alpha-trim кадры (лист 128×80). Ноги нижнего яруса
## на y=80, «с потолка» — ярусы сталактитов выровнены по своей верхней кромке.
const REGIONS := {
	"ALTAR": Rect2(0, 39, 13, 25),
	"CHEST": Rect2(14, 51, 26, 13),
	# c36 (вердикт c35 «пещерный сундук берём»): открытый кадр 26×15 — крышка
	# подъём 2 ряда, жерло 2 ряда, корпус байт-в-бит закрытого; новый ярус
	# атласа под CHEST (лист вырос 128×64 -> 128×80, сам CHEST не сдвинут)
	"CHEST_OPEN": Rect2(14, 65, 26, 15),
	"BRAZIER": Rect2(48, 47, 17, 17),
	"STALC3": Rect2(66, 45, 9, 19),
	"STALAG3": Rect2(76, 45, 13, 19),
	"STALC2": Rect2(89, 52, 7, 12),
	"STALAG2": Rect2(97, 52, 11, 12),
	"STALC1": Rect2(108, 56, 5, 8),
	"STALAG1": Rect2(114, 56, 9, 8),
	"TORCH1": Rect2(0, 25, 9, 10),
	"TORCH2": Rect2(10, 25, 9, 10),
	# c12: арка входа в подземелье (16×24 ~1.5H) — верхняя полоса атласа;
	# стопа кадра — нижняя граница региона (одна арка на обе стороны входа)
	"STAIRS": Rect2(20, 1, 16, 24),
}
const ATLAS_SIZE := Vector2i(128, 80)
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


## Целочисленный хэш с солью (тот же FNV-рецепт, что frac/hash_xy) — для
## детерминированного выбора соседей/скоростей в c7.
static func hash_salted(x: int, y: int, salt: int) -> int:
	return hash_xy(x * 31 + salt, y * 17 + salt * 7)


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


## Публичный доступ к канон-кадру региона (c12: арка входа ставится и в
## деревне (world.CaveStairs), и в пещере (dungeon_zone.ExitStairs)).
static func region_texture(key: String) -> AtlasTexture:
	return _region(load_atlas(), key)


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


## Детерминированная расстановка факелов (c5): якоря — сундук, вход, дверь
## (проходы в залы), затем алтари в порядке карты. Кандидат — стена '#' с
## проходимым («.»/»,») полом ПОД собой (факел висит на стене, пламя в
## клетке стены — проходимость не трогается). Фиксированный порядок якорей и
## направлений => бит-детерминизм без randi. Не более TORCH_MAX штук.
static func torch_slots(rows: Array, chest: Vector2i, spawn: Vector2i,
		door: Vector2i) -> Array:
	var anchors: Array = []
	if chest.x >= 0:
		anchors.append(chest)
	if spawn.x >= 0:
		anchors.append(spawn)
	if door.x >= 0:
		anchors.append(door)
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if row[x] == "A":
				anchors.append(Vector2i(x, y))
	var out: Array = []
	var used := {}
	for an in anchors:
		if out.size() >= TORCH_MAX:
			break
		for d in TORCH_DIRS:
			var m := Vector2i(int(an.x) + d.x, int(an.y) + d.y)
			if used.has(m):
				continue
			if char_at(rows, m.x, m.y) != "#":
				continue
			var below := char_at(rows, m.x, m.y + 1)
			if below != "." and below != ",":
				continue
			used[m] = true
			out.append(m)
			break
	return out


## «Среда v1» (25.11): _mk_torch_light/PointLight2D СНЯТЫ по вердикту —
## световой пульс живёт в тоне кадров листа (рампа FIRE), освещение у якорей
## факелов не ставим (gl_compatibility, без shader/Light2D).


## Факел-спрайт «Среда v1»: 4-кадровый НОЧНОЙ цикл листа (250 мс, пульс тона
## встроен в кадр), фаза — shash клетки, t — счётчик кадров зоны (не wall-time;
## вне пещеры зона PROCESS_MODE_DISABLED и тики стоят — картинка не «догоняется»).
## PointLight2D больше НЕТ (вердикт 25.11). Живёт и тикает только когда зона
## пещеры активна (PROCESS_MODE наследуется от зоны).
class TorchSprite:
	extends Sprite2D
	var strip: Texture2D
	var ph := 0
	var tick := 0
	var last := -1

	func _process(_delta: float) -> void:
		tick += 1
		var idx := CaveArt.ENV.cell_frame(tick, ph, CaveArt.ENV.T_TORCH, 4)
		if idx != last:
			last = idx
			texture = CaveArt.ENV.atlas_of(strip, idx, 10)


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
	# стопа на нижнюю границу клетки; состояние держат тайл 12 и снятие
	# фантома, а c36 (вердикт c35) добавляет и визуал вскрытия: амулет взят —
	# ставится открытый кадр CHEST_OPEN (группа для swaps в open_chest).
	# TILE-12 DISPOSITION B0 (25.11, реестр t2): «тайл 12» — легаси-слот атласа
	# пещеры, НЕ деревенский валун 12 (world.gd A) и не CAS_F1=12 (json C);
	# все три оставлены с датированным комментарием по решению капитана.
	if dz.chest_tile.x >= 0:
		var cfoot := Vector2(float(dz.chest_tile.x) * 16.0 + 8.0,
				float(dz.chest_tile.y + 1) * 16.0)
		var chest := _spr(layer, atlas,
				"CHEST_OPEN" if GameState.has_amulet else "CHEST", cfoot)
		chest.add_to_group("cave_chest_prop")
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
	# факелы (c5 «факелы лучше» + «Среда v1» 25.11): ночной 4-кадровый цикл
	# листа БЕЗ PointLight2D; кострище-мох не ставится (BRAZIER остаётся в
	# атласе неиспользуемым искусом — пин qa_lp «в дереве пещеры его нет»).
	var t_strip: Texture2D = ENV.strip_torch(true)
	for m in torch_slots(rows, dz.chest_tile, dz.spawn_tile, dz.door_tile):
		var t := TorchSprite.new()
		t.strip = t_strip
		t.ph = ENV.cell_phase(m.x, m.y, ENV.T_TORCH, 4)
		t.texture = ENV.atlas_of(t_strip, ENV.cell_frame(0, t.ph, ENV.T_TORCH, 4), 10)
		# «стопа» кронштейна на 2 px выше верхней границы проходимой клетки
		# под стеной: кадр листа 10x15 центрирован — нижняя граница рамки
		# кадра стоит на «стопе», всё пламя — выше головы идущего героя
		# (инвариант прежних 12-px кадров сохранён); z — общая шкала V-01 от
		# «стопы»; в дим-реестр НЕ идёт (на стене, героя не накрывает).
		var tbottom := float(m.y + 1) * 16.0 - 2.0
		t.position = Vector2(float(m.x) * 16.0 + 8.0, tbottom - 7.5)
		layer.add_child(t)
		world._ys_prop(t)
	# c7 микро-жизнь: медленные падающие пылинки в залах (чистая визуализация)
	_build_dust(world, layer)
	return layer


# ------------------------------------------------------------- c7 пылинки

## Пылинки: «зал» = 4-связная компонента клеток длинных (>= HALL_RUN_MIN)
## горизонтальных прогонов проходимого ('.'/',') — коридоры шире 3 отсекаются.
## На зал 2..4 пылинки (хэш зала), глобальный лимит DUST_MAX. Позиция каждой —
## чистая функция времени (fmod-цикл падения + синусный снос): ни накопления,
## ни randi; после отключения зоны не «догоняется». 1 px, CAVE_ROCK LIGHT,
## вне реестра дима (в воздухе, героя не накрывают), z шкалы V-01 от потолка
## зала — ПОД актёрами.
const HALL_RUN_MIN := 5
const DUST_MAX := 24

static var _dust_tex: ImageTexture = null


static func _dust_texture() -> ImageTexture:
	if _dust_tex == null:
		var im := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		im.set_pixel(0, 0, P.RAMPS["CAVE_ROCK"][P.T_LIGHT])
		_dust_tex = ImageTexture.create_from_image(im)
	return _dust_tex


## Залы карты: список {left,top,right,bottom} (в клетках). Детерминировано.
static func halls(rows: Array) -> Array:
	var marked := {}
	for y in rows.size():
		var row := String(rows[y])
		var x := 0
		while x < row.length():
			var run := 0
			while x + run < row.length() and (row[x + run] == "." or row[x + run] == ","):
				run += 1
			if run >= HALL_RUN_MIN:
				for k in run:
					marked[Vector2i(x + k, y)] = true
			x += maxi(run, 1)
	# 4-связные компоненты
	var seen := {}
	var out: Array = []
	for c0 in marked:
		if seen.has(c0):
			continue
		var stack: Array = [c0]
		var comp: Array = []
		seen[c0] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n2: Vector2i = c + d
				if marked.has(n2) and not seen.has(n2):
					seen[n2] = true
					stack.append(n2)
		var l := 1 << 30
		var t0 := 1 << 30
		var r := -(1 << 30)
		var b := -(1 << 30)
		for c: Vector2i in comp:
			l = mini(l, c.x)
			r = maxi(r, c.x)
			t0 = mini(t0, c.y)
			b = maxi(b, c.y)
		if r - l + 1 >= HALL_RUN_MIN and b - t0 + 1 >= 5 and comp.size() >= 30:
			out.append({"left": l, "top": t0, "right": r, "bottom": b})
	out.sort_custom(func(a2, b2):
		var at := int(a2["top"])
		var bt := int(b2["top"])
		if at != bt:
			return at < bt
		return int(a2["left"]) < int(b2["left"])
	)
	return out


static func _build_dust(world, layer: Node2D) -> void:
	var hl: Array = halls(world.dungeon_zone.map_rows)
	if hl.is_empty():
		return
	var mgr: CaveDustLayer = CaveDustLayer.new()
	mgr.name = "CaveDust"
	layer.add_child(mgr)
	var total := 0
	for hi in hl.size():
		var hall: Dictionary = hl[hi]
		var n := 2 + absi(hash_salted(int(hall["left"]), int(hall["top"]), 71)) % 3  # 2..4
		for k in n:
			if total >= DUST_MAX:
				return
			var seedx := absi(hash_salted(int(hall["left"]) + k, int(hall["top"]) * 3 + hi, 83))
			var w_cells: int = int(hall["right"]) - int(hall["left"]) + 1
			var x0 := (float(hall["left"]) + float(seedx % w_cells)) * 16.0 + 8.0
			var top := float(hall["top"]) * 16.0
			var hh := float(int(hall["bottom"]) - int(hall["top"]) + 1) * 16.0
			var spr := Sprite2D.new()
			spr.texture = _dust_texture()
			spr.modulate = Color(1.0, 1.0, 1.0, 0.85)
			spr.z_as_relative = false
			spr.z_index = int(round(fposmod(top, float(world.YS_CYCLE))))
			mgr.add_child(spr)
			mgr.motes.append({
				"spr": spr, "x": x0, "top": top, "h": hh,
				"spd": 3.0 + float(seedx % 4),                 # 3..6 px/с — медленно
				"ph": float((seedx >> 4) % 1000) / 1000.0,
			})
			total += 1


class CaveDustLayer:
	extends Node2D
	## Падение: y = top + fmod(t*spd + ph*h, h) — бесшовный цикл без
	## накопления; снос: x = x0 + sin(t*0.4 + ph*2PI)*1.2. Всё детерминировано.
	var motes: Array = []

	func _process(_delta: float) -> void:
		var tt := float(Time.get_ticks_msec()) / 1000.0
		for m in motes:
			var y := float(m["top"]) + fmod(tt * float(m["spd"]) + float(m["ph"]) * float(m["h"]),
					float(m["h"]))
			var x := float(m["x"]) + sin(tt * 0.4 + float(m["ph"]) * TAU) * 1.2
			m["spr"].position = Vector2(x, y)


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
