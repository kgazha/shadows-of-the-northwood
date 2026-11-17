class_name UiIcons
extends RefCounted
## t52 снос (закон пользователя 13.11): ген-иконки item/skill/talent сняты.
## t53/c15: иконки скиллов v2 — принятый пользователем лист c11 интегрирован
## дословно (12 рисовалок перенесены из tools_art/sheet_icons.gd; попиксельное
## равенство листу гейтится самопроверкой генератора). Рисуются кодом в RGBA8
## 16 px — без картинок вообще. Атлас скиллов — 12 слотов по 16 px,
## порядок = classes_data.gd. Цвета иконок — только PixelPalette.RAMPS/FLATS;
## фон слота — технический SHEET.BG (как в утверждённом листе).
## c25: предметные иконки — утверждённый лист c24, 6 рисовалок перенесены
## дословно из tools_art/sheet_items.gd (equality-пин в его самопроверке);
## tech-фон предмета (_slot_bg BG/INK) и fallback неизвестных id — не тронуты.

const S := 16  # canonical slot size, px

const PAL := preload("res://scripts/pixel_palette.gd")

# порядок слотов атласа скиллов (classes_data.gd: warrior 0-3, hunter 4-6,
# mage 7-11: power_strike, whirlwind, second_wind, execute, pierce, volley,
# mark, rain, firebolt, frost_nova, siphon, firestorm)
const SKILL_SLOTS := ["power_strike", "whirlwind", "second_wind", "execute", \
	"pierce", "volley", "mark", "rain", "firebolt", "frost_nova", "siphon", "firestorm"]

const INK := Color(0.16, 0.11, 0.08)      # тёмный контур/штрих (предметы)
const BG := Color(0.23, 0.17, 0.12)       # фон слота предмета — «дерево» HUD
const ACC_W := Color(0.85, 0.68, 0.32)    # воинская охра (рамка талантов)
const ACC_G := Color(0.72, 0.72, 0.78)    # сталь/пепел (предметы)

const _L := 0  # тона рамп PixelPalette: LIGHT/MID/DARK/OUTLINE
const _M := 1
const _D := 2
const _O := 3

static var _skill_atlas: Texture2D = null
static var _item_cache := {}

# временный холст рисовалок (задаётся только на время skill_atlas())
static var _cv: Image = null
static var _cv_ox := 0

## Атлас скиллов 192x16 (12 слотов) — тот же контракт, что был у ген-атласа.
static func skill_atlas() -> Texture2D:
	if _skill_atlas != null:
		return _skill_atlas
	var img := Image.create_empty(S * SKILL_SLOTS.size(), S, false, Image.FORMAT_RGBA8)
	_cv = img
	for i in SKILL_SLOTS.size():
		for y in S:
			for x in S:
				img.set_pixel(i * S + x, y, PAL.SHEET.BG)
		_cv_ox = i * S
		_ic16(i)
	_cv = null
	_cv_ox = 0
	_skill_atlas = ImageTexture.create_from_image(img)
	return _skill_atlas

## Иконка предмета 16x16 по имени слота (herb/mushroom/root/ash/berry/glowcap).
static func item_icon(name: String) -> Texture2D:
	if _item_cache.has(name):
		return _item_cache[name]
	var img := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	_stamp_item(img, name)
	var tex := ImageTexture.create_from_image(img)
	_item_cache[name] = tex
	return tex

## Иконка таланта: базовая 8x8 из talents.gd (_PIXELS), сюда — только рамка-слот.
static func talent_frame(img: Image) -> void:
	_outline(img, ACC_W)

# ---------- палитровые примитивы рисовалок (цвета — только PixelPalette) ----------

static func _P(x: int, y: int, ramp: String, tone: int) -> void:
	# P(alette) — точка материалом; вне холста молча режется
	var xx := x + _cv_ox
	if xx < 0 or y < 0 or xx >= _cv.get_width() or y >= _cv.get_height():
		return
	_cv.set_pixel(xx, y, PAL.c(ramp, tone))

static func _F(x: int, y: int, flat: String) -> void:
	var xx := x + _cv_ox
	if xx < 0 or y < 0 or xx >= _cv.get_width() or y >= _cv.get_height():
		return
	_cv.set_pixel(xx, y, PAL.FLATS[flat])

static func _hl(x0: int, x1: int, y: int, ramp: String, tone: int) -> void:
	for x in range(x0, x1 + 1):
		_P(x, y, ramp, tone)

static func _vl(x: int, y0: int, y1: int, ramp: String, tone: int) -> void:
	for y in range(y0, y1 + 1):
		_P(x, y, ramp, tone)

static func _diag(pts: Array, ramp: String, tone: int) -> void:
	for p in pts:
		_P(int(p[0]), int(p[1]), ramp, tone)

static func _dot(x: int, y: int, ramp: String) -> void:
	# «жирная» точка 2×2 с СЗ-светом
	_P(x, y, ramp, _L)
	_P(x + 1, y, ramp, _M)
	_P(x, y + 1, ramp, _M)
	_P(x + 1, y + 1, ramp, _D)

# ================= 16 px иконки (перенос из sheet_icons.gd, verbatim) =======
# Правило ряда: рисуем внутри квадрата 16×16 (холст — слот атласа);
# нижний пиксельный ряд объекта — OUTLINE-тон; LIGHT — верх/лево открытой
# грани; правый бок — DARK.

static func _ic16(idx: int) -> void:
	match idx:
		0: _ic_power_strike()
		1: _ic_whirlwind()
		2: _ic_second_wind()
		3: _ic_execute()
		4: _ic_pierce()
		5: _ic_volley()
		6: _ic_mark()
		7: _ic_rain()
		8: _ic_firebolt()
		9: _ic_frost_nova()
		10: _ic_siphon()
		11: _ic_firestorm()

## power_strike — бронзовый молот вниз-вправо (голова справа внизу), рукоять вверх.
static func _ic_power_strike() -> void:
	# голова: компактный бронзовый блок 4×3 справа внизу
	_hl(9, 12, 7, "BRONZE", _L)
	_hl(9, 11, 8, "BRONZE", _M)
	_vl(12, 8, 9, "BRONZE", _D)
	_hl(9, 12, 9, "BRONZE", _M)
	_hl(9, 12, 10, "BRONZE", _O)
	# шип вправо
	_P(13, 8, "BRONZE", _M)
	_P(13, 9, "BRONZE", _O)
	# рукоять вверх-влево
	_diag([[8, 6], [7, 5], [6, 4], [5, 3]], "WOOD", _M)
	_diag([[7, 4], [6, 3]], "WOOD", _L)
	# навершие — золото
	_diag([[4, 2], [4, 1]], "HUD_GOLD", _L)
	_P(3, 2, "HUD_GOLD", _M)

## whirlwind — спираль вихря в левом верхнем углу (НЕ кольцо).
static func _ic_whirlwind() -> void:
	var pts := [[8, 2], [6, 1], [4, 1], [2, 2], [1, 4], [1, 6],
		[2, 8], [4, 9], [6, 8], [7, 6], [6, 5], [5, 5]]
	for i in pts.size():
		var t := _L if i < 4 else (_M if i < 8 else _D)
		_P(int(pts[i][0]), int(pts[i][1]), "WATER", t)
	# стыки ленты (спираль непрерывна)
	_P(5, 1, "WATER", _M)
	_P(1, 3, "WATER", _M)
	_P(1, 7, "WATER", _M)
	_P(3, 9, "WATER", _D)
	# юбка ленты — OUTLINE ряда
	_diag([[2, 9], [3, 10], [4, 10], [5, 10], [6, 9]], "WATER", _O)
	# песчинки — золото
	_P(3, 4, "HUD_GOLD", _L)
	_P(5, 3, "HUD_GOLD", _M)

## second_wind — перо в правом столбце: редкие штрихи опахала, просветы.
static func _ic_second_wind() -> void:
	# стержень — сплошная лесенка справа налево вниз
	_diag([[12, 2], [11, 3], [11, 4], [10, 5], [9, 6], [9, 7], [8, 8],
		[7, 9], [7, 10], [6, 11], [6, 12]], "LEAF", _D)
	# опахало: штрихи через ряд (просветы!), СЗ-свет вверху
	for i in 5:
		var y := 2 + i * 2
		var bx := 12 - i
		_hl(bx + 1, bx + 2, y, "LEAF", _L if i < 3 else _M)
		_P(bx - 2, y, "LEAF", _D)
	# насечки воздуха
	_P(14, 5, "LEAF", _L)
	# очин — ноги ряда
	_diag([[6, 13], [7, 13]], "LEAF", _O)
	# завихрение ветра — золото (хвост — OUTLINE ряда)
	_diag([[11, 11], [12, 12]], "HUD_GOLD", _M)
	_P(12, 10, "HUD_GOLD", _L)
	_P(11, 13, "HUD_GOLD", _O)

## execute — бронзовый палаш вниз у левого края: узкий клинок, алая обмотка.
static func _ic_execute() -> void:
	# яблоко — золото
	_hl(3, 4, 1, "HUD_GOLD", _L)
	# крестовина WOOD
	_hl(1, 6, 3, "WOOD", _M)
	_hl(1, 6, 4, "WOOD", _O)
	# рукоять — красная обмотка
	_vl(3, 5, 6, "HP_RED", _L)
	_vl(4, 5, 6, "HP_RED", _M)
	# клинок узкий: 2 колонки
	_vl(3, 7, 11, "BRONZE", _L)
	_vl(4, 7, 10, "BRONZE", _M)
	_vl(5, 7, 9, "BRONZE", _D)
	# остриё и ноги ряда
	_P(4, 11, "BRONZE", _D)
	_hl(3, 4, 12, "BRONZE", _O)

## pierce — стрела со свистом вверх-вправо: оперенье CLOTH, бронза.
static func _ic_pierce() -> void:
	_diag([[2, 11], [3, 10], [4, 9], [5, 8], [6, 7], [7, 6], [8, 5],
		[9, 4], [10, 3]], "WOOD", _M)
	_diag([[3, 10], [5, 8], [7, 6], [9, 4]], "WOOD", _L)
	# наконечник BRONZE
	_diag([[11, 2], [12, 1]], "BRONZE", _L)
	_diag([[11, 3], [12, 2]], "BRONZE", _D)
	_P(10, 4, "HUD_GOLD", _M)
	# оперенье CLOTH и ноги ряда
	_diag([[1, 12], [2, 11]], "CLOTH", _M)
	_diag([[1, 13], [2, 13]], "CLOTH", _O)
	_P(13, 1, "HUD_GOLD", _L)

## volley — лук лёжа (плечи вниз) в среднем поясе, стрела вдоль хорды вправо.
static func _ic_volley() -> void:
	# дуга плечей брюхом вниз (реже: 5 точек)
	_diag([[4, 8], [5, 9], [7, 10], [9, 9], [10, 8]], "BARK", _M)
	_P(5, 8, "BARK", _L)
	_P(9, 8, "BARK", _D)
	_P(4, 8, "CLOTH", _L)
	_P(11, 8, "CLOTH", _M)
	# тетива-хорда (крашеная HP_RED)
	_hl(4, 10, 8, "HP_RED", _M)
	# стрела над тетивой, вправо
	_hl(4, 8, 7, "WOOD", _M)
	_hl(5, 8, 6, "WOOD", _L)
	_P(9, 6, "BRONZE", _L)
	_P(9, 7, "BRONZE", _D)
	# оперенье
	_diag([[3, 6], [3, 7]], "CLOTH", _D)
	# ноги ряда: низ брюха
	_P(7, 11, "BARK", _O)

## mark — коготные росчерки в нижнем-среднем поясе: три штриха HP_RED + золото.
static func _ic_mark() -> void:
	var strokes := [
		[[3, 7], [4, 8], [5, 9]],
		[[7, 5], [8, 6], [9, 7], [10, 8], [11, 9]],
		[[12, 5], [13, 6]],
	]
	for s in strokes:
		for i in s.size():
			_P(int(s[i][0]), int(s[i][1]), "HP_RED", _L if i == 0 else _M)
			_P(int(s[i][0]), int(s[i][1]) + 1, "HP_RED", _D)
	# хвосты штрихов — OUTLINE
	_diag([[5, 10], [11, 10], [13, 7]], "HP_RED", _O)
	# вырванная метка — золото
	_P(5, 12, "HUD_GOLD", _L)
	_P(5, 13, "HUD_GOLD", _O)

## rain — полое дно-колчан в левом нижнем углу, стрелы вправо-вверх.
static func _ic_rain() -> void:
	# полое дно-чулок: верхняя кромка, бока, дно (крашеная кожа CLOTH-бок)
	_hl(1, 6, 9, "BARK", _L)
	_vl(1, 10, 12, "CLOTH", _M)
	_vl(6, 10, 12, "BARK", _D)
	_vl(7, 9, 11, "CLOTH", _M)
	# дно — ноги ряда
	_hl(1, 6, 13, "BARK", _O)
	# ремень с золотой пряжкой
	_vl(3, 10, 12, "HP_RED", _M)
	_P(3, 11, "HUD_GOLD", _L)
	_P(4, 11, "HUD_GOLD", _M)
	# три стрелы высыпаются вправо-вверх
	for sp in [[10, 3], [12, 6], [10, 7]]:
		var bx := int(sp[0])
		var by := int(sp[1])
		_P(bx, by, "WOOD", _M)
		_P(bx + 1, by - 1, "BRONZE", _L)
		_P(bx, by + 1, "CLOTH", _D)

## firebolt — комета в верхнем поясе (центр): голова FIRE с ядром HOT, хвост.
static func _ic_firebolt() -> void:
	# голова (сдвинута вниз, чтобы не сливаться с хордой volley)
	_hl(6, 8, 4, "FIRE", _L)
	_hl(6, 7, 5, "FIRE", _M)
	_vl(9, 5, 6, "FIRE", _D)
	_hl(6, 9, 7, "FIRE", _O)
	_F(7, 5, "FIRE_HOT")
	_F(8, 6, "FIRE_HOT")
	# хвост — редкие штрихи влево
	_hl(4, 5, 5, "FIRE", _M)
	_P(3, 4, "FIRE", _L)
	_P(2, 6, "FIRE", _M)
	# искра впереди
	_P(11, 3, "HUD_GOLD", _L)

## frost_nova — разлёт ледяных игл: Y CRYSTAL + золотые искры-блики.
static func _ic_frost_nova() -> void:
	# hub
	_dot(7, 5, "CRYSTAL")
	# игла вверх-влево
	_diag([[6, 4], [5, 3], [4, 2], [3, 1]], "CRYSTAL", _M)
	_diag([[5, 4], [4, 3]], "CRYSTAL", _L)
	_diag([[8, 5]], "CRYSTAL", _D)
	# игла вправо (короткая — не спорить с молотом справа)
	_diag([[9, 5], [10, 4], [11, 4]], "CRYSTAL", _M)
	_diag([[11, 5]], "CRYSTAL", _D)
	# игла вниз — ноги ряда
	_diag([[8, 8], [8, 9], [8, 10]], "CRYSTAL", _M)
	_diag([[9, 8], [9, 9]], "CRYSTAL", _D)
	_diag([[8, 11], [9, 11]], "CRYSTAL", _O)
	# холодные искры — золото
	_P(4, 8, "HUD_GOLD", _M)
	_P(12, 6, "HUD_GOLD", _L)

## siphon — серп: крюк BRONZE сверху, древко вниз-влево, росчерк жизни HP_RED.
static func _ic_siphon() -> void:
	# крюк лезвия
	_diag([[8, 4], [9, 2], [11, 1], [13, 2], [13, 4], [12, 5], [10, 5]], "BRONZE", _M)
	_diag([[9, 1], [11, 0 + 1], [13, 1]], "BRONZE", _L)
	_diag([[10, 6], [12, 6], [13, 5]], "BRONZE", _D)
	_diag([[10, 7], [11, 7]], "BRONZE", _O)
	# древко наискось вниз-влево
	_diag([[7, 7], [6, 9], [5, 11]], "WOOD", _M)
	_diag([[6, 8], [5, 10]], "WOOD", _L)
	# ноги ряда
	_diag([[4, 13], [5, 13]], "WOOD", _O)
	# украденная жизнь — росчерк HP_RED
	_diag([[14, 7], [14, 8]], "HP_RED", _M)
	_P(14, 9, "HP_RED", _O)
	_P(13, 7, "HP_RED", _L)

## firestorm — огненная волна в правом поясе: крутой гребень снизу-слева вправо.
static func _ic_firestorm() -> void:
	# крутой гребень (полоса 2px)
	_diag([[4, 12], [5, 11], [6, 9], [7, 8], [8, 7], [9, 6], [10, 5],
		[11, 4]], "FIRE", _M)
	_diag([[5, 10], [7, 7], [9, 5], [10, 4]], "FIRE", _L)
	_diag([[6, 10], [8, 8], [10, 6], [11, 5]], "FIRE", _D)
	# гребень закручен
	_diag([[12, 3], [13, 3]], "FIRE", _L)
	_P(14, 4, "FIRE", _D)
	# ядра HOT
	_F(10, 4, "FIRE_HOT")
	_F(7, 7, "FIRE_HOT")
	# основание — ноги ряда
	_hl(4, 6, 13, "FIRE", _O)
	# уголь — золото
	_P(14, 10, "HUD_GOLD", _M)

# ========== предметные иконки (перенос из sheet_items.gd, verbatim; c25) =====
# Утверждённый пользователем лист c24. Тот же холст-механизм, что у скиллов
# (_cv/_cv_ox); примитивы общие. Нижняя нога — OUTLINE, LIGHT — верх/лево.

## herb — пучок из трёх листьев, перевязанный золотой лентой.
static func _ic_item_herb() -> void:
	# три листа-клинка (средний выше): левый край LIGHT, ядро MID, правый DARK,
	# основание листа — OUTLINE-тон LEAF
	for b in [[4, 5, 11], [7, 2, 11], [10, 4, 11]]:
		var bx: int = b[0]
		var y0: int = b[1]
		var y1: int = b[2]
		_P(bx, y0, "LEAF", _L)
		_P(bx + 1, y0 + 1, "LEAF", _M)
		for y in range(y0 + 1, y1):
			_P(bx, y, "LEAF", _L)
			_P(bx + 1, y, "LEAF", _M)
		_P(bx + 2, y0 + 2, "LEAF", _D)
		for y in range(y0 + 3, y1):
			_P(bx + 2, y, "LEAF", _D)
		_hl(bx, bx + 2, y1, "LEAF", _O)
	# перевязь — золотая лента (акцент «связанный сбор»), низ — OUTLINE золота
	_hl(3, 12, 12, "HUD_GOLD", _L)
	_hl(3, 12, 13, "HUD_GOLD", _M)
	_hl(3, 12, 14, "HUD_GOLD", _O)

## mushroom — боровик: шляпка HP_RED с костяными пятнами, ножка BONE.
static func _ic_item_mushroom() -> void:
	_hl(6, 9, 4, "HP_RED", _L)
	_hl(4, 7, 5, "HP_RED", _L)
	_hl(8, 11, 5, "HP_RED", _M)
	_hl(3, 7, 6, "HP_RED", _L)
	_hl(8, 11, 6, "HP_RED", _M)
	_hl(12, 13, 6, "HP_RED", _D)
	_hl(2, 5, 7, "HP_RED", _L)
	_hl(6, 10, 7, "HP_RED", _M)
	_hl(11, 13, 7, "HP_RED", _D)
	_hl(3, 12, 8, "HP_RED", _O)        # кайма низа шляпки
	# костяные пятна
	_F(5, 5, "FIRE_HOT")
	_P(6, 6, "BONE", _L)
	_P(9, 5, "BONE", _M)
	_P(11, 7, "BONE", _M)
	_P(4, 7, "BONE", _L)
	# ножка (кремовая, как у боровика): свет левый, тень правый, раструб внизу
	_vl(6, 9, 12, "PARCHMENT", _L)
	_hl(7, 8, 9, "PARCHMENT", _M)
	_vl(7, 10, 12, "PARCHMENT", _M)
	_vl(9, 9, 12, "PARCHMENT", _D)
	_hl(6, 9, 13, "PARCHMENT", _M)
	_hl(5, 10, 14, "PARCHMENT", _O)

## root — корень с отпиленным верхом (кремовый срез), усиками и золотым
## кончиком (акцент «ценная сердцевина»).
static func _ic_item_root() -> void:
	# срез — светлая кремовая шапка
	_hl(6, 10, 3, "PARCHMENT", _L)
	_hl(6, 10, 4, "PARCHMENT", _M)
	# тело: изогнутый ствол BARK (свет слева)
	_P(6, 5, "BARK", _L)
	_hl(7, 9, 5, "BARK", _M)
	_vl(6, 6, 8, "BARK", _L)
	_hl(7, 8, 6, "BARK", _M)
	_vl(8, 7, 9, "BARK", _M)
	_vl(9, 6, 8, "BARK", _D)
	_P(6, 9, "BARK", _L)
	_hl(7, 9, 9, "BARK", _M)
	# усики
	_diag([[10, 7], [11, 8]], "BARK", _D)
	_diag([[5, 10], [4, 11]], "BARK", _D)
	_diag([[10, 10], [11, 11]], "BARK", _D)
	# сужение к кончику
	_vl(7, 10, 11, "BARK", _M)
	_vl(8, 10, 11, "BARK", _D)
	# золотая сердцевина кончика (акцент) и OUTLINE-стопа
	_hl(7, 9, 12, "HUD_GOLD", _L)
	_hl(7, 9, 13, "HUD_GOLD", _M)
	_hl(6, 9, 14, "BARK", _O)
	# росток на срезе (свежий сбор)
	_P(7, 2, "LEAF", _M)
	_P(8, 1, "LEAF", _L)
	_P(9, 2, "LEAF", _D)
	# комья земли
	_P(4, 7, "ASH_GROUND", _M)
	_P(12, 9, "ASH_GROUND", _M)

## ash — горка пепла с тлеющими углями (акцент ASH_EMBER) и дымком.
static func _ic_item_ash() -> void:
	# дымки (северо-запад — вверх-влево)
	_diag([[7, 3], [6, 4], [7, 5]], "PARCHMENT", _M)
	_diag([[10, 4], [10, 6]], "PARCHMENT", _D)
	# горка: светлая верхушка слева, тело MID, тень справа
	_hl(7, 8, 8, "ASH_GROUND", _L)
	_P(6, 9, "ASH_GROUND", _L)
	_hl(7, 9, 9, "ASH_GROUND", _M)
	_hl(4, 9, 10, "ASH_GROUND", _M)
	_hl(10, 11, 10, "ASH_GROUND", _D)
	_P(3, 11, "ASH_GROUND", _L)
	_hl(4, 10, 11, "ASH_GROUND", _M)
	_hl(11, 12, 11, "ASH_GROUND", _D)
	_hl(2, 13, 12, "ASH_GROUND", _M)
	_hl(5, 10, 13, "ASH_EMBER", _M)
	_hl(2, 4, 13, "ASH_GROUND", _D)
	_hl(11, 13, 13, "ASH_GROUND", _D)
	_hl(1, 14, 14, "ASH_GROUND", _O)
	# тлеющие угли — смысл предмета
	_P(5, 12, "ASH_EMBER", _L)
	_P(6, 11, "ASH_EMBER", _L)
	_P(7, 12, "ASH_EMBER", _M)
	_P(8, 12, "ASH_EMBER", _M)
	_P(9, 11, "ASH_EMBER", _M)
	_P(10, 12, "ASH_EMBER", _D)
	_P(11, 12, "ASH_EMBER", _D)
	_F(8, 10, "FIRE_HOT")

## berry — гроздь трёх ягод HP_RED на ветке с листом.
static func _ic_item_berry() -> void:
	# ветка и лист
	_diag([[8, 4], [8, 5], [7, 6], [7, 7]], "BARK", _M)
	_diag([[9, 3], [10, 3], [11, 4]], "LEAF", _L)
	_diag([[10, 4], [11, 5], [12, 5]], "LEAF", _M)
	_P(12, 6, "LEAF", _D)
	# ягоды 2x2 с собственным светом; низ каждой — OUTLINE
	_P(4, 8, "HP_RED", _L)
	_P(5, 8, "HP_RED", _M)
	_P(4, 9, "HP_RED", _M)
	_hl(4, 5, 10, "HP_RED", _O)
	_P(9, 9, "HP_RED", _L)
	_P(10, 9, "HP_RED", _M)
	_P(9, 10, "HP_RED", _M)
	_hl(9, 10, 11, "HP_RED", _O)
	_P(6, 11, "HP_RED", _L)
	_P(7, 11, "HP_RED", _M)
	_P(6, 12, "HP_RED", _M)
	_hl(6, 7, 13, "HP_RED", _O)
	# концы грозди (самый нижний ряд)
	_P(5, 14, "HP_RED", _O)
	_P(8, 14, "HP_RED", _O)

## glowcap — светособака: колокол-фонарь CRYSTAL с горячим ядром, лучами и
## светящейся ножкой.
static func _ic_item_glowcap() -> void:
	# лучи (NW-ориентированные штрихи)
	_P(4, 3, "CRYSTAL", _L)
	_P(3, 5, "CRYSTAL", _L)
	_P(12, 3, "CRYSTAL", _M)
	_P(13, 5, "CRYSTAL", _M)
	# колокол: узкий верх — распор вниз; свет слева
	_hl(7, 8, 4, "CRYSTAL", _L)
	_hl(6, 9, 5, "CRYSTAL", _L)
	_hl(10, 10, 5, "CRYSTAL", _M)
	_hl(5, 8, 6, "CRYSTAL", _L)
	_hl(9, 11, 6, "CRYSTAL", _M)
	_hl(5, 8, 7, "CRYSTAL", _L)
	_hl(9, 11, 7, "CRYSTAL", _M)
	_hl(12, 12, 7, "CRYSTAL", _D)
	_hl(4, 11, 8, "CRYSTAL", _M)
	_P(4, 8, "CRYSTAL", _L)
	_hl(12, 12, 8, "CRYSTAL", _D)
	_hl(4, 12, 9, "CRYSTAL", _O)       # кайма раструба
	# горячее ядро под куполом
	_F(7, 7, "FIRE_HOT")
	_P(6, 8, "CRYSTAL", _L)
	_P(8, 8, "CRYSTAL", _L)
	# ножка (светящийся кристалл, не кость — держит акцент предмета)
	_vl(7, 10, 13, "CRYSTAL", _L)
	_vl(8, 10, 13, "CRYSTAL", _M)
	_hl(7, 8, 14, "CRYSTAL", _O)

# ========== g20a: инвентарные силуэты (вердикт 17.11 ~10:00) ==========
# Новые предметы сетки 6×2. Тот же канон ряда, что у листа c24: LIGHT — верх/
# лево открытой грани, DARK — правый бок, нижний ряд — OUTLINE; палитра только
# PixelPalette.RAMPS/FLATS.

## hide — «Шкура слизня»: складчатый прямоугольник со швом (вердикт:
## «складчатый прямоугольник со швом»). Верхнее полотно светлое, складка —
## тёмная борозда со светлыми проколами стежка, нижнее полотно — изнанка.
static func _ic_item_hide() -> void:
	# верхнее полотно: СЗ-кромка светлая, тело MID, блик перед складкой
	_hl(4, 11, 3, "BONE", _L)
	_vl(3, 4, 11, "BONE", _L)
	_hl(4, 11, 4, "BONE", _M)
	_hl(4, 11, 5, "BONE", _M)
	_hl(4, 11, 6, "BONE", _L)
	# шов: тёмная борозда + светлые проколы иглы (пунктир через один)
	_hl(4, 11, 7, "BONE", _D)
	_P(5, 7, "BONE", _L)
	_P(7, 7, "BONE", _L)
	_P(9, 7, "BONE", _L)
	_P(11, 7, "BONE", _L)
	# изнанка (нижнее полотно темнее — оно подогнуто) и правый бок-тень
	_hl(4, 11, 8, "BONE", _M)
	_hl(4, 11, 9, "BONE", _M)
	_hl(4, 11, 10, "BONE", _D)
	_hl(4, 11, 11, "BONE", _D)
	_vl(12, 4, 11, "BONE", _D)
	# ноги ряда
	_hl(3, 12, 12, "BONE", _O)
	# портняжная игла в углу — золотой акцент предмета
	_diag([[12, 2], [13, 1]], "HUD_GOLD", _L)
	_diag([[12, 3], [13, 2]], "HUD_GOLD", _M)

## sinew — «Волчья жила»: витая полоска (вердикт). Жилка идёт S-волной сверху
# вниз, на перехлёстах — тёмные складки скрутки; внизу капля алой крови
# (волк) как акцент.
static func _ic_item_sinew() -> void:
	# тело волны: два ряда MID с юго-восточной тенью
	_diag([[8, 2], [9, 3], [9, 4], [8, 5], [7, 6], [7, 7], [8, 8],
		[9, 9], [9, 10], [8, 11], [7, 12]], "PARCHMENT", _M)
	_diag([[10, 3], [10, 4], [9, 5], [8, 6], [8, 7], [9, 8], [10, 9],
		[10, 10], [9, 11], [8, 12]], "PARCHMENT", _D)
	# северо-западный светлый гребень (жилка влажно блестит)
	_diag([[7, 2], [8, 3], [8, 4], [7, 5], [6, 6], [6, 7], [7, 8],
		[8, 9], [8, 10], [7, 11], [6, 12]], "PARCHMENT", _L)
	# срезы концов
	_P(7, 1, "PARCHMENT", _L)
	_P(9, 1, "PARCHMENT", _M)
	# складки скрутки — тёмные штрихи в перетяжках
	_P(9, 4, "BONE", _O)
	_P(8, 7, "BONE", _O)
	_P(9, 10, "BONE", _O)
	# ноги ряда
	_diag([[6, 13], [7, 13], [8, 13]], "PARCHMENT", _O)
	# алый акцент — капля волчьей крови у bottom
	_P(10, 12, "HP_RED", _M)
	_P(10, 13, "HP_RED", _O)
	_P(11, 12, "HP_RED", _L)

## torch — «Факел»:Wood-древко в красной обмотке, пламя FIRE с горячим ядром.
static func _ic_item_torch() -> void:
	# древко (свет левый грань, тень правая, ноги ряда)
	_vl(6, 8, 13, "WOOD", _L)
	_vl(7, 8, 13, "WOOD", _M)
	_vl(8, 8, 13, "WOOD", _D)
	_hl(6, 8, 14, "WOOD", _O)
	# тряпица-обмотка под пламенем
	_hl(5, 9, 7, "HP_RED", _M)
	_hl(5, 9, 8, "HP_RED", _O)
	_P(5, 7, "HP_RED", _L)
	# пламя: капля с СЗ-светом, ядро HOT, нижняя кромка — тон контура
	_hl(6, 8, 2, "FIRE", _L)
	_hl(6, 8, 3, "FIRE", _M)
	_vl(9, 3, 5, "FIRE", _D)
	_P(9, 2, "FIRE", _M)
	_hl(6, 9, 4, "FIRE", _M)
	_hl(5, 9, 5, "FIRE", _M)
	_hl(5, 9, 6, "FIRE", _O)
	_F(7, 4, "FIRE_HOT")
	_F(7, 5, "FIRE_HOT")
	# искра-отлетевший уголёк
	_P(11, 1, "HUD_GOLD", _L)
	_P(12, 3, "HUD_GOLD", _M)

## resin — «Смола»: янтарная капля на отщепе коры; блик — горячая точка.
static func _ic_item_resin() -> void:
	# капля: узкое ухо сверху, пузо книзу; свет слева, тень справа
	_P(7, 1, "HUD_GOLD", _L)
	_hl(7, 8, 2, "HUD_GOLD", _M)
	_hl(6, 9, 3, "HUD_GOLD", _M)
	_hl(6, 9, 4, "HUD_GOLD", _M)
	_hl(5, 10, 5, "HUD_GOLD", _M)
	_hl(5, 10, 6, "HUD_GOLD", _M)
	_hl(6, 9, 7, "HUD_GOLD", _D)
	_P(5, 3, "HUD_GOLD", _L)
	_P(5, 4, "HUD_GOLD", _L)
	_P(5, 5, "HUD_GOLD", _M)
	_P(11, 4, "HUD_GOLD", _D)
	_P(11, 5, "HUD_GOLD", _D)
	_P(10, 6, "HUD_GOLD", _D)
	# блик — единственная горячая точка (как у glowcap-ядра)
	_F(7, 4, "FIRE_HOT")
	_F(6, 5, "FIRE_HOT")
	# нижняя кромка капли
	_hl(6, 9, 8, "HUD_GOLD", _O)
	# отщеп коры, на котором смола затвердела
	_hl(3, 12, 10, "BARK", _M)
	_hl(4, 11, 11, "BARK", _D)
	_hl(3, 12, 12, "BARK", _O)

## key — «Ключ пещеры»: бронзовое кольцо-ушко, стержень, два зубa вниз.
static func _ic_item_key() -> void:
	# ушко: колечко 4×4 с дыркой
	_hl(4, 6, 5, "BRONZE", _M)
	_vl(3, 6, 8, "BRONZE", _M)
	_vl(7, 6, 8, "BRONZE", _D)
	_hl(4, 6, 9, "BRONZE", _M)
	_P(4, 5, "BRONZE", _L)
	_P(3, 7, "BRONZE", _L)
	_P(4, 6, "BRONZE", _L)
	_P(5, 7, "BRONZE", _O)
	_P(5, 8, "BRONZE", _O)
	_P(4, 7, "BRONZE", _O)
	# стержень (светлая верхняя грань)
	_hl(7, 13, 7, "BRONZE", _M)
	_hl(8, 13, 6, "BRONZE", _L)
	# зубья вниз
	_vl(11, 8, 9, "BRONZE", _M)
	_vl(13, 8, 10, "BRONZE", _M)
	_P(12, 8, "BRONZE", _D)
	# ноги ряда
	_P(11, 10, "BRONZE", _O)
	_P(13, 11, "BRONZE", _O)
	_hl(12, 13, 7, "BRONZE", _O)

## amulet — «Амулет Леса»: кристальный лист на шнурке; ядро светится (он и
## в мире даёт подсветку — та же суть предмета).
static func _ic_item_amulet() -> void:
	# шнурок: два диагональных штриха к колечку
	_diag([[5, 1], [6, 2], [7, 3]], "CLOTH", _M)
	_diag([[11, 1], [10, 2], [9, 3]], "CLOTH", _M)
	_P(8, 3, "CLOTH", _O)
	# лист-капля CRYSTAL: свет левый бок, тень правый, жилка посередине
	_hl(7, 8, 4, "CRYSTAL", _L)
	_hl(6, 9, 5, "CRYSTAL", _L)
	_hl(5, 10, 6, "CRYSTAL", _M)
	_hl(5, 10, 7, "CRYSTAL", _M)
	_hl(5, 10, 8, "CRYSTAL", _M)
	_hl(6, 9, 9, "CRYSTAL", _D)
	_hl(7, 8, 10, "CRYSTAL", _D)
	_P(10, 6, "CRYSTAL", _D)
	_P(11, 7, "CRYSTAL", _D)
	_P(5, 6, "CRYSTAL", _L)
	_P(5, 7, "CRYSTAL", _L)
	_P(10, 8, "CRYSTAL", _D)
	# жилка — тёмная средняя линия
	_vl(8, 5, 9, "CRYSTAL", _O)
	# ноги ряда
	_hl(7, 8, 11, "CRYSTAL", _O)
	# светящееся ядро (акцент подсветки)
	_F(7, 7, "FIRE_HOT")

# ================== g20b (t63): снаряжение вердикта ==================
# Тот же канон ряда: LIGHT — верх/лево открытой грани, DARK — правый бок,
# OUTLINE — низ/кромка; материалы только PixelPalette (IRON — сталь клинков,
# BONE — кость клыка, UI_BLUE — гарда «северян», VIOLET — клыко-клинок).

## whet — «Точильный камень»: брусок с лоском заточки и искоркой трения.
static func _ic_item_whet() -> void:
	# тело бруска: верх световой, низ тёмный
	_hl(4, 10, 7, "IRON", _L)
	_hl(3, 10, 8, "IRON", _M)
	_hl(3, 10, 9, "IRON", _D)
	_hl(4, 11, 10, "IRON", _O)
	_vl(11, 8, 9, "IRON", _D)
	_P(11, 7, "IRON", _M)
	# лоск на верхней грани
	_hl(5, 8, 7, "BONE", _L)
	# искра трения (след заточки)
	_P(12, 5, "FIRE", _L)
	_P(13, 6, "FIRE", _M)
	_P(12, 7, "FIRE", _O)

## shortsword — «Краткий меч»: короткий прямой клинок, бронзовая гарда.
static func _ic_item_shortsword() -> void:
	_P(8, 2, "IRON", _L)
	_vl(7, 3, 8, "IRON", _L)
	_vl(8, 3, 8, "IRON", _M)
	_vl(9, 4, 8, "IRON", _D)
	_hl(9, 9, 3, "IRON", _O)
	# гарда и рукоять
	_hl(5, 11, 9, "BRONZE", _M)
	_P(5, 9, "BRONZE", _L)
	_P(11, 9, "BRONZE", _D)
	_vl(8, 10, 12, "BARK", _M)
	_P(8, 13, "BRONZE", _D)

## nordsword — «Меч северян»: широкое полотну, синяя гарда-«крылья».
static func _ic_item_nordsword() -> void:
	_P(8, 1, "IRON", _L)
	_vl(7, 2, 8, "IRON", _L)
	_vl(8, 2, 8, "IRON", _M)
	_vl(9, 2, 8, "IRON", _D)
	_vl(6, 4, 8, "IRON", _L)
	_vl(10, 5, 8, "IRON", _D)
	# гарда-крылья (северная синь)
	_hl(3, 13, 9, "UI_BLUE", _M)
	_hl(4, 12, 10, "UI_BLUE", _D)
	_P(3, 9, "UI_BLUE", _L)
	_P(13, 9, "UI_BLUE", _O)
	_P(13, 10, "UI_BLUE", _O)
	# рукоять в обмотке и яблоко
	_vl(8, 11, 13, "CLOTH", _D)
	_P(8, 14, "UI_BLUE", _O)

## fangblade — «Клыко-клинок»: изогнутый клык на стальной рукояти, фиолет
## вкрапление смолы (очень редкий — цвет рамки сделает своё, тут намёк).
static func _ic_item_fangblade() -> void:
	# клык: дуга BONE от низа-слева к острию вправо-вверх
	_vl(5, 9, 11, "BONE", _M)
	_P(5, 12, "BONE", _O)
	_diag([[6, 8], [7, 7], [8, 6], [9, 5]], "BONE", _M)
	_diag([[10, 4], [11, 3], [12, 2]], "BONE", _L)
	_P(13, 1, "BONE", _L)
	_P(6, 9, "BONE", _L)
	_P(7, 8, "BONE", _L)
	# теневая сторона клыка
	_diag([[6, 10], [7, 9], [8, 8], [9, 7], [10, 6], [11, 5], [12, 4]], "BONE", _D)
	# фиолетовая смола в основании
	_P(6, 11, "VIOLET", _M)
	_P(5, 10, "VIOLET", _D)
	# стальная рукоять с навершием
	_hl(2, 4, 13, "IRON", _M)
	_P(2, 13, "IRON", _L)
	_P(4, 13, "IRON", _O)

## leather — «Кожаный доспех»: нагрудник из дублёной кожи с заклёпками.
static func _ic_item_leather() -> void:
	_hl(5, 10, 3, "BARK", _L)
	_hl(4, 11, 4, "BARK", _M)
	_hl(4, 11, 5, "BARK", _M)
	_hl(4, 11, 6, "BARK", _D)
	_hl(5, 10, 7, "BARK", _D)
	_hl(5, 10, 8, "BARK", _O)
	# V-вырез
	_diag([[7, 4], [8, 5], [9, 4]], "BARK", _O)
	# заклёпки бронзой
	_P(5, 5, "BRONZE", _L)
	_P(10, 5, "BRONZE", _M)
	_P(7, 7, "BRONZE", _M)
	_P(9, 7, "BRONZE", _D)

## chain — «Кольчуга»: сетка колец (сталь), подкладка тёмная.
static func _ic_item_chain() -> void:
	# подкладка
	_hl(4, 11, 4, "CHAR", _D)
	_hl(4, 11, 5, "CHAR", _O)
	_hl(4, 11, 6, "CHAR", _O)
	# ряды колец (свет/тень в шахматке)
	for y in [4, 6]:
		for x in [5, 8, 11]:
			_P(x, y, "IRON", _L)
			_P(x + 1, y, "IRON", _M)
			_P(x, y + 1, "IRON", _D)
		for x in [6, 9]:
			_P(x + 1, y + 1, "IRON", _M)
	_hl(5, 10, 7, "IRON", _D)
	_hl(5, 10, 8, "IRON", _O)

## boarhide — «Шкура вепря»: шкура с клыками и щетиной (верх трофейного сета).
static func _ic_item_boarhide() -> void:
	# мездра: тёмный край сверху, тело кожи
	_hl(4, 11, 3, "BARK", _D)
	_hl(3, 12, 4, "BARK", _M)
	_hl(3, 12, 5, "BARK", _M)
	_hl(3, 12, 6, "BARK", _D)
	_hl(4, 11, 7, "BARK", _D)
	_hl(4, 11, 8, "BARK", _O)
	# щетина
	_vl(5, 1, 2, "CHAR", _D)
	_vl(8, 1, 2, "CHAR", _D)
	_vl(11, 1, 2, "CHAR", _D)
	# клыки по нижним углам
	_diag([[4, 9], [3, 10], [3, 11]], "BONE", _L)
	_diag([[11, 9], [12, 10], [12, 11]], "BONE", _M)
	_P(6, 6, "BONE", _M)
	_P(9, 6, "BONE", _D)

## hero — силуэт героя для колонки экипировки: голову/плечи/ пояс/меч в руке.
static func _ic_hero_silhouette() -> void:
	# голова
	_hl(7, 8, 2, "BONE", _L)
	_hl(7, 8, 3, "BONE", _M)
	_hl(6, 9, 4, "CLOTH", _D)
	# плечи и торс (плащ)
	_hl(5, 10, 5, "CLOTH", _M)
	_hl(5, 10, 6, "CLOTH", _M)
	_hl(5, 10, 7, "CLOTH", _D)
	# пояс
	_hl(6, 9, 8, "BRONZE", _M)
	# ноги
	_vl(6, 9, 12, "CLOTH", _D)
	_vl(9, 9, 12, "CLOTH", _D)
	_hl(5, 7, 13, "IRON", _O)
	_hl(8, 10, 13, "IRON", _O)
	# меч в правой руке
	_vl(12, 4, 10, "IRON", _M)
	_P(12, 3, "IRON", _L)
	_hl(11, 13, 11, "BRONZE", _M)

# ---------- низкоуровневая графика (предметы/таланты — легаси-примитивы) ----

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, c)

static func _hline(img: Image, x0: int, x1: int, y: int, c: Color) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		_px(img, x, y, c)

static func _vline(img: Image, x: int, y0: int, y1: int, c: Color) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		_px(img, x, y, c)

static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			_px(img, x, y, c)

## Рамка слота: фон + тёмный контур по канту (общий для всех заглушек).
static func _slot_bg(img: Image, ox: int = 0) -> void:
	for y in range(S):
		for x in range(1, S - 1):
			_px(img, ox + x, y, BG)
	for x in range(S):
		for y in [0, S - 1]:
			_px(img, ox + x, y, INK)
	for y in range(1, S - 1):
		_px(img, ox, y, INK)
		_px(img, ox + S - 1, y, INK)

static func _outline(img: Image, c: Color) -> void:
	for x in range(1, img.get_width() - 1):
		_px(img, x, 0, c)
		_px(img, x, img.get_height() - 1, c)
	for y in range(1, img.get_height() - 1):
		_px(img, 0, y, c)
		_px(img, img.get_width() - 1, y, c)

# ---------- предметные символы ----------
# c25: шесть иконок — дословный перенос утверждённого листа c24
# (tools_art/sheet_items.gd). Рисуются палитровыми примитивами на общем холсте;
# tech-рамка слота (_slot_bg) и легаси-заглушка для неизвестных id — как были.

static func _stamp_item(img: Image, id: String) -> void:
	_slot_bg(img)
	match id:
		"herb", "mushroom", "root", "ash", "berry", "glowcap":
			_cv = img
			_cv_ox = 0
			match id:
				"herb": _ic_item_herb()
				"mushroom": _ic_item_mushroom()
				"root": _ic_item_root()
				"ash": _ic_item_ash()
				"berry": _ic_item_berry()
				"glowcap": _ic_item_glowcap()
			_cv = null
			_cv_ox = 0
		"hide", "sinew", "torch", "resin", "key", "amulet":
			# g20a: сетка инвентаря (шкура/жила/факел/смола/ключ/амулет)
			_cv = img
			_cv_ox = 0
			match id:
				"hide": _ic_item_hide()
				"sinew": _ic_item_sinew()
				"torch": _ic_item_torch()
				"resin": _ic_item_resin()
				"key": _ic_item_key()
				"amulet": _ic_item_amulet()
			_cv = null
			_cv_ox = 0
		"whet", "shortsword", "nordsword", "fangblade", "boarhide", "leather", "chain", "hero":
			# g20b (t63): снаряжение вердикта + точильный камень + силуэт героя
			_cv = img
			_cv_ox = 0
			match id:
				"whet": _ic_item_whet()
				"shortsword": _ic_item_shortsword()
				"nordsword": _ic_item_nordsword()
				"fangblade": _ic_item_fangblade()
				"boarhide": _ic_item_boarhide()
				"leather": _ic_item_leather()
				"chain": _ic_item_chain()
				"hero": _ic_hero_silhouette()
			_cv = null
			_cv_ox = 0
		_:
			_hline(img, 4, 11, 8, ACC_G)

# ================== c30: «крепкое зелье» (brewed_btn) ==================
# Вердикт w2: «третий вариант с колбой» — круглая колба с пробкой и искрами
# (лист c28, секция F, alch2). Рисовалка _flask/_vial и вспомогательные
# _mask/_dilate/_merge/_spec_color/_paint16/_bake16 перенесены ДОСЛОВНО из
# tools_art/sheet_ui.gd (прецедент c25); стенд qa_lp сверяет рантайм-кадр
# побайтово с золотым кадром утверждённого листа (GOLD_C30_FLASK).

static func _mask(cells: Array) -> Array:
	var m := {}
	for c in cells:
		var p := String(c).split(",")
		m[int(p[0]) + int(p[1]) * 16] = 1
	return [m, false]

static func _dilate(m: Array) -> Array:
	var src: Dictionary = m[0]
	var out := {}
	for k in src:
		var x: int = k % 16
		var y: int = k / 16
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx: int = x + dx
				var ny: int = y + dy
				if nx >= 0 and ny >= 0 and nx < 16 and ny < 16:
					out[nx + ny * 16] = 1
	return [out, true]

static func _merge(a: Array, b: Array) -> Array:
	var m: Dictionary = a[0].duplicate()
	for k in b[0]:
		if not m.has(k):
			m[k] = b[0][k]
	return [m, "merged"]

static func _spec_color(spec: String) -> Color:
	if spec == "INK":
		return PAL.FLATS["INK"]
	var p := spec.split(":")
	return PAL.c(p[0], int(p[1]))

static func _paint16(img: Image, m: Array, ox: int, oy: int) -> void:
	var d: Dictionary = m[0]
	for k in d:
		var spec := String(d[k])
		var x: int = k % 16
		var y: int = k / 16
		img.set_pixel(ox + x, oy + y, _spec_color(spec))

static func _bake16(m: Array) -> Image:
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	_paint16(im, m, 0, 0)
	return im

static func _flask(fill: String, big: bool) -> Array:
	if not big:
		return _vial(fill)
	# большая круглая колба: пробка, горло 2, круглое пузато тело, искры
	var cells: Array = []
	cells.append("7,1")
	cells.append("8,1")
	for y in range(2, 6):
		cells.append("7,%d" % y)
		cells.append("8,%d" % y)
	var cy := 9
	var r := 5
	for y in range(cy - r, cy + r + 1):
		for x in range(8 - r - 1, 8 + r + 2):
			var dx: float = x - 7.5
			var dy: float = y - float(cy)
			if dx * dx + dy * dy <= float(r * r) + 3.0:
				cells.append("%d,%d" % [x, y])
	var b := _mask(cells)
	var bd: Dictionary = b[0]
	var toned := {}
	for k in bd:
		var x: int = k % 16
		var y: int = k / 16
		if y == 1:
			toned[k] = "BARK:%d" % _M
		elif y <= 5:
			toned[k] = "IRON:%d" % _L
		else:
			if x <= 7 and y <= 9:
				toned[k] = fill + ":%d" % _L
			elif x >= 9:
				toned[k] = fill + ":%d" % _D
			else:
				toned[k] = fill + ":%d" % _M
	var ring := {}
	for k in _dilate(b)[0]:
		if not bd.has(k):
			ring[k] = "IRON:%d" % _O
	var res := _merge([toned, "t"], [ring, "o"])
	res[0][13 + 4 * 16] = "HUD_GOLD:%d" % _L
	res[0][3 + 6 * 16] = "HUD_GOLD:%d" % _M
	res[0][12 + 7 * 16] = "HUD_GOLD:%d" % _L
	return res

static func _vial(fill: String) -> Array:
	# узкая пробирка: ободок, цилиндр 4, скруглённое дно
	var cells: Array = []
	for x in range(5, 11):
		cells.append("%d,3" % x)
	for y in range(4, 13):
		for x in range(6, 10):
			cells.append("%d,%d" % [x, y])
	for p in [[5, 13], [10, 13]]:
		cells.append("%d,%d" % [p[0], p[1]])
	var b := _mask(cells)
	var bd: Dictionary = b[0]
	var toned := {}
	for k in bd:
		var x: int = k % 16
		var y: int = k / 16
		if y == 3:
			toned[k] = "IRON:%d" % _L
		elif y <= 7:
			toned[k] = "IRON:%d" % _M
		else:
			if x <= 6:
				toned[k] = fill + ":%d" % _L
			elif x >= 9:
				toned[k] = fill + ":%d" % _D
			else:
				toned[k] = fill + ":%d" % _M
	var ring := {}
	for k in _dilate(b)[0]:
		if not bd.has(k):
			ring[k] = "IRON:%d" % _O
	return _merge([toned, "t"], [ring, "o"])

## Иконка крепкого зелья для brewed_btn (c30): колба варианта 3 листа c28.
static func brewed_icon() -> Texture2D:
	return ImageTexture.create_from_image(_bake16(_flask("HP_RED", true)))

# ---------------------------------------------------------------- g14: рубрики
## Эмблемы рубрик достижений (просьба пользователя 16.11): код-ген 8×8, тот же
## язык, что brewed_icon (рукописная маска-силуэт, тональный контур).
## g15 (просьба пользователя «крупнее и привлекательнее»): объём в 3 тона —
## СЗ-ребро LIGHT, тело MID, ЮВ-тень DARK, контур OUTLINE; у янтарной версии
## горячая точка блика FIRE_HOT (FLATS-прецедент). Состояния: закрытая — тусклый
## IRON, открытая — янтарь HUD_GOLD. Крупный вариант achv_big_icon — тот же арт,
## отпечатанный скейлом 3× (24×24, NEAREST): пиксель-арт не интерполируется,
## растровых файлов по-прежнему ноль; палитра — только PixelPalette (пины _inv12).
const _ACH_BODY := {
	# меч (боевые): клинок, гарде, рукоять
	"combat": ["4,0", "3,1", "4,1", "3,2", "4,2", "3,3", "4,3", "3,4", "4,4",
			"1,5", "2,5", "3,5", "4,5", "5,5", "6,5", "3,6", "4,6", "3,7", "4,7"],
	# два следа (исследования): левый и правый отпечатки со смещением
	"explore": ["2,0", "3,0", "2,1", "3,1", "2,2", "3,2", "2,3", "3,3",
			"4,4", "5,4", "4,5", "5,5", "4,6", "5,6", "4,7", "5,7"],
	# кузнечный молот (ремесло): бойок + рукоять
	"craft": ["2,0", "3,0", "4,0", "5,0", "6,0", "2,1", "3,1", "4,1", "5,1",
			"6,1", "4,2", "4,3", "4,4", "4,5", "4,6", "5,7"],
	# монета (сделка): диск + блик, кант тоном контура
	"trade": ["3,1", "4,1", "2,2", "3,2", "4,2", "5,2", "1,3", "2,3", "3,3",
			"4,3", "5,3", "6,3", "1,4", "2,4", "3,4", "4,4", "5,4", "6,4",
			"2,5", "3,5", "4,5", "5,5", "3,6", "4,6"],
	# спираль (петля): внешний виток + завиток к центру
	"loop": ["3,0", "4,0", "5,0", "2,1", "6,1", "2,2", "3,2", "4,2", "6,2",
			"1,3", "6,3", "1,4", "5,4", "1,5", "2,5", "3,5", "4,5", "6,5",
			"6,6", "2,6"],
}
static var _ach_tex_cache := {}

## 8×8 художественная эмблема в Image (тело-градиент + контур + блик).
static func _ach8(cat: String, unlocked: bool) -> Image:
	var rn := "HUD_GOLD" if unlocked else "IRON"
	var im := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	var body := {}
	for c in _ACH_BODY.get(cat, []):
		body[String(c)] = true
	# объём: СЗ-ребро LIGHT (нет соседа слева и сверху), ЮВ-тень DARK (нет
	# соседа справа и снизу), остальное MID — три тона палитры на силуэт
	for k in body:
		var p: PackedStringArray = String(k).split(",")
		var x := int(p[0])
		var y := int(p[1])
		var hi := (not body.has("%d,%d" % [x - 1, y])) \
				and (not body.has("%d,%d" % [x, y - 1]))
		var lo := (not body.has("%d,%d" % [x + 1, y])) \
				and (not body.has("%d,%d" % [x, y + 1]))
		var tone := _L if hi else (_D if (lo and not hi) else _M)
		im.set_pixel(x, y, PAL.c(rn, tone))
	# горячая точка блика — единственный FIRE_HOT на самый СЗ-пиксель тела,
	# только у янтарной (закрытой) версии: тусклая остаётся тусклой
	if unlocked:
		var gx := 99
		var gy := 99
		for k in body:
			var p2: PackedStringArray = String(k).split(",")
			var x2 := int(p2[0])
			var y2 := int(p2[1])
			if y2 * 8 + x2 < gy * 8 + gx:
				gx = x2
				gy = y2
		if gx < 99:
			im.set_pixel(gx, gy, PAL.FLATS["FIRE_HOT"])
	# контур OUTLINE: пустые соседние клетки вокруг силуэта (8-соседство)
	for y in 8:
		for x in 8:
			if body.has("%d,%d" % [x, y]):
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					if body.has("%d,%d" % [x + dx, y + dy]):
						near = true
			if near:
				im.set_pixel(x, y, PAL.c(rn, _O))
	return im

## Эмблема рубрики 8×8: cat — ключ из AchvCatalog.CAT_TITLES; unlocked — янтарь.
static func achv_icon(cat: String, unlocked: bool) -> Texture2D:
	var key := cat + ("|1" if unlocked else "|0")
	if _ach_tex_cache.has(key):
		return _ach_tex_cache[key]
	var tex := ImageTexture.create_from_image(_ach8(cat, unlocked))
	_ach_tex_cache[key] = tex
	return tex

## Крупная эмблема 24×24 (g15, плашка карточки): тот же 8×8 арт, скейл 3×
## интерполяцией NEAREST — пиксели ложатся ровно квадратами 3×3, арт код-ген.
static func achv_big_icon(cat: String, unlocked: bool) -> Texture2D:
	var key := cat + ("|1b" if unlocked else "|0b")
	if _ach_tex_cache.has(key):
		return _ach_tex_cache[key]
	var im := _ach8(cat, unlocked)
	im.resize(24, 24, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(im)
	_ach_tex_cache[key] = tex
	return tex
