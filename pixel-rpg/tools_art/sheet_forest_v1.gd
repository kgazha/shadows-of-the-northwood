extends SceneTree
## Инструмент рисовки листа-вердикта «Лес v1» (w3 добивки стиля по аудиту c26).
## Рисует кодом пиксель-спрайты леса в каноне «единый hand-made пиксель» и
## собирает sheet: ряды 4x для разглядывания + 1x (нативный экран игры при
## зуме 1, герой H=16), ряд фаз свая (A покой / B −1px / C +1px), ряд честности
## («что уйдёт из tiles.png» рядом с «что не тронется — v4»), контекст-коллаж
## луг→кромка→лес с тропой v4 и героем 16 px, легенда рамп.
##
## Догфуд канона (шаблоны — sheet_village.gd t53/t54, sheet_cave.gd c1):
##  - единственный источник цвета — PixelPalette; САМОПРОВЕРКИ: off-палитра=0,
##    полупрозрачных (mask) пикселей=0, нижний ряд силуэта — OUTLINE, СЗ-свет,
##    тайлы непрозрачны и бесшовны (пин-метрика шва);
##  - дельта палитры = пусто: ни одного нового цвета; VIOLET (рампа C пещеры)
##    в лесу не участвует (лес зелёный, с пещерой не спорит);
##  - резец кроны/пней/камней — геометрия утверждённой «Деревни v4» 1:1.
##
## Байт-воспроизводимость: ноль randi — только хэш-шум; повторный запуск (и
## bake x2) обязан дать равные CONTENT-HASH и равные md5 файлов.
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_forest_v1.gd -- <out.png>
##   Godot ... -- bake <out_dir>   — атласы forest_floor_v1.png (64×16),
##     forest_props_v1.png + манифест forest_regions.json.
## Выход 0 — все самопроверки PASS, иначе 1.

const P := preload("res://scripts/pixel_palette.gd")
const FP := preload("res://tools_art/forest_paint.gd")
const CP := preload("res://tools_art/cave_paint.gd")

const SEAM_RATIO_MAX := 2.2

var _fails := 0
var _idx := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_idx = P.color_index()
	var mode := "sheet"
	var target := "res://tools_art/sheet_forest_v1.png"
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

# ============================================================ наборы

func _tiles() -> Array:
	var out: Array = []
	for t in FP.floor_tile_set():
		out.append({"name": t["name"], "short": t["short"], "canon": "16X16 TILE",
				"img": t["img"], "tile": true,
				"seam_h": t["name"] in ["FFLR", "FFLR2", "FEDGE_S"],
				"seam_v": t["name"] in ["FFLR", "FFLR2", "FEDGE_E"]})
	return out

func _props() -> Array:
	var out: Array = []
	for s in FP.prop_set_canon():
		out.append({"name": s["name"], "short": s["name"], "canon": s["canon"], "img": s["img"]})
	return out

func _sway_row() -> Array:
	var out: Array = []
	out.append_array(FP.sway_triplet("PINE_T1", "3.0H", FP.build_pine_t1))
	out.append_array(FP.sway_triplet("OAK_T", "3.0H fit", FP.build_oak_t))
	out.append_array(FP.sway_triplet("OAK_TP", "3.0H walk", FP.build_oak_tp))
	out.append_array(FP.sway_triplet("BUSH", "0.7H", FP.build_bush))
	out.append_array(FP.sway_triplet("BUSH2", "0.6H", FP.build_bush2))
	return out

# ============================================================ самопроверки

func _check_sprite(s: Dictionary) -> void:
	var img: Image = s["img"]
	var nm := String(s["name"])
	var w := img.get_width()
	var h := img.get_height()
	var foreign := 0
	var mask := 0
	var uniq := {}
	for y in h:
		for x in w:
			var col := img.get_pixel(x, y)
			if col.a > 0.0 and col.a < 1.0:
				mask += 1
			if col.a < 0.5:
				continue
			uniq[P.key(col)] = true
			if not _idx.has(P.key(col)):
				foreign += 1
	if foreign > 0:
		_fails += 1
		print("[FAIL] %s: %d пикселей вне палитры (off)" % [nm, foreign])
	if mask > 0:
		_fails += 1
		print("[FAIL] %s: %d полупрозрачных px (mask)" % [nm, mask])
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
	print("[spr] %-10s %2dx%-2d %8s off:%d mask:%d light t/b:%d/%d hash:%s" % [nm, w, h, String(s["canon"]), foreign, mask, lt_top, lt_bot, CP.img_hash(img)])

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
		print("[tile] %-9s 16x16 off:0 mask:0 ok hash:%s" % [nm, CP.img_hash(img)])

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
	var mark := ""
	if bool(t.get("seam_h", false)) and ratio_x > SEAM_RATIO_MAX:
		_fails += 1
		mark = " [FAIL PIN]"
	print("[seam] %-9s horiz seam=%.1f field=%.1f ratio=%.2f%s" % [String(t["name"]), seam_x, field_x, ratio_x, mark])
	if bool(t.get("seam_v", false)):
		var v := ""
		if ratio_y > SEAM_RATIO_MAX:
			_fails += 1
			v = " [FAIL PIN]"
		print("[seam] %-9s vertil seam=%.1f ratio=%.2f%s" % [String(t["name"]), seam_y, ratio_y, v])

func _check_atlas(img: Image, nm: String) -> void:
	var off := 0
	var mask := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a > 0.0 and col.a < 1.0:
				mask += 1
			if col.a > 0.5 and not _idx.has(P.key(col)):
				off += 1
	if off > 0 or mask > 0:
		_fails += 1
	print("[atlas] %-16s %dx%d off:%d mask:%d hash:%s" % [nm, img.get_width(), img.get_height(), off, mask, CP.img_hash(img)])

func _db(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var a := img.get_pixel(x0, y0)
	var b := img.get_pixel(x1, y1)
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0

# ============================================================ режимы

func _sheet(out_path: String) -> void:
	var tiles := _tiles()
	var props := _props()
	var sway := _sway_row()
	for t in tiles:
		_check_tile(t)
		_check_seam(t)
	for s in props:
		_check_sprite(s)
	for s in sway:
		_check_sprite(s)
	# атласные candidate-файлы тоже проверяем (тот же пиксель, что в bake)
	var pres: Dictionary = FP.bake_props_atlas()
	_check_atlas(FP.bake_floor_atlas(), "forest_floor_v1")
	_check_atlas(pres["img"], "forest_props_v1")
	var sheet := _compose(tiles, props, sway)
	var err := sheet.save_png(out_path)
	print("sheet saved: %s (%dx%d) err=%d" % [out_path, sheet.get_width(), sheet.get_height(), err])
	var up := _upscale2(sheet)
	var p2 := out_path.replace(".png", "_2x.png")
	var err2 := up.save_png(p2)
	print("sheet saved: %s (%dx%d) err=%d" % [p2, up.get_width(), up.get_height(), err2])

func _bake(out_dir: String) -> void:
	var fatlas: Image = FP.bake_floor_atlas()
	var pres: Dictionary = FP.bake_props_atlas()
	_check_atlas(fatlas, "forest_floor_v1")
	_check_atlas(pres["img"], "forest_props_v1")
	for t in _tiles():
		_check_tile(t)
		_check_seam(t)
	var e1 := fatlas.save_png(out_dir + "/forest_floor_v1.png")
	var e2 := (pres["img"] as Image).save_png(out_dir + "/forest_props_v1.png")
	var manifest := {
		"atlas_size": [int(pres["size"].x), int(pres["size"].y)],
		"floor_slots": {"FFLR": 0, "FFLR2": 1, "FEDGE_S": 2, "FEDGE_E": 3},
		"props": pres["regions"],
		"sway": {"frames": ["_A", "_B", "_C"], "T_s": 0.5,
				"note": "int(t/T)%3, фаза из FNV-хэша клетки (прецедент c7/c9)"},
	}
	var mf := FileAccess.open(out_dir + "/forest_regions.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.flush()
	print("bake saved: forest_floor_v1.png (%dx%d) err=%d; forest_props_v1.png (%dx%d) err=%d; forest_regions.json" % [
			fatlas.get_width(), fatlas.get_height(), e1,
			(pres["img"] as Image).get_width(), (pres["img"] as Image).get_height(), e2])
	for k in (pres["regions"] as Dictionary):
		var p: Dictionary = pres["regions"][k]
		print("[region] %-10s x=%d y=%d w=%d h=%d off=(%d,%d)" % [String(k), int(p["x"]), int(p["y"]), int(p["w"]), int(p["h"]), int(p["off_x"]), int(p["off_y"])])

# ============================================================ шрифт/примитивы (эталон sheet_cave)

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

func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

func hp(x: int, y: int) -> float:
	return CP.hp(x, y)

## alpha-blit src в dst с масштабом sc ( nearest ), прозрачность src — дыра
func _blit(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var col := src.get_pixel(x, y)
			if col.a < 0.5:
				continue
			for dy in sc:
				for dx in sc:
					_px(dst, x0 + x * sc + dx, y0 + y * sc + dy, col)

func _draw_row(sheet: Image, items: Array, sc: int, x0: int, y0: int, maxh: int, pad: int, gap: int) -> void:
	var x := x0
	for s in items:
		var img: Image = s["img"]
		var cw: int = img.get_width() * sc
		var cell_w := cw + pad * 2
		var cell_h := maxh * sc + pad * 2
		var cy := y0 + (maxh - img.get_height()) * sc
		_rect(sheet, x, y0, x + cell_w - 1, y0 + cell_h - 1, P.SHEET["PANEL"])
		_rect(sheet, x, y0, x + cell_w - 1, y0, P.SHEET["LINE"])
		_rect(sheet, x, y0 + cell_h - 1, x + cell_w - 1, y0 + cell_h - 1, P.SHEET["LINE"])
		_blit(sheet, img, x + pad, cy + pad, sc)
		_text(sheet, x + 2, y0 + cell_h + 3, String(s["name"]), 1, P.SHEET["TEXT"])
		_text(sheet, x + 2, y0 + cell_h + 10, "%dX%d %s" % [img.get_width(), img.get_height(), String(s["canon"])], 1, P.SHEET["LINE"])
		x += cell_w + gap

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

# ============================================================ коллаж и ряды честности

## Контекст-коллаж: луг v4 (утверждённый пол) → тропа → кромка → лес.
## 28×7 клеток при 2x. Пропы сортированы по стопе (демо честного y-sort).
func _draw_collage(sheet: Image, x0: int, y0: int) -> void:
	var cw := 28
	var ch := 7
	var sc := 2
	var v4f: Image = load("res://assets/village/village_floor_v4.png").get_image()
	var tiles := FP.floor_tile_set()
	var fflr: Image = tiles[0]["img"]
	var fflr2: Image = tiles[1]["img"]
	var edges: Image = tiles[2]["img"]
	# 1) полы
	for cy in ch:
		for cx in cw:
			var t: Image
			if cy >= 5:
				var slot := 0
				if cy == 5 and cx >= 2 and cx <= 11:
					slot = 3  # тропа из деревни
				elif hp(cx * 3 + 1, cy) > 0.7:
					slot = 1
				t = v4f.get_region(Rect2i(slot * 16, 0, 16, 16))
			elif cy == 4:
				t = edges
			else:
				t = fflr if hp(cx + 2, cy + 7) > 0.5 else fflr2
			_blit(sheet, t, x0 + cx * 16 * sc, y0 + cy * 16 * sc, sc)
	# 2) пропы: (имя, клетка_x, клетка_y_ноги, фаза)
	var items: Array = [
		["PINE_T2", 12, 1, 0], ["PINE_T1", 16, 2, 0], ["PINE_T1", 11, 3, 0],
		["PINE_T2", 25, 1, 1], ["OAK_T", 21, 3, 2], ["PINE_T1", 26, 3, 0],
		["BUSH", 13, 2, 0], ["BUSH2", 18, 1, 0], ["BUSH", 24, 4, 1],
		["BUSH2", 14, 4, 0], ["FERN", 10, 2, 0], ["FERN2", 19, 2, 0],
		["FERN", 15, 1, 0], ["FERN2", 27, 2, 0],
		["STUMP_F", 20, 4, 0], ["STONE_M", 17, 4, 0], ["STONES_F", 9, 3, 0],
		["SHROOM1", 13, 3, 0], ["SHROOM2", 23, 3, 0], ["STUMP_F2", 22, 2, 0],
	]
	var painted: Array = []
	for it in items:
		var nm := String(it[0])
		var img: Image
		match nm:
			"PINE_T1": img = FP.build_pine_t1(int(it[3]))
			"PINE_T2": img = FP.build_pine_t2(int(it[3]))
			"OAK_T": img = FP.build_oak_t(int(it[3]))
			"BUSH": img = FP.build_bush(int(it[3]))
			"BUSH2": img = FP.build_bush2(int(it[3]))
			"FERN": img = FP.build_fern()
			"FERN2": img = FP.build_fern2()
			"STUMP_F": img = FP.build_stump_f()
			"STUMP_F2": img = FP.build_stump_f2()
			"STONES_F": img = FP.build_stones_f()
			"STONE_M": img = FP.build_stone_m()
			"SHROOM1": img = FP.build_shroom1()
			"SHROOM2": img = FP.build_shroom2()
		painted.append([int(it[2]), int(it[1]), img])
	# герой (class_warrior, кадр 0,0) стоит на тропе
	var hero_src: Image = load("res://assets/class_warrior.png").get_image()
	var hero: Image = hero_src.get_region(Rect2i(0, 0, 16, 16))
	painted.append([5, 5, hero])
	painted.sort_custom(func(a, b): return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	for pp in painted:
		var fy: int = pp[0]
		var fx: int = pp[1]
		var img2: Image = pp[2]
		var dx := x0 + fx * 16 * sc
		var dy := y0 + (fy + 1) * 16 * sc - img2.get_height() * sc
		_blit(sheet, img2, dx, dy, sc)
	_rect(sheet, x0, y0, x0 + cw * 16 * sc - 1, y0 + ch * 16 * sc - 1, P.SHEET["LINE"])

## Ряд честности: легаси-клетки tiles.png (уходят) и v4-пол (не трогается).
func _draw_honesty(sheet: Image, x0: int, y0: int) -> void:
	var legacy: Image = load("res://assets/tiles.png").get_image()
	var v4f: Image = load("res://assets/village/village_floor_v4.png").get_image()
	var sc := 4
	var labels_l := [["LEGACY_T5", 5, "TILE 5 TREE T"], ["LEGACY_R12", 12, "TILE 12 ROCK R"], ["LEGACY_T15", 15, "TILE 15 WALK T"]]
	var x := x0
	for lb in labels_l:
		var cell: Image = legacy.get_region(Rect2i(int(lb[1]) * 16, 0, 16, 16))
		_blit(sheet, cell, x, y0, sc)
		_rect(sheet, x - 1, y0 - 1, x + 16 * sc, y0 + 16 * sc, P.SHEET["LINE"])
		_text(sheet, x, y0 + 16 * sc + 3, String(lb[2]), 1, P.SHEET["TEXT"])
		x += 16 * sc + 22
	x += 24
	_text(sheet, x - 20, y0 + 8, "->", 2, P.SHEET["LINE"])
	var v4lbl := ["V4 GRASS", "V4 GRASS2", "V4 FLOWER", "V4 PATH", "V4 WATER"]
	for i in 5:
		var cell2: Image = v4f.get_region(Rect2i(i * 16, 0, 16, 16))
		_blit(sheet, cell2, x, y0, sc)
		_rect(sheet, x - 1, y0 - 1, x + 16 * sc, y0 + 16 * sc, P.SHEET["LINE"])
		_text(sheet, x, y0 + 16 * sc + 3, v4lbl[i], 1, P.SHEET["LINE"])
		x += 16 * sc + 10

# ============================================================ композиция

func _compose(tiles: Array, props: Array, sway: Array) -> Image:
	var pad := 6
	var gap := 14
	var title := 34
	var lbl := 20
	var tile_h4 := 16 * 4 + pad * 2
	var tile_h1 := 16 + pad * 2
	var prop_h4 := _row_h(props) * 4 + pad * 2
	var prop_h1 := _row_h(props) + pad * 2
	var sway_h4 := _row_h(sway) * 4 + pad * 2
	var sway_h1 := _row_h(sway) + pad * 2
	var honesty_h := 16 * 4 + 14
	var collage_h := 7 * 16 * 2 + 6
	var W0 := maxi(_row_w(tiles, 4, pad, gap), _row_w(props, 4, pad, gap))
	var collage_w := 28 * 16 * 2 + 30
	var W := maxi(maxi(W0, _row_w(sway, 4, pad, gap)), collage_w) + 40
	var H := title + (tile_h4 + lbl) + (tile_h1 + lbl) + (prop_h4 + lbl) + (prop_h1 + lbl) \
			+ (sway_h4 + lbl) + (sway_h1 + lbl) + (honesty_h + 16) + (collage_h + 16) + 40
	var sheet := _im(W, H)
	sheet.fill(P.SHEET["BG"])
	_text(sheet, 10, 8, "FOREST V1 - PIXEL CANON SHEET (CODEGEN, HEAD C06E77C)", 2, P.SHEET["TEXT"])
	_text(sheet, 10, 22, "NW LIGHT / FOOT OUTLINE / TILE16 H16 / PAL DELTA = EMPTY / VIOLET RAMP C UNUSED", 1, P.SHEET["LINE"])
	var y := title
	_text(sheet, 10, y + 2, "TILES 4X", 1, P.SHEET["LINE"])
	_draw_row(sheet, tiles, 4, 90, y, 16, pad, gap)
	y += tile_h4 + lbl
	_text(sheet, 10, y + 2, "TILES 1X=SCREEN", 1, P.SHEET["LINE"])
	_draw_row(sheet, tiles, 1, 90, y, 16, pad, gap)
	y += tile_h1 + lbl
	_text(sheet, 10, y + 2, "PROPS 4X", 1, P.SHEET["LINE"])
	_draw_row(sheet, props, 4, 90, y, _row_h(props), pad, gap)
	y += prop_h4 + lbl
	_text(sheet, 10, y + 2, "PROPS 1X=SCREEN", 1, P.SHEET["LINE"])
	# герой-бокс
	var hero: Image = load("res://assets/class_warrior.png").get_image().get_region(Rect2i(0, 0, 16, 16))
	_blit(sheet, hero, 90 + 6, y + pad + (_row_h(props) - 16), 1)
	_text(sheet, 90, y + pad + _row_h(props) + 10, "HERO16", 1, P.SHEET["LINE"])
	_draw_row(sheet, props, 1, 90 + 44, y, _row_h(props), pad, gap)
	y += prop_h1 + lbl
	_text(sheet, 10, y + 2, "SWAY A/B/C 4X (FUNC OF TIME, NO PHYS NODES - C7/C9)", 1, P.SHEET["LINE"])
	_draw_row(sheet, sway, 4, 90, y, _row_h(sway), pad, gap)
	y += sway_h4 + lbl
	_text(sheet, 10, y + 2, "SWAY 1X", 1, P.SHEET["LINE"])
	_draw_row(sheet, sway, 1, 90, y, _row_h(sway), pad, gap)
	y += sway_h1 + lbl + 6
	_text(sheet, 10, y + 2, "HONESTY: LEFT = LEAVING TILES.PNG CELLS - RIGHT = V4 APPROVED, NOT TOUCHED", 1, P.SHEET["LINE"])
	y += 14
	_draw_honesty(sheet, 10, y)
	y += honesty_h + 16
	_text(sheet, 10, y + 2, "COLLAGE 2X: MEADOW V4 + PATH -> FEDGE -> FOREST (PROPS Y-SORTED BY FOOT)", 1, P.SHEET["LINE"])
	_draw_collage(sheet, 10, y + 12)
	# легенда рамп
	var used := ["GRASS", "PATH", "LEAF", "PINE", "BARK", "WOOD", "STONE", "CLOTH", "HP_RED", "BONE"]
	var ny := H - 26
	_text(sheet, 10, ny - 9, "RAMPS USED (PIXELPALETTE FOREST ZONE, DELTA = EMPTY; VIOLET NOT USED HERE)", 1, P.SHEET["LINE"])
	var nx0 := 10
	for rn in used:
		var ramp: Array = P.RAMPS[rn]
		for t in 4:
			_rect(sheet, nx0 + t * 7, ny, nx0 + t * 7 + 5, ny + 7, ramp[t])
		_text(sheet, nx0, ny + 9, rn.left(7), 1, P.SHEET["LINE"])
		nx0 += 4 * 7 + 9
	print("[hash] sheet pre-save %s" % CP.img_hash(sheet))
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
