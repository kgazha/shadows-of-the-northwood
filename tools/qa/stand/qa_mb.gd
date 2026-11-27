extends "res://mb_base.gd"
## qa_mb — t20 P0-3 «мета-прогресс смерти»: экран смерти с итогами забега +
## Пепельная доска (таланты ×3 ранга) + ретеншн пепла 100% (t70: не догорает) + благословение
## волхвы (+2%/смерть круга, кап). Мир не поднимаем (паттерн qa_run): каналы
## GameState/Ash/Loot/MetaBoard/RunSummary напрямую; рантайм-панель R6 —
## RunSummary на голом Node-хосте (автолоады есть, hud нет — _busy ложен).
## Граница: qa_mb.gd/.tscn + запись в manifest.json (прецедент qa_gb, t19).

const ClassesData := preload("res://scripts/classes_data.gd")

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	r1_runstats()
	r2_board_purchase()
	r3_effects_on_new_run()
	r4_ash_retention_band()
	r5_volkhv_blessing()
	r8_master_x15()
	r9_procs()
	r7_infra_pins()
	await get_tree().process_frame
	await r6_death_screen()
	done()

# --- фикстура (паттерн qa_run.mk, независимая копия — стенды изолированы) ---

func mk(save: Dictionary) -> void:
	var base := {
		"v": 2, "class_id": "warrior", "level": 1, "xp": 0, "xp_next": 20,
		"max_hp": 12, "hp": 12, "mana": 0, "gold": 0, "seen_intro": true,
		"cave_state": 0, "in_cave": false,
		"gear": {"weapon": "", "armor": ""}, "flags": {},
	}
	for k in save:
		base[k] = save[k]
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(base))
	f = null
	GameState.load_game()

## Флаг ng_magnat превентивно: его порог meta.ash>=20, и если бы анлок случился
## внутри теста, grant_ash->Ash.add исказил бы rs.earned/баланс. Детерминизм.
const GUARD := {"ach.ng_magnat": 1}

func flags_with(extras: Dictionary) -> Dictionary:
	var f: Dictionary = GUARD.duplicate()
	for k in extras:
		f[k] = extras[k]
	return f

# --- R1: сбор статистики забега (rs.*) ---

func r1_runstats() -> void:
	mk({"flags": flags_with({})})
	Ash.add(5)
	check("R1: Ash.add(5) -> meta.ash=5", Ash.balance() == 5)
	check("R1: Ash.add(5) -> rs.earned=5 (счётчик заработка забега)", int(GameState.flags.get("rs.earned", -1)) == 5)
	Ash.add(2)
	check("R1: Ash.add(2) -> rs.earned=7", int(GameState.flags.get("rs.earned", -1)) == 7)
	check("R1: Ash.spend(3) -> true, баланс 4", Ash.spend(3) and Ash.balance() == 4)
	check("R1: трата НЕ отъедает rs.earned (остался 7)", int(GameState.flags.get("rs.earned", -1)) == 7)
	Loot.on_mob_death("slime", Vector2.INF)
	Loot.on_mob_death("slime", Vector2.INF)
	check("R1: Loot.on_mob_death x2 -> rs.k.slime=2", int(GameState.flags.get("rs.k.slime", -1)) == 2)
	Loot.on_mob_death("boss2", Vector2.INF)
	check("R1: босс считается по своему kind (rs.k.boss2=1)", int(GameState.flags.get("rs.k.boss2", -1)) == 1)
	# t70 (17.11): баланс 4, earned 7 — при смерти не сгорает НИЧЕГО: 4 и остаётся.
	# t38 I5 (перепин 27.11, мягкая смерть): rs.* при мягкой смерти НЕ стираются
	# вовсе (вайпа нет); вытирание rs — на отказном входе, пин ниже.
	GameState.soft_death()
	check("R1/t70+t38: после мягкой смерти баланс цел = 4 (заработанное не догорает)", Ash.balance() == 4)
	check("R1/t38: rs.earned при мягкой смерти ЦЕЛ (статистику забега не сжигают)", int(GameState.flags.get("rs.earned", -1)) == 7)
	check("R1/t38: rs.k.* при мягкой смерти целы", int(GameState.flags.get("rs.k.slime", -1)) == 2 and int(GameState.flags.get("rs.k.boss2", -1)) == 1)
	GameState.start_fresh_game()
	check("R1/t38: отказ от круга — rs.earned стёрт вайпом (прежний канон жив здесь)", not GameState.flags.has("rs.earned"))
	check("R1/t38: отказ от круга — rs.k.* стёрты вайпом", not GameState.flags.has("rs.k.slime") and not GameState.flags.has("rs.k.boss2"))

# --- R2: Пепельная доска — покупка/цены/кап/табличное чиселко ---

func r2_board_purchase() -> void:
	mk({"flags": flags_with({"meta.ash": 20})})
	check("R2: цена ранга 1 = 2 пепла", MetaBoard.next_cost(0) == 2)
	check("R2: цена ранга 2 = 5", MetaBoard.next_cost(1) == 5)
	check("R2: цена ранга 3 = 9", MetaBoard.next_cost(2) == 9)
	check("R2: за капом цены нет (-1)", MetaBoard.next_cost(3) == -1)
	check("R2: покупка 1-го ранга first_coal", MetaBoard.buy("first_coal"))
	check("R2: rank 1, списано 2 (баланс 18)", MetaBoard.rank_of("first_coal") == 1 and Ash.balance() == 18)
	check("R2: покупка 2-го ранга (цена 5) -> баланс 13", MetaBoard.buy("first_coal") and MetaBoard.rank_of("first_coal") == 2 and Ash.balance() == 13)
	check("R2: покупка 3-го ранга (цена 9) -> баланс 4", MetaBoard.buy("first_coal") and MetaBoard.rank_of("first_coal") == 3 and Ash.balance() == 4)
	check("R2: кап 3 ранга — покупка отказывает, деньги целы", not MetaBoard.buy("first_coal") and MetaBoard.rank_of("first_coal") == 3 and Ash.balance() == 4)
	check("R2: неизвестный id — отказ без траты", not MetaBoard.buy("nope") and Ash.balance() == 4)
	check("R2: coal_heart ранг 1 за 2 (баланс 2)", MetaBoard.buy("coal_heart") and Ash.balance() == 2)
	check("R2: ash_step ранг 1 за 2 (баланс 0)", MetaBoard.buy("ash_step") and Ash.balance() == 0)
	check("R2: не хватает пепла — отказ, ранг не вырос", not MetaBoard.buy("deep_pockets") and MetaBoard.rank_of("deep_pockets") == 0)
	check("R2: ранг живёт в meta.mb.<id> (вечный слой)", int(GameState.flags.get("meta.mb.first_coal", -1)) == 3)
	# таблица чисел — единственный источник и для хуков, и для UI
	check("R2: first_coal 15/30/50", MetaBoard.value_at_rank(1, "first_coal") == 15 and MetaBoard.value_at_rank(2, "first_coal") == 30 and MetaBoard.value_at_rank(3, "first_coal") == 50)
	check("R2: coal_heart 4/8/12", MetaBoard.value_at_rank(1, "coal_heart") == 4 and MetaBoard.value_at_rank(3, "coal_heart") == 12)
	check("R2: ash_step 4/8/12", MetaBoard.value_at_rank(2, "ash_step") == 8)
	check("R2: deep_pockets 8/16/24", MetaBoard.value_at_rank(3, "deep_pockets") == 24)
	check("R2: ранг 0 -> эффект 0; ранг вне таблицы -> 0", MetaBoard.value_at_rank(0, "first_coal") == 0 and MetaBoard.value_at_rank(7, "first_coal") == 0 and MetaBoard.value_at_rank(1, "nope") == 0)
	check("R2: GameState.mb_value читает флаги (first_coal=50)", GameState.mb_value("first_coal") == 50)

# --- R3: эффекты применяются к новому забегу (числа) ---

func r3_effects_on_new_run() -> void:
	mk({"flags": flags_with({"meta.purse": 1, "meta.mb.first_coal": 2, "meta.mb.coal_heart": 3})})
	# t38 I5 (перепин 27.11): «золото нового забега» отныне платится только на
	# отказном/победном входах («Новая игра»/арка) — смерть его не сбрасывает.
	GameState.start_fresh_game()
	check("R3: золото нового забега = 50*purse(1) + first_coal(30) = 80", GameState.gold == 80)
	var base_hp := int(ClassesData.class_data("warrior").hp)
	check("R3: макс. HP = база(%d) + coal_heart(12) = %d" % [base_hp, base_hp + 12], GameState.max_hp == base_hp + 12)
	check("R3: герой входит в забег с полным HP", GameState.hp == GameState.max_hp)
	mk({"flags": flags_with({"meta.purse": 0})})
	GameState.start_fresh_game()  # t38 I5 (27.11): грант «Кошелька» — отказной вход
	check("R3: ранги 0 -> тождество qa_run (золото 0, purse 0)", GameState.gold == 0)
	GameState.flags["meta.mb.ash_step"] = 1
	check("R3: ash_step ранг 1 -> множитель скорости +4% (mb_value=4)", GameState.mb_value("ash_step") == 4)
	GameState.flags["meta.mb.deep_pockets"] = 1
	check("R3: deep_pockets ранг 1 -> надбавка золота мобов +8% (mb_value=8)", GameState.mb_value("deep_pockets") == 8)

# --- R4: t70 (17.11) «earnings survive death fully» — заработанное переживает
#     смерть и отказ от круга на 100 % (прежнее догорание 35 % убрано) ---

func r4_ash_retention_band() -> void:
	# t70: правило keep = floor(earned × 0.65) убрано ВМЕСТЕ с константами. Пин
	# держит два факта: дельта баланса при конце забега = ровно 0 (весь заработок
	# уже начислен Ash.add), и констант догорания в GameState нет — иначе
	# «балансировку» вернут молча, а экран смерти снова начнёт врать игроку.
	var consts: Dictionary = GameState.get_script().get_script_constant_map()
	check("R4/t70: констант догорания в GameState нет (RATE/MIN/MAX)",
		not consts.has("ASH_KEEP_RATE") and not consts.has("ASH_KEEP_MIN") and not consts.has("ASH_KEEP_MAX"))
	for e in [10, 20, 50, 100, 1000]:
		mk({"flags": flags_with({"meta.ash": 90})})
		var b0 := Ash.balance()
		Ash.add(e)  # боевой канал: баланс и rs.earned растут вместе
		check("R4/t70: earned=%d -> надбавка баланса ровно %+d (%d->%d)" % [e, e, b0, Ash.balance()], Ash.balance() == b0 + e)
		GameState.soft_death()  # t38 I5 (27.11): смерть мягкая — пепел и подавно цел
		check("R4/t70: смерть при earned=%d -> баланс цел %d (при keep 0.65 было бы %d)" % [
			e, b0 + e, b0 + int(floor(0.65 * e))], Ash.balance() == b0 + e)
	# тот же заработок переживает «Новую игру» (отказ от круга) — оба пути когерентны
	for e2 in [10, 100]:
		mk({"flags": flags_with({"meta.ash": 90})})
		var b1 := Ash.balance()
		Ash.add(e2)
		GameState.start_fresh_game()
		check("R4/t70: start_fresh_game при earned=%d -> баланс цел %d" % [e2, b1 + e2], Ash.balance() == b1 + e2)
	# вечный remainder как не горел, так и не горит: 100 баланса / 10 заработано -> 100
	mk({"flags": flags_with({"meta.ash": 100, "rs.earned": 10})})
	GameState.soft_death()  # t38 I5 (27.11): мягкая смерть — догоранию тем более негде быть
	check("R4/t70: balance 100 / earned 10 -> 100 (ничего не сгорело)", Ash.balance() == 100)
	# заработанное проедено: баланс 3 при rs.earned 10 -> смерть ничего не снимает
	mk({"flags": flags_with({"meta.ash": 3, "rs.earned": 10})})
	GameState.soft_death()
	check("R4/t70: earned>balance -> баланс 3 цел (вычитания больше нет)", Ash.balance() == 3)
	# канон qa_run R2: заработано 0 -> баланс нетронут (12)
	mk({"flags": flags_with({"meta.ash": 12})})
	GameState.soft_death()
	check("R4: earned=0 -> баланс 12 цел (qa_run-канон «мета-слой вечен»)", Ash.balance() == 12)


# --- R5: благословение волхвы (+2%/смерть круга, кап, сброс на новом круге) ---

func r5_volkhv_blessing() -> void:
	mk({"flags": flags_with({})})
	check("R5: константы: BLESS_PER_DEATH=0.02, кап=10", GameState.BLESS_PER_DEATH == 0.02 and GameState.BLESS_CAP_DEATHS == 10)
	check("R5: старт: стопки 0, множитель 1.0", GameState.volkhv_stacks() == 0 and is_equal_approx(GameState.volkhv_bless_mult(), 1.0))
	GameState.soft_death()  # t38 I5 (27.11): ставка круга живёт в мягкой смерти
	check("R5: смерть 1 -> meta.vd=1", int(GameState.flags.get("meta.vd", -1)) == 1)
	check("R5: множитель 1.02", is_equal_approx(GameState.volkhv_bless_mult(), 1.02))
	for i in range(11):
		GameState.soft_death()
	check("R5: 12 смертей -> vd=12", int(GameState.flags.get("meta.vd", -1)) == 12)
	check("R5: кап: стопки=10, множитель 1.20 (+20%)", GameState.volkhv_stacks() == 10 and is_equal_approx(GameState.volkhv_bless_mult(), 1.2))
	GameState.start_ng_plus()
	check("R5: новый круг — vd=0, благословение выгорело (1.0)", int(GameState.flags.get("meta.vd", -1)) == 0 and is_equal_approx(GameState.volkhv_bless_mult(), 1.0))
	check("R5: не путать с алтарём: meta.bless не трогается смертью", meta_bless_untouched())

func meta_bless_untouched() -> bool:
	mk({"flags": flags_with({"meta.bless": 2})})
	GameState.soft_death()  # t38 I5 (27.11): та же ставка, новый канал
	return int(GameState.flags.get("meta.bless", -1)) == 2 and int(GameState.flags.get("meta.vd", -1)) == 1

## t38 I5 (27.11): число кнопок экрана смерти (VBox панели): было 3 с t9
## («Доска», «Вспыхнуть», «Выбрать класс»), стало 2 — классовый аффорданс снят
## вместе с обнулением класса.
func _rs_buttons(rs) -> int:
	var n := 0
	for c in rs.panel.get_children():
		for cc in c.get_children():
			if cc is Button:
				n += 1
	return n

# --- R6: экран смерти — содержимое ярлыков + Esc-маршрут + доска ---

func r6_death_screen() -> void:
	mk({"flags": flags_with({
		"ach.n.deaths": 4, "meta.ash": 9, "rs.earned": 8, "rs.t": 65.0,
		"rs.zone": "cave", "rs.src": "brute", "rs.k.slime": 2,
		"ng.wave": 2, "ng.boss_2": 1, "ashen.boss": "dead", "meta.vd": 2,
		# t38 I5 (перепин 27.11): экран открывается ПОСЛЕ soft_death — фикстура
		# играет уже списанную цену и уже инкрементированные ставки.
		"meta.last_loss": 8,
	}), "gold": 41, "run_seed": 777})
	var host := Node.new()
	host.name = "RSHost"
	add_child(host)
	var rs := RunSummary.new()
	host.add_child(rs)
	await get_tree().process_frame
	RunSummary.open()
	check("R6: панель открылась на голом хосте (is_open)", RunSummary.is_open())
	# t52 снос (закон 13.11): ген-декор «бумажная кромка» снят — экран смерти
	# живёт на чистых code-stylebox панелях. Пин новой нормы: PaperEdge не
	# примонтирован ни соседом, ни ребёнком (класс жив, инстансов нет).
	await get_tree().process_frame  # layout: rect панели зафиксирован
	var paper_any := false
	for c in rs.root.get_children():
		if c is PaperEdge:
			paper_any = true
	for c in rs.panel.get_children():
		if c is PaperEdge:
			paper_any = true
	check("R6: PaperEdge снесён — экран смерти без ген-кромки (t52)", not paper_any and rs.panel != null)
	var st := rs.stats_lbl.text
	# t38 I5 (перепин 27.11): экран мягкой смерти — заголовок и КРУПНАЯ сумма
	# потери. head — первый Label первого контейнера панели (структура _build).
	var head_lbl: Label = null
	for c in rs.panel.get_children():
		if head_lbl != null:
			break
		for cc in c.get_children():
			if cc is Label:
				head_lbl = cc as Label
				break
	check("R6/t38: заголовок мягкой смерти («Тьма забрала тебя»)", head_lbl != null and head_lbl.text == "Тьма забрала тебя")
	check("R6/t38: крупное «Потеряно 8 серебра» (meta.last_loss, прошедшее время)", rs.loss_lbl.text == "Потеряно 8 серебра")
	check("R6/t38: счётчик смертей на экране («Смертей: 4» — ставка видна)", st.contains("Смертей: 4"))
	check("R6/t38: аффордансов выбора класса больше нет (класс цел) — кнопок две", _rs_buttons(rs) == 2)
	check("R6: сид показан (Сид: 777)", st.contains("Сид: 777"))
	check("R6: глубина/волна показана (Круг (глубь): 2)", st.contains("Круг (глубь): 2"))
	check("R6: время mm:ss (Время: 01:05)", st.contains("Время: 01:05"))
	check("R6: золото показано (Золото: 41)", st.contains("Золото: 41"))
	check("R6/t70: пепел: заработано 8 / сохраняется всё", st.contains("заработано 8") and st.contains("сохраняется всё"))
	# t13 перепин 25.11 (замена брютов «Тлель-вепрь», лист «Замена v1»): kind
	# "brute" — моб, его RU-имя теперь «Тлель-вепрь»; босс — отдельная ветка
	# kill_src()="boss" («Осквернённый Гром» в покрве run_summary).
	check("R6: убийца — RU-имя из AchvCatalog (Пал от: Тлель-вепрь)", st.contains("Пал от: Тлель-вепрь"))
	check("R6: убийства по типам (Слайм ×2)", rs.kills_lbl.text.contains("Слайм ×2"))
	check("R6: статус боссов (Гром повержен / Ведьма повержена)", rs.kills_lbl.text.contains("Гром повержен") and rs.kills_lbl.text.contains("Ведьма повержена"))
	# t38 I5 (перепин 27.11): экран открывается ПОСЛЕ soft_death — meta.vd уже
	# включает эту смерть, «+1 в прогноз» снят: vd=2 -> +4% (было «+6% (vd=2 +
	# эта смерть = 3)» терминальной эпохи).
	check("R6/t38: благословение в UI: +4% (vd=2 уже с этой смертью)", rs.bless_lbl.text.contains("+4%"))
	check("R6: кнопка «Доска пепла» + доска-дитя созданы", rs.board_btn != null and rs.board != null)
	# Esc-маршрут: 1-й Esc закрывает открытую доску, 2-й — «Вспыхнуть у костра»
	MetaBoard.open()
	check("R6: доска открыта поверх экрана смерти", MetaBoard.is_open())
	# t52 снос: и доска пепла — без ген-кромки (только code-stylebox панели).
	await get_tree().process_frame
	var bpaper_any := false
	for c in rs.board.root.get_children():
		if c is PaperEdge:
			bpaper_any = true
	for c in rs.board.panel.get_children():
		if c is PaperEdge:
			bpaper_any = true
	check("R6: PaperEdge доски снесён — доска без ген-кромки (t52)", not bpaper_any and rs.board.panel != null)
	# t27 P0-1: eff-текст каждой строки доски непустой и ровно fmt % значение
	# ранга (в бейзлайне fmt содержал одинарный '%' -> String formatting error
	# -> две строки таблицы были битыми; пустоты/неотформатированных строк быть не должно)
	var brows: Array = []
	for c in rs.board.rows_box.get_children():
		if not c.is_queued_for_deletion():  # пересборка рядов делает queue_free старых
			brows.append(c)
	check("t27: рядов доски ровно по таблице (%d) (факт=%d)" % [MetaBoard.TALENTS.size(), brows.size()], brows.size() == MetaBoard.TALENTS.size())
	for i in mini(brows.size(), MetaBoard.TALENTS.size()):
		var t: Dictionary = MetaBoard.TALENTS[i]
		var trow := brows[i] as PanelContainer
		var eff: Label = null
		if trow != null and trow.get_child_count() > 0:
			var hb: Node = trow.get_child(0)
			if hb.get_child_count() > 0:
				var col: Node = hb.get_child(0)
				if col.get_child_count() > 1:
					eff = col.get_child(1) as Label
		var want: String = String(t["fmt"]) % int((t["vals"] as Array)[MetaBoard.rank_of(String(t["id"]))])
		var got := "" if eff == null else eff.text
		check("t27: eff-строка '%s' непустая и форматирована ('%s')" % [String(t["id"]), want],
			eff != null and got != "" and got == want)
	# --- t32: двойная трата Пепла (находка artist-hud из t29) ---
	# Ряды гасятся queue_free() и остаются в дереве ХИТТЕСТABLE до конца кадра,
	# поэтому два «pressed» одной кнопки в одном физическом кадре проходили обе
	# валидации: ранг +2 и −7 пепла за покупку ранга 1 (цена 2). Каждый шаг ниже
	# стартует с чистого состояния (ранг 0, баланс 20) — иначе состояние перетекает
	# из шага в шаг и проверка становится вакуумной (на сломанном коде шаг 2
	# проходил лишь потому, что первый шаг уже упёрся в кап).
	var d_id: String = String(MetaBoard.TALENTS[0]["id"])
	var d_id2: String = String(MetaBoard.TALENTS[1]["id"])
	var d_ash_saved := Ash.balance()
	var d_row: PanelContainer = brows[0] as PanelContainer
	var d_btn: Button = null
	if d_row != null and d_row.get_child_count() > 0:
		var dhb: Node = d_row.get_child(0)
		if dhb.get_child_count() > 1:
			d_btn = dhb.get_child(1) as Button
	check("t32: кнопка покупки ряда «%s» найдена и активна" % d_id, d_btn != null and not d_btn.disabled)

	# шаги 1/2: ровно одна покупка на кадр (двойной клик по ещё живой строке)
	for step in ["pressed.emit()", "_on_buy()"]:
		GameState.flags["meta.ash"] = 20
		GameState.flags[MetaBoard.KEY_PREFIX + d_id] = 0
		rs.board._rebuild()
		var d_r0 := MetaBoard.rank_of(d_id)
		var d_a0 := Ash.balance()
		var d_c0 := MetaBoard.next_cost(d_r0)
		if step == "pressed.emit()":
			# два сигнала ОДНОЙ кнопки в одном кадре — так выглядит двойной клик
			# по строке, которая ещё не уничтожена (queue_free в конце кадра)
			d_btn.pressed.emit()
			d_btn.pressed.emit()
		else:
			# прямой двойной вызов обработчика в одном кадре (обход хиттеста)
			rs.board._on_buy(d_id)
			rs.board._on_buy(d_id)
		check("t32: %s x2 в одном кадре -> ровно один ранг +1 (факт +%d)" \
			% [step, MetaBoard.rank_of(d_id) - d_r0], MetaBoard.rank_of(d_id) == d_r0 + 1)
		check("t32: %s x2 в одном кадре -> ровно одно списание %d (ожидали %d, факт %d)" \
			% [step, d_c0, d_a0 - d_c0, Ash.balance()], Ash.balance() == d_a0 - d_c0)
		await get_tree().process_frame

	# шаг 3: штатные одиночные покупки всех рангов в разных кадрах работают как
	# прежде (защита от двойной траты не имеет права блокировать покупки)
	GameState.flags["meta.ash"] = 20
	GameState.flags[MetaBoard.KEY_PREFIX + d_id] = 0
	rs.board._rebuild()
	var d_ok := true
	var d_trace := ""
	for want in [1, 2, 3]:
		var cost_w: int = MetaBoard.next_cost(MetaBoard.rank_of(d_id))
		var ash_w: int = Ash.balance()
		rs.board._on_buy(d_id)
		var ok: bool = MetaBoard.rank_of(d_id) == int(want) and Ash.balance() == ash_w - cost_w
		d_ok = d_ok and ok
		d_trace += "r%d(-%d)->%d/%d " % [int(want), cost_w, MetaBoard.rank_of(d_id), Ash.balance()]
		await get_tree().process_frame
	check("t32: штатные покупки рангов 1/2/3 по одному клику не изменились (%s)" % d_trace.strip_edges(),
		d_ok and Ash.balance() == 20 - 2 - 5 - 9)
	# шаг 4: семантика «одна покупка на кадр» для РАЗНЫХ рядов (документирована):
	# второй ряд в том же кадре не тратится, в следующем — покупается штатно
	GameState.flags["meta.ash"] = 20
	GameState.flags[MetaBoard.KEY_PREFIX + d_id] = 0
	GameState.flags[MetaBoard.KEY_PREFIX + d_id2] = 0
	rs.board._rebuild()
	rs.board._on_buy(d_id)
	rs.board._on_buy(d_id2)
	check("t32: другой ряд в том же кадре не тратится (первый куплен, второй ждёт кадр)",
		MetaBoard.rank_of(d_id) == 1 and MetaBoard.rank_of(d_id2) == 0 and Ash.balance() == 18)
	await get_tree().process_frame
	rs.board._on_buy(d_id2)
	check("t32: в следующем кадре второй ряд покупается штатно",
		MetaBoard.rank_of(d_id2) == 1 and Ash.balance() == 16)
	# шаг 5: СИНХРОННАЯ валидация по фактическому рангу: обработчик знает ранг,
	# под которым кнопка была отрисована (bind), и обязан отказать, если ранг уже
	# уехал — независимо от того, в одном кадре клик или в другом.
	await get_tree().process_frame
	GameState.flags["meta.ash"] = 20
	GameState.flags[MetaBoard.KEY_PREFIX + d_id] = 1
	rs.board._rebuild()
	var d_s_a := Ash.balance()
	rs.board._on_buy(d_id, 0)   # «кнопка из-под ранга 0», а фактический ранг 1
	check("t32: устаревшая кнопка (рисована для ранга 0 при ранге 1) отказывает, пепел цел (%d)" \
		% d_s_a, Ash.balance() == d_s_a and MetaBoard.rank_of(d_id) == 1)
	rs.board._on_buy(d_id, 1)   # актуальный ранг — покупка проходит
	check("t32: кнопка с актуальным рангом покупает как прежде",
		MetaBoard.rank_of(d_id) == 2 and Ash.balance() == d_s_a - 5)
	# шаг 6: кап-ряд «Макс.» — кнопка дизейблена, покупка за капом отказывает
	GameState.flags[MetaBoard.KEY_PREFIX + d_id] = MetaBoard.COSTS.size()
	await get_tree().process_frame
	rs.board._rebuild()
	var d_crow: PanelContainer = null
	for c in rs.board.rows_box.get_children():
		if not c.is_queued_for_deletion():
			d_crow = c as PanelContainer
			break
	var d_cbtn: Button = null
	if d_crow != null and d_crow.get_child_count() > 0:
		var chb: Node = d_crow.get_child(0)
		if chb.get_child_count() > 1:
			d_cbtn = chb.get_child(1) as Button
	var d_ca := Ash.balance()
	check("t32: кап-ряд — кнопка «Макс.» и она дизейблена (текст '%s')" \
		% ("" if d_cbtn == null else d_cbtn.text), d_cbtn != null and d_cbtn.disabled and d_cbtn.text == "Макс.")
	rs.board._on_buy(d_id)
	rs.board._on_buy(d_id)
	check("t32: двойной вызов на кап-ряде ничего не тратит (баланс %d, факт %d)" % [d_ca, Ash.balance()],
		Ash.balance() == d_ca and MetaBoard.rank_of(d_id) == MetaBoard.COSTS.size())
	GameState.flags["meta.ash"] = d_ash_saved
	rs.board._rebuild()
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	rs._unhandled_input(ev)
	check("R6: 1-й Esc закрыл ТОЛЬКО доску", not MetaBoard.is_open() and RunSummary.is_open())
	# t38 I5 (ПЕРЕПИН 27.11, мягкая смерть): прежние пины «2-й Esc = rekindle:
	# deaths 4->5» и «rekindle сжёг rs.*» сняты — смерть оплачивается в
	# world.on_player_death()/soft_death(), а не на кнопке; rs жив; а сам
	# _rekindle теперь ещё и перезагружает сцену (reload_current_scene) — для
	# сцены стенда это смерть корутины. Пин разбит: payload воскресения через
	# GameState, идемпотентность и проводка кнопки — под щитом _finalized.
	check("R6/t38: до решения экран живёт (Esc закрыл доску, экран на месте)", RunSummary.is_open())
	GameState.respawn_after_death()
	check("R6/t38: воскресение домой: area=village, in_cave=false, полный hp",
		String(GameState.area) == "village" and GameState.in_cave == false and GameState.hp == GameState.max_hp)
	check("R6/t38: rs.* при мягкой смерти ЦЕЛЫ (прежний пин «сгорели» снят 27.11)",
		GameState.flags.has("rs.k.slime") and GameState.flags.has("rs.zone") and GameState.flags.has("rs.src"))
	check("R6/t38: счётчик смертей уплачен на самой смерти — кнопка его не двигает (4 стоит)",
		int(GameState.flags.get("ach.n.deaths", -1)) == 4)
	rs._finalized = true
	rs._unhandled_input(ev)  # «второй Esc» после решения: no-op, без reload
	check("R6/t38: щит _finalized: Esc после решения не гасит экран (стенд не перезаряжается)",
		RunSummary.is_open() and not MetaBoard.is_open())
	rs.rekindle_btn.pressed.emit()
	check("R6/t38: проводка кнопки под _finalized безопасна (no-op без краха/reload)", RunSummary.is_open())
	host.queue_free()
	await get_tree().process_frame

# --- R8 (t39): «Мастерство» алтаря Пепла = ровно +15% за покупку, кап 3 ---

func r8_master_x15() -> void:
	# База 20 выбрана против float-шума: 20×1.15=22.999…→23, 20×1.3=26.000…4→26,
	# 20×1.45=28.999…6→29 (round() в GDScript — от нуля; узкие места исключены).
	var f := preload("res://scripts/gear_data.gd")
	mk({"flags": flags_with({"meta.master": 1})})
	check("R8-t39: мастер f=1 → 20×1.15 = 23", int(f.player_damage(20, GameState)) == 23)
	mk({"flags": flags_with({"meta.master": 2})})
	check("R8-t39: мастер f=2 → 20×1.30 = 26", int(f.player_damage(20, GameState)) == 26)
	mk({"flags": flags_with({"meta.master": 3})})
	check("R8-t39: мастер f=3 (кап) → 20×1.45 = 29", int(f.player_damage(20, GameState)) == 29)
	mk({"flags": flags_with({"meta.master": 9})})
	check("R8-t39: кап f≤3 держится (meta.master=9 → всё равно 29)", int(f.player_damage(20, GameState)) == 29)
	mk({"flags": flags_with({})})
	check("R8-t39: без мастера регресс 20", int(f.player_damage(20, GameState)) == 20)
	# source-пин: множитель именно 0.15 (t38 было 0.10)
	var fs := FileAccess.open("res://scripts/gear_data.gd", FileAccess.READ)
	var src := fs.get_as_text() if fs != null else ""
	check("R8-t39: gear_data содержит 0.15 * f (ровно +15%/стек)", src.contains("0.15 * f") and not src.contains("0.10 * f"))

# --- R7: инфраструктурные пины (PaperEdge/AshIcon/таблица доски) ---

func r7_infra_pins() -> void:
	var pe := PaperEdge.new()
	check("R7: global class_name PaperEdge доступен (вынесен из journal.gd)", pe != null)
	pe.free()
	check("R7: ген-ассет бумажной кромки снесён (t52, закон 13.11)", not ResourceLoader.exists("res://assets/ui/decor_paper_edge.png"))
	var ic := AshIcon.make()
	check("R7: AshIcon.make() — код-иконка ImageTexture 16×16 (t52 стаб вместо ген-атласа)",
		ic is ImageTexture and (ic as ImageTexture).get_width() == 16 and (ic as ImageTexture).get_height() == 16)
	var ash_img: Image = (ic as ImageTexture).get_image() if ic is ImageTexture else null
	var ash_ink := 0
	if ash_img != null:
		for yy in ash_img.get_height():
			for xx in ash_img.get_width():
				if ash_img.get_pixel(xx, yy).a > 0.0:
					ash_ink += 1
	check("R7: код-иконка пепла непустая (непрозрачных пикселей %d > 0)" % ash_ink, ash_ink > 0)
	# g19 РЕ-ПИН (вердикт 16.11 22:44 «Проки перенеси в таланты, а не за очки
	# пепла»): с экрана смерти сняты proc-ряды, таблица доски сведена к вечной
	# четвёрке. Прежний пин 6 (4+2 прока) отзыван вместе с волной g17-моделей.
	check("R7: доска — 4 вечных таланта (proc-ряды сняты в g19)", MetaBoard.TALENTS.size() == 4)
	var ok := true
	for t in MetaBoard.TALENTS:
		var vals: Array = t["vals"]
		if String(t["id"]) == "" or vals.size() != 3:
			ok = false
	check("R7: каждый талант — id + ровно 3 значения рангов", ok)

# --- R9: g19 — доска БЕЗ проков + миграция старых proc-токенов в таланты ---
# (вердикт 16.11 22:44: «Проки перенеси в таланты, а не за очки пепла».)

func r9_procs() -> void:
	mk({"flags": flags_with({"meta.ash": 20})})
	var bf := "boar_fang"
	var ta := "twisted_arrow"
	check("R9: доска чиста: 4 вечных, proc_ids() пуст (стопор против возврата)",
		MetaBoard.TALENTS.size() == 4 and MetaBoard.proc_ids().is_empty())
	check("R9: proc id больше не таблицный — цены дефолтной линейки [2,5,9], покупка отказана, пепел цел",
		MetaBoard.next_cost(1, bf) == 5 and not MetaBoard.buy(bf) and Ash.balance() == 20)
	check("R9: вечная четвёрка покупается как прежде (coal_heart ранг 1 за 2, баланс 18)",
		MetaBoard.buy("coal_heart") and Ash.balance() == 18)
	# t38 I5 (перепин 27.11): мягкая смерть — вечный слой цел как прежде
	GameState.soft_death()
	check("R9: мягкая смерть — вечный coal_heart уцелел", MetaBoard.rank_of("coal_heart") == 1)
	# --- миграция meta.mb.<proc> -> tal.<proc> (класс совпал / не совпал) ---
	mk({"class_id": "warrior", "level": 3, "flags": flags_with({
		"meta.mb.boar_fang": 2, "meta.mb.twisted_arrow": 1})})
	check("R9: воин — свой токен стал рангом таланта бесплатно (boar_fang=2)",
		GameState.tal_rank(bf) == 2)
	check("R9: чужой токен стёрт без ранга (twisted_arrow у воина не появляется)",
		GameState.tal_rank(ta) == 0 and not GameState.flags.has("tal." + ta))
	check("R9: токены исчезли из вечного слоя",
		not GameState.flags.has("meta.mb." + bf) and not GameState.flags.has("meta.mb." + ta))
	check("R9: подарок не ест очки: level=3 с рангом 2 имеет те же 2 очка, что и без токенов",
		GameState.tal_rank(bf) == 2 and GameState.tal_points() == 2)
	GameState.save_game()
	GameState.load_game()
	check("R9: идемпотентность — повторная загрузка ничего не добавляет",
		GameState.tal_rank(bf) == 2 and int(GameState.flags.get("tal.gift", 0)) == 2)
	# t38 I5 (перепин 27.11): мягкая смерть tal.* НЕ трогает (qa_run D4); сгорает
	# прок только на отказном входе «Новая игра» — общий вайп жив там.
	GameState.start_fresh_game()
	check("R9: отказ от круга — прок-ранг и gift сгорели в общем вайпе tal.*",
		GameState.tal_rank(bf) == 0 and not GameState.flags.has("tal.gift"))
	# пин «аудиозапись в реестре»: прок-клавесин зарегистрирован и собирается
	check("R9: «прок-клавесин» записан в кодоген-реестре (KEYS+GAIN)",
		SfxCatalog.KEYS.has("proc_chime") and SfxCatalog.GAIN.has("proc_chime"))
	var pw := SfxCatalog.build("proc_chime")
	check("R9: «прок-клавесин» собирается в настоящий буфер (dur=%.2f c, байт=%d)" % [
			pw.get_length(), pw.data.size()],
		pw != null and pw.format == AudioStreamWAV.FORMAT_16_BITS and not pw.stereo
			and pw.mix_rate == 22050 and pw.get_length() >= 0.3)
