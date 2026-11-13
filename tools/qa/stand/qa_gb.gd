extends "res://mb_base.gd"
## QA GB (t19, P0-2 «честный Гром + маркер цели»).
## ЧАСТЬ А — честность босса пещеры (brute.gd, модель fair — только настоящий Гром):
##   G1 константы: замах 0.4–0.6 с, окно наказания ≥1.5 с, радиус ≤1.2×силуэта и
##      достижим от позы покоя героя; телеграф алый (дисциплина цвета); в модели
##      только Гром — Ведьма (mob_boss2) и ярусные отпрыски вне её;
##   G2 геометрия: полигон телеграфа == фактическая зона урона (сетка проб +
##      границы радиуса/сектора);
##   G3 замах: телеграф виден всё время замаха, урона во время замаха нет, удар
##      ровно один и только после замаха;
##   G4 промах/окно: цель вне сектора и за радиусом — урона нет, окно ≥90 кадров,
##      в окне Гром молчит, а удары героя валят (hp падает);
##   G5 после окна цикл возобновляется; G6 рывок не наносит урона, тост цел;
##   G7 ярусный моб сохранил прежний контактный урон (регрессия «не тронули»).
## ЧАСТЬ Б — маркер цели квеста (quest_marker.gd + world.objective_pos):
##   M1 старейшина; M2 сдача слаймов — торговец; M3 NG-линия: цель жива — маршрут
##      (извне на вход), мертва — цели нет; M4 стрелка: нет в кадре — показана на
##      орбите-эллипсе, орбита (64 направления) не задевает боевой HUD, цель в
##      кадре — стрелки нет.
## RESULT: X pass / Y fail.

const BR := preload("res://scripts/brute.gd")
const QM := preload("res://scripts/quest_marker.gd")

# боевой HUD на экране 640×360 (hud.gd): блок hp/маны/опыта слева сверху и
# панель скиллов/зелий/материалов снизу (прямоугольники — консервативные границы)
const HUD_TOP := Rect2(6, 6, 130, 34)      # x 6..136, y 6..40
const HUD_BOT := Rect2(250, 305, 316, 51)  # x 250..566, y 305..356

func _ready() -> void:
	await boot(save_for(0))
	await pump_raw(3)
	var boss = _spawn_grom()
	_clear_nearby(boss)
	_g1(boss)
	_g2(boss)
	await _g3(boss)
	await _g4(boss)
	await _g4b(boss)
	await _g4c(boss)
	await _g5(boss)
	await _g6(boss)
	boss.set_physics_process(false)  # паркуем ДО G7: добиток G-секций не должен
	await _g7(boss)                  # контаминировать dmg_log ярусного моба
	await _m()
	done()

func _spawn_grom():
	var b = BR.new()
	world.add_child(b)
	b.setup(world, Vector2i(500, 500))
	b.global_position = Vector2(300.0, 300.0)
	b.charge_cd = 0.0  # для детерминизма melee-секций (рывок проверяем отдельно, G6)
	return b

## flake-guard (поймано на полной батарее t19): деревенские слаймы (slime.gd —
## контактный урон без gate) и ярусные мобы бродят по randf и время от времени
## доходят до мишени — их попадания контаминировали dmg_log (ложный FAIL G4c:
## соло-прогоны просто не успевали дождаться гостя). Перед каждым окном
## наблюдений освобождаем всех врагов в 250 px от Грома, кроме него самого.
func _clear_nearby(boss) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == boss or not is_instance_valid(e):
			continue
		if e is Node2D and (e as Node2D).global_position.distance_to(boss.global_position) <= 250.0:
			e.free()

## один physics-кадр; возвращает число кадров до условия, -1 — таймаут
func _waitf(cond: Callable, maxf: int) -> int:
	for i in range(maxf):
		await get_tree().physics_frame
		if bool(cond.call()):
			return i + 1
	return -1

# ------------------------------ часть А ------------------------------

func _g1(boss) -> void:
	check("GB G1: замах в каноне 0.4–0.6 с (=%.2f)" % float(BR.WINDUP_TIME),
		float(BR.WINDUP_TIME) >= 0.4 and float(BR.WINDUP_TIME) <= 0.6)
	check("GB G1: окно наказания ≥1.5 с (=%.2f)" % float(BR.STRIKE_RECOVER),
		float(BR.STRIKE_RECOVER) >= 1.5)
	check("GB G1: радиус удара ≤1.2×силуэта (бокс 18 px): %.1f≤21.6" % float(BR.HIT_DIST_BOSS),
		float(BR.HIT_DIST_BOSS) <= 1.2 * 18.0 + 0.001)
	check("GB G1: радиус достижим из позы покоя героя (≥14 px)", float(BR.HIT_DIST_BOSS) >= 14.0)
	# ширина рисованого силуэта: играющий кадр × масштаб anim
	var tex: Texture2D = boss.anim.sprite_frames.get_frame_texture("walk", 0)
	var drawn_w := float(tex.get_width()) * float(boss.anim.scale.x)
	check("GB G1: радиус ≤1.2×рисованого силуэта (%.1f px)" % drawn_w,
		float(BR.HIT_DIST_BOSS) <= 1.2 * drawn_w + 0.001)
	var c: Color = boss.tg.color
	check("GB G1: телеграф алый — смертельное (дисциплина цвета)", c.r > c.g and c.r > c.b and c.a > 0.0)
	check("GB G1: честная модель включена у Грома", bool(boss.fair))
	var w2 = load("res://scripts/mob_boss2.gd").new()
	world.add_child(w2)
	w2.setup(world, Vector2i(420, 420))
	check("GB G1: Ведьма вне честной модели (контактное поведение цело)",
		not bool(w2.fair) and w2.get("tg") == null)
	w2.free()

func _g2(boss) -> void:
	boss.strike_dir = Vector2.RIGHT
	var poly: PackedVector2Array = boss.telegraph_points()
	var mism := 0
	var n := 0
	for gx in range(-24, 25, 3):
		for gy in range(-24, 25, 3):
			var v := Vector2(float(gx), float(gy))
			if v.length() < 1.0:
				continue
			n += 1
			var in_poly := Geometry2D.is_point_in_polygon(v, poly)
			var in_pred: bool = boss.strike_contains(boss.global_position + v)
			if in_poly != in_pred:
				mism += 1
	check("GB G2: полигон телеграфа == зона урона (проб %d, расхождений 0)" % n,
		mism == 0 and n >= 50)
	var r := float(BR.HIT_DIST_BOSS)
	check("GB G2: по оси внутри радиуса — поражаёт",
		boss.strike_contains(boss.global_position + Vector2(r - 1.0, 0.0)))
	check("GB G2: по оси за радиусом — нет",
		not boss.strike_contains(boss.global_position + Vector2(r + 1.0, 0.0)))
	check("GB G2: у края внутри сектора (54°) — поражаёт",
		boss.strike_contains(boss.global_position + Vector2(cos(0.95), sin(0.95)) * (r - 1.0)))
	check("GB G2: у края вне сектора (66°) — нет",
		not boss.strike_contains(boss.global_position + Vector2(cos(1.15), sin(1.15)) * (r - 1.0)))
	check("GB G2: центр Грома — контакт смертелен", boss.strike_contains(boss.global_position))

func _g3(boss) -> void:
	_clear_nearby(boss)
	stub.dmg_log.clear()
	stub.global_position = boss.global_position + Vector2(12.0, 0.0)
	var f := 0
	var wind_frames := 0
	var vis_frames := 0
	var early := false
	var hit_f := -1
	while f < 90 and hit_f < 0:
		f += 1
		await get_tree().physics_frame
		if float(boss.windup_t) > 0.0:
			wind_frames += 1
			if boss.tg != null and boss.tg.visible:
				vis_frames += 1
		if stub.dmg_log.size() > 0:
			hit_f = f
			if float(boss.windup_t) > 0.0:
				early = true
	check("GB G3: замах начат", wind_frames > 0)
	check("GB G3: телеграф виден всё время замаха (кадров %d/%d, ≥20)" % [vis_frames, wind_frames],
		wind_frames > 0 and vis_frames == wind_frames and vis_frames >= 20)
	check("GB G3: во время замаха урона нет", not early)
	check("GB G3: удар только после замаха (кадр %d ≥24)" % hit_f, hit_f >= 24)
	check("GB G3: удар ровно один", stub.dmg_log.size() == 1)
	check("GB G3: урон == dmg (%d)" % int(boss.dmg),
		stub.dmg_log.size() == 1 and int(stub.dmg_log[0]) == int(boss.dmg))
	check("GB G3: после удара телеграф скрыт, окно наказания открыто",
		boss.tg != null and not boss.tg.visible and float(boss.recover_t) > 0.0)

func _g4(boss) -> void:
	# цель осталась в секторе: в окне Гром обязан молчать, удары героя валят
	_clear_nearby(boss)
	var rec_f := 0
	for i in range(50):
		rec_f += 1
		await get_tree().physics_frame
	check("GB G4: через 50 кадров окна Гром не бил", stub.dmg_log.size() == 1)
	var hp0 := int(boss.hp)
	boss.hurt(2, boss.global_position + Vector2(30.0, 0.0))
	check("GB G4: удар героя в окно ватится (hp %d→%d)" % [hp0, int(boss.hp)],
		int(boss.hp) == hp0 - 2)
	while float(boss.recover_t) > 0.0 and rec_f < 250:
		rec_f += 1
		await get_tree().physics_frame
	check("GB G4: окно наказания ≥90 кадров (1.5 с @60 Гц): %d" % rec_f, rec_f >= 90)

func _g4b(boss) -> void:
	# промах по УГЛУ: цель в радиусе, но вне телеграф-сектора
	_clear_nearby(boss)
	stub.dmg_log.clear()
	var wf := await _waitf(func() -> bool: return float(boss.windup_t) > 0.0, 120)
	check("GB G4b: замах после окна возобновился", wf > 0)
	var sd: Vector2 = boss.strike_dir
	stub.global_position = boss.global_position + sd.rotated(1.35) * 13.0
	var sf := await _waitf(func() -> bool: return float(boss.recover_t) > 0.0, 120)
	check("GB G4b: цель в радиусе, но вне сектора — промах (окно открылось)",
		stub.dmg_log.size() == 0 and sf > 0)

func _g4c(boss) -> void:
	# промах по РАДИУСУ: цель за HIT_DIST_BOSS — урона нет и после замаха
	_clear_nearby(boss)
	stub.dmg_log.clear()
	var wf := await _waitf(func() -> bool: return float(boss.windup_t) > 0.0, 120)
	check("GB G4c: новый замах начат", wf > 0)
	var sd: Vector2 = boss.strike_dir
	stub.global_position = boss.global_position + sd * (float(BR.HIT_DIST_BOSS) + 6.0)
	var sf := await _waitf(func() -> bool: return float(boss.recover_t) > 0.0, 120)
	check("GB G4c: за пределами радиуса урона нет (окно открылось)",
		stub.dmg_log.size() == 0 and sf > 0)

func _g5(boss) -> void:
	# после окна цикл жив: возвращаемся в сектор — снова прилетает
	_clear_nearby(boss)
	stub.dmg_log.clear()
	stub.global_position = boss.global_position + boss.strike_dir * 10.0
	var hf := await _waitf(func() -> bool: return stub.dmg_log.size() > 0, 180)
	check("GB G5: после окна цикл возобновился — удар снова проходит",
		hf >= 0 and stub.dmg_log.size() == 1)

func _g6(boss) -> void:
	# рывок — сближение, не атака: урона не несёт, предупреждающий тост цел
	_clear_nearby(boss)
	boss.recover_t = 0.0
	boss.windup_t = 0.0
	boss.charge_cd = 0.1
	boss.charge_t = 0.0
	stub.dmg_log.clear()
	clear_toasts()
	stub.global_position = boss.global_position + Vector2(0.0, -55.0)
	var saw_rush := false
	for i in range(50):
		await get_tree().physics_frame
		if float(boss.rush_t) > 0.0:
			saw_rush = true
	check("GB G6: рывок выполнен", saw_rush)
	check("GB G6: рывок не наносит урона", stub.dmg_log.size() == 0)
	check("GB G6: тост «Гром бросается вперёд» сохранён", n_toast("Гром бросается") >= 1)

func _g7(boss) -> void:
	# регрессия «не тронули»: ярусный отпрыск бьёт прежним контактным уроном
	_clear_nearby(boss)
	var m1 = BR.new()
	world.add_child(m1)
	m1.boss = false
	m1.tier = 1
	m1.setup(world, Vector2i(410, 410))
	m1.global_position = stub.global_position + Vector2(16.0, 0.0)
	check("GB G7: ярусный моб вне честной модели", not bool(m1.fair))
	stub.dmg_log.clear()
	for i in range(90):
		await get_tree().physics_frame
		# герой «подпирает» моба телом, как живой герой у стены: без этого
		# выталкивание (безопасный зазор 10 px) держит пассивную мишень ровно
		# за порогом HIT_DIST_MOB=9 — это стенд-мишень, а не потеря урона
		stub.global_position = m1.global_position + Vector2(3.5, 7.5)  # центр-центр 8.3 px
	var hits: int = stub.dmg_log.size()
	var allv: bool = hits > 0
	for v in stub.dmg_log:
		if int(v) != int(m1.dmg):
			allv = false
	check("GB G7: ярусный моб бьёт старым контактом (попаданий %d, урон везде %d)" % [hits, int(m1.dmg)],
		allv)
	m1.set_physics_process(false)

# ------------------------------ часть Б ------------------------------

func _m() -> void:
	# M1: квест старейшины — стрелка на старейшину
	GameState.elder_quest = 0
	GameState.slime_quest = 0
	GameState.cave_state = 0
	GameState.flags = {}
	var el: Node2D = world.call("_find_npc", "elder")
	check("GB M1: квест старейшины — цель = старейшина",
		el != null and world.objective_pos() == el.global_position)
	# M2: слаймы добыты — цель = торговец (сдача)
	GameState.elder_quest = 2
	GameState.slime_quest = 1
	GameState.slime_kills_circle = 3
	var me: Node2D = world.call("_find_npc", "merchant")
	check("GB M2: слаймы добыты — цель = торговец",
		me != null and world.objective_pos() == me.global_position)
	# M3: NG-линия — Ведьма жива: цель видна; извне Пепелища маршрут = вход
	GameState.slime_quest = 2
	GameState.cave_state = 4
	var ent: Vector2 = world.tile_to_world(world.get("ASHEN_ENTRANCE_TILE"))
	var ob: Vector2 = world.objective_pos()
	check("GB M3: NG-линия (Ведьма жива): извне цель = вход на Пепелище",
		ob != Vector2.INF and ob == ent)
	# M3b: Ведьма мертва — цели нет
	GameState.flags = {"ashen.boss": "dead"}
	check("GB M3b: Ведьма мертва — цели нет", world.objective_pos() == Vector2.INF)
	GameState.flags = {}
	GameState.cave_state = 0
	GameState.slime_quest = 0
	GameState.elder_quest = 0
	# M4: орбита стрелки — чистая математика (64 направления vs боевой HUD)
	var vp: Viewport = world.get_viewport()
	var qm_size: Vector2 = vp.get_visible_rect().size
	var center := qm_size * 0.5
	var rx: float = maxf(center.x - QM.RX_PAD, 8.0)
	var ry: float = maxf(center.y - QM.RY_PAD, 8.0)
	var bad := 0
	for i in range(64):
		var a := TAU * float(i) / 64.0
		var d := Vector2(cos(a), sin(a))
		var k := sqrt(pow(d.x / rx, 2.0) + pow(d.y / ry, 2.0))
		var p := center + d / k
		var box := Rect2(p - Vector2(9.0, 9.0), Vector2(18.0, 18.0))
		if box.intersects(HUD_TOP) or box.intersects(HUD_BOT):
			bad += 1
	check("GB M4: орбита (64 направления) не задевает боевой HUD", bad == 0)
	# M4c: цель вне кадра — стрелка на орбите; в кадре — спрятана.
	# Сторону «за экраном» выбираем адаптивно (подстраховка от клампа камеры
	# о границы карты): проверяем экранное положение той же формулой, что маркер.
	# t51 (зум мира 1): при кадре 640×360 деревня 48×30 (768×480 px) целиком
	# внутри клампа камеры — старый сайд ±260 не выносит старейшину (x=168)
	# за экран. Механизм стрелки — экранная страховка на зумов >1, потому
	# прогоняем M4c с форсированным zoom 2 (вид 320×180, тот же живой
	# canvas-transform путь) и возвращаем зум мира в конце блока.
	el = world.call("_find_npc", "elder")
	var cam: Camera2D = world.get("cam")  # камера — чайлд НАСТОЯЩЕГО игрока (on -9000),
	# за stub в стенде она не ходит — ведём вручную, как живой follow
	var z0: Vector2 = cam.zoom
	cam.zoom = Vector2(2.0, 2.0)
	var placed_off := false
	var dbg := ""
	for side in [-260.0, 260.0]:
		world.player.global_position = el.global_position + Vector2(side, 0.0)
		cam.global_position = world.player.global_position
		for i in range(4):
			await get_tree().process_frame
		var sp: Vector2 = vp.get_canvas_transform() * el.global_position
		dbg = "side=%d sp=%s obj=%s" % [int(side), str(sp), str(world.objective_pos())]
		if sp.x <= 8.0 or sp.x >= qm_size.x - 8.0 or sp.y <= 8.0 or sp.y >= qm_size.y - 8.0:
			placed_off = true
			break
	print("T19 M4DBG ", dbg)
	check("GB M4: создан режим «цель вне кадра» (страховка от клампа камеры)", placed_off)
	var arrow = world.get("quest_marker").get("arrow")
	check("GB M4: цель вне кадра — стрелка показана", placed_off and bool(arrow.visible))
	var ap: Vector2 = arrow.position
	var kk := sqrt(pow((ap.x - center.x) / rx, 2.0) + pow((ap.y - center.y) / ry, 2.0))
	check("GB M4: стрелка лежит на орбите (k=%.3f≈1)" % kk, absf(kk - 1.0) <= 0.02)
	var abox := Rect2(ap - Vector2(9.0, 9.0), Vector2(18.0, 18.0))
	check("GB M4: стрелка не пересекает прямоугольники боевого HUD",
		not abox.intersects(HUD_TOP) and not abox.intersects(HUD_BOT))
	world.player.global_position = el.global_position + Vector2(18.0, 0.0)
	cam.global_position = world.player.global_position
	for i in range(4):
		await get_tree().process_frame
	check("GB M4: цель в кадре — стрелка скрыта", not bool(arrow.visible))
	cam.zoom = z0  # t51: зум мира (1) возвращён
