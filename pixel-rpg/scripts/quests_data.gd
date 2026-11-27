class_name QuestsData
extends RefCounted
## Статический реестр квестов «Теней Северного Леса» (волна «контент»).
##
## Модель: квест = id + название + описание + цепочка целей. Прогресс считается
## ТОЛЬКО как функция от GameState (var-поля, get_flag) — никакой записи в
## GameState, кроме set_flag для служебных флагов с префиксом "q." и emit
## сигналов toast / quest_changed (автостарт/завершение побочных квестов).
##
## Сюжетные квесты (elder/slime/cave) обёрнуты в эту модель, но их поля-канон
## (elder_quest / slime_quest / cave_state) остаются в GameState и здесь
## только читаются — переходы по-прежнему пишет world.gd через диалоги.
##
## Служебные флаги системы (хранилище GameState.flags, префикс "q."):
##  "q.<quest_id>" — статус побочного квеста: 1 активен, 2 выполнен (нет = 0);
##  "q.got.<mat>"  — накоплено материала за игру (для целей типа collect_mat);
##  "q.last.<mat>" — последнее виденное количество материала (для счёта дельты).
##
## Единственный носитель системы — journal.gd: он дёргает refresh() тиком.
## Без журнала (не интегрирован) квесты-обёртки читаются корректно, но
## автостарт побочек не происходит — это штатная деградация.

const FLAG_PREFIX := "q."        # статусы побочных квестов: "q." + id

const BTY := preload("res://scripts/bounties.gd")  # t36 I3: охоты доски (журнал)
const GOT_PREFIX := "q.got."     # накоплено материала: "q.got." + material id
const LAST_PREFIX := "q.last."   # последнее виденное кол-во: "q.last." + id

const STATUS_NONE := 0     # не начат (для побочек — не виден в журнале)
const STATUS_ACTIVE := 1   # активен
const STATUS_DONE := 2     # выполнен

# g12/BALANCE.md: «новые» цифры главы 1 — один реестр, каждая запинена QA.
# Строки 1–2 таблицы баланса (сдачи сюжетных квестов главы «Деревня»);
# PRICE_RESIN/PRICE_TORCH/PRICE_POTION (строки 6–8) — проводка Г1.3–Г1.5.
const GOLD_QUEST_TREES := 20    # «Три коренья», сдача Морге (опыт +25 — как есть)
const GOLD_QUEST_SLIMES := 30   # «Трофеи со слаймов», сдача Драну (плюс к опыту +30)

## Реестр. Порядок словаря = порядок показа в журнале (сюжетные первыми).
## Цели: {"type", "label", "need", ["mat"]} — прогресс считает progress() по type.
## Поле "when" (только побочки) — код условия автостарта в _cond_met().
## Поле "reward": {"xp": N} (побочки) — выдаётся однократно при автозавершении
## (флаг DONE ставится до выдачи — повтор исключён идемпотентностью статуса).
## Поле "permanent_done": "<flag>" — доп. метка завершения, переживающая вайп
## "q.*" при смене круга (мгновенный ре-фарш badge-квестов в NG+ исключён).
const QUESTS := {
	"elder": {
		# GLOSSARY #21: в журнале — «Три коренья» (разг. Морги); старое название
		# «Травы для старейшины» снято проводкой g12 (заменено, не дополнено).
		"title": "Три коренья",
		"desc": "Старейшина Морга хворает. Три коренья с южной опушки — и она встанет.",
		"story": true,
		"targets": [
			{"type": "talk_elder", "label": "Поговорить со старейшиной", "need": 1},
			{"type": "collect_herb", "label": "Собрать коренья у кустов", "need": 3},
			{"type": "deliver_elder", "label": "Отнести коренья старейшине", "need": 1},
		],
	},
	"slime": {
		"title": "Трофеи со слаймов",
		"desc": "Торговец платит за доказанные победы над слаймами тощего леса.",
		"story": true,
		"targets": [
			{"type": "kill_slime", "label": "Разобраться со слаймами", "need": 3},
			{"type": "deliver_slime", "label": "Вернуться к торговцу за наградой", "need": 1},
		],
	},
	"cave": {
		"title": "Осквернённый гром",
		"desc": "Говорят, отшельник Геральд ждёт в пещере того, кто снимет порчу с Амулета Леса.",
		"story": true,
		"targets": [
			{"type": "visit_cave", "label": "Найти пещеру в лесу", "need": 1},
			{"type": "defeat_boss", "label": "Одолей Осквернённый гром", "need": 1},
			{"type": "get_key", "label": "Получить ключ от Геральда", "need": 1},
			{"type": "open_door", "label": "Открыть дверь алтарной ниши", "need": 1},
			{"type": "take_amulet", "label": "Взять Амулет Леса из сундука", "need": 1},
			{"type": "return_amulet", "label": "Вернуть амулет Геральду", "need": 1},
		],
	},
	"witch": {
		"title": "Ведьма Пепелища",
		"desc": "В выжженной пустоши на востоке за деревней затаилась Ведьма. Пока она цела, круг пепла не замкнётся — и не разомкнётся.",
		"story": true,
		"targets": [
			{"type": "kill_witch", "label": "Найти и покончить с Ведьмой", "need": 1},
		],
	},
	"q_suhotsvet": {
		"title": "Сухоцвет впрок",
		"desc": "Сухоцвет — трофей со слаймов, основа зелий. Собери пять штук: считается накопленное, варить можно.",
		"when": "has_suhotsvet",
		"targets": [
			{"type": "collect_mat", "mat": "suhotsvet", "label": "Собрать сухоцвет", "need": 5},
		],
	},
	"q_campfires": {
		# Фидбек баланса: костёр в мире один (world.CAMPFIRE_SPOTS) — цель на круг
		# одна отдых-точка, «три костра» недостижима за круг честной игрой.
		"title": "Привал у костра",
		"desc": "Старая примета: кто отдохнул у костра Северного Леса — тому лес больше не враг.",
		"when": "first_campfire",
		"targets": [
			{"type": "rest_campfire", "label": "Отдохнуть у костра", "need": 1},
		],
	},
	"q_slimehunt": {
		"title": "Зачистка леса",
		"desc": "Торговец просит не останавливаться на трёх: вычисти лес так, чтобы слаймов стало вполовину меньше.",
		"when": "slime_quest_done",
		"targets": [
			{"type": "kill_slime", "label": "Уничтожить слаймов (в этом круге)", "need": 8},
		],
	},
	"q_brewer": {
		"title": "Варка на славу",
		"desc": "Знахарка варит не по одному зелью за присест. Свари шесть зелий — пояс тут ни при чём, считается мастерство.",
		"when": "brewer_watch",
		"permanent_done": "meta.q_brewer_done",
		"reward": {"xp": 25},
		"targets": [
			{"type": "brew_total", "label": "Сварить зелий (за всё время)", "need": 6},
		],
	},
	"q_wealth": {
		"title": "Богач леса",
		"desc": "Гриим говорит: настоящие деньги — те, что лежат в руке. Держи 250 золотых на руках.",
		"when": "wealth_watch",
		"permanent_done": "meta.q_wealth_done",
		"targets": [
			{"type": "hold_gold", "label": "Держать золота на руках", "need": 250},
		],
	},
	"q_ashen": {
		"title": "Пепелище",
		"desc": "Проследи, что стало с землёй к востоку за деревней.",
		"when": "amulet_returned",
		"reward": {"xp": 25},
		"targets": [
			{"type": "visit_ashen", "label": "Побывать на Пепелище", "need": 1},
		],
	},
}

static func ids() -> Array:
	return QUESTS.keys()

## Справочник квеста (константный словарь — не мутировать!). {} если id нет.
static func quest_def(id: String) -> Dictionary:
	return QUESTS.get(id, {})

static func is_story(id: String) -> bool:
	return bool(quest_def(id).get("story", false))

## --- маркеры над головами NPC (задача «Квесты: однократность + маркеры») ---
const MARKER_NONE := 0    # маркера нет
const MARKER_TAKE := 1    # «!» — квест можно взять
const MARKER_READY := 2   # «?» — можно сдать (приоритетнее «!»)

## Маркер NPC по id — дословное отражение гейтов выдачи/сдачи world.gd::talk():
## elder: 0 => взять, 1 + herbs>=3 => сдать; merchant: 0 => взять,
## 1 + slime_kills_circle>=3 => сдать. Однократность «Трав» обеспечивает сам
## elder_quest: после meta.q_elder_done круг стартует с 2 (_wipe_circle) —
## стадии 0 (а значит, и «!») больше не будет. Кузнец квестов не даёт;
## Геральд — внутренний класс dungeon_zone.gd (не npc.gd), здесь не описан.
static func marker_state(gs, npc_id: String) -> int:
	match npc_id:
		"elder":
			if int(gs.elder_quest) == 1 and int(gs.herbs) >= 3:
				return MARKER_READY
			if int(gs.elder_quest) == 0:
				return MARKER_TAKE
		"merchant":
			if int(gs.slime_quest) == 1 and int(gs.slime_kills_circle) >= 3:
				return MARKER_READY
			if int(gs.slime_quest) == 0:
				return MARKER_TAKE
	return MARKER_NONE

## Статус квеста: сюжетные — из полей-канона GameState, побочки — из флага "q.<id>".
static func status(gs, id: String) -> int:
	match id:
		"elder":
			return STATUS_DONE if int(gs.elder_quest) >= 2 else STATUS_ACTIVE
		"slime":
			var sq := clampi(int(gs.slime_quest), 0, 2)
			return sq
		"cave":
			return STATUS_DONE if int(gs.cave_state) >= 4 else STATUS_ACTIVE
		"witch":
			# story-цель NG-лупа: флаг смерти пишет mob_boss2.gd, вайп ashen.*
			# в start_ng_plus пере-взводит цель каждый круг
			return STATUS_DONE if str(gs.flags.get("ashen.boss", "")) == "dead" else STATUS_ACTIVE
	return int(gs.get_flag(FLAG_PREFIX + id, 0))

## Показывать ли квест в журнале: побочки — только начатые; «Гром» и «Травы»
## видны с нуля (как в HUD-строке «Задания»), слаймы — после разговора с торговцем.
static func visible_in_journal(gs, id: String) -> bool:
	match id:
		"elder":
			return true
		"slime":
			return int(gs.slime_quest) >= 1
		"cave":
			return true
		"witch":
			# не спойлерим зону до первого взгляда на Пепелище (world.gd::enter_ashen
			# ставит флаг вместе с FirstHint); смерть ведьмы тоже делает цель видимой
			return str(gs.flags.get("ashen.intro_seen", "")) != "" \
				or str(gs.flags.get("ashen.boss", "")) == "dead"
	return int(gs.get_flag(FLAG_PREFIX + id, 0)) != STATUS_NONE

## Прогресс одной цели (0..+; витрина клампит к need). param — mat для collect_mat.
static func progress(gs, type: String, param: String = "") -> int:
	match type:
		"talk_elder":
			return 1 if int(gs.elder_quest) >= 1 else 0
		"collect_herb":
			return int(gs.herbs)
		"deliver_elder":
			return 1 if int(gs.elder_quest) >= 2 else 0
		"kill_slime":
			# цель квеста — работа ТЕКУЩЕГО круга: total-счётчик переживает NG+
			# (на его охотничьи ачивки), сюжет же нельзя сдать «вчерашними» трупами
			return int(gs.slime_kills_circle)
		"deliver_slime":
			return 1 if int(gs.slime_quest) >= 2 else 0
		"visit_cave":
			return 1 if (bool(gs.seen_cave_intro) or bool(gs.in_cave)) else 0
		"accept_hermit":
			return 1 if int(gs.cave_state) >= 1 else 0
		"defeat_boss":
			return 1 if bool(gs.boss_defeated) else 0
		"get_key":
			return 1 if int(gs.cave_state) >= 3 else 0
		"open_door":
			return 1 if bool(gs.door_opened) else 0
		"take_amulet":
			# амулет переносится между кругами; в новом круге этап честен только
			# у алтаря (cave_state>=3: дверь открыта, сундук в этой истории пройден);
			# на wave 0 (первый круг, включая сейвы до правки) амулет = взят из сундука
			return 1 if bool(gs.has_amulet) \
				and (int(gs.ng_wave()) == 0 or int(gs.cave_state) >= 3) else 0
		"return_amulet":
			return 1 if int(gs.cave_state) >= 4 else 0
		"kill_witch":
			return 1 if str(gs.flags.get("ashen.boss", "")) == "dead" else 0
		"brew_total":
			# вечный счётчик варок (achv.gd::count("brews")); badge-квест закрыт
			# навсегда meta-меткой — вайп q.* в NG+ его не ре-взводит
			return int(gs.get_flag("ach.n.brews", 0))
		"hold_gold":
			return int(gs.gold)
		"visit_ashen":
			# тот же флаг/событие, что у FirstHint "ashen" (world.gd::enter_ashen).
			# t19: str(), а не String(...) — конструктор String() падает на значениях
			# не-строкового типа («Nonexistent 'String' constructor», мягкий спам в qa_ng);
			# str() принимает любой Variant. Вся строка флагов в файле переведена на str().
			return 1 if str(gs.flags.get("ashen.intro_seen", "")) != "" else 0
		"collect_mat":
			return int(gs.get_flag(GOT_PREFIX + param, 0))
		"rest_campfire":
			var cf: Variant = gs.campfires_used
			return cf.size() if typeof(cf) == TYPE_DICTIONARY else 0
	push_warning("QuestsData: неизвестный тип цели: %s" % type)
	return 0

## Все цели выполнены? (для side-квестов — сигнал завершения в refresh()).
static func is_complete(gs, id: String) -> bool:
	var targets: Array = quest_def(id).get("targets", [])
	if targets.is_empty():
		return false
	for d in targets:
		var td: Dictionary = d
		if progress(gs, String(td.get("type", "")), String(td.get("mat", ""))) < int(td.get("need", 1)):
			return false
	return true

## Готовые данные для журнала: массив
## {id, title, desc, status, story, targets:[{label, cur, need, done}]}
## только для видимых квестов, в порядке реестра.
static func entries(gs) -> Array:
	var out: Array = []
	for raw_id in QUESTS:
		var id := String(raw_id)
		if not visible_in_journal(gs, id):
			continue
		var def: Dictionary = QUESTS[id]
		var st := status(gs, id)
		var targets: Array = []
		for raw_t in def.get("targets", []):
			var td: Dictionary = raw_t
			var need := maxi(1, int(td.get("need", 1)))
			var p := mini(need, progress(gs, String(td.get("type", "")), String(td.get("mat", ""))))
			# выполненный квест показывает все цели закрытыми: счётчики-
			# расходники (травы) после сдачи обнулены каноном — не пугать игрока
			var done := p >= need or st == STATUS_DONE
			targets.append({"label": String(td.get("label", "")), "cur": need if done else p, "need": need, "done": done})
		out.append({
			"id": id,
			"title": String(def.get("title", id)),
			"desc": String(def.get("desc", "")),
			"status": st,
			"story": is_story(id),
			"targets": targets,
		})
	# t18 (25.11, DESIGN_DEPTH_V2 §3): цепочка поясов — те же строки журнала
	# тем же языком; в журнал попадают только взятые/сданные звенья.
	for i in BELT_CHAIN.size():
		var st := belt_status(gs, i)
		if st == STATUS_NONE:
			continue
		var def: Dictionary = BELT_CHAIN[i]
		var need := maxi(1, int(def.get("need", 1)))
		var p := mini(need, belt_progress(gs, i))
		var done := p >= need or st == STATUS_DONE
		out.append({
			"id": String(def.get("id", "bq_%d" % i)),
			"title": String(def.get("title", "")),
			"desc": String(def.get("desc", "")),
			"status": st,
			"story": false,
			"targets": [{"label": String(def.get("label", "")),
					"cur": need if done else p, "need": need, "done": done}],
		})
	# t36 I3 (26.11, волна «Интерес v1»): охота дня — той же формой строки в тот
	# же список; journal.gd НЕ тронут (g12-пин), цепочку слияние не касается.
	for raw_b in BTY.journal_entries(gs):
		out.append(raw_b)
	# t37 I4 (26.11): публичный счётчик pity — «радость ожидания» работает только
	# когда прогресс ВИДЕН. Строка появляется с первым кредитом и гаснет после
	# выдачи (счётчик обнулён — копить заново). Формулировка — существительное
	# мира, без обещаний помимо механики.
	var pity := int(gs.elite_pity)
	if pity > 0:
		out.append({
			"id": "pity",
			"title": "Реликтовая милость",
			"desc": "Элиты, охоты и зачистки точат жребий. Когда чаша полна, следующая редкая награда падает реликтом — и чаша пустеет.",
			"status": STATUS_ACTIVE,
			"story": false,
			"targets": [{"label": "До реликта",
					"cur": mini(pity, int(gs.PITY_THRESHOLD)),
					"need": int(gs.PITY_THRESHOLD),
					"done": pity >= int(gs.PITY_THRESHOLD)}],
		})
	# t38 I5 (27.11, вердикт пользователя «число смертей видно — игрок видит свои
	# ставки»): строка ставок смерти. Вечный счётчик ach.n.deaths (веха игрока) в
	# заголовке, ставка текущего круга — шкала благословения волхвы (кап 10).
	# Строка живёт, только пока ставки nonzero: без смертей пугалло в журнале лишний.
	var deaths_all := int(gs._num(gs.flags.get("ach.n.deaths", 0), 0))
	if deaths_all > 0:
		var vd := int(gs._num(gs.flags.get("meta.vd", 0), 0))
		var cap := int(gs.BLESS_CAP_DEATHS)
		out.append({
			"id": "death_price",
			"title": "Ставки пепла · смертей: %d" % deaths_all,
			"desc": "Тьма берёт пятую часть серебра — и только: сумка, снасть и опыт неприкосновенны. Каждая смерть круга — благословение волхвы +2% урона, до десяти.",
			"status": STATUS_ACTIVE,
			"story": false,
			"targets": [{"label": "Смертей круга",
					"cur": mini(vd, cap), "need": cap, "done": vd >= cap}],
		})
	return out

## Тик системы (вызывает journal.gd): счётчики материалов + автостарты +
## автозавершение побочных квестов (+ их награды из реестра и permanent_done).
## Пишет флаги "q.*" и объявленные в реестре permanent-метки; выдаёт add_xp
## наград; уведомления — toast; автосейв — quest_changed. Сюжетные квесты
## не трогает никогда.
static func refresh(gs) -> void:
	_track_material(gs, "suhotsvet")
	for raw_id in QUESTS:
		var id := String(raw_id)
		if is_story(id):
			continue
		var def: Dictionary = QUESTS[id]
		match status(gs, id):
			STATUS_NONE:
				if _cond_met(gs, String(def.get("when", ""))):
					gs.set_flag(FLAG_PREFIX + id, STATUS_ACTIVE)
					gs.toast.emit("Новый квест: %s (J — журнал)" % String(def.get("title", id)))
					gs.quest_changed.emit()
			STATUS_ACTIVE:
				if is_complete(gs, id):
					gs.set_flag(FLAG_PREFIX + id, STATUS_DONE)
					# badge-квесты: метка, переживающая вайп "q.*" (иначе в NG+
					# старт+финиш за тик на вечном счётчике — тот же H2)
					var perm := String(def.get("permanent_done", ""))
					if perm != "":
						gs.set_flag(perm, 1)
					# награды реестра — однократно: флаг DONE уже выше, повтор
					# в этот круг недостижим (идемпотентность статуса)
					var rew: Dictionary = def.get("reward", {})
					var xp := int(rew.get("xp", 0))
					if xp > 0:
						gs.add_xp(xp)
					GameAudio.sfx("book")  # закрытие side-квеста: шелест журнала (аудио-аудит)
					gs.toast.emit("Квест выполнен: %s!%s"
						% [String(def.get("title", id)), " (+%d опыта)" % xp if xp > 0 else ""])
					gs.quest_changed.emit()
			_:
				pass

## Вечная метка однократности сюжетных «Трав» (задача «Квесты: однократность
## + маркеры»). Сдача (elder_quest>=2) ставит meta.q_elder_done: meta.* —
## вечный слой, переживает вайп q.* и сюжетных полей (_wipe_circle), поэтому
## в новом круге/после смерти world.talk("elder") не увидит стадию 0 — ни
## повторной выдачи, ни повторной награды. Идемпотентна; true — только
## первая постановка (вызывающему зафиксировать автосейвом). refresh()
## сюжетные квесты не трогает никогда, поэтому метку зовёт npc.gd синхронно
## на quest_changed: world.gd в колбэке сдачи пишет elder_quest=2 и сразу
## эмитит quest_changed — гонки со смертью/вайпом не остаётся.
static func sync_story_permanence(gs) -> bool:
	if int(gs.elder_quest) >= 2 and int(gs.get_flag("meta.q_elder_done", 0)) == 0:
		gs.set_flag("meta.q_elder_done", 1)
		return true
	return false

## Кумулятивный учёт собранного материала: сколько прибавилось в рюкзаке с
## прошлого тика — то «собрано» (варка/трата не откатывает прогресс цели).
static func _track_material(gs, mid: String) -> void:
	var last := int(gs.get_flag(LAST_PREFIX + mid, 0))
	var cur := int(gs.mat_count(mid))
	if cur > last:
		gs.set_flag(GOT_PREFIX + mid, int(gs.get_flag(GOT_PREFIX + mid, 0)) + (cur - last))
	if cur != last:
		gs.set_flag(LAST_PREFIX + mid, cur)

## Коды условий автостарта побочных квестов (поле "when" в QUESTS).
static func _cond_met(gs, when: String) -> bool:
	match when:
		"has_suhotsvet":
			return int(gs.mat_count("suhotsvet")) > 0
		"first_campfire":
			var cf: Variant = gs.campfires_used
			return typeof(cf) == TYPE_DICTIONARY and cf.size() > 0
		"slime_quest_done":
			return int(gs.slime_quest) >= 2
		"brewer_watch":
			# badge: вечный счётчик ach.n.brews + meta-метка «не ре-фаршить в NG+»
			return int(gs.get_flag("ach.n.brews", 0)) >= 1 \
				and int(gs.get_flag("meta.q_brewer_done", 0)) == 0
		"wealth_watch":
			# badge-квест: meta-метка переживает вайп q.* — после NG+ не ре-фаршится
			return int(gs.gold) >= 150 and int(gs.get_flag("meta.q_wealth_done", 0)) == 0
		"amulet_returned":
			# путь на Пепелище открывается историей амулета (конец «Грома»);
			# цель-вход живёт на вечном флаге ashen.intro_seen (вайп ashen.* в
			# start_ng_plus пере-взводит указатель каждый круг — и это честно:
			# в новом круге игрок обязан вернуться на Пепелище за Ведьмой)
			return int(gs.cave_state) >= 4
	return false

# --- t18 «Глубина v2 §3: Квесты поясов» (25.11, docs/DESIGN_DEPTH_V2.md) ----
# Один квестовый поток через доску объявлений: заказчик — старейшина, звенья
# открываются ПО МЕРЕ ОТКРЫТИЯ поясов (канон-флаг wm.open.<зона> ставит
# world.enter_location), цели живут в биомах, сдача — у доски. Прогресс —
# функция от GameState (счётчики "q.bk.<зона>"/"q.bc.<зона>"), статусы —
# "q.bq.<звень>", всё вайпится с "q.*" каждый круг (цепочка — нажитое забега,
# как побочки; награда — ровно один раз на круг, флаги 1/2). Цели v1 —
# «зачистить N» и «найти сундук»; «закрыть ход» придёт вместе с ходами
# микро-подземелий (t19) — реестр готов принять новый тип без правок остального.
# ЗВЕНЬЯ НЕ В РЕЕСТРЕ QUESTS: их не трогает автостарт/автозавершение refresh()
# — взятие и сдача только через доску (interactable kind "board").

const BQ_PREFIX := "q.bq."   # статус звена цепочки: 1 взято, 2 сдано (нет = 0)
const BK_PREFIX := "q.bk."   # убийства мобов Зоны (счётчик цели «зачистить»)
const BC_PREFIX := "q.bc."   # сундук Зоны найден/открыт (1)
const BM_PREFIX := "q.bm."   # t19: ход пояса «закрыт» — мини-босс убит (1)

## Вилка золота звена — BALANCE.md §«Цепочка поясов» (30+10·пояс; финал
## пояса с реликтом — +15). Реликт — guaranteed (Loot.quest_relic, force_relic
## канона t17). Пул — существующие вещи яруса пояса; «уже в сумке» и матрица
## can_equip отсекаются в Loot.quest_relic (награда никогда не «не в руку»),
## когда у класса весь пул куплен — честное реликтовое серебро (+40 зол.).
const BELT_CHAIN := [
	{"id": "bq_snow_1", "zone": "snow", "type": "biome_kill", "need": 4,
		"title": "Снежный долг", "label": "Зачистить сущностей в Снежнике",
		"desc": "Старейшина: «Снежник открыт — и ветер оттуда несёт не только снег. Разберись с первыми тенями, тогда поговорим дальше.»",
		"gold": 30},
	{"id": "bq_snow_2", "zone": "snow", "type": "biome_chest", "need": 1,
		"title": "Клад под снегом", "label": "Найти и открыть сундук Снежника",
		"desc": "Старейшина: «Передать надо то, что было до нас. В Снежнике под сугробом ждёт сундук первых — найди его.»",
		"gold": 45, "relic": true,
		"relic_pool": ["leather", "chain", "shortsword", "staff_apprentice", "bow_hunter"]},
	{"id": "bq_desert_1", "zone": "desert", "type": "biome_kill", "need": 5,
		"title": "Пепельный урок", "label": "Зачистить сущностей в Пустоши",
		"desc": "Старейшина: «Пустошь помнит пожар. То, что ползает в пепле, помнит его хуже — научи их тишине.»",
		"gold": 40},
	{"id": "bq_desert_2", "zone": "desert", "type": "biome_chest", "need": 1,
		"title": "Закопанное солнце", "label": "Найти и открыть сундук Пустоши",
		"desc": "Старейшина: «В Пустоши, где тень короче всего, зарыто то, что прятали от огня.»",
		"gold": 55, "relic": true,
		"relic_pool": ["leather", "chain", "boarhide", "sword", "nordsword", "staff_oak", "bow_heavy", "shield_iron"]},
	{"id": "bq_steppe_1", "zone": "steppe", "type": "biome_kill", "need": 6,
		"title": "Степной простор", "label": "Зачистить сущностей в Степи",
		"desc": "Старейшина: «Степь широка и потому дерзка. Пройди её — так, чтобы кочевники запомнили шаг.»",
		"gold": 50},
	{"id": "bq_steppe_2", "zone": "steppe", "type": "biome_chest", "need": 1,
		"title": "Курган", "label": "Найти и открыть сундук Степи",
		"desc": "Старейшина: «В кургане Степи лежит то, что кочевники забрали у леса. Пусть вернётся в оборот.»",
		"gold": 65, "relic": true,
		"relic_pool": ["leather", "chain", "boarhide", "sword", "nordsword", "staff_oak", "bow_heavy", "shield_iron"]},
	{"id": "bq_forest_1", "zone": "forest", "type": "biome_kill", "need": 7,
		"title": "Закон Чащи", "label": "Зачистить сущностей в Чаще",
		"desc": "Старейшина: «Чаща — наша соседка и наша кормилица. То, что гложет её изнутри, должно уйти.»",
		"gold": 60},
	{"id": "bq_forest_2", "zone": "forest", "type": "biome_chest", "need": 1,
		"title": "Сердце Чащи", "label": "Найти и открыть сундук Чащи",
		"desc": "Старейшина: «В чаще есть поляна, которую лес обходит. Что там оставлено — забери, лес не обидится.»",
		"gold": 75, "relic": true,
		"relic_pool": ["chain", "boarhide", "nordsword", "fangblade", "rune_blade", "staff_oak", "staff_rune", "bow_heavy", "shield_raven"]},
	{"id": "bq_castle_1", "zone": "castle", "type": "biome_kill", "need": 8,
		"title": "Каменный зуб", "label": "Зачистить сущностей у Замка",
		"desc": "Старейшина: «Замок сломан, а зуб его всё ещё кусается. Выбей этот зуб.»",
		"gold": 70},
	{"id": "bq_castle_2", "zone": "castle", "type": "biome_chest", "need": 1,
		"title": "Зал с сокровищем", "label": "Найти и открыть сундук Замка",
		"desc": "Старейшина: «В Замке есть зал, который не грабили — боялись. Испугайся ты, забери и принеси.»",
		"gold": 85, "relic": true,
		"relic_pool": ["chain", "boarhide", "nordsword", "fangblade", "rune_blade", "staff_oak", "staff_rune", "bow_heavy", "shield_raven"]},
	{"id": "bq_dungeon_1", "zone": "dungeon", "type": "biome_kill", "need": 9,
		"title": "Тьма под землёй", "label": "Зачистить сущностей в Подземелье",
		"desc": "Старейшина: «Подземелье — последний пояс и последняя наша забота. Свети мечом там, где не светит солнце.»",
		"gold": 80},
	{"id": "bq_dungeon_2", "zone": "dungeon", "type": "biome_chest", "need": 1,
		"title": "Последняя комната", "label": "Найти и открыть сундук Подземелья",
		"desc": "Старейшина: «В последней комнате Подземелья оставлено то, что не сумели унести прежние. Цепочка замкнётся — и деревня будет должна тебе до конца зимы.»",
		"gold": 95, "relic": true,
		"relic_pool": ["chain", "boarhide", "nordsword", "fangblade", "rune_blade", "staff_oak", "staff_rune", "bow_heavy", "shield_raven"]},
]

static func belt_link(i: int) -> Dictionary:
	return BELT_CHAIN[i] if i >= 0 and i < BELT_CHAIN.size() else {}

static func belt_status(gs, i: int) -> int:
	var lid := String(belt_link(i).get("id", ""))
	return int(gs.get_flag(BQ_PREFIX + lid, 0)) if lid != "" else STATUS_NONE

## Первое несданное звено; == BELT_CHAIN.size() — цепочка закрыта.
static func belt_current(gs) -> int:
	for i in BELT_CHAIN.size():
		if belt_status(gs, i) != STATUS_DONE:
			return i
	return BELT_CHAIN.size()

## Взять можно первое несданное звено, только если пояс открыт (wm.open —
## канон «Тумана открытия» t7: игрок ногами дошёл до локации).
static func belt_can_offer(gs, i: int) -> bool:
	if i != belt_current(gs) or belt_status(gs, i) != STATUS_NONE:
		return false
	return str(gs.get_flag("wm.open." + String(belt_link(i).get("zone", "")), "")) == "1"

## Прогресс цели звена (0..+; витрина клампит к need).
static func belt_progress(gs, i: int) -> int:
	var def := belt_link(i)
	match String(def.get("type", "")):
		"biome_kill":
			return int(gs.get_flag(BK_PREFIX + String(def.get("zone", "")), 0))
		"biome_chest":
			return int(gs.get_flag(BC_PREFIX + String(def.get("zone", "")), 0))
		"mini_clear":
			# t19 (25.11): «закрыть ход» = мини-босс микро-подземелья убит
			# (хук MiniBossWatch -> q.bm.<биом>). Звенья цепочки с этой целью
			# добавит t20 — ветка готова заранее, BELT_SIGS qa_q5 не трогает.
			return int(gs.get_flag(BM_PREFIX + String(def.get("zone", "")), 0))
	return 0

static func belt_ready(gs, i: int) -> bool:
	return belt_status(gs, i) == STATUS_ACTIVE \
			and belt_progress(gs, i) >= int(belt_link(i).get("need", 1))

## Честная строка прогресса для подсказки/тоста: «2/4» или «0/1».
static func belt_progress_line(gs, i: int) -> String:
	var def := belt_link(i)
	return "%d/%d" % [mini(int(def.get("need", 1)), belt_progress(gs, i)), int(def.get("need", 1))]

## Имя зоны звена для тостов. ЗЕРКАЛО OpenWorld.ZONE_NAMES (QuestsData не
## предлоадит open_world — тот же приём, что у OW_ZONES; стенд сверяет).
const ZONE_TITLES := {"snow": "Снежник", "desert": "Пустошь", "steppe": "Степь",
		"forest": "Чаща", "castle": "Замок", "dungeon": "Подземелье"}

static func belt_zone_name(gs, i: int) -> String:
	var z := String(belt_link(i).get("zone", ""))
	return String(ZONE_TITLES.get(z, z))

## Взять звено у доски. Идемпотентен: только NONE -> ACTIVE и только current.
static func belt_offer(gs, i: int) -> void:
	if not belt_can_offer(gs, i):
		return
	gs.set_flag(BQ_PREFIX + String(belt_link(i).get("id", "")), STATUS_ACTIVE)
	gs.toast.emit("Доска: взято «%s»." % String(belt_link(i).get("title", "")))
	gs.quest_changed.emit()  # автосейв: звено взято

## Сдача звена у доски: флаг 2 ДО выдачи (идемпотентность награды — канон
## refresh()), золото вилки, на финале пояса — гарантированный реликт t17.
static func belt_turnin(gs, i: int) -> void:
	if belt_status(gs, i) != STATUS_ACTIVE or not belt_ready(gs, i):
		return
	var def := belt_link(i)
	gs.set_flag(BQ_PREFIX + String(def.get("id", "")), STATUS_DONE)
	var gold := int(def.get("gold", 0))
	if gold > 0:
		gs.add_gold(gold)
	gs.toast.emit("Сдано: «%s». +%d зол." % [String(def.get("title", "")), gold])
	if bool(def.get("relic", false)):
		Loot.quest_relic(gs, String(def.get("id", "")),
				def.get("relic_pool", []) as Array)
	GameAudio.sfx("coin")
	gs.quest_changed.emit()  # автосейв: награда выдана ровно один раз

# --- счётчики целей (хуки loot.gd::on_mob_death и biome_zone BiomeChest) ----

## Убийство внутри локации ("loc_<зона>") — поясная цель цепочки. Вне локаций
## (лес/деревня/пещера/Пепелище) — тишина: счётчики цепочки живут только
## поясами, ни одна прежняя ветка (ачивки, rs.k.*, трофеи) не тронута.
static func note_belt_kill_area(gs, active_area: String) -> void:
	if not active_area.begins_with("loc_"):
		return
	var z := active_area.substr(4)
	if not OW_ZONES.has(z):
		return
	gs.set_flag(BK_PREFIX + z, int(gs.get_flag(BK_PREFIX + z, 0)) + 1)
	# БЕЗ quest_changed: счётчик читается доской/журналом свежим в момент
	# просмотра, автосейв на каждое убийство раздувал бы диск; переходы
	# (взятие/сдача) сейвят сами.

## Сундук локации открыт — цель «найти сундук» закрыта (хукает BiomeChest).
static func note_belt_chest(gs, zone: String) -> void:
	if OW_ZONES.has(zone):
		gs.set_flag(BC_PREFIX + zone, 1)

## t19 (25.11): «закрыть ход» — мини-босс микро-подземелья убит (хук
## MiniBossWatch в mini_zone.gd). Флаг-факт, как счётчики выше: без
## quest_changed на смерть (доска/журнал читуют свежим; переходы сейвят сами).
## t37 I4 (26.11): зачистка микро-подземелья — третий источник pity-кредита
## (+1; элита +1 в loot.gd, охота +2 в bounties.gd). Флаг-гейт однократный —
## кредит начисляется ровно раз на биом за круг (повторный удар по флагу
## молчит, как и сам факт).
static func note_belt_mini(gs, zone: String) -> void:
	if OW_ZONES.has(zone):
		if int(gs.get_flag(BM_PREFIX + zone, 0)) == 0:
			gs.elite_pity = int(gs.elite_pity) + 1
		gs.set_flag(BM_PREFIX + zone, 1)

## Членство в реестре зон (свой const — QuestsData не предлоадит open_world,
## порядок букв совпадает с OpenWorld.ZONES; расхождение поймает стенд).
const OW_ZONES := ["snow", "desert", "steppe", "forest", "castle", "dungeon"]
