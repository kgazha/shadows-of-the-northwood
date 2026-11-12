class_name RunSummary
extends CanvasLayer
## «Забег окончен» — терминальная модалка смерти (CONTRACT_RUNLOOP §1.8–1.9):
## открывается вместо респавна по окончании диалога "death" (колбэк в
## world.gd::on_player_death). Выходы: «Вспыхнуть заново» (тот же Esc, §1.8) =
## GameState.start_new_run(), и «Доска пепла» (t20 P0-3, MetaBoard — покупка
## талантов за пепел перед новым забегом). Мир пересобирает существующий хук
## ng_plus_started (world.gd), вместе со сценой умирает и эта панель (с доской).
## Паттерн модалок Shop/SettingsMenu: свой GameState.input_locked + watchdog в
## _process + полное глотание ввода в _unhandled_input — до world-страховки
## «разлока при закрытых окнах hud» (world.gd::_unhandled_input) не доходит
## ничего, гейты _hotbar_allowed()/E/зелье (input_locked) закрыты модально.
## Закрыта с момента создания — смоук-мира не касается. Закрытие — это смерть
## узла при перезаборе мира: in-scene close() отсутствует by design, висячий
## lock снимает _exit_tree (паттерн Shop).
## t20 P0-3: снимок итогов расширен контрактом — зона/глубина (волна), убийства
## по типам (rs.k.*), золото, заработанный пепел (rs.earned) + сколько
## сохранится, время забега (rs.t), статус боссов круга, сид (run_seed), тип
## убийцы (rs.src) и строка благословения волхвы. Всё из GameState.flags с
## префиксом rs.* (сейв-совместимо: flags едут в сейве как есть; старые v1/v2
## просто не имеют rs.* — везде дефолты).

static var I: RunSummary        # синглтон; назначает сам себя в _enter_tree

var root: Control               # полноэкранный корень панели; visible = «открыта»
var dim: ColorRect              # затемнение мира; клики мимо окна глушатся
var panel: PanelContainer
var stats_lbl: Label
var kills_lbl: Label
var bless_lbl: Label
var rekindle_btn: Button
var board_btn: Button
var ui_frame_tex: Texture2D     # 9-slice рамка (assets/ui/panel_frame.png), опц.
var board: MetaBoard            # «Доска пепла» (дитя панели, layer=7)
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
	# t20: доска пепла — дочерняя модалка (умирает вместе с этой панелью при
	# перезаборе мира; лок ввода остаётся у RunSummary, доска его не берёт).
	board = MetaBoard.new()
	add_child(board)

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
	panel.custom_minimum_size = Vector2(232, 0)
	panel.theme = th
	if ui_frame_tex != null:
		panel.add_theme_stylebox_override("panel", _ui_frame_style(26.0))
	center.add_child(panel)
	# t20: бумажная кромка пергамента — общий компонент wave-3 (PaperEdge,
	# те же марджины, что в журнале; панель расширена 200→232 и content 6→26,
	# чтобы текст не залезал на кромку — урок t24).
	if ResourceLoader.exists("res://assets/ui/decor_paper_edge.png"):
		var paper := PaperEdge.new()
		paper.tex = load("res://assets/ui/decor_paper_edge.png")
		paper.src_margin = 95.0
		paper.dst_margin = 24.0
		paper.set_anchors_preset(Control.PRESET_FULL_RECT)
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		panel.add_child(paper)
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
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stats_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	vb.add_child(stats_lbl)
	kills_lbl = Label.new()
	kills_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	kills_lbl.add_theme_font_size_override("font_size", 7)
	kills_lbl.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	vb.add_child(kills_lbl)
	bless_lbl = Label.new()
	bless_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bless_lbl.add_theme_font_size_override("font_size", 7)
	bless_lbl.add_theme_color_override("font_color", Color(0.65, 0.8, 0.7))
	vb.add_child(bless_lbl)
	# t20: ряд «Пепел: заработано …» с утверждённой иконкой ash_v2 (вердикт юзера)
	var ash_row := HBoxContainer.new()
	ash_row.add_theme_constant_override("separation", 4)
	vb.add_child(ash_row)
	ash_row.add_child(AshIcon.make_rect(14))
	var ash_note := Label.new()
	ash_note.text = "Пепел переживает смерть: сохраняется 60–70% заработанного."
	ash_note.add_theme_font_size_override("font_size", 7)
	ash_note.add_theme_color_override("font_color", Color(0.78, 0.68, 0.5))
	ash_row.add_child(ash_note)
	board_btn = Button.new()
	board_btn.text = "Доска пепла"
	board_btn.pressed.connect(_open_board)
	vb.add_child(board_btn)
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

## Снимок итогов t20 — в момент открытия (start_new_run ещё не вызывался,
## rs.* ещё живы). Значения из сейва — каноническим парсером GameState._num
## (trust-boundary, R5-принцип); level/ng_wave типизированы в самом GameState.
func _refresh() -> void:
	var f: Dictionary = GameState.flags
	var ash := GameState._num(f.get("meta.ash", 0), 0)
	var deaths := GameState._num(f.get("ach.n.deaths", 0), 0)
	var earned := GameState._num(f.get("rs.earned", 0), 0)
	var keep := int(floor(float(earned) * GameState.ASH_KEEP_RATE))
	var tsec := int(GameState._num(f.get("rs.t", 0), 0))
	var w := GameState.ng_wave()
	stats_lbl.text = "Забег: #%d · Круг (глубь): %d\nВремя: %02d:%02d · Золото: %d\nПепел: баланс %d · заработано %d · сохранится ~%d\n%s\nСид: %d" % [
		deaths + 1, w,
		int(tsec / 60.0), tsec % 60, GameState.gold,
		ash, earned, keep,
		_killer_line(), GameState.run_seed,
	]
	kills_lbl.text = _kills_block() + _boss_line(w)
	# Благословение волхвы: vd ещё «до этой смерти» (инкрементит start_new_run) —
	# показываем, с каким множителем стартует НОВЫЙ забег.
	var next_stacks := clampi(deaths_to_stacks_preview(), 0, GameState.BLESS_CAP_DEATHS)
	bless_lbl.text = "Волхва: +%d%% урона в новом забеге (смертей круга: %d)" % [
		int(round(GameState.BLESS_PER_DEATH * 100.0 * float(next_stacks))),
		GameState._num(f.get("meta.vd", 0), 0) + 1,
	]

## Смертей круга, которые учтёт новый забег (meta.vd + эта смерть, с капом
## через тот же BLESS_CAP_DEATHS, что и GameState.volkhv_stacks).
func deaths_to_stacks_preview() -> int:
	return GameState._num(GameState.flags.get("meta.vd", 0), 0) + 1

## «Пал от: …» — kind убийцы (rs.src) → RU-имя из единого реестра AchvCatalog.MOBS.
func _killer_line() -> String:
	var src := String(GameState.flags.get("rs.src", ""))
	if src == "":
		return "Пал от: лес"
	return "Пал от: %s" % _mob_name(src)

## RU-имя моба: реестр AchvCatalog.MOBS (единый источник имён) + покро-вные
## ключи, которых в нём нет по истории (лут-табличные id боев и tier-Гром).
func _mob_name(k: String) -> String:
	if AchvCatalog.MOBS.has(k):
		return String(AchvCatalog.MOBS[k])
	if k == "boss":
		return "Осквернённый Гром"
	if k.begins_with("brute_t"):
		return "Гром (усиленный)"
	if k == "wraith":
		return "Тенеплёт"
	return k

## «Убийства: …» — счётчики rs.k.<kind> в алфавите RU-имён.
func _kills_block() -> String:
	var parts: Array = []
	var keys: Array = GameState.flags.keys()
	keys.sort()
	for k in keys:
		var ks := String(k)
		if not ks.begins_with("rs.k."):
			continue
		var n := GameState._num(GameState.flags[k], 0)
		if n > 0:
			parts.append("%s ×%d" % [_mob_name(ks.substr(5)), n])
	if parts.is_empty():
		return "Убийства: ни одного\n"
	return "Убийства: " + ", ".join(PackedStringArray(parts)) + "\n"

## Статус боссов круга: Гром — пер-волновой гейт ng.boss_<w> (brute.gd),
## ведьма — ashen.boss == "dead" (её флаг стирается вайпом, как и всё ashen.*).
func _boss_line(w: int) -> String:
	var grom := GameState._num(GameState.flags.get("ng.boss_%d" % w, 0), 0) > 0
	var witch := String(GameState.flags.get("ashen.boss", "")) == "dead"
	return "Боссы: %s · %s\n" % [
		"Гром повержен" if grom else "Гром жив",
		"Ведьма повержена" if witch else "Ведьма жива",
	]

func _open_board() -> void:
	GameAudio.sfx("ui_confirm")
	MetaBoard.open()

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
	# гасим; Esc — двухступенчатый (t20): при открытой доске пепла сначала
	# закрывает доску, только затем «Вспыхнуть заново» (§1.8). Глотаем всё,
	# включая release-события: до world-страховки не доходит ничего, собственный
	# lock не «мигает» и не снимается чужими ветками world.gd.
	if event.is_action_pressed("ui_cancel"):
		if MetaBoard.is_open():
			MetaBoard.close_panel()
		else:
			_rekindle()
	get_viewport().set_input_as_handled()
