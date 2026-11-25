extends SceneTree
## t13 «Тлель-вепрь» (25.11, вердикт «оставь тлель-вепря» по листу Замена v1):
## кодо-бейк файла-носителя скина тяжёлого милишника assets/mobs_boar_v1.png —
## 64x32, два кадра 32px, дизайн-карта 16px с листа масштабирована x2
## (nearest, побитово). Geometry == старый лист brute.png 64x32: regions,
## TIERS.scale, якоря и T11-метрики не плывут. Легаси assets/brute.png в
## дереве остаётся (c23_golden/G12-носители), но НИГДЕ не отрисовывается —
## brute.gd грузит этот лист. Карты рядов дословно синхронны с
## sheet_replace_v1.gd (лист — история вердикта; этот файл — канон рантайма).
##
## Запуск:
##   Godot ... -s res://tools_art/boar_sprite_v1.gd -- bake res://assets/mobs_boar_v1.png
##   Godot ... -s res://tools_art/boar_sprite_v1.gd -- check [png]
## Выход 0: кадры непустые, все пиксели в RAMPS (off:0), double-bake идентичен.

const P := preload("res://scripts/pixel_palette.gd")

var _fails := 0
var _idx := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "check"
	var target := "res://assets/mobs_boar_v1.png"
	if args.size() > 0:
		mode = String(args[0])
	if args.size() > 1:
		target = String(args[1])
	_idx = P.color_index()
	if mode == "bake":
		_bake(target)
	else:
		_check(target)
	print("[boar] %s" % ("SELF-CHECK: PASS" if _fails == 0 else "SELF-CHECK: FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)

func _c(rn: String, t: int) -> Color:
	return P.RAMPS[rn][t]

func _rows(f: int) -> Array:
	# дословно Тлель-вепрь K0/K1 из sheet_replace_v1.gd (лист «Замена v1», 25.11)
	if f == 0:
		return [
			"................",
			"................",
			"................",
			"................",
			"......mm........",
			".....mmmm.......",
			"....ommmmo......",
			"..cCCCCCCCc.....",
			".cCCCCCCCCCCc...",
			".CCCCCCCCCCEC...",
			"CCCCCCCCCCCCCCB.",
			"DCCCCCCCCCCCCCC.",
			"..DD.CC..CC.DD..",
			"..DD.CC..CC.DD..",
			"................",
			"................",
		]
	return [
		"................",
		"................",
		"................",
		"................",
		".......mm.......",
		"......mmmm......",
		"....ommmmo......",
		"..cCCCCCCCc.....",
		".cCCCCCCCCCCc...",
		".CCCCCCCCCCEC...",
		"CCCCCCCCCCCCCCB.",
		"DCCCCCCCCCCCCCC.",
		".DD...CC..CC.DD.",
		"..D...CC..CC..D.",
		"................",
		"................",
	]

func _chmap() -> Dictionary:
	return {
		"m": _c("MOSS_GLOW", P.T_MID), "o": _c("MOSS_GLOW", P.T_LIGHT),
		"C": _c("CHAR", P.T_MID), "c": _c("CHAR", P.T_LIGHT), "D": _c("CHAR", P.T_DARK),
		"E": _c("HP_RED", P.T_MID), "B": _c("BONE", P.T_LIGHT),
	}

## Кадр 16px -> Image 16x16.
func _frame16(f: int) -> Image:
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var cm := _chmap()
	var rows: Array = _rows(f)
	for y in 16:
		var row := String(rows[y])
		if row.length() != 16:
			_fails += 1
			print("[FAIL] K%d r%d: длина %d" % [f, y, row.length()])
			continue
		for x in 16:
			var ch := String(row[x])
			if ch == ".":
				continue
			if not cm.has(ch):
				_fails += 1
				print("[FAIL] K%d: глиф '%s'" % [f, ch])
				continue
			im.set_pixel(x, y, cm[ch])
	return im

## Лист 64x32: кадры x2 nearest в ячейки 32px.
func _sheet() -> Image:
	var out := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for f in 2:
		var src := _frame16(f)
		for y in 16:
			for x in 16:
				var col := src.get_pixel(x, y)
				if col.a < 0.5:
					continue
				for dy in 2:
					for dx in 2:
						out.set_pixel(f * 32 + x * 2 + dx, y * 2 + dy, col)
	return out

func _bake(target: String) -> void:
	var a := _sheet()
	var b := _sheet()
	if a.save_png_to_buffer() != b.save_png_to_buffer():
		_fails += 1
		print("[FAIL] double-bake разошёлся")
	var off := _off(a)
	if off > 0:
		_fails += 1
		print("[FAIL] off пикселей: %d" % off)
	if _fails > 0:
		return
	var err := a.save_png(target)
	print("[bake] %s 64x32 err=%d off:%d hash:%s" % [target, err, off, _fnv32_hex(a)])
	if err != OK:
		_fails += 1

func _check(target: String) -> void:
	if not ResourceLoader.exists(target):
		_fails += 1
		print("[FAIL] %s нет в дереве" % target)
		return
	var img: Image = load(target).get_image()
	if img.get_width() != 64 or img.get_height() != 32:
		_fails += 1
		print("[FAIL] %s: %dx%d (ждали 64x32)" % [target, img.get_width(), img.get_height()])
	var off := _off(img)
	if off > 0:
		_fails += 1
		print("[FAIL] %s: off=%d" % [target, off])
	for f in 2:
		var n := 0
		for y in 32:
			for x in range(f * 32, f * 32 + 32):
				if img.get_pixel(x, y).a > 0.5:
					n += 1
		if n < 64:
			_fails += 1
			print("[FAIL] кадр K%d пустоват: %d px" % [f, n])
		else:
			print("[ok] K%d px:%d hash:%s" % [f, n, _fnv32_hex_frame(img, f)])

func _fnv32_hex_frame(img: Image, f: int) -> String:
	var fr := img.get_region(Rect2i(f * 32, 0, 32, 32))
	return _fnv32_hex(fr)

func _off(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a > 0.5 and not _idx.has(P.key(col)):
				n += 1
	return n

func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h
