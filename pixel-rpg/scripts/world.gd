extends Node2D
## Мир: карта из JSON, стены-коллизии, игрок, сущности, диалоги, сейвы.
## Две зоны в контейнерах Node2D: "Village" (деревня) и "Cave" (пещера).
## Пещера сдвинута на CAVE_OFFSET, чтобы физика зон никогда не пересекалась;
## переход — затемнение, смена видимости зон и телепорт героя.

const TILE := 16
const Nav := preload("res://scripts/nav.gd")
const CHAR_TO_TILE := {
	"g": 0, "G": 1, "f": 2, "d": 3, "w": 4, "t": 5, "W": 6, "R": 7,
	"D": 8, "#": 9, "r": 12, "s": 13, "T": 15,
}
const BLOCKING := [4, 5, 6, 7, 8, 9, 12, 13]
const CAVE_OFFSET := Vector2(0, 4800.0)      # «этаж» пещеры в общих координатах
const CAVE_ENTRANCE_TILE := Vector2i(40, 17) # вход в пещеру в лесу (тайл проходим: T)

var map_rows: Array = []
var map_w := 0
var map_h := 0
var meta: Dictionary = {}
var spawn_tile := Vector2i(8, 10)
var dialogues: Dictionary = {}
var player: CharacterBody2D
var hud: CanvasLayer
var near: Array = []
var hint_label: Label
var village_zone: Node2D
var cave_zone: Node2D
var dungeon_zone  # scripts/dungeon_zone.gd (типизирован слабо — API: setup/spawn_world_pos/map_w/map_h)
var cam: Camera2D
var fade_rect: ColorRect
var village_return_pos := Vector2.INF  # куда возвращаться из пещеры (то место, где вошли)
var cur_move: Texture2D    # курсор «идти» (cursor_move.png)
var cur_enemy: Texture2D   # курсор «атака» (cursor_enemy.png)
var atmosphere             # scripts/atmosphere.gd: свет/тени/частицы/цветокор (весь визуал спринта «Атмосфера»)

func _ready() -> void:
	var mf := FileAccess.open("res://data/map_village.json", FileAccess.READ)
	meta = JSON.parse_string(mf.get_as_text())
	map_rows = meta["grid"]
	map_h = map_rows.size()
	map_w = String(map_rows[0]).length()
	var sp: Array = meta["spawn"]
	spawn_tile = Vector2i(int(sp[0]), int(sp[1]))
	var df := FileAccess.open("res://data/dialogues.json", FileAccess.READ)
	dialogues = JSON.parse_string(df.get_as_text())
	# догрузка текстов сценариста: dialogues_v2.json может отсутствовать (параллельная работа),
	# его ключи перекрывают старые
	if FileAccess.file_exists("res://data/dialogues_v2.json"):
		var vf := FileAccess.open("res://data/dialogues_v2.json", FileAccess.READ)
		if vf != null:
			var v2: Variant = JSON.parse_string(vf.get_as_text())
			if typeof(v2) == TYPE_DICTIONARY:
				dialogues.merge(v2, true)
	village_zone = Node2D.new()
	village_zone.name = "Village"
	add_child(village_zone)
	cave_zone = Node2D.new()
	cave_zone.name = "Cave"
	cave_zone.position = CAVE_OFFSET
	add_child(cave_zone)
	_build_tiles()
	_build_walls()
	_spawn_player()
	_spawn_entities()
	_build_cave()
	_build_cave_entrance()
	atmosphere = load("res://scripts/atmosphere.gd").new()
	add_child(atmosphere)
	atmosphere.setup(self)
	atmosphere.zone_changed(GameState.in_cave, true)  # стартовое состояние после загрузки сейва — без фейда
	_build_fade()
	_load_cursors()
	hud = load("res://scripts/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	if GameState.load_game():
		apply_zone(GameState.in_cave, false)
		if GameState.pos_valid:
			player.global_position = GameState.player_pos
		player.apply_class()
		hud.refresh_skills()
	if GameState.class_id == "":
		# новые игры: сначала выбор героя, интро — после (в _start_intro)
		hud.show_class_modal(_start_intro)
	else:
		_start_intro()

func _start_intro() -> void:
	if not GameState.seen_intro:
		GameState.seen_intro = true
		start_dialogue("intro")

func _load_cursors() -> void:
	if ResourceLoader.exists("res://assets/cursor_move.png"):
		cur_move = load("res://assets/cursor_move.png")
	if ResourceLoader.exists("res://assets/cursor_enemy.png"):
		cur_enemy = load("res://assets/cursor_enemy.png")

func tile_to_world(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE + 2.0)

func _build_tiles() -> void:
	var ts := TileSet.new()
	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/tiles.png")
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in 16:
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.z_index = -10
	village_zone.add_child(layer)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var ch := row[x]
			if CHAR_TO_TILE.has(ch):
				layer.set_cell(Vector2i(x, y), 0, Vector2i(int(CHAR_TO_TILE[ch]), 0))

func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 2
	body.collision_mask = 0
	village_zone.add_child(body)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var ch := row[x]
			if not CHAR_TO_TILE.has(ch):
				continue
			if int(CHAR_TO_TILE[ch]) in BLOCKING:
				var cs := CollisionShape2D.new()
				var sh := RectangleShape2D.new()
				sh.size = Vector2(TILE, TILE)
				cs.shape = sh
				cs.position = Vector2(x * TILE + 8, y * TILE + 8)
				body.add_child(cs)

func _spawn_player() -> void:
	player = load("res://scripts/player.gd").new()
	player.position = tile_to_world(spawn_tile)
	add_child(player)
	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = map_w * TILE
	cam.limit_bottom = map_h * TILE
	player.add_child(cam)
	cam.make_current()
	hint_label = Label.new()
	hint_label.position = Vector2(-45, -26)
	hint_label.size = Vector2(90, 10)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(1, 1, 0.75))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_label.add_theme_constant_override("outline_size", 4)
	hint_label.add_theme_font_size_override("font_size", 8)
	player.add_child(hint_label)

func _spawn_entities() -> void:
	var npc_script := load("res://scripts/npc.gd")
	for e: Array in meta.get("npcs", []):
		var npc = npc_script.new()
		village_zone.add_child(npc)
		npc.setup(self, String(e[0]), Vector2i(int(e[1]), int(e[2])))
		npc.input_event.connect(_on_area_pick.bind(npc))  # ЛКМ по NPC = дойти и взаимодействовать
	var it_script := load("res://scripts/interactable.gd")
	for e: Array in meta.get("herbs", []):
		var herb = it_script.new()
		village_zone.add_child(herb)
		herb.setup(self, "herb", Vector2i(int(e[0]), int(e[1])))
		herb.input_event.connect(_on_area_pick.bind(herb))
	for e: Array in meta.get("chests", []):
		var chest = it_script.new()
		village_zone.add_child(chest)
		chest.setup(self, "chest", Vector2i(int(e[0]), int(e[1])))
		chest.input_event.connect(_on_area_pick.bind(chest))
	var slime_script := load("res://scripts/slime.gd")
	for e: Array in meta.get("slimes", []):
		var slime = slime_script.new()
		village_zone.add_child(slime)
		slime.setup(self, Vector2i(int(e[0]), int(e[1])))

func _build_cave() -> void:
	var dz = load("res://scripts/dungeon_zone.gd").new()
	cave_zone.add_child(dz)
	dz.setup(self)
	dungeon_zone = dz
	# интерактив пещеры (отшельник, лестница, дверь, сундук) — тоже кликабелен мышью
	for ch in dz.get_children():
		if ch.has_method("get_hint") and "input_event" in ch:
			ch.input_event.connect(_on_area_pick.bind(ch))
	cave_zone.visible = false
	cave_zone.process_mode = Node.PROCESS_MODE_DISABLED

func _build_cave_entrance() -> void:
	var stairs := CaveStairs.new()
	village_zone.add_child(stairs)
	stairs.setup(self, CAVE_ENTRANCE_TILE)
	stairs.input_event.connect(_on_area_pick.bind(stairs))

func _build_fade() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 10
	add_child(cl)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # не есть мышь: слой выше HUD!
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(fade_rect)

func _process(_delta: float) -> void:
	if player == null:
		return
	var i := near.size() - 1
	while i >= 0:
		if not is_instance_valid(near[i]):
			near.remove_at(i)
		i -= 1
	near.sort_custom(func(a, b):
		return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	if near.is_empty() or GameState.input_locked:
		hint_label.text = ""
	else:
		hint_label.text = "E: " + near[0].get_hint()
	_update_cursor()

# --- мышь: курсор и враги под курсором ---

## Враг (группа "enemy") под мировой точкой p — физ-запрос к слою 4.
func _enemy_at(p: Vector2) -> Node2D:
	if player == null:
		return null
	var space := get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = 4
	q.collide_with_bodies = true
	q.collide_with_areas = false
	for res in space.intersect_point(q, 8):
		var c = res.collider
		if c != null and is_instance_valid(c) and c.is_in_group("enemy"):
			return c
	return null

func _update_cursor() -> void:
	if GameState.input_locked or cur_move == null:
		Input.set_custom_mouse_cursor(null)  # во время диалога/модалки — обычный
		return
	var e := _enemy_at(get_global_mouse_position())
	if e != null and cur_enemy != null:
		Input.set_custom_mouse_cursor(cur_enemy, Input.CURSOR_ARROW, Vector2(8, 8))
	else:
		Input.set_custom_mouse_cursor(cur_move, Input.CURSOR_ARROW, Vector2(8, 8))

## ЛКМ по интерактиву (Area2D с get_hint) — дойти и try_interact().
func _on_area_pick(_vp: Node, ev: InputEvent, _shape: int, obj) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if GameState.input_locked or hud.is_dialog_open() or hud.is_modal_open():
			return
		if is_instance_valid(obj):
			player.command_interact(obj)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if GameState.input_locked:
		var advance_input: bool = event.is_action_pressed("interact") or event.is_action_pressed("attack") \
			or event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton and event.pressed \
				and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT))
		if advance_input and hud.is_dialog_open():
			hud.advance()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		if not near.is_empty() and near[0].has_method("try_interact"):
			near[0].try_interact()
	elif event.is_action_pressed("quicksave"):
		GameState.player_pos = player.global_position
		GameState.pos_valid = true
		if GameState.save_game():
			GameState.toast.emit("Игра сохранена (F5)")
		else:
			GameState.toast.emit("Не удалось сохранить")
	elif event.is_action_pressed("quickload"):
		if GameState.load_game():
			apply_zone(GameState.in_cave, false)
			if GameState.pos_valid:
				player.global_position = GameState.player_pos
			player.apply_class()
			hud.refresh_skills()
			GameState.toast.emit("Игра загружена (F9)")
		else:
			GameState.toast.emit("Сохранение не найдено")
	# --- мышь-приказы и скиллы (спринт 2) ---
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var e := _enemy_at(get_global_mouse_position())
			if e != null:
				player.command_attack(e)
			else:
				player.command_move(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			player.cancel_orders()
	elif event.is_action_pressed("ui_cancel"):
		player.cancel_orders()
	elif event.is_action_pressed("potion"):
		drink_potion()
	else:
		for i in 4:
			if event.is_action_pressed("skill_%d" % (i + 1)):
				player.cast_skill(i, get_global_mouse_position())

# --- зелья ---

## Лесное зелье: трава -> +3 HP (клавиша Q или кнопка на HUD).
func drink_potion() -> void:
	if GameState.input_locked or hud.is_dialog_open() or hud.is_modal_open():
		return
	if GameState.herbs <= 0:
		GameState.toast.emit("Трав нет. Собери их у кустов (E).")
		return
	if GameState.hp >= GameState.max_hp:
		GameState.toast.emit("Ты и так здрав.")
		return
	GameState.herbs -= 1
	GameState.heal(3)
	GameState.quest_changed.emit()  # автосейв + обновление HUD
	GameState.toast.emit("Лесное зелье: +3 HP")

# --- маркер цели квеста ---

## Мировые координаты текущей цели для HUD-стрелки (Vector2.INF — цели нет).
func objective_pos() -> Vector2:
	var target := _objective_raw()
	if target == Vector2.INF or player == null:
		return Vector2.INF
	# цель в другой зоне — стрелка ведёт к переходу
	var target_in_cave: bool = target.y > CAVE_OFFSET.y - 1000.0
	if target_in_cave != GameState.in_cave:
		if GameState.in_cave and dungeon_zone != null and dungeon_zone.stairs_node != null:
			return dungeon_zone.stairs_node.global_position
		if not GameState.in_cave:
			return tile_to_world(CAVE_ENTRANCE_TILE)
	return target

func _objective_raw() -> Vector2:
	if GameState.elder_quest < 2:
		if GameState.elder_quest == 1 and GameState.herbs < 3:
			var hb := _nearest_herb()
			if hb != null:
				return hb.global_position
		var el := _find_npc("elder")
		return el.global_position if el != null else Vector2.INF
	# --- линия пещеры (cave_state 0..3) ---
	if GameState.cave_state >= 4:
		return Vector2.INF
	if dungeon_zone == null:
		return Vector2.INF
	if GameState.cave_state == 3:
		if not GameState.has_amulet:
			if GameState.door_opened and is_instance_valid(dungeon_zone.chest_node):
				return dungeon_zone.chest_node.global_position
			if dungeon_zone.door_tile.x >= 0:
				return CAVE_OFFSET + dungeon_zone.tile_to_world(dungeon_zone.door_tile)
		if dungeon_zone.hermit_node != null:
			return dungeon_zone.hermit_node.global_position
		return Vector2.INF
	if not GameState.boss_defeated and is_instance_valid(dungeon_zone.boss_node):
		return dungeon_zone.boss_node.global_position
	if dungeon_zone.hermit_node != null:
		return dungeon_zone.hermit_node.global_position
	return Vector2.INF

func _find_npc(id: String) -> Node2D:
	for n in village_zone.get_children():
		if n.get("npc_id") != null and n.get("npc_id") == id:
			return n
	return null

func _nearest_herb() -> Node2D:
	if player == null:
		return null
	var best: Node2D = null
	var bd := INF
	for h in village_zone.get_children():
		if h.get("kind") != null and h.get("kind") == "herb" and h.get("used") != true:
			var d := player.global_position.distance_squared_to(h.global_position)
			if d < bd:
				bd = d
				best = h
	return best

# --- навигация: путь в обход препятствий ---

func _village_walkable(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.y >= map_h or t.x >= map_w:
		return false
	var row := String(map_rows[t.y])
	if t.x >= row.length():
		return false
	var ch := row[t.x]
	if not CHAR_TO_TILE.has(ch):
		return true
	return not (int(CHAR_TO_TILE[ch]) in BLOCKING)

func _active_nav() -> Dictionary:
	if GameState.in_cave and dungeon_zone != null:
		return {"w": dungeon_zone.map_w, "h": dungeon_zone.map_h, "walk": dungeon_zone.cell_walkable, "base": CAVE_OFFSET}
	return {"w": map_w, "h": map_h, "walk": _village_walkable, "base": Vector2.ZERO}

static func _world_to_tile(p: Vector2, base: Vector2) -> Vector2i:
	var l := p - base
	return Vector2i(int(floor(l.x / TILE)), int(floor(l.y / TILE)))

## Мирные точки -> массив мировых точек пути (пусто — прямая/недостижимо).
func build_path(from_w: Vector2, to_w: Vector2) -> Array:
	var ctx := _active_nav()
	var st := _world_to_tile(from_w, ctx["base"])
	var gt := _world_to_tile(to_w, ctx["base"])
	var raw: Array = Nav.astar(ctx["walk"], int(ctx["w"]), int(ctx["h"]), st, gt)
	if raw.is_empty():
		return []
	var simp: Array = Nav.simplify(raw, ctx["walk"])
	var out: Array = []
	for t: Vector2i in simp:
		out.append(ctx["base"] + tile_to_world(t))
	return out

## Прямая линия свободна (для «короткой дистанции — без обхода»).
func line_clear(a: Vector2, b: Vector2) -> bool:
	var ctx := _active_nav()
	return Nav.los(_world_to_tile(a, ctx["base"]), _world_to_tile(b, ctx["base"]), ctx["walk"])

# --- переход между зонами ---

## Смена активной зоны. teleport=false — позиция останется из сейва (загрузка).
func apply_zone(to_cave: bool, teleport: bool = true) -> void:
	GameState.in_cave = to_cave
	village_zone.visible = not to_cave
	cave_zone.visible = to_cave
	village_zone.process_mode = Node.PROCESS_MODE_DISABLED if to_cave else Node.PROCESS_MODE_INHERIT
	cave_zone.process_mode = Node.PROCESS_MODE_INHERIT if to_cave else Node.PROCESS_MODE_DISABLED
	near.clear()
	player.cancel_orders()  # приказы прошлой зоны не тянем в новую
	if teleport:
		if to_cave:
			village_return_pos = player.global_position
			if dungeon_zone != null:
				player.global_position = CAVE_OFFSET + dungeon_zone.spawn_world_pos
		else:
			player.global_position = village_return_pos if village_return_pos != Vector2.INF else tile_to_world(spawn_tile)
	_set_cam_limits(to_cave)
	if atmosphere != null:
		atmosphere.zone_changed(to_cave)

func _set_cam_limits(to_cave: bool) -> void:
	if to_cave and dungeon_zone != null:
		cam.limit_left = int(CAVE_OFFSET.x)
		cam.limit_top = int(CAVE_OFFSET.y)
		cam.limit_right = int(CAVE_OFFSET.x) + int(dungeon_zone.map_w) * TILE
		cam.limit_bottom = int(CAVE_OFFSET.y) + int(dungeon_zone.map_h) * TILE
	else:
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = map_w * TILE
		cam.limit_bottom = map_h * TILE

## Плавный переход: затемнение -> смена зоны -> просветление.
## after — что сделать после (обычно диалог); без него просто снимаем блокировку ввода.
func transition_to(to_cave: bool, after: Callable = Callable()) -> void:
	GameState.input_locked = true
	var t := get_tree().create_tween()
	t.tween_property(fade_rect, "color:a", 1.0, 0.25)
	t.tween_callback(apply_zone.bind(to_cave))
	t.tween_property(fade_rect, "color:a", 0.0, 0.25)
	t.tween_callback(func():
		if after.is_valid():
			after.call()
		else:
			GameState.input_locked = false)

func enter_cave() -> void:
	if GameState.in_cave:
		return
	var first := not GameState.seen_cave_intro
	transition_to(true, func():
		if first:
			GameState.seen_cave_intro = true
			start_dialogue("cave_intro")
			if not hud.is_dialog_open():
				GameState.input_locked = false
		else:
			GameState.input_locked = false)

func exit_cave() -> void:
	if not GameState.in_cave:
		return
	transition_to(false)

# --- диалоги и квесты ---

func start_dialogue(key: String, cb: Callable = Callable()) -> void:
	if not dialogues.has(key):
		push_warning("Нет диалога: %s" % key)
		return
	hud.show_dialog(dialogues[key], cb)

func talk(id: String) -> void:
	match id:
		"elder":
			match GameState.elder_quest:
				0:
					start_dialogue("elder_quest", func():
						GameState.elder_quest = 1
						GameState.quest_changed.emit())
				1:
					if GameState.herbs >= 3:
						start_dialogue("elder_done", func():
							GameState.elder_quest = 2
							GameState.add_xp(25)
							GameState.heal_full())
					else:
						start_dialogue("elder_progress")
				_:
					start_dialogue("elder_after")
		"merchant":
			match GameState.slime_quest:
				0:
					start_dialogue("merchant", func():
						GameState.slime_quest = 1
						GameState.quest_changed.emit())
				1:
					if GameState.slime_kills >= 3:
						start_dialogue("merchant_done", func():
							GameState.slime_quest = 2
							GameState.add_xp(30))  # урон теперь от класса/меча/амулета
					else:
						start_dialogue("merchant_progress")
				_:
					start_dialogue("merchant_after")
		"hermit":
			match GameState.cave_state:
				0:
					start_dialogue("hermit_quest", func():
						GameState.cave_state = 1
						GameState.quest_changed.emit())
				1:
					if GameState.boss_defeated:
						_hermit_give_key()
					else:
						start_dialogue("hermit_progress")
				2:
					_hermit_give_key()
				3:
					if GameState.has_amulet:
						start_dialogue("amulet_done", func():
							GameState.cave_state = 4
							GameState.add_xp(60)
							GameState.quest_changed.emit())
					else:
						start_dialogue("hermit_after")
				_:
					start_dialogue("hermit_after")
		_:
			start_dialogue(id)

## Босс мёртв, ключ не отдан: Геральд дарит ключ от алтарного зала.
func _hermit_give_key() -> void:
	start_dialogue("hermit_done", func():
		GameState.has_key = true
		GameState.cave_state = 3
		GameState.quest_changed.emit()
		_show_key_fx())

## Визуальный эффект получения ключа (key.png может отсутствовать — ассет рисует сосед).
func _show_key_fx() -> void:
	if not ResourceLoader.exists("res://assets/key.png"):
		push_warning("Нет ассета: assets/key.png — эффект ключа пропущен")
		return
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/key.png")
	spr.global_position = player.global_position + Vector2(0, -20)
	add_child(spr)
	var t := get_tree().create_tween()
	t.tween_property(spr, "position:y", spr.position.y - 14.0, 0.8)
	t.parallel().tween_property(spr, "modulate:a", 0.0, 0.8)
	t.tween_callback(spr.queue_free)

func on_player_death() -> void:
	start_dialogue("death", func(): respawn_player())

func respawn_player() -> void:
	player.cancel_orders()
	if GameState.in_cave and dungeon_zone != null:
		player.global_position = CAVE_OFFSET + dungeon_zone.spawn_world_pos
	else:
		player.global_position = tile_to_world(spawn_tile)
	GameState.heal_full()

# --- объекты ---

class CaveStairs:
	extends Area2D
	## Лестница в пещеру в лесу: вход по E (стиль npc.gd).
	var world
	func setup(p_world: Node2D, tile: Vector2i) -> void:
		world = p_world
		position = world.tile_to_world(tile)
		if ResourceLoader.exists("res://assets/dungeon_tiles.png"):
			var spr := Sprite2D.new()
			var at := AtlasTexture.new()
			at.atlas = load("res://assets/dungeon_tiles.png")
			at.region = Rect2(5 * 16, 0, 16, 16)
			spr.texture = at
			add_child(spr)
		else:
			push_warning("Нет ассета: assets/dungeon_tiles.png — заглушка входа в пещеру")
			var ph := ColorRect.new()
			ph.color = Color(0.1, 0.09, 0.13)
			ph.size = Vector2(14, 14)
			ph.position = Vector2(-7, -5)
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(ph)
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(16, 16)
		cs.shape = sh
		add_child(cs)
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
	func get_hint() -> String:
		return "Спуститься в пещеру"
	func try_interact() -> void:
		world.enter_cave()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			world.near.erase(self)
