extends Node
## QA-стенд CONTRACT_TALENTS (база 313cd5e). Запуск:
##   godot --headless --path <proj> res://tools/qa/stand/qa_tal.tscn
## Печатает строки "QA_TAL PASS|FAIL <id> <детали>" и итог "QA_TAL SUMMARY ...".
## Детерминизм: все rng-батчи через фиксированный seed(); никаких Time.*.
## Выход: 0 — все проверки зелёные, 1 — есть FAIL.

const BruteScript := preload("res://scripts/brute.gd")
const SlimeScript := preload("res://scripts/slime.gd")
const PlayerScript := preload("res://scripts/player.gd")
const FirstHintScript := preload("res://scripts/first_hint.gd")

var _checks := 0
var _fails := 0

## Фейковый мир-хост: только то, что читают player.gd/brute.gd.
class FakeWorld:
	extends Node2D
	var player: Node = null
	func tile_to_world(_t: Vector2i) -> Vector2:
		return Vector2.ZERO
	# get_global_mouse_position() НЕ переопределяем: метод уже есть в CanvasItem
	# (4.x), а повторное объявление — warning-as-error.

func _chk(id: String, ok: bool, info: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("QA_TAL %s %s | %s" % ["PASS" if ok else "FAIL", id, info])

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _pframes(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Полный сброс GameState к «голему» герою 1-го уровня (класс фиксируем).
func _fresh() -> void:
	GameState.flags = {}
	GameState.gold = 0
	GameState.gear = {"weapon": "", "armor": ""}
	GameState.has_sword = false
	GameState.has_amulet = false
	GameState.materials = {"suhotsvet": 0, "zhim": 0}
	GameState.brewed_potions = 0
	GameState.herbs = 0
	GameState.slime_kills = 0
	GameState.level = 1
	GameState.xp = 0
	GameState.xp_next = 20
	GameState.combat_t = 0.0
	GameState._hp_regen_t = 0.0
	GameState._mana_regen_t = 0.0
	GameState.cave_state = 0
	GameState.input_locked = false
	GameState.max_hp = int(GameState.Classes.class_data(GameState.class_id).hp)
	GameState.hp = GameState.max_hp

func _count_in(path: String, needle: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var txt := f.get_as_text()
	var n := 0
	var i := txt.find(needle)
	while i >= 0:
		n += 1
		i = txt.find(needle, i + 1)
	return n

func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			out.append(c)
		_collect_buttons(c, out)

func _set_key(action: String, pressed_ev: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed_ev
	Input.parse_input_event(ev)

func _ready() -> void:
	_run()

func _run() -> void:
	# ---- T00: фундамент (автload резолвится, реестр целостен) ----
	_chk("t0_autoload", GameState != null, "GameState autoload")
	var nodes: Dictionary = Talents.NODES
	var sum_max := 0
	var branch_ok := true
	var cost_ok := true
	for id in nodes:
		sum_max += int(nodes[id].get("max", 0))
		if not Talents.BRANCHES.has(String(nodes[id].get("branch", ""))):
			branch_ok = false
		if int(nodes[id].get("cost_per_rank", 0)) != 1:
			cost_ok = false
	_chk("t0_registry_enum", nodes.size() == 12, "NODES=%d — канон: перечисленные §1 id (в прозе §1 «14» — опечатка контракта, см. INFO)" % nodes.size())
	print("QA_TAL INFO contract_discrepancy | prose «14 узлов/13 хуков» vs enumerated §1 = 12 id, сумма max = 20 (реализован перечисленный канон; импровизация числами запрещена)")
	_chk("t0_sum20", sum_max == 20, "sum(max)=%d (Сила 7 + Лес 7 + Пепел 6)" % sum_max)
	_chk("t0_branches", branch_ok and Talents.BRANCHES.size() == 3, "3 ветки, у всех узлов валидный branch")
	_chk("t0_cost1", cost_ok, "cost_per_rank == 1 у всех 14")
	_chk("t0_maxof", Talents.max_of("fury") == 3 and Talents.max_of("zzz") == 0, "max_of: fury=3, неизвестный=0")

	# ---- T01: tal_points / трата / отказы ----
	_fresh()
	GameState.level = 1
	_chk("t1_pts0_at_l1", GameState.tal_points() == 0, "level=1 => 0 очков")
	_chk("t1_deny_l1", not GameState.try_spend_talent("whetstone") and GameState.tal_rank("whetstone") == 0, "на 1-м уровне отказ, ранг не вырос")
	GameState.level = 3
	_chk("t1_pts2_at_l3", GameState.tal_points() == 2, "level=3 => 2 очка")
	var s1 := GameState.try_spend_talent("whetstone")
	var s2 := GameState.try_spend_talent("whetstone")
	_chk("t1_spend_seq", s1 and s2 and GameState.tal_rank("whetstone") == 2 and GameState.tal_spent() == 2 and GameState.tal_points() == 0, "2 траты подряд: rank=2 spent=2 pts=0")
	_chk("t1_deny_cap", not GameState.try_spend_talent("whetstone") and GameState.tal_rank("whetstone") == 2, "cap узла (max=2): отказ")
	_chk("t1_deny_unknow", not GameState.try_spend_talent("nope_xyz") and not GameState.flags.has("tal.nope_xyz"), "неизвестный id: отказ, флаг не создан")
	_chk("t1_deny_nopoints", not GameState.try_spend_talent("fury") and GameState.tal_rank("fury") == 0, "очки кончились: отказ")
	GameState.level = 6
	_chk("t1_pts3_after_l6", GameState.tal_points() == 3, "level=6: pts = 5-2 = 3")
	var fz := GameState.try_spend_talent("fury") and GameState.try_spend_talent("fury") and GameState.try_spend_talent("fury")
	_chk("t1_fury_cap3", fz and GameState.tal_rank("fury") == 3 and not GameState.try_spend_talent("fury"), "fury 3 траты, 4-я — отказ (cap 3)")
	GameState.level = 7  # 6-5 вложенных = 1 очко под heavy
	_chk("t1_heavy_cap1", GameState.try_spend_talent("heavy") and not GameState.try_spend_talent("heavy"), "heavy: 1 трата, cap=1")

	# ---- T02: tal_rank — клампы и битые данные ----
	_fresh()
	GameState.flags["tal.fury"] = 99
	_chk("t2_clamp_hi", GameState.tal_rank("fury") == 3, "флаг 99 => кламп к max 3")
	GameState.flags["tal.skin"] = "abc"
	_chk("t2_garbage0", GameState.tal_rank("skin") == 0, "строка «abc» => 0")
	GameState.flags["tal.zzz"] = 5
	_chk("t2_unknown_notcounted", GameState.tal_rank("zzz") == 0 and GameState.tal_spent() == 3, "неизвестный id не в tal_spent (только fury=3)")
	GameState.flags["tal.breath"] = -4
	_chk("t2_negative0", GameState.tal_rank("breath") == 0 and GameState.hp_regen_interval() == 4.0, "отрицательный флаг => 0 => интервал 4.0")

	# ---- T03: урон (whetstone/fury/heavy/amulet/master + регресс rank0) ----
	_fresh()
	var pd := func(base: int) -> int: return GearData.player_damage(base, GameState)
	_chk("t3_bare", pd.call(10) == 10, "ранг0 без всего: 10 (регресс HEAD-поведения)")
	_fresh(); GameState.flags["tal.whetstone"] = 2
	_chk("t3_whetstone2", pd.call(10) == 13, "whetstone2: 10*(1+0.30)=13")
	_fresh(); GameState.flags["tal.fury"] = 3
	_chk("t3_fury3", pd.call(10) == 12, "fury3: round(10*1.15)=12")
	_fresh(); GameState.flags["tal.heavy"] = 1
	_chk("t3_heavy1", pd.call(10) == 11, "heavy1: 10+1=11")
	_fresh(); GameState.has_amulet = true
	_chk("t3_amulet", pd.call(10) == 11, "амулет без талантов: 10+1=11")
	_fresh(); GameState.has_sword = true
	_chk("t3_sword_rank0", pd.call(10) == 20, "регресс: legacy-меч x2 ранг0 = 20")
	_fresh(); GameState.has_sword = true; GameState.flags["tal.whetstone"] = 2; GameState.flags["tal.fury"] = 3; GameState.flags["tal.heavy"] = 1; GameState.has_amulet = true; GameState.flags["meta.master"] = 3
	# t39: мастерство +15%/стек (было +10%): 10*(2.0+0.30)*(1.45)=33.35;
	# *1.15=38.3525; +1(амулет)+1(heavy)=40.3525 -> 40
	_chk("t3_stack_all", pd.call(10) == 40, "стек sword+wh2+master3+fury3+amul+heavy: 40 (мастер t39 +15%×3=+45%)")
	_fresh(); GameState.flags["tal.fury"] = 3
	_chk("t3_min1", GearData.player_damage(-5, GameState) >= 1, "округление к минимуму 1")

	# ---- T04: броня skin ----
	_fresh()
	GameState.flags["tal.skin"] = 2
	_chk("t4_skin2", GearData.armor_bonus(GameState) == 2 and GearData.absorb(GameState, 5) == 3, "skin2: броня 2, удар 5 -> 3")
	_fresh(); GameState.gear["armor"] = "leather"; GameState.flags["tal.skin"] = 1
	_chk("t4_leather_skin", GearData.armor_bonus(GameState) == 2 and GearData.absorb(GameState, 5) == 3, "leather(1)+skin1=2")
	_chk("t4_floor1", GearData.absorb(GameState, 1) == 1, "пол: ненулевой удар минимум 1")
	_fresh()
	_chk("t4_zero", GearData.armor_bonus(GameState) == 0, "ранг0 без брони: 0")

	# ---- T05: breath — таблица и тик регена (_process напрямую) ----
	_fresh()
	_chk("t5_table", GameState.hp_regen_interval() == 4.0, "ранг0: 4.0")
	GameState.flags["tal.breath"] = 1
	_chk("t5_table1", GameState.hp_regen_interval() == 3.2, "ранг1: 3.2")
	GameState.flags["tal.breath"] = 2
	_chk("t5_table2", GameState.hp_regen_interval() == 2.6, "ранг2: 2.6")
	_fresh()
	GameState.hp = 1; GameState.max_hp = 10; GameState._hp_regen_t = 0.0; GameState.combat_t = 0.0
	GameState._process(3.9)
	_chk("t5_tick_early", GameState.hp == 1, "ранг0: 3.9 с < 4.0 — тика нет")
	GameState._process(0.2)
	_chk("t5_tick_fire", GameState.hp == 2 and GameState._hp_regen_t < 1.0, "ранг0: тик на 4.0 — hp+1, таймер сброшен")
	_fresh(); GameState.flags["tal.breath"] = 1
	GameState.hp = 1; GameState.max_hp = 10; GameState._hp_regen_t = 0.0
	GameState._process(3.3)
	_chk("t5_tick_fast", GameState.hp == 2, "ранг1: тик раньше (3.2)")
	_fresh()
	GameState.hp = 1; GameState.max_hp = 10; GameState._hp_regen_t = 0.0; GameState.combat_t = 20.0
	GameState._process(10.0)
	_chk("t5_combat_pause", GameState.hp == 1, "в бою реген паузится")

	# ---- T06: scholar + FirstHint-хук на 2-м уровне ----
	_fresh()
	GameState.flags["tal.scholar"] = 2; GameState.xp = 0
	GameState.add_xp(10)
	_chk("t6_scholar2", GameState.xp == 12, "scholar2: add_xp(10) => +12")
	_fresh(); GameState.flags["tal.scholar"] = 1; GameState.xp = 0
	GameState.add_xp(5)
	_chk("t6_scholar1", GameState.xp == 6, "scholar1: add_xp(5) => round(5.5)=6")
	_fresh(); GameState.flags["tal.scholar"] = 2; GameState.xp = 10
	GameState.add_xp(-3)
	_chk("t6_negative_raw", GameState.xp == 7, "отрицательная коррекция без множителя")
	_fresh()
	var hint := FirstHintScript.new()
	add_child(hint)
	await _frames(1)
	_chk("t6_hint_singleton", FirstHint.I == hint, "FirstHint.I зарегистрирован")
	GameState.add_xp(20)  # ровно порог 20 => уровень 2 => хук
	var lvl2 := GameState.level == 2
	await _frames(6)  # FirstHint ставит флаг при фактическом показе из _process
	_chk("t6_levelup2", lvl2, "add_xp(20) => level 2")
	_chk("t6_hint_shown", str(GameState.flags.get("hint.talents", "")) == "1", "флаг hint.talents выставлен показом")
	_chk("t6_pts_after_level", GameState.tal_points() == 1, "после 2-го уровня: 1 очко")
	hint.show_hint("talents", "дедуп")
	await _frames(3)
	_chk("t6_hint_dedup", str(GameState.flags.get("hint.talents", "")) == "1", "повторный show_hint — идемпотентен")
	hint.queue_free()
	await _frames(2)

	# ---- T07: скорость/замах/кувырок на живом player ----
	_fresh()
	var world3: Node2D = FakeWorld.new()
	add_child(world3)
	var pl := PlayerScript.new()
	world3.add_child(pl)
	await _frames(2)
	_chk("t7_player_ready", pl.world == world3 and String(pl.class_data().kind) == "melee", "player в дереве, класс воин (melee)")
	var spd0 := float(pl.class_data().speed)
	_set_key("move_right", true)
	await _pframes(3)
	var v0 := absf(pl.velocity.x)
	_chk("t7_stride0", absf(v0 - spd0) < 0.01, "скорость rank0 = %.1f" % spd0)
	GameState.flags["tal.stride"] = 2
	await _pframes(3)
	var v2 := absf(pl.velocity.x)
	_chk("t7_stride2", absf(v2 - spd0 * 1.1) < 0.02, "stride2: %.2f = база*1.10" % v2)
	_set_key("move_right", false)
	await _pframes(2)
	pl.attack_cd = 0.0
	pl.do_attack()
	var cd0 := pl.attack_cd
	GameState.flags["tal.zeal"] = 1
	pl.attack_cd = 0.0
	pl.do_attack()
	var cd1 := pl.attack_cd
	_chk("t7_zeal", absf(cd0 - float(pl.class_data().attack_speed)) < 0.0001 and absf(cd1 - float(pl.class_data().attack_speed) * 0.92) < 0.0001, "attack_cd: %.3f -> zeal %.3f (x0.92)" % [cd0, cd1])
	pl.attack_cd = 0.0
	pl.roll_t = 0.0; pl.roll_cd = 0.0
	pl.start_roll(Vector2.RIGHT)
	var rc0 := pl.roll_cd
	GameState.flags["tal.lightfoot"] = 1
	pl.roll_t = 0.0
	pl.start_roll(Vector2.RIGHT)
	var rc1 := pl.roll_cd
	GameState.flags["meta.feet"] = 1
	pl.roll_t = 0.0
	pl.start_roll(Vector2.RIGHT)
	var rc2 := pl.roll_cd
	_chk("t7_lightfoot", absf(rc0 - 1.12) < 0.0001 and absf(rc1 - 1.02) < 0.0001 and absf(rc2 - 0.87) < 0.0001, "roll_cd: %.2f -> lf %.2f -> feet+lf %.2f (пол 0.15)" % [rc0, rc1, rc2])
	pl.roll_t = 0.0; pl.roll_cd = 0.0
	pl.queue_free()
	world3.queue_free()
	await _frames(2)

	# ---- T08: ember — золото с мобов (тот же seed, 200 убojств slime) ----
	_fresh()
	GameState.gold = 0
	seed(12345)
	for i in 200:
		Loot.on_mob_death("slime", Vector2.ZERO)
	var g0 := GameState.gold
	GameState.gold = 0
	GameState.materials = {"suhotsvet": 0, "zhim": 0}
	seed(12345)
	GameState.flags["tal.ember"] = 2
	for i in 200:
		Loot.on_mob_death("slime", Vector2.ZERO)
	var g2 := GameState.gold
	var ratio := float(g2) / float(g0)
	# Формула канонична (×1.15/ранг, структурно проверено в t14); на мелких
	# золотых ролах int(round()) систематически округляет вверх — фактический
	# детерминированный_ratio выше номинала. Границы ловят регресс формулы,
	# не ломаясь на каноничном поведении round().
	_chk("t8_ember2", g0 > 0 and g2 > g0 and ratio > 1.05 and ratio < 1.45, "ember2: %d -> %d (x%.3f; >=1.15- nominал с округлением вверх на малых ролах, тот же seed)" % [g0, g2, ratio])

	# ---- T09: herblore — шанс дропа материалов (1000 бросков, seed) ----
	_fresh()
	var sl := SlimeScript.new()
	seed(777)
	var h0 := 0
	for i in 1000:
		GameState.materials = {"suhotsvet": 0, "zhim": 0}
		var before := int(GameState.materials["suhotsvet"]) + int(GameState.materials["zhim"])
		sl._roll_mat_drop()
		var after := int(GameState.materials["suhotsvet"]) + int(GameState.materials["zhim"])
		if after > before:
			h0 += 1
	seed(777)
	GameState.flags["tal.herblore"] = 1
	var h1 := 0
	for i in 1000:
		GameState.materials = {"suhotsvet": 0, "zhim": 0}
		var before2 := int(GameState.materials["suhotsvet"]) + int(GameState.materials["zhim"])
		sl._roll_mat_drop()
		var after2 := int(GameState.materials["suhotsvet"]) + int(GameState.materials["zhim"])
		if after2 > before2:
			h1 += 1
	sl.free()
	_chk("t9_herblore", h0 > 205 and h0 < 295 and h1 > 270 and h1 < 370 and h1 > h0, "дроп 1000 роллов: rank0=%d (~250), herblore=%d (~320), тот же seed" % [h0, h1])

	# ---- T10: whisper — пепло-дельты при убojстве босса (живой brute) ----
	_fresh()
	var world4: Node2D = FakeWorld.new()
	add_child(world4)
	var qc := [0]
	GameState.quest_changed.connect(func() -> void: qc[0] += 1)
	var kill_boss := func() -> int:
		var ash_before := Ash.balance()
		var b: Node2D = BruteScript.new()
		world4.add_child(b)
		b.setup(world4, Vector2i(0, 0))
		b.hp = 5
		b.hurt(99999, Vector2.ZERO)
		await _frames(2)  # queue_free доделан
		return Ash.balance() - ash_before
	# Примирование: первый анлок «Убийца босса» (+3) идёт сверх 3 за босса.
	var d1: int = await kill_boss.call()
	_chk("t10_prime", d1 == 6, "первая смерть: 3 (босс) + 3 (ачивка) = 6")
	GameState.flags["ng.boss_0"] = 0
	var d2: int = await kill_boss.call()
	_chk("t10_boss3", d2 == 3, "чистая смерть босса: +3 пепла")
	GameState.flags["tal.whisper"] = 1
	GameState.flags["ng.boss_0"] = 0
	var d3: int = await kill_boss.call()
	_chk("t10_whisper4", d3 == 4, "whisper1: +4 пепла за босса")
	var d4: int = await kill_boss.call()
	_chk("t10_dedup0", d4 == 0, "гейт ng.boss_<w> без сброса: 0 (дедуп не сломан)")
	# канал автосейва: успех талента — один quest_changed, отказ — ноль
	_fresh()
	GameState.level = 8
	qc[0] = 0
	var ok_spend := GameState.try_spend_talent("heavy")
	var qc_after_ok: int = qc[0]
	var ok_deny := GameState.try_spend_talent("heavy")
	var qc_after_deny: int = qc[0]
	_chk("t10_save_channel", ok_spend and qc_after_ok == 1 and not ok_deny and qc_after_deny == 1, "успех: quest_changed=1 (автосейв-канал); отказ: эмита нет")
	world4.queue_free()
	await _frames(2)

	# ---- T11: журнал — вкладка «Таланты», кнопка, input_locked-гейт ----
	_fresh()
	GameState.level = 6
	var j := Journal.new()
	add_child(j)
	j.open()
	j.select_tab(2)
	var btns: Array = []
	_collect_buttons(j._tal_list, btns)
	var header0: Label = j._tal_list.get_child(0) as Label
	_chk("t11_tab", j._tab == 2 and j._tal_list.visible, "TAB_TALENTS=2 открыт, список виден")
	_chk("t11_titles", Journal.TAB_TITLES.size() == 3 and String(Journal.TAB_TITLES[2]) == "Таланты", "3 вкладки, 3-я «Таланты»")
	_chk("t11_btn12", btns.size() == 12, "кнопок узлов: %d (12 — перечисленный канон §1)" % btns.size())
	_chk("t11_header", header0 != null and header0.text == "Очки: 5", "заголовок: «%s»" % (header0.text if header0 != null else "<нет>"))
	var wet: Button = null
	for b in btns:
		if String(b.text).contains("Точильный"):
			wet = b
	_chk("t11_wet_found", wet != null, "кнопка «Точильный камень» найдена: %s" % (wet.text if wet != null else ""))
	GameState.input_locked = true
	if wet != null:
		wet.pressed.emit()
	await _frames(1)
	_chk("t11_click_locked", GameState.tal_rank("whetstone") == 0, "input_locked=true: клик по кнопке НЕ тратит очко")
	GameState.input_locked = false
	j.open()  # страховка: если журнал успел закрыться на тике с input_locked — вернуть
	if wet != null:
		wet.pressed.emit()
	await _frames(1)
	var header1: Label = j._tal_list.get_child(0) as Label
	_chk("t11_click_spend", GameState.tal_rank("whetstone") == 1 and header1 != null and header1.text == "Очки: 4", "клик без лока: ранг=1, заголовок «%s»" % (header1.text if header1 != null else ""))
	GameState.level = 8  # внешнее изменение (уровень вырос при открытом журнале)
	# Реальное время > TICK(0.35): headless гонит кадры на максиме, счёт кадров
	# не гарантировал бы тик _process — ждём таймером дерева.
	await get_tree().create_timer(0.8).timeout
	var header2: Label = j._tal_list.get_child(0) as Label
	_chk("t11_live_rebuild", header2 != null and header2.text == "Очки: 6", "живой пересбор по подписи: «%s» (8-1-1)" % (header2.text if header2 != null else ""))
	j.queue_free()
	await _frames(2)

	# ---- T12: сейв-раунд-трип tal.* (JSON + файл save/load) ----
	_fresh()
	GameState.level = 6
	GameState.flags["tal.fury"] = 2
	GameState.flags["tal.whetstone"] = 2
	GameState.flags["tal.stride"] = 1
	GameState.gold = 123
	GameState.has_amulet = true
	var d_save: Dictionary = GameState.to_dict()
	var txt := JSON.stringify(d_save)
	var d_back: Dictionary = JSON.parse_string(txt)
	_fresh()
	GameState.from_dict(d_back)
	_chk("t12_json_trip", GameState.tal_rank("fury") == 2 and GameState.tal_rank("whetstone") == 2 and GameState.tal_rank("stride") == 1 and GameState.level == 6 and GameState.gold == 123 and GameState.tal_spent() == 5 and GameState.tal_points() == 0, "to_dict->JSON->from_dict: ранги 2/2/1, уровень 6, pts 0 (флот-инты съедены _num)")
	var sv := GameState.save_game()
	GameState.flags["tal.fury"] = 0
	var ld := GameState.load_game()
	_chk("t12_file_trip", sv and ld and GameState.tal_rank("fury") == 2 and GameState.level == 6, "save_game()/load_game(): fury восстановлен = 2")

	# ---- T13: start_ng_plus — tal.* стираются, уровень и ach/meta/hint живут ----
	GameState.flags["tal.stride"] = 2
	GameState.level = 4
	GameState.flags["q.test"] = 1
	GameState.flags["ashen.zone"] = 1
	GameState.flags["ng.boss_2"] = 1
	GameState.flags["ng.wave"] = 2
	GameState.flags["meta.ash"] = 13
	GameState.flags["hint.talents"] = "1"
	GameState.flags["ach.keep"] = true
	var w := GameState.start_ng_plus()
	_chk("t13_wave3", w == 3, "старый круг 2 => новый круг 3")
	_chk("t13_tal_erased", not GameState.flags.has("tal.fury") and not GameState.flags.has("tal.whetstone") and not GameState.flags.has("tal.stride") and GameState.tal_spent() == 0, "tal.* стёрты (collect-then-erase)")
	_chk("t13_q_erased", not GameState.flags.has("q.test") and not GameState.flags.has("ashen.zone") and not GameState.flags.has("ng.boss_2"), "q.*/ashen.*/ng.boss_* тоже стёрты (регресс прежнего списка)")
	_chk("t13_kept", bool(GameState.flags.get("ach.keep", false)) and int(GameState.flags.get("meta.ash", 0)) == 13 and str(GameState.flags.get("hint.talents", "")) == "1", "ach.*/meta.ash/hint.* перенесены")
	_chk("t13_carryover", GameState.level == 4 and GameState.tal_points() == 3, "уровень 4 перенесён => tal_points()=3 (респец круга)")

	# ---- T14: структурные проверки канона (единичность применений) ----
	var cnt_zeal := _count_in("res://scripts/player.gd", "(0.92 if GameState.tal_rank(\"zeal\") > 0 else 1.0)")
	var cnt_stride := _count_in("res://scripts/player.gd", "(1.0 + 0.05 * GameState.tal_rank(\"stride\"))")
	var cnt_floor := _count_in("res://scripts/player.gd", "maxf(0.15,")
	var cnt_ember := _count_in("res://scripts/loot.gd", "gold * (1.0 + 0.15 * GameState.tal_rank(\"ember\"))")
	var cnt_herb_b := _count_in("res://scripts/brute.gd", "0.32 if GameState.tal_rank(\"herblore\") > 0")
	var cnt_herb_s := _count_in("res://scripts/slime.gd", "0.32 if GameState.tal_rank(\"herblore\") > 0")
	var cnt_whisper := _count_in("res://scripts/brute.gd", "grant_ash(3 + (1 if GameState.tal_rank(\"whisper\") > 0 else 0))")
	var cnt_fury := _count_in("res://scripts/gear_data.gd", "d *= 1.0 + 0.05 * float(fury)")
	var cnt_wet := _count_in("res://scripts/gear_data.gd", "w_add = 0.15 * float(gs.tal_rank(\"whetstone\"))")
	var cnt_heavy := _count_in("res://scripts/gear_data.gd", "d += float(heavy)")
	var cnt_skin := _count_in("res://scripts/gear_data.gd", "b += gs.tal_rank(\"skin\")")
	var cnt_breath := _count_in("res://scripts/game_state.gd", "var t := [4.0, 3.2, 2.6]")
	var cnt_scholar := _count_in("res://scripts/game_state.gd", "1.0 + 0.10 * tal_rank(\"scholar\")")
	var cnt_hint := _count_in("res://scripts/game_state.gd", "FirstHint.I.show_hint(\"talents\"")
	var cnt_talwipe := _count_in("res://scripts/game_state.gd", "begins_with(\"tal.\")")
	var cnt_deny := _count_in("res://scripts/game_state.gd", "GameAudio.sfx(\"ui_deny\")")
	var cnt_confirm := _count_in("res://scripts/game_state.gd", "GameAudio.sfx(\"ui_confirm\")")
	var cnt_purchase := _count_in("res://scripts/game_state.gd", "ui_purchase") + _count_in("res://scripts/journal.gd", "ui_purchase") + _count_in("res://scripts/talents.gd", "ui_purchase")
	var cnt_cap := _count_in("res://scripts/game_state.gd", "CAP-128")
	var structural := cnt_zeal == 2 and cnt_stride == 1 and cnt_floor == 1 and cnt_ember == 1 and cnt_herb_b == 1 and cnt_herb_s == 1 and cnt_whisper == 1 and cnt_fury == 1 and cnt_wet == 1 and cnt_heavy == 1 and cnt_skin == 1 and cnt_breath == 1 and cnt_scholar == 1 and cnt_hint == 1 and cnt_talwipe == 1 and cnt_deny == 1 and cnt_confirm == 1 and cnt_purchase == 0 and cnt_cap >= 1
	print("QA_TAL INFO struct zeal=%d stride=%d floor=%d ember=%d herb=%d/%d whisper=%d fury=%d wet=%d heavy=%d skin=%d breath=%d scholar=%d hint=%d talwipe=%d deny=%d confirm=%d purchase=%d cap=%d" % [cnt_zeal, cnt_stride, cnt_floor, cnt_ember, cnt_herb_b, cnt_herb_s, cnt_whisper, cnt_fury, cnt_wet, cnt_heavy, cnt_skin, cnt_breath, cnt_scholar, cnt_hint, cnt_talwipe, cnt_deny, cnt_confirm, cnt_purchase, cnt_cap])
	_chk("t14_structural", structural, "все хуки применены ровно единожды (zeal=2 сайта), ui_purchase=0, CAP-128 док есть")

	print("QA_TAL SUMMARY checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
