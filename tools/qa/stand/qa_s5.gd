extends Node
## QA-харнесс s5: «воскресает» ли убитый босс при рестарте процесса
## (спавн пещеры исполняется до GameState.load_game()).

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
	# сейв «босс уже мёртв»: cave_state=2 + boss_defeated
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
	var bosses := 0
	for b in get_tree().get_nodes_in_group("boss"):
		bosses += 1
	print("NOTE bosses spawned in-process with boss_defeated=true: %d" % bosses)
	ck(bosses == 0, "S5 dead boss must not respawn after restart", "bosses=%d" % bosses)
	if bosses > 0:
		print("BUG S5 boss respawns despite cave_state>=2: dungeon built before load_game(), spawn gate saw default false")
		# экономическая сторона: добить повторно = 25-40 золота за каждый рестарт
		var b = get_tree().get_nodes_in_group("boss")[0]
		GameState.gold = 0
		b.call("hurt", 99999, Vector2.ZERO)
		print("NOTE re-kill boss gold gained=%d cave_state=%d" % [GameState.gold, GameState.cave_state])
		ck(GameState.gold >= 25 and GameState.gold <= 40, "S5 re-kill pays loot table", "g=%d" % GameState.gold)
		ck(GameState.cave_state == 2, "S5 cave_state idempotent")
	print("S5 DONE fails=%d" % fails["n"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	get_tree().quit(0)
