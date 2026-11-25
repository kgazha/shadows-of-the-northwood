class_name WorldWeapons
extends RefCounted
## t14 «Оружие v1» (вердикт пользователя 25.11 «спрайты внедряй»): мировые
## спрайты оружия — кодо-бейк assets/world/weapons_world_v1.png (генератор
## tools_art/weapons_world_v1.gd, md5-пин в qa_lp C33, FNV-равенство листу
## «Оружие v1» — в qa_gear G9). Ноль растров: png порождается кодом, как
## mobs_boar_v1.png; в дереве только артефакт бейка.
##
## ЛИСТ «Оружие v1» (diag-t10) предложил два кандидата спрайтов мира;
## вердикт 25.11 утвердил внедрение, вариант листа — KORYAGA (рекомендация
## листа явно не отменена). Разворот вердикта в «тёмную руку» = ОДНА
## константа ниже: ряд SILHOUETTE уже запечён в атлас (тот же рисовальщик,
## форма — кант BONE по открытым верху/леву).

const P := preload("res://scripts/pixel_palette.gd")

const ATLAS_PATH := "res://assets/world/weapons_world_v1.png"
const SLOT := 16

## Единый переключатель мирового стиля (см. шапку): true — KORYAGA (ряд 0,
## полный цвет), false — SILHOUETTE (ряд 1, CHAR DARK тело + световой кант).
const WORLD_ART_KORYAGA := true

## Порядок слотов атласа = порядок бейка; только оружие/щиты витрин
## (VENDOR_STOCK головы smith/merchant/hermit), доспехи не в стойке.
const SLOTS := ["sword", "axe", "rune_blade", "shortsword", "nordsword",
	"staff_apprentice", "staff_oak", "staff_rune",
	"bow_hunter", "bow_heavy", "shield_iron", "shield_raven"]

static var _img: Image = null
static var _loaded := false
static var _tex_cache := {}

static func row_index() -> int:
	return 0 if WORLD_ART_KORYAGA else 1

static func slot_index(id: String) -> int:
	return SLOTS.find(id)

static func _image() -> Image:
	if not _loaded:
		_loaded = true
		_img = null
		if ResourceLoader.exists(ATLAS_PATH):
			var res: Texture2D = load(ATLAS_PATH)
			if res != null:
				_img = res.get_image()
	return _img

static func available() -> bool:
	return _image() != null

## Кадр id как Image (QA-равенства; null — нет файла/слота).
static func frame_image(id: String) -> Image:
	var img := _image()
	var si := slot_index(id)
	if img == null or si < 0:
		return null
	return img.get_region(Rect2i(si * SLOT, row_index() * SLOT, SLOT, SLOT))

## Кадр id как AtlasTexture для витрины (кэш; null — нет файла/слота).
static func frame_texture(id: String) -> AtlasTexture:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var img := _image()
	var si := slot_index(id)
	if img == null or si < 0:
		return null
	var at := AtlasTexture.new()
	at.atlas = load(ATLAS_PATH)
	at.region = Rect2(si * SLOT, row_index() * SLOT, SLOT, SLOT)
	_tex_cache[id] = at
	return at
