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
##   S5 — c21: бой/смерть: эфир неуязвим, материализация уязвима, смерть —
##        тост/achv/XP ровно по разу, тело убрано;
##   S6 — c21: пустой список wraiths в карте — узел не создаётся;
##   S7 — c21: сохранение/загрузка не ломают инвариант (пересборка == генератор,
##        дублей нет; персиста individual-смертей нет — паритет с archer/swarm).
## Тостов с именем моба при сборке мира быть не должно. RESULT: X pass / Y fail.

const WRAITH_SHEET := "res://assets/mobs_wraith.png"
const SW := preload("res://scripts/mob_swarmling.gd")  # статика стаи (SWARMS)

func _ready() -> void:
	await boot(save_for(0))
	await pump(3)
	# --- S1: T13 — ноль живых тенеплётов в деревне и пещере ---
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
	if aw.size() >= 2:
		var eth: Node2D = aw[aw.size() - 1]
		eth.call("hurt", 4, eth.global_position + Vector2(50.0, 0.0))
		check("WR0: c21 в эфире урон не принимается (hp 8)", int(eth.get("hp")) == 8)
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
