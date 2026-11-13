class_name PixelPalette
extends RefCounted
## Единый модуль палитры канона «hand-made пиксель» (docs/PIXEL_STYLE.md, t53).
##
## Закон пользователя 13.11: полноценная глубина цвета (PNG32/RGBA8), НЕ 8-bit:
## никакого квантизационного куба, никаких системных палитр, никаких полос
## дизеринга ради имитации градиентов.
##
## Правила, которые обеспечивает этот модуль (см. PIXEL_STYLE.md):
##  1. Единственный источник цвета: любой новый спрайт/иконка/FX рисуются
##     ТОЛЬКО цветами из RAMPS (или SHEET — для технических листов). Другие
##     цвета запрещены; инструменты рисовки обязаны это проверять.
##  2. Ramp материала = ровно 4 тона: [LIGHT, MID, DARK, OUTLINE].
##     Больше четырёх тонов на материал — спорно, меньше — бедно.
##  3. Единый источник света — СЕВЕРО-ЗАПАД (верх-лево):
##     LIGHT — верхняя/левая открытая грань, DARK — боковая правая,
##     OUTLINE — самый тёмный тон материала: нижний/нижне-боковой контур
##     (чистый #000000 forbidden — контур всегда тонирован материалом).
##  4. OUTLINE — не отдельный цвет «чёрный», а 4-й тон каждого материала,
##     поэтому контур остаётся цветным и тёплым/холодным в своей зоне.
##
## Зоны: FOREST (лес/деревня — базовые), CAVE (пещеры), ASHEN (Пепелище),
## UI (интерфейс). Материалы зон намеренно разделены: один материал в двух
## зонах = два разных рампа (STONE vs CAVE_ROCK vs ASH_GROUND).

const T_LIGHT := 0
const T_MID := 1
const T_DARK := 2
const T_OUTLINE := 3

# --- Лес / деревня (база) ----------------------------------------------------
const GRASS := [Color("7aa551"), Color("5c8740"), Color("40632e"), Color("2a4620")]
const PATH := [Color("a8825a"), Color("8a6844"), Color("674c31"), Color("453220")]
const WOOD := [Color("d1a266"), Color("b08249"), Color("85603a"), Color("57402a")]
const BARK := [Color("8a6a4a"), Color("6e5238"), Color("4f3a27"), Color("33251a")]
const ROOF := [Color("b0765a"), Color("8f5c45"), Color("6b4232"), Color("452a20")]
const STONE := [Color("b3b6bd"), Color("94979e"), Color("70747c"), Color("494d55")]
const STONE_WARM := [Color("b0a894"), Color("918a77"), Color("6d6757"), Color("464236")]
const WATER := [Color("8fd0e0"), Color("5ca3c0"), Color("3a7694"), Color("214a63")]
const LEAF := [Color("83b457"), Color("5f9140"), Color("42682c"), Color("29441c")]
const PINE := [Color("6f9f63"), Color("527f4a"), Color("385c34"), Color("22391f")]
const FIRE := [Color("ffd98a"), Color("ff9e3d"), Color("d95a22"), Color("6e2f13")]
const FIRE_HOT := Color("fff3cf")  # единственная «горячая» точка (ядро пламени)
const CLOTH := [Color("d4614a"), Color("ab4433"), Color("7c2e24"), Color("4e1b15")]
const IRON := [Color("a3a8b2"), Color("838892"), Color("5f646e"), Color("3a3e46")]

# --- Пещеры -------------------------------------------------------------------
const CAVE_ROCK := [Color("7c8299"), Color("5f657c"), Color("454a5f"), Color("2b2f40")]
const CRYSTAL := [Color("a5e2f2"), Color("6fb7d4"), Color("4887a8"), Color("2a5570")]
const MOSS_GLOW := [Color("8fdba0"), Color("5fae76"), Color("3d7a52"), Color("234c33")]
const CAVE_WATER := [Color("7fb8d8"), Color("5688ac"), Color("38607e"), Color("203c52")]

# --- Пепелище -------------------------------------------------------------------
const ASH_GROUND := [Color("7a706c"), Color("5e5551"), Color("443d3a"), Color("292422")]
const CHAR := [Color("554a45"), Color("403733"), Color("2c2623"), Color("191514")]
const ASH_EMBER := [Color("ffc06a"), Color("f57b31"), Color("c24a17"), Color("5f240c")]
const BONE := [Color("e2d8c2"), Color("c0b69f"), Color("948b77"), Color("5f584a")]

# --- UI -------------------------------------------------------------------
const PARCHMENT := [Color("f2e4ba"), Color("ddc894"), Color("b9a06e"), Color("7d6a4b")]
const BRONZE := [Color("dca863"), Color("ab7646"), Color("7c5230"), Color("4c321d")]
const UI_BLUE := [Color("7fb0cf"), Color("5787a8"), Color("3a607c"), Color("223d50")]
const HUD_GOLD := [Color("ffd873"), Color("e3ac41"), Color("ab7c2b"), Color("6d4d1a")]
const HP_RED := [Color("e2604e"), Color("b93f31"), Color("85281f"), Color("521712")]
const INK := Color("3b3029")  # плоский цвет текста/обводки UI (без ramp)

# Технические цвета листов-вердиктов (НЕ для игровых спрайтов).
const SHEET := {
	"BG": Color("23262c"),
	"PANEL": Color("2d313a"),
	"LINE": Color("3a3f4a"),
	"TEXT": Color("f2e4ba"),
}

## Все material-рампы по имени (канон: список закрытый, новые — только вердиктом).
const RAMPS := {
	"GRASS": GRASS, "PATH": PATH, "WOOD": WOOD, "BARK": BARK, "ROOF": ROOF,
	"STONE": STONE, "STONE_WARM": STONE_WARM, "WATER": WATER, "LEAF": LEAF,
	"PINE": PINE, "FIRE": FIRE, "CLOTH": CLOTH, "IRON": IRON,
	"CAVE_ROCK": CAVE_ROCK, "CRYSTAL": CRYSTAL, "MOSS_GLOW": MOSS_GLOW,
	"CAVE_WATER": CAVE_WATER,
	"ASH_GROUND": ASH_GROUND, "CHAR": CHAR, "ASH_EMBER": ASH_EMBER, "BONE": BONE,
	"PARCHMENT": PARCHMENT, "BRONZE": BRONZE, "UI_BLUE": UI_BLUE,
	"HUD_GOLD": HUD_GOLD, "HP_RED": HP_RED,
}

## Допустимые «плоские» цвета вне рамп ( technically justified points ).
const FLATS := {
	"FIRE_HOT": FIRE_HOT,
	"INK": INK,
}


static func r(name: String) -> Array:
	assert(RAMPS.has(name), "PixelPalette: неизвестный материал " + name)
	return RAMPS[name]


static func c(name: String, tone: int) -> Color:
	return r(name)[tone]


## Аргб-ключ цвета (для точных сравнений пиксель↔палитра).
static func key(col: Color) -> int:
	return col.to_argb32()


## Карта argb32 -> [имя_рампа, тон]; для авторазбора и самопроверк.
static func color_index() -> Dictionary:
	var out := {}
	for rn in RAMPS:
		var ramp: Array = RAMPS[rn]
		for t in ramp.size():
			out[key(ramp[t])] = [rn, t]
	for fn in FLATS:
		out[key(FLATS[fn])] = [fn, -1]
	return out
