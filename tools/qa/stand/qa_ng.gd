extends Node
## QA-стенд NG+ «Круги Пепла» (P1): формулы §1.3, сброс/перенос §1.2, скейл мобов
## при спавне, золотой EV (200 роллов ×2 прогона), кап волны, старый сейв без ng.*.
## ВНИМАНИЕ: служебный файл QA, в сдачу (sand_ng.diff) НЕ входит.

const SAVE := "user://save_morkheim.json"

var _p := 0
var _f := 0
var _fails: Array = []
var world_node

func ck(cname: String, cond: bool, note := "") -> void:
	if cond:
		_p += 1
	else:
		_f += 1
		_fails.append(cname)
	print("QA_NG_CHECK %s %s %s" % [cname, "PASS" if cond else "FAIL", note])

func _del_save() -> void:
	var da := DirAccess.open("user://")
	if da != null and da.file_exists("save_morkheim.json"):
		da.remove("save_morkheim.json")

func _spawn_slime(tile: Vector2i):
	var sl = load("res://scripts/slime.gd").new()
	add_child(sl)
	sl.setup(world_node, tile)
	return sl

func _spawn_brute(tile: Vector2i, is_boss: bool, tr: int):
	var br = load("res://scripts/brute.gd").new()
	br.set("boss", is_boss)
	br.set("tier", tr)
	add_child(br)
	br.setup(world_node, tile)
	return br

func _find_node_script(root: Node, path_part: String):
	var s = root.get_script()
	if s != null and String(s.resource_path).contains(path_part):
		return root
	for c in root.get_children():
		var r = _find_node_script(c, path_part)
		if r != null:
			return r
	return null

func _mute_world_reload_hooks() -> void:
	# Драйвер стенда живёт в ПЕРЕЗАГРУЖАЕМОЙ сцене: world.gd в _ready вешает на
	# ng_plus_started лямбда reload_current_scene -> при start_ng_plus сцена
	# пересоздаётся, _ready драйвера стартует заново -> ещё один круг -> петля
	# волн до капа и убийство по таймауту. Секции 4-8 сверяют слой
	# GameState/диска, а не пересборку сцены (пересборку крыть qa_ng2).
	# Глушим ТОЛЬКО world-лямбды: именованный Achv._on_ng_plus (ачивки NG+)
	# и собственный счётчик стенда (object == self) остаются подключены.
	for c in GameState.get_signal_connection_list("ng_plus_started"):
		var cb: Callable = c["callable"]
		if cb.is_valid() and cb.get_object() != self \
				and cb.get_object() != null and cb.get_object().has_method("tile_to_world"):
			GameState.ng_plus_started.disconnect(cb)

func _ready() -> void:
	print("QA_NG_BEGIN")
	_del_save()  # мир в _ready грузит сейв — стартуем с чистого листа

	# --- 1) Формулы — чистые функции GameState (одна точка истины) ---
	var hps := [1.0, 1.5, 2.0, 2.5, 3.0, 3.5]
	var okh := true
	for w in 6:
		if absf(GameState.hp_mult(w) - float(hps[w])) > 0.000001:
			okh = false
	ck("formula_hp_mult", okh, "w0..w5 => x1.0..x3.0")
	ck("formula_hp_mult_cap", absf(GameState.hp_mult(7) - 3.5) < 0.000001, "w7 => 3.5")
	var dms := [0, 1, 1, 2, 2, 3]
	var okd := true
	for w in 6:
		if GameState.dmg_bonus(w) != int(dms[w]):
			okd = false
	ck("formula_dmg_bonus", okd, "w0..w5 => +0..+3")
	var gms := [1.0, 1.4, 1.8, 2.2, 2.6, 3.0]
	var okg := true
	for w in 6:
		if absf(GameState.ng_gold_mult(w) - float(gms[w])) > 0.000001:
			okg = false
	ck("formula_gold_mult", okg, "w0..w5 => x1.0..x3.0")
	ck("ng_wave_default", GameState.ng_wave() == 0)

	# --- 2) Мир w0: базовые цифры мобов не изменились ---
	print("QA_NG_M1_before_load")
	world_node = load("res://scenes/main.tscn").instantiate()
	print("QA_NG_M2_instantiated class=%s" % world_node.get_class())
	add_child(world_node)
	print("QA_NG_M3_added")
	await get_tree().process_frame
	print("QA_NG_M4_frame")
	ck("world_boots", world_node != null and world_node.has_method("tile_to_world"))
	var sl0 = _spawn_slime(Vector2i(4, 4))
	ck("w0_slime", int(sl0.hp) == 3 and int(sl0.dmg) == 1, "hp=%s dmg=%s" % [sl0.hp, sl0.dmg])
	var b1 = _spawn_brute(Vector2i(6, 4), false, 1)
	var b2 = _spawn_brute(Vector2i(7, 4), false, 2)
	var b3 = _spawn_brute(Vector2i(8, 4), false, 3)
	ck("w0_brute_t1", int(b1.hp) == 6 and int(b1.dmg) == 1, "hp=%s" % b1.hp)
	ck("w0_brute_t2", int(b2.hp) == 9 and int(b2.dmg) == 2, "hp=%s" % b2.hp)
	ck("w0_brute_t3", int(b3.hp) == 12 and int(b3.dmg) == 2, "hp=%s" % b3.hp)
	var boss0 = _spawn_brute(Vector2i(30, 30), true, 3)
	ck("w0_boss", int(boss0.hp) == 24 and int(boss0.dmg) == 3, "hp=%s" % boss0.hp)

	# --- 3) Золотой EV на w0 (бензема) — те же 200 роллов с тем же seed ---
	var g0 := GameState.gold
	seed(777)
	for i in 200:
		Loot.on_mob_death("slime", Vector2.ZERO)
	var sum0 := GameState.gold - g0
	ck("ev_w0_sample", sum0 >= 480 and sum0 <= 720, "sum0=%d (EV~595 +first_blood)" % sum0)

	# --- 4) Fixture «пройденный мир» + запуск круга ---
	var sp := {"ng": 0, "q": 0}
	GameState.ng_plus_started.connect(func() -> void: sp["ng"] += 1)
	GameState.quest_changed.connect(func() -> void: sp["q"] += 1)
	GameState.class_id = "warrior"
	GameState.level = 3
	GameState.elder_quest = 2
	GameState.slime_quest = 2
	GameState.cave_state = 4
	GameState.has_key = true
	GameState.door_opened = true
	GameState.chest_mark_used("chest@1,1")
	GameState.campfires_used["cf1"] = true
	GameState.materials["suhotsvet"] = 3
	GameState.brewed_potions = 2
	GameState.gold = 123
	GameState.has_amulet = true
	GameState.equip_item("weapon", "sword")
	GameState.in_cave = true
	GameState.pos_valid = true
	GameState.player_pos = Vector2(500, 600)
	GameState.flags["ach.probe"] = 1
	GameState.flags["meta.ash"] = 7
	GameState.flags["meta.bless"] = 2
	GameState.flags["daily.streak"] = 3
	GameState.flags["ng.boss_0"] = 1
	GameState.flags["merchant_seen"] = true
	GameState.flags["ashen.boss"] = "dead"  # убитая ведьма и взятый сундук зоны-2
	GameState.flags["ashen.chest"] = "taken"
	GameState.flags["ashen.intro_seen"] = 1
	GameState.flags["q.grims"] = 1
	GameState.flags["q.got.potion"] = 1
	GameState.flags["q.last.talk"] = 1
	GameState.save_game()  # фиксируем fixture на диске: «до/после» миры читают его

	# контроль: мир, построенный при ashen.boss="dead", — без Ведьмы
	var w_ctl = load("res://scenes/main.tscn").instantiate()
	add_child(w_ctl)
	await get_tree().process_frame
	ck("ctl_dead_witch_no_node", _find_node_script(w_ctl, "mob_boss2") == null)
	w_ctl.queue_free()
	await get_tree().process_frame

	# секции, дёргающие start_ng_plus: заглушить world-хук перезагрузки сцены
	_mute_world_reload_hooks()
	var w1: int = GameState.start_ng_plus()
	ck("start_returns_1", w1 == 1, "ret=%d" % w1)
	ck("wave_is_1", GameState.ng_wave() == 1)
	# Новый канон (8f8dc78): квест старейшины однократный. Fixture сдал его
	# (elder_quest=2) до NG+, sync по загрузке мира поставил meta.q_elder_done —
	# вайп держит квест закрытым (2). Слайм-квест — по-прежнему per-circle сброс.
	ck("reset_quests", GameState.elder_quest == 2 and GameState.slime_quest == 0)
	ck("elder_done_pinned", int(GameState.flags.get("meta.q_elder_done", 0)) == 1)
	ck("reset_cave", GameState.cave_state == 0 and not GameState.has_key \
		and not GameState.door_opened and not GameState.boss_defeated)
	ck("reset_chests_cf", GameState.chests_used.is_empty() and GameState.campfires_used.is_empty())
	ck("reset_mats_brew", int(GameState.materials["suhotsvet"]) == 0 \
		and int(GameState.materials["zhim"]) == 0 and GameState.brewed_potions == 0)
	ck("reset_qflags", not GameState.flags.has("q.grims") \
		and not GameState.flags.has("q.got.potion") and not GameState.flags.has("q.last.talk"))
	ck("reset_ashen_flags", not GameState.flags.has("ashen.boss") \
		and not GameState.flags.has("ashen.chest") and not GameState.flags.has("ashen.intro_seen"))
	# NG+ ачивки (cad57bb): внутри круга _check_ng анлокает ng_second (+1 Пепло) —
	# meta.ash двигается, ach.ng_* появляются. «Живёт» = не потерялось, новые
	# ach.* допускаются. 9402ee1: ng.boss_* намеренно СТИРАются (пепел босса
	# перезарабатывается каждый круг) — проверятся отдельным reset-чеком ниже.
	var ash_after := int(GameState.flags.get("meta.ash", 0))
	ck("keep_meta_ach_daily_ng", ash_after >= 7 \
		and int(GameState.flags.get("meta.bless", 0)) == 2 \
		and int(GameState.flags.get("ach.probe", 0)) == 1 \
		and int(GameState.flags.get("daily.streak", 0)) == 3 \
		and bool(GameState.flags.get("ach.ng_second", false)), \
		"meta.ash=%d ng_second=%s" % [ash_after, str(GameState.flags.get("ach.ng_second", false))])
	ck("reset_ng_boss_gates_p0", not GameState.flags.has("ng.boss_0"), "P0 9402ee1")
	ck("keep_plain_flag", bool(GameState.flags.get("merchant_seen", false)))
	ck("keep_gold_gear_amulet_level", GameState.gold == 123 \
		and String(GameState.gear["weapon"]) == "sword" and GameState.has_amulet \
		and GameState.level == 3)
	ck("world_entry_reset", not GameState.in_cave and not GameState.pos_valid)
	ck("sig_ng_started_once", int(sp["ng"]) == 1, "count=%d" % int(sp["ng"]))
	ck("sig_quest_changed", int(sp["q"]) >= 1, "count=%d" % int(sp["q"]))
	ck("mats_struct_after_reset", GameState.add_material("suhotsvet"))

	# автосейв на диске: волна и перенесённое золото записаны
	var disk: Variant = null
	var f := FileAccess.open(SAVE, FileAccess.READ)
	if f != null:
		disk = JSON.parse_string(f.get_as_text())
	var okd2 := false
	if typeof(disk) == TYPE_DICTIONARY:
		var dfl: Variant = disk.get("flags", {})
		okd2 = typeof(dfl) == TYPE_DICTIONARY and int(dfl.get("ng.wave", -1)) == 1 \
			and int(disk.get("gold", -1)) == 123
	ck("autosave_on_disk_w1", okd2)

	# --- 5) Спавны на w1: скейл по формулам ---
	var sl1 = _spawn_slime(Vector2i(9, 4))
	ck("w1_slime", int(sl1.hp) == 5 and int(sl1.dmg) == 2, \
		"hp=%s dmg=%s (round(3*1.5)=5)" % [sl1.hp, sl1.dmg])
	var sb1 = _spawn_brute(Vector2i(10, 4), false, 1)
	var sb2 = _spawn_brute(Vector2i(11, 4), false, 2)
	var sb3 = _spawn_brute(Vector2i(12, 4), false, 3)
	var boss1 = _spawn_brute(Vector2i(31, 30), true, 3)
	ck("w1_brute_t1", int(sb1.hp) == 9 and int(sb1.dmg) == 2, "hp=%s (6*1.5=9)" % sb1.hp)
	ck("w1_brute_t2", int(sb2.hp) == 14 and int(sb2.dmg) == 3, "hp=%s (9*1.5=13.5->14)" % sb2.hp)
	ck("w1_brute_t3", int(sb3.hp) == 18 and int(sb3.dmg) == 3, "hp=%s" % sb3.hp)
	ck("w1_boss", int(boss1.hp) == 36 and int(boss1.dmg) == 4, "hp=%s" % boss1.hp)

	# reset стёр ashen.boss => мир перестраивается с ЖИВОЙ ведьмой, и её
	# цифры не тронуты скейлом (канон-решение оркестратора: boss2 вне круга)
	var w_live = load("res://scenes/main.tscn").instantiate()
	add_child(w_live)
	await get_tree().process_frame
	var witch_live = _find_node_script(w_live, "mob_boss2")
	ck("witch_respawns_after_reset", witch_live != null)
	if witch_live != null:
		ck("w1_witch_unscaled", int(witch_live.hp) == 48 and int(witch_live.dmg) == 3, \
			"hp=%s dmg=%s" % [witch_live.hp, witch_live.dmg])
	else:
		ck("w1_witch_unscaled", false, "witch missing")
	w_live.queue_free()
	await get_tree().process_frame

	# --- 6) Золотой EV на w1: те же роллы => ×1.4 (с точностью округления) ---
	var g1 := GameState.gold
	seed(777)
	for i in 200:
		Loot.on_mob_death("slime", Vector2.ZERO)
	var sum1 := GameState.gold - g1
	var ratio := float(sum1) / float(maxi(1, sum0))
	ck("ev_w1_sample", sum1 >= 650 and sum1 <= 1020, "sum1=%d (EV~833)" % sum1)
	ck("ev_gold_ratio_x14", absf(ratio - 1.4) <= 0.21, "ratio=%.3f" % ratio)

	# --- 7) Кап волны: догоняем до 5, лишние вызовы не плодят w6, сброс идёт ---
	_mute_world_reload_hooks()  # страховка: w_live в секции 5 коннектил свой хук до free
	for i in 4:
		GameState.start_ng_plus()
	ck("wave_caps_5", GameState.ng_wave() == 5, "wave=%d" % GameState.ng_wave())
	GameState.chest_mark_used("cx")
	GameState.campfires_used["c2"] = true
	GameState.materials["zhim"] = 2
	var rc: int = GameState.start_ng_plus()
	ck("cap_no_w6", rc == 5 and GameState.ng_wave() == 5, "ret=%d" % rc)
	ck("cap_still_resets", GameState.chests_used.is_empty() \
		and GameState.campfires_used.is_empty() and int(GameState.materials["zhim"]) == 0)
	ck("cap_keep_meta", int(GameState.flags.get("meta.ash", 0)) >= 7)

	# --- 8) Персистентность: волна доживает до перезагрузки ---
	# (gold на диске = 123 + EV-прибавка w1-прогона, сверяем со снапшотом)
	var gcap := GameState.gold
	GameState.in_cave = true  # доказываем, что load реально перезаписал память
	var okl: bool = GameState.load_game()
	ck("reload_wave5", okl and GameState.ng_wave() == 5 and GameState.gold == gcap \
		and not GameState.in_cave, "gold=%d snap=%d" % [GameState.gold, gcap])

	# --- 9) Старый сейв без ng.* грузится и живёт на w0 ---
	var fw := FileAccess.open(SAVE, FileAccess.WRITE)
	fw.store_string('{"max_hp":10,"hp":8,"level":1,"xp":5,"gold":50,"has_sword":true,' \
		+ '"elder_quest":2,"cave_state":1}')
	fw.close()
	var okold: bool = GameState.load_game()
	ck("old_save_loads", okold and GameState.ng_wave() == 0 and GameState.gold == 50 \
		and GameState.elder_quest == 2)
	var sl_old = _spawn_slime(Vector2i(13, 4))
	ck("old_save_w0_slime", int(sl_old.hp) == 3 and int(sl_old.dmg) == 1)

	_del_save()
	print("QA_NG_RESULT %d/%d fails=%s" % [_p, _p + _f, str(_fails)])
	get_tree().quit(0 if _f == 0 else 1)
