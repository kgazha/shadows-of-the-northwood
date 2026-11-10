extends CanvasLayer
## HUD: полоска HP, полоса опыта, задания, диалоги с эффектом печати, тосты,
## этап создания героя (модалка выбора класса) и панель скиллов (спринт 2).

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
var hp_bg: ColorRect            # полоска здоровья (вместо сердец)
var hp_fill: ColorRect
var hp_txt: Label
var mana_bg: ColorRect          # полоска маны — только у мага
var mana_fill: ColorRect
var mana_txt: Label
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
var portraits_tex: Texture2D
var portraits2_tex: Texture2D
# --- спринт 2 ---
var skill_icons_tex: Texture2D
var skill_panel: PanelContainer
var skill_slots: Array = []     # словари {root, icon, cd, lvl_lbl}
var potion_btn: Button          # зелье из трав (Q)
var marker: Polygon2D           # стрелка к цели квеста
var marker_t := 0.0
var modal: Control
var modal_shown := false
var class_chosen_cb := Callable()

func setup(p_world: Node2D) -> void:
	world = p_world
	portraits_tex = load("res://assets/portraits.png")
	# portraits2.png рисует параллельная команда — может отсутствовать, это штатно
	if ResourceLoader.exists("res://assets/portraits2.png"):
		portraits2_tex = load("res://assets/portraits2.png")
	else:
		push_warning("Нет ассета: assets/portraits2.png — отшельник без портрета")
	var th := Theme.new()
	th.default_font_size = 8
	hp_bg = ColorRect.new()
	hp_bg.color = Color(0.08, 0.08, 0.1, 0.9)
	hp_bg.size = Vector2(130, 9)
	hp_bg.custom_minimum_size = Vector2(130, 9)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.72, 0.15, 0.18)
	hp_fill.position = Vector2(1, 1)
	hp_fill.size = Vector2(128, 7)
	hp_bg.add_child(hp_fill)
	hp_txt = Label.new()
	hp_txt.add_theme_font_size_override("font_size", 7)
	hp_txt.add_theme_color_override("font_color", Color(1, 0.92, 0.86))
	hp_txt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	hp_txt.add_theme_constant_override("outline_size", 3)
	hp_txt.position = Vector2(45, 1)
	hp_bg.add_child(hp_txt)
	# мана: та же ширина, синий цвет; полоска скрыта, пока max_mana == 0
	mana_bg = ColorRect.new()
	mana_bg.color = Color(0.08, 0.08, 0.12, 0.9)
	mana_bg.size = Vector2(130, 9)
	mana_bg.custom_minimum_size = Vector2(130, 9)
	mana_bg.visible = false
	mana_fill = ColorRect.new()
	mana_fill.color = Color(0.2, 0.4, 0.85)
	mana_fill.position = Vector2(1, 1)
	mana_fill.size = Vector2(128, 7)
	mana_bg.add_child(mana_fill)
	mana_txt = Label.new()
	mana_txt.add_theme_font_size_override("font_size", 7)
	mana_txt.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	mana_txt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	mana_txt.add_theme_constant_override("outline_size", 3)
	mana_txt.position = Vector2(45, 1)
	mana_bg.add_child(mana_txt)
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
	top.add_child(hp_bg)
	top.add_child(mana_bg)
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
	var dhint := Label.new()
	dhint.text = "ЛКМ / E — далее ▸"
	dhint.add_theme_font_size_override("font_size", 7)
	dhint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	dhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dhint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	dhint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dhint)
	panel.theme = th
	add_child(panel)
	panel.visible = false

	_build_skill_panel(th)
	_build_class_modal(th)
	# стрелка-указатель цели: рисуется на канвасе CanvasLayer = экранные координаты
	marker = Polygon2D.new()
	marker.polygon = PackedVector2Array([Vector2(9, 0), Vector2(-6, -6), Vector2(-3, 0), Vector2(-6, 6)])
	marker.color = Color(1.0, 0.84, 0.35, 0.9)
	marker.visible = false
	add_child(marker)

	GameState.stats_changed.connect(refresh)
	GameState.quest_changed.connect(refresh)
	GameState.toast.connect(show_toast)
	GameState.leveled_up.connect(_on_leveled_up)
	refresh()
	refresh_skills()
	# виньетка спринта «Атмосфера» — последний child CanvasLayer: поверх всей HUD, мышь не перехватывает
	var vign := TextureRect.new()
	vign.name = "Vignette"
	# дизайн-разрешение из project.godot (visible_rect на старте ещё не он); STRETCH_SCALE растянет под окно
	var dres := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	vign.texture = load("res://scripts/atmosphere.gd").make_vignette_texture(dres)
	vign.stretch_mode = TextureRect.STRETCH_SCALE
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vign)

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
	_update_marker(delta)

## Стрелка к цели: видна, только когда цель за краем экрана.
func _update_marker(delta: float) -> void:
	if marker == null or world == null or world.player == null:
		return
	if GameState.class_id == "" or GameState.input_locked or is_dialog_open() or is_modal_open():
		marker.visible = false
		return
	var tp: Vector2 = world.objective_pos()
	if tp == Vector2.INF:
		marker.visible = false
		return
	var xform := world.get_viewport().get_canvas_transform()
	var center := get_viewport().get_visible_rect().size * 0.5
	var d: Vector2 = xform * tp - center
	var half := center - Vector2(24, 24)
	if absf(d.x) < half.x and absf(d.y) < half.y:
		marker.visible = false  # цель на экране — стрелка не нужна
		return
	marker_t += delta
	var ad := Vector2(maxf(absf(d.x), 0.001), maxf(absf(d.y), 0.001))
	var t := minf(half.x / ad.x, half.y / ad.y)
	marker.position = center + d * t
	marker.rotation = d.angle()
	marker.color = Color(1.0, 0.84, 0.35, 0.75 + 0.2 * sin(marker_t * 5.0))
	marker.visible = true

func refresh() -> void:
	var max_hp := maxi(GameState.max_hp, 1)
	var frac := clampf(GameState.hp / float(max_hp), 0.0, 1.0)
	hp_fill.size = Vector2(maxf(0.0, 128.0 * frac), 7)
	# при низком здоровье полоса краснеет и чуть «пульсирует» оттенком
	if frac <= 0.3:
		hp_fill.color = Color(0.95, 0.22, 0.18)
	else:
		hp_fill.color = Color(0.72, 0.15, 0.18)
	hp_txt.text = "%d / %d" % [GameState.hp, max_hp]
	# мана — видна только тем, у кого она есть (маг)
	if GameState.max_mana > 0:
		mana_bg.visible = true
		var mf := clampf(GameState.mana / float(GameState.max_mana), 0.0, 1.0)
		mana_fill.size = Vector2(maxf(0.0, 128.0 * mf), 7)
		mana_txt.text = "%d / %d" % [GameState.mana, GameState.max_mana]
	else:
		mana_bg.visible = false
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
	if potion_btn != null:
		potion_btn.visible = GameState.class_id != ""
		potion_btn.text = "x%d" % GameState.herbs

func show_toast(text: String) -> void:
	toast_lbl.text = text
	toast_t = 3.0

func show_dialog(arr: Array, cb: Callable) -> void:
	if arr.is_empty():
		# пустая реплика (потерянный ключ диалога) — не блокируем ввод и не падаем
		if cb.is_valid():
			cb.call()
		return
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
	# прижато к самому низу экрана, чтобы не закрывать поле боя
	skill_panel.offset_left = -70
	skill_panel.offset_right = 70
	skill_panel.offset_top = -40
	skill_panel.offset_bottom = -4
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	skill_panel.add_child(hb)
	for i in 4:
		var sc := Control.new()
		sc.custom_minimum_size = Vector2(SLOT, SLOT)
		# Иконка и шторка КД делят ОДИН прямоугольник (2,2,24,24): scale-трюк для
		# TextureRect съезжал относительно ColorRect — кулдаун «жил рядом» с иконкой.
		var icon := TextureRect.new()
		icon.position = Vector2(2, 2)
		icon.size = Vector2(SLOT - 4.0, SLOT - 4.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE  # 16 px -> 24 px, nearest из настроек проекта
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.gui_input.connect(_on_skill_slot_input.bind(i))
		sc.add_child(icon)
		var cdc := ColorRect.new()
		cdc.color = Color(0, 0, 0, 0.65)
		cdc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cdc.position = Vector2(2, 2)
		cdc.size = Vector2(SLOT - 4.0, 0)
		sc.add_child(cdc)
		var cdnum := Label.new()  # секунды кулдауна — по центру иконки
		cdnum.position = Vector2(2, 2)
		cdnum.size = Vector2(SLOT - 4.0, SLOT - 4.0)
		cdnum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cdnum.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cdnum.add_theme_font_size_override("font_size", 12)
		cdnum.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		cdnum.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		cdnum.add_theme_constant_override("outline_size", 4)
		cdnum.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(cdnum)
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
		skill_slots.append({"root": sc, "icon": icon, "cd": cdc, "cdn": cdnum, "lvl": lvl, "hot": hot})
	skill_panel.theme = th
	add_child(skill_panel)
	# зелье из трав — справа от панели скиллов
	potion_btn = Button.new()
	potion_btn.add_theme_font_size_override("font_size", 8)
	potion_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	potion_btn.offset_left = 76
	potion_btn.offset_right = 124
	potion_btn.offset_top = -40
	potion_btn.offset_bottom = -4
	potion_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	potion_btn.tooltip_text = "Лесное зелье: +3 HP (Q или клик)"
	if ResourceLoader.exists("res://assets/tiles.png"):
		var hat := AtlasTexture.new()
		hat.atlas = load("res://assets/tiles.png")
		hat.region = Rect2(11 * 16, 0, 16, 16)
		potion_btn.icon = hat
	potion_btn.pressed.connect(_on_potion_pressed)
	potion_btn.theme = th
	potion_btn.visible = false
	add_child(potion_btn)

func _on_potion_pressed() -> void:
	if world != null and world.has_method("drink_potion"):
		world.drink_potion()

## Перестроить иконки под текущий класс (после создания героя, загрузки сейва).
func refresh_skills() -> void:
	var has := GameState.class_id != ""
	if skill_panel != null:
		skill_panel.visible = has
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
		var mc := int(sd.get("mana", 0))
		icon.tooltip_text = "%s — ур. %d, КД %.0f с%s\n%s" % [sd.name, sd.level, sd.cd, (", энергия %d" % mc) if mc > 0 else "", sd.desc]
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
		var cd_left := 0.0
		if p != null and float(p.skill_cd[i]) > 0.0:
			cd_left = float(p.skill_cd[i])
			frac = clampf(cd_left / float(sd.cd), 0.0, 1.0)
		# шторка лежит точно на иконке и уходит снизу вверх: тёмной остаётся верхняя часть
		slot["cd"].size = Vector2(SLOT - 4.0, (SLOT - 4.0) * frac)
		slot["cdn"].text = str(ceili(cd_left)) if frac > 0.0 else ""

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

# --- этап создания героя (выбор класса, необратим) ---

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
	title.text = "Создание героя"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Выбор класса необратим — герой создаётся один раз"
	subtitle.add_theme_font_size_override("font_size", 8)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.75, 0.6))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(subtitle)
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
	GameState.toast.emit("Герой создан: %s. Путь выбран — назад не повернуть!" % String(Classes.CLASSES[id].name))
	refresh_skills()
	if class_chosen_cb.is_valid():
		class_chosen_cb.call()
	class_chosen_cb = Callable()
