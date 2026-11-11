extends "res://mb_base.gd"
## Кейс 3: тенеплёт — эфир не принимается, материализация 1.1с уязвима,
## фаза сквозь стены не застревает, заморозка выбивает из фазы, dying-страж.

const ETH := 0
const PHA := 1
const MAT := 2

var w1: Node2D = null
var w2: Node2D = null
var wraiths: Array = []

func _ready() -> void:
	await boot(save_for(0))
	await prep()
	await section_ethereal()
	await section_materialize_kill()
	await section_wall_stuck()
	await section_freeze_lock()
	done()

func prep() -> void:
	for s in find_mob(world.village_zone, "slime"):
		park(s)
	for a in find_mob(world.village_zone, "mob_archer"):
		park(a)
	for r in find_mob(world.village_zone, "mob_swarmling"):
		park(r)
	park(world.dungeon_zone.boss_node)
	wraiths = find_mob(world.dungeon_zone, "mob_wraith")
	check("W: два тенеплёта в пещере", wraiths.size() == 2)
	if wraiths.size() < 2:
		return
	w1 = wraiths[0]
	w2 = wraiths[1]
	world.apply_zone(true, false)  # пещера активна, героя не телепортируем
	stub.global_position = cave_spot_near(w1.global_position, 45.0, 90.0)

## Ближайшая к эталонному расстоянию проходимая пещерная точка вокруг center.
func cave_spot_near(center: Vector2, mind: float, maxd: float) -> Vector2:
	var best := center
	var best_d := 1e20
	var dz: Node = world.dungeon_zone
	for y in range(int(dz.map_h)):
		for x in range(int(dz.map_w)):
			if not cave_tile_walkable(Vector2i(x, y)):
				continue
			var p := cave_global(world, Vector2i(x, y))
			var d: float = center.distance_to(p)
			if d < mind or d > maxd:
				continue
			if absf(d - (mind + maxd) * 0.5) < best_d:
				best_d = absf(d - (mind + maxd) * 0.5)
				best = p
	return best

func wait_state(node: Node2D, st: int, maxf: int) -> bool:
	return await until(func() -> bool: return int(node.state) == st, maxf)

func section_ethereal() -> void:
	if w1 == null:
		return
	await wait_state(w1, ETH, 300)
	check("W: стартовое состояние — эфир", int(w1.state) == ETH)
	GameState.entered_combat()
	var xp0 := GameState.xp
	w1.hurt(3, Vector2.ZERO)
	w1.hurt(3, Vector2.ZERO)
	await pump(2)
	check("W: эфир — урон НЕ принимается (hp=8)", int(w1.hp) == 8)
	check("W: эфир — XP не начислен", GameState.xp == xp0)
	# фаза тоже неуязвима
	w1.dash_cd = 0.0
	var got_pha: bool = await wait_state(w1, PHA, 200)
	check("W: рывок-фаза возникает", got_pha)
	if int(w1.state) == PHA:
		w1.hurt(3, Vector2.ZERO)
		check("W: фаза — урон НЕ принимается", int(w1.hp) == 8)
	# фаза через стену не оставляет в породе в момент конца (базовая проверка)
	await pump(60)
	check("W: вне фазы всегда на проходимом тайле", bool(w1.call("_tile_walkable", w1.global_position)))

## Отодвинуть стенд от тенеплёта, чтобы снова работал триггер фазы (d>24).
func pull_stub_away(node: Node2D, dist: float) -> void:
	var dir := (stub.global_position - node.global_position)
	if dir.length_squared() < 1.0:
		dir = Vector2.RIGHT
	stub.global_position = node.global_position + dir.normalized() * dist

## Свежий цикл ETH -> PHA -> первый кадр MAT; возвращает mat_t первого кадра.
func fresh_mat(node: Node2D) -> float:
	pull_stub_away(node, 70.0)
	node.dash_cd = 0.0
	await until(func() -> bool: return int(node.state) == ETH, 120)
	if not await wait_state(node, PHA, 300):
		return -1.0
	if not await wait_state(node, MAT, 300):
		return -1.0
	return float(node.mat_t)

func section_materialize_kill() -> void:
	if w1 == null:
		return
	var mat_seen: float = await fresh_mat(w1)
	check("W: материализация доходит до героя", mat_seen > 0.0)
	check("W: окно материализации ~1.1с (первый кадр t=%.3f)" % mat_seen, mat_seen >= 1.05 and mat_seen <= 1.11)
	# уязвимость в окне
	var hp_before := int(w1.hp)
	w1.hurt(2, Vector2.ZERO)
	check("W: в материализации урон принят (hp %d->%d)" % [hp_before, int(w1.hp)], int(w1.hp) == hp_before - 2)
	# после окна снова эфир — неуязвим
	await wait_state(w1, ETH, 300)
	hp_before = int(w1.hp)
	w1.hurt(2, Vector2.ZERO)
	check("W: после окна — снова неуязвим", int(w1.hp) == hp_before)
	# убийство в окне: XP ровно один раз
	var mt_kill: float = await fresh_mat(w1)
	var ok_kill := mt_kill > 0.0
	check("W: второе окно материализации открылось", ok_kill)
	var xp0 := GameState.xp
	clear_toasts()
	w1.hurt(99, Vector2.ZERO)
	var xp_mid := GameState.xp
	w1.hurt(99, Vector2.ZERO)
	w1.hurt(99, Vector2.ZERO)
	await pump(3)
	check("W: XP за тенеплёта ровно +15", xp_mid == xp0 + 15 and GameState.xp == xp0 + 15)
	check("W: тост смерти один", n_toast("рассеян") == 1)

func section_wall_stuck() -> void:
	if w2 == null:
		return
	# ищем «толстую» стену: T проходим, T+d и T+2d — камень, T+3d снова проходим:
	# рывок (0.35с * 95 = ~33px) обязан заканчиваться в породе и выплёвываться на last_safe
	var dz: Node = world.dungeon_zone
	var niche: Array = []  # [tile T, stub tile S, Vector2i dir]
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for y in range(int(dz.map_h)):
		for x in range(int(dz.map_w)):
			var t := Vector2i(x, y)
			if not cave_tile_walkable(t):
				continue
			for d in dirs:
				if cave_tile_walkable(t + d) or cave_tile_walkable(t + d * 2):
					continue
				if cave_tile_walkable(t + d * 3):
					niche = [t, t + d * 3, d]
					break
			if niche.size() > 0:
				break
		if niche.size() > 0:
			break
	if niche.size() == 0:
		check("W: найдена ниша «толстая стена» для soak", false)
		return
	check("W: найдена ниша «толстая стена» для soak (%s -> %s)" % [niche[0], niche[1]], true)
	var t_tile: Vector2i = niche[0]
	var s_tile: Vector2i = niche[1]
	var wall_dir: Vector2i = niche[2]
	w2.global_position = cave_global(world, t_tile)
	w2.last_safe = w2.global_position
	var bad_frames := 0
	var mats := 0
	var to_rock := 0       # сколько раз фаза кончилась в камне (телепорт last_safe)
	var teleports := 0
	var prev_st := int(w2.state)
	var prev_pos: Vector2 = w2.global_position
	var prev_in_rock := false
	for i in range(1800):  # 30 секунд soak
		GameState.hp = GameState.max_hp
		stub.global_position = cave_global(world, s_tile)
		await get_tree().physics_frame
		if not is_instance_valid(w2):
			break
		var st := int(w2.state)
		var in_rock: bool = not bool(w2.call("_tile_walkable", w2.global_position))
		if st != PHA and in_rock:
			bad_frames += 1
		# фаза, завершившаяся внутри камня: в предыдущем кадре были в породе на PHA,
		# в этом — телепорт на проходимую точку
		if st != PHA and prev_st == PHA and prev_in_rock:
			teleports += 1
		if prev_st == PHA and not in_rock and st == PHA:
			pass
		if st == MAT and prev_st == PHA:
			to_rock += 0  # материализация после фазы
			mats += 1
		if st != PHA and prev_st == PHA and not bool(w2.call("_tile_walkable", w2.global_position)):
			pass
		prev_pos = w2.global_position
		prev_st = st
		prev_in_rock = in_rock
	check("W: soak 30с — ни одного «в породе вне фазы» (bad=%d)" % bad_frames, bad_frames == 0)
	check("W: soak — фаза хоть раз упёрлась в камень (teleports=%d)" % teleports, teleports >= 1)
	check("W: цикл фаз не умер (материализаций=%d)" % mats, mats >= 3)
	if is_instance_valid(w2):
		await until(func() -> bool: return int(w2.state) != PHA, 180)
		check("W: после soak жив и валиден", not bool(w2.is_queued_for_deletion()))
		check("W: после soak на проходимом", bool(w2.call("_tile_walkable", w2.global_position)))
	else:
		check("W: после soak жив и валиден", false)
		check("W: после soak на проходимом", false)

func section_freeze_lock() -> void:
	if w2 == null:
		return
	# freeze во время фазы выбивает в эфир и чинит маску
	w2.dash_cd = 0.0
	await wait_state(w2, PHA, 200)
	if int(w2.state) == PHA:
		w2.freeze_t = 3.0
		await pump_raw(2)
		check("W: freeze из фазы -> эфир", int(w2.state) == ETH)
		check("W: freeze вернул коллизию со стенами (mask=6: 2|4)", int(w2.collision_mask) == 6)
		check("W: freeze — тело прозрачно для героя (layer=0)", int(w2.collision_layer) == 0)
		var pf: Vector2 = w2.global_position
		await pump(60)
		check("W: freeze — стоит", w2.global_position.distance_to(pf) < 0.5)
		w2.freeze_t = 0.0
	# input_locked — полная заморозка
	await pump(10)
	GameState.input_locked = true
	var s0 := int(w2.state)
	var mt0 := float(w2.mat_t)
	var p0: Vector2 = w2.global_position
	for i in range(90):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
	check("W: input_locked — состояние заморожено", int(w2.state) == s0 and float(w2.mat_t) == mt0)
	check("W: input_locked — позиция заморожена", w2.global_position.distance_to(p0) < 0.5)
	GameState.input_locked = false
	# смерть героя — полная заморозка
	GameState.hp = 0
	var p1: Vector2 = w2.global_position
	for i in range(90):
		await get_tree().physics_frame
	GameState.hp = GameState.max_hp
	check("W: hp=0 героя — стоит 1.5с", w2.global_position.distance_to(p1) < 0.5)
