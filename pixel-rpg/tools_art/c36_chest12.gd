extends SceneTree
## c36 инструмент: детерминированный ребейк легаси-тайла 12 (chest_big_open)
## в res://assets/dungeon_tiles.png (вердикт c35 «пещерный сундук берём»).
##
## Болезнь прежней десятки-двенадцатой (тот же класс дефекта, что отвергнутый
## v1 пепелища): полный перекрас корпуса относительно тайла 11 (diff 182/256),
## пропавший замок и 20 px пещерной фиолетовой подсветки — «полоса легаси»
## над крышкой проп-сундука. Кадрированный v2 строит тайл 12 по канону c32b
## СТРОГО из тайла 11 (тот же код и те же байты, что утверждённый кандидат
## md5 ED81740F44833CDFDF49365FA478B433): крышка y2..3 x2..13 подъём ровно
## 2 ряда без перекраски; жерло y2..3 x2..13 самый тёмный тон этого тайла;
## содержимое ровно 2 px (тёмное золото замка + тьма скважины); корпус
## y4..15 байт-в-бит. Итог: зона раскрытия 48/256, новых цветов 0.
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/c36_chest12.gd
## Идемпотентен: крышка читается из тайла 11 (он не меняется), второй прогон
## печатает побайтово идентичный файл. Выход 0 — все самопроверки PASS.

const SRC := "res://assets/dungeon_tiles.png"
const TX := 176  # источник: тайл 11 chest_big_closed (колонка 11 листа по 16 px)
const TD := 192  # приёмник: тайл 12 chest_big_open (колонка 12)
const THROAT := Color8(0x10, 0x11, 0x1B)  # самый тёмный тон самого тайла 11
const LOOT_1 := Color8(0x7C, 0x60, 0x2C)  # тёмное золото замка (тон 11)
const LOOT_2 := Color8(0x0E, 0x0E, 0x14)  # тьма скважины (тон 11)


func _init() -> void:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(SRC)) != OK:
		print("FAIL: не читается ", SRC)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	if img.get_size() != Vector2i(256, 16):
		print("FAIL: размер dungeon_tiles %s != 256x16" % str(img.get_size()))
		quit(1)
		return
	var t11: Image = img.get_region(Rect2i(TX, 0, 16, 16))
	# крышка: y2..3 x2..13 -> y0..1 (подъём ровно 2 ряда, пиксели те же)
	for x in range(2, 14):
		img.set_pixel(TD + x, 0, t11.get_pixel(x, 2))
		img.set_pixel(TD + x, 1, t11.get_pixel(x, 3))
	# фон по краям y0..3 (колонки 0,1,14,15) — как в закрытом (иначе v1-фон
	# старой двенадцатой остался бы рамкой вокруг нового кадра)
	for x in [0, 1, 14, 15]:
		for y in 4:
			img.set_pixel(TD + x, y, t11.get_pixel(x, y))
	# жерло ровно 2 ряда — темнее корпуса (крайние колонки 0,1,14,15 — фон 11)
	for y in [2, 3]:
		for x in range(2, 14):
			img.set_pixel(TD + x, y, THROAT)
	# содержимое ровно 2 px тёмных тонов этого же кадра
	img.set_pixel(TD + 7, 3, LOOT_1)
	img.set_pixel(TD + 8, 3, LOOT_2)
	# корпус с замком и полосами y4..15 — байт-в-бит тайла 11 (12×16 = 192 px;
	# старая десятка-двенадцатая перекрашивала именно его — источник 11)
	for y in range(4, 16):
		for x in 16:
			img.set_pixel(TD + x, y, t11.get_pixel(x, y))
	# --- самопроверки: зона раскрытия ровно 48 (ряды 0..3), корпус 0, новых
	# --- цветов относительно тайла 11 ровно 0
	var set11 := {}
	for y in 16:
		for x in 16:
			set11[t11.get_pixel(x, y).to_html(false)] = true
	var zone := 0
	var body_bad := 0
	var newc := 0
	for y in 16:
		for x in 16:
			var a := t11.get_pixel(x, y)
			var b := img.get_pixel(TD + x, y)
			if a.to_argb32() != b.to_argb32():
				if y <= 3:
					zone += 1
				else:
					body_bad += 1
			if b.a > 0.5 and not set11.has(b.to_html(false)):
				newc += 1
	if zone != 48 or body_bad != 0 or newc != 0:
		print("FAIL: zone=%d body=%d new=%d" % [zone, body_bad, newc])
		quit(1)
		return
	if img.save_png(SRC) != OK:
		print("FAIL: save_png ", SRC)
		quit(1)
		return
	print("c36_chest12: zone=%d body=%d new=%d md5=%s" % [
			zone, body_bad, newc, FileAccess.get_md5(SRC)])
	quit(0)
