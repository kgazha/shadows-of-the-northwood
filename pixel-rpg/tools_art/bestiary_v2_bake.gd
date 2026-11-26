extends SceneTree
## t26 «Бестиарий v2» (26.11, вердикт пользователя «принимаем бестиарий всех»):
## кодо-бейк рантайм-атласа шести новых мобов + строки манифеста mob_variants.
##
## Единый источник арта — static-билдеры tools_art/sheet_bestiary_v2.gd (лист
## t21, FNV BE81DD9D): кадры K0/K1/T0/T1 каждого вида попадают в атлас
## побитово-равными кадрам листа — самопроверка сверяет FNV32 всех 24 кадров
## с канонической таблицей PINS_W7.md (метод t13/t14: равенство пину держит
## QA-стенд, здесь — неравенство не даёт выйти из tools).
##
## Раскладка атласа mobs_bestiary_v2.png: 64x96 = 6 рядов (вид) × 4 колонки
## (K0/K1/T0/T1), клетка 16px (hero-канон). Ряды — порядок листа:
## 0 ambusher (лес), 1 forerunner (степь), 2 worm (пустыня), 3 whisperer
## (снег), 4 knight (замок), 5 miner (подземелье).
##
## Манифест mobs_variants.json дозаписывается детерминированно (тот же
## JSON.stringify с таб-отступом):
## - шесть kind-строк "<биом>/<вид>": {file, src, fam, kind, row, size};
##   src = базовый атлас семейства-носителя (brute->mobs_boar_v1.png и т.д.),
##   kind-строку рантайм читает НОВЫМ путём (пересборка SpriteFrames), а не
##   region-swap, поэтому открытые old-строки ("<биом>/<семейство>") не
##   трогает ни байтом;
## - одна честная починка t21 №1: "snow/wraith" — снежный wraith-носитель
##   мини-босса перестает быть silent no-op: строка ведёт face шептуна
##   (plain-скина snow/wraith в манифесте нет и не было — face применяет
##   apply_biome_skin по правилу «plain > kind > no-op»).
##
## Запуск:
##   Godot ... -s res://tools_art/bestiary_v2_bake.gd [-- <out_dir>]
## Выход 0 = SELF-CHECK PASS (24 FNV равны пину, off-палитра 0, double-bake
## побайтно равен, манифест перечитывается). В конце печатается MD5 атласа —
## его пинует qa_lp C33.

const P := preload("res://scripts/pixel_palette.gd")
const SH := preload("res://tools_art/sheet_bestiary_v2.gd")

const FAMS := {
	"ambusher": {"biome": "forest", "fam": "brute", "src": "res://assets/mobs_boar_v1.png", "row": 0},
	"forerunner": {"biome": "steppe", "fam": "archer", "src": "res://assets/mobs_archer.png", "row": 1},
	"worm": {"biome": "desert", "fam": "swarmling", "src": "res://assets/mobs_swarmling.png", "row": 2},
	"whisperer": {"biome": "snow", "fam": "wraith", "src": "res://assets/mobs_wraith.png", "row": 3},
	"knight": {"biome": "castle", "fam": "brute", "src": "res://assets/mobs_boar_v1.png", "row": 4},
	"miner": {"biome": "dungeon", "fam": "wraith", "src": "res://assets/mobs_wraith.png", "row": 5},
}
## Канон FNV32 кадров (PINS_W7.md «FNV32 новых кадров», байка листа 25.11):
## равенство рантайм-кадров этому столбцу — и есть «FNV-в-FNV листу».
const FNV_PINS := {
	"ambusher": ["0F2EA201", "E2A3AD2B", "FCA9BAE5", "A305CE04"],
	"forerunner": ["307229E9", "1B906573", "FF25DA5E", "133F6DE3"],
	"worm": ["EA2115E9", "87254D82", "EF713FC6", "9A2BAA9B"],
	"whisperer": ["990B3790", "6A74B86B", "C7B80731", "1FD72A56"],
	"knight": ["79E20412", "02DE0C57", "766D3504", "B5ACA077"],
	"miner": ["55BB94E0", "9763B483", "565238AB", "75ECC43F"],
}
const ROWS := ["ambusher", "forerunner", "worm", "whisperer", "knight", "miner"]
const ATLAS := "mobs_bestiary_v2.png"
const MANIFEST := "res://assets/world/mobs_variants.json"

var _fails := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := "res://assets/world"
	if args.size() > 0:
		out_dir = String(args[0])
	var a := _bake_atlas()
	var b := _bake_atlas()
	if a == null or b == null or a.save_png_to_buffer() != b.save_png_to_buffer():
		_fails += 1
		print("[FAIL] double-bake не побайтен")
	if a != null:
		_check_frames(a)
		_check_palette(a)
		var err := a.save_png(out_dir + "/" + ATLAS)
		if err != OK:
			_fails += 1
			print("[FAIL] save %s err=%d" % [ATLAS, err])
	if _fails == 0:
		_patch_manifest(out_dir)
	print("[atlas] md5 %s" % _md5(out_dir + "/" + ATLAS))
	print("[bake] bestiary_v2 %s" % ("SELF-CHECK: PASS" if _fails == 0 else "SELF-CHECK: FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)

func _bake_atlas() -> Image:
	var im := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	for r in ROWS.size():
		var key := String(ROWS[r])
		for c in 4:
			var fr: Image = SH._new_frame(key, c)
			for y in 16:
				for x in 16:
					var col := fr.get_pixel(x, y)
					if col.a > 0.5:
						im.set_pixel(c * 16 + x, r * 16 + y, col)
	return im

func _check_frames(im: Image) -> void:
	for r in ROWS.size():
		var key := String(ROWS[r])
		for c in 4:
			var fr := im.get_region(Rect2i(c * 16, r * 16, 16, 16))
			var got: String = SH._fnv32_hex(fr)
			var want := String(FNV_PINS[key][c])
			if got != want:
				_fails += 1
				print("[FAIL] %s f%d: FNV %s != пин %s" % [key, c, got, want])

func _check_palette(im: Image) -> void:
	var idx := P.color_index()
	var off := 0
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			if c.a > 0.5 and not idx.has(P.key(c)):
				off += 1
	if off > 0:
		_fails += 1
		print("[FAIL] off-палитра пикселей: %d" % off)
	else:
		print("[scan] off-палитра: 0 (закрытая RAMPS)")

func _patch_manifest(out_dir: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fails += 1
		print("[FAIL] манифест не читается")
		return
	var man := parsed as Dictionary
	var skins := man.get("skins", {}) as Dictionary
	# F-2 аудита 26.11: Godot-парсер JSON отдаёт числа float'ами, stringify их и
	# печатает «64.0» — байтовый дрейф относительно оригинального bake. Все
	# size-массивы возвращаем к int (канон tools_art/mob_variants_v1.gd), иначе
	# будущая ре-генерация манифеста дала бы лишний md5.
	for key in skins:
		var e0: Variant = skins[key]
		if typeof(e0) != TYPE_DICTIONARY:
			continue
		if (e0 as Dictionary).has("size"):
			var sa: Array = (e0 as Dictionary)["size"]
			for i in sa.size():
				sa[i] = int(sa[i])
	for key in ROWS:
		var meta: Dictionary = FAMS[key]
		skins[String(meta["biome"]) + "/" + String(key)] = {
			"file": ATLAS, "src": String(meta["src"]), "fam": String(meta["fam"]),
			"kind": String(key), "row": int(meta["row"]), "size": [64, 96],
		}
	# честный факт t21 №1: починка silent no-op снежного wraith (face шептуна).
	skins["snow/wraith"] = {
		"file": ATLAS, "src": "res://assets/mobs_wraith.png", "fam": "wraith",
		"kind": "whisperer", "row": 3, "size": [64, 96],
	}
	man["skins"] = skins
	man["status"] = "WIRED t3 (18.11) - скины локаций мира; t26 (26.11) - Бестиарий v2: 6 kind-строк + починка snow/wraith"
	var f := FileAccess.open(out_dir + "/mobs_variants.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(man, "\t"))
	f.flush()
	f.close()
	var again: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_dir + "/mobs_variants.json"))
	if typeof(again) != TYPE_DICTIONARY or ((again as Dictionary).get("skins", {}) as Dictionary).size() != skins.size():
		_fails += 1
		print("[FAIL] манифест после записи не перечитывается 1:1")
	else:
		print("[manifest] skins=%d (kind-строк +6, починка snow/wraith)" % skins.size())

func _md5(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "?"
	var hc := HashingContext.new()
	if hc.start(HashingContext.HASH_MD5) != OK:
		f.close()
		return "?"
	hc.update(f.get_buffer(f.get_length()))
	f.close()
	return hc.finish().hex_encode()
