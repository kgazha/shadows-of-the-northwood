extends "res://mb_base.gd"
## qa_run — фаза 1 «смерть-петля»: инварианты R1–R7 контракта CONTRACT_RUNLOOP.md (§3).
## Проверяется контрактный вход GameState.start_new_run() (пишется параллельно, P1).
## Вызов start_new_run идёт через Variant-ссылку на GameState — это ПРЯМОЙ вызов
## без has_method-гейта (канон задачи), но скрипт обязан компилироваться ещё ДО
## слияния ядра (единственный hard-guard контракта: ноль ошибок парсинга). До
## слияния ядра ожидаем в рантайме «Invalid call ... start_new_run» и красный
## вердикт — это плановый RED, а не подгонка ассертов под отсутствие API.
## Мир не поднимаем (паттерн mb_4): только каналы GameState/Achv — детерминизм.
## Граница P3 (§2): qa_run.gd / qa_run.tscn; manifest.json не трогаем.

## Позаимствовано у mb_base: const Classes := preload("res://scripts/classes_data.gd").
## Динамическая привязка к параллельно пишущейся функции GameState: вызов прямой,
## гейтов нет; статический резолвинг включится сам, когда ядро сольют.
var _gs: Variant = GameState

const STAMP := 1747500000.5  # фиксированный unix-day для daily.stamp

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	r1_live_entry()
	r2_wipe_and_carry()
	r3_hero_zeroed()
	r4_deaths_and_rekindled()
	r5_save_load_roundtrip()
	r6_ng_plus_regression()
	r7_daily_not_rewound()
	# Целостность сюиты: при отсутствии ядра рантайм-ошибка в _gs.start_new_run()
	# обрывает лишь текущую функцию, и до done() дошёл бы псевдозелёный отсчёт
	# прошедших R6. Проверяем собственный счётчик — не has_method-гейт, блок
	# «недосчитан» честно даёт FAIL, до слияния ядра вердикт стенда красный.
	check("RALL: исполнены все 56 проверок R1–R7 (нет оборванных блоков)", _pass + _fail == 56)
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

# --- R1: «hp→0» смоделирован напрямую, вход из живого mid-run ---

func r1_live_entry() -> void:
	mk_midrun(1, false)
	GameState.hp = 0  # смерть смоделирована напрямую, не через бой (§3 R1)
	_gs.start_new_run()
	check("R1: start_new_run из mid-run с hp=0 не роняет и оживляет героя", GameState.hp >= 1)
	check("R1: hp после воскрешения в диапазоне (hp <= max_hp)", GameState.hp <= GameState.max_hp)

# --- R2: волна стоит; метаслой цел; мир вытерт (набор = start_ng_plus) ---

func r2_wipe_and_carry() -> void:
	mk_midrun(1, true)
	_gs.start_new_run()
	check("R2: ng.wave смертью не двигается (=2, и через ng_wave())", int(GameState.flags.get("ng.wave", 0)) == 2 and GameState.ng_wave() == 2)
	var residual := ""
	for k in GameState.flags:
		var ks := String(k)
		if ks.begins_with("q.") or ks.begins_with("ashen.") or ks.begins_with("ng.boss_") or ks.begins_with("tal."):
			residual += ks + " "
	check("R2: q./ashen./ng.boss_/tal. вытерты начисто [%s]" % residual, residual == "")
	check("R2: флаг ng.wave не задет общим префиксным вайпом ng.", GameState.flags.has("ng.wave"))
	check("R2: ach.n.campfires=7 цел (вечный счётчик)", int(GameState.flags.get("ach.n.campfires", -1)) == 7)
	check("R2: ach.treasure=true цел (анлок не откатывается)", bool(GameState.flags.get("ach.treasure", false)) == true)
	check("R2: Амулет Леса вечен — has_amulet=true пережил смерть (канон оркестратора, game_state:628)", GameState.has_amulet == true)
	check("R2: meta.purse/ash/bless целы", int(GameState.flags.get("meta.purse", -1)) == 1 and int(GameState.flags.get("meta.ash", -1)) == 12 and int(GameState.flags.get("meta.bless", -1)) == 1)
	check("R2: daily.stamp/streak целы", float(GameState.flags.get("daily.stamp", 0.0)) == STAMP and int(GameState.flags.get("daily.streak", -1)) == 3)
	check("R2: hint.* цел", String(GameState.flags.get("hint.campfire", "")) == "seen")
	check("R2: пепел босса не откатан смертью, хотя гейт ng.boss_2 стёрт (§0)", int(GameState.flags.get("meta.ash", 0)) == 12 and not GameState.flags.has("ng.boss_2"))
	check("R2: квесты и пещера сброшены", GameState.elder_quest == 0 and GameState.slime_quest == 0 and GameState.cave_state == 0 and GameState.has_key == false and GameState.door_opened == false)
	check("R2: сундуки/костры/травы/круг-убийства/зелья обнулены", GameState.chests_used.size() == 0 and GameState.campfires_used.size() == 0 and GameState.herbs == 0 and GameState.slime_kills_circle == 0 and GameState.brewed_potions == 0)
	check("R2: materials обнулены, структура ключей цела (has() для add_material)", GameState.materials.has("suhotsvet") and GameState.materials.has("zhim") and int(GameState.materials.get("suhotsvet", -1)) == 0 and int(GameState.materials.get("zhim", -1)) == 0)
	check("R2: в деревню: in_cave=false, pos_valid=false", GameState.in_cave == false and GameState.pos_valid == false)
	check("R2: lifetime slime_kills=9 не съеден (основа ачивок «Охотник»)", GameState.slime_kills == 9)

# --- R3: герой обнулён, золото = 50 x meta.purse ---

func r3_hero_zeroed() -> void:
	mk_midrun(1, false)
	_gs.start_new_run()
	check("R3: уровень=1 и опыт=0", GameState.level == 1 and GameState.xp == 0)
	check("R3: шмот стартовый — оба слота пусты", String(GameState.gear.get("weapon", "?")) == "" and String(GameState.gear.get("armor", "?")) == "")
	var base_dmg := int(Classes.class_data("warrior").dmg)
	check("R3: has_sword погашен; урон = база класса %d (меч/таланты вытерты)" % base_dmg, GameState.has_sword == false and GameState.damage == base_dmg)
	check("R3: золото = 50 x meta.purse(1), не перенос 777", GameState.gold == 50)
	mk_midrun(2, false)
	_gs.start_new_run()
	check("R3: meta.purse=2 => стартовое золото 100", GameState.gold == 100)
	mk_midrun(0, false)
	_gs.start_new_run()
	check("R3: meta.purse=0 => золото 0 (голый старт)", GameState.gold == 0)

# --- R4: ach.n.deaths; rekindled на 5-й, идемпотентен на 6-й ---

func r4_deaths_and_rekindled() -> void:
	mk({"flags": {}})  # чистый сейв: счётчика смертей ещё нет
	for i in range(1, 7):
		_gs.start_new_run()
		var now := int(GameState.flags.get("ach.n.deaths", 0))
		check("R4: смерть #%d -> ach.n.deaths=%d (строго +1)" % [i, i], now == i)
		var rek := bool(GameState.flags.get("ach.rekindled", false))
		if i < 5:
			check("R4: #%d — rekindled раньше срока не выдан" % i, rek == false)
		else:
			check("R4: #%d — ach.rekindled=true" % i, rek == true)
	check("R4: «Угас и вспыхнул» выдан ровно один тост (без двойной награды на 6-й)", n_toast("Угас и вспыхнул") == 1)
	# ADDENDUM 1.0 (решение оркестратора по эконом-аудиту): #20 «Неугасимый» на
	# >=15-й смерти того же вечного счётчика. Дотягиваем петлю до 15-й/16-й.
	for _i in range(7, 15):
		_gs.start_new_run()
	check("R4: после 14-й смерти счётчик дошёл (ach.n.deaths=14)", int(GameState.flags.get("ach.n.deaths", 0)) == 14)
	check("R4: undying раньше 15-й не выдан (#14)", bool(GameState.flags.get("ach.undying", false)) == false)
	_gs.start_new_run()  # 15-я
	check("R4: 15-я смерть — ach.undying=true («Неугасимый»), deaths=15", bool(GameState.flags.get("ach.undying", false)) == true and int(GameState.flags.get("ach.n.deaths", 0)) == 15)
	_gs.start_new_run()  # 16-я
	check("R4: на 16-й undying идемпотентен — тост «Неугасимый» ровно один", n_toast("Неугасимый") == 1)
	check("R4: «Угас и вспыхнул» не удвоен соседней вехой (ровно 1 за 16 смертей)", n_toast("Угас и вспыхнул") == 1)

# --- R5: save/load roundtrip после start_new_run — состояние идентично ---

func r5_save_load_roundtrip() -> void:
	mk_midrun(1, false)
	_gs.start_new_run()
	var mem := JSON.stringify(GameState.to_dict())
	check("R5: load_game() после автосейва start_new_run (§1.7) — true", GameState.load_game() == true)
	check("R5: диск после start_new_run идентичен памяти (порядок фиксации §1.7)", JSON.stringify(GameState.to_dict()) == mem)
	var snap := JSON.stringify(GameState.to_dict())
	check("R5: save_game() — true", GameState.save_game() == true)
	check("R5: load_game() после save — true", GameState.load_game() == true)
	check("R5: после save/load roundtrip состояние побайтово идентично", JSON.stringify(GameState.to_dict()) == snap)

# --- R6: регрессия start_ng_plus (победный вход НЕ обнуляет героя) ---

func r6_ng_plus_regression() -> void:
	mk_midrun(1, true)
	var lv := GameState.level
	var xp := GameState.xp
	var gold := GameState.gold
	var w: int = GameState.start_ng_plus()
	check("R6: волна +1 (2->3), возврат = 3", w == 3 and int(GameState.flags.get("ng.wave", 0)) == 3 and GameState.ng_wave() == 3)
	check("R6: победа — герой НЕ обнулён (уровень/опыт перенесены)", GameState.level == lv and GameState.xp == xp and lv == 3)
	check("R6: победа — шмот перенесён (меч+кольчуга, has_sword=true)", String(GameState.gear.get("weapon", "")) == "sword" and String(GameState.gear.get("armor", "")) == "chain" and GameState.has_sword == true)
	check("R6: победа — амулет перенесён (канон NG+ §1.2)", GameState.has_amulet == true)
	check("R6: золото = перенос 777 + 50 x purse (не абсолют 50!)", GameState.gold == gold + 50 and gold == 777)
	check("R6: мир вытерт как раньше (q./tal./ng.boss_/сундуки/травы/деревня)", not GameState.flags.has("q.elder") and not GameState.flags.has("tal.breath") and not GameState.flags.has("ng.boss_2") and GameState.chests_used.size() == 0 and GameState.herbs == 0 and GameState.in_cave == false)
	check("R6: ach./meta./daily. не задеты общим _wipe_circle", int(GameState.flags.get("ach.n.campfires", -1)) == 7 and int(GameState.flags.get("meta.ash", -1)) == 12 and float(GameState.flags.get("daily.stamp", 0.0)) == STAMP)
	mk({"flags": {"ng.wave": 5, "q.elder": 2}})
	GameState.start_ng_plus()
	check("R6: кап — пятая волна не растёт (5 стоит), мир при этом вытерт", int(GameState.flags.get("ng.wave", 0)) == 5 and not GameState.flags.has("q.elder"))

# --- R7: смерть не перематывает дневные (не фармятся смертью) ---

func r7_daily_not_rewound() -> void:
	mk({"flags": {"daily.stamp": STAMP, "daily.streak": 5, "q.elder": 1}})
	_gs.start_new_run()
	_gs.start_new_run()
	check("R7: daily.stamp не перемотан двумя смертями", float(GameState.flags.get("daily.stamp", 0.0)) == STAMP)
	check("R7: daily.streak=5 цел (серия не фармится смертью)", int(GameState.flags.get("daily.streak", 0)) == 5)
