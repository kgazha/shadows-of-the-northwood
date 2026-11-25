extends Node2D
## t19 «Глубина v2 §2а» (25.11): ВНУТРЕННЯЯ сцена микро-подземелья.
## Сетка — mini_dungeon.generate(run_seed, biome) (чистый генератор, пины
## qa_pg PG12). Тайлсет — тайлсет биома (лес: forest_floor_v1) + runtime-скала
## BiomeZone (тот же кодоген), ноль растровых файлов (закон ART). Вход/выход —
## «ход» в локации и MiniReturn на том же месте внутри (паттерн деревня-пещера,
## лёгкий вес: без пропов/воды/мхов — граница новой сцены).
## Население: мини-босс (усиленная существующая шкура, TIERS #11 BALANCE +
## множитель мини-босса — новых артов не заводим) + сундук с гарантированным
## реликтом t17 (Loot.quest_relic, канон-uid "chest@mini_<z>:x,y" — персист
## D4 chests_used, один раз за круг). Смерть внутри = обычный конец забега.
## Публичный API как у BiomeZone: setup/cell_walkable/map_w/map_h/
## spawn_world_pos/biome/belt/spawn_tile.

const OW := preload("res://scripts/open_world.gd")
const MD := preload("res://scripts/mini_dungeon.gd")
const BZ := preload("res://scripts/biome_zone.gd")

const TILE := 16
const FOREST_FLOOR := "res://assets/forest/forest_floor_v1.png"

## Мини-босс (BALANCE §«Микро-подземелья», t19): HP/урон яруса по поясу
## (канон #11 1+0,25·b — применяется сначала, паттерн _spawn_bestiary),
## поверх — множитель мини-босса: HP ×2,5, урон ×1,5 (минимум 2), XP ×3.
## Скорость/ИИ/паттерны не трогаем (контракт «Мир v1» о сложностных вилках).
const MINI_HP_MULT := 2.5
const MINI_DMG_MULT := 1.5
const MINI_XP_MULT := 3
const MINI_LEASH := 88.0   # сторожит дальнюю комнату, через весь ход не чует

## t20 (25.11): ростер мини-боссов — REMAP существующих шкур (§2; обличья
## из §4 — лист «Бестиарий v2» за t21, замена кожи без смены формулы):
## степь — застрельщик (лучник, держит дистанцию), пустыня — песчаный червь
## (рой-плоть), снег — шептун (призрак), подземелье — скелет-рудокоп (§2 —
## покойницкая шкура wraith), замок — краденый рыцарь (колосс-стиль = брут),
## лес — корневой засадчик (брут, t19-плейсхолдер обличья).
const BOSS_FAM := {"forest": "brute", "steppe": "archer", "desert": "swarmling",
		"snow": "wraith", "castle": "brute", "dungeon": "wraith"}
const FAM_SCRIPTS := {"brute": "res://scripts/brute.gd",
		"archer": "res://scripts/mob_archer.gd",
		"swarmling": "res://scripts/mob_swarmling.gd",
		"wraith": "res://scripts/mob_wraith.gd"}

## Флейвор-таблицы (т20): ноль логики, только текст и палитра (рампы
## закрытого PixelPalette — закон ART). HINT/RIM — в mini_dungeon (их читают
## и inner-классы, и world); тосты перехода — здесь, входят статиками MDZ.
const ENTER_TOAST := {
	"forest": "Ход уходит в корни. Внизу дышит что-то большое.",
	"steppe": "Ход уходит в сухие травы. Внизу пахнет полынью и пылью.",
	"desert": "Песок сыплется вниз. Внизу гудит сухожилиями.",
	"snow": "Снег смыкается над головой. Внизу шепчут.",
	"castle": "Каменные ступени в темноту. Внизу звенит железо.",
	"dungeon": "Сырые ступени вниз. Внизу скребут по камню.",
}
const CLOSE_TOAST := {
	"forest": "Хрип стих. Корни затихли — ход закрыт.",
	"steppe": "Свист тетивы оборвался. Ход затих.",
	"desert": "Песок осел. Гул стих — ход закрыт.",
	"snow": "Шёпот оборвался. Снег в ходу замолчал.",
	"castle": "Железо звякнуло в последний раз. Ход закрыт.",
	"dungeon": "Скрежет смолк. Под землёй пусто.",
}

static func enter_toast(b: String) -> String:
	return String(ENTER_TOAST.get(b, ENTER_TOAST["forest"]))

static func close_toast(b: String) -> String:
	return String(CLOSE_TOAST.get(b, CLOSE_TOAST["forest"]))

# Геттер для inner-класса выхода (его скоуп внешних const не видит).
func close_line() -> String:
	return String(CLOSE_TOAST.get(biome, CLOSE_TOAST["forest"]))

## Пулы реликтов сундука — ЗЕРКАЛО ярусных пулов цепочки t18 (тот же вкус
## награды: «поясная» вещь, которая точно надеть можно).
const RELIC_POOLS := {
	"t0": ["leather", "chain", "shortsword", "staff_apprentice", "bow_hunter"],
	"t1": ["leather", "chain", "boarhide", "sword", "nordsword", "staff_oak",
			"bow_heavy", "shield_iron"],
	"t2": ["chain", "boarhide", "nordsword", "fangblade", "rune_blade",
			"staff_oak", "staff_rune", "bow_heavy", "shield_raven"],
}

var world: Node2D
var biome := "forest"
var belt := 0
var map_rows: Array = []
var map_w := 0
var map_h := 0
var spawn_tile := Vector2i(20, 18)
var chest_tile := Vector2i(-1, -1)
var boss_tile := Vector2i(-1, -1)
var tilemap: TileMapLayer
var chest_node: Node2D
var boss_node: Node2D
var exit_node: Node2D

static func relic_pool_for(belt_: int) -> Array:
	return RELIC_POOLS["t2"] if belt_ >= 4 else (RELIC_POOLS["t1"] if belt_ >= 2 else RELIC_POOLS["t0"])

func setup(p_world: Node2D, p_map: Dictionary) -> void:
	world = p_world
	if p_map.is_empty() or not p_map.has("grid"):
		push_warning("MiniZone: пустой словарь генератора — ход не построен")
		return
	var meta: Dictionary = p_map.get("meta", {})
	biome = String(meta.get("biome", "forest"))
	belt = int(OW.zone_belt(biome))
	map_rows = p_map["grid"]
	map_h = map_rows.size()
	map_w = String(map_rows[0]).length()
	var sp: Array = meta.get("spawn", [20, 18])
	spawn_tile = Vector2i(int(sp[0]), int(sp[1]))
	var ch: Array = meta.get("chest", [-1, -1])
	chest_tile = Vector2i(int(ch[0]), int(ch[1]))
	var bo: Array = meta.get("boss", [-1, -1])
	boss_tile = Vector2i(int(bo[0]), int(bo[1]))
	_build_tiles()
	_build_walls()
	_spawn_exit()
	_spawn_chest()
	_spawn_boss()

func tile_to_world(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE + 2.0)

func spawn_world_pos() -> Vector2:
	return tile_to_world(spawn_tile)

func cell_walkable(t: Vector2i) -> bool:
	return OW.walkable(map_rows, t.x, t.y)

# --- графика: пол биома + скала BiomeZone (тот же runtime-кодоген) -----------

func _build_tiles() -> void:
	var ts := TileSet.new()
	var rock_tex: Texture2D = BZ._build_rock_texture()
	var rock_src := TileSetAtlasSource.new()
	rock_src.texture = rock_tex
	rock_src.texture_region_size = Vector2i(TILE, TILE)
	rock_src.create_tile(Vector2i(0, 0))
	ts.add_source(rock_src, 0)
	# t20: пол — тайлсет биома (лес — forest_floor_v1 два кадра, прочие —
	# пара слотов world_floor_v1 по индексам .manifest, паттерн BiomeZone).
	var slots := _floor_pair()
	var strip_ok := not slots.is_empty()
	if strip_ok:
		var fsrc := TileSetAtlasSource.new()
		fsrc.texture = load(FOREST_FLOOR if biome == "forest" else BZ.FLOOR_TEX)
		fsrc.texture_region_size = Vector2i(TILE, TILE)
		for sxi in slots:
			fsrc.create_tile(Vector2i(int(sxi), 0))
		ts.add_source(fsrc, 1)
	tilemap = TileMapLayer.new()
	tilemap.tile_set = ts
	tilemap.z_index = -10
	add_child(tilemap)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			if String(row[x]) == "#":
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
			elif strip_ok:
				tilemap.set_cell(Vector2i(x, y), 1, Vector2i(int(slots[(x + y) % 2]), 0))
			else:
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))

## Пара atlas-X слотов пола: лес — свои 0/1; прочие — FLOOR_SLOTS-имена
## через floor_slots манифеста (тот же json, что у BiomeZone; статик-кэш).
static var _slot_cache := {}
func _floor_pair() -> Array:
	if biome == "forest":
		return [0, 1] if ResourceLoader.exists(FOREST_FLOOR) else []
	if not ResourceLoader.exists(BZ.FLOOR_TEX) or not BZ.FLOOR_SLOTS.has(biome):
		return []
	if _slot_cache.is_empty():
		if FileAccess.file_exists(BZ.MANIFEST_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BZ.MANIFEST_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_slot_cache = parsed.get("floor_slots", {})
	var pair: Array = BZ.FLOOR_SLOTS[biome]
	return [int(_slot_cache.get(String(pair[0]), 0)), int(_slot_cache.get(String(pair[1]), 1))]

func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 2
	body.collision_mask = 0
	add_child(body)
	for r in OW.solid_rects(map_rows):
		var rc: Vector4i = r
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(rc.z * TILE, rc.w * TILE)
		cs.position = Vector2(rc.x * TILE + rc.z * TILE / 2.0, rc.y * TILE + rc.w * TILE / 2.0)
		cs.shape = sh
		body.add_child(cs)

# --- содержимое ----------------------------------------------------------------

func _spawn_exit() -> void:
	var e := MiniReturn.new()
	add_child(e)
	e.setup(self, spawn_tile)
	exit_node = e

func _spawn_chest() -> void:
	if chest_tile.x < 0:
		return
	var c := MiniChest.new()
	add_child(c)
	c.setup(self, chest_tile)
	chest_node = c

## Мини-босс: remap существующей шкуры (BOSS_FAM), ярус/пояс — каноном
## (_spawn_bestiary-порядок: сначала базовые статы, множители ПОСЛЕ).
## Поля семей разные: у брута dmg/kill_xp/tier/leash свои поля, у
## лучника/червя/шептуна урон = конста × dmg_mult (паттерн зоны), XP —
## var kill_xp (t20-рефакт мобов, значение по умолчанию = прежняя конста).
## Лут — строка "<fam>@b<N>" (наследие brute_t1 в таблице — не наша дыра,
## базовая строка семейства парсится механизмом суффикса).
func _spawn_boss() -> void:
	if boss_tile.x < 0:
		return
	var fam := String(BOSS_FAM.get(biome, "brute"))
	var m = load(FAM_SCRIPTS[fam]).new()
	if "boss" in m:
		m.boss = false
	if "tier" in m:
		m.tier = OW.brute_tier(belt)
	var mult := OW.belt_mult(belt)
	if "belt_loot" in m:
		m.belt_loot = "brute@b%d" % belt
	elif "loot_kind" in m:
		m.loot_kind = "%s@b%d" % [fam, belt]
	add_child(m)
	m.setup(world, boss_tile)
	m.hp = maxi(1, int(round(int(round(float(m.hp) * mult)) * MINI_HP_MULT)))
	if "max_hp" in m:
		m.max_hp = m.hp
	if "dmg" in m:
		m.dmg = maxi(2, int(round(int(round(float(m.dmg) * mult)) * MINI_DMG_MULT)))
	elif "dmg_mult" in m:
		m.dmg_mult = mult * MINI_DMG_MULT
	if "kill_xp" in m:
		m.kill_xp = int(m.kill_xp) * MINI_XP_MULT
	if "boss_leash" in m:
		m.boss_leash = MINI_LEASH
	OW.apply_biome_skin(m, biome)
	boss_node = m
	var w := MiniBossWatch.new()
	add_child(w)
	w.setup(self, m)

func _relic_pool() -> Array:
	return relic_pool_for(belt)

class MiniReturn:
	extends Area2D
	## Выход «тем же интерактором»: стойка хода у спавна (паттерн BiomeExit).
	const MDS := preload("res://scripts/mini_dungeon.gd")
	var zone
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile)
		var root := MiniHoleArt.new()
		root.rim = MDS.hole_rim(String(zone.biome))
		root.stub_biome = String(zone.biome)
		root.scale.x = -1.0  # разворот пасти (Node2D, не Sprite — flip_h тут нет)
		root.position = Vector2(0, -2)
		add_child(root)
		var stub := root._ensure_art()
		if stub != null:
			root.add_child(stub)
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
		return "Выйти из хода"
	func try_interact() -> void:
		GameAudio.sfx("ui_click")
		zone.world.exit_mini(String(zone.biome))
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class MiniHole:
	extends Area2D
	## E-интерактор «ход» ВНУТРИ локации (ставит world._ensure_hole). «Виден
	## после открытия» по §2 выполняется самим фактом: ход живёт в локации,
	## а локация открывается туманом t7 — до входа в биом хода не существует.
	const MDS := preload("res://scripts/mini_dungeon.gd")
	var zone
	var biome := "forest"   # ставит world._ensure_hole (zone здесь — BiomeZone)
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		position = zone.tile_to_world(tile)
		var root := MiniHoleArt.new()
		root.rim = MDS.hole_rim(biome)
		root.stub_biome = biome
		root.position = Vector2(0, -2)
		add_child(root)
		var stub := root._ensure_art()
		if stub != null:
			root.add_child(stub)
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
		return MDS.hole_hint(biome)
	func try_interact() -> void:
		GameAudio.sfx("ui_click")
		zone.world.enter_mini(String(zone.biome))
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			zone.world.near.erase(self)

class MiniHoleArt:
	extends Node2D
	## Код-графика пасти: тёмный провал (CAVE_ROCK) с биомным ободом
	## (HOLE_RIM — рампы закрытого PixelPalette — закон ART). Лес сверху
	## цепляет пень-корягу STUMP_F из существующего ForestArt-листа; прочие
	## биомы — провал без опознавательного знака биома (свой антураж — §4).
	## Ноль растровых файлов.
	const PAL := preload("res://scripts/pixel_palette.gd")
	var rim := "BARK"
	var stub_biome := "forest"
	func _draw() -> void:
		var dk: Color = PAL.c("CAVE_ROCK", PAL.T_OUTLINE)
		var md: Color = PAL.c(rim, PAL.T_DARK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.72))
		draw_circle(Vector2(0, 2), 7.0, dk)
		draw_arc(Vector2(0, 2), 7.5, PI, TAU, 12, md, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	func _ensure_art() -> Sprite2D:
		if stub_biome != "forest":
			return null
		if ResourceLoader.exists(ForestArt.ATLAS_PATH) and ForestArt.REGIONS.has("STUMP_F"):
			var s := Sprite2D.new()
			s.texture = ForestArt._region(ForestArt.load_atlas(), "STUMP_F")
			s.position = Vector2(0, -7)
			return s
		return null

class MiniChest:
	extends Area2D
	## Сундук с гарантированным реликтом (t17 API): Loot.quest_relic —
	## детерминированный выбор из ярусного пула (отсечены «уже в сумке» и
	## чужая рука), force_relic-ролл 2 аффиксов, при исчерпании пула —
	## реликтовое серебро +40. Персист — канон D4 "chest@mini_<z>:x,y".
	var zone
	var used := false
	var uid := ""
	func setup(p_zone, tile: Vector2i) -> void:
		zone = p_zone
		uid = "chest@mini_%s:%d,%d" % [zone.biome, tile.x, tile.y]
		position = zone.tile_to_world(tile)
		used = GameState.chests_used.has(uid)
		if ResourceLoader.exists(CaveArt.ATLAS_PATH) and CaveArt.REGIONS.has("CHEST"):
			var spr := Sprite2D.new()
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
		Loot.quest_relic(GameState, "mini_" + String(zone.biome), zone._relic_pool())
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

class MiniBossWatch:
	extends Node
	## Смерть мини-босса = цель «закрыть ход» (хук q.bm.<биом>, t18-реестр;
	## звенья цепочки с этой целью добавит t20). Смерть отличается от планового
	## сноса зоны: смотрим на dying/hp — при teardown (NG+/ресет) dying=false
	## и hp>0, ложного закрытия не будет.
	var zone
	var boss: Node
	func setup(p_zone, p_boss: Node) -> void:
		zone = p_zone
		boss = p_boss
		boss.tree_exiting.connect(_on_gone)
	func _on_gone() -> void:
		var dy: Variant = boss.get("dying")
		var hpv: Variant = boss.get("hp")
		var dead: bool = (dy == true) or (int(hpv) <= 0)
		if dead:
			QuestsData.note_belt_mini(GameState, String(zone.biome))
			GameState.toast.emit(zone.close_line())
			GameState.quest_changed.emit()
