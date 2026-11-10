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
## стены тонут.
##
## СОДЕРЖИМОЕ (текущая зона целиком, тумана войны нет): тайлы walk/wall кэшем
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
const C_DIM := 0.38                               # альфа «прошлого» POI (пепел/пустой)

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
	_radar.visible = false
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
		var cave := bool(GameState.in_cave)
		var zone := "village"
		var ao: Variant = world.get("ASHEN_OFFSET")
		var pl = world.player
		if cave:
			zone = "cave"
		elif pl != null and is_instance_valid(pl) and ao is Vector2 and pl.global_position.y > (ao as Vector2).y:
			zone = "ashen"
		var az = world.get("ashen_grid")   # слабая ссылка: null в сборках без Пепелища
		var prefix := "a" if zone == "ashen" else ("c" if cave else "v")
		var rows_s: String
		if zone == "ashen" and az != null and is_instance_valid(az) and az.get("map_rows") != null:
			rows_s = str(az.map_rows)
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
	if _zone == "ashen":
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
	if _zone == "ashen":
		var az = world.ashen_grid
		if az == null or not is_instance_valid(az):
			return
		if az.portal_node != null and is_instance_valid(az.portal_node):
			_pois.append({"t": _tile_of(az.portal_node.global_position, _zone_base(), ts), "c": C_PORTAL, "s": 3})
		# Взятый сундук снимает свой узел (queue_free) — блипа нет; флаг ashen.chest
		# закрывает и отложенный кадр до фактического удаления узла.
		if az.chest_node != null and is_instance_valid(az.chest_node) \
				and String(GameState.flags.get("ashen.chest", "")) != "taken":
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
	# выжженная аршина на восточной окраине — вход в Пепелище
	var aet: Variant = world.get("ASHEN_ENTRANCE_TILE")
	if aet is Vector2i:
		_pois.append({"t": aet, "c": C_PORTAL, "s": 3})

func _zone_base() -> Vector2:
	if _zone == "cave":
		return world.CAVE_OFFSET
	if _zone == "ashen":
		var ao: Variant = world.get("ASHEN_OFFSET")
		var off := Vector2.ZERO
		if ao is Vector2:
			off = ao
		return off
	return Vector2.ZERO

## Мировые координаты -> тайл зоны (обратный ход world.tile_to_world: +0.5T и +2px).
func _tile_of(p: Vector2, base: Vector2, ts: float) -> Vector2i:
	return Vector2i(int(floor((p.x - base.x) / ts)), int(floor((p.y - base.y - 2.0) / ts)))

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
	# статичные POI
	for poi in _pois:
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
		_frame.add_theme_stylebox_override("panel", sb)
		add_child(_frame)

	func _draw() -> void:
		if mm != null:
			mm.paint(self)
