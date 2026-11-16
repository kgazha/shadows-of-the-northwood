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
##      dungeon_tiles.png — MD5 после t52-реставрации клеток 6/7; Тенеплёт жив
##      в Пепелище (c21, спавн из координат генератора; деревня/пещера — ноль, T13).
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
##  T46 микроволна 16.11: пины на юзер-фиксы дня — рывок вдоль выпуклой стены
##      (упор не гасит, скольжение доводит до мили, удар после приземления),
##      «усы» мобов (обход камня + тупик = встать), агро только по прямой
##      видимости и память 1.6 с (уход к последнему видимому месту), возврат из
##      пещеры/Пепелища к арке входа после резюма. Подвкладки журнала — qa_vlg.

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
	await _t17()
	await _t18()
	_t23()
	_t25()
	_t27()
	_t29()
	_t30()
	_t34()
	_t35()
	_t36()
	await _t37()
	await _t41()
	await _t42()
	await _t44()
	await _t46()
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
	# c13 (вердикт пользователя «алтарей много, можно оставить 1-2»): на пин-сиде
	# ровно 2 алтаря — по одному в алтарной комнате и в алтарном зале босса.
	chk(altar_n == 2, "t13: на карте ровно 2 алтаря — по одному в зале (%d)" % altar_n)
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
# (48×64: кадры 16 px, ряды down/left/right/up, 4 кадра/аним; с c19 порядок
# кадров цикла [1,0,2,0] — колонки те же 0/1/2 листа class_warrior.png),
# слизень — slime.png (2 кадра bob), мглокрыс/лучник — mobs_swarmling/mobs_archer.png
# ({idle,walk,act}_{dirs}, idle 2 кадра), гнидень/Гром/Ведьма — brute.png
# (32 px кадры × TIERS.scale; Ведьма ×1.12). Фильтры — INHERITED (проектный
# nearest; мипмапсов на листах нет). dungeon_tiles.png после восстановления
# клеток 6/7 из доген-блоба пинится MD5. Тенеплёт (wraith) оживлён в Пепелище (c21).
const T11_GEN_GONE := [
	"hero_idle.png", "hero_walk.png", "hero_attack.png",
	"mob_slime.png", "mob_swarmling.png", "mob_archer.png",
	"mob_rotspawn.png", "mob_grom.png", "mob_witch.png",
]
# Канонический MD5 dungeon_tiles.png после t52-восстановления клеток 6/7
# (каменные плиты) из предген-блоба 8fb87cb^; ниже — сверка hex_encode().
# c33: честная RED->GREEN — байтовое золото держало старые CAVE_ROCK-пиксели
# dungeon_tiles; волна c36 (вердикт c35 «пещерный сундук берём»): легаси-тайл 12
# v2 пересобран детерминированным тулом c36_chest12.gd СТРОГО из тайла 11
# (зона раскрытия 48 px рядов 0..3, корпус байт-в-бит, новых цветов 0; двойной
# bake тула дал идентичные md5 — канон ниже честным RED->GREEN обновлён).
const T11_DUNGEON_MD5 := "d39709f47d2ee25cbfc9e7a1432431cd"

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
		# c19 (вердикт «добавляем цикл ходьбы», лист sheet_walk_v1): порядок
		# кадров цикла [0,1,0,2] -> [1,0,2,0]; сами regions 16 px по рядам
		# листа — как пинились.
		var cols := [1, 0, 2, 0]
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
	# --- 4. Тенеплёт ---
	# T11: легаси-арта тенеплёта в assets/art нет (утверждённый лист — корневой
	# assets/mobs_wraith.png, он не под сканом). c21 (вердикт пользователя
	# «тенеплёт — оживить»): ссылка на mob_wraith допускается ТОЛЬКО в
	# ashen_zone.gd — единственной зоне спавна; world.gd и dungeon_zone.gd —
	# по-прежнему чисты (T13: деревня/пещера вне геймплея для тенеплёта;
	# живой ноль в этих зонах пинит qa_wr0 S1).
	var wraith_art := ""
	var d := DirAccess.open("res://assets/art")
	if d != null:
		for fn in d.get_files():
			if String(fn).to_lower().contains("wraith"):
				wraith_art += String(fn) + " "
	chk(wraith_art == "", "T11: в assets/art нет ассетов Тенеплёта (wraith не интегрирован)")
	var wraith_ref := ""
	var wraith_other := ""
	for sp: String in ["res://scripts/world.gd", "res://scripts/ashen_zone.gd", "res://scripts/dungeon_zone.gd"]:
		var f2 := FileAccess.open(sp, FileAccess.READ)
		if f2 != null:
			if f2.get_as_text().contains("mob_wraith"):
				if sp.ends_with("ashen_zone.gd"):
					wraith_ref += sp.get_file() + " "
				else:
					wraith_other += sp.get_file() + " "
			f2.close()
	chk(wraith_ref.contains("ashen_zone.gd"), "c21: ashen_zone ссылается на mob_wraith (оживлён вердиктом)")
	chk(wraith_other == "", "c21: ссылка mob_wraith только в ashen_zone (world/dungeon чисты, T13 цел)")

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
	var fgn := 0
	if ysd != null:
		for p in ysd:
			var spr := p as Sprite2D
			if spr != null and spr.texture is AtlasTexture:
				var t: Texture2D = (spr.texture as AtlasTexture).atlas
				if t != null and String(t.resource_path).contains("assets/village/"):
					v4n += 1
				elif t != null and String(t.resource_path).contains("assets/cave/"):
					cvn += 1
				elif t != null and String(t.resource_path).contains("assets/forest/"):
					fgn += 1  # w3int (вердикт «берём»): подлесок леса v1
	chk(ysd != null and v4n >= 3 and cvn >= 2 and fgn >= 10 and v4n + cvn + fgn == ysd.size(),
		"t15: реестр дима = только кодоген-пропы village/cave/forest (%d+%d+%d/%d)" \
		% [v4n, cvn, fgn, ysd.size() if ysd != null else 0])
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

## c14: метрика вертикального wrap 16×16 кадра — mean|Δ|(RGB) стыка «низ↔верх»
## против средней mean|Δ| соседних строк поля (формула пин-метрики шва листа,
## независимая реализация).
func _t14_seam_y(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var seam := 0.0
	for x in w:
		seam += _t14_db(img, x, h - 1, x, 0)
	seam /= float(w)
	var field := 0.0
	for y in range(h - 1):
		for x in w:
			field += _t14_db(img, x, y, x, y + 1)
	field /= float((h - 1) * w)
	return seam / maxf(field, 0.001)

## c14: парная горизонтальная метрика (стык «правый край↔левый» против поля).
func _t14_seam_x(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var seam := 0.0
	for y in h:
		seam += _t14_db(img, w - 1, y, 0, y)
	seam /= float(h)
	var field := 0.0
	for y in h:
		for x in range(w - 1):
			field += _t14_db(img, x, y, x + 1, y)
	field /= float(h * (w - 1))
	return seam / maxf(field, 0.001)

func _t14_db(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var a := img.get_pixel(x0, y0)
	var b := img.get_pixel(x1, y1)
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0

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
		"t16: размеры атласов 64x16/80x16/128x80 (%s/%s/%s)" \
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
		if String(k) in ["ALTAR", "CHEST", "CHEST_OPEN", "STALAG1", "STALAG2", "STALAG3", "STAIRS"]:
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
	# 6b) c14 (вердикт пользователя «подправь тайл», ревью c4 F3): вертикальный wrap
	#     CORNER_L (стык «низ↔верх» кадра 3 атласа стен) — формула пин-метрики шва
	#     из листа (mean|Δ| шва против поля), независимая реализация здесь.
	#     Порог уровня тела: WALL-тело 1.21, свод 1.29; до правки было 1.75 —
	#     светлая нить с периодом 4 читалась линией на столбике угла.
	#     c33: перекалибровка цвета (не сетки) под рампу C: измерено 1.50 (CAVE было
	#     1.48, +0.019 при равной светлоте тонов; тело 1.205, свод 1.275 — не хуже),
	#     патология 1.75 по-прежнему далеко; формальные 2.0/2.2 ниже не тронуты.
	var cl_f: Image = wimg.get_region(Rect2i(48, 0, 16, 16))
	var ry_cl := _t14_seam_y(cl_f)
	var rx_cl := _t14_seam_x(cl_f)
	chk(ry_cl < 1.55, "t14: вертикальный wrap CORNER_L на уровне тела (<1.55 c33; %.2f)" % ry_cl)
	chk(ry_cl < 2.0 and rx_cl < 2.2,
			"t14: CORNER_L wrap в формальных порогах 2.0/2.2 (верт %.2f / гор %.2f)" % [ry_cl, rx_cl])
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
	# c13: в дереве ровно 2 спрайта алтаря (по клеткам) — висячих нет, дим-реестр
	# и свет следуют за фактическими алтарями (зеркало выше покрывает геометрию)
	chk(altar_cells.size() == 2 and alt_n.size() == 2,
			"t13: в дереве пещеры ровно 2 алтаря — объекты строго по клеткам (%d/%d)" \
			% [alt_n.size(), altar_cells.size()])
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

# ------------------------------------------------------------------ T17 (c19)

## c19 «цикл ходьбы в игре» (вердикт «добавляем», лист sheet_walk_v1 утверждён).
## Фазы кадра — от пройденного пути, НЕ от времени; покой = стойка; мглокрыс —
## 2-фазный цикл. На голом HEAD честный RED: констант WALK_SEQ/WALK_BOB/
## PX_PER_PHASE/RAT_PX_PER_PHASE нет в скриптах (get_script_constant_map).
func _t17() -> void:
	var p = world.player
	if p == null:
		chk(false, "t17: героя нет в мире")
		return
	var pcm: Dictionary = p.get_script().get_script_constant_map()
	var has_hero: bool = pcm.has("WALK_SEQ") and pcm.has("WALK_BOB") \
			and pcm.has("PX_PER_PHASE")
	chk(has_hero, "t17: у героя есть константы WALK_SEQ/WALK_BOB/PX_PER_PHASE (на голом HEAD — RED)")
	var SR = load("res://scripts/mob_swarmling.gd")
	var scm: Dictionary = SR.get_script_constant_map()
	var has_rat: bool = scm.has("RAT_PX_PER_PHASE")
	chk(has_rat, "t17: у мглокрыса есть константа RAT_PX_PER_PHASE (на голом HEAD — RED)")
	if not (has_hero and has_rat):
		return
	var seq: Array = pcm["WALK_SEQ"]
	var bob: Array = pcm["WALK_BOB"]
	var ppx := float(pcm["PX_PER_PHASE"])
	chk(seq == [1, 0, 2, 0] and bob == [0, -1, 0, -1] and absf(ppx - 7.0) < 0.001,
		"t17: договор констант: [1,0,2,0] / bob [0,-1,0,-1] (оба прохода) / 7 px (получено %s %s %.2f)" \
				% [str(seq), str(bob), ppx])
	world.apply_area("village", true)
	await _frames(8)
	var anim: AnimatedSprite2D = p.get("anim")
	if anim == null:
		chk(false, "t17: у героя нет анимации")
		return
	# покой: стойка (колонка 0 hero.png) без bob — тот же кадр, что до интеграции
	var f0: Texture2D = anim.sprite_frames.get_frame_texture(anim.animation, int(anim.frame))
	chk(f0 is AtlasTexture and int((f0 as AtlasTexture).region.position.x) == 0 \
			and anim.offset == Vector2.ZERO,
		"t17: покой = кадр стойки (колонка 0) без смещения — вид не изменился")
	# бег на месте (стена справа не мешает: фаза от намерения-скорости, как в сговоре)
	GameState.hp = 999
	Input.action_press("move_right")
	var seen_phase := {}
	var bad_frame := 0
	var bad_bob := 0
	var trans_d: Array = []
	var prev_ph := -1
	for i in 150:
		await get_tree().physics_frame
		var wd := float(p.get("walk_dist"))
		var ph := int(wd / ppx) % 4
		var ft: Texture2D = anim.sprite_frames.get_frame_texture(anim.animation, int(anim.frame))
		if not (ft is AtlasTexture) \
				or int((ft as AtlasTexture).region.position.x) != int(seq[ph]) * 16:
			bad_frame += 1
		if int(anim.offset.y) != int(bob[ph]):
			bad_bob += 1
		seen_phase[ph] = true
		if ph != prev_ph:
			trans_d.append(wd)
			prev_ph = ph
	Input.action_release("move_right")
	chk(bad_frame == 0,
		"t17: кадр при ходьбе = WALK_SEQ[floor(путь/7)] (кадров-несоответствий %d)" % bad_frame)
	chk(bad_bob == 0,
		"t17: bob = WALK_BOB[по фазе] (−1 px на проходных фазах) (несоответствий %d)" % bad_bob)
	chk(seen_phase.size() == 4,
		"t17: полный цикл [1,0,2,0] пройден за 150 кадров (фаз %d)" % seen_phase.size())
	var step_bad := 0
	for i in range(1, trans_d.size()):
		if absf(float(trans_d[i]) - float(trans_d[i - 1]) - ppx) > 1.5:
			step_bad += 1
	chk(trans_d.size() >= 5 and step_bad == 0,
		"t17: смена фазы ровно каждые ~7 px пути (смен %d, сбоев %d)" % [trans_d.size(), step_bad])
	# покой снова стойка, bob обнулён
	await _frames(3)
	var f1: Texture2D = anim.sprite_frames.get_frame_texture(anim.animation, int(anim.frame))
	chk(f1 is AtlasTexture and int((f1 as AtlasTexture).region.position.x) == 0 \
			and anim.offset == Vector2.ZERO,
		"t17: встал — снова кадр стойки, bob вернулся в 0")
	# сговор о персисте: фаза — производная пути, в сейв не попадает
	if GameState.save_game():
		var fa := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var txt := fa.get_as_text()
		chk(not txt.contains("walk_dist") and not txt.contains("\"phase\""),
				"t17: в сейве нет walk_dist/phase — загрузка не ломает фазу (она от пути)")
	else:
		chk(false, "t17: save_game() не смог записаться")
	# мглокрыс: свой экземпляр рядом с героем (погоня — детерминированный ход)
	var r = SR.new()
	world.village_zone.add_child(r)
	var hp_t := Vector2i(
		int(floor((p.global_position.x - world.village_zone.global_position.x) / 16.0)),
		int(floor((p.global_position.y - world.village_zone.global_position.y) / 16.0)))
	r.setup(world, hp_t + Vector2i(2, 0))
	await _frames(2)
	var rppx := float(scm["RAT_PX_PER_PHASE"])
	var seen_f := {}
	var bad_rf := 0
	var moving_n := 0
	for i in 90:
		await get_tree().physics_frame
		var ra: AnimatedSprite2D = r.get("anim")
		if ra == null:
			continue
		var an := String(ra.animation)
		if an.begins_with("walk"):
			moving_n += 1
			var rph := int(float(r.get("walk_dist")) / rppx) % 2
			if int(ra.frame) != rph:
				bad_rf += 1
			seen_f[int(ra.frame)] = true
		elif an.begins_with("idle") and r.velocity.length_squared() > 1.0:
			bad_rf += 1  # едет, а стоит в idle — несогласовано
	chk(moving_n > 20 and bad_rf == 0 and seen_f.size() == 2,
		"t17: мглокрыс — 2-фазный цикл от пути при движении (кадры %s, ходовых %d, сбоев %d)" \
				% [str(seen_f.keys()), moving_n, bad_rf])
	r.queue_free()

## c20 «Пепелище v1 в игре» (вердикт «берём», лист sheet_ashen_v1 утверждён).
## Аттлас assets/ashen_tiles.png == побайтовый bake генератора (полы 0–3 —
## кадры листа, палитра 0 off); prop-слой «AshenPropV1» стоит ровно на
## блокировщиках T/K/# (запрещённые pin-имена T6/T13 не заняты); сундук — свой
## кадр (слот 8), портал — слот 7 (деревенский вход синхронен тем же атласом);
## self_modulate земли убран (тон в листе); тинты мобов — как были (перекраска c22).
## Честный RED на голом HEAD: легаси-аттлас вне палитры, bake_atlas нет,
## prop-слоя нет, сундук лесной, self_modulate висит.
func _t18() -> void:
	var AZ = load("res://scripts/ashen_zone.gd")
	var azm: Dictionary = AZ.get_script_constant_map()
	var SH = load("res://tools_art/sheet_ashen_v1.gd")
	chk(SH != null, "t20: лист-инструмент tools_art/sheet_ashen_v1.gd в репо")
	var has_bake := false
	if SH != null:
		for mi in SH.get_script_method_list():
			if String(mi.get("name", "")) == "bake_atlas":
				has_bake = true
	chk(has_bake, "t20: у инструмента есть статический bake_atlas — единственный источник атласа (голо-HEAD: RED)")
	var az = world.ashen_grid
	# 1) байты атласа == генератор (raw RGBA, без пересчёта палитры)
	var fb := FileAccess.get_file_as_bytes("res://assets/ashen_tiles.png")
	var fi := Image.new()
	var ferr := fi.load_png_from_buffer(fb)
	var raw_match := false
	if has_bake and ferr == OK:
		var baked: Image = SH.bake_atlas()
		raw_match = baked != null and baked.get_data() == fi.get_data()
	chk(raw_match, "t20: assets/ashen_tiles.png == bake_atlas() побайтово (raw RGBA)")
	# 2) новый пин контракта: палитра 0 off для регионов пола 0–3 (легаси: все 1024)
	var off03 := 0
	if ferr == OK:
		var cidx: Dictionary = PAL.color_index()
		var lim := mini(64, fi.get_width())
		for y in mini(16, fi.get_height()):
			for x in lim:
				var col := fi.get_pixel(x, y)
				if col.a > 0.5 and not cidx.has(PAL.key(col)):
					off03 += 1
	chk(off03 == 0, "t20: палитра PixelPalette: 0 off-пикселей в регионах 0–3 (легаси давал 1024, получено %d)" % off03)
	# 3) алфавит grid и коллайдеры — байтово заморожены (grid и GOLDEN-ASHEN-PIN не тронуты)
	chk(azm.get("CHAR_TO_TILE") == {".": 0, ",": 1, "c": 2, "a": 3, "T": 4, "K": 5, "#": 6, "P": 7} \
			and azm.get("BLOCKING") == [4, 5, 6] \
			and azm.get("ASHEN_BLOCK_SHAPES") == {5: [10, 8, 0, 3]},
			"t20: CHAR_TO_TILE/BLOCKING/форма пня — байтово заморожены (блокировщики T/K/# на местах)")
	# 4) prop-слой: разрешённое имя; стоит ровно на T/K/#; регионы — layout инструмента
	var layer = az.get_node_or_null("AshenPropV1")
	chk(layer != null and az.get_node_or_null("AshenFloorPaint") == null \
			and az.get_node_or_null("Env4AshenProps") == null \
			and world.ashen_zone.get_node_or_null("AshenFloorPaint") == null \
			and world.ashen_zone.get_node_or_null("Env4AshenProps") == null,
			"t20: prop-слой AshenPropV1 есть; запрещённые pin-имена (T6/T13) не заняты")
	var exp := {}
	var n_block := 0
	var ctm: Dictionary = azm.get("CHAR_TO_TILE", {})
	for y in int(az.map_h):
		var row := String(az.map_rows[y])
		for x in int(az.map_w):
			var idx := int(ctm.get(String(row[x]), -1))
			if idx == 4:
				exp[Vector2i(x, y)] = "TREE1" if (x + y) % 2 == 0 else "TREE2"
				n_block += 1
			elif idx == 5:
				exp[Vector2i(x, y)] = "STUMP"
				n_block += 1
			elif idx == 6:
				exp[Vector2i(x, y)] = "LOG"
				n_block += 1
	var regs: Dictionary = {}
	if SH != null:
		regs = SH.get_script_constant_map().get("PROP_REGIONS", {})
	var got := {}
	var bad_pos := 0
	var bad_z := 0
	if layer != null:
		for n in layer.get_children():
			var spr := n as Sprite2D
			if spr == null or not (spr.texture is AtlasTexture):
				bad_pos += 1
				continue
			var reg: Rect2 = (spr.texture as AtlasTexture).region
			var foot := spr.position.y + reg.size.y / 2.0
			var keyv := Vector2i(int(round(spr.position.x / 16.0)) - 1, int(round(foot / 16.0)) - 1)
			if not exp.has(keyv):
				bad_pos += 1
				continue
			var want_nm := String(exp[keyv])
			if not regs.has(want_nm) or regs[want_nm] != reg:
				bad_pos += 1
			got[keyv] = true
			if spr.z_as_relative or spr.z_index != int(round(fposmod(foot, 4800.0))):
				bad_z += 1
	chk(layer != null and got.size() == n_block and bad_pos == 0,
			"t20: prop-слой стоит ровно на клетках T/K/# (блокировщиков %d, спрайтов %d, несоответствий %d)" \
			% [n_block, got.size(), bad_pos])
	chk(layer != null and bad_z == 0,
			"t20: стопы спрайтов — низ клетки, z-сортировка fposmod(стопа, 4800) как у актёров (сбоев %d)" % bad_z)
	chk(regs.size() == 5,
			"t20: layout инструмента PROP_REGIONS запинен и используется зоной (регионов %d; c34: +CHEST_OPEN)" % regs.size())
	# 5) тон листа: self_modulate земли убран
	var tm = az.get("tilemap")
	chk(tm != null and (tm as CanvasItem).self_modulate == Color.WHITE,
			"t20: self_modulate земли убран — тон делает лист (голо-HEAD: RED)")
	# 6) сундук/портал — свои кадры ashen_v1; вход в деревне синхронен атласом
	var chest = az.get("chest_node")
	var chest_ok := false
	if chest != null:
		for n in (chest as Node).get_children():
			var spr := n as Sprite2D
			if spr != null and spr.texture is AtlasTexture:
				var at := spr.texture as AtlasTexture
				chest_ok = String((at.atlas as Resource).resource_path).ends_with("ashen_tiles.png") \
						and at.region == Rect2(8 * 16, 0, 16, 16)
	chk(chest_ok, "t20: сундук — свой кадр ashen_v1 (слот 8); uid/награда/флаг не тронуты (голо-HEAD: RED)")
	var portal = az.get("portal_node")
	var portal_ok := false
	if portal != null:
		for n in (portal as Node).get_children():
			var spr := n as Sprite2D
			if spr != null and spr.texture is AtlasTexture:
				var at := spr.texture as AtlasTexture
				portal_ok = String((at.atlas as Resource).resource_path).ends_with("ashen_tiles.png") \
						and at.region == Rect2(7 * 16, 0, 16, 16)
	var gate_ok := false
	var vstack: Array = [world.village_zone]
	while not vstack.is_empty():
		var nd: Node = vstack.pop_back()
		for c in nd.get_children():
			vstack.append(c)
			var spr := c as Sprite2D
			if spr != null and spr.texture is AtlasTexture \
					and String(((spr.texture as AtlasTexture).atlas as Resource).resource_path).ends_with("ashen_tiles.png"):
				gate_ok = (spr.texture as AtlasTexture).region == Rect2(7 * 16, 0, 16, 16)
	chk(portal_ok and gate_ok,
			"t20: портал — слот 7 листа; вход в деревне (world.gd, AshenGate) синхронен тем же атласом")
	# 7) тинты мобов зоны — как были (перекраска наполнения — c22)
	var tint_arch := false
	var tint_rat := false
	for n in az.get_children():
		if n.get_script() != null:
			var rp := String((n.get_script() as Resource).resource_path)
			if rp.ends_with("mob_archer.gd") and (n as CanvasItem).self_modulate != Color.WHITE:
				tint_arch = true
			if rp.ends_with("mob_swarmling.gd") and (n as CanvasItem).self_modulate != Color.WHITE:
				tint_rat = true
	chk(tint_arch and tint_rat,
			"t20: modulate-тинты мобов зоны оставлены как есть (лесные листы; перекраска — c22)")

## c23 «перекраска персонажей в игре» (вердикт пользователя «да» по листу c22).
## Карта — tools_art/c22_recolor.gd (таблица корзин B = 606 соответствий);
## золотые легаси-PNG 13 атласов описи c17 §1 — res://c23_golden.gd (HEAD до
## перепёка). Пины: инструмент в репо; каждый атлас == карта, применённая к
## золотому легаси, ПОБАЙТОВО; альфа (маска/силуэт) == золотая побайтово;
## PixelPalette off суммарно: легаси 486 -> в игре 0; размеры атласов
## заморожены (ни нового кадра/рисовалки).
## Честный RED на голом HEAD: инструмента и золотого файла нет, атласы в игре
## вне палитры (486 off-пикселей).
func _t23() -> void:
	var RT = load("res://tools_art/c22_recolor.gd")
	var has_recolor := false
	if RT != null:
		for mi in RT.get_script_method_list():
			if String(mi.get("name", "")) == "recolor_atlas":
				has_recolor = true
	chk(has_recolor, "c23: инструмент tools_art/c22_recolor.gd с recolor_atlas в репо (голый HEAD: RED)")
	var GD = load("res://c23_golden.gd")
	chk(GD != null, "c23: золотые легаси-атласы res://c23_golden.gd (голый HEAD: RED)")
	if GD == null:
		chk(false, "c23: атлас == карта c22 побайтово (золото отсутствует)")
		return
	var cidx: Dictionary = PAL.color_index()
	# список и пути заморожены в пине (голый HEAD без инструмента тоже краснеет числом)
	var assets := {
		"class_warrior": "res://assets/class_warrior.png",
		"class_archer": "res://assets/class_archer.png",
		"class_mage": "res://assets/class_mage.png",
		"npc_elder": "res://assets/npc_elder.png",
		"npc_farmer": "res://assets/npc_farmer.png",
		"npc_hermit": "res://assets/npc_hermit.png",
		"npc_merchant": "res://assets/npc_merchant.png",
		"npc_smith": "res://assets/npc_smith.png",
		"slime": "res://assets/slime.png",
		"swarmling": "res://assets/mobs_swarmling.png",
		"mob_archer": "res://assets/mobs_archer.png",
		"wraith": "res://assets/mobs_wraith.png",
		"brute": "res://assets/brute.png",
	}
	var names: Array = assets.keys()
	names.sort()
	var raw_all_ok := true
	var alpha_all_ok := true
	var sizes_ok := true
	var off_after_set := {}
	var legacy_uniq := {}
	var off_before_set := {}
	for a in names:
		var lraw: PackedByteArray = Marshalls.base64_to_raw(String(GD.GOLD[a]))
		var legacy := Image.new()
		if legacy.load_png_from_buffer(lraw) != OK:
			chk(false, "c23: золотой PNG декодируется (%s)" % a)
			raw_all_ok = false
			continue
		var exp: Image = null
		if has_recolor:
			exp = RT.recolor_atlas(String(a), legacy)
		else:
			raw_all_ok = false
		var ship := Image.new()
		if ship.load_png_from_buffer(FileAccess.get_file_as_bytes(String(assets[a]))) != OK:
			chk(false, "c23: атлас читается из res://assets (%s)" % a)
			raw_all_ok = false
			continue
		if String(GD.SIZES[a]) != "%dx%d" % [ship.get_width(), ship.get_height()]:
			sizes_ok = false
		if exp != null and exp.get_data() != ship.get_data():
			raw_all_ok = false
		var la: PackedByteArray = legacy.get_data()
		var sa: PackedByteArray = ship.get_data()
		if la.size() != sa.size():
			alpha_all_ok = false
		else:
			for i in range(3, la.size(), 4):
				if la[i] != sa[i]:
					alpha_all_ok = false
					break
		var seen := {}
		for y in legacy.get_height():
			for x in legacy.get_width():
				var c := legacy.get_pixel(x, y)
				if c.a == 0.0:
					continue
				var k: int = PAL.key(Color(c.r, c.g, c.b, 1.0))
				if not seen.has(k):
					seen[k] = true
					legacy_uniq["%s|%d" % [a, k]] = true
					if not cidx.has(k):
						off_before_set[k] = true
		for y in ship.get_height():
			for x in ship.get_width():
				var c2 := ship.get_pixel(x, y)
				if c2.a > 0.0:
					var k2: int = PAL.key(Color(c2.r, c2.g, c2.b, 1.0))
					if not cidx.has(k2):
						off_after_set[k2] = true
	chk(sizes_ok, "c23: размеры 13 атласов заморожены (ни нового кадра/рисовалки)")
	chk(alpha_all_ok, "c23: альфа (маска/силуэт) каждого кадра == золотая побайтово")
	chk(raw_all_ok, "c23: каждый атлас == карта c22, применённая к золотому легаси, побайтово")
	chk(legacy_uniq.size() == 606, "c23: соответствий в карте — 606 (золото дало %d)" % legacy_uniq.size())
	chk(off_before_set.size() == 486, "c23: легаси off (union 13 атласов) = 486 (золото дало %d)" % off_before_set.size())
	chk(off_after_set.size() == 0, "c23: PixelPalette off в игровых атласах = 0 (486 -> %d)" % off_after_set.size())

## c25 «предметные иконки в игре» (вердикт по листу c24 «берём, мешочек не надо»).
## Пины: инструмент листа в репо; рантайм item_icon() шести id — 0 пикселей вне
## PixelPalette (у стабов t52 было 1536/1536); сырые цвета стабов исчезли;
## fallback неизвестного id — техстаб-линия (седьмая рисовалка НЕ added);
## атлас скиллов 192x16 не тронут. Popcount-различимость листа числами.
## Честный RED на голом HEAD: off=1536, сырые цвета стабов в кадре.
func _t25() -> void:
	var ui := load("res://scripts/ui_icons.gd")
	var tool := load("res://tools_art/sheet_items.gd")
	chk(tool != null, "c25: инструмент tools_art/sheet_items.gd в репо (голый HEAD: RED)")
	var palkeys := {}
	for col in PAL.color_index():
		palkeys[col] = true
	# ключ фонов/стабов — как их реально сохранит RGBA8 (float ui.BG/INK в to_argb32
	# округляются иначе, чем пишет set_pixel: Color(0.16,..)->40, не 41)
	var k25 := func(c: Color) -> int:
		var im := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		im.set_pixel(0, 0, c)
		return im.get_pixel(0, 0).to_argb32()
	var bgk: int = k25.call(ui.BG)
	var inkk: int = k25.call(ui.INK)
	var ids := ["herb", "mushroom", "root", "ash", "berry", "glowcap"]
	var stubs := [Color(0.4, 0.65, 0.32), Color(0.72, 0.3, 0.28), Color(0.85, 0.78, 0.65),
		Color(0.55, 0.4, 0.25), Color(0.6, 0.6, 0.66), Color(0.75, 0.25, 0.4),
		Color(0.45, 0.75, 0.85), Color(0.5, 0.75, 0.38), Color(0.9, 0.85, 0.7),
		Color(0.35, 0.6, 0.7), Color(0.8, 0.95, 1.0)]
	var stub_keys := {}
	for c in stubs:
		stub_keys[k25.call(c)] = true
	var off_all := 0
	var stub_px := 0
	var sizes_ok := true
	var fg_min := 1 << 30
	for idv in ids:
		var img: Image = ui.item_icon(String(idv)).get_image()
		if img.get_width() != 16 or img.get_height() != 16:
			sizes_ok = false
		var off := 0
		var fg := 0
		for y in 16:
			for x in 16:
				var k := PAL.key(img.get_pixel(x, y))
				if k == bgk or k == inkk:
					continue
				fg += 1
				if not palkeys.has(k):
					off += 1
				if stub_keys.has(k):
					stub_px += 1
		off_all += off
		fg_min = mini(fg_min, fg)
	chk(sizes_ok, "c25: все шесть предметных иконок 16x16")
	chk(off_all == 0, "c25: PixelPalette off на предметных рантайм-иконках = 0 (стабы давали 1536, сейчас %d)" % off_all)
	chk(stub_px == 0, "c25: сырых цветов стабов t52 в иконках нет (остаток %d px)" % stub_px)
	chk(fg_min >= 24, "c25: заполнение иконок не тоньше утверждённого листа (min fg %d px)" % fg_min)
	# fallback: неизвестный id — техстаб (BG/INK/ACC_G линия 8 px), без седьмой рисовалки
	var fb: Image = ui.item_icon("__unknown_id__").get_image()
	var accg: int = k25.call(ui.ACC_G)
	var fb_ok := true
	var accpx := 0
	for y in 16:
		for x in 16:
			var k := PAL.key(fb.get_pixel(x, y))
			if k == bgk or k == inkk:
				continue
			if k == accg:
				accpx += 1
			else:
				fb_ok = false
	chk(fb_ok and accpx == 8, "c25: fallback неизвестного id — техстаб-линия ACC_G (седьмая иконка не добавлена)")
	var sat2: Image = ui.skill_atlas().get_image()
	chk(sat2.get_width() == 192 and sat2.get_height() == 16, "c25: атлас скиллов 192x16 не тронут")
	# popcount-различимость 15 пар листа — числа в логе генератора (sheet_items.gd),
	# здесь не считаем: instantiating SceneTree-скрипта внутри батареи недопустим.

## c27 «волна w1: портреты на палитру» (план c26, без вердикта).
## Пины: карта c27_portraits в репо; золотые легаси-портреты (base64) ==
## HEAD-состояние; ожидание = карта, применённая к золоту, == ассет побайтово;
## альфа-маска байт-в-байт; размеры 120x40 заморожены; off 6175 -> 0 числами.
## Честный RED на голом HEAD: инструмента нет, ассет == золото != ожиданию, off=6175.
func _t27() -> void:
	var G = load("res://c27_golden.gd")
	chk(G != null, "c27: золотые легаси-портреты res://c27_golden.gd (голый HEAD: RED)")
	if G == null:
		return
	var RT = load("res://tools_art/c27_portraits.gd")
	chk(RT != null, "c27: карта c27_portraits в репо (голый HEAD: RED)")
	var cidx: Dictionary = PAL.color_index()
	var assets := {
		"portraits": "res://assets/portraits.png",
		"portraits2": "res://assets/portraits2.png",
	}
	var raw_all_ok := true
	var alpha_all_ok := true
	var sizes_ok := true
	var off_before := 0
	var off_after := 0
	for a in ["portraits", "portraits2"]:
		var legacy := Image.new()
		if legacy.load_png_from_buffer(Marshalls.base64_to_raw(String(G.GOLD[a]))) != OK:
			chk(false, "c27: золотой PNG декодируется (%s)" % a)
			raw_all_ok = false
			continue
		var exp: Image = null
		if RT != null:
			exp = legacy.duplicate()
			RT.bake(String(a), exp)
		var ship := Image.new()
		if ship.load_png_from_buffer(FileAccess.get_file_as_bytes(String(assets[a]))) != OK:
			chk(false, "c27: ассет читается (%s)" % a)
			raw_all_ok = false
			continue
		if "%dx%d" % [ship.get_width(), ship.get_height()] != "120x40":
			sizes_ok = false
		if exp != null and exp.get_data() != ship.get_data():
			raw_all_ok = false
		var la: PackedByteArray = legacy.get_data()
		var sa: PackedByteArray = ship.get_data()
		if la.size() != sa.size():
			alpha_all_ok = false
		else:
			for i in range(3, la.size(), 4):
				if la[i] != sa[i]:
					alpha_all_ok = false
					break
		for y in legacy.get_height():
			for x in legacy.get_width():
				var k: int = legacy.get_pixel(x, y).to_argb32()
				if ((k >> 24) & 0xFF) == 255 and not cidx.has(k):
					off_before += 1
		for y in ship.get_height():
			for x in ship.get_width():
				var k2: int = ship.get_pixel(x, y).to_argb32()
				if ((k2 >> 24) & 0xFF) == 255 and not cidx.has(k2):
					off_after += 1
	chk(sizes_ok, "c27: размеры портретов 120x40 заморожены (ни нового кадра)")
	chk(alpha_all_ok, "c27: альфа-маска портретов == золото побайтово")
	chk(raw_all_ok, "c27: портреты == карта c27, применённая к золоту, побайтово (голый HEAD: RED)")
	chk(off_after == 0, "c27: PixelPalette off на портретах = 0 (легаси давало %d, сейчас %d)" % [off_before, off_after])

## c29 «UI-мелочь в игре» (вердикт по листу c28 «берём»; alch не тронута).
## Пины: база-трекинг (ls-tree по возможности живым git, иначе золото HEAD-байтов
## — см. комментарий в теле); инструмент sheet_ui (bake_assets in-process —
## единственный источник арта); 8 PNG побайтово == bake_assets; двойной bake
## побайтово идентичен; off (непрозрачные вне RAMPS/FLATS) = 0 и полупрозрачных
## масок в этих PNG нет (§3: baked-теней в спрайтах нет — у легаси-костра были);
## panel_frame 32×32 контракт margin-4 (полосы/центр — независимый пересчёт
## фактического PNG); костёр 5 кадров, d>=16 между соседними; курсоры
## читаемость >=0.12 на CHAR_DARK и PARCHMENT_M (фактические PNG);
## alch_icons побайтово == HEAD.
## Путь источника: рабочий план main (worktree) — волна пинится ДО коммита;
## после коммита worktree == стад HEAD, пины не меняются. Числа легаси-off
## стенд считает сам по золотым HEAD-байтам (base64, прецедент c27) — это и
## есть честный RED на голом HEAD: ассеты == золото, off != 0, инструмента нет.
const C29_NAMES := ["panel_frame.png", "cursor_arrow.png", "cursor_crosshair.png",
	"cursor_move.png", "cursor_enemy.png", "projectiles.png", "key.png", "campfire.png"]
const C29_REPO := {
	"panel_frame.png": "pixel-rpg/assets/ui/panel_frame.png",
	"cursor_arrow.png": "pixel-rpg/assets/ui/cursor_arrow.png",
	"cursor_crosshair.png": "pixel-rpg/assets/ui/cursor_crosshair.png",
	"cursor_move.png": "pixel-rpg/assets/cursor_move.png",
	"cursor_enemy.png": "pixel-rpg/assets/cursor_enemy.png",
	"projectiles.png": "pixel-rpg/assets/projectiles.png",
	"key.png": "pixel-rpg/assets/key.png",
	"campfire.png": "pixel-rpg/assets/campfire.png",
}
## HEAD-байта легаси-ассетов на 9ef6251 (сверены с git show HEAD побайтово).
const GOLD_C29 := {
	"alch_icons.png": "iVBORw0KGgoAAAANSUhEUgAAADAAAAAQCAYAAABQrvyxAAABRklEQVR42mNggAIREZn/pGAGNDCg+kECGhrmJGFkQ2ilH9nBOPXj04yNxmYBPkfiU0NIblWV1/++BAswxukJXBJHYjTA9IcTUWD6zZEADEOo4QB8+qfNXg/HJHsA5vj/H/bBPUGsB0BiTU09KDgsLIEk/SBHPwtw+7/KyAhMY/MEVg+A+A96rOAegGFssUDIASe+/odjmAMI6YfpffHuB4oHsHmCqCQEwzA+oRDE5nhkT8SciEHJV4Q8gIyJ9gAlmRjmAJBD13yYAaZhGCRuMs0KpwfwOR6bJ/B6AKYgYV4ASaUIIQ/gS0LYPPC/p2ngPICOifUAeqgje4JoD4DEFRL0BtQD6KFP1xhAx8QWw7higeRMjOwBpyorkioibG0XUmpifIFAVEWGrACX44lpShDTHiKmHUR2ewhX8Umvxhyx+od0cxoAnIPK7qUH1hoAAAAASUVORK5CYII=",
	"campfire.png": "iVBORw0KGgoAAAANSUhEUgAAAFAAAAAQCAYAAACBSfjBAAABiUlEQVR42mNgGAWjYNCCY4Eq/1vMJP6D6KHkbpCbB41D/i+w+Q9z0MyEoRWQA5oIQBbeidIAByCIJtUB5Dqc0tSDHsngRHCn4j/dUyUs9YEsR06FpOonJ/Bh+mF2IkcEKbmA0kQAAjm5Jf/JKj9gMUdOAMIdjqaXWM/D9CO7hdQIRHEDmYlgwFIgil4k/dcKdf+Tqh/ERg5Mct1PTgosKq78PyABiJ4CKdIPxZQG4MCUgWQGAIoHhqh+ENi2bf//qqoGylMhubE3lPU3lZf+r6ioI93erGDr/6FWSmAMLvhbPP73JViA+Q5ahB0y1PWbair9N1GTBWNYJMD4ajJimPpzc4v+R0cngiXq4+z/Z7lpwDEsBpHF4u0hBTFIj7Oz5//hpN/FROu/g74qHHtoSfwvKKhCEbPSUkTRD2bADADFHii28GFYLML0DSf9oNQX7mCIF8NSIVwfKBTBIcnAwAAyHDm2sGGYA2D6hpN+UOAgpzZsGBaAyPoYjIzMQQwQ1iMS/4fqGfH6Ad5GWNng1EDZAAAAAElFTkSuQmCC",
	"cursor_arrow.png": "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAABFSURBVDhP7czBCgAgCANQ//+nK4VdYhMjoUsPdhCntoxCUuyARYqCgr0Xld4HmEmkKADmLakoAWZfVPU8IDlydfy9ZTYB51eLdVyB9RQAAAAASUVORK5CYII=",
	"cursor_crosshair.png": "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAABYSURBVDhPY8AF3n349h8ZQ4WJA+iaYRgqTRjANDw6EgXGQ8AAmAJSMUWaYRjDudicjFcNXkkowKsGxiAXo9hAKgZrxgZgCnB5iSAYPAagY6g0cYA4zQwMAG1CEu9CPOulAAAAAElFTkSuQmCC",
	"cursor_enemy.png": "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAXklEQVR42mNgoAV49+Hbf2yYaI27rMywYrwGoWtE5mOTw2kAspNf5CWAMbIYVgPQbUP3EiF1GLbjMwCrK5BNRnYyuhdAbLwuoNgAqniBrECkOBqpkpAoTspUyUzkAADEnNIcZ3lurgAAAABJRU5ErkJggg==",
	"cursor_move.png": "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAe0lEQVR42mNgwAHeffj2/9GRKDAGsRnIASCNFGsm2RCYBpDT/7+YBqeJMgikAFkTNhqvIcg2o3sBWRxDEzbN6IGIS54B5ixk5xPLB7EZ0AWQnY+cDnDJo3gBPaDQvYBNHmcsoAciybGAiyYqLWBLD2SnSKrkB7I1E5OdAYZV02Eiqmh7AAAAAElFTkSuQmCC",
	"key.png": "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAj0lEQVR42mNgIAJYaIn/D7KTQ8FeFtL/idHLoCYr9F9LQQSs6d6evP81CTqkGQLSDMIgzV/uTAMbgGwIUbaj24zMJ8p2dFtJMgCkGGYIiI3uGoLOB2GQ35FdAhMHxQ5BzTAXwGgYBqkhWjNRGvFpxqsJV5zD2AykAFx+JskAbIYQbQCuMCDJG8iGkBSA5AIAIZ3JogMvXzwAAAAASUVORK5CYII=",
	"panel_frame.png": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAABsSURBVFhHYwABKRGe/wOB4Zb7Wcn/zw4yoCsG2Ql2BIjApoAeGMMBIFfRA+N1gIq0AE3xqANGHTDqgFEHjDpg1AGjDhh1wKgDRh0w6oDB7wB6YJwOoDeGOwDZVfTCIDvBDoD1kAcCMzAwMAAATCHUxA6B65YAAAAASUVORK5CYII=",
	"projectiles.png": "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAQCAYAAACm53kpAAAA7UlEQVR42mNgGAWjYBSMAhqDEj25/8+6bP6DaFL1ejUs+z/kPPz/TMV/dM8jY2IDYt+DD/8rNlz4PyQDATkAQAECw8QGAMjzsACgSyCcO7HjPwgTUjdlzpr/+DwLY28J0ACzQR4Ge/7NFqIDAORhkOdffPsDDwBCgXD2w4s8ECbk/ml3LlRglQiSUgAbXhZl9R8fPnHpCRjj8jyMhgUAOSkA2dPIgYAvAPa9ezQN5kF8+N6PDwtAGGsKmDahiaIUgB775JYBBhE1KDFPTBYAxf60E/tSyE4Bg60WQA6EIV0IUgpGtOdHwSgYBTQHAEiVJ4v8NYM+AAAAAElFTkSuQmCC",
}

func _c29_ws() -> String:
	# корень воркспейса: предок с tools/godot и pixel-rpg/project.godot
	# (стад-копия лежит в ROOT/tools/appdata_qa/stage/pixel-rpg)
	var p := ProjectSettings.globalize_path("res://")
	for i in range(0, 6):
		if DirAccess.dir_exists_absolute(p.path_join("tools").path_join("godot")) \
				and FileAccess.file_exists(p.path_join("pixel-rpg").path_join("project.godot")):
			return p
		var pp := p.replace("\\", "/")
		while pp.ends_with("/"):
			pp = pp.substr(0, pp.length() - 1)
		var si := pp.rfind("/")
		if si <= 0:
			break
		var up: String = pp.substr(0, si)
		if up == pp:
			break
		p = up
	return ""

func _c29_off(im: Image) -> Dictionary:
	var idx := PAL.color_index()
	var off := 0
	var masks := 0
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			var a := int(c.a * 255.0)
			if a == 0:
				continue
			if a < 255:
				masks += 1
			elif not idx.has(PAL.key(c)):
				off += 1
	return {"off": off, "masks": masks}

func _c29_lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

func _c29_read(img: Image, ox: int, bg: Color) -> float:
	var leg := 0
	var tot := 0
	for y in range(0, 16):
		for x in range(0, 16):
			var p := img.get_pixel(ox + x, y)
			if p.a > 0.5:
				tot += 1
				if absf(_c29_lum(p) - _c29_lum(bg)) > 0.12:
					leg += 1
	return float(leg) / float(maxi(1, tot))

func _c29_fdiff(img: Image, fa: int, fb: int) -> int:
	var n := 0
	for y in range(0, 16):
		for x in range(0, 16):
			var sa := img.get_pixel(fa * 16 + x, y).a > 0.5
			var sb := img.get_pixel(fb * 16 + x, y).a > 0.5
			if sa != sb:
				n += 1
	return n

func _t29() -> void:
	var ws := _c29_ws()
	var pxr := ws.path_join("pixel-rpg") if ws != "" \
			else ProjectSettings.globalize_path("res://")
	# --- инструмент (единственный источник) ---
	var SU = load("res://tools_art/sheet_ui.gd") \
			if ResourceLoader.exists("res://tools_art/sheet_ui.gd") else null
	var tool_src := "res://tools_art/sheet_ui.gd"
	if SU == null:
		var abs_tool := pxr.path_join("tools_art/sheet_ui.gd")
		if FileAccess.file_exists(abs_tool):
			SU = load(abs_tool)
			tool_src = abs_tool
	chk(SU != null, "c29: инструмент sheet_ui в репо (единственный источник bake; голый HEAD: RED)")
	# --- база: 8 ассетов трекаются в HEAD (ребейк ЗАМЕНЯЕТ, а не создаёт) ---
	# Живой git из-под Godot в песочнице недоступен: OS.execute с git/ls-tree или
	# даёт пустой вывод, или вешает процесс (проверено probes 2026-11-15), поэтому
	# ls-tree НЕ зовём. Носимое доказательство базы: чек «золото легаси-байтов
	# декодируется» ниже + побайтовая сверка WORK-ассетов с GOLD_C29 — HEAD-блобы,
	# снятые и сверенные с `git show HEAD:...`/`git ls-tree HEAD` ВНЕ Godot
	# (evidence в отчёте волны); совпадение байт возможно только для трекаемого
	# файла, т.е. ребейк гарантированно заменяет существующие ассеты.
	print("qa_lp c29: ls-tree базы снимался вне стенда: git ls-tree HEAD — 8/8 paths из C29_REPO трекаются (9ef6251)")
	if SU == null:
		return
	# --- bake_assets in-process + двойной bake побайтово ---
	var gen: Dictionary = SU.bake_assets()
	var gen2: Dictionary = SU.bake_assets()
	var dbl_ok := gen.size() == 8
	var eq_ok := true
	var sizes_ok := true
	var want_sizes := {
		"panel_frame.png": Vector2i(32, 32), "cursor_arrow.png": Vector2i(16, 16),
		"cursor_crosshair.png": Vector2i(16, 16), "cursor_move.png": Vector2i(16, 16),
		"cursor_enemy.png": Vector2i(16, 16), "projectiles.png": Vector2i(64, 16),
		"key.png": Vector2i(16, 16), "campfire.png": Vector2i(80, 16)}
	var ship := {}
	var md5s := ""
	for nm in C29_NAMES:
		var a: Image = gen[nm]
		var b: Image = gen2[nm]
		if a.save_png_to_buffer() != b.save_png_to_buffer():
			dbl_ok = false
		if a.get_size() != want_sizes[nm]:
			sizes_ok = false
		var abs_p := pxr.path_join("assets").path_join(String(C29_REPO[nm]).trim_prefix("pixel-rpg/assets/"))
		var bytes := FileAccess.get_file_as_bytes(abs_p)
		ship[nm] = bytes
		if bytes.is_empty() or a.save_png_to_buffer() != bytes:
			eq_ok = false
		else:
			md5s += FileAccess.get_md5(abs_p).substr(0, 8) + " "
	chk(dbl_ok, "c29: двойной bake in-process побайтово идентичен (8 PNG)")
	chk(sizes_ok, "c29: размеры заморожены 32x32/16/16/16x16/16/64x16/16/80x16")
	chk(eq_ok, "c29: 8 PNG побайтово == bake_assets инструмента (md5 %s; голый HEAD: RED)" % md5s)
	# --- off/mask по фактическим PNG + честные числа легаси по золоту HEAD ---
	var gold := {}
	for gk in GOLD_C29:
		var gim := Image.new()
		if gim.load_png_from_buffer(Marshalls.base64_to_raw(String(GOLD_C29[gk]))) == OK:
			gold[gk] = gim
	chk(gold.size() == GOLD_C29.size(), "c29: золото легаси-байтов декодируется (%d/%d)" \
			% [gold.size(), GOLD_C29.size()])
	var off_all := 0
	var mask_all := 0
	var head_off_sum := 0
	var head_detail := ""
	for nm in C29_NAMES:
		var im := Image.new()
		if im.load_png_from_buffer(ship[nm]) != OK:
			chk(false, "c29: PNG декодируется (%s)" % nm)
			continue
		var st := _c29_off(im)
		off_all += int(st["off"])
		mask_all += int(st["masks"])
		if gold.has(nm):
			var hs := _c29_off(gold[nm])
			head_off_sum += int(hs["off"])
			head_detail += "%s=%d " % [nm, int(hs["off"])]
	chk(off_all == 0, "c29: PixelPalette off на 8 ребейкнутых PNG = 0 (HEAD-легаси давал %d: %s)" \
		% [head_off_sum, head_detail])
	chk(mask_all == 0, "c29: полупрозрачных пикселей в 8 PNG нет (§3 — baked-теней в спрайтах нет; легаси-костёр их имел)")
	# --- panel_frame: контракт margin-4 по факту PNG ---
	var pf := Image.new()
	var pf_ok := pf.load_png_from_buffer(ship["panel_frame.png"]) == OK
	if pf_ok:
		for r in range(0, 4):
			var t0 := pf.get_pixel(12, r)
			var b0 := pf.get_pixel(12, 31 - r)
			var l0 := pf.get_pixel(r, 12)
			var r0 := pf.get_pixel(31 - r, 12)
			for i in range(4, 28):
				if PAL.key(pf.get_pixel(i, r)) != PAL.key(t0) \
						or PAL.key(pf.get_pixel(i, 31 - r)) != PAL.key(b0) \
						or PAL.key(pf.get_pixel(r, i)) != PAL.key(l0) \
						or PAL.key(pf.get_pixel(31 - r, i)) != PAL.key(r0):
					pf_ok = false
		var c0 := pf.get_pixel(16, 16)
		for y in range(4, 28):
			for x in range(4, 28):
				if PAL.key(pf.get_pixel(x, y)) != PAL.key(c0):
					pf_ok = false
	chk(pf_ok, "c29: panel_frame 32×32 — полосы margin-4 постоянны, центр solid (потребители не правятся)")
	# --- костёр: 5 кадров, соседние d>=16 ---
	var cf := Image.new()
	if cf.load_png_from_buffer(ship["campfire.png"]) == OK:
		var dmin := 99999
		var dd := ""
		for f in range(0, 4):
			var d := _c29_fdiff(cf, f, f + 1)
			dd += "%d " % d
			dmin = mini(dmin, d)
		chk(dmin >= 16, "c29: костёр 5 кадров, соседние различаются d>=16 (d=%s)" % dd)
	else:
		chk(false, "c29: костёр декодируется")
	# --- курсоры: читаемость на обоих фонах по фактическим PNG ---
	var dark := PAL.c("CHAR", PAL.T_DARK)
	var lite := PAL.c("PARCHMENT", PAL.T_MID)
	var rd_ok := true
	var rd := ""
	for nm in ["cursor_arrow.png", "cursor_crosshair.png", "cursor_move.png", "cursor_enemy.png"]:
		var cim := Image.new()
		if cim.load_png_from_buffer(ship[nm]) != OK:
			rd_ok = false
			continue
		var fd := _c29_read(cim, 0, dark)
		var fl := _c29_read(cim, 0, lite)
		rd += "%s %.2f/%.2f " % [nm.trim_prefix("cursor_").trim_suffix(".png"), fd, fl]
		if fd < 0.12 or fl < 0.12:
			rd_ok = false
	chk(rd_ok, "c29: курсоры читаемы на CHAR_DARK/PARCHMENT_M, >=0.12 (dark/light %s)" % rd)
	# --- alch_icons: до c30 была побайтово == HEAD; вердиктом w2-alch удалена ---
	# (рабочее дерево — волна до коммита; стад HEAD-архива до мержа держит легаси)
	var al_bytes := FileAccess.get_file_as_bytes(pxr.path_join("assets/alch_icons.png"))
	chk(al_bytes.is_empty(),
		"c29/c30: alch_icons.png не в дереве (до c30 == HEAD-золото; удалена вердиктом колбы)")

## c30 «алхимия в игре» (вердикт «третий вариант с колбой»; прецедент c25).
## Пины: рисовалка brewed_icon в ui_icons (голый HEAD: RED); рантайм-кадр
## побайтово == золото кадра листа c28 (GOLD_C30_FLASK — 16×16-кроп утверждённого
## листа F702…, сверен попиксельно единственным совпадением в позиции (344,526)
## плюс то, что кадр испечён репозиторным генератором sheet_ui.gd); размер 16×16;
## off/mask рантайм-кадра = 0; hud читает brewed_icon и не упоминает alch_icons
## (скан исходника); alch_icons.png(+.import) отсутствует в дереве — все 3 кадра,
## мёртвые 0/1 включительно; ls-tree базы: alch_icons.png трекалась в HEAD до
## удаления (снят вне Godot, 9ef6251/855ed50) — носимое доказательство:
## GOLD_C29["alch_icons.png"] декодируется (чек в _t29). SKILL_SLOTS/атлас — без
## изменений.
const GOLD_C30_FLASK := "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAMBJREFUOI1jZMABrOzc/iPzjx3axYhNHRMuAxgYGBhMRD4xmIh8wqcEvwGmYVUMpmFVpBuA7nxcYlgNgCnMzMqBi8HYMLn/N4rhhjES0owMpk+bwsDAgBqgcIaVndv/lXm/Gf5v4UXRdP3+Y4YzL9/B+VvF1FEMQfECumZs4OgsXRQ+3ljABtoC1lBmADpgQeZcv/+YZAModgGKAY3/RQlqgMUChgGwaMFnCHoUYrgAnyHYNDMwoKVEGMCV7rFlaQDbFEZgTREbvAAAAABJRU5ErkJggg=="

func _t30() -> void:
	# Рабочее дерево приоритетно (волна пинится до коммита; прецедент c29-инструмента).
	# load() по abs-пути нельзя: class_name UiIcons конфликтует с зарегистрированным
	# глобальным классом — компилируем исходник WORK отдельно (GDScript.reload).
	var UIS = null
	var abs_ui := pxr_c30().path_join("scripts/ui_icons.gd")
	var src := FileAccess.get_file_as_string(abs_ui)
	if src != "":
		# class_name снимаем: второй объявления того же глобального класса
		# Godot не позволяет (test-harness адаптация, код рисовалок — без изменений)
		var src2 := src.replace("class_name UiIcons", "")
		var G := GDScript.new()
		G.source_code = src2
		if G.reload(true) == OK:
			UIS = G
	if UIS == null:
		UIS = load("res://scripts/ui_icons.gd")
	chk(UIS != null, "c30: ui_icons.gd грузится")
	if UIS == null:
		return
	var has_m := false
	for mi in UIS.get_script_method_list():
		if String(mi.get("name", "")) == "brewed_icon":
			has_m = true
	chk(has_m, "c30: рисовалка колбы brewed_icon в ui_icons (прецедент c25; голый HEAD: RED)")
	if not has_m:
		chk(false, "c30: рантайм-кадр побайтово == лист c28 (метод не найден — RED)")
		chk(false, "c30: кадр 16×16, off/mask=0 (метод не найден — RED)")
	else:
		var tex: Texture2D = UIS.brewed_icon()
		var img: Image = tex.get_image() if tex != null else null
		var gold := Marshalls.base64_to_raw(GOLD_C30_FLASK)
		var eq := img != null and img.save_png_to_buffer() == gold
		chk(eq, "c30: равенство-пин — рантайм brewed_icon побайтово == кадр листа c28 (0 расхождений; голый HEAD: RED)")
		var st := _c29_off(img) if img != null else {"off": -1, "masks": -1}
		chk(img != null and img.get_size() == Vector2i(16, 16) \
				and int(st["off"]) == 0 and int(st["masks"]) == 0,
			"c30: кадр 16×16, off=0, mask=0 (получено %d×%d off=%s mask=%s)" % [
				img.get_size().x if img != null else 0, img.get_size().y if img != null else 0,
				str(st["off"]), str(st["masks"])])
	# --- hud: источник читает рисовалку и забыл PNG (рабочее дерево — волна до коммита) ---
	var hud_src := FileAccess.get_file_as_string(pxr_c30().path_join("scripts/hud.gd"))
	chk(hud_src.contains("brewed_icon") and not hud_src.contains("alch_icons"),
		"c30: hud brewed_btn читает UiIcons.brewed_icon, alch_icons в исходнике не упоминается")
	# --- alch_icons PNG+import отсутствуют (рабочее дерево; стад HEAD-архива до
	# коммита содержит легаси-копию — как и ассеты c29, пин по WORK, прецедент выше) ---
	var png_abs := pxr_c30().path_join("assets/alch_icons.png")
	var imp_abs := pxr_c30().path_join("assets/alch_icons.png.import")
	chk(not FileAccess.file_exists(png_abs) and not FileAccess.file_exists(imp_abs),
		"c30: alch_icons.png(+.import) удалены целиком — все 3 кадра, мёртвые 0/1 включительно")
	print("qa_lp c30: ls-tree базы — alch_icons.png трекалась в HEAD до удаления (снят вне Godot; золото == HEAD-блоб, чек в _t29)")
	# --- атлас-контракт не тронут ---
	var at: Texture2D = UIS.skill_atlas()
	chk(at.get_width() == 192 and at.get_height() == 16 and UIS.SKILL_SLOTS.size() == 12,
		"c30: атлас скиллов 192x16 и SKILL_SLOTS(12) не тронуты")

func pxr_c30() -> String:
	var ws := _c29_ws()
	return ws.path_join("pixel-rpg") if ws != "" else ProjectSettings.globalize_path("res://")

# =============================================================================
# c33: фиолетовая рампа C (вердикт c31 «на усмотрение» → капитан: C, полный
# scope). Пины: палитра+алиас CAVE_ROCK:=VIOLET; поштучный diff 13 LIVE-файлов
# против золотого среза HEAD tools/qa/gold/c33_base == таблица c31 scan2
# (всего 4832 px); остальные 29 трекаемых PNG бит-в-бит (md5 HEAD); old-hex
# (CAVE4 + 51 snap) не встречается нигде; off=0/mask=0 на ретаченных.
const C33_VIOLET := ["8071a4", "665686", "4b3e66", "302644"]
const C33_CAVE4 := ["7c8299", "5f657c", "454a5f", "2b2f40"]
const C33_SNAP := ["2e233f", "452e5e", "4a3865", "654389", "674a81", "704a98", "7d57a2",
	"9373b2", "a678d0", "ab88cb", "c1a4dc", "d6b6f4", "372345", "4d345d", "664e77",
	"1d1b28", "20162a", "26263c", "281f39", "29273f", "292941", "2c273d", "302a40",
	"302d42", "302d43", "302e43", "313147", "332f44", "33334a", "352d41", "353248",
	"383249", "38364e", "3f2c56", "583c70", "7f6e9c", "836fa2", "84609e", "9179ab",
	"967cb1", "977eb4", "997fb4", "9a7fb1", "9f82b4", "ae8ec6", "af90c9", "b795cf",
	"c0a2db", "c39fe1", "c6a0e7", "d0bee2"]
const C33_DIFF := {
	# c36 (вердикт c35): cave/cave_props_v1.png УБРАН — props-атлас легитимно
	# вырос 128×64->128×80 (регион CHEST_OPEN); dungeon_tiles.png УБРАН — легаси-
	# тайл 12 v2 пересобран (зона 48 px). Побайтовая целостность обоих файлов
	# пинится в _t36 (== кандидаты, == rebake, md5 двойного bake). Прежние
	# суммы таблицы: 925 и 133 входили в 4832 — стало 3774.
	# w5int (вердикт пользователя 16.11 «Вариант А»): cave/cave_wall_v1.png 1277->0 —
	# золотой срез c33_base для ЭТОГО файла обновлён на принятый байт-атлас волны
	# читаемости (wall после ретюна, md5 4A125B16...); запись таблицы вырождена в
	# побайтовый пин (любой diff против него = bad), доказательство миграции VIOLET
	# для стены держат _t16 (rebake генератора == файл) и off-скан c33 (off==0).
	# Пол (955) не двигался.
	"anim_tiles.png": 54, "cave/cave_floor_v1.png": 955,
	"cave/cave_wall_v1.png": 0, "class_mage.png": 8, "decor.png": 11,
	"mobs_archer.png": 2, "mobs_swarmling.png": 2,
	"mobs_wraith.png": 1006, "npc_merchant.png": 2, "portraits.png": 344,
	"portraits2.png": 113,
}
const C33_MD5_KEPT29 := {
	# c34: ashen_tiles.png УБРАН из списка — атлас легитимно изменён волной c34
	# (открытый сундук v2 в prop-зону строки 1, вердикт «Сундук пепелища ок»);
	# побайтовая целостность нового атласа пинится в _t35 (== bake_atlas и == v2)
	"brute.png": "73dedb5b9b26420c5466832e9032fabf",
	"campfire.png": "e2efeb093d3dc1579e97afbc12bcda32",
	"class_archer.png": "8b00142c7ffcf2ca6f161a59b63f8388",
	"class_warrior.png": "ea449f35a68a2233531d02e29314b7e0",
	"cursor_enemy.png": "af8e2e568e1de4111f455259a9b72503",
	"cursor_move.png": "d2475d2df98754ed968a2df802c7ddad",
	"fx/fx_dot.png": "85c821a12b70b3c6d3120412a8193102",
	"fx/fx_dot_soft.png": "d4c678a43633419efe9c4e1533c7992c",
	"fx/fx_flame.png": "f6c907c05fe94448017d732e96c72be7",
	"fx/fx_shard.png": "97345564934c92d5b542c9852df27417",
	"fx/fx_smoke.png": "592518f0a85b9e813efc81eb4b6a365d",
	"fx/fx_spark.png": "46457ec8cbd947367f1d97af1f5dc40e",
	"fx/fx_star.png": "afa6d037d323834d3c7dcb1b4f943403",
	"key.png": "85bd30fcd5b1f49aa8a5731829b262b9",
	"npc_elder.png": "ac4cec0e1ae2cc1df6f18b003b916595",
	"npc_farmer.png": "453ebf26675cb406524a4dab1b04a21e",
	"npc_hermit.png": "d458ca45bbcad51299d69074af212105",
	"npc_smith.png": "97788a16fa3af939b27b009d22dd094d",
	"player.png": "442d457117661445340e0385e95e4247",
	"projectiles.png": "1c42a8a4ab75766c04b0f293fb506e93",
	"shadow.png": "5f64bf91032ef8fdf4b13da11cbf6bbf",
	"slime.png": "7c07d4f502451dbdfe031bc0af345b3f",
	"tiles.png": "cb3e05695831f27d6b183140441a2a80",
	"ui/cursor_arrow.png": "714ba88ea5a5550d1040eaa726136820",
	"ui/cursor_crosshair.png": "f5bd8926cffbbef7f62f694d00e3ca36",
	"ui/panel_frame.png": "6db79b0d4573e60e57aec003183fe36c",
	"village/village_floor_v4.png": "bce6c93d9cc1ade2e45d51e687b72e70",
	"village/village_v4.png": "02aea8f41ffe011ef6357821f3940a47",
}

static func _c33_lum(h: String) -> float:
	var c := Color(h)
	return (maxf(maxf(c.r, c.g), c.b) + minf(minf(c.r, c.g), c.b)) * 0.5

## Старый hex -> ожидаемый новый (CAVE4 1:1 по тону; snap -> ближайший тон
## VIOLET по светлоте — то же правило, что mock c31 SnapIdx и tools_art/c33_violet.gd).
static func _c33_expect_map() -> Dictionary:
	var m := {}
	for i in 4:
		m[C33_CAVE4[i]] = C33_VIOLET[i]
	for h in C33_SNAP:
		var l := _c33_lum(h)
		var bi := 0
		var bd := 9e9
		for i in 4:
			var d := absf(_c33_lum(C33_VIOLET[i]) - l)
			if d < bd:
				bd = d
				bi = i
		m[h] = C33_VIOLET[bi]
	return m

## 5 спрайтов генерятся из легаси-GOLD корзиной c22 (источник истины — _t23):
## там тон выбирается по светлоте ЛЕГАСИ-цвета, а не «тон-в-тон», напр. 64 px
## ведьмы CAVE3->VIOLET2 — законное поведение принятой таблицы B, diff-счёт верен.
const C33_PIPE5 := ["mobs_wraith.png", "mobs_archer.png", "mobs_swarmling.png",
	"npc_merchant.png", "class_mage.png"]
## off-пиксели легаси-атласов на HEAD (POTENTIAL_GRAY нетронут по границам scope);
## после snap-ремапа ровно табличное число px уходит в палитру
const C33_OFF_HEAD := {"anim_tiles.png": 1294, "decor.png": 471, "dungeon_tiles.png": 4096}

func _t34() -> void:
	# 1) палитра + алиас (runtime-проверка: на голом HEAD краснеет, не ломая компиляцию)
	var vio: Array = PAL.RAMPS.get("VIOLET", [])
	var ok_v: bool = vio.size() == 4
	if ok_v:
		for i in 4:
			if String((vio[i] as Color).to_html(false)) != C33_VIOLET[i]:
				ok_v = false
	chk(ok_v, "c33: RAMPS[\"VIOLET\"] == рампа C #8071a4/#665686/#4b3e66/#302644 (голый HEAD: RED)")
	chk(vio.size() == 4 and PAL.RAMPS.get("CAVE_ROCK", null) == vio,
		"c33: алиас CAVE_ROCK := VIOLET (RAMPS: тот же массив)")
	# 2) золотой срез HEAD
	var ws := _c29_ws()
	var gdir := ""
	if ws != "":
		gdir = ws.path_join("tools").path_join("qa").path_join("gold").path_join("c33_base")
	var gold_ok: bool = gdir != "" and DirAccess.dir_exists_absolute(gdir)
	chk(gold_ok, "c33: gold base tools/qa/gold/c33_base (побайтовый срез HEAD) на месте")
	if not gold_ok:
		return
	var em := _c33_expect_map()
	var cidx: Dictionary = PAL.color_index()
	var sum_diff := 0
	var resid := 0
	var bad_total := 0
	var offm_total := 0
	for rel in C33_DIFF:
		var cur := Image.new()
		var bas := Image.new()
		if cur.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/" + rel)) != OK:
			chk(false, "c33: %s: нечитаем из res://assets" % rel)
			continue
		if bas.load_png_from_buffer(FileAccess.get_file_as_bytes(gdir.path_join(rel))) != OK:
			chk(false, "c33: %s: нечитаем из gold base" % rel)
			continue
		if cur.get_size() != bas.get_size():
			chk(false, "c33: %s: размер кадра не совпал с gold base" % rel)
			continue
		var diff := 0
		var bad := 0
		var off := 0
		var msk := 0
		for y in cur.get_height():
			for x in cur.get_width():
				var k1 := bas.get_pixel(x, y).to_argb32()
				var c2: Color = cur.get_pixel(x, y)
				var k2 := c2.to_argb32()
				var a2 := int(round(c2.a * 255.0))
				if a2 > 0:
					if a2 < 255:
						msk += 1
					if not cidx.has(k2):
						off += 1
					if em.has(c2.to_html(false)):
						resid += 1
				if k1 == k2:
					continue
				diff += 1
				var oh: String = "%06x" % (k1 & 0xFFFFFF)
				if C33_PIPE5.has(rel):
					if not em.has(oh) or not cidx.has(k2):
						bad += 1
				elif not em.has(oh) or String(em[oh]) != c2.to_html(false):
					bad += 1
		sum_diff += diff
		bad_total += bad
		offm_total += off + msk
		chk(diff == int(C33_DIFF[rel]) and bad == 0,
			"c33: %s diff=%d (таблица c31: %d), незаконных замен=%d" % [rel, diff, int(C33_DIFF[rel]), bad])
		var legacy_off = C33_OFF_HEAD.get(rel, null)
		var off_exp := 0 if legacy_off == null else int(legacy_off) - int(C33_DIFF[rel])
		chk(off == off_exp and msk == 0,
			"c33: %s off=%d mask=%d (ожидается %d/0: легаси-gray нетронут, snap вычищен)" % [rel, off, msk, off_exp])
	chk(sum_diff == 2497 and bad_total == 0,
		"c33: суммарный diff 11 файлов == 2497 px (3774 минус wall 1277, срез стены = база волны w5int; получено %d, bad=%d)" % [sum_diff, bad_total])
	chk(resid == 0, "c33: старых CAVE/snap hex не осталось (остаток %d)" % resid)
	# 3) остальные трекаемые PNG — бит-в-бит HEAD (28: ashen_tiles легитимно
	# изменён c34 и запинен в _t35)
	var keep_ok := true
	for rel in C33_MD5_KEPT29:
		if _t11_md5("res://assets/" + rel) != String(C33_MD5_KEPT29[rel]):
			keep_ok = false
			print("c33: ИЗМЕНЁН сверх scope: ", rel)
	chk(keep_ok, "c33: остальные %d трекаемых PNG бит-в-бит HEAD (md5)" % C33_MD5_KEPT29.size())
	# 4) POTENTIAL_GRAY легаси — нетронутость доказывается п.3 (tiles/player) и
	# п.2 для dungeon_tiles: diff там строго из old-домена snap/CAVE (bad==0).
	print("qa_lp c33: GOLDEN-пины сеток (CHAR_TO_TILE/BLOCKING t16) выше, без пересчёта")

# ------------------------------------------------------------------ c34 (контракт: «qa_lp _t34»; имя занято рампой c33 → _t35)
# Открытый сундук Пепелища (вердикт пользователя «Сундук пепелища ок», кадр v2
# волны c32b: двойной bake md5 DC27EB9FFFA66FAADE1A9E5863AA8AB5).
const C34_OPEN_B64 := "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACVSURBVDhPYxh8INTL9T+UiQF01JRxysGBg7nxf5AhILx4xab/zR2TwGyQOAhDleEGMIUgDNIMwiA2yHaiXUCRASBFkqIiWDHJBhzyEv+/ukabNANweQGGocpwA5AiWKiDNINcAWKDbCfJBSAngwz4Wm1IugHILoB5gWQXwAyIT8mDByDJBiBjog2ARRkuDFVGLcDAAACeEKfPlA/gNAAAAABJRU5ErkJggg=="
const C34_BASE_MD5_UNTOUCHED := {  # чужие сундуки (деревня t10→t14, пещера t11→t12): код и кадр не тронуты
	# c36 (вердикт c35): dungeon_zone.gd УБРАН — open_chest() легитимно расширен
	# (проп-кадр CHEST_OPEN вместо только тайла); поведение запинено в _t36.
	# c37 (P0 Esc-меню): world.gd УБРАН — do_quickload/фейлсейф легитимно изменили
	# мир; поведение запинено в _t37. Кадры чужих сундуков по-прежнему бит-в-бит.
	# g12 (голоса гл.1): interactable.gd УБРАН — лексема «коренье» в подсказке/тостах
	# сбора (сейв-формат и сундучная ветка не тронуты); поведение запинено в _t41.
	"res://assets/tiles.png": "cb3e05695831f27d6b183140441a2a80",
}

func _t35() -> void:
	# 1) кадр v2 в атласе: prop-зона строки 1 (96,16,16,16) побайтово == доставленный v2
	var v2 := Image.new()
	var ok2 := v2.load_png_from_buffer(Marshalls.base64_to_raw(C34_OPEN_B64)) == OK
	var fi := Image.new()
	var okf := fi.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ashen_tiles.png")) == OK
	var dv := 256
	if ok2 and okf and fi.get_width() >= 112 and fi.get_height() >= 32:
		dv = 0
		for y in 16:
			for x in 16:
				if fi.get_pixel(96 + x, 16 + y).to_argb32() != v2.get_pixel(x, y).to_argb32():
					dv += 1
	chk(dv == 0, "c34: атлас prop-зона (96,16,16,16) == доставленный v2-кадр побайтово (diff %d)" % dv)
	# 2) кадр печатает генератор (единый источник) и layout согласован с зоной
	var SH = load("res://tools_art/sheet_ashen_v1.gd")
	var has_open_fn := false
	if SH != null:
		for mi in SH.get_script_method_list():
			if String(mi.get("name", "")) == "_chest_open_frame":
				has_open_fn = true
	chk(has_open_fn, "c34: _chest_open_frame() есть в sheet_ashen_v1.gd — единый источник (голо-HEAD: RED)")
	var dgb := 256
	var rgn_gen = null
	if SH != null and has_open_fn:
		var baked: Image = SH.bake_atlas()
		if baked != null:
			dgb = 0
			for y in 16:
				for x in 16:
					if baked.get_pixel(96 + x, 16 + y).to_argb32() != v2.get_pixel(x, y).to_argb32():
						dgb += 1
		var smap: Dictionary = SH.get_script_constant_map()
		rgn_gen = (smap.get("PROP_REGIONS", {}) as Dictionary).get("CHEST_OPEN", null)
	chk(dgb == 0, "c34: bake_atlas() генератора печатает v2 в (96,16) побайтово (diff %d)" % dgb)
	chk(rgn_gen == Rect2(96, 16, 16, 16), "c34: layout инструмента: CHEST_OPEN == Rect2(96,16,16,16)")
	var AZ = load("res://scripts/ashen_zone.gd")
	var rgn_zone = (AZ.get_script_constant_map().get("PROP_REGIONS", {}) as Dictionary).get("CHEST_OPEN", null)
	chk(rgn_zone == Rect2(96, 16, 16, 16), "c34: зона использует тот же регион (layout синхронен)")
	# 3) ветка поведения: ни одного queue_free в AshenChest; персист-ключ не менялся
	var src := String(FileAccess.get_file_as_string("res://scripts/ashen_zone.gd"))
	var ci := src.find("class AshenChest:")
	var body := src.substr(ci) if ci >= 0 else ""
	chk(ci >= 0 and body.length() > 0 and not body.contains("queue_free("),
			"c34: в AshenChest нет queue_free — сундук остаётся в мире (голо-HEAD: RED)")
	chk(body.contains("open()") and body.contains("PROP_REGIONS[\"CHEST_OPEN\"]"),
			"c34: try_interact -> open() с открытым кадром v2 (идемпотентен, узел живёт)")
	chk(src.contains("\"chest@ashen:%d,%d\""), "c34: персист-ключ \"chest@ashen:x,y\" — без изменений")
	# 4) поведение на живом мире: открытие = used, кадр v2, узел и коллайдер целы
	var az = world.ashen_grid
	var chest = az.get("chest_node") if az != null else null
	if chest == null:
		chk(String(GameState.flags.get("ashen.chest", "")) == "taken",
				"c34: при taken узел спавнится (в qa_lp флаг не taken — узел обязан быть)")
	else:
		var g0: int = GameState.gold
		chest.try_interact()
		var g1: int = GameState.gold  # награда выдана; защита — от СЛЕДУЮЩИх вызовов
		var spr: Sprite2D = null
		for n in (chest as Node).get_children():
			if n is Sprite2D:
				spr = n as Sprite2D
		var reg_ok := spr != null and spr.texture is AtlasTexture \
				and (spr.texture as AtlasTexture).region == Rect2(96, 16, 16, 16)
		chk(reg_ok, "c34: после вскрытия спрайт — открытый кадр v2 (96,16), а не исчезновение")
		chk(bool(chest.get("used")) and is_instance_valid(chest),
				"c34: used=true, узел в дереве (коллайдер не снят)")
		var ncol := 0
		for n in (chest as Node).get_children():
			if n is CollisionShape2D:
				ncol += 1
		chk(ncol == 1, "c34: коллайдер сундука сохранён (декорация, а не пустая клетка)")
		chest.try_interact()
		chk(GameState.gold == g1, "c34: повторный interact не удваивает награду (защита прежняя)")
		chk(String(chest.call("get_hint")) == "", "c34: вскрытый сундук не подсказывает «Открыть»")
		chk(String(GameState.flags.get("ashen.chest", "")) == "taken",
				"c34: флаг taken выставлен (автосейв), uid-схема не тронута")
	# 5) регресс чужих сундуков (village t10→t14, cave t11→t12): код и кадр побайтово целы
	var okall := true
	for p in C34_BASE_MD5_UNTOUCHED:
		if _t11_md5(String(p)) != String(C34_BASE_MD5_UNTOUCHED[p]):
			okall = false
			print("c34: ИЗМЕНЕНО сверх scope: ", p)
	chk(okall, "c34: tiles.png бит-в-бит HEAD — кадры чужих сундуков не тронуты (world/gs/interactable: правки c37/g12 запинены в _t37/_t41)")
	# 6) пересборка мира с taken (спавн сразу открытым) — раннер qa_z1._phase_rebuild
	print("qa_lp c34: taken=>spawn-open запинен поведением в qa_z1 (пересборка мира)")

# ------------------------------------------------------------------ c36 (контракт: пин пещерного сундука)
# Пещерный сундук (вердикт пользователя «новый пещерный сундук берём»).
# Кандидаты волны c35 (лист «Пещера: открытый сундук»): проп-кадр 26×15
# (доставленный md5 7BFED0BF73B3D3168F02AC51EB171F0B) и легаси-тайл 12 v2
# (md5 ED81740F44833CDFDF49365FA478B433) — пинятся побайтово инлайн-b64
# (qa самодостаточен, паттерн _t35). Полосовой дефект прежнего «открытия»
# (перекрашенный корпус 182/256 + 20 px фиолетового свечения над крышкой)
# устранён структурно: тайл 12 = кандидат, зона раскрытия ровно 48 px,
# свечения нет — пин «на отсутствие» ниже.
const C36_OPEN_PROP_B64 := "iVBORw0KGgoAAAANSUhEUgAAABoAAAAPCAYAAAD6Ud/mAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAD0SURBVDhPY8AFLi5K+48NL16xCYyxybUmWP2HascPQAb0314AxxuaPDFwc8ek//EpeVjlQBhkIcgckBqosRCA7CKYRfHryrAaAsKELAJhmBqYuWCfghjoCpA1oWNcapAdh64GHqRWdm7/aYnBloAANklceHWN9n+t0AKscrgw2JJwBy2wt0Heg3kZxMaGYSkOhrGpAWF0c0B2gC2DxROyAuTwhbFB8ksfffqfv/0KPA6wqUWOI5AY2BIQIMUikCUe7StoaxGIDYofEKaaRTAxdIOQDcEmD6Kp4qPhYRGMD6IpsgiUzkEYlsFgfGyYHDUMDAwMAKCsKXc3wUylAAAAAElFTkSuQmCC"
const C36_TILE12_B64 := "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAEFSURBVDhPnZNNCoJQFIVdgRQ0ax7SD/RPZoU4iKIG1cCikTSIRi0gJFpBo1bQKhq0lrZy67y4j9Sn8Boc0eM9n0euGrYzpW5vTI/bQUvjyZqQNSq1PpWsNt0vWy0tVjtC1mi0XBqM5pTLF7WEDLIGng6aaigMqmSaBeU9AJCVDXy3rKV60/02cIYz0UD1nlnCQ5EVDUBT1cwS6osGOMD4rRcGXuRa5SEjAFgFA07nq6iH4Xhl9jDDALlGBsSHX8/j57wa8aBIA7xLGgDhLIBcYxoA3wD060GRBlgFA/zNPjHMYg8zDJBrlAANyQYM+EcCwL8zfk9WyeoID8IQPNdbJjzbmdIb0DXWehG3TG0AAAAASUVORK5CYII="
# канон двойного bake c36_chest12.gd (T11_DUNGEON_MD5 обновлён тем же значением)
const C36_TILES_MD5 := "d39709f47d2ee25cbfc9e7a1432431cd"
# сейв и чужие сундуки не тронуты: проводка c36 живёт только в
# cave_art/dungeon_zone/cave_paint (world/game_state/interactable бит-в-бит)
# c37 (P0 Esc-меню): game_state.gd и world.gd УБРАНЫ — start_fresh_game и
# do_quickload/фейлсейф легитимно их изменили; поведение запинено в _t37.
# g12 (голоса гл.1): interactable.gd УБРАН — лексема «коренье» (сбор); таблица
# пуста, чужое закрыто md5-регрессом _t41 (G12_UNTOUCHED) и пинами _t41.
const C36_UNTOUCHED := {
}

func _t36() -> void:
	var CA = load("res://scripts/cave_art.gd")
	var CP = load("res://tools_art/cave_paint.gd")
	# 1) регион и размер: CHEST_OPEN(14,65,26,15), атлас 128×80 (файл и константа)
	var regv = (CA.REGIONS as Dictionary).get("CHEST_OPEN", null)
	chk(regv != null and regv == Rect2(14, 65, 26, 15),
		"c36: REGIONS[\"CHEST_OPEN\"] == Rect2(14,65,26,15) (голо-HEAD: RED)")
	var cp := Image.new()
	var okp := cp.load_png_from_buffer(Marshalls.base64_to_raw(C36_OPEN_PROP_B64)) == OK
	var pbytes: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/cave/cave_props_v1.png")
	var pimg := Image.new()
	var okpi := pimg.load_png_from_buffer(pbytes) == OK
	chk(okp and okpi and pimg.get_size() == Vector2i(128, 80)
			and CA.ATLAS_SIZE == Vector2i(128, 80),
		"c36: props-атлас 128×80 — файл и ATLAS_SIZE (self-check c2 на новом размере)")
	var dvp := 26 * 15
	if okp and okpi and pimg.get_size() == Vector2i(128, 80):
		dvp = 0
		for y in 15:
			for x in 26:
				if pimg.get_pixel(14 + x, 65 + y).to_argb32() != cp.get_pixel(x, y).to_argb32():
					dvp += 1
	chk(dvp == 0, "c36: атлас (14,65,26,15) == доставленный кадр 26×15 побайтово (md5 7BFED0BF…, diff %d)" % dvp)
	# 2) генератор — единый источник: build_chest_open() печатает те же байты;
	#    rebake всего props-атласа == закоммиченный файл (двойной bake md5 канон)
	var by := {}
	for s in CP.prop_set_canon():
		by[String(s["name"])] = s["img"]
	var gen = by.get("CHEST_OPEN", null)
	var dvg := 26 * 15
	if gen != null and okp and (gen as Image).get_size() == Vector2i(26, 15):
		dvg = 0
		for y in 15:
			for x in 26:
				if (gen as Image).get_pixel(x, y).to_argb32() != cp.get_pixel(x, y).to_argb32():
					dvg += 1
	chk(gen != null and dvg == 0,
		"c36: cave_paint.build_chest_open() печатает кандидат побайтово (diff %d, голо-HEAD: RED)" % dvg)
	var pb: Dictionary = CP.bake_props_atlas(CA.REGIONS, CA.ATLAS_SIZE)
	chk((pb["fails"] as Array).is_empty()
			and (pb["img"] as Image).save_png_to_buffer() == pbytes,
		"c36: rebake props-атласа == committed (двойной bake md5 %s)" % _t11_md5("res://assets/cave/cave_props_v1.png"))
	# 3) легаси-тайл 12 v2: побайтово == кандидат; зона раскрытия ровно 48 px
	#    (ряды 0..3), корпус y4..15 байт-в-бит тайла 11, новых цветов 0;
	#    пин «на отсутствие» полосы: прежнее свечение 8071a4/665686 в тайле 12
	var t12 := Image.new()
	var okt := t12.load_png_from_buffer(Marshalls.base64_to_raw(C36_TILE12_B64)) == OK
	var dg := Image.new()
	var okd := dg.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/dungeon_tiles.png")) == OK
	var dvt := 256
	var zone := 0
	var body := 0
	var newc := 0
	var glow := 0
	if okt and okd and dg.get_size() == Vector2i(256, 16):
		dvt = 0
		var set11 := {}
		for y in 16:
			for x in 16:
				set11[dg.get_pixel(176 + x, y).to_html(false)] = true
		for y in 16:
			for x in 16:
				var a: Color = dg.get_pixel(176 + x, y)
				var b: Color = dg.get_pixel(192 + x, y)
				if a.to_argb32() != b.to_argb32():
					if y <= 3:
						zone += 1
					else:
						body += 1
				if b.a > 0.5 and not set11.has(b.to_html(false)):
					newc += 1
				if b.to_html(false) in ["8071a4", "665686", "4b3e66", "302644"]:
					glow += 1
				if dg.get_pixel(192 + x, y).to_argb32() != t12.get_pixel(x, y).to_argb32():
					dvt += 1
	chk(dvt == 0, "c36: dungeon_tiles тайл 12 == кандидат ED81740F… побайтово (diff %d)" % dvt)
	chk(zone == 48 and body == 0 and newc == 0,
		"c36: зона раскрытия 48/256 (ряды 0..3), корпус == тайл 11, новых цветов 0 (z=%d b=%d n=%d)" % [zone, body, newc])
	chk(glow == 0 and _t11_md5("res://assets/dungeon_tiles.png") == C36_TILES_MD5,
		"c36: полоса легаси устранена — свечения нет, файл == канон двойного bake (%s)" % C36_TILES_MD5)
	# 4) живая проводка: проп один, закрыт; вскрытие реальным интерактивом —
	#    тайл 12 и проп-кадр CHEST_OPEN (без полосы над крышкой: кадр 26×15
	#    закрывает клетку, подложка — кандидат v2)
	var dz = world.dungeon_zone
	var props: Array = get_tree().get_nodes_in_group("cave_chest_prop")
	chk(props.size() == 1, "c36: в слое пещеры ровно один широкий проп сундука (получено %d)" % props.size())
	var spr: Sprite2D = (props[0] as Sprite2D) if props.size() == 1 else null
	var r0 := Rect2()
	if spr != null and spr.texture is AtlasTexture:
		r0 = (spr.texture as AtlasTexture).region
	chk(r0 == Rect2(14, 51, 26, 13),
		"c36: при has_amulet=false проп — закрытый CHEST (получено %s)" % str(r0))
	GameState.door_opened = true  # канон-гейт сундука: сначала дверь зала
	GameState.has_key = true      # ключ Геральда — штатный путь try_interact
	if dz.chest_node != null:
		dz.chest_node.try_interact()
	# g18 (вердикт 16.11 ~22:27 «большой широкий сундук поверх маленького»):
	# при v1-арте легаси-подложка тайла 12 из-под пропа убрана — клетка остаётся
	# полом, рисунок сундука — только проп. Перепин легитимный: состояние держит
	# GameState.has_amulet + кадр пропа (пинеется ниже), а не тайл 12.
	var src_open: int = dz.tilemap.get_cell_source_id(dz.chest_tile)
	chk(bool(GameState.has_amulet) and dz.tilemap != null \
			and (src_open == CA.SRC_FLOOR if CA.have_art() \
					else dz.tilemap.get_cell_atlas_coords(dz.chest_tile) == Vector2i(12, 0)),
		"c36/g18: вскрытие — has_amulet; клетка: пол v1 (легаси-тайл 12 убран) / тайл 12 в легаси (амулет не убегает)")
	var r1 := Rect2()
	if spr != null and is_instance_valid(spr) and spr.texture is AtlasTexture:
		r1 = (spr.texture as AtlasTexture).region
	chk(r1 == Rect2(14, 65, 26, 15),
		"c36: вскрытие — проп сменил кадр на CHEST_OPEN (получено %s)" % str(r1))
	# 5) перезаход: пересборка слоя (build читает has_amulet) — сундук открытый
	var layer2 = CA.build(world)
	var reopen := Rect2()
	if layer2 != null:
		for c in layer2.get_children():
			if c is Sprite2D and (c as Sprite2D).texture is AtlasTexture:
				var rr: Rect2 = ((c as Sprite2D).texture as AtlasTexture).region
				if rr.size == Vector2(26, 15):
					reopen = rr
		layer2.queue_free()
	chk(reopen == Rect2(14, 65, 26, 15),
		"c36: перезаход (пересборка слоя при has_amulet) — стоит открытый (получено %s)" % str(reopen))
	# 6) сейв и соседи: game_state/world/interactable бит-в-бит, ключи на месте
	var okall := true
	for p in C36_UNTOUCHED:
		if _t11_md5(String(p)) != String(C36_UNTOUCHED[p]):
			okall = false
			print("c36: ИЗМЕНЕНО сверх scope: ", p)
	chk(okall, "c36: чужие сундуки/сейв не тронуты (interactable: g12-лексема запинена в _t41; md5-регресс чужих — G12_UNTOUCHED)")
	var gs := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	chk(gs.contains("\"has_amulet\"") and gs.contains("chest_mark_used"),
		"c36: персист-ключи has_amulet/chest_mark_used на месте")
	print("qa_lp c36: GOLDEN-пины сеток не пересчитывались (тайл 12 — визуальное состояние)")

# ------------------------------------------------------------------ c37 (контракт: P0 Esc-меню + фейлсейф старта)
# P0 пользователя: «при запуске открывается подземелье, персонажа не видно,
# ничего сделать не могу». Пины: валидация позиции Resume (скала/граница ->
# штатный вход зоны + тост), секция «Игра» (Новая игра двухступенчатая с
# отменой по 3 с, Загрузить == F9-путь), канон §4 (мета-пепел/амулет живы).
const C37_STUCK := Vector2(8, 4808)  # клетка (0,0) пещеры PIN_SEED — граница '#'

var _c37_toasts: Array = []

func _t37() -> void:
	# 0) чистый стол: тосты собираем, чужие диалоги (наследие _t36) дожимаем
	_c37_toasts.clear()
	GameState.toast.connect(func(t: String) -> void: _c37_toasts.append(t))
	var guard := 0
	while world.hud.is_dialog_open() and guard < 20:
		guard += 1
		world.hud.advance()
	GameState.input_locked = false
	# c37 probe-диагноз (4.7.2): у headless-Window size (64,64) и GUI-pick
	# выбрасывает события вне этого квадрата — ни push_input, ни parse_input_event
	# до кнопок не доходят. Раздуваем окно до канваса (headless-квота 1:1).
	get_tree().root.size = Vector2i(640, 360)
	# 1) текстовые пины проводки (голо-HEAD: RED)
	var wsrc := FileAccess.get_file_as_string("res://scripts/world.gd")
	chk(wsrc.contains("do_quickload()") and wsrc.contains("_place_resumed_player()"),
		"c37: world — F9 и _ready идут единым путём do_quickload/_place_resumed_player (голо-HEAD: RED)")
	var msrc := FileAccess.get_file_as_string("res://scripts/settings_menu.gd")
	chk(msrc.contains("do_quickload") and msrc.contains("save_morkheim.json")
			and msrc.contains("reload_current_scene.call_deferred"),
		"c37: меню: «Загрузить» дерёт do_quickload, «Новая игра» удал сейв + перезагрузка (голо-HEAD: RED)")
	var gsrc := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	chk(gsrc.contains("func start_fresh_game") and gsrc.contains("class_id = \"\""),
		"c37: game_state.start_fresh_game с очисткой класса (голо-HEAD: RED)")
	# 2) семантика «Новой игры» (память): забег сгорает, вечное живёт (§0/§4)
	GameState.class_id = "warrior"
	GameState.level = 5
	GameState.xp = 99
	GameState.gold = 777
	GameState.has_amulet = true
	GameState.in_cave = true
	GameState.pos_valid = true
	GameState.flags["meta.ash"] = 500
	GameState.flags["rs.earned"] = 100
	GameState.flags["ach.test"] = 1
	GameState.flags["daily.test"] = 1
	GameState.flags["hint.test"] = "1"
	GameState.flags["q.smelt"] = 1
	GameState.flags["tal.x"] = 1
	var wave0 := GameState.ng_wave()
	GameState.start_fresh_game()
	chk(int(GameState.gold) == 0 and int(GameState.level) == 1 and int(GameState.xp) == 0
			and String(GameState.class_id) == "" and not bool(GameState.has_sword),
		"c37: fresh — герой/золото/класс обнулены (gold=%d lv=%d class=[%s])" % [int(GameState.gold), int(GameState.level), String(GameState.class_id)])
	chk(int(GameState.flags.get("meta.ash", 0)) == 465,
		"c37: пепел по канону смерти: 500 − догорание(100−65) = 465 (получено %d)" % int(GameState.flags.get("meta.ash", 0)))
	chk(bool(GameState.has_amulet) and GameState.flags.has("ach.test")
			and GameState.flags.has("daily.test") and GameState.flags.has("hint.test")
			and not GameState.flags.has("q.smelt") and not GameState.flags.has("tal.x")
			and not GameState.flags.has("rs.earned"),
		"c37: вечный слой и Амулет живы; круговой (q./tal./rs.) сгорел")
	chk(GameState.ng_wave() == wave0 and not bool(GameState.in_cave)
			and not bool(GameState.pos_valid),
		"c37: волна с отказа не растёт, вход мира — деревня")
	# 3) фейлсейф размещения (живой мир): скала/за границей -> вход зоны + тост
	_c37_write_save(true, C37_STUCK.x, C37_STUCK.y)
	world.do_quickload()
	var centry: Vector2 = world.CAVE_OFFSET + world.dungeon_zone.spawn_world_pos
	chk(world.player.global_position == centry and _c37_toasts.has("Герой вышел к входу")
			and bool(GameState.in_cave),
		"c37: скала пещеры (0,0)='#' — герой на входе пещеры + тост (pos=%s)" % str(world.player.global_position))
	_c37_write_save(false, 8.0, 9608.0)
	world.do_quickload()
	var aentry: Vector2 = world.ASHEN_OFFSET + world.ashen_grid.spawn_world_pos
	chk(world.player.global_position == aentry and String(world.active_area) == "ashen",
		"c37: скала Пепелища — вход Пепелища, не деревня (pos=%s)" % str(world.player.global_position))
	var bad := Vector2i(-1, -1)
	for yy in range(0, world.map_h, 2):
		for xx in range(0, world.map_w, 2):
			if not bool(world.call("_village_walkable", Vector2i(xx, yy))):
				bad = Vector2i(xx, yy)
				break
		if bad.x >= 0:
			break
	var badw: Vector2 = world.tile_to_world(bad)
	_c37_write_save(false, badw.x, badw.y)
	world.do_quickload()
	chk(world.player.global_position == world.tile_to_world(world.spawn_tile)
			and bool(world.call("_village_walkable", world.spawn_tile)),
		"c37: стена деревни (%s) — герой ровно на спавне деревни (pos=%s)" % [str(bad), str(world.player.global_position)])
	# позитивная ветка: валидная позиция уважается, фейлсейф не лезет
	var goodp: Vector2 = world.tile_to_world(world.spawn_tile)
	var rescues := _c37_toasts.count("Герой вышел к входу")
	_c37_write_save(false, goodp.x, goodp.y)
	world.do_quickload()
	chk(world.player.global_position == goodp
			and _c37_toasts.count("Герой вышел к входу") == rescues,
		"c37: валидная позиция сейва не тронута (pos=%s)" % str(world.player.global_position))
	# 4) меню «Игра»: узлы, доступность «Загрузить» от сейва, мышь, клавиатура
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var sm = null
	for c in world.get_children():
		if c is SettingsMenu:
			sm = c
	chk(sm != null, "c37: SettingsMenu найден в мире")
	_c37_push_key(KEY_ESCAPE)
	await _frames(3)
	chk(sm != null and sm.is_open() and String(sm.btn_new_game.text) == "Новая игра"
			and String(sm.btn_load_game.text) == "Загрузить"
			and bool(sm.btn_load_game.disabled) and not bool(sm.btn_new_game.disabled),
		"c37: сейва нет — «Загрузить» неактивна, «Новая игра» активна (голо-HEAD: RED)")
	await _frames(6)
	chk(sm.panel.size.y <= 340 and sm.panel.size.x <= 620,
		"c37: панель %s влезает в 640×360 (секция не сломала мерку qa8)" % str(sm.panel.size))
	# дальше — с сейвом на диске: «Загрузить» активна и фокусируема
	_c37_write_save(false, goodp.x, goodp.y)
	_c37_push_key(KEY_ESCAPE)  # закрыть
	await _frames(3)
	_c37_push_key(KEY_ESCAPE)  # открыть: сейв виден
	await _frames(3)
	# мышь: настоящее нажатие по центру кнопки -> armed
	_c37_click(sm.btn_new_game)
	await _frames(4)
	chk(String(sm.btn_new_game.text) == "Точно? — прогресс круга сгорит",
		"c37: касание мышь#1 — подтверждение вооружено (текст=[%s])" % String(sm.btn_new_game.text))
	# клавиатура: без фокуса Tab наводит, Tab->Tab переводит, Enter вооружает/жмёт
	_c37_push_key(KEY_TAB)
	await _frames(3)
	chk(get_viewport().gui_get_focus_owner() == sm.btn_load_game,
		"c37: Tab — фокус на «Загрузить» (мышинное меню стало клавиатурным, голо-HEAD: RED)")
	_c37_push_key(KEY_TAB)
	await _frames(3)
	chk(get_viewport().gui_get_focus_owner() == sm.btn_new_game,
		"c37: Tab — перенос фокуса на «Новую игру»")
	# отмена: 3.4 с без второго касания -> текст откатан, сейв/меню целые
	await get_tree().create_timer(3.4).timeout
	chk(String(sm.btn_new_game.text) == "Новая игра",
		"c37: таймаут 3 с отменил подтверждение (текст=[%s])" % String(sm.btn_new_game.text))
	# при появлении сейва «Загрузить» оживает (пересъём состояния на open)
	_c37_write_save(false, goodp.x, goodp.y)
	_c37_push_key(KEY_ESCAPE)  # закрыть
	await _frames(3)
	chk(not bool(sm.is_open()) and not bool(GameState.input_locked),
		"c37: Esc закрыл меню и отпустил ввод (приоритет не съехал)")
	_c37_push_key(KEY_ESCAPE)  # открыть заново
	await _frames(3)
	chk(bool(sm.is_open()) and not bool(sm.btn_load_game.disabled),
		"c37: сейв есть — «Загрузить» активна")
	# «Загрузить» реальной мышью (меню УЖЕ открыто chk-выше): закрытие + F9-тост,
	# повторное нажатие (второй цикл) идемпотентен
	var loads := _c37_toasts.count("Игра загружена (F9)")
	_c37_click(sm.btn_load_game)
	await _frames(8)
	chk(not bool(sm.is_open()) and _c37_toasts.count("Игра загружена (F9)") == loads + 1,
		"c37: мышиная «Загрузить» == F9-тост (меню закрыто, идемпотентно)")
	_c37_push_key(KEY_ESCAPE)
	await _frames(3)
	_c37_click(sm.btn_load_game)
	await _frames(8)
	chk(_c37_toasts.count("Игра загружена (F9)") == loads + 2
			and world.player.global_position == goodp,
		"c37: повторное «Загрузить» безопасно (позиция стабильна)")
	# глотание мира не сломано: Q под открытым меню не пьёт зелье (матрица qa_s2)
	GameState.herbs = 3
	_c37_push_key(KEY_ESCAPE)
	await _frames(3)
	if not sm.is_open():
		_c37_push_key(KEY_ESCAPE)
		await _frames(3)
	_c37_push_key(KEY_Q)
	await _frames(4)
	chk(int(GameState.herbs) == 3 and sm.is_open(), "c37: Q под меню по-прежнему проглочен")
	if sm.is_open():
		_c37_push_key(KEY_ESCAPE)
		await _frames(3)
	print("qa_lp c37: фейлсейф старта и выход из залипшего забега запинены; "
			+ "подтверждение «Новой игры» наживую (reload сцены) снято оконным прогоном")

# --- хелперы c37 ---

func _c37_write_save(in_cave: bool, px: float, py: float) -> void:
	var d := GameState.to_dict()
	d["in_cave"] = in_cave
	d["px"] = px
	d["py"] = py
	d["pos_valid"] = true
	d["class_id"] = "warrior"
	d["seen_intro"] = true
	d["seen_cave_intro"] = true
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()

func _c37_push_key(phys: int) -> void:
	# паттерн qa_ib/qa_s2: press+release синхронно через Window.push_input
	var e := InputEventKey.new()
	e.keycode = phys
	e.physical_keycode = phys
	e.pressed = true
	get_tree().root.push_input(e)
	var r := InputEventKey.new()
	r.keycode = phys
	r.physical_keycode = phys
	r.pressed = false
	get_tree().root.push_input(r)

## Мышиное нажатие на центр контрола: паттерн qa_ib _click_at (motion+press+
## release, координаты ОКНА через get_canvas_transform контрола) — работает
## после раздутия headless-окна (см. начало _t37).
func _c37_click(c: Control) -> void:
	var t: Transform2D = c.get_canvas_transform()
	var vp: Vector2 = t * c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = vp
	mm.global_position = vp
	get_tree().root.push_input(mm)
	for press in [true, false]:
		var b := InputEventMouseButton.new()
		b.position = vp
		b.global_position = vp
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = press
		get_tree().root.push_input(b)
		await _frames(2)
	await _frames(2)

# ============================================================================
# g12: голоса деревни (LINES_VILLAGE) + квест «Три коренья» (GOAL_TASKS Г1.2)
# ============================================================================

# Снятые строки старой озвучки («Травы для старейшины», «Три слайма», старый
# Гриим, реплики героя). Автоскан приёмки: НИ ОДНА не встречается в данных.
const G12_OLD_LINES := [
	"Ах, путник... Силы тают", "Травы с алыми ягодами", "Я соберу их. Держитесь!",
	"Как травы? Отвар нужен", "Три травы! Вот теперь", "Ты спасла меня",
	"Здорово... Ступай, лес зовёт героя.", "стерегут старинный клад",
	"Победи трёх слаймов", "Договорились. Три слайма", "трещат по швам",
	"Три слайма?! Ну ты даёшь", "Счастливо, герой! Заглядывай.",
	"Побеждено три слайма!", "Каждый борётся как может.",
	"Пойду спрошу, чем могу помочь.", "Не всё... Пепел помнит.",
	"Куй да плати — вот и вся песня", "Мечи, топоры, кожа, кольчуга",
	"Слушаю, кузнец. Что есть доброго?",
]
# Принятые вердиктом строки листа (проверяются дословно):
const G12_DIALOGUES_JSON1 := [  # dialogues.json: Морга М1-М5, Дран Д1-Д3
	"Очнулся? Значит, лес выбрал тебя раньше, чем я успела отговорить.",
	"Слушай коротко: хворь сидит во мне. Три коренья с южной опушки — и я встану.",
	"Коренья сами не придут. Красный усик под кустами, южная опушка. Ищи да не ленись.",
	"Живые, пахнут лесом. Отвар сварит Ута — я лишь скажу ей: этот стоит того.",
	"Не благодари. Лесу факел нужнее, чем мне отвар. Ступай к Грииму, он растолкует.",
	"Смола — пятнадцать, геройская цена. Грииму назло, тебе впрок. Торг кончен.",
	"Готовый факел — двадцать пять. Чего тянуть? Тьма ведь не подождёт.",
	"Товар не любит сквозняка, а Дран — пустых карманов. Но для тебя — заходи.",
]
const G12_DIALOGUES_JSON2 := [  # dialogues_v2.json: Гриим Г1-Г3, Ута У1-У3, Геральд Е1-Е3
	"Факел — древко, тряпица, смола. Смолу бери у Драна. Сплету даром, печь моя.",
	"Держи. В пещере огонь — второй ты. Уронишь — первого не сыщешь.",
	"Молот занятой. Говори делом или ступай: искры не ждут.",
	"Сухоцвет да жим, поровну. На три вдоха в котёл. Над паром не дыши — глупеют.",
	"Котелок — твои руки. Вари сам: ровные руки и есть всё лекарское дело.",
	"Котёл горячий — мне не о чем. Остынет — приходи.",
	"Гниль травами не лечится. Она не хворь — голод. А голод не заговаривают.",
	"Восточней опушки лес помнит огонь паче дождя. Тамошний пепел не тает. Не ходи туда.",
	"Ступай. Стариком не оборачивайся: спину мне лес согнул недаром.",
]
const G12_HINTS := [  # С1-С3 живут в world.gd (FirstHint.show_hint вызовы)
	"Коренья — у южной опушки, красный усик под кустами. Три — и к старейшине.",
	"Факел куёт Гриим: нужно его смола. Без огня в пещере не считаются шаги.",
	"Вари у Уты: сухоцвет да жим. Котёл греется у её дома, деньги не нужны.",
]
# g12 не трогает (регресс приёмки: Esc-меню, RunSummary/мета, HUD, FirstHint…):
# g13 (экономика гл.1): hud.gd, game_state.gd и shop.gd УБРАНЫ — У2-хук/смола
# в hud, факелы+материал в game_state, вендорные витрины в shop легитимно их
# изменили; поведение запинено в _t42. Остальные — по-прежнему бит-в-бит.
const G12_UNTOUCHED := {
	"res://scripts/settings_menu.gd": "c7b90737cc53c457cf3963b69e5bd742",
	"res://scripts/run_summary.gd": "6404ba292ef8ea899d6a0c0db43655f8",
	"res://scripts/npc.gd": "419a3887918731d4d2207f3bcf51fd23",
	"res://scripts/first_hint.gd": "93520eda37ea1e453cd2bc4c737e04d4",
	# 16.11 вечер: текст-фикс пользователя «здрав->здоров» тронул alchemy.gd —
	# ре-пин по прецеденту вердиктных волн (g13/g14/g15), базис прежний: md5
	# файла на диске архива (CRLF), измерен распаковкой git archive HEAD.
	"res://scripts/alchemy.gd": "abbb8e8687fe4c9c289bcfa1e7254845",
	# g14 (рубрики+значки достижений, просьба пользователя 16.11) ЦЕЛЕНАПРАВЛЕННО
	# изменил journal.gd — ре-пин по прецеденту g13 (hud/shop/game_state убраны
	# из таблицы): поведение g12-приёмки живое, новый хеш принятого файла.
	# 16.11 оживление хвоста _t41 (t50), базис этой записи: md5 файла НА ДИСКЕ
	# стенда, т.е. с CRLF, которые отдаёт git archive при core.autocrlf=true —
	# ровно так считает _t11_md5, и у остальных семи записей базис тот же
	# (ср. npc.gd 419a3887… == файл на диске, тогда как LF-блоб дал бы
	# fb9bd412…). Прежнее значение d3dbdf81… было md5 от LF-блоба, поэтому
	# запись краснела на ровном месте; journal.gd не тронут, пересчитана
	# только строка таблицы.
	# g15 (карточки Steam/WoW + крупные значки, просьба пользователя 16.11)
	# ЦЕЛЕНАПРАВЛЕННО изменили journal.gd — ре-пин по прецедентам g13 (hud/shop/
	# game_state убраны из таблицы) и t50 (базис = md5 файла на диске стенда,
	# CRLF из git archive; его считает _t11_md5). Поведение g12-приёмки живое.
	# g18 (вердикт 16.11 ~22:07 «блоки достижений должны быть равны по высоте»)
	# ЦЕЛЕНАПРАВЛЕННО изменили journal.gd — равная высота карточек + описание
	# <=2 строк; ре-пин тем же прецедентом (базис — md5 файла на диске).
	"res://scripts/journal.gd": "b854bd0d34e14ab7906539799ce8739c",
}

var _g12_toasts: Array = []

func _g12_drain() -> void:
	var guard := 0
	while world.hud.is_dialog_open() and guard < 24:
		guard += 1
		world.hud.advance()
		await _frames(1)

## 16.11 (t50, оживление хвоста _t41): FirstHint ставит hint.<id> в кадре
## фактического показа, очередь сериализована и стоит под input_locked
## (диалог, витрина лавки, журнал). Значит после реплики с лавкой своей
## подсказки надо ДОЖДАТЬСЯ: бюджет — кадры фиксированного шага, 900 = 15 с
## логики (замер на этом же хвосте: 472 и 241 кадр; цикл выходит в кадре
## флага, поэтому запас дёшев и не добавляет времени в зелёном прогоне).
func _g12_wait_hint(id: String, frames_budget: int) -> int:
	var w := 0
	while str(GameState.flags.get("hint." + id, "")) != "1" and w < frames_budget:
		w += 1
		await _frames(1)
	return w

func _t41() -> void:
	GameState.toast.connect(func(t: String) -> void: _g12_toasts.append(t))
	# 0) данные: автоскан старых строк и дословность принятых (LINES_VILLAGE)
	var d1: String = FileAccess.get_file_as_string("res://data/dialogues.json")
	var d2: String = FileAccess.get_file_as_string("res://data/dialogues_v2.json")
	var wsrc: String = FileAccess.get_file_as_string("res://scripts/world.gd")
	var ghosts: Array = []
	for old in G12_OLD_LINES:
		if d1.contains(String(old)) or d2.contains(String(old)):
			ghosts.append(old)
	chk(ghosts.is_empty() and not d1.contains("спасла"),
		"g12: автоскан — ни одной старой строки «Трав»/«Трёх слаймов»/старого Гриима не осталось (%s)" % str(ghosts))
	var miss1: Array = []
	for s in G12_DIALOGUES_JSON1:
		if not d1.contains(String(s)):
			miss1.append(s)
	chk(miss1.is_empty(), "g12: М1-М5/Д1-Д3 — дословно в dialogues.json (%s)" % str(miss1))
	var miss2: Array = []
	for s in G12_DIALOGUES_JSON2:
		if not d2.contains(String(s)):
			miss2.append(s)
	chk(miss2.is_empty(), "g12: Г1-Г3/У1-У3/Е1-Е3 — дословно в dialogues_v2.json (%s)" % str(miss2))
	var miss3: Array = []
	for s in G12_HINTS:
		if not wsrc.contains(String(s)):
			miss3.append(s)
	chk(miss3.is_empty(), "g12: С1-С3 — дословно в FirstHint-хуках world.gd (%s)" % str(miss3))
	# глава 1 молчалива: в dialogues.json нет ни одной реплики героя
	var hero_lines := 0
	var parsed: Variant = JSON.parse_string(d1)
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed:
			for ln in (parsed[k] as Array):
				if String((ln as Dictionary).get("who", "")) == "hero":
					hero_lines += 1
	chk(hero_lines == 0, "g12: ни одной реплики героя в главу 1 не вернулось (герой молчалив), найдено %d" % hero_lines)
	# 1) реестр и цифры BALANCE
	chk(String(QuestsData.QUESTS["elder"]["title"]) == "Три коренья"
			and str(QuestsData.QUESTS["elder"]["targets"][1]["label"]).contains("коренья")
			and str(QuestsData.QUESTS["elder"]["targets"][2]["label"]).contains("коренья"),
		"g12: журнал — «Три коренья» + лейблы цели «коренья» (GLOSSARY #21)")
	chk(QuestsData.GOLD_QUEST_TREES == 20 and QuestsData.GOLD_QUEST_SLIMES == 30,
		"g12: реестр цифр BALANCE: 20/30 зол. за сдачи")
	# 2) живой полный цикл квеста
	GameState.elder_quest = 0
	GameState.slime_quest = 0
	GameState.herbs = 0
	GameState.slime_kills_circle = 0
	GameState.set_flag("meta.q_elder_done", 0)
	GameState.flags.erase("q.smith_talked")
	GameState.flags.erase("q.uta_talked")
	for hid in ["roots", "torch_smith", "herbalist"]:
		GameState.flags.erase("hint." + hid)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.input_locked = false
	var uta_found := false
	for c in world.village_zone.get_children():
		var nid: Variant = c.get("npc_id")  # паттерн world._find_npc: сравнение Variant без
		if nid != null:                     # String() — конструктор падает на чужих Variant
			if typeof(nid) != TYPE_STRING:
				print("qa_lp g12: нестроковый npc_id tipo=%d val=%s на %s (%s)" % [typeof(nid), str(nid), String(c.name), c.get_class()])
			if str(nid) == "uta":
				uta_found = true
	chk(uta_found, "g12: травница Ута стоит у тропы к южной опушке (npc «uta» в деревне)")
	# выдача: М1+М2,quest=1,С1 один раз за сейв
	world.talk("elder")
	await _frames(2)
	var ok_take: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON1[0])
	await _g12_drain()
	await _frames(4)
	chk(ok_take and int(GameState.elder_quest) == 1,
		"g12: выдача Морга М1→М2, elder_quest=1 (кадр первой реплики: %s)" % str(ok_take))
	chk(str(GameState.flags.get("hint.roots", "")) == "1",
		"g12: С1 всплыла после выдачи (hint.roots)")
	if FirstHint.I != null:
		FirstHint.I.show_hint("roots", "дубль-заявка")  # дедуп: флаг уже стоит
		chk((FirstHint.I.get("_queue") as Array).is_empty(),
			"g12: С1 повторно не встанет в очередь (один раз за сейв)")
	# повтор с нулём: М3
	world.talk("elder")
	await _frames(2)
	var ok_prog: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON1[2])
	await _g12_drain()
	chk(ok_prog, "g12: повтор (квест взят) — М3")
	# сбор у южной опушки живыми кустами
	var picked_evt := _g12_toasts.size()
	var g := 0
	while GameState.herbs < 3 and g < 12:
		g += 1
		for c in world.village_zone.get_children():
			# 16.11 (qa5-финиш, попытка 2 — капитанская): попытка 1 починила
			# String(null), но наступилась на другую половину: у Object get()
			# ровно ОДИН аргумент (дефолт — только у Dictionary), и двухаргументный
			# вызов на TileMapLayer-детях убивал корутину здесь же. Теперь:
			# null-страховка ДО String. Обрыв здесь с эпохи g12 лишал _t41 хвоста
			# (проверки «У1…», таблица байтов G12) — оживает этим же коммитом.
			var kv: Variant = c.get("kind")
			if kv != null and String(kv) == "herb" and not bool(c.get("used")):
				GameState.combat_t = 0.0
				c.try_interact()
				await _frames(1)
				break
	chk(GameState.herbs >= 3 and _g12_toasts.size() > picked_evt,
		"g12: сбор 3 корений живыми кустами (herbs=%d, тост лексема «коренье»)" % int(GameState.herbs))
	# сейв на середине и восстановление прогресса (пины GameState)
	var gold_mid := int(GameState.gold)
	GameState.save_game()
	GameState.elder_quest = 0
	GameState.herbs = 0
	var loaded := GameState.load_game()
	chk(loaded and int(GameState.elder_quest) == 1 and int(GameState.herbs) >= 3,
		"g12: загрузка на середине восстанавливает прогресс (elder_quest=%d herbs=%d)" % [int(GameState.elder_quest), int(GameState.herbs)])
	# сдача: М4 + BALANCE-золото + вечная метка
	GameState.input_locked = false
	var gold0 := int(GameState.gold)
	world.talk("elder")
	await _frames(2)
	var ok_done: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON1[3])
	await _g12_drain()
	chk(ok_done and int(GameState.elder_quest) == 2 and int(GameState.gold) == gold0 + 20
			and int(GameState.flags.get("meta.q_elder_done", 0)) == 1,
		"g12: сдача М4: +20 зол. (%d→%d), quest=2, meta-метка" % [gold0, int(GameState.gold)])
	# повтор после сдачи: М5
	world.talk("elder")
	await _frames(2)
	var ok_after: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON1[4])
	await _g12_drain()
	chk(ok_after, "g12: повтор после сдачи — М5")
	# Дран: выдача с тостом-проводником (квест молчит в репликах), сдача +30 зол.
	# g13: за репликами Драна открывается его лавка — в этом прогоне её закрываем,
	# чтобы следующая реплика звучала в свободном мире (торговые пины — в _t42).
	world.talk("merchant")
	await _frames(2)
	var ok_m: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON1[5])
	await _g12_drain()
	if Shop.is_open():
		Shop.close()
	var found_toast := false
	for t in _g12_toasts:
		if String(t).contains("Трофеи со слаймов"):
			found_toast = true
	chk(ok_m and int(GameState.slime_quest) == 1 and found_toast,
		"g12: Д1 + выдача «Трофеи со слаймов» с проводником-тостом")
	GameState.slime_kills_circle = 3
	GameState.input_locked = false
	var gold1 := int(GameState.gold)
	world.talk("merchant")
	await _g12_drain()
	if Shop.is_open():
		Shop.close()
	chk(int(GameState.slime_quest) == 2 and int(GameState.gold) == gold1 + 30,
		"g12: сдача Драну +30 зол. (%d→%d), quest=2" % [gold1, int(GameState.gold)])
	# Гриим: Г1 + С2 при первой встрече круга, Г3 в повтор; лавка открывается
	world.talk("smith")
	await _frames(2)
	var ok_s: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON2[0])
	await _g12_drain()
	# 16.11 оживление хвоста _t41 (t50): тексты Г1 побайтово равны константе
	# (сверялась строка dialogues_v2 «smith»[0] и G12_DIALOGUES_JSON2[0], 75
	# символов, различий ноль), расходился не текст, а флаг С2. Причин две,
	# обе легитимные следствия g13: (1) у диалога Гриима появился колбэк
	# Shop.open(), лавка держит input_locked, а FirstHint ставит hint.* только
	# в момент фактического показа (first_hint.gd:103) и под залоченным вводом
	# не стартует; (2) очередь FirstHint сериализована — к этому кадру ещё
	# досматривается С1 (HIDE_AFTER 4 с = 240 кадров), «пока активна, другие id
	# ждут». Поэтому лавку закрываем ДО проверки и своей подсказки дожидается
	# тестовый бюджет. Текстовая часть пина не тронута, константы не перепилены.
	if Shop.is_open():
		Shop.close()
	var w_s := await _g12_wait_hint("torch_smith", 900)
	chk(ok_s and str(GameState.flags.get("hint.torch_smith", "")) == "1",
		"g12: Г1 у кузницы + С2 (hint.torch_smith)")
	if Shop.is_open():
		Shop.close()
	world.talk("smith")
	await _frames(2)
	var ok_s2: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON2[2])
	await _g12_drain()
	if Shop.is_open():
		Shop.close()
	chk(ok_s2, "g12: повтор у Гриима — Г3")
	# Ута: У1 + С3 при первой встрече, У3 в повтор
	world.talk("uta")
	await _frames(2)
	var ok_u: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON2[3])
	await _g12_drain()
	# то же, что у Гриима: котёл Уты с g13 открывает её витрину Shop.open("uta")
	# и держит ввод, а С3 встанет лишь в кадре фактического показа подсказки,
	# когда досмотрит своя строка предыдущая. Тексты У1 не перепилены.
	if Shop.is_open():
		Shop.close()
	var w_u := await _g12_wait_hint("herbalist", 900)
	chk(ok_u and str(GameState.flags.get("hint.herbalist", "")) == "1",
		"g12: У1 у травницы + С3 (hint.herbalist)")
	if Shop.is_open():
		Shop.close()
	world.talk("uta")
	await _frames(2)
	var ok_u2: bool = world.hud.is_dialog_open() \
			and String(world.hud.dtext.text) == String(G12_DIALOGUES_JSON2[5])
	await _g12_drain()
	if Shop.is_open():
		Shop.close()
	chk(ok_u2, "g12: повтор у Уты — У3")
	chk(str(GameState.flags.get("q.smith_talked", "")) == "1"
			and str(GameState.flags.get("q.uta_talked", "")) == "1",
		"g12: флаги встреч в разрешённом пространстве имён q.* (assert qa_q3)")
	# 3) регресс: g12 не трогала чужие файлы (Esc-меню, RunSummary/мета, HUD…)
	var touched: Array = []
	for p in G12_UNTOUCHED:
		if _t11_md5(String(p)) != String(G12_UNTOUCHED[p]):
			touched.append(String(p))
	chk(touched.is_empty(), "g12: Esc-меню/RunSummary/мета/npc/FirstHint/alchemy/journal бит-в-бит (%s)" % str(touched))
	# порядок: сейв-тест не оставляет мусора
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("qa_lp g12: GOLDEN-пины сеток не пересчитывались; Е1-Е3 — данные под хук Г1.5; С2/С3 дождались показа за %d/%d кадров" % [w_s, w_u])

# ════════════════════ g13: экономика деревни (Г1.3–Г1.5, BALANCE-реестр) ════════════════════
## Строка листа LINES_VILLAGE -> её место в константных листах _t41:
## Г1-Г3 = G12_DIALOGUES_JSON2[0..2], У1-У3 = [3..5], Е1-Е3 = [6..8].
func _g13_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func _t42() -> void:
	# 0) реестр BALANCE: пять «новых» чисел — по одному литералу (BALANCE.md
	# «Правила коридора»). Строки 1–2 живут в QuestsData, 6–8 — в GearData.
	chk(QuestsData.GOLD_QUEST_TREES == 20 and QuestsData.GOLD_QUEST_SLIMES == 30,
		"g13: реестр BALANCE строки 1–2: 20/30 зол. за сдачи")
	chk(GearData.PRICE_RESIN == 15 and GearData.PRICE_TORCH == 25 and GearData.PRICE_POTION == 30,
		"g13: реестр BALANCE строки 6–8: 15/25/30")
	chk(GearData.price("resin") == GearData.PRICE_RESIN and GearData.price("torch") == GearData.PRICE_TORCH
			and GearData.price("potion") == GearData.PRICE_POTION,
		"g13: ценники товаров берутся из реестра, не дублируются")
	chk(GearData.PRICE_TORCH - GearData.PRICE_RESIN == GearData.CRAFT_SAVING and GearData.CRAFT_SAVING == 10,
		"g13: крафт (15) дешевле готового (25) ровно на 10 — разницу не менять")
	# 1) витрины: чей прилавок — тот набор (л/р кнопок и секций)
	GameState.input_locked = false
	if Shop.is_open():
		Shop.close()
	GameState.gold = 200
	Shop.open("merchant")
	await _frames(3)
	chk(String(Shop.I.head_lbl.text) == "Лавка Драна" \
			and (Shop.I.buy_btns["resin"] as Button).visible \
			and (Shop.I.buy_btns["torch"] as Button).visible \
			and not (Shop.I.buy_btns["sword"] as Button).visible \
			and not Shop.I.craft_btn.visible and not Shop.I.sell_head.visible \
			and not Shop.I.altar_head.visible,
		"g13: лавка Драна: смола+факел, кузнечных секций (крафт/скупка/алтарь) не видно")
	Shop.close(); await _frames(2)
	Shop.open("smith"); await _frames(3)
	chk(String(Shop.I.head_lbl.text) == "Кузница Гриима" \
			and (Shop.I.buy_btns["sword"] as Button).visible \
			and Shop.I.craft_btn.visible and Shop.I.altar_head.visible \
			and Shop.I.sell_head.visible \
			and not (Shop.I.buy_btns["resin"] as Button).visible,
		"g13: кузница не сломана: 5 снарядок + крафт + скупка + алтарь, товары Драна скрыты")
	Shop.close(); await _frames(2)
	# 2) сделка с Драном: смола 15 зол.; рюкзак полон — деньги целы
	var gr0 := int(GameState.gold)
	Shop.open("merchant"); await _frames(2)
	Shop.I._on_buy("resin"); await _frames(2)
	chk(GameState.mat_count("smola") == 1 and int(GameState.gold) == gr0 - 15,
		"g13: смола у Драна −15 зол., рюкзак 1/%d" % GameState.MAT_CAP)
	GameState.materials["smola"] = GameState.MAT_CAP
	var gr1 := int(GameState.gold)
	Shop.I._on_buy("resin"); await _frames(2)
	chk(int(GameState.gold) == gr1 and GameState.mat_count("smola") == GameState.MAT_CAP,
		"g13: рюкзак смолы полон — покупка отбита, золото не списано")
	# готовый факел у Драна: 25 зол.
	Shop.I._on_buy("torch"); await _frames(2)
	chk(GameState.torches == 1 and int(GameState.gold) == gr1 - 25,
		"g13: готовый факел −25 зол. (факелов: 1)")
	Shop.close(); await _frames(2)
	# 3) крафт у Гриима: даром, из одной смолы; ПИН равенства «тот же предмет»
	GameState.materials["smola"] = 1
	var gc0 := int(GameState.gold)
	Shop.open("smith"); await _frames(2)
	Shop.I._on_craft_torch(); await _frames(3)  # первый крафт: лавка закрылась, Г2
	var g2ok: bool = world.hud.is_dialog_open() \
			and str(world.hud.dtext.text) == String(G12_DIALOGUES_JSON2[1])
	await _g12_drain()
	chk(g2ok and GameState.torches == 2 and GameState.mat_count("smola") == 0 \
			and int(GameState.gold) == gc0 and not Shop.is_open() \
			and str(GameState.flags.get("q.smith_forge", "")) == "1",
		"g13: крафт даром: золото %d цело, смола списана, факел 2, Г2 дословно" % gc0)
	# «факел из крафта == факел из лавки одним объектом»: один id в реестре и
	# одна точка GameState.add_torch() на оба пути (источник + поведение выше:
	# покупка дала +1, крафт дал +1 в тот же счётчик torches).
	var gss := _g13_src("res://scripts/game_state.gd")
	var shs := _g13_src("res://scripts/shop.gd")
	chk(gss.contains("func add_torch()") \
			and shs.count("GameState.add_torch()") == 2 \
			and GearData.ITEMS.has("torch") and GearData.ITEMS.size() == GearData.ITEMS.keys().size(),
		"g13: лавка и крафт зовут один add_torch() для одного предмета «torch»")
	# смолы нет — Гриим отказывает молча (ни факела, ни списания)
	Shop.open("smith"); await _frames(2)
	var gc1 := int(GameState.gold)
	Shop.I._on_craft_torch(); await _frames(2)
	chk(GameState.torches == 2 and int(GameState.gold) == gc1 and Shop.is_open(),
		"g13: без смолы крафт отбит (лавка открыта, счётчики целы)")
	Shop.close(); await _frames(2)
	# 4) зельеварка: котёл (костёр у дома Уты), варка бесплатна, == c30-заряд
	GameState.flags.erase("q.uta_brewed")
	GameState.brewed_potions = 0
	GameState.materials = {"suhotsvet": 1, "zhim": 1, "smola": 0}
	GameState.hp = GameState.max_hp - 10
	world.player.global_position = world.tile_to_world(Vector2i(18, 13))
	await _frames(6)
	# Прайм одноразовых выплат процесса (ачивка/ежедневная награда achv.gd
	# сыпят золотом при первом on_brew — канон, не баг): иначе их разовый
	# payout протёк бы в замер «варка бесплатна». Карман фиксируем после.
	Achv.on_brew()
	GameState.gold = 160
	var gb0 := int(GameState.gold)
	chk(world.campfire_near() != null, "g13: котёл у дома Уты живая точка варки (герой у огня)")
	world.hud._on_brew_pressed("strong_potion"); await _frames(3)
	var u2ok: bool = world.hud.is_dialog_open() \
			and str(world.hud.dtext.text) == String(G12_DIALOGUES_JSON2[4])
	await _g12_drain()
	chk(u2ok and GameState.brewed_potions == 1 and int(GameState.gold) == gb0 \
			and GameState.mat_count("suhotsvet") == 0 and GameState.mat_count("zhim") == 0 \
			and str(GameState.flags.get("q.uta_brewed", "")) == "1",
		"g13: варка у котла бесплатна (сухоцвет+жим списаны, %d зол. целы), У2 первое зелье" % gb0)
	# результат == существующее зелье здоровья: пьётся кнопкой HUD, +6 (c30)
	GameState.input_locked = false
	var hp0 := int(GameState.hp)
	world.hud._on_brewed_pressed(); await _frames(2)
	chk(int(GameState.hp) == hp0 + GameState.STRONG_POTION_HEAL and GameState.brewed_potions == 0,
		"g13: варёное == крепкое зелье здоровья: кнопка c30, +%d HP" % GameState.STRONG_POTION_HEAL)
	# стек/расход: кап 2, третий вар не берёт («пояс полон» — тот же текст, что у варки)
	GameState.materials = {"suhotsvet": 5, "zhim": 5, "smola": 0}
	world.hud._on_brew_pressed("strong_potion"); await _frames(1)
	world.hud._on_brew_pressed("strong_potion"); await _frames(1)
	var gm0 := int(GameState.gold)
	world.hud._on_brew_pressed("strong_potion"); await _frames(2)
	var full_toast := false
	for t in _g12_toasts:
		if String(t).contains("Пояс полон"):
			full_toast = true
	chk(GameState.brewed_potions == GameState.BREWED_CAP and full_toast \
			and GameState.mat_count("suhotsvet") == 3 and int(GameState.gold) == gm0,
		"g13: кап стек крепких = %d, переполнение отбито без расхода/списания (двух варок хватило: 5->3)" % GameState.BREWED_CAP)
	# покупка зелья у Уты: 30 зол., под капом отказ с тем же текстом «пояс полон»
	Shop.open("uta"); await _frames(2)
	var gu0 := int(GameState.gold)
	Shop.I._on_buy("potion"); await _frames(2)
	chk(int(GameState.gold) == gu0 and String(Shop.I.head_lbl.text) == "Прилавок Уты",
		"g13: утыч заряд под капом не продаётся (золото цело), вывеска верна")
	GameState.brewed_potions = 0
	Shop.I._on_buy("potion"); await _frames(2)
	chk(GameState.brewed_potions == 1 and int(GameState.gold) == gu0 - 30,
		"g13: крепкое зелье у Уты −30 зол. (BALANCE строка 8)")
	Shop.close(); await _frames(2)
	# 5) отшельник Геральд за околицей (Г1.5): Е1–Е3 первая беседа, далее Е3
	var hm_found := false
	for c in world.village_zone.get_children():
		var nid: Variant = c.get("npc_id")
		if nid != null and str(nid) == "hermit_out":
			hm_found = true
	chk(hm_found and world.dialogues.has("hermit_outside") and world.dialogues.has("hermit_out_repeat"),
		"g13: Геральд за околицей стоит (живой лист npc_hermit.png), реплики загружены")
	GameState.flags.erase("q.hermit_met")
	world.talk("hermit_out"); await _frames(2)
	var e1ok: bool = world.hud.is_dialog_open() \
			and str(world.hud.dtext.text) == String(G12_DIALOGUES_JSON2[6])
	var who_ok := true
	for ln in (world.dialogues["hermit_outside"] as Array):
		if String((ln as Dictionary).get("who", "")) != "hermit":
			who_ok = false  # hud NAMES: «hermit» => «Отшельник Геральд»
	await _g12_drain()
	chk(e1ok and who_ok and str(GameState.flags.get("q.hermit_met", "")) == "1",
		"g13: первая встреча — Е1 (лор) дословно, кто=«hermit» (имя в NAMES), флаг круга")
	world.talk("hermit_out"); await _frames(2)
	var e3ok: bool = world.hud.is_dialog_open() \
			and str(world.hud.dtext.text) == String(G12_DIALOGUES_JSON2[8])
	await _g12_drain()
	chk(e3ok, "g13: повтор за околицей — Е3 (прощание)")
	# 6) факелы/смола переживают сейв-загрузку (P1)
	GameState.torches = 2
	GameState.materials["smola"] = 3
	GameState.save_game(); await _frames(2)
	GameState.torches = 0
	GameState.materials["smola"] = 0
	var ldr := GameState.load_game()
	chk(ldr and GameState.torches == 2 and GameState.mat_count("smola") == 3,
		"g13: сейв/загрузка: факелы=2 и смола=3 восстановлены")
	var wss := _g13_src("res://scripts/game_state.gd")
	chk(wss.contains("torches = 0") and wss.contains("\"torches\": torches"),
		"g13: torches в сейве и в круговом вайпе (нажитое круга сгорает)")
	# 7) деревенский сундук = плановые +15 (кошель не его); кошель живёт вне деревни
	var ichs := _g13_src("res://scripts/interactable.gd")
	chk(ichs.contains("if area != \"village\":") and ichs.contains("randi_range(32, 42)"),
		"g13: кошель 32–42 gated зоной; литерал жив (пин T14 не обманут)")
	var village_chest = null  # слабый тип: prop-доступ к interactable.gd без стат-ошибки
	for c in world.village_zone.get_children():
		if c.get("kind") != null and str(c.get("kind")) == "chest":
			village_chest = c
	var gcx := int(GameState.gold)
	seed(777)
	GameState.chests_used.clear()
	village_chest.used = false
	var n_toasts0 := _g12_toasts.size()
	village_chest.try_interact(); await _frames(3)
	var chest_delta := int(GameState.gold) - gcx
	var purse_leak := false
	for i in range(n_toasts0, _g12_toasts.size()):
		if String(_g12_toasts[i]).contains("кошель"):
			purse_leak = true
	chk(chest_delta >= 8 and chest_delta <= 18 and not purse_leak,
		"g13: деревенский сундук дал %d зол. (горсть 8–18), кошель не потёк (BALANCE строка 4)" % chest_delta)
	# 8) эконометр главы (приёмка С1 коридора 78–106 + остаток ≈47): детерминизм
	# по seed перед каждым броском — рулетинг воспроизводим бит-в-бит в батарее.
	const ECON_SEED := 20261116
	GameState.gold = 0
	GameState.brewed_potions = 0
	GameState.elder_quest = 1
	GameState.herbs = 3
	GameState.input_locked = false
	world.talk("elder"); await _g12_drain(); await _frames(2)   # сдача Морги +20
	GameState.slime_quest = 1
	GameState.slime_kills_circle = 3
	world.talk("merchant"); await _g12_drain(); await _frames(2)  # сдача Драну +30
	if Shop.is_open():
		Shop.close()
	var mob_delta := 0
	var mob_i := 0
	for c in world.village_zone.get_children():
		var sp: String = String(c.get_script().resource_path) if c.get_script() != null else ""
		if not (sp.ends_with("slime.gd") or sp.ends_with("mob_swarmling.gd")):
			continue
		mob_i += 1
		seed(ECON_SEED + mob_i * 7919)
		var g_before := int(GameState.gold)
		if sp.ends_with("slime.gd"):
			c._die()  # slime.gd: смерть отдельным методом
		else:
			c.hurt(999, c.global_position + Vector2(1, 0))  # рой умирает через hurt()
		await _frames(1)
		mob_delta += int(GameState.gold) - g_before
	chk(mob_i == 8, "g13: обязательная зачистка главы = 8 тварей (6 слаймов + 2 мглокрыса), есть %d" % mob_i)
	seed(ECON_SEED + 91)
	GameState.chests_used.clear()
	village_chest.used = false
	var gch := int(GameState.gold)
	village_chest.try_interact(); await _frames(3)
	var econ_chest := int(GameState.gold) - gch
	var income := int(GameState.gold)  # старт был 0 — всё нажитое и есть доход
	chk(income >= 78 and income <= 106,
		"g13: доход главы = %d зол. в коридоре 78–106 (50 квесты + %d твари + %d сундук), seed=%d" % [income, mob_delta, econ_chest, ECON_SEED])
	# обязательная корзина 45: смола 15 + зелье 30 (факел из смолы — даром)
	Shop.open("merchant"); await _frames(2)
	Shop.I._on_buy("resin"); await _frames(1)
	Shop.I._on_buy("potion"); await _frames(1)
	Shop.close(); await _frames(1)
	Shop.open("smith"); await _frames(2)
	GameState.flags["q.smith_forge"] = "1"  # не переспамливаем Г2 в этом прогоне
	Shop.I._on_craft_torch(); await _frames(2)
	Shop.close(); await _frames(1)
	var leftover := int(GameState.gold)
	chk(leftover == income - 45 and leftover >= 33 and leftover <= 61,
		"g13: остаток на вход в главу 2 = %d зол. (доход %d − корзина 45; коридор 33–61 ≈ план 47)" % [leftover, income])
	print("qa_lp g13: эконометр: доход=%d (квесты 50, твари=%d, сундук=%d), корзина 45, остаток=%d, seed=%d" % [income, mob_delta, econ_chest, leftover, ECON_SEED])
	# 9) регресс реестра-пинов чужих файлов идёт в _t41 (G12_UNTOUCHED без hud/
	# game_state/shop — их правки запинены здесь); сейв-мусор убираем.
	GameState.input_locked = false
	if Shop.is_open():
		Shop.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("qa_lp g13: экономика главы 1 запинена: реестр, витрины, факел-равенство, котёл, Геральд, эконометр")

# ------------------------------------------------- t44: w3int «Лес v1» в игре (вердикт «берём»)
# Bake-md5 лесных атласов — те самые байты, что смотрел вердикт пользователя по
# листу (двойной bake в w3/w3int совпал побайтово).
const T44_FLOOR_MD5 := "ded3921ad37c0dd2442d0960298b3095"
const T44_PROPS_MD5 := "e44a824e9b4dd6ff6264f9e86df1400d"
const T44_MAP_MD5 := "c9b59e4f21e5482bfcf3b10556e85e0f"

func _t44() -> void:
	# 1) сетка/литералы бит-в-бит (GOLDEN не пересчитывается — md5 сети пиним здесь)
	chk(_t11_md5("res://data/map_village.json") == T44_MAP_MD5,
		"t44: map_village.json — md5 бит-в-бит (GOLDEN не пересчитан)")
	var wsrc := FileAccess.get_file_as_string("res://scripts/world.gd")
	chk(wsrc.contains('"t": 5') and wsrc.contains('"r": 12') and wsrc.contains('"T": 15'),
		"t44: CHAR_TO_TILE t/T/r = 5/12/15 бит-в-бит")
	chk(wsrc.contains("5: [6, 6, 0, 5]") and wsrc.contains("12: [11, 10, 0, 1]"),
		"t44: BLOCK_SHAPES дерево/валун бит-в-бит")
	# 2) атласы: md5 запечённого листа вердикта + off/mask-скан (новых цветов палитры 0)
	chk(_t11_md5("res://assets/forest/forest_floor_v1.png") == T44_FLOOR_MD5,
		"t44: forest_floor_v1.png — bake md5 = байты листа вердикта")
	chk(_t11_md5("res://assets/forest/forest_props_v1.png") == T44_PROPS_MD5,
		"t44: forest_props_v1.png — bake md5 = байты листа вердикта")
	var allowed := {}
	for ramp in PAL.RAMPS.values():
		for c in ramp:
			allowed[c] = true
	for c in PAL.FLATS.values():
		allowed[c] = true
	allowed[PAL.FIRE_HOT] = true
	var off := 0
	var mask := 0
	for pair: Array in [["res://assets/forest/forest_floor_v1.png", true],
			["res://assets/forest/forest_props_v1.png", false]]:
		var img := Image.load_from_file(ProjectSettings.globalize_path(String(pair[0])))
		chk(img != null, "t44: атлас прочитан %s" % String(pair[0]))
		if img == null:
			continue
		for yy in img.get_height():
			for xx in img.get_width():
				var c := img.get_pixel(xx, yy)
				if c.a == 0.0:
					continue
				if c.a < 1.0:
					mask += 1
				if not allowed.has(c):
					off += 1
	chk(off == 0 and mask == 0,
		"t44: off-скан леса: off=%d mask=%d (новых цветов/полупрозрачных — 0, PixelPalette)" % [off, mask])
	# 3) манифест-зеркало: data/forest_regions.json — единственный источник раскладки
	var mf := JSON.new()
	chk(mf.parse(FileAccess.get_file_as_string(ForestArt.MANIFEST_PATH)) == OK,
		"t44: forest_regions.json читается")
	var md: Dictionary = mf.data
	var mirror_ok := true
	for k in (md["props"] as Dictionary).keys():
		var v: Dictionary = md["props"][k]
		if not ForestArt.REGIONS.has(k) or ForestArt.REGIONS[k] != Rect2(v["x"], v["y"], v["w"], v["h"]):
			mirror_ok = false
	for k in ForestArt.REGIONS.keys():
		if not (md["props"] as Dictionary).has(k):
			mirror_ok = false
	chk(mirror_ok, "t44: REGIONS == forest_regions.json (все %d регионов)" % ForestArt.REGIONS.size())
	chk(int((md["floor_slots"] as Dictionary)["FFLR"]) == int(ForestArt.FLOOR_SLOTS["FFLR"]) \
			and float((md["sway"] as Dictionary)["T_s"]) == ForestArt.SWAY_T,
		"t44: floor_slots и sway T_s=0.5 — манифест и модуль согласны")
	# 4) тайлмап: лесной пол на source2, счётчик c26 785→0, v4-пол бит-в-бит
	var tl: TileMapLayer = null
	for c in world.village_zone.get_children():
		if c is TileMapLayer:
			tl = c
			break
	chk(tl != null and tl.tile_set.has_source(0) and tl.tile_set.has_source(1) and tl.tile_set.has_source(2),
		"t44: источники 0(легаси)/1(v4)/2(лес) на месте — фолбэк-ветки живы")
	var forest_cells := 0
	var src2 := 0
	var src0 := 0
	var layout_ok := true
	for cell in tl.get_used_cells():
		var s := tl.get_cell_source_id(cell)
		var ch := _ch(world.map_rows, cell.x, cell.y)
		if s == 0:
			src0 += 1
			continue
		if s == 2:
			src2 += 1
			if not ForestArt.FLOOR_CHARS.has(ch):
				layout_ok = false
			elif tl.get_cell_atlas_coords(cell) != Vector2i(ForestArt.floor_slot(world, cell.x, cell.y), 0):
				layout_ok = false
			continue
		if s == 1:
			if ForestArt.FLOOR_CHARS.has(ch):
				layout_ok = false
			var want := 0 if "WRDs".find(ch) >= 0 else int(VillageArt.FLOOR_SLOTS.get(ch, -7))
			if tl.get_cell_atlas_coords(cell).x != want:
				layout_ok = false
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length():
			if ForestArt.FLOOR_CHARS.has(row[x]):
				forest_cells += 1
	chk(forest_cells == 785 and src2 == 785 and layout_ok,
		"t44: счётчик c26: лесных клеток %d, все на source2 (t+T+r=785), слоты совпадают" % forest_cells)
	chk(src0 == 0,
		"t44: видимых клеток легаси tiles.png (source0) = %d — план 785→0" % src0)
	chk(FileAccess.file_exists("res://assets/tiles.png"),
		"t44: tiles.png на месте (удаление — финалом w4)")
	# 5) пропы: детерминированное количество по формуле build(); кроны в реестре; z V-01
	var expect_trees := 0
	var expect_under := 0
	var r_n := 0
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length():
			var ch2 := row[x]
			if ch2 == "t":
				expect_trees += 1
			elif ch2 == "T":
				if CaveArt.frac(x, y, 17) < 0.68:
					expect_trees += 1
				elif CaveArt.frac(x, y, 29) < 0.45:
					expect_under += 1
			elif ch2 == "r":
				r_n += 1
	chk(world._ys_canopies.size() == expect_trees,
		"t44: крон в _ys_canopies = %d (формула: t + 68%% от T)" % world._ys_canopies.size())
	var spr_n := 0
	for c in world.forest_v1.get_children():
		if c is Sprite2D:
			spr_n += 1
		if c is CollisionObject2D:
			chk(false, "t44: физический узел появился в ForestV1")
	chk(spr_n == expect_trees + expect_under + r_n,
		"t44: спрайтов ForestV1 = %d (деревья %d + подлесок %d + валуны %d) — детерминизм" % [spr_n, expect_trees, expect_under, r_n])
	var z_ok := true
	for i in [0, 1, 2, 3, 4]:
		if i >= world._ys_canopies.size():
			break
		var spr := world._ys_canopies[i] as Sprite2D
		var foot_g := spr.to_global(Vector2(0.0, float(spr.texture.get_height()) * 0.5 + spr.offset.y))
		if spr.z_index != int(round(fposmod(foot_g.y, world.YS_CYCLE))):
			z_ok = false
	chk(z_ok, "t44: z выборки крон == Y стопы mod 4800 (канон стоп V-01)")
	# 6) свай: трёхфазный, чистая функция времени, ноль физ-узлов
	var sway = world.forest_v1.get_node_or_null("ForestSway")
	chk(sway != null and sway.items.size() > 0,
		"t44: overlay-свай живёт: %d субъектов, T=%.1f с, кадр int(t/T+фаза)%%3" % [sway.items.size() if sway != null else 0, ForestArt.SWAY_T])
	if sway != null and sway.items.size() > 0:
		var it0: Dictionary = sway.items[0]
		chk(it0["a"] != it0["b"] and it0["b"] != it0["c"] and it0["a"] != it0["c"],
			"t44: у свай-субъекта три разных baked-кадра A/B/C (±1 px строк листа)")
		var det_ok := true
		for k in 6:
			var t1 := int(float(k) / ForestArt.SWAY_T) % 3
			var t2 := int(float(k) / ForestArt.SWAY_T) % 3
			if t1 != t2:
				det_ok = false
		chk(det_ok, "t44: кадр — чистая функция времени (повтор броска идентичен)")
	print("qa_lp t44: лес v1 запинен: c26 785->%d source0, источники 0/1/2, атласы = байты листа, манифест-зеркало, спрайтов %d, свай %d, tiles.png цел" % [src0, spr_n, sway.items.size() if sway != null else 0])

# ------------------------------------------- t46: микроволна юзер-фиксов 16.11
# Пины на сегодняшние фиксы: рывок вдоль стены (589212b), «усы» мобов (3ef13f6,
# mob_avoid.gd), агро только по прямой видимости + память SEE_MEMORY (1a1c932),
# возврат к арке входа после резюма (34edbf7). Подвкладки журнала (76f389b)
# пинит qa_vlg::_inv11 — там живой мир деревни. Каждый пин устроен так, что на
# ПРЕЖНЕЙ механике он краснеет (проверено пооткатно в этом же стенде).
# Нового стенда не заведено: секция живёт в qa_lp; геометрия берётся из ЖИВОЙ
# сетки пещеры сида 42 (пин не строит своих стен), пины поведенческие — без md5.

const T46_THR := 18.0      # порог мили рывка == 13 + размер_цели*0.5 (player.gd::_boar_land)
const T46_CHASE := 48.0    # slime.gd::CHASE_DIST
const T46_WANDER := 16.0   # slime.gd::SPEED_WANDER
const T46_SEE_FRAMES := 96 # slime.gd::SEE_MEMORY 1.6 с на 60 fps

## Мировая координата центра клетки пещеры (пещера — этаж CAVE_OFFSET).
func _t46_cw(c: Vector2i) -> Vector2:
	return world.CAVE_OFFSET + world.tile_to_world(c)

## Клетка, ближайшая к мировой точке пещеры (проверка «не прошёл ли сквозь стену»).
func _t46_cell(w: Vector2) -> Vector2i:
	var l: Vector2 = w - world.CAVE_OFFSET
	return Vector2i(int(round((l.x - 8.0) / 16.0)), int(round((l.y - 10.0) / 16.0)))

func _t46_fl(rows: Array, c: Vector2i) -> bool:
	return _walk(_ch(rows, c.x, c.y), CAVE_WALK)

## Луч по слою стен 2 между мировыми точками (пустой словар = чисто).
func _t46_ray(a: Vector2, b: Vector2) -> Dictionary:
	var space: PhysicsDirectSpaceState2D = world.player.get_world_2d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters2D.create(a, b, 2, []))

## Стендовый слайм в пещере: setup() считает координаты по деревенской сетке,
## поэтому позицию и гнездо ставим вручную — ровно как генератор для своей зоны.
## live=false — физика выключена (мишень ждёт удара, не бегает).
func _t46_mob(c: Vector2i, live: bool) -> Node2D:
	var sl: Node2D = load("res://scripts/slime.gd").new()
	world.cave_zone.add_child(sl)
	sl.setup(world, Vector2i(1, 1))
	sl.global_position = _t46_cw(c)
	sl.set("home", _t46_cw(c))
	sl.set_physics_process(live)
	return sl

## Зеркало player.gd::_slide_endpoint (константы те же: 40 px предел, 4 px маржа):
## нужно, чтобы ВЫБРАТЬ из всех углов пещеры тот, где скольжение реально доводит
## до мили. Поведение по-прежнему проверяется живым _boar_dash, не зеркалом.
func _t46_slide(from: Vector2, contact: Vector2, n: Vector2, t: Vector2) -> Vector2:
	var base_tan := n.orthogonal()
	if n.length_squared() <= 0.0001:
		base_tan = Vector2.ZERO
	var best := contact
	var best_d: float = contact.distance_to(t)
	var ex: Array = [world.player.get_rid()]
	for sgn in [1.0, -1.0]:
		var tan: Vector2 = base_tan * sgn
		if tan.dot(t - contact) <= 0.0:
			continue
		var want: float = minf(40.0, contact.distance_to(t))
		var hit2: Dictionary = world.player.get_world_2d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters2D.create(contact, contact + tan * want, 2, ex))
		var ep: Vector2 = contact + tan * want
		if not hit2.is_empty():
			ep = contact + tan * maxf(0.0, contact.distance_to(hit2["position"]) - 4.0)
		if ep.distance_to(t) < best_d - 1.0:
			best_d = ep.distance_to(t)
			best = ep
	return best

## Выпуклый угол под «рывок из упора»: ряд стены 2..4 клетки, весь ряд над ним
## проходим, за дальним торцом — пол. Герой над стеной, цель за торцом: прямая
## цепляет ВЕРХ стены (нормаль вверх), скольжение по верхнемуусу доезжает до цели,
## а прежний «упор» (contact) оставляет цель вне мили — на том и стоит пин.
## Берётся лучший из всех углов (минимум дистанции после скольжения), причём
## цель обязана влезать в радиус захвата рывка (BOAR_DASH_RANGE 72 px).
func _t46_corner(rows: Array) -> Dictionary:
	var ex: Array = [world.player.get_rid()]
	var space: PhysicsDirectSpaceState2D = world.player.get_world_2d().direct_space_state
	var best: Dictionary = {}
	var best_d := 1e9
	for y in range(2, rows.size() - 1):
		var row := String(rows[y])
		for x in range(2, row.length() - 3):
			if _t46_fl(rows, Vector2i(x, y)):
				continue
			var run := 0
			while x + run < row.length() and not _t46_fl(rows, Vector2i(x + run, y)):
				run += 1
			if run < 2 or run > 4:
				continue
			var hero := Vector2i(x - 1, y - 1)
			var tg := Vector2i(x + run, y)
			if not _t46_fl(rows, hero) or not _t46_fl(rows, tg):
				continue
			var above_ok := true
			for i in range(x - 1, x + run + 1):
				if not _t46_fl(rows, Vector2i(i, y - 1)):
					above_ok = false
			if not above_ok:
				continue
			var a := _t46_cw(hero)
			var b := _t46_cw(tg)
			if a.distance_to(b) > 64.0:
				continue  # цель вне радиуса захвата рывка (72 px) — каст не догонит
			var hit: Dictionary = space.intersect_ray(
				PhysicsRayQueryParameters2D.create(a, b, 2, ex))
			if hit.is_empty():
				continue
			var nrm: Vector2 = hit.get("normal", Vector2.ZERO)
			if absf(nrm.y) < 0.5:
				continue
			var dd: float = a.distance_to(hit["position"])
			var contact: Vector2 = a + (b - a).normalized() * maxf(0.0, dd - 5.0)
			if contact.y >= b.y:
				continue
			var old_d: float = contact.distance_to(b)
			if old_d <= T46_THR:
				continue  # прежний «упор» и так бил бы: пин ничего не доказывает
			var slide: Vector2 = _t46_slide(a, contact, nrm, b)
			var slide_d: float = slide.distance_to(b)
			if slide_d >= best_d:
				continue
			best_d = slide_d
			best = {"hero": hero, "target": tg, "old": contact, "old_d": old_d,
				"slide": slide, "slide_d": slide_d, "range": a.distance_to(b)}
	return best

## Тонкая стена (1 клетка) с обходом вбок: герой и моб на одной линии по разные
## стороны, перпендикулярно стене. На старой механике моб с такой геометрией не
## двигался вовсе (скорость перпендикулярна стене, move_and_slide гасит её).
func _t46_thin(rows: Array) -> Dictionary:
	for y in range(2, rows.size() - 2):
		var row := String(rows[y])
		for x in range(2, row.length() - 2):
			var w := Vector2i(x, y)
			if _t46_fl(rows, w):
				continue
			var h := Vector2i(x - 1, y)
			var m := Vector2i(x + 1, y)
			if not _t46_fl(rows, h) or not _t46_fl(rows, m):
				continue
			var bypass := false
			for s in [-1, 1]:
				if _t46_fl(rows, Vector2i(x, y + s)) and _t46_fl(rows, Vector2i(x - 1, y + s)):
					bypass = true
			if not bypass:
				continue
			if _t46_ray(_t46_cw(h), _t46_cw(m)).is_empty():
				continue
			return {"hero": h, "mob": m}
	return {}

## Карман для пина памяти: моб в проходимом столбце, над ним пол (герой виден),
## западнее — две стены подряд; герой переносится на (x-2, y): дистанция та же,
## прямой видимости нет, и обратно из кармана её тоже нет (обе клетки — скала).
func _t46_mem(rows: Array) -> Dictionary:
	for y in range(2, rows.size() - 2):
		var row := String(rows[y])
		for x in range(3, row.length() - 2):
			var m := Vector2i(x, y)
			if not _t46_fl(rows, m):
				continue
			var s := Vector2i(x, y - 1)
			var h2 := Vector2i(x - 2, y)
			if not _t46_fl(rows, s) or not _t46_fl(rows, h2):
				continue
			if _t46_fl(rows, Vector2i(x - 1, y)) or _t46_fl(rows, Vector2i(x - 1, y - 1)):
				continue
			if not _t46_ray(_t46_cw(m), _t46_cw(s)).is_empty():
				continue
			if _t46_ray(_t46_cw(m), _t46_cw(h2)).is_empty():
				continue
			return {"mob": m, "seen": s, "hero": h2}
	return {}

## Глухая скала: все 8 соседей — стены, значит любой из 7 «усов» упирается в
## камень в пределах PROBE 26 px. Это и есть тупик контракта steer() -> ZERO.
func _t46_pocket(rows: Array) -> Vector2i:
	for y in range(1, rows.size() - 1):
		var row := String(rows[y])
		for x in range(1, row.length() - 1):
			if _t46_fl(rows, Vector2i(x, y)):
				continue
			var sealed := true
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if _t46_fl(rows, Vector2i(x + dx, y + dy)):
						sealed = false
			if sealed:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## (1) Рывок вепря у выпуклой стены: упор не гасит рывок, скольжение доводит до
## мили, удар и оглушение засчитаны ПОСЛЕ приземления.
func _t46_dash(rows: Array) -> void:
	var p: Node2D = world.player
	var corner := _t46_corner(rows)
	if corner.is_empty():
		chk(false, "t46: в пещере сида 42 не нашлось выпуклого угла под рывок — пин нечего строить")
		return
	var slide_d: float = float(corner["slide_d"])
	if slide_d > 13.0:
		chk(false, "t46: лучший угол пещеры доводит скольжение лишь до %.1f px от цели (нужно <= 13, чтобы приземление было в мили)" % slide_d)
		return
	var hcell: Vector2i = corner["hero"]
	var tcell: Vector2i = corner["target"]
	p.global_position = _t46_cw(hcell)
	await _frames(2)
	var mob := _t46_mob(tcell, false)
	await _frames(1)
	var tw: Vector2 = mob.global_position
	var hp0 := int(mob.get("hp"))
	var tgt: Node2D = p.call("_dash_target")
	chk(tgt == mob, "t46: рывок берёт целью мишень за стеной (радиус 72 px, d=%.0f)" % p.global_position.distance_to(tw))
	p.set_physics_process(false)
	p.call("_boar_dash", mob)
	var midv: Variant = p.get("boar_mid")
	var destv: Variant = p.get("boar_dest")
	var mid_ok: bool = midv is Vector2 and (midv as Vector2) != Vector2.ZERO
	var dest_d: float = -1.0
	if destv is Vector2:
		dest_d = (destv as Vector2).distance_to(tw)
	chk(mid_ok, "t46: упор в стену не гасит рывок — маршрут со скольжением (boar_mid задан)")
	chk(dest_d >= 0.0 and dest_d <= T46_THR, "t46: скольжение доводит до мили: dest..цель = %.1f px (порог %.0f)" % [dest_d, T46_THR])
	var old_d: float = float(corner["old_d"])
	chk(old_d > T46_THR, "t46-до: прежний «упор» оставлял цель в %.1f px (> %.0f) — на старой механике пин краснеет" % [old_d, T46_THR])
	p.set_physics_process(true)
	await _frames(12)
	var hp1 := int(mob.get("hp"))
	var land_d: float = p.global_position.distance_to(tw)
	chk(float(p.get("boar_t")) == 0.0, "t46: рывок завершён (boar_t=0) за 9 кадров полёта")
	chk(land_d <= T46_THR, "t46: герой приземлился в мили от цели (%.1f px)" % land_d)
	chk(hp1 < hp0, "t46: удар после приземления засчитан (hp %d -> %d)" % [hp0, hp1])
	chk(float(mob.get("freeze_t")) > 0.0, "t46: цель оглушена рывком (freeze_t=%.2f)" % float(mob.get("freeze_t")))
	mob.queue_free()
	await _frames(2)

## (2) «Усы»: за выпуклой стеной моб не дрожит, а обходит камень; в глухом
## камне — встаёт (Vector2.ZERO), а не пиляет стену.
func _t46_whiskers(rows: Array) -> void:
	var AV = load("res://scripts/mob_avoid.gd")
	chk(AV != null, "t46: mob_avoid.gd («усы») подключён")
	if AV == null:
		return
	var p: Node2D = world.player
	var pair := _t46_thin(rows)
	if pair.is_empty():
		chk(false, "t46: в пещере сида 42 не нашлось тонкой стены с обходом — пину негде жить")
		return
	var mcell: Vector2i = pair["mob"]
	p.global_position = _t46_cw(pair["hero"])
	await _frames(2)
	var mob := _t46_mob(mcell, true)
	await _frames(2)
	var seen: Vector2 = p.global_position
	# тестовые таймеры: память удлинена, чтобы весь прогон (1.83 с) был в ветке
	# погони и распад SEE_MEMORY не портил геометрию обхода
	mob.set("_seen_pos", seen)
	mob.set("_seen_t", 5.0)
	chk(not AV.los(mob, seen), "t46: геометрия — прямой видимости через камень нет (AVOID.los)")
	var want: Vector2 = (seen - mob.global_position).normalized() * 40.0
	var steered: Vector2 = AV.steer(mob, want)
	var ang := rad_to_deg(acos(clampf(steered.normalized().dot(want.normalized()), -1.0, 1.0)))
	chk(ang > 5.0 and absf(steered.length() - want.length()) < 0.5,
		"t46: усь отклоняет вектор от камня на %.0f°, величина скорости та же (%.0f)" % [ang, steered.length()])
	var path := 0.0
	var prev: Vector2 = mob.global_position
	var d0: float = mob.global_position.distance_to(seen)
	for i in 110:
		await _frames(1)
		path += prev.distance_to(mob.global_position)
		prev = mob.global_position
	var d1: float = mob.global_position.distance_to(seen)
	chk(path >= 25.0, "t46: моб за камнем обходит его, а не дрожит: путь %.0f px за 1.83 с (на старой механике 0)" % path)
	chk(d1 <= d0 - 8.0, "t46: обход даёт сближение с последним видимым местом: %.1f -> %.1f px" % [d0, d1])
	chk(_t46_fl(rows, _t46_cell(mob.global_position)),
		"t46: моб не прошёл сквозь камень — остался в проходимой клетке %s" % str(_t46_cell(mob.global_position)))
	mob.queue_free()
	# тупик: все 7 усов в камень -> встать, а не дрожать
	var pk := _t46_pocket(rows)
	chk(pk.x >= 0, "t46: в сетке пещеры есть глухая скала (все 7 усов в камень) %s" % str(pk))
	if pk.x < 0:
		return
	var near := _t46_fl_near(rows, pk)
	if near.x < 0:
		chk(false, "t46: у глухой скалы нет проходимой клетки рядом — тупик не проверить")
		return
	p.global_position = _t46_cw(near)
	var trapped := _t46_mob(pk, true)
	await _frames(2)
	trapped.set("_seen_pos", p.global_position)
	trapped.set("_seen_t", 5.0)
	var at: Vector2 = trapped.global_position
	await _frames(5)
	var spd: float = float((trapped.get("velocity") as Vector2).length())
	chk(spd < 0.5, "t46: в тупике моб встаёт: скорость %.2f (усь-контракт Vector2.ZERO)" % spd)
	chk(trapped.global_position.distance_to(at) < 0.5, "t46: и не дрожит на месте (сместился на %.2f px)" % trapped.global_position.distance_to(at))
	trapped.queue_free()
	await _frames(2)

## Проходимая клетка рядом с произвольной (для запуска тупика).
func _t46_fl_near(rows: Array, c: Vector2i) -> Vector2i:
	for dy in [-2, -1, 0, 1, 2]:
		for dx in [-2, -1, 0, 1, 2]:
			var n := Vector2i(c.x + dx, c.y + dy)
			if _t46_fl(rows, n):
				var d: float = _t46_cw(c).distance_to(_t46_cw(n))
				if d < T46_CHASE:
					return n
	return Vector2i(-1, -1)

## (3) Агро: без прямой видимости погоня не стартует; после 1.6 с без видимости
## моб уходит к последнему видимому месту и перестаёт гнаться.
func _t46_aggro(rows: Array) -> void:
	var p: Node2D = world.player
	# (а) нет LOS -> нет агро
	var pair := _t46_thin(rows)
	if pair.is_empty():
		chk(false, "t46: (агро) не нашлось тонкой стены — пину LOS негде жить")
	else:
		p.global_position = _t46_cw(pair["hero"])
		await _frames(2)
		var mob := _t46_mob(pair["mob"], true)
		var d: float = p.global_position.distance_to(mob.global_position)
		await _frames(45)
		var tv: Variant = mob.get("_seen_t")
		var pv: Variant = mob.get("_seen_pos")
		var setpos: bool = pv is Vector2 and (pv as Vector2) != Vector2.ZERO
		var pv_s := "не задан"
		if setpos:
			pv_s = str(pv)
		chk(tv != null and float(tv) == 0.0 and not setpos,
			"t46: моб в %.0f px за стеной не агдится: память не заведена (_seen_t %s, last-seen %s)" % [d, str(tv), pv_s])
		var spd: float = float((mob.get("velocity") as Vector2).length())
		chk(spd <= T46_WANDER + 0.5, "t46: ...и не летит в стену: скорость %.1f ≤ %.0f (блуждание)" % [spd, T46_WANDER])
		mob.queue_free()
		await _frames(2)
	# (б) потерял видимость -> догоняет последним видимым местом, потом останавливается
	var mem := _t46_mem(rows)
	if mem.is_empty():
		chk(false, "t46: не найден карман для пина памяти SEE_MEMORY")
		return
	var mcell: Vector2i = mem["mob"]
	var seen: Vector2 = _t46_cw(mem["seen"])
	p.global_position = seen
	await _frames(2)
	var mob2 := _t46_mob(mcell, true)
	await _frames(8)
	var tv2v: Variant = mob2.get("_seen_t")
	var svv: Variant = mob2.get("_seen_pos")
	if tv2v == null or not (svv is Vector2):
		chk(false, "t46: у слайма нет памяти (_seen_t/_seen_pos) — фикс агро не на месте")
		mob2.queue_free()
		return
	var tv2: float = float(tv2v)
	var sv: Vector2 = svv
	chk(tv2 > 1.4 and sv.distance_to(seen) < 0.01,
		"t46: при прямой видимости память заведена (_seen_t=%.2f, last-seen = герой)" % tv2)
	p.global_position = _t46_cw(mem["hero"])
	# направление мерим ДО прихода к метке (16 px = ~24 кадра): у самой метки
	# направление к last-seen вырождается, там мерить «куда смотрит» бессмысленно
	await _frames(6)
	var v: Vector2 = mob2.get("velocity")
	var d_to_seen: float = mob2.global_position.distance_to(sv)
	if d_to_seen < 4.0:
		chk(false, "t46: моб уже у метки через 6 кадров (%.1f px) — направление не померить" % d_to_seen)
	else:
		var to_seen: Vector2 = (sv - mob2.global_position).normalized()
		var to_hero: Vector2 = (p.global_position - mob2.global_position).normalized()
		chk(v.length() > 1.0 and v.normalized().dot(to_seen) > 0.9,
			"t46: телепортированного за угол моб догоняет последним видимым местом (dot=%.2f, %.1f px до метки)" % [v.normalized().dot(to_seen), d_to_seen])
		chk(v.normalized().dot(to_hero) < 0.8,
			"t46: ...а не идёт сквозь стену на самого героя (dot=%.2f)" % v.normalized().dot(to_hero))
	await _frames(T46_SEE_FRAMES + 40)
	var tv3: float = float(mob2.get("_seen_t"))
	var spd2: float = float((mob2.get("velocity") as Vector2).length())
	var dseen: float = mob2.global_position.distance_to(sv)
	chk(tv3 <= 0.0, "t46: за 1.6 с без видимости память погасла (_seen_t=%.2f)" % tv3)
	chk(dseen <= 12.0, "t46: моб ушёл к последнему видимому месту (%.1f px)" % dseen)
	chk(spd2 <= T46_WANDER + 1.0, "t46: дальше не гонится: скорость %.1f ≤ %.0f (перешёл к блужданию)" % [spd2, T46_WANDER])
	mob2.queue_free()
	await _frames(2)

## (4) Возврат из пещеры после резюма: точка возврата — арка входа, а не старт.
func _t46_return() -> void:
	GameState.heal(999)  # пины выше могли поцарапать героя — резюм честный
	# свежий резюм: world-кэш точек возврата пуст (так и есть при загрузке сейва)
	world.village_return_pos = Vector2.INF
	world.ashen_return_pos = Vector2.INF
	var arch: Vector2 = world.tile_to_world(world.CAVE_ENTRANCE_TILE)
	var start: Vector2 = world.tile_to_world(world.spawn_tile)
	_c37_write_save(true, C37_STUCK.x, C37_STUCK.y)  # сейв «в пещере», позиция в скале
	world.do_quickload()
	await _frames(2)
	chk(world.village_return_pos == arch,
		"t46: резюм в пещере — точка возврата = арка входа %s, а не спавн %s" % [str(arch), str(start)])
	world.apply_zone(false)  # штатный выход из пещеры (легаси-API world.gd)
	chk(world.player.global_position == arch,
		"t46: поднялся из пещеры — герой у арки входа (%s)" % str(world.player.global_position))
	chk(world.player.global_position != start,
		"t46-до: на старой механике кэш был INF и герой падал на старт %s" % str(start))
	chk(bool(world.call("_village_walkable", world.CAVE_ENTRANCE_TILE)),
		"t46: арочный тайл возврата проходим (герой не в стене)")
	# то же для Пепелища: выходим к портальному камню «A»
	world.village_return_pos = Vector2.INF
	world.ashen_return_pos = Vector2.INF
	_c37_write_save(false, 8.0, 9608.0)  # сейв «в Пепелище», позиция в скале
	world.do_quickload()
	await _frames(2)
	var agate: Vector2 = world.tile_to_world(world.ASHEN_ENTRANCE_TILE)
	chk(world.ashen_return_pos == agate,
		"t46: резюм в Пепелище — точка возврата = портальный камень %s" % str(agate))
	world.apply_zone(false)
	chk(world.player.global_position == agate,
		"t46: выход из Пепелища — герой у портального камня (%s)" % str(world.player.global_position))

func _t46() -> void:
	world.apply_area("cave", true)
	await _frames(4)
	_clear_enemies(world.cave_zone)
	await _frames(3)
	var rows: Array = world.dungeon_zone.map_rows
	var p: Node2D = world.player
	chk(p != null and world.dungeon_zone != null, "t46: пещера сида 42 активна для пинов физики")
	# каждую секцию ждём до конца: внутри await-кадры, без await они бы повисли
	# и процесс завершился бы раньше проверок (тот же порядок, что у _t12/_t37)
	await _t46_dash(rows)
	await _t46_whiskers(rows)
	await _t46_aggro(rows)
	await _t46_return()
	var free_lights := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and world.cave_zone.is_ancestor_of(e as Node):
			free_lights += 1
	print("qa_lp t46: юзер-фиксы 16.11 запинены: рывок у стены, усы (обход + тупик), агро по LOS + память %.1f с, возврат к арке (пещера + Пепелище); стендовых мобов в пещере осталось %d" % [float(T46_SEE_FRAMES) / 60.0, free_lights])
