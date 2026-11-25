class_name EnvArt
extends RefCounted
## «Среда v1» (t11, волна «Мир v2: наполнение», вердикт пользователя 25.11):
## рантайм-бейк утверждённых листом кодо-циклов — вода (лето/зима), факел
## (ночь с пульсом тона / плоский день), мох (лес LEAF / подземелье MOSS_GLOW /
## замок GRASS-лишайник, bright/dim). Функции кадра — ПОСТРОЧНЫЙ порт
## утверждённого листа pixel-rpg/tools_art/sheet_env_v1.gd (md5 листа
## E5EE113FC7937A962DE044C61A282E6D, PINS_W4.md 24.11): кадры побитово равны
## листным, что подтверждается FNV-пинами ниже (та же методика _fnv32_hex —
## FNV-1a 32 по PNG-байтам, рецепт cave_paint).
##
## Канон прокрутки — РЕШЕНИЕ ЛИСТА B: таймер-скинер int(t/T)%N + фаза
## shash(x,y) на клетку; t — СЧЁТ КАДРОВ (не wall-time!), в сейв не пишется.
## Ноль растровых файлов: всё рисуется кодом в RAM из PixelPalette (RAMPS/FLATS)
## — дельта палитры пуста, как на листе. Световой пульс факела — МОДУЛЯЦИЯ
## ТОНА ВНУТРИ РАМПЫ FIRE (без PointLight2D/shader, gl_compatibility).

const P := preload("res://scripts/pixel_palette.gd")
const OW := preload("res://scripts/open_world.gd")

# Тайминги листа (мс) -> кадры при 60 fps: T_MS * 60 / 1000.
const T_WATER := 18            # 300 мс x 4 = 1200 мс (лето: озеро/река/оазис)
const T_ICE := 24              # 400 мс x 4 = 1600 мс (зимнее подлёдное)
const T_TORCH := 15            # 250 мс x 4 = 1000 мс (пульс встроен в кадр)
const T_MOSS := 54             # 900 мс x 3 = 2700 мс (дыхание)

# FNV-пины кадров (PINS_W4.md, 24.11): hex FNV-1a 32 по PNG-байтам каждого
# кадра. self_check() сверяет рантайм-бейк с листом; расхождение = ЦИКЛ
# ПОЕХАЛ, интеграция запрещена (пины стенда qa_world «W7.1» — то же).
const FNV_PINS := {
	"WATER": ["916CE56A", "130922C5", "27F99733", "C0C96400"],
	"WINTER": ["2C185CFF", "C931C3DA", "70B76EE9", "E5178E52"],
	"TORCH_NIGHT": ["CD3CD0D4", "7BA1CD80", "03A6B317", "43CC7166"],
	"TORCH_DAY": ["5F56A198", "FAA0E90C", "A9C82B8A", "93473D09"],
	"MOSS_FOREST_B": ["0FB208DB", "838BDBC7", "87B3FBD6"],
	"MOSS_FOREST_D": ["5CEFA1D6", "C53D5942", "570C2A4D"],
	"MOSS_DUNGEON_B": ["F57772E7", "9ECBACC5", "7AD33271"],
	"MOSS_DUNGEON_D": ["AFFEF1C0", "D954E78F", "8A841296"],
	"MOSS_CASTLE_B": ["FECC65BD", "AAB2AE46", "974E98F4"],
	"MOSS_CASTLE_D": ["08D2D66D", "CBD88523", "D00C318E"],
}

# ============================================================================
# Кадры (построчный порт sheet_env_v1.gd — менять ТОЛЬКО зеркально с листом)
# ============================================================================

static func _c(rn: String, t: int) -> Color:
	return P.RAMPS[rn][t]

static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)

static func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func _wave_y(phase: int, base: int, amp: float) -> int:
	return base + int(round(amp + amp * sin(TAU * float(phase) / 16.0)))

## Озеро/река/оазис (лето): кадр f 16x16, непрозрачный, бесшовный по обеим
## осям; две синусные волны DARK ползут на 4 px/кадр, пена LIGHT на подъёме,
## блик WATER LIGHT на кадрах 1 и 3 (СЗ-четверть).
static func water_summer(f: int) -> Image:
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

## Зимняя variant (снежное озеро): лёд CRYSTAL, трещины WATER OUTLINE,
## подлёдная тьма ползёт на 1 px/кадр, льдинки дрейфуют на 3 px/кадр.
static func water_winter(f: int) -> Image:
	var img := _im(16, 16)
	img.fill(_c("CRYSTAL", P.T_MID))
	for pt in [[3, 3], [4, 4], [5, 4], [6, 5], [7, 6], [8, 6], [9, 7], [10, 8], [11, 8], [11, 9], [6, 7], [6, 8]]:
		_px(img, pt[0], pt[1], _c("WATER", P.T_OUTLINE))
	_px(img, 7, 5, _c("CRYSTAL", P.T_LIGHT))
	_px(img, 9, 8, _c("CRYSTAL", P.T_LIGHT))
	_px(img, 4 + f, 11, _c("WATER", P.T_DARK))
	_px(img, 5 + f, 11, _c("WATER", P.T_DARK))
	_px(img, 2 + 3 * f, 5, _c("CRYSTAL", P.T_LIGHT))
	_px(img, 3 + 3 * f, 5, _c("CRYSTAL", P.T_LIGHT))
	_px(img, 2 + 3 * f, 4, _c("WATER", P.T_LIGHT))
	if f == 0:
		_px(img, 12, 2, _c("WATER", P.T_LIGHT))
	if f == 2:
		_px(img, 2, 12, _c("WATER", P.T_LIGHT))
	return img

## Силуэты пламени (x, y, тон), тон — символ рампы FIRE; H = FLAT FIRE_HOT.
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
static func _pulse_tone(sym: String, mode: int) -> String:
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
	if sym == "H":
		return "M"
	if sym == "L":
		return "M"
	if sym == "M":
		return "D"
	if sym == "D":
		return "O"
	return "O"

## Факел 10x15: ночь — 4 кадра с пульсом тона; день — силуэты без ядра/пульса.
static func torch(f: int, night: bool) -> Image:
	var img := _im(10, 15)
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
	_px(img, 3, 8, _c("IRON", P.T_LIGHT))
	_px(img, 4, 8, _c("IRON", P.T_MID))
	_px(img, 5, 8, _c("IRON", P.T_MID))
	_px(img, 6, 8, _c("IRON", P.T_DARK))
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

## Моховое пятно 16x16 — оверлей на камень (прозрачный вне силуэта).
const MOSS_ROWS := {5: [5, 9], 6: [3, 11], 7: [2, 13], 8: [1, 14], 9: [1, 14], 10: [2, 12], 11: [2, 11], 12: [3, 10]}
const MOSS_D := [[6, 10], [6, 11], [7, 11], [7, 12], [7, 13], [8, 12], [8, 13], [8, 14],
	[9, 12], [9, 13], [9, 14], [10, 10], [10, 11], [10, 12], [11, 8], [11, 9], [11, 10], [11, 11]]
const MOSS_L_BRIGHT := [[5, 5], [7, 5], [4, 6], [3, 7], [6, 7], [5, 8]]
const MOSS_L_DIM := [[5, 5], [7, 5], [4, 6]]
const MOSS_D_DIM_EXTRA := [[8, 10], [9, 10], [4, 9]]

static func moss(ramp: String, bright: bool, f: int) -> Image:
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

# ============================================================================
# Бейк полос и кадр-доступ
# ============================================================================

static var _strips: Dictionary = {}      # ключ -> ImageTexture (горизонт. полоса)
static var _atlases: Dictionary = {}     # "ключ:idx" -> AtlasTexture (кэш, без аллокаций на кадр)

static func _bake_strip(key: String, frames: Array, fw: int, fh: int) -> ImageTexture:
	if _strips.has(key):
		return _strips[key]
	var img := _im(fw * frames.size(), fh)
	for i in frames.size():
		var fimg: Image = frames[i]
		img.blit_rect(fimg, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
	var t := ImageTexture.create_from_image(img)
	t.resource_name = key
	_strips[key] = t
	return t

## Полосы циклов. Ключи — префиксы atlas-кэшей, пинятся стендом (W7).
static func strip_water(snow: bool) -> ImageTexture:
	var key := "EnvWtrW" if snow else "EnvWtrS"
	if _strips.has(key):
		return _strips[key]
	var frames: Array = []
	for f in 4:
		frames.append(water_winter(f) if snow else water_summer(f))
	return _bake_strip(key, frames, 16, 16)

static func strip_torch(night: bool) -> ImageTexture:
	var key := "EnvTrN" if night else "EnvTrD"
	var frames: Array = []
	for f in 4:
		frames.append(torch(f, night))
	return _bake_strip(key, frames, 10, 15)

## zone_key: "FOREST" | "DUNGEON" | "CASTLE" (рампы LEAF / MOSS_GLOW / GRASS).
static func strip_moss(zone_key: String, bright: bool) -> ImageTexture:
	var ramp: String = String({"FOREST": "LEAF", "DUNGEON": "MOSS_GLOW", "CASTLE": "GRASS"}.get(zone_key, "LEAF"))
	var key := "EnvMoss%s%s" % [zone_key, "B" if bright else "D"]
	var frames: Array = []
	for f in 3:
		frames.append(moss(String(ramp), bright, f))
	return _bake_strip(key, frames, 16, 16)

## AtlasTexture кадра idx полосы (общий кэш — скиннер не аллоцирует на кадр).
static func atlas_of(tex: ImageTexture, idx: int, fw: int) -> AtlasTexture:
	var key := "%s:%d" % [String(tex.resource_name), idx]
	if _atlases.has(key):
		return _atlases[key]
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(idx * fw, 0, fw, tex.get_height())
	_atlases[key] = at
	return at

# ============================================================================
# Скинер листа: вариант B — int((ticks+фаза)/K)%N, ticks — счётчик кадров
# ============================================================================

## Фаза клетки (0..K*N-1 кадров сдвига): shash от координат (тот же FNV-1a 32,
#  что во всём Мире v1; системный hash() запрещён аудитом F3).
static func cell_phase(x: int, y: int, k: int, n: int) -> int:
	return OW.shash("env:%d,%d" % [x, y]) % (k * n)

static func cell_frame(ticks: int, phase: int, k: int, n: int) -> int:
	return int((ticks + phase) / k) % n

class EnvTicker:
	extends Node2D
	## Таймер-скинер варианта B: t — счётчик КАДРОВ (не wall-time): в headless
	## и на паузе детерминирован; в сейв не пишется; живёт в контейнере зоны —
	## вне зоны зона PROCESS_MODE_DISABLED и тики стоят (картинка не «догоняется»).
	var items: Array = []      # {spr, tex, fw, k, n, ph, last}
	var ticks := 0

	func add_spr(spr: Sprite2D, tex: ImageTexture, fw: int, k: int, n: int, phase: int) -> void:
		var i0 := EnvArt.cell_frame(0, phase, k, n)
		spr.texture = EnvArt.atlas_of(tex, i0, fw)
		items.append({"spr": spr, "tex": tex, "fw": fw, "k": k, "n": n, "ph": phase, "last": i0})

	func _process(_delta: float) -> void:
		ticks += 1
		for it in items:
			var idx := EnvArt.cell_frame(ticks, int(it["ph"]), int(it["k"]), int(it["n"]))
			if idx != int(it["last"]):
				it["last"] = idx
				var spr: Sprite2D = it["spr"]
				if spr != null and is_instance_valid(spr):
					spr.texture = EnvArt.atlas_of(it["tex"], idx, int(it["fw"]))

# ============================================================================
# Самопроверка против листа (использует стенд qa_world W7.1)
# ============================================================================

## Кадры цикла как одиночные Images (тот же побайтовый путь, что на листе).
static func cycle_frames(cycle: String) -> Array:
	match cycle:
		"WATER":
			return [water_summer(0), water_summer(1), water_summer(2), water_summer(3)]
		"WINTER":
			return [water_winter(0), water_winter(1), water_winter(2), water_winter(3)]
		"TORCH_NIGHT":
			return [torch(0, true), torch(1, true), torch(2, true), torch(3, true)]
		"TORCH_DAY":
			return [torch(0, false), torch(1, false), torch(2, false), torch(3, false)]
		"MOSS_FOREST_B":
			return [moss("LEAF", true, 0), moss("LEAF", true, 1), moss("LEAF", true, 2)]
		"MOSS_FOREST_D":
			return [moss("LEAF", false, 0), moss("LEAF", false, 1), moss("LEAF", false, 2)]
		"MOSS_DUNGEON_B":
			return [moss("MOSS_GLOW", true, 0), moss("MOSS_GLOW", true, 1), moss("MOSS_GLOW", true, 2)]
		"MOSS_DUNGEON_D":
			return [moss("MOSS_GLOW", false, 0), moss("MOSS_GLOW", false, 1), moss("MOSS_GLOW", false, 2)]
		"MOSS_CASTLE_B":
			return [moss("GRASS", true, 0), moss("GRASS", true, 1), moss("GRASS", true, 2)]
		"MOSS_CASTLE_D":
			return [moss("GRASS", false, 0), moss("GRASS", false, 1), moss("GRASS", false, 2)]
	return []

## FNV-1a 32 по PNG-байтам (рецепт листа _fnv32_hex).
static func fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

## Палитрная чистота кадра (off = чужих пикселей, mask = полупрозрачных).
static func palette_scan(img: Image) -> Dictionary:
	var idx := P.color_index()
	var off := 0
	var mask := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a < 0.5:
				continue
			if col.a < 1.0:
				mask += 1
				continue
			if not idx.has(P.key(col)):
				off += 1
	return {"off": off, "mask": mask}

## Список расхождений с листом (пустой = бейк == утверждённый лист).
static func self_check() -> PackedStringArray:
	var out: PackedStringArray = []
	for cycle in FNV_PINS:
		var frames := cycle_frames(String(cycle))
		var pins: Array = FNV_PINS[cycle]
		if frames.size() != pins.size():
			out.append("%s: кадров %d, пинов %d" % [cycle, frames.size(), pins.size()])
			continue
		for i in frames.size():
			var h := fnv32_hex(frames[i])
			if h != String(pins[i]):
				out.append("%s f%d: FNV %s != пин %s" % [cycle, i, h, pins[i]])
			var sc := palette_scan(frames[i])
			if int(sc["off"]) > 0 or int(sc["mask"]) > 0:
				out.append("%s f%d: палитра off=%d mask=%d" % [cycle, i, sc["off"], sc["mask"]])
	return out
