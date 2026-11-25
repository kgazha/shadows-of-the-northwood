extends SceneTree
## Инструмент вердикт-листа «Оружие v1» (волна «Мир v2: наполнение», t10, 25.11).
##
## ВЕРДИКТ ПОЛЬЗОВАТЕЛЯ 25.11: «магу посохи, а не мечи или лук; лучнику только
## луки; воину только мечи и щиты». Таксономия/гейт/предметы УЖЕ В КОДЕ
## (gear_data.gd CLASS_WEAPONS + слот shield) — код и гейт листа не ждали.
## ЛИСТ — на вердикт по СПРАЙТАМ МИРА: интеграция спрайтов только после «да»
## (закон ART). Иконки интерфейса — дословный двойник ui_icons.gd: лист рисует
## ИМИ ЖЕ (UiIcons.item_icon), поэтому равенство листа игре конструктивно.
##
## Секции:
##  A) RUNTIME ICONS — что игра рисует сегодня (zoom1 + zoom3, палитра, цены).
##  B) WORLD SPRITE PROPOSALS — два кандидата спрайта в мир на каждый предмет:
##     KORYAGA (полный цвет, кодо-арт) и SILHOUETTE (силуэт героя + световой
##     кант) — zoom3. НИ ОДИН НЕ В ИГРЕ до вердикта.
##  C) HERO PARITY — герой 16 px zoom1 (инвариант) рядом с кандидатами.
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_weapons_v1.gd -- <out.png>
## Выход 0 — самопроверки + STRICT-скан PASS (скан ДО сохранения: при провале
## файл не выкладывается), иначе 1.

const P := preload("res://scripts/pixel_palette.gd")
const UI := preload("res://scripts/ui_icons.gd")

## Порядок листа = порядок реестра ITEMS для новых позиций t10.
const NEW_IDS := ["staff_apprentice", "staff_oak", "staff_rune",
	"bow_hunter", "bow_heavy", "shield_iron", "shield_raven"]
const NAMES := {
	"staff_apprentice": "STAFF APPRENTICE - 60G - DMG +2 - MANA +5 - HERMIT",
	"staff_oak": "STAFF OAK - 150G - DMG +4 - MANA +10 - SMITH",
	"staff_rune": "STAFF RUNE - 300G - DMG +6 - MANA +15 - RARE - MERCHANT",
	"bow_hunter": "BOW HUNTER - 80G - DMG +2 - MERCHANT",
	"bow_heavy": "BOW HEAVY - 200G - DMG +4 - RARE - MERCHANT",
	"shield_iron": "SHIELD IRON - 70G - ARMOR +1 - SMITH",
	"shield_raven": "SHIELD RAVEN - 220G - ARMOR +2 - RARE - SMITH",
}

var _fails := 0
var _allowed := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var target := "res://tools_art/sheet_weapons_v1.png"
	if args.size() > 0:
		target = String(args[0])
	var idx: Dictionary = P.color_index()
	_allowed = idx.duplicate()
	for k in P.SHEET:
		_allowed[P.key(P.SHEET[k])] = ["SHEET", -1]
	# технические цвета слота ui_icons (фон-«дерево» и контур) — те же, что
	# допускал лист c24 (tech-фон предмета, не арт). КЛЮЧ — как его сохранит
	# RGBA8 (float->uint8 у ui.BG/ui.INK не совпадает с сырым to_argb32,
	# двойник _store_key из sheet_items.gd):
	_allowed[_store_key(UI.BG)] = ["TECH", -1]
	_allowed[_store_key(UI.INK)] = ["TECH", -1]
	var img_a: Image = _build_sheet()
	var img_b: Image = _build_sheet()
	var ba: PackedByteArray = img_a.save_png_to_buffer()
	var bb: PackedByteArray = img_b.save_png_to_buffer()
	var double_bake: bool = ba == bb
	print("[bake] double-bake byte-identical: %s" % ("PASS" if double_bake else "FAIL"))
	if not double_bake:
		_fails += 1
	var ok := _strict_scan(img_a)
	if ok:
		var dir := target.rfind("/")
		if dir > 0:
			var dp := target.substr(0, dir).replace("res://", ProjectSettings.globalize_path("res://") + "/")
			DirAccess.make_dir_recursive_absolute(dp)
		var err := img_a.save_png(target)
		print("[save] %s err=%d pre-save hash %s" % [target, err, _fnv32_hex(img_a)])
		if err != OK:
			_fails += 1
	if _fails > 0:
		print("SELF-CHECK: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("SELF-CHECK: PASS")
		quit(0)

## Ключ цвета ТАК, как его сохранит 8-битный RGBA8 Image (двойник
## _store_key из sheet_items.gd: float->uint8 округление в ui.BG/ui.INK
## не совпадает с сырым to_argb32).
func _store_key(c: Color) -> int:
	var im := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	im.set_pixel(0, 0, c)
	return im.get_pixel(0, 0).to_argb32()

# ============================================================ арт-двойники

## Иконка-изображение id — ровно то, что рисует игра (кэш UiIcons общий).
func _icon_img(id: String) -> Image:
	return UI.item_icon(id).get_image()

## Прозрачный «кандидат в мир» (KORYAGA): тот же рисовальщик, но БЕЗ tech-фона
## слота — только предмет.
func _bare_img(id: String) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	UI._cv = img
	UI._cv_ox = 0
	match id:
		"staff_apprentice": UI._ic_item_staff_apprentice()
		"staff_oak": UI._ic_item_staff_oak()
		"staff_rune": UI._ic_item_staff_rune()
		"bow_hunter": UI._ic_item_bow_hunter()
		"bow_heavy": UI._ic_item_bow_heavy()
		"shield_iron": UI._ic_item_shield_iron()
		"shield_raven": UI._ic_item_shield_raven()
	UI._cv = null
	UI._cv_ox = 0
	return img

## SILHOUETTE-кандидат: форма KORYAGA, залитая трупным CHAR DARK, световой
## кант 1 px там, где сверху или слева пустота (кант «открытой грани»).
func _sil_img(src: Image) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body: Color = P.RAMPS["CHAR"][P.T_DARK]
	var rim: Color = P.RAMPS["BONE"][P.T_LIGHT]
	for y in 16:
		for x in 16:
			if src.get_pixel(x, y).a < 0.5:
				continue
			var up_empty := y == 0 or src.get_pixel(x, y - 1).a < 0.5
			var left_empty := x == 0 or src.get_pixel(x - 1, y).a < 0.5
			img.set_pixel(x, y, rim if (up_empty or left_empty) else body)
	return img

## Проверка кандидата: непустой (>=12 пикселей), палитра чистая по цвету.
func _check_proposal(img: Image, nm: String) -> void:
	var n := 0
	var off := 0
	for y in 16:
		for x in 16:
			var col := img.get_pixel(x, y)
			if col.a < 0.5:
				continue
			n += 1
			if not _allowed.has(P.key(col)):
				off += 1
	var ok: bool = n >= 12 and off == 0
	print("[prop] %-24s px:%3d off:%d %s hash:%s" % [nm, n, off, "PASS" if ok else "FAIL", _fnv32_hex(img)])
	if not ok:
		_fails += 1

# ============================================================ проверки

func _strict_scan(img: Image) -> bool:
	var off := 0
	var mask := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a < 1.0:
				mask += 1
				continue
			if not _allowed.has(P.key(col)):
				off += 1
	var ok: bool = off == 0 and mask == 0
	print("[strict] sheet-wide %dx%d off=%d mask=%d %s" % [img.get_width(), img.get_height(), off, mask, "PASS" if ok else "FAIL"])
	if not ok:
		_fails += 1
	return ok

func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

# ============================================================ лист

func _build_sheet() -> Image:
	var W := 620
	var sheet := _im(W, 1000)
	sheet.fill(P.SHEET["BG"])
	var x0 := 10
	var y := 8
	_text(sheet, x0, y, "WEAPONS V1 - STAFF / BOW / SHIELD - CODE ART - VERDICT SHEET - T10 25.11", 2, P.SHEET["TEXT"])
	y += 16
	_text(sheet, x0, y, "CANON - WARRIOR SWORDS AND SHIELDS - ARCHER BOWS ONLY - MAGE STAVES ONLY", 1, P.SHEET["LINE"])
	y += 9
	_text(sheet, x0, y, "OFF-HAND BUY IS LEGAL - FUTURE CIRCLE GOODS - ONLY EQUIP IS GATED - LEGACY GATE STRIPS ON LOAD", 1, P.SHEET["LINE"])
	y += 12

	# --- секция A: рантайм-иконки (то, что игра рисует уже) ---
	_text(sheet, x0, y, "A - RUNTIME ICONS - DRAWN BY UIICONS ITSELF - EQUALS THE GAME BY CONSTRUCTION - ZOOM1 X3 THEN ZOOM3", 1, P.SHEET["TEXT"])
	y += 10
	for id in NEW_IDS:
		var ic := _icon_img(id)
		_check_icon(ic, id)
		var items: Array = [
			{"name": id.to_upper(), "img": ic},
			{"name": "", "img": ic},
			{"name": "", "img": ic},
			{"name": "ZOOM3", "img": ic},
		]
		# zoom1 x3 в ряд + zoom3, верхние края равны; строка 56 px
		var xx := x0
		for i in 3:
			_cell(sheet, xx, y, ic, 1)
			xx += 16 + 8
		_cell(sheet, xx, y, ic, 3)
		_text(sheet, xx + 56, y + 2, String(NAMES[id]), 1, P.SHEET["TEXT"])
		_text(sheet, xx + 56, y + 14, "ICON HASH - SEE PRINT LINES AND PINS", 1, P.SHEET["LINE"])
		y += 56

	# --- секция B: кандидаты спрайтов в мир (НЕ В ИГРЕ) ---
	_text(sheet, x0, y, "B - WORLD SPRITE CANDIDATES - NOT IN GAME - CAPTAIN VERDICT REQUIRED - LAW ART", 1, P.SHEET["TEXT"])
	y += 9
	_text(sheet, x0, y, "KORYAGA - FULL COLOR CODE ART - VS SILHOUETTE - HERO DARK BODY - BONE RIM ON OPEN TOP AND LEFT EDGE", 1, P.SHEET["LINE"])
	y += 11
	for id in NEW_IDS:
		var bare := _bare_img(id)
		var sil := _sil_img(bare)
		_check_proposal(bare, "KORYAGA " + id)
		_check_proposal(sil, "SILHOUETTE " + id)
		var xx := x0
		_cell(sheet, xx, y, bare, 3)
		_text(sheet, xx + 2, y + 50, "KORYAGA", 1, P.SHEET["LINE"])
		xx += 56
		_cell(sheet, xx, y, sil, 3)
		_text(sheet, xx + 2, y + 50, "SILHOUETTE", 1, P.SHEET["LINE"])
		xx += 64
		_text(sheet, xx, y + 8, id.to_upper(), 1, P.SHEET["TEXT"])
		_text(sheet, xx, y + 20, "VS - SAME FORM - DIFFERENT SOUL", 1, P.SHEET["LINE"])
		y += 62

	# --- секция C: герой 16 px zoom1 (инвариант) рядом с кандидатами ---
	_text(sheet, x0, y, "C - HERO PARITY - HERO 16PX ZOOM1 INVARIANT - CANDIDATES AT ITEM SCALE", 1, P.SHEET["TEXT"])
	y += 10
	var hero: Image = load("res://assets/class_warrior.png").get_image().get_region(Rect2i(0, 0, 16, 16))
	_cell(sheet, x0, y, hero, 1)
	var hx := x0 + 22
	for id in ["shield_iron", "shield_raven", "staff_apprentice", "bow_hunter"]:
		_cell(sheet, hx, y, _bare_img(id), 1)
		hx += 22
	_text(sheet, hx + 6, y + 4, "WARRIOR LOADOUT ITEMS AT 1PX - NO RESCALE - NO RASTER", 1, P.SHEET["LINE"])
	y += 26
	_text(sheet, x0, y, "FAMILIES - PIXELPALETTE ONLY - BARK IRON BRONZE CLOTH CRYSTAL CHAR BONE UI BLUE HUD GOLD - DELTA EMPTY", 1, P.SHEET["LINE"])
	return sheet

## Иконка: непустая и палитрно-чистая + пин-печать.
func _check_icon(ic: Image, id: String) -> void:
	var n := 0
	var off := 0
	for yy in 16:
		for xx in 16:
			var col := ic.get_pixel(xx, yy)
			if col.a < 0.5:
				continue
			n += 1
			if not _allowed.has(P.key(col)):
				off += 1
	var ok: bool = n >= 30 and off == 0
	print("[icon] %-24s px:%3d off:%d %s hash:%s" % [id, n, off, "PASS" if ok else "FAIL", _fnv32_hex(ic)])
	if not ok:
		_fails += 1

## Ячейка-панель с blit-масштабом.
func _cell(img: Image, x0: int, y0: int, art: Image, sc: int) -> void:
	var cw := art.get_width() * sc
	_rect(img, x0 - 1, y0 - 1, x0 + cw, y0 + cw, P.SHEET["LINE"])
	_blit(img, art, x0, y0, sc)

# ============================================================ примитивы (эталон sheet_env_v1)

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

func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for yy in range(y0, y1 + 1):
		for xx in range(x0, x1 + 1):
			_px(img, xx, yy, col)

func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

func _blit(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	for yy in src.get_height():
		for xx in src.get_width():
			var col := src.get_pixel(xx, yy)
			if col.a < 0.5:
				continue
			for dy in sc:
				for dx in sc:
					_px(dst, x0 + xx * sc + dx, y0 + yy * sc + dy, col)
