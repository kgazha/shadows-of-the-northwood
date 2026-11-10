extends CharacterBody2D
## Босс «Осквернённый гром» (boss=true) и «отпрыски гнили» (boss=false) —
## моб пещеры трёх ярусов, которых world.gd расставляет по глубине (CAVE_MOB_BANDS).
## Лист assets/brute.png — 64x32, два кадра 32x32.
## Баланс (правка пещеры): герой 3–5 уровня проходит ярусы с потерями, но живым;
## пик сложности — босс. Было: hp 12 / dmg 2 / speed 30 / рывок раз в 4.5 с.

const HIT_DIST_BOSS := 12.0
const HIT_DIST_MOB := 9.0
## Рывок: босс каждые 4.0 с, ярусы 2–3 — реже; ярус 1 не рывкует (cd=0).
const CHARGE_SPEED := 80.0
const CHARGE_TIME := 0.7
const CHARGE_MIN_DIST := 26.0
const LEASH := 64.0        # моб преследует героя только в этом радиусе
const WANDER_R := 24.0     # и бродит не дальше этого от точки появления
const BOSS_HP := 24
const BOSS_DMG := 3
const BOSS_SPEED := 34.0
const BOSS_CHARGE_CD := 4.0
const BOSS_XP := 40
## Ярусы мобов: чем глубже, тем жирнее, злее и быстрее (xp — за убийство).
const TIERS := {
	1: {"hp": 6, "dmg": 1, "speed": 24.0, "xp": 6, "cd": 0.0, "scale": 0.72},
	2: {"hp": 9, "dmg": 2, "speed": 29.0, "xp": 8, "cd": 6.0, "scale": 0.85},
	3: {"hp": 12, "dmg": 2, "speed": 33.0, "xp": 10, "cd": 4.5, "scale": 1.0},
}

var world: Node2D
var boss := true           # false — обычный моб (ставит world.gd до setup)
var tier := 3              # актуален только при boss=false
var hp := BOSS_HP
var dmg := BOSS_DMG
var speed := BOSS_SPEED
var charge_cd := BOSS_CHARGE_CD
var kill_xp := BOSS_XP
var hit_dist := HIT_DIST_BOSS
var anim: AnimatedSprite2D
var hurt_t := 0.0
## Заморозка («Морозная нова» мага): >0 — не двигается и не бьёт, синий тинт.
var freeze_t := 0.0
var charge_t := 2.5
var rush_t := 0.0
var rush_dir := Vector2.ZERO
var home := Vector2.ZERO
var wander_t := 0.0
var wander_dir := Vector2.ZERO
var base_tint := Color.WHITE

func setup(p_world: Node2D, tile: Vector2i) -> void:
	world = p_world
	if not boss:
		var cfg: Dictionary = TIERS[tier]
		hp = int(cfg.hp)
		dmg = int(cfg.dmg)
		speed = float(cfg.speed)
		charge_cd = float(cfg.cd)
		kill_xp = int(cfg.xp)
		hit_dist = HIT_DIST_MOB
		base_tint = Color(0.86, 0.92, 1.0) if tier == 1 else (Color(1.0, 0.96, 0.86) if tier == 2 else Color(0.94, 0.84, 1.0))
	position = world.tile_to_world(tile)
	home = position
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("enemy")
	if boss:
		add_to_group("boss")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(18, 16) if boss else Vector2(10, 8)  # моб проходит узкие проходы
	cs.shape = sh
	add_child(cs)
	anim = AnimatedSprite2D.new()
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	fr.add_animation("walk")
	fr.set_animation_loop("walk", true)
	fr.set_animation_speed("walk", 2.5)
	if ResourceLoader.exists("res://assets/brute.png"):
		var tex := load("res://assets/brute.png")
		for col in [0, 1]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(col * 32, 0, 32, 32)
			fr.add_frame("walk", at, 0.0)
		anim.sprite_frames = fr
		add_child(anim)
		anim.play("walk")
		if not boss:
			anim.scale = Vector2.ONE * float(TIERS[tier].scale)  # ярус 1 мельче, ярус 3 полный
	else:
		push_warning("Нет ассета: assets/brute.png — у босса цветная заглушка")
		var ph := ColorRect.new()
		ph.color = Color(0.45, 0.28, 0.5)
		ph.size = Vector2(24, 22)
		ph.position = Vector2(-12, -11)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ph)
	modulate = base_tint

func _physics_process(delta: float) -> void:
	hurt_t = maxf(0.0, hurt_t - delta)
	freeze_t = maxf(0.0, freeze_t - delta)
	if hurt_t > 0.0:
		modulate = Color(1, 0.5, 0.5)
	elif freeze_t > 0.0:
		modulate = Color(0.55, 0.75, 1.0)
	else:
		modulate = base_tint
	if GameState.input_locked or world.player == null or GameState.hp <= 0:
		velocity = Vector2.ZERO
		return
	if freeze_t > 0.0:
		velocity = Vector2.ZERO
		return
	var player: CharacterBody2D = world.player
	var d := global_position.distance_to(player.global_position)
	if not boss and d > LEASH:
		# героя далеко нет — не идём на весь cave, а сторожим свою часть пещеры
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(1.0, 2.4)
			var off := global_position - home
			if off.length() > WANDER_R or randf() < 0.3:
				wander_dir = -off.normalized()
			else:
				wander_dir = Vector2(randf() - 0.5, randf() - 0.5).normalized()
		velocity = wander_dir * speed * 0.4
		move_and_slide()
		if global_position.distance_to(player.global_position) < hit_dist:
			player.take_damage(dmg)
		return
	if rush_t > 0.0:
		rush_t -= delta
		if hurt_t <= 0.0 and freeze_t <= 0.0:
			modulate = Color(1.15, 0.7, 0.55)
		velocity = rush_dir * CHARGE_SPEED
	else:
		charge_t -= delta
		if charge_cd > 0.0 and charge_t <= 0.0 and d > CHARGE_MIN_DIST:
			charge_t = charge_cd
			rush_t = CHARGE_TIME
			rush_dir = (player.global_position - global_position).normalized()
			if boss:
				GameState.toast.emit("Гром бросается вперёд — отходи!")
		else:
			velocity = (player.global_position - global_position).normalized() * speed
	move_and_slide()
	if global_position.distance_to(player.global_position) < hit_dist:
		player.take_damage(dmg)

func hurt(dmg_in: int, from: Vector2) -> void:
	GameState.entered_combat()  # контакт с врагом — реген паузится
	hp -= dmg_in
	hurt_t = 0.3
	velocity = (global_position - from).normalized() * 50.0
	if hp <= 0:
		if boss:
			GameState.boss_defeated = true
			GameState.add_xp(BOSS_XP)
			GameState.toast.emit("Гниль отступает!")
		else:
			GameState.add_xp(kill_xp)
			GameState.toast.emit("Отпрыск гнили повержен! (+%d XP)" % kill_xp)
		GameState.quest_changed.emit()
		queue_free()
