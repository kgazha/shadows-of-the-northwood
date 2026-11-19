class_name OpenWorld
extends RefCounted
## «Мир v1» (t3, волна «Мир v1»): детерминированный генератор открытого мира
## за северной аркой деревни — карта мира 96×60 и шесть локаций-входов
## (снег/пустыня/степь/лес/замок/подземелье) на фиксированных дистанциях.
##
## Канон:
##  • сид — явно от run_seed: ProcGen.mixi(run_seed, shash(zone_id), wave);
##    системный хэш строки hash() в новых файлах ЗАПРЕЩЁН (аудит w2 F3) —
##    только shash();
##  • сложность — поясами от ворот кольца: belt = Chebyshev(cell, ворота)/14,
##    множитель HP/урона = 1 + 0,25·belt, золота = 1 + 0,15·belt
##    (строки 21–24 реестра BALANCE.md);
##  • проходы в глухой массе >= 2 клетки — геометрия кластеров (g24a),
##    проверка cluster_holes() перенесена из world_paint (утверждённый лист);
##  • пины золотые: composition-хеш канонической сериализации сетки (FNV-1a 64).
##
## Сетка (алфавит): '#' скала-стена (блок), '.' степь, 's' снег, 'f' лес,
## 'd' пустыня, 'c' замок, 'u' подземелье, '-' дорога, 'p' портал (проходн.),
## 'a' арка (проходн.), 'M'/'W'/'C' глухая масса (блок),
## deco (проходные): 'i' ледяной шип, 'S' кости/череп, 'b' знамёна, 'r' хлам,
## 't' ковыль, 'n' папоротник, 'g' гриб-свет.

# ============================================================================
# Этажи зон: y-смещение Node2D-контейнера. Шкала z = fposmod(Y, 4800) циклична,
# поэтому этажи — кратные 4800 (деревня 0, пещера 4800, пепелище 9600).
# ============================================================================
const WM_OFFSET_Y := 14400
const LOC_OFFSET_Y := {
	"snow": 19200, "desert": 24000, "steppe": 28800,
	"forest": 33600, "castle": 38400, "dungeon": 43200,
}
const ZONES := ["snow", "desert", "steppe", "forest", "castle", "dungeon"]
const ZONE_NAMES := {
	"snow": "Снежник", "desert": "Пустошь", "steppe": "Степь",
	"forest": "Чаща", "castle": "Замок", "dungeon": "Подземелье",
}

# ============================================================================
# Карта мира
# ============================================================================
const WM_W := 96
const WM_H := 60
const WM_GATE_X := 47                 # коридор ворот x=47..48 сквозь кольцо
const WM_ANCHOR := Vector2i(47, 58)   # пояс считается от середины ворот
const WM_SPAWN := Vector2i(47, 56)    # прибытие из деревни (за северной аркой)
const WM_ARCH_CELL := Vector2i(48, 58)  # интерактор возвращения в деревню
const PORTAL_CELLS := {
	"forest": Vector2i(20, 44),
	"steppe": Vector2i(62, 46),
	"dungeon": Vector2i(12, 32),
	"castle": Vector2i(78, 18),
	"snow": Vector2i(52, 8),
	"desert": Vector2i(84, 36),
}
## Поля биомов карты мира (эллипсы с шумовой кромкой), порядок наложения фикс.
const FIELDS := [
	{"ch": "s", "cx": 48, "cy": 12, "rx": 17, "ry": 11},
	{"ch": "c", "cx": 78, "cy": 16, "rx": 11, "ry": 8},
	{"ch": "d", "cx": 76, "cy": 40, "rx": 15, "ry": 10},
	{"ch": "u", "cx": 14, "cy": 34, "rx": 11, "ry": 8},
	{"ch": "f", "cx": 24, "cy": 28, "rx": 11, "ry": 8},
]
## Сколько кластерных масс ставится в каждое поле карты мира + шаг поиска.
const FIELD_CLUSTERS := {"s": 4, "d": 4, "c": 3, "u": 3, "f": 4, ".": 3}

# ============================================================================
# Пояса сложности (BALANCE.md строки 21–24)
# ============================================================================
const BELT_TILES := 14
const BELT_STEP := 0.25
const GOLD_BELT_STEP := 0.15

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func belt_of_cell(c: Vector2i) -> int:
	return cheb(c, WM_ANCHOR) / BELT_TILES

static func belt_mult(b: int) -> float:
	return 1.0 + BELT_STEP * float(b)

static func gold_mult(b: int) -> float:
	return 1.0 + GOLD_BELT_STEP * float(b)

static func portal_belt(zone: String) -> int:
	return belt_of_cell(PORTAL_CELLS[zone])

## Пояс мобов локации — по её порталу на карте мира (фикс. дистанция).
static func zone_belt(zone: String) -> int:
	return portal_belt(zone)

static func brute_tier(belt: int) -> int:
	return 3 if belt >= 3 else (2 if belt == 2 else 1)

# ============================================================================
# Бестиарий локаций (семейства существующие; сложность — ТОЛЬКО множителем
# HP/урона/золота, скорость/ИИ не трогаем — контракт t3)
# ============================================================================
const BESTIARY := {
	"snow": [["slime", 4], ["brute", 2]],
	"desert": [["swarmling", 5], ["brute", 2]],
	"steppe": [["slime", 3], ["brute", 2], ["archer", 1]],
	"forest": [["slime", 2], ["swarmling", 3], ["brute", 1]],
	"castle": [["brute", 3], ["archer", 2]],
	"dungeon": [["wraith", 2], ["brute", 2], ["slime", 2]],
}

# ============================================================================
# Хэш/шум (детерминизм между платформами: целые int64-операции ProcGen.mixi)
# ============================================================================
## FNV-1a 32 по UTF-8 (тот же алгоритм, что в world_paint.shash — аудит F3;
## двойной пин сверяется в qa_world).
static func shash(s: String) -> int:
	var h := 2166136261
	for b in s.to_utf8_buffer():
		h = int(h ^ b)
		h = (h * 16777619) & 0xFFFFFFFF
	return h

static func zone_seed(run_seed: int, zone_id: String) -> int:
	return ProcGen.mixi(run_seed, shash(zone_id), 1)

static func nz(seed_: int, x: int, y: int) -> float:
	return float(ProcGen.mixi(seed_, x, y)) / 4294967296.0

## Каноническая сериализация: dict — ключи по sorted(), float — 6 знаков.
static func canon(value) -> String:
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		var parts: Array = []
		for k in keys:
			parts.append("%s:%s" % [canon(k), canon(value[k])])
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts2: Array = []
		for v in value:
			parts2.append(canon(v))
		return "[" + ",".join(parts2) + "]"
	if value is float:
		return "%.6f" % value
	if value is String:
		return "\"" + (value as String).replace("\\", "\\\\").replace("\"", "\\\"") + "\""
	return str(value)

## FNV-1a 64 (знаковый int64, обёртка совпадает с эталоном qa_pg).
static func fnv64(s: String) -> int:
	var h := -3750763034362895579
	for b in s.to_utf8_buffer():
		h = int(h ^ b)
		h = h * 1099511628211
	return h

static func hash_map(m: Dictionary) -> int:
	return fnv64(canon(m))

# ============================================================================
# Геометрия
# ============================================================================
const SOLID := ["#", "M", "W", "C"]

static func ch_at(grid: Array, x: int, y: int) -> String:
	if y < 0 or x < 0 or y >= grid.size():
		return "#"
	var row := String(grid[y])
	if x >= row.length():
		return "#"
	return row[x]

static func walkable(grid: Array, x: int, y: int) -> bool:
	return not SOLID.has(ch_at(grid, x, y))

## Слияние глухих клеток в прямоугольники-коллайдеры (приём деревни: 825
## СЛИТЫХ полос вместо клетки-на-клетку). Жадно: вниз до упора, затем вправо
## на всю высоту. Детерминированно, O(cells·H). Возвращает Array[Vector4i]
## (x, y, w, h) в клетках.
static func solid_rects(grid: Array) -> Array:
	var out: Array = []
	var h := grid.size()
	if h == 0:
		return out
	var w := String(grid[0]).length()
	var covered := {}
	for y in h:
		var row := String(grid[y])
		for x in w:
			if covered.has("%d,%d" % [x, y]):
				continue
			if not SOLID.has(row[x]):
				continue
			var hh := 0
			while y + hh < h:
				var r2 := String(grid[y + hh])
				if x >= r2.length() or not SOLID.has(r2[x]) or covered.has("%d,%d" % [x, y + hh]):
					break
				hh += 1
			var ww := 1
			while x + ww < w:
				var ok := true
				for dy in hh:
					var r3 := String(grid[y + dy])
					if x + ww >= r3.length() or not SOLID.has(r3[x + ww]) \
							or covered.has("%d,%d" % [x + ww, y + dy]):
						ok = false
						break
				if not ok:
					break
				ww += 1
			for dy in hh:
				for dx in ww:
					covered["%d,%d" % [x + dx, y + dy]] = true
			out.append(Vector4i(x, y, ww, hh))
	return out

## Перенос проверки из world_paint.cluster_holes (утверждённая геометрия):
## единичный ЗАМКНУТЫЙ проход между массами = нарушение «коридор >= 2».
static func cluster_holes(grid: Array) -> Array:
	var out: Array = []
	var solid := func(x: int, y: int) -> bool:
		if y < 0 or x < 0 or y >= grid.size():
			return false
		var row := String(grid[y])
		if x >= row.length():
			return false
		return SOLID.has(row[x])
	var free := func(x: int, y: int) -> bool:
		return not solid.call(x, y)
	for cy in grid.size():
		var cols := String(grid[cy]).length()
		var cx := 0
		while cx < cols:
			if free.call(cx, cy) and solid.call(cx - 1, cy):
				var run := 0
				var x2 := cx
				while x2 < cols and free.call(x2, cy):
					run += 1
					x2 += 1
				if run == 1 and solid.call(x2, cy):
					out.append([cx, cy, "H"])
				cx = x2
			else:
				cx += 1
	for cx in String(grid[0]).length():
		var cy := 0
		while cy < grid.size():
			if free.call(cx, cy) and solid.call(cx, cy - 1):
				var run := 0
				var y2 := cy
				while y2 < grid.size() and free.call(cx, y2):
					run += 1
					y2 += 1
				if run == 1 and solid.call(cx, y2):
					out.append([cx, cy, "V"])
				cy = y2
			else:
				cy += 1
	return out

## BFS-связность от spawn по проходным клеткам (4-связность).
static func reachable(grid: Array, spawn: Vector2i) -> Dictionary:
	var seen := {}
	var q: Array[Vector2i] = [spawn]
	seen[spawn] = true
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			var k := "%d,%d" % [n.x, n.y]
			if seen.has(k) or not walkable(grid, n.x, n.y):
				continue
			seen[k] = true
			q.append(n)
	return seen

# ============================================================================
# Кластеры масс (глухая масса + проходной декор; геометрия из утверждённого
# листа 17.11 для снега/пустыни/замка, своя — для степи/леса/подземелья;
# все проверены cluster_holes в стенде qa_world)
# ============================================================================
const CLUSTER_SNOW := [
	"..i.........MMM....i..",
	".i..........MMM.......",
	".........MMMMMMM...i..",
	"..i.....MMMMMMMMM.....",
	"......................",
	"...i.........i........",
	"..........MMM.........",
	".........MMMMM....i...",
	"..i.....MMMMMMM.......",
	"......................",
]
const CLUSTER_DESERT := [
	"..S.......MMM......C..",
	"..........MMM....C....",
	"......MMMMMMMMM...C...",
	"......MMMMMMMMM.......",
	"...................S..",
	"..C...................",
	"........C.............",
	".....MM....CCC........",
	".....MM...CCCCC.......",
	"..................S...",
]
const CLUSTER_CASTLE := [
	"....WWWWWWWW....b....r",
	"....WWWWWWWW..........",
	"......................",
	"......................",
	"..r....WW....WW.....r.",
	".......WW....WW.......",
	"......................",
	"..b.......W........b..",
	"......................",
	"......................",
]
const CLUSTER_STEPPE := [
	"......................",
	"..MM............MMt...",
	"..MMt..........MMM....",
	"...t....MMM...........",
	"........MMM....t......",
	"...tt...MMM...........",
	"......................",
	"..MMt......ttt........",
	"..MM..................",
	"......................",
]
const CLUSTER_FOREST := [
	"..n.....MMM......n....",
	"........MMM.........n.",
	"...n..MMMMMMM.........",
	"......MMMMMMM...n.....",
	"..n.................n.",
	".....MMM..............",
	"...n.MMM.....MMM......",
	".....MMM.....MMM..n...",
	"......................",
	"......................",
]
const CLUSTER_DUNGEON := [
	"..g....WW..WW....g....",
	"........WW..WW........",
	"......................",
	"....WW..........WW..g.",
	"....WW..........WW....",
	"......................",
	"..g......WWWW.........",
	".........WWWW....g....",
	"......................",
	"......................",
]
const CLUSTERS := {
	"s": CLUSTER_SNOW, "d": CLUSTER_DESERT, "c": CLUSTER_CASTLE,
	".": CLUSTER_STEPPE, "f": CLUSTER_FOREST, "u": CLUSTER_DUNGEON,
}

# ============================================================================
# Карта мира
# ============================================================================
static func worldmap_map(run_seed: int) -> Dictionary:
	var zs := zone_seed(run_seed, "worldmap")
	var grid: Array = []
	for y in WM_H:
		var row := ""
		for x in WM_W:
			var d := mini(mini(x, WM_W - 1 - x), mini(y, WM_H - 1 - y))
			row += "#" if d == 0 else "."
		grid.append(row)
	# поля биомов: эллипс с шумовой кромкой (±1.5 клетки)
	for fd in FIELDS:
		for y in range(1, WM_H - 1):
			for x in range(1, WM_W - 1):
				var jx := (nz(zs, x * 3 + 1, y * 3 + 7) - 0.5) * 3.0
				var jy := (nz(zs, x * 3 + 11, y * 3 + 23) - 0.5) * 3.0
				var nx := (float(x + int(round(jx))) - float(fd["cx"])) / float(fd["rx"])
				var ny := (float(y + int(round(jy))) - float(fd["cy"])) / float(fd["ry"])
				if nx * nx + ny * ny <= 1.0:
					var row := String(grid[y])
					row[x] = String(fd["ch"])
					grid[y] = row
	# дороги: вертикальный ствол от ворот, поперечник, отроги к порталам
	var road_cells: Array = []
	for y in range(12, 58):
		road_cells.append([47, y])
	for x in range(16, 81):
		road_cells.append([x, 20])
	for x in range(12, 48):
		road_cells.append([x, 32])
	for x in range(20, 48):
		road_cells.append([x, 44])
	for x in range(48, 63):
		road_cells.append([x, 46])
	for x in range(48, 85):
		road_cells.append([x, 36])
	for x in range(48, 79):
		road_cells.append([x, 20])
	for y in range(8, 13):
		road_cells.append([52, y])
	for x in range(48, 53):
		road_cells.append([x, 12])
	for y in range(18, 21):
		road_cells.append([78, y])
	for rc in road_cells:
		var x: int = rc[0]
		var y: int = rc[1]
		if ch_at(grid, x, y) != "#":
			var row := String(grid[y])
			row[x] = "-"
			grid[y] = row
	# ворота кольца: сквозной вырез стены y=57..59 (x=47..48) — зеркало F5-листа
	for y in range(WM_H - 3, WM_H):
		for x in range(WM_GATE_X, WM_GATE_X + 2):
			var grow := String(grid[y])
			grow[x] = "-"
			grid[y] = grow
	# массы: в каждое поле — свои кластеры; вне дорог/порталов/арки, без
	# пересечений; кандидаты детерминированы nz.
	var reserved := {}
	for z in PORTAL_CELLS:
		var pc: Vector2i = PORTAL_CELLS[z]
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				reserved["%d,%d" % [pc.x + dx, pc.y + dy]] = true
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			reserved["%d,%d" % [WM_ARCH_CELL.x + dx, WM_ARCH_CELL.y + dy]] = true
			reserved["%d,%d" % [WM_SPAWN.x + dx, WM_SPAWN.y + dy]] = true
	var placed: Array = []
	var fi := 0
	for fd in ([{"ch": ".", "cx": 40, "cy": 48, "rx": 24, "ry": 9}] + FIELDS):
		var ch := String(fd["ch"])
		var cmap: Array = CLUSTERS[ch]
		var want: int = int(FIELD_CLUSTERS.get(ch, 3))
		var got := 0
		var tries := 0
		while got < want and tries < 24:
			tries += 1
			var fx := int(fd["cx"])
			var fy := int(fd["cy"])
			var rx := int(fd.get("rx", 14)) - 6
			var ry := int(fd.get("ry", 10)) - 6
			var ax := fx - rx + int(nz(zs, fi * 577 + tries * 31, 13) * float(2 * rx + 1))
			var ay := fy - ry + int(nz(zs, fi * 577 + tries * 31, 29) * float(2 * ry + 1))
			if _stamp_cluster(grid, cmap, ax, ay, reserved, road_cells, placed):
				got += 1
		fi += 1
	# маркеры портала/арки — поверх всего (клетки и так проходные)
	for z in PORTAL_CELLS:
		var pc: Vector2i = PORTAL_CELLS[z]
		var row := String(grid[pc.y])
		row[pc.x] = "p"
		grid[pc.y] = row
	var row2 := String(grid[WM_ARCH_CELL.y])
	row2[WM_ARCH_CELL.x] = "a"
	grid[WM_ARCH_CELL.y] = row2
	var gates: Array = []
	for y in range(WM_H - 3, WM_H):
		gates.append([WM_GATE_X, y])
		gates.append([WM_GATE_X + 1, y])
	var belts := {}
	for z in PORTAL_CELLS:
		belts[z] = portal_belt(z)
	return {
		"width": WM_W, "height": WM_H, "grid": grid,
		"meta": {
			"spawn": [WM_SPAWN.x, WM_SPAWN.y], "arch": [WM_ARCH_CELL.x, WM_ARCH_CELL.y],
			"gate": gates, "portals": _cells_dict(), "belts": belts,
		},
	}

static func _cells_dict() -> Dictionary:
	var out := {}
	for z in PORTAL_CELLS:
		var pc: Vector2i = PORTAL_CELLS[z]
		out[z] = [pc.x, pc.y]
	return out

static func _stamp_cluster(grid: Array, cmap: Array, ax: int, ay: int, reserved: Dictionary,
		road_cells: Array, placed: Array) -> bool:
	var rows := cmap.size()
	var cols := String(cmap[0]).length()
	if ax < 1 or ay < 1 or ax + cols > WM_W - 1 or ay + rows > WM_H - 2:
		return false
	var roads := {}
	for rc in road_cells:
		roads["%d,%d" % [rc[0], rc[1]]] = true
	for cy in rows:
		var row := String(cmap[cy])
		for cx in cols:
			var ch := String(row[cx])
			if ch == ".":
				continue
			var k := "%d,%d" % [ax + cx, ay + cy]
			if reserved.has(k) or roads.has(k):
				return false
			if ch_at(grid, ax + cx, ay + cy) == "#":
				return false
			if ch in SOLID:
				for p in placed:
					if absi(p[0] - (ax + cx)) <= 1 and absi(p[1] - (ay + cy)) <= 1:
						return false
	var snap := {}
	var added: Array = []
	for cy in rows:
		var row := String(cmap[cy])
		snap[ay + cy] = String(grid[ay + cy])
		var grow := String(grid[ay + cy])
		for cx in cols:
			var ch := String(row[cx])
			if ch == ".":
				continue
			grow[ax + cx] = ch
			if ch in SOLID:
				added.append([ax + cx, ay + cy])
		grid[ay + cy] = grow
	placed.append_array(added)
	# валидация геометрии: замкнутый проход длины 1 = откат кандидата (g24a)
	if cluster_holes(grid).size() > 0:
		for sy in snap:
			grid[int(sy)] = snap[sy]
		for p in added:
			placed.erase(p)
		return false
	return true

# ============================================================================
# Локация (44×34: экран 40×22.5 + запас; вход-арка с юга, выход-портал у входа)
# ============================================================================
const LOC_W := 44
const LOC_H := 34

static func loc_ground(zone: String) -> String:
	match zone:
		"snow": return "s"
		"desert": return "d"
		"castle": return "c"
		"dungeon": return "u"
		"forest": return "f"
		_: return "."

static func loc_map(run_seed: int, zone: String) -> Dictionary:
	var zs := zone_seed(run_seed, "loc_" + zone)
	var gch := loc_ground(zone)
	var grid: Array = []
	for y in LOC_H:
		var row := ""
		for x in LOC_W:
			var d := mini(mini(x, LOC_W - 1 - x), mini(y, LOC_H - 1 - y))
			row += "#" if d <= 1 else gch
		grid.append(row)
	# массы: 5 кластеров, кандидаты детерминированы; дороги считаются ДО масс
	# и входят в защитную полосу ±1 — дорога никогда не прорезает глухую массу
	# одиночным коридором (g24a), кластерная валидация ловит прочие дыры.
	var spawn := Vector2i(21, LOC_H - 4)
	var portal_out := Vector2i(22, LOC_H - 3)
	var cmap: Array = CLUSTERS[gch]
	var rows := cmap.size()
	var cols := String(cmap[0]).length()
	var far_cells := [[7, 7], [LOC_W - 8, 7], [7, LOC_H - 12], [LOC_W - 8, LOC_H - 12], [int(LOC_W / 2), 6]]
	var chest_cell: Array = far_cells[int(nz(zs, 101, 7) * float(far_cells.size())) % far_cells.size()]
	var road_cells: Array = []
	for y in range(6, LOC_H - 3):
		road_cells.append([21, y])
	var fx := 21
	while true:
		road_cells.append([fx, 6])
		if fx == chest_cell[0]:
			break
		fx += 1 if fx < chest_cell[0] else -1
	var fy := int(chest_cell[1])
	while fy >= 6:
		road_cells.append([chest_cell[0], fy])
		if fy == 6:
			break
		fy -= 1
	var blocked_zone := {}
	for dy in range(-5, 2):
		for dx in range(-4, 5):
			blocked_zone["%d,%d" % [spawn.x + dx, spawn.y + dy]] = true
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			blocked_zone["%d,%d" % [chest_cell[0] + dx, chest_cell[1] + dy]] = true
	for rc in road_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				blocked_zone["%d,%d" % [rc[0] + dx, rc[1] + dy]] = true
	var placed: Array = []
	var got := 0
	var tries := 0
	while got < 5 and tries < 60:
		tries += 1
		var ax := 4 + int(nz(zs, tries * 41, 17) * float(LOC_W - cols - 8))
		var ay := 4 + int(nz(zs, tries * 41, 53) * float(LOC_H - rows - 9))
		if _stamp_cluster_rect(grid, cmap, ax, ay, blocked_zone, placed, LOC_W, LOC_H):
			got += 1
	for rc in road_cells:
		_paint(grid, rc[0], rc[1], "-")
	# маркеры
	_paint(grid, portal_out.x, portal_out.y, "p")
	# мобы: дальние проходимые клетки,>=8 от входа, разнесены >=3
	var belt := zone_belt(zone)
	var mobs: Array = []
	var taken: Array = []
	for ent in BESTIARY[zone]:
		var kind := String(ent[0])
		var n := int(ent[1])
		var placed_n := 0
		var scan := 0
		while placed_n < n and scan < 400:
			var x := 3 + int(nz(zs, 300 + scan * 17 + kind.length() * 7, 11) * float(LOC_W - 6))
			var y := 3 + int(nz(zs, 700 + scan * 23 + kind.length() * 13, 37) * float(LOC_H - 8))
			scan += 1
			var k2 := "%d,%d" % [x, y]
			if blocked_zone.has(k2) or ch_at(grid, x, y) in SOLID or ch_at(grid, x, y) == "#":
				continue
			if cheb(Vector2i(x, y), spawn) < 8:
				continue
			var ok := true
			for t in taken:
				if cheb(Vector2i(x, y), Vector2i(t[0], t[1])) < 3:
					ok = false
					break
			if not ok:
				continue
			taken.append([x, y])
			mobs.append([kind, x, y])
			placed_n += 1
	return {
		"width": LOC_W, "height": LOC_H, "grid": grid,
		"meta": {
			"zone": zone, "belt": belt, "spawn": [spawn.x, spawn.y],
			"portal_out": [portal_out.x, portal_out.y],
			"chest": [chest_cell[0], chest_cell[1]],
			"chest_id": "chest@loc_" + zone, "mobs": mobs,
		},
	}

static func _paint(grid: Array, x: int, y: int, ch: String) -> void:
	if y < 0 or x < 0 or y >= grid.size():
		return
	var row := String(grid[y])
	if x < 0 or x >= row.length():
		return
	row[x] = ch
	grid[y] = row

static func _stamp_cluster_rect(grid: Array, cmap: Array, ax: int, ay: int,
		blocked: Dictionary, placed: Array, w: int, h: int) -> bool:
	var rows := cmap.size()
	var cols := String(cmap[0]).length()
	if ax < 2 or ay < 2 or ax + cols > w - 2 or ay + rows > h - 2:
		return false
	for cy in rows:
		var row := String(cmap[cy])
		for cx in cols:
			var ch := String(row[cx])
			if ch == ".":
				continue
			var k := "%d,%d" % [ax + cx, ay + cy]
			if blocked.has(k):
				return false
			if ch_at(grid, ax + cx, ay + cy) == "#":
				return false
			if ch in SOLID:
				for p in placed:
					if absi(p[0] - (ax + cx)) <= 1 and absi(p[1] - (ay + cy)) <= 1:
						return false
	var snap := {}
	var added: Array = []
	for cy in rows:
		var row := String(cmap[cy])
		snap[ay + cy] = String(grid[ay + cy])
		var grow := String(grid[ay + cy])
		for cx in cols:
			var ch := String(row[cx])
			if ch == ".":
				continue
			grow[ax + cx] = ch
			if ch in SOLID:
				added.append([ax + cx, ay + cy])
		grid[ay + cy] = grow
	placed.append_array(added)
	# валидация геометрии: замкнутый проход длины 1 = откат кандидата (g24a)
	if cluster_holes(grid).size() > 0:
		for sy in snap:
			grid[int(sy)] = snap[sy]
		for p in added:
			placed.erase(p)
		return false
	return true

## Итоговая карта мира + все локации одним снимком (для золотых пинов состава).
static func composition(run_seed: int) -> Dictionary:
	var out := {"worldmap": worldmap_map(run_seed)}
	for z in ZONES:
		out[z] = loc_map(run_seed, z)
	return out

## --- Скины биомов (t3 шаг 3; метод c22 — перекрас палитры, не тонировка) -----
## mobs_variants.json: {"skins": {"<биом>/<семейство>": {file, size, src}}}.
## Подмена: у каждого AtlasTexture в поддереве моба atlas меняется на вариант
## с ТЕМ ЖЕ region (раскладка листа-варианта совпадает с источником — это
## гарантирует tools_art/mob_variants_v1.gd режим check). Спрайты мобов
## построчные (per-instance SpriteFrames), обычные зоны не затрагиваются.
const VARIANTS_MANIFEST := "res://assets/world/mobs_variants.json"
const VARIANTS_DIR := "res://assets/world/"
static var _skins_by_src: Dictionary = {}     # биом -> {src_path: Texture2D}
static var _variant_cache: Dictionary = {}    # path -> Texture2D (null = нет файла)

static func _load_skins() -> void:
	if not _skins_by_src.is_empty() or not FileAccess.file_exists(VARIANTS_MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VARIANTS_MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for key in (parsed.get("skins", {}) as Dictionary):
		var e: Variant = (parsed["skins"] as Dictionary)[key]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var parts: PackedStringArray = String(key).split("/")
		if parts.size() != 2:
			continue
		var biome := String(parts[0])
		if not _skins_by_src.has(biome):
			_skins_by_src[biome] = {}
		(_skins_by_src[biome] as Dictionary)[String((e as Dictionary)["src"])] = \
			String(VARIANTS_DIR) + String((e as Dictionary)["file"])

## Покрасить моба (поддерево) в палитру биома. Тихий no-op без скина/листа.
static func apply_biome_skin(node: Node, biome: String) -> void:
	_load_skins()
	var by_src: Dictionary = _skins_by_src.get(biome, {})
	if by_src.is_empty():
		return
	_swap_rec(node, by_src)

static func _swap_rec(node: Node, by_src: Dictionary) -> void:
	if node is AnimatedSprite2D:
		var aspr := node as AnimatedSprite2D
		if aspr.sprite_frames != null:
			for anim_name in aspr.sprite_frames.get_animation_names():
				var n := aspr.sprite_frames.get_frame_count(String(anim_name))
				for i in n:
					var ft := aspr.sprite_frames.get_frame_texture(String(anim_name), i)
					var vt := _variant_atlas(ft, by_src)
					if vt != null:
						aspr.sprite_frames.set_frame(String(anim_name), i, vt)
	elif node is Sprite2D:
		var spr := node as Sprite2D
		var vt2 := _variant_atlas(spr.texture, by_src)
		if vt2 != null:
			spr.texture = vt2
	for c in node.get_children():
		_swap_rec(c, by_src)

## AtlasTexture -> вариант-AtlasTexture (region сохраняется); иначе null.
static func _variant_atlas(tex: Texture2D, by_src: Dictionary) -> AtlasTexture:
	var at := tex as AtlasTexture
	if at == null or at.atlas == null:
		return null
	var src_path := String(at.atlas.resource_path)
	if not by_src.has(src_path):
		return null
	var vpath := String(by_src[src_path])
	if not _variant_cache.has(vpath):
		_variant_cache[vpath] = load(vpath) if ResourceLoader.exists(vpath) else null
	var vtex: Texture2D = _variant_cache[vpath]
	if vtex == null:
		return null
	var nt := AtlasTexture.new()
	nt.atlas = vtex
	nt.region = at.region
	return nt
