extends Node2D
## Общая база харнессов QA боевой волны (sand_mb). Не часть игры.

const Classes := preload("res://scripts/classes_data.gd")

var _pass := 0
var _fail := 0
var _failed: Array = []
var toasts: Array = []
var world: Node2D = null
var stub: CharacterBody2D = null
var real_player: Node2D = null

func boot(save: Dictionary) -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(save))
	f = null
	var si := load("res://scenes/main.tscn")
	world = si.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.input_locked = false
	if world.player != null and is_instance_valid(world.player):
		real_player = world.player
		world.player.set_physics_process(false)
		world.player.visible = false
		world.player.global_position = Vector2(-9000.0, -9000.0)
	stub = PStub.new()
	world.add_child(stub)
	stub.global_position = Vector2(400.0, 400.0)
	world.player = stub

func park(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.set_physics_process(false)
	if node is Node2D:
		(node as Node2D).visible = false

func find_mob(parent: Node, script_substr: String) -> Array:
	var out: Array = []
	for c in parent.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path.contains(script_substr):
			out.append(c)
	return out

func check(what: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("PASS: %s" % what)
	else:
		_fail += 1
		_failed.append(what)
		print("FAIL: %s" % what)

func done() -> void:
	print("RESULT: %d pass / %d fail" % [_pass, _fail])
	if _failed.size() > 0:
		print("FAILED: %s" % ", ".join(PackedStringArray(_failed)))
	get_tree().quit(0 if _fail == 0 else 1)

func n_toast(substr: String) -> int:
	var n := 0
	for t in toasts:
		if String(t).contains(substr):
			n += 1
	return n

func clear_toasts() -> void:
	toasts.clear()

## Прокачка кадров с поддержанием HP героя (реген/сла́ймы не убивают стенд).
func pump(n: int) -> void:
	for i in range(n):
		GameState.hp = GameState.max_hp
		GameState.input_locked = false
		await get_tree().physics_frame

## Прокачка без вмешательства (для тестов смерти/заморозки).
func pump_raw(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func until(cond: Callable, max_frames: int) -> bool:
	for i in range(max_frames):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
		if bool(cond.call()):
			return true
	return false

func tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / 16.0), int(pos.y / 16.0))

func cave_global(w: Node2D, t: Vector2i) -> Vector2:
	var dz: Node2D = w.dungeon_zone
	return dz.global_position + dz.tile_to_world(t)

func village_tile_walkable(t: Vector2i) -> bool:
	return bool(world.call("_village_walkable", t))

func cave_tile_walkable(t: Vector2i) -> bool:
	return bool(world.dungeon_zone.call("cell_walkable", t))

func save_for(cave_state: int) -> Dictionary:
	return {
		"v": 2, "class_id": "warrior", "level": 1, "xp": 0, "xp_next": 99999,
		"max_hp": 12, "hp": 12, "mana": 0,
		"seen_intro": true, "seen_cave_intro": true, "seen_boss_intro": true,
		"cave_state": cave_state, "in_cave": false,
		"gold": 0, "gear": {"weapon": "", "armor": ""}, "flags": {},
		# T4: пин канон-сида — пещера детерминирована (якори/мобы от генератора).
		"run_seed": 42,
	}

class PStub extends CharacterBody2D:
	var roll_t := 0.0
	var hurt_cd := 0.0
	var skill_cd: Array = [0.0, 0.0, 0.0, 0.0]
	var dmg_log: Array = []
	func _ready() -> void:
		collision_layer = 1
		collision_mask = 0
		add_to_group("player")
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(10, 8)
		cs.shape = sh
		add_child(cs)
	func take_damage(n: int) -> void:
		dmg_log.append(n)
	func cast_skill(_i: int) -> void:
		pass
	func cancel_orders() -> void:
		pass
