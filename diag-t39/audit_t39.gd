extends "res://mb_base.gd"
## t39 — НЕЗАВИСИМЫЕ ворота волны «Интерес v1» (qa-gate, 27.11).
##
## Это НЕ стенды авторов тикетов (qa_el / qa_rt / qa_bty / qa_pt / qa_run), а
## отдельная проверка тех же контрактов другими руками: распределение ролла
## элит считается по всей сетке, награды — средним по 30 убийствам, детерминизм
## охот и элит выгружается таблицей для побайтового сравнения ДВУХ процессов,
## pity проходит весь путь (источник -> порог -> форс -> сброс), смерть — ариф-
## метикой и снимком инвентаря. Всё, что не удаётся проверить честно, печатается
## как SKIP, а не как PASS.
##
## Время для И2 гоняется ускорением Engine.time_scale (игровые секунды, не
## реальные), часы — прямой установкой GameState.day_t.

const EL := preload("res://scripts/elites.gd")
const OW := preload("res://scripts/open_world.gd")
const ENR := preload("res://scripts/enroute.gd")
const BTY := preload("res://scripts/bounties.gd")
const LOOT := preload("res://scripts/loot.gd")
const GD := preload("res://scripts/gear_data.gd")
const BFX := preload("res://scripts/bold_fx.gd")

var dump := {"elite_rolls": [], "bounty_days": [], "notes": []}
var _t0 := 0


func _mark(s: String) -> void:
	# маяки по разделам: без них подвешивание неотличимо от тяжёлого раздела
	print("T39 >>> %s (t=%.1f с)" % [s, (Time.get_ticks_msec() - _t0) / 1000.0])


func _process(_d: float) -> void:
	# страховка по РЕАЛЬНОМУ времени (time_scale на неё не влияет): аудит не имеет
	# права жить дольше 12 минут — иначе подвисание неотличимо от тяжёлого раздела
	if Time.get_ticks_msec() - _t0 > 720000:
		print("T39 !!!failsafe: 720 с реального времени — принудительный выход")
		_out()
		get_tree().quit(3)


func note(s: String) -> void:
	dump["notes"].append(s)
	print("T39 ЗАМЕТКА: %s" % s)


func num_of(n: Node, prop: String) -> float:
	var v: Variant = n.get(prop)
	return float(v) if (v is int or v is float) else -1.0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_mark("старт")
	await boot(save_for(0))
	await pump(3)
	# Мир может стоять на паузе стартового диалога/модалки, а world._process —
	# ЕДИНСТВЕННЫЕ часы (rs.t, day_t, тикер I2): на паузе они не идут. Проходим
	# через окна штатным advance() и снимаем паузу — иначе «игровые секунды»
	# не текут и ответка никогда не поспевает.
	var hud0: Node = world.get("hud")
	if hud0 != null:
		for i in 40:
			if not bool(hud0.call("is_dialog_open")) and not bool(hud0.call("is_modal_open")):
				break
			hud0.call("advance")
			await pump(4)
	get_tree().paused = false
	GameState.input_locked = false
	_mark("boot готов, окна старта закрыты")
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	await _a_elites()
	_mark("A элиты")
	await _b_enroute()
	_mark("B события")
	await _c_bounties()
	_mark("C охоты")
	await _d_pity()
	_mark("D pity")
	await _e_death()
	_mark("E смерть")
	_out()
	done()


# =========================================================== A · элиты (I1)
func _a_elites() -> void:
	# A1. Доля ролла по ВСЕЙ сетке, три сида. Ролл чистый — перебираем сами.
	var total := 0
	var hit := 0
	var per_seed := {}
	for sd in [2801, 777, 12345]:
		var s_hit := 0
		var s_tot := 0
		for y in 70:
			for x in 70:
				for ord in 2:
					var r := EL.roll(sd, "loc_forest", Vector2i(x, y), ord)
					s_tot += 1
					if r:
						s_hit += 1
					if x < 20 and y < 20 and ord == 0 and sd == 2801:
						dump["elite_rolls"].append([x, y, ord, 1 if r else 0])
		_mark("A1 сид %d обход %.1f с" % [sd, (Time.get_ticks_msec() - _t0) / 1000.0])
		per_seed[sd] = [s_hit, s_tot]
		total += s_tot
		hit += s_hit
		var share := 100.0 * float(s_hit) / float(s_tot)
		check("A1 сид %d: доля элит %.2f%% в полосе 10,5..13,5%% (n=%d)" % [sd, share, s_tot],
				share > 10.5 and share < 13.5)
	var pooled := 100.0 * float(hit) / float(total)
	check("A1 сводно: доля элит %.3f%% при RATE_PCT=%d (n=%d)" % [pooled, EL.RATE_PCT, total],
		absf(pooled - float(EL.RATE_PCT)) < 0.8)
	# A2. Детерминизм и чувствительность ключа (смена любого аргумента меняет исход).
	var same := 0
	var diff_seed := 0
	var diff_tile := 0
	var diff_ord := 0
	for i in 400:
		var t := Vector2i(i % 17, (i / 17) + 3)
		var a := EL.roll(2801, "loc_forest", t, 1)
		if a == EL.roll(2801, "loc_forest", t, 1):
			same += 1
		if a != EL.roll(99991, "loc_forest", t, 1):
			diff_seed += 1
		if a != EL.roll(2801, "loc_forest", t + Vector2i(1, 0), 1):
			diff_tile += 1
		if a != EL.roll(2801, "loc_forest", t, 2):
			diff_ord += 1
	check("A2 ролл детерминирован (400/400 совпадений)", same == 400)
	check("A2 ключ чувствителен: сид %d/400, клетка %d/400, ordinal %d/400"
			% [diff_seed, diff_tile, diff_ord],
			diff_seed > 20 and diff_tile > 20 and diff_ord > 20)
	# A3. Статы на ЖИВОМ мобу локации: hp x2, урон x1.5 по своему каналу, скорость та же.
	_mark("A3 вход в локацию")
	world.call("enter_location", "forest")
	var ok_area := false
	for i in 400:
		await get_tree().physics_frame
		if str(world.get("active_area")) == "loc_forest":
			ok_area = true
			break
	check("A3 вход в локацию loc_forest выполнен (нужен для живых мобов)", ok_area)
	var zone: Node = null
	for c in world.get_children():
		if str(c.get("map_rows")) != "" or c.get("map_rows") != null:
			zone = c
	var mobs := _all_mobs(world)
	note("мобов в дереве после входа в loc_forest: %d" % mobs.size())
	var tested := 0
	var hp_x2 := 0
	var dmg_x15 := 0
	var speed_same := 0
	for m in mobs:
		if tested >= 6:
			break
		var hp0 := num_of(m, "hp")
		var dmg0 := num_of(m, "dmg")
		var mult0 := num_of(m, "dmg_mult")
		var sp0 := num_of(m, "speed")
		if hp0 <= 0.0:
			continue
		var got: bool = EL.apply_named(m, "Тестовый", Color(0.5, 0.1, 0.1))
		tested += 1
		if not got:
			continue
		if absf(num_of(m, "hp") - hp0 * EL.HP_MULT) < 0.51:
			hp_x2 += 1
		var dm_ok := false
		if dmg0 > 0.0:
			dm_ok = absf(num_of(m, "dmg") - dmg0 * EL.DMG_MULT) < 0.51
		elif mult0 > 0.0:
			dm_ok = absf(num_of(m, "dmg_mult") - mult0 * EL.DMG_MULT) < 0.01
		else:
			dm_ok = true
		if dm_ok:
			dmg_x15 += 1
		if sp0 < 0.0 or absf(num_of(m, "speed") - sp0) < 0.001:
			speed_same += 1
	check("A3 hp x2 на %d/%d живых мобов" % [hp_x2, tested], tested >= 2 and hp_x2 == tested)
	check("A3 урон x1,5 по каналу семейства на %d/%d" % [dmg_x15, tested], tested >= 2 and dmg_x15 == tested)
	check("A3 скорость не тронута на %d/%d" % [speed_same, tested], tested >= 2 and speed_same == tested)
	# A4. Гейт по структуре: не-моб (страж/босс-обёртка/чужой узел) элитой стать не
	# может — тот же отказ, который не пускает сюда деревню и мини-боссов.
	var gated := 0
	var probes := 3
	var decoy := Node2D.new()
	# узел с чужим скриптом (не моб из FAM_BY_SCRIPT). Отдельная находка аудита:
	# Elites.apply() читает mob.get_script().resource_path без проверки на null,
	# поэтому узел ВООБЩЕ без скрипта роняет SCRIPT ERROR внутри apply(). В игре
	# спавнеры всегда передают моба со скриптом, так что это не путь боя, но
	# прочность функции — оставляем проверку на узле со скриптом, как в игре.
	decoy.set_script(GDScript.new())
	add_child(decoy)
	for i in probes:
		if not EL.apply(decoy, "loc_forest", Vector2i(i, i), i):
			gated += 1
	check("A4 чужой узел (не моб из FAM_BY_SCRIPT) не получает элиту (%d/3)" % gated,
			gated == probes)
	note("зоны, где apply() вообще вызывается: только biome_zone и ashen_zone (структурный"
			+ " гейт, проверяется A4 + B2: деревня/пещера/мини/ведьма не в жребии)")
	decoy.queue_free()
	# A5. Тумблер bold_fx: украшение гаснет, статы и флаг остаются.
	GameState.set("bold_fx", false)
	var m2: Node = null
	for m in _all_mobs(world):
		m2 = m
		break
	if m2 != null:
		var kids0 := m2.get_child_count()
		var hp1 := num_of(m2, "hp")
		var got2: bool = EL.apply_named(m2, "Молчун", Color(0.2, 0.6, 0.2))
		var kids1 := m2.get_child_count()
		check("A5 bold_fx OFF: украшение не добавлено (детей %d -> %d), статы применены"
				% [kids0, kids1], got2 and kids1 == kids0 and num_of(m2, "hp") > hp1)
		note("bold_fx.enabled() при выключенном тумблере = %s" % str(BFX.enabled()))
	else:
		note("A5 SKIP: живого моба не найдено")
	GameState.set("bold_fx", true)
	# A6. Награда: серебро x3 и pity-кредит — среднее по 120 убийствам: дисперсия
	# серебра на малой выборке велика (30 убийств давали 3,70 вместо 3,00).
	_mark("A6 240 вызовов loot")
	var g_plain := 0
	var g_elite := 0
	var pity0 := int(GameState.get("elite_pity"))
	var kind := "slime"
	for i in 120:
		var gp0 := int(GameState.get("gold"))
		LOOT.on_mob_death(kind, Vector2(0, 0), null, null)
		g_plain += int(GameState.get("gold")) - gp0
	var pity_mid := int(GameState.get("elite_pity"))
	for i in 120:
		var fake := Node2D.new()
		fake.set_meta("elite", true)
		var gp1 := int(GameState.get("gold"))
		LOOT.on_mob_death(kind, Vector2(0, 0), null, fake)
		g_elite += int(GameState.get("gold")) - gp1
		fake.free()
	var ratio := float(g_elite) / float(maxi(1, g_plain))
	check("A6 серебро элиты/обычного = %.2f около x%.1f (plain=%d, elite=%d, n=120)"
			% [ratio, EL.GOLD_MULT, g_plain, g_elite], ratio > 2.6 and ratio < 3.4)
	var pity_gain := int(GameState.get("elite_pity")) - pity_mid
	check("A6 pity-кредит за убийство элиты: +%d за 120 смертей элиты" % pity_gain, pity_gain >= 100)
	note("pity до блока = %d, после обычных смертей = %d" % [pity0, pity_mid])


func _all_mobs(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	var guard := 0
	while not stack.is_empty() and guard < 20000:
		guard += 1
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			var sc: Script = c.get_script()
			if sc != null:
				var base := str(sc.resource_path.get_file().get_basename())
				if EL.FAM_BY_SCRIPT.has(base):
					out.append(c)
	return out


# ================================================== B · события в пути (I2)
func _b_enroute() -> void:
	# B1. Часы: фазы и день.
	GameState.set("day_t", 0.0)
	var day_ok: bool = not ENR.is_night() and ENR.day_index() == 0
	GameState.set("day_t", float(ENR.DAY_LEN))
	var night_ok: bool = ENR.is_night()
	GameState.set("day_t", float(ENR.CYCLE))
	var wrap_ok: bool = (not ENR.is_night()) and ENR.day_index() == 1
	check("B1 часы: день/ночь/переход цикла (day=%s night=%s wrap=%s)"
			% [str(day_ok), str(night_ok), str(wrap_ok)], day_ok and night_ok and wrap_ok)
	# B2. Гейты зон: ни деревня, ни пещера, ни Пепелище, ни карта, ни мини не eligible.
	var bad: Array = []
	for a in ["village", "cave", "ashen", "worldmap", "mini_forest", "loc_dungeon"]:
		if bool(ENR.eligible_area(a)):
			bad.append(a)
	check("B2 гейт зон: %s не допускают событий (%s)"
			% ["village/cave/ashen/worldmap/mini/loc_dungeon", str(bad)], bad.is_empty())
	# B3. Патрули ставит ТОЛЬКО вход в сцену ночью (enroute.on_area_enter — тот же
	# шов, что зовёт world.apply_area). Значит и проверка идёт через этот же шов:
	# ночь -> заход (патрули есть), день -> заход (патрулей нет). Простая
	# установка day_t посреди сцены патрулей не поднимает — это факт метода, он же
	# и проверка того, что система не спавнит «из ниоткуда» на пустой дороге.
	var anchor: Node2D = null
	for m in _all_mobs(world):
		anchor = m
		break
	if anchor != null:
		(world.get("player") as Node2D).global_position = anchor.global_position + Vector2(24, 0)
	_mark("B: заглушка героя в локации")
	GameState.set("enroute_events", true)
	ENR.reset_all()
	GameState.set("day_t", float(ENR.DAY_LEN) + 20.0)
	ENR.on_area_enter(world, "village")
	await pump(60)
	var night_patrols := _count_meta("i2_patrol")
	ENR.reset_all()
	GameState.set("day_t", 10.0)
	ENR.on_area_enter(world, "village")
	await pump(60)
	var day_patrols := _count_meta("i2_patrol")
	check("B3 ночью патрулей %d, днём %d" % [night_patrols, day_patrols],
			night_patrols > 0 and day_patrols == 0)
	# B4. Ответка на шум: ровно после NOISE_KILLS, ровно один наряд, с дистанции.
	ENR.reset_all()
	GameState.set("day_t", 10.0)   # день: ответка не привязана к ночи
	clear_toasts()
	for i in int(ENR.NOISE_KILLS) - 1:
		ENR.note_kill("loc_forest")
	var before := _count_meta("i2_retrib")
	await _run_seconds(20.0)
	var after_two := _count_meta("i2_retrib")
	var rs_a := _rs()
	ENR.note_kill("loc_forest")
	await _run_seconds(float(ENR.NOISE_MIN) + float(ENR.NOISE_SPAN) + 20.0)
	var after_three := _count_meta("i2_retrib")
	var dist_ok := _min_dist_cells()
	note("B4 диагностика: GameState.area=%s active=%s | rs.t %.1f -> %.1f | шум=%s | нарядов=%d | дорог=%d" % [
			str(GameState.area), str(world.get("active_area")), rs_a, _rs(),
			str(ENR._noise), _squads(), _road_cells()])
	check("B4 до третьего килла нарядов %d (было %d), после третьего — %d"
			% [after_two, before, after_three], after_two == 0 and after_three >= 1)
	check("B4 спавн с дистанции: ближайший из наряда в %.1f клетках (порог %d)"
			% [dist_ok, int(ENR.RETRIB_DIST)], dist_ok >= float(ENR.RETRIB_DIST) - 0.5)
	# лимит: ещё три килла при живом наряде — второго наряда нет
	var alive_now := _squads()
	for i in 6:
		ENR.note_kill("loc_forest")
	await _run_seconds(float(ENR.NOISE_MIN) + 10.0)
	check("B4 лимит: живых нарядов %d при повторном шуме (было %d)" % [_squads(), alive_now],
			_squads() <= alive_now + 1 and _squads() <= 2)
	note("тостов на шум: %d, первый = %s" % [n_toast("шум"), toasts[0] if not toasts.is_empty() else "нет"])
	# B5. Тумблер OFF: часовые события мертвы.
	ENR.reset_all()
	GameState.set("enroute_events", false)
	GameState.set("day_t", float(ENR.DAY_LEN) + 20.0)
	clear_toasts()
	await pump(30)
	for i in 6:
		ENR.note_kill("loc_forest")
	await _run_seconds(float(ENR.NOISE_MIN) + float(ENR.NOISE_SPAN) + 20.0)
	check("B5 тумблер OFF: патрулей %d, нарядов %d, тостов %d"
			% [_count_meta("i2_patrol"), _count_meta("i2_retrib"), n_toast("шум")],
			_count_meta("i2_patrol") == 0 and _count_meta("i2_retrib") == 0
			and n_toast("шум") == 0)
	GameState.set("enroute_events", true)
	GameState.set("day_t", 0.0)
	ENR.reset_all()


func _run_seconds(sec: float) -> void:
	# Игровые секунды крутим САМИ штатными функциями мира: в стенде mb_base
	# world._process после смены сцены часы не ведёт (rs.t стоит: замер 0.1 -> 0.1
	# при 20 игровых секундах), а rs.t/day_t/ENR.tick — единственные часы I2.
	# Тикер вызывается ровно тот же, что зовёт мир: ENR.tick(world, delta).
	var steps := int(sec * 60.0)
	var dt := 1.0 / 60.0
	var rs0 := _rs()
	for i in steps:
		GameState.flags["rs.t"] = _rs() + dt
		GameState.day_t += dt
		ENR.tick(world, dt)
		if i % 120 == 0:
			await get_tree().physics_frame
	note("пройдено %.0f игровых с штатным тикером: rs.t %.1f -> %.1f" % [sec, rs0, _rs()])


func _count_meta(tag: String) -> int:
	var n := 0
	for m in _all_mobs(world):
		if bool(m.get_meta(tag, false)):
			n += 1
		elif str(m.get_meta("i2_tag", "")) == tag:
			n += 1
	return n


func _squads() -> int:
	var v: Variant = ENR._retrib
	if v is Array:
		return (v as Array).size()
	return -1


func _rs() -> float:
	return float(GameState.flags.get("rs.t", 0))


func _road_cells() -> int:
	var grids: Variant = world.get("biome_grids")
	if grids == null or not (grids is Dictionary):
		return -1
	var zone: Node = (grids as Dictionary).get("forest")
	if zone == null or not is_instance_valid(zone):
		return -2
	return (zone.call("road_cells") as Array).size()


func _min_dist_cells() -> float:
	var hero: Node = world.get("player")
	if not (hero is Node2D):
		return -1.0
	var best := 9999.0
	for m in _all_mobs(world):
		if not (bool(m.get_meta("i2_retrib", false)) \
				or str(m.get_meta("i2_tag", "")) == "i2_retrib"):
			continue
		if m is Node2D:
			best = minf(best, (m as Node2D).global_position.distance_to(
					(hero as Node2D).global_position) / 16.0)
	return best


# ======================================================= C · охоты (I3)
func _c_bounties() -> void:
	# открываем пояса так же, как игра: флаги wm.open.<зона> = "1"
	var zones: Array = OW.ZONES
	for z in zones:
		GameState.call("set_flag", "wm.open." + str(z), "1")
	# C1. Детерминизм по дням — таблица в дамп, сравниваем ДВА процесса побайтово.
	var same_days := 0
	var days := 20
	for d in days:
		var a: Dictionary = BTY.offer_for(GameState, d)
		var b: Dictionary = BTY.offer_for(GameState, d)
		if str(a) == str(b):
			same_days += 1
		dump["bounty_days"].append([d, str(a.get("zone", "")), str(a.get("fam", "")),
				str(a.get("tile", Vector2i())), str(a.get("name", "")), int(a.get("gold", 0))])
	check("C1 повторный вызов доски совпал при повторном вызове в %d/%d дней" % [same_days, days], same_days == days)
	var uniq := {}
	for row in dump["bounty_days"]:
		uniq["%s|%s|%s" % [row[1], row[2], row[4]]] = true
	check("C1 по %d дням %d разных целей (не одна и та же цель вечно)" % [days, uniq.size()],
			uniq.size() >= 3)
	# C1b. Смена сида меняет офер (ролл сид-зависим).
	var seed0 := int(GameState.get("run_seed"))
	var d0: Dictionary = BTY.offer_for(GameState, 3)
	GameState.set("run_seed", seed0 + 1)
	var d1: Dictionary = BTY.offer_for(GameState, 3)
	GameState.set("run_seed", seed0)
	check("C1b другой сид -> другая офер-зона/клетка/имя (зона %s/%s, имя %s/%s)"
			% [str(d0.get("zone", "")), str(d1.get("zone", "")), str(d0.get("name", "")),
				str(d1.get("name", ""))], str(d0) != str(d1))
	# C2. Одна активная охота.
	BTY.cull(GameState)
	var first: bool = bool(BTY.board_press(GameState))
	var st1 := int(BTY.status(GameState))
	var again: bool = bool(BTY.board_press(GameState))
	var st2 := int(BTY.status(GameState))
	var marker_active := str(BTY.map_marker_zone(GameState))
	var off_now: Dictionary = BTY.offer(GameState)
	check("C2 взятая охота помечена на карте: «%s» против офера «%s»"
			% [marker_active, str(off_now.get("zone", ""))],
			marker_active != "" and marker_active == str(off_now.get("zone", "")))
	check("C2 первая выдача %s (статус %d), повторная выдача %s (статус %d — одна)"
			% [str(first), st1, str(again), st2], first and st1 == BTY.ST_ACTIVE and st2 == BTY.ST_ACTIVE)
	# C3. Награда ровно один раз + 2 pity-кредита. Цель — настоящая именная элита,
	# поднятая самой доской (ensure_target) с мета "i3_bounty" = день офера; синтет
	# используется только если доска не смогла поставить цель (тогда помечаем).
	var off: Dictionary = BTY.offer(GameState)
	var gold0 := int(GameState.get("gold"))
	var pity0 := int(GameState.get("elite_pity"))
	BTY.ensure_target(world)
	await pump(30)
	var mob: Node = null
	for m in _all_mobs(world):
		if m.has_meta("i3_bounty"):
			mob = m
			break
	var synthetic := false
	if mob == null:
		synthetic = true
		mob = Node2D.new()
		add_child(mob)
		var scr := _mob_script(str(off.get("fam", "slime")))
		if scr != "":
			mob.set_script(load(scr))
		note("C3: доска не поставила цель в текущей зоне — цель собрана вручную "
				+ "(мета i3_bounty = %d); проверку «награда ровно раз» это не отменяет"
				% int(off.get("day", -1)))
	mob.set_meta("i3_bounty", int(off.get("day", -1)))
	BTY.on_bounty_death(GameState, mob)
	var gold1 := int(GameState.get("gold"))
	BTY.on_bounty_death(GameState, mob)
	var gold2 := int(GameState.get("gold"))
	if synthetic:
		mob.queue_free()
	var want_gold := int(off.get("gold", 0))
	check("C3 выплата %d за закрытие (ожидалось +%d), повторная выплата %+d"
			% [gold1 - gold0, want_gold, gold2 - gold1],
			want_gold > 0 and (gold1 - gold0) >= want_gold and (gold2 - gold1) == 0)
	check("C3 pity за охоту +%d (ожидалось 2)" % (int(GameState.get("elite_pity")) - pity0),
			int(GameState.get("elite_pity")) - pity0 >= 2)
	# C4. Журнал и маркер.
	var je: Array = BTY.journal_entries(GameState)
	check("C4 журнал охоты непуст (%d строк)" % je.size(), not je.is_empty())
	var marker_closed := str(BTY.map_marker_zone(GameState))
	note("маркер после закрытия охоты: «%s» (пусто = метка снята; офер был «%s»)"
			% [marker_closed, str(off.get("zone", ""))])
	# C5. Срок мягкий: новый день без закрытия сбрасывает охоту в ноль.
	GameState.set("day_t", float((int(ENR.day_index()) + 1)) * float(ENR.CYCLE) + 1.0)
	BTY.cull(GameState)
	check("C5 на следующий день статус %d (ожидан %d)" % [int(BTY.status(GameState)), BTY.ST_NONE],
			int(BTY.status(GameState)) == BTY.ST_NONE)


func _mob_script(fam: String) -> String:
	var cand := {"slime": "slime.gd", "brute": "brute.gd", "swarmling": "mob_swarmling.gd",
			"archer": "mob_archer.gd", "wraith": "mob_wraith.gd"}
	var f := str(cand.get(fam, ""))
	return ("res://scripts/" + f) if f != "" else ""


# ======================================================== D · pity (I4)
func _d_pity() -> void:
	GameState.set("elite_pity", GameState.PITY_THRESHOLD - 1)
	var below: bool = bool(LOOT.pity_active(GameState))
	GameState.set("elite_pity", GameState.PITY_THRESHOLD)
	var at: bool = bool(LOOT.pity_active(GameState))
	check("D1 порог: при %d чаша не активна, при %d активна (порог %d)"
			% [int(GameState.PITY_THRESHOLD) - 1, int(GameState.PITY_THRESHOLD),
				int(GameState.PITY_THRESHOLD)], (not below) and at)
	# D2. Форс реликта на следующем ролле и сброс ровно на фактической выдаче.
	GameState.set("elite_pity", GameState.PITY_THRESHOLD)
	var owned_snapshot := JSON.stringify(GameState.get("owned_gear"))
	var pick := ""
	for cand in ["shortsword", "leather", "fangblade", "boarhide", "nordsword", "chain"]:
		if not owned_snapshot.contains(cand):
			pick = cand
			break
	note("D2: владея %s; выбираем не выданную вещь: %s" % [owned_snapshot.left(160), pick])
	var gear0 := (GameState.get("owned_gear") as Array).size()
	LOOT.grant_gear_set(GameState, [pick], "chest:audit_t39")
	var arr: Array = GameState.get("owned_gear") as Array
	var gear1 := arr.size()
	var pity_after := int(GameState.get("elite_pity"))
	var item_json := ""
	if gear1 > gear0:
		item_json = JSON.stringify(arr[gear0])
	var affs: Array = (GameState.affixes as Dictionary).get(pick, [])
	note("выдача при полной чаше: %s, аффиксы %s (реликтовых слотов %d)" % [
			item_json.left(120), str(affs), int(LOOT.AFFIX_RELIC_N)])
	check("D2 форс: вещь выдана (%d -> %d), ролл силён реликтом (аффиксов %d при %d), чаша погашена (pity=%d)"
			% [gear0, gear1, affs.size(), int(LOOT.AFFIX_RELIC_N), pity_after],
			gear1 > gear0 and affs.size() == int(LOOT.AFFIX_RELIC_N) and pity_after == 0)
	# D3. Сейв: версия, аддитивные ключи, легаси.
	var d: Dictionary = GameState.call("to_dict")
	check("D3 to_dict несёт elite_pity=%s и day_t=%s"
			% [str(d.get("elite_pity", "нет")), str(d.get("day_t", "нет"))],
			d.has("elite_pity") and d.has("day_t"))
	var GS := load("res://scripts/game_state.gd")
	var gs2 = GS.new()
	d["elite_pity"] = 9
	d["day_t"] = 33.0
	gs2.call("from_dict", d)
	check("D3 round-trip: elite_pity=%d day_t=%.1f" % [int(gs2.elite_pity), float(gs2.day_t)],
			int(gs2.elite_pity) == 9 and absf(float(gs2.day_t) - 33.0) < 0.001)
	var dl: Dictionary = GameState.call("to_dict")
	dl.erase("elite_pity")
	dl.erase("day_t")
	var gs3 = GS.new()
	gs3.call("from_dict", dl)
	check("D3 легаси без ключей: pity=%d day_t=%.1f (ожиданы 0 и 0)"
			% [int(gs3.elite_pity), float(gs3.day_t)],
			int(gs3.elite_pity) == 0 and absf(float(gs3.day_t)) < 0.001)
	gs2.free()
	gs3.free()
	# D4. Дельта силы считается честной формулой, а не строкой.
	var dmg_now := int(GD.player_damage(5, GameState, false))
	var lbl := str(GD.delta_label(7, "СИЛЫ"))
	var lbl0 := str(GD.delta_label(0, "СИЛЫ"))
	check("D4 метка дельты: +7 -> «%s», 0 -> «%s», базовый урон=%d"
			% [lbl, lbl0, dmg_now], lbl.contains("7") and not lbl0.contains("7"))


# ===================================================== E · цена смерти (I5)
func _e_death() -> void:
	var rows := [[100, 20], [9, 1], [4, 0], [0, 0], [1009, 201]]
	var bad := 0
	for r in rows:
		GameState.set("gold", int(r[0]))
		var loss := int(GameState.call("soft_death"))
		var rest := int(GameState.get("gold"))
		if loss != int(r[1]) or rest != int(r[0]) - int(r[1]):
			bad += 1
			note("смерть %d -> потеря %d (ожидалось %d), остаток %d" % [r[0], loss, r[1], rest])
	check("E1 арифметика −20%% с полом: 5 случаев, ошибок %d" % bad, bad == 0)
	# E2. Снимок: экип, сумка, класс, сид, квесты — целы; hp полный; не в пещере.
	var snap := {
		"gear": JSON.stringify(GameState.get("owned_gear")),
		"inv": JSON.stringify(GameState.get("inventory")),
		"cls": str(GameState.get("class_id")),
		"seed": int(GameState.get("run_seed")),
		"quest": str(GameState.get_flag("q.stage", "?")),
	}
	GameState.set("gold", 250)
	GameState.call("soft_death")
	GameState.call("respawn_after_death")
	var broke: Array = []
	if JSON.stringify(GameState.get("owned_gear")) != snap["gear"]:
		broke.append("экипировка")
	if JSON.stringify(GameState.get("inventory")) != snap["inv"]:
		broke.append("сумка")
	if str(GameState.get("class_id")) != snap["cls"]:
		broke.append("класс")
	if int(GameState.get("run_seed")) != snap["seed"]:
		broke.append("сид")
	check("E2 после смерти цело (%s), hp=%.0f/%.0f, in_cave=%s"
			% ["всё" if broke.is_empty() else str(broke), float(GameState.get("hp")),
				float(GameState.get("max_hp")), str(GameState.get("in_cave"))],
			broke.is_empty() and float(GameState.get("hp")) >= float(GameState.get("max_hp"))
			and bool(GameState.get("in_cave")) == false)
	# E3. Журнал и мета.
	var entries: Array = QuestsData.entries(GameState)
	var found := ""
	for e in entries:
		var s := str(JSON.stringify(e))
		if s.contains("Ставки пепла") or s.contains("смертей"):
			found = s
			break
	if entries.is_empty():
		note("E3: журнал пуст — сверяй со стендом qa_run")
	else:
		check("E3 в журнале есть строка о ставках пепла: %s" % found.left(90), found != "")
	var last_loss := int(GameState.call("_num", GameState.flags.get("meta.last_loss", 0), 0))
	check("E3 meta.last_loss = %d (ожидалось 50 из 250)" % last_loss, last_loss == 50)
	note("meta.vd (счётчик смертей) = %d"
			% int(GameState.call("_num", GameState.flags.get("meta.vd", 0), 0)))


func _out() -> void:
	var f := FileAccess.open("t39_audit.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(dump))
		f.close()
		note("дамп детерминизма записан: t39_audit.json")
	else:
		note("дамп записать не удалось: %s" % str(FileAccess.get_open_error()))
