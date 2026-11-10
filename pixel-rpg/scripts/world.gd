extends Node2D
## Мир: карта из JSON, стены-коллизии, игрок, сущности, диалоги, сейвы.
## Две зоны в контейнерах Node2D: "Village" (деревня) и "Cave" (пещера).
## Пещера сдвинута на CAVE_OFFSET, чтобы физика зон никогда не пересекалась;
## переход — затемнение, смена видимости зон и телепорт героя.

const TILE := 16
const Nav := preload("res://scripts/nav.gd")
const CHAR_TO_TILE := {
	"g": 0, "G": 1, "f": 2, "d": 3, "w": 4, "t": 5, "W": 6, "R": 7,
	"D": 8, "#": 9, "r": 12, "s": 13, "T": 15, "A": 3,
}
const BLOCKING := [4, 5, 6, 7, 8, 9, 12, 13]
## Коллизии «мелких» блокирующих тайлов: индекс -> [w, h, dx, dy] от центра клетки.
## Полный тайл жмёт только крупняк; иначе вокруг столбика/камня образуются
## «невидимые стены» — упираться в пустоту рядом с видимым предметом обидно.
const BLOCK_SHAPES := {
	12: [11, 10, 0, 1],   # валун: тело камня, не углы клетки
	13: [6, 5, 0, 3],     # указатель: лишь столб у земли
}
## То же для пещерных тайлов (индексы dungeon_zone.CHAR_TO_TILE, см. CAVE-скан
## qa_c2): колонна/обломки/сундук не занимают клетку целиком — полный коллайдер
## ставил бы невидимые стены вдоль проходов.
const CAVE_BLOCK_SHAPES := {
	6: [10, 16, 0, 0],    # колонна: ствол с постаментом (капитель визуально уже)
	7: [12, 10, 0, 1],    # обломки: куча в центре, углы клетки проходимы
	11: [13, 12, 0, 1],   # алтарный сундук: корпус без углов
}
const DZ := preload("res://scripts/dungeon_zone.gd")
const CAVE_OFFSET := Vector2(0, 4800.0)      # «этаж» пещеры в общих координатах
const CAVE_ENTRANCE_TILE := Vector2i(40, 17) # вход в пещеру в лесу (тайл проходим: T)
const ASHEN_OFFSET := Vector2(0, 9600.0)     # «этаж» Пепелища в общих координатах
const ASHEN_ENTRANCE_TILE := Vector2i(45, 20) # «A» — выжженная аршина на восточной окраине
## Костры-привалы (id -> тайл): у дороги к торговцу, в травяном поле слаймов,
## у входа в пещеру. Одноразовые — последний привал перед опасным рывком.
const CAMPFIRE_SPOTS := {
	"cf_village": Vector2i(18, 13),
	"cf_forest": Vector2i(12, 19),
	"cf_cave": Vector2i(38, 18),
}

## Мобы пещеры — «отпрыски гнили» тремя ярусами по глубине (расстояние от входа
## в тайл Чебышёва): чем глубже, тем плотнее и сильнее. Пик сложности — босс.
const CAVE_MOB_BANDS := {1: [4, 7], 2: [8, 11], 3: [12, 999]}
const CAVE_MOB_CAPS := {1: 3, 2: 4, 3: 5}

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
var ashen_zone: Node2D
var ashen_grid    # scripts/ashen_zone.gd (слабо: setup/spawn_world_pos/map_w/map_h/portal_node)
var active_area := "village"  # "village" | "cave" | "ashen" — где сейчас герой
var cam: Camera2D
var fade_rect: ColorRect
var village_return_pos := Vector2.INF  # куда возвращаться из пещеры (то место, где вошли)
var ashen_return_pos := Vector2.INF    # куда возвращаться из Пепелища
var cur_move: Texture2D    # курсор «идти» (world: прицел assets/ui/cursor_crosshair.png, фолбэк cursor_move.png)
var cur_enemy: Texture2D   # курсор «атака» (cursor_enemy.png)
var cur_arrow: Texture2D   # стрелка для диалогов/модалок (assets/ui/cursor_arrow.png)
var atmosphere             # scripts/atmosphere.gd: свет/тени/частицы/цветокор (весь визуал спринта «Атмосфера»)
var campfires: Array = []  # scripts/campfire.gd (hud читает для панели варки/полосы отдыха)

func _ready() -> void:
	# Звук: единственный экземпляр GameAudio создаём ПЕРВЫМ — любой _ready ниже
	# (hud, slime, campfire) уже может звать GameAudio.sfx(...) без проверки.
	var audio := GameAudio.new()
	add_child(audio)
	GameAudio.I = audio
	GameAudio.music("forest")
	# ПКМ-перемещение: синглтон ClickMove (по образцу GameAudio — экземпляр + static I).
	var click_move := ClickMove.new()
	add_child(click_move)
	ClickMove.I = click_move
	# Миникарта (M): синглтон Minimap (по образцу ClickMove — экземпляр + static I).
	var minimap := Minimap.new()
	add_child(minimap)
	Minimap.I = minimap
	# Подсказки первопроходцу: синглтон FirstHint (паттерн ClickMove/Minimap).
	var first_hint := FirstHint.new()
	add_child(first_hint)
	FirstHint.I = first_hint
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
	# Сейв читаем ДО всего, что читает персист в момент спавна: campfire.setup()
	# (campfires_used), interactable.setup() (chests_used), dungeon_zone.setup()
	# (door_opened/has_amulet/boss_defeated -> дверь, сундук, босс), а также
	# atmosphere/hud ниже (in_cave, статы). Порядок «сначала спавн, потом загрузка»
	# рождал целое семейство ресинков; сами они остаются как страховка (F9/рантайм),
	# но теперь никогда не видят «незагруженное» состояние. apply_zone() вызывается
	# позже: зона пещеры к моменту применения должна быть собрана.
	var loaded := GameState.load_game()  # true — сейв прочитан (F9 грузит сам, см. _unhandled_input)
	village_zone = Node2D.new()
	village_zone.name = "Village"
	add_child(village_zone)
	cave_zone = Node2D.new()
	cave_zone.name = "Cave"
	cave_zone.position = CAVE_OFFSET
	add_child(cave_zone)
	ashen_zone = Node2D.new()
	ashen_zone.name = "Ashen"
	ashen_zone.position = ASHEN_OFFSET
	add_child(ashen_zone)
	_build_tiles()
	_build_walls()
	_spawn_player()
	_spawn_entities()
	_build_campfires()
	_build_cave()
	_build_cave_entrance()
	_build_ashen()
	_build_ashen_entrance()
	atmosphere = load("res://scripts/atmosphere.gd").new()
	add_child(atmosphere)
	atmosphere.setup(self)
	atmosphere.zone_changed(GameState.in_cave, true)  # стартовое состояние после загрузки сейва — без фейда
	_build_fade()
	_load_cursors()
	hud = load("res://scripts/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	add_child(Journal.new())  # журнал квестов (J): quests_data.gd + journal.gd, самодостаточен
	add_child(Shop.new())  # лавка Гриима: скрыта по умолчанию; после Journal — Esc у Shop приоритетнее
	add_child(SettingsMenu.new())  # меню настроек (Esc): как GameAudio — узел стартует скрытым
	add_child(Achv.new())  # достижения+daily (achv.gd); после load_game() — daily видит stamp
	GameState.ng_plus_started.connect(func() -> void: get_tree().reload_current_scene.call_deferred())
	if loaded:
		apply_zone(GameState.in_cave, false)
		if GameState.pos_valid:
			player.global_position = GameState.player_pos
			if player.global_position.y > ASHEN_OFFSET.y:
				apply_area("ashen", false)  # сейв оставил героя в Пепелище
		player.apply_class()
		hud.refresh_skills()
		_apply_chest_states()  # страховка: спавн уже видит сейв, идемпотентно (нужно для F9)
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
	# мир: пиксельный прицел из Kenney Cursor Pixel Pack; при отсутствии — штатный cursor_move.png
	if ResourceLoader.exists("res://assets/ui/cursor_crosshair.png"):
		cur_move = load("res://assets/ui/cursor_crosshair.png")
	elif ResourceLoader.exists("res://assets/cursor_move.png"):
		cur_move = load("res://assets/cursor_move.png")
	if ResourceLoader.exists("res://assets/cursor_enemy.png"):
		cur_enemy = load("res://assets/cursor_enemy.png")
	if ResourceLoader.exists("res://assets/ui/cursor_arrow.png"):
		cur_arrow = load("res://assets/ui/cursor_arrow.png")

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
			var idx := int(CHAR_TO_TILE[ch])
			if idx in BLOCKING:
				var spec: Array = BLOCK_SHAPES.get(idx, [TILE, TILE, 0, 0])
				var cs := CollisionShape2D.new()
				var sh := RectangleShape2D.new()
				sh.size = Vector2(float(spec[0]), float(spec[1]))
				cs.shape = sh
				cs.position = Vector2(x * TILE + 8 + float(spec[2]), y * TILE + 8 + float(spec[3]))
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
	# Кузнец Гриим (лавка): фиксированная точка, тайл 'g' walkable
	var smith = npc_script.new()
	village_zone.add_child(smith)
	smith.setup(self, "smith", Vector2i(26, 13))
	var it_script := load("res://scripts/interactable.gd")
	for e: Array in meta.get("herbs", []):
		var herb = it_script.new()
		village_zone.add_child(herb)
		herb.setup(self, "herb", Vector2i(int(e[0]), int(e[1])))
	for e: Array in meta.get("chests", []):
		var chest = it_script.new()
		village_zone.add_child(chest)
		chest.setup(self, "chest", Vector2i(int(e[0]), int(e[1])))
	var slime_script := load("res://scripts/slime.gd")
	for e: Array in meta.get("slimes", []):
		var slime = slime_script.new()
		village_zone.add_child(slime)
		slime.setup(self, Vector2i(int(e[0]), int(e[1])))
	# Боевые архетипы (sand_m): лучники держат дистанцию в дальних углах леса…
	var archer_script := load("res://scripts/mob_archer.gd")
	for e: Array in [[4, 26], [44, 26]]:
		var arch = archer_script.new()
		village_zone.add_child(arch)
		arch.setup(self, Vector2i(int(e[0]), int(e[1])))
	# …а стая мглокрыс — на западной поляне (общий испуг при живых <= половины).
	var rat_script := load("res://scripts/mob_swarmling.gd")
	for e: Array in [[6, 16], [9, 16], [6, 18], [10, 18]]:
		var rat = rat_script.new()
		rat.swarm_id = "glade_west"
		village_zone.add_child(rat)
		rat.setup(self, Vector2i(int(e[0]), int(e[1])))

## Костры-привалы (E-отдых + варка). Костёр — Area2D, использует тот же паттерн
## world.near, что NPC/травы; одноразовость живёт в GameState.campfires_used.
func _build_campfires() -> void:
	var cf_script := load("res://scripts/campfire.gd")
	for id in CAMPFIRE_SPOTS:
		var cf = cf_script.new()
		village_zone.add_child(cf)
		cf.setup(self, String(id), CAMPFIRE_SPOTS[id])
		campfires.append(cf)

## Ближайший живой (не использованный) костёр в зоне E — или null.
func campfire_near() -> Node2D:
	var best: Node2D = null
	var bd := INF
	for n in near:
		if n.get("is_campfire") == true and n.get("used") == false and player != null:
			var d := player.global_position.distance_squared_to(n.global_position)
			if d < bd:
				bd = d
				best = n
	return best

func _build_cave() -> void:
	var dz = load("res://scripts/dungeon_zone.gd").new()
	cave_zone.add_child(dz)
	dz.setup(self)
	dungeon_zone = dz
	_spawn_cave_embers()
	_apply_cave_shapes(dz)
	# сундук открывают и в этой сессии: try_interact эмитит stats_changed — снимаем
	# коллайдер сразу, а не только после перезахода (пещера строится один раз)
	GameState.stats_changed.connect(_sync_cave_chest)
	_spawn_cave_mobs()
	# Тенеплёты в нише босса (появляются только живым боссом, песочница sand_m).
	if not GameState.boss_defeated and dungeon_zone != null and dungeon_zone.boss_node != null:
		var wraith_script := load("res://scripts/mob_wraith.gd")
		for t: Vector2i in [Vector2i(9, 16), Vector2i(13, 17)]:
			var wr = wraith_script.new()
			dungeon_zone.add_child(wr)
			wr.setup(self, t)
	cave_zone.visible = false
	cave_zone.process_mode = Node.PROCESS_MODE_DISABLED

## Тлеющие угли — 3 точки пещеры (у входа, у комнаты отшельника, у зала босса).
## Генераторы живут в cave_zone: с выходом из пещеры замирают (DISABLED),
## со сменой сцены удаляются вместе с зоной — утечек нет.
func _spawn_cave_embers() -> void:
	for t: Vector2i in [Vector2i(15, 2), Vector2i(23, 11), Vector2i(13, 15)]:
		var e := Fx.ember_bed(Vector2(t.x * TILE + 8, t.y * TILE + 10))
		if e != null:
			cave_zone.add_child(e)

## Коллайдеры «мелких» пещерных блокеров: dungeon_zone строит их полными тайлами,
## а CAVE_BLOCK_SHAPES задаёт видимую форму — правим после setup().
func _apply_cave_shapes(dz) -> void:
	var walls: Node = dz.get_node_or_null("Walls")
	if walls == null:
		return
	for child in walls.get_children():
		if not (child is CollisionShape2D):
			continue
		var cs: CollisionShape2D = child
		var tx := int((cs.position.x - 8.0) / float(TILE))
		var ty := int((cs.position.y - 8.0) / float(TILE))
		if ty < 0 or ty >= dz.map_rows.size() or tx < 0 or tx >= String(dz.map_rows[ty]).length():
			continue
		var ch: String = String(dz.map_rows[ty])[tx]
		if not DZ.CHAR_TO_TILE.has(ch):
			continue
		var idx := int(DZ.CHAR_TO_TILE[ch])
		if not CAVE_BLOCK_SHAPES.has(idx):
			continue
		if idx == 11 and GameState.has_amulet:
			cs.queue_free()  # сундук открыт (тайл уже 12) — коллайдер был бы невидимой стеной
			continue
		var spec: Array = CAVE_BLOCK_SHAPES[idx]
		var sh := RectangleShape2D.new()
		sh.size = Vector2(float(spec[0]), float(spec[1]))
		cs.shape = sh
		cs.position = Vector2(tx * TILE + 8 + float(spec[2]), ty * TILE + 8 + float(spec[3]))

## Сундук открыт (амулет взят — тот же признак, по которому dungeon_zone красит
## тайл 11 -> 12): коллайдер 13x12 в нише надо снять, иначе на месте тайла 12
## остаётся невидимая стена. Идемпотентно — сборка пещеры, загрузка сейва, рантайм.
func _sync_cave_chest() -> void:
	if dungeon_zone == null or dungeon_zone.chest_tile.x < 0 or not GameState.has_amulet:
		return
	dungeon_zone.open_chest()  # тайл 12: теперь нужно для F9 — при старте setup() сам рисует 12
	var walls: Node = dungeon_zone.get_node_or_null("Walls")
	if walls == null:
		return
	for child in walls.get_children():
		if not (child is CollisionShape2D) or child.is_queued_for_deletion():
			continue
		var cs: CollisionShape2D = child
		var t := Vector2i(int((cs.position.x - 8.0) / float(TILE)), int((cs.position.y - 8.0) / float(TILE)))
		if t == dungeon_zone.chest_tile:
			cs.queue_free()

## Детерминированный спавн мобов по ярусам глубины (см. CAVE_MOB_BANDS/CAPS):
## тайлы проходимы, подальше от «точек интереса», не в узких коридорах, с
## интервалом ≥2. Плотность ограничена(cap), состав — см. brute.TIERS.
func _spawn_cave_mobs() -> void:
	if dungeon_zone == null:
		return
	var dz = dungeon_zone
	var sp: Vector2i = dz.spawn_tile
	var pois: Array = [[sp, 4], [dz.chest_tile, 2], [dz.door_tile, 1]]
	if dz.stairs_node != null:
		pois.append([_node_tile(dz.stairs_node), 2])
	if dz.hermit_node != null:
		pois.append([_node_tile(dz.hermit_node), 2])
	if dz.boss_node != null:
		pois.append([_node_tile(dz.boss_node), 3])
	var counts := {1: 0, 2: 0, 3: 0}
	var placed: Array = []
	for y in dz.map_h:
		var row := String(dz.map_rows[y])
		for x in row.length():
			var ch: String = row[x]
			if ch != "." and ch != ",":
				continue
			var d := maxi(absi(x - sp.x), absi(y - sp.y))
			if d < 4:
				continue
			var tier := 1
			if d > 7:
				tier = 2
			if d > 11:
				tier = 3
			if counts[tier] >= int(CAVE_MOB_CAPS[tier]):
				continue
			if d < int(CAVE_MOB_BANDS[tier][0]):
				continue
			if (x * 31 + y * 17) % 3 != 0:
				continue
			var t := Vector2i(x, y)
			if not dz.cell_walkable(t) or _near_cave_poi(t, pois) or _near_placed(placed, t):
				continue
			var m = load("res://scripts/brute.gd").new()
			m.boss = false
			m.tier = tier
			dz.add_child(m)
			m.setup(self, t)
			counts[tier] += 1
			placed.append(t)

func _node_tile(n: Node2D) -> Vector2i:
	return Vector2i(int(n.position.x / float(TILE)), int((n.position.y - 2.0) / float(TILE)))

func _near_cave_poi(t: Vector2i, pois: Array) -> bool:
	for p: Array in pois:
		var pt: Vector2i = p[0]
		if pt.x < 0:
			continue
		if maxi(absi(t.x - pt.x), absi(t.y - pt.y)) <= int(p[1]):
			return true
	return false

func _near_placed(list: Array, t: Vector2i) -> bool:
	for q: Vector2i in list:
		if maxi(absi(t.x - q.x), absi(t.y - q.y)) < 2:
			return true
	return false

func _build_cave_entrance() -> void:
	var stairs := CaveStairs.new()
	village_zone.add_child(stairs)
	stairs.setup(self, CAVE_ENTRANCE_TILE)

## Пепелище: контейнер ashen_zone уже в _ready (сдвиг ASHEN_OFFSET). Зона
## строится после load_game() — персист ведьмы/сундука читается из флагов.
func _build_ashen() -> void:
	var az = load("res://scripts/ashen_zone.gd").new()
	ashen_zone.add_child(az)
	az.setup(self)
	ashen_grid = az
	ashen_zone.visible = false
	ashen_zone.process_mode = Node.PROCESS_MODE_DISABLED

func _build_ashen_entrance() -> void:
	var gate := AshenGate.new()
	village_zone.add_child(gate)
	gate.setup(self, ASHEN_ENTRANCE_TILE)

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
	if GameState.input_locked:
		# диалог/модалка: стрелка из того же пака (меню кликают стрелкой, не прицелом)
		if cur_arrow != null:
			Input.set_custom_mouse_cursor(cur_arrow, Input.CURSOR_ARROW, Vector2(0, 0))
		else:
			Input.set_custom_mouse_cursor(null)
		return
	if cur_move == null:
		Input.set_custom_mouse_cursor(null)
		return
	var e := _enemy_at(get_global_mouse_position())
	if e != null and cur_enemy != null:
		Input.set_custom_mouse_cursor(cur_enemy, Input.CURSOR_ARROW, Vector2(8, 8))
	else:
		Input.set_custom_mouse_cursor(cur_move, Input.CURSOR_ARROW, Vector2(8, 8))

func _unhandled_input(event: InputEvent) -> void:
	# Софтлок-страховка: блокировка ввода обязана жить только под открытым
	# диалогом или модалкой. Если оба окна закрыты, «разлок» был потерян
	# (несработавший колбэк фейда, панель, закрытая не через advance()): ветка
	# ниже глушила весь ввод — E только листал бы диалог, F5/F9 не доходили,
	# движение гейтилось в player.gd. input_locked при этом не сериализуется,
	# так что залипание переживало быструю загрузку и снималось только
	# рестартом процесса. Снимаем его при первом же вводе и обрабатываем
	# событие штатно (F9, например, сразу сработает).
	if GameState.input_locked and not hud.is_dialog_open() and not hud.is_modal_open():
		GameState.input_locked = false
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
				if player.global_position.y > ASHEN_OFFSET.y:
					apply_area("ashen", false)  # F9 из Пепелища: сейв не знает про in_ashen
			player.apply_class()
			hud.refresh_skills()
			_apply_chest_states()  # сундуки после F9-загрузки (фикс T2)
			GameState.toast.emit("Игра загружена (F9)")
		else:
			GameState.toast.emit("Сохранение не найдено")
	# --- скиллы и зелье (атака ЛКМ опрашивается в player.gd) ---
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
	Achv.on_herb_drunk()  # ачивка «Травник» (achv.gd §2 #11)
	var _hp0 := GameState.hp  # heal-число = реально восстановленные HP
	GameState.heal(3)
	DmgNumbers.spawn(player.global_position + Vector2(0, -12), GameState.hp - _hp0, "heal")
	GameState.quest_changed.emit()  # автосейв + обновление HUD
	GameState.toast.emit("Лесное зелье: +%d HP" % (GameState.hp - _hp0))  # факт долечено (QA F1)

# --- маркер цели квеста ---

## Мировые координаты текущей цели для HUD-стрелки (Vector2.INF — цели нет).
func objective_pos() -> Vector2:
	var target := _objective_raw()
	if target == Vector2.INF or player == null:
		return Vector2.INF
	# цель в другой зоне — стрелка ведёт к переходу
	# эвристика «y > CAVE_OFFSET.y - 1000» одна только не различает два «этажа»
	# ниже деревни: у Пепелища (y=9600) она звала бы в пещеру
	var target_zone := "village"
	if target.y > ASHEN_OFFSET.y - 1000.0:
		target_zone = "ashen"
	elif target.y > CAVE_OFFSET.y - 1000.0:
		target_zone = "cave"
	if target_zone != active_area:
		if active_area == "cave" and dungeon_zone != null and dungeon_zone.stairs_node != null:
			return dungeon_zone.stairs_node.global_position
		if active_area == "ashen":
			if ashen_grid != null and ashen_grid.portal_node != null:
				return ashen_grid.portal_node.global_position  # наружу — через выжженную аршину
			return target
		if target_zone == "cave":
			return tile_to_world(CAVE_ENTRANCE_TILE)
		return tile_to_world(ASHEN_ENTRANCE_TILE)
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

func _apply_chest_states() -> void:
	# Страховка после загрузки: при старте сущности уже спавнятся с загруженным
	# состоянием, но F9 (quickload) приходит в живой мир, где сундуки старее сейва.
	# Идемпотентно (refresh_used только включает «использован»).
	for n in village_zone.get_children():
		if n.get("kind") != null and n.get("kind") == "chest" and n.has_method("refresh_used"):
			n.refresh_used()

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
	if active_area == "ashen" and ashen_grid != null:
		return {"w": ashen_grid.map_w, "h": ashen_grid.map_h, "walk": ashen_grid.cell_walkable, "base": ASHEN_OFFSET}
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

## Смена активной зоны (легаси-API пещеры): true — пещера, false — деревня.
## teleport=false — позиция останется из сейва (загрузка).
func apply_zone(to_cave: bool, teleport: bool = true) -> void:
	apply_area("cave" if to_cave else "village", teleport)

## Смена активной области: "village" | "cave" | "ashen". Общее правило: видима и
## жива (PROCESS_MODE_INHERIT) только активная — остальные снимаются с физики.
## GameState.in_cave остаётся «пещерным» флагом: в Пепелище герой НЕ в пещере.
func apply_area(area: String, teleport: bool = true) -> void:
	var prev := active_area
	active_area = area
	var to_cave := area == "cave"
	GameState.in_cave = to_cave
	village_zone.visible = area == "village"
	cave_zone.visible = to_cave
	ashen_zone.visible = area == "ashen"
	village_zone.process_mode = Node.PROCESS_MODE_INHERIT if area == "village" else Node.PROCESS_MODE_DISABLED
	cave_zone.process_mode = Node.PROCESS_MODE_INHERIT if to_cave else Node.PROCESS_MODE_DISABLED
	ashen_zone.process_mode = Node.PROCESS_MODE_INHERIT if area == "ashen" else Node.PROCESS_MODE_DISABLED
	near.clear()
	player.cancel_orders()  # приказы прошлой зоны не тянем в новую
	if teleport:
		if area == "cave":
			village_return_pos = player.global_position
			if dungeon_zone != null:
				player.global_position = CAVE_OFFSET + dungeon_zone.spawn_world_pos
		elif area == "ashen":
			ashen_return_pos = player.global_position
			if ashen_grid != null:
				player.global_position = ASHEN_OFFSET + ashen_grid.spawn_world_pos
		elif prev == "ashen":
			player.global_position = ashen_return_pos if ashen_return_pos != Vector2.INF else tile_to_world(spawn_tile)
		else:
			player.global_position = village_return_pos if village_return_pos != Vector2.INF else tile_to_world(spawn_tile)
	_set_cam_limits(area)
	if atmosphere != null:
		# Пепелище — НАЗЕМНЫЙ тон: пещерной палитры не просим (false), серый
		# холодок зоны рисует сам ashen_zone (self_modulate тайлмапа)
		atmosphere.zone_changed(to_cave)
	# музыка по зоне: пещера — своя тема, Пепелище — тот же мрачный трек (новых
	# ассетов не заводим), выход — лес (кроссфейд внутри GameAudio)
	GameAudio.music("cave" if to_cave or area == "ashen" else "forest")

func _set_cam_limits(area: String) -> void:
	if area == "cave" and dungeon_zone != null:
		cam.limit_left = int(CAVE_OFFSET.x)
		cam.limit_top = int(CAVE_OFFSET.y)
		cam.limit_right = int(CAVE_OFFSET.x) + int(dungeon_zone.map_w) * TILE
		cam.limit_bottom = int(CAVE_OFFSET.y) + int(dungeon_zone.map_h) * TILE
	elif area == "ashen" and ashen_grid != null:
		cam.limit_left = int(ASHEN_OFFSET.x)
		cam.limit_top = int(ASHEN_OFFSET.y)
		cam.limit_right = int(ASHEN_OFFSET.x) + int(ashen_grid.map_w) * TILE
		cam.limit_bottom = int(ASHEN_OFFSET.y) + int(ashen_grid.map_h) * TILE
	else:
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = map_w * TILE
		cam.limit_bottom = map_h * TILE

## Плавный переход: затемнение -> смена зоны -> просветление.
## after — что сделать после (обычно диалог); без него просто снимаем блокировку ввода.
func transition_to(to_cave: bool, after: Callable = Callable()) -> void:
	transition_to_area("cave" if to_cave else "village", after)

func transition_to_area(area: String, after: Callable = Callable()) -> void:
	GameState.input_locked = true
	var t := get_tree().create_tween()
	t.tween_property(fade_rect, "color:a", 1.0, 0.25)
	t.tween_callback(apply_area.bind(area))
	t.tween_property(fade_rect, "color:a", 0.0, 0.25)
	t.tween_callback(func():
		if after.is_valid():
			after.call()
		elif not hud.is_dialog_open():
			# Хвост фейда не имеет права отпирать ввод, если поверх перехода
			# открылся диалог (например, смерть в момент затемнения): иначе
			# панель останется видимой при разблокированном вводе и advance()
			# станет недостижим — лок снимет только закрытие диалога.
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

## Восточные «выжженные полы»: вход по E у аршины "A", как пещера — по E у "T".
## Первый заход — диалог ashen_intro (когда допишут ключ) или тост-заглушка;
## флаг seen — в GameState.flags (сейв v2-совместимо, новых полей не заводим).
func enter_ashen() -> void:
	if active_area == "ashen":
		return
	var first: bool = String(GameState.flags.get("ashen.intro_seen", "")) != "1"
	transition_to_area("ashen", func():
		if first:
			GameState.set_flag("ashen.intro_seen", "1")
			if FirstHint.I != null: FirstHint.I.show_hint("ashen", "Пепелище опаснее пещеры: силы тут не жалеют. Отступай к аршине.")
			if dialogues.has("ashen_intro"):
				start_dialogue("ashen_intro")
				if not hud.is_dialog_open():
					GameState.input_locked = false
			else:
				GameState.input_locked = false
				GameState.toast.emit("Пепелище: воздух стоит от золы. С дальней поляны на вас смотрит ведьма...")
		else:
			GameState.input_locked = false)

func exit_ashen() -> void:
	if active_area != "ashen":
		return
	transition_to_area("village")

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
							GameState.herbs = 0  # травы реально отданы (фикс T6)
							GameState.add_xp(25)
							GameState.heal_full()
							GameState.quest_changed.emit())  # автосейв: квест закрыт, повторной сдачи нет (фикс T1)
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
							GameState.add_xp(30)  # урон теперь от класса/меча/амулета
							GameState.quest_changed.emit())  # автосейв: квест закрыт, повторной сдачи нет (фикс T1)
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
		"smith":
			start_dialogue("smith", func(): Shop.open())
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
	if FirstHint.I != null: FirstHint.I.show_hint("death", "Смерть — не конец: воскреснешь обновлённым, всё собранное остаётся.")
	start_dialogue("death", func(): respawn_player())

func respawn_player() -> void:
	player.cancel_orders()
	if active_area == "ashen" and ashen_grid != null:
		player.global_position = ASHEN_OFFSET + ashen_grid.spawn_world_pos
	elif GameState.in_cave and dungeon_zone != null:
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

class AshenGate:
	extends Area2D
	## Выжженная аршина на восточной окраине (тайл "A"): вход в Пепелище по E,
	## симметрично лестнице пещеры. Тайл "A" проходим (CHAR_TO_TILE -> 3, грунт),
	## визуальный портал — спрайт из ashen_tiles.png (тайл 7), новых ассетов нет.
	var world
	func setup(p_world: Node2D, tile: Vector2i) -> void:
		world = p_world
		position = world.tile_to_world(tile)
		if ResourceLoader.exists("res://assets/ashen_tiles.png"):
			var spr := Sprite2D.new()
			var at := AtlasTexture.new()
			at.atlas = load("res://assets/ashen_tiles.png")
			at.region = Rect2(7 * 16, 0, 16, 16)
			spr.texture = at
			add_child(spr)
		else:
			push_warning("Нет ассета: assets/ashen_tiles.png — заглушка входа в Пепелище")
			var ph := ColorRect.new()
			ph.color = Color(0.35, 0.32, 0.4)
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
		return "Войти в Пепелище"
	func try_interact() -> void:
		world.enter_ashen()
	func _on_enter(b: Node) -> void:
		if b.is_in_group("player"):
			world.near.append(self)
	func _on_exit(b: Node) -> void:
		if b.is_in_group("player"):
			world.near.erase(self)
