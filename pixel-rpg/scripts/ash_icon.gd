class_name AshIcon
extends RefCounted
## t20: иконка Пепла для панелей мета-прогресса (экран смерти, Пепельная доска).
## Источник — атлас assets/item_icons.png (t23, 96x16 RGBA, 6 слотов по 16px:
## herb, mushroom, root, ASH, berry, glowcap). Слот 3 (x=48) сверен попиксельно
## с art_gen/items/item_ash_v2.png — это УТВЕРЖДЁННЫЙ ВАРИАНТ ash_v2 (вердикт
## пользователя, волна 4) — т.е. «подключить ash_v2» = показать именно этот слот.
## NEAREST-фильтр: иконка рисуются в нативных 16px (или целых кратных) — пиксель-
## арт не мылится; в отличие от фонов (PaperEdge/LINEAR) тут даунскейла нет.

const ATLAS := "res://assets/item_icons.png"
const SLOT := Rect2(48, 0, 16, 16)  # slot index 3 = "ash"

## atlas-текстура слота пепла; null, если атлас не найден (вызывающие глушат).
static func make() -> Texture2D:
	if not ResourceLoader.exists(ATLAS):
		push_warning("Нет ассета: assets/item_icons.png — иконка пепла пропущена")
		return null
	var at := AtlasTexture.new()
	at.atlas = load(ATLAS)
	at.region = SLOT
	return at

## Готовый TextureRect 16x16 (NEAREST, мышь не ест) для вставки в контейнеры.
static func make_rect(px: int = 16) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = make()
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
