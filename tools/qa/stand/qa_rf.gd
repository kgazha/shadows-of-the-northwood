extends Node2D
## qa_rf: порядок загрузки персистентного состояния в world._ready().
## Кейсы (env QA_RF_S), каждый = свой user://save_morkheim.json ДО instantiating
## main.tscn (дальше мир грузит сейв сам — именно момент загрузки и проверяем):
##   1 — перезаход в пещеру с открытой дверью (door_opened + cave_state=1, in_cave)
##   2 — открытый сундук после рестарта (has_amulet)
##   3 — использованный костёр + использованный деревенский сундук
##   4 — босс убит (cave_state=2/boss_defeated) — без повторного спавна босса/лута
##   5 — старый сейв без полей v2 (только v1-набор) — tolerant load
## Порядок загрузки ловится зондом stats_changed: from_dict() эмитит stats_changed
## в самом конце, поэтому по состоянию мира в этот момент видно, ГДЕ произошёл
## load_game() — до спавнов (как надо) или после них (как было).
## Временный харнесс песочницы: в дифф не входит.

const SAVE := "user://save_morkheim.json"
const DOOR := Vector2i(17, 18)
const CHEST := Vector2i(18, 18)
const HINT_DOOR := "Открыть дверь"
const HINT_CHEST := "Открыть сундук"
const CAVE_PX := 264.0
const CAVE_PY := 5096.0  # клетка (16,18) — коридор у открытой двери, в стороне от лестницы выхода

var total := 0
var ok := 0
var main = null
var stats_probe := {}  # что видел мир в момент первого stats_changed (from_dict)

func _ready() -> void:
	var s := 1
	var e := OS.get_environment("QA_RF_S")
	if e != "":
		s = int(e)
	_wipe_save()
	_seed_save(s)
	print("qa_rf DIAG seeded file: ", _save_state_on_disk())
	var before := _save_state_on_disk()
	GameState.stats_changed.connect(_on_stats_changed)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	print("qa_rf DIAG after _ready: in_cave=%s cave_vis=%s player=%s" % [GameState.in_cave, main.cave_zone.visible, main.player.global_position])
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("qa_rf DIAG after 2 frames: in_cave=%s cave_vis=%s player=%s" % [GameState.in_cave, main.cave_zone.visible, main.player.global_position])
	var dz = main.dungeon_zone
	if dz == null:
		print("qa_rf s=%d FAIL: dungeon_zone не построен" % s)
		get_tree().quit(1)
		return
	match s:
		1:
			_case_door(dz)
		2:
			_case_chest(dz)
		3:
			_case_campfire()
		4:
			_case_boss(dz)
		5:
			_case_legacy()
	# автосейв на quest_changed обязан был нормализовать файл, а не испортить его
	_chk("s%d: сейв на диске читабелен после старта" % s, before != "" and _save_state_on_disk() != "")
	print("qa_rf s=%d ИТОГ: %d/%d" % [s, ok, total])
	get_tree().quit(1 if ok < total else 0)

## Зонд порядка: срабатывает ровно один раз — на первом stats_changed.
func _on_stats_changed() -> void:
	if not stats_probe.is_empty():
		return
	stats_probe = {
		"flags": GameState.door_opened or GameState.has_amulet or GameState.boss_defeated or GameState.in_cave,
		"cf_used_present": not GameState.campfires_used.is_empty(),
		"village_null": main == null or main.get("village_zone") == null,
		"cave_null": main == null or main.get("cave_zone") == null,
		"dz_null": main == null or main.get("dungeon_zone") == null,
	}

## 1: дверь открыта в прошлой сессии — игрок возвращается в пещеру.
func _case_door(dz) -> void:
	print("qa_rf DIAG s1: probe=%s in_cave=%s cave_visible=%s player=%s save=%s" % [
		str(stats_probe), str(GameState.in_cave), str(main.cave_zone.visible),
		str(main.player.global_position), _save_state_on_disk()])
	_chk_order("s1")
	_chk("s1: in_cave из сейва применён", GameState.in_cave and main.cave_zone.visible)
	_chk("s1: cave_state=1", GameState.cave_state == 1)
	_chk("s1: дверь открыта", GameState.door_opened)
	_chk("s1: CaveDoor не заспавнен (нет фантомной подсказки)", _hint_node(dz, HINT_DOOR) == null)
	_chk("s1: тайл двери = атлас 0", _atlas_x(dz, DOOR) == 0)
	_probe("s1: клетка двери (%d,%d) свободна" % [DOOR.x, DOOR.y], _w(DOOR), false)
	_probe("s1: подход (%d,%d) свободен" % [16, 18], _w(Vector2i(16, 18)), false)
	_chk("s1: тон атмосферы — пещера мгновенно (zone_changed(in_cave, true) уже знает зону)", _is_cave_tint())
	_chk("s1: игрок в пещере", main.player.global_position.y > main.CAVE_OFFSET.y)

## 2: амулет взят в прошлой сессии.
func _case_chest(dz) -> void:
	_chk_order("s2")
	_chk("s2: has_amulet из сейва", GameState.has_amulet)
	_chk("s2: CaveChest не заспавнен", _hint_node(dz, HINT_CHEST) == null)
	_chk("s2: dz.chest_node не висит", dz.chest_node == null or not is_instance_valid(dz.chest_node))
	_chk("s2: тайл сундука = атлас 12", _atlas_x(dz, CHEST) == 12)
	_probe("s2: клетка сундука (%d,%d) свободна" % [CHEST.x, CHEST.y], _w(CHEST), false)
	_probe("s2: ниша (%d,%d) свободна" % [19, 18], _w(Vector2i(19, 18)), false)
	_chk("s2: cell_walkable(сундук) == true", dz.cell_walkable(CHEST))

## 3: привал и деревенский сундук уже использованы.
func _case_campfire() -> void:
	_chk("s3: in_cave=false, активна деревня", not GameState.in_cave and main.village_zone.visible)
	_chk("s3: в момент from_dict деревня ещё не построена (костры спавнятся уже с сейвом)",
		stats_probe.get("village_null") == true and stats_probe.get("cf_used_present") == true)
	var used_cf: Array = []
	var live_cf: Array = []
	for cf in main.campfires:
		if cf.used:
			used_cf.append(cf.camp_id)
		else:
			live_cf.append(cf.camp_id)
	_chk("s3: погашен ровно cf_village", used_cf == ["cf_village"])
	# Ребейз на «один костёр в мире» (CAMPFIRE_SPOTS): cf_forest/cf_cave удалены —
	# канон фиксируем строго: костёр в мире ровно один и он погашен (живых нет).
	_chk("s3: костёр в мире ровно один (cf_forest/cf_cave удалены)", main.campfires.size() == 1)
	_chk("s3: живых костров не осталось", live_cf.is_empty())
	var cf = _campfire("cf_village")
	_chk("s3: подсказка погасшего костра", cf != null and cf.get_hint() == "Костёр погас")
	_chk("s3: зона E погасшего костра выключена", cf != null and cf._shape.disabled)
	_chk("s3: campfire_near() его не видит", main.campfire_near() == null or main.campfire_near().camp_id != "cf_village")
	var ch = _chest(Vector2i(37, 21))
	_chk("s3: деревенский сундук 37,21 помнит открытым", ch != null and ch.used)
	_chk("s3: подсказка открытого сундука", ch != null and ch.get_hint() == "Пустой сундук")
	_chk("s3: тон атмосферы — лес", not _is_cave_tint())

## 4: босс убит в прошлой сессии — он не должен воскреснуть (и отдать лут дважды).
func _case_boss(dz) -> void:
	_chk_order("s4")
	_chk("s4: cave_state=2", GameState.cave_state >= 2)
	_chk("s4: boss_defeated", GameState.boss_defeated)
	_chk("s4: dz.boss_node пуст", dz.boss_node == null or not is_instance_valid(dz.boss_node))
	var bosses := 0
	var mobs := 0
	for n in dz.get_children():
		if n.get("boss") == null:
			continue
		if n.get("boss") == true:
			bosses += 1
		else:
			mobs += 1
	_chk("s4: боссов в дереве 0 (лут не задваивается)", bosses == 0)
	_chk("s4: обычные мобны спавнятся (>=1)", mobs >= 1)
	_chk("s4: BossTrigger не мешает (нет диалога)", not main.hud.is_dialog_open())
	_probe("s4: клетка босса (12,16) пуста (тела врага нет)", _w(Vector2i(12, 16)), false, 4)

## 5: старый сейв без v2-полей.
func _case_legacy() -> void:
	_chk("s5: загрузился без падения", main != null)
	_chk("s5: класс из legacy-дефолта — воин", GameState.class_id == "warrior")
	_chk("s5: gold=0", GameState.gold == 0)
	# legacy-миграция: has_sword в старом сейве => gear.weapon == "sword" (game_state.gd:387)
	_chk("s5: gear.migration: weapon=sword, armor пуст", String(GameState.gear["weapon"]) == "sword" and String(GameState.gear["armor"]) == "")
	_chk("s5: flags пуст", GameState.flags.is_empty())
	_chk("s5: костры целы (сейв без campfires_used)", GameState.campfires_used.is_empty())
	_chk("s5: сундуки целы", GameState.chests_used.is_empty())
	var any_used := false
	for cf in main.campfires:
		if cf.used:
			any_used = true
	_chk("s5: ни один костёр не «использован»", not any_used)
	_chk("s5: cave_state=0, пещера не начата", GameState.cave_state == 0 and not GameState.in_cave)
	_chk("s5: hp полон (поля hp нет в сейве)", GameState.hp == GameState.max_hp)
	_chk("s5: сундук-спавн в деревне закрыт", _chest(Vector2i(37, 21)) != null and not _chest(Vector2i(37, 21)).used)

## Ключевой порядок: from_dict() уже применил флаги, а мира ещё нет — значит
## load_game() отработал ДО спавнов, чувствительных к персисту.
func _chk_order(tag: String) -> void:
	_chk("%s: в момент from_dict деревня/пещера ещё не построены (load до спавнов)" % tag,
		stats_probe.get("flags") == true and stats_probe.get("village_null") == true
			and stats_probe.get("cave_null") == true and stats_probe.get("dz_null") == true)

# ---------- утилиты ----------

func _seed_save(s: int) -> void:
	var d := {
		"class_id": "warrior", "level": 3, "xp": 40, "xp_next": 60,
		"hp": 20, "mana": 5, "seen_intro": true, "in_cave": false,
		"px": 136.0, "py": 168.0, "pos_valid": true,
		"v": 2, "gold": 10,
	}
	match s:
		1:
			d["cave_state"] = 1
			d["has_key"] = true
			d["door_opened"] = true
			d["in_cave"] = true
			d["seen_cave_intro"] = true
			d["px"] = CAVE_PX
			d["py"] = CAVE_PY
		2:
			d["cave_state"] = 2
			d["has_key"] = true
			d["door_opened"] = true
			d["has_amulet"] = true
			d["boss_defeated"] = true
			d["in_cave"] = true
			d["seen_cave_intro"] = true
			d["seen_boss_intro"] = true
			d["px"] = CAVE_PX
			d["py"] = CAVE_PY
		3:
			d["cave_state"] = 1
			d["has_key"] = true
			d["campfires_used"] = {"cf_village": true}
			d["chests_used"] = ["chest@37,21"]
			d["materials"] = {"suhotsvet": 1, "zhim": 0}
			d["brewed"] = 1
		4:
			d["cave_state"] = 2
			d["boss_defeated"] = true
			d["has_key"] = true
			d["door_opened"] = true
			d["has_amulet"] = true
			d["in_cave"] = true
			d["seen_cave_intro"] = true
			d["seen_boss_intro"] = true
			d["px"] = CAVE_PX
			d["py"] = CAVE_PY
		5:
			# только v1-набор: ни v, ни gold/gear/flags, ни campfires/chests, ни hp
			d = {"class_id": "warrior", "level": 3, "xp": 40, "xp_next": 60,
				"max_hp": 20, "mana": 5, "damage": 3, "has_sword": true,
				"herbs": 2, "slime_kills": 4, "elder_quest": 1, "slime_quest": 0,
				"seen_intro": true, "px": 136.0, "py": 168.0, "pos_valid": true}
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))

func _save_state_on_disk() -> String:
	if not FileAccess.file_exists(SAVE):
		return ""
	var f := FileAccess.open(SAVE, FileAccess.READ)
	return f.get_as_text()

func _wipe_save() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

func _w(t: Vector2i) -> Vector2:
	return main.CAVE_OFFSET + Vector2(t.x * 16 + 8, t.y * 16 + 8)

func _probe(what: String, p: Vector2, expect_hit: bool, mask: int = 2) -> void:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hit: bool = not get_world_2d().direct_space_state.intersect_point(q).is_empty()
	_chk("%s (ждали %s)" % [what, "твёрдо" if expect_hit else "свободно"], hit == expect_hit)

func _chk(msg: String, cond: bool) -> void:
	total += 1
	if cond:
		ok += 1
	else:
		print("qa_rf FAIL: %s" % msg)

func _atlas_x(dz, t: Vector2i) -> int:
	if dz.tilemap == null or dz.tilemap.get_cell_source_id(t) < 0:
		return -1
	return dz.tilemap.get_cell_atlas_coords(t).x

func _hint_node(dz, hint: String) -> Node:
	for n in dz.find_children("*", "Area2D", true, false):
		if n.has_method("get_hint") and n.get_hint() == hint:
			return n
	return null

func _campfire(id: String) -> Node:
	for cf in main.campfires:
		if cf.camp_id == id:
			return cf
	return null

func _chest(t: Vector2i) -> Node:
	for n in main.village_zone.get_children():
		if n.get("kind") == "chest" and n.get("tile_xy") == t:
			return n
	return null

func _is_cave_tint() -> bool:
	var atm = main.atmosphere
	if atm == null or atm._cm == null:
		return false
	return atm._cm.color == atm.TINT_CAVE
