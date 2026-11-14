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
	5: [6, 6, 0, 5],     # дерево: ствол с основанием по атласу (колонки 5..11, ряды 10..16), крона проходима
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
## t52 СНОС арт-волны 3 (закон пользователя 13.11, VISUAL_REBUILD.md «план
## сноса»): весь qwen-image ген-арт убран из игры — рощи (GroveCanopy),
## деревенские пропсы (VillageProps), env4-пропы, «живая земля»/тропы и
## «живые полы» пещеры/Пепелища. Мир = базовый пиксельный атлас + ручные
## актёры + код-арт UI. ИНФРАСТРУКТУРА y-sort (ниже) СОХРАНЕНА: списки
## _ys_canopies/_ys_props_dim пусты, механика ждёт пропсы ручной прорисовки
## (t53+). Коллайдеры, CHAR_TO_TILE, POI (костёр/сундук/портал) — бит-в-бит.
## V-01..V-04 (волна «Тени-3»): ОБЩЕЕ пространство глубины актёров и пропсов.
## Слой-«пятёрка» (GroveCanopy/VillageProps/Env4Props) упорядочивал пропсы только
## МЕЖДУ СОБОЙ и всегда рисовался поверх актёров (z 0): герой «съедался» избами,
## кронами и алтарями с любой стороны. Переход: z_index высокого пропа = его
## СТОПА (глобальный Y нижнего края спрайта, абсолютный z), z_index актёра
## (герой, мобы, NPC) = его стопа на той же шкале. Порядок пропс-против-пропа
## остаётся порядком стоп (честный y-sort канон), но отношение «актёр vs проп»
## становится корректным с обеих сторон. Коллайдеры/блокировка/геометрия — бит-в-бит.
## Ограничение движка: z_index клампится в [-4096..4096], а «этажи» зон лежат на
## +4800/+9600 (CAVE_OFFSET/ASHEN_OFFSET) — поэтому общая шкала ЦИКЛИЧНА:
## z = fposmod(Y, 4800). Этажи разнесены на 4800 px при высоте карты ≤480 px,
## в одном кадре двух «этажей» не бывает — свёртка в локальную глубину безопасна.
const YS_CYCLE := 4800.0         # шаг «этажей» зон == CAVE_OFFSET.y (ASHEN — кратно)
const YS_ACTOR_BIAS := 8         # t51 (16px-мир): стопа актёра ≈ +8 ниже центра ноды (узел в центре 16px-кадра)
const YS_CANOPY_DIM_AT := 0.5    # крона «растворяется», когда закрывает >= 50% бокса героя (крона над героем)
const YS_CANOPY_DIM_ALPHA := 0.5 # целевая alpha кроны при нависании (паттерн Glimpse/T3)
const YS_PROP_DIM_AT := 0.4      # t41: мелкий проп деревни димится, когда накрывает >= 40% бокса героя
                                 # (порог ниже крон: пропы мелкие, цель — hero visibility на тяжёлых тайлах)
const YS_HUD_Z := 4000           # цифры урона поверх любой глубины: локальная y зон ≤ 480 << 4000 ≤ 4096
const CAVE_OFFSET := Vector2(0, 4800.0)      # «этаж» пещеры в общих координатах
const CAVE_ENTRANCE_TILE := Vector2i(40, 17) # вход в пещеру в лесу (тайл проходим: T)
const ASHEN_OFFSET := Vector2(0, 9600.0)     # «этаж» Пепелища в общих координатах
const ASHEN_ENTRANCE_TILE := Vector2i(45, 20) # «A» — выжженная аршина на восточной окраине
## Ключи зоны для сида забега (CONTRACT_PROCGEN §2) — аргументы ProcGen.seed_zone.
const CAVE_ZONE_ID := "cave"
const ASHEN_ZONE_ID := "ashen"
## Костры-привалы (id -> тайл). Ровно один на мир — фидбек игрока: «не более
## одного, и то реже» (варка/отдых = осознанная редкость). Одноразовый.
const CAMPFIRE_SPOTS := {
	"cf_village": Vector2i(18, 13),
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
var quest_marker: CanvasLayer  # t19: стрелка цели квеста (scripts/quest_marker.gd)
var near: Array = []
var hint_label: Label
var village_zone: Node2D
var village_v4: Node2D  # t54: слой «Деревня v4» (VillageArt) — пропы кодоген-атласа
var cave_v1: Node2D     # c3: слой «Пещера v1» (CaveArt) — алтарь/сундук/сталагмиты
# t52 снос: GroveCanopy/VillageProps/Env4Props/живая земля сняты (VISUAL_REBUILD
# «план сноса»).
var _ys_canopies: Array = []   # Sprite2D крон — overhead-дим по герою (V-01/V-07); пусто с t52
var _ys_props_dim: Array = []  # Sprite2D мелких пропов — дим-контракт по герою;
                               # с t54/c3 заполнен кодоген-пропами village/ и cave/
var cave_zone: Node2D
var dungeon_zone  # scripts/dungeon_zone.gd (типизирован слабо — API: setup/spawn_world_pos/map_w/map_h)
var ashen_zone: Node2D
var ashen_grid    # scripts/ashen_zone.gd (слабо: setup/spawn_world_pos/map_w/map_h/portal_node)
## Шов PROCGEN §2: словари карт из ProcGen (T1 — прокси, читающий data/map_*.json
## как есть). Зоны пока грузят JSON сами в setup(); передача словаря генератору —
## задача T4/T5, здесь поле-приёмник фиксирует сам шов.
var cave_map: Dictionary = {}
var ashen_map: Dictionary = {}
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
	# t46 (F1): ЕДИНАЯ очистка реестра стай при старте мира — ПЕРВОЙ строкой, до
	# спавна всего живого. mob_swarmling.SWARMS — static: переживает
	# reload_current_scene (смерть-ретрай/NG+, хук ниже); осиротевшие записи
	# старого круга иначе мержатся с новым миром (ложная паника при рождении,
	# «статуи» с нулевым flee_dir, бессмертный ghost-alive). Чистится ВЕСЬ словарь
	# — это тот же реестр у ключей glade_west/ashen_brood/witch_guard/brute_ash_*;
	# новый мир заведёт свои записи сам в setup(). Телепорты внутри забега
	# (apply_area/enter_ashen) сцену не реломят — легитимные стаи живого круга
	# не затрагиваются.
	load("res://scripts/mob_swarmling.gd").reset_registry()
	# Звук: единственный экземпляр GameAudio создаём ПЕРВЫМ — любой _ready ниже
	# (hud, slime, campfire) уже может звать GameAudio.sfx(...) без проверки.
	var audio := GameAudio.new()
	add_child(audio)
	GameAudio.I = audio
	GameAudio.music("forest")
	# t31: процедурный Sfx-движок — сразу за GameAudio, чтобы при _ready он
	# унаследовал уже прочитанные им громкости, а meta-хранилище (audio.*)
	# применилось поверх. Хостинг как у GameAudio/ClickMove: экземпляр + static I.
	var sfx_host := Sfx.new()
	add_child(sfx_host)
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
	# «Мягкий мир» (волна 3): контейнеры зон с texture_filter=LINEAR — тайлы,
	# сущности, кроны и пропсы наследуют сглаживание (живописная стилистика без
	# пиксельной сетки). Физика/координаты не двигаются: фильтр — только вывод.
	# HUD/Minimap/Journal — CanvasLayer-поддеревья вне зон, не затронуты.
	village_zone = Node2D.new()
	village_zone.name = "Village"
	village_zone.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(village_zone)
	cave_zone = Node2D.new()
	cave_zone.name = "Cave"
	cave_zone.position = CAVE_OFFSET
	cave_zone.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(cave_zone)
	ashen_zone = Node2D.new()
	ashen_zone.name = "Ashen"
	ashen_zone.position = ASHEN_OFFSET
	ashen_zone.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(ashen_zone)
	_build_tiles()
	_build_walls()
	_spawn_player()
	_spawn_entities()
	_build_campfires()
	_build_village_v4()
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
	# t19 (P0-2Б): мировая стрелка цели квеста — отдельный слой (указание капитана:
	# на время t23 в hud.gd не входить). Добавляемся сразу за hud, тот же layer 1.
	quest_marker = load("res://scripts/quest_marker.gd").new()
	add_child(quest_marker)
	quest_marker.setup(self)
	add_child(Journal.new())  # журнал квестов (J): quests_data.gd + journal.gd, самодостаточен
	add_child(Shop.new())  # лавка Гриима: скрыта по умолчанию; после Journal — Esc у Shop приоритетнее
	add_child(SettingsMenu.new())  # меню настроек (Esc): как GameAudio — узел стартует скрытым
	add_child(RunSummary.new())  # «Забег окончен» (смерть-петля §1.8): скрыта; последняя из модалок — её Esc приоритетнее
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
	# Экспозиционный тост-завязка: мир и ставка в одну строку (TEXT-AUDIT В1).
	# 77 зн < лимита тоста (~110), в HUD-баннер влезает без переноса.
	GameState.toast.emit("Морхейм на краю леса. Дым, хворь, слаймы у опушки — и старейшина при смерти.")
	if FirstHint.I != null: FirstHint.I.show_hint("controls_shown", "Все клавиши — в Меню (Esc), раздел «Управление».")

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
	# t54 (вердикт «Деревня v4 — внедряем»): пол деревни — v4-атлас кодогенерации
	# (PixelPalette-рампы GRASS/PATH/WATER/CLOTH/FIRE, тот же модуль, что и пропы).
	# Лес/деревня ходят по нему; «дикая» природа пещеры/Пепелища — своими атласами.
	var v4src := TileSetAtlasSource.new()
	v4src.texture = load(VillageArt.FLOOR_PATH)
	v4src.texture_region_size = Vector2i(TILE, TILE)
	for i in VillageArt.FLOOR_SIZE.x / TILE:
		v4src.create_tile(Vector2i(i, 0))
	ts.add_source(v4src, 1)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.z_index = -10
	village_zone.add_child(layer)
	for y in map_h:
		var row := String(map_rows[y])
		for x in map_w:
			var ch := row[x]
			if VillageArt.FLOOR_SLOTS.has(ch):
				layer.set_cell(Vector2i(x, y), 1, Vector2i(int(VillageArt.FLOOR_SLOTS[ch]), 0))
			elif CHAR_TO_TILE.has(ch):
				var idx := int(CHAR_TO_TILE[ch])
				if idx in [6, 7, 8, 13]:
					# W/R/D («изба») и «s» (указатель) с t54 рисуются v4-спрайтами
					# из атласа — под ними обычная трава; СЕТКА и BLOCKING бит-в-бит.
					layer.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
				else:
					layer.set_cell(Vector2i(x, y), 0, Vector2i(idx, 0))

## Глубина пропа по канону стоп (V-01): абсолютный z = глобальный Y нижнего края
## картинки (стопа). z_as_relative=false — радиус действия слоя (z 5) больше не
## перекрывает актёров; порядок пропсов внутри слоя не меняется (стопы тех же
## кластеров монотонны по y-sort), но актёр южнее стопы теперь честно поверх.
## Внутренний offset спрайта (в домасштабных пикселях) учитывается до to_global.
func _ys_prop(spr: Sprite2D) -> void:
	var tex := spr.texture
	if tex == null:
		return
	spr.z_as_relative = false
	var foot_local := Vector2(0.0, float(tex.get_height()) * 0.5 + spr.offset.y)
	spr.z_index = int(round(fposmod(spr.to_global(foot_local).y, YS_CYCLE)))


## FNV-1a по клетке: общий хэш-хелпер детерминизма (без randi) — мир
## воспроизводится бит-в-бит (D3). t52: после сноса пропсов остаётся как
## первоисточник канонической копии из procgen-секции ниже.
func _env4_hash(x: int, y: int) -> int:
	var h := 2166136261
	for b in [x & 0xFF, (x >> 8) & 0xFF, y & 0xFF, (y >> 8) & 0xFF]:
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return h

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
			if idx in [6, 7, 8]:
				# t54: W/R/D — клетки избы в сетке (BFS-зеркало qa_vlg не трогать!),
				# но ФИЗИКА теперь у самого спрайта избы (VillageArt: честный
				# силуэт 35×32 вместо невидимых стен блока 96×64).
				continue
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
	# герой живёт НЕ в контейнере зоны (общие координаты, телепорты между «этажами»),
	# «мягкий мир» ставим ему прямо — иначе он один остался бы nearest на сглаженном мире
	player.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	player.position = tile_to_world(spawn_tile)
	add_child(player)
	cam = Camera2D.new()
	# t51 (закон пользователя 13.11): возврат масштаба «до Крупного мира» — зум 1
	# во всех зонах, в кадре 640×360 ~40×22.5 клетки. Лимиты — мировые пиксели,
	# Godot клампит вид-окно внутрь лимитов зоны, а _set_cam_limits переставляет
	# их на каждой смене зоны — герой всегда в кадре.
	cam.zoom = Vector2.ONE
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = map_w * TILE
	cam.limit_bottom = map_h * TILE
	player.add_child(cam)
	cam.make_current()
	Juice.attach_camera(cam)  # t18 «сочность»: мазок-тряска пишется в cam.offset (juice.gd)
	hint_label = Label.new()
	# текст world-space подсказок — не «картинка», держим пиксельную чёткость
	# (наследовать LINEAR от героя ему не надо)
	hint_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# t51: герой 16 px (макушка ~ -8) — подсказка «было» на (−45, −26)
	hint_label.position = Vector2(-45, -26)
	hint_label.size = Vector2(90, 10)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))  # t18: амбер = интерактив (канон цвета)
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_label.add_theme_constant_override("outline_size", 4)
	hint_label.add_theme_font_size_override("font_size", 8)
	player.add_child(hint_label)

func _spawn_entities() -> void:
	var npc_script := load("res://scripts/npc.gd")
	for e: Array in meta.get("npcs", []):
		var npc = npc_script.new()
		village_zone.add_child(npc)
		npc.add_to_group("ys_actor")  # V-01: общая глубина «стопа к стопе» с пропсами
		npc.setup(self, String(e[0]), Vector2i(int(e[1]), int(e[2])))
	# Кузнец Гриим (лавка): фиксированная точка, тайл 'g' walkable
	var smith = npc_script.new()
	village_zone.add_child(smith)
	smith.add_to_group("ys_actor")
	smith.setup(self, "smith", Vector2i(26, 13))
	var it_script := load("res://scripts/interactable.gd")
	for e: Array in meta.get("herbs", []):
		var herb = it_script.new()
		village_zone.add_child(herb)
		herb.setup(self, "herb", Vector2i(int(e[0]), int(e[1])))
	for e: Array in meta.get("chests", []):
		var chest = it_script.new()
		village_zone.add_child(chest)
		chest.setup(self, "chest", Vector2i(int(e[0]), int(e[1])), "village")  # D4: uid зоны
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
	# t39 grace: рой у старта урезан 4→2 и уведён в глубь западной поляны
	# (t38: 4 особи в 97 px — агрессивный новичок умирал за 9.9 с, а без ввода
	# блуждающая крыса доходила до героя к ~34 с). 2 особи = первое убийство
	# сразу включает панику стаи (alive*2<=total); 233+ px — ближайшая цель
	# агрессивного бота на старте теперь слайм (1-на-1), а не свалка 2-в-1;
	# плюс блуждание роя привязано к дому (mob_swarmling, t39) — пассивный
	# новичок крыс не дождётся.
	var rat_script := load("res://scripts/mob_swarmling.gd")
	for e: Array in [[4, 24], [3, 26]]:
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

## t54 (вердикт пользователя «внедряем в игру»): художественный слой деревни
## «Деревня v4» — кодоген-атласы листа t53 (docs/PIXEL_STYLE.md). Изба/колодец/
## указатель — спрайты VillageArt; костёр-POI перекрашен на v4-кадры. Сетка,
## CHAR_TO_TILE, коллайдеры мелких блокировщиков и POI — бит-в-бит (qa_vlg).
func _build_village_v4() -> void:
	village_v4 = VillageArt.build(self)
	for cf in campfires:
		VillageArt.restyle_campfire(cf)

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

## ---- Т14: перестройка пространства пещеры/Пепелища --------------------------
## Фидбек игрока: «в подземелье огромные алтари и порталы» — SCALE_CANON-пропы
## (алтарь 51 px, портал 70 px) не уменьшаются, вместо них генераторную сетку
## post-process'ят чистая геометрия: залы 5×6 вокруг каждого пропа и проходы
## шире 1 клетки. Позиции-якоря (spawn/stairs/door/chest/A/P/meta) НЕ двигаются;
## алфавит grid и CHAR_TO_TILE не трогаются; выемка только ДОБАВЛЯЕТ пол
## (монотонно) — старые POI остаются достижимы. Детерминизм: никаких randi,
## обход row-major, тай-брейки по хэшу клетки — два прогона дают бит-в-бит
## одинаковую сетку (стенд qa_lp сверяет снимки двух сборок).
## Никогда не вскрываются: внешний ранг "#", клетки «L»/«S»/«C»/«A»/«P» (их нет
## в dig-наборах), и защищённая ниша сундука — интерьер, достижимый из «C» без
## «L», плюс её настенная рамка: дверь остаётся ЕДИНСТВЕННЫМ входом к сундуку.

## Символы зон: floor-набор выемки, проходимые (для 2×2), вскрываемые блоки.
const RG_CAVE_WALK := ".,SBM"           # «L» (дверь) — блокировщик, не walk
const RG_CAVE_DIG := "#PRV"             # стена / колонна / осыпь / ниша-стена
const RG_ASHEN_WALK := ".,caP"          # портал «P» проходим
const RG_ASHEN_DIG := "#TK"             # бревно / дерево / пень

static func _rg_ch(grid: Array, x: int, y: int) -> String:
	if y < 0 or y >= grid.size():
		return ""
	var row := String(grid[y])
	if x < 0 or x >= row.length():
		return ""
	return row[x]

static func _rg_set(grid: Array, x: int, y: int, ch: String) -> void:
	var row := String(grid[y])
	grid[y] = row.substr(0, x) + ch + row.substr(x + 1)

static func _rg_key(x: int, y: int) -> int:
	return y * 4096 + x

## Копия FNV-1a из _env4_hash: тем же вектор входа — тот же бит-выход.
static func _rg_hash(x: int, y: int) -> int:
	var h := 2166136261
	for b in [x & 0xFF, (x >> 8) & 0xFF, y & 0xFF, (y >> 8) & 0xFF]:
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return h

## Защищённые клетки: интерьер ниши сундука (BFS от каждой «C»; «L» и стены —
## непроходимы) плюс все «#», примыкающие к интерьеру (в т.ч. по диагонали).
static func _rg_chest_protect(grid: Array, walk: String) -> Dictionary:
	var prot := {}
	for y in grid.size():
		var row := String(grid[y])
		for x in row.length():
			if row[x] != "C":
				continue
			var seen := {_rg_key(x, y): true}
			var stack: Array = [Vector2i(x, y)]
			while not stack.is_empty():
				var t: Vector2i = stack.pop_back()
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var n := t + Vector2i(int(d[0]), int(d[1]))
					var k := _rg_key(n.x, n.y)
					if seen.has(k):
						continue
					var ch := _rg_ch(grid, n.x, n.y)
					if ch != "C" and walk.find(ch) < 0:
						continue
					seen[k] = true
					stack.append(n)
			for k in seen:
				prot[k] = true
			for k in seen.keys():
				var cx := int(k) % 4096
				var cy := int(k) >> 12
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]:
					if _rg_ch(grid, cx + int(d[0]), cy + int(d[1])) == "#":
						prot[_rg_key(cx + int(d[0]), cy + int(d[1]))] = true
	return prot

## Выемка dig-символов в прямоугольнике x±hw, y−up..y+down; ранг и защита — табу.
static func _rg_hall(grid: Array, cx: int, cy: int, hw: int, up: int, down: int,
		dig: String, prot: Dictionary) -> void:
	var h := grid.size()
	for y in range(cy - up, cy + down + 1):
		if y < 0 or y >= h:
			continue
		var w := String(grid[y]).length()
		for x in range(cx - hw, cx + hw + 1):
			if x <= 0 or y <= 0 or x >= w - 1 or y >= h - 1:
				continue  # ранг не вскрываем никогда
			if prot.has(_rg_key(x, y)):
				continue
			if dig.find(_rg_ch(grid, x, y)) >= 0:
				_rg_set(grid, x, y, ".")

## Кандидатский квадрат 2×2 с клеткой (x,y) в углу (a,b): проходим?
## Возвращает [feasible, cost, cells] — cells только dig-клетки под выемку.
static func _rg_square(grid: Array, x: int, y: int, a: int, b: int,
		walk: String, dig: String, prot: Dictionary) -> Array:
	var h := grid.size()
	var cells: Array = []
	var cost := 0
	for dy in 2:
		for dx in 2:
			var cx := x - a + dx
			var cy := y - b + dy
			var w := String(grid[cy]).length() if cy >= 0 and cy < h else 0
			if cx <= 0 or cy <= 0 or cx >= w - 1 or cy >= h - 1:
				return [false, 0, []]
			var ch := _rg_ch(grid, cx, cy)
			if walk.find(ch) >= 0:
				continue
			if dig.find(ch) < 0 or prot.has(_rg_key(cx, cy)):
				return [false, 0, []]
			cost += 1
			cells.append(Vector2i(cx, cy))
	return [true, cost, cells]

## Есть ли у клетки проходимый квадрат 2×2 (клетка — в любом из 4 углов).
static func _rg_has_2x2(grid: Array, x: int, y: int, walk: String) -> bool:
	for a in [0, 1]:
		for b in [0, 1]:
			var ok := true
			for dy in 2:
				for dx in 2:
					if walk.find(_rg_ch(grid, x - a + dx, y - b + dy)) < 0:
						ok = false
			if ok:
				return true
	return false

## Найти выполнимый квадрат 2×2 (тот же порядок кандидатов, что у выемки):
## публичная проверка «тупик легален — вскрыть нечего».
static func _rg_feasible_2x2(grid: Array, x: int, y: int,
		walk: String, dig: String, prot: Dictionary) -> bool:
	var hsh := _rg_hash(x, y)
	var rot := hsh % 4
	for i in 4:
		var a: int = [0, 0, 1, 1][(rot + i) % 4]
		var b: int = [0, 1, 0, 1][(rot + i) % 4]
		var r := _rg_square(grid, x, y, a, b, walk, dig, prot)
		if bool(r[0]):
			return true
	return false

## Расширение проходов: каждая проходимая клетка обязана лежать в проходимом
## квадрате 2×2; если нет — вскрываем кандидатский квадрат с минимальной ценой
## (меньше спилить нельзя), порядок кандидатов — поворот от хэша клетки.
## Итерации до неподвижной точки (≤12; сетки 30×22/40×30 — миг).
static func _rg_widen(grid: Array, walk: String, dig: String, prot: Dictionary) -> void:
	var rounds := 0
	var changed := true
	while changed and rounds < 12:
		changed = false
		rounds += 1
		for y in grid.size():
			var row := String(grid[y])
			for x in row.length():
				if walk.find(row[x]) < 0:
					continue
				if _rg_has_2x2(grid, x, y, walk):
					continue
				var hsh := _rg_hash(x, y)
				var rot := hsh % 4
				var best_cells: Variant = null
				var best_cost := 99
				for i in 4:
					var a: int = [0, 0, 1, 1][(rot + i) % 4]
					var b: int = [0, 1, 0, 1][(rot + i) % 4]
					var r := _rg_square(grid, x, y, a, b, walk, dig, prot)
					if bool(r[0]) and int(r[1]) > 0 and int(r[1]) < best_cost:
						best_cost = int(r[1])
						best_cells = r[2]
				if best_cells != null:
					for c: Vector2i in best_cells:
						_rg_set(grid, c.x, c.y, ".")
					changed = true

## Пещера: зал 5×6 вокруг КАЖДОГО алтаря «A» (x±2, y−3..y+2 — пропс якорится
## нижней гранью, 51 px вершины стоят над свободным полом; правило «не более
## нижней трети высоты пропса пересекает стену») + расширение проходов.
static func _reshape_cave_map(p_map: Dictionary) -> void:
	var grid: Array = p_map.get("grid", [])
	if grid.is_empty() or String(grid[0]).is_empty():
		return
	var prot := _rg_chest_protect(grid, RG_CAVE_WALK)
	for y in grid.size():
		var row := String(grid[y])
		for x in row.length():
			if row[x] == "A":
				_rg_hall(grid, x, y, 2, 3, 2, RG_CAVE_DIG, prot)
	_rg_widen(grid, RG_CAVE_WALK, RG_CAVE_DIG, prot)

## Пепелище: зал 5×6 вокруг выходного портала (x±2, y−4..y+1 — портал 70 px,
# якорь у земли, вершина трещины высоко) + расширение проходов.
static func _reshape_ashen_map(p_map: Dictionary) -> void:
	var grid: Array = p_map.get("grid", [])
	if grid.is_empty() or String(grid[0]).is_empty():
		return
	var meta: Dictionary = p_map.get("meta", {})
	var prot := _rg_chest_protect(grid, RG_ASHEN_WALK)
	var portal := Vector2i(-1, -1)
	var pa: Array = meta.get("exit_portal", [])
	if pa.size() == 2:
		portal = Vector2i(int(pa[0]), int(pa[1]))
	if portal.x < 0:
		for y in grid.size():
			var xi := String(grid[y]).find("P")
			if xi >= 0:
				portal = Vector2i(xi, y)
				break
	if portal.x >= 0:
		_rg_hall(grid, portal.x, portal.y, 2, 4, 1, RG_ASHEN_DIG, prot)
	_rg_widen(grid, RG_ASHEN_WALK, RG_ASHEN_DIG, prot)

func _build_cave() -> void:
	# Шов PROCGEN §2: словарь карты — из ProcGen, сид = сид забега × «cave» × волна.
	# Порядок в _ready не двигается: билдеры и так стоят после load_game() (qa_rf).
	cave_map = ProcGen.cave_map(ProcGen.seed_zone(GameState.run_seed, CAVE_ZONE_ID, GameState.ng_wave()))
	# Т14: перестройка пространства ДО setup — тайлы, коллайдеры, миникарта,
	# якоря мобов и угли строятся уже из новой сетки (чанк ниже — чистая геометрия).
	_reshape_cave_map(cave_map)
	var dz = load("res://scripts/dungeon_zone.gd").new()
	cave_zone.add_child(dz)
	# Словарь-шов §2: карта пещеры строится генератором (как Пепелище в T5b);
	# битый/пустой dict dungeon_zone сам откатывает на эталон map_cave.json.
	dz.setup(self, cave_map)
	dungeon_zone = dz
	_spawn_cave_embers()
	_apply_cave_shapes(dz)
	# сундук открывают и в этой сессии: try_interact эмитит stats_changed — снимаем
	# коллайдер сразу, а не только после перезахода (пещера строится один раз)
	GameState.stats_changed.connect(_sync_cave_chest)
	_spawn_cave_mobs()
	_build_cave_v1()
	# T13: тенеплёты в нише босса убраны из геймплея полностью (вердикт
	# пользователя: напрягают). Скрипт-резерв и арт остаются в репозитории, но
	# активная логика их не загружает и не создаёт — ни в пещере, ни в иных зонах.
	cave_zone.visible = false
	cave_zone.process_mode = Node.PROCESS_MODE_DISABLED

## c3 (вердикт «1 внедряем; 2 сундук широкий; 3 — под вопросом»): визуальный
## слой «Пещера v1» — алтарь, широкий сундук над стандартной клеткой-коллайдером,
## сталагмиты в реестре дима, сталактиты «с потолка» над актёров. Кострище-мох
## НЕ размещается (ждёт отдельного вердикта). Сетка/BFS/коллайдеры не затронуты;
## нет атласов — слой не строится (легаси-вид).
func _build_cave_v1() -> void:
	cave_v1 = CaveArt.build(self)

## Первая проходимая клетка-«пол» ('.'/','), отсутствующая в banned: обход
## колец Chebyshev d_min..d_max от t0 (внутри кольца — row-major). Якоря/двери/
## сундуки/лестницы не «пол» — их клетки автоматически пропускаются.
## Нет кандидата (t0 вне карты, всё занято) — Vector2i(-1,-1).
func _cave_free_near(t0: Vector2i, d_min: int, d_max: int, banned: Array) -> Vector2i:
	if dungeon_zone == null:
		return Vector2i(-1, -1)
	var dz = dungeon_zone
	for d in range(d_min, d_max + 1):
		for y in range(t0.y - d, t0.y + d + 1):
			if y < 0 or y >= dz.map_rows.size():
				continue
			var row := String(dz.map_rows[y])
			for x in range(t0.x - d, t0.x + d + 1):
				if maxi(absi(x - t0.x), absi(y - t0.y)) != d:
					continue
				if x < 0 or x >= row.length():
					continue
				var ch: String = row[x]
				if ch != "." and ch != ",":
					continue
				var t := Vector2i(x, y)
				if t in banned:
					continue
				return t
	return Vector2i(-1, -1)

## Тлеющие угли — из сетки (T4): по одному у каждого якоря-ориентира ручной
## расстановки (у входа, у комнаты отшельника, у зала босса) на ближайшей
## проходимой «.,»-клетке (кольца 1..2). На генераторной карте прежние три
## фиксированные точки легли бы в стены.
func _spawn_cave_embers() -> void:
	if dungeon_zone == null:
		return
	var m: Dictionary = dungeon_zone.loaded_map
	for key: String in ["spawn", "hermit", "boss"]:
		var a: Array = m.get(key, [])
		if a.size() != 2:
			continue
		var spot := _cave_free_near(Vector2i(int(a[0]), int(a[1])), 1, 2, [])
		if spot == Vector2i(-1, -1):
			continue
		var e := Fx.ember_bed(Vector2(spot.x * TILE + 8, spot.y * TILE + 10))
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

## Расстановка мобов — ProcGen.place_units (T3, профили волн
## data/proc_profiles.json) на фактической карте пещеры. Мануальные литералы
## удалены: золотой эталон (legacy_seed 0 = 11 брутов ручной карты) держит
## золотой тест T3, world его не воспроизводит. Вид/ярус/клетка — из units[]
## (row-major, капсы/полосы — профиль); интервалы и POI-запретники внутри
## place_units.
func _spawn_cave_mobs() -> void:
	if dungeon_zone == null:
		return
	var dz = dungeon_zone
	if dz.loaded_map.is_empty():
		return
	var zone_seed := ProcGen.seed_zone(GameState.run_seed, CAVE_ZONE_ID, GameState.ng_wave())
	var res: Dictionary = ProcGen.place_units(zone_seed, dz.loaded_map, "cave", GameState.ng_wave())
	for u: Variant in res.get("units", []):
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var pos: Array = (u as Dictionary).get("pos", [])
		if pos.size() < 2:
			continue
		var t := Vector2i(int(pos[0]), int(pos[1]))
		if not dz.cell_walkable(t):
			continue
		var m = load("res://scripts/brute.gd").new()
		m.boss = false
		# t39: полосы глубины (bands) остаются как есть — золотой тест T3 про
		# place_units не трогает, — но ранг брута режется по волне забега
		# (w≤2→т1, w3→т2, w4+→т3): волна 2 перестаёт быть скачком ×3,7.
		m.tier = mini(int((u as Dictionary).get("tier", 1)), GameState.brute_max_tier(GameState.ng_wave()))
		dz.add_child(m)
		m.setup(self, t)

func _build_cave_entrance() -> void:
	var stairs := CaveStairs.new()
	village_zone.add_child(stairs)
	stairs.setup(self, CAVE_ENTRANCE_TILE)

## Пепелище: контейнер ashen_zone уже в _ready (сдвиг ASHEN_OFFSET). Зона
## строится после load_game() — персист ведьмы/сундука читается из флагов.
func _build_ashen() -> void:
	# Шов PROCGEN §2: как у пещеры — ProcGen-словарь на сиде забега × «ashen» × волна.
	# T5b: зона строится ИЗ ЭТОГО СЛОВАРЯ (setup принимает dict: grid+meta, байты
	# grid — канон тайлов map_ashen.json). data/map_ashen.json остаётся на диске
	# деревенским эталоном — ashen_zone читает его только как fallback пустого dict.
	ashen_map = ProcGen.ashen_map(ProcGen.seed_zone(GameState.run_seed, ASHEN_ZONE_ID, GameState.ng_wave()))
	# Т14: зал выходного портала + проходы ≥2 — та же чистая геометрия, что у пещеры.
	_reshape_ashen_map(ashen_map)
	var az = load("res://scripts/ashen_zone.gd").new()
	ashen_zone.add_child(az)
	az.setup(self, ashen_map)
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

## V-01..V-04: единая шкала глубины актёров и пропсов каждый кадр. Пропсы уже
## получили z=стопа при постройке (_ys_prop); здесь его получают актёры: герой,
## мобы (группа "enemy", включая боссов и отпрысков) и NPC ("ys_actor").
## Кроны (overhead) гаснут до YS_CANOPY_DIM_ALPHA, пока накрывают >= 50% бокса
## героя И рисуются над ним (герой северее стопы кроны); южнее стопы герой сам
## поверх кроны. t41: тот же overhead-дим для мелких пропов деревни с порогом
## YS_PROP_DIM_AT (40%) — знак/костёр/колодец не должны «съедать» героя.
## Цифры урона поднимаются над всей z-шкалой зон. Только порядок
## отрисовки: физика, коллайдеры, координаты не трогаются.
func _ys_update(delta: float) -> void:
	var hz := int(round(fposmod(player.global_position.y, YS_CYCLE))) + YS_ACTOR_BIAS
	player.z_index = hz
	for grp: String in ["enemy", "ys_actor"]:
		for n in get_tree().get_nodes_in_group(grp):
			var a := n as Node2D
			if a != null and is_instance_valid(a):
				a.z_index = int(round(fposmod(a.global_position.y, YS_CYCLE))) + YS_ACTOR_BIAS
	var dn := get_node_or_null("DmgNumbers")
	if dn == null and get_tree().current_scene != null and get_tree().current_scene != self:
		dn = get_tree().current_scene.get_node_or_null("DmgNumbers")  # мир вложен (харнессы)
	if dn is CanvasItem and (dn as CanvasItem).z_index < YS_HUD_Z:
		(dn as CanvasItem).z_index = YS_HUD_Z
	# t51 «было»: бокс героя = клетка 16 px: макушка −8, стопа +8 от центра ноды
	var hr := Rect2(player.global_position + Vector2(-8.0, -8.0), Vector2(16.0, 16.0))
	for c in _ys_canopies:
		var spr := c as Sprite2D
		if spr == null or not is_instance_valid(spr) or spr.texture == null:
			continue
		var target := 1.0
		if spr.z_index > hz:  # крона над героем (южнее — герой сам поверх, дим не нужен)
			var sz := Vector2(float(spr.texture.get_width()), float(spr.texture.get_height())) * spr.get_global_transform().get_scale().abs()
			var cr := Rect2(spr.get_global_transform().origin - sz * 0.5, sz)
			if cr.intersects(hr) and cr.intersection(hr).get_area() / maxf(hr.get_area(), 1.0) >= YS_CANOPY_DIM_AT:
				target = YS_CANOPY_DIM_ALPHA
		var a := spr.modulate.a
		# плавное растворение; в покое (вдали) — ровно 1.0, без «хвоста» лерпа
		a = target if absf(a - target) < 0.02 else lerpf(a, target, clampf(delta * 8.0, 0.0, 1.0))
		spr.modulate.a = a
	# t41: тот же контракт для мелких пропов (signpost/костёр/колодец/изба…),
	# порог ниже (YS_PROP_DIM_AT): пропы мелкие, но на тяжёлых тайлах закрывали до
	# 78% героя. Южнее героя (spr.z <= hz) проп и так под ним — дим не нужен, 1.0.
	# t48 (F1 t47): реестр общий с env4 (алтари пещеры, портал/сундук Пепелища) —
	# ставятся _env4_place; rect-гейт различает этажи (зоны в 4800 px друг от друга).
	for p in _ys_props_dim:
		var spr := p as Sprite2D
		if spr == null or not is_instance_valid(spr) or spr.texture == null:
			continue
		var target := 1.0
		if spr.z_index > hz:  # проп нарисован над героем (герой севернее стопы пропа)
			var sz := Vector2(float(spr.texture.get_width()), float(spr.texture.get_height())) * spr.get_global_transform().get_scale().abs()
			var cr := Rect2(spr.get_global_transform().origin - sz * 0.5, sz)
			if cr.intersects(hr) and cr.intersection(hr).get_area() / maxf(hr.get_area(), 1.0) >= YS_PROP_DIM_AT:
				target = YS_CANOPY_DIM_ALPHA
		var a := spr.modulate.a
		a = target if absf(a - target) < 0.02 else lerpf(a, target, clampf(delta * 8.0, 0.0, 1.0))
		spr.modulate.a = a

func _process(delta: float) -> void:
	if player == null:
		return
	_ys_update(delta)  # V-01: общая глубина «актёры + пропсы» каждый кадр
	# t20 P0-3: время забега для экрана смерти (rs.t, сек). Копится, пока мир
	# живёт (в т.ч. при открытом журнале/магазине — «время экспедиции», не чистое
	# время ввода); диалог смерти замораживает мир до снимка итогов — счёт честный.
	GameState.flags["rs.t"] = GameState._num(GameState.flags.get("rs.t", 0), 0) + delta
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
	_check_witch_done()
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
			GameAudio.sfx("ui_confirm")  # F5-успех (аудио-аудит)
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
			GameAudio.sfx("ui_confirm")  # F9-успех (аудио-аудит)
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
	DmgNumbers.spawn(player.global_position + Vector2(0, -12), GameState.hp - _hp0, "heal")  # t51: было −12
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
				return ashen_grid.portal_node.global_position  # наружу — через выжженную прогалину
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
	# t19 (P0-2Б): линия торговца — цель «вернуться сдать» становится маршрутом.
	# Пока слаймов не хватает — цели нет (лес открыт, стрелка на случайных слаймов
	# лишь мешала бы); как добыто — стрелка ведёт к Грииму.
	if int(GameState.slime_quest) == 1 and int(GameState.slime_kills_circle) >= 3:
		var me := _find_npc("merchant")
		if me != null:
			return me.global_position
	# --- линия пещеры (cave_state 0..3) ---
	if GameState.cave_state >= 4:
		# t19 (P0-2Б): амулет сдан — раньше цель была INF, и стрелка гасла на всю
		# NG-линию. Квест «Ведьма Пепелища» живёт на флаге ashen.boss: ведьма жива —
		# ведём на неё (из другой зоны objective_pos сам переключит на переход);
		# Пепелище ещё не построено — на вход. Ведьма мертва — цели нет, как раньше.
		if str(GameState.flags.get("ashen.boss", "")) != "dead":
			if ashen_grid != null and ashen_grid.boss_node != null and is_instance_valid(ashen_grid.boss_node):
				return ashen_grid.boss_node.global_position
			return tile_to_world(ASHEN_ENTRANCE_TILE)
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
	# t20 P0-3: зона гибели для экрана смерти — обновляем при каждой смене области.
	GameState.flags["rs.zone"] = area
	var to_cave := area == "cave"
	GameState.in_cave = to_cave
	village_zone.visible = area == "village"
	cave_zone.visible = to_cave
	ashen_zone.visible = area == "ashen"
	village_zone.process_mode = Node.PROCESS_MODE_INHERIT if area == "village" else Node.PROCESS_MODE_DISABLED
	cave_zone.process_mode = Node.PROCESS_MODE_INHERIT if to_cave else Node.PROCESS_MODE_DISABLED
	ashen_zone.process_mode = Node.PROCESS_MODE_INHERIT if area == "ashen" else Node.PROCESS_MODE_DISABLED
	near.clear()
	# t39: ведьма Пепелища масштабируется под уровень героя (mob_boss2.depth_scale) —
	# переливаем силу при каждом входе в зону (L1 19hp/1dmg … L6+ канон 48/3).
	if area == "ashen" and ashen_grid != null and ashen_grid.boss_node != null \
			and is_instance_valid(ashen_grid.boss_node) and ashen_grid.boss_node.has_method("refresh_depth"):
		ashen_grid.boss_node.refresh_depth()
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

## Восточные «выжженные полы»: вход по E у прогалины "A", как пещера — по E у "T".
## Первый заход — диалог ashen_intro (ключ дописан в dialogues_v2.json);
## флаг seen — в GameState.flags (сейв v2-совместимо, новых полей не заводим).
func enter_ashen() -> void:
	if active_area == "ashen":
		return
	var first: bool = str(GameState.flags.get("ashen.intro_seen", "")) != "1"
	transition_to_area("ashen", func():
		if first:
			GameState.set_flag("ashen.intro_seen", "1")
			# подсказка короче диалога ashen_intro и не повторяет его (TEXT-AUDIT Г3);
			# «аршина» из игрового текста убрана — термин не вводился (TEXT-AUDIT A5)
			if FirstHint.I != null: FirstHint.I.show_hint("ashen", "Пепелище опаснее пещеры: здесь не жалеют сил. Помни про выход — он рядом.")
			if dialogues.has("ashen_intro"):
				start_dialogue("ashen_intro")
				if not hud.is_dialog_open():
					GameState.input_locked = false
			else:
				GameState.input_locked = false
				GameState.toast.emit("Пепелище: воздух стоит от золы. С дальней поляны на тебя смотрит ведьма...")
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
							GameState.herbs -= 3  # сдаёт ровно три — излишек живёт в сумке (Q5-H1)
							GameState.add_xp(25)
							GameState.heal_full()
							GameState.quest_changed.emit())  # автосейв: квест закрыт, повторной сдачи нет (фикс T1)
					else:
						start_dialogue("elder_progress")
				_:
					# NPC-амнезия по кругам (TEXT-AUDIT B7): на волне N — узел
					# elder_after_<N> (один раз на волну), фолбэк — общий elder_after.
					# Волна — int через GameState.ng_wave() (clampi флага ng.wave).
					_dialog_once("elder_after", GameState.ng_wave(), func():
						start_dialogue("elder_after"))
		"merchant":
			match GameState.slime_quest:
				0:
					start_dialogue("merchant", func():
						GameState.slime_quest = 1
						GameState.quest_changed.emit())
				1:
					if GameState.slime_kills_circle >= 3:  # работа текущего круга (total — у ачивок)
						start_dialogue("merchant_done", func():
							GameState.slime_quest = 2
							GameState.add_xp(30)  # урон теперь от класса/меча/амулета
							GameState.quest_changed.emit())  # автосейв: квест закрыт, повторной сдачи нет (фикс T1)
					else:
						start_dialogue("merchant_progress")
				_:
					# Дран — имя и реакция на смерть босса (TEXT-AUDIT Б): один раз за
					# круг после закрытия квеста и победы над Громом (key q.merchant_boss
					# с префиксом q. — гасится start_ng_plus, как и полагается пер-круговой
					# вести); далее — обычный merchant_after.
					if GameState.boss_defeated and GameState.cave_state >= 2 \
							and str(GameState.flags.get("q.merchant_boss", "")) != "1":
						GameState.set_flag("q.merchant_boss", "1")
						start_dialogue("merchant_boss", func(): start_dialogue("merchant_after"))
					else:
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

## Диалог-вариант по волне: сначала "<base>_<wave>" — ровно ОДИН РАЗ НА ВОЛНУ,
## иначе — fallback. Дедуп-флаг намеренно БЕЗ точек и чужих префиксов
## ("dlg_<base>_<wave>"): QA-ассерт qa_q3 требует от флагов неймспейсы
## q./ach./meta./ng./daily./hint./ashen., а start_ng_plus стирает только
## q.*/ashen.*/ng.boss_*. Не стирается никогда — на повторных кругах кап-волны
## (номер не растёт) «волна-осведомлённая» сцена не повторяется, игрок слышит
## обычную elder_after. Волна 0 (обычная игра) — суффикса нет, сразу fallback.
## wave — int: GameState.ng_wave() = clampi(int-флаг ng.wave, 0, кап).
func _dialog_once(base: String, wave: int, fallback: Callable) -> void:
	if wave > 0 and dialogues.has("%s_%d" % [base, wave]):
		var key := "dlg_%s_%d" % [base, wave]
		if str(GameState.flags.get(key, "")) != "1":
			GameState.set_flag(key, "1")
			start_dialogue("%s_%d" % [base, wave])
			return
	if fallback.is_valid():
		fallback.call()

## Ведьма Пепелища пала, а Пепелище молчало (TEXT-AUDIT B8): «что дальше» —
## диалог witch_done прямо на арене, один раз за круг. Дедуп — флаг
## "ashen.witch_done" (префикс ashen. стирает start_ng_plus — на новом круге
## сцена законна заново) + гейт active_area=="ashen" (после выхода из зоны —
## не показываем, продолжение берёт на себя реплика Старейшины в npc.gd).
## Сигнал смерти от mob_boss2 не ловим — штатный персист ashen.boss=="dead";
## не лезем в фейд перехода (fade_rect) и поверх открытого диалога
## (смерть героя, интро зоны).
func _check_witch_done() -> void:
	if active_area != "ashen" or hud == null or fade_rect == null:
		return
	if GameState.input_locked or hud.is_dialog_open() or fade_rect.color.a > 0.01:
		return
	if str(GameState.flags.get("ashen.boss", "")) != "dead":
		return
	if str(GameState.flags.get("ashen.witch_done", "")) == "1" or not dialogues.has("witch_done"):
		return
	GameState.set_flag("ashen.witch_done", "1")
	start_dialogue("witch_done")

func on_player_death() -> void:
	Sfx.play("player_death")  # t31: низкий нисходящий тон (процедурный каталог) вместо «шлепка кожи»
	# t29 B-02 (реестр t28, blocker): смерть при открытой лавке хоронила диалог
	# смерти под вуалью лавки (диалог — hud, CanvasLayer 1; лавка — CanvasLayer 5):
	# все клики съедал полноэкранный dim лавки, Esc был мёртв, оставалось слепое E.
	# Смерть закрывает лавку — как журнал под чужим локом (journal.gd::_process);
	# порядок важен: закрыться до start_dialogue(), чтобы лавка успела отдать свой
	# lock (иначе show_dialog() поднял бы lock поверх, а close() лавки снял бы его).
	if Shop.is_open():
		Shop.close()
	# Смерть гасит забег (CONTRACT_RUNLOOP §1.1): респавна больше нет — после
	# диалога открывается модалка RunSummary, «Вспыхнуть заново» = start_new_run().
	if FirstHint.I != null: FirstHint.I.show_hint("death", "Смерть гасит забег: опыт и добыча сгорят. Но пепел, достижения и благословения алтаря — навсегда с тобой.")
	start_dialogue("death", func() -> void: RunSummary.open())

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
		if CaveArt.REGIONS.has("STAIRS") and ResourceLoader.exists(CaveArt.ATLAS_PATH):
			# c12 вердикт «вход в подземелье не каноничный»: арка — кодоген-кадр
			# STAIRS (16×24 ~1.5H) из cave_props_v1.png, та же, что и на обратной
			# стороне входа в пещере. Легаси-спрайт dungeon_tiles.png (кадр 5,
			# 218 вне-палитрных цветов на кадр) остаётся только фолбэком.
			# Стопа — нижняя граница клетки: нода на tile_to_world (+2 смещение),
			# центр кадра на -6 локально; z — общая шкала V-01 от стопы.
			var spr := Sprite2D.new()
			spr.texture = CaveArt.region_texture("STAIRS")
			spr.position = Vector2(0.0, -6.0)
			add_child(spr)
			world._ys_prop(spr)
		elif ResourceLoader.exists("res://assets/dungeon_tiles.png"):
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
	## Выжженная прогалина на восточной окраине (тайл "A"): вход в Пепелище по E,
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
