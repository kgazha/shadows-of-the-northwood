extends Node2D
## Пещера «Осквернение»: карта data/map_cave.json, тайлы assets/dungeon_tiles.png
## (регион index*16, 0, 16, 16), стены, отшельник, лестница выхода, запертая дверь,
## алтарный сундук и босс. Публичный API: setup(p_world) -> void.
## Вход/выход: world.enter_cave() / world.exit_cave() (меняют видимость зон).

const TILE := 16
const TEX_PATH := "res://assets/dungeon_tiles.png"
const CHAR_TO_TILE := {
	".": 0, ",": 1, "#": 2, "L": 3, "S": 5, "P": 6, "R": 7,
	"B": 8, "M": 9, "A": 10, "C": 11, "V": 15,
}
const BLOCKING := [2, 3, 6, 7, 10, 11, 15]

var world: Node2D
var map_rows: Array = []
var map_w := 0
var map_h := 0
var spawn_tile := Vector2i(13, 2)
var spawn_world_pos := Vector2.ZERO
var tilemap: TileMapLayer
var _door_shapes := {}  # Vector2i -> CollisionShape2D: форму двери убираем при открытии
var chest_tile := Vector2i(-1, -1)  # тайл алтарного сундука (для chest_big_open = 12)

func setup(p_world: Node2D) -> void:
	world = p_world
	if not FileAccess.file_exists("res://data/map_cave.json"):
		push_warning("Нет карты data/map_cave.json — пещера не построена")
		return
	var f := FileAccess.open("res://data/map_cave.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Повреждена карта data/map_cave.json — пещера не построена")
		return
	var m: Dictionary = parsed
	map_rows = m["grid"]
	map_h = map_rows.size()
	map_w = String(map_rows[0]).length()
	var sp: Array = m.get("spawn", [13, 2])
	spawn_tile = Vector2i(int(sp[0]), int(sp[1]))
	spawn_world_pos = tile_to_world(spawn_tile)
	var cht: Array = m.get("chest", [])
	if cht.size() == 2:
		chest_tile = Vector2i(int(cht[0]), int(cht[1]))  # до _build_tiles: нужен для тайла 12
	if ResourceLoader.exists(TEX_PATH):
		_build_tiles()
	else:
		push_warning("Нет ассета: assets/dungeon_tiles.png — пещера построена без тайлов")
	_build_walls()
	_spawn_entities(m)

func tile_to_world(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE + 2.0)

func _atlas(index: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load(TEX_PATH)
	at.region = Rect2(index * TILE, 0, TILE, TILE)
	return at

func _build_tiles() -> void:
	var ts := TileSet.new()
	var src := TileSetAtlasSource.new()
	src.texture = load(TEX_PATH)
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in 16:
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	tilemap = TileMapLayer.new()
	tilemap.tile_set = ts
	tilemap.z_index = -10
	add_child(tilemap)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var ch := row[x]
			if CHAR_TO_TILE.has(ch):
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(int(CHAR_TO_TILE[ch]), 0))
	# амулет уже взят — сундук рисуем открытым (dungeon_tiles.png, тайл 12)
	if chest_tile.x >= 0 and GameState.has_amulet:
		tilemap.set_cell(chest_tile, 0, Vector2i(12, 0))

## Сундук открыт: тайл 11 -> 12 (chest_big_open). Публичный API.
func open_chest() -> void:
	if chest_tile.x >= 0 and tilemap != null:
		tilemap.set_cell(chest_tile, 0, Vector2i(12, 0))

func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 2
	body.collision_mask = 0
	add_child(body)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var ch := row[x]
			if not CHAR_TO_TILE.has(ch):
				continue
			var idx := int(CHAR_TO_TILE[ch])
			if idx in BLOCKING:
				var cs := CollisionShape2D.new()
				var sh := RectangleShape2D.new()
				sh.size = Vector2(TILE, TILE)
				cs.shape = sh
				cs.position = Vector2(x * TILE + 8, y * TILE + 8)
				body.add_child(cs)
				if idx == 3:  # запертая дверь — снимем коллизию при открытии
					_door_shapes[Vector2i(x, y)] = cs

func unlock_door(t: Vector2i) -> void:
	if tilemap != null:
		tilemap.set_cell(t, 0, Vector2i(0, 0))  # открытая дверь = каменный пол
	if _door_shapes.has(t):
		_door_shapes[t].queue_free()
		_door_shapes.erase(t)

func _spawn_entities(m: Dictionary) -> void:
	var her: Array = m.get("hermit", [])
	if her.size() == 2:
		var hm := HermitNpc.new()
		add_child(hm)
		hm.setup(self, Vector2i(int(her[0]), int(her[1])))
	var st: Array = m.get("stairs_out", [spawn_tile.x, spawn_tile.y])
	if st.size() == 2:
		var xs := ExitStairs.new()
		add_child(xs)
		xs.setup(self, Vector2i(int(st[0]), int(st[1])))
	for d: Array in m.get("door", []):
		if d.size() == 2:
			var dr := CaveDoor.new()
			add_child(dr)
			dr.setup(self, Vector2i(int(d[0]), int(d[1])))
	var ch: Array = m.get("chest", [])
	if ch.size() == 2 and not GameState.has_amulet:
		var cc := CaveChest.new()
		add_child(cc)
		cc.setup(self, Vector2i(int(ch[0]), int(ch[1])))
	if not GameState.boss_defeated:
		var bs: Array = m.get("boss", [])
		if bs.size() == 2:
			var brute = load("res://scripts/brute.gd").new()
			add_child(brute)
			brute.setup(world, Vector2i(int(bs[0]), int(bs[1])))
		var tg: Array = m.get("boss_trigger", [])
		if tg.size() == 2:
			var tr := BossTrigger.new()
			add_child(tr)
			tr.setup(self, Vector2i(int(tg[0]), int(tg[1])))

# --- объекты пещеры (в стиле npc.gd / interactable.gd) ---

class HermitNpc:
	extends Area2D
	## Отшельник Геральд: спрайт npc_hermit.png, зона диалога.
	var zone
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile)
		if ResourceLoader.exists("res://assets/npc_hermit.png"):
			var spr := Sprite2D.new()
			spr.texture = load("res://assets/npc_hermit.png")
			add_child(spr)
		else:
			push_warning("Нет ассета: assets/npc_hermit.png — заглушка отшельника")
			var ph := ColorRect.new()
			ph.color = Color(0.55, 0.45, 0.3)
			ph.size = Vector2(12, 14)
			ph.position = Vector2(-6, -7)
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(ph)
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(14, 16)
		cs.shape = sh
		add_child(cs)
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
	func get_hint() -> String:
		return "Поговорить"
	func try_interact() -> void:
		zone.world.talk("hermit")
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class ExitStairs:
	extends Area2D
	## Лестница наружу: поднимает обратно в деревню.
	var zone
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile)
		if ResourceLoader.exists("res://assets/dungeon_tiles.png"):
			var spr := Sprite2D.new()
			spr.texture = zone._atlas(5)
			add_child(spr)
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = 14.0
		cs.shape = sh
		add_child(cs)
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
	func get_hint() -> String:
		return "Подняться в деревню"
	func try_interact() -> void:
		zone.world.exit_cave()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class CaveDoor:
	extends Area2D
	## Запертая дверь алтарного зала: открывается КЛЮЧОМ Геральда.
	var zone
	var tile := Vector2i.ZERO
	func setup(p_zone, t: Vector2i) -> void:
		zone = p_zone
		tile = t
		position = zone.tile_to_world(t)
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = 14.0
		cs.shape = sh
		add_child(cs)
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
	func get_hint() -> String:
		return "Открыть дверь"
	func try_interact() -> void:
		if not GameState.has_key:
			GameState.toast.emit("Нужен ключ Геральда")
			return
		zone.unlock_door(tile)
		GameState.toast.emit("Защёлкнул древний замок — дверь открыта")
		queue_free()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class CaveChest:
	extends Area2D
	## Алтарный сундук: внутри Амулет Леса (нужен ключ).
	var zone
	var used := false
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile)
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = 14.0
		cs.shape = sh
		add_child(cs)
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
	func get_hint() -> String:
		return "Открыть сундук"
	func try_interact() -> void:
		if used:
			return
		if not GameState.has_key:
			GameState.toast.emit("Нужен ключ Геральда")
			return
		used = true
		GameState.has_amulet = true
		GameState.recalc_max_hp()  # +4 к макс. HP входит в формулу класса
		GameState.heal(4)          # урон +1 — через производный damage (has_amulet)
		GameState.stats_changed.emit()
		GameState.quest_changed.emit()
		zone.open_chest()  # тайл 12: сундук остаётся открытым и после перезахода
		if zone.world.dialogues.has("treasure_done"):
			zone.world.start_dialogue("treasure_done")
		else:
			GameState.toast.emit("Амулет Леса! Макс. HP +4, урон +1")
			GameState.toast.emit("Отнеси амулет отшельнику Геральду")
		queue_free()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class BossTrigger:
	extends Area2D
	## Вход в алтарный зал: при первом появлении — диалог «boss_intro».
	var zone
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile)
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = 20.0
		cs.shape = sh
		add_child(cs)
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player") and not GameState.seen_boss_intro:
			GameState.seen_boss_intro = true
			zone.world.start_dialogue("boss_intro")
			queue_free()
