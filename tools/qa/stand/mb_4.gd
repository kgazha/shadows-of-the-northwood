extends "res://mb_base.gd"
## Блок 2: регресс фиксов game_state (коммит 52d05a1). Мир не поднимается.

func _ready() -> void:
	t_equip()
	t_gear_canon()
	t_flags_types()
	t_flags_cap()
	t_cf_cap()
	t_legacy_sword()
	t_adversarial()
	done()

func mk(extra: Dictionary) -> void:
	var base := {
		"v": 2, "class_id": "warrior", "level": 1, "xp": 0, "xp_next": 99999,
		"max_hp": 12, "hp": 12, "mana": 0, "seen_intro": true,
	}
	for k in extra:
		base[k] = extra[k]
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(base))
	f = null

func ld() -> bool:
	return GameState.load_game()

func t_equip() -> void:
	mk({})
	if not ld():
		check("E: базовый сейв грузится", false)
		return
	var base_dmg := int(Classes.class_data("warrior").dmg)
	var prev := String(GameState.equip_item("weapon", "sword"))
	check("E: меч надет — has_sword=true", GameState.has_sword == true)
	check("E: меч dmg=round(base*2)=%d" % (base_dmg * 2), GameState.damage == base_dmg * 2)
	prev = String(GameState.equip_item("weapon", "axe"))
	check("E: equip вернул предыдущий 'sword'", prev == "sword")
	check("E: топор при мече — has_sword=false", GameState.has_sword == false)
	var want_axe := int(round(float(base_dmg) * 2.5))
	check("E: топор dmg=round(base*2.5)=%d (факт=%d)" % [want_axe, GameState.damage], GameState.damage == want_axe)
	GameState.equip_item("weapon", "rune_blade")
	check("E: клинок рун x3", GameState.damage == int(round(float(base_dmg) * 3.0)))
	GameState.equip_item("weapon", "")
	check("E: очистка слота — has_sword=false без «призрачного меча»", GameState.has_sword == false and GameState.damage == base_dmg)

func t_gear_canon() -> void:
	mk({"gear": {"weapon": "sword", "armor": ""}, "has_sword": false})
	ld()
	check("G: gear=sword + has_sword:false => has_sword=true (M2)", GameState.has_sword == true)
	check("G: урон меча x2=4", GameState.damage == 4)
	mk({"gear": {"weapon": "axe", "armor": ""}, "has_sword": true})
	ld()
	check("G: документация: axe+has_sword:true — M2 НЕ гасит флаг", GameState.has_sword == true)
	check("G: урон по axe (x2.5)=5", GameState.damage == 5)

func t_flags_types() -> void:
	mk({"flags": {"q": 2, "f": 2.0, "s": "txt", "b": true}})
	ld()
	check("F: flags int сохраняется int (typeof==TYPE_INT)", typeof(GameState.flags.get("q")) == TYPE_INT)
	check("F: float 2.0 нормализуется в int 2 (M3)", typeof(GameState.flags.get("f")) == TYPE_INT and int(GameState.flags["f"]) == 2)
	check("F: строка остается строкой", typeof(GameState.flags.get("s")) == TYPE_STRING)
	check("F: bool остается bool", typeof(GameState.flags.get("b")) == TYPE_BOOL)
	GameState.set_flag("rt", 5)
	GameState.save_game()
	ld()
	check("F: set_flag(5) -> save -> load: int 5", typeof(GameState.flags.get("rt")) == TYPE_INT and int(GameState.flags["rt"]) == 5)

func t_flags_cap() -> void:
	var fd := {}
	for i in range(200):
		fd["k%d" % i] = i
	mk({"flags": fd})
	ld()
	check("F: 200 ключей flags => ровно 128 (остаток отброшен)", GameState.flags.size() == 128)

func t_cf_cap() -> void:
	var cu := {}
	for i in range(200):
		cu["cf%d" % i] = true
	mk({"campfires_used": cu})
	ld()
	check("F: 200 ключей campfires_used => ровно 64", GameState.campfires_used.size() == 64)

func t_legacy_sword() -> void:
	mk({"has_sword": true})
	ld()
	check("L: legacy has_sword:true без gear => weapon=sword", String(GameState.gear["weapon"]) == "sword")
	check("L: legacy dmg x2 = 4", GameState.damage == 4)

func t_adversarial() -> void:
	mk({})
	ld()
	GameState.equip_item("weapon", "leather")
	check("A: не-weapon id в weapon-слоте => x1, флаг погашен", GameState.has_sword == false and GameState.damage == 2)
	GameState.equip_item("weapon", "excalibur")
	check("A: неизвестный id => x1, не краш", GameState.damage == 2)
	var prev2 := String(GameState.equip_item("ring", "sword"))
	check("A: неизвестный слот => '' без последствий", prev2 == "" and String(GameState.gear.get("ring", "")) == "")
	GameState.equip_item("weapon", "")
	GameState.equip_item("armor", "sword")
	check("A: меч в armor-слоте: не урон, не флаг", GameState.has_sword == false and GameState.damage == 2)
	GameState.equip_item("armor", "chain")
	GameState.hp = 12
	GameState.hurt(3)
	check("A: кольчуга режет урон до 1 (3->1)", GameState.hp == 11)
	GameState.equip_item("armor", "")
	# мусор в campfires_used: не-bool значения принимаются как есть (документация)
	mk({"campfires_used": {"cf_a": "мусор", "cf_b": 7}})
	ld()
	check("A: campfires_used принимает мусорные значения как есть", GameState.campfires_used.has("cf_a") and GameState.campfires_used.has("cf_b"))
