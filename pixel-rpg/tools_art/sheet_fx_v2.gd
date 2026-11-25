extends SceneTree
## t15 «Лист „Ощущение v2 — VFX смело“» (вердикт пользователя 25.11 по
## листу «Ощущение v1», секция A: «VFX-боя можно проработать смелее, больше
## эффектов визуальных, от удара, от выстрела»).
##
## ЭТО ЛИСТ-ВЕРДИКТ, НЕ ИНТЕГРАЦИЯ (закон ART): рантайм не тронут. Секции B/C
## (слизень/призрак) без вердикта — на этом листе их НЕТ, не смешивать.
## Ноль растров в дереве игры: PNG живёт в diag-w5b (как W4/W5/T10).
##
## Палитра: только RAMPS/FLATS/pixel_palette.SHEET. Глифы игры (handjet)
## не цитированы — бортовой шрифт инструмента 3x5 (тот же эталон, что
## sheet_env_v1/sheet_feel_v1). gl_compatibility: всё — покадровые спрайты,
## Tween, ColorRect, существующие пулы CPUParticles; GPU-частиц и shader нет.
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_fx_v2.gd -- <out.png>
##   Godot ... -- PAINTERS        # ASCII-силуэты ключевых кадров, файл не пишет

const P := preload("res://scripts/pixel_palette.gd")

# Тайминги (мс) — const листа, цитируются в PINS_W5B
const T_WAVE_MS := 40      # ударная волна: 3 x 40 = 120 мс (тяжёлые удары)
const T_SPLAT_MS := 40     # брызги-осколки: 3 x 40 = 120 мс
const T_VIGN_MS := 70      # виньетка получения: 2 x 70 = 140 мс
const T_COMBO_MS := 50     # комбо-искра: 3 x 50 = 150 мс
const T_FINISH_SLOW := 60  # добивание: замедление-кадр, мс
const T_FINISH_FLASH := 100 # …и белый флеш, 1 кадр-вспышка ~100 мс
const T_FLY_MS := 45       # след стрелы: 2 x 45 = 90 мс хвост
const T_QUIVER_MS := 60    # дрожание оперения: 2 x 60 = 120 мс
const T_BOLT_MS := 60      # мерцание сгустка: 2 x 60 = цикл
const T_BURST_MS := 40     # лучи удара магии: 3 x 40 = 120 мс
const T_SWISH_MS := 50     # свист промаха: 2 x 50 = 100 мс
const T_SHAD_MS := 70      # тень-лужа смерти: 3 x 70 = 210 мс

var _fails := 0
var _allowed := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("PAINTERS"):
		_ascii_probe()
		quit(0)
		return
	var target := "res://tools_art/sheet_fx_v2.png"
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

# ====================================================== УДАР: волна-кольцо 3к

func _ring(im: Image, cx: float, cy: float, r: float, col: Color, step: int) -> void:
	var n := int(maxf(12.0, TAU * r))
	for i in range(0, n, step):
		var a := TAU * float(i) / float(n)
		_put(im, int(round(cx + r * cos(a))), int(round(cy + r * sin(a))), col)

func _wave(f: int) -> Image:
	var im := _im(16, 16)
	match f:
		0:
			_ring(im, 8, 8, 3, _c("BONE", P.T_LIGHT), 1)
		1:
			_ring(im, 8, 8, 6, _c("BONE", P.T_MID), 1)
		2:
			_ring(im, 8, 8, 9, _c("BONE", P.T_DARK), 2)
			_put(im, 8, 8, _c("BONE", P.T_LIGHT))
	return im

# ====================================================== УДАР: брызги-осколки

func _splat(f: int) -> Image:
	var im := _im(16, 16)
	match f:
		0:
			_rect16(im, 10, 6, 11, 7, _c("HUD_GOLD", P.T_LIGHT))
			_rect16(im, 12, 4, 13, 5, _c("HUD_GOLD", P.T_LIGHT))
			for d in [[9, 8], [11, 5], [13, 3], [8, 9], [12, 8]]:
				_put(im, d[0], d[1], _c("HUD_GOLD", P.T_MID))
		1:
			_rect16(im, 12, 4, 13, 5, _c("HUD_GOLD", P.T_MID))
			for d in [[14, 3], [11, 4], [13, 7], [10, 8]]:
				_put(im, d[0], d[1], _c("FIRE", P.T_MID))
		2:
			for d in [[13, 4], [14, 2], [12, 8], [10, 9], [10, 3]]:
				_put(im, d[0], d[1], _c("CHAR", P.T_MID))
			_put(im, 13, 3, _c("FIRE", P.T_DARK))
			_put(im, 11, 6, _c("FIRE", P.T_DARK))
	return im

# ============================================ УДАР: виньетка получения 2к
# Макет окна 64x36 (16:9 мира): герой-болванка + красная рамка-виньетка.
# Читаемо, но не слепит: к0 рамка 2px HP_RED_MID со светлыми углами,
# к1 — гаснет в 1px HP_RED_DARK.

func _vign(f: int) -> Image:
	var im := _im(64, 36)
	_fill(im, P.SHEET["BG"])
	_span(im, 0, 63, 30, _c("PATH", P.T_MID))
	_rect16(im, 29, 20, 34, 29, _c("IRON", P.T_MID))
	_rect16(im, 30, 17, 33, 19, _c("BONE", P.T_MID))
	if f == 0:
		_frame_rect(im, 0, 0, 63, 35, 2, _c("HP_RED", P.T_MID))
		for d in [[0, 0], [63, 0], [0, 35], [63, 35], [1, 0], [62, 0], [1, 35], [62, 35]]:
			_put(im, d[0], d[1], _c("HP_RED", P.T_LIGHT))
	else:
		_frame_rect(im, 0, 0, 63, 35, 1, _c("HP_RED", P.T_DARK))
	return im

func _frame_rect(im: Image, x0: int, y0: int, x1: int, y1: int, th: int, col: Color) -> void:
	for t in th:
		_span(im, x0, x1, y0 + t, col)
		_span(im, x0, x1, y1 - t, col)
		for y in range(y0, y1 + 1):
			_put(im, x0 + t, y, col)
			_put(im, x1 - t, y, col)

# ============================================ УДАР: комбо-искра 3+ подряд

func _combo(f: int) -> Image:
	var im := _im(16, 16)
	match f:
		0:
			_text(im, 4, 6, "X3", 1, _c("HUD_GOLD", P.T_LIGHT))
			for d in [[2, 4], [13, 4], [2, 11], [13, 11]]:
				_put(im, d[0], d[1], _c("HUD_GOLD", P.T_MID))
		1:
			_text(im, 4, 6, "X3", 1, _c("HUD_GOLD", P.T_MID))
		2:
			_text(im, 4, 6, "X3", 1, _c("CHAR", P.T_DARK))
	return im

# ============================================ УДАР: добивание dobivanie - tumblernoe
# к0 — кадр до; к1 — белый флеш 1 кадр после замедления-кадра 60 мс.

func _fin(f: int) -> Image:
	var im := _im(16, 16)
	var col := _c("CHAR", P.T_LIGHT)
	var c2 := _c("IRON", P.T_MID)
	var sl := _c("BONE", P.T_MID)
	if f == 1:
		col = _c("BONE", P.T_LIGHT)
		c2 = _c("BONE", P.T_LIGHT)
		sl = _c("BONE", P.T_LIGHT)
	_rect16(im, 3, 7, 6, 13, col)
	_rect16(im, 9, 5, 13, 13, c2)
	for d in [[7, 4], [8, 5], [7, 6]]:
		_put(im, d[0], d[1], sl)
	return im

# ================================================= ВЫСТРЕЛ: стрела + след 2к
# Клетка 48x16: дуга полёта видна целиком, хвост затухает.

func _fly(f: int) -> Image:
	var im := _im(48, 16)
	var x0 := 24 if f == 0 else 28
	_put(im, x0 + 12, 8, _c("IRON", P.T_LIGHT))
	_put(im, x0 + 11, 7, _c("IRON", P.T_LIGHT))
	_put(im, x0 + 11, 9, _c("IRON", P.T_DARK))
	_span(im, x0, x0 + 10, 8, _c("BARK", P.T_MID))
	_span(im, x0, x0 + 10, 7, _c("BARK", P.T_LIGHT))
	_put(im, x0 - 1, 7, _c("CLOTH", P.T_LIGHT))
	_put(im, x0 - 1, 9, _c("CLOTH", P.T_MID))
	_put(im, x0 - 2, 8, _c("CLOTH", P.T_LIGHT))
	if f == 0:
		_put(im, x0 - 6, 8, _c("PATH", P.T_MID))
		_put(im, x0 - 10, 7, _c("PATH", P.T_MID))
		_put(im, x0 - 14, 7, _c("PATH", P.T_DARK))
	else:
		_put(im, x0 - 5, 8, _c("PATH", P.T_DARK))
		_put(im, x0 - 9, 7, _c("PATH", P.T_DARK))
	return im

# ============================== ВЫСТРЕЛ: попадание — оперение дрожит + пыль

func _quiv(f: int) -> Image:
	var im := _im(16, 16)
	_rect16(im, 4, 8, 6, 10, _c("IRON", P.T_DARK))
	if f == 0:
		_span(im, 8, 12, 9, _c("BARK", P.T_MID))
		_put(im, 7, 8, _c("CLOTH", P.T_LIGHT))
		_put(im, 7, 9, _c("CLOTH", P.T_LIGHT))
		_put(im, 7, 10, _c("CLOTH", P.T_MID))
	else:
		_span(im, 8, 12, 8, _c("BARK", P.T_MID))
		_put(im, 7, 7, _c("CLOTH", P.T_LIGHT))
		_put(im, 7, 8, _c("CLOTH", P.T_LIGHT))
		_put(im, 7, 9, _c("CLOTH", P.T_MID))
		_put(im, 8, 11, _c("PATH", P.T_MID))
		_put(im, 10, 12, _c("PATH", P.T_DARK))
	return im

# ================================================== МАГИЯ: сгусток 2к мерц.

func _bolt(f: int) -> Image:
	var im := _im(16, 16)
	if f == 0:
		_rect16(im, 7, 7, 9, 9, _c("CRYSTAL", P.T_MID))
		for d in [[6, 8], [10, 8], [8, 6], [8, 10], [6, 6], [10, 6], [6, 10], [10, 10]]:
			_put(im, d[0], d[1], _c("CRYSTAL", P.T_DARK))
	else:
		_rect16(im, 7, 7, 9, 9, _c("CRYSTAL", P.T_LIGHT))
		for d in [[6, 8], [10, 8], [8, 6], [8, 10]]:
			_put(im, d[0], d[1], _c("VIOLET", P.T_MID))
		for d in [[6, 6], [10, 6], [6, 10], [10, 10]]:
			_put(im, d[0], d[1], _c("VIOLET", P.T_DARK))
	return im

# ======================== МАГИЯ: удар — лучи 4+4 крест-накрест 3к + осколки

func _burst(f: int) -> Image:
	var im := _im(16, 16)
	var C := 8
	match f:
		0:
			for d in [[1, 0], [2, 0], [3, 0], [-1, 0], [-2, 0], [-3, 0], [0, 1], [0, 2], [0, 3], [0, -1], [0, -2], [0, -3]]:
				_put(im, C + d[0], C + d[1], _c("CRYSTAL", P.T_LIGHT))
			for d in [[1, 1], [-1, 1], [1, -1], [-1, -1], [2, 2], [-2, 2], [2, -2], [-2, -2]]:
				_put(im, C + d[0], C + d[1], _c("VIOLET", P.T_LIGHT))
		1:
			for s in 5:
				for sgn in [1, -1]:
					_put(im, C + sgn * s, C, _c("CRYSTAL", P.T_LIGHT if s == 4 else P.T_MID))
					_put(im, C, C + sgn * s, _c("CRYSTAL", P.T_LIGHT if s == 4 else P.T_MID))
			for s in 3:
				for d in [[1, 1], [-1, 1], [1, -1], [-1, -1]]:
					_put(im, C + d[0] * s, C + d[1] * s, _c("VIOLET", P.T_MID))
		2:
			for d in [[6, 0], [-6, 0], [0, 6], [0, -6]]:
				_put(im, C + d[0], C + d[1], _c("CRYSTAL", P.T_DARK))
			_put(im, 13, 3, _c("VIOLET", P.T_DARK))
			_put(im, 14, 2, _c("VIOLET", P.T_MID))
			_put(im, 3, 12, _c("VIOLET", P.T_DARK))
			_put(im, 2, 13, _c("VIOLET", P.T_MID))
			_put(im, 12, 13, _c("CRYSTAL", P.T_DARK))
			_put(im, 4, 3, _c("CRYSTAL", P.T_DARK))
	return im

# ============================ ПРОМАХ: свист-дуга 2к — промах ВИДЕН целиком

func _swish(f: int) -> Image:
	var im := _im(16, 16)
	_rect16(im, 3, 6, 5, 11, _c("CHAR", P.T_LIGHT))
	if f == 0:
		_put(im, 13, 3, _c("IRON", P.T_LIGHT))
		_put(im, 12, 4, _c("IRON", P.T_MID))
		_put(im, 11, 5, _c("BARK", P.T_MID))
		_put(im, 10, 6, _c("BARK", P.T_MID))
		_put(im, 9, 6, _c("CLOTH", P.T_LIGHT))
	else:
		var n := 16
		for i in range(0, n, 2):
			var a := deg_to_rad(lerpf(100.0, 20.0, float(i) / float(n)))
			_put(im, int(round(2 + 11 * cos(a))), int(round(14 - 11 * sin(a))), _c("CRYSTAL", P.T_MID))
		_put(im, 12, 4, _c("HUD_GOLD", P.T_MID))
	return im

# =============================================== СМЕРТЬ: тень-лужа 3к

func _shad(f: int) -> Image:
	var im := _im(16, 16)
	_span(im, 1, 14, 13, _c("GRASS", P.T_MID))
	match f:
		0:
			_rect16(im, 9, 2, 13, 6, _c("CHAR", P.T_LIGHT))
			_span(im, 7, 9, 13, _c("GRASS", P.T_DARK))
		1:
			_rect16(im, 9, 5, 13, 9, _c("CHAR", P.T_LIGHT))
			_span(im, 5, 11, 13, _c("GRASS", P.T_DARK))
		2:
			_span(im, 3, 12, 13, _c("GRASS", P.T_DARK))
			_span(im, 3, 12, 12, _c("GRASS", P.T_MID))
			_put(im, 3, 12, _c("GRASS", P.T_LIGHT))
			_put(im, 12, 12, _c("GRASS", P.T_LIGHT))
	return im

## Лужи-варианты по палитре биома: лес / поле / Пепелище.
func _puddle(fam: String) -> Image:
	var im := _im(16, 16)
	_span(im, 1, 14, 13, _c(fam, P.T_MID))
	_span(im, 3, 12, 12, _c(fam, P.T_DARK))
	_span(im, 4, 11, 11, _c(fam, P.T_DARK))
	_put(im, 3, 11, _c(fam, P.T_LIGHT))
	_put(im, 12, 11, _c(fam, P.T_LIGHT))
	return im

# ================================================================ лист

func _build_sheet() -> Image:
	var W := 720
	var sh := _im(W, 1400)
	_fill(sh, P.SHEET["BG"])
	var y := 10
	_text(sh, 12, y, "OSHCHUSHENIE V2 : VFX SMEELO : T15 : 25.11.2026", 2, P.SHEET["TEXT"])
	y += 16
	_text(sh, 12, y, "VERDIKT POLZOVATELYA : VFX BOYA MOZHNO PRORABOTAT SMELLEE -", 1, P.SHEET["TEXT"])
	y += 9
	_text(sh, 12, y, "BOLSHE EFFEKTOV VIZUALNYH : OT UDARA : OT VYSTRELA", 1, P.SHEET["TEXT"])
	y += 9
	_text(sh, 12, y, "NE INTEGRIROVANO - ZAKON ART : SEKCIJ B/C - SUDA NE KASAEMSYA", 1, P.c("HP_RED", P.T_LIGHT))
	y += 14

	# ---- 0. честность: что уже есть -------------------------------------
	_sec(sh, y, "0. CHTO UZHE EST V IGRYE - PROVERENO PO KODU - VTOROGO NE NADO")
	y += 12
	_box(sh, 12, y, W - 24, 86, [
		"ISKRA UDARA: Fx.hit - CPUParticles2D + fx_spark.png 7x7 : UZHE EST",
		"VSPYSHKA TINTA MOBA <=0.1 s : LINEAR >1 : UZHE EST - NE TROGAT",
		"CHISLA DmgNumbers 9/11/7 px : KRIT ALOY : DISCIPLINA KRASNOE=SMERTELNOE",
		"TRYASKA 4 STUP + HITSTOP juice.gd : PYL Fx.dust pri rolle",
		"OGNEBALL: OGNEV SLED fire_trail + VZRYV fire_burst : FROST_RING",
		"NET: sleda strely : kombo-schetchika : vignetki geroyu : zamedleniya",
		"dobivaniya : teni-luzhi smerti : drozhaniya pera : svista promaha",
	])
	y += 86 + 14

	# ---- 1. УДАР --------------------------------------------------------
	_sec(sh, y, "1. UDAR : VOLNA : BRYZGI : VIGNETKA : KOMBO : DOBIVANIE")
	y += 12
	y = _strip(sh, [
		{"img": _wave(0), "name": "volna0"},
		{"img": _wave(1), "name": "volna1"},
		{"img": _wave(2), "name": "volna2"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "3 KADRA : 3x40 MC : TOLYAKO TYAZHELYE - TARAN VEPRYA", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "DUBINA : DVOLNOJ KRIT : KONTUR BONE RASHODITSYA", 1, P.SHEET["LINE"])
	y += 12
	y = _strip(sh, [
		{"img": _splat(0), "name": "bryzgi0"},
		{"img": _splat(1), "name": "bryzgi1"},
		{"img": _splat(2), "name": "bryzgi2"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "5-7 TOCEK PO VEKTORU UDARA : 2 RAZMERA : 3x40 MC", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "GOLD -> OGON -> UGLI CHAR : ZATUHANIYE 3 KADRA", 1, P.SHEET["LINE"])
	y += 12
	# виньетка на своём месте (64x36 x2)
	var v0 := _vign(0)
	var v1 := _vign(1)
	_check_fx(v0, "vign0")
	_check_fx(v1, "vign1")
	_blit_sc(sh, v0, 16, y, 2)
	_blit_sc(sh, v1, 160, y, 2)
	_text(sh, 16, y + 76, "VIGNETKA POLUCHENIYA : 2 KADRA x 70 MC : RAMKA HP_RED", 1, P.SHEET["LINE"])
	_text(sh, 330, y + 20, "CHITAEMO : NO NE SLEPIT : 2 KADRA", 1, P.SHEET["LINE"])
	_text(sh, 330, y + 30, "K0 RAMKA 2PX + SVETLYE UGLY : K1 GASNET 1PX", 1, P.SHEET["LINE"])
	_text(sh, 330, y + 40, "HODIT NA CanvasLayer : ColorRect - BEZ SHADEROV", 1, P.SHEET["LINE"])
	y += 90
	y = _strip(sh, [
		{"img": _combo(0), "name": "kombo0"},
		{"img": _combo(1), "name": "kombo1"},
		{"img": _combo(2), "name": "kombo2"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "PRI 3+ PODRYAD : X3 ZOLOTOE ISKROJ : 3x50 MC", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "ZHIVET VTORYM LABEL V PUULE DmgNumbers", 1, P.SHEET["LINE"])
	y += 12
	y = _strip(sh, [
		{"img": _fin(0), "name": "dobi0"},
		{"img": _fin(1), "name": "dobi1"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "DOBIVANIE : ZAMEDLENIE-KADR 60 MS + BELYJ FLESH 1 KADR", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "TUMBLERNOE : TUMBLER SMELYE EFFEKTY OFF = PROKHOD ITYOT TIHO", 1, P.SHEET["LINE"])
	y += 16

	# ---- 2. ВЫСТРЕЛ/ПОЛЁТ ----------------------------------------------
	_sec(sh, y, "2. VYSTREL I POLYOT : SLED : PERO : SUSTOK : LUCHI : SVIST")
	y += 12
	# полёт стрелы — клетки 48x16 sc2
	var fl0 := _fly(0)
	var fl1 := _fly(1)
	_check_fx(fl0, "strela0")
	_check_fx(fl1, "strela1")
	_blit_sc(sh, fl0, 16, y, 2)
	_blit_sc(sh, fl1, 120, y, 2)
	_text(sh, 16, y + 36, "STRELA : DREVKO + OPERENIE CHITAEMO : HVOSTOVOJ SLED 2K", 1, P.SHEET["LINE"])
	_text(sh, 330, y + 10, "DUKA POLYOTA VIDNA CELIKOM : 2x45 MC", 1, P.SHEET["LINE"])
	_text(sh, 330, y + 20, "VTOROJ AtlasTexture-KADR NA projectile", 1, P.SHEET["LINE"])
	_text(sh, 330, y + 30, "- CLED ZATUHAYET PATH M -> D", 1, P.SHEET["LINE"])
	y += 50
	y = _strip(sh, [
		{"img": _quiv(0), "name": "pero0"},
		{"img": _quiv(1), "name": "pero1"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "POPAL : OPERENIE DROZHIT 2 KADRA PEREZ ISCHEZNOVEM", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "+ PYLEVOJ BLIP PATH : Tween poshutki na ostatke strely", 1, P.SHEET["LINE"])
	y += 12
	y = _strip(sh, [
		{"img": _bolt(0), "name": "sustok0"},
		{"img": _bolt(1), "name": "sustok1"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "MAGIYA : SUSTOK S MERZANIEM 2 KADRA x 60 MC", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "CRYSTAL SERDCE : KOLZO VIOLET PO PEREMENNYM KADRAM", 1, P.SHEET["LINE"])
	y += 12
	y = _strip(sh, [
		{"img": _burst(0), "name": "luchi0"},
		{"img": _burst(1), "name": "luchi1"},
		{"img": _burst(2), "name": "luchi2"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "UDAR MAGII : LUCHI 4+4 KREST-NAKREST 3 KADRA x 40 MC", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "+ OSKOLKI KRISTALLA : TEX_SHARD UZHE EST V FX.PULAH", 1, P.SHEET["LINE"])
	y += 12
	y = _strip(sh, [
		{"img": _swish(0), "name": "svist0"},
		{"img": _swish(1), "name": "svist1"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "UKLONENIE/PROMAH : SVIST-DUGA 2K : PROMAH VIDEN", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "IGROK PONIMAET POCHEMU NE POPAL : 2x50 MC", 1, P.SHEET["LINE"])
	y += 16

	# ---- 3. СМЕРТЬ ------------------------------------------------------
	_sec(sh, y, "3. SMERT MOBA : PADAYUSHAYA TEN-LUZHKA 3 KADRA - PALITRA BIO")
	y += 12
	y = _strip(sh, [
		{"img": _shad(0), "name": "ten0"},
		{"img": _shad(1), "name": "ten1"},
		{"img": _shad(2), "name": "ten2"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "KADR MIRA ZAMIRAET 60 MS : TEN PADAJET I RASTEKAYETSZY", 1, P.SHEET["LINE"])
	_text(sh, 330, y - 20, "3x70 MC : Sprite2D + Tween : lezhit pod ostatkom", 1, P.SHEET["LINE"])
	y += 12
	y = _strip(sh, [
		{"img": _puddle("GRASS"), "name": "luzha:les"},
		{"img": _puddle("PATH"), "name": "luzha:pole"},
		{"img": _puddle("ASH_GROUND"), "name": "luzha:pepelishche"},
	], 3, 16, y)
	_text(sh, 330, y - 30, "PALITRA POLA BIO: GRASS / PATH / ASH_GROUND", 1, P.SHEET["LINE"])
	y += 16

	# ---- 4. таблица ------------------------------------------------------
	_sec(sh, y, "4. TABLICA : TAJMINGI : PALITRY : GDE ZHIVET : BEZ NOVOY ARHIT")
	y += 12
	_box(sh, 12, y, W - 24, 140, [
		"EFFEKT          KADRY  TAJMING   PALITRA            GDE ZHIVET",
		"volna udara     3      3x40 ms   BONE L/M/D         AtlasTexture + Tween, kax env-art",
		"bryzgi udara    3      3x40 ms   HUD_GOLD/FIRE/CHAR CPUParticles2D - kax Fx.hit, tochno",
		"vignetka 2k     2      2x70 ms   HP_RED             CanvasLayer : 4 ColorRect - bez shader",
		"kombo iskra     3      3x50 ms   HUD_GOLD           vtoroj Label v puule DmgNumbers",
		"dobivanie       2      60+100ms  BONE L             Juice: time_pulse -> vernut kadr",
		"strela + sled   2      2x45 ms   BARK/IRON/CLOTH    vtoroj AtlasTexture na projectile",
		"pero drozhit    2      2x60 ms   CLOTH + PATH pyl   Tween poshutki na ostatke strely",
		"sustok magii    2      2x60 ms   CRYSTAL/VIOLET     kadr boly: merzanie Tween",
		"luchi udara     3      3x40 ms   CRYSTAL/VIOLET     krest-AtlasTexture + oskolki SHARD",
		"svist promaha   2      2x50 ms   CRYSTAL M          duga-AtlasTexture za strelkoj",
		"ten-luzhka      3      3x70 ms   palitra pola bio   Sprite2D + Tween, cvet pod bio",
	])
	y += 140 + 14

	# ---- 5. настройки и обещания ----------------------------------------
	_sec(sh, y, "5. TUMBLER I GRANICY")
	y += 12
	_box(sh, 12, y, W - 24, 78, [
		"TUMBLER SMELYE EFFEKTY - V SettingsMenu : PO UMOLCHANIYU VKLYUCHENO",
		"OFF: volna/bryzgi/vignetka/dobivanie/ten/svist -> ne igrayut : chisla",
		"i tryaska zhivut kak segodnya : tumblery - ne novaya arhitektura",
		"gl_compatibility: kadry + Tween + CPUParticles : GPU-chasticy i shader",
		"NE ISPOLZUUTSYA : kadr-uroven trjukov: modulate >1 - kak uzhe v t18",
		"VIZII NET - GLAZAMI: SILUETY V REZHIME PAINTERS + HASHI V PINS_W5B",
	])
	y += 78 + 14

	_text(sh, 12, y, "KOD-PECHARENKA LISTA - NOL RASTROV V DEREVE : PNG ZHYVET V DIAG-W5B", 1, P.SHEET["LINE"])
	y += 9
	_text(sh, 12, y, "GLIFY IGRY NE CITIRUUTSYA: BORTOVOJ SHRIPT INSTRUMENTA 3x5", 1, P.SHEET["LINE"])
	if y + 5 >= sh.get_height():
		_fails += 1
		print("[layout] overflow: footer na y=%d pri h=%d" % [y, sh.get_height()])
	else:
		print("[layout] ispolzovano %d iz %d px" % [y + 5, sh.get_height()])
	return sh

func _sec(sheet: Image, y: int, txt: String) -> void:
	_text(sheet, 12, y, txt, 1, P.SHEET["TEXT"])
	_hline_px(sheet, 12, 707, y + 8, P.SHEET["LINE"])

func _strip(sheet: Image, items: Array, sc: int, x: int, y: int) -> int:
	var xx := x
	for it in items:
		var im: Image = it["img"]
		var nm: String = String(it["name"])
		_check_fx(im, nm.replace(":", "_"))
		_blit_sc(sheet, im, xx, y, sc)
		_text(sheet, xx, y + im.get_height() * sc + 3, nm, 1, P.SHEET["LINE"])
		xx += maxi(im.get_width() * sc + 6, 40)
	return y + 16 * sc + 14

# ====================================================== PAINTERS без vision

func _ascii_probe() -> void:
	_ascii_dump(_wave(1), "volna1")
	_ascii_dump(_splat(0), "bryzgi0")
	_ascii_dump(_vign(0), "vign0")
	_ascii_dump(_combo(0), "kombo0")
	_ascii_dump(_fin(1), "dobi1")
	_ascii_dump(_fly(0), "strela0")
	_ascii_dump(_quiv(1), "pero1")
	_ascii_dump(_bolt(1), "sustok1")
	_ascii_dump(_burst(1), "luchi1")
	_ascii_dump(_swish(1), "svist1")
	_ascii_dump(_shad(2), "ten2")

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

# ================================================== проверки/примитивы

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
	print("[fx] %-14s px:%3d off:%d %s hash:%s" % [nm, n, off, ("PASS" if ok else "FAIL"), _fnv32_hex(im)])
	if not ok:
		_fails += 1

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

func _fill(img: Image, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, col)

func _put(im: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, col)

func _span(im: Image, x0: int, x1: int, y: int, col: Color) -> void:
	for x in range(x0, x1 + 1):
		_put(im, x, y, col)

func _rect16(im: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_put(im, x, y, col)

func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

func _blit_sc(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var col := src.get_pixel(x, y)
			if col.a < 0.5:
				continue
			for dy in sc:
				for dx in sc:
					_put(dst, x0 + x * sc + dx, y0 + y * sc + dy, col)

func _box(sheet: Image, x: int, y0: int, w: int, h: int, lines: Array) -> void:
	_hline_px(sheet, x, x + w, y0, P.SHEET["LINE"])
	_hline_px(sheet, x, x + w, y0 + h, P.SHEET["LINE"])
	for yy in range(y0, y0 + h + 1):
		_put(sheet, x, yy, P.SHEET["LINE"])
		_put(sheet, x + w, yy, P.SHEET["LINE"])
	var ty := y0 + 6
	for t_0 in lines:
		_text(sheet, x + 5, ty, String(t_0), 1, P.SHEET["TEXT"])
		ty += 9

func _hline_px(sheet: Image, xa: int, xb: int, y: int, col: Color) -> void:
	for xx in range(mini(xa, xb), maxi(xa, xb) + 1):
		_put(sheet, xx, y, col)

# ================================================== бортовой шрифт 3x5
## Глифы игры НЕ цитируются: собственный чертёжный шрифт инструмента
## (тот же эталон, что sheet_env_v1 / sheet_feel_v1 / sheet_weapons_v1).

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
								_put(img, x + c * sc + dx, y0 + r * sc + dy, col)
		x += 4 * sc
	return x - x0 - sc
