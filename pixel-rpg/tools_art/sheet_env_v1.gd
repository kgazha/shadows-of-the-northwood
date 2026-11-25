extends SceneTree
## Инструмент вердикт-листа «Среда v1» (волна «Мир v2: наполнение», W4, 24.11).
##
## ЛИСТ НА ВЕРДИКТ: интеграция — ТОЛЬКО после «да» пользователя (закон ART).
## Игра сегодня: легаси anim_tiles.png (A_WATER 4k@350ms, A_TORCH 2k@250ms,
## A_MOSS 2k) + Light2D/PointLight2D. Лист предлагает замену: кодо-циклы
## PixelPalette-чистыми спрайтами, световой пульс факела — МОДУЛЯЦИЕЙ ЦВЕТА
## внутри рампы (без shader-освещения, gl_compatibility).
##
## Циклы: ВОДА — озеро (WATER) 4 кадра + зимняя variant (CRYSTAL-лёд,
## подлёдная тьма WATER DARK, льдинки) 4 кадра; ФАКЕЛ — пламя 4 кадра,
## пульс заложен в тон кадра (норма/подъём/спуск), day/night; МОХ — дыхание
## 3 кадра, две яркости, три зоны (лес LEAF / подземелье MOSS_GLOW /
## замок GRASS-лишайник). Каждый цикл — zoom1 + zoom3 + палитрные пины.
##
## Кандидаты прокрутки (оба показаны кадром, решение — в листе):
##   A — TileMap тайл-варианты (анимация полями атласа): только глобальный
##       fps, синхронно, требует перепина утверждённых атласов;
##   B — отдельный таймер-скинер int(t/T)%N + фаза hash(x,y) (паттерн
##       atmosphere/mob-скинеров). ЛИСТ РЕКОМЕНДУЕТ B.
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_env_v1.gd -- <out.png>
## Выход 0 — все самопроверки + STRICT-скан листа PASS (скан ДО сохранения:
## при провале файл не выкладывается), иначе 1.

const P := preload("res://scripts/pixel_palette.gd")

const SEAM_RATIO_MAX := 2.4

# тайминги кадра (мс) — печатаются для PINS_W4.md
const T_WATER_MS := 300        # озеро: 4 x 300 = 1200 мс
const T_ICE_MS := 400          # зимняя variant: 4 x 400 = 1600 мс
const T_TORCH_MS := 250        # факел: 4 x 250 = 1000 мс (пульс встроен в кадр)
const T_MOSS_MS := 900         # мох: 3 x 900 = 2700 мс

var _fails := 0
var _idx := {}
var _allowed := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var target := "res://tools_art/sheet_env_v1.png"
	if args.size() > 0:
		target = String(args[0])
	_idx = P.color_index()
	_allowed = _idx.duplicate()
	for k in P.SHEET:
		_allowed[P.key(P.SHEET[k])] = ["SHEET", -1]
	_sheet(target)
	if _fails > 0:
		print("SELF-CHECK: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("SELF-CHECK: PASS")
		quit(0)

func _c(rn: String, t: int) -> Color:
	return P.RAMPS[rn][t]

# ============================================================ контент: ВОДА

## Озеро (лес/деревня/оазис) — 4 кадра 16x16, непрозрачные, бесшовные по обеим
## осям: две синусные волны DARK (период 16, наклон <=1 px/колонку => шов
## равен соседству внутри тайла) ползут на 4 px/кадр; пена — LIGHT 1 px на
## подъёме (СЗ-грань); блик WATER LIGHT 2 px в СЗ-четверти на кадрах 1 и 3.
## Сдвиг 4 по периоду 16 => все 4 кадра различны, цикл замкнут.
func _wave_y(phase: int, base: int, amp: float) -> int:
	return base + int(round(amp + amp * sin(TAU * float(phase) / 16.0)))

func _water_summer(f: int) -> Image:
	var img := _im(16, 16)
	img.fill(_c("WATER", P.T_MID))
	var w1: Array = []
	var w2: Array = []
	for x in 16:
		w1.append(_wave_y(x + 4 * f, 4, 2.5))
		w2.append(_wave_y(x + 4 * f + 8, 11, 1.5))
	for x in 16:
		_px(img, x, w1[x], _c("WATER", P.T_DARK))
		if w1[x] < w1[(x + 15) % 16]:
			_px(img, x, w1[x] - 1, _c("WATER", P.T_LIGHT))
		_px(img, x, w2[x], _c("WATER", P.T_DARK))
		if w2[x] < w2[(x + 15) % 16]:
			_px(img, x, w2[x] - 1, _c("WATER", P.T_LIGHT))
	if f == 1:
		_px(img, 2, 2, _c("WATER", P.T_LIGHT))
		_px(img, 3, 2, _c("WATER", P.T_LIGHT))
	if f == 3:
		_px(img, 5, 2, _c("WATER", P.T_LIGHT))
		_px(img, 6, 2, _c("WATER", P.T_LIGHT))
	return img

## Зимняя variant (снежное озеро): лёд CRYSTAL MID, трещины WATER OUTLINE,
## подлёдная тьма — WATER DARK «окно» ползёт на 1 px/кадр, льдинки CRYSTAL
## LIGHT дрейфуют на 3 px/кадр, WATER LIGHT — подлёдный отблеск на кадрах
## 0 и 2. Кромки тайла чистые (узор внутренний) => шов = 0.
func _water_winter(f: int) -> Image:
	var img := _im(16, 16)
	img.fill(_c("CRYSTAL", P.T_MID))
	for pt in [[3, 3], [4, 4], [5, 4], [6, 5], [7, 6], [8, 6], [9, 7], [10, 8], [11, 8], [11, 9], [6, 7], [6, 8]]:
		_px(img, pt[0], pt[1], _c("WATER", P.T_OUTLINE))
	_px(img, 7, 5, _c("CRYSTAL", P.T_LIGHT))
	_px(img, 9, 8, _c("CRYSTAL", P.T_LIGHT))
	# подлёдная тьма
	_px(img, 4 + f, 11, _c("WATER", P.T_DARK))
	_px(img, 5 + f, 11, _c("WATER", P.T_DARK))
	# льдинки
	_px(img, 2 + 3 * f, 5, _c("CRYSTAL", P.T_LIGHT))
	_px(img, 3 + 3 * f, 5, _c("CRYSTAL", P.T_LIGHT))
	_px(img, 2 + 3 * f, 4, _c("WATER", P.T_LIGHT))
	if f == 0:
		_px(img, 12, 2, _c("WATER", P.T_LIGHT))
	if f == 2:
		_px(img, 2, 12, _c("WATER", P.T_LIGHT))
	return img

# ============================================================ контент: ФАКЕЛ

## Силуэты пламени (x, y, тон). Тон — символ рампы FIRE; H = FLAT FIRE_HOT.
## Пульс заложен в выбор тона кадра: f0 норма, f1 подъём (+1 тон), f2 норма,
## f3 спуск (-1 тон) — все тона остаются в RAMPS (это и есть «модуляция
## цвета» без shader-освещения). День: без подъёма/спуска и без H-ядра.
const FLAME := [
	[[4, 0, "L"], [3, 1, "L"], [4, 1, "M"], [5, 1, "M"], [2, 2, "L"], [3, 2, "M"], [4, 2, "M"], [5, 2, "D"], [6, 2, "D"],
	 [2, 3, "L"], [3, 3, "M"], [4, 3, "M"], [5, 3, "D"], [6, 3, "D"], [3, 4, "M"], [4, 4, "H"], [5, 4, "D"], [6, 4, "D"],
	 [3, 5, "M"], [4, 5, "M"], [5, 5, "D"], [3, 6, "O"], [4, 6, "O"], [5, 6, "O"], [4, 7, "O"], [5, 7, "O"]],
	[[3, 1, "L"], [2, 2, "L"], [3, 2, "M"], [4, 2, "M"], [5, 2, "D"],
	 [1, 3, "L"], [2, 3, "M"], [3, 3, "M"], [4, 3, "D"], [5, 3, "D"],
	 [1, 4, "L"], [2, 4, "M"], [3, 4, "M"], [4, 4, "D"],
	 [2, 5, "M"], [3, 5, "M"], [4, 5, "D"], [2, 6, "O"], [3, 6, "O"], [4, 6, "O"], [3, 7, "O"], [4, 7, "O"]],
	[[4, 0, "L"], [3, 1, "L"], [4, 1, "M"], [5, 1, "M"], [2, 2, "L"], [3, 2, "M"], [4, 2, "M"], [5, 2, "D"], [6, 2, "D"],
	 [1, 3, "L"], [2, 3, "M"], [3, 3, "M"], [4, 3, "M"], [5, 3, "D"], [6, 3, "D"],
	 [2, 4, "M"], [3, 4, "H"], [4, 4, "H"], [5, 4, "D"],
	 [3, 5, "M"], [4, 5, "M"], [5, 5, "D"], [3, 6, "O"], [4, 6, "O"], [5, 6, "O"], [4, 7, "O"], [5, 7, "O"]],
	[[5, 1, "L"], [4, 2, "L"], [5, 2, "M"], [6, 2, "M"],
	 [4, 3, "L"], [5, 3, "M"], [6, 3, "M"], [7, 3, "D"],
	 [4, 4, "M"], [5, 4, "M"], [6, 4, "M"], [7, 4, "D"],
	 [4, 5, "M"], [5, 5, "M"], [6, 5, "D"], [4, 6, "O"], [5, 6, "O"], [6, 6, "O"], [4, 7, "O"], [5, 7, "O"]],
]

## Тона кадра пульса: норм/подъём/спуск — сдвиги ВНУТРИ рампы FIRE (H — ядро).
func _pulse_tone(sym: String, mode: int) -> String:
	# mode: 0 норма, 1 подъём, -1 спуск; возвращает символ или "" (погасить H)
	if mode == 0:
		return sym
	if mode > 0:
		if sym == "H":
			return "H"
		if sym == "L":
			return "L"
		if sym == "M":
			return "L"
		if sym == "D":
			return "M"
		if sym == "O":
			return "D"
	# спуск
	if sym == "H":
		return "M"
	if sym == "L":
		return "M"
	if sym == "M":
		return "D"
	if sym == "D":
		return "O"
	return "O"

## Факел 10x15 (ночь: 4 кадра с пульсом; день: пульс и H-ядро выключены).
func _torch(f: int, night: bool) -> Image:
	var img := _im(10, 15)
	# ножка WOOD (СЗ: LIGHT левый столбец сверху, DARK правый бок), низ — OUTLINE
	_px(img, 4, 9, _c("WOOD", P.T_LIGHT))
	_px(img, 5, 9, _c("WOOD", P.T_MID))
	_px(img, 4, 10, _c("WOOD", P.T_LIGHT))
	_px(img, 5, 10, _c("WOOD", P.T_DARK))
	_px(img, 4, 11, _c("WOOD", P.T_MID))
	_px(img, 5, 11, _c("WOOD", P.T_DARK))
	_px(img, 4, 12, _c("WOOD", P.T_MID))
	_px(img, 5, 12, _c("WOOD", P.T_DARK))
	_px(img, 4, 13, _c("WOOD", P.T_MID))
	_px(img, 5, 13, _c("WOOD", P.T_DARK))
	_px(img, 4, 14, _c("WOOD", P.T_OUTLINE))
	_px(img, 5, 14, _c("WOOD", P.T_OUTLINE))
	# обжим IRON (LIGHT слева)
	_px(img, 3, 8, _c("IRON", P.T_LIGHT))
	_px(img, 4, 8, _c("IRON", P.T_MID))
	_px(img, 5, 8, _c("IRON", P.T_MID))
	_px(img, 6, 8, _c("IRON", P.T_DARK))
	# пламя: пульс встроен (ночь), день — плоский без ядра
	var mode := 0
	if night:
		mode = [0, 1, 0, -1][f]
	for pt in FLAME[f]:
		var sym := String(pt[2])
		sym = _pulse_tone(sym, mode)
		if sym == "":
			continue
		if not night and sym == "H":
			sym = "M"
		var col: Color
		if sym == "H":
			col = P.FLATS["FIRE_HOT"]
		elif sym == "L":
			col = _c("FIRE", P.T_LIGHT)
		elif sym == "M":
			col = _c("FIRE", P.T_MID)
		elif sym == "D":
			col = _c("FIRE", P.T_DARK)
		else:
			col = _c("FIRE", P.T_OUTLINE)
		_px(img, int(pt[0]), int(pt[1]), col)
	return img

# ============================================================ контент: МОХ

## Пятно мха/лишайника 16x16 — оверлей на камень. Дыхание 3 кадра: f0 база,
## f1 мерцание (+LIGHT), f2 выдох (-LIGHT / +DARK). Две яркости.
## Силуэт, кромка DARK справа/снизу, низ — OUTLINE.
const MOSS_ROWS := {5: [5, 9], 6: [3, 11], 7: [2, 13], 8: [1, 14], 9: [1, 14], 10: [2, 12], 11: [2, 11], 12: [3, 10]}
const MOSS_D := [[6, 10], [6, 11], [7, 11], [7, 12], [7, 13], [8, 12], [8, 13], [8, 14],
	[9, 12], [9, 13], [9, 14], [10, 10], [10, 11], [10, 12], [11, 8], [11, 9], [11, 10], [11, 11]]
const MOSS_L_BRIGHT := [[5, 5], [7, 5], [4, 6], [3, 7], [6, 7], [5, 8]]
const MOSS_L_DIM := [[5, 5], [7, 5], [4, 6]]
const MOSS_D_DIM_EXTRA := [[8, 10], [9, 10], [4, 9]]

func _moss(ramp: String, bright: bool, f: int) -> Image:
	var img := _im(16, 16)
	var dset := {}
	for p in MOSS_D:
		dset["%d,%d" % [p[0], p[1]]] = true
	if not bright:
		for p in MOSS_D_DIM_EXTRA:
			dset["%d,%d" % [p[0], p[1]]] = true
	var lset := {}
	var base: Array = MOSS_L_BRIGHT if bright else MOSS_L_DIM
	for p in base:
		lset["%d,%d" % [p[0], p[1]]] = true
	if f == 1:
		lset["7,8"] = true
	elif f == 2:
		if bright:
			lset.erase("6,7")
			dset["10,9"] = true
		else:
			lset["9,6"] = true
	for ry in MOSS_ROWS:
		var y := int(ry)
		var span: Array = MOSS_ROWS[ry]
		for x in range(span[0], span[1] + 1):
			var k := "%d,%d" % [x, y]
			if y == 12:
				_px(img, x, y, _c(ramp, P.T_OUTLINE))
			elif lset.has(k):
				_px(img, x, y, _c(ramp, P.T_LIGHT))
			elif dset.has(k):
				_px(img, x, y, _c(ramp, P.T_DARK))
			else:
				_px(img, x, y, _c(ramp, P.T_MID))
	return img

# ============================================================ самопроверки

## Тайл (вода): непрозрачен, off:0, шов по обеим осям <= SEAM_RATIO_MAX.
func _check_tile(img: Image, nm: String) -> void:
	var off := 0
	var mask := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a < 1.0:
				mask += 1
				if col.a < 0.5:
					off += 1
				continue
			if not _idx.has(P.key(col)):
				off += 1
	if off > 0 or mask > 0:
		_fails += 1
		print("[FAIL] tile %s off=%d mask=%d" % [nm, off, mask])
	var rx := _seam_ratio(img, true)
	var ry := _seam_ratio(img, false)
	var mark := ""
	if rx > SEAM_RATIO_MAX or ry > SEAM_RATIO_MAX:
		_fails += 1
		mark = " [FAIL SEAM]"
	print("[tile] %-12s 16x16 off:0 mask:0 seamH=%.2f seamV=%.2f hash:%s%s" % [nm, rx, ry, _fnv32_hex(img), mark])

## Спрайт цикла (факел/мох): off:0 mask:0; нижний ряд — OUTLINE-тона;
## СЗ-подсветка — LIGHT в верхней половине (для цикла считаем сумму кадров:
## самоизлучающий/дышащий объект светит не каждым кадром).
func _check_sprite_set(items: Array, nm: String) -> void:
	var off := 0
	var mask := 0
	var lt_top := 0
	var hmax := 0
	for it in items:
		var img: Image = it["img"]
		hmax = maxi(hmax, img.get_height())
		for y in img.get_height():
			for x in img.get_width():
				var col := img.get_pixel(x, y)
				if col.a > 0.0 and col.a < 1.0:
					mask += 1
				if col.a < 0.5:
					continue
				if not _idx.has(P.key(col)):
					off += 1
					continue
				var info = _idx.get(P.key(col))
				if int(info[1]) == P.T_LIGHT and y < img.get_height() / 2.0:
					lt_top += 1
		var last := -1
		for y in range(img.get_height() - 1, -1, -1):
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					last = y
					break
			if last >= 0:
				break
		for x in img.get_width():
			if img.get_pixel(x, last).a > 0.5:
				var info = _idx.get(P.key(img.get_pixel(x, last)))
				if info == null or int(info[1]) != P.T_OUTLINE:
					_fails += 1
					print("[FAIL] %s f%d: нижний ряд не OUTLINE" % [nm, items.find(it)])
	if off > 0:
		_fails += 1
		print("[FAIL] %s off=%d" % [nm, off])
	if mask > 0:
		_fails += 1
		print("[FAIL] %s mask=%d" % [nm, mask])
	if lt_top < 3:
		_fails += 1
		print("[FAIL] %s: нет СЗ-подсветки (LIGHT сверху: %d)" % [nm, lt_top])
	var hashes: Array = []
	for it in items:
		hashes.append(_fnv32_hex(it["img"]))
	print("[cycle] %-22s frames:%2d off:0 mask:0 light:%d hash:%s" % [nm, items.size(), lt_top, " ".join(hashes)])

func _seam_ratio(img: Image, horiz: bool) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var seam := 0.0
	var field := 0.0
	if horiz:
		for y in h:
			seam += _db(img, w - 1, y, 0, y)
		seam /= float(h)
		for y in h:
			for x in range(w - 1):
				field += _db(img, x, y, x + 1, y)
		field /= float(h * (w - 1))
	else:
		for x in w:
			seam += _db(img, x, h - 1, x, 0)
		seam /= float(w)
		for y in range(h - 1):
			for x in w:
				field += _db(img, x, y, x, y + 1)
		field /= float((h - 1) * w)
	return seam / maxf(field, 0.001)

func _db(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var a := img.get_pixel(x0, y0)
	var b := img.get_pixel(x1, y1)
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0

## STRICT-скан листа ПЕРЕД выкладкой: каждый пиксель — RAMPS/FLATS/SHEET,
## полупрозрачных нет. Провал => файл не сохраняется.
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
	var ok := off == 0 and mask == 0
	print("[strict] sheet-wide %dx%d off=%d mask=%d %s" % [img.get_width(), img.get_height(), off, mask, "PASS" if ok else "FAIL"])
	if not ok:
		_fails += 1
	return ok

## FNV-1a 32 по PNG-байтам (тот же рецепт, что cave_paint.img_hash).
func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

# ============================================================ лист

func _sheet(out_path: String) -> void:
	var hero: Image = load("res://assets/class_warrior.png").get_image().get_region(Rect2i(0, 0, 16, 16))
	var pad := 6
	var gap := 12
	var x0 := 10
	var W := 660
	var sheet := _im(W, 2400)
	sheet.fill(P.SHEET["BG"])

	# --- вода: контент + проверки
	var ws: Array = []
	var ww: Array = []
	for f in 4:
		ws.append({"name": "WTR%d" % f, "img": _water_summer(f)})
		ww.append({"name": "ICE%d" % f, "img": _water_winter(f)})
	for it in ws:
		_check_tile(it["img"], String(it["name"]))
	for it in ww:
		_check_tile(it["img"], String(it["name"]))
	# --- факел: контент + проверки
	var tn: Array = []
	var td: Array = []
	for f in 4:
		tn.append({"name": "TRN%d" % f, "img": _torch(f, true)})
		td.append({"name": "TRD%d" % f, "img": _torch(f, false)})
	_check_sprite_set(tn, "TORCH NIGHT 4F")
	_check_sprite_set(td, "TORCH DAY 4F")
	# --- мох: контент + проверки
	var moss_zones := [["FOREST", "LEAF"], ["DUNGEON", "MOSS_GLOW"], ["CASTLE", "GRASS"]]
	var moss_sets := {}
	for z in moss_zones:
		for br in [["BRIGHT", true], ["DIM", false]]:
			var key := "%s %s" % [z[0], br[0]]
			var arr: Array = []
			for f in 3:
				arr.append({"name": "M%d" % f, "img": _moss(String(z[1]), bool(br[1]), f)})
			moss_sets[key] = arr
			_check_sprite_set(arr, key)

	_text(sheet, 10, 8, "ENV V1 - WATER / TORCH / MOSS CODE CYCLES - VERDICT SHEET - NOT INTEGRATED - W4 24.11", 2, P.SHEET["TEXT"])
	_text(sheet, 10, 24, "HERO 16PX ZOOM1 / PALETTE DELTA = EMPTY / NO SHADER LIGHT - COLOR PULSE ONLY / GL_COMPATIBILITY", 1, P.SHEET["LINE"])
	var y := 42

	# ============ секция 1: ВОДА ============
	_text(sheet, x0, y, "WATER - LAKE AND RIVER - 4F X 300MS = 1200MS LOOP - TILEABLE BOTH AXES", 1, P.SHEET["TEXT"])
	y += 12
	y = _cycle_row(sheet, ws, 3, x0, y, 16, pad, gap, hero)
	# zoom1 рядом уже в _cycle_row; пины
	_pins(sheet, x0 + 4, [["WATER", [0, 1, 2, 3]]], y + 4)
	y += 34
	_text(sheet, x0, y, "WATER WINTER - SNOW LAKE - 4F X 400MS = 1600MS - ICE CRYSTAL / UNDER-ICE DARK WATER / DRIFTING FLOES", 1, P.SHEET["TEXT"])
	y += 12
	y = _cycle_row(sheet, ww, 3, x0, y, 16, pad, gap, hero)
	_pins(sheet, x0 + 4, [["CRYSTAL", [0, 1, 2, 3]], ["WATER", [0, 2, 3]]], y + 4)
	y += 34

	# ============ секция 2: ФАКЕЛ ============
	_text(sheet, x0, y, "TORCH NIGHT - 4F X 250MS = 1000MS - PULSE EMBEDDED IN FRAME TONE - NO POINTLIGHT NO SHADER", 1, P.SHEET["TEXT"])
	y += 12
	y = _cycle_row(sheet, tn, 3, x0, y, 15, pad, gap, hero)
	_pins(sheet, x0 + 4, [["FIRE", [0, 1, 2, 3]], ["WOOD", [0, 1, 2, 3]], ["IRON", [0, 1, 2, 3]], ["FIREHOT", [-1]]], y + 4)
	y += 34
	_text(sheet, x0, y, "TORCH DAY - SAME SILHOUETTES - NO HOT CORE - NO PULSE STEPS", 1, P.SHEET["TEXT"])
	y += 12
	y = _cycle_row(sheet, td, 3, x0, y, 15, pad, gap, hero)
	y += 12
	_text(sheet, x0, y, "PULSE - FRAME TONE SHIFT INSIDE RAMP - NORM - LIFT -1 TONE UP - NORM - FALL -1 TONE DOWN - ALL PALETTE", 1, P.SHEET["LINE"])
	_pulse_legend(sheet, x0, y + 10)
	y += 46

	# ============ секция 3: МОХ ============
	for z in moss_zones:
		for br in [["BRIGHT", "1 BRIGHTNESS LIGHT AND MID DOMINANT"], ["DIM", "2 BRIGHTNESS DARK CLOTHED - 3 GLOW SPECKLES HOLD"]]:
			var key := "%s %s" % [z[0], String(br[0]).to_lower().to_upper()]
			_text(sheet, x0, y, "MOSS %s - %s RAMP - 3F X 900MS = 2700MS BREATH - %s" % [z[0], z[1], br[1]], 1, P.SHEET["TEXT"])
			y += 12
			y = _cycle_row(sheet, moss_sets[key], 3, x0, y, 16, pad, gap, hero if key == "FOREST BRIGHT" else null)
			_pins(sheet, x0 + 4, [[String(z[1]), [0, 1, 2, 3]]], y + 4)
			y += 34

	# ============ кандидаты прокрутки ============
	_text(sheet, x0, y, "SCROLL CANDIDATES - BOTH SHOWN WITH FRAMES - SHEET DECISION = B", 1, P.SHEET["TEXT"])
	y += 12
	var ca: Array = []
	var cb: Array = []
	for f in 4:
		ca.append({"name": "A%d" % f, "img": _water_summer(f)})
	for order_i in [0, 2, 1, 3]:
		cb.append({"name": "B%d" % order_i, "img": _water_summer(order_i)})
	_text(sheet, x0, y, "A - TILEMAP TILE VARIANTS - ANIM FIELDS ON ATLAS - GLOBAL FPS - SYNC ONLY - NEEDS REBAKE OF PINNED ATLASES", 1, P.SHEET["LINE"])
	_draw_row(sheet, ca, 2, x0 + 6, y + 10, 16, pad, gap)
	var xA := x0 + 6 + _row_w(ca, 2, pad, gap) + 16
	_text(sheet, xA, y, "B - TIMER-SKINNER - INT T/T % 4 - PHASE HASH X Y PER CELL - PATTERNS ATMOSPHERE AND MOB VARIANTS", 1, P.SHEET["LINE"])
	_draw_row(sheet, cb, 2, xA, y + 10, 16, pad, gap)
	y += 10 + 16 * 2 + pad * 2 + 18
	_text(sheet, x0, y, "WHY B - WATER ALREADY RUNS A SKINNER IN VILLAGE - QA PINS HOLD - PER-CELL PHASE KILLS THE STROBE -", 1, P.SHEET["LINE"])
	_text(sheet, x0, y + 9, "TORCH PULSE NEEDS PER-INSTANCE MODULATE - TILEMAP ANIM CANNOT MODULATE PER CELL WITHOUT SHADER", 1, P.SHEET["LINE"])
	y += 28

	# ============ честность + легенда ============
	_text(sheet, x0, y, "HONESTY - IN GAME TODAY - LEGACY ANIM TILES WATER 4F 350MS / TORCH 2F 250MS / MOSS 2F + LIGHT2D - THIS SHEET", 1, P.SHEET["TEXT"])
	_text(sheet, x0, y + 9, "IS A REPLACEMENT CANDIDATE - INTEGRATION ONLY AFTER USER VERDICT - LAW ART", 1, P.SHEET["LINE"])
	y += 26
	_text(sheet, x0, y, "FAMILIES - PIXELPALETTE ONLY - DELTA EMPTY", 1, P.SHEET["TEXT"])
	y += 11
	_pins(sheet, x0, [["WATER", [0, 1, 2, 3]], ["CRYSTAL", [0, 1, 2, 3]], ["FIRE", [0, 1, 2, 3]], ["FIREHOT", [-1]],
			["WOOD", [0, 1, 2, 3]], ["IRON", [0, 1, 2, 3]], ["LEAF", [0, 1, 2, 3]], ["MOSSGLOW", [0, 1, 2, 3]], ["GRASS", [0, 1, 2, 3]]], y)
	y += 24

	var final_h := y + 8
	var out_img: Image = sheet
	if final_h < sheet.get_height():
		out_img = sheet.get_region(Rect2i(0, 0, sheet.get_width(), final_h))
	# STRICT перед выкладкой
	if not _strict_scan(out_img):
		print("[strict] SHEET NOT SAVED - fix palette purity first")
		return
	var err := out_img.save_png(out_path)
	print("sheet saved: %s (%dx%d) err=%d" % [out_path, out_img.get_width(), out_img.get_height(), err])
	print("[hash] sheet pre-save %s" % _fnv32_hex(out_img))
	print("[timing] WATER %d x4 = %d | WINTER %d x4 = %d | TORCH %d x4 = %d | MOSS %d x3 = %d" % [
			T_WATER_MS, T_WATER_MS * 4, T_ICE_MS, T_ICE_MS * 4, T_TORCH_MS, T_TORCH_MS * 4, T_MOSS_MS, T_MOSS_MS * 3])

# ============================================================ отрисовка листа

## Ряд цикла: zoom3 слева (подписи кадров) + zoom1 справа (нативный экран).
func _cycle_row(sheet: Image, items: Array, sc: int, x0: int, y0: int, maxh: int, pad: int, gap: int, hero: Image) -> int:
	var roww := _draw_row(sheet, items, sc, x0, y0, maxh, pad, gap)
	var x := x0 + roww + 24
	_text(sheet, x, y0 + (maxh * sc + pad * 2) - 24, "ZOOM1", 1, P.SHEET["LINE"])
	_draw_row(sheet, items, 1, x, y0 + (maxh * sc + pad * 2) / 2 - (maxh + pad * 2) / 2, maxh, pad, gap)
	if hero != null:
		var hx := x + _row_w(items, 1, pad, gap) + 10
		_blit(sheet, hero, hx, y0 + (maxh * sc + pad * 2) - pad - 16, 1)
		_text(sheet, hx, y0 + (maxh * sc + pad * 2) + 3, "HERO16", 1, P.SHEET["LINE"])
	return y0 + maxh * sc + pad * 2 + 18

## Палитрные пины: свотчи тонов + подпись имени рампы.
func _pins(sheet: Image, x0: int, spec: Array, y0: int) -> void:
	var x := x0
	for e in spec:
		var rn := String(e[0])
		var tones: Array = e[1]
		var sx := x
		for t in tones:
			# лейбл без подчёркивания (шрифт листа): MOSSGLOW -> RAMPS["MOSS_GLOW"]
			var lookup := "MOSS_GLOW" if rn == "MOSSGLOW" else rn
			var col: Color = P.FLATS["FIRE_HOT"] if rn == "FIREHOT" else P.RAMPS[lookup][int(t)]
			_fill(sheet, x, y0, x + 6, y0 + 7, col)
			_rect(sheet, x, y0, x + 6, y0 + 7, P.SHEET["LINE"])
			x += 8
		_text(sheet, sx, y0 + 9, rn, 1, P.SHEET["LINE"])
		x += 26

func _pulse_legend(sheet: Image, x0: int, y0: int) -> void:
	var states := [["NORM", 0], ["LIFT", 1], ["NORM", 0], ["FALL", -1]]
	var x := x0
	for st in states:
		for tone in ["L", "M", "D"]:
			var sym := _pulse_tone(String(tone), int(st[1]))
			var col: Color
			match sym:
				"H":
					col = P.FLATS["FIRE_HOT"]
				"L":
					col = _c("FIRE", P.T_LIGHT)
				"M":
					col = _c("FIRE", P.T_MID)
				_:
					col = _c("FIRE", P.T_DARK)
			_fill(sheet, x, y0, x + 5, y0 + 7, col)
			_rect(sheet, x, y0, x + 5, y0 + 7, P.SHEET["LINE"])
			x += 7
		_text(sheet, x - 22, y0 + 9, String(st[0]), 1, P.SHEET["LINE"])
		x += 12

# ============================================================ примитивы (эталон sheet_world)

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

func _fill(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
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

## Ряд кадров: панель + кадр + подпись; возвращает ширину ряда.
func _draw_row(sheet: Image, items: Array, sc: int, x0: int, y0: int, maxh: int, pad: int, gap: int) -> int:
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
	return x - x0 - gap

func _row_w(items: Array, sc: int, pad: int, gap: int) -> int:
	var wsum := 0
	for s in items:
		wsum += (s["img"] as Image).get_width() * sc + pad * 2 + gap
	return wsum
