extends Node
## Глобальное состояние игры: герой, прогресс, квесты, сохранения.

const Classes := preload("res://scripts/classes_data.gd")
# t7 «Туман открытия» (25.11): модель discovered-поля карты мира; preload без
# class_name — паттерн OW/ClickMove (headless-устойчивость к stale cache).
const FogWar := preload("res://scripts/fog_of_war.gd")

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

# --- привалы и алхимия (дефицит: дроп редкий, костёр одноразовый) ---
## g20a (вердикт 17.11 ~10:00, INVENTORY.md): «рюкзак-карман» стал инвентарём —
## материалы живут стопками по 99 (ячейка сетки с угловым счётчиком, как в
## лавке); прежний лимит переноса 5 отменён вердиктом «заводим сразу».
const MAT_CAP := 99             # размер стопки материала (старый «лимит переноса» 5 отменён g20a)
const BREWED_CAP := 2           # запас варёных зелий (крепких)
const STRONG_POTION_HEAL := 6   # HP за крепкое зелье (обычное травяное — 3)
const MAT_NAMES := {"suhotsvet": "Сухоцвет", "zhim": "Жим",
	"smola": "Смола",  # g13 (Г1.3): «Смола» — материал факела, покупается у Драна
	"hide": "Шкура слизня", "sinew": "Волчья жила",  # g20a: материалы всегдашнего дропа
	"whet": "Точильный камень"}  # g20b (вердикт 17.11 п.4): валюта заточки, частый дроп

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
## g20a: стопки до MAT_CAP; hide/sinew — всегдашний дроп мобов (INVENTORY.md §2).
var materials := {"suhotsvet": 0, "zhim": 0, "smola": 0, "hide": 0, "sinew": 0, "whet": 0}
var brewed_potions := 0
## Факелы (g13/Г1.3). Счётчик-расходник: факел из лавки Драна и факел, сплетённый
## Гриимом, — один предмет ("torch" в GearData.ITEMS), один add_torch() на оба
## пути; «горение в пещере» — глава 2 (G2.1), здесь носка/сейв. Круг обнуляет.
var torches := 0
## Костры-привалы: id -> true, если уже использован (одноразовые).
var campfires_used := {}
## Открытые сундуки (ачивка «Клад» = size): uid вида "chest@<area>:x,y", area —
## village/cave/ashen (D4, PROCGEN_PLAN §6). Старые координатные ключи
## "chest@x,y" (сейвы v1–v3) валидны навсегда, не мигрируются; chest_used() —
## точное сравнение строк, на один сундук живёт ровно одна запись. Переживают перезапуск.
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
## t3 «Мир v1» (сейв v4, аддитивно): активная область героя —
## "village" | "cave" | "ashen" | "worldmap" | "loc_<биом>". Пустая строка —
## «ключа нет» (старый сейв): from_dict выводит зону легаси-цепочкой без потерь.
var area := "village"
var input_locked := false

# --- v2 (фундамент волны «контент»): золото, шестерня, общие флаги ---
## Хранилище здесь; реестр предметов (id -> слот/цена/статы) — scripts/gear_data.gd
## (фича экономики), справочник квестов — scripts/quests_data.gd (фича квестов).
var gold := 0
## Снаряжение: слот ("weapon"/"armor"/"shield"/"relic") -> item id, "" — пусто.
## g20b (вердикт 17.11 «давай оружие, броня + оберег»): третий слот relic.
## t10 (вердикт 25.11 «магу посохи, лучнику луки, воину мечи и щиты»):
## четвёртый слот shield. Сейв-ключ "gear" — словарь: аддитивно, старые
## сейвы получают shield:"" (из gear.duplicate() ключ просто берётся).
var gear := {"weapon": "", "armor": "", "shield": "", "relic": ""}
## t10 (вердикт 25.11): ОДНОРАЗОВОЕ пояснение legacy-гейта (from_dict снял
## чужое — мир прочитает и покажет тост, когда HUD уже слушает; в сейв НЕ
## пишется: после первого снятия слот чист, повторного тоста не будет).
var gear_gate_note := ""

## Выдать накопленное пояснение гейта тостом и погасить ( идемпотентно:
## пустая заметка — молчаливый no-op). Зовёт world.gd после постройки HUD
## (бут-лоад) и после успешной F9-загрузки.
func flush_gear_gate_note() -> void:
	if gear_gate_note != "":
		toast.emit(gear_gate_note)
		gear_gate_note = ""
## Сумка снаряжения (g20b): список id ЭКИПИРУЕМОГО, которым владеет герой
## (включая надетое — слоты gear ссылаются в него же). Предмет уникален,
## стопок нет. Пустой id/чужой id в сумму не попадает (ensure_gear).
var owned_gear: Array = []
## Степень заточки по id оружия (g20b, вердикт п.4): id -> 0..5; шьётся
## к оружию, живёт в сейве, при снятии не теряется.
var sharpen := {}
## t17 «Глубина v2 §1: Аффиксы» (25.11): id предмета -> массив аффиксов
## (0/1/2 шт — обычная/добротная/реликтовая). Пусто/нет ключа = обычная
## (обратная совместимость v4 без миграции). Даёт бонус только НАДЕТАЯ вещь;
## из сумки влияет лишь на цену продажи. Ролл — Loot.affix_roll (shash-канон).
var affixes := {}
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
	# t17 (25.11, DESIGN_DEPTH_V2 §1): аффикс «Тёплая нить» — получение
	# лечения +10% (любой канал: травы, алхимия, казнь, костёр, реген).
	if n > 0:
		n = int(round(float(n) * (1.0 + GearData.affix_sum(self, "mending"))))
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

## Положить факел в руки (g13/Г1.3). Единая точка и для покупки у Драна, и для
## крафта у Гриима: «факел из крафта == факел из лавки» — один предмет ("torch")
## и этот один метод на оба пути (пин _t42).
func add_torch() -> void:
	torches += 1

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
## t10 (вердикт 25.11): МАТРИЦА КАНОНА на входе — экипировка чужого типа
## запрещена ЗДЕСЬ (GearData.can_equip), с штатной причиной в тосте, не молча.
## Отказ возвращает прежний предмет слота, слот не трогается (ни has_sword,
## ни статы). class_id == "" (безкласса, t9) — матрица молчит.
func equip_item(slot: String, item_id: String) -> String:
	if not gear.has(slot):
		push_warning("Неизвестный слот: %s" % slot)
		return ""
	var prev := String(gear[slot])
	if item_id != "":
		var gate: Dictionary = GearData.can_equip(class_id, item_id)
		if not bool(gate.get("ok", true)):
			toast.emit(String(gate.get("reason", "Не твоя рука.")))
			return prev
	gear[slot] = item_id
	if slot == "weapon":
		# M1 (QA): флаг синхронизируется ЖЁСТКО — любой другой id (топор, клинок)
		# обязан гасить has_sword, иначе при очистке слота остаётся «призрачный меч» x2.
		has_sword = (item_id == "sword")
	# t10: мана-потолок от посоха пересчитывается вместе с оружием. t17 (25.11):
	# пересчёт переехал на ВСЕ слоты — аффикс «Глубокий колодец» живёт и на
	# броне/щите/обереге; без посоха/колодца recalc тождественен (идемпотентен).
	recalc_max_mana()
	stats_changed.emit()
	return prev

## g20b: положить экипируемый предмет в сумку (уникально; только реальные
## weapon/armor/relic из реестра). true — предмет добавлен.
func ensure_gear(id: String) -> bool:
	if id == "" or owned_gear.has(id):
		return false
	var sl := String(GearData.item(id).get("slot", ""))
	if sl != "weapon" and sl != "armor" and sl != "relic" and sl != "shield":
		push_warning("ensure_gear: не экипируемый id: %s" % id)
		return false
	owned_gear.append(id)
	quest_changed.emit()  # автосейв: обновленная сумка — часть сейва v4
	return true

## g20b: снять с слота в сумку (владение остаётся — предмет не исчезает).
func unequip_slot(slot: String) -> void:
	if gear.has(slot) and String(gear[slot]) != "":
		equip_item(slot, "")

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

## Пересчёт макс. HP: класс + 2 за каждый уровень + 4 за амулет + 4 за «Благословение» алтаря
## + t20 «Углевое сердце» мета-доски (meta.mb.coal_heart): +4 HP за ранг (кап 3 → +12).
func recalc_max_hp() -> void:
	max_hp = int(Classes.class_data(class_id).hp) + 2 * (level - 1) + (4 if has_amulet else 0) + 4 * int(flags.get("meta.bless", 0)) + mb_value("coal_heart")
	if hp > max_hp:
		hp = max_hp
	stats_changed.emit()

## Пересчёт макс. маны из класса (0 у не-магов) + мана-потолок надетого
## посоха (t10, вердикт 25.11: «магу посохи» — посох даёт урон И ману);
## mana поджимается под потолок.
func recalc_max_mana() -> void:
	var m := int(Classes.class_data(class_id).get("mana", 0)) + GearData.mana_bonus(self)
	# t17 (25.11, DESIGN_DEPTH_V2 §1): аффикс «Глубокий колодец» надетой вещи —
	# потолок маны +15% (round). Пересчёт идёт при экипировке/снятии — канон.
	max_mana = int(round(float(m) * (1.0 + GearData.affix_sum(self, "deepwell"))))
	if mana > max_mana:
		mana = max_mana
	stats_changed.emit()

## Выбор/смена класса: базовые статы пересчитываются, HP полный.
func set_class(id: String) -> void:
	if class_id != "":
		# класс выбирается один раз на забег; смерть обнуляет class_id (t9, 25.11 —
		# вердикт пользователя), поэтому «смена» возможна только как новый герой
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
## Кап CAP-128 на число ключей flags учитывает 14 ключей tal.* по числу
## узлов (12 общих + 2 классовых прока g19) + служебный tal.gift (док в from_dict).

## Ранг узла talents (0..max_of); неизвестный id => max_of=0 => 0.
func tal_rank(id: String) -> int:
	return clampi(_num(flags.get("tal." + id, 0), 0), 0, Talents.max_of(id))

## Сколько очков таланта уже вложено (сумма рангов по всем узлам).
func tal_spent() -> int:
	var s := 0
	for id in Talents.NODES:
		s += tal_rank(String(id))
	return s

## Свободные очки таланта: по одному за каждый уровень выше 1-го минус
## вложенные. g19: + tal.gift — подаренные очки за миграцию proc-рангов
## с доски пепла (вердикт 16.11 22:44: перенос «бесплатный», очко не съедается).
## Gift живёт в семействе tal.* и сгорает на смерти/кругу вместе с рангами.
func tal_points() -> int:
	return maxi(level - 1 + _num(flags.get("tal.gift", 0), 0) - tal_spent(), 0)

## Потратить очко в узел id. false (со звуком ui_deny) — неизвестный id, узел
## прокачан до cap, чужой классовый прок (g19: воину не виден и недоступен
## прок лучника) или нет свободных очков. Успех — +1 ранг, ui_confirm и
## quest_changed (тот же канал автосейва, что квесты/ачивки).
func try_spend_talent(id: String) -> bool:
	if not Talents.NODES.has(id) or tal_rank(id) >= Talents.max_of(id) or tal_points() <= 0 \
			or (Talents.class_of(id) != "" and Talents.class_of(id) != class_id):
		GameAudio.sfx("ui_deny")
		return false
	flags["tal." + id] = tal_rank(id) + 1
	quest_changed.emit()
	GameAudio.sfx("ui_confirm")
	return true

## g19 (вердикт 16.11 22:44): миграция proc-рангов с доски пепла в таланты.
## Старые сейвы могли купить «Клык вепря»/«Скрученную стрелу» за пепел
## (meta.mb.<id>, вечный слой). При загрузке: класс совпал — равный ранг
## выдаётся в tal.<id> бесплатно, а в tal.gift ложится компенсация очков
## (иначе подаренный ранг молча съел бы будущие очки); класс не совпал —
## токен просто стирается (перенос чужого прока не имеет смысла). Токен
## чистится всегда => операция идемпотентна (из вечного слоя флаг исчезает,
## gift остаётся до конца круга как у всех tal.*). true — хоть один токен
## найден и сейв надо зафиксировать (паттерн run_seed-миграции ниже).
func _migrate_proc_tokens() -> bool:
	var touched := false
	for pid in ["boar_fang", "twisted_arrow"]:
		var pid_s := String(pid)  # цикл по untyped Array: pid — Variant, явное String
		var key: String = "meta.mb." + pid_s
		var rank := clampi(_num(flags.get(key, 0), 0), 0, Talents.max_of(pid_s))
		if not flags.has(key):
			continue
		flags.erase(key)
		touched = true
		if rank <= 0:
			continue
		if Talents.class_of(pid_s) == class_id:
			flags["tal." + pid_s] = mini(tal_rank(pid_s) + rank, Talents.max_of(pid_s))
			flags["tal.gift"] = _num(flags.get("tal.gift", 0), 0) + rank
		# чужой класс: токен стёрт, ранг не переносится
	return touched

func to_dict() -> Dictionary:
	return {
		"max_hp": max_hp, "hp": hp, "mana": mana, "level": level, "xp": xp, "xp_next": xp_next,
		"damage": damage, "has_sword": has_sword, "class_id": class_id,
		# g20a (вердикт 17.11 ~10:00): ВЕТКИ ПРЕДМЕТОВ переехали в inv — сейв v4
		# (см. from_dict: v≤3 читаются через миграцию без потерь). has_key/
		# has_amulet остались top-level: это квестовые флаги сюжета, а не
		# стопки; сетка инвентаря показывает их как ячейки-единицы.
		"slime_kills": slime_kills,
		"slime_kills_circle": slime_kills_circle,
		"elder_quest": elder_quest, "slime_quest": slime_quest,
		"seen_intro": seen_intro,
		"cave_state": cave_state, "has_key": has_key, "has_amulet": has_amulet,
		"door_opened": door_opened,
		"in_cave": in_cave, "seen_cave_intro": seen_cave_intro,
		"seen_boss_intro": seen_boss_intro, "boss_defeated": boss_defeated,
		"inv": {
			"herb": herbs, "brewed": brewed_potions, "torch": torches,
			"mat": materials.duplicate(),
			# g20b: сумка снаряжения и степени заточки — внутри того же v4-
			# контейнера (аддитивно: старые v4 без этих ключей грузятся пустыми)
			"bag": owned_gear.duplicate(), "sharpen": sharpen.duplicate(),
			# t17 (25.11): аффиксы — аддитивно к тому же v4: отсутствие ключа
			# у старой записи = обычные предметы, миграции нет.
			"affixes": affixes.duplicate(true),
		},
		"campfires_used": campfires_used.duplicate(),
		"chests_used": chests_used.duplicate(),
		"v": 4, "gold": gold, "gear": gear.duplicate(), "flags": flags.duplicate(),
		"px": player_pos.x, "py": player_pos.y, "pos_valid": pos_valid,
		"area": area,  # t3 «Мир v1»: явный ключ зоны (аддитивно к v4)
		"run_seed": run_seed,
		# t7 «Туман открытия» (25.11): discovered-поле карты мира, base64 720
		# байт — аддитивно к v4. Пустая строка = туман выключен (легаси-сейв,
		# см. from_dict); в остальном старые сейвы грузятся без потерь.
		"wm_fog": wm_fog.to_b64() if wm_fog != null else "",
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
	# g20a: травы — часть инвентарного блока inv ниже (сейвы v≤3 мигрируются там же)
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
	# --- g20a (вердикт 17.11 ~10:00): инвентарь сейва v4 ---
	# v4 несёт ветки предметов в словаре inv. Сейвы v≤3 (herbs/materials/
	# brewed/torches top-level) читаются тем же резолвером напрямую — это и
	# есть миграция «в сетку без потерь»: каждый старый ключ попадает в своё
	# поле, а следующий save_game() уже пишет v4. Ключей g19 (tal.*, meta.mb.*)
	# блок не касается: вечный слой в flags живёт отдельным ключом сейва.
	var inv: Variant = d.get("inv", {})
	var inv_d: Dictionary = inv if typeof(inv) == TYPE_DICTIONARY else {}
	var has_inv: bool = not inv_d.is_empty()
	var herb_v: Variant = inv_d.get("herb", 0) if has_inv else d.get("herbs", 0)
	# травы исторически были без капа; стопка сетки — MAT_CAP, излишек старого
	# сейва клампится (99 трав в забеге нереалистичны; потери нулевые на практике)
	herbs = clampi(_num(herb_v, 0), 0, MAT_CAP)
	# привалы и алхимия: СТАРЫЕ сейвы без этих полей => пустой рюкзак, костры целы
	materials = {"suhotsvet": 0, "zhim": 0, "smola": 0, "hide": 0, "sinew": 0, "whet": 0}
	# v4: материалы в inv.mat; v≤3: top-level "materials" (hide/sinew там
	# заведомо нет — нули)
	var md: Variant = inv_d.get("mat", {}) if has_inv else d.get("materials", {})
	if typeof(md) == TYPE_DICTIONARY:
		for mid in materials:
			materials[mid] = clampi(_num((md as Dictionary).get(mid, 0), 0), 0, MAT_CAP)
	var br_v: Variant = inv_d.get("brewed", 0) if has_inv else d.get("brewed", 0)
	brewed_potions = clampi(_num(br_v, 0), 0, BREWED_CAP)
	var torch_v: Variant = inv_d.get("torch", 0) if has_inv else d.get("torches", 0)
	torches = clampi(_num(torch_v, 0), 0, MAT_CAP)  # старый сейв без поля — ноль факелов
	# --- g20b: сумка снаряжения и заточка (аддитивно к v4; v≤3 — пусто,
	# надетое из gear добавится ниже, старый амулет — из has_amulet) ---
	owned_gear = []
	var bag_v: Variant = inv_d.get("bag", [])
	if typeof(bag_v) == TYPE_ARRAY:
		for gid in bag_v:
			if typeof(gid) == TYPE_STRING and not owned_gear.has(String(gid)) \
					and owned_gear.size() < 12:  # physically: 6 free bag cells + slots
				var gsl := String(GearData.item(String(gid)).get("slot", ""))
				if gsl == "weapon" or gsl == "armor" or gsl == "relic" or gsl == "shield":
					owned_gear.append(String(gid))
	# ensure_gear НЕ используем: он эмитит автосейв на каждый предмет, лоад
	# обязан быть без сайв-побочки (паттерн всех полей from_dict).
	sharpen = {}
	var shv: Variant = inv_d.get("sharpen", {})
	if typeof(shv) == TYPE_DICTIONARY:
		for wid in shv:
			var wids := String(wid)
			if String(GearData.item(wids).get("slot", "")) == "weapon":
				sharpen[wids] = clampi(_num(shv[wid], 0), 0, GearData.SHARPEN_MAX)
	# t17 (25.11): аффиксы — аддитивное поле того же v4-контейнера (старые
	# сейвы без ключа = всё обычное). Санитизация: ключ обязан лежать в
	# сумке, значение — массив известных id без повторов, кап 2 (иначе
	# «реликтовой» станет любая строка-мусор).
	affixes = {}
	var afv: Variant = inv_d.get("affixes", {})
	if typeof(afv) == TYPE_DICTIONARY:
		for aid in afv:
			var aids := String(aid)
			var arv: Variant = afv[aid]
			if typeof(arv) != TYPE_ARRAY or not owned_gear.has(aids):
				continue
			var clean: Array = []
			for el in arv:
				var eid := String(el)
				if GearData.AFFIXES.has(eid) and not clean.has(eid) and clean.size() < 2:
					clean.append(eid)
			if not clean.is_empty():
				affixes[aids] = clean
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
	gear = {"weapon": "", "armor": "", "shield": "", "relic": ""}
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
	# t10 (вердикт пользователя 25.11, матрица CLASS_WEAPONS): LEGACY-ГЕЙТ —
	# старые сейвы не знали, что «магу посохи, лучнику луки, воину мечи+щиты».
	# При загрузке предмет чужого класса СНИМАЕТСЯ с слота в сумку (инвентарь
	# сохраняется: «предмет — товар будущего круга/перерождения», рынок живёт)
	# с ОДНОРАЗОВЫМ тостом-пояснением (gear_gate_note — одноразово, потому что
	# F9 без гейта больше не повторит: после первого снятия слот чист).
	# has_sword пересинхронизируется ПОСЛЕ снятия: LEGACY_SWORD_MULT остаётся
	# только за честным «пустой слот + флаг» (старый меч воина не трогается —
	# warrior/sword матрицей разрешён).
	gear_gate_note = ""
	var stripped: Array = []
	for gslot in ["weapon", "shield"]:
		var ggid := String(gear[gslot])
		if ggid == "":
			continue
		if not bool(GearData.can_equip(class_id, ggid).get("ok", true)):
			gear[gslot] = ""
			if not owned_gear.has(ggid) and owned_gear.size() < 12:
				owned_gear.append(ggid)
			stripped.append(String(GearData.item(ggid).get("name", ggid)))
	has_sword = String(gear["weapon"]) == "sword"
	if not stripped.is_empty():
		gear_gate_note = "Привычка прежних дней: %s снят — не твоя рука. В сумке." % ", ".join(stripped)
	# g20b: инвариант сумки — НАДЕТОЕ всегда во владении. Старые сейвы (v≤3)
	# не знали bag: меч из лавки/сундука и ВЕЧНЫЙ Амулет Леса (has_amulet —
	# сюжетный флаг, переживает забег) доезжают в сумку миграцией при лоаде.
	for slot in gear:
		var eid := String(gear[slot])
		if eid != "" and not owned_gear.has(eid) \
				and String(GearData.item(eid).get("slot", "")) == slot:
			owned_gear.append(eid)
	if has_amulet and not owned_gear.has("amulet") and owned_gear.size() < 12:
		owned_gear.append("amulet")
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
	# t3 «Мир v1»: зона резюме при загрузке — единым правилом
	# resolve_resume_zone (ключ area из словаря; поля in_cave/player_pos/
	# pos_valid уже проставлены выше из того же словаря). Миграция без
	# потерь; следующий save_game() пишет ключ.
	area = resolve_resume_zone(_str(d.get("area", ""), ""))
	# --- v3: сид забега (PROCGEN §2); сейвы v2 без поля => страж −1, живой
	# сид родит миграция в load_game() (не здесь: from_dict чист) ---
	run_seed = _num(d.get("run_seed", -1), -1)
	# t7 «Туман открытия» (25.11): аддитивный ключ v4. LEGASI (ключа нет или
	# пусто) => wm_fog == null — туман ВЫКЛЮЧЕН: прежний сейв играет открытой
	# картой, без регрессии пройденного опыта (вердикт-тюнинг капитана). Новое
	# состояние всегда привозит непустой ключ; new game/смерть/NG+ засевают
	# туман через var-инициализатор и _wipe_circle.
	var fog_b64 := _str(d.get("wm_fog", ""), "")
	wm_fog = FogWar.new() if fog_b64 != "" else null
	if wm_fog != null:
		wm_fog.from_b64(fog_b64)
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

## t3 «Мир v1» — ЕДИНАЯ резолюция зоны резюме (из from_dict и из мира).
## Доказательства до-t3: флаг пещеры и у-этап героя при ВАЛИДНОЙ позиции
## (этажи зон кратны 4800, см. OpenWorld.LOC_OFFSET_Y). Автосейвы достижений
## (Achv.grant_ash) и xp пишут сейв посреди фазы: зона живая, позиция ещё не
## ставилась (pos_valid=false) — до t3 такой сейв резюмился «к входу
## деревни»; паритет сохраняем: нет позиции — доказательств нет, деревня.
## Ключ area (аддитивная v4-надстройка) УТОЧНЯЕТ вывод, только когда позиция
## валидна и физика сказала «деревня» (этажные зоны физика читает сама).
func resolve_resume_zone(key: String = "") -> String:
	# t19 (25.11): ход — этаж 48000, выше всех y-полос; ключ зоны первичен
	# (легаси-полосы ниже не затронуты — прежние входы резолвятся 1:1).
	if key.begins_with("mini_"):
		return key
	var phys := "village"
	if in_cave:
		phys = "cave"
	elif pos_valid:
		var py := player_pos.y
		if py >= 43200.0:
			phys = "loc_dungeon"
		elif py >= 38400.0:
			phys = "loc_castle"
		elif py >= 33600.0:
			phys = "loc_forest"
		elif py >= 28800.0:
			phys = "loc_steppe"
		elif py >= 24000.0:
			phys = "loc_desert"
		elif py >= 19200.0:
			phys = "loc_snow"
		elif py >= 14400.0:
			phys = "worldmap"
		elif py > 9600.0:
			phys = "ashen"
	if pos_valid and phys == "village" and key != "":
		return key
	return phys

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
	# g19 (вердикт 16.11 22:44): миграция proc-токенов доски в таланты — ДО
	# любой записи, найденное сразу фиксируется на диске (тот же паттерн, что
	# run_seed ниже: миграция совершается ровно один раз).
	if _migrate_proc_tokens():
		save_game()
	# PROCGEN §2 миграция: сейв без run_seed (v2) или с стражом −1 — сид забега
	# рождается РОВНО ОДИН РАЗ и сразу фиксируется на диске, чтобы рестарты его
	# не перегенерили. Глобальный RNG здесь допустим: это рождение сида, а не
	# генерация (D3 запрещает randi() только внутри генератора).
	if run_seed < 0:
		run_seed = randi()
		save_game()
	return true

# --- NG+ «Круги Пепла» (RETENTION_NG_PLUS §1): ОДНА точка истины формул ---
## Кап волны: дальше цифры не растут — круги на кап-значениях играются сколько
## угодно (удержание, а не бесконечная спираль).
const NG_WAVE_CAP := 5

## Сид текущего забега (CONTRACT_PROCGEN §2): детерминированный корень
## генератора карт — ProcGen.seed_zone(run_seed, зона, волна). −1 — страж
## legacy: свежая игра до первого вайпа либо сейв без поля; при лоаде −1
## рождается randi() РОВНО ОДИН РАЗ и сразу пишется на диск (миграция в
## load_game), а вайп круга/смерти перевыбрасывает его в _wipe_circle().
var run_seed := -1
## t7 «Туман открытия» (вердикт 25.11): discovered-поле карты мира (96x60).
## Живёт в сейве аддитивным ключом v4 "wm_fog" (base64, 720 байт); сброс —
## только общий вайп круга (_wipe_circle), легаси-сейв без ключа = туман с нуля
## (первая clearing засевается при входе на карту, остальное — исследование).
var wm_fog = FogWar.new()

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

## t39 «баланс по t38»: гейт тяжёлых(brute) по волнам. Профиль глубины остаётся
## полосами пещеры (bands в proc_profiles.json — золотой тест), но ранг brute
## режется по волне забега: w≤2 — только т1, w3 — до т2, w4+ — до т3.
## Смысл: скачок сложности волны 1→2 (t1→t2 = +50% HP и +100% урона) не должен
## вылезать за ×2 относительной угрозы (t38: было ×3.7).
func brute_max_tier(w: int) -> int:
	if w <= 2:
		return 1
	if w == 3:
		return 2
	return 3

## Множитель золота (§1.3): +40% за круг, w5 → ×3.0. Применяется к ИТОГУ ролла.
func ng_gold_mult(w: int) -> float:
	return 1.0 + 0.4 * float(w)

# --- t20 P0-3: мета-прогресс смерти (пепел/благословение волхвы) ---
##
## t70 (17.11, вердикт пользователя 16:14 «заработанное полностью исчезает»):
## заработанный пепел переживает смерть ПОЛНОСТЬЮ. Rs.earned инкассируется 1:1 —
## ни один процент не догорает ни при смерти (start_new_run), ни при отказе от
## круга («Новая игра», start_fresh_game): начисление уже произошло в Ash.add,
## поэтому баланс при конце забега не уменьшается вовсе. Прежнее правило
## keep = floor(earned × 0.65) с вычитанием из баланса УБРАНО вместе с константами
## ASH_KEEP_RATE/MIN/MAX — чтобы не вернули молча, qa_mb R4 пинит их отсутствие
## и ровно +E на обоих путях. Вечный meta.ash (ачивки прошлых кругов, алтарь,
## NG+) не горел и не горит (§0 «мета-слой вечен»). Нажитое забегом — золото,
## вещи, травы, факелы — сгорает по-прежнему: это другой контур (§6, t62/t63).

## Благословение волхвы: +2% урона за КАЖДУЮ смерть текущего круга, кап — 10
## смертей (+20%). Счётчик meta.vd: +1 в start_new_run(), сброс 0 в
## start_ng_plus() (новый круг — благословение выгорает, волхва благословляет заново).
## Не путать с meta.bless — «Благословение» алтаря Пепла (+4 HP/ранг, t-ранняя система).
const BLESS_PER_DEATH := 0.02
const BLESS_CAP_DEATHS := 10

## Число учтённых смертей круга (до капа) — множитель урона hero.
func volkhv_stacks() -> int:
	return clampi(_num(flags.get("meta.vd", 0), 0), 0, BLESS_CAP_DEATHS)

## Множитель урона героя от благословения волхвы (1.0 .. 1.0+0.02*10).
func volkhv_bless_mult() -> float:
	return 1.0 + BLESS_PER_DEATH * float(volkhv_stacks())

## Ранг таланта мета-доски пепла (0..3); ключ "meta.mb.<id>", вайп НЕ трогает
## (мета-слой вечен). Единственная точка чтения для всех hooks (game_state/player/loot).
func mb_rank(id: String) -> int:
	return clampi(_num(flags.get("meta.mb." + id, 0), 0), 0, 3)

## Числовой эффект ранга: 0 / vals[0] / vals[1] / vals[2] по таблице MetaBoard.
func mb_value(id: String) -> int:
	return MetaBoard.value_at_rank(mb_rank(id), id)

## Начать новый круг (§1.1–1.2). P1: вызывается программно (триггер в диалоге
## Старейшины — P2, не здесь). Переносится: золото, шестерня, класс/уровни/статы,
## амулет, achv.*, meta.*, daily.*, ng.*; сбрасывается мир и сюжет (§1.2).
## На кап-волне номер не растёт, но мир сбрасывается — круги повторяемы.
## Возвращает номер круга после вызова.
func start_ng_plus() -> int:
	var w := mini(ng_wave() + 1, NG_WAVE_CAP)
	flags["ng.wave"] = w
	# t20 P0-3: «Благословение волхвы» считается по смертям ТЕКУЩЕГО круга —
	# новый круг обнуляет счётчик (волхва благословляет заново с чистого листа).
	flags["meta.vd"] = 0
	# g17 (TALENT_PROCS): NG+ стирал таланты-проки точечно из вечного meta.mb.*.
	# g19 (вердикт 16.11 22:44): проки переехали в tal.* (Talents, классовые
	# узлы) — их выметает общий _wipe_circle ниже вместе с ветвями, как и всё
	# живое. Цикл по proc_ids() оставлен стопором: таблица доски пуста — проход
	# холостой; вернутся proc-строки — снова станут чиститься точечно.
	for pid in MetaBoard.proc_ids():
		flags.erase(MetaBoard.KEY_PREFIX + String(pid))
	# Вайп-набор — общий хелпер _wipe_circle() (CONTRACT_RUNLOOP §1.3). Герой
	# (уровень/опыт/шмот) НЕ обнуляется — «ушёл домой с триумфом» (R6-антибаг:
	# обнуление героя принадлежит только смертельному входу start_new_run()).
	_wipe_circle()
	# --- порядок фиксации: сигналы/сейв ДО ng_plus_started, чтобы хук-перезагрузка
	# сцены не перехватил состояние раньше диска ---
	quest_changed.emit()  # HUD-квесты + автосейв из _ready
	save_game()           # явный автосейв: круг не должен «повиснуть» незаписанным
	ng_plus_started.emit()
	return w

## Общий «вайп круга» (CONTRACT_RUNLOOP §1.3): дословный исходник вайп-блока
## start_ng_plus() без семантических изменений, вызывают оба входа — победный
## (старт выше: ng.wave+1 там, герой переносится) и смертельный
## start_new_run() (волну НЕ трогаем, героя обнуляет вызывающий).
## Здесь НЕ трогаются: ng.wave, герой (уровень/опыт/шмот/золото сверх «Кошелька»),
## вечный слой ach.*/meta.*/daily.*/hint.* (смерть переживает всё — §0).
func _wipe_circle() -> void:
	# Новый забег — новый сид карт (PROCGEN §2; закреплённое решение: randi()
	# СРАЗУ здесь, а не «world родит сид при первом обращении к seam при −1»).
	# Глобальный RNG вне генератора — D3 не нарушается: seed_zone получит
	# уже готовый явный сид.
	run_seed = randi()
	# t7 «Туман открытия» (25.11): новый круг — новая карта (сид выше) и новый
	# туман: discovered-поле с нуля, clearing у арки мир засеет при входе.
	wm_fog = FogWar.new()
	# --- что сбрасывается (инверсия таблицы переноса §1.2) ---
	# «Травы для старейшины» — однократный на жизнь сейва (задача «Квесты:
	# однократность + маркеры»): сдача помечена вечно в meta.q_elder_done
	# (ставит QuestsData.sync_story_permanence по quest_changed). Мета-слой
	# вайп переживает (§0), поэтому круг стартует ЗАКРЫТЫМ: world.talk("elder")
	# никогда больше не увидит стадию 0 — повторные выдача и награда исключены.
	# Метки нет (квест не сдавался или легаси-сейв до правки) — обычный сброс.
	elder_quest = 2 if int(flags.get("meta.q_elder_done", 0)) == 1 else 0
	slime_quest = 0
	cave_state = 0  # boss_defeated — производный (var-обёртка), обнулится сам
	has_key = false
	door_opened = false
	chests_used = []
	campfires_used = {}
	materials = {"suhotsvet": 0, "zhim": 0, "smola": 0, "hide": 0, "sinew": 0, "whet": 0}  # структура сохраняем: add_material сверяет has()
	brewed_potions = 0
	torches = 0  # g13: факелы — нажитое круга, сгорает вместе с кругом (как травы)
	# травы — подвальный инвентарь деревенского круга («Сухоцвет впрок»
	# перепроходит каждый круг, carry-over тривиализировал бы квест);
	# счётчик убийств круга — парный ему для «Зачистки леса».
	herbs = 0
	slime_kills_circle = 0
	# алтарный «Кошелёк» (meta.purse, кап 2): +50 золота за ранг к старту круга.
	gold += 50 * int(flags.get("meta.purse", 0))
	# t20 «Первые угли» мета-доски (meta.mb.first_coal): стартовое золото забега
	# +15/+30/+50 за ранг. Рядом с «Кошельком»: R3 qa_run (gold == 50×purse)
	# остаётся тождеством при ранге 0 (значение 0).
	gold += mb_value("first_coal")
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
		# t20: rs.* — статистика забега (время/киллы/заработанный пепло/зона/
		# убийца) для экрана смерти; живёт ровно один забег, стирается здесь же.
		if ks.begins_with("q.") or ks.begins_with("ashen.") or ks.begins_with("ng.boss_") or ks.begins_with("tal.") or ks.begins_with("rs."):
			wipe_keys.append(k)
	for k in wipe_keys:
		flags.erase(k)
	# мир пересобирается хуком владельца сцены; точка входа — деревня (не пещера,
	# позитивный вайп по психологическому правилу док), поэтому:
	in_cave = false
	pos_valid = false
	area = "village"  # t3 «Мир v1»: новый забег начинается в деревне (тот же сброс)

## Смерть = конец забега (CONTRACT_RUNLOOP §1.1–1.5): перезапуск ЭТОГО ЖЕ этажа —
## вайп мира как у победы, но волна (сложность) НЕ растёт и герой обнуляется
## с нуля. Мета-слой вечен: ach.* (вкл. счётчики n.*), meta.*, daily.*
## (смерть не перематывает дневные — R7), hint.* и Амулет Леса.
## t9 (25.11, ВЕРДИКТ ПОЛЬЗОВАТЕЛЯ «после смерти нельзя выбрать класс»): класс
## больше НЕ вечен — смерть обнуляет class_id, мир пересобирается с модалкой
## «Создание героя» (гейт world.gd по class_id == ""). Прежний канон «класс вечен»
## (CONTRACT_RUNLOOP §1.2 до правки, qa_c1 «класс вечен (воин)») перепинен
## инверсией. Амулет Леса — вечен и был, и есть (вердикт про него не говорил).
## Фиксация — законом start_ng_plus (§1.7); мир пересобирает существующий хук
## ng_plus_started (world.gd), нового сигнала не вводим (§1.6).
func start_new_run() -> void:
	# 1) Учёт смерти ДО вайпа (§1.5): вечный счётчик ach.n.deaths + ачивки
	# «Угас и вспыхнул» (>=5) / «Неугасимый» (>=15) (achv.gd::on_death, ADDENDUM 1.0).
	Achv.on_death()
	# 1a) t70 (17.11): заработанный пепел НЕ догорает. Весь rs.earned уже лежит в
	# балансе (Ash.add начислил его в момент заработка), поэтому при смерти баланс
	# не уменьшается: «заработанное сохраняется полностью» (вердикт 16:14).
	# Вычитание keep = floor(earned × 0.65) убрано; счётчик сотрёт _wipe_circle() ниже.
	# 1b) t20 P0-3: «Благословение волхвы» — смерть текущего круга засчитывается
	# сюда же; новый забег стартует уже с множителем урона (player.dmg_vs).
	flags["meta.vd"] = _num(flags.get("meta.vd", 0), 0) + 1
	# 2) Всё нажитое в забеге сгорает. gold = 0 ДО вайпа: «Кошелёк» внутри
	# _wipe_circle положит сверху ровно 50 × meta.purse (R3: золото == 50×purse,
	# а не «остаток + надбавка» как у победного входа).
	gold = 0
	_wipe_circle()
	# 3) Герой обнулён (§1.2, R3) — канонические поля этого файла: уровень/опыт
	# к дефолтам свежей игры (var-инициализаторы выше, дефолт from_dict),
	# шмот — стартовый по GearData: пустые слоты («голый» герой, x1 без брони;
	# has_sword=false — как fresh-сейв, зеркало gear.weapon из from_dict).
	level = 1
	xp = 0
	xp_next = 20
	gear = {"weapon": "", "armor": "", "shield": "", "relic": ""}
	has_sword = false
	gear_gate_note = ""  # t10: у нового круга чужих снятий не было
	# g20b: нажитое в забеге сгорает целиком — сумка и заточка тоже (вечный
	# Амулет Леса вернётся миграцией has_amulet при следующем лоаде).
	owned_gear = []
	sharpen = {}
	affixes = {}  # t17: аффиксы — часть нажитого, сгорают вместе с сумкой
	# t9 (25.11, ВЕРДИКТ ПОЛЬЗОВАТЕЛЯ «после смерти нельзя выбрать класс»): класс
	# не вечен — смерть стирает героя до «безкласса», как свежая игра ДО выбора:
	# world.gd при сборке нового мира увидит class_id == "" и покажет штатную
	# модалку «Создание героя» (путь fresh-игры, доказанный ветками Ф1-C/Ф2 реестра
	# diag-fx2). Обнуление ДО recalc_* — новый забег входит с базой «безкласса»
	# (фолбэк class_data("") == воин), ровно как fresh-сейв.
	class_id = ""
	# Производные статы — по канону пересчёта: вечные амулет (has_amulet) и
	# «Благословение» алтаря (meta.bless) остаются в силе на 1-м уровне.
	recalc_max_hp()
	recalc_max_mana()
	heal_full()  # героя зовут с hp == 0 — в новый забег он входит живым
	# 4) Порядок фиксации — закон start_ng_plus (§1.7).
	quest_changed.emit()
	save_game()
	ng_plus_started.emit()

## c37 «Новая игра» (P0 «нет выхода из залипшего забега»): конец круга решением
## игрока, а не смертью. Экономика — канон смерти (§4 pet-keep/ash-purse):
## пепел НЕ догорает (t70, 17.11: заработанное инкассируется 100%, как при смерти),
## gold = 0, общий вайп _wipe_circle(), герой обнуляется (§1.2/R3 —
## как в start_new_run). ОТЛИЧИЯ сознательные: НЕ плодятся счётчики смерти
## (ни Achv.on_death, ни meta.vd — отказ от забега не смерть; иначе «отказ»
## стал бы фармом «Благословения волхвы») и НЕ растёт ng.wave. Вечный слой
## (§0/§4: ach.*/meta.*/daily.*/hint.*, Амулет Леса, баланс пепла) — жив.
## class_id = "" — новая игра значит нового героя: на старте следующего мира
## выбор класса появится сам (world.gd гейтит по class_id == "").
## save_game() НЕ зовём: вызывающий (меню) удаляет файл сейва и перезагружает
## сцену — новый мир строится чистым из этой памяти, пустого диска и модалки.
func start_fresh_game() -> void:
	# t70 (17.11): как при смерти — заработанное не догорает, баланс цел.
	gold = 0
	_wipe_circle()
	level = 1
	xp = 0
	xp_next = 20
	gear = {"weapon": "", "armor": "", "shield": "", "relic": ""}
	has_sword = false
	gear_gate_note = ""  # t10: свежий круг NG+ — заметок гейта не копим
	owned_gear = []   # g20b: та же логика, что в start_new_run
	sharpen = {}
	affixes = {}  # t17: и аффиксы — тот же канон «нажитое сгорает»
	class_id = ""
	recalc_max_hp()
	recalc_max_mana()
	heal_full()
