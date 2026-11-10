extends Node
## Глобальное состояние игры: герой, прогресс, квесты, сохранения.

const Classes := preload("res://scripts/classes_data.gd")

signal stats_changed
signal quest_changed
signal toast(text: String)
signal leveled_up(level: int)
signal regen_hp_tick
signal regen_mana_tick

# --- восстановление (B+F): внебойная регенерация + мана мага ---
const COMBAT_HOLD := 6.0        # сколько секунд считаем «в бою» после контакта
const HP_REGEN_EVERY := 4.0     # +1 HP каждые 4 с вне боя
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
		return int(Classes.class_data(class_id).dmg) * (2 if has_sword else 1) + (1 if has_amulet else 0)
	set(_value):
		pass
var herbs := 0
var slime_kills := 0
## Алхимия: материалы с врагов (id -> кол-во, см. MAT_NAMES) и заряды варёных зелий.
var materials := {"suhotsvet": 0, "zhim": 0}
var brewed_potions := 0
## Костры-привалы: id -> true, если уже использован (одноразовые).
var campfires_used := {}
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

func _ready() -> void:
	# Автосебы: редкие, но важные для игрока моменты не должны теряться.
	leveled_up.connect(func(_l: int) -> void: save_game())
	quest_changed.connect(func() -> void: save_game())

func _process(delta: float) -> void:
	combat_t = maxf(0.0, combat_t - delta)
	if combat_t > 0.0 or hp <= 0:
		return  # в бою реген нет — только в тишине
	if hp < max_hp:
		_hp_regen_t += delta
		if _hp_regen_t >= HP_REGEN_EVERY:
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

func add_xp(n: int) -> void:
	xp += n
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = int(round(xp_next * 1.6))  # правка v1.1: рост x1.6 (20->32->51->82)
		max_hp += 2
		heal_full()
		toast.emit("Новый уровень: %d! Максимум HP вырос!" % level)
		leveled_up.emit(level)
	stats_changed.emit()

# --- классы (спринт 2) ---

## Пересчёт макс. HP: класс + 2 за каждый уровень + 4 за амулет.
func recalc_max_hp() -> void:
	max_hp = int(Classes.class_data(class_id).hp) + 2 * (level - 1) + (4 if has_amulet else 0)
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

func to_dict() -> Dictionary:
	return {
		"max_hp": max_hp, "hp": hp, "mana": mana, "level": level, "xp": xp, "xp_next": xp_next,
		"damage": damage, "has_sword": has_sword, "class_id": class_id,
		"herbs": herbs, "slime_kills": slime_kills,
		"elder_quest": elder_quest, "slime_quest": slime_quest,
		"seen_intro": seen_intro,
		"cave_state": cave_state, "has_key": has_key, "has_amulet": has_amulet,
		"door_opened": door_opened,
		"in_cave": in_cave, "seen_cave_intro": seen_cave_intro,
		"seen_boss_intro": seen_boss_intro, "boss_defeated": boss_defeated,
		"materials": materials.duplicate(), "brewed": brewed_potions,
		"campfires_used": campfires_used.duplicate(),
		"px": player_pos.x, "py": player_pos.y, "pos_valid": pos_valid,
	}

func from_dict(d: Dictionary) -> void:
	max_hp = int(d.get("max_hp", 10))
	hp = int(d.get("hp", max_hp))
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	xp_next = int(d.get("xp_next", 20))
	# damage — производный, из справочника классов (legacy-поле сейва игнорируется)
	class_id = String(d.get("class_id", "warrior"))  # старый сейв без класса => воин
	has_sword = bool(d.get("has_sword", false))
	herbs = int(d.get("herbs", 0))
	slime_kills = int(d.get("slime_kills", 0))
	elder_quest = int(d.get("elder_quest", 0))
	slime_quest = int(d.get("slime_quest", 0))
	seen_intro = bool(d.get("seen_intro", false))
	# новые поля: СТАРЫЕ сейвы грузятся через значения по умолчанию
	cave_state = int(d.get("cave_state", 0))
	has_key = bool(d.get("has_key", false))
	has_amulet = bool(d.get("has_amulet", false))
	door_opened = bool(d.get("door_opened", false))
	in_cave = bool(d.get("in_cave", false))
	seen_cave_intro = bool(d.get("seen_cave_intro", false))
	seen_boss_intro = bool(d.get("seen_boss_intro", false))
	if bool(d.get("boss_defeated", false)):
		cave_state = maxi(cave_state, 2)
	# привалы и алхимия: СТАРЫЕ сейвы без этих полей => пустой рюкзак, костры целы
	materials = {"suhotsvet": 0, "zhim": 0}
	var md: Variant = d.get("materials", {})
	if typeof(md) == TYPE_DICTIONARY:
		for mid in materials:
			materials[mid] = clampi(int(md.get(mid, 0)), 0, MAT_CAP)
	brewed_potions = clampi(int(d.get("brewed", 0)), 0, BREWED_CAP)
	var cu: Variant = d.get("campfires_used", {})
	campfires_used = cu.duplicate() if typeof(cu) == TYPE_DICTIONARY else {}
	player_pos = Vector2(float(d.get("px", 0)), float(d.get("py", 0)))
	pos_valid = bool(d.get("pos_valid", false))
	recalc_max_hp()  # класс + уровни + амулет — канон поверх сохранённого max_hp
	recalc_max_mana()
	# мана: старый сейв без поля => полная; всегда в пределах потолка класса
	mana = clampi(int(d.get("mana", max_mana)), 0, max_mana)
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
