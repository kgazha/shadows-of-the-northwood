extends Node
## QA ребаланса лута (sand_bt, база 8e73bd1). НЕ для мержа.
## Аналитика + sim 500/вид на фикс-сиде. Вызывает Loot.on_mob_death напрямую
## (тот же путь, что хуки мобов; GameState/achievements живут).

var fails := 0

func _ready() -> void:
	_table()
	await _achv_new_kind()
	await _sim()
	await _brute_real_path()
	print("QA BT: fails=", fails, " -> ", ("ALL PASS" if fails == 0 else "FAILS!"))
	get_tree().quit(0 if fails == 0 else 1)

func _table() -> void:
	var t: Variant = GearData.LOOT
	_check(t.get("brute") == [{"gold": [6, 9], "chance": 0.9}, {"item": "potion", "chance": 0.12, "qty": 1}], "brute row [6,9]")
	_check(t.get("brute_t2") == [{"gold": [8, 12], "chance": 0.9}, {"item": "potion", "chance": 0.12, "qty": 1}], "brute_t2 row [8,12]")
	_check(t.get("brute_t3") == [{"gold": [10, 15], "chance": 0.9}, {"item": "potion", "chance": 0.12, "qty": 1}], "brute_t3 row [10,15]")
	_check(t.get("swarmling") == [{"gold": [1, 3], "chance": 0.8}, {"item": "herb", "chance": 0.08, "qty": 1}], "swarmling 0.8+herb0.08")
	# нет регрессий по чужим строкам
	_check(t.get("slime") == [{"gold": [2, 5], "chance": 0.85}, {"item": "herb", "chance": 0.12, "qty": 1}], "slime untouched")
	_check(t.get("boss") == [{"gold": [25, 40], "chance": 1.0}, {"item": "potion", "chance": 1.0, "qty": 1}], "boss untouched")
	_check(t.get("archer") == [{"gold": [6, 11], "chance": 0.8}, {"item": "herb", "chance": 0.15, "qty": 1}], "archer untouched")
	_check(t.get("wraith") == [{"gold": [10, 18], "chance": 0.9}, {"item": "potion", "chance": 0.15, "qty": 1}], "wraith untouched")

func _achv_new_kind() -> void:
	# «Первая кровь» должна сработать с НОВЫМ kind (brute_t3) и не сломать счётчики
	GameState.set_flag("ach.first_blood", false)
	GameState.gold = 0
	var g0: int = GameState.gold
	Loot.on_mob_death("brute_t3", Vector2(10, 10))
	await get_tree().physics_frame
	_check(bool(GameState.get_flag("ach.first_blood", false)), "first_blood unlocks via brute_t3")
	_check(GameState.gold >= g0, "no crash on new kind, gold sane")

func _sim() -> void:
	var kinds: Array[String] = ["brute", "brute_t2", "brute_t3", "swarmling"]
	# аналитические EV золота за убийство
	var ev := {"brute": 0.9 * 7.5, "brute_t2": 0.9 * 10.0, "brute_t3": 0.9 * 12.5, "swarmling": 0.8 * 2.0}
	for kind: String in kinds:
		seed(20261110)
		GameState.gold = 0
		GameState.herbs = 0
		GameState.brewed_potions = 0
		for i: int in range(500):
			Loot.on_mob_death(kind, Vector2(5, 5))
		var g: int = GameState.gold
		var expect: float = ev[kind] * 500.0
		var rel: float = absf(float(g) - expect) / expect
		print("SIM %s: gold=%d ev*500=%.0f rel=%.3f herbs=%d brewed=%d" % [kind, g, expect, rel, GameState.herbs, GameState.brewed_potions])
		_check(rel < 0.05, "sim %s gold within 5%%: %d vs %.0f" % [kind, g, expect])
	if true:
		# swarmling herb-частота ~0.08
		seed(20261110)
		GameState.herbs = 0
		for i: int in range(500):
			Loot.on_mob_death("swarmling", Vector2(5, 5))
		print("SIM swarmling herbs/500=", GameState.herbs, " (EV 40)")
		_check(GameState.herbs >= 20 and GameState.herbs <= 65, "swarmling herb rate sane")

func _brute_real_path() -> void:
	# реальный hurt() реального brute.gd: боссов-ветку не трогаем, только boss=false
	var BR := load("res://scripts/brute.gd")
	var ranges := {1: [6, 9], 2: [8, 12], 3: [10, 15]}
	for tier: int in [1, 2, 3]:
		seed(20261110 + tier)
		var seen := 0
		var ok_all := true
		for i: int in range(30):
			var b = BR.new()
			b.boss = false
			b.tier = tier
			b.hp = 1
			b.kill_xp = 0  # без XP-шума (левел-апы/ачивки не дают золота в этом тесте)
			GameState.gold = 0
			b.hurt(99, Vector2(1, 1))
			await get_tree().physics_frame  # queue_free отработал, но gold уже начислен до free
			var g: int = GameState.gold
			if g == 0:
				continue  # шанс 0.9 не сыграл
			seen += 1
			if g < ranges[tier][0] or g > ranges[tier][1]:
				ok_all = false
				print("  bad drop tier%d gold=%d" % [tier, g])
		print("SIM brute real-path tier%d: drops=%d/30 ok=%s range=%s" % [tier, seen, ok_all, ranges[tier]])
		_check(ok_all and seen >= 20, "tier%d gold drops within %s (%d/30)" % [tier, str(ranges[tier]), seen])

func _check(ok: bool, name: String) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		fails += 1
