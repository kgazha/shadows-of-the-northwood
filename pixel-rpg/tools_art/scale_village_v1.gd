extends SceneTree
## g21b (t65, вердикт 17.11, OPEN_WORLD.md фаза 1): детерминированный
## генератор РАСШИРЕНИЯ карты деревни+леса 48×30 -> 59×37 (≈×1,516 площади).
##
## Запуск (из pixel-rpg):
##   godot --headless --script res://tools_art/scale_village_v1.gd
##
## Принципы (честность пересъёма пинов):
##  1. СТАРОЕ ЯДРО НЕ ДВИГАЕТСЯ: все POI/NPC/арки/колодец/каменоломни остаются
##     на своих тайлах. Правятся РОВНО 6 старых клеток-швов (проходы из старого
##     мира в новый), всё остальное ядро — байт-в-байт:
##       (46,20),(47,20) «t»->«d»  — дорога от арки A(45,20) продолжается на
##                                   восток, в новую «Поляну с камнями»;
##       (21,28),(22,28),(21,29),(22,29) «t»->«d» — южная тропа от вертикальной
##                                   дороги x=22 уходит в новый южный тракт.
##     (16-битные швы — два парных прохода по 2 клетки = 32 px >= 14 px.)
##  2. НОВЫЕ КЛЕТКИ — по тем же правилам сетки: алфавит леса ⊆ t,r,T,f,d,s;
##     валунные группы 2..3, рощи 3..6 (кроме структурных поясов — загон и
##     стены, они кластерно-сплошные по замыслу), проходы >= 2 клетки,
##     глухой пояс 2 клетки по новому внешнему краю (масса t58 => герметично).
##  3. СМЫСЛ новых территорий (без маркеров квестов):
##       — восток: «Поляна с камнями» (три валунных группы + куртины) через
##         дорогу от арки — площадка под будущую кузню/алтарь;
##       — юго-запад: «Загон-роща» — кольцо деревьев с воротами на восток,
##         внутри трава, деревья, валуны, трава-куртины (площадка загона);
##       — юго-восток: поляна-точка интереса с валунами и цветами у конца
##         южного тракта;
##       — новые травы: (11,33) в загоне, (42,34) на южной поляне (ресурс,
##         не маркер).
##  4. Детерминизм: НОЛЬ randi. Декор «f» в новых клетках ставит тот же
##     FNV-хэш клетки, что и рантайм (CaveArt.frac, salt 61) — вариант травы
##     и цветов на одной клетке никогда не конфликтует с рантайм-хэшами
##     (salt'ы рантайма 3,11,17,23,29,... — наш 61 уникален).
##  5. Формат файла сохраняется: JSON.stringify(data," ") как был, CRLF.
##     md5 результата = новый золотой пин (qa_lp T44_MAP_MD5), changelog —
##     в комментарии пина.

const MAP_PATH := "res://data/map_village.json"
const OUT_PATH := MAP_PATH
const SEED_NOTE := "структура = ручная маска (этот файл), декор = FNV(salt 61); сид структуры фиксирован вердиктом t65"

func _init() -> void:
	var raw := FileAccess.get_file_as_string(MAP_PATH)
	if raw == "":
		print("FAIL: карта не прочитана")
		quit(1)
		return
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		print("FAIL: JSON не читается")
		quit(1)
		return
	var grid: Array = data["grid"]
	if grid.size() != 30 or String(grid[0]).length() != 48:
		print("FAIL: ожидались 48x30, получено %dx%d" % [String(grid[0]).length(), grid.size()])
		quit(1)
		return

	# ── 1) шеcвы старых клеток (РОВНО 6, см. шапку) ─────────────────────────
	var seams: Array = [
		[46, 20, "d"], [47, 20, "d"],
		[21, 28, "d"], [22, 28, "d"], [21, 29, "d"], [22, 29, "d"],
	]
	for s in seams:
		var rowb := String(grid[int(s[1])])
		if rowb[int(s[0])] != "t":
			print("FAIL: шов (%d,%d) не «t», а «%s» — план карты уехал" % [int(s[0]), int(s[1]), rowb[int(s[0])]])
			quit(1)
			return
		grid[int(s[1])] = rowb.left(int(s[0])) + String(s[2]) + rowb.substr(int(s[0]) + 1)

	# ── 2) восточная полоса: хвосты 11 клеток к существующим строкам ───────
	# По умолчанию: внешние стены rows 0..14/27..29 — глухие «t».
	var tails: Array = []
	for y in 30:
		var cells := PackedStringArray()
		for x in range(48, 59):
			cells.append("t")
		tails.append(cells)
	# Восточная «Поляна с камнями»: ряды 15..26, колонки 48..58.
	# Стена-пояс: col48/col58 «t», rows 15/26 «t». Въезд — дорога с row20.
	# Интерьер rows 16..25 × cols 49..57 — луг «g» (поверх него маска ниже).
	for y in range(16, 26):
		for x in range(49, 58):
			tails[y][x - 48] = "g"
	var east: Dictionary = {
		# ряд: {col: символ} — всё вне списка остаётся «g» поляны или «t» стены.
		# Валунные группы (2..3) НЕ касаются древесного пояса ни по стороне
		# (правило inv3 «смешанных кластеров — ноль»): ряды 17..24, col 49..56.
		17: {53: "r", 54: "r"},                       # группа 1 (2)
		18: {51: "r", 52: "r"},                       # группа 2 (3) — L-кластер
		19: {51: "r"},
		20: {48: "d", 49: "d", 50: "d", 51: "d"},     # дорога от шва на восток
		21: {51: "d"},
		22: {49: "T", 50: "T", 51: "d", 52: "d", 53: "d"},
		23: {49: "T", 50: "T", 53: "d", 54: "r", 55: "r"},  # группа 3 (3)
		24: {54: "r"},
	}
	for yy in east.keys():
		for cc in (east[yy] as Dictionary).keys():
			tails[int(yy)][int(cc) - 48] = String((east[yy] as Dictionary)[cc])
	# «f»-куртины нового луга — детерминированный FNV(salt 61), в проходимых
	# клетках полосы (t/r не украшаем).
	for y in 30:
		for x in range(48, 59):
			if tails[y][x - 48] == "g" and _frac(x, y, 61) < 0.14:
				tails[y][x - 48] = "f"
	for y in 30:
		grid[y] = String(grid[y]) + "".join(tails[y])

	# ── 3) южная полоса: rows 30..36 × 59 колонок ───────────────────────────
	# По умолчанию rows 30..35 — луг «g» (col0/1/57/58 — пояс «t»), row36 —
	# глухой южный пояс. Полоса row30 — «берег» под старым поясом rows28-29:
	# она соединяет западный карман, тракт и восточный тупик в один компонент
	# (иначе за стеной загона возникли бы отрезанные карманы — inv13/BFS).
	var south: Array = []
	for y in 7:
		var cells := PackedStringArray()
		for x in 59:
			cells.append("t" if (y == 6 or x <= 1 or x >= 57) else "g")
		south.append(cells)
	# Юго-восточная стена L (соединена с восточным поясом above): cols 46..56
	# rows 30..35 — масса, карманов за ней нет и не бывает (row36 тоже пояс).
	for y in range(30, 36):
		for x in range(46, 57):
			south[y - 30][x] = "t"
	# Южный тракт: от шва (21..22,28/29) вниз и на восток до южной поляны.
	for y in range(30, 33):
		south[y - 30][21] = "d"
		south[y - 30][22] = "d"
	for x in range(21, 46):
		south[3][x] = "d"
	# «Загон-роща»: периметр rows 31..35 × cols 5..18 «t», ворота в восточной
	# стене (18,32),(18,33), interior — трава с деревьями/валунами.
	for x in range(5, 19):
		south[1][x] = "t"
		south[5][x] = "t"
	for y in range(31, 36):
		south[y - 30][5] = "t"
		south[y - 30][18] = "t"
	south[2][18] = "g"  # ворота 2 клетки
	south[3][18] = "d"
	south[3][19] = "d"  # подъезд к воротам от тракта
	south[3][20] = "d"
	# внутри загона: деревья (проходимые «T»), валуны 2 — в СРЕДНЕМ ряду
	#interior (row33): верхний/нижний ряды загона смежны со стеной «t», валун
	# там слился бы с деревом в смешанный кластер (правило inv3).
	south[2][9] = "T"
	south[2][10] = "T"
	south[3][9] = "T"
	south[3][13] = "r"
	south[3][14] = "r"
	# Юго-восточная поляна interest: валуны 3 у конца тракта
	south[1][38] = "r"
	south[1][39] = "r"
	south[2][39] = "r"
	# Деревные кластеры-заполнители (3 клетки, проходы >=2):
	var fillers: Array = [
		[[24, 31], [25, 31], [24, 32]],   # между прогоном и трактом
		[[26, 34], [27, 34], [26, 35]],   # южнее тракта
		[[31, 31], [32, 31], [32, 32]],   # восточнее прогонов
		[[40, 34], [41, 34], [41, 35]],   # на поляне interest
	]
	for f in fillers:
		for c in f:
			south[int(c[1]) - 30][int(c[0])] = "t"
	# «f»-декор южных лугов тем же FNV(salt 61)
	for y in range(30, 36):
		for x in range(2, 46):
			if south[y - 30][x] == "g" and _frac(x, y, 61) < 0.12:
				south[y - 30][x] = "f"
	for y in 7:
		grid.append("".join(south[y]))

	data["width"] = 59
	data["height"] = 37

	# ── 4) новые травы (ресурс, не маркер) — в конец списка, старые не тронуты
	var herbs: Array = data["herbs"]
	herbs.append([11, 33])
	herbs.append([44, 32])

	# ── 5) запись в прежнем формате (1-пробельный отступ, CRLF) ─────────────
	var out := JSON.stringify(data, " ")
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(out.replace("\n", "\r\n"))
	f.flush()
	f = null

	# ── 6) пересчёт md5 и сводка (для пинов) ────────────────────────────────
	var bytes := FileAccess.get_file_as_bytes(OUT_PATH)
	var md5 := ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	md5 = ctx.finish().hex_encode()
	var w2 := String(grid[0]).length()
	var forest := 0
	var t := 0
	var r := 0
	for rowv in grid:
		for chx in String(rowv):
			if chx == "t":
				forest += 1
				t += 1
			elif chx == "T":
				forest += 1
			elif chx == "r":
				forest += 1
				r += 1
			elif chx == "f":
				pass
	print("OK: %dx%d (площадь %d, x%.3f)" % [w2, grid.size(), w2 * grid.size(), float(w2 * grid.size()) / 1440.0])
	print("md5=%s" % md5)
	print("лесные клетки (t+T+r) = %d  [t=%d r=%d]" % [forest, t, r])
	print("СЕЕД: %s" % SEED_NOTE)
	for y in grid.size():
		print("%02d %s" % [y, String(grid[y])])
	quit(0)

## FNV-1a хэш клетки в [0,1) — тот же рецепт, что CaveArt.frac/hash_xy.
func _frac(x: int, y: int, salt: int) -> float:
	var h := 2166136261
	for b in [x & 0xFF, (x >> 8) & 0xFF, y & 0xFF, (y >> 8) & 0xFF, salt & 0xFF, (salt >> 8) & 0xFF]:
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return float(h & 0xFFFFFF) / float(0x1000000)
