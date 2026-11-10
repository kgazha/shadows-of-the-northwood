class_name SettingsMenu
extends CanvasLayer
## Меню настроек «Теней Северного Леса»: открывать/закрывать клавишей Esc
## (физический KEY_ESCAPE — клавиша в игре была свободна: в скриптах нет ни
## одного KEY_*, диалоги листаются E/ЛКМ/ui_accept, не Esc). Узел создаёт
## world._ready (интеграционный запрос — отдельным хунком); стартует СКРЫТЫМ,
## в скрытом виде mouse_filter=IGNORE — «невидимое стекло» над игрой не остаётся.
##
## Громкости: слайдеры «Музыка»/«Эффекты» 0–100 %, инициализация из GameAudio.I,
## live-применение set_volumes() при каждом движении — GameAudio сам персистит
## user://audio_cfg.json. Своего user://settings.json НЕТ: своих полей пока нет
## (появятся — заведём файл здесь же, по образцу GameAudio._save_cfg).
##
## Тумблер «Ход по правому клику» написан СТРОГО против внешнего контракта
## параллельной фичи: ClickMove.is_on() -> bool, ClickMove.set_on(v: bool).
## Файла может не быть — preload запрещён (несуществующий preload ломает
## компиляцию всего скрипта), только ResourceLoader.exists + load в момент
## открытия. Порядок поиска: автозагрузка /root/ClickMove -> скрипт с
## class_name ClickMove и статическими методами. Ничего не найдено — строка
## скрыта (никаких падений и SCRIPT ERROR).
##
## Перехват ввода пока меню открыто — осознанно модалный режим, как штатные
## диалоги/модалка выбора класса (меню НЕ на весь экран, но мир за ним
## замирает). Причина: WASD/кувырок/атака в player.gd полляются
## (Input.get_vector / is_action_pressed в _physics_process), поэтому
## set_input_as_handled над ними бессилен — событие «съедено», а опрос всё
## равно читает зажатую клавишу. Единственный штатный рычаг в игре —
## GameState.input_locked (ранний return в player.gd гейтит ход, кувырок,
## атаку; world.gd гейтит E/F5/F9/Q/1-4; мобов паузит). Надёжность возврата:
## * поверх чужих окон не открываемся (_busy): диалог, модалка класса, фейд
##   перехода или любой внешний input_locked -> Esc молча отказывает (ui_deny),
##   lock нам «чужой» не достаётся и close() всегда снимает ровно свой;
## * все нажатия клавиш меню проглатывает в _input (он раньше GUI и
##   _unhandled_input), мышь вне панели гасит полноэкранная затемняющая вуаль
##   MOUSE_FILTER_STOP — до world._unhandled_input не доходит ничего, его
##   софтлок-страховка (снимает lock при закрытых окнах) наше меню не разлокает;
## * _process() добирает lock, если экзотическое событие (например, курсор
##   закрай окна) всё же просочился и страховка его сняла;
## * close() и _exit_tree() возвращает lock гарантированно.
## Побочный эффект (как у диалогов): мобы замирают — меню = пауза. Это и есть
## ответ на «WASD/атака за меню не должны проходить»: полностью выполнить его
## без GameState.input_locked при polled-вводе невозможно, а блокировать вовсе
## ничего — означало бы стрелять себя по слайдерам и уходить из-под меню в бой.
## Клавиатурная навигация по меню отключена (фокус FOCUS_NONE, клавиши
## глотаются) — меню мышиное, как модалка создания героя; Esc и клик мимо
## панели — закрыть.

const CM_PATH := "res://scripts/click_move.gd"
const CM_CLASS := "ClickMove"
const MM_PATH := "res://scripts/minimap.gd"
const MM_CLASS := "Minimap"
const FRAME_PATH := "res://assets/ui/panel_frame.png"  # та же Kenney 9-slice рамка, что у окон hud

var dim: ColorRect             # полноэкранная вуаль: открыта -> STOP, скрыта -> IGNORE
var panel: PanelContainer
var mus_slider: HSlider
var sfx_slider: HSlider
var mus_pct: Label
var sfx_pct: Label
var cm_row: HBoxContainer      # строка тумблера ПКМ-хода; нет ClickMove -> скрыта
var cm_btn: Button
var _cm_api                    # ClickMove: автозагрузка-узел либо GDScript со статиками
var mm_row: HBoxContainer      # строка тумблера миникарты; нет Minimap -> скрыта
var mm_btn: Button
var _mm_api                    # Minimap: GDScript со статиками (паттерн _cm_api)
var sv_export: LineEdit        # «Сейв»: readonly-строка экспорта (выделение+копия)
var sv_import: LineEdit        # «Сейв»: поле вставки строки импорта
var sv_apply_btn: Button
var sv_msg: Label              # тост результата прямо в секции
var _open := false

func _ready() -> void:
	layer = 20                   # выше hud (1) и фейда переходов (10)
	_build()
	_set_open(false)             # контракт: старт скрытым + мышь насквозь

# --- открытие / закрытие ---

func open() -> void:
	if _open:
		return
	if _busy():                  # чужой диалог/модалка/фейд/lock — не открываемся
		GameAudio.sfx("ui_deny")
		return
	_sync_audio()
	_refresh_click_move()        # фича могла «прилететь» между открытиями — перепроверка
	_refresh_minimap()           # фича могла «прилететь» между открытиями — перепроверка
	_set_open(true)
	GameState.input_locked = true
	GameAudio.sfx("ui_click")

func close() -> void:
	if not _open:
		return
	_set_open(false)
	_release_lock()
	GameAudio.sfx("ui_click")

func is_open() -> bool:
	return _open

func _set_open(o: bool) -> void:
	_open = o
	visible = o
	# Скрыто: мышь насквозь (self.visible и так глушит поддерево в GUI-хит-тесте,
	# но фильтры ставим явно — по контракту «mouse_filter=IGNORE когда скрыт»,
	# и узел, оставленный видимым по чужой прихоти, не должен остаться стеклом).
	dim.mouse_filter = Control.MOUSE_FILTER_STOP if o else Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if o else Control.MOUSE_FILTER_IGNORE

## Вернуть lock, который поставило меню. Если поверх успел открыться диалог
## (отложенный колбэк) и lock перешёл к нему — не трогаем: снимет сам advance().
func _release_lock() -> void:
	if GameState.input_locked and not _ui_windows_open():
		GameState.input_locked = false

## Страховка: world._unhandled_input при первом же просочившемся событии снимает
## lock (софтлок-страховка game-кода). Возвращаем, пока меню открыто и окна чисты.
func _process(_delta: float) -> void:
	if _open and not GameState.input_locked and not _ui_windows_open():
		GameState.input_locked = true

func _exit_tree() -> void:
	if _open:
		_open = false
		visible = false
		_release_lock()

# --- ввод ---

func _input(event: InputEvent) -> void:
	# _input идёт раньше GUI и _unhandled_input: Esc перехватываем первыми.
	if not (event is InputEventKey) or event.echo:
		return
	if _open:
		# Меню мышиное: глотаем ВСЕ клавиатурные события, включая release:
		# дошедшее до world-страховки release-событие снимало бы наш
		# input_locked до перелока в _process (мигание блокировки).
		# Исключение — редакторы текста секции «Сейв»: пока LineEdit в фокусе,
		# пропускаем клавиши к GUI (набор/Ctrl+V/Ctrl+C). Просочившееся release
		# безопасно: lock держит перелок в _process (страховка уже в контракте).
		var fo := get_viewport().gui_get_focus_owner()
		if not (fo is LineEdit and is_ancestor_of(fo)):
			if event.pressed and event.physical_keycode == KEY_ESCAPE:
				close()
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.physical_keycode == KEY_ESCAPE:
			close()  # Esc из поля — закрыть меню (по контракту Esc всегда закрывает)
			get_viewport().set_input_as_handled()
			return
		return
	if event.pressed and event.physical_keycode == KEY_ESCAPE:
		if not _busy():
			open()
			get_viewport().set_input_as_handled()
		return

## Клик мимо панели — закрыть (вуаль под панелью, по панели клики не проходят).
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close()

# --- сборка панели (стиль как у окон hud: тема 8 px, Kenney-рамка 9-slice) ---

func _build() -> void:
	var th := Theme.new()
	th.default_font_size = 8
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.theme = th
	var frame_tex: Texture2D = null
	if ResourceLoader.exists(FRAME_PATH):
		frame_tex = load(FRAME_PATH)
	else:
		push_warning("Нет ассета: assets/ui/panel_frame.png — панель настроек без рамки")
	if frame_tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = frame_tex
		sb.region_rect = Rect2(0, 0, 32, 32)
		sb.texture_margin_left = 4
		sb.texture_margin_top = 4
		sb.texture_margin_right = 4
		sb.texture_margin_bottom = 4
		sb.content_margin_left = 10
		sb.content_margin_top = 8
		sb.content_margin_right = 10
		sb.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	center.add_child(panel)

	var title := Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)

	# строка «Музыка»: подпись — слайдер 0..100 — проценты
	var row_m := HBoxContainer.new()
	row_m.add_theme_constant_override("separation", 6)
	row_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab_m := _row_label("Музыка")
	mus_slider = HSlider.new()
	mus_slider.min_value = 0.0
	mus_slider.max_value = 100.0
	mus_slider.step = 1.0
	mus_slider.custom_minimum_size = Vector2(120, 10)
	mus_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mus_slider.focus_mode = Control.FOCUS_NONE  # меню мышиное — рамка фокуса не нужна
	mus_slider.value_changed.connect(func(_v: float) -> void: _apply())
	mus_pct = _row_label("")
	mus_pct.custom_minimum_size = Vector2(26, 0)
	row_m.add_child(lab_m)
	row_m.add_child(mus_slider)
	row_m.add_child(mus_pct)
	vb.add_child(row_m)

	var row_s := HBoxContainer.new()
	row_s.add_theme_constant_override("separation", 6)
	row_s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab_s := _row_label("Эффекты")
	sfx_slider = HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 100.0
	sfx_slider.step = 1.0
	sfx_slider.custom_minimum_size = Vector2(120, 10)
	sfx_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sfx_slider.focus_mode = Control.FOCUS_NONE
	sfx_slider.value_changed.connect(func(_v: float) -> void: _apply())
	sfx_pct = _row_label("")
	sfx_pct.custom_minimum_size = Vector2(26, 0)
	row_s.add_child(lab_s)
	row_s.add_child(sfx_slider)
	row_s.add_child(sfx_pct)
	vb.add_child(row_s)

	# тумблер ПКМ-хода — виден, только когда фича ClickMove реально в проекте
	cm_row = HBoxContainer.new()
	cm_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cm_btn = Button.new()
	cm_btn.toggle_mode = true
	cm_btn.focus_mode = Control.FOCUS_NONE
	cm_btn.add_theme_font_size_override("font_size", 8)
	cm_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cm_btn.toggled.connect(_on_cm_toggled)
	cm_row.add_child(cm_btn)
	cm_row.visible = false
	vb.add_child(cm_row)

	# тумблер миникарты — виден, только когда фича Minimap реально в проекте
	mm_row = HBoxContainer.new()
	mm_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm_btn = Button.new()
	mm_btn.toggle_mode = true
	mm_btn.focus_mode = Control.FOCUS_NONE
	mm_btn.add_theme_font_size_override("font_size", 8)
	mm_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	mm_btn.toggled.connect(_on_mm_toggled)
	mm_row.add_child(mm_btn)
	mm_row.visible = false
	vb.add_child(mm_row)

	# --- «Сейв»: переносной бэкап (SaveVault; RETENTION_NG_PLUS §5.2) ---
	var sv_title := Label.new()
	sv_title.text = "Сейв"
	sv_title.add_theme_font_size_override("font_size", 9)
	sv_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	sv_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sv_title)

	var row_e := HBoxContainer.new()
	row_e.add_theme_constant_override("separation", 6)
	row_e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var exp_btn := Button.new()
	exp_btn.text = "Экспорт"
	exp_btn.focus_mode = Control.FOCUS_NONE
	exp_btn.add_theme_font_size_override("font_size", 8)
	exp_btn.tooltip_text = "Строка сейва в это поле и в буфер обмена (если площадка отдаёт буфер)."
	exp_btn.pressed.connect(_on_sv_export)
	sv_export = LineEdit.new()
	sv_export.editable = false           # readonly: мышь выделяет, Ctrl+C копирует
	sv_export.custom_minimum_size = Vector2(150, 0)
	sv_export.add_theme_font_size_override("font_size", 8)
	row_e.add_child(exp_btn)
	row_e.add_child(sv_export)
	vb.add_child(row_e)

	var row_i := HBoxContainer.new()
	row_i.add_theme_constant_override("separation", 6)
	row_i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv_import = LineEdit.new()
	sv_import.placeholder_text = "Вставь сейв..."
	sv_import.custom_minimum_size = Vector2(150, 0)
	sv_import.add_theme_font_size_override("font_size", 8)
	sv_apply_btn = Button.new()
	sv_apply_btn.text = "Применить"
	sv_apply_btn.focus_mode = Control.FOCUS_NONE
	sv_apply_btn.add_theme_font_size_override("font_size", 8)
	sv_apply_btn.pressed.connect(_on_sv_import)
	row_i.add_child(sv_import)
	row_i.add_child(sv_apply_btn)
	vb.add_child(row_i)

	sv_msg = Label.new()
	sv_msg.add_theme_font_size_override("font_size", 7)
	sv_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sv_msg)

	var reset_btn := Button.new()
	reset_btn.text = "Сброс"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_font_size_override("font_size", 8)
	reset_btn.tooltip_text = "Громкости по умолчанию (%d %%). Ход по ПКМ не трогаем — его умолчание принадлежит ClickMove." % int(GameAudio.DEF_VOL * 100.0)
	reset_btn.pressed.connect(_on_reset)
	vb.add_child(reset_btn)

	var hint := Label.new()
	hint.text = "Esc или клик мимо — закрыть"
	hint.add_theme_font_size_override("font_size", 7)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint)

func _row_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# --- громкости ---

## Инициализация слайдеров из синглтона (I мог ещё не родиться — фолбэк дефолт).
## set_value_no_signal: открытие меню не должно писать audio_cfg.json «на ровном месте».
func _sync_audio() -> void:
	var mv := GameAudio.DEF_VOL
	var sv := GameAudio.DEF_VOL
	if GameAudio.I != null:
		mv = GameAudio.I.music_vol
		sv = GameAudio.I.sfx_vol
	mus_slider.set_value_no_signal(float(roundi(mv * 100.0)))
	sfx_slider.set_value_no_signal(float(roundi(sv * 100.0)))
	_sync_pct_labels()

func _sync_pct_labels() -> void:
	mus_pct.text = "%d%%" % int(mus_slider.value)
	sfx_pct.text = "%d%%" % int(sfx_slider.value)

## Live-применение: шины + персист делает GameAudio.set_volumes (user://audio_cfg.json).
func _apply() -> void:
	_sync_pct_labels()
	if GameAudio.I != null:
		GameAudio.I.set_volumes(mus_slider.value / 100.0, sfx_slider.value / 100.0)

func _on_reset() -> void:
	var d := GameAudio.DEF_VOL * 100.0
	mus_slider.value = d   # value_changed -> _apply
	sfx_slider.value = d
	_apply()               # значения могли уже быть дефолтными — сигнал бы молчал
	GameAudio.sfx("ui_confirm")

# --- тумблер «Ход по правому клику» (внешний контракт ClickMove) ---

## Резолв против контракта по порядку: автозагрузка-узел -> скрипт по пути
## со статиками (preload отсутствующего файла = мёртвый скрипт, потому только
## ResourceLoader.exists + load в момент открытия). QA на 4.7.2.stable: классы
## class_name в рантаймовом ClassDB ОТСУТСТВУЮТ (ClassDB.class_exists("ClickMove")
## == false при живом скрипте со статиками), поэтому ClassDB здесь не приврата.
## Ничего -> null -> строка скрыта.
func _resolve_click_move():
	var node := get_tree().root.get_node_or_null(NodePath(CM_CLASS))
	if node != null and node.has_method("is_on") and node.has_method("set_on"):
		return node
	if not ResourceLoader.exists(CM_PATH):
		return null
	var sc := load(CM_PATH) as GDScript
	if sc == null:
		return null
	var names: Array = []
	for m in sc.get_script_method_list():
		names.append(String((m as Dictionary).get("name", "")))
	if names.has("is_on") and names.has("set_on"):
		return sc
	push_warning("ClickMove без is_on/set_on — контракт не выполнен, тумблер скрыт")
	return null

## Вызывается при каждом открытии: фича появляется позже этой задачи.
func _refresh_click_move() -> void:
	_cm_api = _resolve_click_move()
	if _cm_api == null:
		cm_row.visible = false
		return
	var on := false
	if _cm_api is Node:
		on = bool(_cm_api.call("is_on"))
	else:
		on = bool((_cm_api as GDScript).call("is_on"))
	cm_btn.set_pressed_no_signal(on)  # программная установка — без сигнала toggled
	_cm_refresh_text(on)
	cm_row.visible = true

func _cm_refresh_text(on: bool) -> void:
	cm_btn.text = "Ход по правому клику — %s" % ("вкл" if on else "выкл")

func _on_cm_toggled(on: bool) -> void:
	GameAudio.sfx("ui_click")
	_cm_refresh_text(on)
	if _cm_api != null:
		_cm_api.call("set_on", on)   # персист — ответственность ClickMove

# --- тумблер миникарты (тот же контракт is_on/set_on, что у ClickMove) ---

## Резолв против контракта: узел-автозагрузка -> скрипт class_name Minimap из
## ГЛОБАЛЬНОГО СПИСКА КЛАССОВ ProjectSettings (ClassDB.class_exists НЕ видит
## скриптовые классы — проба на 4.7.2) -> проверка файла и статик is_on/set_on.
## Ничего -> null -> строка скрыта.
func _resolve_minimap():
	var node := get_tree().root.get_node_or_null(NodePath(MM_CLASS))
	if node != null and node.has_method("is_on") and node.has_method("set_on"):
		return node
	var known := false
	for g in ProjectSettings.get_global_class_list():
		if String((g as Dictionary).get("class", "")) == MM_CLASS:
			known = true
			break
	if not known:
		return null
	if not ResourceLoader.exists(MM_PATH):
		push_warning("Minimap зарегистрирован, но %s отсутствует — тумблер скрыт" % MM_PATH)
		return null
	var sc := load(MM_PATH) as GDScript
	if sc == null:
		return null
	var names: Array = []
	for m in sc.get_script_method_list():
		names.append(String((m as Dictionary).get("name", "")))
	if names.has("is_on") and names.has("set_on"):
		return sc
	push_warning("Minimap без is_on/set_on — контракт не выполнен, тумблер скрыт")
	return null

## Вызывается при каждом открытии: фича появляется позже этого хунка.
func _refresh_minimap() -> void:
	_mm_api = _resolve_minimap()
	if _mm_api == null:
		mm_row.visible = false
		return
	var on := false
	if _mm_api is Node:
		on = bool(_mm_api.call("is_on"))
	else:
		on = bool((_mm_api as GDScript).call("is_on"))
	mm_btn.set_pressed_no_signal(on)
	_mm_refresh_text(on)
	mm_row.visible = true

func _mm_refresh_text(on: bool) -> void:
	mm_btn.text = "Миникарта (M) — %s" % ("вкл" if on else "выкл")

func _on_mm_toggled(on: bool) -> void:
	GameAudio.sfx("ui_click")
	_mm_refresh_text(on)
	if _mm_api != null:
		_mm_api.call("set_on", on)   # персист — ответственность Minimap

# --- «Сейв»: экспорт/импорт строкового бэкапа (вся логика — в SaveVault) ---

func _on_sv_export() -> void:
	var t := SaveVault.export_text()
	if t == "":
		_sv_msg("Сейва ещё нет — экспортировать нечего", false)
		GameAudio.sfx("ui_deny")
		return
	sv_export.text = t
	sv_export.select(0, t.length())  # предвыделение: сразу видно, что копируем
	# Буфер — best-effort: на десктопе/WebGL есть, на headless/экзотах тихий
	# фолбэк — readonly-строка с предвыделением и Ctrl+C всегда остаются.
	var copied := false
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(t)
		copied = DisplayServer.clipboard_has()
	_sv_msg("Скопировано в буфер" if copied else "Выделено: Ctrl+C", true)
	GameAudio.sfx("ui_confirm")

func _on_sv_import() -> void:
	var s := sv_import.text.strip_edges()
	if s == "":
		# Пустой ввод — только мерцание отказа: без тоста, без crash, файл не тронут.
		GameAudio.sfx("ui_deny")
		_sv_blink(sv_apply_btn)
		return
	if SaveVault.import_text(s) == OK:
		sv_import.text = ""
		sv_export.text = ""
		_sv_msg("Сейв восстановлен. Перезайдите (F9) или перезапустите", true)
		# В реестре GameAudio нет ui_purchase — канонное «успех» имя ui_confirm.
		GameAudio.sfx("ui_confirm")
	else:
		_sv_msg("Не похоже на наш сейв", false)
		GameAudio.sfx("ui_deny")
		_sv_blink(sv_apply_btn)

func _sv_msg(text: String, ok: bool) -> void:
	sv_msg.text = text
	sv_msg.add_theme_color_override("font_color",
		Color(0.6, 0.9, 0.6) if ok else Color(0.95, 0.55, 0.45))

## Мерцание отказа: тройное падение modulate (Tween, без оверхеда в _process).
func _sv_blink(btn: Button) -> void:
	var tw := create_tween()
	tw.set_loops(3)
	tw.tween_property(btn, "modulate", Color(1.0, 0.45, 0.45), 0.07)
	tw.tween_property(btn, "modulate", Color.WHITE, 0.07)

# --- занятость мира (по чужим окнам не открываемся) ---

## Диалог / модалка выбора класса у родителя-world (слабая типизация: узел hud
## ищет через get(), без предположений о порядке создания).
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
	# Открытые лавка/журнал: Esc принадлежит им. Наш _input опережает их
	# _unhandled-фазы — без этого гейта Esc «воровался» у лавки/журнала:
	# окно под меню не закрывалось, а Esc открывал меню поверх него.
	if Shop.is_open():
		return true
	for c in p.get_children():
		if c is Journal and c.is_open():
			return true
	return false

## Открытию мешает любой чужой владелец ввода: наш lock ставится только поверх
## свободной игры — тогда close()/_exit_tree снимают именно его.
func _busy() -> bool:
	return GameState.input_locked or _ui_windows_open()
