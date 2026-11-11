extends Node
## QA-CF: стенд-драйвер «один костёр в мире» (HEAD f3aa4c9 + sand_cf).
## Канон фидбека «костров слишком много»: в мире ровно один костёр cf_village;
## q_campfires — need 1 на круг; ачивка «Три костра» на ВЕЧНОМ суммарном
## канале ach.n.campfires (гейт >=3, как brews/buys), костёр один — отдых
## переносится между кругами.
##
## Покрытия:
##   W — мир: world.campfires.size()==1, id cf_village, костёр жив;
##   Q — отдых -> q_campfires ACTIVE->DONE за круг (need 1), журнал-витрина;
##   J — journal::_ach_cur("n.campfires") подхватывает флаг автоматически;
##   A — 3 отдыха в 3 «кругах» (эмуляция start_ng_plus между) -> ачивка
##       ровно один раз, счёт 3; 2 круга без 3-го -> НЕ анлокнул раньше;
##       4-й отдых -> без дубля награды/тоста (идемпотентность unlock).
## Детерминирован: Journal.ticks отключён, QuestsData.refresh зовём руками.
## Запуск: godot --headless --fixed-fps 60 res://qa_cf.tscn (чистый user://).
## ВЕРДИКТ: строка "QA_CF SUMMARY | PASS=n FAIL=n", quit(0) при 0 фейлов.

var pass_n := 0
var fail_n := 0
var world: Node2D
var jr: Node = null
var toasts: Array = []

func chk(g: String, n: String, c: bool, info: String = "") -> void:
	if c:
		pass_n += 1
		print("PASS | %s | %s" % [g, n])
	else:
		fail_n += 1
		print("FAIL | %s | %s | %s" % [g, n, info])

func tick() -> void:  # тик журнала (единственный носитель QuestsData.refresh)
	QuestsData.refresh(GameState)

func rest() -> void:
	# канонический хвост campfire.gd::_finish() (SINGLE_USE-ветка): пометка
	# костра + хук ачивки + quest_changed (автосейв-канал). Круг 1 — через
	# реальный узел (_mark_used: used/perist/визуал тем же кодом игры); в
	# эмулированных кругах 2+ узел не переспаунен — тот же канал GameState.
	var cf = world.campfires[0] if world.campfires.size() == 1 else null
	if cf != null and not cf.used:
		cf._mark_used()
	else:
		GameState.campfires_used["cf_village"] = true
	Achv.on_campfire_used()
	GameState.quest_changed.emit()

func circle_wipe() -> void:
	# Эмуляция game_state.gd::start_ng_plus() — Subset БЕЗ сигналов/сейва/
	# перезагрузки сцены (сцена стенда не current, reload ломает драйвер):
	# ровно то, что важно для этого стенда — костёр снова жив, q.* пере-
	# взводятся. n.campfires (ach.*) — вечный, не трогается. ng.wave НЕ
	# поднимаем: подъём круга легально триггерит ach ng_* (ещё +пепел в grant_ash
	# через _check_ng) и ломает честную сверку награды «ровно +1».
	GameState.campfires_used = {}
	var wipe_keys: Array = []
	for k in GameState.flags:
		if String(k).begins_with("q."):
			wipe_keys.append(k)
	for k in wipe_keys:
		GameState.flags.erase(k)

func toast_count(frag: String) -> int:
	var n := 0
	for t in toasts:
		if String(t).contains(frag):
			n += 1
	return n

func qstatus(id: String) -> int:
	return QuestsData.status(GameState, id)

func qentry(id: String) -> Variant:
	for e in QuestsData.entries(GameState):
		if String(e.id) == id:
			return e
	return null

func catalog_row(id: String) -> Dictionary:
	for r in AchvCatalog.ITEMS:
		if String((r as Dictionary).get("id", "")) == id:
			return r
	return {}

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	print("=== QA CF START ===")
	var ms: Node = load("res://scenes/main.tscn").instantiate()
	add_child(ms)
	world = ms
	for c in world.get_children():
		if c is Journal:
			jr = c
			jr.set_process(false)  # только ручные тики refresh — детерминизм
	for i in 6:
		await get_tree().process_frame
	_group_world()
	_group_quest()
	_group_journal()
	_group_achv()
	print("QA_CF SUMMARY | PASS=%d FAIL=%d" % [pass_n, fail_n])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	get_tree().quit(0 if fail_n == 0 else 1)

# ---------------------------------------------------------------- W: мир

func _group_world() -> void:
	var g := "W"
	chk(g, "Journal найден и приторможен (ручные тики)", jr != null)
	var spots: Variant = world.get("CAMPFIRE_SPOTS")
	chk(g, "CAMPFIRE_SPOTS: ровно 1 запись", spots is Dictionary and (spots as Dictionary).size() == 1,
		"spots=%s" % str(spots))
	chk(g, "world.campfires.size() == 1", world.campfires.size() == 1,
		"n=%d" % world.campfires.size())
	var ids: Array = []
	for cf in world.campfires:
		ids.append(String(cf.camp_id))
	chk(g, "id костра ровно cf_village", ids == ["cf_village"], "ids=%s" % str(ids))
	var cf = world.campfires[0] if world.campfires.size() == 1 else null
	chk(g, "cf_village заспавнен в тайл (18,13)", cf != null \
		and cf.position == world.tile_to_world(Vector2i(18, 13)),
		"pos=%s" % (str(cf.position) if cf != null else "null"))
	chk(g, "костёр жив (не пепел) на свежем старте", cf != null and cf.used == false \
		and cf.get_hint() != "Костёр погас")

# ---------------------------------------------------------------- Q: квест

func _group_quest() -> void:
	var g := "Q"
	tick()
	chk(g, "до отдыха q_campfires не начат (when=first_campfire)", qstatus("q_campfires") == 0)
	rest()
	tick()
	chk(g, "после отдыха q_campfires АВТОстартовал", qstatus("q_campfires") == 1)
	var e: Variant = qentry("q_campfires")
	chk(g, "витрина: label «Отдохнуть у костра», need=1, cur=1", e != null \
		and String(e.targets[0].label) == "Отдохнуть у костра" \
		and int(e.targets[0].need) == 1 and int(e.targets[0].cur) == 1,
		"e=%s" % (str(e) if e != null else "null"))
	tick()
	chk(g, "q_campfires DONE за круг (один отдых, need=1)", qstatus("q_campfires") == 2)
	chk(g, "тост закрытия с новым названием «Привал у костра»",
		toast_count("Привал у костра") >= 2)  # старт + завершение
	chk(g, "костёр после отдыха — пепел в узле и в персисте (одноразовый)",
		world.campfires[0].used == true
		and bool(GameState.campfires_used.get("cf_village", false))
		and world.campfires[0].get_hint() == "Костёр погас")

# ---------------------------------------------------------------- J: журнал

func _group_journal() -> void:
	var g := "J"
	var row := catalog_row("campfires")
	chk(g, "каталог campfires: counter=n.campfires, goal=3",
		String(row.get("counter", "")) == "n.campfires" and int(row.get("goal", 0)) == 3,
		"row=%s" % str(row))
	chk(g, "каталог campfires: name «Три костра», desc «между кругами»",
		String(row.get("name", "")) == "Три костра" \
		and String(row.get("desc", "")).contains("между кругами"))
	chk(g, "_ach_cur(\"n.campfires\") == флаг ach.n.campfires",
		jr != null and jr._ach_cur("n.campfires") == int(GameState.flags.get("ach.n.campfires", 0)) \
		and jr._ach_cur("n.campfires") == 1)

# ---------------------------------------------------------------- A: ачивка

func _group_achv() -> void:
	var g := "A"
	chk(g, "круг 1: ачивка НЕ снята (n.campfires=1 < 3)",
		int(GameState.flags.get("ach.n.campfires", 0)) == 1
		and not bool(GameState.flags.get("ach.campfires", false)))
	# круг 2 (эмуляция смены круга: костёр ожил, q.* стёрты, счётчик вечен)
	circle_wipe()
	tick()
	chk(g, "круг 2: q_campfires пере-взведён (костёр снова жив)", qstatus("q_campfires") == 0)
	rest()
	tick()
	tick()
	chk(g, "круг 2: q_campfires снова DONE за круг", qstatus("q_campfires") == 2)
	chk(g, "2 круга без 3-го: ачивка НЕ анлокнута (n=2)",
		int(GameState.flags.get("ach.n.campfires", 0)) == 2
		and not bool(GameState.flags.get("ach.campfires", false)))
	# круг 3: третий отдых — ровно здесь и ровно один раз
	circle_wipe()
	var ash0: int = Ash.balance()
	var t0: int = toast_count("Три костра")
	rest()
	tick()
	tick()
	chk(g, "круг 3: ачивка campfires анлокнута, счёт == 3",
		bool(GameState.flags.get("ach.campfires", false))
		and int(GameState.flags.get("ach.n.campfires", 0)) == 3)
	chk(g, "награда ровно одна: пепел +1 (gold-часть награды = 0)", Ash.balance() == ash0 + 1,
		"ash %d->%d" % [ash0, Ash.balance()])
	chk(g, "тост «Три костра» ровно 1 раз", toast_count("Три костра") == t0 + 1,
		"n=%d" % (toast_count("Три костра") - t0))
	# круг 4: 4-й отдых — счёт растёт, награда не дублируется (идемпотентность)
	circle_wipe()
	var ash1: int = Ash.balance()
	rest()
	tick()
	tick()
	chk(g, "4-й отдых: n=4, ачивка жива, пепел/тост НЕ задвоены",
		int(GameState.flags.get("ach.n.campfires", 0)) == 4
		and bool(GameState.flags.get("ach.campfires", false))
		and Ash.balance() == ash1
		and toast_count("Три костра") == t0 + 1)
	# витрина после анлока: журнал прячет счётчик за ✓ (не «4/3» и не «0/3»)
	jr._rebuild_achv()
	var line := ""
	var stack: Array = [jr]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and String((n as Label).text).contains("Костров"):
			line = String((n as Label).text)
		for c in n.get_children():
			stack.append(c)
	chk(g, "журнал после анлока: «Костров: ✓» без дробей", line.contains("✓") \
		and not line.contains("/"), "line='%s'" % line)
