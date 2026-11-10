class_name AchvCatalog
## Каталог достижений: КОНСТАНТНАЯ таблица 12 ачивок по канону
## docs/RETENTION_NG_PLUS.md §2. Данные (названия/описания/награды) — только отсюда;
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
]
