extends Node2D
## Зона «Карта мира» (t3 «Мир v1»): открытая сетка 96×60 за северной аркой
## деревни. Карта — словарь OpenWorld.worldmap_map(run_seed): {grid, meta}.
## Тайлы — утверждённый bake assets/world/world_floor_v1.png (слоты из
## world_regions.json), скала кольца — runtime-тайл из RAMPS STONE (кодоген,
## дельта палитры = пусто), пропы/порталы/арка — world_props_v1.png по
## регионам манифеста. Шесть порталов (E) ведут в локации; южные ворота
## (проход x=47..48, y=57..59) — арка back to village (E на клетке 'a').
## Публичный API: setup(p_world, p_map); cell_walkable/map_w/map_h/
## spawn_world_pos/portals_dict.

const TILE := 16
const MANIFEST_PATH := "res://assets/world/world_regions.json"
const FLOOR_TEX := "res://assets/world/world_floor_v1.png"
const PROP_TEX := "res://assets/world/world_props_v1.png"
const FOREST_FLOOR := "res://assets/forest/forest_floor_v1.png"

const OW := preload("res://scripts/open_world.gd")

var world: Node2D
var map_rows: Array = []
var map_w := 0
var map_h := 0
var spawn_tile := Vector2i(47, 56)
var arch_tile := Vector2i(48, 58)
var portals: Dictionary = {}          # zone -> Vector2i
var tilemap: TileMapLayer
var portal_nodes := {}                # zone -> Area2D (для QA)
var arch_node: Node2D

var _slots := {}                      # имя тайла -> index
var _props := {}                      # имя пропа -> регион-dict
var _prop_tex: Texture2D
var _rock_tex: Texture2D              # runtime-скала (STONE-рампа)

func setup(p_world: Node2D, p_map: Dictionary) -> void:
	world = p_world
	if not p_map.has("grid") or (p_map["grid"] as Array).is_empty():
		push_warning("WorldMap: пустой словарь генератора — зона не построена")
		return
	map_rows = p_map["grid"]
	map_h = map_rows.size()
	map_w = String(map_rows[0]).length()
	var meta: Dictionary = p_map.get("meta", {})
	var sp: Array = meta.get("spawn", [47, 56])
	spawn_tile = Vector2i(int(sp[0]), int(sp[1]))
	var ar: Array = meta.get("arch", [48, 58])
	arch_tile = Vector2i(int(ar[0]), int(ar[1]))
	_load_manifest()
	_build_tiles()
	_build_walls()
	_build_props()
	_spawn_interactors()

func _load_manifest() -> void:
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_slots = parsed.get("floor_slots", {})
			_props = parsed.get("props", {})
	if ResourceLoader.exists(PROP_TEX):
		_prop_tex = load(PROP_TEX)
	_rock_tex = _build_rock_texture()

## Runtime-скала кольца: STONE-рампа (MID кирпич, OUTLINE раствор, LIGHT фаска
## СЗ) — кодоген в палитре, 16-периодных швов не требует (массив глухой).
func _build_rock_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var mid := OW_PAL.c("STONE", OW_PAL.T_MID)
	var dark := OW_PAL.c("STONE", OW_PAL.T_DARK)
	var lite := OW_PAL.c("STONE", OW_PAL.T_LIGHT)
	var outl := OW_PAL.c("STONE", OW_PAL.T_OUTLINE)
	for y in 16:
		for x in 16:
			var col := mid
			if y % 4 == 3 or (x + (int(y / 4) % 2) * 4) % 8 == 7:
				col = outl
			elif y % 4 == 0:
				col = lite
			elif y % 4 == 2 and (x + int(y / 4) * 3) % 5 == 0:
				col = dark
			img.set_pixel(x, y, col)
	var t := ImageTexture.create_from_image(img)
	t.resource_name = "WorldmapRockV1"
	return t

func spawn_world_pos() -> Vector2:
	return tile_to_world(spawn_tile)

func tile_to_world(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE + 2.0)

func cell_walkable(t: Vector2i) -> bool:
	return OW.walkable(map_rows, t.x, t.y)

func portals_dict() -> Dictionary:
	return portals

# ---------------------------------------------------------------- тайлы

func _floor_index(slot_a: String, slot_b: String, x: int, y: int) -> int:
	var s: String = slot_a if ((x + y) % 2 == 0 or not _slots.has(slot_b)) else slot_b
	return int(_slots.get(s, _slots.get(slot_a, 0)))

func _build_tiles() -> void:
	var ts := TileSet.new()
	var floor_ok := ResourceLoader.exists(FLOOR_TEX)
	var src := TileSetAtlasSource.new()
	src.texture = load(FLOOR_TEX) if floor_ok else _rock_tex
	src.texture_region_size = Vector2i(TILE, TILE)
	# все 22 слота стрипа (world_regions.json floor_slots 0..21) — иначе set_cell
	# на несозданную координату атласа пустит ошибку и оставит дыру;
	if floor_ok:
		for i in 22:
			src.create_tile(Vector2i(i, 0))
	else:
		src.create_tile(Vector2i(0, 0))
	ts.add_source(src, 0)
	# второй источник — скала runtime (свои координаты тайлов)
	var rock_src := TileSetAtlasSource.new()
	rock_src.texture = _rock_tex
	rock_src.texture_region_size = Vector2i(TILE, TILE)
	rock_src.create_tile(Vector2i(0, 0))
	ts.add_source(rock_src, 1)
	# третий — утверждённый лесной пол (FFLR/FFLR2 = слоты 0/1), если атлас на месте
	var forest_ok := ResourceLoader.exists(FOREST_FLOOR)
	if forest_ok:
		var fsrc := TileSetAtlasSource.new()
		fsrc.texture = load(FOREST_FLOOR)
		fsrc.texture_region_size = Vector2i(TILE, TILE)
		fsrc.create_tile(Vector2i(0, 0))
		fsrc.create_tile(Vector2i(1, 0))
		ts.add_source(fsrc, 2)
	tilemap = TileMapLayer.new()
	tilemap.tile_set = ts
	tilemap.z_index = -10
	add_child(tilemap)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var ch := String(row[x]) if x < row.length() else "."
			match ch:
				"#":
					tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
				"s":
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_floor_index("SNOW_F1", "SNOW_F2", x, y), 0))
				"d":
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_floor_index("DES_F1", "DES_F2", x, y), 0))
				"c":
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_floor_index("CAS_F1", "CAS_F2", x, y), 0))
				"u":
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_floor_index("DUN_F1", "DUN_F2", x, y), 0))
				"-":
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_floor_index("ROAD_F1", "ROAD_F2", x, y), 0))
				"f":
					if forest_ok:
						tilemap.set_cell(Vector2i(x, y), 2, Vector2i((x + y) % 2, 0))
					else:
						tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_floor_index("STP_F1", "STP_F2", x, y), 0))
				_:
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_floor_index("STP_F1", "STP_F2", x, y), 0))

func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 2
	body.collision_mask = 0
	add_child(body)
	# слитые прямоугольники (OW.solid_rects) вместо клетка-на-клетку:
	# то же покрытие физики, на порядок меньше форм (приём деревни)
	for r in OW.solid_rects(map_rows):
		var rc: Vector4i = r
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(rc.z * TILE, rc.w * TILE)
		cs.position = Vector2(rc.x * TILE + rc.z * TILE / 2.0, rc.y * TILE + rc.w * TILE / 2.0)
		cs.shape = sh
		body.add_child(cs)

func _build_props() -> void:
	if _prop_tex == null:
		push_warning("WorldMap: нет world_props_v1.png — пропы не построены")
		return
	var layer := Node2D.new()
	layer.name = "WorldMapPropV1"
	add_child(layer)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var ch := String(row[x])
			var pname := _prop_for(ch, x, y)
			if pname == "":
				continue
			var spr := _prop_sprite(pname)
			if spr == null:
				continue
			var foot_y := float((y + 1) * TILE)
			var off := Vector2(0, -_prop_h(pname) / 2.0)
			spr.position = Vector2(float(x * TILE) + TILE / 2.0, foot_y) + off
			spr.z_as_relative = false
			spr.z_index = int(round(fposmod(foot_y, float(world.YS_CYCLE))))
			layer.add_child(spr)

## Буква сетки -> проп. Массы и декор — по таблице биомов; 'p'/'a' — интеракторы.
func _prop_for(ch: String, x: int, _y: int) -> String:
	match ch:
		"M":
			# масса биома: поле под массой даёт семейство (снег/пустыня/скала/степь/лес/подземелье)
			var g := _ground_under(x, _y)
			match g:
				"s": return "SNOW_PINE"
				"d": return "MESA"
				"c": return "WALL_T"
				"u": return "PILLAR_D"
				"f": return "PINE_T2"
				_: return "STEP_ROCK"
		"W": return "WALL_T"
		"C": return "MESA"
		"i": return "ICE_SPIKE"
		"S": return "SKULL"
		"b": return "BANNER"
		"r": return "CRATE"
		"t": return "TALLGRASS"
		"n": return "FERN"
		"g": return "FUNGUS"
	return ""

## Масса лежит на поле; поле определяем по соседу (масса перезаписала букву).
func _ground_under(x: int, y: int) -> String:
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, -1)]:
		var t: Vector2i = Vector2i(x, y) + (d as Vector2i)
		if t.x >= 0 and t.y >= 0 and t.y < map_h and t.x < String(map_rows[t.y]).length():
			var ch := String(map_rows[t.y][t.x])
			if ch in "sdcuf.":
				return ch
	return "."

func _prop_sprite(pname: String) -> Sprite2D:
	if _props.has(pname):
		var r: Dictionary = _props[pname]
		var at := AtlasTexture.new()
		at.atlas = _prop_tex
		at.region = Rect2(int(r["x"]), int(r["y"]), int(r["w"]), int(r["h"]))
		var spr := Sprite2D.new()
		spr.texture = at
		return spr
	# лесные пропы (PINE_T2/FERN) живут в утверждённом лесном атласе
	if ForestArt.REGIONS.has(pname) and ResourceLoader.exists(ForestArt.ATLAS_PATH):
		var spr2 := Sprite2D.new()
		spr2.texture = ForestArt._region(ForestArt.load_atlas(), pname)
		return spr2
	return null

## Высота пропа (для стопного якоря) — из манифеста или лесных регионов.
func _prop_h(pname: String) -> int:
	if _props.has(pname):
		return int((_props[pname] as Dictionary).get("h", 16))
	if ForestArt.REGIONS.has(pname):
		return int(ForestArt.REGIONS[pname].size.y)
	return 16

# ---------------------------------------------------------------- интеракторы

func _spawn_interactors() -> void:
	for z in OW.PORTAL_CELLS:
		var c: Vector2i = OW.PORTAL_CELLS[z]
		portals[z] = c
		var p := WorldPortal.new()
		add_child(p)
		p.setup(self, c, String(z))
		portal_nodes[z] = p
	var a := WorldArchBack.new()
	add_child(a)
	a.setup(self, arch_tile)
	arch_node = a

const OW_PAL := preload("res://scripts/pixel_palette.gd")

class WorldPortal:
	extends Area2D
	## Портал-вход локацию (E): переход штатный, как пещера/Пепелище.
	var zone
	var biome := ""
	func setup(p_zone, tile: Vector2i, p_biome: String) -> void:
		zone = p_zone
		biome = p_biome
		position = zone.tile_to_world(tile)
		var spr: Sprite2D = zone._prop_sprite("PORTAL_" + biome.to_upper())
		if spr != null:
			spr.position = Vector2(0, 6 - zone._prop_h("PORTAL_" + biome.to_upper()) / 2.0)
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
		return String(OW.ZONE_NAMES.get(biome, "Локация")) + " — войти"
	func try_interact() -> void:
		zone.world.enter_location(biome)
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class WorldArchBack:
	extends Area2D
	## Северная арка на карте мира: обратный ход в деревню (E).
	var zone
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile) + Vector2(8, 0)  # центр створа ворот x=47/48
		var spr: Sprite2D = zone._prop_sprite("ARCH_NORTH")
		if spr != null:
			spr.position = Vector2(0, 6 - zone._prop_h("ARCH_NORTH") / 2.0)
			add_child(spr)
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(32, 16)
		cs.shape = sh
		add_child(cs)
		collision_layer = 0
		collision_mask = 1
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
	func get_hint() -> String:
		return "Вернуться в деревню"
	func try_interact() -> void:
		zone.world.exit_worldmap()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)
