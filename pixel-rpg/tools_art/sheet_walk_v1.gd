extends SceneTree
## c17 «Циклы ходьбы v1» — лист на вердикт пользователя (игра НЕ тронута).
##
## Лист: полоса A — герой (воин): 4 направления × 4 фазы цикла
## contact/pass/contact/pass; полоса B — sample-враг мглокрыс: 2 направления ×
## 4 фазы (машущий полёт). Под каждой клеткой 16 px — мастер 48 px (nearest ×3).
##
## Фаза 0 каждого направления — побайтово кадр стойки из игрового атласа
## (assets/class_warrior.png / mobs_swarmling.png, колонка 0). Фазы 1..3 —
## только уже существующие канон-кадры атласа (шаги col1/col2, взмах col1)
## и чистые вертикальные сдвиги на 1 px (покачивание). Генератор НЕ вводит
## ни одного нового цвета в спрайтовые области: палитра кадров унаследована
## от утверждённой стойки (наследие: персонажный арт старше палитры
## PixelPalette — число off-пикселей источника печатается отдельной метрикой
## и вынесено на вердикт отдельным вопросом).
##
## Запуск: godot --headless --path pixel-rpg -s res://tools_art/sheet_walk_v1.gd -- <out.png>
##
## Самопроверки (exit != 0 при провале):
##  1) фаза 0 каждой клетки == стойка источника (col 0 ряда) побайтово,
##     прозрачные пиксели источника — фон листа;
##  2) каждая фаза == копия своего исходного кадра с точным вертикальным
##     сдвигом (ни одного «лишнего»/обрезанного пикселя, стопы в границах
##     клетки 16×16, сдвиг не срезает содержимое);
##  3) покачивание == 1 px (не больше);
##  4) новых спрайтовых цветов против источника — 0;
##  5) число цветов вне PixelPalette — только унаследованные (печать).

const S := 16          # клетка (канон H=16)
const M := 48          # мастер
const PITCH := 50      # шаг колонки
const PAD := 2
const BAND := S + 4 + M + 8   # полоса: клетка + разделитель + мастер + цифры
const BOB := -1        # покачивание: 1 px вверх на pass/взмах-фазе
const PAL := preload("res://scripts/pixel_palette.gd")

const DIRS_HERO := ["down", "left", "right", "up"]
const ROW_OF_DIR := {"down": 0, "left": 1, "right": 2, "up": 3}

var _img: Image

# ---------- раскладка фаз ----------

func _phase_spec(kind: String) -> Array:
	# 4 фазы цикла: [колонка атласа, вертикальный сдвиг]
	if kind == "hero":
		# contact/pass/contact/pass: стойка, шаг-1, стойка+подъём (pass), шаг-2
		return [[0, 0], [1, 0], [0, BOB], [2, 0]]
	# мглокрыс (полёт): парение, взмах+подъём, парение, взмах
	return [[0, 0], [1, BOB], [0, 0], [1, 0]]

# ---------- отрисовка ----------

func _copy_cell(src: Image, col: int, row: int, dx: int, dy: int, shift: int) -> void:
	for y in S:
		for x in S:
			var ys := y - shift
			if ys < 0 or ys >= S:
				continue
			var c := src.get_pixel(col * S + x, row * S + ys)
			if c.a > 0.5:
				_img.set_pixel(dx + x, dy + y, c)

func _master(src: Image, col: int, row: int, dx: int, dy: int, shift: int) -> void:
	for y in M:
		for x in M:
			var sy := y / 3 - shift
			if sy < 0 or sy >= S:
				continue
			var c := src.get_pixel(col * S + x / 3, row * S + sy)
			if c.a > 0.5:
				_img.set_pixel(dx + x, dy + y, c)

func _band(src: Image, kind: String, dirs: Array, top: int) -> void:
	var spec := _phase_spec(kind)
	var col := 0
	for d: String in dirs:
		var row := int(ROW_OF_DIR[d])
		for ph in 4:
			var x0 := PAD + col * PITCH
			var ix := x0 + (PITCH - S) / 2
			_frame(ix - 1, top - 1, ix + S, top + S, "STONE", 3)
			_copy_cell(src, int(spec[ph][0]), row, ix, top, int(spec[ph][1]))
			var mx := x0 + (PITCH - M) / 2
			var my := top + S + 4
			_hline(x0, x0 + PITCH - 1, top + S + 2, "STONE", 3)
			_master(src, int(spec[ph][0]), row, mx, my, int(spec[ph][1]))
			_hline(mx - 1, mx + M, my + M, "STONE", 3)
			_digit(x0 + PITCH / 2 - 1, my + M + 1, ph + 1)
			col += 1
		var sx := PAD + col * PITCH - 1
		_vline(sx, top - 1, top + BAND - 3, "PARCHMENT", 3)

# ---------- технические примитивы (вне спрайтов) ----------

func _hline(x0: int, x1: int, y: int, ramp: String, tone: int) -> void:
	for x in range(x0, x1 + 1):
		_img.set_pixel(x, y, PAL.c(ramp, tone))

func _vline(x: int, y0: int, y1: int, ramp: String, tone: int) -> void:
	for y in range(y0, y1 + 1):
		_img.set_pixel(x, y, PAL.c(ramp, tone))

func _frame(x0: int, y0: int, x1: int, y1: int, ramp: String, tone: int) -> void:
	_hline(x0, x1, y0, ramp, tone)
	_hline(x0, x1, y1, ramp, tone)
	_vline(x0, y0, y1, ramp, tone)
	_vline(x1, y0, y1, ramp, tone)

# цифры 1..4 — технический глиф 3×5 (камень OUTLINE), под мастером
const GLYPHS := {
	1: [".#.", "##.", ".#.", ".#.", "###"],
	2: ["##.", "..#", ".#.", "#..", "###"],
	3: ["##.", "..#", ".#.", "..#", "##."],
	4: ["#.#", "#.#", "###", "..#", "..#"],
}

func _digit(x: int, y: int, n: int) -> void:
	var g: Array = GLYPHS[n]
	for r in 5:
		var line := String(g[r])
		for cc in 3:
			if String(line[cc]) == "#":
				_img.set_pixel(x + cc, y + r, PAL.c("STONE", 3))

func _bake() -> void:
	var w := PAD * 2 + 16 * PITCH
	var h := PAD * 2 + BAND * 2
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_img.fill(PAL.SHEET.BG)
	var hero := Image.load_from_file("res://assets/class_warrior.png")
	hero.convert(Image.FORMAT_RGBA8)
	var rat := Image.load_from_file("res://assets/mobs_swarmling.png")
	rat.convert(Image.FORMAT_RGBA8)
	_band(hero, "hero", DIRS_HERO, PAD)
	_band(rat, "rat", ["down", "left"], PAD + BAND)

# ---------- самопроверки ----------

func _self_check() -> int:
	var fails := 0
	var hero := Image.load_from_file("res://assets/class_warrior.png")
	hero.convert(Image.FORMAT_RGBA8)
	var rat := Image.load_from_file("res://assets/mobs_swarmling.png")
	rat.convert(Image.FORMAT_RGBA8)
	var bgkey := PAL.SHEET.BG.to_argb32()
	var srcs := [
		[hero, "hero", DIRS_HERO, PAD],
		[rat, "rat", ["down", "left"], PAD + BAND],
	]
	# палитра источника (наследование цветов) + off-палитра источника
	var src_colors := {}
	var src_off_colors := {}
	var pal := PAL
	var keys := {}
	for k in pal.color_index():
		keys[k] = true
	for s in srcs:
		var img0: Image = s[0]
		for y in img0.get_height():
			for x in img0.get_width():
				var c0 := img0.get_pixel(x, y)
				if c0.a < 0.5:
					continue
				var k0 := c0.to_argb32()
				src_colors[k0] = true
				if not keys.has(pal.key(c0)):
					src_off_colors[k0] = true
	var new_colors := 0
	var clipped := 0
	var off_in_sheet := 0
	var bob_max := 0
	var n0 := 0
	for s in srcs:
		var img: Image = s[0]
		var kind := String(s[1])
		var dirs: Array = s[2]
		var top := int(s[3])
		var spec := _phase_spec(kind)
		var col := 0
		for d: String in dirs:
			var row := int(ROW_OF_DIR[d])
			var x0 := PAD + col * PITCH
			var ix := x0 + (PITCH - S) / 2
			# 1) фаза 0 == стойка побайтово (прозрачное — фон листа)
			var same := true
			for y in S:
				for x in S:
					var a := _img.get_pixel(ix + x, top + y)
					var b := img.get_pixel(x, row * S + y)
					if b.a > 0.5:
						if a.to_argb32() != b.to_argb32():
							same = false
					elif a.to_argb32() != bgkey:
						same = false
			if same:
				n0 += 1
			else:
				print("SELF-CHECK FAIL %s/%s: фаза 0 != стойка" % [kind, d])
				fails += 1
			for ph in 4:
				var cx := PAD + col * PITCH
				var i1 := cx + (PITCH - S) / 2
				var scol := int(spec[ph][0])
				var shift := int(spec[ph][1])
				bob_max = maxi(bob_max, absi(shift))
				# 2) сдвиг не срезает содержимое источника
				if shift < 0:
					for yy in range(0, -shift):
						for x in S:
							if img.get_pixel(scol * S + x, row * S + yy).a > 0.5:
								clipped += 1
				# каждая фаза == копия источника со сдвигом; фон — BG
				var bad := 0
				var src_ink := 0
				for y in S:
					for x in S:
						if img.get_pixel(scol * S + x, row * S + y).a > 0.5:
							src_ink += 1
				if src_ink == 0:
					print("SELF-CHECK FAIL %s/%s p%d: пустой исходный кадр col%d" % [kind, d, ph, scol])
					fails += 1
				for y in S:
					for x in S:
						var c := _img.get_pixel(i1 + x, top + y)
						var sy := y - shift
						var exp: Color = (
							img.get_pixel(scol * S + x, row * S + sy)
							if sy >= 0 and sy < S else Color(0, 0, 0, 0)
						)
						if exp.a > 0.5:
							if c.to_argb32() != exp.to_argb32():
								bad += 1
							if not src_colors.has(c.to_argb32()):
								new_colors += 1
							elif not keys.has(pal.key(c)):
								off_in_sheet += 1
						elif c.to_argb32() != bgkey:
							bad += 1  # лишняя краска в клетке
				if bad > 0:
					print("SELF-CHECK FAIL %s/%s p%d: %d px вне канона копии" % [kind, d, ph, bad])
					fails += 1
				col += 1
	if clipped > 0:
		print("SELF-CHECK FAIL: сдвиг срезает содержимое в ", clipped, " px")
		fails += 1
	if bob_max > 1:
		print("SELF-CHECK FAIL: покачивание ", bob_max, " px > 1")
		fails += 1
	if new_colors > 0:
		print("SELF-CHECK FAIL: новых цветов против источника: ", new_colors)
		fails += 1
	print("METRIC phase0_eq_stance=", n0, "/6")
	print("METRIC bob_max_px=", bob_max)
	print("METRIC new_colors=", new_colors)
	print("METRIC off_palette_source_colors=", src_off_colors.size(),
		" (унаследовано от игрового арта; генератор новых не ввёл)")
	print("METRIC off_palette_px_in_cells=", off_in_sheet)
	if fails > 0:
		print("SELF-CHECK: %d FAIL" % fails)
		return 1
	print("SELF-CHECK PASS")
	return 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: sheet_walk_v1.gd -- <out.png>")
		quit(2)
		return
	_bake()
	var out := String(args[0])
	if not out.ends_with(".png"):
		out = out.path_join("sheet_walk_v1.png")
	var err := _img.save_png(out)
	if err != OK:
		print("SAVE FAIL ", err, " -> ", out)
		quit(3)
		return
	var rc := _self_check()
	print("saved ", out, " ", _img.get_width(), "x", _img.get_height())
	quit(rc)
