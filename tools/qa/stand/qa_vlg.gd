extends Node2D
## QA-стенд инвариантов перепланировки леса деревни (diff base 17ff31e).
## Прогон: godot --headless res://qa_vlg.tscn
## Проверяет прямо по res://data/map_village.json (без сборки мира) контракт
## «кластеры леса»:
##  1. spawn/npcs/herbs/chests/slimes — пин-координаты (сакральные, как пин-сид
##     у qa_z1: числа, не самогенерат).
##  2. Строки grid 0..14 — пин-дамп ручной деревни; фикс. клетки леса
##     (тропа d x22 rows15..18, s(23,15), тропа d row20 x22..44, A(45,20)) —
##     пин; алфавит леса ⊆ {t,r,T,f,d,s,A}; пещера (40,17) проходима;
##     костёр (18,13)+r1 не блокирует.
##  3. Кластеры t/r (rows 15..26, cols 2..45): одиночных — 0; смешанных t+r — 0;
##     рощицы 3..6 деревьев; группы валунов 2..3; в каждом ряду проходимый
##     интервал между препятствиями (кластеры и физ. указатель 's', BLOCK_SHAPES
##     13 в world.gd) и до рамок col1/col46 — не меньше 2. Радиус 1 у herbs и
##     spawn проходим (соседи в несдвигаемой рамке карты col0/1/46/47 не
##     считаются: herb(45,12) у рамки замурован инвариантом 2).
##  4. BFS из spawn (блоки = w,t,W,R,D,#,r,s — зеркало world.gd BLOCKING):
##     достижимы все herbs, chests, стартовые slimes, A(45,20), пещера(40,17);
##     у каждой 's' есть достижимый проходимый сосед; карманов в лесу нет.
##  5. Объём блоков леса: пин t=59 r=26 (всего 85) и коридор ±20% от базы 71
##     (диапазон 57..85).

const PATH_MAP := "res://data/map_village.json"

const PIN_SPAWN := [8, 10]
const PIN_NPCS := [["elder", 10, 8], ["merchant", 22, 13], ["farmer", 29, 13]]
const PIN_HERBS := [[14, 19], [26, 20], [17, 24], [30, 24], [24, 17], [12, 17], [45, 12]]
const PIN_CHESTS := [[37, 21]]
const PIN_SLIMES := [[16, 21], [24, 22], [30, 19], [20, 25], [33, 22], [27, 24]]
const PIN_ROWS_0_14 := [
	"tttttttttttttttttttttttttttttttttttttttttttttttt",
	"tttttttttttttttttttttttttttttttttttttttttttttttt",
	"ttggggggggggggggggggggggggggggggggggggggggggggtt",
	"ttggggRRRRRRgggggfggggggggggggggggggfgggggggggtt",
	"ttggggRRRRRRggggfggggggggggggggggggfwwwwwwwwwgtt",
	"ttggggWWWWWWgggggggggggggggggfgggggrwwwwwwwwwgtt",
	"ttgggfWWDWWWggggggggggggfgggggggggggwwwwwwwwwgtt",
	"ttggggggdggfggggggggggggggggggfgggggwwwwwwwwwgtt",
	"ttggggggdggggggggggggggggggfgggggggrwwwwwwwwwgtt",
	"ttggggggdggggfggggggggggggggggggfgggwwwwwwwwwgtt",
	"ttggggggdggggggfggggggggggggggggggfgggggggggggtt",
	"ttggggggdgsggggggggfggggggggggggggggggfgggggggtt",
	"ttggdddddddddddddddddddddddddddddddddddddddddgtt",
	"ttggggggggggggggggggggdgggggggggggggggggggggggtt",
	"ttggggggggggggggggggggdgggggggggggggggggggggggtt",
]
# фикс. клетки внутри лесных строк (x,y,ch)
const PIN_FIXED_CELLS := [
	[22, 15, "d"], [23, 15, "s"], [22, 16, "d"], [22, 17, "d"], [22, 18, "d"],
	[22, 20, "d"], [45, 20, "A"],
]
const PIN_ROW20_D_RUN := [22, 44]        # row20: d на x=22..44 включительно
const PIN_BASE_BLOCK := 71               # t+r в лесу (interior) до перепланировки
const PIN_T := 59
const PIN_R := 26
const FOREST_ROWS := [15, 26]
const FOREST_COLS := [2, 45]
const BLOCK_CHARS := "tWrWDR#s"
const FOREST_ALPHABET := "trTfdsA"

var pass_n := 0
var fail_n := 0
var grid: Array = []
var W := 0
var H := 0
var spawn := []
var herbs := []
var chests := []
var slimes := []

func chk(cond: bool, name: String) -> void:
	if cond:
		pass_n += 1
		print("qa_vlg ok: ", name)
	else:
		fail_n += 1
		print("qa_vlg FAIL: ", name)

func _ready() -> void:
	var f := FileAccess.open(PATH_MAP, FileAccess.READ)
	if f == null:
		print("qa_vlg FAIL: не открыт ", PATH_MAP)
		print("QA_VLG 0/1")
		get_tree().quit(1)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		print("qa_vlg FAIL: JSON не читается")
		print("QA_VLG 0/1")
		get_tree().quit(1)
		return
	W = int(data.get("width", 0))
	H = int(data.get("height", 0))
	grid = data.get("grid", [])
	spawn = _ints(data.get("spawn", []))
	herbs = _arrs(data.get("herbs", []))
	chests = _arrs(data.get("chests", []))
	slimes = _arrs(data.get("slimes", []))
	var npcs_raw: Array = []
	for n in data.get("npcs", []):
		npcs_raw.append([String(n[0]), int(n[1]), int(n[2])])
	chk(W == 48 and H == 30 and grid.size() == H, "карта 48x30")
	var rows_ok := true
	for r in grid:
		if String(r).length() != W:
			rows_ok = false
	chk(rows_ok, "все строки по 48")
	if not (W == 48 and H == 30 and grid.size() == H):
		print("QA_VLG %d/%d" % [pass_n, pass_n + fail_n])
		get_tree().quit(1)
		return
	_inv1(npcs_raw)
	_inv2()
	_inv3()
	_inv4()
	_inv5()
	var total: int = pass_n + fail_n
	print("QA_VLG %d/%d" % [pass_n, total])
	get_tree().quit(0 if fail_n == 0 else 1)

func _ints(a: Array) -> Array:
	var o := []
	for v in a:
		o.append(int(v))
	return o

func _arrs(a: Array) -> Array:
	var o := []
	for p in a:
		o.append([int(p[0]), int(p[1])])
	return o

func _ch(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= W or y >= H:
		return "#"
	return String(grid[y])[x]

func _blocked(x: int, y: int) -> bool:
	return BLOCK_CHARS.find(_ch(x, y)) >= 0

# ---------------------------------------------------------------- инв. 1
func _inv1(npcs_raw: Array) -> void:
	chk(spawn == PIN_SPAWN, "inv1: spawn %s" % str(PIN_SPAWN))
	chk(npcs_raw == PIN_NPCS, "inv1: npcs пин (3 шт)")
	chk(herbs == PIN_HERBS, "inv1: herbs пин (7 шт)")
	chk(chests == PIN_CHESTS, "inv1: chests пин (37,21)")
	chk(slimes == PIN_SLIMES, "inv1: slimes пин (6 шт)")

# ---------------------------------------------------------------- инв. 2
func _inv2() -> void:
	var rows_bad := 0
	for y in 15:
		if String(grid[y]) != String(PIN_ROWS_0_14[y]):
			rows_bad += 1
			print("   row %d рассинхрон с пином" % y)
	chk(rows_bad == 0, "inv2: строки 0..14 = пин-дамп деревни")
	var alpha_bad := 0
	for y in range(FOREST_ROWS[0], FOREST_ROWS[1] + 1):
		for x in range(FOREST_COLS[0], FOREST_COLS[1] + 1):
			if FOREST_ALPHABET.find(_ch(x, y)) < 0:
				alpha_bad += 1
	chk(alpha_bad == 0, "inv2: алфавит леса ⊆ t,r,T,f,d,s,A")
	var fix_bad := 0
	for c in PIN_FIXED_CELLS:
		if _ch(c[0], c[1]) != String(c[2]):
			fix_bad += 1
			print("   (%d,%d)='%s' != '%s'" % [c[0], c[1], _ch(c[0], c[1]), c[2]])
	for x in range(PIN_ROW20_D_RUN[0], PIN_ROW20_D_RUN[1] + 1):
		if _ch(x, 20) != "d":
			fix_bad += 1
	chk(fix_bad == 0, "inv2: фикс. клетки леса целы (тропы d, s(23,15), A(45,20), row20 d 22..44)")
	chk(not _blocked(40, 17), "inv2: пещера (40,17) проходима")
	var fire_bad := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _blocked(18 + dx, 13 + dy):
				fire_bad += 1
	chk(fire_bad == 0, "inv2: костёр (18,13)+r1 не блокирует")

# ---------------------------------------------------------------- инв. 3
func _in_forest_block(x: int, y: int) -> bool:
	if y < FOREST_ROWS[0] or y > FOREST_ROWS[1] or x < FOREST_COLS[0] or x > FOREST_COLS[1]:
		return false
	var c := _ch(x, y)
	return c == "t" or c == "r"

func _inv3() -> void:
	var seen := {}
	var singles := 0
	var mixed := 0
	var tree_bad := ""
	var rock_bad := ""
	var n_tree := 0
	var n_rock := 0
	var total := 0
	for y in range(FOREST_ROWS[0], FOREST_ROWS[1] + 1):
		for x in range(FOREST_COLS[0], FOREST_COLS[1] + 1):
			if not _in_forest_block(x, y) or seen.has([x, y]):
				continue
			var cells := [[x, y]]
			seen[[x, y]] = true
			var q := [[x, y]]
			while not q.is_empty():
				var c: Array = q.pop_front()
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx: int = c[0] + d[0]
					var ny: int = c[1] + d[1]
					if _in_forest_block(nx, ny) and not seen.has([nx, ny]):
						seen[[nx, ny]] = true
						cells.append([nx, ny])
						q.append([nx, ny])
			total += 1
			var kinds := {}
			for c in cells:
				kinds[_ch(c[0], c[1])] = true
			if cells.size() == 1:
				singles += 1
				continue
			if kinds.size() > 1:
				mixed += 1
			elif kinds.has("t"):
				n_tree += 1
				if cells.size() < 3 or cells.size() > 6:
					tree_bad += "%d@%d,%d " % [cells.size(), x, y]
			else:
				n_rock += 1
				if cells.size() < 2 or cells.size() > 3:
					rock_bad += "%d@%d,%d " % [cells.size(), x, y]
	print("   кластеров=%d (рощ=%d валунов=%d) одиночных=%d смешанных=%d" % [total, n_tree, n_rock, singles, mixed])
	chk(singles == 0, "inv3: одиночных блокирующих — 0")
	chk(mixed == 0, "inv3: смешанных кластеров t+r — 0")
	chk(tree_bad == "", "inv3: все рощицы 3..6 деревьев" + (" [" + tree_bad + "]" if tree_bad != "" else ""))
	chk(rock_bad == "", "inv3: все группы валунов 2..3" + (" [" + rock_bad + "]" if rock_bad != "" else ""))
	# проходы: между препятствиями (кластер/указатель s) и рамками col1/col46 >= 2
	var gap_bad := 0
	for y in range(FOREST_ROWS[0], FOREST_ROWS[1] + 1):
		var runs := [[1, 1], [46, 46]]
		var x := FOREST_COLS[0]
		while x <= FOREST_COLS[1]:
			var c := _ch(x, y)
			if c == "t" or c == "r":
				var x2 := x
				while x2 + 1 <= FOREST_COLS[1] and (_ch(x2 + 1, y) == "t" or _ch(x2 + 1, y) == "r"):
					x2 += 1
				runs.append([x, x2])
				x = x2 + 1
			elif c == "s":
				runs.append([x, x])
				x += 1
			else:
				x += 1
		runs.sort_custom(func(a, b): return a[0] < b[0])
		for i in range(1, runs.size()):
			if runs[i][0] - runs[i - 1][1] - 1 < 2:
				gap_bad += 1
				print("   row %d: зазор %d у x=%d..%d" % [y, runs[i][0] - runs[i - 1][1] - 1, runs[i - 1][1], runs[i][0]])
	chk(gap_bad == 0, "inv3: проходы между кластерами >= 2 в каждом лесном ряду")
	# r1 у herbs/spawn (рамка карты не считается)
	var clr_bad := 0
	for p in herbs + [spawn]:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx: int = p[0] + dx
				if nx <= 1 or nx >= 46:
					continue
				if _blocked(nx, p[1] + dy):
					clr_bad += 1
					print("   r1 (%d,%d) блокирует (%d,%d)='%s'" % [p[0], p[1], nx, p[1] + dy, _ch(nx, p[1] + dy)])
	chk(clr_bad == 0, "inv3: радиус 1 у herbs+spawn проходим")

# ---------------------------------------------------------------- инв. 4
func _inv4() -> void:
	var reach := []
	for y in H:
		reach.append([])
		for x in W:
			reach[y].append(false)
	var miss := []
	if _blocked(spawn[0], spawn[1]):
		chk(false, "inv4: spawn на блокирующей клетке")
	else:
		reach[spawn[1]][spawn[0]] = true
		var q := [[spawn[0], spawn[1]]]
		while not q.is_empty():
			var c: Array = q.pop_front()
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = c[0] + d[0]
				var ny: int = c[1] + d[1]
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				if reach[ny][nx] or _blocked(nx, ny):
					continue
				reach[ny][nx] = true
				q.append([nx, ny])
		for p in herbs:
			if not reach[p[1]][p[0]]:
				miss.append("herb(%d,%d)" % [p[0], p[1]])
		for p in chests:
			if not reach[p[1]][p[0]]:
				miss.append("chest(%d,%d)" % [p[0], p[1]])
		for p in slimes:
			if not reach[p[1]][p[0]]:
				miss.append("slime(%d,%d)" % [p[0], p[1]])
		if not reach[20][45]:
			miss.append("A(45,20)")
		if not reach[17][40]:
			miss.append("cave(40,17)")
	chk(miss.is_empty(), "inv4: BFS из spawn — %d целей достижимы%s" % [herbs.size() + chests.size() + slimes.size() + 2, (" ПРОПУЩЕНО: " + str(miss)) if not miss.is_empty() else ""])
	# у указателей s есть достижимый сосед
	var s_bad := 0
	for y in H:
		for x in W:
			if _ch(x, y) != "s":
				continue
			var adj := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and ny >= 0 and nx < W and ny < H and not _blocked(nx, ny) and reach[ny][nx]:
						adj = true
			if not adj:
				s_bad += 1
	chk(s_bad == 0, "inv4: у всех указателей s достижимый сосед есть")
	# карманы в лесу
	var pockets := 0
	for y in range(FOREST_ROWS[0], FOREST_ROWS[1] + 1):
		for x in range(FOREST_COLS[0], FOREST_COLS[1] + 1):
			if not _blocked(x, y) and not reach[y][x]:
				pockets += 1
				if pockets <= 5:
					print("   карман (%d,%d)='%s'" % [x, y, _ch(x, y)])
	chk(pockets == 0, "inv4: карманов в лесу нет")

# ---------------------------------------------------------------- инв. 5
func _inv5() -> void:
	var t := 0
	var r := 0
	for y in range(FOREST_ROWS[0], FOREST_ROWS[1] + 1):
		for x in range(FOREST_COLS[0], FOREST_COLS[1] + 1):
			var c := _ch(x, y)
			if c == "t":
				t += 1
			elif c == "r":
				r += 1
	var all := t + r
	var lo := int(ceil(PIN_BASE_BLOCK * 0.8))
	var hi := int(floor(PIN_BASE_BLOCK * 1.2))
	chk(t == PIN_T, "inv5: деревьев в лесу %d = пин %d" % [t, PIN_T])
	chk(r == PIN_R, "inv5: валунов в лесу %d = пин %d" % [r, PIN_R])
	chk(all >= lo and all <= hi, "inv5: блоков %d в ±20%% от базы %d (%d..%d)" % [all, PIN_BASE_BLOCK, lo, hi])
