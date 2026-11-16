extends RefCounted
## forest_paint.gd — статический генератор листа-вердикта «Лес v1» (w3, аудит c26 §2/§5).
##
## Единственный источник цвета — PixelPalette (RAMPS зоны «Лес/деревня»);
## ДЕЛЬТА ПАЛИТРЫ = ПУСТО: ни одного нового цвета/рампа — только GRASS/PATH/
## WOOD/BARK/STONE/LEAF/PINE (+HP_RED/BONE на мухоморах). Рампа C (VIOLET) не
## трогается и в лес не заходит: лес остаётся зелёным, с пещерой не спорит.
##
## Резец — тот же, что у утверждённой «Деревни v4» (sheet_village.gd) и пещеры
## (cave_paint.gd): хелперы (blob/canon_pass/шум/обводка) берутся из
## cave_paint.gd, кроны/пни/камни повторяют геометрию v4-листа 1:1 (рубы
## переиспользуются, новых силуетов-конкурентов не заводим).
##
## Детерминизм: ноль randi — только хэш-шум hp()/hashf() с фиксированными
## офсетами; bake многократен до байта (двойной прогон → равные md5).
##
## Свай (покачивание) — кандидаты 3 фаз (A покой / B −1px / C +1px): кадр
## считается ФУНКЦИЕЙ ОТ РИСОВКИ (строки крон выше пивота сдвинуты с тейпером),
## рантайм-план — тот же прецедент c7/c9: overlay-спрайты/смена кадра по
## int(t/T)%3 с фазой из хэша клетки, ни одного физ-узла, тайлмап не мутируется.

const P := preload("res://scripts/pixel_palette.gd")
const CP := preload("res://tools_art/cave_paint.gd")

static func C(rn: String, tone: int) -> Color:
	return P.r(rn)[tone]

static func im(w: int, h: int) -> Image:
	return CP.im(w, h)

static func px(img: Image, x: int, y: int, col: Color) -> void:
	CP.px(img, x, y, col)

static func pxw(img: Image, x: int, y: int, col: Color) -> void:
	CP.pxw(img, x, y, col)

static func rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	CP.rect(img, x0, y0, x1, y1, col)

static func linew(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	CP.linew(img, x0, y0, x1, y1, col)

static func hp(x: int, y: int) -> float:
	return CP.hp(x, y)

# ============================================================ ПОЛЫ (16×16, бесшовные поверхности)

static func _litter_base(img: Image, ox: int, oy: int) -> void:
	## Подстица: тёмный притенённый дёрн + листвяный сор + хвоинки. Шум hp с
	## офсетами; всё, что касается краёв, заворачивается pxw — период 16.
	img.fill(C("GRASS", P.T_DARK))
	for y in 16:
		for x in 16:
			var h := hp(x + ox, y + oy)
			if h < 0.10:
				pxw(img, x, y, C("GRASS", P.T_MID))
			elif h < 0.04:
				pxw(img, x, y, C("GRASS", P.T_LIGHT))
			elif h > 0.955:
				pxw(img, x, y, C("GRASS", P.T_OUTLINE))
	# листовой сор: одиночные пиксели листвы (СЗ-ориентированные «запятые»)
	for i in 9:
		var hx := int(hp(ox + i * 7, oy + 3) * 15.99)
		var hy := int(hp(ox + i * 13, oy + 11) * 15.99)
		var leaf := C("LEAF", P.T_MID) if hp(hx + ox, hy + oy) > 0.5 else C("LEAF", P.T_DARK)
		pxw(img, hx, hy, leaf)
		pxw(img, hx + 1, hy, C("LEAF", P.T_LIGHT))
	# хвоинки: короткие штрихи PINE DARK (закручиваются через шов)
	linew(img, 2, 6, 4, 6, C("PINE", P.T_DARK))
	linew(img, 10, 12, 12, 13, C("PINE", P.T_DARK))
	pxw(img, 7, 3, C("PINE", P.T_MID))


static func build_floor_litter() -> Image:  # FFLR
	var img := im(16, 16)
	_litter_base(img, 3, 5)
	# сучок под ногами (кольцом через шов y=14, горизонтальный непрерывный цикл)
	linew(img, -1, 14, 2, 14, C("BARK", P.T_DARK))
	linew(img, 2, 14, 5, 13, C("BARK", P.T_MID))
	linew(img, 5, 13, 8, 14, C("BARK", P.T_DARK))
	linew(img, 8, 14, 16, 14, C("BARK", P.T_DARK))
	pxw(img, 4, 13, C("BARK", P.T_LIGHT))
	return img


static func build_floor_litter2() -> Image:  # FFLR2
	var img := im(16, 16)
	_litter_base(img, 11, 17)
	# папоротневая тень внутри клетки (швы не трогает)
	rect(img, 9, 4, 11, 5, C("PINE", P.T_OUTLINE))
	px(img, 9, 4, C("PINE", P.T_DARK))
	px(img, 12, 5, C("PINE", P.T_MID))
	px(img, 3, 9, C("LEAF", P.T_DARK))
	return img


## Кромка «лес→поле» (южная граница): сверху подстица, снизу луг v4-леса
## (GRASS MID со световыми лезвиями трав). Граница — рваная линия опавшего
## листа с периодом 16 (генерируется из hp(x) — шов непрерывен).
static func build_floor_edge_s() -> Image:
	var img := im(16, 16)
	# низ — луг
	for y in 16:
		for x in 16:
			var b := hp(x + 31, y + 41)
			var col := C("GRASS", P.T_MID)
			if b < 0.14:
				col = C("GRASS", P.T_LIGHT)
			elif b > 0.90:
				col = C("GRASS", P.T_DARK)
			img.set_pixel(x, y, col)
	# лезвия трав (светлые вертикали, не на нижней кромке)
	for x in [1, 5, 10, 14]:
		pxw(img, x, 12, C("GRASS", P.T_LIGHT))
		pxw(img, x + 1, 13, C("GRASS", P.T_LIGHT))
	# верх — подстица
	for y in 16:
		for x in 16:
			if y >= 8:
				continue
			var h := hp(x + 3, y + 5)
			var col := C("GRASS", P.T_DARK)
			if h < 0.10:
				col = C("GRASS", P.T_MID)
			elif h > 0.95:
				col = C("GRASS", P.T_OUTLINE)
			img.set_pixel(x, y, col)
	# рваная граница: y_b(x) = 7/8 с зубом по хэшу; листовой подсып LEAF
	for x in 16:
		var tooth := 7 if hp(x + 77, 5) > 0.42 else 8
		for y in range(0, tooth + 1):
			var h := hp(x + 3, y + 5)
			var col := C("GRASS", P.T_DARK)
			if h < 0.10:
				col = C("GRASS", P.T_MID)
			elif h > 0.95:
				col = C("GRASS", P.T_OUTLINE)
			img.set_pixel(x, y, col)
		pxw(img, x, tooth + 1, C("LEAF", P.T_DARK) if hp(x + 19, 9) > 0.35 else C("LEAF", P.T_MID))
		if hp(x + 53, 3) > 0.62:
			pxw(img, x, tooth + 2, C("LEAF", P.T_OUTLINE))
	# травинки лезут вверх через границу
	for x in [3, 11]:
		pxw(img, x, tooth_at(x) - 1, C("GRASS", P.T_LIGHT))
		pxw(img, x, tooth_at(x), C("GRASS", P.T_LIGHT))
	# горизонтальный шов низа: нижняя строка — поле луга (бесшовно)
	return img

static func tooth_at(x: int) -> int:
	return 7 if hp(x + 77, 5) > 0.42 else 8


## Кромка «лес→поле» (восточная граница, зеркало по вертикали): слева подстица,
## справа луг.
static func build_floor_edge_e() -> Image:
	var img := im(16, 16)
	for y in 16:
		for x in 16:
			var b := hp(x + 61, y + 71)
			var col := C("GRASS", P.T_MID)
			if b < 0.14:
				col = C("GRASS", P.T_LIGHT)
			elif b > 0.90:
				col = C("GRASS", P.T_DARK)
			img.set_pixel(x, y, col)
	# восточная граница: граница — СТОЛБЕЦ t(y), слева подстица, справа луг
	for y in 16:
		var t := tooth_at2(y)
		for x in range(0, t + 1):
			var h := hp(x + 3, y + 5)
			var col := C("GRASS", P.T_DARK)
			if h < 0.10:
				col = C("GRASS", P.T_MID)
			elif h > 0.95:
				col = C("GRASS", P.T_OUTLINE)
			img.set_pixel(x, y, col)
		pxw(img, t + 1, y, C("LEAF", P.T_MID) if hp(29, y + 17) > 0.4 else C("LEAF", P.T_DARK))
		if hp(53, y + 7) > 0.62:
			pxw(img, t + 2, y, C("LEAF", P.T_OUTLINE))
	for y in [4, 12]:
		pxw(img, tooth_at2(y) + 1, y, C("GRASS", P.T_LIGHT))
	return img

static func tooth_at2(y: int) -> int:
	return 6 if hp(91, y + 13) > 0.44 else 7

# ============================================================ КРОНЫ/ДЕРЕВЬЯ (пропы со стопой)

## Общий сдвиг строк для фазы свая: rows < pivot сдвинуты на sway с тейпером
## (полный ±1 выше pivot-8, ноль у pivot). Строки рвутся по x, канон-обводка
## перепрогоняется — кромка кадра честно переобводится.
static func _sway_rows(img: Image, pivot: int, sway: int) -> void:
	if sway == 0:
		return
	var w := img.get_width()
	var h := img.get_height()
	var src: Image = img.duplicate()
	for y in range(0, pivot):
		var d := float(pivot - y) / float(maxi(pivot - 8, 1))
		var off := int(round(float(sway) * minf(d, 1.0)))
		if off == 0:
			continue
		for x in w:
			var sx: int = x - off
			var col := Color(0, 0, 0, 0) if sx < 0 or sx >= w else src.get_pixel(sx, y)
			img.set_pixel(x, y, col)

static func _pine_core(h_tiers: Array, w: int, cx: int, trunk_top: int, trunk_h: int) -> Image:
	## Ярусная ель: тот же алгоритм лап, что v4 PINE (аппроксимация v4 1:1 для
	## полного роста; для меньших — те же пропорции maxhw/tiers).
	var img := im(w, trunk_top + trunk_h)
	for y in range(trunk_top, img.get_height()):
		_px(img, cx - 1, y, C("BARK", P.T_LIGHT))
		_px(img, cx, y, C("BARK", P.T_MID))
		_px(img, cx + 1, y, C("BARK", P.T_DARK))
	var base := img.get_height() - 1
	_rect(img, cx - 3, base - 2, cx - 2, base, C("BARK", P.T_MID))
	_rect(img, cx + 2, base - 2, cx + 3, base, C("BARK", P.T_DARK))
	for t in h_tiers:
		var apex: int = t[0]
		var bottom: int = t[1]
		var maxhw: int = t[2]
		for y in range(apex, bottom + 1):
			var hw := int(float(maxhw) * float(y - apex + 1) / float(bottom - apex + 1))
			for x in range(cx - hw, cx + hw + 1):
				var tone := P.T_MID
				if x == cx - hw or x == cx + hw:
					tone = P.T_DARK
				if y == bottom:
					tone = P.T_DARK
				if y <= apex + 1:
					tone = P.T_LIGHT
				_px(img, x, y, C("PINE", tone))
	# живая неравномерность нижних ярусов (тот же приём v4)
	for y in h_tiers.map(func(t): return int(t[1])):
		for x in range(0, w):
			if img.get_pixel(x, y).a > 0.5 and y - 1 >= 0 and img.get_pixel(x, y - 1).a < 0.5 and hp(x, y) < 0.4:
				_px(img, x, y, C("PINE", P.T_LIGHT))
	return img

static func _px(img: Image, x: int, y: int, col: Color) -> void:
	CP.px(img, x, y, col)

static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	CP.rect(img, x0, y0, x1, y1, col)

## Ель полная 29×48 — геометрия v4 PINE 1:1 (утверждённый резец).
static func build_pine_t1(sway: int = 0) -> Image:
	var img := _pine_core([[24, 40, 14], [12, 28, 12], [5, 16, 9], [0, 7, 6]], 29, 14, 38, 10)
	_px(img, 12, 46, C("GRASS", P.T_LIGHT))
	_px(img, 18, 46, C("GRASS", P.T_MID))
	_sway_rows(img, 41, sway)
	CP.canon_pass(img)
	return img

## Ель средняя 22×34 — тот же рубило, 3 яруса (просеки/гуща).
static func build_pine_t2(sway: int = 0) -> Image:
	var img := _pine_core([[16, 27, 10], [7, 18, 8], [0, 9, 5]], 22, 11, 26, 8)
	_px(img, 9, 32, C("GRASS", P.T_LIGHT))
	_px(img, 14, 32, C("GRASS", P.T_MID))
	_sway_rows(img, 28, sway)
	CP.canon_pass(img)
	return img

## Дуб 45×44 — геометрия v4 OAK 1:1 (лиственный ярус для «Т»-просветов).
static func build_oak_t(sway: int = 0) -> Image:
	var img := im(45, 44)
	for y in range(26, 44):
		_px(img, 20, y, C("BARK", P.T_LIGHT))
		for x in range(21, 24):
			_px(img, x, y, C("BARK", P.T_MID))
		_px(img, 24, y, C("BARK", P.T_DARK))
	_px(img, 22, 30, C("BARK", P.T_DARK))
	_px(img, 21, 35, C("BARK", P.T_DARK))
	_px(img, 23, 39, C("BARK", P.T_DARK))
	_rect(img, 18, 41, 19, 43, C("BARK", P.T_MID))
	_rect(img, 25, 41, 26, 43, C("BARK", P.T_DARK))
	_px(img, 17, 43, C("BARK", P.T_DARK))
	_px(img, 27, 43, C("BARK", P.T_DARK))
	var lobes := [
		[11, 13, 8.0, 7.0], [22, 9, 10.0, 8.0], [34, 13, 8.0, 7.0],
		[8, 20, 7.0, 6.5], [37, 20, 7.0, 6.5], [22, 18, 13.5, 12.0],
		[15, 22, 8.5, 7.0], [29, 22, 8.5, 7.0],
	]
	for y in range(0, 32):
		for x in range(0, 45):
			for lb in lobes:
				var nx := float(x - int(lb[0])) / float(lb[2])
				var ny := float(y - int(lb[1])) / float(lb[3])
				if nx * nx + ny * ny <= 1.0:
					var col := C("LEAF", P.T_MID)
					var hv := hp(x, y)
					if (y <= 7 and x <= 22 and hv < 0.32) or (hv < 0.08 and y < 16):
						col = C("LEAF", P.T_LIGHT)
					elif hv < 0.10 and y >= 24:
						col = C("LEAF", P.T_DARK)
					img.set_pixel(x, y, col)
					break
	img.set_pixel(5, 18, Color(0, 0, 0, 0))
	img.set_pixel(40, 14, Color(0, 0, 0, 0))
	img.set_pixel(24, 29, Color(0, 0, 0, 0))
	img.set_pixel(16, 27, Color(0, 0, 0, 0))
	_px(img, 15, 42, C("GRASS", P.T_LIGHT))
	_px(img, 29, 42, C("GRASS", P.T_LIGHT))
	_px(img, 30, 42, C("GRASS", P.T_MID))
	_sway_rows(img, 33, sway)
	CP.canon_pass(img)
	return img

# ============================================================ КУСТЫ (prop, 3 фазы свая)

static func build_bush(sway: int = 0) -> Image:
	var img := im(14, 12)
	CP.blob(img, 4, 6, 3.6, 3.4, "LEAF")
	CP.blob(img, 10, 7, 3.2, 3.0, "LEAF")
	CP.blob(img, 7, 4, 4.0, 3.0, "LEAF")
	# ветки у ноги
	_px(img, 6, 10, C("BARK", P.T_MID))
	_px(img, 7, 10, C("BARK", P.T_DARK))
	_px(img, 8, 10, C("BARK", P.T_MID))
	# ягоды — акцент HP_RED (палитра UI-рампы легальна как материал-акцент? НЕТ:
	# §1 — только рампы зоны. Ягоды красим CLOTH (лесной красный ресурс Драна/тряпица).
	_px(img, 3, 5, C("CLOTH", P.T_MID))
	_px(img, 11, 6, C("CLOTH", P.T_MID))
	_px(img, 7, 3, C("CLOTH", P.T_LIGHT))
	# светлые кончики верхних веток
	for x in range(2, 12):
		if img.get_pixel(x, 2).a > 0.5 and img.get_pixel(x, 1).a < 0.5 and hp(x, 2) < 0.5:
			_px(img, x, 2, C("LEAF", P.T_LIGHT))
	_sway_rows(img, 10, sway)
	CP.canon_pass(img)
	return img

static func build_bush2(sway: int = 0) -> Image:
	var img := im(12, 10)
	CP.blob(img, 4, 5, 3.2, 3.0, "PINE")
	CP.blob(img, 9, 6, 2.6, 2.6, "PINE")
	_px(img, 5, 8, C("BARK", P.T_MID))
	_px(img, 6, 8, C("BARK", P.T_DARK))
	for x in range(2, 10):
		if img.get_pixel(x, 2).a > 0.5 and img.get_pixel(x, 1).a < 0.5 and hp(x + 9, 4) < 0.5:
			_px(img, x, 2, C("PINE", P.T_LIGHT))
	_sway_rows(img, 8, sway)
	CP.canon_pass(img)
	return img

# ============================================================ ДЕКОР (пни/камни/мухоморы/папоротник)

static func build_stump_f() -> Image:
	## Пень 11×8 — v4 STUMP + мох щедрее (лесная влага).
	var img := im(11, 8)
	for x in range(1, 6):
		_px(img, x, 0, C("GRASS", P.T_MID) if hp(x, 61) > 0.35 else C("GRASS", P.T_LIGHT))
	_px(img, 3, 1, C("WOOD", P.T_LIGHT))
	_rect(img, 4, 1, 7, 1, C("WOOD", P.T_MID))
	_px(img, 5, 1, C("WOOD", P.T_DARK))
	_rect(img, 2, 2, 8, 2, C("WOOD", P.T_LIGHT))
	_px(img, 6, 2, C("WOOD", P.T_MID))
	_px(img, 1, 2, C("BARK", P.T_DARK))
	_px(img, 9, 2, C("BARK", P.T_DARK))
	for y in range(3, 7):
		_px(img, 0, y, C("BARK", P.T_DARK))
		_px(img, 1, y, C("BARK", P.T_LIGHT))
		for x in range(2, 9):
			_px(img, x, y, C("BARK", P.T_MID))
		_px(img, 3, y, C("BARK", P.T_DARK))
		_px(img, 7, y, C("BARK", P.T_DARK))
		_px(img, 9, y, C("BARK", P.T_MID))
		_px(img, 10, y, C("BARK", P.T_DARK))
	_px(img, 0, 6, C("GRASS", P.T_MID))
	_px(img, 10, 6, C("GRASS", P.T_MID))
	# мох боковой (лесная версия — пятно на СЗ-грани)
	_px(img, 1, 4, C("GRASS", P.T_MID))
	_px(img, 1, 5, C("GRASS", P.T_LIGHT))
	_px(img, 2, 5, C("GRASS", P.T_MID))
	_rect(img, 0, 7, 1, 7, C("BARK", P.T_DARK))
	_rect(img, 3, 7, 7, 7, C("BARK", P.T_MID))
	_rect(img, 9, 7, 10, 7, C("BARK", P.T_DARK))
	CP.canon_pass(img)
	return img

static func build_stump_f2() -> Image:
	## Пень-коряжка 8×6 — мелкий, сросшийся с подстицей.
	var img := im(8, 6)
	_px(img, 1, 0, C("GRASS", P.T_LIGHT))
	_px(img, 2, 0, C("GRASS", P.T_MID))
	_rect(img, 2, 1, 5, 1, C("WOOD", P.T_LIGHT))
	_px(img, 4, 1, C("WOOD", P.T_DARK))
	for y in range(2, 5):
		_px(img, 0, y, C("BARK", P.T_DARK))
		for x in range(1, 6):
			_px(img, x, y, C("BARK", P.T_MID))
		_px(img, 3, y, C("BARK", P.T_DARK))
		_px(img, 6, y, C("BARK", P.T_DARK))
		_px(img, 7, y, C("BARK", P.T_DARK))
	_rect(img, 1, 5, 2, 5, C("BARK", P.T_DARK))
	_rect(img, 4, 5, 6, 5, C("BARK", P.T_DARK))
	CP.canon_pass(img)
	return img

static func build_stones_f() -> Image:
	## Семейка камней 15×12 — v4 STONES + мох.
	var img := im(15, 12)
	CP.blob(img, 5, 7, 4.6, 4.2, "STONE")
	CP.blob(img, 12, 8, 2.8, 2.8, "STONE")
	_px(img, 3, 4, C("STONE", P.T_LIGHT))
	_px(img, 4, 3, C("STONE", P.T_LIGHT))
	_px(img, 10, 6, C("STONE", P.T_LIGHT))
	_px(img, 6, 7, C("STONE", P.T_DARK))
	_px(img, 7, 8, C("STONE", P.T_DARK))
	_px(img, 12, 9, C("STONE", P.T_DARK))
	_px(img, 8, 9, C("GRASS", P.T_LIGHT))
	_px(img, 9, 8, C("GRASS", P.T_MID))
	_px(img, 1, 9, C("GRASS", P.T_MID))
	for x in range(3, 8):
		if img.get_pixel(x, 3).a > 0.5 and hp(x, 81) < 0.45:
			_px(img, x, 3, C("GRASS", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_stone_m() -> Image:
	## Одинокий валун 11×7 — мелкий, «северный» мох.
	var img := im(11, 7)
	CP.blob(img, 5, 4, 4.6, 3.2, "STONE")
	_px(img, 3, 2, C("STONE", P.T_LIGHT))
	_px(img, 4, 1, C("STONE", P.T_LIGHT))
	_px(img, 6, 4, C("STONE", P.T_DARK))
	_px(img, 4, 1, C("GRASS", P.T_MID))
	_px(img, 5, 1, C("GRASS", P.T_LIGHT))
	_px(img, 9, 5, C("GRASS", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_shroom1() -> Image:
	## Мухомор 7×7: шляпка HP_RED (единственный красный акцент леса),
	## ножка/крапинки BONE. Ноль FIRE/CLOTH.
	var img := im(7, 7)
	# ножка
	for y in range(3, 6):
		_px(img, 3, y, C("BONE", P.T_MID))
		_px(img, 4, y, C("BONE", P.T_DARK))
	_px(img, 3, 6, C("BONE", P.T_OUTLINE))
	_px(img, 4, 6, C("BONE", P.T_OUTLINE))
	# шляпка
	_rect(img, 1, 1, 5, 1, C("HP_RED", P.T_MID))
	_rect(img, 0, 2, 6, 3, C("HP_RED", P.T_MID))
	_px(img, 1, 2, C("HP_RED", P.T_LIGHT))
	_px(img, 2, 1, C("HP_RED", P.T_LIGHT))
	_px(img, 5, 3, C("HP_RED", P.T_DARK))
	_px(img, 6, 3, C("HP_RED", P.T_DARK))
	# крапины
	_px(img, 2, 2, C("BONE", P.T_LIGHT))
	_px(img, 4, 2, C("BONE", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_shroom2() -> Image:
	## Семейка мухоморов 10×8 (большой + два малыша).
	var img := im(10, 8)
	for y in range(4, 7):
		_px(img, 6, y, C("BONE", P.T_MID))
		_px(img, 7, y, C("BONE", P.T_DARK))
	_px(img, 6, 7, C("BONE", P.T_OUTLINE))
	_px(img, 7, 7, C("BONE", P.T_OUTLINE))
	_rect(img, 4, 2, 9, 2, C("HP_RED", P.T_MID))
	_rect(img, 4, 3, 9, 4, C("HP_RED", P.T_MID))
	_px(img, 5, 2, C("HP_RED", P.T_LIGHT))
	_px(img, 4, 2, C("HP_RED", P.T_LIGHT))
	_px(img, 9, 4, C("HP_RED", P.T_DARK))
	_px(img, 6, 3, C("BONE", P.T_LIGHT))
	_px(img, 8, 3, C("BONE", P.T_MID))
	# малыш
	_px(img, 1, 6, C("BONE", P.T_MID))
	_px(img, 1, 7, C("BONE", P.T_OUTLINE))
	_rect(img, 0, 5, 2, 5, C("HP_RED", P.T_MID))
	_px(img, 0, 5, C("HP_RED", P.T_LIGHT))
	_px(img, 1, 5, C("BONE", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_fern() -> Image:
	## Папоротник 13×10: три вайи PINE, кончики LEAF-подсветкой.
	var img := im(13, 10)
	for i in 3:
		var cx := 2 + i * 4
		for y in range(2, 9):
			var x := cx + (0 if y > 6 else (i - 1))
			_px(img, x, y, C("PINE", P.T_MID))
			if y % 2 == 0:
				_px(img, x - 1, y, C("PINE", P.T_DARK))
				_px(img, x + 1, y, C("PINE", P.T_DARK))
		_px(img, cx + (i - 1), 2, C("LEAF", P.T_LIGHT))
	_px(img, 5, 9, C("PINE", P.T_OUTLINE))
	_px(img, 6, 9, C("PINE", P.T_OUTLINE))
	_px(img, 9, 9, C("PINE", P.T_OUTLINE))
	CP.canon_pass(img)
	return img

static func build_fern2() -> Image:
	## Папоротник малый 9×6 — канонный «веер»: сплошная ворска с наклонными
	## плечами (канон-пасс сам кладёт LIGHT по открытым СЗ-граням).
	var img := im(9, 6)
	var rows := [[4, 4], [3, 5], [2, 6], [2, 7], [1, 7], [1, 7]]
	for y in rows.size():
		for x in range(rows[y][0], rows[y][1] + 1):
			_px(img, x, y, C("PINE", P.T_MID))
	# жилки-щелины (внутри тела, кромки не рвём)
	_px(img, 4, 2, C("PINE", P.T_DARK))
	_px(img, 3, 4, C("PINE", P.T_DARK))
	_px(img, 6, 4, C("PINE", P.T_DARK))
	# кончик светлый листовой
	_px(img, 4, 0, C("LEAF", P.T_LIGHT))
	_px(img, 3, 1, C("LEAF", P.T_LIGHT))
	CP.canon_pass(img)
	return img

# ============================================================ НАБОРЫ

static func floor_tile_set() -> Array:
	return [
		{"name": "FFLR", "short": "FFLR", "img": build_floor_litter()},
		{"name": "FFLR2", "short": "FFLR2", "img": build_floor_litter2()},
		{"name": "FEDGE_S", "short": "EDG-S", "img": build_floor_edge_s()},
		{"name": "FEDGE_E", "short": "EDG-E", "img": build_floor_edge_e()},
	]

## Пропы (статичные кадры; фазы свая A==покой — тот же кадр).
static func prop_set_canon() -> Array:
	var out: Array = []
	out.append({"name": "PINE_T1", "canon": "3.0H", "img": build_pine_t1(0)})
	out.append({"name": "PINE_T2", "canon": "2.1H", "img": build_pine_t2(0)})
	out.append({"name": "OAK_T", "canon": "3.0H fit", "img": build_oak_t(0)})
	out.append({"name": "BUSH", "canon": "0.7H", "img": build_bush(0)})
	out.append({"name": "BUSH2", "canon": "0.6H", "img": build_bush2(0)})
	out.append({"name": "STUMP_F", "canon": "0.55H", "img": build_stump_f()})
	out.append({"name": "STUMP_F2", "canon": "0.4H", "img": build_stump_f2()})
	out.append({"name": "STONES_F", "canon": "0.75H", "img": build_stones_f()})
	out.append({"name": "STONE_M", "canon": "0.5H", "img": build_stone_m()})
	out.append({"name": "SHROOM1", "canon": "0.4H", "img": build_shroom1()})
	out.append({"name": "SHROOM2", "canon": "0.5H", "img": build_shroom2()})
	out.append({"name": "FERN", "canon": "0.6H", "img": build_fern()})
	out.append({"name": "FERN2", "canon": "0.4H", "img": build_fern2()})
	return out

static func sway_triplet(label: String, canon: String, f: Callable) -> Array:
	return [
		{"name": label + "_A", "canon": canon, "img": f.call(0)},
		{"name": label + "_B", "canon": canon, "img": f.call(-1)},
		{"name": label + "_C", "canon": canon, "img": f.call(1)},
	]

# ============================================================ BAKE

## Печать атласов: пол 4×16=64×16; пропы — alpha-trim кадры (как пещера,
## caves trim). Манифест REGIONS вычисляется из фактических trim — детерминизм.
static func bake_floor_atlas() -> Image:
	var tiles := floor_tile_set()
	var out := im(tiles.size() * 16, 16)
	for i in tiles.size():
		out.blit_rect(tiles[i]["img"], Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
	return out

static func bake_list() -> Array:
	## Что едет в атлас пропов: статичные + ТРИ фазы качающихся.
	var out: Array = []
	for s in prop_set_canon():
		out.append(s)
	for g in [["PINE_T1", "3.0H", build_pine_t1], ["OAK_T", "3.0H fit", build_oak_t],
			["BUSH", "0.7H", build_bush], ["BUSH2", "0.6H", build_bush2]]:
		out.append({"name": String(g[0]) + "_B", "canon": String(g[1]), "img": (g[2] as Callable).call(-1)})
		out.append({"name": String(g[0]) + "_C", "canon": String(g[1]), "img": (g[2] as Callable).call(1)})
	return out

static func bake_props_atlas() -> Dictionary:
	## Упаковка: строки слева направо, перенос при переполнении (детерминированно).
	## В манифесте — x/y/w/h кадра в атласе + off_x/off_y trim-смещения оригинала
	## (нужны интеграции для стопного якоря, как CaveArt.REGIONS).
	var sprites := bake_list()
	var pad := 2
	var W := 160
	var x := 0
	var y := 0
	var row_h := 0
	var places := {}
	var trims := {}
	for s in sprites:
		var img: Image = s["img"]
		var t: Dictionary = CP.trim(img)
		var timg: Image = t["img"]
		var w2: int = timg.get_width()
		var h2: int = timg.get_height()
		if x + w2 + pad > W:
			x = 0
			y += row_h + pad
			row_h = 0
		var nm := String(s["name"])
		places[nm] = {"x": x, "y": y, "w": w2, "h": h2, "off_x": int(t["x"]), "off_y": int(t["y"])}
		trims[nm] = timg
		x += w2 + pad
		row_h = maxi(row_h, h2)
	var H: int = y + row_h + pad
	var out := im(W, H)
	out.fill(Color(0, 0, 0, 0))
	for nm in places:
		var p: Dictionary = places[nm]
		var timg: Image = trims[nm]
		out.blit_rect(timg, Rect2i(0, 0, int(p["w"]), int(p["h"])), Vector2i(int(p["x"]), int(p["y"])))
	return {"img": out, "regions": places, "size": Vector2i(W, H)}
