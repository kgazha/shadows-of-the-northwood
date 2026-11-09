extends Node2D
## Атмосфера (спринт «Атмосфера»): тени сущностей, анимированная вода и факелы,
## свет пещеры (мох/алтарь/босс/сундук), свет игрока, частицы (споры/пыльца),
## цветокор деревня<->пещера (CanvasModulate), процедурная виньетка для HUD,
## детерминированный декор тайлмапа деревни.
## Игровая логика НЕ трогается: только визуал; мир вызывает setup() и zone_changed().
## world.gd — единственный источник констант карты (preload), циклов зависимостей нет.

const WorldScript := preload("res://scripts/world.gd")

const DECOR_TEX := "res://assets/decor.png"        # 128x16: 0 куст+ягоды, 1 папоротник, 2 кленовый лист, 3 мухомор, 4 пень, 5 камыши, 6 рогоз, 7 камни
const ANIM_TEX := "res://assets/anim_tiles.png"    # 128x16: 0-3 вода, 4-5 факел, 6-7 светящийся мох
const SHADOW_TEX := "res://assets/shadow.png"      # 32x16: тень персонажа Rect(0,0,16,8), тень босса Rect(8,7,24,9)

const SHADOW_NAME := "AtmoShadow"
const SCAN_PERIOD := 0.5       # пересканирование сущностей для теней, с
const T_WALK := 0.35           # период смены кадра воды, с
const T_TORCH := 0.25          # период смены кадра факела, с

# индексы decor.png
const D_BUSH := 0
const D_FERN := 1
const D_LEAF := 2
const D_SHROOM := 3
const D_STUMP := 4
const D_REEDS := 5
const D_CATTAIL := 6
const D_STONES := 7
# индексы anim_tiles.png
const A_WATER0 := 0
const A_TORCH0 := 4
const A_MOSS0 := 6

# весовой столб декора на траве: куст/папоротник/лист/мухомор/пень/рогоз (сумма 88)
const DECOR_W := [[D_BUSH, 10], [D_FERN, 24], [D_LEAF, 24], [D_SHROOM, 8], [D_STUMP, 12], [D_CATTAIL, 10]]

# цветокор зон (CanvasModulate): тёплая деревня <-> холодная пещера
const TINT_VILLAGE := Color(1.03, 1.0, 0.94)
const TINT_CAVE := Color(0.85, 0.93, 1.04)

var world: Node2D
var water_layer: TileMapLayer
var water_cells: Array[Vector2i] = []
var _water_frame := 0
var _water_t := 0.0
var _torch_t := 0.0
var _torches: Array = []       # {spr: Sprite2D, light: Light2D, phase: float}
var _moss: Array = []          # {spr: Sprite2D, light: Light2D, phase: float}
var _altar_light: Light2D = null
var _boss: Node2D = null
var _boss_light: Light2D = null
var _scan_t := 0.0
var _amb_village: Node2D       # деревенская атмосфера (тайлмапы-слои, факелы) — живёт в Village
var _cave_container: Node2D    # свет/частицы пещеры — в Atmo, гасятся явно (зона PROCESS_MODE_DISABLED)
var _cm: CanvasModulate = null
var _spores: CPUParticles2D = null
var _pollen: CPUParticles2D = null
var _rad_cache: Dictionary = {}
var _shadow_tex: Texture2D = null
var _anim_tex: Texture2D = null

## Вызывается из world._ready() ПОСЛЕ спавна сущностей и постройки пещеры.
func setup(p_world: Node2D) -> void:
	world = p_world
	name = "Atmo"
	add_to_group("atmosphere")
	_shadow_tex = _load_tex(SHADOW_TEX)
	_anim_tex = _load_tex(ANIM_TEX)
	_cm = CanvasModulate.new()
	_cm.color = TINT_VILLAGE
	world.add_child(_cm)
	if get_parent() == null:  # мир может добавить нас в дерево сам (см. хук в world._ready)
		world.add_child(self)
	_amb_village = Node2D.new()
	_amb_village.name = "AmbienceVillage"
	_amb_village.z_index = -8  # факелы выше тайлмапа/воды, ниже сущностей
	world.village_zone.add_child(_amb_village)
	_cave_container = Node2D.new()
	_cave_container.name = "AmbienceCave"
	add_child(_cave_container)
	_build_shadows()
	_build_water()
	_build_torches()
	_build_cave()
	_build_player_light()
	_build_particles()
	_build_decor()
	# новые NPC/слаймы/интерактивы могут появиться в любой момент: мгновенный скан
	# на child_entered_tree дерева + страховочный таймер SCAN_PERIOD (см. _process)
	world.child_entered_tree.connect(_on_child_entered)
	world.village_zone.child_entered_tree.connect(_on_child_entered)
	world.cave_zone.child_entered_tree.connect(_on_child_entered)
	world.tree_exiting.connect(_disconnect_scan)

func _disconnect_scan() -> void:
	if world != null and world.is_inside_tree():
		world.child_entered_tree.disconnect(_on_child_entered)
		world.village_zone.child_entered_tree.disconnect(_on_child_entered)
		world.cave_zone.child_entered_tree.disconnect(_on_child_entered)

## Хук мира: смена зоны — частицы и цветокор. instant=true — загрузка сейва, без фейда.
func zone_changed(to_cave: bool, instant := false) -> void:
	if _spores != null:
		_spores.visible = to_cave
		_spores.process_mode = Node.PROCESS_MODE_INHERIT if to_cave else Node.PROCESS_MODE_DISABLED
	if _pollen != null:
		_pollen.visible = not to_cave
		_pollen.process_mode = Node.PROCESS_MODE_DISABLED if to_cave else Node.PROCESS_MODE_INHERIT
	if _cm == null:
		return
	var target := TINT_CAVE if to_cave else TINT_VILLAGE
	if instant:
		_cm.color = target
	else:
		var t := create_tween()
		t.tween_property(_cm, "color", target, 0.8)

func _process(delta: float) -> void:
	# периодическое пересканирование сущностей (respawn/смерть)
	_scan_t += delta
	if _scan_t >= SCAN_PERIOD:
		_scan_t = 0.0
		_scan_shadows()
	# вода: 4 кадра 16x16 из anim_tiles.png, цикл T_WALK
	if water_layer != null and not water_cells.is_empty():
		_water_t += delta
		if _water_t >= T_WALK:
			_water_t -= T_WALK
			_water_frame = (_water_frame + 1) % 4
			for c in water_cells:
				water_layer.set_cell(c, 0, Vector2i(A_WATER0 + _water_frame, 0))
	# факелы: 2 кадра + мягкий синусный фликер (кадр — смена AtlasTexture)
	if not _torches.is_empty():
		_torch_t += delta
		var ti := int(_torch_t / T_TORCH) % 2
		var tt := _time()
		for tr in _torches:
			tr["spr"].texture = tr["t1"] if ti == 1 else tr["t0"]
			tr["light"].energy = 0.9 * (0.85 + 0.15 * sin(tt * 7.0 + float(tr["phase"])))
	# мох пещеры: 2 кадра + фликер
	if not _moss.is_empty():
		var mt := int(_time() * 2.5) % 2
		var tt2 := _time()
		for m in _moss:
			m["spr"].texture = m["t1"] if mt == 1 else m["t0"]
			m["light"].energy = 0.9 * (0.8 + 0.2 * sin(tt2 * 5.0 + float(m["phase"])))
	# алтарь: медленный пульс
	if _altar_light != null:
		_altar_light.energy = 0.75 + 0.25 * sin(_time() * 2.2)
	# босс: свет «за спиной» (brute.gd не задаёт facing — считаем лицом вниз)
	if _boss_light != null:
		if _boss != null and is_instance_valid(_boss):
			var fd := Vector2(0, 1)
			if _boss.has_method("facing_dir"):
				fd = _boss.facing_dir()
			_boss_light.position = -fd * 10.0
		else:
			_boss_light = null

# ---------- тени ----------

func _build_shadows() -> void:
	_scan_t = 0.0
	_scan_shadows()

func _on_child_entered(_node: Node) -> void:
	_scan_t = SCAN_PERIOD  # мгновенный скан: в дереве появилась новая сущность

func _scan_shadows() -> void:
	if world == null:
		return
	_walk_shadowable(world)

func _walk_shadowable(n: Node) -> void:
	for c in n.get_children():
		if c is Node2D:
			_try_shadow(c as Node2D)
		_walk_shadowable(c)

## Кандидат на тень: враг (enemy, включая босса) или интерактив/NPC с get_hint().
func _try_shadow(e: Node2D) -> void:
	if _in_atmo(e):
		return
	if not e.is_in_group("enemy") and not e.is_in_group("player") and not e.has_method("get_hint"):
		return
	_ensure_shadow(e)

## true если узел — часть поддерева атмосферы (декор, контейнеры, свет).
func _in_atmo(n: Node) -> bool:
	var p := n
	while p != null and p != world:
		if p == self:
			return true
		p = p.get_parent()
	return false

## Вешает Sprite2D-тень child'ом в сущность index 0 (перед её спрайтом), якорь — ноги.
func _ensure_shadow(e: Node2D) -> void:
	if e.has_node(SHADOW_NAME):
		return
	# ищем видимый спрайт; у бесспрайтовых объектов (лестницы, триггеры) тени нет
	var spr: CanvasItem = null
	for ch in e.get_children():
		if (ch is Sprite2D or ch is AnimatedSprite2D) and String(ch.name) != SHADOW_NAME:
			spr = ch
			break
	if spr == null or _shadow_tex == null:
		return
	var is_boss := e.is_in_group("boss")
	var sh := Sprite2D.new()
	sh.name = SHADOW_NAME
	sh.texture = _shadow_tex
	sh.centered = false
	if is_boss:
		sh.region_enabled = true
		sh.region_rect = Rect2(8, 7, 24, 9)
	sh.modulate = Color(0, 0, 0, 0.5)
	sh.position = Vector2(-12, 7) if is_boss else Vector2(-8, 2)
	var idx := 0
	for ch2 in e.get_children():
		if ch2 == spr:
			break
		idx += 1
	e.add_child(sh)
	e.move_child(sh, idx)  # child index 0 (или прямо перед спрайтом) — тень рисуется под сущностью

# ---------- вода (деревня) ----------

func _build_water() -> void:
	if _anim_tex == null:
		push_warning("atmosphere: нет assets/anim_tiles.png — вода/факелы/мох без анимации")
		return
	var ts := TileSet.new()
	var src := TileSetAtlasSource.new()
	src.texture = _anim_tex
	src.texture_region_size = Vector2i(16, 16)
	for i in 8:
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	water_layer = TileMapLayer.new()
	water_layer.name = "AtmoWater"
	water_layer.tile_set = ts
	water_layer.z_index = -9  # над базовым тайлмапом (-10), под сущностями
	world.village_zone.add_child(water_layer)
	world.village_zone.move_child(water_layer, _village_tilemap_index() + 1)
	var ct: Dictionary = WorldScript.CHAR_TO_TILE
	for y in world.map_h:
		var row := String(world.map_rows[y])
		for x in world.map_w:
			if ct.has(row[x]) and int(ct[row[x]]) == 4:
				water_cells.append(Vector2i(x, y))
	for c in water_cells:
		water_layer.set_cell(c, 0, Vector2i(A_WATER0, 0))

func _village_tilemap_index() -> int:
	var i := 0
	for ch in world.village_zone.get_children():
		if ch is TileMapLayer and String(ch.name) != "AtmoWater":
			return i
		i += 1
	return 0

# ---------- факелы у дверей (деревня) ----------

func _build_torches() -> void:
	if _anim_tex == null:
		return
	var ct: Dictionary = WorldScript.CHAR_TO_TILE
	for y in world.map_h:
		var row := String(world.map_rows[y])
		for x in world.map_w:
			if not ct.has(row[x]) or int(ct[row[x]]) != 8:
				continue
			var holder := Node2D.new()
			holder.position = world.tile_to_world(Vector2i(x, y)) + Vector2(0, -6)  # -6 px от центра двери
			var spr := Sprite2D.new()
			var t0 := _anim_frame(A_TORCH0)
			var t1 := _anim_frame(A_TORCH0 + 1)
			spr.texture = t0
			holder.add_child(spr)
			var l := _mk_light(Color(1.0, 0.75, 0.45), 0.9, 36.0)
			holder.add_child(l)
			_amb_village.add_child(holder)
			_torches.append({"spr": spr, "light": l, "phase": float(_hash(x, y)), "t0": t0, "t1": t1})

func _anim_frame(idx: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = _anim_tex
	at.region = Rect2(idx * 16, 0, 16, 16)
	return at

# ---------- пещера: мох, алтарь, босс, сундук ----------

func _build_cave() -> void:
	var dz = world.dungeon_zone
	if dz == null or _anim_tex == null:
		return
	var ct: Dictionary = WorldScript.CHAR_TO_TILE
	var moss_all: Array[Vector2i] = []
	var altar_cells: Array[Vector2i] = []
	for y in int(dz.map_h):
		var row := String(dz.map_rows[y])
		for x in int(dz.map_w):
			if not ct.has(row[x]):
				continue
			match int(ct[row[x]]):
				9:
					moss_all.append(Vector2i(x, y))
				10:
					altar_cells.append(Vector2i(x, y))
	# ~8 светящихся грибов: детерминированный hash (подстраховка — первые 8)
	var chosen: Array[Vector2i] = []
	for t in moss_all:
		if _hash(t.x, t.y) < 8:
			chosen.append(t)
	if chosen.size() < 8:
		chosen.clear()
		for t in moss_all:
			chosen.append(t)
			if chosen.size() >= 8:
				break
	for t in chosen:
		var base: Vector2 = dz.tile_to_world(t) + Vector2(world.CAVE_OFFSET)
		var spr := Sprite2D.new()
		var t0 := _anim_frame(A_MOSS0)
		var t1 := _anim_frame(A_MOSS0 + 1)
		spr.texture = t0
		spr.position = base
		spr.z_index = -8  # мох на полу, под сущностями
		add_child(spr)
		var l := _mk_light(Color(0.4, 1.0, 0.5), 0.9, 28.0)
		l.position = base
		add_child(l)
		_moss.append({"spr": spr, "light": l, "phase": float(_hash(t.x + 11, t.y + 7)), "t0": t0, "t1": t1})
	# алтарь 'A' — один зелёный Light2D radius 60 (центр по клеткам A), пульс
	if not altar_cells.is_empty():
		var c := Vector2.ZERO
		for t in altar_cells:
			c += dz.tile_to_world(t)
		c /= float(altar_cells.size())
		_altar_light = _mk_light(Color(0.4, 1.0, 0.5), 1.0, 60.0)
		_altar_light.position = c + Vector2(world.CAVE_OFFSET)
		add_child(_altar_light)
	# босс — свет radius 44 за спиной (child в боссе: живёт и умирает вместе с ним)
	var bosses := get_tree().get_nodes_in_group("boss")
	if not bosses.is_empty():
		_boss = bosses[0]
		_boss_light = _mk_light(Color(0.8, 0.6, 1.0), 0.85, 44.0)
		_boss.add_child(_boss_light)
	# алтарный сундук до взятия амулета — золотой свет radius 24.
	# CaveChest — inner-class без имени класса в рантайме; опознаём по хинту,
	# подсветка — child'ом: при взятии сундук queue_free() и забирает свет с собой.
	if not GameState.has_amulet:
		for ch in dz.get_children():
			if is_instance_valid(ch) and ch.has_method("get_hint") \
					and String(ch.call("get_hint")).find("сундук") >= 0:
				ch.add_child(_mk_light(Color(1.0, 0.84, 0.4), 0.8, 24.0))
				break

# ---------- игрок ----------

func _build_player_light() -> void:
	if world.player == null:
		return
	world.player.add_child(_mk_light(Color(1, 1, 1), 0.35, 50.0))

# ---------- частицы (частицы CPU, gl_compatibility, суммарно <120) ----------

func _build_particles() -> void:
	var dot := _dot_texture()
	# споры пещеры: жёлто-зелёные, вверх, process region ~карта пещеры
	var dz = world.dungeon_zone
	var cw := 30 * 16.0
	var chh := 22 * 16.0
	if dz != null:
		cw = float(int(dz.map_w) * 16)
		chh = float(int(dz.map_h) * 16)
	_spores = CPUParticles2D.new()
	_spores.name = "CaveSpores"
	_spores.amount = 80
	_spores.lifetime = 6.0
	_spores.preprocess = 3.0
	_spores.local_coords = false
	_spores.texture = dot
	_spores.emission_shape = CPUParticles2D.EmissionShape.EMISSION_SHAPE_RECTANGLE
	_spores.emission_rect_extents = Vector2(cw * 0.5, chh * 0.5)
	_spores.direction = Vector2(0, -1)
	_spores.spread = 28.0
	_spores.gravity = Vector2.ZERO
	_spores.initial_velocity_min = 4.0
	_spores.initial_velocity_max = 11.0
	_spores.randomness = 0.35  # «дрейф» спор: разброс параметров вместо недоступного turbulence
	_spores.color_ramp = _ramp(Color(0.85, 1.0, 0.45, 0.0), Color(0.7, 0.95, 0.35, 0.55))
	_spores.position = Vector2(world.CAVE_OFFSET) + Vector2(cw * 0.5, chh * 0.5)
	_spores.visible = false
	_spores.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_spores)
	# деревня: 20 частиц золотой пыльцы
	_pollen = CPUParticles2D.new()
	_pollen.name = "VillagePollen"
	_pollen.amount = 20
	_pollen.lifetime = 8.0
	_pollen.preprocess = 4.0
	_pollen.local_coords = false
	_pollen.texture = dot
	_pollen.emission_shape = CPUParticles2D.EmissionShape.EMISSION_SHAPE_RECTANGLE
	_pollen.emission_rect_extents = Vector2(world.map_w * 8.0, world.map_h * 8.0)
	_pollen.direction = Vector2(0, -1)
	_pollen.spread = 70.0
	_pollen.gravity = Vector2(0, -1.5)
	_pollen.initial_velocity_min = 2.0
	_pollen.initial_velocity_max = 6.0
	_pollen.randomness = 0.5
	_pollen.color_ramp = _ramp(Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.82, 0.4, 0.65))
	_pollen.position = Vector2(world.map_w * 8.0, world.map_h * 8.0)
	_cave_container.add_child(_pollen)

func _dot_texture() -> ImageTexture:
	var img := Image.create(5, 5, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(2, 2, Color(1, 1, 1, 1))
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		img.set_pixel(2 + int(d[0]), 2 + int(d[1]), Color(1, 1, 1, 0.6))
	for d in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
		img.set_pixel(2 + int(d[0]), 2 + int(d[1]), Color(1, 1, 1, 0.3))
	return ImageTexture.create_from_image(img)

func _ramp(from_c: Color, to_c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, from_c)
	g.set_color(1, to_c)
	return g

# ---------- декор (деревня) ----------

## Детерминированный hash клетки: (x*7349 + y*9151) % 100.
func _hash(x: int, y: int) -> int:
	return posmod(x * 7349 + y * 9151, 100)

func _build_decor() -> void:
	if not ResourceLoader.exists(DECOR_TEX):
		push_warning("atmosphere: нет assets/decor.png — декор пропущен")
		return
	var decor_tex := load(DECOR_TEX)
	var ct: Dictionary = WorldScript.CHAR_TO_TILE
	var tile_at := func(xx: int, yy: int) -> int:
		if xx < 0 or yy < 0 or xx >= world.map_w or yy >= world.map_h:
			return -1
		var r := String(world.map_rows[yy])
		return int(ct[r[xx]]) if ct.has(r[xx]) else -1
	# запрет декора в 1 клетке от тропы/стен/крыш/дверей/спавна/входа в пещеру/сущностей
	var banned := {}
	var forbid := func(tx: int, ty: int) -> void:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				banned[Vector2i(tx + dx, ty + dy)] = true
	for y in world.map_h:
		var row := String(world.map_rows[y])
		for x in world.map_w:
			if not ct.has(row[x]):
				continue
			match int(ct[row[x]]):
				3, 6, 7, 8:  # тропа, стена, крыша, дверь
					forbid.call(x, y)
	forbid.call(world.spawn_tile.x, world.spawn_tile.y)
	forbid.call(int(world.CAVE_ENTRANCE_TILE.x), int(world.CAVE_ENTRANCE_TILE.y))
	for arr_name in ["npcs", "herbs", "chests", "slimes"]:
		for e: Array in world.meta.get(arr_name, []):
			forbid.call(int(e[e.size() - 2]), int(e[e.size() - 1]))
	var container := Node2D.new()
	container.name = "AtmoDecor"
	world.village_zone.add_child(container)
	# tree order: сразу за базовым тайлмапом, до сущностей
	world.village_zone.move_child(container, _village_tilemap_index() + 1)
	for y in world.map_h:
		for x in world.map_w:
			if tile_at.call(x, y) not in [0, 1, 2]:
				continue
			if banned.has(Vector2i(x, y)):
				continue
			var h := _hash(x, y)
			var idx := -1
			if _near_water(tile_at, x, y):
				idx = D_REEDS if h % 2 == 0 else D_CATTAIL  # сосед воды — камыши/рогоз
			elif h < 6:
				idx = _pick_decor(_hash(x + 37, y + 53))   # 6% травяной декор
			elif _hash(x + 71, y + 97) < 3:
				idx = D_STONES                             # 3% камни
			if idx < 0:
				continue
			var spr := Sprite2D.new()
			var at := AtlasTexture.new()
			at.atlas = decor_tex
			at.region = Rect2(idx * 16, 0, 16, 16)
			spr.texture = at
			spr.position = world.tile_to_world(Vector2i(x, y))  # центр тайла, y+2 уже в tile_to_world
			container.add_child(spr)

func _near_water(tile_at: Callable, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if tile_at.call(x + dx, y + dy) == 4:
				return true
	return false

## Взвешенный выбор по броску 0..99 (куст/папоротник/лист/мухомор/пень/рогоз).
func _pick_decor(roll: int) -> int:
	var acc := 0
	for w in DECOR_W:
		acc += int(w[1])
		if roll < acc:
			return int(w[0])
	return int(DECOR_W[0][0])

# ---------- виньетка (для HUD) ----------

## Процедурная виньетка под размер вьюпорта: центр прозрачный, углы чёрный alpha~90,
## самый край — чисто (0). HUD кладёт TextureRect с этой текстурой поверх всего.
static func make_vignette_texture(vp: Vector2) -> ImageTexture:
	var w := int(vp.x)
	var h := int(vp.y)
	if w < 8 or h < 8:
		w = 640
		h = 360
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := float(w - 1) * 0.5
	var cy := float(h - 1) * 0.5
	for y in h:
		for x in w:
			var dx := (float(x) - cx) / cx
			var dy := (float(y) - cy) / cy
			var r := sqrt(dx * dx + dy * dy) * 0.70710678  # 0 в центре, 1.0 в углах
			var t := clampf((r - 0.45) / 0.55, 0.0, 1.0)
			var edge := minf(minf(float(x), float(y)), minf(float(w - 1 - x), float(h - 1 - y))) / 3.0
			var a := (3.0 * t * t - 2.0 * t * t * t) * clampf(edge, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, a * (90.0 / 255.0)))
	return ImageTexture.create_from_image(img)

# ---------- утилиты ----------

func _mk_light(col: Color, en: float, rad: float) -> Light2D:
	# Light2D абстрактный — конкретика PointLight2D; радиус = ширина текстуры / 2 * texture_scale
	var l := PointLight2D.new()
	l.texture = _radial(rad)
	l.color = col
	l.energy = en
	l.texture_scale = 1.0
	return l

## Радиальная текстура света — генерируется кодом (GradientTexture2D).
## Диаметр подобран под радиус: width = 2*rad -> фактический радиус света = rad.
func _radial(rad: float) -> Texture2D:
	var key := int(ceil(rad * 2.0))
	if _rad_cache.has(key):
		return _rad_cache[key]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = key
	gt.height = key
	_rad_cache[key] = gt
	return gt

func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("atmosphere: нет ассета %s" % path)
	return null

func _time() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
