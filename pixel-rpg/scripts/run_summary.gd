class_name RunSummary
extends CanvasLayer
## «Забег окончен» — терминальная модалка смерти (CONTRACT_RUNLOOP §1.8–1.9):
## открывается вместо респавна по окончании диалога "death" (колбэк в
## world.gd::on_player_death). Единственный выход — кнопка «Вспыхнуть заново»
## (тот же Esc, §1.8) = GameState.start_new_run(); мир пересобирает существующий
## хук ng_plus_started (world.gd), вместе со сценой умирает и эта панель.
## Паттерн модалок Shop/SettingsMenu: свой GameState.input_locked + watchdog в
## _process + полное глотание ввода в _unhandled_input — до world-страховки
## «разлока при закрытых окнах hud» (world.gd::_unhandled_input) не доходит
## ничего, гейты _hotbar_allowed()/E/зелье (input_locked) закрыты модально.
## Закрыта с момента создания — смоук-мира не касается. Закрытие — это смерть
## узла при перезаборе мира: in-scene close() отсутствует by design, висячий
## lock снимает _exit_tree (паттерн Shop).
## Поля — минимум §1.9, новых хранимых полей нет: волна ng_wave(), достигнутый
## уровень, всего Пепла (meta.ash), номер забега = ach.n.deaths + 1 (счётчик
## инкрементит start_new_run, здесь он ещё «до этой смерти»).

static var I: RunSummary        # синглтон; назначает сам себя в _enter_tree

var root: Control               # полноэкранный корень панели; visible = «открыта»
var dim: ColorRect              # затемнение мира; клики мимо окна глушатся
var panel: PanelContainer
var stats_lbl: Label
var rekindle_btn: Button
var ui_frame_tex: Texture2D     # 9-slice рамка (assets/ui/panel_frame.png), опц.
var _holds_lock := false        # input_locked сейчас принадлежит нам, а не кому-то ещё
var _finalized := false         # start_new_run ровно один раз (кнопка и Esc)

func _enter_tree() -> void:
	if I == null:
		I = self

func _exit_tree() -> void:
	# Выход из сцены с открытой панелью (перезабор мира после start_new_run)
	# не должен оставлять висячий lock: снимаем, только если lock был наш и
	# поверх не стоит чужое окно (паттерн Shop).
	_release_lock()
	if I == self:
		I = null

func _ready() -> void:
	layer = 6  # выше HUD (1) и модалок Shop/Journal (5), ниже фейда переходов (10)
	if ResourceLoader.exists("res://assets/ui/panel_frame.png"):
		ui_frame_tex = load("res://assets/ui/panel_frame.png")
	_build()

# --- статические обёртки ---

## Открытие из чистого конца диалога (advance() закрывает панель и снимает свой
## lock ДО колбэков — состояние свободно). Повторный open поверх открытой панели
## идемпотентен (_set_open).
static func open() -> void:
	if I == null or I.root == null:
		return
	if I._busy():  # чужой диалог/модалка/lock — не открываемся (как Shop)
		GameAudio.sfx("ui_deny")
		return
	I._set_open(true)

static func is_open() -> bool:
	return I != null and I.root != null and I.root.visible

# --- построение панели (паттерн Shop) ---

func _build() -> void:
	var th := Theme.new()
	th.default_font_size = 8
	root = Control.new()
	root.name = "RunSummaryRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false  # скрыта с момента создания — смоук-мира не касается
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # скрытая мышь не ест
	add_child(root)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.theme = th
	if ui_frame_tex != null:
		panel.add_theme_stylebox_override("panel", _ui_frame_style(6.0))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var head := Label.new()
	head.text = "Забег окончен"
	head.add_theme_font_size_override("font_size", 10)
	head.add_theme_color_override("font_color", Color(0.85, 0.45, 0.25))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	stats_lbl = Label.new()
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	vb.add_child(stats_lbl)
	rekindle_btn = Button.new()
	rekindle_btn.text = "Вспыхнуть заново (Esc)"
	rekindle_btn.pressed.connect(_rekindle)
	vb.add_child(rekindle_btn)

## Тёмная деревянная рамка (тот же ассет и приёмы, что Shop/hud.gd).
func _ui_frame_style(content: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = ui_frame_tex
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

# --- открытие/снимок итогов ---

func _set_open(v: bool) -> void:
	if root.visible == v:
		return
	root.visible = v
	# открытая панель ловит мышь (мир под ней мёртв и не нужен); скрытая — IGNORE
	root.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
	GameAudio.sfx("ui_confirm" if v else "ui_click")
	if v:
		_acquire_lock()
		_refresh()

## Снимок итогов §1.9 — в момент открытия (start_new_run ещё не вызывался).
## Значения из сейва — каноническим парсером GameState._num (trust-boundary,
## R5-принцип); level/ng_wave типизированы в самом GameState.
func _refresh() -> void:
	var ash := GameState._num(GameState.flags.get("meta.ash", 0), 0)
	var deaths := GameState._num(GameState.flags.get("ach.n.deaths", 0), 0)
	stats_lbl.text = "Волна: %d\nДостигнутый уровень: %d\nВсего пепла: %d\nЗабег: #%d" % [
		GameState.ng_wave(), GameState.level, ash, deaths + 1,
	]

## Кнопка и Esc — одно и то же (§1.8). Идемпотентна: ng_plus_started триггерит
## отложенный перезабор сцены, второй сигнал не проходит (_finalized).
func _rekindle() -> void:
	if _finalized:
		return
	_finalized = true
	GameAudio.sfx("ui_confirm")
	GameState.start_new_run()

# --- лок и владение вводом (паттерн Shop/SettingsMenu) ---

func _acquire_lock() -> void:
	# Вызываемся только из состояния «не занято» (статический open() проверил
	# _busy): lock ставится поверх свободной игры и принадлежит теперь нам.
	GameState.input_locked = true
	_holds_lock = true

## Вернуть lock, который поставили мы. Если поверх успело встать чужое окно и
## lock «перешёл» к нему — не трогаем: снимет сам владелец.
func _release_lock() -> void:
	if _holds_lock and not _ui_windows_open():
		GameState.input_locked = false
	_holds_lock = false

## Страховка (паттерн Shop): если внешний код снял lock (безусловный разлок в
## конце диалога) — возвращаем, пока панель открыта и чужие окна чисты.
func _process(_delta: float) -> void:
	if root != null and root.visible and not GameState.input_locked and not _ui_windows_open():
		GameState.input_locked = true
		_holds_lock = true

## Чужие окна у родителя-world: диалог/модалка hud, журнал. Слабая типизация:
## hud через get(), без предположений о порядке создания узлов (паттерн Shop).
func _ui_windows_open() -> bool:
	var p := get_parent()
	if p == null:
		return false
	var h = p.get("hud")
	if h == null or not is_instance_valid(h):
		return false
	if h.has_method("is_dialog_open") and h.is_dialog_open():
		return true
	if h.has_method("is_modal_open") and h.is_modal_open():
		return true
	for c in p.get_children():
		if c is Journal and c.is_open():
			return true
	return false

## Открытию мешает любой чужой владелец ввода.
func _busy() -> bool:
	return GameState.input_locked or _ui_windows_open()

# --- ввод ---

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return  # закрытая панель не перехватывает ничего: Esc/J/всё остальное — игре
	# открытая панель модальна по вводу: клавиши мира (скиллы, зелье, E, F5/F9)
	# гасим, Esc = кнопка «Вспыхнуть заново» (§1.8). Глотаем всё, включая
	# release-события: до world-страховки не доходит ничего, собственный lock
	# не «мигает» и не снимается чужими ветками world.gd.
	if event.is_action_pressed("ui_cancel"):
		_rekindle()
	get_viewport().set_input_as_handled()
