extends Node
## g20a QA-стенд «Инвентарь» (вердикт пользователя 17.11 ~10:00, INVENTORY.md,
## поставка А t62). Методология qa_ib: живой main.tscn + РЕАЛЬНЫЙ ввод через
## get_tree().root.push_input (тот же путь события, что у настоящей клавиатуры).
##
## Пины вердикта:
##  N0 структура: окно/сетка 6×2/12 ячеек, заголовок «Инвентарь»;
##  N1 открытие/закрытие I и ESC, ввод движения заморожен (lock), после
##     закрытия — свободен; пустой инвентарь = пустые ячейки;
##  N2 «скиллы с хотбара живут»: скилл и Q-зелье работают под НАШИМ локом,
##     хотбар не гаснет; чужой lock (диалог) — по-прежнему мёртв (qa_ib B-03
##     остаётся зелёным);
##  N3 стопки: +99 карается 99; «шкура/жила — дроп мобов всегда»;
##  N4 крафт на количества: списывается нужное, cost_text «N/M»;
##  N5 хотбар зеркалит инвентарь (общие источники истины, Use тратит из сетки);
##  N6 сейв v4 ("inv") + миграция старых v≤3 без потерь + адверсариал;
##  N7 взаимные гейты окон (лавка/журнал) и смерть-закрывание.

const MAIN_SCENE := "res://scenes/main.tscn"
const Alch := preload("res://scripts/alchemy.gd")
const SAVE := "user://save_morkheim.json"

var passes := 0
var fails := 0
var world: Node = null
var hud = null
var player: Node = null
var invn = null

func _ready() -> void:
	_wipe_saves()
	await _boot()
	if world == null or hud == null or player == null or invn == null:
		print("QA INV: БОТ НЕ ЗАПУСТИЛСЯ — стенд не может ничего проверить")
		print("QA_INV_RESULT %d/%d fails=%s" % [passes, passes + fails, "boot"])
		get_tree().quit(1)
		return
	await _n0_structure()
	await _n1_open_close()
	await _n2_hotbar_alive()
	await _n3_stacks_and_drop()
	await _n4_craft_counts()
	await _n5_hotbar_mirror()
	await _n6_save_v4_migration()
	await _n7_window_gates()
	print("QA INV: %d проверок" % (passes + fails))
	print("QA_INV_RESULT %d/%d fails=%s" % [passes, passes + fails, "none" if fails == 0 else "see above"])
	get_tree().quit(0 if fails == 0 else 1)

# ---------------- инфраструктура (паттерн qa_ib) ----------------

func _wipe_saves() -> void:
	var da := DirAccess.open("user://")
	if da != null:
		for f: String in da.get_files():
			if f.ends_with(".json"):
				da.remove(f)

func _step() -> void:
	await get_tree().physics_frame

func _fr(n: int) -> void:
	for i: int in n:
		await _step()

func _check(ok: bool, what: String) -> bool:
	if ok:
		passes += 1
	else:
		fails += 1
	print("  [%s] %s" % ["OK" if ok else "FAIL", what])
	return ok

func _note(what: String) -> void:
	print("  [NOTE] " + what)

func _descendants(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func _key(code: Key) -> void:
	var d := InputEventKey.new()
	d.keycode = code
	d.physical_keycode = code
	d.pressed = true
	get_tree().root.push_input(d)
	var u := InputEventKey.new()
	u.keycode = code
	u.physical_keycode = code
	u.pressed = false
	get_tree().root.push_input(u)

func _close_dialog(max_steps: int) -> bool:
	for i: int in max_steps:
		if not hud.is_dialog_open():
			return true
		hud.advance()
		await _fr(1)
	return not hud.is_dialog_open()

func _boot() -> void:
	var inst: Node = load(MAIN_SCENE).instantiate()
	add_child(inst)
	await _fr(12)
	for n in _descendants(get_tree().current_scene):
		if world == null and n.has_method("drink_potion") and n.get("player") != null:
			world = n
		if player == null and n.is_in_group("player"):
			player = n
	_check(world != null, "INV boot: world найден")
	_check(player != null, "INV boot: player найден")
	if world == null or player == null:
		return
	hud = world.hud
	for c in world.get_children():
		if c is Inventory:
			invn = c
	_check(invn != null, "INV boot: окно Inventory — узел world найден")
	if hud.is_modal_open():
		hud._pick_class("warrior")
	_check(not hud.is_modal_open() and GameState.class_id == "warrior",
			"INV boot: класс выбран (хотбар активен)")
	for i: int in range(60):
		if not hud.is_dialog_open():
			break
		hud.advance()
		await _fr(1)
	_check(not hud.is_dialog_open(), "INV boot: интро-диалоги пролистаны")

## Чистый инвентарь для детерминизма блоков.
func _empty_inv() -> void:
	GameState.herbs = 0
	GameState.brewed_potions = 0
	GameState.torches = 0
	GameState.materials = {"suhotsvet": 0, "zhim": 0, "smola": 0, "hide": 0, "sinew": 0}
	GameState.has_key = false
	GameState.has_amulet = false

func _cell(i: int) -> Dictionary:
	return invn.cells[i]

# ---------------- N0 структура ----------------

func _n0_structure() -> void:
	print("== N0: структура окна ==")
	_check(not Inventory.is_open(), "N0: на старте окно закрыто")
	_check(Inventory.grid_kinds().size() == 10,
			"N0: строк сетки 10 (2 зелья + факел + 5 материалов + 2 квеста) — <=12 ячеек")
	_check(invn.cells.size() == 12, "N0: ячеек ровно 12 (сетка 6×2)")
	_check(invn.grid.columns == 6, "N0: GridContainer columns == 6")
	_check(invn.head_lbl.text == "Инвентарь", "N0: заголовок «Инвентарь»")
	_check(GameState.MAT_CAP == 99, "N0: стопка материала = 99 (MAT_CAP переписан вердиктом)")
	# порядок колонок: СЕТКА СЛЕВА — HBox: grid precede hint-колонку
	var hb: Node = invn.grid.get_parent()
	var kids: Array = hb.get_children()
	_check(kids.size() >= 2 and kids[0] == invn.grid,
			"N0: сетка — первый ребёнок ряда (слева), подсказки справа")

# ---------------- N1 открытие/закрытие ----------------

func _n1_open_close() -> void:
	print("== N1: I открывает/закрывает, ESC закрывает, ввод заморожен ==")
	_empty_inv()
	GameState.hp = 5
	_key(KEY_I)
	await _fr(3)
	_check(Inventory.is_open(), "N1: I открыла окно")
	_check(GameState.input_locked, "N1: под окном input_locked (ход/кувырок/атака заморожены, как в лавке)")
	_check(invn.root.visible, "N1: корень окна виден")
	# пустой инвентарь = пустые ячейки
	var all_empty := true
	for i in 12:
		var c: Dictionary = _cell(i)
		if (c["btn"] as Button).icon != null or String((c["cnt"] as Label).text) != "":
			all_empty = false
	_check(all_empty, "N1: пустой инвентарь = пустые слоты (ни иконок, ни счётчиков)")
	_key(KEY_I)
	await _fr(3)
	_check(not Inventory.is_open() and not GameState.input_locked,
			"N1: вторичная I закрыла окно, ввод свободен")
	_key(KEY_I)
	await _fr(2)
	_key(KEY_ESCAPE)
	await _fr(3)
	_check(not Inventory.is_open(), "N1: ESC закрыл окно (и не открыл меню настроек)")
	_check(not _settings_open(), "N1: SettingsMenu под закрытием инвентаря не открылась")
	# движение заморожено доказано lock'ом; проверим, что мир жив (бой не паузится):
	_key(KEY_I)
	await _fr(2)
	_check(Inventory.is_open(), "N1: контроль — окно снова открыто")
	_key(KEY_I)
	await _fr(2)

func _settings_open() -> bool:
	for c in world.get_children():
		if c is SettingsMenu and c.is_open():
			return true
	return false

# ---------------- N2 хотбар живёт под окном ----------------

func _n2_hotbar_alive() -> void:
	print("== N2: скиллы и зелья живут при открытом окне ==")
	_empty_inv()
	GameState.level = 5
	GameState.mana = GameState.max_mana
	GameState.hp = mini(GameState.max_hp - 4, GameState.hp)
	for i in 4:
		player.skill_cd[i] = 0.0
	Inventory.open()
	await _fr(2)
	_check(Inventory.is_open() and GameState.input_locked, "N2: контроль — окно открыто, lock держится")
	_check(hud.skill_panel.visible and hud.potion_btn.visible,
			"N2: хотбар (панель скиллов + Q-кнопка) под окном НЕ гаснет")
	# скилл 2 (whirlwind — без цели: power_strike без цели отказывает by design,
	# для теста живости нужен скилл, который проходит все внутренние гейты)
	GameState.recalc_max_mana()
	GameState.mana = GameState.max_mana
	_key(KEY_2)
	await _fr(2)
	_check(float(player.skill_cd[1]) > 0.0,
			"N2: скилл с хотбара живёт: KEY_2 под НАШИМ локом ушёл в кд (%.1f)" % float(player.skill_cd[1]))
	# Q-зелье из-под окна
	GameState.herbs = 1
	var hp0 := GameState.hp
	_key(KEY_Q)
	await _fr(2)
	_check(GameState.herbs == 0 and GameState.hp > hp0,
			"N2: Q-зелье живёт: травы %d, hp %d->%d" % [GameState.herbs, hp0, GameState.hp])
	# движение: WASD не двигает (тот же input_locked, что гейтит ход в player.gd)
	var pos0: Vector2 = player.global_position
	_key(KEY_D)
	await _fr(6)
	_check(player.global_position.distance_to(pos0) < 0.5,
			"N2: движение заморожено под окном (D не сдвинул героя)")
	Inventory.close()
	await _fr(2)
	# контроль отрицания: диалог (ЧУЖОЙ lock) скилл глушит — qa_ib B-03 дублирует
	hud.show_dialog([{"who": "narr", "text": "Гейт-проверка."}], Callable())
	await _fr(3)
	var cd1 := float(player.skill_cd[1])
	player.skill_cd[1] = 0.0
	GameState.mana = GameState.max_mana
	_key(KEY_2)
	await _fr(2)
	_check(float(player.skill_cd[1]) == 0.0, "N2: чужой lock (диалог) скилл НЕ будит (отказ не случайность)")
	player.skill_cd[1] = cd1
	var _d := await _close_dialog(20)
	await _fr(2)

# ---------------- N3 стопки и всегдашний дроп ----------------

func _n3_stacks_and_drop() -> void:
	print("== N3: стопка 99, шкура/жила — дроп всегда ==")
	_empty_inv()
	for i in 120:
		GameState.add_material("hide")
	var capped: int = GameState.mat_count("hide")
	_check(capped == 99, "N3: 120 попыток add_material -> стопка карается 99 (есть %d)" % capped)
	_check(not GameState.add_material("hide"), "N3: 100-й в полный — отказ")
	# всегдашний дроп: chance 1.0 строки LOOT
	GameState.materials = {"suhotsvet": 0, "zhim": 0, "smola": 0, "hide": 0, "sinew": 0}
	Loot.on_mob_death("slime", Vector2.ZERO)
	_check(GameState.mat_count("hide") == 1, "N3: слизень всегда капает шкуру (+1 hide)")
	Loot.on_mob_death("brute_t2", Vector2.ZERO)
	_check(GameState.mat_count("sinew") == 1, "N3: брут всегда капает жилу (+1 sinew)")
	Loot.on_mob_death("boss2", Vector2.ZERO)
	_check(GameState.mat_count("hide") == 3 and GameState.mat_count("sinew") == 3,
			"N3: ведьма — обе стопки по +2 (qty строк таблицы)")
	# переполнение при дропе не роняет и не растит стопку за кап
	GameState.materials["sinew"] = 99
	Loot.on_mob_death("slime", Vector2.ZERO)
	_check(GameState.mat_count("sinew") == 99, "N3: дроп в полную стопку остаётся 99")

# ---------------- N4 крафт на количества ----------------

func _n4_craft_counts() -> void:
	print("== N4: рецепты N/M — списывается нужное ==")
	_empty_inv()
	GameState.materials["suhotsvet"] = 5
	GameState.materials["zhim"] = 2
	GameState.brewed_potions = 0
	# thorn_tonic: 2 сухоцвета из 5 — спишется ровно 2, а не «всё/есть-нет»
	_check(Alch.brew("thorn_tonic"), "N4: тоник сварился (стоимость 2/5 — по количества)")
	_check(GameState.mat_count("suhotsvet") == 3,
			"N4: списано РОВНО нужное: 5-2=3 (остаток %d)" % GameState.mat_count("suhotsvet"))
	# cost_text теперь «есть/нужно»
	var ct := Alch.cost_text("thorn_tonic")
	_check(ct.contains("3/2"), "N4: cost_text показывает N/M (%s)" % ct)
	# strong_potion: 1+1; варим до капа 2 — затем отказ «пояс полон»
	_check(Alch.brew("strong_potion") and Alch.brew("strong_potion"), "N4: две варки крепкого")
	_check(GameState.brewed_potions == GameState.BREWED_CAP and not Alch.brew("strong_potion"),
			"N4: кап крепких цел (BREWED_CAP=%d), переполнение отбито" % GameState.BREWED_CAP)
	_check(GameState.mat_count("suhotsvet") == 1 and GameState.mat_count("zhim") == 0,
			"N4: после двух варок материалы %d/%d (списание по 1+1)" % [GameState.mat_count("suhotsvet"), GameState.mat_count("zhim")])

# ---------------- N5 хотбар зеркалит инвентарь ----------------

func _n5_hotbar_mirror() -> void:
	print("== N5: сетка = источники истины хотбара ==")
	_empty_inv()
	GameState.herbs = 7
	GameState.torches = 2
	GameState.has_key = true
	hud.refresh()
	Inventory.open()
	await _fr(2)
	var c0: Dictionary = _cell(0)
	var c2: Dictionary = _cell(2)
	var c8: Dictionary = _cell(8)
	_check((c0["btn"] as Button).icon != null and String((c0["cnt"] as Label).text) == "7",
			"N5: 7 трав -> ячейка 0 иконка + счётчик «7»")
	_check(String((c2["cnt"] as Label).text) == "2", "N5: 2 факела -> ячейка 2 «2»")
	_check(String((c8["cnt"] as Label).text) == "1", "N5: ключ пещеры -> ячейка 8 «1»")
	_check(hud.potion_btn.text == "x7", "N5: хотбар-кнопка зеркалит те же 7 («%s»)" % hud.potion_btn.text)
	# клик по ячейке зелья = Use тратит из инвентаря (общий источник)
	GameState.hp = mini(GameState.max_hp - 5, GameState.hp)
	invn._on_cell_pressed(0)
	await _fr(2)
	_check(GameState.herbs == 6, "N5: клик по ячейке зелья истратил траву из инвентаря (%d)" % GameState.herbs)
	await _fr(2)  # кадр живой сетки
	_check(String((c0["cnt"] as Label).text) == "6", "N5: сетка обновилась живьём («6»)")
	# подбор в открытом окне (бой не паузится): летит в тот же источник
	GameState.herbs += 3
	await _fr(2)
	_check(String((c0["cnt"] as Label).text) == "9", "N5: подбор при открытом окне виден сразу («9»)")
	Inventory.close()
	await _fr(2)

# ---------------- N6 сейв v4 + миграция ----------------

func _write_save(d: Dictionary) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))

func _read_save() -> Dictionary:
	var f := FileAccess.open(SAVE, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _n6_save_v4_migration() -> void:
	print("== N6: сейв v4 (inv) и миграция старых без потерь ==")
	# --- старым v3-сейвом: каждый предмет игрока попадает в сетку ---
	var v3 := {
		"v": 3, "class_id": "warrior", "level": 3, "seen_intro": true,
		"herbs": 4, "materials": {"suhotsvet": 2, "zhim": 1, "smola": 3},
		"brewed": 2, "torches": 2,
		"has_key": true, "has_amulet": true, "cave_state": 3,
	}
	_write_save(v3)
	_empty_inv()
	_check(GameState.load_game(), "N6: v3-сейв прочитан")
	_check(GameState.herbs == 4 and GameState.mat_count("suhotsvet") == 2 \
			and GameState.mat_count("zhim") == 1 and GameState.mat_count("smola") == 3 \
			and GameState.brewed_potions == 2 and GameState.torches == 2,
			"N6: миграция v3→v4 без потерь: все старые предметы в сетке")
	_check(GameState.has_key and GameState.has_amulet, "N6: квестовые ключ/амулет целы")
	var d4 := GameState.to_dict()
	_check(int(d4.get("v", 0)) == 4, "N6: to_dict пишет v4")
	var iv: Variant = d4.get("inv", {})
	_check(typeof(iv) == TYPE_DICTIONARY and not (iv as Dictionary).is_empty(),
			"N6: ветки предметов живут в inv (v4)")
	_check(not d4.has("herbs") and not d4.has("materials") and not d4.has("brewed") \
			and not d4.has("torches"),
			"N6: старые top-level ключей предметов в v4 больше нет (один контейнер)")
	var matd: Variant = (iv as Dictionary).get("mat", {})
	_check(typeof(matd) == TYPE_DICTIONARY and str(matd).contains("hide") \
			and str(matd).contains("sinew"),
			"N6: inv.mat несёт все пять материалов (включая hide/sinew)")
	_check(GameState.save_game(), "N6: v4 записан")
	# --- круг v4: hide переживает save/load (стопка — часть сейва) ---
	GameState.materials["hide"] = 41
	GameState.save_game()
	GameState.materials["hide"] = 0
	_check(GameState.load_game() and GameState.mat_count("hide") == 41,
			"N6: стопка hide=41 переживает v4 roundtrip")
	# --- идемпотентность: повторная загрузка v4 не двигает числа ---
	var br0 := GameState.brewed_potions
	var he0 := GameState.herbs
	_check(GameState.load_game() and GameState.brewed_potions == br0 and GameState.herbs == he0,
			"N6: v4 грузится идемпотентно (g19-токены не конфликтуют: load_game отработал)")
	# --- g19-совместимость: load_game по-прежнему мигрирует proc-токены ---
	var v3g := {
		"v": 3, "class_id": "warrior", "level": 3, "seen_intro": true,
		"herbs": 1, "flags": {"meta.mb.boar_fang": 2, "meta.mb.twisted_arrow": 1},
	}
	_write_save(v3g)
	_check(GameState.load_game() and GameState.tal_rank("boar_fang") == 2 \
			and GameState.tal_rank("twisted_arrow") == 0 \
			and not GameState.flags.has("meta.mb.boar_fang"),
			"N6: g19-миграция proc-токенов жива рядом с inv (воин: boar=2, arrow=0)")
	# --- адверсариал: мусор в inv не роняет и не лезет за кап ---
	_write_save({"v": 4, "class_id": "warrior", "level": 2, "seen_intro": true,
			"inv": {"herb": "abc", "brewed": -3, "torch": 500.0,
					"mat": {"hide": -5, "sinew": 500, "suhotsvet": 7.0}}})
	_check(GameState.load_game() and GameState.herbs == 0 and GameState.brewed_potions == 0 \
			and GameState.torches == 99 and GameState.mat_count("hide") == 0 \
			and GameState.mat_count("sinew") == 99 and GameState.mat_count("suhotsvet") == 7,
			"N6: мусор в inv резолвится нулём, стопки клампятся 0..99")
	_wipe_saves()

# ---------------- N7 взаимные гейты окон ----------------

func _n7_window_gates() -> void:
	print("== N7: окна не толкаются локтями ==")
	_empty_inv()
	var jr = null
	for c in world.get_children():
		if c is Journal:
			jr = c
	_check(jr != null, "N7: журнал найден (узел world)")
	Inventory.open()
	await _fr(2)
	Shop.open()
	_check(not Shop.is_open(), "N7: лавка не открывается поверх инвентаря (lock)")
	jr.open()
	# журнал немодальный: под чужим локом его снимает его же _process (TICK) —
	# ждём с запасом (0.7 c), «закрыт» пинтуем по факту
	await _fr(45)
	_check(not jr.is_open(), "N7: журнал под локом инвентаря сам погас (немодалный гейт)")
	Inventory.close()
	await _fr(2)
	Shop.open()
	await _fr(2)
	_check(Shop.is_open(), "N7: контроль — лавка открылась (свободно)")
	Inventory.open()
	_check(not Inventory.is_open(), "N7: инвентарь не открывается под лавкой")
	Shop.close()
	await _fr(2)
	# смерть закрывает окно (семантика B-02: не прятать диалог под вуалем)
	Inventory.open()
	await _fr(2)
	world.on_player_death()
	await _fr(3)
	_check(not Inventory.is_open(), "N7: смерть закрыла инвентарь (диалог смерти не под вуалем)")
	var closed := await _close_dialog(30)
	_check(closed, "N7: диалог смерти пролистнут (далее — экран итогов, его не трогаем)")
	await _fr(3)
	_check(not Inventory.is_open() and not Shop.is_open() and not jr.is_open(),
			"N7: стенд закрыт без висящих окон игры")
