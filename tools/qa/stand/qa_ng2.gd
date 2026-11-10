extends Node
## QA-стенд NG+ UX (P2): опция Старейшины «Начать круг N» (ветка elder в npc.gd)
## и строка «Круг N» в meta_hud.gd. В сдачу (sand_ng2.diff) НЕ входит.

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
	print("QA_NG2_CHECK %s %s %s" % [cname, "PASS" if cond else "FAIL", note])

func _del_save() -> void:
	var da := DirAccess.open("user://")
	if da != null and da.file_exists("save_morkheim.json"):
		da.remove("save_morkheim.json")

func _find_script(root: Node, path_part: String, member := "", want := ""):
	var s = root.get_script()
	if s != null and String(s.resource_path).contains(path_part):
		if member == "" or String(root.get(member)) == want:
			return root
	for c in root.get_children():
		var r = _find_script(c, path_part, member, want)
		if r != null:
			return r
	return null

func _hud():
	return world_node.get("hud")

func _all_text() -> String:
	var out := ""
	for ln in _hud().lines:
		out += String(ln.get("text", "")) + "|"
	return out

func _close_dialog() -> void:
	var h = _hud()
	var guard := 0
	while h.is_dialog_open() and guard < 60:
		h.advance()
		guard += 1

func _ready() -> void:
	print("QA_NG2_BEGIN")
	_del_save()
	# молалку выбора класса и интро-диалог на старте не зовём (иначе висят поверх)
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	world_node = load("res://scenes/main.tscn").instantiate()
	add_child(world_node)
	await get_tree().process_frame
	var h = _hud()
	ck("world_boots", world_node != null and h != null)

	# На сигнале ДВА легитимных коннекта (с rebase на cad57bb/f0d9450):
	# Achv._on_ng_plus (ачивки NG+ снимаются до перезагрузки) и world-лямбда
	# reload_current_scene. Снимаем оба: reload убил бы стенд на середине
	# матрицы, а Achv-прирост Пепла здесь — шум (meta.ash держим fixture'ом).
	var conns: Array = GameState.get_signal_connection_list("ng_plus_started")
	ck("world_reload_hook_connected", conns.size() == 2, "count=%d (Achv+world)" % conns.size())
	for c in conns:
		GameState.ng_plus_started.disconnect(c["callable"])

	var elder = _find_script(world_node, "npc.gd", "npc_id", "elder")
	var merchant = _find_script(world_node, "npc.gd", "npc_id", "merchant")
	var mh = _find_script(world_node, "meta_hud")
	ck("elder_found", elder != null)
	ck("merchant_found", merchant != null)
	ck("meta_hud_found", mh != null)
	if elder == null or merchant == null or mh == null:
		print("QA_NG2_RESULT %d/%d fails=%s" % [_p, _p + _f, str(_fails)])
		get_tree().quit(1)
		return

	# --- 1) meta_hud: волна 0 — строки «Круг» нет ---
	mh.call("_update")
	var ng_lbl = mh.get("_ng_lbl")
	ck("hud_ng_hidden_w0", not bool(ng_lbl.visible), "wave=%d" % GameState.ng_wave())

	# --- 2) волна 0, ведьма жива: обычный разговор, NG+ опции нет ---
	elder.try_interact()
	ck("w0_plain_dialog", bool(h.is_dialog_open()) and not _all_text().contains("Круг"), \
		_all_text())
	_close_dialog()
	ck("w0_dialog_closed", not bool(h.is_dialog_open()) and not GameState.input_locked)
	ck("w0_wave_untouched", GameState.ng_wave() == 0)

	# --- 3) fixture: пройденный круг 0 (квесты, мир, мета) + мёртвая Ведьма ---
	GameState.class_id = "warrior"
	GameState.level = 3
	GameState.elder_quest = 2
	GameState.slime_quest = 2
	GameState.cave_state = 4
	GameState.chest_mark_used("chest@1,1")
	GameState.campfires_used["cf1"] = true
	GameState.materials["suhotsvet"] = 3
	GameState.brewed_potions = 2
	GameState.gold = 123
	GameState.has_amulet = true
	GameState.equip_item("weapon", "sword")
	GameState.in_cave = true
	GameState.pos_valid = true
	GameState.flags["ach.probe"] = 1
	GameState.flags["meta.ash"] = 7
	GameState.flags["daily.streak"] = 3
	GameState.flags["ng.boss_0"] = 1
	GameState.flags["q.grims"] = 1
	GameState.flags["ashen.boss"] = "dead"
	GameState.flags["ashen.chest"] = "taken"
	GameState.save_game()

	# --- 4) Старейшина предлагает круг 1; дочитывание = согласие ---
	elder.try_interact()
	var txt := _all_text()
	ck("offer_dialog_opens", bool(h.is_dialog_open()), txt)
	ck("offer_says_round1", txt.contains("Круг 1") and txt.contains("ведьмы"), txt)
	_close_dialog()
	ck("ng_started_w1", GameState.ng_wave() == 1, "wave=%d" % GameState.ng_wave())
	ck("reset_after_offer", GameState.elder_quest == 0 and GameState.slime_quest == 0 \
		and GameState.cave_state == 0 and GameState.chests_used.is_empty() \
		and GameState.campfires_used.is_empty() and not GameState.in_cave \
		and not GameState.pos_valid)
	ck("reset_ashen_q_after_offer", not GameState.flags.has("ashen.boss") \
		and not GameState.flags.has("ashen.chest") and not GameState.flags.has("q.grims"))
	# meta.ash >= 7: внутри круга Achv._check_ng/ng_second вправе докинуть Пепла
	# (cad57bb). ng.boss_0 из переноса УБРАН: 9402ee1 намеренно стирает ng.boss_*
	# (пепел босса перезарабатывается каждый круг) — отдельный reset-чек ниже.
	ck("carry_after_offer", GameState.gold == 123 and String(GameState.gear["weapon"]) == "sword" \
		and GameState.has_amulet and GameState.level == 3 \
		and int(GameState.flags.get("meta.ash", 0)) >= 7 \
		and int(GameState.flags.get("daily.streak", 0)) == 3 \
		and int(GameState.flags.get("ach.probe", 0)) == 1, \
		"ash=%s" % str(GameState.flags.get("meta.ash", -1)))
	ck("reset_ng_boss_gates_offer", not GameState.flags.has("ng.boss_0"), "P0 9402ee1")
	ck("autosave_w1_disk", GameState.load_game() and GameState.ng_wave() == 1)
	ck("dialog_unlocked", not bool(h.is_dialog_open()) and not GameState.input_locked)

	# --- 5) meta_hud: волна 1 — «Круг 1» виден ---
	mh.call("_update")
	ck("hud_ng_shown_w1", bool(ng_lbl.visible) and String(ng_lbl.text) == "Круг 1", \
		String(ng_lbl.text))

	# --- 6) кап: волна 5 + ведьма мертва — финальная реплика без действия ---
	GameState.flags["ng.wave"] = 5
	GameState.flags["ashen.boss"] = "dead"
	GameState.elder_quest = 2  # чтобы обычный разговор после кап-реплики = elder_after
	mh.call("_update")
	ck("hud_ng_shown_w5", bool(ng_lbl.visible) and String(ng_lbl.text) == "Круг 5", \
		String(ng_lbl.text))
	elder.try_interact()
	var txt2 := _all_text()
	ck("cap_final_line", txt2.contains("Финальный круг пройден") and not txt2.contains("Круг 6"), \
		txt2)
	# Колбэк капа — обычный разговор (elder_after, «Ступай»). Крутим advance
	# ПОКА не увидим реплику elder_after: закрытие кап-реплики синхронно
	# открывает следующую (say() не даёт typing'у дотикать — advance в typing
	# просто досматривает строку), цикл _close_dialog'а проглотил бы её целиком.
	var guard := 0
	while h.is_dialog_open() and not _all_text().contains("Ступай") and guard < 60:
		h.advance()
		guard += 1
	ck("cap_then_plain", bool(h.is_dialog_open()) and _all_text().contains("Ступай"), \
		_all_text())
	_close_dialog()
	ck("cap_wave_stays_5", GameState.ng_wave() == 5 and \
		int(GameState.flags.get("ng.cap_seen", -1)) == 5)

	# --- 7) кап повтор: финальная реплика уже не показывается ---
	elder.try_interact()
	ck("cap_shown_once", bool(h.is_dialog_open()) and _all_text().contains("Ступай") \
		and not _all_text().contains("Финальный круг"), _all_text())
	_close_dialog()

	# --- 8) чужие NPC не затронуты: у торговца нет NG+ реплик (на волне 5!) ---
	merchant.try_interact()
	ck("merchant_unaffected", bool(h.is_dialog_open()) and not _all_text().contains("Круг") \
		and not _all_text().contains("круг"), _all_text())
	_close_dialog()

	# --- 9) волна 2, ведьма ЖИВА: Старейшина снова ordinary ---
	# (§6 оставил ashen.boss="dead" — с ним матрица легитимно предлагает «Круг 3»,
	# стираем ключ, иначе стенд проверял бы не ту ветку)
	GameState.flags["ng.wave"] = 2
	GameState.flags.erase("ashen.boss")
	GameState.elder_quest = 2
	elder.try_interact()
	ck("w2_no_witch_plain", bool(h.is_dialog_open()) and not _all_text().contains("Круг"), \
		_all_text())
	_close_dialog()

	_del_save()
	print("QA_NG2_RESULT %d/%d fails=%s" % [_p, _p + _f, str(_fails)])
	get_tree().quit(0 if _f == 0 else 1)
