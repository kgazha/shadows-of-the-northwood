extends SceneTree
## Инструмент рисовки листа-вердикта «Пепелище v1» (волна c18; игра НЕ тронута).
## Детерминированный кодоген пиксель-спрайтов Пепелища в каноне «единый
## hand-made пиксель» (прецеденты: tools_art/sheet_cave.gd, sheet_village.gd).
##
## Состав листа:
##  - 4 тайла-пола 16×16 (зола / осыпь / трещины-угли / арена) — алфавит
##    ashen_zone.gd CHAR_TO_TILE 0..3 сохранён, бесшовность пин-метрикой;
##  - обгоревшие деревья 2 варианта (~1.5H=24 px, стопы-якорь) + пень + бревно
##    (блокировщики K/#/T: сетка и коллизии при интеграции НЕ меняются);
##  - пропы: угли (тлеющий акцент ASH_EMBER + FIRE_HOT-ядро), пепельный холм,
##    кость-куча, остов (ребра) — все по канону силуэта;
##  - c20 (вердикт «берём»): портал (слот 7) и сундук (слот 8) — свои кадры;
##    режим atlas печатает игровой атлас assets/ashen_tiles.png (bake_atlas):
##    строка 0 — ячейки 16×16 (полы 0–3 = кадры листа, 4–6 — подложки
##    блокировщиков, 7 портал, 8 сундук), строка 1 — высокие prop-кадры.
##
## Догфуд канона:
##  - единственный источник цвета — PixelPalette; самопроверка чистоты 0 off;
##    расширения палитры НЕТ (ASH_GROUND/CHAR/ASH_EMBER/BONE уже в ней);
##  - нижний ряд силуэта — только OUTLINE-тон (стопа-якорь y-sort);
##    подсветка СЕВЕРО-ЗАПАД (LIGHT в верхней половине);
##  - FIRE_HOT — одна горячая точка, только у углей (семейство огня);
##  - детерминизм: без randi, только FNV-хэш-шум с фиксированным сидом;
##    CONTENT-HASH (FNV-1a 32) каждого элемента и листа печатается.
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_ashen_v1.gd -- <out.png>
## Выход 0 — все самопроверки PASS.

const P := preload("res://scripts/pixel_palette.gd")
const SEED := 42
const SEAM_RATIO_MAX := 2.2

var _fails := 0
var _idx := {}

# ------------------------------------------------------------------ хэш-шум
static func _fnv32(s: int) -> int:
	# FNV-1a 32 на четырёх байтах входа (детерминированный, без randi)
	var h := 2166136261
	for i in 4:
		h = h ^ ((s >> (8 * i)) & 255)
		h = (h * 16777619) & 0x7FFFFFFF
	return h

static func _n2(x: int, y: int, salt: int) -> int:
	# период шума ровно 16 px: координаты по модулю 16 (циклический тайл)
	return _fnv32(x % 16 + 16 * (y % 16) + 256 * salt)

static func _hash_img(img: Image) -> String:
	var d := img.get_data()
	var h := 2166136261
	for i in d.size():
		h = h ^ int(d[i])
		h = (h * 16777619) & 0x7FFFFFFF
	return "%08X" % h

# ------------------------------------------------------------------ кисти
static func _img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func _pxl(img: Image, x: int, y: int, ramp: String, tone: int) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, P.c(ramp, tone))

static func _rectpx(img: Image, x0: int, y0: int, x1: int, y1: int, ramp: String, tone: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_pxl(img, x, y, ramp, tone)

static func _flat(img: Image, x: int, y: int, fname: String) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, P.FLATS[fname])

# ------------------------------------------------------------------ полы
static func _floor_ash() -> Image:
	# «.»: базовая зола — ASH_GROUND с пятнами осыпи и редким углём
	var img := _img(16, 16)
	for y in 16:
		for x in 16:
			var v := _n2(x, y, 1) % 100
			var ramp := "ASH_GROUND"
			var tone := P.T_MID
			if v < 14:
				tone = P.T_LIGHT
			elif v < 58:
				tone = P.T_MID
			elif v < 84:
				tone = P.T_DARK
			else:
				tone = P.T_MID
			if v >= 95:
				ramp = "CHAR"
				tone = P.T_DARK
			_pxl(img, x, y, ramp, tone)
	# мягкие «выбоины» — тёмные пятна 2px
	for k in 5:
		var px := _fnv32(1000 + k * 7) % 15
		var py := _fnv32(2000 + k * 11) % 15
		_pxl(img, px, py, "ASH_GROUND", P.T_DARK)
		_pxl(img, px + 1, py, "ASH_GROUND", P.T_DARK)
	return img

static func _floor_scree() -> Image:
	# «,»: осыпь — зола + щебень угля/костяной крошки
	var img := _floor_ash()
	for y in 16:
		for x in 16:
			var v := _n2(x, y, 2) % 100
			if v < 8:
				_pxl(img, x, y, "CHAR", P.T_MID)
			elif v >= 96:
				_pxl(img, x, y, "BONE", P.T_DARK)
	for k in 4:
		var px := _fnv32(3000 + k * 13) % 14
		var py := _fnv32(4000 + k * 17) % 14
		_pxl(img, px, py, "CHAR", P.T_DARK)
		_pxl(img, px + 1, py, "CHAR", P.T_OUTLINE)
		_pxl(img, px, py + 1, "CHAR", P.T_MID)
	return img

static func _floor_crack() -> Image:
	# «c»: трещины с тлением — УГОЛЬ, не лава: тонкая линия DARK/OUTLINE,
	# тлеющая точка внутри — ровно 1 px ASH_EMBER (минимум FIRE-семейства)
	var img := _floor_ash()
	var pts := [[2, 1], [3, 2], [4, 3], [5, 3], [6, 4], [6, 5], [7, 6], [8, 7],
		[9, 7], [10, 8], [10, 9], [11, 10], [12, 11], [13, 11], [14, 12], [14, 13], [15, 14]]
	for i in pts.size():
		var p: Array = pts[i]
		_pxl(img, p[0], p[1], "CHAR", P.T_DARK)
		_pxl(img, p[0], p[1] + 1, "CHAR", P.T_OUTLINE)
	_pxl(img, 7, 6, "CHAR", P.T_OUTLINE)
	_pxl(img, 10, 9, "ASH_EMBER", P.T_DARK)
	_pxl(img, 11, 10, "ASH_EMBER", P.T_MID)
	# короткая вторая трещина
	for q in [[0, 9], [1, 10], [1, 11], [2, 12], [3, 13]]:
		_pxl(img, q[0], q[1], "CHAR", P.T_DARK)
		_pxl(img, q[0], q[1] + 1, "CHAR", P.T_OUTLINE)
	return img

static func _floor_arena() -> Image:
	# «a»: вытоптанная арена — концентрические копоть/зола, циклично по 16
	var img := _img(16, 16)
	for y in 16:
		for x in 16:
			var v := _n2(x, y, 3) % 100
			_pxl(img, x, y, "ASH_GROUND", P.T_MID if v < 70 else P.T_DARK)
	var c := Vector2(8, 8)
	for y in 16:
		for x in 16:
			var d: float = Vector2(x, y).distance_to(c + Vector2(_n2(x, y, 4) % 3 - 1, _n2(x, y, 5) % 3 - 1))
			if d < 2.4:
				_pxl(img, x, y, "CHAR", P.T_DARK)
			elif d < 3.4:
				_pxl(img, x, y, "CHAR", P.T_MID)
			elif d < 4.4:
				_pxl(img, x, y, "ASH_GROUND", P.T_DARK)
			elif d > 5.4 and d < 6.2:
				_pxl(img, x, y, "ASH_GROUND", P.T_LIGHT)
	for k in 4:
		var px := _fnv32(5000 + k * 19) % 16
		var py := _fnv32(6000 + k * 23) % 16
		if Vector2(px, py).distance_to(c) > 4.4:
			_pxl(img, px, py, "CHAR", P.T_OUTLINE)
	return img

# ------------------------------------------------------------------ деревья/блоки
static func _tree1() -> Image:
	# обгоревшее дерево ~1.5H: ствол + расщеплённая крона, стопы-якорь OUTLINE
	var img := _img(16, 24)
	# ствол
	_rectpx(img, 6, 8, 9, 22, "CHAR", P.T_MID)
	for y in range(8, 23):
		_pxl(img, 6, y, "CHAR", P.T_LIGHT)     # СЗ-грань
		_pxl(img, 9, y, "CHAR", P.T_DARK)      # правая грань
	# основание-корни
	_rectpx(img, 4, 20, 5, 22, "CHAR", P.T_MID)
	_pxl(img, 3, 22, "CHAR", P.T_MID)
	_rectpx(img, 10, 21, 11, 22, "CHAR", P.T_DARK)
	# ветви (обломанные, вверх-в стороны)
	_rectpx(img, 3, 6, 4, 10, "CHAR", P.T_MID)
	_pxl(img, 3, 8, "CHAR", P.T_LIGHT)
	_pxl(img, 5, 9, "CHAR", P.T_MID)
	_pxl(img, 5, 10, "CHAR", P.T_MID)
	_rectpx(img, 11, 4, 12, 9, "CHAR", P.T_MID)
	_pxl(img, 12, 6, "CHAR", P.T_DARK)
	_pxl(img, 10, 8, "CHAR", P.T_MID)
	_pxl(img, 10, 9, "CHAR", P.T_MID)
	# верхушка-рожки
	_pxl(img, 6, 6, "CHAR", P.T_MID)
	_pxl(img, 7, 5, "CHAR", P.T_MID)
	_pxl(img, 8, 4, "CHAR", P.T_MID)
	_pxl(img, 8, 3, "CHAR", P.T_LIGHT)
	_pxl(img, 9, 6, "CHAR", P.T_MID)
	_pxl(img, 10, 5, "CHAR", P.T_DARK)
	_pxl(img, 7, 7, "CHAR", P.T_LIGHT)
	_pxl(img, 11, 4, "CHAR", P.T_LIGHT)
	_pxl(img, 3, 6, "CHAR", P.T_LIGHT)
	# пепельные «зубцы» кроны
	_pxl(img, 4, 5, "ASH_GROUND", P.T_DARK)
	_pxl(img, 12, 3, "ASH_GROUND", P.T_DARK)
	# стопы: нижний ряд строго OUTLINE
	for x in 16:
		for y in 24:
			if img.get_pixel(x, y).a > 0.5 and y == 22:
				img.set_pixel(x, y, P.c("CHAR", P.T_OUTLINE))
	_pxl(img, 4, 23, "CHAR", P.T_OUTLINE)
	_pxl(img, 5, 23, "CHAR", P.T_OUTLINE)
	_pxl(img, 6, 23, "CHAR", P.T_OUTLINE)
	_pxl(img, 7, 23, "CHAR", P.T_OUTLINE)
	_pxl(img, 8, 23, "CHAR", P.T_OUTLINE)
	_pxl(img, 9, 23, "CHAR", P.T_OUTLINE)
	_pxl(img, 10, 23, "CHAR", P.T_OUTLINE)
	_pxl(img, 11, 23, "CHAR", P.T_OUTLINE)
	return img

static func _tree2() -> Image:
	# Второй вариант: наклонённое раздвоенное дерево
	var img := _img(16, 24)
	# наклонный ступеньками ствол влево-вверх
	for y in range(10, 23):
		var x := 7 - int(float(y - 10) / 4.0)
		_pxl(img, x, y, "CHAR", P.T_LIGHT)
		_pxl(img, x + 1, y, "CHAR", P.T_MID)
		_pxl(img, x + 2, y, "CHAR", P.T_DARK)
	# основание
	_rectpx(img, 6, 21, 11, 22, "CHAR", P.T_MID)
	_pxl(img, 12, 22, "CHAR", P.T_DARK)
	# развилка наверху
	_rectpx(img, 2, 3, 3, 10, "CHAR", P.T_MID)
	_pxl(img, 2, 3, "CHAR", P.T_LIGHT)
	_pxl(img, 2, 6, "CHAR", P.T_LIGHT)
	_pxl(img, 3, 8, "CHAR", P.T_LIGHT)
	_rectpx(img, 6, 5, 7, 11, "CHAR", P.T_MID)
	_pxl(img, 6, 5, "CHAR", P.T_LIGHT)
	_pxl(img, 4, 10, "CHAR", P.T_MID)
	_pxl(img, 5, 11, "CHAR", P.T_MID)
	_pxl(img, 8, 9, "CHAR", P.T_DARK)
	_pxl(img, 8, 10, "CHAR", P.T_DARK)
	# обломанные сучья
	_pxl(img, 1, 5, "CHAR", P.T_DARK)
	_pxl(img, 4, 4, "CHAR", P.T_DARK)
	_pxl(img, 7, 4, "CHAR", P.T_LIGHT)
	_pxl(img, 6, 3, "CHAR", P.T_MID)
	_pxl(img, 9, 7, "CHAR", P.T_DARK)
	# пепельные зубцы
	_pxl(img, 2, 2, "ASH_GROUND", P.T_DARK)
	_pxl(img, 6, 2, "ASH_GROUND", P.T_DARK)
	# стопы OUTLINE
	for x in range(6, 13):
		if img.get_pixel(x, 22).a > 0.5:
			img.set_pixel(x, 22, P.c("CHAR", P.T_OUTLINE))
	for x in range(6, 13):
		img.set_pixel(x, 23, P.c("CHAR", P.T_OUTLINE))
	return img

static func _stump() -> Image:
	# пень (блокировщик K, коллизия 10×8 сохраняется)
	var img := _img(14, 12)
	_rectpx(img, 2, 4, 11, 10, "CHAR", P.T_MID)
	for x in range(2, 12):
		_pxl(img, x, 4, "CHAR", P.T_LIGHT)
	_pxl(img, 2, 5, "CHAR", P.T_LIGHT)
	_pxl(img, 11, 5, "CHAR", P.T_DARK)
	_pxl(img, 11, 6, "CHAR", P.T_DARK)
	# трещины пня
	_pxl(img, 5, 4, "CHAR", P.T_OUTLINE)
	_pxl(img, 8, 4, "CHAR", P.T_OUTLINE)
	_pxl(img, 4, 7, "CHAR", P.T_OUTLINE)
	_pxl(img, 9, 8, "CHAR", P.T_OUTLINE)
	# тлеющая точка внутри — 1 px
	_pxl(img, 4, 7, "ASH_EMBER", P.T_DARK)
	# опавшая зола
	_pxl(img, 0, 10, "ASH_GROUND", P.T_DARK)
	_pxl(img, 13, 10, "ASH_GROUND", P.T_DARK)
	for x in range(1, 13):
		img.set_pixel(x, 11, P.c("CHAR", P.T_OUTLINE))
	return img

static func _log() -> Image:
	# бревно (блокировщик #) — лежачий ствол
	var img := _img(20, 10)
	_rectpx(img, 1, 3, 18, 8, "CHAR", P.T_MID)
	for x in range(1, 19):
		_pxl(img, x, 3, "CHAR", P.T_LIGHT)
	for y in range(4, 9):
		_pxl(img, 18, y, "CHAR", P.T_DARK)
	# спил слева — торец BONE-серый
	_pxl(img, 0, 4, "BONE", P.T_MID)
	_pxl(img, 0, 5, "BONE", P.T_LIGHT)
	_pxl(img, 0, 6, "BONE", P.T_MID)
	_pxl(img, 1, 5, "BONE", P.T_DARK)
	# кора-трещины
	_pxl(img, 6, 5, "CHAR", P.T_OUTLINE)
	_pxl(img, 7, 6, "CHAR", P.T_OUTLINE)
	_pxl(img, 12, 4, "CHAR", P.T_OUTLINE)
	_pxl(img, 13, 6, "CHAR", P.T_OUTLINE)
	_pxl(img, 16, 5, "CHAR", P.T_OUTLINE)
	# зола у основания
	_pxl(img, 3, 8, "ASH_GROUND", P.T_DARK)
	_pxl(img, 9, 8, "ASH_GROUND", P.T_DARK)
	for x in range(0, 20):
		if img.get_pixel(x, 8).a > 0.5:
			img.set_pixel(x, 8, P.c("CHAR", P.T_OUTLINE))
	for x in range(1, 19):
		img.set_pixel(x, 9, P.c("CHAR", P.T_OUTLINE))
	return img

# ------------------------------------------------------------------ пропы
static func _ember_pile() -> Image:
	# угли: кучка CHAR с тлеющим ядром (FIRE_HOT — ровно 1 точка)
	var img := _img(16, 9)
	_rectpx(img, 3, 4, 12, 6, "CHAR", P.T_MID)
	_pxl(img, 2, 5, "CHAR", P.T_MID)
	_pxl(img, 13, 5, "CHAR", P.T_DARK)
	for x in range(4, 12):
		_pxl(img, x, 4, "CHAR", P.T_LIGHT)
	_pxl(img, 5, 3, "CHAR", P.T_MID)
	_pxl(img, 9, 3, "CHAR", P.T_MID)
	_pxl(img, 5, 4, "ASH_EMBER", P.T_DARK)
	_pxl(img, 6, 4, "ASH_EMBER", P.T_MID)
	_pxl(img, 7, 4, "ASH_EMBER", P.T_LIGHT)
	_flat(img, 8, 4, "FIRE_HOT")
	_pxl(img, 9, 4, "ASH_EMBER", P.T_MID)
	_pxl(img, 9, 5, "ASH_EMBER", P.T_DARK)
	# бока нижней кромки и стопа — OUTLINE угля
	_pxl(img, 2, 6, "CHAR", P.T_OUTLINE)
	_pxl(img, 13, 6, "CHAR", P.T_OUTLINE)
	for x in range(1, 15):
		img.set_pixel(x, 7, P.c("CHAR", P.T_OUTLINE))
	for x in range(2, 14):
		img.set_pixel(x, 8, P.c("CHAR", P.T_OUTLINE))
	return img

static func _ash_mound() -> Image:
	# пепелище-холмик: ASH_GROUND купол со светлой СЗ-шапкой
	var img := _img(16, 8)
	var rows := [[6, 9], [5, 10], [4, 11], [3, 12], [2, 13], [1, 14], [1, 14]]
	for i in rows.size():
		_rectpx(img, rows[i][0], i, rows[i][1], i, "ASH_GROUND", P.T_MID)
	for x in range(6, 9):
		_pxl(img, x, 0, "ASH_GROUND", P.T_LIGHT)
	_pxl(img, 5, 1, "ASH_GROUND", P.T_LIGHT)
	_pxl(img, 4, 2, "ASH_GROUND", P.T_LIGHT)
	for x in range(10, 12):
		_pxl(img, x, 2, "ASH_GROUND", P.T_DARK)
		_pxl(img, x, 3, "ASH_GROUND", P.T_DARK)
	_pxl(img, 12, 4, "ASH_GROUND", P.T_DARK)
	_pxl(img, 9, 3, "CHAR", P.T_MID)
	_pxl(img, 3, 5, "CHAR", P.T_DARK)
	# стопа холма — OUTLINE угля (тушит холм)
	for x in range(1, 15):
		img.set_pixel(x, 7, P.c("CHAR", P.T_OUTLINE))
	return img

static func _bone_pile() -> Image:
	# кость-куча: рёбра/череп, BONE ramp
	var img := _img(16, 9)
	# череп слева
	_rectpx(img, 2, 3, 5, 5, "BONE", P.T_MID)
	_pxl(img, 2, 3, "BONE", P.T_LIGHT)
	_pxl(img, 3, 3, "BONE", P.T_LIGHT)
	_pxl(img, 3, 4, "BONE", P.T_DARK)
	_pxl(img, 5, 4, "BONE", P.T_DARK)
	# рёбра дугами
	for x in range(7, 12):
		var yy := 3 + absi(x - 9) / 2
		_pxl(img, x, yy, "BONE", P.T_LIGHT if x <= 9 else P.T_MID)
		_pxl(img, x, yy + 1, "BONE", P.T_MID if x <= 9 else P.T_DARK)
	for x in range(9, 14):
		var yy := 5 + absi(x - 11) / 2
		_pxl(img, x, yy, "BONE", P.T_MID if x <= 11 else P.T_DARK)
	_pxl(img, 6, 5, "BONE", P.T_DARK)
	_pxl(img, 1, 6, "ASH_GROUND", P.T_DARK)
	_pxl(img, 14, 6, "ASH_GROUND", P.T_DARK)
	for x in range(1, 15):
		img.set_pixel(x, 7, P.c("BONE", P.T_DARK))
	for x in range(1, 15):
		img.set_pixel(x, 8, P.c("BONE", P.T_OUTLINE))
	return img

static func _skeleton() -> Image:
	# остов: грудная клетка зверя ~1H (16×15), BONE + тень
	var img := _img(16, 15)
	# позвоночник дугой
	for i in 11:
		var x := 2 + i
		var yy := 3 + (0 if i < 4 else (1 if i < 8 else 2))
		_pxl(img, x, yy, "BONE", P.T_LIGHT if i < 5 else P.T_MID)
		_pxl(img, x, yy + 1, "BONE", P.T_MID if i < 5 else P.T_DARK)
	# рёбра вниз от хребта
	for i: int in [1, 3, 5, 7, 9]:
		var x: int = 3 + i
		var top: int = 3 + (0 if i < 4 else (1 if i < 8 else 2)) + 2
		for k in range(3, 6):
			var xx: int = x - 1 + int(k / 3)
			_pxl(img, xx, top + k - 3, "BONE", P.T_MID if i % 2 == 0 else P.T_LIGHT)
	# череп слева сверху
	_rectpx(img, 0, 3, 1, 5, "BONE", P.T_MID)
	_pxl(img, 0, 3, "BONE", P.T_LIGHT)
	_pxl(img, 1, 4, "BONE", P.T_DARK)
	# лапы-останки справа
	_pxl(img, 14, 8, "BONE", P.T_DARK)
	_pxl(img, 15, 9, "BONE", P.T_DARK)
	_pxl(img, 13, 9, "BONE", P.T_MID)
	_pxl(img, 2, 12, "BONE", P.T_DARK)
	_pxl(img, 5, 11, "BONE", P.T_DARK)
	_pxl(img, 8, 12, "BONE", P.T_DARK)
	_pxl(img, 11, 11, "BONE", P.T_DARK)
	for x in range(1, 15):
		img.set_pixel(x, 13, P.c("BONE", P.T_OUTLINE))
	for x in range(2, 14):
		img.set_pixel(x, 14, P.c("BONE", P.T_OUTLINE))
	return img

# ------------------------------------------------------------------ наборы
static func _portal_tile() -> Image:
	# портал «P» (слот 7): ЦЕЛЫЙ тайл-пол (посыпка) с аркой обгоревших столбов —
	# легаси-семантика слота 7 (тайлмап рисует его на клетке «P», спрайты портала
	# в зоне и в деревне накладывают те же пиксели). FIRE_HOT не используем:
	# тление — ASH_EMBER (правило одной горячей точки — не нарушается).
	var img := _floor_scree()
	# перекладина (СЗ-подсветка сверху, тёмная грань справа)
	_rectpx(img, 2, 4, 13, 5, "CHAR", P.T_MID)
	_rectpx(img, 3, 4, 8, 4, "CHAR", P.T_LIGHT)
	_rectpx(img, 11, 5, 13, 5, "CHAR", P.T_DARK)
	_pxl(img, 2, 3, "CHAR", P.T_LIGHT)
	_pxl(img, 13, 3, "CHAR", P.T_DARK)
	_pxl(img, 10, 5, "CHAR", P.T_OUTLINE)
	# столбы
	_rectpx(img, 2, 6, 3, 14, "CHAR", P.T_MID)
	_rectpx(img, 12, 6, 13, 14, "CHAR", P.T_MID)
	_pxl(img, 2, 8, "CHAR", P.T_LIGHT)
	_pxl(img, 2, 11, "CHAR", P.T_LIGHT)
	_rectpx(img, 13, 6, 13, 14, "CHAR", P.T_DARK)
	_pxl(img, 3, 9, "CHAR", P.T_OUTLINE)
	_pxl(img, 12, 12, "CHAR", P.T_OUTLINE)
	# аршина: тёмное нутро и тлеющее дно
	_rectpx(img, 4, 7, 11, 10, "CHAR", P.T_OUTLINE)
	_rectpx(img, 4, 11, 11, 12, "ASH_EMBER", P.T_DARK)
	_rectpx(img, 5, 13, 10, 13, "ASH_EMBER", P.T_MID)
	_pxl(img, 7, 13, "ASH_EMBER", P.T_LIGHT)
	_pxl(img, 6, 12, "ASH_EMBER", P.T_MID)
	_pxl(img, 9, 11, "ASH_EMBER", P.T_MID)
	return img

static func _chest_frame() -> Image:
	# сундук Пепелища (слот 8): обгоревший сундук с железной оковкой и тлеющей
	# скважиной; свой кадр вместо лесного тайла 10 (персист/награда — не тронуты)
	var img := _img(16, 16)
	# крышка
	_rectpx(img, 4, 5, 11, 7, "CHAR", P.T_MID)
	_rectpx(img, 5, 5, 9, 5, "CHAR", P.T_LIGHT)
	_rectpx(img, 10, 6, 11, 7, "CHAR", P.T_DARK)
	_pxl(img, 4, 4, "CHAR", P.T_LIGHT)
	_pxl(img, 11, 4, "CHAR", P.T_DARK)
	# корпус
	_rectpx(img, 4, 8, 11, 13, "CHAR", P.T_MID)
	_rectpx(img, 10, 9, 11, 13, "CHAR", P.T_DARK)
	_pxl(img, 5, 9, "CHAR", P.T_LIGHT)
	_pxl(img, 5, 11, "CHAR", P.T_LIGHT)
	_pxl(img, 6, 10, "CHAR", P.T_OUTLINE)
	_pxl(img, 9, 12, "CHAR", P.T_OUTLINE)
	# железная оковка и замок
	_rectpx(img, 7, 5, 8, 12, "IRON", P.T_MID)
	_pxl(img, 7, 5, "IRON", P.T_LIGHT)
	_pxl(img, 8, 12, "IRON", P.T_DARK)
	_pxl(img, 8, 9, "ASH_EMBER", P.T_DARK)
	_pxl(img, 8, 10, "ASH_EMBER", P.T_MID)
	# дно
	for x in range(4, 12):
		img.set_pixel(x, 14, P.c("CHAR", P.T_OUTLINE))
	return img

# ------------------------------------------------------------------ атлас игры (c20)
# Разметка assets/ashen_tiles.png (bake_atlas): строка 0 — ячейки 16×16
# (0–3 полы листа, 4–6 «подложки» блокировщиков под prop-спрайтами,
# 7 портал, 8 сундук); строка 1 — высокие кадры(props) для Sprite2D
# (TileMap в строку 1 не смотрит: create_tile только (i,0), i<8).
const ATLAS_W := 144
const ATLAS_H := 40
const PROP_REGIONS := {
	"TREE1": Rect2(0, 16, 16, 24),
	"TREE2": Rect2(16, 16, 16, 24),
	"STUMP": Rect2(32, 16, 14, 12),
	"LOG": Rect2(48, 16, 20, 10),
}

static func bake_atlas() -> Image:
	var img := _img(ATLAS_W, ATLAS_H)
	var tiles: Array = _build_tiles()
	for i in tiles.size():
		img.blit_rect(tiles[i]["img"] as Image, Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
	# подложки блокировщиков: под деревья/бревно — осыпь, под пень — зола
	img.blit_rect(_floor_scree(), Rect2i(0, 0, 16, 16), Vector2i(4 * 16, 0))
	img.blit_rect(_floor_ash(), Rect2i(0, 0, 16, 16), Vector2i(5 * 16, 0))
	img.blit_rect(_floor_scree(), Rect2i(0, 0, 16, 16), Vector2i(6 * 16, 0))
	img.blit_rect(_portal_tile(), Rect2i(0, 0, 16, 16), Vector2i(7 * 16, 0))
	img.blit_rect(_chest_frame(), Rect2i(0, 0, 16, 16), Vector2i(8 * 16, 0))
	img.blit_rect(_tree1(), Rect2i(0, 0, 16, 24), Vector2i(0, 16))
	img.blit_rect(_tree2(), Rect2i(0, 0, 16, 24), Vector2i(16, 16))
	img.blit_rect(_stump(), Rect2i(0, 0, 14, 12), Vector2i(32, 16))
	img.blit_rect(_log(), Rect2i(0, 0, 20, 10), Vector2i(48, 16))
	return img

# ------------------------------------------------------------------ наборы
static func _build_tiles() -> Array:
	var srcs := [
		["FLOOR_ASH", "FLAS", _floor_ash(), true],
		["FLOOR_SCREE", "FLSC", _floor_scree(), true],
		["FLOOR_EMBER", "FLEM", _floor_crack(), true],
		["FLOOR_ARENA", "FLAR", _floor_arena(), true],
	]
	var out: Array = []
	for s in srcs:
		out.append({"name": s[0], "short": s[1], "canon": "16X16 TILE",
			"img": s[2], "tile": true, "seam_v": s[3]})
	return out

static func _build_props() -> Array:
	var meta := [
		["TREE1", "TR1", "~1.5H", _tree1()],
		["TREE2", "TR2", "~1.5H", _tree2()],
		["STUMP", "STP", "~0.7H", _stump()],
		["LOG", "LOG", "~0.6H", _log()],
		["EMBER_PILE", "EMB", "~0.5H", _ember_pile()],
		["ASH_MOUND", "MSH", "~0.5H", _ash_mound()],
		["BONE_PILE", "BNP", "~0.5H", _bone_pile()],
		["SKELETON", "SKL", "~1H", _skeleton()],
		["PORTAL", "PRT", "TILE16", _portal_tile(), true],
		["CHEST", "CHS", "~0.9H", _chest_frame()],
	]
	var out: Array = []
	for m in meta:
		var d := {"name": m[0], "short": m[1], "canon": m[2], "img": m[3]}
		if m.size() > 4:
			d["opaque"] = bool(m[4])
		out.append(d)
	return out

# ------------------------------------------------------------------ самопроверки
func _check_sprite(s: Dictionary) -> void:
	var img: Image = s["img"]
	var nm := String(s["name"])
	var w := img.get_width()
	var h := img.get_height()
	var foreign := 0
	var uniq := {}
	for y in h:
		for x in w:
			var col := img.get_pixel(x, y)
			if col.a < 0.5:
				continue
			uniq[P.key(col)] = true
			if not _idx.has(P.key(col)):
				foreign += 1
	if foreign > 0:
		_fails += 1
		print("[FAIL] %s: %d px вне палитры" % [nm, foreign])
	var last := -1
	for y in range(h - 1, -1, -1):
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				last = y
				break
		if last >= 0:
			break
	var bad_foot := 0
	for x in w:
		if img.get_pixel(x, last).a > 0.5:
			var info = _idx.get(P.key(img.get_pixel(x, last)))
			if info == null or int(info[1]) != P.T_OUTLINE:
				bad_foot += 1
	if bad_foot > 0:
		_fails += 1
		print("[FAIL] %s: нижний ряд не OUTLINE: %d px" % [nm, bad_foot])
	var lt_top := 0
	var lt_bot := 0
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.5:
				continue
			var info = _idx.get(P.key(img.get_pixel(x, y)))
			if info == null or not P.RAMPS.has(String(info[0])):
				continue
			if int(info[1]) == P.T_LIGHT:
				if y < h / 2.0:
					lt_top += 1
				else:
					lt_bot += 1
	if lt_top < 3:
		_fails += 1
		print("[FAIL] %s: нет подсветки СЗ (LIGHT сверху: %d)" % [nm, lt_top])
	# FIRE_HOT — максимум одна точка и только у углей
	var hot := 0
	for y in h:
		for x in w:
			if img.get_pixel(x, y).to_argb32() == P.FLATS["FIRE_HOT"].to_argb32():
				hot += 1
	if hot > (1 if nm == "EMBER_PILE" else 0):
		_fails += 1
		print("[FAIL] %s: FIRE_HOT точек %d" % [nm, hot])
	print("[spr] %-10s %2dx%-2d  %6s  colors:%d  light t/b: %d/%d  hot:%d  hash:%s" % [
		nm, w, h, String(s["canon"]), uniq.size(), lt_top, lt_bot, hot, _hash_img(img)])

func _check_tile(t: Dictionary) -> void:
	var img: Image = t["img"]
	var nm := String(t["name"])
	var bad := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a < 1.0 or not _idx.has(P.key(col)):
				bad += 1
	if bad > 0:
		_fails += 1
		print("[FAIL] tile %s: %d px вне палитры/прозрачны" % [nm, bad])
	else:
		print("[tile] %-12s 16x16 ok  hash:%s" % [nm, _hash_img(img)])

func _db(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var a := img.get_pixel(x0, y0)
	var b := img.get_pixel(x1, y1)
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0

func _check_seam(t: Dictionary) -> void:
	var img: Image = t["img"]
	var w := img.get_width()
	var h := img.get_height()
	var seam_x := 0.0
	for y in h:
		seam_x += _db(img, 15, y, 0, y)
	seam_x /= float(h)
	var field_x := 0.0
	for y in h:
		for x in range(w - 1):
			field_x += _db(img, x, y, x + 1, y)
	field_x /= float(h * (w - 1))
	var ratio_x := seam_x / maxf(field_x, 0.001)
	var seam_y := 0.0
	var ratio_y := 1.0
	if bool(t.get("seam_v", false)):
		for x in w:
			seam_y += _db(img, x, 15, x, 0)
		seam_y /= float(w)
		var field_y := 0.0
		for y in range(h - 1):
			for x in w:
				field_y += _db(img, x, y, x, y + 1)
		field_y /= float((h - 1) * w)
		ratio_y = seam_y / maxf(field_y, 0.001)
	var verdict := ""
	if ratio_x > SEAM_RATIO_MAX or ratio_y > SEAM_RATIO_MAX:
		_fails += 1
		verdict = "  [FAIL PIN]"
	print("[seam] %-12s horiz seam=%.1f field=%.1f ratio=%.2f vertil ratio=%.2f%s" % [
		String(t["name"]), seam_x, field_x, ratio_x, ratio_y, verdict])

func _contrast(img: Image, nm: String, opaque: bool) -> void:
	var rs := 0.0
	var gs := 0.0
	var bs := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			rs += c.r
			gs += c.g
			bs += c.b
			n += 1
	if n == 0:
		return
	var rb := int((rs - bs) / n * 255)
	print("[contrast] %-12s R-B=%s%d L=%d%s" % [nm, "-" if rb < 0 else "+", absi(rb),
		int((rs + gs + bs) / n / 3.0 * 255), " (opaque)" if opaque else ""])

func _metrics(tiles: Array, props: Array) -> void:
	for t in tiles:
		_contrast(t["img"], String(t["name"]), true)
	for s in props:
		_contrast(s["img"], String(s["name"]), false)
	# среднее по всем полам v1
	var rs := 0.0
	var bs := 0.0
	var ls := 0.0
	var n := 0
	for t in tiles:
		var img: Image = t["img"]
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				rs += c.r
				bs += c.b
				ls += (c.r + c.g + c.b) / 3.0
				n += 1
	var rb := (rs - bs) / n * 255.0
	var lum := ls / n * 255.0
	print("METRIC floors_v1_R_minus_B=%s%d" % ["-" if rb < 0 else "+", absi(int(rb))])
	print("METRIC floors_v1_L=%d" % int(lum))
	print("METRIC legacy_ashen_R_minus_B=-3 L=87 (замер легаси-листа, probe)")
	if rb <= 0:
		_fails += 1
		print("SELF-CHECK FAIL: полы v1 не читаются тёплыми (R-B<=0) — риск копии пещеры")
	print("METRIC tree_heights=24/24 (1.5H от H=16)")

# ------------------------------------------------------------------ шрифт/компоновка
const FONT := {
	"A": ["111", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["111", "100", "100", "100", "111"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "111", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["111", "100", "101", "101", "111"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "111"],
	"K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "101", "101", "101"], "N": ["110", "101", "101", "101", "101"],
	"O": ["111", "101", "101", "101", "111"], "P": ["111", "101", "111", "100", "100"],
	"Q": ["111", "101", "101", "111", "011"], "R": ["111", "101", "110", "101", "101"],
	"S": ["111", "000", "111", "001", "111"], "T": ["111", "010", "010", "010", "010"],
	"U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
	"W": ["101", "101", "101", "111", "101"], "X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "111", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "001", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "001"],
	" ": ["000", "000", "000", "000", "000"], "-": ["000", "000", "111", "000", "000"],
	"+": ["000", "010", "111", "010", "000"], "=": ["000", "111", "000", "111", "000"],
	".": ["000", "000", "000", "000", "010"], "~": ["000", "011", "110", "000", "000"],
	"/": ["001", "001", "010", "100", "100"], ":": ["000", "010", "000", "010", "000"],
}

func _text(img: Image, x0: int, y0: int, txt: String, sc: int, col: Color) -> int:
	var x := x0
	for ch in txt.to_upper():
		var g = FONT.get(ch)
		if g != null:
			for r in 5:
				for c in 3:
					if String(g[r])[c] == "1":
						for dy in sc:
							for dx in sc:
								_px(img, x + c * sc + dx, y0 + r * sc + dy, col)
		x += 4 * sc
	return x - x0 - sc

func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)

func _boxrect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, col)

func _draw_row(sheet: Image, items: Array, sc: int, x0: int, y0: int, maxh: int, pad: int, gap: int, full_names: bool) -> void:
	var x := x0
	for s in items:
		var img: Image = s["img"]
		var nm := String(s["name"]) if full_names else String(s["short"])
		var cw: int = img.get_width() * sc
		var ch: int = img.get_height() * sc
		var cell_w := cw + pad * 2
		var cell_h := maxh * sc + pad * 2
		var cy := y0 + (maxh - img.get_height()) * sc
		_boxrect(sheet, x, y0, x + cell_w - 1, y0 + cell_h - 1, P.SHEET["PANEL"])
		_boxrect(sheet, x, y0, x + cell_w - 1, y0, P.SHEET["LINE"])
		_boxrect(sheet, x, y0 + cell_h - 1, x + cell_w - 1, y0 + cell_h - 1, P.SHEET["LINE"])
		for yy in ch:
			for xx in cw:
				var col := img.get_pixel(int(xx / sc), int(yy / sc))
				if col.a > 0.5:
					var sx := x + pad + int(xx / sc) * sc
					var sy := cy + pad + int(yy / sc) * sc
					for dy in sc:
						for dx in sc:
							sheet.set_pixel(sx + dx, sy + dy, col)
		_text(sheet, x + 2, y0 + cell_h + 3, nm, 1, P.SHEET["TEXT"])
		_text(sheet, x + 2, y0 + cell_h + 10, "%dX%d %s" % [img.get_width(), img.get_height(), String(s["canon"])], 1, P.SHEET["LINE"])
		x += cell_w + gap

func _hero_box(sheet: Image, x: int, y: int, sc: int) -> void:
	for i in range(0, 16 * sc, 2):
		_px(sheet, x + i, y, P.SHEET["LINE"])
		_px(sheet, x + i + 1, y, P.SHEET["LINE"])
		_px(sheet, x + i, y + 16 * sc - 1, P.SHEET["LINE"])
		_px(sheet, x + i + 1, y + 16 * sc - 1, P.SHEET["LINE"])
	for i in range(0, 16 * sc, 2):
		_px(sheet, x, y + i, P.SHEET["LINE"])
		_px(sheet, x, y + i + 1, P.SHEET["LINE"])
		_px(sheet, x + 16 * sc - 1, y + i, P.SHEET["LINE"])
		_px(sheet, x + 16 * sc - 1, y + i + 1, P.SHEET["LINE"])
	_text(sheet, x + 2, y + 16 * sc + 3, "HERO 16", 1, P.SHEET["LINE"])

func _row_h(items: Array) -> int:
	var m := 0
	for s in items:
		m = maxi(m, (s["img"] as Image).get_height())
	return m

func _row_w(items: Array, sc: int, pad: int, gap: int) -> int:
	var wsum := 0
	for s in items:
		wsum += (s["img"] as Image).get_width() * sc + pad * 2 + gap
	return wsum

func _compose(tiles: Array, props: Array) -> Image:
	var pad := 6
	var gap := 14
	var title := 34
	var lbl := 20
	var tile_h4 := 16 * 4 + pad * 2
	var tile_h1 := 16 + pad * 2
	var prop_h4 := _row_h(props) * 4 + pad * 2
	var prop_h1 := _row_h(props) + pad * 2
	var ruler := 46
	var W0 := maxi(_row_w(tiles, 4, pad, gap), _row_w(props, 4, pad, gap))
	var W1 := ruler + maxi(_row_w(tiles, 1, pad, gap), _row_w(props, 1, pad, gap) + 60)
	var W := ruler + maxi(W0, W1) + 20
	var H := title + (tile_h4 + lbl) + (tile_h1 + lbl) + (prop_h4 + lbl) + (prop_h1 + lbl) + 44
	var sheet := _img(W, H)
	sheet.fill(P.SHEET["BG"])
	_text(sheet, 10, 8, "ASHEN V1 - PIXEL CANON SHEET (CODEGEN, HEAD DED8446)", 2, P.SHEET["TEXT"])
	_text(sheet, 10, 22, "NW LIGHT / OUTLINE FOOT / TILE16 H16 / PAL=PIXELPALETTE 0 NEW", 1, P.SHEET["LINE"])
	var y := title
	_text(sheet, 10, y + 2, "FLOOR 4X", 1, P.SHEET["LINE"])
	_draw_row(sheet, tiles, 4, ruler, y, 16, pad, gap, true)
	y += tile_h4 + lbl
	_text(sheet, 10, y + 2, "FLOOR 1X = SCREEN", 1, P.SHEET["LINE"])
	_draw_row(sheet, tiles, 1, ruler, y, 16, pad, gap, true)
	y += tile_h1 + lbl
	_text(sheet, 10, y + 2, "PROPS 4X", 1, P.SHEET["LINE"])
	_draw_row(sheet, props, 4, ruler, y, _row_h(props), pad, gap, true)
	y += prop_h4 + lbl
	_text(sheet, 10, y + 2, "PROPS 1X = SCREEN", 1, P.SHEET["LINE"])
	_hero_box(sheet, ruler, y + pad + (_row_h(props) - 16), 1)
	_draw_row(sheet, props, 1, ruler + 46, y, _row_h(props), pad, gap, false)
	for sc in [4, 1]:
		var ry: int = y - (prop_h4 + lbl if sc == 4 else 0) + pad + (_row_h(props) - 16) * sc
		for yy in 16 * sc:
			_px(sheet, 20, ry + yy, P.SHEET["LINE"])
		for xx in 5:
			_px(sheet, 20 + xx, ry, P.SHEET["LINE"])
			_px(sheet, 20 + xx, ry + 16 * sc - 1, P.SHEET["LINE"])
		_text(sheet, 27, ry + maxi(0, (16 * sc - 5) / 2), "H", 1, P.SHEET["LINE"])
	var used := ["ASH_GROUND", "CHAR", "ASH_EMBER", "BONE", "IRON"]
	var ny := H - 26
	_text(sheet, 10, ny - 9, "RAMPS USED (PIXELPALETTE, ASHEN DELTA = EMPTY)", 1, P.SHEET["LINE"])
	var nx0 := 10
	for rn in used:
		var ramp: Array = P.RAMPS[rn]
		for t in 4:
			_boxrect(sheet, nx0 + t * 7, ny, nx0 + t * 7 + 5, ny + 7, ramp[t])
		_text(sheet, nx0, ny + 9, rn.left(7), 1, P.SHEET["LINE"])
		nx0 += 4 * 7 + 9
	_boxrect(sheet, nx0, ny, nx0 + 5, ny + 7, P.FLATS["FIRE_HOT"])
	_text(sheet, nx0, ny + 9, "FIREHOT", 1, P.SHEET["LINE"])
	print("[hash] sheet pre-save  %s" % _hash_img(sheet))
	return sheet

func _upscale2(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := _img(w * 2, h * 2)
	for y in h:
		for x in w:
			var col := img.get_pixel(x, y)
			out.set_pixel(x * 2, y * 2, col)
			out.set_pixel(x * 2 + 1, y * 2, col)
			out.set_pixel(x * 2, y * 2 + 1, col)
			out.set_pixel(x * 2 + 1, y * 2 + 1, col)
	return out

func _init() -> void:
	_idx = P.color_index()
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and String(args[0]) == "atlas":
		# c20: печать игрового атласа (единый источник — bake_atlas)
		var apath := "res://assets/ashen_tiles.png"
		if args.size() > 1:
			apath = String(args[1])
		var a := bake_atlas()
		var bad := 0
		for y in a.get_height():
			for x in a.get_width():
				var col := a.get_pixel(x, y)
				if col.a > 0.5 and not _idx.has(P.key(col)):
					bad += 1
		print("[atlas] %dx%d off=%d hash=%s" % [a.get_width(), a.get_height(), bad, _hash_img(a)])
		var aerr := a.save_png(apath)
		print("atlas saved: %s err=%d" % [apath, aerr])
		if bad > 0 or aerr != OK:
			print("SELF-CHECK: FAIL (atlas)")
			quit(1)
		print("SELF-CHECK: PASS")
		quit(0)
	var out_path := "res://tools_art/sheet_ashen_v1.png"
	if args.size() > 0:
		out_path = String(args[0])
	var tiles := _build_tiles()
	var props := _build_props()
	for s in props:
		if bool(s.get("opaque", false)):
			_check_tile(s)
		else:
			_check_sprite(s)
	for t in tiles:
		_check_tile(t)
		_check_seam(t)
	_metrics(tiles, props)
	var sheet := _compose(tiles, props)
	var err := sheet.save_png(out_path)
	print("sheet saved: %s (%dx%d) err=%d" % [out_path, sheet.get_width(), sheet.get_height(), err])
	var p2 := out_path.replace(".png", "_2x.png")
	var err2 := _upscale2(sheet).save_png(p2)
	print("sheet saved: %s err=%d" % [p2, err2])
	if _fails > 0:
		print("SELF-CHECK: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("SELF-CHECK: PASS")
		quit(0)
