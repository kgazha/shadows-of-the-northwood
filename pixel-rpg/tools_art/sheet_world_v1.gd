extends SceneTree
## Инструмент листа «Мир v1» (волна «Мир v1»). t1 — лист на вердикт;
## 18.11 отмашка пользователя («да», без правок) — t3-интеграция: F5-прорезка
## южных ворот сквозной тропой, F3-хэш shash() вместо String.hash(), проп
## ARCH_NORTH (северная арка-интерактор деревни), режим wire (атласы в игру).
##
## ЛИСТ t1 (архив): игра тогда не читала ни одного из этих артов; интеграция —
## после «да» пользователя (конвенция листа sheet_cave t53 / forest v1). Лист:
## тайлы пола/кромки шести биомов (лес — утверждённый forest v1 как есть),
## декор, шесть порталов локаций, рамка карты мира с деревней, южными
## сквозными воротами и слотами порталов, кластеры глухой массы с проходами
## >= 2 клетки (правило g24a), легенда семейств PixelPalette (дельта = пусто).
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_world_v1.gd -- <out.png>
##   Godot ... -- bake <out_dir>     — КАНДИДАТ атласов (в out_dir, status
##     CANDIDATE); Godot ... -- wire <dir> — атласы для assets (status WIRED).
## Выход 0 — все самопроверки PASS, иначе 1.

const P := preload("res://scripts/pixel_palette.gd")
const WP := preload("res://tools_art/world_paint.gd")
const FP := preload("res://tools_art/forest_paint.gd")
const CP := preload("res://tools_art/cave_paint.gd")

const SEAM_RATIO_MAX := 2.4

var _fails := 0
var _idx := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_idx = P.color_index()
	var mode := "sheet"
	var target := "res://tools_art/sheet_world_v1.png"
	if args.size() > 0:
		if String(args[0]) in ["sheet", "bake", "wire"]:
			mode = String(args[0])
			if args.size() > 1:
				target = String(args[1])
		else:
			target = String(args[0])
	if mode == "bake" or mode == "wire":
		_bake(target, mode == "wire")
	else:
		_sheet(target)
	if _fails > 0:
		print("SELF-CHECK: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("SELF-CHECK: PASS")
		quit(0)

# ============================================================ самопроверки

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
		print("[tile] %-10s 16x16 off:0 mask:0 ok hash:%s" % [nm, CP.img_hash(img)])

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
	var mark := ""
	if bool(t.get("seam_h", false)) and ratio_x > SEAM_RATIO_MAX:
		_fails += 1
		mark = " [FAIL PIN]"
	print("[seam] %-10s horiz seam=%.1f field=%.1f ratio=%.2f%s" % [String(t["name"]), seam_x, field_x, ratio_x, mark])
	if bool(t.get("seam_v", false)):
		var seam_y := 0.0
		for x in w:
			seam_y += _db(img, x, 15, x, 0)
		seam_y /= float(w)
		var field_y := 0.0
		for y in range(h - 1):
			for x in w:
				field_y += _db(img, x, y, x, y + 1)
		field_y /= float((h - 1) * w)
		var ratio_y := seam_y / maxf(field_y, 0.001)
		var v := ""
		if ratio_y > SEAM_RATIO_MAX:
			_fails += 1
			v = " [FAIL PIN]"
		print("[seam] %-10s vertil seam=%.1f ratio=%.2f%s" % [String(t["name"]), seam_y, ratio_y, v])

func _check_sprite(s: Dictionary) -> void:
	var img: Image = s["img"]
	var nm := String(s["name"])
	var w := img.get_width()
	var h := img.get_height()
	var foreign := 0
	var mask := 0
	for y in h:
		for x in w:
			var col := img.get_pixel(x, y)
			if col.a > 0.0 and col.a < 1.0:
				mask += 1
			if col.a < 0.5:
				continue
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
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.5:
				continue
			var info = _idx.get(P.key(img.get_pixel(x, y)))
			if info == null or not P.RAMPS.has(String(info[0])):
				continue
			if int(info[1]) == P.T_LIGHT and y < h / 2.0:
				lt_top += 1
	if lt_top < 3:
		_fails += 1
		print("[FAIL] %s: нет подсветки СЗ (LIGHT сверху: %d)" % [nm, lt_top])
	print("[spr] %-10s %2dx%-2d %10s off:%d mask:%d light:%d hash:%s" % [nm, w, h, String(s["canon"]), foreign, mask, lt_top, CP.img_hash(img)])

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

func _check_frame(img: Image) -> void:
	var off := 0
	var mask := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a > 0.0 and col.a < 1.0:
				mask += 1
			if col.a < 0.5 or not _idx.has(P.key(col)):
				off += 1
	if off > 0 or mask > 0:
		_fails += 1
		print("[FAIL] world_frame: off=%d mask=%d" % [off, mask])
	print("[frame] world_frame %dx%d off:0 mask:0 hash:%s" % [img.get_width(), img.get_height(), CP.img_hash(img)])

func _check_clusters() -> void:
	for c in [["SNOW", WP.CLUSTER_SNOW], ["DESERT", WP.CLUSTER_DESERT], ["CASTLE", WP.CLUSTER_CASTLE]]:
		var holes: Array = WP.cluster_holes(c[1])
		if holes.size() > 0:
			_fails += 1
			print("[FAIL] cluster %s: единичные проходы (правило >=2): %s" % [String(c[0]), str(holes)])
		else:
			print("[mass] cluster %-8s все проходы покрыты 2x2 свободно (>= 2 клетки)" % String(c[0]))

func _db(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var a := img.get_pixel(x0, y0)
	var b := img.get_pixel(x1, y1)
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0

# ============================================================ наборы листа

func _biome_tiles(b: Dictionary) -> Array:
	var out: Array = []
	for f in (b["floors"] as Array):
		out.append({"name": String(f["name"]), "img": f["img"], "tile": true,
				"seam_h": bool(f.get("seam_h", false)), "seam_v": bool(f.get("seam_v", false))})
	for e in (b["edges"] as Array):
		out.append({"name": String(e["name"]), "img": e["img"], "tile": true, "seam_h": false, "seam_v": false})
	return out

func _biome_props(b: Dictionary) -> Array:
	var out: Array = []
	for p in (b["props"] as Array):
		out.append({"name": String(p["name"]), "canon": String(p["canon"]), "img": p["img"]})
	return out

func _forest_tiles() -> Array:
	var out: Array = []
	for t in FP.floor_tile_set():
		out.append({"name": String(t["name"]), "img": t["img"], "tile": true,
				"seam_h": t["name"] in ["FFLR", "FFLR2", "FEDGE_S"], "seam_v": t["name"] in ["FFLR", "FFLR2", "FEDGE_E"]})
	return out

func _forest_props() -> Array:
	var out: Array = []
	for k in ["PINE_T2", "OAK_T", "BUSH", "STONE_M", "FERN"]:
		for s in FP.prop_set_canon():
			if String(s["name"]) == k:
				out.append({"name": k, "canon": String(s["canon"]), "img": s["img"]})
	return out

# ============================================================ режимы

func _all_checks() -> void:
	for b in WP.biome_list():
		if String(b["id"]) == "FOREST":
			continue
		for t in _biome_tiles(b):
			_check_tile(t)
			_check_seam(t)
		for s in _biome_props(b):
			_check_sprite(s)
	for t in _forest_tiles():
		_check_tile(t)
	for s in WP.portals():
		_check_sprite(s)
	for s in WP.extra_props():
		_check_sprite(s)
	for t in WP.extra_floors():
		_check_tile(t)
		_check_seam(t)
	_check_clusters()
	_check_atlas(WP.bake_floor_atlas(), "world_floor_v1")
	_check_atlas((WP.bake_props_atlas() as Dictionary)["img"], "world_props_v1")
	_check_frame(WP.world_frame())

func _sheet(out_path: String) -> void:
	_all_checks()
	var hero: Image = load("res://assets/class_warrior.png").get_image().get_region(Rect2i(0, 0, 16, 16))
	var pad := 6
	var gap := 12
	var x0 := 10
	var W := 660
	var sheet := _im(W, 3060)
	sheet.fill(P.SHEET["BG"])
	_text(sheet, 10, 8, "WORLD V1 - SIX BIOMES SHEET (T3 INTEGRATION - F5 GATE + ARCH_NORTH, 18.11)", 2, P.SHEET["TEXT"])
	_text(sheet, 10, 24, "640X360 ZOOM1 / HERO 16PX / PALETTE DELTA = EMPTY / NW LIGHT / FOOT OUTLINE / MASS CORRIDORS >= 2 CELLS", 1, P.SHEET["LINE"])
	var y := 40
	var biome_sections := {}
	for b in WP.biome_list():
		var id := String(b["id"])
		if id == "FOREST":
			continue
		var tiles := _biome_tiles(b)
		var props := _biome_props(b)
		_text(sheet, x0, y, "%s BIOME - TILES 4X + 1X (NATIVE)" % id, 1, P.SHEET["TEXT"])
		y += 12
		var sec_y0 := y
		_draw_row(sheet, tiles, 4, x0, y, 16, pad, gap)
		_draw_row(sheet, tiles, 1, x0 + _row_w(tiles, 4, pad, gap) + 24, y + (16 * 4 - 16) / 2, 16, pad, gap)
		y += 16 * 4 + pad * 2 + 22
		_text(sheet, x0, y, "%s DECOR 4X (FOOT OUTLINE, YSORT FOOT)" % id, 1, P.SHEET["LINE"])
		y += 12
		_draw_row(sheet, props, 4, x0, y, _row_h(props), pad, gap)
		y += _row_h(props) * 4 + pad * 2 + 26
		var sec_y1 := y
		biome_sections[id] = Rect2i(x0, sec_y0, W - x0 * 2, sec_y1 - sec_y0)
	# лес — утверждённый v1 как есть
	var ft := _forest_tiles()
	var fp := _forest_props()
	_text(sheet, x0, y, "FOREST - APPROVED V1 REUSED AS IS (NO REDRAW, NO NEW COLOR)", 1, P.SHEET["TEXT"])
	y += 12
	_draw_row(sheet, ft, 4, x0, y, 16, pad, gap)
	_draw_row(sheet, fp, 4, x0 + _row_w(ft, 4, pad, gap) + 24, y, _row_h(fp), pad, gap)
	y += 16 * 4 + pad * 2 + 26
	# порталы
	var ports := WP.portals()
	_text(sheet, x0, y, "LOCATION PORTALS 4X (ARCH + BIOME RUNE; CASTLE IRON BANDS / DUNGEON STONE)", 1, P.SHEET["TEXT"])
	y += 12
	_draw_row(sheet, ports, 4, x0, y, 26, pad, gap)
	_blit(sheet, hero, x0 + _row_w(ports, 4, pad, gap) + 16, y + pad + 26 * 4 - 16, 4)
	_text(sheet, x0 + _row_w(ports, 4, pad, gap) + 16, y + pad + 26 * 4 + 6, "HERO16", 1, P.SHEET["LINE"])
	y += 26 * 4 + pad * 2 + 26
	# северная арка деревни (w3): интерактор выхода на карту мира
	var gate := WP.extra_props()
	_text(sheet, x0, y, "VILLAGE NORTH ARCH 4X (WORLD EXIT INTERACTOR - ARCH_NORTH)", 1, P.SHEET["TEXT"])
	y += 12
	_draw_row(sheet, gate, 4, x0, y, 24, pad, gap)
	_blit(sheet, hero, x0 + _row_w(gate, 4, pad, gap) + 16, y + pad + 24 * 4 - 16, 4)
	y += 24 * 4 + pad * 2 + 26
	# кластеры массы
	_text(sheet, x0, y, "MASS CLUSTERS 2X - CORRIDORS >= 2 CELLS BY GEOMETRY (g24a); HERO PAIR = 2 CELLS CLEAR", 1, P.SHEET["TEXT"])
	y += 12
	var cl_y0 := y
	var sc1 := WP.cluster_scene(WP.CLUSTER_SNOW, [WP.build_snow_f1(), WP.build_snow_f2()],
			{"M": [WP.build_snow_pine(), WP.build_snow_rock()]}, {"i": [WP.build_ice_spike()]})
	var sc2 := WP.cluster_scene(WP.CLUSTER_DESERT, [WP.build_desert_f1(), WP.build_desert_f2()],
			{"M": [WP.build_mesa()], "C": [WP.build_cactus()]}, {"S": [WP.build_skull()]})
	var sc3 := WP.cluster_scene(WP.CLUSTER_CASTLE, [WP.build_castle_f1(), WP.build_castle_f2()],
			{"W": [WP.build_wall_t()]}, {"b": [WP.build_banner()], "r": [WP.build_crate(), WP.build_barrel()]})
	var scenes := [sc1, sc2, sc3]
	var hx := [[4, 4], [15, 4], [2, 2]]
	var cx0 := x0
	for i in 3:
		var sc: Image = scenes[i]
		_blit(sheet, sc, cx0, y, 2)
		# пара героев в свободный проход (2 клетки)
		var extra := 4
		var px0: int = cx0 + int(hx[i][0]) * 16 * 2
		var py0: int = y + (extra + int(hx[i][1]) + 1) * 16 * 2 - 16 * 2
		_blit(sheet, hero, px0, py0, 2)
		_blit(sheet, hero, px0 + 16 * 2, py0, 2)
		_rect(sheet, cx0 - 1, y - 1, cx0 + sc.get_width() * 2, y + sc.get_height() * 2, P.SHEET["LINE"])
		cx0 += sc.get_width() * 2 + 14
	var cl_y1 := y + maxi(sc1.get_height(), maxi(sc2.get_height(), sc3.get_height())) * 2
	y = cl_y1 + 30
	# рамка мира
	_text(sheet, x0, y, "WORLD FRAME 4X: MOUNTAIN RING - 6 BIOME REGIONS - VILLAGE + SOUTH ARCH - 6 PORTAL SLOTS", 1, P.SHEET["TEXT"])
	y += 12
	var fr_y0 := y
	var frame := WP.world_frame()
	_blit(sheet, frame, x0, y, 4)
	_rect(sheet, x0 - 1, y - 1, x0 + frame.get_width() * 4, y + frame.get_height() * 4, P.SHEET["LINE"])
	var fr_y1 := y + frame.get_height() * 4
	y = fr_y1 + 16
	# честность
	_text(sheet, x0, y, "HONESTY - IN GAME TODAY (NOT TOUCHED BY THIS SHEET): VILLAGE V4 FLOORS / FOREST V1", 1, P.SHEET["TEXT"])
	y += 12
	var v4f: Image = load("res://assets/village/village_floor_v4.png").get_image()
	var xx := x0
	for i in 5:
		_blit(sheet, v4f.get_region(Rect2i(i * 16, 0, 16, 16)), xx, y, 4)
		xx += 16 * 4 + 6
	var fft: Image = FP.bake_floor_atlas()
	for i in 4:
		_blit(sheet, fft.get_region(Rect2i(i * 16, 0, 16, 16)), xx, y, 4)
		xx += 16 * 4 + 6
	y += 16 * 4 + 22
	# легенда семейств
	_text(sheet, x0, y, "FAMILIES (PIXELPALETTE ONLY - DELTA EMPTY): SNOW BONE+STONE+CRYSTAL / DESERT PATH+STONE_WARM+LEAF / STEPPE GRASS+PATH", 1, P.SHEET["LINE"])
	_text(sheet, x0, y + 9, "CASTLE STONE+IRON+BRONZE+CLOTH / DUNGEON VIOLET+CRYSTAL+MOSS_GLOW / FOREST GRASS+PINE+BARK (APPROVED)", 1, P.SHEET["LINE"])
	y += 20
	var nx0 := x0
	for rn in ["BONE", "STONE", "CRYSTAL", "PATH", "STONE_WARM", "LEAF", "GRASS", "IRON", "BRONZE", "CLOTH", "VIOLET", "MOSS_GLOW", "PINE", "BARK", "CHAR", "WATER"]:
		var ramp: Array = P.RAMPS[rn]
		for t in 4:
			_rect(sheet, nx0 + t * 6, y, nx0 + t * 6 + 4, y + 7, ramp[t])
		_text(sheet, nx0, y + 9, rn.left(6), 1, P.SHEET["LINE"])
		nx0 += 4 * 6 + 8
	var final_h := y + 24
	if final_h < sheet.get_height():
		var trimmed := sheet.get_region(Rect2i(0, 0, sheet.get_width(), final_h))
		sheet = trimmed
	var err := sheet.save_png(out_path)
	print("sheet saved: %s (%dx%d) err=%d" % [out_path, sheet.get_width(), sheet.get_height(), err])
	print("[hash] sheet pre-save %s" % CP.img_hash(sheet))
	# превью x3: снежный разворот / кластеры / рамка
	var pv1 := sheet.get_region(Rect2i(0, biome_sections["SNOW"].position.y, W, biome_sections["SNOW"].size.y))
	_save3(pv1, out_path.replace(".png", "_pv_snow3x.png"))
	var pv2 := sheet.get_region(Rect2i(0, cl_y0 - 12, W, cl_y1 - cl_y0 + 14))
	_save3(pv2, out_path.replace(".png", "_pv_clusters3x.png"))
	var pv3 := sheet.get_region(Rect2i(x0 - 2, fr_y0 - 2, frame.get_width() * 4 + 6, (fr_y1 - fr_y0) + 4))
	_save3(pv3, out_path.replace(".png", "_pv_frame3x.png"))

func _save3(img: Image, path: String) -> void:
	var up := _upscale(img, 3)
	var e := up.save_png(path)
	print("preview saved: %s (%dx%d) err=%d" % [path, up.get_width(), up.get_height(), e])

func _bake(out_dir: String, wired: bool = false) -> void:
	_all_checks()
	var fatlas: Image = WP.bake_floor_atlas()
	var pres: Dictionary = WP.bake_props_atlas()
	var e1 := fatlas.save_png(out_dir + "/world_floor_v1.png")
	var e2 := (pres["img"] as Image).save_png(out_dir + "/world_props_v1.png")
	var manifest := {
		"status": ("WIRED t3 (18.11) - игра грузит эти атласы в зонах мира"
				if wired else "CANDIDATE - verdict pending, NOT wired into game"),
		"floor_size": [int(fatlas.get_width()), int(fatlas.get_height())],
		"atlas_size": [int(pres["size"].x), int(pres["size"].y)],
		"floor_slots": WP.bake_floor_slots(),
		"props": pres["regions"],
		"forest_note": "forest floors/props stay in forest_floor_v1/forest_props_v1 (approved v1)",
	}
	var mf := FileAccess.open(out_dir + "/world_regions.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.flush()
	print("bake saved: world_floor_v1.png (%dx%d) err=%d; world_props_v1.png (%dx%d) err=%d; world_regions.json" % [
			fatlas.get_width(), fatlas.get_height(), e1,
			(pres["img"] as Image).get_width(), (pres["img"] as Image).get_height(), e2])

# ============================================================ шрифт/примитивы (эталон sheet_forest)

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

func _blit(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var col := src.get_pixel(x, y)
			if col.a < 0.5:
				continue
			for dy in sc:
				for dx in sc:
					_px(dst, x0 + x * sc + dx, y0 + y * sc + dy, col)

func _upscale(img: Image, k: int) -> Image:
	var out := _im(img.get_width() * k, img.get_height() * k)
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			for dy in k:
				for dx in k:
					out.set_pixel(x * k + dx, y * k + dy, col)
	return out

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
