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
