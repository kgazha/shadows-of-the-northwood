extends CharacterBody2D
## Герой спринта 2: управление мышью (приказы идти/атаковать/взаимодействовать),
## класс из classes_data.gd, автоатака (мили — do_attack, дальние — снаряд),
## скиллы 1-4 с кулдаунами. WASD убран.

const Classes := preload("res://scripts/classes_data.gd")
const PROJ := preload("res://scripts/projectile.gd")

const LEASH := 160.0        # погоня за целью дальше этой точки от приказа — отмена
const ARRIVE := 3.0         # точность прихода в точку приказа
const INTERACT_DIST := 14.0 # дистанция, с которой выполняем try_interact
const CANCEL_RATIO := 0.35  # прошли меньше CANCEL_RATIO желаемого — упёрлись, отмена

var anim: AnimatedSprite2D
var facing := "down"
var attack_cd := 0.0
var hurt_cd := 0.0
var _flash_t := 0.0

# --- приказы мышью ---
var move_target := Vector2.INF     # идти в точку
var attack_target: Node2D = null   # догнать и бить
var attack_origin := Vector2.INF   # точка отмены по leash
var interact_target = null         # дойти и try_interact()
var path: Array = []               # waypoints мировых точек (A* по тайлам)
var _repath_t := 0.0
var _stuck_t := 0.0
# --- скиллы ---
var skill_cd := [0.0, 0.0, 0.0, 0.0]  # НЕ сериализуются
var pending_mult := 1.0               # «Мощный удар»: множитель следующего мили-удара
var mark_target: Node2D = null        # «Метка охотника»
var mark_t := 0.0
var siphon_t := 0.0                   # «Поглощение»: лечение от попаданий снарядов

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

# --- приказы (вызывает world из обработчиков мыши) ---

func command_move(p: Vector2) -> void:
	cancel_orders()
	move_target = p
	path = world.build_path(global_position, p)

func command_attack(e: Node2D) -> void:
	cancel_orders()
	attack_target = e
	attack_origin = global_position

func command_interact(obj) -> void:
	cancel_orders()
	interact_target = obj
	if obj != null and obj is Node2D:
		path = world.build_path(global_position, (obj as Node2D).global_position)

func cancel_orders() -> void:
	move_target = Vector2.INF
	attack_target = null
	interact_target = null
	attack_origin = Vector2.INF
	pending_mult = 1.0
	path = []

## Куда бежим прямо сейчас: ближайший waypoint пути, иначе — прямая к цели.
func _next_step_want(goal: Vector2) -> Vector2:
	while not path.is_empty() and global_position.distance_to(path[0]) < 3.0:
		path.remove_at(0)
	if not path.is_empty():
		return global_position.direction_to(path[0])
	return global_position.direction_to(goal)

func _physics_process(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	hurt_cd = maxf(0.0, hurt_cd - delta)
	_flash_t = maxf(0.0, _flash_t - delta)
	siphon_t = maxf(0.0, siphon_t - delta)
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
		move_and_slide()
		return

	_execute_orders(delta)

	if velocity != Vector2.ZERO:
		if absf(velocity.x) >= absf(velocity.y):
			facing = "right" if velocity.x > 0 else "left"
		else:
			facing = "down" if velocity.y > 0 else "up"
		anim.play(facing)
	else:
		if anim.animation != facing:
			anim.play(facing)
		anim.frame = 0
		anim.pause()
	if Input.is_action_just_pressed("attack"):
		do_attack()

## Исполнение активного приказа. Приоритет: атака > взаимодействие > идти в точку.
## Ход — по A*-пути вокруг стен; враг близко и видно напрямую — идём прямо.
func _execute_orders(delta: float) -> void:
	var want := Vector2.ZERO
	var goal := Vector2.INF  # финальная точка приказа (для перестроения пути)
	if attack_target != null:
		if not is_instance_valid(attack_target):
			attack_target = null
		elif attack_origin != Vector2.INF and global_position.distance_squared_to(attack_origin) > LEASH * LEASH:
			attack_target = null  # цель убежала за leash — отмена
		else:
			var d := global_position.distance_to(attack_target.global_position)
			face_to(attack_target.global_position)
			if d <= float(class_data().radius):
				_attack_in_range()
			else:
				goal = attack_target.global_position
				if d <= float(class_data().radius) + 26.0 and world.line_clear(global_position, goal):
					path = []  # цель видна — прямая без обхода
					want = global_position.direction_to(goal)
				else:
					_repath_t -= delta
					if _repath_t <= 0.0:
						_repath_t = 0.45
						path = world.build_path(global_position, goal)
					want = _next_step_want(goal)
	if want == Vector2.ZERO and interact_target != null:
		if not is_instance_valid(interact_target):
			interact_target = null
			path = []
		else:
			var di := global_position.distance_to(interact_target.global_position)
			if di <= INTERACT_DIST:
				var it = interact_target
				interact_target = null
				path = []
				if it.has_method("try_interact"):
					it.try_interact()
			else:
				goal = interact_target.global_position
				want = _next_step_want(goal)
	if want == Vector2.ZERO and move_target != Vector2.INF and attack_target == null and interact_target == null:
		var dm := global_position.distance_to(move_target)
		if dm <= ARRIVE:
			move_target = Vector2.INF
			path = []
		else:
			goal = move_target
			want = _next_step_want(goal)
	velocity = want * float(class_data().speed)
	if want != Vector2.ZERO:
		var prev := global_position
		move_and_slide()
		# упёрлись: путь есть — перестроить; пути нет — отменить приказ (старое поведение)
		var moved := global_position.distance_to(prev)
		if moved < float(class_data().speed) * delta * CANCEL_RATIO:
			_stuck_t += delta
			if _stuck_t > 0.45:
				_stuck_t = 0.0
				if goal != Vector2.INF and not path.is_empty():
					path = world.build_path(global_position, goal)
				elif attack_target == null:
					move_target = Vector2.INF
					interact_target = null
					path = []
		else:
			_stuck_t = 0.0
	else:
		move_and_slide()

func _attack_in_range() -> void:
	if attack_cd > 0.0:
		return
	if String(class_data().kind) == "melee":
		do_attack()
	else:
		attack_cd = float(class_data().attack_speed)
		fire_projectile(global_position.direction_to(attack_target.global_position))

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
	melee_hit(mult)

## Мгновенный мили-удар: враги в радиусе точки удара (12 px по facing).
func melee_hit(mult: float, center := Vector2.INF, radius := 13.0, only: Node2D = null) -> void:
	var c := center if center != Vector2.INF else global_position + facing_offset()
	_spark(c)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("hurt"):
			continue
		if only != null and e != only:
			continue
		if e.global_position.distance_to(c) <= radius + _enemy_size(e) * 0.5:
			e.hurt(dmg_vs(e, mult), global_position)

static func _enemy_size(e: Node) -> float:
	return 18.0 if e.is_in_group("boss") else 10.0

func _spark(c: Vector2) -> void:
	var spark := ColorRect.new()
	spark.color = Color(1, 1, 0.8, 0.85)
	spark.size = Vector2(6, 6)
	spark.position = c - global_position - Vector2(3, 3)
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
	var tgt := attack_target if attack_target != null and is_instance_valid(attack_target) else null
	var d := dmg_vs(tgt, mult) if tgt != null else int(round(float(GameState.damage) * mult))
	var pd = PROJ.new()
	world.add_child(pd)
	pd.setup(global_position + dir * 8.0, dir, float(class_data().proj_speed), d, idx, pierce, aoe, self)

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
	skill_cd[i] = float(sd.cd)
	match sid:
		"power_strike":
			var t := _skill_target()
			if t != null and global_position.distance_to(t.global_position) <= float(class_data().radius):
				face_to(t.global_position)
				melee_hit(2.0, Vector2.INF, 13.0, t)
			else:
				pending_mult = 2.0  # догнёт — следующий удар x2
		"whirlwind":
			melee_hit(1.5, global_position, 28.0)
		"second_wind":
			GameState.heal(4)
			GameState.toast.emit("Второй ветер: +4 HP")
		"execute":
			var t := _skill_target()
			face_to(t.global_position)
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
			fire_projectile(_shoot_dir(), 2.5, false, 12.0, 1)
		"frost_nova":
			for e in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(e) and "freeze_t" in e and global_position.distance_to(e.global_position) <= 32.0:
					e.freeze_t = 3.0
			GameState.toast.emit("Морозная нова!")
		"siphon":
			siphon_t = 5.0
			GameState.toast.emit("Поглощение: попадания снарядов лечат")
		"firestorm":
			for k in 3:
				get_tree().create_timer(0.5 * (k + 1)).timeout.connect(_firestorm_tick)
	return true

## Цель скилла: активная цель автоатаки или ближайший враг в радиусе класса.
func _skill_target() -> Node2D:
	if attack_target != null and is_instance_valid(attack_target):
		return attack_target
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
	if attack_target != null and is_instance_valid(attack_target):
		return global_position.direction_to(attack_target.global_position)
	return facing_dir()

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
	_spark(global_position + Vector2(randf_range(-14, 14), randf_range(-14, 14)))

# --- получение урона ---

func take_damage(n: int) -> void:
	if hurt_cd > 0.0 or GameState.hp <= 0:
		return
	hurt_cd = 0.8
	_flash_t = 0.35
	GameState.hurt(n)
	if GameState.hp <= 0:
		cancel_orders()
		world.on_player_death()
