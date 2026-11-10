class_name Journal
extends CanvasLayer
## Журнал приключений: накладное окно поверх HUD, открывается/закрывается
## клавишей J (physical_keycode — работает и в русской раскладке) и Esc.
##
## Создаётся ОДНОЙ строкой из world._ready() (см. интеграционный запрос):
## 	add_child(Journal.new())
## Никаких других правок world.gd/hud.gd не требуется.
##
## Мышь: когда журнал скрыт — не перехватывает НИЧЕГО (root и все Control
## в IGNORE, subtree скрыт). У CanvasLayer в Godot 4 нет mouse_filter,
## поэтому проброс мыши обеспечивается на уровне Control-корня (_root):
## скрыт => visible=false + все child в MOUSE_FILTER_IGNORE.
##
## Прогресс/автостарты не считает: тиком дёргает QuestsData.refresh() —
## единственный источник правды о квестах. Уведомления — через GameState.toast.

const TICK := 0.35  # сек между аудитами реестра квестов (автостарт/завершение)

var _open := false
var _dirty := true
var _tick := 0.0
var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _frame_tex: Texture2D

func _ready() -> void:
	layer = 5  # поверх HUD (у hud.gd слой 1, виньетка — внутри hud)
	# ассет-фолбэки как в hud.gd: без рамки окно остаётся на стиле темы
	if ResourceLoader.exists("res://assets/ui/panel_frame.png"):
		_frame_tex = load("res://assets/ui/panel_frame.png")
	else:
		push_warning("Нет ассета: assets/ui/panel_frame.png — журнал без рамки")
	var th := Theme.new()
	th.default_font_size = 8  # пиксельная сетка HUD: 8 px базовый шрифт
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -160
	_panel.offset_right = 160
	_panel.offset_top = -110
	_panel.offset_bottom = 110
	if _frame_tex != null:
		_panel.add_theme_stylebox_override("panel", _ui_frame_style(6.0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	_panel.add_child(vb)
	var title := _mk_label("Журнал приключений", 10, Color(1, 0.9, 0.55))
	vb.add_child(title)
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(1, 0.85, 0.5, 0.3)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sep)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(296, 160)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var hint := _mk_label("J / Esc — закрыть", 7, Color(1, 1, 1, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(hint)
	_panel.theme = th
	_root.add_child(_panel)
	close()  # стартовое состояние: скрыт, мышь насквозь
	GameState.quest_changed.connect(func() -> void: _dirty = true)

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	QuestsData.refresh(GameState)  # автостарты/завершения: только флаги "q." + toast
	if _open and GameState.input_locked:
		close()  # открылся диалог/модалка — журнал не должен мешать
	if _open and _dirty:
		_dirty = false
		_rebuild()

# --- публичный API ---

func open() -> void:
	if _open:
		return
	_open = true
	_dirty = false
	_rebuild()
	_root.visible = true
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.scroll_vertical = 0
	GameAudio.sfx("book")  # шелест страниц; нет файла — тихий пропуск

func close() -> void:
	_open = false
	_root.visible = false
	_set_mouse_pass(_root)  # скрыт => НИ ОДИН control не ловит мышь

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func is_open() -> bool:
	return _open

# --- ввод ---

## Physical-код: буква на физической клавише, раскладка (ру/англ) не важна.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo or not event.pressed:
		return
	if event.physical_keycode == KEY_J:
		if _open:
			close()
			get_viewport().set_input_as_handled()
		elif not GameState.input_locked:  # диалог/модалка — журнал не открываем
			open()
			get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()

# --- построение списка квестов ---

func _rebuild() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var entries: Array = QuestsData.entries(GameState)
	if entries.is_empty():
		_list.add_child(_mk_label("Записей пока нет.\nПоговори со старейшиной в деревне.", 8, Color(0.85, 0.8, 0.7, 0.8)))
		return
	for raw_e in entries:
		var e: Dictionary = raw_e
		var st := int(e.get("status", 0))
		var head: String = "[x] " if st == QuestsData.STATUS_DONE else "[ ] "
		var col := Color(0.55, 0.85, 0.5) if st == QuestsData.STATUS_DONE else (Color(1, 0.9, 0.55) if bool(e.get("story", false)) else Color(0.7, 0.88, 1.0))
		var t := _mk_label(head + String(e.get("title", "")), 8, col)
		_list.add_child(t)
		var d := _mk_label(String(e.get("desc", "")), 7, Color(0.85, 0.8, 0.7, 0.7))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(280, 0)
		_list.add_child(d)
		for raw_tg in e.get("targets", []):
			var tg: Dictionary = raw_tg
			var done := bool(tg.get("done", false))
			var row := _mk_label("    %s %s  %d/%d" % ["[x]" if done else "[ ]", String(tg.get("label", "")), int(tg.get("cur", 0)), int(tg.get("need", 1))], 7, Color(0.55, 0.85, 0.5) if done else Color(1, 1, 1, 0.85))
			_list.add_child(row)

# --- мелкие хелперы стиля (в тон hud.gd) ---

func _mk_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Скрытый журнал мышь не перехватывает вовсе: весь subtree в IGNORE.
func _set_mouse_pass(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_set_mouse_pass(c)

## Клон _ui_frame_style из hud.gd: Kenney 9-slice рамка 32x32, край 4 px.
func _ui_frame_style(content: float) -> StyleBoxTexture:
	if _frame_tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = _frame_tex
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
