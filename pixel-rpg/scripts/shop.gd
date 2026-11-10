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

var root: Control              # полноэкранный корень панели; visible = «лавка открыта»
var dim: ColorRect             # затемнение мира; клик мимо окна закрывает лавку
var panel: PanelContainer
var gold_lbl: Label
var buy_btns := {}             # item id -> Button («купить и надеть»)
var sell_btns := {}            # slot -> Button («продать надетое»)
var ui_frame_tex: Texture2D    # 9-slice рамка (assets/ui/panel_frame.png), опц.
var _holds_lock := false       # input_locked сейчас принадлежит лавке, а не кому-то ещё

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

# --- статические обёртки: хукам не нужна проверка I в каждом вызове ---

static func open() -> void:
	if I == null or I.root == null:
		return
	if I._busy():  # чужой диалог/модалка/журнал/lock — не открываемся (как SettingsMenu)
		GameAudio.sfx("ui_deny")
		return
	I._set_open(true)

static func close() -> void:
	if I != null and I.root != null:
		I._set_open(false)

static func is_open() -> bool:
	return I != null and I.root != null and I.root.visible

# --- построение панели ---

func _build() -> void:
	var th := Theme.new()
	th.default_font_size = 8
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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 0)
	panel.theme = th
	if ui_frame_tex != null:
		panel.add_theme_stylebox_override("panel", _ui_frame_style(5.0))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
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
	vb.add_child(_section_label("Витрина:"))
	for id in GearData.SHOP_STOCK:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_buy.bind(String(id)))
		vb.add_child(btn)
		buy_btns[String(id)] = btn
	vb.add_child(_section_label("Скупка (сдам надетое вдвое дешевле):"))
	for slot in ["weapon", "armor"]:
		var sbtn := Button.new()
		sbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sbtn.pressed.connect(_on_sell.bind(String(slot)))
		vb.add_child(sbtn)
		sell_btns[String(slot)] = sbtn
	var close_btn := Button.new()
	close_btn.text = "Закрыть (Esc)"
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)
	GameState.gold_changed.connect(refresh)
	refresh()

func _section_label(text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", 7)
	lb.add_theme_color_override("font_color", Color(0.85, 0.75, 0.6))
	return lb

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
		GameAudio.sfx("ui_confirm" if v else "ui_click")
		if v:
			_acquire_lock()
		else:
			_release_lock()
	if v:
		refresh()

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
	if root != null and root.visible and not GameState.input_locked and not _ui_windows_open():
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
	GameAudio.sfx("ui_confirm")
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
