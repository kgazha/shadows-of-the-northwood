extends "res://mb_base.gd"
## QA EL — t34 I1 «Элиты» (26.11, волна «Интерес v1»; вердикт: «12% мобов
## должны заставлять игрока остановиться и подумать „тяну я это или нет“»).
## Проверяется РОВНО контракт I1: детерминированный shash-ролл (доля/детерминизм
## двух проходов/зависимость от ординала), статы hp x2 / урон x1.5 при прежней
## скорости, каналы урона по семействам (dmg vs dmg_mult), украшение (золотая
## аура + подпись «Элитный …», гасится тумблером bold_fx, статы — нет),
## награда (серебро x3 точно, доп. гарантированный предмет, pity-кредит),
## сейв elite_pity (roundtrip + легаси-сейв без ключа = 0), гейты: деревня,
## пещера и мини-боссы вне жребия, разводка — только biome/ashen.
## Золото в loot.gd идёт через randi_range (не через test_roll!) — потому
## ровно-×3 проверяется парными seed() до каждого убийства.

const EL := preload("res://scripts/elites.gd")

func _ready() -> void:
	await boot(save_for(0))
	await pump(3)
	_s1()
	_s2()
	_s4()
	_s5()
	await _s6()   # кадры: free() отложен, счётчик элит считает живое дерево
	done()

# ------------------------------------------------------------- ролл-канон
func _s1() -> void:
	# сетка 60x40 синтетического сида: доля и два прохода побитово;
	# ординал 1 — ДРУГОЙ набор (ролл зависит от ординала, а не только клетки).
	var hits_a := 0
	var set_a: Array[int] = []
	var hits_b := 0
	for yy in 40:
		for xx in 60:
			var t := Vector2i(xx, yy)
			if EL.roll(20261126, "bz0:forest", t, 0):
				hits_a += 1
				set_a.append(yy * 60 + xx)
			if EL.roll(20261126, "bz0:forest", t, 0):
				hits_b += 1
	check("S1 доля элит на сетке 12%%: %d/2400 = %.3f в допуске [0.08;0.16]" % [hits_a, float(hits_a) / 2400.0],
		hits_a >= 192 and hits_a <= 384)
	check("S1 детерминизм двух проходов (%d == %d)" % [hits_a, hits_b], hits_a == hits_b)
	# ординал меняет набор: сравниваем поэлементно (иначе 0 hits == 0 hits)
	var ord_list: Array[int] = []
	for yy in 40:
		for xx in 60:
			if EL.roll(20261126, "bz0:forest", Vector2i(xx, yy), 1):
				ord_list.append(yy * 60 + xx)
	var differ := ord_list.size() != set_a.size()
	if not differ:
		for i in ord_list.size():
			if ord_list[i] != set_a[i]:
				differ = true
				break
	check("S1 ординал входит в ключ ролла (набор ordinal=0 != ordinal=1, %d vs %d)" % [set_a.size(), ord_list.size()], differ)

# --------------------------------------------------------- статы/украшение
func _mk(path: String, tile: Vector2i) -> Node2D:
	var m = load(path).new()
	world.add_child(m)
	m.setup(world, tile)
	return m

func _win(salt: String, tile: Vector2i, want: bool) -> int:
	for k in 600:
		if EL.roll(int(GameState.run_seed), salt, tile, k) == want:
			return k
	return -1

func _s2() -> void:
	# slime: hp x2 + dmg x1.5 (канал var dmg)
	var t := Vector2i(2, 6)
	var ord_w := _win("t47", t, true)
	var ord_l := _win("t47", t, false)
	check("S2 найдены выигрышный (%d) и проигрышный (%d) ординалы" % [ord_w, ord_l], ord_w >= 0 and ord_l >= 0)
	var s_n := _mk("res://scripts/slime.gd", t)
	var s_l := _mk("res://scripts/slime.gd", t)
	var s_e := _mk("res://scripts/slime.gd", t)
	check("S2 проигрышный ролл не делает элитой", not EL.apply(s_l, "t47", t, ord_l))
	check("S2 выигрышный ролл делает элитой", EL.apply(s_e, "t47", t, ord_w))
	check("S2 флаг meta elite только у элиты", bool(s_e.get_meta("elite", false)) and not bool(s_l.get_meta("elite", false)))
	check("S2 слайм: hp x2 (%d -> %d)" % [s_n.hp, s_e.hp], int(s_e.hp) == int(round(float(s_n.hp) * 2.0)))
	check("S2 слайм: удар x1.5 (%d -> %d)" % [s_n.dmg, s_e.dmg], int(s_e.dmg) == maxi(1, int(round(float(s_n.dmg) * 1.5))))
	# archer/wraith/swarmling: канал dmg_mult (стрелы и контакт считают от него)
	var t2 := Vector2i(4, 6)
	var ow2 := _win("t47b", t2, true)
	for pair in [["res://scripts/mob_archer.gd", "лучник"], ["res://scripts/mob_wraith.gd", "тенеплёт"], ["res://scripts/mob_swarmling.gd", "мглокрыс"]]:
		var p_n := _mk(String(pair[0]), t2)
		var p_e := _mk(String(pair[0]), t2)
		var ok := EL.apply(p_e, "t47b", t2, ow2)
		check("S2 %s: стал элитным на выигрышном ординале" % String(pair[1]), ok)
		check("S2 %s: dmg_mult x1.5 (%.2f -> %.2f)" % [String(pair[1]), float(p_n.dmg_mult), float(p_e.dmg_mult)],
			is_equal_approx(float(p_e.dmg_mult), float(p_n.dmg_mult) * 1.5))
		check("S2 %s: hp x2 с max_hp синхронно" % String(pair[1]),
			int(p_e.hp) == int(round(float(p_n.hp) * 2.0)) and int(p_e.max_hp) == int(round(float(p_n.max_hp) * 2.0)))
		# вердикт: скорость та же — элита не трогает множитель скорости t28
		if "feel_spd_mult" in p_e:
			check("S2 %s: множитель скорости не тронут" % String(pair[1]),
				is_equal_approx(float(p_e.feel_spd_mult), float(p_n.feel_spd_mult)))
		p_n.free()
		p_e.free()
	# украшение: аура + подпись (t26-вид по kill_kind), тумблер гасит украшение,
	# но не статы
	check("S2 элита: аура EliteAura под тумблером bold_fx", s_e.get_node_or_null("EliteAura") != null)
	var lbl: Label = s_e.get_node_or_null("ElitePlate") as Label
	check("S2 элита: подпись «Элитный Слайм»", lbl != null and String(lbl.text) == "Элитный Слайм")
	var wt := _mk("res://scripts/mob_wraith.gd", t2)
	wt.name = "T47Wraith"
	wt.kill_kind = "whisperer"
	check("S2 подпись вида: kill_kind перебивает семейное имя", EL.apply(wt, "t47v", t2, _win("t47v", t2, true))
		and String((wt.get_node_or_null("ElitePlate") as Label).text) == "Элитный Снежный шептун")
	wt.free()
	GameState.bold_fx = false
	var t3 := Vector2i(8, 6)
	var s_off := _mk("res://scripts/slime.gd", t3)
	var ok_off := EL.apply(s_off, "t47off", t3, _win("t47off", t3, true))
	check("S2 bold_fx OFF: элитизация всё равно случилась (статы — не украшение)", ok_off and int(s_off.hp) > int(s_n.hp))
	check("S2 bold_fx OFF: ни ауры, ни подписи (закон t23)", s_off.get_node_or_null("EliteAura") == null and s_off.get_node_or_null("ElitePlate") == null)
	GameState.bold_fx = true
	# t44 (27.11, находка ворот t39): узел без скрипта — get_script() в null.
	# Модуль обязан быть тотально безопасным на обоих входах (apply/apply_named).
	var bare := Node2D.new()
	check("S2/t44: apply() без скрипта = false без SCRIPT ERROR", not EL.apply(bare, "t44", Vector2i(0, 0), 0))
	check("S2/t44: apply_named() без скрипта = false без SCRIPT ERROR", not EL.apply_named(bare, "Т44"))
	bare.free()
	s_off.free()
	s_n.free()
	s_l.free()
	s_e.free()

# ----------------------------------------------------------------- награда
func _s4() -> void:
	var gold0: int = GameState.gold
	var mats0: Dictionary = GameState.materials.duplicate(true)
	var herbs0: int = int(GameState.herbs)
	var pity0: int = int(GameState.elite_pity)
	var e_dummy = load("res://scripts/slime.gd").new()
	e_dummy.set_meta("elite", true)
	var n_dummy = load("res://scripts/slime.gd").new()
	Loot.test_roll = 0.05
	# Серебро ровно ×3. Точность измерений: randi_range НЕ под test_roll ->
	# три прохода с одним seed(777); первый убийственный проход в стенде
	# платит ачивку first_blood (+10 золота) — базовую линию снимаем тёплым
	# обычным киллом, дальше дельты чистые: элита = 3×ролла, обычный = ролл.
	GameState.gold = 0
	seed(777)
	Loot.on_mob_death("slime", Vector2.ZERO, null, n_dummy)
	var a1 := GameState.gold
	seed(777)
	Loot.on_mob_death("slime", Vector2.ZERO, null, e_dummy)
	var a2 := GameState.gold
	seed(777)
	Loot.on_mob_death("slime", Vector2.ZERO, null, n_dummy)
	var a3 := GameState.gold
	var d_e := a2 - a1
	var d_n := a3 - a2
	check("S4 серебро: обычный ролл %d, элита %d == ровно x3" % [d_n, d_e], d_n > 0 and d_e == 3 * d_n)
	# Доп. гарантированный предмет = первая item/mat строка таблицы (у слайма
	# это трава). Мерило: обычный килл +1 трава (шанс 0.12 под test_roll 0.05),
	# элита +2 (таблица + гарантированный). Шкура — шанс 1.0 — у обоих +1.
	var herb0: int = int(GameState.herbs)
	var h0 := int(GameState.materials.get("hide", 0))
	Loot.on_mob_death("slime", Vector2.ZERO, null, n_dummy)
	var herb_n: int = int(GameState.herbs) - herb0
	var h1 := int(GameState.materials.get("hide", 0))
	Loot.on_mob_death("slime", Vector2.ZERO, null, e_dummy)
	var herb_e: int = int(GameState.herbs) - herb_n - herb0
	var h2 := int(GameState.materials.get("hide", 0))
	check("S4 обычный: таблица (трав +1, шкур +1) без гарантии (%d, %d)" % [herb_n, h1 - h0], herb_n == 1 and h1 - h0 == 1)
	check("S4 элита: +1 дополнительный гарантированный предмет (%d травы, %d шкур)" % [herb_e, h2 - h1], herb_e == 2 and h2 - h1 == 1)
	# pity: +1 за элиту, 0 за обычного (к этому месту убиты две элиты: a2 и h2)
	check("S4 pity == числу элитных килов (%d)" % (int(GameState.elite_pity) - pity0), int(GameState.elite_pity) - pity0 == 2)
	Loot.on_mob_death("slime", Vector2.ZERO, null, n_dummy)
	check("S4 pity не растёт с обычных (%d)" % (int(GameState.elite_pity) - pity0), int(GameState.elite_pity) - pity0 == 2)
	Loot.test_roll = -1.0
	e_dummy.free()
	n_dummy.free()
	GameState.gold = gold0
	GameState.materials = mats0.duplicate(true)
	GameState.herbs = herbs0
	GameState.elite_pity = pity0

# -------------------------------------------------------------------- сейв
func _s5() -> void:
	GameState.elite_pity = 7
	var d: Dictionary = GameState.to_dict()
	check("S5 to_dict несёт elite_pity (аддитивно к v4)", int(d.get("elite_pity", -1)) == 7)
	var gs2 = load("res://scripts/game_state.gd").new()
	gs2.from_dict(d)
	check("S5 roundtrip: fresh-инстанс прочитал pity", int(gs2.elite_pity) == 7)
	var d_leg: Dictionary = d.duplicate(true)
	d_leg.erase("elite_pity")
	var gs3 = load("res://scripts/game_state.gd").new()
	gs3.elite_pity = 42
	gs3.from_dict(d_leg)
	check("S5 легаси-сейв без ключа = 0 (миграции нет)", int(gs3.elite_pity) == 0)
	gs2.free()
	gs3.free()
	GameState.elite_pity = 0

# ------------------------------------------------------------------- гейты
func _count_elite_excl(n: Node, skip: Node) -> int:
	if n == skip:
		return 0
	var c := 0
	if n.has_meta("elite") and bool(n.get_meta("elite")):
		c += 1
	for ch in n.get_children():
		c += _count_elite_excl(ch, skip)
	return c

func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func _s6() -> void:
	# free() в Godot отложен: до счёча прогоняем кадры, чтобы разобранные
	# стендовые мобы реально вышли из дерева
	await pump(4)
	# Живой мир boot: Пепелище строится вместе с миром и спавнер элит там
	# РАБОТАЕТ (это и есть интеграция) — значит нуль элит требован ВНЕ
	# Пепелища: дерёвня/пещера/мирские узлы вне жребия со структуры спавнера.
	var az: Node = world.get_node_or_null("Ashen")
	var in_ashen := _count_elite_excl(az, null) if az != null else -1
	var stray := _count_elite_excl(world, az)
	check("S6 живой мир: вне Пепелища ноль элит (внутри — %d, спавнер жив; чужих — %d)" % [in_ashen, stray],
		stray == 0 and in_ashen >= 0)
	for path in ["village_zone.gd", "mini_zone.gd", "mob_boss2.gd", "dungeon_zone.gd", "world.gd"]:
		check("S6 гейт: %s не вызывает ELITES (мирные/квестовые/мини-боссы вне жребия)" % path,
			not _src("res://scripts/" + path).contains("ELITES."))
	for path in ["biome_zone.gd", "ashen_zone.gd"]:
		check("S6 разводка: %s зовёт ELITES.apply" % path, _src("res://scripts/" + path).contains("ELITES.apply("))
	# скорость брут-элиты в биоме — то же правило (brute канал dmg): статично
	check("S6 brute — в таблице семейств элит", EL.FAM_BY_SCRIPT.has("brute"))
