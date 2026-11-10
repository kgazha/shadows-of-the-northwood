class_name Fx
## VFX-система «Тени Северного Леса». Статические функции спавнят
## одноразовые CPUParticles2D (надёжнее GPUParticles2D в GL Compatibility
## и headless) в переданную ноду мира и сами себя убирают: сигнал
## finished + страховочный SceneTreeTimer. Текстуры — собственные CC0
## пиксели assets/fx/*.png (белые, оттенок задаётся цветом процессора).
## Kenney Particle Pack не был скачан (сеть закрыта) — при появлении
## архива достаточно положить PNG в assets/fx под теми же именами.

const TEX_DIR := "res://assets/fx/"
const TEX_DOT := "fx_dot.png"         # 4x4 искра/уголь
const TEX_DOT_SOFT := "fx_dot_soft.png"  # 6x6 мягкое свечение
const TEX_SPARK := "fx_spark.png"     # 7x7 четырёхлучевая искра
const TEX_STAR := "fx_star.png"       # 5x5 звёздный крест
const TEX_FLAME := "fx_flame.png"     # 6x8 пламя
const TEX_SMOKE := "fx_smoke.png"     # 8x8 дымок
const TEX_SHARD := "fx_shard.png"     # 5x7 ледяной осколок

static var _tex_cache: Dictionary = {}

static func _tex(fname: String) -> Texture2D:
	if _tex_cache.has(fname):
		return _tex_cache[fname]
	var t: Texture2D = null
	var path := TEX_DIR + fname
	if ResourceLoader.exists(path):
		t = load(path)
	else:
		push_warning("Fx: нет текстуры %s" % path)
	_tex_cache[fname] = t
	return t

## Градиент жизни частицы: c0 -> c1 (45%) -> c2 (обычно альфа 0).
## У CPUParticles2D поле color_ramp — Gradient (не Texture, как у GPU).
static func _ramp(c0: Color, c1: Color, c2: Color) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([c0, c1, c2])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	return g

## Огонь игры: в середине жизни ядрёный ~(200,90,40).
static func _fire_ramp() -> Gradient:
	return _ramp(Color(1.0, 0.86, 0.5), Color(0.78, 0.35, 0.16), Color(0.30, 0.10, 0.06, 0.0))

static func _ice_ramp() -> Gradient:
	return _ramp(Color(0.78, 0.93, 1.0), Color(0.35, 0.59, 0.86), Color(0.18, 0.36, 0.66, 0.0))

## Ядро: собрать CPUParticles2D по конфигу, заспавнить в parent и приучить
## себя удаляться. cfg-ключи: tex amount life explode dir spread gravity
## vmin vmax damp_min damp_max ramin ramax smin smax ring color ramp z.
static func _make(parent: Node2D, pos: Vector2, cfg: Dictionary) -> CPUParticles2D:
	if parent == null or not is_instance_valid(parent):
		push_warning("Fx: родительская нода не задана/невалидна — эффект пропущен")
		return null
	var p := CPUParticles2D.new()
	p.name = "Fx"
	p.add_to_group("fx")  # учёт харнессу
	p.one_shot = true
	p.explosiveness = float(cfg.get("explode", 1.0))
	p.lifetime = float(cfg.get("life", 0.4))
	p.amount = int(cfg.get("amount", 12))
	var tex: Texture2D = _tex(String(cfg.get("tex", TEX_DOT)))
	if tex != null:
		p.texture = tex
	p.direction = cfg.get("dir", Vector2.UP)
	p.spread = float(cfg.get("spread", 180.0))
	p.gravity = cfg.get("gravity", Vector2.ZERO)
	p.initial_velocity_min = float(cfg.get("vmin", 30.0))
	p.initial_velocity_max = float(cfg.get("vmax", 70.0))
	p.damping_min = float(cfg.get("damp_min", 0.0))
	p.damping_max = float(cfg.get("damp_max", 0.0))
	p.radial_accel_min = float(cfg.get("ramin", 0.0))
	p.radial_accel_max = float(cfg.get("ramax", 0.0))
	p.scale_amount_min = float(cfg.get("smin", 0.8))
	p.scale_amount_max = float(cfg.get("smax", 1.2))
	if cfg.has("ramp"):
		p.color_ramp = cfg["ramp"]
	else:
		p.color = cfg.get("color", Color(1, 1, 1, 0.9))
	var ring := float(cfg.get("ring", 0.0))
	if ring > 0.0:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
		p.emission_ring_radius = ring
		p.emission_ring_inner_radius = ring * 0.82
	p.z_index = int(cfg.get("z", 20))
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	# страховка: finished у one_shot может не дожить (пауза дерева посреди
	# эффекта) — дочерний Timer добьёт эмиттер; сам Timer при этом висит на
	# p и умирает вместе с ним, «висячих» лямбда-захватов нет.
	var guard := Timer.new()
	guard.name = "FxGuard"
	guard.one_shot = true
	guard.wait_time = p.lifetime * 2.0 + 0.5
	guard.process_mode = Node.PROCESS_MODE_ALWAYS
	guard.autostart = true
	guard.timeout.connect(p.queue_free)
	p.add_child(guard)
	p.emitting = true
	return p

# --- публичные эффекты ---

## Искры от попадания (мили-удар, урон по герою).
static func hit(pos: Vector2, parent: Node2D) -> void:
	_make(parent, pos, {
		"tex": TEX_SPARK, "amount": 10, "life": 0.3, "explode": 1.0,
		"vmin": 45.0, "vmax": 90.0, "gravity": Vector2(0, 150),
		"damp_min": 60.0, "damp_max": 110.0, "smin": 0.45, "smax": 0.85,
		"ramp": _ramp(Color(1, 0.95, 0.75), Color(1, 0.62, 0.3), Color(0.9, 0.24, 0.12, 0.0)),
	})

## Огненный след по сегменту from->to (огненный снаряд фаерболта).
static func fire_trail(from_p: Vector2, to_p: Vector2, parent: Node2D) -> void:
	var d := to_p - from_p
	var dist: float = maxf(d.length(), 1.0)
	var life: float = clampf(dist / 130.0, 0.3, 0.55)
	var v: float = dist / life
	_make(parent, from_p, {
		"tex": TEX_FLAME, "amount": 16, "life": life, "explode": 0.3,
		"dir": d.normalized(), "spread": 9.0,
		"vmin": v * 0.82, "vmax": v, "damp_min": 30.0, "damp_max": 70.0,
		"smin": 0.6, "smax": 1.1, "ramp": _fire_ramp(),
	})

## Огненный взрыв-вспышка (попадание снаряда, тик фаершторма).
static func fire_burst(pos: Vector2, parent: Node2D) -> void:
	_make(parent, pos, {
		"tex": TEX_FLAME, "amount": 16, "life": 0.45, "explode": 0.9,
		"vmin": 28.0, "vmax": 74.0, "gravity": Vector2(0, -30),
		"damp_min": 50.0, "damp_max": 100.0, "smin": 0.7, "smax": 1.3,
		"ramp": _fire_ramp(),
	})

## Кольцо ледяных осколков радиуса r (морозная нова).
static func frost_ring(pos: Vector2, r: float, parent: Node2D) -> void:
	var rad: float = maxf(r, 4.0)
	_make(parent, pos, {
		"tex": TEX_SHARD, "amount": 20, "life": 0.4, "explode": 1.0,
		"ring": rad * 0.32, "vmin": 12.0, "vmax": 28.0,
		"ramin": rad * 3.5, "ramax": rad * 6.5,
		"smin": 0.55, "smax": 1.0, "ramp": _ice_ramp(),
	})

## Восходящие зелёные искры лечения (реген, поглощение, зелье).
static func heal(pos: Vector2, parent: Node2D) -> void:
	_make(parent, pos, {
		"tex": TEX_DOT_SOFT, "amount": 9, "life": 0.65, "explode": 0.55,
		"dir": Vector2.UP, "spread": 22.0, "vmin": 20.0, "vmax": 44.0,
		"gravity": Vector2(0, -26), "smin": 0.55, "smax": 1.0,
		"ramp": _ramp(Color(0.55, 1.0, 0.6), Color(0.33, 0.85, 0.45, 0.85), Color(0.16, 0.55, 0.28, 0.0)),
	})

## Пыльное облачко у ног (кувырок).
static func dust(pos: Vector2, parent: Node2D) -> void:
	_make(parent, pos, {
		"tex": TEX_SMOKE, "amount": 6, "life": 0.5, "explode": 0.7,
		"dir": Vector2.UP, "spread": 60.0, "vmin": 8.0, "vmax": 22.0,
		"gravity": Vector2(0, -10), "smin": 0.8, "smax": 1.5,
		"ramp": _ramp(Color(0.66, 0.6, 0.5, 0.55), Color(0.55, 0.5, 0.42, 0.35), Color(0.4, 0.37, 0.32, 0.0)),
	})

## Новый уровень: золотой всплеск звёзд + столб мягкого свечения.
static func level_up(pos: Vector2, parent: Node2D) -> void:
	_make(parent, pos, {
		"tex": TEX_STAR, "amount": 14, "life": 0.6, "explode": 0.9,
		"vmin": 40.0, "vmax": 95.0, "gravity": Vector2(0, 60),
		"damp_min": 40.0, "damp_max": 80.0, "smin": 0.5, "smax": 0.95,
		"ramp": _ramp(Color(1.0, 0.95, 0.7), Color(1.0, 0.8, 0.35), Color(0.85, 0.55, 0.12, 0.0)),
	})
	_make(parent, pos + Vector2(0, 4), {
		"tex": TEX_DOT_SOFT, "amount": 10, "life": 0.7, "explode": 0.25,
		"dir": Vector2.UP, "spread": 12.0, "vmin": 30.0, "vmax": 65.0,
		"gravity": Vector2(0, -18), "smin": 0.6, "smax": 1.1,
		"ramp": _ramp(Color(1.0, 0.92, 0.6), Color(0.95, 0.75, 0.3, 0.8), Color(0.8, 0.55, 0.15, 0.0)),
	})

## Угасающие угли для пещеры: возвращает постоянный генератор (живёт,
## пока жив его родитель — вешать на cave_zone; зона с PROCESS_MODE
## DISABLED его честно замораживает). position — ЛОКАЛЬНЫЕ координаты зоны.
static func ember_bed(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.name = "FxEmberBed"
	n.position = pos
	var p := CPUParticles2D.new()
	p.name = "Embers"
	p.amount = 7
	p.lifetime = 2.6
	p.one_shot = false
	var tex: Texture2D = _tex(TEX_DOT)
	if tex != null:
		p.texture = tex
	p.direction = Vector2.UP
	p.spread = 30.0
	p.gravity = Vector2(0, -9.0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 14.0
	p.scale_amount_min = 0.45
	p.scale_amount_max = 0.95
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(5, 2)
	p.z_index = 5
	p.color_ramp = _ramp(Color(1.0, 0.62, 0.25), Color(0.82, 0.28, 0.1, 0.75), Color(0.25, 0.06, 0.04, 0.0))
	n.add_child(p)
	return n
