extends SceneTree
## c33: переборка ассетов на фиолетовую рампу C (вердикт пользователя «на твоё
## усмотрение» → капитан: состав C, полный scope 4832 px / 13 файлов, REBAKE c31).
## Источники — те же генераторы, что и у волн c22/c23/c27/t16:
##   • cave/cave_*.png        — cave_paint.bake_* (читает PAL, алиас CAVE_ROCK:=VIOLET);
##   • portraits(.2).png      — c27_golden.GOLD + c27_portraits.bake (MAP с целевыми VIOLET);
##   • 5 спрайтов c23-волны   — c23_golden.GOLD + c22_recolor.recolor_atlas;
##   • anim_tiles/decor/dungeon_tiles — рукотворные, hex-ремап CAVE4->VIOLET4 1:1
##     по тону + snap 51 магийных hex -> ближайший тон VIOLET по светлоте
##     (таблица и правило — c31 mock; ровно как в принятой таблице scan2).
## Остальные файлы дерева не касаются. Детерминировано: никаких randf/timer.
## Запуск: godot --headless --path pixel-rpg -s res://tools_art/c33_violet.gd -- --write

const PAL := preload("res://scripts/pixel_palette.gd")
const CP := preload("res://tools_art/cave_paint.gd")
const CA := preload("res://scripts/cave_art.gd")
const SH27 := preload("res://tools_art/c27_portraits.gd")
const RT22 := preload("res://tools_art/c22_recolor.gd")
## золотые легаси-атласы живут в tools/qa/stand/ (в стенд-рантайме — res://root);
## тул запускается из рабочего дерева стенда, поэтому load() по абсолютному пути
func _gold_script(name: String) -> Dictionary:
	var p := ProjectSettings.globalize_path("res://../tools/qa/stand/" + name)
	var sc = load(p)
	if sc == null:
		push_error("c33: золотой скрипт не найден: " + p)
		return {}
	return sc.GOLD

const CAVE4 := ["7c8299", "5f657c", "454a5f", "2b2f40"]
const SNAP51 := ["2e233f", "452e5e", "4a3865", "654389", "674a81", "704a98", "7d57a2",
	"9373b2", "a678d0", "ab88cb", "c1a4dc", "d6b6f4", "372345", "4d345d", "664e77",
	"1d1b28", "20162a", "26263c", "281f39", "29273f", "292941", "2c273d", "302a40",
	"302d42", "302d43", "302e43", "313147", "332f44", "33334a", "352d41", "353248",
	"383249", "38364e", "3f2c56", "583c70", "7f6e9c", "836fa2", "84609e", "9179ab",
	"967cb1", "977eb4", "997fb4", "9a7fb1", "9f82b4", "ae8ec6", "af90c9", "b795cf",
	"c0a2db", "c39fe1", "c6a0e7", "d0bee2"]
## рукотворные hex-ремапом (путь -> true если применять SNAP, иначе только CAVE)
const HEX_FILES := {
	"res://assets/anim_tiles.png": true,
	"res://assets/decor.png": true,
	"res://assets/dungeon_tiles.png": true,
}
const C23_FILES := {
	"wraith": "res://assets/mobs_wraith.png",
	"mob_archer": "res://assets/mobs_archer.png",
	"swarmling": "res://assets/mobs_swarmling.png",
	"npc_merchant": "res://assets/npc_merchant.png",
	"class_mage": "res://assets/class_mage.png",
}
const GOLD_DIR := "res://../tools/qa/gold/c33_base"

static func _gold_abs(rel: String) -> String:
	# res:// не умеет «..» — переводим в абсолют (FileAccess уже по OS-пути)
	var g := ProjectSettings.globalize_path(GOLD_DIR)
	return g.replace("\\", "/") + "/" + rel

static func _lum(c: Color) -> float:
	return (maxf(maxf(c.r, c.g), c.b) + minf(minf(c.r, c.g), c.b)) * 0.5

static func _expect_map() -> Dictionary:
	var m := {}
	var vio: Array = PAL.RAMPS["VIOLET"]
	for i in 4:
		m[CAVE4[i]] = String((vio[i] as Color).to_html(false))
	for h in SNAP51:
		var l := _lum(Color(h))
		var bi := 0
		var bd := 9e9
		for i in 4:
			var d := absf(_lum(vio[i]) - l)
			if d < bd:
				bd = d
				bi = i
		m[h] = String((vio[bi] as Color).to_html(false))
	return m

static func _remap_file(path: String, m: Dictionary, snap: bool) -> int:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		print("C33 FAIL load ", path)
		return -1
	var changed := 0
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var h := String(c.to_html(false))
			if h == "7c8299" or h == "5f657c" or h == "454a5f" or h == "2b2f40" or snap:
				if m.has(h):
					img.set_pixel(x, y, Color(String(m[h])))
					changed += 1
	var err := img.save_png(path)
	print("C33 HEX %s changed=%d save=%d" % [path, changed, err])
	return changed

func _init() -> void:
	var write := OS.get_cmdline_user_args().has("--write")
	print("C33 VIOLET ramp: ", str(PAL.RAMPS["VIOLET"].map(func(c: Color) -> String: return c.to_html(false))))
	print("C33 CAVE_ROCK is VIOLET: ", str(PAL.RAMPS["CAVE_ROCK"] == PAL.RAMPS["VIOLET"]))
	var m := _expect_map()
	# 1) пещерные атласы — генератор cave_paint
	var paths := ["res://assets/cave/cave_floor_v1.png", "res://assets/cave/cave_wall_v1.png",
		"res://assets/cave/cave_props_v1.png"]
	if write:
		var e1 := CP.bake_floor_atlas().save_png(paths[0])
		var e2 := CP.bake_wall_atlas().save_png(paths[1])
		var pimg: Image = CP.bake_props_atlas(CA.REGIONS, CA.ATLAS_SIZE)["img"]
		var e3 := pimg.save_png(paths[2])
		print("C33 CAVE bake save=", e1, "/", e2, "/", e3)
	# 2) портреты — GOLD + bake (MAP с целевыми VIOLET)
	if write:
		var g27 := _gold_script("c27_golden.gd")
		for id in SH27.FILES:
			var img := Image.new()
			if img.load_png_from_buffer(Marshalls.base64_to_raw(String(g27[id]))) != OK:
				print("C33 FAIL gold portrait ", id)
				quit(2)
				return
			var st: Dictionary = SH27.bake(String(id), img)
			var err := img.save_png(String(SH27.FILES[id]))
			print("C33 PORTRAIT %s changed=%d unknown=%d save=%d" % [id, int(st["changed"]), int(st["unknown"]), err])
			if int(st["unknown"]) != 0 or err != OK:
				quit(2)
				return
	# 3) спрайты c23-волны — GOLD + recolor_atlas
	if write:
		var g23 := _gold_script("c23_golden.gd")
		for a in C23_FILES:
			var img := Image.new()
			if img.load_png_from_buffer(Marshalls.base64_to_raw(String(g23[a]))) != OK:
				print("C33 FAIL gold sprite ", a)
				quit(2)
				return
			var out: Image = RT22.recolor_atlas(String(a), img)
			var err := out.save_png(String(C23_FILES[a]))
			print("C33 SPRITE %s save=%d" % [a, err])
	# 4) рукотворные hex-ремапом
	if write:
		for p in HEX_FILES:
			_remap_file(String(p), m, bool(HEX_FILES[p]))
	# 5) отчёт diff против gold-среза HEAD
	for rel in [
		"anim_tiles.png", "cave/cave_floor_v1.png", "cave/cave_props_v1.png",
		"cave/cave_wall_v1.png", "class_mage.png", "decor.png", "dungeon_tiles.png",
		"mobs_archer.png", "mobs_swarmling.png", "mobs_wraith.png", "npc_merchant.png",
		"portraits.png", "portraits2.png"]:
		var cur := Image.new()
		var bas := Image.new()
		if cur.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/" + rel)) != OK \
				or bas.load_png_from_buffer(FileAccess.get_file_as_bytes(_gold_abs(rel))) != OK:
			print("C33 REPORT-FAIL ", rel)
			quit(2)
			return
		var d := 0
		for y in cur.get_height():
			for x in cur.get_width():
				if cur.get_pixel(x, y).to_argb32() != bas.get_pixel(x, y).to_argb32():
					d += 1
		print("C33 DIFF %s = %d" % [rel, d])
	print("C33 TOOL DONE write=", write)
	quit(0)
