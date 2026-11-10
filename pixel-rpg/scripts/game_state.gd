extends Node
## Глобальное состояние игры: герой, прогресс, квесты, сохранения.

const Classes := preload("res://scripts/classes_data.gd")

signal stats_changed
signal quest_changed
signal toast(text: String)
signal leveled_up(level: int)
signal regen_hp_tick
signal regen_mana_tick
signal gold_changed
## Новый «Круг Пепла» активирован: мир пересобран владельцем сцены (хук в world).
signal ng_plus_started

# --- восстановление (B+F): внебойная регенерация + мана мага ---
const COMBAT_HOLD := 6.0        # сколько секунд считаем «в бою» после контакта
# HP_REGEN_EVERY переехал в hp_regen_interval(): базовые 4.0 с теперь левый
# край таблицы таланта «Глубокое дыхание» (CONTRACT_TALENTS §3).
const MANA_REGEN_EVERY := 2.0   # +2 маны каждые 2 с вне боя
const MANA_REGEN_STEP := 2

# --- привалы и алхимия (дефицит: дроп редкий, перенос ограничен, костёр одноразовый) ---
const MAT_CAP := 5              # лимит переноса на каждый материал
const BREWED_CAP := 2           # запас варёных зелий (крепких)
const STRONG_POTION_HEAL := 6   # HP за крепкое зелье (обычное травяное — 3)
const MAT_NAMES := {"suhotsvet": "Сухоцвет", "zhim": "Жим"}

var max_hp := 10
var hp := 10
var mana := 0
var max_mana := 0
var combat_t := 0.0
var _hp_regen_t := 0.0
var _mana_regen_t := 0.0
var level := 1
var xp := 0
var xp_next := 20
## Класс героя: "" — ещё не выбран (модалка), старые сейвы читаются как "warrior".
var class_id := ""
var has_sword := false
## Урон — производный: классный x2 за меч +1 за амулет.
## Запись игнорируется (наследие старого кода, писавшего damage = maxi(...)):
## канон — флаги has_sword/has_amulet + класс.
var damage: int:
	get:
		return GearData.player_damage(int(Classes.class_data(class_id).dmg), self)
	set(_value):
		pass
var herbs := 0
var slime_kills := 0
## Убийства слаймов ЗА ТЕКУЩИЙ круг (обнуляется в start_ng_plus): боковой квест
## «Зачистка леса» должен перепроходить каждый круг, а не «уже сделан навсегда».
## slime_kills остаётся lifetime-счётчиком ачивок (Охотник 25/100).
var slime_kills_circle := 0
## Алхимия: материалы с врагов (id -> кол-во, см. MAT_NAMES) и заряды варёных зелий.
var materials := {"suhotsvet": 0, "zhim": 0}
var brewed_potions := 0
## Костры-привалы: id -> true, если уже использован (одноразовые).
var campfires_used := {}
## Открытые сундуки: id вида "chest@x,y" (тип+тайл из map-меты). Переживают перезапуск.
var chests_used: Array = []
## Квесты: 0 = не начат, 1 = активен, 2 = выполнен
var elder_quest := 0
var slime_quest := 0
var seen_intro := false
## Пещера «Осквернённый гром» (cave_state): 0 не начато, 1 квест у Геральда,
## 2 босс мёртв, 3 ключ отдан, 4 амулет возвращён
var cave_state := 0
var has_key := false
var has_amulet := false
var door_opened := false  # дверь алтарной ниши открыта ключом (переживает перезаход)
var in_cave := false
var seen_cave_intro := false
var seen_boss_intro := false
## Смерть босса хранится в cave_state; var-обёртка — для удобной записи из brute.gd
var boss_defeated: bool:
	get:
		return cave_state >= 2
	set(value):
		if value:
			cave_state = maxi(cave_state, 2)

var player_pos := Vector2.ZERO
var pos_valid := false
var input_locked := false

# --- v2 (фундамент волны «контент»): золото, шестерня, общие флаги ---
## Хранилище здесь; реестр предметов (id -> слот/цена/статы) — scripts/gear_data.gd
## (фича экономики), справочник квестов — scripts/quests_data.gd (фича квестов).
var gold := 0
## Снаряжение: слот ("weapon"/"armor") -> item id, "" — пусто.
var gear := {"weapon": "", "armor": ""}
## Универсальные событийные флаги (квесты, диалоги, лавочник): id -> bool/int/string.
var flags := {}

func _ready() -> void:
	# Автосебы: редкие, но важные для игрока моменты не должны теряться.
	leveled_up.connect(func(_l: int) -> void: save_game())
	quest_changed.connect(func() -> void: save_game())
	gold_changed.connect(func() -> void: save_game())

## Интервал регена HP: база 4.0 с, талант «Глубокое дыхание» (breath) сокращает
## до 3.2/2.6 (CONTRACT_TALENTS §3: таблица [4.0, 3.2, 2.6], индекс 0..2).
func hp_regen_interval() -> float:
	var t := [4.0, 3.2, 2.6]
	return float(t[clampi(tal_rank("breath"), 0, 2)])

func _process(delta: float) -> void:
	combat_t = maxf(0.0, combat_t - delta)
	if combat_t > 0.0 or hp <= 0:
		return  # в бою реген нет — только в тишине
	if hp < max_hp:
		_hp_regen_t += delta
		if _hp_regen_t >= hp_regen_interval():
			_hp_regen_t = 0.0
			hp += 1
			stats_changed.emit()
			regen_hp_tick.emit()
	else:
		_hp_regen_t = 0.0
	if max_mana > 0 and mana < max_mana:
		_mana_regen_t += delta
		if _mana_regen_t >= MANA_REGEN_EVERY:
			_mana_regen_t = 0.0
			mana = mini(max_mana, mana + MANA_REGEN_STEP)
			stats_changed.emit()
			regen_mana_tick.emit()
	else:
		_mana_regen_t = 0.0

## Контакт с врагом (нанесли или получили) — сброс «тишины» регена.
func entered_combat() -> void:
	combat_t = COMBAT_HOLD

## Попотратить ману; false — не хватает (с тостом).
func try_spend_mana(n: int) -> bool:
	if n <= 0:
		return true
	if mana < n:
		toast.emit("Не хватает энергии!")
		return false
	mana -= n
	stats_changed.emit()
	return true

func heal_full() -> void:
	hp = max_hp
	mana = max_mana
	stats_changed.emit()

func hurt(n: int) -> void:
	n = GearData.absorb(self, n)  # броня: кожа -1, кольчуга -2 (не ниже 1)
	if hp <= 0:
		return
	hp = max(0, hp - n)
	stats_changed.emit()

func heal(n: int) -> void:
	hp = min(max_hp, hp + n)
	stats_changed.emit()

# --- привалы и алхимия ---

func mat_name(mid: String) -> String:
	return String(MAT_NAMES.get(mid, mid))

func mat_count(mid: String) -> int:
	return int(materials.get(mid, 0))

## Положить материал в рюкзак; false — неизвестный id или лимит переноса.
func add_material(mid: String) -> bool:
	if not materials.has(mid):
		push_warning("Неизвестный материал: %s" % mid)
		return false
	if mat_count(mid) >= MAT_CAP:
		return false
	materials[mid] = mat_count(mid) + 1
	return true

## Списать набор материалов; false (с тостом) — не хватает. Тратит только если всего хватает.
func try_spend_materials(cost: Dictionary) -> bool:
	for mid in cost:
		if mat_count(String(mid)) < int(cost[mid]):
			toast.emit("Не хватает: %s (нужно %d, есть %d)" % [mat_name(String(mid)), int(cost[mid]), mat_count(String(mid))])
			return false
	for mid in cost:
		materials[String(mid)] = mat_count(String(mid)) - int(cost[mid])
	return true

# --- сундуки (персист «сундук открыт») ---

func chest_used(uid: String) -> bool:
	return chests_used.has(uid)

func chest_mark_used(uid: String) -> void:
	if not chests_used.has(uid):
		chests_used.append(uid)

# --- v2: золото / снаряжение / флаги ---

func add_gold(n: int) -> void:
	if n == 0:
		return
	gold = maxi(0, gold + n)
	gold_changed.emit()

## Потратить золото; false с тостом — не хватает.
func spend_gold(n: int) -> bool:
	if n < 0:
		return false
	if gold < n:
		toast.emit("Не хватает золота: нужно %d, есть %d" % [n, gold])
		return false
	gold -= n
	gold_changed.emit()
	return true

func can_afford(n: int) -> bool:
	return gold >= n

## Надеть item id в слот; возвращает id ранее надетого предмета (или "").
## legacy-флаг has_sword держится в синхроне ("sword"/"") до канона gear_data.gd.
func equip_item(slot: String, item_id: String) -> String:
	if not gear.has(slot):
		push_warning("Неизвестный слот: %s" % slot)
		return ""
	var prev := String(gear[slot])
	gear[slot] = item_id
	if slot == "weapon":
		# M1 (QA): флаг синхронизируется ЖЁСТКО — любой другой id (топор, клинок)
		# обязан гасить has_sword, иначе при очистке слота остаётся «призрачный меч» x2.
		has_sword = (item_id == "sword")
		stats_changed.emit()
	return prev

func get_flag(id: String, def: Variant = false) -> Variant:
	return flags.get(id, def)

func set_flag(id: String, value: Variant) -> void:
	flags[id] = value

# --- безопасный разбор полей сейва (ни одно поле не должно уронить парсер) ---

## Число из поля сейва: null/битое/строка-не-число => default.
static func _num(v: Variant, def: int) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			if is_nan(v) or is_inf(v):
				return def
			return int(v)
		TYPE_STRING:
			var s := String(v)
			if s.is_valid_int():
				return int(s)
			if s.is_valid_float():
				return int(float(s))
			return def
		_:
			return def

## Вещественное из поля сейва: null/битое => default.
static func _numf(v: Variant, def: float) -> float:
	match typeof(v):
		TYPE_INT:
			return float(v)
		TYPE_FLOAT:
			return def if is_nan(v) or is_inf(v) else float(v)
		TYPE_STRING:
			var s := String(v)
			return float(s) if s.is_valid_float() else def
		_:
			return def

## Флаг из поля сейва: null/битое => default.
static func _flag(v: Variant, def: bool) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT, TYPE_FLOAT:
			return _num(v, 0) != 0
		_:
			return def

## Строка из поля сейва: null/битое => default.
static func _str(v: Variant, def: String) -> String:
	return String(v) if typeof(v) == TYPE_STRING else def

func add_xp(n: int) -> void:
	# Талант «Рачительный опыт» (§3): +10% опыта за ранг — только на положительный
	# приток (отрицательные корректировки, если появятся, множить нельзя).
	if n > 0:
		n = int(round(n * (1.0 + 0.10 * tal_rank("scholar"))))
	xp += n
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = int(round(xp_next * 1.6))  # правка v1.1: рост x1.6 (20->32->51->82)
		max_hp += 2
		heal_full()
		toast.emit("Новый уровень: %d! Максимум HP вырос!" % level)
		leveled_up.emit(level)
		# Таланты открываются со 2-го уровня (первое очко) — контекстная подсказка
		# первопроходцу (канон вызова как slime.gd: guard FirstHint.I != null;
		# дедуп и очередь — внутри FirstHint.show_hint по флагу hint.talents).
		if level == 2 and FirstHint.I != null:
			FirstHint.I.show_hint("talents", "Новый уровень — очко таланта. J → Таланты.")
	stats_changed.emit()

# --- классы (спринт 2) ---

## Пересчёт макс. HP: класс + 2 за каждый уровень + 4 за амулет + 4 за «Благословение» алтаря.
func recalc_max_hp() -> void:
	max_hp = int(Classes.class_data(class_id).hp) + 2 * (level - 1) + (4 if has_amulet else 0) + 4 * int(flags.get("meta.bless", 0))
	if hp > max_hp:
		hp = max_hp
	stats_changed.emit()

## Пересчёт макс. маны из класса (0 у не-магов); mana поджимается под потолок.
func recalc_max_mana() -> void:
	max_mana = int(Classes.class_data(class_id).get("mana", 0))
	if mana > max_mana:
		mana = max_mana
	stats_changed.emit()

## Выбор/смена класса: базовые статы пересчитываются, HP полный.
func set_class(id: String) -> void:
	if class_id != "":
		# класс выбирается один раз на этапе создания героя и больше не меняется
		push_warning("Класс уже выбран — смена невозможна")
		return
	if not Classes.CLASSES.has(id):
		push_warning("Неизвестный класс: %s" % id)
		return
	class_id = id
	recalc_max_hp()
	recalc_max_mana()
	heal_full()

# --- древо талантов (CONTRACT_TALENTS §2): ранги живут в flags "tal."+id ---
## Никаких новых top-level полей сейва: только int-ранги 0..max в flags.
## Реестр узлов и их максимумы — scripts/talents.gd (class_name Talents).
## Кап CAP-128 на число ключей flags учитывает 14 ключей tal.* (док в from_dict).

## Ранг узла talents (0..max_of); неизвестный id => max_of=0 => 0.
func tal_rank(id: String) -> int:
	return clampi(_num(flags.get("tal." + id, 0), 0), 0, Talents.max_of(id))

## Сколько очков таланта уже вложено (сумма рангов по всем узлам).
func tal_spent() -> int:
	var s := 0
	for id in Talents.NODES:
		s += tal_rank(String(id))
	return s

## Свободные очки таланта: по одному за каждый уровень выше 1-го минус вложенные.
func tal_points() -> int:
	return maxi(level - 1 - tal_spent(), 0)

## Потратить очко в узел id. false (со звуком ui_deny) — неизвестный id, узел
## прокачан до cap или нет свободных очков. Успех — +1 ранг, ui_confirm и
## quest_changed (тот же канал автосейва, что квесты/ачивки).
func try_spend_talent(id: String) -> bool:
	if not Talents.NODES.has(id) or tal_rank(id) >= Talents.max_of(id) or tal_points() <= 0:
		GameAudio.sfx("ui_deny")
		return false
	flags["tal." + id] = tal_rank(id) + 1
	quest_changed.emit()
	GameAudio.sfx("ui_confirm")
	return true

func to_dict() -> Dictionary:
	return {
		"max_hp": max_hp, "hp": hp, "mana": mana, "level": level, "xp": xp, "xp_next": xp_next,
		"damage": damage, "has_sword": has_sword, "class_id": class_id,
		"herbs": herbs, "slime_kills": slime_kills,
		"slime_kills_circle": slime_kills_circle,
		"elder_quest": elder_quest, "slime_quest": slime_quest,
		"seen_intro": seen_intro,
		"cave_state": cave_state, "has_key": has_key, "has_amulet": has_amulet,
		"door_opened": door_opened,
		"in_cave": in_cave, "seen_cave_intro": seen_cave_intro,
		"seen_boss_intro": seen_boss_intro, "boss_defeated": boss_defeated,
		"materials": materials.duplicate(), "brewed": brewed_potions,
		"campfires_used": campfires_used.duplicate(),
		"chests_used": chests_used.duplicate(),
		"v": 2, "gold": gold, "gear": gear.duplicate(), "flags": flags.duplicate(),
		"px": player_pos.x, "py": player_pos.y, "pos_valid": pos_valid,
	}

func from_dict(d: Dictionary) -> void:
	# Порядок (фикс T8): сначала class/уровень/флаги -> recalc статов ->
	# и только потом hp/mana из сейва (иначе hp считается от «старого» max_hp=10).
	level = clampi(_num(d.get("level", 1), 1), 1, 99)
	xp = maxi(0, _num(d.get("xp", 0), 0))
	xp_next = maxi(1, _num(d.get("xp_next", 20), 20))
	# damage — производный, из справочника классов (legacy-поле сейва игнорируется)
	class_id = _str(d.get("class_id", "warrior"), "warrior")  # старый сейв без класса => воин
	has_sword = _flag(d.get("has_sword", false), false)
	herbs = maxi(0, _num(d.get("herbs", 0), 0))
	slime_kills = maxi(0, _num(d.get("slime_kills", 0), 0))
	slime_kills_circle = maxi(0, _num(d.get("slime_kills_circle", d.get("slime_kills", 0)), 0))  # легаси-сейв без поля — seed тоталом: активный квест круга не обнуляется (Q5-C5)
	elder_quest = clampi(_num(d.get("elder_quest", 0), 0), 0, 2)
	slime_quest = clampi(_num(d.get("slime_quest", 0), 0), 0, 2)
	seen_intro = _flag(d.get("seen_intro", false), false)
	# новые поля: СТАРЫЕ сейвы грузятся через значения по умолчанию
	cave_state = clampi(_num(d.get("cave_state", 0), 0), 0, 4)
	has_key = _flag(d.get("has_key", false), false)
	has_amulet = _flag(d.get("has_amulet", false), false)
	door_opened = _flag(d.get("door_opened", false), false)
	in_cave = _flag(d.get("in_cave", false), false)
	seen_cave_intro = _flag(d.get("seen_cave_intro", false), false)
	seen_boss_intro = _flag(d.get("seen_boss_intro", false), false)
	if _flag(d.get("boss_defeated", false), false):
		cave_state = maxi(cave_state, 2)
	# привалы и алхимия: СТАРЫЕ сейвы без этих полей => пустой рюкзак, костры целы
	materials = {"suhotsvet": 0, "zhim": 0}
	var md: Variant = d.get("materials", {})
	if typeof(md) == TYPE_DICTIONARY:
		for mid in materials:
			materials[mid] = clampi(_num(md.get(mid, 0), 0), 0, MAT_CAP)
	brewed_potions = clampi(_num(d.get("brewed", 0), 0), 0, BREWED_CAP)
	var cu: Variant = d.get("campfires_used", {})
	# M4 (QA): каппим как сундуки (64) с varning — раньше кап был только у
	# chests_used и молча резал данные, а campfires_used не валидировался вовсе.
	campfires_used = {}
	if typeof(cu) == TYPE_DICTIONARY:
		var cn := 0
		for ck in cu:
			if cn >= 64:
				push_warning("campfires_used: больше 64 ключей — остаток отброшен")
				break
			# N4 (адверсариал): значения — только bool-резолвер _flag: JSON-мусор
			# ("abc", null, словарь) => false, число => nonzero; в словаре живут
			# строго bool; campfire.gd читает тем же _flag — каналы не разойдутся.
			campfires_used[String(ck)] = _flag(cu[ck], false)
			cn += 1
	# сундуки: массив строк-ид; битые элементы молча пропускаем
	chests_used = []
	var chu: Variant = d.get("chests_used", [])
	if typeof(chu) == TYPE_ARRAY:
		for cid in chu:
			if typeof(cid) == TYPE_STRING and chests_used.size() < 64:
				chest_mark_used(String(cid))
	# --- v2: золото/шестерня/флаги (старые сейвы => чистые значения) ---
	gold = maxi(0, _num(d.get("gold", 0), 0))
	gear = {"weapon": "", "armor": ""}
	var gd: Variant = d.get("gear", {})
	if typeof(gd) == TYPE_DICTIONARY:
		for slot in gear:
			gear[slot] = _str(gd.get(slot, ""), "")
	# legacy-миграция: старый сейв с мечом => weapon="sword" (если слот пуст)
	if has_sword and String(gear["weapon"]) == "":
		gear["weapon"] = "sword"
	# N3 (адверсариал): единый источник правды — gear.weapon (канон equip_item,
	# M1); has_sword — производное зеркало. Обоюдно-несогласованные каналы
	# ("has_sword":true + weapon:"axe" — «призрачный меч») не переживают лоад;
	# прежняя M2-обратная синхронизация покрывается этой же строкой.
	has_sword = String(gear["weapon"]) == "sword"
	flags = {}
	var fd: Variant = d.get("flags", {})
	# CAP-128: load-лимит на число ключей flags. С деревом талантов сюда
	# приходит до 14 ключей tal.* (по одному на узел): типичный полный сейв
	# ~40 служебных ключей (ach./hint./meta./ng./q./ashen.) + 14 tal.* — до
	# капа 128 запас более чем двукратный, обрезки не происходит.
	if typeof(fd) == TYPE_DICTIONARY:
		var n := 0
		var truncated := false
		for k in fd:
			if typeof(k) != TYPE_STRING:
				continue
			if n >= 128:
				truncated = true
				break
			# M3 (QA): JSON отдаёт float для целых — приводим целые значения
			# обратно к int, иначе тип «плывёт» в сейве навсегда (typeof врёт).
			var v: Variant = fd[k]
			if typeof(v) == TYPE_FLOAT and not is_nan(v) and not is_inf(v) and v == floor(v) and absf(v) < 9.0e15:
				v = int(v)
			flags[String(k)] = v
			n += 1
		if truncated:
			push_warning("flags: больше 128 ключей — остаток отброшен при загрузке")
	player_pos = Vector2(_numf(d.get("px", 0.0), 0.0), _numf(d.get("py", 0.0), 0.0))
	pos_valid = _flag(d.get("pos_valid", false), false)
	recalc_max_hp()  # класс + уровни + амулет — канон поверх сохранённого max_hp
	recalc_max_mana()
	# hp: из сейва (клампы под потолок класса); нет/битое — ПОЛНЫЙ максимум класса,
	# а не дефолт «старого» max_hp=10 (фикс T8).
	var hpv := _num(d.get("hp", -1), -1)
	hp = clampi(hpv, 0, max_hp) if hpv >= 0 else max_hp
	# мана: старый сейв без поля => полная; всегда в пределах потолка класса
	var manav := _num(d.get("mana", -1), -1)
	mana = clampi(manav, 0, max_mana) if manav >= 0 else max_mana
	stats_changed.emit()
	quest_changed.emit()

func save_game() -> bool:
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true

func load_game() -> bool:
	if not FileAccess.file_exists("user://save_morkheim.json"):
		return false
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	from_dict(data)
	return true

# --- NG+ «Круги Пепла» (RETENTION_NG_PLUS §1): ОДНА точка истины формул ---
## Кап волны: дальше цифры не растут — круги на кап-значениях играются сколько
## угодно (удержание, а не бесконечная спираль).
const NG_WAVE_CAP := 5

## Текущий круг (обычная игра — 0). Сейвы без ng.* читаются как 0 (§5 риск-правило:
## только flags.get с дефолтом, никаких прямых обращений к ключу).
func ng_wave() -> int:
	return clampi(_num(flags.get("ng.wave", 0), 0), 0, NG_WAVE_CAP)

## Множитель HP мобов (§1.3): +50% за круг, потолок ×3.5 (на w5 и выше).
func hp_mult(w: int) -> float:
	return minf(1.0 + 0.5 * float(w), 3.5)

## Прибавка к урону мобов (§1.3): w1-2 +1, w3-4 +2, w5 +3.
func dmg_bonus(w: int) -> int:
	return int(ceil(float(w) / 2.0))

## Множитель золота (§1.3): +40% за круг, w5 → ×3.0. Применяется к ИТОГУ ролла.
func ng_gold_mult(w: int) -> float:
	return 1.0 + 0.4 * float(w)

## Начать новый круг (§1.1–1.2). P1: вызывается программно (триггер в диалоге
## Старейшины — P2, не здесь). Переносится: золото, шестерня, класс/уровни/статы,
## амулет, achv.*, meta.*, daily.*, ng.*; сбрасывается мир и сюжет (§1.2).
## На кап-волне номер не растёт, но мир сбрасывается — круги повторяемы.
## Возвращает номер круга после вызова.
func start_ng_plus() -> int:
	var w := mini(ng_wave() + 1, NG_WAVE_CAP)
	flags["ng.wave"] = w
	# --- что сбрасывается (инверсия таблицы переноса §1.2) ---
	elder_quest = 0
	slime_quest = 0
	cave_state = 0  # boss_defeated — производный (var-обёртка), обнулится сам
	has_key = false
	door_opened = false
	chests_used = []
	campfires_used = {}
	materials = {"suhotsvet": 0, "zhim": 0}  # структура сохраняем: add_material сверяет has()
	brewed_potions = 0
	# травы — подвальный инвентарь деревенского круга («Сухоцвет впрок»
	# перепроходит каждый круг, carry-over тривиализировал бы квест);
	# счётчик убийств круга — парный ему для «Зачистки леса».
	herbs = 0
	slime_kills_circle = 0
	# алтарный «Кошелёк» (meta.purse, кап 2): +50 золота за ранг к старту круга.
	gold += 50 * int(flags.get("meta.purse", 0))
	# квестовые/диалоговые флаги (q.*, q.got.*, q.last.*) и Пепелище (ashen.*:
	# ведьма/сундук/интро) — перепроходятся каждый круг (канон-решение оркестратора:
	# Пепла с ведьмы не течёт, зона пересоздаётся живой);
	# ng.boss_<w> — пер-волновые гейты пепла за босса (+3/убийство). Без сброса
	# повторные круги на кап-волне остаются без босс-пепла и ретеншн-луп
	# пересыхает; ach.* уже разблокированные (ng_crowns) не откатываются —
	# unlock идемпотентен по ach.-флагам.
	# collect-then-erase: не мутируем flags во время итерации по нему
	var wipe_keys: Array = []
	for k in flags:
		var ks := String(k)
		if ks.begins_with("q.") or ks.begins_with("ashen.") or ks.begins_with("ng.boss_") or ks.begins_with("tal."):
			wipe_keys.append(k)
	for k in wipe_keys:
		flags.erase(k)
	# мир пересобирается хуком владельца сцены; точка входа — деревня (не пещера,
	# позитивный вайп по психологическому правилу док), поэтому:
	in_cave = false
	pos_valid = false
	# --- порядок фиксации: сигналы/сейв ДО ng_plus_started, чтобы хук-перезагрузка
	# сцены не перехватил состояние раньше диска ---
	quest_changed.emit()  # HUD-квесты + автосейв из _ready
	save_game()           # явный автосейв: круг не должен «повиснуть» незаписанным
	ng_plus_started.emit()
	return w
