extends RefCounted
## t19 «Глубина v2 §2а» (25.11): ЧИСТЫЙ генератор микро-подземелий.
## Ни GameState, ни randf, ни сцен — детерминизм воспроизводится под -s без
## игры (тот же приём, что affixes.gd в t17; хэши-пины qa_pg PG12).
## Канон сида: OW.zone_seed(run_seed, "mini_<биом>") — родич сида локации,
## но отдельный ключ: ход живёт СВОЕЙ геометрией, локацию не двигает
## (GOLDEN-WM-PIN и решётки loc_map целы — инвариант §2).
##
## Планиметрия: 40×24 (640×384 px — обе оси >= вида 640×360, camera limits
## честные, полос не будет). Кольцо '#' по периметру глухое. Комнаты 3..4:
## входная (снизу,spawn = клетка хода), 1..2 средних, финальная. Якоря —
## по BFS от спавна (определение, не макет): мини-босс — центр самой ДАЛЕКОЙ
## не-входной комнаты («дальняя комната» контракта), сундук — ближайшая из
## прочих; ties — первый по обходу. Связность —
## L-коридорами цепочки комнат (ширина 1); конструктивно гарантирована,
## BFS-пин qa_pg сверяет поверх. Пол — символ биома (лес 'f').
##
## "Перф-этаж": MINI_Y = 48000 = 10 × YS_CYCLE — новый верхний «этаж»
## над лентой локаций; шаг YS/сейв-полос тот же, что у всех зон.

const OW := preload("res://scripts/open_world.gd")

const W := 40
const H := 24
const MINI_Y := 48000.0
## t20 (25.11): «этаж» хода на биом — MINI_Y + i×4800 (тот же шаг полос
## YS_CYCLE, что у всех зон). ПОРЯДОК BIOMES-append-only: индексы (а значит
## и этажи, и сейвы «mini_<biom>») прежних биомов не двигаются.
const FLOOR_STEP := 4800.0

## t19: лес (§2 «по одному биому за шаг»). t20 (25.11) шагами открывает
## остальные пять; список append-only (этажи mini_y привязаны к индексу).
const BIOMES := ["forest", "steppe", "desert", "snow", "castle", "dungeon"]

## Этаж (y-сдвиг) хода биома; неизвестный биом — base (не должен зваться).
static func mini_y(biome: String) -> float:
	var i: int = BIOMES.find(biome)
	return MINI_Y + FLOOR_STEP * float(maxi(i, 0))

## Биом по мировой y («с какого хода точка»); вне мини-этажей — "".
static func biome_at_y(y: float) -> String:
	if y < MINI_Y:
		return ""
	var i := int(floor((y - MINI_Y) / FLOOR_STEP))
	if i < 0 or i >= BIOMES.size():
		return ""
	return String(BIOMES[i])

## Пол биома (символ клетки внутренней сетки).
static func floor_ch(biome: String) -> String:
	return OW.loc_ground(biome)

static func seed_for(run_seed: int, biome: String) -> int:
	return OW.zone_seed(run_seed, "mini_" + biome)

## t20 (25.11): флейвор-данные хода (текст/палитра — closed RAMPS имена).
## Живут в data-слое: читают их inner-классы mini_zone (их скоуп внешние
## const своего файла не видит) и world.
const HOLE_HINT := {
	"forest": "Ход вниз (корни)", "steppe": "Ход вниз (полынь)",
	"desert": "Ход вниз (пески)", "snow": "Ход вниз (снег)",
	"castle": "Ход вниз (обвал)", "dungeon": "Ход вниз (пролом)",
}
const HOLE_RIM := {
	"forest": "BARK", "steppe": "STONE_WARM", "desert": "PATH",
	"snow": "CRYSTAL", "castle": "IRON", "dungeon": "BONE",
}

static func hole_hint(b: String) -> String:
	return String(HOLE_HINT.get(b, "Ход вниз (открытая рана)"))

static func hole_rim(b: String) -> String:
	return String(HOLE_RIM.get(b, "BARK"))

## Полная внутренняя карта: {width, height, grid: Array[String], meta}.
## meta: biome, spawn, chest, boss, centers (по порядку комнат), n_rooms, seed.
static func generate(run_seed: int, biome: String) -> Dictionary:
	var zs := seed_for(run_seed, biome)
	var fl := floor_ch(biome)
	var grid: Array = []
	for y in H:
		var row := ""
		for x in W:
			row += "#"
		grid.append(row)
	# комната 0 — входная (низ, центр карты): spawn = середина, тут же «выход
	# тем же интерактором». Верхние комнаты — цепочка к финальной.
	var n_rooms: int = 3 + (zs % 2)  # 3..4 (входная + средние + финальная)
	var rects: Array = []
	rects.append(Rect2i(14, 16, 12, 5))
	# средние: y-центр 11, фикс. высота 6 => ряды 8..14 (от входной отделены);
	# первая — джиттер по X, вторая (если есть) — с противоположного края.
	var cx1: int = 6 + int(OW.nz(zs, 103, 7) * 10.0)          # 6..15
	var cx2: int = W - 7 - int(OW.nz(zs, 104, 7) * 10.0)      # 18..27
	var mids: Array = []
	mids.append(Rect2i(cx1, 8, 10, 6))
	if n_rooms >= 4:
		mids.append(Rect2i(cx2, 8, 10, 6))
	# финальная (босс) — верхний ярус, центр X джиттерит; отделена от средних
	# (ряды 2..7 против 8..14).
	var bx: int = 6 + int(OW.nz(zs, 105, 9) * (float(W) - 20.0))  # 6..25
	var top_room := Rect2i(bx, 2, 14, 6)
	# порядок обхода: вход -> средние -> финальная
	for r in mids:
		rects.append(r)
	rects.append(top_room)
	for r in rects:
		_carve_rect(grid, r, fl)
	for i in range(1, rects.size()):
		_carve_l(grid, _center(rects[i - 1]), _center(rects[i]), fl)
	var spawn: Vector2i = _center(rects[0])
	# «Дальняя комната» — ОПРЕДЕЛЕНИЕ, а не надежда на макет: BFS от спавна,
	# босс — центр комнаты-рекордсмена (связный остаток цепочки). Сундук —
	# ближайшая из прочих не-входных комнат (иначе два якоря слипались бы
	# на длинных обходах). Детерминировано: порядок обхода фиксирован,
	# ties — первым встретившимся.
	var dist := bfs(grid, spawn, fl)
	var ds: Array = []
	for i in range(1, rects.size()):
		var c := _center(rects[i])
		ds.append(int(dist.get("%d,%d" % [c.x, c.y], -1)))
	var boss_i := 0
	var chest_i := -1
	for i in range(ds.size()):
		if int(ds[i]) > int(ds[boss_i]):
			boss_i = i
	for i in range(ds.size()):
		if i == boss_i or int(ds[i]) < 0:
			continue
		if chest_i < 0 or int(ds[i]) < int(ds[chest_i]):
			chest_i = i
	if chest_i < 0:
		chest_i = (boss_i + 1) % ds.size()
	var boss_room: Rect2i = rects[1 + boss_i]
	var chest_room: Rect2i = rects[1 + chest_i]
	var chest: Vector2i = _center(chest_room)
	var boss: Vector2i = _center(boss_room)
	var centers: Array = []
	for r in rects:
		centers.append(_center(r))
	return {
		"width": W, "height": H, "grid": grid,
		"meta": {
			"biome": biome, "seed": zs, "n_rooms": n_rooms,
			"spawn": [spawn.x, spawn.y], "chest": [chest.x, chest.y],
			"boss": [boss.x, boss.y], "centers": centers,
		},
	}

## Клетка «хода» внутри локации: лесной пол 'f', примыкает к массе/скале
## ('#'|'M') — нора в гуще, не посреди поляны; вдали от входа/сундука/портала.
## Детерминизм — argmax shash("minihole:x,y") по кандидатам (скан y-x —
## стабильный порядок при редком совпадении хэша). Пусто — (-1,-1), зона
## просто не ставит ход (стенд ловит).
static func pick_hole(rows: Array, spawn: Vector2i, chest: Vector2i,
		portal: Vector2i, biome: String) -> Vector2i:
	var fl := floor_ch(biome)
	var best := Vector2i(-1, -1)
	var best_h := -1
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if String(row[x]) != fl:
				continue
			var c := Vector2i(x, y)
			if OW.cheb(c, spawn) < 9 or OW.cheb(c, portal) < 9 or OW.cheb(c, chest) < 7:
				continue
			var touches := false
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n: Vector2i = c + d
				if n.y >= 0 and n.y < rows.size():
					var ch := String(String(rows[n.y])[n.x])
					if ch == "#" or ch == "M":
						touches = true
						break
			if not touches:
				continue
			var hs := OW.shash("minihole:%d,%d" % [x, y])
			if hs > best_h:
				best_h = hs
				best = c
	return best

## 4-связный BFS от клетки по проходимым ('fl'-полу) — для пинов связности и
## «дальней комнаты». Ключ словаря "x,y", значения — дистанции в клетках.
static func bfs(rows: Array, from: Vector2i, fl: String) -> Dictionary:
	var dist := {"%d,%d" % [from.x, from.y]: 0}
	var q: Array = [from]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.y >= rows.size() or n.x >= String(rows[0]).length():
				continue
			if String(rows[n.y])[n.x] != fl:
				continue
			var k := "%d,%d" % [n.x, n.y]
			if dist.has(k):
				continue
			dist[k] = int(dist["%d,%d" % [c.x, c.y]]) + 1
			q.append(n)
	return dist

# --- резные примитивы ---------------------------------------------------------

static func _center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + int(r.size.x / 2), r.position.y + int(r.size.y / 2))

static func _carve_rect(grid: Array, r: Rect2i, fl: String) -> void:
	for y in range(maxi(1, r.position.y), mini(H - 1, r.position.y + r.size.y)):
		for x in range(maxi(1, r.position.x), mini(W - 1, r.position.x + r.size.x)):
			_carve(grid, x, y, fl)

static func _carve_l(grid: Array, a: Vector2i, b: Vector2i, fl: String) -> void:
	var x := a.x
	while x != b.x:
		_carve(grid, x, a.y, fl)
		x += 1 if x < b.x else -1
	_carve(grid, b.x, a.y, fl)
	var y := a.y
	while y != b.y:
		_carve(grid, b.x, y, fl)
		y += 1 if y < b.y else -1
	_carve(grid, b.x, b.y, fl)

static func _carve(grid: Array, x: int, y: int, ch: String) -> void:
	if x < 1 or y < 1 or x > W - 2 or y > H - 2:
		return
	var row := String(grid[y])
	grid[y] = row.substr(0, x) + ch + row.substr(x + 1)
