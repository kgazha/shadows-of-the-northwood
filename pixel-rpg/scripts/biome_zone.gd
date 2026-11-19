extends Node2D
## Зона-локация «Мира v1» (t3): одна из шести (снег/пустыня/степь/лес/замок/
## подземелье). Сетка — OpenWorld.loc_map(run_seed, zone). Пол — утверждённый
## биомный F1/F2 из world_floor_v1.png (лес — forest_floor_v1), скала периметра
## — runtime-тайл STONE (кодоген), пропы/выход-портал — world_props_v1.png.
## Вход: южная арка (сейв-точка зоны: respawn/return = spawn). Выход: портал
## PORTAL_<BIOME> у входа (E) -> карта мира. Сундук — один, персист по
## канон-схеме "chest@loc_<z>:x,y" (chests_used). Мобов спавнит world
## (его мобы — паттерн ashen); зона отдаёт meta.
## Публичный API: setup(p_world, p_map, p_belt); cell_walkable/map_w/map_h/
## spawn_world_pos/biome/belt/spawn_tile.

const TILE := 16
const OW := preload("res://scripts/open_world.gd")
const OW_PAL := preload("res://scripts/pixel_palette.gd")
const MANIFEST_PATH := "res://assets/world/world_regions.json"
const FLOOR_TEX := "res://assets/world/world_floor_v1.png"
const PROP_TEX := "res://assets/world/world_props_v1.png"
const FOREST_FLOOR := "res://assets/forest/forest_floor_v1.png"

## Биом -> пара слотов пола (world_regions.json) и семейство масс/декора.
const FLOOR_SLOTS := {
	"snow": ["SNOW_F1", "SNOW_F2"], "desert": ["DES_F1", "DES_F2"],
	"steppe": ["STP_F1", "STP_F2"], "castle": ["CAS_F1", "CAS_F2"],
	"dungeon": ["DUN_F1", "DUN_F2"],
}
const MASS_PROP := {"s": "SNOW_PINE", "d": "MESA", ".": "STEP_ROCK",
	"f": "PINE_T2", "c": "WALL_T", "u": "PILLAR_D"}
const DECO_PROP := {"i": "ICE_SPIKE", "S": "SKULL", "b": "BANNER", "r": "CRATE",
	"t": "TALLGRASS", "n": "FERN", "g": "FUNGUS"}

var world: Node2D
var biome := "snow"
var belt := 0
var map_rows: Array = []
var map_w := 0
var map_h := 0
var spawn_tile := Vector2i(21, 30)
var portal_out_tile := Vector2i(22, 31)
var chest_tile := Vector2i(-1, -1)
var mobs_meta: Array = []
var tilemap: TileMapLayer
var chest_node: Node2D
var portal_out_node: Node2D

var _slots := {}
var _props := {}
var _prop_tex: Texture2D
var _rock_tex: Texture2D

func setup(p_world: Node2D, p_map: Dictionary) -> void:
	world = p_world
	if p_map.is_empty() or not p_map.has("grid"):
		push_warning("BiomeZone: пустой словарь генератора — локация не построена")
		return
	var meta: Dictionary = p_map.get("meta", {})
	biome = String(meta.get("zone", "snow"))
	belt = int(meta.get("belt", 0))
	map_rows = p_map["grid"]
	map_h = map_rows.size()
	map_w = String(map_rows[0]).length()
	var sp: Array = meta.get("spawn", [21, 30])
	spawn_tile = Vector2i(int(sp[0]), int(sp[1]))
	var po: Array = meta.get("portal_out", [22, map_h - 3])
	portal_out_tile = Vector2i(int(po[0]), int(po[1]))
	var ch: Array = meta.get("chest", [-1, -1])
	chest_tile = Vector2i(int(ch[0]), int(ch[1]))
	mobs_meta = meta.get("mobs", [])
	_load_manifest()
	_build_tiles()
	_build_walls()
	_build_props()
	_spawn_chest()
	_spawn_exit()
	_spawn_bestiary()

func _load_manifest() -> void:
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_slots = parsed.get("floor_slots", {})
			_props = parsed.get("props", {})
	if ResourceLoader.exists(PROP_TEX):
		_prop_tex = load(PROP_TEX)
	_rock_tex = _build_rock_texture()

static func _build_rock_texture() -> Texture2D:
	# та же runtime-скала, что у карты мира (идентичный код — детерминирован)
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
	t.resource_name = "BiomeRockV1"
	return t

func tile_to_world(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE + 2.0)

func spawn_world_pos() -> Vector2:
	return tile_to_world(spawn_tile)

func cell_walkable(t: Vector2i) -> bool:
	return OW.walkable(map_rows, t.x, t.y)

func _floor_index(x: int, y: int) -> int:
	var pair: Array = FLOOR_SLOTS.get(biome, ["STP_F1", "STP_F2"])
	var s: String = String(pair[0])
	if (x + y) % 2 == 1:
		s = String(pair[1])
	return int(_slots.get(s, 0))

func _build_tiles() -> void:
	var forest_ok := biome == "forest" and ResourceLoader.exists(FOREST_FLOOR)
	var ts := TileSet.new()
	var floor_ok := ResourceLoader.exists(FLOOR_TEX)
	var src := TileSetAtlasSource.new()
	src.texture = load(FLOOR_TEX) if floor_ok else _rock_tex
	src.texture_region_size = Vector2i(TILE, TILE)
	# все 22 слота стрипа world_floor_v1 (floor_slots 0..21) — см. worldmap_zone
	if floor_ok:
		for i in 22:
			src.create_tile(Vector2i(i, 0))
	else:
		src.create_tile(Vector2i(0, 0))
	ts.add_source(src, 0)
	var rock_src := TileSetAtlasSource.new()
	rock_src.texture = _rock_tex
	rock_src.texture_region_size = Vector2i(TILE, TILE)
	rock_src.create_tile(Vector2i(0, 0))
	ts.add_source(rock_src, 1)
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
			var c := String(row[x])
			match c:
				"#":
					tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
				"-":
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(int(_slots.get("ROAD_F2" if (x + y) % 2 == 1 else "ROAD_F1", 0)), 0))
				_:
					if forest_ok:
						tilemap.set_cell(Vector2i(x, y), 2, Vector2i((x + y) % 2, 0))
					else:
						tilemap.set_cell(Vector2i(x, y), 0, Vector2i(_floor_index(x, y), 0))

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

func _prop_sprite(pname: String) -> Sprite2D:
	if _props.has(pname):
		var r: Dictionary = _props[pname]
		var at := AtlasTexture.new()
		at.atlas = _prop_tex
		at.region = Rect2(int(r["x"]), int(r["y"]), int(r["w"]), int(r["h"]))
		var spr := Sprite2D.new()
		spr.texture = at
		return spr
	if ForestArt.REGIONS.has(pname) and ResourceLoader.exists(ForestArt.ATLAS_PATH):
		var spr2 := Sprite2D.new()
		spr2.texture = ForestArt._region(ForestArt.load_atlas(), pname)
		return spr2
	return null

func _prop_h(pname: String) -> int:
	if _props.has(pname):
		return int((_props[pname] as Dictionary).get("h", 16))
	if ForestArt.REGIONS.has(pname):
		return int(ForestArt.REGIONS[pname].size.y)
	return 16

func _build_props() -> void:
	if _prop_tex == null:
		return
	var layer := Node2D.new()
	layer.name = "BiomePropV1"
	add_child(layer)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var c := String(row[x])
			var pname := ""
			if c == "M":
				pname = String(MASS_PROP.get(OW.loc_ground(biome), "STEP_ROCK"))
			elif DECO_PROP.has(c):
				pname = String(DECO_PROP[c])
			if pname == "":
				continue
			var spr := _prop_sprite(pname)
			if spr == null:
				continue
			var foot_y := float((y + 1) * TILE)
			spr.position = Vector2(float(x * TILE) + 8.0, foot_y - _prop_h(pname) / 2.0)
			spr.z_as_relative = false
			spr.z_index = int(round(fposmod(foot_y, float(world.YS_CYCLE))))
			layer.add_child(spr)

func _spawn_exit() -> void:
	var p := BiomeExit.new()
	add_child(p)
	p.setup(self, portal_out_tile)
	portal_out_node = p

## Наполнение локации (контракт «Мир v1»): семейства мобов — существующие
## (те же скрипты, что в лесу/пещере/Пепелище), сложность — ТОЛЬКО поясной
## множитель HP/урона/золота (скорость/ИИ/паттерны не трогаем), палитра —
## перекрас скином биома (c22-метод). Спавн живёт ЗДЕСЬ, а не в world.gd:
## паттерн ashen_zone (зона спавнит своих мобов в своём модуле; c21-скан
## world/dungeon остаётся byte-чистым). Таблица — OpenWorld.BESTIARY.
const MOB_SCRIPTS := {
	"slime": "res://scripts/slime.gd",
	"brute": "res://scripts/brute.gd",
	"archer": "res://scripts/mob_archer.gd",
	"swarmling": "res://scripts/mob_swarmling.gd",
	"wraith": "res://scripts/mob_wraith.gd",
}

func _spawn_bestiary() -> void:
	var mult := OW.belt_mult(belt)
	for ent in mobs_meta:
		var fam := String((ent as Array)[0])
		if not MOB_SCRIPTS.has(fam):
			continue
		var m = load(MOB_SCRIPTS[fam]).new()
		if fam == "brute":
			m.boss = false
			m.tier = OW.brute_tier(belt)
			m.belt_loot = "brute_t%d@b%d" % [m.tier, belt]
		else:
			m.loot_kind = "%s@b%d" % [fam, belt]
		add_child(m)
		m.setup(world, Vector2i(int((ent as Array)[1]), int((ent as Array)[2])))
		# поясной множитель — ПОСЛЕ setup() (паттерн _apply_ng_stats)
		if "hp" in m:
			m.hp = maxi(1, int(round(int(m.hp) * mult)))
		if "max_hp" in m:
			m.max_hp = maxi(1, int(round(int(m.max_hp) * mult)))
		if "dmg" in m:
			m.dmg = maxi(1, int(round(int(m.dmg) * mult)))
		if "dmg_mult" in m:
			m.dmg_mult = mult
		OW.apply_biome_skin(m, biome)

func _spawn_chest() -> void:
	if chest_tile.x < 0:
		return
	var c := BiomeChest.new()
	add_child(c)
	c.setup(self, chest_tile)
	chest_node = c

class BiomeExit:
	extends Area2D
	## Портал обратного хода (E): локация -> карта мира.
	var zone
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile)
		var pname: String = "PORTAL_" + String(zone.biome).to_upper()
		var spr: Sprite2D = zone._prop_sprite(pname)
		if spr != null:
			spr.position = Vector2(0, 6 - zone._prop_h(pname) / 2.0)
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
		return "К карте мира"
	func try_interact() -> void:
		zone.world.exit_location()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class BiomeChest:
	extends Area2D
	## Сундук локации: стандартная награда Loot.chest_reward (шапка пояса —
	## золото масштабируется множителем зоны при выдаче). Персист — канон-схема
	## GameState D4 "chest@loc_<z>:x,y" (chests_used), фолбэк-флаг как у Пепелища.
	var zone
	var used := false
	var uid := ""
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		uid = "chest@loc_%s:%d,%d" % [zone.biome, tile.x, tile.y]
		position = zone.tile_to_world(tile)
		used = GameState.chests_used.has(uid)
		var spr: Sprite2D = null
		if ResourceLoader.exists(CaveArt.ATLAS_PATH) and CaveArt.REGIONS.has("CHEST"):
			spr = Sprite2D.new()
			spr.texture = CaveArt.region_texture("CHEST" if not used else "CHEST_OPEN")
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
		if used:
			return ""
		return "Открыть сундук"
	func try_interact() -> void:
		if used:
			return
		used = true
		GameState.chest_mark_used(uid)
		Loot.chest_reward(GameState)
		Achv.on_chest_opened()
		GameState.quest_changed.emit()  # автосейв: сундук осядет в сохранении
		if ResourceLoader.exists(CaveArt.ATLAS_PATH) and CaveArt.REGIONS.has("CHEST_OPEN"):
			for n in get_children():
				var s := n as Sprite2D
				if s != null:
					s.texture = CaveArt.region_texture("CHEST_OPEN")
	func _on_enter(b: Node) -> void:
		if used:
			return
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)
