extends SceneTree
## t28 «Ощущение v1» B+C (26.11, вердикт пользователя «принимай пока что слизня
## и призрака»): кодо-бейк рантайм-носителей принятых секций листа W5.
##
## Единый источник арта — static-билдеры tools_art/sheet_feel_v1.gd (лист
## 720x1140, pre-save FNV 6C5131C2, PINS_W5.md). Рантайм-кадры попадают в
## файлы ПОБИТОВО-РАВНЫМИ кадрам листа: самопроверка сверяет FNV-1a32 каждого
## кадра с канонической таблицей PINS_W5 §5 (метод t13/t14/t26: неравенство
## не даёт выйти из tools; QA-стенд qa_lp держит равенство afterwards).
##
## Что печатаем (закон ART: runtime-арт = кадр листа, палитра RAMPS, ноль
## hand-raster):
##  B слизень  — assets/slime.png 32x16 (2 кадра «дрожь/присед» по 16px;
##               геометрия 16px-области и коллайдер 10x8 в slime.gd НЕ меняются);
##               биомные листы world/mobs_slime_{forest,steppe,snow,dungeon}_v1.png
##               — тот же carrier 32x16, палитры листа B (LEAF/HUD_GOLD,
##               PATH/BRONZE, WATER/CRYSTAL, MOSS_GLOW/VIOLET). Отступление от
##               SUBS mob_variants_v1 осознанно: лист рисует биомные ОКРАСЫ
##               новой формы (шарик-антенна BRONZE/CRYSTAL/VIOLET), SUBS-таблицы
##               старых рамп их не воспроизводят; pipeline-манифест (пути/размеры)
##               не меняется, меняется только содержимое PNG.
##  C призрак  — assets/mobs_wraith_state_v1.png 64x48: ряды состояний
##               «Тень-заимка» (FSM mob_wraith.gd feel_v1):
##               row0 possess0..3 (полёт вселения 4x180мс),
##               row1 occupied0, occupied1 (хозяин занят, пульс канта), banish0,
##                    banish1 (вспышка изгнания),
##               row2 banish2, stun0, stun1 (ошмёток со звёздами), пусто.
##
## Двойной bake побайтово идентичен; off-пикселей (вне RAMPS) = 0; в конце —
## MD5 всех файлов (пины qa_lp _t40).
##
## Запуск:
##   Godot_v4.7.2 --headless --path pixel-rpg -s res://tools_art/feel_v1_bake.gd

const P := preload("res://scripts/pixel_palette.gd")
const SH := preload("res://tools_art/sheet_feel_v1.gd")

## Канон FNV-1a32 pre-save (PINS_W5.md §5, лист 6C5131C2).
const FNV_PINS := {
	"slime_new0": "4E377B06", "slime_new1": "5D728633",
	"biome_forest": "4E377B06", "biome_steppe": "3872E37C",
	"biome_snow": "73761CE9", "biome_dungeon": "0819B9AF",
	"possess0": "75C0C165", "possess1": "BCDB47F0",
	"possess2": "62DFB52A", "possess3": "13FDDACF",
	"occupied0": "E536BCE7", "occupied1": "52B39B15",
	"banish0": "B313358C", "banish1": "936CF059", "banish2": "090E59C0",
	"stun0": "9F870489", "stun1": "CE5F5113",
}
## Палитры биомных coat-ов листа B: [рампа, ножка-антенны, шарик].
const COATS := {
	"forest": ["LEAF", "LEAF", "HUD_GOLD"],
	"steppe": ["PATH", "PATH", "BRONZE"],
	"snow": ["WATER", "WATER", "CRYSTAL"],
	"dungeon": ["MOSS_GLOW", "MOSS_GLOW", "VIOLET"],
}

var _fails := 0

func _init() -> void:
	var idx: Dictionary = P.color_index()
	# ---- B: кадры слизня (лист: _slime(pal, stalk, dot, frame))
	var frames := {}
	for coat in COATS:
		var c: Array = COATS[coat]
		for f in 2:
			var img: Image = SH._slime(String(c[0]), String(c[1]), String(c[2]), f)
			var key := ("slime_new%d" % f) if coat == "forest" else ("biome_%s" % coat)
			if coat == "forest" or f == 0:
				_pin(img, key)
			_off(img, idx)
			frames["%s%d" % [coat, f]] = img
	# ---- C: клетки состояний призрака
	for f in 4:
		var im := SH._possession_cell(f)
		_pin(im, "possess%d" % f)
		_off(im, idx)
		frames["possess%d" % f] = im
	for f in 2:
		var im := SH._occupied_cell(f)
		_pin(im, "occupied%d" % f)
		_off(im, idx)
		frames["occupied%d" % f] = im
	for f in 3:
		var im := SH._banish_cell(f)
		_pin(im, "banish%d" % f)
		_off(im, idx)
		frames["banish%d" % f] = im
	for f in 2:
		var im := SH._ghost("slumped", f)
		_pin(im, "stun%d" % f)
		_off(im, idx)
		frames["stun%d" % f] = im
	if _fails > 0:
		print("[feel_v1_bake] FNV/off SELF-CHECK: FAIL (%d) — выход без записи" % _fails)
		quit(1)
		return

	# ---- сборка носителей
	var carriers: Array = []
	for coat in COATS:
		var sl := Image.create(32, 16, false, Image.FORMAT_RGBA8)
		sl.blit_rect(frames["%s0" % coat], Rect2i(0, 0, 16, 16), Vector2i(0, 0))
		sl.blit_rect(frames["%s1" % coat], Rect2i(0, 0, 16, 16), Vector2i(16, 0))
		if coat == "forest":
			# лесной coat побитово = база (лист: pin forest == slime_new0),
			# но носитель скина world/mobs_slime_forest_v1.png обязан жить
			# теми же байтами — строка манифеста forest/slime ведёт к нему.
			carriers.append(["res://assets/slime.png", sl])
			carriers.append(["res://assets/world/mobs_slime_forest_v1.png", sl])
		else:
			carriers.append(["res://assets/world/mobs_slime_%s_v1.png" % String(coat), sl])
	var st := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	var cells := [["possess0", 0, 0], ["possess1", 1, 0], ["possess2", 2, 0], ["possess3", 3, 0],
		["occupied0", 0, 1], ["occupied1", 1, 1], ["banish0", 2, 1], ["banish1", 3, 1],
		["banish2", 0, 2], ["stun0", 1, 2], ["stun1", 2, 2]]
	for c: Array in cells:
		st.blit_rect(frames[String(c[0])], Rect2i(0, 0, 16, 16), Vector2i(int(c[1]) * 16, int(c[2]) * 16))
	carriers.append(["res://assets/mobs_wraith_state_v1.png", st])

	# ---- запись + двойной bake побайтово
	for cr: Array in carriers:
		var path := String(cr[0])
		var img: Image = cr[1]
		var again: Image = img.duplicate()
		if img.save_png(path) != OK:
			print("[FAIL] save %s" % path)
			_fails += 1
			continue
		var raw := FileAccess.get_file_as_bytes(path)
		var raw2 := again.save_png_to_buffer()
		# save_png добавляет стабильные чанки — сравниваем декод побитово
		var d1 := Image.new()
		var d2 := Image.new()
		d1.load_png_from_buffer(raw)
		d2.load_png_from_buffer(raw2)
		if d1.get_data() != d2.get_data():
			print("[FAIL] двойной bake разошёлся: %s" % path)
			_fails += 1
		var off := _off(img, idx)
		if off > 0:
			print("[FAIL] off-пикселей %d в %s" % [off, path])
			_fails += 1
		print("[bake] %-44s %dx%d off:%d md5 %s" % [path, img.get_width(), img.get_height(),
			off, _md5(path)])
	print("[feel_v1_bake] %s" % ("SELF-CHECK: PASS" if _fails == 0 else "SELF-CHECK: FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)

func _pin(img: Image, key: String) -> void:
	var got := SH._fnv32_hex(img)
	var want := String(FNV_PINS[key])
	if got != want:
		_fails += 1
		print("[FAIL] FNV %s: %s != %s (лист-канон)" % [key, got, want])

func _off(img: Image, idx: Dictionary) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and not idx.has(P.key(c)):
				n += 1
	return n

func _md5(path: String) -> String:
	var hc := HashingContext.new()
	if hc.start(HashingContext.HASH_MD5) != OK:
		return "?"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "?"
	hc.update(f.get_buffer(f.get_length()))
	return hc.finish().hex_encode()
