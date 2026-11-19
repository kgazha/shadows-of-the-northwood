class_name Loot
extends RefCounted
## Дроп со смерти мобов и награда сундуков: броски по таблицам GearData.LOOT,
## выдача золота/предметов в GameState, звук монет и тосты.
## Вызывается из хуков в slime.gd / brute.gd / interactable.gd — см. отчёт
## «ИНТЕГРАЦИОННЫЕ ЗАПРОСЫ»; файлы движка экономики не меняет.

const OW := preload("res://scripts/open_world.gd")  # t3: GOLD_BELT_STEP — реестр поясов

## g20b TEST-ONLY: если >= 0, каждый бросок таблицы на смерть моба берётся
## отсюда вместо randf() — детерминированная проверка 5%-дропа снаряжения
## (qa_gear) без тысячи убийств. Игра никогда не выставляет: по умолчанию -1.
static var test_roll: float = -1.0

static func _roll() -> float:
	return test_roll if test_roll >= 0.0 else randf()

## Смерть моба: kind — строка таблицы GearData.LOOT ("slime"/"brute"/"boss").
## world_pos + world (опц.) — точка для искр золота на месте трупа; без world
## эффект просто пропускается (headless-QA, бо́сс после queue_free и т. п.).
static func on_mob_death(kind: String, world_pos: Vector2, world: Node2D = null) -> void:
	# t3 «Мир v1»: kind мобов локаций несёт ПОЯСНОЙ суффикс "@b<N>" (зоны по
	# удалению, OPEN_WORLD/BALANCE строка 24): таблица/ачивки/счётчики — базовые
	# (суффикс снимается), золото итоговое ×(1+GOLD_BELT_STEP·N). Kind без
	# суффикса — прежнее поведение байт-в-байт.
	var belt_b := 0
	if kind.contains("@"):
		var parts: PackedStringArray = kind.split("@")
		kind = String(parts[0])
		var tag := String(parts[1]) if parts.size() > 1 else ""
		if tag.begins_with("b") and tag.substr(1).is_valid_int():
			belt_b = clampi(int(tag.substr(1)), 0, 8)
	Achv.on_mob_death(kind)  # ачивка «Первая кровь» (§2 #1, achv.gd)
	# t20 P0-3: счётчик убийств по типам для экрана смерти (rs.k.<kind>).
	# ДО сверки с таблицей лута: моб умер — засчитываем даже без таблицы
	# (QA-симуляции qa_bt/qa_s4/qa_s6 зовут с синтетическими kind — безвредно,
	# rs.* стирается каждый забег в _wipe_circle).
	GameState.flags["rs.k." + kind] = GameState._num(GameState.flags.get("rs.k." + kind, 0), 0) + 1
	var table: Variant = GearData.LOOT.get(kind, [])
	if typeof(table) != TYPE_ARRAY or table.is_empty():
		push_warning("Loot: неизвестный вид моба: %s" % kind)
		return
	var gold := 0
	for e in table:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if _roll() > float(e.get("chance", 0.0)):
			continue
		if e.has("gold"):
			gold += _roll_gold(e["gold"])
		elif e.has("item"):
			_give_item(GameState, String(e.get("item", "")), maxi(1, int(e.get("qty", 1))))
		elif e.has("mat"):
			# g20a: материал в стопку инвентаря (шкура/жила — «всегдашний» дроп)
			_give_mat(GameState, String(e.get("mat", "")), maxi(1, int(e.get("qty", 1))))
		elif e.has("gear"):
			# g20b (вердикт §4): редкий дроп снаряжения (5%) — в сумку GameState
			_give_gear(GameState, String(e.get("gear", "")), world_pos, world)
	# NG+ §1.3: золото × ng_gold_mult(волна) — на ИТОГ ролла, формула в game_state.gd
	# (одна точка истины). ПОРЯДОК: до greedy-строки алтаря ниже (§4.2: жадность —
	# поверх волны). На w0 тождество (×1.0).
	gold = int(round(gold * GameState.ng_gold_mult(GameState.ng_wave())))
	# t3 «Мир v1»: пояс локации (суффикс "@bN") — золото ×(1+0,15·N), одна точка
	# истины OpenWorld.GOLD_BELT_STEP; до жадности/талантов (они поверх).
	if belt_b > 0:
		gold = int(round(gold * _ow_gold_belt_mult(belt_b)))
	# Талант «Уголёк в монете» (ember, CONTRACT_TALENTS §3): +15% золота мобов за
	# ранг — стоит рядом с множителем волны, до жадности и до записи в GameState.
	gold = int(round(gold * (1.0 + 0.15 * GameState.tal_rank("ember"))))
	if gold <= 0:
		return
	# «Жадность» алтаря Пепла: +25% золота (поверх будущих ng_gold_mult — они встанут ниже).
	gold = int(round(gold * (1.0 + 0.25 * int(GameState.flags.get("meta.greed", 0)))))
	# t20 «Глубокие карманы» мета-доски (meta.mb.deep_pockets): +8/16/24% золота
	# мобов за ранг — последняя надбавка перед выдачей (поверх волны/угорь/жадность).
	gold = int(round(gold * (1.0 + 0.01 * float(GameState.mb_value("deep_pockets")))))
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

static func _ow_gold_belt_mult(b: int) -> float:
	return 1.0 + OW.GOLD_BELT_STEP * float(b)

## Монеты из строки таблицы: [min, max] — равномерный бросок, int — сумма.
static func _roll_gold(v: Variant) -> int:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return randi_range(int(v[0]), int(v[1]))
	return maxi(0, int(v))

## Выдача материала в стопку (g20a): qty штук через единственную точку
## add_material(); переполнение стопки (99) — «потерян» как у старых дропов.
static func _give_mat(gs: Node, mid: String, qty: int) -> void:
	var added := 0
	for q in qty:
		if GameState.add_material(mid):
			added += 1
	if added == 0:
		gs.toast.emit("Инвентарь полон — %s потерян" % GameState.mat_name(mid))
	else:
		gs.toast.emit("Трофей: %s (%d/%d)." % [GameState.mat_name(mid), gs.mat_count(mid), GameState.MAT_CAP])

## g20b: редкий дроп снаряжения (5% строка таблицы). Предмет уникален:
## повторный дроп той же вещи — бездна молчания (дублей сумка не плодит).
## Цветная рамка редкости в мире — короткий glint над точкой смерти.
static func _give_gear(gs: Node, id: String, world_pos: Vector2 = Vector2.ZERO, world: Node2D = null) -> void:
	if id == "" or not GearData.has_item(id):
		push_warning("Loot: неизвестный gear id: %s" % id)
		return
	if not gs.ensure_gear(id):
		return
	var it := GearData.item(id)
	var rn := GearData.rarity_name(id)
	GameAudio.sfx("potion")
	gs.toast.emit("Трофей: %s%s!" % [String(it.get("name", id)), (" — " + rn) if rn != "" else ""])
	if world != null and GearData.rarity_of(id) != "":
		Fx.gear_glint(world_pos, world, GearData.rarity_color(id))

## g20b (вердикт §4 «гарантированные наборы»): выдача сундучного сета
## снаряжения (деревня — краткий меч+кожа, пещера — северяне+кольчуга,
## Пепелище — клыко-клинок+шкура вепря). Один сундук открывается один раз,
## значит и сет один раз (used/chests_used — канон T2).
static func grant_gear_set(gs: Node, ids: Array) -> void:
	var got: Array = []
	for gid in ids:
		var id := String(gid)
		if gs.ensure_gear(id):
			got.append(String(GearData.item(id).get("name", id)))
	if not got.is_empty():
		GameAudio.sfx("coin")
		gs.toast.emit("В сундуке снаряжение: %s!" % ", ".join(PackedStringArray(got)))

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
