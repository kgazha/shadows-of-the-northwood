extends Node

## qa_dr — t60: два запроса пользователя от 16.11 вечера, один стенд.
##
## Д1 (16.11 22:56) «при сдаче квеста в лавке Драна открывается сама лавка — баг».
##   Источник найден в world.gd: колбэк диалога сдачи (merchant_done, переход
##   slime_quest 1->2) вызывал Shop.open("merchant") сразу после реплики. Это НЕ
##   «проглоченная» клавиша E: диалог гасит ввод сам, и D3 доказывает это реальным
##   вводом (тот же репро, но клавишами, а не вызовом talk()).
## Д2 (16.11 22:58) «стрелы у лучника слишком большие и толстые — уменьшить,
##   скорость увеличить»: силуэт печатает генератор листа sheet_ui.gd (_prj_arrow),
##   скорость — classes_data.gd (герой-лучник) и mob_archer.gd (лучник-моб).
##
## Пины:
##   D0 boot: world/hud/player найдены
##   D1 выдача квеста (0->1): лавка ОТКРЫТА — замысел g13 «сделка» не тронут
##   D2 СДАЧА квеста (1->2): Shop.is_open() == false (запрошенный пин) + quest=2 + 30 зол.
##   D3 тот же путь РЕАЛЬНЫМ вводом (E у Драна, листание тоже E): после последней
##      реплики лавки нет -> дело было не в эхе клавиши, а в колбэке
##   D4 следующий E по Драну как торговцу лавку по-прежнему открывает
##   A1 proj_speed героя-лучника = 300.0 (ровно +50 % к 200.0)
##   A2 лучник-моб: ARROW_SPEED == Arrow.speed == 255.0 (ровно +50 % к 170.0)
##   A3 лист projectiles.png: размер 64x16; стрелы (кадры 0 и 3) — длина 10,
##      толщина 4, 40 пикселей (было 15/8/91); соседние кадры (файербол/осколок)
##   A4 палитра стрел — прежняя, новых цветов нет
##   A5 стрела отцентрована в кадре по вертикали (центр y = 8.0) — точка вращения
##      снаряда не уехала
##   A6/A7 живой полёт: 5.00 px/кадр у героя, 4.25 px/кадр у моба (снаряд не гаснет)
##   A8 читаемость полёта: за кадр снаряд проходит не больше 0.55 своей длины
##      и не меньше 2 px (иначе «телепорт»)

const MAIN_SCENE := "res://scenes/main.tscn"
const ClassesData := preload("res://scripts/classes_data.gd")
const MobArcher := preload("res://scripts/mob_archer.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const PROJ_PX := "res://assets/projectiles.png"

const OLD_HERO_SPEED := 200.0
const OLD_MOB_SPEED := 170.0
const NEW_HERO_SPEED := 300.0
const NEW_MOB_SPEED := 255.0
# Прежняя палитра стрел (кадр 0 и кадр 3): контур оперения, контур/наконечник,
# перо, светлое и тёмное древко, крепление, теневое перо + «костяной» набор призрака.
const PAL_OLD: Array = [
	Color8(78, 27, 21), Color8(58, 62, 70), Color8(212, 97, 74), Color8(163, 168, 178),
	Color8(131, 136, 146), Color8(171, 68, 51), Color8(124, 46, 36),
	Color8(95, 88, 74), Color8(192, 182, 159), Color8(226, 216, 194),
]

var world = null  # не типизируем: talk()/hud есть у world.gd, раннер грузит сценами
var hud: Node = null
var player: CharacterBody2D = null
var _p := 0
var _f := 0


func _ready() -> void:
	# чистый старт: стенды батареи делят один user://, и чужой сейв (например
	# с мёртвым героем) поднимает на запуске экран итогов — а под ним Shop.open()
	# по контракту отказывается открывать окно (shop.gd, «отказ под чужим окном»).
	# Третий стенд подряд (qa_cf/qa_lp) делает ровно так же: удаляем сейв до boot.
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	GameState.class_id = "archer"
	GameState.seen_intro = true
	GameState.seen_cave_intro = true
	GameState.flags["ashen.intro_seen"] = "1"
	GameState.flags["hint.slime"] = "1"
	GameState.flags["hint.talents"] = "1"
	GameState.run_seed = 20261116
	await _fr(2)
	var inst: Node = load(MAIN_SCENE).instantiate()
	add_child(inst)
	await _fr(12)
	for n in _descendants(get_tree().current_scene):
		if world == null and n.has_method("drink_potion") and n.get("player") != null:
			world = n as Node2D
		if player == null and n.is_in_group("player"):
			player = n as CharacterBody2D
	if world != null:
		hud = world.get("hud")
	ck(world != null and hud != null and player != null, "D0 мир/HUD/герой найдены")
	if world == null or hud == null or player == null:
		_report()
		return
	# Стенды батареи живут в одном user:// подряд: чтобы чужой сейв не подсадил
	# на старт чужое окно (под модалкой Shop.open() по контракту отказывает),
	# стартуем свежий круг и печатаем, чем мир встретил тест.
	GameState.start_fresh_game()
	GameState.class_id = "archer"
	GameState.heal(99)
	GameState.input_locked = false
	print("QA DR boot: hp=%d input_locked=%s modal=%s dialog=%s итогов=%s" % [
		int(GameState.hp), str(GameState.input_locked),
		str(bool(hud.is_modal_open())) if hud.has_method("is_modal_open") else "?",
		str(bool(hud.is_dialog_open())) if hud.has_method("is_dialog_open") else "?",
		str(RunSummary.is_open())])
	await _merchant_checks()
	_arrow_checks()
	await _flight_checks()
	_report()


func _fr(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _descendants(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		out.append(n)
	return out


func ck(ok: bool, label: String) -> void:
	if ok:
		_p += 1
	else:
		_f += 1
	print("QA DR %s | %s" % ["ok " if ok else "FAIL", label])


func _report() -> void:
	print("RESULT: %d pass / %d fail" % [_p, _f])
	get_tree().quit(0)


## Листание диалога до закрытия (программно, как в qa_lp._g12_drain).
func _drain(guard: int = 40) -> bool:
	var g := 0
	while hud.is_dialog_open() and g < guard:
		g += 1
		hud.advance()
		await _fr(1)
		GameState.heal(9)  # страховка: пока герой слушает, его могут hit'нуть
	return not hud.is_dialog_open()


## Клавиша «как человек»: то же событие, что идёт от клавиатуры.
func _key_action(action: String) -> void:
	var d := InputEventAction.new()
	d.action = action
	d.strength = 1.0
	d.pressed = true
	get_tree().root.push_input(d)
	var u := InputEventAction.new()
	u.action = action
	u.strength = 0.0
	u.pressed = false
	get_tree().root.push_input(u)


func _find_npc(npc_id: String) -> Node2D:
	for n in _descendants(world):
		if str(n.get("npc_id")) == npc_id and n is Node2D:
			return n as Node2D
	return null


# ── Дран ────────────────────────────────────────────────────────────────────

func _merchant_checks() -> void:
	# чистый круг: квест не взят, лавка закрыта, ввод свободен
	if Shop.is_open():
		Shop.close()
	GameState.slime_quest = 0
	GameState.slime_kills_circle = 0
	GameState.input_locked = false
	GameState.flags.erase("q.merchant_boss")
	GameState.boss_defeated = false
	# Д1: выдача квеста — лавка открывается (g13 «сделка»: за первой репликой
	# игрок действительно стоит у прилавка, смола и факел нужны сразу)
	world.talk("merchant")
	await _fr(2)
	var opened := bool(hud.is_dialog_open())
	var ok1: bool = await _drain()
	ck(opened and ok1 and int(GameState.slime_quest) == 1 and Shop.is_open(),
			"D1 выдача квеста: диалог отыгран, quest=1, прилавок открыт (намеренно) [drain=%s quest=%d open=%s]" % [str(ok1), int(GameState.slime_quest), str(Shop.is_open())])
	if Shop.is_open():
		Shop.close()
	await _fr(2)
	GameState.input_locked = false
	# Д2: СДАЧА квеста — прилавок сам выпрыгивать не должен (16.11 22:56)
	GameState.slime_kills_circle = 3
	var gold0 := int(GameState.gold)
	world.talk("merchant")
	await _fr(2)
	var ok2: bool = await _drain()
	await _fr(6)
	ck(ok2 and int(GameState.slime_quest) == 2 and int(GameState.gold) == gold0 + 30,
			"D2a сдача: quest=2, золота +%d (ожидали +30)" % (int(GameState.gold) - gold0))
	ck(not Shop.is_open(),
			"D2b сдача квеста: Shop открыт == false (лавка не открывается сама)")
	GameState.input_locked = false
	# Д4: повторное обращение к Драну = торговец, прилавок открывается по-прежнему
	world.talk("merchant")
	await _fr(2)
	var ok4: bool = await _drain()
	var vendor := str(Shop.I.get("_vendor")) if Shop.I != null else "?"
	ck(ok4 and Shop.is_open() and vendor == "merchant",
			"D4 следующий разговор с Драном открывает прилавок merchant [drain=%s open=%s vendor=%s]" % [str(ok4), str(Shop.is_open()), vendor])
	if Shop.is_open():
		Shop.close()
	await _fr(2)
	GameState.input_locked = false
	await _real_key_repro()


## Д3: пользовательский репро целиком на РЕАЛЬНОМ вводе — подойти к Драну, E,
## листать диалог сдачи той же E, убрать руки с клавиатуры. Прежний баг
## воспроизводится и здесь (колбэк открывал окно), и «эхо клавиши» тоже
## поймался бы: без новых нажатий прилавок обязан оставаться закрытым.
func _real_key_repro() -> void:
	var npc := _find_npc("merchant")
	if npc == null:
		ck(false, "D3a Дран найден в сцене")
		return
	# откатываем квестовое состояние к «принёс трофеи» — тот же переход 1->2
	GameState.slime_quest = 1
	GameState.slime_kills_circle = 3
	GameState.heal(99)
	if Shop.is_open():
		Shop.close()
	GameState.input_locked = false
	player.global_position = npc.global_position
	await _fr(4)
	var gold0 := int(GameState.gold)
	_key_action("interact")
	await _fr(2)
	var opened := bool(hud.is_dialog_open())
	var g := 0
	while hud.is_dialog_open() and g < 40:
		g += 1
		_key_action("interact")
		await _fr(2)
		GameState.heal(9)
	var closed: bool = not bool(hud.is_dialog_open())
	ck(opened and closed and int(GameState.slime_quest) == 2,
			"D3a реальный E у Драна: диалог сдачи открыт и дослушан (open=%s closed=%s quest=%d)" % [str(opened), str(closed), int(GameState.slime_quest)])
	await _fr(10)  # руки убраны с клавиатуры: ни одного нового события ввода
	ck(not Shop.is_open(),
			"D3b реальный E: после закрытия диалога прилавок закрыт (открыт=%s)" % str(Shop.is_open()))
	ck(int(GameState.gold) >= gold0 + 30,
			"D3c реальный E: награда за сдачу выдана (+%d зол.)" % (int(GameState.gold) - gold0))
	GameState.input_locked = false


# ── стрелы ──────────────────────────────────────────────────────────────────

func _arrow_checks() -> void:
	var cd: Dictionary = ClassesData.class_data("archer")
	var ps := float(cd.get("proj_speed", -1.0))
	ck(ps == NEW_HERO_SPEED and ps == OLD_HERO_SPEED * 1.5,
			"A1 герой-лучник proj_speed = %.1f (было %.1f, +50%%)" % [ps, OLD_HERO_SPEED])
	var mob_const := float(MobArcher.ARROW_SPEED)
	var probe = MobArcher.Arrow.new()
	var mob_var := float(probe.speed)
	probe.free()
	ck(mob_const == NEW_MOB_SPEED and mob_var == NEW_MOB_SPEED and mob_const == OLD_MOB_SPEED * 1.5,
			"A2 лучник-моб: ARROW_SPEED=%.1f и Arrow.speed=%.1f (было %.1f, +50%%)" % [mob_const, mob_var, OLD_MOB_SPEED])

	var tex: Texture2D = load(PROJ_PX)
	if tex == null:
		ck(false, "A3 лист projectiles.png загружается")
		return
	var img: Image = tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	ck(img.get_width() == 64 and img.get_height() == 16,
			"A3a лист остался 64x16 (%d x %d)" % [img.get_width(), img.get_height()])
	var f0 := _sil(img, 0)
	var f3 := _sil(img, 3)
	ck(f0["len"] == 10 and f0["thick"] == 4 and f0["n"] == 40
			and f3["len"] == 10 and f3["thick"] == 4 and f3["n"] == 40,
			"A3b стрелы (кадры 0/3): длина %d (было 15), толщина %d (было 8), пикселей %d (было 91)" % [f0["len"], f0["thick"], f0["n"]])
	var f1 := _sil(img, 1)
	var f2 := _sil(img, 2)
	ck(f1["n"] == 103 and f2["n"] == 116,
			"A3c соседние кадры не тронуты: файербол %d px, осколок %d px" % [f1["n"], f2["n"]])
	var stranger := _first_foreign_color(img)
	ck(stranger == "", "A4 палитра стрел прежняя (чужой пиксел: %s)" % (stranger if stranger != "" else "нет"))
	var yc: float = (f0["y0"] + f0["y1"] + 1) / 2.0
	ck(absf(yc - 8.0) < 0.001,
			"A5 стрела центрирована по высоте кадра: центр y=%.1f (как и было)" % yc)


## Силуэт кадра: площадь, длина, максимальная толщина по столбцу, границы.
func _sil(img: Image, frame: int) -> Dictionary:
	var n := 0
	var minx := 999
	var maxx := -1
	var miny := 999
	var maxy := -1
	var thickest := 0
	for x in range(16):
		var col := 0
		for y in range(16):
			if img.get_pixel(frame * 16 + x, y).a8 <= 0:
				continue
			n += 1
			col += 1
			minx = mini(minx, x)
			maxx = maxi(maxx, x)
			miny = mini(miny, y)
			maxy = maxi(maxy, y)
		thickest = maxi(thickest, col)
	return {"n": n, "len": maxx - minx + 1, "thick": thickest, "y0": miny, "y1": maxy}


## Есть ли в кадрах-стрелах цвет вне прежней палитры (канон: палитра не растёт).
func _first_foreign_color(img: Image) -> String:
	for fr in [0, 3]:
		for x in range(16):
			for y in range(16):
				var c := img.get_pixel(fr * 16 + x, y)
				if c.a8 <= 0:
					continue
				var known := false
				for p in PAL_OLD:
					var pc: Color = p
					if absf(c.r - pc.r) < 0.004 and absf(c.g - pc.g) < 0.004 and absf(c.b - pc.b) < 0.004:
						known = true
						break
				if not known:
					return "кадр %d (%d,%d) = %s" % [fr, x, y, str(c)]
	return ""


## Живой полёт: измеряем фактические приращения позиции по физическим кадрам.
## Столкновения на время замера гасятся collision_mask = 0, чтобы на скорость не
## влиял пробегающий мимо моб; сама формула движения (position += dirv*speed*delta)
## не тронута.
func _flight_checks() -> void:
	var hero_step := await _measure_flight(true)
	var mob_step := await _measure_flight(false)
	ck(absf(hero_step - NEW_HERO_SPEED / 60.0) < 0.06,
			"A6 полёт героя: %.2f px/кадр (ожидали %.2f)" % [hero_step, NEW_HERO_SPEED / 60.0])
	ck(absf(mob_step - NEW_MOB_SPEED / 60.0) < 0.06,
			"A7 полёт моба: %.2f px/кадр (ожидали %.2f)" % [mob_step, NEW_MOB_SPEED / 60.0])
	var f0 := 10.0  # длина стрелы из A3b, px
	ck(hero_step <= 0.55 * f0 and hero_step >= 2.0 and mob_step <= 0.55 * f0 and mob_step >= 2.0,
			"A8 читаемость: за кадр %.2f/%.2f px при длине %.0f px (порог 0.55 длины = %.2f, не «телепорт»)" % [hero_step, mob_step, f0, 0.55 * f0])


func _measure_flight(is_hero: bool) -> float:
	# типы намеренно не выводим: setup() есть у самого снаряда, а не у Area2D
	var a = null
	if is_hero:
		a = ProjectileScript.new()
		a.setup(player.global_position + Vector2(200.0, -120.0), Vector2.RIGHT, NEW_HERO_SPEED, 1, 0)
	else:
		a = MobArcher.Arrow.new()
		a.setup(player.global_position + Vector2(200.0, -120.0), Vector2.RIGHT, player, 2)
	a.collision_mask = 0
	world.add_child(a)
	await _fr(1)
	var prev: Vector2 = a.global_position
	var acc := 0.0
	var samples := 0
	for i in range(8):
		await _fr(1)
		if not is_instance_valid(a):
			break
		acc += a.global_position.distance_to(prev)
		prev = a.global_position
		samples += 1
	if is_instance_valid(a):
		a.queue_free()
	await _fr(2)
	return acc / float(maxi(1, samples))
