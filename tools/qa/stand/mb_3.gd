extends "res://mb_base.gd"
## Кейс 4: стая мглокрыс — испуг при <=50% живых (один тост, разлёт, чистый реестр).
## Усилено по вердикту: после разлёта 2 убежавших из 4-стаи (2 убиты) реестр чист;
## стая с той же id после полного разлёта НЕ рождается panicked.
## Кейс 5: input_locked/смерть/freeze_t, dying-страж XP.

const SScript := preload("res://scripts/mob_swarmling.gd")

var qa4_pack: Array = []

func _ready() -> void:
	await boot(save_for(0))
	await prep()
	await section_clear_original()
	await section_panic()
	await section_registry()
	await section_flee_pocket()
	await section_dying_xp()
	await section_lock()
	done()

func prep() -> void:
	for s in find_mob(world.village_zone, "slime"):
		park(s)
	for a in find_mob(world.village_zone, "mob_archer"):
		park(a)
	for w in find_mob(world.dungeon_zone, "mob_wraith"):
		park(w)
	park(world.dungeon_zone.boss_node)
	# герой-стенд подальше от поляны, чтобы поедание/погоня не мешали
	stub.global_position = world.tile_to_world(Vector2i(24, 24))
	if not village_tile_walkable(Vector2i(24, 24)):
		stub.global_position = world.tile_to_world(Vector2i(24, 15))
	await pump(2)

func spawn_pack(id: String, tiles: Array) -> Array:
	var out: Array = []
	for t: Vector2i in tiles:
		var r = SScript.new()
		r.swarm_id = id
		world.village_zone.add_child(r)
		r.setup(world, t)
		out.append(r)
	return out

func section_clear_original() -> void:
	# зачистка штатной стаи: путь «все убиты» обязан очистить реестр
	var rats: Array = find_mob(world.village_zone, "mob_swarmling")
	for r in rats:
		r.hurt(99, Vector2.ZERO)
	await pump(3)
	check("Q: реестр чист после зачистки штатной стаи", not SScript.SWARMS.has("glade_west"))

func section_panic() -> void:
	var tiles: Array = [Vector2i(6, 16), Vector2i(9, 16), Vector2i(6, 18), Vector2i(10, 18)]
	qa4_pack = spawn_pack("qa4", tiles)
	check("Q: стая qa4 заведена (total=4)", int(SScript.SWARMS["qa4"].total) == 4)
	clear_toasts()
	qa4_pack[0].hurt(99, Vector2.ZERO)
	await pump(2)
	check("Q: 3/4 живых — паники нет", bool(SScript.SWARMS["qa4"].panicked) == false)
	check("Q: 3/4 живых — тоста испуга нет", n_toast("шарахается") == 0)
	qa4_pack[1].hurt(99, Vector2.ZERO)
	await pump(2)
	check("Q: 2/4 (=50%) — паника случилась", bool(SScript.SWARMS["qa4"].panicked) == true)
	check("Q: тост испуга ровно один", n_toast("шарахается") == 1)
	var f1: Vector2 = qa4_pack[2].flee_dir
	var f2: Vector2 = qa4_pack[3].flee_dir
	check("Q: выжившие получили векторы разлёта", f1.length_squared() > 0.5 and f2.length_squared() > 0.5)
	check("Q: разлёт веером (углы различаются)", absf(f1.angle_to(f2)) > 1.0)
	check("Q: реестр жив при панике (2/4 убегают)", int(SScript.SWARMS["qa4"].alive) == 2)

func section_registry() -> void:
	# 2 убежавших из 4-стаи (2 убиты): обе растворяются за FLEE_RADIUS — реестр обязан очиститься
	var id0: int = qa4_pack[2].get_instance_id()
	var id1: int = qa4_pack[3].get_instance_id()
	# t43 FIX FLAKE (ложный RED в батарее две ночи подряд). Корень: веер разлёта
	# mob_swarmling.scatter строит углы через глобальный randf (flee-угол ±0.35 рад).
	# Свип 48 углов × 2 тайла (t43 REPORT): углы вблизи 0/90/180/270° — геометрические
	# карманы поляны, крыса из них НЕ убегает никогда (maxd 7–121px за 30 c симуляции,
	# FLEE_RADIUS=128 так и не достигается) → покадровый бюджет не спасает. Под нагрузкой
	# параллельных прогонов последовательность глобального randf иная → в батарее выпадал
	# карманный угол, в изолированном ретрае — убегающий. Тест обязан быть RNG-нейтральным:
	# игровая проверка «веера» осталась в section_panic (углы игры различаются >1 рад),
	# здесь — после неё — фиксируем заведомо убегающие углы 45°/225° (замер свипа: выход
	# из кармана за 116–235 кадров). Механика бегства, деспавна за FLEE_RADIUS и чистки
	# реестра — настоящие, живые; устранён только источник подбрасывания монетки.
	qa4_pack[2].set_flee(Vector2(0.70710678, 0.70710678))   # 45°  — убегающий угол (6,18)
	qa4_pack[3].set_flee(Vector2(-0.70710678, -0.70710678)) # 225° — убегающий угол (10,18)
	var v0 := false
	var v1 := false
	for i in range(240):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
		if is_instance_id_valid(id0) and Vector2((instance_from_id(id0) as Node2D).velocity).length() > 55.0:
			v0 = true
		if is_instance_id_valid(id1) and Vector2((instance_from_id(id1) as Node2D).velocity).length() > 55.0:
			v1 = true
	check("Q: обе испуганные крысы убегают (скорость ~66)", v0 and v1)
	var chk := func() -> bool:
		return (not is_instance_id_valid(id0)) and (not is_instance_id_valid(id1))
	# t43: бюджет 1500→3000 кадров — страховка на случай изменения геометрии (успех
	# возвращается сразу, цена у страховки нулевая; детерминированный выход ~≤235 кадров).
	var gone: bool = await until(chk, 3000)
	if not gone:
		# САМОДИАГНОСТИКА: будущий RED обязан быть объясним из лога без пересъёмки.
		var n0: Node2D = instance_from_id(id0) as Node2D if is_instance_id_valid(id0) else null
		var n1: Node2D = instance_from_id(id1) as Node2D if is_instance_id_valid(id1) else null
		print("DEBUG flee-stuck: rat0 valid=%s pos=%s vel=%s | rat1 valid=%s pos=%s vel=%s | hero=%s" % [
			is_instance_id_valid(id0), str(n0.global_position) if n0 != null else "-",
			str(n0.velocity) if n0 != null else "-",
			is_instance_id_valid(id1), str(n1.global_position) if n1 != null else "-",
			str(n1.velocity) if n1 != null else "-", str(stub.global_position)])
	check("Q: обе крысы исчезли с карты", gone)
	await pump(5)
	check("Q: ПОСЛЕ РАЗЛЁТА 2/2 реестр чист (фикс W2)", not SScript.SWARMS.has("qa4"))
	check("Q: тост испуга за всё время один", n_toast("шарахается") == 1)
	# респавн стаи с ТОЙ ЖЕ id после полного разлёта — не рождается panicked
	var qa4b := spawn_pack("qa4", [Vector2i(6, 16), Vector2i(10, 18)])
	await pump(2)
	check("Q: респавн qa4: запись создана заново", SScript.SWARMS.has("qa4") and int(SScript.SWARMS["qa4"].total) == 2)
	check("Q: респавн qa4 НЕ panicked", bool(SScript.SWARMS["qa4"].panicked) == false)
	qa4b[0].hurt(99, Vector2.ZERO)
	qa4b[1].hurt(99, Vector2.ZERO)
	await pump(3)
	check("Q: респавн qa4 зачищен («все убиты»)", not SScript.SWARMS.has("qa4"))
	# эталонный путь «все убиты» — реестр обязан чиститься
	var pack5 := spawn_pack("qa5", [Vector2i(6, 16), Vector2i(10, 18)])
	await pump(2)
	pack5[0].hurt(99, Vector2.ZERO)
	pack5[1].hurt(99, Vector2.ZERO)
	await pump(3)
	check("Q: путь «все убиты» — реестр чист", not SScript.SWARMS.has("qa5"))

func section_flee_pocket() -> void:
	# t44 RED-пин: геометрический карман поляны. Свип t43 (48 углов × 2 тайла):
	# из тайла (6,18) с углом разлёта 0° крыса упирается в стену — за 30 с симуляции
	# максимальное удаление от дома 8.8 px, FLEE_RADIUS=128 не достигается НИКОГДА,
	# крыса не despawn-ится → стая вечно «держит» живую особу (утечка живых мобов).
	# Анти-залипание: FLEE_STUCK_T секунд без обновления рекорда удаления от дома →
	# despawn тем же путём, что и FLEE_RADIUS (без XP/лута/тоста/убийства).
	# Бюджет пина: 12 с (720 кадров) — порог 9 с + запас; до фикса крыса жива вечно.
	var pack := spawn_pack("qa7", [Vector2i(6, 16), Vector2i(6, 18)])
	await pump(2)
	pack[0].hurt(99, Vector2.ZERO)   # 1/2 живых = 50% — паника; вторая крыса убегает
	await pump(2)
	var rat = pack[1]
	var rid: int = rat.get_instance_id()
	rat.set_flee(Vector2(1.0, 0.0))  # 0° — карманный угол из свипа t43 (STUCK, maxd 8.8)
	clear_toasts()
	var xp0 := GameState.xp
	var gone := false
	for i in range(720):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
		if not is_instance_id_valid(rid):
			gone = true
			break
	if not gone:
		var n: Node2D = instance_from_id(rid) as Node2D
		print("DEBUG t44 pocket: pos=%s vel=%s home_dist=%.1f (ожидание: despawn ≤12 c)" % [
			str(n.global_position), str(n.velocity), n.global_position.distance_to(n.home)])
	check("Q(t44): карманная крыса despawn-нулась в срок анти-залипания (≤12 c)", gone)
	check("Q(t44): despawn в кармане — без XP и без тоста убийства",
		GameState.xp == xp0 and n_toast("Мглокрыс повержен") == 0)
	await pump(5)
	check("Q(t44): реестр чист после карманного despawn", not SScript.SWARMS.has("qa7"))

func section_dying_xp() -> void:
	var pack6 := spawn_pack("qa6", [Vector2i(6, 16), Vector2i(9, 16), Vector2i(6, 18)])
	await pump(2)
	clear_toasts()
	var xp0 := GameState.xp
	pack6[0].hurt(99, Vector2.ZERO)
	pack6[0].hurt(99, Vector2.ZERO)
	await pump(2)
	check("Q: XP за крысу ровно +3", GameState.xp == xp0 + 3)
	check("Q: тост смерти крысы один", n_toast("Мглокрыс повержен") == 1)

func section_lock() -> void:
	var pack: Array = []
	for c in world.village_zone.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path.contains("mob_swarmling") and String(c.get("swarm_id")) == "qa6":
			pack.append(c)
	if pack.is_empty():
		check("Q: крысы qa6 живы для тестов", false)
		return
	# герой рядом — крысы должны были бы преследовать
	stub.global_position = (pack[0] as Node2D).global_position + Vector2(40.0, 0.0)
	GameState.input_locked = true
	var p0: Vector2 = (pack[0] as Node2D).global_position
	for i in range(90):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
	check("Q: input_locked — крысы заморожены", (pack[0] as Node2D).global_position.distance_to(p0) < 0.5)
	GameState.input_locked = false
	GameState.hp = 0
	var p1: Vector2 = (pack[0] as Node2D).global_position
	for i in range(90):
		await get_tree().physics_frame
	GameState.hp = GameState.max_hp
	check("Q: hp=0 героя — крысы заморожены", (pack[0] as Node2D).global_position.distance_to(p1) < 0.5)
	# freeze_t
	var r0 = pack[0]
	r0.freeze_t = 3.0
	var p2: Vector2 = r0.global_position
	await pump(60)
	check("Q: freeze_t — крыса стоит", r0.global_position.distance_to(p2) < 0.5)
	check("Q: freeze_t — синий тинт", r0.modulate.b > 0.9 and r0.modulate.r < 0.7)
