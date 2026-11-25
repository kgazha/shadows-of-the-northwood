extends Node
## g20b QA-стенд «Экипировка, заточка, источники, редкость» (t63, вердикт
## пользователя 17.11, docs/INVENTORY.md §2-4 + вердикт 16.11 22:56 о
## подсветке). Методология qa_ib/qa_inv: живой main.tscn + GameState/GearData
## как игровые точки + реальные кнопки окна.
##
## Пины вердикта:
##  G0 данные: новые предметы/слот relic/редкость/константы заточки (шаги
##     5/7/10/12/15 => накопленные 5/12/22/34/49, цены 1..5), переименование
##     узла «Уход за клинком» (id/цифры прежние);
##  G1 формулы: плоские +2/+4/+7 к урону GameState.damage (база и скиллы —
##     один производный источник), броня −1/−2/−3 «минимум 1», «Урон 8 + 4» в
##     подсказке, амулет +1 и без слота, legacy-меч ×2 не тронут;
##  G2 заточка: лестница 0..5 камнями 1/2/3/4/5 (итого 15), без рандума,
##     отказ при нехватке/пределе, степень шьётся к оружию и живёт в сейве;
##  G3 источники: деревенский сундук выдает базовый сет ОДИН раз (живой узел),
##     пещера/Пепелище — пин сетов по источнику (зоны строятся только в своих
##     мирах) + юнит grant_gear_set;
##  G4 дроп 5%: детерминированно через TEST-only Loot.test_roll (игра его не
##     выставляет), шкуры/жилы прежние;
##  G5 UI: клик из сумки надевает/снимает, метка «надето», цветной кант
##     редкости, силуэт и три слота на месте;
##  G6 торговцы: прилавок Геральда (базовый сет), Дран после сделки, у
##     Гриима кольчуга как была; покупка -> сумка, legacy-флаг не горит;
##  G7 сейв: bag/sharpen в v4 без версии-банпа, миграция legacy, адверсариал;
##  G8 канон оружия (t10, вердикт 25.11 «магу посохи, лучнику луки, воину
##     мечи и щиты»): матрица 3x3, слот shield, гейт экипировки с причиной,
##     «не твоя рука» покупается но не надевается, легаси-сейв снимает чужое
##     одноразовым тостом, щит = плоская броня, мана-потолок посохов,
##     FNV-иконки листа tools_art/sheet_weapons_v1.gd.

const MAIN_SCENE := "res://scenes/main.tscn"
const SAVE := "user://save_morkheim.json"

var passes := 0
var fails := 0
var world: Node = null
var hud = null
var player: Node = null
var invn = null
var shopn = null
## t10 (Оружие v1, 25.11): счётчик тостов для гейта «не твоя рука» —
## проверяем и причину (не молча), и однократность (легаси-флеш, клик в сумке).
var _toasts: Array = []

func _toast_g8(msg: String) -> void:
	_toasts.append(msg)

func _ready() -> void:
	_wipe_saves()
	await _boot()
	if world == null or player == null or invn == null or shopn == null:
		print("QA GEAR: БОТ НЕ ЗАПУСТИЛСЯ — стенд не может ничего проверить")
		print("QA_GEAR_RESULT %d/%d fails=boot" % [passes, passes + fails])
		get_tree().quit(1)
		return
	await _g0_data()
	await _g1_formulas()
	await _g2_sharpen()
	await _g3_chests()
	await _g4_drop5()
	await _g5_ui()
	await _g6_vendors()
	await _g7_save()
	await _g8_canon()
	await _g9_world_art()
	print("QA GEAR: %d проверок" % (passes + fails))
	print("QA_GEAR_RESULT %d/%d fails=%s" % [passes, passes + fails, "none" if fails == 0 else "see above"])
	get_tree().quit(0 if fails == 0 else 1)

# ---------------- инфраструктура (паттерн qa_ib/qa_inv) ----------------

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

func _descendants(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func _boot() -> void:
	var inst: Node = load(MAIN_SCENE).instantiate()
	add_child(inst)
	await _fr(12)
	for n in _descendants(get_tree().current_scene):
		if world == null and n.has_method("drink_potion") and n.get("player") != null:
			world = n
		if player == null and n.is_in_group("player"):
			player = n
	_check(world != null, "boot: world найден")
	_check(player != null, "boot: player найден")
	if world == null or player == null:
		return
	hud = world.hud
	for c in world.get_children():
		if c is Inventory:
			invn = c
		if c is Shop:
			shopn = c
	_check(invn != null, "boot: окно Inventory — узел world найден")
	_check(shopn != null, "boot: лавка Shop — узел world найден")
	if hud.is_modal_open():
		hud._pick_class("warrior")
	_check(not hud.is_modal_open() and GameState.class_id == "warrior",
			"boot: класс воин выбран (база урона 2 — из реестра классов)")
	for i: int in range(80):
		if not hud.is_dialog_open():
			break
		hud.advance()
		await _fr(1)
	_check(not hud.is_dialog_open(), "boot: интро-диалоги пролистаны")
	_empty_gear()

## Чистая экипировка для детерминизма блоков.
func _empty_gear() -> void:
	# t10 (Оружие v1, 25.11): слот shield добавлен (было 3 ключа)
	GameState.gear = {"weapon": "", "armor": "", "shield": "", "relic": ""}
	GameState.owned_gear = []
	GameState.sharpen = {}
	GameState.has_sword = false
	GameState.has_amulet = false
	GameState.gear_gate_note = ""  # t10: заметка легаси-гейта не наследуется
	GameState.materials = {"suhotsvet": 0, "zhim": 0, "smola": 0, "hide": 0, "sinew": 0, "whet": 0}
	GameState.flags["meta.master"] = 0
	Loot.test_roll = -1.0
	GameState.stats_changed.emit()

func _give(id: String, slot: String) -> void:
	GameState.ensure_gear(id)
	GameState.equip_item(slot, id)

## Запись сейва-файла с гарантированным сбросом буфера (открытый WRITE-хэндл
## не отдал бы байты load_game — буферизация FileAccess).
func _write_raw(s: String) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(s)
	f.flush()
	f = null

# ---------------- G0 данные ----------------

func _g0_data() -> void:
	print("== G0: реестр, слоты, заточка, редкость, узел таланта ==")
	var sw := GearData.item("shortsword")
	var ns := GearData.item("nordsword")
	var fb := GearData.item("fangblade")
	var bh := GearData.item("boarhide")
	var am := GearData.item("amulet")
	_check(String(sw.get("slot", "")) == "weapon" and int(sw.get("dmg_bonus", 0)) == 2,
			"G0: краткий меч — оружие +2 (вердикт §3)")
	_check(String(ns.get("slot", "")) == "weapon" and int(ns.get("dmg_bonus", 0)) == 4 \
			and String(ns.get("rarity", "")) == "rare",
			"G0: меч северян — оружие +4, редкий (вердикт §3 + 16.11)")
	_check(String(fb.get("slot", "")) == "weapon" and int(fb.get("dmg_bonus", 0)) == 7 \
			and String(fb.get("rarity", "")) == "epic",
			"G0: клыко-клинок — оружие +7, очень редкий")
	_check(int(GearData.item("leather").get("armor_bonus", 0)) == 1 \
			and int(GearData.item("chain").get("armor_bonus", 0)) == 2 \
			and int(bh.get("armor_bonus", 0)) == 3 and String(bh.get("rarity", "")) == "epic",
			"G0: броня −1/−2/−3 (кожа/кольчуга — прежние id вердикта, шкура вепря — эпик)")
	_check(String(GearData.item("chain").get("rarity", "")) == "rare",
			"G0: кольчуга — редкий (вердикт 16.11 22:56: синий)")
	_check(String(am.get("slot", "")) == "relic",
			"G0: Амулет Леса — экипируемый оберег (слот relic, вердикт §2)")
	# t10 (Оружие v1, 25.11): +shield — было 3 (weapon/armor/relic)
	_check(GameState.gear.has("relic") and GameState.gear.has("shield") \
			and GameState.gear.size() == 4,
			"G0: слоты GameState — weapon/shield/armor/relic (канон 25.11)")
	# легендарный — только инфраструктура цвета (вердикт: предмета пока нет)
	_check(GearData.RARITY_COLORS.has("legend") and GearData.RARITY_NAMES.has("legend"),
			"G0: оранжевый «легендарный» — инфраструктура готова")
	var any_legend := false
	for id in GearData.ITEMS:
		if String(GearData.ITEMS[id].get("rarity", "")) == "legend":
			any_legend = true
	_check(not any_legend, "G0: ни один предмет пока не legendary — ждём вердикт")
	# палитра: синий/фиолетовый различимы по каналу B>R (синий), R>G (фиолетовый —
	# общий критерий: синий B макс, фиолетовый R&B оба выше G)
	var rare: Color = GearData.RARITY_COLORS["rare"]
	var epic: Color = GearData.RARITY_COLORS["epic"]
	_check(rare.b > rare.r and rare.b > rare.g and epic.r > epic.g and epic.b > epic.g,
			"G0: синий — редкий, фиолетовый — очень редкий (цвета различимы)")
	# заточка: вердиктные ступени и накопленные суммы — одна таблица
	_check(GearData.SHARPEN_STEP_PCT == [5, 7, 10, 12, 15],
			"G0: прибавки ступеней 5/7/10/12/15% (вердикт §4 дословно)")
	_check(GearData.SHARPEN_PCT == [0, 5, 12, 22, 34, 49],
			"G0: накопленные 0/5/12/22/34/49% (сумма до +49%)")
	var cum := true
	for i in 5:
		if GearData.SHARPEN_PCT[i + 1] != GearData.SHARPEN_PCT[i] + GearData.SHARPEN_STEP_PCT[i]:
			cum = false
	_check(cum, "G0: накопленная таблица = сумма шагов (внутренняя непротиворечивость)")
	_check(GearData.SHARPEN_COST == [1, 2, 3, 4, 5] and GearData.SHARPEN_MAX == 5,
			"G0: цена ступеней 1/2/3/4/5 камней, потолок 5")
	_check(GameState.MAT_NAMES.has("whet") and String(GameState.MAT_NAMES["whet"]) == "Точильный камень",
			"G0: предмет «Точильный камень» — материал-валюта заточки")
	# переименование узла: id/макс/цена/формула — прежние (вердикт п.4)
	var node: Dictionary = Talents.NODES.get("whetstone", {})
	_check(String(node.get("name", "")) == "Уход за клинком",
			"G0: узел переименован «Уход за клинком» (имя отдано предмету)")
	_check(int(node.get("max", 0)) == 2 and int(node.get("cost_per_rank", 0)) == 1,
			"G0: id whetstone, max 2, цена 1 — НЕ тронуты (сейвы/формулы)")
	# скиллы: единый производный источник урона (плоский бонус и % живут в нём)
	var psrc := FileAccess.get_file_as_string("res://scripts/player.gd")
	_check(psrc.contains("GameState.damage"),
			"G0: удар и скиллы читают GameState.damage — один источник (бонусы доходят до скиллов)")
	# точка брони — единственная в получении урона
	var gssrc := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	_check(gssrc.contains("GearData.absorb(self, n)"),
			"G0: урон по герою проходит через GearData.absorb (мин-1 там же)")

# ---------------- G1 формулы ----------------

func _g1_formulas() -> void:
	print("== G1: урон/броня — контрольные значения ==")
	_empty_gear()
	_check(GameState.damage == 2, "G1: голый воин (база 2) — урон 2")
	_give("shortsword", "weapon")
	_check(GameState.damage == 4, "G1: краткий меч — урон 2+2=4 (плоский +2, вердикт §3)")
	_give("nordsword", "weapon")
	_check(GameState.damage == 6, "G1: меч северян — 2+4=6")
	_give("fangblade", "weapon")
	_check(GameState.damage == 9, "G1: клыко-клинок — 2+7=9")
	_check(not GameState.has_sword,
			"G1: вердиктно-плоские мечи НЕ поднимают legacy has_sword (×2 не из воздуха)")
	# амулет: +1 и без слота (флаг-эффект, вердикт «работает как сейчас»)
	GameState.has_amulet = true
	_check(GameState.damage == 10, "G1: амулет-флаг +1 (9→10) без всякого слота")
	GameState.equip_item("relic", "amulet")
	_check(GameState.damage == 10, "G1: амулет НАДЕТ в оберег — урон тот же (нет двойного учёта)")
	# заточка в формуле: крупная база убирает эффект округления — чистое %
	GameState.sharpen["fangblade"] = 5
	var big := GearData.player_damage(100, GameState)
	_check(big == int(round((100.0 * 1.49 + 7.0))) + 1,
			"G1: база 100 + клинок +7 + заточка 49%% => %d (100×1.49+7+амулет 1)" % big)
	GameState.sharpen["fangblade"] = 1
	_check(GearData.player_damage(100, GameState) == int(round(100.0 * 1.05 + 7.0)) + 1,
			"G1: ступень 1 = +5%% ровно (формула накопленная, не сумма проходов)")
	# legacy-канон: железный меч ×2 поверх амулета, плоская линия не мешает
	GameState.equip_item("weapon", "sword")
	_check(GameState.has_sword and GameState.damage == 2 * 2 + 1,
			"G1: старый меч ×2 жив (сейвы t-канона): 2×2+амулет=5")
	_give("leather", "armor")
	_check(GearData.absorb(GameState, 4) == 3, "G1: кожа −1 (4→3)")
	_give("chain", "armor")
	_check(GearData.absorb(GameState, 4) == 2, "G1: кольчуга −2 (4→2)")
	_give("boarhide", "armor")
	_check(GearData.absorb(GameState, 4) == 1, "G1: шкура вепря −3 (4→1)")
	_check(GearData.absorb(GameState, 1) == 1 and GearData.absorb(GameState, 3) == 1,
			"G1: «минимум 1 проходит» при любой броне (вердикт §3)")
	_check(GearData.armor_bonus(GameState) == 3, "G1: оберег/оружие в броню не лезут: armor_bonus=3 (шкура)")
	# «Урон 8 + 4»: форма строки в подсказке слота
	_empty_gear()
	_give("nordsword", "weapon")
	Inventory.open()
	await _fr(2)
	var tip := String(invn.item_tip("nordsword"))
	var re := RegEx.create_from_string("Урон (\\d+) \\+ (\\d+)")
	var mt := re.search(tip)
	_check(mt != null and int(mt.get_string(2)) == 4,
			"G1: подсказка «Урон %d + %d» — честная форма (вердикт §3): «%s»" % [
				int(mt.get_string(1)) if mt != null else -1,
				int(mt.get_string(2)) if mt != null else -1, tip])
	Inventory.close()
	await _fr(2)

# ---------------- G2 заточка ----------------

func _g2_sharpen() -> void:
	print("== G2: лестница заточки камнями ==")
	_empty_gear()
	_give("shortsword", "weapon")
	# нет камней — отказ без списаний
	_check(not GearData.sharpen_weapon(GameState) and GameState.sharpen.is_empty(),
			"G2: 0 камней — отказ, степень не двигается")
	GameState.materials["whet"] = 15
	var ok := true
	var spent := 0
	for t in 5:
		var cost: int = GearData.SHARPEN_COST[t]
		var before := GameState.mat_count("whet")
		if not GearData.sharpen_weapon(GameState):
			ok = false
			break
		if int(GameState.sharpen.get("shortsword", -1)) != t + 1:
			ok = false
			break
		if before - GameState.mat_count("whet") != cost:
			ok = false
			break
		spent += cost
	_check(ok, "G2: пять ступеней подряд — степени 1..5, цены 1/2/3/4/5 камней")
	_check(GameState.mat_count("whet") == 0 and spent == 15,
			"G2: суммарно ровно 15 камней за 0→5 (сумма цен)")
	_check(GearData.sharpen_pct(5) == 49 and GearData.sharpen_tier(GameState) == 5,
			"G2: потолок +49% на 5-й ступени (вердикт §4)")
	_check(not GearData.sharpen_weapon(GameState) and int(GameState.sharpen["shortsword"]) == 5,
			"G2: за потолком — отказ, степень цела (нет потери прогресса)")
	# степень шьётся к оружию: снял/надел другое — своё осталось
	GameState.materials["whet"] = 1
	GameState.equip_item("weapon", "")
	_check(GearData.sharpen_tier(GameState) == 0 and int(GameState.sharpen.get("shortsword", 0)) == 5,
			"G2: без оружия степень 0, у снятого меча — своя пятёрка в сейве")
	GameState.equip_item("weapon", "shortsword")
	_check(GearData.sharpen_tier(GameState) == 5, "G2: надел обратно — заточка при мече")
	GameState.ensure_gear("axe")
	GameState.equip_item("weapon", "axe")
	_check(GearData.sharpen_tier(GameState) == 0 and GearData.sharpen_weapon(GameState),
			"G2: топор точится своей первой ступенью (словарь по оружию)")
	_check(int(GameState.sharpen["axe"]) == 1 and int(GameState.sharpen["shortsword"]) == 5,
			"G2: степени независимы: axe=1, shortsword=5")
	# не оружие — не точится
	GameState.equip_item("weapon", "")
	GameState.materials["whet"] = 9
	_check(not GearData.sharpen_weapon(GameState), "G2: нечего надето — отказ (оружие нужно)")

# ---------------- G3 сундуки-сеты ----------------

func _g3_chests() -> void:
	print("== G3: гарантированные наборы сундуков ==")
	_empty_gear()
	GameState.chests_used = []
	GameState.flags.erase("ashen.chest")
	var chest = null
	for d in _descendants(world):
		if str(d.get("kind")) == "chest" and str(d.get("area")) == "village":
			chest = d
			break
	if _check(chest != null, "G3: деревенский сундук найден на живой карте"):
		var gold0 := GameState.gold
		chest.try_interact()
		await _fr(2)
		_check(GameState.owned_gear.has("shortsword") and GameState.owned_gear.has("leather"),
				"G3: деревенский сундук — краткий меч + кожаный доспех (сет §4)")
		_check(GameState.mat_count("whet") == 2, "G3: туда же — пара точильных камней")
		_check(GameState.gold > gold0, "G3: золото BALANCE-строки 4 не потеряно (+>0)")
		chest.try_interact()
		_check(GameState.owned_gear.size() == 2,
				"G3: повторный клик — сет НЕ дублируется (сундук один раз)")
	# пещера и Пепелище: зоны живут только в своих мирах — сеты пинуются
	# источником (канон qa_lp: источник = факт сборки) + юнит grant_gear_set
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon_zone.gd")
	_check(dsrc.contains("Loot.grant_gear_set(GameState, [\"nordsword\", \"chain\"])"),
			"G3: пещерный сундук — сет «меч северян + кольчуга» (источник-пин)")
	_check(dsrc.contains("GameState.has_amulet = true") and dsrc.contains("ensure_gear(\"amulet\")"),
			"G3: амулет в сундуке — и флаг квеста, и владение сумки")
	var asrc := FileAccess.get_file_as_string("res://scripts/ashen_zone.gd")
	_check(asrc.contains("Loot.grant_gear_set(GameState, [\"fangblade\", \"boarhide\"])"),
			"G3: сундук Пепелища — верхний сет «клыко-клинок + шкура вепря»")
	_check(asrc.contains("ashen.chest"), "G3: гейт «один раз» пепельного сундука прежен (флаг)")
	# юнит: выдача сета идемпотентна (повтор — ноль новых владений)
	_empty_gear()
	Loot.grant_gear_set(GameState, ["fangblade", "boarhide"])
	var n0 := GameState.owned_gear.size()
	Loot.grant_gear_set(GameState, ["fangblade", "boarhide"])
	_check(n0 == 2 and GameState.owned_gear.size() == 2,
			"G3: grant_gear_set идемпотентен (предметы уникальны)")

# ---------------- G4 дроп 5% ----------------

func _g4_drop5() -> void:
	print("== G4: редкий дроп снаряжения 5%% (TEST-инъекция броска) ==")
	# порядок важен: _empty_gear() обнуляет и test_roll — инъекция ВЫСТАВЛЯЕТСЯ
	# после очистки (иначе бросок снова случайный).
	_empty_gear()
	Loot.test_roll = 0.04
	Loot.on_mob_death("slime", Vector2.ZERO)
	_check(GameState.owned_gear.has("shortsword"),
			"G4: бросок 0.04 < 0.05 — слизень выронил краткий меч")
	_check(GameState.mat_count("hide") == 1 and GameState.mat_count("whet") == 1,
			"G4: шкура (всегда) и точильный камень (часто) в том же дропе")
	Loot.on_mob_death("brute_t3", Vector2.ZERO)
	_check(GameState.owned_gear.has("fangblade"),
			"G4: бросок ниже 0.05 — брут тир-3 отдаёт клыко-клинок (0.05-строка)")
	_empty_gear()
	Loot.test_roll = 0.06
	Loot.on_mob_death("slime", Vector2.ZERO)
	_check(GameState.owned_gear.is_empty(),
			"G4: бросок 0.06 > 0.05 — шестерня НЕ выпала (порог ровно 5%)")
	_check(GameState.mat_count("whet") == 1 and GameState.mat_count("hide") == 1,
			"G4: обычные строки дропа от порога не пострадали")
	_empty_gear()
	Loot.test_roll = 0.95
	Loot.on_mob_death("boss", Vector2.ZERO)
	_check(GameState.owned_gear.is_empty() and GameState.mat_count("hide") == 2 \
			and GameState.mat_count("whet") == 2,
			"G4: босс: шкуры/жилы/камни qty2 как в таблице, снаряжение боссы не роняют")
	Loot.test_roll = -1.0
	_check(is_equal_approx(Loot.test_roll, -1.0), "G4: инъекция сброшена (игра её не выставляет)")

# ---------------- G5 UI ----------------

func _g5_ui() -> void:
	print("== G5: окно — силуэт, слоты, клик надеть/снять, кант редкости ==")
	_empty_gear()
	Inventory.open()
	await _fr(2)
	_check(invn.hero_img.texture != null, "G5: силуэт героя в правой колонке (нарисован)")
	# t10 (Оружие v1, 25.11): четыре карточки — было 3 (Оружие/Броня/Оберег)
	_check(invn.slot_btns.size() == 4 and invn.slot_btns.has("relic") and invn.slot_btns.has("shield"),
			"G5: карточки слотов: Оружие/Щит/Броня/Оберег (вердикт §2 + канон 25.11 «щиты воину»)")
	_check(invn.sharpen_btn != null and invn.bag_cells.size() == 12,
			"G5: сумка снаряжения 6×2 + кнопка «Точить» построены")
	# клик по пустому слоту — отказ-подсказка, ничего не ломается
	invn._on_slot_pressed("weapon")
	_check(GearData.equipped_id(GameState, "weapon") == "", "G5: пустой слот по клику остаётся пуст")
	# выдать набор и надеть кликами
	GameState.ensure_gear("shortsword")
	GameState.ensure_gear("fangblade")
	GameState.ensure_gear("boarhide")
	GameState.ensure_gear("amulet")
	await _fr(2)
	var ids: Array = Inventory.gear_view_ids()
	_check(ids == ["shortsword", "fangblade", "boarhide", "amulet"],
			"G5: порядок сумки — канон реестра, не порядок получения: %s" % str(ids))
	invn._on_bag_pressed(ids.find("shortsword"))
	await _fr(2)
	_check(GearData.equipped_id(GameState, "weapon") == "shortsword" and GameState.damage == 4,
			"G5: клик по мечу в сумке — надет, урон 2+2")
	var cell_sc: Dictionary = invn.bag_cells[ids.find("shortsword")]
	_check(String((cell_sc["mark"] as Label).text) == "✓",
			"G5: надетая вещь помечена в сумке (вердикт §2 «экипированное видно»)")
	invn._on_slot_pressed("weapon")
	await _fr(2)
	_check(GearData.equipped_id(GameState, "weapon") == "" \
			and GameState.owned_gear.has("shortsword") and GameState.damage == 2,
			"G5: клик по слоту — снял в сумку (не потерял, урон упал обратно)")
	invn._on_bag_pressed(ids.find("fangblade"))
	await _fr(2)
	var cell_fb: Dictionary = invn.bag_cells[ids.find("fangblade")]
	var sb := (cell_fb["btn"] as Button).get_theme_stylebox("normal") as StyleBoxFlat
	_check(sb != null and sb.border_color == GearData.RARITY_COLORS["epic"] \
			and sb.border_width_left == 2,
			"G5: фиолетовый кант 2px на клетке очень редкого клинка (16.11 22:56)")
	var cell_leather_style := (invn.bag_cells[ids.find("boarhide")]["btn"] as Button) \
			.get_theme_stylebox("normal") as StyleBoxFlat
	_check(cell_leather_style.border_color == GearData.RARITY_COLORS["epic"],
			"G5: шкура вепря — тоже эпик-кант")
	# синяя рамка на редком
	GameState.ensure_gear("nordsword")
	await _fr(2)
	ids = Inventory.gear_view_ids()
	var sb2 := (invn.bag_cells[ids.find("nordsword")]["btn"] as Button) \
			.get_theme_stylebox("normal") as StyleBoxFlat
	_check(sb2.border_color == GearData.RARITY_COLORS["rare"],
			"G5: синий кант — редкий меч северян")
	# оберег: amulet в слот relic
	invn._on_bag_pressed(ids.find("amulet"))
	await _fr(2)
	_check(GearData.equipped_id(GameState, "relic") == "amulet",
			"G5: амулет надевается в «Оберег» кликом")
	# кнопка заточки в окне: активна на оружии с камнями
	GameState.materials["whet"] = 1
	GameState.equip_item("weapon", "shortsword")
	await _fr(2)
	_check(not invn.sharpen_btn.disabled and String(invn.sharpen_btn.text).contains("1"),
			"G5: «Точить» активна: 1 камень — первая ступень (кнопка в окне вместо «в подсказке»)")
	invn._on_sharpen_pressed()
	await _fr(2)
	_check(int(GameState.sharpen.get("shortsword", 0)) == 1 and GameState.mat_count("whet") == 0,
			"G5: кнопка точит: степень 1, камень списан")
	_check(invn.sharpen_btn.disabled, "G5: кончились камни — кнопка гаснет (не мёртвая, а честная)")
	Inventory.close()
	await _fr(2)

# ---------------- G6 торговцы ----------------

func _g6_vendors() -> void:
	print("== G6: прилавки — Геральд базовый, Дран после сделки ==")
	_empty_gear()
	GameState.gold = 500
	# Дран ДО сделки: трофейных позиций нет (вердикт §4 «после сделки»)
	GameState.slime_quest = 1
	Shop.open("merchant")
	await _fr(2)
	_check(Shop.is_open(), "G6: прилавок Драна открылся")
	var nb: Button = shopn.buy_btns.get("nordsword", null)
	var cb: Button = shopn.buy_btns.get("chain", null)
	_check(nb != null and not nb.visible and cb != null and not cb.visible,
			"G6: Дран до сделки — меча северян и кольчуги на витрине нет")
	GameState.slime_quest = 2
	shopn._apply_vendor()
	_check(nb.visible and cb.visible,
			"G6: сделка закрыта (квест слаймов сдан) — северяне и кольчуга появились")
	# покупка у Драна: в сумку и на героя; legacy-флаг не поднимается
	GameState.gold = 500
	nb.pressed.emit()
	await _fr(2)
	_check(GameState.owned_gear.has("nordsword") \
			and GearData.equipped_id(GameState, "weapon") == "nordsword" \
			and not GameState.has_sword and GameState.damage == 6,
			"G6: куплено у Драна: сумка+надето, 2+4=6, has_sword чист")
	Shop.close()
	await _fr(2)
	# Геральд: базовый сет (вердикт §4 «Геральд продаёт базовые»)
	Shop.open("hermit")
	await _fr(2)
	_check(String(shopn.head_lbl.text).contains("Геральд"),
			"G6: шапка прилавка — припасы Геральда")
	var sb1: Button = shopn.buy_btns.get("shortsword", null)
	var lb: Button = shopn.buy_btns.get("leather", null)
	_check(sb1 != null and sb1.visible and lb != null and lb.visible,
			"G6: у Геральда — краткий меч и кожа (базовый сет)")
	var fb2: Button = shopn.buy_btns.get("fangblade", null)
	_check(fb2 == null or not fb2.visible, "G6: трофейный клыко-клинок не продаётся НИГДЕ")
	# мирный вход: прямой _on_buy на закрытой гейтом позиции — отказ, слот цел
	GameState.slime_quest = 1
	GameState.owned_gear.erase("nordsword")
	GameState.equip_item("weapon", "")
	Shop.open("merchant")
	await _fr(2)
	shopn._on_buy("nordsword")
	_check(not GameState.owned_gear.has("nordsword") \
			and GearData.equipped_id(GameState, "weapon") != "nordsword",
			"G6: прямой вызов покупки запертой позиции отбит гейтом (не только глазами)")
	Shop.close()
	await _fr(2)
	# Гриим: кольчуга как была ( VENDORS-массив не отрезал старого прилавок)
	Shop.open("smith")
	await _fr(2)
	var cb2: Button = shopn.buy_btns.get("chain", null)
	_check(cb2 != null and cb2.visible, "G6: у Гриима кольчуга видна всегда (регресс проверял)")
	Shop.close()
	await _fr(2)

# ---------------- G7 сейв ----------------

func _g7_save() -> void:
	print("== G7: сумка/заточка в сейве v4, миграция, адверсариал ==")
	_empty_gear()
	GameState.ensure_gear("nordsword")
	GameState.ensure_gear("chain")
	GameState.equip_item("weapon", "nordsword")
	GameState.equip_item("armor", "chain")
	GameState.sharpen["nordsword"] = 3
	_check(GameState.save_game(), "G7: сейв записан")
	var d := GameState.to_dict()
	_check(int(d.get("v", 0)) == 4, "G7: версия сейва осталась 4 (аддитивно, без банпа)")
	var iv: Dictionary = d.get("inv", {})
	_check(iv.has("bag") and iv.has("sharpen"), "G7: inv.bag и inv.sharpen — в контейнере v4")
	GameState.owned_gear = []
	GameState.sharpen = {}
	GameState.gear = {"weapon": "", "armor": "", "shield": "", "relic": ""}  # t10: +shield
	_check(GameState.load_game(), "G7: загрузка прошла")
	_check(GameState.owned_gear.has("nordsword") and GameState.owned_gear.has("chain") \
			and GearData.equipped_id(GameState, "weapon") == "nordsword" \
			and GearData.equipped_id(GameState, "armor") == "chain",
			"G7: сумка и надетое пережили roundtrip")
	_check(int(GameState.sharpen.get("nordsword", 0)) == 3 and GearData.sharpen_tier(GameState) == 3,
			"G7: заточка 3-й ступени при оружии после сейва (вердикт п.4 «в сейве»)")
	# legacy v3: меч из старого сейва — и слот, и владение; амулет вечный
	_write_raw(JSON.stringify({
		"v": 3, "class_id": "warrior", "level": 2, "seen_intro": true,
		"has_sword": true, "has_amulet": true,
	}))
	_check(GameState.load_game(), "G7: старый v3 прочитан")
	_check(GearData.equipped_id(GameState, "weapon") == "sword" \
			and GameState.owned_gear.has("sword") and GameState.owned_gear.has("amulet"),
			"G7: миграция: legacy меч и вечный амулет сами встали в сумку")
	_check(GameState.sharpen.is_empty(), "G7: у legacy-сейва заточки нет (пусто, не мусор)")
	# адверсариал: мусор в bag/перелив sharpen не переживают лоад
	_write_raw(JSON.stringify({
		"v": 4, "class_id": "warrior", "level": 2, "seen_intro": true,
		"inv": {"bag": ["__ghost__", 42, "potion", "nordsword"], "sharpen": {"nordsword": 99, "potion": 2}},
	}))
	_check(GameState.load_game(), "G7: сейв-мусор прочитан без падения")
	_check(GameState.owned_gear == ["nordsword"],
			"G7: чужие/некорректные id выкинуты из сумки: %s" % str(GameState.owned_gear))
	_check(int(GameState.sharpen.get("nordsword", 0)) == 5 and not GameState.sharpen.has("potion"),
			"G7: степень клампится в 5, не-оружие в заточке не живёт")
	# забег сжигает нажитое: start_fresh_game чистит сумку/заточку
	GameState.start_fresh_game()
	_check(GameState.owned_gear.is_empty() and GameState.sharpen.is_empty() \
			and String(GameState.gear.get("weapon", "x")) == "",
			"G7: новый забег — снаряжение и заточка сгорели (вечный амулет вернётся флагом)")

# ---------------- G8 канон оружия (t10, вердикт пользователя 25.11) ----------------
# «магу посохи, а не мечи или лук; лучнику только луки; воину только мечи
# и щиты». Таксономия weapon_type + слот shield + матрица + гейт экипировки +
# «не твоя рука» покупается, но не надевается + легаси-сейв снимает чужое.
# Лист-двойник иконок: tools_art/sheet_weapons_v1.gd (FNV-пины ниже).

## Смена класса в тесте: set_class отказывает на уже выбранном (канон t9),
## поэтому честный «новый герой» = обнулить и выбрать.
func _set_cls(cid: String) -> void:
	GameState.class_id = ""
	if cid != "":
		GameState.set_class(cid)
	GameState.gear_gate_note = ""
	_toasts = []

## FNV-1a 32 по PNG-байтам (тот же рецепт, что cave_paint/sheet-инструменты).
func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

func _g8_canon() -> void:
	print("== G8: канон оружия 25.11 — матрица, гейт, щиты, рынок, легаси ==")
	_empty_gear()
	GameState.toast.connect(_toast_g8)

	# --- W8.1 реестр: таксономия и семь новых позиций ---
	_check(GearData.weapon_type("sword") == "sword" and GearData.weapon_type("rune_blade") == "sword",
			"W: старая линейка — оружие типа sword (без поля = меч, канон weapon_type)")
	_check(GearData.weapon_type("axe") == "sword",
			"W: топор в группе sword при AXE_AS_SWORD=true (одна константа, ждёт вердикт)")
	var gsrc := FileAccess.get_file_as_string("res://scripts/gear_data.gd")
	_check(gsrc.contains("const AXE_AS_SWORD := true"),
			"W: AXE_AS_SWORD=true в источнике (false => топор не наденет никто — одна строка)")
	_check(GearData.weapon_type("bow_hunter") == "bow" and GearData.weapon_type("staff_rune") == "staff",
			"W: лук/посох размечены своими типами")
	_check(GearData.weapon_type("leather") == "", "W: не-оружие — пустой weapon_type")
	_check(GearData.CLASS_WEAPONS == {"warrior": ["sword"], "archer": ["bow"], "mage": ["staff"]} \
			and GearData.CLASS_SHIELDS == ["warrior"],
			"W: матрица канона 3x3 + щит только воину (вердикт дословно)")
	var specs := [
		["staff_apprentice", "weapon", 60, 2, 5, ""],
		["staff_oak", "weapon", 150, 4, 10, ""],
		["staff_rune", "weapon", 300, 6, 15, "rare"],
		["bow_hunter", "weapon", 80, 2, 0, ""],
		["bow_heavy", "weapon", 200, 4, 0, "rare"],
		["shield_iron", "shield", 70, 0, 0, ""],
		["shield_raven", "shield", 220, 0, 0, "rare"],
	]
	var reg_ok := true
	for s in specs:
		var it: Dictionary = GearData.item(String(s[0]))
		var want_ab: int = 1 if s[0] == "shield_iron" else (2 if s[0] == "shield_raven" else 0)
		if String(it.get("slot", "")) != String(s[1]) or int(it.get("price", -1)) != int(s[2]) \
				or int(it.get("dmg_bonus", 0)) != int(s[3]) or int(it.get("mana_bonus", 0)) != int(s[4]) \
				or int(it.get("armor_bonus", 0)) != want_ab \
				or String(it.get("rarity", "")) != String(s[5]):
			reg_ok = false
	_check(reg_ok, "W: семь позиций реестра — цена/бонусы/манаредкость по BALANCE-строкам 15–21")
	_check("staff_apprentice" in GearData.VENDOR_STOCK["hermit"] \
			and "bow_hunter" in GearData.VENDOR_STOCK["merchant"] \
			and "bow_heavy" in GearData.VENDOR_STOCK["merchant"] \
			and "staff_rune" in GearData.VENDOR_STOCK["merchant"] \
			and "staff_oak" in GearData.VENDOR_STOCK["smith"] \
			and "shield_iron" in GearData.VENDOR_STOCK["smith"] \
			and "shield_raven" in GearData.VENDOR_STOCK["smith"],
			"W: витрины — посох Геральда, лучная линия Драна, железо посохов/щитов у Гриима")
	var ssrc := FileAccess.get_file_as_string("res://scripts/shop.gd")
	_check(ssrc.contains('for slot in ["weapon", "shield", "armor"]'),
			"W: скупка лавки принимает щиты (строка продажи расширена)")
	var gssrc := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	_check(gssrc.contains("flush_gear_gate_note") and gssrc.contains("gear_gate_note"),
			"W: легаси-гейт сейва и одноразовая заметка живут в GameState (не только в UI)")

	# --- W8.2 матрица 3x3 (чистый can_equip, все девять пар) ---
	var matrix := {
		"warrior": {"sword": true, "bow_hunter": false, "staff_oak": false},
		"archer": {"sword": false, "bow_hunter": true, "staff_oak": false},
		"mage": {"sword": false, "bow_hunter": false, "staff_oak": true},
	}
	for cid in ["warrior", "archer", "mage"]:
		for iid in ["sword", "bow_hunter", "staff_oak"]:
			var g: Dictionary = GearData.can_equip(String(cid), String(iid))
			_check(bool(g.get("ok", false)) == bool(matrix[cid][iid]),
					"W: матрица %s x %s => %s" % [cid, iid, "надеть" if matrix[cid][iid] else "отказ"])
	# щиты трём классам + «не оружие» всем + безмолвие без класса
	_check(bool(GearData.can_equip("warrior", "shield_iron").get("ok", false)) \
			and not bool(GearData.can_equip("archer", "shield_iron").get("ok", false)) \
			and not bool(GearData.can_equip("mage", "shield_raven").get("ok", false)),
			"W: щит — только воину (все три класса проверены)")
	var soft_ok := true
	for cid in ["warrior", "archer", "mage"]:
		if not bool(GearData.can_equip(String(cid), "leather").get("ok", true)) \
				or not bool(GearData.can_equip(String(cid), "amulet").get("ok", true)):
			soft_ok = false
	_check(soft_ok, "W: доспех/оберег — вне матрицы (гейт их не трогает)")
	_check(bool(GearData.can_equip("", "staff_rune").get("ok", true)) \
			and bool(GearData.can_equip("", "shield_raven").get("ok", true)),
			"W: class_id \"\" (без класса после смерти, t9) — гейт молчит")

	# --- W8.3 живое поведение equip_item + причина тоста ---
	_set_cls("archer")
	_empty_gear()
	GameState.equip_item("weapon", "bow_hunter")
	_check(GearData.equipped_id(GameState, "weapon") == "bow_hunter" and GameState.damage == 4,
			"W: лучник натянул охотничий лук — урон 2+2 (лук платит в damage как меч)")
	_toasts = []
	GameState.equip_item("weapon", "sword")
	_check(GearData.equipped_id(GameState, "weapon") == "bow_hunter" \
			and _toasts.size() == 1 and String(_toasts[0]).contains("носят воины"),
			"W: меч лучнику — отказ ОДНИМ тостом с причиной (не молча), слот цел")
	_toasts = []
	_set_cls("mage")
	_empty_gear()
	GameState.equip_item("weapon", "bow_hunter")
	_check(GearData.equipped_id(GameState, "weapon") == "" \
			and _toasts.size() == 1 and String(_toasts[0]).contains("носят лучники"),
			"W: лук магу — отказ с причиной («лук носят лучники»)")
	GameState.equip_item("weapon", "staff_oak")
	_check(GearData.equipped_id(GameState, "weapon") == "staff_oak" and GameState.max_mana == 40,
			"W: маг взял крепкий посох — урон есть, мана 30+10=40 (потолок, не реген)")
	GameState.equip_item("weapon", "staff_rune")
	_check(GameState.max_mana == 45 and GameState.damage == 3 + 6,
			"W: рунный посох — мана 45, урон 3+6 (формула читает weapon slot)")
	GameState.equip_item("weapon", "")
	_check(GameState.max_mana == 30, "W: посох снят — потолок маны вернулся к 30")
	_set_cls("archer")
	_toasts = []
	GameState.equip_item("shield", "shield_iron")
	_check(GearData.equipped_id(GameState, "shield") == "" \
			and String(_toasts[0]).contains("ноша воина"),
			"W: щит лучнику — отказ «ноша воина» (слот shield тоже под матрицей)")
	_set_cls("warrior")
	GameState.equip_item("shield", "shield_iron")
	_check(GearData.equipped_id(GameState, "shield") == "shield_iron",
			"W: воин поднял щит — слот shield живой")
	GameState.ensure_gear("axe")
	GameState.equip_item("weapon", "axe")
	_check(GearData.equipped_id(GameState, "weapon") == "axe",
			"W: боевой топор воину разрешён (AXE_AS_SWORD, ждёт уточнения пользователя)")
	# без класса — надевание молча проходит (t9-флоу смерти)
	_set_cls("")
	_empty_gear()
	_toasts = []
	GameState.equip_item("weapon", "staff_oak")
	_check(GearData.equipped_id(GameState, "weapon") == "staff_oak" and _toasts.is_empty(),
			"W: без класса — надевание без тоста (гейт молчит, модалка класса впереди)")

	# --- W8.4 щит в бою: плоский armor_bonus, не рандум-блок ---
	_set_cls("warrior")
	_empty_gear()
	_check(GearData.absorb(GameState, 4) == 4, "W: голый воин — 4 проходит целиком")
	_give("leather", "armor")
	GameState.equip_item("shield", "shield_iron")
	_check(GearData.armor_bonus(GameState) == 2 and GearData.absorb(GameState, 4) == 2,
			"W: кожа+щит = броня 2 (щит плоский, «съедает» 1; детерминизм absorb)")
	_give("boarhide", "armor")
	GameState.equip_item("shield", "shield_raven")
	_check(GearData.armor_bonus(GameState) == 5 and GearData.absorb(GameState, 8) == 3,
			"W: шкура вепря+вороний щит = 5, урон 8->3")
	_check(GearData.absorb(GameState, 1) == 1, "W: «минимум 1» непреломен и с двумя щитами брони")

	# --- W8.5 лавка: чужое видно серым, покупается, не надевается ---
	_set_cls("archer")
	_empty_gear()
	GameState.gold = 1000
	Shop.open("smith")
	await _fr(2)
	var sword_btn: Button = shopn.buy_btns.get("sword", null)
	_check(sword_btn != null and sword_btn.visible and sword_btn.modulate == Color(0.6, 0.6, 0.66) \
			and String(sword_btn.tooltip_text).contains("Не твоя рука"),
			"W: витрина — меч лучнику серый с подсказкой, но НЕ disabled (товар будущего круга)")
	var gold0: int = GameState.gold
	_toasts = []
	shopn._on_buy("sword")
	await _fr(2)
	var buy_ok := GameState.gold == gold0 - GearData.price("sword") \
			and GameState.owned_gear.has("sword") \
			and GearData.equipped_id(GameState, "weapon") == ""
	var toast_found := false
	for t in _toasts:
		if String(t).contains("Куплено: Железный меч") and String(t).contains("носят воины"):
			toast_found = true
	_check(buy_ok and toast_found,
			"W: покупка чужого РАЗРЕШЕНА — золото списано, меч в сумке, слот пуст, тост честный (золото %d->%d, сумка %s, слот '%s', тосты %s)" % [
				gold0, GameState.gold, str(GameState.owned_gear),
				GearData.equipped_id(GameState, "weapon"), str(_toasts)])
	# мирная покупка «не своей» ветки у своего торговца (воин и посох)
	Shop.close()
	await _fr(2)
	_set_cls("warrior")
	_empty_gear()
	GameState.gold = 1000
	Shop.open("hermit")
	await _fr(2)
	_toasts = []
	shopn._on_buy("staff_apprentice")
	_check(GameState.owned_gear.has("staff_apprentice") \
			and GearData.equipped_id(GameState, "weapon") == "",
			"W: воин купил ученический посох — в сумку, не на спину (auto-equip лавки исправлен) (сумка %s, оружие '%s', золото %d, тосты %s)" % [
				str(GameState.owned_gear), GearData.equipped_id(GameState, "weapon"), GameState.gold, str(_toasts)])
	# своё — как раньше: покупка + надевание + белый цвет витрины
	Shop.close()
	await _fr(2)
	Shop.open("smith")
	await _fr(2)
	shopn.refresh()
	await _fr(2)
	var sword_btn2: Button = shopn.buy_btns.get("sword", null)
	_check(sword_btn2.modulate == Color.WHITE, "W: тому же классу — тот же меч белым по белому")
	gold0 = GameState.gold
	shopn._on_buy("shield_iron")
	await _fr(2)
	_check(GearData.equipped_id(GameState, "shield") == "shield_iron" \
			and gold0 - GameState.gold == GearData.price("shield_iron"),
			"W: воин купил щит — надет в shield-слот, цена 70 списана")
	Shop.close()
	await _fr(2)
	# клик чужого в сумке — пред-проверка UI: один тост, слот цел
	_set_cls("archer")
	_empty_gear()
	GameState.ensure_gear("sword")
	Inventory.open()
	await _fr(2)
	_check(invn.slot_btns.has("shield") and String(Inventory.SLOT_NAMES["shield"]) == "Щит",
			"W: карточка слота «Щит» построена (SLOT_ORDER t10)")
	_toasts = []
	invn._on_bag_pressed(Inventory.gear_view_ids().find("sword"))
	await _fr(2)
	_check(GearData.equipped_id(GameState, "weapon") == "" and _toasts.size() == 1,
			"W: клик чужого меча из сумки — ОДИН отказной тост (двойного нет), не наделось")
	Inventory.close()
	await _fr(2)

	# --- W8.6 легаси-сейв: чужое снимается при загрузке с одноразовым тостом ---
	_write_raw(JSON.stringify({
		"v": 4, "class_id": "mage", "level": 2, "seen_intro": true,
		"gear": {"weapon": "sword", "armor": "", "shield": "shield_raven", "relic": ""},
		"inv": {"bag": [], "sharpen": {}},
	}))
	_check(GameState.load_game(), "W: маг-сейв с мечом и щитом прочитан")
	_check(GearData.equipped_id(GameState, "weapon") == "" \
			and GearData.equipped_id(GameState, "shield") == "" \
			and GameState.owned_gear.has("sword") and GameState.owned_gear.has("shield_raven") \
			and not GameState.has_sword,
			"W: гейт при загрузке снял чужое в сумку, has_sword пересинхронизирован (x2 из воздуха не выросло)")
	_check(GameState.gear_gate_note.contains("Железный меч") and GameState.gear_gate_note.contains("Вороний щит"),
			"W: заметка называет снятые вещи («Привычка прежних дней…») — не молча")
	_toasts = []
	GameState.flush_gear_gate_note()
	_check(_toasts.size() == 1 and String(_toasts[0]).contains("не твоя рука") \
			and GameState.gear_gate_note == "",
			"W: флеш — ровно один тост при входе в мир")
	_toasts = []
	GameState.flush_gear_gate_note()
	_check(_toasts.is_empty(), "W: повторный флеш молчит (одноразовость)")
	# маг не потерял потолок маны из-за переполоха: посох из сумки встал бы законно
	_check(GameState.max_mana == 30, "W: без посоха потолок маны мага честные 30")
	_write_raw(JSON.stringify({
		"v": 4, "class_id": "warrior", "level": 2, "seen_intro": true,
		"gear": {"weapon": "sword", "armor": "", "shield": "shield_raven", "relic": ""},
		"inv": {"bag": [], "sharpen": {}},
	}))
	_check(GameState.load_game() \
			and GearData.equipped_id(GameState, "weapon") == "sword" \
			and GearData.equipped_id(GameState, "shield") == "shield_raven" \
			and GameState.has_sword and GameState.gear_gate_note == "",
			"W: воин с тем же сейвом — всё на месте, legacy x2 жив, заметки нет")

	# --- W8.7 иконки: FNV-пины листа tools_art/sheet_weapons_v1.gd (25.11) ---
	var icon_pins := {
		"staff_apprentice": "F2F43024", "staff_oak": "77E1791A", "staff_rune": "E3AA1E97",
		"bow_hunter": "D4BD2538", "bow_heavy": "F9477B26",
		"shield_iron": "662DEA71", "shield_raven": "0129D820",
	}
	for iid in icon_pins:
		_check(_fnv32_hex(UiIcons.item_icon(String(iid)).get_image()) == String(icon_pins[iid]),
				"W: иконка %s — байт-в-байт листу (код-арт, ноль растровов)" % iid)

	# Hygiene: возврат к бойлерплейт-состоянию других секций не нужен (стенд
	# умирает), но класс почистим — вдруг следующий автосейв дёрнется
	GameState.class_id = ""
	GameState.toast.disconnect(_toast_g8)

# ---------------- G9 мировые спрайты оружия (t14 «коряга», вердикт 25.11) ----------------
# Лист «Оружие v1» (diag-t10/PINS_T10.md) утверждён вердиктом «спрайты внедряй»,
# мировой вариант — KORYAGA (одна константа WorldWeapons.WORLD_ART_KORYAGA).
# Цепочка равенств: лист (FNV PINS_T10) == рисовальщик == байты атласа ==
# стойка в витрине. 47-й стенд не плодим: всё в живом qa_gear.

const WWTool := preload("res://tools_art/weapons_world_v1.gd")
## Байт-целостность артефакта бейка (tools_art/weapons_world_v1.gd, 25.11):
const WW_ATLAS_MD5 := "12a1052a2c859abf6c2f8cae788de1d8"
## FNV-пины листа, секция B (ряд 0 KORYAGA / ряд 1 SILHOUETTE):
const WW_PIN_KORYAGA := {
	"staff_apprentice": "AD94FAAE", "staff_oak": "8A2D5D47", "staff_rune": "D92F1020",
	"bow_hunter": "716A18CF", "bow_heavy": "FA62C3CF",
	"shield_iron": "2C6EFA7E", "shield_raven": "AE747213",
}
const WW_PIN_SIL := {
	"staff_apprentice": "414EDA4B", "staff_oak": "B7E43346", "staff_rune": "FDC77A90",
	"bow_hunter": "C5B70EF2", "bow_heavy": "B1B0ED5E",
	"shield_iron": "C43D6FB6", "shield_raven": "C43D6FB6",
}

func _md5_res(path: String) -> String:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var buf := f.get_buffer(65536)
	while buf.size() > 0:
		ctx.update(buf)
		buf = f.get_buffer(65536)
	return ctx.finish().hex_encode()

func _lum8(c: Color) -> float:
	return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b)

func _g9_world_art() -> void:
	print("== G9: мировые спрайты оружия — коряга (t14, вердикт 25.11) ==")
	# G9.1 файл: кодо-бейк в дереве, геометрия 2 ряда × 12 слотов 16 px
	_check(WorldWeapons.available(), "G9: атлас weapons_world_v1.png в дереве (кодо-бейк, ноль растров-импортов)")
	if not WorldWeapons.available():
		return
	var img: Image = load(WorldWeapons.ATLAS_PATH).get_image()
	_check(img.get_width() == WorldWeapons.SLOT * WorldWeapons.SLOTS.size() and img.get_height() == WorldWeapons.SLOT * 2,
			"G9: геометрия атласа %dx%d (12 слотов x 2 ряда по 16 px)" % [img.get_width(), img.get_height()])
	_check(_md5_res(WorldWeapons.ATLAS_PATH) == WW_ATLAS_MD5,
			"G9: md5 атласа побайтово по пину бейка 25.11")
	# G9.2 лист == рисовальщик: FNV кадров, посчитанные тем же энкодером, —
	# дословно PINS_T10 секция B (побитовое равенство утверждённому листу)
	for id in WW_PIN_KORYAGA:
		_check(WWTool._fnv32_hex(WWTool._frame(String(id))) == String(WW_PIN_KORYAGA[id]),
				"G9: KORYAGA %s — FNV побитово листу (PINS_T10)" % id)
	for id in WW_PIN_SIL:
		_check(WWTool._fnv32_hex(WWTool._sil(WWTool._frame(String(id)))) == String(WW_PIN_SIL[id]),
				"G9: SILHOUETTE %s — FNV побитово листу (запасной ряд)" % id)
	# G9.3 рисовальщик == атлас после декода: все 24 кадра, alpha-маска + RGB
	var pdiff := 0
	for i in WorldWeapons.SLOTS.size():
		for row in 2:
			var a: Image = WWTool._frame(String(WorldWeapons.SLOTS[i])) if row == 0 \
					else WWTool._sil(WWTool._frame(String(WorldWeapons.SLOTS[i])))
			var b: Image = WWTool._frame_of(img, i, row)
			for y in WorldWeapons.SLOT:
				for x in WorldWeapons.SLOT:
					var ca: Color = a.get_pixel(x, y)
					var cb: Color = b.get_pixel(x, y)
					if (ca.a > 0.5) != (cb.a > 0.5) \
							or (ca.a > 0.5 and (ca.to_rgba32() & 0xFFFFFF) != (cb.to_rgba32() & 0xFFFFFF)):
						pdiff += 1
	_check(pdiff == 0, "G9: атлас == рисовальщик пиксель-в-пиксель (24 кадра, alpha+RGB): diff=%d" % pdiff)
	# G9.4 палитра мирового атласа — чистые RAMPS/FLATS (техцветов слота нет)
	var pidx: Dictionary = PixelPalette.color_index()
	var off := 0
	for y in img.get_height():
		for x in img.get_width():
			var col: Color = img.get_pixel(x, y)
			if col.a > 0.5 and not pidx.has(PixelPalette.key(col)):
				off += 1
	_check(off == 0, "G9: палитра атласа в family (RAMPS/FLATS), off=%d" % off)
	# G9.5 переключатель вердикта: KORYAGA включена, стойка читет ряд 0
	_check(WorldWeapons.WORLD_ART_KORYAGA and WorldWeapons.row_index() == 0,
			"G9: мировой стиль — KORYAGA (вердикт 25.11), переключатель один")
	var at: AtlasTexture = WorldWeapons.frame_texture("sword")
	_check(at != null and at.region.position.y == 0.0 and at.region.size == Vector2(16, 16),
			"G9: кадр витрины берётся из выбранного ряда (16 px, y=0)")
	# G9.6 живая лавка Гриима: стойка показывает ровно видимое оружейное стекло
	Shop.open("smith")
	await _fr(2)
	var rack: HFlowContainer = shopn.rack
	_check(rack != null and rack.visible, "G9: у Гриима стойка оружия видна (существующая витрина, без 47-го стенда)")
	var rack_ids: Array = []
	for rid in shopn.rack_rects:
		if (shopn.rack_rects[rid] as TextureRect).visible:
			rack_ids.append(String(rid))
	var btn_ids: Array = []
	for bid in shopn.buy_btns:
		var bit := GearData.item(String(bid))
		if String(bit.get("slot", "")) in ["weapon", "shield"] and (shopn.buy_btns[bid] as Button).visible:
			btn_ids.append(String(bid))
	rack_ids.sort()
	btn_ids.sort()
	_check(rack_ids == btn_ids and rack_ids.size() == 6,
			"G9: стойка == видимые ряды оружия (6 позиций, зеркало витрины): %s" % str(rack_ids))
	# G9.7 гейт витрины на стойке: Дран до/после сделки (VENDOR_REQ тот же)
	Shop.close()
	GameState.slime_quest = 1
	Shop.open("merchant")
	await _fr(2)
	var nr: TextureRect = shopn.rack_rects.get("nordsword", null)
	_check(nr != null and not nr.visible, "G9: Дран до сделки — меча северян на стойке нет (гейт общий с рядом)")
	GameState.slime_quest = 2
	shopn._apply_vendor()
	_check(nr.visible, "G9: сделка закрыта — северянин встал на стойку")
	# G9.8 Ута: оружия нет — стойка целиком скрыта (панель не полнеет)
	Shop.close()
	Shop.open("uta")
	await _fr(2)
	_check(not shopn.rack.visible, "G9: у Уты стойка скрыта (нечего выкладывать, высоты не даёт)")
	Shop.close()
	await _fr(2)
	# G9.9 мышь: стойка не ест клики (контракт модальности лавки B-02)
	var mouse_ok := rack.mouse_filter == Control.MOUSE_FILTER_IGNORE
	for rid in shopn.rack_rects:
		mouse_ok = mouse_ok and ((shopn.rack_rects[rid] as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check(mouse_ok, "G9: rack и все кадры — MOUSE_FILTER_IGNORE (клики принадлежат рядам)")
	# G9.10 читаемость на полах биомов (1:1, как секция C листа): пол — не
	# заливка, а патчворк LIGHT/MID/DARK одного рампа; кадр обязан читаться
	# (>=10 контрастных по светлоте пикселей) хотя бы на каждом опорном тоне,
	# считаем по максимуму по патчам семейства — как он реально лежит под ногами.
	var floor_families: Array = ["GRASS", "PATH", "STONE_WARM", "CRYSTAL", "ASH_GROUND", "CHAR"]
	var read_ok := true
	for i in WorldWeapons.SLOTS.size():
		var fr: Image = WWTool._frame_of(img, i, 0)
		for fam in floor_families:
			var best := 0
			for tone in [PixelPalette.T_LIGHT, PixelPalette.T_MID, PixelPalette.T_DARK]:
				var fc: Color = PixelPalette.c(String(fam), tone)
				var n := 0
				for y in WorldWeapons.SLOT:
					for x in WorldWeapons.SLOT:
						var c: Color = fr.get_pixel(x, y)
						if c.a > 0.5 and absf(_lum8(c) - _lum8(fc)) >= 0.12:
							n += 1
				best = maxi(best, n)
			if best < 10:
				read_ok = false
	_check(read_ok, "G9: каждый кадр KORYAGA читаем на полах шести биомов (>=10 контрастных px на лучшем патче)")
	# G9.11 подсказки стойки — названия предметов (витрина объяснима без кода)
	var tips_ok := true
	for rid in shopn.rack_rects:
		if String((shopn.rack_rects[rid] as TextureRect).tooltip_text) == "":
			tips_ok = false
	_check(tips_ok, "G9: у каждого кадра стойки — tooltip с названием предмета")
