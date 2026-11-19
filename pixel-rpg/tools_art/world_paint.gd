extends RefCounted
## WorldPaint — кодоген-артист листа «Мир v1» (волна «Мир v1», t1, вердикт-гейт).
##
## Шесть биомов открытого мира (docs/OPEN_WORLD.md, фаза 2) в каноне
## «hand-made пиксель» (docs/PIXEL_STYLE.md): тайлы пола/кромки, декор и
## порталы локаций. ВНИМАНИЕ: это ЛИСТ-ВЕРДИКТ — игра не читает этот модуль;
## интеграция только после «да» пользователя (конвенция листа: sheet_cave t53,
## sheet_forest v1/w3).
##
## Законы:
##  - единственный источник цвета — PixelPalette (RAMPS закрыты, дельта палитры
##    пуста; биомы — УЗНАВАЕМЫЕ СЕМЕЙСТВА существующих рамп:
##      снег   = BONE(теплое небо) + STONE(холод) + CRYSTAL(лёд) + WATER,
##      пустыня= PATH(песок) + STONE_WARM + BARK + LEAF(кактус) + FIRE,
##      степь  = GRASS + PATH(сухотень) + STONE_WARM,
##      лес    = УТВЕРЖДЁННЫЙ forest_paint v1 (переиспользуется как есть),
##      замок  = STONE + IRON + BRONZE + WOOD/BARK + CLOTH,
##      подз.  = VIOLET(CAVE_ROCK) + CRYSTAL + MOSS_GLOW + CAVE_WATER + BONE);
##  - свет СЗ, нижний контур OUTLINE-тоном (CP.canon_pass), тайлы-поверхности
##    непрозрачны и бесшовны (шум периодичен ровно 16, pxw/linew),
##    hero=16px (SCALE_CANON);
##  - ноль randi: детерминированный хэш-шум CP.hp (SEED=4321) с фикс.
##    офсетами — побайтовое воспроизведение двойным bake (пин md5/FNV);
##  - правило глухой массы (g24a): проходы в кластерах >= 2 КЛЕТКИ сразу
##    в геометрии — кластеры задаются ASCII-картами, лист их проверяет.

const P := preload("res://scripts/pixel_palette.gd")
const CP := preload("res://tools_art/cave_paint.gd")
const FP := preload("res://tools_art/forest_paint.gd")

static func C(rn: String, tone: int) -> Color:
	return CP.C(rn, tone)

static func im(w: int, h: int) -> Image:
	return CP.im(w, h)

static func px(img: Image, x: int, y: int, col: Color) -> void:
	CP.px(img, x, y, col)

static func rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	CP.rect(img, x0, y0, x1, y1, col)

static func line(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	CP.line(img, x0, y0, x1, y1, col)

static func pxw(img: Image, x: int, y: int, col: Color) -> void:
	CP.pxw(img, x, y, col)

static func linew(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	CP.linew(img, x0, y0, x1, y1, col)

static func hp(x: int, y: int) -> float:
	return CP.hp(x, y)

## Детерминированный FNV-1a 32 над UTF-8 строки (канон репозитория: тот же
## алгоритм, что CP.img_hash над байтами PNG; сверен с независимой BigInt-
## реализацией 18.11, см. diag-t3/PLAN_W3.md §5.1). Системный хэш строки
## hash() ЗАПРЕЩЁН в генераторах: CityHash без контракта совместимости между
## версиями движка — золотые пины «поедут» при апгрейде Godot (аудит w2, F3).
static func shash(s: String) -> int:
	var h := 2166136261
	for b in s.to_utf8_buffer():
		h = int(h ^ b)
		h = (h * 16777619) & 0xFFFFFFFF
	return h

# ============================================================ поля полов
## Поле — бесшовный 16-периодный шумовой «ковер» биома. Ключи поля:
##  rn — рампа; base — базовый тон; l/lt — порог и тон светлых пятен;
##  d — порог тёмных, drn — рампа тёмных вкраплений (по умолчанию rn);
##  dry — {rn,tone,th}: пороговая «сухая» примесь вторым офсетом;
##  slab — рампа плиточной кладки (замок/подземелье).
static func _smp(fd: Dictionary, x: int, y: int) -> Color:
	if fd.has("slab"):
		return _slab(x, y, String(fd["slab"]))
	var ramp: Array = P.RAMPS[String(fd["rn"])]
	var h := hp(x + int(fd["ox"]), y + int(fd["oy"]))
	var drn := String(fd.get("drn", fd["rn"]))
	if fd.has("dry") and hp(x + int(fd["ox"]) + 41, y + int(fd["oy"]) + 17) > float((fd["dry"] as Dictionary)["th"]):
		return C(String((fd["dry"] as Dictionary)["rn"]), int((fd["dry"] as Dictionary)["tone"]))
	if h < float(fd["l"]):
		return ramp[int(fd["lt"])]
	if h > float(fd["d"]) + 0.035:
		return C(drn, P.T_OUTLINE)
	if h > float(fd["d"]):
		return C(drn, P.T_DARK)
	return ramp[int(fd["base"])]

## Плитняк «бегущий ряд»: полосы 4 px, раствор OUTLINE, СЗ-фаска LIGHT.
static func _slab(x: int, y: int, rn: String) -> Color:
	if y % 4 == 3:
		return C(rn, P.T_OUTLINE)
	var xv: int = (x + (int(y / 4) % 2) * 4) % 8
	if xv == 7:
		return C(rn, P.T_OUTLINE)
	if y % 4 == 0:
		return C(rn, P.T_LIGHT)
	return C(rn, P.T_MID)

## Заполнить тайл полем (полностью непрозрачно).
static func _field(img: Image, fd: Dictionary) -> void:
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, _smp(fd, x, y))

const F_SNOW := {"rn": "BONE", "base": P.T_LIGHT, "l": 0.18, "lt": P.T_MID, "d": 0.965, "drn": "STONE", "ox": 3, "oy": 11}
const F_SNOW2 := {"rn": "BONE", "base": P.T_LIGHT, "l": 0.2, "lt": P.T_MID, "d": 0.955, "drn": "STONE", "ox": 19, "oy": 27}
const F_DES := {"rn": "PATH", "base": P.T_LIGHT, "l": 0.15, "lt": P.T_MID, "d": 0.96, "drn": "STONE_WARM", "ox": 7, "oy": 23}
const F_DES2 := {"rn": "PATH", "base": P.T_LIGHT, "l": 0.17, "lt": P.T_MID, "d": 0.955, "drn": "STONE_WARM", "ox": 31, "oy": 13}
const F_STEPPE := {"rn": "GRASS", "base": P.T_MID, "l": 0.13, "lt": P.T_LIGHT, "d": 0.93, "drn": "GRASS", "dry": {"rn": "PATH", "tone": P.T_MID, "th": 0.95}, "ox": 5, "oy": 29}
const F_STEPPE2 := {"rn": "GRASS", "base": P.T_MID, "l": 0.14, "lt": P.T_LIGHT, "d": 0.925, "drn": "GRASS", "dry": {"rn": "PATH", "tone": P.T_MID, "th": 0.945}, "ox": 23, "oy": 47}
const F_MEADOW := {"rn": "GRASS", "base": P.T_MID, "l": 0.15, "lt": P.T_LIGHT, "d": 0.9, "drn": "GRASS", "ox": 61, "oy": 41}
const F_CASTLE := {"slab": "STONE", "ox": 0, "oy": 0}
const F_CASTLE2 := {"slab": "STONE", "ox": 1, "oy": 2}
const F_DUNGEON := {"slab": "VIOLET", "ox": 0, "oy": 0}
const F_DUNGEON2 := {"slab": "VIOLET", "ox": 1, "oy": 2}

# ------------------------------------------------------------ снег
static func build_snow_f1() -> Image:
	var img := im(16, 16)
	_field(img, F_SNOW)
	# ветровые гряды: две зубчатые волны (шов непрерывен — pxw)
	for x in 16:
		var y1: int = 4 if hp(x + 21, 7) > 0.5 else 5
		pxw(img, x, y1, C("STONE", P.T_LIGHT))
		pxw(img, x, y1 + 1, C("STONE", P.T_MID) if hp(x + 9, 3) > 0.4 else C("BONE", P.T_MID))
		var y2: int = 10 if hp(x + 45, 5) > 0.5 else 11
		pxw(img, x, y2, C("STONE", P.T_LIGHT))
	# наледь: лёд CRYSTAL/WATER + блик
	pxw(img, 6, 13, C("WATER", P.T_DARK))
	pxw(img, 7, 13, C("WATER", P.T_MID))
	pxw(img, 7, 12, C("CRYSTAL", P.T_MID))
	pxw(img, 6, 12, C("CRYSTAL", P.T_LIGHT))
	# искры снега
	for i in 4:
		var sx: int = int(hp(3 + i * 13, 17) * 15.99)
		var sy: int = int(hp(9 + i * 7, 41) * 15.99)
		pxw(img, sx, sy, C("WATER", P.T_LIGHT))
	return img

static func build_snow_f2() -> Image:
	var img := im(16, 16)
	_field(img, F_SNOW2)
	# сугробная дуга (тень с наветренной стороны)
	linew(img, 1, 7, 5, 5, C("STONE", P.T_MID))
	linew(img, 6, 5, 9, 6, C("STONE", P.T_LIGHT))
	pxw(img, 4, 6, C("BONE", P.T_LIGHT))
	linew(img, 10, 13, 14, 12, C("STONE", P.T_MID))
	pxw(img, 12, 3, C("CRYSTAL", P.T_MID))
	pxw(img, 12, 2, C("WATER", P.T_LIGHT))
	for i in 3:
		var sx: int = int(hp(21 + i * 17, 11) * 15.99)
		var sy: int = int(hp(33 + i * 5, 29) * 15.99)
		pxw(img, sx, sy, C("WATER", P.T_LIGHT))
	return img

# ------------------------------------------------------------ пустыня
static func build_desert_f1() -> Image:
	var img := im(16, 16)
	_field(img, F_DES)
	# рябь дюн: три зубчатые полосы с подсветкой гребня
	for x in 16:
		var yr: int = 3 if hp(x + 11, 3) > 0.5 else 4
		pxw(img, x, yr, C("PATH", P.T_MID))
		pxw(img, x, yr - 1, C("PATH", P.T_LIGHT) if hp(x + 3, 27) > 0.45 else C("PATH", P.T_MID))
		var yr2: int = 9 if hp(x + 37, 5) > 0.55 else 10
		pxw(img, x, yr2, C("PATH", P.T_MID))
	# сухая трещина (закручена через шов)
	linew(img, -1, 14, 3, 13, C("BARK", P.T_DARK))
	linew(img, 3, 13, 8, 14, C("BARK", P.T_DARK))
	linew(img, 8, 14, 16, 14, C("BARK", P.T_DARK))
	pxw(img, 5, 13, C("BARK", P.T_OUTLINE))
	# галька
	pxw(img, 12, 6, C("STONE_WARM", P.T_DARK))
	pxw(img, 13, 6, C("STONE_WARM", P.T_MID))
	pxw(img, 13, 5, C("STONE_WARM", P.T_LIGHT))
	return img

static func build_desert_f2() -> Image:
	var img := im(16, 16)
	_field(img, F_DES2)
	for x in 16:
		var yr: int = 5 if hp(x + 19, 9) > 0.5 else 6
		pxw(img, x, yr, C("PATH", P.T_MID))
		pxw(img, x, yr - 1, C("PATH", P.T_LIGHT) if hp(x + 41, 13) > 0.5 else C("PATH", P.T_MID))
	# трещины-звёздочки
	linew(img, 9, 10, 12, 12, C("BARK", P.T_DARK))
	pxw(img, 10, 12, C("BARK", P.T_DARK))
	pxw(img, 12, 10, C("BARK", P.T_DARK))
	linew(img, 2, 1, 4, 3, C("BARK", P.T_DARK))
	# выветренный камень
	rect(img, 4, 11, 5, 12, C("STONE_WARM", P.T_DARK))
	px(img, 4, 11, C("STONE_WARM", P.T_LIGHT))
	px(img, 6, 12, C("STONE_WARM", P.T_MID))
	return img

# ------------------------------------------------------------ степь
static func _steppe_base(img: Image, fd: Dictionary) -> void:
	_field(img, fd)
	# травяные лезвия СЗ + сухие семеновины
	for i in 4:
		var gx: int = int(hp(int(fd["ox"]) + i * 7, int(fd["oy"]) + 5) * 15.99)
		var gy: int = int(hp(int(fd["ox"]) + i * 11, int(fd["oy"]) + 31) * 15.99)
		pxw(img, gx, gy, C("GRASS", P.T_LIGHT))
		pxw(img, gx, gy + 1, C("GRASS", P.T_LIGHT))
		pxw(img, gx + 1, gy + 1, C("PATH", P.T_LIGHT))
	for i in 3:
		var sx: int = int(hp(int(fd["ox"]) + 9 + i * 19, int(fd["oy"]) + 13) * 15.99)
		var sy: int = int(hp(int(fd["ox"]) + 5 + i * 23, int(fd["oy"]) + 7) * 15.99)
		pxw(img, sx, sy, C("PATH", P.T_MID))
	pxw(img, 13, 9, C("STONE_WARM", P.T_DARK))
	pxw(img, 14, 9, C("STONE_WARM", P.T_MID))

static func build_steppe_f1() -> Image:
	var img := im(16, 16)
	_steppe_base(img, F_STEPPE)
	return img

static func build_steppe_f2() -> Image:
	var img := im(16, 16)
	_steppe_base(img, F_STEPPE2)
	# куртина сухой травы (не трогает швов)
	linew(img, 4, 12, 3, 9, C("PATH", P.T_DARK))
	linew(img, 5, 12, 5, 8, C("PATH", P.T_MID))
	linew(img, 6, 12, 7, 9, C("PATH", P.T_DARK))
	px(img, 5, 8, C("PATH", P.T_LIGHT))
	return img

# ------------------------------------------------------------ замок / подземелье (плитняк)
static func _slab_extra(img: Image, ox: int, oy: int, chip_rn: String) -> void:
	# сколы и сор поверх кладки (шумовые, не по раствору)
	for i in 5:
		var cx: int = int(hp(ox + i * 13, oy + 3) * 15.99)
		var cy: int = int(hp(ox + i * 17, oy + 29) * 15.99)
		if cy % 4 == 3 or (cx + (int(cy / 4) % 2) * 4) % 8 == 7:
			continue
		pxw(img, cx, cy, C(chip_rn, P.T_DARK) if hp(cx + ox, cy + oy) > 0.5 else C(chip_rn, P.T_LIGHT))

static func build_castle_f1() -> Image:
	var img := im(16, 16)
	_field(img, F_CASTLE)
	_slab_extra(img, 5, 7, "STONE")
	linew(img, 2, 5, 6, 6, C("STONE", P.T_OUTLINE))
	pxw(img, 4, 5, C("STONE", P.T_DARK))
	# мох у раствора
	pxw(img, 0, 7, C("GRASS", P.T_DARK))
	pxw(img, 11, 3, C("GRASS", P.T_DARK))
	pxw(img, 12, 3, C("GRASS", P.T_MID))
	# гравий
	pxw(img, 9, 13, C("PATH", P.T_DARK))
	pxw(img, 10, 14, C("PATH", P.T_MID))
	return img

static func build_castle_f2() -> Image:
	var img := im(16, 16)
	_field(img, F_CASTLE2)
	_slab_extra(img, 11, 19, "STONE")
	# трещина через плиту (шов-цикл)
	linew(img, 13, -1, 14, 2, C("STONE", P.T_OUTLINE))
	linew(img, 14, 2, 12, 5, C("STONE", P.T_OUTLINE))
	linew(img, 13, -1, 12, 15, C("STONE", P.T_OUTLINE))
	pxw(img, 8, 9, C("MOSS_GLOW", P.T_DARK))
	pxw(img, 2, 10, C("PATH", P.T_DARK))
	pxw(img, 3, 11, C("PATH", P.T_MID))
	return img

static func build_dungeon_f1() -> Image:
	var img := im(16, 16)
	_field(img, F_DUNGEON)
	_slab_extra(img, 3, 5, "VIOLET")
	# кристальная жила по диагонали (шов-цикл)
	linew(img, 1, 15, 8, 6, C("CRYSTAL", P.T_MID))
	linew(img, 8, 6, 15, 0, C("CRYSTAL", P.T_MID))
	pxw(img, 6, 8, C("CRYSTAL", P.T_LIGHT))
	pxw(img, 10, 4, C("CRYSTAL", P.T_LIGHT))
	# светящийся мох + сырость
	pxw(img, 12, 11, C("MOSS_GLOW", P.T_MID))
	pxw(img, 13, 11, C("MOSS_GLOW", P.T_LIGHT))
	pxw(img, 12, 12, C("MOSS_GLOW", P.T_DARK))
	pxw(img, 3, 12, C("CAVE_WATER", P.T_DARK))
	pxw(img, 4, 12, C("CAVE_WATER", P.T_MID))
	pxw(img, 9, 9, C("BONE", P.T_DARK))
	return img

static func build_dungeon_f2() -> Image:
	var img := im(16, 16)
	_field(img, F_DUNGEON2)
	_slab_extra(img, 9, 23, "VIOLET")
	linew(img, 5, -1, 4, 4, C("CRYSTAL", P.T_MID))
	pxw(img, 5, 2, C("CRYSTAL", P.T_LIGHT))
	pxw(img, 11, 8, C("CRYSTAL", P.T_MID))
	pxw(img, 7, 13, C("MOSS_GLOW", P.T_DARK))
	pxw(img, 8, 13, C("MOSS_GLOW", P.T_MID))
	pxw(img, 2, 5, C("BONE", P.T_MID))
	pxw(img, 14, 1, C("CAVE_WATER", P.T_DARK))
	pxw(img, 15, 1, C("CAVE_WATER", P.T_MID))
	return img

# ============================================================ кромки (переходы)
## Зубчатый шов y=6..8 (или x), верх/лево — поле A, низ/право — поле B.
static func _tooth(x: int, o: int) -> int:
	var h := hp(x + o, 5)
	return 8 if h > 0.62 else (7 if h > 0.30 else 6)

static func edge_s(fa: Dictionary, fb: Dictionary, o: int) -> Image:
	var img := im(16, 16)
	for x in 16:
		var t := _tooth(x, o)
		for y in 16:
			img.set_pixel(x, y, _smp(fa, x, y) if y <= t else _smp(fb, x, y))
		pxw(img, x, t, _seam_col(fa))
		pxw(img, x, t + 1, C(String(fb.get("drn", fb["rn"])), P.T_LIGHT) if hp(x + o + 9, 7) > 0.6 else _smp(fb, x, t + 1))
	return img

static func edge_e(fa: Dictionary, fb: Dictionary, o: int) -> Image:
	var img := im(16, 16)
	for y in 16:
		var t := _tooth(y, o + 31)
		for x in 16:
			img.set_pixel(x, y, _smp(fa, x, y) if x <= t else _smp(fb, x, y))
		pxw(img, t, y, _seam_col(fa))
		pxw(img, t + 1, y, C(String(fb.get("drn", fb["rn"])), P.T_LIGHT) if hp(y + o + 13, 9) > 0.6 else _smp(fb, t + 1, y))
	return img

static func _seam_col(fd: Dictionary) -> Color:
	if fd.has("slab"):
		return C(String(fd["slab"]), P.T_OUTLINE)
	return C(String(fd.get("drn", fd["rn"])), P.T_OUTLINE)

static func build_snow_edge_s() -> Image:
	var img := edge_s(F_SNOW, F_STEPPE, 13)
	# снежные подтёки через зуб + ледяная искра
	for x in 16:
		var t := _tooth(x, 13)
		if hp(x + 5, 21) > 0.55:
			pxw(img, x, t + 2, C("BONE", P.T_MID))
		if hp(x + 17, 9) > 0.8:
			pxw(img, x, t + 1, C("CRYSTAL", P.T_LIGHT))
	# травинки степи лезут в снег
	for x in [3, 11]:
		pxw(img, x, _tooth(x, 13) - 1, C("GRASS", P.T_LIGHT))
		pxw(img, x, _tooth(x, 13) - 2, C("PATH", P.T_LIGHT))
	return img

static func build_snow_edge_e() -> Image:
	var img := edge_e(F_SNOW, F_STEPPE, 5)
	for y in 16:
		var t := _tooth(y, 36)
		if hp(y + 7, 25) > 0.55:
			pxw(img, t + 2, y, C("BONE", P.T_MID))
		if hp(y + 23, 11) > 0.8:
			pxw(img, t + 1, y, C("CRYSTAL", P.T_LIGHT))
	for y in [4, 12]:
		pxw(img, _tooth(y, 36) - 1, y, C("GRASS", P.T_LIGHT))
	return img

static func build_desert_edge_s() -> Image:
	var img := edge_s(F_DES, F_STEPPE, 7)
	# осыпающийся песок по шву
	for x in 16:
		var t := _tooth(x, 7)
		if hp(x + 3, 19) > 0.5:
			pxw(img, x, t + 2, C("PATH", P.T_LIGHT))
	pxw(img, 5, _tooth(5, 7) - 1, C("STONE_WARM", P.T_MID))
	return img

static func build_steppe_edge_s() -> Image:
	var img := edge_s(F_STEPPE, F_MEADOW, 23)
	# травяной «язык» степи переходит в луг: шов светлыми лезвиями
	for x in 16:
		var t := _tooth(x, 23)
		if hp(x + 11, 5) > 0.55:
			pxw(img, x, t - 1, C("GRASS", P.T_LIGHT))
		if hp(x + 29, 7) > 0.7:
			pxw(img, x, t + 2, C("PATH", P.T_MID))
	return img

static func build_castle_edge_s() -> Image:
	var img := edge_s(F_CASTLE, F_STEPPE, 3)
	# у раствора зубa — крошка камня
	for x in 16:
		var t := _tooth(x, 3)
		if hp(x + 13, 9) > 0.55:
			pxw(img, x, t + 1, C("STONE", P.T_MID))
	pxw(img, 9, _tooth(9, 3) + 2, C("GRASS", P.T_LIGHT))
	return img

static func build_castle_edge_e() -> Image:
	var img := edge_e(F_CASTLE, F_STEPPE, 11)
	for y in 16:
		var t := _tooth(y, 42)
		if hp(y + 19, 7) > 0.55:
			pxw(img, t + 1, y, C("STONE", P.T_MID))
	return img

static func build_dungeon_edge_s() -> Image:
	var img := edge_s(F_DUNGEON, F_MEADOW, 17)
	# корень/мох по кромке подземного свода
	for x in 16:
		var t := _tooth(x, 17)
		if hp(x + 7, 3) > 0.6:
			pxw(img, x, t + 1, C("MOSS_GLOW", P.T_DARK))
		if hp(x + 31, 11) > 0.78:
			pxw(img, x, t, C("CRYSTAL", P.T_MID))
	return img

static func build_dungeon_edge_e() -> Image:
	var img := edge_e(F_DUNGEON, F_MEADOW, 9)
	for y in 16:
		var t := _tooth(y, 40)
		if hp(y + 3, 17) > 0.6:
			pxw(img, t + 1, y, C("MOSS_GLOW", P.T_DARK))
	return img

# ============================================================ декор (силуэты)
## Все — альфа-фон, силуэт, canon_pass (СЗ-свет + нижний OUTLINE), без свая
## (свай — задача интеграции; в лесу качающиеся уже есть).

static func build_snow_pine() -> Image:
	var img := im(21, 40)
	# ствол
	rect(img, 9, 33, 11, 38, C("BARK", P.T_DARK))
	px(img, 9, 34, C("BARK", P.T_MID))
	# три яруса ели (широкие нижние — глухая масса)
	for tier in [[24, 39, 21], [15, 29, 15], [6, 20, 9]]:
		var ty: int = tier[0]
		var by: int = tier[1]
		var wid: int = tier[2]
		for y in range(ty, by + 1):
			var frac := float(y - ty) / float(maxi(by - ty, 1))
			var half := int(round(frac * wid / 2.0))
			for x in range(10 - half, 11 + half):
				px(img, x, y, C("PINE", P.T_MID))
		px(img, 10, ty - 1, C("PINE", P.T_MID))
	# снежные шапки по ярусам (перед canon_pass)
	for row in [[24, [8, 12]], [16, [9, 11]], [17, [8, 12]], [25, [6, 14]], [26, [5, 15]], [7, [9, 11]]]:
		var y: int = row[0]
		for x in range(row[1][0], row[1][1] + 1):
			if hp(x * 3 + y, y) > 0.3:
				px(img, x, y, C("BONE", P.T_LIGHT))
	px(img, 6, 27, C("BONE", P.T_LIGHT))
	px(img, 14, 27, C("BONE", P.T_LIGHT))
	px(img, 8, 19, C("BONE", P.T_LIGHT))
	px(img, 12, 18, C("BONE", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_ice_spike() -> Image:
	var img := im(11, 20)
	# три льдины: средняя главная
	for x in 11:
		var hgt: int = 6 if x < 2 or x > 8 else (17 if x >= 4 and x <= 6 else 11)
		for y in range(20 - hgt, 20):
			var col := C("CRYSTAL", P.T_MID)
			if x <= 4 and y > 20 - hgt + 1 and hp(x + y, y * 2) > 0.45:
				col = C("CRYSTAL", P.T_LIGHT)
			elif x >= 7:
				col = C("CRYSTAL", P.T_DARK)
			px(img, x, y, col)
	# блики
	px(img, 4, 4, C("WATER", P.T_LIGHT))
	px(img, 5, 6, C("CRYSTAL", P.T_LIGHT))
	px(img, 2, 13, C("WATER", P.T_LIGHT))
	CP.canon_pass(img)
	return img

static func build_snow_rock() -> Image:
	var img := im(13, 10)
	CP.blob(img, 6, 6, 5.5, 3.2, "STONE")
	px(img, 2, 4, C("STONE", P.T_MID))
	px(img, 10, 4, C("STONE", P.T_MID))
	px(img, 4, 3, C("STONE", P.T_LIGHT))
	# снежная шапка
	for x in range(2, 11):
		if hp(x * 5, 7) > 0.25:
			px(img, x, 3 if hp(x, 9) > 0.4 else 4, C("BONE", P.T_LIGHT))
	px(img, 5, 2, C("BONE", P.T_LIGHT))
	px(img, 7, 2, C("BONE", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_cactus() -> Image:
	var img := im(9, 26)
	# основной стебель
	rect(img, 3, 3, 5, 24, C("LEAF", P.T_MID))
	# рёбра
	for y in range(4, 24):
		px(img, 4, y, C("LEAF", P.T_DARK))
		if y % 4 == 1:
			px(img, 3, y, C("LEAF", P.T_LIGHT))
	# руки С ФОНАМИ: левая ниже (столб x0-1 + локоть к стволу), правая выше
	rect(img, 0, 8, 1, 14, C("LEAF", P.T_MID))
	rect(img, 2, 13, 3, 14, C("LEAF", P.T_MID))
	px(img, 0, 9, C("LEAF", P.T_LIGHT))
	rect(img, 7, 5, 8, 11, C("LEAF", P.T_MID))
	rect(img, 6, 10, 6, 11, C("LEAF", P.T_MID))
	px(img, 7, 6, C("LEAF", P.T_LIGHT))
	px(img, 5, 10, C("LEAF", P.T_LIGHT))
	# цветок на макушке
	px(img, 3, 1, C("FIRE", P.T_MID))
	px(img, 4, 0, C("FIRE", P.T_LIGHT))
	px(img, 5, 1, C("FIRE", P.T_DARK))
	CP.canon_pass(img)
	return img

static func build_mesa() -> Image:
	var img := im(17, 14)
	# плоская «столовая» скала: уступы
	for y in 14:
		var inset: int = 0 if y < 4 else (2 if y < 8 else 4)
		if y < 13:
			rect(img, inset, y, 16 - inset, y, C("STONE_WARM", P.T_MID))
	# верхняя грань светлее, правый бок темнее (до canon_pass — он добьёт)
	rect(img, 1, 0, 15, 1, C("STONE_WARM", P.T_LIGHT))
	for y in range(2, 13):
		var inset2: int = 0 if y < 4 else (2 if y < 8 else 4)
		px(img, 16 - inset2, y, C("STONE_WARM", P.T_DARK))
	px(img, 4, 5, C("STONE_WARM", P.T_DARK))
	px(img, 5, 6, C("STONE_WARM", P.T_DARK))
	px(img, 8, 10, C("STONE_WARM", P.T_DARK))
	px(img, 3, 11, C("BONE", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_skull() -> Image:
	var img := im(11, 9)
	# купол
	for x in range(2, 9):
		for y in range(0, 6):
			if hp(x * 7, y * 13) > 0.08:
				px(img, x, y, C("BONE", P.T_LIGHT))
	rect(img, 1, 3, 9, 5, C("BONE", P.T_LIGHT))
	# глазницы и нос
	rect(img, 3, 3, 4, 4, C("CHAR", P.T_OUTLINE))
	rect(img, 6, 3, 7, 4, C("CHAR", P.T_OUTLINE))
	px(img, 5, 5, C("CHAR", P.T_DARK))
	# зубы
	for x in range(3, 8):
		px(img, x, 7, C("BONE", P.T_MID))
		if x % 2 == 0:
			px(img, x, 8, C("BONE", P.T_DARK))
	CP.canon_pass(img)
	return img

static func build_tallgrass() -> Image:
	var img := im(13, 13)
	# куртина: дуги-лезвия из общей точки низа
	for i in 7:
		var lean: int = i - 3
		var topy: int = 1 + (absi(lean))
		var x0: int = 6
		for t in 6:
			var xx: int = x0 + int(round(lean * t / 5.0))
			var yy: int = 12 - t * 2 if 12 - t * 2 > topy else topy + (t % 2)
			px(img, xx, yy, C("GRASS", P.T_MID) if i % 2 == 0 else C("GRASS", P.T_DARK))
		px(img, x0 + lean, topy, C("PATH", P.T_LIGHT))
	px(img, 6, 12, C("GRASS", P.T_DARK))
	CP.canon_pass(img)
	return img

static func build_drybush() -> Image:
	var img := im(15, 12)
	# сухой куст: пересекающиеся ветки
	line(img, 2, 10, 6, 3, C("BARK", P.T_DARK))
	line(img, 7, 11, 8, 2, C("BARK", P.T_MID))
	line(img, 12, 10, 9, 4, C("BARK", P.T_DARK))
	line(img, 3, 6, 11, 5, C("BARK", P.T_DARK))
	line(img, 4, 8, 10, 8, C("PATH", P.T_DARK))
	px(img, 8, 2, C("PATH", P.T_LIGHT))
	px(img, 6, 3, C("PATH", P.T_LIGHT))
	px(img, 10, 4, C("PATH", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_steppe_rock() -> Image:
	var img := im(11, 8)
	CP.blob(img, 5, 4, 4.4, 2.6, "STONE_WARM")
	px(img, 3, 2, C("STONE_WARM", P.T_LIGHT))
	px(img, 2, 3, C("STONE_WARM", P.T_LIGHT))
	px(img, 7, 3, C("STONE_WARM", P.T_DARK))
	CP.canon_pass(img)
	return img

static func build_wall_t() -> Image:
	var img := im(16, 30)
	# боевая стена 1 клетка: зубцы + кладка + бойница
	for x in 16:
		if x % 4 < 3:
			rect(img, x, 0, x, 3, C("STONE", P.T_MID))
			px(img, x, 0, C("STONE", P.T_LIGHT))
	for y in range(4, 30):
		for x in 16:
			img.set_pixel(x, y, _slab(x, y, "STONE"))
	_slab_extra(img, 9, 11, "STONE")
	# бойница (железо)
	rect(img, 7, 9, 8, 14, C("IRON", P.T_OUTLINE))
	px(img, 7, 9, C("IRON", P.T_DARK))
	# мох у земли
	px(img, 2, 26, C("GRASS", P.T_DARK))
	px(img, 13, 27, C("GRASS", P.T_DARK))
	px(img, 13, 26, C("GRASS", P.T_MID))
	CP.canon_pass(img)
	return img

static func build_crate() -> Image:
	var img := im(11, 11)
	rect(img, 0, 0, 10, 10, C("BARK", P.T_DARK))
	rect(img, 1, 1, 9, 9, C("WOOD", P.T_MID))
	line(img, 1, 1, 9, 9, C("BARK", P.T_DARK))
	line(img, 9, 1, 1, 9, C("BARK", P.T_DARK))
	px(img, 5, 5, C("BARK", P.T_OUTLINE))
	for x in range(2, 9):
		px(img, x, 1, C("WOOD", P.T_LIGHT))
	px(img, 1, 2, C("WOOD", P.T_LIGHT))
	CP.canon_pass(img)
	return img

static func build_barrel() -> Image:
	var img := im(9, 12)
	for y in 12:
		var inset: int = 1 if y == 0 else (0 if y > 0 and y < 11 else 1)
		rect(img, inset, y, 8 - inset, y, C("BARK", P.T_MID))
	# клёпки и обручи
	for x in [2, 4, 6]:
		px(img, x, 3, C("IRON", P.T_DARK))
		px(img, x, 8, C("IRON", P.T_DARK))
	for x in range(1, 8):
		px(img, x, 2, C("IRON", P.T_DARK))
		px(img, x, 7, C("IRON", P.T_DARK))
		px(img, x, 0, C("IRON", P.T_MID))
	# СЗ-блик бочки
	px(img, 1, 4, C("BARK", P.T_LIGHT))
	px(img, 1, 5, C("BARK", P.T_LIGHT))
	CP.canon_pass(img)
	return img

static func build_banner() -> Image:
	var img := im(7, 18)
	# древко
	rect(img, 0, 1, 1, 17, C("IRON", P.T_DARK))
	px(img, 0, 1, C("BRONZE", P.T_LIGHT))
	px(img, 0, 0, C("BRONZE", P.T_MID))
	# полотнище
	for y in range(2, 12):
		for x in range(2, 7 - (1 if y > 8 else 0)):
			px(img, x, y, C("CLOTH", P.T_MID))
	for x in range(2, 7):
		px(img, x, 2, C("CLOTH", P.T_LIGHT))
	px(img, 3, 5, C("CLOTH", P.T_LIGHT))
	px(img, 4, 8, C("CLOTH", P.T_DARK))
	px(img, 5, 11, C("CLOTH", P.T_DARK))
	CP.canon_pass(img)
	return img

static func build_pillar_d() -> Image:
	var img := im(13, 26)
	# база
	rect(img, 0, 22, 12, 25, C("CAVE_ROCK", P.T_MID))
	rect(img, 1, 21, 11, 21, C("CAVE_ROCK", P.T_LIGHT))
	# шахта
	for y in range(4, 21):
		for x in range(2, 11):
			var col := C("VIOLET", P.T_MID)
			if x == 2:
				col = C("VIOLET", P.T_LIGHT)
			elif x == 10:
				col = C("VIOLET", P.T_DARK)
			if y % 4 == 0:
				col = ramp_shadow(col, "VIOLET")
			px(img, x, y, col)
	# капитель
	rect(img, 0, 2, 12, 3, C("CAVE_ROCK", P.T_MID))
	rect(img, 1, 1, 11, 1, C("CAVE_ROCK", P.T_LIGHT))
	px(img, 4, 9, C("CRYSTAL", P.T_MID))
	px(img, 4, 8, C("CRYSTAL", P.T_LIGHT))
	px(img, 8, 16, C("CRYSTAL", P.T_MID))
	CP.canon_pass(img)
	return img

static func ramp_shadow(col: Color, rn: String) -> Color:
	return col if col != C(rn, P.T_MID) else C(rn, P.T_DARK)

static func build_spire() -> Image:
	var img := im(11, 18)
	for x in 11:
		var hgt: int = 5 if x < 2 or x > 8 else (15 if x >= 4 and x <= 6 else 9)
		for y in range(18 - hgt, 18):
			var col := C("CRYSTAL", P.T_MID)
			if x >= 7:
				col = C("CRYSTAL", P.T_DARK)
			elif x <= 3 and hp(x + y, y) > 0.4:
				col = C("CRYSTAL", P.T_LIGHT)
			px(img, x, y, col)
	px(img, 5, 4, C("VIOLET", P.T_LIGHT))
	px(img, 2, 12, C("VIOLET", P.T_LIGHT))
	CP.canon_pass(img)
	return img

static func build_fungus() -> Image:
	var img := im(11, 14)
	# ножка
	rect(img, 4, 7, 6, 13, C("BONE", P.T_MID))
	px(img, 4, 8, C("BONE", P.T_LIGHT))
	# шляпка
	CP.blob(img, 5, 5, 4.8, 2.8, "MOSS_GLOW")
	rect(img, 2, 6, 8, 6, C("MOSS_GLOW", P.T_DARK))
	px(img, 3, 3, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 4, 2, C("MOSS_GLOW", P.T_LIGHT))
	px(img, 5, 4, C("MOSS_GLOW", P.T_LIGHT))
	CP.canon_pass(img)
	return img

static func build_bonepile() -> Image:
	var img := im(13, 8)
	# два холма костей (широкие — canon_pass даст СЗ-свет сверху) + длинная кость
	CP.blob(img, 4, 5, 3.6, 2.3, "BONE")
	CP.blob(img, 9, 5, 3.1, 2.0, "BONE")
	for x in range(2, 12):
		px(img, x, 1 + (x % 3) / 2, C("BONE", P.T_LIGHT))
	px(img, 5, 4, C("BONE", P.T_DARK))
	px(img, 9, 4, C("BONE", P.T_DARK))
	CP.canon_pass(img)
	return img

# ============================================================ порталы локаций
## Арка-переход 16×26: рама STONE_WARM (каменная кладка), проём — глухая
## тьма CHAR с биомным руническим акцентом. Ядро НЕПРозрачно (маск-пикселей
## ноль) — «свечение» рисуется тонами рамп, не альфой.
static func _arch_open(x: int, y: int) -> bool:
	## Проём арки: низ — прямоугольник x4..11 y13..23, верх — полуцилиндр
	## с центром (7.5, 12) r²≈20.5.
	if y < 8 or x < 4 or x > 11:
		return false
	if y > 12:
		return true
	var dxr := float(x) - 7.5
	var dyr := float(y) - 12.0
	return dxr * dxr + dyr * dyr <= 20.5

static func portal_for(biome: String) -> Image:
	var img := im(16, 26)
	# ступени
	rect(img, 1, 24, 14, 25, C("STONE", P.T_MID))
	px(img, 1, 24, C("STONE", P.T_LIGHT))
	# рама-арка (каменная кладка «бегущий ряд»)
	for y in 24:
		for x in 16:
			if _arch_open(x, y):
				continue
			var col := C("STONE_WARM", P.T_MID)
			if y % 4 == 3:
				col = C("STONE_WARM", P.T_OUTLINE)
			elif (x + (int(y / 4) % 2) * 4) % 8 == 7:
				col = C("STONE_WARM", P.T_OUTLINE)
			elif y % 4 == 0:
				col = C("STONE_WARM", P.T_LIGHT)
			px(img, x, y, col)
	# оковы замка/подземелья (только по раме, не по проёму)
	if biome == "CASTLE" or biome == "DUNGEON":
		var rn := "IRON" if biome == "CASTLE" else "CAVE_ROCK"
		for yy in [8, 20]:
			for x in range(3, 13):
				if _arch_open(x, yy):
					continue
				px(img, x, yy, C(rn, P.T_MID))
				if not _arch_open(x, yy + 1):
					px(img, x, yy + 1, C(rn, P.T_DARK))
	# проём: глухая тьма CHAR (без альфы), левая внутренняя грань светлее
	for y in range(8, 24):
		for x in range(4, 12):
			if not _arch_open(x, y):
				continue
			px(img, x, y, C("CHAR", P.T_DARK) if x == 4 else C("CHAR", P.T_OUTLINE))
	# биомная рунa в центре проёма
	var glyph := _glyph(biome)
	for g in glyph:
		px(img, 7 + int(g[0]), 15 + int(g[1]), g[2])
	# порожек света у ног (намёк перехода, тон-в-тон)
	for x in range(5, 11):
		px(img, x, 23, C("CHAR", P.T_DARK))
	CP.canon_pass(img)
	return img

static func _glyph(biome: String) -> Array:
	match biome:
		"SNOW":
			return [[0, -3, C("CRYSTAL", P.T_LIGHT)], [0, -2, C("CRYSTAL", P.T_LIGHT)], [0, -1, C("CRYSTAL", P.T_MID)], [0, 0, C("CRYSTAL", P.T_MID)], [-1, -2, C("CRYSTAL", P.T_MID)], [1, -2, C("CRYSTAL", P.T_MID)], [-1, 0, C("CRYSTAL", P.T_MID)], [1, 0, C("CRYSTAL", P.T_MID)], [0, 1, C("WATER", P.T_LIGHT)]]
		"DESERT":
			return [[-2, 0, C("FIRE", P.T_MID)], [-1, -1, C("FIRE", P.T_LIGHT)], [0, 0, C("FIRE", P.T_MID)], [1, -1, C("FIRE", P.T_LIGHT)], [2, 0, C("FIRE", P.T_MID)], [0, 1, C("PATH", P.T_LIGHT)], [-2, 1, C("PATH", P.T_MID)], [2, 1, C("PATH", P.T_MID)]]
		"STEPPE":
			return [[0, 1, C("GRASS", P.T_LIGHT)], [0, 0, C("GRASS", P.T_LIGHT)], [0, -1, C("PATH", P.T_LIGHT)], [-1, 0, C("GRASS", P.T_MID)], [1, 0, C("GRASS", P.T_MID)], [-1, 1, C("GRASS", P.T_MID)], [1, 1, C("GRASS", P.T_MID)]]
		"FOREST":
			return [[0, -2, C("LEAF", P.T_LIGHT)], [0, -1, C("LEAF", P.T_LIGHT)], [-1, 0, C("LEAF", P.T_MID)], [0, 0, C("LEAF", P.T_MID)], [1, 0, C("LEAF", P.T_MID)], [0, 1, C("BARK", P.T_MID)], [0, 2, C("BARK", P.T_MID)]]
		"CASTLE":
			return [[0, -2, C("BRONZE", P.T_LIGHT)], [0, -1, C("BRONZE", P.T_LIGHT)], [0, 0, C("BRONZE", P.T_MID)], [-1, 0, C("BRONZE", P.T_MID)], [1, 0, C("BRONZE", P.T_MID)], [0, 1, C("BRONZE", P.T_DARK)], [-1, 1, C("IRON", P.T_MID)], [1, 1, C("IRON", P.T_MID)]]
		_:
			return [[0, -2, C("VIOLET", P.T_LIGHT)], [-1, -1, C("VIOLET", P.T_LIGHT)], [1, -1, C("VIOLET", P.T_LIGHT)], [0, 0, C("CRYSTAL", P.T_LIGHT)], [-1, 1, C("VIOLET", P.T_MID)], [1, 1, C("VIOLET", P.T_MID)], [0, 2, C("VIOLET", P.T_MID)]]

# ============================================================ рамка мира
## Карта-обзор 152×92: горное кольцо-рамка, шесть биомных областей, деревня
## с южной аркой выхода и шесть слотов порталов, тропы от деревни.
static func world_frame() -> Image:
	var img := im(152, 92)
	# внутренность: степное поле
	for y in 92:
		for x in 152:
			img.set_pixel(x, y, _smp(F_STEPPE, x * 3, y * 3))
	# биомные области (эллипсы с шумовой кромкой)
	var ftx: Image = FP.build_floor_litter()
	for y in range(8, 86):
		for x in range(8, 144):
			var jitter := (hp(x, y) - 0.5) * 14.0
			# снег — север
			if _in_ell(x + jitter, y + jitter * 0.6, 76, 6, 52, 26):
				img.set_pixel(x, y, _smp(F_SNOW, x * 3, y * 3))
				if hp(x + 61, y) > 0.92:
					px(img, x, y, C("CRYSTAL", P.T_MID))
			# подземелье — запад
			if _in_ell(x + jitter * 0.8, y + jitter * 0.8, 12, 52, 22, 20):
				img.set_pixel(x, y, _smp(F_DUNGEON, x * 2, y * 2))
			# пустыня — восток-юго-восток
			if _in_ell(x + jitter, y + jitter, 126, 66, 24, 20):
				img.set_pixel(x, y, _smp(F_DES, x * 3, y * 3))
			# замок — восток-северо-восток
			if _in_ell(x + jitter * 0.7, y + jitter * 0.7, 128, 26, 18, 13):
				img.set_pixel(x, y, _smp(F_CASTLE, x * 2, y * 2))
			# лесной пояс вокруг деревни (центр-юг)
			if _in_ell(x + jitter * 0.6, y + jitter * 0.6, 66, 60, 26, 16) and not _in_ell(x, y, 66, 62, 9, 6):
				img.set_pixel(x, y, ftx.get_pixel(x % 16, y % 16))
	# деревня: clearing + дома
	for y in range(57, 68):
		for x in range(58, 75):
			img.set_pixel(x, y, _smp(F_MEADOW, x, y))
	for hcell in [[60, 59], [64, 58], [68, 60], [61, 63], [66, 63]]:
		_hut(img, hcell[0], hcell[1])
	# тропы от деревни к слотам порталов и арке (зубчатые, 1px). Первая — к
	# южным воротам: ведём до нижнего края (74,91), F5-сквозная тропа.
	var roads: Array = [[66, 68, 74, 91], [66, 66, 76, 12], [63, 64, 16, 52], [70, 64, 126, 64], [70, 61, 128, 26], [63, 60, 26, 26]]
	for rd in roads:
		_road(img, rd[0], rd[1], rd[2], rd[3])
	# горное кольцо-рамка поверх краёв (с вырезом южных ворот, F5)
	_mountain_ring(img)
	# южная арка выхода — сквозные ворота через кольцо
	_village_arch_cut(img)
	# слоты порталов (6)
	_slot(img, 76, 20, "SNOW")
	_slot(img, 122, 62, "DESERT")
	_slot(img, 40, 74, "STEPPE")
	_slot(img, 26, 26, "FOREST")
	_slot(img, 128, 26, "CASTLE")
	_slot(img, 16, 52, "DUNGEON")
	return img

static func _in_ell(x: int, y: int, cx: int, cy: int, rx: float, ry: float) -> bool:
	var nx := float(x - cx) / rx
	var ny := float(y - cy) / ry
	return nx * nx + ny * ny <= 1.0

static func _hut(img: Image, x: int, y: int) -> void:
	# домик 5×5: крыша ROOF коньком, стены WOOD, тёмная южная база
	rect(img, x, y + 2, x + 4, y + 4, C("WOOD", P.T_MID))
	px(img, x + 2, y, C("ROOF", P.T_LIGHT))
	px(img, x + 1, y + 1, C("ROOF", P.T_MID))
	px(img, x + 2, y + 1, C("ROOF", P.T_MID))
	px(img, x + 3, y + 1, C("ROOF", P.T_DARK))
	px(img, x, y + 2, C("ROOF", P.T_DARK))
	px(img, x + 1, y + 2, C("ROOF", P.T_MID))
	px(img, x + 2, y + 2, C("ROOF", P.T_MID))
	px(img, x + 3, y + 2, C("ROOF", P.T_DARK))
	px(img, x + 4, y + 2, C("ROOF", P.T_OUTLINE))
	px(img, x + 2, y + 4, C("BARK", P.T_OUTLINE))
	px(img, x, y + 4, C("BARK", P.T_OUTLINE))
	px(img, x + 1, y + 3, C("WOOD", P.T_LIGHT))

## F5 (w3): ворота южной арки в горном кольце рамки 152×92 — вырез 8 px
## (2 клетки на 16-px сетке) сквозь всю южную полосу; сквозная тропа до края.
const GATE_X0 := 70
const GATE_X1 := 77
const GATE_Y0 := 84  # начало южной полосы кольца (d = 91-y <= 7)

static func _in_gate(x: int, y: int) -> bool:
	return y >= GATE_Y0 and x >= GATE_X0 and x <= GATE_X1

static func _road(img: Image, x0: int, y0: int, x1: int, y1: int) -> void:
	var n := maxi(absi(x1 - x0), absi(y1 - y0))
	for i in range(0, n + 1):
		var x: int = x0 + int(round(float(x1 - x0) * i / float(n)))
		var y: int = y0 + int(round(float(y1 - y0) * i / float(n)))
		if hp(x, y) > 0.12:
			px(img, x, y, C("PATH", P.T_MID))
		if hp(x + 7, y + 3) > 0.8:
			px(img, x, y, C("PATH", P.T_LIGHT))

static func _mountain_ring(img: Image) -> void:
	# F5 (w3, отмашка 18.11): ворота южной арки — вырез 8 px (x=70..77) сквозь ВСЮ
	# южную полосу кольца (y=84..91): базовое заполнение и пики пропусток не
	# касаются, но внутрь выреза кольцо не заходит — тропа сквозная до края.
	for y in 92:
		for x in 152:
			if _in_gate(x, y):
				continue
			var d := mini(mini(x, 151 - x), mini(y, 91 - y))
			if d > 7:
				continue
			var base := C("STONE", P.T_OUTLINE) if d <= 1 else (C("STONE", P.T_DARK) if d < 4 else C("STONE", P.T_MID))
			img.set_pixel(x, y, base)
	# пики по периметру (период 6; обход = 2*(152+92) = 488)
	for i in range(0, 488, 6):
		var p := _ring_pt(i)
		var pk := _ring_pt(i + 3)
		var hgt: int = 3 if hp(i, 7) > 0.45 else 2
		for t in range(0, hgt + 1):
			var a := _ring_pt(i + t)
			var b := _ring_pt(i + 6 - t)
			if not _in_gate(a[0], a[1]):
				px(img, a[0], a[1], C("STONE", P.T_LIGHT))
			if not _in_gate(b[0], b[1]):
				px(img, b[0], b[1], C("STONE", P.T_DARK))
		if not _in_gate(pk[0], pk[1]):
			px(img, pk[0], pk[1], C("STONE", P.T_LIGHT))
		if hp(i + 13, 3) > 0.5 and not _in_gate(p[0], p[1]):
			px(img, p[0], p[1], C("BONE", P.T_LIGHT))

static func _ring_pt(t: int) -> Vector2i:
	# обход по периметру 244: верх 152, право 84, низ, лево
	if t < 152:
		return Vector2i(t, 0)
	t -= 152
	if t < 92:
		return Vector2i(151, t)
	t -= 92
	if t < 152:
		return Vector2i(151 - t, 91)
	t -= 152
	return Vector2i(0, 91 - t)

static func _village_arch_cut(img: Image) -> void:
	## F5 (w3, отмашка 18.11): было — арка 8×7 над кольцом, строки y=89..91
	## оставались горой и затыкали дорогу («выход» = тупик). Стало — сквозные
	## ворота: кольцо пропускает вырез (_in_gate), тропа БЕЗ шума (шум hp() дал
	## бы дырку в воротах) идёт от луга деревни до нижнего края карты y=91.
	# луг перед воротами
	for yy in range(81, 84):
		for xx in range(71, 79):
			px(img, xx, yy, _smp(F_MEADOW, xx, yy))
	# балка WOOD над проездом (СЗ-подсветка верхней грани)
	for xx in range(GATE_X0, GATE_X1 + 1):
		px(img, xx, 80, C("WOOD", P.T_MID))
		px(img, xx, 81, C("WOOD", P.T_LIGHT))
	# столбы STONE_WARM по краям выреза
	px(img, GATE_X0, 82, C("STONE_WARM", P.T_MID))
	px(img, GATE_X0, 83, C("STONE_WARM", P.T_LIGHT))
	px(img, GATE_X1, 82, C("STONE_WARM", P.T_MID))
	px(img, GATE_X1, 83, C("STONE_WARM", P.T_DARK))
	# проезд под балкой (между столбов)
	for yy in range(82, 84):
		for xx in range(GATE_X0 + 1, GATE_X1):
			px(img, xx, yy, C("PATH", P.T_MID))
	# сквозная тропа сквозь полосу кольца до края карты (безусловная)
	for yy in range(GATE_Y0, 92):
		for xx in range(GATE_X0, GATE_X1 + 1):
			var col: Color = C("PATH", P.T_MID)
			if hp(xx, yy + 31) > 0.8:
				col = C("PATH", P.T_LIGHT)
			px(img, xx, yy, col)

static func _slot(img: Image, x: int, y: int, biome: String) -> void:
	# слот портала 5×7: арочка STONE_WARM + биомное ядро
	for yy in 7:
		for xx in 5:
			var arch: bool = yy <= 1 and (xx == 0 or xx == 4)
			if xx == 0 or xx == 4 or yy == 6 or (yy == 0 and xx > 0 and xx < 4):
				px(img, x + xx, y + yy, C("STONE_WARM", P.T_LIGHT if yy == 0 or xx == 0 else P.T_MID))
			elif arch:
				px(img, x + xx, y + yy, C("STONE_WARM", P.T_MID))
			else:
				px(img, x + xx, y + yy, C("CHAR", P.T_OUTLINE))
	# ядро
	for g in _glyph(biome):
		var gx: int = x + 2 + int(g[0])
		var gy: int = y + 3 + int(g[1])
		if gx >= x + 1 and gx <= x + 3 and gy >= y + 1 and gy <= y + 5:
			px(img, gx, gy, g[2])
	if hp(x, y) > 0.5:
		px(img, x + 2, y + 7, C("PATH", P.T_MID))

# ============================================================ кластеры (масса >=2)
## ASCII-карты сцен: M/W/C — глухая масса, b/r/i/S/B — проходной декор,
## '.' — пол. Проходы по построению >= 2 клетки (лист проверяет покрытием 2x2).
const CLUSTER_SNOW := [
	"..i.........MMM....i..",
	".i..........MMM.......",
	".........MMMMMMM...i..",
	"..i.....MMMMMMMMM.....",
	"......................",
	"...i.........i........",
	"..........MMM.........",
	".........MMMMM....i...",
	"..i.....MMMMMMM.......",
	"......................",
]
const CLUSTER_DESERT := [
	"..S.......MMM......C..",
	"..........MMM....C....",
	"......MMMMMMMMM...C...",
	"......MMMMMMMMM.......",
	"...................S..",
	"..C...................",
	"........C.............",
	".....MM....CCC........",
	".....MM...CCCCC.......",
	"..................S...",
]
const CLUSTER_CASTLE := [
	"....WWWWWWWW....b....r",
	"....WWWWWWWW..........",
	"......................",
	"......................",
	"..r....WW....WW.....r.",
	".......WW....WW.......",
	"......................",
	"..b.......W........b..",
	"......................",
	"......................",
]

static func cluster_scene(map: Array, floors: Array, mass_map: Dictionary, deco_map: Dictionary) -> Image:
	var rows := map.size()
	var cols := String(map[0]).length()
	var extra := 4  # запас под высокие силуэты сверху
	var img := im(cols * 16, (rows + extra) * 16)
	for cy in rows:
		for cx in cols:
			var f: Image = floors[0] if hp(cx * 5 + 3, cy * 7 + 1) > 0.5 else floors[1]
			img.blit_rect(f, Rect2i(0, 0, 16, 16), Vector2i(cx * 16, (extra + cy) * 16))
	# пропы снизу вверх (y-sort по стопе)
	var props: Array = []
	for cy in rows:
		var row := String(map[cy])
		for cx in cols:
			var ch := row[cx] if cx < row.length() else "."
			var key := String(ch)
			if mass_map.has(key) or deco_map.has(key):
				var lst: Array = mass_map[key] if mass_map.has(key) else deco_map[key]
				var pick: Image = lst[int(hp(cx * 11 + shash(key), cy * 17) * lst.size()) % lst.size()]
				props.append([cy, cx, pick])
	for pp in props:
		var fy: int = pp[0]
		var fx: int = pp[1]
		var pimg: Image = pp[2]
		var base_y := (extra + fy + 1) * 16 - pimg.get_height()
		img.blend_rect(pimg, Rect2i(0, 0, pimg.get_width(), pimg.get_height()), Vector2i(fx * 16, base_y))
	return img

static func cluster_free(map: Array, cx: int, cy: int) -> bool:
	if cy < 0 or cx < 0 or cy >= map.size():
		return false
	var row := String(map[cy])
	if cx >= row.length():
		return false
	var ch := String(row[cx])
	return ch == "." or ch == "i" or ch == "S" or ch == "b" or ch == "r" or ch == "B"

static func _is_block(map: Array, cx: int, cy: int) -> bool:
	## Вне карты — «мир открыт» (не блок). Блок = только глухая масса (M/W/C).
	if cy < 0 or cx < 0 or cy >= map.size():
		return false
	var row := String(map[cy])
	if cx >= row.length():
		return false
	var ch := String(row[cx])
	return ch == "M" or ch == "W" or ch == "C"

static func cluster_holes(map: Array) -> Array:
	## Единичный проход = горизонтальный/вертикальный ЗАМКНУТЫЙ (блоки с обоих
	## концов; край карты — открытый мир, не конец) пробег свободных клеток
	## длиной 1 между массами. Пустой список = проходы >= 2 клетки.
	var out: Array = []
	for cy in map.size():
		var cols := String(map[cy]).length()
		var cx := 0
		while cx < cols:
			if cluster_free(map, cx, cy) and _is_block(map, cx - 1, cy):
				var run := 0
				var x2 := cx
				while x2 < cols and cluster_free(map, x2, cy):
					run += 1
					x2 += 1
				if run == 1 and _is_block(map, x2, cy):
					out.append([cx, cy, "H"])
				cx = x2
			else:
				cx += 1
	for cx in String(map[0]).length():
		var cy := 0
		while cy < map.size():
			if cluster_free(map, cx, cy) and _is_block(map, cx, cy - 1):
				var run := 0
				var y2 := cy
				while y2 < map.size() and cluster_free(map, cx, y2):
					run += 1
					y2 += 1
				if run == 1 and _is_block(map, cx, y2):
					out.append([cx, cy, "V"])
				cy = y2
			else:
				cy += 1
	return out

# ============================================================ наборы для листа/печати
static func biome_list() -> Array:
	return [
		{"id": "SNOW", "floors": [
			{"name": "SNOW_F1", "img": build_snow_f1(), "seam_h": true, "seam_v": true},
			{"name": "SNOW_F2", "img": build_snow_f2(), "seam_h": true, "seam_v": true}],
			"edges": [
			{"name": "SNOW_EDG_S", "img": build_snow_edge_s()},
			{"name": "SNOW_EDG_E", "img": build_snow_edge_e()}],
			"props": [
			{"name": "SNOW_PINE", "canon": "2.5H", "img": build_snow_pine()},
			{"name": "ICE_SPIKE", "canon": "1.25H", "img": build_ice_spike()},
			{"name": "SNOW_ROCK", "canon": "0.65H", "img": build_snow_rock()}]},
		{"id": "DESERT", "floors": [
			{"name": "DES_F1", "img": build_desert_f1(), "seam_h": true, "seam_v": true},
			{"name": "DES_F2", "img": build_desert_f2(), "seam_h": true, "seam_v": true}],
			"edges": [
			{"name": "DES_EDG_S", "img": build_desert_edge_s()},
			{"name": "DES_EDG_E", "img": edge_e(F_DES2, F_STEPPE, 11)}],
			"props": [
			{"name": "CACTUS", "canon": "1.6H", "img": build_cactus()},
			{"name": "MESA", "canon": "0.9H", "img": build_mesa()},
			{"name": "SKULL", "canon": "0.55H", "img": build_skull()}]},
		{"id": "STEPPE", "floors": [
			{"name": "STP_F1", "img": build_steppe_f1(), "seam_h": true, "seam_v": true},
			{"name": "STP_F2", "img": build_steppe_f2(), "seam_h": true, "seam_v": true}],
			"edges": [
			{"name": "STP_EDG_S", "img": build_steppe_edge_s()},
			{"name": "STP_EDG_E", "img": edge_e(F_STEPPE, F_MEADOW, 19)}],
			"props": [
			{"name": "TALLGRASS", "canon": "0.8H", "img": build_tallgrass()},
			{"name": "DRYBUSH", "canon": "0.75H", "img": build_drybush()},
			{"name": "STEP_ROCK", "canon": "0.5H", "img": build_steppe_rock()}]},
		{"id": "FOREST", "floors": [], "edges": [],
			"props": []},
		{"id": "CASTLE", "floors": [
			{"name": "CAS_F1", "img": build_castle_f1(), "seam_h": true, "seam_v": true},
			{"name": "CAS_F2", "img": build_castle_f2(), "seam_h": true, "seam_v": true}],
			"edges": [
			{"name": "CAS_EDG_S", "img": build_castle_edge_s()},
			{"name": "CAS_EDG_E", "img": build_castle_edge_e()}],
			"props": [
			{"name": "WALL_T", "canon": "1.9H mass", "img": build_wall_t()},
			{"name": "CRATE", "canon": "0.7H", "img": build_crate()},
			{"name": "BARREL", "canon": "0.75H", "img": build_barrel()},
			{"name": "BANNER", "canon": "1.1H", "img": build_banner()}]},
		{"id": "DUNGEON", "floors": [
			{"name": "DUN_F1", "img": build_dungeon_f1(), "seam_h": true, "seam_v": true},
			{"name": "DUN_F2", "img": build_dungeon_f2(), "seam_h": true, "seam_v": true}],
			"edges": [
			{"name": "DUN_EDG_S", "img": build_dungeon_edge_s()},
			{"name": "DUN_EDG_E", "img": build_dungeon_edge_e()}],
			"props": [
			{"name": "PILLAR_D", "canon": "1.6H mass", "img": build_pillar_d()},
			{"name": "SPIRE", "canon": "1.1H", "img": build_spire()},
			{"name": "FUNGUS", "canon": "0.9H", "img": build_fungus()},
			{"name": "BONEPILE", "canon": "0.5H", "img": build_bonepile()}]},
	]

static func portals() -> Array:
	var out: Array = []
	for b in ["SNOW", "DESERT", "STEPPE", "FOREST", "CASTLE", "DUNGEON"]:
		out.append({"name": "PORTAL_" + String(b), "canon": "1.6H", "img": portal_for(String(b))})
	return out

static func build_arch_north() -> Image:
	## Северная арка деревни (t3, w3): интерактор-выход на карту мира. 16×24
	## (1.5H): балка WOOD (СЗ-свет), каменная арка STONE_WARM «бегущий ряд»,
	## проезд прозрачный (герой ходит под аркой, y-sort по стопе).
	var img := im(16, 24)
	for xx in range(2, 14):
		px(img, xx, 0, C("WOOD", P.T_LIGHT))
	for xx in range(1, 15):
		px(img, xx, 1, C("WOOD", P.T_MID))
	for xx in range(1, 15):
		px(img, xx, 2, C("WOOD", P.T_DARK))
	for xx in 16:
		var c3: Color = C("STONE_WARM", P.T_MID)
		if xx == 0 or xx == 15:
			c3 = C("STONE_WARM", P.T_DARK)
		px(img, xx, 3, c3)
	for xx in 16:
		px(img, xx, 4, C("STONE_WARM", P.T_OUTLINE))
	for yy in range(5, 24):
		for xx in [0, 1, 2, 3, 12, 13, 14, 15]:
			if yy == 23:
				px(img, xx, yy, C("STONE_WARM", P.T_OUTLINE))
				continue
			var grout: bool = yy % 4 == 3 or (xx + (int(yy / 4.0) % 2) * 4) % 8 == 7
			if grout:
				px(img, xx, yy, C("STONE_WARM", P.T_OUTLINE))
			elif xx == 0 or xx == 12:
				px(img, xx, yy, C("STONE_WARM", P.T_LIGHT))
			elif xx == 3 or xx == 15:
				px(img, xx, yy, C("STONE_WARM", P.T_DARK))
			else:
				px(img, xx, yy, C("STONE_WARM", P.T_MID))
	CP.canon_pass(img)
	return img

static func extra_props() -> Array:
	## Артефакты вне шести биомов (обвязка w3): северная арка деревни.
	return [{"name": "ARCH_NORTH", "canon": "1.5H", "img": build_arch_north()}]

# ------------------------------------------------------------ дороги (t3)
## Тропы карты мира и локаций: PATH-семейство (канон деревенских дорог),
## 16-периодный механизм поля + колея DARK и гравий STONE_WARM (pxw — шов цел).
const F_ROAD := {"rn": "PATH", "base": P.T_MID, "l": 0.30, "lt": P.T_LIGHT, "d": 0.93, "drn": "PATH", "ox": 11, "oy": 5}
const F_ROAD2 := {"rn": "PATH", "base": P.T_MID, "l": 0.26, "lt": P.T_LIGHT, "d": 0.92, "drn": "PATH", "ox": 29, "oy": 43}

static func build_road_f1() -> Image:
	var img := im(16, 16)
	_field(img, F_ROAD)
	for x in 16:
		var y1: int = 5 if hp(x + 61, 13) > 0.5 else 6
		pxw(img, x, y1, C("PATH", P.T_DARK))
		if hp(x + 77, 29) > 0.15:
			var y2: int = 11 if hp(x + 77, 29) > 0.5 else 12
			pxw(img, x, y2, C("PATH", P.T_DARK))
	for i in 3:
		var sx: int = int(hp(13 + i * 29, 7) * 15.99)
		var sy: int = int(hp(23 + i * 11, 53) * 15.99)
		pxw(img, sx, sy, C("STONE_WARM", P.T_LIGHT))
	return img

static func build_road_f2() -> Image:
	var img := im(16, 16)
	_field(img, F_ROAD2)
	linew(img, 2, 3, 6, 4, C("PATH", P.T_LIGHT))
	linew(img, 9, 10, 13, 10, C("PATH", P.T_LIGHT))
	pxw(img, 12, 11, C("PATH", P.T_DARK))
	pxw(img, 4, 8, C("STONE_WARM", P.T_MID))
	pxw(img, 14, 6, C("STONE_WARM", P.T_LIGHT))
	return img

static func extra_floors() -> Array:
	## Доп. тайлы пола вне биомных сетов (t3): дорога.
	return [
		{"name": "ROAD_F1", "img": build_road_f1(), "seam_h": true, "seam_v": true},
		{"name": "ROAD_F2", "img": build_road_f2(), "seam_h": true, "seam_v": true},
	]

# ============================================================ BAKE (кандидат атласов)
static func bake_floor_atlas() -> Image:
	var tiles: Array = []
	for b in biome_list():
		for f in (b["floors"] as Array):
			tiles.append(f)
		for e in (b["edges"] as Array):
			tiles.append(e)
	for f in extra_floors():
		tiles.append(f)
	var out := im(tiles.size() * 16, 16)
	for i in tiles.size():
		out.blit_rect(tiles[i]["img"], Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
	return out

static func bake_floor_slots() -> Dictionary:
	var slots := {}
	var i := 0
	for b in biome_list():
		for f in (b["floors"] as Array):
			slots[String(f["name"])] = i
			i += 1
		for e in (b["edges"] as Array):
			slots[String(e["name"])] = i
			i += 1
	for f in extra_floors():
		slots[String(f["name"])] = i
		i += 1
	return slots

static func bake_props_atlas() -> Dictionary:
	## Упаковка та же, что forest: строки слева направо, alpha-trim, манифест
	## x/y/w/h + off_x/off_y (стопный якорь). Детерминированно.
	var sprites: Array = []
	for b in biome_list():
		for p in (b["props"] as Array):
			sprites.append(p)
	for p in portals():
		sprites.append(p)
	for p in extra_props():
		sprites.append(p)
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
