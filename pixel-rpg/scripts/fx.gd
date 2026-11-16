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

# --- g16: левелап (вердикт пользователя 16.11) ---
# Переключатель вида: 1 = «Вспышка» (shipping default), 2 = «Столб света».
# Пользователю нравятся ОБА эффекта и выбирать он хочет по живым скриншотам,
# поэтому значение — static var, а не const: скриншотный харнесс (_lvlshot.gd,
# вне git) снимает оба варианта за один прогон без пересборки. Дефолт при этом
# неизменен: в игру уходит вариант 1, пока пользователь не скажет иное.
const LEVEL_UP_STYLE_DEFAULT := 1
static var LEVEL_UP_STYLE: int = LEVEL_UP_STYLE_DEFAULT

const LU_TEXT := "Новый уровень!"       # русская надпись над героем (вердикт)
const LU_FONT_SIZE := 16                # 16px-шрифт (Handjet, кириллица покрыта)
const LU_RISE := 24.0                   # всплытие, px
const LU_RISE_T := 0.5                  # всплытие, с
const LU_HOLD_T := 0.7                  # висит, с
const LU_FADE_T := 0.4                  # растворение, с
const LU_FLASH_T := 0.35                # вспышка варианта 1, с
const LU_BEAM_T := 0.7                  # жизнь столба варианта 2, с
const LU_BEAM_FADE_T := 0.3             # растворение столба, с
const LU_BEAM_FRAME_T := 2.0 / 60.0     # «2 кадра на фазу» при шаге 60 fps
const LU_FLASH_S0 := 1.0                # вспышка: старт масштаба мягкой точки
const LU_FLASH_S1 := 8.4                # …и пик (6px-точка => ~50 px вокруг героя)
const LU_LIGHT_PEAK := 3.4              # пик импульса света (факел дышит 0.5..1.0)
const LU_BEAM_H := 32                   # столб: высота, px
const LU_BEAM_W := 7                    # …и ширина (ядро 1 px + «крылья»)
const LU_GOLD := Color(1.0, 0.84, 0.35)       # тон звёздного всплеска
const LU_GOLD_HOT := Color(1.0, 0.96, 0.78)   # горячая середина вспышки

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
	if cfg.has("rect"):
		# узкая колонна эмиссии (g16: искры внутри столба света). Рядом с ring:
		# оба только задают emission_shape, приоритет у rect — он уникальнее.
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = cfg["rect"]
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

## Новый уровень (g16): звёздный всплеск остаётся базой при любом варианте,
## вокруг него добавляется усиление (вариант 1 «Вспышка» / вариант 2 «Столб
## света») и русская надпись «Новый уровень!» над героем. parent — узел мира.
static func level_up(pos: Vector2, parent: Node2D) -> void:
	_star_burst(pos, parent)
	if LEVEL_UP_STYLE == 2:
		_light_beam(pos, parent)
	else:
		_flash_burst(pos, parent)
	_banner(pos, parent)
	_fanfare_guard()

## База, какая была до g16: золотой всплеск звёзд. Конфиг не менялся — эффект
## пользователю нравится, просили усилить подачу вокруг него, а не сам всплеск.
static func _star_burst(pos: Vector2, parent: Node2D) -> void:
	_make(parent, pos, {
		"tex": TEX_STAR, "amount": 14, "life": 0.6, "explode": 0.9,
		"vmin": 40.0, "vmax": 95.0, "gravity": Vector2(0, 60),
		"damp_min": 40.0, "damp_max": 80.0, "smin": 0.5, "smax": 0.95,
		"ramp": _ramp(Color(1.0, 0.95, 0.7), Color(1.0, 0.8, 0.35), Color(0.85, 0.55, 0.12, 0.0)),
	})

## Вариант 1 «Вспышка»: тёплая радиальная вспышка ~0.35 с (масштабируемая мягкая
## точка), импульс света как от факела и сноп искр вверх.
static func _flash_burst(pos: Vector2, parent: Node2D) -> void:
	var flash := LevelUpFlash.new()
	flash.name = "FxFlash"
	flash.texture = _tex(TEX_DOT_SOFT)
	flash.position = pos + Vector2(0, -2)
	parent.add_child(flash)
	# Свет — по образцу пещерных факелов (CaveArt._mk_torch_light): тот же
	# радиальный градиент и тот же цвет семьи факела. Радиус в два факела
	# (факел 36 px, здесь 72 px) и пик вчетверо ярче факельной базы 0.75: в
	# тёмной пещере вспышка должна осветить стены вокруг героя, а не только
	# его саму — иначе выбор варианта по скриншотам был бы вслепую.
	var lamp := LevelUpLight.new()
	lamp.name = "FxFlashLight"
	lamp.texture = _radial_tex(144.0)
	lamp.color = LU_GOLD
	lamp.position = pos
	parent.add_child(lamp)
	_make(parent, pos + Vector2(0, -4), {
		"tex": TEX_SPARK, "amount": 12, "life": 0.5, "explode": 1.0,
		"dir": Vector2.UP, "spread": 26.0, "vmin": 55.0, "vmax": 105.0,
		"gravity": Vector2(0, 120), "damp_min": 20.0, "damp_max": 50.0,
		"smin": 0.5, "smax": 0.9,
		"ramp": _ramp(Color(1.0, 0.98, 0.8), Color(1.0, 0.8, 0.32), Color(0.9, 0.5, 0.1, 0.0)),
	})

## Вариант 2 «Столб света»: вертикальный луч над героем (2 кадра на фазу),
## поднимающиеся внутри луча искры и мягкий ореол у ног.
static func _light_beam(pos: Vector2, parent: Node2D) -> void:
	var beam := LevelUpBeam.new()
	beam.name = "FxBeam"
	beam.tex_a = _beam_tex(0)
	beam.tex_b = _beam_tex(1)
	# спрайт центрирован, поэтому сдвиг = половина высоты: низ луча у пояса
	# героя (pos.y - 1), верх на LU_BEAM_H px выше
	beam.position = pos + Vector2(0, -1.0 - LU_BEAM_H * 0.5)
	parent.add_child(beam)
	_make(parent, pos + Vector2(0, -10), {
		"tex": TEX_DOT, "amount": 12, "life": 0.75, "explode": 0.35,
		"dir": Vector2.UP, "spread": 6.0, "rect": Vector2(2.0, 7.0),
		"vmin": 26.0, "vmax": 52.0, "gravity": Vector2(0, -22),
		"smin": 0.45, "smax": 0.85,
		"ramp": _ramp(Color(1.0, 0.97, 0.72), Color(1.0, 0.82, 0.36, 0.9), Color(0.85, 0.58, 0.14, 0.0)),
	})
	var halo := LevelUpHalo.new()
	halo.name = "FxHalo"
	halo.texture = _tex(TEX_DOT_SOFT)
	halo.position = pos + Vector2(0, 5)    # ореол у ног
	parent.add_child(halo)

## Надпись «Новый уровень!» поверх всплеска — одинаковая в обоих вариантах.
static func _banner(pos: Vector2, parent: Node2D) -> void:
	var lb := LevelUpText.new()
	lb.name = "FxLevelUpText"
	lb.position = pos + Vector2(0, -26)
	parent.add_child(lb)

## Гвард-фанфара. Основной тон — синтезированный «levelup» (тёплое G-C-G из
## процедурного каталога), его играет ЕДИНСТВЕННАЯ точка — hud._on_leveled_up;
## пин qa_snd «I: hud.gd — уровень/ранг» запрещает там ui_levelup именно ради
## того, чтобы на одно событие не было двух звуков. Поэтому здесь проверка БЕЗ
## проигрывания: если процедурного каталога нет вовсе (нет узла Sfx или нет
## ключа) — берём короткий тон ui_levelup из реестра GameAudio (образец
## guarded-вызова как в journal.gd: нет ассета — тихий пропуск). Дёргать
## Sfx.play второй раз нельзя: троттл ключа 300 мс вернул бы false и дал бы
## удвоение звука на каждом левелапе.
static func _fanfare_guard() -> void:
	if Sfx.I != null and is_instance_valid(Sfx.I) and Sfx.keys().has("levelup"):
		return
	GameAudio.sfx("ui_levelup")

## Радиальная текстура света по образцу CaveArt._mk_torch_light. Рецепт держим
## у себя: fx.gd не должен зависеть от пещерного арт-модуля.
static var _rad_cache: Dictionary = {}

static func _radial_tex(diameter: float) -> GradientTexture2D:
	var key := str(int(diameter))
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
	gt.width = int(ceil(diameter))
	gt.height = gt.width
	_rad_cache[key] = gt
	return gt

## Столб света (фаза 0/1). Пиксели рисует код — тот же канон, что у UiIcons и
## ForestArt, никаких растровых ассетов: ядро шириной 1 px, по бокам
## полупрозрачные «крылья», яркость строки падает кверху (порог 1.6 — подобран
## под 26 px, чтобы верх луча растворялся, а не обрывался). Во второй фазе ядро
## тусклее и крыльев нет — отсюда «мигание» 2 кадра / 2 кадра.
static var _beam_cache: Dictionary = {}

static func _beam_tex(phase: int) -> Texture2D:
	if _beam_cache.has(phase):
		return _beam_cache[phase]
	var w := LU_BEAM_W
	var h := LU_BEAM_H
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := int(w * 0.5)   # середина нечётной ширины (7 -> 3)
	for y in h:
		var k := clampf(float(h - 1 - y) / float(h - 1), 0.0, 1.0)
		var a := pow(k, 1.6)
		var core := a if phase == 0 else a * 0.72
		var wing := a * 0.45 if phase == 0 else 0.0
		var faint := wing * 0.4
		for x in w:
			var d := absi(x - cx)
			var al := 0.0
			var col := LU_GOLD
			match d:
				0:
					al = core
				1:
					al = wing
				2:
					al = faint
			img.set_pixel(x, y, Color(col.r, col.g, col.b, al))
	var tex := ImageTexture.create_from_image(img)
	_beam_cache[phase] = tex
	return tex

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

# --- g16: ноды левелапа (отжили свою долю секунды — удалили себя сами) ---

## Всплывающая надпись «Новый уровень!»: всплытие LU_RISE px за LU_RISE_T,
## висит LU_HOLD_T, растворяется LU_FADE_T. Control живёт в Node2D-мире:
## координаты мировые, центр строки — точно над героем, поверх всего.
class LevelUpText:
	extends Label
	var _t := 0.0
	var _x0 := 0.0
	var _y0 := 0.0

	func _ready() -> void:
		text = Fx.LU_TEXT
		var f: Font = UIFont.get_font()
		if f != null:
			add_theme_font_override("font", f)   # Label под Node2D тему не наследует
		add_theme_font_size_override("font_size", Fx.LU_FONT_SIZE)
		add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		add_theme_constant_override("outline_size", 3)   # контур как у DmgNumbers
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 40           # над частицами (z=20), под числами урона (z=90)
		add_to_group("fx")     # учёт харнессу, как у частиц
		reset_size()
		position = Vector2(position.x - size.x * 0.5, position.y)  # центр над героем
		pivot_offset = size * 0.5
		_x0 = position.x
		_y0 = position.y

	func _process(delta: float) -> void:
		_t += delta
		var rise := 0.0
		var alpha := 1.0
		if _t < Fx.LU_RISE_T:
			rise = Fx.LU_RISE * (_t / Fx.LU_RISE_T)
		elif _t < Fx.LU_RISE_T + Fx.LU_HOLD_T:
			rise = Fx.LU_RISE
		elif _t < Fx.LU_RISE_T + Fx.LU_HOLD_T + Fx.LU_FADE_T:
			var k := (_t - Fx.LU_RISE_T - Fx.LU_HOLD_T) / Fx.LU_FADE_T
			rise = Fx.LU_RISE + 4.0 * k   # лёгкий добор вверх на растворении
			alpha = 1.0 - k
		else:
			queue_free()
			return
		position = Vector2(_x0, _y0 - rise)
		modulate = Color(1.0, 1.0, 1.0, alpha)

## Радиальная вспышка варианта 1: мягкая точка разрастается и гаснет за
## LU_FLASH_T. Растёт быстро в начале (sqrt), гаснет квадратом — читается как
## «вспыхнул и погас», а не «плавно растворился».
class LevelUpFlash:
	extends Sprite2D
	var _t := 0.0

	func _ready() -> void:
		centered = true
		scale = Vector2.ONE * Fx.LU_FLASH_S0
		z_index = 19
		add_to_group("fx")

	func _process(delta: float) -> void:
		_t += delta
		var k := _t / Fx.LU_FLASH_T
		if k >= 1.0:
			queue_free()
			return
		scale = Vector2.ONE * lerpf(Fx.LU_FLASH_S0, Fx.LU_FLASH_S1, sqrt(k))
		modulate = Color(Fx.LU_GOLD_HOT, (1.0 - k) * (1.0 - k))

## Импульс света варианта 1: энергия 2.6 -> 0 за LU_FLASH_T. Форма и цвет — как
## у пещерного факела, но разово и ярче факельной базы 0.9: в тёмной пещере это
## видно как вспышку, осветившую стены вокруг героя.
class LevelUpLight:
	extends PointLight2D
	var _t := 0.0

	func _ready() -> void:
		energy = Fx.LU_LIGHT_PEAK
		add_to_group("fx")

	func _process(delta: float) -> void:
		_t += delta
		var k := _t / Fx.LU_FLASH_T
		if k >= 1.0:
			queue_free()
			return
		energy = lerpf(Fx.LU_LIGHT_PEAK, 0.0, k * k)

## Столб света варианта 2: две фазы по 2 кадра (LU_BEAM_FRAME_T), затем
## растворение за LU_BEAM_FADE_T. Текстуры фаз строит Fx._beam_tex.
class LevelUpBeam:
	extends Sprite2D
	var tex_a: Texture2D
	var tex_b: Texture2D
	var _t := 0.0

	func _ready() -> void:
		centered = true
		z_index = 18
		add_to_group("fx")
		texture = tex_a

	func _process(delta: float) -> void:
		_t += delta
		if _t >= Fx.LU_BEAM_T + Fx.LU_BEAM_FADE_T:
			queue_free()
			return
		var unit := int(_t / Fx.LU_BEAM_FRAME_T)
		texture = tex_b if unit % 2 == 1 else tex_a
		var a := 1.0
		if _t > Fx.LU_BEAM_T:
			a = 1.0 - (_t - Fx.LU_BEAM_T) / Fx.LU_BEAM_FADE_T
		modulate = Color(1.0, 1.0, 1.0, a)

## Мягкий ореол у ног (вариант 2): дышит теми же фазами 2/2 кадра и гаснет
## вместе со столбом — чтобы вариант читался одним эффектом, а не тремя.
class LevelUpHalo:
	extends Sprite2D
	var _t := 0.0

	func _ready() -> void:
		centered = true
		z_index = 6      # под героем: ореол лежит на земле, а не поверх спрайта
		scale = Vector2(2.4, 1.1)
		modulate = Color(Fx.LU_GOLD, 0.85)
		add_to_group("fx")

	func _process(delta: float) -> void:
		_t += delta
		if _t >= Fx.LU_BEAM_T + Fx.LU_BEAM_FADE_T:
			queue_free()
			return
		var unit := int(_t / Fx.LU_BEAM_FRAME_T)
		var s := 2.4 if unit % 2 == 0 else 2.05
		var a := 0.85 if unit % 2 == 0 else 0.6
		if _t > Fx.LU_BEAM_T:
			a *= 1.0 - (_t - Fx.LU_BEAM_T) / Fx.LU_BEAM_FADE_T
		scale = Vector2(s, s * 0.46)
		modulate = Color(Fx.LU_GOLD, a)
