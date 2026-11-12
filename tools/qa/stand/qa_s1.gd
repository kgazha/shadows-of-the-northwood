extends Node
## QA-харнесс s1: Shop (покупка/отказ/идемпотентность/sell), GearData (damage/absorb),
## save v3 roundtrip (run_seed), legacy v1 миграция, битые поля сейва.

const CANON := Vector2(640, 360)  # t34 V-06: канон base-вьюпорта (window 1280×720, zoom 2)
const SAFE_H := 352.0             # t34 V-06: 360 − 2×EDGE_GAP(4) — поле, обязан влезать панель

var fails := {"n": 0}
var toasts: Array = []
var shop: Shop

func ck(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		print("PASS %s" % name)
	else:
		fails["n"] += 1
		print("FAIL %s :: %s" % [name, detail])

func reset_state(gold: int) -> void:
	GameState.class_id = "warrior"
	GameState.gold = gold
	GameState.equip_item("weapon", "")
	GameState.equip_item("armor", "")
	GameState.has_amulet = false
	GameState.flags = {}
	GameState.recalc_max_hp()
	GameState.heal_full()
	toasts.clear()

func has_toast(sub: String) -> bool:
	for t in toasts:
		if String(t).find(sub) >= 0:
			return true
	return false

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	shop = Shop.new()
	add_child(shop)
	await _run()  # t34 V-06: T18 меряет макет — нужды реальные кадры (layout)
	print("SUMMARY fails=%d" % fails["n"])
	get_tree().quit(0)

func _run() -> void:
	var base := 2  # warrior dmg
	# --- T1 базовый урон без оружия ---
	reset_state(0)
	ck(GameState.damage == base, "T1 bare damage==2", "got %d" % GameState.damage)

	# --- T2 отказ по цене: gold не уходит, экипировки нет ---
	reset_state(0)
	ck(shop.buy_btns.has("sword"), "T2 buy btn exists")
	shop.buy_btns["sword"].pressed.emit()
	ck(GameState.gold == 0, "T2 gold untouched on reject", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "", "T2 no equip on reject", String(GameState.gear["weapon"]))
	ck(has_toast("Не хватает золота"), "T2 toast deny")
	ck(not has_toast("Куплено"), "T2 no purchase toast")

	# --- T3 79 золота на axe(160) — отказ ---
	reset_state(79)
	shop.buy_btns["axe"].pressed.emit()
	ck(GameState.gold == 79 and String(GameState.gear["weapon"]) == "", "T3 reject at 79g", "gold=%d gear=%s" % [GameState.gold, GameState.gear["weapon"]])

	# --- T4 успешная покупка sword(80): gold, gear, legacy-флаг, damage ---
	reset_state(100)
	shop.buy_btns["sword"].pressed.emit()
	ck(GameState.gold == 20, "T4 gold 100-80=20", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "sword", "T4 gear weapon=sword", String(GameState.gear["weapon"]))
	ck(GameState.has_sword, "T4 has_sword synced")
	ck(GameState.damage == 4, "T4 dmg 2x2=4", "got %d" % GameState.damage)
	ck(has_toast("Куплено"), "T4 purchase toast")

	# --- T5 повторная покупка надетого — отказ, gold стоит ---
	reset_state(120)
	shop.buy_btns["sword"].pressed.emit()  # надето
	var g5: int = GameState.gold
	shop.buy_btns["sword"].pressed.emit()  # повторно
	ck(GameState.gold == g5, "T5 gold untouched on re-buy", "before=%d after=%d" % [g5, GameState.gold])
	ck(has_toast("Это уже на тебе"), "T5 already-worn toast")

	# --- T6 замена оружия: sword -> axe ---
	reset_state(300)
	shop.buy_btns["sword"].pressed.emit()
	shop.buy_btns["axe"].pressed.emit()
	ck(GameState.gold == 300 - 80 - 160, "T6 gold after two buys", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "axe", "T6 gear weapon=axe", String(GameState.gear["weapon"]))
	ck(not GameState.has_sword, "T6 has_sword cleared on axe")
	ck(GameState.damage == 5, "T6 dmg round(2*2.5)=5", "got %d" % GameState.damage)

	# --- T7 броня: absorb leather=1 chain=2, min-1 ---
	reset_state(400)
	shop.buy_btns["leather"].pressed.emit()
	ck(String(GameState.gear["armor"]) == "leather", "T7 gear armor=leather")
	GameState.heal_full()
	var hp0: int = GameState.hp
	GameState.hurt(5)
	ck(GameState.hp == hp0 - 4, "T7 leather absorb 1 (5->4)", "hp %d->%d" % [hp0, GameState.hp])
	shop.buy_btns["chain"].pressed.emit()
	GameState.heal_full()
	hp0 = GameState.hp
	GameState.hurt(5)
	ck(GameState.hp == hp0 - 3, "T7 chain absorb 2 (5->3)", "hp %d->%d" % [hp0, GameState.hp])
	GameState.heal_full()
	hp0 = GameState.hp
	GameState.hurt(1)
	ck(GameState.hp == hp0 - 1, "T7 min-1 damage with chain", "hp %d->%d" % [hp0, GameState.hp])

	# --- T8 sell: продажа надетого, +цена/2, слот чист, повторный отказ ---
	reset_state(80)
	shop.buy_btns["sword"].pressed.emit()    # gold=0, sword надет
	toasts.clear()
	shop.sell_btns["weapon"].pressed.emit()  # +40
	ck(GameState.gold == 40, "T8 sell gold 0+40", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "", "T8 slot cleared after sell")
	ck(not GameState.has_sword, "T8 has_sword cleared after sell")
	ck(GameState.damage == 2, "T8 damage back to bare", "got %d" % GameState.damage)
	g5 = GameState.gold
	shop.sell_btns["weapon"].pressed.emit()  # продавать уже нечего
	ck(GameState.gold == g5, "T8 sell-empty gold untouched")
	ck(has_toast("Продавать нечего"), "T8 sell-empty toast")

	# --- T9 buy->sell цикл: чистый минус (no dupe profit) ---
	reset_state(1000)
	shop.buy_btns["rune_blade"].pressed.emit()  # -320
	shop.sell_btns["weapon"].pressed.emit()     # +160
	ck(GameState.gold == 1000 - 320 + 160, "T9 buy/sell roundtrip net -160", "got %d" % GameState.gold)

	# --- T10 legacy-меч: покупка не-sword съедает бесплатный legacy-флаг (NOTE) ---
	reset_state(0)
	GameState.has_sword = true  # меч из старого сундука: флаг есть, gear пуст
	ck(GameState.damage == 4, "T10 legacy flag mult x2", "got %d" % GameState.damage)
	var mult_legacy := GearData.weapon_mult(GameState)
	ck(mult_legacy == 2.0, "T10 weapon_mult legacy 2.0", "got %f" % mult_legacy)
	GameState.gold = 200
	shop.buy_btns["axe"].pressed.emit()  # equip "" -> has_sword=false, затем axe
	ck(not GameState.has_sword, "T10 NOTE legacy sword absorbed by axe buy")
	shop.sell_btns["weapon"].pressed.emit()
	ck(GameState.damage == 2, "T10 NOTE legacy sword lost after sell", "got %d" % GameState.damage)

	# --- T11 витрина: gold label, disabled только у надетого ---
	reset_state(33)
	shop.refresh()
	ck(shop.gold_lbl.text == "Золото: 33", "T11 gold label", shop.gold_lbl.text)
	shop.buy_btns["sword"].pressed.emit()  # надо 80, есть 33 -> отказ, не надет
	shop.refresh()
	ck(not bool(shop.buy_btns["sword"].disabled), "T11 NOTE unaffordable btn NOT disabled (design: gray only)")
	# наденем sword честно:
	GameState.gold = 500
	shop.buy_btns["sword"].pressed.emit()
	shop.refresh()
	ck(bool(shop.buy_btns["sword"].disabled), "T11 equipped btn disabled")

	# --- T12 spend_gold границы ---
	reset_state(50)
	ck(not GameState.spend_gold(-5), "T12 negative spend rejected")
	ck(GameState.gold == 50, "T12 negative spend no-op")
	ck(GameState.spend_gold(0), "T12 zero spend ok")
	ck(not GameState.spend_gold(51), "T12 over-spend rejected")
	ck(GameState.gold == 50, "T12 over-spend no-op")
	GameState.gold = 0
	GameState.add_gold(-999)
	ck(GameState.gold == 0, "T12 add_gold clamps >=0", "got %d" % GameState.gold)

	# --- T13 статический API Shop ---
	ck(not Shop.is_open(), "T13 shop closed at start")
	Shop.open()
	ck(Shop.is_open(), "T13 static open")
	Shop.close()
	ck(not Shop.is_open(), "T13 static close")

	# --- T14 цены/SELL_DIV для всего стока ---
	var ok14 := true
	for id in GearData.SHOP_STOCK:
		var p := GearData.price(String(id))
		var s := GearData.sell_price(String(id))
		if p <= 0 or s != maxi(1, int(p / 2)):
			ok14 = false
			print("  item %s price=%d sell=%d" % [id, p, s])
	ck(ok14, "T14 sell==floor(price/2) all stock")

	# --- T15 save v3 roundtrip (gold/gear/flags/run_seed + автосейв по gold_changed) ---
	reset_state(1)
	GameState.run_seed = 123456789
	GameState.gold = 0
	GameState.add_gold(777)  # через add_gold -> gold_changed -> автосейв
	shop.buy_btns["sword"].pressed.emit()
	shop.buy_btns["chain"].pressed.emit()
	GameState.set_flag("q.test", 5)
	GameState.cave_state = 2
	ck(GameState.save_game(), "T15 save_game ok")
	reset_state(0)
	GameState.flags = {}
	GameState.cave_state = 0
	ck(GameState.load_game(), "T15 load_game ok")
	ck(GameState.run_seed == 123456789, "T15 run_seed v3 roundtrip", str(GameState.run_seed))
	# add_gold(777)+покупки: 777-80-180=517
	ck(GameState.gold == 517, "T15 gold roundtrip", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "sword", "T15 weapon roundtrip", String(GameState.gear["weapon"]))
	ck(String(GameState.gear["armor"]) == "chain", "T15 armor roundtrip", String(GameState.gear["armor"]))
	ck(GameState.has_sword, "T15 has_sword roundtrip")
	ck(int(GameState.flags.get("q.test", -1)) == 5, "T15 flag roundtrip", str(GameState.flags.get("q.test")))
	ck(GameState.cave_state == 2, "T15 cave_state roundtrip")
	ck(GameState.damage == 4, "T15 damage after load", "got %d" % GameState.damage)
	# автосейв без save_game():
	GameState.add_gold(1000)
	reset_state(0)
	ck(GameState.load_game(), "T15 autosave load")
	ck(GameState.gold == 1517, "T15 autosave on gold_changed", "got %d" % GameState.gold)

	# --- T16 legacy v1 сейв: без v/gold/gear/flags, has_sword=true ---
	var f1 := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f1.store_string('{"level":3,"xp":5,"xp_next":32,"has_sword":true,"class_id":"warrior","hp":9,"herbs":2}')
	f1.close()
	ck(GameState.load_game(), "T16 legacy v1 loads")
	ck(GameState.gold == 0, "T16 legacy gold=0")
	ck(String(GameState.gear["weapon"]) == "sword", "T16 legacy migrates to gear.sword", String(GameState.gear["weapon"]))
	ck(GameState.damage == 4, "T16 legacy damage x2", "got %d" % GameState.damage)
	ck(GameState.level == 3 and GameState.xp == 5, "T16 legacy level/xp")
	ck(GameState.max_hp == 12 + 2 * 2, "T16 legacy max_hp=16", "got %d" % GameState.max_hp)
	ck(GameState.hp == 9, "T16 legacy hp=9", "got %d" % GameState.hp)
	ck(int(GameState.to_dict().get("v", 0)) == 3, "T16 re-save versioned v3")
	ck(GameState.run_seed >= 0, "T16 legacy migration seeds run_seed", str(GameState.run_seed))

	# --- T17 битые поля ---
	var f2 := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f2.store_string('{"gold":"abc","gear":{"weapon":123,"armor":{"a":1}},"flags":"nope","level":"x","hp":null,"has_sword":1}')
	f2.close()
	ck(GameState.load_game(), "T17 corrupt loads without crash")
	ck(GameState.gold == 0, "T17 corrupt gold->0", "got %d" % GameState.gold)
	ck(String(GameState.gear["weapon"]) == "sword", "T17 bad gear + has_sword=1 migration", String(GameState.gear["weapon"]))
	ck(String(GameState.gear["armor"]) == "", "T17 bad armor->empty")
	ck(GameState.flags.is_empty(), "T17 bad flags->empty")
	ck(GameState.level == 1, "T17 bad level->1")
	# неизвестные id в gear: инертны
	var f3 := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f3.store_string('{"class_id":"warrior","gear":{"weapon":"mordor","armor":"chainmail"},"gold":10}')
	f3.close()
	ck(GameState.load_game(), "T17 unknown-id save loads")
	ck(GameState.damage == 2, "T17 unknown weapon id inert dmg", "got %d" % GameState.damage)
	GameState.heal_full()
	var hp17: int = GameState.hp
	GameState.hurt(5)
	ck(GameState.hp == hp17 - 5, "T17 unknown armor id inert absorb", "hp %d->%d" % [hp17, GameState.hp])
	toasts.clear()
	shop.refresh()
	shop.sell_btns["weapon"].pressed.emit()
	ck(has_toast("Продавать нечего"), "T17 unknown id unsellable")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))

	# --- T18 (t34 V-06): витрина целиком в каноническом поле 640×360 ---
	# Пин НЕ зависит от окна стенда: в headless окно 640×640 (headless-сервер не
	# применяет window overrides), а панель центрирует CenterContainer, поэтому
	# берём канонический сдвиг dy = (360 − h)/2 − y_панели и проверяем уже им
	# сдвинутые прямоугольники. Это ровно то, что игрок видит в 1280×720 zoom 2.
	reset_state(250)
	Shop.open()
	await get_tree().process_frame
	await get_tree().process_frame
	ck(shop.scroll != null and shop.list_vb != null and shop.close_btn != null,
		"T18 витрина обёрнута в ScrollContainer, close отдельной строкой")
	var pr: Rect2 = shop.panel.get_global_rect()
	var dy: float = (CANON.y - pr.size.y) * 0.5 - pr.position.y
	# Замер на стенде (headless, тот же код темы/шрифта): панель 328 px, низ
	# close 339 при поле 360 (было: панель 397, низ close 392 — целиком за экраном).
	ck(pr.size.y <= SAFE_H + 0.5, "T18 панель <= безопасного поля 352", "h=%.1f rect=%s" % [pr.size.y, pr])
	var cr: Rect2 = shop.close_btn.get_global_rect()
	ck(cr.position.y + dy >= 0.0 and cr.end.y + dy <= CANON.y,
		"T18 close-кнопка полностью в viewport", "canon y=[%.1f..%.1f]" % [cr.position.y + dy, cr.end.y + dy])
	ck(not shop.scroll.is_ancestor_of(shop.close_btn),
		"T18 close вне скролла => видима без прокрутки")
	ck(shop.scroll.mouse_filter == Control.MOUSE_FILTER_STOP,
		"T18 скролл ест мышь (пустое место витрины не закрывает лавку)", "mf=%d" % shop.scroll.mouse_filter)
	# «мышью попасть можно»: центр close в канонических координатах не под скроллом
	var hit: Vector2 = Vector2((cr.position + cr.end) * 0.5)
	ck(cr.has_point(hit) and not shop.scroll.get_global_rect().has_point(hit)
		and shop.close_btn.mouse_filter == Control.MOUSE_FILTER_STOP,
		"T18 по центру close можно кликнуть (не перекрыта скроллом)", "hit=%s close=%s" % [hit, cr])
	# Оффскрин-скан лавки (правило t30: size>=2, площадь < 95% поля, толерант 1px).
	ck(_offscreen_count(dy) == 0, "T18 UI shop: offscreen==0", _offscreen_list(dy))
	# t40 (находка t38, w_forge.log PIN#01): центрированная панель накрывала героя
	# у прилавка на 100 % (оконный прогон 1280x720, real-alpha маска спрайта).
	# Панель приставлена к ПРАВОМУ краю: [W − pw − gap .. W − gap]. Канон колонки
	# героя — центр поля: реально накрашенные пиксели героя x 311.6..328.4 (замер
	# probe_t40, тот же код камеры/zoom), поэтому правый док даёт 0 % перекрытия.
	# Порог 342 = 328.4 + ~14 px запаса (защита от отката к центрированию: у
	# центрированной панели левый край был 200); фактический левый край 396 —
	# 67.6 px чистого воздуха до колонки героя.
	ck(absf(pr.end.x - (CANON.x - shop.EDGE_GAP)) <= 1.0,
		"T40 панель приставлена к правому краю поля (зазор EDGE_GAP)", "right=%.1f gap=%.1f" % [pr.end.x, shop.EDGE_GAP])
	ck(pr.position.x >= 342.0,
		"T40 левый край панели правее колонки героя => герой читается", "left=%.1f герой=311.6..328.4" % pr.position.x)

	# Страховка переполнения: «витрина выросла» (260 px запас) — панель НЕ растёт
	# ниже поля, скролл появляется, close остаётся в поле, колесо мыши скроллит.
	var spacer := Control.new()
	spacer.name = "T18Spacer"
	spacer.custom_minimum_size = Vector2(0, 260)
	shop.list_vb.add_child(spacer)
	shop._fit_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var pr2: Rect2 = shop.panel.get_global_rect()
	var dy2: float = (CANON.y - pr2.size.y) * 0.5 - pr2.position.y
	var cr2: Rect2 = shop.close_btn.get_global_rect()
	ck(pr2.size.y <= SAFE_H + 0.5, "T18 страховка: панель не распухла выше поля", "h=%.1f" % pr2.size.y)
	ck(cr2.position.y + dy2 >= 0.0 and cr2.end.y + dy2 <= CANON.y,
		"T18 страховка: close по-прежнему целиком в viewport", "canon y=[%.1f..%.1f]" % [cr2.position.y + dy2, cr2.end.y + dy2])
	var bar := shop.scroll.get_v_scroll_bar()
	ck(bar.max_value > 0.0, "T18 страховка: полоса прокрутки появилась", "max=%.1f" % bar.max_value)
	# t40: правый док обязан пережить переполнение витрины — pw мог вырасти из-за
	# полосы прокрутки, но формуля дока даёт правый край W − EDGE_GAP при любой pw.
	ck(absf(pr2.end.x - (CANON.x - shop.EDGE_GAP)) <= 1.0,
		"T40 страховка: правый док держится при переполненной витрине", "right=%.1f w=%.1f" % [pr2.end.x, pr2.size.x])
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = shop.scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	# Godot 4: Control.push_input больше нет, а Viewport.push_input возвращает void.
	# ВАЖНО: координаты отдаём КАК ЛОКАЛЬНЫЕ для вьюпорта (local_coords=true) —
	# иначе событие трактуется как оконное и пересчитывается canvas-трансформом,
	# а в headless окно 64×64 при поле 640: пиккинг уходил бы в никуда.
	get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	await get_tree().process_frame
	ck(shop.scroll.scroll_vertical > 0.0,
		"T18 колесо мыши прокручивает витрину (скролл рабочий)", "val=%.1f" % shop.scroll.scroll_vertical)
	ck(shop.list_vb.position.y < 0.0,
		"T18 прокрутка реально сдвигает содержимое витрины", "list_y=%.1f" % shop.list_vb.position.y)
	shop.scroll.scroll_vertical = 0
	await get_tree().process_frame
	# t29 B-02 не сломана: под чужим окном лавка отдаёт мышь целиком — и новый
	# скролл в том числе (иначе полоса витрины глушила бы клики по диалогу смерти).
	var held := shop._holds_lock
	shop._holds_lock = false  # «лок принадлежит не нам» — эквивалент чужого окна сверху
	await get_tree().process_frame
	ck(shop.scroll.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"T18 B-02: скролл отдаёт мышь под чужим окном", "mf=%d" % shop.scroll.mouse_filter)
	shop._holds_lock = held
	await get_tree().process_frame
	ck(shop.scroll.mouse_filter == Control.MOUSE_FILTER_STOP,
		"T18 после ухода чужого окна скролл снова ловит мышь", "mf=%d" % shop.scroll.mouse_filter)
	spacer.queue_free()
	await get_tree().process_frame
	shop._fit_panel()
	await get_tree().process_frame
	ck(shop.scroll.scroll_vertical <= 0.5,
		"T18 после возвращения нормальной витрины скролл обнулился", "val=%.1f" % shop.scroll.scroll_vertical)
	var dy3: float = (CANON.y - shop.panel.get_global_rect().size.y) * 0.5 - shop.panel.get_global_rect().position.y
	ck(_offscreen_count(dy3) == 0, "T18 UI shop: offscreen==0 после цикла переполнения", _offscreen_list(dy3))
	# Хиттест НАСТОЯЩИМ курсором: заводим hover реальным движением мыши в центр
	# «Закрыть (Esc)» — под курсором должна оказаться именно кнопка, а не скролл
	# и не витрина (иначе клик по «видимой, но закрытой» кнопке — тот же V-06).
	# Координаты отдаём как локальные вьюпорту: в headless окно 64×64 при поле 640,
	# «оконные» координаты canvas-трансформ уводит в никуда.
	# Честно: сам клик (mouse button) headless-сервером до Controls не доходит —
	# ограничение движка, зафиксированное ещё в t29; реальный ЛКМ доказан
	# ОКОННЫМ прогоном 1280×720 (см. поставку t34: скриншот + трейс до/после).
	var cp: Vector2 = shop.close_btn.get_global_rect().get_center()
	var mo := InputEventMouseMotion.new()
	mo.position = cp
	mo.global_position = cp
	get_viewport().push_input(mo, true)
	await get_tree().process_frame
	ck(shop.close_btn.is_hovered() and not shop.scroll.get_global_rect().has_point(cp),
		"T18 центр close открыт курсору: под мышью сама кнопка",
		"hovered=%s cp=%s close=%s" % [shop.close_btn.is_hovered(), cp, shop.close_btn.get_global_rect()])
	Shop.close()
	ck(not Shop.is_open() and not bool(GameState.input_locked),
		"T18 лавка закрывается как раньше (Esc/кнопка, лок снят)",
		"open=%s locked=%s" % [Shop.is_open(), GameState.input_locked])
	# Открытие/закрытие по-прежнему работает как раньше (контракт t29 B-02 жив),
	# и лавка всегда открывается с начала витрины.
	Shop.open()
	await get_tree().process_frame
	ck(Shop.is_open() and bool(GameState.input_locked) and shop.scroll.scroll_vertical == 0.0,
		"T18 повторное открытие: лок взят, витрина с начала",
		"open=%s locked=%s val=%.1f" % [Shop.is_open(), GameState.input_locked, shop.scroll.scroll_vertical])
	Shop.close()
	ck(not Shop.is_open() and not bool(GameState.input_locked),
		"T18 закрытие после повторного открытия (лок снят)",
		"open=%s locked=%s" % [Shop.is_open(), GameState.input_locked])

	print("S1 DONE")


## t34 V-06: сколько элементов лавки висит за каноническим полем 640×360.
## dy — сдвиг «панель отцентрована в поле 360» (в headless окно другое, см. T18).
func _offscreen_count(dy: float) -> int:
	var n := 0
	var stack: Array = [shop.root]
	while not stack.is_empty():
		var c = stack.pop_back()
		for ch in (c as Node).get_children():
			if ch is Control:
				stack.append(ch)
		var ca := c as Control
		if ca == null or not ca.is_visible_in_tree():
			continue
		var r: Rect2 = ca.get_global_rect()
		r = Rect2(r.position + Vector2(0, dy), r.size)
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue
		if r.get_area() >= CANON.x * CANON.y * 0.95:
			continue  # полноэкранные dim/center/root — не «элемент за экраном»
		if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > CANON.x + 1.0 or r.end.y > CANON.y + 1.0:
			n += 1
	return n


## Те же элементы списком — для деталей FAIL'а.
func _offscreen_list(dy: float) -> String:
	var out: Array = []
	var stack: Array = [shop.root]
	while not stack.is_empty():
		var c = stack.pop_back()
		for ch in (c as Node).get_children():
			if ch is Control:
				stack.append(ch)
		var ca := c as Control
		if ca == null or not ca.is_visible_in_tree():
			continue
		var r: Rect2 = ca.get_global_rect()
		r = Rect2(r.position + Vector2(0, dy), r.size)
		if r.size.x < 2.0 or r.size.y < 2.0 or r.get_area() >= CANON.x * CANON.y * 0.95:
			continue
		if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > CANON.x + 1.0 or r.end.y > CANON.y + 1.0:
			out.append("%s@%s" % [ca.name, r])
	return "off=[%s]" % ", ".join(out)
