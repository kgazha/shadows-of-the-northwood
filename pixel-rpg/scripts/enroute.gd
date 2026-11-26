extends RefCounted
## I2 «Ритм в пути» (t35, 26.11, волна «Интерес v1»; вердикт 26.11: «мир не
## должен быть коридором»). Два события ПОСЕРЁДШЕМУ ПОСЛЕ существующих мобов,
## без нового ИИ и без нового контента:
## 1) НОЧНЫЕ ПАТРУЛИ: в сценах-локациях (loc_<биом>, кроме подземелья) после
##    наступления ночи по ДОРОГАМ loc_map (столб x=21 + ветка к сундуку —
##    детерминированная геометрия генератора) патрулируют 1-2 группы
##    существующих видов. Патруль = обычный моб, у которого этот тикер
##    переставляет `home` по дорожным клеткам: канон t39 («блуждание привязано
##    к гнезду») сам ведёт моба к дому, а штатная агр-механика моба (видит
##    игрока — погоня по своему velocity) включается БЕЗ нашего участия.
##    Рассвет — патрули расходятся (despawn). Дом паттерна: только ПРОХОДИМЫЕ
##    дорожные клетки (условие капитана 26.11 — никаких встанков у стен).
## 2) ОТВЕТКА НА ШУМ: три убийства в активной локации за один заход — через
##    45-90 с (детерминированный shash-выбор) на дистанции от героя прилетает
##    ответка 1-2 моба (шанс элиты — правило I1, Elites.apply), ОДИН раз на
##    зону за заход, не более ОДНОЙ активной. Тост «Что-то идёт на шум...».
##    Идёт на шум: `home`_members обновляется позицией героя, пока не завидит.
## Часы: GameState.day_t (тик в world._process, аддитивный ключ сейва, сброс
## с кругом). Цикл: DAY_LEN дня + NIGHT_LEN ночи. Ночь = ЕДИНСТВЕННОЕ время
## патрулей; day/night-вариантов арт-скелетов у мобов нет (ночь в мире —
## легальное ВРЕМЯ, а не перекраска — перекраски и не делаем).
## Тумблер «События в пути» (GameState.enroute_events, default ON, сейв
## аддитивно, Settings-строка по образцу bold_fx) глушит ОБА события; статы
## существ не меняются нигде.
## Визит-состояние (счётчик шума, патрули) — ПАМЯТЬ, не сейв: перезаход/
## перезагрузка = новый заход (семантика «один раз на зону ЗА ЗАХОД»).
## Таймер ответки тикает от rs.t (время забега, уже в сейве) — пауза
## переживает сохранение честной, а тесты крутят её без реального времени.

const OW := preload("res://scripts/open_world.gd")     # shash/BESTIARY — каноны
const ELITES := preload("res://scripts/elites.gd")     # I1 — шанс элиты ответки

const DAY_LEN := 180.0        # сек дня
const NIGHT_LEN := 120.0      # сек ночи
const CYCLE := DAY_LEN + NIGHT_LEN
const NOISE_KILLS := 3        # киллов за заход до срабатывания
const NOISE_MIN := 45.0       # пауза ответки, сек
const NOISE_SPAN := 46.0      # + shash % 46 -> [45..90] сек (капитан: 45-90)
const RETRIB_LIFE := 150.0    # предельное время жизни ответки, сек
const PATROL_NEAR := 10.0     # px до "пришёл в дом", дальше — следующая клетка
const RETRIB_DIST := 12       # клеток от героя при спавне ответки («прилетает издалека»)
const TOAST_NOISE := "Что-то идёт на шум..."   # ПИН (qa_rt сверяет буквально)

# ---- память визита (не сейвится: перезаход = чистый лист, см. шапку) ----
static var _noise := {}        # area -> {"kills":int,"due":float,"fired":bool}
static var _patrols: Array = []  # [{"mob":m,"zone":z,"path":[tiles],"idx":int}]
static var _retrib: Array = []   # [{"mobs":[..],"zone":z,"born":float,"next_home":float}]
static var _was_night := false

static func enabled() -> bool:
	return bool(GameState.enroute_events)

static func is_night() -> bool:
	return fmod(float(GameState.day_t), CYCLE) >= DAY_LEN

static func day_index() -> int:
	return int(float(GameState.day_t) / CYCLE)

## Сцены, где I2 живёт: биомные локации-переходы. Подземелье — по договору
## вне событий («не плодить смерть в убежище»), деревня/Пепелище/пещера/
## карта/мини-ходы — не сцены-переходы, их здесь нет структурно.
static func eligible_area(a: String) -> bool:
	return a.begins_with("loc_") and a != "loc_dungeon"

## Часы гонит world._process (единственный тикер мира).
static func tick(world: Node, delta: float) -> void:
	if not enabled():
		return
	var night := is_night()
	if _was_night and not night:
		_disperse_patrols()
	_was_night = night
	_tick_patrols()
	_tick_noise(world)
	_tick_retrib(world)

# ============================================================== шум/ответка
## зовёт loot.on_mob_death (рядом с note_belt_kill_area — тот же прецедент).
static func note_kill(area: String) -> void:
	if not enabled() or not eligible_area(area):
		return
	var st: Dictionary = _noise.get(area, {"kills": 0, "due": 0.0, "fired": false})
	if bool(st["fired"]):
		return
	st["kills"] = int(st["kills"]) + 1
	if int(st["kills"]) == NOISE_KILLS:
		var rs_t := float(GameState._num(GameState.flags.get("rs.t", 0), 0))
		var wait := NOISE_MIN + float(OW.shash("i2noise:%d:%s:%d" % [int(GameState.run_seed), area, day_index()]) % int(NOISE_SPAN))
		st["due"] = rs_t + wait
		GameState.toast.emit(TOAST_NOISE)
	_noise[area] = st

static func _tick_noise(world: Node) -> void:
	if not _retrib.is_empty():
		return   # ЖИВАЯ ответка — единственный активный наряд (сверх нового
				 # заказа не принимаем; срок жизни/смерть освобождают слот)
	if not _noise.is_empty():
		var rs_t := float(GameState._num(GameState.flags.get("rs.t", 0), 0))
		for area in _noise:
			var st: Dictionary = _noise[area]
			if bool(st["fired"]) or float(st["due"]) <= 0.0 or rs_t < float(st["due"]):
				continue
			st["due"] = -1.0
			if String(GameState.area) == String(area):
				_spawn_retrib(world, String(area))
				st["fired"] = true

static func _spawn_retrib(world: Node, area: String) -> void:
	# biome_grids[биом] — УЗЕЛ зоны (biome_zone.gd), не контейнер Loc_*:
	# только у зоны есть road_cells/spawn_event_mob.
	var zone: Node = world.get("biome_grids").get(area.substr(4)) if world.get("biome_grids") != null else null
	if zone == null or not is_instance_valid(zone):
		return
	var path: Array = zone.call("road_cells")
	if path.is_empty():
		return
	var zone_name := String(zone.get("biome"))
	if zone_name == "":
		return
	var fams: Array = OW.BESTIARY.get(zone_name, [])
	if fams.is_empty():
		return
	var hero: Node = world.get("player")
	if hero == null:
		return
	var n := 1 + (1 if OW.shash("i2rn:%d:%s:%d" % [int(GameState.run_seed), area, day_index()]) % 100 < 45 else 0)
	var born := float(GameState._num(GameState.flags.get("rs.t", 0), 0))
	var mobs: Array = []
	var ord := 0
	for k in n:
		ord += 1
		var fam := String((fams[OW.shash("i2rf:%d:%s:%d:%d" % [int(GameState.run_seed), area, day_index(), ord]) % fams.size()] as Array)[0])
		if not zone.call("mob_fam_known", fam):
			continue
		var cell := _far_road_cell(zone, path, hero, area, ord)
		if cell == Vector2i(-1, -1):
			continue
		var m: Node = zone.call("spawn_event_mob", fam, cell)
		if m == null:
			continue
		m.set_meta("i2_retrib", true)
		# I1-наследие: ответка — мировые мобы, шанс элиты по правилу I1.
		ELITES.apply(m, "i2retrib:" + area, cell, ord)
		m.home = hero.global_position   # идёт на шум
		mobs.append(m)
	if mobs.is_empty():
		return
	_retrib.append({"mobs": mobs, "zone": zone, "born": born, "next_home": 0.0})

## Дальняя дорожная клетка: >= RETRIB_DIST клеток от героя, детерминированный
## обход дороги от shash-смещения; только проходимые (гарантия — не встанет в стену).
static func _far_road_cell(zone: Node, path: Array, hero: Node, area: String, ord: int) -> Vector2i:
	var start := OW.shash("i2rc:%d:%s:%d:%d" % [int(GameState.run_seed), area, day_index(), ord]) % maxi(1, path.size())
	var tile_size := 16.0
	for k in path.size():
		var t: Vector2i = path[(start + k) % path.size()]
		if not bool(zone.call("cell_walkable", t)):
			continue
		var wp: Vector2 = zone.call("tile_to_world", t)
		if wp.distance_to(hero.global_position) >= float(RETRIB_DIST) * tile_size:
			return t
	return Vector2i(-1, -1)

static func _tick_retrib(world: Node) -> void:
	var rs_t := float(GameState._num(GameState.flags.get("rs.t", 0), 0))
	var i := _retrib.size() - 1
	while i >= 0:
		var e: Dictionary = _retrib[i]
		var alive: Array = []
		for m in (e["mobs"] as Array):
			if is_instance_valid(m) and not bool(m.get("dying")):
				alive.append(m)
		var old_zone: Node = e["zone"]
		if alive.is_empty() or rs_t - float(e["born"]) > RETRIB_LIFE or not is_instance_valid(old_zone):
			for m in (e["mobs"] as Array):
				if is_instance_valid(m):
					m.queue_free()
			_retrib.remove_at(i)
			i -= 1
			continue
		e["mobs"] = alive
		# «идёт на шум»: дом = герой, пока не завидит (дальше моб сам).
		if rs_t >= float(e["next_home"]):
			e["next_home"] = rs_t + 2.0
			var hero: Node = world.get("player")
			if hero != null:
				for m in alive:
					if m.global_position.distance_to(hero.global_position) > 40.0:
						m.home = hero.global_position
		i -= 1

# ================================================================= патрули
## зовёт world.apply_area при входе в сцену (после сборки зоны).
static func on_area_enter(world: Node, _prev: String) -> void:
	var area := String(GameState.area)
	# заход = чистый лист шума (семантика договора); патрули старой сцены
	# живут в выключенных контейнерах — их доживит тик/рассвет.
	_noise.erase(area)
	if not enabled() or not eligible_area(area) or not is_night():
		return
	var grids: Variant = world.get("biome_grids")
	if grids == null:
		return
	var zone: Node = grids.get(area.substr(4))
	if zone == null or not is_instance_valid(zone):
		return
	_spawn_patrols(world, zone, area)

static func _spawn_patrols(world: Node, zone: Node, area: String) -> void:
	if not _patrols_for_area(area).is_empty():
		return   # уже стоим в этой сцене (резюме без смены сцены)
	var path: Array = zone.call("road_cells")
	if path.size() < 6:
		return
	var zone_name := String(zone.get("biome"))
	if zone_name == "":
		return
	var fams: Array = OW.BESTIARY.get(zone_name, [])
	if fams.is_empty():
		return
	var groups := 1 + (1 if OW.shash("i2pg:%d:%s:%d" % [int(GameState.run_seed), area, day_index()]) % 100 < 50 else 0)
	var off := OW.shash("i2po:%d:%s:%d" % [int(GameState.run_seed), area, day_index()]) % path.size()
	for g in groups:
		var fam := String((fams[OW.shash("i2pf:%d:%s:%d:%d" % [int(GameState.run_seed), area, day_index(), g]) % fams.size()] as Array)[0])
		if not zone.call("mob_fam_known", fam):
			continue
		for s in 2:   # группа — пара, идущая гуськом по дороге
			var idx := (off + g * 3 + s) % path.size()
			var t: Vector2i = path[idx]
			if not bool(zone.call("cell_walkable", t)):
				continue
			var m: Node = zone.call("spawn_event_mob", fam, t)
			if m == null:
				continue
			m.set_meta("i2_patrol", true)
			_patrols.append({"mob": m, "zone": zone, "area": area, "path": path, "idx": idx})

static func _patrols_for_area(area: String) -> Array:
	var out: Array = []
	for p in _patrols:
		if String(p["area"]) == area and is_instance_valid(p["mob"]):
			out.append(p)
	return out

## Перестановка дома: дошёл (или прилип) — следующая дорожная клетка ТОЛЬКО
## проходимая (условие капитана: никаких новых трупов у стен).
## t36-хвост (26.11, qa_c1): валидность проверяется ДО типизированного
## присваивания — `var m: Node = p["mob"]` от уже freed-инстанса сам поднимает
## SCRIPT ERROR (кадр с гибелью патруля засорял лог; длинный c1-плейт ловил TMO
## на потоке ошибок). Вариант-чтение безопасно, тип — только после гейта.
static func _tick_patrols() -> void:
	var i := _patrols.size() - 1
	while i >= 0:
		var p: Dictionary = _patrols[i]
		if not is_instance_valid(p["mob"]) or not is_instance_valid(p["zone"]) \
				or bool((p["mob"] as Node).get("dying")):
			_patrols.remove_at(i)
			i -= 1
			continue
		var m: Node = p["mob"]
		var z: Node = p["zone"]
		var home_pos: Vector2 = m.home
		if m.global_position.distance_to(home_pos) <= PATROL_NEAR:
			var path: Array = p["path"]
			var nidx := (int(p["idx"]) + 1) % path.size()
			var guard := 0
			var t: Vector2i = path[nidx]
			while not bool(z.call("cell_walkable", t)) and guard < path.size():
				nidx = (nidx + 1) % path.size()
				t = path[nidx]
				guard += 1
			if bool(z.call("cell_walkable", t)):
				m.home = z.call("tile_to_world", t)
				if "wander_t" in m:
					m.wander_t = 0.0
				p["idx"] = nidx
		i -= 1

static func _disperse_patrols() -> void:
	for p in _patrols:
		if is_instance_valid(p["mob"]):
			(p["mob"] as Node).queue_free()
	_patrols.clear()

## Полный сброс памяти (стенды/тесты): патрули сняты, шум чист.
static func reset_all() -> void:
	_disperse_patrols()
	for e in _retrib:
		for m in (e["mobs"] as Array):
			if is_instance_valid(m):
				m.queue_free()
	_retrib.clear()
	_noise.clear()
	_was_night = false
