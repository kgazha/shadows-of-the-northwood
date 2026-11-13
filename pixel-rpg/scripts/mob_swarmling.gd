extends CharacterBody2D
## Мглокрыс: мелкий, быстрый, слабый. Спавнится СТАЕЙ 3–5 штук (world.gd задаёт
## каждому один и тот же swarm_id до setup). У стаи общий «испуг»: когда гибнет
## половина и больше — уцелевшие разбегаются в разные стороны и исчезают, не
## дожидаясь добивания. HP 2, урон 1, опыта мало — стая как препятствие, не стена.
## Лист assets/mobs_swarmling.png — 48x64: 3 кадра (возня / перебежка / укус)
## на 4 ряда (вниз / влево / вправо / вверх).

const LEASH := 56.0           # реакция только на героя рядом
const HIT_DIST := 8.0
const SPEED_CHASE := 54.0     # быстрее слайма: мелкий и юркий
const SPEED_FLEE := 66.0      # испуганная крыса почти не догоняема
const SPEED_WANDER := 14.0
const FLEE_RADIUS := 128.0    # отбежал на это расстояние — стая растворилась в тумане
## t44 «анти-залипание»: свип t43 (48 углов × 2 тайла) показал геометрические карманы
## поляны — углы вблизи 0/90/180/270° (7 из 48) не достигают FLEE_RADIUS НИКОГДА
## (maxd 7–121 px за 30 с): крыса вечно скользит вдоль стены, и стая «держит» живую
## особу в реестре. Порог: столько секунд без обновления рекорда удаления от дома →
## despawn тем же путём, что и FLEE_RADIUS. Штатный разлёт укладывается в 2–4 с
## (116–235 кадров, замер t43) — порог беззапасен для нормального бегства.
const FLEE_STUCK_T := 9.0
const MAX_HP := 2
## t51 (возврат «до Крупного мира»): мглокрыс 16 px 1:1 (коллайдер 8x6,
## дистанции и скорости — прежние). Контент-стоп 16px-кадра на +6 задаёт
## картинка, якорь ZERO (было: ×1.5/−3.0, t22 ×1.125/−0.75).
const VISUAL_SCALE := 1.0

## Реестры стай: swarm_id -> {total, alive, panicked, scatter}.
## static — переживает конкретный экземпляр; чистится сам, когда стая гибнет/исчезает.
static var SWARMS := {}

## Имя стаи задаётся МИРОМ до setup (все крысы запуска одной волной).
var swarm_id := "solo"
var world: Node2D
var hp := MAX_HP
var max_hp := MAX_HP
var anim: AnimatedSprite2D
var hurt_t := 0.0
## Заморозка («Морозная нова» мага): >0 — не двигается и не кусает, синий тинт.
var freeze_t := 0.0
var wander_t := 0.0
var wander_dir := Vector2.ZERO
var flee_dir := Vector2.ZERO
var home := Vector2.ZERO
var facing := "down"
var bit_t := 0.0              # >0 — проигрывается кадр укуса
var dying := false            # страж повторной смерти: XP — ровно один раз
var swarm_left := false       # крыса покинула стайный учёт ровно один раз (смерть XOR бегство)
var flee_best := 0.0          # t44: макс. удаление от дома за текущий бег (якорь = FLEE_RADIUS)
var flee_stall := 0.0         # t44: секунды с последней прибавки к этому рекорду
var _shape: CollisionShape2D

func setup(p_world: Node2D, tile: Vector2i) -> void:
	world = p_world
	# t39: как у лучника — лёгкий hp-скейл +20% MAX_HP за волну, урон прежний.
	# На w0–w1 floor(2×0.2×w)=0: стартовый рой деревни (круг 0) не дорожает.
	var ngw := GameState.ng_wave()
	hp = MAX_HP + int(floor(float(MAX_HP) * 0.2 * float(ngw)))
	max_hp = hp
	position = world.tile_to_world(tile)
	home = position
	collision_layer = 4
	collision_mask = 2 | 4  # слой героя (1) убран: вместо взаимной блокировки — мягкое выталкивание (_push_from_hero)
	add_to_group("enemy")
	var sw := _swarm()
	sw.total = int(sw.total) + 1
	sw.alive = int(sw.alive) + 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(8, 6)
	cs.shape = sh
	add_child(cs)
	_shape = cs
	anim = AnimatedSprite2D.new()
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	if ResourceLoader.exists("res://assets/mobs_swarmling.png"):
		# t52 снос (закон 13.11): ген-ассет art_gen снят — прежний пиксельный
		# лист mobs_swarmling.png (4 ряда направления × idle/walk/act).
		var tex: Texture2D = load("res://assets/mobs_swarmling.png")
		var rows := {"down": 0, "left": 1, "right": 2, "up": 3}
		for dir_name: String in rows.keys():
			var row: int = int(rows[dir_name])
			for kind: Array in [["idle", [0, 1], true, 4.0], ["walk", [0, 1], true, 9.0], ["act", [2], false, 0.0]]:
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
		anim.scale = Vector2.ONE * VISUAL_SCALE
		anim.position = Vector2.ZERO  # t51 «было»: якорь в центре ноды
		anim.play("idle_down")
	else:
		push_warning("Нет ассета: assets/mobs_swarmling.png — у мглокрыса цветная заглушка")
		var ph := ColorRect.new()
		ph.color = Color(0.42, 0.36, 0.3)
		ph.size = Vector2(9, 6)
		ph.position = Vector2(-4, -3)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ph)

func _swarm() -> Dictionary:
	if not SWARMS.has(swarm_id):
		SWARMS[swarm_id] = {"total": 0, "alive": 0, "panicked": false, "scatter": false}
	return SWARMS[swarm_id]

## t46 (F1): единая точка сброса реестра при СТАРТЕ МИРА (world._ready, до спавна
## живого). static SWARMS живёт в процессе, а не в сцене: он переживает
## reload_current_scene (смерть-петля/ретрай и NG+, world.gd), при котором крысы
## умирают вместе с деревом без штатного _leave_swarm. Осиротевшие записи прошлого
## круга мержатся с новым миром: стая рождается уже в панике с flee_dir=(0,0)
## («статуи»), ghost-alive никогда не убывает — запись бессмертна и отравляет все
## круги. Тот же словарь у ключей ashen_brood/witch_guard/brute_ash_* — чистим
## ВЕСЬ реестр, а не по ключам: новый мир пересоздаёт свои записи в setup().
## Безопасно к переходам внутри забега: телепорты (apply_area/enter_ashen) сцену
## НЕ перезагружают — world._ready исполняется ровно один раз на экземпляр мира,
## а при настоящем релоаде все прежние стаи уже мертвы вместе со старым деревом.
static func reset_registry() -> void:
	SWARMS.clear()

func _physics_process(delta: float) -> void:
	if dying:
		return
	hurt_t = maxf(0.0, hurt_t - delta)
	freeze_t = maxf(0.0, freeze_t - delta)
	bit_t = maxf(0.0, bit_t - delta)
	if hurt_t > 0.0:
		modulate = Color(1.8, 0.62, 0.55)  # t18: горячая вспышка ≤0.1 с (яркость >1 — LINEAR)
	elif freeze_t > 0.0:
		modulate = Color(0.55, 0.75, 1.0)
	else:
		modulate = Color.WHITE
	if GameState.input_locked or world.player == null or GameState.hp <= 0:
		velocity = Vector2.ZERO
		return
	if freeze_t > 0.0:
		velocity = Vector2.ZERO
		_push_from_hero()  # мёрзлый мглокрыс тоже уступает место герою, не лежит под ним
		return
	var player: CharacterBody2D = world.player
	var sw := _swarm()
	var d := global_position.distance_to(player.global_position)
	if bool(sw.panicked):
		# общий испуг: каждая крыса уже выбрала свой угол разлёта — просто убегаем
		velocity = flee_dir * SPEED_FLEE
		move_and_slide()
		_face(flee_dir)
		_anim()
		# t44 «анти-залипание»: прогресс бегства = новый максимум удаления от дома
		# (тот же якорь, что у FLEE_RADIUS и LEASH-блуждания t39). Карманная крыса,
		# упирающаяся в стену, рекордов не ставит → счётчик растёт. Заморозка и
		# input_locked сюда не доходят (ранние выходы выше) — пауза не «съедает» бегство.
		var dh: float = global_position.distance_to(home)
		if dh > flee_best + 0.5:
			flee_best = dh
			flee_stall = 0.0
		else:
			flee_stall += delta
		if dh > FLEE_RADIUS or flee_stall >= FLEE_STUCK_T:
			# стая растворилась — крыса убегает за пределы сцены навсегда; t44: залипшая
			# в геометрическом кармане — тем же путём и с той же семантикой: это НЕ убийство
			# (ни XP, ни счётчика убийств, ни лута, ни тоста; swarm_left — гарантированный
			# единичный учёт убыли стаи)
			remove_from_group("enemy")
			_leave_swarm()  # фикс W2: бегство — тоже убыль стаи (тот же путь, что смерть; без XP/тоста)
			queue_free()
		return
	if d < LEASH:
		velocity = (player.global_position - global_position).normalized() * SPEED_CHASE
		if d < HIT_DIST:
			player.take_damage(1, "swarmling")  # t20: kind убийцы для экрана смерти
			bit_t = 0.25
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(0.8, 2.0)
			if randf() < 0.3:
				wander_dir = Vector2.ZERO
			else:
				wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		# t39 «grace стартового роя»: LEASH («реакция только на героя рядом») отныне
		# связывает и блуждание — рой не уходит со своей поляне дальше полу-LEASH
		# (28 px ≈ 1,75 тайла). Раньше свободный random-walk мог донести крысу до
		# пассивного героя к ~34 с (t38/t39-база: idle-новичок умирал на 43 с).
		if global_position.distance_to(home) > LEASH * 0.5:
			wander_dir = (home - global_position).normalized()
		velocity = wander_dir * SPEED_WANDER
	_face(player.global_position - global_position if d < LEASH else velocity)
	_anim()
	move_and_slide()
	_push_from_hero()  # «стенка без пиления»: упор герой<->крыса больше не дребезжит камерой

## «Стенка без пиления» (дребезг экрана вплотную): герой (слой 1) убран из маски —
## два CharacterBody2D при упоре друг в друга пилят каждый кадр в противофазе, а
## камера висит на герое. Крыса уступает сам: отход вдоль оси наименьшего
## проникновения боксов до старого контакта (бокс 8x6): укус по-прежнему бьёт
## «сверху/снизу» (d<HIT_DIST), геометрия покоя идентична живой стене. Разбег
## испуганной стаи не выталкиваем — там крыса убегает, а не подпирать.
func _push_from_hero() -> void:
	if world == null or world.player == null:
		return
	var d: Vector2 = global_position - world.player.global_position
	var mb := Vector2(8, 6)
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

func _face(dvec: Vector2) -> void:
	if dvec == Vector2.ZERO:
		return
	if absf(dvec.x) > absf(dvec.y):
		facing = "right" if dvec.x > 0.0 else "left"
	else:
		facing = "up" if dvec.y < 0.0 else "down"

func _anim() -> void:
	if anim == null or not anim.sprite_frames.has_animation("idle_down"):
		return
	var want := "act" if bit_t > 0.0 else ("walk" if velocity.length_squared() > 1.0 else "idle")
	var an := "%s_%s" % [want, facing]
	if anim.animation != an:
		anim.play(an)

func hurt(dmg: int, from: Vector2) -> void:
	if dying:
		return  # труп не получает урон: XP и quest_changed — ровно один раз
	GameState.entered_combat()  # контакт с врагом — реген паузится
	hp -= dmg
	hurt_t = 0.09  # t18: вспышка цели ≤0.1 с
	Juice.hit()    # t18 «сочность»: hitstop + мазок (гарантии восстановления — juice.gd)
	Juice.shake(0.8, 0.09)
	velocity = (global_position - from).normalized() * 55.0
	if hp <= 0:
		dying = true
		remove_from_group("enemy")
		GameAudio.sfx("drop")
		GameState.add_xp(3)
		Achv.count("kill_swarmling")  # счётчик убийств (achv.gd)
		GameAudio.sfx("coin")
		GameState.toast.emit("Мглокрыс повержен! (+3 опыта)")
		Loot.on_mob_death("swarmling", global_position)
		GameState.quest_changed.emit()
		_on_swarm_death()
		queue_free()

## Общий испуг стаи: как только живых стало не больше половины — уцелевшие
## выбирают веерные направления разлёта (один раз на стаю, один тост).
func _on_swarm_death() -> void:
	_leave_swarm()  # смерть — один из вариантов ухода из стаи

## Единый учёт выхода крысы из стаи (смерть XOR бегство): ровно один декремент
## alive на особь (страж swarm_left). Иначе в static-реестре вечно висит запись
## с panicked=true (фикс W2: убежавшая крыса не убывала из стаи).
func _leave_swarm() -> void:
	if swarm_left:
		return
	swarm_left = true
	var sw := _swarm()
	sw.alive = maxi(0, int(sw.alive) - 1)
	if bool(sw.panicked) or int(sw.alive) <= 0:
		_maybe_forget_swarm()
		return
	if int(sw.alive) * 2 > int(sw.total):
		return
	sw.panicked = true
	GameState.toast.emit("Стая мглокрысов шарахается в разные стороны!")
	# веер: каждый уцелевший разбегается в свою сторону от центра стаи
	var survivors: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("_is_swarm_member") and e._is_swarm_member(swarm_id):
			survivors.append(e)
	for i: int in range(survivors.size()):
		var ang := TAU * float(i) / maxf(1.0, float(survivors.size())) + randf_range(-0.35, 0.35)
		survivors[i].call("set_flee", Vector2(cos(ang), sin(ang)))

func _is_swarm_member(id: String) -> bool:
	return swarm_id == id and not dying

func set_flee(dirv: Vector2) -> void:
	flee_dir = dirv.normalized() if dirv != Vector2.ZERO else Vector2(0.0, -1.0)

## Последняя крыса стаи исчезла (убита или убежала) — чистим реестр за собой,
## чтобы static-словарь не копил мёртвые записи (никаких таймеров после queue_free).
func _maybe_forget_swarm() -> void:
	var sw: Dictionary = SWARMS.get(swarm_id, {})
	if int(sw.get("alive", 0)) <= 0:
		SWARMS.erase(swarm_id)
