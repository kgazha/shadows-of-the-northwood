extends Area2D
## Костёр-привал: E — «Отдых» каналом REST_TIME секунд.
## Дефицит и риск: отдых прерывается боем/ходом/диалогом и НЕ лечит при прерывании;
## костёр одноразовый — пепел навсегда (см. обоснование SINGLE_USE ниже).

## Канал отдыха, сек. Ниже 3 — незаметно, выше 6 — раздражающе на паутине.
const REST_TIME := 4.0
## HP за завершённый отдых. max_hp героя 10..20+: это «много», но не heal_full.
const REST_HP := 6
## true — костёр гаснет после первого отдыха. Выбран одноразовый вариант, а не
## длинный таймер: мир остаётся «голодным» на восстановление вне квестовых наград,
## игрок планирует привал перед danger-зонами; состояние id->used тривиально сериализуется.
const SINGLE_USE := true
## Резерв балансировки: если одноразовость станет слишком жёсткой — поставить >0
## (секунды до повторного зажигания). -1 = никогда.
const REKINDLE_AFTER := -1.0

## Для hud/world: маркер «это костёр» (world.campfire_near / панель варки).
var is_campfire := true
var world
var camp_id := ""
var used := false
var resting := false
var rest_t := 0.0
var _anim: AnimatedSprite2D
var _rekindle_t := 0.0
var _shape: CollisionShape2D

func setup(p_world: Node2D, id: String, tile: Vector2i) -> void:
	world = p_world
	camp_id = id
	position = world.tile_to_world(tile)
	used = bool(GameState.campfires_used.get(id, false))
	var spr := Sprite2D.new()
	_anim = AnimatedSprite2D.new()
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	_build_anim(fr, "fire", [0, 1, 2, 3], 7.0)
	_build_anim(fr, "ash", [4], 1.0)
	_anim.sprite_frames = fr
	spr.visible = false  # кадрами рулит AnimatedSprite2D
	add_child(spr)
	add_child(_anim)
	_shape = CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 13.0
	_shape.shape = sh
	add_child(_shape)
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	_set_state_visual()

func _build_anim(fr: SpriteFrames, anim_name: String, cells: Array, fps: float) -> void:
	var tex := load("res://assets/campfire.png")
	fr.add_animation(anim_name)
	fr.set_animation_loop(anim_name, anim_name == "fire")
	fr.set_animation_speed(anim_name, fps)
	for c in cells:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(int(c) * 16, 0, 16, 16)
		fr.add_frame(anim_name, at, 0.0)

func _set_state_visual() -> void:
	if used:
		_anim.play("ash")
		_shape.set_deferred("disabled", true)  # пепел: не подсказка, не интеракт
	else:
		_anim.play("fire")
		_shape.set_deferred("disabled", false)

func get_hint() -> String:
	if used:
		return "Костёр погас"
	if resting:
		return "Отдыхаешь… не двигайся"
	if GameState.combat_t > 0.0:
		return "Слишком тревожно — сначала отойди от погони"
	if GameState.hp >= GameState.max_hp and (GameState.max_mana <= 0 or GameState.mana >= GameState.max_mana):
		return "Ты и так полон сил"
	return "Отдохнуть у костра"

func try_interact() -> void:
	if used or resting:
		return
	if GameState.combat_t > 0.0:
		GameState.toast.emit("Рядом враги — отдыхать нельзя. (бой %ds)" % ceili(GameState.combat_t))
		return
	if GameState.hp >= GameState.max_hp and (GameState.max_mana <= 0 or GameState.mana >= GameState.max_mana):
		GameState.toast.emit("Ты и так полон сил. Костёр одноразовый — поберечь на худшие времена.")
		return
	resting = true
	rest_t = 0.0
	GameAudio.sfx("belt")  # шелест снаряги: садимся, отстёгиваем пояс
	GameState.toast.emit("Ты садишься к огню… (не двигайся и не вступай в бой)")

func _process(delta: float) -> void:
	# резервный путь баланса: повторное зажигание (по умолчанию выключено)
	if REKINDLE_AFTER > 0.0 and used:
		_rekindle_t -= delta
		if _rekindle_t <= 0.0:
			used = false
			GameState.campfires_used.erase(camp_id)
			_set_state_visual()
	if not resting:
		return
	# прерывание: диалог/модалка, смерть, бой (любой entered_combat/take_damage), ход игрока
	if GameState.input_locked or GameState.hp <= 0:
		_cancel("Отдых прерван.")
		return
	if GameState.combat_t > 0.0:
		_cancel("Нападение! Отдых прерван.")
		return
	if world != null and world.player != null and world.player.velocity.length_squared() > 1.0:
		_cancel("Ты встал и пошёл прочь.")
		return
	rest_t += delta
	if rest_t >= REST_TIME:
		_finish()

func _cancel(msg: String) -> void:
	resting = false
	rest_t = 0.0
	GameState.toast.emit(msg)

func _finish() -> void:
	resting = false
	rest_t = 0.0
	if FirstHint.I != null: FirstHint.I.show_hint("campfire", "Костёр вернул силы. Отдыхай перед дорогой — пещера ошибок не прощает.")
	if SINGLE_USE:
		_mark_used()
		Achv.on_campfire_used()  # ачивка «Трёх костров» (achv.gd)
	GameState.heal(REST_HP)
	var msg: String = "Тёплое забытье: +%d HP" % REST_HP
	if GameState.max_mana > 0 and GameState.mana < GameState.max_mana:
		GameState.mana = GameState.max_mana
		msg += ", энергия полна"
	GameState.stats_changed.emit()
	GameState.quest_changed.emit()  # автосейв: состояние костра не должно потеряться
	GameAudio.sfx("ui_confirm")  # отдых завершён — «динь-дон»
	GameState.toast.emit(msg)

func _mark_used() -> void:
	used = true
	GameState.campfires_used[camp_id] = true
	_set_state_visual()
	world.near.erase(self)
	if REKINDLE_AFTER > 0.0:
		_rekindle_t = REKINDLE_AFTER

func _on_enter(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.append(self)

func _on_exit(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.erase(self)
		if resting:
			_cancel("Ты отошёл от костра.")
