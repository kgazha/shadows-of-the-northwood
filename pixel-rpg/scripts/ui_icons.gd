class_name UiIcons
extends RefCounted
## t52 снос (закон пользователя 13.11): ген-иконки item/skill/talent сняты.
## t53/c15: иконки скиллов v2 — принятый пользователем лист c11 интегрирован
## дословно (12 рисовалок перенесены из tools_art/sheet_icons.gd; попиксельное
## равенство листу гейтится самопроверкой генератора). Рисуются кодом в RGBA8
## 16 px — без картинок вообще. Атлас скиллов — 12 слотов по 16 px,
## порядок = classes_data.gd. Цвета иконок — только PixelPalette.RAMPS/FLATS;
## фон слота — технический SHEET.BG (как в утверждённом листе).

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

static func _stamp_item(img: Image, id: String) -> void:
	_slot_bg(img)
	match id:
		"herb":  # трава: три дудочки-листа
			for k in 3:
				var bx := 4 + k * 3
				_vline(img, bx, 5, 12, Color(0.4, 0.65, 0.32))
				_px(img, bx + 1, 7 - k, Color(0.5, 0.75, 0.38))
		"mushroom":  # гриб: шляпка-ножка
			_rect(img, 4, 5, 11, 8, Color(0.72, 0.3, 0.28))
			for k in 3:
				_px(img, 5 + k * 2, 6, Color(0.9, 0.85, 0.7))
			_rect(img, 6, 9, 9, 12, Color(0.85, 0.78, 0.65))
		"root":  # корень: вертикалка с боковушками
			_vline(img, 8, 3, 4, Color(0.55, 0.4, 0.25))
			_vline(img, 7, 5, 8, Color(0.55, 0.4, 0.25))
			_px(img, 9, 6, Color(0.55, 0.4, 0.25))
			_px(img, 6, 11, Color(0.55, 0.4, 0.25))
			_vline(img, 9, 9, 12, Color(0.55, 0.4, 0.25))
			_px(img, 11, 11, Color(0.55, 0.4, 0.25))
		"ash":  # пепел: урна-горка с точками
			_hline(img, 4, 11, 11, ACC_G)
			_hline(img, 5, 10, 10, ACC_G)
			_px(img, 6, 8, Color(0.6, 0.6, 0.66))
			_px(img, 9, 7, Color(0.6, 0.6, 0.66))
			_px(img, 7, 5, Color(0.5, 0.5, 0.56))
		"berry":  # ягода: три ягоды + лист
			for c in [[6, 9], [9, 10], [7, 12]]:
				_rect(img, c[0], c[1], c[0] + 1, c[1] + 1, Color(0.75, 0.25, 0.4))
			_vline(img, 8, 4, 7, Color(0.4, 0.65, 0.32))
			_px(img, 9, 4, Color(0.5, 0.75, 0.38))
		"glowcap":  # светособака: купол со свечением
			_rect(img, 5, 6, 10, 10, Color(0.45, 0.75, 0.85))
			_px(img, 4, 11, Color(0.35, 0.6, 0.7))
			_px(img, 11, 11, Color(0.35, 0.6, 0.7))
			_px(img, 7, 4, Color(0.8, 0.95, 1.0))
			_px(img, 9, 3, Color(0.8, 0.95, 1.0))
		_:
			_hline(img, 4, 11, 8, ACC_G)
