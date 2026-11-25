class_name Inventory
extends CanvasLayer
## g20a (вердикт пользователя 17.11 ~10:00, INVENTORY.md «Окно», поставка А):
## окно инвентаря на I. Панель в стиле карточек лавки (та же 9-slice рамка
## panel_frame + Theme UIFont), слева сетка 6×2 (12 ячеек), угловой счётчик
## стопки как в лавке. Закрытие — I или ESC.
##
## Модель: инвентарь — ЗЕРКАЛО единственных источников истины GameState
## (herbs / brewed_potions / torches / materials + квестовые has_key/
## has_amulet). Отдельного склада нет: подбор кладёт в источник, хотбар и
## сетка читают его же, Use тратит из него же (пустой инвентарь = пустой
## хотбар-слот). Сейв-контейнер v4 ("inv") — в game_state.gd.
##
## Владение вводом — паттерн Shop (t29 B-02/B-03 заимствованы целиком):
## lock приобретается только поверх свободной игры, перелок в _process,
## возврат только своего, под ЧУЖИМ окном мышь отдаётся наружу.
## Отличие от лавки (вердикт): «бой не паузится, но скиллы с хотбара живут» —
## под НАШИМ локом скилл-клавиши 1–4 и зелье (Q) проводятся в world.gd
## сквозь окно (там же — страховка от ложного разлока); движение, атака и
## остальные клавиши мира заморожены, как в лавке.
## остальное — через world-страховку); экипация — клик по вещи в сумке или
## по слоту (вердикт §2: «надеть/снять кликом»), заточка — кнопка под слотом
## оружия (вердикт §4); подсветка редкости — цветной кант клетки (вердикт
## 16.11 22:56): синий редкий, фиолетовый очень редкий, оранжевый легендарный.

static var I: Inventory = null

const COLS := 6                 # сетка 6×2 = 12 ячеек (вердикт)
const ROWS := 2
const Alch := preload("res://scripts/alchemy.gd")

var root: Control
var dim: ColorRect
var panel: PanelContainer
var head_lbl: Label
var grid: GridContainer
var hint_lbl: Label
var close_btn: Button
var cells: Array = []           # {btn: Button, cnt: Label, kind: Dictionary}
# --- g20b: экипировка (правая колонка) + сумка снаряжения (под сеткой) ---
# t10 (вердикт 25.11 «воину мечи и щиты»): слот shield — РЯДОМ с оружием.
const SLOT_ORDER := ["weapon", "shield", "armor", "relic"]
const SLOT_NAMES := {"weapon": "Оружие", "shield": "Щит", "armor": "Броня", "relic": "Оберег"}
const BAG_CELLS := 12           # 6×2 — как сетка расходников (физических
                                # экипируемых вещей в реестре 17 с t10, но
                                # в одном забеге их не бывает больше дюжины;
                                # кап сумки в сейве — 12, см. from_dict)
var bag_grid: GridContainer
var bag_cells: Array = []       # {btn: Button, mark: Label} — id в bag_ids
var bag_ids: Array = []         # порядок id, обновляется в refresh
var slot_btns := {}             # slot -> Button
var sharpen_btn: Button
var hero_img: TextureRect
var _rarity_styles := {}        # кэш StyleBoxFlat по (normal, rarity)
var ui_frame_tex: Texture2D = null
var _holds_lock := false        # input_locked сейчас принадлежит окну
var _mouse_pass := false        # мышь принадлежит чужому окну (окно пропускает)

# --- строки сетки: icon — рисовалка UiIcons, kind — резолвер количества ---
# Порядок стабилен (пины ссылаются на индексы). Ячейки-квесты (ключ/амулет) —
# единицы: их нельзя «использовать», они показывают ношу.
static func grid_kinds() -> Array:
	return [
		{"icon": "herb", "name": "Лесное зелье (травы)", "use": "potion"},
		{"icon": "brewed", "name": "Крепкое зелье", "use": "brewed"},
		{"icon": "torch", "name": "Факел"},
		{"icon": "root", "name": "Сухоцвет", "mat": "suhotsvet"},
		{"icon": "herb", "name": "Жим", "mat": "zhim"},
		{"icon": "resin", "name": "Смола", "mat": "smola"},
		# g20b: амулет уехал из сетки в экипировку (слот «Оберег» + сумка
		# снаряжения), ряд занял точильный камень — валюта заточки.
		{"icon": "whet", "name": "Точильный камень", "mat": "whet"},
		{"icon": "hide", "name": "Шкура слизня", "mat": "hide"},
		{"icon": "sinew", "name": "Волчья жила", "mat": "sinew"},
		{"icon": "key", "name": "Ключ пещеры", "quest": "key"},
	]

## Количество для строки сетки (единственные источники истины).
static func count_of(k: Dictionary) -> int:
	if k.has("mat"):
		return GameState.mat_count(String(k["mat"]))
	match String(k.get("icon", "")):
		"herb":
			return GameState.herbs  # строка «Лесное зелье (травы)»
		"brewed":
			return GameState.brewed_potions
		"torch":
			return GameState.torches
		"key":
			return 1 if GameState.has_key else 0
	return 0

func _enter_tree() -> void:
	if I == null:
		I = self

func _exit_tree() -> void:
	# Выход из сцены с открытым окном не должен оставлять висячий lock.
	_release_lock()
	if I == self:
		I = null

func _ready() -> void:
	layer = 5  # тот же слой, что лавка: выше HUD (1), ниже фейда переходов (10)
	if ResourceLoader.exists("res://assets/ui/panel_frame.png"):
		ui_frame_tex = load("res://assets/ui/panel_frame.png")
	_build()

# --- статические обёртки (как Shop) ---

static func open() -> void:
	if I == null or I.root == null:
		return
	if I._busy():  # чужой диалог/модалка/лавка/журнал/lock — не открываемся
		GameAudio.sfx("ui_deny")
		return
	I._set_open(true)
	Sfx.play("panel_open")

static func close() -> void:
	if I != null and I.root != null:
		I._set_open(false)

static func is_open() -> bool:
	return I != null and I.root != null and I.root.visible

# --- построение панели ---

func _build() -> void:
	var th := Theme.new()
	UIFont.apply(th, 9)  # та же ступень, что витрина лавки
	root = Control.new()
	root.name = "InventoryRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.theme = th
	if ui_frame_tex != null:
		panel.add_theme_stylebox_override("panel", _ui_frame_style(6.0))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	head_lbl = Label.new()
	head_lbl.text = "Инвентарь"
	head_lbl.add_theme_font_size_override("font_size", 10)
	head_lbl.add_theme_color_override("font_color", Color(1, 0.84, 0.45))
	head_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head_lbl)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	# СЛЕВА — сетка 6×2 расходников (вердикт: «слева сетка 6x2 (12 ячеек)»)
	# + под ней сумка снаряжения 6×2 (g20b: вещи, которыми владеем; надетое
	# помечен — вердикт §2 «экипированное видно»).
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	hb.add_child(left)
	grid = GridContainer.new()
	grid.name = "InvGrid"
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	left.add_child(grid)
	for i in COLS * ROWS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(26, 28)
		btn.add_theme_stylebox_override("normal", _cell_style(true))
		btn.add_theme_stylebox_override("hover", _cell_style(false))
		btn.add_theme_stylebox_override("pressed", _cell_style(false))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(btn)
		var cnt := Label.new()
		cnt.add_theme_font_size_override("font_size", 8)
		cnt.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
		cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		cnt.add_theme_constant_override("outline_size", 3)
		# счётчик в углу ячейки (как «рюкзак N/5» в лавке — здесь угол клетки)
		cnt.position = Vector2(12, 16)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cnt)
		cells.append({"btn": btn, "cnt": cnt})
	# --- g20b: сумка снаряжения (6×2): владение вещью + метка «надето» ---
	var bag_head := Label.new()
	bag_head.name = "BagHead"
	bag_head.text = "Сумка снаряжения:"
	bag_head.add_theme_font_size_override("font_size", 9)
	bag_head.add_theme_color_override("font_color", Color(1, 0.84, 0.45))
	left.add_child(bag_head)
	bag_grid = GridContainer.new()
	bag_grid.name = "GearBag"
	bag_grid.columns = COLS
	bag_grid.add_theme_constant_override("h_separation", 2)
	bag_grid.add_theme_constant_override("v_separation", 2)
	left.add_child(bag_grid)
	for i in BAG_CELLS:
		var bbtn := Button.new()
		bbtn.custom_minimum_size = Vector2(26, 28)
		bbtn.add_theme_stylebox_override("normal", _cell_style(true))
		bbtn.add_theme_stylebox_override("hover", _cell_style(false))
		bbtn.add_theme_stylebox_override("pressed", _cell_style(false))
		bbtn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		bbtn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bbtn.pressed.connect(_on_bag_pressed.bind(i))
		bag_grid.add_child(bbtn)
		var mark := Label.new()
		mark.add_theme_font_size_override("font_size", 8)
		mark.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
		mark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		mark.add_theme_constant_override("outline_size", 3)
		mark.position = Vector2(15, 15)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bbtn.add_child(mark)
		bag_cells.append({"btn": bbtn, "mark": mark})
	# СПРАВА — силуэт героя и три слоты экипировки (вердикт §2: «справа от
	# сетки — герой и слоты Оружие/Броня/Оберег, клик надевает/снимает»).
	var right := VBoxContainer.new()
	right.name = "GearColumn"
	right.add_theme_constant_override("separation", 3)
	hb.add_child(right)
	hero_img = TextureRect.new()
	hero_img.name = "HeroSil"
	hero_img.texture = icon_tex("hero")
	hero_img.custom_minimum_size = Vector2(56, 42)
	hero_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hero_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(hero_img)
	for slot in SLOT_ORDER:
		var cap := Label.new()
		cap.name = "Cap_" + slot
		cap.text = String(SLOT_NAMES[slot])
		cap.add_theme_font_size_override("font_size", 8)
		cap.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		right.add_child(cap)
		var sbtn := Button.new()
		sbtn.name = "Slot_" + slot
		sbtn.custom_minimum_size = Vector2(56, 28)
		sbtn.add_theme_stylebox_override("normal", _cell_style(true))
		sbtn.add_theme_stylebox_override("hover", _cell_style(false))
		sbtn.add_theme_stylebox_override("pressed", _cell_style(false))
		sbtn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		sbtn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sbtn.pressed.connect(_on_slot_pressed.bind(String(slot)))
		right.add_child(sbtn)
		slot_btns[String(slot)] = sbtn
	sharpen_btn = Button.new()
	sharpen_btn.name = "SharpenBtn"
	sharpen_btn.custom_minimum_size = Vector2(56, 0)
	sharpen_btn.pressed.connect(_on_sharpen_pressed)
	right.add_child(sharpen_btn)
	hint_lbl = Label.new()
	hint_lbl.text = "Клик по зелью — использовать.\nВещь из сумки — надеть,\nклик по слоту — снять."
	hint_lbl.add_theme_font_size_override("font_size", 8)
	hint_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hint_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(hint_lbl)
	close_btn = Button.new()
	close_btn.text = "Закрыть (I)"
	close_btn.pressed.connect(_on_close_pressed)
	vb.add_child(close_btn)

## Стиль ячейки: дерево-слот как карточка лавки (Panel-подложка + кант).
func _cell_style(normal: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.11, 0.10) if normal else Color(0.19, 0.16, 0.13)
	sb.border_color = Color(0.42, 0.30, 0.17)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(2.0)
	return sb

## 9-slice рамка — та же примитива, что витрина лавки (общий frame-стиль).
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

# --- открытие/закрытие / владение lock (паттерн Shop) ---

func _set_open(v: bool) -> void:
	if root.visible != v:
		root.visible = v
		root.mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
		_mouse_pass = false
		if v:
			_set_mouse_pass(false)
		GameAudio.sfx("ui_confirm" if v else "ui_click")
		if v:
			_acquire_lock()
		else:
			_release_lock()
	if v:
		refresh()

## Иконка строки сетки: «brewed» — колба UiIcons (её рисует brewed_icon,
## не item_icon), прочие — общие предметные рисовалки. Texture кэшируются:
## brewed_icon() каждый раз создаёт ImageTexture.
var _icon_cache := {}

func icon_tex(icon_id: String) -> Texture2D:
	if _icon_cache.has(icon_id):
		return _icon_cache[icon_id]
	var t: Texture2D = UiIcons.brewed_icon() if icon_id == "brewed" \
			else UiIcons.item_icon(icon_id)
	_icon_cache[icon_id] = t
	return t

func _acquire_lock() -> void:
	GameState.input_locked = true
	_holds_lock = true

func _release_lock() -> void:
	if _holds_lock and not _ui_windows_open():
		GameState.input_locked = false
	_holds_lock = false

## Страховка (паттерн Shop): если внешний код снял lock — возвращаем, пока
## окно открыто и чужие окна чисты.
func _process(_delta: float) -> void:
	if root == null or not root.visible:
		return
	# бой не паузится (вердикт) — подбор/траты летят, пока окно открыто:
	# сетка обновляется каждый кадр (12 ярлыков, копейки)
	refresh()
	var pass_thru := _external_lock()
	if pass_thru != _mouse_pass:
		_mouse_pass = pass_thru
		_set_mouse_pass(pass_thru)
	if not GameState.input_locked and not _ui_windows_open():
		GameState.input_locked = true
		_holds_lock = true

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
	if Shop.is_open():
		return true
	for c in p.get_children():
		if c is Journal and c.is_open():
			return true
	return false

func _external_lock() -> bool:
	return _ui_windows_open() or (GameState.input_locked and not _holds_lock)

func _busy() -> bool:
	return GameState.input_locked or _ui_windows_open()

func _set_mouse_pass(passthrough: bool) -> void:
	if root == null:
		return
	_apply_pass(root, passthrough)

func _apply_pass(c: Control, passthrough: bool) -> void:
	if c == root or c == dim or c == panel or c is Button:
		var want := Control.MOUSE_FILTER_IGNORE if passthrough else Control.MOUSE_FILTER_STOP
		if c.mouse_filter != want:
			c.mouse_filter = want
	for ch in c.get_children():
		if ch is Control:
			_apply_pass(ch as Control, passthrough)

# --- ввод ---

## Открытая панель модальна по вводу, НО (вердикт) скилл-клавиши 1–4 и Q-зелье
## проводятся к миру: world.gd узнаёт «наш» lock по Inventory.is_open() и
## пропускает ровно эти действия. Всё остальное (движение — через lock в
## player.gd, E, F5/F9, Esc чужих окон) гасится здесь же, как в лавке.
func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		# закрытое окно: только клавиша I (физическая — раскладка не важна,
		# паттерн KEY_J в journal.gd); чужой lock/окно — отказ внутри open().
		if event is InputEventKey and event.pressed and not event.echo \
				and event.physical_keycode == KEY_I:
			if not _busy():
				open()
				get_viewport().set_input_as_handled()
		return
	if _external_lock():
		return  # поверх встало чужое окно — не глушим его
	if event.is_action_pressed("potion"):
		return  # живёт: world обработает (гейт снят для нашего окна)
	for i in 4:
		if event.is_action_pressed("skill_%d" % (i + 1)):
			return  # живёт
	if (event is InputEventKey and event.pressed and not event.echo
			and (event.physical_keycode == KEY_I
					or event.is_action_pressed("ui_cancel"))):
		close()
	get_viewport().set_input_as_handled()

func _on_dim_input(event: InputEvent) -> void:
	if _external_lock():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

func _on_close_pressed() -> void:
	close()

## Клик по ячейке: расходник — использовать (вердикт §1 «клик по вещи —
## использовать, если расходник»), остальное — просто тик (экипация — Б).
func _on_cell_pressed(i: int) -> void:
	if _external_lock():
		return
	if i < 0 or i >= cells.size():
		return
	var kk: Array = grid_kinds()
	if i >= kk.size():
		return  # пустая заготовка ячейки (строк меньше 12)
	var k: Dictionary = kk[i]
	var use := String(k.get("use", ""))
	if use == "potion":
		var p := get_parent()
		if p != null and p.has_method("drink_potion"):
			p.drink_potion()
		else:
			GameAudio.sfx("ui_click")
	elif use == "brewed":
		Alch.drink_brewed()
	else:
		GameAudio.sfx("ui_click")

# --- g20b: экипировка (надеть/снять/заточить) ---

## Порядок сумки — канон реестра ITEMS (не порядок приобретения): сумка не
## «прыгает» при дропе, пины ссылаются на стабильные индексы.
static func gear_view_ids() -> Array:
	var out: Array = []
	for id in GearData.ITEMS:
		if GameState.owned_gear.has(String(id)):
			out.append(String(id))
	return out

static func _is_equipped(id: String) -> bool:
	var sl := String(GearData.item(id).get("slot", ""))
	return sl != "" and GearData.equipped_id(GameState, sl) == id

## Честная строка предмета (вердикт §3: «формула видна: „Урон 8 + 4“»).
## Для НАДЕТОГО оружия «часть» считается реальной разницей формулы — в неё
## честное число включает и заточку; для вещи в сумке — номинал реестра.
func item_tip(id: String) -> String:
	var it := GearData.item(id)
	var nm := String(it.get("name", id))
	# t17 (DESIGN_DEPTH_V2 §1, 25.11): качество-инстанс (добротная/реликтовая)
	# в имени важнее статной редкости; без аффиксов строка прежняя 1:1.
	var qn := GearData.quality_name(GameState, id)
	var rn := qn if qn != "" else GearData.rarity_name(id)
	if rn != "":
		nm += " (%s)" % rn
	# t17: честные строки аффиксов («Острый край: урон +10%») — хвостом,
	# после слотной строки; их порядок = порядок ролла.
	var af := GearData.affix_lines(GameState, id)
	var tip := nm
	match String(it.get("slot", "")):
		"weapon":
			var t := GearData.sharpen_tier_of(GameState, id)
			var tail := ""
			if t > 0:
				tail = ". Заточка %d/%d (+%d%%)" % [t, GearData.SHARPEN_MAX, GearData.sharpen_pct(t)]
			# t10 (25.11): посох, кроме урона, поднимает потолок маны — видно
			# в подсказке (число из реестра, «формула честная и видна»).
			var mb := int(it.get("mana_bonus", 0))
			if mb > 0:
				tail += ". Мана +%d" % mb
			if _is_equipped(id):
				var part := GearData.weapon_part(GameState)
				tip = "%s: Урон %d + %d%s" % [nm, GameState.damage - part, part, tail]
			elif it.has("dmg_bonus"):
				tip = "%s: Урон +%d%s" % [nm, int(it["dmg_bonus"]), tail]
			else:
				tip = "%s: Урон ×%.1f%s" % [nm, float(it.get("dmg_mult", 1.0)), tail]
		"armor":
			tip = "%s: держит %d урона, минимум 1 проходит" % [nm, int(it.get("armor_bonus", 0))]
		"shield":
			# t10: щит — тот же плоский канал, что броня (min 1 проходит)
			tip = "%s: держит %d урона, минимум 1 проходит" % [nm, int(it.get("armor_bonus", 0))]
		"relic":
			tip = "Амулет Леса: подсветка и +1 урон. Работает и без слота."
	if af != "":
		tip += "\n" + af
	return tip

## Клик по вещи в сумке: надеть (или снять, если уже надето — вердикт §2).
func _on_bag_pressed(i: int) -> void:
	if _external_lock():
		return
	if i < 0 or i >= bag_ids.size():
		GameAudio.sfx("ui_click")
		return
	var id := String(bag_ids[i])
	var slot := String(GearData.item(id).get("slot", ""))
	if slot == "":
		return
	if _is_equipped(id):
		GameState.unequip_slot(slot)
		GameAudio.sfx("ui_click")
	else:
		# t10 (вердикт 25.11): матрица канона на входе — отказ с причиной,
		# НЕ молча (сам гейт живёт в GameState.equip_item; здесь штатный
		# ui_deny + тот же текст, что вернул бы backstop-гейт).
		var gate: Dictionary = GearData.can_equip(GameState.class_id, id)
		if not bool(gate.get("ok", true)):
			GameAudio.sfx("ui_deny")
			GameState.toast.emit(String(gate.get("reason", "Не твоя рука.")))
			refresh()
			return
		GameState.equip_item(slot, id)
		GameState.stats_changed.emit()  # armor/relic equip_item не эмитит (паттерн Shop)
		GameAudio.sfx("belt")
	refresh()

## Клик по слоту: снять в сумку; пустой слот — только отказ-подсказка.
func _on_slot_pressed(slot: String) -> void:
	if _external_lock():
		return
	var cur := GearData.equipped_id(GameState, slot)
	if cur == "":
		GameAudio.sfx("ui_deny")
		GameState.toast.emit("%s: пусто. Клик по вещи в сумке наденет её." % String(SLOT_NAMES[slot]))
	else:
		GameState.unequip_slot(slot)
		GameAudio.sfx("ui_click")
	refresh()

## «Точить» (вердикт п.4): ступень +5/+7/+10/+12/+15% за 1..5 камней, без
## рандума и без потери прогресса; камни списывает sharpen_weapon (отказ —
## собственный тост с нехваткой).
func _on_sharpen_pressed() -> void:
	if _external_lock():
		return
	if GearData.sharpen_weapon(GameState):
		GameAudio.sfx("ui_confirm")
	refresh()

# --- наполнение сетки ---

## Перерисовать 12 ячеек по источникам истины. Пустая стопка = пустая клетка
## (ни иконки, ни счётчика): «пустой инвентарь = пустые слоты» (вердикт).
func refresh() -> void:
	if grid == null:
		return
	var kk: Array = grid_kinds()
	for i in cells.size():
		var cell: Dictionary = cells[i]
		var btn: Button = cell["btn"]
		var cnt: Label = cell["cnt"]
		if i >= kk.size():
			btn.icon = null
			btn.tooltip_text = ""
			cnt.text = ""
			continue
		var k: Dictionary = kk[i]
		var n := count_of(k)
		if n <= 0:
			btn.icon = null
			btn.tooltip_text = String(k["name"]) + ": пусто"
			cnt.text = ""
			continue
		btn.icon = icon_tex(String(k["icon"]))
		btn.tooltip_text = String(k["name"]) + ": " + str(n)
		cnt.text = str(n)
	_refresh_gear()

## g20b: сумка снаряжения + слоты + кнопка заточки. Пустая клетка сумки —
## просто пустая; надетое помечено галочкой (вердикт §2 «экипированное видно»).
func _refresh_gear() -> void:
	if bag_grid == null:
		return
	bag_ids = gear_view_ids()
	for i in bag_cells.size():
		var cell: Dictionary = bag_cells[i]
		var bbtn: Button = cell["btn"]
		var mark: Label = cell["mark"]
		if i >= bag_ids.size():
			bbtn.icon = null
			bbtn.tooltip_text = ""
			mark.text = ""
			bbtn.add_theme_stylebox_override("normal", _cell_style(true))
			continue
		var id := String(bag_ids[i])
		bbtn.icon = icon_tex(id)
		var eq := _is_equipped(id)
		mark.text = "✓" if eq else ""
		bbtn.tooltip_text = item_tip(id) + ("\nНадето — клик снимет." if eq else "\nКлик наденет.")
		bbtn.add_theme_stylebox_override("normal",
				_rarity_style(true, GearData.display_rarity(GameState, id)))  # t17: качество-инстанс
	for slot in SLOT_ORDER:
		var sbtn: Button = slot_btns[slot]
		var cur := GearData.equipped_id(GameState, slot)
		if cur == "":
			sbtn.icon = null
			sbtn.tooltip_text = "%s: пусто. Клик по вещи в сумке наденет её." % String(SLOT_NAMES[slot])
			sbtn.add_theme_stylebox_override("normal", _rarity_style(true, ""))
		else:
			sbtn.icon = icon_tex(cur)
			sbtn.tooltip_text = item_tip(cur) + "\nКлик снимет в сумку."
			sbtn.add_theme_stylebox_override("normal",
					_rarity_style(true, GearData.display_rarity(GameState, cur)))  # t17: качество-инстанс
	# Кнопка заточки: активна на НАДЕТОМ оружии, камни хватает, ступень < 5.
	var wid := GearData.equipped_id(GameState, "weapon")
	var valid := wid != "" and String(GearData.item(wid).get("slot", "")) == "weapon"
	var t := GearData.sharpen_tier_of(GameState, wid)
	if not valid:
		sharpen_btn.text = "Точить: нечего"
		sharpen_btn.disabled = true
		sharpen_btn.tooltip_text = "Затачивается надетое оружие."
	elif t >= GearData.SHARPEN_MAX:
		sharpen_btn.text = "Заточка %d/%d (+%d%%)" % [t, GearData.SHARPEN_MAX, GearData.sharpen_pct(t)]
		sharpen_btn.disabled = true
		sharpen_btn.tooltip_text = "Дальше некуда."
	else:
		var cost := GearData.sharpen_cost(t)
		var have := GameState.mat_count("whet")
		sharpen_btn.text = "Точить — %d кам." % cost
		sharpen_btn.disabled = have < cost
		sharpen_btn.tooltip_text = "Ступень %d: +%d%% к урону (всего станет +%d%%). Без рандума и потери. Камни: %d/%d." % [
			t + 1, GearData.SHARPEN_STEP_PCT[t], GearData.sharpen_pct(t + 1), have, cost]

## Кант клетки по редкости (вердикт 16.11 22:56): обычный — прежний кожаный
## кант; редкий/очень редкий/легендарный — цветная рамка в 2 px. Кэш по
## (normal, rarity): StyleBox создаётся один раз на пару, не на кадр.
func _rarity_style(normal: bool, rarity: String) -> StyleBoxFlat:
	var key := ("%d|%s" % [1 if normal else 0, rarity])
	if _rarity_styles.has(key):
		return _rarity_styles[key]
	var sb := _cell_style(normal)
	if rarity != "" and GearData.RARITY_COLORS.has(rarity):
		sb.border_color = GearData.RARITY_COLORS[rarity]
		sb.set_border_width_all(2)
	_rarity_styles[key] = sb
	return sb
