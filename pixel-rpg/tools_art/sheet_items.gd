extends SceneTree
## c24 «Предметные иконки v1» — лист на вердикт пользователя (игра НЕ тронута).
##
## Инвентарь (по коду: ui_icons.gd::_stamp_item; потребители — hud.gd
## potion_btn=herb, ash_icon.gd=ash, root/mushroom/berry/glowcap — сбор/лут):
##   herb, mushroom, root, ash, berry, glowcap  (6 id; fallback-линия — техстаб).
## Текущий вид — стабы эпохи t52: сырые Color вне PixelPalette; скрипт печатает
## их метрики как baseline («до») прямо из рантайм-рендера item_icon().
##
## Лист: 6 колонок; в колонке — иконка 16 px (верх) и мастер 48 px (детальный
## эталон). Порядок = ITEMS. Фон/сетка — технические SHEET/STONE/PARCHMENT.
## Цвета объектов — только PixelPalette.RAMPS/FLATS. Свет СЗ, контур —
## OUTLINE-тон своего материала.
##
## Запуск: godot --headless --path pixel-rpg -s res://tools_art/sheet_items.gd -- <out.png>
##
## Самопроверки (exit != 0 при провале):
##  1) чистота палитры: внутри боксов только RAMPS/FLATS (0 off);
##  2) нижний ряд силуэта — только OUTLINE-тона;
##  3) СЗ-подсветка: LIGHT в верхней половине каждого спрайта;
##  4) >=3 цвета палитры на спрайт;
##  5) попарная различимость 16px-ряда: popcount пикселей с разным цветом
##     (15 пар, min/mean/max числами): min >= MIN_DIFF и не хуже стабов;
##  6) средняя насыщенность 16px-ряда >= MIN_SAT и не хуже стабов;
##  7) baseline-снимок рантайм-стабов ui_icons.item_icon(): off-палитра,
##     popcount min/max/mean, sat — печатаются числами («до»);
##  8) c25 equality-пин (прецедент c15): рантайм item_icon() == 16px-ряд листа
##     попиксельно, mismatches=0 (техфон слота не в счёт).

const S := 16
const M := 48
const PITCH := 50
const PAD := 2

const PAL := preload("res://scripts/pixel_palette.gd")

const ITEMS := ["herb", "mushroom", "root", "ash", "berry", "glowcap"]
const COLS := 6

# пороги: popcount расхождения цветов в паре слотов и насыщение
const MIN_DIFF := 64   # из 256 px слота — минимум «различимо на глаз»
const MIN_SAT := 0.48  # природные материалы (пепел/кость) ниже скилловых;
                       # главный гейт — «не хуже стабов» (см. baseline-блок)

const _L := 0
const _M := 1
const _D := 2
const _O := 3

var _img: Image
var _ox := 0
var _oy := 0

# ---------- примитивы (цвета — только палитра) ----------

func _P(x: int, y: int, ramp: String, tone: int) -> void:
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

# ================= 16 px иконки =================
# Правило ряда: нижний пиксельный ряд объекта — OUTLINE-тон; LIGHT — верх/лево
# открытой грани; правый бок — DARK.

func _ic16(i: int) -> void:
	match i:
		0: _ic_herb()
		1: _ic_mushroom()
		2: _ic_root()
		3: _ic_ash()
		4: _ic_berry()
		5: _ic_glowcap()

## herb — пучок из трёх листьев, перевязанный золотой лентой.
func _ic_herb() -> void:
	# три листа-клинка (средний выше): левый край LIGHT, ядро MID, правый DARK,
	# основание листа — OUTLINE-тон LEAF
	for b in [[4, 5, 11], [7, 2, 11], [10, 4, 11]]:
		var bx: int = b[0]
		var y0: int = b[1]
		var y1: int = b[2]
		_P(bx, y0, "LEAF", _L)
		_P(bx + 1, y0 + 1, "LEAF", _M)
		for y in range(y0 + 1, y1):
			_P(bx, y, "LEAF", _L)
			_P(bx + 1, y, "LEAF", _M)
		_P(bx + 2, y0 + 2, "LEAF", _D)
		for y in range(y0 + 3, y1):
			_P(bx + 2, y, "LEAF", _D)
		_hl(bx, bx + 2, y1, "LEAF", _O)
	# перевязь — золотая лента (акцент «связанный сбор»), низ — OUTLINE золота
	_hl(3, 12, 12, "HUD_GOLD", _L)
	_hl(3, 12, 13, "HUD_GOLD", _M)
	_hl(3, 12, 14, "HUD_GOLD", _O)

## mushroom — боровик: шляпка HP_RED с костяными пятнами, ножка BONE.
func _ic_mushroom() -> void:
	_hl(6, 9, 4, "HP_RED", _L)
	_hl(4, 7, 5, "HP_RED", _L)
	_hl(8, 11, 5, "HP_RED", _M)
	_hl(3, 7, 6, "HP_RED", _L)
	_hl(8, 11, 6, "HP_RED", _M)
	_hl(12, 13, 6, "HP_RED", _D)
	_hl(2, 5, 7, "HP_RED", _L)
	_hl(6, 10, 7, "HP_RED", _M)
	_hl(11, 13, 7, "HP_RED", _D)
	_hl(3, 12, 8, "HP_RED", _O)        # кайма низа шляпки
	# костяные пятна
	_F(5, 5, "FIRE_HOT")
	_P(6, 6, "BONE", _L)
	_P(9, 5, "BONE", _M)
	_P(11, 7, "BONE", _M)
	_P(4, 7, "BONE", _L)
	# ножка (кремовая, как у боровика): свет левый, тень правый, раструб внизу
	_vl(6, 9, 12, "PARCHMENT", _L)
	_hl(7, 8, 9, "PARCHMENT", _M)
	_vl(7, 10, 12, "PARCHMENT", _M)
	_vl(9, 9, 12, "PARCHMENT", _D)
	_hl(6, 9, 13, "PARCHMENT", _M)
	_hl(5, 10, 14, "PARCHMENT", _O)

## root — корень с отпиленным верхом (кремовый срез), усиками и золотым
## кончиком (акцент «ценная сердцевина»).
func _ic_root() -> void:
	# срез — светлая кремовая шапка
	_hl(6, 10, 3, "PARCHMENT", _L)
	_hl(6, 10, 4, "PARCHMENT", _M)
	# тело: изогнутый ствол BARK (свет слева)
	_P(6, 5, "BARK", _L)
	_hl(7, 9, 5, "BARK", _M)
	_vl(6, 6, 8, "BARK", _L)
	_hl(7, 8, 6, "BARK", _M)
	_vl(8, 7, 9, "BARK", _M)
	_vl(9, 6, 8, "BARK", _D)
	_P(6, 9, "BARK", _L)
	_hl(7, 9, 9, "BARK", _M)
	# усики
	_diag([[10, 7], [11, 8]], "BARK", _D)
	_diag([[5, 10], [4, 11]], "BARK", _D)
	_diag([[10, 10], [11, 11]], "BARK", _D)
	# сужение к кончику
	_vl(7, 10, 11, "BARK", _M)
	_vl(8, 10, 11, "BARK", _D)
	# золотая сердцевина кончика (акцент) и OUTLINE-стопа
	_hl(7, 9, 12, "HUD_GOLD", _L)
	_hl(7, 9, 13, "HUD_GOLD", _M)
	_hl(6, 9, 14, "BARK", _O)
	# росток на срезе (свежий сбор)
	_P(7, 2, "LEAF", _M)
	_P(8, 1, "LEAF", _L)
	_P(9, 2, "LEAF", _D)
	# комья земли
	_P(4, 7, "ASH_GROUND", _M)
	_P(12, 9, "ASH_GROUND", _M)

## ash — горка пепла с тлеющими углями (акцент ASH_EMBER) и дымком.
func _ic_ash() -> void:
	# дымки (северо-запад — вверх-влево)
	_diag([[7, 3], [6, 4], [7, 5]], "PARCHMENT", _M)
	_diag([[10, 4], [10, 6]], "PARCHMENT", _D)
	# горка: светлая верхушка слева, тело MID, тень справа
	_hl(7, 8, 8, "ASH_GROUND", _L)
	_P(6, 9, "ASH_GROUND", _L)
	_hl(7, 9, 9, "ASH_GROUND", _M)
	_hl(4, 9, 10, "ASH_GROUND", _M)
	_hl(10, 11, 10, "ASH_GROUND", _D)
	_P(3, 11, "ASH_GROUND", _L)
	_hl(4, 10, 11, "ASH_GROUND", _M)
	_hl(11, 12, 11, "ASH_GROUND", _D)
	_hl(2, 13, 12, "ASH_GROUND", _M)
	_hl(5, 10, 13, "ASH_EMBER", _M)
	_hl(2, 4, 13, "ASH_GROUND", _D)
	_hl(11, 13, 13, "ASH_GROUND", _D)
	_hl(1, 14, 14, "ASH_GROUND", _O)
	# тлеющие угли — смысл предмета
	_P(5, 12, "ASH_EMBER", _L)
	_P(6, 11, "ASH_EMBER", _L)
	_P(7, 12, "ASH_EMBER", _M)
	_P(8, 12, "ASH_EMBER", _M)
	_P(9, 11, "ASH_EMBER", _M)
	_P(10, 12, "ASH_EMBER", _D)
	_P(11, 12, "ASH_EMBER", _D)
	_F(8, 10, "FIRE_HOT")

## berry — гроздь трёх ягод HP_RED на ветке с листом.
func _ic_berry() -> void:
	# ветка и лист
	_diag([[8, 4], [8, 5], [7, 6], [7, 7]], "BARK", _M)
	_diag([[9, 3], [10, 3], [11, 4]], "LEAF", _L)
	_diag([[10, 4], [11, 5], [12, 5]], "LEAF", _M)
	_P(12, 6, "LEAF", _D)
	# ягоды 2x2 с собственным светом; низ каждой — OUTLINE
	_P(4, 8, "HP_RED", _L)
	_P(5, 8, "HP_RED", _M)
	_P(4, 9, "HP_RED", _M)
	_hl(4, 5, 10, "HP_RED", _O)
	_P(9, 9, "HP_RED", _L)
	_P(10, 9, "HP_RED", _M)
	_P(9, 10, "HP_RED", _M)
	_hl(9, 10, 11, "HP_RED", _O)
	_P(6, 11, "HP_RED", _L)
	_P(7, 11, "HP_RED", _M)
	_P(6, 12, "HP_RED", _M)
	_hl(6, 7, 13, "HP_RED", _O)
	# концы грозди (самый нижний ряд)
	_P(5, 14, "HP_RED", _O)
	_P(8, 14, "HP_RED", _O)

## glowcap — светособака: колокол-фонарь CRYSTAL с горячим ядром, лучами и
## тонкой костяной ножкой.
func _ic_glowcap() -> void:
	# лучи (NW-ориентированные штрихи)
	_P(4, 3, "CRYSTAL", _L)
	_P(3, 5, "CRYSTAL", _L)
	_P(12, 3, "CRYSTAL", _M)
	_P(13, 5, "CRYSTAL", _M)
	# колокол: узкий верх — распор вниз; свет слева
	_hl(7, 8, 4, "CRYSTAL", _L)
	_hl(6, 9, 5, "CRYSTAL", _L)
	_hl(10, 10, 5, "CRYSTAL", _M)
	_hl(5, 8, 6, "CRYSTAL", _L)
	_hl(9, 11, 6, "CRYSTAL", _M)
	_hl(5, 8, 7, "CRYSTAL", _L)
	_hl(9, 11, 7, "CRYSTAL", _M)
	_hl(12, 12, 7, "CRYSTAL", _D)
	_hl(4, 11, 8, "CRYSTAL", _M)
	_P(4, 8, "CRYSTAL", _L)
	_hl(12, 12, 8, "CRYSTAL", _D)
	_hl(4, 12, 9, "CRYSTAL", _O)       # кайма раструба
	# горячее ядро под куполом
	_F(7, 7, "FIRE_HOT")
	_P(6, 8, "CRYSTAL", _L)
	_P(8, 8, "CRYSTAL", _L)
	# ножка (светящийся кристалл, не кость — держит акцент предмета)
	_vl(7, 10, 13, "CRYSTAL", _L)
	_vl(8, 10, 13, "CRYSTAL", _M)
	_hl(7, 8, 14, "CRYSTAL", _O)

# ================= мастера 48 px =================

func _ms(i: int) -> void:
	match i:
		0: _ms_herb()
		1: _ms_mushroom()
		2: _ms_root()
		3: _ms_ash()
		4: _ms_berry()
		5: _ms_glowcap()

func _ms_herb() -> void:
	# три широких листа с прожилкой; перевязь в 3 ряда с хвостами
	for b in [[10, 12, 33], [19, 4, 33], [28, 9, 33]]:
		var bx: int = b[0]
		var y0: int = b[1]
		var y1: int = b[2]
		_P(bx + 1, y0, "LEAF", _L)
		_hl(bx, bx + 2, y0 + 2, "LEAF", _L)
		for y in range(y0 + 3, y1):
			_P(bx, y, "LEAF", _L)
			_P(bx + 1, y, "LEAF", _L)
			_P(bx + 2, y, "LEAF", _D)
		_P(bx - 1, y0 + 6, "LEAF", _M)
		_hl(bx - 1, bx + 3, y1, "LEAF", _O)
	# кончики с изгибом
	_P(21, 5, "LEAF", _M)
	_P(12, 14, "LEAF", _M)
	_P(31, 11, "LEAF", _M)
	# перевязь
	_hl(6, 41, 34, "HUD_GOLD", _L)
	_hl(6, 41, 35, "HUD_GOLD", _M)
	_hl(6, 41, 36, "HUD_GOLD", _M)
	_P(6, 35, "HUD_GOLD", _L)
	_hl(6, 41, 37, "HUD_GOLD", _O)
	_diag([[8, 38]], "HUD_GOLD", _O)
	_diag([[39, 38]], "HUD_GOLD", _O)

func _ms_mushroom() -> void:
	# шляпка-купол с ободком и пятнами
	_hl(18, 29, 8, "HP_RED", _L)
	_hl(13, 24, 10, "HP_RED", _L)
	_hl(25, 33, 10, "HP_RED", _M)
	_hl(10, 22, 12, "HP_RED", _L)
	_hl(23, 33, 12, "HP_RED", _M)
	_hl(34, 37, 12, "HP_RED", _D)
	_hl(8, 37, 14, "HP_RED", _M)
	_hl(8, 19, 14, "HP_RED", _L)
	_hl(34, 39, 14, "HP_RED", _D)
	_hl(7, 19, 16, "HP_RED", _L)
	_hl(20, 34, 16, "HP_RED", _M)
	_hl(35, 40, 16, "HP_RED", _D)
	_hl(8, 39, 18, "HP_RED", _M)
	_hl(32, 40, 18, "HP_RED", _D)
	_hl(9, 39, 20, "HP_RED", _O)
	# пятна
	_F(16, 12, "FIRE_HOT")
	_P(15, 13, "BONE", _L)
	_P(24, 11, "BONE", _L)
	_P(25, 12, "BONE", _M)
	_P(32, 14, "BONE", _M)
	_P(33, 15, "BONE", _D)
	_P(12, 16, "BONE", _L)
	_P(21, 16, "BONE", _M)
	# юбка пластин
	_hl(12, 36, 21, "PARCHMENT", _M)
	_hl(12, 36, 22, "PARCHMENT", _D)
	# ножка с раструбом (кремовая)
	_vl(18, 23, 36, "PARCHMENT", _L)
	_hl(19, 26, 23, "PARCHMENT", _M)
	_vl(20, 24, 36, "PARCHMENT", _M)
	_vl(26, 24, 36, "PARCHMENT", _D)
	_vl(27, 23, 36, "PARCHMENT", _D)
	_hl(18, 27, 37, "PARCHMENT", _M)
	_hl(15, 30, 38, "PARCHMENT", _M)
	_hl(14, 31, 39, "PARCHMENT", _O)
	# травинка у стопы
	_vl(33, 36, 38, "GRASS", _M)
	_P(34, 36, "GRASS", _L)

func _ms_root() -> void:
	# срез
	_hl(16, 30, 8, "PARCHMENT", _L)
	_hl(16, 30, 9, "PARCHMENT", _M)
	_hl(16, 30, 10, "PARCHMENT", _D)
	# росток на срезе
	_P(21, 6, "LEAF", _M)
	_P(22, 4, "LEAF", _L)
	_P(22, 5, "LEAF", _L)
	_P(23, 6, "LEAF", _M)
	_P(24, 7, "LEAF", _D)
	# тело-веретено
	_P(15, 11, "BARK", _L)
	_hl(16, 31, 11, "BARK", _M)
	_vl(15, 12, 20, "BARK", _L)
	_vl(16, 12, 22, "BARK", _L)
	_hl(17, 26, 12, "BARK", _M)
	_vl(27, 12, 18, "BARK", _D)
	_vl(28, 12, 16, "BARK", _D)
	_hl(16, 26, 15, "BARK", _M)
	_hl(16, 27, 18, "BARK", _M)
	_hl(16, 27, 21, "BARK", _M)
	_vl(16, 23, 27, "BARK", _L)
	_hl(17, 25, 24, "BARK", _M)
	_vl(26, 22, 27, "BARK", _D)
	# шрамики
	_hl(18, 23, 14, "BARK", _D)
	_hl(18, 24, 19, "BARK", _D)
	_hl(18, 23, 26, "BARK", _D)
	# усы
	_diag([[29, 13], [32, 15], [34, 18]], "BARK", _D)
	_diag([[14, 22], [11, 24], [9, 27]], "BARK", _D)
	_diag([[27, 23], [30, 25], [32, 28]], "BARK", _D)
	_diag([[15, 28], [13, 31]], "BARK", _D)
	# сужение к кончику + золотой кончик
	_vl(19, 28, 32, "BARK", _L)
	_hl(20, 23, 28, "BARK", _M)
	_vl(24, 28, 32, "BARK", _D)
	_hl(20, 23, 31, "BARK", _M)
	_hl(19, 24, 32, "HUD_GOLD", _L)
	_hl(20, 23, 33, "HUD_GOLD", _L)
	_hl(20, 23, 34, "HUD_GOLD", _M)
	_hl(19, 24, 35, "HUD_GOLD", _D)
	_hl(19, 24, 36, "BARK", _O)
	# земляные комья
	_P(10, 14, "ASH_GROUND", _M)
	_P(33, 22, "ASH_GROUND", _M)
	_P(12, 33, "ASH_GROUND", _D)

func _ms_ash() -> void:
	# дымки
	_diag([[20, 4], [18, 6], [19, 8], [17, 10]], "PARCHMENT", _M)
	_diag([[28, 5], [29, 8], [27, 10]], "PARCHMENT", _D)
	_diag([[35, 7], [35, 9]], "PARCHMENT", _D)
	# горка
	_hl(20, 27, 14, "ASH_GROUND", _L)
	_hl(17, 19, 16, "ASH_GROUND", _L)
	_hl(20, 30, 16, "ASH_GROUND", _M)
	_hl(13, 16, 18, "ASH_GROUND", _L)
	_hl(17, 33, 18, "ASH_GROUND", _M)
	_hl(34, 35, 18, "ASH_GROUND", _D)
	_hl(9, 13, 20, "ASH_GROUND", _L)
	_hl(14, 37, 20, "ASH_GROUND", _M)
	_hl(38, 39, 20, "ASH_GROUND", _D)
	_hl(6, 41, 23, "ASH_GROUND", _M)
	_hl(6, 10, 23, "ASH_GROUND", _L)
	_hl(36, 42, 23, "ASH_GROUND", _D)
	_hl(5, 42, 26, "ASH_GROUND", _M)
	_hl(36, 43, 26, "ASH_GROUND", _D)
	_hl(4, 43, 29, "ASH_GROUND", _D)
	_hl(3, 44, 32, "ASH_GROUND", _D)
	_hl(2, 45, 35, "ASH_GROUND", _O)
	# провалы фактуры
	_hl(12, 15, 22, "ASH_GROUND", _D)
	_hl(30, 34, 24, "ASH_GROUND", _D)
	_hl(18, 21, 27, "ASH_GROUND", _O)
	_hl(28, 32, 30, "ASH_GROUND", _O)
	# угли с горячим ядром
	_P(18, 20, "ASH_EMBER", _L)
	_P(19, 21, "ASH_EMBER", _M)
	_F(20, 19, "FIRE_HOT")
	_P(26, 24, "ASH_EMBER", _M)
	_P(27, 25, "ASH_EMBER", _D)
	_P(31, 22, "ASH_EMBER", _M)
	_F(32, 21, "FIRE_HOT")
	_P(15, 26, "ASH_EMBER", _D)
	_hl(22, 24, 29, "ASH_EMBER", _D)
	_P(12, 25, "ASH_EMBER", _L)
	_P(13, 26, "ASH_EMBER", _M)
	_P(34, 27, "ASH_EMBER", _M)
	_P(23, 28, "ASH_EMBER", _M)

func _ms_berry() -> void:
	# ветка и лист
	_diag([[23, 8], [22, 11], [21, 14], [20, 17]], "BARK", _M)
	_hl(26, 30, 6, "LEAF", _L)
	_diag([[31, 7], [34, 8], [37, 11]], "LEAF", _L)
	_hl(31, 36, 9, "LEAF", _L)
	_diag([[32, 10], [35, 12], [37, 13]], "LEAF", _M)
	_diag([[38, 13], [39, 15]], "LEAF", _D)
	_hl(32, 36, 11, "LEAF", _D)
	# ягода 1 (верх-лево)
	_hl(12, 17, 18, "HP_RED", _L)
	_hl(11, 19, 20, "HP_RED", _L)
	_hl(20, 22, 20, "HP_RED", _M)
	_hl(11, 18, 23, "HP_RED", _M)
	_hl(19, 22, 23, "HP_RED", _D)
	_hl(12, 21, 25, "HP_RED", _O)
	_F(14, 19, "FIRE_HOT")
	# ягода 2 (право)
	_hl(27, 32, 22, "HP_RED", _L)
	_hl(26, 34, 24, "HP_RED", _L)
	_hl(35, 37, 24, "HP_RED", _D)
	_hl(26, 33, 27, "HP_RED", _M)
	_hl(34, 37, 27, "HP_RED", _D)
	_hl(27, 36, 29, "HP_RED", _O)
	# ягода 3 (низ-центр, крупная)
	_hl(17, 23, 28, "HP_RED", _L)
	_hl(15, 26, 30, "HP_RED", _L)
	_hl(27, 30, 30, "HP_RED", _M)
	_hl(15, 25, 33, "HP_RED", _M)
	_hl(26, 30, 33, "HP_RED", _D)
	_hl(16, 29, 35, "HP_RED", _O)
	_F(19, 29, "FIRE_HOT")
	# плодоножки
	_diag([[20, 16], [19, 17]], "BARK", _D)
	_diag([[30, 20], [29, 21]], "BARK", _D)
	_diag([[23, 26], [24, 27]], "BARK", _D)
	# травинка
	_vl(10, 33, 34, "GRASS", _M)
	_P(11, 33, "GRASS", _L)
	_P(10, 35, "GRASS", _O)

func _ms_glowcap() -> void:
	# лучи
	_diag([[12, 8], [10, 11]], "CRYSTAL", _L)
	_diag([[36, 8], [38, 11]], "CRYSTAL", _M)
	_P(8, 16, "CRYSTAL", _L)
	_P(40, 16, "CRYSTAL", _M)
	# колокол
	_hl(21, 26, 10, "CRYSTAL", _L)
	_hl(18, 27, 12, "CRYSTAL", _L)
	_hl(28, 31, 12, "CRYSTAL", _M)
	_hl(15, 27, 14, "CRYSTAL", _L)
	_hl(28, 33, 14, "CRYSTAL", _M)
	_hl(13, 27, 16, "CRYSTAL", _L)
	_hl(28, 35, 16, "CRYSTAL", _M)
	_hl(12, 27, 18, "CRYSTAL", _L)
	_hl(28, 36, 18, "CRYSTAL", _M)
	_hl(12, 27, 20, "CRYSTAL", _L)
	_hl(28, 37, 20, "CRYSTAL", _M)
	_hl(36, 37, 20, "CRYSTAL", _D)
	_hl(11, 38, 22, "CRYSTAL", _M)
	_hl(37, 38, 22, "CRYSTAL", _D)
	# внутреннее свечение
	_hl(20, 28, 15, "CRYSTAL", _L)
	_F(23, 16, "FIRE_HOT")
	_F(24, 17, "FIRE_HOT")
	_P(21, 17, "CRYSTAL", _L)
	_P(26, 16, "CRYSTAL", _M)
	# кайма раструба
	_hl(10, 38, 24, "CRYSTAL", _D)
	_hl(10, 38, 25, "CRYSTAL", _O)
	# ножка-свеча
	_vl(21, 26, 36, "BONE", _L)
	_hl(22, 25, 26, "BONE", _M)
	_vl(23, 27, 36, "BONE", _M)
	_vl(26, 26, 36, "BONE", _D)
	_hl(20, 27, 37, "BONE", _M)
	_hl(18, 29, 38, "BONE", _O)
	# искры
	_P(16, 13, "CRYSTAL", _L)
	_P(33, 15, "CRYSTAL", _M)
	_P(19, 28, "BONE", _L)

# ==================== сборка листа ====================

func _bake_sheet() -> void:
	var w := PAD * 2 + COLS * PITCH
	var h := PAD * 2 + S + 4 + M
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_img.fill(PAL.SHEET.BG)
	for i in COLS:
		var colx := PAD + i * PITCH
		if i > 0:
			_vl(colx - 1, PAD, h - PAD - 1, "PARCHMENT", _O)
		var ix := colx + (PITCH - S) / 2
		_frame(ix - 1, PAD - 1, ix + S, PAD + S, "STONE", _O)
		_ox = ix
		_oy = PAD
		_ic16(i)
		_ox = 0
		_oy = 0
		var mx := colx + (PITCH - M) / 2
		_hl(colx, colx + PITCH - 1, PAD + S + 2, "STONE", _O)
		_ox = mx
		_oy = PAD + S + 4
		_ms(i)
		_ox = 0
		_oy = 0
		_hl(mx - 1, mx + M, PAD + S + 4 + M, "STONE", _O)

func _icon_boxes() -> Array:
	var out: Array = []
	for i in COLS:
		var colx := PAD + i * PITCH
		out.append([colx + (PITCH - S) / 2, PAD, S, S])
	for i in COLS:
		var colx2 := PAD + i * PITCH
		out.append([colx2 + (PITCH - M) / 2, PAD + S + 4, M, M])
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

var _lk: Dictionary = {}
func _light_keys() -> Dictionary:
	if _lk.is_empty():
		for rn in PAL.RAMPS:
			_lk[PAL.key((PAL.RAMPS[rn] as Array)[0])] = true
	return _lk

## Ключ цвета ТАК, как его сохранит 8-битный RGBA8 Image (float->uint8 округление
## в ui.BG/ui.INK не совпадает с сырым to_argb32).
func _store_key(c: Color) -> int:
	var im := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	im.set_pixel(0, 0, c)
	return im.get_pixel(0, 0).to_argb32()

func _is_tech(c: Color) -> bool:
	for k in PAL.SHEET:
		if PAL.key(c) == PAL.key(PAL.SHEET[k]):
			return true
	for rn in ["STONE", "PARCHMENT"]:
		if c.to_argb32() in (PAL.RAMPS[rn] as Array).map(func(t): return PAL.key(t)):
			return true
	return false

# ==================== самопроверки ====================

func _self_check() -> int:
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
		var name := "%s@%d" % [ITEMS[idx % COLS], 16 if idx < COLS else 48]
		var colors := {}
		var bottom_t := -1
		var top_t := 1 << 30
		var off := 0
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
					if _light_keys().has(k):
						light_top = true
				else:
					row.append(false)
					if c.a > 0.5 and not _is_tech(c):
						off += 1
			mask.append(row)
		if light_top:
			var ok_light := false
			var mid_y := top_t + (bottom_t - top_t + 1) / 2
			for y in range(top_t, mini(mid_y + 1, bh)):
				for x in bw:
					var k2 := PAL.key(_img.get_pixel(x0 + x, y0 + y))
					if palkeys.has(k2) and _light_keys().has(k2):
						ok_light = true
			light_top = ok_light
		masks.append(mask)
		if off > 0:
			print("SELF-CHECK FAIL %s: off-palette %d px" % [name, off])
			fails += 1
		if bottom_t < 0:
			print("SELF-CHECK FAIL %s: пустой спрайт" % name)
			fails += 1
			idx += 1
			continue
		var bad_bottom := 0
		for x in bw:
			var k3 := PAL.key(_img.get_pixel(x0 + x, y0 + bottom_t))
			if palkeys.has(k3) and not outline_tones.has(k3):
				bad_bottom += 1
		if bad_bottom > 0:
			print("SELF-CHECK FAIL %s: нижний ряд не OUTLINE (%d px)" % [name, bad_bottom])
			fails += 1
		if not light_top:
			print("SELF-CHECK FAIL %s: нет СЗ-подсветки" % name)
			fails += 1
		if colors.size() < 3:
			print("SELF-CHECK FAIL %s: цветов палитры %d < 3" % [name, colors.size()])
			fails += 1
		idx += 1
	# --- popcount различимости 16px-ряда: пиксели с разным цветом (больше — различимее)
	var keys: Array = []
	for i in COLS:
		var kx := PAD + i * PITCH + (PITCH - S) / 2
		var g: Array = []
		for y in S:
			var row2: Array = []
			for x in S:
				row2.append(_img.get_pixel(kx + x, PAD + y).to_argb32())
			g.append(row2)
		keys.append(g)
	var mn := 1 << 30
	var mxx := 0
	var sum := 0.0
	var worst := "?"
	var pairs: Array = []
	for i in COLS:
		for j in range(i + 1, COLS):
			var diff := 0
			for y in S:
				for x in S:
					if keys[i][y][x] != keys[j][y][x]:
						diff += 1
			if diff < mn:
				mn = diff
				worst = "%s+%s" % [ITEMS[i], ITEMS[j]]
			if diff > mxx:
				mxx = diff
			sum += diff
			pairs.append([diff, "%s+%s" % [ITEMS[i], ITEMS[j]]])
	pairs.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var tops := ""
	for t in pairs:
		tops += "%s=%d " % [t[1], t[0]]
	print("METRIC new pairs_diff: ", tops)
	print("METRIC new min_pair_diff=%d (worst %s) max=%d mean=%.1f (15 пар из 256)" %
			[mn, worst, mxx, sum / 15.0])
	if mn < MIN_DIFF:
		print("SELF-CHECK FAIL: min попарный diff %d < %d" % [mn, MIN_DIFF])
		fails += 1
	# --- насыщенность и цвета ---
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
			print("METRIC %s colors=%d sat=%.3f px=%d" % [ITEMS[i], _colors16(i), s2 / n2, n2])
			ssum += s2 / n2
	var mean_sat := ssum / COLS
	print("METRIC new mean_sat=%.3f" % mean_sat)
	if mean_sat < MIN_SAT:
		print("SELF-CHECK FAIL: средняя насыщенность %.3f < %.2f" % [mean_sat, MIN_SAT])
		fails += 1
	# --- baseline: рантайм-стабы ui_icons.item_icon() («до», числа в REPORT) ---
	var ui := load("res://scripts/ui_icons.gd")
	var stub_off := 0
	var stub_px := 0
	var stub_sat_sum := 0.0
	var bgk := PAL.key(ui.BG)
	var inkk := PAL.key(ui.INK)
	var skeys: Array = []
	for idv in ITEMS:
		var simg: Image = ui.item_icon(String(idv)).get_image()
		var ss3 := 0.0
		var sn := 0
		var g2: Array = []
		for y in S:
			var row3: Array = []
			for x in S:
				var c := simg.get_pixel(x, y)
				var k := PAL.key(c)
				row3.append(c.to_argb32())
				if k != bgk and k != inkk:
					stub_px += 1
					if not palkeys.has(k):
						stub_off += 1
					ss3 += c.s
					sn += 1
			g2.append(row3)
		skeys.append(g2)
		stub_sat_sum += (ss3 / sn) if sn > 0 else 0.0
	var s_min := 1 << 30
	var s_max := 0
	var s_sum := 0.0
	for i in COLS:
		for j in range(i + 1, COLS):
			var diff2 := 0
			for y in S:
				for x in S:
					if skeys[i][y][x] != skeys[j][y][x]:
						diff2 += 1
			if diff2 < s_min:
				s_min = diff2
			if diff2 > s_max:
				s_max = diff2
			s_sum += diff2
	print("METRIC stub off_palette=%d/%d_fg_px min_diff=%d max=%d mean=%.1f mean_sat=%.3f" %
			[stub_off, stub_px, s_min, s_max, s_sum / 15.0, stub_sat_sum / COLS])
	# 8) c25 equality-пин (прецедент c15): рантайм item_icon(id) == 16px-ряд листа
	#    попиксельно. Фоны слотов штатно разные (в игре технический BG/INK,
	#    на листе SHEET.BG) — если с обеих сторон фон, расхождением не считается.
	#    Ключи фонов берём ЭМПИРИЧЕСКИ через запись в RGBA8 (float->8bit округление
	#    ui.BG/INK не совпадает с сырым to_argb32: Color(0.16,..) хранится как 40).
	var bgk_rt := _store_key(ui.BG)
	var inkk_rt := _store_key(ui.INK)
	var sheetbg_k := _store_key(PAL.SHEET.BG)
	var eq_mism := 0
	for i in COLS:
		var rim: Image = ui.item_icon(String(ITEMS[i])).get_image()
		var ix := PAD + i * PITCH + (PITCH - S) / 2
		var m := 0
		for y in S:
			for x in S:
				var ca := rim.get_pixel(x, y)
				var cb := _img.get_pixel(ix + x, PAD + y)
				var ka := ca.to_argb32()
				var a_bg := ka == bgk_rt or ka == inkk_rt
				var b_bg := cb.to_argb32() == sheetbg_k
				if a_bg and b_bg:
					continue
				if ca.to_argb32() != cb.to_argb32():
					m += 1
		print("METRIC equality %s mismatches=%d" % [ITEMS[i], m])
		eq_mism += m
	print("METRIC equality_total mismatches=%d" % eq_mism)
	if eq_mism > 0:
		print("SELF-CHECK FAIL: рантайм ui_icons != утверждённый лист (%d px) — перенос не сделан" % eq_mism)
		fails += 1
	if mn < s_min:
		print("SELF-CHECK FAIL: min diff %d хуже стабов (%d)" % [mn, s_min])
		fails += 1
	if sum / 15.0 < s_sum / 15.0:
		print("SELF-CHECK FAIL: mean diff %.1f хуже стабов (%.1f)" % [sum / 15.0, s_sum / 15.0])
		fails += 1
	if mean_sat < stub_sat_sum / COLS:
		print("SELF-CHECK FAIL: mean sat %.3f хуже стабов (%.3f)" % [mean_sat, stub_sat_sum / COLS])
		fails += 1
	print("INFO equality-пин (рантайм == лист) ставится при интеграции (прецедент c15);")
	print("INFO сейчас рантайм — стабы t52 (baseline выше), лист — кандидат.")
	if fails > 0:
		print("SELF-CHECK: %d FAIL" % fails)
	else:
		print("SELF-CHECK PASS")
	return fails

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
		print("usage: sheet_items.gd -- <out.png>")
		quit(2)
		return
	_bake_sheet()
	var out := String(args[0])
	if not out.ends_with(".png"):
		out = out.path_join("sheet_items_v1.png")
	var err := _img.save_png(out)
	if err != OK:
		print("SAVE FAIL ", err, " -> ", out)
		quit(3)
		return
	var fails := _self_check()
	print("saved ", out, " ", _img.get_width(), "x", _img.get_height())
	quit(0 if fails == 0 else 1)
