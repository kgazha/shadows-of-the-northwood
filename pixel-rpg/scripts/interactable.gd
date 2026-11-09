extends Area2D
## Интерактивный объект: трава или сундук.
## Травы — возобновляемый ресурс (зелья): через ~50 с отрастают на месте.

const HERB_RESPAWN := 50.0

var world: Node2D
var kind := "herb"
var used := false
var spr: Sprite2D
var _respawn_t := 0.0

func setup(p_world: Node2D, p_kind: String, tile: Vector2i) -> void:
	world = p_world
	kind = p_kind
	position = world.tile_to_world(tile)
	spr = Sprite2D.new()
	spr.texture = _atlas(11 if kind == "herb" else 10)
	add_child(spr)
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 10.0
	cs.shape = sh
	add_child(cs)
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func _atlas(tile_index: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/tiles.png")
	at.region = Rect2(tile_index * 16, 0, 16, 16)
	return at

func get_hint() -> String:
	if kind == "herb":
		return "Взять траву" if not used else "Трава ещё не отросла"
	return "Открыть сундук" if not used else "Пустой сундук"

func try_interact() -> void:
	if used:
		return
	if kind == "herb":
		if GameState.elder_quest == 0:
			GameState.toast.emit("Рановато. Сначала поговори со старейшиной.")
			return
		GameState.herbs += 1
		GameState.toast.emit("Трава собрана (всего: %d). Q — испить снадобья (+3 HP)" % GameState.herbs)
		GameState.quest_changed.emit()
		if GameState.elder_quest == 1 and GameState.herbs >= 3:
			GameState.toast.emit("Достаточно! Отнеси старейшине.")
		used = true
		_respawn_t = HERB_RESPAWN
		spr.visible = false
	else:
		used = true
		GameState.has_sword = true
		GameState.toast.emit("Найден Железный меч! Урон x2")
		GameState.stats_changed.emit()
		spr.texture = _atlas(14)
		world.near.erase(self)

func _process(delta: float) -> void:
	if kind == "herb" and used:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			used = false
			spr.visible = true

func _on_enter(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.append(self)

func _on_exit(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.erase(self)
