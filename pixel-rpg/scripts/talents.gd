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
## 14 узлов на 20 очков (сумма max): Сила 7 + Лес 7 + Пепел 6.
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
}

## Ветки для UI (journal.gd): ключ -> заголовок колонки.
const BRANCHES := {"power": "Сила", "forest": "Лес", "ash": "Пепел"}

## Максимальный ранг узла; неизвестный id => 0 (такой узел не потратить).
static func max_of(id: String) -> int:
	if not NODES.has(id):
		return 0
	return int(NODES[id].get("max", 0))
