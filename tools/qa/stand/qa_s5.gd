extends Node
## QA-харнесс s5: «воскресает» ли убитый пещерный босс при рестарте процесса.
## Исторический корень (спавн до load_game()) исправлен в world.gd; стенд
## остался как регресс-гейт: cave_state=2 в сейве => brute не спавнится.

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

# Только пещерный босс (brute.gd): ведьма mob_boss2 тоже в группе "boss".
func _cave_bosses() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("boss"):
		if b == null or b.is_queued_for_deletion():
			continue
		var s = b.get_script()
		if s != null and String(s.resource_path).contains("brute.gd"):
			out.append(b)
	return out

func _ready() -> void:
	# сейв «босс уже мёртв»: cave_state=2 + boss_defeated
	# PIN-SEED 42 (T4): сид приезжает в сейве и load_game() применит его до
	# _build_cave() — генераторная пещера стенда детерминирована. Проверки
	# стенда координатно-инвариантны (счётчики brute), пин — для воспроизводимости.
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	GameState.run_seed = 42
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	GameState.cave_state = 2
	GameState.boss_defeated = true
	GameState.seen_boss_intro = true
	GameState.gold = 100
	ck(GameState.save_game(), "S5 save with boss_defeated written")
	GameState.cave_state = 0
	GameState.boss_defeated = false
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	_run()

func _run() -> void:
	await frames(5)
	ck(GameState.boss_defeated, "S5 save loaded (boss_defeated=true)")
	# В группе "boss" кроме пещерного босса (brute.gd) числится и NG+ ведьма
	# (mob_boss2.gd, спавн в /Ashen/ gated by ashen.boss). Стенд проверяет
	# ГЕЙТ ПЕЩЕРНОГО босса (boss_defeated / cave_state>=2) — фильтруем по скрипту.
	var bosses := 0
	for b in _cave_bosses():
		bosses += 1
	print("NOTE cave bosses spawned in-process with boss_defeated=true: %d" % bosses)
	ck(bosses == 0, "S5 dead boss must not respawn after restart", "bosses=%d" % bosses)
	if bosses > 0:
		print("BUG S5 brute respawns despite cave_state>=2: spawn gate failed after load_game()")
		# экономическая сторона: добить повторно = 25-40 золота за каждый рестарт
		var b = _cave_bosses()[0]
		GameState.gold = 0
		b.call("hurt", 99999, Vector2.ZERO)
		print("NOTE re-kill boss gold gained=%d cave_state=%d" % [GameState.gold, GameState.cave_state])
		ck(GameState.gold >= 25 and GameState.gold <= 40, "S5 re-kill pays loot table", "g=%d" % GameState.gold)
		ck(GameState.cave_state == 2, "S5 cave_state idempotent")
	print("S5 DONE fails=%d" % fails["n"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	get_tree().quit(0)
