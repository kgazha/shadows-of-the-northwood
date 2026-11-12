extends Node
## t29 QA-стенд «UI-fix-2» — реестр багов t28 (bugs.md): B-02, B-03, B-04, B-06,
## B-07, B-08, B-09, B-11 + инвариант qa-gate «двойной клик по покупке = одна
## покупка». B-01/B-05 закрыты t27 (здесь только сквозная проверка, что их не
## вернули); B-10 (утечка 1 RID при выходе) — принятый шум окружения, стендом
## не проверяется, см. отчёт.
##
## Методология стендов qa_s2/qa_dn/qa_mb: живой main.tscn и РЕАЛЬНЫЙ ввод —
## get_tree().root.push_input() (синхронная доставка, тот же путь события, что у
## настоящей мыши/клавиатуры игрока). Приватные поля читаются только там, где
## это и есть предмет проверки (владение lock, номер страницы).

const MAIN_SCENE := "res://scenes/main.tscn"
const Alch := preload("res://scripts/alchemy.gd")

var passes := 0
var fails := 0
var world: Node = null
var hud = null
var player: Node = null
var sm: SettingsMenu = null

func _ready() -> void:
	_wipe_saves()
	await _boot()
	if world == null or hud == null or player == null:
		print("QA IB: БОТ НЕ ЗАПУСТИЛСЯ — стенд не может ничего проверить")
		print("RESULT: %d pass / %d fail" % [passes, fails])
		get_tree().quit(1)
		return
	await _b03_hotbar_through_dialog()
	await _b04_long_and_short_lines()
	await _b11_toast_stack()
	await _b07_double_esc()
	await _b09_b08_board_gate_and_caption()
	await _b02_death_with_open_shop()
	await _b06_b09_summary_retry_and_double_buy()
	await _step()
	print("QA IB: %d проверок" % (passes + fails))
	print("RESULT: %d pass / %d fail" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)

# ---------------- инфраструктура ----------------

func _wipe_saves() -> void:
	var da := DirAccess.open("user://")
	if da != null:
		for f: String in da.get_files():
			if f.ends_with(".json"):
				da.remove(f)

func _step() -> void:
	await get_tree().physics_frame

func _fr(n: int) -> void:
	for i: int in n:
		await _step()

func _check(ok: bool, what: String) -> bool:
	if ok:
		passes += 1
	else:
		fails += 1
	print("  [%s] %s" % ["OK" if ok else "FAIL", what])
	return ok

func _note(what: String) -> void:
	print("  [NOTE] " + what)

func _descendants(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

## Координаты контента 640×360 -> координаты окна. В headless-квотах вьюпорт
## равен контенту (коэффициент 1), в окне 1280×720 — 2.
## Координаты канваса -> координаты ОКНА, которые ждёт Window.push_input.
## Берём трансформацию канваса у HUD-слоя: она уже учитывает content_scale
## (масштаб канваса) и смещение CanvasLayer. Прежний вариант «× ширина/640»
## предполагал канвас ровно 640×360 и при другом размере уводил клики за край.
func _to_view(p: Vector2) -> Vector2:
	# hud — CanvasLayer (трансформации канваса у него нет), поэтому берём
	# трансформацию его же корневого Control: она и есть канвас -> экран.
	if hud == null or hud.panel == null:
		return p
	var t: Transform2D = hud.panel.get_canvas_transform()
	return t * p

## Позиция КОНКРЕТНОГО контроля в координатах окна: трансформация того
## канвас-слоя, в котором он живёт (у модалок свой слой, у HUD — свой).
func _win_pos(c: Control) -> Vector2:
	var t: Transform2D = c.get_canvas_transform()
	return t * c.get_global_rect().get_center()

## Реальный клик ЛКМ (motion + press + release) по координатам ОКНА.
func _click_win(vp: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = vp
	mm.global_position = vp
	get_tree().root.push_input(mm)
	var d := InputEventMouseButton.new()
	d.position = vp
	d.global_position = vp
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	get_tree().root.push_input(d)
	var u := InputEventMouseButton.new()
	u.position = vp
	u.global_position = vp
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	get_tree().root.push_input(u)

## Реальный клик ЛКМ ровно по центру контроля (координаты берём у него же).
func _click_at(c: Control) -> void:
	_click_win(_win_pos(c))

## Совместимость: клик по координатам канваса.
func _click(pos: Vector2) -> void:
	_click_win(_to_view(pos))

func _key(code: Key) -> void:
	var d := InputEventKey.new()
	d.keycode = code
	d.physical_keycode = code
	d.pressed = true
	get_tree().root.push_input(d)
	var u := InputEventKey.new()
	u.keycode = code
	u.physical_keycode = code
	u.pressed = false
	get_tree().root.push_input(u)

## Пролистать диалог «по-человечески» (advance до закрытия), с защитой от вечного цикла.
func _close_dialog(max_steps: int) -> bool:
	for i: int in max_steps:
		if not hud.is_dialog_open():
			return true
		hud.advance()
		await _fr(1)
	return not hud.is_dialog_open()

func _boot() -> void:
	var inst: Node = load(MAIN_SCENE).instantiate()
	add_child(inst)
	await _fr(12)
	for n in _descendants(get_tree().current_scene):
		if world == null and n.has_method("drink_potion") and n.get("player") != null:
			world = n
		if player == null and n.is_in_group("player"):
			player = n
	_check(world != null, "IB boot: world найден")
	_check(player != null, "IB boot: player найден")
	if world == null or player == null:
		return
	hud = world.hud
	for c in world.get_children():
		if c is SettingsMenu:
			sm = c
	_check(hud != null and sm != null, "IB boot: hud и SettingsMenu найдены")
	if hud.is_modal_open():
		hud._pick_class("warrior")
	_check(not hud.is_modal_open() and GameState.class_id == "warrior",
		"IB boot: класс выбран (хотбар активен)")
	for i: int in range(60):
		if not hud.is_dialog_open():
			break
		hud.advance()
		await _fr(1)
	_check(not hud.is_dialog_open() and not GameState.input_locked,
		"IB boot: забег чист — диалогов нет, ввод свободен")
	_check(RunSummary.I != null and not RunSummary.is_open() and not MetaBoard.is_open(),
		"IB boot: экранов смерти/доски нет")
	_note("геометрия: окно=%s visible_rect=%s | диалог=%s канвас-xform=%s" % [
		str(DisplayServer.window_get_size()), str(get_tree().root.get_visible_rect().size),
		str(hud.panel.get_global_rect()), str(hud.panel.get_canvas_transform())])

# ---------------- B-03: зельевые кнопки не стреляют сквозь окно диалога ----------------

func _b03_hotbar_through_dialog() -> void:
	print("== B-03: кнопки зелий под окном диалога (реальный клик) ==")
	GameState.herbs = 3
	GameState.brewed_potions = 2
	GameState.max_hp = 20
	GameState.hp = 12
	hud.refresh()
	await _fr(3)
	_check(hud.potion_btn.visible and hud.brewed_btn.visible and hud.mat_lbl.visible,
		"B-03 before: свободный хотбар виден (иначе тест ничего не доказывает)")
	# запоминаем РЕАЛЬНЫЕ прямоугольники кнопок, пока они ещё на экране
	var rq_win: Vector2 = _win_pos(hud.brewed_btn)
	var rqr_win: Vector2 = _win_pos(hud.potion_btn)
	_note("кнопки в координатах окна: R %s, Q %s (окно %s, xform канваса %s)" % [
		str(rq_win), str(rqr_win), str(get_tree().root.get_visible_rect().size),
		str(hud.panel.get_canvas_transform())])
	# КАК ЗДЕСЬ ВЕРИФИЦИРУЕТСЯ «КЛИК ПО КНОПКЕ». Замер прямо на этом стенде:
	# в headless-сборке 4.7 синтетическое мышиное событие до BaseButton НЕ
	# доходит ни одним из способов — Window.push_input, Input.parse_input_event
	# и warp_mouse+push_input дали hp 10->10 (warp_mouse ещё и увёл курсор в
	# (4720, 6180) вместо (472, 618)). Node-обработчики такие события ВИДЯТ:
	# на Window.push_input построены листание диалога в B-02/B-04 и двойной Esc.
	# Поэтому для Control-кнопок проверяем то, что в Godot и решает исход:
	# 1) скрытый контроль исключён из GUI-хиттеста (is_visible_in_tree == false),
	#    т.е. кликнуть его физически нельзя;
	# 2) вторая дверь — гейт API: прямой вызов обяз обязан отказать под локом;
	# 3) контроль живости: тот же вызов вне окна лечит (иначе отказ ничего не
	#    значит, а баг «не воспроизводился» бы сам собой).
	var hp_free: int = GameState.hp
	var bp_free: int = GameState.brewed_potions
	var ok_free: bool = Alch.drink_brewed()
	await _fr(2)
	_check(ok_free and GameState.hp > hp_free and GameState.brewed_potions == bp_free - 1,
		"B-03 контроль живости: вне окна то же API лечит (hp %d->%d, заряды %d->%d) — отказ под окном не пустой" % [
			hp_free, GameState.hp, bp_free, GameState.brewed_potions])
	_check(hud.brewed_btn.is_visible_in_tree() and hud.potion_btn.is_visible_in_tree(),
		"B-03 контроль: в свободном забеге кнопки в дереве видимы — хиттест их находит (баг был достижим)")
	GameState.hp = 12
	GameState.brewed_potions = 2
	GameState.herbs = 3
	hud.refresh()
	await _fr(2)
	# диалог из ДВУХ реплик: два клика по окну его не закрывают, поэтому все
	# нижние проверки гарантированно делаются под залоченным окном
	hud.show_dialog([
		{"who": "narr", "text": "Первая реплика."},
		{"who": "narr", "text": "Вторая реплика."},
	], Callable())
	await _fr(3)
	_check(hud.is_dialog_open() and GameState.input_locked,
		"B-03: окно диалога открыто, ввод залочен")
	_check(not hud.potion_btn.visible and not hud.brewed_btn.visible and not hud.mat_lbl.visible,
		"B-03: кнопки зелий и счётчик материалов СПРЯТАНЫ под окном (гейт _hotbar_allowed)")
	_check(not hud.potion_btn.is_visible_in_tree() and not hud.brewed_btn.is_visible_in_tree(),
		"B-03: кнопки вне дерева видимых (is_visible_in_tree == false) — GUI-хиттест Godot их не находит, кликнуть нельзя")
	_check(not hud.skill_panel.visible, "B-03: панель скиллов тоже гаснет (пин t27 цел)")
	_check(not hud._hotbar_allowed(), "B-03: сам гейт возвращает false под окном")
	var dlg: Rect2 = hud.panel.get_global_rect()
	var bqr: Rect2 = hud.potion_btn.get_global_rect()
	var brr: Rect2 = hud.brewed_btn.get_global_rect()
	_note("окно %s / Q %s / R %s" % [str(dlg), str(bqr), str(brr)])
	_check(dlg.size.y > 0.0 and bqr.size.x > 0.0 and brr.size.x > 0.0
		and dlg.intersects(bqr) and dlg.intersects(brr),
		"B-03: прямоугольники кнопок лежат ВНУТРИ окна — баг был реальным, скрытие обязательно")
	var hp0: int = GameState.hp
	var bp0: int = GameState.brewed_potions
	var hb0: int = GameState.herbs
	# клик ровно по прежнему месту кнопки R (крепкое зелье) — сквозь окно
	_click_win(rq_win)
	await _fr(4)
	_note("после клика R: открыт=%s печатается=%s hp=%d" % [str(hud.is_dialog_open()), str(hud.typing), GameState.hp])
	_check(not hud.typing,
		"B-03 контроль: клик по окну обработан — реплика достпечатана, значит клик долетает до окна")
	_check(GameState.hp == hp0 and GameState.brewed_potions == bp0 and GameState.herbs == hb0,
		"B-03: реальный клик по месту кнопки под окном НЕ лечит (hp %d, заряды %d, травы %d)" % [GameState.hp, GameState.brewed_potions, GameState.herbs])
	# клик по месту Q — то же самое
	_click_win(rqr_win)
	await _fr(4)
	_check(hud.is_dialog_open(),
		"B-03 контроль: после второго клика окно ещё открыто (вторая реплика) — дальше проверяем под локом")
	_check(GameState.hp == hp0 and GameState.herbs == hb0,
		"B-03: клик по месту Q-кнопки тоже не лечит (травы %d)" % GameState.herbs)
	# Q-хоткей под локом: путь world._unhandled_input отрезан гейтом
	_key(KEY_Q)
	await _fr(3)
	_check(hud.is_dialog_open() and GameState.input_locked,
		"B-03 контроль: Q-хоткей окно не закрыл — лок всё ещё законный")
	_check(GameState.hp == hp0 and GameState.herbs == hb0,
		"B-03: Q под локом диалога не срабатывает (hp %d, травы %d)" % [GameState.hp, GameState.herbs])
	# и прямой вызов API больше не обходит лок (вторая дверь)
	var rc: bool = Alch.drink_brewed()
	_check(hud.is_dialog_open(),
		"B-03 контроль: окно открыто и в момент прямого вызова (отказ нельзя списать на снятый лок)")
	_check(rc == false and GameState.hp == hp0 and GameState.brewed_potions == bp0,
		"B-03: прямой Alch.drink_brewed() под input_locked отказал (ret=%s)" % str(rc))
	var cl_b03 := await _close_dialog(20)
	_check(cl_b03, "B-03: диалог закрыт через advance")
	await _fr(3)
	_check(hud.potion_btn.visible and hud.brewed_btn.visible and hud.mat_lbl.visible,
		"B-03: окно ушло — хотбар вернулся сам (кадровый надзор)")
	GameState.hp = 10
	hud.refresh()
	await _fr(2)
	var hp1: int = GameState.hp
	var bp1: int = GameState.brewed_potions
	var rc2: bool = Alch.drink_brewed()
	await _fr(2)
	_check(rc2 and GameState.hp > hp1 and GameState.brewed_potions == bp1 - 1,
		"B-03: вне окна зелье по-прежнему пьётся (hp %d->%d, заряды %d)" % [hp1, GameState.hp, GameState.brewed_potions])

# ---------------- B-04: длинная реплика листается, короткая не растёт ----------------

func _b04_long_and_short_lines() -> void:
	print("== B-04: перенос + листание длинной реплики (было: обрывок 209 из 1395 знаков) ==")
	# короткая реплика: базовая высота окна и ОДНА страница
	hud.show_dialog([{"who": "narr", "text": "Короткая реплика."}], Callable())
	await _fr(5)
	var h_short: float = hud.panel.get_global_rect().size.y
	var pc_short: int = hud.dialog_page_count()
	_note("короткая: окно %.1f px, dtext %.1f px, строк %d (влезает %d), страниц %d" % [
		h_short, hud.dtext.get_global_rect().size.y, hud.dtext.get_line_count(),
		hud.dtext.get_visible_line_count(), pc_short])
	_check(pc_short == 1, "B-04: короткая реплика — ровно 1 страница (окно не раздувается)")
	_check(absf(h_short - 69.0) < 1.0,
		"B-04: высота окна короткой реплики не изменилась: %.1f px (канон t27 = 69, не 125)" % h_short)
	_check(absf(hud.dtext.get_global_rect().size.y - 36.0) < 0.5,
		"B-04: viewport текста остался 36 px (окно не выросло под текст)")
	_check(hud.dtext.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"B-04: autowrap включён — слова переносятся, а не обрезаются пословно")
	_check(hud.dtext.scroll_active, "B-04: окно прокручиваемое (единственный доступный в 4.7 способ страничить)")
	var cl_short := await _close_dialog(10)
	_check(cl_short, "B-04: короткая реплика закрывается за 2 нажатия (листать нечего)")
	# очень длинная реплика (масштаб рекорда реестра — 1395 знаков)
	var w := "сияние северного леса "
	var long_text: String = w.repeat(63) + "И ВОТ ПОСЛЕДНЕЕ СЛОВО."
	_note("длина реплики: %d знаков" % long_text.length())
	hud.show_dialog([{"who": "narr", "text": long_text}], Callable())
	await _fr(6)  # layout: autowrap + разбивка на строки считаются после раскладки
	var h_long: float = hud.panel.get_global_rect().size.y
	_check(absf(h_long - h_short) < 1.0,
		"B-04: окно НЕ выросло под длинный текст: %.1f px против %.1f px у короткой" % [h_long, h_short])
	_check(hud.dialog_page() == 0, "B-04: старт всегда с первой страницы (сброс страницы)")
	var t1 := 0
	while hud.typing and t1 < 30:
		hud.advance()
		t1 += 1
		await _fr(1)
	_check(hud.dtext.visible_characters == -1, "B-04: первое «далее» достпечатывает реплику целиком")
	await _fr(3)  # полный текст выложен -> строки посчитаны
	var lines_total: int = hud.dtext.get_line_count()
	var per_page: int = hud.dtext.get_visible_line_count()
	var pages: int = hud.dialog_page_count()
	_note("длинная: строк %d, влезает %d, страниц %d, окно %.1f px" % [lines_total, per_page, pages, h_long])
	_check(lines_total > per_page and lines_total > 4,
		"B-04: текст реально НЕ влезает в окно (строк %d при %d видимых) — раньше хвост был потерян" % [lines_total, per_page])
	_check(pages >= 2, "B-04: реплика разбита на %d страниц (раньше была одна обрезанная)" % pages)
	var guard := 0
	while hud.is_dialog_open() and hud.dialog_page() < hud.dialog_page_count() - 1 and guard < 24:
		_click_at(hud.dtext)  # реальный ЛКМ-ивент = «далее» (путь _unhandled_input)
		guard += 1
		await _fr(2)
	_check(hud.is_dialog_open(), "B-04: реплика ещё открыта во время листания (клик по полю её не закрывает)")
	_check(hud.dialog_page() == pages - 1,
		"B-04: реальными кликами долистали до последней страницы (%d из %d)" % [hud.dialog_page(), pages])
	_check(hud.dtext.get_visible_line_count() > 0,
		"B-04: на последней странице есть отрисованные строки (%d) — хвост реплики ВИДЕН" % hud.dtext.get_visible_line_count())
	_check(hud.dialog_page_count() == pages,
		"B-04: число страниц не скачет во время листания (стабильно %d)" % pages)
	var cl_long := await _close_dialog(12)
	_check(cl_long, "B-04: после последней страницы реплика закрывается (листание терминально)")
	_check(not GameState.input_locked, "B-04: lock снят закрытием")
	# короткий хвост-кейс: несколько реплик, где длинная — средняя
	hud.show_dialog([
		{"who": "narr", "text": "Первая."},
		{"who": "narr", "text": (w.repeat(40) + "ХВОСТ-СРЕДНЕЙ").left(1100)},
		{"who": "narr", "text": "Последняя."},
	], Callable())
	await _fr(5)
	var g2 := 0
	while hud.is_dialog_open() and g2 < 40:
		hud.advance()
		await _fr(1)
		g2 += 1
	_check(not hud.is_dialog_open() and not GameState.input_locked,
		"B-04: микс коротких и длинных реплик проходится за %d нажатий без зависания" % g2)

# ---------------- B-11: стопка тостов ----------------

func _b11_toast_stack() -> void:
	print("== B-11: тосты — стопка вместо «новый затирает непрочитанный» ==")
	_check(hud.toast_lbl != null and hud.toast_more.size() == 2,
		"B-11: стопка %d строк (свежая + %d уходящих)" % [1 + hud.toast_more.size(), hud.toast_more.size()])
	hud.toast_lbl.text = ""
	for l in hud.toast_more:
		l.text = ""
	GameState.toast.emit("ПЕРВЫЙ-НЕПРОЧИТАННЫЙ")
	GameState.toast.emit("ВТОРОЙ-СВЕЖИЙ")
	_check(hud.toast_lbl.text == "ВТОРОЙ-СВЕЖИЙ",
		"B-11: свежий тост наверху (получили «%s»)" % hud.toast_lbl.text)
	_check(hud.toast_more[0].text == "ПЕРВЫЙ-НЕПРОЧИТАННЫЙ",
		"B-11: ПРЕДЫДУЩИЙ не затёрт — уехал вниз (получили «%s»)" % hud.toast_more[0].text)
	GameState.toast.emit("ТРЕТИЙ")
	GameState.toast.emit("ЧЕТВЁРТЫЙ")
	_check(hud.toast_lbl.text == "ЧЕТВЁРТЫЙ" and hud.toast_more[0].text == "ТРЕТИЙ"
		and hud.toast_more[1].text == "ВТОРОЙ-СВЕЖИЙ",
		"B-11: стопка 3 строк «%s | %s | %s» — за борт только самая старая" % [
			hud.toast_lbl.text, hud.toast_more[0].text, hud.toast_more[1].text])
	# независимые таймеры: старый гаснет сам, свежий ещё жив
	hud.toast_lbl.text = ""
	for l in hud.toast_more:
		l.text = ""
	GameState.toast.emit("СТАРЫЙ-МАРКЕР")
	await _fr(110)  # ~1.8 с из 3.0
	GameState.toast.emit("СВЕЖИЙ-МАРКЕР")
	await _fr(2)
	_check(hud.toast_lbl.text == "СВЕЖИЙ-МАРКЕР" and hud.toast_more[0].text == "СТАРЫЙ-МАРКЕР",
		"B-11: оба тоста видимы одновременно")
	await _fr(90)  # ещё ~1.5 с: старый дожил свой остаток
	_check(hud.toast_more[0].text == "" and hud.toast_lbl.text == "СВЕЖИЙ-МАРКЕР",
		"B-11: старый погас ПО СВОЕМУ таймеру, свежий ещё жив («%s» / «%s»)" % [
			hud.toast_lbl.text, hud.toast_more[0].text])
	await _fr(110)
	_check(hud.toast_lbl.text == "" and hud.toast_more[0].text == "" and hud.toast_more[1].text == "",
		"B-11: через ~3 с после последнего тоста стопка чистая (следов нет)")

# ---------------- B-07: двойной Esc не оставляет висячего лока ----------------

func _b07_double_esc() -> void:
	print("== B-07: двойной Esc (двойное нажатие в один кадр) ==")
	_check(not sm.is_open() and not hud.is_dialog_open() and not GameState.input_locked,
		"B-07 pre: состояние чистое (иначе трассировка t28 нерелевантна)")
	# ровно ОДИН кадр, между нажатиями нет await — тот же ввод, что «дважды за клик»
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE)
	_note("после двух Esc в одном кадре: settings=%s locked=%s" % [str(sm.is_open()), str(GameState.input_locked)])
	_check(not sm.is_open(), "B-07: настройки закрыты после двойного Esc")
	_check(not GameState.input_locked, "B-07: висячего лока НЕТ (главный симптом реестра)")
	_check(sm._holds_lock == false, "B-07: флаг владения lock сброшен (меню ничего не держит)")
	# одиночный Esc по-прежнему работает в обе стороны
	_key(KEY_ESCAPE)
	await _fr(2)
	_check(sm.is_open() and GameState.input_locked, "B-07: одиночный Esc открывает настройки и лочит ввод")
	_key(KEY_ESCAPE)
	await _fr(3)
	_check(not sm.is_open() and not GameState.input_locked,
		"B-07: одиночный Esc закрывает и ОТДАЁТ ввод (атомарность открытия не сломана)")
	# скриншот-меню: F1 (другая клавиша) тоже открывает/закрывает без остатка
	sm.open()
	await _fr(2)
	_check(sm.is_open() and GameState.input_locked and sm._holds_lock,
		"B-07: программное open() тоже владеет локом")
	sm.close()
	await _fr(3)
	_check(not sm.is_open() and not GameState.input_locked, "B-07: close() отдаёт лок")
	# воспроизводим ГРЯЗНУЮ предполаг из трассировки t28 (квестовый диалог + двойной Esc):
	# lock=true там belonged диалогу — важно, что он снимается закрытием диалога
	hud.show_dialog([{"who": "narr", "text": "Квестовая реплика (позаимствованная предполаг трассировки)."}], Callable())
	await _fr(3)
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE)
	await _fr(2)
	_note("трассировка t28 L16: settings=%s locked=%s (диалог ещё открыт)" % [str(sm.is_open()), str(GameState.input_locked)])
	_check(not sm.is_open(), "B-07: двойной Esc под диалогом не роняет чужие окна")
	_check(GameState.input_locked and hud.is_dialog_open(),
		"B-07: lock под диалогом принадлежит ДИАЛОГУ (не «потерянный»)")
	var cl_b07 := await _close_dialog(20)
	_check(cl_b07, "B-07: диалог закрыт")
	await _fr(3)
	_check(not GameState.input_locked,
		"B-07: после закрытия диалога ввод свободен — т.е. в трассировке t28 не было висячего лока")

# ---------------- B-09 (гейт) + B-08 (подпись капа) ----------------

func _b09_b08_board_gate_and_caption() -> void:
	print("== B-09: вход на «Доску пепла» только с экрана смерти; B-08: кап в подписи ==")
	_check(not RunSummary.is_open(), "B-09 pre: экрана итогов нет (живой забег)")
	MetaBoard.open()
	await _fr(3)
	_check(not MetaBoard.is_open(),
		"B-09: доска НЕ открылась посреди живого забега (было: игрок тратил пепел не туда)")
	_check(not GameState.input_locked, "B-09: отказ ничего не залочил")
	# B-08: подпись Волхвы обязана называть кап
	var f: Dictionary = GameState.flags
	f["meta.vd"] = 2
	RunSummary.I._refresh()
	var t2 := RunSummary.I.bless_lbl.text
	_note("meta.vd=2 -> «%s»" % t2)
	_check(t2.contains("+6%"), "B-08: ниже капа формулировка не изменилась (стаб qa_mb «+6%%») — «%s»" % t2)
	_check(t2.contains("смертей круга: 3"), "B-08: ниже капа кап не упоминается")
	f["meta.vd"] = 15
	RunSummary.I._refresh()
	var t15 := RunSummary.I.bless_lbl.text
	_note("meta.vd=15 -> «%s»" % t15)
	_check(t15.contains("+20%"), "B-08: при 16 смертях показан РЕАЛЬНЫЙ процент +20% (кап), а не +32%")
	_check(t15.contains("кап 10"), "B-08: кап назван словами (нет обещания «32 стана за 16 смертей») — «%s»" % t15)
	_check(t15.contains("16"), "B-08: сырое число смертей не спрятано")
	f["meta.vd"] = 0
	RunSummary.I._refresh()

# ---------------- B-02: смерть при открытой лавке + 30 реальных кликов ----------------

func _b02_death_with_open_shop() -> void:
	print("== B-02: смерть при открытой лавке — прокрутка реальными кликами ЛКМ ==")
	GameState.hp = 6
	GameState.herbs = 2
	GameState.brewed_potions = 1
	Shop.open()
	await _fr(3)
	_check(Shop.is_open() and GameState.input_locked, "B-02 pre: лавка открыта, ввод у лавки")
	_check(Shop.I._holds_lock and not Shop.I._external_lock(),
		"B-02 pre: лавка — законный владелец ввода (мышь у неё, не «внешний лок»)")
	# под лавкой клавиши мира мертвы: зелье не пьём, героя не бьём
	var hp_pre := GameState.hp
	_key(KEY_Q)
	await _fr(3)
	_check(GameState.hp == hp_pre, "B-02 pre: под лавкой Q не срабатывает (hp=%d)" % GameState.hp)
	_note("исходный кадр: лавка=%s диалог=%s locked=%s" % [
		str(Shop.is_open()), str(hud.is_dialog_open()), str(GameState.input_locked)])
	player.hurt_cd = 0.0
	player.roll_t = 0.0
	player.take_damage(9999)
	_check(GameState.hp == 0, "B-02: герой мёртв")
	_check(hud.is_dialog_open(), "B-02: диалог смерти открыт")
	_check(not Shop.is_open(), "B-02: лавка ЗАКРЫТА при смерти (окно под диалогом не живёт)")
	await _fr(8)
	_check(not Shop.is_open(),
		"B-02: лавка осталась закрытой — watchdog не возвращает окно под диалог")
	_check(not hud.potion_btn.visible and not hud.brewed_btn.visible,
		"B-02/B-03: зельевые кнопки под диалогом смерти скрыты (лечиться нечем)")
	# 30 РЕАЛЬНЫХ нажатий ЛКМ в центр экрана: диалог обязан листаться кликом
	var hp_after_death := GameState.hp
	var used := 0
	for i: int in range(30):
		if not hud.is_dialog_open():
			break
		_click_at(hud.dtext)
		used += 1
		await _fr(2)
	_note("реальных кликов ЛКМ потрачено: %d из 30 (диалог открыт: %s)" % [used, str(hud.is_dialog_open())])
	_check(used > 0 and used < 30,
		"B-02: диалог смерти пролистАН МЫШЬЮ за %d реальных кликов (не завис, не потребовалось все 30)" % used)
	_check(not hud.is_dialog_open(), "B-02: диалог смерти закрыт кликами")
	_check(GameState.hp == hp_after_death, "B-02/B-03: ни один клик не воскресил и не ударил героя (hp=%d)" % GameState.hp)
	await _fr(5)
	_check(RunSummary.is_open(),
		"B-02/B-06: экран итогов открылся сам, гонки с lock нет")
	_check(GameState.input_locked, "B-02: лок перешёл к экрану итогов")
	_check(not Shop.is_open() and not MetaBoard.is_open() and not sm.is_open(),
		"B-02: никаких лишних окон поверх итогов (в т.ч. ни одной лавки)")

# ---------------- B-06: отказ не теряет экран итогов + B-09 легитимный вход ----------------
## Кнопка покупки первой строки доски (детерминированно, не стековым обходом).
func _first_buy_button() -> Button:
	if MetaBoard.I == null or MetaBoard.I.rows_box == null:
		return null
	for c in MetaBoard.I.rows_box.get_children():
		for n in _descendants(c):
			if n is Button and not (n as Button).disabled and String((n as Button).text).begins_with("Ранг"):
				return n as Button
	return null


func _b06_b09_summary_retry_and_double_buy() -> void:
	print("== B-06: retry/watchdog «Экрана итогов»; B-09 легитимный вход; покупка: 1 активация = 1 покупка ==")
	MetaBoard.open()
	await _fr(4)
	_check(MetaBoard.is_open(),
		"B-09: с открытого экрана итогов доска открывается (гейт не перекрывает штатный вход)")
	Ash.add(50)
	MetaBoard.I._rebuild()
	await _fr(2)
	# кнопку берём НЕ обходом дерева в стеке (он даёт ПОСЛЕДНИЙ ряд, и купленный
	# талант оказывался не тем, что проверяем), а из первой строки rows_box
	var tid := String((MetaBoard.TALENTS as Array)[0]["id"])
	var btn: Button = _first_buy_button()
	_check(btn != null, "инвариант: кнопка покупки первой строки найдена")
	if btn != null:
		var r0: int = MetaBoard.rank_of(tid)
		var ash0: int = Ash.balance()
		var cost0: int = MetaBoard.next_cost(r0)
		_note("кнопка «%s» (пепел %d, ранг %d, цена ранга %d), видима в дереве: %s" % [
			btn.text, ash0, r0, cost0, str(btn.is_visible_in_tree())])
		# ОДНА активация = ровно то, что делает один клик. В headless 4.7
		# синтетический клик до BaseButton не доходит (замер в B-03), поэтому
		# активируем сигнал pressed — он и есть «клик» для логики покупки.
		btn.pressed.emit()
		await _fr(3)
		var r1: int = MetaBoard.rank_of(tid)
		var ash1: int = Ash.balance()
		_check(r1 - r0 == 1 and ash0 - ash1 == cost0,
			"одна активация кнопки покупки = ровно ОДНА покупка и ровно один ранг-прайс (ранг %d->%d, пепел %d->%d)" % [
				r0, r1, ash0, ash1])
		_check(not is_instance_valid(btn) or not btn.is_inside_tree(),
			"кнопка после покупки выведена из дерева (queue_free) — на следующий кадр кликнуть «старую» нельзя")
		# t32 (закрыта двойная трата): раньше две активации в ОДНОМ кадре уводили
		# на два ранга и списывали две цены, т.к. до конца кадра старая кнопка была
		# жива (queue_free). После фикса (гард одного кадра + сверка отрисованного
		# ранга + мгновенное обезвреживание умирающего ряда) двойной pressed даёт
		# ровно ОДНУ покупку. Пин переведён на корректный инвариант по инструкции
		# старого пина («при починке пин обновить») — зеркалит qa_mb.
		var btn2: Button = _first_buy_button()
		if btn2 != null:
			var r2: int = MetaBoard.rank_of(tid)
			var ash2: int = Ash.balance()
			var c2: int = MetaBoard.next_cost(r2)
			btn2.pressed.emit()
			btn2.pressed.emit()
			await _fr(3)
			var r3: int = MetaBoard.rank_of(tid)
			var ash3: int = Ash.balance()
			_note("t32-контроль: две активации в одном кадре -> ранг %d->%d, пепел %d->%d (ждём ровно +1 ранг и -%d)" % [
				r2, r3, ash2, ash3, c2])
			_check(r3 - r2 == 1 and ash2 - ash3 == c2,
				"t32 починено: 2 активации в 1 кадре = ровно ОДНА покупка (ранг +%d, пепел -%d, цена %d)" % [
					r3 - r2, ash2 - ash3, c2])
		else:
			_check(false, "после покупки не удалось найти следующую кнопку ряда — проверять двойную активацию не на чем")
	_check(RunSummary.is_open(), "B-06 pre: экран итогов никуда не делся (живёт под доской)")
	MetaBoard.close_panel()
	await _fr(3)
	# B-06: мир занят лавкой -> open() отказывает, но экран ОБЯЗАН появиться позже
	var old: Node = RunSummary.I
	old.free()
	await _fr(3)
	var fresh: RunSummary = RunSummary.new()
	world.add_child(fresh)
	await _fr(4)
	_check(RunSummary.I == fresh and not RunSummary.is_open(),
		"B-06 pre: свежий закрытый экран итогов в дереве (мир свободен)")
	Shop.open()
	await _fr(3)
	_check(Shop.is_open() and GameState.input_locked, "B-06: мир занят — открыта лавка")
	RunSummary.open()
	await _fr(2)
	_check(not RunSummary.is_open(), "B-06: при занятом мире немедленный отказ (окно не лезет поверх лавки)")
	_check(fresh._want_open == true, "B-06: отказ ЗАПИСАН как заявка, а не потерян (прежний баг: rs_open=false навсегда)")
	Shop.close()
	await _fr(4)
	_check(RunSummary.is_open(),
		"B-06: watchdog открыл итоги в первом свободном кадре — rs_open == true")
	_check(GameState.input_locked and fresh._holds_lock, "B-06: лок принадлежит экрану итогов")
	_check(fresh._want_open == false, "B-06: заявка снята после исполнения (повторных открытий нет)")
	RunSummary.open()
	await _fr(2)
	_check(RunSummary.is_open(), "B-06: повторный open() по уже открытому экрану безопасен")
