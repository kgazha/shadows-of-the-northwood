extends Node
## QA-ретест mержа 75b5b69, процесс-1: Esc-матрица vs Shop/Journal (п.2),
## гейт J в лавке (п.3), реальный ClickMove: тумблер + запись user://clickmove_cfg.json (п.4а).
## Финальный сейв (босс мёртв, пещера 2) остаётся для процесса-2 (п.1, п.4б).

var world: Node2D
var sm   # SettingsMenu
var journal
var shop: Shop
var fails := {"n": 0}

func ck(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		print("PASS %s" % name)
	else:
		fails["n"] += 1
		print("FAIL %s :: %s" % [name, detail])

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func push_key(phys: int) -> void:
	var e := InputEventKey.new()
	e.keycode = phys
	e.physical_keycode = phys
	e.pressed = true
	get_tree().root.push_input(e)
	var r := InputEventKey.new()
	r.keycode = phys
	r.physical_keycode = phys
	r.pressed = false
	get_tree().root.push_input(r)

func esc() -> void:
	push_key(KEY_ESCAPE)

func read_clickmove_cfg() -> Variant:
	if not FileAccess.file_exists("user://clickmove_cfg.json"):
		return null
	var f := FileAccess.open("user://clickmove_cfg.json", FileAccess.READ)
	if f == null:
		return null
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return v

func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://audio_cfg.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://clickmove_cfg.json"))
	# PIN-SEED 42 (T4): сид убеждает в final-seedsave ниже — процесс-2 (qa_r2)
	# грузит его и строит ту же детерминированную генераторную пещеру.
	GameState.run_seed = 42
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for c in world.get_children():
		if c is SettingsMenu:
			sm = c
		elif c is Journal:
			journal = c
	shop = Shop.I
	print("NOTE nodes: sm=%s journal=%s shop=%s ClickMove.I=%s" % [sm != null, journal != null, shop != null, ClickMove.I != null])
	_run()

func _run() -> void:
	await frames(3)

	# --- A: узлы и стартовое состояние ---
	ck(sm != null and journal != null and shop != null, "A nodes found")
	ck(ClickMove.I != null and is_instance_valid(ClickMove.I), "A world instantiated real ClickMove")
	ck(not sm.is_open() and not shop.is_open() and not journal.is_open(), "A all windows closed at start")

	# --- B: базовый Esc настроек (sanity) ---
	esc()
	ck(sm.is_open(), "B esc opens settings")
	esc()
	ck(not sm.is_open() and not GameState.input_locked, "B esc closes settings, lock released")

	# --- C (п.2): Esc закрывает Shop и Journal, SettingsMenu поверх них не открывается ---
	Shop.open()
	esc()
	ck(not Shop.is_open(), "C2 Esc closes shop")
	ck(not sm.is_open(), "C2 settings NOT opened over shop")
	ck(not GameState.input_locked, "C2 no lock residue after shop esc")
	journal.open()
	esc()
	ck(not journal.is_open(), "C2 Esc closes journal")
	ck(not sm.is_open(), "C2 settings NOT opened over journal")
	ck(not GameState.input_locked, "C2 no lock residue after journal esc")
	# лавка+журнал одновременно закрыты — теперь Esc наш
	esc()
	ck(sm.is_open(), "C2 Esc opens settings when world free")
	esc()

	# --- D (п.3): J при открытой лавке не создаёт двойной оверлей ---
	Shop.open()
	push_key(KEY_J)
	await frames(2)
	ck(Shop.is_open() and not journal.is_open(), "D J blocked while shop open (no double overlay)")
	Shop.close()
	await frames(2)
	push_key(KEY_J)
	await frames(2)
	ck(journal.is_open(), "D control: J opens journal when shop closed")
	push_key(KEY_J)
	await frames(2)
	ck(not journal.is_open(), "D control: J closes journal")

	# --- E (п.4а): тумблер против РЕАЛЬНОГО click_move.gd, запись cfg ---
	ck(read_clickmove_cfg() == null, "E no cfg at start (clean slate)")
	esc()
	ck(sm.is_open(), "E settings opened")
	ck(sm.cm_row.visible and sm._cm_api != null, "E ClickMove row visible, api resolved", "api=%s" % str(sm._cm_api))
	ck(bool(ClickMove.is_on()), "E default on (feature default ВКЛ)")
	ck(bool(sm.cm_btn.is_pressed()) and sm.cm_btn.text == "Ход по правому клику — вкл", "E button state reflects on", sm.cm_btn.text)
	sm.cm_btn.set_pressed(false)  # реальный клик тумблера: смена состояния -> toggled
	await frames(2)
	var cfg1: Variant = read_clickmove_cfg()
	ck(typeof(cfg1) == TYPE_DICTIONARY and bool(cfg1.get("on", true)) == false, "E set_on wrote clickmove_cfg.json on=false", str(cfg1))
	ck(not bool(ClickMove.is_on()), "E ClickMove.is_on()==false after toggle")
	sm.close()
	esc()
	ck(sm.cm_row.visible and not bool(sm.cm_btn.is_pressed()) and sm.cm_btn.text == "Ход по правому клику — выкл", "E reopen shows off state", sm.cm_btn.text)
	sm.close()
	await frames(2)

	# --- F: состояние «босс мёртв, я в пещере» + золото для процесса-2 (п.1/п.4б) ---
	GameState.cave_state = 2
	GameState.boss_defeated = true
	GameState.seen_boss_intro = true
	GameState.gold = 555
	ck(GameState.save_game(), "F final save written (boss dead, cave 2, gold 555)")
	print("R1 DONE fails=%d" % fails["n"])
	get_tree().quit(0)
