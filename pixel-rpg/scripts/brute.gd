extends CharacterBody2D
## Босс «Осквернённый гром»: медленно преследует героя, бьёт при контакте.
## Лист assets/brute.png — 64x32, два кадра 32x32.

const SPEED := 30.0
const HIT_DIST := 12.0
## Рывок: раз в ~4.5 с гром бросается вперёд — давление и на ближний бой,
## и на «стойщих» вдали лучника/мага (правка баланса из retention-ревью).
const CHARGE_SPEED := 80.0
const CHARGE_CD := 4.5
const CHARGE_TIME := 0.7
const CHARGE_MIN_DIST := 26.0

var world: Node2D
var hp := 12
var anim: AnimatedSprite2D
var hurt_t := 0.0
## Заморозка («Морозная нова» мага): >0 — не двигается и не бьёт, синий тинт.
var freeze_t := 0.0
var charge_t := 2.5
var rush_t := 0.0
var rush_dir := Vector2.ZERO

func setup(p_world: Node2D, tile: Vector2i) -> void:
	world = p_world
	position = world.tile_to_world(tile)
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("enemy")
	add_to_group("boss")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(18, 16)
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
	else:
		push_warning("Нет ассета: assets/brute.png — у босса цветная заглушка")
		var ph := ColorRect.new()
		ph.color = Color(0.45, 0.28, 0.5)
		ph.size = Vector2(24, 22)
		ph.position = Vector2(-12, -11)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ph)

func _physics_process(delta: float) -> void:
	hurt_t = maxf(0.0, hurt_t - delta)
	freeze_t = maxf(0.0, freeze_t - delta)
	if hurt_t > 0.0:
		modulate = Color(1, 0.5, 0.5)
	elif freeze_t > 0.0:
		modulate = Color(0.55, 0.75, 1.0)
	else:
		modulate = Color.WHITE
	if GameState.input_locked or world.player == null or GameState.hp <= 0:
		velocity = Vector2.ZERO
		return
	if freeze_t > 0.0:
		velocity = Vector2.ZERO
		return
	var d := global_position.distance_to(world.player.global_position)
	if rush_t > 0.0:
		rush_t -= delta
		modulate = Color(1.15, 0.7, 0.55) if hurt_t <= 0.0 and freeze_t <= 0.0 else modulate
		velocity = rush_dir * CHARGE_SPEED
	else:
		charge_t -= delta
		if charge_t <= 0.0 and d > CHARGE_MIN_DIST:
			charge_t = CHARGE_CD
			rush_t = CHARGE_TIME
			rush_dir = (world.player.global_position - global_position).normalized()
			GameState.toast.emit("Гром бросается вперёд — отходи!")
		else:
			velocity = (world.player.global_position - global_position).normalized() * SPEED
	move_and_slide()
	if global_position.distance_to(world.player.global_position) < HIT_DIST:
		world.player.take_damage(2)

func hurt(dmg: int, from: Vector2) -> void:
	hp -= dmg
	hurt_t = 0.3
	velocity = (global_position - from).normalized() * 50.0
	if hp <= 0:
		GameState.boss_defeated = true
		GameState.add_xp(40)
		GameState.toast.emit("Гниль отступает!")
		GameState.quest_changed.emit()
		queue_free()
