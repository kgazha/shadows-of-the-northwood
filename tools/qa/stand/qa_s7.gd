extends Node
## QA s7 (шаг C): влияние Achv/DmgNumbers на IO-автосейвы.
## Метрики: байт/запись, мс/запись (1000× save_game), записи/убийство
## (счётчик gold_changed в реальном Loot-цикле), рост файла от ach-флагов
## (пустой -> все 12 анлоков + счётчики 3 видов ×500), краш-тест DmgNumbers.

var writes := {"n": 0}
var fails := {"n": 0}

func ck(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		print("PASS %s" % name)
	else:
		fails["n"] += 1
		print("FAIL %s :: %s" % [name, detail])

func sz() -> int:
	if not FileAccess.file_exists("user://save_morkheim.json"):
		return -1
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.READ)
	if f == null:
		return -1
	var n := int(f.get_length())
	f.close()
	return n

func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	GameState.flags.clear()
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	GameState.gold = 10
	ck(GameState.save_game(), "S7 fresh save written")
	var s0 := sz()
	print("NOTE fresh v2 save size=%d B" % s0)

	# --- цена одной автосейв-записи ---
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		GameState.save_game()
	var t1 := Time.get_ticks_usec()
	var ms_per := float(t1 - t0) / 1000.0 / 1000.0
	print("NOTE save_game: %.3f ms/write, size=%d B (1000 writes = %.2f ms, %.2f KB total)" % [ms_per, s0, float(t1 - t0) / 1000.0, float(s0 * 1000) / 1024.0])
	ck(ms_per < 5.0, "S7 save_game write cost sane", "ms=%.3f" % ms_per)

	# --- записи/убийство в реальном Loot-цикле (achv-хук внутри) ---
	GameState.gold_changed.connect(func() -> void: writes["n"] += 1)
	for kind in ["swarmling", "archer", "wraith"]:
		writes["n"] = 0
		GameState.gold = 0
		t0 = Time.get_ticks_usec()
		for i in 500:
			Loot.on_mob_death(kind, Vector2.ZERO)
		t1 = Time.get_ticks_usec()
		print("NOTE %-10s: writes/kill=%.2f, ms/kill=%.3f (500 kills, first-kill unlock = +1 write всего)" % [kind, float(writes["n"]) / 500.0, float(t1 - t0) / 500.0 / 1000.0])
		ck(writes["n"] <= 501 and writes["n"] >= 250, "S7 %s writes<=kills (+unlock)" % kind, "w=%d" % writes["n"])
	#swarmling без золота (40%) не пишет вообще — уже покрыто: writes/kill≈0.6

	# --- рост файла от achv-инфраструктуры ---
	var s1 := sz()  # после 1500 убийств: ach.first_blood + ach.n.{3 kinds} счётчики
	for id in ["hunter_25", "hunter_100", "boss_slayer", "alchemist", "brewer_10", "campfires", "treasure", "collector", "wealth", "herbalist", "hardcore"]:
		Achv.unlock(id, 0, 0)
	GameState.save_game()
	var s2 := sz()
	print("NOTE save size: fresh=%d, after 1500 kills (1 unlock+3 counters)=%d, all 12 ach unlocked=%d (delta=%d B)" % [s0, s1, s2, s2 - s0])
	ck(s2 - s0 < 1500, "S7 achv flags footprint bounded", "delta=%d" % (s2 - s0))
	# повторные анлоки идемпотентны и не пишут
	writes["n"] = 0
	for i in 200:
		Achv.unlock("hunter_25", 30, 0)
	ck(writes["n"] == 0, "S7 repeat unlocks write no IO")

	# --- DmgNumbers: без world/пула — не краш, не IO ---
	var sz_before := sz()
	for i in 200:
		DmgNumbers.spawn(Vector2.ZERO, 3, "normal")
		DmgNumbers.spawn(Vector2.ZERO, 1, "heal")
		DmgNumbers.spawn(Vector2.ZERO, 2, "armor")
	await frames(2)
	ck(sz_before == sz(), "S7 DmgNumbers zero IO", "%d -> %d" % [sz_before, sz()])

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	print("S7 DONE fails=%d" % fails["n"])
	get_tree().quit(0)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
