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
	"q_suhotsvet": {
		"title": "Сухоцвет впрок",
		"desc": "Сухоцвет — трофей со слаймов, основа зелий. Собери пять штук: считается накопленное, варить можно.",
		"when": "has_suhotsvet",
		"targets": [
			{"type": "collect_mat", "mat": "suhotsvet", "label": "Собрать сухоцвет", "need": 5},
		],
	},
	"q_campfires": {
		"title": "Привал у трёх костров",
		"desc": "Старая примета: кто отдохнул у каждого костра Северного Леса — тому лес больше не враг.",
		"when": "first_campfire",
		"targets": [
			{"type": "rest_campfire", "label": "Отдохнуть у костров леса", "need": 3},
		],
	},
	"q_slimehunt": {
		"title": "Зачистка леса",
		"desc": "Торговец просит не останавливаться на трёх: вычисти лес так, чтобы слаймов стало вполовину меньше.",
		"when": "slime_quest_done",
		"targets": [
			{"type": "kill_slime", "label": "Уничтожить слаймов (всего)", "need": 8},
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
			return int(gs.slime_kills)
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
			return 1 if (bool(gs.has_amulet) or int(gs.cave_state) >= 4) else 0
		"return_amulet":
			return 1 if int(gs.cave_state) >= 4 else 0
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
## автозавершение побочных квестов. Пишет ТОЛЬКО флаги "q.*"; уведомления —
## toast; автосейв — quest_changed. Сюжетные квесты не трогает никогда.
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
					GameAudio.sfx("book")  # закрытие side-квеста: шелест журнала (аудио-аудит)
					gs.toast.emit("Квест выполнен: %s!" % String(def.get("title", id)))
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
	return false
