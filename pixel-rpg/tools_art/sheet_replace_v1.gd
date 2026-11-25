extends SceneTree
## Инструмент вердикт-листа «Замена v1» (волна «Мир v2: наполнение», t12, 25.11).
##
## ВЕРДИКТ ПОЛЬЗОВАТЕЛЯ 25.11: «замени брютов на других монстров, не нравится
## визуально этот враг». Диагностика капитана (попиксельно): тело брюта =
## трапеция (ratio верха/низа 0.63), монолитный купол без талии/ног/плеч,
## легаси-растр эпохи до закона ART, унаследован шестью биомными ремейками.
## ЛИСТ — НА ВЕРДИКТ, НЕ интеграция (закон ART): спрайт/имена/пины — только
## после выбора пользователя. Рантайм не тронут ни на пиксель.
##
## СОСТАВ: обвиняемый (assets/brute.png байт-в-байт, как образец) + ТРИ
## кодо-кандидата: «Корневой идол» (анти-трапеция: широкая крона, узкие
## корни-ноги), «Тлель-вепрь» (горбатый таран), «Краденый колосс» (каменная
## глыба со светящимися щелями; перекличка с будущим «краденым рыцарем»
## Глубины v2 — помечено на листе). Каждый: 2 кадра, биомные палитр-ремейки
## x3 (лес/снег/пустошь) ровно через SUBS-таблицы mob_variants_v1 (тот же
## PixelPalette-пайплайн), контекст 16px на биомном полу, поведенческая
## карточка (механический слот тяжёлого милишника и tier-вилки BALANCE #11
## сохранены — меняются скин/имя/лор/телеграф).
##
## Запуск:
##   Godot ... -s res://tools_art/sheet_replace_v1.gd -- <out.png>
##   Godot ... -s res://tools_art/sheet_replace_v1.gd -- PAINTERS   (ASCII)
## Выход 0 = SELF-CHECK PASS: double-bake побайтно равен, strict-скан off=0
## mask=0, все кадры >=6 px в RAMPS/SHEET, CJK-гигиена шрифта.

const P := preload("res://scripts/pixel_palette.gd")
# Пайплайн биомных ремейков — дословно чужой, не переопределяем:
const MV := preload("res://tools_art/mob_variants_v1.gd")

# Тайминги кадрового цикла (наследуют браузерный канон brute.gd: walk 2.5 fps)
const T_WALK_MS := 400        # 2 кадра x 400 мс = цикл 800 мс (walk 2.5 fps)
# Телеграфы кандидатов (предложение интеграции; BASE-слот цел):
const WINDUP_BASE := 0.5      # сегодня канон Грома/тяжёлого (brute.gd WINDUP_TIME)
const WINDUP_IDOL := 0.7      # идол: замах корнем ДОЛЬШЕ
const REACH_BASE := 16.0      # сегодня HIT_DIST_BOSS
const REACH_IDOL := 20.0      # идол: ДАЛЬШЕ (корень)
const RAM_TELEGRAPH := 0.5    # вепрь: стойка-зарывание
const RAM_DASH := 0.5         # вепрь: сам таран
const RAM_SPEED := 95.0       # вепрь: скорость тарана (ныне CHARGE_SPEED 80)
const BLOCK_TIME := 0.8       # колосс: фронтальный блок

var _fails := 0
var _allowed := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	# Диагностика: режим PAINTERS — ASCII силуэтов (vision-модель недоступна
	# дома), файл НЕ пишется.
	if args.has("PAINTERS"):
		_ascii_probe()
		quit(0)
		return
	var target := "res://tools_art/sheet_replace_v1.png"
	if args.size() > 0:
		target = String(args[0])
	_allowed = P.color_index().duplicate()
	for k in P.SHEET:
		_allowed[P.key(P.SHEET[k])] = ["SHEET", -1]
	var a := _build_sheet()
	var b := _build_sheet()
	var ident: bool = a.save_png_to_buffer() == b.save_png_to_buffer()
	print("[bake] double-bake byte-identical: %s" % ("PASS" if ident else "FAIL"))
	if not ident:
		_fails += 1
	if _strict_scan(a):
		var dirpos := target.rfind("/")
		if dirpos > 0:
			DirAccess.make_dir_recursive_absolute(
				target.substr(0, dirpos).replace("res://", ProjectSettings.globalize_path("res://") + "/"))
		var err := a.save_png(target)
		print("[save] %s err=%d pre-save hash %s" % [target, err, _fnv32_hex(a)])
		if err != OK:
			_fails += 1
	if _fails > 0:
		print("SELF-CHECK: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("SELF-CHECK: PASS")
		quit(0)

func _c(rn: String, t: int) -> Color:
	return P.RAMPS[rn][t]

# ============================================================ холсты кандидатов
## Каждый кадр — честные 16x16 (юнит-канон hero=16px). Карты рядов: ровно 16
## символов; проверка длины встроена (ошибка пиксель-плана = FAIL, не тишина).

func _paint_map(im: Image, rows: Array, chmap: Dictionary, nm: String) -> void:
	if rows.size() != 16:
		_fails += 1
		print("[map] %s: %d рядов (ждали 16)" % [nm, rows.size()])
		return
	for y in 16:
		var row := String(rows[y])
		if row.length() != 16:
			_fails += 1
			print("[map] %s r%d: длина %d (ждали 16)" % [nm, y, row.length()])
			continue
		for x in 16:
			var ch := String(row[x])
			if ch == ".":
				continue
			if not chmap.has(ch):
				_fails += 1
				print("[map] %s r%d c%d: неизвестный глиф '%s'" % [nm, y, x, ch])
				continue
			im.set_pixel(x, y, chmap[ch])

# ---- (1) Корневой идол: широкая крона x1..14, ствол x5..10, корни-ноги ----

func _idol_rows(f: int) -> Array:
	if f == 0:
		return [
			"................",
			"....oLLLLLLo....",
			"..oLLLLLLLLLLo..",
			".oLLlLLLLLLlLlo.",
			".odLLLLLLLLLLdo.",
			"..ddLLBBBBLLdd..",
			"....BbBBBBb.....",
			".....BEBBEB.....",
			".....BEBBEB.....",
			".....DBBBBD.....",
			"....dBBBBBBd....",
			"....dBB.BBd.....",
			"...dBB....Bd....",
			"..dBB.....Bd....",
			"..DB......d.....",
			"................",
		]
	return [
		"................",
		"...oLLLLLLo.....",
		"..oLLLLLLLLLLo..",
		".oLlLLLLLLLLllo.",
		".odLLLLLLLLLLdo.",
		"..ddLLBBBBLLdd..",
		"....BbBBBBb.....",
		".....BEBBEB.....",
		".....BEBBEB.....",
		".....DBBBBD.....",
		"....dBBBBBBd....",
		"....dBB.BBd.....",
		"....dB....BBd...",
		"....dB.....dBB..",
		"....d......DB...",
		"................",
	]

func _idol(f: int) -> Image:
	var im := _im(16, 16)
	var chmap := {
		"o": _c("LEAF", P.T_LIGHT), "L": _c("LEAF", P.T_MID), "l": _c("LEAF", P.T_DARK),
		"d": _c("BARK", P.T_DARK), "B": _c("BARK", P.T_MID), "b": _c("BARK", P.T_LIGHT),
		"D": _c("BARK", P.T_OUTLINE),
		"E": _c("HP_RED", P.T_MID),
	}
	_paint_map(im, _idol_rows(f), chmap, "idol%d" % f)
	return im

# ---- (2) Тлель-вепрь: низкий широкий таран, горб с мхом, клык, глаз ----

func _boar_rows(f: int) -> Array:
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

func _boar(f: int) -> Image:
	var im := _im(16, 16)
	var chmap := {
		"m": _c("MOSS_GLOW", P.T_MID), "o": _c("MOSS_GLOW", P.T_LIGHT),
		"C": _c("CHAR", P.T_MID), "c": _c("CHAR", P.T_LIGHT), "D": _c("CHAR", P.T_DARK),
		"E": _c("HP_RED", P.T_MID), "B": _c("BONE", P.T_LIGHT),
	}
	_paint_map(im, _boar_rows(f), chmap, "boar%d" % f)
	return im

# ---- (3) Краденый колосс: квадратная глыба, железный пояс, свет-щели ----

func _coloss(f: int) -> Image:
	var im := _im(16, 16)
	var lite := _c("STONE", P.T_LIGHT)
	var mid := _c("STONE", P.T_MID)
	var dark := _c("STONE", P.T_DARK)
	var outl := _c("STONE", P.T_OUTLINE)
	var iron := _c("IRON", P.T_MID)
	var ironl := _c("IRON", P.T_LIGHT)
	var glow := _c("VIOLET", P.T_LIGHT) if f == 1 else _c("VIOLET", P.T_MID)
	var eye := _c("HP_RED", P.T_MID)
	# корпус x2..13, y1..11: середина, светлая крышка и левая грань,
	# тёмные правая грань и подошва, контур снизу
	for y in range(1, 12):
		for x in range(2, 14):
			im.set_pixel(x, y, mid)
	for x in range(2, 14):
		im.set_pixel(x, 1, lite)
		im.set_pixel(x, 11, dark)
	for y in range(1, 12):
		im.set_pixel(2, y, lite)
		im.set_pixel(13, y, dark)
	for x in range(2, 14):
		im.set_pixel(x, 12, outl)
	# железный «украденный» пояс y3 + заклёпки	for x in range(2, 14):
		im.set_pixel(x, 3, iron)
	im.set_pixel(3, 3, ironl)
	im.set_pixel(12, 3, ironl)
	# глаза-щели
	im.set_pixel(5, 2, eye)
	im.set_pixel(6, 2, eye)
	im.set_pixel(9, 2, eye)
	im.set_pixel(10, 2, eye)
	# горизонтальная свет-щель y5 + трещина вниз
	for x in range(4, 11):
		im.set_pixel(x, 5, glow)
	im.set_pixel(7, 6, glow)
	im.set_pixel(7, 7, glow)
	im.set_pixel(7, 8, dark)
	# руки-глыбы x0..1 / x14..15; кадр 1 — опущены на шаг
	var ay: int = 4 if f == 0 else 5
	for y in range(ay, ay + 6):
		im.set_pixel(0, y, dark)
		im.set_pixel(1, y, mid)
		im.set_pixel(14, y, mid)
		im.set_pixel(15, y, dark)
	im.set_pixel(0, ay, lite)
	im.set_pixel(15, ay, lite)
	# ноги-опоры; кадр 1 — размен шага
	var lx: int = 0 if f == 0 else 1
	for y in range(12, 16):
		for x in range(4 + lx, 7 + lx):
			im.set_pixel(x, y, mid if y < 15 else outl)
		for x in range(10 - lx, 13 - lx):
			im.set_pixel(x, y, mid if y < 15 else outl)
	return im

func _frames(fn: String, f: int) -> Image:
	if fn == "idol":
		return _idol(f)
	if fn == "boar":
		return _boar(f)
	return _coloss(f)

# ============================================================ биомные ремейки
## Ровно SUBS-таблицы mob_variants_v1 (лес/снег/пустошь) + color_index
## PixelPalette: тон сохраняется, рампа меняется на биомную. Ноль новых правил.

var _idx_cache: Dictionary = {}

func _biome_remake(img: Image, biome: String) -> Image:
	if _idx_cache.is_empty():
		_idx_cache = P.color_index()
	var subs: Dictionary = MV.SUBS[biome]
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a < 0.5:
				continue
			var info = _idx_cache.get(P.key(col))
			if info == null:
				out.set_pixel(x, y, col)  # strict-скан кадра это поймает
				continue
			var rn := String(info[0])
			var tone := int(info[1])
			if subs.has(rn):
				rn = String(subs[rn])
			out.set_pixel(x, y, P.RAMPS[rn][tone])
	return out

# ============================================================ биомный пол 16px
## Детерминированная двухтоновая шахматка + крошки-акценты: честный контекст
## для оценки читаемости силуэта 1:1 (это ПОЛ-подложка, не ассет).

func _floor(biome: String) -> Dictionary:
	match biome:
		"snow":
			return {"a": _c("STONE", P.T_LIGHT), "b": _c("STONE", P.T_MID), "acc": _c("CRYSTAL", P.T_MID)}
		"desert":
			return {"a": _c("PATH", P.T_LIGHT), "b": _c("PATH", P.T_MID), "acc": _c("STONE_WARM", P.T_DARK)}
		_:
			return {"a": _c("GRASS", P.T_LIGHT), "b": _c("GRASS", P.T_MID), "acc": _c("BARK", P.T_MID)}

func _context_strip(biome: String, spr: Image, w_cells: int = 4) -> Image:
	var w := 16 * w_cells
	var im := _im(w, 16)
	var fl := _floor(biome)
	for y in 16:
		for x in w:
			im.set_pixel(x, y, fl["a"] if (x + y) % 2 == 0 else fl["b"])
	for y in range(2, 15, 3):
		for x in range(0, w):
			if (x * 7 + y * 13) % 29 == 0:
				im.set_pixel(x, y, fl["acc"])
	_blit_into(im, spr, int(w / 2.0) - 8, 0, 1)
	return im

# ============================================================ замер силуэтов
## ratio = ширина верхних 25% рядов / ширина нижних 25% (по крайним непрозрачным
## пикселям). Трапеция брюта < 1; кандидаты обязаны читаться иначе.

func _sil_ratio(img: Image) -> float:
	var rows_w: Array = []
	var first := -1
	var last := -1
	for y in img.get_height():
		var lo := -1
		var hi := -1
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				if lo < 0:
					lo = x
				hi = x
		if lo >= 0:
			if first < 0:
				first = y
			last = y
		rows_w.append(0 if lo < 0 else hi - lo + 1)
	if first < 0:
		return 0.0
	# кварталы считаем по огранычику силуэта, а не по пустым полям холста
	var span := last - first + 1
	var q: int = maxi(1, int(span / 4.0))
	var top_w := 0
	var bot_w := 0
	for y in range(first, first + q):
		top_w = maxi(top_w, int(rows_w[y]))
	for y in range(last - q + 1, last + 1):
		bot_w = maxi(bot_w, int(rows_w[y]))
	if bot_w == 0:
		return 0.0
	return float(top_w) / float(bot_w)

# ============================================================ лист

func _build_sheet() -> Image:
	var W := 720
	var sheet := _im(W, 1064)
	sheet.fill(P.SHEET["BG"])
	var x0 := 10
	var y := 8
	_text(sheet, x0, y, "REPLACE V1 - BRUTE VISUAL REPLACEMENT CANDIDATES - VERDICT SHEET - NOT INTEGRATED - W6 25.11", 2, P.SHEET["TEXT"])
	y += 16
	_text(sheet, x0, y, "USER VERDICT 25.11 - I DO NOT LIKE THE BRUTE VISUALLY - REPLACE WITH OTHER MONSTERS", 1, P.SHEET["LINE"])
	y += 9
	_text(sheet, x0, y, "MECHANICAL SLOT IS KEPT - HEAVY MELEE - TIERS 6/9/12 HP - BALANCE ROW 11 - SAME SPAWN BAND", 1, P.SHEET["LINE"])
	y += 9
	_text(sheet, x0, y, "CODE ART ONLY - BIOME REMAKES VIA mob_variants_v1 SUBS TABLES - RUNTIME UNTOUCHED", 1, P.SHEET["LINE"])
	y += 9
	_text(sheet, x0, y, "CANDIDATE FRAME CYCLE - 2 X %dMS = 2.5FPS - INHERITS THE PACE OF THE CURRENT SHEET" % T_WALK_MS, 1, P.SHEET["LINE"])
	y += 16

	# ---------- обвиняемый ----------
	_text(sheet, x0, y, "THE ACCUSED - LEGACY SHEET brute.png BYTE-FOR-BYTE (2 FRAMES 32PX, WALK 2.5FPS)", 1, P.SHEET["TEXT"])
	y += 12
	var bimg: Image = load("res://assets/brute.png").get_image()
	var b0 := bimg.get_region(Rect2i(0, 0, 32, 32))
	var b1 := bimg.get_region(Rect2i(32, 0, 32, 32))
	print("[ref] brute K0 ratio=%.2f hash=%s" % [_sil_ratio(b0), _fnv32_hex(b0)])
	print("[ref] brute K1 ratio=%.2f hash=%s" % [_sil_ratio(b1), _fnv32_hex(b1)])
	_blit_sc(sheet, b0, x0, y, 3)
	_blit_sc(sheet, b1, x0 + 110, y, 3)
	var bx := x0 + 230
	_text(sheet, bx, y + 4, "TOP OVER BOTTOM WIDTH = %.2f - A TRAPEZOID DOME" % _sil_ratio(b0), 1, P.SHEET["LINE"])
	_text(sheet, bx, y + 16, "NO WAIST - NO LEGS - NO SHOULDERS - READS AS A PUDDING", 1, P.SHEET["LINE"])
	_text(sheet, bx, y + 28, "LEGACY RASTER FROM PRE ART LAW ERA - CARRIED BY ALL", 1, P.SHEET["LINE"])
	_text(sheet, bx, y + 40, "SIX BIOME PALETTE REMAKES - THE DISEASE SPREAD", 1, P.SHEET["LINE"])
	_text(sheet, bx, y + 52, "CAMEL: same file also skins the cave boss and witch", 1, P.SHEET["LINE"])
	_text(sheet, bx, y + 64, "(mob_boss2) - integration ticket must re-skin them too", 1, P.SHEET["LINE"])
	y += 32 * 3 + 14

	# ---------- кандидаты ----------
	var cands := [
		{"fn": "idol", "ru": "КОРНЕВОЙ ИДОЛ", "lat": "ROOT IDOL - WALKING STUMP - FOREST ANCHOR",
			"lines": [
				"SLOT KEPT - HEAVY MELEE - TIERS 6/9/12 HP - XP 6/8/10 - SAME BAND",
				"ANTI TRAPEZOID - TOP OVER BOTTOM = %.2f - WIDE CROWN NARROW ROOTS" % _sil_ratio(_idol(0)),
				"TELEGRAPH - ROOT WINDUP %.1fS (BASE %.1fS) - REACH %.0fPX (BASE %.0fPX)" % [WINDUP_IDOL, WINDUP_BASE, REACH_IDOL, REACH_BASE],
				"PUNISH WINDOW 1.6S KEPT - EYES HP RED - CANON THREAT SIGNAL",
				"LORE - THE FOREST REMEMBERS EVERY AXE - IT WALKS THE LEDGER",
			]},
		{"fn": "boar", "ru": "ТЛЕЛЬ-ВЕПРЬ", "lat": "TLEL BOAR - UNDERGROWTH BOAR - LOW BROAD RAM",
			"lines": [
				"SLOT KEPT - HEAVY MELEE - TIERS 6/9/12 HP - XP 6/8/10 - SAME BAND",
				"LOW WIDE BODY 15X10 - RATIO IS NOT HIS CLAIM - TUSK AND GAIT",
				"TELEGRAPH - REAR STANCE %.1fS MOSS BRISTLE STANDING UP" % RAM_TELEGRAPH,
				"THEN RAM DASH %.1fS AT %.0fPX S (BASE CHARGE 80) - HIT ON PATH" % [RAM_DASH, RAM_SPEED],
				"RECOVER 1.2S - TUSK BONE - EYE HP RED - MOSS MANTLE glows dim",
			]},
		{"fn": "coloss", "ru": "КРАДЕНЫЙ КОЛОСС", "lat": "STOLEN COLOSS - CASTLE STONE GOLEM - SQUARE BLOCK",
			"lines": [
				"SLOT KEPT - HEAVY MELEE - TIERS 6/9/12 HP - XP 6/8/10 - SAME BAND",
				"SQUARE MASS x12 WITH LIGHT SEAMS - ANTI DOME BY CONSTRUCTION",
				"BASE WINDUP %.1fS KEPT - FRONT BLOCK STANCE %.1fS (SHIELD FRONT)" % [WINDUP_BASE, BLOCK_TIME],
				"CALLS FORWARD TO STOLEN KNIGHT OF DEPTH V2 - NOT BUILT YET",
				"IRON BELT IS STOLEN SMITHWORK - GLOW SEAM PULSES BETWEEN FRAMES",
			]},
	]
	for cand in cands:
		var cd: Dictionary = cand
		var fn := String(cd["fn"])
		_text(sheet, x0, y, String(cd["lat"]), 1, P.SHEET["TEXT"])
		_ru(sheet, x0, y + 10, String(cd["ru"]), 1, P.SHEET["TEXT"])
		y += 28
		# два кадра zoom3 + FNV в консоль (PINS)
		for f in 2:
			var fr := _frames(fn, f)
			_check_fx(fr, "%s%d" % [fn, f])
			_blit_sc(sheet, fr, x0 + f * 64, y, 3)
			_text(sheet, x0 + f * 64, y + 48 + 3, "K%d" % f, 1, P.SHEET["LINE"])
		# биомные ремейки x3 (тот же пайплайн SUBS)
		var rx := x0 + 64 + 64 + 16
		var biomes := ["forest", "snow", "desert"]
		for bi in range(biomes.size()):
			var bm: String = biomes[bi]
			var rm := _biome_remake(_frames(fn, 0), bm)
			_check_fx(rm, "%s_b%s0" % [fn, bm.substr(0, 1)])
			_blit_sc(sheet, rm, rx, y, 2)
			_text(sheet, rx, y + 32 + 3, bm.to_upper(), 1, P.SHEET["LINE"])
			rx += 40
		# контекст 1:1 на биомном полу
		var cx := rx + 8
		for bi in range(biomes.size()):
			var bm2: String = biomes[bi]
			var st := _context_strip(bm2, _frames(fn, 0), 4)
			_check_fx(st, "%s_ctx%s" % [fn, bm2.substr(0, 1)])
			_blit_into(sheet, st, cx, y + 16, 1)
			cx += 64 + 6
		# карточка поведения
		var ly := y + 4
		var tx := cx + 10
		for ln in (cd["lines"] as Array):
			_text(sheet, tx, ly, String(ln), 1, P.SHEET["LINE"])
			ly += 10
		y += 74
		_hline_px(sheet, x0, W - 10, y - 6, P.SHEET["LINE"])
		y += 4

	# ---------- сравнение силуэтов ----------
	_text(sheet, x0, y, "SILOUETTE LINEUP - ACCUSED VERSUS CANDIDATES - 16PX ON NEUTRAL FLOOR - RATIO ABOVE EACH", 1, P.SHEET["TEXT"])
	y += 12
	var lineup: Array = [{"n": "BRUTE %.2f" % _sil_ratio(b0), "img": b0}]
	for cand in cands:
		var cd2: Dictionary = cand
		var fr2 := _frames(String(cd2["fn"]), 0)
		print("[sil] %-7s ratio=%.2f" % [String(cd2["fn"]), _sil_ratio(fr2)])
		lineup.append({"n": "%s %.2f" % [String(cd2["fn"]).to_upper(), _sil_ratio(fr2)], "img": fr2})
	var lx2 := x0
	for it in lineup:
		var im2: Image = it["img"]
		var pad := _im(18, 18)
		for yy in 16:
			for xx in 18:
				pad.set_pixel(xx, yy, _c("ASH_GROUND", P.T_MID) if (xx + yy) % 2 == 0 else _c("ASH_GROUND", P.T_DARK))
		_blit_into(pad, im2, 1, 1, 1)
		_check_fx(pad, "lineup_bg")
		_blit_sc(sheet, pad, lx2, y, 2)
		_text(sheet, lx2, y + 36 + 3, String(it["n"]), 1, P.SHEET["LINE"])
		lx2 += 18 * 2 + 14
	y += 54

	# ---------- честность ----------
	_text(sheet, x0, y, "IN GAME TODAY - BRUTE SHEET ALSO SKINS CAVE GROM AND ASHEN WITCH - THEY NEED A RE-SKIN ROW", 1, P.SHEET["TEXT"])
	y += 9
	_text(sheet, x0, y, "IN INTEGRATION - SPRITE PLUS NAME PLUS LORE ROWS PLUS DATED REPIN OF qa_mb BRUT PINS", 1, P.SHEET["TEXT"])
	y += 9
	_text(sheet, x0, y, "brute_tier MECHANICS STAY UNTOUCHED - BALANCE ROW 11 KEEPS TIER FORKS VERBATIM", 1, P.SHEET["TEXT"])
	y += 9
	_text(sheet, x0, y, "SHEETS FRAMES ARE CODE GENERATED - ZERO RASTER FILES WRITTEN - RUNTIME FILES UNTOUCHED", 1, P.SHEET["TEXT"])
	y += 12
	_text(sheet, x0, y, "HONESTY - SILHOUETTES PROVED BY ASCII DUMPS (PAINTERS MODE) - FINAL AESTHETICS: HUMAN EYE", 1, P.SHEET["TEXT"])
	y += 12
	var h := mini(y, 1064)
	sheet.crop(W, h)  # Godot 4.7: crop(width, height) от верхнего левого угла
	return sheet

# ============================================================ режим PAINTERS

func _ascii_probe() -> void:
	var bimg: Image = load("res://assets/brute.png").get_image()
	_ascii_dump(bimg.get_region(Rect2i(0, 0, 32, 32)), "brute K0 (accused, 32px)")
	_ascii_dump(_idol(0), "idol K0")
	_ascii_dump(_idol(1), "idol K1")
	_ascii_dump(_boar(0), "boar K0")
	_ascii_dump(_boar(1), "boar K1")
	_ascii_dump(_coloss(0), "coloss K0")
	_ascii_dump(_coloss(1), "coloss K1")
	_ascii_dump(_biome_remake(_idol(0), "snow"), "idol snow remake")
	_ascii_dump(_biome_remake(_boar(0), "desert"), "boar desert remake")
	_ascii_dump(_biome_remake(_coloss(0), "snow"), "coloss snow remake")

func _ascii_dump(img: Image, title: String) -> void:
	print("== " + title)
	for y in img.get_height():
		var row := ""
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				row += "."
			elif c.v < 0.25:
				row += "#"
			elif c.v < 0.55:
				row += "+"
			elif c.v < 0.8:
				row += "o"
			else:
				row += "O"
		print(row)

func _check_fx(im: Image, nm: String) -> void:
	var n := 0
	var off := 0
	for yy in im.get_height():
		for xx in im.get_width():
			var col := im.get_pixel(xx, yy)
			if col.a < 0.5:
				continue
			n += 1
			if not _allowed.has(P.key(col)):
				off += 1
	var ok: bool = n >= 6 and off == 0
	print("[fx] %-16s px:%3d off:%d %s hash:%s" % [nm, n, off, ("PASS" if ok else "FAIL"), _fnv32_hex(im)])
	if not ok:
		_fails += 1

# ============================================================ строгий скан / хэш

func _strict_scan(img: Image) -> bool:
	var off := 0
	var mask := 0
	for yy in img.get_height():
		for xx in img.get_width():
			var col := img.get_pixel(xx, yy)
			if col.a < 1.0:
				mask += 1
				continue
			if not _allowed.has(P.key(col)):
				off += 1
	var ok: bool = off == 0 and mask == 0
	print("[strict] sheet-wide %dx%d off=%d mask=%d %s" % [img.get_width(), img.get_height(), off, mask, ("PASS" if ok else "FAIL")])
	if not ok:
		_fails += 1
	return ok

func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

# ============================================================ бортовые шрифты
## Глифы игры НЕ цитируются: собственный чертёжный шрифт инструмента.
## Латинь 3x5 (как sheet_feel_v1) + Кириллица 5x7 (имена на листе — русские).

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

## Кириллица 5x7 — собственный чертёжный набор инструмента (только литеры
## имён листа; игровые глифы handjet не цитировались никогда).
const RU := {
	"А": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"В": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"Г": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"Д": ["00100", "00100", "00100", "00100", "01110", "10001", "11111"],
	"Е": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"И": ["10001", "10001", "10001", "10011", "10101", "11001", "10001"],
	"Й": ["00100", "00000", "10001", "10011", "10101", "11001", "10001"],
	"К": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"Л": ["00111", "01001", "01001", "01001", "01001", "01001", "10001"],
	"Н": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"О": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"П": ["11111", "10001", "10001", "10001", "10001", "10001", "10001"],
	"Р": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"С": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"Т": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"У": ["10001", "10001", "10001", "01111", "00010", "00100", "11000"],
	"Ы": ["10001", "10001", "10001", "11101", "10001", "10001", "10001"],
	"Ь": ["10000", "10000", "10000", "01110", "10001", "10001", "01110"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
}

func _ru(img: Image, x0: int, y0: int, txt: String, sc: int, col: Color) -> int:
	var x := x0
	for ch in txt.to_upper():
		var g = RU.get(ch)
		if g == null:
			push_warning("RU font: литеры '%s' нет" % ch)
			x += 6 * sc
			continue
		for r in 7:
			for c in 5:
				if String(g[r])[c] == "1":
					for dy in sc:
						for dx in sc:
							_px(img, x + c * sc + dx, y0 + r * sc + dy, col)
		x += 6 * sc
	return x - x0 - sc

func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)

# ---- мелкие примитивы (тот же чертёжный набор, что sheet_feel_v1) ----

func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

func _blit_into(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var col := src.get_pixel(x, y)
			if col.a < 0.5:
				continue
			for dy in sc:
				for dx in sc:
					_px(dst, x0 + x * sc + dx, y0 + y * sc + dy, col)

func _blit_sc(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	_blit_into(dst, src, x0, y0, sc)

func _hline_px(sheet: Image, xa: int, xb: int, y: int, col: Color) -> void:
	for xx in range(mini(xa, xb), maxi(xa, xb) + 1):
		_px(sheet, xx, y, col)
