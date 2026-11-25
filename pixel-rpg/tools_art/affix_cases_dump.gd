extends SceneTree
## t17 «Глубина v2 §1: Аффиксы» (25.11): генератор детерминизм-кейсов для
## источника истины стойки qa_gear G10 (50 бит-в-бит пар «вход -> ролл»).
## Это НЕ рантайм: только печать таблицы. Реролл таблицы при смене канона
## ролла — сознательный датированный перепин, а не тихая правка.
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/affix_cases_dump.gd

func _init() -> void:
	# ЧИСТЫЙ модуль (ни GameState, ни сцен) — компилируется в -s без игры.
	var affix: GDScript = load("res://scripts/affixes.gd")
	var seeds: Array = [7, 777]
	var cells: Array = ["0,0", "5,21", "17,-4", "chest:village@9,12", "chest:ashen"]
	var ords: Array = [0, 1, 2, 7, 4242]  # 2 x 5 x 5 = ровно 50 кейсов
	var n := 0
	for s in seeds:
		for c in cells:
			for o in ords:
				if n >= 50:
					break
				var arr: Array = affix.affix_roll(int(s), String(c), int(o))
				print("\t\t\"%d|%s|%d\": %s," % [s, c, o, str(arr)])
				n += 1
	print("cases=%d" % n)
	quit(0)
