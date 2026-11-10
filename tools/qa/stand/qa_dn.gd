extends Node
## QA стыков DmgNumbers (main ad88b93). НЕ входит в поставку — тесты в main не мержим.
## Хост цепляется к tree.current_scene (в игре это Main-сцена; здесь — харнесс-сцена,
## механика та же: lazy spawn + пул). Слейм — orphan-нода (в дерево не ставим,
## чтобы _physics_process без world не падал — это не предмет проверки).

const Alch := preload("res://scripts/alchemy.gd")

var world: Node = null
var player: Node = null
var toasts: Array[String] = []
var fails := 0
var checks := 0

func _ready() -> void:
	GameState.toast.connect(_on_toast)
	_boot_clean_saves()
	await _boot_world()
	await _t1_pool()
	await _t2_armor()
	await _t3_heal()
	await _t4_f9()
	await _t6_inf_path()
	await _t5_death()
	await _t7_perf()
	print("QA DN: checks=%d fails=%d" % [checks, fails])
	print("QA DN: " + ("ALL PASS" if fails == 0 else "FAILS!"))
	get_tree().quit(0 if fails == 0 else 1)

# ---------------- boot ----------------

func _boot_clean_saves() -> void:
	var da := DirAccess.open("user://")
	if da != null:
		for f: String in da.get_files():
			if f.ends_with(".json"):
				da.remove(f)

func _boot_world() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	add_child(inst)
	await frames(4)  # world._ready: карта, тайлы, player
	for n: Node in _descendants(get_tree().current_scene):
		if world == null and n.has_method("drink_potion") and n.get("player") != null:
			world = n
		if player == null and n.is_in_group("player"):
			player = n
	_check(world != null, "boot world found")
	_check(player != null, "boot player found")
	# штатный new-game: модалка выбора класса лочит ввод — «кликом» выбираем воина
	if world.hud.is_modal_open():
		world.hud._pick_class("warrior")
	_check(world.hud.is_modal_open() == false, "boot class modal closed")
	# интро-диалог после выбора — пролистываем advance()
	for i: int in range(60):
		if not world.hud.is_dialog_open():
			break
		world.hud.advance()
		await frames(1)
	_check(not world.hud.is_dialog_open() and not GameState.input_locked, "boot dialogs clear")

# ---------------- T1: 10 ударов / пул / кап / переиспользование ----------------

func _t1_pool() -> void:
	var s = load("res://scripts/slime.gd").new()
	s.hp = 1000
	s.global_position = Vector2(300, 200)
	for i: int in range(10):
		s.hurt(2, Vector2(200, 200))
	var host := _host()
	_check(host != null, "T1 host lazily created")
	_check(host.active_count() == 10, "T1 10 numbers after 10 hits: %d" % host.active_count())
	_check(_texts(host).count("2") == 10, "T1 texts all '2'")
	_check(host.get_child_count() <= 12, "T1 nodes <=12: %d" % host.get_child_count())
	# переполнение: ещё 5 ударов — активный кап 12, нод всё равно 12
	for i: int in range(5):
		s.hurt(2, Vector2(200, 200))
	_check(host.active_count() == 12, "T1 cap 12 active: %d" % host.active_count())
	var nodes := host.get_child_count()
	_check(nodes <= 12, "T1 nodes still <=12: %d" % nodes)
	# 0.75 с (45物理 кадров) — все в пул, ни одной ноды не удалено (queue_free нет)
	await frames(48)
	_check(host.active_count() == 0, "T1 all retired after 0.75s: %d" % host.active_count())
	_check(host.get_child_count() == nodes, "T1 no queue_free (child count stable): %d" % host.get_child_count())
	_check(host.get_child_count() > 0, "T1 labels kept in pool: %d" % host.get_child_count())
	# переиспользование: вторая волна не создаёт новых Label
	for i: int in range(10):
		s.hurt(2, Vector2(200, 200))
	_check(host.get_child_count() == nodes, "T1 pool reused, no new nodes: %d" % host.get_child_count())
	_check(host.active_count() == 10, "T1 second wave active: %d" % host.active_count())
	await frames(48)
	s.free()

# ---------------- T2: броня — число = реально снятое ----------------

func _t2_armor() -> void:
	await _settle()
	GameState.equip_item("armor", "leather")
	_check(GearData.armor_bonus(GameState) == 1, "T2 leather bonus 1")
	GameState.hp = GameState.max_hp
	player.hurt_cd = 0.0
	player.roll_t = 0.0
	var before: int = _host().active_count()
	player.take_damage(2)
	_check(GameState.hp == GameState.max_hp - 1, "T2 leather: hp took 1 not 2: hp=%d" % GameState.hp)
	_check(_last_text(_host()) == "1", "T2 number '1' not '2': '%s'" % _last_text(_host()))
	_check(_host().active_count() == before + 1, "T2 exactly one number per hit")
	await _settle()
	# полное поглощение невозможно: absorb даёт min 1 — кольчуга vs dmg 1 → снято 1, число '1'
	GameState.equip_item("armor", "chain")
	_check(GearData.armor_bonus(GameState) == 2, "T2 chain bonus 2")
	_check(GearData.absorb(GameState, 1) == 1, "T2 absorb min 1 (полного 0 не бывает)")
	GameState.hp = GameState.max_hp
	player.hurt_cd = 0.0
	player.roll_t = 0.0
	player.take_damage(1)
	_check(GameState.hp == GameState.max_hp - 1, "T2 chain vs dmg1: took 1: hp=%d" % GameState.hp)
	_check(_last_text(_host()) == "1", "T2 chain number '1': '%s'" % _last_text(_host()))
	await _settle()
	# метка «броня» — путь amount==0 (через героя недостижим из-за min 1, проверям напрямую)
	DmgNumbers.spawn(Vector2(120, 120), 0, "normal")
	_check(_last_text(_host()) == "броня", "T2 direct amount0 -> 'броня'")
	await _settle()

# ---------------- T3: хил — фактическое восстановление ----------------

func _t3_heal() -> void:
	# Q-зелье: hp=max → тихо (гейт world, ни числа, ни тоста про зелье)
	_check(not world.hud.is_dialog_open() and not world.hud.is_modal_open() and not GameState.input_locked, "T3 precondition: world unlocked")
	GameState.equip_item("armor", "")
	GameState.hp = GameState.max_hp
	GameState.herbs = 1
	var h := _host()
	var a0: int = h.active_count()
	world.drink_potion()
	_check(h.active_count() == a0, "T3 Q at full hp: silent")
	_check(GameState.herbs == 1, "T3 Q at full hp: herb not wasted")
	# hp=max-1 → «+1», не «+3»
	GameState.hp = GameState.max_hp - 1
	world.drink_potion()
	_check(GameState.hp == GameState.max_hp, "T3 Q healed to max")
	_check(_last_text(h) == "+1", "T3 Q number '+1' not '+3': '%s'" % _last_text(h))
	await _settle()
	# крепкое: hp=max → тихо
	GameState.hp = GameState.max_hp
	GameState.brewed_potions = 1
	a0 = h.active_count()
	var ok: bool = Alch.drink_brewed()
	_check(not ok, "T3 strong at full hp: refused")
	_check(h.active_count() == a0, "T3 strong at full hp: silent")
	_check(GameState.brewed_potions == 1, "T3 strong at full hp: charge not wasted")
	# hp=max-1 → «+1», не «+6»
	GameState.hp = GameState.max_hp - 1
	ok = Alch.drink_brewed()
	_check(ok and GameState.hp == GameState.max_hp, "T3 strong healed to max")
	_check(_last_text(h) == "+1", "T3 strong number '+1' not '+6': '%s'" % _last_text(h))
	await _settle()

# ---------------- T4: F9 quickload — один хост, числа живые ----------------

func _t4_f9() -> void:
	var h := _host()
	_check(h != null, "T4 host exists before F9")
	_check(_host_count() == 1, "T4 exactly 1 host before F9: %d" % _host_count())
	GameState.player_pos = player.global_position
	GameState.pos_valid = true
	_check(GameState.save_game(), "T4 save_game ok")
	toasts.clear()
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "quickload"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	_check(toasts.has("Игра загружена (F9)"), "T4 quickload branch ran (toast)")
	_check(_host_count() == 1, "T4 one host after F9 (no dup, no orphan): %d" % _host_count())
	_check(_host() == h, "T4 same host instance after F9")
	# числа спавнятся после F9
	var s = load("res://scripts/slime.gd").new()
	s.hp = 50
	s.global_position = Vector2(250, 150)
	var a0: int = _host().active_count()
	s.hurt(3, Vector2(200, 200))
	_check(_host().active_count() == a0 + 1, "T4 numbers spawn after F9")
	await _settle()
	s.free()

# ---------------- T6: Vector2.INF без игрока ----------------

func _t6_inf_path() -> void:
	GameState.hp = GameState.max_hp - 1
	GameState.brewed_potions = 1
	player.remove_from_group("player")
	await frames(2)
	var h := _host()
	var a0: int = h.active_count()
	var ok: bool = Alch.drink_brewed()  # heal есть, числа показать не над кем
	_check(ok, "T6 heal applied without player")
	_check(h.active_count() == a0, "T6 INF path silent without player, no crash")
	await frames(3)  # ни одного исключения за кадры
	player.add_to_group("player")
	GameState.hp = GameState.max_hp - 1
	GameState.brewed_potions = 1
	Alch.drink_brewed()
	_check(_last_text(h) == "+1", "T6 INF resolves over player: '%s'" % _last_text(h))
	await _settle()

# ---------------- T5: смерть игрока ----------------

func _t5_death() -> void:
	GameState.input_locked = false
	GameState.hp = 3
	player.hurt_cd = 0.0
	player.roll_t = 0.0
	var h := _host()
	var a0: int = h.active_count()
	player.take_damage(50)
	_check(GameState.hp == 0, "T5 hero dead")
	_check(h.active_count() == a0 + 1, "T5 death-blow number spawned: %d->%d" % [a0, h.active_count()])
	_check(_last_text(h) == "3", "T5 death number = actual 3 hp: '%s'" % _last_text(h))
	_check(world.hud.is_dialog_open(), "T5 death dialogue opened")
	_check(GameState.input_locked, "T5 input locked by dialogue")
	# числа в лок-момент не падают: ещё spawn + тик 0.75 с — твины живут при input_locked
	DmgNumbers.spawn(player.global_position + Vector2(0, -12), 5, "normal")
	_check(h.active_count() >= 2, "T5 numbers alive during lock: %d" % h.active_count())
	await frames(48)
	_check(is_instance_valid(player) and is_instance_valid(h), "T5 no crash, nodes valid")
	_check(h.active_count() == 0, "T5 retired fine under lock: %d" % h.active_count())
	# закрыть диалог смерти (advance до завершения)
	for i: int in range(40):
		if not world.hud.is_dialog_open():
			break
		world.hud.advance()
		await frames(1)
	GameState.input_locked = false
	await frames(3)

# ---------------- T7: грубая производительность ----------------

func _t7_perf() -> void:
	await _settle()
	var worst_us := 0
	var total_us := 0
	for batch: int in range(10):
		var t0 := Time.get_ticks_usec()
		for i: int in range(200):
			DmgNumbers.spawn(player.global_position + Vector2(float(i % 40), 0.0), 3, "normal")
		var dt: int = Time.get_ticks_usec() - t0
		worst_us = maxi(worst_us, dt)
		total_us += dt
		await frames(6)  # ~10 всплесков/сек по 200 = жёстче заявленных 200/с
	print("PERF 200-spawn batch: worst %.3f ms, avg %.3f ms" % [float(worst_us) / 1000.0, float(total_us) / 10000.0])
	_check(float(worst_us) / 1000.0 < 50.0, "T7 worst 200-spawn batch < 50ms: %.3f ms" % (float(worst_us) / 1000.0))
	var h := _host()
	_check(h.get_child_count() <= 12, "T7 total Labels <=12 under storm: %d" % h.get_child_count())
	# 300 кадров шторма по 4 числа/кадр (=240/с) с крутящимися твинами;
	# headless не привязан к реальному времени — мерило: стеновое время на кадр
	var f0 := Engine.get_process_frames()
	var t1 := Time.get_ticks_msec()
	for fr: int in range(300):
		for i: int in range(4):
			DmgNumbers.spawn(player.global_position + Vector2(float(i * 7), 0.0), 3, "normal")
		await get_tree().physics_frame
	var wall: int = Time.get_ticks_msec() - t1
	var fps: int = Engine.get_process_frames() - f0
	var ms_per_frame := float(wall) / float(maxi(1, fps))
	print("PERF 5s storm 240/s: frames=%d wall=%d ms -> %.3f ms/frame (бюджет 16.7)" % [fps, wall, ms_per_frame])
	_check(ms_per_frame < 16.7, "T7 per-frame cost under storm %.3f ms < 16.7" % ms_per_frame)
	# Дренаж пула: время жизни числа + тик MetaHud (TICK=0.5 с => 30 кадров) —
	# фиксированные 60 были впритык и flak'али (2/5). Поллим до 90 кадров.
	var drained := false
	for fr: int in range(90):
		if int(h.active_count()) == 0:
			drained = true
			break
		await get_tree().physics_frame
	_check(drained and int(h.active_count()) == 0, \
		"T7 pool drained after storm: %d" % int(h.active_count()))

# ---------------- helpers ----------------

func frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame

func _settle() -> void:
	await frames(50)  # все числа (~0.5 с) гарантированно в пуле

func _host() -> DmgNumbers:
	return get_tree().current_scene.get_node_or_null("DmgNumbers") as DmgNumbers

func _host_count() -> int:
	var n := 0
	for d: Node in _descendants(get_tree().current_scene):
		if d.name == "DmgNumbers":
			n += 1
	return n

func _descendants(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var v: Node = stack.pop_back()
		out.append(v)
		for c: Node in v.get_children():
			stack.append(c)
	return out

func _texts(h: DmgNumbers) -> Array:
	var out: Array = []
	for e: Variant in h._active:
		out.append(String((e["lbl"] as Label).text))
	return out

func _last_text(h: DmgNumbers) -> String:
	if h._active.is_empty():
		return "<none>"
	return String(((h._active[h._active.size() - 1])["lbl"] as Label).text)

func _on_toast(t: String) -> void:
	toasts.append(t)

func _check(ok: bool, name: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		fails += 1
