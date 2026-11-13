extends SceneTree
## Инструмент рисовки листа-вердикта «Деревня v4» (t53, docs/PIXEL_STYLE.md).
## Рисует кодом пиксель-спрайты деревенских пропов в новом каноне
## «единый hand-made пиксель» и собирает sheet: ряд 4x для разглядывания +
## ряд 1x (нативный игровой размер при zoom 1), линейка H=16 и легенда рамп.
##
## Догфуд канона:
##  - единственный источник цвета — PixelPalette (самопроверка «чистота палитры»);
##  - единый прогон canon_pass(): тёмный контур по нижней/боковым открытым
##    граням (тон OUTLINE материала), подсветка северо-запада (LIGHT по
##    верхне-левым открытым граням), нижний ряд силуэта — всегда OUTLINE
##    (правило «стопы/низ» как якорь y-sort);
##  - никаких чистых #000/#FFF, никаких вне-палитрных цветов (FIRE_HOT —
##    единственная разрешённая «горячая» точка).
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_village.gd -- <out.png>
## Выход 0 — все самопроверки PASS, иначе 1.

const P := preload("res://scripts/pixel_palette.gd")

const H_HERO := 16  # мир. px, канон t51

var _fails := 0
var _idx := {}  # argb32 -> [ramp, tone]

# ----------------------------------------------------------------------------- helpers
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "res://tools_art/sheet_village.png"
	_idx = P.color_index()
	var sprites: Array = _build_all()
	for s in sprites:
		_canon_pass(s["img"])
		_check_sprite(s)
	var sheet := _compose(sprites)
	var err := sheet.save_png(out_path)
	print("sheet saved: %s (%dx%d) err=%d" % [out_path, sheet.get_width(), sheet.get_height(), err])
	if _fails > 0:
		print("SELF-CHECK: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("SELF-CHECK: PASS")
		quit(0)


func C(rn: String, tone: int) -> Color:
	return P.r(rn)[tone]


func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, col)


func _line(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	while true:
		_px(img, x0, y0, col)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy


func _hash(x: int, y: int) -> float:
	return fposmod(sin(float(x) * 127.1 + float(y) * 311.7) * 43758.5453, 1.0)


func _blob(img: Image, cx: int, cy: int, rx: float, ry: float, rn: String) -> void:
	var mid := C(rn, P.T_MID)
	for y in range(cy - int(ry) - 1, cy + int(ry) + 2):
		for x in range(cx - int(rx) - 1, cx + int(rx) + 2):
			var nx := float(x - cx) / rx
			var ny := float(y - cy) / ry
			if nx * nx + ny * ny <= 1.15:
				_px(img, x, y, mid)


# ----------------------------------------------------------------------------- canon pass
## Единый прогон канона: OUTLINE снизу и по бокам, LIGHT-подсветка СЗ.
func _canon_pass(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src: Image = img.duplicate()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a < 0.5:
				continue
			var col := src.get_pixel(x, y)
			var info = _idx.get(P.key(col))
			if info == null:
				continue
			var rn := String(info[0])
			var tone := int(info[1])
			if not P.RAMPS.has(rn):
				continue
			var ramp: Array = P.RAMPS[rn]
			var open_below := y == h - 1 or src.get_pixel(x, y + 1).a < 0.5
			var open_right := x == w - 1 or src.get_pixel(x + 1, y).a < 0.5
			var open_left := x == 0 or src.get_pixel(x - 1, y).a < 0.5
			var open_up := y == 0 or src.get_pixel(x, y - 1).a < 0.5
			var open_ul := (x > 0 and y > 0) and src.get_pixel(x - 1, y - 1).a < 0.5
			if open_below:
				img.set_pixel(x, y, ramp[P.T_OUTLINE])
			elif open_right and tone != P.T_OUTLINE:
				img.set_pixel(x, y, ramp[P.T_DARK])
			elif (open_up or open_left or open_ul) and (tone == P.T_MID or tone == P.T_DARK):
				img.set_pixel(x, y, ramp[P.T_LIGHT])
			elif open_left and tone == P.T_LIGHT:
				pass


# ----------------------------------------------------------------------------- sprites
func _build_all() -> Array:
	return [
		{"name": "HUT", "canon": "2.4H", "img": _build_hut()},
		{"name": "WELL", "canon": "1.8H", "img": _build_well()},
		{"name": "CAMPFIRE", "canon": "~1.4H", "img": _build_campfire()},
		{"name": "SIGN", "canon": "3.0H", "img": _build_sign()},
		{"name": "STUMP", "canon": "0.55H", "img": _build_stump()},
		{"name": "STONES", "canon": "0.75H", "img": _build_stones()},
		{"name": "BOULDER", "canon": "0.65H", "img": _build_boulder()},
		{"name": "OAK", "canon": "3.0H fit", "img": _build_oak()},
		{"name": "PINE", "canon": "3.0H", "img": _build_pine()},
	]


func _build_hut() -> Image:
	var img := _im(35, 36)
	# труба (каменная, тёплый камень) x7..10 y0..6
	_rect(img, 6, 0, 11, 0, C("STONE_WARM", P.T_DARK))
	_rect(img, 7, 1, 10, 6, C("STONE_WARM", P.T_MID))
	_rect(img, 7, 1, 7, 6, C("STONE_WARM", P.T_LIGHT))
	_rect(img, 10, 1, 10, 6, C("STONE_WARM", P.T_DARK))
	_px(img, 8, 3, C("STONE_WARM", P.T_DARK))
	_px(img, 9, 5, C("STONE_WARM", P.T_DARK))
	# крыша: конёк y=4 (центр x=17), свес y=14 на всю ширину
	for y in range(4, 15):
		var hw := int(2.0 + (y - 4) * 1.5)
		var tone := P.T_LIGHT if (y - 4) % 3 == 0 else (P.T_MID if (y - 4) % 3 == 1 else P.T_MID)
		for x in range(17 - hw, 17 + hw + 1):
			var t := tone
			if x >= 17 + hw - 1:
				t = P.T_DARK  # восточная граница ската — в тень
			_px(img, x, y, C("ROOF", t))
	# слуховое окно в коньке
	_rect(img, 15, 9, 19, 13, C("ROOF", P.T_DARK))
	_rect(img, 16, 10, 18, 12, C("WATER", P.T_MID))
	_px(img, 16, 10, C("WATER", P.T_LIGHT))
	# свес и мягкая тень под свесом
	_rect(img, 0, 14, 34, 14, C("ROOF", P.T_MID))
	_rect(img, 2, 15, 32, 15, C("ROOF", P.T_DARK))
	# сруб: MID-бревна с теневым швом каждые 3 ряда и редкой СЗ-подсветкой выпуклости
	for y in range(16, 32):
		for x in range(3, 32):
			var t := P.T_DARK if y % 3 == 2 else P.T_MID
			if t == P.T_MID and y % 3 == 0 and _hash(x, y) < 0.4:
				t = P.T_LIGHT
			_px(img, x, y, C("WOOD", t))
	# угловые окладные брёвна
	for y in range(16, 32):
		_px(img, 3, y, C("BARK", P.T_LIGHT))
		_px(img, 4, y, C("BARK", P.T_MID))
		_px(img, 30, y, C("BARK", P.T_MID))
		_px(img, 31, y, C("BARK", P.T_DARK))
	# окно x8..13 y19..24
	_rect(img, 8, 19, 13, 24, C("BARK", P.T_OUTLINE))
	_rect(img, 9, 20, 12, 23, C("WATER", P.T_MID))
	_px(img, 9, 20, C("WATER", P.T_LIGHT))
	_px(img, 10, 20, C("WATER", P.T_LIGHT))
	_px(img, 9, 21, C("WATER", P.T_LIGHT))
	_rect(img, 7, 25, 14, 25, C("WOOD", P.T_DARK))  # подоконник
	# дверь x20..25 y19..31
	_rect(img, 19, 19, 26, 19, C("BARK", P.T_DARK))  # наличник
	_rect(img, 20, 20, 25, 31, C("WOOD", P.T_MID))
	_rect(img, 20, 20, 20, 31, C("WOOD", P.T_LIGHT))
	_line(img, 23, 21, 23, 30, C("WOOD", P.T_DARK))  # щель меж досок
	_px(img, 24, 26, C("IRON", P.T_LIGHT))  # ручка
	# фундамент + крыльцо
	_rect(img, 3, 32, 34, 32, C("STONE_WARM", P.T_MID))
	for x in range(3, 35):
		for y in range(33, 36):
			var col := C("STONE_WARM", P.T_MID)
			if (x * 7 + y * 5) % 13 < 2:
				col = C("STONE_WARM", P.T_DARK)
			_px(img, x, y, col)
	_rect(img, 19, 33, 26, 34, C("STONE_WARM", P.T_LIGHT))  # ступени
	_rect(img, 19, 34, 26, 34, C("STONE_WARM", P.T_MID))
	# кустик у фундамента (двухъярусный: нижний ряд канон положит в тень — как подножье)
	_px(img, 1, 32, C("GRASS", P.T_LIGHT))
	_px(img, 2, 32, C("GRASS", P.T_LIGHT))
	_px(img, 1, 33, C("GRASS", P.T_MID))
	_px(img, 2, 33, C("GRASS", P.T_MID))
	return img


func _build_well() -> Image:
	var img := _im(21, 27)
	# двускатная крыша: конёк x=10 y0, свес y5
	for y in range(0, 6):
		var hw := int(1.0 + y * 1.7)
		var tone := P.T_LIGHT if y % 3 == 0 else P.T_MID
		for x in range(10 - hw, 10 + hw + 1):
			var t := tone
			if x >= 10 + hw - 1:
				t = P.T_DARK
			_px(img, x, y, C("ROOF", t))
	_rect(img, 3, 6, 17, 6, C("ROOF", P.T_DARK))  # тень под крышей
	# стойки
	for y in range(6, 17):
		_px(img, 3, y, C("WOOD", P.T_LIGHT))
		_px(img, 4, y, C("WOOD", P.T_MID))
		_px(img, 16, y, C("WOOD", P.T_MID))
		_px(img, 17, y, C("WOOD", P.T_DARK))
	_rect(img, 3, 7, 17, 7, C("WOOD", P.T_MID))  # верхняя перекладина
	# ворот + верёвка + ведро
	_px(img, 9, 8, C("IRON", P.T_LIGHT))
	_px(img, 11, 8, C("IRON", P.T_DARK))
	_line(img, 10, 8, 10, 12, C("BARK", P.T_MID))
	_rect(img, 8, 12, 12, 12, C("WOOD", P.T_DARK))  # обод
	_rect(img, 8, 13, 12, 15, C("WOOD", P.T_MID))
	_px(img, 8, 13, C("WOOD", P.T_LIGHT))
	_px(img, 12, 13, C("WOOD", P.T_DARK))
	_rect(img, 8, 14, 12, 14, C("IRON", P.T_MID))
	_px(img, 10, 13, C("WATER", P.T_LIGHT))  # блик воды
	# сруб-ограждение (тёплый камень)
	_rect(img, 2, 16, 18, 16, C("STONE_WARM", P.T_LIGHT))
	for x in range(2, 19):
		for y in range(17, 27):
			var col := C("STONE_WARM", P.T_MID)
			if (x * 7 + y * 5) % 11 < 2:
				col = C("STONE_WARM", P.T_DARK)
			_px(img, x, y, col)
	_px(img, 1, 25, C("GRASS", P.T_LIGHT))
	_px(img, 19, 24, C("GRASS", P.T_MID))
	_px(img, 19, 25, C("GRASS", P.T_LIGHT))
	return img


func _build_campfire() -> Image:
	var img := _im(23, 23)
	# порядок слоёв: брёвна → тренога → связка → котелок → пламя (пламя спереди)
	# брёвна крестом (двойные линии — толщина 2)
	_line(img, 6, 20, 16, 18, C("BARK", P.T_MID))
	_line(img, 6, 21, 16, 19, C("BARK", P.T_DARK))
	_line(img, 17, 20, 7, 18, C("BARK", P.T_DARK))
	_line(img, 17, 21, 7, 19, C("BARK", P.T_OUTLINE))
	# тренога: левая нога на свету (2px), правая в тени, задняя центром
	_line(img, 11, 1, 3, 20, C("BARK", P.T_LIGHT))
	_line(img, 12, 1, 4, 20, C("BARK", P.T_MID))
	_line(img, 12, 1, 19, 20, C("BARK", P.T_DARK))
	_line(img, 13, 1, 20, 20, C("BARK", P.T_OUTLINE))
	_line(img, 11, 2, 11, 17, C("BARK", P.T_MID))
	_rect(img, 9, 1, 13, 2, C("WOOD", P.T_DARK))  # связка вершин
	_px(img, 10, 1, C("WOOD", P.T_LIGHT))
	_px(img, 11, 1, C("WOOD", P.T_LIGHT))
	# котелок
	_rect(img, 10, 3, 12, 3, C("IRON", P.T_LIGHT))  # крышка
	_px(img, 10, 4, C("IRON", P.T_LIGHT))
	_rect(img, 9, 4, 13, 4, C("IRON", P.T_MID))
	_rect(img, 8, 5, 14, 9, C("IRON", P.T_MID))
	_rect(img, 9, 10, 13, 10, C("IRON", P.T_DARK))
	_rect(img, 10, 11, 12, 11, C("IRON", P.T_DARK))
	_px(img, 8, 5, C("IRON", P.T_LIGHT))
	_px(img, 9, 5, C("IRON", P.T_LIGHT))
	_px(img, 8, 6, C("IRON", P.T_LIGHT))
	_px(img, 15, 7, C("IRON", P.T_DARK))  # носик
	# пламя: капля от y12 (язык) до y19 — поверх ног, под ним угли
	_px(img, 11, 12, C("FIRE", P.T_MID))
	_rect(img, 10, 13, 12, 13, C("FIRE", P.T_MID))
	_rect(img, 9, 14, 13, 14, C("FIRE", P.T_MID))
	_rect(img, 8, 15, 14, 18, C("FIRE", P.T_MID))
	_rect(img, 9, 19, 13, 19, C("FIRE", P.T_MID))
	_rect(img, 10, 15, 12, 18, C("FIRE", P.T_LIGHT))
	_px(img, 11, 16, P.FIRE_HOT)
	_px(img, 11, 17, P.FIRE_HOT)
	_px(img, 7, 12, C("FIRE", P.T_DARK))  # искры
	_px(img, 15, 11, C("FIRE", P.T_DARK))
	_px(img, 13, 10, C("FIRE", P.T_DARK))
	# камни у основания
	_blob(img, 3, 21, 2.6, 1.6, "STONE")
	_blob(img, 19, 21, 2.6, 1.6, "STONE")
	return img


func _build_sign() -> Image:
	var img := _im(13, 45)
	# столб с острым верхом x5..7
	_px(img, 6, 2, C("BARK", P.T_LIGHT))
	_rect(img, 5, 3, 7, 4, C("BARK", P.T_MID))
	_px(img, 5, 3, C("BARK", P.T_LIGHT))
	for y in range(4, 42):
		_px(img, 5, y, C("BARK", P.T_LIGHT))
		_px(img, 6, y, C("BARK", P.T_MID))
		_px(img, 7, y, C("BARK", P.T_DARK))
	# верхняя доска вправо (стрелка) y6..11
	_rect(img, 3, 6, 10, 11, C("WOOD", P.T_MID))
	_rect(img, 3, 6, 10, 6, C("WOOD", P.T_LIGHT))
	_rect(img, 3, 11, 10, 11, C("WOOD", P.T_DARK))
	_rect(img, 11, 7, 11, 10, C("WOOD", P.T_MID))
	_rect(img, 12, 8, 12, 9, C("WOOD", P.T_MID))
	_px(img, 4, 8, C("WOOD", P.T_DARK))  # резная полоска
	_px(img, 5, 9, C("WOOD", P.T_DARK))
	_px(img, 6, 8, C("IRON", P.T_LIGHT))  # гвоздь
	# нижняя доска влево y16..21
	_rect(img, 2, 16, 9, 21, C("WOOD", P.T_MID))
	_rect(img, 2, 16, 9, 16, C("WOOD", P.T_LIGHT))
	_rect(img, 2, 21, 9, 21, C("WOOD", P.T_DARK))
	_rect(img, 1, 17, 1, 20, C("WOOD", P.T_MID))
	_rect(img, 0, 18, 0, 19, C("WOOD", P.T_MID))
	_px(img, 8, 18, C("WOOD", P.T_DARK))
	_px(img, 6, 18, C("IRON", P.T_LIGHT))
	# тень досок на столбе + сучки
	_px(img, 7, 12, C("BARK", P.T_DARK))
	_px(img, 7, 22, C("BARK", P.T_DARK))
	_px(img, 6, 28, C("BARK", P.T_DARK))
	_px(img, 6, 35, C("BARK", P.T_DARK))
	_px(img, 5, 31, C("BARK", P.T_DARK))
	# земля у основания
	_rect(img, 4, 42, 8, 42, C("PATH", P.T_MID))
	_rect(img, 3, 43, 9, 43, C("PATH", P.T_MID))
	_rect(img, 2, 44, 10, 44, C("PATH", P.T_DARK))
	_px(img, 1, 43, C("GRASS", P.T_LIGHT))
	_px(img, 11, 43, C("GRASS", P.T_LIGHT))
	_px(img, 2, 42, C("GRASS", P.T_MID))
	return img


func _build_stump() -> Image:
	var img := _im(11, 8)
	# мох на северной кромке + срез
	_px(img, 2, 0, C("GRASS", P.T_MID))
	_px(img, 3, 0, C("GRASS", P.T_LIGHT))
	_px(img, 4, 0, C("GRASS", P.T_MID))
	_px(img, 3, 1, C("WOOD", P.T_LIGHT))
	_rect(img, 4, 1, 7, 1, C("WOOD", P.T_MID))
	_px(img, 5, 1, C("WOOD", P.T_DARK))  # сердцевина кольца
	_rect(img, 2, 2, 8, 2, C("WOOD", P.T_LIGHT))
	_px(img, 6, 2, C("WOOD", P.T_MID))
	_px(img, 1, 2, C("BARK", P.T_DARK))
	_px(img, 9, 2, C("BARK", P.T_DARK))
	for y in range(3, 7):
		_px(img, 0, y, C("BARK", P.T_DARK))
		_px(img, 1, y, C("BARK", P.T_LIGHT))
		for x in range(2, 9):
			_px(img, x, y, C("BARK", P.T_MID))
		_px(img, 3, y, C("BARK", P.T_DARK))
		_px(img, 7, y, C("BARK", P.T_DARK))
		_px(img, 9, y, C("BARK", P.T_MID))
		_px(img, 10, y, C("BARK", P.T_DARK))
	_px(img, 0, 6, C("GRASS", P.T_MID))
	_px(img, 10, 6, C("GRASS", P.T_MID))
	# корни
	_rect(img, 0, 7, 1, 7, C("BARK", P.T_DARK))
	_rect(img, 3, 7, 7, 7, C("BARK", P.T_MID))
	_rect(img, 9, 7, 10, 7, C("BARK", P.T_DARK))
	return img


func _build_stones() -> Image:
	var img := _im(15, 12)
	_blob(img, 5, 7, 4.6, 4.2, "STONE")
	_blob(img, 12, 8, 2.8, 2.8, "STONE")
	# подсветка СЗ и трещины
	_px(img, 3, 4, C("STONE", P.T_LIGHT))
	_px(img, 4, 3, C("STONE", P.T_LIGHT))
	_px(img, 10, 6, C("STONE", P.T_LIGHT))
	_px(img, 6, 7, C("STONE", P.T_DARK))
	_px(img, 7, 8, C("STONE", P.T_DARK))
	_px(img, 12, 9, C("STONE", P.T_DARK))
	# травинки между камней (не на нижней кромке — иначе канон съест в OUTLINE)
	_px(img, 8, 9, C("GRASS", P.T_LIGHT))
	_px(img, 9, 8, C("GRASS", P.T_MID))
	_px(img, 1, 9, C("GRASS", P.T_MID))
	return img


func _build_boulder() -> Image:
	var img := _im(17, 11)
	_blob(img, 8, 6, 8.0, 5.4, "STONE")
	# мох наверху (северная сторона)
	for x in range(5, 12):
		if _hash(x, 1) > 0.4:
			_px(img, x, 1, C("GRASS", P.T_MID))
	_px(img, 6, 1, C("GRASS", P.T_LIGHT))
	_px(img, 9, 0, C("GRASS", P.T_MID))
	_px(img, 10, 1, C("GRASS", P.T_LIGHT))
	# блик и трещина
	_px(img, 4, 3, C("STONE", P.T_LIGHT))
	_px(img, 5, 2, C("STONE", P.T_LIGHT))
	_line(img, 9, 4, 10, 6, C("STONE", P.T_DARK))
	_px(img, 11, 7, C("STONE", P.T_DARK))
	_px(img, 2, 9, C("GRASS", P.T_MID))
	_px(img, 14, 9, C("GRASS", P.T_LIGHT))
	return img


func _build_oak() -> Image:
	var img := _im(45, 44)
	# ствол — рисуем первым, крона перекроет верх
	for y in range(26, 44):
		_px(img, 20, y, C("BARK", P.T_LIGHT))
		for x in range(21, 24):
			_px(img, x, y, C("BARK", P.T_MID))
		_px(img, 24, y, C("BARK", P.T_DARK))
	_px(img, 22, 30, C("BARK", P.T_DARK))
	_px(img, 21, 35, C("BARK", P.T_DARK))
	_px(img, 23, 39, C("BARK", P.T_DARK))
	# root flare
	_rect(img, 18, 41, 19, 43, C("BARK", P.T_MID))
	_rect(img, 25, 41, 26, 43, C("BARK", P.T_DARK))
	_px(img, 17, 43, C("BARK", P.T_DARK))
	_px(img, 27, 43, C("BARK", P.T_DARK))
	# крона — union лопастных окружностей
	var lobes := [
		[11, 13, 8.0, 7.0], [22, 9, 10.0, 8.0], [34, 13, 8.0, 7.0],
		[8, 20, 7.0, 6.5], [37, 20, 7.0, 6.5], [22, 18, 13.5, 12.0],
		[15, 22, 8.5, 7.0], [29, 22, 8.5, 7.0],
	]
	var canopy := {}
	for y in range(0, 32):
		for x in range(0, 45):
			for lb in lobes:
				var nx := float(x - int(lb[0])) / float(lb[2])
				var ny := float(y - int(lb[1])) / float(lb[3])
				if nx * nx + ny * ny <= 1.0:
					canopy[y * 45 + x] = true
					break
	for k in canopy:
		var x: int = k % 45
		var y: int = int(k / 45)
		var col := C("LEAF", P.T_MID)
		var hv := _hash(x, y)
		if (y <= 7 and x <= 22 and hv < 0.32) or (hv < 0.08 and y < 16):
			col = C("LEAF", P.T_LIGHT)
		elif hv < 0.10 and y >= 24:
			col = C("LEAF", P.T_DARK)
		img.set_pixel(x, y, col)
	# «прорехи» листвы для живой руки
	img.set_pixel(5, 18, Color(0, 0, 0, 0))
	img.set_pixel(40, 14, Color(0, 0, 0, 0))
	img.set_pixel(24, 29, Color(0, 0, 0, 0))
	img.set_pixel(16, 27, Color(0, 0, 0, 0))
	# трава у ноги
	_px(img, 15, 42, C("GRASS", P.T_LIGHT))
	_px(img, 29, 42, C("GRASS", P.T_LIGHT))
	_px(img, 30, 43, C("GRASS", P.T_MID))
	return img


func _build_pine() -> Image:
	var img := _im(29, 48)
	# ствол
	for y in range(38, 48):
		_px(img, 13, y, C("BARK", P.T_LIGHT))
		_px(img, 14, y, C("BARK", P.T_MID))
		_px(img, 15, y, C("BARK", P.T_DARK))
	_rect(img, 11, 45, 12, 47, C("BARK", P.T_MID))
	_rect(img, 16, 45, 17, 47, C("BARK", P.T_DARK))
	# ярусы лап, снизу вверх (верхние перекрывают нижние)
	var tiers := [
		[24, 40, 14], [12, 28, 12], [5, 16, 9], [0, 7, 6],
	]
	for t in tiers:
		var apex: int = t[0]
		var bottom: int = t[1]
		var maxhw: int = t[2]
		for y in range(apex, bottom + 1):
			var hw := int(float(maxhw) * float(y - apex + 1) / float(bottom - apex + 1))
			for x in range(14 - hw, 14 + hw + 1):
				var tone := P.T_MID
				if x == 14 - hw or x == 14 + hw:
					tone = P.T_DARK
				if y == bottom:
					tone = P.T_DARK
				if y <= apex + 1:
					tone = P.T_LIGHT
				_px(img, x, y, C("PINE", tone))
	# живая неравномерность нижних ярусов
	for y in [18, 19, 30, 31]:
		for x in range(0, 29):
			if img.get_pixel(x, y).a > 0.5 and img.get_pixel(x, y - 1).a < 0.5 and _hash(x, y) < 0.4:
				_px(img, x, y, C("PINE", P.T_LIGHT))
	_px(img, 12, 47, C("GRASS", P.T_LIGHT))
	_px(img, 18, 47, C("GRASS", P.T_MID))
	return img


# ----------------------------------------------------------------------------- self-check
func _check_sprite(s: Dictionary) -> void:
	var img: Image = s["img"]
	var nm := String(s["name"])
	var w := img.get_width()
	var h := img.get_height()
	# 1) чистота палитры
	var foreign := 0
	var uniq := {}
	for y in h:
		for x in w:
			var col := img.get_pixel(x, y)
			if col.a < 0.5:
				continue
			uniq[P.key(col)] = true
			if not _idx.has(P.key(col)):
				foreign += 1
	if foreign > 0:
		_fails += 1
		print("[FAIL] %s: %d пикселей вне палитры" % [nm, foreign])
	# 2) нижний открытый ряд — только OUTLINE тона (правило стопы/низа)
	var last := -1
	for y in range(h - 1, -1, -1):
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				last = y
				break
		if last >= 0:
			break
	var bad_foot := 0
	for x in w:
		if img.get_pixel(x, last).a > 0.5:
			var info = _idx.get(P.key(img.get_pixel(x, last)))
			if info == null or int(info[1]) != P.T_OUTLINE:
				bad_foot += 1
	if bad_foot > 0:
		_fails += 1
		print("[FAIL] %s: нижний ряд не из OUTLINE-тонов: %d px" % [nm, bad_foot])
	# 3) подсветка СЗ: в верхней половинеLIGHT-тонов не меньше, чем в нижней
	var lt_top := 0
	var lt_bot := 0
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.5:
				continue
			var info = _idx.get(P.key(img.get_pixel(x, y)))
			if info == null or not P.RAMPS.has(String(info[0])):
				continue
			if int(info[1]) == P.T_LIGHT:
				if y < h / 2.0:
					lt_top += 1
				else:
					lt_bot += 1
	if lt_top < 3:
		_fails += 1
		print("[FAIL] %s: нет подсветки СЗ (LIGHT сверху: %d)" % [nm, lt_top])
	print("[spr] %-9s %2dx%-2d  %5s  colors:%d  light t/b: %d/%d" % [nm, w, h, String(s["canon"]), uniq.size(), lt_top, lt_bot])


# ----------------------------------------------------------------------------- sheet
const FONT := {
	"A": ["111", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["111", "100", "100", "100", "111"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["111", "100", "101", "101", "111"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "111"],
	"K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "101", "101", "101"], "N": ["110", "101", "101", "101", "101"],
	"O": ["111", "101", "101", "101", "111"], "P": ["111", "101", "111", "100", "100"],
	"Q": ["111", "101", "101", "111", "011"], "R": ["111", "101", "110", "101", "101"],
	"S": ["111", "100", "111", "001", "111"], "T": ["111", "010", "010", "010", "010"],
	"U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
	"W": ["101", "101", "101", "111", "101"], "X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "111", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "001", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "001"],
	" ": ["000", "000", "000", "000", "000"], "-": ["000", "000", "111", "000", "000"],
	"+": ["000", "010", "111", "010", "000"], "=": ["000", "111", "000", "111", "000"],
}


func _text(img: Image, x0: int, y0: int, txt: String, sc: int, col: Color) -> int:
	var x := x0
	for ch in txt.to_upper():
		var g = FONT.get(ch)
		if g != null:
			for r in 5:
				for c in 3:
					if String(g[r])[c] == "1":
						for dy in sc:
							for dx in sc:
								_px(img, x + c * sc + dx, y0 + r * sc + dy, col)
		x += 4 * sc
	return x - x0 - sc


func _maxh(sprites: Array) -> int:
	var m := 0
	for s in sprites:
		m = maxi(m, (s["img"] as Image).get_height())
	return m


func _compose(sprites: Array) -> Image:
	var pad := 6
	var gap := 14
	var cap_gap := 4
	var row1_lbl := 12
	var row1_h := _maxh(sprites) * 4 + pad * 2
	var row2_h := _maxh(sprites) + pad * 2
	var ruler := 36
	var title := 30
	var pal_h := 26
	var W := 0
	for s in sprites:
		W += ((s["img"] as Image).get_width()) * 4 + pad * 2 + gap
	W += ruler + 20
	W = maxi(W, 560)
	var H := title + row1_h + cap_gap + 12 + row2_h + cap_gap + 12 + pal_h + 16
	var sheet := _im(W, H)
	sheet.fill(P.SHEET["BG"])
	# заголовок
	_text(sheet, 10, 8, "VILLAGE V4 - PIXEL CANON SHEET", 2, P.SHEET["TEXT"])
	_text(sheet, 10, 21, "NORTHWEST LIGHT / OUTLINE BOTTOM / FOOT=YSORT / TILE16 H16", 1, P.SHEET["LINE"])
	# ряды
	var rows := [[4, title + row1_lbl / 2, row1_h], [1, title + row1_lbl / 2 + row1_h + cap_gap + 5 + row1_lbl + 4, row2_h]]
	for row in rows:
		var sc: int = row[0]
		var y0: int = row[1]
		var x := ruler
		_text(sheet, 10, y0 + 2, "%dX" % sc, 1, P.SHEET["LINE"])
		for s in sprites:
			var img: Image = s["img"]
			var cw := img.get_width() * sc
			var ch := img.get_height() * sc
			var cell_w := cw + pad * 2
			var cell_h := _maxh(sprites) * sc + pad * 2
			var cy := y0 + (_maxh(sprites) * sc - ch)  # ногиsprite'ов на одну линию
			# панель
			_rect(sheet, x, y0, x + cell_w - 1, y0 + cell_h - 1, P.SHEET["PANEL"])
			_rect(sheet, x, y0, x + cell_w - 1, y0, P.SHEET["LINE"])
			_rect(sheet, x, y0 + cell_h - 1, x + cell_w - 1, y0 + cell_h - 1, P.SHEET["LINE"])
			for yy in ch:
				for xx in cw:
					var col := img.get_pixel(xx / sc, yy / sc)
					if col.a > 0.5:
						var sx := x + pad + (xx / sc) * sc
						var sy := cy + pad + (yy / sc) * sc
						for dy in sc:
							for dx in sc:
								sheet.set_pixel(sx + dx, sy + dy, col)
			# подпись
			var lbl := "%s %DX%D" % [String(s["name"]), img.get_width(), img.get_height()]
			_text(sheet, x + 2, y0 + cell_h + cap_gap, lbl, sc, P.SHEET["TEXT"])
			x += cell_w + gap
		# линейка H
		var ly := y0 + (_maxh(sprites) - H_HERO) * sc + pad
		for yy in H_HERO * sc:
			_px(sheet, 18, ly + yy, P.SHEET["LINE"])
		for xx in 5:
			_px(sheet, 18 + xx, ly, P.SHEET["LINE"])
			_px(sheet, 18 + xx, ly + H_HERO * sc - 1, P.SHEET["LINE"])
		_text(sheet, 25, ly + (H_HERO * sc - 5 * 1) / 2, "H", 1, P.SHEET["LINE"])
	# легенда палитры
	var py := H - pal_h + 4
	_text(sheet, 10, py, "RAMPS 4 TONES L/M/D/O", 1, P.SHEET["LINE"])
	var px0 := 10
	var names: Array = P.RAMPS.keys()
	var nx0 := 10
	var ny := py + 10
	for rn in names:
		var ramp: Array = P.RAMPS[rn]
		for t in 4:
			_rect(sheet, nx0 + t * 7, ny, nx0 + t * 7 + 5, ny + 7, ramp[t])
		nx0 += 4 * 7 + 3
		if nx0 > W - 40:
			nx0 = 10
			ny += 9
	return sheet
