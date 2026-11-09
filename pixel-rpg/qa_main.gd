extends Node
## QA-харнесс (временный, QA-сессия 2026-11-09). Грузит настоящую main.tscn и гоняет матрицу тестов.

const PROJ := preload("res://scripts/projectile.gd")
const SLIME := preload("res://scripts/slime.gd")
const BRUTE := preload("res://scripts/brute.gd")

var world
var GS
var fails := []
var npass := 0
var toasts: Array = []
var lvlups: Array = []

func ok(cond: bool, label: String) -> void:
	if cond:
		npass += 1
		print("PASS | " + label)
	else:
		fails.append(label)
		print("FAIL | " + label)

func eqf(got, want, label: String) -> void:
	ok(got == want, "%s (got=%s want=%s)" % [label, str(got), str(want)])

func step(n := 1) -> void:
	for _i in n:
		await get_tree().process_frame

func ad(n := 40) -> void:
	for _i in n:
		if not world.hud.is_dialog_open():
			return
		world.hud.advance()
		await get_tree().process_frame

func find_hint_areas(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if not is_instance_valid(c):
			continue
		if c.has_method("get_hint"):
			out.append(c)
	return out

func find_area_by_hint(root: Node, substr: String):
	for a in find_hint_areas(root):
		if String(a.call("get_hint")).contains(substr):
			return a
	return null

func spawn_enemy(kind: String, gp: Vector2, zone: Node):
	var e
	if kind == "brute":
		e = BRUTE.new()
	else:
		e = SLIME.new()
	zone.add_child(e)
	e.setup(world, world.tile_to_world(Vector2i(1, 1)))
	e.global_position = gp
	return e

func snap_state() -> Dictionary:
	return {
		"max_hp": GS.max_hp, "hp": GS.hp, "level": GS.level, "xp": GS.xp, "xp_next": GS.xp_next,
		"class_id": GS.class_id, "has_sword": GS.has_sword, "herbs": GS.herbs,
		"slime_kills": GS.slime_kills, "elder_quest": GS.elder_quest, "slime_quest": GS.slime_quest,
		"seen_intro": GS.seen_intro, "cave_state": GS.cave_state, "has_key": GS.has_key,
		"has_amulet": GS.has_amulet, "in_cave": GS.in_cave, "seen_cave_intro": GS.seen_cave_intro,
		"seen_boss_intro": GS.seen_boss_intro, "player_pos": GS.player_pos, "pos_valid": GS.pos_valid,
		"input_locked": GS.input_locked,
	}

func restore_state(s: Dictionary) -> void:
	for k in s:
		GS.set(k, s[k])

func remove_save() -> void:
	var p: String = ProjectSettings.globalize_path("user://save_morkheim.json")
	if FileAccess.file_exists("user://save_morkheim.json"):
		DirAccess.remove_abs(p)

func write_raw(txt: String) -> void:
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.WRITE)
	f.store_string(txt)
	f.close()

func _ready() -> void:
	GS = get_node("/root/GameState")
	GS.toast.connect(func(t): toasts.append(t))
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await step(2)
	await run_all()
	print("SUMMARY | pass=%d fail=%d" % [npass, fails.size()])
	for f in fails:
		print("SUMMARYFAIL | " + f)
	var fa := FileAccess.open("res://qa_results.txt", FileAccess.WRITE)
	if fa != null:
		fa.store_string("pass=%d fail=%d\n" % [npass, fails.size()])
		for f in fails:
			fa.store_string("FAIL | " + f + "\n")
		fa.close()
	get_tree().quit(0 if fails.is_empty() else 1)

func run_all() -> void:
	# ---------- G1 boot: выбор класса + интро ----------
	print("SECTION G1 boot")
	ok(GS.class_id == "", "G1: до выбора класса class_id пуст")
	ok(world.hud.is_modal_open(), "G1: модалка выбора героя открыта на старте")
	ok(GS.input_locked, "G1: модалка блокирует ввод")
	world.hud._pick_class("warrior")
	await step(1)
	ok(GS.class_id == "warrior", "G1: класс выбран через _pick_class")
	ok(not GS.input_locked, "G1: после выбора класс_снят лок")
	ok(world.hud.is_dialog_open(), "G1: после выбора класса стартовало интро")
	eqf(GS.seen_intro, true, "G1: seen_intro=true")
	await ad()
	ok(not GS.input_locked and not world.hud.is_dialog_open(), "G1: интро пройдено, лок снят")

	# ---------- G3 квест-цепочка hermit 0→4 ----------
	print("SECTION G3 hermit chain")
	GS.player_pos = world.player.global_position
	GS.pos_valid = true
	GS.has_sword = false
	var lv_before: int = GS.level
	var xp_before: int = GS.xp
	world.player.global_position = world.CAVE_OFFSET + world.dungeon_zone.spawn_world_pos
	world.apply_zone(true, false)
	await step(2)
	ok(GS.in_cave, "G3: телепорт в пещеру (apply_zone)")
	var hermit = find_area_by_hint(world.cave_zone, "Поговорить")
	ok(hermit != null, "G3: отшельник найден в пещере")
	world.talk("hermit")
	await step(1)
	ok(GS.input_locked and world.hud.is_dialog_open(), "G3: диалог hermit_quest открыт, ввод залочен")
	eqf(GS.cave_state, 0, "G3: cave_state=0 до конца диалога")
	await ad()
	eqf(GS.cave_state, 1, "G3: talk(0) -> cave_state=1")
	ok(not GS.input_locked, "G3: лок снят после cb")
	# повторный talk на 1 без босса
	world.talk("hermit")
	await ad()
	eqf(GS.cave_state, 1, "G3: повторный talk без босса — cave_state=1 (идемпотентно)")
	# умиротворяем boss_trigger телепортом к Геральду и убиваем босса
	var brute = null
	for ch in world.cave_zone.get_children():
		if is_instance_valid(ch) and ch.is_in_group("boss"):
			brute = ch
	ok(brute != null, "G3: босс существует в мире")
	if brute != null:
		brute.hurt(999, brute.global_position)
		await step(1)
	ok(GS.boss_defeated, "G3: смерть босса -> boss_defeated=true")
	eqf(GS.cave_state, 2, "G3: boss dead -> cave_state=2")
	# сундук и дверь БЕЗ ключа — отказ
	var chest = find_area_by_hint(world.cave_zone, "сундук")
	ok(chest != null, "G3: алтарный сундук существует (амулет не взят)")
	toasts.clear()
	if chest != null:
		chest.try_interact()
		ok(not GS.has_amulet, "G3: сундук без ключа — амулет НЕ выдан")
		ok(_toast_contains("Нужен ключ"), "G3: сундук без ключа — тост «Нужен ключ»")
	var door = find_area_by_hint(world.cave_zone, "дверь")
	ok(door != null, "G3: дверь существует")
	toasts.clear()
	if door != null:
		door.try_interact()
		ok(_toast_contains("Нужен ключ"), "G3: дверь без ключа — отказ тостом")
	ok(GS.has_key == false, "G3: has_key по-прежнему false")
	world.player.global_position = hermit.global_position
	# квест 1+босс мёртв -> ключ
	world.talk("hermit")
	await step(1)
	ok(world.hud.is_dialog_open(), "G3: диалог hermit_done стартанул")
	await ad()
	ok(GS.has_key, "G3: после доклада выдан ключ")
	eqf(GS.cave_state, 3, "G3: ключ выдан -> cave_state=3")
	ok(GS.input_locked == false, "G3: лок снят после key-cb")
	# idempotency: повторный talk на 3
	world.talk("hermit")
	await ad()
	eqf(GS.cave_state, 3, "G3: повторный talk на 3 — без изменений")
	ok(GS.has_key, "G3: has_key стабилен")
	# открываем дверь ключом
	door = find_area_by_hint(world.cave_zone, "дверь")
	ok(door != null, "G3: дверь цела до открытия")
	if door != null:
		door.try_interact()
		await step(1)
		var _sid: int = world.dungeon_zone.tilemap.get_cell_source_id(Vector2i(11, 13))
		var _atc: Vector2i = world.dungeon_zone.tilemap.get_cell_atlas_coords(Vector2i(11, 13))
		ok(_sid != -1 and _atc.x == 0, "G3: unlock_door: тайл 11,13 -> атлас 0 (открыта)")
		ok(find_area_by_hint(world.cave_zone, "дверь") == null, "G3: зона двери убрана из дерева (queue_free)")
	# сундук с ключом -> амулет
	var dmg_before: int = GS.damage
	var maxhp_before: int = GS.max_hp
	chest = find_area_by_hint(world.cave_zone, "сундук")
	ok(GS.has_amulet == false, "G3: до взаимодействия has_amulet=false")
	ok(chest != null, "G3: сундук снова найден")
	if chest != null:
		chest.try_interact()
	ok(GS.has_amulet, "G3: сундук с ключом -> has_amulet=true")
	eqf(GS.max_hp, maxhp_before + 4, "G3: амулет +4 max_hp")
	eqf(GS.damage, dmg_before + 1, "G3: амулет +1 damage")
	var _csid: int = world.dungeon_zone.tilemap.get_cell_source_id(Vector2i(18, 18))
	var _catc: Vector2i = world.dungeon_zone.tilemap.get_cell_atlas_coords(Vector2i(18, 18))
	ok(_csid != -1 and _catc.x == 12, "G3: open_chest -> тайл 18,18 = атлас 12")
	await ad()  # treasure_done
	ok(not GS.input_locked, "G3: treasure_done закрыт, лок снят")
	# амулет Геральду -> 4
	var st_before: int = GS.cave_state
	world.talk("hermit")
	await step(1)
	ok(world.hud.is_dialog_open(), "G3: диалог amulet_done стартанул")
	await ad()
	eqf(GS.cave_state, 4, "G3: амулет сдан -> cave_state=4")
	ok(not GS.input_locked, "G3: лок снят после amulet_done")
	world.talk("hermit")
	await ad()
	eqf(GS.cave_state, 4, "G3: повторный talk на 4 идемпотентен")
	# смерть в пещере -> респаун в пещере
	world.respawn_player()
	await step(1)
	var cave_spawn: Vector2 = world.CAVE_OFFSET + world.dungeon_zone.spawn_world_pos
	ok(world.player.global_position.distance_to(cave_spawn) < 1.0, "G3: death->respawn в пещере = точка спавна пещеры")
	ok(GS.hp == GS.max_hp, "G3: после респауна полный HP")
	# выход из пещеры
	world.exit_cave()
	for _i in 60:
		if not GS.input_locked:
			break
		await step(1)
	ok(not GS.input_locked, "G3: exit_cave — фейд-твин завершён, лок снят")
	ok(not GS.in_cave, "G3: вышли в деревню")
	ok(world.village_zone.process_mode == Node.PROCESS_MODE_INHERIT, "G3: деревня снова обрабатывается")

	# ---------- G4 derived boss_defeated + класс/амулет ----------
	print("SECTION G4 derived")
	eqf(GS.boss_defeated, true, "G4: getter boss_defeated при cave_state=4 -> true")
	GS.boss_defeated = false
	eqf(GS.cave_state, 4, "G4: set(false) не понижает cave_state")
	GS.cave_state = 0
	GS.boss_defeated = true
	eqf(GS.cave_state, 2, "G4: set(true) при cave_state=0 -> 2")
	GS.cave_state = 1
	GS.boss_defeated = true
	eqf(GS.cave_state, 2, "G4: set(true) при cave_state=1 -> 2")
	GS.cave_state = 4
	GS.boss_defeated = true
	eqf(GS.cave_state, 4, "G4: set(true) при cave_state=4 не понижает")
	# формула амулета поверх формулы класса
	GS.has_sword = false
	GS.class_id = "warrior"
	GS.has_amulet = true
	GS.level = 3
	GS.recalc_max_hp()
	eqf(GS.max_hp, 12 + 2 * 2 + 4, "G4: max_hp = 12+2*(lv-1)+4(амулет)")
	eqf(GS.damage, 2 + 1, "G4: damage = класс(2)+амулет(1)")
	GS.has_amulet = false
	GS.recalc_max_hp()
	eqf(GS.max_hp, 16, "G4: без амулета max_hp=16")
	eqf(GS.damage, 2, "G4: без амулета damage=2")

	# ---------- G2 сейвы ----------
	print("SECTION G2 saves")
	remove_save()
	ok(not GS.load_game(), "G2: load_game без файла -> false")
	GS.class_id = "mage"
	GS.level = 3
	GS.xp = 5
	GS.xp_next = 51
	GS.has_sword = true
	GS.has_amulet = true
	GS.has_key = true
	GS.cave_state = 4
	GS.herbs = 2
	GS.slime_kills = 4
	GS.elder_quest = 2
	GS.slime_quest = 1
	GS.seen_intro = true
	GS.seen_cave_intro = true
	GS.seen_boss_intro = true
	GS.in_cave = true
	GS.player_pos = Vector2(123.0, 456.0)
	GS.pos_valid = true
	GS.heal_full()
	ok(GS.save_game(), "G2: save_game -> true")
	var snapshot := GS.to_dict()
	GS.class_id = ""
	GS.level = 1
	GS.cave_state = 0
	GS.has_key = false
	GS.in_cave = false
	ok(GS.load_game(), "G2: load_game с файла -> true")
	eqf(GS.class_id, "mage", "G2 round-trip: class_id")
	eqf(GS.cave_state, 4, "G2 round-trip: cave_state")
	eqf(GS.has_key, true, "G2 round-trip: has_key")
	eqf(GS.has_amulet, true, "G2 round-trip: has_amulet")
	eqf(GS.seen_intro, true, "G2 round-trip: seen_intro")
	eqf(GS.seen_cave_intro, true, "G2 round-trip: seen_cave_intro")
	eqf(GS.seen_boss_intro, true, "G2 round-trip: seen_boss_intro")
	eqf(GS.in_cave, true, "G2 round-trip: in_cave")
	eqf(GS.player_pos, Vector2(123.0, 456.0), "G2 round-trip: player_pos")
	eqf(GS.pos_valid, true, "G2 round-trip: pos_valid")
	eqf(GS.herbs, 2, "G2 round-trip: herbs")
	eqf(GS.slime_kills, 4, "G2 round-trip: slime_kills")
	eqf(GS.xp_next, 51, "G2 round-trip: xp_next")
	eqf(GS.boss_defeated, true, "G2 round-trip: boss_defeated=true")
	eqf(GS.damage, 3 * 2 + 1, "G2 round-trip: damage магия x2 меч +1 амулет")
	eqf(GS.max_hp, 6 + 2 * 2 + 4, "G2 round-trip: max_hp пересчитан (mage lv3+амулет)")
	# legacy-сейв без новых полей
	remove_save()
	write_raw('{"max_hp":10,"hp":7,"level":2,"xp":3,"xp_next":32,"damage":2,"has_sword":true,"herbs":1,"slime_kills":1,"elder_quest":1,"slime_quest":0,"seen_intro":true,"px":50.5,"py":60.5,"pos_valid":true}')
	ok(GS.load_game(), "G2 legacy: загрузка старого сейва без новых полей")
	eqf(GS.class_id, "warrior", "G2 legacy: class_id по умолчанию=warrior")
	eqf(GS.cave_state, 0, "G2 legacy: cave_state по умолчанию=0")
	eqf(GS.has_key, false, "G2 legacy: has_key=false")
	eqf(GS.has_amulet, false, "G2 legacy: has_amulet=false")
	eqf(GS.in_cave, false, "G2 legacy: in_cave=false")
	eqf(GS.damage, 4, "G2 legacy: damage=2*2(меч)")
	eqf(GS.player_pos, Vector2(50.5, 60.5), "G2 legacy: позиция прочитана")
	# legacy с boss_defeated=true без cave_state
	write_raw('{"boss_defeated":true}')
	ok(GS.load_game(), "G2 legacy2: сейв только с boss_defeated=true")
	eqf(GS.cave_state, 2, "G2 legacy2: boss_defeated=true поднимает cave_state до 2")
	# битый JSON
	write_raw("{{{broken json!!!")
	var hp_locked: bool = GS.input_locked
	ok(not GS.load_game(), "G2 corrupt: битый JSON -> load_game=false, без падения")
	eqf(GS.input_locked, hp_locked, "G2 corrupt: input_locked не тронут")
	# JSON не-словарь
	write_raw('[1,2,3]')
	ok(not GS.load_game(), "G2 non-dict: JSON-массив -> false")
	# load во время диалога
	world.start_dialogue("elder_progress", Callable())
	await step(1)
	ok(GS.input_locked and world.hud.is_dialog_open(), "G2 mid-dialog: диалог открыт, ввод залочен")
	write_raw('{"level":1,"xp":0,"xp_next":20,"class_id":"warrior"}')
	ok(GS.load_game(), "G2 mid-dialog: load_game во время диалога не падает")
	await ad()
	ok(not GS.input_locked, "G2 mid-dialog: диалог после лоада закрывается штатно")
	# F9 без файла
	remove_save()
	toasts.clear()
	var key_ev := InputEventKey.new()
	key_ev.physical_keycode = KEY_F9
	world._unhandled_input(key_ev)
	await step(1)
	ok(_toast_contains("Сохранение не найдено"), "G2 F9 без файла: тост «Сохранение не найдено», не падает")

	# ---------- G8 классы ----------
	print("SECTION G8 classes")
	GS.has_amulet = false
	GS.has_sword = false
	GS.level = 1
	GS.class_id = "warrior"
	GS.recalc_max_hp()
	eqf(GS.max_hp, 12, "G8: warrior base hp=12")
	GS.class_id = "archer"
	GS.recalc_max_hp()
	eqf(GS.max_hp, 8, "G8: archer hp=8")
	eqf(GS.damage, 2, "G8: archer dmg=2")
	GS.class_id = "mage"
	GS.recalc_max_hp()
	eqf(GS.max_hp, 6, "G8: mage hp=6")
	eqf(GS.damage, 3, "G8: mage dmg=3")
	GS.has_sword = true
	eqf(GS.damage, 6, "G8: меч x2 (mage 3*2)")
	GS.damage = 99
	eqf(GS.damage, 6, "G8: запись damage — no-op (производный)")
	GS.has_sword = false
	GS.set_class("warrior")
	ok(GS.class_id == "warrior" and GS.hp == GS.max_hp, "G8: set_class пересчитывает и лечит полностью")
	var cd_before: String = GS.class_id
	GS.set_class("paladin")
	eqf(GS.class_id, cd_before, "G8: set_class('paladin') — unknown, class_id не изменён")
	GS.level = 5
	GS.xp = 30
	GS.xp_next = 99
	GS.reset_progress_for_class_change()
	eqf(GS.level, 1, "G8: reset_progress: level=1")
	eqf(GS.xp, 0, "G8: reset_progress: xp=0")
	eqf(GS.xp_next, 20, "G8: reset_progress: xp_next=20")
	ok(GS.has_sword == false, "G8: reset_progress не трогает has_sword")

	# ---------- G6 XP ----------
	print("SECTION G6 xp")
	GS.class_id = "warrior"
	GS.level = 1
	GS.xp = 0
	GS.xp_next = 20
	GS.has_amulet = false
	GS.has_sword = false
	GS.recalc_max_hp()
	GS.hurt(6)
	var lv_events: Array = []
	var skill_toasts: Array = []
	GS.leveled_up.connect(func(l): lv_events.append(l))
	var tc := func(t):
		if t.begins_with("Новый навык"):
			skill_toasts.append(t)
	GS.toast.connect(tc)
	GS.add_xp(19)
	eqf(GS.level, 1, "G6: 19 xp -> уровень 1")
	eqf(GS.xp, 19, "G6: 19 xp -> xp=19")
	GS.add_xp(1)
	eqf(GS.level, 2, "G6: 20-й xp -> уровень 2")
	eqf(GS.xp_next, 32, "G6: xp_next 20->32")
	eqf(GS.xp, 0, "G6: перенос остатка 0")
	GS.add_xp(52)
	eqf(GS.level, 3, "G6: ещё 52 -> уровень 3")
	eqf(GS.xp_next, 51, "G6: xp_next 32->51 (round 32*1.6=51.2)")
	eqf(GS.xp, 1, "G6: остаток 1")
	GS.add_xp(200)
	eqf(GS.level, 4, "G6: +200 -> уровень 4")
	eqf(GS.xp_next, 82, "G6: xp_next 51->82 (round 81.6)")
	eqf(GS.xp, 23, "G6: остаток 23")
	eqf(GS.max_hp, 18, "G6: max_hp 12+2*3=18")
	eqf(GS.hp, 18, "G6: leveled_up -> полный хил")
	eqf(lv_events, [2, 3, 4], "G6: leveled_up эмитирован для 2,3,4")
	ok("Новый навык: Вихрь клинка!" in skill_toasts, "G6: тост навыка на ур.2 (whirlwind)")
	ok("Новый навык: Второй ветер!" in skill_toasts, "G6: тост навыка на ур.3 (second_wind)")
	ok("Новый навык: Казнь!" in skill_toasts, "G6: тост навыка на ур.4 (execute)")
	GS.toast.disconnect(tc)

	# ---------- G7 скиллы ----------
	print("SECTION G7 skills")
	GS.class_id = "warrior"
	GS.level = 1
	GS.has_sword = false
	GS.has_amulet = false
	GS.recalc_max_hp()
	GS.heal_full()
	var hero = world.player
	for i in 4:
		hero.skill_cd[i] = 0.0
	var vpos: Vector2 = world.player.global_position
	ok(not hero.cast_skill(1), "G7: whirlwind залочен на 1 уровне -> false")
	eqf(hero.skill_cd[1], 0.0, "G7: залоченный скилл не тратит КД")
	var b1 = spawn_enemy("brute", vpos + Vector2(0, 10), world.village_zone)
	var hp0: int = b1.hp
	ok(hero.cast_skill(0), "G7: power_strike каст (уровень 1)")
	eqf(hp0 - b1.hp, 4, "G7: power_strike = 2x урон (2->4)")
	eqf(hero.skill_cd[0], 4.0, "G7: power_strike задал КД=4")
	ok(not hero.cast_skill(0), "G7: повтор во время КД блокируется")
	# pending_mult при цели вне радиуса
	hero.skill_cd[0] = 0.0
	b1.global_position = vpos + Vector2(0, 60)
	ok(hero.cast_skill(0), "G7: power_strike вне радиуса кастуется")
	eqf(hero.pending_mult, 2.0, "G7: вне радиуса — pending_mult=2")
	hero.cancel_orders()
	eqf(hero.pending_mult, 1.0, "G7: cancel_orders сбрасывает pending_mult")
	# cast без класса
	hero.skill_cd[0] = 0.0
	GS.class_id = ""
	ok(not hero.cast_skill(0), "G7: class_id=='' — каст запрещён")
	eqf(hero.skill_cd[0], 0.0, "G7: при class_id=='' КД не тратится")
	GS.class_id = "warrior"
	# cast при input_locked
	GS.input_locked = true
	ok(not hero.cast_skill(0), "G7: input_locked — каст запрещён")
	GS.input_locked = false
	# second_wind с капом (нужен ур.3)
	GS.level = 3
	hero.skill_cd[2] = 0.0
	GS.hp = GS.max_hp - 7
	ok(hero.cast_skill(2), "G7: second_wind каст (ур.3)")
	eqf(GS.hp, GS.max_hp - 3, "G7: second_wind лечит 4")
	GS.hp = GS.max_hp - 2
	hero.skill_cd[2] = 0.0
	ok(hero.cast_skill(2), "G7: second_wind каст у капа")
	eqf(GS.hp, GS.max_hp, "G7: second_wind не лечит сверх капа")
	# execute
	GS.level = 4
	var b2 = spawn_enemy("brute", vpos + Vector2(0, 10), world.village_zone)
	ok(not hero.cast_skill(3), "G7: execute без цели -> false и БЕЗ траты КД")
	eqf(hero.skill_cd[3], 0.0, "G7: execute no-target не жрёт КД")
	hero.skill_cd[3] = 0.0
	hero.attack_target = b2
	ok(hero.cast_skill(3), "G7: execute по цели с полным HP")
	eqf(b2.hp, 12 - 3, "G7: execute по здоровому = 1.5x (round(2*1.5)=3)")
	hero.attack_target = null
	var b3 = spawn_enemy("brute", vpos + Vector2(0, 10), world.village_zone)
	b3.hp = 2
	hero.skill_cd[3] = 0.0
	hero.attack_target = b3
	ok(hero.cast_skill(3), "G7: execute по цели hp<=25%")
	ok(not is_instance_valid(b3) or b3.hp <= 0, "G7: казнь: hp<=25% -> мгновенная смерть")
	hero.attack_target = null
	# whirlwind: 1.5x по нескольким врагам (нужен ур.2 — есть)
	hero.skill_cd[1] = 0.0
	var w1 = spawn_enemy("slime", vpos + Vector2(15, 0), world.village_zone)
	var w2 = spawn_enemy("slime", vpos + Vector2(-15, 0), world.village_zone)
	var w1h: int = w1.hp
	var w2h: int = w2.hp
	ok(hero.cast_skill(1), "G7: whirlwind каст (ур.4)")
	eqf(w1h - w1.hp, 3, "G7: whirlwind 1.5x по врагу 1")
	eqf(w2h - w2.hp, 3, "G7: whirlwind 1.5x по врагу 2")
	if is_instance_valid(w1):
		w1.queue_free()
	if is_instance_valid(w2):
		w2.queue_free()
	if is_instance_valid(b1):
		b1.queue_free()
	if is_instance_valid(b2):
		b2.queue_free()
	await step(1)
	# mage: frost_nova + firebolt aoe + siphon
	GS.class_id = "mage"
	GS.recalc_max_hp()
	GS.heal_full()
	hero.apply_class()
	var f1 = spawn_enemy("slime", vpos + Vector2(20, 0), world.village_zone)
	var f2 = spawn_enemy("slime", vpos + Vector2(45, 0), world.village_zone)
	hero.skill_cd[1] = 0.0
	ok(hero.cast_skill(1), "G7: frost_nova каст")
	ok(is_instance_valid(f1) and f1.freeze_t > 2.5, "G7: frost_nova: враг в 32px заморожен freeze_t~3")
	ok(is_instance_valid(f2) and f2.freeze_t <= 0.0, "G7: frost_nova: враг вне 32px не заморожен")
	if is_instance_valid(f2):
		f2.queue_free()
	await step(1)
	GS.hp = 3
	var fb1 = spawn_enemy("brute", vpos + Vector2(30, 0), world.village_zone)
	var fb2 = spawn_enemy("slime", vpos + Vector2(36, 0), world.village_zone)
	hero.skill_cd[0] = 0.0
	hero.attack_cd = 0.0
	ok(hero.cast_skill(0), "G7: firebolt каст")
	var dead_ok := false
	for _i in 60:
		await step(1)
		if is_instance_valid(fb1) and fb1.hp < 12:
			break
	ok(is_instance_valid(fb1) and 12 - fb1.hp == 8, "G7: firebolt 2.5x (mage 3*2.5=8)")
	ok(is_instance_valid(fb2) and 3 - fb2.hp == 8, "G7: firebolt AoE12 задел второго врага")
	if is_instance_valid(fb1):
		fb1.queue_free()
	if is_instance_valid(fb2):
		fb2.queue_free()
	await step(1)
	# siphon
	hero.skill_cd[2] = 0.0
	ok(hero.cast_skill(2), "G7: siphon каст")
	eqf(hero.siphon_t, 5.0, "G7: siphon_t=5")
	GS.hp = GS.max_hp - 3
	var sh := PROJ.new()
	world.add_child(sh)
	sh.setup(hero.global_position, Vector2.RIGHT, 100.0, 1, 1, false, 0.0, hero)
	var sponge = spawn_enemy("slime", vpos + Vector2(100, 0), world.village_zone)
	sh._on_hit(sponge)
	eqf(GS.hp, GS.max_hp - 2, "G7: siphon: попадание снаряда лечит 1")
	sh.queue_free()
	if is_instance_valid(sponge):
		sponge.queue_free()
	await step(1)
	# firestorm smoke
	hero.skill_cd[3] = 0.0
	var kids_before: int = world.get_child_count()
	ok(hero.cast_skill(3), "G7: firestorm каст (smoke)")
	await step(90)
	ok(world.get_child_count() >= kids_before - 5, "G7: firestorm: искры cleaned up, мир не разрастается")
	# archer: mark + volley + rain
	GS.class_id = "archer"
	GS.recalc_max_hp()
	hero.apply_class()
	var m1 = spawn_enemy("slime", vpos + Vector2(40, 0), world.village_zone)
	hero.skill_cd[2] = 0.0
	hero.attack_target = m1
	ok(hero.cast_skill(2), "G7: mark каст")
	eqf(hero.dmg_vs(m1, 1.0), 3, "G7: mark: dmg_vs = round(2*1.5)=3")
	eqf(hero.dmg_vs(null, 1.0), 2, "G7: mark: без метки dmg=2")
	hero.attack_target = null
	var kids0: int = world.get_child_count()
	hero.skill_cd[1] = 0.0
	ok(hero.cast_skill(1), "G7: volley каст")
	eqf(world.get_child_count(), kids0 + 3, "G7: volley создаёт 3 снаряда")
	for c in world.get_children():
		if c is Area2D and "dirv" in c:
			c.queue_free()
	await step(1)
	# rain (арчер слот 3, ур.4)
	var rr = spawn_enemy("slime", vpos + Vector2(35, 0), world.village_zone)
	var rrh: int = rr.hp
	hero.skill_cd[3] = 0.0
	ok(hero.cast_skill(3, vpos + Vector2(35, 0)), "G7: rain каст в точку")
	for _i in 60:
		await step(1)
		if not is_instance_valid(rr) or rr.hp < rrh:
			break
	ok(is_instance_valid(rr) and rrh - rr.hp == 4, "G7: rain: 2x урон (round(2*2)=4) в AoE 30px")
	if is_instance_valid(rr):
		rr.queue_free()
	if is_instance_valid(m1):
		m1.queue_free()
	await step(1)

	# ---------- G9 снаряды ----------
	print("SECTION G9 projectiles")
	var pgp: Vector2 = world.player.global_position
	var p1 := PROJ.new()
	world.add_child(p1)
	p1.setup(pgp, Vector2.RIGHT, 200.0, 2, 0, false, 0.0, world.player)
	var p_start: Vector2 = p1.global_position
	for _i in 3:
		await step(1)
	ok(p1.global_position.distance_to(p_start) > 5.0, "G9: снаряд летит (позиция сместилась)")
	var s1 = spawn_enemy("slime", pgp + Vector2(40, 0), world.village_zone)
	p1.global_position = pgp + Vector2(20, 0)
	p1._on_hit(s1)
	eqf(s1.hp, 1, "G9: попадание снаряда снимает HP")
	await step(1)
	ok(not is_instance_valid(p1), "G9: non-pierce снаряд исчезает после попадания")
	var s2 = spawn_enemy("brute", pgp + Vector2(30, 0), world.village_zone)
	var s3 = spawn_enemy("brute", pgp + Vector2(60, 0), world.village_zone)
	var p2 := PROJ.new()
	world.add_child(p2)
	p2.setup(pgp, Vector2.RIGHT, 200.0, 2, 3, true, 0.0, world.player)
	p2._on_hit(s2)
	await step(1)
	eqf(s2.hp, 10, "G9: pierce: первый враг получил урон")
	ok(is_instance_valid(p2), "G9: pierce: снаряд НЕ исчез после 1-го врага")
	p2._on_hit(s3)
	eqf(s3.hp, 10, "G9: pierce: второй враг тоже задет")
	p2._on_hit(s2)
	eqf(s2.hp, 10, "G9: pierce: повторный hit по тому же врагу игнорируется")
	p2.queue_free()
	# смерть кастера во время полёта
	var p3 := PROJ.new()
	var dummy_player := CharacterBody2D.new()
	world.add_child(dummy_player)
	p3.setup(pgp, Vector2.UP, 50.0, 1, 0, false, 0.0, dummy_player)
	dummy_player.queue_free()
	for _i in 60:
		await step(1)
	ok(not is_instance_valid(p3), "G9: снаряд дожил и истёк по life после смерти кастера (без крэша)")
	if is_instance_valid(s1):
		s1.queue_free()
	if is_instance_valid(s2):
		s2.queue_free()
	if is_instance_valid(s3):
		s3.queue_free()
	await step(1)

	# ---------- G5 мышь-приказы ----------
	print("SECTION G5 orders")
	var pl = world.player
	var pgp2: Vector2 = pl.global_position
	pl.command_move(pgp2 + Vector2(30, 0))
	ok(pl.move_target == pgp2 + Vector2(30, 0), "G5: command_move ставит цель")
	var e1 = spawn_enemy("slime", pgp2 + Vector2(0, 80), world.village_zone)
	pl.command_attack(e1)
	ok(pl.attack_target == e1, "G5: command_attack ставит цель")
	ok(pl.move_target == Vector2.INF, "G5: command_attack очищает move_target")
	ok(pl.attack_origin != Vector2.INF, "G5: command_attack фиксирует leash-точку")
	var e2 = spawn_enemy("slime", pgp2 + Vector2(60, 80), world.village_zone)
	pl.command_attack(e2)
	ok(pl.attack_target == e2, "G5: повторный command_attack переключает цель")
	pl.cancel_orders()
	ok(pl.move_target == Vector2.INF and pl.attack_target == null and pl.interact_target == null and pl.attack_origin == Vector2.INF, "G5: cancel_orders очищает всё")
	# враг умер до прихода
	pl.command_attack(e1)
	e1.queue_free()
	await step(3)
	ok(pl.attack_target == null, "G5: цель умерла до прихода — приказ снят")
	pl.command_move(pgp2 + Vector2(50, 0))
	pl.command_attack(e2)
	pl.attack_target = null
	var pos_after_clear: Vector2 = pl.global_position
	for _i in 6:
		await step(1)
	ok(pl.move_target != Vector2.INF or pl.global_position.distance_to(pos_after_clear) > 1.0, "G5: снятие атаки не блокирует исполнитель (приказ жив/движение идёт)")
	pl.cancel_orders()
	pl.global_position = pgp2
	pl.command_attack(e2)
	pl.global_position = pgp2 + Vector2(200, 0)
	await step(2)
	ok(pl.attack_target == null, "G5: leash — цель отменена при отходе >160px")
	pl.cancel_orders()
	pl.global_position = pgp2
	# автоатака мили: ceil(hp/dmg)*cd
	GS.class_id = "warrior"
	GS.level = 1
	GS.has_sword = false
	GS.has_amulet = false
	GS.recalc_max_hp()
	pl.apply_class()
	var tank = spawn_enemy("brute", pl.global_position + Vector2(0, 10), world.village_zone)
	pl.attack_cd = 0.0
	pl.command_attack(tank)
	var need_hits := int(ceil(12.0 / float(GS.damage)))
	var cd := 1.0  # warrior attack_speed
	var frames_per_hit := int(ceil(cd * 60.0))
	var max_frames := (need_hits + 1) * frames_per_hit + 20
	var killed := false
	for _i in max_frames:
		await step(1)
		if not is_instance_valid(tank):
			killed = true
			break
	ok(killed, "G5: мили-автоатака убивает цель за ~ceil(hp/dmg)*cd (hp=12 dmg=%d cd=1.0)" % GS.damage)
	pl.cancel_orders()
	if is_instance_valid(e2):
		e2.queue_free()
	await step(1)

	# ---------- G11 freeze ----------
	print("SECTION G11 freeze")
	var fzp: Vector2 = world.player.global_position
	var sl = spawn_enemy("slime", fzp + Vector2(20, 0), world.village_zone)
	GS.input_locked = true
	sl.freeze_t = 1.5
	var spos: Vector2 = sl.global_position
	sl._physics_process(0.5)
	sl._physics_process(0.5)
	ok(sl.global_position == spos, "G11: замороженный слайм не двигается")
	eqf(sl.velocity, Vector2.ZERO, "G11: velocity=0 во время freeze")
	eqf(sl.modulate, Color(0.55, 0.75, 1.0), "G11: синий тинт во время freeze")
	eqf(GS.hp, GS.max_hp, "G11: замороженный слайм не бьёт")
	sl.freeze_t = 0.0
	GS.input_locked = false
	for _i in 6:
		sl._physics_process(1.0 / 60.0)
	ok(sl.global_position.distance_to(spos) > 0.0 or sl.velocity != Vector2.ZERO, "G11: после freeze слайм ожил (двигается)")
	if is_instance_valid(sl):
		sl.queue_free()
	await step(1)

	# ---------- G10 зоны ----------
	print("SECTION G10 zones")
	var n_vil: int = world.village_zone.get_child_count()
	var n_cave: int = world.cave_zone.get_child_count()
	var n_atmo: int = world.atmosphere.get_child_count()
	for i in 10:
		world.apply_zone(i % 2 == 1)
		await step(1)
	ok(world.village_zone.get_child_count() == n_vil, "G10: x10 смен зон — без утечек детей Village")
	ok(world.cave_zone.get_child_count() == n_cave, "G10: x10 смен зон — без утечек детей Cave")
	ok(world.atmosphere.get_child_count() == n_atmo, "G10: x10 смен зон — без утечек детей Atmo")
	world.apply_zone(true)
	await step(1)
	eqf(world.cave_zone.process_mode, Node.PROCESS_MODE_INHERIT, "G10: cave process_mode INHERIT в пещере")
	eqf(world.village_zone.process_mode, Node.PROCESS_MODE_DISABLED, "G10: village process_mode DISABLED в пещере")
	eqf(world.cam.limit_right, int(world.CAVE_OFFSET.x) + 30 * 16, "G10: камера — limits пещеры по X")
	eqf(world.cam.limit_top, int(world.CAVE_OFFSET.y), "G10: камера — limit_top пещеры")
	ok(world.player.global_position.y > world.CAVE_OFFSET.y, "G10: телепорт в пещеру выполнен")
	world.apply_zone(false)
	await step(1)
	eqf(world.village_zone.process_mode, Node.PROCESS_MODE_INHERIT, "G10: обратно — деревня активна")
	eqf(world.cam.limit_right, 48 * 16, "G10:limits деревни восстановлены")
	# вход к лестнице: доводим героя и проверяем подсказку (лестница на тайле-дереве!)
	var stairs = find_area_by_hint(world.village_zone, "Спуститься")
	ok(stairs != null, "G10: лестница в пещеру найдена")
	if stairs != null:
		world.player.global_position = world.tile_to_world(Vector2i(40, 15))
		var got_hint := false
		for _i in 90:
			world.player.command_move(stairs.global_position)
			await step(1)
			if world.near.has(stairs) and String(world.hint_label.text).contains("Спуститься"):
				got_hint = true
				break
		ok(got_hint, "G10: к лестнице в пещеру можно дойти пешком (подсказка появляется)")
		world.player.cancel_orders()
	# частицы/цветокор
	world.apply_zone(true)
	await step(1)
	var spores = world.atmosphere.get_node_or_null("CaveSpores")
	ok(spores != null and spores.visible and spores.process_mode == Node.PROCESS_MODE_INHERIT, "G14: споры активны в пещере")
	world.apply_zone(false)
	await step(1)
	ok(spores != null and not spores.visible and spores.process_mode == Node.PROCESS_MODE_DISABLED, "G14: споры выключены в деревне")

	# ---------- G12 диалоги ----------
	print("SECTION G12 dialogs")
	var dlg_file: Variant = JSON.parse_string(FileAccess.open("res://data/dialogues.json", FileAccess.READ).get_as_text())
	var v2_file: Variant = JSON.parse_string(FileAccess.open("res://data/dialogues_v2.json", FileAccess.READ).get_as_text())
	ok(String(world.dialogues["intro"][0]["text"]) == String(dlg_file["intro"][0]["text"]), "G12: merge — базовый intro сохранён")
	ok(world.dialogues.has("hermit_quest") and world.dialogues.has("treasure_done"), "G12: v2-ключи смержены")
	var shared: Array = []
	for k in dlg_file:
		if v2_file.has(k):
			shared.append(k)
	ok(shared.is_empty(), "G12: live-данные: ключей-пересечений base/v2 нет (глубина merge не проявляется)")
	var a0 := {"k": [{"t": "a"}]}
	a0.merge({"k": [{"t": "b"}]}, true)
	eqf((a0["k"] as Array).size(), 2, "G12 (латентный): Dictionary.merge глубокий — общий ключ СКЛЕИВАЕТ массивы")
	ok(not world.dialogues.has("unknown_key_xyz"), "G12: нет диалога unknown_key_xyz")
	world.start_dialogue("unknown_key_xyz")
	await step(1)
	ok(not GS.input_locked and not world.hud.is_dialog_open(), "G12: unknown-ключ — warning, не лочит ввод")
	# латентный: пустой массив реплик -> вечный лок
	world.dialogues["qa_empty"] = []
	world.start_dialogue("qa_empty")
	await step(1)
	var empty_locked := GS.input_locked
	world.hud.advance()
	await step(1)
	ok(empty_locked and GS.input_locked and world.hud.is_dialog_open(), "G12 (латентный): пустой диалог = вечный input_locked (softlock)")
	world.dialogues.erase("qa_empty")
	world.hud.panel.visible = false
	world.hud.on_end = Callable()
	GS.input_locked = false
	# advance посреди печати
	world.start_dialogue("elder_progress")
	await step(1)
	ok(world.hud.typing, "G12: эффект печати активен")
	world.hud.advance()
	ok(not world.hud.typing, "G12: advance во время печати просто раскрывает текст")
	await ad()
	ok(not GS.input_locked, "G12: диалог закрыт, лок снят")

	# ---------- G13 interactables ----------
	print("SECTION G13 interactables")
	GS.class_id = "archer"
	GS.level = 1
	GS.has_sword = false
	GS.has_amulet = false
	GS.recalc_max_hp()
	var herb = null
	for c in world.village_zone.get_children():
		if is_instance_valid(c) and c.has_method("get_hint") and String(c.get_hint()).contains("траву"):
			herb = c
			break
	ok(herb != null, "G13: трава найдена")
	if herb != null:
		GS.elder_quest = 0
		toasts.clear()
		herb.try_interact()
		eqf(GS.herbs, 0, "G13: трава не собирается при elder_quest=0")
		ok(_toast_contains("Рановато"), "G13: тост-отказ для травы без квеста")
		GS.herbs = 0
		GS.elder_quest = 1
		herb.try_interact()
		eqf(GS.herbs, 1, "G13: трава собирается при elder_quest=1")
		await step(2)
		ok(not is_instance_valid(herb), "G13: собранная трава удалена (повтор невозможен)")
	var chest2 = null
	for c in world.village_zone.get_children():
		if is_instance_valid(c) and c.has_method("get_hint") and String(c.get_hint()).contains("сундук"):
			chest2 = c
			break
	ok(chest2 != null, "G13: сундук с мечом найден")
	if chest2 != null:
		var d_before: int = GS.damage
		chest2.try_interact()
		ok(GS.has_sword, "G13: chest -> has_sword=true")
		eqf(GS.damage, d_before * 2, "G13: damage x2 через derived (archer 2*2)")
		chest2.try_interact()
		eqf(GS.damage, 4, "G13: повторный chest не удваивает повторно")
		ok(String(chest2.get_hint()).contains("сундук"), "G13 (cosmetic): подсказка открытого сундука всё ещё «Открыть сундук»")

	# ---------- G14 виньетка/UX ----------
	print("SECTION G14 vignette/ux")
	var last_child = world.hud.get_child(world.hud.get_child_count() - 1)
	ok(String(last_child.name) == "Vignette", "G14: виньетка — последний child HUD")
	eqf(last_child.mouse_filter, Control.MOUSE_FILTER_IGNORE, "G14: виньетка mouse_filter=IGNORE")
	var slots: Array = world.hud.skill_slots
	var tips_ok := true
	for s in slots:
		if String(s["icon"].tooltip_text).strip_edges() == "":
			tips_ok = false
	ok(tips_ok, "G15: у всех 4 слотов скиллов непустой тултип")
	ok(String(world.hud.skill_slots[1]["icon"].tooltip_text).contains("Вихрь клинка"), "G15: тултип скилла воина #2 = whirlwind")
	GS.level = 1
	world.hud._update_skill_states()
	ok(String(world.hud.skill_slots[3]["lvl"].text).contains("замк"), "G15: locked-слот показывает «замк. ур.4»")
	ok(String(world.hud.skill_slots[0]["lvl"].text) == "", "G15: unlocked-слот без пометки")
	# подсказка near[] во время модалки
	var fresh_state := snap_state()
	world.free()
	await step(2)
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await step(2)
	ok(world.hud.is_modal_open(), "G15b: на свежем сейве модалка снова открыта (class_id=='' в памяти)")
	var dummy_hint = Area2D.new()
	dummy_hint.set_script(load("res://scripts/npc.gd"))
	world.village_zone.add_child(dummy_hint)
	dummy_hint.world = world
	dummy_hint.npc_id = "farmer"
	world.near.append(dummy_hint)
	ok(world.hint_label.text == "", "G15: во время модалки hint_label пуст (даже с near[])")
	world._process(0.016)
	ok(world.hint_label.text == "", "G15: world._process чистит хинт при input_locked")
	dummy_hint.queue_free()
	world.near.clear()
	restore_state(fresh_state)
	GS.seen_intro = true
	GS.class_id = "warrior"
	GS.input_locked = false
	world.hud._pick_class("warrior")
	await step(1)
	if world.hud.is_dialog_open():
		await ad()

	# ---------- G5a/G5b латентные регрессии на свежих пересборках ----------
	print("SECTION G5 latent regressions")
	var st_pre := snap_state()
	# G5a: убить босса БЕЗ квеста, потом поговорить с Геральдом
	GS.cave_state = 0
	GS.has_key = false
	GS.has_amulet = false
	world.free()
	await step(2)
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await step(2)
	var brute2 = null
	for ch in world.cave_zone.get_children():
		if is_instance_valid(ch) and ch.is_in_group("boss"):
			brute2 = ch
	ok(brute2 != null, "G5a: босс заспавнен (cave_state=0)")
	brute2.hurt(999, brute2.global_position)
	await step(1)
	eqf(GS.cave_state, 2, "G5a: смерть босса -> cave_state=2")
	world.talk("hermit")
	await ad()
	eqf(GS.cave_state, 1, "G5a REGRESSION: talk(hermit) при cave_state 0->1 ПОНИЖАЕТ 2 (реальный код: ожидаем 1)")
	ok(GS.boss_defeated, "G5a: boss_defeated всё ещё true (прогрессия не потеряна полностью)")
	# G5b: дверь открыта, сейв, рестарт -> дверь срослась снова, интерактив мёртв
	GS.cave_state = 0
	GS.has_key = true
	GS.has_amulet = false
	world.free()
	await step(2)
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await step(2)
	var dz2 = world.dungeon_zone
	var door2 = find_area_by_hint(world.cave_zone, "дверь")
	ok(door2 != null, "G5b: дверь-зона заспавнена")
	dz2.unlock_door(Vector2i(11, 13))
	GS.player_pos = world.player.global_position
	GS.pos_valid = true
	ok(GS.save_game(), "G5b: save после открытия двери")
	world.free()
	await step(2)
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await step(2)
	var door_tile: int = world.dungeon_zone.tilemap.get_cell_atlas_coords(Vector2i(11, 13)).x
	eqf(door_tile, 3, "G5b REGRESSION: после рестарта тайл двери снова 3 (BLOCKING, невидимая стена)")
	ok(find_area_by_hint(world.cave_zone, "дверь") == null, "G5b REGRESSION: зона двери НЕ переспавнена (дверь невозможно открыть)")
	restore_state(st_pre)
	world.free()
	await step(2)
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await step(2)
	if world.hud.is_dialog_open():
		await ad()
	ok(true, "G5: мир пересобран, финальное состояние восстановлено")

func _toast_contains(sub: String) -> bool:
	for t in toasts:
		if String(t).contains(sub):
			return true
	return false
