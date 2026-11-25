class_name Minimap
extends Node
## Миникарта «Тени Северного Леса»: радар ~64×64 px в правом верхнем углу экрана.
## ЛЕНИВЫЙ СИНГЛТОН в точности как ClickMove/GameAudio: static I, саморегистрация
## в _enter_tree, владелец (world._ready) создаёт узел и присваивает I — единственный
## интеграционный хук; без него узел можно добавить из любого места, он заработает.
##
## ЭКРАН, а не мир: собственный CanvasLayer(layer = 0) — выше мирового канваса
## (y-sort мобов его не касается), НИЖЕ hud (layer = 1): полосы/тосты HUD всегда
## поверх радара. z_index вуали радара поднят явно (100) на случай чужих
## CanvasItem-оверлеев на том же слое. Рамка — та же Kenney 9-slice
## assets/ui/panel_frame.png, что у окон hud/settings (region 32, поля 4); новых
## ассетов не рисуется. Тёмная палитра: фон почти чёрный, пол светлый «подсветкой»,
## стены тонут. Рамка — только КайМА: у StyleBox сердцевина непрозрачна, а Panel
## рисуется после _draw радара, поэтому draw_center=false (t49) — фоном поля
## считает paint().
##
## СОДЕРЖИМОЕ (текущая зона целиком; t7 «Туман открытия» 25.11: на карте мира
## туманная вуаль поверх тайлов/блипов — неизвестные клетки темнеют, блипы
## туманных порталов гаснут, герой всегда на открытой клетке): тайлы walk/wall кэшем
## ImageTexture (деревня — world.map_rows + CHAR_TO_TILE/BLOCKING, пещера —
## dungeon_zone.map_rows + cell_walkable, Пепелище — ashen_grid.map_rows +
## cell_walkable), герой — белая точка-маркер, мобы —
## красные (группа "enemy"; boss — крупнее и злее: мёртвый моб снят с группы,
## исчезает сам), костры жёлтые (погасший — тусклее), сундуки золотые (открытый —
## тусклее: village — interactable(kind="chest").used, cave — GameState.has_amulet),
## NPC белые, вход в пещеру/лестница выхода — голубые; аршина Пепелища (вход
## из деревни и портал наружу) — тоже голубые, сундук Пепелища золотится лишь
## пока цел (взят — узел снят, блипа нет), Ведьма — общий босс-блип группы
## "enemy"+"boss": убита (или мертва из сейва) — гаснет сама, без спец-кода.
##
## ПЕРЕКЛЮЧЕНИЕ ЗОНЫ: сигнала world.zone_changed в world.gd нет — поллинг 0.5 с
## (GameState.in_cave + гейт Пепелища по y героя (world.gd: y > ASHEN_OFFSET.y) +
## подпись карт: третья подпись — строки ashen_grid.map_rows). ПЕРЕВЫКЛЮЧАТЕЛЬ: внешний контракт как у
## ClickMove — статические is_on() -> bool / set_on(v: bool), персист
## user://minimap_cfg.json, дефолт ВКЛ; settings_menu резолвит его тем же
## паттерном (class_name-скрипт со статиками). Клавиша M (физический KEY_M,
## action не заводим — project.godot не трогаем) — toggle в живой игре; в
## диалоге/меню (GameState.input_locked) молчим.
##
## ЛЕНИВЫЕ СТРАХОВКИ: без мира/в мирном месте (_draw при world == null) — рамка
## и тишина, ни одного SCRIPT ERROR; отсутствующий ассет рамки — тёмная подложка.

const CFG_PATH := "user://minimap_cfg.json"
const FRAME_PATH := "res://assets/ui/panel_frame.png"
const SIZE := 64.0          # весь радар с рамкой, px (внутреннее поле 64 - 2*FRAME)
const FRAME := 4.0          # толщина 9-slice рамки (Kenney: регион 32, поля 4)
const PAD := 6.0            # отступ от правого верхнего угла экрана (как HUD-полосы)
const POLL := 0.5           # сек между проверками зоны/статичных POI
const TILE_SCALE := 1.0     # 1 тайл = 1 px (48x30 и 30x22 влезают в 56×56 целиком)

# --- палитра (тёмная) ---
const C_BG := Color(0.043, 0.051, 0.071)          # подложка радара
const C_FLOOR := Color(0.176, 0.204, 0.294)       # проходимый пол
const C_WALL := Color(0.055, 0.063, 0.090)        # стена (тонет в фоне)
const C_HERO := Color(0.957, 0.965, 1.0)          # герой
const C_MOB := Color(0.878, 0.337, 0.290)         # моб — красный
const C_BOSS := Color(1.0, 0.231, 0.188)          # босс — злее и крупнее
const C_FIRE := Color(1.0, 0.714, 0.282)          # костёр — жёлтый
const C_CHEST := Color(1.0, 0.824, 0.290)         # сундук — золотой
const C_NPC := Color(0.875, 0.902, 0.933)         # NPC — белый
const C_PORTAL := Color(0.345, 0.784, 1.0)        # вход в пещеру / выход — голубой
const C_GLADE := Color(0.373, 0.569, 0.251)       # Д2 поляна «лес запад» — LEAF MID (5f9140)
const C_DIM := 0.38                               # альфа «прошлого» POI (пепел/пустой)
# t7 «Туман открытия» (25.11): вуаль неизвестности карты мира — почти чёрная
# синева, рисуется поверх тайлов и блипов (герой стоит только на открытом).
const C_FOG := Color(0.020, 0.024, 0.036, 0.86)

static var I: Minimap              # синглтон; назначает world._ready (fallback — _enter_tree)
static var _enabled := true        # кэш user://minimap_cfg.json
static var _cfg_loaded := false

var world                          # узел world.gd (родитель); слабо, как у ClickMove
var _layer: CanvasLayer
var _radar: _Radar
var _zone := "village"             # зона нарисованных кэшей: "village" | "cave" | "ashen"
var _zone_seen := false            # хоть одна карта собрана?
var _grid_tex: ImageTexture = null # walk/wall текущей зоны (1px = 1 тайл)
var _grid_w := 0
var _grid_h := 0
var _pois: Array = []              # [{t=Vector2i, c=Color, s=int}] — костры/сундуки/NPC/порты
var _sig := ""                     # подпись зоны для поллинга: in_cave + сами rows (F9/пересборка)
var _poll_t := 0.0
# t7 «Туман открытия»: кэш вуали карты мира — пересборка только при смене
# версии GameState.wm_fog (или самого объекта: новый круг).
var _fog_obj = null
var _fog_ver := -1
var _fog_tex: ImageTexture = null

# --- переключатель: user://minimap_cfg.json (дефолт — ВКЛ), контракт ClickMove ---

static func is_on() -> bool:
	if not _cfg_loaded:
		_load_cfg()
	return _enabled

static func set_on(v: bool) -> void:
	_enabled = v
	_cfg_loaded = true
	var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Не удалось записать %s" % CFG_PATH)
		return
	f.store_string(JSON.stringify({"on": v}))

static func _load_cfg() -> void:
	_cfg_loaded = true
	_enabled = true
	if not FileAccess.file_exists(CFG_PATH):
		return
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		_enabled = bool(data.get("on", true))

# --- жизненный цикл (паттерн ClickMove) ---

func _enter_tree() -> void:
	if I == null:
		I = self

func _ready() -> void:
	world = get_parent()
	if world == null or not world.has_method("tile_to_world") or world.get("map_rows") == null:
		push_warning("Minimap добавлен не под узел world — миникарта молчит")
		world = null
	_build_ui()
	_poll_t = 0.0  # первый кадр: немедленная сборка
	set_process(true)

func _exit_tree() -> void:
	if I == self:
		I = null

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 0           # выше мирового канваса, ниже hud (1) / фейда (10) / настроек (20)
	_layer.name = "MinimapLayer"
	add_child(_layer)
	_radar = _Radar.new()
	_radar.mm = self
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar.z_index = 100       # «высокий z»: не перекрывается ничьими оверлеями того же слоя
	_radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# 6px от угла — тот же ритм, что у HUD-полос; полосы слева, пересечений нет
	_radar.offset_left = -PAD - SIZE
	_radar.offset_top = PAD
	_radar.offset_right = -PAD
	_radar.offset_bottom = PAD + SIZE
	_radar.visible = true      # сам радар видим всегда; гейт показа — _layer.visible
	                           # в _process (M/settings); скрытый CanvasLayer не показывает
	                           # детей, но видимый — НЕ показывает и скрытого ребёнка:
	                           # false здесь прятал миникарту навсегда (юзер-баг).
	_layer.add_child(_radar)
	_radar.build_frame()

func _process(delta: float) -> void:
	var ok := world != null and is_instance_valid(world)
	_layer.visible = ok and is_on()   # флаги статики: settings/M включают к следующему кадру
	if not _layer.visible:
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL
		# мира мог «не стать» (F9/пересборка): подпись зоны — гейт + сами rows
		# гейт Пепелища — тот же, что в world.gd: y героя > ASHEN_OFFSET.y
		# t3 «Мир v1»: единый источник зоны — world.active_area (village/cave/
		# ashen/worldmap/loc_<биом>). Фолбэк-цепочка по y — для сборок/стендов
		# без ключа (as is с t64, qa_mm-совместимо).
		var cave := bool(GameState.in_cave)
		var zone := String(world.get("active_area"))
		if zone == "":
			zone = "village"
			var ao: Variant = world.get("ASHEN_OFFSET")
			var pl = world.player
			if cave:
				zone = "cave"
			elif pl != null and is_instance_valid(pl) and ao is Vector2 and pl.global_position.y > (ao as Vector2).y:
				zone = "ashen"
		elif zone != "village" and zone != "cave" and zone != "ashen" \
				and zone != "worldmap" and not zone.begins_with("loc_") \
				and not zone.begins_with("mini_"):
			zone = "village"  # незнакомое значение — безопасная деревня
		var az = world.get("ashen_grid")   # слабая ссылка: null в сборках без Пепелища
		var prefix := "a" if zone == "ashen" else ("c" if zone == "cave" else ("v" if zone == "village" else zone))
		var rows_s: String
		if zone == "ashen" and az != null and is_instance_valid(az) and az.get("map_rows") != null:
			rows_s = str(az.map_rows)
		elif zone == "worldmap" or zone.begins_with("loc_") or zone.begins_with("mini_"):
			var zg = _world_grid(zone)
			rows_s = str(zg.map_rows) if zg != null else ""
		else:
			rows_s = str(world.map_rows)
		var sig := prefix + "|" + rows_s
		if sig != _sig:
			_sig = sig
			_zone = zone
			_rebuild_grid()
			_rebuild_pois()
	_radar.queue_redraw()

# --- сборка тайловой подложки (кэш: только при смене зоны) ---

func _rebuild_grid() -> void:
	_grid_tex = null
	_grid_w = 0
	_grid_h = 0
	var rows: Array
	var w := 0
	var h := 0
	if _zone == "worldmap" or String(_zone).begins_with("loc_"):
		# t3 «Мир v1»: карта мира и локации — свои rows/размеры (тот же приём,
		# что у Пепелища: сетку отдаёт сама зона).
		var zg = _world_grid(_zone)
		if zg == null or not is_instance_valid(zg) or zg.get("map_rows") == null:
			_zone_seen = false
			return
		rows = zg.map_rows
		h = int(zg.map_h)
		w = int(zg.map_w)
	elif _zone == "ashen":
		var az = world.ashen_grid
		if az == null or not is_instance_valid(az) or az.get("map_rows") == null:
			_zone_seen = false
			return
		rows = az.map_rows
		h = int(az.map_h)
		w = int(az.map_w)
	elif _zone == "cave":
		var dz = world.dungeon_zone
		if dz == null or not is_instance_valid(dz) or dz.get("map_rows") == null:
			_zone_seen = false
			return
		rows = dz.map_rows
		h = int(dz.map_h)
		w = int(dz.map_w)
	else:
		rows = world.map_rows
		h = int(world.map_h)
		w = int(world.map_w)
	if rows == null or w <= 0 or h <= 0:
		_zone_seen = false
		return
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var walk := _cell_walkable(rows, w, Vector2i(x, y))
			img.set_pixel(x, y, C_FLOOR if walk else C_WALL)
	_grid_tex = ImageTexture.create_from_image(img)
	_grid_w = w
	_grid_h = h
	_zone_seen = true

## Проходимость тайла: деревня — те же публичные константы world, что у
## ClickMove._tile_walkable; пещера — dungeon_zone.cell_walkable, Пепелище —
## ashen_grid.cell_walkable (закрытая дверь и взятый сундук уже учтены самими
## методами).
func _cell_walkable(rows: Array, w: int, t: Vector2i) -> bool:
	if _zone == "worldmap" or String(_zone).begins_with("loc_"):
		# t3: проходимость зон Мира — у самой зоны (скала/массы уже в SOLID)
		var zg = _world_grid(_zone)
		return zg != null and zg.cell_walkable(t)
	if _zone == "ashen":
		return world.ashen_grid.cell_walkable(t)
	if _zone == "cave":
		return world.dungeon_zone.cell_walkable(t)
	if t.y < 0 or t.y >= rows.size() or t.x < 0 or t.x >= w:
		return false
	var row := String(rows[t.y])
	if t.x >= row.length():
		return false
	var ch: String = row[t.x]
	if not world.CHAR_TO_TILE.has(ch):
		return true
	return not (int(world.CHAR_TO_TILE[ch]) in world.BLOCKING)

# --- статичные POI (поллинг 0.5 с: костры гаснут, сундуки открываются) ---

func _rebuild_pois() -> void:
	_pois.clear()
	var ts := float(world.TILE)
	if _zone == "worldmap":
		# t3: шесть порталов земель + обратная арка — портал-блипы
		var wg = world.get("worldmap_grid")
		if wg == null or not is_instance_valid(wg):
			return
		var pnodes: Variant = wg.get("portal_nodes")
		if pnodes is Dictionary:
			for z in (pnodes as Dictionary):
				var pn = (pnodes as Dictionary)[z]
				if pn != null and is_instance_valid(pn):
					_pois.append({"t": _tile_of((pn as Node2D).global_position, _zone_base(), ts), "c": C_PORTAL, "s": 3})
		var an = wg.get("arch_node")
		if an != null and is_instance_valid(an):
			_pois.append({"t": _tile_of((an as Node2D).global_position, _zone_base(), ts), "c": C_PORTAL, "s": 3})
		return
	if String(_zone).begins_with("loc_"):
		# t3: портал выхода + сундук локации (вскрытый — без блипа, как у Пепелища)
		var gz = _world_grid(_zone)
		if gz == null or not is_instance_valid(gz):
			return
		var pn = gz.get("portal_out_node")
		if pn != null and is_instance_valid(pn):
			_pois.append({"t": _tile_of((pn as Node2D).global_position, _zone_base(), ts), "c": C_PORTAL, "s": 3})
		var cn = gz.get("chest_node")
		if cn != null and is_instance_valid(cn) and cn.get("used") != true:
			_pois.append({"t": _tile_of((cn as Node2D).global_position, _zone_base(), ts), "c": C_CHEST, "s": 3})
		return
	if _zone == "ashen":
		var az = world.ashen_grid
		if az == null or not is_instance_valid(az):
			return
		if az.portal_node != null and is_instance_valid(az.portal_node):
			_pois.append({"t": _tile_of(az.portal_node.global_position, _zone_base(), ts), "c": C_PORTAL, "s": 3})
		# Взятый сундук снимает свой узел (queue_free) — блипа нет; флаг ashen.chest
		# закрывает и отложенный кадр до фактического удаления узла.
		if az.chest_node != null and is_instance_valid(az.chest_node) \
				and str(GameState.flags.get("ashen.chest", "")) != "taken":
			_pois.append({"t": _tile_of(az.chest_node.global_position, _zone_base(), ts), "c": C_CHEST, "s": 3})
		return  # Ведьма и мобы — живой цикл группы "enemy" в paint()
	elif _zone == "cave":
		var dz = world.dungeon_zone
		if dz == null or not is_instance_valid(dz):
			return
		if dz.stairs_node != null and is_instance_valid(dz.stairs_node):
			_pois.append({"t": _tile_of(dz.stairs_node.global_position, _zone_base(), ts), "c": C_PORTAL, "s": 3})
		if dz.hermit_node != null and is_instance_valid(dz.hermit_node):
			_pois.append({"t": _tile_of(dz.hermit_node.global_position, _zone_base(), ts), "c": C_NPC, "s": 2})
		if Vector2i(dz.chest_tile).x >= 0:
			# алтарный сундук считается открытым по амулету (тот же признак, что у dungeon_zone)
			_pois.append({"t": Vector2i(dz.chest_tile), "c": _dim(C_CHEST) if GameState.has_amulet else C_CHEST, "s": 3})
		return
	# деревня: костры из world.campfires (жёлтые; пепел — тусклый)
	for cf in world.campfires:
		if cf != null and is_instance_valid(cf):
			var used_cf: bool = cf.get("used") == true
			_pois.append({"t": _tile_of((cf as Node2D).global_position, _zone_base(), ts), "c": _dim(C_FIRE) if used_cf else C_FIRE, "s": 3})
	# сундуки и NPC — по скриптам сущностей (групп у них нет; имена файлов стабильны)
	for n in world.village_zone.get_children():
		var sc := n.get_script() as Script
		if sc == null:
			continue
		var p := String(sc.resource_path)
		if p.ends_with("interactable.gd") and n.get("kind") == "chest":
			var used_ch: bool = n.get("used") == true
			_pois.append({"t": _tile_of((n as Node2D).global_position, _zone_base(), ts), "c": _dim(C_CHEST) if used_ch else C_CHEST, "s": 3})
		elif p.ends_with("npc.gd"):
			_pois.append({"t": _tile_of((n as Node2D).global_position, _zone_base(), ts), "c": C_NPC, "s": 2})
	_pois.append({"t": Vector2i(world.CAVE_ENTRANCE_TILE), "c": C_PORTAL, "s": 3})
	# Д2 «Лес запад» (25.11): поляна на (5,21) — зелёный блип; собранная (флаг
	# fw.glade_taken) — тусклый, как пепел костра/вскрытый сундук.
	var gl = world.get("forest_glade")
	if gl != null and is_instance_valid(gl):
		var taken_g: bool = int(GameState.flags.get("fw.glade_taken", 0)) == 1
		_pois.append({"t": _tile_of((gl as Node2D).global_position, _zone_base(), ts),
				"c": _dim(C_GLADE) if taken_g else C_GLADE, "s": 3})
	# выжженная аршина на восточной окраине — вход в Пепелище
	var aet: Variant = world.get("ASHEN_ENTRANCE_TILE")
	if aet is Vector2i:
		_pois.append({"t": aet, "c": C_PORTAL, "s": 3})

## t3 «Мир v1»: реестр этажей (WM_OFFSET_Y/LOC_OFFSET_Y) — preload вместо
## class_name: устойчиво к stale global_script_class_cache в headless.
const OW := preload("res://scripts/open_world.gd")

func _zone_base() -> Vector2:
	if _zone == "cave":
		return world.CAVE_OFFSET
	if _zone == "worldmap":
		# t3 «Мир v1»: этаж карты мира (OW.WM_OFFSET_Y)
		return Vector2(0.0, float(OW.WM_OFFSET_Y))
	if String(_zone).begins_with("loc_"):
		# t3: этаж локации из реестра OW.LOC_OFFSET_Y
		var offs: Variant = OW.LOC_OFFSET_Y
		if offs is Dictionary and (offs as Dictionary).has(String(_zone).substr(4)):
			return Vector2(0.0, float((offs as Dictionary)[String(_zone).substr(4)]))
		return Vector2.ZERO
	if String(_zone).begins_with("mini_"):
		# t19/t20: этаж хода MD.mini_y(биом) = 48000 + i×4800 (шаг полос этажей)
		return Vector2(0.0, preload("res://scripts/mini_dungeon.gd").mini_y(
				String(_zone).substr(5)))
	if _zone == "ashen":
		var ao: Variant = world.get("ASHEN_OFFSET")
		var off := Vector2.ZERO
		if ao is Vector2:
			off = ao
		return off
	return Vector2.ZERO

## t3: сетка зоны Мира по имени ("worldmap" | "loc_<биом>"); null — ещё не
## построена (ленивая зона: блипы/подложка дождутся первого входа).
func _world_grid(zone: String):
	if zone == "worldmap":
		return world.get("worldmap_grid")
	if zone.begins_with("loc_"):
		var bg: Variant = world.get("biome_grids")
		if bg is Dictionary:
			return (bg as Dictionary).get(zone.substr(4), null)
	if zone.begins_with("mini_"):
		# t19: внутренняя карта хода (world.mini_grids)
		var mg: Variant = world.get("mini_grids")
		if mg is Dictionary:
			return (mg as Dictionary).get(zone.substr(5), null)
	return null

## Мировые координаты -> тайл зоны (обратный ход world.tile_to_world: +0.5T и +2px).
func _tile_of(p: Vector2, base: Vector2, ts: float) -> Vector2i:
	return Vector2i(int(floor((p.x - base.x) / ts)), int(floor((p.y - base.y - 2.0) / ts)))

## t7 «Туман открытия»: вуаль карты мира (1 клетка = 1 px, те координаты и
## тот же rect, что у _grid_tex). Пересборка — только при смене версии
## GameState.wm_fog или подмены объекта (новый круг): в покое — ноль работы.
func _ensure_fog_tex() -> ImageTexture:
	var fog = GameState.wm_fog
	if fog == null or _grid_w <= 0 or _grid_h <= 0:
		return null
	if _fog_obj != fog or _fog_ver != int(fog.version) or _fog_tex == null:
		var img := Image.create(_grid_w, _grid_h, false, Image.FORMAT_RGBA8)
		for y in _grid_h:
			for x in _grid_w:
				if fog.is_discovered(x, y):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
				else:
					img.set_pixel(x, y, C_FOG)
		_fog_tex = ImageTexture.create_from_image(img)
		_fog_obj = fog
		_fog_ver = int(fog.version)
	return _fog_tex

func _fog_known(t: Vector2i) -> bool:
	var fog = GameState.wm_fog
	return fog == null or fog.is_discovered(t.x, t.y)

static func _dim(c: Color) -> Color:
	return Color(c.r, c.g, c.b, C_DIM)

static func _dim25(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.25)

# --- отрисовка (вызывается из _Radar._draw; публично — юнион-тесту) ---

## Нарисовать радар на canvas-элементе. Все страховки на месте: без мира/кэшей —
## только фон, ни одной ошибки (lazy-режим без хука в world тоже живёт здесь).
func paint(ci: CanvasItem) -> void:
	var inner := Rect2(FRAME, FRAME, SIZE - 2.0 * FRAME, SIZE - 2.0 * FRAME)
	ci.draw_rect(inner, C_BG)
	if world == null or not is_instance_valid(world) or not _zone_seen or _grid_tex == null:
		return
	var ts := float(world.TILE)
	var base := _zone_base()
	# карта целиком, центрированно (48×30 и 30×22 при 56×56 поля)
	var ox := inner.position.x + floorf((inner.size.x - _grid_w * TILE_SCALE) * 0.5)
	var oy := inner.position.y + floorf((inner.size.y - _grid_h * TILE_SCALE) * 0.5)
	ci.draw_texture_rect(_grid_tex, Rect2(ox, oy, _grid_w * TILE_SCALE, _grid_h * TILE_SCALE), false)
	# статичные POI. t7 «Туман открытия»: на карте мира туманные блипы не
	# загораются (портал ещё неизвестен — арка в стартовой clearing всегда).
	for poi in _pois:
		if _zone == "worldmap" and not _fog_known(poi["t"]):
			continue
		_blip(ci, poi["t"], poi["c"], poi["s"], Vector2(ox, oy))
	# мобы: группа "enemy" (мёртвый снят с группы — исчезает с радара сам)
	var tree := get_tree()
	if tree != null:
		for e in tree.get_nodes_in_group("enemy"):
			if not (e is Node2D) or not is_instance_valid(e):
				continue
			var t := _tile_of((e as Node2D).global_position, base, ts)
			if e.is_in_group("boss"):
				_blip(ci, t, C_BOSS, 4, Vector2(ox, oy))
			else:
				_blip(ci, t, C_MOB, 2, Vector2(ox, oy))
	# t7 «Туман открытия»: вуаль поверх тайлов/блипов/мобов (клетка героя
	# всегда открыта — герой под туман не попадает).
	if _zone == "worldmap":
		var ftex := _ensure_fog_tex()
		if ftex != null:
			ci.draw_texture_rect(ftex, Rect2(ox, oy, _grid_w * TILE_SCALE, _grid_h * TILE_SCALE), false)
	# герой — белая точка с лучами
	var pl: Node2D = world.player
	if pl != null and is_instance_valid(pl):
		var pt := _tile_of(pl.global_position, base, ts)
		var pos := Vector2(ox, oy) + Vector2(pt.x, pt.y) * TILE_SCALE
		var big := maxf(TILE_SCALE, 2.0)
		ci.draw_rect(Rect2(pos - Vector2.ONE, Vector2(big + 2.0, big + 2.0)), _dim25(C_HERO))
		ci.draw_rect(Rect2(pos, Vector2(big, big)), C_HERO)
		var cc := pos + Vector2(big * 0.5, big * 0.5)
		for i in 4:
			var d := Vector2.RIGHT.rotated(TAU * float(i) * 0.25)
			ci.draw_line(cc + d * (big + 1.0), cc + d * (big + 3.0), Color(C_HERO, 0.75), 1.0)

## Одна точка-блип (квадратик s×s по центру тайла), если тайл в поле карты.
func _blip(ci: CanvasItem, t: Vector2i, col: Color, s: int, origin: Vector2) -> void:
	if t.x < 0 or t.y < 0 or t.x >= _grid_w or t.y >= _grid_h:
		return
	var pos := origin + Vector2(t.x, t.y) * TILE_SCALE + Vector2.ONE * (TILE_SCALE - float(s)) * 0.5
	ci.draw_rect(Rect2(pos, Vector2(float(s), float(s))), col)

# --- ввод: M — тумблер (физ. KEY_M: action в project.godot не заводим) ---

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if GameState.input_locked:
		return  # диалог/меню/фейд: клавиатуру забирает они
	if (event as InputEventKey).physical_keycode == KEY_M:
		toggle()
		get_viewport().set_input_as_handled()

## Публичный тумблер (клавиша M и тесты идут через него).
func toggle() -> void:
	set_on(not is_on())
	GameAudio.sfx("ui_click")

# --- вуаль радара: рамка-панель + вызов paint в _draw ---

class _Radar extends Control:
	var mm: Minimap
	var _frame: Panel

	func build_frame() -> void:
		_frame = Panel.new()
		_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb = StyleBoxTexture.new()  # без type-inference: фолбек — StyleBoxFlat
		if ResourceLoader.exists(Minimap.FRAME_PATH):
			sb.texture = load(Minimap.FRAME_PATH)
			sb.region_rect = Rect2(0, 0, 32, 32)
			sb.texture_margin_left = 4.0
			sb.texture_margin_top = 4.0
			sb.texture_margin_right = 4.0
			sb.texture_margin_bottom = 4.0
		else:
			push_warning("Нет ассета: assets/ui/panel_frame.png — миникарта без рамки")
			var flat := StyleBoxFlat.new()
			flat.bg_color = Color(0.07, 0.08, 0.11, 0.9)
			flat.set_border_width_all(1)
			flat.border_color = Color(0.35, 0.4, 0.5, 0.8)
			sb = flat
		# t49 (юзер-баг «мир виден, радар пустой» в окне): рамка обязана рисовать
		# ТОЛЬКО кайму. Panel — ребёнок контрола радара, а дети CanvasItem рисуются
		# ПОСЛЕ его _draw(): непрозрачная сердцевина 9-slice (panel_frame.png,
		# 99.6 % пикселей с a=1) затягивала всю тайловую подложку и блипы — при
		# зелёных данных и зелёном _draw. Фон внутреннего поля рисует paint()
		# (C_BG по всему полю), поэтому центр StyleBox выключен и для фолбека.
		sb.draw_center = false
		_frame.add_theme_stylebox_override("panel", sb)
		add_child(_frame)
		# t52 снос (закон пользователя 13.11): ген-«бронзовое кольцо» снято —
		# рамка миникарты остаётся легаси деревянной 9-slice panel_frame (+фолбек).

	func _draw() -> void:
		if mm != null:
			mm.paint(self)
