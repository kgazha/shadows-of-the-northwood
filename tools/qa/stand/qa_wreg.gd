extends Node2D
## qa_wreg — t4 независимая QA-регрессия «Мир v1» (роль: qa-gate; веноз вендора
## qa_world — не дублируем внутренности, свои алгоритмы и свои сканеры).
##
## Разделы:
##  R1 золотые пины composition (FNV-1a 64, 5 сидов) + повторный пересчёт +
##     НЕЗАВИСИМЫМ хэшером (своя сериализация сетки) — кросс-процессные константы;
##  R2 BFS-связность (своя реализация, 16 сидов): карта мира и 6 локаций —
##     ноль отрезанных walkable-клеток от точки входа; порталы/арка/сундук/
##     спавны мобов достижимы; мобы: >=8 от входа, разнесены >=3;
##  R3 края (t59-метод, Minkowski 5×4 по герою 10×8, СВОЙ скан): 0 касаний
##     пиксельной границы на 7 картах ×5 сидов + НЕГАТИВНЫЙ КОНТРОЛЬ (дырявая
##     карта обязана детектироваться) + живая физика == сетка (t58-рассогласования);
##  R4 зазоры: минимальная замкнутая клеточная щель >= 14 px (канон t58; по
##     full-cell коллайдерам физики = 16×run), все коллайдеры — кратны клетке;
##  R5 пояса: своя таблица Chebyshev, ДВОЙНОЙ пин (своя таблица != OpenWorld),
##     формулы belt/gold, brute_tier, живой belt зон;
##  R6 сейв/резюме: worldmap и локации roundtrip (позиция/зона/флаги wm.open),
##     легаси-цепочка этажей, сейв без позиции -> деревня, живой resume из
##     user:// на dungeon и worldmap (точка входа = спавн зоны);
##  R7 утечки нод: туда-обратно x6 локаций x3 раунда, дельта OBJECT_NODE_COUNT
##     между раундами == 0, мобы не накапливаются;
##  R8 перф: кадр худшей зоны/карты к деревне <= x1,3 (метод v5.2 — max-знаменатель
##     по смежным замерам деревни с отсевом раундов-сталлов; история и основание
##     в r8_perf, старшая версия метода в шапке perf_world.gd); генерация: warm-up
##     стабильность <= x1,1 + абсолютный бюджет; аллокации на покое:
##     OBJECT_NODE_COUNT/RESOURCE дельта == 0;
##  R9 кадры: PNG-схема карты мира и шести локаций (QA-артефакт, вне палитры).
##
## Формат: "QA_WREG x/y" (manifest mode "xy").

const RUN_SEED := 97531
const CELL_SEEDS := 16
const PIX_SEEDS := 5
const GOLDEN_N := 5
const HERO_HW := 5.0
const HERO_HH := 4.0
const T16 := 16

# GOLDEN-WM-PIN(25.11, причина: «Среда v1» — водная геометрия: река Чащи с
# 1-клеточными бродами, озеро Снежника, оазис Пустоши (SOLID+'w', коллайдеры
# честные, периметр t59 не тронут, R2-карманы откатываются); прежний ряд 19.11
# «W-P0-1 fix»: -3144…/1295…/9108…/-1282…/-8037…; ряд 18.11: 8645…/4246…/
# 6360…/8408…/-4502…) — двойной пин: стенд сверяет ГЕНЕРАТОР с константой,
# независимой от него
const GOLDEN_COMP_PINS := [
	3667740230982545934,    # seed 97531
	-223799754728817763,    # seed 105450
	-6968745053202592759,   # seed 113369
	-4388011758957587721,   # seed 121288
	-8369543153597366183,   # seed 129207
]
# MY-WM-PIN(25.11, «Среда v1»): вторые константы — независимый
# сериализационный кросс-хэш (_my_comp_hash), сбит с генератора НЕ канонической
# склейкой; стабилен на 2 пересчётах до записи (R1.2 был stability-only, теперь —
# второй пин). Прежний ряд 19.11 «W-P0-1 fix»: 3830…/2505…/-917…/6146…/-2690…
const MY_COMP_PINS := [
	7537080674183788661,   # seed 97531
	2797681100009836924,   # seed 105450
	-2896983677630182774,  # seed 113369
	7547205301623735724,   # seed 121288
	-8273286034137620872,  # seed 129207
]
# своя таблица порталов/поясов (независимый источник, BALANCE «Мир v1»)
const MY_PORTALS := {"forest": [20, 44], "steppe": [62, 46], "dungeon": [12, 32],
		"castle": [78, 18], "snow": [52, 8], "desert": [84, 36]}
const MY_BELTS := {"forest": 1, "steppe": 1, "dungeon": 2, "castle": 2, "snow": 3, "desert": 2}
const MY_ANCHOR := [47, 58]
# «Среда v1» (t11, вердикт 25.11): 'w' — честная непроходимая вода (река/
# озеро/оазис), своё SOLID-зеркало сканеров R2-R4 включает её; брод
# (1-клеточная переправа дороги '-' через реку) остаётся проходимым.
const SOLID := ["#", "M", "W", "C", "w"]
const ZONES := ["snow", "desert", "steppe", "forest", "castle", "dungeon"]

var total := 0
var pass_n := 0
var fail_n := 0
var OWg: Variant = null
var world = null
var _wm_cache := {}
var _loc_cache := {}

func chk(cond: bool, name: String) -> void:
	total += 1
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])

func _fr(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

func _seed(i: int) -> int:
	return RUN_SEED + i * 7919

func _wm(s: int) -> Dictionary:
	if not _wm_cache.has(s):
		_wm_cache[s] = OWg.worldmap_map(s)
	return _wm_cache[s]

func _loc(s: int, z: String) -> Dictionary:
	var k := "%d|%s" % [s, z]
	if not _loc_cache.has(k):
		_loc_cache[k] = OWg.loc_map(s, z)
	return _loc_cache[k]

# ================================================================ свои сканеры
func _ch(grid: Array, x: int, y: int) -> String:
	if y < 0 or x < 0 or y >= grid.size():
		return "#"
	var row := String(grid[y])
	if x >= row.length():
		return "#"
	return row[x]

func _solid(grid: Array, x: int, y: int) -> bool:
	return SOLID.has(_ch(grid, x, y))

## своя BFS по клеткам: dict "x,y" -> true
func _bfs_cells(grid: Array, spawn: Vector2i) -> Dictionary:
	var seen := {}
	if _solid(grid, spawn.x, spawn.y):
		return seen
	seen["%d,%d" % [spawn.x, spawn.y]] = true
	var q: Array = [spawn]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			var k := "%d,%d" % [n.x, n.y]
			if seen.has(k) or _solid(grid, n.x, n.y):
				continue
			seen[k] = true
			q.append(n)
	return seen

## t59-метод своей реализацией: blocked-пиксели = SOLID-клетки, раздутые на
## половину бокса героя (Minkowski 5×4); BFS центров 4-связно по пиксельной
## сетке карты (карта клипится её прямоугольником). Возвращает
## {reach, edge: {"cx,cy": px}, spawn_ok}
func _pix_scan(grid: Array, spawn: Vector2i, w: int, h: int) -> Dictionary:
	var pw := w * T16
	var ph := h * T16
	var blocked := PackedByteArray()
	blocked.resize(pw * ph)
	for y in h:
		for x in w:
			if not SOLID.has(String(grid[y])[x]):
				continue
			var x0 := maxi(0, int(floor(x * T16 - HERO_HW)))
			var x1 := mini(pw - 1, int(ceil((x + 1) * T16 + HERO_HW)) - 1)
			var y0 := maxi(0, int(floor(y * T16 - HERO_HH)))
			var y1 := mini(ph - 1, int(ceil((y + 1) * T16 + HERO_HH)) - 1)
			for py in range(y0, y1 + 1):
				var base := py * pw
				for px in range(x0, x1 + 1):
					blocked[base + px] = 1
	var spx := spawn.x * T16 + T16 / 2
	var spy := spawn.y * T16 + T16 / 2
	var res := {"reach": 0, "edge": {}, "spawn_ok": blocked[spy * pw + spx] == 0}
	if not res["spawn_ok"]:
		return res
	var q := PackedInt32Array()
	q.append(spy * pw + spx)
	blocked[spy * pw + spx] = 2
	var head := 0
	while head < q.size():
		var p: int = q[head]
		head += 1
		res["reach"] = int(res["reach"]) + 1
		var pxx := p % pw
		var pyy := int(p / pw)
		if pxx == 0 or pyy == 0 or pxx == pw - 1 or pyy == ph - 1:
			var ck := "%d,%d" % [int(pxx / T16), int(pyy / T16)]
			res["edge"][ck] = int(res["edge"].get(ck, 0)) + 1
		for d in [1, -1, pw, -pw]:
			var n: int = p + d
			if d == 1 and pxx == pw - 1:
				continue
			if d == -1 and pxx == 0:
				continue
			if n < 0 or n >= pw * ph:
				continue
			if blocked[n] != 0:
				continue
			blocked[n] = 2
			q.append(n)
	return res

## минимальная ЗАМКНУТАЯ (с обеих сторон solid) клеточная щель, в клетках
func _min_closed_run(grid: Array) -> int:
	var best := 999
	var h := grid.size()
	for cy in h:
		var cols := String(grid[cy]).length()
		var cx := 0
		while cx < cols:
			if not _solid(grid, cx, cy) and _solid(grid, cx - 1, cy):
				var run := 0
				var x2 := cx
				while x2 < cols and not _solid(grid, x2, cy):
					run += 1
					x2 += 1
				if x2 < cols and run > 0:
					best = mini(best, run)
				cx = x2
			else:
				cx += 1
	for cx in String(grid[0]).length():
		var cy := 0
		while cy < h:
			if not _solid(grid, cx, cy) and _solid(grid, cx, cy - 1):
				var run := 0
				var y2 := cy
				while y2 < h and not _solid(grid, cx, y2):
					run += 1
					y2 += 1
				if y2 < h and run > 0:
					best = mini(best, run)
				cy = y2
			else:
				cy += 1
	return best

## независимый хэш composition: своя сериализация (rows + spawn/portal/chest)
func _my_fnv(s: String) -> int:
	var h := -3750763034362895579
	for b in s.to_utf8_buffer():
		h = int(h ^ b)
		h = h * 1099511628211
	return h

func _my_comp_hash(comp: Dictionary) -> int:
	var keys: Array = comp.keys()
	keys.sort()
	var s := ""
	for k in keys:
		var m: Dictionary = comp[k]
		s += "%s|" % String(k)
		for row in (m["grid"] as Array):
			s += String(row) + "\n"
		var meta: Dictionary = m["meta"]
		s += "sp%s|po%s|ch%s|m%s" % [str(meta.get("spawn", [])), str(meta.get("portal_out", [])),
				str(meta.get("chest", [])), str(meta.get("mobs", []))]
		s += "p%s|a%s" % [str(meta.get("portals", {})), str(meta.get("arch", []))]
	return _my_fnv(s)

# ==================================================================== main
func _ready() -> void:
	print("[qa_wreg] begin")
	_wipe_save()
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	GameState.run_seed = RUN_SEED
	OWg = load("res://scripts/open_world.gd")
	print("WREG beat r1")
	r1_pins()
	print("WREG beat r2")
	r2_connectivity()
	print("WREG beat r3")
	r3_edges_grid()
	print("WREG beat r4")
	r4_gaps()
	print("WREG beat r5")
	r5_belts_grid()
	print("WREG beat r6")
	await r6_live_and_save()
	print("WREG beat r7")
	await r7_leaks()
	print("WREG beat r8")
	await r8_perf()
	print("WREG beat r9")
	r9_frames()
	_wipe_save()
	GameState.start_fresh_game()
	print("QA_WREG %d/%d" % [pass_n, total])
	get_tree().quit(0 if fail_n == 0 else 1)

func _wipe_save() -> void:
	if FileAccess.file_exists("user://save_morkheim.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))

# --- R1 пины -------------------------------------------------------------------
func r1_pins() -> void:
	var ok := true
	var my_ok := true
	for i in GOLDEN_N:
		var s := _seed(i)
		var comp: Dictionary = OWg.composition(s)
		var h: int = int(OWg.hash_map(comp))
		if h != int(GOLDEN_COMP_PINS[i]):
			ok = false
			print("  pin %d: %d != %d" % [s, h, GOLDEN_COMP_PINS[i]])
		var h2: int = int(OWg.hash_map(OWg.composition(s)))
		if h2 != h:
			ok = false
		var mh := _my_comp_hash(comp)
		var mh2 := _my_comp_hash(OWg.composition(s))
		if mh != mh2 or mh != int(MY_COMP_PINS[i]):
			my_ok = false
			print("  mypin %d: %d != %d" % [s, mh, int(MY_COMP_PINS[i])])
		print("WREG MYPIN seed=%d h=%d" % [s, mh])
	chk(ok, "R1.1 GOLDEN-WM-PIN composition x5 (пересчёт побайтово равен)")
	chk(my_ok, "R1.2 кросс-хэш composition x5 == второй пин MY_COMP_PIN и стабилен при пересчёте")

# --- R2 связность --------------------------------------------------------------
func _walk_count(grid: Array) -> int:
	var n := 0
	for y in grid.size():
		for x in String(grid[y]).length():
			if not SOLID.has(String(grid[y])[x]):
				n += 1
	return n

func r2_connectivity() -> void:
	if OWg == null:
		chk(false, "R2 нет OpenWorld")
		return
	var wm_pockets := 0
	var wm_key_ok := true
	for i in CELL_SEEDS:
		var s := _seed(i)
		var m: Dictionary = _wm(s)
		var g: Array = m["grid"]
		var meta: Dictionary = m["meta"]
		var sp := Vector2i(int((meta["spawn"] as Array)[0]), int((meta["spawn"] as Array)[1]))
		var seen := _bfs_cells(g, sp)
		var walk := _walk_count(g)
		if seen.size() != walk:
			wm_pockets += walk - seen.size()
		for z in MY_PORTALS:
			var pc := Vector2i(MY_PORTALS[z][0], MY_PORTALS[z][1])
			if not seen.has("%d,%d" % [pc.x, pc.y]):
				wm_key_ok = false
		if not seen.has("48,58"):
			wm_key_ok = false
	chk(wm_pockets == 0, "R2.1 карта мира x%d: отрезанных walkable-клеток 0" % CELL_SEEDS)
	chk(wm_key_ok, "R2.2 карта мира x%d: 6 порталов + арка достижимы от входа" % CELL_SEEDS)
	for z in ZONES:
		var pockets := 0
		var key_ok := true
		var mob_ok := true
		for i in CELL_SEEDS:
			var s := _seed(i)
			var m: Dictionary = _loc(s, z)
			var g: Array = m["grid"]
			var meta: Dictionary = m["meta"]
			var sp := Vector2i(int((meta["spawn"] as Array)[0]), int((meta["spawn"] as Array)[1]))
			var seen := _bfs_cells(g, sp)
			var walk := _walk_count(g)
			if seen.size() != walk:
				pockets += walk - seen.size()
			var po := Vector2i(int((meta["portal_out"] as Array)[0]), int((meta["portal_out"] as Array)[1]))
			if not seen.has("%d,%d" % [po.x, po.y]):
				key_ok = false
			var ch := Vector2i(int((meta["chest"] as Array)[0]), int((meta["chest"] as Array)[1]))
			if not seen.has("%d,%d" % [ch.x, ch.y]):
				key_ok = false
			var taken: Array = []
			for e in (meta["mobs"] as Array):
				var mx := int(e[1])
				var my := int(e[2])
				if not seen.has("%d,%d" % [mx, my]):
					key_ok = false
				if maxi(absi(mx - sp.x), absi(my - sp.y)) < 8:
					mob_ok = false
				for t in taken:
					if maxi(absi(mx - int(t[0])), absi(my - int(t[1]))) < 3:
						mob_ok = false
				taken.append([mx, my])
		chk(pockets == 0, "R2.3 локация %s x%d: отрезанных клеток 0" % [z, CELL_SEEDS])
		chk(key_ok, "R2.4 локация %s: портал-выход/сундук/мобы достижимы" % z)
		chk(mob_ok, "R2.5 локация %s: мобы >=8 от входа, разнесены >=3" % z)

# --- R3 края (t59 метод + негативный контроль) ----------------------------------
func _clone(grid: Array) -> Array:
	var out: Array = []
	for r in grid:
		out.append(String(r))
	return out

func _paint(grid: Array, x: int, y: int, c: String) -> void:
	var row := String(grid[y])
	row[x] = c
	grid[y] = row

func r3_edges_grid() -> void:
	if OWg == null:
		chk(false, "R3 нет OpenWorld")
		return
	# мира: касаний границы ноль. С 19.11 (W-P0-1) ворота — тупик 57..58, ряд 59
	# глух: исключений у сканера нет, нижняя стена полная.
	var wm_touch := 0
	var wm_gate_cells := {}
	for i in PIX_SEEDS:
		var s := _seed(i)
		print("WREG r3 wm seed=%d" % s)
		var m: Dictionary = _wm(s)
		var g: Array = m["grid"]
		var sp := Vector2i(47, 56)
		var r: Dictionary = _pix_scan(g, sp, 96, 60)
		for ck in (r["edge"] as Dictionary).keys():
			wm_touch += (r["edge"] as Dictionary)[ck]
			wm_gate_cells[ck] = true
		# негативный контроль детектора: прогрызи левый берег
		var bad := _clone(g)
		_paint(bad, 0, 30, ".")
		_paint(bad, 0, 31, ".")
		var rb: Dictionary = _pix_scan(bad, sp, 96, 60)
		if (rb["edge"] as Dictionary).is_empty():
			chk(false, "R3 контроль: детектор НЕ нашёл вгрыз в левый край (сид %d)" % s)
	# локации: касаний ноль
	var loc_touch := 0
	for z in ZONES:
		for i in PIX_SEEDS:
			var m: Dictionary = _loc(_seed(i), z)
			var g: Array = m["grid"]
			var r: Dictionary = _pix_scan(g, Vector2i(21, 30), 44, 34)
			for v in (r["edge"] as Dictionary).values():
				loc_touch += int(v)
	chk(loc_touch == 0, "R3.1 локации x%d: 0 достижимых центров на пиксельной границе (t59)" % PIX_SEEDS)
	chk(wm_touch == 0, "R3.2 карта мира x%d: 0 достижимых центров на пиксельной границе (t59); факт: %d px в клетках %s" % [PIX_SEEDS, wm_touch, str(wm_gate_cells.keys())])
	# контроль: заделать ворота -> касаний ноль (кольцо иначе герметично)
	var g2 := _clone((_wm(_seed(0)) as Dictionary)["grid"])
	for yy in [57, 58, 59]:
		_paint(g2, 47, yy, "#")
		_paint(g2, 48, yy, "#")
	var r2: Dictionary = _pix_scan(g2, Vector2i(47, 56), 96, 60)
	chk((r2["edge"] as Dictionary).is_empty() and int(r2["reach"]) > 300000,
			"R3.3 контроль: заделанные ворота -> кольцо герметично (сканер различает)")

# --- R4 зазоры >=14 px ----------------------------------------------------------
func r4_gaps() -> void:
	var worst := 999
	for i in CELL_SEEDS:
		var s := _seed(i)
		worst = mini(worst, _min_closed_run((_wm(s) as Dictionary)["grid"]))
		for z in ZONES:
			worst = mini(worst, _min_closed_run((_loc(s, z) as Dictionary)["grid"]))
	var px := worst * T16
	chk(px >= 14, "R4.1 минимальная замкнутая щель = %d px >= 14 (канон t58), x%d сидов" % [px, CELL_SEEDS])

# --- R5 пояса -------------------------------------------------------------------
func _my_cheb(x: int, y: int) -> int:
	return maxi(absi(x - MY_ANCHOR[0]), absi(y - MY_ANCHOR[1]))

func r5_belts_grid() -> void:
	var t_ok := true
	for z in MY_PORTALS:
		var b := _my_cheb(MY_PORTALS[z][0], MY_PORTALS[z][1]) / 14
		if b != int(MY_BELTS[z]) or int(OWg.portal_belt(z)) != b:
			t_ok = false
			print("  belt %s: my=%d ow=%d want=%d" % [z, b, OWg.portal_belt(z), MY_BELTS[z]])
	chk(t_ok, "R5.1 таблица поясов: свой Chebyshev == пин == OpenWorld (двойной пин)")
	var f_ok := true
	for b in [0, 1, 2, 3, 4]:
		if absf(float(OWg.belt_mult(b)) - (1.0 + 0.25 * b)) > 1e-9:
			f_ok = false
		if absf(float(OWg.gold_mult(b)) - (1.0 + 0.15 * b)) > 1e-9:
			f_ok = false
	chk(f_ok, "R5.2 формулы belt x(1+0.25b) / gold x(1+0.15b) — таблицы 0..4")
	chk(int(OWg.brute_tier(0)) == 1 and int(OWg.brute_tier(1)) == 1 and int(OWg.brute_tier(2)) == 2
			and int(OWg.brute_tier(3)) == 3 and int(OWg.brute_tier(5)) == 3,
			"R5.3 brute_tier: {0,1}->1, 2->2, >=3->3")

# --- R6 живой мир + сейв ---------------------------------------------------------
func _mkworld():
	var w = load("res://scenes/main.tscn").instantiate()
	add_child(w)
	await _fr(6)
	return w

func _wait_area(w, want: String, cap: int = 300) -> bool:
	var waited := 0
	while String(w.active_area) != want and waited < cap:
		await get_tree().process_frame
		waited += 1
	return String(w.active_area) == want

func r6_live_and_save() -> void:
	var w = await _mkworld()
	world = w
	print("WREG r6 world A построен")
	# R3 live: физика == сетка + ворота
	var wcov_ok := true
	var walls_found := 0
	bool(w.call("_ensure_worldmap"))
	var wmg = w.get("worldmap_grid")
	if wmg == null:
		chk(false, "R3.4 worldmap_grid не построен")
	else:
		var cont: Node2D = w.get("worldmap_zone")
		var rects := _wall_rects(cont)
		walls_found = rects.size()
		var cov := _coverage(rects, 96, 60)
		var g: Array = (wmg as Node).get("map_rows")
		for y in 60:
			for x in 96:
				var k := "%d,%d" % [x, y]
				var want := 1 if SOLID.has(String(g[y])[x]) else 0
				if int(cov.get(k, 0)) != want:
					wcov_ok = false
		chk(wcov_ok and walls_found > 0,
				"R3.4 карта мира: физика==сетка (коллайдеров %d, рассогласований 0)" % walls_found)
		# есть ли физический уловитель ПОД створом ворот (x 752..784, y >= 960)?
		var below := 0
		for r: Rect2 in rects:
			if r.end.x > 752.0 and r.position.x < 784.0 and r.position.y >= 60 * 16 - 0.5:
				below += 1
		print("WREG gate: коллайдеров-уловителей под створом ворот = %d" % below)
	for z in ZONES:
		if not bool(w.call("_ensure_location", z)):
			chk(false, "R3.5 локация %s не собралась" % z)
			continue
		var cont2: Node2D = (w.get("biome_zone_cont") as Dictionary)[z]
		var rects2 := _wall_rects(cont2)
		var cov2 := _coverage(rects2, 44, 34)
		var g2: Array = ((w.get("biome_grids") as Dictionary)[z] as Node).get("map_rows")
		var okz := true
		for y in 34:
			for x in 44:
				var k := "%d,%d" % [x, y]
				var want := 1 if SOLID.has(String(g2[y])[x]) else 0
				if int(cov2.get(k, 0)) != want:
					okz = false
		chk(okz, "R3.5 локация %s: физика==сетка" % z)
	# R5 live: belt зон
	var belt_ok := true
	for z in ZONES:
		var gz = (w.get("biome_grids") as Dictionary)[z]
		if int(gz.get("belt")) != int(MY_BELTS[z]):
			belt_ok = false
	chk(belt_ok, "R5.4 живой belt 6 зон == таблица поясов")
	# R6 фикстуры from_dict
	var base: Dictionary = GameState.to_dict()
	var fx := [
		["worldmap", "worldmap", 14400.0 + 56 * 16 + 8, true, "резюме по y-этапу мира"],
		["loc_castle", "loc_castle", 40000.0, true, "резюме по y-этапу замка"],
		["loc_steppe", "loc_steppe", 28800.0, true, "этап степи"],
		["loc_dungeon", "loc_dungeon", 43200.0, true, "этап подземелья"],
		["", "ashen", 9700.0, true, "легаси y>9600 -> пепелище"],
		["", "village", 100.0, true, "легаси равнина -> деревня"],
		["worldmap", "village", 100.0, false, "без позиции -> деревня (паритет)"],
	]
	var fx_ok := true
	for f in fx:
		var d: Dictionary = base.duplicate(true)
		d["area"] = String(f[0])
		d["px"] = 400.0
		d["py"] = float(f[2])
		d["pos_valid"] = bool(f[3])
		d["in_cave"] = false
		GameState.from_dict(d)
		if String(GameState.area) != String(f[1]):
			fx_ok = false
			print("  fix %s: area=%s want=%s" % [f[4], GameState.area, f[1]])
	chk(fx_ok, "R6.1 фикстуры резолвера зон (8/7 этажей, паритет без позиции)")
	var d2: Dictionary = base.duplicate(true)
	d2["in_cave"] = true
	d2["px"] = 0.0
	d2["py"] = 0.0
	d2["pos_valid"] = false
	d2["area"] = ""
	GameState.from_dict(d2)
	chk(GameState.area == "cave", "R6.2 легаси-флаг пещеры -> cave")
	# R6 живой сейв с локации + resume
	GameState.from_dict(base.duplicate(true))
	w.call("apply_area", "loc_dungeon")
	var ok_in := await _wait_area(w, "loc_dungeon")
	await _fr(30)
	GameState.player_pos = (w.get("player") as Node2D).global_position
	GameState.pos_valid = true
	var sv: bool = bool(GameState.save_game())
	var disk := FileAccess.get_file_as_string("user://save_morkheim.json")
	chk(ok_in and sv and disk.contains("\"area\":\"loc_dungeon\""),
			"R6.3 сейв с локации: зона+флаг в user:// (roundtrip-доказательство)")
	GameState.set_flag("wm.open.snow", "1")
	GameState.save_game()
	GameState.start_fresh_game()
	bool(GameState.load_game())
	chk(String(GameState.area) == "loc_dungeon" and str(GameState.flags.get("wm.open.snow", "")) == "1",
			"R6.4 load: зона loc_dungeon + открытые порталы (wm.open.snow) без потерь")
	w.queue_free()
	await _fr(10)
	var w2 = await _mkworld()
	world = w2
	var ok_res := await _wait_area(w2, "loc_dungeon", 60)
	var want_pos: Vector2 = Vector2(0.0, 43200.0) + ((w2.get("biome_grids") as Dictionary)["dungeon"] as Node).call("spawn_world_pos")
	chk(ok_res and (w2.get("player") as Node2D).global_position.distance_to(want_pos) < 0.01,
			"R6.5 живой resume: локация + точка входа (южная арка подземелья)")
	# мирная цепочка: сейв с карты мира -> resume на мире
	w2.call("apply_area", "worldmap")
	await _wait_area(w2, "worldmap")
	await _fr(20)
	GameState.player_pos = (w2.get("player") as Node2D).global_position
	GameState.pos_valid = true
	GameState.save_game()
	GameState.start_fresh_game()
	bool(GameState.load_game())
	w2.queue_free()
	await _fr(10)
	var w3 = await _mkworld()
	world = w3
	var ok_res2 := await _wait_area(w3, "worldmap", 60)
	var want2: Vector2 = Vector2(0.0, 14400.0) + (w3.get("worldmap_grid") as Node).call("spawn_world_pos")
	chk(ok_res2 and (w3.get("player") as Node2D).global_position.distance_to(want2) < 0.01,
			"R6.6 живой resume: карта мира + позиция входа за аркой")
	_wipe_save()

func _wall_rects(cont: Node) -> Array:
	var out: Array = []
	var base: Vector2 = (cont as Node2D).global_position
	var stack: Array = [cont]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is StaticBody2D) or int(n.collision_layer) & 2 == 0:
			continue
		for cs in n.get_children():
			if not (cs is CollisionShape2D) or not (cs.shape is RectangleShape2D):
				continue
			var sz: Vector2 = (cs.shape as RectangleShape2D).size
			out.append(Rect2((cs as CollisionShape2D).global_position - sz * 0.5 - base, sz))
	return out

func _coverage(rects: Array, w: int, h: int) -> Dictionary:
	var cov := {}
	for r: Rect2 in rects:
		var x0 := int(round(r.position.x / T16))
		var y0 := int(round(r.position.y / T16))
		var x1 := int(round(r.end.x / T16))
		var y1 := int(round(r.end.y / T16))
		for y in range(y0, y1):
			for x in range(x0, x1):
				var k := "%d,%d" % [x, y]
				cov[k] = int(cov.get(k, 0)) + 1
	return cov

# --- R7 утечки нод ---------------------------------------------------------------
func _nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

func _count_mobs(cont: Node) -> int:
	var n := 0
	var stack: Array = [cont]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for c in nd.get_children():
			stack.append(c)
		var scpt: Variant = nd.get_script()
		if scpt == null:
			continue
		var p := String((scpt as Resource).resource_path)
		if p.ends_with("slime.gd") or p.ends_with("brute.gd") or p.ends_with("mob_archer.gd") \
				or p.ends_with("mob_swarmling.gd") or p.ends_with("mob_wraith.gd"):
			n += 1
	return n

func r7_leaks() -> void:
	var w = world
	if w == null:
		chk(false, "R7 нет живого мира")
		return
	w.call("apply_area", "village")
	await _wait_area(w, "village")
	# warm: все зоны построены (R6 их уже построил) — стабильность
	await _fr(30)
	var rounds: Array = []
	for rd in 4:
		for z in ZONES:
			w.call("enter_location", z)
			await _wait_area(w, "loc_" + z)
			await _fr(6)
			w.call("exit_location")
			await _wait_area(w, "worldmap")
			await _fr(6)
		await _fr(40)  # устоять отложенным освобождениям твинов/интеракторов
		rounds.append(_nodes())
		print("WREG leak round %d nodes=%d" % [rd, rounds[rd]])
	w.call("apply_area", "village")
	await _wait_area(w, "village")
	await _fr(20)
	# раунд 0 — прогрев (первые входы: тосты/хинты/чекпоинт-сейвы), сравниваем 1..3
	var d1: int = int(rounds[2]) - int(rounds[1])
	var d2: int = int(rounds[3]) - int(rounds[2])
	chk(d1 == 0 and d2 == 0, "R7.1 туда-обратно x6 локаций (раунды 1..3 прогреты): дельта нод %d/%d == 0" % [d1, d2])
	var snow = (w.get("biome_grids") as Dictionary).get("snow", null)
	var meta_arr: Array = (_loc(RUN_SEED, "snow") as Dictionary)["meta"]["mobs"] as Array
	var live_n := _count_mobs((w.get("biome_zone_cont") as Dictionary)["snow"])
	chk(live_n == meta_arr.size() and snow != null,
			"R7.2 мобы не накапливаются: снег %d == бестиарий %d" % [live_n, meta_arr.size()])

# --- R8 перф ----------------------------------------------------------------------
func _harvest(arr: Array, n: int) -> void:
	for _i in n:
		await get_tree().process_frame
		arr.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)

func _med(arr: Array) -> float:
	if arr.is_empty():
		return 1e12
	var s: Array = arr.duplicate()
	s.sort()
	return float(s[int(s.size() / 2)])

## Замер одного кадра-окна: перевод мира в зону + N кадров PROCESS_TIME (мкс).
func _probe(area: String, n: int) -> Array:
	world.call("apply_area", area)
	await get_tree().process_frame
	var arr: Array = []
	await _harvest(arr, n)
	return arr

## База v5.1 для одного окна: МАКС по смежным замерам деревни, раунды-сталлы
## (медиана > 2 x медузы деревенского пула) отсеиваются; если сталловые оба —
## берём медузу пула (пусть лучше будет честный красный, чем зелёная ложь).
func _village_base(before: Array, after: Array, pool_med: float) -> float:
	var best := 0.0
	for a in [before, after]:
		var m: float = _med(a)
		if m > 2.0 * pool_med:
			continue
		best = maxf(best, m)
	return best if best > 0.0 else pool_med

func r8_perf() -> void:
	var w = world
	if w == null:
		chk(false, "R8 нет живого мира")
		return
	await _fr(60)
	var N := 80
	# Метод R8.1 — v5.1 (26.11.2026, бэклог t40), тот же, что в perf_world.gd;
	# ИСТОРИЯ МЕТОДА (полная — в шапке perf_world.gd):
	#   v1 (t3)  — медиана пула 4 зон, прогрева не было;
	#   v2 (t10) — warm-up-круг 240 кадров на зону;
	#   v3 (t10) — интерливинг зон, медиана пула, порог 1.3 (контракт перф-
	#              допуска; не двигался ни в v3, ни в v5.2);
	#   v4 (пара «деревня+зона», худший раунд) — откатана: 60-кадровые окна
	#              шумят сильнее (1.08-2.23 при равных деревне медузах);
	#   v5 (26.11, t27) — знаменатель = МАКС по раундам медианы деревни: медуза
	#              деревни бимодальна и квантована вертикалкой (плато ~17,8 мс
	#              или ~25,5 мс при ТОМ ЖЕ коде), поэтому быстрое плато само
	#              рождало красный;
	#   v5.1 (26.11, t27 в perf_world / t40 здесь) — из базы отсекаются
	#              раунды-сталлы (медиана раунда > 2 x медузы деревенского
	#              пула): чистый max менял ложные красные на ложные зелёные
	#              (один раунд 66891 мкс раздувал базу втрое, ratio падал до
	#              0.47 при честных ~1.2).
	# Сюда метод приехал потому, что R8.1 была последней плато-жертвой батареи:
	# 26.11 три красных подряд под нагрузкой (1.36/1.39/2.27) и зелёные в тишине.
	#   v5.2 (здесь, 26.11, та же пена) — чистый v5.1 в нагруженном окне ПРОВАЛИЛСЯ
	#              (эксперимент t40: второй живой world-sim рядом, ratio 1.57;
	#              раунды деревни 36048/23842/34655 — помеха приходит
	#              асимметрично: деревня меряется в тихую секунду, зона — в пик).
	#              Поэтому база берётся не «по раундам вообще», а по ДВУМ ЗАМЕРАМ
	#              ДЕРЕВНИ, ОБРАМЛЯЮЩИМ ИЗМЕРЕНИЕ ЗОНЫ (до и сразу после): та же
	#              пара «max + отсев сталлов», но знаменатель живёт в том же
	#              временном окне, что и числитель. Это не v4: окна по-прежнему
	#              N=80 кадров (не 60) и медуза, а не худший кадр.
	# Раундов 2: плечо «обрамление x 7 зон» дороже одинарного круга, а max по
	# смежным замерам не нуждается в длинной истории. Числитель (медиана худшей
	# зоны) и порог 1.3 не тронуты; имя проверки не тронуто, чтобы не ломать
	# разбор логов.
	var ROUNDS := 2
	var zones := ["worldmap", "loc_snow", "loc_desert", "loc_steppe", "loc_forest", "loc_castle", "loc_dungeon"]
	var village_pool: Array = []
	var zone_med := {}          # зона -> худшая (max) медуза по раундам
	for z in zones:
		zone_med[z] = 0.0
	var ratio := 0.0
	var worstz := ""
	var brackets: Array = []
	for rd in ROUNDS:
		for z in zones:
			var vb: Array = await _probe("village", N)
			var zm: Array = await _probe(String(z), N)
			var va: Array = await _probe("village", N)
			village_pool.append_array(vb)
			village_pool.append_array(va)
			var pv: float = _med(village_pool)
			var base: float = _village_base(vb, va, pv)
			var m: float = _med(zm)
			zone_med[z] = maxf(float(zone_med[z]), m)
			var r: float = m / maxf(base, 0.5)
			brackets.append("%s r%.0f/%.1f=%.2f" % [String(z), rd, m, r])
			if r > ratio:
				ratio = r
				worstz = String(z)
	w.call("apply_area", "village")
	await _wait_area(w, "village")
	for z in zones:
		print("WREG perf %s med=%.1f мкс" % [z, float(zone_med[z])])
	print("WREG perf v5.2: деревня медуза=%.1f (пул %d кадров); поплечо (зона раунд/медуза=отношение): %s" % [
			_med(village_pool), village_pool.size(), " ".join(PackedStringArray(brackets))])
	chk(ratio <= 1.3, "R8.1 кадр худшей зоны (%s) к деревне = %.2f <= 1.3" % [worstz, ratio])
	# генерация: warm-up стабильность x1.1 + бюджет
	var t0 := Time.get_ticks_usec()
	OWg.composition(4242)
	var g1 := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	OWg.composition(4242)
	var g2 := Time.get_ticks_usec() - t0
	var gen_ratio: float = float(maxi(g1, g2)) / float(maxi(mini(g1, g2), 1))
	var wm_ms := 0.0
	t0 = Time.get_ticks_usec()
	OWg.worldmap_map(999)
	wm_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	print("WREG perf gen comp=%d/%d мкс ratio=%.2f wm=%.1fмс" % [g1, g2, gen_ratio, wm_ms])
	chk(gen_ratio <= 1.1, "R8.2 генерация composition: warm-up стабильность %.2f <= 1.1" % gen_ratio)
	chk(wm_ms <= 400.0, "R8.3 генерация карты мира %.1f мс <= 400 (бюджет ленивой сборки)" % wm_ms)
	# аллокации на покое: две идущие подряд сессии простоя на карте мира
	w.call("apply_area", "worldmap")
	await _wait_area(w, "worldmap")
	await _fr(120)  # дли устой: отложенные освобождения переходов R8 не попадают в окно
	var n0 := _nodes()
	var r0 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	await _fr(120)
	var n1 := _nodes()
	var r1 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	chk(n1 == n0 and r1 == r0, "R8.4 аллокации на покое мира: дельта нод/ресурсов %d/%d == 0" % [n1 - n0, r1 - r0])

# --- R9 кадры (PNG-схемы) ----------------------------------------------------------
func r9_frames() -> void:
	var out := OS.get_environment("QA_WREG_OUT")
	if out == "" or not DirAccess.dir_exists_absolute(out):
		print("WREG frames: QA_WREG_OUT не задан — схемы пропущены")
		return
	var s := _seed(0)
	var wm: Dictionary = _wm(s)
	_save_schematic(out + "/wm_%d.png" % s, (wm["meta"] as Dictionary), (wm["grid"] as Array))
	for z in ZONES:
		var m: Dictionary = _loc(s, z)
		_save_schematic(out + "/loc_%s_%d.png" % [z, s], (m["meta"] as Dictionary), (m["grid"] as Array))
	print("WREG frames записаны в %s" % out)

func _save_schematic(path: String, meta: Dictionary, grid: Array) -> void:
	var h := grid.size()
	var w := String(grid[0]).length()
	var im := Image.create(w * T16, h * T16, false, Image.FORMAT_RGBA8)
	im.fill(Color(0.10, 0.11, 0.13))
	for y in h:
		for x in w:
			var c := Color(0.55, 0.60, 0.35)
			var ch := String(grid[y])[x]
			match ch:
				"#": c = Color(0.20, 0.22, 0.26)
				"M", "W", "C": c = Color(0.13, 0.14, 0.17)
				"s": c = Color(0.83, 0.88, 0.94)
				"d": c = Color(0.88, 0.74, 0.50)
				"c": c = Color(0.52, 0.52, 0.58)
				"u": c = Color(0.42, 0.30, 0.52)
				"f": c = Color(0.24, 0.42, 0.24)
				"-": c = Color(0.78, 0.68, 0.48)
				"p": c = Color(0.95, 0.83, 0.20)
				"a": c = Color(0.90, 0.20, 0.20)
				"i": c = Color(0.70, 0.85, 0.95)
				"g": c = Color(0.45, 0.85, 0.75)
				"w": c = Color(0.20, 0.45, 0.85)  # «Среда v1» (25.11): вода — схема переснята
			for dy in T16:
				for dx in T16:
					im.set_pixel(x * T16 + dx, y * T16 + dy, c)
	var marks := [["spawn", Color(0.2, 1.0, 0.3)], ["arch", Color(1.0, 0.4, 0.2)], ["chest", Color(1.0, 0.2, 0.9)]]
	for mk in marks:
		if meta.has(String(mk[0])):
			var pt: Array = meta[mk[0]]
			_stamp_marker(im, int(pt[0]), int(pt[1]), mk[1])
	if meta.has("portals"):
		for z in (meta["portals"] as Dictionary):
			var pt2: Array = (meta["portals"] as Dictionary)[z]
			_stamp_marker(im, int(pt2[0]), int(pt2[1]), Color(1.0, 1.0, 0.3))
	if meta.has("portal_out"):
		var po: Array = meta["portal_out"]
		_stamp_marker(im, int(po[0]), int(po[1]), Color(0.3, 0.9, 1.0))
	var e := im.save_png(path)
	if e != OK:
		print("WREG frame save fail %s (%d)" % [path, e])

func _stamp_marker(im: Image, cx: int, cy: int, c: Color) -> void:
	var ox := cx * T16 + 6
	var oy := cy * T16 + 6
	for dy in range(0, 4):
		for dx in range(0, 4):
			im.set_pixel(ox + dx, oy + dy, c)
