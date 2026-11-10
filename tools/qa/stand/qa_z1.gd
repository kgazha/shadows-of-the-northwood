extends Node2D
## QA-харнесс волны Z2 (песочница sand_z2, в дифф НЕ входит).
## Прогон: godot --headless res://qa_z1.tscn
## Покрывает: сборка зоны, валидация спавнов, коллизии-пробы, E-турнель
## деревня->Пепелище->деревня, objective-роутинг, respawn, ведьма (50% -> ровно
## 2 стража ровно раз, смерть -> флаг -> лут boss2), сундук, персист-round-trip
## флагов через save/load, пересборка мира без ведьмы/сундука.

const Main := "res://scenes/main.tscn"
const SW := preload("res://scripts/mob_swarmling.gd")
const SAVE_PATH := "user://save_morkheim.json"

var pass_n := 0
var fail_n := 0
var world: Node2D

func chk(cond: bool, name: String) -> void:
	if cond:
		pass_n += 1
		print("qa_z1 ok: ", name)
	else:
		fail_n += 1
		print("qa_z1 FAIL: ", name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	# детерминизм: без старого сейва, без интро-диалогов, класс задан (нет модалки)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	GameState.seen_cave_intro = true
	GameState.elder_quest = 0
	await _frames(2)
	await _phase_build()
	await _phase_nav()
	await _phase_tunnel()
	await _phase_witch()
	await _phase_chest()
	await _phase_persist()
	await _phase_rebuild()
	var total: int = pass_n + fail_n
	print("QA_Z1 %d/%d" % [pass_n, total])
	get_tree().quit(0 if fail_n == 0 else 1)

func _spawn_world() -> Node2D:
	var w: Node2D = load(Main).instantiate()
	add_child(w)
	await _frames(3)
	return w

# ---------------------------------------------------------------- сборка
func _phase_build() -> void:
	world = await _spawn_world()
	chk(world.get("ashen_grid") != null, "ashen_grid собран")
	var az = world.ashen_grid
	chk(int(az.map_w) == 40 and int(az.map_h) == 30, "карта 40x30")
	chk(az.tilemap != null, "тайлмап построен")
	chk(az.boss_node != null, "ведьма заспавнена")
	chk(az.portal_node != null, "портал выхода есть")
	chk(az.chest_node != null, "сундук есть")
	# состав мобов: 2 лучника, стая 4, 2 тенеплёта (+ крыс-стражей пока нет)
	var counts := _count_mobs(world.ashen_zone)
	chk(int(counts["archer"]) == 2, "лучников 2")
	chk(int(counts["swarmling"]) == 4, "стаи 4 крыса")
	chk(int(counts["wraith"]) == 2, "тенеплётов 2")
	chk(int(counts["witch"]) == 1, "ведьма одна")
	# тинты через self_modulate (атмосферная перекраска без новых ассетов)
	var tinted := true
	for n in az.get_children():
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("mob_archer.gd"):
			if n.self_modulate == Color.WHITE:
				tinted = false
	chk(tinted, "лучники перекрашены self_modulate")
	# валидатор: все POI на проходимых клетках
	var f := FileAccess.open("res://data/map_ashen.json", FileAccess.READ)
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	var meta: Dictionary = m["meta"]
	var all_poi: Array = [meta["spawn"], meta["exit_portal"], meta["boss"]]
	all_poi.append_array(meta["chests"])
	all_poi.append_array(meta["herbs"])
	var mobs: Dictionary = meta["mobs"]
	for k in mobs.keys():
		all_poi.append_array(mobs[k])
	var bad := 0
	for p in all_poi:
		if not az.cell_walkable(Vector2i(int(p[0]), int(p[1]))):
			bad += 1
			print("   недостижим POI ", p)
	chk(bad == 0, "все %d POI на проходимых клетках" % all_poi.size())
	# сетка ровная
	var rows_ok: bool = true
	for row in m["grid"]:
		if String(row).length() != 40:
			rows_ok = false
	chk(rows_ok, "все строки по 40")
	# проба физики: блокировщики стоят как стены, пол свободен (нужна активная зона)
	world.apply_area("ashen", true)
	await _frames(2)
	var blocking_cells := 0
	var blocked_hits := 0
	var open_cells := 0
	var open_clear := 0
	for y in az.map_h:
		var row := String((m["grid"] as Array)[y])
		for x in az.map_w:
			var chch := row[x]
			var gp: Vector2 = world.ASHEN_OFFSET + Vector2(x * 16 + 8, y * 16 + 8)
			if "TK#".find(String(chch)) >= 0:
				blocking_cells += 1
				if _probe(gp):
					blocked_hits += 1
			elif (x * 7 + y * 13) % 11 == 0:
				open_cells += 1
				if not _probe(gp):
					open_clear += 1
	chk(blocking_cells > 0 and blocked_hits == blocking_cells,
		"все %d блоков открыты коллизиями" % blocking_cells)
	chk(open_cells > 20 and open_clear == open_cells,
		"пол свободен (%d/%d проб)" % [open_clear, open_cells])
	world.apply_area("village", true)
	await _frames(2)
	# деревенский портал «A»: проходим и без стены
	chk(world._village_walkable(Vector2i(45, 20)), "клетка A (45,20) проходима")
	chk(not _probe(Vector2(45 * 16 + 8, 20 * 16 + 8)), "клетка A без коллизии")
	var gate: Node = _find_gate()
	chk(gate != null, "AshenGate в деревне")
	var pathv: Array = world.build_path(world.tile_to_world(world.spawn_tile), world.tile_to_world(Vector2i(45, 20)))
	chk(not pathv.is_empty(), "деревня: путь до A есть")

func _probe(gp: Vector2) -> bool:
	var st := world.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = gp
	q.collision_mask = 2
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return st.intersect_point(q, 4).size() > 0

func _count_mobs(node: Node) -> Dictionary:
	var out := {"archer": 0, "swarmling": 0, "wraith": 0, "witch": 0, "guard": 0}
	_tally(node, out)
	return out

func _tally(node: Node, out: Dictionary) -> void:
	for n in node.get_children():
		if n.get_script() != null:
			var p := String(n.get_script().resource_path)
			if p.ends_with("mob_archer.gd"):
				out["archer"] += 1
			elif p.ends_with("mob_wraith.gd"):
				out["wraith"] += 1
			elif p.ends_with("mob_boss2.gd"):
				out["witch"] += 1
			elif p.ends_with("mob_swarmling.gd"):
				out["swarmling"] += 1
				if String(n.get("swarm_id")) == "witch_guard":
					out["guard"] += 1
		_tally(n, out)  # мобы висят на ashen_grid (глубже на уровень)

func _find_gate() -> Node:
	for n in world.village_zone.get_children():
		if n.has_method("get_hint") and String(n.call("get_hint")) == "Войти в Пепелище":
			return n
	return null

# ---------------------------------------------------------------- пути/зона
func _phase_nav() -> void:
	world.apply_area("ashen", true)
	await _frames(2)
	var az = world.ashen_grid
	var sp: Vector2 = world.ASHEN_OFFSET + az.spawn_world_pos
	var boss: Vector2 = world.ASHEN_OFFSET + az.tile_to_world(az.boss_tile)
	var pth: Array = world.build_path(sp, boss)
	chk(not pth.is_empty(), "ashen: путь спавн->ведьма найден")
	# камера ограничена зоной
	chk(int(world.cam.limit_top) == int(world.ASHEN_OFFSET.y), "камера: ashen limits")
	# respawn внутри ashen
	world.respawn_player()
	var rp: Vector2 = world.player.global_position
	chk(is_equal_approx(rp.x, sp.x) and is_equal_approx(rp.y, sp.y), "respawn в Пепелище")
	# objective: квест пещеры, а герой в Пепелище -> стрелка на портал выхода
	GameState.elder_quest = 2
	var ob: Vector2 = world.objective_pos()
	chk(ob == az.portal_node.global_position, "objective из ashen -> портал выхода")
	GameState.elder_quest = 0
	world.apply_area("village", true)
	await _frames(2)
	chk(int(world.cam.limit_top) == 0, "камера: обратно деревня")

# ---------------------------------------------------------------- E-турнель
func _phase_tunnel() -> void:
	var gate: Node = _find_gate()
	var before: Vector2 = world.player.global_position
	gate.try_interact()  # как E-взаимодействие (не вход ходьбой)
	await _frames(90)    # фейд-твин 0.5 c с запасом
	chk(String(world.active_area) == "ashen", "E: турнель в Пепелище")
	var az = world.ashen_grid
	var sp: Vector2 = world.ASHEN_OFFSET + az.spawn_world_pos
	var d: float = world.player.global_position.distance_to(sp)
	chk(d < 2.0, "телепорт на спавн Пепелища")
	chk(world.cave_zone.visible == false and world.village_zone.visible == false, "зоны скрыты")
	chk(world.ashen_zone.visible, "ashen видима")
	chk(String(GameState.flags.get("ashen.intro_seen", "")) == "1", "флаг ashen.intro_seen")
	# обратно порталом (E)
	az.portal_node.try_interact()
	await _frames(90)
	chk(String(world.active_area) == "village", "E: турнель обратно")
	var db: float = world.player.global_position.distance_to(before)
	chk(db < 2.0, "возврат на место входа")
	chk(GameState.in_cave == false, "в Пепелище герой НЕ in_cave")

# ---------------------------------------------------------------- ведьма
func _phase_witch() -> void:
	# achv first_blood (+10g в on_mob_death) не должен попадать в окно лута:
	# считаем анлок уже выданным (детерминизм дельты золота)
	GameState.set_flag("ach.first_blood", true)
	world.apply_area("ashen", true)
	await _frames(2)
	var az = world.ashen_grid
	var witch = az.boss_node
	chk(int(witch.hp) == 48, "hp x2 = 48")
	chk(absf(float(witch.speed) - 34.0 * 0.9) < 0.01, "скорость x0.9")
	chk(float(witch.charge_cd) == 0.0, "рывок выключен (нет чужого тоста)")
	var c0 := _count_mobs(world.ashen_zone)
	chk(int(c0["guard"]) == 0, "стражей нет до порога")
	witch.hurt(24, witch.global_position + Vector2(20, 0))  # ровно 50%
	await _frames(2)
	var c1 := _count_mobs(world.ashen_zone)
	chk(int(c1["guard"]) == 2, "на 50% — РОВНО 2 стража")
	witch.hurt(1, witch.global_position + Vector2(20, 0))
	await _frames(2)
	var c2 := _count_mobs(world.ashen_zone)
	chk(int(c2["guard"]) == 2, "повторный порог — стража НЕ респаунится")
	# лут босса: boss2 35..60 золота всегда, зелье по шансу
	var g0: int = GameState.gold
	var p0: int = GameState.brewed_potions
	var xp0: int = GameState.xp
	var lvl0: int = GameState.level
	var witch2 = az.boss_node
	witch2.hurt(999, witch2.global_position + Vector2(0, 20))
	await _frames(4)
	chk(not is_instance_valid(witch2), "ведьма мертва (queue_free)")
	chk(String(GameState.flags.get("ashen.boss", "")) == "dead", "флаг ashen.boss=dead")
	var dg: int = GameState.gold - g0
	chk(dg >= 35 and dg <= 60, "лут boss2: золото %d в [35..60]" % dg)
	var dp: int = GameState.brewed_potions - p0
	chk(dp >= 0 and dp <= 1, "зелье boss2 по шансу (0..1)")
	chk(GameState.level > lvl0 or GameState.xp >= xp0 + 25, "XP +25 выдан")
	var c3 := _count_mobs(world.ashen_zone)
	chk(int(c3["guard"]) == 2, "после смерти стража не удвоилась")
	chk(GameState.boss_defeated == false, "cave boss_defeated НЕ тронут")

# ---------------------------------------------------------------- сундук
func _phase_chest() -> void:
	var az = world.ashen_grid
	var chest = az.chest_node
	var g0: int = GameState.gold
	chest.try_interact()
	chk(String(GameState.flags.get("ashen.chest", "")) == "taken", "флаг ashen.chest=taken")
	chk(GameState.gold - g0 >= 8, "награда сундука золотом")
	chest = az.chest_node
	if chest != null and is_instance_valid(chest):
		chest.try_interact()  # защита от двойного нажатия до queue_free
	chk(GameState.gold - g0 < 60, "повторный interact не удваивает награду")

# ---------------------------------------------------------------- персист флагов
func _phase_persist() -> void:
	# save/load round-trip флагов (сейв v2, поле flags)
	chk(GameState.save_game(), "save_game ok")
	GameState.set_flag("ashen.boss", "подмена")
	chk(String(GameState.flags.get("ashen.boss", "")) == "подмена", "подмена принята")
	chk(GameState.load_game(), "load_game ok")
	chk(String(GameState.flags.get("ashen.boss", "")) == "dead", "flag пережил save/load")
	# мир ниже перестраиваем БЕЗ сейва, чтобы load_game не тащил прошлое состояние
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

# ---------------------------------------------------------------- пересборка мира
func _phase_rebuild() -> void:
	world.queue_free()
	await _frames(4)
	(SW.SWARMS as Dictionary).clear()  # статика моба: чистим между мирами
	world = await _spawn_world()
	var az = world.ashen_grid
	chk(az != null and az.boss_node == null, "пересборка: ведьмы нет (флаг dead)")
	chk(az.chest_node == null, "пересборка: сундука нет (флаг taken)")
	var c := _count_mobs(world.ashen_zone)
	chk(int(c["archer"]) == 2 and int(c["wraith"]) == 2, "пересборка: аркадные спавны на месте")
	chk(int(c["swarmling"]) == 4 and int(c["guard"]) == 0, "пересборка: стая 4, стражи 0")
	chk(az.portal_node != null, "пересборка: портал на месте")
	# музыка/атмосфера не падали: зона активируется штатно
	world.apply_area("ashen", true)
	await _frames(2)
	chk(String(world.active_area) == "ashen", "пересборка: вход работает")
