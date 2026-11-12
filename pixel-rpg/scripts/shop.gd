class_name Shop
extends CanvasLayer
## Лавка кузнеца Гриима: покупка снаряжения (сразу equip через GameState.equip_item)
## и продажа надетого (свободных слотов инвентаря в игре нет — «дубли» сдать
## нельзя, сдать можно только то, что надето, по половине цены).
## Панель скрыта с момента создания и в скрытом состоянии не ест мышь
## (mouse_filter=IGNORE) и не светится поверх мира — smoke-прогон её «не видит».
## Открытие/закрытие из любого кода: Shop.open()/close() (хук — реплика кузнеца).
## Синглтон по образцу GameAudio: статический I захватывается в _enter_tree.
##
## Лавка модальна по образцу SettingsMenu: открытие из свободной игры ставит
## GameState.input_locked (мир замирает: player.gd гейтит ход/кувырок/атаку,
## world.gd — E/F5/F9/скиллы, мобы паузятся). Снимается ровно свой lock:
## * поверх чужого окна/чужого lock не открываемся (_busy -> ui_deny), поэтому
##   close()/_exit_tree() никогда не снимают «чужой» lock;
## * пока лавка открыта все события глотаются в _unhandled_input (Esc закрывает
##   только лавку) — до world-софтлок-страховки (world.gd снимает lock при
##   закрытых окнах hud) не доходит ничего, разлока не происходит;
## * _process() — watchdog: возвращает lock, если внешний код всё же снял его
##   (advance() диалога снимает input_locked безусловно; курсор за краем окна);
## * если поверх лавки встало чужое окно (квестовый диалог, смерть) или чужой
##   lock — лавка перестаёт перехватывать ввод (_external_lock), окно работает;
##   после его закрытия watchdog возвращает lock лавке;
## * покупка/продажа доступны под СОБСТВЕННЫМ lock (иначе лавка не торговала бы),
##   но блокируются при чужом;
## * GameAudio input_locked не гейтится — музыка/звуки под лавкой не молчат.
## Ключи InputMap не регистрируются — project.godot не трогаем.

static var I: Shop             # синглтон; назначает сам себя в _enter_tree

## «Алтарь Пепла» (§4.2): второй список кнопок внутри уже открытой лавки,
## валюта — Пепел из res://scripts/ash.gd (резолв ResourceLoader.exists + load:
## class_name в рантаймовом ClassDB 4.7.2 отсутствует, паттерн settings_menu.gd).
## Алтарь НЕ модальность: свой lock не берёт, покупка под гейтом _external_lock()
## — как обычная покупка/продажа. cap=0 — без потолка (bless: шаг цены +2).
const ASH_PATH := "res://scripts/ash.gd"
const ALTAR := [
	{"id": "bless", "name": "Благословение", "desc": "+4 к max HP навсегда", "price": 3, "step": 2, "cap": 0},
	# t42: ярлык обязан совпадать с данными. Источник истины — gear_data.player_damage():
	# множитель «0.15 * f» (t39 поднял с 0.10, кап f≤3 ⇒ максимум +45 %), он же
	# source-пинуется в qa_mb R8. Читать его из константы тривиально нельзя: в
	# gear_data.gd это литерал внутри выражения, а сам файл вне объёма t42.
	{"id": "master", "name": "Мастерство", "desc": "+15% к урону героя", "price": 5, "step": 0, "cap": 3},
	{"id": "purse", "name": "Кошелёк", "desc": "+50 зол. к старту каждого NG+ (эффект вступит с NG+)", "price": 4, "step": 0, "cap": 2},
	{"id": "greed", "name": "Жадность", "desc": "+25% золота с мобов", "price": 6, "step": 0, "cap": 1},
	{"id": "feet", "name": "Лёгкие ноги", "desc": "Кулдаун кувырка 0.9 → 0.75 c", "price": 8, "step": 0, "cap": 1},
]

## t34 V-06 (реестр t30, high): полная витрина в дефолтном стиле была 240×397
## при каноническом поле 640×360 (window 1280×720, stretch canvas_items/expand) —
## «Закрыть (Esc)» @(205,371) целиком уходила за нижнюю границу, закрыть мышью
## было нельзя (только Esc). Меры, обе сразу:
## 1) КОМПАКТ-ТЕМА: штатные стейтбоксы кнопки с урезанными вертикальными
##    content-отступами (4 -> 2, ряд 21 -> 17) + separation 3 -> 2. Полный список
##    (шапка + 5 покупок + 2 скупки + 5 алтаря + 3 заголовка + close) = 328 px
##    (замер probe: витрина 268 + шапка/close/поля 60), т.е. влезает в безопасное
##    поле 352 (= 360 − 2×4) с запасом 24 px; низ close — 339 вместо 392;
## 2) SCROLLCONTAINER вокруг витрины — СТРАХОВКА на случай роста стока или
##    низкого окна: список уходит внутрь, а close-кнопка стоит ВНЕ скролла,
##    значит видима без прокрутки всегда. Пока всё влезает — полосы нет и
##    оффскрин-скан лавки даёт 0 (ни один элемент не за экраном).
##
## t40 (находка t38, t38_play/logs/w_forge.log PIN#01): при открытой лавке
## панель накрывала ГЕРОЯ ПОЛНОСТЬЮ — он стоит ровно по центру поля, а панель
## центрирована в том же центре. Замер ОКОННЫМ прогоном 1280×720 (stretch
## canvas_items/expand ⇒ окно 2×, zoom мира 1.5 ⇒ 3 px окна на мирный px),
## лавка открыта НАСТОЯЩИМ E у прилавка (кузнец Гриим, тайл (26,13)); маска
## героя = реально накрашенные пиксели кадра спрайта (2092 шт.), не bounding box:
##   • ЦЕНТР (как было): панель base x 200..440 — под ней 100 % пикселей героя
##     (колонка героя x 311.6..328.4), плюс 13 126 px спрайта самого кузнеца,
##     16 505 px реквизита и 45 414 px крон = 75 045 px живого мира под панелью;
##   • ЛЕВЫЙ край (gap 4): герой 0 %, но под панелью 21 467 + 3 343 + 32 907
##     = 57 717 px мира;
##   • ПРАВЫЙ край (gap 4): герой 0 %, 16 188 + 1 905 + 19 916 = 38 009 px —
##     наименьшее затемнение мира из трёх, выбран ОН.
## Итог: панель прижата к правому краю (base x 396..636 вместо 200..440); до
## колонки героя остаётся 67.6 px запаса, перекрытие спрайта героя = 0 % при
## лимите задачи 25 %. Компакт-тема t34 и ширина 240 не тронуты (компакт-вариант
## всё равно стоял бы на герое), полупрозрачность как последний резерв НЕ
## применена — панель осталась opaque-«деревянной», просто съехала вправо.
## ВЕРТИКАЛЬ для игроки НЕ изменилась: панель по-прежнему центрирована в поле с
## зазором EDGE_GAP (как в t34), пины t34 — «Закрыть (Esc)» в кадре, OFFSCR=0,
## высота ≤352, колесо мыши — проходят без единой правки. Единственное изменение
## по высоте — контейнер-якорь ограничивается КАНОНической высотой поля (в окне
## 1280×720 visible-rect ровно 640×360 ⇒ сдвиг = 0, то есть бит-в-бит то же
## самое; в headless-окне 640×640 контейнер больше не торчит за канон 360, и
## оффскрин-скан t30/t34 не принимает его за «элемент за экраном» — до t40 он
## спасался лишь правилом «площадь ≥ 95 % поля», а с правым доком площадь стала
## 248×640). Крона GroveCanopy над прилавком (34 %
## бокса героя у t38) вне объёма задачи и не тронута: канон «принять/осветить»,
## overhead-дим (modulate 0.5) уже работает.
const BASE_VIEW_H := 360.0     # канон base-вьюпорта (не окно!) — поле проектирования UI
const PANEL_W := 240.0         # ширина панели (была custom_minimum_size.x)
const EDGE_GAP := 4.0          # воздушный зазор панели от верхней/нижней границы поля
const COL_SEPARATION := 2      # t34 V-06: было 3
const ROW_SEPARATION := 2      # t34 V-06: было 3
const BTN_PAD_V := 2           # t34 V-06: вертикальный content-отступ кнопки (дефолт 4)

var scroll: ScrollContainer    # t34 V-06: прокручиваемая витрина (страховка переполнения)
var list_vb: VBoxContainer     # t34 V-06: единственный ребёнок scroll (секции витрины)
var close_btn: Button          # t34 V-06: вне скролла => «Закрыть (Esc)» видима всегда

var altar_head: Label          # заголовок секции алтаря с балансом Пепла (§4.2)
var altar_btns := {}           # meta id -> Button алтаря

var root: Control              # полноэкранный корень панели; visible = «лавка открыта»
var dim: ColorRect             # затемнение мира; клик мимо окна закрывает лавку
var panel: PanelContainer
var center: CenterContainer    # t40: контейнер-«якорь» панели; по высоте — центр, по X — правый край
var gold_lbl: Label
var buy_btns := {}             # item id -> Button («купить и надеть»)
var sell_btns := {}            # slot -> Button («продать надетое»)
var ui_frame_tex: Texture2D    # 9-slice рамка (assets/ui/panel_frame.png), опц.
var _holds_lock := false       # input_locked сейчас принадлежит лавке, а не кому-то ещё
var _mouse_pass := false       # t29 B-02: мышь сейчас принадлежит чужому окну (лавка её пропускает)

func _enter_tree() -> void:
	if I == null:
		I = self

func _exit_tree() -> void:
	# Выход из сцены с открытой лавкой не должен оставлять висячий lock:
	# снимаем только если lock был наш и поверх не стоит чужое окно.
	_release_lock()
	if I == self:
		I = null

func _ready() -> void:
	layer = 5  # выше HUD (1), ниже фейда переходов (10)
	if ResourceLoader.exists("res://assets/ui/panel_frame.png"):
		ui_frame_tex = load("res://assets/ui/panel_frame.png")
	_build()
	# t34 V-06: окно ниже канона (или другой aspect при expand) — витрина уходит
	# в скролл, а не за нижнюю границу экрана.
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _fit_panel):
		vp.size_changed.connect(_fit_panel)

# --- статические обёртки: хукам не нужна проверка I в каждом вызове ---

static func open() -> void:
	if I == null or I.root == null:
		return
	if I._busy():  # чужой диалог/модалка/журнал/lock — не открываемся (как SettingsMenu)
		GameAudio.sfx("ui_deny")
		return
	I._set_open(true)
	Sfx.play("panel_open")  # t31: мягкий взмах ткани на открытии витрины

static func close() -> void:
	if I != null and I.root != null:
		I._set_open(false)

static func is_open() -> bool:
	return I != null and I.root != null and I.root.visible

# --- построение панели ---

func _build() -> void:
	var th := Theme.new()
	UIFont.apply(th, 9)  # t27 P1-1: пиксельный шрифт с кириллицей, базовая ступень 8 -> 9
	_compact_buttons(th)  # t34 V-06: компакт-ряды, чтобы полный список влез в поле 360
	root = Control.new()
	root.name = "ShopRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false  # скрыта с момента создания — смоук-мира не касается
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # скрытая мышь не ест
	add_child(root)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	root.add_child(dim)
	center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.name = "ShopPanel"
	panel.theme = th
	if ui_frame_tex != null:
		panel.add_theme_stylebox_override("panel", _ui_frame_style(5.0))
	center.add_child(panel)
	# Колонка панели (t34 V-06): неизменяемая шапка + прокручиваемая витрина +
	# close-кнопка ВСЕГДА под витриной, а не внутри неё.
	var vb := VBoxContainer.new()
	vb.name = "Col"
	vb.add_theme_constant_override("separation", COL_SEPARATION)
	panel.add_child(vb)
	var head := Label.new()
	head.text = "Кузница Гриима"
	head.add_theme_font_size_override("font_size", 10)
	head.add_theme_color_override("font_color", Color(1, 0.84, 0.45))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	gold_lbl = Label.new()
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	vb.add_child(gold_lbl)
	scroll = ScrollContainer.new()
	scroll.name = "ShopScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# t34 V-06: STOP (не PASS!) — иначе клик по пустому месту витрины проваливался
	# бы в dim и закрывал лавку; колесо мыши скроллит именно здесь.
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL  # берёт весь остаток колонки
	vb.add_child(scroll)
	list_vb = VBoxContainer.new()
	list_vb.name = "ShopList"
	list_vb.add_theme_constant_override("separation", ROW_SEPARATION)
	list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # паттерн journal.gd
	scroll.add_child(list_vb)
	list_vb.add_child(_section_label("Витрина:"))
	for id in GearData.SHOP_STOCK:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_buy.bind(String(id)))
		list_vb.add_child(btn)
		buy_btns[String(id)] = btn
	list_vb.add_child(_section_label("Скупка (сдам надетое вдвое дешевле):"))
	for slot in ["weapon", "armor"]:
		var sbtn := Button.new()
		sbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sbtn.pressed.connect(_on_sell.bind(String(slot)))
		list_vb.add_child(sbtn)
		sell_btns[String(slot)] = sbtn
	# --- «Алтарь Пепла» (§4.2): вторая витрина, цены в Пепле ---
	altar_head = _section_label("Пепельный Алтарь:")
	list_vb.add_child(altar_head)
	for e in ALTAR:
		var abtn := Button.new()
		abtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		abtn.pressed.connect(_on_ash_buy.bind(String((e as Dictionary).get("id", ""))))
		list_vb.add_child(abtn)
		altar_btns[String((e as Dictionary).get("id", ""))] = abtn
	close_btn = Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "Закрыть (Esc)"
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)
	GameState.gold_changed.connect(refresh)
	_fit_panel()  # t34 V-06: до первого кадра панель уже в безопасном поле
	refresh()

func _section_label(text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", 8)  # t27 P1-1: 7 -> 8
	lb.add_theme_color_override("font_color", Color(0.85, 0.75, 0.6))
	return lb

## t34 V-06 (компакт-тема): берём ШТАТНЫЕ стейтбоксы кнопки (цвет/рамка/скругления
## канона не тронуты) и режем только вертикальные content-отступы 4 -> 2:
## ряд 21 -> 17 px. Theme.get_stylebox делает fallback в родительские и дефолтную
## темы, а берём мы ДУБЛИКАТ — иначе поправили бы общий ресурс на весь проект.
## Кнопки настроек/журнала живут своими темами, не затронуты.
func _compact_buttons(th: Theme) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var base: StyleBox = th.get_stylebox(st, "Button")
		if base == null:
			continue  # темы нет — просто оставляем дефолт (ряды будут чуть выше)
		var sb := base.duplicate() as StyleBox
		if sb == null:
			continue
		sb.content_margin_top = BTN_PAD_V
		sb.content_margin_bottom = BTN_PAD_V
		th.set_stylebox(st, "Button", sb)

## t34 V-06: панель никогда не выше безопасного поля. Считаем по min-size'ам
## (синхронно, до первого кадра): «полная» высота = витрина + шапка + close +
## поля панели; если она влезает — скролл получает ровно высоту содержимого
## (полосы нет, оффскрина нет); если нет — скролл сжимается до остатка, а
## close-кнопка остаётся снизу колонки видимой без прокрутки.
func _fit_panel() -> void:
	if panel == null or scroll == null or list_vb == null or close_btn == null:
		return
	var field_h := BASE_VIEW_H
	var raw_h: float = BASE_VIEW_H
	var vp := get_viewport()
	if vp != null:
		raw_h = vp.get_visible_rect().size.y
		field_h = minf(raw_h, BASE_VIEW_H)  # headless-окно 640×640 -> канон 360
	var max_h: float = maxf(96.0, field_h - EDGE_GAP * 2.0)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)  # сброс: ниже меряем «чистый» min
	var content := list_vb.get_combined_minimum_size().y
	scroll.custom_minimum_size = Vector2(0, content)  # временно: сколько хочет витрина
	var natural := panel.get_combined_minimum_size().y
	var chrome := natural - content  # шапка + close + separation + поля панели
	var target := minf(natural, max_h)
	panel.custom_minimum_size = Vector2(PANEL_W, target)
	scroll.custom_minimum_size = Vector2(0, maxf(0.0, target - chrome))
	# t40: док к ПРАВОМУ краю (обоснование и замеры — в ГЕОМЕТРИЯ в шапке файла).
	# CenterContainer размещает ребёнка по ЦЕНТРУ своего rect, поэтому сдвигаем
	# сам rect контейнера слева на (W − pw − 2×gap): левый край панели встаёт в
	# W − pw − gap, правый — в W − gap. По высоте rect остаётся «центральным»
	# (см. band ниже) ⇒ для окна 1280×720 вертикальная геометрия бит-в-бит t34.
	# Берём ФАКТИЧЕСКУЮ ширину панели (запас на случай, если подпись кнопки
	# раздвинет её дальше PANEL_W), иначе док дал бы хвост за правым краем.
	var pw: float = maxf(PANEL_W, panel.get_combined_minimum_size().x)
	var field_w: float = vp.get_visible_rect().size.x if vp != null else 640.0
	center.offset_left = maxf(0.0, field_w - pw - EDGE_GAP * 2.0)
	# t40: вертикаль якоря ограничена каноническим полем. В реальном окне 1280×720
	# visible-rect = 640×360 ⇒ band = 0, то есть вертикальная геометрия бит-в-бит
	# та же, что в t34 (проверено оконным прогоном: панель y=16, h=328). В headless
	# (окно 640×640) band = 140 снимает с якоря фантомные 280 px высоты, из-за
	# которых оффскрин-скан t30/t34 считал бы его «элементом за экраном».
	var band: float = maxf(0.0, (raw_h - field_h) * 0.5)
	center.offset_top = band
	center.offset_bottom = -band

## Тёмная деревянная рамка для PanelContainer (тот же ассет и приёмы, что в hud.gd).
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

# --- открытие/закрытие ---

func _set_open(v: bool) -> void:
	if root.visible != v:
		root.visible = v
		# открытая лавка ловит мышь (мир под ней не кликается и не атакует:
		# player.gd не бьёт, когда под курсором есть Control); скрытая — IGNORE
		root.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
		_mouse_pass = false
		if v:
			_set_mouse_pass(false)  # t29 B-02: при открытии мышь снова вся наша
			_fit_panel()            # t34 V-06: актуальное поле на момент открытия
			if scroll != null:
				scroll.scroll_vertical = 0  # лавка всегда открывается с начала витрины
		GameAudio.sfx("ui_confirm" if v else "ui_click")
		if v:
			_acquire_lock()
		else:
			_release_lock()
	if v:
		refresh()

## t29 B-02 (реестр t28): под ЧУЖИМ окном (диалог/смерть) лавка по контракту
## «окно работает» не должна перехватывать мышь, но раньше полноэкранный dim
## (STOP) и кнопки продолжали есть клики: диалог смерти под вуалью нельзя было
## пролистать мышью вообще. Здесь мышь отдаётся целиком: dim/корень/панель/кнопки
## и скролл витрины -> IGNORE (остальные Control и так IGNORE), клики уходят
## миру -> hud.advance().
func _set_mouse_pass(passthrough: bool) -> void:
	if root == null:
		return
	_apply_pass(root, passthrough)

func _apply_pass(c: Control, passthrough: bool) -> void:
	# t34 V-06: ScrollContainer — такой же «едок» мыши, как кнопки (mouse_filter
	# STOP), поэтому обязан участвовать в отдаче: иначе под чужим окном полоса
	# скролла витрины глушила бы клики по диалогу/смерти (регресс B-02).
	if c == root or c == dim or c == panel or c is Button or c is ScrollContainer:
		var want := Control.MOUSE_FILTER_IGNORE if passthrough else Control.MOUSE_FILTER_STOP
		if c.mouse_filter != want:
			c.mouse_filter = want
	for ch in c.get_children():
		if ch is Control:
			_apply_pass(ch as Control, passthrough)

func _acquire_lock() -> void:
	# Вызываемся только из состояния «не занято» (статический open() проверил
	# _busy): lock ставится поверх свободной игры и принадлежит теперь лавке.
	GameState.input_locked = true
	_holds_lock = true

## Вернуть lock, который поставила лавка. Если поверх успело встать чужое окно
## и lock «перешёл» к нему — не трогаем: снимет сам владелец (advance/модалка).
func _release_lock() -> void:
	if _holds_lock and not _ui_windows_open():
		GameState.input_locked = false
	_holds_lock = false

## Страховка (паттерн SettingsMenu): если внешний код снял lock (безусловный
## разлок в конце диалога, просочившееся за край окна событие + world-страховка) —
## возвращаем, пока лавка открыта и чужие окна чисты.
func _process(_delta: float) -> void:
	if root == null or not root.visible:
		return
	# t29 B-02: мышь принадлежит чужому окну, пока оно поверх (диалог, смерть) —
	# отдаём весь ввод наружу; как только окно ушло, лавка снова берёт мышь себе.
	var pass_thru := _external_lock()
	if pass_thru != _mouse_pass:
		_mouse_pass = pass_thru
		_set_mouse_pass(pass_thru)
	if not GameState.input_locked and not _ui_windows_open():
		GameState.input_locked = true
		_holds_lock = true

# --- владение вводом (паттерн SettingsMenu) ---

## Чужие окна у родителя-world: диалог/модалка hud, журнал. Слабая типизация:
## hud через get(), без предположений о порядке создания узлов.
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

## Ввод/лок, принадлежащий не лавке: чужое окно либо lock, который ставили не мы.
func _external_lock() -> bool:
	return _ui_windows_open() or (GameState.input_locked and not _holds_lock)

## Открытию мешает любой чужой владелец ввода.
func _busy() -> bool:
	return GameState.input_locked or _ui_windows_open()

# --- ввод ---

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return  # закрытая лавка не перехватывает ничего: Esc/J/всё остальное — игре
	if _external_lock():
		return  # поверх лавки встало чужое окно/lock (диалог, смерть) — не глушим его
	# открытая лавка модальна по вводу: клавиши мира (скиллы, зелье, E, F9) гасим,
	# Esc закрывает только лавку (в InputMap ничего не регистрировали). Глотаем
	# всё, включая release-события: до world-страховки не доходит ничего,
	# собственный lock не «мигает» и не снимается чужими ветками world.gd.
	if event.is_action_pressed("ui_cancel"):
		close()
	get_viewport().set_input_as_handled()

func _on_dim_input(event: InputEvent) -> void:
	if _external_lock():
		return  # поверх лавки чужое окно — клики принадлежат ему
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

# --- сделки ---

func _on_buy(id: String) -> void:
	if _external_lock():
		return  # покупка разрешена только под СОБСТВЕННЫМ lock лавки
	var it := GearData.item(id)
	var slot := String(it.get("slot", ""))
	if not GameState.gear.has(slot):
		push_warning("Shop: неизвестный слот предмета: %s" % id)
		return
	var equipped := GearData.equipped_id(GameState, slot) == id
	if equipped:
		GameAudio.sfx("ui_deny")
		GameState.toast.emit("Это уже на тебе.")
		return
	if not GameState.spend_gold(GearData.price(id)):
		GameAudio.sfx("ui_deny")  # тост «Не хватает золота...» — внутри spend_gold
		refresh()
		return
	# Надеть: сначала освободить слот — это синхронизирует legacy has_sword
	# (equip_item чистит флаг на ""), затем положить новую вещь.
	GameState.equip_item(slot, "")
	GameState.equip_item(slot, id)
	GameState.stats_changed.emit()  # armor-слот equip_item не эмитит — HUD сам обновим
	Sfx.play("coin")  # t31: тёплый монетный «дзынь» вместо ui_confirm
	GameState.toast.emit("Куплено: %s. Надето!" % String(it.get("name", id)))
	Achv.on_buy()  # ачивка «Покупатель: 5 вещей» (achv.gd)
	refresh()

func _on_sell(slot: String) -> void:
	if _external_lock():
		return  # аналогично покупке: только под своим lock
	var gid := GearData.equipped_id(GameState, slot)
	var price := GearData.sell_price(gid)
	if price <= 0:
		GameAudio.sfx("ui_deny")
		GameState.toast.emit("Продавать нечего.")
		return
	GameState.equip_item(slot, "")
	GameState.add_gold(price)
	GameState.stats_changed.emit()
	GameAudio.sfx("belt")
	GameState.toast.emit("Гриим скупил: %s (+%d зол.)" % [String(GearData.item(gid).get("name", gid)), price])
	refresh()

# --- «Алтарь Пепла» (§4.2) ---

## Резолв Пепла: class_name в рантаймовом ClassDB 4.7.2 отсутствует —
## ResourceLoader.exists + load в момент вызова (паттерн settings_menu.gd).
## null — скрипта нет: алтарь деградирует в отказ (ui_deny), лавка живёт.
func _ash() -> GDScript:
	if not ResourceLoader.exists(ASH_PATH):
		return null
	return load(ASH_PATH) as GDScript

func _ash_balance() -> int:
	var sc := _ash()
	return int(sc.call("balance")) if sc != null else 0

## Цена позиции: base + step * куплено (bless: 3,5,7…; шаг 0 — фикс).
func _altar_price(e: Dictionary, owned: int) -> int:
	return int(e.get("price", 0)) + int(e.get("step", 0)) * owned

func _owned(id: String) -> int:
	return int(GameState.flags.get("meta." + id, 0))  # только .get(): старые сейвы не крашим

func _on_ash_buy(id: String) -> void:
	if _external_lock():
		return  # покупка только под СОБСТВЕННЫМ lock лавки (контракт модальности)
	var e: Dictionary = {}
	for x in ALTAR:
		if String((x as Dictionary).get("id", "")) == id:
			e = x
			break
	if e.is_empty():
		push_warning("Shop: неизвестная позиция алтаря: %s" % id)
		return
	var cap := int(e.get("cap", 0))
	var owned := _owned(id)
	if cap > 0 and owned >= cap:
		GameAudio.sfx("ui_deny")
		GameState.toast.emit("%s: предел (%d/%d)." % [String(e.get("name", id)), owned, cap])
		return
	var sc := _ash()
	if sc == null:
		GameAudio.sfx("ui_deny")
		return
	var price := _altar_price(e, owned)
	if not bool(sc.call("spend", price)):
		GameAudio.sfx("ui_deny")
		GameState.toast.emit("Не хватает Пепла: нужно %d." % price)
		refresh()
		return
	GameState.set_flag("meta." + id, owned + 1)
	if FirstHint.I != null: FirstHint.I.show_hint("ash", "Пепел — валюта алтаря: усиления покупаются навсегда, даже между жизнями.")
	GameState.save_game()  # трата обязана пережить выход (железное правило P1)
	Sfx.play("altar")  # t31: алтарный аккорд A-E-A — взяточнее простого «подтверждения»
	var total := _owned(id)
	var cap_s := "∞" if cap <= 0 else str(cap)
	GameState.toast.emit("Алтарь: %s (куплено %d/%s)." % [String(e.get("name", id)), total, cap_s])
	refresh()

# --- витрина ---

func refresh() -> void:
	if gold_lbl == null:
		return
	gold_lbl.text = "Золото: %d" % GameState.gold
	for id in buy_btns:
		var btn: Button = buy_btns[id]
		var it := GearData.item(String(id))
		var price := GearData.price(String(id))
		var equipped := GearData.equipped_id(GameState, String(it.get("slot", ""))) == String(id)
		btn.disabled = equipped
		btn.text = "%s — %d зол.%s" % [String(it.get("name", id)), price, "  [надето]" if equipped else ""]
		btn.tooltip_text = String(it.get("desc", ""))
		btn.modulate = Color.WHITE if equipped or GameState.can_afford(price) else Color(0.6, 0.6, 0.66)
	for slot in sell_btns:
		var sbtn: Button = sell_btns[slot]
		var gid := GearData.equipped_id(GameState, String(slot))
		var price := GearData.sell_price(gid)
		sbtn.disabled = price <= 0
		sbtn.text = "%s — %d зол." % [String(GearData.item(gid).get("name", gid)), price] if price > 0 else "— пусто —"
		sbtn.modulate = Color.WHITE
	_refresh_altar()

## Витрина алтаря: баланс в заголовке секции, цены в Пепле (пепельный цвет,
## не золото), подпись «куплено N/M»; предел — кнопка гаснет.
func _refresh_altar() -> void:
	if altar_head == null:
		return
	var bal := _ash_balance()
	altar_head.text = "Пепельный Алтарь (пепел: %d):" % bal
	for x in ALTAR:
		var e := x as Dictionary
		var id := String(e.get("id", ""))
		var abtn: Button = altar_btns.get(id, null)
		if abtn == null:
			continue
		var cap := int(e.get("cap", 0))
		var owned := _owned(id)
		var capped := cap > 0 and owned >= cap
		var price := _altar_price(e, owned)
		var cap_s := "∞" if cap <= 0 else str(cap)
		abtn.disabled = capped
		if capped:
			abtn.text = "%s  [предел %d/%s]" % [String(e.get("name", id)), owned, cap_s]
			abtn.modulate = Color(0.6, 0.6, 0.66)
		else:
			abtn.text = "%s — %d пепла  [куплено %d/%s]" % [String(e.get("name", id)), price, owned, cap_s]
			abtn.modulate = Color(0.84, 0.81, 0.75) if bal >= price else Color(0.55, 0.55, 0.6)
		abtn.tooltip_text = String(e.get("desc", ""))
