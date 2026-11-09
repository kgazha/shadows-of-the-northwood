extends CanvasLayer
## HUD: сердца HP, полоса опыта, задания, диалоги с эффектом печати, тосты,
## модалка «Выбери героя» и панель скиллов (спринт 2).

const Classes := preload("res://scripts/classes_data.gd")

const NAMES := {
	"hero": "Герой", "elder": "Старейшина", "merchant": "Торговец",
	"farmer": "Фермер", "hermit": "Отшельник Геральд", "narr": "",
}
const PORTRAITS := {"hero": 0, "elder": 40, "merchant": 80}
const PORTRAIT_SIZE := 40
# индекс портрета отшельника в portraits2.png (ассет рисует соседняя команда)
const PORTRAITS2_INDEX := {"hermit": 0}

const SLOT := 28.0  # размер слота иконки скилла

var world: Node2D
var heart_row: HBoxContainer
var xp_bg: ColorRect
var xp_fill: ColorRect
var info: Label
var quests: Label
var toast_lbl: Label
var toast_t := 0.0
var panel: PanelContainer
var portrait: TextureRect
var dname: Label
var dtext: RichTextLabel
var lines: Array = []
var li := 0
var typing := false
var chars_shown := 0.0
var on_end: Callable = Callable()
var hearts_tex: Texture2D
var portraits_tex: Texture2D
var portraits2_tex: Texture2D
# --- спринт 2 ---
var skill_icons_tex: Texture2D
var skill_panel: PanelContainer
var skill_slots: Array = []     # словари {root, icon, cd, lvl_lbl}
var switch_btn: Button
var modal: Control
var modal_shown := false
var class_chosen_cb := Callable()

func setup(p_world: Node2D) -> void:
	world = p_world
	hearts_tex = load("res://assets/heart.png")
	portraits_tex = load("res://assets/portraits.png")
	# portraits2.png рисует параллельная команда — может отсутствовать, это штатно
	if ResourceLoader.exists("res://assets/portraits2.png"):
		portraits2_tex = load("res://assets/portraits2.png")
	else:
		push_warning("Нет ассета: assets/portraits2.png — отшельник без портрета")
	var th := Theme.new()
	th.default_font_size = 8
	heart_row = HBoxContainer.new()
	heart_row.add_theme_constant_override("separation", 2)
	xp_bg = ColorRect.new()
	xp_bg.color = Color(0.08, 0.08, 0.1, 0.85)
	xp_bg.size = Vector2(130, 8)
	xp_bg.custom_minimum_size = Vector2(130, 8)
	xp_fill = ColorRect.new()
	xp_fill.color = Color(0.35, 0.85, 0.4)
	xp_fill.position = Vector2(1, 1)
	xp_bg.add_child(xp_fill)
	info = Label.new()
	quests = Label.new()
	var top := VBoxContainer.new()
	top.position = Vector2(6, 6)
	top.add_theme_constant_override("separation", 3)
	top.add_child(heart_row)
	top.add_child(xp_bg)
	top.add_child(info)
	top.add_child(quests)
	top.theme = th
	add_child(top)

	toast_lbl = Label.new()
	toast_lbl.position = Vector2(0, 30)
	toast_lbl.size = Vector2(640, 12)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_color_override("font_color", Color(1, 1, 0.75))
	toast_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	toast_lbl.add_theme_constant_override("outline_size", 4)
	toast_lbl.theme = th
	add_child(toast_lbl)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 8
	panel.offset_right = -8
	panel.offset_top = -66
	panel.offset_bottom = -8
	dname = Label.new()
	dname.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	dtext = RichTextLabel.new()
	dtext.bbcode_enabled = false
	dtext.custom_minimum_size = Vector2(0, 40)
	dtext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(40, 40)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(dname)
	vb.add_child(dtext)
	hbox.add_child(portrait)
	hbox.add_child(vb)
	panel.add_child(hbox)
	panel.theme = th
	add_child(panel)
	panel.visible = false

	_build_skill_panel(th)
	_build_class_modal(th)

	GameState.stats_changed.connect(refresh)
	GameState.quest_changed.connect(refresh)
	GameState.toast.connect(show_toast)
	GameState.leveled_up.connect(_on_leveled_up)
	refresh()
	refresh_skills()

func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			toast_lbl.text = ""
	if typing:
		chars_shown += delta * 45.0
		if chars_shown >= float(dtext.get_total_character_count()):
			chars_shown = 1e9
			typing = false
		dtext.visible_characters = int(chars_shown)
	_update_skill_states()

func refresh() -> void:
	for c in heart_row.get_children():
		c.queue_free()
	var hearts := int(ceil(GameState.max_hp / 2.0))
	for i in hearts:
		var tr := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = hearts_tex
		if GameState.hp >= (i + 1) * 2:
			at.region = Rect2(0, 0, 7, 6)
		elif GameState.hp == i * 2 + 1:
			at.region = Rect2(0, 0, 4, 6)
		else:
			at.region = Rect2(0, 0, 7, 6)
			tr.modulate = Color(0.3, 0.15, 0.18, 0.9)
		tr.texture = at
		heart_row.add_child(tr)
	xp_fill.size = Vector2(maxf(0.0, 128.0 * GameState.xp / float(GameState.xp_next)), 6)
	info.text = "Ур. %d  Опыт %d/%d  Атака %d" % [GameState.level, GameState.xp, GameState.xp_next, GameState.damage]
	var q: Array[String] = []
	if GameState.elder_quest == 0:
		q.append("• Поговори со старейшиной")
	elif GameState.elder_quest == 1:
		if GameState.herbs >= 3:
			q.append("• Травы собраны — отнеси старейшине!")
		else:
			q.append("• Травы старейшине: %d/3" % GameState.herbs)
	if GameState.slime_quest == 1:
		if GameState.slime_kills >= 3:
			q.append("• Награда ждёт у торговца!")
		else:
			q.append("• Слаймы для торговца: %d/3" % GameState.slime_kills)
	match GameState.cave_state:
		0:
			q.append("• Осквернённый гром: найди отшельника в пещере")
		1:
			if GameState.boss_defeated:
				q.append("• Гром повержен — доложи отшельнику")
			else:
				q.append("• Осквернённый гром: одолей его в алтарном зале пещеры")
		2:
			q.append("• Вернись к отшельнику в пещеру")
		3:
			if GameState.has_amulet:
				q.append("• Отнеси Амулет Леса Геральду")
			else:
				q.append("• Открой сундук за запертой дверью (нужен ключ)")
	quests.text = ("Задания:\n" + "\n".join(q)) if not q.is_empty() else ""

func show_toast(text: String) -> void:
	toast_lbl.text = text
	toast_t = 3.0

func show_dialog(arr: Array, cb: Callable) -> void:
	lines = arr
	li = 0
	on_end = cb
	GameState.input_locked = true
	panel.visible = true
	_show_line()

func _show_line() -> void:
	var ln: Dictionary = lines[li]
	var who := String(ln.get("who", "narr"))
	dname.text = String(NAMES.get(who, who))
	dtext.text = String(ln.get("text", ""))
	var atlas: Texture2D = null
	var px := -1
	if PORTRAITS.has(who):
		atlas = portraits_tex
		px = int(PORTRAITS[who])
	elif PORTRAITS2_INDEX.has(who) and portraits2_tex != null:
		atlas = portraits2_tex
		px = int(PORTRAITS2_INDEX[who])
	if atlas != null and px >= 0:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(px, 0, PORTRAIT_SIZE, PORTRAIT_SIZE)
		portrait.texture = at
		portrait.visible = true
	else:
		portrait.visible = false
	chars_shown = 0.0
	dtext.visible_characters = 0
	typing = true

func is_dialog_open() -> bool:
	return panel.visible

func is_modal_open() -> bool:
	return modal_shown

func advance() -> void:
	if typing:
		typing = false
		dtext.visible_characters = -1
		return
	li += 1
	if li >= lines.size():
		panel.visible = false
		GameState.input_locked = false
		var cb := on_end
		on_end = Callable()
		if cb.is_valid():
			cb.call()
	else:
		_show_line()

# --- панель скиллов ---

func _build_skill_panel(th: Theme) -> void:
	if ResourceLoader.exists("res://assets/skill_icons.png"):
		skill_icons_tex = load("res://assets/skill_icons.png")
	else:
		push_warning("Нет ассета: assets/skill_icons.png — панель скиллов без иконок")
	skill_panel = PanelContainer.new()
	skill_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skill_panel.offset_left = -70
	skill_panel.offset_right = 70
	skill_panel.offset_top = -92
	skill_panel.offset_bottom = -64
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	skill_panel.add_child(hb)
	for i in 4:
		var sc := Control.new()
		sc.custom_minimum_size = Vector2(SLOT, SLOT)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.scale = Vector2(1.5, 1.5)  # 16 px -> 24 px, фильтр nearest из проекта
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.gui_input.connect(_on_skill_slot_input.bind(i))
		sc.add_child(icon)
		var cdc := ColorRect.new()
		cdc.color = Color(0, 0, 0, 0.65)
		cdc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cdc.size = Vector2(SLOT, 0)
		sc.add_child(cdc)
		var lvl := Label.new()
		lvl.add_theme_font_size_override("font_size", 7)
		lvl.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
		lvl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lvl.add_theme_constant_override("outline_size", 3)
		lvl.position = Vector2(2, 15)
		lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(lvl)
		var hot := Label.new()
		hot.add_theme_font_size_override("font_size", 7)
		hot.add_theme_color_override("font_color", Color(1, 1, 0.7, 0.9))
		hot.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		hot.add_theme_constant_override("outline_size", 3)
		hot.position = Vector2(1, -1)
		hot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(hot)
		hb.add_child(sc)
		skill_slots.append({"root": sc, "icon": icon, "cd": cdc, "lvl": lvl, "hot": hot})
	skill_panel.theme = th
	add_child(skill_panel)
	# кнопка смены класса — правый верхний угол
	switch_btn = Button.new()
	switch_btn.text = "Сменить класс"
	switch_btn.add_theme_font_size_override("font_size", 8)
	switch_btn.position = Vector2(548, 6)
	switch_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	switch_btn.pressed.connect(_on_class_switch)
	switch_btn.theme = th
	add_child(switch_btn)

## Перестроить иконки под текущий класс (после выбора/смены класса, загрузки сейва).
func refresh_skills() -> void:
	var has := GameState.class_id != ""
	if skill_panel != null:
		skill_panel.visible = has
	if switch_btn != null:
		switch_btn.visible = has
	if not has:
		return
	var sids: Array = Classes.skills_for(GameState.class_id)
	for i in 4:
		var sd := Classes.skill(String(sids[i]))
		var slot: Dictionary = skill_slots[i]
		var icon: TextureRect = slot["icon"]
		if skill_icons_tex != null:
			var at := AtlasTexture.new()
			at.atlas = skill_icons_tex
			at.region = Rect2(int(sd.icon) * 16, 0, 16, 16)
			icon.texture = at
		icon.tooltip_text = "%s — ур. %d, КД %.0f с\n%s" % [sd.name, sd.level, sd.cd, sd.desc]
		slot["hot"].text = str(i + 1)

func _update_skill_states() -> void:
	if skill_panel == null or not skill_panel.visible or GameState.class_id == "":
		return
	var sids: Array = Classes.skills_for(GameState.class_id)
	var p = world.player if world != null else null
	for i in 4:
		var sd := Classes.skill(String(sids[i]))
		var slot: Dictionary = skill_slots[i]
		var locked: bool = GameState.level < int(sd.level)
		slot["icon"].modulate = Color(0.45, 0.45, 0.5) if locked else Color.WHITE
		slot["lvl"].text = ("замк. ур.%d" % int(sd.level)) if locked else ""
		var frac := 0.0
		if p != null and float(p.skill_cd[i]) > 0.0:
			frac = clampf(float(p.skill_cd[i]) / float(sd.cd), 0.0, 1.0)
		# шторка уходит снизу вверх: тёмной остаётся верхняя часть
		slot["cd"].size = Vector2(SLOT, SLOT * frac)

func _on_skill_slot_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if world != null and world.player != null:
			world.player.cast_skill(i, world.get_global_mouse_position())

func _on_leveled_up(lv: int) -> void:
	if GameState.class_id == "":
		return
	for sid in Classes.skills_for(GameState.class_id):
		var sd := Classes.skill(String(sid))
		if int(sd.level) == lv:
			GameState.toast.emit("Новый навык: %s!" % sd.name)

# --- модалка «Выбери героя» ---

func _build_class_modal(th: Theme) -> void:
	modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vb)
	var title := Label.new()
	title.text = "Выбери героя"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(cards)
	for id in Classes.CLASSES:
		cards.add_child(_make_class_card(String(id), th))
	modal.theme = th
	add_child(modal)

func _make_class_card(id: String, th: Theme) -> Control:
	var cd: Dictionary = Classes.CLASSES[id]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(140, 118)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var spr := TextureRect.new()
	spr.custom_minimum_size = Vector2(48, 48)
	spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	spr.scale = Vector2(3, 3)  # кадр 16 px -> 48 px, nearest из настроек проекта
	var path := String(cd.sprites)
	if ResourceLoader.exists(path):
		var at := AtlasTexture.new()
		at.atlas = load(path)
		at.region = Rect2(0, 0, 16, 16)  # кадр простоя (down)
		spr.texture = at
	else:
		push_warning("Нет ассета: %s — карточка класса без спрайта" % path)
	v.add_child(spr)
	for t in [
		[String(cd.name), 11, Color(1, 0.9, 0.55)],
		[String(cd.desc1), 8, Color.WHITE],
		[String(cd.desc2), 8, Color.WHITE],
		[String(cd.bonus), 8, Color(0.6, 1.0, 0.6)],
	]:
		var lb := Label.new()
		lb.text = String(t[0])
		lb.add_theme_font_size_override("font_size", int(t[1]))
		lb.add_theme_color_override("font_color", t[2])
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size = Vector2(128, 0)
		v.add_child(lb)
	card.add_child(v)
	# клики — по самой карточке, все дети не перехватывают мышь
	for ch in [v, spr]:
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lb in v.get_children():
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.gui_input.connect(_on_card_input.bind(id))
	card.mouse_entered.connect(func(): card.modulate = Color(1.25, 1.25, 1.25))
	card.mouse_exited.connect(func(): card.modulate = Color.WHITE)
	card.theme = th
	return card

func _on_card_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick_class(id)

func show_class_modal(cb: Callable = Callable()) -> void:
	modal_shown = true
	class_chosen_cb = cb
	GameState.input_locked = true
	modal.visible = true

func _pick_class(id: String) -> void:
	if not modal_shown:
		return
	GameState.set_class(id)
	if world != null and world.player != null:
		world.player.apply_class()
	modal.visible = false
	modal_shown = false
	GameState.input_locked = false
	GameState.toast.emit("Класс выбран: %s" % String(Classes.CLASSES[id].name))
	refresh_skills()
	if class_chosen_cb.is_valid():
		class_chosen_cb.call()
	class_chosen_cb = Callable()

func _on_class_switch() -> void:
	if is_dialog_open() or modal_shown:
		GameState.toast.emit("Сейчас нельзя сменить класс")
		return
	GameState.reset_progress_for_class_change()
	GameState.stats_changed.emit()
	GameState.toast.emit("Внимание: уровень и опыт будут сброшены до 1!")
	show_class_modal()
