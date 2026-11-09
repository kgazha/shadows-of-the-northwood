extends Node
## Временный интеграционный стенд спринта 2. Запуск:
##   godot --headless --path pixel-rpg res://test_s2.tscn
## Проверяет: старый сейв, выбор класса/пересчёт статов, приказы мыши,
## мили-убийство, дальнее убийство лучника, power_strike x2, заморозку,
## xp-кривую x1.6, блокировку смены класса в диалоге.

var world          # инстанс main.tscn
var fails := 0

func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		print("FAIL | таймаут стенда")
		get_tree().quit(3))
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_run()

func check(label: String, ok: bool) -> void:
	print(("OK   | " if ok else "FAIL | ") + label)
	if not ok:
		fails += 1

func wait_until(cond: Callable, cap: int = 1500) -> bool:
	for _i in cap:
		await get_tree().physics_frame
		if cond.call():
			return true
	return false

func _run() -> void:
	# 0 — старый сейв без class_id грузится и пересчитывается
	var old := {"max_hp": 10, "hp": 6, "level": 2, "xp": 5, "xp_next": 40,
		"damage": 2, "has_sword": true, "herbs": 1, "elder_quest": 1}
	GameState.from_dict(old)
	check("старый сейв: class_id => warrior", GameState.class_id == "warrior")
	check("старый сейв: max_hp = 12+2*(2-1) = 14", GameState.max_hp == 14)
	check("старый сейв: damage = 2*2 (меч) = 4", GameState.damage == 4)
	DirAccess.remove_absolute(OS.get_user_data_dir() + "/save_morkheim.json")

	# xp-кривая v1.1: 20 -> 32 -> 51 -> 82
	GameState.from_dict({})
	check("xp_next = 20 на старте", GameState.xp_next == 20)
	GameState.add_xp(20)
	check("lv2: xp_next = round(20*1.6) = 32", GameState.level == 2 and GameState.xp_next == 32)
	GameState.add_xp(32)
	check("lv3: xp_next = 51", GameState.level == 3 and GameState.xp_next == 51)
	GameState.add_xp(51)
	check("lv4: xp_next = 82", GameState.level == 4 and GameState.xp_next == 82)

	# 1 — мир без класса: модалка выбора героя
	GameState.from_dict({})
	GameState.class_id = ""
	GameState.seen_intro = true  # интро не мешает стенду
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hud = world.hud
	var p = world.player
	check("без класса — модалка открыта", hud.is_modal_open())
	check("без класса — ввод залочен", GameState.input_locked)
	hud._pick_class("mage")
	check("маг: class_id", GameState.class_id == "mage")
	check("маг: max_hp = 6", GameState.max_hp == 6)
	check("маг: damage = 3", GameState.damage == 3)
	check("маг: модалка закрыта", not hud.is_modal_open())
	check("маг: ввод разблокирован", not GameState.input_locked)
	GameState.has_sword = true
	check("маг+меч: damage = 3*2 = 6", GameState.damage == 6)
	GameState.has_sword = false

	# 2 — приказы мышью
	p.command_move(p.global_position + Vector2(40, 0))
	check("приказ идти: цель задана", p.move_target != Vector2.INF)
	p.command_move(Vector2.INF)
	p.command_move(p.global_position + Vector2(40, 0))
	p.cancel_orders()
	check("cancel_orders: цель снята", p.move_target == Vector2.INF and p.attack_target == null)

	GameState.set_class("warrior")
	p.apply_class()
	GameState.hp = 400  # неуязвимость стенда

	# 3 — мили-автоатака убивает слайма
	var sl = load("res://scripts/slime.gd").new()
	world.village_zone.add_child(sl)
	sl.setup(world, world.spawn_tile + Vector2i(2, 0))
	p.command_attack(sl)
	var killed := await wait_until(func(): not is_instance_valid(sl))
	check("мили: слайм убит автоатакой", killed)
	await wait_until(func(): not GameState.input_locked)  # на случай смерти игрока

	# 4 — лучник добивает с расстояния снарядом
	GameState.set_class("archer")
	p.apply_class()
	GameState.hp = 400
	var sl2 = load("res://scripts/slime.gd").new()
	world.village_zone.add_child(sl2)
	sl2.setup(world, world.spawn_tile + Vector2i(4, 0))  # 64 px — дальше мили
	p.command_attack(sl2)
	var p0: Vector2 = p.global_position
	var dist0: float = p.global_position.distance_to(sl2.global_position)
	var killed2 := await wait_until(func(): not is_instance_valid(sl2), 2000)
	var moved: float = p.global_position.distance_to(p0)
	check("лучник: слайм убит с %d px" % int(dist0), killed2 and dist0 > 40)
	check("лучник: стрелял с места (не догонял в мили)", killed2 and moved < 1.0)
	p.cancel_orders()

	# 5 — «Мощный удар» воина: 2x по цели (гром 12 -> 8)
	GameState.set_class("warrior")
	p.apply_class()
	GameState.hp = 400
	var br = load("res://scripts/brute.gd").new()
	world.village_zone.add_child(br)
	br.setup(world, world.spawn_tile + Vector2i(1, 0))
	p.attack_cd = 99.0  # автоатака не должна съесть HP до скилла
	p.command_attack(br)
	await get_tree().physics_frame
	var cast_ok: bool = p.cast_skill(0, p.global_position)
	check("power_strike: каст прошёл", cast_ok)
	check("power_strike: 2x урон (12 -> 8)", br.hp == 8)
	check("power_strike: кулдаун взведён", float(p.skill_cd[0]) > 3.0)
	var cast_again: bool = p.cast_skill(0, p.global_position)
	check("power_strike: на КД не кастуется", not cast_again)
	p.cancel_orders()
	br.queue_free()
	await get_tree().physics_frame

	# 6 — замороженный слайм не двигается, обычный — двигается
	var sf = load("res://scripts/slime.gd").new()
	world.village_zone.add_child(sf)
	sf.setup(world, world.spawn_tile + Vector2i(0, 6))
	sf.dirv = Vector2.UP
	sf.wander_t = 99.0
	var sn = load("res://scripts/slime.gd").new()
	world.village_zone.add_child(sn)
	sn.setup(world, world.spawn_tile + Vector2i(2, 6))
	sn.dirv = Vector2.UP
	sn.wander_t = 99.0
	sf.freeze_t = 3.0
	await wait_until(func(): false, 60)  # просто 60 физ-кадров
	check("freeze: слайм не сдвинулся", sf.global_position.distance_to(
		world.tile_to_world(world.spawn_tile + Vector2i(0, 6))) < 0.5)
	check("freeze: обычный слайм двигается", sn.global_position.distance_to(
		world.tile_to_world(world.spawn_tile + Vector2i(2, 6))) > 2.0)
	check("freeze: синий тинт", sf.modulate.b > 0.9 and sf.modulate.r < 0.8)
	sf.queue_free()
	sn.queue_free()

	# 7 — старый сейв-файл грузится (без class_id)
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"max_hp": 10, "hp": 4, "level": 1, "xp": 0,
		"xp_next": 20, "damage": 1, "has_sword": false, "herbs": 1, "elder_quest": 1}))
	f = null
	check("сейв-файл без class_id загрузился", GameState.load_game())
	check("сейв: class_id = warrior", GameState.class_id == "warrior")
	check("сейв: max_hp пересчитан в 12", GameState.max_hp == 12)
	check("сейв: hp сохранён (4)", GameState.hp == 4)
	p.apply_class()
	hud.refresh_skills()
	check("сейв: панель скиллов показана", hud.skill_panel.visible)

	# 8 — смена класса недоступна во время диалога
	world.start_dialogue("intro")
	check("диалог открыт", hud.is_dialog_open())
	hud._on_class_switch()
	check("в диалоге: модалка НЕ открылась", not hud.is_modal_open())
	var guard := 0
	while hud.is_dialog_open() and guard < 100:
		hud.advance()
		guard += 1
	check("диалог закрыт", not hud.is_dialog_open())
	hud._on_class_switch()
	check("после диалога: смена класса доступна", hud.is_modal_open())
	hud._pick_class("warrior")
	check("смена класса: статы воина", GameState.max_hp == 12 and GameState.damage == 2)
	check("смена класса: прогресс сброшен", GameState.level == 1 and GameState.xp == 0)

	# уборка за собой
	DirAccess.remove_absolute(OS.get_user_data_dir() + "/save_morkheim.json")
	print("== ИТОГ: fails=%d ==" % fails)
	get_tree().quit(1 if fails > 0 else 0)
