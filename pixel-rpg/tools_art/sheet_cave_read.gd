extends SceneTree
## w5 (запрос пользователя 16.11 «стены и пол одного цвета»): вердикт-лист
## читаемости пещеры — РАЗДЕЛЕНИЕ светлот пола и лица стены в 4 тонах VIOLET.
##
## Игра НЕ тронута: инструмент только рисует лист и кандидат-атласы
## (прецедент волн листа c1/c10/c33). Кандидаты — детерминированный тональный
## ребейк существующих генераторов cave_paint (никаких новых пикселей-форм:
## геометрия/шумы/трещины бит-в-бит, меняется только тональная карта):
##   A = лицо стены ТЕМНЕЕ пола: стена --1 ступень (MID->DARK, DARK->OUTLINE,
##       LIGHT->MID), пол без изменений;
##   B = лицо стены СВЕТЛЕЕ пола: пол --1 ступень, стена без изменений;
##   AO-полоса подошвы (WALL_BOT, ряд 14) усилена на 1 тон в обоих
##   кандидатах (ряд 15 — уже OUTLINE-зубцы, остаётся; направленная кромка,
##   вертикаль не стекуется — пин F4, швам не угрожает).
## Самопроверки: базовый тон лица != базовый тон пола (>=1 ступень), off=0,
## новых цветов 0 (кандидат-цвета ⊆ цвета текущих атласов), вертикальный wrap
## c14 < 2.0 и горизонтальный <= 2.2 на стекуемых тайлах, «нитевые»
## сильно-контрастные ряды стека не больше прежнего +2, AO-ряд жив и усилен.

const P := preload("res://scripts/pixel_palette.gd")
const CP := preload("res://tools_art/cave_paint.gd")
const SEAM_V_MAX := 2.0   # формальный порог вертикального wrap (acceptance)
const SEAM_H_MAX := 2.2   # формальный SEAM_RATIO_MAX (как sheet_cave)
const STACK := 7          # высота стека для нитевой метрики (как c14)
const THREAD_K := 2.2     # ряд «сильноконтрастный», если rowdiff > K*field

var _fails := 0
var _out_dir := ""

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and String(args[0]) == "bake":
		_bake(String(args[1]))
		print("SELF-CHECK: ", "PASS" if _fails == 0 else "FAIL(%d)" % _fails)
		quit(0 if _fails == 0 else 1)
		return
	if args.size() >= 1:
		_sheet(String(args[0]))
		print("SELF-CHECK: ", "PASS" if _fails == 0 else "FAIL(%d)" % _fails)
		quit(0 if _fails == 0 else 1)
		return
	push_error("usage: -s res://tools_art/sheet_cave_read.gd -- sheet <out.png> | bake <out_dir>")
	quit(2)

# ------------------------------------------------------------------ тон-карты

static func C(tone: int) -> Color:
	return P.RAMPS["VIOLET"][tone]

## --1 ступень со сворачиванием дна (OUTLINE->OUTLINE): единственный вид
## тонального сдвига кандидата. Ключи — точные цвета VIOLET; акцентные рампы
## (CRYSTAL/CAVE_WATER/MOSS_GLOW/FIRE/BONE…) в карту не входят — проходят насквозь.
static func darken_map() -> Dictionary:
	return {C(P.T_LIGHT): C(P.T_MID), C(P.T_MID): C(P.T_DARK),
			C(P.T_DARK): C(P.T_OUTLINE), C(P.T_OUTLINE): C(P.T_OUTLINE)}

## Отмягчение вертикального шва стекуемых тайлов (тоналность, геометрия цела):
## в колонках, где стык row15<->row0 > 3x среднего дельта поля, ряд 15
## поднимается на пол-ступени (OUTLINE->DARK, DARK->MID). Так CORNER_R держал
## 2.04 ЕЩЕ на HEAD (незапинено); кандидаты обязаны быть <2.0 и не хуже before.
static func lighten_map() -> Dictionary:
	return {C(P.T_OUTLINE): C(P.T_DARK), C(P.T_DARK): C(P.T_MID)}

static func soften_seam(img: Image, field: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for x in w:
		var d := _db_c(img, x, h - 1, x, 0)
		if d > 3.0 * field:
			var col := img.get_pixel(x, h - 1)
			if lighten_map().has(col):
				img.set_pixel(x, h - 1, lighten_map()[col])

static func _db_c(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var a := img.get_pixel(x0, y0)
	var b := img.get_pixel(x1, y1)
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0

static func field_y(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var f := 0.0
	for y in range(h - 1):
		for x in w:
			f += _db_c(img, x, y, x, y + 1)
	return f / float((h - 1) * w)

static func _wv(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var seam := 0.0
	for x in w:
		seam += _db_c(img, x, h - 1, x, 0)
	seam /= float(w)
	return seam / maxf(field_y(img), 0.001)

## Тонкое место стекуемого набора: все стекуемые тайлы (пол x4, тело, углы)
## с wrap_v >= 1.9 получают однопроходное отмягчение шва (только ряд 15,
## только колонки-выбросы; направленная подошва/свод не трогается).
static func soften_set(tiles: Array, idxs: Array) -> void:
	for i in idxs:
		var img: Image = tiles[i]
		if _wv(img) >= 1.9:
			soften_seam(img, field_y(img))

static func retone(img: Image, map: Dictionary) -> Image:
	var out: Image = img.duplicate()
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if map.has(col):
				out.set_pixel(x, y, map[col])
	return out

static func retone_row(img: Image, y: int, map: Dictionary) -> void:
	for x in img.get_width():
		var col := img.get_pixel(x, y)
		if map.has(col):
			img.set_pixel(x, y, map[col])

# --------------------------------------------------------------- наборы тайлов

## [floor[4], wall[5]] конкретного кандидата: "before"|"A"|"B".
static func sets(which: String) -> Array:
	var floors: Array = []
	var walls: Array = []
	for t in CP.floor_tile_set():
		floors.append(t["img"])
	# Пред-ретюн-база: с w5int wall_tile_set() содержит канон «Вариант А»,
	# исторические кандидаты листа считаются от raw-билдеров (бит-в-бит t45).
	for t in CP.wall_tile_set_raw():
		walls.append(t["img"])
	if which == "before":
		return [floors, walls]
	var dm := darken_map()
	if which == "A":
		var wa: Array = []
		for wimg in walls:
			wa.append(retone(wimg, dm))
		soften_set(floors, [0, 1, 2, 3])
		soften_set(wa, [0, 3, 4])
		return [floors, wa]
	# B: пол темнее; стена как есть, кроме WALL_BOT (индекс 2) — AO-ряд 14 +1 тон
	var fb: Array = []
	for fimg in floors:
		fb.append(retone(fimg, dm))
	var wb: Array = walls.duplicate()
	var bot: Image = wb[2].duplicate()
	retone_row(bot, 14, dm)
	wb[2] = bot
	soften_set(fb, [0, 1, 2, 3])
	soften_set(wb, [0, 3, 4])
	return [fb, wb]

static func remap_row_unused() -> void:
	pass

## Модальный тон VIOLET тайла (-1 если нет).
static func base_tone(img: Image) -> int:
	var cnt := [0, 0, 0, 0]
	for y in img.get_height():
		for x in img.get_width():
			var i := violet_tone(img.get_pixel(x, y))
			if i >= 0:
				cnt[i] += 1
	var best := -1
	var bn := 0
	for i in 4:
		if cnt[i] > bn:
			bn = cnt[i]
			best = i
	return best

static func violet_tone(col: Color) -> int:
	for i in 4:
		if col == C(i):
			return i
	return -1

static func row_frac(img: Image, y: int, tone: int) -> float:
	var n := 0
	for x in img.get_width():
		if violet_tone(img.get_pixel(x, y)) == tone:
			n += 1
	return float(n) / float(img.get_width())

# --------------------------------------------------------------------- метрики

func _db(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var a := img.get_pixel(x0, y0)
	var b := img.get_pixel(x1, y1)
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0

## c14: вертикальный wrap (стык низ<->верх против поля).
func wrap_v(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var seam := 0.0
	for x in w:
		seam += _db(img, x, h - 1, x, 0)
	seam /= float(w)
	var field := 0.0
	for y in range(h - 1):
		for x in w:
			field += _db(img, x, y, x, y + 1)
	field /= float((h - 1) * w)
	return seam / maxf(field, 0.001)

## c14-парная: горизонтальный wrap.
func wrap_h(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var seam := 0.0
	for y in h:
		seam += _db(img, w - 1, y, 0, y)
	seam /= float(h)
	var field := 0.0
	for y in h:
		for x in range(w - 1):
			field += _db(img, x, y, x + 1, y)
	field /= float(h * (w - 1))
	return seam / maxf(field, 0.001)

## Нитевая метрика стека: число сильно-контрастных границных пар строк в
## вертикальном стеке STACK копий кадра (rowdiff > THREAD_K * среднее).
func thread_rows(img: Image) -> int:
	var w := img.get_width()
	var H := img.get_height() * STACK
	var diffs: Array = []
	var field := 0.0
	for y in range(H - 1):
		var d := 0.0
		for x in w:
			d += _absd(img, x, y % img.get_height(), x, (y + 1) % img.get_height())
		d /= float(w)
		diffs.append(d)
		field += d
	field /= float(H - 1)
	var n := 0
	for d in diffs:
		if float(d) > THREAD_K * field:
			n += 1
	return n

func _absd(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	return _db(img, x0, y0, x1, y1)

static func violet_only(img: Image) -> bool:
	for y in img.get_height():
		for x in img.get_width():
			if violet_tone(img.get_pixel(x, y)) < 0:
				return false
	return true

# -------------------------------------------------------------------- палитра

static func palette_ok() -> Dictionary:
	var allowed := {}
	for ramp in P.RAMPS.values():
		for c in ramp:
			allowed[c] = true
	for c in P.FLATS.values():
		allowed[c] = true
	allowed[P.FIRE_HOT] = true
	return allowed

static func color_set(imgs: Array) -> Dictionary:
	var set := {}
	for imgv in imgs:
		var img: Image = imgv
		for y in img.get_height():
			for x in img.get_width():
				var col := img.get_pixel(x, y)
				if col.a > 0.0:
					set[col] = true
	return set

# ----------------------------------------------------------------------- bake

func _bake(out_dir: String) -> void:
	var dirs := ["before", "A", "B"]
	var before_sets := sets("before")
	var cset_before := color_set(before_sets[0] + before_sets[1])
	var pal := palette_ok()
	for which in dirs:
		if which == "before":
			continue
		var s := sets(which)
		var fl: Array = s[0]
		var wl: Array = s[1]
		var fatlas := Image.create(fl.size() * 16, 16, false, Image.FORMAT_RGBA8)
		for i in fl.size():
			fatlas.blit_rect(fl[i], Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
		var watlas := Image.create(wl.size() * 16, 16, false, Image.FORMAT_RGBA8)
		for i in wl.size():
			watlas.blit_rect(wl[i], Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
		for pair: Array in [["cand%s_floor.png" % which, fatlas], ["cand%s_wall.png" % which, watlas]]:
			var path := out_dir + "/" + String(pair[0])
			var err := (pair[1] as Image).save_png(path)
			print("[bake] %s err=%d hash=%s" % [String(pair[0]), err, CP.img_hash(pair[1])])
		# кандидата: off=0 и новых цветов 0 (цвета ⊆ текущих атласов)
		for atl in [fatlas, watlas]:
			var set := color_set([atl])
			var off := 0
			var fresh := 0
			for col in set.keys():
				if not pal.has(col):
					off += 1
				if not cset_before.has(col):
					fresh += 1
			if off != 0 or fresh != 0:
				_fails += 1
			print("[cand %s] off=%d new_colors=%d" % [which, off, fresh])

# ----------------------------------------------------------------------- лист

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
	">": ["100", "010", "001", "000", "000"], "<": ["001", "010", "100", "000", "000"],
	"(": ["010", "100", "100", "100", "010"], ")": ["010", "001", "001", "001", "010"],
}

func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)

func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, col)

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

func _blit(img: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var col := src.get_pixel(x, y)
			if col.a > 0.5:
				for dy in sc:
					for dx in sc:
						_px(img, x0 + x * sc + dx, y0 + y * sc + dy, col)

func _tone_name(t: int) -> String:
	return ["LIGHT", "MID", "DARK", "OUTLINE"][t]

## Панель-коридор 8x7 клеток: свод/тело/подошва + пол; torch/dim по флагу.
func _panel(sheet: Image, x0: int, y0: int, s: Array, torch: bool, dim: bool) -> void:
	var floors: Array = s[0]
	var walls: Array = s[1]
	var hero: Image = load("res://assets/class_warrior.png").get_image().get_region(Rect2i(0, 0, 16, 16))
	var props: Array = CP.prop_set_canon()
	var torch1: Image = props[9]["img"]  # TORCH1 (9x10)
	var px_cell := 16
	for cy in 7:
		for cx in 8:
			var tile: Image
			if cy == 0:
				tile = walls[1]                      # WALL_TOP
			elif cy == 1 or cy == 2:
				tile = walls[0]
			elif cy == 3:
				tile = walls[2]                      # WALL_BOT (подошва к полу)
			elif cy == 4 and cx == 5:
				tile = floors[1]                     # FLOOR_CRACK
			elif cy == 6 and cx == 1:
				tile = floors[3]                     # FLOOR_MOSS
			else:
				tile = floors[0 if (cx + cy) % 3 != 2 else 1]
			_blit(sheet, tile, x0 + cx * px_cell * 2, y0 + cy * px_cell * 2, 2)
	# угол левый: колонка 0 строк 1..2 -> corner_l, чтобы угол был виден
	for cy in [1, 2]:
		_blit(sheet, walls[3], x0, y0 + cy * px_cell * 2, 2)
	# герой 16 px: стопа на нижнюю границу строки 5 (в коридоре у подошвы)
	_blit(sheet, hero, x0 + 3 * 32 + 8, y0 + 5 * 32 + 16, 2)
	if torch:
		_blit(sheet, torch1, x0 + 6 * 32 + 12, y0 + 3 * 32 + 12, 2)
	if dim:
		# тех-имитация света БЕЗ факела: x0.62 по всем пикселям панели (мок-приём,
		# атласы не трогает; атласные кандидаты проверяются чистыми выше)
		var w := 8 * 32
		var h := 7 * 32
		for yy in h:
			for xx in w:
				var col := sheet.get_pixel(x0 + xx, y0 + yy)
				if col.a > 0.5:
					sheet.set_pixel(x0 + xx, y0 + yy,
							Color(col.r * 0.62, col.g * 0.62, col.b * 0.62, 1.0))

func _chip(sheet: Image, x: int, y: int, tone: int, lab: String) -> void:
	_rect(sheet, x, y, x + 11, y + 11, C(tone))
	_rect(sheet, x, y, x + 11, y, P.SHEET["LINE"])
	_text(sheet, x + 14, y + 3, lab, 1, P.SHEET["TEXT"])

func _sheet(out_path: String) -> void:
	var W := 1740
	var H := 1200
	var sheet := Image.create(W, H, false, Image.FORMAT_RGBA8)
	sheet.fill(P.SHEET["BG"])
	var y := 8
	_text(sheet, 10, y, "CAVE READABILITY - FLOOR VS WALL - VERDICT SHEET (CODEGEN)", 2, P.SHEET["TEXT"])
	y += 16
	_text(sheet, 10, y, "USER 16.11: FLOOR AND WALL ARE SAME COLOR - HARD TO ORIENT. FIX: SPLIT VALUE BANDS IN 4 VIOLET TONES,", 1, P.SHEET["LINE"])
	_text(sheet, 10, y + 8, "0 NEW COLORS. AO SKIRT +1 TONE. GEOMETRY/SEAMS BIT-EXACT (TONAL RETUNE OF APPROVED GENERATORS ONLY).", 1, P.SHEET["LINE"])
	y += 24

	var sb := sets("before")
	var sa := sets("A")
	var sbb := sets("B")
	var base := {
		"before": [base_tone(sb[0][0]), base_tone(sb[1][0])],
		"A": [base_tone(sa[0][0]), base_tone(sa[1][0])],
		"B": [base_tone(sbb[0][0]), base_tone(sbb[1][0])],
	}
	_text(sheet, 10, y, "TILES 4X - FLOOR X4 THEN WALL X5 (BODY/TOP/BOT/CORNER-L/CORNER-R)", 1, P.SHEET["LINE"])
	y += 10
	var names := ["FFLR", "FFCR", "FFAL", "FFMS", "WALL", "WTOP", "WBOT", "CORL", "CORR"]
	for group: Array in [["BEFORE (NOW: SAME MID BOTH)", sb], ["CAND A: WALL DARKER", sa], ["CAND B: FLOOR DARKER", sbb]]:
		var label := String(group[0])
		var s: Array = group[1]
		_text(sheet, 14, y + 6, label, 1, P.SHEET["TEXT"])
		var x := 200
		var tiles: Array = s[0] + s[1]
		for i in tiles.size():
			_rect(sheet, x - 2, y - 2, x + 67, y + 66, P.SHEET["PANEL"])
			_blit(sheet, tiles[i], x, y, 4)
			_text(sheet, x, y + 68, names[i], 1, P.SHEET["LINE"])
			x += 78
		y += 82
	y += 4

	# AO-ряд увеличением x8: WALL_BOT строки 12..15
	_text(sheet, 10, y, "WALL BOT SKIRT 8X (ROWS 12-15): BEFORE / A / B - AO +1 TONE AT ROW 14, OUTLINE TEETH AT 15 KEPT", 1, P.SHEET["LINE"])
	y += 10
	for i in 3:
		var s: Array = [sb, sa, sbb][i]
		var strip := Image.create(16, 4, false, Image.FORMAT_RGBA8)
		for yy in 4:
			for xx in 16:
				strip.set_pixel(xx, yy, (s[1][2] as Image).get_pixel(xx, 12 + yy))
		_rect(sheet, 12 + i * 160, y - 2, 12 + i * 160 + 130, y + 34, P.SHEET["PANEL"])
		_blit(sheet, strip, 14 + i * 160, y, 8)
		y += 36
	_text(sheet, 12, y, "", 1, P.SHEET["LINE"])
	y += 4

	# коллажи: BEFORE / A / B, каждый с факелом и без (тех-имитация x0.62)
	_text(sheet, 10, y, "CORRIDOR MOCK 2X - WITH TORCH / NO TORCH (TECH DIM x0.62, ATLAS NOT TOUCHED) - HERO 16PX", 1, P.SHEET["LINE"])
	y += 8
	var px0 := 12
	for group: Array in [["BEFORE", sb], ["A", sa], ["B", sbb]]:
		var label := String(group[0])
		var s: Array = group[1]
		_text(sheet, px0 + 2, y, label + " - TORCH", 1, P.SHEET["TEXT"])
		_text(sheet, px0 + 270, y, label + " - NO TORCH", 1, P.SHEET["TEXT"])
		_rect(sheet, px0 - 2, y + 8, px0 + 258, y + 8 + 226, P.SHEET["PANEL"])
		_rect(sheet, px0 + 266, y + 8, px0 + 526, y + 8 + 226, P.SHEET["PANEL"])
		_panel(sheet, px0, y + 10, s, true, false)
		_panel(sheet, px0 + 268, y + 10, s, false, true)
		px0 += 556
	y += 258

	# метрики текстом
	_text(sheet, 10, y, "METRICS (FORMULAS OF QA LP T14 / SHEET CAVE SEAM PIN)", 1, P.SHEET["LINE"])
	y += 10
	var lines: Array = []
	for which: String in ["before", "A", "B"]:
		var s: Array = {"before": sb, "A": sa, "B": sbb}[which]
		var fl: Array = s[0]
		var wl: Array = s[1]
		lines.append("%s: FLOOR BASE=%s WALL BASE=%s STEP-DIFF=%d" % [
			which.to_upper(), _tone_name(base[which][0]), _tone_name(base[which][1]),
			absi(base[which][0] - base[which][1])])
		var m := ""
		for pair: Array in [["F", fl[0]], ["F", fl[1]], ["F", fl[2]], ["F", fl[3]],
				["W", wl[0]], ["CL", wl[3]], ["CR", wl[4]]]:
			m += "%s v=%.2f h=%.2f  " % [String(pair[0]), wrap_v(pair[1]), wrap_h(pair[1])]
		lines.append("  wrap: " + m)
		lines.append("  thread rows (stack7): WALL=%d CORL=%d CORR=%d ; BOT row14 OUT=%.2f row15 OUT=%.2f" % [
			thread_rows(wl[0]), thread_rows(wl[3]), thread_rows(wl[4]),
			row_frac(wl[2], 14, P.T_OUTLINE), row_frac(wl[2], 15, P.T_OUTLINE)])
	for ln in lines:
		_text(sheet, 10, y, String(ln), 1, P.SHEET["TEXT"])
		y += 8
	y += 4

	# чипы + вердикт-подсказка
	_text(sheet, 10, y, "VIOLET RAMP (4 TONES, NO DELTA):", 1, P.SHEET["LINE"])
	_chip(sheet, 200, y - 4, P.T_LIGHT, "LIGHT")
	_chip(sheet, 290, y - 4, P.T_MID, "MID")
	_chip(sheet, 370, y - 4, P.T_DARK, "DARK")
	_chip(sheet, 450, y - 4, P.T_OUTLINE, "OUTLINE")
	_text(sheet, 620, y - 1, "PROPS ATLAS UNTOUCHED / TILE 16X16 SAME / INTEGRATION AFTER VERDICT", 1, P.SHEET["LINE"])
	y += 16

	# ---------------------------------------------- самопроверки
	var pal := palette_ok()
	var cset_before := color_set(sb[0] + sb[1])
	for which: String in ["A", "B"]:
		var s: Array = {"A": sa, "B": sbb}[which]
		if base[which][0] == base[which][1] or absi(base[which][0] - base[which][1]) < 1:
			_fails += 1
			print("[FAIL] %s: базовые тон пола/лица не разделены (%d/%d)" % [which, base[which][0], base[which][1]])
		var setc := color_set(s[0] + s[1])
		var off := 0
		var fresh := 0
		for col in setc.keys():
			if not pal.has(col):
				off += 1
			if not cset_before.has(col):
				fresh += 1
		if off != 0 or fresh != 0:
			_fails += 1
		print("[cand %s] base floor=%s wall=%s off=%d new=%d" % [which, _tone_name(base[which][0]), _tone_name(base[which][1]), off, fresh])
		var sbase: Array = {"A": sb, "B": sb}[which]
		for pair: Array in [[0, s[0][0]], [1, s[0][1]], [2, s[0][2]], [3, s[0][3]],
				[4, s[1][0]], [5, s[1][3]], [6, s[1][4]]]:
			var wv := wrap_v(pair[1])
			var wh := wrap_h(pair[1])
			var ok := wv < SEAM_V_MAX and wh <= SEAM_H_MAX
			if not ok:
				_fails += 1
			print("[wrap %s t%d] v=%.2f h=%.2f %s" % [which, int(pair[0]), wv, wh, "" if ok else "[FAIL]"])
		var tb := thread_rows((sbase as Array)[1][0])
		for ti in [0, 3, 4]:
			var tc := thread_rows(s[1][ti])
			if tc > tb + 2:
				_fails += 1
				print("[FAIL thread %s w%d] %d > before %d + 2" % [which, ti, tc, tb])
		var b14 := row_frac((sbase as Array)[1][2], 14, P.T_OUTLINE)
		var a14 := row_frac(s[1][2], 14, P.T_OUTLINE)
		var a15 := row_frac(s[1][2], 15, P.T_OUTLINE)
		if a15 <= 0.3 or a14 <= b14 + 0.2:
			_fails += 1
			print("[FAIL AO %s] row14 OUT %.2f -> %.2f, row15 %.2f" % [which, b14, a14, a15])
		else:
			print("[AO %s] row14 OUT %.2f->%.2f (+1 тон), row15 зубцы %.2f" % [which, b14, a14, a15])

	var err := sheet.save_png(out_path)
	print("sheet saved: ", out_path, " (", W, "x", H, ") err=", err)
	var up := _upscale2(sheet)
	var p2 := out_path.replace(".png", "_2x.png")
	print("sheet saved: ", p2, " err=", up.save_png(p2))

func _upscale2(img: Image) -> Image:
	var out := Image.create(img.get_width() * 2, img.get_height() * 2, false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			out.set_pixel(x * 2, y * 2, col)
			out.set_pixel(x * 2 + 1, y * 2, col)
			out.set_pixel(x * 2, y * 2 + 1, col)
			out.set_pixel(x * 2 + 1, y * 2 + 1, col)
	return out
