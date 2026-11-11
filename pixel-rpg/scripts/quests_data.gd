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
const GOT_PREFIX := "q.got."     # накоплено материала: "q.got." + material id
const LAST_PREFIX := "q.last."   # последнее виденное кол-во: "q.last." + id

const STATUS_NONE := 0     # не начат (для побочек — не виден в журнале)
const STATUS_ACTIVE := 1   # активен
const STATUS_DONE := 2     # выполнен

## Реестр. Порядок словаря = порядок показа в журнале (сюжетные первыми).
## Цели: {"type", "label", "need", ["mat"]} — прогресс считает progress() по type.
## Поле "when" (только побочки) — код условия автостарта в _cond_met().
## Поле "reward": {"xp": N} (побочки) — выдаётся однократно при автозавершении
## (флаг DONE ставится до выдачи — повтор исключён идемпотентностью статуса).
## Поле "permanent_done": "<flag>" — доп. метка завершения, переживающая вайп
## "q.*" при смене круга (мгновенный ре-фарш badge-квестов в NG+ исключён).
const QUESTS := {
	"elder": {
		"title": "Травы для старейшины",
		"desc": "Старейшина Морга просит собрать лесные травы — в деревни беда с хворью.",
		"story": true,
		"targets": [
			{"type": "talk_elder", "label": "Поговорить со старейшиной", "need": 1},
			{"type": "collect_herb", "label": "Собрать травы у кустов", "need": 3},
			{"type": "deliver_elder", "label": "Отнести травы старейшине", "need": 1},
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
			return STATUS_DONE if String(gs.flags.get("ashen.boss", "")) == "dead" else STATUS_ACTIVE
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
			return String(gs.flags.get("ashen.intro_seen", "")) != "" \
				or String(gs.flags.get("ashen.boss", "")) == "dead"
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
			return 1 if String(gs.flags.get("ashen.boss", "")) == "dead" else 0
		"brew_total":
			# вечный счётчик варок (achv.gd::count("brews")); badge-квест закрыт
			# навсегда meta-меткой — вайп q.* в NG+ его не ре-взводит
			return int(gs.get_flag("ach.n.brews", 0))
		"hold_gold":
			return int(gs.gold)
		"visit_ashen":
			# тот же флаг/событие, что у FirstHint "ashen" (world.gd::enter_ashen)
			return 1 if String(gs.flags.get("ashen.intro_seen", "")) != "" else 0
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
