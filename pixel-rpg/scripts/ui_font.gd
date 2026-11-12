class_name UIFont
extends RefCounted
## t27 P1-1: единая точка загрузки пиксельного шрифта интерфейса (Handjet, OFL —
## LICENSE.txt рядом с ttf). Кириллица покрыта (t27_font_check: has_char miss=0
## на А-Я а-я Ё ё + цифрах/знаках). Для глифов вне покрытия (•, ✓, ●, ○, →)
## включён fallback на движковый шрифт ThemeDB — ровно то, чем интерфейс
## рисовался до t27: никаких «тофу» и регрессий относительно бейзлайна.

const PATH := "res://assets/fonts/handjet.ttf"

## Шрифт или null (нет ассета — push_warning, интерфейс остаётся базовым).
static func get_font() -> Font:
	if not ResourceLoader.exists(PATH):
		push_warning("Нет ассета: assets/fonts/handjet.ttf — интерфейс базовым шрифтом")
		return null
	var f := load(PATH) as FontFile
	# 4.7 API: свойство называется `fallbacks` (мн. ч.); явный движковый fallback
	# детерминированнее системного (allow_system_fallback зависит от ОС-шрифтов).
	if f != null and f.fallbacks.is_empty() and ThemeDB.fallback_font != null:
		f.fallbacks = [ThemeDB.fallback_font]
	return f

## Применить к теме: шрифт + базовый размер (t27: ступень 8 -> 9).
static func apply(th: Theme, size: int) -> void:
	th.default_font = get_font()
	th.default_font_size = size
