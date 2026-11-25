extends Node
## QA-Q5: стенд проверки волновых правок квестового ядра (база HEAD 0c9dfe0).
## Проверяет ПОВЕДЕНИЕ ПОСЛЕ правок sand_q5.diff + хунков game_state.gd
## (slime_kills_circle / purse / herbs — применяются оркестратором в main).
## Симулирует канонические колбэки: world.gd::talk(), slime.gd::_die(),
## interactable.gd::chest, CaveChest/AshenChest, campfire.gd::_finish(),
## mob_boss2.gd::смерть, QuestsData.refresh() тиком журнала.
## Ожидание поставки: fails=0, holes=0, quit(0). Запускать ДВАЖЫ — вывод детерминирован.

var fails := 0
# Дыры аудита 0c9dfe0 (H1..H7 + D4): в секции F перенесены ДОСЛОВНЫЕ пробы
# old-стенда qa_audit.gd — на фикшенном дереве каждая обязана дать
# «не воспроизвелось»; любая регрессия поднимает holes и уводит quit(1).
var holes := 0
var toasts: Array = []
var gs: Node

func _ready() -> void:
	gs = GameState
	gs.toast.connect(func(t: String) -> void: toasts.append(t))
	print("=== QA Q5 START ===")
	sim_circle1()
	sim_side_badges()
	sim_ng_plus()
	sim_achv_gates()
	sim_belt_chain()
	sim_old_holes()
	sim_supply_info()
	print("=== QA Q5 DONE: fails=%d holes=%d ===" % [fails, holes])
	get_tree().quit(0 if fails + holes == 0 else 1)

func ck(what: String, cond: bool, info := "") -> void:
	if cond:
		print("PASS | %s" % what)
	else:
		fails += 1
		print("FAIL | %s | %s" % [what, info])

func inf(tag: String, msg: String) -> void:
	print("INFO | %s | %s" % [tag, msg])

func hole(what: String, broken: bool, info := "") -> void:
	if broken:
		holes += 1
		print("HOLE | %s | %s" % [what, info])
	else:
		print("PASS | %s (не воспроизвелось)" % what)

func file_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func file_has(path: String, frag: String) -> bool:
	return file_src(path).contains(frag)

func ntok() -> int:
	var n := toasts.size()
	toasts.clear()
	return n

func any_toast(frag: String) -> bool:
	for t in toasts:
		if String(t).contains(frag):
			return true
	return false

func rst() -> void:
	gs.from_dict({"v": 2, "level": 1, "class_id": "warrior"})
	toasts.clear()

func qstatus(id: String) -> int:
	return QuestsData.status(gs, id)

func qentry(id: String) -> Variant:
	for e in QuestsData.entries(gs):
		if String(e.id) == id:
			return e
	return null

func target_done(id: String, prefix: String) -> bool:
	var e: Variant = qentry(id)
	if e == null:
		return false
	for t in e.targets:
		if String(t.label).begins_with(prefix):
			return bool(t.done)
	return false

# --- реплики канонических мутаций (скопированы из fixed-версий скриптов) ---

func talk_elder_accept() -> void:
	gs.elder_quest = 1
	gs.quest_changed.emit()

func talk_elder_deliver() -> void:  # world.gd fixed: herbs-=3 (излишек остаётся)
	if int(gs.herbs) >= 3 and int(gs.elder_quest) == 1:
		gs.elder_quest = 2
		gs.herbs -= 3
		gs.add_xp(25)
		gs.quest_changed.emit()

func talk_merchant_accept() -> void:
	gs.slime_quest = 1
	gs.quest_changed.emit()

func merchant_can_deliver() -> bool:  # world.gd fixed: круговой счётчик
	return int(gs.slime_quest) == 1 and int(gs.slime_kills_circle) >= 3

func talk_merchant_deliver() -> void:
	if not merchant_can_deliver():
		return
	gs.slime_quest = 2
	gs.add_xp(30)
	gs.quest_changed.emit()

func kill_slime(n := 1) -> void:  # slime.gd fixed: два счётчика
	for _i in n:
		gs.slime_kills += 1
		gs.slime_kills_circle += 1
		Achv.on_slime_kill()
		gs.add_xp(7)
		gs.quest_changed.emit()

func kill_boss() -> void:  # brute.gd босс-ветка
	gs.boss_defeated = true
	Achv.on_boss_death()
	var boss_key := "ng.boss_%d" % gs.ng_wave()
	if int(gs.flags.get(boss_key, 0)) == 0:
		gs.set_flag(boss_key, 1)
		Achv.grant_ash(3)
	gs.add_xp(40)
	gs.quest_changed.emit()

func open_village_chest() -> void:  # interactable.gd chest-ветка
	if bool(gs.chest_used("chest@village:37,21")):
		return
	gs.has_sword = true
	gs.chest_mark_used("chest@village:37,21")
	Achv.on_chest_opened()
	gs.quest_changed.emit()

func open_cave_chest() -> void:  # dungeon_zone.gd CaveChest fixed
	if int(gs.cave_state) < 3 or not bool(gs.has_key):
		return
	if bool(gs.has_amulet):
		gs.toast.emit("Сундук пуст — амулет уже у тебя.")  # fixed-ветка dungeon_zone.gd
		return
	gs.has_amulet = true
	# PIN-SEED 42 (T4): сундук генераторной пещеры seed_zone(42,"cave",0) стоит
	# на (9,12) (дамп scratch_cm/dump_cave42.gd) — литерал ручной карты 18,18 мёртв.
	gs.chest_mark_used("chest@cave:9,12")
	Achv.on_chest_opened()
	gs.recalc_max_hp()
	gs.quest_changed.emit()

func open_ashen_chest() -> void:  # ashen_zone.gd AshenChest fixed
	if String(gs.flags.get("ashen.chest", "")) == "taken":
		return
	gs.set_flag("ashen.chest", "taken")
	gs.chest_mark_used("chest@ashen:30,24")
	Achv.on_chest_opened()
	gs.quest_changed.emit()

func enter_ashen() -> void:  # world.gd enter_ashen: флаг вместе с FirstHint
	if String(gs.flags.get("ashen.intro_seen", "")) == "":
		gs.set_flag("ashen.intro_seen", "1")
		gs.quest_changed.emit()

func kill_witch() -> void:  # mob_boss2.gd fixed: ачивка после флага
	gs.set_flag("ashen.boss", "dead")
	Achv.on_witch_death()
	gs.add_xp(25)
	gs.quest_changed.emit()

func rest_campfire(id: String) -> void:  # campfire.gd::_finish
	gs.campfires_used[id] = true
	Achv.on_campfire_used()
	gs.quest_changed.emit()

func tick() -> void:  # журнал: тик refresh
	QuestsData.refresh(gs)

# --- A: круг 1: сюжет start→end + новая честность ---

func sim_circle1() -> void:
	print("--- A: круг 1, сюжет (fixed-поведение) ---")
	rst()
	tick()
	ck("A1.журнал пустого мира: elder+cave видны, witch скрыт (нет intro_seen)",
		qentry("elder") != null and qentry("cave") != null and qentry("witch") == null)
	# elder: излишек трав больше не испаряется
	talk_elder_accept()
	gs.herbs += 5
	talk_elder_deliver()
	tick()
	ck("A1.herbs-=3: излишек 5-3=2 сохранён", int(gs.herbs) == 2, "herbs=%d" % gs.herbs)
	ck("A1.elder выполнен", qstatus("elder") == QuestsData.STATUS_DONE)
	# slime: круговой счётчик
	talk_merchant_accept()
	kill_slime(2)
	ck("A2.сдать нельзя на 2/3 круга", not merchant_can_deliver())
	kill_slime(1)
	ck("A2.сдать можно на 3/3 круга", merchant_can_deliver())
	talk_merchant_deliver()
	tick()
	ck("A2.slime выполнен, q_slimehunt автостартовал",
		qstatus("slime") == 2 and qstatus("q_slimehunt") == 1)
	kill_slime(5)  # круг: 8
	tick()
	ck("A2.q_slimehunt закрыт на 8 круга (награда-0 → без xp-суффикса в тосте)",
		qstatus("q_slimehunt") == 2 and any_toast("Зачистка леса!")
		and not any_toast("опыта"))
	ntok()
	# cave: цепочка этапов (порядок = world.gd/dungeon_zone.gd)
	gs.seen_cave_intro = true
	gs.quest_changed.emit()
	gs.cave_state = 1
	gs.quest_changed.emit()
	kill_boss()
	tick()
	ck("A3.witch по-прежнему скрыт (амулет не выдан)", qentry("witch") == null)
	gs.has_key = true
	gs.cave_state = 3
	gs.quest_changed.emit()
	open_cave_chest()
	gs.quest_changed.emit()
	gs.door_opened = true
	tick()
	ck("A3.cave: цель «Взять Амулет» [x] после сундука (wave 0, amulet=true)",
		target_done("cave", "Взять") and not target_done("cave", "Вернуть")
		and bool(gs.has_amulet) and int(gs.cave_state) == 3)
	gs.cave_state = 4  # возврат Геральду
	gs.quest_changed.emit()
	tick()
	ck("A3.cave выполнен", qstatus("cave") == 2)
	ck("A3.q_ashen автостартовал после возврата амулета (указатель на мету)",
		qstatus("q_ashen") == 1 and qentry("q_ashen") != null)
	ntok()
	var lv0: int = gs.level
	var xp0: int = gs.xp
	enter_ashen()
	tick()
	ck("A3.q_ashen выполнен фактом входа: +25 xp, тост с наградой",
		qstatus("q_ashen") == 2 and toasts.size() >= 1 and any_toast("(+25 опыта)")
		and (int(gs.level) != lv0 or int(gs.xp) == xp0 + 25), "toasts=%s" % str(toasts))
	ck("A3.witch story виден и активен после входа",
		qentry("witch") != null and qstatus("witch") == 1)
	ntok()
	var ash0 := Ash.balance()
	kill_witch()
	tick()
	ck("A3.witch выполнен; witch_slayer +1 пепла",
		qstatus("witch") == 2 and bool(gs.get_flag("ach.witch_slayer", false))
		and Ash.balance() == ash0 + 1)
	kill_witch()
	ck("A3.идемпотентность: повторная смерть ведьмы не удваивает пепел",
		Ash.balance() == ash0 + 1)
	# сундуки: единая схема chest@<area>:x,y (D4) → treasure на 3-м открытии
	open_village_chest()
	open_ashen_chest()
	ck("A3.treasure: 3 метки (пещера+деревня+Пепелище) → анлок",
		gs.chests_used.size() == 3 and bool(gs.get_flag("ach.treasure", false)),
		"chests=%s" % str(gs.chests_used))
	ntok()

# --- B: badge-квесты (награды, без дублей сигналов) ---

func sim_side_badges() -> void:
	print("--- B: побочки/badge (круг 1) ---")
	# q_suhotsvet: кумулятив сквозь варки (регрессия — не сломать)
	gs.materials = {"suhotsvet": 0, "zhim": 0}
	var d := 0
	while d < 12:
		gs.add_material("suhotsvet")
		d += 1
		tick()
		if d % 3 == 0 and gs.mat_count("suhotsvet") >= 2:
			gs.try_spend_materials({"suhotsvet": 2})
			Achv.on_brew()
			tick()
	ck("B1.q_suhotsvet закрыт сквозь варки (regression)", qstatus("q_suhotsvet") == 2)
	# q_campfires: «один костёр в мире» (world.CAMPFIRE_SPOTS) — цель круга = 1
	# отдых; ачивка «Три костра» переехала на вечный счётчик ach.n.campfires
	# (как brews/buys): campfires_used обнуляется кругом, 3 разных костра за
	# круг честной игрой недостижимы. Смена круга здесь — очистка campfires_used
	# (ровно то, что делает start_ng_plus; полный NG+ — секция C).
	rest_campfire("cf_village")
	tick()
	ck("B1.q_campfires активен после 1-го отдыха (when=first_campfire)",
		qstatus("q_campfires") == 1)
	var ecf: Variant = qentry("q_campfires")
	ck("B1.витрина q_campfires: label «Отдохнуть у костра», need=1", ecf != null \
		and String(ecf.targets[0].label) == "Отдохнуть у костра" \
		and int(ecf.targets[0].need) == 1 and int(ecf.targets[0].cur) == 1,
		"e=%s" % (str(ecf) if ecf != null else "null"))
	tick()
	ck("B1.q_campfires закрыт за 1 отдых (need=1)", qstatus("q_campfires") == 2)
	ck("B1.ачивка campfires НЕ на 1-м отдыхе (n.campfires=1 < 3)",
		int(gs.get_flag("ach.n.campfires", 0)) == 1
		and not bool(gs.get_flag("ach.campfires", false)))
	gs.campfires_used.clear()  # смена круга: костёр снова жив, счётчик вечен
	rest_campfire("cf_village")
	tick()
	ck("B1.campfires НЕ на 2-м отдыхе (n.campfires=2)",
		int(gs.get_flag("ach.n.campfires", 0)) == 2
		and not bool(gs.get_flag("ach.campfires", false)))
	gs.campfires_used.clear()
	rest_campfire("cf_village")
	tick()
	ck("B1.campfires ровно на 3-м отдыхе между кругами; счёт=3",
		bool(gs.get_flag("ach.campfires", false))
		and int(gs.get_flag("ach.n.campfires", 0)) == 3)
	ntok()
	# q_brewer: счётчик вечный ach.n.brews (BREWED_CAP=2 — поясом мерить нельзя)
	ck("B2.q_brewer активен (brews>0 уже из B1)", qstatus("q_brewer") == 1)
	var e: Variant = qentry("q_brewer")
	var cur_b := -1
	if e != null:
		cur_b = int(e.targets[0].cur)
	ck("B2.прогресс = ach.n.brews (не пояс brewed_potions)",
		e != null and cur_b == int(gs.get_flag("ach.n.brews", 0)),
		"cur=%d flag=%d" % [cur_b, int(gs.get_flag("ach.n.brews", 0))])
	while int(gs.get_flag("ach.n.brews", 0)) < 6:
		Achv.on_brew()
		tick()
	ck("B2.q_brewer закрыт ровно на счётчике 6",
		qstatus("q_brewer") == 2 and int(gs.get_flag("ach.n.brews", 0)) == 6)
	ck("B2.награда +25 xp в тосте", any_toast("(+25 опыта)"))
	ck("B2.meta-метка q_brewer проставлена", int(gs.get_flag("meta.q_brewer_done", -1)) == 1)
	ntok()
	# 3 варки: DONE не ре-взводится, тостов нет (brewer_10 на 10-й — не здесь)
	for _i in 3:
		Achv.on_brew()
		tick()
	ck("B2.после закрытия: on_brew/refresh не генерят тостов и статуса",
		ntok() == 0 and qstatus("q_brewer") == 2)
	# q_wealth: бейдж по золоту на руках
	gs.gold = 160
	gs.gold_changed.emit()
	tick()
	ck("B3.q_wealth активен при 160 (порог when=150)", qstatus("q_wealth") == 1)
	gs.gold = 250
	tick()
	ck("B3.q_wealth закрыт при 250 + meta-метка",
		qstatus("q_wealth") == 2 and int(gs.get_flag("meta.q_wealth_done", -1)) == 1)
	ntok()

# --- C: NG+ после всех правок ---

func sim_ng_plus() -> void:
	print("--- C: NG+ (fixed-семантика) ---")
	rst()
	# полный круг 1 (сжато)
	talk_elder_accept()
	gs.herbs += 4
	talk_elder_deliver()
	talk_merchant_accept()
	kill_slime(8)
	talk_merchant_deliver()
	kill_boss()
	gs.seen_cave_intro = true
	gs.cave_state = 1
	gs.has_key = true
	gs.cave_state = 3
	gs.door_opened = true
	open_cave_chest()
	gs.cave_state = 4
	open_village_chest()
	enter_ashen()
	open_ashen_chest()
	kill_witch()
	# «Один костёр в мире»: 1 отдых за круг (q_campfires need=1); вечный
	# ach.n.campfires копит 3 отдыха между кругами — здесь смена круга
	# эмулируется очисткой campfires_used (полный start_ng_plus — ниже).
	rest_campfire("cf_village")
	gs.campfires_used.clear()
	rest_campfire("cf_village")
	gs.campfires_used.clear()
	rest_campfire("cf_village")
	for _i in 6:
		Achv.on_brew()
		tick()
	var dm := 0
	while dm < 12 and int(gs.get_flag("q.got.suhotsvet", 0)) < 5:
		if gs.add_material("suhotsvet"):
			dm += 1
		tick()
	# q_wealth: старт (>=150) и финиш (>=250) — на разных тиках, как в игре
	gs.gold = 260
	gs.gold_changed.emit()
	tick()
	tick()
	var all_done := true
	for idv in QuestsData.ids():
		if qstatus(String(idv)) != 2:
			all_done = false
	ck("C0.к концу круга 1 закрыты ВСЕ 10 квестов реестра", all_done,
		"brewer=%d wealth=%d ashen=%d witch=%d suhotsvet=%d" % [qstatus("q_brewer"),
			qstatus("q_wealth"), qstatus("q_ashen"), qstatus("witch"), qstatus("q_suhotsvet")])
	# переносимые артефакты перед сменой круга
	gs.gold = 120
	gs.herbs = 4  # остаток трав на момент смены круга
	gs.set_flag("meta.purse", 2)  # алтарь «Кошелёк» куплен дважды (хунк б)
	var ash0 := Ash.balance()
	ntok()
	var w: int = gs.start_ng_plus()
	ck("C1.волна 1; slime_kills total=%d перенесён, circle=0" % gs.slime_kills,
		w == 1 and int(gs.slime_kills) == 8 and int(gs.slime_kills_circle) == 0)
	ck("C1.хунк herbs=0: сумка трав не переносится", int(gs.herbs) == 0)
	ck("C1.хунк purse: +50x2 зол. к старту круга (120→220)", int(gs.gold) == 220,
		"gold=%d" % gs.gold)
	ck("C1.badge-метки живучи (meta.q_brewer_done/q_wealth_done)",
		int(gs.get_flag("meta.q_brewer_done", -1)) == 1 and int(gs.get_flag("meta.q_wealth_done", -1)) == 1)
	ck("C1.ach.* перенесены (witch_slayer/campfires/treasure)",
		bool(gs.get_flag("ach.witch_slayer", false)) and bool(gs.get_flag("ach.campfires", false))
		and bool(gs.get_flag("ach.treasure", false)))
	ck("C1.пепел не дублируется при смене круга", Ash.balance() == ash0)
	# круг 2: ничего не фаршится само
	tick()
	ck("C2.после NG+ refresh: ноль тостов, badge не ре-взведены",
		ntok() == 0 and qstatus("q_brewer") == 0 and qstatus("q_wealth") == 0)
	ck("C2.q_ashen скрыт до нового возврата амулета", qstatus("q_ashen") == 0 and qentry("q_ashen") == null)
	ck("C2.witch story скрыт (ashen.intro_seen стёрт вайпом)", qentry("witch") == null)
	# merchant: даром круг-2 не сдаётся «вчерашними» трупами
	talk_merchant_accept()
	ck("C3.сюжет слаймов в круге 2 НЕ сдать без новых убийств", not merchant_can_deliver())
	var e: Variant = qentry("slime")
	ck("C3.журнал: 0/3 в новом круге (total=8 не враньё)",
		e != null and int(e.targets[0].cur) == 0)
	kill_slime(3)
	ck("C3.сдать можно после 3 НОВЫХ убийств", merchant_can_deliver())
	talk_merchant_deliver()
	tick()
	ck("C3.q_slimehunt пере-взведён с 0 (не мгновенный финиш)",
		qstatus("q_slimehunt") == 1 and int(QuestsData.progress(gs, "kill_slime")) == 3,
		"status=%d progress=%d" % [qstatus("q_slimehunt"), int(QuestsData.progress(gs, "kill_slime"))])
	kill_slime(5)
	tick()
	ck("C3.q_slimehunt закрыт на 8 круга 2", qstatus("q_slimehunt") == 2)
	# амулет: журнал не врёт до алтаря нового круга
	ck("C4.take_amulet не отмечен в свежем круге (has_amulet перенесён, cave_state=0)",
		not target_done("cave", "Взять"))
	gs.cave_state = 3  # дошёл до алтаря этого круга
	tick()
	ck("C4.take_amulet [x] только у открытой двери этого круга", target_done("cave", "Взять"))
	# stale-сундук круга 2 (узел дожил перезаход): guard has_amulet → без мутаций
	gs.has_key = true
	var marks0: int = gs.chests_used.size()
	open_cave_chest()
	ck("C4.сундук круга 2 при амулете: ни метки, ни прогресса treasure",
		gs.chests_used.size() == marks0 and not bool(gs.chest_used("chest@cave:9,12")))
	# честность вкладки «Достижения» на живом Journal (до легаси-сейва, что сотрёт ach.*)
	sim_journal_honesty()
	# легаси-сейв: seed кругового счётчика тоталом (активный квест не обнуляется)
	gs.from_dict({"v": 2, "level": 1, "class_id": "warrior", "slime_kills": 8, "slime_quest": 1})
	ck("C5.легаси-сейв без круга: seed=8 → активный квест не обнулён", int(gs.slime_kills_circle) == 8)
	ntok()
	for _i in 6:
		w = gs.start_ng_plus()
	ck("C6.кап волн держится (6 стартов → волна 5)", w == 5 and int(gs.flags["ng.wave"]) == 5)

# --- честность вкладки достижений после NG+-обнуления live-счётчиков ---

func sim_journal_honesty() -> void:
	print("--- C-JRN: честность вкладки «Достижения» ---")
	# состояние выше: campfires/treasure анлокнуты (ach.* вечны), live-счётчики обнулены NG+
	var jr := Journal.new()
	add_child(jr)  # _ready строит _ach_list синхронно
	var texts: Array = []
	# g14: список фильтруется по активной рубрике — обходим все, строки-то вечные
	for ai in AchvCatalog.CAT_TITLES.size():
		jr.select_asub(ai)  # пересобирает внутри себя
		var stack: Array = [jr]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is Label:
				texts.append((n as Label).text)
			for c in n.get_children():
				stack.append(c)
	var cf_line := ""
	var tr_line := ""
	for t in texts:
		var s := String(t)
		if s.contains("Костров:"):
			cf_line = s
		if s.contains("Сундуков:"):
			tr_line = s
	ck("C-JRN.campfires: счётчик скрыт за ✓ (не «0/3» после NG+)",
		cf_line.contains("✓") and not cf_line.contains("0/3"), "line='%s'" % cf_line)
	ck("C-JRN.treasure: счётчик скрыт за ✓ (не «0/3» после NG+)",
		tr_line.contains("✓") and not tr_line.contains("0/3"), "line='%s'" % tr_line)
	jr.queue_free()

# --- D: гейты ачивок после правок ---

func sim_achv_gates() -> void:
	print("--- D: гейты достижений ---")
	rst()
	var at25 := -1
	var at40 := -1
	for i in range(1, 46):
		gs.slime_kills = i
		Achv.on_slime_kill()
		if at25 < 0 and bool(gs.get_flag("ach.hunter_25", false)):
			at25 = i
		if at40 < 0 and bool(gs.get_flag("ach.hunter_100", false)):
			at40 = i
	ck("D1.hunter_25 ровно на 25", at25 == 25, "at25=%d" % at25)
	ck("D1.hunter_100: гейт опущен — ровно на 40", at40 == 40, "at40=%d" % at40)
	ck("D1.награда hunter-ветки однократна (пепел 0+2)", Ash.balance() == 2, "ash=%d" % Ash.balance())
	rst()
	for _i in 10:
		Achv.on_brew()
	ck("D2.brewer_10 на 10-й варке", bool(gs.get_flag("ach.brewer_10", false)))
	ck("D2.витрина treasure: goal=3, desc «Открыть все сундуки мира.»",
		int(_catalog_row("treasure").get("goal", 0)) == 3
		and String(_catalog_row("treasure").get("desc", "")) == "Открыть все сундуки мира.")
	ck("D2.витрина hunter_100: goal=40 (число синхронно гейту)",
		int(_catalog_row("hunter_100").get("goal", 0)) == 40)
	ck("D2.каталог: witch_slayer+смерть-вехи добавлены (20 строк)",
		_catalog_row("witch_slayer") != null and _catalog_row("rekindled") != null
		and _catalog_row("undying") != null and AchvCatalog.ITEMS.size() == 20)

func _catalog_row(id: String) -> Dictionary:
	for r in AchvCatalog.ITEMS:
		if String((r as Dictionary).get("id", "")) == id:
			return r
	return {}

# --- F: зонды исходных дыр аудита (qa_audit.gd @0c9dfe0) на фикшенном дереве ---
# Каждый — дословный перенос проверки old-стенда, ожидающей «не воспроизвелось».
# Состояния self-contained: детерминизм и независимость от порядка секций.

func sim_old_holes() -> void:
	print("--- F: пробы дыр H1..H7/D4 (ожидаем PASS: не воспроизвелось) ---")
	# --- H1..H5: свежий круг 1 → NG+ → круг 2 (old-контекст пробы) ---
	rst()
	talk_elder_accept()
	gs.herbs += 4  # fixed-deliver оставляет излишек 1 — ровно old-условие дыры
	talk_elder_deliver()
	talk_merchant_accept()
	kill_slime(8)
	talk_merchant_deliver()
	gs.seen_cave_intro = true
	gs.cave_state = 1
	gs.has_key = true
	gs.cave_state = 3
	gs.door_opened = true
	open_cave_chest()
	gs.cave_state = 4
	tick()
	ntok()
	gs.start_ng_plus()
	# H1: old «herbs != 0» — остаток сумки переносился в новый круг
	hole("H1.herbs НЕ обнуляется при NG+ (остаток переносится)", int(gs.herbs) != 0,
		"herbs=%d на старте круга 2" % gs.herbs)
	# H2: old «instant_ready» — total-гейт world.talk позволял сдать без убийств
	talk_merchant_accept()
	hole("H2.сюжет «3 слайма» в круге 2 выдаётся БЕЗ новых убийств", merchant_can_deliver(),
		"slime_kills=%d total при circle=0" % gs.slime_kills)
	# H3: old «мгновенный финиш q_slimehunt за тик» — old-путь: deliver без гейта
	gs.slime_quest = 2  # old world.gd пропускал сдачу на total>=3; fixed — нет (H2 выше)
	gs.quest_changed.emit()
	tick()
	tick()
	hole("H3.q_slimehunt пере-стартовал и завершён за 1 тик без игрового прогресса",
		qstatus("q_slimehunt") == 2,
		"status=%d, убийств в круге 2: 0" % qstatus("q_slimehunt"))
	# H4: old «Взять Амулет [x] до взятия» — progress по одному has_amulet
	tick()
	hole("H4.журнал круга 2: цель «Взять Амулет» показана [x] до взятия",
		target_done("cave", "Взять"), "has_amulet перенесён, cave_state=0")
	# H5: old «алтарный сундук без ответа» — fixed guard обязан отвечать тостом
	ntok()
	gs.cave_state = 3  # круг 2: дошёл до алтаря (old-сценарий дыры)
	gs.has_key = true
	open_cave_chest()
	hole("H5.алтарный сундук в круге 2 — «Открыть сундук» без ответа",
		not any_toast("Сундук пуст"), "fixed: toast-ответ + ни метки, ни лута")
	ck("H5.и по-прежнему ни метки, ни двойного амулета",
		not bool(gs.chest_used("chest@cave:9,12")) and bool(gs.has_amulet))
	# --- H6/D4/H7: статические пробы исходников (поставка, не реплика) ---
	var src_cave := file_src("res://scripts/dungeon_zone.gd")
	var src_ashen := file_src("res://scripts/ashen_zone.gd")
	hole("H6.CaveChest/AshenChest не зовут chest_mark_used/on_chest_opened (treasure недостижим)",
		not (src_cave.contains("chest_mark_used") and src_cave.contains("on_chest_opened")
			and src_ashen.contains("chest_mark_used") and src_ashen.contains("on_chest_opened")),
		"grep-доказательство по исходникам")
	hole("D4.алтарь «Кошелёк» — мёртвая покупка (нет потребителей meta.purse)",
		not file_has("res://scripts/game_state.gd", "meta.purse"),
		"fixed: start_ng_plus начисляет 50xстепень (C1 выше = 220 зол.)")
	hole("H7.hunter_100 требует 100 убийств (~33 мин чистой охоты)",
		file_has("res://scripts/achv.gd", "slime_kills >= 100"),
		"fixed: гейт 40 (D1 выше — точное число анлока)")
	ntok()

# --- E: поставка контента после балансировки ---

func sim_supply_info() -> void:
	print("--- E: поставка/баланс ---")
	inf("E1", "hunter-гейт 40: потолок деревни ~7.2 уб/мин → ≥5.6 мин чистого фарма, "
		+ "реалистично ~13 мин суммарно за игру (total копится между кругами)")
	inf("E2", "q_suhotsvet (сухоцвет со слаймов, need 5) сходится с охотничьим гейтом 40")
	inf("E3", "q_ashen: 25 xp за вход на Пепелище каждый круг — маршрут и так обязателен (Ведьма)")

# --- G: t18 «Квесты поясов» (25.11, DESIGN_DEPTH_V2 §3) --------------------
# Цепочка 12 звеньев через доску: gate «по мере открытия поясов» (wm.open),
# цели biome_kill/biome_chest, награда один раз (флаг 2 до выдачи), финал
# пояса — гарантированный реликт (force_relic t17). Полный путь на 4 сидах —
# пин-таблица сигнатур реликтов (детерминизм shash-канона).

## Мировая заглушка: Loot.on_mob_death читает world.active_area для поясного
## счётчика. Только это поле и нужно (Fx при синтетическом kind без золота не
## вызывается — канон qa_bt/qa_s4 с синтетическими kind).
class FakeArea:
	extends Node2D
	var active_area := ""

var fake_area: Node2D

func belt_kill(zone: String, n: int) -> void:
	if fake_area == null:
		fake_area = FakeArea.new()
	fake_area.set("active_area", "loc_" + zone)
	for k in n:
		Loot.on_mob_death("qa_belt_probe@b0", Vector2.ZERO, fake_area)

func belt_kill_outside(area: String) -> void:
	if fake_area == null:
		fake_area = FakeArea.new()
	fake_area.set("active_area", area)
	Loot.on_mob_death("qa_belt_probe@b0", Vector2.ZERO, fake_area)

## Пин-сида полного пути (t18, 25.11): сигнатура = порядок реликтовых
## выдач (id или "-" = серебро-откат) + итог золота (старт героя 10 + 750
## наград цепочки = 760, воина, ни одного отката). Пере-пин — только
## датированной записью (паттерн таблицы аффиксов t17). Снято прогоном
## 25.11 (build t18 до пинования, G7 PASS в пробеге).
const BELT_SEEDS := [1, 7, 1337, 90210]
const BELT_SIGS := [
	"chain|sword|boarhide|fangblade|shield_raven|nordsword#760",
	"leather|chain|shield_iron|nordsword|rune_blade|shield_raven#760",
	"shortsword|nordsword|shield_iron|chain|shield_raven|boarhide#760",
	"leather|boarhide|nordsword|rune_blade|fangblade|shield_raven#760",
]

## Пройти цепочку до конца; вернуть «pick1|pick2…#gold».
func walk_full_chain() -> String:
	var picks: Array = []
	for i in QuestsData.BELT_CHAIN.size():
		var def: Dictionary = QuestsData.belt_link(i)
		var z := String(def.get("zone", ""))
		gs.set_flag("wm.open." + z, "1")
		QuestsData.belt_offer(gs, i)
		if String(def.get("type", "")) == "biome_kill":
			belt_kill(z, int(def.get("need", 1)))
		else:
			QuestsData.note_belt_chest(gs, z)
		var is_relic := bool(def.get("relic", false))
		var a0: int = gs.affixes.size()
		var g0 := int(gs.gold)
		QuestsData.belt_turnin(gs, i)
		if is_relic:
			var got_new: bool = gs.affixes.size() == a0 + 1
			picks.append(String(gs.affixes.keys().back()) if got_new else "-")
			# награда ровно один раз: второй тычок доски ничего не должен менять
			QuestsData.belt_turnin(gs, i)
			if int(gs.gold) != g0 + int(def.get("gold", 0)) or gs.affixes.size() != a0 + (1 if got_new else 0):
				return "DOUBLE_REWARD@" + String(def.get("id", ""))
	return "|".join(PackedStringArray(picks)) + "#%d" % int(gs.gold)

func sim_belt_chain() -> void:
	print("--- G: t18 цепочка поясов ---")
	rst()
	ck("G0.чистый герой: current=0, в журнале пусто",
		QuestsData.belt_current(gs) == 0 and qentry("bq_snow_1") == null)
	QuestsData.belt_offer(gs, 0)  # без открытого пояса — no-op
	ck("G0.без открытого пояса не берётся",
		not QuestsData.belt_can_offer(gs, 0) and QuestsData.belt_status(gs, 0) == QuestsData.STATUS_NONE)
	# G1: gate «по мере открытия» + взятие
	gs.set_flag("wm.open.snow", "1")  # канон: world.enter_location (t7)
	ck("G1.пояс открыт → звено предложено", QuestsData.belt_can_offer(gs, 0))
	QuestsData.belt_offer(gs, 0)
	ck("G1.взято, журнал видит, цель не закрыта",
		QuestsData.belt_status(gs, 0) == QuestsData.STATUS_ACTIVE
		and qentry("bq_snow_1") != null and not target_done("bq_snow_1", "Зачистить"))
	# G2: счётчик убийств — ТОЛЬКО своя локация, канонический хук лута
	belt_kill("snow", 3)
	ck("G2.3/4 в своём поясе; чужие пояса и лес — мимо",
		QuestsData.belt_progress(gs, 0) == 3 and not QuestsData.belt_ready(gs, 0))
	belt_kill("desert", 5)
	belt_kill_outside("forest")
	ck("G2.чужая аттрибуция не считается", QuestsData.belt_progress(gs, 0) == 3)
	ck("G2.цепочка не трогает slime_kills_circle", int(gs.slime_kills_circle) == 0)
	# G3: сдача один раз
	belt_kill("snow", 1)
	ck("G3.цель закрыта (4/4)", QuestsData.belt_ready(gs, 0) and target_done("bq_snow_1", "Зачистить"))
	var g0 := int(gs.gold)
	QuestsData.belt_turnin(gs, 0)
	ck("G3.сдача +30 зол., статус 2, журнал done",
		int(gs.gold) == g0 + 30 and QuestsData.belt_status(gs, 0) == QuestsData.STATUS_DONE
		and target_done("bq_snow_1", "Зачистить"))
	QuestsData.belt_turnin(gs, 0)
	ck("G3.повторная сдача — награда ноль", int(gs.gold) == g0 + 30 and QuestsData.belt_current(gs) == 1)
	QuestsData.belt_offer(gs, 0)
	ck("G3.сданное не берётся заново", QuestsData.belt_status(gs, 0) == QuestsData.STATUS_DONE)
	# G4: финал пояса — гарантированный реликт
	ck("G4.финал пояса берётся (пояс уже открыт)", QuestsData.belt_can_offer(gs, 1))
	QuestsData.belt_offer(gs, 1)
	ck("G4.сундук не найден — не готово", not QuestsData.belt_ready(gs, 1))
	QuestsData.note_belt_chest(gs, "snow")
	ck("G4.сундук → цель закрыта", QuestsData.belt_ready(gs, 1) and target_done("bq_snow_2", "Найти"))
	g0 = int(gs.gold)
	QuestsData.belt_turnin(gs, 1)
	ck("G4.+45 зол. и ровно одна реликтовая запись",
		int(gs.gold) == g0 + 45 and gs.affixes.size() == 1)
	var pick := String((gs.affixes.keys() as Array)[0])
	ck("G4.реликт = ровно 2 аффикса (force_relic)", (gs.affixes[pick] as Array).size() == 2)
	QuestsData.belt_turnin(gs, 1)
	ck("G4.реликт не дублируется при повторной сдаче",
		int(gs.gold) == g0 + 45 and gs.affixes.size() == 1)
	# G5: сейв-roundtrip середины цепочки
	var snap: Dictionary = gs.to_dict()
	belt_kill("snow", 4)
	QuestsData.note_belt_chest(gs, "desert")
	gs.add_gold(999)
	gs.from_dict(snap)
	ck("G5.roundtrip: звенья/счётчики/золото/аффиксы восстановлены",
		QuestsData.belt_status(gs, 0) == QuestsData.STATUS_DONE
		and QuestsData.belt_status(gs, 1) == QuestsData.STATUS_DONE
		and QuestsData.belt_progress(gs, 1) == 1
		and int(gs.gold) == int(snap.get("gold", -1)) and gs.affixes.size() == 1)
	# G6: новый круг — цепочка пере-взводится (семантика побочек q.*)
	var w: int = gs.start_ng_plus()
	ck("G6.NG+: current=0, статусы/счётчики/журнал обнулены",
		w == 1 and QuestsData.belt_current(gs) == 0
		and QuestsData.belt_status(gs, 0) == QuestsData.STATUS_NONE
		and QuestsData.belt_progress(gs, 0) == 0 and qentry("bq_snow_1") == null)
	# G7: полный путь 12 звеньев на 4 сидах — бит-в-бит пин-таблица
	for si in BELT_SEEDS.size():
		rst()
		gs.run_seed = int(BELT_SEEDS[si])
		var sig := walk_full_chain()
		inf("G7.seed%d" % int(BELT_SEEDS[si]), sig)
		if String(BELT_SIGS[si]) == "":
			ck("G7.seed %d: путь 12/12 без двойной награды (таблица ещё пуста — пробег)" % int(BELT_SEEDS[si]),
				not sig.contains("DOUBLE_REWARD") and QuestsData.belt_current(gs) == QuestsData.BELT_CHAIN.size())
		else:
			ck("G7.seed %d: путь 12/12, реликты bit-в-бит, награда один раз" % int(BELT_SEEDS[si]),
				sig == String(BELT_SIGS[si]) and QuestsData.belt_current(gs) == QuestsData.BELT_CHAIN.size())
	# G8: провода на месте (статические пины интеграции)
	ck("G8.провода: хук лута / сундук-хук / доска в деревне / кнопка HUD",
		file_has("res://scripts/loot.gd", "note_belt_kill_area")
		and file_has("res://scripts/biome_zone.gd", "note_belt_chest")
		and file_has("res://scripts/world.gd", '"board", Vector2i(12, 8)')
		and file_has("res://scripts/hud.gd", "_build_journal_btn"))
	ck("G8.звенья цепочки НЕ в реестре QUESTS (нет автозавершения refresh)",
		not file_src("res://scripts/quests_data.gd").contains("\"bq_snow_1\": {"))
	# G9: клавиатурный канон не сломан: журнал J, Q — зелье
	ck("G9.журнал на J (KEY_Q в journal.gd не появился)",
		file_has("res://scripts/journal.gd", "KEY_J") and not file_has("res://scripts/journal.gd", "KEY_Q"))
