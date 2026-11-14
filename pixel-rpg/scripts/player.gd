extends CharacterBody2D
## Герой: WASD-движение, прицел мышью (ЛКМ — атака в сторону курсора),
## кувырок на пробеле (i-frames), класс из classes_data.gd, скиллы 1-4.

const Classes := preload("res://scripts/classes_data.gd")
const PROJ := preload("res://scripts/projectile.gd")

const ROLL_TIME := 0.22     # длительность кувырка
const ROLL_SPEED := 170.0   # скорость рывка (базовая скорость героя ~55)
const ROLL_CD := 0.9        # кулдаун после окончания кувырка
const ROLL_CD_FEET := 0.75  # алтарь «Лёгкие ноги»: КД при meta.feet>=1
# --- воин: «Рывок вепря» (rework second_wind) и награда «Казни» ---
const BOAR_DASH_RANGE := 72.0  # радиус поиска цели рывка, px (больше радиуса атаки)
const BOAR_DASH_STOP := 12.0   # встать от цели на дистанцию мили-удара, px
const BOAR_DASH_TIME := 0.14   # длительность полёта рывка, с (readable-dash: 8–9 кадров на 60 fps)
const BOAR_STUN := 0.7         # оглушение цели, с
const BOAR_STUN_BOSS := 0.35   # босс держит оглушение вдвое короче (канон brute)
const EXEC_HEAL := 3           # «Казнь» добивила цель: +HP воину (кламп по max_hp)
# --- t51: возврат «до Крупного мира» — рост героя = клетка 16 px, зум 1 ---
# Спрайт 16px рисуется 1:1 (масштаб-мультипликат H=32 снят по таблице
# VISUAL_REBUILD.md §3). Коллайдер 10x8, скорости и хитбоксы — не тронуты.
# ANIM_HOME = ZERO: спрайт возвращается в центр ноды (как было до волны 5),
# контент-стопы 16px-кадра (+5) задаёт сама картинка.
const VISUAL_SCALE := 1.0
const ANIM_HOME := Vector2.ZERO
# --- c19 «цикл ходьбы v1» (вердикт «добавляем», лист sheet_walk_v1) ---
# Кадр ходьбы — от ПРОЙДЕННОГО ПУТИ, не от времени: шаг «приклеен» к земле,
# не скользит и не зависит от частоты кадров. WALK_SEQ — порядок колонок
# hero.png (0 стойка, 1 шаг левой, 2 шаг правой): было [0,1,0,2], стало
# [1,0,2,0] — стойка стала проходной фазой между шагами, и на ОБЕИХ проходных
# фазах (позиции 1 и 3) герой поднимается на 1 px (WALK_BOB). Фаза =
# floor(путь/PX_PER_PHASE); 7 px при
# базовых 55 px/с — тот же темп 8 fps, что был. Кувырок/рывок — старая
# временная анимация (autoplay), контракт покоя: кадр стойки, bob=0.
const WALK_SEQ := [1, 0, 2, 0]
const WALK_BOB := [0, -1, 0, -1]
const PX_PER_PHASE := 7.0
const WALK_IDLE_FR := 1  # кадр стойки в новом порядке (колонка 0 = прежний кадр 0)
# t52 снос (закон пользователя 13.11): ген-герой art_gen снят — герой снова
# рисуется пиксельным листом класса (player.png-канон), код-арт без картинок gen.

var anim_home := ANIM_HOME
var head_y := -8.0  # линия макушки 16px-героя (искры/цифры поднимаем вместе с головой)

var anim: AnimatedSprite2D
var facing := "down"
var walk_dist := 0.0  # c19: пройденный путь, px; фаза производна от него, НЕ сериализуется
var attack_cd := 0.0
var hurt_cd := 0.0
var _flash_t := 0.0
# --- кувырок ---
var roll_t := 0.0
var roll_cd := 0.0
var roll_dir := Vector2.RIGHT
# --- «Рывок вепря»: фаза полёта (ввод залочен, удар/стан — на финише) ---
var boar_t := 0.0                   # >0 — летим; тикает в _physics_process
var boar_from := Vector2.ZERO
var boar_dest := Vector2.ZERO
var boar_target: Node2D = null      # цель на старте; валидность проверяем на приземлении
var boar_dust := 0                  # сколько промежуточных пылей шлейфа выпущено
# --- скиллы ---
var skill_cd := [0.0, 0.0, 0.0, 0.0]  # НЕ сериализуются
var pending_mult := 1.0               # «Мощный удар»: множитель следующего мили-удара
var mark_target: Node2D = null        # «Метка охотника»
var mark_t := 0.0
var siphon_t := 0.0                   # «Поглощение»: лечение от попаданий снарядов
var _atk_fx_t: Tween = null           # туин «подачи тела», один на героя
var _step_t := 0.0                    # таймер звука шага
var _step_alt := false                # чередование двух сэмплов шага
var _swing_alt := false               # t31: чередование двух процедурных ударов
var _ghost_t := 0.0                   # t18: таймер паузы между «призраками» шлейфа

@onready var world: Node2D = get_parent()

func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	# Только стены: моб больше физически не блокирует героя, а герой — моба.
	# Вплотную два CharacterBody2D пилили друг друга каждый кадр в противофазе
	# (move_and_slide), и экран дребезжал. «Стенку» без пиления даёт мягкий
	# односторонний выталкивание моба от героя (_push_from_hero в mob*.gd).
	collision_mask = 2
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(10, 8)
	cs.shape = sh
	add_child(cs)
	anim = AnimatedSprite2D.new()
	# t51: герой 1:1 (VISUAL_SCALE=1.0) — тело, коллайдер 10x8 и всё движение
	# не тронуты мультипликатами
	anim.scale = Vector2.ONE * VISUAL_SCALE
	anim.position = ANIM_HOME
	add_child(anim)
	apply_class()
	anim.play("down")
	# тик регенерации — видимая искра над героем (t51 «было»: heal −12, spark −10,
	# levelup −8 относительно позиции героя)
	GameState.regen_hp_tick.connect(func() -> void:
		if is_instance_valid(self):
			Fx.heal(global_position + Vector2(0, -12), world))
	GameState.regen_mana_tick.connect(func() -> void:
		if is_instance_valid(self):
			_spark(global_position + Vector2(0, -10), Color(0.4, 0.65, 1.0, 0.9), 5.0))
	GameState.leveled_up.connect(func(_l: int) -> void:
		if is_instance_valid(self):
			Fx.level_up(global_position + Vector2(0, -8), world))

func class_data() -> Dictionary:
	return Classes.class_data(GameState.class_id)

## Вызвать после выбора/смены класса и загрузки сейва: перекрасить героя.
func apply_class() -> void:
	var path := String(class_data().sprites)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif ResourceLoader.exists("res://assets/player.png"):
		push_warning("Нет ассета: %s — герой дефолтным спрайтом" % path)
		tex = load("res://assets/player.png")
	if tex != null:
		_build_frames(tex)

func _build_frames(tex: Texture2D) -> void:
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	var rows := {"down": 0, "left": 1, "right": 2, "up": 3}
	for dir_name in rows:
		fr.add_animation(dir_name)
		fr.set_animation_loop(dir_name, true)
		fr.set_animation_speed(dir_name, 8.0)  # автоиграет только кувырок/рывок (c19)
		for col in WALK_SEQ:  # c19: порядок кадров = цикл [1,0,2,0] (колонки hero.png)
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(col * 16, rows[dir_name] * 16, 16, 16)
			fr.add_frame(dir_name, at, 0.0)
	anim.sprite_frames = fr

# --- приказы удалены: прямое управление WASD + мышь-прицел ---

## Сброс «заряженных» состояний (смерть и пр.).
func cancel_orders() -> void:
	pending_mult = 1.0
	boar_t = 0.0
	boar_target = null
	anim.modulate.a = 1.0

func _physics_process(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	hurt_cd = maxf(0.0, hurt_cd - delta)
	_flash_t = maxf(0.0, _flash_t - delta)
	siphon_t = maxf(0.0, siphon_t - delta)
	roll_cd = maxf(0.0, roll_cd - delta)
	if mark_t > 0.0:
		mark_t -= delta
		if mark_t <= 0.0:
			mark_target = null
	for i in skill_cd.size():
		skill_cd[i] = maxf(0.0, skill_cd[i] - delta)
	if _flash_t > 0:
		# t18 «сочность»: короткая (≤0.1 с) горячая вспышка — короче кадра моргания,
		# яркость выше единицы (LINEAR-рендер разрешает >1) — удар «бьёт» по глазам
		modulate = Color(1.9, 0.55, 0.5)
	else:
		modulate = Color.WHITE

	if GameState.input_locked:
		velocity = Vector2.ZERO
		roll_t = 0.0
		boar_t = 0.0
		boar_target = null  # диалог на середине рывка: отменяем полёт (как прерванный кувырок)
		anim.modulate.a = 1.0  # прерванный диалогом кувырок: не залипаем полупрозрачным (фикс T5)
		move_and_slide()
		return

	# --- кувырок (активная фаза: перекрывает обычный ход) ---
	if roll_t > 0.0:
		roll_t = maxf(0.0, roll_t - delta)
		velocity = roll_dir * ROLL_SPEED
		_set_facing_from(roll_dir)
		_play_walk()
		_ghost_tick(delta)  # t18: «призрачный» шлейф скорости
		if roll_t == 0.0:
			anim.modulate.a = 1.0
			_spawn_ghost()  # последний силуэт в точке приземления
		move_and_slide()
		return

	# --- «Рывок вепря» (активная фаза): тот же механизм лока ввода, что кувырок —
	# движение считаем сами, WASD/атаку/пробел в эти кадры не читаем ---
	if boar_t > 0.0:
		_boar_step(delta)
		return

	# --- WASD-ход ---
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Талант «Скороход» (stride, CONTRACT_TALENTS §3): скорость хода +5% за ранг
	# (рывок кувырка — своя константа ROLL_SPEED, талантом не ускоряется).
	velocity = mv * float(class_data().speed) * (1.0 + 0.05 * GameState.tal_rank("stride"))
	# t20 «Пепельная поступь» мета-доски (meta.mb.ash_step): +4/8/12% к скорости
	# хода за ранг. Поверх «Скорохода» (пер × проценты складываются мультипликативно).
	velocity *= 1.0 + 0.01 * float(GameState.mb_value("ash_step"))
	if velocity != Vector2.ZERO:
		_set_facing_from(velocity)
		_walk_tick(delta)
		_step_tick(delta)
	else:
		_step_t = 0.0  # встал — следующий шаг зазвучит сразу, не «доедет» по таймеру
		# в покое герой смотрит на курсор — прицел melee-дуги всегда понятен
		face_to(world.get_global_mouse_position())
		if anim.animation != facing:
			anim.play(facing)
		anim.frame = WALK_IDLE_FR  # кадр стойки (колонка 0) — вид как до c19
		anim.offset = Vector2.ZERO
		anim.pause()
	var pre_pos := global_position
	var pre_vel := velocity  # move_and_slide обнуляет упирающуюся компоненту — бережём намерение
	move_and_slide()
	_corner_slip(pre_pos, pre_vel)  # «угловая коррекция»: упор в стену по оси -> соскальзывание

	# --- атака удержанием ЛКМ в сторону курсора (не кликаем сквозь UI) ---
	if roll_t <= 0.0 and Input.is_action_pressed("attack") \
			and get_viewport().gui_get_hovered_control() == null:
		attack_at(world.get_global_mouse_position())

	# --- кувырок на пробеле ---
	if Input.is_action_just_pressed("roll") and roll_cd <= 0.0 and roll_t <= 0.0:
		start_roll(mv)

## Угловая коррекция (классический Zelda-приём): если упёрся в стену строго по
## оси (скорость есть, is_on_wall(), фактическое смещение ~0) — микро-сандж
## перпендикулярно на 4..6 px в первую свободную сторону (чисты и сам сандж, и
## шаг вперёд с новой точки) и повторный move_and_slide. Полный стоп превращается
## в соскальзывание вдоль препятствия: деревья/углы больше не тормозят ход.
## Детерминированно: никаких randf, порядок сторон фиксирован. Только WASD-ход:
## кувырок и «рывок вепря» — отдельные ветки _physics_process, их не трогаем.
func _corner_slip(pre_pos: Vector2, pre_vel: Vector2) -> void:
	if pre_vel == Vector2.ZERO:
		return
	if global_position.distance_to(pre_pos) > 0.05:
		return  # не полный стоп (уже скользим вдоль) — не вмешиваемся
	var fwd := pre_vel.normalized()
	if not test_move(Transform2D(0.0, global_position), fwd):
		return  # впереди свободно — пилящих касаний нет, не вмешиваемся
	var perp := fwd.orthogonal()  # единичный (от нормализованного)
	var step_len := pre_vel.length() * get_physics_process_delta_time()
	# Ищем сторону, с которой шаг вперёд открывается: микро-пробы 4..6 px — как в
	# контракте; 8..12 px — только «разведка» (для толстых столбов), шаг всё равно
	# не больше 6 px за кадр, проход вокруг ствола накапливается за 2-3 кадра.
	# Плоская стена/угол: вперёд закрыто с любой точки до 12 px в обе стороны —
	# герой НЕ начинает ползти вдоль стены сам по себе.
	for probe: float in [4.0, 5.0, 6.0, 8.0, 10.0, 12.0]:
		for s: float in [-1.0, 1.0]:
			if test_move(Transform2D(0.0, global_position), perp * (probe * s)):
				continue  # сюда и вбок нельзя
			if test_move(Transform2D(0.0, global_position + perp * (probe * s)), fwd * step_len):
				continue  # и вперёд с этой точки тоже закрыто
			var side := perp * (minf(probe, 6.0) * s)
			position += side
			velocity = pre_vel
			move_and_slide()
			return

func _set_facing_from(v: Vector2) -> void:
	if absf(v.x) >= absf(v.y):
		facing = "right" if v.x > 0 else "left"
	else:
		facing = "down" if v.y > 0 else "up"

## Ход: прежний листовой канон (4 направления, 3 кадра).
## Автоигра кадров — только кувырок/рывок (c19: WASD-ход перешёл на _walk_tick).
func _play_walk() -> void:
	anim.play(facing)

## c19 «цикл ходьбы v1»: кадр — от пройденного пути (WALK_SEQ), проходные
## фазы (стойка между шагами) поднимают спрайт на 1 px (WALK_BOB). Автоигра
## выключена (pause): фаза производна от пути, поэтому шаг не скользит при
## упоре в стену и не зависит от частоты кадров. walk_dist не сериализуется:
## после загрузки фаза продолжается от нового пути, а не из сейва.
func _walk_tick(delta: float) -> void:
	if anim.animation != facing:
		anim.play(facing)
	anim.pause()
	walk_dist += velocity.length() * delta
	var ph := int(walk_dist / PX_PER_PHASE) % WALK_SEQ.size()
	if anim.frame != ph:
		anim.frame = ph
	anim.offset.y = float(WALK_BOB[ph])

## Шаг: два сэмпла попеременно, лёгкий разброс темпа и высоты — не «швейная машинка».
func _step_tick(delta: float) -> void:
	_step_t -= delta
	if _step_t > 0.0:
		return
	_step_t = 0.38
	_step_alt = not _step_alt
	GameAudio.sfx("step1" if _step_alt else "step2", 1.0, randf_range(0.9, 1.1))

## Кувырок: рывок в сторону движения (или к курсору, если стоим).
## Во время roll_t герой неуязвим — перекат сквозь врагов и снаряды.
func start_roll(mv: Vector2) -> void:
	roll_dir = mv.normalized() if mv != Vector2.ZERO else _aim_dir()
	roll_t = ROLL_TIME
	# Талант «Лёгкая поступь» (lightfoot): откат кувырка -0.1 с, пол 0.15 с.
	roll_cd = maxf(0.15, (ROLL_CD_FEET if int(GameState.flags.get("meta.feet", 0)) >= 1 else ROLL_CD) + ROLL_TIME - 0.1 * GameState.tal_rank("lightfoot"))
	GameAudio.sfx("roll")  # шорох ткани на старте кувырка
	_ring_fx(12.0, Color(0.75, 0.65, 0.5, 0.5))
	Fx.dust(global_position + roll_dir * 4.0, world)
	anim.modulate.a = 0.75
	anim.offset = Vector2.ZERO  # c19: кувырок стартует без bob проходной фазы
	_ghost_t = 0.0

## t18 «сочность»: призрачный шлейф рывка — затухающие силуэты текущего кадра.
## Кратковременные Sprite2D в world (не в группах enemy/player, без get_hint —
## атмосфера их игнорирует), живут 0.2 с и queue_free — узлы не копятся.
func _ghost_tick(delta: float) -> void:
	_ghost_t -= delta
	if _ghost_t <= 0.0:
		_ghost_t = 0.05
		_spawn_ghost()

func _spawn_ghost() -> void:
	if world == null or anim == null:
		return
	if anim.sprite_frames == null or not anim.sprite_frames.has_animation(anim.animation) \
			or anim.sprite_frames.get_frame_count(anim.animation) == 0:
		return
	var tex := anim.sprite_frames.get_frame_texture(anim.animation, anim.frame)
	if tex == null:
		return
	var g := Sprite2D.new()
	g.name = "DashGhost"
	g.texture = tex
	g.scale = anim.scale
	g.flip_h = anim.flip_h
	g.texture_filter = anim.texture_filter
	g.self_modulate = Color(0.85, 0.9, 1.0, 0.4)  # холодный «остаточный образ»
	world.add_child(g)
	g.global_position = global_position + anim.position
	var t := g.create_tween()
	t.tween_property(g, "self_modulate:a", 0.0, 0.2)
	t.tween_callback(g.queue_free)

## Атака в мировую точку: встать лицом и ударить/выстрелить в её сторону.
func attack_at(p: Vector2) -> void:
	if attack_cd > 0.0 or roll_t > 0.0:
		return
	# t31: два тёплых процедурных удара поочерёдно (Kenney "attack" на этом
	# событии ЗАМЕНЁН, а не задвоен). Ровно раз на удар: держание ЛКМ глушит
	# кулдаун выше.
	_swing_alt = not _swing_alt
	Sfx.play("hit_a" if _swing_alt else "hit_b")
	face_to(p)
	if String(class_data().kind) == "melee":
		do_attack()
	else:
		# Талант «Берсеркова удаль» (zeal): задержка выстрела ×0.92 после класса.
		attack_cd = float(class_data().attack_speed) * (0.92 if GameState.tal_rank("zeal") > 0 else 1.0)
		var dir := global_position.direction_to(p)
		_recoil_fx(dir)
		fire_projectile(dir)

## Направление прицела: от героя к курсору (в Standby — лицом).
func _aim_dir() -> Vector2:
	var d := world.get_global_mouse_position() - global_position
	return d.normalized() if d.length() > 2.0 else facing_dir()

## Отдача дальнобойщика: корпус слегка отводит назад от выстрела.
func _recoil_fx(dir: Vector2) -> void:
	_lunge_fx(-dir, 3.0)

func face_to(p: Vector2) -> void:
	var d := p - global_position
	if absf(d.x) >= absf(d.y):
		facing = "right" if d.x > 0 else "left"
	else:
		facing = "down" if d.y > 0 else "up"

func facing_dir() -> Vector2:
	match facing:
		"down": return Vector2(0, 1)
		"up": return Vector2(0, -1)
		"left": return Vector2(-1, 0)
		_: return Vector2(1, 0)

func facing_offset() -> Vector2:
	return facing_dir() * 12.0

## Урон по конкретному врагу с учётом «Метки охотника» и благословения волхвы
## (t20 P0-3: +2% за смерть круга, кап +20% — GameState.volkhv_bless_mult;
## единая точка умножения урона героя: все атаки/скиллы идут через dmg_vs).
func dmg_vs(e: Node, mult: float) -> int:
	var d := float(GameState.damage) * mult * GameState.volkhv_bless_mult()
	if e == mark_target and mark_t > 0.0:
		d *= 1.5
	return int(round(d))

# --- атаки ---

func do_attack() -> void:
	if attack_cd > 0.0:
		return
	# Талант «Берсеркова удаль» (zeal): задержка удара ×0.92 после класса.
	attack_cd = float(class_data().attack_speed) * (0.92 if GameState.tal_rank("zeal") > 0 else 1.0)
	var mult := pending_mult
	pending_mult = 1.0
	_lunge_fx(facing_dir(), 5.0)
	_slash_fx()
	melee_hit(mult)

# --- визуал атак (без новых ассетов: pure tween/poligon) ---

## Подача тела: спрайт резко наклоняется к цели и упруго возвращается.
## Двигаем anim (визуальный ребёнок), физику не трогаем.
func _lunge_fx(dir: Vector2, dist: float) -> void:
	if _atk_fx_t != null and _atk_fx_t.is_valid():
		_atk_fx_t.kill()
	# волна 5: «домой» спрайт возвращается не в ноль, а в якорь ног (anim_home:
	# −5 для пиксельных листов, −11 для tight-кропа t17)
	anim.position = anim_home
	_atk_fx_t = create_tween()
	_atk_fx_t.tween_property(anim, "position", anim_home + dir * dist, 0.06)
	_atk_fx_t.tween_property(anim, "position", anim_home, 0.13)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Дуга замаха: серповидный «всплеск» клинка, проворачивается по дуге и гаснет.
func _slash_fx(color := Color(0.93, 0.96, 1.0, 0.9)) -> void:
	var sw := Node2D.new()
	sw.name = "SlashFx"
	sw.global_position = global_position
	var base := facing_dir().angle()
	sw.rotation = base - 0.85
	var arc := Polygon2D.new()
	var pts := PackedVector2Array()
	var n := 8
	for i in n + 1:
		var a := deg_to_rad(-55.0 + 110.0 * float(i) / float(n))
		pts.append(Vector2(cos(a), sin(a)) * 14.0)
	for i in n + 1:
		var a := deg_to_rad(55.0 - 110.0 * float(i) / float(n))
		pts.append(Vector2(cos(a), sin(a)) * 8.5)
	arc.polygon = pts
	arc.color = color
	sw.add_child(arc)
	world.add_child(sw)
	var t := sw.create_tween()
	t.set_parallel(true)
	t.tween_property(sw, "rotation", base + 0.85, 0.16)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(arc, "modulate:a", 0.0, 0.22)
	t.chain().tween_callback(sw.queue_free)

## Расходящееся кольцо (вихревой удар, нова).
func _ring_fx(radius: float, color := Color(0.95, 0.9, 0.7, 0.35)) -> void:
	var ring := Polygon2D.new()
	ring.name = "RingFx"
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(Vector2(cos(a), sin(a)))
	ring.polygon = pts
	ring.color = color
	ring.scale = Vector2.ONE * 6.0
	world.add_child(ring)
	ring.global_position = global_position
	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2.ONE * radius, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(ring.queue_free)

## Оборот героя вокруг себя (вихревой удар): спрайт делает полный оборот.
func _spin_fx() -> void:
	anim.rotation = 0.0
	var t := create_tween()
	t.tween_property(anim, "rotation", TAU, 0.28)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): anim.rotation = 0.0)

## Мгновенный мили-удар: враги в радиусе точки удара (12 px по facing).
func melee_hit(mult: float, center := Vector2.INF, radius := 13.0, only: Node2D = null) -> void:
	var c := center if center != Vector2.INF else global_position + facing_offset()
	Fx.hit(c, world)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("hurt"):
			continue
		if only != null and e != only:
			continue
		if e.global_position.distance_to(c) <= radius + _enemy_size(e) * 0.5:
			e.hurt(dmg_vs(e, mult), global_position)

static func _enemy_size(e: Node) -> float:
	return 18.0 if e.is_in_group("boss") else 10.0

func _spark(c: Vector2, color := Color(1, 1, 0.8, 0.85), size := 6.0) -> void:
	var spark := ColorRect.new()
	spark.name = "SparkFx"
	spark.color = color
	spark.size = Vector2(size, size)
	spark.position = c - global_position - Vector2(size, size) * 0.5
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spark)
	var t := spark.create_tween()
	t.tween_property(spark, "modulate:a", 0.0, 0.18)
	t.tween_callback(spark.queue_free)

## Выпустить снаряд класса (или указанный). Кулдаун автоатаки не трогает —
## вызывающий сам решает (автоатака ставит cd сама, скиллы — нет).
func fire_projectile(dir: Vector2, mult := 1.0, pierce := false, aoe := 0.0, sprite := -1) -> void:
	var idx := sprite if sprite >= 0 else int(class_data().projectile)
	if idx < 0:
		return
	var tgt := _skill_target()
	var d := dmg_vs(tgt, mult) if tgt != null else int(round(float(GameState.damage) * mult))
	var muzzle := global_position + dir * 8.0
	var pd = PROJ.new()
	world.add_child(pd)
	pd.setup(muzzle, dir, float(class_data().proj_speed), d, idx, pierce, aoe, self)
	# вспышка у дула: очевидно, что снаряд только что выпущен
	_spark(muzzle, Color(1, 1, 0.85, 0.9), 4.0)

# --- скиллы ---

## Каст скилла по слоту 0..3 (клавиши 1-4 или клик по иконке).
## at — точка под курсором (для «Дождя стрел»), Vector2.INF — без точки.
func cast_skill(i: int, at := Vector2.INF) -> bool:
	if i < 0 or i >= 4 or GameState.input_locked or GameState.class_id == "":
		return false
	var sids: Array = Classes.skills_for(GameState.class_id)
	var sid := String(sids[i])
	var sd := Classes.skill(sid)
	if GameState.level < int(sd.level) or skill_cd[i] > 0.0:
		return false
	# Проверка цели ДО кулдауна и маны: без цели скилл не активируется и
	# не тратится (power_strike/«Рывок вепря» — с отказом-подсказкой, п.6).
	var tgt: Node2D = null
	match sid:
		"execute", "mark":
			tgt = _skill_target()
			if tgt == null:
				return false  # без цели кулдаун не тратим
		"power_strike":
			tgt = _skill_target()  # радиус досягаемости = радиус обычной атаки
			if tgt == null:
				_no_target_reject()
				return false
		"second_wind":
			tgt = _dash_target()  # свой радиус шире атаки — рывок «догоняет»
			if tgt == null:
				_no_target_reject()
				return false
	# мана тратится после проверки цели — неудачный каст не «съедает» энергию
	if not GameState.try_spend_mana(int(sd.get("mana", 0))):
		return false
	skill_cd[i] = float(sd.cd)
	GameAudio.sfx("spell")  # файла spell.wav пока нет — тихий пропуск (guarded)
	match sid:
		"power_strike":
			# «Догнать-режим» убран: без цели в радиусе скилл не активируется
			# вовсе (guard выше), здесь цель всегда есть и она досягаема.
			face_to(tgt.global_position)
			_lunge_fx(facing_dir(), 7.0)
			# t18 цветовая дисциплина: смертельный удар — красное семейство (золото = лут)
			_slash_fx(Color(1.0, 0.45, 0.35, 0.95))
			melee_hit(2.0, Vector2.INF, 13.0, tgt)
		"whirlwind":
			_spin_fx()
			_ring_fx(28.0, Color(0.95, 0.92, 0.7, 0.4))
			melee_hit(1.5, global_position, 28.0)
		"second_wind":
			_boar_dash(tgt)
		"execute":
			face_to(tgt.global_position)
			_lunge_fx(facing_dir(), 8.0)
			_slash_fx(Color(1.0, 0.45, 0.35, 0.95))
			# Честный порог (фикс T10): <=25% макс. HP цели, минимум 1 HP.
			# max_hp читаем у врага, если он его задаёт; иначе константы slime/brute.
			var mhp := 12.0 if tgt.is_in_group("boss") else 3.0
			if tgt.get("max_hp") != null:
				mhp = float(tgt.get("max_hp"))
			if int(tgt.hp) <= maxi(1, int(mhp * 0.25)):
				tgt.hurt(999, global_position)  # казнён
				# Награда палача (п.7): цель УМЕРЛА от казни — воин восстанавливает
				# EXEC_HEAL HP (heal клампит по max_hp). Промах/не-добивание — без хила.
				if tgt.get("hp") != null and int(tgt.get("hp")) <= 0:
					GameState.heal(EXEC_HEAL)
					Fx.heal(global_position + Vector2(0, -12), world)  # t51: было −12
					GameState.toast.emit("+%d HP" % EXEC_HEAL)
			else:
				melee_hit(1.5, Vector2.INF, 13.0, tgt)
		"pierce":
			fire_projectile(_shoot_dir(), 1.5, true, 0.0, 3)  # стрела-призрак
		"volley":
			var b := _shoot_dir()
			fire_projectile(b.rotated(-deg_to_rad(20.0)))
			fire_projectile(b)
			fire_projectile(b.rotated(deg_to_rad(20.0)))
		"mark":
			mark_target = tgt
			mark_t = 6.0
			GameState.toast.emit("Метка на цели!")
		"rain":
			var pt := at
			if pt == Vector2.INF:
				var t2 := _skill_target()
				pt = t2.global_position if t2 != null else global_position
			_rain_marker(pt)
			get_tree().create_timer(0.5).timeout.connect(func(): _rain_burst(pt))
		"firebolt":
			var fb_dir := _shoot_dir()
			fire_projectile(fb_dir, 2.5, false, 12.0, 1)
			Fx.fire_trail(global_position + fb_dir * 8.0, global_position + fb_dir * 56.0, world)
		"frost_nova":
			_ring_fx(32.0, Color(0.55, 0.85, 1.0, 0.5))
			Fx.frost_ring(global_position, 32.0, world)
			for e in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(e) and "freeze_t" in e and global_position.distance_to(e.global_position) <= 32.0:
					e.freeze_t = 3.0
			GameState.entered_combat()  # заморозка — тоже бой, хоть и без урона
			GameState.toast.emit("Морозная нова!")
		"siphon":
			siphon_t = 5.0
			Fx.heal(global_position + Vector2(0, -12), world)  # t51: было −8…−12, сводим к −12
			GameState.toast.emit("Поглощение: попадания снарядов лечат")
		"firestorm":
			for k in 3:
				get_tree().create_timer(0.5 * (k + 1)).timeout.connect(_firestorm_tick)
	return true

## Цель скилла: ближайший враг в радиусе класса.
func _skill_target() -> Node2D:
	var best: Node2D = null
	var bd := float(class_data().radius)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d <= bd:
			bd = d
			best = e
	return best

## Отказ каста без цели («Нет цели рядом»): звук + вспышка + тост.
## Кулдаун и мана НЕ тратятся — скилл просто не активировался (п.6).
func _no_target_reject() -> void:
	GameAudio.sfx("ui_deny")
	_spark(global_position + Vector2(0, -10), Color(1.0, 0.72, 0.3, 0.9), 5.0)  # t18: отказ = interact-фидбек, амбер; t51: было −10
	GameState.toast.emit("Нет цели рядом")

## Цель «Рывка вепря»: ближайший враг в собственном радиусе (шире радиуса атаки).
func _dash_target() -> Node2D:
	var best: Node2D = null
	var bd := BOAR_DASH_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d <= bd:
			bd = d
			best = e
	return best

## «Рывок вепря» (rework «Второго ветра»): догнать цель (BOAR_DASH_TIME = 0.14 с,
## ease-out — быстрый старт, readable) сквозь врагов, но не сквозь стены (ray по
## слою стен 2, маржа 5 px), встать на дистанцию мили-удара; удар 1x и оглушение
## freeze_t — существующей mob-механикой «замри» (frost_nova: моб не двигается и не
## атакует) — НАНОСЯТСЯ ПОСЛЕ ПРИЗЕМЛЕНИЯ (_boar_land), чтобы не бить сквозь стену
## раньше доезда. Босс оглушается вдвое короче (BOAR_STUN_BOSS) — канон brute: Гром
## держит удар, но не резистен полностью. Если стена встала ближе дистанции удара —
## рывок короткая: ни оглушения, ни удара (кулдаун при этом потрачен на старте,
## цель была в радиусе). Цель погибла в полёте — приземляемся без удара.
func _boar_dash(t: Node2D) -> void:
	var from := global_position
	var dir := (t.global_position - from).normalized()
	var dest := t.global_position - dir * BOAR_DASH_STOP
	var q := PhysicsRayQueryParameters2D.create(from, dest, 2, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		# встать до стены с маржой 5 px (у ray-результата нет distance — мерим до point)
		dest = from + dir * maxf(0.0, from.distance_to(hit["position"]) - 5.0)
	boar_from = from
	boar_dest = dest
	boar_target = t
	boar_dust = 0
	boar_t = BOAR_DASH_TIME
	_set_facing_from(dir)
	_play_walk()
	anim.modulate.a = 0.75  # как кувырок: полупрозрачность скорости на время полёта
	_ghost_t = 0.0
	Fx.dust(from, world)

## Кадры полёта: позиция по заранее посчитанному ray-маршруту (ease-out),
## шлейф из 2 промежуточных пылей; по окончании — финиш-хэндлер.
func _boar_step(delta: float) -> void:
	boar_t = maxf(0.0, boar_t - delta)
	var p := clampf(1.0 - boar_t / BOAR_DASH_TIME, 0.0, 1.0)
	var e := 1.0 - (1.0 - p) * (1.0 - p)  # квадратичный ease-out: резкий старт, посадка
	global_position = boar_from.lerp(boar_dest, e)
	velocity = Vector2.ZERO
	_ghost_tick(delta)  # t18: шлейф «маха лапой» в полёте
	if boar_dust < 2 and p >= 0.34 * float(boar_dust + 1):
		boar_dust += 1
		Fx.dust(global_position, world)
	if boar_t <= 0.0:
		global_position = boar_dest
		_boar_land()

## Приземление: только здесь стан/удар/тосты — семантика прежняя, но «не бьём
## в полёте». Кулдаун потрачен на старте каста (канон) и в полёте не возвращается.
func _boar_land() -> void:
	boar_t = 0.0
	anim.modulate.a = 1.0
	_spawn_ghost()  # t18: последний силуэт в точке приземления
	var t := boar_target
	boar_target = null
	Fx.dust(global_position, world)
	if GameState.hp <= 0:
		return  # герой погиб в полёте — приземление без удара
	if t == null or not is_instance_valid(t) \
			or (t.get("hp") != null and int(t.get("hp")) <= 0):
		return  # цель погибла/умирает в полёте: приземляемся без удара
	face_to(t.global_position)
	if global_position.distance_to(t.global_position) > 13.0 + _enemy_size(t) * 0.5:
		GameState.toast.emit("Стена помешала рывку")
		return
	_lunge_fx(facing_dir(), 7.0)
	_slash_fx(Color(0.95, 0.5, 0.38, 0.95))  # t18: красное семейство (смертельный удар)
	if t.get("freeze_t") != null:
		t.freeze_t = BOAR_STUN_BOSS if t.is_in_group("boss") else BOAR_STUN
	melee_hit(1.0, Vector2.INF, 13.0, t)

func _shoot_dir() -> Vector2:
	return _aim_dir()

func _rain_marker(p: Vector2) -> void:
	var m := ColorRect.new()
	m.color = Color(1.0, 0.35, 0.28, 0.3)  # t18: телеграф дождя — красный (смертельный), не золото
	m.size = Vector2(60, 60)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(m)
	m.global_position = p - Vector2(30, 30)
	var t := m.create_tween()
	t.tween_interval(0.5)
	t.tween_property(m, "modulate:a", 0.0, 0.05)
	t.tween_callback(m.queue_free)

func _rain_burst(p: Vector2) -> void:
	_spark(p)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("hurt") and p.distance_to(e.global_position) <= 30.0:
			e.hurt(dmg_vs(e, 2.0), p)

func _firestorm_tick() -> void:
	if not is_instance_valid(self):
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("hurt") and global_position.distance_to(e.global_position) <= 36.0:
			e.hurt(dmg_vs(e, 1.0), global_position)
	Fx.fire_burst(global_position + Vector2(randf_range(-14, 14), randf_range(-14, 14)), world)

# --- получение урона ---

## src — kind атакующего ("slime"/"brute"/…), опционально (t20 P0-3): на
## фатальном ударе пишется в rs.src — экран смерти показывает «пал от: …».
## QA-вызовы с одним аргументом (без src) безопасны: пустая строка.
func take_damage(n: int, src := "") -> void:
	if hurt_cd > 0.0 or roll_t > 0.0 or GameState.hp <= 0:
		return  # кувырок = i-frames: сквозь удары и снаряды
	hurt_cd = 0.8
	_flash_t = 0.09  # t18: вспышка цели ≤0.1 с (яркость компенсирована >1 tint'ом)
	GameState.entered_combat()  # реген «замолкает» на время боя
	var _hp0 := GameState.hp  # число урона = реально снятые HP (после брони), не входящий урон
	GameState.hurt(n)
	DmgNumbers.spawn(global_position + Vector2(0, -12), maxi(0, _hp0 - GameState.hp), "normal")  # t51: было −12
	Fx.hit(global_position + Vector2(0, -6), world)
	Sfx.play("hurt")  # t31:глухой тёплый «в тело» (процедурный каталог)
	# t18 «сочность»: hitstop + тряска; фатальный удар — тяжелее. Восстановление
	# time_scale гарантировано realtime-watchdog'ом juice.gd (смерть/диалог не залипают).
	Juice.hit()
	if GameState.hp <= 0:
		Juice.shake(2.4, 0.22)   # фатальный удар — тяжёлый мазок
	else:
		Juice.shake(1.6, 0.14)
	if GameState.hp <= 0:
		# t20 P0-3: память об убийце для экрана смерти (RS «пал от: …»).
		if src != "":
			GameState.flags["rs.src"] = src
		cancel_orders()
		world.on_player_death()
