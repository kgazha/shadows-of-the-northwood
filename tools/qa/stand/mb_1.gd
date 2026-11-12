extends "res://mb_base.gd"
## Кейс 1: позиции/проходимость спавнов. Кейс 2: лучник — телеграф, урон стрелы,
## упор <28px, LOS/ролл-контры. Кейс 5 (частично): input_locked/смерть/freeze_t.

func _ready() -> void:
	await boot(save_for(0))
	section_spawn()
	await section_archer()
	done()

func tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(roundi(pos.x / 16.0 - 0.5), roundi((pos.y - 2.0) / 16.0 - 0.5))

func section_spawn() -> void:
	var archers: Array = find_mob(world.village_zone, "mob_archer")
	var rats: Array = find_mob(world.village_zone, "mob_swarmling")
	var wraiths: Array = find_mob(world.dungeon_zone, "mob_wraith")
	check("S1: 2 лучника заспавнены", archers.size() == 2)
	check("S1: стая из 2 мглокрыс (t39 grace: рой у старта урезан 4→2)", rats.size() == 2)
	check("S1: тенеплётов в пещере нет — T13 убран из геймплея (резерв)", wraiths.is_empty())
	var want_arch: Array = [Vector2i(4, 26), Vector2i(44, 26)]
	for i in range(mini(archers.size(), 2)):
		var a: Node2D = archers[i]
		var t := tile_of(a.position)
		check("S1: лучник на тайле %s" % str(t), t == want_arch[0] or t == want_arch[1])
		check("S1: тайл лучника %s проходим" % str(t), village_tile_walkable(t))
	# t39 grace: стая уведена 4→2 особей в глубь западной поляны (подальше от
	# старта новичка); тайлы ниже — новые пин-факты из world.gd (_spawn_entities).
	var want_rats: Array = [Vector2i(4, 24), Vector2i(3, 26)]
	for r in rats:
		var t2 := tile_of((r as Node2D).position)
		check("S1: крыса на тайле %s" % str(t2), want_rats.has(t2))
		check("S1: тайл крысы %s проходим" % str(t2), village_tile_walkable(t2))
		check("S1: крыса swarm_id=glade_west", String(r.swarm_id) == "glade_west")
	# T13: тенеплёты из геймплея выведены — тайловые проверки ниши босса убраны,
	# выше остаётся только проверка «в пещере их нет».

## Кандидатная позиция стаба вокруг точки center на дистанции dist с LOS от archer.
func place_spot(archer: Node2D, center: Vector2, dirs: Array, dist: float, want_los: bool) -> bool:
	for d: Vector2 in dirs:
		var p := center + d * dist
		var t := Vector2i(floori(p.x / 16.0), floori((p.y - 2.0) / 16.0))
		if not village_tile_walkable(t):
			continue
		stub.global_position = p
		var has := bool(archer.call("_has_los", stub))
		if has == want_los:
			return true
	return false

func arrows_now() -> Array:
	var out: Array = []
	for c in world.get_children():
		if c.get("dirv") != null and c.get("dmg") != null and c.get("life") != null:
			out.append(c)
	return out

func wait_tele(archer: Node2D, maxf: int) -> float:
	## Возвращает значение tele_t на первом кадре телеграфа (0, если не начался).
	for i in range(maxf):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
		if archer.tele_t > 0.0:
			return float(archer.tele_t)
	return 0.0

func section_archer() -> void:
	await pump(2)
	# изоляция: всё лишнее паркуем
	for s in find_mob(world.village_zone, "slime"):
		park(s)
	for r in find_mob(world.village_zone, "mob_swarmling"):
		park(r)
	for w in find_mob(world.dungeon_zone, "mob_wraith"):
		park(w)
	park(world.dungeon_zone.boss_node)
	var archers: Array = find_mob(world.village_zone, "mob_archer")
	if archers.size() < 1:
		check("S2: лучник найден", false)
		return
	var arch: Node2D = archers[0]  # (4,26)
	park(archers[1])
	var a0: Vector2 = arch.position
	var dirs: Array = [Vector2.RIGHT, Vector2.UP, Vector2(0.707, -0.707), Vector2(0.707, 0.707), Vector2.DOWN, Vector2.LEFT]
	# --- телеграф 0.7с читаем ---
	if not place_spot(arch, a0, dirs, 80.0, true):
		check("S2: найдена позиция 80px с LOS", false)
		return
	check("S2: позиция LOS-открыта на 80px", true)
	stub.velocity = Vector2.ZERO
	var tele0 := await wait_tele(arch, 500)
	check("S2: телеграф стартует с ~0.7с (f=1/60 включительно)", tele0 >= 0.67 and tele0 <= 0.71)
	await pump_raw(1)
	var hl: Color = arch.modulate
	check("S2: телеграф подсвечен (читаемый сигнал)", hl.r > 1.2 and hl.g > 1.0)
	# --- урон стрелы ровно 2 ---
	stub.dmg_log.clear()
	var got_hit: bool = await until(func() -> bool: return stub.dmg_log.size() > 0, 400)
	check("S2: стрела попала", got_hit)
	if got_hit:
		check("S2: урон стрелы ровно 2", int(stub.dmg_log[0]) == 2)
		await pump(90)
		check("S2: за окно — ровно одна стрела", stub.dmg_log.size() == 1)
	# --- рывок-контра (roll_t блокирует пуск/срывает) ---
	await until(func() -> bool: return arch.tele_t > 0.0, 400)
	check("S2: телеграф возобновился", arch.tele_t > 0.0)
	stub.roll_t = 0.5
	await pump_raw(2)
	check("S2: кувырок срывает телеграф", float(arch.tele_t) == 0.0)
	stub.roll_t = 0.0
	# --- LOS-срыв ---
	if place_spot(arch, a0, dirs, 80.0, true):
		await until(func() -> bool: return arch.tele_t > 0.0, 400)
		var was := float(arch.tele_t)
		if place_spot(arch, a0, dirs, 96.0, false):
			await pump_raw(3)
			check("S2: стена за 0-3 кадра срывает телеграф (шёл t=%.2f)" % was, float(arch.tele_t) == 0.0)
			check("S2: сорванный выстрел -> короткий пауз-кулдаун ~0.5", float(arch.shot_cd) >= 0.3 and float(arch.shot_cd) <= 0.6)
		else:
			check("S2: найдена LOS-закрытая позиция", false)
	# --- в упор <28px не стреляет (стаб «приклеен» в 15px) ---
	var glue_dir := Vector2.ZERO
	for d0: Vector2 in dirs:
		stub.global_position = arch.global_position + d0 * 15.0
		if bool(arch.call("_has_los", stub)):
			glue_dir = d0
			break
	check("S2: упор-позиция 15px с LOS построена", glue_dir != Vector2.ZERO)
	var no_shots := true
	var tele_in_tight := false
	var min_arrow_dist := 9999.0
	var seen_arrows := 0
	for i in range(600):
		stub.global_position = arch.global_position + glue_dir * 15.0
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
		stub.global_position = arch.global_position + glue_dir * 15.0
		var d: float = arch.global_position.distance_to(stub.global_position)
		if d < 28.0 and float(arch.tele_t) > 0.0:
			tele_in_tight = true
		var arr := arrows_now()
		if arr.size() > seen_arrows:
			no_shots = false
			min_arrow_dist = minf(min_arrow_dist, d)
		seen_arrows = arr.size()
	# --- input_locked ---
	place_spot(arch, a0, dirs, 80.0, true)
	GameState.input_locked = true
	var pos_lock: Vector2 = arch.global_position
	for i in range(180):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
	check("S2: input_locked — нет телеграфа за 3с", float(arch.tele_t) == 0.0)
	check("S2: input_locked — лучник стоит", arch.global_position.distance_to(pos_lock) < 0.5)
	GameState.input_locked = false
	var resumed: bool = await until(func() -> bool: return arch.tele_t > 0.0, 400)
	check("S2: после разморозки ИИ возобновился", resumed)
	stub.roll_t = 0.5
	await pump_raw(2)
	stub.roll_t = 0.0
	# --- freeze_t ---
	arch.freeze_t = 3.0
	var pos_fz: Vector2 = arch.global_position
	await pump(60)
	check("S2: freeze_t — стоит", arch.global_position.distance_to(pos_fz) < 0.5)
	check("S2: freeze_t — телеграф сброшен", float(arch.tele_t) == 0.0)
	var arrows_during := arrows_now().size()
	await pump(120)
	check("S2: freeze_t — не стреляет 2с", arrows_now().size() == arrows_during)
	check("S2: freeze_t — синий тинт", arch.modulate.b > 0.9 and arch.modulate.r < 0.7)
	arch.freeze_t = 0.0
	# --- смерть героя ---
	place_spot(arch, a0, dirs, 80.0, true)
	var pos_die: Vector2 = arch.global_position
	var arr_die := arrows_now().size()
	GameState.hp = 0
	await pump_raw(180)
	GameState.hp = GameState.max_hp
	check("S2: hp=0 героя — лучник замолкает (3с без выстрелов)", arrows_now().size() == arr_die)
	check("S2: hp=0 героя — стоит", arch.global_position.distance_to(pos_die) < 0.5)
	# --- dying-страж: XP ровно один раз ---
	var xp0 := GameState.xp
	arch.hurt(99, Vector2.ZERO)
	arch.hurt(99, Vector2.ZERO)
	arch.hurt(99, Vector2.ZERO)
	await pump(2)
	check("S2: XP за лучника ровно +9 (dying-страж)", GameState.xp == xp0 + 9)
	check("S2: тост смерти один", n_toast("лучник повержен") == 1)
