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
##
## Вкладки (P1.5, docs/RETENTION_NG_PLUS.md §2): «Квесты» / «Достижения» /
## «Таланты» (CONTRACT_TALENTS §4).
## Самих данных в журнале нет — const-таблица AchvCatalog (канон §2),
## статусы читаются из GameState: флаг "ach.<id>" (в JSON-сейве может лежать
## float — сверяем через != null и float > 0), прогресс-подсказки из
## "ach.n.<kind>" / int-полей / размеров контейнеров GameState (см. _ach_cur).
## Журнал остаётся НЕМОДАЛЬНЫМ: ввода не берёт, J-гейт при открытом Shop
## (75b5b69) не трогает; переключение вкладок — мышь или Tab (только когда
## журнал открыт). Закрытая вкладка достижений ничего не опрашивает.

const TICK := 0.35  # сек между аудитами реестра квестов (автостарт/завершение)
const TAB_QUESTS := 0
const TAB_ACHV := 1
const TAB_TALENTS := 2  # «Древо талантов» (CONTRACT_TALENTS §4), после достижений
const TAB_TITLES := ["Квесты", "Достижения", "Таланты"]

var _open := false
var _dirty := true
var _tick := 0.0
var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _frame_tex: Texture2D
var _tab := TAB_QUESTS
var _tab_btns: Array = []        # Button на вкладку (стилизация flat-тегми)
var _ach_list: VBoxContainer     # список 12 строк достижений (вкладка TAB_ACHV)
var _ach_sig := -1               # подпись состояния ачивок: анлоки + счётчики
var _tal_list: VBoxContainer     # колонки веток талантов (вкладка TAB_TALENTS)
var _tal_sig := -1               # подпись: свободные очки + вложенные (уровень/траты)

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
	# t24: окно больше (было 320x220; юзер: «текст залезает на рамки, окно больше»)
	# нижний край 318 < хотбара (320) — клики скиллов при открытом журнале живы
	_panel.offset_left = -200
	_panel.offset_right = 200
	_panel.offset_top = -138
	_panel.offset_bottom = 138
	if _frame_tex != null:
		# контент-марджин 28: за рисуемой бумажной кромкой 24 + отдушина 4 (аутлайн текста 3)
		_panel.add_theme_stylebox_override("panel", _ui_frame_style(28.0))
	# волна 3 «Живая стилистика»: бумажная кромка пергамента по краю окна —
	# ПЕРВЫМ ребёнком PanelContainer (под контентом); t24: вместо NinePatchRect
	# (256-текстура, марджин 1:1 -> кромка даунскейлена 4x и растянута анизотропно,
	# юзер: «размытый и сильно растянутый фон») — PaperEdge: масштабированный
	# 9-patch с независимыми src/dst марджинами от нативной 999-текстуры.
	# Позиции текста/списков не сдвигаются: это фон, mouse IGNORE.
	if ResourceLoader.exists("res://assets/ui/decor_paper_edge.png"):
		var paper := PaperEdge.new()
		paper.name = "PaperEdge"
		paper.tex = load("res://assets/ui/decor_paper_edge.png")
		paper.src_margin = 95.0  # реальный край рамки: на срезе alpha=0 (t24_measure)
		paper.dst_margin = 24.0
		paper.set_anchors_preset(Control.PRESET_FULL_RECT)
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_panel.add_child(paper)
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
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for i in TAB_TITLES.size():
		var tb := Button.new()
		tb.flat = true
		tb.text = String(TAB_TITLES[i])
		tb.focus_mode = Control.FOCUS_NONE  # мышиные: клавиатурный фокус не воруем
		tb.add_theme_font_size_override("font_size", 8)
		tb.pressed.connect(select_tab.bind(i))
		tabs.add_child(tb)
		_tab_btns.append(tb)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(344, 164)  # t24: 400-2*28; min панели ровно 400x276
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_ach_list = VBoxContainer.new()
	_ach_list.add_theme_constant_override("separation", 4)
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_list.visible = false
	_scroll.add_child(_ach_list)
	_tal_list = VBoxContainer.new()
	_tal_list.add_theme_constant_override("separation", 4)
	_tal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tal_list.visible = false
	_scroll.add_child(_tal_list)
	var hint := _mk_label("J / Esc — закрыть, Tab — вкладка", 7, Color(1, 1, 1, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(hint)
	_panel.theme = th
	_root.add_child(_panel)
	_tab_style()
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
	# вкладка достижений живая: анлок/счётчик могли измениться при открытом
	# журнале (покупка у Гриима, варка) — дешёвая подпись вместо пересборки вслепую
	if _open and _tab == TAB_ACHV and _ach_sig != _ach_sig_calc():
		_rebuild_achv()
	# вкладка талантов живая: уровень вырос (leveled_up не дёргает quest_changed),
	# NG+ сбросил tal.* — подпись «очки+вложения» дёшеве пересборки вслепую
	if _open and _tab == TAB_TALENTS and _tal_sig != _tal_sig_calc():
		_rebuild_talents()

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
	for b in _tab_btns:  # close() пряча subtree оставил их в IGNORE — вернуть клик
		(b as Button).mouse_filter = Control.MOUSE_FILTER_STOP
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

func select_tab(i: int) -> void:
	if i < 0 or i >= TAB_TITLES.size() or i == _tab:
		return
	_tab = i
	_tab_style()
	_list.visible = _tab == TAB_QUESTS
	_ach_list.visible = _tab == TAB_ACHV
	_tal_list.visible = _tab == TAB_TALENTS
	_scroll.scroll_vertical = 0
	if _tab == TAB_ACHV:
		_rebuild_achv()  # свежие статусы на каждый вход во вкладку
	if _tab == TAB_TALENTS:
		_rebuild_talents()  # свежие ранги/очки на каждый вход + мышь на кнопки

func _tab_style() -> void:
	for i in _tab_btns.size():
		var b: Button = _tab_btns[i]
		b.add_theme_color_override(
			"font_color", Color(1, 0.9, 0.55) if i == _tab else Color(1, 1, 1, 0.45))
		b.add_theme_color_override(
			"font_hover_color", Color(1, 0.9, 0.55) if i == _tab else Color(1, 1, 1, 0.7))

# --- ввод ---

## Physical-код: буква на физической клавише, раскладка (ру/англ) не важна.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo or not event.pressed:
		return
	if event.physical_keycode == KEY_J:
		if _open:
			close()
			get_viewport().set_input_as_handled()
		elif not GameState.input_locked and not Shop.is_open():  # диалог/модалка/лавка — журнал не открываем
			open()
			get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_TAB and _open:
		# цикл по всем вкладкам: Квесты -> Достижения -> Таланты -> Квесты
		select_tab((_tab + 1) % TAB_TITLES.size())
		get_viewport().set_input_as_handled()

# --- построение списка квестов ---

func _rebuild() -> void:
	if _tab == TAB_ACHV:
		_rebuild_achv()
		return
	if _tab == TAB_TALENTS:
		_rebuild_talents()
		return
	for ch in _list.get_children():
		ch.queue_free()
	# JC-4 (QA-4): журнал рисует сюжетки только реально взятые (elder_quest /
	# cave_state >= 1). Слой данных не тронут: visible_in_journal — канон HUD и
	# стендов (qa_q5 A1 «elder+cave видны с нуля») — правка только рендера:
	# у нового героя журнал обязан пустовать, иначе подсказка ниже мертва,
	# а «Гром» спойлерит пещеру до Геральда. «Слаймы» и «Ведьма» уже gate'ятся
	# слоем данных (slime_quest / ashen.intro_seen).
	var entries: Array = []
	for raw_v in QuestsData.entries(GameState):
		var ev: Dictionary = raw_v
		match String(ev.get("id", "")):
			"elder":
				if int(GameState.elder_quest) < 1:
					continue
			"cave":
				if int(GameState.cave_state) < 1:
					continue
		entries.append(ev)
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
		d.custom_minimum_size = Vector2(330, 0)  # t24: +12 min ширины скролла < 344 (иначе панель распухнет)
		_list.add_child(d)
		for raw_tg in e.get("targets", []):
			var tg: Dictionary = raw_tg
			var done := bool(tg.get("done", false))
			var row := _mk_label("    %s %s  %d/%d" % ["[x]" if done else "[ ]", String(tg.get("label", "")), int(tg.get("cur", 0)), int(tg.get("need", 1))], 7, Color(0.55, 0.85, 0.5) if done else Color(1, 1, 1, 0.85))
			_list.add_child(row)

# --- построение вкладки достижений (P1.5) ---

## Статус ачивки: флаг "ach.<id>". В JSON-сейве значение могло стать float —
## поэтому «!= null и float(...) > 0», а не bool()/сравнение с 1.
func _ach_unlocked(id: String) -> bool:
	var v: Variant = GameState.flags.get("ach." + id)
	if v == null:
		return false
	return float(v) > 0.0

## Текущее значение прогресс-подсказки по спецификации из AchvCatalog:
## "n.<kind>" — счётчик "ach.n.<kind>" (голый "<kind>" трактуется так же),
## "field:<p>" — int-поле GameState, "size:<p>" — размер поля-контейнера.
func _ach_cur(spec: String) -> int:
	if spec.begins_with("n."):
		return int(GameState.flags.get("ach." + spec, 0))
	if spec.begins_with("field:"):
		return int(GameState.get(spec.trim_prefix("field:")))
	if spec.begins_with("size:"):
		var v: Variant = GameState.get(spec.trim_prefix("size:"))
		if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY:
			return v.size()
		return 0
	return int(GameState.flags.get("ach.n." + spec, 0))

## Дешёвая подпись состояния (для живого обновления вкладки при открытом
## журнале): количество анлоков и сумма прогрессов, ограниченных целью.
func _ach_sig_calc() -> int:
	var s := 0
	for raw_c in AchvCatalog.ITEMS:
		var c: Dictionary = raw_c
		if _ach_unlocked(String(c.get("id", ""))):
			s += 1000
		var spec := String(c.get("counter", ""))
		if spec != "":
			s += mini(_ach_cur(spec), int(c.get("goal", 0)) + 1)
	return s

func _rebuild_achv() -> void:
	_ach_sig = _ach_sig_calc()
	for ch in _ach_list.get_children():
		ch.queue_free()
	for raw_c in AchvCatalog.ITEMS:
		var c: Dictionary = raw_c
		var id := String(c.get("id", ""))
		var unlocked := _ach_unlocked(id)
		# палитра как у квестов: выполнено — тёплое золото, нет — приглушённый
		var head_col := Color(1, 0.9, 0.55) if unlocked else Color(0.6, 0.58, 0.54)
		var head := _mk_label("%s %s — %s%s" % [
			"[x]" if unlocked else "[ ]",
			String(c.get("name", id)),
			String(c.get("reward", "")),
			"  ✓ закрыто" if unlocked else "",
		], 8, head_col)
		_ach_list.add_child(head)
		var d := _mk_label(String(c.get("desc", "")), 7,
			Color(0.85, 0.8, 0.7, 0.7) if unlocked else Color(0.85, 0.8, 0.7, 0.4))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(330, 0)  # t24: +12 min ширины скролла < 344 (иначе панель распухнет)
		_ach_list.add_child(d)
		var spec := String(c.get("counter", ""))
		if spec != "":
			if unlocked:
				# live-счётчики (campfires/chests/...) обнуляются сменой круга,
				# а анлок вечен: «0/3» рядом с «✓ закрыто» врал бы игроку (Q5)
				_ach_list.add_child(_mk_label("    %s: ✓" % String(c.get("hint", "Прогресс")),
					7, Color(0.55, 0.85, 0.5)))
			else:
				var cur := _ach_cur(spec)
				var goal := int(c.get("goal", 0))
				_ach_list.add_child(_mk_label("    %s: %d/%d" % [String(c.get("hint", "Прогресс")), cur, goal],
					7, Color(0.55, 0.85, 0.5) if cur >= goal else Color(1, 1, 1, 0.6)))

# --- построение вкладки талантов (CONTRACT_TALENTS §4) ---

## Дешёвая подпись состояния талантов: свободные очки и вложения. Уровень вырос
## (очки) или куплен ранг (и то и другое) — подпись меняется, список пересобирается.
func _tal_sig_calc() -> int:
	return GameState.tal_points() * 64 + GameState.tal_spent()

## Клик по узлу: трата очка в GameState.try_spend_talent (звук/отказ — внутри).
## Журнал НЕМОДАЛЕН, а input_locked гасит его только следующим тиком _process —
## поэтому клики сквозь открывшийся диалог/модалку отсекаем прямо здесь.
func _on_tal_clicked(id: String) -> void:
	if GameState.input_locked:
		return
	GameState.try_spend_talent(id)
	_rebuild_talents()  # заголовок «Очки» и подсветка доступных — сразу

## Три колонки-ветки (Сила/Лес/Пепел), порядок узлов — порядок NODES (§1).
## Узел = кнопка "[название (ранг/max)]" + под ней desc; недоступный (нет очков
## или кап ранга) — затенение той же палитрой, что закрытые ачивки.
func _rebuild_talents() -> void:
	_tal_sig = _tal_sig_calc()
	for ch in _tal_list.get_children():
		ch.queue_free()
	var pts := GameState.tal_points()
	_tal_list.add_child(_mk_label("Очки: %d" % pts, 9, Color(1, 0.9, 0.55)))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 6)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tal_list.add_child(cols)
	for raw_b in Talents.BRANCHES:
		var bkey := String(raw_b)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		col.add_child(_mk_label(String(Talents.BRANCHES[bkey]), 8, Color(1, 0.9, 0.55)))
		for raw_n in Talents.NODES:
			var id := String(raw_n)
			var nd: Dictionary = Talents.NODES[raw_n]
			if String(nd.get("branch", "")) != bkey:
				continue
			var mx := Talents.max_of(id)
			var r := GameState.tal_rank(id)
			var avail := r < mx and pts > 0
			# цвета — существующая палитра журнала: открытый синий квестов,
			# приглушённый закрытых ачивок, тёплое золото заголовков
			var btn_col := Color(0.7, 0.88, 1.0) if avail else Color(0.6, 0.58, 0.54)
			var b := Button.new()
			b.flat = true
			# Фидбек: «у талантов нет иконок» — строка узла = procedural-иконка
			# 8x8 (рисуется 16x16, nearest — как skill_icons в хотбаре) + имя +
			# ранг; палитра/стиль — как вкладка достижений (золото/приглушённый).
			b.icon = Talents.icon_texture(id)
			b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			b.text = "%s %d/%d" % [String(nd.get("name", id)), r, mx]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # t24: длинное имя — перенос, не наезд на рамку
			b.focus_mode = Control.FOCUS_NONE  # клавиатурный фокус не воруем
			b.add_theme_font_size_override("font_size", 8)
			b.add_theme_color_override("font_color", btn_col)
			b.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.55) if avail else btn_col)
			b.add_theme_color_override("font_pressed_color", btn_col)
			b.pressed.connect(_on_tal_clicked.bind(id))
			col.add_child(b)
			var d := _mk_label("— " + String(nd.get("desc", "")), 7,
				Color(0.85, 0.8, 0.7, 0.7) if avail else Color(0.85, 0.8, 0.7, 0.4))
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(100, 0)  # t24: колонка (344-2*6)/3 ≈ 110
			col.add_child(d)

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

## t24: «масштабируемый 9-patch» бумажной кромки. NinePatchRect не годился:
## его марджины рисуются 1:1 нативному размеру текстуры (256-текстура = кромка
## уже даунскейллена 4x из 1024-оригинала и на окне 2x ещё и растянута ~2.6x
## по горизонтальным рёбрам — «размытый/растянутый» фон). Здесь источник —
## нативная 999² текстура, срез строго по границе hole (alpha=0, t24_measure),
## углы — равномерным скеем, рёбра — только даунскейл (1.15–1.98 texel/win px).
## Центр не рисуем вовсе: он transparent и под ним stylebox панели.
class PaperEdge:
	extends Control
	var tex: Texture2D
	var src_margin := 95.0
	var dst_margin := 24.0

	func _draw() -> void:
		if tex == null:
			return
		var s := tex.get_size()
		var sm: float = minf(src_margin, minf(s.x, s.y) * 0.5 - 1.0)
		var dm: float = minf(dst_margin, minf(size.x, size.y) * 0.5 - 1.0)
		if sm <= 0.0 or dm <= 0.0 or size.x < 2.0 * dm or size.y < 2.0 * dm:
			return
		var iw: float = s.x - 2.0 * sm
		var ih: float = s.y - 2.0 * sm
		# углы — из нативных уголков, равномерный скей (без анаморфоза)
		draw_texture_rect_region(tex, Rect2(0, 0, dm, dm), Rect2(0, 0, sm, sm))
		draw_texture_rect_region(tex, Rect2(size.x - dm, 0, dm, dm), Rect2(s.x - sm, 0, sm, sm))
		draw_texture_rect_region(tex, Rect2(0, size.y - dm, dm, dm), Rect2(0, s.y - sm, sm, sm))
		draw_texture_rect_region(tex, Rect2(size.x - dm, size.y - dm, dm, dm),
			Rect2(s.x - sm, s.y - sm, sm, sm))
		# рёбра — единственной координатой вдоль ленты; оба фактора <=1 (даунскейл)
		var ew: float = size.x - 2.0 * dm
		var eh: float = size.y - 2.0 * dm
		draw_texture_rect_region(tex, Rect2(dm, 0, ew, dm), Rect2(sm, 0, iw, sm))
		draw_texture_rect_region(tex, Rect2(dm, size.y - dm, ew, dm), Rect2(sm, s.y - sm, iw, sm))
		draw_texture_rect_region(tex, Rect2(0, dm, dm, eh), Rect2(0, sm, sm, ih))
		draw_texture_rect_region(tex, Rect2(size.x - dm, dm, dm, eh), Rect2(s.x - sm, sm, sm, ih))
