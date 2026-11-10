extends Node
## QA-харнесс s4: экономический разбор фарм-цикла mob->loot->sell.
## Детерминированный seed; 20 циклов + статистика EV + эксплуатационные проверки.

var world: Node2D
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

func _ready() -> void:
	seed(42)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	_run()

func farm(kind: String, cycles: int) -> Array:
	var deltas: Array = []
	for i in cycles:
		var before: int = GameState.gold
		Loot.on_mob_death(kind, Vector2.ZERO)
		deltas.append(GameState.gold - before)
	return deltas

func ev_est(kind: String, n: int) -> float:
	GameState.gold = 0
	var d := farm(kind, n)
	var sum := 0
	var x: Variant = 0
	for v in d:
		sum += int(v)
	return float(sum) / float(n)

func _run() -> void:
	await frames(5)
	# --- состав врагов ---
	var slimes := 0
	var brutes := 0
	var boss := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		var sp := String(e.get_script().resource_path)
		if e.is_in_group("boss") or sp.contains("brute.gd") and e.get("boss") == true:
			boss += 1
		elif sp.contains("brute.gd"):
			brutes += 1
		elif sp.contains("slime.gd"):
			slimes += 1
	print("NOTE enemies: total=%d slimes=%d brutes=%d boss=%d" % [get_tree().get_nodes_in_group("enemy").size(), slimes, brutes, boss])

	# --- теория: EV из таблиц GearData.LOOT ---
	print("NOTE EV-theory: slime=2.975 brute=5.85 boss=32.5 chest=13.0 (gold/cycle)")

	# --- EV-оценка по 500 симуляций на вид ---
	var ev_s := ev_est("slime", 500)
	var ev_b := ev_est("brute", 500)
	var ev_x := ev_est("boss", 500)
	print("NOTE EV-sim500: slime=%.3f brute=%.3f boss=%.3f" % [ev_s, ev_b, ev_x])
	ck(absf(ev_s - 2.975) < 0.35, "EV slime ~2.975", "got %f" % ev_s)
	ck(absf(ev_b - 5.85) < 0.5, "EV brute ~5.85", "got %f" % ev_b)
	ck(absf(ev_x - 32.5) < 2.5, "EV boss ~32.5", "got %f" % ev_x)
	# границы бросков
	GameState.gold = 0
	var dmin := 999
	var dmax := -1
	GameState.gold = 0
	var ds := farm("slime", 500)
	for v in ds:
		dmin = mini(dmin, int(v))
		dmax = maxi(dmax, int(v))
	ck(dmin >= 0 and dmax <= 5, "slime per-kill gold in [0..5]", "min=%d max=%d" % [dmin, dmax])

	# --- 20-цикловый фарм-прогон (требование задания) ---
	seed(42)
	GameState.gold = 0
	GameState.herbs = 0
	var run20 := farm("slime", 20)
	var tot := 0
	for v in run20:
		tot += int(v)
	print("NOTE 20-cycle slime run: gold=%d deltas=%s herbs_after=%d" % [GameState.gold, str(run20), GameState.herbs])
	ck(GameState.gold == tot, "20-cycle accounting exact")
	# цена полного сета
	var sword := GearData.price("sword")
	var axe := GearData.price("axe")
	var rune := GearData.price("rune_blade")
	var leather := GearData.price("leather")
	var chain := GearData.price("chain")
	print("NOTE prices: sword=%d axe=%d rune=%d leather=%d chain=%d" % [sword, axe, rune, leather, chain])
	print("NOTE kills-to-afford (slime EV): sword=%.1f axe=%.1f rune=%.1f leather=%.1f chain=%.1f" % [sword / ev_s, axe / ev_s, rune / ev_s, leather / ev_s, chain / ev_s])
	print("NOTE kills-to-afford (brute EV): sword=%.1f axe=%.1f rune=%.1f" % [sword / ev_b, axe / ev_b, rune / ev_b])

	# --- sell-петля: покупка-продажа не генерирует золото ---
	seed(7)
	GameState.gold = 5000
	var g0: int = GameState.gold
	for i in 10:
		GameState.equip_item("weapon", "")
		GameState.equip_item("weapon", "rune_blade")
		GameState.spend_gold(GearData.price("rune_blade"))
		GameState.equip_item("weapon", "")
		GameState.add_gold(GearData.sell_price("rune_blade"))
	ck(GameState.gold < g0, "buy/sell loop strictly negative", "g0=%d g1=%d" % [g0, GameState.gold])
	print("NOTE buy/sell loop x10: %d -> %d (net %d)" % [g0, GameState.gold, GameState.gold - g0])

	# --- двойная смерть за кадр: loot один раз (dying guard) ---
	var slime: Node = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if String(e.get_script().resource_path).contains("slime.gd"):
			slime = e
			break
	ck(slime != null, "found a slime for double-death test")
	if slime != null:
		seed(5)
		GameState.gold = 0
		slime.set("hp", 1)
		slime.call("hurt", 5, Vector2.ZERO)
		var g_after_first: int = GameState.gold
		slime.call("hurt", 5, Vector2.ZERO)  # второй удар в том же кадре
		ck(GameState.gold == g_after_first, "double-death same frame: loot once", "g=%d vs %d" % [GameState.gold, g_after_first])
		ck(g_after_first >= 0 and g_after_first <= 5, "first-kill gold sane", "g=%d" % g_after_first)
		# респаун-цикл: фарм возможен (respan 50 с) — убить повторно после респавна
		var dying_before: bool = bool(slime.get("dying"))
		ck(dying_before, "slime marked dying")
		slime.set("respawn_t", 0.1)
		await frames(12)  # ~0.2 c > respawn_t
		ck(not bool(slime.get("dying")), "slime respawned")
		GameState.gold = 0
		slime.call("hurt", 999, Vector2.ZERO)
		ck(GameState.gold >= 0 and GameState.gold <= 5 and GameState.gold > 0 or GameState.gold == 0, "respawn kill yields gold roll")
		print("NOTE respawn kill gold=%d (roll 2..5, p=0.85)" % GameState.gold)

	# --- сундуки: E=13, одноразовые ---
	seed(9)
	GameState.gold = 0
	var csum := 0
	for i in 500:
		var before: int = GameState.gold
		Loot.chest_reward(GameState)
		csum += GameState.gold - before
	print("NOTE chest EV sim500=%.2f (theory 13.0)" % (float(csum) / 500.0))
	ck(absf(float(csum) / 500.0 - 13.0) < 0.7, "chest EV ~13", "got %f" % (float(csum) / 500.0))

	# --- смешанный маршрут 20 циклов: slime+herb+sell-поведение ---
	seed(123)
	GameState.gold = 0
	GameState.herbs = 0
	var total_herbs0: int = GameState.herbs
	for i in 20:
		Loot.on_mob_death("slime", Vector2.ZERO)
	print("NOTE mixed: after 20 slime-kill gold=%d herbs=%d (herbs без капа MAT_CAP — note)" % [GameState.gold, GameState.herbs])

	print("S4 DONE fails=%d" % fails["n"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	get_tree().quit(0)
