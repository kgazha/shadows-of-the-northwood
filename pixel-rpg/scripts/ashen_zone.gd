extends Node2D
## Зона «Пепелище»: выжженная древним пожаром роща на востоке леса.
## Карта — ProcGen-словарь из world._build_ashen (T5b): setup(p_world, p_map)
## принимает {grid, meta:{spawn, exit_portal, boss, chests, herbs, mobs{archers,
## wraiths, swarm}}}; байты grid — канон тайлов data/map_ashen.json (тот же
## алфавит ". , c a T K # P"). Пустой/битый dict -> fallback на JSON-эталон
## data/map_ashen.json (файл остаётся на диске документацией/эталонной картой).
## Тайлы assets/ashen_tiles.png (регион index*16,
## 0, 16, 16), стены, портал выхода, сундук награды, травы, моб-наполнение:
## 3 лучника, стая мглокрысов из 4, 4 тенеплёта и мини-босс «Ведьма Пепелища»
## (scripts/mob_boss2.gd) — состав эммитит генератор (ASHEN_MOBS), реестры/волны
## мобов — без изменений. Персист — GameState.flags: "ashen.boss" = "dead",
## "ashen.chest" = "taken" (cave_state/boss_defeated НЕ трогаем — у пещеры свой путь).
## Тинты мобов — через self_modulate: скрипты мобов перекрашивают modulate каждый
## кадр (вспышки урона), self_modulate перемножается с modulate и выживает.
## Публичный API: setup(p_world, p_map) -> void; вход/выход: world.enter_ashen()/exit_ashen().

const TILE := 16
const TEX_PATH := "res://assets/ashen_tiles.png"
const CHAR_TO_TILE := {
	".": 0, ",": 1, "c": 2, "a": 3,   # полы: зола / осыпь / трещины / арена
	"T": 4, "K": 5, "#": 6,           # блокировщики: дерево / пень / бревно
	"P": 7,                           # портал (проходим)
}
const BLOCKING := [4, 5, 6]
## Коллизии «мелких» блокировщиков: индекс -> [w, h, dx, dy] от центра клетки
## (приём world.BLOCK_SHAPES): ствол дерева/бревно занимают клетку почти целиком,
## а пень — только туловище, иначе вокруг пня вставала бы невидимая стена.
const ASHEN_BLOCK_SHAPES := {
	5: [10, 8, 0, 3],     # пень: тело пня, углы и верх клетки проходимы
}
## Тинты «пепельного» наполнения (атмосферная перекраска существующих листов).
const TINT_ARCHER := Color(0.74, 0.76, 0.88)   # пепельный лучник: холодная зола
const TINT_WRAITH := Color(1.0, 0.62, 0.45)    # угольный тенеплёт: тлеющий уголь
const TINT_RAT := Color(0.86, 0.74, 0.66)      # саженный мглокрыс

var world: Node2D
var map_rows: Array = []
var map_w := 0
var map_h := 0
var spawn_tile := Vector2i(5, 15)
var spawn_world_pos := Vector2.ZERO
var tilemap: TileMapLayer
var boss_tile := Vector2i(-1, -1)
var chest_tile := Vector2i(-1, -1)
# ссылки для маркера цели и QA-харнесса
var boss_node: Node2D
var chest_node: Node2D
var portal_node: Node2D

func setup(p_world: Node2D, p_map: Dictionary = {}) -> void:
	world = p_world
	var m: Dictionary = {}
	# основной путь (T5b): генераторный словарь world._build_ashen — {grid, meta}
	if typeof(p_map.get("grid", null)) == TYPE_ARRAY and not (p_map["grid"] as Array).is_empty() \
			and typeof(p_map.get("meta", null)) == TYPE_DICTIONARY:
		m = p_map
	else:
		# fallback: деревенский эталон data/map_ashen.json (файл намеренно на диске)
		push_warning("ProcGen-словарь Пепелища пуст/бит — откат на эталон data/map_ashen.json")
		if not FileAccess.file_exists("res://data/map_ashen.json"):
			push_warning("Нет карты data/map_ashen.json — Пепелище не построено")
			return
		var f := FileAccess.open("res://data/map_ashen.json", FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("Повреждена карта data/map_ashen.json — Пепелище не построено")
			return
		m = parsed
	map_rows = m["grid"]
	map_h = map_rows.size()
	map_w = String(map_rows[0]).length()
	var meta: Dictionary = m.get("meta", {})
	var sp: Array = meta.get("spawn", [5, 15])
	spawn_tile = Vector2i(int(sp[0]), int(sp[1]))
	spawn_world_pos = tile_to_world(spawn_tile)
	var bs: Array = meta.get("boss", [])
	if bs.size() == 2:
		boss_tile = Vector2i(int(bs[0]), int(bs[1]))
	var cht: Array = meta.get("chests", [])
	if cht.size() > 0 and (cht[0] as Array).size() == 2:
		chest_tile = Vector2i(int(cht[0][0]), int(cht[0][1]))
	if ResourceLoader.exists(TEX_PATH):
		_build_tiles()
	else:
		push_warning("Нет ассета: assets/ashen_tiles.png — Пепелище построено без тайлов")
	_build_walls()
	_spawn_entities(meta)

func tile_to_world(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE + 2.0)

## Проходимость клетки Пепелища для поиска пути. Порталы/сундуки/ведьма клетки
## не перекрывают (проходимый пол), персист читается при спавне узлов.
func cell_walkable(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.y >= map_h or t.x >= map_w:
		return false
	var row := String(map_rows[t.y])
	if t.x >= row.length():
		return false
	var ch := row[t.x]
	if not CHAR_TO_TILE.has(ch):
		return true
	return not (int(CHAR_TO_TILE[ch]) in BLOCKING)

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
	for i in 8:
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	tilemap = TileMapLayer.new()
	tilemap.tile_set = ts
	tilemap.z_index = -10
	# наземный тон Пепелища: холодная дымка только на землю (зоны-спрайты мобов
	# красятся individually) — атмосфера остаётся «лесной», не пещерной
	tilemap.self_modulate = Color(0.93, 0.94, 1.0)
	add_child(tilemap)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var ch := row[x]
			if CHAR_TO_TILE.has(ch):
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(int(CHAR_TO_TILE[ch]), 0))

## Коллизии блокировщиков — полная клетка 16x16 (приём dungeon_zone.gd).
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
			if int(CHAR_TO_TILE[ch]) in BLOCKING:
				var cs := CollisionShape2D.new()
				var sh := RectangleShape2D.new()
				if ASHEN_BLOCK_SHAPES.has(int(CHAR_TO_TILE[ch])):
					var s: Array = ASHEN_BLOCK_SHAPES[int(CHAR_TO_TILE[ch])]
					sh.size = Vector2(int(s[0]), int(s[1]))
					cs.position = Vector2(x * TILE + 8 + int(s[2]), y * TILE + 8 + int(s[3]))
				else:
					sh.size = Vector2(TILE, TILE)
					cs.position = Vector2(x * TILE + 8, y * TILE + 8)
				cs.shape = sh
				body.add_child(cs)

func _spawn_entities(meta: Dictionary) -> void:
	# портал выхода (E-взаимодействие, как лестница пещеры)
	var ep: Array = meta.get("exit_portal", [spawn_tile.x, spawn_tile.y])
	if ep.size() == 2:
		var p := AshenPortal.new()
		add_child(p)
		p.setup(self, Vector2i(int(ep[0]), int(ep[1])))
		portal_node = p
	# сундук награды — персист по флагу, без has_sword-побочного эффекта деревенского сундука
	if str(GameState.flags.get("ashen.chest", "")) != "taken" \
			and chest_tile.x >= 0:
		var c := AshenChest.new()
		add_child(c)
		c.setup(self, chest_tile)
		chest_node = c
	# травы — штатный interactable.gd (респаун 50 с, общий счётчик трав)
	var it_script := load("res://scripts/interactable.gd")
	for h: Array in meta.get("herbs", []):
		if h.size() == 2:
			var herb = it_script.new()
			add_child(herb)
			herb.setup(world, "herb", Vector2i(int(h[0]), int(h[1])))
	# наполнение: лучники, стая, тенеплёты (перекрашенные существующие листы)
	var archer_script := load("res://scripts/mob_archer.gd")
	var mobs: Dictionary = meta.get("mobs", {})
	for a: Array in mobs.get("archers", []):
		if a.size() == 2:
			var ar = archer_script.new()
			add_child(ar)
			ar.setup(world, Vector2i(int(a[0]), int(a[1])))
			ar.self_modulate = TINT_ARCHER
	var swarm: Array = mobs.get("swarm", [])
	if not swarm.is_empty():
		var rat_script := load("res://scripts/mob_swarmling.gd")
		for s: Array in swarm:
			if s.size() == 2:
				var rt = rat_script.new()
				rt.swarm_id = "ashen_brood"  # до setup: реестр стаи заводится в setup
				add_child(rt)
				rt.setup(world, Vector2i(int(s[0]), int(s[1])))
				rt.self_modulate = TINT_RAT
	var wraith_script := load("res://scripts/mob_wraith.gd")
	for wcoord: Array in mobs.get("wraiths", []):
		if wcoord.size() == 2:
			var wr = wraith_script.new()
			add_child(wr)
			wr.setup(world, Vector2i(int(wcoord[0]), int(wcoord[1])))
			wr.self_modulate = TINT_WRAITH
	# мини-босс: «Ведьма Пепелища» — живёт до смерти, персист по флагу
	if str(GameState.flags.get("ashen.boss", "")) != "dead" and boss_tile.x >= 0:
		var witch = load("res://scripts/mob_boss2.gd").new()
		add_child(witch)
		witch.setup(world, boss_tile)
		boss_node = witch

## Первая помощь страже/сундуку: свободная клетка рядом с центром (кольца 1..3).
func free_neighbours(center: Vector2i, want: int) -> Array:
	var out: Array = []
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(abs(dx), abs(dy)) != radius:
					continue
				var t := center + Vector2i(dx, dy)
				if cell_walkable(t):
					out.append(t)
					if out.size() >= want:
						return out
	return out

# --- объекты Пепелища (в стиле dungeon_zone.gd) ---

class AshenPortal:
	extends Area2D
	## Выжженная аршина наружу: выход обратно в деревню (по E).
	var zone
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile)
		if ResourceLoader.exists("res://assets/ashen_tiles.png"):
			var spr := Sprite2D.new()
			spr.texture = zone._atlas(7)
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
		return "Выйти в деревню"
	func try_interact() -> void:
		zone.world.exit_ashen()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class AshenChest:
	extends Area2D
	## Сундук награды Пепелища: золото + крепкое зелье (та же схема наград,
	## что у Loot.chest_reward), персист — GameState.flags["ashen.chest"].
	var zone
	var used := false
	var uid := ""  # канон-схема GameState D4 "chest@<area>:x,y" (interactable._uid)
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		uid = "chest@ashen:%d,%d" % [tile.x, tile.y]
		position = zone.tile_to_world(tile)
		if ResourceLoader.exists("res://assets/tiles.png"):
			var spr := Sprite2D.new()
			var at := AtlasTexture.new()
			at.atlas = load("res://assets/tiles.png")
			at.region = Rect2(10 * 16, 0, 16, 16)  # сундук — тайл 10, как в interactable.gd
			spr.texture = at
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
		return "Открыть сундук"
	func try_interact() -> void:
		if used or str(GameState.flags.get("ashen.chest", "")) == "taken":
			return
		used = true
		GameState.set_flag("ashen.chest", "taken")
		GameState.chest_mark_used(uid)  # «Клад» считается и этим сундуком (схема T2)
		Loot.chest_reward(GameState)
		Loot._give_item(GameState, "potion", 1)  # гарантированная награда-экипировка
		Achv.on_chest_opened()
		GameState.quest_changed.emit()          # автосейв: флаг осядет в сохранении
		queue_free()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)
