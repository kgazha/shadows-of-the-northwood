extends Node
## QA-стенд NG+ UX. ИСТОРИЯ: v1 пинил опцию Старейшины «Начать круг N»
## (ветка elder в npc.gd). v2 (g19, вердикт пользователя 16.11 22:44
## «старейшина не должен давать возможность начинать ng+») — ИНВЕРСИЯ
## матрицы: опции БОЛЬШЕ НЕТ ни у кого, и стенд пинит именно это: мёртвая
## Ведьма не рождает предложения, мир не вытирается, ng.cap_seen не пишется.
## Строка «Круг N» в meta_hud остаётся витриной счётчика (механика счёта
## жива, входа в неё нет); сами формулы/вайпы start_ng_plus пинит qa_ng.

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

	# --- 4) g19 ИНВЕРСИЯ: мёртвая Ведьма, волна 0 — Старейшина молчит про
	# круги: обычный разговор (elder_after «Ступай»), мир не вытерт, счётчик цел ---
	elder.try_interact()
	var txt := _all_text()
	ck("g19_no_offer_plain", bool(h.is_dialog_open()) and txt.contains("Ступай") \
		and not txt.contains("Круг Пепла") and not txt.contains("Станешь угольком"), txt)
	_close_dialog()
	ck("g19_wave_stays_0", GameState.ng_wave() == 0)
	ck("g19_no_wipe_by_talk", GameState.elder_quest == 2 and GameState.cave_state == 4 \
		and not GameState.campfires_used.is_empty() and GameState.in_cave \
		and String(GameState.flags.get("ashen.boss", "")) == "dead" \
		and GameState.flags.has("ng.boss_0"),
		"прогресс круга/флаги ведьмы не вытерты разговором (вайп умеет только start_ng_plus, входа нет)")
	ck("g19_cap_seen_never_written", not GameState.flags.has("ng.cap_seen"))
	ck("g19_dialog_unlocked", not bool(h.is_dialog_open()) and not GameState.input_locked)

	# --- 5) meta_hud — витрина счётчика цела: волну ставим вручную (входа в
	# прибавку нет, дисплейная логика прежняя) ---
	GameState.flags["ng.wave"] = 1
	mh.call("_update")
	ck("hud_ng_shown_w1", bool(ng_lbl.visible) and String(ng_lbl.text) == "Круг 1", \
		String(ng_lbl.text))

	# --- 6) кап-волна + мёртвая Ведьма: cap-реплики «Финальный круг» и
	# предложения нет; первая беседа = вариант 5-й волны (TEXT-AUDIT B7) ---
	GameState.flags["ng.wave"] = 5
	GameState.flags["ashen.boss"] = "dead"
	GameState.elder_quest = 2  # обычный разговор = elder_after
	mh.call("_update")
	ck("hud_ng_shown_w5", bool(ng_lbl.visible) and String(ng_lbl.text) == "Круг 5", \
		String(ng_lbl.text))
	elder.try_interact()
	var txt2 := _all_text()
	ck("g19_no_cap_line", not txt2.contains("Финальный круг") \
		and not txt2.contains("Станешь угольком") and not txt2.contains("Круг 6"), txt2)
	# Канон 2dcbb05: ПЕРВАЯ беседа на волне 5 — однократный elder_after_5
	# («Пятая свеча»). Крутим advance ПОКА не увидим вариант: закрытие строки
	# синхронно открывает следующую (advance в typing досматривает строку).
	var guard := 0
	while h.is_dialog_open() and not _all_text().contains("Пятая свеча") and guard < 60:
		h.advance()
		guard += 1
	ck("wave5_variant_direct", bool(h.is_dialog_open()) and _all_text().contains("Пятая свеча"), \
		_all_text())
	_close_dialog()
	ck("cap_wave_stays_5", GameState.ng_wave() == 5 \
		and not GameState.flags.has("ng.cap_seen"), "кап-реплика не писалась")

	# --- 7) повторная беседа: обычный elder_after, NG+-реплик нет вообще ---
	elder.try_interact()
	ck("plain_repeat", bool(h.is_dialog_open()) and _all_text().contains("Ступай") \
		and not _all_text().contains("Финальный круг") \
		and not _all_text().contains("Круг Пепла"), _all_text())
	_close_dialog()

	# --- 8) чужие NPC не затронуты: у торговца нет NG+ реплик (на волне 5!) ---
	merchant.try_interact()
	ck("merchant_unaffected", bool(h.is_dialog_open()) and not _all_text().contains("Круг") \
		and not _all_text().contains("круг"), _all_text())
	_close_dialog()

	# --- 9) волна 2, ведьма ЖИВА: Старейшина ordinary (как и с мёртвой — g19)
	# (§6 оставил ashen.boss="dead" — стираем ключ: стенд проверяет и этот срез)
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
