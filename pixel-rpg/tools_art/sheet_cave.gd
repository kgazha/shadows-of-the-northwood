extends SceneTree
## Инструмент рисовки листа-вердикта «Пещера v1» (волна c1; c3 — интеграция).
## Рисует кодом пиксель-спрайты пещеры в каноне «единый hand-made пиксель» и
## собирает sheet: ряды 4x для разглядывания + ряды 1x (нативный игровой размер
## при зуме 1, hero H=16), линейка H, силуэт-бокс героя 16×16, легенда рамп.
##
## Рисовка вынесена в res://tools_art/cave_paint.gd (статический генератор —
## его же побайново ребейкают QA-стенды). Раскладка проп-атласа — единственный
## источник истины CaveArt.REGIONS (scripts/cave_art.gd): кадры пропов педаются
## с alpha-trim до видимого силуэта (аудит c2, F2: пустых полей в кадре нет,
## нога/аутлайн на нижней границе).
##
## Догфуд канона (шаблон — sheet_village.gd, t53/t54):
##  - единственный источник цвета — PixelPalette; САМОПРОВЕРКА чистоты палитры;
##    палитра НЕ расширялась: CAVE_ROCK/CRYSTAL/MOSS_GLOW/CAVE_WATER уже в
##    PixelPalette (t53), дельта CAVE_* = пусто;
##  - прогон canon_pass() для всех спрайтов-силуэтов (алтарь/сундук/сталактиты/
##    сталагмиты/кострище): OUTLINE по нижним открытым граням, LIGHT-подсветка
##    СЗ, нижний ряд — только OUTLINE (правило стопы/низа как якорь y-sort);
##  - тайлы (пол/стена) — ПОВЕРХНОСТИ: канон силуэта к ним не применяется, но
##    проверяются непрозрачность, чистота палитры и БЕСШОВНОСТЬ (пин-метрика
##    шва: mean|delta| пары «правый край↔левый» против соседних колонок;
##    период текстуры ровно 16 px => шов статистически неотличим от поля);
##  - никаких чистых #000/#FFF, никаких вне-палитрных цветов (FIRE_HOT —
##    единственная «горячая» точка, только у огня).
##
## Байт-воспроизводимость: никакого randi — только детерминированный хэш-шум
## с фиксированным сидом SEED; итоговый CONTENT-HASH (FNV-1a 32) печатается
## для каждого элемента и листа: повторный запуск обязан дать те же хэши.
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_cave.gd -- <out.png>
##   — режим sheet: лист-вердикт «Пещера v1» (+ рядом <out>_2x.png — nearest ×2
##     для читаемости; 1x-ряды листа = нативный экран игры при зуме 1).
##   Godot ... -- bake <out_dir>
##   — режим bake: пещерные атласы игры (cave_floor_v1.png 64×16,
##     cave_wall_v1.png 80×16, cave_props_v1.png 128×64 + regions-манифест).
## Выход 0 — все самопроверки PASS, иначе 1.

const P := preload("res://scripts/pixel_palette.gd")
const CP := preload("res://tools_art/cave_paint.gd")
const CA := preload("res://scripts/cave_art.gd")

const H_HERO := 16        # мир. px, канон t51 (SCALE_CANON.md)
const SEAM_RATIO_MAX := 2.2  # порог пин-метрики шва (шов/поле)

var _fails := 0
var _idx := {}  # argb32 -> [ramp, tone]

# ----------------------------------------------------------------------------- helpers
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_idx = P.color_index()
	var mode := "sheet"
	var target := "res://tools_art/sheet_cave.png"
	if args.size() > 0:
		if String(args[0]) in ["sheet", "bake"]:
			mode = String(args[0])
			if args.size() > 1:
				target = String(args[1])
		else:
			target = String(args[0])
	if mode == "bake":
		_bake(target)
	else:
		_sheet(target)
	if _fails > 0:
		print("SELF-CHECK: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("SELF-CHECK: PASS")
		quit(0)


func _sheet(out_path: String) -> void:
	var tiles: Array = _build_tiles_all()
	var props: Array = _build_props_all()
	for s in props:
		_check_sprite(s)
	for t in tiles:
		_check_tile(t)
		_check_seam(t)
	var sheet := _compose(tiles, props)
	var err := sheet.save_png(out_path)
	print("sheet saved: %s (%dx%d) err=%d" % [out_path, sheet.get_width(), sheet.get_height(), err])
	var up := _upscale2(sheet)
	var p2 := out_path.replace(".png", "_2x.png")
	var err2 := up.save_png(p2)
	print("sheet saved: %s (%dx%d) err=%d" % [p2, up.get_width(), up.get_height(), err2])


## Игровые атласы (вердикт «1 внедряем»): пол/стены — прямая раскладка,
## пропы — alpha-trim кадры точно по регионам CaveArt.REGIONS.
func _bake(out_dir: String) -> void:
	var tiles: Array = _build_tiles_all()
	for t in tiles:
		_check_tile(t)
		_check_seam(t)
	var props: Array = _build_props_all()
	for s in props:
		_check_sprite(s)
	var fatlas: Image = CP.bake_floor_atlas()
	var watlas: Image = CP.bake_wall_atlas()
	var pres: Dictionary = CP.bake_props_atlas(CA.REGIONS, CA.ATLAS_SIZE)
	for f in pres["fails"]:
		_fails += 1
		print("[FAIL] bake: %s" % String(f))
	var patlas: Image = pres["img"]
	for k in CA.REGIONS:
		var reg: Rect2 = CA.REGIONS[k]
		print("[region] %-8s x=%d y=%d w=%d h=%d" % [String(k), int(reg.position.x),
				int(reg.position.y), int(reg.size.x), int(reg.size.y)])
	var e1 := fatlas.save_png(out_dir + "/cave_floor_v1.png")
	var e2 := watlas.save_png(out_dir + "/cave_wall_v1.png")
	var e3 := patlas.save_png(out_dir + "/cave_props_v1.png")
	print("bake saved: cave_floor_v1.png (%dx%d) err=%d; cave_wall_v1.png (%dx%d) err=%d; cave_props_v1.png (%dx%d) err=%d" % [
		fatlas.get_width(), fatlas.get_height(), e1,
		watlas.get_width(), watlas.get_height(), e2,
		patlas.get_width(), patlas.get_height(), e3])


# ----------------------------------------------------------------------------- наборы
func _build_tiles_all() -> Array:
	var floors := CP.floor_tile_set()
	var walls := CP.wall_tile_set()
	var meta := [
		["FLOOR", "FLR"], ["FLOOR_CRACK", "FLRK"], ["FLOOR_ALTAR", "FLAL"],
		["FLOOR_MOSS", "FLMS"],
		["WALL", "WAL"], ["WALL_TOP", "WTOP"], ["WALL_BOT", "WBOT"],
		["WALL_CORNER_L", "WCL"], ["WALL_CORNER_R", "WCR"],
	]
	var seamv := [true, true, true, true, true, false, false, false, false]
	var src: Array = floors + walls
	var out: Array = []
	for i in src.size():
		out.append({"name": meta[i][0], "short": meta[i][1], "canon": "16X16 TILE",
				"img": src[i]["img"], "tile": true, "seam_v": seamv[i]})
	return out


## Порядок ряда пропов в листе — как в утверждённом c1-листе + новая пара
## кадров факела c5 («факелы лучше»); канон уже прогнан генератором (тот же
## пиксель, что в атласе).
func _build_props_all() -> Array:
	var by := {}
	for s in CP.prop_set_canon():
		by[String(s["name"])] = s["img"]
	var meta := [
		["ALTAR", "ALT", "1.6H"], ["CHEST", "CST", "~1.2H"],
		["BRAZIER", "BRZ", "~1.2H"],
		["STALC1", "C1", "0.5H"], ["STALC2", "C2", "0.75H"], ["STALC3", "C3", "1.2H"],
		["STALAG1", "G1", "0.5H"], ["STALAG2", "G2", "0.75H"], ["STALAG3", "G3", "1.2H"],
		["TORCH1", "TRH1", "~0.6H"], ["TORCH2", "TRH2", "~0.6H"],
	]
	var out: Array = []
	for m in meta:
		out.append({"name": m[0], "short": m[1], "canon": m[2], "img": by[m[0]]})
	return out


# ----------------------------------------------------------------------------- self-check
## Силуэт: (1) чистота палитры, (2) нижний ряд только OUTLINE (стопа/якорь),
## (3) подсветка СЗ (LIGHT в верхней половине) — копия эталона sheet_village.
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
		print("[FAIL] %s: %d пикселей вне палитры" % [nm, foreign])
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
		print("[FAIL] %s: нижний ряд не из OUTLINE-тонов: %d px" % [nm, bad_foot])
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
	print("[spr] %-10s %2dx%-2d  %6s  colors:%d  light t/b: %d/%d  hash:%s" % [nm, w, h, String(s["canon"]), uniq.size(), lt_top, lt_bot, CP.img_hash(img)])


## Тайл-поверхность: 16×16, полностью непрозрачен, чистая палитра.
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
		print("[tile] %-14s 16x16 ok  hash:%s" % [nm, CP.img_hash(img)])


## Пин-метрика шва: mean|Δ| (RGB, 0..255) на стыке «правый край↔левый» (гориз.)
## и «низ↔верх» (верт.) против средней mean|Δ| соседних колонок/строк внутри
## тайла. Шов «зажат» (пин), если ratio выше порога: тайлы-поверхности обязаны
## быть статистически непрерывны (ratio ≤ SEAM_RATIO_MAX).
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
	print("[seam] %-14s horiz mean|d| seam=%.1f field=%.1f ratio=%.2f%s" % [String(t["name"]), seam_x, field_x, ratio_x, verdict])
	if bool(t.get("seam_v", false)):
		var v := ""
		if ratio_y > SEAM_RATIO_MAX:
			v = "  [FAIL PIN]"
		print("[seam] %-14s vertil mean|d| seam=%.1f ratio=%.2f%s" % [String(t["name"]), seam_y, ratio_y, v])


func _db(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var a := img.get_pixel(x0, y0)
	var b := img.get_pixel(x1, y1)
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0


# ----------------------------------------------------------------------------- sheet
## 3×5 шрифт — рукописная копия эталона sheet_village.gd + '.' и '~' для
## подписей долей H («1.6H», «~1.2H»). Только ASCII.
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
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, col)


## Ряд элементов: панель+рисунок+двухстрочная подпись; ноги — на одну линию.
func _draw_row(sheet: Image, items: Array, sc: int, x0: int, y0: int, maxh: int, pad: int, gap: int, full_names: bool) -> void:
	var x := x0
	for s in items:
		var img: Image = s["img"]
		var nm := String(s["name"]) if full_names else String(s["short"])
		var cw: int = img.get_width() * sc
		var ch: int = img.get_height() * sc
		var cell_w := cw + pad * 2
		var cell_h := maxh * sc + pad * 2
		var cy := y0 + (maxh - img.get_height()) * sc  # ноги на одну линию
		_rect(sheet, x, y0, x + cell_w - 1, y0 + cell_h - 1, P.SHEET["PANEL"])
		_rect(sheet, x, y0, x + cell_w - 1, y0, P.SHEET["LINE"])
		_rect(sheet, x, y0 + cell_h - 1, x + cell_w - 1, y0 + cell_h - 1, P.SHEET["LINE"])
		for yy in ch:
			for xx in cw:
				var col := img.get_pixel(int(xx / sc), int(yy / sc))
				if col.a > 0.5:
					var sx := x + pad + int(xx / sc) * sc
					var sy := cy + pad + int(yy / sc) * sc
					for dy in sc:
						for dx in sc:
							sheet.set_pixel(sx + dx, sy + dy, col)
		var l1 := nm
		var l2 := "%dX%d %s" % [img.get_width(), img.get_height(), String(s["canon"])]
		var lsc: int = 1
		_text(sheet, x + 2, y0 + cell_h + 3, l1, lsc, P.SHEET["TEXT"])
		_text(sheet, x + 2, y0 + cell_h + 10, l2, lsc, P.SHEET["LINE"])
		x += cell_w + gap


func _hero_box(sheet: Image, x: int, y: int, sc: int) -> void:
	# референс: герой 16 px (SCALE_CANON t51) — пунктирный бокс
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


func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


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
	var W := maxi(W0, W1) + 20
	var H := title + (tile_h4 + lbl) + (tile_h1 + lbl) + (prop_h4 + lbl) + (prop_h1 + lbl) + 44
	var sheet := _im(W, H)
	sheet.fill(P.SHEET["BG"])
	_text(sheet, 10, 8, "CAVE V1 - PIXEL CANON SHEET (CODEGEN, HEAD B524C31)", 2, P.SHEET["TEXT"])
	_text(sheet, 10, 22, "NW LIGHT / OUTLINE FOOT / TILE16 H16 / PAL=PIXELPALETTE 0 NEW", 1, P.SHEET["LINE"])
	# ряды
	var y := title
	_text(sheet, 10, y + 2, "TILES 4X", 1, P.SHEET["LINE"])
	_draw_row(sheet, tiles, 4, ruler, y, 16, pad, gap, true)
	y += tile_h4 + lbl
	_text(sheet, 10, y + 2, "TILES 1X = SCREEN", 1, P.SHEET["LINE"])
	_draw_row(sheet, tiles, 1, ruler, y, 16, pad, gap, true)
	y += tile_h1 + lbl
	_text(sheet, 10, y + 2, "PROPS 4X", 1, P.SHEET["LINE"])
	_draw_row(sheet, props, 4, ruler, y, _row_h(props), pad, gap, true)
	y += prop_h4 + lbl
	_text(sheet, 10, y + 2, "PROPS 1X = SCREEN", 1, P.SHEET["LINE"])
	_hero_box(sheet, ruler, y + pad + (_row_h(props) - 16), 1)
	_draw_row(sheet, props, 1, ruler + 46, y, _row_h(props), pad, gap, false)
	# линейка H=16 (на prop-рядах)
	for sc in [4, 1]:
		var ry: int = y - (prop_h4 + lbl if sc == 4 else 0) + pad + (_row_h(props) - 16) * sc
		for yy in 16 * sc:
			_px(sheet, 20, ry + yy, P.SHEET["LINE"])
		for xx in 5:
			_px(sheet, 20 + xx, ry, P.SHEET["LINE"])
			_px(sheet, 20 + xx, ry + 16 * sc - 1, P.SHEET["LINE"])
		_text(sheet, 27, ry + maxi(0, (16 * sc - 5) / 2), "H", 1, P.SHEET["LINE"])
	# легенда рамп (только использованные материалы волны)
	var used := ["CAVE_ROCK", "CRYSTAL", "MOSS_GLOW", "CAVE_WATER", "WOOD", "IRON", "FIRE"]
	var ny := H - 26
	_text(sheet, 10, ny - 9, "RAMPS USED (PIXELPALETTE, CAVE DELTA = EMPTY)", 1, P.SHEET["LINE"])
	var nx0 := 10
	for rn in used:
		var ramp: Array = P.RAMPS[rn]
		for t in 4:
			_rect(sheet, nx0 + t * 7, ny, nx0 + t * 7 + 5, ny + 7, ramp[t])
		_text(sheet, nx0, ny + 9, rn.left(7), 1, P.SHEET["LINE"])
		nx0 += 4 * 7 + 9
	_rect(sheet, nx0, ny, nx0 + 5, ny + 7, P.FLATS["FIRE_HOT"])
	_text(sheet, nx0, ny + 9, "FIREHOT", 1, P.SHEET["LINE"])
	print("[hash] sheet pre-save  %s" % CP.img_hash(sheet))
	return sheet


func _upscale2(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := _im(w * 2, h * 2)
	for y in h:
		for x in w:
			var col := img.get_pixel(x, y)
			out.set_pixel(x * 2, y * 2, col)
			out.set_pixel(x * 2 + 1, y * 2, col)
			out.set_pixel(x * 2, y * 2 + 1, col)
			out.set_pixel(x * 2 + 1, y * 2 + 1, col)
	return out
