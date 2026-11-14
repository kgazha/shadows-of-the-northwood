extends Node2D
## QA-стенд Т14 «крупные пропы вписаны в пространство» (пещера/Пепелище).
## Прогон: godot --headless res://qa_lp.tscn
## Пин-сид забега 42 (как qa_z1). Проверяет пост-процесс сеток world._reshape_*
## (залы алтарей/портала, проходы ≥2 клетки) С НЕЗАВИСИМОЙ геометрией: BFS/2×2
## переписаны здесь, а не вызываются из world.gd (зеркальная реализация).
##  T1  таблицы символов бит-в-бит + монотонность перестройки против свежего
##      генераторного dict (только dig-символы -> ".", якоря/рамка целы).
##  T2  зал алтаря 5x6 (x±2, y-3..y+2): в верхних рядах нет стен (кроме
##      защищённой ниши сундука); ранг не тронут; t52: ген-пропов нет —
##      пины ENV4_* констант на ОТСУТСТВИЕ.
##  T3  все POI пещеры достижимы из spawn BFS с открытой дверью; сундук и
##      алтари НЕ достижимы с закрытой (гейт двери сохранён).
##  T4  Пепелище: монотонность, зал портала 5x6 (x±2, y-4..y+1), якорь=клетка P.
##  T5  проходы: каждая проходимая клетка обеих зон лежит в проходимом 2x2
##      ИЛИ вскрытие легально невозможно (тупик у рамки/защиты).
##  T6  t52: слои «живой земли» (Cave/AshenFloorPaint, GroundPaint) и их
##      билдеры снесены; детерминизм: два мира на сиде 42 — бит-в-бит дампы.
##  T7  t52 «план сноса»: каталоги assets/art/ и assets/portraits/ удалены,
##      ген-иконки/UI-декор (item/skill/talent_icons, decor_paper_edge,
##      decor_minimap_bronze) — файл+.import отсутствуют; ENV4_* констант нет;
##      ручные атласы (portraits.png/2, dungeon_tiles, tiles) на месте;
##      default_texture_filter=0 не тронут.
##  T8  физ-проба: в центре КАЖДОЙ проходимой клетки обеих зон нет статических
##      коллайдеров (сетка <-> коллайдеры после перестройки согласованы).
##  T9  soak 2x5 сек (пещера+Пепелище, враги сняты): герой не застревает в
##      стенах (>30 кадров в блокирующей клетке), не вылетает за карту.
##  T10 миникарта: размер сетки-подложки = размер текущей зоны (динамический
##      пересчёт, не пиксель — пиксельные сигнатуры сверяет qa_mm).
##  T11 t52: ген-листы актёров снесены; герой — AtlasTexture листа класса
##      (class_warrior.png, 4 аним × 4 кадра 16 px, drawn 16/стопы 8, parent-фильтр);
##      бестиарий — slime/mobs_*/brute листы (ярусы × TIERS.scale, Ведьма ×1.12);
##      dungeon_tiles.png — MD5 после t52-реставрации клеток 6/7; Тенеплёт не
##      интегрирован.
##  T12 t18 «сочность»: hitstop конечен и возвращает Engine.time_scale в
##      РЕАЛЬНОМ времени (обычный и смертельный удар), вспышки цели ≤0.1 с,
##      overshoot цифр 1.3 (qa_dn зелёный), тень по высоте актёра + воздушная
##      фаза «Рывка вепря», «дыхание» легаси-проп-светов (atmo._prop_lights:
##      сундук пещеры; env4-слоёв t52-сносом нет), шлейф кувырка, красный
##      виньеточный импульс.
##  T13 t33 «общая глубина» (V-03/V-04) + t52: env4-слои снесены; актёры
##      (герой/мобы/NPC) — в динамической шкале z = round(fposmod(y,YS_CYCLE))
##      +YS_ACTOR_BIAS (южнее — глубже); цифры урона подняты над z-шкалой зон.
##      Только порядок отрисовки — геометрия бит-в-бит.
##  T15 t52+t54: env4-реестров/VillageProps нет (контракт отсутствия); с вердикта
##      «Деревня v4 — внедряем» реестр _ys_props_dim заполнен только кодоген-
##      спрайтами атласов assets/village/ и assets/cave/; в дереве мира ни одной
##      ген-текстуры.
##  T16 c3 «Пещера v1 — внедряем»: кодоген-атласы assets/cave/ в игре; кадры
##      пропов alpha-trim’лены до силуэта (пустых полей нет, стопа=OUTLINE);
##      побайтовый rebake == закоммиченные атласы; CHAR_TO_TILE/BLOCKING бит-в-бит,
##      визуальные источники 1/2 с зеркальным пересчётом каждой клетки;
##      направленные кромки стены по вертикали не повторяются (аудит c2 F4);
##      широкий сундук — визуальный слой над стандартным клеточным коллайдером;
##      сталактиты над актёров, сталагмиты в реестре дима; живой дим; чистые
##      комментарии генератора (без CJK и склеек).
##  T16.10 c5 «факелы лучше»: состав 3..5, 2 кадра фликера (паттерн A_TORCH),
##      монтаж на стене выше головы (z V-01, вне дима), пульс PointLight2D по
##      паттерну _altar_light, детерминированная расстановка (зеркало),
##      мох-кострище в дереве пещеры отсутствует (кадр — только в атласе).
##  T16.11 c7 «микро-жизнь»: пылинки пещеры — залы (компоненты длинных
##      прогонов), 2..4 на зал, лимит, fmod-цикл без накопления, живое
##      движение при активной зоне, вне реестра дима.

const Main := "res://scenes/main.tscn"
const WS := preload("res://scripts/world.gd")
const PAL := preload("res://scripts/pixel_palette.gd")
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
	await _t13()
	await _t14()
	await _t15()
	await _t16()
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
		# t35 (V-05): запечённый слой — текстура без пути (ImageTexture). Якорь
		# детерминизма бейка: размеры + MD5 побайтового содержимого.
		if spr.texture != null and String(spr.texture.resource_path) == "":
			var img := spr.texture.get_image()
			if img != null:
				var hc := HashingContext.new()
				hc.start(HashingContext.HASH_MD5)
				hc.update(img.get_data())
				s += "BAKE %dx%d amax=%.4f md5=%s;" % [img.get_width(), img.get_height(), float(spr.get_meta("gp_amax")) if spr.has_meta("gp_amax") else -1.0, hc.finish().hex_encode()]
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
	# t35 (V-05): деревенская «живая земля» тоже в снимке — бейк детерминирован и
	# пинится md5 наравне с пещерой/Пепелищем (раньше слой не пинился вовсе).
	s += "|GP>" + _paint_dump(w, w.village_zone, "GroundPaint")
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
	# залы алтарей — POI-геометрия карты (t52: ген-картинок алтаря/камней нет)
	chk(halls_ok, "T2: залы алтарей 5x6 без dig-символов (алтарей %d)" % altar_n)
	chk(top_ok, "T2: верхние ряды залов (выше клетки алтаря) без стен")
	# t52 «план сноса»: ген-пропов алтаря/камней нет — их картинок не существует;
	# констант ENV4_* в world.gd тоже нет, зал остаётся POI-геометрией карты.
	var wf2 := FileAccess.open("res://scripts/world.gd", FileAccess.READ)
	var wsrc2: String = wf2.get_as_text() if wf2 != null else ""
	chk(not wsrc2.contains("const ENV4_ART") and not wsrc2.contains("const ENV4_CANON_H") \
		and not wsrc2.contains("const ENV4_PROP_CANON_H"),
		"T2: ENV4-* константы снесены из world.gd")

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
	# t52: ген-картинки портала снесена; портал остаётся игровым объектом на
	# клетке «P» (POOL-проверки ниже), ширины картинок больше не пиним.
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
	# t52 «план сноса»: слои «живой земли» (ген-патчи полов пещеры/Пепелища и
	# деревенский GroundPaint) снесены — пол рендерится базовым тайловым атласом.
	var layer_c = world.cave_zone.get_node_or_null("CaveFloorPaint")
	var layer_a = world.ashen_zone.get_node_or_null("AshenFloorPaint")
	var layer_v = world.village_zone.get_node_or_null("GroundPaint")
	chk(layer_c == null and layer_a == null and layer_v == null,
		"T6: слои «живой земли» снесены (cave/ashen paint + GroundPaint)")
	chk(not world.has_method("_build_zone_floor_paint") \
		and not world.has_method("_build_ground_paint") and not world.has_method("_gp_bake"),
		"T6: билдеры ген-полов удалены из world.gd")
	# второй мир — тот же сид: снимок бит-в-бит
	world.queue_free()
	await _frames(5)
	world = null
	world = await _spawn_world()
	var snap2: String = _snapshot(world)
	chk(snap2 == snap1, "T6: детерминизм — два мира идентичны (grid+floor paint dump)")

# ------------------------------------------------------------------ T7

func _t7() -> void:
	# t52 «план сноса»: контракт GREEN = ОТСУТСТВИЕ ген-ресурсов на диске и в
	# реестре. Каталог assets/art/ (env4/полы/герой/мобы/деревня/роща) снесён,
	# ген-портреты (assets/portraits/), ген-иконки и UI-декор удалены; вместо
	# иконок — код-заглушки UiIcons (ImageTexture, без файлов). Проектный
	# default_texture_filter=0 (nearest) не тронут — канон полной глубины цвета
	# без 8-битной квантизации живёт в LINEAR-ренстере тайлов (t51).
	chk(DirAccess.open("res://assets/art") == null,
		"T7: каталог ген-ассетов res://assets/art/ снесён")
	chk(DirAccess.open("res://assets/portraits") == null,
		"T7: каталог ген-портретов res://assets/portraits/ снесён")
	for gone_path: String in ["res://assets/item_icons.png",
			"res://assets/skill_icons.png", "res://assets/talent_icons.png",
			"res://assets/ui/decor_paper_edge.png",
			"res://assets/ui/decor_minimap_bronze.png"]:
		chk(not ResourceLoader.exists(gone_path) and not FileAccess.file_exists(gone_path + ".import"),
			"T7: %s — файл и .import удалены" % gone_path)
	var wf7 := FileAccess.open("res://scripts/world.gd", FileAccess.READ)
	var wsrc7: String = wf7.get_as_text() if wf7 != null else ""
	chk(not wsrc7.contains("const ENV4_ART") and not wsrc7.contains("const ENV4_CANON_H") \
		and not wsrc7.contains("const ENV4_PROP_CANON_H"),
		"T7: константы ENV4_* снесены из world.gd")
	# легаси-атласы ручной отрисовки, на которые опирается игра, — живы
	for keep_path: String in ["res://assets/portraits.png", "res://assets/portraits2.png",
			"res://assets/dungeon_tiles.png", "res://assets/tiles.png"]:
		chk(ResourceLoader.exists(keep_path), "T7: ручной ассет на месте: %s" % keep_path)
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

# t52 «план сноса» (закон пользователя 13.11): весь qwen-image ген-арт (assets/art/:
# герой-листы, бестиарий, роща, деревня, env4, полы) снят с игры. Актёры — ручные
# пиксельные листы (t51, мир 16 px): герой — лист класса class_warrior.png
# (48×64: кадры 16 px, ряды down/left/right/up, колонки [0,1,0,2], 4 кадра/аним),
# слизень — slime.png (2 кадра bob), мглокрыс/лучник — mobs_swarmling/mobs_archer.png
# ({idle,walk,act}_{dirs}, idle 2 кадра), гнидень/Гром/Ведьма — brute.png
# (32 px кадры × TIERS.scale; Ведьма ×1.12). Фильтры — INHERITED (проектный
# nearest; мипмапсов на листах нет). dungeon_tiles.png после восстановления
# клеток 6/7 из доген-блоба пинится MD5. Тенеплёт (wraith) не интегрирован.
const T11_GEN_GONE := [
	"hero_idle.png", "hero_walk.png", "hero_attack.png",
	"mob_slime.png", "mob_swarmling.png", "mob_archer.png",
	"mob_rotspawn.png", "mob_grom.png", "mob_witch.png",
]
# Канонический MD5 dungeon_tiles.png после t52-восстановления клеток 6/7
# (каменные плиты) из предген-блоба 8fb87cb^; ниже — сверка hex_encode().
const T11_DUNGEON_MD5 := "be38cea964639e25db2f5cb97bd8d538"

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
	# --- 1. статика: ген-листы снесены с диска; ручной канон полов пинится MD5 ---
	for n: String in T11_GEN_GONE:
		chk(not FileAccess.file_exists("res://assets/art/" + n) \
			and not ResourceLoader.exists("res://assets/art/" + n),
			"T11: ген-лист %s снесён с диска" % n)
	chk(_t11_md5("res://assets/dungeon_tiles.png") == T11_DUNGEON_MD5,
		"T11: dungeon_tiles.png — MD5 канон t52 (клетки 6/7 восстановлены)")
	# --- 2. живой герой: пиксельный лист класса (t51 мир 16 px), канон 16/8 ---
	var p = world.player
	var hero_ok: bool = p != null and p.get("gen_art") == null and p.anim != null
	chk(hero_ok, "T11: герой на пиксельном листе класса (флага gen_art нет)")
	if hero_ok:
		var pa: AnimatedSprite2D = p.anim
		var f0: Texture2D = pa.sprite_frames.get_frame_texture("down", 0)
		chk(f0 is AtlasTexture \
				and String((f0 as AtlasTexture).atlas.resource_path).ends_with("class_warrior.png"),
			"T11: герой — AtlasTexture листа class_warrior.png")
		var row_of := {"down": 0, "left": 1, "right": 2, "up": 3}
		var reg_ok := true
		var cols := [0, 1, 0, 2]
		for dir_name: String in row_of.keys():
			if not pa.sprite_frames.has_animation(dir_name) \
					or pa.sprite_frames.get_frame_count(dir_name) != 4 \
					or not pa.sprite_frames.get_animation_loop(dir_name):
				reg_ok = false
				continue
			for fi in 4:
				var ft: Texture2D = pa.sprite_frames.get_frame_texture(dir_name, fi)
				if not (ft is AtlasTexture) or (ft as AtlasTexture).region \
						!= Rect2(cols[fi] * 16, int(row_of[dir_name]) * 16, 16, 16):
					reg_ok = false
		chk(reg_ok, "T11: герой — 4 аним × 4 кадра, regions 16 px по рядам/колонкам листа")
		var idle: Texture2D = pa.sprite_frames.get_frame_texture("down", 0)
		var drawn_h: float = float(idle.get_height()) * pa.scale.x
		var foot_h: float = pa.position.y + drawn_h / 2.0
		chk(absf(drawn_h - 16.0) <= 0.001 and absf(foot_h - 8.0) <= 0.001 \
				and pa.scale == Vector2.ONE and pa.position == Vector2.ZERO,
			"T11: герой drawn=%.3f (канон 16), стопы=%.3f (центр ноды, t51)" % [drawn_h, foot_h])
		chk(pa.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE,
			"T11: герой — фильтр INHERIT/parent (проектный nearest)")
	else:
		chk(false, "T11: герой — AtlasTexture class_warrior.png (нет аним/героя)")
		chk(false, "T11: герой — 4 аним × 4 кадра по регионам листа (нет аним/героя)")
		chk(false, "T11: герой — канон 16 / стопы 8 (нет аним/героя)")
		chk(false, "T11: герой — фильтр INHERITED (нет аним/героя)")
	# --- 3. живой бестиарий: setup-спавн вдали, проверки по месту, free ---
	# t52 (ручные листы, t51 мир 16 px): мелочь — кадры 16 px (drawn 16, стопы 8);
	# brute.png 32 px × TIERS.scale {0.72,0.85,1.0} (Гром 1.0), Ведьма ×1.12.
	_t11_mob("слизень", "res://scripts/slime.gd", "slime.png", "walk", 2, 16.0, 8.0, {})
	_t11_mob("мглокрыс", "res://scripts/mob_swarmling.gd", "mobs_swarmling.png", "idle_down", 2, 16.0, 8.0, {})
	_t11_mob("лучник", "res://scripts/mob_archer.gd", "mobs_archer.png", "idle_down", 2, 16.0, 8.0, {})
	# brute.gd: var boss := true по умолчанию — world.gd переводит ярусных мобов
	# в boss=false до setup; здесь воспроизводим канонический порядок
	_t11_mob("гнидень ярус1", "res://scripts/brute.gd", "brute.png", "walk", 2, 23.04, 11.52, {"boss": false, "tier": 1})
	_t11_mob("гнидень ярус2", "res://scripts/brute.gd", "brute.png", "walk", 2, 27.2, 13.6, {"boss": false, "tier": 2})
	_t11_mob("гнидень ярус3", "res://scripts/brute.gd", "brute.png", "walk", 2, 32.0, 16.0, {"boss": false, "tier": 3})
	_t11_mob("Гром", "res://scripts/brute.gd", "brute.png", "walk", 2, 32.0, 16.0, {"boss": true})
	_t11_mob("Ведьма Пепелища", "res://scripts/mob_boss2.gd", "brute.png", "walk", 2, 35.84, 17.92, {})
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

func _t11_mob(tag: String, script_path: String, tex_name: String, anim_name: String, \
		frames_expected: int, canon: float, foot: float, cfg: Dictionary) -> void:
	# спавн по каноническому пути (new -> add_child -> setup), далеко от героя;
	# проверки синхронные (setup строит anim сразу), free() — до физ-кадра.
	# t52: кадры — AtlasTexture ручных листов (res://assets/*.png), фильтр
	# INHERITED (проектный nearest), якорь — центр ноды (стопа = drawn/2).
	var m = load(script_path).new()
	for k: String in cfg:
		m.set(k, cfg[k])
	add_child(m)
	m.setup(world, Vector2i(400, 400))
	var ok := true
	var a: AnimatedSprite2D = m.get("anim")
	var tex: Texture2D = null
	if a == null or a.sprite_frames == null or not a.sprite_frames.has_animation(anim_name):
		ok = false
	else:
		tex = a.sprite_frames.get_frame_texture(anim_name, 0)
		ok = tex is AtlasTexture \
			and String((tex as AtlasTexture).atlas.resource_path).ends_with(tex_name) \
			and a.sprite_frames.get_frame_count(anim_name) == frames_expected \
			and String(a.animation) == anim_name
		if ok:
			var dh0 := float(tex.get_height()) * a.scale.x
			ok = absf(dh0 - canon) <= 0.05 \
				and absf(a.position.y + dh0 / 2.0 - foot) <= 0.01 \
				and a.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE
	if not ok:
		print("   QA_LP: %s — провал проверки аним-листа (anim=%s)" % [tag, a])
	var dh := (float(tex.get_height()) * a.scale.x) if (a != null and tex != null) else -1.0
	var fh := (a.position.y + dh / 2.0) if a != null else -1.0
	chk(ok, "T11: %s — %s, \"%s\" %d к., drawn=%.3f (канон %.2f), стопы=%.5f" % [
		tag, tex_name, anim_name, frames_expected, dh, canon, fh])
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

	# 2) тени по высоте актёра. t51 (мир 16 px, делитель канона 32→16): герой и
	#    слизень одного канона (16 px) — обе тени в канон-масштабе; отношение
	#    «тень растёт по высоте» проверяем удвоенным слизнем (32 px → тень 2.0,
	#    пересканирование атмосферы идёт каждые SCAN_PERIOD=0.5 с реала)
	var sl := _t12_slime()
	if sl == null:
		sl = _t12_spawn_slime(Vector2i(28, 13))
	var sh_p := p.get_node_or_null("AtmoShadow") as Sprite2D
	var sh_s := sl.get_node_or_null("AtmoShadow") as Sprite2D
	chk(sh_p != null and sh_p.scale.x >= 0.9 and sh_p.scale.x <= 1.1,
		"T12: тень героя — канон-масштаб (%.2f)" % (sh_p.scale.x if sh_p != null else -1.0))
	chk(sh_s != null and sh_s.scale.x >= 0.9 and sh_s.scale.x <= 1.1,
		"T12: тень 16px-слизня — канон-масштаб, как у героя (%.2f)" % (
			sh_s.scale.x if sh_s != null else -1.0))
	var sl_big := _t12_spawn_slime(Vector2i(40, 20))
	var big_a: AnimatedSprite2D = sl_big.get("anim")
	if big_a != null:
		big_a.scale = big_a.scale * 2.0
	await _t12_rt(0.7)
	var sh_b := sl_big.get_node_or_null("AtmoShadow") as Sprite2D
	chk(sh_b != null and sh_p != null and sh_b.scale.x >= 1.9 and sh_b.scale.x <= 2.1 \
			and sh_b.scale.x > sh_p.scale.x + 0.5,
		"T12: тень растёт по высоте актёра (%.2f против геройской %.2f)" % [
			sh_b.scale.x if sh_b != null else -1.0, sh_p.scale.x if sh_p != null else -1.0])

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

	# 9) t52 снос (закон 13.11): env4-пропы сняты — «дыхание» алтаря/портала/
	# env4-сундука вместе с их JuiceLight нет. Инфраструктура дышит дальше:
	# легасовы света в реестре атмосферы (золотой свет сундука пещеры) живые.
	var atmo = world.get_node_or_null("Atmo")
	var pls: Array = atmo.get("_prop_lights") if atmo != null else []
	var env4_gone: bool = world.cave_zone.get_node_or_null("Env4CaveProps") == null \
			and world.ashen_zone.get_node_or_null("Env4AshenProps") == null
	chk(pls.size() >= 1 and env4_gone,
		"T12: env4-слои сняты, легасовый реестр atmosphere жив (%d)" % pls.size())
	if not pls.is_empty():
		var lt: Light2D = pls[0]["light"]
		var e0: float = lt.energy
		var y0: float = (lt as Node2D).position.y
		var e_dev := 0.0
		var y_dev := 0.0
		for i in 6:
			e_dev = maxf(e_dev, absf(lt.energy - e0))
			y_dev = maxf(y_dev, absf((lt as Node2D).position.y - y0))
			await _t12_rt(0.25)
		chk(e_dev > 0.02 and y_dev > 0.2,
			"T12: легасовый свет дышит — пульс %.3f bob %.2f px" % [e_dev, y_dev])
	else:
		chk(false, "T12: легасовых светов нет — дыхание не проверено")

	# 10) финал: тряска обнулена, время = 1 (никаких залипаний после боя)
	await _t12_rt(0.45)
	chk(world.cam.offset == Vector2.ZERO,
		"T12: тряска не залипла (offset %s)" % world.cam.offset)
	chk(Engine.time_scale == 1.0, "T12: Engine.time_scale == 1.0 на выходе")
	Juice.reset()
	p.modulate = Color.WHITE

# ------------------------------------------------------------------ T13 (t33)

## Независимый мировой rect спрайта (только центральный якорь, без поворотов —
## пропы их не имеют): origin = gt * (−size/2 + offset), size — масштабированный.
func _spr_rect(sp: Sprite2D) -> Rect2:
	var tex := sp.texture
	var gt := sp.get_global_transform()
	var sz := Vector2(float(tex.get_width()), float(tex.get_height())) \
		* Vector2(absf(gt.x.x), absf(gt.y.y))
	return Rect2(gt * (Vector2(float(tex.get_width()), float(tex.get_height())) * -0.5 + sp.offset), sz)

func _biggest_prop(zone: Node2D, layer_name: String, tex_suffix: String) -> Sprite2D:
	var l = zone.get_node_or_null(NodePath(layer_name))
	if l == null:
		return null
	var best: Sprite2D = null
	var ba := 0.0
	for c in l.get_children():
		var spr := c as Sprite2D
		if spr == null or spr.texture == null or not spr.visible:
			continue
		if not String(spr.texture.resource_path).ends_with(tex_suffix):
			continue
		var a := _spr_rect(spr).get_area()
		if a > ba:
			ba = a
			best = spr
	return best

func _t13() -> void:
	# чистый мир (T12 гонял героя/модалки; глубина проверяется на свежей постройке)
	world.queue_free()
	await _frames(5)
	world = await _spawn_world()
	# 1) t52: ген-слои env4-пропов снесены; инфраструктура YS-глубины сохранена
	var gcav_l = world.cave_zone.get_node_or_null(NodePath("Env4CaveProps"))
	var gas_l = world.ashen_zone.get_node_or_null(NodePath("Env4AshenProps"))
	chk(gcav_l == null and gas_l == null,
		"T13: env4-слои пропсов снесены (cave/ashen)")
	var wsrc13: String = ""
	var wf13 := FileAccess.open("res://scripts/world.gd", FileAccess.READ)
	if wf13 != null:
		wsrc13 = wf13.get_as_text()
	chk(wsrc13.contains("_ys_canopies") and wsrc13.contains("YS_ACTOR_BIAS") \
		and not wsrc13.contains("_build_village_props"),
		"T13: YS-инфраструктура цела, ген-построители удалены из world.gd")
	# 2) актёры участвуют: моб (деревенский слизень) двигает z вместе с ногами.
	# Процесс моба глушим — ИИ/физика не сдвигают ноги между телепортом и сверкой;
	# z сверяется НА ТОЧНО с формулой от фактической y. Регресс на «статический z
	# из тайла спавна» ловится: после переноса статический z не совпадёт.
	var mob: Node2D = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and (e as Node2D).get_parent() == world.village_zone:
			mob = e as Node2D
			break
	if mob == null:
		chk(false, "T13: мобиль деревни не найден")
	else:
		mob.process_mode = Node.PROCESS_MODE_DISABLED
		mob.global_position += Vector2(0.0, 100.0)
		await _frames(4)
		var z_s: int = mob.z_index
		var fy_s: int = int(round(fposmod(mob.global_position.y, WS.YS_CYCLE))) + WS.YS_ACTOR_BIAS
		chk(z_s == fy_s, "T13: моб (юг) — z == формула ног точно (%d == %d)" % [z_s, fy_s])
		mob.global_position -= Vector2(0.0, 200.0)
		await _frames(4)
		var z_n: int = mob.z_index
		var fy_n: int = int(round(fposmod(mob.global_position.y, WS.YS_CYCLE))) + WS.YS_ACTOR_BIAS
		chk(z_n == fy_n and z_n < z_s and z_s - z_n == 200,
			"T13: моб в динамической шкале глубины (%d -> %d при -200 px)" % [z_s, z_n])
		mob.process_mode = Node.PROCESS_MODE_INHERIT
	# 3) пещера: герой в динамической шкале — z == формула стопы; южнее — глубже
	# (t52: ген-алтаря больше нет, сверка — с независимой формулой YS).
	# Физика героя глушим: телепорты не откатываются collision-разрешением,
	# world._ys_update пересчитывает z от фактических ног в любом process_mode.
	world.apply_area("cave")
	await _frames(20)
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	# Якорь y=600: пробы ставятся в середине цикла YS (0..4800) — у нулевой y
	# «северный» телепорт заворачивал бы fposmod в хвост цикла (z~4770), а
	# движок отрезает z>4096 (канон YS, не предмет t52).
	var pp0: Vector2 = world.player.global_position
	world.player.global_position = Vector2(pp0.x, 600.0)
	await _frames(2)
	var zc_south := -1
	var zc_north := -1
	world.player.global_position += Vector2(0.0, 96.0)
	await _frames(4)
	zc_south = world.player.z_index
	chk(world.player.z_index \
		== int(round(fposmod(world.player.global_position.y, WS.YS_CYCLE))) + WS.YS_ACTOR_BIAS,
		"T13: герой пещеры (юг) — z по формуле стопы (%d)" % world.player.z_index)
	world.player.global_position -= Vector2(0.0, 192.0)
	await _frames(4)
	zc_north = world.player.z_index
	chk(world.player.z_index \
		== int(round(fposmod(world.player.global_position.y, WS.YS_CYCLE))) + WS.YS_ACTOR_BIAS,
		"T13: герой пещеры (север) — z по формуле стопы (%d)" % world.player.z_index)
	chk(zc_south - zc_north == 192,
		"T13: порядок глубины: южнее — z больше ровно на разницу ног (%d > %d)" % [zc_south, zc_north])
	world.player.process_mode = Node.PROCESS_MODE_INHERIT
	# 4) Пепелище: та же пара проверок на живой постройке ashen
	world.apply_area("ashen")
	await _frames(20)
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	var pp1: Vector2 = world.player.global_position
	world.player.global_position = Vector2(pp1.x, 600.0)
	await _frames(2)
	var za_south := -1
	var za_north := -1
	world.player.global_position += Vector2(0.0, 96.0)
	await _frames(4)
	za_south = world.player.z_index
	chk(world.player.z_index \
		== int(round(fposmod(world.player.global_position.y, WS.YS_CYCLE))) + WS.YS_ACTOR_BIAS,
		"T13: герой Пепелища (юг) — z по формуле стопы (%d)" % world.player.z_index)
	world.player.global_position -= Vector2(0.0, 192.0)
	await _frames(4)
	za_north = world.player.z_index
	chk(world.player.z_index \
		== int(round(fposmod(world.player.global_position.y, WS.YS_CYCLE))) + WS.YS_ACTOR_BIAS,
		"T13: герой Пепелища (север) — z по формуле стопы (%d)" % world.player.z_index)
	chk(za_south - za_north == 192,
		"T13: порядок глубины Пепелища — ровно на разницу ног (%d > %d)" % [za_south, za_north])
	world.player.process_mode = Node.PROCESS_MODE_INHERIT
	# 5) цифры урона над всей z-шкалой зон (иначе высокий z пропов прятал бы их).
	# Хост DmgNumbers живёт на current_scene (в стенде это корень харнесса, не мир)
	# — тот же путь, что в T12; мир поднимает его fallback'ом по current_scene.
	DmgNumbers.spawn(world.player.global_position, 5, "normal")
	await _frames(3)
	var dn = get_node_or_null("DmgNumbers")
	chk(dn != null and (dn as CanvasItem).z_index >= WS.YS_HUD_Z,
		"T13: цифры урона подняты над глубиной (z=%d)" % ((dn as CanvasItem).z_index if dn != null else -1))

# ------------------------------------------------------------------ T14 (t39)

## t39 «баланс по t38»: гейт брутов по волне, масштаб ведьмы по уровню, grace
## стартового роя, сундук без меча, hp-скейл лучника/крыса, пепел с киллов = 0.
func _t14() -> void:
	# 1) brute_max_tier: w≤2→т1, w3→т2, w4+→т3
	chk(GameState.brute_max_tier(0) == 1 and GameState.brute_max_tier(1) == 1 \
			and GameState.brute_max_tier(2) == 1 and GameState.brute_max_tier(3) == 2 \
			and GameState.brute_max_tier(4) == 3 and GameState.brute_max_tier(9) == 3,
		"T14: brute_max_tier 1/1/1/2/3/3 (w0..w3,w4,w9)")
	# 2) рантайм: в пещере на волне 0 живой Гром-трэш только т1 (гейт в спавне)
	var nb := 0
	var bad := 0
	for c in world.dungeon_zone.get_children():
		if c.get_script() == null:
			continue
		if not String(c.get_script().resource_path).ends_with("brute.gd"):
			continue
		if bool(c.get("boss")):
			continue
		nb += 1
		if int(c.get("tier")) > GameState.brute_max_tier(GameState.ng_wave()):
			bad += 1
	chk(nb >= 1 and bad == 0, "T14: пещера w0: брутов %d, все tier ≤ гейта (нарушений %d)" % [nb, bad])
	# 3) ведьма: глубинная формула + таблица hp/dmg (L1 19/1, L3 31/1, L5 43/2, L6+ 48/3)
	var WB := load("res://scripts/mob_boss2.gd")
	chk(absf(WB.depth_scale(1) - 0.4) < 0.001 and absf(WB.depth_scale(3) - 0.65) < 0.001 \
			and absf(WB.depth_scale(5) - 0.9) < 0.001 and absf(WB.depth_scale(6) - 1.0) < 0.001 \
			and absf(WB.depth_scale(20) - 1.0) < 0.001,
		"T14: depth_scale 0.4/0.65/0.9/1.0/кап")
	var wl = WB.new()
	var lv0 := GameState.level
	for pair: Array in [[1, 19, 1], [3, 31, 1], [5, 43, 2], [6, 48, 3], [9, 48, 3]]:
		GameState.level = int(pair[0])
		wl._apply_depth_scale(true)
		chk(int(wl.hp) == int(pair[1]) and int(wl.dmg) == int(pair[2]),
			"T14: ведьма L%d = %d hp / %d dmg" % [pair[0], pair[1], pair[2]])
	GameState.level = lv0
	wl.free()
	# 4) grace: стартовый рой у спавна — ровно 2 особи (общий испуг с 1-й смерти)
	var rats := 0
	for c in world.village_zone.get_children():
		# c.get() на узле без свойства даёт Nil — String(Nil) падает скриптовым
		# эррором; сравниваем Variant напрямую (Nil != "glade_west" безопасно).
		if c.get("swarm_id") == "glade_west":
			rats += 1
	chk(rats == 2, "T14: старт-рой glade_west = 2 особи (было 4)")
	# 4b) t39 grace: блуждание крыса/слайма привязано к дому (канон лучника
	# _wander: за пределами нормы — возврат к home); пассивный новичок мобов
	# не дожидается (t38-база: idle-смерть ~34–43 с от блуждающих мобов).
	var fwr := FileAccess.open("res://scripts/mob_swarmling.gd", FileAccess.READ)
	var swr: String = fwr.get_as_text() if fwr != null else ""
	var fsm := FileAccess.open("res://scripts/slime.gd", FileAccess.READ)
	var stm: String = fsm.get_as_text() if fsm != null else ""
	chk(swr.contains("LEASH * 0.5") and stm.contains("CHASE_DIST * 0.5"),
		"T14: wander крыса/слайм привязан к дому (grace)")
	# 5) лёгкий hp-скейл лучника/крыса (источник: +20% MAX_HP за волну, урон не тронут)
	var fa := FileAccess.open("res://scripts/mob_archer.gd", FileAccess.READ)
	var sa: String = fa.get_as_text() if fa != null else ""
	var fw := FileAccess.open("res://scripts/mob_swarmling.gd", FileAccess.READ)
	var sw: String = fw.get_as_text() if fw != null else ""
	chk(sa.contains("0.2 * float(ngw)") and sw.contains("0.2 * float(ngw)"),
		"T14: archer/swarmling hp-скейл +20%/волну в setup")
	# 6) сундук (37,21): не меч — кошель 32..42 поверх loot 8..18 (= 40..60)
	var fi := FileAccess.open("res://scripts/interactable.gd", FileAccess.READ)
	var si: String = fi.get_as_text() if fi != null else ""
	chk(si.contains("randi_range(32, 42)") and not si.contains("has_sword"),
		"T14: chest-ветка — кошель 32..42, меча не даёт (has_sword не трогает)")
	var fl := FileAccess.open("res://scripts/loot.gd", FileAccess.READ)
	var sl: String = fl.get_as_text() if fl != null else ""
	chk(sl.contains("randi_range(8, 18)"), "T14: chest_reward 8..18 не менялся (итог сундука 40..60)")
	# 7) пепел за киллы = 0 — приёмочный инвариант (loot.gd не знает про Ash)
	chk(not sl.contains("Ash.add") and not sl.contains("Ash.spend"),
		"T14: пепел с киллов = 0 (loot.gd не вызывает Ash)")

# --------------------------------------------- T15 (t52): снос ген-пропсов ------
## t52 «план сноса»: env4-пропы, VillageProps и ген-текстуры удалены из мира.
## Контракт GREEN — отсутствие: реестров нет, _ys_props_dim пуст, в дереве мира
## ни одной ген-текстуры (art/, portraits/, env4_, cottage, grove).

func _t15_spr(layer: Node, suffix: String) -> Sprite2D:
	if layer == null:
		return null
	var best: Sprite2D = null
	var ba := 0.0
	for c in layer.get_children():
		var spr := c as Sprite2D
		if spr == null or spr.texture == null or not spr.visible:
			continue
		if suffix != "" and not String(spr.texture.resource_path).ends_with(suffix):
			continue
		var a := _t15_rect(spr).get_area()
		if a > ba:
			ba = a
			best = spr
	return best

## Мировой rect спрайта (центр + масштаб), зеркало world._ys_update.
func _t15_rect(sp: Sprite2D) -> Rect2:
	var t := sp.texture
	if t == null:
		return Rect2()
	var tr := sp.get_global_transform()
	var hw := float(t.get_width()) * 0.5
	var hh := float(t.get_height()) * 0.5
	var l0 := tr * (sp.offset + Vector2(-hw, -hh))
	var l1 := tr * (sp.offset + Vector2(hw, hh))
	return Rect2(l0, l1 - l0).abs()

func _t15() -> void:
	if world == null or world.player == null:
		chk(false, "t15: мир не построен")
		return
	# t52 «план сноса»: env4-пропов и ген-слоёв нет — контракт GREEN = отсутствие.
	var cave = world.get("_env4_cave_props")
	var ashen = world.get("_env4_ashen_props")
	chk(cave == null and ashen == null,
		"t15: env4-реестров мира нет (_env4_cave_props/_env4_ashen_props)")
	chk(world.get("village_props") == null,
		"t15: VillageProps снесён (world.village_props == null)")
	# t54 (вердикт «Деревня v4 — внедряем») + c3 («Пещера v1 — внедряем»): реестр
	# дима заполнен — но ЧЕСТНО: только спрайты кодоген-атласов assets/village/ и
	# assets/cave/ (закон 13.11: qwen нет).
	var ysd: Array = world.get("_ys_props_dim")
	var v4n := 0
	var cvn := 0
	if ysd != null:
		for p in ysd:
			var spr := p as Sprite2D
			if spr != null and spr.texture is AtlasTexture:
				var t: Texture2D = (spr.texture as AtlasTexture).atlas
				if t != null and String(t.resource_path).contains("assets/village/"):
					v4n += 1
				elif t != null and String(t.resource_path).contains("assets/cave/"):
					cvn += 1
	chk(ysd != null and v4n >= 3 and cvn >= 2 and v4n + cvn == ysd.size(),
		"t15: реестр дима = только кодоген-пропы village/cave (%d+%d/%d)" \
		% [v4n, cvn, ysd.size() if ysd != null else 0])
	# в дереве мира нет ни одной ген-текстуры: art/, portraits/, env4_ и т.п.
	var gen_seen: Array[String] = []
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var spr := n as Sprite2D
		if spr != null and spr.texture != null:
			var t: Texture = spr.texture
			while t is AtlasTexture:
				t = (t as AtlasTexture).atlas
			var p := "" if t == null else String(t.resource_path)
			if p.contains("assets/art/") or p.contains("assets/portraits/") \
					or p.contains("env4_") or p.contains("village_cottage") or p.contains("grove_"):
				gen_seen.append(p)
	chk(gen_seen.is_empty(),
		"t15: в дереве мира нет ген-текстур (%d: %s)" % [gen_seen.size(), str(gen_seen)])

# ------------------------------------------- T16 (c3+c5): интеграция «Пещера v1» -------
## Вердикт «1 внедряем; 2 сундук широкий; 3 кострище-мох — под вопросом».
## Пин-сид 42. Зеркальные пересчёты (wall/floor слот, FNV) переписаны здесь
## НЕЗАВИСИМО от scripts/cave_art.gd — как BFS/2×2 в T3/T5.

## Независимое зеркало CaveArt.wall_slot: направленные кромки только на
## открытой грани массива => по вертикали не повторяются (аудит c2 F4).
func _t16_wall_slot(rows: Array, x: int, y: int) -> int:
	if _ch(rows, x, y + 1) != "#":
		return 2   # W_BOT
	if _ch(rows, x, y - 1) != "#":
		return 1   # W_TOP
	if _ch(rows, x + 1, y) != "#":
		return 3   # W_CORNER_L
	if _ch(rows, x - 1, y) != "#":
		return 4   # W_CORNER_R
	return 0       # W_BODY

## Независимое зеркало FNV-1a + солей CaveArt (тот же канон, своя реализация).
func _t16_frac(x: int, y: int, salt: int) -> float:
	var xx := x * 31 + salt
	var yy := y * 17 + salt * 7
	var h := 2166136261
	for b in [xx & 0xFF, (xx >> 8) & 0xFF, yy & 0xFF, (yy >> 8) & 0xFF]:
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return float(h) / 4294967295.0

## Независимое зеркало CaveArt.floor_slot.
func _t16_floor_slot(rows: Array, x: int, y: int, idx: int) -> int:
	if idx == 1:
		return 1
	if idx >= 10 and idx <= 12:
		return 2
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if _ch(rows, x + dx, y + dy) == "A":
				return 2
	if _t16_frac(x, y, 11) < 0.12:
		return 3
	return 0

## bbox непрозрачных пикселей кадра (или Rect2i(0,0,0,0) для пустого).
func _t16_bbox(img: Image) -> Rect2i:
	var minx := img.get_width()
	var miny := img.get_height()
	var maxx := -1
	var maxy := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	if maxx < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)

func _t16() -> void:
	if world == null or world.dungeon_zone == null:
		chk(false, "t16: мир/пещера не построены")
		return
	var dz = world.dungeon_zone
	# 0) таблицы — бит-в-бит (вердикт в): визуальная интеграция не трогала сетку
	chk(dz.CHAR_TO_TILE == PIN_CAVE_CT, "t16: CHAR_TO_TILE пещеры бит-в-бит")
	chk(dz.BLOCKING == PIN_CAVE_BLK, "t16: BLOCKING пещеры бит-в-бит")
	var have_scripts := ResourceLoader.exists("res://scripts/cave_art.gd") \
			and ResourceLoader.exists("res://tools_art/cave_paint.gd")
	var paths := ["res://assets/cave/cave_floor_v1.png",
			"res://assets/cave/cave_wall_v1.png",
			"res://assets/cave/cave_props_v1.png"]
	var ok_assets := true
	for p in paths:
		if not ResourceLoader.exists(p):
			ok_assets = false
	chk(ok_assets, "t16: атласы пещеры v1 на месте (assets/cave/)")
	if not (have_scripts and ok_assets):
		chk(false, "t16: cave_art/cave_paint или атласы отсутствуют — пины 1..9 не выполнимы")
		return
	var CA = load("res://scripts/cave_art.gd")
	var CP = load("res://tools_art/cave_paint.gd")
	var rows: Array = dz.map_rows
	var origin: Vector2 = world.cave_zone.global_position
	# 1) размеры атласов точные
	var fimg: Image = (load(paths[0]) as Texture2D).get_image()
	var wimg: Image = (load(paths[1]) as Texture2D).get_image()
	var pimg: Image = (load(paths[2]) as Texture2D).get_image()
	chk(fimg.get_size() == CA.FLOOR_SIZE and wimg.get_size() == CA.WALL_SIZE \
			and pimg.get_size() == CA.ATLAS_SIZE,
		"t16: размеры атласов 64x16/80x16/128x64 (%s/%s/%s)" \
		% [str(fimg.get_size()), str(wimg.get_size()), str(pimg.get_size())])
	# 2) alpha-trim: bbox силуэта == кадр региона (пустых полей нет — аудит c2 F2),
	#    нижний ряд «стоячих» кадров — только OUTLINE (стопа-якорь)
	var idxm: Dictionary = PAL.color_index()
	var bad_tight := 0
	var bad_foot := 0
	for k in CA.REGIONS:
		var r: Rect2 = CA.REGIONS[k]
		var crop := pimg.get_region(Rect2i(int(r.position.x), int(r.position.y),
				int(r.size.x), int(r.size.y)))
		var bb := _t16_bbox(crop)
		if bb != Rect2i(0, 0, crop.get_width(), crop.get_height()):
			bad_tight += 1
		if String(k) in ["ALTAR", "CHEST", "STALAG1", "STALAG2", "STALAG3", "STAIRS"]:
			var last := crop.get_height() - 1
			var seen := 0
			for x in crop.get_width():
				var col := crop.get_pixel(x, last)
				if col.a < 0.5:
					continue
				seen += 1
				var info = idxm.get(PAL.key(col))
				if info == null or int(info[1]) != PAL.T_OUTLINE:
					bad_foot += 1
			if seen == 0:
				bad_foot += 1
	chk(bad_tight == 0, "t16: кадры пропов alpha-trim’лены — силуэт касается всех сторон (%d)" % bad_tight)
	chk(bad_foot == 0, "t16: стопа стоячих кадров — OUTLINE на нижней границе (%d)" % bad_foot)
	# 3) вне регионов props-атласа пикселей нет (раскладка = единственный источник)
	var outside := 0
	for y in pimg.get_height():
		for x in pimg.get_width():
			if pimg.get_pixel(x, y).a <= 0.5:
				continue
			var inside := false
			for k in CA.REGIONS:
				var r2: Rect2 = CA.REGIONS[k]
				if x >= int(r2.position.x) and x < int(r2.position.x + r2.size.x) \
						and y >= int(r2.position.y) and y < int(r2.position.y + r2.size.y):
					inside = true
					break
			if not inside:
				outside += 1
	chk(outside == 0, "t16: props-атлас чист вне регионов REGIONS (%d px)" % outside)
	# 4) детерминизм: побайтовый in-process rebake == закоммиченные файлы
	var eq_f: bool = CP.bake_floor_atlas().save_png_to_buffer() \
			== FileAccess.get_file_as_bytes(paths[0])
	var eq_w: bool = CP.bake_wall_atlas().save_png_to_buffer() \
			== FileAccess.get_file_as_bytes(paths[1])
	var eq_p: bool = CP.bake_props_atlas(CA.REGIONS, CA.ATLAS_SIZE)["img"] \
			.save_png_to_buffer() == FileAccess.get_file_as_bytes(paths[2])
	chk(eq_f and eq_w and eq_p,
		"t16: rebake == committed md5 %s/%s/%s" % [
			FileAccess.get_md5(paths[0]), FileAccess.get_md5(paths[1]),
			FileAccess.get_md5(paths[2])])
	# 5) тайл-источники и зеркальный пересчёт КАЖДОЙ клетки (вердикт в/б)
	var tm: TileMapLayer = dz.tilemap
	chk(tm != null and tm.tile_set.get_source(1) != null and tm.tile_set.get_source(2) != null,
		"t16: tileset пещеры содержит визуальные источники 1/2")
	var bad_map := 0
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			var ch := row[x]
			if not PIN_CAVE_CT.has(ch):
				continue
			var idx := int(PIN_CAVE_CT[ch])
			if idx == 3 and GameState.door_opened:
				idx = 0
			var src := tm.get_cell_source_id(Vector2i(x, y))
			var co := tm.get_cell_atlas_coords(Vector2i(x, y))
			if idx == 2:
				if src != 2 or co.x != _t16_wall_slot(rows, x, y):
					bad_map += 1
			elif idx == 0 or idx == 1 or idx == 10 or idx == 11:
				if x == dz.chest_tile.x and y == dz.chest_tile.y and GameState.has_amulet:
					if src != 0 or co.x != 12:
						bad_map += 1
				elif src != 1 or co.x != _t16_floor_slot(rows, x, y, idx):
					bad_map += 1
			elif src != 0 or co.x != idx:
				bad_map += 1
	chk(bad_map == 0, "t16: рисунок каждой клетки = зеркальный пересчёт (ошибок %d)" % bad_map)
	# 6) направленные кромки по факту тайлмапа: под WALL_BOT никогда нет стены
	#    (однократная кромка, вертикального репита нет — аудит c2 F4)
	var bot_n := 0
	var bot_bad := 0
	for y in rows.size():
		for x in String(rows[y]).length():
			if String(rows[y])[x] != "#":
				continue
			if tm.get_cell_source_id(Vector2i(x, y)) == 2 \
					and tm.get_cell_atlas_coords(Vector2i(x, y)).x == 2:
				bot_n += 1
				if _ch(rows, x, y + 1) == "#":
					bot_bad += 1
	chk(bot_n > 0 and bot_bad == 0,
		"t16: WALL_BOT однократен — подошва над проходимым, репита нет (%d клеток, %d)" % [bot_n, bot_bad])
	# 7) пропы: слой CaveV1 — алтарь на каждой «A», сундук на «C», якоря стопой
	#    на нижнюю границу клетки, z по V-01; сталактиты — над актёров
	var layer: Node2D = world.cave_zone.get_node_or_null("CaveV1")
	chk(layer != null, "t16: слой CaveV1 построен в пещере")
	if layer == null:
		return
	var key_of := {}  # Rect2 региона -> имя
	for k in CA.REGIONS:
		key_of[CA.REGIONS[k]] = String(k)
	var by_key := {}
	for c in layer.get_children():
		var spr := c as Sprite2D
		if spr == null or not (spr.texture is AtlasTexture):
			continue
		var at := spr.texture as AtlasTexture
		var kk: String = String(key_of.get(at.region, ""))
		if kk == "":
			continue
		if not by_key.has(kk):
			by_key[kk] = []
		by_key[kk].append(spr)
	var altar_cells: Array = []
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if row[x] == "A":
				altar_cells.append(Vector2i(x, y))
	var alt_n: Array = by_key.get("ALTAR", [])
	var alt_bad := 0
	for ac: Vector2i in altar_cells:
		var want_bottom: float = origin.y + float(ac.y + 1) * 16.0
		var want_x: float = origin.x + float(ac.x) * 16.0 + 8.0
		var found := false
		for s in alt_n:
			var rr := _t15_rect(s)
			if absf(rr.end.y - want_bottom) < 0.6 and absf(rr.get_center().x - want_x) < 0.6 \
					and s.z_index == int(round(fposmod(rr.end.y, WS.YS_CYCLE))):
				found = true
				break
		if not found:
			alt_bad += 1
	chk(alt_n.size() == altar_cells.size() and alt_bad == 0,
		"t16: алтарь 1.6H на каждой «A» (стопа=граница клетки, z V-01) (%d/%d, bad %d)" \
		% [alt_n.size(), altar_cells.size(), alt_bad])
	# сундук ~0.8H (вердикт c10 «сундук уменьши»: 33×16 → 26×13): визуальный
	# слой >1 клетки; коллайдер клетки и grid — целы
	var chst: Array = by_key.get("CHEST", [])
	var ct: Vector2i = dz.chest_tile
	var chest_spr: Sprite2D = null
	if chst.size() == 1 and ct.x >= 0:
		chest_spr = chst[0]
		var rr := _t15_rect(chest_spr)
		var ok_geom: bool = absf(rr.size.x - 26.0) < 0.6 \
				and absf(rr.size.y - 13.0) < 0.6 \
				and absf(rr.get_center().x - (origin.x + float(ct.x) * 16.0 + 8.0)) < 0.6 \
				and absf(rr.end.y - (origin.y + float(ct.y + 1) * 16.0)) < 0.6
		chk(ok_geom and not dz.cell_walkable(ct),
			"t16: сундук ~0.8H 26x13 поверх клеточного коллайдера «C» (walkable=%s)" \
			% str(dz.cell_walkable(ct)))
		var space := get_world_2d().direct_space_state
		var q := PhysicsPointQueryParameters2D.new()
		q.position = origin + Vector2(float(ct.x) * 16.0 + 8.0, float(ct.y) * 16.0 + 8.0)
		q.collision_mask = 2
		q.collide_with_bodies = true
		# «этаж» пещеры выключен (process DISABLED) — тела вне симуляции;
		# включаем зону на время пробы и возвращаем как было.
		world.cave_zone.process_mode = Node.PROCESS_MODE_INHERIT
		await _frames(2)
		var hits := space.intersect_point(q, 4)
		var solid := false
		for h in hits:
			var col: Object = h.get("collider")
			if col is StaticBody2D and world.cave_zone.is_ancestor_of(col as Node):
				solid = true
		world.cave_zone.process_mode = Node.PROCESS_MODE_DISABLED
		chk(solid, "t16: физика клетки сундука осталась (стандартный блок не изменён)")
	else:
		chk(false, "t16: сундук не найден на клетке «C» (%d)" % chst.size())
	# сталактиты: висячие, z выше потолка актёров, верх кадра = верх клетки-свода
	var stalc_all: Array = by_key.get("STALC3", []) + by_key.get("STALC2", []) \
			+ by_key.get("STALC1", [])
	var stalc_ok := 0
	for s in stalc_all:
		var rr := _t15_rect(s)
		var wx := int(round((rr.get_center().x - origin.x - 8.0) / 16.0))
		var wy := int(round((rr.position.y - origin.y) / 16.0))
		if s.z_index == CA.Z_STALC and _ch(rows, wx, wy) == "#" \
				and _ch(rows, wx, wy + 1) in [".", ",", "A", "C"]:
			stalc_ok += 1
	chk(stalc_all.size() > 0 and stalc_ok == stalc_all.size() and int(CA.Z_STALC) > 480,
		"t16: сталактиты над актёров (z=%s>480), верх на границе свода (%d/%d)" \
		% [str(CA.Z_STALC), stalc_ok, stalc_all.size()])
	# сталагмиты: в общем реестре дима, стопа на нижней границе клетки пола под «#»
	var ysd: Array = world.get("_ys_props_dim")
	var g_n := (by_key.get("STALAG1", []) as Array).size() \
			+ (by_key.get("STALAG2", []) as Array).size() \
			+ (by_key.get("STALAG3", []) as Array).size()
	var g_ok := 0
	for kk in ["STALAG1", "STALAG2", "STALAG3"]:
		for s in by_key.get(kk, []):
			if not ysd.has(s):
				continue
			var rr := _t15_rect(s)
			var wx := int(round((rr.get_center().x - origin.x - 8.0) / 16.0))
			var wy := int(round((rr.end.y - origin.y) / 16.0)) - 1
			if _ch(rows, wx, wy) in [".", ","] and _ch(rows, wx, wy - 1) == "#" \
					and s.z_index == int(round(fposmod(rr.end.y, WS.YS_CYCLE))):
				g_ok += 1
	chk(g_n > 0 and g_ok == g_n,
		"t16: сталагмиты в реестре дима, стопа у нижней границы клетки (%d/%d)" % [g_ok, g_n])
	# 8) живой дим (вердикт г): герой севернее стопы сундука >= 40% бокса -> 0.5,
	#    южнее — ровно 1.0 (тот же контракт, что кроны/деревня)
	if chest_spr != null:
		var p = world.player
		var p0: Vector2 = p.global_position
		p.set_physics_process(false)
		var cxg: float = origin.x + float(ct.x) * 16.0 + 8.0
		var footg: float = origin.y + float(ct.y + 1) * 16.0
		p.global_position = Vector2(cxg, footg - 10.0)
		await _frames(24)
		var a_dim: float = chest_spr.modulate.a
		p.global_position = Vector2(cxg, footg + 20.0)
		await _frames(24)
		var a_near: float = chest_spr.modulate.a
		p.global_position = p0
		p.set_physics_process(true)
		chk(a_dim > 0.35 and a_dim < 0.65 and a_near >= 0.995,
			"t16: живой дим сундука — севернее %.2f, южнее %.2f" % [a_dim, a_near])
	else:
		chk(false, "t16: дим не проверен — сундука нет")
	# 9) чистые комментарии (вердикт д): ни CJK, ни склеек в генераторе/модулях
	var bad_src := 0
	for fp in ["res://tools_art/sheet_cave.gd", "res://tools_art/cave_paint.gd",
			"res://scripts/cave_art.gd"]:
		var fa := FileAccess.open(fp, FileAccess.READ)
		if fa == null:
			bad_src += 1
			continue
		var src: String = fa.get_as_text()
		for i in src.length():
			var u := src.unicode_at(i)
			if (u >= 0x3040 and u <= 0x30FF) or (u >= 0x3400 and u <= 0x4DBF) \
					or (u >= 0x4E00 and u <= 0x9FFF) or (u >= 0xF900 and u <= 0xFAFF) \
					or (u >= 0xFF01 and u <= 0xFF5E):
				bad_src += 1
				break
		if src.contains("противInternal") or src.contains("уfooter") \
				or src.contains("теньfoot-"):
			bad_src += 1
	chk(bad_src == 0, "t16: комментарии чистые — без CJK и склеек (%d файлов с дефектами)" % bad_src)
	# 10) c5 факелы (вердикт «факелы лучше»): состав 3..5, два кадра фликера,
	#     легальный настенный монтаж выше головы, пульс света, мох-кострища
	#     в дереве пещеры нет, расстановка бит-детерминирована
	if not (CA.REGIONS.has("TORCH1") and CA.REGIONS.has("TORCH2")):
		chk(false, "t16: c5 — кадры TORCH1/TORCH2 не в REGIONS (поставка не на месте)")
		return
	var torches: Array = []
	for c in layer.get_children():
		if c is Sprite2D and c.get("t0") != null and c.get("t1") != null:
			torches.append(c)
	chk(torches.size() >= 3 and torches.size() <= 5,
		"t16: состав факелов 3..5 (%d)" % torches.size())
	var trh_ok := 0
	var trh_cells: Array = []
	for t in torches:
		var s2 := t as Sprite2D
		var a0 := s2.get("t0") as AtlasTexture
		var a1 := s2.get("t1") as AtlasTexture
		var lt: Object = s2.get("lit")
		var rr := _t15_rect(s2)
		var wx := int(round((rr.get_center().x - origin.x - 8.0) / 16.0))
		# низ кронштейна — на 2 px выше верхней границы проходимой клетки
		var wy := int(round((rr.end.y - origin.y + 2.0) / 16.0)) - 1
		trh_cells.append(Vector2i(wx, wy))
		var frames_ok: bool = a0 != null and a1 != null and a0 != a1 \
				and a0.region == CA.REGIONS["TORCH1"] and a1.region == CA.REGIONS["TORCH2"]
		var mount_ok: bool = _ch(rows, wx, wy) == "#" and _ch(rows, wx, wy + 1) in [".", ","] \
				and absf(rr.end.y - (origin.y + float(wy + 1) * 16.0 - 2.0)) < 0.6
		var depth_ok: bool = s2.z_index == int(round(fposmod(rr.end.y, WS.YS_CYCLE))) \
				and not ysd.has(s2)
		var light_ok: bool = lt is PointLight2D
		if frames_ok and mount_ok and depth_ok and light_ok:
			trh_ok += 1
	chk(trh_ok == torches.size() and torches.size() > 0,
		"t16: факелы — 2 кадра (TORCH1/2), стена над проходимым, выше головы," \
				+ " z V-01, вне дима, со светом (%d/%d)" % [trh_ok, torches.size()])
	# расстановка = независимое зеркало алгоритма (тот же контракт порядка)
	var slots_a := _t16_torch_slots(rows, dz.chest_tile, dz.spawn_tile, dz.door_tile)
	var slots_b := _t16_torch_slots(rows, dz.chest_tile, dz.spawn_tile, dz.door_tile)
	var cells_eq: bool = slots_a == slots_b and slots_a.size() == torches.size()
	if cells_eq:
		for i in slots_a.size():
			if slots_a[i] != trh_cells[i]:
				cells_eq = false
				break
	chk(cells_eq,
		"t16: расстановка факелов детерминирована и совпадает с зеркалом (%d/%d)" \
				% [slots_a.size(), torches.size()])
	# живой фликер + пульс: зона пещеры активна лишь мгновение пробы (паттерн
	# физ-пробы сундука); кадры обязан показать оба, свет — ненулевой размах
	if not torches.is_empty():
		var ts0 := torches[0] as Sprite2D
		world.cave_zone.process_mode = Node.PROCESS_MODE_INHERIT
		var seen_frames := {}
		var e_min := 99.0
		var e_max := -99.0
		# окно — НАСТОЯЩЕЕ время (в headless кадры могут идти быстрее реального):
		# 1.3 c ≈ 45 % периода алтарного пульса (2.2 рад/с) => размах гарантирован
		var t_end := Time.get_ticks_msec() + 1300
		while Time.get_ticks_msec() < t_end:
			await _frames(2)
			var cur := ts0.texture as AtlasTexture
			if cur != null:
				seen_frames[cur.region.position.x] = true
			var l2: Object = ts0.get("lit")
			if l2 is PointLight2D:
				e_min = minf(e_min, float(l2.energy))
				e_max = maxf(e_max, float(l2.energy))
		world.cave_zone.process_mode = Node.PROCESS_MODE_DISABLED
		chk(seen_frames.has(CA.REGIONS["TORCH1"].position.x) \
				and seen_frames.has(CA.REGIONS["TORCH2"].position.x),
			"t16: факел мигает двумя кадрами (паттерн A_TORCH T=0.25 c)")
		chk(e_max - e_min > 0.15,
			"t16: пульс света ненулевой (размах %.3f, амплитуда как у алтаря)" % (e_max - e_min))
	# кострище-мох: кадр сохранён в атласе как искусство, но в дереве пещеры
	# ни одного спрайта с регионом BRAZIER
	var brz_n := 0
	var stack: Array = [world.cave_zone]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is Sprite2D and (nd as Sprite2D).texture is AtlasTexture \
				and ((nd as Sprite2D).texture as AtlasTexture).region == CA.REGIONS["BRAZIER"]:
			brz_n += 1
		for chd in nd.get_children():
			stack.append(chd)
	var brz_reg: Rect2 = CA.REGIONS["BRAZIER"]
	var brz_px := 0
	for y in int(brz_reg.size.y):
		for x in int(brz_reg.size.x):
			if pimg.get_pixel(int(brz_reg.position.x) + x, int(brz_reg.position.y) + y).a > 0.5:
				brz_px += 1
	chk(brz_n == 0 and brz_px > 0,
			"t16: мох-кострища в дереве пещеры нет, кадр жив в атласе (%d px)" % brz_px)
	# 11) c7 пылинки пещеры: залы, 2..4 на зал, лимит, ненулевое падение
	#     (fmod-цикл без накопления), живое движение, вне реестра дима
	var dust: Node = world.cave_zone.find_child("CaveDust", true, false)
	if dust == null:
		chk(false, "t16: c7 — CaveDust не найден (поставка не на месте)")
		return
	var motes: Array = dust.get("motes")
	var hl: Array = CA.halls(rows)
	chk(not hl.is_empty() and motes.size() > 0 and motes.size() <= int(CA.DUST_MAX),
		"t16: пылинки: залов %d, пылинок %d (лимит %d)" % [hl.size(), motes.size(), int(CA.DUST_MAX)])
	# каждая пылинка вписана в bbox своего зала (старт от потолка, высота =
	# высота зала); на зал 2..4 пылинки
	var par_ok := 0
	var per_hall := {}
	for m in motes:
		var mx := float(m["x"])
		var mtop := float(m["top"])
		var mh := float(m["h"])
		for hi in hl.size():
			var hall: Dictionary = hl[hi]
			var hx0 := float(int(hall["left"])) * 16.0
			var hx1 := (float(int(hall["right"])) + 1.0) * 16.0
			var hy0 := float(int(hall["top"])) * 16.0
			var hy1 := (float(int(hall["bottom"])) + 1.0) * 16.0
			if mx >= hx0 - 0.1 and mx <= hx1 + 0.1 and absf(mtop - hy0) < 0.1 \
					and absf(mtop + mh - hy1) < 0.1:
				par_ok += 1
				per_hall[hi] = int(per_hall.get(hi, 0)) + 1
				break
	var halls_ok := per_hall.size() > 0
	for hi in per_hall:
		if int(per_hall[hi]) < 2 or int(per_hall[hi]) > 4:
			halls_ok = false
	chk(par_ok == motes.size() and halls_ok,
		"t16: пылинки вписаны в залы, 2..4 на зал (%d/%d, залов %d)" \
				% [par_ok, motes.size(), per_hall.size()])
	# падение ненулевое у каждой (зеркало y = top + fmod(t*spd + ph*h, h))
	var move_ok := 0
	for m in motes:
		var mtop := float(m["top"])
		var mh := float(m["h"])
		var spd := float(m["spd"])
		var ph := float(m["ph"])
		var differs := false
		var ys: Array = []
		for tv: float in [0.3, 1.7, 4.9]:
			ys.append(mtop + fmod(tv * spd + ph * mh, mh))
		if not (absf(float(ys[0]) - float(ys[1])) < 0.01 and absf(float(ys[1]) - float(ys[2])) < 0.01):
			differs = true
		if differs and spd > 0.0 and spd <= 8.0:
			move_ok += 1
	chk(move_ok == motes.size(),
		"t16: падение ненулевое у всех пылинок, скорость медленная (%d/%d)" \
				% [move_ok, motes.size()])
	# живое движение при активной зоне (окно по НАСТОЯЩЕМУ времени: в headless
	# кадры быстрее реального); счёт не растёт (без накопления)
	var n0 := motes.size()
	var y0s: Array = []
	var ymoved: Array = []
	for m in motes:
		y0s.append((m["spr"] as Sprite2D).position.y)
		ymoved.append(false)
	world.cave_zone.process_mode = Node.PROCESS_MODE_INHERIT
	var t_end := Time.get_ticks_msec() + 1300
	while Time.get_ticks_msec() < t_end:
		await _frames(2)
		for i in motes.size():
			var dy: float = absf((motes[i]["spr"] as Sprite2D).position.y - float(y0s[i]))
			if dy > 0.5:
				ymoved[i] = true
	var live_move := 0
	for f in ymoved:
		if bool(f):
			live_move += 1
	var grew := motes.size() != n0
	world.cave_zone.process_mode = Node.PROCESS_MODE_DISABLED
	chk(live_move > 0 and not grew,
			"t16: пылинки живые (движение %d), счёт не растёт (%d)" % [live_move, motes.size()])
	# вне реестра дима (в воздухе, героя не накрывают)
	var dim_free := 0
	for m in motes:
		if not ysd.has(m["spr"]):
			dim_free += 1
	chk(dim_free == motes.size(), "t16: пылинки вне реестра дима (%d)" % dim_free)
	# 12) c12 арка входа (вердикт «вся графика в едином стиле»): канонный кадр
	#     STAIRS с обеих сторон двери вместо легаси-кадра dungeon_tiles.png
	if not CA.REGIONS.has("STAIRS"):
		chk(false, "t12: c12 — арка STAIRS не в REGIONS (поставка не на месте)")
		return
	var sr: Rect2 = CA.REGIONS["STAIRS"]
	var arch_px := 0
	var arch_pal := 0
	for y in int(sr.size.y):
		for x in int(sr.size.x):
			var ac := pimg.get_pixel(int(sr.position.x) + x, int(sr.position.y) + y)
			if ac.a > 0.5:
				arch_px += 1
				if idxm.has(PAL.key(ac)):
					arch_pal += 1
	chk(sr.size == Vector2(16, 24) and arch_px > 100 and arch_pal == arch_px,
			"t12: арка 16×24 в атласе и строго из палитры (%d/%d px)" % [arch_pal, arch_px])
	# обе зоны: ровно две арки, ни одного спрайта на легаси-листе dungeon_tiles
	var legacy_tex := load("res://assets/dungeon_tiles.png")
	var stacks: Array = [world.village_zone, world.cave_zone]
	var arches: Array = []
	var legacy_n := 0
	while not stacks.is_empty():
		var nd: Node = stacks.pop_back()
		if nd is Sprite2D:
			var tx: Texture2D = (nd as Sprite2D).texture
			if tx is AtlasTexture and (tx as AtlasTexture).region == CA.REGIONS["STAIRS"]:
				arches.append(nd)
			elif tx != null and (tx == legacy_tex \
					or (tx is AtlasTexture and (tx as AtlasTexture).atlas == legacy_tex)):
				legacy_n += 1
		for chd in nd.get_children():
			stacks.append(chd)
	chk(legacy_n == 0,
			"t12: легаси-спрайтов dungeon_tiles в зонах деревни/пещеры нет (%d)" % legacy_n)
	# геометрия: стопа на нижней границе клетки якоря, центр по x, z — V-01
	var st: Array = dz.loaded_map.get("stairs_out", [])
	var et := Vector2i(40, 17) # CAVE_ENTRANCE_TILE из world.gd — закреплённая копия
	var v_or: Vector2 = world.village_zone.global_position
	var cave_arch: Sprite2D = null
	var vil_arch: Sprite2D = null
	for a2 in arches:
		var s2a := a2 as Sprite2D
		var rr2 := _t15_rect(s2a)
		if absf(rr2.end.y - (origin.y + float(int(st[1]) + 1) * 16.0)) < 0.6 \
				and absf(rr2.get_center().x - (origin.x + (float(int(st[0])) + 0.5) * 16.0)) < 0.6:
			cave_arch = s2a
		elif absf(rr2.end.y - (v_or.y + float(et.y + 1) * 16.0)) < 0.6 \
				and absf(rr2.get_center().x - (v_or.x + (float(et.x) + 0.5) * 16.0)) < 0.6:
			vil_arch = s2a
	var z_ok := 0
	for a3 in [cave_arch, vil_arch]:
		if a3 == null:
			continue
		if (a3 as Sprite2D).z_index == int(round(fposmod(_t15_rect(a3).end.y, WS.YS_CYCLE))):
			z_ok += 1
	chk(arches.size() == 2 and cave_arch != null and vil_arch != null and z_ok == 2,
			"t12: арки с обеих сторон двери — стопа на границе клетки, z V-01 (%d/2)" % z_ok)
	# геймплей под арками не тронут: клетки входа/выхода проходимы
	chk(bool(world.call("_village_walkable", et)) \
			and bool(dz.cell_walkable(Vector2i(int(st[0]), int(st[1])))),
			"t12: клетки под арками проходимы — проход открыт (двери не тронуты)")


## Независимое зеркало расстановки факелов (тот же контракт: якоря сундук/вход/
## дверь/алтари по карте, фиксированный список смещений, стена с проходимым
## полом снизу, не более 5; смещения — дословная копия договора c5).
func _t16_torch_slots(rows: Array, chest: Vector2i, spawn: Vector2i,
		door: Vector2i) -> Array:
	var dirs := [Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, -1), Vector2i(2, -1), Vector2i(-2, -1), Vector2i(2, 0),
			Vector2i(-2, 0), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(3, -1),
			Vector2i(-3, -1), Vector2i(3, 0), Vector2i(-3, 0), Vector2i(2, -2),
			Vector2i(-2, -2), Vector2i(3, -2), Vector2i(-3, -2), Vector2i(0, -2),
			Vector2i(0, -3)]
	var anchors: Array = []
	if chest.x >= 0:
		anchors.append(chest)
	if spawn.x >= 0:
		anchors.append(spawn)
	if door.x >= 0:
		anchors.append(door)
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			if row[x] == "A":
				anchors.append(Vector2i(x, y))
	var out: Array = []
	var used := {}
	for an in anchors:
		if out.size() >= 5:
			break
		for d in dirs:
			var m := Vector2i(int(an.x) + d.x, int(an.y) + d.y)
			if used.has(m):
				continue
			if _ch(rows, m.x, m.y) != "#":
				continue
			if not (_ch(rows, m.x, m.y + 1) in [".", ","]):
				continue
			used[m] = true
			out.append(m)
			break
	return out
