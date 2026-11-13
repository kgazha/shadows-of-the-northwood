class_name UiIcons
extends RefCounted
## t52 снос (закон пользователя 13.11): ген-иконки item/skill/talent сняты.
## До ручного пиксель-прохода (t53+) — временные код-заглушки: тёмный контур
## + узнаваемый символ. Рисуются кодом в RGBA8 16 px — без картинок вообще;
## вид в духе HUD-панелей (тёплая охра на тёплом тёмно-коричневом), никакого
## gen-арта. Атлас скиллов — 12 слотов по 16 px, порядок = classes_data.gd.

const S := 16  # canonical slot size, px

# порядок слотов атласа скиллов (classes_data.gd: warrior 0-3, hunter 4-6,
# mage 7-11: power_strike, whirlwind, second_wind, execute, pierce, volley,
# mark, rain, firebolt, frost_nova, siphon, firestorm)
const SKILL_SLOTS := ["power_strike", "whirlwind", "second_wind", "execute", \
	"pierce", "volley", "mark", "rain", "firebolt", "frost_nova", "siphon", "firestorm"]

const INK := Color(0.16, 0.11, 0.08)      # тёмный контур/штрих
const BG := Color(0.23, 0.17, 0.12)       # фон слота — «дерево» HUD
const ACC_W := Color(0.85, 0.68, 0.32)    # воинская охра
const ACC_H := Color(0.55, 0.75, 0.42)    # охотничья зелень
const ACC_M := Color(0.45, 0.6, 0.95)     # магическая синь
const ACC_G := Color(0.72, 0.72, 0.78)    # сталь/пепел

static var _skill_atlas: Texture2D = null
static var _item_cache := {}

## Атлас скиллов 192x16 (12 слотов) — тот же контракт, что был у ген-атласа.
static func skill_atlas() -> Texture2D:
	if _skill_atlas != null:
		return _skill_atlas
	var img := Image.create_empty(S * SKILL_SLOTS.size(), S, false, Image.FORMAT_RGBA8)
	for i in SKILL_SLOTS.size():
		_stamp_skill(img, i, SKILL_SLOTS[i])
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

# ---------- низкоуровневая графика ----------

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

## Клинкок-«меч» — общая форма для воина/охотника/ранимых символов.
static func _blade(img: Image, ox: int, c: Color) -> void:
	for i in 8:  # лезвие из левого верха в центр
		_px(img, ox + 3 + i, 3 + i, c)
		_px(img, ox + 4 + i, 3 + i, c)
	_hline(img, ox + 2, ox + 6, 9, INK)  # гарда
	_vline(img, ox + 5, 9, 12, INK)       # рукоять

# ---------- скилловые символы ----------

static func _stamp_skill(img: Image, idx: int, id: String) -> void:
	_slot_bg(img, idx * S)
	var ox := idx * S
	match id:
		"power_strike":
			_blade(img, ox, ACC_W)
			_px(img, ox + 12, 4, ACC_W)  # искра усиления
			_px(img, ox + 13, 3, ACC_W)
		"whirlwind":
			for i in 9:  # дуга окружности
				var a := TAU * float(i) / 9.0
				_px(img, ox + 8 + roundi(cos(a) * 5.0), 8 + roundi(sin(a) * 5.0), ACC_W)
			_px(img, ox + 8, 8, INK)
		"second_wind":
			_hline(img, ox + 4, ox + 11, 6, ACC_W)
			_hline(img, ox + 3, ox + 10, 8, ACC_W)
			_px(img, ox + 12, 5, ACC_W)  # «порыв» — стрелка вправо
			_px(img, ox + 13, 6, ACC_W)
			_px(img, ox + 12, 9, ACC_W)
			_px(img, ox + 13, 8, ACC_W)
		"execute":
			_vline(img, ox + 8, 3, 11, INK)
			_hline(img, ox + 4, ox + 12, 3, ACC_W)  # топор палача
			_hline(img, ox + 5, ox + 11, 4, ACC_W)
		"pierce":
			_hline(img, ox + 2, ox + 13, 8, ACC_H)  # стрела сквозь
			_px(img, ox + 13, 7, ACC_H)
			_px(img, ox + 14, 8, ACC_H)
			_px(img, ox + 13, 9, ACC_H)
			_vline(img, ox + 3, 6, 10, INK)  # оперение
		"volley":
			for k in 3:
				_hline(img, ox + 4 + k * 3, ox + 6 + k * 3, 4, ACC_H)
				_vline(img, ox + 5 + k * 3, 4, 11, ACC_H)
				_px(img, ox + 5 + k * 3, 12, INK)
		"mark":
			for r in [5.0, 2.0]:  # мишень
				for i in 12:
					var a := TAU * float(i) / 12.0
					_px(img, ox + 8 + roundi(cos(a) * r), 8 + roundi(sin(a) * r), ACC_H)
			_px(img, ox + 8, 8, ACC_H)
		"rain":
			for k in 3:  # туча
				_hline(img, ox + 4 + k * 2, ox + 6 + k * 2, 4, ACC_M)
			for k in 3:  # капли-стрелы
				_vline(img, ox + 4 + k * 4, 7, 10, ACC_M)
				_px(img, ox + 4 + k * 4, 11, INK)
		"firebolt":
			_rect(img, ox + 7, 4, ox + 9, 9, ACC_M)
			_px(img, ox + 8, 3, ACC_W)  # язычок пламени
			_px(img, ox + 6, 5, ACC_M)
			_px(img, ox + 10, 5, ACC_M)
		"frost_nova":
			for i in 8:  # лучи снежинки
				var a := TAU * float(i) / 8.0
				for r in [2.0, 4.0, 6.0]:
					_px(img, ox + 8 + roundi(cos(a) * r), 8 + roundi(sin(a) * r), ACC_M)
		"siphon":
			_vline(img, ox + 8, 3, 7, ACC_M)
			for i in 5:  # воронка
				_hline(img, ox + 4 + i, ox + 12 - i, 8 + int(i * 0.75), ACC_M)
		"firestorm":
			for k in 4:  # столбы огня
				var bx := ox + 3 + k * 3
				_vline(img, bx, 6, 11, ACC_W)
				_px(img, bx, 5, Color(0.95, 0.55, 0.25))
			_hline(img, ox + 2, ox + 13, 12, INK)
		_:
			_hline(img, ox + 4, ox + 11, 8, ACC_G)

# ---------- предметные символы ----------

static func _stamp_item(img: Image, id: String) -> void:
	_slot_bg(img)
	match id:
		"herb":  # трава: три стебля с листьями
			for k in 3:
				var bx := 4 + k * 4
				_vline(img, bx, 5, 12, Color(0.4, 0.65, 0.32))
				_px(img, bx - 1, 6 + k, Color(0.5, 0.75, 0.38))
				_px(img, bx + 1, 8 + k % 2, Color(0.5, 0.75, 0.38))
		"mushroom":  # гриб: шляпка + ножка
			_rect(img, 4, 5, 11, 8, Color(0.72, 0.3, 0.28))
			_px(img, 6, 6, Color(0.9, 0.8, 0.7))
			_px(img, 9, 7, Color(0.9, 0.8, 0.7))
			_rect(img, 6, 9, 9, 12, Color(0.85, 0.78, 0.65))
		"root":  # корень: извилистая линия вниз
			_vline(img, 8, 3, 4, Color(0.55, 0.4, 0.25))
			_px(img, 7, 5, Color(0.55, 0.4, 0.25))
			_vline(img, 7, 5, 8, Color(0.55, 0.4, 0.25))
			_px(img, 8, 9, Color(0.55, 0.4, 0.25))
			_vline(img, 9, 9, 12, Color(0.55, 0.4, 0.25))
			_px(img, 6, 11, Color(0.55, 0.4, 0.25))
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
