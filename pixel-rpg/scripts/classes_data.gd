extends RefCounted
## Статические данные спринта 2: 3 класса и 12 скиллов (по 4 каждому).
## Пороги разблокировки — уровни 1/2/3/4 (правка v1.1).
## Иконки: assets/skill_icons.png — 192x16, 12 слотов 16x16 в ряд:
## 0 power_strike, 1 whirlwind, 2 second_wind, 3 execute,
## 4 pierce, 5 volley, 6 mark, 7 rain, 8 firebolt, 9 frost_nova, 10 siphon, 11 firestorm.

## kind: "melee" — do_attack в радиусе; "ranged" — снаряд projectile-индекса.
## proj_speed — px/с для дальних. radius — радиус применения автоатаки, px.
const CLASSES := {
	"warrior": {
		"name": "Воин", "hp": 12, "dmg": 2, "speed": 95.0,
		"radius": 18.0, "attack_speed": 1.0, "kind": "melee",
		"projectile": -1, "proj_speed": 0.0,
		"sprites": "res://assets/class_warrior.png",
		"desc1": "Крепкая броня и тяжёлый клинок.",
		"desc2": "Бьёт вблизи, выдерживает удары.",
		"bonus": "Класс: +2 к урону вблизи, много HP",
	},
	"archer": {
		"name": "Лучник", "hp": 8, "dmg": 2, "speed": 100.0,
		"radius": 80.0, "attack_speed": 0.7, "kind": "ranged",
		"projectile": 0, "proj_speed": 200.0,
		"sprites": "res://assets/class_archer.png",
		"desc1": "Быстрые ноги, меткая рука.",
		"desc2": "Стреляет издалека, хрупок вблизи.",
		"bonus": "Класс: дальний бой, самая быстрая атака",
	},
	"mage": {
		"name": "Маг", "hp": 6, "dmg": 3, "speed": 95.0,
		"radius": 70.0, "attack_speed": 1.05, "kind": "ranged",
		"projectile": 1, "proj_speed": 140.0,
		"sprites": "res://assets/class_mage.png",
		"desc1": "Мантия шумит, пальцы искрят.",
		"desc2": "Файерболы сильны, но тело хрупко.",
		"bonus": "Класс: самый сильный снаряд, мало HP",
	},
}

## id скилла -> данные. level — требуемый уровень (правка v1.1: 1/2/3/4),
## cd — кулдаун, сек; icon — слот в skill_icons.png.
const SKILLS := {
	"power_strike": {"name": "Мощный удар", "level": 1, "cd": 4.0, "icon": 0,
		"desc": "Мгновенно 2x урон текущей цели (иначе догнать и ударить)."},
	"whirlwind": {"name": "Вихрь клинка", "level": 2, "cd": 8.0, "icon": 1,
		"desc": "1.5x урон всем врагам в радиусе 28 px вокруг."},
	"second_wind": {"name": "Второй ветер", "level": 3, "cd": 20.0, "icon": 2,
		"desc": "Мгновенно лечит 4 HP."},
	"execute": {"name": "Казнь", "level": 4, "cd": 12.0, "icon": 3,
		"desc": "Цель с HP <= 25% погибает мгновенно, иначе 1.5x урон."},
	"pierce": {"name": "Пробивающий выстрел", "level": 1, "cd": 5.0, "icon": 4,
		"desc": "Стрела сквозь всех на линии, 1.5x урон."},
	"volley": {"name": "Залп", "level": 2, "cd": 7.0, "icon": 5,
		"desc": "3 стрелы конусом +/-20 градусов, по 1x урону."},
	"mark": {"name": "Метка охотника", "level": 3, "cd": 10.0, "icon": 6,
		"desc": "Цель получает +50% урона от тебя на 6 с."},
	"rain": {"name": "Дождь стрел", "level": 4, "cd": 15.0, "icon": 7,
		"desc": "AoE 30 px в точке курсора, 2x урон, задержка 0.5 с."},
	"firebolt": {"name": "Огненная стрела", "level": 1, "cd": 4.0, "icon": 8,
		"desc": "Тяжёлый снаряд 2.5x, AoE 12 px при попадании."},
	"frost_nova": {"name": "Морозная нова", "level": 2, "cd": 10.0, "icon": 9,
		"desc": "Враги в радиусе 32 px заморожены на 3 с."},
	"siphon": {"name": "Поглощение", "level": 3, "cd": 12.0, "icon": 10,
		"desc": "5 с попадания снарядов лечат по 1 HP."},
	"firestorm": {"name": "Огненная буря", "level": 4, "cd": 18.0, "icon": 11,
		"desc": "Вокруг себя 3 удара по 1x в радиусе 36 px за 1.5 с."},
}

const CLASS_SKILLS := {
	"warrior": ["power_strike", "whirlwind", "second_wind", "execute"],
	"archer": ["pierce", "volley", "mark", "rain"],
	"mage": ["firebolt", "frost_nova", "siphon", "firestorm"],
}

static func class_data(id: String) -> Dictionary:
	return CLASSES.get(id, CLASSES["warrior"])

static func skills_for(id: String) -> Array:
	return CLASS_SKILLS.get(id, CLASS_SKILLS["warrior"])

static func skill(sid: String) -> Dictionary:
	return SKILLS.get(sid, {})
