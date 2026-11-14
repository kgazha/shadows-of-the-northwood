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
##
## PG10 (T6-остаток): place_units(zone_seed, map, zone, wave=1) — канон T3.
## Чистота API (двойной вызов на одной карте, 3-arg == 4-arg wave=1),
## инварианты расстановки на 50 сидах × волны 1..5 × обе зоны (юниты на
## проходимых, ни одного точно на якоре POI, попарно chebyshev >= 2, капсы по
## видам — капсы ЧИТАЮТСЯ из data/proc_profiles.json, не хардкод), золотой
## эталон 11 брутов на ручной data/map_cave.json @ zone_seed=0 (позиции
## запинены числами), chest_bonus = 1 при wave >= 3.
## PG11 (баг владельца «сундук открылся, не открывая дверь»): зона взаимодействия
## сундука (8-окрестность клетки «C»: CaveChest r=14 + бокс игрока достают уголком
## через угол стены) целиком закрыта в CLOSED; дверь не сирота (к ней примыкает
## достижимый closed-пол). 50 сидов каскада.

const GOLDEN_CAVE_PIN := -1017898612486188285  # GOLDEN-CAVE-PIN: FNV-1a 64, cave_map(seed_zone(42,"cave",1)) @ c13 (тонкийка алтарей: по одному «A» в комнатах с алтарями; был 8065050884287841817 @ b862110 после PG8a-фикса)
const GOLDEN_ASHEN_PIN := 8636615847371749653  # GOLDEN-ASHEN-PIN: FNV-1a 64, ashen_map(seed_zone(42,"ashen",1)) @ b862110
const GOLDEN_CAVE_UNITS := [[24, 6], [27, 6], [13, 7], [16, 7], [11, 8], [27, 9], [10, 10], [24, 12], [27, 12], [8, 14], [17, 14]]  # GOLDEN-PLACE-PIN: эталон world._spawn_cave_mobs (11 брутов), место действия — PG10c
const PROFILES_PATH := "res://data/proc_profiles.json"
const MAP_CAVE_PATH := "res://data/map_cave.json"

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
	pg10_api()
	pg10_invariants()
	pg10_golden()
	pg10_chest()
	pg11_chest_seal()
	# Целостность сюиты (паттерн qa_run): рантайм-ошибка «Invalid call ... on Nil»
	# обрывает лишь текущую функцию — RALL по СОБСТВЕННОМУ счётчику ловит оборванные
	# блоки. До генератора вердикт стенда — плановый красный.
	check("RALL: исполнены все 34 проверок PG1–PG11 (нет оборванных блоков)", _pass + _fail == 34)
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

# --- PG10: place_units (T6-остаток; сигнатура/возврат — канон T3) ---

func pg10_api() -> void:
	# Чистота API: двойной вызов place_units на ОДНОЙ и той же карте-словаре
	# (ловит и скрытую мутацию карты, и нечистый детерминизм) + канон 3-arg
	# вызова (wave по умолчанию == 1). Обе зоны, та же каскадная выборка сидов.
	var badd: Array = []
	var bad3: Array = []
	for rs in _seeds():
		for zone in ["cave", "ashen"]:
			var z: int = _zone_seed(rs, zone)
			var m: Dictionary = _pg.cave_map(z) if zone == "cave" else _pg.ashen_map(z)
			var r1: Dictionary = _pg.place_units(z, m, zone, 1)
			var r2: Dictionary = _pg.place_units(z, m, zone, 1)
			if _canon(r1) != _canon(r2):
				badd.append("%s seed=%d: двойной вызов place_units разошёлся" % [zone, rs])
			var r3: Dictionary = _pg.place_units(z, m, zone)
			if _canon(r1) != _canon(r3):
				bad3.append("%s seed=%d: 3-arg != 4-arg wave=1" % [zone, rs])
	check("PG10a: place_units детерминирован (двойной вызов на одной карте, обе зоны, %d сидов)" % SEEDS, _report("PG10a", badd))
	check("PG10a2: place_units(seed, map, zone) == place_units(seed, map, zone, 1) — канон 3-arg (обе зоны, %d)" % SEEDS, _report("PG10a2", bad3))

func pg10_invariants() -> void:
	# Инварианты расстановки: 50 сидов × волны 1..5 × обе зоны. Капсы по видам
	# ЧИТАЮТСЯ из data/proc_profiles.json (родитель: не хардкод); набор якорей —
	# ровно тот, что читает place_units: cave spawn/stairs_out/chest/door/hermit/
	# boss, ashen spawn/exit_portal/boss + массивы chests/herbs (boss_trigger —
	# НЕ POI, намеренно вне набора). Проверка «на якоре» — точное совпадение с
	# координатой якоря (не радиус): радиусные запретники — внутренность движка.
	var prof: Variant = _json_at(PROFILES_PATH)
	var badw: Array = []
	var bada: Array = []
	var badch: Array = []
	var badk: Array = []
	if typeof(prof) != TYPE_DICTIONARY:
		badk.append("%s нечитаем — капсы непроверяемы" % PROFILES_PATH)
	for rs in _seeds():
		for zone in ["cave", "ashen"]:
			var z: int = _zone_seed(rs, zone)
			var m: Dictionary = _pg.cave_map(z) if zone == "cave" else _pg.ashen_map(z)
			var g := _grid_rows(m)
			var anch := _anchor_points(m, zone)
			for wave in range(1, 6):
				var res: Dictionary = _pg.place_units(z, m, zone, wave)
				var units: Array = res.get("units", [])
				for u in units:
					var p := _upos(u)
					if p.size() != 2:
						badw.append("%s seed=%d w%d: unit без pos" % [zone, rs, wave])
						continue
					if not _w_ok(zone, _ch(g, p[0], p[1]), false):
						badw.append("%s seed=%d w%d: unit (%d,%d) на непроходимой клетке" % [zone, rs, wave, p[0], p[1]])
					var pk := "%d,%d" % [p[0], p[1]]
					if anch.has(pk):
						bada.append("%s seed=%d w%d: unit точно на якоре %s (%s)" % [zone, rs, wave, String(anch[pk]), pk])
				for i in units.size():
					var pa := _upos(units[i])
					if pa.size() != 2:
						continue
					for j in range(i + 1, units.size()):
						var pb := _upos(units[j])
						if pb.size() != 2:
							continue
						if maxi(absi(pa[0] - pb[0]), absi(pa[1] - pb[1])) < 2:
							badch.append("%s seed=%d w%d: cheb(%d,%d;%d,%d) < 2" % [zone, rs, wave, pa[0], pa[1], pb[0], pb[1]])
							break
				if typeof(prof) == TYPE_DICTIONARY:
					var row: Variant = _prof_row(prof, zone, wave)
					if row == null:
						badk.append("%s w%d: нет строки волны в профиле" % [zone, wave])
					else:
						var kinds: Array = _prof_kinds(prof, zone)
						var caps: Array = (row as Dictionary).get("caps", [])
						var counts := {}
						for u2 in units:
							var kd := String((u2 as Dictionary).get("kind", ""))
							counts[kd] = int(counts.get(kd, 0)) + 1
						for kk in counts:
							var kkd := String(kk)
							var ci: int = kinds.find(kkd)
							if ci < 0:
								badk.append("%s seed=%d w%d: вид \"%s\" вне kinds профиля" % [zone, rs, wave, kkd])
							elif ci >= caps.size():
								badk.append("%s w%d: капсов в строке меньше, чем kinds" % [zone, wave])
							elif int(counts[kkd]) > int(caps[ci]):
								badk.append("%s seed=%d w%d: %s=%d > капс %d" % [zone, rs, wave, kkd, int(counts[kkd]), int(caps[ci])])
	check("PG10b: все юниты на проходимых клетках (волны 1..5, обе зоны, %d сидов)" % SEEDS, _report("PG10b", badw))
	check("PG10b2: ни один юнит не стоит точно на координате якоря POI (волны 1..5, обе зоны, %d)" % SEEDS, _report("PG10b2", bada))
	check("PG10b3: попарно chebyshev >= 2 между юнитами (волны 1..5, обе зоны, %d)" % SEEDS, _report("PG10b3", badch))
	check("PG10b4: капсы по видам не превышены, капсы из data/proc_profiles.json (волны 1..5, обе зоны, %d)" % SEEDS, _report("PG10b4", badk))

func pg10_golden() -> void:
	# Ровно родительский канон: place_units(0, РУЧНАЯ data/map_cave.json с диска,
	# "cave") == множество 11 брутов эталона world._spawn_cave_mobs (позиции
	# запинены числами выше) + chest_bonus == 0. Вид/тир юнита при этом —
	# каноническая глубинная полоса от spawn (bands/kinds читаются из
	# proc_profiles.json, не хардкод): на волне 1 глубина 4..7 -> brute,
	# 8..11 -> brute_t2, 12+ -> brute_t3 — «бруты» эталона в своих полосах.
	var ok := false
	var msg := ""
	var parsed: Variant = _json_at(MAP_CAVE_PATH)
	var prof: Variant = _json_at(PROFILES_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		msg = "%s не читается как Dictionary" % MAP_CAVE_PATH
	elif typeof(prof) != TYPE_DICTIONARY or typeof((prof as Dictionary).get("cave", null)) != TYPE_DICTIONARY:
		msg = "%s нечитаем — bands/kinds недоступны" % PROFILES_PATH
	else:
		var cave: Dictionary = (prof as Dictionary)["cave"] as Dictionary
		var kinds: Array = cave.get("kinds", [])
		var bands: Array = cave.get("bands", [])
		var sp := _xy_of(parsed as Dictionary, "spawn")
		if kinds.is_empty() or bands.is_empty() or sp.size() != 2:
			msg = "профиль/спавн карты неполны"
		else:
			var res: Dictionary = _pg.place_units(0, parsed as Dictionary, "cave")
			var units: Array = res.get("units", [])
			var got := {}
			var kindbad := 0
			for u in units:
				var p := _upos(u)
				if p.size() != 2:
					kindbad += 1
					continue
				var d := maxi(absi(p[0] - sp[0]), absi(p[1] - sp[1]))
				var ki := bands.size() - 1
				for b in bands.size():
					if d <= int((bands[b] as Array)[1]):
						ki = b
						break
				var ud := u as Dictionary
				if d < int((bands[0] as Array)[0]) or String(ud.get("kind", "")) != String(kinds[ki]) or int(ud.get("tier", -1)) != ki + 1:
					kindbad += 1
				got["%d,%d" % [p[0], p[1]]] = true
			var want := {}
			for e in GOLDEN_CAVE_UNITS:
				want["%d,%d" % [int((e as Array)[0]), int((e as Array)[1])]] = true
			var cb := int(res.get("chest_bonus", -1))
			ok = kindbad == 0 and cb == 0 and got == want
			if not ok:
				msg = "got=%d want=%d kindbad=%d chest_bonus=%d" % [got.size(), want.size(), kindbad, cb]
				for k in want:
					if not got.has(k):
						msg += " нет(%s)" % String(k)
				for k in got:
					if not want.has(k):
						msg += " лишн(%s)" % String(k)
	check("PG10c GOLDEN-PLACE: place_units(0, data/map_cave.json, \"cave\") == 11 брутов эталона (позиции) + chest_bonus==0", ok)
	if not msg.is_empty():
		print("  [PG10c] %s" % msg)

func pg10_chest() -> void:
	# chest_bonus — флаг бонусного сундука волны: 1 при wave >= 3, 0 при wave 1..2
	# (план §2.2). 5 сидов × волны 1..5 × обе зоны.
	var bad: Array = []
	for rs in _seeds().slice(0, 5):
		for zone in ["cave", "ashen"]:
			var z: int = _zone_seed(rs, zone)
			var m: Dictionary = _pg.cave_map(z) if zone == "cave" else _pg.ashen_map(z)
			for wave in range(1, 6):
				var res: Dictionary = _pg.place_units(z, m, zone, wave)
				var wantb: int = 1 if wave >= 3 else 0
				var cb := int(res.get("chest_bonus", -1))
				if cb != wantb:
					bad.append("%s seed=%d w%d: chest_bonus=%d != %d" % [zone, rs, wave, cb, wantb])
	check("PG10d: chest_bonus = 1 при wave>=3, 0 при wave 1..2 (волны 1..5, обе зоны, 5 сидов)", _report("PG10d", bad))

# --- PG11: герметичность сундука (баг «сундук открылся, не открывая дверь») ---

func pg11_chest_seal() -> void:
	# Владелец жаловался: сундук открывался, не открывая двери, а «двери
	# случайным образом разбросаны». Корень (проверено фактической диагностикой
	# на каскаде): CaveChest — Area2D r=14 плюс бокс игрока 10x8, поэтому игрок,
	# стоявший рядом или по диагонали за углом, доставал сундук УГОЛКОМ хитбокса
	# через стену даже при запертой двери. Значит одного «клетка сундука
	# недостижима в closed» (PG6a) мало: недостижимой должна быть ВСЯ зона
	# взаимодействия — 8-клеточное кольцо вокруг сундука.
	#
	# PG11a: ни одна клетка 8-окрестности сундука не достижима из spawn в CLOSED
	#       (иначе игрок тычется в сундук сквозь угол до открытия двери).
	# PG11b: дверь не «валяется» сиротой — у неё есть хотя бы одна соседняя
	#       достижимая в CLOSED клетка пола (подход снаружи), т.е. closed-пол
	#       примыкает к двери.
	var bad_a: Array = []
	var bad_b: Array = []
	var dx8 := [1, -1, 0, 0, 1, 1, -1, -1]
	var dy8 := [0, 0, 1, -1, 1, -1, 1, -1]
	var dx4 := [1, -1, 0, 0]
	var dy4 := [0, 0, 1, -1]
	for rs in _seeds():
		var m: Dictionary = _gen_cave(rs)
		var g := _grid_rows(m)
		var wh := _wh(m)
		var meta := _meta_of(m)
		var sp := _xy_of(meta, "spawn")
		var ch := _xy_of(meta, "chest")
		var dr := _xy_of(meta, "door")
		if sp.size() != 2 or ch.size() != 2:
			bad_a.append("seed=%d: нет spawn/chest" % rs)
			continue
		var closed: Dictionary = _bfs(g, wh.x, wh.y, sp, "cave", false)
		var cx: int = ch[0]
		var cy: int = ch[1]
		for d in 8:
			var nx: int = cx + dx8[d]
			var ny: int = cy + dy8[d]
			if nx < 0 or ny < 0 or nx >= wh.x or ny >= wh.y:
				continue
			if closed.has(ny * wh.x + nx):
				bad_a.append("seed=%d chest(%d,%d): зона взаимодействия (%d,%d) достижима в CLOSED" % [rs, cx, cy, nx, ny])
		if dr.size() != 2:
			bad_b.append("seed=%d: нет door" % rs)
			continue
		var rx: int = dr[0]
		var ry: int = dr[1]
		var approach := false
		for d in 4:
			var ax: int = rx + dx4[d]
			var ay: int = ry + dy4[d]
			if ax < 0 or ay < 0 or ax >= wh.x or ay >= wh.y:
				continue
			if closed.has(ay * wh.x + ax):
				approach = true
				break
		if not approach:
			bad_b.append("seed=%d door(%d,%d): сирота — нет достижимого в CLOSED подхода снаружи" % [rs, rx, ry])
	check("PG11a: зона взаимодействия сундука (8-окрестность, CaveChest r=14+бокс) целиком закрыта в CLOSED (%d сидов)" % SEEDS, _report("PG11a", bad_a))
	check("PG11b: дверь не сирота — у неё есть достижимый в CLOSED подход снаружи (%d сидов)" % SEEDS, _report("PG11b", bad_b))

# --- хелперы PG10 ---

static func _json_at(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

static func _prof_row(prof: Variant, zone: String, wave: int) -> Variant:
	var z: Variant = (prof as Dictionary).get(zone, null)
	if typeof(z) != TYPE_DICTIONARY:
		return null
	var wv: Variant = (z as Dictionary).get("waves", null)
	if typeof(wv) != TYPE_DICTIONARY:
		return null
	var row: Variant = (wv as Dictionary).get(str(wave), null)
	return row if typeof(row) == TYPE_DICTIONARY else null

static func _prof_kinds(prof: Variant, zone: String) -> Array:
	var z: Variant = (prof as Dictionary).get(zone, null)
	if typeof(z) == TYPE_DICTIONARY:
		var kd: Variant = (z as Dictionary).get("kinds", null)
		if typeof(kd) == TYPE_ARRAY:
			return kd as Array
	return []

static func _upos(u: Variant) -> Array:
	if typeof(u) != TYPE_DICTIONARY:
		return []
	var pv: Variant = (u as Dictionary).get("pos", null)
	if typeof(pv) == TYPE_ARRAY and (pv as Array).size() >= 2:
		return [int((pv as Array)[0]), int((pv as Array)[1])]
	if typeof(pv) == TYPE_VECTOR2I:
		return [(pv as Vector2i).x, (pv as Vector2i).y]
	return []

static func _pt(e: Variant) -> Array:
	# Как _poi_add у движка: вложенная форма [[x, y]] сворачивается в первую пару.
	if typeof(e) != TYPE_ARRAY:
		return []
	var a: Array = e
	if a.size() >= 1 and typeof(a[0]) == TYPE_ARRAY:
		a = a[0]
	if a.size() >= 2:
		return [int(a[0]), int(a[1])]
	return []

static func _anchor_points(m: Dictionary, zone: String) -> Dictionary:
	var meta := _meta_of(m)
	var out := {}
	var keys: Array = ["spawn", "stairs_out", "chest", "door", "hermit", "boss"] if zone == "cave" else ["spawn", "exit_portal", "boss"]
	for k in keys:
		var p := _xy_of(meta, String(k))
		if p.size() == 2:
			out["%d,%d" % [p[0], p[1]]] = String(k)
	if zone != "cave":
		for lk in ["chests", "herbs"]:
			var v: Variant = meta.get(String(lk), null)
			if typeof(v) != TYPE_ARRAY:
				continue
			for e in (v as Array):
				var pe := _pt(e)
				if pe.size() == 2:
					out["%d,%d" % [pe[0], pe[1]]] = String(lk)
	return out
