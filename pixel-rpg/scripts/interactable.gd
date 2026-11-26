extends Area2D
## Интерактивный объект: трава, сундук или доска объявлений (t18, 25.11 —
## kind "board": код-графика, многоразовая, цепочка поясов в quests_data).
## Травы — возобновляемый ресурс (зелья): через ~50 с отрастают на месте.

const HERB_RESPAWN := 50.0
const BD := preload("res://scripts/bounties.gd")  # t36 I3: охоты на той же доске
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
	if kind == "board":
		# t18 (25.11): доска объявлений старейшины — код-графика (ноль растров);
		# многоразовая: used не ставит, диалог с цепочкой поясов живёт в try.
		var art := _BoardArt.new()
		art.position = Vector2(0, -4)
		add_child(art)
	else:
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
	if kind == "board":
		# t18: подсказка доски честная по состоянию цепочки (язык маркеров NPC:
		# «смотри объявления» = можно взять, «сдай» = цель закрыта).
		var i := QuestsData.belt_current(GameState)
		if i >= QuestsData.BELT_CHAIN.size():
			# t36 I3: цепочка закрыта — доска работает охотой дня.
			var hs0 := BD.hunt_hint(GameState)
			return ("Доска: %s" % hs0) if hs0 != "" else "Доска: цепочка закрыта"
		match QuestsData.belt_status(GameState, i):
			QuestsData.STATUS_NONE:
				if QuestsData.belt_can_offer(GameState, i):
					return "Доска: смотри объявления"
				# t36 I3: «не по пути» — единственная ветка NONE без действия
				# цепочки, сюда подмешивается охота; «смотри объявления» —
				# строка-пин цепочки, не тронута.
				var hs1 := BD.hunt_hint(GameState)
				return "Доска: объявление не по пути" \
						+ ("; %s" % hs1 if hs1 != "" else "")
			QuestsData.STATUS_ACTIVE:
				return "Доска: сдай" if QuestsData.belt_ready(GameState, i) \
						else "Доска: работаешь — %s" % QuestsData.belt_progress_line(GameState, i)
			_:
				return "Доска"
	if kind == "herb":
		# g12 (Г1.2 «Три коренья»): в речи мира это коренья Морги (GLOSSARY #21);
		# машинное имя kind/счётчика — прежнее ("herb"/herbs), канон полей сейва.
		return "Взять коренье" if not used else "Коренье ещё не отросло"
	return "Открыть сундук" if not used else "Пустой сундук"

func try_interact() -> void:
	if kind == "board":
		_interact_board()
		return
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
			GameState.toast.emit("На шуму боя не до корений! Собрано +%d (всего: %d)" % [picked, GameState.herbs])
		else:
			GameState.toast.emit("Коренье собрано: +%d (всего: %d). Q — испить снадобья (+3 HP)" % [picked, GameState.herbs])
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
		# g13 (BALANCE строка 4, вердикт g11): деревенский сундук главы 1 — это
		# плановые +15 (горсть 8–18 из loot.gd), а КОШЕЛЬ живёт «как в коде-
		# диапазонах» вне деревни: в пещере/Пепелище 32..42 правят экономику меча
		# (t39), в главе 1 он ломал коридор дохода 78–106 (эконометр _t42).
		# Источник-пин T14 не тронут: литерал randi_range(32, 42) в файле жив.
		GameState.chest_mark_used(_uid())  # «сундук открыт» в сейв (фикс T2)
		Loot.chest_reward(GameState)  # золото/зелье (loot.gd)
		# g20b (вердикт 17.11 §4 «гарантированные наборы»): деревенский сундук
		# главы 1 добирает СТАРТОВЫЙ сет — краткий меч + кожа + пара точильных
		# камней. Золото BALANCE-строки 4 (+15) не тронуто; сундук одноразовый
		# (used/chests_used), значит и сет строго один раз на сейв-жизнь.
		if area == "village":
			for i in 2:
				GameState.add_material("whet")
			# t17 (25.11): cell — uid сундука: аффиксы стартового сета
			# детерминированы под этот сейв и не дрейфят при повторных входах.
			Loot.grant_gear_set(GameState, ["shortsword", "leather"], "chest:" + _uid())
		if area != "village":
			var purse := randi_range(32, 42)
			GameState.add_gold(purse)
			GameAudio.sfx("coin")
			GameState.toast.emit("В сундуке — кошель: ещё +%d зол.! Меч ищите у кузнеца." % purse)
		GameState.quest_changed.emit()  # автосейв: состояние сундука и золото
		Achv.on_chest_opened()  # ачивка «Клад» (achv.gd)
		if FirstHint.I != null: FirstHint.I.show_hint("chest", "В сундуках — золото, расходники и снаряжение. Оружие — и у кузнеца тоже.")
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

# --- t18 «Квесты поясов» (25.11): доска объявлений старейшины ---------------

## Ритуал доски: первое несданное звено цепочки. Взять (если пояс открыт),
## сдать (если цель закрыта) или честная подсказка, что мешает. Идемпотентность
## наград — в QuestsData.belt_turnin (флаг 2 до выдачи).
## t36 I3 (26.11): доска — одно место двух потоков. Если у цепочки есть
## НАВЕШАННОЕ действие (взять/сдать) — нажатие её, без изменений; иначе
## нажатие забирает охота (взятие бесплатное / статус). belt-цепь не тронута.
func _interact_board() -> void:
	GameAudio.sfx("ui_click")
	var i := QuestsData.belt_current(GameState)
	var st := QuestsData.belt_status(GameState, i)
	var chain_pending := i < QuestsData.BELT_CHAIN.size() \
			and ((st == QuestsData.STATUS_NONE and QuestsData.belt_can_offer(GameState, i)) \
				or (st == QuestsData.STATUS_ACTIVE and QuestsData.belt_ready(GameState, i)))
	if chain_pending:
		if st == QuestsData.STATUS_NONE:
			QuestsData.belt_offer(GameState, i)
		else:
			QuestsData.belt_turnin(GameState, i)
		return
	if BD.board_press(GameState):
		return
	if i >= QuestsData.BELT_CHAIN.size():
		GameState.toast.emit("На доске — старые адреса. Старейшина больше ни о чём не просит.")
		return
	var title := String(QuestsData.belt_link(i).get("title", ""))
	if st == QuestsData.STATUS_ACTIVE:
		GameState.toast.emit("«%s» ещё не закрыто: %s."
				% [title, QuestsData.belt_progress_line(GameState, i)])
	else:
		GameState.toast.emit("Объявление «%s» не по пути: сперва доберись до «%s»."
				% [title, QuestsData.belt_zone_name(GameState, i)])

class _BoardArt:
	extends Node2D
	## Код-графика доски (арт-закон: ноль растров, как маркер npc.gd и RootBoard):
	# ножки, доска-планка, два листа, амбер-кант = на доске есть дело (взять/сдать).
	func _ready() -> void:
		GameState.quest_changed.connect(queue_redraw)
	func _draw() -> void:
		var wood := Color(0.47, 0.34, 0.22)
		var dark := Color(0.20, 0.14, 0.09)
		draw_rect(Rect2(-6, -2, 2, 9), dark)              # ножки
		draw_rect(Rect2(4, -2, 2, 9), dark)
		draw_rect(Rect2(-9, -11, 18, 10), wood)           # планка
		draw_rect(Rect2(-9, -11, 18, 10), dark, false, 1.0)
		draw_rect(Rect2(-7, -9, 7, 6), Color(0.93, 0.90, 0.80))   # листы
		draw_rect(Rect2(1, -8, 6, 6), Color(0.87, 0.84, 0.73))
		var i := QuestsData.belt_current(GameState)
		if i < QuestsData.BELT_CHAIN.size() and (QuestsData.belt_can_offer(GameState, i)
				or QuestsData.belt_ready(GameState, i)):
			draw_rect(Rect2(-5, -10, 2, 2), Color(1.0, 0.7, 0.26))  # амбер = есть дело
			draw_rect(Rect2(2, -9, 2, 2), Color(1.0, 0.7, 0.26))
