extends RefCounted
## Алхимия: рецепты из data/alchemy.json, варка у костра и питьё зарядов.
## Варить можно только рядом с горящим костром (проверяет вызывающий — hud.gd);
## здесь — чистые операции над GameState, удобно тестировать из харнессов.

const RECIPES_PATH := "res://data/alchemy.json"
static var _recipes: Dictionary = {}

## Справочник рецептов (id -> {name, desc, effect, cost, ...}); пустой без файла.
static func recipes() -> Dictionary:
	if _recipes.is_empty():
		if FileAccess.file_exists(RECIPES_PATH):
			var f := FileAccess.open(RECIPES_PATH, FileAccess.READ)
			if f != null:
				var data: Variant = JSON.parse_string(f.get_as_text())
				if typeof(data) == TYPE_DICTIONARY:
					_recipes = data
		else:
			push_warning("Нет файла рецептов: %s" % RECIPES_PATH)
	return _recipes

static func recipe(rid: String) -> Dictionary:
	var r: Variant = recipes().get(rid, {})
	return r if typeof(r) == TYPE_DICTIONARY else {}

static func cost_text(rid: String) -> String:
	var parts: Array[String] = []
	for mid in recipe(rid).get("cost", {}):
		parts.append("%d %s" % [int(recipe(rid)["cost"][mid]), GameState.mat_name(String(mid)).to_lower()])
	return " + ".join(parts)

## Сварить рецепт: сначала проверяем осуществимость (материалы + лимонка эффекта),
## потом атомарно тратим и применяем. false — отказ (тост уже произнесён).
static func brew(rid: String) -> bool:
	var r := recipe(rid)
	if r.is_empty():
		push_warning("Неизвестный рецепт: %s" % rid)
		return false
	var eff := String(r.get("effect", ""))
	if eff not in ["charge", "xp", "calm"]:
		push_warning("Рецепт без эффекта: %s" % rid)
		return false
	# лимит переноса — часть дефицита: заряды нельзя варить «про запас» сверх cap
	if eff == "charge" and GameState.brewed_potions >= GameState.BREWED_CAP:
		GameState.toast.emit("Пояс полон: максимум %d крепких зелий." % GameState.BREWED_CAP)
		return false
	if not GameState.try_spend_materials(r.get("cost", {})):
		return false
	var nm := String(r.get("name", rid))
	match eff:
		"charge":
			GameState.brewed_potions = mini(GameState.brewed_potions + int(r.get("count", 1)), GameState.BREWED_CAP)
			GameState.toast.emit("Сварено: %s (запас %d)" % [nm, GameState.brewed_potions])
		"xp":
			var n := int(r.get("amount", 0))
			GameState.add_xp(n)
			GameState.toast.emit("%s: +%d опыта" % [nm, n])
		"calm":
			GameState.combat_t = 0.0
			GameState.toast.emit("%s: затишье — можно отдыхать" % nm)
		_:
			push_warning("Рецепт без эффекта: %s" % rid)
			return false
	GameState.quest_changed.emit()  # трата материалов переживает перезапуск
	return true

## Выпить крепкое зелье (кнопка HUD; Q-зелье — отдельная семантика, не трогаем).
static func drink_brewed() -> bool:
	if GameState.brewed_potions <= 0:
		GameState.toast.emit("Крепких зелий нет. Вари у костра.")
		return false
	if GameState.hp >= GameState.max_hp:
		GameState.toast.emit("Ты и так здрав.")
		return false
	if GameState.combat_t > 0.0:
		# питьё требует секунды на глоток — в бою (COMBAT_HOLD) отказ, состояние не трогаем
		GameState.toast.emit("Слишком тревожно — выпей после боя.")
		return false
	GameState.brewed_potions -= 1
	GameState.heal(GameState.STRONG_POTION_HEAL)
	GameState.quest_changed.emit()
	GameState.toast.emit("Крепкое зелье: +%d HP (осталось %d)" % [GameState.STRONG_POTION_HEAL, GameState.brewed_potions])
	return true
