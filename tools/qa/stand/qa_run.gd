extends "res://mb_base.gd"
## qa_run — смерть-петля: инварианты CONTRACT_RUNLOOP.md (§3) + t38 I5.
## ИСТОРИЯ: стенд создан под терминальную смерть (R1–R7 через start_new_run).
## ПЕРЕПИН 27.11 (t38 I5, вердикт пользователя 27.11, выбор А «МЯГКАЯ СМЕРТЬ —
## воскресение у костра/в деревне, −20% серебра с полом, экип/сумка/класс целы»):
## death-путь = GameState.soft_death() + GameState.respawn_after_death();
## терминальный вайп снят, его прежние ассерты (обнуление героя, 50×purse,
## вытирание мира) перенесены в D8 — на отказной вход start_fresh_game(), где
## этот вайп и живёт («Новая игра»). Победная арка (D9) не менялась.
## Экран смерти (loss/bless/Смертей) запинен в qa_mb R6 — здесь только GameState.
## Мир не поднимаем (паттерн mb_4): только каналы GameState/Achv — детерминизм.
## Граница P3 (§2): qa_run.gd / qa_run.tscn; manifest.json не трогаем.

## Позаимствовано у mb_base: const Classes := preload("res://scripts/classes_data.gd").
var _gs: Variant = GameState

const STAMP := 1747500000.5  # фиксированный unix-day для daily.stamp

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	d1_soft_entry()
	d2_gold_arithmetic()
	d3_untouchable()
	d4_world_and_meta_untouched()
	d5_save_roundtrip()
	d6_counters_and_blessing()
	d7_legacy_stub()
	d8_fresh_refusal_keeps_old_wipe()
	d9_ng_plus_regression()
	# Целостность сюиты: собственный счётчик (не has_method-гейт) — оборванный
	# блок честно даёт FAIL. Перепин 27.11: 57 (терминальная эпоха) -> 82 (мягкая).
	check("RALL: исполнены все 82 проверки D1–D9 без обрывов (нет оборванных блоков)", _pass + _fail == 82)
	done()

# --- фикстуры ---

func mk(save: Dictionary) -> void:
	var base := {
		"v": 2, "class_id": "warrior", "level": 1, "xp": 0, "xp_next": 20,
		"max_hp": 12, "hp": 12, "mana": 0, "gold": 0, "seen_intro": true,
		"cave_state": 0, "in_cave": false,
		"gear": {"weapon": "", "armor": ""}, "flags": {},
	}
	for k in save:
		base[k] = save[k]
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(base))
	f = null
	GameState.load_game()

## Живой mid-run: 3-й уровень, шмот, пещера в 3-й фазе, флаги во всех
## неймспейсах (q./ashen./ng./tal./ach./meta./daily./hint.) + инвентарь и счётчики.
func mk_midrun(purse: int, amulet: bool) -> void:
	mk({
		"level": 3, "xp": 11, "xp_next": 51, "hp": 3,
		"gold": 777, "gear": {"weapon": "sword", "armor": "chain"}, "has_sword": true,
		"cave_state": 3, "has_key": true, "door_opened": true, "has_amulet": amulet,
		"in_cave": true, "pos_valid": true, "px": 313.5, "py": 208.25,
		"elder_quest": 2, "slime_quest": 1,
		"herbs": 3, "slime_kills": 9, "slime_kills_circle": 4,
		"materials": {"suhotsvet": 2, "zhim": 1}, "brewed": 2,
		"campfires_used": {"cf_a": true, "cf_b": true},
		"chests_used": ["chest@18,18", "chest@30,24"],
		"flags": {
			"ng.wave": 2, "ng.boss_2": 1,
			"q.elder": 2, "q.got.amulet": 1, "ashen.witch": 1,
			"tal.breath": 1, "tal.skin": 1,
			"ach.n.campfires": 7, "ach.treasure": true,
			"meta.purse": purse, "meta.ash": 12, "meta.bless": 1,
			"daily.stamp": STAMP, "daily.streak": 3,
			"hint.campfire": "seen",
		},
	})

## Всё «нажитое забегом» — в память ПОСЛЕ загрузки (сумка/заточка/аффиксы —
## те же поля, что до 27.11 сгорали в вайпе; теперь неприкосновенны).
## Инварианты канона, обязательные для честного roundtrip-пина: надеть можно
## только то, что лежит в сумке (значит экипированное есть в bag), аффиксы —
## массив РЕАЛЬНЫХ id из GearData.AFFIXES (мусор лоад выбрасывает, и он прав).
func add_bag() -> void:
	GameState.owned_gear = ["sword", "chain", "shortsword"]
	GameState.sharpen = {"sword": 2}
	GameState.affixes = {"sword": ["hardened"]}

# --- D1: живой вход hp=0 -> цена + воскресение в деревне ---

func d1_soft_entry() -> void:
	mk_midrun(1, false)
	add_bag()
	GameState.hp = 0  # смерть смоделирована напрямую, не через бой (§3 R1)
	var maxp := GameState.max_hp
	var loss: int = _gs.soft_death()
	GameState.respawn_after_death()
	check("D1: soft_death вернула потерю и не уронила стенд (loss=%d)" % loss, loss == 155)
	check("D1: respawn из mid-run с hp=0 не роняет и оживляет героя", GameState.hp >= 1)
	check("D1: hp после воскресения в диапазоне (hp <= max_hp)", GameState.hp <= GameState.max_hp)
	check("D1: воскресший в полном здоровье (hp == max_hp, max не прыгнул)", GameState.hp == GameState.max_hp and GameState.max_hp == maxp)
	check("D1: домой, в деревню: area=village, in_cave=false, pos_valid=false", String(GameState.area) == "village" and GameState.in_cave == false and GameState.pos_valid == false)

# --- D2: арифметика цены: ровно 20% с floor, пол 0 ---

func d2_gold_arithmetic() -> void:
	# (старт, потеря, остаток) — floor при int-усечении; пол: не ниже 0
	var cases := [[777, 155, 622], [100, 20, 80], [9, 1, 8], [4, 0, 4], [0, 0, 0]]
	for c in cases:
		mk({"gold": int(c[0]), "flags": {}})
		var loss: int = _gs.soft_death()
		check("D2: gold=%d -> потеря %d, остаток %d, meta.last_loss=%d (floor, пол 0)" % [int(c[0]), int(c[1]), int(c[2]), int(c[1])],
			loss == int(c[1]) and GameState.gold == int(c[2]) and int(GameState.flags.get("meta.last_loss", -1)) == int(c[1]))

# --- D3: неприкосновенность: экип/сумка/заточка/аффиксы/класс/прогресс ---

func d3_untouchable() -> void:
	mk_midrun(1, false)
	add_bag()
	GameState.hp = 0
	var dmg := GameState.damage
	var maxp := GameState.max_hp
	_gs.soft_death()
	GameState.respawn_after_death()
	check("D3: уровень/опыт целы (3/11 — не обнулены)", GameState.level == 3 and GameState.xp == 11 and GameState.xp_next == 51)
	check("D3: экип цел (sword+chain, has_sword)", String(GameState.gear.get("weapon", "")) == "sword" and String(GameState.gear.get("armor", "")) == "chain" and GameState.has_sword == true)
	check("D3: сумка цела (owned_gear из 3 предметов)", GameState.owned_gear.size() == 3 and "shortsword" in GameState.owned_gear)
	check("D3: заточка цела (sword:2)", int(GameState.sharpen.get("sword", -1)) == 2)
	check("D3: аффиксы целы (sword:hardened)", (GameState.affixes.get("sword", []) as Array).has("hardened"))
	check("D3: класс цел (воин переживает смерть — правка 27.11 отменяет «стирает класс»)", String(GameState.class_id) == "warrior")
	check("D3: боеспособность не пересчитана в минус (damage/max_hp те же)", GameState.damage == dmg and GameState.max_hp == maxp)
	check("D3: серебро — единственная потеря (777 -> 622)", GameState.gold == 622)

# --- D4: мир при смерти цел: неймспейсы, волна, вечный слой, rs-статистика,
##     дневные не перематываются (поглощает прежние R2/R7: вайпа смерти больше нет) ---

func d4_world_and_meta_untouched() -> void:
	mk_midrun(1, true)
	add_bag()
	GameState.hp = 0
	_gs.soft_death()
	check("D4: soft_death НЕ вытирает мир: q./ashen./tal./ng.boss_ целы", GameState.flags.has("q.elder") and GameState.flags.has("ashen.witch") and GameState.flags.has("tal.breath") and GameState.flags.has("ng.boss_2"))
	check("D4: ng.wave смертью не двигается (=2, и через ng_wave())", int(GameState.flags.get("ng.wave", 0)) == 2 and GameState.ng_wave() == 2)
	check("D4: до respawn зона не тронута (in_cave=true, pos_valid=true — зона смерти ждёт решения)", GameState.in_cave == true and GameState.pos_valid == true)
	check("D4: ach.n.campfires=7 цел (вечный счётчик)", int(GameState.flags.get("ach.n.campfires", -1)) == 7)
	check("D4: ach.treasure=true цел (анлок не откатывается)", bool(GameState.flags.get("ach.treasure", false)) == true)
	check("D4: meta.purse/ash/bless целы", int(GameState.flags.get("meta.purse", -1)) == 1 and int(GameState.flags.get("meta.ash", -1)) == 12 and int(GameState.flags.get("meta.bless", -1)) == 1)
	check("D4: daily.stamp/streak целы (смерть не перематывает дневные — прежний R7)", float(GameState.flags.get("daily.stamp", 0.0)) == STAMP and int(GameState.flags.get("daily.streak", -1)) == 3)
	check("D4: hint.* цел", String(GameState.flags.get("hint.campfire", "")) == "seen")
	check("D4: пепел не тронут смертью (t70-норма усилена: и вайпа нет)", int(GameState.flags.get("meta.ash", 0)) == 12)
	check("D4: rs-статистика забега цела (смерть не обнуляет счётчик забега)", int(GameState.flags.get("rs.earned", -1)) >= 0 or not GameState.flags.has("rs.earned"))
	check("D4: квесты/пещера/сундуки/травы НЕ сброшены смертью", GameState.elder_quest == 2 and GameState.slime_quest == 1 and GameState.cave_state == 3 and GameState.herbs == 3 and GameState.chests_used.size() == 2)
	check("D4: Амулет Леса и lifetime slime_kills не съедены", GameState.has_amulet == true and GameState.slime_kills == 9)
	check("D4: materials целы (зачистка не сгорает)", int(GameState.materials.get("suhotsvet", -1)) == 2)

# --- D5: save/load roundtrip после цены+воскресения (прежний R5, F-10 норма:
##     структура сейва не менялась — новый факт живёт в flags.meta.last_loss) ---

func d5_save_roundtrip() -> void:
	mk_midrun(1, false)
	add_bag()
	GameState.hp = 0
	_gs.soft_death()
	GameState.respawn_after_death()
	var mem := JSON.stringify(GameState.to_dict())
	check("D5: load_game() после автосейва respawn (§1.7) — true", GameState.load_game() == true)
	# Дифф-диагностика нормализованная: JSON.parse_string приводит int к float,
	# поэтому обе стороны прогоняются через parse->stringify (иначе шум типов).
	var mem2s := JSON.stringify(GameState.to_dict())
	var mem1: Variant = JSON.parse_string(JSON.stringify(JSON.parse_string(mem)))
	var mem2: Variant = JSON.parse_string(mem2s)
	var diffs := ""
	for k in mem1:
		if String(JSON.stringify(mem1[k])) != String(JSON.stringify(mem2.get(k))):
			diffs += "%s: disk=%s mem=%s " % [k, String(JSON.stringify(mem1[k])).substr(0, 60), String(JSON.stringify(mem2.get(k))).substr(0, 60)]
	check("D5: диск после respawn идентичен памяти (порядок фиксации §1.7) %s" % diffs.substr(0, 200), mem2s == mem)
	var snap := JSON.stringify(GameState.to_dict())
	check("D5: save_game() — true", GameState.save_game() == true)
	check("D5: load_game() после save — true", GameState.load_game() == true)
	check("D5: после save/load roundtrip состояние побайтово идентично", JSON.stringify(GameState.to_dict()) == snap)
	check("D5: воскресение переживает лоад (village/жив/сумка цела/цена на диске)", String(GameState.area) == "village" and GameState.hp >= 1 and GameState.owned_gear.size() == 3 and int(GameState.flags.get("meta.last_loss", -1)) == 155)

# --- D6: вечные счётчики и благословение — ставки живут в soft_death
##     (прежний R4: вехи 5/15 идемпотентны; + meta.vd) ---

func d6_counters_and_blessing() -> void:
	mk({"flags": {}})  # чистый сейв: счётчика смертей ещё нет
	for i in range(1, 7):
		_gs.soft_death()
		var now := int(GameState.flags.get("ach.n.deaths", 0))
		check("D6: смерть #%d -> ach.n.deaths=%d (строго +1)" % [i, i], now == i)
		var rek := bool(GameState.flags.get("ach.rekindled", false))
		if i < 5:
			check("D6: #%d — rekindled раньше срока не выдан" % i, rek == false)
		else:
			check("D6: #%d — ach.rekindled=true" % i, rek == true)
	check("D6: «Угас и вспыхнул» выдан ровно один тост (без двойной награды на 6-й)", n_toast("Угас и вспыхнул") == 1)
	# ADDENDUM 1.0 (решение оркестратора по эконом-аудиту): #20 «Неугасимый» на
	# >=15-й смерти того же вечного счётчика. Дотягиваем петлю до 15-й/16-й.
	for _i in range(7, 15):
		_gs.soft_death()
	check("D6: после 14-й смерти счётчик дошёл (ach.n.deaths=14)", int(GameState.flags.get("ach.n.deaths", 0)) == 14)
	check("D6: undying раньше 15-й не выдан (#14)", bool(GameState.flags.get("ach.undying", false)) == false)
	_gs.soft_death()  # 15-я
	check("D6: 15-я смерть — ach.undying=true («Неугасимый»), deaths=15", bool(GameState.flags.get("ach.undying", false)) == true and int(GameState.flags.get("ach.n.deaths", 0)) == 15)
	_gs.soft_death()  # 16-я
	check("D6: на 16-й undying идемпотентен — тост «Неугасимый» ровно один", n_toast("Неугасимый") == 1)
	check("D6: «Угас и вспыхнул» не удвоен соседней вехой (ровно 1 за 16 смертей)", n_toast("Угас и вспыхнул") == 1)
	check("D6: ставка круга meta.vd растёт с каждой смертью (=16)", int(GameState.flags.get("meta.vd", -1)) == 16)
	check("D6: «Благословение» алтаря (meta.bless) смертью не трогается", int(GameState.flags.get("meta.bless", 0)) == 0)

# --- D7: мёртвый вход-стопор: терминальный start_new_run не имеет права
##     что-либо менять (тихого возвращения вайпа не будет) ---

func d7_legacy_stub() -> void:
	mk_midrun(1, false)
	add_bag()
	_gs.start_new_run()  # push_warning-стопор: обязан быть безвреден
	check("D7: stopper: золото не обнулено (777 стоит)", GameState.gold == 777)
	check("D7: stopper: герой не обнулён (level=3, класс цел)", GameState.level == 3 and String(GameState.class_id) == "warrior")
	check("D7: stopper: мир не вытерт (q.elder жив)", GameState.flags.has("q.elder"))

# --- D8: отказ от круга («Новая игра») — ПРЕЖНИЙ терминальный канон целиком:
##     переезд бывших R2/R3 с терминальной смерти (перепин 27.11: вайп живёт
##     здесь, где и был дублирован сознательно) ---

func d8_fresh_refusal_keeps_old_wipe() -> void:
	mk_midrun(1, true)
	add_bag()
	var deaths0 := int(GameState.flags.get("ach.n.deaths", 0))
	var vd0 := int(GameState.flags.get("meta.vd", 0))
	_gs.start_fresh_game()
	check("D8: уровень=1 и опыт=0", GameState.level == 1 and GameState.xp == 0)
	check("D8: шмот стартовый — оба слота пусты, сумка/заточка/аффиксы вытерты", String(GameState.gear.get("weapon", "?")) == "" and String(GameState.gear.get("armor", "?")) == "" and GameState.owned_gear.is_empty() and GameState.sharpen.is_empty() and GameState.affixes.is_empty())
	check("D8: класс обнулён (отказ = новый герой; 24.11-канон жив здесь)", String(GameState.class_id) == "")
	# fixtures выше с amulet=true — вечный амулет даёт законный +1 к базе
	var _dmg0 := int(Classes.class_data("warrior").dmg) + (1 if bool(GameState.has_amulet) else 0)
	check("D8: has_sword погашен; урон = база класса + вечный амулет = %d (факт sword=%s dmg=%d)" % [_dmg0, str(GameState.has_sword), GameState.damage], GameState.has_sword == false and GameState.damage == _dmg0)
	check("D8: золото = 50 x meta.purse(1), не перенос 622", GameState.gold == 50)
	check("D8: q./ashen./ng.boss_/tal. вытерты начисто, ng.wave не задет", not GameState.flags.has("q.elder") and not GameState.flags.has("ashen.witch") and not GameState.flags.has("ng.boss_2") and not GameState.flags.has("tal.breath") and int(GameState.flags.get("ng.wave", 0)) == 2)
	check("D8: квесты и пещера сброшены", GameState.elder_quest == 0 and GameState.slime_quest == 0 and GameState.cave_state == 0 and GameState.has_key == false and GameState.door_opened == false)
	check("D8: сундуки/костры/травы/круг-убийства/зелья обнулены", GameState.chests_used.is_empty() and GameState.campfires_used.is_empty() and GameState.herbs == 0 and GameState.slime_kills_circle == 0 and GameState.brewed_potions == 0)
	check("D8: materials обнулены, структура ключей цела", GameState.materials.has("suhotsvet") and int(GameState.materials.get("suhotsvet", -1)) == 0)
	check("D8: в деревню: in_cave=false, pos_valid=false", GameState.in_cave == false and GameState.pos_valid == false)
	check("D8: вечное цело: amulet/purse/ash/daily/hint/ach", GameState.has_amulet == true and int(GameState.flags.get("meta.purse", -1)) == 1 and int(GameState.flags.get("meta.ash", -1)) == 12 and float(GameState.flags.get("daily.stamp", 0.0)) == STAMP and String(GameState.flags.get("hint.campfire", "")) == "seen" and int(GameState.flags.get("ach.n.campfires", -1)) == 7)
	check("D8: отказ — НЕ смерть: deaths/vd не выросли (нет фарма благословения отказом)", int(GameState.flags.get("ach.n.deaths", 0)) == deaths0 and int(GameState.flags.get("meta.vd", 0)) == vd0)
	mk_midrun(2, false)
	_gs.start_fresh_game()
	check("D8: meta.purse=2 => стартовое золото 100", GameState.gold == 100)
	mk_midrun(0, false)
	_gs.start_fresh_game()
	check("D8: meta.purse=0 => золото 0 (голый старт)", GameState.gold == 0)

# --- D9: регрессия start_ng_plus (победный вход НЕ обнуляет героя) — прежний R6 ---

func d9_ng_plus_regression() -> void:
	mk_midrun(1, true)
	var lv := GameState.level
	var xp := GameState.xp
	var gold := GameState.gold
	var w: int = GameState.start_ng_plus()
	check("D9: волна +1 (2->3), возврат = 3", w == 3 and int(GameState.flags.get("ng.wave", 0)) == 3 and GameState.ng_wave() == 3)
	check("D9: победа — герой НЕ обнулён (уровень/опыт перенесены)", GameState.level == lv and GameState.xp == xp and lv == 3)
	check("D9: победа — шмот перенесён (меч+кольчуга, has_sword=true)", String(GameState.gear.get("weapon", "")) == "sword" and String(GameState.gear.get("armor", "")) == "chain" and GameState.has_sword == true)
	check("D9: победа — амулет перенесён (канон NG+ §1.2)", GameState.has_amulet == true)
	check("D9: золото = перенос 777 + 50 x purse (не абсолют 50!)", GameState.gold == gold + 50 and gold == 777)
	check("D9: мир вытерт как раньше (q./tal./ng.boss_/сундуки/травы/деревня)", not GameState.flags.has("q.elder") and not GameState.flags.has("tal.breath") and not GameState.flags.has("ng.boss_2") and GameState.chests_used.size() == 0 and GameState.herbs == 0 and GameState.in_cave == false)
	check("D9: ach./meta./daily. не задеты общим _wipe_circle", int(GameState.flags.get("ach.n.campfires", -1)) == 7 and int(GameState.flags.get("meta.ash", -1)) == 12 and float(GameState.flags.get("daily.stamp", 0.0)) == STAMP)
	mk({"flags": {"ng.wave": 5, "q.elder": 2}})
	GameState.start_ng_plus()
	check("D9: кап — пятая волна не растёт (5 стоит), мир при этом вытерт", int(GameState.flags.get("ng.wave", 0)) == 5 and not GameState.flags.has("q.elder"))
