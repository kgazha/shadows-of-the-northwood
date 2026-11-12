extends "res://mb_base.gd"
## QA WR0 (T13): «тенеплёт» убран из геймплея полностью по вердикту пользователя
## («убери монстра призрака, напрягает в геймплее»). Прежняя секция репро
## «вечного призрака» неактуальна: живых спавнов больше нет ни в одной зоне.
## Стенд-страж проверяет новое постоянство:
##   S1 — 0 живых узлов mob_wraith в деревне / пещере (босс ЖИВ на save_for(0):
##        раньше здесь строились 2 тенеплёта в нише) / Пепелище (раньше 4);
##   S2 — резерв жив: скрипт mob_wraith.gd существует, компилируется и
##        инстанцируется без ошибок (арт-ассеты не трогаем);
##   S3 — схема/детерминизм генератора не тронуты: ashen_map.meta.mobs по-прежнему
##        содержит координаты «wraiths» (данные есть, спавна нет).
## Тостов с именем моба при сборке мира быть не должно. RESULT: X pass / Y fail.

func _ready() -> void:
	await boot(save_for(0))
	await pump(3)
	# --- S1: ноль живых тенеплётов во всех трёх зонах ---
	var vw: Array = find_mob(world.village_zone, "mob_wraith")
	check("WR0: деревня — живых тенеплётов 0 (n=%d)" % vw.size(), vw.is_empty())
	var dw: Array = find_mob(world.dungeon_zone, "mob_wraith")
	check("WR0: пещера при живом боссе — живых тенеплётов 0 (n=%d)" % dw.size(), dw.is_empty())
	var az: Node = world.get("ashen_zone")
	if az != null:
		var aw: Array = find_mob(az, "mob_wraith")
		check("WR0: Пепелище — живых тенеплётов 0 (n=%d)" % aw.size(), aw.is_empty())
	else:
		check("WR0: Пепелище построено (ожидалось)", false)
	check("WR0: при сборке мира тостов «Тенеплёт» не было", n_toast("Тенеплёт") == 0)
	# --- S2: резерв компилируется и создаётся ---
	var wpath := "res://scripts/mob_wraith.gd"
	check("WR0: скрипт-резерв существует", ResourceLoader.exists(wpath))
	var s: Script = load(wpath)
	check("WR0: скрипт-резерв компилируется", s != null)
	if s != null:
		var inst: Object = s.new()
		check("WR0: резервный инстанс создаётся без ошибок", inst != null)
		if inst != null:
			inst.free()
	# --- S3: генераторную схему не трогали — координаты есть, спавна нет ---
	var amap: Dictionary = world.get("ashen_map")
	var meta: Dictionary = amap.get("meta", {})
	var mobs: Dictionary = meta.get("mobs", {})
	var wlist: Array = mobs.get("wraiths", [])
	check("WR0: генератор Пепелища по-прежнему эммитит mobs.wraiths (n=%d) — схема/сиды целы" % wlist.size(),
		wlist.size() >= 1)
	done()
