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
	# NG+ P2 («Круги Пепла», RETENTION_NG_PLUS §1.1): Старейшина — проводник круга.
	# Ветка ТОЛЬКО npc_id=="elder", прочие NPC идут своим путём нетронутые.
	# Условия: в текущем круге пала Ведьма Пепелища (ashen.boss; start_ng_plus
	# стирает флаг — дедупликация по кругу встроена) и волна под капом. «Опция» = дочитать
	# реплику до конца — паттерн согласия этого кодовой базы (так же принимаются
	# квесты elder_quest). Обычный разговор — колбэком после реплики; при старте
	# круга сцену перезагружает хук ng_plus_started в world.gd и talk() не доживает
	# до конца диалога — это задумано (новый круг начинается сразу).
	if npc_id == "elder":
		var wave := GameState.ng_wave()
		if String(GameState.flags.get("ashen.boss", "")) == "dead":
			if wave < GameState.NG_WAVE_CAP:
				world.hud.show_dialog([
					{"who": "elder", "text": "Пепел ведьмы ещё не остыл... Круг замкнулся, герой."},
					{"who": "elder", "text": "Впереди — новый Круг Пепла. Старые подвиги миром уже сыты."},
					{"who": "elder", "text": "Станешь угольком, что разожжёт мир снова? [Круг %d]" % (wave + 1)},
				], func() -> void: GameState.start_ng_plus())
				return
			# кап пройден: финальная реплика один раз на кап-волну, без действия
			if int(GameState.flags.get("ng.cap_seen", -1)) != wave:
				GameState.flags["ng.cap_seen"] = wave
				world.hud.show_dialog([
					{"who": "elder", "text": "Финальный круг пройден — мир ждёт героя. Пепла глубже нет."},
				], func() -> void: world.talk(npc_id))
				return
	world.talk(npc_id)

func _on_enter(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.append(self)

func _on_exit(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.erase(self)
