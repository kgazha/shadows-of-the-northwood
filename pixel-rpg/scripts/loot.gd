class_name Loot
extends RefCounted
## Дроп со смерти мобов и награда сундуков: броски по таблицам GearData.LOOT,
## выдача золота/предметов в GameState, звук монет и тосты.
## Вызывается из хуков в slime.gd / brute.gd / interactable.gd — см. отчёт
## «ИНТЕГРАЦИОННЫЕ ЗАПРОСЫ»; файлы движка экономики не меняет.

## Смерть моба: kind — строка таблицы GearData.LOOT ("slime"/"brute"/"boss").
## world_pos + world (опц.) — точка для искр золота на месте трупа; без world
## эффект просто пропускается (headless-QA, бо́сс после queue_free и т. п.).
static func on_mob_death(kind: String, world_pos: Vector2, world: Node2D = null) -> void:
	Achv.on_mob_death(kind)  # ачивка «Первая кровь» (§2 #1, achv.gd)
	var table: Variant = GearData.LOOT.get(kind, [])
	if typeof(table) != TYPE_ARRAY or table.is_empty():
		push_warning("Loot: неизвестный вид моба: %s" % kind)
		return
	var gold := 0
	for e in table:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if randf() > float(e.get("chance", 0.0)):
			continue
		if e.has("gold"):
			gold += _roll_gold(e["gold"])
		elif e.has("item"):
			_give_item(GameState, String(e.get("item", "")), maxi(1, int(e.get("qty", 1))))
	# NG+ §1.3: золото × ng_gold_mult(волна) — на ИТОГ ролла, формула в game_state.gd
	# (одна точка истины). ПОРЯДОК: до greedy-строки алтаря ниже (§4.2: жадность —
	# поверх волны). На w0 тождество (×1.0).
	gold = int(round(gold * GameState.ng_gold_mult(GameState.ng_wave())))
	# Талант «Уголёк в монете» (ember, CONTRACT_TALENTS §3): +15% золота мобов за
	# ранг — стоит рядом с множителем волны, до жадности и до записи в GameState.
	gold = int(round(gold * (1.0 + 0.15 * GameState.tal_rank("ember"))))
	if gold <= 0:
		return
	# «Жадность» алтаря Пепла: +25% золота (поверх будущих ng_gold_mult — они встанут ниже).
	gold = int(round(gold * (1.0 + 0.25 * int(GameState.flags.get("meta.greed", 0)))))
	GameState.add_gold(gold)
	GameAudio.sfx("coin")
	GameState.toast.emit("+%d зол." % gold)
	if world != null:
		Fx.hit(world_pos, world)  # тёплые искры монет на месте дропа

## Награда сундука (хук interactable.gd при открытии): горсть золота,
## в половине случаев — зелье (заряд крепкого или трава, если заряды полны).
## Возвращает выданное золото (для тестов/журналов).
static func chest_reward(gs: Node) -> int:
	var gold := randi_range(8, 18)
	gs.add_gold(gold)
	GameAudio.sfx("coin")
	gs.toast.emit("В сундуке: +%d зол." % gold)
	if randf() < 0.5:
		if gs.brewed_potions < GameState.BREWED_CAP:
			gs.brewed_potions += 1
			gs.toast.emit("В углу сундука — крепкое зелье (заряд %d/%d)!" % [gs.brewed_potions, GameState.BREWED_CAP])
		else:
			gs.herbs += 1
			gs.toast.emit("Зелья нет — в углу сундука пучок трав.")
	return gold

## Монеты из строки таблицы: [min, max] — равномерный бросок, int — сумма.
static func _roll_gold(v: Variant) -> int:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return randi_range(int(v[0]), int(v[1]))
	return maxi(0, int(v))

## Выдача special-предмета: "herb" — трава (Q-зелье), "potion" — заряд
## крепкого зелья (до BREWED_CAP, излишек — травами). Свободного инвентаря
## в игре нет; всё остальное — молчаливая потеря с предупреждением.
static func _give_item(gs: Node, id: String, qty: int) -> void:
	match id:
		"herb":
			gs.herbs += qty
			gs.toast.emit("Трофей: трава (всего: %d)." % gs.herbs)
		"potion":
			if gs.brewed_potions < GameState.BREWED_CAP:
				gs.brewed_potions = mini(GameState.BREWED_CAP, gs.brewed_potions + qty)
				GameAudio.sfx("potion")
				gs.toast.emit("Трофей: крепкое зелье (заряд %d/%d)." % [gs.brewed_potions, GameState.BREWED_CAP])
			else:
				gs.herbs += 1
				gs.toast.emit("Зелья не влезают — трофей: трава.")
		_:
			push_warning("Loot: предмет не помещается в рюкзак: %s" % id)
