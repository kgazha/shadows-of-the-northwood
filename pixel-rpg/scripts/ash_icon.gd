class_name AshIcon
extends RefCounted
## t20: иконка Пепла для панелей мета-прогресса (экран смерти, Пепельная доска).
## t52 снос (закон пользователя 13.11): ген-атлас иконок предметов снят — пепел
## рисуется кодом (UiIcons: контур+символ, 16 px). API прежнее: make()/make_rect().

## код-заглушка слота пепла (16 px RGBA8, без картинок).
static func make() -> Texture2D:
	return UiIcons.item_icon("ash")

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
