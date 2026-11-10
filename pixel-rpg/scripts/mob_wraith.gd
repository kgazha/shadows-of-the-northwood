extends CharacterBody2D
## Тенеплёт: медленный призрак пещеры. В «эфирном» состоянии полупрозрачен,
## неуязвим и проходит сквозь стены КОРОТКИМИ РЫВКАМИ-фазами (0.35 с). Перед
## ударом ОБЯЗАН материализоваться: 1.1 с уплотнения (альфа 0.35 -> 1.0 как
## телеграф), и только в материализации получает урон и бьёт контактом.
## Нечестного «неуязвимого тарана» нет: фаза не наносит урона вовсе.
## HP 8, урон 2. Появляется ближе к нише босса пещеры (позиционирует world.gd,
## интеграционный запрос в отчёте). Лист assets/mobs_wraith.png — 48x64:
## 3 кадра (парение / взмах / материализация) на 4 ряда (вниз / влево / вправо / вверх).

enum { ETHEREAL, PHASING, MATERIALIZING }

const LEASH := 110.0          # радиус интереса: дальше — бродит у ниши
const DASH_SPEED := 95.0
const DASH_TIME := 0.35       # длительность фазы сквозь стены
const DASH_CD_MIN := 1.8      # новый рывок не чаще этого
const DASH_CD_JITTER := 0.6
const MAT_TIME := 1.1         # окно материализации: окно уязвимости и удара
const SPEED_DRIFT := 22.0     # блуждание в эфире
const SPEED_MAT := 26.0       # медлителен в материализации — наказуем
const HIT_DIST := 10.0
const ALPHA_ETH := 0.45
const ALPHA_PHASE := 0.3
const MAX_HP := 8

var world: Node2D
var hp := MAX_HP
var max_hp := MAX_HP
var anim: AnimatedSprite2D
var hurt_t := 0.0
## Заморозка («Морозная нова» мага): >0 — замирает (и фаза прерывается), синий тинт.
var freeze_t := 0.0
var state := ETHEREAL
var dash_cd := 1.0
var dash_t := 0.0
var dash_dir := Vector2.ZERO
var mat_t := 0.0
var facing := "down"
var home := Vector2.ZERO
var wander_t := 0.0
var wander_dir := Vector2.ZERO
var last_safe := Vector2.ZERO # последняя проходимая точка — выход из фазы в стене
var dying := false            # страж повторной смерти: XP — ровно один раз
var _shape: CollisionShape2D

func setup(p_world: Node2D, tile: Vector2i) -> void:
	world = p_world
	position = world.tile_to_world(tile)
	home = position
	last_safe = position
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("enemy")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(10, 8)
	cs.shape = sh
	add_child(cs)
	_shape = cs
	anim = AnimatedSprite2D.new()
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	if ResourceLoader.exists("res://assets/mobs_wraith.png"):
		var tex := load("res://assets/mobs_wraith.png")
		var rows := {"down": 0, "left": 1, "right": 2, "up": 3}
		for dir_name: String in rows.keys():
			var row: int = int(rows[dir_name])
			for kind: Array in [["idle", [0, 1], true, 2.0], ["walk", [0, 1], true, 4.0], ["act", [2], false, 0.0]]:
				var an := "%s_%s" % [String(kind[0]), dir_name]
				fr.add_animation(an)
				fr.set_animation_loop(an, bool(kind[2]))
				if bool(kind[2]):
					fr.set_animation_speed(an, float(kind[3]))
				for col: int in kind[1]:
					var at := AtlasTexture.new()
					at.atlas = tex
					at.region = Rect2(col * 16, row * 16, 16, 16)
					fr.add_frame(an, at, 0.0)
		anim.sprite_frames = fr
		add_child(anim)
		anim.play("idle_down")
	else:
		push_warning("Нет ассета: assets/mobs_wraith.png — у тенеплёта цветная заглушка")
		var ph := ColorRect.new()
		ph.color = Color(0.45, 0.32, 0.6)
		ph.size = Vector2(11, 13)
		ph.position = Vector2(-5, -7)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ph)
	modulate = Color(1, 1, 1, ALPHA_ETH)

func _physics_process(delta: float) -> void:
	if dying:
		return
	hurt_t = maxf(0.0, hurt_t - delta)
	freeze_t = maxf(0.0, freeze_t - delta)
	if GameState.input_locked or world.player == null or GameState.hp <= 0:
		velocity = Vector2.ZERO
		return
	if freeze_t > 0.0:
		# заморозка «выбрасывает» тенеплёта из фазы обратно в эфир
		if state == PHASING:
			_end_phase()
		state = ETHEREAL
		modulate = Color(0.55, 0.75, 1.0, ALPHA_ETH)
		velocity = Vector2.ZERO
		return
	var player: CharacterBody2D = world.player
	match state:
		PHASING:
			_tick_phase(delta)
		MATERIALIZING:
			_tick_materialize(delta, player)
		_:
			_tick_ethereal(delta, player)
	if hurt_t > 0.0:
		modulate = Color(1, 0.5, 0.5, modulate.a)

## Эфир: полупрозрачное блуждание, подпускание героя; рывок-фаза по кулдауну.
func _tick_ethereal(delta: float, player: CharacterBody2D) -> void:
	var d := global_position.distance_to(player.global_position)
	if d > LEASH:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(1.4, 3.0)
			var off := global_position - home
			if off.length() > 28.0 or randf() < 0.3:
				wander_dir = -off.normalized() if off != Vector2.ZERO else Vector2.ZERO
			else:
				wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		velocity = wander_dir * SPEED_DRIFT * 0.6
	else:
		velocity = (player.global_position - global_position).normalized() * SPEED_DRIFT
		dash_cd -= delta
		if dash_cd <= 0.0 and d > 24.0:
			# рывок сквозь стены: сквозь камень, но без урона — урон только «в теле»
			state = PHASING
			dash_t = DASH_TIME
			dash_dir = (player.global_position - global_position).normalized()
			collision_mask = 1 | 4  # стены (слой 2) игнорируются только на время фазы
			GameAudio.sfx("roll")   # шелест «уходящей» тени
	dash_cd = maxf(dash_cd, 0.0)
	_remember_safe()
	_face(player.global_position - global_position)
	_anim(false)
	move_and_slide()
	modulate = Color(1, 1, 1, ALPHA_ETH) if hurt_t <= 0.0 else modulate

## Фаза: короткий бросок сквозь камень. Урона нет; в конце — материализация.
func _tick_phase(delta: float) -> void:
	dash_t -= delta
	velocity = dash_dir * DASH_SPEED
	move_and_slide()
	modulate = Color(0.85, 0.7, 1.0, ALPHA_PHASE)
	if dash_t <= 0.0:
		_end_phase()
		# влезли в камень — откат на последнюю проходимую точку
		if not _tile_walkable(global_position):
			global_position = last_safe
		state = MATERIALIZING
		mat_t = MAT_TIME
		velocity = Vector2.ZERO
		collision_mask = 1 | 2 | 4

## Материализация: уплотнение (альфа-телеграф), медленное сближение, контакт-удар.
## Только здесь тенеплёт уязвим — hurt() вне этого состояния урон не принимает.
func _tick_materialize(delta: float, player: CharacterBody2D) -> void:
	mat_t -= delta
	var k := clampf(1.0 - mat_t / MAT_TIME, 0.0, 1.0)
	modulate = Color(1, 1, 1, lerpf(ALPHA_PHASE, 1.0, k)) if hurt_t <= 0.0 else modulate
	var to_p := player.global_position - global_position
	velocity = to_p.normalized() * SPEED_MAT if mat_t > 0.0 else Vector2.ZERO
	_face(to_p)
	_anim(true)
	move_and_slide()
	if to_p.length() < HIT_DIST:
		player.take_damage(2)
	if mat_t <= 0.0:
		state = ETHEREAL
		dash_cd = DASH_CD_MIN + randf_range(0.0, DASH_CD_JITTER)

func _end_phase() -> void:
	dash_t = 0.0
	collision_mask = 1 | 2 | 4

func _hurt_flash() -> void:
	modulate = Color(1, 0.5, 0.5, modulate.a)

## Помечаем проходимую точку, чтобы фаза, кончившаяся в породе, «выплевывалась» наружу.
func _remember_safe() -> void:
	if _tile_walkable(global_position):
		last_safe = global_position

## Проходимость тайла под центром: зона (пещера/деревня) сама знает свою карту.
## Позицию переводим в локальные координаты зоны — cave_zone несёт CAVE_OFFSET.
func _tile_walkable(pos: Vector2) -> bool:
	if get_parent() != null and get_parent().has_method("cell_walkable"):
		var z: Node2D = get_parent()
		var lp := z.to_local(pos)
		var t := Vector2i(floori(lp.x / 16.0), floori((lp.y - 2.0) / 16.0))
		return bool(z.call("cell_walkable", t))
	var lp2 := to_local(pos)
	var t2 := Vector2i(floori(lp2.x / 16.0), floori((lp2.y - 2.0) / 16.0))
	return bool(world.call("_village_walkable", t2))

func _face(dvec: Vector2) -> void:
	if absf(dvec.x) > absf(dvec.y):
		facing = "right" if dvec.x > 0.0 else "left"
	else:
		facing = "up" if dvec.y < 0.0 else "down"

func _anim(mat: bool) -> void:
	if anim == null or not anim.sprite_frames.has_animation("idle_down"):
		return
	var want := "act" if mat else ("walk" if velocity.length_squared() > 1.0 else "idle")
	var an := "%s_%s" % [want, facing]
	if anim.animation != an:
		anim.play(an)

func hurt(dmg: int, from: Vector2) -> void:
	if dying:
		return  # труп не получает урон: XP и quest_changed — ровно один раз
	GameState.entered_combat()  # контакт с врагом — реген паузится
	if state != MATERIALIZING:
		# эфир и фаза неуязвимы: клинок проходит сквозь дымку — только вспыхнет
		_hurt_flash()
		return
	hp -= dmg
	hurt_t = 0.3
	velocity = (global_position - from).normalized() * 40.0
	if hp <= 0:
		dying = true
		remove_from_group("enemy")
		GameAudio.sfx("drop")
		GameState.add_xp(15)
		GameAudio.sfx("coin")
		GameState.toast.emit("Тенеплёт рассеян! (+15 XP)")
		Loot.on_mob_death("wraith", global_position)
		GameState.quest_changed.emit()
		queue_free()
