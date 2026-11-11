extends "res://mb_base.gd"
## qa_pg — T6-пре: инварианты генератора ProcGen по CONTRACT_PROCGEN.md (§1 API, §3 план).
## Граница T6-пре: qa_pg.gd / qa_pg.tscn; manifest.json не трогаем.
## procregion.gd пишется параллельно (T2) — стенд НЕ заглядывает в дерево procregion:
## динамическая привязка по паттерну qa_run — var _pg: Variant, гейт только на ЗАГРУЗКЕ
## класса (ResourceLoader.exists), дальше ПРЯМЫЕ вызовы _pg.mixi(...) и т.д. Без
## has_method-гейтов: до появления генератора рантайм-ошибка обрывает блок, а
## «недосчитанные» проверки честно краснит RALL — это плановый RED, не подгонка.
##
## Проходимость стенд считает САМ по алфавитам зон (dungeon_zone/ashen_zone — источник
## истинны алфавита, сам стенд их не вызывает):
##   cave  closed: "." "," "S" "B" "M";          open: + "L" (дверь) + "C" (взят амулет —
##         сундук снят с клетки, dungeon_zone.cell_walkable);
##   ashen closed == open: "." "," "c" "a" "P" (дверей нет).
## Достижимость якоря = клетка якоря ИЛИ один из 4-соседей достижима (chest/door живут
## на функциональных блокерах C/L — мета-координата может быть клеткой-приставкой).
## Связность: открытое состояние; критерий карманов — план PROCGEN_PLAN §3.2.5:
## «нет изолированных проходимых карманов ≥2 клеток» (одиночная клетка-остров —
## унаследованный косметический дефект карты ash, (38,28); при ужесточении критерия
## до «строго всё в одном компоненте» — править одно место в _pocket_violations).
## uid сундуков: ТЕКУЩИЙ канон save-схемы T2 "chest@x,y" (game_state.chests_used);
## T5 сменит формат — стенд пишется против текущего и будет адаптирован.
## Golden-хеши: каноническая сериализация ВСЕГО словаря карты (ключи словарей
## упорядочены рекурсивно) + FNV-1a 64. Значения — ЗАГЛУШКИ: orchestrator запинит
## реальные хеши после мержа T2; до этого эти две проверки честно красные.

const GOLDEN_CAVE_PIN := -3750763034362895579  # TODO GOLDEN-CAVE-PIN: заглушка (= FNV-1a offset basis), запинить после T2
const GOLDEN_ASHEN_PIN := -3750763034362895578  # TODO GOLDEN-ASHEN-PIN: заглушка (offset basis + 1), запинить после T2

const RUN_SEED := 97531          # фиксированный мета-сид: seed_i = RUN_SEED + i*7919
const SEEDS := 50                # §3: 50 сидов на инвариант
const DAILY_STAMP := "1747500000"  # seed_daily пока принимает строку-стикер

var _pg: Variant = null

func _ready() -> void:
	if ResourceLoader.exists("res://scripts/procregion.gd"):
		_pg = load("res://scripts/procregion.gd")
	pg1_api()
	pg2_golden()
	pg3_size()
	pg4_determinism()
	pg5_unique_anchors()
	pg6_reach()
	pg7_anchors_walkable()
	pg8_connectivity()
	pg9_uid()
	# Целостность сюиты (паттерн qa_run): рантайм-ошибка «Invalid call ... on Nil»
	# обрывает лишь текущую функцию — RALL по СОБСТВЕННОМУ счётчику ловит оборванные
	# блоки. До генератора вердикт стенда — плановый красный.
	check("RALL: исполнены все 24 проверок PG1–PG9 (нет оборванных блоков)", _pass + _fail == 24)
	done()

# --- обвязка сидов ---

func _seeds() -> Array:
	var out: Array = []
	for i in SEEDS:
		out.append(RUN_SEED + i * 7919)
	return out

func _zone_seed(rs: int, zone: String) -> int:
	return int(_pg.seed_zone(rs, zone, 1))

func _gen_cave(rs: int) -> Dictionary:
	return _pg.cave_map(_zone_seed(rs, "cave"))

func _gen_ashen(rs: int) -> Dictionary:
	return _pg.ashen_map(_zone_seed(rs, "ashen"))

func _report(tag: String, bad: Array) -> bool:
	for s in bad.slice(0, 5):
		print("  [%s] %s" % [tag, String(s)])
	return bad.is_empty()

# --- канон и хеш (golden) ---

static func _canon(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = (v as Dictionary).keys()
			keys.sort()
			var parts: Array = []
			for k in keys:
				parts.append("%s:%s" % [_canon(k), _canon((v as Dictionary)[k])])
			return "{" + ",".join(PackedStringArray(parts)) + "}"
		TYPE_ARRAY:
			var parts2: Array = []
			for e in (v as Array):
				parts2.append(_canon(e))
			return "[" + ",".join(PackedStringArray(parts2)) + "]"
		TYPE_STRING:
			return "\"%s\"" % String(v)
		_:
			return str(v)

static func _fnv(s: String) -> int:
	# FNV-1a 64. offset basis 14695981039346656037 как int64-паттерн = -3750763034362895579.
	var h := -3750763034362895579
	for b in s.to_utf8_buffer():
		h ^= int(b)
		h *= 1099511628211  # FNV prime
	return h

# --- карты и обход ---

static func _grid_rows(m: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var g: Variant = m.get("grid", null)
	if typeof(g) == TYPE_ARRAY:
		for r in (g as Array):
			out.append(String(r))
	elif typeof(g) == TYPE_STRING:
		for r in String(g).split("\n"):
			out.append(r)
	return out

static func _wh(m: Dictionary) -> Vector2i:
	return Vector2i(int(m.get("width", 0)), int(m.get("height", 0)))

static func _ch(grid: PackedStringArray, x: int, y: int) -> String:
	if y < 0 or y >= grid.size() or x < 0 or x >= String(grid[y]).length():
		return "#"
	return String(grid[y])[x]

static func _w_ok(zone: String, ch: String, opened: bool) -> bool:
	if zone == "cave":
		if opened and (ch == "L" or ch == "C"):
			return true
		return ch == "." or ch == "," or ch == "S" or ch == "B" or ch == "M"
	return ch == "." or ch == "," or ch == "c" or ch == "a" or ch == "P"

static func _meta_of(m: Dictionary) -> Dictionary:
	var mt: Variant = m.get("meta", null)
	if typeof(mt) == TYPE_DICTIONARY:
		return mt as Dictionary
	return m

static func _xy_of(meta: Dictionary, key: String) -> Array:
	var v: Variant = meta.get(key, null)
	if typeof(v) == TYPE_ARRAY and (v as Array).size() > 0:
		var f: Variant = (v as Array)[0]
		if typeof(f) == TYPE_ARRAY:
			v = f
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return [int((v as Array)[0]), int((v as Array)[1])]
	return []

static func _count_anchor(meta: Dictionary, key: String) -> int:
	var v: Variant = meta.get(key, null)
	if v == null:
		return 0
	if typeof(v) != TYPE_ARRAY:
		return 0
	var a := v as Array
	if a.is_empty():
		return 0
	if typeof(a[0]) == TYPE_ARRAY:
		return a.size()
	if a.size() == 2 and typeof(a[0]) == TYPE_INT and typeof(a[1]) == TYPE_INT:
		return 1
	return a.size()

static func _bfs(grid: PackedStringArray, w: int, h: int, spawn: Array, zone: String, opened: bool) -> Dictionary:
	var seen := {}
	if spawn.size() != 2 or not _w_ok(zone, _ch(grid, spawn[0], spawn[1]), opened):
		return seen
	var start: int = spawn[1] * w + spawn[0]
	seen[start] = true
	var q: Array = [start]
	var head := 0
	var dx := [1, -1, 0, 0]
	var dy := [0, 0, 1, -1]
	while head < q.size():
		var k: int = q[head]
		head += 1
		var cx := k % w
		var cy := k / w
		for d in 4:
			var nx: int = cx + dx[d]
			var ny: int = cy + dy[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nk: int = ny * w + nx
			if seen.has(nk):
				continue
			if _w_ok(zone, _ch(grid, nx, ny), opened):
				seen[nk] = true
				q.append(nk)
	return seen

static func _reach(seen: Dictionary, w: int, h: int, x: int, y: int) -> bool:
	if seen.has(y * w + x):
		return true
	var dx := [1, -1, 0, 0]
	var dy := [0, 0, 1, -1]
	for d in 4:
		var nx: int = x + dx[d]
		var ny: int = y + dy[d]
		if nx >= 0 and ny >= 0 and nx < w and ny < h and seen.has(ny * w + nx):
			return true
	return false

## Критерий §3.2.5: изолированные проходимые карманы ≥2 клеток запрещены;
## одиночные клетки-острова (1 недостижимый проходимый тайл без достижимых соседей)
## допускаются унаследованной картой (ash (38,28)). При ужесточении — менять здесь.
static func _pocket_violations(seen: Dictionary, grid: PackedStringArray, w: int, h: int, zone: String, opened: bool) -> int:
	var bad := 0
	for y in h:
		for x in w:
			var k := y * w + x
			if seen.has(k) or not _w_ok(zone, _ch(grid, x, y), opened):
				continue
			var alone := true
			var dx := [1, -1, 0, 0]
			var dy := [0, 0, 1, -1]
			for d in 4:
				var nx: int = x + dx[d]
				var ny: int = y + dy[d]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var nk: int = ny * w + nx
				if seen.has(nk) or (_w_ok(zone, _ch(grid, nx, ny), opened) and not seen.has(nk) and nk > k):
					alone = false
			if not alone:
				bad += 1
	return bad

# --- PG1: чистота API ---

func pg1_api() -> void:
	var det := true
	for t in [[1, 2, 3], [0, 0, 0], [42, 42, 42], [-7, 99, 1], [12345, 6789, 2024], [97531, 7919, 3]]:
		var a: int = int(_pg.mixi(int(t[0]), int(t[1]), int(t[2])))
		var b: int = int(_pg.mixi(int(t[0]), int(t[1]), int(t[2])))
		det = det and (a == b) and (typeof(_pg.mixi(int(t[0]), int(t[1]), int(t[2]))) == TYPE_INT)
	check("PG1a: mixi детерминирован и возвращает int (6 троек, двойной вызов)", det)
	var tv: Variant = _pg.mixi(777, 777, 777)
	check("PG1b: mixi возвращает exactly int (TYPE_INT)", typeof(tv) == TYPE_INT)
	var vals := {}
	for t in [[1, 2, 3], [2, 1, 3], [1, 2, 4], [1, 3, 2], [0, 0, 1], [5000, 6, 7]]:
		vals[int(_pg.mixi(int(t[0]), int(t[1]), int(t[2])))] = true
	check("PG1c: mixi различает разные входы (6 троек → 6 разных значений)", vals.size() == 6)
	var z1: int = int(_pg.seed_zone(42, "cave", 1))
	var z2: int = int(_pg.seed_zone(42, "cave", 1))
	check("PG1d: seed_zone(42,\"cave\",1) детерминирован", z1 == z2)
	var za: int = int(_pg.seed_zone(42, "ashen", 1))
	var zw: int = int(_pg.seed_zone(42, "cave", 2))
	check("PG1e: seed_zone различает зону (cave!=ashen)", z1 != za)
	check("PG1f: seed_zone различает волну (cave,w1!=cave,w2)", z1 != zw)
	var d1: int = int(_pg.seed_daily(DAILY_STAMP))
	var d2: int = int(_pg.seed_daily(DAILY_STAMP))
	check("PG1g: seed_daily(\"%s\") детерминирован" % DAILY_STAMP, d1 == d2)

# --- PG2: golden (заглушки, плановый RED до пина orchestrator'ом) ---

func pg2_golden() -> void:
	# Ровно родительский канон: seed_zone(42, zone, 1) → zone_map → канон-хеш.
	var hc: int = _fnv(_canon(_pg.cave_map(int(_pg.seed_zone(42, "cave", 1)))))
	check("PG2a GOLDEN-CAVE-PIN: seed_zone(42,\"cave\",1) → cave_map → канон-хеш == запиненный golden", hc == GOLDEN_CAVE_PIN)
	print("  [GOLDEN-CAVE-PIN] фактический хеш = %d" % hc)
	var ha: int = _fnv(_canon(_pg.ashen_map(int(_pg.seed_zone(42, "ashen", 1)))))
	check("PG2b GOLDEN-ASHEN-PIN: seed_zone(42,\"ashen\",1) → ashen_map → канон-хеш == запиненный golden", ha == GOLDEN_ASHEN_PIN)
	print("  [GOLDEN-ASHEN-PIN] фактический хеш = %d" % ha)

# --- PG3: размеры ---

func pg3_size() -> void:
	var bad: Array = []
	for rs in _seeds():
		var m := _gen_cave(rs)
		var wh := _wh(m)
		var g := _grid_rows(m)
		if wh.x != 30 or wh.y != 22 or g.size() != 22:
			bad.append("seed=%d dims=%dx%d rows=%d" % [rs, wh.x, wh.y, g.size()])
			continue
		for row in g:
			if row.length() != 30:
				bad.append("seed=%d rowlen=%d" % [rs, row.length()])
				break
	check("PG3a: cave 30×22, сетка 22 строки равной длины (%d сидов)" % SEEDS, _report("PG3a", bad))
	var bad2: Array = []
	for rs in _seeds():
		var m2 := _gen_ashen(rs)
		var wh2 := _wh(m2)
		var g2 := _grid_rows(m2)
		if wh2.x != 40 or wh2.y != 30 or g2.size() != 30:
			bad2.append("seed=%d dims=%dx%d rows=%d" % [rs, wh2.x, wh2.y, g2.size()])
			continue
		for row in g2:
			if row.length() != 40:
				bad2.append("seed=%d rowlen=%d" % [rs, row.length()])
				break
	check("PG3b: ashen 40×30, сетка 30 строк равной длины (%d сидов)" % SEEDS, _report("PG3b", bad2))

# --- PG4: детерминизм двойной генерации ---

func pg4_determinism() -> void:
	var bad: Array = []
	for rs in _seeds():
		var zc := _zone_seed(rs, "cave")
		var h1: int = _fnv(_canon(_pg.cave_map(zc)))
		var h2: int = _fnv(_canon(_pg.cave_map(zc)))
		if h1 != h2:
			bad.append("cave seed=%d h1=%d h2=%d" % [rs, h1, h2])
	check("PG4a: cave_map детерминирован (двойной вызов, %d сидов)" % SEEDS, _report("PG4a", bad))
	var bad2: Array = []
	for rs in _seeds():
		var za := _zone_seed(rs, "ashen")
		var k1: int = _fnv(_canon(_pg.ashen_map(za)))
		var k2: int = _fnv(_canon(_pg.ashen_map(za)))
		if k1 != k2:
			bad2.append("ashen seed=%d h1=%d h2=%d" % [rs, k1, k2])
	check("PG4b: ashen_map детерминирован (двойной вызов, %d сидов)" % SEEDS, _report("PG4b", bad2))

# --- PG5: ровно по одному якорю ---

func pg5_unique_anchors() -> void:
	var bad: Array = []
	for rs in _seeds():
		var meta := _meta_of(_gen_cave(rs))
		for k in ["door", "chest", "boss", "boss_trigger"]:
			var n := _count_anchor(meta, k)
			if n != 1:
				bad.append("seed=%d %s=%d" % [rs, k, n])
	check("PG5a: cave door/chest/boss/boss_trigger ровно по одному (%d сидов)" % SEEDS, _report("PG5a", bad))
	var bad2: Array = []
	for rs in _seeds():
		var meta2 := _meta_of(_gen_ashen(rs))
		var nb := _count_anchor(meta2, "boss")
		var nc := _count_anchor(meta2, "chests")
		if nb != 1 or nc != 1:
			bad2.append("seed=%d boss=%d chests=%d" % [rs, nb, nc])
	check("PG5b: ashen boss==1, chests[0] ровно один (%d сидов)" % SEEDS, _report("PG5b", bad2))

# --- PG6: достижимость якорей (BFS от spawn) ---

func pg6_reach() -> void:
	var badc: Array = []
	var badch: Array = []
	var bada: Array = []
	for rs in _seeds():
		var mc := _gen_cave(rs)
		var g := _grid_rows(mc)
		var wh := _wh(mc)
		var meta := _meta_of(mc)
		var sp := _xy_of(meta, "spawn")
		var closed := _bfs(g, wh.x, wh.y, sp, "cave", false)
		for k in ["stairs_out", "hermit", "boss", "boss_trigger"]:
			var p := _xy_of(meta, k)
			if p.size() != 2 or not _reach(closed, wh.x, wh.y, p[0], p[1]):
				badc.append("seed=%d %s unreachable(closed)" % [rs, k])
		var opened := _bfs(g, wh.x, wh.y, sp, "cave", true)
		var ch := _xy_of(meta, "chest")
		if ch.size() != 2 or not _reach(opened, wh.x, wh.y, ch[0], ch[1]):
			badch.append("seed=%d chest unreachable(open)" % rs)
		var ma := _gen_ashen(rs)
		var ga := _grid_rows(ma)
		var wha := _wh(ma)
		var meta2 := _meta_of(ma)
		var spa := _xy_of(meta2, "spawn")
		var seen := _bfs(ga, wha.x, wha.y, spa, "ashen", true)
		for k in ["exit_portal", "boss"]:
			var p2 := _xy_of(meta2, k)
			if p2.size() != 2 or not _reach(seen, wha.x, wha.y, p2[0], p2[1]):
				bada.append("seed=%d %s unreachable" % [rs, k])
		var cs := _xy_of(meta2, "chests")
		if cs.size() != 2 or not _reach(seen, wha.x, wha.y, cs[0], cs[1]):
			bada.append("seed=%d chests[0] unreachable" % rs)
	check("PG6a: cave закрытая: stairs_out/hermit/boss/boss_trigger достижимы из spawn (%d)" % SEEDS, _report("PG6a", badc))
	check("PG6a2: cave открытая: chest достижим из spawn (%d)" % SEEDS, _report("PG6a2", badch))
	check("PG6b: ashen: exit_portal/boss/chests[0] достижимы из spawn (%d)" % SEEDS, _report("PG6b", bada))

# --- PG7: якоря на проходимых клетках ---

func pg7_anchors_walkable() -> void:
	var bad: Array = []
	for rs in _seeds():
		var mc := _gen_cave(rs)
		var g := _grid_rows(mc)
		var meta := _meta_of(mc)
		for k in ["spawn", "stairs_out", "hermit", "boss", "boss_trigger"]:
			var p := _xy_of(meta, k)
			if p.size() != 2 or not _w_ok("cave", _ch(g, p[0], p[1]), false):
				bad.append("seed=%d %s на непроходимой клетке" % [rs, k])
	check("PG7a: cave spawn/stairs_out/hermit/boss/boss_trigger на проходимых клетках (%d)" % SEEDS, _report("PG7a", bad))
	var bad2: Array = []
	for rs in _seeds():
		var ma := _gen_ashen(rs)
		var g2 := _grid_rows(ma)
		var meta2 := _meta_of(ma)
		for k in ["spawn", "exit_portal", "boss"]:
			var p2 := _xy_of(meta2, k)
			if p2.size() != 2 or not _w_ok("ashen", _ch(g2, p2[0], p2[1]), false):
				bad2.append("seed=%d %s на непроходимой клетке" % [rs, k])
	check("PG7b: ashen spawn/exit_portal/boss на проходимых клетках (%d)" % SEEDS, _report("PG7b", bad2))

# --- PG8: связность пола (открытое состояние; карманы §3.2.5) ---

func pg8_connectivity() -> void:
	var bad: Array = []
	for rs in _seeds():
		var mc := _gen_cave(rs)
		var g := _grid_rows(mc)
		var wh := _wh(mc)
		var sp := _xy_of(_meta_of(mc), "spawn")
		var seen := _bfs(g, wh.x, wh.y, sp, "cave", true)
		var v := _pocket_violations(seen, g, wh.x, wh.y, "cave", true)
		if v > 0:
			bad.append("seed=%d pocket-tiles=%d" % [rs, v])
	check("PG8a: cave открытая: все проходимые в одном компоненте пола, карманов ≥2 нет (%d)" % SEEDS, _report("PG8a", bad))
	var bad2: Array = []
	for rs in _seeds():
		var ma := _gen_ashen(rs)
		var ga := _grid_rows(ma)
		var wha := _wh(ma)
		var spa := _xy_of(_meta_of(ma), "spawn")
		var seen2 := _bfs(ga, wha.x, wha.y, spa, "ashen", true)
		var v2 := _pocket_violations(seen2, ga, wha.x, wha.y, "ashen", true)
		if v2 > 0:
			bad2.append("seed=%d pocket-tiles=%d" % [rs, v2])
	check("PG8b: ashen: все проходимые в одном компоненте пола, карманов ≥2 нет (%d)" % SEEDS, _report("PG8b", bad2))

# --- PG9: uid-совместимость (ТЕКУЩИЙ формат "chest@x,y", T5 адаптирует) ---

func pg9_uid() -> void:
	var bad: Array = []
	for rs in _seeds():
		var meta := _meta_of(_gen_cave(rs))
		var p := _xy_of(meta, "chest")
		if p.size() != 2 or not _uid_ok("chest@%d,%d" % [p[0], p[1]], p[0], p[1]):
			bad.append("seed=%d chest uid" % rs)
	check("PG9a: cave chest uid \"chest@x,y\" разбирается обратно в мета-координаты (%d)" % SEEDS, _report("PG9a", bad))
	var bad2: Array = []
	for rs in _seeds():
		var meta2 := _meta_of(_gen_ashen(rs))
		var p2 := _xy_of(meta2, "chests")
		if p2.size() != 2 or not _uid_ok("chest@%d,%d" % [p2[0], p2[1]], p2[0], p2[1]):
			bad2.append("seed=%d chests[0] uid" % rs)
	check("PG9b: ashen chests[0] uid \"chest@x,y\" разбирается обратно (%d)" % SEEDS, _report("PG9b", bad2))

static func _uid_ok(uid: String, x: int, y: int) -> bool:
	# ТЕКУЩАЯ канон-схема save: "chest@x,y" (interactable._uid / GameState.chests_used).
	if not uid.begins_with("chest@"):
		return false
	var rest := uid.substr(6)
	var cs := rest.split(",")
	if cs.size() != 2:
		return false
	var xs := String(cs[0])
	var ys := String(cs[1])
	if xs.is_empty() or ys.is_empty():
		return false
	for c in xs + ys:
		if c < "0" or c > "9":
			return false
	return int(xs) == x and int(ys) == y
