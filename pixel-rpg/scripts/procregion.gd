class_name ProcGen
## Процген фазы 2 (T2): чистая функция seed -> карта. Канон: CONTRACT_PROCGEN.md §1/§3/§4,
## поверх PROCGEN_PLAN.md §2.2.
## Железо D3: НИ GameState, НИ сцен, НИ randomize()/randi()/randf() — rng только с явным
## сидом; обход grid строго row-major; никакого обхода Dictionary в алгоритме раскладки
## (порядки — фиксированные массивы; валидационные словари-множества не несут порядка).
## Выход cave_map/ashen_map побайтово = data/map_cave.json / data/map_ashen.json
## (структура читалась из фактических JSON: у пещеры ключи на верхнем уровне, у
## Пепелища — словарь "meta").
## Шаблоны комнат: data/proc_rooms_cave.json / data/proc_rooms_ashen.json (схема §3):
## рамка "#", символы строго из CHAR_TO_TILE своей зоны, anchors — координаты ВНУТРИ
## шаблона под теми же именами, что ключи meta (spawn/stairs_out/exit_portal/boss/
## boss_trigger/chest/hermit). Допущение по шаблонам: имена якорей = имена meta-ключей.

const MASK32 := 0xFFFFFFFF
const TILE := 16
const CAVE_W := 30
const CAVE_H := 22
const ASHEN_W := 40
const ASHEN_H := 30
const ROOMS_CAVE_PATH := "res://data/proc_rooms_cave.json"
const ROOMS_ASHEN_PATH := "res://data/proc_rooms_ashen.json"
const MAX_ATTEMPTS := 64      # детерминированные salt-ветки при провале валидации
const MARGIN := 0             # зазор между комнатами: 0 — разделяют их "#" -рамки
# (суммарная площадь шести пещерных комнат с зазором > карты; непрокалываемость
# чужих рамок гарантирует _banned_other, зазор от края карты — рамку карты)

## Состав зон: фиксированный порядок тегов (никаких Dictionary-итераций).
const CAVE_TAGS := ["entry", "boss", "chest", "hermit", "altar", "any"]
const ASHEN_TAGS := ["entry", "boss", "chest", "any", "any", "any"]
## Сколько мобов/трав эммитит ashen_map (сверялось с фактическим map_ashen.json:
## archers=3, wraiths=4, swarm=4, herbs=3).
const ASHEN_MOBS := {"archers": 3, "wraiths": 4, "swarm": 4}
const ASHEN_HERBS := 3

const DIRS4 := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const _ALPHABET_CAVE := ".,#LSPRBMACV"
const _ALPHABET_ASHEN := ".,caTK#P"

# ============================================================================
# §1 API: сиды
# ============================================================================

## Splitmix-подобный целочисленный перемешиватель. Только int64-операции с маской
## 0xFFFFFFFF; множители < 2^31 — произведение с 32-битным аргументом гарантированно
## в диапазоне int64 (без переполнения знака; стабильно между платформами).
static func mixi(a: int, b: int, c: int) -> int:
	var x := (a + 0x9E3779B9) & MASK32
	x = (x ^ ((b & MASK32) + 0x85EBCA6B + ((x << 6) & MASK32) + (x >> 2))) & MASK32
	x = _mix_step(x)
	x = (x ^ ((c & MASK32) + 0xC2B2AE35 + ((x << 6) & MASK32) + (x >> 2))) & MASK32
	x = _mix_step(x)
	return x

static func _mix_step(x: int) -> int:
	x = (x ^ (x >> 16)) & MASK32
	x = (x * 0x7FEB352D) & MASK32
	x = (x ^ (x >> 15)) & MASK32
	x = (x * 0x6B9F1E7D) & MASK32
	x = (x ^ (x >> 17)) & MASK32
	return x

## Сид зоны забега: mixi(run_seed, hash(zone_id), wave). String.hash() — стабильный
## 32-битный FNV Godot (не зависит от платформы).
static func seed_zone(run_seed: int, zone_id: String, wave: int) -> int:
	return mixi(run_seed, zone_id.hash(), wave)

## Сид дневного забега по stamp'у. ЗАШИТ, НЕ ПОДКЛЮЧЕН (режима daily-run пока нет).
static func seed_daily(stamp: String) -> int:
	return mixi(0x0DAB1E, stamp.hash(), stamp.length())

# ============================================================================
# §1 API: карты
# ============================================================================

## Пещера: {width,height,tile,grid,spawn,stairs_out,hermit,boss,boss_trigger,chest,door}.
## Провал валидации — пересборка с детерминированной rng-солью (salt-ветка), не рандом.
static func cave_map(zone_seed: int) -> Dictionary:
	return _build_zone("cave", ROOMS_CAVE_PATH, zone_seed, 0xCA7E)

## Пепелище: {width,height,tile,grid,meta:{spawn,exit_portal,boss,chests,herbs,mobs}}.
static func ashen_map(zone_seed: int) -> Dictionary:
	return _build_zone("ashen", ROOMS_ASHEN_PATH, zone_seed, 0xA54E41)

static func _build_zone(zone: String, path: String, zone_seed: int, tagmix: int) -> Dictionary:
	var templates: Array = _load_templates(path)
	var last: Dictionary = {}
	for salt in MAX_ATTEMPTS:
		var rng := _rng(mixi(zone_seed, salt, tagmix))
		var r: Dictionary = _build_once(templates, zone, rng)
		last = r
		if r.get("ok", false):
			return r.get("map", {})
	# Все ветки иссякли (на валидных шаблонах практически недостижимо) — отдаём
	# последнюю сборку: потребитель стабильно получает словарь нужной формы.
	return last.get("map", _finish_map(_blank(CAVE_W if zone == "cave" else ASHEN_W,
		CAVE_H if zone == "cave" else ASHEN_H), {}, zone,
		CAVE_W if zone == "cave" else ASHEN_W, CAVE_H if zone == "cave" else ASHEN_H))

# ============================================================================
# Внутреннее: rng, шаблоны, алфавиты
# ============================================================================

static func _rng(seed_: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	return rng

static func _load_templates(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("ProcGen: нет шаблонов %s — карта не будет построена" % path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ProcGen: повреждён %s" % path)
		return []
	# "zone" в схеме §3 — на уровне ФАЙЛА; room-level "zone" — необязательное переопределение.
	var file_zone := String((parsed as Dictionary).get("zone", "cave"))
	var rooms: Variant = (parsed as Dictionary).get("rooms", [])
	if typeof(rooms) != TYPE_ARRAY:
		return []
	var out: Array = []
	for r in (rooms as Array):  # отбраковка — детерминированная, порядок файла
		if _template_ok(r, file_zone):
			out.append(r)
	return out

## Валидность шаблона по §3: прямоугольник строк равной длины, рамка "#",
## символы из алфавита зоны, интерьер непустой (>=5x5).
static func _template_ok(t: Variant, file_zone: String) -> bool:
	if typeof(t) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = t
	var grid: Variant = d.get("grid", [])
	if typeof(grid) != TYPE_ARRAY or (grid as Array).is_empty():
		return false
	var rows: Array = grid
	var w: int = String(rows[0]).length()
	if w < 5 or rows.size() < 5:
		return false
	var alphabet: String = _ALPHABET_CAVE \
		if String(d.get("zone", file_zone)) == "cave" else _ALPHABET_ASHEN
	var y := 0
	for rowv in rows:
		var row := String(rowv)
		if row.length() != w:
			return false
		for x in w:
			var ch := row[x]
			if alphabet.find(ch) < 0:
				return false
			if (y == 0 or y == rows.size() - 1 or x == 0 or x == w - 1) and ch != "#":
				return false
		y += 1
	return true

static func _walkable(zone: String, ch: String, open: bool) -> bool:
	if zone == "cave":
		if ch == "L" or ch == "C":
			return open
		# ".", "," — пол; "S" — выход; "B"/"M" — проходимый декор (в BLOCKING
		# dungeon_zone 8 и 9 отсутствуют). "P", "R", "A", "V" — блокеры.
		return ch == "." or ch == "," or ch == "S" or ch == "B" or ch == "M"
	return ch == "." or ch == "," or ch == "c" or ch == "a" or ch == "P"

static func _is_blocked(zone: String, ch: String) -> bool:
	return not _walkable(zone, ch, true)

# ============================================================================
# Раскладка (§4): упаковка комнат, остов+кольца, BFS-прорыв коридоров, двери
# ============================================================================

## Одна попытка: выбор шаблонов -> упаковка -> граф -> коридоры -> meta -> валидация.
static func _build_once(templates: Array, zone: String, rng: RandomNumberGenerator) -> Dictionary:
	var w: int = CAVE_W if zone == "cave" else ASHEN_W
	var h: int = CAVE_H if zone == "cave" else ASHEN_H
	var tags: Array = CAVE_TAGS if zone == "cave" else ASHEN_TAGS
	var picked: Array = _pick_templates(templates, tags, rng)
	if picked.size() != tags.size():
		return {"ok": false, "map": _finish_map(_blank(w, h), {}, zone, w, h)}
	var rects: Array = _pack_rooms(picked, w, h, rng)
	if rects.is_empty():
		return {"ok": false, "map": _finish_map(_blank(w, h), {}, zone, w, h)}
	var grid: Array = _carve_layout(picked, rects, zone, w, h, rng)
	var m: Dictionary = _emit_meta(grid, picked, rects, zone, w, h, rng)
	var map: Dictionary = _finish_map(grid, m, zone, w, h)
	return {"ok": _validate(map, zone, w, h), "map": map}

## Выбор шаблона под каждый тег состава: кандидаты — порядок файла, выбор rng.
static func _pick_templates(templates: Array, tags: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for tagv in tags:
		var tag := String(tagv)
		var candidates: Array = []
		for t in templates:
			var tgs: Variant = (t as Dictionary).get("tags", [])
			if typeof(tgs) == TYPE_ARRAY and (tgs as Array).has(tag):
				candidates.append(t)
		if candidates.is_empty() and tag == "any":
			for t in templates:  # "any" берёт любой шаблон, порядок файла
				candidates.append(t)
		if candidates.is_empty():
			return []
		out.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	return out

## Упаковка: порядок — по убыванию площади (индекс как tie-брейк; детерминированно),
## позиция из rng (несколько попыток); при коллизии — детерминированный скан
## row-major. Зазор между комнатами — их собственные "#" -рамки (MARGIN=0);
## chest-комната требует дополнительное кольцо воздуха: двери нужно место копания
## за рамкой (нишевые шаблоны иначе геометрически недостижимы).
static func _pack_rooms(picked: Array, w: int, h: int, rng: RandomNumberGenerator) -> Array:
	var n := picked.size()
	var rects: Array = []
	rects.resize(n)
	var sizes: Array = []
	var gaps: Array = []
	for t in picked:
		var rows0: Array = (t as Dictionary).get("grid", [])
		sizes.append([String(rows0[0]).length(), rows0.size()])
		var tgs: Variant = (t as Dictionary).get("tags", [])
		var g: int = MARGIN
		if typeof(tgs) == TYPE_ARRAY and (tgs as Array).has("chest"):
			g = MARGIN + 1
		gaps.append(g)
	var order: Array = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var sa: Array = sizes[a]
		var sb: Array = sizes[b]
		var aa: int = int(sa[0]) * int(sa[1])
		var ab: int = int(sb[0]) * int(sb[1])
		if aa != ab:
			return aa > ab
		return a < b)
	for idx in order:
		var rw: int = int((sizes[idx] as Array)[0])
		var rh: int = int((sizes[idx] as Array)[1])
		var gi: int = int(gaps[idx])
		if rw + 2 * gi + 2 > w or rh + 2 * gi + 2 > h:
			return []
		var rect := Rect2i(0, 0, rw, rh)
		var placed := false
		var lo_x := 1 + gi
		var hi_x := w - rw - 1 - gi
		var lo_y := 1 + gi
		var hi_y := h - rh - 1 - gi
		if hi_x < lo_x or hi_y < lo_y:
			return []
		for _try in 4:
			rect.position = Vector2i(rng.randi_range(lo_x, hi_x), rng.randi_range(lo_y, hi_y))
			if not _overlaps(rects, gaps, idx, rect):
				placed = true
				break
		if not placed:
			for y in range(lo_y, hi_y + 1):
				for x in range(lo_x, hi_x + 1):
					rect.position = Vector2i(x, y)
					if not _overlaps(rects, gaps, idx, rect):
						placed = true
						break
				if placed:
					break
		if not placed:
			return []
		rects[idx] = rect
	for i in n:
		if rects[i] == null:
			return []  # не должно случаться: порядок покрывает все индексы
	return rects

static func _overlaps(rects: Array, gaps: Array, idx: int, rect: Rect2i) -> bool:
	var gi: int = int(gaps[idx])
	for j in rects.size():
		if j == idx or rects[j] == null:
			continue
		var need: int = gi + int(gaps[j])
		var other: Rect2i = rects[j]
		if rect.position.x - other.position.x < other.size.x + need \
				and other.position.x - rect.position.x < rect.size.x + need \
				and rect.position.y - other.position.y < other.size.y + need \
				and other.position.y - rect.position.y < rect.size.y + need:
			return true
	return false

static func _blank(w: int, h: int) -> Array:
	var grid: Array = []
	for _y in h:
		grid.append("#".repeat(w))
	return grid

static func _rect_center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + int(r.size.x / 2), r.position.y + int(r.size.y / 2))

static func _rect_dist(a: Rect2i, b: Rect2i) -> int:
	var ca := _rect_center(a)
	var cb := _rect_center(b)
	return maxi(absi(ca.x - cb.x), absi(ca.y - cb.y))

## Комнаты в grid; фоновый "#" замещается интерьером шаблона.
static func _stamp_rooms(grid: Array, picked: Array, rects: Array) -> void:
	var i := 0
	for t in picked:
		var rows: Array = (t as Dictionary).get("grid", [])
		var rect: Rect2i = rects[i]
		var rx := rect.position.x
		var y := 0
		for _rowv in rows:
			var ry: int = rect.position.y + y
			# rect гарантированно внутри карты (_pack_rooms), строка шаблона — нужной длины:
			# вставляем сегмент шаблона в фон строки, не трогая остальное.
			var bg := String(grid[ry])
			grid[ry] = bg.substr(0, rx) + String(rows[y]) + bg.substr(rx + rect.size.x)
			y += 1
		i += 1

static func _carve_layout(picked: Array, rects: Array, zone: String, w: int, h: int,
		rng: RandomNumberGenerator) -> Array:
	var grid: Array = _blank(w, h)
	_stamp_rooms(grid, picked, rects)
	var chest_idx := _tag_index(picked, "chest") if zone == "cave" else -1
	var edges: Array = _mst(rects, rng, chest_idx)
	for e in _rings(edges, rects, zone, chest_idx, rng):
		edges.append(e)
	for e in edges:
		var a := int(e[0])
		var b := int(e[1])
		if b == chest_idx or a == chest_idx:
			_carve_door(grid, picked, rects, zone, w, h,
				a if a != chest_idx else b, chest_idx)
			continue
		_dig(grid, zone, w, h, rects, a, b, _rect_center(rects[a] as Rect2i),
			_rect_center(rects[b] as Rect2i), _banned_other(rects, a, b))
	return grid

## Prim-остов от entry (индекс 0): обход пар фиксированный, расстояние + rng-джиттер.
## leaf (chest в cave) — ЛИСТ остова: присоединяется один раз как best_j и НИКОГДА
## не расширяется — иначе остальные комнаты связываются ЧЕРЕЗ сундук (под дверью),
## и появляется второе отверстие в chest-комнате.
static func _mst(rects: Array, rng: RandomNumberGenerator, leaf: int) -> Array:
	var n := rects.size()
	var in_tree: Array = []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[0] = true
	var edges: Array = []
	for _step in n - 1:
		var best_d := 1 << 30
		var best_i := -1
		var best_j := -1
		for i in n:
			if not in_tree[i] or i == leaf:
				continue
			for j in n:
				if in_tree[j]:
					continue
				var d := _rect_dist(rects[i] as Rect2i, rects[j] as Rect2i) + rng.randi_range(0, 2)
				if d < best_d:
					best_d = d
					best_i = i
					best_j = j
		if best_j < 0:
			return edges
		in_tree[best_j] = true
		edges.append([mini(best_i, best_j), maxi(best_i, best_j)])
	return edges

## 1–2 ребра-кольца из свободных пар (сортировка фиксированная: dist,i,j, затем
## шаг выбора из rng). В cave chest не участвует: дверь остаётся единственным входом.
static func _rings(edges: Array, rects: Array, zone: String, chest_idx: int,
		rng: RandomNumberGenerator) -> Array:
	var n := rects.size()
	var taken := {}
	for e in edges:
		taken["%d:%d" % [mini(int(e[0]), int(e[1])), maxi(int(e[0]), int(e[1]))]] = true
	var free: Array = []
	for i in n:
		for j in range(i + 1, n):
			if taken.has("%d:%d" % [i, j]):
				continue
			if zone == "cave" and (i == chest_idx or j == chest_idx):
				continue
			free.append([i, j, _rect_dist(rects[i] as Rect2i, rects[j] as Rect2i)])
	free.sort_custom(func(p: Array, q: Array) -> bool:
		if int(p[2]) != int(q[2]):
			return int(p[2]) < int(q[2])
		if int(p[0]) != int(q[0]):
			return int(p[0]) < int(q[0])
		return int(p[1]) < int(q[1]))
	var want := 1 + rng.randi_range(0, 1)
	var out: Array = []
	var k := 0
	while out.size() < want and k < free.size():
		out.append([int(free[k][0]), int(free[k][1])])
		k += rng.randi_range(1, 2)  # не всегда самое близкое — кольца разнообразнее
	return out

static func _tag_index(picked: Array, tag: String) -> int:
	for i in picked.size():
		var tgs: Variant = (picked[i] as Dictionary).get("tags", [])
		if typeof(tgs) == TYPE_ARRAY and (tgs as Array).has(tag):
			return i
	return -1

## Чужие рамки (непрокалываемые клетки) для ребра a—b: точки рамок всех прочих rect.
static func _banned_other(rects: Array, own_a: int, own_b: int) -> Array:
	var out: Array = []
	for i in rects.size():
		if i == own_a or i == own_b:
			continue
		var r: Rect2i = rects[i]
		for x in range(r.position.x, r.position.x + r.size.x):
			out.append(Vector2i(x, r.position.y))
			out.append(Vector2i(x, r.position.y + r.size.y - 1))
		for y in range(r.position.y + 1, r.position.y + r.size.y - 1):
			out.append(Vector2i(r.position.x, y))
			out.append(Vector2i(r.position.x + r.size.x - 1, y))
	return out

static func _banned_has(banned: Array, t: Vector2i) -> bool:
	for b in banned:
		if t == b:
			return true
	return false

## BFS-прорыв: от from до цели. Цель: клетка `to` (explicit=true) либо первая
## проходимая клетка внутри rect B. Проходимые — проходим; "#" — прокалываем ("." пол);
## прочие блокеры и banned-клетки (рамки чужих комнат) — стена. Путь w1 расширяем до
## w2 компаньоном по перпендикуляру (там, где "#" и не banned). Возвращает true при
## соединении.
static func _dig(grid: Array, zone: String, w: int, h: int, rects: Array,
		_own_a: int, own_b: int, from: Vector2i, to: Vector2i, banned: Array,
		explicit: bool = false) -> bool:
	var rb: Rect2i = rects[own_b] as Rect2i
	if to.x < 1 or to.y < 1 or to.x > w - 2 or to.y > h - 2:
		return false
	if explicit and _banned_has(banned, to):
		return false
	if not explicit and rb.has_point(to):
		# цель внутри чужого rect: копать разрешено только в собственную рамку
		var ra: Rect2i = rects[_own_a] as Rect2i
		for i in rects.size():
			if i == _own_a or i == own_b:
				continue
			if (rects[i] as Rect2i).has_point(to):
				return false
	var seen := {}
	var prev := {}
	var q: Array = [from]
	seen[_key(from)] = true
	var head := 0
	var goal := Vector2i(-1, -1)
	while head < q.size() and goal.x < 0:
		var t: Vector2i = q[head]
		head += 1
		for d in DIRS4:
			var n := Vector2i(t.x + int(d[0]), t.y + int(d[1]))
			if n.x < 1 or n.y < 1 or n.x > w - 2 or n.y > h - 2:
				continue
			if seen.has(_key(n)):
				continue
			var ch := String(grid[n.y])[n.x]
			var walk := not _is_blocked(zone, ch)
			if not walk and ch != "#":
				continue  # блокеры кроме "#" — непроходимы
			if _banned_has(banned, n):
				continue  # рамка чужой комнаты / рамка chest-RECT (её вскрывает только дверь)
			seen[_key(n)] = true
			prev[_key(n)] = t
			if (explicit and n == to) or (not explicit and rb.has_point(n) and walk):
				goal = n
				break
			q.append(n)
	if goal.x < 0:
		return false
	# цепочка -> путь row-major-стабильный (обратный prev-ход детерминирован)
	var path: Array = [goal]
	var cur := goal
	while cur != from:
		cur = prev[_key(cur)]
		path.append(cur)
	path.reverse()
	for i in path.size():
		var t: Vector2i = path[i]
		if String(grid[t.y])[t.x] == "#":
			_set_cell(grid, t.x, t.y, ".", w, h)
		# w2: компаньон-полоса (кроме первой клетки и рамки целевой комнаты)
		if i > 0 and i < path.size() - 1:
			var p: Vector2i = path[i - 1]
			var perp := Vector2i(0, 1) if p.x == t.x else Vector2i(1, 0)
			var c := t + perp
			if c.x > 0 and c.y > 0 and c.x < w - 1 and c.y < h - 1 \
					and String(grid[c.y])[c.x] == "#" and not _banned_has(banned, c):
				_set_cell(grid, c.x, c.y, ".", w, h)
	return true

## Ребро к chest-комнате (cave): коридор w2 до клетки рамки; дальше единственная
## 1-тайловая дверь "L" и прокол клетки за ней (если "#"). Кандидаты двери — 4
## стороны, приоритет: «внутри» попадает на chest-якорь или соседку с ним — иначе
## нишевые шаблоны (c_chest_a: сундук в кармане за "C") недостижимы в принципе.
## Рамка chest-RECT забанена для копания: комнату вскрывает ТОЛЬКО дверь.
## Единственность входа: chest — лист остова (кольца его не касаются) + бан копания.
static func _carve_door(grid: Array, picked: Array, rects: Array, zone: String,
		w: int, h: int, other: int, chest_idx: int) -> bool:
	var rc: Rect2i = rects[chest_idx] as Rect2i
	var co := _rect_center(rects[other] as Rect2i)
	var a := _anchor_grid(picked[chest_idx] as Dictionary, rc, "chest")
	var banned: Array = _banned_other(rects, other, chest_idx)
	banned.append_array(_frame_points(rc))
	var pairs: Array = []  # фиксированный порядок: левая колонка, правая, верх, низ
	var top := rc.position.y
	var bot := rc.position.y + rc.size.y - 1
	var left := rc.position.x
	var right := rc.position.x + rc.size.x - 1
	for y in range(top + 1, bot):
		pairs.append([Vector2i(left, y), Vector2i(left + 1, y)])
	for y in range(top + 1, bot):
		pairs.append([Vector2i(right, y), Vector2i(right - 1, y)])
	for x in range(left + 1, right):
		pairs.append([Vector2i(x, top), Vector2i(x, top + 1)])
	for x in range(left + 1, right):
		pairs.append([Vector2i(x, bot), Vector2i(x, bot - 1)])
	for score_want in 3:  # 0 — внутрь якоря, 1 — соседка якоря, 2 — любая
		for p in pairs:
			var door: Vector2i = p[0]
			var ins: Vector2i = p[1]
			var score := 2
			if ins == a:
				score = 0
			elif absi(ins.x - a.x) + absi(ins.y - a.y) == 1:
				score = 1
			if score != score_want:
				continue
			if String(_at(grid, door.x, door.y, w, h)) != "#":
				continue
			var ch_in := String(_at(grid, ins.x, ins.y, w, h))
			if ch_in != "#" and ch_in != "" and _is_blocked(zone, ch_in):
				continue  # за дверью декор-блокнер — ищем другое место
			var out := _door_outside(rc, door)
			if out.x < 1 or out.y < 1 or out.x > w - 2 or out.y > h - 2:
				continue
			if not _dig(grid, zone, w, h, rects, other, chest_idx, co, out, banned, true):
				continue
			if ch_in == "#":
				_set_cell(grid, ins.x, ins.y, ".", w, h)
			_set_cell(grid, door.x, door.y, "L", w, h)
			return true
	return false

static func _door_outside(rc: Rect2i, door: Vector2i) -> Vector2i:
	if door.x == rc.position.x:
		return Vector2i(door.x - 1, door.y)
	if door.x == rc.position.x + rc.size.x - 1:
		return Vector2i(door.x + 1, door.y)
	if door.y == rc.position.y:
		return Vector2i(door.x, door.y - 1)
	return Vector2i(door.x, door.y + 1)

## Точки рамки rect (полное кольцо) — для бана копания.
static func _frame_points(rc: Rect2i) -> Array:
	var out: Array = []
	var x0 := rc.position.x
	var y0 := rc.position.y
	var x1 := rc.position.x + rc.size.x - 1
	var y1 := rc.position.y + rc.size.y - 1
	for x in range(x0, x1 + 1):
		out.append(Vector2i(x, y0))
		out.append(Vector2i(x, y1))
	for y in range(y0 + 1, y1):
		out.append(Vector2i(x0, y))
		out.append(Vector2i(x1, y))
	return out

# ============================================================================
# Эмиссия meta
# ============================================================================

static func _emit_meta(grid: Array, picked: Array, rects: Array, zone: String,
		w: int, h: int, rng: RandomNumberGenerator) -> Dictionary:
	var m: Dictionary = {}
	var entry := _tag_index(picked, "entry")
	var boss_i := _tag_index(picked, "boss")
	var chest_i := _tag_index(picked, "chest")
	var hermit_i := _tag_index(picked, "hermit")
	if entry >= 0:
		m["spawn"] = _xy(_anchor_grid(picked[entry] as Dictionary,
			rects[entry] as Rect2i, "spawn"))
		if zone == "cave":
			var st := _anchor_grid(picked[entry] as Dictionary,
				rects[entry] as Rect2i, "stairs_out")
			m["stairs_out"] = [st.x, st.y]
			_set_cell(grid, st.x, st.y, "S", w, h)  # тайл 5 — лестница, проходимый
		else:
			var pt := _anchor_grid(picked[entry] as Dictionary,
				rects[entry] as Rect2i, "exit_portal")
			if _is_blocked("ashen", String(_at(grid, pt.x, pt.y, w, h))):
				pt = _adjacent_floor(grid, zone,
					Vector2i(int(m["spawn"][0]), int(m["spawn"][1])), w, h)
			m["exit_portal"] = [pt.x, pt.y]
			_set_cell(grid, pt.x, pt.y, "P", w, h)  # тайл 7 — портал, проходимый
	if boss_i >= 0:
		m["boss"] = _xy(_anchor_grid(picked[boss_i] as Dictionary,
			rects[boss_i] as Rect2i, "boss"))
		var bt := _anchor_grid(picked[boss_i] as Dictionary,
			rects[boss_i] as Rect2i, "boss_trigger")
		if _is_blocked(zone, String(_at(grid, bt.x, bt.y, w, h))):
			bt = _adjacent_floor(grid, zone,
				Vector2i(int(m["boss"][0]), int(m["boss"][1])), w, h)
		m["boss_trigger"] = [bt.x, bt.y]
	if zone == "cave" and hermit_i >= 0:
		m["hermit"] = _xy(_anchor_grid(picked[hermit_i] as Dictionary,
			rects[hermit_i] as Rect2i, "hermit"))
	if chest_i >= 0:
		var ct := _anchor_grid(picked[chest_i] as Dictionary,
			rects[chest_i] as Rect2i, "chest")
		if zone == "cave":
			# Сундук = клетка "C": единственный в rect шаблона (c_chest_a — ниша),
			# иначе штампуем "C" (тайл 11) на якоре (c_chest_b нарисован без C).
			var cp := _find_char_rect(grid, "C", rects[chest_i] as Rect2i, w, h)
			if cp.x < 0:
				cp = ct
				_set_cell(grid, cp.x, cp.y, "C", w, h)
			m["chest"] = [cp.x, cp.y]
			m["door"] = [_xy(_find_door(grid, w, h))]
		else:
			m["chests"] = [[ct.x, ct.y]]
	if zone == "ashen":
		var sp := Vector2i(int(m["spawn"][0]), int(m["spawn"][1]))
		var banned_rects: Array = []
		if entry >= 0:
			banned_rects.append(rects[entry])
		if boss_i >= 0:
			banned_rects.append(rects[boss_i])
		var res: Array = _anchor_points(m)
		var hs := _scatter(grid, sp, ASHEN_HERBS, 4, res, banned_rects, w, h, rng)
		m["herbs"] = hs
		for v in hs:
			res.append(Vector2i(int(v[0]), int(v[1])))
		var mobs: Dictionary = {}
		for kind in ["archers", "wraiths", "swarm"]:
			var pts := _scatter(grid, sp, int(ASHEN_MOBS[kind]), 5 if kind == "swarm" else 6,
				res, banned_rects, w, h, rng)
			mobs[kind] = pts
			for v in pts:
				res.append(Vector2i(int(v[0]), int(v[1])))
		m["mobs"] = mobs
	return m

static func _anchor_points(m: Dictionary) -> Array:
	var out: Array = []
	for keyv in ["spawn", "exit_portal", "boss", "chests"]:
		if not m.has(keyv):
			continue
		var v: Variant = m[keyv]
		if typeof(v) != TYPE_ARRAY:
			continue
		if keyv == "chests":
			for e in (v as Array):
				out.append(Vector2i(int((e as Array)[0]), int((e as Array)[1])))
		else:
			out.append(Vector2i(int((v as Array)[0]), int((v as Array)[1])))
	return out

## Якорь шаблона -> глобальные координаты (сдвиг rect). Нет ключа — центр rect
## (оценит валидатор; отсутствие якоря на входе — дефект шаблона, не генератора).
static func _anchor_grid(t: Dictionary, rect: Rect2i, key: String) -> Vector2i:
	var hi: Dictionary = t.get("anchors", {})
	if hi.has(key):
		var a: Variant = hi[key]
		if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 2:
			return rect.position + Vector2i(int((a as Array)[0]), int((a as Array)[1]))
	return _rect_center(rect)

static func _xy(v: Vector2i) -> Array:
	return [v.x, v.y]

## Первый проходимый сосед по фикс-порядку DIRS4; если нет — сама точка (оценит валидатор).
static func _adjacent_floor(grid: Array, zone: String, from: Vector2i,
		w: int, h: int) -> Vector2i:
	for d in DIRS4:
		var t := Vector2i(from.x + int(d[0]), from.y + int(d[1]))
		if t.x >= 1 and t.y >= 1 and t.x < w - 1 and t.y < h - 1 \
				and not _is_blocked(zone, String(_at(grid, t.x, t.y, w, h))):
			return t
	return from

## Единственная "L" на карте — скан row-major (инвариант: ровно одна дверь).
static func _find_door(grid: Array, w: int, h: int) -> Vector2i:
	for y in h:
		var x := String(grid[y]).find("L")
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)

## Первый символ ch в rect — скан row-major (поиск штатного "C" шаблона).
static func _find_char_rect(grid: Array, ch: String, rc: Rect2i,
		w: int, h: int) -> Vector2i:
	for y in range(rc.position.y, mini(rc.position.y + rc.size.y, h)):
		var row := String(grid[y])
		for x in range(rc.position.x, mini(rc.position.x + rc.size.x, w)):
			if x < row.length() and row[x] == ch:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## Разброска мобов/трав Пепелища: кандидаты row-major -> Fisher–Yates (rng) ->
## greed: от spawn >= min_spawn, между собой >=2, не на якорях, вне rect entry/boss.
static func _scatter(grid: Array, spawn: Vector2i, want: int, min_spawn: int,
		reserved: Array, banned_rects: Array, w: int, h: int,
		rng: RandomNumberGenerator) -> Array:
	var cands: Array = []
	for y in range(1, h - 1):
		var row := String(grid[y])
		for x in range(1, w - 1):
			var ch := row[x]
			if ch != "." and ch != ",":
				continue
			var t := Vector2i(x, y)
			if maxi(absi(x - spawn.x), absi(y - spawn.y)) < min_spawn:
				continue
			var bad := false
			for r in reserved:
				if t == r:
					bad = true
					break
			if not bad:
				for br in banned_rects:
					if (br as Rect2i).has_point(t):
						bad = true
						break
			if not bad:
				cands.append(t)
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	var out: Array = []
	for t in cands:
		if out.size() >= want:
			break
		var ok := true
		for o in out:
			var ov: Array = o
			if maxi(absi(t.x - int(ov[0])), absi(t.y - int(ov[1]))) < 2:
				ok = false
				break
		if ok:
			out.append([t.x, t.y])
	return out

static func _finish_map(grid: Array, m: Dictionary, zone: String, w: int, h: int) -> Dictionary:
	if zone == "cave":
		return {
			"width": w, "height": h, "tile": TILE, "grid": grid,
			"spawn": m.get("spawn", [1, 1]),
			"stairs_out": m.get("stairs_out", [1, 1]),
			"hermit": m.get("hermit", [1, 1]),
			"boss": m.get("boss", [1, 1]),
			"boss_trigger": m.get("boss_trigger", [1, 1]),
			"chest": m.get("chest", [-1, -1]),
			"door": m.get("door", []),
		}
	return {"width": w, "height": h, "tile": TILE, "grid": grid, "meta": m}

static func _key(t: Vector2i) -> int:
	return t.y * 4096 + t.x

static func _at(grid: Array, x: int, y: int, w: int, h: int) -> String:
	if x < 0 or y < 0 or x >= w or y >= h:
		return ""
	return String(grid[y])[x]

## NB: имя не "_set" — не должно конфликтовать с виртуальным Object._set(property,value).
static func _set_cell(grid: Array, x: int, y: int, ch: String, w: int, h: int) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	var row := String(grid[y])
	grid[y] = row.substr(0, x) + ch + row.substr(x + 1)

# ============================================================================
# Валидация до эмиссии (§4)
# ============================================================================

static func _validate(map: Dictionary, zone: String, w: int, h: int) -> bool:
	var grid: Array = map.get("grid", [])
	if grid.size() != h:
		return false
	var m := map if zone == "cave" else (map.get("meta", {}) as Dictionary)
	var sp := Vector2i(int(m.get("spawn", [-1, -1])[0]), int(m.get("spawn", [-1, -1])[1]))
	if not _walkable(zone, String(_at(grid, sp.x, sp.y, w, h)), false):
		return false
	var reach := _bfs(grid, zone, sp, w, h, false)
	if zone == "cave":
		for keyv in ["stairs_out", "hermit", "boss_trigger", "boss"]:
			var p: Variant = m.get(keyv, [-1, -1])
			if not _reachable(reach, Vector2i(int((p as Array)[0]), int((p as Array)[1]))):
				return false
		var chest := Vector2i(int(m.get("chest", [-1, -1])[0]),
			int(m.get("chest", [-1, -1])[1]))
		if chest.x < 0 or String(_at(grid, chest.x, chest.y, w, h)) != "C":
			return false
		if _count_char(grid, "L", w, h) != 1:
			return false
		# в закрытом состоянии к сундуку не пройти (дверь держит)
		for d in DIRS4:
			if reach.has(_key(Vector2i(chest.x + int(d[0]), chest.y + int(d[1])))):
				return false
		# в открытом (L проходим) — достижим сосед сундука
		var ro := _bfs(grid, zone, sp, w, h, true)
		var nb := false
		for d in DIRS4:
			if ro.has(_key(Vector2i(chest.x + int(d[0]), chest.y + int(d[1])))):
				nb = true
		return nb
	# --- ashen: всё в одном состоянии (L/C нет) ---
	var r2 := _bfs(grid, zone, sp, w, h, true)
	var pts: Array = [
		Vector2i(int(m.get("exit_portal", [-1, -1])[0]), int(m.get("exit_portal", [-1, -1])[1])),
		Vector2i(int(m.get("boss", [-1, -1])[0]), int(m.get("boss", [-1, -1])[1])),
	]
	for e in m.get("chests", []):
		pts.append(Vector2i(int((e as Array)[0]), int((e as Array)[1])))
	for e in m.get("herbs", []):
		pts.append(Vector2i(int((e as Array)[0]), int((e as Array)[1])))
	var mobs: Variant = m.get("mobs", {})
	if typeof(mobs) != TYPE_DICTIONARY:
		return false
	for kind in ["archers", "wraiths", "swarm"]:
		var arr: Variant = (mobs as Dictionary).get(kind, [])
		if typeof(arr) != TYPE_ARRAY or (arr as Array).size() < int(ASHEN_MOBS[kind]):
			return false
		for e in (arr as Array):
			pts.append(Vector2i(int((e as Array)[0]), int((e as Array)[1])))
	if (m.get("herbs", []) as Array).size() < ASHEN_HERBS:
		return false
	for p in pts:
		if not _reachable(r2, p):
			return false
	return true

static func _count_char(grid: Array, ch: String, w: int, h: int) -> int:
	var n := 0
	for y in h:
		n += String(grid[y]).count(ch)
	return n

## BFS 4-связности по проходимому полу (якорям/мобам 4-связности достаточно).
static func _bfs(grid: Array, zone: String, from: Vector2i, w: int, h: int,
		open: bool) -> Dictionary:
	var seen := {}
	if not _walkable(zone, String(_at(grid, from.x, from.y, w, h)), open):
		return seen
	var q: Array = [from]
	seen[_key(from)] = true
	var head := 0
	while head < q.size():
		var t: Vector2i = q[head]
		head += 1
		for d in DIRS4:
			var n := Vector2i(t.x + int(d[0]), t.y + int(d[1]))
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if seen.has(_key(n)):
				continue
			if not _walkable(zone, String(grid[n.y])[n.x], open):
				continue
			seen[_key(n)] = true
			q.append(n)
	return seen

## Достижимо: клетка в BFS или имеет достижимую соседку (босс стоит на «V»).
static func _reachable(reach: Dictionary, t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0:
		return false
	if reach.has(_key(t)):
		return true
	for d in DIRS4:
		if reach.has(_key(Vector2i(t.x + int(d[0]), t.y + int(d[1])))):
			return true
	return false
