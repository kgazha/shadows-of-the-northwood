class_name Talents
extends RefCounted
## Реестр «Древа талантов» (CONTRACT_TALENTS §1): плоские аддитивные эффекты,
## никаких proc-механик. Данные здесь — канон чисел; ранги живёт в
## GameState.flags под ключом "tal." + id (сейв v2, cap-128 учтён в game_state.gd).
## Узор — чисто статический справочник по образцу gear_data.gd: ни полей, ни
## обращений к GameState — реестр не знает ничего о состоянии.
## cost_per_rank всегда 1: узел стоит ровно одно очко таланта за ранг.

## id -> данные: name, desc, branch ("power"/"forest"/"ash"), max (рангов),
## cost_per_rank. Порядок объявления = порядок отображения в журнале.
## 12 общих узлов на 20 очков (сумма max: Сила 7 + Лес 7 + Пепел 6) + с g19
## два классовых прока (по max 3; в 20 очков не входят — см. ниже).
## g19 (вердикт пользователя 16.11 22:44 «Проки перенеси в таланты … проки у
## каждого класса свои»): контракт «плоские аддитивные» РАСШИРЕН двумя
## поллями — "class" (узел виден в журнале только этому классу; узлы без
## поля — общие, как всегда) и "vals" (число ранга 1/2/3 для proc-узлов,
## читает value_at_rank). Оба поля опциональны и ничего не меняют для
## прежних узлов. Ранги proc-узлов живут в тех же tal.* и, как всё
## семейство, сгорают на смерти/новом круге — «с нуля» (проки больше НЕ
## вечный слой meta.mb.*, доска пепла их не продаёт).
## Ранг прока при этом стоит очков как обычный узел, КРОМЕ подаренных
## миграцией рангов: те компенсированы gift-очками (game_state.tal_points).
const NODES := {
	# --- ветка «Сила» ---
	"whetstone": {
		"name": "Точильный камень", "branch": "power", "max": 2, "cost_per_rank": 1,
		"desc": "Остриё надёжнее: +0.15 к множителю оружия за ранг.",
	},
	"fury": {
		"name": "Яростная сила", "branch": "power", "max": 3, "cost_per_rank": 1,
		"desc": "Ярость бьёт больнее: +5% к итоговому урону за ранг.",
	},
	"heavy": {
		"name": "Тяжёлый удар", "branch": "power", "max": 1, "cost_per_rank": 1,
		"desc": "Каждый удар догружен: +1 к финальному урону.",
	},
	"zeal": {
		"name": "Берсеркова удаль", "branch": "power", "max": 1, "cost_per_rank": 1,
		"desc": "Замах чаще: задержка между атаками x0.92.",
	},
	# --- ветка «Лес» ---
	"skin": {
		"name": "Толстая кожа", "branch": "forest", "max": 2, "cost_per_rank": 1,
		"desc": "Лес натренировал шкуру: броня +1 за ранг.",
	},
	"breath": {
		"name": "Глубокое дыхание", "branch": "forest", "max": 2, "cost_per_rank": 1,
		"desc": "Ровный дух: реген HP чаще, интервал 4.0 → 3.2 → 2.6 с.",
	},
	"stride": {
		"name": "Скороход", "branch": "forest", "max": 2, "cost_per_rank": 1,
		"desc": "Ноги ходят быстрее: скорость +5% за ранг.",
	},
	"herblore": {
		"name": "Травничество", "branch": "forest", "max": 1, "cost_per_rank": 1,
		"desc": "Глаз на траву: дроп материалов с мобов 25% → 32%.",
	},
	# --- ветка «Пепел» ---
	"ember": {
		"name": "Уголёк в монете", "branch": "ash", "max": 2, "cost_per_rank": 1,
		"desc": "Монета звенит жирнее: золото с мобов +15% за ранг.",
	},
	"whisper": {
		"name": "Шёпот алтаря", "branch": "ash", "max": 1, "cost_per_rank": 1,
		"desc": "Алтарь слышит: +1 пепла за убитого босса круга.",
	},
	"scholar": {
		"name": "Рачительный опыт", "branch": "ash", "max": 2, "cost_per_rank": 1,
		"desc": "Ни крупицы впустую: опыт +10% за ранг.",
	},
	"lightfoot": {
		"name": "Лёгкая поступь", "branch": "ash", "max": 1, "cost_per_rank": 1,
		"desc": "Кувырок проворнее: откат кувырка -0.1 с.",
	},
	# --- g19: классовые проки (вердикт 16.11 22:44). Переехали с доски пепла
	# (MetaBoard TALENTS proc:true, цены 2/3/5 — отозваны) в общее древо:
	# покупаются очками таланта, живут в tal.*, сгорают на смерти/кругу вместе
	# со всеми. "class" — узел виден только своему классу (journal); остальные
	# игроки его не видят и не покупают (журнал фильтрует, try_spend guard).
	"boar_fang": {
		"name": "Клык вепря", "branch": "power", "max": 3, "cost_per_rank": 1,
		"class": "warrior", "vals": [20, 30, 40],
		"desc": "Вепрь не отпускает: шанс 20/30/40% сбросить откат «Мощного удара».",
	},
	"twisted_arrow": {
		"name": "Скрученная стрела", "branch": "forest", "max": 3, "cost_per_rank": 1,
		"class": "archer", "vals": [20, 30, 40],
		"desc": "Стрела возвращается в колчан: шанс 20/30/40% сбросить откат «Пробивающего выстрела».",
	},
}

## Ветки для UI (journal.gd): ключ -> заголовок колонки.
const BRANCHES := {"power": "Сила", "forest": "Лес", "ash": "Пепел"}

## Максимальный ранг узла; неизвестный id => 0 (такой узел не потратить).
static func max_of(id: String) -> int:
	if not NODES.has(id):
		return 0
	return int(NODES[id].get("max", 0))

## Число ранга proc-узла (g19): vals[rank-1]; ранг 0 / вне таблицы / узел без
## vals => 0. Единственный источник шансов проков после переноса с доски.
static func value_at_rank(rank: int, id: String) -> int:
	if rank < 1 or rank > max_of(id):
		return 0
	var v: Variant = NODES[id].get("vals")
	if typeof(v) != TYPE_ARRAY or rank > (v as Array).size():
		return 0
	return int((v as Array)[rank - 1])

## g19: класс-ограничение узла ("" = общий). Журнал фильтрует видимость,
## GameState.try_spend_talent держит тот же guard (нельзя вложить очко в
## чужой прок, даже узнав id).
static func class_of(id: String) -> String:
	if not NODES.has(id):
		return ""
	return String(NODES[id].get("class", ""))

# --- процедурные иконки вкладки «Таланты» (фидбек: «у талантов нет иконок») ---
## Пиксель-арт БЕЗ бинарных ассетов: каждый узел — маска 8 строк по 8 символов,
## символ -> цвет из палитры игры (цвета полос/текста hud.gd: золото заголовков,
#  HP-красный, опыт-зелёный, отдых-уголёк). Маска 8 px -> INTERPOLATE_NEAREST
## resize в 16 px при создании текстурки (+nearest из project.godot при отрисовке),
## тот же принцип, что у код-заглушек UiIcons в хотбаре hud.gd (t52).

## Источник — 8 px; на экране x2 (см. ICON_DRAW).
const ICON := 8
## Масштаб отрисовки: 8 px маска -> 16 px в строке журнала.
const ICON_DRAW := 2.0

## Символ маски -> цвет; "." — прозрачный.
const _PAL := {
	"x": Color(0.09, 0.08, 0.11),  # контур (тёмное дерево HUD)
	"s": Color(0.72, 0.76, 0.85),  # сталь
	"d": Color(0.40, 0.44, 0.54),  # тёмная сталь/чугун
	"g": Color(1.00, 0.84, 0.40),  # золото (заголовки журнала)
	"b": Color(0.55, 0.38, 0.24),  # шкура/дерево
	"r": Color(0.78, 0.20, 0.20),  # кровь (hp-полоса)
	"e": Color(0.95, 0.62, 0.25),  # уголёк (полоса отдыха)
	"h": Color(1.00, 0.93, 0.55),  # жар/искры
	"n": Color(0.35, 0.85, 0.40),  # листва (xp-полоса)
	"w": Color(0.78, 0.86, 1.00),  # дыхание/лунный свет
}

## id узла -> маска 8x8 (8 строк ровно по 8 символов). Силуэты:
## точильный камень с искрами, скрещённые клинки, гиря, пламя-пыл, шкура с
## зацепками, потоки дыхания, два следа, пучок травы, уголь с жаром,
## пузырёк шёпота, раскрытая книга, полумесяц над дорожкой; g19 — парные
## вепривы клыки и скрученная стрела.
const _PIXELS := {
	"whetstone": [
		"........",
		"....h.h.",
		"......h.",
		".xxxxxx.",
		"xssssssx",
		"xsddddsx",
		"xsddddsx",
		".xxxxxx.",
	],
	"fury": [
		"s.....s.",
		"xs...sx.",
		".xs.xs..",
		"..xssx..",
		"..xssx..",
		".xs.xs..",
		"xs...sx.",
		"g.....g.",
	],
	"heavy": [
		"..xxxx..",
		".xx..xx.",
		".x....x.",
		"xxdssdxx",
		"xdsdddsx",
		"xddddddx",
		".xddddx.",
		"..xxxx..",
	],
	"zeal": [
		"....e...",
		"...ee...",
		"..eee...",
		".eeeee..",
		".errre..",
		"errhhre.",
		".errre..",
		"........",
	],
	"skin": [
		".xxxxxx.",
		"xbrbrbrx",
		"xbbrbrbx",
		"xbrbrbrx",
		"xbbrbrbx",
		"xbrbrbrx",
		"xbbrbrbx",
		".xxxxxx.",
	],
	"breath": [
		"........",
		".wwwwwx.",
		"......wx",
		"..wwwwx.",
		"......wx",
		".wwwwwx.",
		"......wx",
		"........",
	],
	"stride": [
		".xxx....",
		"xsxsx...",
		"xsxsx...",
		".xxx....",
		"....xxx.",
		"....xsx.",
		"....xsx.",
		"....xxx.",
	],
	"herblore": [
		"........",
		"....n...",
		"..n.n.n.",
		"..n.n.n.",
		"..n.n.n.",
		".nnnnnn.",
		"..bbbb..",
		"........",
	],
	"ember": [
		"........",
		"......h.",
		"..xxxx..",
		".xddedx.",
		".xehhex.",
		".xddedx.",
		"..xxxx..",
		"........",
	],
	"whisper": [
		".xxxxx..",
		"xwwwwwx.",
		"xwxwxwx.",
		"xwwwwwx.",
		".xxxxx..",
		"..xx....",
		".xx.....",
		"........",
	],
	"scholar": [
		".xxxxxx.",
		"xggxxggx",
		"xggxxggx",
		"xggxxggx",
		"xggxxggx",
		"xxxxxxxx",
		".xxxxxx.",
		"........",
	],
	"lightfoot": [
		"..www...",
		".ww.....",
		"ww......",
		"ww......",
		".ww.....",
		"..www...",
		".g..g..g",
		"........",
	],
	# g19: парные вепривы клыки (сталь с контуром) и скрученная стрела
	# (остриё, витой древко s/d чередованием, оперение)
	"boar_fang": [
		"........",
		".xx..xx.",
		".xs..sx.",
		".xs..sx.",
		".xs..sx.",
		"..s..s..",
		"..x..x..",
		"........",
	],
	"twisted_arrow": [
		"...xx...",
		"..xssx..",
		"...ds...",
		"...sd...",
		"...ds...",
		"...sd...",
		"..xxsxx.",
		"..x...x.",
	],
}

static var _icon_cache := {}

## Сырое изображение иконки 8x8 RGBA8; неизвестный id -> null.
static func icon_image(id: String) -> Image:
	if not _PIXELS.has(id):
		return null
	var img := Image.create(ICON, ICON, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rows: Array = _PIXELS[id]
	for y in ICON:
		var row := String(rows[y])
		for x in ICON:
			var col: Variant = _PAL.get(row[x])
			if col != null:
				img.set_pixel(x, y, col)
	return img

## Текстурка иконки для UI (t52 снос, закон 13.11: ген-атлас 192x16 снят —
## иконка всегда процедурная): маска 8 px растягивается INTERPOLATE_NEAREST в
## 16 px (пиксель-арт остаётся квадратным; nearest из настроек проекта
## дополняет это при отрисовке). Кэш по id, неизвестный id -> null (журнал
## нарисует строку без иконки).
static func icon_texture(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var img := icon_image(id)
	if img == null:
		return null
	var side := int(ICON * ICON_DRAW)
	img.resize(side, side, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[id] = tex
	return tex
