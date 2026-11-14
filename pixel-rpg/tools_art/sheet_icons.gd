extends SceneTree
## c11 «Иконки скиллов v2» — лист на вердикт пользователя (игра НЕ тронута).
##
## Лист: 12 колонок; в колонке — иконка 16 px (верх, порядок = UiIcons.SKILL_SLOTS,
## контракт атласа) и под ней мастер 48 px (детальный эталон). Фон/сетка —
## технические цвета SHEET (вне боксов иконок). Цвета объектов — только
## PixelPalette.RAMPS/FLATS. Свет СЗ, контур — OUTLINE-тон своего материала 1 px.
##
## Запуск:  godot --headless --path pixel-rpg -s res://tools_art/sheet_icons.gd -- <out.png>
##
## Самопроверки (exit != 0 при провале):
##  1) чистота палитры: каждый пиксель внутри боксов ∈ RAMPS/FLATS;
##  2) нижний ряд силуэта каждого спрайта — только OUTLINE-тона;
##  3) СЗ-подсветка: LIGHT-тон в верхней половине каждого спрайта;
##  4) >=3 разных цвета палитры на каждый спрайт;
##  5) попарная пересечимость масок 16px-ряда: max <= MAX_INTER (порог) и
##     среднее ниже старого (печатаются числа для всех 66 пар max/mean);
##  6) средняя насыщенность 16px-ряда >= MIN_SAT.
##  7) c15 equality-пин: 16px-ряд листа == рантайм ui_icons.skill_atlas()
##     попиксельно (0 расхождений) — источник истины после интеграции.

const S := 16          # иконка
const M := 48          # мастер
const COLS := 12
const PITCH := 50      # ширина колонки
const PAD := 2

const PAL := preload("res://scripts/pixel_palette.gd")

const SKILLS := ["power_strike", "whirlwind", "second_wind", "execute", \
	"pierce", "volley", "mark", "rain", "firebolt", "frost_nova", "siphon", "firestorm"]

# пороги самопроверок (старое: max_pair_inter=11 mean=4.61 sat=0.548 — см. REPORT).
# Контракт: максимум НЕ ВЫШЕ старого максимума (11); держим жёсткий гейт = 11.
const MAX_INTER := 11
const MIN_SAT := 0.60

const _L := 0
const _M := 1
const _D := 2
const _O := 3

var _img: Image
var _ox := 0  # офсет «холста» 16px-иконок (мастера рисуют явными координатами)
var _oy := 0


# ---------- низкоуровневые примитивы (цвета — только палитра) ----------

func _px(x: int, y: int, col: Color) -> void:
	_img.set_pixel(x, y, col)

func _P(x: int, y: int, ramp: String, tone: int) -> void:
	# P(alette) — точка материалом; вне холста молча режется (канва-кроп)
	var xx := x + _ox
	var yy := y + _oy
	if xx < 0 or yy < 0 or xx >= _img.get_width() or yy >= _img.get_height():
		return
	_img.set_pixel(xx, yy, PAL.c(ramp, tone))

func _F(x: int, y: int, flat: String) -> void:
	var xx := x + _ox
	var yy := y + _oy
	if xx < 0 or yy < 0 or xx >= _img.get_width() or yy >= _img.get_height():
		return
	_img.set_pixel(xx, yy, PAL.FLATS[flat])

func _rect(x0: int, y0: int, x1: int, y1: int, ramp: String, tone: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_P(x, y, ramp, tone)

func _hl(x0: int, x1: int, y: int, ramp: String, tone: int) -> void:
	_rect(x0, y, x1, y, ramp, tone)

func _vl(x: int, y0: int, y1: int, ramp: String, tone: int) -> void:
	_rect(x, y0, x, y1, ramp, tone)

func _diag(pts: Array, ramp: String, tone: int) -> void:
	for p in pts:
		_P(int(p[0]), int(p[1]), ramp, tone)

func _frame(x0: int, y0: int, x1: int, y1: int, ramp: String, tone: int) -> void:
	_hl(x0, x1, y0, ramp, tone)
	_hl(x0, x1, y1, ramp, tone)
	_vl(x0, y0, y1, ramp, tone)
	_vl(x1, y0, y1, ramp, tone)

func _dot(x: int, y: int, ramp: String) -> void:
	# «жирная» точка 2×2 с СЗ-светом
	_P(x, y, ramp, _L)
	_P(x + 1, y, ramp, _M)
	_P(x, y + 1, ramp, _M)
	_P(x + 1, y + 1, ramp, _D)


# ================= 16 px иконки (ox — левый край слота) =================
# Правило ряда: рисуй внутри квадрата 16×16; нижний пиксельный ряд объекта —
# OUTLINE-тон; LIGHT — верх/лево открытой грани; правый бок — DARK.

func _ic16(idx: int, ox: int) -> void:
	match idx:
		0: _ic_power_strike(ox)
		1: _ic_whirlwind(ox)
		2: _ic_second_wind(ox)
		3: _ic_execute(ox)
		4: _ic_pierce(ox)
		5: _ic_volley(ox)
		6: _ic_mark(ox)
		7: _ic_rain(ox)
		8: _ic_firebolt(ox)
		9: _ic_frost_nova(ox)
		10: _ic_siphon(ox)
		11: _ic_firestorm(ox)


## power_strike — бронзовый молот вниз-вправо (голова справа внизу), рукоять вверх.
func _ic_power_strike(ox: int) -> void:
	# голова: компактный бронзовый блок 4×3 справа внизу
	_hl(9, 12, 7, "BRONZE", _L)
	_hl(9, 11, 8, "BRONZE", _M)
	_vl(12, 8, 9, "BRONZE", _D)
	_hl(9, 12, 9, "BRONZE", _M)
	_hl(9, 12, 10, "BRONZE", _O)
	# шип вправо
	_P(13, 8, "BRONZE", _M)
	_P(13, 9, "BRONZE", _O)
	# рукоять вверх-влево
	_diag([[8, 6], [7, 5], [6, 4], [5, 3]], "WOOD", _M)
	_diag([[7, 4], [6, 3]], "WOOD", _L)
	# навершие — золото
	_diag([[4, 2], [4, 1]], "HUD_GOLD", _L)
	_P(3, 2, "HUD_GOLD", _M)


## whirlwind — спираль вихря в левом верхнем углу (НЕ кольцо).
func _ic_whirlwind(ox: int) -> void:
	var pts := [[8, 2], [6, 1], [4, 1], [2, 2], [1, 4], [1, 6],
		[2, 8], [4, 9], [6, 8], [7, 6], [6, 5], [5, 5]]
	for i in pts.size():
		var t := _L if i < 4 else (_M if i < 8 else _D)
		_P(int(pts[i][0]), int(pts[i][1]), "WATER", t)
	# стыки ленты (спираль непрерывна)
	_P(5, 1, "WATER", _M)
	_P(1, 3, "WATER", _M)
	_P(1, 7, "WATER", _M)
	_P(3, 9, "WATER", _D)
	# юбка ленты — OUTLINE ряда
	_diag([[2, 9], [3, 10], [4, 10], [5, 10], [6, 9]], "WATER", _O)
	# песчинки — золото
	_P(3, 4, "HUD_GOLD", _L)
	_P(5, 3, "HUD_GOLD", _M)


## second_wind — перо в правом столбце: редкие штрихи опахала, просветы.
func _ic_second_wind(ox: int) -> void:
	# стержень — сплошная лесенка справа налево вниз
	_diag([[12, 2], [11, 3], [11, 4], [10, 5], [9, 6], [9, 7], [8, 8],
		[7, 9], [7, 10], [6, 11], [6, 12]], "LEAF", _D)
	# опахало: штрихи через ряд (просветы!), СЗ-свет вверху
	for i in 5:
		var y := 2 + i * 2
		var bx := 12 - i
		_hl(bx + 1, bx + 2, y, "LEAF", _L if i < 3 else _M)
		_P(bx - 2, y, "LEAF", _D)
	# насечки воздуха
	_P(14, 5, "LEAF", _L)
	# очин — ноги ряда
	_diag([[6, 13], [7, 13]], "LEAF", _O)
	# завихрение ветра — золото (хвост — OUTLINE ряда)
	_diag([[11, 11], [12, 12]], "HUD_GOLD", _M)
	_P(12, 10, "HUD_GOLD", _L)
	_P(11, 13, "HUD_GOLD", _O)


## execute — бронзовый палаш вниз у левого края: узкий клинок, алая обмотка.
func _ic_execute(ox: int) -> void:
	# яблоко — золото
	_hl(3, 4, 1, "HUD_GOLD", _L)
	# крестовина WOOD
	_hl(1, 6, 3, "WOOD", _M)
	_hl(1, 6, 4, "WOOD", _O)
	# рукоять — красная обмотка
	_vl(3, 5, 6, "HP_RED", _L)
	_vl(4, 5, 6, "HP_RED", _M)
	# клинок узкий: 2 колонки
	_vl(3, 7, 11, "BRONZE", _L)
	_vl(4, 7, 10, "BRONZE", _M)
	_vl(5, 7, 9, "BRONZE", _D)
	# остриё и ноги ряда
	_P(4, 11, "BRONZE", _D)
	_hl(3, 4, 12, "BRONZE", _O)


## pierce — стрела со свистом вверх-вправо: оперенье CLOTH, бронза.
func _ic_pierce(ox: int) -> void:
	_diag([[2, 11], [3, 10], [4, 9], [5, 8], [6, 7], [7, 6], [8, 5],
		[9, 4], [10, 3]], "WOOD", _M)
	_diag([[3, 10], [5, 8], [7, 6], [9, 4]], "WOOD", _L)
	# наконечник BRONZE
	_diag([[11, 2], [12, 1]], "BRONZE", _L)
	_diag([[11, 3], [12, 2]], "BRONZE", _D)
	_P(10, 4, "HUD_GOLD", _M)
	# оперенье CLOTH и ноги ряда
	_diag([[1, 12], [2, 11]], "CLOTH", _M)
	_diag([[1, 13], [2, 13]], "CLOTH", _O)
	_P(13, 1, "HUD_GOLD", _L)


## volley — лук лёжа (плечи вниз) в среднем поясе, стрела вдоль хорды вправо.
func _ic_volley(ox: int) -> void:
	# дуга плечей брюхом вниз (реже: 5 точек)
	_diag([[4, 8], [5, 9], [7, 10], [9, 9], [10, 8]], "BARK", _M)
	_P(5, 8, "BARK", _L)
	_P(9, 8, "BARK", _D)
	_P(4, 8, "CLOTH", _L)
	_P(11, 8, "CLOTH", _M)
	# тетива-хорда (крашеная HP_RED)
	_hl(4, 10, 8, "HP_RED", _M)
	# стрела над тетивой, вправо
	_hl(4, 8, 7, "WOOD", _M)
	_hl(5, 8, 6, "WOOD", _L)
	_P(9, 6, "BRONZE", _L)
	_P(9, 7, "BRONZE", _D)
	# оперенье
	_diag([[3, 6], [3, 7]], "CLOTH", _D)
	# ноги ряда: низ брюха
	_P(7, 11, "BARK", _O)


## mark — коготные росчерки в нижнем-среднем поясе: три штриха HP_RED + золото.
func _ic_mark(ox: int) -> void:
	var strokes := [
		[[3, 7], [4, 8], [5, 9]],
		[[7, 5], [8, 6], [9, 7], [10, 8], [11, 9]],
		[[12, 5], [13, 6]],
	]
	for s in strokes:
		for i in s.size():
			_P(int(s[i][0]), int(s[i][1]), "HP_RED", _L if i == 0 else _M)
			_P(int(s[i][0]), int(s[i][1]) + 1, "HP_RED", _D)
	# хвосты штрихов — OUTLINE
	_diag([[5, 10], [11, 10], [13, 7]], "HP_RED", _O)
	# вырванная метка — золото
	_P(5, 12, "HUD_GOLD", _L)
	_P(5, 13, "HUD_GOLD", _O)


## rain — полое дно-колчан в левом нижнем углу, стрелы вправо-вверх.
func _ic_rain(ox: int) -> void:
	# полое дно-чулок: верхняя кромка, бока, дно (крашеная кожа CLOTH-бок)
	_hl(1, 6, 9, "BARK", _L)
	_vl(1, 10, 12, "CLOTH", _M)
	_vl(6, 10, 12, "BARK", _D)
	_vl(7, 9, 11, "CLOTH", _M)
	# дно — ноги ряда
	_hl(1, 6, 13, "BARK", _O)
	# ремень с золотой пряжкой
	_vl(3, 10, 12, "HP_RED", _M)
	_P(3, 11, "HUD_GOLD", _L)
	_P(4, 11, "HUD_GOLD", _M)
	# три стрелы высыпаются вправо-вверх
	for sp in [[10, 3], [12, 6], [10, 7]]:
		var bx := int(sp[0])
		var by := int(sp[1])
		_P(bx, by, "WOOD", _M)
		_P(bx + 1, by - 1, "BRONZE", _L)
		_P(bx, by + 1, "CLOTH", _D)


## firebolt — комета в верхнем поясе (центр): голова FIRE с ядром HOT, хвост.
func _ic_firebolt(ox: int) -> void:
	# голова (сдвинута вниз, чтобы не сливаться с хордой volley)
	_hl(6, 8, 4, "FIRE", _L)
	_hl(6, 7, 5, "FIRE", _M)
	_vl(9, 5, 6, "FIRE", _D)
	_hl(6, 9, 7, "FIRE", _O)
	_F(7, 5, "FIRE_HOT")
	_F(8, 6, "FIRE_HOT")
	# хвост — редкие штрихи влево
	_hl(4, 5, 5, "FIRE", _M)
	_P(3, 4, "FIRE", _L)
	_P(2, 6, "FIRE", _M)
	# искра впереди
	_P(11, 3, "HUD_GOLD", _L)


## frost_nova — разлёт ледяных игл: Y CRYSTAL + золотые искры-блики.
func _ic_frost_nova(ox: int) -> void:
	# hub
	_dot(7, 5, "CRYSTAL")
	# игла вверх-влево
	_diag([[6, 4], [5, 3], [4, 2], [3, 1]], "CRYSTAL", _M)
	_diag([[5, 4], [4, 3]], "CRYSTAL", _L)
	_diag([[8, 5]], "CRYSTAL", _D)
	# игла вправо (короткая — не спорить с молотом справа)
	_diag([[9, 5], [10, 4], [11, 4]], "CRYSTAL", _M)
	_diag([[11, 5]], "CRYSTAL", _D)
	# игла вниз — ноги ряда
	_diag([[8, 8], [8, 9], [8, 10]], "CRYSTAL", _M)
	_diag([[9, 8], [9, 9]], "CRYSTAL", _D)
	_diag([[8, 11], [9, 11]], "CRYSTAL", _O)
	# холодные искры — золото
	_P(4, 8, "HUD_GOLD", _M)
	_P(12, 6, "HUD_GOLD", _L)


## siphon — серп: крюк BRONZE сверху, древко вниз-влево, росчерк жизни HP_RED.
func _ic_siphon(ox: int) -> void:
	# крюк лезвия
	_diag([[8, 4], [9, 2], [11, 1], [13, 2], [13, 4], [12, 5], [10, 5]], "BRONZE", _M)
	_diag([[9, 1], [11, 0 + 1], [13, 1]], "BRONZE", _L)
	_diag([[10, 6], [12, 6], [13, 5]], "BRONZE", _D)
	_diag([[10, 7], [11, 7]], "BRONZE", _O)
	# древко наискось вниз-влево
	_diag([[7, 7], [6, 9], [5, 11]], "WOOD", _M)
	_diag([[6, 8], [5, 10]], "WOOD", _L)
	# ноги ряда
	_diag([[4, 13], [5, 13]], "WOOD", _O)
	# украденная жизнь — росчерк HP_RED
	_diag([[14, 7], [14, 8]], "HP_RED", _M)
	_P(14, 9, "HP_RED", _O)
	_P(13, 7, "HP_RED", _L)


## firestorm — огненная волна в правом поясе: крутой гребень снизу-слева вправо.
func _ic_firestorm(ox: int) -> void:
	# крутой гребень (полоса 2px)
	_diag([[4, 12], [5, 11], [6, 9], [7, 8], [8, 7], [9, 6], [10, 5],
		[11, 4]], "FIRE", _M)
	_diag([[5, 10], [7, 7], [9, 5], [10, 4]], "FIRE", _L)
	_diag([[6, 10], [8, 8], [10, 6], [11, 5]], "FIRE", _D)
	# гребень закручен
	_diag([[12, 3], [13, 3]], "FIRE", _L)
	_P(14, 4, "FIRE", _D)
	# ядра HOT
	_F(10, 4, "FIRE_HOT")
	_F(7, 7, "FIRE_HOT")
	# основание — ноги ряда
	_hl(4, 6, 13, "FIRE", _O)
	# уголь — золото
	_P(14, 10, "HUD_GOLD", _M)


# ================= мастера 48 px (ox, oy — левый верх колодца) ============
# Те же предметы, детальный эталон. Собираются примитивами; свет СЗ.

func _ms(idx: int, ox: int, oy: int) -> void:
	match idx:
		0: _ms_power_strike(ox, oy)
		1: _ms_whirlwind(ox, oy)
		2: _ms_second_wind(ox, oy)
		3: _ms_execute(ox, oy)
		4: _ms_pierce(ox, oy)
		5: _ms_volley(ox, oy)
		6: _ms_mark(ox, oy)
		7: _ms_rain(ox, oy)
		8: _ms_firebolt(ox, oy)
		9: _ms_frost_nova(ox, oy)
		10: _ms_siphon(ox, oy)
		11: _ms_firestorm(ox, oy)

## мастер: смещение координат иконки задаётся вручную; ниже — свои примитивы.
func _ramp_rect(x0: int, y0: int, x1: int, y1: int, ramp: String) -> void:
	# блок с canon-светом: LIGHT сверху/слева, DARK правый бок, низ/ноги OUTLINE
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var t := _M
			if y == y1:
				t = _O
			elif x == x1:
				t = _O if y == y1 - 1 else _D
			elif x == x0 or y == y0:
				t = _L
			_P(x, y, ramp, t)


## power_strike v2: молот крупнее, деревянная вставка, окованные шипы, пыль удара.
func _ms_power_strike(mo_x: int, mo_y: int) -> void:
	# рукоять: толстая диагональ с СЗ-гранью и булавом на конце
	var shaft := [[8, 40], [9, 39], [10, 38], [11, 36], [12, 35], [13, 33],
		[14, 32], [15, 30], [16, 29], [17, 27], [18, 26], [19, 24], [20, 23],
		[21, 21], [22, 20]]
	for p in shaft:
		_P(int(p[0]), int(p[1]), "WOOD", _M)
		_P(int(p[0]) - 1, int(p[1]), "WOOD", _L)
	# булав (утяжеление рукояти)
	_ramp_rect(6, 40, 9, 43, "WOOD")
	# кожаная обмотка HP_RED на хвате
	for i in 5:
		_P(12 + i, 35 - i, "HP_RED", _M)
		_P(11 + i, 35 - i, "HP_RED", _L)
	# голова молота: окованный блок с боковыми шипами
	_ramp_rect(18, 8, 34, 18, "IRON")
	_hl(17, 17, 9, "IRON", _L)
	# верхняя грань — скол света
	_hl(20, 30, 9, "IRON", _L)
	# шипы
	_diag([[35, 10], [36, 10], [37, 11], [38, 12]], "IRON", _M)
	_diag([[37, 13], [38, 14], [37, 15]], "IRON", _D)
	_diag([[16, 10], [15, 11]], "IRON", _L)
	# заклёпки WOOD-вкладыш поперёк головы
	_vl(26, 10, 17, "WOOD", _D)
	_vl(25, 10, 16, "WOOD", _M)
	# пыль удара: золото справа-снизу от головы
	for q in [[37, 22], [34, 25], [39, 26], [36, 29]]:
		_P(int(q[0]), int(q[1]), "HUD_GOLD", _L)
	_P(38, 24, "HUD_GOLD", _M)
	_P(35, 27, "HUD_GOLD", _M)


## whirlwind v2: лента-вихрь с утолщением, подхваченные листья/песчинки.
func _ms_whirlwind(mo_x: int, mo_y: int) -> void:
	var outer := [[40, 12], [37, 8], [33, 6], [28, 6], [24, 8], [21, 11],
		[19, 15], [19, 20], [21, 25], [24, 29], [28, 31], [32, 31], [36, 29],
		[38, 26], [38, 22], [37, 19], [34, 17], [31, 17], [28, 19], [27, 22]]
	for i in outer.size():
		var t := _L if i < 6 else (_M if i < 14 else _D)
		_P(int(outer[i][0]), int(outer[i][1]), "WATER", t)
		_P(int(outer[i][0]), int(outer[i][1]) + 1, "WATER",
			_M if i < 6 else _L if i < 14 else _O)
		_P(int(outer[i][0]) - 1, int(outer[i][1]) + 2, "WATER", _O if i >= 6 else _D)
	# песчинки в вихре
	for q in [[15, 14], [42, 18], [17, 30], [24, 30]]:
		_P(int(q[0]), int(q[1]), "HUD_GOLD", _M)
		_P(int(q[0]) + 1, int(q[1]), "HUD_GOLD", _L)
	# листья (LEAF) закручены
	for lf in [[13, 22], [39, 30]]:
		_P(int(lf[0]), int(lf[1]), "LEAF", _M)
		_P(int(lf[0]) + 1, int(lf[1]) - 1, "LEAF", _L)
		_P(int(lf[0]) - 1, int(lf[1]) + 1, "LEAF", _D)
	# хвостовой срез ленты внизу — OUTLINE ноги
	_diag([[27, 24], [28, 25], [29, 25], [30, 24]], "WATER", _O)
	# нижний ряд спирали (y+2 от i=10..12) — перетонировать в OUTLINE ноги
	_diag([[28, 33], [32, 33], [36, 31]], "WATER", _O)


## second_wind v2: крупное перо с рассечённым опахалом и ветровыми дугами.
func _ms_second_wind(mo_x: int, mo_y: int) -> void:
	# стержень — дуга BONE
	var rachis := [[30, 6], [29, 9], [27, 13], [25, 17], [23, 21], [21, 26],
		[19, 31], [17, 36], [16, 40]]
	for p in rachis:
		_P(int(p[0]), int(p[1]), "BONE", _M)
		_P(int(p[0]) - 1, int(p[1]), "BONE", _L)
	# опахало: перья вдоль стержня, справа длиннее; насечки справа снизу
	for i in range(0, 15):
		var y := 7 + i * 2
		var bx := 29 - (i * 2) / 3
		var rlen := 7 - absi(i - 5) / 2
		_hl(bx + 1, bx + rlen, y, "LEAF", _M)
		_hl(bx + 1, bx + rlen, y - 1, "LEAF", _L)
		_hl(bx - 4, bx - 1, y, "LEAF", _D)
		if i % 3 == 2:
			_P(bx + rlen + 1, y, "LEAF", _O)
	# насечка опахала справа снизу (рваный ветер)
	for g in [[20, 27], [17, 31], [15, 35]]:
		_P(int(g[0]), int(g[1]), "LEAF", _O)
	# очин: ноги ряда OUTLINE
	_diag([[15, 42], [16, 42], [17, 42]], "BONE", _O)
	# ветровые дуги справа — HUD_GOLD
	for arc in [[38, 20], [39, 26], [37, 32]]:
		var ax := int(arc[0])
		var ay := int(arc[1])
		_hl(ax, ax + 4, ay, "HUD_GOLD", _M)
		_hl(ax, ax + 4, ay - 1, "HUD_GOLD", _L)
		_P(ax + 5, ay, "HUD_GOLD", _O)


## execute v2: двуручный палаш вниз, широкое лезвие, fuller, красная обмотка.
func _ms_execute(mo_x: int, mo_y: int) -> void:
	# лезвие: трапеция к острию
	for i in 22:
		var y := 10 + i
		var half := maxi(1, 5 - i / 5)
		_hl(24 - half, 24 + half, y, "IRON", _M)
		_P(24 - half, y, "IRON", _L)
		if half >= 2:
			_P(24 + half, y, "IRON", _D)
			_P(24, y, "IRON", _D if i % 2 else _M)
	# дол (fuller) — светлая полоса слева-в центре
	_vl(22, 12, 26, "IRON", _L)
	# острие и ноги ряда
	_hl(23, 25, 32, "IRON", _D)
	_hl(24, 24, 33, "IRON", _O)
	# крестовина WOOD
	_rect(14, 34, 7, 10, "WOOD", _M)
	_hl(14, 34, 7, "WOOD", _L)
	_hl(14, 34, 11, "WOOD", _O)
	# рукоять: красная обмотка крест-накрест
	for i in 12:
		var y := 12 + i * 2
		_hl(22, 26, y, "HP_RED", _M)
		_hl(22, 24, y, "HP_RED", _L)
		_hl(22, 26, y + 1, "HP_RED", _D if i % 2 else _M)
	# яблоко — золото
	_ramp_rect(21, 37, 27, 41, "HUD_GOLD")
	# блик на лезвии — одна точка HOT-канона не у огня → IRON LIGHT уже есть;
	# добавим искру золота у острия
	_P(29, 30, "HUD_GOLD", _L)


## pierce v2: крупная стрела вверх-вправо со свистом, перья CLOTH ступенями.
func _ms_pierce(mo_x: int, mo_y: int) -> void:
	# древко толстая диагональ (2px) WOOD с СЗ-гранью
	for i in 26:
		var x := 10 + i
		var y := 40 - i
		_P(x, y, "WOOD", _M)
		_P(x + 1, y + 1, "WOOD", _D)
		if i % 4 < 2:
			_P(x, y + 1, "WOOD", _L)
		else:
			_P(x, y + 1, "WOOD", _M)
	# наконечник: лопастной ромб IRON с хребтом
	var head := [[36, 12], [37, 11], [38, 10], [39, 9], [40, 8]]
	for i in head.size():
		_P(int(head[i][0]), int(head[i][1]), "IRON", _M)
		_P(int(head[i][0]) + 1, int(head[i][1]) + 1, "IRON", _D)
		_P(int(head[i][0]) - 1, int(head[i][1]) + 1, "IRON", _L)
	_P(41, 7, "IRON", _L)
	# втулка золота
	_diag([[35, 14], [36, 13]], "HUD_GOLD", _M)
	# оперенье: два пера CLOTH ступенями
	for k in 4:
		_hl(6 + k, 8 + k, 44 - k * 2, "CLOTH", _M if k % 2 else _L)
		_hl(8 + k * 2, 10 + k * 2, 42 - k * 2, "CLOTH", _D)
	_hl(5, 10, 45, "CLOTH", _O)
	# свист воздуха: золото впереди острия
	_hl(43, 45, 6, "HUD_GOLD", _L)
	_hl(42, 44, 10, "HUD_GOLD", _M)


## volley v2: тугой лук фронтально, тетива на стреле, перья, детали рога.
func _ms_volley(mo_x: int, mo_y: int) -> void:
	# плечи лука — толстая дуга BARK с захватами
	var bow := [[22, 5], [18, 8], [15, 13], [13, 19], [12, 26], [13, 33],
		[15, 39], [18, 43], [22, 46]]
	for p in bow:
		var bx := int(p[0])
		var by := int(p[1])
		_P(bx, by, "BARK", _M)
		_P(bx + 1, by, "BARK", _L)
		_P(bx, by + 1, "BARK", _D)
	# нашлепки на концах — HP_RED
	_P(22, 4, "HP_RED", _L)
	_P(22, 45, "HP_RED", _M)
	# тетива оттянута к стреле
	_diag([[22, 5], [25, 12], [27, 20], [28, 26],
		[27, 32], [25, 40], [22, 46]], "PARCHMENT", _M)
	# стрела: древко вправо, наконечник, перья у тетивы
	_hl(28, 40, 26, "WOOD", _M)
	_hl(28, 40, 25, "WOOD", _L)
	_hl(28, 40, 27, "WOOD", _D)
	_diag([[41, 26], [42, 25], [43, 24]], "IRON", _M)
	_P(43, 25, "IRON", _D)
	_P(44, 24, "IRON", _L)
	_diag([[27, 24], [29, 22], [30, 21]], "CLOTH", _L)
	_diag([[27, 28], [29, 30], [30, 31]], "CLOTH", _D)
	# ноги ряда: нижний захват лука (внутри бокса, строка 47)
	_hl(21, 23, 47, "BARK", _O)


## mark v2: три глубоких коготных борозды с мякотом HP_RED и золотой пылью.
func _ms_mark(mo_x: int, mo_y: int) -> void:
	var claws := [
		[[8, 10], [12, 15], [16, 20], [20, 25], [23, 29]],
		[[20, 6], [24, 11], [28, 16], [32, 21], [36, 26], [39, 30]],
		[[32, 8], [35, 12], [38, 16], [40, 19]],
	]
	for s in claws:
		for i in s.size():
			var cx := int(s[i][0])
			var cy := int(s[i][1])
			_P(cx, cy, "HP_RED", _L)
			_P(cx + 1, cy + 1, "HP_RED", _M)
			_P(cx + 2, cy + 2, "HP_RED", _D)
			_P(cx + 2, cy + 3, "HP_RED", _O)
	# золотая пыль метки между бороздами
	for q in [[17, 12], [25, 26], [31, 12], [27, 30]]:
		_P(int(q[0]), int(q[1]), "HUD_GOLD", _L)
		_P(int(q[0]) + 1, int(q[1]) + 1, "HUD_GOLD", _M)
	# ноги ряда: хвост средней борозды уходит в OUTLINE
	_diag([[39, 31], [40, 31], [41, 31]], "HP_RED", _O)


## rain v2: крупный опрокинутый колчан: ворс, ремень, пряжка, высыпающиеся стрелы.
func _ms_rain(mo_x: int, mo_y: int) -> void:
	# корпус: овал-чулок BARK лёжа
	_ramp_rect(6, 26, 26, 42, "BARK")
	# ворс по верхнему краю (светлая бахрома)
	for i in 9:
		_P(7 + i * 2, 25, "BONE", _L)
		_P(8 + i * 2, 25, "BONE", _M)
	# ремень HP_RED с золотой пряжкой
	_vl(14, 27, 42, "HP_RED", _M)
	_vl(15, 27, 42, "HP_RED", _L)
	_vl(16, 27, 42, "HP_RED", _D)
	_rect(12, 18, 33, 36, "HUD_GOLD", _M)
	_hl(12, 18, 33, "HUD_GOLD", _L)
	_hl(12, 18, 36, "HUD_GOLD", _O)
	# горловина вправо: устье PARCHMENT, проём тёмный
	_rect(26, 28, 28, 40, "BARK", _D)
	_vl(28, 28, 39, "PARCHMENT", _M)
	_vl(28, 40, 40, "PARCHMENT", _O)
	# стрелы высыпаются фонтаном вправо-вверх (3 шт, наклонены)
	for a in [[[32, 30], 1], [[34, 22], 1], [[30, 14], 1]]:
		var ax := int(a[0][0])
		var ay := int(a[0][1])
		for k in 7:
			_P(ax + k, ay - k, "WOOD", _M)
			_P(ax + k, ay - k + 1, "WOOD", _L)
		_P(ax + 7, ay - 7, "IRON", _L)
		_P(ax + 8, ay - 7, "IRON", _D)
		_P(ax - 1, ay + 1, "CLOTH", _M)
		_P(ax, ay + 2, "CLOTH", _D)
	# ноги ряда
	_hl(6, 26, 43, "BARK", _O)


## firebolt v2: комета с чешуйчатым хвостом, ядром HOT, россыпью углей.
func _ms_firebolt(mo_x: int, mo_y: int) -> void:
	# голова — капля НЕ: гребешковый снаряд, горизонтальный «гвоздь»
	_ramp_rect(30, 18, 42, 27, "FIRE")
	_hl(30, 41, 18, "FIRE", _L)
	_P(43, 22, "FIRE", _M)
	_P(43, 23, "FIRE", _D)
	_P(44, 22, "FIRE", _O)
	_F(38, 22, "FIRE_HOT")
	_F(39, 23, "FIRE_HOT")
	# гребень пламени сверху головы
	_diag([[32, 16], [33, 15], [35, 16], [36, 14],
		[38, 16]], "FIRE", _L)
	# хвост: чешуйки FIRE убывают влево рядами
	var tail := [[10, 22], [13, 21], [16, 20], [19, 21], [22, 22], [25, 21],
		[12, 25], [15, 26], [18, 27], [21, 26], [24, 25]]
	for t in tail:
		var tx := int(t[0])
		var ty := int(t[1])
		_P(tx, ty, "FIRE", _M)
		_P(tx + 1, ty, "FIRE", _L)
		_P(tx, ty + 2, "FIRE", _D)
	_hl(11, 24, 29, "FIRE", _O)
	# угли впереди и сзади — золото
	for q in [[44, 17], [46, 26], [7, 24], [25, 28]]:
		_P(int(q[0]), int(q[1]), "HUD_GOLD", _L)


## frost_nova v2: разлёт крупных игл CRYSTAL с осколками WATER и искрами.
func _ms_frost_nova(mo_x: int, mo_y: int) -> void:
	# ядро: ромб с facet-светом
	_ramp_rect(21, 21, 27, 27, "CRYSTAL")
	_P(24, 24, "CRYSTAL", _L)
	# игла вверх-влево
	var n1 := [[19, 19], [17, 17], [15, 15], [13, 12], [11, 10], [9, 7]]
	for i in n1.size():
		var x := int(n1[i][0])
		var y := int(n1[i][1])
		_P(x, y, "CRYSTAL", _M)
		_P(x - 1, y, "CRYSTAL", _L)
		_P(x + 1, y + 1, "CRYSTAL", _D)
		_P(x + 1, y + 2, "CRYSTAL", _O)
	# игла вправо
	var n2 := [[29, 24], [32, 22], [35, 21], [38, 19], [41, 18]]
	for i in n2.size():
		var x := int(n2[i][0])
		var y := int(n2[i][1])
		_P(x, y, "CRYSTAL", _M)
		_P(x, y - 1, "CRYSTAL", _L)
		_P(x, y + 1, "CRYSTAL", _D)
	# игла вниз
	for i in 8:
		var y := 29 + i
		_P(24, y, "CRYSTAL", _M)
		_P(25, y, "CRYSTAL", _D)
		_P(23, y, "CRYSTAL", _L)
		if i >= 6:
			_P(24, y, "CRYSTAL", _O)
	_P(24, 37, "CRYSTAL", _O)
	_P(25, 37, "CRYSTAL", _O)
	# осколки WATER вокруг
	for q in [[14, 28], [17, 32], [34, 30], [37, 28], [12, 24], [31, 12]]:
		_P(int(q[0]), int(q[1]), "WATER", _L)
		_P(int(q[0]) + 1, int(q[1]) + 1, "WATER", _M)
	# искра горячего воздуха у острия иглы (золото — контраст холода)
	_P(8, 6, "HUD_GOLD", _L)


## siphon v2: серп с гравировкой, кованое лезвие, украденная жизнь — росчерк.
func _ms_siphon(mo_x: int, mo_y: int) -> void:
	# древко WOOD наискось, толстое
	for i in 22:
		var x := 22 - (i / 3)
		var y := 20 + i
		_P(x, y, "WOOD", _M)
		_P(x - 1, y, "WOOD", _L)
		_P(x + 1, y, "WOOD", _D)
	_hl(14, 16, 43, "WOOD", _O)
	# набалдашник HP_RED
	_ramp_rect(14, 41, 17, 44, "HP_RED")
	# лезвие-крюк: внешняя дуга
	var blade := [[23, 18], [25, 14], [28, 11], [32, 9], [36, 9], [39, 11],
		[41, 14], [41, 17], [39, 20], [36, 22], [33, 23], [30, 23]]
	for i in blade.size():
		var x := int(blade[i][0])
		var y := int(blade[i][1])
		_P(x, y, "IRON", _M)
		_P(x, y - 1, "IRON", _L)
		_P(x, y + 1, "IRON", _D)
	_P(42, 12, "IRON", _L)
	# внутренняя кромка лезвия — OUTLINE ряда кончика
	_diag([[30, 24], [32, 24], [34, 24], [36, 24],
		[38, 23]], "IRON", _O)
	# гравировка на лезвии — золото
	_diag([[31, 14], [33, 13], [35, 13], [37, 15]], "HUD_GOLD", _M)
	_P(34, 16, "HUD_GOLD", _L)
	# украденная жизнь — росчерк HP_RED от острия вниз
	_diag([[41, 20], [42, 22], [42, 25], [41, 28]], "HP_RED", _M)
	_diag([[40, 22], [40, 26]], "HP_RED", _L)
	_diag([[41, 29], [42, 29]], "HP_RED", _O)


## firestorm v2: волна с гребнем-валом, языками, углями; низ — угольная основа.
func _ms_firestorm(mo_x: int, mo_y: int) -> void:
	# тело волны: ступенчатый склон (низ тяжёлый)
	var steps := [[8, 42, 40], [10, 40, 36], [13, 38, 32], [16, 36, 28],
		[19, 34, 24], [23, 32, 20], [27, 30, 17], [31, 28, 14], [35, 26, 12]]
	for s in steps:
		_hl(int(s[0]), 42, int(s[2]), "FIRE", _M)
		_hl(int(s[0]), int(s[0]) + 2, int(s[2]), "FIRE", _L)
	# склон световой — по верхней кромке
	var crest := [[8, 41], [11, 39], [14, 37], [17, 35], [21, 31], [25, 27],
		[29, 24], [33, 21], [37, 18], [40, 16]]
	for p in crest:
		_P(int(p[0]), int(p[1]), "FIRE", _L)
	# гребень-вал закручен влево: языки сверху
	_diag([[38, 12], [39, 10], [41, 10], [42, 12]], "FIRE", _L)
	_diag([[34, 13], [35, 11]], "FIRE", _L)
	_diag([[43, 14], [43, 16], [44, 18]], "FIRE", _D)
	_P(44, 20, "FIRE", _O)
	# ядра HOT в теле волны
	_F(39, 18, "FIRE_HOT")
	_F(34, 24, "FIRE_HOT")
	_F(28, 32, "FIRE_HOT")
	# основание — пепельный подсвет CHAR и OUTLINE ноги
	_hl(8, 43, 43, "FIRE", _O)
	_hl(6, 43, 44, "CHAR", _D)
	_hl(6, 43, 45, "CHAR", _O)
	# угли впереди — золото
	for q in [[44, 38], [46, 41], [4, 44], [2, 40]]:
		_P(int(q[0]), int(q[1]), "HUD_GOLD", _M)


# ==================== сборка листа и самопроверки ====================

func _bake_sheet() -> void:
	var w := PAD * 2 + COLS * PITCH
	var h := PAD * 2 + S + 4 + M
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_img.fill(PAL.SHEET.BG)
	for i in COLS:
		var colx := PAD + i * PITCH
		# сетка колонок
		if i > 0:
			_vl(colx - 1, PAD, h - PAD - 1, "PARCHMENT", _O)
		# бокс иконки: рамка PANEL + тёмная подложка, иконка по центру колонки
		var ix := colx + (PITCH - S) / 2
		_frame(ix - 1, PAD - 1, ix + S, PAD + S, "STONE", _O)
		_ox = ix
		_oy = PAD
		_ic16(i, 0)
		_ox = 0
		_oy = 0
		# мастер
		var mx := colx + (PITCH - M) / 2
		_hl(colx, colx + PITCH - 1, PAD + S + 2, "STONE", _O)
		_ox = mx
		_oy = PAD + S + 4
		_ms(i, 0, 0)
		_ox = 0
		_oy = 0
		# бокс мастера — тонкая линия снизу
		_hl(mx - 1, mx + M, PAD + S + 4 + M, "STONE", _O)


func _icon_boxes() -> Array:
	# прямоугольники «холстов» спрайтов: [x0, y0, w, h] (12×16 и 12×48)
	var out: Array = []
	for i in COLS:
		var colx := PAD + i * PITCH
		out.append([colx + (PITCH - S) / 2, PAD, S, S])
	for i in COLS:
		var colx := PAD + i * PITCH
		out.append([colx + (PITCH - M) / 2, PAD + S + 4, M, M])
	return out


func _outline_tones() -> Dictionary:
	var o := {}
	for rn in PAL.RAMPS:
		o[PAL.key((PAL.RAMPS[rn] as Array)[3])] = true
	return o


func _palette_keys() -> Dictionary:
	var k := {}
	for col in PAL.color_index():
		k[col] = true
	return k


func _self_check() -> void:
	var fails := 0
	var palkeys := _palette_keys()
	var outline_tones := _outline_tones()
	var idx := 0
	var masks: Array = []
	for box in _icon_boxes():
		var x0 := int(box[0])
		var y0 := int(box[1])
		var bw := int(box[2])
		var bh := int(box[3])
		var name := "%s@%d" % [SKILLS[idx % COLS], 16 if idx < COLS else 48]
		var colors := {}
		var bottom_t := -1
		var top_t := 1 << 30
		var dirty := 0
		var light_top := false
		var mask: Array = []
		for y in bh:
			var row: Array = []
			for x in bw:
				var c := _img.get_pixel(x0 + x, y0 + y)
				var k := PAL.key(c)
				if palkeys.has(k):
					colors[k] = true
					row.append(true)
					if y > bottom_t:
						bottom_t = y
					if y < top_t:
						top_t = y
					if k in _light_keys():
						light_top = true   # грубый флаг; точная граница ниже
				else:
					# техническая область (фон/рамка SHEET/STONE) вне спрайта
					row.append(false)
					if c.a > 0.5 and not _is_tech(c):
						dirty += 1
			mask.append(row)
		# СЗ-подсветка: LIGHT в ВЕРХНЕЙ ПОЛОВИНЕ самого объекта
		if light_top:
			var ok_light := false
			var mid_y := top_t + (bottom_t - top_t + 1) / 2
			for y in range(top_t, mini(mid_y + 1, bh)):
				for x in bw:
					if palkeys.has(PAL.key(_img.get_pixel(x0 + x, y0 + y))) \
							and _light_keys().has(PAL.key(_img.get_pixel(x0 + x, y0 + y))):
						ok_light = true
			light_top = ok_light
		masks.append(mask)
		if dirty > 0:
			print("SELF-CHECK FAIL %s: чужих пикселей %d" % [name, dirty])
			fails += 1
		if bottom_t < 0:
			print("SELF-CHECK FAIL %s: пустой спрайт" % name)
			fails += 1
			idx += 1
			continue
		var bad_bottom := 0
		for x in bw:
			var c := _img.get_pixel(x0 + x, y0 + bottom_t)
			var k := PAL.key(c)
			if palkeys.has(k) and not outline_tones.has(k):
				bad_bottom += 1
		if bad_bottom > 0:
			print("SELF-CHECK FAIL %s: нижний ряд не OUTLINE (%d px)" % [name, bad_bottom])
			fails += 1
		if not light_top:
			print("SELF-CHECK FAIL %s: нет СЗ-подсветки (LIGHT в верхней половине)" % name)
			fails += 1
		if colors.size() < 3:
			print("SELF-CHECK FAIL %s: цветов палитры %d < 3" % [name, colors.size()])
			fails += 1
		idx += 1
	# --- метрики 16px-ряда ---
	var mx := 0
	var sum := 0.0
	var cnt := 0
	var worst := "?"
	var pairs: Array = []
	for i in COLS:
		for j in range(i + 1, COLS):
			var inter := 0
			for y in S:
				for x in S:
					if masks[i][y][x] and masks[j][y][x]:
						inter += 1
			if inter > mx:
				mx = inter
				worst = "%s+%s" % [SKILLS[i], SKILLS[j]]
			sum += inter
			cnt += 1
			pairs.append([inter, "%s+%s" % [SKILLS[i], SKILLS[j]]])
	pairs.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	var tops := ""
	for t in pairs.slice(0, 5):
		tops += "%s=%d " % [t[1], t[0]]
	print("METRIC top_pairs: ", tops)
	print("METRIC new max_pair_inter=%d (worst %s) mean=%.2f  [old: max=11 mean=4.61]" %
			[mx, worst, sum / cnt])
	if mx > MAX_INTER:
		print("SELF-CHECK FAIL: пересечение масок %d > порога %d" % [mx, MAX_INTER])
		fails += 1
	var ssum := 0.0
	for i in COLS:
		var s2 := 0.0
		var n2 := 0
		var x0 := PAD + i * PITCH + (PITCH - S) / 2
		for y in S:
			for x in S:
				if masks[i][y][x]:
					s2 += _img.get_pixel(x0 + x, PAD + y).s
					n2 += 1
		if n2 > 0:
			print("METRIC %s colors=%d sat=%.3f px=%d" % [SKILLS[i], _colors16(i), s2 / n2, n2])
			ssum += s2 / n2
	var mean_sat := ssum / COLS
	print("METRIC new mean_sat=%.3f  [old: 0.548]" % mean_sat)
	if mean_sat < MIN_SAT:
		print("SELF-CHECK FAIL: средняя насыщенность %.3f < %.2f" % [mean_sat, MIN_SAT])
		fails += 1
	# 7) c15 equality-пин: рантайм-рендер ui_icons.skill_atlas() обязан быть
	#    попиксельно равен 16px-ряду этого утверждённого листа (0 расхождений).
	var ui := load("res://scripts/ui_icons.gd")
	var rimg: Image = ui.skill_atlas().get_image()
	if rimg.get_width() != COLS * S or rimg.get_height() != S:
		print("SELF-CHECK FAIL: ui_icons.atlas size %dx%d != %dx%d"
				% [rimg.get_width(), rimg.get_height(), COLS * S, S])
		fails += 1
	else:
		var mism := 0
		for i in COLS:
			var ix := PAD + i * PITCH + (PITCH - S) / 2
			for y in S:
				for x in S:
					if rimg.get_pixel(i * S + x, y).to_argb32() != _img.get_pixel(ix + x, PAD + y).to_argb32():
						mism += 1
		print("METRIC ui_icons_equality mismatches=%d" % mism)
		if mism > 0:
			print("SELF-CHECK FAIL: рантайм ui_icons отличается от листа (%d px)" % mism)
			fails += 1
	if fails > 0:
		print("SELF-CHECK: %d FAIL" % fails)
		quit(1)
	print("SELF-CHECK PASS")


var _lk: Dictionary = {}
func _light_keys() -> Dictionary:
	if _lk.is_empty():
		for rn in PAL.RAMPS:
			_lk[PAL.key((PAL.RAMPS[rn] as Array)[0])] = true
	return _lk


func _is_tech(c: Color) -> bool:
	for k in PAL.SHEET:
		if PAL.key(c) == PAL.key(PAL.SHEET[k]):
			return true
	for rn in ["STONE", "PARCHMENT"]:
		if c.to_argb32() in (PAL.RAMPS[rn] as Array).map(func(t): return PAL.key(t)):
			return true
	return false


func _colors16(i: int) -> int:
	var x0 := PAD + i * PITCH + (PITCH - S) / 2
	var cs := {}
	var palkeys := _palette_keys()
	for y in S:
		for x in S:
			var k := PAL.key(_img.get_pixel(x0 + x, PAD + y))
			if palkeys.has(k):
				cs[k] = true
	return cs.size()


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: sheet_icons.gd -- <out.png>")
		quit(2)
		return
	_bake_sheet()
	var out := String(args[0])
	if not out.ends_with(".png"):
		out = out.path_join("sheet_icons_v2.png")
	var err := _img.save_png(out)
	if err != OK:
		print("SAVE FAIL ", err, " -> ", out)
		quit(3)
		return
	_self_check()
	print("saved ", out, " ", _img.get_width(), "x", _img.get_height())
	quit(0)
