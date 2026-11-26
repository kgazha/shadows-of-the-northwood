extends "res://mb_base.gd"
## QA BTY — t36 I3 «Доска охот» (26.11, волна «Интерес v1»; вердикт: «причина
## вернуться»). Пины ровно контракта I3: детерминированный выбор дня (двое
## суток / два сида побитово; имя — из кодо-слогов 20×20, не пусто), цель
## спавнится именованной ЭЛИТОЙ I1 (hp x2, плашка своим именем, аура; статы
## живут и при bold_fx OFF — закон t23), маркер «†» зоны цели (чистая функция
## + гейт тумана t7 «в радиусе»), награда ровно ОДИН раз (флаг-2-до-выдачи
## канон; точная выплата; канал смерти loot даёт элитный +1 pity сверх +2),
## сброс по истечении дня без штрафа, журнал показывает активную охоту,
## belt-цепь не тронута. (Имя qa_bty: qa_bt занят стендом ребаланса лута t62.)

const BD := preload("res://scripts/bounties.gd")
const QD := preload("res://scripts/quests_data.gd")

var _toasts: Array = []

func _ready() -> void:
	await boot(save_for(0))
	await pump(3)
	GameState.toast.connect(func(t: String) -> void: _toasts.append(t))
	_s1()
	await _s2()
	await _s3()
	await _s4()
	await _s5()
	await _s6()
	await _s7()
	done()

func _open_all() -> void:
	for z in ["snow", "steppe", "forest"]:
		GameState.set_flag("wm.open." + z, "1")

func _reset_state() -> void:
	GameState.set_flag("q.bty.day", -1)
	GameState.set_flag("q.bty.state", 0)

# ------------------------------------------------------- детермин + имя
func _s1() -> void:
	GameState.enroute_events = true
	GameState.day_t = 10.0
	_open_all()
	_reset_state()
	var o1: Dictionary = BD.offer(GameState)
	var o1b: Dictionary = BD.offer(GameState)
	check("S1 два чтения одного дня побитово равны (%s)" % String(o1.get("name", "")),
		str(o1) == str(o1b) and not o1.is_empty())
	GameState.day_t = BD.ENR.CYCLE + 10.0
	var o2: Dictionary = BD.offer(GameState)
	GameState.day_t = 2.0 * BD.ENR.CYCLE + 10.0
	var o3: Dictionary = BD.offer(GameState)
	GameState.day_t = 10.0
	check("S1 двое суток — разные объявления (день0≠день1≠день2)",
		str(o1) != str(o2) and str(o2) != str(o3))
	GameState.run_seed = 777
	var o777: Dictionary = BD.offer(GameState)
	GameState.run_seed = 42
	var o42: Dictionary = BD.offer(GameState)
	check("S1 два сида: 777≠42 и 42 побитово == прежнему",
		str(o777) != str(o42) and str(o42) == str(o1))
	var nm := String(o1["name"])
	var okn := false
	for a in BD.SYL_A:
		for b in BD.SYL_B:
			if String(a) + String(b) == nm:
				okn = true
	check("S1 имя «%s» не пусто и из слогов 20×20" % nm, nm != "" and okn)
	check("S1 пояс/зона/клетка согласованы (gold=40+25·belt, belt=%d)" % int(o1["belt"]),
		int(o1["gold"]) == BD.bounty_gold(int(o1["belt"])) and String(o1["zone"]) != "")

# ------------------------------------------------------------ доска/журнал
func _s2() -> void:
	_reset_state()
	GameState.day_t = 10.0
	BD.take(GameState)
	check("S2 взятие: статус 1, тост с «охота»", BD.status(GameState) == 1 and _toasts.size() > 0)
	_toasts.clear()
	BD.take(GameState)
	check("S2 повторное take не сдваивает (1 активная)", BD.status(GameState) == 1)
	var found := ""
	for e in QD.entries(GameState):
		if String((e as Dictionary).get("id", "")).begins_with("bty_"):
			found = String((e as Dictionary).get("title", ""))
	check("S2 журнал (J) показывает активную охоту: [%s]" % found, found.begins_with("Охота: "))
	check("S2 belt-цепь не тронута (current=0, статус NONE)",
		QD.belt_current(GameState) == 0 and QD.belt_status(GameState, 0) == 0)

# ------------------------------------------------------ цель = элита
func _find_meta(n: Node, key: String, out: Array) -> void:
	if n.has_meta(key):
		out.append(n)
	for ch in n.get_children():
		_find_meta(ch, key, out)

# Стендовый эквивалент боя: в игре цель роняет удар (die+queue_free). Здесь
# «смерть» рукописная, поэтому перед новым заходом снимаем ВСЕ tagged-узлы
# напрямую (зоны — постоянные дети world, их мобы переживают apply_area).
func _wipe_targets() -> int:
	var arr: Array = []
	_find_meta(world, "i3_bounty", arr)
	for n in arr:
		(n as Node).free()
	BD._despawn_target()
	return arr.size()

func _s3() -> void:
	_reset_state()
	GameState.day_t = 10.0
	var o: Dictionary = BD.offer(GameState)
	BD.take(GameState)
	world.apply_area("loc_" + String(o["zone"]))
	await pump(3)
	var targets: Array = []
	_find_meta(world, "i3_bounty", targets)
	check("S3 цель заспавнена одна при входе в зону (%d)" % targets.size(), targets.size() == 1)
	if targets.is_empty():
		return
	var m: Node = targets[0]
	check("S3 цель — элита I1 (meta elite) с СВОИМ именем на плашке",
		bool(m.get_meta("elite")) and m.get_node_or_null("ElitePlate") != null
			and String(m.get_node("ElitePlate").text) == String(o["name"]))
	var zone: Node = world.biome_grids.get(String(o["zone"]))
	var plain: Node = zone.call("spawn_event_mob", String(o["fam"]), o["tile"] as Vector2i)
	check("S3 комплект hp x2 против простого моба того же пояса (%d vs %d)" % [int(m.hp), int(plain.hp)],
		plain != null and int(m.hp) == 2 * int(plain.hp))
	if plain != null:
		plain.free()
	# закон t23: OFF глушит украшение, не статы
	GameState.bold_fx = false
	BD._despawn_target()
	world.apply_area("village")
	await pump(1)
	world.apply_area("loc_" + String(o["zone"]))
	await pump(3)
	var t2: Array = []
	_find_meta(world, "i3_bounty", t2)
	if t2.size() == 1:
		var m2: Node = t2[0]
		check("S3 bold_fx OFF: плашки нет, статы элиты целы (hp=%d)" % int(m2.hp),
			m2.get_node_or_null("ElitePlate") == null and int(m2.hp) >= 2 and bool(m2.get_meta("elite")))
	GameState.bold_fx = true

# ------------------------------------------------------ маркер «†»
func _s4() -> void:
	var o: Dictionary = BD.offer(GameState)
	check("S4 маркер указывает на зону цели (%s)" % String(o["zone"]),
		BD.map_marker_zone(GameState) == String(o["zone"]))
	world.apply_area("worldmap")
	await pump(2)
	var wm: Node = world.worldmap_grid
	var cell: Vector2i = (wm.call("portals_dict") as Dictionary)[String(o["zone"])]
	GameState.wm_fog.reveal_disk(cell, 6.0)
	wm.call("refresh_fog")
	await pump(1)
	check("S4 «в радиусе»: портал открыт туманом — маркер показуется",
		not bool(wm.call("portal_fogged", String(o["zone"]))))
	# охота закрыта -> маркера нет
	GameState.set_flag("q.bty.state", 2)
	check("S4 после закрытия маркера нет", BD.map_marker_zone(GameState) == "")
	GameState.set_flag("q.bty.state", 1)

# ------------------------------------------------------ награда ровно раз
func _s5() -> void:
	var o: Dictionary = BD.offer(GameState)
	world.apply_area("loc_" + String(o["zone"]))
	await pump(2)
	var targets: Array = []
	_find_meta(world, "i3_bounty", targets)
	if targets.is_empty():
		check("S5 цель не нашлась для выдачи", false)
		return
	var m: Node = targets[0]
	var g0 := int(GameState.gold)
	var p0 := int(GameState.elite_pity)
	_toasts.clear()
	BD.on_bounty_death(GameState, m)
	check("S5 точная выплата: +%d серебра (пин 40+25·belt) и pity +2" % int(o["gold"]),
		int(GameState.gold) - g0 == int(o["gold"]) and int(GameState.elite_pity) - p0 == 2)
	check("S5 статус 2 (флаг ДО выдачи) + ровно один тост",
		BD.status(GameState) == 2 and _toasts.size() == 1)
	var g1 := int(GameState.gold)
	BD.on_bounty_death(GameState, m)
	check("S5 повторная смерть награду не повторяет", int(GameState.gold) == g1)
	# Живой канал: Loot.on_mob_death (who=цель) на НОВОЙ охоте — элитный лут
	# даёт +1 pity (t34) + 2 охоты; серебро >= пина награды (лут сверху).
	# Ручная «смерть» выше не роняла узел (в бою это делает удар) — снимаем
	# цель штатным _despawn_target, иначе WeakRef цели сбивает ensure().
	BD._despawn_target()
	var wiped := _wipe_targets()
	_reset_state()
	world.apply_area("village")
	BD.take(GameState)
	var o2: Dictionary = BD.offer(GameState)
	world.apply_area("loc_" + String(o2["zone"]))
	await pump(2)
	var t2: Array = []
	_find_meta(world, "i3_bounty", t2)
	if t2.size() != 1:
		check("S5 канал: вторая цель size=%d wiped=%d st=%d" % [t2.size(), wiped, BD.status(GameState)], false)
		return
	var m2: Node = t2[0]
	var g2 := int(GameState.gold)
	var p2 := int(GameState.elite_pity)
	Loot.on_mob_death(String(m2.get("loot_kind")), m2.global_position, null, m2)
	check("S5 канал смерти: награда + лут элиты, pity ровно +3 (1 элита + 2 охота)",
		int(GameState.gold) - g2 >= int(o2["gold"]) and int(GameState.elite_pity) - p2 == 3)

# ------------------------------------------------------ просрочка-сброс
func _s6() -> void:
	_reset_state()
	GameState.day_t = 10.0
	BD.take(GameState)
	var g0 := int(GameState.gold)
	var p0 := int(GameState.elite_pity)
	var h0 := int(GameState.herbs)
	_toasts.clear()
	GameState.day_t = BD.ENR.CYCLE + 10.0   # рассвет наступил
	BD.cull(GameState)
	check("S6 сброс по истечении дня: статус 0, мягкий тост «истекла»",
		BD.status(GameState) == 0 and _toasts.size() == 1 and String(_toasts[0]).contains("истекла"))
	check("S6 без штрафа: золото/pity/травы целы",
		int(GameState.gold) == g0 and int(GameState.elite_pity) == p0 and int(GameState.herbs) == h0)
	check("S6 доска снова предлагает (перевзятие бесплатное)", BD.hunt_hint(GameState) != "")
	BD.take(GameState)
	check("S6 перевзятие работает", BD.status(GameState) == 1)

# -------------------------------------------------- журнал/закрытая/нет зон
func _s7() -> void:
	var e_done := false
	GameState.set_flag("q.bty.state", 2)
	for e in QD.entries(GameState):
		if String((e as Dictionary).get("id", "")).begins_with("bty_"):
			var tg: Array = (e as Dictionary).get("targets", []) as Array
			if tg.size() == 1 and bool((tg[0] as Dictionary).get("done", false)):
				e_done = true
	check("S7 журнал: закрытая охота показана целью выполненной", e_done)
	# нет открытых зон — доска молчит, охоты нет
	for z in ["snow", "steppe", "forest"]:
		GameState.set_flag("wm.open." + z, "")
	_reset_state()
	check("S7 без открытых поясов охоты нет", BD.offer(GameState).is_empty() and BD.hunt_hint(GameState) == "")
	BD.take(GameState)
	check("S7 take без зон — no-op", BD.status(GameState) == 0)
	_open_all()
	_reset_state()
	GameState.day_t = 0.0
	check("S7 разбор: флаги охоты нейтральны (day=-1, state=0)",
		int(GameState.get_flag("q.bty.day", -9)) == -1 and int(GameState.get_flag("q.bty.state", -9)) == 0)
