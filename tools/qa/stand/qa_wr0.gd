extends "res://mb_base.gd"
## QA WR0: тенеплёт — постоянство вердиктов.
## T13 («убери монстра призрака, напрягает в геймплее»): деревня и пещера —
## живых тенеплётов ноль (нишевые спавны у босса удалены; ЖИЗНЬ в этих зонах
## под запретом до отдельного вердикта).
## c21 («тенеплёт — оживить», Пепелище): зона читает координаты
## ashen_map.meta.mobs.wraiths генератора и спавнит ровно их — тем же
## паттерном, что лучники/стая; кадры — утверждённый лист assets/mobs_wraith.png
## без правок; скрипт mob_wraith.gd не перерисован и не перекрашен (тинт — c22).
## Секции:
##   S1 — ноль живых узлов mob_wraith в деревне и пещере (T13 цел);
##   S2 — резерв жив: скрипт существует, компилируется, инстанцируется;
##   S3 — схема/детерминизм генератора не тронуты: mobs.wraiths эммитится;
##   S4 — c21: Пепелище спавнит ровно записи wraiths (count>0, позиция ==
##        генераторная клетка, физ-узел 1, группа enemy, кадры из листа);
##   S5 — c21 бой/смерть + t28 (26.11) репин с историей: у заимки нет
##        неуязвимого эфира — погоня уязвима (прежний пин c21 «эфир неуязвим,
##        hp 8» поднят вердиктом), материализация легаси уязвима, смерть —
##        тост/achv/XP ровно по разу, тело убрано;
##   S6 — c21: пустой список wraiths в карте — узел не создаётся;
##   S7 — c21: сохранение/загрузка не ломают инвариант (пересборка == генератор,
##        дублей нет; персиста individual-смертей нет — паритет с archer/swarm).
##   S8 — t28 (26.11): полный проход механики «Тень-заимка» на своём
##        слизне-хозяине в деревне: погоня -> полёт (наказуем) -> оккупация
##        (бафф x1.5, призрак не достать) -> удар по хозяину = изгнание ->
##        реставрация баффа -> оглушение бьётся -> смерть прежним каналом.
##   S9 — t28 добор вердикта 26.11 11:26: доля уязвимого времени числом
##        (порог >= 0.45, факт ~0.50), факел (выкуривание/устрашение/срыв
##        вселения), золотой блик входа в окно, тост выкуривания.
## Тостов с именем моба при сборке мира быть не должно. RESULT: X pass / Y fail.

const WRAITH_SHEET := "res://assets/mobs_wraith.png"
const SW := preload("res://scripts/mob_swarmling.gd")  # статика стаи (SWARMS)

func _ready() -> void:
	await boot(save_for(0))
	await pump(3)
	# --- S1: T13 — ноль живых тенеплётов в деревне и пещере ---
	# ^ t28 (26.11, вердикт «Ощущение v1» C): пещерная НИША снята вердиктом уже
	# не как временный запрет T13, а как часть решения «надоедливые» — нуль-пины
	# остаются стражей; живут Пепелище (row=4, ниже) и подземелье (biome_zone).
	var vw: Array = find_mob(world.village_zone, "mob_wraith")
	check("WR0: деревня — живых тенеплётов 0 (T13) (n=%d)" % vw.size(), vw.is_empty())
	var dw: Array = find_mob(world.dungeon_zone, "mob_wraith")
	check("WR0: пещера при живом боссе — живых тенеплётов 0 (T13) (n=%d)" % dw.size(), dw.is_empty())
	check("WR0: при сборке мира тостов «Тенеплёт» не было", n_toast("Тенеплёт") == 0)
	# --- S2: резерв компилируется и создаётся ---
	var wpath := "res://scripts/mob_wraith.gd"
	check("WR0: скрипт существует", ResourceLoader.exists(wpath))
	var s: Script = load(wpath)
	check("WR0: скрипт компилируется", s != null)
	if s != null:
		var inst: Object = s.new()
		check("WR0: инстанс создаётся без ошибок", inst != null)
		if inst != null:
			inst.free()
	# --- S3: генераторную схему не трогали — координаты есть ---
	var amap: Dictionary = world.get("ashen_map")
	var meta: Dictionary = amap.get("meta", {})
	var mobs: Dictionary = meta.get("mobs", {})
	var wlist: Array = mobs.get("wraiths", [])
	check("WR0: генератор Пепелища эммитит mobs.wraiths (n=%d) — схема/сиды целы" % wlist.size(),
		wlist.size() >= 1)
	# t28 (26.11): вердикт зафиксировал ряд Пепелища РОВНО четырьмя тенеплётами
	# (ASHEN_MOBS.wraiths=4 — прокрегион не тронут, пин сверху вниз по факту).
	check("WR0: t28 вердикт: ряд Пепелища = 4 (ASHEN_MOBS.wraiths) (n=%d)" % wlist.size(),
		wlist.size() == 4)
	# --- S4: c21 — спавн ровно по генераторным координатам ---
	var az: Node = world.get("ashen_grid")
	if az == null:
		check("WR0: Пепелище собрано (ожидалось)", false)
		done()
		return
	var aw: Array = find_mob(az, "mob_wraith")
	check("WR0: c21 Пепелище — живых тенеплётов == записи генератора и >0 (n=%d want=%d)" % [aw.size(), wlist.size()],
		aw.size() == wlist.size() and aw.size() > 0)
	var pos_ok := aw.size() == wlist.size()
	var frames_ok := not aw.is_empty()
	var phys_ok := not aw.is_empty()
	for i in aw.size():
		var wt: Node2D = aw[i]
		var wcoord: Array = wlist[i]
		var want: Vector2 = az.call("tile_to_world", Vector2i(int(wcoord[0]), int(wcoord[1])))
		if wt.global_position.distance_to(az.global_position + want) > 0.01:
			pos_ok = false
		if not wt.is_in_group("enemy"):
			pos_ok = false
		var shapes := 0
		for ch in wt.get_children():
			if ch is CollisionShape2D:
				shapes += 1
		if shapes != 1:
			phys_ok = false
		var spr = wt.get("anim")
		if spr == null or not (spr is AnimatedSprite2D) \
				or not (spr as AnimatedSprite2D).sprite_frames.has_animation("idle_down"):
			frames_ok = false
		elif frames_ok:
			var anim2: AnimatedSprite2D = spr
			var seen := 0
			for dir_n in ["down", "left", "right", "up"]:
				for a_n in ["idle", "walk", "act"]:
					var an := "%s_%s" % [a_n, dir_n]
					if not anim2.sprite_frames.has_animation(an):
						continue
					for fi in anim2.sprite_frames.get_frame_count(an):
						var tx := anim2.sprite_frames.get_frame_texture(an, fi)
						if tx is AtlasTexture and String((tx as AtlasTexture).atlas.resource_path) == WRAITH_SHEET \
								and (tx as AtlasTexture).region.size == Vector2(16, 16):
							seen += 1
			if seen < 12:  # 4 ряда минимум по idle+walk (2 кадра) — 12+ кадров листа
				frames_ok = false
	check("WR0: c21 позиции == генераторные клетки, группа enemy", pos_ok)
	check("WR0: c21 кадры — AtlasTexture 16x16 утверждённого листа mobs_wraith.png", frames_ok)
	check("WR0: c21 у каждого тенеплёта ровно 1 CollisionShape2D", phys_ok)
	# --- S5: c21 — бой/смерть не ломают инварианты ---
	# ^ t28 (26.11, вердикт «принимай слизня и призрака»): ряд Пепелища перешёл
	# на автомат «Тень-заимка» (feel_v1). ДАТИРОВАННЫЙ РЕПИН: прежний пин c21
	# «в эфире урон не принимается (hp 8)» СНЯТ — у заимки нет неуязвимого эфира;
	# погоня видима и уязвима, прятаться призрак умеет только В ХОЗЯИНЕ (S8).
	# Смерть/тост/XP/achv — прежний канал (hp 8, урон 2, XP 15), он и ниже.
	if aw.size() >= 2:
		var eth: Node2D = aw[aw.size() - 1]
		check("WR0: t28 заимка стартует в погоне F_CHASE", int(eth.get("f_state")) == 0)
		eth.call("hurt", 4, eth.global_position + Vector2(50.0, 0.0))
		check("WR0: t28 погоня заимки — урон принимается (hp 4; прежний c21-пин «эфир неуязвим» поднят вердиктом)", int(eth.get("hp")) == 4)
		var mat: Node2D = aw[0]
		clear_toasts()
		var xp0 := int(GameState.xp)
		var ach0 := int(GameState.flags.get("ach.n.kill_wraith", 0))
		mat.call("_enter_materialize")
		mat.call("hurt", 4, mat.global_position + Vector2(50.0, 0.0))
		check("WR0: c21 в материализации урон принят (hp 4)", int(mat.get("hp")) == 4)
		mat.call("hurt", 4, mat.global_position + Vector2(50.0, 0.0))
		check("WR0: c21 смерть — тост ровно 1 (n=%d)" % n_toast("Тенеплёт рассеян"),
			n_toast("Тенеплёт рассеян") == 1)
		check("WR0: c21 смерть — XP +15 (d=%d)" % (int(GameState.xp) - xp0), int(GameState.xp) - xp0 == 15)
		var ach1 := int(GameState.flags.get("ach.n.kill_wraith", 0))
		check("WR0: c21 смерть — achv kill_wraith +1 (d=%d)" % (ach1 - ach0), ach1 - ach0 == 1)
		await until(func() -> bool: return not is_instance_valid(mat) or mat.is_queued_for_deletion(), 30)
		check("WR0: c21 мёртвый узел убран из дерева", not is_instance_valid(mat) or mat.is_queued_for_deletion())
		var after: Array = find_mob(az, "mob_wraith")
		check("WR0: c21 после смерти живых == генератор-1 (n=%d)" % after.size(),
			after.size() == wlist.size() - 1)
	else:
		check("WR0: c21 для боя нужны >=2 спавна", false)
	# --- S8: t28 (26.11) механика «Тень-заимка» — лист W5 секция C, вердикт ---
	# Границы по листу: погоня 3.0 c -> полёт вселения 1.5 c (фаза сквозь стены,
	# ЕДИНСТВЕННОЕ окно кроме оглушения) -> оккупация 6.0 c (хозяин урон x1.5,
	# призрак не достать) -> удар по хозяину = изгнание: тряска banish 1.0/0.1
	# и честное анти-окно stun 2.0 c. Тест в деревне (активная зона), на своём
	# слизне-хозяине; S7 ниже пересобирает мир — следов не остаёт.
	GameState.input_locked = false
	var wsc: Script = load("res://scripts/mob_wraith.gd")
	var ssc: Script = load("res://scripts/slime.gd")
	var ht := Vector2i(24, 26)
	var pl: Node2D = world.player
	var found := false
	for yy in range(6, 40):
		for xx in range(6, 40):
			if found:
				break
			var t := Vector2i(xx, yy)
			if bool(world.call("_village_walkable", t)) \
					and bool(world.call("_village_walkable", t + Vector2i(1, 0))) \
					and pl.global_position.distance_to(
						world.call("tile_to_world", t)) > 130.0:
				ht = t
				found = true
		if found:
			break
	var hs = ssc.new()
	world.village_zone.add_child(hs)
	hs.setup(world, ht)
	var wr = wsc.new()
	wr.feel_v1 = true
	world.village_zone.add_child(wr)
	wr.setup(world, ht + Vector2i(1, 0))
	# погоня — стартовое состояние автомата (проверка ДО физ-кадров: хозяин
	# соседний, и уже первый тик обязан перепрыгнуть в полёт — ниже)
	check("WR0: t28 S8 заимка стартует в погоне", int(wr.get("f_state")) == 0)
	await pump(2)
	var in_flight: bool = await until(func() -> bool: return int(wr.get("f_state")) == 1, 120)
	check("WR0: t28 S8 хозяин в 96 px -> полёт вселения F_FLIGHT", in_flight)
	wr.call("hurt", 2, wr.global_position + Vector2(30.0, 0.0))
	check("WR0: t28 S8 окно вселения наказуемо (hp 6)", int(wr.get("hp")) == 6)
	var occupied: bool = await until(func() -> bool: return int(wr.get("f_state")) == 2, 240)
	check("WR0: t28 S8 прилёт -> оккупация хозяина F_OCCUPIED", occupied)
	var prev: Dictionary = hs.get_meta("feel_prev") if hs.has_meta("feel_prev") else {}
	check("WR0: t28 S8 хозяин занят (feel_prev на хосте, урон x1.5 round=%d->%d)" % [
		int(prev.get("dmg", 0)), int(hs.get("dmg"))],
		not prev.is_empty() and int(hs.get("dmg")) == int(round(int(prev.get("dmg")) * 1.5)))
	var hp_occ := int(wr.get("hp"))
	wr.call("hurt", 2, wr.global_position + Vector2(30.0, 0.0))
	check("WR0: t28 S8 в хозяине призрак не достать (hp %d)" % int(wr.get("hp")), int(wr.get("hp")) == hp_occ)
	hs.call("hurt", 1, hs.global_position + Vector2(10.0, 0.0))
	var stunned: bool = await until(func() -> bool: return int(wr.get("f_state")) == 3, 90)
	check("WR0: t28 S8 удар по занятому хозяину изгоняет -> F_STUN", stunned)
	check("WR0: t28 S8 изгнание снимает бафф хозяина (dmg %d==%d, feel_prev снят)" % [
		int(hs.get("dmg")), int(prev.get("dmg", -1))],
		int(hs.get("dmg")) == int(prev.get("dmg", -1)) and not hs.has_meta("feel_prev"))
	var before_stun := int(wr.get("hp"))
	wr.call("hurt", 1, wr.global_position + Vector2(30.0, 0.0))
	check("WR0: t28 S8 оглушение — честное анти-окно, урон принят (hp %d)" % int(wr.get("hp")),
		int(wr.get("hp")) == before_stun - 1)
	clear_toasts()
	var xp_s8 := int(GameState.xp)
	wr.call("hurt", 99, wr.global_position + Vector2(30.0, 0.0))
	check("WR0: t28 S8 смерть заимки — прежний канал (тост 1, XP +15)",
		n_toast("Тенеплёт рассеян") == 1 and int(GameState.xp) - xp_s8 == 15)
	hs.call("hurt", 99, hs.global_position)
	await pump(3)
	# --- S9: t28 ПРАВКА ВЕРДИКТА 26.11 11:26 — доля уязвимого времени, факел,
	# маркер входа в окно. До правки пассивная доля была ~20% (hold 6.0 на цикл
	# 7.5); после: полёт 1.0 + погоня-под-замком 2.5 против hold 3.5 => ~50%
	# пассивно, факел добавляет принудительное окно (выкуривание 0.8 с). ---
	GameState.input_locked = false
	GameState.torches = 0
	clear_toasts()
	var ht9 := Vector2i(24, 26)
	var found9 := false
	for yy in range(6, 40):
		for xx in range(6, 40):
			if found9:
				break
			var t9 := Vector2i(xx, yy)
			if bool(world.call("_village_walkable", t9)) \
					and bool(world.call("_village_walkable", t9 + Vector2i(1, 0))) \
					and pl.global_position.distance_to(
						world.call("tile_to_world", t9)) > 130.0:
				ht9 = t9
				found9 = true
		if found9:
			break
	var hs9 = ssc.new()
	world.village_zone.add_child(hs9)
	hs9.setup(world, ht9)
	var wr9 = wsc.new()
	wr9.feel_v1 = true
	world.village_zone.add_child(wr9)
	wr9.setup(world, ht9 + Vector2i(1, 0))
	# пассивная доля: герой далеко, игрок «ждёт» — считаем доли кадров, где
	# урон принимается (любое состояние кроме оккупации), за 7 с (420 кадров)
	await pump(2)
	var hit_f := 0
	var total_f := 0
	for k in range(70):
		await pump(6)
		total_f += 6
		if int(wr9.get("f_state")) != 2:
			hit_f += 6
	var share9 := float(hit_f) / float(total_f)
	check("WR0: t28 S9 пассивная доля уязвимого времени >= 0.45 (факт %.2f; до правки ~0.20)" % share9,
		share9 >= 0.45)
	# факел: переносим пару к герою, ждём оккупацию, зажигаем (факел при себе) —
	# принудительное выкуривание 0.8 с с бликом входа и тостом
	hs9.global_position = pl.global_position + Vector2(20.0, 0.0)
	wr9.global_position = hs9.global_position
	var occ9: bool = await until(func() -> bool: return int(wr9.get("f_state")) == 2, 240)
	check("WR0: t28 S9 перед факлом заимка успевает засесть (оккупация)", occ9)
	GameState.torches = 1
	clear_toasts()
	var smoke_ok := false
	var flash_seen := false
	for k in range(120):
		await pump(1)
		if int(wr9.get("f_state")) != 2:
			smoke_ok = true
			if float(wr9.get("f_flash")) > 0.0:
				flash_seen = true
			break
	check("WR0: t28 S9 факел выкуривает из хозяина (окно принудительно)",
		smoke_ok and int(wr9.get("f_state")) == 3)
	check("WR0: t28 S9 золотой блик в момент входа в окно (f_flash)", flash_seen)
	check("WR0: t28 S9 тост выкуривания (n=%d)" % n_toast("Факел выкуривает"),
		n_toast("Факел выкуривает") == 1)
	# устрашение огнём: пока факел при себе и герой близко — ни полёта, ни
	# оккупации вообще (открытая уязвимая фигура у огня)
	var fear_bad := false
	for k in range(180):
		await pump(1)
		var st9 := int(wr9.get("f_state"))
		if st9 == 1 or st9 == 2:
			fear_bad = true
	check("WR0: t28 S9 у огня нет ни вселения, ни оккупации (3 с)", not fear_bad)
	wr9.call("hurt", 99, wr9.global_position)
	hs9.call("hurt", 99, hs9.global_position)
	await pump(3)
	GameState.torches = 0
	# --- S6: c21 — пустой список wraiths: узел не создаётся ---
	var zscript: Script = load("res://scripts/ashen_zone.gd")
	var z2: Node2D = zscript.new()
	add_child(z2)
	z2.call("setup", world, {"grid": [".....", "..P..", "....."], "meta": {"mobs": {}}})
	var none: Array = find_mob(z2, "mob_wraith")
	check("WR0: c21 при 0 записей wraiths узел не создаётся (n=%d)" % none.size(), none.is_empty())
	z2.free()
	# --- S7: c21 — сохранение/загрузка: пересборка == генератор, дублей нет ---
	check("WR0: c21 GameState.save_game()", GameState.save_game())
	check("WR0: c21 GameState.load_game()", GameState.load_game())
	world.queue_free()
	await pump(5)
	(SW.SWARMS as Dictionary).clear()
	var w2: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(w2)
	await pump(4)
	GameState.input_locked = false
	var az2: Node = w2.get("ashen_grid")
	var amap2: Dictionary = w2.get("ashen_map")
	var list2: Array = amap2.get("meta", {}).get("mobs", {}).get("wraiths", [])
	var aw2: Array = find_mob(az2, "mob_wraith") if az2 != null else []
	check("WR0: c21 после сейв/лоад пересборка: спавн == генератор без дублей (n=%d want=%d)" % [aw2.size(), list2.size()],
		az2 != null and aw2.size() == list2.size() and aw2.size() > 0)
	var dup := false
	var seenp := {}
	for n2 in aw2:
		var p2: Vector2 = (n2 as Node2D).global_position
		var key := "%.2f,%.2f" % [p2.x, p2.y]
		if seenp.has(key):
			dup = true
		seenp[key] = true
	check("WR0: c21 дублей позиций после пересборки нет", not dup)
	w2.queue_free()
	await pump(2)
	done()
