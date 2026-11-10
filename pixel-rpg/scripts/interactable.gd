extends Area2D
## ÐÐ½ÑÐµÑÐ°ÐºÑÐ¸Ð²Ð½ÑÐ¹ Ð¾Ð±ÑÐµÐºÑ: ÑÑÐ°Ð²Ð° Ð¸Ð»Ð¸ ÑÑÐ½Ð´ÑÐº.
## Ð¢ÑÐ°Ð²Ñ â Ð²Ð¾Ð·Ð¾Ð±Ð½Ð¾Ð²Ð»ÑÐµÐ¼ÑÐ¹ ÑÐµÑÑÑÑ (Ð·ÐµÐ»ÑÑ): ÑÐµÑÐµÐ· ~50 Ñ Ð¾ÑÑÐ°ÑÑÐ°ÑÑ Ð½Ð° Ð¼ÐµÑÑÐµ.

const HERB_RESPAWN := 50.0

var world: Node2D
var kind := "herb"
var used := false
var tile_xy := Vector2i.ZERO
var spr: Sprite2D
var _respawn_t := 0.0

func setup(p_world: Node2D, p_kind: String, tile: Vector2i) -> void:
	world = p_world
	kind = p_kind
	tile_xy = tile
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
	refresh_used()

## Ð¡ÑÐ½Ð´ÑÐº ÑÐ¶Ðµ Ð¾ÑÐºÑÑÑ Ð² Ð¿ÑÐ¾ÑÐ»Ð¾Ð¹ ÑÐµÑÑÐ¸Ð¸ â Ð²Ð¾ÑÑÑÐ°Ð½Ð°Ð²Ð»Ð¸Ð²Ð°ÐµÐ¼ ÑÐ¾ÑÑÐ¾ÑÐ½Ð¸Ðµ Ð¸Ð· ÑÐµÐ¹Ð²Ð° (ÑÐ¸ÐºÑ T2).
## ÐÑÐ·ÑÐ²Ð°ÐµÑÑÑ Ð¸ Ð¿Ð¾ÑÐ»Ðµ load_game(): ÑÑÑÐ½Ð¾ÑÑÐ¸ Ð¼Ð¸ÑÐ° ÑÑÑÐ¾ÑÑÑÑ Ð´Ð¾ ÑÑÐµÐ½Ð¸Ñ ÑÐµÐ¹Ð²Ð°.
func refresh_used() -> void:
	if kind == "chest" and not used and GameState.chest_used(_uid()):
		used = true
		spr.texture = _atlas(14)

## Ð£ÑÑÐ¾Ð¹ÑÐ¸Ð²ÑÐ¹ id Ð¾Ð±ÑÐµÐºÑÐ°: ÑÐ¸Ð¿+ÑÐ°Ð¹Ð» Ð¸Ð· map-Ð¼ÐµÑÑ, Ð½Ð°Ð¿ÑÐ¸Ð¼ÐµÑ "chest@37,21".
func _uid() -> String:
	return "%s@%d,%d" % [kind, tile_xy.x, tile_xy.y]

func _atlas(tile_index: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/tiles.png")
	at.region = Rect2(tile_index * 16, 0, 16, 16)
	return at

func get_hint() -> String:
	if kind == "herb":
		return "ÐÐ·ÑÑÑ ÑÑÐ°Ð²Ñ" if not used else "Ð¢ÑÐ°Ð²Ð° ÐµÑÑ Ð½Ðµ Ð¾ÑÑÐ¾ÑÐ»Ð°"
	return "ÐÑÐºÑÑÑÑ ÑÑÐ½Ð´ÑÐº" if not used else "ÐÑÑÑÐ¾Ð¹ ÑÑÐ½Ð´ÑÐº"

func try_interact() -> void:
	if used:
		return
	if kind == "herb":
		if GameState.elder_quest == 0:
			GameState.toast.emit("Ð Ð°Ð½Ð¾Ð²Ð°ÑÐ¾. Ð¡Ð½Ð°ÑÐ°Ð»Ð° Ð¿Ð¾Ð³Ð¾Ð²Ð¾ÑÐ¸ ÑÐ¾ ÑÑÐ°ÑÐµÐ¹ÑÐ¸Ð½Ð¾Ð¹.")
			return
		GameState.herbs += 1
		GameState.toast.emit("Ð¢ÑÐ°Ð²Ð° ÑÐ¾Ð±ÑÐ°Ð½Ð° (Ð²ÑÐµÐ³Ð¾: %d). Q â Ð¸ÑÐ¿Ð¸ÑÑ ÑÐ½Ð°Ð´Ð¾Ð±ÑÑ (+3 HP)" % GameState.herbs)
		GameState.quest_changed.emit()
		if GameState.elder_quest == 1 and GameState.herbs >= 3:
			GameState.toast.emit("ÐÐ¾ÑÑÐ°ÑÐ¾ÑÐ½Ð¾! ÐÑÐ½ÐµÑÐ¸ ÑÑÐ°ÑÐµÐ¹ÑÐ¸Ð½Ðµ.")
		used = true
		_respawn_t = HERB_RESPAWN
		spr.visible = false
		_sync_shadow()  # иначе чёрный блин тени висит над пустой клеткой до респавна
	else:
		used = true
		GameState.has_sword = true
		GameState.chest_mark_used(_uid())  # Â«ÑÑÐ½Ð´ÑÐº Ð¾ÑÐºÑÑÑÂ» Ð² ÑÐµÐ¹Ð² (ÑÐ¸ÐºÑ T2)
		GameState.toast.emit("ÐÐ°Ð¹Ð´ÐµÐ½ ÐÐµÐ»ÐµÐ·Ð½ÑÐ¹ Ð¼ÐµÑ! Ð£ÑÐ¾Ð½ x2")
		GameState.stats_changed.emit()
		GameState.quest_changed.emit()  # Ð°Ð²ÑÐ¾ÑÐµÐ¹Ð²: Ð¼ÐµÑ Ð¸ ÑÐ¾ÑÑÐ¾ÑÐ½Ð¸Ðµ ÑÑÐ½Ð´ÑÐºÐ°
		spr.texture = _atlas(14)
		world.near.erase(self)

func _process(delta: float) -> void:
	if kind == "herb" and used:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			used = false
			spr.visible = true
			_sync_shadow()  # трава отросла — тень возвращается вместе с ней

func _on_enter(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.append(self)

func _on_exit(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.erase(self)

## Тень атмосферы (AtmoShadow) — отдельный child (вешает atmosphere.gd), поэтому
## при скрытии/возврате спрайта гасим и её синхронно; страховочная синхронизация
## есть и в скане atmosphere (_sync_shadow). Сундук не затронут: его спрайт не
## скрывается (при смене текстуры закрыт->открыт тень остаётся).
func _sync_shadow() -> void:
	var sh := get_node_or_null("AtmoShadow")
	if sh != null:
		(sh as CanvasItem).visible = spr != null and spr.visible
