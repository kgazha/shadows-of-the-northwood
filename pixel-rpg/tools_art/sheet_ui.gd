extends SceneTree
## c28 «UI-мелочь v1» — лист на вердикт пользователя (игра НЕ тронута).
##
## Инвентарь (потребители по коду; подробности в REPORT c28):
##  ui/panel_frame.png 32x32 — 9-slice margin 4: hud._ui_frame_style
##    (StyleBoxTexture, ~7 экранов) + hud.rest_frame (NinePatchRect) + camp_panel;
##  ui/cursor_arrow.png 16 — Input.set_custom_mouse_cursor(ARROW, hot 0,0),
##    диалоги/модалки;
##  ui/cursor_crosshair.png 16 — мир/прицел (hot 8,8; фолбэк cursor_move);
##  cursor_move.png 16 — фолбэк-прицел (hot 8,8);
##  cursor_enemy.png 16 — атака (hot 8,8);
##  projectiles.png 64x16 — 4 кадра: 0 стрела (вращается), 1 файербол,
##    2 осколок льда, 3 стрела-призрак (modulate a=0.6, вращается);
##  key.png 16x16 — world-эффект подбора ключа;
##  campfire.png 80x16 — 5 кадров: fire-анимация [0..3] @7fps + ash [4];
##  alch_icons.png 48x16 — живой потребитель ОДИН: brewed_btn icon кадр 2
##    (hud.gd); кадры 0/1 — мертвы.
##
## Секции листа (легенда с координатами — в REPORT):
##  A: курсоры ×4 на тёмной и светлой подложках (читаемость);
##  B: курсоры ×1;
##  C: panel_frame 32×32 ×4 + честные 9-slice сборки 96×64 (×1) и ×2:
##     углы — копия 1:1, кромки 1px, центр solid (стретч-инвариантность);
##  D: снаряды ×4 + ×1; E: ключ ×4 + костёр 5 кадров ×4; F: алхимия ×4 (3 варианта);
##  G: реальная величина ×1 (тёмная подложка).
## Цвета объектов — только PixelPalette.RAMPS/FLATS. Свет СЗ, OUTLINE своего
## материала (UI-обводка — FLAT INK). Технические фоны: SHEET.BG, STONE-линии,
## PARCHMENT_M (светлая подложка) — прецедент c24.
##
## Запуск: godot --headless --path pixel-rpg -s res://tools_art/sheet_ui.gd -- <outdir>
## Пишет: <outdir>/sheet_ui.png и <outdir>/c28_current.png (легаси ×2 как «до»).
##
## Самопроверки (exit != 0 при провале):
##  1) off-palette = 0 во всех боксах новой отрисовки;
##  2) панель 32×32: полосы кромок постоянны вдоль оси стретча, центр solid,
##     сборка 96×64 == эталон, углы сборок 1:1 (побайтово);
##  3) popcount-различимость: курсоры min>=24, снаряды min>=32, алхимия min>=24;
##  4) читаемость курсоров: доля пикселей с |dY|>0.12 >= 12% против CHAR_DARK
##     и PARCHMENT_M; >=3 цвета палитры в каждом;
##  5) нижний ряд каждого спрайта — OUTLINE-тон (для UI-обводки допустим INK);
##  6) костёр: соседние fire-кадры различаются >=8 px, fire vs ash >=40 px.

const PAL := preload("res://scripts/pixel_palette.gd")

const _L := 0
const _M := 1
const _D := 2
const _O := 3

const Z := 4  # зум основной секции

var _img: Image
var _ox := 0
var _oy := 0
var _bufs: Dictionary = {}  # name -> Image 16×16 (источник метрик)
var _boxes: Array = []      # [x0,y0,w,h,name] — боксы новой отрисовки

# ---------- примитивы ----------

func _P(x: int, y: int, ramp: String, tone: int) -> void:
	var xx := x + _ox
	var yy := y + _oy
	if xx < 0 or yy < 0 or xx >= _img.get_width() or yy >= _img.get_height():
		return
	_img.set_pixel(xx, yy, PAL.c(ramp, tone))

func _F(x: int, y: int, flat: String) -> void:
	var xx := x + _ox
	var yy := y + _oy
	if xx < 0 or yy < 0 or xx >= _img.get_width() or yy >= _img.get_height():
		return
	_img.set_pixel(xx, yy, PAL.FLATS[flat])

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

static func _toned(m: Array, fn: Callable) -> Array:
	var src: Dictionary = m[0]
	var out := {}
	for k in src:
		out[k] = String(fn.call(k % 16, k / 16))
	return [out, "toned"]

static func _ring_of(o: Array, b: Array) -> Array:
	var bd: Dictionary = b[0]
	var src: Dictionary = o[0]
	var ring := {}
	for k in src:
		if not bd.has(k):
			ring[k] = "INK"
	return [ring, "outline_only"]

static func _merge(a: Array, b: Array) -> Array:
	var m: Dictionary = a[0].duplicate()
	for k in b[0]:
		if not m.has(k):
			m[k] = b[0][k]
	return [m, "merged"]

func _draw16(m: Array) -> void:
	var d: Dictionary = m[0]
	for k in d:
		var spec := String(d[k])
		var x: int = k % 16
		var y: int = k / 16
		if spec == "INK":
			_F(x, y, "INK")
		else:
			var parts := spec.split(":")
			_P(x, y, parts[0], int(parts[1]))

# ================== КУРОРЫ ==================

static func _cur_arrow() -> Array:
	# классическая стрелка NW, hotspot (0,0). Тело — PARCHMENT, обводка INK.
	var body: Array = []
	for y in range(0, 10):
		for x in range(0, y + 1):
			body.append("%d,%d" % [x, y])
	for y in range(10, 13):
		for x in range(3, 6):
			body.append("%d,%d" % [x, y])
	body.append("6,10")
	body.append("6,11")
	body.append("7,11")
	var b := _mask(body)
	var o := _dilate(b)
	var f := func(x: int, y: int) -> String:
		if x <= y - 2:
			return "PARCHMENT:%d" % _L
		if x == y or (y >= 10 and x >= 6):
			return "PARCHMENT:%d" % _D
		return "PARCHMENT:%d" % _M
	return _merge(_toned(b, f), _ring_of(o, b))

static func _cur_crosshair() -> Array:
	# мирный прицел: 4 штриха 2×3 + ядро-квадрат 2×2 золото. hot (8,8)->центр.
	var cells: Array = []
	for x in range(6, 8):
		for y in [1, 2, 3, 11, 12, 13]:
			cells.append("%d,%d" % [x, y])
	for y in range(6, 8):
		for x in [1, 2, 3, 11, 12, 13]:
			cells.append("%d,%d" % [x, y])
	for x in range(6, 8):
		for y in range(6, 8):
			cells.append("%d,%d" % [x, y])
	var b := _mask(cells)
	var o := _dilate(b)
	var f := func(x: int, y: int) -> String:
		if x >= 6 and x < 8 and y >= 6 and y < 8:
			if x == 6 and y == 6:
				return "HUD_GOLD:%d" % _L
			if x == 7 and y == 7:
				return "HUD_GOLD:%d" % _D
			return "HUD_GOLD:%d" % _M
		if x < 6 or (y < 6 and x < 8):
			return "IRON:%d" % _L
		if y >= 8 and x >= 8:
			return "IRON:%d" % _D
		return "IRON:%d" % _M
	return _merge(_toned(b, f), _ring_of(o, b))

static func _cur_move() -> Array:
	# кольцо действия (фолбэк-прицел/interact), золото, hot центр.
	var cells: Array = []
	var pts := [[8, 2], [9, 2], [7, 3], [10, 3], [6, 3], [5, 4], [11, 4], [4, 5],
		[12, 5], [4, 6], [12, 6], [3, 7], [3, 8], [4, 9], [12, 9], [4, 10],
		[12, 10], [5, 11], [11, 11], [6, 12], [10, 12], [7, 12], [9, 12], [8, 13]]
	for p in pts:
		cells.append("%d,%d" % [p[0], p[1]])
	var b := _mask(cells)
	var o := _dilate(b)
	var f := func(x: int, y: int) -> String:
		if y < 7 or (y < 9 and x < 8):
			return "HUD_GOLD:%d" % _L
		if y >= 9 and x >= 8:
			return "HUD_GOLD:%d" % _D
		return "HUD_GOLD:%d" % _M
	return _merge(_toned(b, f), _ring_of(o, b))

static func _cur_enemy() -> Array:
	# ромб-прицел атаки (HP_RED) + ядро. hot центр.
	var cells: Array = []
	for d in range(0, 4):
		cells.append("%d,%d" % [8 - d, 2 + d])
		cells.append("%d,%d" % [8 + d, 2 + d])
	for d in range(0, 4):
		cells.append("%d,%d" % [8 - d, 13 - d])
		cells.append("%d,%d" % [8 + d, 13 - d])
	for d in range(3, 6):
		cells.append("%d,%d" % [2 + d, 7])
		cells.append("%d,%d" % [2 + d, 8])
		cells.append("%d,%d" % [13 - d, 7])
		cells.append("%d,%d" % [13 - d, 8])
	for x in range(7, 9):
		for y in range(7, 9):
			cells.append("%d,%d" % [x, y])
	var b := _mask(cells)
	var o := _dilate(b)
	var f := func(x: int, y: int) -> String:
		if x >= 7 and x < 9 and y >= 7 and y < 9:
			if x == 7 and y == 7:
				return "PARCHMENT:%d" % _L
			return "PARCHMENT:%d" % _M
		if y <= 7 - absi(8 - x) + 1 or (x < 8 and y < 8):
			return "HP_RED:%d" % _L
		if y >= 8 and x >= 8:
			return "HP_RED:%d" % _D
		return "HP_RED:%d" % _M
	return _merge(_toned(b, f), _ring_of(o, b))

# ================== PANEL_FRAME 32×32 ==================

static func _pf_band_top(r: int) -> String:
	match r:
		0: return "INK"
		1: return "WOOD:%d" % _D
		2: return "WOOD:%d" % _O
		_: return "CHAR:%d" % _D

static func _pf_band_bottom(r: int) -> String:  # r = 31-y (0..3)
	match r:
		0: return "INK"
		1: return "WOOD:%d" % _O
		2: return "WOOD:%d" % _O
		_: return "CHAR:%d" % _D

static func _pf_band_left(c: int) -> String:
	match c:
		0: return "INK"
		1: return "WOOD:%d" % _D
		2: return "WOOD:%d" % _O
		_: return "CHAR:%d" % _D

static func _pf_band_right(c: int) -> String:  # c = 31-x
	match c:
		0: return "INK"
		1: return "WOOD:%d" % _O
		2: return "WOOD:%d" % _O
		_: return "CHAR:%d" % _D

## Полный 32×32 как словарь (x,y)->spec; центр solid CHAR_D. Полосы постоянны
## вдоль оси стретча; углы 4×4 переносят соседние полосы без шва (СЗ свет).
static func _pf_pixels() -> Dictionary:
	var d := {}
	for y in range(0, 32):
		for x in range(0, 32):
			var spec := ""
			var dt := y
			var db := 31 - y
			var dl := x
			var dr := 31 - x
			var m := mini(mini(dt, db), mini(dl, dr))
			if m >= 4:
				spec = "CHAR:%d" % _D
			elif dt <= 3 and dl <= 3:
				spec = _pf_band_top(dt) if dt <= dl else _pf_band_left(dl)
			elif dt <= 3 and dr <= 3:
				spec = _pf_band_top(dt) if dt <= dr else _pf_band_right(dr)
			elif db <= 3 and dl <= 3:
				spec = _pf_band_bottom(db) if db <= dl else _pf_band_left(dl)
			elif db <= 3 and dr <= 3:
				spec = _pf_band_bottom(db) if db <= dr else _pf_band_right(dr)
			elif dt <= 3:
				spec = _pf_band_top(dt)
			elif db <= 3:
				spec = _pf_band_bottom(db)
			elif dl <= 3:
				spec = _pf_band_left(dl)
			else:
				spec = _pf_band_right(dr)
			d[x + y * 32] = spec
	return d

var _pf_cache: Dictionary = {}

static func _spec_color(spec: String) -> Color:
	if spec == "INK":
		return PAL.FLATS["INK"]
	var p := spec.split(":")
	return PAL.c(p[0], int(p[1]))

func _pf_draw(x0: int, y0: int, scale: int) -> void:
	if _pf_cache.is_empty():
		_pf_cache = _pf_pixels()
	for y in range(0, 32):
		for x in range(0, 32):
			var c := _spec_color(String(_pf_cache[x + y * 32]))
			for sy in range(0, scale):
				for sx in range(0, scale):
					var xx := x0 + x * scale + sx
					var yy := y0 + y * scale + sy
					if xx < _img.get_width() and yy < _img.get_height():
						_img.set_pixel(xx, yy, c)

## Сборка 9-slice из 32×32 по margin 4 в w×h — эталон «как в игре».
static func _pf_nine(w: int, h: int) -> Image:
	var src := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var px := _pf_pixels()
	for y in range(0, 32):
		for x in range(0, 32):
			src.set_pixel(x, y, _spec_color(String(px[x + y * 32])))
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(0, h):
		for x in range(0, w):
			var sx: int
			var sy: int
			if x < 4:
				sx = x
			elif x >= w - 4:
				sx = 28 + (x - (w - 4))
			else:
				sx = 20  # середина кромки: полоса постоянна вдоль оси стретча
			if y < 4:
				sy = y
			elif y >= h - 4:
				sy = 28 + (y - (h - 4))
			else:
				sy = 20
			out.set_pixel(x, y, src.get_pixel(sx, sy))
	return out

func _blit_image(img: Image, x0: int, y0: int, scale: int) -> void:
	for y in range(0, img.get_height()):
		for x in range(0, img.get_width()):
			var c: Color = img.get_pixel(x, y)
			for sy in range(0, scale):
				for sx in range(0, scale):
					var xx := x0 + x * scale + sx
					var yy := y0 + y * scale + sy
					if xx < _img.get_width() and yy < _img.get_height():
						_img.set_pixel(xx, yy, c)

# ================== СНАРЯДЫ ==================

static func _prj_arrow(body_ramp: String) -> Array:
	# стрела вправо; ramp-материал тела (IRON — обычная, BONE — призрак)
	var cells: Array = []
	for x in range(3, 12):
		cells.append("%d,7" % x)
		cells.append("%d,8" % x)
	for d in range(0, 3):
		for y in range(7 - d, 9 + d):
			cells.append("%d,%d" % [12 + d, y])
	for y in range(5, 11):
		var w: int = 6 - absi(y - 7) * 2
		for x in range(2, 2 + maxi(1, w)):
			cells.append("%d,%d" % [x, y])
	var b := _mask(cells)
	var o := _dilate(b)
	var f := func(x: int, y: int) -> String:
		if x >= 12:
			return body_ramp + ":%d" % (_L if y <= 7 else _M)
		if x <= 4:
			return "CLOTH:%d" % (_L if y < 7 else (_M if y <= 8 else _D))
		return body_ramp + ":%d" % (_L if y == 7 else _M)
	var bd: Dictionary = b[0]
	var ring := {}
	for k in o[0]:
		if not bd.has(k):
			var x: int = k % 16
			if x <= 3:
				ring[k] = "CLOTH:%d" % _O
			elif body_ramp == "IRON":
				ring[k] = "IRON:%d" % _O
			else:
				ring[k] = body_ramp + ":%d" % _O
	return _merge(_toned(b, f), [ring, "o"])

static func _prj_fireball() -> Array:
	var cells: Array = []
	for y in range(4, 12):
		for x in range(4, 12):
			var dx: float = x - 7.5
			var dy: float = y - 7.5
			if dx * dx + dy * dy <= 16.0:
				cells.append("%d,%d" % [x, y])
	for p in [[2, 6], [1, 7], [2, 9]]:
		cells.append("%d,%d" % [p[0], p[1]])
	var b := _mask(cells)
	var o := _dilate(b)
	var f := func(x: int, y: int) -> String:
		if x <= 2:
			return "ASH_EMBER:%d" % (_L if y == 6 else _M)
		var dx: float = x - 7.5
		var dy: float = y - 7.5
		var dd := dx * dx + dy * dy
		if dd <= 5.0:
			return "FIRE:%d" % _L
		if dd > 12.0:
			return "FIRE:%d" % _D
		if dx + dy < 0:
			return "FIRE:%d" % _M
		return "FIRE:%d" % _D
	var bd: Dictionary = b[0]
	var ring := {}
	for k in o[0]:
		if not bd.has(k):
			ring[k] = ("FIRE:%d" % _O) if (k % 16) > 2 else ("ASH_EMBER:%d" % _O)
	return _merge(_toned(b, f), [ring, "o"])

static func _prj_ice() -> Array:
	# осколок льда: вытянутый ромб вправо
	var cells: Array = []
	for x in range(3, 14):
		var hh: int
		if x < 10:
			hh = int(round(1.0 + float(10 - x) * 0.4))
		else:
			hh = maxi(1, 3 - (x - 9))
		for d in range(0, hh + 1):
			cells.append("%d,%d" % [x, 7 - d])
			cells.append("%d,%d" % [x, 8 + d])
	var b := _mask(cells)
	var o := _dilate(b)
	var f := func(x: int, y: int) -> String:
		if y < 7 or (y == 7 and x < 9):
			return "CRYSTAL:%d" % _L
		if y >= 8 and x > 8:
			return "CRYSTAL:%d" % _D
		return "CRYSTAL:%d" % _M
	var bd: Dictionary = b[0]
	var ring := {}
	for k in o[0]:
		if not bd.has(k):
			ring[k] = "CRYSTAL:%d" % _O
	return _merge(_toned(b, f), [ring, "o"])

# ================== КЛЮЧ ==================

static func _key() -> Array:
	# ушко-кольцо сверху, стержень вниз, два зуба вправо.
	var cells: Array = []
	for p in [[8, 1], [9, 1], [7, 2], [10, 2], [6, 3], [11, 3], [6, 4], [11, 4],
		[7, 5], [10, 5], [8, 6], [9, 6]]:
		cells.append("%d,%d" % [p[0], p[1]])
	for y in range(6, 14):
		cells.append("%d,%d" % [7, y])
		cells.append("%d,%d" % [8, y])
	for p in [[9, 10], [10, 10], [9, 11], [10, 11], [9, 13], [10, 13], [11, 13]]:
		cells.append("%d,%d" % [p[0], p[1]])
	var b := _mask(cells)
	var o := _dilate(b)
	var f := func(x: int, y: int) -> String:
		if y <= 3 or (y < 5 and x < 8):
			return "HUD_GOLD:%d" % _L
		if (y >= 9 and x >= 9) or (x >= 8 and y >= 4):
			return "HUD_GOLD:%d" % _D
		return "HUD_GOLD:%d" % _M
	var bd: Dictionary = b[0]
	var ring := {}
	for k in o[0]:
		if not bd.has(k):
			ring[k] = "HUD_GOLD:%d" % _O
	return _merge(_toned(b, f), [ring, "o"])

# ================== КОСТЁР 16×16 ×5 ==================

static func _camp_logs() -> Array:
	# два пересеженных бревна (общие для fire-кадров)
	var cells: Array = []
	for d in range(0, 9):
		for w in range(0, 2):
			cells.append("%d,%d" % [3 + d, 13 + w - int(d / 3)])
	for d in range(0, 9):
		for w in range(0, 2):
			cells.append("%d,%d" % [12 - d, 13 + w - int(d / 3)])
	var b := _mask(cells)
	var f := func(x: int, y: int) -> String:
		if x > 8 or (x + y) % 3 == 0:
			return "BARK:%d" % _D
		return "BARK:%d" % _M
	var bd: Dictionary = b[0]
	var ring := {}
	for k in _dilate(b)[0]:
		if not bd.has(k):
			ring[k] = "BARK:%d" % _O
	return _merge(_toned(b, f), [ring, "o"])

static func _camp_fire(h: int, tilt: int) -> Array:
	# пламя высоты h, наклон верхушки tilt; поверх брёвен
	var cells: Array = []
	var base := 11
	for i in range(0, h):
		var y: int = base - i
		var half := int(round(float(h - i) / 3.0)) + 1
		var cx := 8 + int(round(float(tilt * i) / float(maxi(1, h - 1))))
		for x in range(cx - half, cx + half + 1):
			cells.append("%d,%d" % [x, y])
	var b := _mask(cells)
	var bd: Dictionary = b[0]
	var toned := {}
	for k in bd:
		var x: int = k % 16
		var y: int = k / 16
		var dy: int = base - y
		if dy >= h - 2 and x <= 8:
			toned[k] = "FIRE:%d" % _L
		elif x >= 9:
			toned[k] = "FIRE:%d" % _D
		elif dy >= 3 and x <= 7:
			toned[k] = "FIRE:%d" % _M
		else:
			toned[k] = "FIRE:%d" % _M
	var ring := {}
	for k in _dilate(b)[0]:
		if not bd.has(k):
			ring[k] = "FIRE:%d" % _O
	var m: Dictionary = toned.duplicate()
	for p in [[4, base - h + 1], [12, base - h + 2]]:
		m[p[0] + p[1] * 16] = "ASH_EMBER:%d" % _M
	for k in ring:
		if not m.has(k):
			m[k] = ring[k]
	var logs: Array = _camp_logs()
	var out: Dictionary = {}
	for k in m:
		out[k] = m[k]
	for k in logs[0]:
		out[k] = logs[0][k]
	return [out, "camp"]

static func _camp_ash() -> Array:
	var cells: Array = []
	for d in range(0, 9):
		for w in range(0, 2):
			cells.append("%d,%d" % [3 + d, 13 + w - int(d / 3)])
	for d in range(0, 9):
		for w in range(0, 2):
			cells.append("%d,%d" % [12 - d, 13 + w - int(d / 3)])
	for x in range(3, 14):
		cells.append("%d,11" % x)
	for p in [[4, 10], [12, 10]]:
		cells.append("%d,%d" % [p[0], p[1]])
	var b := _mask(cells)
	var bd: Dictionary = b[0]
	var toned := {}
	for k in bd:
		var x: int = k % 16
		var y: int = k / 16
		if y == 10:
			toned[k] = "ASH_EMBER:%d" % _M  # тлеющие угли
		elif y <= 11:
			toned[k] = "ASH_GROUND:%d" % _L
		elif x >= 9 or y >= 14:
			toned[k] = "CHAR:%d" % _D
		else:
			toned[k] = "CHAR:%d" % _M
	var ring := {}
	for k in _dilate(b)[0]:
		if not bd.has(k):
			ring[k] = "CHAR:%d" % _O
	return _merge([toned, "t"], [ring, "o"])

# ================== АЛХИМИЯ (3 варианта, кадр 2 — живой) ==================

static func _al_herb() -> Array:
	var cells: Array = []
	for y in range(3, 12):
		cells.append("%d,%d" % [8, y])
		cells.append("%d,%d" % [9, y])
	for p in [[6, 4], [5, 5], [4, 6], [11, 4], [12, 5], [13, 6], [6, 6], [11, 6]]:
		cells.append("%d,%d" % [p[0], p[1]])
	for x in range(5, 12):
		cells.append("%d,3" % x)
	var b := _mask(cells)
	var bd: Dictionary = b[0]
	var toned := {}
	for k in bd:
		var x: int = k % 16
		var y: int = k / 16
		if x >= 8 and x <= 9 and y >= 6:
			toned[k] = "LEAF:%d" % _D
		elif y <= 4 or x < 8:
			toned[k] = "LEAF:%d" % _L
		else:
			toned[k] = "LEAF:%d" % _M
	var ring := {}
	for k in _dilate(b)[0]:
		if not bd.has(k):
			ring[k] = "LEAF:%d" % _O
	return _merge([toned, "t"], [ring, "o"])

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

# ================== ВЫПЕЧКА ИГРОВЫХ PNG (c29, единый источник) ==================
# Те же маски/тона, что на утверждённом листе: стенд qa_lp вызывает bake_assets()
# in-process и сверяет побайтово с ассетами (прецедент t16/cave_paint).

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

static func _bake_strip(masks: Array, frame: int) -> Image:
	var im := Image.create(frame * masks.size(), 16, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	for i in range(0, masks.size()):
		_paint16(im, masks[i], i * frame, 0)
	return im

static func bake_panel_frame() -> Image:
	var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var px := _pf_pixels()
	for y in range(0, 32):
		for x in range(0, 32):
			im.set_pixel(x, y, _spec_color(String(px[x + y * 32])))
	return im

static func bake_projectiles() -> Image:
	return _bake_strip([_prj_arrow("IRON"), _prj_fireball(), _prj_ice(),
		_prj_arrow("BONE")], 16)

static func bake_campfire() -> Image:
	return _bake_strip([_camp_fire(6, 0), _camp_fire(9, -1), _camp_fire(8, 1),
		_camp_fire(7, 0), _camp_ash()], 16)

static func bake_cursors() -> Dictionary:
	return {
		"cursor_arrow.png": _bake16(_cur_arrow()),
		"cursor_crosshair.png": _bake16(_cur_crosshair()),
		"cursor_move.png": _bake16(_cur_move()),
		"cursor_enemy.png": _bake16(_cur_enemy()),
	}

## имя файла -> Image (RGBA8, прозрачный фон). Единственный источник ребейка.
static func bake_assets() -> Dictionary:
	var out := bake_cursors()
	out["panel_frame.png"] = bake_panel_frame()
	out["projectiles.png"] = bake_projectiles()
	out["key.png"] = _bake16(_key())
	out["campfire.png"] = bake_campfire()
	return out

## имя файла -> путь в игре (потребители не меняются: размеры/hotspot/margin)
static func res_paths() -> Dictionary:
	return {
		"panel_frame.png": "res://assets/ui/panel_frame.png",
		"cursor_arrow.png": "res://assets/ui/cursor_arrow.png",
		"cursor_crosshair.png": "res://assets/ui/cursor_crosshair.png",
		"cursor_move.png": "res://assets/cursor_move.png",
		"cursor_enemy.png": "res://assets/cursor_enemy.png",
		"projectiles.png": "res://assets/projectiles.png",
		"key.png": "res://assets/key.png",
		"campfire.png": "res://assets/campfire.png",
	}

## off-пиксели спрайтового PNG (непрозрачные вне RAMPS/FLATS; маски — отдельно)
static func off_of_image(im: Image) -> Dictionary:
	var idx := PAL.color_index()
	var off := 0
	var masks := 0
	for y in range(0, im.get_height()):
		for x in range(0, im.get_width()):
			var c := im.get_pixel(x, y)
			var a := int(c.a * 255.0)
			if a == 0:
				continue
			if a < 255:
				masks += 1
				continue
			if not idx.has(PAL.key(c)):
				off += 1
	return {"off": off, "mask_px": masks}

func _emit_assets(out_dir: String) -> int:
	var rc := 0
	var baked := bake_assets()
	for name in baked:
		var img: Image = baked[name]
		var path := out_dir + "/" + String(name)
		var err := img.save_png(path)
		var st := off_of_image(img)
		print("EMIT %s md5=%s off=%d mask_px=%d err=%d" % [name,
			FileAccess.get_md5(path), int(st["off"]), int(st["mask_px"]), err])
		if err != OK:
			rc = 1
	return rc

## ребейк НА МЕСТЕ (c29): пишет ровно в res://-пути потребителей.
func _inplace_assets() -> int:
	var rc := 0
	var baked := bake_assets()
	for name in baked:
		var img: Image = baked[name]
		var path := String(res_paths()[name])
		var err := img.save_png(path)
		var st := off_of_image(img)
		print("INPLACE %s -> %s md5=%s off=%d mask_px=%d err=%d" % [name, path,
			FileAccess.get_md5(path), int(st["off"]), int(st["mask_px"]), err])
		if err != OK:
			rc = 1
	return rc

# ================== ЛИСТ ==================

func _frame_outline(x: int, y: int, w: int, h: int) -> void:
	for i in range(0, w):
		_img.set_pixel(x + i, y, PAL.c("STONE", _O))
		_img.set_pixel(x + i, y + h - 1, PAL.c("STONE", _O))
	for j in range(0, h):
		_img.set_pixel(x, y + j, PAL.c("STONE", _O))
		_img.set_pixel(x + w - 1, y + j, PAL.c("STONE", _O))

func _cell_bg(x: int, y: int, w: int, h: int, c: Color) -> void:
	_img.fill_rect(Rect2i(x, y, w, h), c)

func _draw16z(mask: Array, x: int, y: int, z: int, name: String = "") -> void:
	# рисуем в буфер 16 БЕЗ смещения, потом блитим ×z в (x,y) листа
	_ox = 0
	_oy = 0
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var save := _img
	_img = im
	_draw16(mask)
	_img = save
	if name != "":
		_bufs[name] = im
	for yy in range(0, 16):
		for xx in range(0, 16):
			var c: Color = im.get_pixel(xx, yy)
			if c.a > 0.0:
				for sy in range(0, z):
					for sx in range(0, z):
						_img.set_pixel(x + xx * z + sx, y + yy * z + sy, c)

func _bake(out_dir: String) -> int:
	var W := 648
	var cur_masks := [_cur_arrow(), _cur_crosshair(), _cur_move(), _cur_enemy()]
	var H := 16
	H += 20 + 16 * Z
	H += 12 + 16 + 26
	H += 20 + 32 * Z
	H += 12 + 16 * Z + 36
	H += 12 + 16 * Z
	H += 12 + 16 * Z
	H += 12 + 16
	H += 6
	_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_img.fill(PAL.SHEET.BG)

	# тёмная подложка — техцвет листа; читаемость считается из буферов
	# против CHAR_DARK / PARCHMENT_M (реальные фоны игры).
	var dark := PAL.SHEET.BG
	var light := PAL.c("PARCHMENT", _M)
	var y := 8
	# --- A: курсоры ×4 (тёмная/светлая подложки) ---
	for i in range(0, 4):
		var x := 8 + i * (16 * Z + 8)
		_cell_bg(x - 2, y - 2, 16 * Z + 4, 16 * Z + 4, dark)
		_draw16z(cur_masks[i], x, y, Z, "cur%d" % i)
		_boxes.append([x, y, 16 * Z, 16 * Z, "cur%d_dark" % i])
		var x2 := 8 + (i + 4) * (16 * Z + 8)
		_cell_bg(x2 - 2, y - 2, 16 * Z + 4, 16 * Z + 4, light)
		_draw16z(cur_masks[i], x2, y, Z, "cur%d_light" % i)
		_boxes.append([x2, y, 16 * Z, 16 * Z, "cur%d_light" % i])
	y += 16 * Z + 10

	# --- B: курсоры ×1 (тёмная и светлая полосы) + key ×1 на светлой ---
	_cell_bg(8, y - 2, 4 * 20 + 28, 20, dark)
	for i in range(0, 4):
		_draw16z(cur_masks[i], 11 + i * 20, y, 1)
	_draw16z(_key(), 11 + 4 * 20 + 4, y, 1)
	_boxes.append([8, y - 2, 4 * 20 + 28, 20, "row1d"])
	_cell_bg(8, y + 24, 4 * 20 + 6, 20, light)
	for i in range(0, 4):
		_draw16z(cur_masks[i], 11 + i * 20, y + 26, 1)
	_boxes.append([8, y + 24, 4 * 20 + 6, 20, "row1l"])
	y += 52

	# --- C: panel_frame ---
	_pf_draw(8, y, Z)
	_boxes.append([8, y, 128, 128, "pf_new"])
	var p1 := _pf_nine(96, 64)
	_blit_image(p1, 8 + 128 + 12, y + 32, 1)
	_boxes.append([8 + 128 + 12, y + 32, 96, 64, "pf96"])
	_blit_image(p1, 8 + 128 + 12 + 96 + 16, y, 2)
	_boxes.append([8 + 128 + 12 + 96 + 16, y, 192, 128, "pf192"])
	# хайдлайнеры сборок — вне боксов
	var mx := 8 + 128 + 12 + 96 + 16
	_frame_outline(mx - 3, y - 5, 198, 4)
	_frame_outline(mx - 3, y + 128 + 1, 198, 4)
	y += 128 + 12

	# --- D: снаряды ×4 + ×1 ---
	var prjs := [_prj_arrow("IRON"), _prj_fireball(), _prj_ice(), _prj_arrow("BONE")]
	for i in range(0, 4):
		var x := 8 + i * (16 * Z + 8)
		_cell_bg(x - 2, y - 2, 16 * Z + 4, 16 * Z + 4, dark)
		_draw16z(prjs[i], x, y, Z, "prj%d" % i)
		_boxes.append([x, y, 64, 64, "prj%d" % i])
	_cell_bg(8, y + 16 * Z + 4, 4 * 20 + 6, 20, dark)
	for i in range(0, 4):
		_draw16z(prjs[i], 11 + i * 20, y + 16 * Z + 6, 1)
	_boxes.append([8, y + 16 * Z + 4, 4 * 20 + 6, 20, "prjrow"])
	y += 16 * Z + 4 + 20 + 12

	# --- E: ключ ×4, костёр 5 кадров ×4 ---
	_cell_bg(6, y - 2, 16 * Z + 4, 16 * Z + 4, dark)
	_draw16z(_key(), 8, y, Z, "key")
	_boxes.append([8, y, 64, 64, "key"])
	var cx := 8 + 16 * Z + 16
	var fires := [_camp_fire(6, 0), _camp_fire(9, -1), _camp_fire(8, 1), _camp_fire(7, 0), _camp_ash()]
	for i in range(0, 5):
		var x := cx + i * (16 * Z + 6)
		_cell_bg(x - 2, y - 2, 16 * Z + 4, 16 * Z + 4, dark)
		_draw16z(fires[i], x, y, Z, "camp%d" % i)
		_boxes.append([x, y, 64, 64, "camp%d" % i])
	y += 16 * Z + 12

	# --- F: алхимия ×4 ---
	var alchs := [_al_herb(), _flask("HP_RED", false), _flask("HP_RED", true)]
	for i in range(0, 3):
		var x := 8 + i * (16 * Z + 8)
		_cell_bg(x - 2, y - 2, 16 * Z + 4, 16 * Z + 4, dark)
		_draw16z(alchs[i], x, y, Z, "alch%d" % i)
		_boxes.append([x, y, 64, 64, "alch%d" % i])
	y += 16 * Z + 12

	# --- G: реальная величина ×1 ---
	var gx := 8
	_cell_bg(6, y - 2, W - 16, 20, dark)
	for i in range(0, 4):
		_draw16z(cur_masks[i], gx, y, 1)
		gx += 22
	gx += 6
	for i in range(0, 4):
		_draw16z(prjs[i], gx, y, 1)
		gx += 20
	_draw16z(_key(), gx, y, 1)
	gx += 22
	for i in range(0, 5):
		_draw16z(fires[i], gx, y, 1)
		gx += 20
	for i in range(0, 3):
		_draw16z(alchs[i], gx, y, 1)
		gx += 20
	_pf_draw(gx + 4, y - 8, 1)
	_boxes.append([6, y - 2, W - 16, 20, "rowG"])

	var err := _img.save_png(out_dir + "/sheet_ui.png")
	if err != OK:
		print("SAVE FAIL ", err)
		return 1
	_legacy_contact(out_dir + "/c28_current.png")
	return 0

## «Как сейчас»: легаси-кропы ×2 из реальных PNG (только чтение ассетов).
func _legacy_contact(out_png: String) -> void:
	var files := ["res://assets/ui/panel_frame.png", "res://assets/ui/cursor_arrow.png",
		"res://assets/ui/cursor_crosshair.png", "res://assets/cursor_move.png",
		"res://assets/cursor_enemy.png", "res://assets/projectiles.png",
		"res://assets/key.png", "res://assets/campfire.png", "res://assets/alch_icons.png"]
	var imgs: Array = []
	var w := 8
	for f in files:
		var im := Image.load_from_file(f)
		imgs.append(im)
		w += im.get_width() * 2 + 8
	var big := Image.create(w, 32 * 2 + 8, false, Image.FORMAT_RGBA8)
	big.fill(PAL.SHEET.BG)
	var x := 4
	for im in imgs:
		var z := 2
		for yy in range(0, im.get_height()):
			for xx in range(0, im.get_width()):
				var c: Color = im.get_pixel(xx, yy)
				if c.a > 0.0:
					for sy in range(0, z):
						for sx in range(0, z):
							big.set_pixel(x + xx * z + sx, 4 + yy * z + sy, c)
		x += im.get_width() * z + 8
	var err := big.save_png(out_png)
	print("LEGACY ", out_png, " err=", err)

# ==================== метрики/самопроверки ====================

static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

func _pal_keys() -> Dictionary:
	var k := {}
	for col in PAL.color_index():
		k[col] = true
	return k

func _is_tech(c: Color) -> bool:
	for kk in PAL.SHEET:
		if PAL.key(c) == PAL.key(PAL.SHEET[kk]):
			return true
	for rn in ["STONE", "PARCHMENT"]:
		for t in (PAL.RAMPS[rn] as Array):
			if PAL.key(c) == PAL.key(t):
				return true
	return false

func _outline_keys() -> Dictionary:
	var o := {}
	for rn in PAL.RAMPS:
		o[PAL.key((PAL.RAMPS[rn] as Array)[3])] = true
	# UI-материал: обводка INK (FLAT)
	o[PAL.key(PAL.FLATS["INK"])] = true
	return o

func _popdiff(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	var keys := a.duplicate()
	keys.merge(b, true)
	for k in keys:
		if a.has(k) != b.has(k):
			n += 1
	return n

## Визуальная различимость двух спрайтов: пиксели, где различается наличие ИЛИ
## цвет (силуэт+палитра вместе).
func _vdiff(ia: Image, ib: Image) -> int:
	var n := 0
	for y in range(0, 16):
		for x in range(0, 16):
			var pa: Color = ia.get_pixel(x, y)
			var pb: Color = ib.get_pixel(x, y)
			var sa := pa.a > 0.5
			var sb := pb.a > 0.5
			if sa != sb:
				n += 1
			elif sa and PAL.key(pa) != PAL.key(pb):
				n += 1
	return n

func _buf_mask(im: Image) -> Dictionary:
	var m := {}
	for y in range(0, 16):
		for x in range(0, 16):
			if im.get_pixel(x, y).a > 0.5:
				m[y * 16 + x] = true
	return m

func _buf_colors(im: Image) -> Dictionary:
	var c := {}
	for y in range(0, 16):
		for x in range(0, 16):
			var p := im.get_pixel(x, y)
			if p.a > 0.5:
				c[PAL.key(p)] = true
	return c

func _frac_legible(im: Image, bg: Color) -> float:
	var leg := 0
	var tot := 0
	for y in range(0, 16):
		for x in range(0, 16):
			var p := im.get_pixel(x, y)
			if p.a > 0.5:
				tot += 1
				if absf(_lum(p) - _lum(bg)) > 0.12:
					leg += 1
	return float(leg) / float(maxi(1, tot))

func _row_pixels(im: Image, y: int) -> Array:
	var r: Array = []
	for x in range(0, 16):
		if im.get_pixel(x, y).a > 0.5:
			r.append(x)
	return r

func _bottom_outline(im: Image, ol: Dictionary) -> bool:
	var row := -1
	for y in range(15, -1, -1):
		if not _row_pixels(im, y).is_empty():
			row = y
			break
	if row < 0:
		return false
	for x in _row_pixels(im, row):
		if not ol.has(PAL.key(im.get_pixel(x, row))):
			return false
	return true

func _min_pair_diff(names: Array) -> int:
	var mn := 99999
	for i in range(0, names.size()):
		for j in range(i + 1, names.size()):
			var d := _vdiff(_bufs[names[i]], _bufs[names[j]])
			if d < mn:
				mn = d
	return mn

func _check() -> int:
	var fails := 0
	var pk := _pal_keys()
	# 1) off-palette = 0 во всех боксах
	var off_total := 0
	for box in _boxes:
		var x0: int = box[0]
		var y0: int = box[1]
		for yy in range(0, int(box[3])):
			for xx in range(0, int(box[2])):
				var c := _img.get_pixel(x0 + xx, y0 + yy)
				if c.a > 0.5 and not pk.has(PAL.key(c)) and not _is_tech(c):
					off_total += 1
	print("OFF_TOTAL=%d" % off_total)
	if off_total > 0:
		fails += 1
	# 2) panel_frame контракт
	var px := _pf_pixels()
	var ok_bands := true
	for r in range(0, 4):
		var t0 := String(px[r * 32 + 12])
		var b0 := String(px[(31 - r) * 32 + 12])
		var l0 := String(px[8 * 32 + r])
		var r0 := String(px[8 * 32 + 31 - r])
		for i in range(4, 28):
			if String(px[r * 32 + i]) != t0 or String(px[(31 - r) * 32 + i]) != b0:
				ok_bands = false
			if String(px[i * 32 + r]) != l0 or String(px[i * 32 + 31 - r]) != r0:
				ok_bands = false
	var ok_center := true
	var c0 := String(px[16 * 32 + 16])
	for yy in range(4, 28):
		for xx in range(4, 28):
			if String(px[yy * 32 + xx]) != c0:
				ok_center = false
	print("PF_BANDS_CONST=%s PF_CENTER_SOLID=%s" % [ok_bands, ok_center])
	if not ok_bands or not ok_center:
		fails += 1
	var exp192 := _pf_nine(96, 64)
	var b192: Array = []
	for bx in _boxes:
		if String(bx[4]) == "pf192":
			b192 = bx
	if b192.size() == 0:
		fails += 1
	else:
		var ok4 := true
		for yy in range(0, 64):
			for xx in range(0, 96):
				var got := _img.get_pixel(int(b192[0]) + xx * 2, int(b192[1]) + yy * 2)
				if PAL.key(got) != PAL.key(exp192.get_pixel(xx, yy)):
					ok4 = false
		var src := _pf_pixels()
		var okc := true
		for yy in range(0, 4):
			for xx in range(0, 4):
				var gt := _img.get_pixel(int(b192[0]) + xx * 2, int(b192[1]) + yy * 2)
				if PAL.key(gt) != PAL.key(_spec_color(String(src[yy * 32 + xx]))):
					okc = false
				var gb := _img.get_pixel(int(b192[0]) + (95 - xx) * 2, int(b192[1]) + (63 - yy) * 2)
				if PAL.key(gb) != PAL.key(_spec_color(String(src[(31 - yy) * 32 + (31 - xx)]))):
					okc = false
		print("PF9_EQUIV=%s PF_CORNERS_1to1=%s" % [ok4, okc])
		if not ok4 or not okc:
			fails += 1
	# 3-6) метрики из буферов
	if not _metrics():
		fails += 1
	# 7) боксы не перекрываются (нет «дырявых» наложений на листе)
	var ov := 0
	for i in range(0, _boxes.size()):
		for j in range(i + 1, _boxes.size()):
			var a: Array = _boxes[i]
			var b: Array = _boxes[j]
			var ix := mini(int(a[0]) + int(a[2]), int(b[0]) + int(b[2])) - maxi(int(a[0]), int(b[0]))
			var iy := mini(int(a[1]) + int(a[3]), int(b[1]) + int(b[3])) - maxi(int(a[1]), int(b[1]))
			if ix > 0 and iy > 0:
				ov += 1
				print("OVERLAP %s x %s" % [a[4], b[4]])
	print("BOX_OVERLAPS=%d" % ov)
	if ov > 0:
		fails += 1
	return fails

func _metrics() -> bool:
	var ok := true
	var ol := _outline_keys()
	var synth_dark := PAL.c("CHAR", _D)
	var synth_light := PAL.c("PARCHMENT", _M)
	var curs: Array = []
	var prj: Array = []
	var alch: Array = []
	for i in range(0, 4):
		curs.append("cur%d" % i)
		prj.append("prj%d" % i)
	for i in range(0, 3):
		alch.append("alch%d" % i)
	var lists := [curs, prj, alch]
	var need := [24, 32, 24]
	var names := ["CURSORS", "PRJ", "ALCH"]
	for li in range(0, 3):
		var l: Array = lists[li]
		var mn := _min_pair_diff(l)
		print("POPCOUNT_MIN %s=%d (need>=%d, пар=%d)" % [names[li], mn, need[li],
			l.size() * (l.size() - 1) / 2])
		if mn < need[li]:
			ok = false
	for n in curs:
		var im: Image = _bufs[n]
		var fd := _frac_legible(im, synth_dark)
		var fl := _frac_legible(im, synth_light)
		var nc := _buf_colors(im).size()
		print("READ %s dark=%.2f light=%.2f colors=%d" % [n, fd, fl, nc])
		if fd < 0.12 or fl < 0.12 or nc < 3:
			ok = false
	var ok_bottom := true
	var all := curs + prj + ["key", "camp0", "camp1", "camp2", "camp3", "camp4"] + alch
	var bad := ""
	for n in all:
		if not _bottom_outline(_bufs[n], ol):
			bad += n + " "
			ok_bottom = false
	print("BOTTOM_ROW_OUTLINE=%s%s" % [ok_bottom, (" (" + bad + ")") if bad != "" else ""])
	if not ok_bottom:
		ok = false
	var d01 := _popdiff(_buf_mask(_bufs["camp0"]), _buf_mask(_bufs["camp1"]))
	var d12 := _popdiff(_buf_mask(_bufs["camp1"]), _buf_mask(_bufs["camp2"]))
	var d23 := _popdiff(_buf_mask(_bufs["camp2"]), _buf_mask(_bufs["camp3"]))
	var dfa := _popdiff(_buf_mask(_bufs["camp0"]), _buf_mask(_bufs["camp4"]))
	print("CAMPFIRE d01=%d d12=%d d23=%d fire_vs_ash=%d" % [d01, d12, d23, dfa])
	if d01 < 8 or d12 < 8 or d23 < 8 or dfa < 40:
		ok = false
	return ok

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	# режимы: (пусто | <outdir>) — вердикт-лист c28; --emit <dir> — 8 PNG в dir;
	# --inplace — ребейк ассетов на месте (c29)
	if args.size() > 0 and args[0] == "--inplace":
		var rci := _inplace_assets()
		quit(rci)
		return
	if args.size() > 1 and args[0] == "--emit":
		var rce := _emit_assets(args[1])
		quit(rce)
		return
	var out_dir := "res://.."
	if args.size() > 0:
		out_dir = args[0]
	var rc := _bake(out_dir)
	var fails := _check()
	if rc != 0:
		fails += 1
	if fails > 0:
		print("SELF-CHECK FAIL %d" % fails)
		quit(1)
		return
	print("SELF-CHECK PASS")
	quit(0)
