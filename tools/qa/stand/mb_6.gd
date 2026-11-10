extends "res://mb_base.gd"
## Кейс 6: стрела лучника и input_locked (фикс N1). В паузе мира стрела висит:
## не летит, life не тикает, мониторинг погашен (висячая не задевает даже если
## цель на ней). После разморозки — monitoring включён, полёт продолжается и
## попадает ровно один раз.

var _dirs: Array = [Vector2.RIGHT, Vector2.UP, Vector2(0.707, -0.707), Vector2(0.707, 0.707), Vector2.DOWN, Vector2.LEFT]

func _ready() -> void:
	await boot(save_for(0))
	await section_freeze()
	done()

## Кандидатная позиция стаба вокруг center на дистанции dist с нужным LOS (как в mb_1).
func place_spot(archer: Node2D, center: Vector2, dist: float, want_los: bool) -> bool:
	for d: Vector2 in _dirs:
		var p := center + d * dist
		var t := Vector2i(floori(p.x / 16.0), floori((p.y - 2.0) / 16.0))
		if not village_tile_walkable(t):
			continue
		stub.global_position = p
		if bool(archer.call("_has_los", stub)) == want_los:
			return true
	return false

func arrows_now() -> Array:
	var out: Array = []
	for c in world.get_children():
		if c.get("dirv") != null and c.get("dmg") != null and c.get("life") != null:
			out.append(c)
	return out

func section_freeze() -> void:
	await pump(2)
	for s in find_mob(world.village_zone, "slime"):
		park(s)
	for r in find_mob(world.village_zone, "mob_swarmling"):
		park(r)
	for w in find_mob(world.dungeon_zone, "mob_wraith"):
		park(w)
	park(world.dungeon_zone.boss_node)
	var archers: Array = find_mob(world.village_zone, "mob_archer")
	if archers.size() < 1:
		check("S6: лучник найден", false)
		return
	var arch: Node2D = archers[0]
	park(archers[1])
	if not place_spot(arch, arch.position, 80.0, true):
		check("S6: позиция LOS 80px не найдена", false)
		return
	check("S6: позиция LOS-открыта на 80px", true)
	stub.dmg_log.clear()
	# ждём телеграф и зассекаем первый вылетевший снаряд
	var arrow: Node2D = null
	for i in range(600):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
		var arr := arrows_now()
		if arr.size() > 0:
			arrow = arr[0]
			break
	check("S6: стрела засечена в полёте", arrow != null)
	if arrow == null:
		return
	var aid: int = arrow.get_instance_id()
	check("S6: до блокировки monitoring/monitorable включены", bool(arrow.monitoring) and bool(arrow.monitorable))
	# --- блокировка: стрела должна зависнуть ---
	GameState.input_locked = true
	var pos0: Vector2 = arrow.global_position
	var stub_pos0: Vector2 = stub.global_position
	var life0 := 0.0
	var died_early := false
	var extra_shots := false
	for i in range(121):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
		if not is_instance_id_valid(aid):
			died_early = true
			break
		if arrows_now().size() > 1:
			extra_shots = true
		if i == 1:
			life0 = float(arrow.life)
			check("S6: lock — monitoring/monitorable погашены", (not bool(arrow.monitoring)) and (not bool(arrow.monitorable)))
	check("S6: lock — стрела жива все 120 кадров (life не тикал)", not died_early)
	check("S6: lock — новых выстрелов не было", not extra_shots)
	if died_early:
		GameState.input_locked = false
		check("S6: lock — висит без смещения", false)
		check("S6: lock — life не изменился", false)
		return
	check("S6: lock — висит без смещения (2с)", arrow.global_position.distance_to(pos0) < 0.001)
	check("S6: lock — life не изменился", absf(float(arrow.life) - life0) < 1e-9)
	# --- висячая стрела не цепляет цель, даже если стаб стоит на ней ---
	stub.global_position = arrow.global_position
	for i in range(30):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
	check("S6: lock — стоящий на стреле стаб не задет", stub.dmg_log.size() == 0 and is_instance_id_valid(aid))
	# --- разморозка: полёт продолжается ---
	GameState.input_locked = false
	stub.global_position = stub_pos0
	await get_tree().physics_frame
	check("S6: release — monitoring/monitorable восстановлены", bool(arrow.monitoring) and bool(arrow.monitorable))
	check("S6: release — стрела полетела дальше", arrow.global_position.distance_to(pos0) > 1.0)
	var flew: bool = await until(func() -> bool: return stub.dmg_log.size() > 0, 120)
	check("S6: release — полёт завершился попаданием", flew)
	if flew:
		check("S6: release — ровно одно попадание +2", stub.dmg_log.size() == 1 and int(stub.dmg_log[0]) == 2)
	await pump_raw(3)
	check("S6: release — стрела освобождена после попадания", not is_instance_id_valid(aid))
