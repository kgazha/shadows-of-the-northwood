extends RefCounted
## CavePaint — генератор арта «Пещера v1» (волна c1/c3, docs/PIXEL_STYLE.md).
##
## Статический модуль рисовки: единственные источники пикселя — код и
## PixelPalette; никаких randi (фикс. сид SEED + периодический хэш-шум).
## Используется двояко:
##  - res://tools_art/sheet_cave.gd — лист-вердикт и режим bake (файлы атласов);
##  - QA-стенды — побайтовый rebake in-process против закоммиченных атласов
##    (пин детерминизма: атлас в репозитории == свежий прогон генератора).
##
## Раскладка атласов пропов — единственный источник истины
## CaveArt.REGIONS (scripts/cave_art.gd); bake сверяет размеры и не рисует
## ничего вне регионов. Кадры пропов проходят alpha-trim до видимого силуэта
## (аудит c2, F2: в кадре нет пустых полей, нога/аутлайн на нижней границе).

const P := preload("res://scripts/pixel_palette.gd")

const SEED := 4321  # фикс. сид шумов (детерминизм без randi)

static var _idx := {}

## argb32 -> [ramp, tone] (ленивая кэшированная карта палитры).
static func idx_map() -> Dictionary:
	if _idx.is_empty():
		_idx = P.color_index()
	return _idx


static func C(rn: String, tone: int) -> Color:
	return P.r(rn)[tone]


static func im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


static func rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			px(img, x, y, col)


static func line(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	while true:
		px(img, x0, y0, col)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy


## Тайловые штрихи с заворачиванием по модулю — трещина/рисунок «вылезает» за
## край и продолжается на противоположной стороне: бесшовность по построению.
static func pxw(img: Image, x: int, y: int, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	img.set_pixel(posmod(x, w), posmod(y, h), col)


static func linew(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	while true:
		pxw(img, x0, y0, col)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy


## Детерминированный шум (аналог sheet_village), с фиксированным сидом SEED.
## Имя hashf: глобальный hash() в GDScript — встроенный (1 аргумент).
static func hashf(x: int, y: int) -> float:
	return fposmod(sin(float(x) * 127.1 + float(y) * 311.7 + float(SEED) * 0.7) * 43758.5453, 1.0)


## Тот же шум, периодический ровно 16 px по обеим осям (для тайлов).
static func hp(x: int, y: int) -> float:
	return hashf(posmod(x, 16), posmod(y, 16))


static func blob(img: Image, cx: int, cy: int, rx: float, ry: float, rn: String) -> void:
	var mid := C(rn, P.T_MID)
	for y in range(cy - int(ry) - 1, cy + int(ry) + 2):
		for x in range(cx - int(rx) - 1, cx + int(rx) + 2):
			var nx := float(x - cx) / rx
			var ny := float(y - cy) / ry
			if nx * nx + ny * ny <= 1.15:
				px(img, x, y, mid)


## Единый прогон канона (копия эталона sheet_village.gd): OUTLINE снизу и по
## бокам, LIGHT-подсветка северо-запада. Применяется к СИЛУЭТАМ; к
## тайлам-поверхностям — нет.
static func canon_pass(img: Image) -> void:
	var idx := idx_map()
	var w := img.get_width()
	var h := img.get_height()
	var src: Image = img.duplicate()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a < 0.5:
				continue
			var col := src.get_pixel(x, y)
			var info = idx.get(P.key(col))
			if info == null:
				continue
			var rn := String(info[0])
			var tone := int(info[1])
			if not P.RAMPS.has(rn):
				continue
			var ramp: Array = P.RAMPS[rn]
			var open_below := y == h - 1 or src.get_pixel(x, y + 1).a < 0.5
			var open_right := x == w - 1 or src.get_pixel(x + 1, y).a < 0.5
			var open_left := x == 0 or src.get_pixel(x - 1, y).a < 0.5
			var open_up := y == 0 or src.get_pixel(x, y - 1).a < 0.5
			var open_ul := (x > 0 and y > 0) and src.get_pixel(x - 1, y - 1).a < 0.5
			if open_below:
				img.set_pixel(x, y, ramp[P.T_OUTLINE])
			elif open_right and tone != P.T_OUTLINE:
				img.set_pixel(x, y, ramp[P.T_DARK])
			elif (open_up or open_left or open_ul) and (tone == P.T_MID or tone == P.T_DARK):
				img.set_pixel(x, y, ramp[P.T_LIGHT])


## FNV-1a 32 (канон world._env4_hash): CONTENT-HASH по PNG-байтам.
static func fnv32(bytes: PackedByteArray) -> int:
	var h := 2166136261
	for b in bytes:
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return h


static func img_hash(img: Image) -> String:
	return "%08X" % fnv32(img.save_png_to_buffer())


# ------------------------------------------------------------------ тайлы: пол
## Пол/стена — 16×16 поверхности. Весь шум периодичен с периодом ровно 16, а
## трещины рисуются с заворачиванием по модулю => соседство тайл↔тайл
## статистически неотличимо от соседства колонок внутри тайла (пин-метрика
## шва в sheet_cave.gd / qa_lp).

## Пол обычный: базальт CAVE_ROCK с редкими вкраплениями и двумя гальками.
static func build_floor_cave() -> Image:
	var img := im(16, 16)
	img.fill(C("CAVE_ROCK", P.T_MID))
	for y in 16:
		for x in 16:
			var h := hp(x, y)
			if h < 0.12:
				pxw(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
			elif h > 0.91:
				pxw(img, x, y, C("CAVE_ROCK", P.T_DARK))
	# гальки: тёмное зерно + СЗ-искорка
	linew(img, 3, 4, 4, 5, C("CAVE_ROCK", P.T_DARK))
	px(img, 3, 4, C("CAVE_ROCK", P.T_LIGHT))
	linew(img, 11, 10, 12, 11, C("CAVE_ROCK", P.T_DARK))
	px(img, 11, 10, C("CAVE_ROCK", P.T_LIGHT))
	# единственная волосяная трещинка (заворачивается по модулю)
	linew(img, 7, 13, 9, 14, C("CAVE_ROCK", P.T_OUTLINE))
	px(img, 8, 13, C("CAVE_ROCK", P.T_DARK))
	return img


## Пол с трещинами: расщелина идёт ГОРИЗОНТАЛЬНО и входит/выходит на одной
## строке y=12 (x=-1 ↔ x=16) — при тайлинге трещина непрерывна через шов;
## вертикальный шов (y15↔y0) трещина и лужа не задевают.
static func build_floor_crack() -> Image:
	var img := im(16, 16)
	img.fill(C("CAVE_ROCK", P.T_MID))
	for y in 16:
		for x in 16:
			var h := hp(x + 5, y + 9)
			if h < 0.10:
				pxw(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
			elif h > 0.93:
				pxw(img, x, y, C("CAVE_ROCK", P.T_DARK))
	# главная расщелина (O-ядро): (−1,12)≡(15,11+) ↔ (16,12)≡(0,12) — кольцо
	linew(img, -1, 12, 3, 10, C("CAVE_ROCK", P.T_OUTLINE))
	linew(img, 3, 10, 7, 13, C("CAVE_ROCK", P.T_OUTLINE))
	linew(img, 7, 13, 11, 9, C("CAVE_ROCK", P.T_OUTLINE))
	linew(img, 11, 9, 16, 12, C("CAVE_ROCK", P.T_OUTLINE))
	# СЗ-кромка отколотого края светлее, ЮВ-губа в тени
	linew(img, -1, 11, 3, 9, C("CAVE_ROCK", P.T_LIGHT))
	linew(img, 4, 9, 7, 12, C("CAVE_ROCK", P.T_LIGHT))
	linew(img, 8, 12, 11, 8, C("CAVE_ROCK", P.T_LIGHT))
	linew(img, 12, 9, 16, 11, C("CAVE_ROCK", P.T_LIGHT))
	linew(img, 0, 13, 3, 11, C("CAVE_ROCK", P.T_DARK))
	linew(img, 4, 12, 7, 14, C("CAVE_ROCK", P.T_DARK))
	linew(img, 8, 14, 11, 10, C("CAVE_ROCK", P.T_DARK))
	# отросток вверх (заканчивается внутри тайла)
	linew(img, 7, 13, 8, 16, C("CAVE_ROCK", P.T_OUTLINE))
	px(img, 8, 15, C("CAVE_ROCK", P.T_DARK))
	# осыпь у трещины
	px(img, 5, 12, C("CAVE_ROCK", P.T_DARK))
	px(img, 5, 11, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 9, 8, C("CAVE_ROCK", P.T_DARK))
	px(img, 9, 7, C("CAVE_ROCK", P.T_LIGHT))
	# сырая лужа (внутри rows 9..14, cols 1..5 — швы не трогает)
	rect(img, 2, 10, 4, 11, C("CAVE_WATER", P.T_MID))
	px(img, 2, 10, C("CAVE_WATER", P.T_LIGHT))
	px(img, 4, 11, C("CAVE_WATER", P.T_DARK))
	px(img, 1, 11, C("CAVE_WATER", P.T_OUTLINE))
	px(img, 5, 11, C("CAVE_WATER", P.T_OUTLINE))
	px(img, 3, 12, C("CAVE_WATER", P.T_OUTLINE))
	px(img, 2, 12, C("CAVE_WATER", P.T_OUTLINE))
	px(img, 4, 12, C("CAVE_WATER", P.T_OUTLINE))
	return img


## Пол у алтаря: тёсаные плиты со стыками (DARK-борозда + LIGHT-блик у нижнего
## стыка), полировка светлее, вставка-кристалл в центре (не касается краёв).
static func build_floor_altar() -> Image:
	var img := im(16, 16)
	img.fill(C("CAVE_ROCK", P.T_MID))
	for y in 16:
		for x in 16:
			var h := hp(x + 11, y + 3)
			if h < 0.22:
				pxw(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
			elif h > 0.95:
				pxw(img, x, y, C("CAVE_ROCK", P.T_DARK))
	# горизонтальные стыки плит (полные линии => шов слева/справа целый)
	for yy in [5, 11]:
		linew(img, 0, yy, 15, yy, C("CAVE_ROCK", P.T_DARK))
		linew(img, 0, yy + 1, 15, yy + 1, C("CAVE_ROCK", P.T_LIGHT))
	# вертикальные стыки вразбежку (не на x=0/x=15 — вертикальный шов целый)
	line(img, 8, 0, 8, 5, C("CAVE_ROCK", P.T_DARK))
	line(img, 9, 1, 9, 5, C("CAVE_ROCK", P.T_LIGHT))
	line(img, 3, 6, 3, 11, C("CAVE_ROCK", P.T_DARK))
	line(img, 4, 6, 4, 11, C("CAVE_ROCK", P.T_LIGHT))
	line(img, 12, 6, 12, 11, C("CAVE_ROCK", P.T_DARK))
	line(img, 13, 6, 13, 11, C("CAVE_ROCK", P.T_LIGHT))
	line(img, 6, 12, 6, 15, C("CAVE_ROCK", P.T_DARK))
	line(img, 7, 12, 7, 15, C("CAVE_ROCK", P.T_LIGHT))
	# вставка-кристалл в центре храма
	rect(img, 7, 8, 9, 10, C("CRYSTAL", P.T_MID))
	px(img, 7, 8, C("CRYSTAL", P.T_LIGHT))
	px(img, 8, 8, C("CRYSTAL", P.T_LIGHT))
	px(img, 9, 10, C("CRYSTAL", P.T_DARK))
	px(img, 7, 11, C("CRYSTAL", P.T_OUTLINE))
	px(img, 8, 11, C("CRYSTAL", P.T_OUTLINE))
	px(img, 9, 11, C("CRYSTAL", P.T_OUTLINE))
	return img


## Пол со мхом: тот же базальт + два мшистых пятна MOSS_GLOW (свечение из
## центра пятна — канон самоизлучающих), полностью внутри тайла.
static func build_floor_moss() -> Image:
	var img := im(16, 16)
	img.fill(C("CAVE_ROCK", P.T_MID))
	for y in 16:
		for x in 16:
			var h := hp(x + 7, y + 13)
			if h < 0.11:
				pxw(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
			elif h > 0.92:
				pxw(img, x, y, C("CAVE_ROCK", P.T_DARK))
	# пятно 1 (крупное)
	blob(img, 5, 6, 3.6, 2.6, "MOSS_GLOW")
	for y in range(3, 10):
		for x in range(1, 10):
			if img.get_pixel(x, y) == C("MOSS_GLOW", P.T_MID):
				var hh := hp(x * 3 + 1, y * 5 + 2)
				if hh < 0.25:
					px(img, x, y, C("MOSS_GLOW", P.T_LIGHT))
				elif hh > 0.86:
					px(img, x, y, C("MOSS_GLOW", P.T_DARK))
	px(img, 4, 5, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 5, 5, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 2, 8, C("MOSS_GLOW", P.T_OUTLINE))
	px(img, 8, 8, C("MOSS_GLOW", P.T_OUTLINE))
	# пятно 2 (мелкое)
	blob(img, 12, 12, 2.2, 1.6, "MOSS_GLOW")
	px(img, 11, 11, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 12, 11, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 13, 13, C("MOSS_GLOW", P.T_OUTLINE))
	px(img, 10, 13, C("MOSS_GLOW", P.T_OUTLINE))
	px(img, 12, 14, C("MOSS_GLOW", P.T_OUTLINE))
	return img


# ------------------------------------------------------------------ тайлы: стены
## Стена (тело массива): плотный CAVE_ROCK, периодична по обеим осям.
static func build_wall_solid() -> Image:
	var img := im(16, 16)
	img.fill(C("CAVE_ROCK", P.T_MID))
	for y in 16:
		for x in 16:
			var h := hp(x + 3, y + 8)
			if h < 0.14:
				pxw(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
			elif h > 0.80:
				pxw(img, x, y, C("CAVE_ROCK", P.T_DARK))
			elif h > 0.74:
				pxw(img, x, y, C("CAVE_ROCK", P.T_OUTLINE))
	# сланцевые жильные трещинки (заворачиваются — шов непрерывен)
	linew(img, 1, 3, 6, 4, C("CAVE_ROCK", P.T_OUTLINE))
	px(img, 2, 3, C("CAVE_ROCK", P.T_LIGHT))
	linew(img, 10, 11, 15, 12, C("CAVE_ROCK", P.T_OUTLINE))
	px(img, 11, 11, C("CAVE_ROCK", P.T_LIGHT))
	linew(img, 9, 16, 13, 18, C("CAVE_ROCK", P.T_OUTLINE))
	return img


## Верх свода: венчающая бровка (1px LIGHT-гребень по СЗ-свету), ниже — тело.
static func build_wall_top() -> Image:
	var img := im(16, 16)
	img.fill(C("CAVE_ROCK", P.T_MID))
	for y in 16:
		for x in 16:
			var h := hp(x + 3, y + 8)
			if h < 0.14:
				pxw(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
			elif h > 0.80:
				pxw(img, x, y, C("CAVE_ROCK", P.T_DARK))
	# гребень: зубчатый LIGHT-гребешок (период 16 => шов целый)
	for x in 16:
		if hp(x, 0) > 0.32:
			pxw(img, x, 0, C("CAVE_ROCK", P.T_LIGHT))
		else:
			pxw(img, x, 0, C("CAVE_ROCK", P.T_MID))
		pxw(img, x, 1, C("CAVE_ROCK", P.T_MID) if hp(x, 1) < 0.8 else C("CAVE_ROCK", P.T_DARK))
	# тень под гребнем — 1px DARK-поясок
	for x in 16:
		if hp(x + 2, 2) > 0.55:
			pxw(img, x, 2, C("CAVE_ROCK", P.T_DARK))
	px(img, 4, 6, C("CRYSTAL", P.T_MID))
	px(img, 5, 7, C("CRYSTAL", P.T_DARK))
	px(img, 4, 7, C("CRYSTAL", P.T_LIGHT))
	return img


## Подошва стены (низ, к полу): тело + каменистая осыпь и рваная OUTLINE-юбка.
## НАПРАВЛЕННАЯ КРОМКА: по вертикали не повторяется (ставится только на нижнюю
## грань массива — пин F4 в qa_lp).
static func build_wall_bot() -> Image:
	var img := im(16, 16)
	img.fill(C("CAVE_ROCK", P.T_MID))
	for y in 13:
		for x in 16:
			var h := hp(x + 3, y + 8)
			if h < 0.14:
				pxw(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
			elif h > 0.80:
				pxw(img, x, y, C("CAVE_ROCK", P.T_DARK))
	# осыпь: гальки у подошвы
	for x in 16:
		if hp(x, 13) > 0.62:
			pxw(img, x, 13, C("CAVE_ROCK", P.T_DARK))
			pxw(img, x, 12, C("CAVE_ROCK", P.T_LIGHT))
	# рваная юбка: DARK с OUTLINE-зубцами (период 16)
	for x in 16:
		var h14 := hp(x + 4, 14)
		pxw(img, x, 14, C("CAVE_ROCK", P.T_DARK) if h14 > 0.30 else C("CAVE_ROCK", P.T_MID))
		var h15 := hp(x + 4, 15)
		pxw(img, x, 15, C("CAVE_ROCK", P.T_OUTLINE) if h15 > 0.34 else C("CAVE_ROCK", P.T_DARK))
	return img


## Угол «стена к полу», левый: массив слева, пол справа; скол-кромка с
## СЗ-бликом и теневой нитью у земли (направление — кромка, без вертикального
## репита).
static func build_wall_corner_l() -> Image:
	var img := im(16, 16)
	img.fill(C("CAVE_ROCK", P.T_MID))
	for y in 16:
		for x in 16:
			var h := hp(x + 7, y + 5)
			if h < 0.12:
				pxw(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
			elif h > 0.90:
				pxw(img, x, y, C("CAVE_ROCK", P.T_DARK))
	# кромка массива: граница «пол/камень» со ступенчатым сколом (период по y)
	for y in 16:
		var ex := 9 + (1 if hp(9, y) > 0.66 else 0) - (1 if hp(8, y) < 0.22 else 0)
		for x in range(0, ex):
			var t := P.T_MID
			var hh := hp(x + 3, y + 3)
			if hh > 0.82:
				t = P.T_DARK
			elif hh < 0.16:
				t = P.T_LIGHT
			px(img, x, y, C("CAVE_ROCK", t))
		px(img, ex - 1, y, C("CAVE_ROCK", P.T_DARK))       # открытая грань в тень
		px(img, maxi(0, ex - 2), y,
				C("CAVE_ROCK", P.T_LIGHT) if y % 4 != 3 else C("CAVE_ROCK", P.T_MID))
	px(img, 8, 3, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 7, 8, C("CAVE_ROCK", P.T_LIGHT))
	# тень перехода у земли: OUTLINE-нитка вдоль кромки + пара галек-отломков
	for y in [14, 15]:
		for x in range(9, 13):
			if hp(x, y) > 0.5:
				px(img, x, y, C("CAVE_ROCK", P.T_OUTLINE))
	px(img, 10, 12, C("CAVE_ROCK", P.T_DARK))
	px(img, 10, 11, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 13, 14, C("CAVE_ROCK", P.T_DARK))
	return img


## Угол «стена к полу», правый — зеркало corner_l (СЗ-свет возвращён на
## нужную сторону).
static func build_wall_corner_r() -> Image:
	var left := build_wall_corner_l()
	var img := im(16, 16)
	for y in 16:
		for x in 16:
			var col := left.get_pixel(15 - x, y)
			# блики/тени при отражении меняют стороны — перекрашиваем крест-накрест
			if col == C("CAVE_ROCK", P.T_LIGHT):
				col = C("CAVE_ROCK", P.T_DARK)
			elif col == C("CAVE_ROCK", P.T_DARK):
				col = C("CAVE_ROCK", P.T_LIGHT)
			img.set_pixel(x, y, col)
	# СЗ-свет на нужной стороне: светлая грань камня у кромки, тень — с другой
	for y in 16:
		for x in range(6, 8):
			if img.get_pixel(x, y) != C("CAVE_ROCK", P.T_OUTLINE):
				img.set_pixel(x, y,
						C("CAVE_ROCK", P.T_LIGHT) if y % 4 != 3 else C("CAVE_ROCK", P.T_MID))
	px(img, 7, 3, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 8, 8, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 5, 11, C("CAVE_ROCK", P.T_LIGHT))
	return img


# ------------------------------------------------------------------ силуэты
## Алтарь пещеры — строго 1.6H (SCALE_CANON «алтарь 1.6 | 26»; легаси
## env4_altar: кроп 502×861, drawn 51 при H=32 → пропорция 0.583 сохранена:
## 26×0.583 ≈ 15 px ширины кадра; alpha-trim даёт силуэт 13×25). Ступенчатый
## постамент CAVE_ROCK, монолит, кристальное навершие CRYSTAL (свечение из
## центра).
static func build_altar() -> Image:
	var img := im(15, 26)
	# ступень 1 (нижняя) y22..25
	rect(img, 1, 22, 13, 25, C("CAVE_ROCK", P.T_MID))
	rect(img, 1, 22, 13, 22, C("CAVE_ROCK", P.T_LIGHT))
	rect(img, 1, 22, 1, 25, C("CAVE_ROCK", P.T_LIGHT))
	rect(img, 13, 23, 13, 25, C("CAVE_ROCK", P.T_DARK))
	px(img, 5, 24, C("CAVE_ROCK", P.T_DARK))
	px(img, 10, 23, C("CAVE_ROCK", P.T_DARK))
	# ступень 2 y18..21
	rect(img, 3, 18, 11, 21, C("CAVE_ROCK", P.T_MID))
	rect(img, 3, 18, 11, 18, C("CAVE_ROCK", P.T_LIGHT))
	rect(img, 3, 18, 3, 21, C("CAVE_ROCK", P.T_LIGHT))
	rect(img, 11, 19, 11, 21, C("CAVE_ROCK", P.T_DARK))
	px(img, 6, 20, C("CAVE_ROCK", P.T_DARK))
	# колонна-монолит y8..17
	rect(img, 5, 8, 9, 17, C("CAVE_ROCK", P.T_MID))
	rect(img, 5, 8, 5, 17, C("CAVE_ROCK", P.T_LIGHT))
	rect(img, 9, 9, 9, 17, C("CAVE_ROCK", P.T_DARK))
	px(img, 7, 16, C("CAVE_ROCK", P.T_DARK))
	px(img, 7, 9, C("CAVE_ROCK", P.T_DARK))
	# кристальная вставка в колонне (свечение из центра, тень справа/снизу)
	rect(img, 6, 10, 8, 13, C("CRYSTAL", P.T_MID))
	px(img, 6, 10, C("CRYSTAL", P.T_LIGHT))
	px(img, 7, 10, C("CRYSTAL", P.T_LIGHT))
	px(img, 8, 12, C("CRYSTAL", P.T_DARK))
	px(img, 8, 13, C("CRYSTAL", P.T_DARK))
	px(img, 5, 11, C("CAVE_ROCK", P.T_OUTLINE))
	px(img, 5, 12, C("CAVE_ROCK", P.T_OUTLINE))
	px(img, 9, 11, C("CAVE_ROCK", P.T_OUTLINE))
	px(img, 6, 14, C("CRYSTAL", P.T_OUTLINE))
	px(img, 7, 14, C("CRYSTAL", P.T_OUTLINE))
	px(img, 8, 14, C("CRYSTAL", P.T_OUTLINE))
	# навершие-кластер кристаллов y1..7
	px(img, 7, 1, C("CRYSTAL", P.T_LIGHT))
	rect(img, 6, 2, 8, 2, C("CRYSTAL", P.T_MID))
	px(img, 6, 2, C("CRYSTAL", P.T_LIGHT))
	rect(img, 5, 3, 9, 6, C("CRYSTAL", P.T_MID))
	px(img, 5, 3, C("CRYSTAL", P.T_LIGHT))
	px(img, 6, 3, C("CRYSTAL", P.T_LIGHT))
	px(img, 5, 4, C("CRYSTAL", P.T_LIGHT))
	px(img, 9, 5, C("CRYSTAL", P.T_DARK))
	px(img, 9, 6, C("CRYSTAL", P.T_DARK))
	px(img, 8, 6, C("CRYSTAL", P.T_DARK))
	rect(img, 5, 7, 9, 7, C("CRYSTAL", P.T_DARK))
	px(img, 4, 5, C("CRYSTAL", P.T_MID))  # боковой отросток
	px(img, 4, 6, C("CRYSTAL", P.T_DARK))
	px(img, 4, 4, C("CRYSTAL", P.T_LIGHT))
	# мох на северо-западных ступенях (зональная зелень пещеры)
	px(img, 2, 22, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 3, 22, C("MOSS_GLOW", P.T_MID))
	px(img, 2, 23, C("MOSS_GLOW", P.T_MID))
	px(img, 12, 18, C("MOSS_GLOW", P.T_MID))
	px(img, 12, 19, C("MOSS_GLOW", P.T_OUTLINE))
	return img


## Сундук пещеры — SCALE_CANON «сундук ~0.8 | 16 | кадр=силуэт 26×13» (вердикт
## c10 «сундук уменьши»: было 33×16). Корпус WOOD, оковки IRON, замок-кристалл
## CRYSTAL, мох MOSS_GLOW на СЗ-крышке — дизайн прежний, габарит 0.8H. Кадр
## рисуется сразу по силуэту (alpha-trim — тождество), нога на нижней границе.
static func build_chest() -> Image:
	var img := im(26, 13)
	# крышка (пологая арка) y0..3 + теневая кромка y4
	px(img, 6, 0, C("WOOD", P.T_MID))
	rect(img, 7, 0, 18, 0, C("WOOD", P.T_MID))
	px(img, 19, 0, C("WOOD", P.T_MID))
	rect(img, 4, 1, 21, 1, C("WOOD", P.T_MID))
	rect(img, 0, 2, 25, 3, C("WOOD", P.T_MID))
	rect(img, 0, 4, 25, 4, C("WOOD", P.T_DARK))
	# корпус y5..12 (ножная плаха — весь нижний ряд y12, канон кладёт OUTLINE)
	rect(img, 1, 5, 24, 12, C("WOOD", P.T_MID))
	# доски (теневые швы)
	for x in [5, 8, 11, 16, 19, 22]:
		line(img, x, 5, x, 12, C("WOOD", P.T_DARK))
	# вертикальные оковки IRON (крышка+корпус, до ножной плахи)
	for xs in [3, 12, 21]:
		for y in range(1 if xs != 12 else 0, 13):
			px(img, xs, y, C("IRON", P.T_MID))
			px(img, xs + 1, y, C("IRON", P.T_DARK))
		px(img, xs, 1 if xs != 12 else 0, C("IRON", P.T_LIGHT))
	# замок: пластина + кристальный ключник (по центру оковки x12/13)
	for x in [11, 12, 13]:
		for y in [5, 6]:
			px(img, x, y, C("IRON", P.T_MID))
	for y in [4, 5, 6, 7]:
		px(img, 14, y, C("IRON", P.T_DARK))
	px(img, 11, 4, C("IRON", P.T_LIGHT))
	px(img, 12, 4, C("IRON", P.T_LIGHT))
	px(img, 13, 4, C("IRON", P.T_LIGHT))
	px(img, 14, 4, C("IRON", P.T_LIGHT))
	px(img, 12, 5, C("CRYSTAL", P.T_MID))
	px(img, 13, 5, C("CRYSTAL", P.T_MID))
	px(img, 12, 6, C("CRYSTAL", P.T_MID))
	px(img, 13, 6, C("CRYSTAL", P.T_DARK))
	px(img, 12, 5, C("CRYSTAL", P.T_LIGHT))
	px(img, 12, 7, C("CRYSTAL", P.T_OUTLINE))
	px(img, 13, 7, C("CRYSTAL", P.T_OUTLINE))
	# сучки/волокно корпуса
	px(img, 6, 8, C("WOOD", P.T_LIGHT))
	px(img, 19, 10, C("WOOD", P.T_DARK))
	px(img, 9, 11, C("WOOD", P.T_DARK))
	# мох на СЗ-крышке и у левого края (зональная зелень пещеры)
	px(img, 4, 1, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 5, 1, C("MOSS_GLOW", P.T_MID))
	px(img, 6, 1, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 4, 2, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 5, 2, C("MOSS_GLOW", P.T_MID))
	px(img, 18, 3, C("MOSS_GLOW", P.T_MID))
	px(img, 1, 4, C("MOSS_GLOW", P.T_MID))
	return img


## Сталактиты: ярусы 0.5H / 0.75H / 1.2H (диапазон задания 0.5–1.2H).
## Висят с потолка: нижний ряд — остриё, canon_pass кладёт его в OUTLINE.
static func build_stalactite_1() -> Image:  # 5×8 — 0.5H
	var img := im(5, 8)
	for y in range(0, 8):
		var hw := 2 if y < 3 else (1 if y < 6 else 0)
		for x in range(2 - hw, 2 + hw + 1):
			var t := P.T_MID
			if x == 2 - hw:
				t = P.T_LIGHT
			elif x == 2 + hw:
				t = P.T_DARK
			px(img, x, y, C("CAVE_ROCK", t))
	px(img, 2, 7, C("CAVE_ROCK", P.T_DARK))
	px(img, 1, 2, C("CAVE_ROCK", P.T_DARK))
	return img


static func build_stalactite_2() -> Image:  # 7×12 — 0.75H
	var img := im(7, 12)
	for y in range(0, 12):
		var hw := 3 if y < 2 else (2 if y < 5 else (1 if y < 9 else 0))
		for x in range(3 - hw, 3 + hw + 1):
			var t := P.T_MID
			if x == 3 - hw:
				t = P.T_LIGHT
			elif x == 3 + hw:
				t = P.T_DARK
			px(img, x, y, C("CAVE_ROCK", t))
	px(img, 3, 10, C("CAVE_ROCK", P.T_DARK))
	px(img, 3, 11, C("CAVE_ROCK", P.T_DARK))
	px(img, 2, 4, C("CAVE_ROCK", P.T_DARK))
	px(img, 1, 6, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 2, 7, C("CAVE_ROCK", P.T_DARK))
	return img


static func build_stalactite_3() -> Image:  # 9×19 — 1.2H, с кристаллической прожилкой
	var img := im(9, 19)
	for y in range(0, 19):
		var hw := 4 if y < 2 else (3 if y < 6 else (2 if y < 11 else (1 if y < 16 else 0)))
		for x in range(4 - hw, 4 + hw + 1):
			var t := P.T_MID
			if x == 4 - hw:
				t = P.T_LIGHT
			elif x == 4 + hw:
				t = P.T_DARK
			px(img, x, y, C("CAVE_ROCK", t))
	px(img, 4, 17, C("CAVE_ROCK", P.T_DARK))
	px(img, 4, 18, C("CAVE_ROCK", P.T_DARK))
	# прожилка-кристалл (своя грань света — самоизлучающий)
	rect(img, 3, 8, 4, 10, C("CRYSTAL", P.T_MID))
	px(img, 3, 8, C("CRYSTAL", P.T_LIGHT))
	px(img, 4, 10, C("CRYSTAL", P.T_DARK))
	px(img, 5, 5, C("CAVE_ROCK", P.T_DARK))
	px(img, 3, 13, C("CAVE_ROCK", P.T_DARK))
	px(img, 2, 3, C("CAVE_ROCK", P.T_DARK))
	return img


## Сталагмиты: ярусы 0.5H / 0.75H / 1.2H, стоят основанием на полу.
static func build_stalagmite_1() -> Image:  # 9×8 — 0.5H
	var img := im(9, 8)
	for y in range(0, 8):
		var hw := 0 if y < 2 else (1 if y < 4 else (2 if y < 6 else 4))
		for x in range(4 - hw, 4 + hw + 1):
			var t := P.T_MID
			if x == 4 - hw:
				t = P.T_LIGHT
			elif x == 4 + hw:
				t = P.T_DARK
			px(img, x, y, C("CAVE_ROCK", t))
	px(img, 2, 6, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 6, 5, C("CAVE_ROCK", P.T_DARK))
	return img


static func build_stalagmite_2() -> Image:  # 11×12 — 0.75H
	var img := im(11, 12)
	for y in range(0, 12):
		var hw := 0 if y < 2 else (1 if y < 4 else (2 if y < 7 else (3 if y < 10 else 5)))
		for x in range(5 - hw, 5 + hw + 1):
			var t := P.T_MID
			if x == 5 - hw:
				t = P.T_LIGHT
			elif x == 5 + hw:
				t = P.T_DARK
			px(img, x, y, C("CAVE_ROCK", t))
	px(img, 3, 4, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 7, 8, C("CAVE_ROCK", P.T_DARK))
	px(img, 2, 9, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 3, 9, C("MOSS_GLOW", P.T_MID))
	return img


static func build_stalagmite_3() -> Image:  # 13×19 — 1.2H
	var img := im(13, 19)
	for y in range(0, 19):
		var hw := 1 if y < 3 else (2 if y < 6 else (3 if y < 10 else (4 if y < 16 else 6)))
		for x in range(6 - hw, 6 + hw + 1):
			var t := P.T_MID
			if x == 6 - hw:
				t = P.T_LIGHT
			elif x == 6 + hw:
				t = P.T_DARK
			px(img, x, y, C("CAVE_ROCK", t))
	# наплыв-нарост на СЗ-склоне (живая геометрия)
	px(img, 3, 8, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 3, 9, C("CAVE_ROCK", P.T_MID))
	px(img, 4, 10, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 9, 12, C("CAVE_ROCK", P.T_DARK))
	px(img, 8, 6, C("CAVE_ROCK", P.T_DARK))
	# мох у подножия слева (не на нижней кромке — каноническая стопа не съест)
	px(img, 2, 16, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 3, 16, C("MOSS_GLOW", P.T_MID))
	px(img, 2, 17, C("MOSS_GLOW", P.T_MID))
	px(img, 1, 16, C("MOSS_GLOW", P.T_MID))
	px(img, 10, 15, C("MOSS_GLOW", P.T_OUTLINE))
	return img


## Кострище-мох (тёплый акцент c1; В ИГРУ НЕ СТАВИТСЯ — ждёт отдельного
## вердикта, SCALE_CANON-строки нет): моховое ложе MOSS_GLOW в каменном венце
## CAVE_ROCK, пламя FIRE с горячим ядром FIRE_HOT. 19×19 ≈ 1.2H.
static func build_brazier() -> Image:
	var img := im(19, 19)
	# каменный венец (двойная кладка)
	blob(img, 9, 15, 8.2, 3.6, "CAVE_ROCK")
	for y in range(12, 19):
		for x in 19:
			if img.get_pixel(x, y) == C("CAVE_ROCK", P.T_MID):
				var hh := hashf(x * 5 + 2, y * 3 + 8)
				if hh < 0.20:
					px(img, x, y, C("CAVE_ROCK", P.T_LIGHT))
				elif hh > 0.82:
					px(img, x, y, C("CAVE_ROCK", P.T_DARK))
	px(img, 2, 14, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 15, 14, C("CAVE_ROCK", P.T_DARK))
	# моховое ложе (светится из центра — канон MOSS_GLOW)
	rect(img, 5, 12, 13, 13, C("MOSS_GLOW", P.T_MID))
	rect(img, 6, 11, 12, 11, C("MOSS_GLOW", P.T_MID))
	px(img, 7, 12, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 8, 13, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 6, 11, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 12, 11, C("MOSS_GLOW", P.T_DARK))
	px(img, 5, 13, C("MOSS_GLOW", P.T_OUTLINE))
	# пламя: язык y2, тело y4..10, ядро FIRE_HOT в середине/низу (канон FIRE)
	px(img, 9, 2, C("FIRE", P.T_MID))
	px(img, 8, 4, C("FIRE", P.T_MID))
	rect(img, 8, 5, 10, 5, C("FIRE", P.T_MID))
	rect(img, 7, 6, 11, 8, C("FIRE", P.T_MID))
	rect(img, 6, 8, 12, 10, C("FIRE", P.T_MID))
	rect(img, 7, 10, 11, 10, C("FIRE", P.T_MID))
	rect(img, 8, 6, 10, 9, C("FIRE", P.T_LIGHT))
	px(img, 9, 7, P.FIRE_HOT)
	px(img, 9, 8, P.FIRE_HOT)
	px(img, 9, 9, P.FIRE_HOT)
	px(img, 6, 9, C("FIRE", P.T_LIGHT))
	px(img, 12, 9, C("FIRE", P.T_DARK))
	px(img, 7, 10, C("FIRE", P.T_DARK))
	px(img, 11, 10, C("FIRE", P.T_DARK))
	# искры (одиночные, над пламенем)
	px(img, 5, 5, C("FIRE", P.T_DARK))
	px(img, 13, 4, C("FIRE", P.T_DARK))
	px(img, 11, 2, C("FIRE", P.T_DARK))
	return img


## Факел настенный (c5, вердикт «факелы лучше») — 9×10 ≈ 0.6H, ДВА кадра
## фликера (кадр/тайминг — паттерн A_TORCH atmosphere.gd, T=0.25 c): кронштейн
## IRON (чаша, монтажная пластина с костылями, ось, стопа), пламя FIRE с
## горячим ядром FIRE_HOT. Кадр 1 — ровное пламя, ядро по центру; кадр 2 —
## пламя склонилось вправо, основание ушло влево (тот же приём, что 2-кадровый
## факел деревни). Композиция кадра плотная по всем четырём сторонам
## (alpha-trim == кадр, пин tight в qa_lp).
static func build_torch_1() -> Image:
	var img := im(9, 10)
	# пламя y0..3
	px(img, 4, 0, C("FIRE", P.T_MID))
	px(img, 3, 1, C("FIRE", P.T_LIGHT))
	px(img, 4, 1, C("FIRE", P.T_MID))
	px(img, 5, 1, C("FIRE", P.T_DARK))
	px(img, 3, 2, C("FIRE", P.T_LIGHT))
	px(img, 4, 2, P.FIRE_HOT)
	px(img, 5, 2, C("FIRE", P.T_DARK))
	px(img, 2, 3, C("FIRE", P.T_MID))
	px(img, 3, 3, C("FIRE", P.T_LIGHT))
	px(img, 4, 3, P.FIRE_HOT)
	px(img, 5, 3, C("FIRE", P.T_MID))
	px(img, 6, 3, C("FIRE", P.T_DARK))
	# кронштейн y4..9: чаша, пластина с костылями, ось, стопа
	rect(img, 3, 4, 5, 4, C("IRON", P.T_MID))
	px(img, 2, 4, C("IRON", P.T_DARK))
	px(img, 6, 4, C("IRON", P.T_DARK))
	px(img, 2, 5, C("IRON", P.T_MID))
	px(img, 6, 5, C("IRON", P.T_MID))
	rect(img, 3, 5, 5, 5, C("IRON", P.T_DARK))
	px(img, 0, 6, C("IRON", P.T_DARK))
	px(img, 8, 6, C("IRON", P.T_DARK))
	rect(img, 1, 6, 7, 6, C("IRON", P.T_MID))
	rect(img, 2, 7, 6, 7, C("IRON", P.T_DARK))
	px(img, 4, 8, C("IRON", P.T_MID))
	rect(img, 3, 9, 5, 9, C("IRON", P.T_MID))
	return img


## Кадр 2: пламя склонилось вправо (остриё x5), основание сместилось.
static func build_torch_2() -> Image:
	var img := build_torch_1()
	# сбить кадр 1 пламени (y0..3) и переложить со сдвигом
	for y in range(0, 4):
		for x in 9:
			px(img, x, y, Color(0, 0, 0, 0))
	px(img, 5, 0, C("FIRE", P.T_MID))
	px(img, 4, 1, C("FIRE", P.T_LIGHT))
	px(img, 5, 1, C("FIRE", P.T_MID))
	px(img, 6, 1, C("FIRE", P.T_DARK))
	px(img, 4, 2, C("FIRE", P.T_LIGHT))
	px(img, 5, 2, P.FIRE_HOT)
	px(img, 6, 2, C("FIRE", P.T_MID))
	px(img, 3, 3, C("FIRE", P.T_MID))
	px(img, 4, 3, P.FIRE_HOT)
	px(img, 5, 3, C("FIRE", P.T_MID))
	px(img, 6, 3, C("FIRE", P.T_DARK))
	px(img, 2, 3, C("FIRE", P.T_LIGHT))
	return img


# ------------------------------------------------------------------ наборы
## Порядок тайлов пола в атласе cave_floor_v1 (индекс = слот).
static func floor_tile_set() -> Array:
	return [
		{"name": "FLOOR", "img": build_floor_cave()},
		{"name": "FLOOR_CRACK", "img": build_floor_crack()},
		{"name": "FLOOR_ALTAR", "img": build_floor_altar()},
		{"name": "FLOOR_MOSS", "img": build_floor_moss()},
	]


## Порядок тайлов стены в атласе cave_wall_v1 (индекс = слот; 2..4 —
## направленные кромки, по вертикали не репитятся).
static func wall_tile_set() -> Array:
	return [
		{"name": "WALL", "img": build_wall_solid()},
		{"name": "WALL_TOP", "img": build_wall_top()},
		{"name": "WALL_BOT", "img": build_wall_bot()},
		{"name": "WALL_CORNER_L", "img": build_wall_corner_l()},
		{"name": "WALL_CORNER_R", "img": build_wall_corner_r()},
	]


## Пропы с прогоном канона (тот же пиксель, что в листе и в атласе).
static func prop_set_canon() -> Array:
	var props: Array = [
		{"name": "ALTAR", "img": build_altar()},
		{"name": "CHEST", "img": build_chest()},
		{"name": "BRAZIER", "img": build_brazier()},
		{"name": "STALC3", "img": build_stalactite_3()},
		{"name": "STALAG3", "img": build_stalagmite_3()},
		{"name": "STALC2", "img": build_stalactite_2()},
		{"name": "STALAG2", "img": build_stalagmite_2()},
		{"name": "STALC1", "img": build_stalactite_1()},
		{"name": "STALAG1", "img": build_stalagmite_1()},
		{"name": "TORCH1", "img": build_torch_1()},
		{"name": "TORCH2", "img": build_torch_2()},
	]
	for s in props:
		canon_pass(s["img"])
	return props


## Alpha-trim: кадр до видимого силуэта (аудит c2, F2). Возвращает
## {"img": обрезанное, "x", "y": смещение bbox в исходном кадре}.
static func trim(img: Image) -> Dictionary:
	var minx := img.get_width()
	var miny := img.get_height()
	var maxx := -1
	var maxy := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	if maxx < 0:
		return {"img": img, "x": 0, "y": 0}
	var w := maxx - minx + 1
	var h := maxy - miny + 1
	var out := im(w, h)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(minx, miny, w, h), Vector2i.ZERO)
	return {"img": out, "x": minx, "y": miny}


## Кандидат-атласы. Пол/стены — прямая раскладка тайл-сетов; пропы — по
## регионам CaveArt.REGIONS (единственный источник раскладки): размер trimmed-
## кадра обязан равняться региону, вне регионов пикселей быть не должно —
## иначе returns fails.
static func bake_floor_atlas() -> Image:
	var tiles := floor_tile_set()
	var out := im(tiles.size() * 16, 16)
	for i in tiles.size():
		out.blit_rect(tiles[i]["img"], Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
	return out


static func bake_wall_atlas() -> Image:
	var tiles := wall_tile_set()
	var out := im(tiles.size() * 16, 16)
	for i in tiles.size():
		out.blit_rect(tiles[i]["img"], Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
	return out


static func bake_props_atlas(regions: Dictionary, atlas_size: Vector2i) -> Dictionary:
	var out := im(atlas_size.x, atlas_size.y)
	out.fill(Color(0, 0, 0, 0))
	var fails: Array = []
	for s in prop_set_canon():
		var key := String(s["name"])
		if not regions.has(key):
			fails.append("нет региона %s" % key)
			continue
		var tr: Dictionary = trim(s["img"])
		var reg: Rect2 = regions[key]
		var img: Image = tr["img"]
		if int(reg.size.x) != img.get_width() or int(reg.size.y) != img.get_height():
			fails.append("регион %s %dx%d != trimmed %dx%d" % [key,
					int(reg.size.x), int(reg.size.y), img.get_width(), img.get_height()])
			continue
		out.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()),
				Vector2i(int(reg.position.x), int(reg.position.y)))
	# вне регионов — пусто
	var cover := im(atlas_size.x, atlas_size.y)
	cover.fill(Color(0, 0, 0, 0))
	for k in regions:
		var r: Rect2 = regions[k]
		for y in range(int(r.position.y), int(r.position.y + r.size.y)):
			for x in range(int(r.position.x), int(r.position.x + r.size.x)):
				cover.set_pixel(x, y, Color(1, 1, 1, 1))
	for y in atlas_size.y:
		for x in atlas_size.x:
			if out.get_pixel(x, y).a > 0.5 and cover.get_pixel(x, y).a < 0.5:
				fails.append("пиксель вне региона (%d,%d)" % [x, y])
				break
	return {"img": out, "fails": fails}
