extends Area2D
## Интерактивный объект: трава или сундук.
## Травы — возобновляемый ресурс (зелья): через ~50 с отрастают на месте.

const HERB_RESPAWN := 50.0
## Травы в бою (combat_t > 0) — правило «на шуму боя»: сбор не запрещён, но
## количество HERB_PICK режется множителем COMBAT_HERB_MULT с округлением вверх
## и нижним пределом COMBAT_HERB_MIN (минимум 1, если куст не пустой).
const HERB_PICK := 1
const COMBAT_HERB_MULT := 0.5
const COMBAT_HERB_MIN := 1

var world: Node2D
var kind := "herb"
var area := ""  # D4: зона uid-префикса ("village"); "" — legacy-форма без префикса
var used := false
var tile_xy := Vector2i.ZERO
var spr: Sprite2D
var _respawn_t := 0.0

func setup(p_world: Node2D, p_kind: String, tile: Vector2i, p_area := "") -> void:
	world = p_world
	kind = p_kind
	area = p_area
	tile_xy = tile
	position = world.tile_to_world(tile)
	spr = Sprite2D.new()
	spr.texture = _atlas(11 if kind == "herb" else 10)
	add_child(spr)
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 10.0
	cs.shape = sh
	add_child(cs)
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	refresh_used()

## Сундук уже открыт в прошлой сессии — восстанавливаем состояние из сейва (фикс T2).
## Вызывается и после load_game(): сущности мира строятся до чтения сейва.
func refresh_used() -> void:
	if kind != "chest" or used:
		return
	# D4: uid с зоной ("chest@village:37,21"), но старый координатный ключ
	# ("chest@37,21") остаётся валидным навсегда — сейвы v1–v3 не мигрируем.
	if GameState.chest_used(_uid()) or GameState.chest_used(_uid_legacy()):
		used = true
		spr.texture = _atlas(14)

## Устойчивый id объекта: тип+зона+тайл из map-меты, например
## "chest@village:37,21". Без зоны (herbs, песочницы) — прежний вид "chest@37,21".
func _uid() -> String:
	if area == "":
		return _uid_legacy()
	return "%s@%s:%d,%d" % [kind, area, tile_xy.x, tile_xy.y]

## Старый формат id: тип+тайл без зоны. Только для чтения персиста (сейвы до D4);
## при открытии пишем строго _uid() — второй записи на один сундук не заводим.
func _uid_legacy() -> String:
	return "%s@%d,%d" % [kind, tile_xy.x, tile_xy.y]

func _atlas(tile_index: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/tiles.png")
	at.region = Rect2(tile_index * 16, 0, 16, 16)
	return at

func get_hint() -> String:
	if kind == "herb":
		return "Взять траву" if not used else "Трава ещё не отросла"
	return "Открыть сундук" if not used else "Пустой сундук"

func try_interact() -> void:
	if used:
		return
	if kind == "herb":
		if GameState.elder_quest == 0:
			GameState.toast.emit("Рановато. Сначала поговори со старейшиной.")
			return
		var picked := HERB_PICK
		var in_combat := GameState.combat_t > 0.0
		if in_combat:
			picked = maxi(COMBAT_HERB_MIN, ceili(HERB_PICK * COMBAT_HERB_MULT))
		GameState.herbs += picked
		GameAudio.sfx("step2", 1.0, randf_range(1.15, 1.35))  # шорох среза травы (аудио-аудит)
		if in_combat:
			# один тост: HUD показывает только последний, два подряд не годятся
			GameState.toast.emit("На шуму боя не до трав! Собрано +%d (всего: %d)" % [picked, GameState.herbs])
		else:
			GameState.toast.emit("Трава собрана: +%d (всего: %d). Q — испить снадобья (+3 HP)" % [picked, GameState.herbs])
		GameState.quest_changed.emit()
		if GameState.elder_quest == 1 and GameState.herbs >= 3:
			GameState.toast.emit("Достаточно! Отнеси старейшине.")
		used = true
		_respawn_t = HERB_RESPAWN
		spr.visible = false
		_sync_shadow()  # иначе чёрный блин тени висит над пустой клеткой до респавна
	else:
		used = true
		# t39 (находка t38): сундук НЕ выдаёт меч — меч покупается у кузнеца (80g),
		# а бесплатный «второй меч» обесценивает экономику первой минуты. Награда —
		# кошель: вместе с Loot.chest_reward (8–18 зол. + расходник с шансом 50%)
		# суммарно 40–60 зол.: purse≥32 закрывает нижнюю границу (32+8=40),
		# purse≤42 — верхнюю (42+18=60).
		GameState.chest_mark_used(_uid())  # «сундук открыт» в сейв (фикс T2)
		Loot.chest_reward(GameState)  # золото/зелье (loot.gd)
		var purse := randi_range(32, 42)
		GameState.add_gold(purse)
		GameAudio.sfx("coin")
		GameState.toast.emit("В сундуке — кошель: ещё +%d зол.! Меч ищите у кузнеца." % purse)
		GameState.quest_changed.emit()  # автосейв: состояние сундука и золото
		Achv.on_chest_opened()  # ачивка «Клад» (achv.gd)
		if FirstHint.I != null: FirstHint.I.show_hint("chest", "В сундуках — золото и расходники. Оружие — у кузнеца.")
		spr.texture = _atlas(14)
		world.near.erase(self)

func _process(delta: float) -> void:
	if kind == "herb" and used:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			used = false
			spr.visible = true
			_sync_shadow()  # трава отросла — тень возвращается вместе с ней

func _on_enter(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.append(self)

func _on_exit(b: Node) -> void:
	if b.is_in_group("player"):
		world.near.erase(self)

## Тень атмосферы (AtmoShadow) — отдельный child (вешает atmosphere.gd), поэтому
## при скрытии/возврате спрайта гасим и её синхронно; страховочная синхронизация
## есть и в скане atmosphere (_sync_shadow). Сундук не затронут: его спрайт не
## скрывается (при смене текстуры закрыт->открыт тень остаётся).
func _sync_shadow() -> void:
	var sh := get_node_or_null("AtmoShadow")
	if sh != null:
		(sh as CanvasItem).visible = spr != null and spr.visible
