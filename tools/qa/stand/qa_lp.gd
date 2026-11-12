extends Node2D
## QA-стенд Т14 «крупные пропы вписаны в пространство» (пещера/Пепелище).
## Прогон: godot --headless res://qa_lp.tscn
## Пин-сид забега 42 (как qa_z1). Проверяет пост-процесс сеток world._reshape_*
## (залы алтарей/портала, проходы ≥2 клетки) С НЕЗАВИСИМОЙ геометрией: BFS/2×2
## переписаны здесь, а не вызываются из world.gd (зеркальная реализация).
##  T1  таблицы символов бит-в-бит + монотонность перестройки против свежего
##      генераторного dict (только dig-символы -> ".", якоря/рамка целы).
##  T2  зал алтаря 5x6 (x±2, y-3..y+2): в верхних рядах нет стен (кроме
##      защищённой ниши сундука); ранг не тронут; ширина пропов ≤ 5*16.
##  T3  все POI пещеры достижимы из spawn BFS с открытой дверью; сундук и
##      алтари НЕ достижимы с закрытой (гейт двери сохранён).
##  T4  Пепелище: монотонность, зал портала 5x6 (x±2, y-4..y+1), якорь=клетка P.
##  T5  проходы: каждая проходимая клетка обеих зон лежит в проходимом 2x2
##      ИЛИ вскрытие легально невозможно (тупик у рамки/защиты).
##  T6  детерминизм: два мира на сиде 42 — бит-в-бит сетки и дампы слоёв
##      живого пола (текстура/позиция/альфа/поворот); alpha ∈ [0.30,0.42];
##      fail-safe: пустой набор ассетов -> слой не создаётся.
##  T7  SCALE_CANON на рантайме: ЭКРАННЫЕ altar 51, portal 70, boulder 26, stones
##      32 px (Т15/Т15b: алтарь/портал — текстуры >=3× экранных (полный кроп
##      1024-исходника) со scale-компенсацией от фактической высоты,
##      LINEAR_WITH_MIPMAPS и mips/generate=true; прочие пропы scale 1.0).
##  T8  физ-проба: в центре КАЖДОЙ проходимой клетки обеих зон нет статических
##      коллайдеров (сетка <-> коллайдеры после перестройки согласованы).
##  T9  soak 2x5 сек (пещера+Пепелище, враги сняты): герой не застревает в
##      стенах (>30 кадров в блокирующей клетке), не вылетает за карту.
##  T10 миникарта: размер сетки-подложки = размер текущей зоны (динамический
##      пересчёт, не пиксель — пиксельные сигнатуры сверяет qa_mm).
##  T11 t17 «живая стилистика»: герой и бестиарий — ген-ассеты (полный кроп
##      1024-оригинала, RGBA8 >256 цветов, без квантизации), MD5-пины,
##      LINEAR_WITH_MIPMAPS + полная мип-цепочка, ЭКРАННЫЕ высоты/линии стоп
##      по канону t12 на живых объектах; Тенеплёт (wraith) не интегрирован.
##  T12 t18 «сочность»: hitstop конечен и возвращает Engine.time_scale в
##      РЕАЛЬНОМ времени (обычный и смертельный удар), вспышки цели ≤0.1 с,
##      overshoot цифр 1.3 (qa_dn зелёный), тень по высоте актёра + воздушная
##      фаза «Рывка вепря», «дыхание» env4-пропов (JuiceLight: алтарь/портал/
##      сундук, спрайты неподвижны), шлейф кувырка, красный виньеточный импульс.

const Main := "res://scenes/main.tscn"
const WS := preload("res://scripts/world.gd")
const SAVE_PATH := "user://save_morkheim.json"
const PIN_SEED := 42

const CAVE_WALK := ".,SBM"
const CAVE_DIG := "#PRV"
const ASHEN_WALK := ".,caP"
const ASHEN_DIG := "#TK"
const PIN_CAVE_CT := {".": 0, ",": 1, "#": 2, "L": 3, "S": 5, "P": 6, "R": 7,
	"B": 8, "M": 9, "A": 10, "C": 11, "V": 15}
const PIN_CAVE_BLK := [2, 3, 6, 7, 10, 11, 15]
const PIN_ASHEN_CT := {".": 0, ",": 1, "c": 2, "a": 3, "T": 4, "K": 5, "#": 6, "P": 7}
const PIN_ASHEN_BLK := [4, 5, 6]

var pass_n := 0
var fail_n := 0
var world: Node2D
var _ash_meta: Dictionary = {}

func chk(cond: bool, name: String) -> void:
	if cond:
		pass_n += 1
		print("qa_lp ok: ", name)
	else:
		fail_n += 1
		print("qa_lp FAIL: ", name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	GameState.seen_cave_intro = true
	GameState.flags["ashen.intro_seen"] = "1"
	await _frames(2)
	world = await _spawn_world()
	var cave_raw: Dictionary = ProcGen.cave_map(ProcGen.seed_zone(PIN_SEED, "cave", 0))
	var ashen_raw: Dictionary = ProcGen.ashen_map(ProcGen.seed_zone(PIN_SEED, "ashen", 0))
	_ash_meta = ashen_raw.get("meta", {})
	var snap1: String = _snapshot(world)
	_t1(cave_raw, ashen_raw)
	_t2(cave_raw)
	_t3()
	_t4(ashen_raw)
	_t5()
	await _t6(snap1)
	_t7()
	await _t8()
	await _t9()
	_t10()
	_t11()
	await _t12()
	var total: int = pass_n + fail_n
	print("QA_LP %d/%d" % [pass_n, total])
	get_tree().quit(0 if fail_n == 0 else 1)

func _spawn_world() -> Node2D:
	GameState.run_seed = PIN_SEED
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var w: Node2D = load(Main).instantiate()
	add_child(w)
	await _frames(3)
	return w

# ----------------------------------------------------------- helpers (независимые)

func _ch(rows: Array, x: int, y: int) -> String:
	if y < 0 or y >= rows.size():
		return ""
	var row := String(rows[y])
	if x < 0 or x >= row.length():
		return ""
	return row[x]

func _walk(ch: String, set: String) -> bool:
	return set.find(ch) >= 0

## Защищённая ниша сундука: BFS от «C» без «L» + настенная рамка (8-соседи).
func _protect(rows: Array, walk: String) -> Dictionary:
	var prot := {}
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if row[x] != "C":
				continue
			var seen := {y * 4096 + x: true}
			var stack: Array = [Vector2i(x, y)]
			while not stack.is_empty():
				var t: Vector2i = stack.pop_back()
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var n := t + Vector2i(int(d[0]), int(d[1]))
					var k := n.y * 4096 + n.x
					if seen.has(k):
						continue
					var c := _ch(rows, n.x, n.y)
					if c != "C" and not _walk(c, walk):
						continue
					seen[k] = true
					stack.append(n)
			for k in seen:
				prot[k] = true
				var cx := int(k) % 4096
				var cy := int(k) >> 12
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]:
					if _ch(rows, cx + int(d[0]), cy + int(d[1])) == "#":
						prot[(cy + int(d[1])) * 4096 + cx + int(d[0])] = true
	return prot

## Интерьеры ниш сундука: по одному Dictionary (ключи клеток) на каждую «C» —
## BFS без «L» (стены и дверь непроходимы).
func _chest_interiors(rows: Array) -> Array:
	var out: Array = []
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if row[x] != "C":
				continue
			var seen := {y * 4096 + x: true}
			var stack: Array = [Vector2i(x, y)]
			while not stack.is_empty():
				var t: Vector2i = stack.pop_back()
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var n := t + Vector2i(int(d[0]), int(d[1]))
					var k := n.y * 4096 + n.x
					if seen.has(k):
						continue
					var c := _ch(rows, n.x, n.y)
					if c == "#" or c == "L" or c == "":
						continue
					seen[k] = true
					stack.append(n)
			out.append(seen)
	return out

func _has2x2(rows: Array, x: int, y: int, walk: String) -> bool:
	for a in [0, 1]:
		for b in [0, 1]:
			var ok := true
			for dy in 2:
				for dx in 2:
					if not _walk(_ch(rows, x - a + dx, y - b + dy), walk):
						ok = false
			if ok:
				return true
	return false

func _feas2x2(rows: Array, x: int, y: int, walk: String, dig: String, prot: Dictionary) -> bool:
	var h := rows.size()
	for a: int in [0, 1]:
		for b: int in [0, 1]:
			var bad := false
			for dy: int in 2:
				for dx: int in 2:
					var cx := x - a + dx
					var cy := y - b + dy
					var w := String(rows[cy]).length() if cy >= 0 and cy < h else 0
					if cx <= 0 or cy <= 0 or cx >= w - 1 or cy >= h - 1:
						bad = true
					var c := _ch(rows, cx, cy)
					if not _walk(c, walk) and (dig.find(c) < 0 or prot.has(cy * 4096 + cx)):
						bad = true
			if not bad:
				return true
	return false

## BFS от клетки; door_open=true считает «L» проходимой. Возвращает set ключей.
func _bfs(rows: Array, start: Vector2i, walk: String, door_open: bool) -> Dictionary:
	var seen := {}
	if not (_walk(_ch(rows, start.x, start.y), walk) or (door_open and _ch(rows, start.x, start.y) == "L")):
		return seen
	seen = {start.y * 4096 + start.x: true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var t: Vector2i = queue[head]
		head += 1
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var n := t + Vector2i(int(d[0]), int(d[1]))
			var k := n.y * 4096 + n.x
			if seen.has(k):
				continue
			var c := _ch(rows, n.x, n.y)
			var ok := _walk(c, walk) or (door_open and c == "L")
			if not ok:
				continue
			seen[k] = true
			queue.append(n)
	return seen

func _cell_of_ach(rows: Array, ch: String) -> Array:
	var out: Array = []
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if row[x] == ch:
				out.append(Vector2i(x, y))
	return out

func _reach_adj(reach: Dictionary, rows: Array, t: Vector2i, walk: String) -> bool:
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [0, 0]]:
		var n := t + Vector2i(int(d[0]), int(d[1]))
		if reach.has(n.y * 4096 + n.x):
			return true
	return false

# ------------------------------------------------------------------ снимки

func _paint_dump(w: Node2D, zone: Node2D, layer_name: String) -> String:
	var layer = zone.get_node_or_null(NodePath(layer_name))
	if layer == null:
		return layer_name + ":ABSENT"
	var s := layer_name + ":z=%d,ys=%s,n=%d;" % [layer.z_index, str(layer.y_sort_enabled), layer.get_child_count()]
	for c in layer.get_children():
		var spr := c as Sprite2D
		if spr == null:
			s += "NOTSPRITE;"
			continue
		s += "%s|%s|%.3f,%.3f|a=%.4f|r=%.2f|f=%d;" % [
			String(spr.texture.resource_path) if spr.texture != null else "null",
			"", snappedf(spr.position.x, 0.001), snappedf(spr.position.y, 0.001),
			spr.modulate.a, snappedf(spr.rotation, 0.001), int(spr.flip_h)]
	return s

func _snapshot(w: Node2D) -> String:
	var s := "CAVE>"
	for r in w.dungeon_zone.map_rows:
		s += String(r) + "/"
	s += "|ASHEN>"
	for r in w.ashen_grid.map_rows:
		s += String(r) + "/"
	s += "|CP>" + _paint_dump(w, w.cave_zone, "CaveFloorPaint")
	s += "|AP>" + _paint_dump(w, w.ashen_zone, "AshenFloorPaint")
	return s

# ------------------------------------------------------------------ T1

func _t1(cave_raw: Dictionary, ashen_raw: Dictionary) -> void:
	var dz = world.dungeon_zone
	var az = world.ashen_grid
	chk(dz.CHAR_TO_TILE == PIN_CAVE_CT and dz.BLOCKING == PIN_CAVE_BLK,
		"T1: CHAR_TO_TILE/BLOCKING пещеры бит-в-бит")
	chk(az.CHAR_TO_TILE == PIN_ASHEN_CT and az.BLOCKING == PIN_ASHEN_BLK,
		"T1: CHAR_TO_TILE/BLOCKING Пепелища бит-в-бит")
	var raw: Array = cave_raw.get("grid", [])
	var new: Array = dz.map_rows
	chk(raw.size() == new.size() and String(raw[0]).length() == 30 and new.size() == 22,
		"T1: пещера 30x22 сохранена")
	var viol := 0
	var changed := 0
	for y in new.size():
		for x in String(new[y]).length():
			var a: String = String(raw[y])[x]
			var b: String = String(new[y])[x]
			if a != b:
				changed += 1
				if CAVE_DIG.find(a) < 0 or b != ".":
					viol += 1
	chk(viol == 0, "T1: монотонность пещеры (только dig -> .) diff=%d" % changed)
	chk(changed > 0, "T1: пещера реально перестроена (%d клеток)" % changed)
	var anchors_ok := true
	for key: String in ["spawn", "stairs_out", "hermit", "boss", "boss_trigger", "chest", "door"]:
		var a: Array = cave_raw.get(key, [])
		if a.size() != 2:
			continue
		var c0: String = String(raw[int(a[1])])[int(a[0])]
		var c1: String = String(new[int(a[1])])[int(a[0])]
		if c0 != c1:
			anchors_ok = false
			print("   якорь ", key, " сдвинулся: ", c0, "->", c1)
	chk(anchors_ok, "T1: якоря dict пещеры на своих клетках со своими символами")
	var raw_a := _cell_of_ach(raw, "A").size()
	var new_a := _cell_of_ach(new, "A").size()
	chk(raw_a > 0 and raw_a == new_a, "T1: алтари сохранены %d->%d" % [raw_a, new_a])
	# Пепелище
	var araw: Array = ashen_raw.get("grid", [])
	var anew: Array = az.map_rows
	chk(anew.size() == 30 and String(anew[0]).length() == 40, "T1: Пепелище 40x30 сохранено")
	var aviol := 0
	var ach := 0
	for y in anew.size():
		for x in String(anew[y]).length():
			var a2: String = String(araw[y])[x]
			var b2: String = String(anew[y])[x]
			if a2 != b2:
				ach += 1
				if ASHEN_DIG.find(a2) < 0 or b2 != ".":
					aviol += 1
	chk(aviol == 0, "T1: монотонность Пепелища (только dig -> .) diff=%d" % ach)
	chk(ach > 0, "T1: Пепелище реально перестроено (%d клеток)" % ach)
	# рамка
	var border_ok := true
	for zone_rows: Array in [new, anew]:
		var hh := zone_rows.size()
		var ww := String(zone_rows[0]).length()
		for x in ww:
			if String(zone_rows[0])[x] != "#" or String(zone_rows[hh - 1])[x] != "#":
				border_ok = false
		for y in hh:
			var r := String(zone_rows[y])
			if r[0] != "#" or r[r.length() - 1] != "#":
				border_ok = false
	chk(border_ok, "T1: внешний ранг обеих зон — сплошной «#»")
	# сырой пол был проходим -> остался
	var mono_walk := true
	for y in new.size():
		for x in String(new[y]).length():
			var a3: String = String(raw[y])[x]
			if _walk(a3, CAVE_WALK) and not _walk(String(new[y])[x], CAVE_WALK):
				mono_walk = false
	chk(mono_walk, "T1: проходимое пещеры не стало непроходимым")

# ------------------------------------------------------------------ T2

func _t2(cave_raw: Dictionary) -> void:
	var rows: Array = world.dungeon_zone.map_rows
	var prot := _protect(rows, CAVE_WALK)
	var halls_ok := true
	var top_ok := true
	var altar_n := 0
	for t: Vector2i in _cell_of_ach(rows, "A"):
		altar_n += 1
		for dy in range(t.y - 3, t.y + 3):
			for dx in range(t.x - 2, t.x + 3):
				if dx <= 0 or dy <= 0 or dx >= 29 or dy >= 21:
					continue
				if prot.has(dy * 4096 + dx):
					continue
				var c := _ch(rows, dx, dy)
				if CAVE_DIG.find(c) >= 0:
					halls_ok = false
					print("   зал алтаря (", t, "): клетка (", dx, ",", dy, ")=", c)
				if dy < t.y and CAVE_DIG.find(c) >= 0:
					top_ok = false
	# ширина алтаря/камней ≤ 5*16 — ЭКРАННАЯ (Т15/Т15b: алтарь в текстуре высокого
	# разрешения живёт со scale-компенсацией, в зал проверяется картинка на экране, не пиксели файла)
	var altar_tex: Texture2D = load(String(WS.ENV4_ART["altar"]))
	var stones_tex: Texture2D = load(String(WS.ENV4_ART["stones"]))
	chk(halls_ok, "T2: залы алтарей 5x6 без dig-символов (алтарей %d)" % altar_n)
	chk(top_ok, "T2: верхние ряды залов (выше клетки алтаря) без стен")
	var aw := int(ceil(_eff_w(altar_tex)))
	var sw := int(ceil(_eff_w(stones_tex)))
	chk(aw <= 5 * 16, "T2: экранная ширина алтаря %d ≤ 80" % aw)
	chk(sw <= 5 * 16, "T2: экранная ширина камней %d ≤ 80" % sw)

## Экранная ширина пропа: текстуры из ENV4_CANON_H масштабируются в канон.
func _eff_w(tex: Texture2D) -> float:
	var canon: float = float(WS.ENV4_CANON_H.get(String(tex.resource_path), 0.0))
	if canon > 0.0:
		return float(tex.get_width()) * canon / float(tex.get_height())
	return float(tex.get_width())

# ------------------------------------------------------------------ T3

func _t3() -> void:
	var dz = world.dungeon_zone
	var rows: Array = dz.map_rows
	var spawn := Vector2i(int(dz.loaded_map["spawn"][0]), int(dz.loaded_map["spawn"][1]))
	GameState.door_opened = true
	var open_reach := _bfs(rows, spawn, CAVE_WALK, true)
	GameState.door_opened = false
	var closed_reach := _bfs(rows, spawn, CAVE_WALK, false)
	chk(open_reach.has(spawn.y * 4096 + spawn.x), "T3: spawn проходим")
	var stairs: Array = dz.loaded_map.get("stairs_out", [])
	if stairs.size() == 2:
		chk(open_reach.has(int(stairs[1]) * 4096 + int(stairs[0])), "T3: лестница выхода достижима (door open)")
	var alt_ok := true
	for t: Vector2i in _cell_of_ach(rows, "A"):
		if not _reach_adj(open_reach, rows, t, CAVE_WALK):
			alt_ok = false
			print("   алтарь (", t, ") недостижим")
	chk(alt_ok, "T3: все алтари достижимы (door open)")
	var ct: Vector2i = dz.chest_tile
	chk(ct.x >= 0 and _reach_adj(open_reach, rows, ct, CAVE_WALK), "T3: сундук достижим с открытой дверью")
	chk(not _reach_adj(closed_reach, rows, ct, CAVE_WALK), "T3: сундук НЕдостижим с закрытой дверью (гейт)")
	var alt_in_niche_closed := true
	var niches := _chest_interiors(rows)
	for interior in niches:
		var openings: Array = []
		for k in interior.keys():
			var cx := int(k) % 4096
			var cy := int(k) >> 12
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx := cx + int(d[0])
				var ny := cy + int(d[1])
				var nk := ny * 4096 + nx
				if interior.has(nk):
					continue
				var c := _ch(rows, nx, ny)
				if c != "#" and not (openings.size() > 0 and openings[0] == nk):
					if not openings.has(nk):
						openings.append(nk)
		var door_ok := openings.size() == 1 and _ch(rows, int(openings[0]) % 4096, int(openings[0]) >> 12) == "L"
		chk(door_ok, "T3: ниша сундука — единственный проём это дверь «L» (проёмов %d)" % openings.size())
		for t: Vector2i in _cell_of_ach(rows, "A"):
			if interior.has(t.y * 4096 + t.x) and _reach_adj(closed_reach, rows, t, CAVE_WALK):
				alt_in_niche_closed = false
	chk(alt_in_niche_closed, "T3: алтари внутри ниши закрыты дверью")
	var boss: Array = dz.loaded_map.get("boss", [])
	if boss.size() == 2:
		chk(_reach_adj(open_reach, rows, Vector2i(int(boss[0]), int(boss[1])), CAVE_WALK),
			"T3: клетка босса достижима (door open)")

# ------------------------------------------------------------------ T4

func _t4(ashen_raw: Dictionary) -> void:
	var az = world.ashen_grid
	var rows: Array = az.map_rows
	var raw: Array = ashen_raw.get("grid", [])
	var meta: Dictionary = ashen_raw.get("meta", {})
	var pa: Array = meta.get("exit_portal", [])
	chk(pa.size() == 2, "T4: якорь exit_portal есть")
	if pa.size() != 2:
		return
	var pt := Vector2i(int(pa[0]), int(pa[1]))
	chk(_ch(rows, pt.x, pt.y) == "P", "T4: якорь портала = клетка «P» (%s)" % str(pt))
	var prot := _protect(rows, ASHEN_WALK)
	var hall_ok := true
	for dy in range(pt.y - 4, pt.y + 2):
		for dx in range(pt.x - 2, pt.x + 3):
			if dx <= 0 or dy <= 0 or dx >= 39 or dy >= 29:
				continue
			if prot.has(dy * 4096 + dx):
				continue
			if ASHEN_DIG.find(_ch(rows, dx, dy)) >= 0:
				hall_ok = false
				print("   зал портала: (", dx, ",", dy, ")=", _ch(rows, dx, dy))
	chk(hall_ok, "T4: зал портала 5x6 без dig-символов")
	var portal_tex: Texture2D = load(String(WS.ENV4_ART["portal"]))
	var pw := int(ceil(_eff_w(portal_tex)))  # Т15/Т15b: экранная ширина (текст высокого разр. + scale)
	chk(pw <= 5 * 16, "T4: экранная ширина портала %d ≤ 80" % pw)
	# POI Пепелища: spawn/портал/сундук/ведьма (meta генераторного dict — reshape
	# его не двигает; ashen_zone dict не хранит)
	var m: Dictionary = meta
	var sp: Array = m.get("spawn", [])
	if sp.size() == 2:
		var s0 := Vector2i(int(sp[0]), int(sp[1]))
		var reach := _bfs(rows, s0, ASHEN_WALK, true)
		chk(reach.has(pt.y * 4096 + pt.x), "T4: портал достижим из spawn")
		var b: Array = m.get("boss", [])
		if b.size() == 2:
			chk(_reach_adj(reach, rows, Vector2i(int(b[0]), int(b[1])), ASHEN_WALK), "T4: арена ведьмы достижима")
		var ch_list: Array = m.get("chests", [])
		var chests_ok := true
		for e: Array in ch_list:
			if not _reach_adj(reach, rows, Vector2i(int(e[0]), int(e[1])), ASHEN_WALK):
				chests_ok = false
		chk(chests_ok, "T4: сундук(и) Пепелища достижимы")

# ------------------------------------------------------------------ T5

func _t5() -> void:
	for spec: Array in [[world.dungeon_zone.map_rows, CAVE_WALK, CAVE_DIG, "пещера"],
			[world.ashen_grid.map_rows, ASHEN_WALK, ASHEN_DIG, "Пепелище"]]:
		var rows: Array = spec[0]
		var prot := _protect(rows, String(spec[1]))
		var bad := 0
		var legal_dead := 0
		for y in rows.size():
			for x in String(rows[y]).length():
				if not _walk(_ch(rows, x, y), String(spec[1])):
					continue
				if _has2x2(rows, x, y, String(spec[1])):
					continue
				if _feas2x2(rows, x, y, String(spec[1]), String(spec[2]), prot):
					bad += 1
					print("   ", spec[3], ": клетка (", x, ",", y, ") в тупике, хотя вскрывать можно")
				else:
					legal_dead += 1
		chk(bad == 0, "T5: %s — проходы ≥2 (легальных тупиков %d)" % [spec[3], legal_dead])

# ------------------------------------------------------------------ T6

func _t6(snap1: String) -> void:
	var layer_c = world.cave_zone.get_node_or_null("CaveFloorPaint")
	var layer_a = world.ashen_zone.get_node_or_null("AshenFloorPaint")
	chk(layer_c != null and layer_c.get_child_count() > 0, "T6: CaveFloorPaint построен (%d)" % (layer_c.get_child_count() if layer_c != null else -1))
	chk(layer_a != null and layer_a.get_child_count() > 0, "T6: AshenFloorPaint построен (%d)" % (layer_a.get_child_count() if layer_a != null else -1))
	var alpha_ok := true
	var lin_ok := true
	for layer: Node2D in [layer_c, layer_a]:
		if layer == null:
			continue
		for c in layer.get_children():
			var spr := c as Sprite2D
			if spr == null:
				continue
			if spr.modulate.a < 0.299 or spr.modulate.a > 0.4201:
				alpha_ok = false
			if spr.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
				lin_ok = false
	chk(alpha_ok, "T6: alpha патчей ∈ [0.30, 0.42]")
	chk(lin_ok, "T6: все патчи LINEAR")
	# fail-safe: несуществующие ассеты -> слой не создаётся
	var probe := Node2D.new()
	add_child(probe)
	var fake_rows: Array = ["....", "...."]
	world._build_zone_floor_paint(probe, fake_rows, ["res://assets/art/__нет_такого__.png"], "X")
	chk(probe.get_child_count() == 0, "T6: fail-safe — без ассетов слой не создаётся")
	probe.queue_free()
	# второй мир — тот же сид: снимок бит-в-бит
	world.queue_free()
	await _frames(5)
	world = null
	world = await _spawn_world()
	var snap2: String = _snapshot(world)
	chk(snap2 == snap1, "T6: детерминизм — два мира идентичны (grid+floor paint dump)")

# ------------------------------------------------------------------ T7

func _t7() -> void:
	# Т15/Т15b «миниатюрная картина»: алтарь/портал — текстуры высокого
	# разрешения (>=3× экранных), ЭКРАННЫЕ высоты по-прежнему канон 51/70
	# (scale-компенсация в _env4_place от фактической высоты),
	# фильтр LINEAR_WITH_MIPMAPS и мипы в импорте; прочие пропы — как жили
	# (scale 1.0, LINEAR). Проектный default_texture_filter=0 не тронут.
	var altar: Texture2D = load(String(WS.ENV4_ART["altar"]))
	var portal: Texture2D = load(String(WS.ENV4_ART["portal"]))
	var boulder: Texture2D = load(String(WS.ENV4_ART["boulder"]))
	var stones: Texture2D = load(String(WS.ENV4_ART["stones"]))
	chk(altar.get_height() >= 3 * 51, "T7: altar texture_h=%d ≥ 3×экранной (51)" % altar.get_height())
	chk(portal.get_height() >= 3 * 70, "T7: portal texture_h=%d ≥ 3×экранной (70)" % portal.get_height())
	chk(boulder.get_height() == 26, "T7: boulder drawn_h=26")
	chk(stones.get_height() == 32, "T7: stones drawn_h=32")
	var eff_ok := true    # экранная высота 51/70 на живых спрайтах
	var filt_ok := true   # LINEAR_WITH_MIPMAPS на этих двух
	var plain_ok := true  # остальные: scale 1.0 и прежний LINEAR
	var n_altar := 0
	var n_portal := 0
	for layer_name: String in ["Env4CaveProps", "Env4AshenProps"]:
		for zone: Node2D in [world.cave_zone, world.ashen_zone]:
			var l = zone.get_node_or_null(NodePath(layer_name))
			if l == null:
				continue
			for c in l.get_children():
				var spr := c as Sprite2D
				if spr == null or spr.texture == null:
					continue
				var p := String(spr.texture.resource_path)
				if p.ends_with("env4_altar.png"):
					n_altar += 1
					if absf(float(spr.texture.get_height()) * spr.scale.y - 51.0) > 0.05:
						eff_ok = false
					if spr.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
						filt_ok = false
				elif p.ends_with("env4_portal.png"):
					n_portal += 1
					if absf(float(spr.texture.get_height()) * spr.scale.y - 70.0) > 0.05:
						eff_ok = false
					if spr.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
						filt_ok = false
				else:
					if spr.scale != Vector2.ONE or spr.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
						plain_ok = false
	chk(n_altar >= 5 and eff_ok, "T7: экранные алтари (5 шт.) — высота 51 px, scale скомпенсирован")
	chk(n_portal >= 1, "T7: портал в сцене (%d)" % n_portal)
	chk(filt_ok, "T7: спрайты алтаря/портала — TEXTURE_FILTER_LINEAR_WITH_MIPMAPS")
	chk(plain_ok, "T7: прочие пропы env4 не тронуты (scale 1.0, LINEAR)")
	var ai: Array = _ctex_mip_info(String(WS.ENV4_ART["altar"]))
	var pi: Array = _ctex_mip_info(String(WS.ENV4_ART["portal"]))
	var bi: Array = _ctex_mip_info(String(WS.ENV4_ART["boulder"]))
	var am: int = int(ai[2]) if ai.size() == 3 else -1
	var pm: int = int(pi[2]) if pi.size() == 3 else -1
	var bm: int = int(bi[2]) if bi.size() == 3 else -1
	# полная мип-цепочка: полных дополнительных уровней floor(log2(max_side));
	# для канона 3× это уже >=7 (как в t15), для полного разрешения — больше
	var need_a: int = int(floor(log(float(maxi(altar.get_width(), altar.get_height()))) / log(2.0)))
	var need_p: int = int(floor(log(float(maxi(portal.get_width(), portal.get_height()))) / log(2.0)))
	var mip_ok: bool = ai.size() == 3 and pi.size() == 3 and bi.size() == 3 and \
		int(ai[0]) == altar.get_width() and int(ai[1]) == altar.get_height() and \
		int(pi[0]) == portal.get_width() and int(pi[1]) == portal.get_height() and \
		am >= need_a and pm >= need_p and bm == 0
	chk(mip_ok, "T7: мип-цепочка полная в .ctex (altar доп.мипов=%d≥%d, portal=%d≥%d, boulder-контроль=%d)" % [am, need_a, pm, need_p, bm])
	var imp_ok := true
	for key: String in ["altar", "portal"]:
		var ipath := String(WS.ENV4_ART[key]) + ".import"
		var f := FileAccess.open(ipath, FileAccess.READ)
		if f == null:
			imp_ok = false
			print("   QA_LP: не читается %s" % ipath)
			continue
		var t := f.get_as_text()
		f.close()
		if not t.contains("mipmaps/generate=true"):
			imp_ok = false
			print("   QA_LP: в %s нет mipmaps/generate=true" % ipath)
	chk(imp_ok, "T7: .import алтаря/портала — mipmaps/generate=true")
	var dflt: int = int(ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter"))
	chk(dflt == 0, "T7: проектный default_texture_filter=0 (nearest) не изменён")

# Читает из заголовка импортированного .ctex (CompressedTexture2D, Godot 4.7.2):
# LE uint32 [@8]=ширина, [@12]=высота, [@44]=число ДОПОЛНИТЕЛЬНЫХ мип-уровней
# (0 — мипов нет). Возвращает [w, h, extra_mips] или [] при неудаче.
# Самовалидация парсера у вызывающего: w/h должны совпасть с текстурой.
func _ctex_mip_info(tex_path: String) -> Array:
	var dir := DirAccess.open("res://.godot/imported")
	if dir == null:
		return []
	var base: String = tex_path.get_file()
	for f in dir.get_files():
		var fn := String(f)
		if not fn.begins_with(base + "-") or not fn.ends_with(".ctex"):
			continue
		var fa := FileAccess.open("res://.godot/imported/" + fn, FileAccess.READ)
		if fa == null:
			return []
		var b := fa.get_buffer(48)
		fa.close()
		if b.size() < 48:
			return []
		var w: int = int(b[8]) | (int(b[9]) << 8) | (int(b[10]) << 16) | (int(b[11]) << 24)
		var h: int = int(b[12]) | (int(b[13]) << 8) | (int(b[14]) << 16) | (int(b[15]) << 24)
		var m: int = int(b[44]) | (int(b[45]) << 8) | (int(b[46]) << 16) | (int(b[47]) << 24)
		return [w, h, m]
	return []

# ------------------------------------------------------------------ T8

func _probe_zone(zone: Node2D, rows: Array, walk: String) -> int:
	var bad := 0
	var space := get_world_2d().direct_space_state
	for y in rows.size():
		for x in String(rows[y]).length():
			if not _walk(_ch(rows, x, y), walk):
				continue
			var q := PhysicsPointQueryParameters2D.new()
			q.position = Vector2(x * 16 + 8, y * 16 + 8) + zone.position
			q.collision_mask = 2
			q.collide_with_bodies = true
			var hits := space.intersect_point(q, 4)
			var wall := false
			for h in hits:
				var col: Object = h.get("collider")
				if col is StaticBody2D and zone.is_ancestor_of(col as Node):
					wall = true
			if wall:
				bad += 1
				if bad <= 5:
					print("   физ-проба: клетка (", x, ",", y, ") проходима по grid, но в стене-коллайдере")
	return bad

func _t8() -> void:
	var bad_c := _probe_zone(world.cave_zone, world.dungeon_zone.map_rows, CAVE_WALK)
	chk(bad_c == 0, "T8: пещера — сетка и коллайдеры согласованы (bad=%d)" % bad_c)
	var bad_a := _probe_zone(world.ashen_zone, world.ashen_grid.map_rows, ASHEN_WALK)
	chk(bad_a == 0, "T8: Пепелище — сетка и коллайдеры согласованы (bad=%d)" % bad_a)

# ------------------------------------------------------------------ T9

func _clear_enemies(zone: Node2D) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and zone.is_ancestor_of(e as Node):
			(e as Node).queue_free()

func _soak(zone: Node2D, rows: Array, walk: String, spawn: Vector2i, tag: String) -> void:
	var stuck_bad := 0
	var max_stuck := 0
	var out_of_map := 0
	var dirs := ["move_left", "move_right", "move_up", "move_down"]
	var held := ""
	var stuck_run := 0
	var f := 0
	while f < 300:
		if f % 20 == 0:
			if held != "":
				Input.action_release(held)
			held = dirs[int(f / 20.0) % 4]
			Input.action_press(held)
		await get_tree().physics_frame
		f += 1
		var p: Vector2 = world.player.global_position - zone.position
		var t := Vector2i(int(floor(p.x / 16.0)), int(floor(p.y / 16.0)))
		var in_map: bool = t.x >= 0 and t.y >= 0 and t.y < rows.size() and t.x < String(rows[t.y]).length()
		if not in_map:
			out_of_map += 1
			continue
		if _walk(_ch(rows, t.x, t.y), walk) or _ch(rows, t.x, t.y) == "L":
			stuck_run = 0
		else:
			stuck_run += 1
			if stuck_run > 30:
				stuck_bad += 1
		max_stuck = maxi(max_stuck, stuck_run)
		if maxi(absi(t.x - spawn.x), absi(t.y - spawn.y)) > 12:
			world.player.global_position = Vector2(spawn.x * 16 + 8, spawn.y * 16 + 8) + zone.position
			stuck_run = 0
	if held != "":
		Input.action_release(held)
	chk(stuck_bad == 0, "T9: %s soak 5 с — застреваний в стенах нет (max_stuck=%d)" % [tag, max_stuck])
	chk(out_of_map == 0, "T9: %s soak — герой не покидал карту" % tag)

func _t9() -> void:
	world.apply_area("cave", true)
	await _frames(5)
	_clear_enemies(world.cave_zone)
	await _frames(10)
	var dz = world.dungeon_zone
	var sp: Array = dz.loaded_map.get("spawn", [1, 1])
	var spc := Vector2i(int(sp[0]), int(sp[1]))
	world.player.global_position = Vector2(spc.x * 16 + 8, spc.y * 16 + 8) + world.cave_zone.position
	await _soak(world.cave_zone, dz.map_rows, CAVE_WALK, spc, "пещера")
	world.apply_area("ashen", true)
	await _frames(5)
	_clear_enemies(world.ashen_zone)
	await _frames(10)
	var az = world.ashen_grid
	var m: Dictionary = _ash_meta
	var asp: Array = m.get("spawn", [1, 1])
	var aspc := Vector2i(int(asp[0]), int(asp[1]))
	world.player.global_position = Vector2(aspc.x * 16 + 8, aspc.y * 16 + 8) + world.ashen_zone.position
	await _soak(world.ashen_zone, az.map_rows, ASHEN_WALK, aspc, "Пепелище")

# ------------------------------------------------------------------ T10

func _t10() -> void:
	var mm = Minimap.I
	chk(mm != null, "T10: миникарта живёт")
	if mm == null:
		return
	var gw: int = int(mm.get("_grid_w"))
	var gh: int = int(mm.get("_grid_h"))
	var cw: int = world.dungeon_zone.map_w
	var chh: int = world.dungeon_zone.map_h
	# apply_area("ashen") ещё активен — подложка пересчитывается динамически;
	# здесь сверяем, что набран размер актуальной зоны: пещеры или Пепелища.
	var aw: int = world.ashen_grid.map_w
	var ah: int = world.ashen_grid.map_h
	chk((gw == cw and gh == chh) or (gw == aw and gh == ah),
		"T10: подложка %dx%d = актуальная зона (cave %dx%d, ashen %dx%d)" % [gw, gh, cw, chh, aw, ah])

# ------------------------------------------------------------------ T11

# t17 «Живая стилистика»: герой (idle/walk/attack) и бестиарий (slime,
# swarmling, archer, rotspawn t1–t3, гром, ведьма) — полные tight alpha-кропы
# 1024-оригиналов art_gen БЕЗ квантизации (RGBA8, >256 цветов). Пиплайн кроя
# (scratch_cm/t17_cut_actors.py) пинит MD5 1024-источников своими assert'ами;
# здесь пиним MD5 привезённых PNG (цепочка «источник→кроп» замывается ими),
# а при доступности art_gen (прогон не только в battery-стейдже) сверяем и
# MD5 источников. Экранные высоты и линии стоп — канон t12 VISUAL_SCALE,
# линии замерены эмпирически по старым спрайтам: tight-кроп => контент-стопы
# на нижней строке текстуры => anim.position.y = foot − canon/2.
# Тенеплёт (wraith) в игру НЕ интегрирован (решение пользователя).
const T11_ART := [
	{"n": "hero_idle.png", "src": "hero/hero_idle_v2.png",
	 "sm": "0edcc9365ee110497261c355803e1fa5", "am": "28c43254198b7b5a5a4ee898636b912e",
	 "w": 513, "h": 1460},
	{"n": "hero_walk.png", "src": "hero/hero_walk_v2.png",
	 "sm": "3f2f987e55723f61c240af2954d6c046", "am": "7670e1c89bbe3f209a47bb701f4162fd",
	 "w": 762, "h": 1374},
	{"n": "hero_attack.png", "src": "hero/hero_attack_v2.png",
	 "sm": "5800b97db70698428d3f8bbe0c35ae9c", "am": "39486e46acb80b8ca9e62976fb772f72",
	 "w": 904, "h": 1283},
	{"n": "mob_slime.png", "src": "monsters/slime_v2.png",
	 "sm": "d1a0e568180bfeafbf4416f56d456f85", "am": "855e4d9ae83bb918d01ac1e90801f82b",
	 "w": 566, "h": 528},
	{"n": "mob_swarmling.png", "src": "monsters/swarmling_v1.png",
	 "sm": "4c1851723013fa3e0920a27dba22ef67", "am": "908be54128e450423991e6e2c832e7b1",
	 "w": 698, "h": 356},
	{"n": "mob_archer.png", "src": "monsters/archer_v2.png",
	 "sm": "8a0e31c7cd396d4711d6130d26dc7133", "am": "de4563c0f71bd335bfa2065afab996f2",
	 "w": 438, "h": 979},
	{"n": "mob_rotspawn.png", "src": "monsters/rotspawn_v2.png",
	 "sm": "e328cce23cd94340da01ecec26b3299c", "am": "e25521cb98cdb693aa77c1bc24084e74",
	 "w": 686, "h": 872},
	{"n": "mob_grom.png", "src": "monsters/grom_v2.png",
	 "sm": "7c61ec9c937e8a871024899fcc2b0394", "am": "32c8d9fa970a752ff57517a8f9efcdb4",
	 "w": 812, "h": 773},
	{"n": "mob_witch.png", "src": "monsters/witch_v2.png",
	 "sm": "4d262d411a3153ac497d448d87db7033", "am": "208385b8eed7c91b5ab5b0be51537a1a",
	 "w": 497, "h": 974},
]

func _t11_md5(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var hc := HashingContext.new()
	if hc.start(HashingContext.HASH_MD5) != OK:
		f.close()
		return ""
	hc.update(f.get_buffer(f.get_length()))
	f.close()
	return hc.finish().hex_encode()

func _t11() -> void:
	# --- 1. статика ассетов: MD5 / глубина цвета / импорт / мипы ---
	var ag_base: String = ProjectSettings.globalize_path("res://") + "../art_gen/"
	for a: Dictionary in T11_ART:
		var rp := "res://assets/art/" + String(a["n"])
		var m_ok: bool = _t11_md5(rp) == String(a["am"])
		var has_src: bool = FileAccess.file_exists(ag_base + String(a["src"]))
		if has_src:
			m_ok = m_ok and _t11_md5(ag_base + String(a["src"])) == String(a["sm"])
		chk(m_ok, "T11: %s — MD5 канон%s" % [a["n"], " (+1024-источник)" if has_src else ""])
	for a: Dictionary in T11_ART:
		var rp := "res://assets/art/" + String(a["n"])
		var tex := load(rp) as Texture2D
		var ok_tex: bool = tex != null and tex.get_width() == int(a["w"]) and tex.get_height() == int(a["h"])
		var imp_ok := true
		var f := FileAccess.open(rp + ".import", FileAccess.READ)
		if f == null:
			imp_ok = false
		else:
			var t := f.get_as_text()
			f.close()
			imp_ok = t.contains("mipmaps/generate=true")
		var ci: Array = _ctex_mip_info(rp)
		var need: int = int(floor(log(float(maxi(int(a["w"]), int(a["h"])))) / log(2.0)))
		var mip_ok: bool = ci.size() == 3 and int(ci[0]) == int(a["w"]) and int(ci[1]) == int(a["h"]) and int(ci[2]) >= need
		chk(ok_tex and imp_ok and mip_ok,
			"T11: %s — %dx%d, mipmaps/generate=true, мип-цепочка полная (доп.=%d≥%d)" % [
				a["n"], a["w"], a["h"], int(ci[2]) if ci.size() == 3 else -1, need])
	for a: Dictionary in T11_ART:
		var f := FileAccess.open("res://assets/art/" + String(a["n"]), FileAccess.READ)
		var ok := false
		var ncol := 0
		var capped := false
		if f != null:
			var img := Image.new()
			if img.load_png_from_buffer(f.get_buffer(f.get_length())) == OK \
					and img.get_format() == Image.FORMAT_RGBA8:
				# подсчёт уникальных RGBA8-палитр по сырым байтам (get_used_colors()
				# в Godot 4 нет); скан обрывается на 4096 — 8-битной квантизации
				# хватило бы 256, порог 4096 подтверждает полную глубину с запасом
				var d := img.get_data()
				var seen := {}
				var i := 0
				while i + 3 < d.size() and seen.size() <= 4096:
					seen[d[i] | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24)] = true
					i += 4
				ncol = seen.size()
				capped = i + 3 < d.size()
				ok = ncol > 256
			f.close()
		chk(ok, "T11: %s — RGBA8, %s цветов (полная глубина, без квантизации)" % [
			a["n"], ("%d+" % ncol) if capped else ("%d" % ncol)])
	# --- 2. живой герой: канон 32, линия стоп 5.0, анимы, flip ---
	var p = world.player
	var hero_ok: bool = p != null and p.gen_art and p.anim != null
	chk(hero_ok, "T11: герой на ген-арте (gen_art)")
	if hero_ok:
		var pa: AnimatedSprite2D = p.anim
		var idle: Texture2D = pa.sprite_frames.get_frame_texture("down", 0)
		chk(idle != null and String(idle.resource_path).ends_with("hero_idle.png"),
			"T11: герой — hero_idle.png в рабочих анимах")
		var drawn_h: float = float(idle.get_height()) * pa.scale.x
		var foot_h: float = pa.position.y + drawn_h / 2.0
		chk(absf(drawn_h - 32.0) <= 0.05 and absf(foot_h - 5.0) <= 0.01,
			"T11: герой drawn=%.3f (канон 32), стопы=%.3f (линия 5.0)" % [drawn_h, foot_h])
		chk(pa.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
			"T11: герой — TEXTURE_FILTER_LINEAR_WITH_MIPMAPS")
		var names_ok := true
		for an: String in ["down", "up", "left", "right", "walk_down", "walk_up", "walk_left", "walk_right", "attack"]:
			if not pa.sprite_frames.has_animation(an) or pa.sprite_frames.get_frame_count(an) != 1:
				names_ok = false
		var walk_tex: Texture2D = pa.sprite_frames.get_frame_texture("walk_down", 0) if pa.sprite_frames.has_animation("walk_down") else null
		var atk_tex: Texture2D = pa.sprite_frames.get_frame_texture("attack", 0) if pa.sprite_frames.has_animation("attack") else null
		chk(names_ok and walk_tex != null and String(walk_tex.resource_path).ends_with("hero_walk.png") \
				and atk_tex != null and String(atk_tex.resource_path).ends_with("hero_attack.png"),
			"T11: герой — 9 аним по 1 кадру, walk/attack на своих листах (резерв аним-прохода)")
		var facing0: String = String(p.facing)
		p.facing = "left"
		p._sync_gen_flip()
		var fl: bool = pa.flip_h
		p.facing = "right"
		p._sync_gen_flip()
		var fr_: bool = pa.flip_h
		p.facing = facing0
		p._sync_gen_flip()
		chk(fl and not fr_, "T11: герой — flip_h по facing (арт смотрит вправо)")
	else:
		chk(false, "T11: герой — hero_idle.png в рабочих анимах (нет ген-арта)")
		chk(false, "T11: герой — канон 32 / линия стоп 5.0 (нет ген-арта)")
		chk(false, "T11: герой — LINEAR_WITH_MIPMAPS (нет ген-арта)")
		chk(false, "T11: герой — 9 аним по 1 кадру (нет ген-арта)")
		chk(false, "T11: герой — flip_h по facing (нет ген-арта)")
	# --- 3. живой бестиарий: setup-спавн вдали, проверки по месту, free ---
	_t11_mob("слизень", "res://scripts/slime.gd", "mob_slime.png", 22.0, 7.0625, {})
	_t11_mob("мглокрыс", "res://scripts/mob_swarmling.gd", "mob_swarmling.png", 24.0, 7.5, {})
	_t11_mob("лучник", "res://scripts/mob_archer.gd", "mob_archer.png", 24.0, 8.5, {})
	# brute.gd: var boss := true по умолчанию — ярусных мобов world.gd переводит
	# в boss=false до setup; здесь воспроизводим канонический порядок
	_t11_mob("гнидень ярус1", "res://scripts/brute.gd", "mob_rotspawn.png", 29.0, 8.50178125, {"boss": false, "tier": 1})
	_t11_mob("гнидень ярус2", "res://scripts/brute.gd", "mob_rotspawn.png", 35.0, 10.26000625, {"boss": false, "tier": 2})
	_t11_mob("гнидень ярус3", "res://scripts/brute.gd", "mob_rotspawn.png", 42.0, 12.3125, {"boss": false, "tier": 3})
	_t11_mob("Гром", "res://scripts/brute.gd", "mob_grom.png", 52.0, 15.2440476, {"boss": true})
	_t11_mob("Ведьма Пепелища", "res://scripts/mob_boss2.gd", "mob_witch.png", 51.0, 13.91375, {})
	# --- 4. Тенеплёт не интегрирован ---
	var wraith_art := ""
	var d := DirAccess.open("res://assets/art")
	if d != null:
		for fn in d.get_files():
			if String(fn).to_lower().contains("wraith"):
				wraith_art += String(fn) + " "
	chk(wraith_art == "", "T11: в assets/art нет ассетов Тенеплёта (wraith не интегрирован)")
	var wraith_ref := ""
	for sp: String in ["res://scripts/world.gd", "res://scripts/ashen_zone.gd", "res://scripts/dungeon_zone.gd"]:
		var f2 := FileAccess.open(sp, FileAccess.READ)
		if f2 != null:
			if f2.get_as_text().contains("mob_wraith"):
				wraith_ref += sp.get_file() + " "
			f2.close()
	chk(wraith_ref == "", "T11: зоны не ссылаются на mob_wraith (Тенеплёт не спавнится)")

func _t11_mob(tag: String, script_path: String, tex_name: String, canon: float, foot: float, cfg: Dictionary) -> void:
	# спавн по каноническому пути (new -> add_child -> setup), далеко от героя;
	# проверки синхронные (setup строит anim сразу), free() — до физ-кадра
	var m = load(script_path).new()
	for k: String in cfg:
		m.set(k, cfg[k])
	add_child(m)
	m.setup(world, Vector2i(400, 400))
	var ok := true
	var a: AnimatedSprite2D = m.get("anim")
	var tex: Texture2D = null
	if a == null:
		ok = false
	else:
		# Флаг gen_art есть не у всех (у slime его нет — одиночный спрайт без
		# флажка), и bool(Variant(Nil)) падает в Godot 4.7.2. Проверяем более
		# надёжный критерий: фактическую играющий аним: slime/brute — "walk",
		# swarmling/archer — "idle_down" (у своих листов свои наборы имён)
		var an := String(a.animation)
		tex = a.sprite_frames.get_frame_texture(an, 0) if a.sprite_frames.has_animation(an) else null
		ok = tex != null and String(tex.resource_path).ends_with(tex_name) \
			and a.sprite_frames.get_frame_count(an) == 1 \
			and absf(float(tex.get_height()) * a.scale.x - canon) <= 0.05 \
			and absf(a.position.y + canon / 2.0 - foot) <= 0.01 \
			and a.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if not ok:
		print("   QA_LP: %s — провал ген-проверки (anim=%s)" % [tag, a])
	var dh := (float(tex.get_height()) * a.scale.x) if (a != null and tex != null) else -1.0
	var fh := (a.position.y + canon / 2.0) if a != null else -1.0
	chk(ok, "T11: %s — %s, drawn=%.3f (канон %.1f), стопы=%.5f" % [tag, tex_name, dh, canon, fh])
	m.free()

# ------------------------------------------------------------------ T12

# t18 «сочность»: hitstop/вспышки/цифры-overshoot/тени/«дыхание» пропов/шлейф/
# виньетка. Геймплейные числа не затронуты — здесь только визуальные гарантии.
# Реальные паузы — поллингом Time.get_ticks_msec(): в headless главный цикл
# крутится быстрее реального времени, и любые кадловые/таймерные ожидания
# (включая create_timer с ignore_time_scale — он в 4.7.2-on-headless считается
# по дельте быстрого цикла) срабатывают раньше реального срока. Тики честные.

func _t12_rt(sec: float) -> void:
	var until_ms := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until_ms:
		await get_tree().process_frame

func _t12_slime() -> Node2D:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var s: Script = (e as Node).get_script()
		if s == null or String(s.resource_path) != "res://scripts/slime.gd":
			continue
		if int((e as Node).get("hp")) > 1 and not (e as Node).get("dying"):
			return e as Node2D
	return null

func _t12_spawn_slime(tile: Vector2i) -> Node2D:
	var sl: Node2D = load("res://scripts/slime.gd").new()
	world.village_zone.add_child(sl)
	sl.setup(world, tile)
	sl.set_physics_process(false)
	return sl

func _t12_ghosts() -> int:
	var n := 0
	for c in world.get_children():
		if is_instance_valid(c) and String((c as Node).name) == "DashGhost":
			n += 1
	return n

func _t12_lights(zone: Node, suffix: String, out: Array) -> void:
	for c in zone.get_children():
		if c is Sprite2D:
			var s := c as Sprite2D
			if s.texture != null and String(s.texture.resource_path).ends_with(suffix) \
					and s.has_node("JuiceLight"):
				out.append({"spr": s, "light": s.get_node("JuiceLight")})
		_t12_lights(c, suffix, out)

func _t12_cam_dev(frames: int) -> float:
	# максимальное отклонение offset'а камеры за окно (тряска «мазок кисти»);
	# сэмплим process_frame — тряска живёт в idle-процессе и в РЕАЛЬНОМ времени
	var dev := 0.0
	for i in frames:
		await get_tree().process_frame
		dev = maxf(dev, absf(world.cam.offset.x) + absf(world.cam.offset.y))
	return dev

func _t12() -> void:
	var p: Node2D = world.player
	world.apply_area("village", true)
	await _frames(15)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			(e as Node).set_physics_process(false)  # тишина поля: только наши вызовы
	p.global_position = world.tile_to_world(Vector2i(26, 13))
	GameState.hp = 50
	p.hurt_cd = 0.0
	p.roll_cd = 0.0
	p.roll_t = 0.0
	await _frames(5)

	# 1) overshoot цифр: константы + живой pop из 1.3 СРАЗУ на кадре спавна
	chk(DmgNumbers.POP_FROM >= 1.25 and DmgNumbers.POP_FROM <= 1.35 \
			and DmgNumbers.POP_TIME >= 0.1,
		"T12: overshoot цифр %.2f->1.0 за %.2f с" % [DmgNumbers.POP_FROM, DmgNumbers.POP_TIME])
	var cc: Color = DmgNumbers.COLORS["crit"]
	chk(cc.r > 0.75 and cc.g < 0.55 and cc.b < 0.45 and cc.r > cc.g * 1.8,
		"T12: крит — алое семейство (смертельное=красное), не золото")
	DmgNumbers.spawn(p.global_position + Vector2(0, -20), 7, "crit")
	var dn := get_node_or_null("DmgNumbers")
	var pop_ok := false
	if dn != null:
		for c in dn.get_children():
			if c is Label and (c as Control).visible \
					and absf((c as Control).scale.x - DmgNumbers.POP_FROM) <= 0.001:
				pop_ok = true
	chk(pop_ok, "T12: метка урона рождается с масштабом overshoot (%.1f)" % DmgNumbers.POP_FROM)

	# 2) тени по высоте актёра: герой (32 px канон) vs слайм (22 px)
	var sl := _t12_slime()
	if sl == null:
		sl = _t12_spawn_slime(Vector2i(28, 13))
	var sh_p := p.get_node_or_null("AtmoShadow") as Sprite2D
	var sh_s := sl.get_node_or_null("AtmoShadow") as Sprite2D
	chk(sh_p != null and sh_p.scale.x >= 0.9 and sh_p.scale.x <= 1.1,
		"T12: тень героя — канон-масштаб (%.2f)" % (sh_p.scale.x if sh_p != null else -1.0))
	chk(sh_s != null and sh_s.scale.x < sh_p.scale.x - 0.12 and sh_s.scale.x >= 0.55,
		"T12: тень мелкого моба меньше геройской (%.2f < %.2f)" % [
			sh_s.scale.x if sh_s != null else -1.0, sh_p.scale.x if sh_p != null else -1.0])

	# 3) hitstop: dip есть, восстановление в РЕАЛЬНОМ времени ≤0.4 с (гарантия)
	Engine.time_scale = 1.0
	await _t12_rt(0.15)  # окно троттла чисто
	sl.hurt(1, p.global_position)
	chk(Engine.time_scale < 1.0 and Engine.time_scale > 0.0,
		"T12: hitstop — удар роняет время (%.2f)" % Engine.time_scale)
	var dev: float = await _t12_cam_dev(10)
	chk(dev > 0.02, "T12: тряска камеры «мазок» бьёт по offset'у (%.2f px)" % dev)
	var t0 := Time.get_ticks_msec()
	while Engine.time_scale != 1.0 and Time.get_ticks_msec() - t0 < 400:
		await get_tree().process_frame
	chk(Engine.time_scale == 1.0,
		"T12: hitstop конечен — время восстановлено за %d мс реала" % (Time.get_ticks_msec() - t0))

	# 4) смертельный удар: утечки времени нет
	var sl2 := _t12_spawn_slime(Vector2i(27, 15))
	await _t12_rt(0.15)
	sl2.hurt(999, p.global_position)
	var lethal: bool = sl2.get("dying")
	t0 = Time.get_ticks_msec()
	while Engine.time_scale != 1.0 and Time.get_ticks_msec() - t0 < 400:
		await get_tree().process_frame
	chk(lethal and Engine.time_scale == 1.0,
		"T12: смертельный удар — время возвращено (dying=%s)" % lethal)

	# 5) вспышка моба ≤0.1 с
	var sl3 := _t12_spawn_slime(Vector2i(25, 15))
	await _t12_rt(0.15)
	sl3.hurt(0, p.global_position)
	var ht: float = float(sl3.get("hurt_t"))
	chk(ht > 0.0 and ht <= 0.1, "T12: вспышка моба %.3f с ≤ 0.1" % ht)

	# 6) вспышка героя ≤0.1 с + горячий тинт + красный импульс виньетки
	p.hurt_cd = 0.0
	GameState.hp = 50
	GameState.stats_changed.emit()  # baseline _last_hp в hud: детект «упало» с честного порога
	await _t12_rt(0.15)
	p.take_damage(2)
	var ft: float = float(p.get("_flash_t"))
	chk(ft > 0.0 and ft <= 0.1, "T12: вспышка героя %.3f с ≤ 0.1" % ft)
	# physics_frame эмитится ДО _physics_process — тинт читаем через кадр
	await _frames(2)
	chk(p.modulate.r > 1.4 and p.modulate.g < 1.0 and p.modulate.b < 1.0,
		"T12: тинт вспышки горячий (%s)" % p.modulate)
	await _frames(2)
	var dv := world.hud.get_node_or_null("DmgVignette") as Control
	var vg_ok := false
	if dv != null and dv.visible and dv.modulate.a > 0.05 and dv.texture != null:
		var img := (dv.texture as ImageTexture).get_image()
		var corner := img.get_pixel(10, 10)
		var mid := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		# красное = только смертельное: уголки красные, центр прозрачный
		vg_ok = corner.r > 0.6 and corner.g < 0.3 and corner.a > 0.3 and mid.a < 0.02
	chk(vg_ok, "T12: красный импульс урона виден, углы красные, центр чист")
	await _t12_rt(0.55)  # 420 мс реала — импульс обязан погаснуть
	chk(dv != null and not dv.visible, "T12: импульс виньетки погас (не залип)")

	# 7) тень в воздушной фазе «Рывка вепря» (физика героя на паузе — только атмосфера)
	if sh_p != null:
		p.set_physics_process(false)
		var k0: float = sh_p.scale.x
		p.set("boar_t", 0.1)
		await _frames(3)
		var k_air: float = sh_p.scale.x
		var a_air: float = sh_p.modulate.a
		p.set("boar_t", 0.0)
		p.set_physics_process(true)
		await _frames(3)
		chk(k_air < k0 * 0.9 and a_air < 0.4,
			"T12: в полёте тень сжата (%.2f<%.2f) и бледна (%.2f)" % [k_air, k0, a_air])
		chk(sh_p.scale.x > k_air * 1.15 and absf(sh_p.modulate.a - 0.5) < 0.01,
			"T12: приземлился — тень вернулась (%.2f)" % sh_p.scale.x)

	# 8) шлейф кувырка: силуэты есть в кувырке, чисто после
	p.roll_cd = 0.0
	p.roll_t = 0.0
	p.start_roll(Vector2.RIGHT)
	await _frames(6)
	var gn := _t12_ghosts()
	chk(gn >= 1, "T12: кувырок оставляет призрачный шлейф (%d)" % gn)
	await _frames(20)
	await _t12_rt(0.4)
	chk(_t12_ghosts() == 0, "T12: шлейф погас — узлов не осталось")

	# 9) «дыхание» env4-пропов: алтарь/портал/сундук + пульс/bob при неподвижном спрайте
	var altar: Array = []
	var portal: Array = []
	var chests: Array = []
	_t12_lights(world.cave_zone, "env4_altar.png", altar)
	_t12_lights(world.ashen_zone, "env4_portal.png", portal)
	_t12_lights(world.cave_zone, "env4_chest.png", chests)
	chk(not altar.is_empty(), "T12: алтарям пещеры живёт свет JuiceLight (%d)" % altar.size())
	chk(not portal.is_empty(), "T12: порталу Пепелища живёт свет JuiceLight (%d)" % portal.size())
	chk(not chests.is_empty(), "T12: сундукам живёт свет JuiceLight (%d)" % chests.size())
	# отсчёт пульса — от ПЕРВОГО сэмпла каждого света (базы у пропов разные)
	var all_l: Array = []
	for grp in [altar, portal, chests]:
		for it in grp:
			all_l.append(it["light"])
	var e_first := {}
	var y_first := {}
	for lt in all_l:
		e_first[lt] = (lt as Light2D).energy
		y_first[lt] = (lt as Node2D).position.y
	var spr0: Vector2 = (altar[0]["spr"] as Node2D).position if not altar.is_empty() else Vector2.INF
	var e_dev := 0.0
	var y_dev := 0.0
	# Сэмпл — РЕАЛЬНЫМ таймером: в headless физ-кадры идут быстрее реального
	# времени, а «дыхание» считает фазу по реальным мсек (Time.get_ticks_msec).
	for i in 9:
		for lt in all_l:
			e_dev = maxf(e_dev, absf((lt as Light2D).energy - float(e_first[lt])))
			y_dev = maxf(y_dev, absf((lt as Node2D).position.y - float(y_first[lt])))
		await _t12_rt(0.25)
	chk(e_dev > 0.02 and y_dev > 0.4,
		"T12: пульс %.3f и bob %.2f px живые" % [e_dev, y_dev])
	chk(spr0 != Vector2.INF and (altar[0]["spr"] as Node2D).position == spr0,
		"T12: спрайт алтаря неподвижен — дышит только свет")

	# 10) финал: тряска обнулена, время = 1 (никаких залипаний после боя)
	await _t12_rt(0.45)
	chk(world.cam.offset == Vector2.ZERO,
		"T12: тряска не залипла (offset %s)" % world.cam.offset)
	chk(Engine.time_scale == 1.0, "T12: Engine.time_scale == 1.0 на выходе")
	Juice.reset()
	p.modulate = Color.WHITE
