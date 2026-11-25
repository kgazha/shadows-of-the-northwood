extends RefCounted
## t17 «Глубина v2 §1: Аффиксы» (25.11, docs/DESIGN_DEPTH_V2.md §1).
## ЧИСТЫЙ модуль данных и канона: ни GameState, ни сцен, ни randf() —
## как procregion.gd (железо D3). Поэтому компилируется и в headless -s:
## детерминизм-таблицы (tools_art/affix_cases_dump.gd -> стойка qa_gear G10)
## воспроизводятся без запуска игры. Потребители (gear_data/loot) зовут
## через const-preload — без class_name-регистрации (паттерн OW).
##
## Реестр: пул 8 аффиксов — только существующие множители в существующие
## пути статов (урон/броня/крит/скорость/золото/лечение/откат/мана),
## без новых полей боя. Ценность предмета-инстанса: 0 аффиксов — обычная
## (белый, поведение 1:1), 1 — добротная (синий "rare"), 2 — реликтовая
## (фиолетовый "epic"). Двухступенчатые значения берут ступень по качеству
## носителя. Двойные кантики QUALITY_* = палитры family уже существующие.

const OW := preload("res://scripts/open_world.gd")  # shash — FNV-1a32 канон мира

const AFFIX_ORDER := ["keen", "hardened", "lethal", "swift", "gilded",
		"mending", "quickhand", "deepwell"]
## name — что видно в подсказке; text — честная строка по ступеням
## [добротная, реликтовая]. Числа читает AFFIX_VALUES (одна таблица).
const AFFIXES := {
	"keen": {"name": "Острый край", "text": ["урон +10%", "урон +15%"]},
	"hardened": {"name": "Латаная кромка", "text": ["броня +1", "броня +2"]},
	"lethal": {"name": "Верная щель", "text": ["крит +2%", "крит +2%"]},
	"swift": {"name": "Быстрая поступь", "text": ["скорость +5%", "скорость +5%"]},
	"gilded": {"name": "Золотая жилка", "text": ["золото +10%", "золото +10%"]},
	"mending": {"name": "Тёплая нить", "text": ["лечение +10%", "лечение +10%"]},
	"quickhand": {"name": "Быстрая рука", "text": ["откат умений −10%", "откат умений −10%"]},
	"deepwell": {"name": "Глубокий колодец", "text": ["мана +15%", "мана +15%"]},
}
## Числовые значения по id и ступени (0 = добротная, 1 = реликтовая) и куда
## ложатся (комментарий-карта; точки применения перечислены в PINS_T17):
## keen — player_damage | hardened — armor_bonus | lethal — player.dmg_vs
## swift — player velocity | gilded — loot gold | mending — GameState.heal
## quickhand — player skill_cd | deepwell — recalc_max_mana
const AFFIX_VALUES := {
	"keen": [0.10, 0.15],
	"hardened": [1.0, 2.0],
	"lethal": [0.02, 0.02],
	"swift": [0.05, 0.05],
	"gilded": [0.10, 0.10],
	"mending": [0.10, 0.10],
	"quickhand": [0.10, 0.10],
	"deepwell": [0.15, 0.15],
}
const QUALITY_NAMES := {1: "добротная", 2: "реликтовая"}
const QUALITY_RARITY := {1: "rare", 2: "epic"}

## Вердиктные шансы редкости (DESIGN_DEPTH_V2 §1): реликтовая 5%, добротная
## 15% (порог 20). Корзина — младшие две децимали shash-канона мира.
const CHANCE_RELIC := 5    # bucket < 5  -> реликтовая (2 аффикса)
const CHANCE_FINE := 20    # bucket < 20 -> добротная (1 аффикс)

## Детерминированный ролл аффиксов дропа: shash(run_seed, cell, drop_ordinal).
## cell — строка клетки ("x,y" мира/локации или "chest:<id>" сундука),
## drop_ordinal — номер выдачи снаряжения в забеге (размер сумки ПОСЛЕ
## покупки — стабилен под повторными входами в тот же сейв). force_relic —
## гарантия реликтовой роли (сундук микро-подземелья t19/t20 и финал
## квестовой цепочки пояса t18 заходят этим же параметром). Чистая функция:
## тот же вход — тот же массив бит-в-бит; randf() не зовётся никогда.
static func affix_roll(run_seed: int, cell: String, drop_ordinal: int,
		force_relic: bool = false) -> Array:
	var h := OW.shash("affix:%d:%s:%d" % [run_seed, cell, drop_ordinal])
	var want := 0
	if force_relic:
		want = 2
	else:
		var bucket := h % 100
		if bucket < CHANCE_RELIC:
			want = 2
		elif bucket < CHANCE_FINE:
			want = 1
	var out: Array = []
	var i := 0
	while out.size() < want and i < 64:  # 64 — потолок шашки, сходится сразу
		var k := OW.shash("affixpick:%d:%s:%d:%d" % [run_seed, cell, drop_ordinal, i]) % AFFIX_ORDER.size()
		var aid := String(AFFIX_ORDER[k])
		if not out.has(aid):
			out.append(aid)
		i += 1
	return out

## Ключ клетки из мировой точки (TILE 16, канон world.gd).
static func cell_key(pos: Vector2) -> String:
	return "%d,%d" % [int(floor(pos.x / 16.0)), int(floor(pos.y / 16.0))]
