extends CharacterBody2D
## Слайм: бродит, преследует героя, бьёт при контакте.

const CHASE_DIST := 48.0
const HIT_DIST := 11.0
const SPEED_CHASE := 40.0
const SPEED_WANDER := 16.0
## Возобновляемый ресурс прокачки: слайм отрастает у дома через ~50 с.
const RESPAWN := 50.0
## Дроп алхимических материалов: умеренный шанс (дефицит — ~4 слайма на материал).
const MAT_DROP_CHANCE := 0.25
const MAT_DROP_TABLE := ["suhotsvet", "zhim"]
## NG+ §1.3: базы до скейла по волне. Формулы — в game_state.gd (одна точка истины).
const BASE_HP := 3
const BASE_DMG := 1

var world: Node2D
var hp := BASE_HP
## Урон контакта (база + волновой бонус, §1.3).
var dmg := BASE_DMG
var anim: AnimatedSprite2D
var wander_t := 0.0
var dirv := Vector2.ZERO
var hurt_t := 0.0
## Заморозка («Морозная нова» мага): >0 — не двигается и не бьёт, синий тинт.
var freeze_t := 0.0
## Смерть: тайм-аут до возрождения у «дома».
var dying := false
var respawn_t := 0.0
var home := Vector2.ZERO
var _shape: CollisionShape2D

func setup(p_world: Node2D, tile: Vector2i) -> void:
	world = p_world
	_apply_ng_stats()
	position = world.tile_to_world(tile)
	home = position
	collision_layer = 4
	collision_mask = 2 | 4  # слой героя (1) убран: вместо взаимной блокировки — мягкое выталкивание (_push_from_hero)
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
	fr.add_animation("walk")
	fr.set_animation_loop("walk", true)
	fr.set_animation_speed("walk", 3.0)
	var tex := load("res://assets/slime.png")
	for col in [0, 1]:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(col * 16, 0, 16, 16)
		fr.add_frame("walk", at, 0.0)
	anim.sprite_frames = fr
	add_child(anim)
	anim.play("walk")

## HP/урон по текущей волне NG+ (§1.3); пересчёт при спавне и дома у респауна.
func _apply_ng_stats() -> void:
	var w := GameState.ng_wave()
	hp = int(round(BASE_HP * GameState.hp_mult(w)))
	dmg = BASE_DMG + GameState.dmg_bonus(w)

func _physics_process(delta: float) -> void:
	if dying:
		respawn_t -= delta
		if respawn_t <= 0.0:
			_respawn()
		return
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
		_push_from_hero()  # мёрзлый слайм тоже уступает место герою, не лежит под ним
		return
	var d := global_position.distance_to(world.player.global_position)
	if d < CHASE_DIST:
		dirv = (world.player.global_position - global_position).normalized()
		velocity = dirv * SPEED_CHASE
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(1.2, 2.6)
			if randf() < 0.35:
				dirv = Vector2.ZERO
			else:
				dirv = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		velocity = dirv * SPEED_WANDER
	move_and_slide()
	_push_from_hero()
	if d < HIT_DIST:
		world.player.take_damage(dmg)

## «Стенка без пиления» (дребезг экрана вплотную к врагу): герой со слоем 1 убран
## из маски моба — иначе два CharacterBody2D при упоре друг в друга каждый кадр
## расталкиваются в противофазе (move_and_slide), и висящая на герое камера
## дребезжит. Стенка сохраняется мягко: если герой залез в нас, не расталкиваемся —
## сами отходим вдоль оси наименьшего проникновения боксов.
## Точка равновесия равна старому физическому контакту боксов — дистанции боя
## (HIT_DIST) не меняются. Стены для выталкивания — препятствия (move_and_collide).
func _push_from_hero() -> void:
	if world == null or world.player == null:
		return
	var d: Vector2 = global_position - world.player.global_position
	var mb := Vector2(10, 8)  # бокс слайма == бокс героя
	var ox := (mb.x + 10.0) * 0.5 - absf(d.x)
	var oy := (mb.y + 8.0) * 0.5 - absf(d.y)
	if ox <= 0.0 or oy <= 0.0:
		return
	if ox < oy:
		var sx := signf(d.x)
		if sx == 0.0:
			sx = 1.0  # точное совпадение центров — отходим вправо
		move_and_collide(Vector2(sx * (ox + 0.05), 0.0))
	else:
		var sy := signf(d.y)
		if sy == 0.0:
			sy = -1.0  # точное совпадение центров — отходим вверх
		move_and_collide(Vector2(0.0, sy * (oy + 0.05)))

func hurt(dmg: int, from: Vector2) -> void:
	if dying:
		return
	GameState.entered_combat()  # контакт с врагом — реген паузится
	DmgNumbers.spawn(global_position + Vector2(0, -12), dmg, "normal")
	hp -= dmg
	hurt_t = 0.3
	velocity = (global_position - from).normalized() * 70.0
	if hp <= 0:
		_die()

func _die() -> void:
	dying = true
	respawn_t = RESPAWN
	GameAudio.sfx("drop")  # шлепок тела (кожа)
	GameState.slime_kills += 1
	GameState.slime_kills_circle += 1  # убийства ТЕКУЩЕГО круга: квесты-обёртки и
									   # сдача торговцу считаются по нему (game_state)
	Achv.on_slime_kill()  # ачивки «Охотник 25/100» (achv.gd)
	if FirstHint.I != null: FirstHint.I.show_hint("slime", "Первая победа! С тварей падает добыча, а торговцу нужны слаймы.")
	GameState.add_xp(7)
	GameAudio.sfx("coin")  # автораздача опыта — звон монет
	GameState.toast.emit("Слайм повержен! (+7 опыта)")
	_roll_mat_drop()
	Loot.on_mob_death("slime", global_position)
	GameState.quest_changed.emit()
	if GameState.slime_quest == 1 and GameState.slime_kills_circle == 3:
		GameState.toast.emit("Три готово! Вернись к торговцу за наградой.")
	remove_from_group("enemy")
	visible = false
	_shape.disabled = true

## Один бросок на материал со смерти; при полном рюкзаке — трофей теряется (дефицит).
func _roll_mat_drop() -> void:
	# Талант «Травничество» (herblore, CONTRACT_TALENTS §3): шанс дропа 0.25 -> 0.32.
	if randf() >= (0.32 if GameState.tal_rank("herblore") > 0 else MAT_DROP_CHANCE):
		return
	var mid := String(MAT_DROP_TABLE[randi() % MAT_DROP_TABLE.size()])
	if not GameState.add_material(mid):
		GameState.toast.emit("Рюкзак полон — %s потерян" % GameState.mat_name(mid))
		return
	GameState.toast.emit("Трофей: %s (%d/%d)" % [GameState.mat_name(mid), GameState.mat_count(mid), GameState.MAT_CAP])

func _respawn() -> void:
	dying = false
	_apply_ng_stats()  # NG+ §1.3: домой волна могла уйти вперёд
	freeze_t = 0.0
	hurt_t = 0.0
	position = home
	modulate = Color.WHITE
	visible = true
	_shape.disabled = false
	add_to_group("enemy")
