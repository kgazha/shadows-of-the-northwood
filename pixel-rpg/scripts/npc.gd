extends Area2D
## NPC: спрайт, зона взаимодействия, подсказка "E", квестовый маркер «!»/«?».
## Маркер (задача «Квесты: однократность + маркеры»): «!» — квест можно взять
## (жёлтый), «?» — можно сдать (зелёный, приоритетнее); состояние считает
## QuestsData.marker_state, обновляемся по сигналу quest_changed (не поллингом);
## во время диалога/модалки (input_locked) прячемся; лёгкое синусоидальное
## покачивание — единственная пер-кадровая работа (косметика).

const MARKER_BASE_Y := -25.0   # верхняя строка метки над макушкой (t51 «было»: спрайт 16 px)
const MARKER_BOB_HZ := 3.4     # rad/s — спокойное «дышащее» покачивание
const MARKER_BOB_AMP := 1.5    # px амплитуда
## t51 (возврат «до Крупного мира»): NPC 16 px 1:1 (мультипликат H=32 снят);
## коллайдер 14x16 и зона взаимодействия — прежние. Якорь ZERO, как было.
const VISUAL_SCALE := 1.0
const SPR_HOME_Y := 0.0

var world: Node2D
var npc_id := ""
var _marker: Label
var _marker_state := QuestsData.MARKER_NONE
var _bob := 0.0

func setup(p_world: Node2D, id: String, tile: Vector2i) -> void:
	world = p_world
	npc_id = id
	position = world.tile_to_world(tile)
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/npc_%s.png" % id)
	# волна 5: крупнее только визуально — Area2D-триггер разговора не изменился
	spr.scale = Vector2.ONE * VISUAL_SCALE
	spr.position = Vector2(0, SPR_HOME_Y)
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
	_make_marker()

func _make_marker() -> void:
	# Label вместо спрайта — процедурная графика проекта (никаких ассетов);
	# контур и кегль как у world.hint_label / цифр урона — читаемо на лесу.
	_marker = Label.new()
	_marker.name = "QuestMarker"
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.size = Vector2(24, 10)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_marker.add_theme_constant_override("outline_size", 4)
	_marker.add_theme_font_size_override("font_size", 8)
	# y_sort в проекте не используется (канон отмечен в dmg_numbers.gd:7),
	# z_index — штатный способ держать world-space подпись поверх сущностей:
	# выше спрайтов (0) и декора (-8), ниже цифр урона (90) и радара (100).
	_marker.z_index = 8
	_marker.visible = false
	add_child(_marker)
	_refresh_marker()
	# GameState — вечноживущий autoload, но коннект к освобождённому NPC
	# отваливается сам; каждый новый NPC подписывается на своём setup().
	GameState.quest_changed.connect(_on_quest_state)

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
		if str(GameState.flags.get("ashen.boss", "")) == "dead":
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

func _on_quest_state() -> void:
	# Канон однократности «Трав»: world.gd в колбэке сдачи пишет elder_quest=2
	# и сразу эмитит quest_changed — вечную meta-метку ловим в этом же эмите
	# (идемпотентный sync) и тут же фиксируем на диск, чтобы следующий
	# _wipe_circle застал её даже после crash/reload.
	if QuestsData.sync_story_permanence(GameState):
		GameState.save_game()
	_refresh_marker()

func _refresh_marker() -> void:
	_marker_state = QuestsData.marker_state(GameState, npc_id)
	match _marker_state:
		QuestsData.MARKER_TAKE:
			_marker.text = "!"
			_marker.add_theme_color_override("font_color", Color(1.0, 0.7, 0.26))  # t18: «!» — амбер: интерактив (золото оставлено луту)
		QuestsData.MARKER_READY:
			_marker.text = "?"
			_marker.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5))  # «?» — зелёный: сдавай
		_:
			_marker.visible = false

func _process(delta: float) -> void:
	# Диалог/модалка (input_locked) — маркер прячем: реплика важнее подсказки.
	if _marker_state == QuestsData.MARKER_NONE or GameState.input_locked:
		_marker.visible = false
		return
	_bob += delta
	# Фаза — от позиции NPC (без RNG — глобальный рандер не крутим, D3):
	# синхронно не дышат, но детерминированно.
	var y := MARKER_BASE_Y + sin(_bob * MARKER_BOB_HZ + fmod(position.x, TAU)) * MARKER_BOB_AMP
	_marker.position = Vector2(-12, y)
	_marker.visible = true
