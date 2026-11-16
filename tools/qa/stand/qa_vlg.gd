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
##  5. Объём блоков леса: пин t=59 r=26 (всего 85) и коридор ±20% от базы 85
##     (диапазон 68..102; база — принятая перепланировка d07c86a).
##  7. Стартовые тайлы мобов деревни проходимы и достижимы из spawn:
##     slimes[] (JSON, пин) + лучники world.gd [4,26],[44,26] + мглокрысы
##     glade_west world.gd [6,16],[9,16],[6,18],[10,18] — пин-факты из кода.
##  8. t33 (V-01/V-02/V-07) общая глубина + t54 (вердикт «внедряем»): qwen-слои
##     (VillageProps/GroveCanopy/Env4) сняты; деревню строит VillageV4 — кодоген-
##     атлас assets/village/village_v4.png (лист v4, bake); костёр-POI перекрашен
##     на v4-кадры fire/ash; изба — герой южнее стопы ПОВЕРХ, севернее ПОД; NPC
##     в динамической шкале. Порядок отрисовки — геометрия/коллайдеры не трогаются.
##  9. t41 дим-контракт мелких пропов на v4-пропах: реестр _ys_props_dim заполнен
##     только спрайтами кодоген-атласов (деревня v4 + c3 пещера v1); указатель при
##     накрытии >= 40% бокса героя
##     димится к 0.5±0.08, южнее стопы — ровно 1.0 (кроны не интегрированы —
##     _ys_canopies пуст).
## 10. c7 «микро-жизнь»: VillageSway (overlay-качание травы/цветов, 2 фазы,
##     фазы кластеров не синхронны, тайлмап не мутируется) и 3..6 светлячков
##     с проходным маршрутом и позицией — чистой функцией времени; у обоих
##     слоёв ноль коллайдеров.
## 11. c9 (вердикт «добавь»): куртины «G» — 8 пин-клеток (6..10) в пин-дампе
##     строк 0..14 и в items качания (каждая сменила кадр, фазы независимы);
##     мультисеты фаз A/L/R строгие (фикс F2 ревью c8: сдвиг на поле 18×16
##     с обрезкой, кромка не теряется).
## 12. 16.11 юзер-фикс «подвкладки в журнале» (76f389b): в разделе «Квесты» —
##     «Активные»/«Завершённые» со счётчиками на кнопках, журнал всегда открывается
##     на «Активных», ряд подвкладок только на квестах, пустые «Завершённые» —
##     заглушка. Живой мир main.tscn (game_world), поведение без md5.

const PATH_MAP := "res://data/map_village.json"

const PIN_SPAWN := [8, 10]
const PIN_NPCS := [["elder", 10, 8], ["merchant", 22, 13], ["farmer", 29, 13]]
const PIN_HERBS := [[14, 19], [26, 20], [17, 24], [30, 24], [24, 17], [12, 17], [45, 12]]
const PIN_CHESTS := [[37, 21]]
const PIN_SLIMES := [[16, 21], [24, 22], [30, 19], [20, 25], [33, 22], [27, 24]]
## c9 (вердикт «добавь»): травяные куртины «G» — пин-клетки (опушка луга:
## северная кромка x6/26/40 row2, у стены избы x12 и в лугу x33 row3,
## южная кромка над тропой x5/20/43 row13). Проходимы (CHAR_TO_TILE "G"=1),
## вне r1 herbs/spawn, не в лесных рядах.
const PIN_TUFTS := [[6, 2], [26, 2], [40, 2], [12, 3], [33, 3], [5, 13], [20, 13], [43, 13]]
const PAL := preload("res://scripts/pixel_palette.gd")
const PIN_ROWS_0_14 := [
	"tttttttttttttttttttttttttttttttttttttttttttttttt",
	"tttttttttttttttttttttttttttttttttttttttttttttttt",
  "ttggggGgggggggggggggggggggGgggggggggggggGgggggtt",
  "ttggggRRRRRRGggggfgggggggggggggggGggfgggggggggtt",
	"ttggggRRRRRRggggfggggggggggggggggggfwwwwwwwwwgtt",
	"ttggggWWWWWWgggggggggggggggggfgggggrwwwwwwwwwgtt",
	"ttgggfWWDWWWggggggggggggfgggggggggggwwwwwwwwwgtt",
	"ttggggggdggfggggggggggggggggggfgggggwwwwwwwwwgtt",
	"ttggggggdggggggggggggggggggfgggggggrwwwwwwwwwgtt",
	"ttggggggdggggfggggggggggggggggggfgggwwwwwwwwwgtt",
	"ttggggggdggggggfggggggggggggggggggfgggggggggggtt",
	"ttggggggdgsggggggggfggggggggggggggggggfgggggggtt",
	"ttggdddddddddddddddddddddddddddddddddddddddddgtt",
  "ttgggGggggggggggggggGgdggggggggggggggggggggGggtt",
	"ttggggggggggggggggggggdgggggggggggggggggggggggtt",
]
# фикс. клетки внутри лесных строк (x,y,ch)
const PIN_FIXED_CELLS := [
	[22, 15, "d"], [23, 15, "s"], [22, 16, "d"], [22, 17, "d"], [22, 18, "d"],
	[22, 20, "d"], [45, 20, "A"],
]
const PIN_ROW20_D_RUN := [22, 44]        # row20: d на x=22..44 включительно
const PIN_BASE_BLOCK := 85               # t+r в лесу (interior) — база d07c86a (принятая перепланировка)
const PIN_T := 59
const PIN_R := 26
# Стартовые тайлы мобов деревни (пин-факты): slimes — JSON; archers —
# world.gd:284; rat(мглокрысы glade_west) — world.gd:290. Тенеплёт (15,7)/
# (16,7) — карта пещеры, не сетка деревни (mb_1.gd: cave_tile_walkable).
const PIN_MOB_SPAWNS := [
	["slime1", 16, 21], ["slime2", 24, 22], ["slime3", 30, 19],
	["slime4", 20, 25], ["slime5", 33, 22], ["slime6", 27, 24],
	["archer1", 4, 26], ["archer2", 44, 26],
	["rat1", 6, 16], ["rat2", 9, 16], ["rat3", 6, 18], ["rat4", 10, 18],
]
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
var reach_map: Array = []

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
	_inv7()
	await _inv8()
	await _inv9()
	await _inv10()
	await _inv11()
	await _inv12()
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
	# c9: куртины «G» — пин-клетки ровно совпадают, других G в карте нет
	var tuft_bad := 0
	for c in PIN_TUFTS:
		if _ch(int(c[0]), int(c[1])) != "G":
			tuft_bad += 1
	var g_total := 0
	for y in H:
		for x in W:
			if _ch(x, y) == "G":
				g_total += 1
	chk(tuft_bad == 0 and g_total == PIN_TUFTS.size() and g_total >= 6 and g_total <= 10,
		"inv2: куртины «G» = пин (%d/%d), в диапазоне 6..10" % [PIN_TUFTS.size() - tuft_bad, g_total])
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
		reach_map = reach
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

# ---------------------------------------------------------------- инв. 8
const MAIN_SCENE := "res://scenes/main.tscn"
const SAVE_PATH := "user://save_morkheim.json"

var game_world: Node2D = null

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Мировой rect спрайта (независимая формула-зеркало: центральный якорь, без
## поворотов — пропы/кроны/NPC-картинки их не имеют).
func _spr_rect(sp: Sprite2D) -> Rect2:
	var tex := sp.texture
	var gt := sp.get_global_transform()
	var sz := Vector2(float(tex.get_width()), float(tex.get_height())) \
		* Vector2(absf(gt.x.x), absf(gt.y.y))
	return Rect2(gt * (Vector2(float(tex.get_width()), float(tex.get_height())) * -0.5 + sp.offset), sz)

func _biggest_sprite(layer: Node, tex_suffix: String) -> Sprite2D:
	if layer == null:
		return null
	var best: Sprite2D = null
	var ba := 0.0
	for c in layer.get_children():
		var spr := c as Sprite2D
		if spr == null or spr.texture == null or not spr.visible:
			continue
		if tex_suffix != "" and not String(spr.texture.resource_path).ends_with(tex_suffix):
			continue
		var a := _spr_rect(spr).get_area()
		if a > ba:
			ba = a
			best = spr
	return best

func _inv8() -> void:
	# Живой мир: глубина «актёры + пропсы» проверяется на реальной постройке.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	await _frames(2)
	GameState.run_seed = 42
	game_world = load(MAIN_SCENE).instantiate()
	add_child(game_world)
	await _frames(8)
	var w := game_world
	chk(w != null and w.player != null, "inv8: мир и герой построены")
	if w == null or w.player == null:
		return
	# 8.1 t52 снос (закон 13.11) + t54 вердикт «внедряем в игру»: qwen-пропы
	# VillageProps/GroveCanopy/Env4* в мире отсутствуют; деревню строит слой
	# VillageV4 — кодоген-атлас листа v4 (tools_art/sheet_village.gd, режим bake).
	var gc = w.village_zone.get_node_or_null("GroveCanopy")
	chk(w.get("village_props") == null and gc == null,
		"inv8: t52 снос — VillageProps и GroveCanopy сняты")
	var v4 = w.village_zone.get_node_or_null("VillageV4")
	var v4_spr: Array = []
	if v4 != null:
		for c in v4.get_children():
			var spr := c as Sprite2D
			if spr != null and spr.texture is AtlasTexture:
				v4_spr.append(spr)
	chk(v4 != null and v4_spr.size() >= 3,
		"inv8: t54 VillageV4 — слой со спрайтами атласа (%d)" % v4_spr.size())
	var v4_tex_ok := 0
	for e in v4_spr:
		var t: Texture2D = ((e as Sprite2D).texture as AtlasTexture).atlas
		if t != null and String(t.resource_path).ends_with("assets/village/village_v4.png"):
			v4_tex_ok += 1
	chk(not v4_spr.is_empty() and v4_tex_ok == v4_spr.size(),
		"inv8: VillageV4 — все спрайты из village_v4.png (ген-текстур нет)")
	var env4_any := false
	for zone: Node2D in [w.cave_zone, w.ashen_zone]:
		for lname: String in ["Env4CaveProps", "Env4AshenProps"]:
			if zone.get_node_or_null(NodePath(lname)) != null:
				env4_any = true
	chk(not env4_any, "inv8: t52 снос — env4-слои пропов сняты (пещера/Пепелище)")
	var fw := FileAccess.open("res://scripts/world.gd", FileAccess.READ)
	var wsrc: String = fw.get_as_text() if fw != null else ""
	if fw != null:
		fw.close()
	chk(wsrc.contains("_ys_canopies") and not wsrc.contains("_build_village_props") \
			and not wsrc.contains("_build_grove"),
		"inv8: world.gd — билдеры ген-пропов сняты, YS-инфраструктура цела")
	# 8.2 костёр — игровой POI (campfire.gd); t54: визуал перекрашен на v4-атлас
	var cfs: Array = w.get("campfires") if w.get("campfires") != null else []
	var cf_v4 := false
	if cfs.size() == 1:
		var anim = cfs[0].get("_anim")
		var fr: SpriteFrames = anim.sprite_frames if anim != null else null
		if fr != null and fr.has_animation("fire") and fr.has_animation("ash") \
				and fr.get_frame_count("fire") == 1 and fr.get_frame_count("ash") == 1:
			var t0 = fr.get_frame_texture("fire", 0)
			while t0 is AtlasTexture:
				t0 = (t0 as AtlasTexture).atlas
			cf_v4 = t0 != null and String(t0.resource_path).ends_with("village_v4.png")
	chk(cfs.size() == 1 and w.has_method("campfire_near") and cf_v4,
		"inv8: костёр-POI жив и перекрашен на v4-атлас fire/ash (%d шт.)" % cfs.size())
	# 8.3 NPC — в динамической шкале (стопа + биас, смещение ноги => смещение z)
	var npc: Node2D = null
	for e in get_tree().get_nodes_in_group("ys_actor"):
		if is_instance_valid(e) and (e as Node2D).get_parent() == w.village_zone:
			npc = e as Node2D
			break
	if npc == null:
		chk(false, "inv8: NPC не найден в группе глубины")
	else:
		var z1: int = npc.z_index
		npc.global_position = Vector2(npc.global_position.x, npc.global_position.y + 48.0)
		await _frames(4)
		chk(z1 > 0 and absf(float(npc.z_index - z1 - 48)) <= 1.0 \
			and absf(float(npc.z_index) - (npc.global_position.y + 10.0)) < 3.0,
			"inv8: NPC в динамической шкале глубины (%d -> %d)" % [z1, npc.z_index])
	# 8.4 t54 (V-01 на v4-избе): герой южнее стопы — ПОВЕРХ избы, севернее — ПОД.
	var hut: Sprite2D = null
	for e in v4_spr:
		if ((e as Sprite2D).texture as AtlasTexture).region.size == Vector2(35, 36):
			hut = e as Sprite2D
	if hut == null:
		chk(false, "inv8: изба v4 (35×36) не найдена в VillageV4")
	else:
		var pl: Node2D = w.player
		var keep := pl.global_position
		var hut_z := hut.z_index
		var foot := Vector2(hut.global_position.x, hut.global_position.y + 18.0)
		pl.global_position = Vector2(foot.x, foot.y + 10.0)
		await _frames(2)
		var z_s := pl.z_index
		pl.global_position = Vector2(foot.x, foot.y - 46.0)
		await _frames(2)
		var z_n := pl.z_index
		pl.global_position = keep
		chk(hut_z > 0 and z_s > hut_z and z_n < hut_z,
			"inv8: изба в шкале стоп: юг z %d>%d, север z %d<%d" % [z_s, hut_z, z_n, hut_z])

# ---------------------------------------------------------------- инв. 7
func _inv7() -> void:
	for m in PIN_MOB_SPAWNS:
		var nm: String = String(m[0])
		var x: int = int(m[1])
		var y: int = int(m[2])
		if _blocked(x, y):
			chk(false, "inv7: моб %s (%d,%d) рождается на непроходимой '%s'" % [nm, x, y, _ch(x, y)])
		elif reach_map.is_empty() or not bool(reach_map[y][x]):
			chk(false, "inv7: моб %s (%d,%d) недостижим из spawn" % [nm, x, y])
		else:
			chk(true, "inv7: старт моба %s (%d,%d) проходим и достижим" % [nm, x, y])

# ---------------------------------------------------------------- инв. 9 (t54)
## t54 вердикт «внедряем в игру»: в деревне — кодоген-пропы v4. Реестр дима
## заполнен ЧЕСТНО: только спрайты кодоген-атласов assets/village/ и
## assets/cave/ (c3 «Пещера v1»; qwen в игре нет —
## закон 13.11 действует); указатель — дим-контракт t41 (накрытие >= 40% бокса
## героя => 0.5±0.08; южнее стопы — ровно 1.0). Кроны не интегрированы —
## _ys_canopies по-прежнему пуст.
func _inv9() -> void:
	var w: Node2D = game_world
	if w == null or w.get("player") == null:
		chk(false, "inv9: мир не построен")
		return
	var pl: Node2D = w.get("player")
	chk(w.get("village_props") == null, "inv9: qwen VillageProps отсутствует (t52 снос)")
	var ysd: Array = w.get("_ys_props_dim") if w.get("_ys_props_dim") != null else []
	var v4_n := 0
	var sig := ""
	for p in ysd:
		var spr := p as Sprite2D
		if spr == null or not (spr.texture is AtlasTexture):
			continue
		var t: Texture2D = (spr.texture as AtlasTexture).atlas
		var pth := String(t.resource_path) if t != null else "null"
		sig += "%s@%s " % [str((spr.texture as AtlasTexture).region.size), pth.get_file()]
		if pth.contains("assets/village/") or pth.contains("assets/cave/") \
				or pth.contains("assets/forest/"):  # w3int: лес v1 (вердикт «берём»)
			v4_n += 1
	print("   реестр дима: %d [%s]" % [ysd.size(), sig])
	chk(ysd.size() >= 3 and v4_n == ysd.size(),
		"inv9: _ys_props_dim — только кодоген-пропы village/cave/forest (%d/%d)" % [v4_n, ysd.size()])
	var yscan: Array = w.get("_ys_canopies") if w.get("_ys_canopies") != null else []
	# w3int (вердикт «берём» по листу): кроны ЛЕСА v1 интегрированы — реестр честный:
	# только AtlasTexture кодоген-атласа assets/forest/ (qwen/легаси — закон 13.11).
	var can_ok := not yscan.is_empty()
	for cnode in yscan:
		var cspr := cnode as Sprite2D
		if cspr == null or not (cspr.texture is AtlasTexture):
			can_ok = false
			break
		var catlas: Texture2D = (cspr.texture as AtlasTexture).atlas
		var cpath := String(catlas.resource_path) if catlas != null else "null"
		if not cpath.contains("assets/forest/"):
			can_ok = false
			break
	chk(can_ok, "inv9: _ys_canopies — только кодоген-кроны forest v1 (%d)" % yscan.size())
	pl.process_mode = Node.PROCESS_MODE_DISABLED
	# указатель (13×45): t41 дим-контракт на реальном пропе v4
	var sgn: Sprite2D = null
	var v4 = w.village_zone.get_node_or_null("VillageV4")
	if v4 != null:
		for c in v4.get_children():
			var spr := c as Sprite2D
			if spr != null and spr.texture is AtlasTexture \
					and (spr.texture as AtlasTexture).region.size == Vector2(13, 45):
				sgn = spr
	if sgn == null:
		chk(false, "inv9: указатель v4 (13×45) не найден")
	else:
		var foot := Vector2(sgn.global_position.x, sgn.global_position.y + 22.5)
		pl.global_position = Vector2(foot.x, foot.y - 16.0)
		await _frames(24)
		var a_dim := sgn.modulate.a
		pl.global_position = Vector2(foot.x, foot.y + 18.0)
		await _frames(24)
		var a_south := sgn.modulate.a
		pl.global_position = Vector2(foot.x, foot.y - 16.0)  # дальше только проверка шкалы
		pl.process_mode = Node.PROCESS_MODE_INHERIT
		chk(a_dim >= 0.42 and a_dim <= 0.58 and absf(a_south - 1.0) < 0.001,
			"inv9: указатель димится при накрытии (a=%.3f), южнее стопы ровно 1.0 (a=%.3f)" \
			% [a_dim, a_south])
	# герой — в общей шкале глубины (стопа + YS-биас); кадры: z пересчитается в _ys_update
	await _frames(3)
	chk(absf(float(pl.z_index) - (pl.global_position.y + 10.0)) < 3.0,
		"inv9: герой в шкале глубины (z=%d, y=%.0f)" % [pl.z_index, pl.global_position.y])

## Пересечение двух rect, доля от площади rect b (для гейта >=40% в inv9).
func rect2_overlap_ratio_proxy(r: Rect2, b: Rect2) -> float:
	if not r.intersects(b):
		return 0.0
	return r.intersection(b).get_area() / maxf(b.get_area(), 1.0)

# ---------------------------------------------------------------- инв. 10 (c7)
## c7 «микро-жизнь v1»: overlay-качание травы/цветов (2 дискретные фазы,
## паттерн int(t/T)%2, фазы кластеров рассинхронизированы хэшем клетки;
## тайлмап не мутируется — inv2/инв.деревни байт-в-байт уже зелёные выше) и
## светлячки 3..6 (маршрут по проходным клеткам — зеркало BLOCK_CHARS, ноль
## физ. узлов; позиция — чистая функция времени: пин-зеркало совпадает).
func _inv10() -> void:
	var w: Node2D = game_world
	if w == null:
		chk(false, "inv10: мир не построен")
		return
	var sway: Node2D = w.village_zone.get_node_or_null("VillageSway")
	var mgr: Node = w.village_zone.find_child("Flies", true, false)
	if sway == null or mgr == null:
		chk(false, "inv10: VillageSway/Flies не найдены — поставка c7 не на месте")
		return
	var items: Array = sway.get("items")
	chk(items.size() > 0, "inv10: кластеров качания построено %d" % items.size())
	var tex0: Array = []
	for it in items:
		tex0.append((it["spr"] as Sprite2D).texture)
	# окно — НАСТОЯЩЕЕ время (в headless кадры идут быстрее реального):
	# 1.3 c ≈ 2.6 периода SWAY_T; сравнение «за весь проём» (на конце окна
	# фаза может совпасть со стартовой)
	var changed_flags: Array = []
	for i in items.size():
		changed_flags.append(false)
	var t_end := Time.get_ticks_msec() + 1300
	while Time.get_ticks_msec() < t_end:
		await _frames(2)
		for i in items.size():
			if (items[i]["spr"] as Sprite2D).texture != tex0[i]:
				changed_flags[i] = true
	var moved := 0
	var distinct := {}
	for i in items.size():
		if bool(changed_flags[i]):
			moved += 1
		distinct[(items[i]["spr"] as Sprite2D).texture] = true
	chk(moved > 0, "inv10: качание — за 1.3 с кадр сменили %d кластеров" % moved)
	chk(distinct.size() >= 2,
		"inv10: фазы не синхронны — в моменте разных кадров %d" % distinct.size())
	# c9: куртины «G» — каждая пин-клетка в items (плотность 1.0), каждая
	# сменила кадр за окно, фазы куртин независимы между собой
	var g_items: Array = []
	var g_flags: Array = []
	for i in items.size():
		var cell: Vector2i = items[i]["cell"]
		if _ch(cell.x, cell.y) == "G":
			g_items.append(items[i])
			g_flags.append(bool(changed_flags[i]))
	var g_moved := 0
	for fl in g_flags:
		if bool(fl):
			g_moved += 1
	var g_distinct := {}
	for git in g_items:
		g_distinct[(git["spr"] as Sprite2D).texture] = true
	chk(g_items.size() == PIN_TUFTS.size() and g_moved == PIN_TUFTS.size(),
		"inv10: куртины в качании — %d/%d клеток, все сменили кадр" % [g_moved, g_items.size()])
	# тайлмап-доказательство (без скриншотов): каждая «G»-клетка — тайл
	# источника 1 (v4-пол) с атлас-координатой слота FLOOR_SLOTS["G"] —
	# зеркало _build_tiles() world.gd; фактический тайл берётся из живого слоя
	var tml: TileMapLayer = null
	for c in w.village_zone.get_children():
		if c is TileMapLayer:
			tml = c as TileMapLayer
			break
	var tile_ok := tml != null
	if tile_ok:
		for t in PIN_TUFTS:
			if tml.get_cell_source_id(Vector2i(int(t[0]), int(t[1]))) != 1 \
					or tml.get_cell_atlas_coords(Vector2i(int(t[0]), int(t[1]))) \
					!= Vector2i(int(VillageArt.FLOOR_SLOTS["G"]), 0):
				tile_ok = false
	chk(tile_ok, "inv10: тайлмап: все куртины — тайл v4-пола слота «G»")
	chk(g_distinct.size() >= 2,
		"inv10: фазы куртин независимы (разных кадров в моменте: %d)" % g_distinct.size())
	# F2 (ревью c8): мультисеты цветов кадров A/L/R строгие для обоих слотов —
	# сдвиг на 1 px не теряет пикселей кромки (поле 18×16 + обрезка)
	var ftex: Texture2D = load("res://assets/village/village_floor_v4.png")
	var ms_ok := true
	for slot in [1, 2]:
		var fr: Array = VillageArt.sway_frames(ftex, slot)
		if fr.is_empty():
			ms_ok = false
			continue
		var m0 := _ms(fr[0])
		if m0.is_empty() or m0 != _ms(fr[1]) or m0 != _ms(fr[2]):
			ms_ok = false
	chk(ms_ok, "inv10: мультисеты кадров A/L/R строгие (фикс F2, слоты 1 и 2)")
	var bodies := 0
	for n: Node in [sway, mgr]:
		for d in n.find_children("*", "CollisionShape2D", true, false):
			bodies += 1
	chk(bodies == 0, "inv10: ноль коллайдеров у качания/светлячков (%d)" % bodies)
	var flies: Array = mgr.get("flies")
	chk(flies.size() >= 3 and flies.size() <= 6,
		"inv10: светлячков %d (в диапазоне 3..6)" % flies.size())
	if flies.is_empty():
		return
	var route_ok := true
	for f: Dictionary in flies:
		for c: Vector2i in f["cells"]:
			if _blocked(c.x, c.y):
				route_ok = false
	chk(route_ok, "inv10: весь маршрут светлячков — проходимые клетки (point-сетка)")
	# чистая функция времени: независимое зеркало формулы совпадает со живым
	# положением (детерминизм без накопления) и в моменте позиция лежит в
	# проходной клетке (в стены зайти не может физически)
	var mirror_ok := true
	var cell_ok := true
	var tt := float(Time.get_ticks_msec()) / 1000.0
	for f: Dictionary in flies:
		var p_live: Vector2 = (f["spr"] as Sprite2D).global_position
		var p_mirr := _ff_pos(f, tt)
		if p_live.distance_to(p_mirr) > 2.0:
			mirror_ok = false
		var cc := Vector2i(int(floor(p_live.x / 16.0)), int(floor(p_live.y / 16.0)))
		if _blocked(cc.x, cc.y):
			cell_ok = false
	chk(mirror_ok, "inv10: позиция светлячка = чистая функция времени (зеркало)")
	chk(cell_ok, "inv10: светлячки в моменте — в проходных клетках")
	# живое движение — тоже окном по настоящему времени (max excursion)
	var p0: Vector2 = (flies[0]["spr"] as Sprite2D).global_position
	var max_move := 0.0
	t_end = Time.get_ticks_msec() + 1300
	while Time.get_ticks_msec() < t_end:
		await _frames(2)
		max_move = maxf(max_move, p0.distance_to((flies[0]["spr"] as Sprite2D).global_position))
	chk(max_move > 1.5,
		"inv10: светлячки живые — ход %.1f px за 1.3 с" % max_move)


## Зеркало формулы FireflyLayer._process (копия договора c7).
func _ff_pos(f: Dictionary, tt: float) -> Vector2:
	var cs: Array = f["cells"]
	var nn := cs.size()
	var u := tt / float(f["hop"]) + float(f["phase"])
	var k := int(u)
	var fr: float = fmod(u, 1.0)
	var a: Vector2i = cs[posmod(k, nn)]
	var b: Vector2i = cs[posmod(k + 1, nn)]
	var pa := Vector2(float(a.x) * 16.0 + 8.0, float(a.y) * 16.0 + 8.0)
	var pb := Vector2(float(b.x) * 16.0 + 8.0, float(b.y) * 16.0 + 8.0)
	return pa.lerp(pb, fr) + Vector2(0.0, -6.0 + sin(tt * 2.1 + float(f["phase"]) * TAU) * 1.5)


## Мультисет непроврачных пикселей текстуры: {аргб-ключ -> count}
## (строгая сверка фаз A/L/R в inv10, фикс F2).
func _ms(tex) -> Dictionary:
	var o := {}
	var im: Image = (tex as ImageTexture).get_image()
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var k := PAL.key(c)
			o[k] = int(o.get(k, 0)) + 1
	return o

# ---------------------------------------------------------------- инв. 11 (16.11)
## 16.11 юзер-фикс «подвкладки в журнале» (76f389b): в разделе «Квесты» —
## «Активные» / «Завершённые» со счётчиками на самих кнопках; журнал ВСЕГДА
## открывается на «Активных»; пустые «Завершённые» показывают заглушку; ряд
## подвкладок живёт только на квестах; переключение перерисовывает список по
## status (строки «[x] » vs «[ ] »). Пин поведенческий, без md5 на живые файлы.

## Заголовки строк квеста в списке журнала: «[x] » — завершён, «[ ] » — активен
## (строки целей начинаются с отступа, их не считаем).
func _inv11_heads(jr: Node) -> Dictionary:
	var o := {"act": 0, "done": 0}
	var lst: VBoxContainer = jr.get("_list")
	for ch in lst.get_children():
		if not (ch is Label):
			continue
		var t := String((ch as Label).text)
		if t.begins_with("[x] "):
			o["done"] = int(o["done"]) + 1
		elif t.begins_with("[ ] "):
			o["act"] = int(o["act"]) + 1
	return o

func _inv11() -> void:
	var w: Node2D = game_world
	if w == null:
		chk(false, "inv11: мир не построен")
		return
	var jr: Node = null
	for c in w.get_children():
		if c is Journal:
			jr = c
	chk(jr != null, "inv11: Journal найден в дереве мира")
	if jr == null:
		return
	# два побочных квеста: один сдан, другой взят — оба видны (visible_in_journal)
	GameState.set_flag("q.q_suhotsvet", QuestsData.STATUS_DONE)
	GameState.set_flag("q.q_campfires", QuestsData.STATUS_ACTIVE)
	await _frames(2)  # тик QuestsData.refresh: DOWN-переходов у реестра нет
	# зеркало данных (entries + сюжетный гейт рендера journal.gd::_rebuild)
	var act := 0
	var done := 0
	for raw_e in QuestsData.entries(GameState):
		var e: Dictionary = raw_e
		var qid := String(e.get("id", ""))
		if qid == "elder" and int(GameState.elder_quest) < 1:
			continue
		if qid == "cave" and int(GameState.cave_state) < 1:
			continue
		if int(e.get("status", 0)) == QuestsData.STATUS_DONE:
			done += 1
		else:
			act += 1
	chk(done > 0 and act > 0,
		"inv11: в данных есть и активные (%d), и завершённые (%d) записи — пин на чём строить" % [act, done])
	# ряд ПОДВКЛАДОК должен существовать как узел и поле: на HEAD до 76f389b их нет
	# вовсе (ни _qsub, ни кнопок) -> пин краснеет честно, без «vacuous pass»
	var qv: Variant = jr.get("_qsub")
	var btnsv: Variant = jr.get("_qsub_btns")
	var rowv: Variant = jr.get("_qsub_row")
	var row_s := "нет"
	if rowv != null:
		row_s = "есть"
	var nbtns := -1
	if btnsv != null:
		nbtns = (btnsv as Array).size()
	chk(qv != null and btnsv != null and rowv != null,
		"inv11: подвкладки на месте: _qsub=%s, кнопок=%d, ряд=%s (до 76f389b — null)" % [
			str(qv), nbtns, row_s])
	if qv == null or btnsv == null or rowv == null:
		return
	var btns: Array = btnsv
	jr.call("close")
	jr.call("open")
	var q0 := int(jr.get("_qsub"))
	chk(q0 == 0, "inv11: журнал открылся на «Активных» (_qsub=%d)" % q0)
	var heads0 := _inv11_heads(jr)
	chk(int(heads0["act"]) == act and int(heads0["done"]) == 0,
		"inv11: на «Активных» %d строк и ноль [x] (данных активных %d)" % [int(heads0["act"]), act])
	chk(btns.size() == 2, "inv11: ряд подвкладок — 2 кнопки («Активные»/«Завершённые») (%d)" % btns.size())
	if btns.size() != 2:
		return
	var b0: Button = btns[0]
	var b1: Button = btns[1]
	chk(String(b0.text) == "Активные · %d" % act and String(b1.text) == "Завершённые · %d" % done,
		"inv11: счётчики на подвкладках: «%s» / «%s»" % [String(b0.text), String(b1.text)])
	chk(b0.get_theme_color("font_color") == Color(1, 0.85, 0.45) \
			and b1.get_theme_color("font_color") == Color(1, 1, 1, 0.55),
		"inv11: активная подвкладка амбер, вторая приглушена (канон flat-тегми вкладок)")
	jr.call("select_qsub", 1)
	await _frames(30)  # пересборка — в тик _process (TICK 0.35 с = 21 кадр на 60 fps)
	var q1 := int(jr.get("_qsub"))
	var heads1 := _inv11_heads(jr)
	chk(q1 == 1, "inv11: подвкладка переключилась (_qsub=%d)" % q1)
	chk(int(heads1["done"]) == done and int(heads1["act"]) == 0,
		"inv11: на «Завершённых» %d строк [x] и ноль активных (данных завершённых %d)" % [int(heads1["done"]), done])
	chk(b1.get_theme_color("font_color") == Color(1, 0.85, 0.45),
		"inv11: после переключения амбер переехал на «Завершённые»")
	# требование пользователя: повторное открытие — всегда с «Активных»
	jr.call("close")
	jr.call("open")
	var q2 := int(jr.get("_qsub"))
	chk(q2 == 0, "inv11: journal.open() всегда возвращает на «Активные» (_qsub=%d)" % q2)
	# мышь живая после повторного открытия: close() прячет subtree в IGNORE
	var mouse_ok := true
	for arr_name in ["_tab_btns", "_qsub_btns"]:
		var arr: Array = jr.get(arr_name)
		for b in arr:
			if (b as Button).mouse_filter != Control.MOUSE_FILTER_STOP:
				mouse_ok = false
	chk(mouse_ok, "inv11: после open() все вкладки и подвкладки ловят мышь")
	# ряд подвкладок живёт только на квестах
	var qrow: HBoxContainer = jr.get("_qsub_row")
	jr.call("select_tab", int(Journal.TAB_ACHV))
	await _frames(3)
	chk(not qrow.visible, "inv11: на «Достижениях» ряд подвкладок скрыт")
	jr.call("select_tab", int(Journal.TAB_QUESTS))
	await _frames(3)
	chk(qrow.visible, "inv11: на «Квестах» ряд подвкладок виден")
	# пустые «Завершённые» — честная заглушка, а не пустой экран
	GameState.set_flag("q.q_suhotsvet", QuestsData.STATUS_NONE)
	jr.call("select_qsub", 1)
	await _frames(30)
	var empty_ok := false
	var lst: VBoxContainer = jr.get("_list")
	for ch2 in lst.get_children():
		if ch2 is Label and String((ch2 as Label).text).begins_with("Завершённых пока нет"):
			empty_ok = true
	chk(empty_ok, "inv11: пустые «Завершённые» показывают заглушку, а не пустоту")
	jr.call("close")
	print("qa_vlg inv11: подвкладки журнала запинены: активные %d / завершённые %d, reset на открытии, амбер, мышь, ряд только на квестах, заглушка" % [act, done])

# g14 (просьба пользователя 16.11): рубрики-подвкладки достижений + код-ген
# значки 8×8. Пины поведенческие, как inv11: покрытие рубрик и неизменность
# id (сейв-совместимость), иконки (палитра/оба состояния), UI-ряд со счётчиком
# «готово/всего», автовход в первую непустую рубрику при open().
const INV12_IDS := "first_blood;hunter_25;hunter_100;boss_slayer;witch_slayer;" \
		+ "alchemist;brewer_10;campfires;treasure;collector;wealth;herbalist;hardcore;" \
		+ "ng_second;ng_vet;ng_finale;ng_magnat;ng_crowns;rekindled;undying;"

func _inv12() -> void:
	var w: Node2D = game_world
	if w == null:
		chk(false, "inv12: мир не построен")
		return
	var jr: Node = null
	for c in w.get_children():
		if c is Journal:
			jr = c
	chk(jr != null, "inv12: Journal найден в дереве мира")
	if jr == null:
		return
	# 1) данные: id 20 ачивок прежним порядком (сейвы живые), рубрика у всех
	var ids := ""
	for raw_c in AchvCatalog.ITEMS:
		var c0: Dictionary = raw_c
		ids += String(c0.get("id", "")) + ";"
	chk(ids == INV12_IDS, "inv12: id достижений не перенумерованы (сейвы живые)")
	var cats: Array = AchvCatalog.CAT_TITLES.keys()
	var per := {}
	for k in cats:
		per[String(k)] = 0
	var foreign := 0
	for raw_c in AchvCatalog.ITEMS:
		var c1: Dictionary = raw_c
		var k := String(c1.get("category", ""))
		if not per.has(k):
			foreign += 1
		else:
			per[k] = int(per[k]) + 1
	var empty_c := 0
	for k in cats:
		if int(per[String(k)]) == 0:
			empty_c += 1
	chk(foreign == 0 and AchvCatalog.ITEMS.size() == 20,
		"inv12: рубрика у всех 20 записей, посторонних ключей %d" % foreign)
	chk(cats.size() >= 4 and cats.size() <= 6 and empty_c == 0,
		"inv12: рубрик %d (4–6), пустых нет: %s" % [cats.size(), str(per)])
	# 2) значки: код-ген 8×8 (семейство brewed_icon), оба состояния, палитра
	var ui := load("res://scripts/ui_icons.gd")
	var pal: Dictionary = PixelPalette.color_index()
	var icons_ok := true
	var detail_min := 99
	for k in cats:
		for st in [false, true]:
			var t: Texture2D = ui.achv_icon(String(k), bool(st))
			if t == null or t.get_size() != Vector2(8, 8):
				icons_ok = false
				continue
			var im: Image = t.get_image()
			var colored := 0
			for y in 8:
				for x in 8:
					var col: Color = im.get_pixel(x, y)
					if col.a == 0.0:
						continue
					colored += 1
					if not pal.has(PixelPalette.key(col)):
						icons_ok = false
			detail_min = mini(detail_min, colored)
	chk(icons_ok and detail_min >= 12,
		"inv12: 10 значков 8×8 код-ген, пиксели в палитре, силуэт не пустой (мин. пикселей %d)" % detail_min)
	var imgA: Image = ui.achv_icon("combat", true).get_image()
	var imgD: Image = ui.achv_icon("combat", false).get_image()
	var differs := false
	for y in 8:
		for x in 8:
			if imgA.get_pixel(x, y) != imgD.get_pixel(x, y):
				differs = true
	chk(differs, "inv12: янтарная (закрытая) и тусклая (открытая) различаются")
	var sil := {}
	for k in cats:
		var sh := ""
		var im2: Image = ui.achv_icon(String(k), false).get_image()
		for y in 8:
			for x in 8:
				if im2.get_pixel(x, y).a > 0.0:
					sh += "1"
		sil[String(k)] = sh
	var uniq := {}
	for k in sil:
		uniq[String(sil[k])] = true
	chk(uniq.size() == cats.size(), "inv12: силуэты пяти рубрик различны (меч/след/молот/монета/спираль)")
	# 2б) g15 (просьба «крупнее и привлекательнее»): крупная плашечная версия
	# 24×24 — тот же арт скейлом 3×, палитра чистая, объём 3 тона + блик
	var big_ok := true
	for k in cats:
		for st in [false, true]:
			var tb: Texture2D = ui.achv_big_icon(String(k), bool(st))
			if tb == null or tb.get_size() != Vector2(24, 24):
				big_ok = false
				continue
			var imb: Image = tb.get_image()
			for y in 24:
				for x in 24:
					var cb: Color = imb.get_pixel(x, y)
					if cb.a == 0.0:
						continue
					if not pal.has(PixelPalette.key(cb)):
						big_ok = false
			# скейл честный: каждый блок 3×3 однороден и == пикселю 8×8-арта
			for y2 in 8:
				for x2 in 8:
					var base2: Color = imb.get_pixel(x2 * 3, y2 * 3)
					for dy3 in 3:
						for dx3 in 3:
							if imb.get_pixel(x2 * 3 + dx3, y2 * 3 + dy3) != base2:
								big_ok = false
	chk(big_ok, "inv12/g15: крупные эмблемы 24×24 — код-ген скейл 3×, палитра чистая")
	var imgB: Image = ui.achv_big_icon("combat", true).get_image()
	var tones := {}
	for y in 24:
		for x in 24:
			if imgB.get_pixel(x, y).a > 0.0:
				tones[PixelPalette.key(imgB.get_pixel(x, y))] = true
	var gold_n := 0
	var hot := false
	for tkey in tones:
		if not hot and tkey == PixelPalette.key(PixelPalette.FLATS["FIRE_HOT"]):
			hot = true
		if String(PixelPalette.color_index()[tkey][0]) == "HUD_GOLD":
			gold_n += 1
	chk(gold_n >= 3 and hot,
		"inv12/g15: янтарная эмблема объёмна: тонов HUD_GOLD %d (ждём >=3, LIGHT/MID/DARK) + блик FIRE_HOT" % gold_n)
	# 3) вкладка: ряд рубрик, счётчик, автовход в первую непустую при open()
	var asv: Variant = jr.get("_asub_btns")
	if asv == null or (asv as Array).size() != cats.size():
		chk(false, "inv12: кнопок рубрик %d, ждали %d" % [
			0 if asv == null else (asv as Array).size(), cats.size()])
		return
	chk(true, "inv12: кнопок рубрик — %d" % cats.size())
	# детерминизм: снимем все ach.*-флаги этого процесса (стенд умрёт вместе с ними)
	var ak: Array = []
	for fk in GameState.flags.keys():
		if String(fk).begins_with("ach."):
			ak.append(fk)
	for fk in ak:
		GameState.flags.erase(fk)
	GameState.set_flag("ach.campfires", true)  # единственная закрытая — «Исследования»
	jr.call("close")
	jr.call("open")
	jr.call("select_tab", int(Journal.TAB_ACHV))
	await _frames(3)
	var a2 := int(jr.get("_asub"))
	chk(a2 >= 0 and a2 < cats.size() and String(cats[a2]) == "explore",
		"inv12: автовход в первую непустую рубрику (_asub=%d, «%s»)" % [
			a2, String(cats[a2]) if a2 >= 0 and a2 < cats.size() else "?"])
	var rowr: Variant = jr.get("_asub_row")
	chk(rowr != null and (rowr as Control).visible, "inv12: ряд рубрик виден на «Достижениях»")
	var btxt := String(((asv as Array)[a2] as Button).text)
	chk(btxt.begins_with("Исследования · 1/2"), "inv12: счётчик готово/всего на рубрике: «%s»" % btxt)
	# строки: только рубрика explore, у каждой карточка (g15) с крупной эмблемой;
	# состояния оба (campfires закрыта — янтарь/бронза, treasure — тусклая/железо)
	var amb := 0
	var dim := 0
	var rows := 0
	var heads2 := 0
	var only := true
	var cards := 0
	var cards_unl := 0
	var cards_dim := 0
	var plates := 0
	var gaps := -1
	var alv: Variant = jr.get("_ach_list")
	if alv != null:
		gaps = (alv as Control).get_theme_constant("separation")
	var stack: Array = [jr.get("_ach_list")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is HBoxContainer:
			rows += 1
		if n is PanelContainer:
			var sbox: StyleBoxFlat = (n as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
			if sbox != null and sbox.bg_color == PixelPalette.SHEET.PANEL \
					and sbox.get_border_width(SIDE_LEFT) == 1:
				cards += 1
				if sbox.border_color == PixelPalette.RAMPS["BRONZE"][1]:
					cards_unl += 1
				elif sbox.border_color == PixelPalette.SHEET.LINE \
						and (n as PanelContainer).get_child_count() > 0 \
						and (n as PanelContainer).get_child(0).get_child_count() > 0 \
						and (n as PanelContainer).get_child(0).get_child(0) is PanelContainer \
						and ((n as PanelContainer).get_child(0).get_child(0) as PanelContainer) \
								.get_theme_stylebox("panel").bg_color == PixelPalette.SHEET.BG:
					cards_dim += 1
					plates += 1
		if n is TextureRect:
			var t2: Texture2D = (n as TextureRect).texture
			if t2 == ui.achv_big_icon("explore", true):
				amb += 1
			elif t2 == ui.achv_big_icon("explore", false):
				dim += 1
		if n is Label:
			var tx := String((n as Label).text)
			if tx.contains("Первая кровь") or tx.contains("Богач"):
				only = false  # чужие рубрики в список не leak'нули
			if tx.begins_with("[x] Три костра") or tx.begins_with("[ ] Кладоискатель"):
				heads2 += 1  # тексты строк на месте (не пустые ряды-заглушки)
		for ch3 in n.get_children():
			stack.append(ch3)
	chk(rows == int(per["explore"]) and only and heads2 == 2,
		"inv12: список фильтрован рубрикой: %d строк (ждём %d), чужих нет, заголовки видны (%d)" % [rows, int(per["explore"]), heads2])
	chk(amb == 1 and dim == 1,
		"inv12: значки в обоих состояниях в строках (янтарь %d, тусклых %d)" % [amb, dim])
	chk(cards == rows and cards_unl == 1 and cards_dim == 1 and plates == 1,
		"inv12/g15: карточки с рамкой 1px и фоном SHEET.PANEL у каждой записи (%d/%d), бронза/железо %d/%d, плашка SHEET.BG %d" % [
			cards, rows, cards_unl, cards_dim, plates])
	chk(gaps >= 4 and gaps <= 8,
		"inv12/g15: зазор между карточками %d px (в контракте 4–8)" % gaps)
	# 4) сейв-совместимость: рубрика — только метаданные, флаг-ключи не тронуты;
	# тестовые анлоки этого процесса убираем
	GameState.flags.erase("ach.campfires")
	jr.call("close")
	print("qa_vlg inv12: рубрики достижений запинены: покрытие, id-порядок, иконки-палитра, автовход, счётчик, фильтр, оба состояния")
