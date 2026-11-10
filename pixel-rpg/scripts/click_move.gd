class_name ClickMove
extends Node2D
## ПКМ-клик-перемещение: щелчок ПКМ по проходимому тайлу — путь A* (nav.gd через
## публичный фасад world.build_path), движение СИНТЕЗИРУЕТСЯ через
## Input.action_press/action_release("move_*") — player.gd приказа не видит и
## не изменён: WASD-ход, атака ЛКМ и кувырок остаются полновластны.
## Синглтон по образцу game_audio.gd: world.gd создаёт узел в _ready() и
## присваивает I (страховка — саморегистрация в _enter_tree). Переключатель
## живёт в user://clickmove_cfg.json, по умолчанию ВКЛ.
## ПКМ в игре иначе свободен: атака — ЛКМ (action "attack"), взаимодействие — E;
## в диалоге/модалке ПКМ принадлежит world.gd (advance) — при input_locked мы
## молчим. Отмена пути: реальное WASD/стрелки, ЛКМ, Space; перекладка пути при
## снесении с тропы > 1.5 тайла; конец пути — полная остановка.

const CFG_PATH := "user://clickmove_cfg.json"
const ARRIVE_R := 3.0        # радиус захвата путевой точки, px
const AXIS_MIN := 0.3        # порог оси нормализованного направления при синтезе
const REPATHT := 0.5         # сек между проверками сноса с тропы
const DEV_TILES := 1.5       # на сколько тайлов можно снести — и путь перекладываем

static var I: ClickMove      # синглтон; назначает world.gd (fallback — _enter_tree)
static var _enabled := true  # кэш user://clickmove_cfg.json
static var _cfg_loaded := false

var world                    # узел world.gd (родитель); слабо типизирован, как world.dungeon_zone
var _path: Array = []        # путевые точки мировых координат (world.build_path)
var _idx := 0                # текущая путевая точка
var _goal := Vector2.ZERO    # точка клика — цель для перекладки
var _seg_a := Vector2.ZERO   # начало проходимого отрезка (мера сноса)
var _zone_cave := false      # зона на момент приказа: смена зоны (F9) гасит путь
var _rep_t := 0.0            # таймер перекладки
var _held := {"move_left": false, "move_right": false, "move_up": false, "move_down": false}
var _marker := false         # рисуем маркер цели?
var _t := 0.0                # время для пульса маркера

# --- переключатель: user://clickmove_cfg.json (дефолт — ВКЛ) ---

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

# --- жизненный цикл (паттерн GameAudio) ---

func _enter_tree() -> void:
	if I == null:
		I = self

func _ready() -> void:
	world = get_parent()
	if world == null or not world.has_method("build_path"):
		push_warning("ClickMove добавлен не под узел world — ПКМ-перемещение выключено")
		world = null
	z_index = -1  # маркер на земле: выше тайлов (-10), ниже спрайтов (0)
	visible = false
	set_physics_process(false)
	set_process(false)

func _exit_tree() -> void:
	_release_all()  # «зажатые» синтетические клавиши не уезжают в следующую сцену
	if I == self:
		I = null

# --- ввод ---

# ВАЖНО (экспериментально на 4.7.2.stable): Input.action_press() меняет только
# состояние экшенов и НЕ шлёт события в пайплайн узлов (_input/_unhandled_input),
# а метода InputEvent::is_synthetic() в этой сборке нет (ClassDB: false). Значит,
# клавиатурное событие, дошедшее до обработчика ниже, всегда реальное — синтез
# move_* сам себе путь не отменит и никакой фильтр синтетики не нужен.
func _unhandled_input(event: InputEvent) -> void:
	# Диалог/модалка/переход: ПКМ листает диалог в world.gd, WASD гейтит player.gd.
	# Здесь не трогаем ничего; активный путь сбросит _physics_process (он же
	# снимает «зажатые» оси, чтобы героя не понесло после разблокировки).
	if GameState.input_locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# реальное нажатие WASD/стрелок = игрок взял управление; Space = кувырок.
		# Эхо удержания не в счёт: зажатая клавиша не должна глушить новый приказ.
		if event.is_action_pressed("roll") \
				or event.is_action_pressed("move_up") or event.is_action_pressed("move_down") \
				or event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
			cancel()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			cancel()  # мышь взялась за атаку — путь доделывать незачем
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _order_at_cursor():
				get_viewport().set_input_as_handled()

## Ход к мировой точке: цель притягивается к центру тайла. true — приказ принят.
## false — тайл непроходим/вне карты/это своя клетка: живой путь НЕ отменяем.
## Недостижимо — старый путь сбрасывается, герой стоит, тост «Туда не дойти.».
func order_to(p: Vector2) -> bool:
	if not is_on() or world == null or not is_instance_valid(world):
		return false
	var pl: Node2D = world.player
	if pl == null or not is_instance_valid(pl):
		return false
	var base: Vector2 = world.CAVE_OFFSET if GameState.in_cave else Vector2.ZERO
	var ts := float(world.TILE)
	var tile := Vector2i(int(floor((p.x - base.x) / ts)), int(floor((p.y - base.y) / ts)))
	if not _tile_walkable(tile):
		return false
	var from := pl.global_position
	var mine := Vector2i(int(floor((from.x - base.x) / ts)), int(floor((from.y - base.y) / ts)))
	if tile == mine:
		return false  # своя клетка — идти некуда
	var goal: Vector2 = base + world.tile_to_world(tile)
	var np: Array = world.build_path(from, goal)
	if np.is_empty():
		cancel()  # новый приказ вытесняет старый; идти нечем — герой стоит
		GameState.toast.emit("Туда не дойти.")
		return true
	_release_all()
	_path = np
	_idx = 0
	_goal = goal
	_seg_a = from
	_zone_cave = GameState.in_cave
	_rep_t = REPATHT
	_show_marker(goal)
	set_physics_process(true)
	set_process(true)
	return true

## ПКМ: курсор как цель (мировые координаты — та же система, что у прицела).
func _order_at_cursor() -> bool:
	if world == null or not is_instance_valid(world):
		return false
	return order_to(world.get_global_mouse_position())

## Проходимость тайла текущей зоны. Деревня — теми же публичными константами
## world (CHAR_TO_TILE/BLOCKING), что и world._village_walkable; пещера —
## dungeon_zone.cell_walkable, т.е. закрытая дверь и взятый сундук учитываются
## сами: приказ «в закрытую дверь» просто не принимается.
func _tile_walkable(t: Vector2i) -> bool:
	if GameState.in_cave:
		var dz = world.dungeon_zone
		return dz != null and dz.has_method("cell_walkable") and dz.cell_walkable(t)
	if t.x < 0 or t.y < 0 or t.y >= int(world.map_h) or t.x >= int(world.map_w):
		return false
	var row := String(world.map_rows[t.y])
	if t.x >= row.length():
		return false
	var ch := row[t.x]
	if not world.CHAR_TO_TILE.has(ch):
		return true
	return not (int(world.CHAR_TO_TILE[ch]) in world.BLOCKING)

# --- ход по пути ---

func _physics_process(delta: float) -> void:
	if _path.is_empty() or world == null:
		return
	var pl: Node2D = world.player
	# гей-лок ввода, выключенный переключатель, смена зоны (F9/портал) — стоп;
	# урон пути НЕ мешает (получение/нанесение не отменяет — по контракту).
	if pl == null or not is_instance_valid(pl) or GameState.input_locked \
			or not is_on() or GameState.in_cave != _zone_cave:
		cancel()
		return
	var p := pl.global_position
	while _idx < _path.size():
		var wp0: Vector2 = _path[_idx]
		if p.distance_squared_to(wp0) > ARRIVE_R * ARRIVE_R:
			break
		_seg_a = wp0
		_idx += 1
	if _idx >= _path.size():
		cancel()  # конец пути — полная остановка: все оси отпущены
		return
	var wp: Vector2 = _path[_idx]
	_rep_t -= delta
	if _rep_t <= 0.0:
		_rep_t = REPATHT
		if _dist_seg(p, _seg_a, wp) > float(world.TILE) * DEV_TILES:
			_repath(p)
			return
	_set_axes(wp - p)

## Снесло с тропы (толкнули, обошли) — перекладываем путь к той же цели.
func _repath(p: Vector2) -> void:
	var np: Array = world.build_path(p, _goal)
	if np.is_empty():
		cancel()
		GameState.toast.emit("Туда не дойти.")
		return
	_release_all()
	_path = np
	_idx = 0
	_seg_a = p

## Синтез нажатий осей: жмём/отпускаем только при смене состояния — состояние
## осей ведётся явно (_held), повторные action_press/action_release ни к чему.
func _set_axes(d: Vector2) -> void:
	var n := d.normalized()
	var want := {
		"move_left": n.x < -AXIS_MIN,
		"move_right": n.x > AXIS_MIN,
		"move_up": n.y < -AXIS_MIN,
		"move_down": n.y > AXIS_MIN,
	}
	for a in want:
		if want[a] == _held[a]:
			continue
		if want[a]:
			Input.action_press(a)
		else:
			Input.action_release(a)
		_held[a] = want[a]

func _release_all() -> void:
	for a in _held:
		if _held[a]:
			Input.action_release(a)
			_held[a] = false

## Расстояние от точки до отрезка a-b — мера сноса с текущего отрезка пути.
static func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (p - (a + ab * t)).length()

# --- маркер цели: рисуется руками, новых ассетов не просим ---

## Публичный API: сбросить путь и полностью остановиться (отпустить все оси).
func cancel() -> void:
	_release_all()
	_path = []
	_idx = 0
	_marker = false
	visible = false
	set_physics_process(false)
	set_process(false)

func is_walking() -> bool:
	return not _path.is_empty()

func _show_marker(p: Vector2) -> void:
	position = p
	visible = true
	_marker = true
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if not _marker:
		return
	var col := Color(1.0, 0.9, 0.45, 0.9)
	var r := 3.5 + 1.2 * sin(_t * 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.62))  # сплюснутый овал — «на земле»
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, col, 1.0)
	for i in 4:
		var a := TAU * float(i) * 0.25 + 0.7853
		var c := Vector2(cos(a), sin(a))
		draw_line(c * (r + 1.0), c * (r + 2.5), col, 1.0)
	draw_rect(Rect2(-1.0, -1.0, 2.0, 2.0), Color(col, 0.85))
