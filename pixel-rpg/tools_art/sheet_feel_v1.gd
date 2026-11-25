extends SceneTree
## Инструмент вердикт-листа «Ощущение v1» (волна «Мир v2: наполнение», W5, 25.11).
##
## ВЕРДИКТЫ ПОЛЬЗОВАТЕЛЯ: «бой скучноват, не хватает спецэффектов», «слизни
## страшные — исправь», «призраки надоедливые — замени механику, игра
## становится неприятной».
##
## ЛИСТ НА ВЕРДИКТ (закон ART): интеграция — ТОЛЬКО после «да». Игра сегодня:
## тряска Juice.shake(амп,с) уже есть (0.8..2.4 px), числа урона — Label-пул
## DmgNumbers (шрифт, крит 11px алое), искра fx_spark + CPUParticles в fx.gd,
## слизень — лист slime.png (2 кадра bob, тёмно-зелёный, глаза-точки),
## призрак «тенеплёт» — вечная погоня + фазы сквозь стены (mobs_wraith.png).
##
## СЕКЦИИ: A) VFX БОЯ (кадры+тайминги, кодо-рисованные, gl_compatibility:
## без GPU-частиц и shader-освещения): искра 4к, дуга взмаха 3 варианта по 3к,
## числа урона 2 размера с палитрным завалом, тряска табличкой (отключаемая
## настройкой), смерть моба вспышка-растворение 4к. B) СЛИЗЕНЬ НОВЫЙ: ниже,
## круглее, глаза-тарелки с белками, две антенны, дрожь 2 кадра; окрасы по
## биомам (лес/пустыня-степь/снег/подземелье), старый против нового.
## C) ПРИЗРАК «ТЕНЬ-ЗАИМКА»: не преследует дольше 3 c — вселяется в ближайшего
## моба (6 c: сильнее/быстрее), уязвим только в полёте вселения 1.5 c, удар по
## занятому изгоняет с оглушением 2 c, сквозь стены во вселенном состоянии НЕ
## ходит, спавн только подземелье/замок. Кадры вселения/оккупации/изгнания/
## оглушения + схема поведения + константы.
##
## Глифы игры (handjet) НЕ цитируются: цифры и подписи — собственный бортовой
## шрифт листа 3x5.
##
## Запуск:
##   Godot --headless --path pixel-rpg -s res://tools_art/sheet_feel_v1.gd -- <out.png>
## Выход 0 — самопроверки + STRICT-скан PASS (скан ДО сохранения: при провале
## файл не выкладывается), иначе 1.

const P := preload("res://scripts/pixel_palette.gd")

# тайминги кадра (мс) — печатаются в PINS_W5.md
const T_SPARK_MS := 40      # искра: 4 x 40 = 160 мс
const T_SWING_MS := 40      # дуга меча/магии: 3 x 40 = 120 мс
const T_CLUB_MS := 50       # дубина (телеграф бута): 3 x 50 = 150 мс
const T_DEATH_MS := 70      # смерть: 4 x 70 = 280 мс
const T_SLIME_MS := 350     # слизень: 2 x 350 = 700 мс дрожь
const T_POSSESS_MS := 180   # вселение: 4 x 180 = 720 мс (окно 1.5 c — два цикла)
const T_OCCUP_MS := 300     # оккупация: 2 x 300 = 600 мс пульс свечения
const T_BANISH_MS := 60     # изгнание: 3 x 60 = 180 мс
const T_STUN_MS := 250      # оглушение: 2 x 250 = 500 мс

# константы призрака «Тень-заимка» (предложение капитана, на вердикт)
const G_CHASE_S := 3.0      # погоня не дольше
const G_FLIGHT_S := 1.5     # окно вселения: единственный миг уязвимости
const G_HOLD_S := 6.0       # оккупация хозяина
const G_STUN_S := 2.0       # оглушение после изгнания
const G_HOST_R := 96.0      # радиус поиска хозяина, px
const G_BUFF_DMG := 1.5     # хозяин: урон
const G_BUFF_SPD := 1.4     # хозяин: скорость

var _fails := 0
var _allowed := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	# Диагностика: режим PAINTERS (второй аргумент после --) печатает ASCII
	# ключевых кадров и выходит, файл НЕ пишет. Нужен, когда vision-модель
	# недоступна: силуэты проверяются текстом.
	if args.has("PAINTERS"):
		_ascii_probe()
		quit(0)
		return
	var target := "res://tools_art/sheet_feel_v1.png"
	if args.size() > 0:
		target = String(args[0])
	_allowed = P.color_index().duplicate()
	for k in P.SHEET:
		_allowed[P.key(P.SHEET[k])] = ["SHEET", -1]
	var a := _build_sheet()
	var b := _build_sheet()
	var ident: bool = a.save_png_to_buffer() == b.save_png_to_buffer()
	print("[bake] double-bake byte-identical: %s" % ("PASS" if ident else "FAIL"))
	if not ident:
		_fails += 1
	if _strict_scan(a):
		var dirpos := target.rfind("/")
		if dirpos > 0:
			DirAccess.make_dir_recursive_absolute(
				target.substr(0, dirpos).replace("res://", ProjectSettings.globalize_path("res://") + "/"))
		var err := a.save_png(target)
		print("[save] %s err=%d pre-save hash %s" % [target, err, _fnv32_hex(a)])
		if err != OK:
			_fails += 1
	if _fails > 0:
		print("SELF-CHECK: FAIL (%d)" % _fails)
		quit(1)
	else:
		print("SELF-CHECK: PASS")
		quit(0)

func _c(rn: String, t: int) -> Color:
	return P.RAMPS[rn][t]

# ============================================================ A1: ИСКРА ПОПАДАНИЯ

func _spark(f: int) -> Image:
	var im := _im(16, 16)
	var C := 8
	match f:
		0:
			_put(im, C, C, P.FLATS["FIRE_HOT"])
			for d in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
				_put(im, C + d[0], C + d[1], _c("HUD_GOLD", P.T_LIGHT))
			for d in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
				_put(im, C + d[0], C + d[1], _c("HUD_GOLD", P.T_MID))
		1:
			_put(im, C, C, P.FLATS["FIRE_HOT"])
			for d in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
				_put(im, C + d[0], C + d[1], _c("HUD_GOLD", P.T_MID))
				_put(im, C + d[0] * 2, C + d[1] * 2, _c("CRYSTAL", P.T_LIGHT))
				_put(im, C + d[0] * 3, C + d[1] * 3, _c("CRYSTAL", P.T_MID))
			for d in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
				_put(im, C + d[0] * 2, C + d[1] * 2, _c("CHAR", P.T_DARK))
		2:
			for d in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
				_put(im, C + d[0], C + d[1], _c("HUD_GOLD", P.T_LIGHT))
				for k in [2, 3, 4]:
					_put(im, C + d[0] * k, C + d[1] * k, _c("CRYSTAL", P.T_MID))
				_put(im, C + d[0] * 5, C + d[1] * 5, _c("CRYSTAL", P.T_DARK))
			_put(im, C, C, _c("HUD_GOLD", P.T_DARK))
		3:
			for d in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
				_put(im, C + d[0] * 3, C + d[1] * 3, _c("CRYSTAL", P.T_DARK))
				_put(im, C + d[0] * 4, C + d[1] * 4, _c("CRYSTAL", P.T_OUTLINE))
			_put(im, C, C, _c("FIRE", P.T_DARK))
	return im

# ============================================================ A2: ДУГА ВЗМАХА

## Дуга вокруг кисти (cx,cy) радиуса r от a0 до a1 (градусы, y вверх).
func _arc(im: Image, cx: float, cy: float, r: float, a0: float, a1: float, col: Color) -> void:
	var n := int(maxf(4.0, absf(a1 - a0)))
	for i in n + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / float(n)))
		var x := int(round(cx + r * cos(a)))
		var y := int(round(cy - r * sin(a)))
		_put(im, x, y, col)

func _swing(kind: String, f: int) -> Image:
	var im := _im(16, 16)
	match kind:
		"sword":
			match f:
				0:
					_arc(im, 4.5, 12.0, 6.0, -20.0, 30.0, _c("IRON", P.T_MID))
					_put(im, 10, 7, _c("IRON", P.T_LIGHT))
				1:
					_arc(im, 4.5, 12.0, 8.0, -20.0, 100.0, _c("IRON", P.T_LIGHT))
					_arc(im, 4.5, 12.0, 7.0, -20.0, 100.0, _c("IRON", P.T_MID))
					_arc(im, 4.5, 12.0, 6.0, 0.0, 90.0, _c("IRON", P.T_DARK))
					_put(im, 4, 4, _c("HUD_GOLD", P.T_LIGHT))
					_put(im, 11, 7, _c("HUD_GOLD", P.T_LIGHT))
				2:
					_arc(im, 4.5, 12.0, 8.0, 40.0, 100.0, _c("IRON", P.T_LIGHT))
					_arc(im, 4.5, 12.0, 7.0, 50.0, 100.0, _c("IRON", P.T_DARK))
					_put(im, 2, 5, _c("IRON", P.T_LIGHT))
					_put(im, 5, 3, _c("IRON", P.T_OUTLINE))
					_put(im, 9, 4, _c("HUD_GOLD", P.T_DARK))
		"club":
			match f:
				0:
					_arc(im, 6.0, 13.5, 5.0, 20.0, 60.0, _c("WOOD", P.T_LIGHT))
				1:
					for rr in [5.0, 6.0, 7.0]:
						var tone := P.T_DARK
						if rr == 7.0:
							tone = P.T_LIGHT
						elif rr == 6.0:
							tone = P.T_MID
						_arc(im, 6.0, 13.5, rr, 20.0, 140.0, _c("WOOD", tone))
					_put(im, 1, 9, _c("BARK", P.T_LIGHT))
					_put(im, 12, 12, _c("BARK", P.T_MID))
				2:
					for rr in [6.0, 7.0]:
						_arc(im, 6.0, 13.5, rr, 90.0, 140.0, _c("WOOD", P.T_DARK))
					_put(im, 2, 7, _c("BARK", P.T_DARK))
					_put(im, 0, 10, _c("BARK", P.T_OUTLINE))
					_put(im, 5, 5, _c("WOOD", P.T_OUTLINE))
		"magic":
			match f:
				0:
					_arc(im, 7.0, 11.0, 7.0, -20.0, 40.0, _c("VIOLET", P.T_MID))
					_put(im, 14, 9, _c("CRYSTAL", P.T_LIGHT))
				1:
					_arc(im, 7.0, 11.0, 8.0, -20.0, 155.0, _c("VIOLET", P.T_MID))
					_arc(im, 7.0, 11.0, 7.0, 20.0, 135.0, _c("VIOLET", P.T_DARK))
					for a_0 in [10, 60, 110, 150]:
						var a := deg_to_rad(float(a_0))
						_put(im, int(round(7.0 + 8.0 * cos(a))), int(round(11.0 - 8.0 * sin(a))), _c("CRYSTAL", P.T_LIGHT))
				2:
					_arc(im, 7.0, 11.0, 8.0, 70.0, 155.0, _c("VIOLET", P.T_LIGHT))
					_put(im, 2, 5, _c("VIOLET", P.T_LIGHT))
					_put(im, 6, 2, _c("CRYSTAL", P.T_MID))
					_put(im, 10, 3, _c("CRYSTAL", P.T_DARK))
	return im

# ============================================================ A3: ЦИФРЫ УРОНА

## Цифры бортовым шрифтом: тело + теневой слой (завал палитрой), глифы игры не
## цитируются — собственный 3x5 листа.
func _nums(txt: String, sc: int, body: Color, shadow: Color) -> Image:
	var w: int = txt.length() * 4 * sc + 2
	var im := _im(w, 5 * sc + 3)
	_txt16(im, 0, 2, txt, sc, shadow, 1, 1)
	_txt16(im, 0, 2, txt, sc, body, 0, 0)
	return im

func _txt16(im: Image, x0: int, y0: int, txt: String, sc: int, col: Color, ox: int, oy: int) -> void:
	var x := x0
	for ch in txt.to_upper():
		var g = FONT.get(ch)
		if g != null:
			for r in 5:
				for c in 3:
					if String(g[r])[c] == "1":
						for dy in sc:
							for dx in sc:
								_put(im, x + c * sc + dx + ox, y0 + r * sc + dy + oy, col)
		x += 4 * sc

# ============================================================ A4: ТРЯСКА (волна)

func _shake_wave() -> Image:
	var im := _im(232, 64)
	var mid := 32
	for x in 220:
		var env := 1.0 - float(x) / 220.0
		var hi := mid - int(round(env * 24.0))
		var lo := mid + int(round(env * 24.0))
		if x % 3 == 0:
			_put(im, x + 6, hi, _c("IRON", P.T_DARK))
			_put(im, x + 6, lo, _c("IRON", P.T_DARK))
		var n: float = sin(float(x) * 0.9) * 0.6 + sin(float(x) * 0.31) * 0.4
		var y := mid - int(round(n * env * 24.0))
		_put(im, x + 6, y, _c("UI_BLUE", P.T_LIGHT))
		_put(im, x + 6, y + 1, _c("UI_BLUE", P.T_MID))
	return im

# ============================================================ A5: СМЕРТЬ-РАСТВОРЕНИЕ

## Растворение нового слизня (лес): k0 вспышка, k1..k3 осыпание углём.
## Детерминизм: фиксированный seed 2511 — двойной bake побайтово идентичен.
func _dissolve(f: int) -> Image:
	var body := _slime("LEAF", "LEAF", "HUD_GOLD", 0)
	var im := _im(16, 16)
	var keep: int = [10, 7, 4, 2][f]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2511
	for y in 16:
		for x in 16:
			var col := body.get_pixel(x, y)
			if col.a < 0.5:
				continue
			if f == 0:
				_put(im, x, y, _c("BONE", P.T_LIGHT))
			elif rng.randi_range(0, 9) < keep:
				_put(im, x, y, col)
			var r2 := rng.randi_range(0, 9)
			if f > 0 and r2 < 0:
				pass  # резерв ветки: осыпь рисуется speck-рядом ниже
	if f >= 1:
		var drift: int = [0, 1, 2, 3][f]
		for s in [[3, 6 - drift], [7, 5 - drift], [11, 6 - drift], [5, 4 - drift], [9, 3 - drift]]:
			var sx: int = int(s[0])
			var sy: int = int(s[1])
			var hot: Color = _c("ASH_EMBER", P.T_MID)
			if f == 3:
				hot = _c("ASH_EMBER", P.T_LIGHT)
			elif (sx + sy) % 2 == 0:
				hot = _c("ASH_GROUND", P.T_DARK)
			_put(im, sx, sy, hot)
	return im

# ============================================================ B: СЛИЗЕНЬ НОВЫЙ

## Новый слизень: низкий широкий купол, глаза-тарелки с белками и зрачками,
## улыбка, два рожка-антенны; frame1 — присед-дрожь (ниже на 1, шире на 1).
func _slime(pal: String, stalk: String, dot: String, frame: int) -> Image:
	var im := _im(16, 16)
	var L := _c(pal, P.T_LIGHT)
	var M := _c(pal, P.T_MID)
	var D := _c(pal, P.T_DARK)
	var O := _c(pal, P.T_OUTLINE)
	var w: Color = _c("BONE", P.T_LIGHT)
	var pup: Color = _c("CHAR", P.T_DARK)
	if frame == 0:
		# антенны
		_put(im, 6, 6, _c(stalk, P.T_DARK))
		_put(im, 9, 6, _c(stalk, P.T_DARK))
		_put(im, 6, 5, _c(dot, P.T_LIGHT))
		_put(im, 9, 5, _c(dot, P.T_LIGHT))
		# купол: 7..14
		_span(im, 6, 9, 7, L)
		_span(im, 5, 10, 8, L)
		_span(im, 4, 11, 9, M)
		_span(im, 3, 12, 10, M)
		_span(im, 3, 12, 11, M)
		_span(im, 2, 13, 12, M)
		_span(im, 2, 13, 13, D)
		_span(im, 3, 12, 14, O)
		_put(im, 1, 12, O)
		_put(im, 14, 12, O)
		_put(im, 2, 14, O)
		_put(im, 13, 14, O)
		# блик
		_put(im, 6, 8, _c("BONE", P.T_LIGHT))
		# глаза-тарелки (широко, по-дурацки мило)
		_rect16(im, 4, 9, 5, 10, w)
		_rect16(im, 10, 9, 11, 10, w)
		_put(im, 5, 10, pup)
		_put(im, 10, 10, pup)
		# улыбка
		_put(im, 6, 12, pup)
		_put(im, 7, 13, pup)
		_put(im, 8, 13, pup)
		_put(im, 9, 12, pup)
	else:
		# присед: купол на ряд ниже, основание шире; кончики антенн разъехались
		_put(im, 5, 5, _c(dot, P.T_LIGHT))
		_put(im, 6, 6, _c(stalk, P.T_DARK))
		_put(im, 10, 5, _c(dot, P.T_LIGHT))
		_put(im, 9, 6, _c(stalk, P.T_DARK))
		_span(im, 5, 10, 8, L)
		_span(im, 4, 11, 9, L)
		_span(im, 3, 12, 10, M)
		_span(im, 2, 13, 11, M)
		_span(im, 1, 14, 12, M)
		_span(im, 1, 14, 13, D)
		_span(im, 2, 13, 14, O)
		_put(im, 0, 13, O)
		_put(im, 15, 13, O)
		_put(im, 1, 14, O)
		_put(im, 14, 14, O)
		_put(im, 6, 9, _c("BONE", P.T_LIGHT))
		_rect16(im, 4, 10, 5, 11, w)
		_rect16(im, 10, 10, 11, 11, w)
		_put(im, 5, 11, pup)
		_put(im, 10, 11, pup)
		_put(im, 6, 13, pup)
		_put(im, 7, 13, pup)
		_put(im, 8, 13, pup)
		_put(im, 9, 13, pup)
	return im

# ============================================================ C: ПРИЗРАК

## Мини-хозяин (правая половина клетки): купол 8 px, для клеток призрака.
func _host_mini(hurt: bool) -> Image:
	var im := _im(16, 16)
	var L := _c("LEAF", P.T_LIGHT)
	var M := _c("LEAF", P.T_MID)
	var D := _c("LEAF", P.T_DARK)
	var O := _c("LEAF", P.T_OUTLINE)
	_span(im, 11, 14, 9, L)
	_span(im, 10, 15, 10, M)
	_span(im, 9, 15, 11, M)
	_span(im, 8, 15, 12, M)
	_span(im, 8, 15, 13, D)
	_span(im, 9, 14, 14, O)
	if hurt:
		# свечение занятого: кант + глаза призрака
		var rim: Color = _c("VIOLET", P.T_LIGHT)
		_put(im, 11, 8, rim)
		_put(im, 14, 8, rim)
		_put(im, 8, 11, rim)
		_put(im, 15, 11, rim)
		_put(im, 11, 11, _c("CRYSTAL", P.T_LIGHT))
		_put(im, 13, 11, _c("CRYSTAL", P.T_LIGHT))
	return im

## Призрак: капюшон + волнистый подол; вид stretched(сжат к хозяину) /
## slumped(ошмёток со звёздами). Глаза CRYSTAL — фирменная «призрачная пара».
func _ghost(kind: String, f: int) -> Image:
	var im := _im(16, 16)
	var M := _c("VIOLET", P.T_MID)
	var D := _c("VIOLET", P.T_DARK)
	var O := _c("VIOLET", P.T_OUTLINE)
	var eye := _c("CRYSTAL", P.T_LIGHT)
	if kind == "stretched":
		# капля, сжимающаяся к хозяину (справа внизу)
		var sh: Array = [[2, 0], [1, 1], [0, 1]][mini(f, 2)]
		var ox: int = int(sh[0])
		var oy: int = int(sh[1])
		_span(im, 3 + ox, 6 + ox, 3 + oy, D)
		_span(im, 2 + ox, 7 + ox, 4 + oy, M)
		_span(im, 2 + ox, 7 + ox, 5 + oy, M)
		_span(im, 3 + ox, 6 + ox, 6 + oy, D)
		_put(im, 3 + ox, 4 + oy, eye)
		_put(im, 6 + ox, 4 + oy, eye)
	elif kind == "slumped":
		_span(im, 4, 11, 10, D)
		_span(im, 3, 12, 11, M)
		_span(im, 3, 12, 12, M)
		_span(im, 4, 11, 13, O)
		_put(im, 5, 11, _c("VIOLET", P.T_LIGHT))
		_put(im, 6, 11, _c("VIOLET", P.T_LIGHT))
		_put(im, 9, 11, _c("VIOLET", P.T_LIGHT))
		_put(im, 10, 11, _c("VIOLET", P.T_LIGHT))
		# звёздочки кружатся
		if f == 0:
			_star(im, 5, 7)
			_star(im, 11, 8)
			_put(im, 3, 9, _c("UI_BLUE", P.T_MID))
		else:
			_star(im, 9, 6)
			_star(im, 4, 9)
			_put(im, 13, 9, _c("UI_BLUE", P.T_MID))
	return im

func _star(im: Image, x: int, y: int) -> void:
	var g: Color = _c("HUD_GOLD", P.T_LIGHT)
	_put(im, x, y, g)
	_put(im, x - 1, y, _c("HUD_GOLD", P.T_MID))
	_put(im, x + 1, y, _c("HUD_GOLD", P.T_MID))
	_put(im, x, y - 1, _c("HUD_GOLD", P.T_MID))
	_put(im, x, y + 1, _c("HUD_GOLD", P.T_MID))

## Клетка вселения: призрак слева, хозяин справа, нить CRYSTAL жиреет, рвётся.
func _possession_cell(f: int) -> Image:
	var im := _im(16, 16)
	_blit_into(im, _host_mini(f >= 2), 0, 0, 1)
	if f < 3:
		_blit_into(im, _ghost("stretched", f), 0, 0, 1)
	var pts := [[5, 7], [6, 7], [6, 8], [7, 8], [7, 9], [8, 9]]
	var take: int = [2, 4, 6, 0][f]
	for i in take:
		_put(im, int(pts[i][0]), int(pts[i][1]), _c("CRYSTAL", P.T_LIGHT))
	return im

## Клетка оккупации: хозяин светится кантом VIOLET + глаза призрака; f — пульс.
func _occupied_cell(f: int) -> Image:
	var im := _blank_host_frame(f)
	return im

## Общий кадр занятого хозяина с пульсом канта.
func _blank_host_frame(f: int) -> Image:
	var im := _im(16, 16)
	_blit_into(im, _host_mini(false), 0, 0, 1)
	var rim: Color = _c("VIOLET", P.T_LIGHT) if f == 0 else _c("VIOLET", P.T_MID)
	for p in [[11, 8], [14, 8], [8, 11], [15, 11], [9, 14], [14, 14]]:
		_put(im, int(p[0]), int(p[1]), rim)
	var eye: Color = _c("CRYSTAL", P.T_LIGHT) if f == 0 else _c("CRYSTAL", P.T_MID)
	_put(im, 11, 11, eye)
	_put(im, 13, 11, eye)
	return im

## Клетка изгнания: вспышка на хозяине, клочок призрака летит влево-вверх.
func _banish_cell(f: int) -> Image:
	var im := _im(16, 16)
	# пустой хозяин без свечения (призрак выгнан)
	var M := _c("LEAF", P.T_MID)
	_span(im, 11, 14, 9, _c("LEAF", P.T_LIGHT))
	_span(im, 10, 15, 10, M)
	_span(im, 9, 15, 11, M)
	_span(im, 8, 15, 12, M)
	_span(im, 8, 15, 13, _c("LEAF", P.T_DARK))
	_span(im, 9, 14, 14, _c("LEAF", P.T_OUTLINE))
	if f == 0:
		_star(im, 9, 8)
		for d in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
			_put(im, 9 + d[0] * 2, 8 + d[1] * 2, _c("BONE", P.T_LIGHT))
		_put(im, 4, 4, _c("VIOLET", P.T_MID))
		_put(im, 5, 4, _c("VIOLET", P.T_MID))
		_put(im, 4, 5, _c("VIOLET", P.T_DARK))
	if f == 1:
		_put(im, 3, 3, _c("VIOLET", P.T_MID))
		_put(im, 4, 3, _c("VIOLET", P.T_DARK))
		_put(im, 6, 5, _c("CRYSTAL", P.T_MID))
		_put(im, 7, 6, _c("CRYSTAL", P.T_DARK))
	if f == 2:
		_put(im, 1, 2, _c("VIOLET", P.T_DARK))
		_put(im, 4, 4, _c("CRYSTAL", P.T_OUTLINE))
	return im

# ============================================================ примитивы

func _put(im: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, col)

func _span(im: Image, x0: int, x1: int, y: int, col: Color) -> void:
	for x in range(x0, x1 + 1):
		_put(im, x, y, col)

func _rect16(im: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_put(im, x, y, col)

func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

func _blit_into(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var col := src.get_pixel(x, y)
			if col.a < 0.5:
				continue
			for dy in sc:
				for dx in sc:
					_put(dst, x0 + x * sc + dx, y0 + y * sc + dy, col)

func _blit_sc(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	_blit_into(dst, src, x0, y0, sc)

# ============================================================ лист

func _build_sheet() -> Image:
	var W := 720
	var sheet := _im(W, 1140)
	sheet.fill(P.SHEET["BG"])
	var x0 := 10
	var y := 8
	_text(sheet, x0, y, "FEEL V1 - COMBAT VFX / NEW SLIME / GHOST TENANT SHADOW - VERDICT SHEET - NOT INTEGRATED - W5 25.11", 2, P.SHEET["TEXT"])
	y += 16
	_text(sheet, x0, y, "USER VERDICTS - COMBAT TOO DRY - SLIMES TOO SCARY - GHOSTS NAGGY MAKE GAME UNPLEASANT", 1, P.SHEET["LINE"])
	y += 9
	_text(sheet, x0, y, "CODE ART ONLY - PALETTE DELTA EMPTY - NO GPU PARTICLES NO SHADER LIGHT - GL_COMPATIBILITY", 1, P.SHEET["LINE"])
	y += 14

	# ---- A1 искра
	_text(sheet, x0, y, "A1 - HIT SPARK - 4F X 40MS = 160MS - CRYSTAL RAYS - HUD GOLD HOT CORE - CHAR SOOT", 1, P.SHEET["TEXT"])
	y += 10
	var strips: Array = []
	for f in 4:
		var im := _spark(f)
		_check_fx(im, "spark%d" % f)
		strips.append({"name": "K%d" % f, "img": im})
	y = _strip(sheet, strips, 3, x0, y)

	# ---- A2 дуги
	_text(sheet, x0, y, "A2 - SWING ARC - 3 VARIANTS X 3F - THE SWING BECOMES SEEN (REACH READABLE)", 1, P.SHEET["TEXT"])
	y += 10
	var kinds := [["sword", "IRON CRESCENT 3F X 40MS - WARRIOR"], ["club", "WOOD BAND 3F X 50MS - BRUTE TELEGRAPH"], ["magic", "VIOLET RING 3F X 40MS - MAGE"]]
	for ki in range(kinds.size()):
		var kk: Array = kinds[ki]
		var row: Array = []
		for f in 3:
			var im := _swing(String(kk[0]), f)
			_check_fx(im, "swing_%s%d" % [kk[0], f])
			row.append({"name": "K%d" % f, "img": im})
		_text(sheet, x0, y + 4, String(kk[1]), 1, P.SHEET["LINE"])
		_strip(sheet, row, 3, x0 + 330, y)
		y += 64

	# ---- A3 числа
	_text(sheet, x0, y, "A3 - DAMAGE NUMBERS - TWO SIZES - PALETTE RAMP BODY PLUS SHADOW - GAME GLYPHS NOT QUOTED (BUILT-IN 3X5)", 1, P.SHEET["TEXT"])
	y += 10
	var n1 := _nums("7", 2, _c("BONE", P.T_LIGHT), _c("PATH", P.T_DARK))
	var n2 := _nums("12", 2, _c("BONE", P.T_LIGHT), _c("PATH", P.T_DARK))
	var c1 := _nums("34", 3, _c("HUD_GOLD", P.T_LIGHT), _c("HP_RED", P.T_MID))
	_check_fx(n1, "num_normal")
	_check_fx(c1, "num_crit")
	_blit_into(sheet, n1, x0, y, 1)
	_blit_into(sheet, n2, x0 + 40, y, 1)
	_blit_into(sheet, c1, x0 + 110, y - 2, 1)
	_text(sheet, x0 + 200, y + 2, "NORMAL BONE LIGHT BODY PATH DARK SHADOW - TODAY 9PX BONE FONT", 1, P.SHEET["LINE"])
	_text(sheet, x0 + 200, y + 12, "CRIT HUD GOLD BODY HP RED SHADOW - TODAY 11PX SCARLET - DISCIPLINE RED IS FATAL ONLY", 1, P.SHEET["LINE"])
	y += 36
	_text(sheet, x0, y, "INTEGRATION - SHADOW = SECOND POOLED LABEL OFFSET 1PX - NO SHADER - SIZES 9 AND 11 KEPT", 1, P.SHEET["LINE"])
	y += 14

	# ---- A4 тряска
	_text(sheet, x0, y, "A4 - SCREEN SHAKE - JUICE EXISTS - TABLE PROPOSED - TOGGLE IN SETTINGS (OFF = AMP 0)", 1, P.SHEET["TEXT"])
	y += 10
	var wave := _shake_wave()
	_check_fx(wave, "shake_wave")
	_blit_into(sheet, wave, x0, y, 1)
	_text(sheet, x0 + 250, y + 4, "ENVELOPE LINEAR - NOISE FASTNOISE2D (TODAY IN JUICE)", 1, P.SHEET["LINE"])
	_text(sheet, x0 + 250, y + 14, "LIGHT 0.8PX 90MS MOB HIT - TODAY", 1, P.SHEET["LINE"])
	_text(sheet, x0 + 250, y + 24, "MEDIUM 1.2PX 120MS BRUTE OR BOSS DEATH - TODAY", 1, P.SHEET["LINE"])
	_text(sheet, x0 + 250, y + 34, "HEAVY 1.6PX 140MS HERO HIT - TODAY", 1, P.SHEET["LINE"])
	_text(sheet, x0 + 250, y + 44, "FATAL 2.4PX 220MS HERO DEATH - TODAY", 1, P.SHEET["LINE"])
	_text(sheet, x0 + 250, y + 54, "BANISH 1.0PX 100MS GHOST EXPELLED - NEW", 1, P.SHEET["LINE"])
	y += 74

	# ---- A5 смерть
	_text(sheet, x0, y, "A5 - MOB DEATH - FLASH PLUS DISSOLVE - 4F X 70MS = 280MS - NEW SLIME AS MODEL VICTIM", 1, P.SHEET["TEXT"])
	y += 10
	var drow: Array = []
	for f in 4:
		var im := _dissolve(f)
		_check_fx(im, "death%d" % f)
		drow.append({"name": "K%d" % f, "img": im})
	_blit_sc(sheet, drow[0]["img"], x0 + 500, y - 46, 3)
	y = _strip(sheet, drow, 3, x0, y)
	_text(sheet, x0, y, "K0 FLASH THEN ASH EMBER FALL - DETERMINISTIC SEED 2511 - ZOOM3 REFERENCE AT RIGHT", 1, P.SHEET["LINE"])
	y += 16

	# ---- B слизень
	_text(sheet, x0, y, "B - SLIME OLD VERSUS NEW - OLD CANON slime.png 2F BOB TALL DARK EYE DOTS READS SCARY", 1, P.SHEET["TEXT"])
	y += 10
	var old_tex: Texture2D = load("res://assets/slime.png")
	var old0 := old_tex.get_image().get_region(Rect2i(0, 0, 16, 16))
	var old1 := old_tex.get_image().get_region(Rect2i(16, 0, 16, 16))
	_blit_sc(sheet, old0, x0, y, 3)
	_blit_sc(sheet, old1, x0 + 64, y, 3)
	_text(sheet, x0 + 150, y + 6, "OLD K0 - EYES ARE DARK DOTS - NO WHITES", 1, P.SHEET["LINE"])
	_text(sheet, x0 + 150, y + 16, "OLD K1 - TALL BOB - READS ANGRY", 1, P.SHEET["LINE"])
	var nx := x0 + 460
	var sl0 := _slime("LEAF", "LEAF", "HUD_GOLD", 0)
	var sl1 := _slime("LEAF", "LEAF", "HUD_GOLD", 1)
	_check_fx(sl0, "slime_new0")
	_check_fx(sl1, "slime_new1")
	_blit_sc(sheet, sl0, nx, y, 3)
	_blit_sc(sheet, sl1, nx + 64, y, 3)
	_text(sheet, nx - 150, y + 6, "NEW IDLE AND SQUAT - 6PX LOW DOME", 1, P.SHEET["LINE"])
	_text(sheet, nx - 150, y + 16, "BIG WHITE EYES WIDE SET - SMILE", 1, P.SHEET["LINE"])
	_text(sheet, nx - 150, y + 26, "TWO ANTENNAE - TREMBLE 2F X 350MS", 1, P.SHEET["LINE"])
	y += 58
	# биома
	_text(sheet, x0, y, "BIOME COATS - SAME SHAPE PALETTE SWAP - PIPELINE mob_variants_v1 EXISTS (MD5 PIN AT BAKE)", 1, P.SHEET["LINE"])
	y += 10
	var biomes := [["LEAF", "LEAF", "HUD_GOLD", "FOREST LEAF RAMP"], ["PATH", "PATH", "BRONZE", "DESERT STEPPE PATH WARM"], ["WATER", "WATER", "CRYSTAL", "SNOW WATER RAMP ICE"], ["MOSS_GLOW", "MOSS_GLOW", "VIOLET", "DUNGEON MOSS GLOW GENTLE"]]
	var bx := x0
	for bi in range(biomes.size()):
		var b: Array = biomes[bi]
		var im := _slime(String(b[0]), String(b[1]), String(b[2]), 0)
		_check_fx(im, "slime_biome%d" % bi)
		_blit_sc(sheet, im, bx, y, 2)
		_text(sheet, bx, y + 36, String(b[3]), 1, P.SHEET["LINE"])
		bx += 170
	y += 54
	_text(sheet, x0, y, "POISON NOT GROTESQUE - NO DRIP PIXELS NO SKULL - FRIENDLY SILHOUETTE DECIDES THE VERDICT", 1, P.SHEET["LINE"])
	y += 16

	# ---- C призрак
	_text(sheet, x0, y, "C - GHOST TENANT SHADOW - TODAY IT CHASES FOREVER AND PHASES THROUGH WALLS (TENEPLYOT)", 1, P.SHEET["TEXT"])
	y += 10
	var wr: Texture2D = load("res://assets/mobs_wraith.png")
	var wimg := wr.get_image().get_region(Rect2i(0, 0, 16, 16))
	_blit_sc(sheet, wimg, x0, y, 3)
	_text(sheet, x0 + 60, y + 6, "OLD FRAME - BEHAVIOR BELOW REPLACES IT (SPRITES MAY STAY)", 1, P.SHEET["LINE"])
	y += 58
	_text(sheet, x0, y, "POSSESSION FLIGHT - 4F X 180MS - WINDOW 1.5S - ONLY MOMENT THE WRAITH CAN BE HURT", 1, P.SHEET["TEXT"])
	y += 10
	var px0 := x0
	for f in 4:
		var im := _possession_cell(f)
		_check_fx(im, "possess%d" % f)
		_blit_sc(sheet, im, px0, y, 2)
		px0 += 44
	y += 36
	_text(sheet, x0, y, "OCCUPIED - HOST BUFF DMG X1.5 SPD X1.4 FOR 6S - NO WALL PHASE - GHOST EYES ON HOST", 1, P.SHEET["TEXT"])
	y += 10
	for f in 2:
		var im := _occupied_cell(f)
		_check_fx(im, "occupied%d" % f)
		_blit_sc(sheet, im, x0 + f * 44, y, 2)
	y += 36
	_text(sheet, x0, y, "BANISH - HIT ON OCCUPIED HOST - 3F X 60MS - WRAITH FLIES OFF IN AN ARC", 1, P.SHEET["TEXT"])
	y += 10
	px0 = x0
	for f in 3:
		var im := _banish_cell(f)
		_check_fx(im, "banish%d" % f)
		_blit_sc(sheet, im, px0, y, 2)
		px0 += 44
	y += 36
	_text(sheet, x0, y, "STUN - 2S - NO PHASE - CAN BE HIT FREELY - FAIR ANTI WINDOW (GOLD STARS)", 1, P.SHEET["TEXT"])
	y += 10
	for f in 2:
		var im := _ghost("slumped", f)
		_check_fx(im, "stun%d" % f)
		_blit_sc(sheet, im, x0 + f * 44, y, 2)
	y += 40

	# схема поведения
	_text(sheet, x0, y, "BEHAVIOR SCHEME", 1, P.SHEET["TEXT"])
	y += 8
	_box(sheet, x0, y, 150, 44, ["MATERIALIZED 3S", "CHASE SLOW - LEASH 110"])
	_arrow(sheet, x0 + 154, y + 20, 26)
	_box(sheet, x0 + 184, y, 150, 44, ["FLIGHT 1.5S", "ONLY HARM WINDOW"])
	_arrow(sheet, x0 + 338, y + 20, 26)
	_box(sheet, x0 + 368, y, 168, 44, ["OCCUPIED 6S", "HOST STRONG - NO WALLS"])
	_hline_px(sheet, x0 + 259, x0 + 452, y + 52, P.SHEET["LINE"])
	_vline_px(sheet, x0 + 259, y + 44, y + 52, P.SHEET["LINE"])
	_text(sheet, x0 + 270, y + 56, "HIT EXPELS TO STUN 2S - OR 6S PASS - WRAITH RESURFACES NEAR HOST", 1, P.SHEET["LINE"])
	y += 70
	var cons := [
		"CHASE MAX 3.0S - FLIGHT VULNERABLE WINDOW 1.5S - HOLD 6.0S - STUN 2.0S",
		"HOST SEARCH RADIUS 96PX - BUFF DMG X1.5 - BUFF SPD X1.4",
		"SPAWN DUNGEON AND CASTLE ONLY - CAVE NICHE AND ASHEN ROWS DROP AT INTEGRATION",
		"WALL PHASE ONLY IN FLIGHT - NEVER WHILE OCCUPIED OR STUNNED",
	]
	for c_line in cons:
		_text(sheet, x0, y, c_line, 1, P.SHEET["LINE"])
		y += 9

	# ---- честность
	y += 8
	_text(sheet, x0, y, "IN GAME TODAY - JUICE SHAKE EXISTS - DMGNUMBERS FONT POOL EXISTS - CPUPARTICLES FX EXIST", 1, P.SHEET["TEXT"])
	y += 9
	_text(sheet, x0, y, "THIS SHEET ADDS FRAMES AND TABLES - INTEGRATION ONLY AFTER VERDICT - LAW ART", 1, P.SHEET["TEXT"])
	return sheet

## Ряд кадров: blit sc, подписи; возвращает y после ряда.
func _strip(sheet: Image, items: Array, sc: int, x: int, y: int) -> int:
	var xx := x
	for it in items:
		var im: Image = it["img"]
		_blit_sc(sheet, im, xx, y, sc)
		_text(sheet, xx, y + 16 * sc + 3, String(it["name"]), 1, P.SHEET["LINE"])
		xx += 16 * sc + 8
	return y + 16 * sc + 14

## Режим PAINTERS: ASCII-печатает ключевые кадры (проверка силуэтов без
## vision-модели). Вызывается из _init, файл не трогает.
func _ascii_probe() -> void:
	_ascii_dump(_slime("LEAF", "LEAF", "HUD_GOLD", 0), "slime idle")
	_ascii_dump(_slime("LEAF", "LEAF", "HUD_GOLD", 1), "slime squat")
	_ascii_dump(_spark(1), "spark1")
	_ascii_dump(_swing("sword", 1), "sword1")
	_ascii_dump(_swing("club", 1), "club1")
	_ascii_dump(_swing("magic", 1), "magic1")
	_ascii_dump(_dissolve(1), "death1")
	_ascii_dump(_possession_cell(1), "possess1")
	_ascii_dump(_occupied_cell(0), "occupied0")
	_ascii_dump(_banish_cell(0), "banish0")
	_ascii_dump(_ghost("slumped", 0), "stun0")

func _ascii_dump(img: Image, title: String) -> void:
	print("== " + title)
	for y in img.get_height():
		var row := ""
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				row += "."
			elif c.v < 0.25:
				row += "#"
			elif c.v < 0.55:
				row += "+"
			elif c.v < 0.8:
				row += "o"
			else:
				row += "O"
		print(row)

func _check_fx(im: Image, nm: String) -> void:
	var n := 0
	var off := 0
	for yy in im.get_height():
		for xx in im.get_width():
			var col := im.get_pixel(xx, yy)
			if col.a < 0.5:
				continue
			n += 1
			if not _allowed.has(P.key(col)):
				off += 1
	var ok: bool = n >= 6 and off == 0
	print("[fx] %-16s px:%3d off:%d %s hash:%s" % [nm, n, off, ("PASS" if ok else "FAIL"), _fnv32_hex(im)])
	if not ok:
		_fails += 1

func _box(sheet: Image, x: int, y0: int, w: int, h: int, lines: Array) -> void:
	_hline_px(sheet, x, x + w, y0, P.SHEET["LINE"])
	_hline_px(sheet, x, x + w, y0 + h, P.SHEET["LINE"])
	for yy in range(y0, y0 + h + 1):
		_px(sheet, x, yy, P.SHEET["LINE"])
		_px(sheet, x + w, yy, P.SHEET["LINE"])
	var ty := y0 + 6
	for t_0 in lines:
		_text(sheet, x + 5, ty, String(t_0), 1, P.SHEET["TEXT"])
		ty += 9

func _arrow(sheet: Image, x: int, y: int, ln: int) -> void:
	if ln <= 0:
		return
	for xx in range(x, x + ln):
		_px(sheet, xx, y, P.SHEET["TEXT"])
	_px(sheet, x + ln, y - 1, P.SHEET["TEXT"])
	_px(sheet, x + ln, y, P.SHEET["TEXT"])
	_px(sheet, x + ln, y + 1, P.SHEET["TEXT"])

func _hline_px(sheet: Image, xa: int, xb: int, y: int, col: Color) -> void:
	for xx in range(mini(xa, xb), maxi(xa, xb) + 1):
		_px(sheet, xx, y, col)

func _vline_px(sheet: Image, x: int, ya: int, yb: int, col: Color) -> void:
	for yy in range(mini(ya, yb), maxi(ya, yb) + 1):
		_px(sheet, x, yy, col)

# ============================================================ строгий скан / хэш

func _strict_scan(img: Image) -> bool:
	var off := 0
	var mask := 0
	for yy in img.get_height():
		for xx in img.get_width():
			var col := img.get_pixel(xx, yy)
			if col.a < 1.0:
				mask += 1
				continue
			if not _allowed.has(P.key(col)):
				off += 1
	var ok: bool = off == 0 and mask == 0
	print("[strict] sheet-wide %dx%d off=%d mask=%d %s" % [img.get_width(), img.get_height(), off, mask, ("PASS" if ok else "FAIL")])
	if not ok:
		_fails += 1
	return ok

func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

# ============================================================ бортовой шрифт 3x5
## Глифы игры НЕ цитируются: это собственный чертёжный шрифт инструмента
## (тот же эталон, что sheet_env_v1 / sheet_weapons_v1).

const FONT := {
	"A": ["111", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["111", "100", "100", "100", "111"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "111", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["111", "100", "101", "101", "111"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "111"],
	"K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "101", "101", "101"], "N": ["110", "101", "101", "101", "101"],
	"O": ["111", "101", "101", "101", "111"], "P": ["111", "101", "111", "100", "100"],
	"Q": ["111", "101", "101", "111", "011"], "R": ["111", "101", "110", "101", "101"],
	"S": ["111", "000", "111", "001", "111"], "T": ["111", "010", "010", "010", "010"],
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
	".": ["000", "000", "000", "000", "010"], "~": ["000", "011", "110", "000", "000"],
	"/": ["001", "001", "010", "100", "100"], ":": ["000", "010", "000", "010", "000"],
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

func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)
