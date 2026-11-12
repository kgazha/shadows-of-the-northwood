class_name Juice
extends Node
## «Сочность» боёвки (t18 P0-1): hitstop + тряска камеры «мазок кисти».
##
## Hitstop = микро-дип Engine.time_scale длительностью STOP_FRAMES ФИЗИЧЕСКИХ
## КАДРОВ (контракт 2–4 кадра). Кадровая, а не миллисекундная привязка выбрана
## специально: headless-симуляция Godot гонит фиксированные тики быстрее
## реального времени (~440 тик/с), поэтому дип в «36 мс реального времени»
## там съедал бы ~16 кадров — таймеры, привязанные к игровому времени,
## голодали и геймплейные стенды краснели. Кадровый дип одинаков в обеих
## средах и предсказуем: каждый hitstop стоит миру ровно
## STOP_FRAMES*(1-DIP) ≈ 1.7 кадра игрового времени.
##
## Гарантии восстановления Engine.time_scale (глобальная величина — обращение
## с ней осторожное):
##  • dip длится строго конечное ЧИСЛО физических тиков — счётчик в
##    _physics_process узла с PROCESS_MODE_ALWAYS (тикает даже на паузе,
##    в диалоге, на смерти героя и после смены сцены);
##  • дублирующий watchdog в _process: dip конечен и в РЕАЛЬНОМ времени
##    (FAILSAFE_MS) — если физика по нештатной причине встала, время всё
##    равно вернётся;
##  • dip ставится только когда хост уже в дереве (не «залипает» при
##    невозможности завести watchdog);
##  • _exit_tree возвращает scale=1 при уничтожении хоста;
##  • hitstop только ОПУСКАЕТ scale и никогда не поднимает выше текущего;
##  • restore — только если dip ещё активен (чужой scale не затираем);
##  • хост висит на root (переживает смену сцены), статический доступ — Juice.*;
##  • root может быть занят сборкой сцены (add_child падает в _ready мира) —
##    хост заводится через call_deferred и живёт с ближайшего кадра.
##
## Тряска — FastNoiseLite (Perlin-подобный «мазок кисти», не белый шум),
## применяется к cam.offset и обнуляется по окончании — залипание невозможно.

const DIP := 0.15             # time_scale во время hitstop (эффект «кадр-стоп»)
const STOP_FRAMES := 2        # длительность dip в ФИЗИЧЕСКИХ КАДРАХ (контракт 2–4)
const FAILSAFE_MS := 150      # жёсткий реальный край dip (страховка: физика встала)
const THROTTLE_MS := 100      # не чаще одного hitstop на комбо-шквал

static var _host: Node = null

static func host() -> Node:
	if _host != null and is_instance_valid(_host):
		return _host
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var h := tree.root.get_node_or_null("JuiceHost")
	if h == null:
		h = Juice.new()
		h.name = "JuiceHost"
		# root бывает занят настройкой детей (attach_camera из world._ready) —
		# прямой add_child там падает; deferred добавляет хост следующим кадром.
		tree.root.add_child.call_deferred(h)
	_host = h
	return h

## Hitstop удара: вызывается в момент попадания (hero hurt / mob hurt).
static func hit() -> void:
	var h := host()
	if h != null:
		(h as Juice)._hit()

## Тряска «мазок кисти»: amp — амплитуда в px, dur_s — длительность в секундах.
static func shake(amp: float, dur_s: float) -> void:
	var h := host()
	if h != null:
		(h as Juice)._shake(amp, dur_s)

static func attach_camera(cam: Camera2D) -> void:
	var h := host()
	if h != null:
		(h as Juice)._cam = cam

## QA/страховка: немедленно вернуть время и покой (тесты восстановления).
static func reset() -> void:
	if _host != null and is_instance_valid(_host):
		(_host as Juice)._restore()
		(_host as Juice)._clear_shake()

var _cam: Camera2D = null
var _noise := FastNoiseLite.new()
var _dip_active := false
var _dip_left := 0            # физических тиков до восстановления
var _dip_deadline := 0        # мс реального времени — резервный край dip
var _last_hit_ms := -100000
var _shake_amp := 0.0
var _shake_t0 := 0
var _shake_ms := 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # watchdog не ставится на паузу/диалог
	_noise.seed = 1187                       # детерминированная «кисть»
	_noise.frequency = 0.09
	_noise.fractal_octaves = 2

func _exit_tree() -> void:
	Engine.time_scale = 1.0                  # мир не замерзает вместе с хостом

func _physics_process(_delta: float) -> void:
	# основной счётчик dip: ровно STOP_FRAMES физических кадров, одинаково
	# в реальном игровом процессе и в headless-симуляции (тики не зависят от time_scale)
	if _dip_active:
		_dip_left -= 1
		if _dip_left <= 0:
			_restore()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _dip_active and now >= _dip_deadline:
		_restore()                           # failsafe: реальное время не ждёт
	if _cam != null and not is_instance_valid(_cam):
		_cam = null
	if _cam == null:
		return
	if now < _shake_t0 + _shake_ms:
		var k := 1.0 - float(now - _shake_t0) / float(_shake_ms)
		k *= k                               # квадратичное затухание: резкий мазок, мягкая посадка
		_cam.offset = Vector2(
			_noise.get_noise_2d(float(now) * 0.05, 3.0),
			_noise.get_noise_2d(float(now) * 0.05, 71.0)) * _shake_amp * k
	elif _cam.offset != Vector2.ZERO:
		_cam.offset = Vector2.ZERO           # тряска не залипает

func _hit() -> void:
	if GameState.input_locked:
		return                               # диалог/пауза: глобальным временем не владеем
	if not is_inside_tree():
		return                               # watchdog ещё не тикает — время не трогаем
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < THROTTLE_MS:
		return                               # шквал попаданий: не больше одного dip за окно
	_last_hit_ms = now
	if Engine.time_scale > DIP:
		Engine.time_scale = DIP              # только опускаем, никогда не поднимаем
	_dip_active = true
	_dip_left = STOP_FRAMES
	_dip_deadline = now + FAILSAFE_MS

func _shake(amp: float, dur_s: float) -> void:
	var now := Time.get_ticks_msec()
	var ms := maxi(1, int(dur_s * 1000.0))
	if now < _shake_t0 + _shake_ms:
		# уже трясёмся — берём максимум амплитуды и более поздний край
		if now + ms > _shake_t0 + _shake_ms:
			_shake_ms = int(_shake_t0) + ms - now
		_shake_amp = maxf(_shake_amp, amp)
	else:
		_shake_amp = amp
		_shake_t0 = now
		_shake_ms = ms

func _restore() -> void:
	if _dip_active:
		Engine.time_scale = 1.0
	_dip_active = false
	_dip_left = 0
	_dip_deadline = 0

func _clear_shake() -> void:
	_shake_ms = 1
	_shake_t0 = -100000
	_shake_amp = 0.0
	if _cam != null and is_instance_valid(_cam):
		_cam.offset = Vector2.ZERO
