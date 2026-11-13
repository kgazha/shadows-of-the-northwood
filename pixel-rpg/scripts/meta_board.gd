class_name MetaBoard
extends CanvasLayer
## t20 P0-3: «Пепельная доска» — мета-доска талантов за Пепел (пепел переживает
## смерть: сохраняется 60–70% заработанного, см. game_state.gd::start_new_run).
## Вход — ТОЛЬКО с экрана смерти (кнопка «Доска пепла» в RunSummary): покупка
## между забегами, эффекты применяются к новому забегу (хуки: _wipe_circle/recalc
## _max_hp/player speed/loot gold). 4 таланта × 3 ранга, цены [2,5,9] пепла.
##
## Ввод: доска НЕ владеет input_locked — лок держит RunSummary (доска стоит
## поверх неё, layer=7). Esc маршрутизирует RunSummary: сначала закрыть доску,
## затем «Вспыхнуть заново». Закрытая доска мышь и клавиши не ест (паттерн
## RunSummary/Journal).
##
## Ранги — int 0..3 в GameState.flags["meta.mb.<id>"] (вечный мета-слой, rs-вайп
## не трогает). Покупка — через единый канал Ash.spend (списание+сейв).

static var I: MetaBoard          # синглтон; назначает сам себя в _enter_tree

const KEY_PREFIX := "meta.mb."
## Цены рангов 1/2/3 в Пепле (порог входа низкий: 1 смерть круга ≈ 2 угля).
const COSTS := [2, 5, 9]
## Таблица талантов: vals — числовой эффект ранга 1/2/3 (единственный источник
## чисел и для хуков (GameState.mb_value), и для UI).
const TALENTS := [
	{"id": "first_coal",   "name": "Первые угли",     "vals": [15, 30, 50], "fmt": "+%d зол. в начале забега"},
	{"id": "coal_heart",   "name": "Углевое сердце",  "vals": [4, 8, 12],   "fmt": "+%d к макс. HP"},
	{"id": "ash_step",     "name": "Пепельная поступь", "vals": [4, 8, 12],  "fmt": "+%d%% к скорости хода"},
	{"id": "deep_pockets", "name": "Глубокие карманы", "vals": [8, 16, 24],  "fmt": "+%d%% золота с мобов"},
]

var root: Control                # полноэкранный корень; visible = «открыта»
var dim: ColorRect
var panel: PanelContainer
var rows_box: VBoxContainer      # ряды талантов (пересобираются)
var balance_lbl: Label
var bless_lbl: Label
var close_btn: Button
var _buy_guard := false          # t32: покупка в текущем кадре уже была

func _enter_tree() -> void:
	if I == null:
		I = self

func _exit_tree() -> void:
	if I == self:
		I = null

func _ready() -> void:
	layer = 7  # поверх RunSummary (6), ниже фейда переходов (10)
	_build()

# --- статические обёртки (паттерн RunSummary) ---

static func open() -> void:
	if I == null or I.root == null:
		return
	# t29 B-09 (реестр t28): гейта не было вовсе — MetaBoard.open() из любого кода
	# поднимал доску (layer=7) посреди живого забега. Контракт: вход ТОЛЬКО с
	# экрана итогов, поэтому пока RunSummary закрыт — отказ (как Shop.open() под
	# чужим окном). Штатная кнопка «Доска пепла» живёт на RunSummary — не затронута.
	if not RunSummary.is_open():
		GameAudio.sfx("ui_deny")
		return
	I._set_open(true)

static func close_panel() -> void:
	if I == null or I.root == null:
		return
	I._set_open(false)

static func is_open() -> bool:
	return I != null and I.root != null and I.root.visible

# --- данные (статические, читают GameState.flags) ---

## Ранг таланта (0..3) — через единую точку GameState.mb_rank.
static func rank_of(id: String) -> int:
	return GameState.mb_rank(id)

## Эффект ранга (0 при ранге 0) — ЕДИНСТВЕННАЯ таблица чисел для хуков игры.
static func value_at_rank(rank: int, id: String) -> int:
	for t in TALENTS:
		if String(t["id"]) == id:
			var vals: Array = t["vals"]
			if rank <= 0 or rank > vals.size():
				return 0
			return int(vals[rank - 1])
	return 0

## Цена следующего ранга (ранг 0->2, 1->5, 2->9); после капа — -1.
static func next_cost(rank: int) -> int:
	if rank < 0 or rank >= COSTS.size():
		return -1
	return int(COSTS[rank])

## Купить следующий ранг: известность id -> кап ранга -> Ash.spend -> флаг -> сейв.
## Возвращает true, если покупка состоялась. Неизвестный id — отказ (деньги не тратятся).
static func buy(id: String) -> bool:
	var known := false
	for t in TALENTS:
		if String(t["id"]) == id:
			known = true
	if not known:
		return false
	var r := rank_of(id)
	if r >= COSTS.size():
		return false
	var cost := next_cost(r)
	if cost <= 0 or not Ash.spend(cost):  # spend сам проверяет баланс и сохраняет
		return false
	GameState.flags[KEY_PREFIX + id] = r + 1
	GameState.save_game()
	return true

# --- построение панели (паттерн RunSummary: PaperEdge + panel_frame) ---

func _build() -> void:
	var th := Theme.new()
	UIFont.apply(th, 9)  # t27 P1-1: пиксельный шрифт с кириллицей, базовая ступень 8 -> 9
	root = Control.new()
	root.name = "MetaBoardRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(252, 0)
	panel.theme = th
	if ResourceLoader.exists("res://assets/ui/panel_frame.png"):
		panel.add_theme_stylebox_override("panel", _ui_frame_style(26.0))
	center.add_child(panel)
	# t52 снос (закон пользователя 13.11): ген-кромка пергамента снята — доска
	# остаётся на код-панели HUD-стиля (9-slice panel_frame + тема), без картинок.
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)  # t27 P1-1: разделители +2
	panel.add_child(vb)
	var head := Label.new()
	head.text = "Пепельная доска"
	head.add_theme_font_size_override("font_size", 10)
	head.add_theme_color_override("font_color", Color(0.85, 0.55, 0.25))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	# строка баланса: иконка пепла (t52: код-заглушка UiIcons вместо ген-атласа)
	# + счётчик
	var bal_row := HBoxContainer.new()
	bal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bal_row.add_theme_constant_override("separation", 4)
	vb.add_child(bal_row)
	var ash_icon := TextureRect.new()
	ash_icon.texture = AshIcon.make()
	ash_icon.custom_minimum_size = Vector2(16, 16)
	ash_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ash_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ash_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bal_row.add_child(ash_icon)
	balance_lbl = Label.new()
	balance_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	bal_row.add_child(balance_lbl)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 5)  # t27 P1-1: +2
	vb.add_child(rows_box)
	bless_lbl = Label.new()
	bless_lbl.add_theme_color_override("font_color", Color(0.65, 0.8, 0.7))
	vb.add_child(bless_lbl)
	close_btn = Button.new()
	close_btn.text = "Закрыть (Esc)"
	close_btn.pressed.connect(_on_close)
	vb.add_child(close_btn)

## Тёмная деревянная рамка (тот же ассет, что Shop/RunSummary).
func _ui_frame_style(content: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/ui/panel_frame.png")
	sb.region_rect = Rect2(0, 0, 32, 32)
	sb.texture_margin_left = 4
	sb.texture_margin_top = 4
	sb.texture_margin_right = 4
	sb.texture_margin_bottom = 4
	sb.content_margin_left = content
	sb.content_margin_top = content
	sb.content_margin_right = content
	sb.content_margin_bottom = content
	return sb

# --- открытие/пересборка ---

func _set_open(v: bool) -> void:
	if root.visible == v:
		return
	root.visible = v
	root.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
	GameAudio.sfx("ui_confirm" if v else "ui_click")
	if v:
		_rebuild()

## Пересборка рядов и счётчиков (после открытия и каждой покупки).
func _rebuild() -> void:
	for c in rows_box.get_children():
		# t32: до конца кадра ряд ещё жив в дереве и ХИТТЕСТABLE (queue_free —
		# отложенное удаление), поэтому его кнопки гасятся СИНХРОННО: второй клик
		# «по мёртвой» кнопке не должен ни нажиматься, ни что-то покупать.
		_invalidate_row(c)
		c.queue_free()
	balance_lbl.text = "Пепел: %d" % Ash.balance()
	var stacks := GameState.volkhv_stacks()
	bless_lbl.text = "Благословение волхвы: +%d%% урона (%d смерт.)" % [
		int(round(GameState.BLESS_PER_DEATH * 100.0 * float(stacks))), stacks,
	]
	for t in TALENTS:
		_add_row(t)

## t32: мгновенная инвалидация ряда, помеченного на удаление: кнопка->disabled +
## мышь->IGNORE рекурсивно. queue_free() исполняется только в конце кадра, и до
## того момента старая кнопка оставалась кликабельной — отсюда двойная трата пепла.
func _invalidate_row(c: Node) -> void:
	if c is Button:
		(c as Button).disabled = true
	if c is Control:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		_invalidate_row(ch)

func _add_row(t: Dictionary) -> void:
	var id := String(t["id"])
	var r := rank_of(id)
	var row := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	row.add_child(hb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(col)
	var name_lbl := Label.new()
	# точки ранга: ● куплен, ○ свободен (3 гнезда)
	var dots := ""
	for i in COSTS.size():
		dots += "●" if i < r else "○"
	name_lbl.text = "%s  %s" % [String(t["name"]), dots]
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.87, 0.75))
	col.add_child(name_lbl)
	var eff := Label.new()
	eff.add_theme_font_size_override("font_size", 8)  # t27 P1-1: мин. ступень 7 -> 8
	eff.add_theme_color_override("font_color", Color(0.7, 0.66, 0.58))
	if r < COSTS.size():
		eff.text = String(t["fmt"]) % int((t["vals"] as Array)[r])
	else:
		eff.text = "Максимум"
	col.add_child(eff)
	var btn := Button.new()
	if r >= COSTS.size():
		btn.text = "Макс."
		btn.disabled = true
	else:
		var cost := next_cost(r)
		btn.text = "Ранг %d — %d пепла" % [r + 1, cost]
		btn.disabled = Ash.balance() < cost
		# t32: кнопка носит ранг, под которым её нарисовали, — обработчик сверяет
		# его с фактическим и отбивает устаревшее нажатие.
		btn.pressed.connect(_on_buy.bind(id, r))
	btn.custom_minimum_size = Vector2(96, 0)
	hb.add_child(btn)
	# t27: латентный база-баг — row НИКОГДА не добавлялся в rows_box (ни в каком
	# коммите), строки талантов не попадали в дерево и не рисовались. Без этой
	# строки P0-1 («eff-текст каждой строки») невыполним в принципе.
	rows_box.add_child(row)

## Покупка по клику. t32 — три слоя защиты от двойной траты Пепла (дыра: строки
## гасятся queue_free() и до конца кадра остаются в дереве кликабельными, два
## сигнала pressed проходили валидацию дважды -> ранг +2 и −7 пепла за ранг 1):
##  1) rendered_rank — ранг, под которым кнопка отрисована: СИНХРОННАЯ сверка с
##     фактическим рангом отбивает нажатие устаревшей кнопки в любой момент;
##  2) _buy_guard — не более одной покупки на кадр: повторный сигнал (та же или
##     другая строка, программный emit) в этом же кадре игнорируется; флаг снимает
##     отложенный вызов в конце кадра, поэтому штатные клики в разных кадрах
##     работают как прежде;
##  3) _invalidate_row() в _rebuild() гасит старые кнопки сразу (disabled/IGNORE),
##     так что «мёртвая» строка физически не кликается до конца кадра.
func _on_buy(id: String, rendered_rank: int = -1) -> void:
	if _buy_guard:
		return  # покупка в этом кадре уже обработана
	if rendered_rank >= 0 and rank_of(id) != rendered_rank:
		return  # кнопка устарела: ряд пересобран, ранг уже другой
	_buy_guard = true
	_release_buy_guard.call_deferred()
	var tname := id
	for t in TALENTS:
		if String(t["id"]) == id:
			tname = String(t["name"])
	if buy(id):
		GameAudio.sfx("coin")
		GameState.toast.emit("Доска пепла: «%s» — ранг %d." % [tname, MetaBoard.rank_of(id)])
	else:
		GameAudio.sfx("ui_deny")
	_rebuild()
	# экран смерти под доской показывает баланс — освежить, если открыт
	if RunSummary.I != null and RunSummary.is_open():
		RunSummary.I._refresh()

## t32: снять «покупка в этом кадре была». Отложенный вызов исполняется в конце
## текущего кадра (после раздачи всех событий ввода), поэтому следующий кадр —
## снова одна легитимная покупка, а все нажатия текущего кадра уже отсеяны.
func _release_buy_guard() -> void:
	_buy_guard = false

func _on_close() -> void:
	close_panel()
