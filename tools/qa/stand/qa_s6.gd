extends Node
## QA s6 (шаг B): EV лута всех архетипов — сид-фиксированная симуляция 500 убийств
## по таблицам GearData.LOOT (семантика loot.gd: шанс на строку, равномерный
## gold-ролл) + теория + сверка с РЕАЛЬНЫМ Loot.on_mob_death (global RNG) + сундук.

const N := 500
const SEED := 20261110
const KINDS := ["slime", "brute", "boss", "swarmling", "archer", "wraith"]
const PRICES := {"sword": 80, "axe": 160, "rune_blade": 320, "leather": 60, "chain": 180}
var fails := {"n": 0}

func ck(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		print("PASS %s" % name)
	else:
		fails["n"] += 1
		print("FAIL %s :: %s" % [name, detail])

func theory_gold(kind: String) -> float:
	var t: Variant = GearData.LOOT.get(kind, [])
	var ev := 0.0
	for e in (t as Array):
		var d: Dictionary = e
		if d.has("gold"):
			ev += float(d.get("chance", 0.0)) * (float(d["gold"][0]) + float(d["gold"][1])) / 2.0
	return ev

func theory_item(kind: String) -> Dictionary:  # herb/potion units per kill
	var res := {"herb": 0.0, "potion": 0.0}
	var t: Variant = GearData.LOOT.get(kind, [])
	for e in (t as Array):
		var d: Dictionary = e
		if d.has("item"):
			res[String(d["item"])] = float(res[String(d["item"])]) + float(d.get("chance", 0.0)) * maxi(1, int(d.get("qty", 1)))
	return res

func _ready() -> void:
	print("SEED=%d N=%d" % [SEED, N])
	# --- симуляция на сид-фиксированном RNG (semantика loot.gd) ---
	for kind in KINDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED
		var table: Variant = GearData.LOOT.get(kind, [])
		var gold_total := 0
		var herb := 0
		var potion := 0
		for i in N:
			for e in (table as Array):
				var d: Dictionary = e
				if rng.randf() > float(d.get("chance", 0.0)):
					continue
				if d.has("gold"):
					gold_total += rng.randi_range(int(d["gold"][0]), int(d["gold"][1]))
				elif d.has("item"):
					if String(d.get("item", "")) == "herb":
						herb += maxi(1, int(d.get("qty", 1)))
					else:
						potion += maxi(1, int(d.get("qty", 1)))
		var sim_g := float(gold_total) / float(N)
		var th_g := theory_gold(kind)
		var ti: Dictionary = theory_item(kind)
		print("NOTE EV %-10s sim=%.3f theory=%.3f | herb sim=%d th=%.2f | potion sim=%d th=%.2f" % [kind, sim_g, th_g, herb, ti["herb"], potion, ti["potion"]])
		var sd := maxf(0.15, th_g * 0.0) + sqrt(sim_g + 1.0)  # грубая дисперсная оценка
		ck(absf(sim_g - th_g) <= 3.0 * sd / sqrt(float(N)) + 0.05, "EV %s sim≈theory" % kind, "sim=%.3f th=%.3f" % [sim_g, th_g])
	# --- сундук: 500 открытий (semantica Loot.chest_reward: gold 8..18 + 50% заряд) ---
	var rngc := RandomNumberGenerator.new()
	rngc.seed = SEED + 1
	var cg := 0
	var cdrop := 0
	for i in N:
		cg += rngc.randi_range(8, 18)
		if rngc.randf() < 0.5:
			cdrop += 1
	print("NOTE EV chest      sim=%.3f theory=13.000 | drop sim=%d th=%.2f" % [float(cg) / float(N), cdrop, 0.5])
	ck(absf(float(cg) / float(N) - 13.0) <= 0.5, "EV chest sim≈theory", "sim=%.3f" % (float(cg) / float(N)))

	# --- сверка с реальным кодом: Loot.on_mob_death 500×/kind (global RNG) ---
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	GameState.herbs = 0
	GameState.brewed_potions = 0
	for kind in ["swarmling", "archer", "wraith", "slime", "brute"]:
		GameState.gold = 0
		for i in N:
			Loot.on_mob_death(kind, Vector2.ZERO)
		var real_g := float(GameState.gold) / float(N)
		var th := theory_gold(kind)
		print("NOTE REAL %-10s gold/kill=%.3f (theory %.3f), herbs=%d potions=%d" % [kind, real_g, th, GameState.herbs, GameState.brewed_potions])
		ck(absf(real_g - th) <= maxf(0.25, th * 0.12), "REAL Loot %s matches theory" % kind, "real=%.3f th=%.3f" % [real_g, th])

	# --- сводная таблица: смёртов до покупки (чистый фарм одного моба) ---
	for kind in KINDS:
		var ev := theory_gold(kind)
		var line := "NOTE KILLS %-10s ev=%.3f" % [kind, ev]
		for pid in ["sword", "axe", "rune_blade", "leather", "chain"]:
			var pr := int(PRICES[pid])
			line += " %s=%d" % [pid, int(ceil(float(pr) / maxf(ev, 0.001)))]
		print(line)
	var cline := "NOTE KILLS chest      ev=13.000"
	for pid in ["sword", "axe", "rune_blade", "leather", "chain"]:
		cline += " %s=%d" % [pid, int(ceil(float(int(PRICES[pid])) / 13.0))]
	print(cline)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	print("S6 DONE fails=%d" % fails["n"])
	get_tree().quit(0)
