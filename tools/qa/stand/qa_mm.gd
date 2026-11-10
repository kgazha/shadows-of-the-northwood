extends Node2D
## QA-харнесс миникарты (песочница sand_z2mm, в дифф НЕ входит).
## Прогон: godot --headless res://qa_mm.tscn
## Покрывает: деревня/пещера без регрессов (формат подписи, размеры, POI),
## Пепелище: гейт по y, своя сетка ashen_grid, подписи «a|», блипы портал/сундук,
## Ведьма живым босс-циклом (смерть -> блип гаснет), взятие сундука, герой в
## локальных координатах, сборка без ashen_grid без падения, M-тумблер и
## персист user://minimap_cfg.json, пересборка мира (мёртвая ведьма/взятый
## сундук не возрождаются на радаре).

const Main := "res://scenes/main.tscn"
const SAVE_PATH := "user://save_morkheim.json"
const CFG_PATH := "user://minimap_cfg.json"

var pass_n := 0
var fail_n := 0
var world: Node2D
var mm: Node

func chk(cond: bool, name: String) -> void:
	if cond:
		pass_n += 1
		print("qa_mm ok: ", name)
	else:
		fail_n += 1
		print("qa_mm FAIL: ", name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _repoll() -> void:
	mm._poll_t = 0.0
	# 6 кадров: поллинг живёт в idle (_process), а ждём мы physics — запас
	await _frames(6)

## paint() легален только внутри _draw — зондим через Control-пробу.
func _paint_ok(tag: String) -> void:
	var probe := Control.new()
	probe.set_process(false)
	add_child(probe)
	var done := [false]
	probe.draw.connect(func() -> void:
		mm.paint(probe)
		done[0] = true)
	probe.queue_redraw()
	for i in 10:
		await get_tree().physics_frame
		if done[0]:
			break
	chk(bool(done[0]), "paint() %s: _draw отработал без ошибок" % tag)
	probe.queue_free()

func _poi_of(c: Color) -> Array:
	var out: Array = []
	for p in mm._pois:
		if p["c"] == c:
			out.append(p)
	return out

func _ready() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if FileAccess.file_exists(CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	GameState.seen_cave_intro = true
	GameState.elder_quest = 0
	await _frames(2)
	world = load(Main).instantiate()
	add_child(world)
	await _frames(4)
	mm = Minimap.I
	chk(mm != null, "Minimap.I назначен")
	await _phase_village()
	await _phase_cave()
	await _phase_ashen()
	await _phase_events()
	await _phase_nozone()
	await _phase_toggle()
	await _phase_rebuild()
	var total: int = pass_n + fail_n
	print("QA_MM %d/%d" % [pass_n, total])
	get_tree().quit(0 if fail_n == 0 else 1)

# ---------------------------------------------------------------- деревня
func _phase_village() -> void:
	await _repoll()
	chk(mm._zone == "village", "зона village")
	chk(mm._sig == "v|" + str(world.map_rows), "подпись v|+rows (формат прежний)")
	chk(int(mm._grid_w) == int(world.map_w) and int(mm._grid_h) == int(world.map_h), "сетка 48x30")
	chk(bool(mm._zone_seen), "сетка собрана")
	var ports := _poi_of(Minimap.C_PORTAL)
	var has_cave := false
	var has_ashen := false
	for p in ports:
		if p["t"] == Vector2i(world.CAVE_ENTRANCE_TILE):
			has_cave = true
		if p["t"] == Vector2i(45, 20):
			has_ashen = true
	chk(has_cave, "деревня: блип входа в пещеру")
	chk(has_ashen, "деревня: блип аршины Пепелища (45,20)")
	chk(_poi_of(Minimap.C_FIRE).size() > 0, "деревня: костры на месте")
	chk(_poi_of(Minimap.C_NPC).size() > 0, "деревня: NPC на месте")
	var pt: Vector2i = mm._tile_of(world.player.global_position, Vector2.ZERO, 16.0)
	chk(pt.x >= 0 and pt.y >= 0 and pt.x < mm._grid_w and pt.y < mm._grid_h, "герой в поле сетки")

# ---------------------------------------------------------------- пещера
func _phase_cave() -> void:
	world.apply_area("cave", true)
	await _repoll()
	chk(bool(GameState.in_cave), "in_cave выставлен")
	chk(mm._zone == "cave", "зона cave")
	chk(mm._sig == "c|" + str(world.map_rows), "подпись c|+rows (экс-квирк сохранён)")
	var dz = world.dungeon_zone
	chk(int(mm._grid_w) == int(dz.map_w) and int(mm._grid_h) == int(dz.map_h), "сетка пещеры из dungeon_zone")
	chk(_poi_of(Minimap.C_PORTAL).size() >= 1, "пещера: лестница-блип")
	world.apply_area("village", true)
	await _repoll()
	chk(mm._zone == "village" and mm._sig.begins_with("v|"), "обратно: village")

# ---------------------------------------------------------------- Пепелище
func _phase_ashen() -> void:
	world.apply_area("ashen", true)
	await _frames(2)
	chk(world.player.global_position.y > world.ASHEN_OFFSET.y, "гейт: y героя > ASHEN_OFFSET.y")
	await _repoll()
	var az = world.ashen_grid
	chk(mm._zone == "ashen", "зона ashen")
	chk(mm._sig == "a|" + str(az.map_rows), "третья подпись a|+ashen rows")
	chk(int(mm._grid_w) == int(az.map_w) and int(mm._grid_h) == int(az.map_h), "сетка 40x30 из ashen_grid")
	chk(bool(mm._zone_seen), "ashen-сетка собрана")
	# портал: тайл = приведение мировых координат к локальным
	var ptl: Vector2i = mm._tile_of(az.portal_node.global_position, world.ASHEN_OFFSET, 16.0)
	var ports := _poi_of(Minimap.C_PORTAL)
	chk(ports.size() == 1 and ports[0]["t"] == ptl, "блип портала на своём тайле")
	var chests := _poi_of(Minimap.C_CHEST)
	chk(chests.size() == 1, "блип сундука есть")
	# герой: локальные координаты внутри 40x30 (доказательство вычета ASHEN_OFFSET)
	var pt: Vector2i = mm._tile_of(world.player.global_position, mm._zone_base(), 16.0)
	chk(mm._zone_base() == world.ASHEN_OFFSET, "база ashen = ASHEN_OFFSET")
	chk(pt.x >= 0 and pt.y >= 0 and pt.x < 40 and pt.y < 30, "герой в локальных тайлах 40x30")
	# живой цикл: мобы + Ведьма в группах
	var bosses := _bosses_in_ashen()
	chk(bosses.size() == 1, "Ведьма в группе boss (блип s=4)")
	var enemies := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and (e as Node2D).global_position.y > world.ASHEN_OFFSET.y:
			enemies += 1
	chk(enemies >= 5, "enemy-мобы Пепелища на радаре (%d)" % enemies)
	await _paint_ok("ashen")

func _bosses_in_ashen() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and (b as Node2D).global_position.y > world.ASHEN_OFFSET.y:
			out.append(b)
	return out

# ---------------------------------------------------------------- события
func _phase_events() -> void:
	var az = world.ashen_grid
	# сундук взят: узел снят + флаг; «раунд-трип» зон — тот же путь, что у
	# F9/смены зоны, при котором деревенские/пещерные POI тоже пересобираются
	GameState.set_flag("ashen.chest", "taken")
	az.chest_node.queue_free()
	await _frames(4)
	world.apply_area("village", true)
	await _repoll()
	world.apply_area("ashen", true)
	await _repoll()
	chk(_poi_of(Minimap.C_CHEST).is_empty(), "сундук взят — блип погас (после смены зоны)")
	chk(_poi_of(Minimap.C_PORTAL).size() == 1, "раунд-трип: портал снова один")
	# смерть Ведьмы -> живой цикл снимает блип, флаг dead
	var witch = az.boss_node
	witch.hurt(999, witch.global_position + Vector2(0, 20))
	await _frames(6)
	chk(String(GameState.flags.get("ashen.boss", "")) == "dead", "флаг ashen.boss=dead")
	chk(_bosses_in_ashen().is_empty(), "Ведьма вне группы boss — блип погас")
	await _paint_ok("после смерти Ведьмы")

# ---------------------------------------------------------------- мир без Пепелища
func _phase_nozone() -> void:
	var az = world.ashen_grid
	world.ashen_grid = null
	await _repoll()
	chk(mm._zone == "ashen" and not bool(mm._zone_seen), "нет az: тихо, без сетки, без падения")
	chk(mm._grid_tex == null, "нет az: _grid_tex сброшена")
	await _paint_ok("без az")
	world.ashen_grid = az
	await _repoll()
	chk(bool(mm._zone_seen) and int(mm._grid_w) == 40, "az вернули — сетка собралась")

# ---------------------------------------------------------------- M-тумблер
func _phase_toggle() -> void:
	Minimap.set_on(false)
	chk(not Minimap.is_on(), "set_on(false)")
	await _frames(2)
	chk(not bool(mm._layer.visible), "радар скрыт на следующий кадр")
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	chk(f != null, "cfg-файл записан")
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		chk(typeof(d) == TYPE_DICTIONARY and d.get("on") == false, "cfg: on=false на диске")
	mm.toggle()
	chk(Minimap.is_on(), "toggle -> вкл")
	await _frames(2)
	chk(bool(mm._layer.visible), "радар виден")
	f = FileAccess.open(CFG_PATH, FileAccess.READ)
	if f != null:
		var d2: Variant = JSON.parse_string(f.get_as_text())
		chk(d2.get("on") == true, "cfg: on=true на диске")

# ---------------------------------------------------------------- пересборка
func _phase_rebuild() -> void:
	world.queue_free()
	await _frames(4)
	world = load(Main).instantiate()
	add_child(world)
	await _frames(4)
	mm = Minimap.I
	await _repoll()
	chk(mm._zone == "village" and mm._sig.begins_with("v|"), "новый мир: деревня как раньше")
	world.apply_area("ashen", true)
	await _repoll()
	chk(mm._zone == "ashen", "новый мир: ashen определяется")
	chk(_poi_of(Minimap.C_PORTAL).size() == 1, "новый мир: портал на месте")
	chk(_poi_of(Minimap.C_CHEST).is_empty(), "новый мир: взятый сундук не возродился")
	chk(_bosses_in_ashen().is_empty(), "новый мир: мёртвая Ведьма не заспавнена")
