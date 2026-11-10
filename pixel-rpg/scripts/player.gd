extends CharacterBody2D
## Герой: WASD-движение, прицел мышью (ЛКМ — атака в сторону курсора),
## кувырок на пробеле (i-frames), класс из classes_data.gd, скиллы 1-4.

const Classes := preload("res://scripts/classes_data.gd")
const PROJ := preload("res://scripts/projectile.gd")

const ROLL_TIME := 0.22     # длительность кувырка
const ROLL_SPEED := 170.0   # скорость рывка (базовая скорость героя ~55)
const ROLL_CD := 0.9        # кулдаун после окончания кувырка

var anim: AnimatedSprite2D
var facing := "down"
var attack_cd := 0.0
var hurt_cd := 0.0
var _flash_t := 0.0
# --- кувырок ---
var roll_t := 0.0
var roll_cd := 0.0
var roll_dir := Vector2.RIGHT
# --- скиллы ---
var skill_cd := [0.0, 0.0, 0.0, 0.0]  # НЕ сериализуются
var pending_mult := 1.0               # «Мощный удар»: множитель следующего мили-удара
var mark_target: Node2D = null        # «Метка охотника»
var mark_t := 0.0
var siphon_t := 0.0                   # «Поглощение»: лечение от попаданий снарядов
var _atk_fx_t: Tween = null           # туин «подачи тела», один на героя

@onready var world: Node2D = get_parent()

func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 2 | 4  # стены + слаймы
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(10, 8)
	cs.shape = sh
	add_child(cs)
	anim = AnimatedSprite2D.new()
	add_child(anim)
	apply_class()
	anim.play("down")
	# тик регенерации — видимая искра над героем
	GameState.regen_hp_tick.connect(func() -> void:
		if is_instance_valid(self):
			Fx.heal(global_position + Vector2(0, -12), world))
	GameState.regen_mana_tick.connect(func() -> void:
		if is_instance_valid(self):
			_spark(global_position + Vector2(0, -12), Color(0.4, 0.65, 1.0, 0.9), 5.0))
	GameState.leveled_up.connect(func(_l: int) -> void:
		if is_instance_valid(self):
			Fx.level_up(global_position + Vector2(0, -10), world))

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
		fr.set_animation_speed(dir_name, 8.0)
		for col in [0, 1, 0, 2]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(col * 16, rows[dir_name] * 16, 16, 16)
			fr.add_frame(dir_name, at, 0.0)
	anim.sprite_frames = fr

# --- приказы удалены: прямое управление WASD + мышь-прицел ---

## Сброс «заряженных» состояний (смерть и пр.).
func cancel_orders() -> void:
	pending_mult = 1.0

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
		modulate = Color(1, 0.4, 0.4)
	else:
		modulate = Color.WHITE

	if GameState.input_locked:
		velocity = Vector2.ZERO
		roll_t = 0.0
		move_and_slide()
		return

	# --- кувырок (активная фаза: перекрывает обычный ход) ---
	if roll_t > 0.0:
		roll_t = maxf(0.0, roll_t - delta)
		velocity = roll_dir * ROLL_SPEED
		_set_facing_from(roll_dir)
		anim.play(facing)
		if roll_t == 0.0:
			anim.modulate.a = 1.0
		move_and_slide()
		return

	# --- WASD-ход ---
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = mv * float(class_data().speed)
	if velocity != Vector2.ZERO:
		_set_facing_from(velocity)
		anim.play(facing)
	else:
		# в покое герой смотрит на курсор — прицел melee-дуги всегда понятен
		face_to(world.get_global_mouse_position())
		if anim.animation != facing:
			anim.play(facing)
		anim.frame = 0
		anim.pause()
	move_and_slide()

	# --- атака удержанием ЛКМ в сторону курсора (не кликаем сквозь UI) ---
	if roll_t <= 0.0 and Input.is_action_pressed("attack") \
			and get_viewport().gui_get_hovered_control() == null:
		attack_at(world.get_global_mouse_position())

	# --- кувырок на пробеле ---
	if Input.is_action_just_pressed("roll") and roll_cd <= 0.0 and roll_t <= 0.0:
		start_roll(mv)

func _set_facing_from(v: Vector2) -> void:
	if absf(v.x) >= absf(v.y):
		facing = "right" if v.x > 0 else "left"
	else:
		facing = "down" if v.y > 0 else "up"

## Кувырок: рывок в сторону движения (или к курсору, если стоим).
## Во время roll_t герой неуязвим — перекат сквозь врагов и снаряды.
func start_roll(mv: Vector2) -> void:
	roll_dir = mv.normalized() if mv != Vector2.ZERO else _aim_dir()
	roll_t = ROLL_TIME
	roll_cd = ROLL_CD + ROLL_TIME
	_ring_fx(12.0, Color(0.75, 0.65, 0.5, 0.5))
	Fx.dust(global_position + roll_dir * 4.0, world)
	anim.modulate.a = 0.75

## Атака в мировую точку: встать лицом и ударить/выстрелить в её сторону.
func attack_at(p: Vector2) -> void:
	if attack_cd > 0.0 or roll_t > 0.0:
		return
	face_to(p)
	if String(class_data().kind) == "melee":
		do_attack()
	else:
		attack_cd = float(class_data().attack_speed)
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

## Урон по конкретному врагу с учётом «Метки охотника».
func dmg_vs(e: Node, mult: float) -> int:
	var d := float(GameState.damage) * mult
	if e == mark_target and mark_t > 0.0:
		d *= 1.5
	return int(round(d))

# --- атаки ---

func do_attack() -> void:
	if attack_cd > 0.0:
		return
	attack_cd = float(class_data().attack_speed)
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
	anim.position = Vector2.ZERO
	_atk_fx_t = create_tween()
	_atk_fx_t.tween_property(anim, "position", dir * dist, 0.06)
	_atk_fx_t.tween_property(anim, "position", Vector2.ZERO, 0.13)\
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
	match sid:
		"execute", "mark":
			if _skill_target() == null:
				return false  # без цели кулдаун не тратим
	# мана тратится после проверки цели — неудачный каст не «съедает» энергию
	if not GameState.try_spend_mana(int(sd.get("mana", 0))):
		return false
	skill_cd[i] = float(sd.cd)
	match sid:
		"power_strike":
			var t := _skill_target()
			if t != null and global_position.distance_to(t.global_position) <= float(class_data().radius):
				face_to(t.global_position)
				_lunge_fx(facing_dir(), 7.0)
				_slash_fx(Color(1.0, 0.85, 0.4, 0.95))
				melee_hit(2.0, Vector2.INF, 13.0, t)
			else:
				pending_mult = 2.0  # догнёт — следующий удар x2
		"whirlwind":
			_spin_fx()
			_ring_fx(28.0, Color(0.95, 0.92, 0.7, 0.4))
			melee_hit(1.5, global_position, 28.0)
		"second_wind":
			GameState.heal(4)
			GameState.toast.emit("Второй ветер: +4 HP")
		"execute":
			var t := _skill_target()
			face_to(t.global_position)
			_lunge_fx(facing_dir(), 8.0)
			_slash_fx(Color(1.0, 0.45, 0.35, 0.95))
			var mx := 12.0 if t.is_in_group("boss") else 3.0
			if float(t.hp) <= mx * 0.25:
				t.hurt(999, global_position)  # казнён
			else:
				melee_hit(1.5, Vector2.INF, 13.0, t)
		"pierce":
			fire_projectile(_shoot_dir(), 1.5, true, 0.0, 3)  # стрела-призрак
		"volley":
			var b := _shoot_dir()
			fire_projectile(b.rotated(-deg_to_rad(20.0)))
			fire_projectile(b)
			fire_projectile(b.rotated(deg_to_rad(20.0)))
		"mark":
			var t := _skill_target()
			mark_target = t
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
			Fx.heal(global_position + Vector2(0, -8), world)
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

func _shoot_dir() -> Vector2:
	return _aim_dir()

func _rain_marker(p: Vector2) -> void:
	var m := ColorRect.new()
	m.color = Color(1, 0.9, 0.3, 0.3)
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

func take_damage(n: int) -> void:
	if hurt_cd > 0.0 or roll_t > 0.0 or GameState.hp <= 0:
		return  # кувырок = i-frames: сквозь удары и снаряды
	hurt_cd = 0.8
	_flash_t = 0.35
	GameState.entered_combat()  # реген «замолкает» на время боя
	GameState.hurt(n)
	Fx.hit(global_position + Vector2(0, -6), world)
	if GameState.hp <= 0:
		cancel_orders()
		world.on_player_death()
