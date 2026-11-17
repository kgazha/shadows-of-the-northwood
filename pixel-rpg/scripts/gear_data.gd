class_name GearData
extends RefCounted
## Реестр предметов экономики: лавка кузнеца Гриима, урон/броня от снаряжения,
## таблицы лута мобов и сундуков. Данные здесь — канон; GameState (сейв v2)
## хранит только золото, gear-слоты и флаги.
## Урон остаётся производным (как в game_state.gd): класс x оружие + амулет +1.
## Legacy-флаг has_sword живёт в синхроне (см. equip_item): при пустом слоте
## оружия он считается старым железным мечом (x2) — старые сейвы и «меч из
## сундука» (interactable.gd пишет только флаг) не проседают по урону.

## Классовая база для честной строки «Урон 8 + 4» (weapon_part): тот же
## preload-алиас, что в game_state.gd (classes_data.gd — чистые данные,
## кругов в графе preload нет).
const Classes := preload("res://scripts/classes_data.gd")

## Реестр «новых» цифр BALANCE.md (строки 6–8; g13/Г1.3–Г1.4). Строки 1–2
## (GOLD_QUEST_TREES/GOLD_QUEST_SLIMES) живут в quests_data.gd — тот же реестр,
## пинуются тем же прогоном _t42. Каждое число — ровно один литерал в коде.
const PRICE_RESIN := 15    # BALANCE строка 6: смола (материал факела) у Драна
const PRICE_TORCH := 25    # BALANCE строка 7: готовый факел у Драна
const PRICE_POTION := 30   # BALANCE строка 8: крепкое зелье (1 заряд) у Уты
## Г1.3-инвариант: крафт у Гриима (одна смола за 15, работа даром — Г1
## «сплету даром, печь моя») дешевле готового ровно на 10. Разницу менять нельзя.
const CRAFT_SAVING := 10

## id -> данные: name, slot ("weapon"/"armor"), price (золото, покупка), desc,
## dmg_mult (множитель урона для оружия) или armor_bonus (единиц урона мимо брони).
## g13: неснаряжаемые позиции торгуются через те же кнопки лавки, но slot —
## "mat" (материал в рюкзак), "charge" (заряд крепкого зелья), "tool" (факел);
## vendor — чей прилавок ("smith" — кузница, "merchant" — Дран, "uta" — Ута).
const ITEMS := {
	"sword": {
		"name": "Железный меч", "slot": "weapon", "price": 80,
		"desc": "Стандарт морхеймской дружины. Верный, но тяжёлый. Урон x2.",
		"dmg_mult": 2.0, "vendor": "smith",
	},
	"axe": {
		"name": "Боевой топор", "slot": "weapon", "price": 160,
		"desc": "Медленнее меча в руках, зато бьёт в два с половиной раза больнее. Урон x2.5.",
		"dmg_mult": 2.5, "vendor": "smith",
	},
	"rune_blade": {
		"name": "Клинок рун", "slot": "weapon", "price": 320,
		"desc": "Руны помнят кузню, которой в лесу давно нет. Урон x3.",
		"dmg_mult": 3.0, "vendor": "smith",
	},
	"leather": {
		"name": "Кожаный доспех", "slot": "armor", "price": 60,
		"desc": "Дублёная кожа: съедает 1 единицу урона из каждого удара.",
		"armor_bonus": 1, "vendors": ["smith", "hermit"],
	},
	"chain": {
		"name": "Кольчуга", "slot": "armor", "price": 180,
		"desc": "Тяжёлое кольцо: съедает 2 единицы урона, в жару тяжела, как болото.",
		# g20b: у Гриима — как всегда; у Драна — «трофейная» позиция после
		# сделки (гейт VENDOR_REQ, вердикт §4). Редкость «редкий» — вердикт
		# 16.11 22:56 (синий кант: меч северян + кольчуга).
		"armor_bonus": 2, "rarity": "rare", "vendors": ["smith", "merchant"],
	},
	# --- g13: экономика главы 1 (BALANCE строки 6–8, LINES Д1/Д2, Г1, У1) ---
	"resin": {
		"name": "Смола", "slot": "mat", "mat": "smola", "price": PRICE_RESIN,
		"desc": "Гриимова смола. Древко, тряпица, капля сноровки — и факел почти готов.",
		"vendor": "merchant",
	},
	"torch": {
		"name": "Факел", "slot": "tool", "price": PRICE_TORCH,
		"desc": "Готовый факел Драна. Тот же, что плетёт Гриим, — просто за деньги, а не за смолу.",
		"vendor": "merchant",
	},
	"potion": {
		"name": "Крепкое зелье", "slot": "charge", "price": PRICE_POTION,
		"desc": "Рецепт Уты: сухоцвет да жим. Заряд крепкого зелья: +6 HP (запас до 2).",
		"vendor": "uta",
	},
	# --- g20b (t63, вердикт пользователя 17.11, INVENTORY.md §2-3 «Что носим») ---
	# Модель вердикта: оружие даёт ПЛОСКИЙ +N к урону базового удара и скиллов
	# (формула видна в подсказке: «Урон 8 + 4»), броня — плоское снижение
	# −1/−2/−3 (минимум 1 проходит — уже обеспечено absorb()). Старая гриимова
	# линейка (множители x2/x2.5/x3) НЕ тронута вердиктом и остаётся каноном
	# старых сейвов и лавки Гриима; новые три предмета — трофейная линия
	# вердикта (сундуки/дроп/Геральд-Дран).
	"shortsword": {
		"name": "Краткий меч", "slot": "weapon", "price": 60, "dmg_bonus": 2,
		"desc": "Короткий и честный: +2 к урону.", "vendor": "hermit",
	},
	"nordsword": {
		"name": "Меч северян", "slot": "weapon", "price": 200, "dmg_bonus": 4,
		"desc": "Трофей северных мореходов: +4 к урону.", "rarity": "rare",
		"vendor": "merchant", "req": "slime_deal",
	},
	"fangblade": {
		"name": "Клыко-клинок", "slot": "weapon", "price": 0, "dmg_bonus": 7,
		"desc": "Клык вепря, вогнанный в сталь: +7 к урону. Только трофей.",
		"rarity": "epic",
	},
	# Кожа/кольчуга вердикта — ОНИ ЖЕ, что старые leather/chain: цифры вердикта
	# (−1/−2) совпали с каноном BALANCE до единицы, id не заводим дублями.
	"boarhide": {
		"name": "Шкура вепря", "slot": "armor", "price": 0, "armor_bonus": 3,
		"desc": "Веприна шкура держит удар: −3 урона, минимум 1 проходит.",
		"rarity": "epic",
	},
	# Оберег (вердикт §2): Амулет Леса становится ЭКИПИРУЕМЫМ. Эффект
	# (подсветка +1 урон) и раньше ключеван флагом has_amulet — в слоте или нет,
	# работает как сейчас (совместимость квеста, вердикт прямо просит).
	"amulet": {
		"name": "Амулет Леса", "slot": "relic", "price": 0,
		"desc": "Радиус подсветки и +1 к урону. Работает и без слота — как привык.",
	},
}
## Стартовый набор лавки Гриима (порядок витрины).
const SHOP_STOCK := ["sword", "axe", "rune_blade", "leather", "chain"]
## Витрины торговых голов главы 1 (g13). Кузница — SHOP_STOCK + крафт-секция
## (shop.gd), Дран — смола/факел, Ута — крепкое зелье.
## g20b (вердикт §4): Дран после сделки («трофейный» круг) — меч северян и
## кольчуга; Геральд — базовый сет (краткий меч + кожа).
const VENDOR_STOCK := {
	"smith": SHOP_STOCK,
	"merchant": ["resin", "torch", "nordsword", "chain"],
	"uta": ["potion"],
	"hermit": ["shortsword", "leather"],
}
## гейт витрины: VENDOR_REQ[vendor][item] == "slime_deal" — позиция видна
## только после закрытия квеста Драна (GameState.slime_quest >= 2, «сделка» g13).
const VENDOR_REQ := {
	"merchant": {"nordsword": "slime_deal", "chain": "slime_deal"},
}
## Заголовки прилавков (шапка панели лавки под каждого торговца).
const VENDOR_HEAD := {
	"smith": "Кузница Гриима",
	"merchant": "Лавка Драна",
	"uta": "Прилавок Уты",
	"hermit": "Припасы Геральда",
}
## Legacy-множитель меча из старой формулы урона (x2). Применяется, только
## когда слот weapon пуст, а has_sword == true.
const LEGACY_SWORD_MULT := 2.0
## Продажа — половина цены покупки (вниз, но не дешевле 1).
const SELL_DIV := 2

# --- g20b (t63): заточка и редкость (вердикт пользователя 17.11, INVENTORY.md
# «ОТВЕЧЕНО» п.4 и вердикт 16.11 22:56 о подсветке) ---

## Ступени заточки 0..5. Прибавка СЛЕДУЮЩЕЙ ступени (к итоговому урону оружия,
## без рандума и без потери прогресса): +5/+7/+10/+12/+15% — суммарно до +49%.
## SHARPEN_PCT — накопленный процент по степени (индекс = степень).
const SHARPEN_STEP_PCT := [5, 7, 10, 12, 15]
const SHARPEN_PCT := [0, 5, 12, 22, 34, 49]
## Цена ступени: степень t -> t+1 стоит SHARPEN_COST[t] точильных камней.
const SHARPEN_COST := [1, 2, 3, 4, 5]
const SHARPEN_MAX := 5

## Палитра редкости (вердикт 16.11 22:56): синий — редкий, фиолетовый — очень
## редкий, оранжевый — легендарный (инфраструктура цвета: предмета-легенды пока
## нет — обсудим, просит вердикт; рамка и имя готовы).
const RARITY_COLORS := {
	"rare": Color(0.40, 0.60, 1.00),
	"epic": Color(0.70, 0.42, 0.95),
	"legend": Color(1.00, 0.60, 0.15),
}
const RARITY_NAMES := {
	"rare": "редкий", "epic": "очень редкий", "legend": "легендарный",
}

static func rarity_of(id: String) -> String:
	return String(item(id).get("rarity", ""))

static func rarity_color(id: String) -> Color:
	return RARITY_COLORS.get(rarity_of(id), Color(0, 0, 0, 0))

static func rarity_name(id: String) -> String:
	return String(RARITY_NAMES.get(rarity_of(id), ""))

## Степень заточки надетого оружия (0 — нет оружия/не точили).
static func sharpen_tier(gs: Object) -> int:
	if gs == null:
		return 0
	return sharpen_tier_of(gs, equipped_id(gs, "weapon"))

static func sharpen_tier_of(gs: Object, wid: String) -> int:
	if gs == null or wid == "":
		return 0
	var sh: Variant = gs.get("sharpen")
	if typeof(sh) != TYPE_DICTIONARY:
		return 0
	return clampi(int((sh as Dictionary).get(wid, 0)), 0, SHARPEN_MAX)

## Наценка заточки на итоговый урон, % (0..49).
static func sharpen_pct(tier: int) -> int:
	return SHARPEN_PCT[clampi(tier, 0, SHARPEN_MAX)]

## Цена повышения tier -> tier+1 в точильных камнях; 0 — дальше некуда.
static func sharpen_cost(tier: int) -> int:
	if tier < 0 or tier >= SHARPEN_MAX:
		return 0
	return SHARPEN_COST[tier]

## Заточка надетого оружия на ступень: без рандума, деньги вперёд (камни),
## прогресс не теряется никогда. false + тост — отказ.
static func sharpen_weapon(gs: Object) -> bool:
	var wid := equipped_id(gs, "weapon")
	if wid == "" or String(item(wid).get("slot", "")) != "weapon":
		GameState.toast.emit("Нечего точить — оружие не надето.")
		return false
	var t := sharpen_tier_of(gs, wid)
	if t >= SHARPEN_MAX:
		GameState.toast.emit("Дальше некуда: заточка %d/%d (+%d%%)." % [t, SHARPEN_MAX, sharpen_pct(t)])
		return false
	var cost := sharpen_cost(t)
	if not gs.try_spend_materials({"whet": cost}):
		GameState.toast.emit("Нужно %d точильных камня (есть %d)." % [cost, gs.mat_count("whet")])
		return false
	gs.sharpen[wid] = t + 1
	GameState.toast.emit("%s: заточка %d/%d (+%d%%)." % [String(item(wid).get("name", "Меч")), t + 1, SHARPEN_MAX, sharpen_pct(t + 1)])
	gs.stats_changed.emit()
	return true

## Таблицы лута: kind моба -> список дропа (ролл на каждую строку).
## Строка: {"gold": [min, max], "chance": float} или
## {"item": id, "chance": float, "qty": int}; special-id предметов:
## "herb" (трава) и "potion" (заряд крепкого зелья) — свободных слотов
## инвентаря в игре нет, снаряжение покупается, а не падает с мобов.
## g20a (вердикт 17.11 ~10:00): строка {"mat": id, "chance": …, "qty": …} —
## материал в стопку (materials). Шкуры/жилы — «дроп мобов всегда» (chance 1.0):
## слизни и мглокрысы — шкуру, брут/лучник/тенеплёт — жилу, боссы — и то, и то.
## g20b (вердикт 17.11 §4 + п.3 «ОТВЕЧЕНО»): {"gear": id, "chance": 0.05} —
## редкий дроп снаряжения (5%, «5% хватит»): id в сумку GameState.owned_gear
## через Loot._give_gear; точильный камень — обычный частый дроп (mat whet).
const LOOT := {
	"slime": [
		{"gold": [2, 5], "chance": 0.85},
		{"item": "herb", "chance": 0.12, "qty": 1},
		{"mat": "hide", "chance": 1.0, "qty": 1},
		{"mat": "whet", "chance": 0.35, "qty": 1},
		{"gear": "shortsword", "chance": 0.05},
	],
	# золото брюта по ярусам (ECONOMY_BALANCE, вердикт 3): тир 1 слабее,
	# тир 3 жирнее — фарм глубоких ярусов перестанет быть выгодным в час.
	"brute": [
		{"gold": [6, 9], "chance": 0.9},
		{"item": "potion", "chance": 0.12, "qty": 1},
		{"mat": "sinew", "chance": 1.0, "qty": 1},
		{"mat": "whet", "chance": 0.35, "qty": 1},
		{"gear": "nordsword", "chance": 0.05},
	],
	"brute_t2": [
		{"gold": [8, 12], "chance": 0.9},
		{"item": "potion", "chance": 0.12, "qty": 1},
		{"mat": "sinew", "chance": 1.0, "qty": 1},
		{"mat": "whet", "chance": 0.35, "qty": 1},
		{"gear": "chain", "chance": 0.05},
	],
	"brute_t3": [
		{"gold": [10, 15], "chance": 0.9},
		{"item": "potion", "chance": 0.12, "qty": 1},
		{"mat": "sinew", "chance": 1.0, "qty": 1},
		{"mat": "whet", "chance": 0.4, "qty": 1},
		{"gear": "fangblade", "chance": 0.05},
	],
	"boss": [
		{"gold": [25, 40], "chance": 1.0},
		{"item": "potion", "chance": 1.0, "qty": 1},
		{"mat": "hide", "chance": 1.0, "qty": 2},
		{"mat": "sinew", "chance": 1.0, "qty": 2},
		{"mat": "whet", "chance": 1.0, "qty": 2},
	],
	# Ведьма Пепелища — мини-босс Зоны 2 (лут-строка запрошена оркестратором).
	"boss2": [
		{"gold": [35, 60], "chance": 1.0},
		{"item": "potion", "chance": 0.5, "qty": 1},
		{"mat": "hide", "chance": 1.0, "qty": 2},
		{"mat": "sinew", "chance": 1.0, "qty": 2},
		{"mat": "whet", "chance": 1.0, "qty": 2},
	],
	# новые архетипы: лучник сытее гнилодына (дальний бой рискует),
	# тенеплёт жирнее всех (эфир — самый опасный), мглокрыс — мелочь на 1 хит.
	"swarmling": [
		{"gold": [1, 3], "chance": 0.8},
		{"item": "herb", "chance": 0.08, "qty": 1},
		{"mat": "hide", "chance": 1.0, "qty": 1},
		{"mat": "whet", "chance": 0.25, "qty": 1},
		{"gear": "leather", "chance": 0.05},
	],
	"archer": [
		{"gold": [6, 11], "chance": 0.8},
		{"item": "herb", "chance": 0.15, "qty": 1},
		{"mat": "sinew", "chance": 1.0, "qty": 1},
		{"mat": "whet", "chance": 0.35, "qty": 1},
		{"gear": "chain", "chance": 0.05},
	],
	"wraith": [
		{"gold": [10, 18], "chance": 0.9},
		{"item": "potion", "chance": 0.15, "qty": 1},
		{"mat": "sinew", "chance": 1.0, "qty": 1},
		{"mat": "whet", "chance": 0.4, "qty": 1},
		{"gear": "boarhide", "chance": 0.05},
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

## Броня в единицах урона из надетого armor-предмета + талант «Толстая кожа»
## (skin, +1/ранг, CONTRACT_TALENTS §3); 0 — без брони и таланта.
static func armor_bonus(gs: Object) -> int:
	var b := 0
	var it := item(equipped_id(gs, "armor"))
	if String(it.get("slot", "")) == "armor":
		b += int(it.get("armor_bonus", 0))
	if gs != null:
		b += gs.tal_rank("skin")
	return b

## Урон после брони (для точки получения урона): любой ненулевой удар бьёт
## минимум на 1 (иначе кожа делала слаймов безвредными — дыра баланса).
static func absorb(gs: Object, dmg: int) -> int:
	if dmg <= 0:
		return 0
	return maxi(1, dmg - armor_bonus(gs))

## Урон героя: классная база x множитель оружия + 1 за Амулет Леса.
## Амулет — награда квеста пещеры (has_amulet), в лавке не продаётся.
## Формула наследует дух game_state.gd: base * (2 если меч) + (1 если амулет).
## g20b (вердикт 17.11 §3): + плоский бонус оружия (dmg_bonus: +2/+4/+7) и
## множитель заточки надетого оружия (до +49%): затачиваем ВСЁ оружие, включая
## старую линейку. skip_weapon_part=true — тот же расчёт БЕЗ вклада нового
## оружия (плоский бонус + заточка): разницей считаем честную строку
## «Урон 8 + 4» в подсказке слота.
static func player_damage(base: int, gs: Object, skip_weapon_part: bool = false) -> int:
	# «Мастерство» алтаря Пепла: t39 +15% за покупку (кап 3 = +45%).
	# (t38: +10% не покрывало роста волн; метку лавки «+10%» правит лавочник t42.)
	var f := 0
	if gs != null:
		f = mini(int(gs.flags.get("meta.master", 0)), 3)
	# Таланты (CONTRACT_TALENTS §3): «Уход за клинком» (id whetstone, g20b
	# переименован вердиктом, цифры прежние) — плоская прибавка +0.15
	# к множителю оружия за ранг; «Яростная сила» — итоговый множитель урона;
	# «Тяжёлый удар» — +1 до финального round(). Ранги читаем через gs (Object),
	# «голый» герой (gs == null) считается без талантов.
	var w_add := 0.0
	var fury := 0
	var heavy := 0
	var amulet := false
	if gs != null:
		w_add = 0.15 * float(gs.tal_rank("whetstone"))
		fury = gs.tal_rank("fury")
		heavy = gs.tal_rank("heavy")
		amulet = bool(gs.get("has_amulet"))
	# Формула каноническая (см. шапку): база x оружие x мастерство, ярость —
	# множит, амулет и тяжёлый удар — плоские +1 до округления.
	var d := float(base) * (weapon_mult(gs) + w_add) * (1.0 + 0.15 * f)
	if not skip_weapon_part:
		# g20b: заточка — накопленный множитель ступени (5/12/22/34/49%),
		# ложится поверх мастерства; плоский бонус нового оружия добавляем
		# до ярости — ярость множит весь вклад целиком.
		d *= 1.0 + 0.01 * float(sharpen_pct(sharpen_tier(gs)))
		d += float(weapon_bonus_flat(gs))
	d *= 1.0 + 0.05 * float(fury)
	if amulet:
		d += 1.0
	d += float(heavy)
	return maxi(1, int(round(d)))

## Плоский бонус надетого оружия (g20b «+2/+4/+7»); 0 — старая линейка/пусто.
static func weapon_bonus_flat(gs: Object) -> int:
	var it := item(equipped_id(gs, "weapon"))
	if String(it.get("slot", "")) != "weapon":
		return 0
	return int(it.get("dmg_bonus", 0))

## Вклад нового оружия в урон (плоский + эффект заточки), целое — для строки
## «Урон %d + %d» подсказки слота (вердикт §3 «формула честная и видна»).
static func weapon_part(gs: Object) -> int:
	if gs == null:
		return 0
	var base := int(Classes.class_data(String(gs.get("class_id"))).get("dmg", 4))
	return player_damage(base, gs) - player_damage(base, gs, true)
