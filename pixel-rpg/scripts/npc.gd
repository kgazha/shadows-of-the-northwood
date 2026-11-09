extends Area2D
## NPC: спрайт, зона взаимодействия, подсказка "E".

var world: Node2D
var npc_id := ""

func setup(p_world: Node2D, id: String, tile: Vector2i) -> void:
	world = p_world
	npc_id = id
	position = world.tile_to_world(tile)
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/npc_%s.png" % id)
	add_child(spr)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(14, 16)
	cs.shape = sh
	add_child(cs)
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func get_hint() -> String:
	return "Поговорить"

func try_interact() -> void:
	world.talk(npc_id)

func _on_enter(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.append(self)

func _on_exit(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.erase(self)
