extends "res://mb_base.gd"
## QA PT — t37 I4 «Pity-гарантия реликта» (26.11, волна «Интерес v1»; вердикт:
## «награды должны радовать темпом и подачей»). Пины контракта: карточка-
## вспышка ТОЛЬКО на редкое (реликт/элита/добротная; обычная — молчание;
## тумблер bold_fx OFF — ноль карточек, числа целы), дельта силы up/down/та же
## по канонической формуле (та же ветка урона, что охраняет гейт CLASS_WEAPONS)
## и броневой счёт с «Латаной кромкой», pity растёт тремя источниками (элита +1
## / зачистка +1 / — охота +2 запинена в qa_bty S6) и СБРАСЫВАЕТСЯ ровно по
## фактической выдаче (откат и канон-quest_relic кредита не лишают), гарантия
## на пороге детерминирована (байт к байту против Loot.affix_roll force),
## сейв v5 раундтрип + легаси-дефолт, журнал: «До реликта» с первым кредитом.

const LOOT := preload("res://scripts/loot.gd")
const QD := preload("res://scripts/quests_data.gd")

var _deltas: Array = []

func _ready() -> void:
	await boot(save_for(0))
	await pump(3)
	GameState.power_delta.connect(func(t: String) -> void: _deltas.append(t))
	_s1()
	_s2()
	_s3()
	_s4()
	_s5()
	_s6()
	done()

# ------------------------------------------------------------- S1 подача
## Детерминированная клетка заданного исхода ЕСТЕСТВЕННОГО ролла: want — число
## аффиксов (0 обычная / 1 добротная / 2 реликт). Ordinal = len+1 — ролл
## происходит ПОСЛЕ ensure_gear (drop_ordinal = размер сумки с новой вещью).
func _cell_for(want: int) -> Vector2:
	for i in 2000:
		var cp := Vector2(i * 16 + 8, i * 7 + 120)
		var c := LOOT.cell_key(cp)
		var r: Array = LOOT.affix_roll(int(GameState.run_seed), c, int(GameState.owned_gear.size()) + 1, false)
		if r.size() == want:
			return cp
	return Vector2.ZERO

func _s1() -> void:
	GameState.bold_fx = true
	BoldFx.reset_state()
	BoldFx._card_ms = -100000    # окно кулдауна — открыто (стенд дергает серии)
	var base := BoldFx.cards_shown()
	# обычная — карточки нет
	GameState.owned_gear.clear(); GameState.affixes.clear()
	LOOT._give_gear(GameState, "leather", _cell_for(0))
	check("S1 обычная вещь — ни одной карточки", BoldFx.cards_shown() == base)
	# добротная — «РЕДКОСТЬ»
	BoldFx._card_ms = -100000
	GameState.owned_gear.clear(); GameState.affixes.clear()
	LOOT._give_gear(GameState, "leather", _cell_for(1))
	var good_n := (GameState.affixes.get("leather", []) as Array).size()
	check("S1 добротная => ровно одна карточка (аффиксов=%d)" % good_n,
			good_n == 1 and BoldFx.cards_shown() == base + 1)
	# реликт — «РЕЛИКТ»
	BoldFx._card_ms = -100000
	GameState.owned_gear.clear(); GameState.affixes.clear()
	GameState.elite_pity = GameState.PITY_THRESHOLD
	LOOT._give_gear(GameState, "boarhide", _cell_for(0))
	check("S1 pity-реликт => карточка РЕЛИКТ + счёт 2 аффикса",
			(GameState.affixes.get("boarhide", []) as Array).size() == 2
			and BoldFx.cards_shown() == base + 2)
	# элита — «ЭЛИТ» (seed — воспроизводимость золотых роллов таблицы)
	BoldFx._card_ms = -100000
	seed(4242)
	GameState.elite_pity = 0
	var who := Node.new()
	who.set_meta("elite", true)
	LOOT.on_mob_death("slime", Vector2.ZERO, null, who)
	who.free()
	check("S1 смерть элиты => минимум одна карточка (ЭЛИТ)", BoldFx.cards_shown() >= base + 3)
	# OFF — молчание; числа (аффиксы) целы
	BoldFx._card_ms = -100000
	GameState.bold_fx = false
	var off_base := BoldFx.cards_shown()
	GameState.owned_gear.clear(); GameState.affixes.clear()
	GameState.elite_pity = GameState.PITY_THRESHOLD
	LOOT._give_gear(GameState, "chain", _cell_for(0))
	seed(4242)
	var who2 := Node.new()
	who2.set_meta("elite", true)
	LOOT.on_mob_death("slime", Vector2.ZERO, null, who2)
	who2.free()
	GameState.bold_fx = true
	check("S1 OFF-тумблер: ноль карточек, аффиксы реликта на месте",
			BoldFx.cards_shown() == off_base
			and (GameState.affixes.get("chain", []) as Array).size() == 2)
	GameState.elite_pity = 0

# ------------------------------------------------------- S2 дельта силы
func _s2() -> void:
	check("S2 формат: +7 СИЛЫ / −2 БРОНИ / та же сила",
			GearData.delta_label(7, "СИЛЫ") == "+7 СИЛЫ"
			and GearData.delta_label(-2, "БРОНИ") == "−2 БРОНИ"
			and GearData.delta_label(0, "СИЛЫ") == "та же сила")
	GameState.class_id = "warrior"
	GameState.owned_gear.clear(); GameState.affixes.clear()
	GameState.gear = {"weapon": "", "armor": "", "shield": "", "relic": ""}
	for w in ["sword", "rune_blade", "shortsword"]:
		GameState.owned_gear.append(w)
	# Воин: база 2; меч x2 => +2; клинок рун x3 => ещё +4; краткий (+2 flat)
	# после руны => −2; повторный клик => 0. Все три — тип "sword" (гейт пройден).
	var d0 := int(GameState.damage)
	GameState.equip_item("weapon", "sword")
	var d1 := int(GameState.damage)
	GameState.equip_item("weapon", "rune_blade")
	var d2 := int(GameState.damage)
	GameState.equip_item("weapon", "shortsword")
	var d3 := int(GameState.damage)
	GameState.equip_item("weapon", "shortsword")
	var d4 := int(GameState.damage)
	var up := d2 - d1
	var down := d3 - d2
	var same := d4 - d3
	check("S2 до/после по канону: рост +%d => «%s», спад %d => «%s», ноль => «%s»"
			% [up, GearData.delta_label(up, "СИЛЫ"), down, GearData.delta_label(down, "СИЛЫ"),
				GearData.delta_label(same, "СИЛЫ")],
			up > 0 and GearData.delta_label(up, "СИЛЫ").begins_with("+")
			and down < 0 and GearData.delta_label(down, "СИЛЫ").begins_with("−")
			and same == 0)
	check("S2 первый экип на голого: %d => %d (%s)" % [d0, d1, GearData.delta_label(d1 - d0, "СИЛЫ")],
			d1 > d0 and d1 - d0 == 2)
	# броневой счёт: реестр + «Латаная кромка»
	var lb := GearData.armor_score(GameState, "leather")
	GameState.affixes["leather"] = ["hardened"]
	var l1 := GearData.armor_score(GameState, "leather")
	GameState.affixes["leather"] = ["hardened", "keen"]
	var l2 := GearData.armor_score(GameState, "leather")
	check("S2 armor_score: реестр %d, кромка +1 => %d, реликт => %d" % [lb, l1, l2],
			l1 == lb + 1 and l2 == lb + 2)
	# сигнальный путь: сигнал объявлен, приёмник ловит строку один в один
	check("S2 GameState.power_delta объявлен", GameState.has_signal("power_delta"))
	var n0 := _deltas.size()
	GameState.power_delta.emit("+9 СИЛЫ")
	check("S2 приёмник ловит «+9 СИЛЫ» дословно",
			_deltas.size() == n0 + 1 and String(_deltas[_deltas.size() - 1]) == "+9 СИЛЫ")
	GameState.equip_item("weapon", "")
	GameState.affixes.clear()

# --------------------------------------------------------- S3 кредиты
func _s3() -> void:
	GameState.elite_pity = 0
	seed(99)
	var who := Node.new()
	who.set_meta("elite", true)
	LOOT.on_mob_death("slime", Vector2.ZERO, null, who)
	who.free()
	check("S3 элита => +1 pity", int(GameState.elite_pity) == 1)
	LOOT.on_mob_death("slime", Vector2.ZERO, null, null)
	check("S3 не-элита => кредит цел", int(GameState.elite_pity) == 1)
	QD.note_belt_mini(GameState, "forest")
	check("S3 зачистка микро-подземелья => +1", int(GameState.elite_pity) == 2)
	QD.note_belt_mini(GameState, "forest")
	check("S3 повторный заход (флаг q.bm.forest) => тишина", int(GameState.elite_pity) == 2)
	QD.note_belt_mini(GameState, "ash")
	check("S3 чужая зона => ни кредита, ни флага",
			int(GameState.elite_pity) == 2 and int(GameState.get_flag("q.bm.ash", 0)) == 0)
	# +2 охоты — пин qa_bty S6; здесь только сверка константы канала
	check("S3 порог гарантии 16 (ECONOMY_BALANCE 26.11)", int(GameState.PITY_THRESHOLD) == 16)

# ------------------------------------------------- S4 гарантия: детермин/расход
func _s4() -> void:
	GameState.owned_gear.clear(); GameState.affixes.clear()
	GameState.elite_pity = int(GameState.PITY_THRESHOLD) - 1
	var cp := _cell_for(0)
	LOOT._give_gear(GameState, "leather", cp)
	check("S4 порог−1: ролл естественный, кредит цел",
			(GameState.affixes.get("leather", []) as Array).size() == 0
			and int(GameState.elite_pity) == int(GameState.PITY_THRESHOLD) - 1)
	# порог: force побитово == канонический force-ролл
	GameState.elite_pity = int(GameState.PITY_THRESHOLD)
	var ordinal := int(GameState.owned_gear.size()) + 1
	LOOT._give_gear(GameState, "boarhide", cp)
	var canon: Array = LOOT.affix_roll(int(GameState.run_seed), LOOT.cell_key(cp), ordinal, true)
	check("S4 на пороге: реликт байт-в-байт против force-ролла",
			str(GameState.affixes.get("boarhide", [])) == str(canon) and canon.size() == 2)
	check("S4 выдача сожгла кредит (сброс в 0)", int(GameState.elite_pity) == 0)
	GameState.owned_gear.clear(); GameState.affixes.clear()
	LOOT._give_gear(GameState, "chain", cp)
	check("S4 после сброса: дроп снова естественный",
			(GameState.affixes.get("chain", []) as Array).size() == 0)
	# откат (дубль в сумке) кредит НЕ тратит
	GameState.elite_pity = int(GameState.PITY_THRESHOLD)
	GameState.owned_gear.append("leather")
	LOOT._give_gear(GameState, "leather", cp)
	check("S4 дубль-дроп: кредит не потрачен", int(GameState.elite_pity) == int(GameState.PITY_THRESHOLD))
	# quest_relic — канон-реликт: кредит не трогает
	var got := String(LOOT.quest_relic(GameState, "qa_pt", ["fangblade"]))
	check("S4 quest_relic выдан (%s), кредит цел" % got,
			got == "fangblade" and int(GameState.elite_pity) == int(GameState.PITY_THRESHOLD))
	# сундучный сет: первый фактический реликт сжигает кредит
	GameState.owned_gear.clear(); GameState.affixes.clear()
	LOOT.grant_gear_set(GameState, ["leather", "chain"], "chest:qa_pt")
	var forced := 0
	for k in ["leather", "chain"]:
		if (GameState.affixes.get(k, []) as Array).size() == 2:
			forced += 1
	check("S4 сет под порогом: реликт есть, кредит сгорел ровно раз",
			forced >= 1 and int(GameState.elite_pity) == 0)
	# естественный реликт (5%) кредит НЕ тратит
	GameState.owned_gear.clear(); GameState.affixes.clear()
	GameState.elite_pity = 1
	var relic_cp := _cell_for(2)
	LOOT._give_gear(GameState, "boarhide", relic_cp)
	check("S4 естественный реликт 5%: выдан, кредит 1 цел",
			(GameState.affixes.get("boarhide", []) as Array).size() == 2
			and int(GameState.elite_pity) == 1)
	GameState.elite_pity = 0

# ------------------------------------------------------------- S5 сейв v5
func _s5() -> void:
	GameState.elite_pity = 11
	var d := GameState.to_dict()
	check("S5 версия сейва 5 (ре-пин t37)", int(d.get("v", 0)) == 5)
	check("S5 elite_pity в словаре = 11", int(d.get("elite_pity", -1)) == 11)
	GameState.elite_pity = 0
	GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check("S5 JSON раундтрип => 11", int(GameState.elite_pity) == 11)
	var leg: Dictionary = JSON.parse_string(JSON.stringify(d))
	leg.erase("elite_pity")
	GameState.from_dict(leg)
	check("S5 легаси без ключа => 0", int(GameState.elite_pity) == 0)

# ----------------------------------------------------------- S6 журнал
func _s6() -> void:
	GameState.elite_pity = 0
	var e0: Array = QD.entries(GameState)
	var has0 := false
	for e in e0:
		if String((e as Dictionary).get("id", "")) == "pity":
			has0 = true
	check("S6 нулевой счётчик — строки в журнале нет", not has0)
	GameState.elite_pity = 3
	var row := _pity_row()
	var t: Dictionary = (row["targets"] as Array)[0]
	check("S6 кредит 3: «До реликта» 3/16 не закрыт",
			String(t["label"]) == "До реликта" and int(t["cur"]) == 3
			and int(t["need"]) == 16 and not bool(t["done"]))
	GameState.elite_pity = 20
	var t2: Dictionary = (_pity_row()["targets"] as Array)[0]
	check("S6 кредит 20: планка прижата к 16, готово",
			int(t2["cur"]) == 16 and int(t2["need"]) == 16 and bool(t2["done"]))
	GameState.elite_pity = 0
	# слияние не половило цепочку: pity — последний, остальные на месте
	GameState.elite_pity = 5
	var e2: Array = QD.entries(GameState)
	var pity_idx := -1
	for i in e2.size():
		if String((e2[i] as Dictionary).get("id", "")) == "pity":
			pity_idx = i
	check("S6 строка pity — последняя, записей больше одной (%d)" % e2.size(),
			pity_idx == e2.size() - 1 and e2.size() > 1)
	GameState.elite_pity = 0

func _pity_row() -> Dictionary:
	for e in QD.entries(GameState):
		if String((e as Dictionary).get("id", "")) == "pity":
			return e as Dictionary
	return {}
