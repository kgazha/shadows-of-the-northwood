class_name Ash
extends RefCounted
# Пепел — мета-валюта NG+ (docs/RETENTION_NG_PLUS.md §4).
# Хранение: GameState.flags["meta.ash"] : int. GameState как узел не трогаем.

const KEY := "meta.ash"

static func balance(gs = null) -> int:
	if gs == null:
		gs = GameState
	return int(gs.flags.get(KEY, 0))

static func add(n: int) -> void:
	n = int(n)
	if n <= 0:
		return
	GameState.flags[KEY] = balance() + n

static func spend(n: int) -> bool:
	n = int(n)
	if n <= 0:
		return false
	var cur := balance()
	if cur < n:
		return false
	GameState.flags[KEY] = cur - n
	GameState.save_game()
	return true
