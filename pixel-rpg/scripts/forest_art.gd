class_name ForestArt
extends RefCounted
## w3int (вердикт пользователя «берём» по листу «Лес v1»): лес в игре.
##
## Единственный источник арта — КОД-ГЕН атласы, запечённые утверждённым
## генератором res://tools_art/sheet_forest_v1.gd (режим bake):
##   assets/forest/forest_floor_v1.png  — пол 16 px (FFLR/FFLR2/FEDGE_S/FEDGE_E),
##   assets/forest/forest_props_v1.png  — кроны/кусты/декор, кадры свая A/B/C,
##   data/forest_regions.json           — манифест регионов (единственная
##   истина раскладки; REGIONS ниже — его зеркало, равенство пинит qa _t44).
##
## Инварианты (пинит qa_lp _t44):
##  - сетка map_village.json, CHAR_TO_TILE, BLOCK_SHAPES, POI — бит-в-бит:
##    лесные клетки t/T/r остаются СЕТКОЙ как были, меняется только визуал
##    (пол — source2 тайлмапа, кроны/декор — спрайты со стопой, физика — ноль
##    новых тел: коллайдеры живут в сетке, невидимых стен не добавляем);
##  - source0 (легаси tiles.png) в дереве/лесу не рисует ни одной клетки
##    (счётчик харнесса c26 785 -> 0); сам tiles.png и фолбэк-ветки
##    ResourceLoader.exists живы — удаление файла финалом w4;
##  - глубина — общая шкала стоп V-01: z = fposmod(Y_стопы, 4800); кроны —
##    в реестр _ys_canopies (дим над героем ≥50% бокса), подлесок — в
##    _ys_props_dim (порог 40%);
##  - свай — чистая функция времени (прецедент c7/c9): кадр =
##    int(t/SWAY_T + фаза_хэш(клетки)) % 3 (A покой / B −1px / C +1px),
##    T = 0.5 с как на листе; ни одного физ-узла, тайлмап не мутируется.

const ATLAS_PATH := "res://assets/forest/forest_props_v1.png"
const FLOOR_PATH := "res://assets/forest/forest_floor_v1.png"
const MANIFEST_PATH := "res://data/forest_regions.json"
const FLOOR_SIZE := Vector2i(64, 16)

## Пол: слоты атласа FLOOR_PATH (порядок bake-генератора).
const FLOOR_SLOTS := {"FFLR": 0, "FFLR2": 1, "FEDGE_S": 2, "FEDGE_E": 3}
## Лесные символы сетки (CHAR_TO_TILE не трогаем — только визуал).
const FLOOR_CHARS := {"t": true, "T": true, "r": true}

const SWAY_T := 0.5  # с, как на утверждённом листе (forest_regions.json T_s)

## Обрезка нижней кромки trim (пиксели ниже стопы кадра) — стопный якорь §4.
const FOOT_CUT := {"BUSH": 1, "BUSH2": 1}

## Зеркало data/forest_regions.json (qa _t44 сверяет побайтово). g24a (t6):
## + PINE_T2P/OAK_TP/OAK_TP_B/OAK_TP_C (проходимые наклонные деревья — только
## 'T'-просветы) и STONE_MW/STONES_FW (MASS-валуны, приземный силуэт до краёв
## коллайдера). Порядок/координаты — ре-байк sheet_forest_v1.gd bake.
const REGIONS := {
	"PINE_T1": Rect2(0, 0, 29, 48),
	"PINE_T2": Rect2(31, 0, 21, 34),
	"PINE_T2P": Rect2(100, 0, 20, 34),
	"OAK_T": Rect2(54, 0, 44, 43),
	"OAK_TP": Rect2(0, 50, 44, 43),
	"BUSH": Rect2(46, 50, 13, 10),
	"BUSH2": Rect2(61, 50, 11, 7),
	"STUMP_F": Rect2(74, 50, 11, 8),
	"STUMP_F2": Rect2(87, 50, 8, 6),
	"STONES_F": Rect2(97, 50, 14, 9),
	"STONE_M": Rect2(113, 50, 9, 6),
	"STONE_MW": Rect2(124, 50, 16, 12),
	"STONES_FW": Rect2(142, 50, 16, 12),
	"SHROOM1": Rect2(0, 95, 7, 6),
	"SHROOM2": Rect2(9, 95, 10, 6),
	"FERN": Rect2(21, 95, 13, 8),
	"FERN2": Rect2(36, 95, 7, 6),
	"PINE_T1_B": Rect2(45, 95, 29, 48),
	"PINE_T1_C": Rect2(76, 95, 29, 48),
	"OAK_T_B": Rect2(107, 95, 44, 43),
	"OAK_T_C": Rect2(0, 145, 43, 43),
	"OAK_TP_B": Rect2(45, 145, 44, 43),
	"OAK_TP_C": Rect2(91, 145, 43, 43),
	"BUSH_B": Rect2(136, 145, 13, 10),
	"BUSH_C": Rect2(0, 190, 12, 10),
	"BUSH2_B": Rect2(14, 190, 11, 7),
	"BUSH2_C": Rect2(27, 190, 10, 7),
}
## Ключи с качающимися кадрами (B/C); A — базовый кадр без суффикса.
const SWAY_KEYS := {"PINE_T1": true, "OAK_T": true, "OAK_TP": true, "BUSH": true, "BUSH2": true}

## g22 (t68, вердикт 17.11 «почти полная прозрачность вокруг персонажа»):
## ствол = нижние 8 px кадра дерева. Крона в ореоле/под нависанием димится
## (world.gd), а полоса ствола остаётся видимой подсказкой «сюда не войти».
## Полосы НЕ множат сцену: вне ореола кроны непрозрачны и ствол виден самим
## кадром — полоса нужна только у героя. TrunkPool — пул из TRUNK_POOL_CAP
## спрайтов, каждый кадр переставляемый на ближайшие деревья (радиус
## TRUNK_PULL_R: ореол 150 + запас); z полосы = z её дерева (V-01 честный,
## привязка абсолютным z, а не порядком детей). ART-ЗАМЕЧАНИЕ: внутри пузыря
## ствол северного дерева может коснуться через полупрозрачную крону южного —
## это и есть семантика пузыря (наведённая прозрачность), вне пузыря полос
## нет вовсе.
const TRUNK_STRIP_H := 8
const TRUNK_POOL_CAP := 300
const TRUNK_PULL_R := 165.0
## g22 читаемость глухих просветов (диагноз t67: 52/52 упоров выглядят проходом),
## g24a (t6) доводка: там, где две СОСЕДНИЕ по горизонтали блокирующие клетки
## (t/r) и хотя бы одна — дерево, визуальный просвет между стволами закрывается
## детерминированным «ковриком корней» из тёмных тонов того же материала
## (BARK[2]/BARK[3], PixelPalette — новых цветов ноль). Коврик 14×8 закрывает
## ВСЮ измеряемую приземную полосу 8..15 пары (g22-коврик 10×6 оставлял
## волосы-щели w3..13 над верхним краем — диагноз t5 P1). Пары р+р закрывает
## не коврик, а MASS-основание валунов (STONE_MW/STONES_FW рисуются до краёв
## коллайдера — P0-2). Физика не меняется: паттерн рисует строго внутри пары
## глухих клеток; проходы между группами (проходимые клетки) не закрашиваются
## никогда — правило построено на соседстве глухих. Маты рисуются ПО ОДНОМУ
## CanvasItem на ряд (RootBoard, _draw по строке, статичен) — сотни квадов не
## плодят элементов сцены; z ряда = стопный z границы (V-01), с однострочными
## деревьями вничью мат строго в бесствольных колонках — перекрытия нет.
const ROOT_MAT_W := 14
const ROOT_MAT_H := 8
const ROOT_MATS := [
	["11111111111111",
	 "12222222222221",
	 "12122222221121",
	 "12222111122221",
	 "12111222222121",
	 "12222222222221",
	 "12212222222121",
	 "11111111111111"],
	["11111111111111",
	 "12222222222221",
	 "12211222211221",
	 "12222211222221",
	 "12122222222121",
	 "12222111122221",
	 "12222222222221",
	 "11111111111111"],
]

## g24a (t5 M2/M4): «корневой пол» MASS-клетки дерева — 16×8 под всю приземную
## полосу глухой клетки-массы (коллайдер 16×16 => земля под деревом мертва,
## невидимых заблокированных px и волосков-щелей между юбками соседних крон
## оставаться не должно: тот же закон, что wide-основание валуна P0-2, только
## для дерева). Рисуется ДО арты ряда (z доски = линия ряда - 1): стволы и
## юбки остаются поверх, корневой узор виден ровно в пустых ячейках земли.
## Только BARK[2]/BARK[3] — новых цветов ноль, детермин (хэш клетки).
const ROOT_FLOOR_W := 16
const ROOT_FLOORS := [
	["1111111111111111",
	 "1222222222222221",
	 "1212222112211221",
	 "1222111221122221",
	 "1211222221221221",
	 "1222221122221121",
	 "1221222212212221",
	 "1111111111111111"],
	["1111111111111111",
	 "1222222222222221",
	 "1221122222112221",
	 "1222221112222121",
	 "1212222222122221",
	 "1222211222211121",
	 "1222122212222221",
	 "1111111111111111"],
]


static func available() -> bool:
	return ResourceLoader.exists(ATLAS_PATH) and ResourceLoader.exists(FLOOR_PATH)


static func _char_at(world, x: int, y: int) -> String:
	var rows: Array = world.map_rows
	if y < 0 or y >= rows.size():
		return "t"  # за карту «лес» — кромка не рисуется наружу
	var row := String(rows[y])
	if x < 0 or x >= row.length():
		return "t"
	return row[x]


static func is_forest_char(ch: String) -> bool:
	return FLOOR_CHARS.has(ch)


## Слот пола лесной клетки: южная кромка (рядом не-лес) приоритетнее
## восточной; иначе вариант подстицы по хэшу клетки (детерминированно).
static func floor_slot(world, x: int, y: int) -> int:
	if not is_forest_char(_char_at(world, x + 1, y)) and not is_forest_char(_char_at(world, x, y + 1)):
		return int(FLOOR_SLOTS["FFLR"]) if CaveArt.frac(x, y, 3) < 0.5 else int(FLOOR_SLOTS["FFLR2"])
	if not is_forest_char(_char_at(world, x, y + 1)):
		return int(FLOOR_SLOTS["FEDGE_S"])
	if not is_forest_char(_char_at(world, x + 1, y)):
		return int(FLOOR_SLOTS["FEDGE_E"])
	return int(FLOOR_SLOTS["FFLR"]) if CaveArt.frac(x, y, 3) < 0.5 else int(FLOOR_SLOTS["FFLR2"])


static func load_atlas() -> Texture2D:
	return load(ATLAS_PATH)


static func _region(atlas: Texture2D, key: String) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = atlas
	at.region = REGIONS[key]
	at.filter_clip = true  # LINEAR-мир: не хватать пиксели соседей по атласу
	return at


## Спрайт с стопой (нижним краем) в foot (с поправкой FOOT_CUT).
static func _spr(parent: Node2D, atlas: Texture2D, key: String, foot: Vector2) -> Sprite2D:
	var at := _region(atlas, key)
	var spr := Sprite2D.new()
	spr.texture = at
	var cut := int(FOOT_CUT.get(key, 0))
	spr.position = Vector2(foot.x, foot.y - float(cut) - float(at.get_size().y) * 0.5)
	parent.add_child(spr)
	return spr


## Строит слой ForestV1: props (кроны/камни/подлесок) по сетке + overlay-свай.
static func build(world) -> Node2D:
	if not available():
		return null  # фолбэк: старый source0 остаётся визуалом (ветка жива)
	var layer := Node2D.new()
	layer.name = "ForestV1"
	world.village_zone.add_child(layer)
	var atlas := load_atlas()
	var sway_layer := ForestSwayLayer.new()
	sway_layer.name = "ForestSway"
	layer.add_child(sway_layer)
	# g22: пул полос стволов у героя (переставляемый, ограниченный) — вместо
	# идеи «полоса на каждое дерево»: +1700 статичных CanvasItem стоили кадру
	# +37 % (замер g22 A/B), пул из TRUNK_POOL_CAP — доли процента.
	var pool := TrunkPool.new()
	pool.name = "TrunkPool"
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length():
			var ch := row[x]
			var foot := Vector2(float(x) * 16.0 + 8.0, float(y + 1) * 16.0)
			if ch == "t":
				#blocking дерево: 62% полная ель, иначе средняя (хэш клетки)
				var key := "PINE_T1" if CaveArt.frac(x, y, 11) < 0.62 else "PINE_T2"
				_tree(world, layer, sway_layer, atlas, key, x, y, foot, pool, true)
			elif ch == "T":
				# проходимое дерево-просвет: 68% крона, иначе подлесок/поляна.
				# g24a (t5 P0-1 «двойники»): кроновые клетки рисуют ПРОХОДИМЫЕ
				# варианты (OAK_TP/PINE_T2P) — наклонный ствол у края клетки и
				# видимый проход у основания; побайтово совпадающих кадров с
				# глухими «t» не существует по построению. В пул полос стволов
				# (pool_ok=false) не регистрируются: полоса = знак «сюда не
				# войти», проходимому дереву она запрещена.
				var f := CaveArt.frac(x, y, 17)
				if f < 0.68:
					var key2 := "OAK_TP" if CaveArt.frac(x, y, 23) < 0.55 else "PINE_T2P"
					_tree(world, layer, sway_layer, atlas, key2, x, y, foot, pool, false)
				else:
					var u := CaveArt.frac(x, y, 29)
					var dk := ""
					if u < 0.16:
						dk = "BUSH" if CaveArt.frac(x, y, 31) < 0.6 else "BUSH2"
					elif u < 0.26:
						dk = "SHROOM1" if CaveArt.frac(x, y, 37) < 0.6 else "SHROOM2"
					elif u < 0.42:
						dk = "FERN" if CaveArt.frac(x, y, 41) < 0.6 else "FERN2"
					elif u < 0.45:
						dk = "STUMP_F" if CaveArt.frac(x, y, 43) < 0.5 else "STUMP_F2"
					if dk != "":
						var spr := _spr(layer, atlas, dk, foot)
						world._ys_prop(spr)
						world._ys_props_dim.append(spr)
						# g18 (вердикт 16.11 «траву в лесу не видно»): подлесок димится
						# не до 0.5, а до 0.8 — трава обязана читаться и под героем
						spr.set_meta("ys_dim_alpha", 0.8)
						if SWAY_KEYS.has(dk):
							sway_layer.items.append({
								"spr": spr, "a": _region(atlas, dk),
								"b": _region(atlas, dk + "_B"), "c": _region(atlas, dk + "_C"),
								"phase": absi(CaveArt.hash_xy(x, y)) % 3,
							})
			elif ch == "r":
				# валун: камушки леса (консервативный сеточный коллайдер как был).
				# g24a (t5 P0-2): MASS-клетка (правило массы t58 — есть глухой
				# сосед по стороне, коллайдер 16×16) получает wide-основание
				# STONE_MW/STONES_FW: приземная полоса клетки 6..15 закрыта
				# камнем до краёв коллайдера — невидимых заблокированных px 0,
				# шов соседних валунов закрыт осыпью. Одиночный «r» (силуэт
				# t54 11×10) остаётся мелким камнем: арта не шире коллайдера.
				var rk: String
				if world._block_mass(x, y):
					rk = "STONE_MW" if CaveArt.frac(x, y, 51) < 0.6 else "STONES_FW"
				else:
					rk = "STONE_M" if CaveArt.frac(x, y, 51) < 0.6 else "STONES_F"
				var rspr := _spr(layer, atlas, rk, foot)
				world._ys_prop(rspr)
	# g22 (t68) + g24a (t6): коврики корней в просветах глухих пар — по CanvasItem
	# на ряд (RootBoard). Правило детерминированное и консервативное: оба
	# соседа по горизонтали блокирующие (t/r) и хотя бы один — дерево ('t');
	# ковриком 14×8 закрыта вся приземная полоса 8..15 шва (t5 P1: старые 10×6
	# оставляли волосы-щели сверху). Пары р+р закрывает MASS-основание валунов.
	# Проходимые клетки (включая 'T'-просветы) в пару не попадают => настоящие
	# проходы не закрашиваются. Вариант/зеркало паттерна — хэш клетки (randi
	# нет).
	var root_tex := _root_textures()
	var boards := {}
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length() - 1:
			var a := String(row[x])
			var b := String(row[x + 1])
			var half := 0
			if _grid_solid(a) and _grid_solid(b):
				if a != "t" and b != "t":
					continue
			# g24a (t5 M4 ZERO «нарисованный просвет без физики»): стык глухого
			# 't'-дерева и проходимого 'T'-КРОНЫ (не подлеска) рисует волосок
			# щели на глухой стороне — центр героя туда не входит (коллайдер
			# ствола), но глаз читает «проход». Половинный коврик (8×8) кладётся
			# ТОЛЬКО на глухую клетку: проходимая земля 'T' не закрашивается.
			elif a == "t" and b == "T" and CaveArt.frac(x + 1, y, 17) < 0.68:
				half = 1
			elif a == "T" and b == "t" and CaveArt.frac(x, y, 17) < 0.68:
				half = 2
			else:
				continue
			var h := absi(CaveArt.hash_xy(x, y))
			var bd: RootBoard = boards.get(y, null)
			if bd == null:
				bd = RootBoard.new()
				bd.name = "Roots_r%d" % y
				bd.z_as_relative = false
				bd.z_index = int(round(fposmod(float((y + 1) * 16), 4800.0))) - 1
				layer.add_child(bd)
				boards[y] = bd
			var item := {
				"tex": root_tex[(h % 2) * 2 + ((0 if half > 0 else (h >> 8) % 2))],
				"pos": Vector2(float(x + 1) * 16.0, float(y + 1) * 16.0 - float(ROOT_MAT_H) * 0.5),
			}
			if half > 0:
				item["half"] = half
			bd.items.append(item)
			world._g22_gap_mats.append({"x": x, "y": y, "half": half})
	# g24a (t5 M2/M4): корневые полы MASS-клеток деревьев — см. ROOT_FLOORS.
	# Только масса (коллайдер 16×16): одиночные «t» с силуэтной физикой не
	# трогаем — между их «ног» проходит герой, и земля там живая.
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length():
			if String(row[x]) != "t":
				continue
			if not world._block_mass(x, y):
				continue
			var bd2: RootBoard = boards.get(y, null)
			if bd2 == null:
				bd2 = RootBoard.new()
				bd2.name = "Roots_r%d" % y
				bd2.z_as_relative = false
				bd2.z_index = int(round(fposmod(float((y + 1) * 16), 4800.0))) - 1
				layer.add_child(bd2)
				boards[y] = bd2
			var hf := absi(CaveArt.hash_xy(x, y))
			bd2.items.append({
				"tex": root_tex[4 + (hf % 2)],
				"pos": Vector2(float(x) * 16.0 + 8.0, float(y + 1) * 16.0 - float(ROOT_MAT_H) * 0.5),
			})
	layer.add_child(pool)
	return layer


static func _tree(world, layer: Node2D, sway_layer, atlas: Texture2D, key: String,
		x: int, y: int, foot: Vector2, pool = null, in_pool: bool = true) -> void:
	var spr := _spr(layer, atlas, key, foot)
	world._ys_prop(spr)
	world._ys_canopies.append(spr)
	# g22 (t68): ГЛУХОЕ дерево регистрируется в пуле полос стволов (полоса-спрайт
	# появляется только у героя — см. TrunkPool). svay-деревья несут фазу, чтобы
	# полоса брала ровно тот же кадр A/B/C, что кроны (ствол в кадре сдвинут
	# вместе с ним — картинка покадрово идентична «целому» дереву).
	# g24a (t5 P0-1): in_pool=false для проходимых 'T'-деревьев — полоса ствола
	# читается как «сюда не войти» и на проходимом дереве запрещена.
	if pool != null and in_pool:
		var e := {
			"x": foot.x, "y": foot.y - float(TRUNK_STRIP_H) * 0.5,
			"z": spr.z_index, "ph": -1,
		}
		if SWAY_KEYS.has(key):
			e["ph"] = absi(CaveArt.hash_xy(x, y)) % 3
			e["a"] = _strip_regions(atlas, key)[0]
			e["b"] = _strip_regions(atlas, key)[1]
			e["c"] = _strip_regions(atlas, key)[2]
		else:
			e["a"] = _strip_regions(atlas, key)[0]
		pool.trees.append(e)
	if SWAY_KEYS.has(key):
		sway_layer.items.append({
			"spr": spr, "a": _region(atlas, key),
			"b": _region(atlas, key + "_B"), "c": _region(atlas, key + "_C"),
			"phase": absi(CaveArt.hash_xy(x, y)) % 3,
		})


## Полосы A/B/C кадра key (кэш на процесс: AtlasTexture создаются один раз
## на ключ, пул переиспользует ссылки).
static var _strip_cache := {}


static func _strip_regions(atlas: Texture2D, key: String) -> Array:
	var ck := key + "|" + str(atlas.get_instance_id())
	if _strip_cache.has(ck):
		return _strip_cache[ck]
	var out: Array = []
	for k in [key, key + "_B", key + "_C"]:
		if k != key and not REGIONS.has(k):
			out.append(out[0])
			continue
		var reg: Rect2 = REGIONS[k]
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(reg.position.x, reg.position.y + reg.size.y - float(TRUNK_STRIP_H),
				reg.size.x, float(TRUNK_STRIP_H))
		at.filter_clip = true
		out.append(at)
	_strip_cache[ck] = out
	return out


class ForestSwayLayer:
	extends Node2D
	## Трёхфазное дискретное качание: кадр = int(t/SWAY_T + фаза_клетки) % 3
	## (паттерн c7 A_TORCH int(t/T)%2, расширенный до A/B/C с листа). Чистая
	## функция времени — накопления нет, физ-узлов нет.
	var items: Array = []

	func _process(_delta: float) -> void:
		var tt := float(Time.get_ticks_msec()) / 1000.0
		for it in items:
			var spr := it["spr"] as Sprite2D
			if spr == null or not is_instance_valid(spr):
				continue  # c37: реестры живут между пересборками — guard до присваивания
			var ti := int(tt / ForestArt.SWAY_T) + int(it["phase"])
			# g21b (t65, масштаб ×1,5): цель — ровно та же картинка, но присваивание
			# только при смене фазы. Дискретный кадр меняется раз в SWAY_T; в
			# остальные ~29 кадров повторная запись той же AtlasTexture — чистая
			# работа setter'а на ~1300 спрайтах. Поведение (пин inv c7: «каждая
			# куртина сменила кадр») не меняется.
			var want: Texture2D = it["a"] if ti % 3 == 0 else (it["b"] if ti % 3 == 1 else it["c"])
			if spr.texture != want:
				spr.texture = want


## Заблокированная по сетке клетка леса (масса t58): дерево или валун.
## 'T'-просвет проходим — в глухие пары не входит (настоящие проходы не
## закрашиваем).
static func _grid_solid(ch: String) -> bool:
	return ch == "t" or ch == "r"


## g22: запечённые текстури ковриков корней — 2 паттерна × прямое/зеркальное
## (индекс = pat*2+flip). Только тёмные тона BARK из PixelPalette — новых
## цветов ноль. Печатаются один раз, детермин.
static var _root_texs: Array = []


static func _root_textures() -> Array:
	if not _root_texs.is_empty():
		return _root_texs
	var pal := preload("res://scripts/pixel_palette.gd")
	var tones := {"1": pal.BARK[2], "2": pal.BARK[3]}
	for pat in ROOT_MATS:
		var im := Image.create(ROOT_MAT_W, ROOT_MAT_H, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		for ry in ROOT_MAT_H:
			var line := String(pat[ry])
			for rx in ROOT_MAT_W:
				var c := String(line[rx])
				if tones.has(c):
					im.set_pixel(rx, ry, tones[c])
		_root_texs.append(ImageTexture.create_from_image(im))
		var mir := im.duplicate()
		mir.flip_x()
		_root_texs.append(ImageTexture.create_from_image(mir))
	for fl in ROOT_FLOORS:
		var im := Image.create(ROOT_FLOOR_W, ROOT_MAT_H, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		for ry in ROOT_MAT_H:
			var line := String(fl[ry])
			for rx in ROOT_FLOOR_W:
				var c := String(line[rx])
				if tones.has(c):
					im.set_pixel(rx, ry, tones[c])
		_root_texs.append(ImageTexture.create_from_image(im))
	return _root_texs


class RootBoard:
	extends Node2D
	## g22: все коврики корней одного ряда — одним CanvasItem (_draw статичен,
	## перерисовки нет). g24a: z = стопная z границы ряда МИНУС 1 — коврики и
	## корневые полы рису ПОД артой своего ряда (стволы/юбки/камни поверх,
	## узор виден только в пустых ячейках земли), над полом и вне ореола дима.
	## item["half"]=1/2 — половинный коврик 8×8 ровно на глухую сторону
	## стыка t|T (левее/правее границы); цельные коврики глухих пар — без поля;
	## полы MASS-клеток — текстура 16×8 без поля half.
	var items: Array = []

	func _draw() -> void:
		for it in items:
			var t: Texture2D = it["tex"]
			var p: Vector2 = it["pos"]
			var half := int(it.get("half", 0))
			if half == 1:
				draw_texture_rect_region(t, Rect2(p.x - 8.0, p.y - 4.0, 8.0, 8.0),
						Rect2(Vector2.ZERO, Vector2(8.0, 8.0)))
			elif half == 2:
				draw_texture_rect_region(t, Rect2(p.x, p.y - 4.0, 8.0, 8.0),
						Rect2(Vector2(float(t.get_width()) - 8.0, 0.0), Vector2(8.0, 8.0)))
			else:
				draw_texture(t, p - Vector2(float(t.get_width()) * 0.5, float(t.get_height()) * 0.5))


class TrunkPool:
	extends Node2D
	## g22: ограниченный пул полос стволов. Каждый кадр деревья ближе
	## TRUNK_PULL_R получают полосу из пула (z = z дерева — честная глубина),
	## остальные полосы скрыты. Вне радиуса кроны непрозрачны (ствол и так
	## виден кадром) — полоса не нужна. Кадры A/B/C — та же чистая функция
	## времени, что у ForestSwayLayer (свай-деревья), статичные — только A.
	var trees: Array = []
	var pool: Array = []
	var _hero: Node2D = null

	func _ready() -> void:
		for i in ForestArt.TRUNK_POOL_CAP:
			var s := Sprite2D.new()
			s.visible = false
			s.z_as_relative = false
			add_child(s)
			pool.append(s)

	func _process(_delta: float) -> void:
		if _hero == null or not is_instance_valid(_hero):
			var g := get_tree().get_nodes_in_group("ys_hero")
			if g.is_empty():
				g = get_tree().get_nodes_in_group("player")
			if g.is_empty():
				return
			_hero = g[0] as Node2D
		var hp := _hero.global_position
		var tt := float(Time.get_ticks_msec()) / 1000.0
		var used := 0
		for t in trees:
			var dx := float(t["x"]) - hp.x
			var dy := float(t["y"]) - hp.y
			if dx * dx + dy * dy > ForestArt.TRUNK_PULL_R * ForestArt.TRUNK_PULL_R:
				continue
			if used >= pool.size():
				break
			var s: Sprite2D = pool[used]
			used += 1
			if not s.visible:
				s.visible = true
			s.position = Vector2(float(t["x"]), float(t["y"]))
			if int(s.z_index) != int(t["z"]):
				s.z_index = int(t["z"])
			var want: Texture2D = t["a"]
			if int(t["ph"]) >= 0:
				var ti := int(tt / ForestArt.SWAY_T) + int(t["ph"])
				want = t["a"] if ti % 3 == 0 else (t["b"] if ti % 3 == 1 else t["c"])
			if s.texture != want:
				s.texture = want
		for j in range(used, pool.size()):
			if (pool[j] as Sprite2D).visible:
				(pool[j] as Sprite2D).visible = false
