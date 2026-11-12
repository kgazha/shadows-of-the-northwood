extends Node
## QA-стенд sand_ui (UI-фидбек, база f3aa4c9): п.2 «текст скиллов налезает на
## окно диалога», п.3 «у талантов нет иконок», п.4 «hp=max, но полоса выглядит
## неполной». Запуск (стадж кладёт qa_ui.gd в корень проекта, как qa_tal):
##   godot --headless --path <proj> res://tools/qa/stand/qa_ui.tscn
## Печатает строки "QA_UI PASS|FAIL <id> <детали>", INFO-числа и
## "QA_UI SUMMARY ...". Выход: 0 — всё зелёное, 1 — есть FAIL.
## Детерминизм: фиксированный класс warrior, без rng и Time.*.

const HudScript := preload("res://scripts/hud.gd")

var _checks := 0
var _fails := 0

func _chk(id: String, ok: bool, info: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("QA_UI %s %s | %s" % ["PASS" if ok else "FAIL", id, info])

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_buttons(c, out)

func _ready() -> void:
	# «голый» герой (автосейв нового процесса, но фиксируем явно)
	GameState.flags = {}
	GameState.gold = 0
	GameState.level = 1
	GameState.xp = 0
	GameState.xp_next = 20
	GameState.input_locked = false
	GameState.class_id = ""

	_icons_checks()
	await _journal_checks()
	await _hud_checks()

	print("QA_UI SUMMARY checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

# --- п.3: procedural-иконки талантов (talents.gd) ---

func _icons_checks() -> void:
	var ids: Array = Talents.NODES.keys()
	_chk("i0_twelve_ids", ids.size() == 12, "NODES=%d узлов (ждём 12)" % ids.size())
	var n_img := 0
	var n_88 := 0
	var n_fmt := 0
	var hashes := {}
	for id in ids:
		var img := Talents.icon_image(String(id))
		if img != null:
			n_img += 1
			if img.get_size() == Vector2i(8, 8):
				n_88 += 1
			if img.get_format() == Image.FORMAT_RGBA8:
				n_fmt += 1
			# PNG-байты как канонический отпечаток (у Image в 4.x нет hash()/sha256)
			hashes[img.save_png_to_buffer().hex_encode()] = String(id)
	_chk("i1_images_built", n_img == 12, "icon_image() вернул Image для %d/12 узлов" % n_img)
	_chk("i2_size_8x8", n_88 == 12, "Image.get_size()==8x8 для %d/12" % n_88)
	_chk("i3_format_rgba8", n_fmt == 12, "FORMAT_RGBA8 для %d/12" % n_fmt)
	_chk("i4_unique", hashes.size() == 12, "уникальных hash: %d/12" % hashes.size())
	var n_tex := 0
	var n_16 := 0
	for id in ids:
		var tex := Talents.icon_texture(String(id))
		if tex is ImageTexture:
			n_tex += 1
			if tex.get_size() == Vector2(16, 16):
				n_16 += 1
	_chk("i5_texture_16x16", n_tex == 12 and n_16 == 12,
		"ImageTexture (nearest resize 8->16) размером 16x16: %d/12" % n_16)
	_chk("i6_same_instance", Talents.icon_texture("whetstone") == Talents.icon_texture("whetstone"),
		"кэш: повторный вызов отдаёт тот же объект")
	_chk("i7_unknown_null", Talents.icon_image("nosuch") == null and Talents.icon_texture("nosuch") == null,
		"неизвестный id -> null (журнал без иконки, не падает)")

# --- п.3: строка узла в журнале = иконка + имя + ранг ---

func _journal_checks() -> void:
	var j: Journal = Journal.new()
	add_child(j)
	j.select_tab(Journal.TAB_TALENTS)  # немодальный: rebuild без open()
	var btns: Array = []
	_buttons(j._tal_list, btns)
	var n_icon := 0
	var n_16 := 0
	var n_text := 0
	for raw_b in btns:
		var b := raw_b as Button
		if b.icon != null:
			n_icon += 1
			if b.icon.get_size() == Vector2(16, 16):
				n_16 += 1
		for raw_id in Talents.NODES.keys():
			var nd: Dictionary = Talents.NODES[raw_id]
			if b.text == "%s %d/%d" % [String(nd.get("name", "")), 0, Talents.max_of(String(raw_id))]:
				n_text += 1
	print("QA_UI INFO journal buttons=%d icon=%d icon16=%d text='%s'" % [btns.size(), n_icon, n_16, (btns[0] as Button).text if not btns.is_empty() else "-"])
	_chk("j1_rows_12", btns.size() == 12, "кнопок-узлов: %d (ждём 12)" % btns.size())
	_chk("j2_icon_on_row", n_icon == 12 and n_16 == 12,
		"иконка 16x16 на строке: %d/12" % n_16)
	_chk("j3_name_rank", n_text == 12, "текст 'Имя ранг/max': %d/12" % n_text)
	# трата очка -> ранг виден в тексте той же кнопки
	GameState.level = 2  # одно очко таланта
	j._on_tal_clicked("whetstone")
	await _frames(1)  # _rebuild_talents делает queue_free старых кнопок
	var btns2: Array = []
	_buttons(j._tal_list, btns2)
	var found := ""
	for raw_b in btns2:
		var b := raw_b as Button
		if b.text.begins_with("Точильный камень"):
			found = b.text
	_chk("j4_rank_after_spend", found == "Точильный камень 1/2", "кнопка после траты: '%s'" % found)
	# измерение колонок: вложенность видна только при layout (скрытый journal не считается)
	j._root.visible = true
	await _frames(2)
	var need_max := 0.0
	var clipped := 0
	for raw_b in btns2:
		var b := raw_b as Button
		var need: float = b.get_combined_minimum_size().x
		need_max = maxf(need_max, need)
		if need > b.size.x + 0.5:
			clipped += 1
	print("QA_UI INFO widths scroll=%.0f col_minmax=%.1f clipped_btns=%d" % [j._scroll.size.x, need_max, clipped])
	_chk("j5_no_clip", clipped == 0,
		"иконка+имя+ранг не обрезаются: widest min=%.1f px при колонке ~%.0f px" % [need_max, (j._scroll.size.x - 12.0) / 3.0])
	# t27 P0-2: бумажная кромка журнала — НЕ ребёнок PanelContainer (контейнер
	# укладывал её в контент-прямоугольник, кромка не доставала до рамки),
	# а сосед окна под _root с ровно тем же глобальным прямоугольником.
	# Layout прогнан выше (2 кадра при _root.visible). Стенд показывает корень
	# напрямую (без open()), поэтому повторяем синк кромки из open() — сам
	# пользовательский путь open() вызывает _sync_paper() (см. journal.gd).
	j._sync_paper()
	var paper: PaperEdge = j._paper
	var paper_in_panel := false
	for c in j._panel.get_children():
		if c is PaperEdge:
			paper_in_panel = true
	var j6_ok := paper != null and not paper_in_panel and paper.get_parent() == j._root \
		and paper.global_position.is_equal_approx(j._panel.global_position) \
		and paper.size.is_equal_approx(j._panel.size)
	_chk("j6_paper_on_frame", j6_ok,
		"PaperEdge — сосед _panel под _root, rect==rect окна: paper=%s panel=%s" % [
			str(paper.size) if paper != null else "-", str(j._panel.size)])
	j.close()

# --- п.2 + п.4: hud.gd ---

func _hud_checks() -> void:
	# откатываем сюжет журнала: полосы считаем от «голого» героя 1-го уровня
	GameState.flags = {}
	GameState.level = 1
	GameState.xp = 0
	GameState.xp_next = 20
	GameState.set_class("warrior")  # hp 12 — чётные доли для ±1px
	var hud: CanvasLayer = HudScript.new()
	add_child(hud)
	hud.setup(null)
	await _frames(3)  # layout VBox: треки полос получили финальные размеры

	# --- п.4: треки и заполнение ---
	var bgw: float = hud.hp_bg.size.x
	var full_w: float = hud.hp_fill.size.x
	print("QA_UI INFO tracks hp_bg=%.0f mana_bg=%.0f xp_bg=%.0f hp_fill(max)=%.1f" % [hud.hp_bg.size.x, hud.mana_bg.size.x, hud.xp_bg.size.x, hud.hp_fill.size.x])
	# у воина mana_bg скрыт (скрытые дети VBox не получают layout) — его
	# проверяем самим флагом растяжения, hp/xp — фактической шириной
	_chk("p1_track_130", bgw == 130.0 and hud.xp_bg.size.x == 130.0
			and hud.mana_bg.size_flags_horizontal == Control.SIZE_SHRINK_BEGIN,
		"трек hp/xp = 130 px, mana_bg не растягивается (VBox больше не тянет фон до текста заданий)")
	_chk("p2_full_reaches_right", absf(full_w - 128.0) < 0.01 and absf(full_w - (bgw - 2.0)) < 0.01,
		"hp==max: заполнение %.1f == 130-2 (симметричные бордюры 1+1)" % full_w)
	GameState.hurt(6)  # по сигналу stats_changed -> refresh в том же кадре
	_chk("p3_half_64", absf(hud.hp_fill.size.x - 64.0) <= 1.0,
		"hp=6/12 (50%%): ширина %.1f == 64 ±1 px" % hud.hp_fill.size.x)
	GameState.hurt(3)
	_chk("p4_quarter_32", absf(hud.hp_fill.size.x - 32.0) <= 1.0,
		"hp=3/12 (25%%): ширина %.1f == 32 ±1 px" % hud.hp_fill.size.x)
	GameState.heal_full()
	_chk("p5_heal_full_same_frame", hud.hp_fill.size.x == 128.0 and hud.hp_txt.text == "12 / 12",
		"heal_full(): полоса=128 px и '%s' в тот же кадр (stats_changed, без ожидания)" % hud.hp_txt.text)
	GameState.add_xp(GameState.xp_next)
	_chk("p6_levelup_same_frame", GameState.level == 2 and GameState.max_hp == 14
			and hud.hp_fill.size.x == 128.0 and hud.hp_txt.text == "14 / 14",
		"level-up: lv=%d max_hp=%d полоса=%.1f '%s' в тот же кадр" % [GameState.level, GameState.max_hp, hud.hp_fill.size.x, hud.hp_txt.text])

	# --- п.2: хотбар и окно диалога ---
	_chk("h1_hotbar_base", hud.skill_panel.visible, "без диалога (класс выбран): хотбар виден")
	hud.show_dialog([{"who": "elder", "text": "проверка наложения слоёв"}], Callable())
	await _frames(2)
	_chk("h2_dialog_hides_hotbar", hud.is_dialog_open() and not hud.skill_panel.visible,
		"диалог открыт: is_dialog_open=%s -> skill_panel.visible=%s (текст скиллов скрыт)" % [hud.is_dialog_open(), hud.skill_panel.visible])
	hud.advance()  # реплика печатается: первый шаг — показать целиком
	var guard := 0
	while hud.is_dialog_open() and guard < 10:
		hud.advance()
		guard += 1
	await _frames(2)
	_chk("h3_dialog_close_restores", not hud.is_dialog_open() and hud.skill_panel.visible,
		"диалог закрыт: skill_panel.visible=%s (вернулся тем же кадром)" % hud.skill_panel.visible)
	hud.show_class_modal()  # модалка тоже гасит слой (то же условие)
	await _frames(2)
	var hidden_modal: bool = not hud.skill_panel.visible
	hud.modal_shown = false
	hud.modal.visible = false
	GameState.input_locked = false
	await _frames(2)
	_chk("h4_modal_hides_hotbar", hidden_modal and hud.skill_panel.visible,
		"модалка: скрыт=%s, после закрытия виден=%s" % [hidden_modal, hud.skill_panel.visible])
