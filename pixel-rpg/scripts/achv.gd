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

## «Пепел» (мета-валюта §4) выдаётся скриптом res://scripts/ash.gd. class_name в
## рантаймовом ClassDB 4.7.2 отсутствует (паттерн settings_menu.gd) — резолвим
## через ResourceLoader.exists + load.
const ASH_PATH := "res://scripts/ash.gd"

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
	GameState.ng_plus_started.connect(_on_ng_plus)  # §D ачивки NG+ цикла
	_daily()  # разово при старте
	_check_ng()  # старый сейв с ng.wave>0 — перепроверка на месте

# --- общий механизм наград (§2: награда ровно при первом анлоке) ---

static func _f(key: String, def: Variant) -> Variant:
	return GameState.flags.get(key, def)  # только .get(): старые сейвы не ломаем

## Анлок по id из таблицы §2: повторно — false без награды (идемпотентность).
## Золотая часть — add_gold, пепельная — grant_ash (только при первом анлоке).
static func unlock(id: String, gold: int, ash: int) -> bool:
	var key := "ach." + id
	if bool(_f(key, false)):
		return false
	GameState.set_flag(key, true)
	if gold > 0:
		GameState.add_gold(gold)  # gold_changed → автосейв: флаги уедут в сейв
	var ash_ok := grant_ash(ash)
	GameAudio.sfx("ui_levelup")
	var reward := ""
	if gold > 0:
		reward = "+%d зол." % gold
	if ash_ok:
		reward += (", " if reward != "" else "") + "+%d пепла" % ash
	var msg := "Достижение: " + _title(id)
	if reward != "":
		msg += " (%s)" % reward
	GameState.toast.emit(msg)
	return true

## Выдача «Пепла» (§4.1): класс по class_name в ClassDB 4.7.2 не резолвится —
## ResourceLoader.exists + load (паттерн settings_menu.gd) и статический вызов
## Ash.add(n). После КАЖДОЙ успешной выдачи — GameState.save_game(): для Пепла
## нет автосейва через gold_changed. false — начисления не было.
static func grant_ash(n: int) -> bool:
	n = int(n)
	if n <= 0:
		return false
	if not ResourceLoader.exists(ASH_PATH):
		return false
	var sc := load(ASH_PATH) as GDScript
	if sc == null:
		return false
	sc.call("add", n)
	_check_ng()  # §D: свежий Пепел — перепроверка фактов цикла (идемпотентно)
	GameState.save_game()
	return true

static func _title(id: String) -> String:
	# Единый источник имён — achv_catalog.ITEMS (нарратив-аудит: тост и журнал
	# больше не могут разойтись — 8 рассогласований устранено удалением копии).
	return AchvCatalog.name_of(id)

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
	if GameState.slime_kills >= 40:
		unlock("hunter_100", 0, 2)

## #4/#12 boss_slayer / hardcore — brute.gd, ветка босса после boss_defeated.
## HP героя берём из GameState.hp (канон; Player.I в коде движка нет).
static func on_boss_death() -> void:
	unlock("boss_slayer", 0, 3)
	if GameState.hp <= 1 and unlock("hardcore", 0, 3):
		GameState.set_flag("ach_brand", true)  # титул (§2 #12)

## #18 witch_slayer — mob_boss2.gd, ветка смерти Ведьмы (сразу после флага
## ashen.boss). Однократна на сейв (идемпотентность unlock по ach.-флагу):
## пер-круговую мотивацию держит квест «Ведьма Пепелища» (quests_data.gd).
static func on_witch_death() -> void:
	unlock("witch_slayer", 0, 1)

## #5/#6 alchemist / brewer_10 — alchemy.gd::brew() на успехе.
static func on_brew() -> void:
	unlock("alchemist", 20, 0)
	if count("brews") >= 10:
		unlock("brewer_10", 0, 1)

## #7 campfires — campfire.gd::_finish() после пометки костра использованным.
## Счёт ВЕЧНЫЙ через суммарный канал "ach.n.campfires" (как brews/buys):
## костёр в мире один, campfires_used обнуляется start_ng_plus() каждый круг —
## на size:campfires_used ачивка была бы недостижима. Гейт и витрина (counter
## "n.campfires" в achv_catalog.gd) читают один и тот же флаг.
static func on_campfire_used() -> void:
	if count("campfires") >= 3:
		unlock("campfires", 0, 1)

## #8 treasure — interactable.gd, ветка chest после Loot.chest_reward;
## тот же хук зовут CaveChest (dungeon_zone.gd) и AshenChest (ashen_zone.gd).
static func on_chest_opened() -> void:
	if GameState.chests_used.size() >= 3:
		unlock("treasure", 40, 0)

## #9 collector — shop.gd::_on_buy() на успехе.
static func on_buy() -> void:
	if count("buys") >= 5:
		unlock("collector", 0, 2)

## #11 herbalist — world.gd::drink_potion() после траты травы (Q).
static func on_herb_drunk() -> void:
	if count("herbs") >= 5:
		unlock("herbalist", 15, 0)

## #19/#20 rekindled / undying — смерть-петля (CONTRACT_RUNLOOP §1.5 +
## ADDENDUM 1.0 п.1–2): зовёт GameState.start_new_run() ДО вайпа. Счётчик —
## вечный канал "ach.n.deaths" (переживает вайп и круги, §0). Награды — штатным
## механизмом каталога (золото 0, Пепел 3/5 — как у соседних записей), НЕ
## отдельная выдача. unlock идемпотентен по ach.-флагам: на 6-й/16-й смерти
## награда не повторяется (R4).
static func on_death() -> void:
	var d := count("deaths")
	if d >= 5:
		unlock("rekindled", 0, 3)
	if d >= 15:
		unlock("undying", 0, 5)

func _check_wealth() -> void:
	# #10 wealth: gold >= 300 на руках.
	if GameState.gold >= 300:
		unlock("wealth", 0, 1)

## §D цикл NG+ (#13–#17): факты — только флаги, бой не трогаем. Волны — ng.wave,
## венец финала — ng.boss_5 (brute.gd пишет флаг ДО своей награды — факт фиксится
## независимо от респавнов), баланс — meta.ash. Счётчиков нет; анлок идемпотентен
## (флаг ставится до наград), поэтому зовём на каждом удобном перепроверочном
## событии: вход в круг, старт узла, каждая выдача Пепла.
static func _check_ng() -> void:
	var w := clampi(int(_f("ng.wave", 0)), 0, GameState.NG_WAVE_CAP)
	if w >= 1:
		unlock("ng_second", 0, 1)
	if w >= 3:
		unlock("ng_vet", 0, 2)
	if w >= 5:
		unlock("ng_finale", 0, 3)
	if int(_f("meta.ash", 0)) >= 20:
		unlock("ng_magnat", 0, 2)
	if int(_f("ng.boss_5", 0)) >= 1:
		unlock("ng_crowns", 0, 3)

## Хук сигнала GameState.ng_plus_started (world.gd коннектит Achv раньше своего
## перезагружающего лямбда-хука — ачивки снимаются до перезагрузки сцены).
func _on_ng_plus() -> void:
	_check_ng()

# --- ежедневная награда (§3): разово при старте, молча в тех же сутки/откате ---
# GameState.save_game() ниже и save_game() внутри grant_ash — единственные
# легальные прямые вызовы сейва из фичи: set_flag автосейв не триггерит, а
# stamp/Пепел обязаны пережить выход.

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
	if last <= 0.0:
		# LEGACY-МИГРАЦИЯ (§5.2, находка qa_rf s5): в сейве нет daily.stamp
		# (float==0) — это НЕ смена дня, а первый запуск после апдейта.
		# Заводим stamp/streak по штатному правилу и выходим БЕЗ награды:
		# иначе каждый старый сейв дарит день 1 (+15 зол), а семидневная
		# серия сдвигается раньше первого реального дня. Смена дня — путь
		# last > 0 ниже (он не тронут).
		GameState.save_game()
		return
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
			# ADDENDUM 1.0 п.3: +1 Пепла механизмом дня 7 (тост честно
			# подстраивается, если Пепел выдать нечем).
			text = "+1 крепкое зелье, +1 пепла" if grant_ash(1) else "+1 крепкое зелье"
		5:
			gold = 40
			text = "+40 зол."
		6:
			gold = 50
			GameState.add_xp(10)
			text = "+50 зол., +10 опыта"
		7:
			gold = 80
			text = "+80 зол., +2 пепла" if grant_ash(2) else "+80 зол."
		_:
			return
	if gold > 0:
		GameState.add_gold(gold)
	GameAudio.sfx("ui_levelup")
	GameState.toast.emit("Ежедневная награда: %s (серия %d/7)" % [text, day])
