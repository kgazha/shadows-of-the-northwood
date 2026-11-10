extends Node
## QA-харнесс s1: Shop (покупка/отказ/идемпотентность/sell), GearData (damage/absorb),
## save v2 roundtrip, legacy v1 миграция, битые поля сейва.

var fails := {"n": 0}
var toasts: Array = []
var shop: Shop

func ck(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		print("PASS %s" % name)
	else:
		fails["n"] += 1
		print("FAIL %s :: %s" % [name, detail])

func reset_state(gold: int) -> void:
	GameState.class_id = "warrior"
	GameState.gold = gold
	GameState.equip_item("weapon", "")
	GameState.equip_item("armor", "")
	GameState.has_amulet = false
	GameState.flags = {}
	GameState.recalc_max_hp()
	GameState.heal_full()
	toasts.clear()

func has_toast(sub: String) -> bool:
	for t in toasts:
		if String(t).find(sub) >= 0:
			return true
	return false

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	shop = Shop.new()
	add_child(shop)
	_run()
	print("SUMMARY fails=%d" % fails["n"])
	get_tree().quit(0)

func _run() -> void:
	var base := 2  # warrior dmg
	# --- T1 базовый урон без оружия ---
	reset_state(0)
	ck(GameState.damage == base, "T1 bare damage==2", "got %d" % GameState.damage)

	# --- T2 отказ по цене: gold не уходит, экипировки нет ---
	reset_state(0)
	ck(shop.buy_btns.has("sword"), "T2 buy btn exists")
	shop.buy_btns["sword"].pressed.emit()
	ck(GameState.gold == 0, "T2 gold untouched on reject", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "", "T2 no equip on reject", String(GameState.gear["weapon"]))
	ck(has_toast("Не хватает золота"), "T2 toast deny")
	ck(not has_toast("Куплено"), "T2 no purchase toast")

	# --- T3 79 золота на axe(160) — отказ ---
	reset_state(79)
	shop.buy_btns["axe"].pressed.emit()
	ck(GameState.gold == 79 and String(GameState.gear["weapon"]) == "", "T3 reject at 79g", "gold=%d gear=%s" % [GameState.gold, GameState.gear["weapon"]])

	# --- T4 успешная покупка sword(80): gold, gear, legacy-флаг, damage ---
	reset_state(100)
	shop.buy_btns["sword"].pressed.emit()
	ck(GameState.gold == 20, "T4 gold 100-80=20", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "sword", "T4 gear weapon=sword", String(GameState.gear["weapon"]))
	ck(GameState.has_sword, "T4 has_sword synced")
	ck(GameState.damage == 4, "T4 dmg 2x2=4", "got %d" % GameState.damage)
	ck(has_toast("Куплено"), "T4 purchase toast")

	# --- T5 повторная покупка надетого — отказ, gold стоит ---
	reset_state(120)
	shop.buy_btns["sword"].pressed.emit()  # надето
	var g5: int = GameState.gold
	shop.buy_btns["sword"].pressed.emit()  # повторно
	ck(GameState.gold == g5, "T5 gold untouched on re-buy", "before=%d after=%d" % [g5, GameState.gold])
	ck(has_toast("Это уже на тебе"), "T5 already-worn toast")

	# --- T6 замена оружия: sword -> axe ---
	reset_state(300)
	shop.buy_btns["sword"].pressed.emit()
	shop.buy_btns["axe"].pressed.emit()
	ck(GameState.gold == 300 - 80 - 160, "T6 gold after two buys", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "axe", "T6 gear weapon=axe", String(GameState.gear["weapon"]))
	ck(not GameState.has_sword, "T6 has_sword cleared on axe")
	ck(GameState.damage == 5, "T6 dmg round(2*2.5)=5", "got %d" % GameState.damage)

	# --- T7 броня: absorb leather=1 chain=2, min-1 ---
	reset_state(400)
	shop.buy_btns["leather"].pressed.emit()
	ck(String(GameState.gear["armor"]) == "leather", "T7 gear armor=leather")
	GameState.heal_full()
	var hp0: int = GameState.hp
	GameState.hurt(5)
	ck(GameState.hp == hp0 - 4, "T7 leather absorb 1 (5->4)", "hp %d->%d" % [hp0, GameState.hp])
	shop.buy_btns["chain"].pressed.emit()
	GameState.heal_full()
	hp0 = GameState.hp
	GameState.hurt(5)
	ck(GameState.hp == hp0 - 3, "T7 chain absorb 2 (5->3)", "hp %d->%d" % [hp0, GameState.hp])
	GameState.heal_full()
	hp0 = GameState.hp
	GameState.hurt(1)
	ck(GameState.hp == hp0 - 1, "T7 min-1 damage with chain", "hp %d->%d" % [hp0, GameState.hp])

	# --- T8 sell: продажа надетого, +цена/2, слот чист, повторный отказ ---
	reset_state(80)
	shop.buy_btns["sword"].pressed.emit()    # gold=0, sword надет
	toasts.clear()
	shop.sell_btns["weapon"].pressed.emit()  # +40
	ck(GameState.gold == 40, "T8 sell gold 0+40", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "", "T8 slot cleared after sell")
	ck(not GameState.has_sword, "T8 has_sword cleared after sell")
	ck(GameState.damage == 2, "T8 damage back to bare", "got %d" % GameState.damage)
	g5 = GameState.gold
	shop.sell_btns["weapon"].pressed.emit()  # продавать уже нечего
	ck(GameState.gold == g5, "T8 sell-empty gold untouched")
	ck(has_toast("Продавать нечего"), "T8 sell-empty toast")

	# --- T9 buy->sell цикл: чистый минус (no dupe profit) ---
	reset_state(1000)
	shop.buy_btns["rune_blade"].pressed.emit()  # -320
	shop.sell_btns["weapon"].pressed.emit()     # +160
	ck(GameState.gold == 1000 - 320 + 160, "T9 buy/sell roundtrip net -160", "got %d" % GameState.gold)

	# --- T10 legacy-меч: покупка не-sword съедает бесплатный legacy-флаг (NOTE) ---
	reset_state(0)
	GameState.has_sword = true  # меч из старого сундука: флаг есть, gear пуст
	ck(GameState.damage == 4, "T10 legacy flag mult x2", "got %d" % GameState.damage)
	var mult_legacy := GearData.weapon_mult(GameState)
	ck(mult_legacy == 2.0, "T10 weapon_mult legacy 2.0", "got %f" % mult_legacy)
	GameState.gold = 200
	shop.buy_btns["axe"].pressed.emit()  # equip "" -> has_sword=false, затем axe
	ck(not GameState.has_sword, "T10 NOTE legacy sword absorbed by axe buy")
	shop.sell_btns["weapon"].pressed.emit()
	ck(GameState.damage == 2, "T10 NOTE legacy sword lost after sell", "got %d" % GameState.damage)

	# --- T11 витрина: gold label, disabled только у надетого ---
	reset_state(33)
	shop.refresh()
	ck(shop.gold_lbl.text == "Золото: 33", "T11 gold label", shop.gold_lbl.text)
	shop.buy_btns["sword"].pressed.emit()  # надо 80, есть 33 -> отказ, не надет
	shop.refresh()
	ck(not bool(shop.buy_btns["sword"].disabled), "T11 NOTE unaffordable btn NOT disabled (design: gray only)")
	# наденем sword честно:
	GameState.gold = 500
	shop.buy_btns["sword"].pressed.emit()
	shop.refresh()
	ck(bool(shop.buy_btns["sword"].disabled), "T11 equipped btn disabled")

	# --- T12 spend_gold границы ---
	reset_state(50)
	ck(not GameState.spend_gold(-5), "T12 negative spend rejected")
	ck(GameState.gold == 50, "T12 negative spend no-op")
	ck(GameState.spend_gold(0), "T12 zero spend ok")
	ck(not GameState.spend_gold(51), "T12 over-spend rejected")
	ck(GameState.gold == 50, "T12 over-spend no-op")
	GameState.gold = 0
	GameState.add_gold(-999)
	ck(GameState.gold == 0, "T12 add_gold clamps >=0", "got %d" % GameState.gold)

	# --- T13 статический API Shop ---
	ck(not Shop.is_open(), "T13 shop closed at start")
	Shop.open()
	ck(Shop.is_open(), "T13 static open")
	Shop.close()
	ck(not Shop.is_open(), "T13 static close")

	# --- T14 цены/SELL_DIV для всего стока ---
	var ok14 := true
	for id in GearData.SHOP_STOCK:
		var p := GearData.price(String(id))
		var s := GearData.sell_price(String(id))
		if p <= 0 or s != maxi(1, int(p / 2)):
			ok14 = false
			print("  item %s price=%d sell=%d" % [id, p, s])
	ck(ok14, "T14 sell==floor(price/2) all stock")

	# --- T15 save v2 roundtrip (gold/gear/flags + автосейв по gold_changed) ---
	reset_state(1)
	GameState.gold = 0
	GameState.add_gold(777)  # через add_gold -> gold_changed -> автосейв
	shop.buy_btns["sword"].pressed.emit()
	shop.buy_btns["chain"].pressed.emit()
	GameState.set_flag("q.test", 5)
	GameState.cave_state = 2
	ck(GameState.save_game(), "T15 save_game ok")
	reset_state(0)
	GameState.flags = {}
	GameState.cave_state = 0
	ck(GameState.load_game(), "T15 load_game ok")
	# add_gold(777)+покупки: 777-80-180=517
	ck(GameState.gold == 517, "T15 gold roundtrip", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "sword", "T15 weapon roundtrip", String(GameState.gear["weapon"]))
	ck(String(GameState.gear["armor"]) == "chain", "T15 armor roundtrip", String(GameState.gear["armor"]))
	ck(GameState.has_sword, "T15 has_sword roundtrip")
	ck(int(GameState.flags.get("q.test", -1)) == 5, "T15 flag roundtrip", str(GameState.flags.get("q.test")))
	ck(GameState.cave_state == 2, "T15 cave_state roundtrip")
	ck(GameState.damage == 4, "T15 damage after load", "got %d" % GameState.damage)
	# автосейв без save_game():
	GameState.add_gold(1000)
	reset_state(0)
	ck(GameState.load_game(), "T15 autosave load")
	ck(GameState.gold == 1517, "T15 autosave on gold_changed", "got %d" % GameState.gold)

	# --- T16 legacy v1 сейв: без v/gold/gear/flags, has_sword=true ---
	var f1 := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f1.store_string('{"level":3,"xp":5,"xp_next":32,"has_sword":true,"class_id":"warrior","hp":9,"herbs":2}')
	f1.close()
	ck(GameState.load_game(), "T16 legacy v1 loads")
	ck(GameState.gold == 0, "T16 legacy gold=0")
	ck(String(GameState.gear["weapon"]) == "sword", "T16 legacy migrates to gear.sword", String(GameState.gear["weapon"]))
	ck(GameState.damage == 4, "T16 legacy damage x2", "got %d" % GameState.damage)
	ck(GameState.level == 3 and GameState.xp == 5, "T16 legacy level/xp")
	ck(GameState.max_hp == 12 + 2 * 2, "T16 legacy max_hp=16", "got %d" % GameState.max_hp)
	ck(GameState.hp == 9, "T16 legacy hp=9", "got %d" % GameState.hp)
	ck(int(GameState.to_dict().get("v", 0)) == 2, "T16 re-save versioned v2")

	# --- T17 битые поля ---
	var f2 := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f2.store_string('{"gold":"abc","gear":{"weapon":123,"armor":{"a":1}},"flags":"nope","level":"x","hp":null,"has_sword":1}')
	f2.close()
	ck(GameState.load_game(), "T17 corrupt loads without crash")
	ck(GameState.gold == 0, "T17 corrupt gold->0", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "sword", "T17 bad gear + has_sword=1 migration", String(GameState.gear["weapon"]))
	ck(String(GameState.gear["armor"]) == "", "T17 bad armor->empty")
	ck(GameState.flags.is_empty(), "T17 bad flags->empty")
	ck(GameState.level == 1, "T17 bad level->1")
	# неизвестные id в gear: инертны
	var f3 := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f3.store_string('{"class_id":"warrior","gear":{"weapon":"mordor","armor":"chainmail"},"gold":10}')
	f3.close()
	ck(GameState.load_game(), "T17 unknown-id save loads")
	ck(GameState.damage == 2, "T17 unknown weapon id inert dmg", "got %d" % GameState.damage)
	GameState.heal_full()
	var hp17: int = GameState.hp
	GameState.hurt(5)
	ck(GameState.hp == hp17 - 5, "T17 unknown armor id inert absorb", "hp %d->%d" % [hp17, GameState.hp])
	toasts.clear()
	shop.refresh()
	shop.sell_btns["weapon"].pressed.emit()
	ck(has_toast("Продавать нечего"), "T17 unknown id unsellable")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	print("S1 DONE")
