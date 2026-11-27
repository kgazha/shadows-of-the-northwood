extends "res://mb_base.gd"
## QA RT — t35 I2 «Ритм в пути» (26.11, волна «Интерес v1»; вердикт: «мир не
## должен быть коридором»). Проверяется РОВНО контракт I2: часы дня (фаза,
## аддитивный сейв-ключ, легаси-дефолты, сброс с кругом), НОЧНЫЕ ПАТРУЛИ в
## сценах-локациях (есть ночью, дома — только проходимые дорожные клетки,
## рассвет разобрал, детерминизм двух сборок), ОТВЕТКА на шум (ровно после
## 3-го килла, тост-пин, пауза в [45..90] сек, спавн с дистанции, ровно один
## наряд, лимит одной живой, чистый лист на новый заход), ГЕЙТЫ (деревня,
## Пепелище, подземелье, пещера, карта — ноль событий), тумблер «События в
## пути» OFF => ноль событий при живых часах.
## Время крутим ЧЕСТНО: rs.t (время забега, общий тикер) для пауз ответки,
## day_t — прямая установка фазы (часы мира тестировщику подчиняются).

const ENR := preload("res://scripts/enroute.gd")

var _toasts: Array = []

func _ready() -> void:
	await boot(save_for(0))
	await pump(3)
	GameState.toast.connect(func(t: String) -> void: _toasts.append(t))
	_s1()
	await _s2()
	await _s3()
	await _s3b()
	await _s4()
	await _s5()
	await _s6()
	done()

# ------------------------------------------------------------------ часы
func _s1() -> void:
	GameState.day_t = 0.0
	check("S1 день стартует днём (day_t=0)", not ENR.is_night() and ENR.day_index() == 0)
	GameState.day_t = ENR.DAY_LEN - 0.5
	check("S1 последняя полсекунда дня — ещё день", not ENR.is_night())
	GameState.day_t = ENR.DAY_LEN
	check("S1 ночь наступает на DAY_LEN", ENR.is_night())
	GameState.day_t = ENR.CYCLE - 0.5
	check("S1 ночь держится до конца цикла", ENR.is_night() and ENR.day_index() == 0)
	GameState.day_t = ENR.CYCLE
	check("S1 рассвет обнуляет день (индекс 1, фаза — день)", not ENR.is_night() and ENR.day_index() == 1)
	GameState.day_t = 0.0

# -------------------------------------------------------------- патрули
func _count_meta(n: Node, key: String) -> int:
	var c := 0
	if n.has_meta(key) and bool(n.get_meta(key)):
		c += 1
	for ch in n.get_children():
		c += _count_meta(ch, key)
	return c

func _collect_meta(n: Node, key: String, out: Array) -> void:
	if n.has_meta(key) and bool(n.get_meta(key)):
		out.append(n)
	for ch in n.get_children():
		_collect_meta(ch, key, out)

func _enter(area: String) -> void:
	world.apply_area(area)
	await pump(2)

func _set_phase(night: bool) -> void:
	# установка фазы + кадр синхронизации _was_night (иначе рассветный
	# триггер сработает на первом же тике и разберёт ещё не рождённое)
	GameState.day_t = ENR.DAY_LEN + 10.0 if night else 5.0
	await pump(1)

func _s2() -> void:
	ENR.reset_all()
	GameState.enroute_events = true
	await _set_phase(true)
	await _enter("loc_steppe")
	var zone: Node = world.biome_grids.get("steppe")
	check("S2 локация собралась", zone != null)
	var patrols: Array = []
	_collect_meta(world, "i2_patrol", patrols)
	check("S2 ночью в степняке патруль есть, 1-2 группы гуськом (2-4 моба): %d" % patrols.size(),
		patrols.size() >= 2 and patrols.size() <= 4)
	# дома патрульных — ТОЛЬКО дорожные проходимые клетки (условие аудитора:
	# никаких встанков у стен)
	var roads: Array = zone.call("road_cells")
	var bad := 0
	for m in patrols:
		var best := 1e9
		for t in roads:
			best = minf(best, (m as Node2D).home.distance_to(zone.call("tile_to_world", t)))
		if best > 1.5:
			bad += 1
	check("S2 дома патрулей лежат на дорогах (%d вне)" % bad, bad == 0 and not roads.is_empty())
	# детерминизм двух сборок одного дня
	var sig_a := ""
	for m in patrols:
		sig_a += "%.0f,%.0f;" % [(m as Node2D).global_position.x, (m as Node2D).global_position.y]
	ENR.reset_all()
	await _enter("village")
	await _set_phase(true)
	await _enter("loc_steppe")
	var patrols2: Array = []
	_collect_meta(world, "i2_patrol", patrols2)
	var sig_b := ""
	for m in patrols2:
		sig_b += "%.0f,%.0f;" % [(m as Node2D).global_position.x, (m as Node2D).global_position.y]
	check("S2 детерминизм: две сборки ночи дают тот же патруль (%d==%d)" % [patrols.size(), patrols2.size()],
		patrols.size() == patrols2.size() and sig_a == sig_b)
	# рассвет расходятся
	await _set_phase(false)
	await pump(3)
	var left := _count_meta(world, "i2_patrol")
	check("S2 рассвет: патрули разошлись (осталось %d)" % left, left == 0)
	ENR.reset_all()

# --------------------------------------------------------------- ответка
func _rs_now() -> float:
	return float(GameState._num(GameState.flags.get("rs.t", 0), 0))

func _advance_rs(sec: float) -> void:
	GameState.flags["rs.t"] = _rs_now() + sec
	await pump(2)

func _squads() -> int:
	var c := 0
	for e in ENR._retrib:
		for m in (e["mobs"] as Array):
			if is_instance_valid(m) and not bool(m.get("dying")):
				c += 1
				break
	return c

func _s3() -> void:
	ENR.reset_all()
	GameState.enroute_events = true
	await _set_phase(false)   # день: патрули не мешают
	await _enter("loc_forest")
	_toasts.clear()
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	check("S3 после двух киллов тишина", _toasts.size() == 0 and _squads() == 0)
	ENR.note_kill("loc_forest")
	check("S3 третий килл => тост-пин «%s»" % ENR.TOAST_NOISE, _toasts.has(ENR.TOAST_NOISE))
	check("S3 сразу наряд не прилетает (пауза)", _squads() == 0)
	await _advance_rs(ENR.NOISE_MIN + ENR.NOISE_SPAN + 5.0)  # 96 сек >max паузы
	var squad: Array = []
	_collect_meta(world, "i2_retrib", squad)
	check("S3 после паузы наряд прилетел (1-2): %d" % squad.size(), squad.size() >= 1 and squad.size() <= 2)
	# «прилетает издалека»: спавн >=10 клеток (движение за 2 кадра — доли пикселя)
	var far := 0
	for m in squad:
		if (m as Node2D).global_position.distance_to(world.player.global_position) >= 10.0 * 16.0:
			far += 1
	check("S3 наряд спавнится с дистанции >=10 клеток (%d/%d)" % [far, squad.size()], far == squad.size())
	# ещё три килла в том же заходе — второй волны нет (fired). 20 с — мало
	# для lifespan наряда (150 с) и много для already-fired: пин честный.
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	await _advance_rs(20.0)
	var again: Array = []
	_collect_meta(world, "i2_retrib", again)
	check("S3 ровно одна волна на заход (повторов нет: %d==%d)" % [again.size(), squad.size()], again.size() == squad.size())
	# живой наряд блокирует новый заказ даже на новом заходе (лимит одного);
	# пин по ИДЕНТИЧНОСТИ: заказ сверх принятого не принимается (тот же born),
	# а не «после сноса lifespan прилетел свежий» — его проверит хвост
	var _born_before := float((ENR._retrib[0] as Dictionary)["born"])
	await _enter("village")
	await _enter("loc_forest")
	_toasts.clear()
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	await _advance_rs(96.0)
	check("S3 лимит: живой наряд — второго нет (тот же заказ, born=%.0f)" % _born_before,
		_squads() == 1 and ENR._retrib.size() == 1 and float((ENR._retrib[0] as Dictionary)["born"]) == _born_before)
	# наряд умер/истёк -> слот свободен (принудительный снос = смерть), а ЧИСТЫЙ
	# ЛИСТ даёт только новый заход (erase при входе): выходим и входим снова,
	# три килла — заказ выполняется (пока живой наряд не блокирует канал)
	for e in ENR._retrib:
		for m in (e["mobs"] as Array):
			if is_instance_valid(m):
				m.free()
	ENR._retrib.clear()
	await _enter("village")
	await _enter("loc_forest")
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	await _advance_rs(96.0)
	check("S3 после сноса наряда новый заход снова стреляет (retrib=%d rs=%.0f)" % [ENR._retrib.size(), _rs_now()], _squads() == 1)
	ENR.reset_all()

## S3b t44 (27.11, находка ворот t39): честная отмена ответки при смене зоны.
## Прежнее поведение молчало: due=-1, счётчик килов висел, повторный заказ
## в заходе был невозможен. Ныне: запись шума стирается, возврат = чистый
## старт с новым тостом; в чужой зоне наряд НЕ телепортируется.
func _s3b() -> void:
	ENR.reset_all()
	GameState.enroute_events = true
	await _set_phase(false)
	await _enter("loc_forest")
	_toasts.clear()
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	check("S3b заказ поставлен (тост)", _toasts.has(ENR.TOAST_NOISE))
	await _enter("village")
	await _advance_rs(ENR.NOISE_MIN + ENR.NOISE_SPAN + 6.0)
	check("S3b честная отмена: запись шума стёрта (не due=-1-призрак)",
		not ENR._noise.has("loc_forest"))
	check("S3b в чужой зоне наряд не прилетает (отмена, не телепорт)", _squads() == 0)
	_toasts.clear()
	await _enter("loc_forest")
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	ENR.note_kill("loc_forest")
	check("S3b счётчик обнулён: на возврате заказ снова встаёт (тост)",
		_toasts.has(ENR.TOAST_NOISE))
	ENR.reset_all()

# ----------------------------------------------------------------- гейты
func _s4() -> void:
	ENR.reset_all()
	await _set_phase(true)
	# деревня ночью — ни патруля
	await _enter("village")
	check("S4 деревня ночью чиста", _count_meta(world, "i2_patrol") == 0 and _count_meta(world, "i2_retrib") == 0)
	# подземелье — контрактный исключённый участок
	await _enter("loc_dungeon")
	check("S4 loc_dungeon ночью чист", _count_meta(world, "i2_patrol") == 0)
	for area in ["village", "cave", "ashen", "loc_dungeon", "worldmap", "mini_forest"]:
		await _enter("village")
		_toasts.clear()
		ENR.note_kill(area)
		ENR.note_kill(area)
		ENR.note_kill(area)
		await _advance_rs(96.0)
		check("S4 гейт: зона %s — шум не слышен (ни тоста, ни наряда)" % area,
			_toasts.is_empty() and _count_meta(world, "i2_retrib") == 0)
	ENR.reset_all()

# --------------------------------------------------------------- тумблер
func _s5() -> void:
	ENR.reset_all()
	GameState.enroute_events = false
	await _set_phase(true)
	await _enter("loc_steppe")
	check("S5 тумблер OFF: ночи нет, патрулей нет", ENR.is_night() and _count_meta(world, "i2_patrol") == 0)
	_toasts.clear()
	ENR.note_kill("loc_steppe")
	ENR.note_kill("loc_steppe")
	ENR.note_kill("loc_steppe")
	await _advance_rs(96.0)
	check("S5 тумблер OFF: шум мёртв", _toasts.is_empty() and _count_meta(world, "i2_retrib") == 0)
	GameState.enroute_events = true
	await _enter("village")
	ENR.reset_all()

# ------------------------------------------------------------------ сейв
func _s6() -> void:
	GameState.day_t = ENR.DAY_LEN + 30.0
	GameState.enroute_events = false
	var d: Dictionary = GameState.to_dict()
	check("S6 to_dict несёт day_t (аддитивно к v4)", absf(float(d.get("day_t", -1.0)) - (ENR.DAY_LEN + 30.0)) < 0.001)
	check("S6 to_dict несёт enroute_events=false", bool(d.get("enroute_events", true)) == false)
	var gs2 = load("res://scripts/game_state.gd").new()
	gs2.from_dict(d)
	check("S6 roundtrip: fresh-инстанс прочитал часы и тумблер",
		absf(gs2.day_t - (ENR.DAY_LEN + 30.0)) < 0.001 and bool(gs2.enroute_events) == false)
	var d_leg: Dictionary = d.duplicate(true)
	d_leg.erase("day_t")
	d_leg.erase("enroute_events")
	var gs3 = load("res://scripts/game_state.gd").new()
	gs3.day_t = 99.0
	gs3.enroute_events = false
	gs3.from_dict(d_leg)
	check("S6 легаси-сейв: часы=0 (день), тумблер=ВКЛ (миграции нет)",
		absf(gs3.day_t) < 0.001 and bool(gs3.enroute_events) == true)
	var gs4 = load("res://scripts/game_state.gd").new()
	gs4.day_t = 50.0
	gs4._wipe_circle()
	check("S6 круг обнуляет часы", absf(gs4.day_t) < 0.001)
	gs2.free()
	gs3.free()
	gs4.free()
	GameState.day_t = 0.0
	GameState.enroute_events = true
	ENR.reset_all()
	check("S6 стенд разобран: память Enroute чиста",
		ENR._patrols.is_empty() and ENR._retrib.is_empty() and ENR._noise.is_empty())
