extends CharacterBody2D
## Лесокров-лучник: стрелок дальнего боя. Держит дистанцию 4–6 тайлов (64–96 px),
## при приближении героя ОТХОДИТ назад, стреляет через собственный снаряд (Arrow).
## Перед выстрелом — телеграф подготовки 0.7 с: подсветка силуэта, кадр «натянутый
## лук» и звук тетивы. HP низкое (4), урон стрелы высокий (2) — наказывает за лобовую
## атаку, но гибнет от пары попаданий. Умный кулдаун: вблизи герой наказывается чаще.
## Лист assets/mobs_archer.png — 48x64: 3 кадра (стойка / шаг / выстрел) на 4 ряда
## (вниз / влево / вправо / вверх), как у героя.
## Позиционируется world.gd (интеграционный запрос в отчёте).

const HOLD_MIN := 64.0        # 4 тайла — нижняя граница «комфортной» дистанции
const HOLD_MAX := 96.0        # 6 тайлов — верхняя граница: дальше — подойти
const LEASH := 150.0          # за пределами — отход домой, не по всей карте
const SPEED_RETREAT := 46.0   # скорость отхода при сближении героя
const SPEED_ADVANCE := 30.0   # скорость сближения, когда герой далеко
const TELEGRAPH := 0.7        # подготовка выстрела: подсветка + кадр лука
const CD_FAR := 2.4           # кулдаун выстрела на дистанции
const CD_NEAR := 1.7          # умный кулдаун: герой ближе HOLD_MIN — стреляет чаще
const ARROW_SPEED := 170.0
const ARROW_LIFE := 1.6
const SHOT_MIN := 28.0        # в упор не стреляет — только отходит
const MAX_HP := 4
## Волна 5: визуальный масштаб ×1.5 (коллайдер 9x7, дистанции кайта и урон —
## прежние). Контент-стоп 16px-кадра на +7: якорь +7*(1−1.5) = −3.5.
const VISUAL_SCALE := 1.5

var world: Node2D
var hp := MAX_HP
var max_hp := MAX_HP
var anim: AnimatedSprite2D
var hurt_t := 0.0
## Заморозка («Морозная нова» мага): >0 — не двигается и не стреляет, синий тинт.
var freeze_t := 0.0
var shot_cd := 1.2            # первый выстрел не мгновенно: у героя есть время войти
var tele_t := 0.0             # >0 — идёт подготовка выстрела
var tele_dir := Vector2.RIGHT # направление, зафиксированное в начале телеграфа
var facing := "down"
var gen_art := false  # t17: ген-ассет (flip по facing, LINEAR_WITH_MIPMAPS)
var home := Vector2.ZERO
var wander_t := 0.0
var wander_dir := Vector2.ZERO
var dying := false            # страж повторной смерти: XP — ровно один раз
var _shape: CollisionShape2D

func setup(p_world: Node2D, tile: Vector2i) -> void:
	world = p_world
	# t39 (t38: лучник — «островок вне волн», его r плоский по всем кругам):
	# лёгкий hp-скейл +20% MAX_HP за волну, УРОН не скейлится (dmg 2 — и так
	# самый чувствительный контакт для новичка). w5: hp 4→8.
	var ngw := GameState.ng_wave()
	hp = MAX_HP + int(floor(float(MAX_HP) * 0.2 * float(ngw)))
	max_hp = hp
	position = world.tile_to_world(tile)
	home = position
	collision_layer = 4
	collision_mask = 2 | 4  # слой героя (1) убран: вместо взаимной блокировки — мягкое выталкивание (_push_from_hero)
	add_to_group("enemy")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(9, 7)
	cs.shape = sh
	add_child(cs)
	_shape = cs
	anim = AnimatedSprite2D.new()
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	if ResourceLoader.exists("res://assets/art/mob_archer.png") \
			or ResourceLoader.exists("res://assets/mobs_archer.png"):
		# t17: ген-ассет (art_gen archer v2) приоритетом над пиксельным листом.
		var gen := ResourceLoader.exists("res://assets/art/mob_archer.png")
		gen_art = gen
		var tex: Texture2D = load("res://assets/art/mob_archer.png") if gen else load("res://assets/mobs_archer.png")
		var rows := {"down": 0, "left": 1, "right": 2, "up": 3}
		for dir_name: String in rows.keys():
			var row: int = int(rows[dir_name])
			for kind: Array in [["idle", [0, 1], true, 2.5], ["walk", [0, 1], true, 6.0], ["act", [2], false, 0.0]]:
				var an := "%s_%s" % [String(kind[0]), dir_name]
				fr.add_animation(an)
				fr.set_animation_loop(an, bool(kind[2]))
				if bool(kind[2]):
					fr.set_animation_speed(an, float(kind[3]))
				if gen:
					fr.add_frame(an, tex, 0.0)  # однокадровый канон-набор (резерв под аним-проход)
				else:
					for col: int in kind[1]:
						var at := AtlasTexture.new()
						at.atlas = tex
						at.region = Rect2(col * 16, row * 16, 16, 16)
						fr.add_frame(an, at, 0.0)
		anim.sprite_frames = fr
		add_child(anim)
		if gen:
			# tight-кроп: s=24/tex_h; линия ног 8.5 (замер старых кадров, ffb=0)
			# → pos.y = 8.5 − 12; тень следует по низу кропа
			var gs := 24.0 / float(tex.get_height())
			anim.scale = Vector2.ONE * gs
			anim.position = Vector2(0, 8.5 - 12.0)
			anim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			anim.flip_h = facing == "left"
		else:
			anim.scale = Vector2.ONE * VISUAL_SCALE
			anim.position = Vector2(0, -3.5)
		anim.play("idle_down")
	else:
		push_warning("Нет ассета: assets/mobs_archer.png — у лучника цветная заглушка")
		var ph := ColorRect.new()
		ph.color = Color(0.3, 0.42, 0.26)
		ph.size = Vector2(10, 12)
		ph.position = Vector2(-5, -6)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ph)

func _physics_process(delta: float) -> void:
	if dying:
		return
	hurt_t = maxf(0.0, hurt_t - delta)
	freeze_t = maxf(0.0, freeze_t - delta)
	if hurt_t > 0.0:
		modulate = Color(1.8, 0.62, 0.55)  # t18: горячая вспышка ≤0.1 с (телеграф-подсветка ниже — канон mb_1, не трогать)
	elif freeze_t > 0.0:
		modulate = Color(0.55, 0.75, 1.0)
	elif tele_t > 0.0:
		modulate = Color(1.3, 1.12, 0.6)  # подсветка подготовки — честный телеграф
	else:
		modulate = Color.WHITE
	if GameState.input_locked or world.player == null or GameState.hp <= 0:
		velocity = Vector2.ZERO
		return
	if freeze_t > 0.0:
		tele_t = 0.0  # заморозка срывает подготовку выстрела
		velocity = Vector2.ZERO
		_push_from_hero()  # мёрзлый лучник тоже уступает место герою, не лежит под ним
		return
	var player: CharacterBody2D = world.player
	var to_p := player.global_position - global_position
	var d := to_p.length()
	if d > LEASH:
		# героя далеко нет — сторожим свой участок леса
		tele_t = 0.0
		_wander(delta)
		_anim_walk()
		move_and_slide()
		return
	_shot_cd(delta)
	if d > HOLD_MAX:
		velocity = to_p.normalized() * SPEED_ADVANCE
	elif d < HOLD_MIN:
		# герой сел в плотную — отходим, стрелок в упор бессилен
		velocity = -to_p.normalized() * SPEED_RETREAT
	else:
		velocity = Vector2.ZERO
	# телеграф выстрела: стоим и тянем тетиву (допускается доворот на героя)
	if tele_t > 0.0:
		velocity *= 0.35
		tele_t -= delta
		if not _has_los(player) or player.roll_t > 0.0:
			tele_t = 0.0
			shot_cd = 0.5  # сорванный выстрел — короткая пауза, потом новая попытка
		else:
			# лук «ведёт» цель, но медленнее героя: боковой рывок во время
			# подсветки и уход за стену — рабочие контрприёмы
			tele_dir = tele_dir.lerp((player.global_position - global_position).normalized(), minf(1.0, 6.0 * delta)).normalized()
			if tele_t <= 0.0:
				_shoot()
	# агрессия «в упор»: если герой всё-таки дожал — отход важнее выстрела
	if tele_t > 0.0 and d < SHOT_MIN:
		tele_t = 0.0
		shot_cd = 0.5
	_face(to_p)
	_anim_move(tele_t > 0.0)
	move_and_slide()
	_push_from_hero()  # «стенка без пиления»: упор герой<->лучник больше не дребезжит камерой

## «Стенка без пиления» (дребезг экрана вплотную): герой (слой 1) убран из маски —
## два CharacterBody2D при упоре друг в друга пилят каждый кадр в противофазе, а
## камера висит на герое. Лучник уступает сам: отход вдоль оси наименьшего
## проникновения боксов до старого контакта (бокс 9x7). Контактного урона нет —
## дистанции кайта (HOLD_MIN) не затронуты. Стены — препятствия.
func _push_from_hero() -> void:
	if world == null or world.player == null:
		return
	var d: Vector2 = global_position - world.player.global_position
	var mb := Vector2(9, 7)
	var ox := (mb.x + 10.0) * 0.5 - absf(d.x)
	var oy := (mb.y + 8.0) * 0.5 - absf(d.y)
	if ox <= 0.0 or oy <= 0.0:
		return
	if ox < oy:
		var sx := signf(d.x)
		if sx == 0.0:
			sx = 1.0  # точное совпадение центров — отход вправо
		move_and_collide(Vector2(sx * (ox + 0.05), 0.0))
	else:
		var sy := signf(d.y)
		if sy == 0.0:
			sy = -1.0  # точное совпадение центров — отход вверх
		move_and_collide(Vector2(0.0, sy * (oy + 0.05)))

## Кулдаун и пуск подготовки: нужен прямой луч до героя; кувырок героя (i-frames)
## тоже блокирует пуск — не тратим выстрел впустую.
func _shot_cd(delta: float) -> void:
	shot_cd -= delta
	if tele_t > 0.0 or shot_cd > 0.0:
		return
	var player: CharacterBody2D = world.player
	var d := global_position.distance_to(player.global_position)
	if d < SHOT_MIN or d > HOLD_MAX + 44.0:
		return
	if player.roll_t > 0.0 or not _has_los(player):
		return
	var cd := CD_NEAR if d < HOLD_MIN + 16.0 else CD_FAR
	shot_cd = cd + randf_range(-0.2, 0.3)
	tele_t = TELEGRAPH
	tele_dir = (player.global_position - global_position).normalized()
	GameAudio.sfx("attack_alt")  # звук натягиваемой тетивы

func _shoot() -> void:
	GameAudio.sfx("attack")
	var player: CharacterBody2D = world.player
	var dist := global_position.distance_to(player.global_position)
	# лёгкое упреждение по скорости героя: бег по прямой на лучника — плохая идея,
	# рывок в сторону и кувырок — хорошие
	var aim := player.global_position + player.velocity * clampf(dist / ARROW_SPEED, 0.0, 0.8)
	var dirv := (aim - global_position).normalized()
	if dirv == Vector2.ZERO:
		dirv = tele_dir
	var a := Arrow.new()
	world.add_child(a)
	a.setup(global_position + dirv * 8.0, dirv, world.player, 2)

## Прямая видимость героя: луч до героя блокируют только стены (слой 2).
func _has_los(player: Node2D) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, player.global_position, 2, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.is_empty()

func _wander(delta: float) -> void:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(1.4, 3.0)
		var off := global_position - home
		if off.length() > 24.0 or randf() < 0.3:
			wander_dir = -off.normalized() if off != Vector2.ZERO else Vector2.ZERO
		else:
			wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	velocity = wander_dir * 14.0

func _face(dvec: Vector2) -> void:
	if absf(dvec.x) > absf(dvec.y):
		facing = "right" if dvec.x > 0.0 else "left"
	else:
		facing = "up" if dvec.y < 0.0 else "down"

func _anim_move(shooting: bool) -> void:
	if anim == null or not anim.sprite_frames.has_animation("idle_down"):
		return
	var want := "act" if shooting else ("walk" if velocity.length_squared() > 1.0 else "idle")
	var an := "%s_%s" % [want, facing]
	if anim.animation != an:
		anim.play(an)
	if gen_art:
		anim.flip_h = facing == "left"  # арт смотрит вправо

func _anim_walk() -> void:
	_anim_move(false)

func hurt(dmg: int, from: Vector2) -> void:
	if dying:
		return  # труп не получает урон: XP и quest_changed — ровно один раз
	GameState.entered_combat()  # контакт с врагом — реген паузится
	hp -= dmg
	hurt_t = 0.09  # t18: вспышка цели ≤0.1 с
	Juice.hit()    # t18 «сочность»: hitstop + мазок (гарантии восстановления — juice.gd)
	Juice.shake(0.8, 0.09)
	tele_t = 0.0  # полученный урон срывает подготовку выстрела
	velocity = (global_position - from).normalized() * 60.0
	if hp <= 0:
		dying = true
		remove_from_group("enemy")
		GameAudio.sfx("drop")
		GameState.add_xp(9)
		Achv.count("kill_archer")  # счётчик убийств (achv.gd)
		GameAudio.sfx("coin")
		GameState.toast.emit("Лесокров-лучник повержен! (+9 опыта)")
		Loot.on_mob_death("archer", global_position)
		GameState.quest_changed.emit()
		queue_free()

class Arrow extends Area2D:
	## Стрела лучника. projectile.gd — снаряд героя (collision_mask 4|2, урон только
	## по группе "enemy"); править его нельзя, поэтому вражеская стрела — собственный
	## Area2D с той же картинкой (assets/projectiles.png, кадр 0), но по слою героя (1).
	var dirv := Vector2.RIGHT
	var speed := 170.0
	var life := 1.6
	var target: Node2D
	var dmg := 2

	func setup(from: Vector2, dir: Vector2, p_target: Node2D, p_dmg: int) -> void:
		global_position = from
		dirv = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
		target = p_target
		dmg = maxi(1, p_dmg)
		rotation = dirv.angle()
		collision_layer = 0
		collision_mask = 1 | 2  # герой + стены: вражеская стрела гаснет о препятствия
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = 3.0
		cs.shape = sh
		add_child(cs)
		if ResourceLoader.exists("res://assets/projectiles.png"):
			var spr := Sprite2D.new()
			var at := AtlasTexture.new()
			at.atlas = load("res://assets/projectiles.png")
			at.region = Rect2(0, 0, 16, 16)
			spr.texture = at
			add_child(spr)
		body_entered.connect(_on_hit)

	func _physics_process(delta: float) -> void:
		# пауза мира (меню/диалог): стрела висит в воздухе — не летит и life не тикает;
		# мониторинг гасим, чтобы висящая стрела не задела цель в момент разблокировки
		if GameState.input_locked:
			if monitoring:
				monitoring = false
				monitorable = false
			return
		if not monitoring:
			monitoring = true
			monitorable = true
		position += dirv * speed * delta
		life -= delta
		if life <= 0.0:
			queue_free()

	func _on_hit(b: Node) -> void:
		# маска 1|2: сюда долетает только герой (слой 1) или преграда — как в
		# projectile.gd (фикс T9): во всё, что не цель, стрела гаснет
		if b == target and b.has_method("take_damage"):
			b.take_damage(dmg, "archer")  # кадры неуязвимости героя (hurt_cd/кувырок) — на его стороне; t20: kind убийцы
		queue_free()
