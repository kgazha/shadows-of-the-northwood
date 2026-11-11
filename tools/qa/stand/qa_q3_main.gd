extends Node
## Adversarial QA «Achv/daily/Ash/Altar» (HEAD dfa0966). Rezhim — user://qa_q2_mode.txt.

const SAVE := "user://save_morkheim.json"
const MODE_F := "user://qa_q2_mode.txt"
const T := 1794300000.0

var pass_n := 0
var fail_n := 0
var world: Node2D
var mode := "old"
var ash_sc: GDScript

func chk(g: String, n: String, c: bool, info: String = "") -> void:
	if c:
		pass_n += 1
		print("PASS | %s | %s" % [g, n])
	else:
		fail_n += 1
		print("FAIL | %s | %s | %s" % [g, n, info])

func ash_bal() -> int:
	return int(ash_sc.call("balance"))

func save_text() -> String:
	return FileAccess.get_file_as_string(SAVE)

func _ready() -> void:
	ash_sc = load("res://scripts/ash.gd") as GDScript
	if FileAccess.file_exists(MODE_F):
		mode = FileAccess.get_file_as_string(MODE_F).strip_edges()
	var ms: Node = load("res://scenes/main.tscn").instantiate()
	add_child(ms)
	world = ms
	for i in 6:
		await get_tree().process_frame
	_boot_checks()
	_altar()
	_group_A()
	_group_B()
	_group_C()
	_group_D()
	_group_E()
	_boss_source()
	_group_F()
	print("SUMMARY | mode=%s | PASS=%d FAIL=%d" % [mode, pass_n, fail_n])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MODE_F))
	get_tree().quit(0 if fail_n == 0 else 1)

# ---------------------------------------------------------------- BOOT

func _boot_checks() -> void:
	var g := "BT"
	var has_achv := false
	for c in world.get_children():
		if c is Achv:
			has_achv = true
	chk(g, "world built + Achv node present", world.player != null and has_achv and Achv.I != null)
	var stamp: float = float(GameState.flags.get("daily.stamp", 0.0))
	var streak: int = int(GameState.flags.get("daily.streak", 0))
	if mode == "old":
		chk(g, "old-save(1e6cacb-shape) daily day6 (order load->Achv)", GameState.gold == 150, "gold=%d" % GameState.gold)
		chk(g, "old-save streak 5->6", streak == 6, "streak=%d" % streak)
		chk(g, "old-save day6 xp +10", GameState.xp == 20, "xp=%d" % GameState.xp)
		chk(g, "no ash from day6", ash_bal() == 0, "ash=%d" % ash_bal())
		chk(g, "stamp persisted to file at boot", save_text().contains("daily.stamp"))
	else:
		chk(g, "today-save daily silent (gold)", GameState.gold == 100, "gold=%d" % GameState.gold)
		chk(g, "today-save streak kept 5", streak == 5, "streak=%d" % streak)
		chk(g, "today stamp NOT refreshed", absf(stamp - (Time.get_unix_time_from_system() - 60.0)) < 30.0, "stamp=%f" % stamp)
	chk(g, "legacy save loads on new HEAD without crash", true)
	chk(g, "no first_blood at boot", not bool(GameState.flags.get("ach.first_blood", false)))

# ---------------------------------------------------------------- ALT: altar (3255824)

func _altar() -> void:
	var g := "AL"
	var shop: Node = Shop.I
	chk(g, "shop singleton present", shop != null)
	Shop.open()
	chk(g, "shop opens as modal", Shop.is_open() and bool(GameState.input_locked))
	chk(g, "altar header shows ash: 0", String(shop.altar_head.text).contains("(пепел: 0)"), String(shop.altar_head.text))
	var mb0 = GameState.flags.get("meta.bless", null)
	shop._on_ash_buy("bless")
	chk(g, "buy at ash=0 denied, no flags, no crash", GameState.flags.get("meta.bless", null) == mb0 and ash_bal() == 0)
	ash_sc.call("add", 3)
	shop.refresh()
	chk(g, "altar header shows ash: 3", String(shop.altar_head.text).contains("(пепел: 3)"), String(shop.altar_head.text))
	var mh0: int = GameState.max_hp
	var sf0 := save_text()
	shop._on_ash_buy("bless")
	chk(g, "bless bought: spend 3 ash -> 0", ash_bal() == 0 and int(GameState.flags.get("meta.bless", 0)) == 1, "ash=%d mb=%s" % [ash_bal(), GameState.flags.get("meta.bless", null)])
	var sf1 := save_text()
	chk(g, "altar spend autosaved (file changed, meta.bless inside)", sf1 != sf0 and sf1.contains("meta.bless"))
	GameState.recalc_max_hp()
	chk(g, "H1 effect: bless +4 max_hp", GameState.max_hp == mh0 + 4, "%d->%d" % [mh0, GameState.max_hp])
	shop._on_ash_buy("bless")
	chk(g, "2nd bless costs 3+2=5, denied at 0 ash", int(GameState.flags.get("meta.bless", 0)) == 1)
	Shop.close()
	chk(g, "shop closes, lock released", not Shop.is_open() and not bool(GameState.input_locked))
	GameState.flags.erase("meta.bless")
	ash_sc.call("spend", 0)

# ---------------------------------------------------------------- A: daily edges

func _daily_run(stamp: Variant, streak: Variant, gold0: int) -> Dictionary:
	GameState.flags["daily.stamp"] = stamp
	GameState.flags["daily.streak"] = streak
	GameState.gold = gold0
	var h0: int = GameState.herbs
	var b0: int = GameState.brewed_potions
	var x0: int = GameState.xp
	var a0: int = ash_bal()
	var inst := Achv.new()
	add_child(inst)
	var r := {
		"dgold": GameState.gold - gold0,
		"streak": int(GameState.flags.get("daily.streak", 0)),
		"stamp": float(GameState.flags.get("daily.stamp", 0.0)),
		"dh": GameState.herbs - h0,
		"db": GameState.brewed_potions - b0,
		"dx": GameState.xp - x0,
		"da": ash_bal() - a0,
	}
	inst.queue_free()
	return r

func _group_A() -> void:
	var g := "DA"
	Achv.test_now = T
	var r: Dictionary
	r = _daily_run(T - 86500.0, 2, 50)
	chk(g, "yesterday -> day3 +25, streak 3", r.dgold == 25 and r.streak == 3 and r.stamp == T, "dg=%d st=%d" % [r.dgold, r.streak])
	r = _daily_run(T - 3600.0, 3, 50)
	chk(g, "same day (1h) silent", r.dgold == 0 and r.streak == 3 and r.stamp == T - 3600.0)
	r = _daily_run(T - 86399.0, 3, 50)
	chk(g, "23h59m silent", r.dgold == 0 and r.streak == 3)
	r = _daily_run(T - 86400.0, 2, 50)
	chk(g, "exactly 24h grants", r.dgold == 25 and r.streak == 3)
	r = _daily_run(T + 7200.0, 3, 50)
	chk(g, "rollback >1h silent, stamp kept", r.dgold == 0 and r.streak == 3 and r.stamp == T + 7200.0)
	r = _daily_run(T + 1800.0, 3, 50)
	chk(g, "rollback 30m silent", r.dgold == 0 and r.streak == 3)
	r = _daily_run(T - 3.0 * 86400.0, 5, 50)
	chk(g, "skip 3d -> streak 1", r.streak == 1 and r.dgold == 15)
	r = _daily_run(T - 86400.0, 7, 50)
	chk(g, "day8 after D7 -> reset 1", r.streak == 1 and r.dgold == 15 and r.da == 0)
	r = _daily_run(T - 86400.0, 6, 50)
	chk(g, "D7 = 80 gold + 2 ASH (new canon)", r.dgold == 80 and r.da == 2 and r.streak == 7, "dg=%d da=%d" % [r.dgold, r.da])
	r = _daily_run(T - 86400.0, 0, 50)
	chk(g, "D1 +15", r.dgold == 15 and r.streak == 1)
	r = _daily_run(T - 86400.0, 1, 50)
	chk(g, "D2 +20 +1 herb", r.dgold == 20 and r.dh == 1 and r.streak == 2)
	GameState.brewed_potions = 0
	r = _daily_run(T - 86400.0, 3, 50)
	chk(g, "D4 +1 brewed 0 gold", r.db == 1 and r.dgold == 0 and r.streak == 4)
	GameState.brewed_potions = GameState.BREWED_CAP
	r = _daily_run(T - 86400.0, 3, 50)
	chk(g, "D4 at cap no overflow", r.db == 0)
	r = _daily_run(T - 86400.0, 5, 50)
	chk(g, "D6 +50 +10xp", r.dgold == 50 and r.dx == 10 and r.streak == 6)
	GameState.flags["daily.stamp"] = T
	GameState.flags["daily.streak"] = 4
	GameState.gold = 50
	var inst := Achv.new()
	add_child(inst)
	chk(g, "same-day restart silent", GameState.gold == 50)
	inst.queue_free()
	GameState.flags.erase("daily.stamp")
	GameState.flags.erase("daily.streak")
	r = _daily_run(T - 86400.0, "x", 50)
	chk(g, "garbage streak no crash", r.streak <= 1)
	Achv.test_now = 0.0

# ---------------------------------------------------------------- B: first blood

func _group_B() -> void:
	var g := "FB"
	GameState.flags.erase("ach.first_blood")
	var g0: int = GameState.gold
	var a0: int = ash_bal()
	Loot.on_mob_death("slime", Vector2.ZERO, null)
	chk(g, "first_blood via Loot hook", bool(GameState.flags.get("ach.first_blood", false)))
	chk(g, "first_blood gold +10 ash +0", GameState.gold - g0 >= 10 and ash_bal() == a0, "dg=%d da=%d" % [GameState.gold - g0, ash_bal() - a0])
	g0 = GameState.gold
	for i in 50:
		Achv.on_mob_death("slime")
	chk(g, "50x -> +0 extra", GameState.gold == g0)
	GameState.flags.erase("ach.first_blood")
	g0 = GameState.gold
	Loot.on_mob_death("boss2_future_kind", Vector2.ZERO, null)
	chk(g, "unknown kind: hook fires, +10 exact, no crash", bool(GameState.flags.get("ach.first_blood", false)) and GameState.gold - g0 == 10)

# ---------------------------------------------------------------- C: herb hook

func _group_C() -> void:
	var g := "HB"
	GameState.flags.erase("ach.n.herbs")
	GameState.flags.erase("ach.herbalist")
	GameState.input_locked = false
	GameState.herbs = 9
	GameState.hp = GameState.max_hp - 10
	var hp0: int = GameState.hp
	world.drink_potion()
	chk(g, "herb -1, heal +3, count 1", GameState.herbs == 8 and GameState.hp - hp0 == 3 and int(GameState.flags.get("ach.n.herbs", 0)) == 1)
	GameState.flags["ach.n.herbs"] = 4
	GameState.herbs = 9
	GameState.hp = GameState.max_hp - 10
	var g0: int = GameState.gold
	var ha0: int = ash_bal()
	world.drink_potion()
	chk(g, "herbalist at 5th: +15 gold, ash +0", bool(GameState.flags.get("ach.herbalist", false)) and GameState.gold - g0 == 15 and ash_bal() == ha0, "dg=%d da=%d" % [GameState.gold - g0, ash_bal() - ha0])
	g0 = GameState.gold
	GameState.hp = GameState.max_hp - 10
	world.drink_potion()
	GameState.hp = GameState.max_hp - 10
	world.drink_potion()
	chk(g, "6/7th: +0 gold, count 7", GameState.gold == g0 and int(GameState.flags.get("ach.n.herbs", 0)) == 7)

# ---------------------------------------------------------------- D: keys & save

func _norm_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		if typeof(a) == TYPE_STRING or typeof(b) == TYPE_STRING or typeof(a) == TYPE_BOOL or typeof(b) == TYPE_BOOL:
			return str(a) == str(b)
		return absf(float(a) - float(b)) < 1e-6
	return a == b

func _group_D() -> void:
	var g := "KY"
	var bad_ns: Array = []
	for k in GameState.flags:
		var s := String(k)
		if not (s.begins_with("q.") or s.begins_with("ach.") or s.begins_with("meta.") or s.begins_with("ng.") or s.begins_with("ashen.") or s.begins_with("daily.") or s.begins_with("hint.") or s.begins_with("tal.") or s == "ach_brand"):
			bad_ns.append(s)
	chk(g, "flags namespaces q./ach./meta./ng./ashen./daily./hint./tal./ach_brand", bad_ns.is_empty(), str(bad_ns))
	var offenders: Array = []
	for k in GameState.flags:
		if String(k).begins_with("ach.ach"):
			offenders.append(String(k))
	chk(g, "no ach.ach_* keys", offenders.is_empty(), str(offenders))
	var jr: Node = null
	for c in world.get_children():
		if c is Journal:
			jr = c
	if jr != null:
		jr.set_process(false)
	var snap: Dictionary = GameState.flags.duplicate(true)
	GameState.save_game()
	GameState.flags.clear()
	var ok_load: bool = GameState.load_game()
	var same: bool = ok_load and GameState.flags.size() == snap.size()
	if same:
		for k in snap:
			if not GameState.flags.has(k) or not _norm_eq(snap[k], GameState.flags[k]):
				same = false
				break
	chk(g, "flags round-trip deep-equal (incl meta.ash)", same, "snap=%d loaded=%d" % [snap.size(), GameState.flags.size()])
	if jr != null:
		jr.set_process(true)
	var v1 := {"level": 2, "xp": 5, "xp_next": 30, "class_id": "warrior", "has_sword": true,
		"herbs": 2, "slime_kills": 1, "elder_quest": 1, "slime_quest": 0, "seen_intro": true, "hp": 15, "mana": 5}
	var sf := FileAccess.open(SAVE, FileAccess.WRITE)
	sf.store_string(JSON.stringify(v1))
	sf.close()
	ok_load = GameState.load_game()
	chk(g, "v1 legacy loads, flags empty", ok_load and GameState.flags.is_empty())
	var junk := {"v": 2, "gold": 5, "flags": "not-a-dict", "meta": 7}
	sf = FileAccess.open(SAVE, FileAccess.WRITE)
	sf.store_string(JSON.stringify(junk))
	sf.close()
	ok_load = GameState.load_game()
	chk(g, "junk flags: loads, {}", ok_load and GameState.flags.is_empty())

# ---------------------------------------------------------------- E: storm (Ash canon)

func _probe_autosave() -> void:
	# ash-only-grant (campfires: gold 0, ash +1) -> file MUST change via grant_ash save_game()
	# Канон после «одного костра в мире»: гейт — вечный счётчик n.campfires (>=3),
	# три вызова = три отдыха на кругах (campfires_used на гейт больше не смотрит).
	GameState.flags.clear()
	GameState.save_game()
	GameState.flags.clear()
	var before := save_text()
	GameState.campfires_used = {"cf_village": true}
	Achv.on_campfire_used()
	Achv.on_campfire_used()
	Achv.on_campfire_used()
	var after := save_text()
	chk("AS", "ash-only unlock autosaves (file changed, meta.ash inside)", after != before and after.contains("meta.ash"), "before_len=%d after_len=%d" % [before.length(), after.length()])
	chk("AS", "campfires grants +1 ash", ash_bal() == 1, "ash=%d" % ash_bal())

func _storm() -> Dictionary:
	var g0: int = GameState.gold
	var a0: int = ash_bal()
	for i in 400:
		Achv.on_mob_death("slime")
	for i in 400:
		Achv.on_buy()
	for i in 400:
		Achv.on_brew()
	for i in 150:
		GameState.slime_kills += 1
		Achv.on_slime_kill()
	for i in 400:
		Achv.on_herb_drunk()
	# «Один костёр в мире»: ачивка на вечном n.campfires — три отдыха на кругах
	# = три вызова хука (эмуляция: костёр в мире один, счётчик круг переживает).
	GameState.campfires_used = {"cf_village": true}
	Achv.on_campfire_used()
	Achv.on_campfire_used()
	Achv.on_campfire_used()
	# Канон-схема uid (3ea93cb): "chest@x,y" — cave 18,18 / ashen 30,24 / village
	# 37,21 (interactable._uid, dungeon_zone/ashen_zone). «Клад» требует size>=3 —
	# ровно как в игре после трёх открытых сундуков.
	GameState.chest_mark_used("chest@18,18")
	GameState.chest_mark_used("chest@30,24")
	GameState.chest_mark_used("chest@37,21")
	Achv.on_chest_opened()
	GameState.hp = 1
	Achv.on_boss_death()
	GameState.add_gold(185)  # 115 rewards + 185 = 300 -> wealth (ash +1)
	return {"dg": GameState.gold - g0, "da": ash_bal() - a0}

func _group_E() -> void:
	var g := "ST"
	_probe_autosave()
	GameState.flags.clear()
	GameState.gold = 0
	GameState.slime_kills = 0
	var r1: Dictionary = _storm()
	# gold: FB10+H25_30+ALCH20+TREASURE40+HERBAL15+inject185 = 300; ash: H100_2+COLL_2+BREW10_1+CAMP_1+HARDCORE_3+BOSS_3+WEALTH_1 = 13
	chk(g, "storm1 gold delta == 300 (115 rewards + 185 inject, wealth ash-only)", r1.dg == 300, "dg=%d" % r1.dg)
	chk(g, "storm1 ASH balance == 13 (7 ash-rewards canon)", r1.da == 13, "da=%d ash=%d" % [r1.da, ash_bal()])
	var want := ["first_blood", "hunter_25", "hunter_100", "boss_slayer", "alchemist", "brewer_10",
		"campfires", "treasure", "collector", "wealth", "herbalist", "hardcore"]
	var missing: Array = []
	for id in want:
		if not bool(GameState.flags.get("ach." + String(id), false)):
			missing.append(id)
	chk(g, "all 12 unlocked", missing.is_empty(), str(missing))
	chk(g, "ach_brand set (hp<=1)", bool(GameState.flags.get("ach_brand", false)))
	chk(g, "counters 400/400/400", int(GameState.flags.get("ach.n.buys", 0)) == 400 and int(GameState.flags.get("ach.n.brews", 0)) == 400 and int(GameState.flags.get("ach.n.herbs", 0)) == 400)
	chk(g, "counter n.campfires == 3 (вечный канал, гейт ачивки)", int(GameState.flags.get("ach.n.campfires", 0)) == 3)
	var r2: Dictionary = _storm()
	chk(g, "storm2 gold delta == 185 (inject only, zero leak)", r2.dg == 185, "dg=%d" % r2.dg)
	chk(g, "storm2 ASH delta == 0 (idempotence)", r2.da == 0, "da=%d" % r2.da)

# ---------------------------------------------------------------- BR: boss ash source dedup

func _boss_source() -> void:
	var g := "BR"
	chk(g, "ng.boss_0 absent before real boss kill", int(GameState.flags.get("ng.boss_0", 0)) == 0)
	var a0: int = ash_bal()
	GameState.hp = 50
	var b1 = load("res://scripts/brute.gd").new()
	world.add_child(b1)
	b1.setup(world, Vector2i(-40, -40))
	b1.boss = true
	b1.hurt(99999, Vector2.ZERO)
	chk(g, "real boss kill: ng.boss_0 set, +3 ash source", int(GameState.flags.get("ng.boss_0", 0)) == 1 and ash_bal() - a0 == 3, "ng=%s da=%d" % [GameState.flags.get("ng.boss_0", null), ash_bal() - a0])
	var sf := save_text()
	chk(g, "boss ash autosaved (ng.boss_0 + meta.ash in file)", sf.contains("ng.boss_0") and sf.contains("meta.ash"))
	await_free()
	var a1: int = ash_bal()
	var b2 = load("res://scripts/brute.gd").new()
	world.add_child(b2)
	b2.setup(world, Vector2i(-40, -40))
	b2.boss = true
	b2.hurt(99999, Vector2.ZERO)
	chk(g, "2nd boss kill: dedup ng.boss_0 -> +0 ash", ash_bal() == a1, "da=%d" % (ash_bal() - a1))

func await_free() -> void:
	for i in 3:
		pass

# ---------------------------------------------------------------- F: namespaces vs quests

func _group_F() -> void:
	var g := "NS"
	GameState.flags.clear()
	GameState.elder_quest = 1
	QuestsData.refresh(GameState)
	var q1: Array = []
	for k in GameState.flags:
		if String(k).begins_with("q."):
			q1.append(String(k))
	for i in 30:
		Achv.on_mob_death("slime")
		Achv.on_buy()
	QuestsData.refresh(GameState)
	var q2: Array = []
	for k in GameState.flags:
		if String(k).begins_with("q."):
			q2.append(String(k))
	chk(g, "ach hooks do not touch q.* set", str(q1) == str(q2), "%s vs %s" % [str(q1), str(q2)])
	var s1: int = QuestsData.status(GameState, "elder")
	GameState.flags["ach.first_blood"] = true
	GameState.flags["meta.ash"] = 9
	GameState.flags["ng.boss_0"] = 1
	QuestsData.refresh(GameState)
	chk(g, "quest status stable under ach/meta/ng noise", QuestsData.status(GameState, "elder") == s1)
	GameState.save_game()
	GameState.flags.clear()
	GameState.load_game()
	chk(g, "mixed save (q+ach+meta+ng) round-trip", QuestsData.status(GameState, "elder") == s1 and int(GameState.flags.get("meta.ash", 0)) == 9 and int(GameState.flags.get("ng.boss_0", 0)) == 1)
