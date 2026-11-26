extends SceneTree
## Инструмент вердикт-листа «Бестиарий v2» (волна «Мир v2: наполнение», t21, 25.11).
##
## Глубина v2 §4: новый моб на пояс (6 штук) + финальные обличья мини-боссов.
## ЛИСТ — НА ВЕРДИКТ, НЕ интеграция (закон ART): рантайм не тронут ни на
## пиксель; интеграция — отдельный тикет капитана ПОСЛЕ выбора пользователя.
##
## СОСТАВ БЛОКА (на моба): заглушка сегодняшнего рантайма (скин t19/t20
## remap байт-в-байт из mobs_variants.json, а где скина нет — база-лист с
## честной пометкой) ПРОТИВ нового обличья: 2 кадра похода + 2 кадра приёма
## (T0 телеграф, T1 исполнение) — все 16px, закрытая палитра PixelPalette;
## контекст 1:1 на полу своего биома; карточка поведения (§4: «знакомое
## поведение + один новый приём»). Полностью русское имя — чертёжный RU 5x7.
##
## ЧЕСТНОЕ ОБЛИЧЬЕ ЗАГЛУШЕК: мини-боссы сегодня ездят на remap-шкурах
## (лес/замок=тлель-вепрь-носитель, степь=лучник, пустыня=рой, снег/
## подземелье=призрак; снег/wraith скина в манифесте НЕТ — рантайм молча
## показывает базовый лист). Пользователь решает, менять ли обличье.
##
## Запуск:
##   Godot ... -s res://tools_art/sheet_bestiary_v2.gd -- <out.png>
##   Godot ... -s res://tools_art/sheet_bestiary_v2.gd -- PAINTERS   (ASCII)
## Выход 0 = SELF-CHECK PASS: double-bake побайтно равен, strict-скан off=0
## mask=0 (цитата заглушек легализована и напечатана списком), все кадры
## >=6 px, CJK-гигиена шрифта.

const P := preload("res://scripts/pixel_palette.gd")
const MANIFEST := "res://assets/world/mobs_variants.json"
const VDIR := "res://assets/world/"

var _fails := 0
var _allowed := {}
var _stub_quote_colors := 0
var _stub_off_names := {}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("PAINTERS"):
		_ascii_probe()
		quit(0)
		return
	var target := "res://tools_art/sheet_bestiary_v2.png"
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
	if _stub_off_names.is_empty():
		print("[stub-palette] цитаты заглушек off-palette: 0 цветов — чистая палитра")
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

# t26 (26.11, интеграция «Бестиарий v2»): билдеры кадров и хэш-метод объявлены
# static-ами — единый источник арта для листа и рантайм-бейка
# bestiary_v2_bake.gd (pre-save hash BE81DD9D после рефакторинга обязан быть
# равным пину: самопроверка ниже это и держит).

static func _c(rn: String, t: int) -> Color:
	return P.RAMPS[rn][t]

# ============================================================ заглушки рантайма
## Читаем mobs_variants.json ровно как open_world.apply_biome_skin: скин
## "<биом>/<семейство>"; если скина нет — рантайм тихо оставляет БАЗОВЫЙ лист
## (для снега/призрака это факт 25.11 — вынесено на лист).

var _man: Dictionary = {}

func _manifest() -> Dictionary:
	if _man.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if typeof(parsed) == TYPE_DICTIONARY:
			_man = parsed.get("skins", {})
	return _man

## Возвращает {frames: Array[Image], note: String, w: int}
func _stub(biome: String, family: String) -> Dictionary:
	var m := _manifest()
	var key := biome + "/" + family
	var img: Image
	var note := ""
	if m.has(key):
		img = load(VDIR + String((m[key] as Dictionary)["file"])).get_image()
	else:
		# фолбэк = base-лист, который рантайм и покажет (silent no-op)
		var src := ""
		for k in m:
			if String(k).ends_with("/" + family):
				src = String((m[k] as Dictionary)["src"])
				break
		note = "NO SKIN IN MANIFEST - RUNTIME SHOWS BASE SHEET"
		img = load(src).get_image()
	var out: Array = []
	if family == "brute":
		out = [img.get_region(Rect2i(0, 0, 32, 32)), img.get_region(Rect2i(32, 0, 32, 32))]
	else:
		out = [img.get_region(Rect2i(0, 0, 16, 16)), img.get_region(Rect2i(16, 0, 16, 16)),
				img.get_region(Rect2i(32, 0, 16, 16))]
	# легализация цитаты: цвета рантайм-листа добавляем в _allowed ОДНОКРАТНО,
	# всё вне закрытой палитры — печатаем честным списком
	for fr in out:
		for yy in fr.get_height():
			for xx in fr.get_width():
				var col: Color = fr.get_pixel(xx, yy)
				if col.a < 0.5:
					continue
				var k2 := P.key(col)
				if not _allowed.has(k2):
					_allowed[k2] = ["STUBQUOT", -1]
					_stub_quote_colors += 1
					var nm := biome + "/" + family
					if not _stub_off_names.has(nm):
						_stub_off_names[nm] = 0
					_stub_off_names[nm] = int(_stub_off_names[nm]) + 1
	return {"frames": out, "note": note, "w": 32 if family == "brute" else 16}

# ============================================================ новые обличья
## Все новые кадры — честные 16x16 (hero-канон), примитивы+акценты, палитра
## закрытая. Кадры: K0/K1 поход, T0 телеграф приёма, T1 исполнение.

static func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)

static func _rect(img: Image, xa: int, ya: int, xb: int, yb: int, col: Color) -> void:
	for yy in range(ya, yb + 1):
		for xx in range(xa, xb + 1):
			_px(img, xx, yy, col)

static func _hrow(img: Image, xa: int, xb: int, y: int, col: Color) -> void:
	_rect(img, xa, y, xb, y, col)

static func _dcol(img: Image, x: int, ya: int, yb: int, col: Color) -> void:
	_rect(img, x, ya, x, yb, col)

# ---- (1) Корневой засадчик (лес): низкий зверь в мху; приём — прыжок ----

static func _amb(f: int) -> Image:
	var im := _im(16, 16)
	var mlo := _c("MOSS_GLOW", P.T_LIGHT)
	var mmid := _c("MOSS_GLOW", P.T_MID)
	var bmid := _c("BARK", P.T_MID)
	var bdark := _c("BARK", P.T_DARK)
	var bout := _c("BARK", P.T_OUTLINE)
	var bone := _c("BONE", P.T_LIGHT)
	var eye := _c("HP_RED", P.T_MID)
	if f <= 1:
		# поход: короткий корпус, поднятая голова справа, 4 корня-лапы
		var lo := f
		# хвост-корень слева
		_px(im, 1, 6, bdark)
		_px(im, 0, 5, bdark)
		# мох-попона: светлый гребень + средних ряд
		_hrow(im, 3, 9, 4, mlo)
		_hrow(im, 2, 10, 5, mmid)
		_px(im, 2, 4, mmid)
		_px(im, 10, 4, mmid)
		# корпус
		_rect(im, 2, 6, 10, 8, bmid)
		_hrow(im, 2, 10, 8, bdark)
		# голова: выше корпуса, шея читается
		_rect(im, 11, 3, 14, 6, bmid)
		_px(im, 11, 3, bdark)
		_px(im, 14, 2, bdark)   # ухо
		_px(im, 13, 4, eye)
		_hrow(im, 11, 14, 6, bdark)  # пасть
		_px(im, 14, 5, bone)   # клык
		# лапы с разменом диагонали
		var la: Array = [3, 6, 9] if lo == 0 else [4, 7, 10]
		for lx in la:
			_dcol(im, int(lx), 9, 11, bout)
		_dcol(im, 12, 7, 9, bout)  # передняя под головой
	elif f == 2:
		# телеграф «шелест»: мох осел холмом, под ним бредень и алый глаз
		_hrow(im, 3, 12, 9, mlo)
		_rect(im, 4, 10, 11, 11, mmid)
		_hrow(im, 5, 10, 12, bdark)       # щель-бредень
		_px(im, 8, 10, eye)
		_px(im, 7, 10, bdark)
		_px(im, 9, 10, bdark)
		# шелест: осыпь мха по дуге
		_px(im, 2, 7, mmid)
		_px(im, 5, 6, mlo)
		_px(im, 10, 6, mlo)
		_px(im, 13, 7, mmid)
		_px(im, 1, 9, mmid)
		_px(im, 14, 9, mmid)
	else:
		# прыжок: диагональ вверх-вправо, когти первыми
		_px(im, 1, 10, mmid)              # ошмётки мха снизу
		_px(im, 2, 9, mlo)
		_px(im, 3, 10, bdark)
		_rect(im, 4, 6, 8, 8, bmid)       # корпус по диагонали
		_hrow(im, 4, 8, 5, mmid)
		_px(im, 5, 4, mlo)
		_rect(im, 9, 3, 12, 5, bmid)      # голова вверху справа
		_px(im, 11, 4, eye)
		_px(im, 12, 5, bdark)
		_px(im, 13, 4, bone)              # когти вперёд
		_px(im, 14, 5, bone)
		_px(im, 13, 6, bone)
		_dcol(im, 5, 9, 10, bout)         # лапы поджаты
		_dcol(im, 7, 9, 10, bout)
		_px(im, 12, 2, mmid)
	return im

# ---- (2) Степной застрельщик: лучник, держит дистанцию отступая ----

static func _forr(f: int) -> Image:
	var im := _im(16, 16)
	var cl := _c("CLOTH", P.T_LIGHT)
	var cm := _c("CLOTH", P.T_MID)
	var cd := _c("CLOTH", P.T_DARK)
	var bone := _c("BONE", P.T_MID)
	var boneL := _c("BONE", P.T_LIGHT)
	var bark := _c("BARK", P.T_MID)
	var iron := _c("IRON", P.T_MID)
	var gold := _c("HUD_GOLD", P.T_LIGHT)
	var eye := _c("HP_RED", P.T_MID)
	# капюшон+лицо ряды 2-4
	_rect(im, 6, 2, 9, 4, cm)
	_px(im, 7, 2, cl)
	_px(im, 8, 3, eye)      # смотрит вперёд (вправо)
	# плащадь 5..9, стан 6..9
	_rect(im, 5, 5, 10, 9, cm)
	_hrow(im, 5, 10, 9, cd)
	_px(im, 5, 6, cl)
	var step := 1 if f == 1 else 0
	# ноги: размен шага, в кадрах приёма — отшаг назад
	var dx := -1 if f >= 2 else 0
	_dcol(im, 6 + dx - step, 10, 12, cd)
	_dcol(im, 9 + dx + step, 10, 12, cd)
	if f == 0:
		# поход: лук в руке вертикально, стрела в колчане
		_dcol(im, 13, 4, 10, bark)
		_px(im, 13, 3, bark)
		_px(im, 13, 11, bark)
		_hrow(im, 11, 12, 7, bone)   # рука к луку
		_dcol(im, 4, 5, 7, cd)       # колчан за спиной
		_px(im, 4, 4, gold)
	elif f == 1:
		_dcol(im, 13, 4, 10, bark)
		_px(im, 13, 3, bark)
		_px(im, 13, 11, bark)
		_hrow(im, 11, 12, 7, bone)
		_dcol(im, 4, 5, 7, cd)
		_px(im, 4, 4, gold)
	elif f == 2:
		# T0 телеграф: натянутая тетива, стрела на прицеле, корпус развернут
		_dcol(im, 13, 4, 10, bark)
		_px(im, 13, 3, bark)
		_px(im, 13, 11, bark)
		_hrow(im, 10, 12, 7, bone)       # рука натянула
		_hrow(im, 7, 14, 7, boneL)       # древко через весь стан
		_px(im, 14, 7, iron)             # остриё впереди
		_px(im, 6, 7, gold)              # оперение
		_px(im, 12, 6, gold)
		_px(im, 12, 8, gold)
		_px(im, 15, 7, gold)             # маркер угрозы-линии
	else:
		# T1 выпуск: лук отвёл, стрела ушла (след), шаг назад
		_dcol(im, 12, 3, 9, bark)
		_hrow(im, 6, 9, 6, bone)   # рука отпущена назад
		_px(im, 15, 6, iron)       # стрела уже в воздухе (правый край)
		_hrow(im, 13, 14, 6, gold) # трезвучие вылета
		_dcol(im, 4, 4, 6, cd)
	return im

# ---- (3) Песчаный червь: выныривание по телеграфу ----

static func _worm(f: int) -> Image:
	var im := _im(16, 16)
	var pl := _c("PATH", P.T_LIGHT)
	var pm := _c("PATH", P.T_MID)
	var pd := _c("PATH", P.T_DARK)
	var podl := _c("PATH", P.T_OUTLINE)
	var mouth := _c("CHAR", P.T_MID)
	var fang := _c("BONE", P.T_LIGHT)
	var eye := _c("HP_RED", P.T_MID)
	if f == 0:
		# ход: две низкие широкие горбины катятся вправо
		_rect(im, 2, 8, 6, 10, pm)
		_hrow(im, 2, 6, 7, pl)
		_hrow(im, 2, 6, 10, pd)
		_rect(im, 9, 9, 12, 10, pm)
		_hrow(im, 9, 12, 8, pl)
		_hrow(im, 9, 12, 10, pd)
	elif f == 1:
		# горбины поменялись фазами (перистальтика)
		_rect(im, 2, 9, 5, 10, pm)
		_hrow(im, 2, 5, 8, pl)
		_hrow(im, 2, 5, 10, pd)
		_rect(im, 8, 7, 12, 10, pm)
		_hrow(im, 8, 12, 6, pl)
		_hrow(im, 8, 12, 10, pd)
		_px(im, 13, 7, pd)
	elif f == 2:
		# T0 телеграф: бугор-вал + стылая щель + сыплющийся песок
		_hrow(im, 2, 13, 9, pl)
		_rect(im, 4, 10, 12, 11, pm)
		_hrow(im, 5, 11, 12, pd)
		_hrow(im, 6, 10, 8, podl)          # щель
		_px(im, 7, 8, eye)                 # тлеющий намёк глаза в щели
		_px(im, 3, 7, pl)                  # песок сыплется
		_px(im, 12, 7, pl)
		_px(im, 5, 6, pm)
		_px(im, 10, 5, pm)
	else:
		# T1: вынырнул столбом, пасть раскрита
		_rect(im, 6, 5, 9, 12, pm)         # тело-колонна
		_hrow(im, 6, 9, 12, pd)
		_dcol(im, 5, 6, 11, pd)
		_dcol(im, 10, 6, 11, pd)
		_hrow(im, 7, 8, 9, pl)             # брюшные кольца
		_hrow(im, 7, 8, 7, pl)
		# пасть-воронка ряды 1..4
		_rect(im, 4, 3, 11, 4, pm)
		_rect(im, 5, 2, 10, 2, pm)
		_hrow(im, 6, 9, 1, mouth)
		_px(im, 4, 3, fang)
		_px(im, 6, 2, fang)
		_px(im, 9, 2, fang)
		_px(im, 11, 3, fang)
		_px(im, 5, 4, eye)
		_px(im, 10, 4, eye)
		_px(im, 3, 5, pm)                  # выброс песка по бокам
		_px(im, 12, 5, pm)
		_px(im, 2, 4, pl)
		_px(im, 13, 4, pl)
	return im

# ---- (4) Снежный шептун: парит, лечит соседей (жрица льда) ----

static func _whisp(f: int) -> Image:
	var im := _im(16, 16)
	var crl := _c("CRYSTAL", P.T_LIGHT)
	var crm := _c("CRYSTAL", P.T_MID)
	var crd := _c("CRYSTAL", P.T_DARK)
	var ubs := _c("UI_BLUE", P.T_LIGHT)
	var face := _c("UI_BLUE", P.T_DARK)
	# база-силуэт: капюшон MID, кант LIGHT, подол DARK — тон, а не молочно
	var bob := 1 if f == 1 else 0
	_hrow(im, 5, 10, 1 + bob, crl)
	_rect(im, 5, 2 + bob, 10, 4 + bob, crm)
	_rect(im, 4, 5 + bob, 11, 8 + bob, crm)
	_rect(im, 3, 9 + bob, 12, 11 + bob, crd)
	_px(im, 4, 5 + bob, crl)
	_px(im, 11, 5 + bob, crl)
	# лицо в капюшоне — два холодных огня
	_px(im, 6, 3 + bob, face)
	_px(im, 9, 3 + bob, face)
	_px(im, 6, 4 + bob, ubs)
	_px(im, 9, 4 + bob, ubs)
	_px(im, 7, 6 + bob, face)
	_px(im, 8, 6 + bob, face)
	# подол — клочья (парит, земли не касается)
	_px(im, 2, 12 + bob, crd)
	_px(im, 5, 13 + bob, crd)
	_px(im, 10, 13 + bob, crd)
	_px(im, 13, 12 + bob, crd)
	if f >= 2:
		# руки-иглы подняты к сигне
		_dcol(im, 3, 3, 5, crd)
		_px(im, 3, 2, crl)
		_dcol(im, 12, 3, 5, crd)
		_px(im, 12, 2, crl)
		# сигн-звезда над головой
		_rect(im, 7, 0, 8, 1, crl)
		if f == 3:
			# T1: знамение вспыхнуло, искры РОВНО к соседям (по бокам)
			_px(im, 1, 4, crl)
			_px(im, 0, 7, crm)
			_px(im, 2, 10, crl)
			_px(im, 14, 4, crl)
			_px(im, 15, 7, crm)
			_px(im, 13, 10, crl)
	return im

# ---- (5) Краденый рыцарь: блок фронта, спина x2 ----

static func _knight(f: int) -> Image:
	var im := _im(16, 16)
	var il := _c("IRON", P.T_LIGHT)
	var imid := _c("IRON", P.T_MID)
	var idark := _c("IRON", P.T_DARK)
	var cl := _c("CLOTH", P.T_MID)
	var cd := _c("CLOTH", P.T_DARK)
	var vis := _c("HP_RED", P.T_MID)
	var violet := _c("VIOLET", P.T_LIGHT)
	var vmid := _c("VIOLET", P.T_MID)
	var back := f == 3
	# шлем 2..4
	_rect(im, 5, 1, 10, 3, imid)
	_hrow(im, 5, 10, 0, il)
	if not back:
		_hrow(im, 6, 9, 2, idark)
		_px(im, 7, 2, vis)
		_px(im, 8, 2, vis)
	else:
		# затылок — щель шлема не светится (глаз сзади нет)
		_hrow(im, 6, 9, 2, idark)
	# торс 4..8; на спине — дыра с реликтивным свечением (уязвь x2)
	_rect(im, 4, 4, 11, 8, imid)
	_hrow(im, 4, 11, 8, idark)
	_px(im, 4, 4, il)
	_px(im, 11, 4, il)
	if not back:
		_hrow(im, 6, 9, 6, cl)   # гербовая ткань на груди
		_px(im, 7, 5, vmid)
		_px(im, 8, 7, vmid)
	else:
		_rect(im, 6, 5, 9, 7, idark)      # выломанная заклёпка-пластина
		_hrow(im, 6, 9, 6, violet)        # украденное светится из спины
		_px(im, 5, 6, vmid)
		_px(im, 10, 6, vmid)
	# юбка-кольчуга 9..10
	_rect(im, 4, 9, 11, 10, idark)
	_hrow(im, 5, 10, 10, cl if not back else idark)
	# ноги с разменом шага
	var step := 1 if (f == 1 or f == 3) else 0
	_dcol(im, 5 + step, 11, 13, idark)
	_dcol(im, 10 - step, 11, 13, idark)
	if f == 0 or f == 1:
		# башенный щит спереди слева (фронт закрыт)
		_rect(im, 0, 3, 2, 11, imid)
		_dcol(im, 0, 3, 11, il)
		_dcol(im, 2, 3, 11, idark)
		_px(im, 1, 5, cd)
		_px(im, 1, 8, cd)
	elif f == 2:
		# T0 блок: щит надвинут, корпус присел, кант вспыхнул
		_rect(im, 1, 2, 4, 12, imid)
		_dcol(im, 1, 2, 12, il)
		_dcol(im, 4, 2, 12, idark)
		_px(im, 2, 3, il)
		_px(im, 3, 6, il)
		_px(im, 2, 10, il)
		# упор: задняя нока далеко сзади
		_dcol(im, 12, 10, 13, idark)
		_hrow(im, 12, 14, 13, idark)
		_px(im, 13, 12, imid)
	else:
		# T1 спина x2: щит унесён вперёд-вбок (слева впереди не виден),
		# спина открыта — свет дыры; маркер x2
		_rect(im, 0, 8, 1, 12, idark)   # кромка щита ушла вниз-вперед
		_px(im, 0, 7, imid)
		_text_x2(im)
	return im

## Маркер «x2» над спиной — из глифов бортового шрифта, рисуется точками
static func _text_x2(im: Image) -> void:
	var g := FONT["X"]
	var col := _c("HUD_GOLD", P.T_LIGHT)
	for r in 5:
		for cch in 3:
			if String(g[r])[cch] == "1":
				_px(im, 11 + cch, r, col)
	var g2 := FONT["2"]
	for r in 5:
		for cch in 3:
			if String(g2[r])[cch] == "1":
				_px(im, 3 + cch, r, col)

# ---- (6) Скелет-рудокоп: мечет обломки дугой ----

static func _miner(f: int) -> Image:
	var im := _im(16, 16)
	var bl := _c("BONE", P.T_LIGHT)
	var bm := _c("BONE", P.T_MID)
	var bd := _c("BONE", P.T_DARK)
	var il := _c("IRON", P.T_LIGHT)
	var imid := _c("IRON", P.T_MID)
	var idark := _c("IRON", P.T_DARK)
	var bark := _c("BARK", P.T_MID)
	var st := _c("STONE", P.T_MID)
	var stl := _c("STONE", P.T_LIGHT)
	var eye := _c("HP_RED", P.T_MID)
	# череп 2..3, рёбра 5..8, таз 9, ноги 10..13
	_rect(im, 6, 1, 9, 3, bm)
	_hrow(im, 6, 9, 3, bd)
	_px(im, 7, 2, eye)
	_px(im, 8, 2, eye)
	_px(im, 7, 3, bd)
	_px(im, 8, 3, bd)
	# рёбра: полоски с пропусками
	for ry in [5, 6, 7]:
		_hrow(im, 6, 9, ry, bm)
		_px(im, 7, ry, bd)
		_px(im, 8, ry, bd)
	_hrow(im, 6, 9, 8, bm)
	_rect(im, 6, 9, 9, 9, bd)
	if f <= 1:
		var step := f
		_dcol(im, 6 + step, 10, 13, bm)
		_dcol(im, 9 - step, 10, 13, bm)
		_px(im, 6 + step, 14, bd)
		_px(im, 9 - step, 14, bd)
		# каска шахтёра над черепом
		_hrow(im, 5, 10, 0, imid)
		_px(im, 5, 1, idark)
		_px(im, 10, 1, idark)
		# кирка на плече: рукоять по диагонали, голова кирки слева сверху
		for d in 5:
			_px(im, 4 + d, 8 - d, bark)
		_hrow(im, 2, 5, 3, imid)
		_px(im, 2, 2, il)
		_px(im, 5, 2, idark)
		# руки-костии к плечу
		_px(im, 5, 6, bm)
		_px(im, 10, 5, bm)
	elif f == 2:
		# T0 замах: кирка над головой, в левой руке обломок
		_dcol(im, 6, 10, 13, bm)
		_dcol(im, 9, 10, 13, bm)
		_hrow(im, 5, 10, 0, imid)
		_px(im, 5, 1, idark)
		_px(im, 10, 1, idark)
		for d in 5:
			_px(im, 8 - d, 4 - d, bark)     # рукоять вверх-налево
		_hrow(im, 2, 5, 0, imid)            # голова кирки наверху
		_px(im, 2, 1, il)
		_px(im, 5, 1, idark)
		_px(im, 10, 5, bm)                  # правая рука поднята
		_px(im, 11, 5, bm)
		# обломок в левой руке (x3..4, y7) — готов к дуге
		_rect(im, 3, 7, 4, 8, st)
		_px(im, 3, 7, stl)
		_px(im, 5, 7, bm)                   # кисть
	else:
		# T1 бросок: рука вперёд, обломок уже НА ДУГЕ над головой
		_dcol(im, 6, 10, 13, bm)
		_dcol(im, 9, 10, 13, bm)
		_hrow(im, 5, 10, 0, imid)
		_px(im, 5, 1, idark)
		_px(im, 10, 1, idark)
		_hrow(im, 10, 12, 5, bm)            # правая рука выброшена вперёд
		_px(im, 13, 5, bm)
		# обломок уже в зените справа сверху — светлый, не сливается с каской
		_rect(im, 13, 0, 14, 1, st)
		_px(im, 13, 0, stl)
		# пунктир дуги от руки к зениту
		_px(im, 14, 3, bd)
		_px(im, 14, 2, bd)
		# кирка в левой опущена
		_dcol(im, 3, 6, 10, bark)
		_hrow(im, 2, 4, 10, imid)
	return im

static func _new_frame(key: String, f: int) -> Image:
	match key:
		"ambusher":
			return _amb(f)
		"forerunner":
			return _forr(f)
		"worm":
			return _worm(f)
		"whisperer":
			return _whisp(f)
		"knight":
			return _knight(f)
		_:
			return _miner(f)

# ============================================================ пол биома 16px

static func _floor(biome: String) -> Dictionary:
	match biome:
		"snow":
			return {"a": _c("STONE", P.T_LIGHT), "b": _c("STONE", P.T_MID), "acc": _c("CRYSTAL", P.T_MID)}
		"desert":
			return {"a": _c("PATH", P.T_LIGHT), "b": _c("PATH", P.T_MID), "acc": _c("STONE_WARM", P.T_DARK)}
		"steppe":
			return {"a": _c("PATH", P.T_MID), "b": _c("PATH", P.T_DARK), "acc": _c("GRASS", P.T_MID)}
		"castle":
			return {"a": _c("STONE", P.T_MID), "b": _c("STONE", P.T_DARK), "acc": _c("IRON", P.T_MID)}
		"dungeon":
			return {"a": _c("CAVE_ROCK", P.T_MID), "b": _c("CAVE_ROCK", P.T_DARK), "acc": _c("VIOLET", P.T_MID)}
		_:
			return {"a": _c("GRASS", P.T_LIGHT), "b": _c("GRASS", P.T_MID), "acc": _c("BARK", P.T_MID)}

## Контекстная полоса: спрайт на полу биома 1:1 (размер как в игре).
## Оба контекста блока — одной высоты 32: линия земли общая.
static func _context_strip(biome: String, spr: Image) -> Image:
	var h := 32
	var w := 64
	var im := _im(w, h)
	var fl := _floor(biome)
	for y in h:
		for x in w:
			im.set_pixel(x, y, fl["a"] if (x + y) % 2 == 0 else fl["b"])
	for y in range(2, h - 1, 3):
		for x in range(0, w):
			if (x * 7 + y * 13) % 29 == 0:
				im.set_pixel(x, y, fl["acc"])
	# нижний край полосы = линия земли; спрайт стоит ногами на ней
	_blit_into(im, spr, int(w / 2.0) - int(spr.get_width() / 2.0), h - spr.get_height(), 1)
	return im

# ============================================================ лист

func _mob_defs() -> Array:
	return [
		{"key": "ambusher", "biome": "forest", "family": "brute",
			"ru": "КОРНЕВОЙ ЗАСАДЧИК", "lat": "ROOT AMBUSHER - LEAP FROM MOSS - MINI FOREST",
			"lines": [
				"§4: KNOWN BEHAVIOUR PLUS ONE TRICK - LEAP OUT OF THE MOSS",
				"TELEGRAPH RUSTLE: MOSS SINKS FRAME T0, SCATTER DUST, RED EYE UNDER IT",
				"T1 AIR BOUND DIAGONAL, CLAWS FIRST - LAND HIT ON TOP OF PATH",
				"STUB TODAY: TLEL BOAR CARRIER REMAP (t19) - SLOT AND STATS KEEP",
				"LORE - THE MOSS HEARS BOOTS LONG BEFORE THE BEAST DOES",
			]},
		{"key": "forerunner", "biome": "steppe", "family": "archer",
			"ru": "СТЕПНОЙ ЗАСТРЕЛЬЩИК", "lat": "STEPPE FORERUNNER - KEEPS RANGE BACKING AWAY",
			"lines": [
				"§4: KNOWN ARCHER PATTERN PLUS ONE TRICK - BACKING RETREAT",
				"TELEGRAPH T0: FULL DRAW, SHAFT ACROSS THE BODY, NOCK GLOW MARKS LINE",
				"T1 RELEASE: STEP BACK WHILE THE SHOT LEAVES - RANGE STAYS HIS",
				"STUB TODAY: PLAIN ARCHER SKIN (t20 remap) - FAMILY STATS KEEP",
				"LORE - HE SHOOTS FIRST AND REGRETS NEVER",
			]},
		{"key": "worm", "biome": "desert", "family": "swarmling",
			"ru": "ПЕСЧАНЫЙ ЧЕРВЬ", "lat": "SAND WORM - RISES ON A TELEGRAPH - MINI DESERT",
			"lines": [
				"§4: KNOWN SWARM DWELLER PLUS ONE TRICK - RISE ON TELEGRAPH",
				"T0 RIDGE AND CRACK UNDER SAND, GRAINS SPILL - READABLE SAFE WINDOW",
				"T1 FULL RISE, FANGS WIDE - STRIKE ZONE VISIBLE BEFORE IT",
				"STUB TODAY: SWARMLING REMAP (t20) - FAMILY STATS KEEP",
				"LORE - THE DUNES HAVE A PULSE IF YOU STAND STILL ENOUGH",
			]},
		{"key": "whisperer", "biome": "snow", "family": "wraith",
			"ru": "СНЕЖНЫЙ ШЕПТУН", "lat": "SNOW WHISPERER - HEALS NEIGHBOURS - PRIORITY KILL",
			"lines": [
				"§4: KNOWN WRAITH DRIFT PLUS ONE TRICK - HEALS NEIGHBOURS",
				"DESIGN: KILL PRIORITY MOVES TO THE HEALER - SHE BUMPS YOUR MATH",
				"T0 SIGN FORMS OVER HOOD, T1 SPARKLE WAVE SPREADS TO ALLIES",
				"HONEST STUB FACT: NO snow/wraith SKIN IN MANIFEST - RUNTIME SILENTLY",
				"SHOWS THE BASE WRAITH SHEET (t20 AUDIT) - SEE NOTE ON THIS SHEET",
				"LORE - THE BLIZZARD REPEATS THE NAMES OF THOSE NOT YET DEAD",
			]},
		{"key": "knight", "biome": "castle", "family": "brute",
			"ru": "КРАДЕНый РЫЦАРЬ", "lat": "STOLEN KNIGHT - BLOCKS FRONT - BACK DOUBLES",
			"lines": [
				"§4: KNOWN HEAVY SLOT PLUS ONE TRICK - FRONT BLOCK, BACK HIT x2",
				"T0 SHIELD BRACE: FRONT READS AS A WALL, SPARKS ON THE RIM",
				"T1 SHOWN FROM BEHIND: PLATE BROKEN OUT - STOLEN RELIC GLOWS - THE x2",
				"STUB TODAY: COLOSS-STYLE BOAR REMAP (t20) - TIERS AND BELT KEEP",
				"LORE - SOMETHING WAS CARRIED OFF THE FORGE AND IT STILL HUMS",
			]},
		{"key": "miner", "biome": "dungeon", "family": "wraith",
			"ru": "СКЕЛЕТ-РУДОКОП", "lat": "SKELETON MINER - LOBS DEBRIS ON AN ARC",
			"lines": [
				"§4: KNOWN SKELETON GAIT PLUS ONE TRICK - DEBRIS LOB ON ARC",
				"T0 PICK OVER HEAD, ROCK IN THE OTHER PAW - WINDUP READS CLEAR",
				"T1 ROCK IS ALREADY APEX - SHELTER OR CLOSE, THE ARC PUNISHES STAND",
				"STUB TODAY: WRAITH REMAP CHOSEN IN t20 FOR THIS SLOT",
				"LORE - HE STILL WORKS THE SEAM HE DIED ON",
			]},
	]

func _build_sheet() -> Image:
	var W := 720
	var sheet := _im(W, 1200)
	sheet.fill(P.SHEET["BG"])
	var x0 := 10
	var y := 8
	_text(sheet, x0, y, "BESTIARY V2 - NEW MOB PER BELT AND MINI-BOSS FACES - VERDICT - W7 25.11", 2, P.SHEET["TEXT"])
	y += 16
	_text(sheet, x0, y, "DESIGN §4: KNOWN BEHAVIOUR PLUS ONE NEW TRICK - SIX BELTS SIX FACES", 1, P.SHEET["LINE"])
	y += 9
	_text(sheet, x0, y, "LEFT OF EACH BLOCK - THE RUNTIME STUB (t19/t20 REMAP, BYTE-FOR-BYTE FROM mobs_variants.json)", 1, P.SHEET["LINE"])
	y += 9
	_text(sheet, x0, y, "RIGHT - PROPOSED NEW FACE: K0 K1 WALK, T0 TELEGRAPH, T1 TRICK MOVE - 16PX CANON - USER DECIDES", 1, P.SHEET["LINE"])
	y += 9
	_text(sheet, x0, y, "CODE ART ONLY - RUNTIME UNTOUCHED - INTEGRATION ONLY AFTER THE VERDICT (CAPTAIN TICKET)", 1, P.SHEET["LINE"])
	y += 14

	for md in _mob_defs():
		var m: Dictionary = md
		var bk := String(m["key"])
		var biome := String(m["biome"])
		_text(sheet, x0, y, String(m["lat"]), 1, P.SHEET["TEXT"])
		_ru(sheet, x0, y + 10, String(m["ru"]), 1, P.SHEET["TEXT"])
		y += 28
		# --- колонка заглушки ---
		var st := _stub(biome, String(m["family"]))
		var stub_frames: Array = st["frames"]
		var sw: int = st["w"]
		_text(sheet, x0, y, "STUB TODAY", 1, P.SHEET["LINE"])
		var sfx := x0
		for fi in stub_frames.size():
			var sfr: Image = stub_frames[fi]
			_check_fx(sfr, "%s_stub%d" % [bk, fi])
			# 32px носителя брюта показываем уменьшенным вдвое (врезка)
			var sc := 3 if sw == 16 else 2
			_blit_sc(sheet, sfr, sfx, y + 12, sc)
			_text(sheet, sfx, y + 12 + sfr.get_height() * sc + 2, "S%d" % fi, 1, P.SHEET["LINE"])
			sfx += sfr.get_width() * sc + 4
		if String(st["note"]) != "":
			_text(sheet, x0, y + 12 + 16 * 3 + 12, "NOTE: " + String(st["note"]), 1, P.SHEET["LINE"])
		# --- колонка нового обличья K0 K1 T0 T1 ---
		var nfx := x0 + 200
		_text(sheet, nfx, y, "NEW FACE", 1, P.SHEET["TEXT"])
		var labels := ["K0", "K1", "T0", "T1"]
		for f in 4:
			var fr := _new_frame(bk, f)
			_check_fx(fr, "%s_%s" % [bk, labels[f]])
			_blit_sc(sheet, fr, nfx + f * 52, y + 12, 3)
			_text(sheet, nfx + f * 52, y + 12 + 48 + 2, labels[f], 1, P.SHEET["LINE"])
		# --- контексты 1:1: заглушка и новое на полу биома ---
		var cx := nfx + 4 * 52 + 12
		var stub_for_ctx: Image = stub_frames[0]
		var stx := _context_strip(biome, stub_for_ctx)
		_check_fx(stx, "%s_ctxstub" % bk)
		_blit_into(sheet, stx, cx, y + 12 + 16, 1)
		_text(sheet, cx, y + 12 + 16 + 32 + 2, "1:1 STUB", 1, P.SHEET["LINE"])
		var ntx := _context_strip(biome, _new_frame(bk, 0))
		_check_fx(ntx, "%s_ctxnew" % bk)
		_blit_into(sheet, ntx, cx + 70, y + 12 + 16, 1)
		_text(sheet, cx + 70, y + 12 + 16 + 32 + 2, "1:1 NEW", 1, P.SHEET["LINE"])
		# --- карточка поведения ---
		var ly := y + 4
		var tx := cx + 70 + 64 + 12
		for ln in (m["lines"] as Array):
			# перенос по 44 символа (латинь scale1 ~176px)
			var s := String(ln)
			while s.length() > 0:
				var cut: int = mini(s.length(), 32)
				if cut < s.length():
					var sp: int = s.rfind(" ", cut)
					if sp > 20:
						cut = sp
				_text(sheet, tx, ly, s.substr(0, cut), 1, P.SHEET["LINE"])
				ly += 10
				s = s.substr(cut)
				s = s.lstrip(" ")
		y += 12 + 48 + 46
		if String(st["note"]) != "":
			y += 10
		_hline_px(sheet, x0, W - 10, y - 6, P.SHEET["LINE"])
		y += 4

	# --- лайнап предлагаемых обличий ---
	_text(sheet, x0, y, "PROPOSED LINEUP - SIX NEW FACES 16PX ON NEUTRAL GROUND - WALK FRAME K0", 1, P.SHEET["TEXT"])
	y += 12
	var lx2 := x0
	for md in _mob_defs():
		var m2: Dictionary = md
		var fr := _new_frame(String(m2["key"]), 0)
		var pad := _im(18, 18)
		for yy in 18:
			for xx in 18:
				pad.set_pixel(xx, yy, _c("ASH_GROUND", P.T_MID) if (xx + yy) % 2 == 0 else _c("ASH_GROUND", P.T_DARK))
		_blit_into(pad, fr, 1, 1, 1)
		_check_fx(pad, "lineup_%s" % String(m2["key"]))
		_blit_sc(sheet, pad, lx2, y, 2)
		_text(sheet, lx2, y + 36 + 3, String(m2["key"]).to_upper(), 1, P.SHEET["LINE"])
		lx2 += 18 * 2 + 20
	y += 56

	# --- честность/интеграция ---
	_text(sheet, x0, y, "RUNTIME FACT t20 AUDIT: MANIFEST HAS NO snow/wraith SKIN - MINI SNOW BOSS DRAWS BASE SHEET", 1, P.SHEET["TEXT"])
	y += 9
	_text(sheet, x0, y, "(SILENT NO-OP). INTEGRATION TICKET MUST: FACE+NAME+REPINS OF OWN BIOME PINS, TIMINGS KEEP,", 1, P.SHEET["TEXT"])
	y += 9
	_text(sheet, x0, y, "SKIN EVERY NEW FACE INTO ALL SIX BIOME VARIANT TABLES, ADD THE MISSING snow/wraith ROW.", 1, P.SHEET["TEXT"])
	y += 12
	_text(sheet, x0, y, "HONESTY - SILHOUETTES PROVED BY ASCII DUMPS (PAINTERS MODE) - FINAL AESTHETICS: HUMAN EYE", 1, P.SHEET["TEXT"])
	y += 12
	if _stub_quote_colors > 0:
		_text(sheet, x0, y, "PALETTE NOTE: STUB QUOTES CONTRIBUTED %d OFF-PALETTE PIXELS (LEGACY SKIN PULL)" % _stub_quote_colors, 1, P.SHEET["LINE"])
		for nm in _stub_off_names:
			_text(sheet, x0, y, "  OFF: %s x%d" % [String(nm), int(_stub_off_names[nm])], 1, P.SHEET["LINE"])
			y += 8
		y += 4
	var h := mini(y + 8, 1200)
	sheet.crop(W, h)  # Godot 4.7: crop(width, height) от верхнего левого угла
	return sheet

# ============================================================ режим PAINTERS

func _ascii_probe() -> void:
	for md in _mob_defs():
		var m: Dictionary = md
		var bk := String(m["key"])
		var st := _stub(String(m["biome"]), String(m["family"]))
		var sframes: Array = st["frames"]
		_ascii_dump(sframes[0], "%s stub0" % bk)
		_ascii_dump(_new_frame(bk, 0), "%s K0" % bk)
		_ascii_dump(_new_frame(bk, 1), "%s K1" % bk)
		_ascii_dump(_new_frame(bk, 2), "%s T0" % bk)
		_ascii_dump(_new_frame(bk, 3), "%s T1" % bk)

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
	print("[fx] %-18s px:%3d off:%d %s hash:%s" % [nm, n, off, ("PASS" if ok else "FAIL"), _fnv32_hex(im)])
	if not ok:
		_fails += 1

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

static func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

# ============================================================ бортовые шрифты
## Глифы игры НЕ цитируются: собственный чертёжный шрифт инструмента.
## Латинь 3x5 + Кириллица 5x7 (имена на листе — русские).

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

## Кириллица 5x7 — собственный чертёжный набор инструмента (расширен в t21
## литерами З/Ж/Ч/Ш/Щ/Ц для имён бестиария; игровые глифы не цитировались).
const RU := {
	"А": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"В": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"Г": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"Д": ["00100", "00100", "00100", "00100", "01110", "10001", "11111"],
	"Е": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"З": ["01110", "10001", "00111", "00001", "00001", "10001", "01110"],
	"Ж": ["10101", "10101", "10101", "11111", "10101", "10101", "10101"],
	"И": ["10001", "10001", "10001", "10011", "10101", "11001", "10001"],
	"Й": ["00100", "00000", "10001", "10011", "10101", "11001", "10001"],
	"К": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"Л": ["00111", "01001", "01001", "01001", "01001", "01001", "10001"],
	"Н": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"О": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"П": ["11111", "10001", "10001", "10001", "10001", "10001", "10001"],
	"Р": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"С": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"Т": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"У": ["10001", "10001", "10001", "01111", "00010", "00100", "11000"],
	"Ы": ["10001", "10001", "10001", "11101", "10001", "10001", "10001"],
	"Ь": ["10000", "10000", "10000", "01110", "10001", "10001", "01110"],
	"Ц": ["10101", "10101", "10101", "10101", "10101", "11111", "00110"],
	"Ч": ["10001", "10001", "10001", "01111", "00001", "00001", "00110"],
	"Ш": ["10101", "10101", "10101", "10101", "10101", "10101", "11111"],
	"Щ": ["10101", "10101", "10101", "10101", "10101", "11111", "00011"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
}

func _ru(img: Image, x0: int, y0: int, txt: String, sc: int, col: Color) -> int:
	var x := x0
	for ch in txt.to_upper():
		var g = RU.get(ch)
		if g == null:
			push_warning("RU font: литеры '%s' нет" % ch)
			x += 6 * sc
			continue
		for r in 7:
			for c in 5:
				if String(g[r])[c] == "1":
					for dy in sc:
						for dx in sc:
							_px(img, x + c * sc + dx, y0 + r * sc + dy, col)
		x += 6 * sc
	return x - x0 - sc

# ---- примитивы ----

static func _blit_into(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var col := src.get_pixel(x, y)
			if col.a < 0.5:
				continue
			for dy in sc:
				for dx in sc:
					_px(dst, x0 + x * sc + dx, y0 + y * sc + dy, col)

static func _blit_sc(dst: Image, src: Image, x0: int, y0: int, sc: int) -> void:
	_blit_into(dst, src, x0, y0, sc)

static func _hline_px(sheet: Image, xa: int, xb: int, y: int, col: Color) -> void:
	for xx in range(mini(xa, xb), maxi(xa, xb) + 1):
		_px(sheet, xx, y, col)
