extends RefCounted
## I3 «Доска охот» (t36, 26.11, волна «Интерес v1»; вердикт: «причина вернуться»
## — доска объявлений начинает предлагать ОХОТЫ). Параллельный «жир» рядом с
## belt-цепью — тот же канал (доска kind "board", флаги q.*, журнал через
## QuestsData.entries), НИ ОДНОГО звена BELT_CHAIN не тронут.
## День рождает ровно одну охоту: зона из ОТКРЫТЫХ поясов (канон wm.open —
## «куда ногами дошёл», как belt_can_offer), вид из BESTIARY, клетка из
## проходимых клеток loc_map, ИМЯ из кодо-слогов 20×20 («Гнилозуб»-стиль).
## Всё — чистая функция (run_seed, день) на FNV-1a32 каноне: двое суток/два
## сида дают побитово те же охоты (qa_bt S1). День берётся из часов I2
## (GameState.day_t) — «доска висит в мире, где есть ночь».
## Цель — именованная элита: комплект I1 (hp x2 / урон x1.5 / серебро x3 /
## pity) плюс СВОЁ имя на плашке и СВОЙ цвет ауры (Elites.apply_named),
## маркер «†» код-графикой над порталом зоны на карте мира — «в радиусе» =
## клетка открыта туманом (t7 канон, новой системы близости не заводим).
## Награда: крупное серебро (40+25×пояс, BALANCE I3) + 2 pity-кредита реликта
## (хук I4) — сверх лута элиты; выдача по канону «флаг 2 ДО выдачи»
## (belt_turnin/refresh) — идемпотентна к повторной смерти/крашу.
## Срок МЯГКИЙ: не таймер в лицах, а «до рассвета» — при смене дня охота
## просто сгорает (cull), без штрафа; перевзятие бесплатное, 1 активная.
## Состояние — флаги q.bty.day / q.bty.state (0 нет, 1 взята, 2 закрыта):
## сейвятся вместе с flags и сгорают с кругом (q.* вайп) — охота нажитое
## забега, как цепочка. Моб-цель в сейв не пишется: ensure() пересаживает её
## детерминированно при входе в зону (той же клеткой из чистой функции).

const OW := preload("res://scripts/open_world.gd")    # shash/BESTIARY/loc_map/zone_belt
const ENR := preload("res://scripts/enroute.gd")      # часы дня (I2) — общий календарь

const DAY_FLAG := "q.bty.day"     # день рождения текущего объявления
const ST_FLAG := "q.bty.state"    # 0 нет / 1 взята / 2 закрыта (флаг 2 до выдачи)
const ST_NONE := 0
const ST_ACTIVE := 1
const ST_DONE := 2
const AURA := Color(0.86, 0.22, 0.30)   # багровая аура именной цели (код-палитра)
const MARK := "†"                        # глиф маркера (рисуется кодом, не шрифтом)

## Награда: 40 + 25×пояс (b1..b6 = 65..190) — «крупное серебро» против
## рядового звена цепочки (30+10×пояс). Пин BALANCE.md §I3.
static func bounty_gold(belt: int) -> int:
	return 40 + 25 * belt

## Кодо-слоги: 20 корней + 20 основ = 400 имён («Гнило»+«зуб»). Гласная на
## стыке опечатана корнями на согласную — как в живой кличке, не по таблице.
const SYL_A := ["Гнило", "Криво", "Кроваво", "Пепло", "Тлею", "Черно", "Ледяно",
	"Пыле", "Мгло", "Косте", "Железно", "Ядо", "Серо", "Глухо", "Зло", "Хрипо",
	"Шерсто", "Грязе", "Осколо", "Голово"]
const SYL_B := ["зуб", "клык", "шкур", "хвост", "череп", "брюхо", "лап", "рог",
	"глаз", "пасть", "коготь", "шип", "хребет", "жил", "прах", "тлен", "дым",
	"смрад", "вой", "скрежет"]

## Чистая функция дня: {} если охотиться негде (ни один пояс не открыт),
## иначе {day, zone, fam, tile, name, belt, gold}. Никаких записей не делает.
## Мемо (t36, правка R8.1): ключ (seed, день, вектор открытых поясов) — все
## три входа offer'а; loc_map-скан клетки — не дешёвая операция, а callers
## (маркер на туман-событие, хинт доски, статус) зовут часто. Чистая функция
## мемоизирована корректно: другой ключ = другой результат, круг-вайп меняет
## вектор/день сам; страж размера — от неограниченного роста в долгую сессию.
static var _offer_memo := {}

static func offer(gs) -> Dictionary:
	var day := ENR.day_index()
	var sig := ""
	for z in OW.ZONES:
		sig += "1" if str(gs.get_flag("wm.open." + String(z), "")) == "1" else "0"
	var key := "%d:%d:%s" % [int(gs.run_seed), day, sig]
	var memo: Variant = _offer_memo.get(key)
	if memo != null:
		return memo
	var o := _offer_compute(gs, day, sig)
	if _offer_memo.size() >= 64:
		_offer_memo.clear()
	_offer_memo[key] = o
	return o

static func _offer_compute(gs, day: int, _sig: String) -> Dictionary:
	var zones: Array = []
	for z in OW.ZONES:
		if str(gs.get_flag("wm.open." + String(z), "")) == "1":
			zones.append(String(z))
	if zones.is_empty():
		return {}
	var seed := int(gs.run_seed)
	var zone := String(zones[OW.shash("btyz:%d:%d" % [seed, day]) % zones.size()])
	var fams: Array = OW.BESTIARY.get(zone, [])
	if fams.is_empty():
		return {}
	var fam := String((fams[OW.shash("btyf:%d:%d:%s" % [seed, day, zone]) % fams.size()] as Array)[0])
	var lm: Dictionary = OW.loc_map(seed, zone)
	var grid: Array = lm.get("grid", [])
	var meta: Dictionary = lm.get("meta", {})
	var spawn: Vector2i = Vector2i(int((meta.get("spawn", [21, 6]) as Array)[0]),
			int((meta.get("spawn", [21, 6]) as Array)[1]))
	var cands: Array = []
	for y in grid.size():
		var row := String(grid[y])
		for x in row.length():
			if not OW.walkable(grid, x, y):
				continue
			if OW.cheb(Vector2i(x, y), spawn) < 8:   # у арки не стоим — цель не «на входе»
				continue
			cands.append(Vector2i(x, y))
	if cands.is_empty():
		return {}
	var tile: Vector2i = cands[OW.shash("btyc:%d:%d:%s" % [seed, day, zone]) % cands.size()]
	var name := String(SYL_A[OW.shash("btya:%d:%d" % [seed, day]) % SYL_A.size()]) \
			+ String(SYL_B[OW.shash("btyb:%d:%d" % [seed, day]) % SYL_B.size()])
	var belt := int(OW.zone_belt(zone))
	return {
		"day": day, "zone": zone, "fam": fam, "tile": tile, "name": name,
		"belt": belt, "gold": bounty_gold(belt),
	}

## Статус ЧИСТЫМ чтением: флаг дня просрочен -> 0 (сброс по истечении дня,
## без штрафа; запись делает cull() в мирских путях).
static func status(gs) -> int:
	var d := int(gs.get_flag(DAY_FLAG, -1))
	if d != ENR.day_index():
		return ST_NONE
	return int(gs.get_flag(ST_FLAG, ST_NONE))

## Мягкий сброс (только мирские пути: доска/энтер/маркер): взятая, но
## просроченная охота сгорает без штрафа; живая цель-призрак снимается.
static func cull(gs) -> void:
	if int(gs.get_flag(DAY_FLAG, -1)) == ENR.day_index():
		return
	if int(gs.get_flag(ST_FLAG, ST_NONE)) == ST_ACTIVE:
		var old := String(offer_for(gs, int(gs.get_flag(DAY_FLAG, 0))).get("name", ""))
		gs.set_flag(ST_FLAG, ST_NONE)
		_despawn_target()
		if old != "":
			gs.toast.emit("Рассвет: охота «%s» истекла — без потери чего-либо." % old)
			gs.quest_changed.emit()

static func take(gs) -> void:
	cull(gs)
	if status(gs) != ST_NONE:
		return
	var o: Dictionary = offer(gs)
	if o.is_empty():
		return
	gs.set_flag(DAY_FLAG, int(o["day"]))
	gs.set_flag(ST_FLAG, ST_ACTIVE)
	gs.toast.emit("Доска: охота «%s» — %s, до рассвета." % [String(o["name"]), zone_title(String(o["zone"]))])
	gs.quest_changed.emit()   # автосейв: переход (канон belt_offer)

## Доска нажала E: берёт охоту или честно говорит статус. true — охота
## «съела» нажатие (цепочка к тому моменту уже отработала своим ответом).
static func board_press(gs) -> bool:
	cull(gs)
	match status(gs):
		ST_NONE:
			if offer(gs).is_empty():
				return false
			take(gs)   # свой тост «взято» даёт take()
			return true
		ST_ACTIVE:
			var o: Dictionary = offer(gs)
			gs.toast.emit("Охота «%s» ещё не закрыта: %s." % [String(o["name"]), zone_title(String(o["zone"]))])
			return true
	return false

## Подсказка доски для охоты (пусто — молчать). Строки охоты отличимы от
## строк цепочки — ни один прежний пин цепочки не трогает.
static func hunt_hint(gs) -> String:
	cull(gs)
	match status(gs):
		ST_NONE:
			if offer(gs).is_empty():
				return ""
			return "Охота «%s» — взять" % String(offer(gs)["name"])
		ST_ACTIVE:
			return "Охота «%s» — не закрыта" % String(offer(gs)["name"])
	return ""

## Зона под маркером «†» на карте мира ("" — маркеров нет).
static func map_marker_zone(gs) -> String:
	cull(gs)
	if status(gs) != ST_ACTIVE:
		return ""
	return String(offer(gs).get("zone", ""))

## Пересадка цели при входе в нужную локацию (зовёт world.apply_area) и на
## взятие, если игрок уже в зоне. Детерминированно: та же клетка offer'а,
## meta "i3_bounty" = день, комплект именованной элиты I1.
static func ensure_target(world: Node) -> void:
	if world == null:
		return
	cull(GameState)
	if status(GameState) != ST_ACTIVE:
		return
	var o: Dictionary = offer(GameState)
	var area := String(GameState.area)
	if area != "loc_" + String(o.get("zone", "")):
		return
	var grids: Variant = world.get("biome_grids")
	if grids == null:
		return
	var zone: Node = grids.get(String(o["zone"]))
	if zone == null or not is_instance_valid(zone):
		return
	if _target_alive():
		return
	var m: Node = zone.call("spawn_event_mob", String(o["fam"]), o["tile"] as Vector2i)
	if m == null:
		return
	m.set_meta("i3_bounty", int(o["day"]))
	Elites.apply_named(m, String(o["name"]), AURA)
	_mob = weakref(m)

static var _mob: WeakRef = null

static func _target_alive() -> bool:
	return _mob != null and _mob.is_valid() and is_instance_valid(_mob.get_ref())

static func _despawn_target() -> void:
	if _target_alive():
		(_mob.get_ref() as Node).queue_free()
	_mob = null

## Смерть цели (хук loot.on_mob_death по meta "i3_bounty" — ВНЕ гейта world,
## выдача не требует мира). Флаг 2 ДО выдачи — канон belt_turnin/refresh:
## повторная смерть/краш после флага награду не повторят.
static func on_bounty_death(gs, mob: Node) -> void:
	if mob == null or not mob.has_meta("i3_bounty"):
		return
	if status(gs) != ST_ACTIVE:
		return
	var o: Dictionary = offer(gs)
	if int(mob.get_meta("i3_bounty")) != int(o.get("day", -1)):
		return
	gs.set_flag(ST_FLAG, ST_DONE)        # флаг 2 — ДО выдачи
	var gold := int(o["gold"])
	gs.add_gold(gold)
	gs.elite_pity = int(gs.elite_pity) + 2   # хук I4: 2 pity-кредита реликта
	GameAudio.sfx("coin")
	gs.toast.emit("«%s» пал! Охота закрыта: +%d серебра, кредит реликта +2."
			% [String(o["name"]), gold])
	gs.quest_changed.emit()               # автосейв: награда выдана ровно раз

## Строка журнала (слияние в QuestsData.entries — язык тот же, что у цепочки;
## journal.gd не тронут — он под g12-пином). В журнал попадает только
## взятая/закрытая охота дня.
static func journal_entries(gs) -> Array:
	var st := status(gs)
	if st == ST_NONE:
		return []
	var o: Dictionary = offer(gs)
	if o.is_empty():
		return []
	return [{
		"id": "bty_%s" % String(o["zone"]),
		"title": "Охота: %s" % String(o["name"]),
		"desc": "Доска объявлений: убить «%s» в %s — до рассвета. " % [String(o["name"]), zone_title(String(o["zone"]))]
				+ "Награда — крупное серебро и кредит реликта. Доска ждёт вестей.",
		"status": st,
		"story": false,
		"targets": [{"label": "Убить: %s" % String(o["name"]),
				"cur": 1 if st == ST_DONE else 0, "need": 1, "done": st == ST_DONE}],
	}]

## offer для ПРОШЛОГО дня (тост истечения имя берёт у сгоревшего объявления).
static func offer_for(gs, day: int) -> Dictionary:
	var cur := ENR.day_index()
	# чистая функция дня: временно не читаем часы — повторяем тело offer()
	# с явным днём (день — единственный канал календаря в offer).
	var zones: Array = []
	for z in OW.ZONES:
		if str(gs.get_flag("wm.open." + String(z), "")) == "1":
			zones.append(String(z))
	if zones.is_empty():
		return {}
	var seed := int(gs.run_seed)
	var zone := String(zones[OW.shash("btyz:%d:%d" % [seed, day]) % zones.size()])
	var name := String(SYL_A[OW.shash("btya:%d:%d" % [seed, day]) % SYL_A.size()]) \
			+ String(SYL_B[OW.shash("btyb:%d:%d" % [seed, day]) % SYL_B.size()])
	return {"name": name, "zone": zone}

## Зеркало ZONE_TITLES QuestsData (тот же приём, что OW_ZONES-зеркала;
## расхождение поймает qa_bt).
static func zone_title(z: String) -> String:
	match z:
		"snow": return "Снежнике"
		"desert": return "Пустоши"
		"steppe": return "Степи"
		"forest": return "Чаще"
		"castle": return "Замке"
		"dungeon": return "Подземелье"
	return z
