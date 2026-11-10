class_name Achv
extends Node
## Достижения (§2) + ежедневная награда (§3) из docs/RETENTION_NG_PLUS.md.
## Синглтон по образцу Shop/GameAudio: static var I; экземпляр создаёт world.gd
## в _ready ПОСЛЕ GameState.load_game() — иначе daily увидел бы пустые flags.
## Хранение — строго GameState.flags: читаем ТОЛЬКО flags.get(key, def) (правило
## §5.2: старые сейвы не имеют наших ключей и обязаны грузиться без изменений).
## Ключи: "ach.<id>"=true — анлок (§2), "ach.n.<kind>"=int — суммарные счётчики,
## "daily.stamp"/"daily.streak" — §3.1, "ach_brand" — титул §2 #12.
## Статические хуки работают и без узла (оперируют только GameState) — узел нужен
## лишь для разовой daily-проверки и коннекта gold_changed (§2 #10).

static var I: Achv               # синглтон; назначает сам себя в _enter_tree

## «Пепел» (мета-валюта §4) ещё не реализован — награды в Пепле временно
## конвертируются золотом: 1 Пепел = ASH_GOLD золота. Временная мера до P1.
const ASH_GOLD := 15

## Подменный «сейчас» для headless-тестов (0 — реальные часы).
static var test_now := 0.0

static func _now() -> float:
	return test_now if test_now > 0.0 else Time.get_unix_time_from_system()

func _enter_tree() -> void:
	if I == null:
		I = self

func _exit_tree() -> void:
	if I == self:
		I = null

func _ready() -> void:
	# §2 #10 wealth: проверяем на существующем сигнале — 0 стоимости по кадрам.
	GameState.gold_changed.connect(_check_wealth)
	_daily()  # разово при старте

# --- общий механизм наград (§2: награда ровно при первом анлоке) ---

static func _f(key: String, def: Variant) -> Variant:
	return GameState.flags.get(key, def)  # только .get(): старые сейвы не ломаем

## Анлок по id из таблицы §2: повторно — false без награды (идемпотентность).
## Награду в Пепле временно выдаём золотом (см. ASH_GOLD).
static func unlock(id: String, gold: int, ash: int) -> bool:
	var key := "ach." + id
	if bool(_f(key, false)):
		return false
	GameState.set_flag(key, true)
	var total := gold + ASH_GOLD * ash
	if total > 0:
		GameState.add_gold(total)  # gold_changed → автосейв: флаги уедут в сейв
	GameAudio.sfx("ui_levelup")
	GameState.toast.emit("Достижение: %s (+%d зол.)" % [_title(id), total])
	return true

static func _title(id: String) -> String:
	match id:
		"first_blood":
			return "Первая кровь"
		"hunter_25":
			return "Охотник: 25 слаймов"
		"hunter_100":
			return "Охотник: 100 слаймов"
		"boss_slayer":
			return "Убийца босса"
		"alchemist":
			return "Алхимик"
		"brewer_10":
			return "Знахарь: 10 варок"
		"campfires":
			return "Трёх костров"
		"treasure":
			return "Клад"
		"collector":
			return "Покупатель: 5 вещей"
		"wealth":
			return "Богатство"
		"herbalist":
			return "Травник"
		"hardcore":
			return "Не на жизнь, а на смерть"
	return id

## Суммарный счётчик вида "ach.n.<kind>" (инкремент + set_flag); возвращает новое
## значение. Хранение — по правилу родителя для суммарных целей.
static func count(kind: String) -> int:
	var key := "ach.n." + kind
	var n := int(_f(key, 0)) + 1
	GameState.set_flag(key, n)
	return n

# --- хуки (§2; каждый вызывается одной строкой из указанного места) ---

## #1 first_blood — вход loot.gd::on_mob_death().
static func on_mob_death(_kind: String) -> void:
	unlock("first_blood", 10, 0)

## #2/#3 hunter_25 / hunter_100 — slime.gd после slime_kills += 1.
static func on_slime_kill() -> void:
	if GameState.slime_kills >= 25:
		unlock("hunter_25", 30, 0)
	if GameState.slime_kills >= 100:
		unlock("hunter_100", 0, 2)

## #4/#12 boss_slayer / hardcore — brute.gd, ветка босса после boss_defeated.
## HP героя берём из GameState.hp (канон; Player.I в коде движка нет).
static func on_boss_death() -> void:
	unlock("boss_slayer", 0, 3)
	if GameState.hp <= 1 and unlock("hardcore", 0, 3):
		GameState.set_flag("ach_brand", true)  # титул (§2 #12)

## #5/#6 alchemist / brewer_10 — alchemy.gd::brew() на успехе.
static func on_brew() -> void:
	unlock("alchemist", 20, 0)
	if count("brews") >= 10:
		unlock("brewer_10", 0, 1)

## #7 campfires — campfire.gd::_finish() после пометки костра использованным.
static func on_campfire_used() -> void:
	if GameState.campfires_used.size() >= 3:
		unlock("campfires", 0, 1)

## #8 treasure — interactable.gd, ветка chest после Loot.chest_reward.
static func on_chest_opened() -> void:
	if GameState.chests_used.size() >= 2:
		unlock("treasure", 40, 0)

## #9 collector — shop.gd::_on_buy() на успехе.
static func on_buy() -> void:
	if count("buys") >= 5:
		unlock("collector", 0, 2)

## #11 herbalist — world.gd::drink_potion() после траты травы (Q).
static func on_herb_drunk() -> void:
	if count("herbs") >= 5:
		unlock("herbalist", 15, 0)

func _check_wealth() -> void:
	# #10 wealth: gold >= 300 на руках.
	if GameState.gold >= 300:
		unlock("wealth", 0, 1)

# --- ежедневная награда (§3): разово при старте, молча в тех же сутки/откате ---
# GameState.save_game() ниже — единственный легальный прямой вызов сейва из
# фичи: set_flag автосейв не триггерит, а stamp обязан пережить выход.

func _daily() -> void:
	var now := _now()
	var last := float(_f("daily.stamp", 0.0))
	if now < last - 3600.0:
		return  # откат часов > 1 ч — молча не награждаем, stamp не трогаем (§3.2)
	var days := 1
	if last > 0.0:
		days = int(floor((now - last) / 86400.0))
	if days < 1:
		return  # тот же день — молча
	var prev := int(_f("daily.streak", 0))
	# пропуск дня обнуляет серию; после 7-го дня — сброс в 1 (§3.3 «день → сброс
	# после 7-го»; буква 3.2 mini(streak+1,7) вечно сидела бы на 7-й награде)
	var streak := 1
	if days == 1 and prev < 7:
		streak = prev + 1
	GameState.set_flag("daily.streak", streak)
	GameState.set_flag("daily.stamp", now)
	_grant_daily(streak)
	GameState.save_game()  # stamp обязан пережить выход; set_flag автосейва нет

func _grant_daily(day: int) -> void:
	var gold := 0
	var text := ""
	match day:
		1:
			gold = 15
			text = "+15 зол."
		2:
			gold = 20
			GameState.herbs += 1  # травы без лимита переноса — кладём в сумку
			text = "+20 зол., трава"
		3:
			gold = 25
			text = "+25 зол."
		4:
			if GameState.brewed_potions < GameState.BREWED_CAP:
				GameState.brewed_potions += 1
			text = "+1 крепкое зелье"
		5:
			gold = 40
			text = "+40 зол."
		6:
			gold = 50
			GameState.add_xp(10)
			text = "+50 зол., +10 опыта"
		7:
			gold = 80 + ASH_GOLD * 2  # «2 Пепла» временно золотом (§4)
			text = "+%d зол." % gold
		_:
			return
	if gold > 0:
		GameState.add_gold(gold)
	GameAudio.sfx("ui_levelup")
	GameState.toast.emit("Ежедневная награда: %s (серия %d/7)" % [text, day])
