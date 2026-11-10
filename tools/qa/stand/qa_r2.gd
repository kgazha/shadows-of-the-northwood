extends Node
## QA-ретест mержа 75b5b69, процесс-2 (РЕАЛЬНЫЙ рестарт после qa_r1):
## п.1 — добитый босс не возродился при загрузке сейва, повторного лута нет;
## п.4б — тумблер показывает верное состояние из user://clickmove_cfg.json,
##        RMB-приказ не принимается при выкл и принимается при вкл.

var world: Node2D
var sm
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

func push_key(phys: int) -> void:
	var e := InputEventKey.new()
	e.keycode = phys
	e.physical_keycode = phys
	e.pressed = true
	get_tree().root.push_input(e)
	var r := InputEventKey.new()
	r.keycode = phys
	r.physical_keycode = phys
	r.pressed = false
	get_tree().root.push_input(r)

func esc() -> void:
	push_key(KEY_ESCAPE)

func read_clickmove_cfg() -> Variant:
	if not FileAccess.file_exists("user://clickmove_cfg.json"):
		return null
	var f := FileAccess.open("user://clickmove_cfg.json", FileAccess.READ)
	if f == null:
		return null
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return v

func _ready() -> void:
	# ВАЖНО: сейв и clickmove_cfg НЕ удаляем — это и есть проверка рестарта.
	print("NOTE cfg at start: %s" % str(read_clickmove_cfg()))
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	for c in world.get_children():
		if c is SettingsMenu:
			sm = c
	print("NOTE nodes: sm=%s ClickMove.I=%s" % [sm != null, ClickMove.I != null])
	_run()

func _run() -> void:
	await frames(5)

	# --- G (п.1): добитый босс после рестарта ---
	ck(GameState.boss_defeated and GameState.cave_state == 2, "G save loaded (boss dead, cave 2)", "def=%s cs=%d" % [GameState.boss_defeated, GameState.cave_state])
	# В группе "boss" сидит и NG+ ведьма (mob_boss2) — считаем только пещерного
	# brute.gd, гейт которого (boss_defeated) здесь и проверяется.
	var bosses := 0
	for b in get_tree().get_nodes_in_group("boss"):
		var s = b.get_script()
		if s != null and String(s.resource_path).contains("brute.gd"):
			bosses += 1
	print("NOTE R2 bosses in world after restart: %d" % bosses)
	ck(bosses == 0, "G dead boss did NOT respawn on restart")
	var dz = world.get("dungeon_zone")
	var bnode = dz.get("boss_node") if dz != null else null
	ck(bnode == null or not is_instance_valid(bnode), "G no boss node to re-loot")
	ck(GameState.gold == 555, "G gold unchanged on restart (no loot)", "g=%d" % GameState.gold)

	# --- H (п.4б): верное состояние тумблера после рестарта + приказ выкл ---
	var cfg1: Variant = read_clickmove_cfg()
	ck(typeof(cfg1) == TYPE_DICTIONARY and bool(cfg1.get("on", true)) == false, "H cfg survived restart on=false", str(cfg1))
	ck(not bool(ClickMove.is_on()), "H ClickMove.is_on()==false from file")
	esc()
	ck(sm != null and sm.is_open(), "H settings opened")
	ck(sm.cm_row.visible and sm._cm_api != null, "H row visible with real api")
	ck(not bool(sm.cm_btn.is_pressed()) and sm.cm_btn.text == "Ход по правому клику — выкл", "H reopen shows correct off state", sm.cm_btn.text)
	sm.close()
	await frames(2)
	# приказ при выкл: заведомо проходимая далёкая клетка — отказ
	var p := _far_walkable()
	if p == Vector2.INF:
		print("NOTE H no walkable far tile found — order test skipped")
	else:
		ck(not ClickMove.I.order_to(p), "H order rejected while off", "point=%s" % str(p))
		ck(not ClickMove.I.is_walking(), "H not walking after rejected order")

	# --- I (п.4в): включить — приказ принимается ---
	esc()
	sm.cm_btn.set_pressed(true)
	await frames(2)
	var cfg2: Variant = read_clickmove_cfg()
	ck(typeof(cfg2) == TYPE_DICTIONARY and bool(cfg2.get("on", false)) == true, "I toggle on wrote cfg on=true", str(cfg2))
	ck(bool(ClickMove.is_on()), "I is_on true after toggle")
	sm.close()
	await frames(2)
	if p != Vector2.INF:
		ck(ClickMove.I.order_to(p), "I order accepted while on", "point=%s" % str(p))
		ck(ClickMove.I.is_walking(), "I walking after order")
		ClickMove.I.cancel()
		ck(not ClickMove.I.is_walking(), "I cancel stops walking")

	print("R2 DONE fails=%d" % fails["n"])
	get_tree().quit(0)

## Далёкая проходимая клетка текущей зоны — мировые координаты центра тайла.
func _far_walkable() -> Vector2:
	var base: Vector2 = world.CAVE_OFFSET if GameState.in_cave else Vector2.ZERO
	var ts := float(world.TILE)
	var pl: Node2D = world.get("player")
	if pl == null:
		return Vector2.INF
	var mine := Vector2i(int(floor((pl.global_position.x - base.x) / ts)), int(floor((pl.global_position.y - base.y) / ts)))
	var ring := [Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6),
		Vector2i(5, 3), Vector2i(-5, 3), Vector2i(5, -3), Vector2i(-5, -3),
		Vector2i(3, 5), Vector2i(-3, 5), Vector2i(3, -5), Vector2i(-3, -5)]
	for d in ring:
		var t: Vector2i = mine + d
		if _walk(t):
			var gw: Vector2 = base + world.tile_to_world(t)
			return gw
	return Vector2.INF

func _walk(t: Vector2i) -> bool:
	if GameState.in_cave:
		var dz = world.get("dungeon_zone")
		return dz != null and dz.has_method("cell_walkable") and dz.cell_walkable(t)
	if t.x < 0 or t.y < 0 or t.y >= int(world.map_h) or t.x >= int(world.map_w):
		return false
	var row := String(world.map_rows[t.y])
	if t.x >= row.length():
		return false
	var ch := row[t.x]
	if not world.CHAR_TO_TILE.has(ch):
		return true
	return not (int(world.CHAR_TO_TILE[ch]) in world.BLOCKING)
