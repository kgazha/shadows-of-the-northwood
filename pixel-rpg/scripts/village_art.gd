class_name VillageArt
extends RefCounted
## t54: постройка деревни «Деревня v4» по вердикту пользователя «внедряем в игру».
##
## Единственный источник арта — КОД-ГЕН атласы листа v4 (docs/PIXEL_STYLE.md),
## запечённые инструментом res://tools_art/sheet_village.gd (режим bake):
##   assets/village/village_v4.png        — пропы (изба/колодец/костёр/пепел/указатель),
##   assets/village/village_floor_v4.png  — пол 16 px (трава 2 варианта, цветы, тропа, вода).
## Никаких сгенерированных картинок (закон 13.11). GEOMETRY REGIONS — источник
## истины и для игры, и для bake-режима инструмента (инструмент читает их отсюда).
##
## Инварианты (qa_vlg inv8/inv9, qa_lp t15):
##  - сетка map_village.json, CHAR_TO_TILE, коллайдеры BLOCK_SHAPES — бит-в-бит;
##    W/R/D (клетки избы) и «s» (указатель) остаются блокерами СЕТКИ (зеркало BFS
##    qa_vlg не меняется), но ФИЗИКА избы — честный прямоугольник силуэта спрайта
##    (тот же паттерн, что BLOCK_SHAPES у дерева: физика ⊂ консервативной сетки,
##    невидимых стен вокруг избы нет);
##  - глубина — общая шкала стоп V-01: z = fposmod(Y_стопы, 4800); пропы
##    (изба/колодец/указатель) регистрируются в реестр дима _ys_props_dim (t41);
##  - SCALE_CANON: размеры равны нативным размерам утверждённого листа
##    (zoom 1, герой 16 px, сетка 16 px): изба 35×36 ≈ 2.4H, колодец 21×27 ≈ 1.8H,
##    указатель 13×45 = 3.0H, костёр 23×23 — стопой (низом спрайта) на нижнюю
##    границу якорной клетки.

const ATLAS_PATH := "res://assets/village/village_v4.png"
const FLOOR_PATH := "res://assets/village/village_floor_v4.png"
const P := preload("res://scripts/pixel_palette.gd")

## ── c7 «микро-жизнь v1» (вердикт «давай начнём с микро-жизни») ──────────
## Обоснование выбора overlay-слоя: пол/цветы деревни — тайлы TileMapLayer,
## анимация set_cell-ом мутировала бы тайлмап (пин «деревня байт-в-байт» и
## зеркало inv2 ломались бы, детерминизм сборки — нет). Поэтому качание —
## overlay-спрайты НАД тайлмапом: тайлы не трогаются вообще. Текстуры оверлея
## НЕ новой рисовкой, а ВЫРЕЗАНИЕМ из уже запечённого атласа пола (единствен-
## ный источник пикселей; фаза A попиксельно равна тайлу => «покоящийся»
## кластер неотличим от тайла), фаза B — те же пиксели со сдвигом ±1 px.
## Паттерн тайминга — как факелы/A_TORCH: дискретно int(t/T)%2, фаза кластера
## из хэша клетки (кластеры не синхронны). Светлячки — runtime-текстура из
## PixelPalette (FIRE/FIRE_HOT), блуждание — чистая функция времени и хэшей
## (ни накопления, ни randi), 0 физ. узлов.
const SWAY_T := 0.5                 # период качания, с (2 фазы)
const SWAY_P_FLOWER := 0.60         # доля цветочных клеток с качанием
const SWAY_P_GRASS := 0.18          # доля «G»-клеток (травяные куртины)
const FF_HOPS := 8                  # клеток в цикле блуждания светлячка
const FF_HOP_T := 2.2               # базовая длительность перехода, с
const FF_Z := 900                   # светлячки летают выше актового z (деревня
									# ниже 480 px => z актёров < FF_Z < цикла)

## Регионы атласа пропов — запечённая геометрия (sheet_village.gd bake).
const REGIONS := {
	"HUT": Rect2(0, 0, 35, 36),
	"WELL": Rect2(36, 0, 21, 27),
	"CAMPFIRE": Rect2(58, 0, 23, 23),
	"CAMPFIRE_ASH": Rect2(82, 0, 23, 23),
	"SIGN": Rect2(0, 37, 13, 45),
}
const ATLAS_SIZE := Vector2i(105, 82)
## Пол: символ карты -> слот (16-пиксельный) атласа FLOOR_PATH.
const FLOOR_SLOTS := {"g": 0, "G": 1, "f": 2, "d": 3, "w": 4, "A": 3}
const FLOOR_SIZE := Vector2i(80, 16)

## Якорь избы — блок клеток W/R/D на сетке (cols 6..11, rows 3..6). Сетка не
## меняется (пин qa_vlg inv2); спрайт ставится центром по блоку, стопой на его
## нижнюю границу. Честный коллайдер — тело спрайта без трубы (35×32).
const HUT_BLOCK := Rect2i(6, 3, 6, 4)
const HUT_SOLID := Vector2(35, 32)
## Колодец — solid-проп (проходимых POI на клетке нет; р1 свободен, карманов
## не создаёт — клетка в открытом поле у площади).
const WELL_TILE := Vector2i(16, 11)
const WELL_SOLID := Vector2(12, 10)


## Строит слой VillageV4 в контейнере деревни мира; возвращает слой.
## world — мир (duck-typed, как везде): нужны village_zone, map_rows,
## _ys_prop(), _ys_props_dim.
static func build(world) -> Node2D:
	var layer := Node2D.new()
	layer.name = "VillageV4"
	world.village_zone.add_child(layer)
	var atlas := load_atlas()
	# изба: центр по блоку (col 6..11 -> x 144), стопа — нижняя граница блока (y 112)
	var hut_foot := Vector2((float(HUT_BLOCK.position.x) + float(HUT_BLOCK.size.x) * 0.5) * 16.0,
			float(HUT_BLOCK.position.y + HUT_BLOCK.size.y) * 16.0)
	var hut := _spr(layer, atlas, "HUT", hut_foot)
	world._ys_prop(hut)
	world._ys_props_dim.append(hut)
	# колодец
	var well_foot := Vector2(float(WELL_TILE.x) * 16.0 + 8.0, float(WELL_TILE.y + 1) * 16.0)
	var well := _spr(layer, atlas, "WELL", well_foot)
	world._ys_prop(well)
	world._ys_props_dim.append(well)
	# указатели: каждая «s» сетки (сейчас одна — (23,15)); коллайдер столба
	# остаётся у _build_walls (BLOCK_SHAPES 13), здесь только картинка.
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length():
			if row[x] != "s":
				continue
			var foot := Vector2(float(x) * 16.0 + 8.0, float(y + 1) * 16.0)
			var sign := _spr(layer, atlas, "SIGN", foot)
			world._ys_prop(sign)
			world._ys_props_dim.append(sign)
	# честная физика силуэтов (паттерн BLOCK_SHAPES: точно по арту, без невидимых стен)
	var solids := StaticBody2D.new()
	solids.name = "VillageV4Solids"
	solids.collision_layer = 2
	solids.collision_mask = 0
	layer.add_child(solids)
	_body_rect(solids, hut_foot, HUT_SOLID)
	_body_rect(solids, well_foot, WELL_SOLID)
	# c7 микро-жизнь: качание травы/цветов и светлячки (чистая визуализация,
	# узлы без коллайдеров, тайлмап/сетка/физика не затронуты)
	_build_sway(world)
	_build_fireflies(world)
	return layer


## Костёр: кадры AnimatedSprite2D (campfire.gd НЕ правится) с легаси-стрипа
## assets/campfire.png заменяются на v4-регионы атласа (огонь/пепел).
## Логика POI (радиус, отдых, одноразовость) не тронута — только визуал.
static func restyle_campfire(cf) -> void:
	var anim: AnimatedSprite2D = cf.get("_anim")
	if anim == null:
		return
	var atlas := load_atlas()
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	for pair: Array in [["fire", "CAMPFIRE"], ["ash", "CAMPFIRE_ASH"]]:
		fr.add_animation(String(pair[0]))
		fr.set_animation_loop(String(pair[0]), false)
		fr.set_animation_speed(String(pair[0]), 1.0)
		fr.add_frame(String(pair[0]), _region(atlas, String(pair[1])), 0.0)
	anim.sprite_frames = fr
	# стопа костра — нижняя граница клетки: нода на cell_center+2 (tile_to_world),
	# низ спрайта 23 px должен лежать на cell*16+16 => смещение центра -5.5 px
	anim.offset = Vector2(0.0, -5.5)
	cf._set_state_visual()


static func load_atlas() -> Texture2D:
	return load(ATLAS_PATH)


static func _region(atlas: Texture2D, key: String) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = atlas
	at.region = REGIONS[key]
	at.filter_clip = true  # LINEAR-мир: не хватать пиксели соседей по атласу
	return at


## Спрайт с стопой (нижним краем) в foot; центр — геометрия региона.
static func _spr(parent: Node2D, atlas: Texture2D, key: String, foot: Vector2) -> Sprite2D:
	var at := _region(atlas, key)
	var spr := Sprite2D.new()
	spr.texture = at
	spr.position = Vector2(foot.x, foot.y - float(at.get_size().y) * 0.5)
	parent.add_child(spr)
	return spr


## Коллайдер: rect w×h с НИЖНЕЙ серединой в foot.
static func _body_rect(body: StaticBody2D, foot: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = size
	cs.shape = sh
	cs.position = Vector2(foot.x, foot.y - size.y * 0.5)
	body.add_child(cs)


# ---------------------------------------------------------------- c7 качание

## Вырезание «качающейся» части тайла пола из запечённого атласа.
## Возвращает [texA, texL, texR] (16×16, фон прозрачный) или [] — mask по
## палитре: слот 2 («f») — головки цветов (рампы CLOTH/FIRE; стебелек LEAF
## не качается), слот 1 («G») — светлые КОНЧИКИ травинок (GRASS LIGHT верхних
## рядов, под которыми не LIGHT). Фаза A точит-в-точек равна тайлу, фазы
## L/R — те же пиксели со сдвигом ∓/+1 px.
static func sway_frames(floor_tex: Texture2D, slot: int) -> Array:
	var img := floor_tex.get_image()
	if img == null or slot * 16 + 16 > img.get_width():
		return []
	var base := img.get_region(Rect2i(slot * 16, 0, 16, 16))
	var idx: Dictionary = P.color_index()
	var a := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	a.fill(Color(0, 0, 0, 0))
	var picked: Array = []
	for y in 16:
		for x in 16:
			var col := base.get_pixel(x, y)
			if col.a < 0.5:
				continue
			var info = idx.get(P.key(col))
			if info == null:
				continue
			var rn := String(info[0])
			var tone := int(info[1])
			var take := false
			if slot == 2:
				take = rn == "CLOTH" or rn == "FIRE"
			elif slot == 1:
				if rn == "GRASS" and tone == P.T_LIGHT and y <= 8:
					var below: Color = base.get_pixel(x, y + 1) if y < 15 \
							else Color(0, 0, 0, 0)
					var binfo = idx.get(P.key(below))
					take = binfo == null or String(binfo[0]) != "GRASS" \
							or int(binfo[1]) != P.T_LIGHT
			if take:
				a.set_pixel(x, y, col)
				picked.append(Vector2i(x, y))
	if picked.is_empty():
		return []
	var lm := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	lm.fill(Color(0, 0, 0, 0))
	var rm := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	rm.fill(Color(0, 0, 0, 0))
	for p: Vector2i in picked:
		var c := a.get_pixel(p.x, p.y)
		if p.x - 1 >= 0:
			lm.set_pixel(p.x - 1, p.y, c)
		if p.x + 1 < 16:
			rm.set_pixel(p.x + 1, p.y, c)
	return [ImageTexture.create_from_image(a), ImageTexture.create_from_image(lm),
			ImageTexture.create_from_image(rm)]


## Слои качания: overlay-спрайты над тайлмапом (тайлы не мутируются). Плотность и
## фаза — хэш клетки (CaveArt.frac/hash_xy — тот же FNV-рецепт): детерминизм,
## разные кластеры не синхронны. Управляется ОДНИМ _process (массив items),
## позиция/кадр — чистая функция времени: ни накопления, ни randi.
static func _build_sway(world) -> void:
	if not ResourceLoader.exists(FLOOR_PATH):
		return
	var ftex: Texture2D = load(FLOOR_PATH)
	var frames := {1: sway_frames(ftex, 1), 2: sway_frames(ftex, 2)}
	if frames[1].is_empty() and frames[2].is_empty():
		return
	var layer: Node2D = SwayLayer.new()
	layer.name = "VillageSway"
	world.village_zone.add_child(layer)
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length():
			var ch := row[x]
			var slot := 2 if ch == "f" else (1 if ch == "G" else -1)
			if slot < 0:
				continue
			var fr: Array = frames[slot]
			if fr.is_empty():
				continue
			if CaveArt.frac(x, y, slot * 3 + 7) >= (SWAY_P_FLOWER if slot == 2 else SWAY_P_GRASS):
				continue
			var spr := Sprite2D.new()
			spr.texture = fr[0]
			spr.position = Vector2(float(x) * 16.0 + 8.0, float(y) * 16.0 + 8.0)
			layer.add_child(spr)
			layer.items.append({
				"spr": spr, "ta": fr[0], "tl": fr[1], "tr": fr[2],
				"phase": CaveArt.hash_xy(x, y) % 2,
				"dir": -1 if CaveArt.frac(x, y, 9) < 0.5 else 1,
			})


class SwayLayer:
	extends Node2D
	## Двухфазное дискретное качание: кадр = int(t/SWAY_T + фаза_клетки) % 2
	## (паттерн A_TORCH int(t/T)%2). Чистая функция времени — после паузы зон
	## состояние не «догоняется», накопления нет.
	var items: Array = []

	func _process(_delta: float) -> void:
		var tt := float(Time.get_ticks_msec()) / 1000.0
		for it in items:
			var ti := int(tt / VillageArt.SWAY_T) + int(it["phase"])
			if ti % 2 == 0:
				it["spr"].texture = it["ta"]
			else:
				it["spr"].texture = it["tl"] if int(it["dir"]) < 0 else it["tr"]


# ------------------------------------------------------------- c7 светлячки

static var _ff_tex: ImageTexture = null


## Runtime-текстура светлячка 3×3: ядро FIRE_HOT + крест FIRE MID (1–2 px
## «тела», остальное — ореол). Только PixelPalette, генерируется один раз.
static func _ff_texture() -> ImageTexture:
	if _ff_tex == null:
		var im := Image.create(3, 3, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		im.set_pixel(1, 1, P.FIRE_HOT)
		im.set_pixel(0, 1, P.RAMPS["FIRE"][P.T_MID])
		im.set_pixel(2, 1, P.RAMPS["FIRE"][P.T_MID])
		im.set_pixel(1, 0, P.RAMPS["FIRE"][P.T_MID])
		im.set_pixel(1, 2, P.RAMPS["FIRE"][P.T_MID])
		_ff_tex = ImageTexture.create_from_image(im)
	return _ff_tex


## 3..6 светлячков, детерминированно от карты зоны (её сида): старт — клетки
## «g» с хэш-пробою, маршрут — FF_HOPS переходов по 4-соседям, выбор соседа
## хэшем (ни randi, ни накопления: позиция — чистая функция времени). Все
## клетки маршрута проходимость проверена на сборке => в стены не входит.
static func _build_fireflies(world) -> void:
	var n := 3 + absi(CaveArt.hash_salted(world.map_w, world.map_h, 5)) % 4
	var starts: Array = []
	for y in world.map_rows.size():
		var row := String(world.map_rows[y])
		for x in row.length():
			if row[x] == "g" and CaveArt.frac(x, y, 31) < 0.02:
				starts.append(Vector2i(x, y))
	if starts.is_empty():
		return
	var layer := Node2D.new()
	layer.name = "VillageFireflies"
	world.village_zone.add_child(layer)
	var mgr: FireflyLayer = FireflyLayer.new()
	mgr.name = "Flies"
	layer.add_child(mgr)
	for i in n:
		var cur: Vector2i = starts[i % starts.size()]
		var cells: Array = [cur]
		for s in FF_HOPS:
			var nb: Array = []
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var t2: Vector2i = cur + d
				if world._village_walkable(t2):
					nb.append(t2)
			if nb.is_empty():
				break
			cur = nb[absi(CaveArt.hash_salted(cur.x, cur.y, 40 + s)) % nb.size()]
			cells.append(cur)
		if cells.size() < 2:
			continue
		var spr := Sprite2D.new()
		spr.texture = _ff_texture()
		spr.z_as_relative = false
		spr.z_index = FF_Z
		mgr.add_child(spr)
		mgr.flies.append({
			"spr": spr,
			"cells": cells,
			"hop": FF_HOP_T + float(absi(CaveArt.hash_salted(cur.x, cur.y, 61)) % 13) / 10.0,
			"phase": CaveArt.frac(i, 0, 77),
		})


class FireflyLayer:
	extends Node2D
	## Блуждание: маршрут — замкнутый цикл проходимость-проверенных клеток;
	## позиция = лерп между соседними клетками цикла + синусный «взлёт» над
	## травой. Всё — чистая функция времени (после выключения зоны не
	## «догоняется», накопления нет).
	var flies: Array = []

	func _process(_delta: float) -> void:
		var tt := float(Time.get_ticks_msec()) / 1000.0
		for f in flies:
			var cs: Array = f["cells"]
			var nn := cs.size()
			var u := tt / float(f["hop"]) + float(f["phase"])
			var k := int(u)
			var fr := fmod(u, 1.0)
			var a: Vector2i = cs[posmod(k, nn)]
			var b: Vector2i = cs[posmod(k + 1, nn)]
			var pa := Vector2(float(a.x) * 16.0 + 8.0, float(a.y) * 16.0 + 8.0)
			var pb := Vector2(float(b.x) * 16.0 + 8.0, float(b.y) * 16.0 + 8.0)
			f["spr"].position = pa.lerp(pb, fr) \
					+ Vector2(0.0, -6.0 + sin(tt * 2.1 + float(f["phase"]) * TAU) * 1.5)
