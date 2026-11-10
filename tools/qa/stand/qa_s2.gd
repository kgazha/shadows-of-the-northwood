extends Node
## QA-харнесс s2: SettingsMenu (Esc-матрица vs Journal/Shop/диалог, модалка,
## слайдеры громкости + персист без рестарта, ClickMove-контракт), + shop-модалка.

var world: Node2D
var sm   # SettingsMenu (может пересоздаваться)
var shop: Shop
var journal  # Journal
var hud
var fails := {"n": 0}
var toasts: Array = []

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

func close_dialog() -> void:
	var guard := 0
	while hud.is_dialog_open() and guard < 20:
		guard += 1
		hud.advance()

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://audio_cfg.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://clickmove_cfg.json"))
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
	hud = world.get("hud")
	print("NOTE nodes: sm=%s journal=%s shop=%s hud=%s" % [sm != null, journal != null, shop != null, hud != null])
	_run()

func _run() -> void:
	await frames(3)

	# --- A: стартовое состояние ---
	ck(sm != null and journal != null and shop != null, "A nodes found")
	ck(not sm.is_open() and not sm.visible, "A settings hidden at start")
	ck(not shop.is_open(), "A shop hidden at start")
	ck(not journal.is_open(), "A journal hidden at start")
	ck(not GameState.input_locked, "A input unlocked")
	ck(not hud.is_dialog_open() and not hud.is_modal_open(), "A no dialog/modal")

	# --- B: Esc открытие/закрытие, лок/разлок ---
	esc()
	ck(sm.is_open() and sm.visible, "B esc opens")
	ck(GameState.input_locked, "B esc locks input")
	ck(sm.dim.mouse_filter == Control.MOUSE_FILTER_STOP, "B dim STOP when open")
	esc()
	ck(not sm.is_open(), "B esc closes")
	ck(not GameState.input_locked, "B esc unlocks")
	ck(sm.dim.mouse_filter == Control.MOUSE_FILTER_IGNORE, "B dim IGNORE when closed")

	# --- C: модалка блокирует игрока; после закрытия ход работает ---
	var p: Node2D = world.player
	var good_dir := ""
	for d in ["move_right", "move_down", "move_left", "move_up"]:
		var p0: Vector2 = p.global_position
		Input.action_press(d)
		await frames(10)
		Input.action_release(d)
		if p.global_position.distance_to(p0) > 4.0:
			good_dir = d
			break
	ck(good_dir != "", "C sanity walking works (dir=%s)" % good_dir)
	if good_dir != "":
		sm.open()
		var p1: Vector2 = p.global_position
		Input.action_press(good_dir)
		await frames(15)
		Input.action_release(good_dir)
		ck(p.global_position.distance_to(p1) < 0.5, "C modal blocks WASD", "drift=%f" % p.global_position.distance_to(p1))
		sm.close()

	# --- C2: Q/J не протекают за меню; Q после закрытия работает ---
	GameState.herbs = 3
	GameState.hp = 1
	sm.open()
	push_key(KEY_Q)
	await frames(2)
	ck(GameState.herbs == 3, "C2 Q swallowed while open", "herbs=%d" % GameState.herbs)
	push_key(KEY_J)
	await frames(2)
	ck(not journal.is_open(), "C2 J swallowed while open")
	sm.close()
	push_key(KEY_Q)
	await frames(2)
	ck(GameState.herbs == 2, "C2 Q works after close", "herbs=%d" % GameState.herbs)

	# --- D: софтлок-страховка мира vs перелок настроек ---
	sm.open()
	GameState.input_locked = false  # имитация просочившегося события, снявшего лок
	await frames(2)
	ck(GameState.input_locked, "D settings re-locks via _process")
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(300, 200)
	get_tree().root.push_input(mm)
	await frames(2)
	ck(GameState.input_locked, "D still locked after mouse motion leak")
	sm.close()
	ck(not GameState.input_locked, "D closed and unlocked")

	# --- E: диалог: поверх не открываемся, лок отдаём честно ---
	hud.show_dialog([{"who": "narr", "text": "строка1"}, {"who": "narr", "text": "строка2"}], Callable())
	ck(hud.is_dialog_open() and GameState.input_locked, "E dialog open+locked")
	esc()
	ck(not sm.is_open(), "E Esc refused over dialog")
	esc()
	ck(not sm.is_open(), "E Esc refused over dialog (2)")
	close_dialog()
	await frames(2)
	ck(not GameState.input_locked, "E dialog close unlocks")
	sm.open()
	ck(sm.is_open(), "E settings open")
	hud.show_dialog([{"who": "narr", "text": "поверх"}], Callable())
	esc()  # закрывает настройки; лок остаётся у диалога
	ck(not sm.is_open(), "E settings closed")
	ck(GameState.input_locked and hud.is_dialog_open(), "E lock stays with dialog")
	close_dialog()
	await frames(2)
	ck(not GameState.input_locked, "E fully unlocked after dialog")
	ck(not sm.is_open(), "E settings still closed")

	# --- F: Esc vs Journal (иерархия окон) ---
	journal.open()
	ck(journal.is_open(), "F journal opened")
	esc()
	ck(not journal.is_open(), "F Esc closes journal (not stolen by settings)")
	ck(not sm.is_open(), "F settings not opened over journal")
	esc()
	ck(sm.is_open(), "F Esc opens settings once journal closed")
	esc()
	ck(not sm.is_open(), "F settings closed again")
	push_key(KEY_J)
	await frames(2)
	ck(journal.is_open(), "F J opens journal")
	push_key(KEY_J)
	await frames(2)
	ck(not journal.is_open(), "F J closes journal")

	# --- G: Esc vs Shop + гейт J в лавке ---
	Shop.open()
	ck(shop.is_open(), "G shop opened")
	esc()
	ck(not Shop.is_open(), "G Esc closes shop (not stolen by settings)")
	ck(not sm.is_open(), "G settings not opened over shop")
	ck(not GameState.input_locked, "G no lock residue after shop esc")
	Shop.open()
	push_key(KEY_J)
	await frames(2)
	ck(not journal.is_open(), "G J blocked while shop open")
	Shop.close()

	# --- H: shop открыт, WASD (polling) ---
	if good_dir != "":
		Shop.open()
		var ph: Vector2 = p.global_position
		Input.action_press(good_dir)
		await frames(15)
		Input.action_release(good_dir)
		var drift: float = p.global_position.distance_to(ph)
		if drift > 4.0:
			print("NOTE H shop does NOT block WASD movement (drift=%f): polled input, shop never sets input_locked" % drift)
		else:
			print("PASS H shop blocks movement (drift=%f)" % drift)
		Shop.close()

	# --- I: слайдеры live + персист без рестарта ---
	# 90dc4c9: шкала переехала на 0..1 шаг 0.05, page=0 (иначе Range режет max-page)
	sm.open()
	ck(absf(sm.master_slider.max_value - 1.0) < 0.001 and absf(sm.master_slider.step - 0.05) < 0.0001 \
		and absf(sm.master_slider.page) < 0.0001, "I slider scale 0..1 step .05 page 0", \
		"max=%f step=%f page=%f" % [sm.master_slider.max_value, sm.master_slider.step, sm.master_slider.page])
	# ed3c444: экран «Управление» — двухколоночная шпаргалка из CONTROLS_TABLE.
	# ct_col = [заголовок, ct_box]; сами 11 строк живут во вложенном ct_box.
	var ct_rows := 0
	if sm.ct_col != null:
		for ch in sm.ct_col.get_children():
			if ch is BoxContainer:
				ct_rows += ch.get_child_count()
	ck(SettingsMenu.CONTROLS_TABLE.size() == 11 and sm.ct_col != null \
		and ct_rows >= 11, "I controls table 11 rows rendered", \
		"table=%d rows=%d" % [SettingsMenu.CONTROLS_TABLE.size(), ct_rows])
	sm.mus_slider.value = 0.3
	sm.sfx_slider.value = 0.0
	sm._save_now()  # эмуляция отпускания слайдера: IO по design — только drag_ended
	await frames(2)
	ck(absf(GameAudio.I.music_vol - 0.3) < 0.001, "I music_vol=0.3", "got %f" % GameAudio.I.music_vol)
	ck(absf(GameAudio.I.sfx_vol - 0.0) < 0.001, "I sfx_vol=0.0", "got %f" % GameAudio.I.sfx_vol)
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	ck(mi >= 0 and absf(AudioServer.get_bus_volume_db(mi) - linear_to_db(0.3)) < 0.01, "I Music bus db", "idx=%d" % mi)
	ck(si >= 0 and AudioServer.is_bus_mute(si), "I SFX bus muted at 0")
	ck(sm.mus_pct.text == "30%" and sm.sfx_pct.text == "0%", "I pct labels", "%s/%s" % [sm.mus_pct.text, sm.sfx_pct.text])
	var fc := FileAccess.open("user://audio_cfg.json", FileAccess.READ)
	var cfg_txt := ""
	if fc != null:
		cfg_txt = fc.get_as_text()
		fc.close()
	ck(cfg_txt.find("0.3") >= 0, "I audio_cfg.json written", cfg_txt)
	sm.close()
	# открытие не должно писать cfg «на ровном месте»
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://audio_cfg.json"))
	sm.open()
	await frames(2)
	ck(not FileAccess.file_exists("user://audio_cfg.json"), "I open does not write cfg on idle")
	ck(absf(sm.mus_slider.value - 0.3) < 0.01 and absf(sm.sfx_slider.value) < 0.01, "I sliders init from GameAudio", "mus=%f sfx=%f" % [sm.mus_slider.value, sm.sfx_slider.value])
	sm._save_now()  # восстановить cfg для теста рестарта (IO только здесь)
	sm.close()
	# персист без рестарта процесса: убить GameAudio, создать новый
	var old_ga: Node = null
	for c in world.get_children():
		if c is GameAudio:
			old_ga = c
			break
	if old_ga != null:
		world.remove_child(old_ga)
		old_ga.free()
	await frames(2)
	var ga2 := GameAudio.new()
	world.add_child(ga2)
	await frames(2)
	ck(absf(GameAudio.I.music_vol - 0.3) < 0.001 and absf(GameAudio.I.sfx_vol - 0.0) < 0.001, "I volumes survive audio-node restart", "m=%f s=%f" % [GameAudio.I.music_vol, GameAudio.I.sfx_vol])
	sm.open()
	ck(absf(sm.mus_slider.value - 0.3) < 0.01, "I sliders sync with restarted audio")
	sm._on_reset()
	await frames(2)
	ck(absf(GameAudio.I.music_vol - GameAudio.DEF_VOL) < 0.001, "I reset restores DEF_VOL", "got %f" % GameAudio.I.music_vol)
	sm.close()

	# --- J: ClickMove ЖИВОЙ (click_move.gd в сборке) -> строка видна, дефолт ВКЛ ---
	# (HEAD 75b5b69+: фича реальная, стаб больше не нужен; cfg удалён в _ready -> дефолт on)
	var cm_node: Node = ClickMove.I
	ck(cm_node != null and is_instance_valid(cm_node), "J world instantiated ClickMove")
	sm.open()
	ck(sm.cm_row.visible and sm._cm_api != null, "J ClickMove row visible, api resolved", "api=%s" % str(sm._cm_api))
	ck(bool(ClickMove.is_on()), "J default on (no cfg)")
	ck(bool(sm.cm_btn.is_pressed()) and sm.cm_btn.text == "Ход по правому клику — вкл", "J button reflects on", sm.cm_btn.text)
	sm.close()

	# --- K: живой контракт — тумблер пишет cfg, перезакрытие перечитывает; free-lok ---
	sm.open()
	sm.cm_btn.set_pressed(false)  # реальный клик тумблера: смена состояния -> toggled -> set_on
	await frames(2)
	var cfg: Variant = null
	if FileAccess.file_exists("user://clickmove_cfg.json"):
		var fc2 := FileAccess.open("user://clickmove_cfg.json", FileAccess.READ)
		cfg = JSON.parse_string(fc2.get_as_text())
		fc2.close()
	ck(typeof(cfg) == TYPE_DICTIONARY and bool(cfg.get("on", true)) == false, "K set_on wrote clickmove_cfg.json on=false", str(cfg))
	ck(not bool(ClickMove.is_on()), "K is_on false after toggle")
	sm.close()
	sm.open()
	ck(not bool(sm.cm_btn.is_pressed()) and sm.cm_btn.text == "Ход по правому клику — выкл", "K reopen re-reads off state", sm.cm_btn.text)
	sm.cm_btn.set_pressed(true)
	await frames(2)
	ck(bool(ClickMove.is_on()), "K toggle back on")
	sm.close()
	# free открытого меню обязан вернуть лок
	sm.open()
	ck(GameState.input_locked, "K open locked before free")
	sm.queue_free()
	sm = null
	await frames(3)
	ck(not GameState.input_locked, "K free while open releases lock")

	print("S2 DONE fails=%d" % fails["n"])
	get_tree().quit(0)
