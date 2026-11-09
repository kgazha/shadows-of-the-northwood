extends Area2D
## Снаряд героя: летит от точки выпуска по направлению.
## assets/projectiles.png 64x16: 0 стрела (вращается по полёту), 1 файербол,
## 2 осколок льда, 3 стрела-призрак (пробивающая, полупрозрачная).

const TEX_PATH := "res://assets/projectiles.png"

var dirv := Vector2.RIGHT
var speed := 200.0
var dmg := 1
var pierce := false
var aoe := 0.0
var life := 1.6
var caster: Node2D          # герой: для «Поглощения» (лечение при попадании)
var _hits := {}             # instance_id уже задетых (pierce не бьёт дважды)

func setup(from: Vector2, dir: Vector2, p_speed: float, p_dmg: int, sprite_idx: int,
		p_pierce := false, p_aoe := 0.0, p_caster: Node2D = null) -> void:
	global_position = from
	dirv = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	speed = p_speed
	dmg = maxi(1, p_dmg)
	pierce = p_pierce
	aoe = p_aoe
	caster = p_caster
	life = 1.6
	# стрела и призрак смотрят по направлению полёта; шары — нет
	rotation = dirv.angle() if sprite_idx == 0 or sprite_idx == 3 else 0.0
	collision_layer = 0
	collision_mask = 4  # только враги
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 3.0
	cs.shape = sh
	add_child(cs)
	if ResourceLoader.exists(TEX_PATH):
		var spr := Sprite2D.new()
		var at := AtlasTexture.new()
		at.atlas = load(TEX_PATH)
		at.region = Rect2(clampi(sprite_idx, 0, 3) * 16, 0, 16, 16)
		spr.texture = at
		if sprite_idx == 3:
			spr.modulate = Color(1, 1, 1, 0.6)  # призрак полупрозрачен
		add_child(spr)
	else:
		push_warning("Нет ассета: assets/projectiles.png — снаряд без спрайта")
	body_entered.connect(_on_hit)

func _physics_process(delta: float) -> void:
	position += dirv * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_hit(b: Node) -> void:
	if not b.is_in_group("enemy") or not b.has_method("hurt"):
		return
	var id := b.get_instance_id()
	if _hits.has(id):
		return
	_hits[id] = true
	if aoe > 0.0:
		# AoE: задевает всех вражей рядом с точкой попадания
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.global_position.distance_to(b.global_position) <= aoe:
				_hit_one(e)
	else:
		_hit_one(b)
	if not pierce:
		queue_free()

func _hit_one(e: Node) -> void:
	e.hurt(dmg, global_position - dirv * 8.0)
	# «Поглощение» мага: попадания снарядов лечат по 1 HP
	if caster != null and is_instance_valid(caster) and float(caster.get("siphon_t")) > 0.0:
		GameState.heal(1)
