class_name GearData
extends RefCounted
## Реестр предметов экономики: лавка кузнеца Гриима, урон/броня от снаряжения,
## таблицы лута мобов и сундуков. Данные здесь — канон; GameState (сейв v2)
## хранит только золото, gear-слоты и флаги.
## Урон остаётся производным (как в game_state.gd): класс x оружие + амулет +1.
## Legacy-флаг has_sword живёт в синхроне (см. equip_item): при пустом слоте
## оружия он считается старым железным мечом (x2) — старые сейвы и «меч из
## сундука» (interactable.gd пишет только флаг) не проседают по урону.

## id -> данные: name, slot ("weapon"/"armor"), price (золото, покупка), desc,
## dmg_mult (множитель урона для оружия) или armor_bonus (единиц урона мимо брони).
const ITEMS := {
	"sword": {
		"name": "Железный меч", "slot": "weapon", "price": 80,
		"desc": "Стандарт морхеймской дружины. Верный, но тяжёлый. Урон x2.",
		"dmg_mult": 2.0,
	},
	"axe": {
		"name": "Боевой топор", "slot": "weapon", "price": 160,
		"desc": "Медленнее меча в руках, зато бьёт в два с половиной раза больнее. Урон x2.5.",
		"dmg_mult": 2.5,
	},
	"rune_blade": {
		"name": "Клинок рун", "slot": "weapon", "price": 320,
		"desc": "Руны помнят кузню, которой в лесу давно нет. Урон x3.",
		"dmg_mult": 3.0,
	},
	"leather": {
		"name": "Кожаный доспех", "slot": "armor", "price": 60,
		"desc": "Дублёная кожа: съедает 1 единицу урона из каждого удара.",
		"armor_bonus": 1,
	},
	"chain": {
		"name": "Кольчуга", "slot": "armor", "price": 180,
		"desc": "Тяжёлое кольцо: съедает 2 единицы урона, в жару тяжела, как болото.",
		"armor_bonus": 2,
	},
}
## Стартовый набор лавки Гриима (порядок витрины).
const SHOP_STOCK := ["sword", "axe", "rune_blade", "leather", "chain"]
## Legacy-множитель меча из старой формулы урона (x2). Применяется, только
## когда слот weapon пуст, а has_sword == true.
const LEGACY_SWORD_MULT := 2.0
## Продажа — половина цены покупки (вниз, но не дешевле 1).
const SELL_DIV := 2

## Таблицы лута: kind моба -> список дропа (ролл на каждую строку).
## Строка: {"gold": [min, max], "chance": float} или
## {"item": id, "chance": float, "qty": int}; special-id предметов:
## "herb" (трава) и "potion" (заряд крепкого зелья) — свободных слотов
## инвентаря в игре нет, снаряжение покупается, а не падает с мобов.
const LOOT := {
	"slime": [
		{"gold": [2, 5], "chance": 0.85},
		{"item": "herb", "chance": 0.12, "qty": 1},
	],
	# золото брюта по ярусам (ECONOMY_BALANCE, вердикт 3): тир 1 слабее,
	# тир 3 жирнее — фарм глубоких ярусов перестанет быть выгодным в час.
	"brute": [
		{"gold": [6, 9], "chance": 0.9},
		{"item": "potion", "chance": 0.12, "qty": 1},
	],
	"brute_t2": [
		{"gold": [8, 12], "chance": 0.9},
		{"item": "potion", "chance": 0.12, "qty": 1},
	],
	"brute_t3": [
		{"gold": [10, 15], "chance": 0.9},
		{"item": "potion", "chance": 0.12, "qty": 1},
	],
	"boss": [
		{"gold": [25, 40], "chance": 1.0},
		{"item": "potion", "chance": 1.0, "qty": 1},
	],
	# новые архетипы: лучник сытее гнилодына (дальний бой рискует),
	# тенеплёт жирнее всех (эфир — самый опасный), мглокрыс — мелочь на 1 хит.
	"swarmling": [
		{"gold": [1, 3], "chance": 0.8},
		{"item": "herb", "chance": 0.08, "qty": 1},
	],
	"archer": [
		{"gold": [6, 11], "chance": 0.8},
		{"item": "herb", "chance": 0.15, "qty": 1},
	],
	"wraith": [
		{"gold": [10, 18], "chance": 0.9},
		{"item": "potion", "chance": 0.15, "qty": 1},
	],
}

# --- доступ к реестру ---

static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {})

static func has_item(id: String) -> bool:
	return ITEMS.has(id)

## Цена покупки в золоте; 0 — неизвестный id (такое не продаётся).
static func price(id: String) -> int:
	return int(item(id).get("price", 0))

## Цена продажи: половина покупки; 0 — неизвестный id.
static func sell_price(id: String) -> int:
	var p := price(id)
	if p <= 0:
		return 0
	return maxi(1, p / SELL_DIV)

# --- производные статы (параметр gs — GameState; null считается «голым» героем) ---

## Надетый item id в слоте ("weapon"/"armor"); "" — слот пуст или gs нет.
static func equipped_id(gs: Object, slot: String) -> String:
	if gs == null:
		return ""
	var gd: Variant = gs.get("gear")
	if typeof(gd) != TYPE_DICTIONARY:
		return ""
	return String(gd.get(slot, ""))

## Множитель урона надетого оружия. Пустой слот + legacy has_sword => x2
## (старый сейв или «меч из сундука», который писал только флаг).
static func weapon_mult(gs: Object) -> float:
	var wid := equipped_id(gs, "weapon")
	if wid != "":
		var it := item(wid)
		if String(it.get("slot", "")) == "weapon":
			return float(it.get("dmg_mult", 1.0))
		return 1.0  # надет «не-weapon» id — не множим, но и не роняем героя
	if gs != null and bool(gs.get("has_sword")):
		return LEGACY_SWORD_MULT
	return 1.0

## Броня в единицах урона из надетого armor-предмета; 0 — без брони.
static func armor_bonus(gs: Object) -> int:
	var it := item(equipped_id(gs, "armor"))
	if String(it.get("slot", "")) != "armor":
		return 0
	return int(it.get("armor_bonus", 0))

## Урон после брони (для точки получения урона): любой ненулевой удар бьёт
## минимум на 1 (иначе кожа делала слаймов безвредными — дыра баланса).
static func absorb(gs: Object, dmg: int) -> int:
	if dmg <= 0:
		return 0
	return maxi(1, dmg - armor_bonus(gs))

## Урон героя: классная база x множитель оружия + 1 за Амулет Леса.
## Амулет — награда квеста пещеры (has_amulet), в лавке не продаётся.
## Формула наследует дух game_state.gd: base * (2 если меч) + (1 если амулет).
static func player_damage(base: int, gs: Object) -> int:
	var d := int(round(float(base) * weapon_mult(gs)))
	if gs != null and bool(gs.get("has_amulet")):
		d += 1
	return maxi(1, d)
