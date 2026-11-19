extends SceneTree
## t3 «Мир v1» шаг 3: тематические рескины мобов шести локаций.
##
## Метод — палитрный ремэп c22 (НЕ тонировка modulate): каждый пиксель
## исходного атласа маппится через PixelPalette (рампа, тон) по таблице
## замен биома; тон сохраняется, рампа меняется на биомную. Функциональные
## цвета (CONTROLS) не трогаем: CHAR-аутлайн читается всегда, HP_RED глаза —
## канонический сигнал угрозы, BONE бивни, IRON клинки, WOOD лук. Готовые
## PNG layouts побайтово совпадают по размеру с оригиналами — рантайм меняет
## только Texture2D под AtlasTexture (регионы/кадры не плывут).
##
## Запуск:
##   Godot ... -s res://tools_art/mob_variants_v1.gd -- bake <out_dir>
##   Godot ... -s res://tools_art/mob_variants_v1.gd -- check
## Выход 0 — все пиксели в RAMPS (off:0), размеры совпали, иначе 1.

const P := preload("res://scripts/pixel_palette.gd")

const FAMILY_ATLAS := {
	"slime": "res://assets/slime.png",
	"brute": "res://assets/brute.png",
	"archer": "res://assets/mobs_archer.png",
	"swarmling": "res://assets/mobs_swarmling.png",
	"wraith": "res://assets/mobs_wraith.png",
}
## Какие семейства печатаем для каждого биома (совпадает с OpenWorld.BESTIARY).
const BIOME_FAMILIES := {
	"snow": ["slime", "brute"],
	"desert": ["swarmling", "brute"],
	"steppe": ["slime", "brute", "archer"],
	"forest": ["slime", "swarmling", "brute"],
	"castle": ["brute", "archer"],
	"dungeon": ["wraith", "brute", "slime"],
}
## Таблицы замен рамп (тон сохраняется). CHAR/HP_RED/BONE/IRON/WOOD/PATH/UI_* —
## CONTROLS, вне таблиц. VIOLET указан везде, где семейство его несёт в биоме.
const SUBS := {
	"snow": {"GRASS": "CRYSTAL", "MOSS_GLOW": "CRYSTAL", "LEAF": "CRYSTAL",
			"WATER": "CRYSTAL", "ASH_GROUND": "STONE", "VIOLET": "CRYSTAL"},
	"desert": {"GRASS": "PATH", "MOSS_GLOW": "STONE_WARM", "LEAF": "PATH",
			"WATER": "STONE_WARM", "ASH_GROUND": "PATH", "VIOLET": "STONE_WARM"},
	"steppe": {"MOSS_GLOW": "GRASS", "LEAF": "GRASS", "WATER": "GRASS",
			"ASH_GROUND": "PATH", "VIOLET": "GRASS"},
	"forest": {"MOSS_GLOW": "LEAF", "WATER": "LEAF", "ASH_GROUND": "BARK",
			"VIOLET": "LEAF"},
	"castle": {"GRASS": "STONE", "MOSS_GLOW": "IRON", "LEAF": "CLOTH",
			"WATER": "IRON", "ASH_GROUND": "STONE", "VIOLET": "CLOTH"},
	"dungeon": {"GRASS": "VIOLET", "MOSS_GLOW": "VIOLET", "LEAF": "MOSS_GLOW",
			"WATER": "CRYSTAL", "ASH_GROUND": "CHAR"},
}

var _fails := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "check"
	var out_dir := ""
	if args.size() > 0:
		mode = String(args[0])
	if args.size() > 1:
		out_dir = String(args[1])
	if mode == "bake":
		_bake(out_dir)
	else:
		_check()
	print("[mob_variants] %s" % ("SELF-CHECK: PASS" if _fails == 0 else "SELF-CHECK: FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)

func _remap(img: Image, subs: Dictionary, idx: Dictionary) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var info = idx.get(P.key(c))
			if info == null:
				# чужой пиксель не должен появляться в исходниках (аудит пуст);
				# на всякий случай переносим как есть — проверка off его поймает
				out.set_pixel(x, y, c)
				continue
			var rn := String(info[0])
			var tone := int(info[1])
			if subs.has(rn):
				rn = String(subs[rn])
			out.set_pixel(x, y, P.RAMPS[rn][tone])
	return out

func _bake(out_dir: String) -> void:
	var idx := P.color_index()
	var manifest := {"status": "WIRED t3 (18.11) - скины локаций мира", "skins": {}}
	for biome in BIOME_FAMILIES:
		var subs: Dictionary = SUBS[biome]
		for fam in BIOME_FAMILIES[biome]:
			var src: String = FAMILY_ATLAS[fam]
			var img: Image = load(src).get_image()
			var w := img.get_width()
			var h := img.get_height()
			var out := _remap(img, subs, idx)
			var fname := "mobs_%s_%s_v1.png" % [fam, biome]
			var err := out.save_png(out_dir + "/" + fname)
			if err != OK:
				_fails += 1
				print("[FAIL] save %s err=%d" % [fname, err])
			if out.get_width() != w or out.get_height() != h:
				_fails += 1
				print("[FAIL] %s размер поплыл" % fname)
			var off := _off_count(out, idx)
			if off > 0:
				_fails += 1
				print("[FAIL] %s off пикселей: %d" % [fname, off])
			manifest["skins"][biome + "/" + fam] = {
				"file": fname, "src": src, "size": [w, h],
			}
			print("[bake] %-34s %dx%d off:%d" % [fname, w, h, off])
	var mf := FileAccess.open(out_dir + "/mobs_variants.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.flush()
	print("manifest mobs_variants.json written")

func _check() -> void:
	var idx := P.color_index()
	for biome in BIOME_FAMILIES:
		for fam in BIOME_FAMILIES[biome]:
			var src: String = FAMILY_ATLAS[fam]
			if not ResourceLoader.exists(src):
				_fails += 1
				print("[FAIL] источник %s не найден" % src)
				continue
			var img: Image = load(src).get_image()
			var off := _off_count(img, idx)
			if off > 0:
				_fails += 1
				print("[FAIL] источник %s: %d пикселей вне RAMPS" % [src, off])
			for rn in SUBS[biome]:
				if not P.RAMPS.has(String(SUBS[biome][rn])):
					_fails += 1
					print("[FAIL] %s: цель %s не в RAMPS" % [biome, SUBS[biome][rn]])

func _off_count(img: Image, idx: Dictionary) -> int:
	var off := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and not idx.has(P.key(c)):
				off += 1
	return off
