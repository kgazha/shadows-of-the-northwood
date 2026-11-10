class_name AchvCatalog
## Каталог достижений: КОНСТАНТНАЯ таблица 17 ачивок по канону
## docs/RETENTION_NG_PLUS.md §2 (базовые) + §D (цикл NG+ — последние 5 строк).
## Данные (названия/описания/награды) — только отсюда;
## логика анлока и наград живёт в achv.gd, отображение — в journal.gd (вкладка
## «Достижения»). Здесь нет ни кода, ни чтения GameState — чистые данные.
##
## Поля строки таблицы:
##   id       — без префикса: флаг анлока GameState.flags["ach.<id>"]
##              (в JSON-сейве значение может лежать float — сверять > 0);
##   name/desc — отображаемые название и условие;
##   reward   — награда по канону §2 (текст для витрины);
##   counter  — опц. источник прогресс-счётчика-подсказки (разбирает journal.gd):
##              "n.<kind>"  — суммарный счётчик GameState.flags["ach.n.<kind>"]
##                            (brews/buys/herbs и будущие kill_*),
##              "field:<p>" — int-поле GameState (slime_kills, gold),
##              "size:<p>"  — размер поля-контейнера GameState (campfires_used,
##                            chests_used);
##   goal     — цель счётчика для отображения «cur/goal»;
##   hint     — подпись счётчика в UI.
const ITEMS: Array = [
	{
		"id": "first_blood",
		"name": "Первая кровь",
		"desc": "Впервые убить моба.",
		"reward": "+10g",
	},
	{
		"id": "hunter_25",
		"name": "Юный охотник",
		"desc": "Убить 25 слизней.",
		"reward": "+30g",
		"counter": "field:slime_kills",
		"goal": 25,
		"hint": "Слизней убито",
	},
	{
		"id": "hunter_100",
		"name": "Ветеран охоты",
		"desc": "Убить 100 слизней.",
		"reward": "+2 Пепла",
		"counter": "field:slime_kills",
		"goal": 100,
		"hint": "Слизней убито",
	},
	{
		"id": "boss_slayer",
		"name": "Победитель босса",
		"desc": "Победить босса Северного Леса.",
		"reward": "+3 Пепла",
	},
	{
		"id": "alchemist",
		"name": "Алхимик",
		"desc": "Сварить первое зелье (любой рецепт).",
		"reward": "+20g",
	},
	{
		"id": "brewer_10",
		"name": "Мастер-варщик",
		"desc": "Сварить 10 зелий суммарно.",
		"reward": "+1 Пепел",
		"counter": "n.brews",
		"goal": 10,
		"hint": "Сварено",
	},
	{
		"id": "campfires",
		"name": "Тот, у огня",
		"desc": "Отдохнуть у 3 костров.",
		"reward": "+1 Пепел",
		"counter": "size:campfires_used",
		"goal": 3,
		"hint": "Костров",
	},
	{
		"id": "treasure",
		"name": "Кладоискатель",
		"desc": "Открыть оба сундука мира.",
		"reward": "+40g",
		"counter": "size:chests_used",
		"goal": 2,
		"hint": "Сундуков",
	},
	{
		"id": "collector",
		"name": "Покупатель",
		"desc": "Купить суммарно 5 предметов у Гриима.",
		"reward": "+2 Пепла",
		"counter": "n.buys",
		"goal": 5,
		"hint": "Покупок",
	},
	{
		"id": "wealth",
		"name": "Богач",
		"desc": "Держать 300 золота на руках.",
		"reward": "+1 Пепел",
		"counter": "field:gold",
		"goal": 300,
		"hint": "Золота",
	},
	{
		"id": "herbalist",
		"name": "Травник",
		"desc": "Выпить 5 трав (Q).",
		"reward": "+15g",
		"counter": "n.herbs",
		"goal": 5,
		"hint": "Трав выпито",
	},
	{
		"id": "hardcore",
		"name": "На волоске",
		"desc": "Убить босса, оставшись с 1 HP.",
		"reward": "+3 Пепла + титул",
	},
	# --- §D: цикл NG+ (петля возврата). Счётчики не используются: факты —
	# флаги ng.wave / ng.boss_<волна> / meta.ash, анлок идемпотентен (achv.gd).
	{
		"id": "ng_second",
		"name": "Второй заход",
		"desc": "Начать второй круг: войти в NG+ (волна 1).",
		"reward": "+1 Пепел",
	},
	{
		"id": "ng_vet",
		"name": "Ветеран Пепелища",
		"desc": "Дойти до волны 3 в кругах NG+.",
		"reward": "+2 Пепла",
	},
	{
		"id": "ng_finale",
		"name": "Финальный круг",
		"desc": "Дойти до предельной волны 5.",
		"reward": "+3 Пепла",
	},
	{
		"id": "ng_magnat",
		"name": "Аш-магнат",
		"desc": "Держать 20 Пепла на алтаре.",
		"reward": "+2 Пепла",
	},
	{
		"id": "ng_crowns",
		"name": "Все венцы",
		"desc": "Победить Грому на финальной волне 5.",
		"reward": "+3 Пепла",
	},
]
