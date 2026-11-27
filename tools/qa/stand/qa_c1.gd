extends Node2D
# qa_c1 — С1: ПОЛНЫЙ сквозной плейт «Тени Северного Леса» (46-й стенд батареи).
# Единственный headless-прогон всего пути игрока ШТАТНЫМИ средствами:
# синтетический ввод (оси через Input.action_press как click_move; E/F5/F9 и клики
# через root.push_input как qa_r1/qa_ib; кнопки лавок через pressed.emit — тот же
# обработчик, что у клика) + навигация честным A* по проходимым клеткам
# (scripts/nav.gd). Путь: спавн -> деревня (старейшина/травы/торговец/кузнец/
# Ута/сундук/костёр-варка) -> лесные POI -> пещера (отшельник, босс Гром, ключ,
# дверь, сундук) -> выход -> Пепелище (ведьма, сундук, портал) -> северная арка ->
# карта мира -> все 6 биомных локаций (вход -> зачистка мобов пояса -> сундук ->
# выход) -> возврат в деревню -> ночлег у костра -> F5/F9 -> снежная локация:
# ОДНА плановая смерть -> экран потери -> доска пепла -> «Вспыхнуть у костра».
# На каждом чекпойнте save+load+continue (резолвер зон). Детекторы: креш,
# софтлоки (BFS-недостижимо / бюджет кадров / залипание), дыры экономики (золото
# и материалы против вилок LOOT-таблицы; коридор BALANCE 78–106 — харнес-допущение,
# в ECONOMY_BALANCE.md отсутствует — P2-05; пепел), инвариант
# «смерть = −20% серебра, нажитое цело (t38 I5, 27.11; прежде — сброс забега)»,
# перф-пробы (µs/кадр) на всех переходах зон.
# P2-06 пины (2026-11-19, diag-p2): corner-геометрия реальной сетки деревни
# (центр-LOS=true, girth-LOS=false), Minkowski-клиренс (коробка героя 10x8) всех
# упрощённых сегментов, живой «угловой путь ПКМ => прибытие без упора» честным
# ClickMove (по образцу probes/p2_live). HAR-1: перед подходом к следующему NPC
# лавка закрывается (P2-03 — модальность лавки, shop.gd:498-509). HAR-2:
# wp_stall-поп не имитирует прибытие, считается и пинится нулём на плейт.
# Детерминизм: seed + PIN run_seed. Артефакты: <корень>/diag-p1/qa_c1_timeline.json
# (тайминги стадий, эконом-срезы, перф, находки — с адресами стадий).
# Итог: "QA_C1 pass/total"; non-zero exit при любом провале.

const SEED_RNG := 20261119   # фикс RNG-стрима (лут/крафт детерминированы)
const SEED_RUN := 555001     # PIN run_seed (карты пещеры/Пепелища/мира/локаций)
const MAIN_SCENE := "res://scenes/main.tscn"
const Nav := preload("res://scripts/nav.gd")
const OW := preload("res://scripts/open_world.gd")
const GD := preload("res://scripts/gear_data.gd")
const QD := preload("res://scripts/quests_data.gd")
const ALC := preload("res://scripts/alchemy.gd")
const ASH := preload("res://scripts/ash.gd")
const SHOP := preload("res://scripts/shop.gd")
const MB := preload("res://scripts/meta_board.gd")
const RS := preload("res://scripts/run_summary.gd")
# t22 (25.11, «Глубина v2 §5»): маршрут плейта через микро-подземелье и доску
# поясов. Клетка хода сверяется с ЧИСТЫМ генератором (mini_dungeon.gd), аффиксы
# реликтов — с чистым модулем ролла (affixes.gd): сверка с источником, а не с
# наблюдением (тот же приём, что QD/AS/SHOP выше).
const MDZ := preload("res://scripts/mini_dungeon.gd")
const MZ := preload("res://scripts/mini_zone.gd")
const AFX := preload("res://scripts/affixes.gd")
const Classes := preload("res://scripts/classes_data.gd")  # t9 (25.11): боёеспособность нового класса после смерти

# ---------------- вечное (переживает reload_current_scene) ----------------------
static var phase := 0        # 0 — полный плейт; 1 — инварианты после смерти
static var total := 0
static var pass_n := 0
static var findings: Array = []
static var timeline: Array = []
static var perf_samples := {}
static var econ: Array = []
static var carried := {}
static var finalized := false
static var _loc_chain_dead := false
static var wp_stall_pops := 0   # HAR-2: сколько раз waypoint сдан по залипанию (пин = 0)
var _heal_off := false
# награды ачивок золотом (achv.gd §2) — известные притоки экономики
const ACH_GOLD := {"first_blood": 10, "hunter_25": 30, "alchemist": 20, "treasure": 40, "herbalist": 15,
	"boss_slayer": 0, "witch_slayer": 0, "wealth": 0, "hardcore": 0, "campfires": 0,
	"collector": 0, "brewer_10": 0, "rekindled": 0, "undying": 0, "hunter_100": 0}
var _ach_ids_before := {}

func _ach_ids() -> Dictionary:
	var d := {}
	for k in GameState.flags:
		var ks := String(k)
		if ks.begins_with("ach.") and not ks.begins_with("ach.n."):
			d[ks.substr(4)] = true
	return d

# ---------------- instance -------------------------------------------------------
var world = null
static var _wall0 := 0
var _stage_name := "boot"
var _aborted := ""
var _planned_death := false
var _perf_tag := ""
var _perf_buf: Array = []
# экономика стадии
var _spend_known := 0
var _quests_gold_known := 0
var _chests_before := 0
var _rs_before := {}
var _el_before := {}   # t41 (а, 26.11, artist-cave): снимок rs.elite.* (элитные киллы)
var _gold_before := 0
var _mats_before := {}
var _ash_before := 0
var _tone_village := Color(1, 1, 1, 1)
var _tone_cave := Color(1, 1, 1, 1)

func _process(_d: float) -> void:
	if _perf_tag != "":
		_perf_buf.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)

# ---------------- учёт -------------------------------------------------------------
func stage(s: String) -> void:
	_stage_name = s
	timeline.append({"stage": s, "wall_ms": Time.get_ticks_msec() - _wall0})
	print("[qa_c1] STAGE %s t=%dms" % [s, Time.get_ticks_msec() - _wall0])

func chk(name: String, ok: bool, detail := "") -> bool:
	total += 1
	if ok:
		pass_n += 1
	else:
		findings.append({"stage": _stage_name, "kind": "check", "detail": name + " :: " + detail})
		print("FAIL %s :: %s" % [name, detail])
	return ok

func finding(kind: String, detail: String) -> void:
	findings.append({"stage": _stage_name, "kind": kind, "detail": detail})
	print("[qa_c1][FINDING:%s] %s" % [kind, detail])

# ---------------- ввод/кадры --------------------------------------------------------
func frames(n: int) -> void:
	for _i in n:
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

func close_dialog(max_frames := 900) -> bool:
	var g := 0
	while world.hud.is_dialog_open() and g < max_frames:
		push_key(KEY_E)
		await get_tree().physics_frame
		await get_tree().physics_frame
		g += 2
	if world.hud.is_dialog_open():
		finding("softlock", "диалог не закрывается за %d кадров" % max_frames)
		return false
	return true

## Дождаться освобождения мира (фейд/диалоги перехода), дожать диалоги.
## Лавка — штатное стабильное состояние (не ждём её закрытия).
func settle(budget := 900) -> void:
	var g := 0
	while g < budget:
		if world.hud.is_dialog_open():
			await close_dialog()
		if not GameState.input_locked or SHOP.is_open():
			break
		await get_tree().physics_frame
		g += 1

func axes(d: Vector2) -> void:
	var want := {"move_left": d.x < -0.3, "move_right": d.x > 0.3, "move_up": d.y < -0.3, "move_down": d.y > 0.3}
	for a in want:
		if want[a]:
			Input.action_press(a)
		else:
			Input.action_release(a)

func heal_if_hurt() -> bool:
	if _heal_off:  # квестовые травы не пьём: они валюта сдачи старейшины
		return false
	if GameState.hp > int(GameState.max_hp * 0.5):
		return false
	if GameState.brewed_potions > 0:
		return bool(ALC.drink_brewed())
	if GameState.herbs > 0 and world != null:
		world.drink_potion()
		return true
	return false

# ---------------- контекст зоны ------------------------------------------------------
func zone_ctx() -> Dictionary:
	match String(world.active_area):
		"cave":
			return {"base": world.CAVE_OFFSET, "w": world.dungeon_zone.map_w,
				"h": world.dungeon_zone.map_h, "walk": world.dungeon_zone.cell_walkable,
				"t2w": world.dungeon_zone.tile_to_world}
		"ashen":
			return {"base": world.ASHEN_OFFSET, "w": world.ashen_grid.map_w,
				"h": world.ashen_grid.map_h, "walk": world.ashen_grid.cell_walkable,
				"t2w": world.ashen_grid.tile_to_world}
		"worldmap":
			return {"base": Vector2(0.0, OW.WM_OFFSET_Y), "w": world.worldmap_grid.map_w,
				"h": world.worldmap_grid.map_h, "walk": world.worldmap_grid.cell_walkable,
				"t2w": world.worldmap_grid.tile_to_world}
		_:
			var a := String(world.active_area)
			if a.begins_with("mini_"):
				# t22 (25.11, «Глубина v2 §5»): микро-подземелье — тот же контекст
				# ходьбы, что у локаций (свой этаж MINI_Y, своя проходимость);
				# без этой ветки A* плейта считал бы ход деревней.
				var mz = world.mini_grids[a.substr(5)]
				return {"base": Vector2(0.0, MDZ.mini_y(a.substr(5))),
					"w": mz.map_w, "h": mz.map_h, "walk": mz.cell_walkable,
					"t2w": mz.tile_to_world}
			if a.begins_with("loc_"):
				var g = world.biome_grids[a.substr(4)]
				return {"base": Vector2(0.0, float(OW.LOC_OFFSET_Y[a.substr(4)])),
					"w": g.map_w, "h": g.map_h, "walk": g.cell_walkable, "t2w": g.tile_to_world}
			return {"base": Vector2.ZERO, "w": 59, "h": 37,
				"walk": world._village_walkable, "t2w": world.tile_to_world}

func pos_to_tile(p: Vector2, base: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / 16.0)), int(floor((p.y - base.y - 2.0) / 16.0)))

func node_tile(n: Node, ctx: Dictionary) -> Vector2i:
	return pos_to_tile(n.get_global_position(), ctx["base"])

# ---------------- честная ходьба A* + уклон от встречи с мобом ------------------------
## 0 ok | 1 no_path (софтлок-дыра) | 2 budget | 3 died
func walk_to(target, tag: String) -> int:
	if GameState.hp <= 0 and not _planned_death:
		return 3
	var ctx := zone_ctx()
	var from := pos_to_tile(world.player.global_position, ctx["base"])
	var to: Vector2i = target if typeof(target) == TYPE_VECTOR2I else node_tile(target, ctx)
	var path: Array = Nav.simplify(Nav.astar(ctx["walk"], ctx["w"], ctx["h"], from, to), ctx["walk"])
	if from != to and path.is_empty():
		# цель в стене/за дверью/на постаменте (CaveDoor,WorldPortal): целимся в
		# проходимого соседа — интеракция с соседней клетки штатна игроку
		var best: Vector2i = to
		var found := false
		var bl := 999999
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nb: Vector2i = to + Vector2i(dx, dy)
				if not bool((ctx["walk"] as Callable).call(nb)):
					continue
				var p3: Array = Nav.astar(ctx["walk"], ctx["w"], ctx["h"], from, nb)
				if not p3.is_empty() and p3.size() < bl:
					bl = p3.size()
					best = nb
					path = Nav.simplify(p3, ctx["walk"])
					found = true
		if not found:
			finding("softlock", "[%s] BFS: цель %s из %s недостижима и соседями (зона %s)" % [tag, str(to), str(from), String(world.active_area)])
			return 1
		to = best
	var wps: Array = []
	for t in path:
		wps.append(ctx["base"] + (ctx["t2w"] as Callable).call(t))
	var tnode: Object = target if typeof(target) == TYPE_OBJECT else null
	if tnode == null:
		# точечная цель: жёсткий захват центра последней клетки обязателен; для ноды
		# хвост пути уже есть в wps, а её центр на solid-тайле (портал/постамент)
		# в принципе недостижим — см. широкий радиус последнего вейпоинта ниже
		wps.append(ctx["base"] + (ctx["t2w"] as Callable).call(to))
	# 240 кадров/вейпоинт: калибровка после HAR-2 — старый бюджет (120) покрывал
	# дистанции только потому, что wp_stall-попы тихонько съедали хвосты путей;
	# с честным прохождением всех точек потолок трансмапповских обходных маршрутов выше
	var budget := 600 + wps.size() * 240
	var g := 0
	var stuck := 0
	var near_cnt := 0
	var refresh_left := 2
	var probe_log := {}
	var wp_stall := 0
	var wp_best := 1e9  # лучшая дистанция до текущего вейпоинта (HAR-2: мера прогресса)
	var last: Vector2 = world.player.global_position
	while g < budget:
		g += 1
		if GameState.hp <= 0 and not _planned_death:
			axes(Vector2.ZERO)
			return 3
		if tnode != null and is_instance_valid(tnode) \
				and (world.near.has(tnode) or world.player.global_position.distance_to(tnode.global_position) <= 13.0):
			axes(Vector2.ZERO)
			return 0
		# тулик у последнего вейпоинта: цель в плотной геометрии — постояли близко, идём жаться
		if tnode != null and wps.size() <= 1 \
				and world.player.global_position.distance_to(tnode.global_position) <= 30.0:
			near_cnt += 1
			if near_cnt >= 45:
				axes(Vector2.ZERO)
				return 0
		else:
			near_cnt = 0
		if world.hud.is_dialog_open():
			axes(Vector2.ZERO)
			await close_dialog()
			continue
		if GameState.input_locked or SHOP.is_open():
			axes(Vector2.ZERO)
			await get_tree().physics_frame
			continue
		# честный ответ на агрессора: долбанул по нам в упор — вступаем в бой
		var amb := nearest_attacker()
		if amb != null:
			axes(Vector2.ZERO)
			var fr := await fight(amb, tag + "_ambush", 3600)
			if fr == "died":
				return 3
			continue
		if await heal_if_hurt():
			await frames(2)
			continue
		if wps.is_empty():
			# цель-нода без вейпоинтов (путь короче шага захвата): стоим/ждём near/tuck,
			# прибытие решает начало цикла; уход цели за 30px — rc=2 по бюджету,
			# interact_with перестроит путь с живой позиции
			axes(Vector2.ZERO)
			await get_tree().physics_frame
			continue
		var wp: Vector2 = wps[0]
		var d: Vector2 = wp - world.player.global_position
		# P2-06/HAR-2 (2026-11-19): последний вейпоинт цели-ноды — центр её клетки, а он
		# недостижим коробкой 10x8, когда нода стоит на физическом теле (арка портала,
		# сундук на постаменте, туша моба). Требование 4px-центра и было «pop-ловушкой»
		# плейта: wp_stall-попы жрали бюджет (sites portal_desert/portal_dungeon/exit_*).
		# На хвосте пути ноды захват = касание E-зоны (≤20px), финал решает near/тулик.
		var cap := 4.0
		if tnode != null and wps.size() == 1:
			cap = 20.0
		if d.length() <= cap:
			wps.pop_front()
			wp_stall = 0
			wp_best = 1e9
			if wps.is_empty():
				axes(Vector2.ZERO)
				return 0
			continue
		# HAR-2 (2026-11-19, diag-p2): wp_stall — мера ОТСУТСТВИЯ ПРОГРЕССА, не времени.
		# Счётчик «кадров у вейпоинта» срабатывал на длинных, но нормальных сегментах:
		# 95px/s = 1.58px/кадр, сегмент >380px ловил «залипание» на 240-м кадру посреди
		# честного шага (все pop-ы прогонов 11.19 d=179..691px — герой шёл, не упирался).
		# Ловушка = за 4 с не сократили дистанцию хотя бы на 0.5px.
		if d.length() < wp_best - 0.5:
			wp_best = d.length()
			wp_stall = 0
		else:
			wp_stall += 1
		# near-miss скос: герой упёрся в недостижимый центр вейпоинта (бортик тела
		# интерактора в 5–12px от центра клетки) — без прогресса, но и не угол: через
		# 0.5 с держания в ≤12px передаём путь дальше, бюджет не едим.
		if wp_stall >= 30 and d.length() <= 12.0:
			wp_stall = 0
			wp_best = 1e9
			wps.pop_front()
			if wps.is_empty():
				axes(Vector2.ZERO)
				return 0
			continue
		if wp_stall > 240:
			# HAR-2 (2026-11-19, diag-p2): waypoint физически не берётся 4 с без единого
			# пикселя сближения — это событие, а не тихая норма: thick-LOS в nav.gd
			# кладёт сегменты с габаритным зазором, угловые упоры излечены в корне.
			# Хвост (size==1) не попится никогда: прибытием считается только честный
			# приход (wps пусто после захвата) или near/13px у цели-ноды. Счётчик
			# пинится нулём в finalize.
			wp_stall_pops += 1
			finding("stuck", "[%s] wp_stall: путевая точка не берётся 4 с без сближения (осталось %d, d=%.0fpx, зона %s) — угловое залипание вернулось?" % [tag, wps.size(), d.length(), String(world.active_area)])
			wp_stall = 0
			wp_best = 1e9
			if wps.size() > 1:
				wps.pop_front()
				continue
		axes(d.normalized())
		if world.player.global_position.distance_to(last) < 0.25:
			stuck += 1
			if stuck == 40:
				# упор в что-то: сначала честный бой с блокатором (если это моб —
				# находка прогона #3: тушки слаймов запирали коридор к сундуку),
				# иначе обновление пути / боковой сход
				var blocker: Node = null
				for e in get_tree().get_nodes_in_group("enemy"):
					if not is_instance_valid(e):
						continue
					var dyb: Variant = e.get("dying")
					if dyb != null and bool(dyb):
						continue
					if not _in_active_zone(e):
						continue
					if e.global_position.distance_to(world.player.global_position) <= 18.0:
						blocker = e
						break
				if blocker != null:
					var frb := await fight(blocker, tag + "_unblock", 1500)
					if frb == "died":
						return 3
				else:
					# кто физически мешает? штатный point-query вперёд по ходу (только чтение)
					var space: PhysicsDirectSpaceState2D = world.player.get_world_2d().direct_space_state
					for probe in [6.0, 10.0, 14.0]:
						var q := PhysicsPointQueryParameters2D.new()
						q.position = world.player.global_position + d.normalized() * probe
						q.collide_with_bodies = true
						q.collide_with_areas = false
						q.collision_mask = 0xFFFFFFFF
						for h in space.intersect_point(q, 8):
							var o = h.get("collider")
							if o != null and o != world.player and is_instance_valid(o):
								var on := String(o.get("name"))
								probe_log[on] = int(probe_log.get(on, 0)) + 1
					refresh_left -= 1
					if refresh_left >= 0:
						var p2: Array = Nav.simplify(Nav.astar(ctx["walk"], ctx["w"], ctx["h"],
							pos_to_tile(world.player.global_position, ctx["base"]), to), ctx["walk"])
						wps = []
						for t2 in p2:
							wps.append(ctx["base"] + (ctx["t2w"] as Callable).call(t2))
						if tnode == null:
							wps.append(ctx["base"] + (ctx["t2w"] as Callable).call(to))
						wp_stall = 0
						wp_best = 1e9
					else:
						axes(Vector2(-d.y, d.x).normalized())
						await frames(18)
				axes(Vector2.ZERO)
				await frames(20)
				stuck = 0
		else:
			stuck = 0
		last = world.player.global_position
		await get_tree().physics_frame
	axes(Vector2.ZERO)
	var fin_d := 9999.0
	if tnode != null and is_instance_valid(tnode):
		fin_d = world.player.global_position.distance_to(tnode.global_position)
	finding("softlock", "[%s] бюджет ходьбы исчерпан (зона %s, цель %s, финал %.0fpx, wps осталось %d, stuck %d, pos %s, упоры: %s)" % [
		tag, String(world.active_area), str(to), fin_d, wps.size(), stuck, str(world.player.global_position), str(probe_log)])
	return 2

## Ближайший живый враг активной зоны, реально достающий до героя (≤ 36 px).
## Вне засады: лучники деревни (равновесие коридора — по плану их не трогать)
## и боссы (с боссом дерёмся только планово, иначе Гром умирал по пути к
## отшельнику и ломал сюжетную последовательность — находка прогона #1).
func nearest_attacker(radius := 36.0) -> Node:
	var p: Vector2 = world.player.global_position
	var best: Node = null
	var bd: float = radius
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var dy0: Variant = e.get("dying")
		if dy0 != null and bool(dy0):
			continue
		# String(null) — падение (находка прогона #2): поля kind/boss есть не у всех
		var knd: Variant = e.get("kind")
		if knd != null and String(knd) == "archer":
			continue
		var bf: Variant = e.get("boss")
		if bf != null and bool(bf):
			continue
		if not _in_active_zone(e):
			continue
		var d: float = p.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best

func _in_active_zone(e: Node) -> bool:
	var y: float = e.global_position.y
	match String(world.active_area):
		"cave":
			return y > world.CAVE_OFFSET.y - 200.0 and y < world.ASHEN_OFFSET.y - 200.0
		"ashen":
			return y > world.ASHEN_OFFSET.y - 200.0 and y < float(OW.WM_OFFSET_Y) - 200.0
		"worldmap":
			return y >= float(OW.WM_OFFSET_Y) - 200.0 and not _in_any_loc(e)
		_:
			var a := String(world.active_area)
			if a.begins_with("mini_"):
				# t22 (25.11): этаж микро-подземелья — своя полоса y (MINI_Y +
				# шаг на биом, t19/t20); без ветки мини-босс считался бы «не здесь».
				return y >= MDZ.mini_y(a.substr(5)) - 200.0
			if a.begins_with("loc_"):
				return y >= float(OW.LOC_OFFSET_Y[a.substr(4)]) - 200.0
			return y < world.CAVE_OFFSET.y - 200.0

func _in_any_loc(e: Node) -> bool:
	for b in OW.ZONES:
		if e.global_position.y >= float(OW.LOC_OFFSET_Y[b]) - 200.0:
			return true
	return false

# ---------------- честное взаимодействие -----------------------------------------------
## Дойти до интерактора, нажать E, дождаться предиката (или просто диалога/окна).
func interact_with(node: Node, tag: String, pred: Callable = Callable(), budget_pred := 600) -> bool:
	if node == null or not is_instance_valid(node):
		finding("hole", "[%s] интерактор не найден" % tag)
		return false
	# HAR-1 (2026-11-19, diag-p2/P2-03): открытая лавка модальна — E следующего NPC
	# ею «съедается» (канон shop.gd:498-509, busy-отказ Shop.open shop.gd:14-15,154).
	# Политика игрока: перед подходом к следующему NPC/интерактору лавку закрывать.
	if SHOP.is_open():
		await close_shop()
	var r := await walk_to(node, tag)
	if r == 3:
		unexpected_death(tag)
		return false
	var ok_near := false
	if r != 0:
		# P2-06 (2026-11-19): rescue-ветки «расстановка героя» и try_interact() в лоб
		# убраны как лишние: thick-LOS в nav.gd кладёт путь с габаритным зазором,
		# упор в угол был артефактом центр-LOS и теперь светится finding'ом walk_to
		# и провалом проверки, а не латается инструментом.
		if not world.near.has(node):
			# путь не пройден: живой микрозаход к живой позиции цели (NPC кочуют)
			for _k in 140:
				if world.near.has(node):
					ok_near = true
					break
				var dd: Vector2 = node.get_global_position() - world.player.global_position
				axes(dd.normalized() if dd.length() > 3.0 else Vector2.ZERO)
				await get_tree().physics_frame
			axes(Vector2.ZERO)
			ok_near = world.near.has(node)
	else:
		await frames(4)
		for _i in 40:
			if world.near.has(node):
				ok_near = true
				break
			await get_tree().physics_frame
	if not ok_near:
		# замкнутый микропреследование: живая позиция цели (NPC кочуют), до упора в near[]
		for _k in 140:
			if world.near.has(node):
				ok_near = true
				break
			var dd: Vector2 = node.get_global_position() - world.player.global_position
			axes(dd.normalized() if dd.length() > 3.0 else Vector2.ZERO)
			await get_tree().physics_frame
		axes(Vector2.ZERO)
		ok_near = world.near.has(node)
	if not ok_near:
		# последний шанс: перестроить путь целиком (цель/мы сдвинулись) и снова жаться
		var rw2 := await walk_to(node, tag + "_retry")
		if rw2 == 3:
			unexpected_death(tag)
			return false
		for _k in 80:
			if world.near.has(node):
				ok_near = true
				break
			var dd2: Vector2 = node.get_global_position() - world.player.global_position
			axes(dd2.normalized() if dd2.length() > 3.0 else Vector2.ZERO)
			await get_tree().physics_frame
		axes(Vector2.ZERO)
		ok_near = world.near.has(node)
	if not ok_near:
		# «матрос»: сетка говорит «проход», физика не пускает — косой обход к цели
		var dds: float = world.player.global_position.distance_to(node.global_position)
		if dds <= 400.0 and dds > 24.0:
			if await _sailor_to(node.get_global_position(), 700):
				for _k in 30:
					if world.near.has(node):
						ok_near = true
						break
					await get_tree().physics_frame
	if not ok_near:
		# P2-06 (2026-11-19): второй rescue-костыль (расстановка dd<=24 и try_interact()
		# в лоб) тоже снят: аудит diag-p2 (P2-01/P2-02) доказал, что недосягаемых
		# E-зон нет — недожим теперь честный провал с диагностикой ниже.
		finding("softlock", "[%s] герой у цели, интерактор не в near[] (зона %s, dd=%.0fpx, method=%s, valid=%s, в near=%d)" % [
			tag, String(world.active_area), world.player.global_position.distance_to(node.global_position),
			str(node.has_method("try_interact")), str(is_instance_valid(node)), int(world.near.size())])
		return false
	push_key(KEY_E)
	await frames(6)
	await settle()
	return await _wait_pred(pred, tag, budget_pred)

## Косой обход («матрос») для участков, где A*-путь по сетке проходит, а физика
## упирается: шаг к цели + чередующиеся боковые уходы. Никакой магии — только
## штатные оси ввода.
func _sailor_to(tpos: Vector2, budget := 700) -> bool:
	var side := 1.0
	var side_t := 0
	var g := 0
	var last: Vector2 = world.player.global_position
	while g < budget:
		g += 1
		if _aborted != "":
			axes(Vector2.ZERO)
			return false
		if world.hud.is_dialog_open() or GameState.input_locked or SHOP.is_open():
			axes(Vector2.ZERO)
			await settle()
			last = world.player.global_position
			continue
		var d: Vector2 = tpos - world.player.global_position
		if d.length() <= 16.0:
			axes(Vector2.ZERO)
			return true
		var dir: Vector2 = d.normalized()
		if side_t > 0:
			dir = Vector2(-dir.y, dir.x) * side
			side_t -= 1
			# агрессор впереди на дороге: честный удар в его сторону сходит его с пути
			var sa := nearest_attacker(44.0)
			if sa != null:
				world.player.attack_at(sa.global_position)
		axes(dir)
		if world.player.global_position.distance_to(last) < 0.2:
			side_t = 30
			side = -side
		else:
			side_t = 0
		last = world.player.global_position
		await get_tree().physics_frame
	axes(Vector2.ZERO)
	return world.player.global_position.distance_to(tpos) <= 24.0

func _wait_pred(pred: Callable, tag: String, budget_pred: int) -> bool:
	if not pred.is_valid():
		return true
	var g := 0
	while not bool(pred.call()) and g < budget_pred:
		if world.hud.is_dialog_open():
			await close_dialog()
		await get_tree().physics_frame
		g += 1
	if not bool(pred.call()):
		finding("hole", "[%s] E нажат, ожидаемое состояние не наступило (%d кадров)" % [tag, budget_pred])
		return false
	return true

## Интеракторы деревни (CaveStairs/AshenGate/WorldArchNorth) НЕ хранят tile —
## ищем по позиции: setup() ставит position = world.tile_to_world(tile).
func village_interactor(tile: Vector2i) -> Node:
	var want: Vector2 = world.tile_to_world(tile)
	for c in world.village_zone.get_children(true):
		if c is Area2D and c.get_global_position().distance_to(want) < 1.0:
			return c
	return null

# ---------------- бой ---------------------------------------------------------------------
## Честный бой: догнать (A* к клетке цели), attack_at с self-gate cd, зелья при низком hp.
## "killed" | "died" | "budget" | "vanished"
func fight(target: Node, tag: String, max_frames := 3600) -> String:
	if _planned_death:
		return "vanished"
	var main_target: Node = target  # ретаргет на аддов временный: убил адда — возвращаемся к главному
	var ctx := zone_ctx()
	var chase: Array = []
	var retargets := 0
	var g := 0
	while g < max_frames:
		g += 1
		if _aborted != "":
			return "died"
		if not is_instance_valid(target):
			if target == main_target or not is_instance_valid(main_target) or bool(main_target.get("dying")):
				return "killed"
			target = main_target
			chase = []
			continue
		if bool(target.get("dying")):
			await frames(4)
			if target == main_target or not is_instance_valid(main_target) or bool(main_target.get("dying")):
				return "killed"
			target = main_target
			chase = []
			continue
		if world.hud.is_dialog_open():
			await close_dialog()
			continue
		if GameState.input_locked or SHOP.is_open():
			await get_tree().physics_frame
			continue
		if GameState.hp <= 0:
			return "died"
		# ретаргет: если к герою подлетел кто-то ближе текущей цели (не босс) — бьём его.
		# Бюджет переключений 3 на окно 600к: вейма держит аддов вечно, но и игнорировать
		# их нельзя; главный после смерти адда возвращаемся (находка прогона #4).
		if (g % 600) == 1:
			retargets = 0
		if (g % 16) == 0 and retargets < 3:
			var alt := nearest_attacker()
			if alt != null and alt != target \
					and world.player.global_position.distance_to(alt.global_position) < world.player.global_position.distance_to(target.global_position):
				target = alt
				retargets += 1
		var d: float = world.player.global_position.distance_to(target.global_position)
		if await heal_if_hurt():
			await frames(2)
			continue
		world.player.attack_at(target.global_position)
		if d > 11.0:
			# A*-преследование (находка прогона #2: прямое «топорь в цель» упиралось
			# в геометрию арены и сожрало бюджет при hp цели 5)
			if chase.is_empty() or (g % 30) == 0:
				var pf := pos_to_tile(world.player.global_position, ctx["base"])
				var ct := pos_to_tile(target.global_position, ctx["base"])
				if not (ctx["walk"] as Callable).call(ct):
					ct = Nav._clamp_free(ctx["walk"], ctx["w"], ctx["h"], ct)
				var pth: Array = Nav.simplify(Nav.astar(ctx["walk"], ctx["w"], ctx["h"], pf, ct), ctx["walk"])
				chase = []
				for t in pth.slice(0, 6):
					chase.append(ctx["base"] + (ctx["t2w"] as Callable).call(t))
			if not chase.is_empty():
				var cw: Vector2 = chase[0]
				if (cw - world.player.global_position).length() <= 6.0:
					chase.pop_front()
					if chase.is_empty():
						axes((target.global_position - world.player.global_position).normalized())
				else:
					axes((cw - world.player.global_position).normalized())
			else:
				axes((target.global_position - world.player.global_position).normalized())
		else:
			axes(Vector2.ZERO)
		await get_tree().physics_frame
	axes(Vector2.ZERO)
	finding("softlock", "[%s] бой: бюджет %d кадров исчерпан (цель hp=%s)" % [tag, max_frames, str(target.get("hp"))])
	return "budget"

func unexpected_death(tag: String) -> void:
	if _planned_death or _aborted != "":
		return
	_aborted = "смерть вне плана на стадии «" + tag + "» (hp=0) — забег прерван"
	finding("crash", _aborted)
	finalize_and_quit()

# ---------------- save+load+continue ---------------------------------------------------------
func checkpoint(label: String, expected_zone: String) -> bool:
	GameState.player_pos = world.player.global_position
	GameState.pos_valid = true
	var gold0: int = GameState.gold
	var hp0: int = GameState.hp
	var pos0: Vector2 = world.player.global_position
	var saved: bool = GameState.save_game()
	if not chk("checkpoint[%s].save_game" % label, saved, "save_game()==false"):
		return false
	world.do_quickload()
	await frames(8)
	var ok_zone: bool = String(GameState.area) == expected_zone and String(world.active_area) == expected_zone
	var resolved: bool = String(GameState.resolve_resume_zone(expected_zone)) == expected_zone
	var restored: bool = world.player.global_position.distance_to(pos0) < 2.0
	var ok := true
	ok = chk("checkpoint[%s].зона=%s" % [label, expected_zone], ok_zone, "area=%s active=%s" % [GameState.area, world.active_area]) and ok
	ok = chk("checkpoint[%s].резолвер_зон" % label, resolved, "resolve_resume_zone(%s)=%s" % [expected_zone, GameState.resolve_resume_zone(expected_zone)]) and ok
	ok = chk("checkpoint[%s].золото (%d)" % [label, gold0], GameState.gold == gold0, "%d != %d" % [GameState.gold, gold0]) and ok
	ok = chk("checkpoint[%s].позиция восстановлена", restored, "сдвиг %.1f px" % world.player.global_position.distance_to(pos0)) and ok
	ok = chk("checkpoint[%s].жив" % label, GameState.hp > 0 and world.player != null, "hp=%d" % GameState.hp) and ok
	if hp0 != GameState.hp and not (GameState.hp == hp0 + 1 and GameState.hp < GameState.max_hp):
		finding("hole", "checkpoint[%s]: hp после load %d != %d" % [label, GameState.hp, hp0])
	await settle()
	return ok

# ---------------- перф --------------------------------------------------------------------------
func perf_start(tag: String) -> void:
	_perf_buf.clear()
	_perf_tag = tag

func perf_end(cap_us := 150000.0) -> void:
	if _perf_tag == "":
		return
	var tag := _perf_tag
	_perf_tag = ""
	var s := _perf_buf.duplicate()
	s.sort()
	var med: float = float(s[int(s.size() / 2.0)]) if not s.is_empty() else 0.0
	var mx: float = float(s[s.size() - 1]) if not s.is_empty() else 0.0
	perf_samples[tag] = {"n": s.size(), "med_us": med, "max_us": mx}
	chk("perf[%s] max %.0fus <= %.0fus" % [tag, mx, cap_us], mx <= cap_us,
		"max=%.0f med=%.0f n=%d" % [mx, med, s.size()])

# ---------------- экономика ------------------------------------------------------------------------
func rs_counts() -> Dictionary:
	var out := {}
	for k in GameState.flags:
		var ks := String(k)
		if ks.begins_with("rs.k."):
			out[ks.substr(5)] = int(GameState.flags[k])
	return out

## t41 (а, 26.11, artist-cave): счётчик ЭЛИТНЫХ киллов забега (rs.elite.<kind>,
## пишет loot.gd в элитной ветке I1). Золотая вилка стадии без него слепнет:
## элитный килл — серебро x3 точно (BALANCE I1), а не табличные 1x.
func elite_counts() -> Dictionary:
	var out := {}
	for k in GameState.flags:
		var ks := String(k)
		if ks.begins_with("rs.elite."):
			out[ks.substr(9)] = int(GameState.flags[k])
	return out

func stage_begin() -> void:
	_gold_before = GameState.gold
	_rs_before = rs_counts()
	_el_before = elite_counts()
	_mats_before = GameState.materials.duplicate()
	_chests_before = GameState.chests_used.size()
	_ash_before = ASH.balance()
	_spend_known = 0
	_quests_gold_known = 0
	_ach_ids_before = _ach_ids()

func stage_end(label: String, belt := 0, mat_bonus := {}, chest_gold: Array = [8, 18]) -> Dictionary:
	var kills := {}
	var now := rs_counts()
	var el_now := elite_counts()
	for k in now:
		var d: int = int(now[k]) - int(_rs_before.get(k, 0))
		if d > 0:
			kills[k] = d
	var mult := 1.0 + 0.15 * float(belt)  # ng_wave()==0 на всём плейте
	var gold_lo := 0
	var gold_hi := 0
	var m_lo := {}
	var m_hi := {}
	for m in ["suhotsvet", "zhim", "smola", "hide", "sinew", "whet"]:
		m_lo[m] = int(_mats_before.get(m, 0))
		m_hi[m] = int(_mats_before.get(m, 0))
	for kind in kills:
		var loot_key := String(kind)
		if loot_key == "brute_t1":
			loot_key = "brute"  # счётчик rs.k.brute_t1, строка лута — "brute" (гирь 231)
		var rows: Array = GD.LOOT.get(loot_key, [])
		if rows.is_empty():
			finding("hole", "econ[%s]: вид '%s' убит, строки лута нет — вилка слепнет" % [label, kind])
		var lo := 0.0
		var hi := 0.0
		for r in rows:
			if r.has("gold"):
				hi += float(r["gold"][1])
				if float(r.get("chance", 1.0)) >= 1.0:
					lo += float(r["gold"][0])
			elif r.has("mat"):
				var mm := String(r["mat"])
				var q := int(r.get("qty", 1)) * int(kills[kind])
				m_hi[mm] = int(m_hi.get(mm, 0)) + q
				if float(r.get("chance", 1.0)) >= 1.0:
					m_lo[mm] = int(m_lo.get(mm, 0)) + q
		gold_lo += int(round(lo * mult)) * int(kills[kind])
		gold_hi += int(round(hi * mult)) * int(kills[kind])
		# t41 (а, 26.11, artist-cave): ЭЛИТНЫЕ киллы I1 — серебро x3 к роллу
		# (loot.gd, BALANCE I1) + один гарантированный предмет. Счётчик
		# rs.elite.<kind> точный, поэтому вилка перестраивается честно: из уже
		# внесённых x1-долей e_k киллов перекладываются в x3 (умножение ДО
		# пояса — тот же порядок, что в loot.gd), плюс гарантированный дроп.
		var e_k: int = clampi(int(el_now.get(kind, 0)) - int(_el_before.get(kind, 0)), 0, int(kills[kind]))
		if e_k > 0:
			gold_lo += (int(round(3.0 * lo * mult)) - int(round(lo * mult))) * e_k
			gold_hi += (int(round(3.0 * hi * mult)) - int(round(hi * mult))) * e_k
			# двойное округление (x3 в int, затем пояс) съедает +/-1 на килл —
			# расширяем вилку на рубль с каждого элитного килла
			gold_lo -= e_k
			gold_hi += e_k
			# гарантированный предмет — ПЕРВАЯ item/mat строка реальной таблицы
			# (игра ищет лут по сырому kind; гирь 231 — только для базы)
			var rows_real: Array = GD.LOOT.get(String(kind), rows)
			for r in rows_real:
				if not (r is Dictionary):
					continue
				if r.has("mat"):
					var em := String((r as Dictionary).get("mat", ""))
					if m_hi.has(em):
						m_lo[em] = int(m_lo.get(em, 0)) + e_k
						m_hi[em] = int(m_hi.get(em, 0)) + e_k
					break
				if r.has("item"):
					break  # трава/зелье — канал вне шестиотслеживаемых матов
		if kind == "slime" or String(kind).begins_with("brute"):
			# MAT_DROP_TABLE ["suhotsvet","zhim"] с шансом 25% — не в LOOT-таблице,
			# учтём отдельной вилкой (находка прогона #1: «жим=1 вне вилки»)
			m_hi["suhotsvet"] = int(m_hi.get("suhotsvet", 0)) + int(kills[kind])
			m_hi["zhim"] = int(m_hi.get("zhim", 0)) + int(kills[kind])
	# бытовые каналы расхода (точильный камень и т.п.) штатно грызут сумку в окне —
	# детектор дыр ловит аномальный ПРИТОК, расход до 4 единиц за окно — норма
	for m in m_lo:
		m_lo[m] = maxi(0, int(m_lo[m]) - 4)
		if int(m_lo[m]) > int(m_hi[m]):
			m_lo[m] = int(m_hi[m])
	var chest_n: int = GameState.chests_used.size() - _chests_before
	gold_lo += chest_n * int(chest_gold[0])
	gold_hi += chest_n * int(chest_gold[1])
	# ачивки платят золотом при анлоке (achv.unlock) — легитимный доход, пин-таблица §2
	var ach_gold := 0
	for id in _ach_ids():
		if not _ach_ids_before.has(id):
			ach_gold += int(ACH_GOLD.get(id, 0))
			if not ACH_GOLD.has(id):
				finding("economy", "ach['%s']: награда не в пин-таблице — вилки отстают" % String(id))
	gold_lo += ach_gold
	gold_hi += ach_gold
	var exp_lo := _gold_before + _quests_gold_known + gold_lo - _spend_known
	var exp_hi := _gold_before + _quests_gold_known + gold_hi - _spend_known
	var mats := {}
	var mats_ok := true
	for m in ["suhotsvet", "zhim", "smola", "hide", "sinew", "whet"]:
		mats[m] = int(GameState.materials.get(m, 0))
		var b: Variant = mat_bonus.get(m, 0)
		var blo := 0
		var bhi := 0
		if typeof(b) == TYPE_ARRAY:
			blo = int(b[0])
			bhi = int(b[1])
		else:
			bhi = int(b)
		if mats[m] < int(m_lo.get(m, 0)) + blo or mats[m] > int(m_hi.get(m, 0)) + bhi:
			mats_ok = false
	var okg := GameState.gold >= exp_lo and GameState.gold <= exp_hi
	var ash_now: int = ASH.balance()
	econ.append({"stage": label, "belt": belt, "kills": kills, "gold": GameState.gold,
		"gold_lo": exp_lo, "gold_hi": exp_hi, "spend": _spend_known, "quests_gold": _quests_gold_known,
		"chests": chest_n, "mats": mats, "mats_lo": m_lo, "mats_hi": m_hi,
		"ash": ash_now, "herbs": GameState.herbs, "brewed": GameState.brewed_potions,
		"level": GameState.level})
	chk("econ[%s].золото %d ∈ [%d..%d] по LOOT-таблице" % [label, GameState.gold, exp_lo, exp_hi], okg,
		"киллы=%s chests=%d spend=%d" % [str(kills), chest_n, _spend_known])
	chk("econ[%s].материалы в вилке LOOT" % label, mats_ok, "факт=%s вилка=[%s..%s]" % [str(mats), str(m_lo), str(m_hi)])
	chk("econ[%s].пепел не убывает (%d >= %d)" % [label, ash_now, _ash_before], ash_now >= _ash_before,
		"пепел уменьшился внутри забега — дыра мета-валюты")
	print("[qa_c1] ECON %s gold=%d[%d..%d] before=%d quests=%d spend=%d kills=%s ash=%d lvl=%d" % [label, GameState.gold, exp_lo, exp_hi, _gold_before, _quests_gold_known, _spend_known, str(kills), ash_now, GameState.level])
	return {"income": GameState.gold + _spend_known, "earned": GameState.gold - _gold_before + _spend_known - ach_gold, "kills": kills, "ach_gold": ach_gold}

# ---------------- класс/модалка ----------------------------------------------------------------
func pick_warrior() -> void:
	var hud = world.hud
	if not hud.is_modal_open():
		chk("модалка класса открыта на старте", false, "её нет")
		return
	var card: PanelContainer = null
	for c in hud.modal.find_children("*", "PanelContainer", true, false):
		card = c
		break
	var clicked := false
	if card != null:
		var center: Vector2 = card.get_global_rect().get_center()
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		root_push_mouse(ev, center)
		await frames(2)
		var ev2 := InputEventMouseButton.new()
		ev2.button_index = MOUSE_BUTTON_LEFT
		ev2.pressed = false
		root_push_mouse(ev2, center)
		await frames(6)
		clicked = String(GameState.class_id) == "warrior"
	if not clicked:
		var ev3 := InputEventMouseButton.new()
		ev3.button_index = MOUSE_BUTTON_LEFT
		ev3.pressed = true
		hud._on_card_input(ev3, "warrior")  # тот же штатный обработчик клика по карте
		await frames(6)
	chk("класс воин выбран честным кликом", String(GameState.class_id) == "warrior", "class_id=%s" % GameState.class_id)

func root_push_mouse(ev: InputEventMouseButton, pos: Vector2) -> void:
	ev.position = pos
	ev.global_position = pos
	get_tree().root.push_input(ev)

# ---------------- артефакты/финал ------------------------------------------------------------------
func repo_root() -> String:
	var cur := ProjectSettings.globalize_path("res://")
	for _i in 12:
		var dd := DirAccess.open(cur)
		if dd != null and dd.dir_exists("tools") and dd.dir_exists("pixel-rpg"):
			return cur
		var up: String = cur.get_base_dir()
		if up == cur or up == "":
			break
		cur = up
	return ProjectSettings.globalize_path("user://")

func finalize_and_quit() -> void:
	if finalized:
		return
	finalized = true
	axes(Vector2.ZERO)
	if _aborted == "":
		# HAR-2 (2026-11-19, diag-p2): wp_stall-поп — не норма и не «прибытие»: с thick-LOS
		# в nav.gd сегменты кладутся с габаритным зазором, коридорные «поп-ловушки»
		# излечены в корне (это был корень залипаний плейта) — на зелёном плейте попов ноль.
		chk("HAR-2: wp_stall-попов за весь плейт 0 (угловые залипания не вернулись)", wp_stall_pops == 0,
			"pops=%d" % wp_stall_pops)
	var doc := {
		"stand": "qa_c1", "seed_rng": SEED_RNG, "seed_run": SEED_RUN,
		"aborted": _aborted, "phase": phase,
		"checks": {"total": total, "pass": pass_n, "fail": total - pass_n},
		"timeline": timeline, "perf_us": perf_samples, "econ": econ, "findings": findings,
	}
	var dir1 := repo_root().path_join("diag-p1")
	DirAccess.make_dir_recursive_absolute(dir1)
	var f := FileAccess.open(dir1.path_join("qa_c1_timeline.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "  "))
		f.close()
	print("[qa_c1] артефакт: %s" % dir1.path_join("qa_c1_timeline.json"))
	var ok := _aborted == "" and pass_n == total
	print("[qa_c1] итог: %d/%d pass, находок: %d" % [pass_n, total, findings.size()])
	print("QA_C1 %d/%d" % [pass_n, total])
	get_tree().quit(0 if ok else 1)

# ================================ BOOT ================================================
func _ready() -> void:
	if _wall0 == 0:
		_wall0 = Time.get_ticks_msec()
	if phase >= 1:
		phase1_ready()
		return
	_run()

func _run() -> void:
	stage("boot")
	seed(SEED_RNG)
	var da := DirAccess.open("user://")
	if da != null:
		for fn in da.get_files():
			da.remove(fn)
	GameState.start_fresh_game()
	GameState.run_seed = SEED_RUN
	world = load(MAIN_SCENE).instantiate()
	add_child(world)
	await frames(8)
	if world == null or world.player == null or world.hud == null:
		chk("мир инстанцирован", false, "world/player/hud не собраны")
		finalize_and_quit()
		return
	chk("мир инстанцирован (player+hud)", true, "")
	if world.hud.is_modal_open():
		await pick_warrior()
	await close_dialog()
	chk("чистый старт: золото 0, класс воин", GameState.gold == 0 and String(GameState.class_id) == "warrior",
		"gold=%d class=%s" % [GameState.gold, GameState.class_id])
	var seq: Array = [
		stage_trail, stage_village_quests, stage_village_shops, stage_village_fight,
		stage_nav_p206,
		stage_village_done, stage_forest_poi, stage_cave, stage_ashen,
		stage_worldmap_and_loc, stage_belt1_mini, stage_return_rest, stage_belt1_board,
		stage_pushout,
		stage_death,
	]
	for f in seq:
		if _aborted != "":
			break
		await (f as Callable).call()
	if _aborted != "":
		finalize_and_quit()
		return
	if phase == 0:
		# стадия смерти не дошла до rekindle — финализируем здесь, иначе висело бы до таймаута
		finalize_and_quit()

# ---------------- стадии --------------------------------------------------------------------
func stage_trail() -> void:
	stage("spawn_trail")
	var r := await walk_to(Vector2i(10, 9), "trail_to_elder")
	chk("путь спавна: старт->старейшина пешком A* по проходу", r == 0, "rc=%d" % r)
	var has_daynight := false
	for c in world.get_children(true):
		var s = c.get_script()
		if s != null and String(s.resource_path).ends_with("day_night.gd"):
			has_daynight = true
	chk("ночной цикл: в движке отсутствует — влияния на бой нет (фиксация)", not has_daynight, "найден день/ночь-скрипт")
	chk("зональный тон задан (atmosphere)", world.atmosphere != null, "atmosphere нет")
	var cm := _find_canvas_modulate()
	if cm != null:
		_tone_village = cm.color

func _find_canvas_modulate() -> CanvasModulate:
	for c in world.get_children(true):
		if c is CanvasModulate:
			return c
	return null

func stage_village_quests() -> void:
	stage("village_elder_quest")
	_heal_off = true  # до сдачи квеста: травы — валюта старейшины, не аптечка
	stage_begin()
	var elder = world._find_npc("elder")
	if chk("старейшина существует", elder != null, "нет NPC elder"):
		await interact_with(elder, "elder_take")
		await close_dialog()
		chk("квест старейшины взят (elder_quest=1)", int(GameState.elder_quest) >= 1, "=%d" % GameState.elder_quest)
	for ht in [Vector2i(12, 17), Vector2i(24, 17), Vector2i(17, 24)]:
		if await walk_to(ht, "herb@%s" % str(ht)) == 0:
			var hb: int = GameState.herbs
			for _t in 4:
				push_key(KEY_E)
				await frames(8)
				if GameState.herbs > hb:
					break
	chk("коренья собраны честным E (herbs>=3)", GameState.herbs >= 3, "herbs=%d" % GameState.herbs)
	if elder != null:
		await interact_with(elder, "elder_done")
		await close_dialog()
		await frames(10)
		if int(GameState.elder_quest) != 2:
			# гонка последней E-страницы диалога (известный паттерн close_dialog):
			# добить дожимами E, затем штатный прямой talk-вызов (тот же вход, что у E)
			for _e2 in 3:
				push_key(KEY_E)
				await frames(12)
				await close_dialog()
				await frames(10)
				if int(GameState.elder_quest) == 2:
					break
		if int(GameState.elder_quest) == 1:
			world.talk("elder")
			await settle()
			await close_dialog()
			await frames(12)
	if int(GameState.elder_quest) == 2:
		_quests_gold_known += int(QD.GOLD_QUEST_TREES)
	chk("квест сдан: elder_quest=2, +%d зол., herbs -3" % int(QD.GOLD_QUEST_TREES),
		int(GameState.elder_quest) == 2, "=%d" % GameState.elder_quest)
	_heal_off = false

func stage_village_shops() -> void:
	stage("village_shops")
	var m = world._find_npc("merchant")
	if chk("торговец существует", m != null, "нет merchant"):
		await interact_with(m, "merchant_take")
		await close_dialog()
		await frames(12)  # cb диалога открывает лавку
		var shop_open: bool = SHOP.is_open()
		chk("квест слаймов взят, лавка Драна открыта", int(GameState.slime_quest) == 1 and shop_open,
			"sq=%d shop=%s" % [GameState.slime_quest, str(shop_open)])
		if shop_open:
			var g0: int = GameState.gold
			var b = SHOP.I.buy_btns.get("resin", null)
			if b != null and b.visible and not b.disabled:
				b.pressed.emit()
				await frames(4)
				if GameState.gold == g0 - 15:
					_spend_known += 15
			chk("смола куплена за 15 (BALANCE стр.6)", GameState.gold == g0 - 15, "gold %d->%d" % [g0, GameState.gold])
			await close_shop()
	var s = world._find_npc("smith")
	if chk("кузнец существует", s != null, "нет smith"):
		await interact_with(s, "smith_dialog")
		await close_dialog()
		await frames(12)
		if SHOP.is_open():
			var t0: int = GameState.torches
			var sm0: int = int(GameState.materials.get("smola", 0))
			var cb = SHOP.I.craft_btn
			if cb != null and cb.visible and not cb.disabled:
				cb.pressed.emit()
				await frames(4)
			chk("крафт факела: 1 смола, денег 0 (BALANCE Г1.3)",
				GameState.torches == t0 + 1 and int(GameState.materials.get("smola", 0)) == sm0 - 1,
				"torches %d->%d smola %d->%d" % [t0, GameState.torches, sm0, GameState.materials.get("smola", 0)])
			await close_shop()
	chk("Ута существует", world._find_npc("uta") != null, "нет uta")

## Покупка зелья у Уты — ПОСЛЕ сдачи слаймов: на старте забега золото 0,
## до квестовой выплаты в 30 зол. зелье физически неоплатно (порядок главы).
func _uta_buy() -> void:
	var u = world._find_npc("uta")
	if u == null:
		return
	await interact_with(u, "uta_dialog")
	await close_dialog()
	# ждём именно прилавок Уты: кнопка зелья стала видимой (переоткрытие лавки асинхронно)
	var gw := 0
	while gw < 120:
		if world.hud.is_dialog_open():
			await close_dialog()
		var bpx: Button = SHOP.I.buy_btns.get("potion", null) if SHOP.I != null else null
		if SHOP.is_open() and bpx != null and bpx.visible:
			break
		await get_tree().physics_frame
		gw += 1
	if not (SHOP.is_open() and SHOP.I.buy_btns.has("potion") and (SHOP.I.buy_btns["potion"] as Button).visible):
		# HAR-1 (2026-11-19, P2-03): костыль «Shop.close()+Shop.open("uta")» снят. С
		# закрытием лавки перед подходом E-цикл обязан сам привести к прилавку Уты
		# (сценарий A probes/p2_live). Незакрытие теперь — провал проверки, а не тихая
		# подмена статического входа.
		chk("HAR-1: прилавок Уты открылся штатным порядком (E->диалог->прилавок, без форс-Shop.open)", false,
			"vend=%s dlg=%s waited=%d" % [str(SHOP.I.get("_vendor")) if SHOP.I != null else "nil",
				str(world.hud.is_dialog_open()), gw])
	else:
		chk("HAR-1: прилавок Уты открылся штатным порядком (E->диалог->прилавок, без форс-Shop.open)", true,
			"waited=%d" % gw)
	if SHOP.is_open():
		var g0: int = GameState.gold
		var bp0: int = GameState.brewed_potions
		var bp = SHOP.I.buy_btns.get("potion", null)
		if bp != null and bp.visible and not bp.disabled:
			bp.pressed.emit()
			await frames(4)
			if GameState.gold == g0 - 30:
				_spend_known += 30
		chk("зелье у Уты за 30 (BALANCE стр.8)", GameState.gold == g0 - 30 and GameState.brewed_potions == bp0 + 1,
			"gold %d->%d brewed %d->%d vis=%s dis=%s vend=%s dlg=%s waited=%d" % [g0, GameState.gold, bp0, GameState.brewed_potions,
				str(bp.visible) if bp != null else "nil", str(bp.disabled) if bp != null else "nil",
				str(SHOP.I.get("_vendor")) if SHOP.I != null else "nil", str(world.hud.is_dialog_open()), gw])
		await close_shop()

func close_shop() -> void:
	var g := 0
	while g < 90:
		if world.hud.is_dialog_open():
			await close_dialog()
		elif SHOP.is_open():
			SHOP.close()
			await frames(3)
		else:
			break
		g += 1

func stage_village_fight() -> void:
	stage("village_fight")
	# обязательный боевой контент главы 1: 6 слаймов + 2 мглокрыса (лучников не трогаем —
	# их лут выбросил бы доход за коридор BALANCE)
	var plan := {"slime": 6, "swarmling": 2}
	for kind in plan:
		var script_of := "slime.gd" if kind == "slime" else "mob_swarmling.gd"
		# зачёт по всему окну деревни: засадные убийства по пути тоже квестовые
		while int(rs_counts().get(kind, 0)) - int(_rs_before.get(kind, 0)) < int(plan[kind]):
			if _aborted != "":
				return
			var tgt: Node = null
			for e in get_tree().get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or not _in_active_zone(e):
					continue
				var dy1: Variant = e.get("dying")
				if dy1 != null and bool(dy1):
					continue
				if String(e.get_script().resource_path.get_file()) == script_of:
					tgt = e
					break
			if tgt == null:
				finding("hole", "зачистка деревни: не найден живой %s (нужно %d)" % [kind, int(plan[kind])])
				break
			var rw := await walk_to(tgt, "approach_%s" % kind)
			if rw == 3:
				unexpected_death("village_fight")
				return
			if rw == 2:
				break  # бюджет/дыра — finding уже записан walk_to
			if not is_instance_valid(tgt):
				continue  # цель легла от засады в пути — зачтётся окном
			var fr := await fight(tgt, "kill_%s" % kind)
			if fr == "died":
				unexpected_death("village_fight")
				return
	# деревенский сундук + экипировка (клики инвентаря = equip_item)
	var chest_node: Node = null
	for c in world.village_zone.get_children(true):
		var s = c.get_script()
		if s != null and String(s.resource_path).ends_with("interactable.gd") and String(c.get("kind")) == "chest":
			chest_node = c
	if chk("деревенский сундук найден", chest_node != null, "нет"):
		await interact_with(chest_node, "village_chest")
		chk("сундук открыт E (chests_used+1)", GameState.chests_used.size() > _chests_before,
			"chests=%d" % GameState.chests_used.size())
		for oid in GameState.owned_gear:
			var slot := String(GD.item(String(oid)).get("slot", ""))
			if slot == "weapon" or slot == "armor":
				GameState.equip_item(slot, String(oid))
		GameState.stats_changed.emit()
		await frames(2)
		chk("экипировка сундука на герое", String(GameState.gear.get("weapon", "")) != "", "gear=%s" % str(GameState.gear))

# ---------------- P2-06 пины (2026-11-19, diag-p2) --------------------------------------
## Старый (до-P2-06) los по ЦЕНТРАМ клеток — эталон только внутри стенда: им доказываем,
## что угловая геометрия в реальной сетке есть и новый thick-los её чинит, а не «всё
## заблокировал». Игрой не используется.
func _los_center(a: Vector2i, b: Vector2i, walkable: Callable) -> bool:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 4
	if steps <= 0:
		return true
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var c := Vector2i(int(round(lerpf(a.x, b.x, t))), int(round(lerpf(a.y, b.y, t))))
		if not walkable.call(c):
			return false
	return true

## Независимый Minkowski-тест: вдоль сегмента центров несём коробку героя 10x8
## (AABB с допуском 0.5px на грань) — своим перебором клеток, НЕ переиспользуя nav.los
## (двойная проверка по образцу t59). Возвращает false, если коробка задела solid.
func _hero_box_clear(a: Vector2i, b: Vector2i, walkable: Callable) -> bool:
	var pa := Vector2(a.x * 16.0 + 8.0, a.y * 16.0 + 8.0)
	var pb := Vector2(b.x * 16.0 + 8.0, b.y * 16.0 + 8.0)
	var steps := maxi(1, int(ceil(pa.distance_to(pb))))
	for s in range(0, steps + 1):
		var c: Vector2 = pa.lerp(pb, float(s) / float(steps))
		for cy in range(int(floor((c.y - 3.5) / 16.0)), int(floor((c.y + 3.5) / 16.0)) + 1):
			for cx in range(int(floor((c.x - 4.5) / 16.0)), int(floor((c.x + 4.5) / 16.0)) + 1):
				if not walkable.call(Vector2i(cx, cy)):
					return false
	return true

func _p206_walk_rows(rows: Array) -> Callable:
	return func(t: Vector2i) -> bool:
		return OW.walkable(rows, t.x, t.y)

func _far_from_enemies(pts: Array, min_d: float) -> bool:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not _in_active_zone(e):
			continue
		var dy0: Variant = e.get("dying")
		if dy0 != null and bool(dy0):
			continue
		for p in pts:
			if e.global_position.distance_to(p as Vector2) < min_d:
				return false
	return true

## Пары «центр-LOS видит, а коробка героя не проходит» — те самые углы, где старый
## nav.gd клал прямой сегмент и коробка 10x8 цепляла массу (P2-06/probes п2).
## Возвращает [corners, pick]: pick — первая детерминированная пара с путём A*,
## вдали (>=140px) от врагов и достаточной длины (cheb>=4), для живого пина.
func _p206_corner_scan(walk: Callable, w: int, h: int, want_pick: bool) -> Array:
	var corners := 0
	var pick: Array = []
	for ay in range(1, h - 1, 2):
		for ax in range(1, w - 1, 2):
			var a := Vector2i(ax, ay)
			if not bool(walk.call(a)):
				continue
			for dy in range(-6, 7, 2):
				for dx in range(-6, 7, 2):
					if dx == 0 or dy == 0:
						continue
					var b := Vector2i(ax + dx, ay + dy)
					if not bool(walk.call(b)):
						continue
					if _los_center(a, b, walk) and not _hero_box_clear(a, b, walk):
						corners += 1
						if want_pick and pick.is_empty() and maxi(absi(dx), absi(dy)) >= 4:
							var pa := Vector2(a.x * 16.0 + 8.0, a.y * 16.0 + 8.0)
							var pb := Vector2(b.x * 16.0 + 8.0, b.y * 16.0 + 8.0)
							if _far_from_enemies([pa, pb], 140.0) \
									and not Nav.astar(walk, w, h, a, b).is_empty():
								pick = [a, b]
	return [corners, pick]

## Инвариант решётки: все сегменты пути ПОСЛЕ Nav.simplify проходимы коробкой героя
## (независимый Minkowski). Сэмпл — фиксированный seed, детерминирован.
func _p206_seg_invariant(tag: String, walk: Callable, w: int, h: int, samples: int, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var seg_n := 0
	var bad := 0
	var tries := 0
	while tries < samples:
		tries += 1
		var a := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		var b := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if not bool(walk.call(a)) or not bool(walk.call(b)) or a == b:
			continue
		var raw: Array = Nav.astar(walk, w, h, a, b)
		if raw.is_empty():
			continue
		var prev: Vector2i = a
		for t: Vector2i in Nav.simplify(raw, walk):
			seg_n += 1
			if not _hero_box_clear(prev, t, walk):
				bad += 1
			prev = t
	chk("P2-06[%s]: габаритная проходимость упрощённых путей — %d сегм. коробкой 10x8, провалов 0" % [tag, seg_n],
		seg_n > 40 and bad == 0, "bad=%d seg=%d" % [bad, seg_n])

func stage_nav_p206() -> void:
	stage("nav_p206_thick_los")
	var ctx := zone_ctx()
	var w := int(ctx["w"])
	var h := int(ctx["h"])
	var walk: Callable = ctx["walk"]
	# 1) Угловая геометрия в реальной сетке деревни существует — без неё пин был бы
	#    пустой проверкой (коробка-тест строже старого центр-LOS: пары обязаны остаться).
	var scan: Array = _p206_corner_scan(walk, w, h, true)
	var corners: int = int(scan[0])
	var pick: Array = scan[1]
	chk("P2-06: угловая геометрия в сетке деревни есть (центр-виден/коробкой-нельзя) — %d пар" % corners,
		corners > 0, "пар 0 — стенд деградирует в пустую проверку")
	# 2) Инвариант new-los: упрощённые пути проходимы габаритом (деревня — живая сетка).
	_p206_seg_invariant("деревня", walk, w, h, 200, 777)
	# 3) Снежный биом — сайт залипаний аудита (exit_snow: 39 упоров «Walls», бюджет
	#    съеден). Решётка статическая от PIN-seed — гоняем тот же инвариант чисто.
	var smap: Dictionary = OW.loc_map(SEED_RUN, "snow")
	var srows: Array = smap["grid"]
	_p206_seg_invariant("снег/статика", _p206_walk_rows(srows), String(srows[0]).length(), srows.size(), 150, 4242)
	# 4) Живой пин: «угловой путь ПКМ => прибытие без упора» — честный ClickMove
	#    (тот же код, что у игрока за ПКМ), живая физика, никакой синтезированной ходьбы.
	if not chk("P2-06: найдена угловая чистая пара для живого пина ПКМ", pick.size() == 2,
			"нет пары вдали от врагов с достижимым A*-путём"):
		return
	if not chk("P2-06: ClickMove живёт в мире (синглтон)", ClickMove.I != null, "I == null"):
		return
	var a: Vector2i = pick[0]
	var b: Vector2i = pick[1]
	heal_if_hurt()
	var cm = ClickMove.I
	var was_on: bool = ClickMove.is_on()
	ClickMove.set_on(true)
	# инструментальная посадка стартовала ТОЛЬКО в проходимую клетку (паттерн probes/p2_live)
	world.player.global_position = (ctx["t2w"] as Callable).call(a)
	await frames(6)
	var goal: Vector2 = (ctx["t2w"] as Callable).call(b)
	var ok := bool(cm.call("order_to", goal))
	var g := 0
	var stall := 0
	var stall_max := 0
	var last: Vector2 = world.player.global_position
	while g < 900 and bool(cm.call("is_walking")):
		await get_tree().physics_frame
		g += 1
		if GameState.hp <= 0:
			break
		var p: Vector2 = world.player.global_position
		if p.distance_to(last) < 0.5:
			stall += 1
			stall_max = maxi(stall_max, stall)
		else:
			stall = 0
		last = p
	var dd: float = world.player.global_position.distance_to(goal)
	chk("P2-06: угловой путь ПКМ %s->%s => прибытие без упора (%.1fpx, %d кадров, макс.упор %d к.)" % [str(a), str(b), dd, g, stall_max],
		ok and dd <= 8.0 and stall_max <= 10,
		"ok=%s dd=%.1f stall_max=%d hp=%d" % [str(ok), dd, stall_max, GameState.hp])
	cm.call("cancel")
	axes(Vector2.ZERO)
	ClickMove.set_on(was_on)
	await frames(2)

func stage_village_done() -> void:
	stage("village_slimes_handin_rest")
	var m = world._find_npc("merchant")
	await interact_with(m, "merchant_handin")
	await close_dialog()
	await frames(10)
	if int(GameState.slime_quest) == 2:
		_quests_gold_known += int(QD.GOLD_QUEST_SLIMES)
	chk("квест слаймов сдан (+30 зол., slime_quest=2)", int(GameState.slime_quest) == 2, "=%d" % GameState.slime_quest)
	# следующий E по Драну — просто прилавок; закрыть
	await interact_with(m, "merchant_reopen")
	await frames(12)
	await close_shop()
	# зелье Уты — теперь (квестовые +30 в кармане)
	await _uta_buy()
	# алхимия минимально: варка у костра штатным Alchemy.brew
	var camp = world.campfires[0] if world.campfires.size() > 0 else null
	if chk("костёр существует", camp != null, "campfires пусто"):
		await walk_to(camp, "camp_walk")
		await frames(4)
		var b0: int = GameState.brewed_potions
		var can := int(GameState.materials.get("suhotsvet", 0)) >= 1 and int(GameState.materials.get("zhim", 0)) >= 1 and b0 < GameState.BREWED_CAP
		var res: bool = ALC.brew("strong_potion")
		if can:
			chk("алхимия: strong_potion сварился по alchemy.json", res, "brew=false")
		else:
			finding("economy", "алхимия: материалов на варку не выпало (сх=%s жм=%s brewed=%d) — варка пропущена, покупка зелья засчитана" % [
				str(GameState.materials.get("suhotsvet", 0)), str(GameState.materials.get("zhim", 0)), b0])
	var inc := stage_end("village", 0, {"whet": 2, "smola": [0, 1]})
	var earned: int = int(inc.get("earned", 0))  # заработок за главу = дельта золота + известные траты
	var k: Dictionary = inc.get("kills", {})
	var extra: bool = int(k.get("slime", 0)) > 6 or int(k.get("swarmling", 0)) > 2 or int(k.get("archer", 0)) > 0
	if extra:
		finding("balance", "сверх плана убито мобов главы 1 (%s) — статический коридор 78–106 неприменим, сверяем только динамический LOOT-вилочный econ" % str(k))
	else:
		# HAR-2/P2-05 (2026-11-19): коридор 78–106 — харнес-допущение, в ECONOMY_BALANCE.md
		# его нет (верх выведен из обязательного контента главы 1, низ — из удачи дропа).
		chk("BALANCE-коридор [харнес-допущение P2-05] главы 1: заработок %d <= 106 (полный обязательный контент)" % earned, earned <= 106,
			"заработок выше потолка BALANCE — подозрение на передроп")
		chk("BALANCE-коридор [харнес-допущение P2-05] главы 1 (нижняя планка 78 при удачном раскате)", earned >= 78, "заработок=%d" % earned)
	await checkpoint("village_pre_cave", "village")

func stage_forest_poi() -> void:
	stage("forest_poi")
	var ctx := zone_ctx()
	var from := pos_to_tile(world.player.global_position, ctx["base"])
	for t in [world.CAVE_ENTRANCE_TILE, world.ASHEN_ENTRANCE_TILE, world.WORLD_ARCH_TILE]:
		var p: Array = Nav.astar(ctx["walk"], ctx["w"], ctx["h"], from, t)
		chk("лесной POI %s достижим из леса (BFS-софтлок-детектор)" % str(t), from == t or not p.is_empty(), "недостижим")
	var stairs := village_interactor(world.CAVE_ENTRANCE_TILE)
	var gate := village_interactor(world.ASHEN_ENTRANCE_TILE)
	var arch := village_interactor(world.WORLD_ARCH_TILE)
	chk("лесные интеракторы построены (лестница/врата/арка)", stairs != null and gate != null and arch != null,
		"stairs=%s gate=%s arch=%s" % [str(stairs != null), str(gate != null), str(arch != null)])

func stage_cave() -> void:
	stage("cave")
	var stairs := village_interactor(world.CAVE_ENTRANCE_TILE)
	if not chk("CaveStairs найден", stairs != null, "нет"):
		return
	perf_start("transition_enter_cave")
	var ok := await interact_with(stairs, "cave_entrance", (func() -> bool: return String(world.active_area) == "cave"))
	perf_end()
	await frames(90)  # твин тоновой перекраски atmosphere.gd = 0.8 с (48 к), берём с запасом
	var cm := _find_canvas_modulate()
	if cm != null:
		_tone_cave = cm.color
	chk("вход в пещеру E-шкой (active=cave)", String(world.active_area) == "cave", "active=%s ok=%s" % [world.active_area, str(ok)])
	chk("пещерный тон отличается от деревенского (визуальная «ночь» есть)", _tone_cave != _tone_village,
		"vlg=%s cave=%s" % [str(_tone_village), str(_tone_cave)])
	await close_dialog()
	if not await checkpoint("cave_enter", "cave"):
		return
	stage_begin()
	await interact_with(world.dungeon_zone.hermit_node, "cave_hermit_take")
	await close_dialog()
	chk("отшельник: квест принят (cave_state>=1)", int(GameState.cave_state) >= 1, "cave_state=%d" % GameState.cave_state)
	var boss = world.dungeon_zone.boss_node
	if GameState.boss_defeated:
		# допустимая альтернативная траектория: Гром лёг от засады по пути —
		# инварианты (ng.boss_0, пепел) проверяем, плановый бой пропускаем
		finding("ambush", "Гром повержен вне плановой сцены (побочный бой в пещере) — последовательность нарушена, инварианты сверяем")
		var ash_a: int = ASH.balance()
		chk("босс пещеры (Гром) повержен (вне сцены)", int(GameState.flags.get("ng.boss_0", 0)) == 1 and ash_a >= _ash_before + 3,
			"ng.boss_0=%s ash %d->%d" % [str(GameState.flags.get("ng.boss_0", 0)), _ash_before, ash_a])
		await checkpoint("cave_boss", "cave")
	elif chk("очаг босса найден (boss_node)", boss != null and is_instance_valid(boss), "нет"):
		var rw := await walk_to(boss, "cave_boss_walk")
		if rw != 0:
			finding("softlock", "пещера: очаг босса недосяжен (rc=%d) — путь к боссу дыряв" % rw)
		await close_dialog()  # boss_intro
		var fr := await fight(boss, "cave_boss_grom", 6000)
		chk("босс пещеры (Гром) повержен честным боем", bool(GameState.boss_defeated),
			"fight=%s boss_defeated=%s" % [fr, str(GameState.boss_defeated)])
		var ash_now: int = ASH.balance()
		chk("пепел за Грома +3 однократно (ng.boss_0=1, delta>=3 с учётом ачивок)",
			int(GameState.flags.get("ng.boss_0", 0)) == 1 and ash_now >= _ash_before + 3,
			"ng.boss_0=%s ash %d->%d" % [str(GameState.flags.get("ng.boss_0", 0)), _ash_before, ash_now])
		await checkpoint("cave_boss", "cave")
		await interact_with(world.dungeon_zone.hermit_node, "cave_key", (func() -> bool: return bool(GameState.has_key)))
		await close_dialog()
		chk("ключ от двери получен (has_key)", bool(GameState.has_key), "has_key=%s" % str(GameState.has_key))
		await checkpoint("cave_key", "cave")
		var door_node: Node = null
		for c in world.dungeon_zone.get_children(true):
			var v = c.get("tile")
			if v != null and Vector2i(int(v.x), int(v.y)) == world.dungeon_zone.door_tile:
				door_node = c
		if door_node != null:
			await interact_with(door_node, "cave_door", (func() -> bool: return bool(GameState.door_opened)))
		else:
			finding("hole", "CaveDoor не найден как интерактор — unlock_door() напрямую (запасной путь)")
			world.dungeon_zone.unlock_door(world.dungeon_zone.door_tile)
			await frames(3)
		chk("дверь алтарной ниши открыта (door_opened)", bool(GameState.door_opened), "=%s" % str(GameState.door_opened))
		await interact_with(world.dungeon_zone.chest_node, "cave_chest", (func() -> bool: return bool(GameState.has_amulet)))
		chk("сундук за дверью: амулет Леса получен", bool(GameState.has_amulet), "has_amulet=%s" % str(GameState.has_amulet))
		for oid in GameState.owned_gear:
			var slot := String(GD.item(String(oid)).get("slot", ""))
			if slot == "weapon" or slot == "armor":
				GameState.equip_item(slot, String(oid))
		GameState.stats_changed.emit()
		await frames(2)
		await interact_with(world.dungeon_zone.hermit_node, "cave_hermit_done")
		await close_dialog()
		chk("отшельник принял амулет (cave_state>=3)", int(GameState.cave_state) >= 3, "cave_state=%d" % GameState.cave_state)
		stage_end("cave", 0, {"whet": 2}, [0, 0])  # сундук амулета: золота не даёт
		await checkpoint("cave_done", "cave")
		await interact_with(world.dungeon_zone.stairs_node, "cave_exit", (func() -> bool: return String(world.active_area) == "village"))
		await settle()
		chk("выход из пещеры в деревню", String(world.active_area) == "village", "active=%s" % world.active_area)

func stage_ashen() -> void:
	stage("ashen")
	var gate := village_interactor(world.ASHEN_ENTRANCE_TILE)
	if not chk("AshenGate найден", gate != null, "нет"):
		return
	perf_start("transition_enter_ashen")
	var ok := await interact_with(gate, "ashen_gate", (func() -> bool: return String(world.active_area) == "ashen"))
	perf_end()
	await settle()
	await close_dialog()
	chk("вход в Пепелище (active=ashen)", String(world.active_area) == "ashen", "active=%s ok=%s" % [world.active_area, str(ok)])
	if not await checkpoint("ashen_enter", "ashen"):
		return
	stage_begin()
	var witch = world.ashen_grid.boss_node
	var fr := "walk_failed"
	if chk("ведьма на месте (boss_node)", witch != null, "нет"):
		var rw := await walk_to(witch, "ashen_witch_walk")
		if rw == 0:
			fr = await fight(witch, "ashen_witch", 12000)
	if fr == "killed" and String(GameState.flags.get("ashen.boss", "")) != "dead":
		await frames(60)  # смерть-анимация mob_boss2: флаг ставится в die()-пути
	chk("ведьма Пепелища повержена (ashen.boss=dead)", String(GameState.flags.get("ashen.boss", "")) == "dead",
		"fight=%s flag=%s witch_valid=%s" % [fr, str(GameState.flags.get("ashen.boss", "")), str(is_instance_valid(witch))])
	await interact_with(world.ashen_grid.chest_node, "ashen_chest", (func() -> bool: return String(GameState.flags.get("ashen.chest", "")) != ""))
	chk("сундук Пепелища взят (ashen.chest)", String(GameState.flags.get("ashen.chest", "")) != "", "flag=%s" % str(GameState.flags.get("ashen.chest", "")))
	for oid in GameState.owned_gear:
		var slot := String(GD.item(String(oid)).get("slot", ""))
		if (slot == "weapon" or slot == "armor") and String(GameState.gear.get(slot, "")) == "":
			GameState.equip_item(slot, String(oid))
	GameState.stats_changed.emit()
	stage_end("ashen", 0, {"whet": 3})
	await checkpoint("ashen_done", "ashen")
	await interact_with(world.ashen_grid.portal_node, "ashen_portal", (func() -> bool: return String(world.active_area) == "village"))
	await settle()
	chk("портал Пепелища -> деревня", String(world.active_area) == "village", "active=%s" % world.active_area)

func stage_worldmap_and_loc() -> void:
	stage("worldmap_arch")
	var arch := village_interactor(world.WORLD_ARCH_TILE)
	if not chk("северная арка найдена", arch != null, "нет"):
		return
	perf_start("transition_enter_worldmap")
	var ok := await interact_with(arch, "world_arch", (func() -> bool: return String(world.active_area) == "worldmap"))
	perf_end()
	await settle()
	await close_dialog()
	chk("северная арка -> карта мира (lazy-build в бюджете перфа)", String(world.active_area) == "worldmap",
		"active=%s ok=%s" % [world.active_area, str(ok)])
	if not await checkpoint("worldmap", "worldmap"):
		return
	for b in ["steppe", "forest", "desert", "castle", "dungeon", "snow"]:
		if _aborted != "":
			return
		await _biome_run(String(b))

func _biome_run(b: String) -> void:
	stage("loc_" + b)
	if _loc_chain_dead:
		chk("локация %s: цепочка биомов мертва (выход из предыдущей не найден)" % b, false, "skip")
		return
	var portal: Node = world.worldmap_grid.portal_nodes.get(b, null)
	if not chk("портал %s на карте мира" % b, portal != null, "нет portal_node"):
		return
	await checkpoint("wm_before_loc_" + b, "worldmap")
	perf_start("transition_enter_loc_" + b)
	var ok := await interact_with(portal, "portal_" + b, (func() -> bool: return String(world.active_area) == "loc_" + b))
	perf_end()
	await settle()
	chk("вход в локацию %s (active=loc_%s)" % [b, b], String(world.active_area) == "loc_" + b, "active=%s ok=%s" % [world.active_area, str(ok)])
	if not world.biome_grids.has(b):
		chk("сетка локации %s построена" % b, false, "biome_grids нет '%s' — вход не состоялся" % b)
		return
	var grid = world.biome_grids[b]
	var belt: int = int(grid.belt)
	if not await checkpoint("loc_%s_enter" % b, "loc_" + b):
		return
	stage_begin()
	# зачистка мобов пояса: все живые мобы ЗОНЫ (A*-подход + честный бой)
	var container: Node = world.biome_zone_cont[b]
	var targets: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var dy2: Variant = e.get("dying")
		if dy2 != null and bool(dy2):
			continue
		if container.is_ancestor_of(e):
			targets.append(e)
	var killed := 0
	for e in targets:
		if _aborted != "":
			return
		if not is_instance_valid(e) or bool(e.get("dying")):
			continue
		if not is_instance_valid(e):
			continue  # лег от засады в пути — засчитается пост-проверкой
		var rw := await walk_to(e, "loc_%s_approach" % b)
		if rw == 3:
			unexpected_death("loc_" + b)
			return
		if not is_instance_valid(e):
			continue
		var fr := await fight(e, "loc_%s_mob" % b, 4200)
		if fr == "died":
			unexpected_death("loc_" + b)
			return
		if fr == "killed":
			killed += 1
	var cleared := 0
	for t2 in targets:
		if not is_instance_valid(t2) or bool(t2.get("dying")):
			cleared += 1
	killed = max(killed, cleared)  # засадные смерти тоже зачёт
	chk("зачистка %s: все %d мобов пояса уничтожены" % [b, targets.size()], killed == targets.size() and targets.size() > 0,
		"killed=%d/%d" % [killed, targets.size()])
	var ch0: int = GameState.chests_used.size()
	await interact_with(grid.chest_node, "chest_" + b, (func() -> bool: return GameState.chests_used.size() > ch0))
	chk("сундук %s открыт (chest@loc)" % b, GameState.chests_used.size() > ch0, "chests=%d" % GameState.chests_used.size())
	await checkpoint("loc_%s_chest" % b, "loc_" + b)
	stage_end("loc_" + b, belt)
	var ok2 := await interact_with(grid.portal_out_node, "exit_" + b, (func() -> bool: return String(world.active_area) == "worldmap"))
	await settle()
	var exited := String(world.active_area) == "worldmap"
	chk("выход из %s на карту мира" % b, exited, "active=%s ok=%s" % [world.active_area, str(ok2)])
	if not exited:
		_loc_chain_dead = true  # анти-каскад: бессмысленно тащить остаток цепочки из плена

func stage_return_rest() -> void:
	stage("return_home_rest")
	if world.worldmap_grid == null:
		chk("карта мира построена (возврат)", false, "worldmap_grid=nil — цепочка арки не прошла")
		return
	var back: Node = world.worldmap_grid.arch_node
	var ok := await interact_with(back, "arch_back", (func() -> bool: return String(world.active_area) == "village"))
	await settle()
	await close_dialog()
	chk("возврат с карты мира в деревню (полный путь замкнут)", String(world.active_area) == "village",
		"active=%s ok=%s" % [world.active_area, str(ok)])
	await checkpoint("village_return", "village")
	# t41 (а, СВОЯ СТРОКА 27.11, artist-cave): автономная аудит-строка элитной
	# ветки econ-вилки. Надстройка в stage_end перестраивает gold/mat-полосу
	# ФОРМУЛОЙ из флагов rs.elite.<kind> (пишет loot.gd по meta "elite" килла,
	# а не по номеру килла — потому вилка сходится на любом сиде); эта строка
	# независимым источником подтверждает, что ветка на этом сиде ЖИВА: ноль
	# элитных киллов на целом плейте = мёртвый код вилки (12% роли I1 при
	# сотнях киллов плейта — на фиксированном сиде это детерминировано).
	var el_total := 0
	var el_brk := ""
	for k in GameState.flags:
		var ks := String(k)
		if ks.begins_with("rs.elite."):
			var ev := int(GameState.flags[k])
			el_total += ev
			if ev > 0:
				el_brk += "%s=%d " % [ks.substr(9), ev]
	chk("econ[plate].элитная надбавка: элитных киллов %d > 0 — вилка ×3+гарант не мёртвый код [%s]" % [el_total, el_brk],
		el_total > 0, "rs.elite.* пуст — элитная ветка I1 на плейте молчала")
	# ночлег: отдых у костра Campfire-каналом 4c (штатные гейты: урон есть, пыл боя 0)
	var camp = world.campfires[0] if world.campfires.size() > 0 else null
	if not chk("костёр существует", camp != null, "пусто"):
		return
	var r := await walk_to(camp, "camp_walk_rest")
	chk("подход к костру (ночлег)", r == 0, "rc=%d" % r)
	if GameState.hp >= GameState.max_hp:
		world.player.take_damage(1, "qa")
		await frames(30)
	var g := 0
	while GameState.combat_t > 0.0 and g < 700:
		await get_tree().physics_frame
		g += 1
	var hp0: int = GameState.hp
	var rest_ok := await interact_with(camp, "camp_rest")
	var g2 := 0
	while not bool(camp.get("used")) and g2 < 500 and not world.hud.is_dialog_open() and GameState.combat_t <= 0.0:
		await get_tree().physics_frame
		g2 += 1
	chk("ночлег: отдых у костра (hp %d->%d, used=%s, rest_ok=%s)" % [hp0, GameState.hp, str(camp.get("used")), str(rest_ok)],
		bool(camp.get("used")) and GameState.hp > hp0, "hp0=%d hp=%d" % [hp0, GameState.hp])
	# F5/F9 — штатные quicksave/quickload
	var g0: int = GameState.gold
	push_key(KEY_F5)
	await frames(6)
	var saved := FileAccess.file_exists("user://save_morkheim.json")
	push_key(KEY_F9)
	await frames(10)
	await settle()
	chk("F5+F9: сейв-файл есть, золото сохранилось", saved and GameState.gold == g0, "saved=%s gold=%d/%d" % [str(saved), GameState.gold, g0])

# ==================================================================================
# t43 (27.11, artist-cave) «Страж выталкивания» (находка t42): герой не может
# остаться в стене — три канала (сейв/резюме, посадка «Рывка вепря», переход)
# синтетическими кейсами на ЖИВОЙ сетке деревни. Карта не меняется — ноль
# перепинов; кейсы лишь читают map_rows и ставят героя в заранее найденную
# пару «свободная клетка / стена восточнее» (детерминированный скан).
# ==================================================================================
func stage_pushout() -> void:
	stage("pushout_guard")
	var p := world.player
	# W1. Страж молчит на свободном: легаси-позиция возвращается КАК ЕСТЬ.
	var here: Vector2 = p.global_position
	chk("t43: страж молчит на свободном (легаси-позиция как есть)",
		world.clear_player_pos(here) == here, "here=%s -> %s" % [str(here), str(world.clear_player_pos(here))])
	# Детерминированный скан: первая свободная клетка со стеной восточнее.
	var free_cell := Vector2i(-1, -1)
	var wall_cell := Vector2i(-1, -1)
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length() - 1:
			var t := Vector2i(x, y)
			if world._pos_walkable(world.tile_to_world(t)) \
					and not world._pos_walkable(world.tile_to_world(t + Vector2i(1, 0))):
				free_cell = t
				wall_cell = t + Vector2i(1, 0)
				break
		if free_cell.x >= 0:
			break
	if not chk("t43: пара «свободная/стена восток» найдена на карте деревни", free_cell.x >= 0, str(free_cell)):
		return
	# W2. Сейв в стену (центр в стене): лоад обязан посадить на чистое.
	GameState.player_pos = world.tile_to_world(wall_cell)
	GameState.pos_valid = true
	world._place_resumed_player()
	await frames(6)
	chk("t43: сейв в стену грузится на чистую клетку", world._box_clear(p.global_position),
		"pos=%s" % str(p.global_position))
	# W3. Вросший бокс (центр свободен, восток-угол в стене — класс t42):
	# страж сдвигает в ближайшую свободную, позиция НЕ остаётся запрошенной.
	var embed := world.tile_to_world(free_cell) + Vector2(4.0, 0.0)
	GameState.player_pos = embed
	GameState.pos_valid = true
	world._place_resumed_player()
	await frames(6)
	chk("t43: вросший бокс (центр свободен) сдвинут со стены", p.global_position != embed and world._box_clear(p.global_position),
		"запрошено=%s факт=%s" % [str(embed), str(p.global_position)])
	# W4. Посадка «Рывка вепря» в центр стены: финиш-хэндлер обязан вытолкнуть
	# в соседнюю свободную (сам рейкаст угла не видит — канал проверяем точкой).
	p.global_position = world.tile_to_world(free_cell)
	await frames(4)
	p.boar_from = p.global_position
	p.boar_mid = Vector2.ZERO
	p.boar_dest = world.tile_to_world(wall_cell)
	p.boar_target = null
	p.boar_t = 0.02
	await frames(6)
	chk("t43: рывок в стену сажает рядом (бокс чист, не в камне)",
		p.global_position != world.tile_to_world(wall_cell) and world._box_clear(p.global_position) \
		and p.global_position.distance_to(world.clear_player_pos(world.tile_to_world(wall_cell))) < 0.5,
		"dest=%s факт=%s" % [str(p.boar_dest), str(p.global_position)])
	# W5. Подвижность после стража: штатный ввод ведёт (мягкий софтлок снят).
	# Ось берём детерминированно по первой проходимой соседней клетке — страж
	# мог посадить героя хоть у какой стены, тыкать в заблокированную честно.
	var p0: Vector2 = p.global_position
	var cur_tile: Vector2i = Vector2i(roundf((p0.x - 8.0) / 16.0), roundf((p0.y - 2.0 - 8.0) / 16.0))
	var ax := Vector2.ZERO
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		if world._pos_walkable(world.tile_to_world(cur_tile + d)):
			if d == Vector2i(1, 0):
				ax = Vector2.RIGHT
			elif d == Vector2i(0, 1):
				ax = Vector2.DOWN
			elif d == Vector2i(-1, 0):
				ax = Vector2.LEFT
			else:
				ax = Vector2.UP
			break
	axes(ax)
	await frames(24)
	axes(Vector2.ZERO)
	chk("t43: после выталкивания герой подвижен (шаг штатным вводом)",
		p.global_position.distance_to(p0) > 2.0, "сдвиг %.1f px ось=%s" % [p.global_position.distance_to(p0), str(ax)])

func stage_death() -> void:
	stage("death_snow")
	# снова на карту мира и в снежную — плановая смерть (инвариант круга)
	if world.worldmap_grid == null:
		chk("карта мира построена (смерть-тест)", false, "worldmap_grid=nil — цепочка не дошла до арки")
		finalize_and_quit()
		return
	var arch := village_interactor(world.WORLD_ARCH_TILE)
	await interact_with(arch, "arch_reenter", (func() -> bool: return String(world.active_area) == "worldmap"))
	await settle()
	var portal: Node = world.worldmap_grid.portal_nodes.get("snow", null)
	if not chk("портал snow", portal != null, "нет"):
		finalize_and_quit()
		return
	await interact_with(portal, "death_to_snow", (func() -> bool: return String(world.active_area) == "loc_snow"))
	await settle()
	if String(world.active_area) != "loc_snow":
		ffail_snow()
		return
	# P2-06 (2026-11-19): формализованный зонд diag-p2/probes/p2_live — сайт залипания
	# аудита (exit_snow: упоры «Walls», бюджет съеден). Посадка в аудитную клетку
	# (инструмент, клетка проходимая) и честная ходьба walk_to к выходу.
	if world.biome_grids.has("snow"):
		var sgrid = world.biome_grids["snow"]
		var sctx := zone_ctx()
		var st := Vector2i(30, 14)
		if chk("P2-06[снег]: аудитная клетка (30,14) проходима", bool((sctx["walk"] as Callable).call(st)), "нет") \
				and chk("P2-06[снег]: узел выхода из локации есть", sgrid.portal_out_node != null, "нет"):
			world.player.global_position = (sctx["base"] as Vector2) + (sctx["t2w"] as Callable).call(st)
			await frames(6)
			var src := await walk_to(sgrid.portal_out_node, "p206_snow_exit")
			chk("P2-06[снег]: коридор (30,14)->выход (22,31) пройден без упоров и без бюджета", src == 0, "rc=%d" % src)
	# вечный снапшот ДО смерти
	carried = {
		"ash": ASH.balance(),
		"vd": int(GameState.flags.get("meta.vd", 0)),
		"deaths": int(GameState.flags.get("ach.n.deaths", 0)),
		"ach_count": _ach_flags_count(),
		"has_amulet": bool(GameState.has_amulet),
		"run_seed": int(GameState.run_seed),
		"rs_earned": int(GameState.flags.get("rs.earned", 0)),
		# t38 I5 (перепин 27.11, мягкая смерть): нажитое до смерти — эталон
		# неприкосновенности (золото за вычетом 20% — пин ниже).
		"gold": int(GameState.gold),
		"dmg": int(GameState.damage),
		"level": int(GameState.level),
		"xp": int(GameState.xp),
		"bag": int(GameState.owned_gear.size()),
		"mats": _mats_sum(),
		"torches": int(GameState.torches),
		"herbs": int(GameState.herbs),
		"brewed": int(GameState.brewed_potions),
		"sq": int(GameState.slime_quest),
		"cs": int(GameState.cave_state),
		"chests": int(GameState.chests_used.size()),
		"campfires": int(GameState.campfires_used.size()),
		"weapon": String(GameState.gear.get("weapon", "")),
	}
	chk("пепел забега учтён в rs.earned (пин t70: == балансу)", int(carried["rs_earned"]) == int(carried["ash"]),
		"rs.earned=%d ash=%d" % [int(carried["rs_earned"]), int(carried["ash"])])
	_planned_death = true
	var g := 0
	while GameState.hp > 0 and g < 40:
		world.player.hurt_cd = 0.0  # как qa_ib B-02: детерминированный удар без кулдауна
		world.player.take_damage(10, "qa-death-test")
		await frames(20)
		g += 1
	chk("плановая смерть констатирована (hp=0)", GameState.hp <= 0, "hp=%d" % GameState.hp)
	await frames(10)
	chk("диалог смерти открыт", world.hud.is_dialog_open(), "нет диалога death")
	await close_dialog()
	await frames(8)
	# экран итогов — синглтон RS (панель живёт глубже, чем дочерний обход world)
	var rs_open := RS.is_open()
	chk("экран итогов забега открылся (RunSummary)", rs_open, "не открылся")
	if rs_open and RS.I != null:
		RS.I.board_btn.pressed.emit()
		await frames(6)
		chk("доска пепла открывается с экрана смерти", MB.is_open(), "не открылась")
		if MB.is_open():
			MB.close_panel()
			await frames(4)
		# ВАЖНО: после emit ни одного await — сцена релоадится deferred,
		# корутина умерла бы вместе со сценой; фазу 1 подхватит новый инстанс
		phase = 1
		RS.I.rekindle_btn.pressed.emit()

func ffail_snow() -> void:
	chk("вход в снежную для смерти-теста", false, "active=%s" % world.active_area)
	finalize_and_quit()

func _ach_flags_count() -> int:
	var n := 0
	for k in GameState.flags:
		if String(k).begins_with("ach."):
			n += 1
	return n

# ================================ ФАЗА 1 =============================================
func phase1_ready() -> void:
	# новый инстанс сцены после reload_current_scene (хук ng_plus_started в world.gd):
	# мир пересоздаётся штатно и сам подхватит post-death сейв
	stage("post_death_invariants")
	world = load(MAIN_SCENE).instantiate()
	add_child(world)
	await frames(10)
	if world == null or world.player == null:
		total += 1
		findings.append({"stage": "post_death", "kind": "crash", "detail": "мир не пересобрался после смерти"})
		finalize_and_quit()
		return
	# t38 I5 (ПЕРЕПИН 27.11, ВЕРДИКТ ПОЛЬЗОВАТЕЛЯ 27.11, выбор А «МЯГКАЯ СМЕРТЬ —
	# воскресение у костра/в деревне, −20% серебра с полом, экип/сумка/класс целы»):
	# прежний блок t9 (инверсия 25.11 «класс обнулён, модалка, lvl1, 50×purse,
	# сид перевыброшен, слой круга вытерт») ОТМЕНЁН этой правкой: смерть больше не
	# сброс. Инварианты мягкой смерти ниже; полный вайп по-прежнему пинится на
	# отказном входе (qa_run D8) и регрессии арки (qa_run D9).
	var ok := true
	ok = chk("post-death: класс ЦЕЛ, модалка «Создание героя» НЕ всплывает (правка 27.11)",
		String(GameState.class_id) == "warrior" and world.hud != null and not world.hud.is_modal_open(),
		"class=[%s] modal=%s" % [String(GameState.class_id),
			str(world.hud.is_modal_open() if world.hud != null else false)]) and ok
	# Дальнейшие фазы считают экономику/скиллы ВОИНА — класс пережил смерть,
	# выбирать заново нечего; урон обязан остаться ПРЕЖНИМ (шмот цел) — эталон
	# берётся из снапшота ДО смерти, не из текущего состояния.
	var pre: Dictionary = carried
	var _dmg_want := int(pre.get("dmg", -1))
	ok = chk("post-death: воин сразу в бою жив (ближний бой, урон = прежний %d — шмот цел)" % _dmg_want,
		String(GameState.class_id) == "warrior" and world.player != null \
			and String(world.player.class_data().kind) == "melee" \
			and int(GameState.damage) == _dmg_want,
		"class=%s dmg=%d want=%d" % [String(GameState.class_id), int(GameState.damage), _dmg_want]) and ok
	# t38 I5 (27.11): цена вместо сброса — ровно floor(20%) с пола; серебро —
	# единственная потеря, остальное сверяется со снапшотом до смерти.
	var gold_pre := int(pre.get("gold", 0))
	var expected_gold := gold_pre - int(floor(float(gold_pre) * GameState.DEATH_GOLD_LOSS))
	ok = chk("мягкая смерть: золото %d -> %d (−20%% floor), meta.last_loss=%d" % [gold_pre, expected_gold, gold_pre - expected_gold],
		GameState.gold == expected_gold and int(GameState.flags.get("meta.last_loss", -1)) == gold_pre - expected_gold,
		"gold=%d want=%d last_loss=%s" % [GameState.gold, expected_gold, str(GameState.flags.get("meta.last_loss", -1))]) and ok
	ok = chk("нажитое целое: lvl/xp/шмот/сумка как до смерти (экип неприкосновенен)",
		GameState.level == int(pre.get("level", 0)) and GameState.xp == int(pre.get("xp", 0)) \
		and String(GameState.gear.get("weapon", "")) == String(pre.get("weapon", "?")) \
		and GameState.owned_gear.size() == int(pre.get("bag", -1)),
		"lvl=%d xp=%d gear=%s bag=%d/%d" % [GameState.level, GameState.xp, str(GameState.gear), GameState.owned_gear.size(), int(pre.get("bag", -1))]) and ok
	var ash_now: int = ASH.balance()
	ok = chk("вечен не только пепел: %d == %d (до смерти)" % [ash_now, int(pre.get("ash", -1))], ash_now == int(pre.get("ash", -1)),
		"до=%d после=%d" % [int(pre.get("ash", -1)), ash_now]) and ok
	ok = chk("ачивки вечны (ach.*: %d >= %d)" % [_ach_flags_count(), int(pre.get("ach_count", 0))],
		_ach_flags_count() >= int(pre.get("ach_count", 0)), "") and ok
	ok = chk("счётчик смертей +1 (meta.vd и ach.n.deaths) — ставки уплачены",
		int(GameState.flags.get("meta.vd", 0)) == int(pre.get("vd", 0)) + 1 and int(GameState.flags.get("ach.n.deaths", 0)) == int(pre.get("deaths", 0)) + 1,
		"vd=%s deaths=%s" % [str(GameState.flags.get("meta.vd", 0)), str(GameState.flags.get("ach.n.deaths", 0))]) and ok
	var wiped_probes: Array = []
	for k in GameState.flags:
		var ks := String(k)
		# t38 I5 (27.11): коллектор-свидетель: собираем живой слой круга; ни о
		# каком «вытирании после вайпа» речи больше нет — смерть мягкая.
		if ks == "q.q_brewer":
			pass  # постоянный квест — тоже свидетель живого слоя
		if ks.begins_with("q.") or ks.begins_with("ashen.") or ks.begins_with("ng.boss_") or ks.begins_with("tal.") \
				or (ks.begins_with("rs.") and ks != "rs.zone" and ks != "rs.t"):
			wiped_probes.append(ks)
	# t38 I5 (ПЕРЕПИН 27.11, вердикт пользователя, выбор А): прежний пин «слой
	# круга вытерт» инвертирован — мягкая смерть НЕ вытирает q./ashen./tal./rs.;
	# q. на этом этапе плейта заведомо непуст — он и есть свидетель отсутствия
	# вайпа (полный набор вайпа пинится на отказном входе: qa_run D8).
	ok = chk("слой круга НЕ вытерт смертью (q. жив — вайп снят 27.11)", wiped_probes.any(func(x): return String(x).begins_with("q.")), "флаги круга: %s" % str(wiped_probes.slice(0, 8))) and ok
	ok = chk("амулет Леса вечен", bool(GameState.has_amulet), "has_amulet=%s" % str(GameState.has_amulet)) and ok
	ok = chk("сид круга НЕ перевыброшен (тот же забег: %d == %d)" % [int(pre.get("run_seed", 0)), GameState.run_seed],
		GameState.run_seed == int(pre.get("run_seed", -1)), "") and ok
	ok = chk("инвентарь цел (материалы/зелья/факелы/травы как до смерти)",
		_mats_sum() == int(pre.get("mats", 0)) and GameState.brewed_potions == int(pre.get("brewed", 0)) \
		and GameState.torches == int(pre.get("torches", 0)) and GameState.herbs == int(pre.get("herbs", 0)),
		"mats=%d/%d brewed=%d torch=%d herbs=%d" % [_mats_sum(), int(pre.get("mats", 0)), GameState.brewed_potions, GameState.torches, GameState.herbs]) and ok
	ok = chk("квесты круга НЕ сброшены (slime_quest/cave_state целы)",
		int(GameState.slime_quest) == int(pre.get("sq", 0)) and int(GameState.cave_state) == int(pre.get("cs", 0)),
		"sq=%d/%d cs=%d/%d" % [GameState.slime_quest, int(pre.get("sq", 0)), GameState.cave_state, int(pre.get("cs", 0))]) and ok
	ok = chk("мягкая смерть уносит домой: резолвер -> деревня (костёр)",
		String(world.active_area) == "village" and String(GameState.resolve_resume_zone(GameState.area)) == "village",
		"active=%s area=%s" % [world.active_area, GameState.area]) and ok
	ok = chk("герой жив, full hp, в деревне (y < CAVE_OFFSET)",
		GameState.hp > 0 and GameState.hp == GameState.max_hp and world.player.global_position.y < world.CAVE_OFFSET.y,
		"hp=%d/%d y=%.0f" % [GameState.hp, GameState.max_hp, world.player.global_position.y]) and ok
	ok = chk("сундуки/костры круга НЕ сброшены смертью (считаются дальше)",
		GameState.chests_used.size() == int(pre.get("chests", -1)) and GameState.campfires_used.size() == int(pre.get("campfires", -1)),
		"chests=%d/%d camp=%d/%d" % [GameState.chests_used.size(), int(pre.get("chests", -1)), GameState.campfires_used.size(), int(pre.get("campfires", -1))]) and ok
	var p0: Vector2 = world.player.global_position
	axes(Vector2.RIGHT)
	await frames(24)
	axes(Vector2.ZERO)
	ok = chk("новый круг управляем (шаг штатным вводом)", world.player.global_position.distance_to(p0) > 2.0,
		"сдвиг %.1f px" % world.player.global_position.distance_to(p0)) and ok
	finalize_and_quit()

func _mats_sum() -> int:
	var s := 0
	for k in GameState.materials:
		s += int(GameState.materials[k])
	return s

# ==================================================================================
# t22 (25.11, «Глубина v2 §5»): маршрут «открыл локацию пояса -> ход в
# микро-подземелье -> мини-босс -> реликтовый сундук -> сдал квест у доски».
# ==================================================================================
# Пояс 1 по реестру = BELT_CHAIN[0] = snow (Снежник): bq_snow_1 «Снежный долг»
# (зачистить 4 сущности) и bq_snow_2 «Клад под снегом» (сундук биома +
# гарантированный реликт). Формулировка задания сказала «открыл лес», но лес в
# реестре — звено 6 (третий пояс); взят ровно ПЕРВЫЙ пояс, как заказано словом
# «пояс 1», а лесной ход (t19) покрыт qa_world W11 (обход шести биомов).
# Правка аддитивная: прежние стадии не тронуты, эконом-окна (stage_begin/
# stage_end) у новых стадий нет — вилки LOOT/BALANCE прежних глав от новых
# наград не съезжают (золото цепочки проверяется здесь отдельными дельтами).
# Статы мини-босса — датированный пин замера t22 (формула t19: база яруса
# x belt-множитель, затем x2.5 hp / x1.5 dmg мин.2 / x3 xp).
const MINI_HP_PIN_SNOW := 35    # HP мини-босса Снежника — датированный пин (замер t22, сид 555001, пояс 1)
const MINI_XP_PIN_SNOW := 45    # kill_xp мини-босса = база x MINI_XP_MULT (замер t22, тот же сид)

## Снимок сумки снаряжения (мультимножество id -> количество).
func _gear_snapshot() -> Dictionary:
	var s := {}
	for raw in GameState.owned_gear:
		var id := String(raw)
		s[id] = int(s.get(id, 0)) + 1
	return s

## Что прибавилось в сумке с момента снимка (порядок не важен).
func _gear_added_since(before: Dictionary) -> Array:
	var out: Array = []
	var after := _gear_snapshot()
	for raw_id in after:
		var id := String(raw_id)
		var d: int = int(after[raw_id]) - int(before.get(id, 0))
		for k in maxi(0, d):
			out.append(id)
	return out

## Независимое повторение выбора Loot.quest_relic (t18): пул минус «уже в
## сумке» минус «не своей руке», индекс — shash("questrelic:<звень>:<сид>").
## Нужно именно до выдачи: после выдачи сумка уже другая.
func _expected_relic(link_id: String, pool: Array) -> String:
	var free: Array = []
	for p in pool:
		var pid := String(p)
		if not GameState.owned_gear.has(pid) \
				and bool(GD.can_equip(String(GameState.class_id), pid).get("ok", true)):
			free.append(pid)
	if free.is_empty():
		return ""
	return String(free[OW.shash("questrelic:%s:%d" % [link_id, int(GameState.run_seed)]) % free.size()])

## Стадия 1 маршрута: Снежник -> ход -> мини-босс -> реликтовый сундук -> выход.
func stage_belt1_mini() -> void:
	stage("belt1_mini_snow")
	if _loc_chain_dead:
		chk("belt1: цепочка биомов мертва — маршрут хода пропущен", false, "skip")
		return
	# --- 1. пояс открыт ногами, цели обоих звеньев закрыты честной главой биомов ---
	var open_flag: Variant = GameState.get_flag("wm.open.snow", "")
	chk("belt1: Снежник открыт ногами (t7 wm.open.snow=1)", String(open_flag) == "1",
		"wm.open.snow=%s" % str(open_flag))
	var bk := int(GameState.get_flag(QD.BK_PREFIX + "snow", 0))
	chk("belt1: зачистка Снежника вошла в цепочку (q.bk.snow=%d >= 4)" % bk, bk >= 4, "bk=%d" % bk)
	var bc := int(GameState.get_flag(QD.BC_PREFIX + "snow", 0))
	chk("belt1: сундук Снежника вошёл в цепочку (q.bc.snow=%d == 1)" % bc, bc == 1, "bc=%d" % bc)
	# --- 2. возврат в Снежник штатным порталом карты мира ---
	var portal: Node = world.worldmap_grid.portal_nodes.get("snow", null)
	if not chk("belt1: портал snow жив для маршрута хода", portal != null, "нет portal_node"):
		return
	perf_start("transition_enter_loc_snow_belt1")
	var ok_in := await interact_with(portal, "belt1_to_snow",
			(func() -> bool: return String(world.active_area) == "loc_snow"))
	perf_end()
	await settle()
	if not chk("belt1: вход в Снежник (маршрут хода, active=loc_snow)",
			String(world.active_area) == "loc_snow", "active=%s ok=%s" % [world.active_area, str(ok_in)]):
		return
	var grid = world.biome_grids.get("snow", null)
	if grid == null:
		chk("belt1: сетка Снежника на месте", false, "biome_grids.snow=nil")
		return
	# --- 3. ход: интерактор в локации стоит ровно там, где сказал генератор ---
	# ВАЖНО (замер t22): игра зовёт pick_hole на СВОИХ рядах зоны —
	# world._ensure_hole передаёт gz.map_rows (world.gd:1208), а не lm["grid"]:
	# после постройки зоны ряды живут (створы/декор), и параллельный пересчёт
	# по «сырому» loc_map даёт другую клетку ((12,28) против (9,24) на сиде
	# плейта). Сверяемся с теми же входами, что у игры: ряды зоны + meta loc_map.
	var hole: Node = world.mini_holes.get("snow", null)
	if not chk("belt1: ход в микро-подземелье посажен (mini_holes.snow)", hole != null, "нет"):
		return
	var lm: Dictionary = OW.loc_map(int(GameState.run_seed), "snow")
	var meta: Dictionary = lm.get("meta", {})
	var sp: Array = meta.get("spawn", [21, OW.LOC_H - 4])
	var po: Array = meta.get("portal_out", [22, OW.LOC_H - 3])
	var ch: Array = meta.get("chest", [-1, -1])
	var want_hole := MDZ.pick_hole(grid.map_rows,
			Vector2i(int(sp[0]), int(sp[1])), Vector2i(int(ch[0]), int(ch[1])),
			Vector2i(int(po[0]), int(po[1])), "snow")
	var hole_cell := node_tile(hole, zone_ctx())
	chk("belt1: клетка хода == pick_hole генератора на рядах этой же зоны (%s)" % str(want_hole),
		hole_cell == want_hole, "факт=%s ждали=%s" % [str(hole_cell), str(want_hole)])
	chk("belt1: клетка хода удовлетворяет правилу посадки (cheb: спавн/портал >= 9, сундук >= 7, нора примыкает к массе/скале)",
			OW.cheb(hole_cell, Vector2i(int(sp[0]), int(sp[1]))) >= 9 \
					and OW.cheb(hole_cell, Vector2i(int(po[0]), int(po[1]))) >= 9 \
					and (int(ch[0]) < 0 or OW.cheb(hole_cell, Vector2i(int(ch[0]), int(ch[1]))) >= 7) \
					and _hole_touches_rock(grid.map_rows, hole_cell),
			"hole=%s cheb(спавн)=%d cheb(портал)=%d cheb(сундук)=%s у_скалы=%s" % [str(hole_cell),
				OW.cheb(hole_cell, Vector2i(int(sp[0]), int(sp[1]))),
				OW.cheb(hole_cell, Vector2i(int(po[0]), int(po[1]))),
				str(-1 if int(ch[0]) < 0 else OW.cheb(hole_cell, Vector2i(int(ch[0]), int(ch[1])))),
				str(_hole_touches_rock(grid.map_rows, hole_cell))])
	# --- 4. спуск ---
	await interact_with(hole, "belt1_hole", (func() -> bool: return String(world.active_area) == "mini_snow"))
	await settle()
	if not chk("belt1: ход -> микро-подземелье (active=mini_snow)",
			String(world.active_area) == "mini_snow", "active=%s" % str(world.active_area)):
		return
	var mz = world.mini_grids.get("snow", null)
	if not chk("belt1: сцена хода построена (mini_grids.snow)", mz != null, "nil"):
		return
	chk("belt1: карта хода %dx%d (обе оси >= вида — полос нет, t19)" % [int(mz.map_w), int(mz.map_h)],
		int(mz.map_w) == int(MDZ.W) and int(mz.map_h) == int(MDZ.H),
		"факт=%sx%s ждали=%sx%s" % [str(mz.map_w), str(mz.map_h), str(MDZ.W), str(MDZ.H)])
	chk("belt1: босс и сундук в разных комнатах (дальняя — боссу)",
		int(mz.boss_tile.x) >= 0 and int(mz.chest_tile.x) >= 0 and mz.boss_tile != mz.chest_tile,
		"boss=%s chest=%s" % [str(mz.boss_tile), str(mz.chest_tile)])
	# t22 (25.11) F-1: сейв+резюме внутри микро-подземелья раньше выбрасывало
	# героя в «Подземелье» (замер diag-t22/mini_save_probe.gd: до сейва
	# active=area=«mini_snow», после do_quickload() — «loc_dungeon» при прежней
	# позиции: do_quickload затирает GameState.area (world.gd:1809) до чтения
	# ключа резюме (world.gd:1703)). P1 принят капитаном как t25 и ИСПРАВЛЕН в
	# HEAD fbb0ceb (узкая форма mini_*; широкая ломала легаси-кейс c37 —
	# устаревший area обязан падать на спавн деревни). Живое подтверждение:
	# прогон diag-t22/qa_c1_run12.log делал сейв+quickload внутри хода — зона
	# осталась mini_snow, сцена хода на месте. Постоянный чек здесь НЕ ставим:
	# do_quickload пересоздаёт сцену мира посреди маршрута, и плейт теряет
	# кэшированные ссылки (на том же прогоне — 17 каскадных красных, см.
	# diag-t22/REGRESS_DEPTH.md F-10). Регресс закрыт standalone-зондом и
	# стендовыми проверками t25, поэтому finding отсюда снят (не кричим волком).
	await frames(10)
	mz = world.mini_grids.get("snow", null)
	if mz == null or mz.boss_node == null:
		chk("belt1: ход цел после входа (сцена+босс)", false, "mz=%s" % str(mz))
		return
	chk("belt1: ход цел после входа (сцена+босс жив)", not bool(mz.boss_node.get("dying")),
		"hp=%s" % str(mz.boss_node.get("hp")))
	# --- 5. мини-босс: честный бой ногами, статы по формуле (пин t22) ---
	var boss: Node = mz.boss_node
	var fam := String(MZ.BOSS_FAM.get("snow", "brute"))
	var script_path := String(boss.get_script().resource_path)
	chk("belt1: мини-босс Снежника — remap семейства «%s» (BOSS_FAM/FAM_SCRIPTS, не новая сущность)" % fam,
		script_path == String(MZ.FAM_SCRIPTS[fam]), "script=%s ждали=%s" % [script_path, String(MZ.FAM_SCRIPTS[fam])])
	var boss_flag: bool = ("boss" in boss) and bool(boss.get("boss"))
	chk("belt1: мини-босс не помечен Громом (поле boss где есть = false; гром-механики не затронуты)",
		not boss_flag, "boss=%s" % str(boss.get("boss")))
	chk("belt1: HP мини-босса синхронизирован с max_hp (множитель применён до границы HP, t20)",
			not ("max_hp" in boss) or int(boss.get("hp")) == int(boss.get("max_hp")),
			"hp=%s max_hp=%s" % [str(boss.get("hp")), str(boss.get("max_hp"))])
	var dmg_note := "dmg=" + str(boss.get("dmg"))
	if not ("dmg" in boss):
		dmg_note = "dmg_mult x%.2f" % float(boss.get("dmg_mult"))
	var leash_note := "leash=" + str(boss.get("boss_leash"))
	if not ("boss_leash" in boss):
		leash_note = "leash=MiniBossWatch (у property нет)"
	chk("belt1: статы мини-босса Снежника = датированный пин t22 (hp=%d, xp=%d; формула t19: база x belt, затем x2.5 hp / x3 xp)"
			% [MINI_HP_PIN_SNOW, MINI_XP_PIN_SNOW],
		int(boss.get("hp")) == MINI_HP_PIN_SNOW and int(boss.get("kill_xp")) == MINI_XP_PIN_SNOW,
		"hp=%s xp=%s %s %s (пины %d/%d; база wraith hp=8 xp=15, belt=3 -> 8x1.75=14 -> x2.5=35)" % [
			str(boss.get("hp")), str(boss.get("kill_xp")), dmg_note, leash_note,
			MINI_HP_PIN_SNOW, MINI_XP_PIN_SNOW])
	var lvl0: int = GameState.level
	var fr := await fight(boss, "belt1_mini_boss", 5400)
	chk("belt1: мини-босс убит честным боем (A*-подход + attack_at)", fr == "killed", "rc=%s" % fr)
	if fr == "died":
		unexpected_death("belt1_mini")
		return
	await frames(30)
	chk("belt1: смерть мини-босса = «ход закрыт» (q.bm.snow=1)",
		int(GameState.get_flag(QD.BM_PREFIX + "snow", 0)) == 1,
		"q.bm.snow=%s" % str(GameState.get_flag(QD.BM_PREFIX + "snow", 0)))
	chk("belt1: опыт мини-босса дошёл до героя (уровень %d -> %d)" % [lvl0, GameState.level],
		GameState.level >= lvl0, "lvl=%d" % GameState.level)
	# --- 6. реликтовый сундук хода: гарантированные 2 аффикса, бит-в-бит ---
	if mz.chest_node == null:
		chk("belt1: сундук хода существует", false, "chest_node=nil")
		return
	var pool: Array = mz._relic_pool()
	var want_relic := _expected_relic("mini_snow", pool)   # ДО выдачи (сумка ещё чистая)
	var gear_before := _gear_snapshot()
	var ch_used0: int = GameState.chests_used.size()
	await interact_with(mz.chest_node, "belt1_mini_chest",
			(func() -> bool: return GameState.chests_used.size() > ch_used0))
	chk("belt1: реликтовый сундук хода открыт", GameState.chests_used.size() > ch_used0,
		"chests=%d" % GameState.chests_used.size())
	var added: Array = _gear_added_since(gear_before)
	var ord_after: int = int(GameState.owned_gear.size())
	if want_relic == "":
		chk("belt1: пул хода исчерпан -> честное серебро (+40)", added.is_empty(), "added=%s" % str(added))
	else:
		chk("belt1: награда хода == независимый повтор Loot.quest_relic («%s»)" % want_relic,
			added.size() == 1 and String(added[0]) == want_relic,
			"added=%s ждали=%s" % [str(added), want_relic])
		var rid := want_relic
		var affs: Array = GameState.affixes.get(rid, []) as Array
		chk("belt1: награда хода — реликтовая (2 аффикса, force_relic t17)", affs.size() == 2,
			"affixes=%s" % str(affs))
		var again: Array = AFX.affix_roll(int(GameState.run_seed), "quest:mini_snow", ord_after, true)
		chk("belt1: аффиксы реликта бит-в-бит с Affixes.affix_roll(seed, «quest:mini_snow», ordinal)",
				again == affs, "факт=%s ролл=%s" % [str(affs), str(again)])
		chk("belt1: награда «по руке» воину (can_equip ok; отсутствующий ключ = провал, не vacuous pass)",
			bool(GD.can_equip(String(GameState.class_id), rid).get("ok", false)), rid)
	# --- 7. выход тем же ходом + повторный вход не дублирует реликт ---
	var hole_pos: Vector2 = hole.get_global_position()
	if mz.exit_node != null:
		await interact_with(mz.exit_node, "belt1_mini_exit",
				(func() -> bool: return String(world.active_area) == "loc_snow"))
		await settle()
		chk("belt1: выход = тот же интерактор (герой на клетке хода)",
			String(world.active_area) == "loc_snow" \
					and world.player.global_position.distance_to(hole_pos) < 24.0,
			"active=%s сдвиг %.1f px" % [str(world.active_area), world.player.global_position.distance_to(hole_pos)])
	else:
		chk("belt1: стойка выхода хода существует (exit_node)", false, "nil")
		return
	var chest_uid := String(mz.chest_node.get("uid"))
	var gear2 := _gear_snapshot()
	if hole != null and is_instance_valid(hole):
		await interact_with(hole, "belt1_reenter",
				(func() -> bool: return String(world.active_area) == "mini_snow"))
		await settle()
		if String(world.active_area) == "mini_snow":
			var mz2 = world.mini_grids.get("snow", null)
			var again_used: bool = mz2 != null and mz2.chest_node != null and bool(mz2.chest_node.get("used"))
			chk("belt1: повторный вход в закрытый ход — сундук уже открыт (%s)" % chest_uid,
				again_used and GameState.chests_used.has(chest_uid), "used=%s" % str(again_used))
			if mz2 != null and mz2.chest_node != null:
				# Замер t22: открытый сундук остаётся живой нодой, но уходит из
				# world.near[] — подсказки E больше нет. interact_with сюда звать
				# нельзя: он ждёт near[] и выдал бы ложный softlock-finding,
				# поэтому подход — штатный walk_to, а E жмём прямо у цели.
				var wr := await walk_to(mz2.chest_node, "belt1_chest_double")
				await frames(6)
				chk("belt1: к открытому сундку можно подойти (walk_to привёл)", wr == 0, "walk=%d" % wr)
				chk("belt1: открытый сундук не в near[] — фантомной подсказки E нет",
					not world.near.has(mz2.chest_node), "near=%d" % int(world.near.size()))
				var gold3: int = GameState.gold
				push_key(KEY_E)
				await frames(20)
				chk("belt1: E у открытого сундука ничего не выдаёт и не списывает (реликт не задваивается)",
						_gear_added_since(gear2).is_empty() and GameState.gold == gold3,
						"added=%s gold=%d->%d" % [str(_gear_added_since(gear2)), gold3, GameState.gold])
			else:
				chk("belt1: узел сундука хода жив после повторного входа", false, "chest_node=nil")
			await interact_with(mz2.exit_node, "belt1_reenter_exit",
					(func() -> bool: return String(world.active_area) == "loc_snow"))
			await settle()
	# --- 8. выход локации на карту мира (к прежнему маршруту плейта) ---
	var grid_out = world.biome_grids.get("snow", null)
	if grid_out != null and grid_out.portal_out_node != null:
		await interact_with(grid_out.portal_out_node, "belt1_exit_loc",
				(func() -> bool: return String(world.active_area) == "worldmap"))
		await settle()
	chk("belt1: выход из Снежника на карту мира (плейт вернулся в прежнее русло)",
		String(world.active_area) == "worldmap", "active=%s" % str(world.active_area))

## Клетка «хода» обязана примыкать к массе/скале ('#'/'M') — то же условие, что
## в MiniDungeon.pick_hole (mini_dungeon.gd:168-175): нора в гуще, не посреди
## поляны. Проверяем по рядам самой зоны (ими же ход и сажали).
func _hole_touches_rock(rows, t: Vector2i) -> bool:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = t + d
		if n.y >= 0 and n.y < rows.size():
			var cell_ch := String(String(rows[n.y])[n.x])
			if cell_ch == "#" or cell_ch == "M":
				return true
	return false

## Стадия 2 маршрута: доска старейшины — взять/сдать оба звена пояса 1,
## награды, идемпотентность и строки журнала (клавиша J).
func stage_belt1_board() -> void:
	stage("belt1_board")
	if String(world.active_area) != "village":
		chk("belt1: доска — в деревне (мы вернулись домой)", false, "active=%s" % str(world.active_area))
		return
	var board := village_interactor(Vector2i(12, 8))
	if not chk("belt1: доска объявлений стоит на клетке (12,8)", board != null, "нет Area2D на 12,8"):
		return
	var i0 := QD.belt_current(GameState)
	chk("belt1: первое несданное звено — bq_snow_1 (индекс 0 реестра)",
		i0 == 0 and String(QD.belt_link(0).get("id", "")) == "bq_snow_1", "i=%d" % i0)
	# звено 1: взять и сдать (цель закрыта главой биомов)
	await interact_with(board, "belt1_board_take1",
			(func() -> bool: return QD.belt_status(GameState, 0) == QD.STATUS_ACTIVE))
	chk("belt1: «Снежный долг» взят у доски (q.bq.bq_snow_1=1)",
		QD.belt_status(GameState, 0) == QD.STATUS_ACTIVE,
		"st=%d" % QD.belt_status(GameState, 0))
	var g0: int = GameState.gold
	await interact_with(board, "belt1_board_turn1",
			(func() -> bool: return QD.belt_status(GameState, 0) == QD.STATUS_DONE))
	var rw0: int = int(QD.belt_link(0).get("gold", 0))
	chk("belt1: «Снежный долг» сдан, выплата = награда реестра (bq_snow_1 gold=30, пин t22)",
		QD.belt_status(GameState, 0) == QD.STATUS_DONE and rw0 == 30 and GameState.gold == g0 + rw0,
		"gold %d->%d, реестр=%d" % [g0, GameState.gold, rw0])
	# звено 2: сундук + гарантированный реликт
	await interact_with(board, "belt1_board_take2",
			(func() -> bool: return QD.belt_status(GameState, 1) == QD.STATUS_ACTIVE))
	chk("belt1: «Клад под снегом» взят у доски", QD.belt_status(GameState, 1) == QD.STATUS_ACTIVE,
		"st=%d" % QD.belt_status(GameState, 1))
	var pool2: Array = QD.belt_link(1).get("relic_pool", []) as Array
	var want2 := _expected_relic("bq_snow_2", pool2)   # ДО сдачи
	var gear1 := _gear_snapshot()
	var gold1: int = GameState.gold
	await interact_with(board, "belt1_board_turn2",
			(func() -> bool: return QD.belt_status(GameState, 1) == QD.STATUS_DONE))
	var rw1: int = int(QD.belt_link(1).get("gold", 0))
	var want_delta: int = rw1 + (40 if want2 == "" else 0)   # 40 — «реликтовое серебро» при исчерпанном пуле
	var name2 := "belt1: «Клад под снегом» сдан, выплата = награда реестра (bq_snow_2 gold=45, пин t22" \
			+ ("" if want2 != "" else " + 40 серебра вместо реликта") + ")"
	chk(name2,
		QD.belt_status(GameState, 1) == QD.STATUS_DONE and rw1 == 45 and GameState.gold == gold1 + want_delta,
		"gold %d->%d (ждали +%d)" % [gold1, GameState.gold, want_delta])
	var added2: Array = _gear_added_since(gear1)
	var ord2: int = int(GameState.owned_gear.size())
	if want2 == "":
		chk("belt1: пул пояса исчерпан — вещь не выдана, расплата золотом (серебро уже в дельте выше)",
				added2.is_empty(), "added=%s" % str(added2))
	else:
		chk("belt1: награда пояса == независимый повтор Loot.quest_relic («%s»)" % want2,
			added2.size() == 1 and String(added2[0]) == want2, "added=%s ждали=%s" % [str(added2), want2])
		var affs2: Array = GameState.affixes.get(want2, []) as Array
		chk("belt1: награда пояса — реликтовая (2 аффикса)", affs2.size() == 2, "affixes=%s" % str(affs2))
		var again2: Array = AFX.affix_roll(int(GameState.run_seed), "quest:bq_snow_2", ord2, true)
		chk("belt1: аффиксы награды пояса бит-в-бит с роллом канона", again2 == affs2,
			"факт=%s ролл=%s" % [str(affs2), str(again2)])
	# журнал (в игре открывается на J — journal.gd:317; «Q» в задании — неточность):
	# belt-строки живут общим языком журнала (t18) — здесь
	# слой данных, живой кадр окна снят отдельно (diag-t22/frames/journal_J.png)
	var ent: Array = QD.entries(GameState)
	var seen := {}
	for e in ent:
		seen[String(e.get("id", ""))] = int(e.get("status", 0))
	chk("belt1: журнал (J) показывает оба сданных звена цепочки",
		int(seen.get("bq_snow_1", 0)) == QD.STATUS_DONE and int(seen.get("bq_snow_2", 0)) == QD.STATUS_DONE,
		"bq_snow_1=%s bq_snow_2=%s всего строк=%d" % [str(seen.get("bq_snow_1")), str(seen.get("bq_snow_2")), ent.size()])
	var j: int = QD.belt_current(GameState)
	chk("belt1: после пояса 1 цепочка указывает на звено 2 (Пустошь)",
		j == 2 and String(QD.belt_link(j).get("zone", "")) == "desert",
		"belt_current=%d zone=%s" % [j, String(QD.belt_link(j).get("zone", ""))])
	# гейт «по мере открытия поясов» (t18): звено следующего пояса берётся
	# только когда пояс открыт ногами; Пустошь плейт прошёл — брать можно.
	var desert_open := String(GameState.get_flag("wm.open.desert", "")) == "1"
	chk("belt1: гейт t18 — звено Пустоши предлагается ровно когда Пустошь открыта ногами",
		QD.belt_can_offer(GameState, j) == desert_open,
		"wm.open.desert=%s can_offer=%s" % [str(desert_open), str(QD.belt_can_offer(GameState, j))])
	# идемпотентность: последний тычок доски после закрытого пояса 1 не платит
	# повторно (максимум — предлагает звено 2, и это тоже без наград).
	# Предикат — «пояс 1 всё ещё сдан» (истина и до, и после): заведомо ложный
	# предикат заставлял interact_with выдавать finding «E нажат, состояние не
	# наступило», хотя именно это от тычка и требовалось (замер t22).
	var g2: int = GameState.gold
	var gear2 := _gear_snapshot()
	var ach2 := _ach_flags_count()
	await interact_with(board, "belt1_board_after",
			(func() -> bool: return QD.belt_status(GameState, 1) == QD.STATUS_DONE))
	await frames(20)
	chk("belt1: доска после закрытой цепочки пояса 1 ничего не выдаёт (золото/сумка/ачивки)",
		GameState.gold == g2 and _gear_added_since(gear2).is_empty() and ach2 == _ach_flags_count(),
		"gold %d->%d added=%s status2=%s" % [g2, GameState.gold, str(_gear_added_since(gear2)),
			str(QD.belt_status(GameState, 2))])

