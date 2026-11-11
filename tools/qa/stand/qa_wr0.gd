extends "res://mb_base.gd"
## QA WR0: репро + гейт фикса «вечного призрака в подземелье» (HEAD f3aa4c9).
## Жалоба игрока: вплотную к тенеплёту (требует d>24px, mob_wraith.gd:135) фаза
## никогда не стартует -> ВЕЧНЫЙ неуязвимый ETHEREAL (hurt() вне MATERIALIZING
## игнорирует), а тело CharacterBody2D (слой 4, в mask игрока входит 4)
## физически блокирует проход; «двигается синхронно» = обоюдное упирание.
## Секции:
##   S1 «вплотную» — заглушка-игрок прижата в 6 px от тенеплёта, 900 кадров
##      (15 с): материализаций >=3, hurt() в окне принят (hp 8->6), hurt() в
##      эфире/фазе не принимается, длительность ETHEREAL конечна (<=3.6 с).
##   S2 «проход» — тенеплёт заморожен в ETHEREAL (окна нет), тело-драйвер
##      (layer 1, mask 2|4, shape 10x8 — как player.gd) идёт по коридору
##      сквозь него: обязан пересечь (перелёт за призрака, min_gap < 6 px);
##      при блокировке move-вектор=60 px/s, а позиция стоит (печатаем INFO).
## Детерминизм: fixed-fps 60, переходы выключены RNG-несущественным путём
## (форс-материализация по таймеру). Вердикт: RESULT + строки WR0 TBL.

const S_NAMES := ["ETH", "PHA", "MAT"]
const ETH := 0
const PHA := 1
const MAT := 2
const PIN_FRAMES := 900        # 15 с при 60 fps
const PASS_FRAMES := 200

var w: Node2D = null
var drv: DriveBody = null
var trans: Array = []          # [t_frames, from, to] — переходы состояний S1

func _ready() -> void:
	await boot(save_for(0))
	await prep()
	await section_close()
	await section_pass()
	print_table()
	done()

func prep() -> void:
	for s in find_mob(world.village_zone, "slime"):
		park_far(s)
	for a in find_mob(world.village_zone, "mob_archer"):
		park_far(a)
	for r in find_mob(world.village_zone, "mob_swarmling"):
		park_far(r)
	park_far(world.dungeon_zone.boss_node)
	# Все пещерные мобы — на прикол: в S2 они физически встают в коридор
	# (маска драйвера видит слой 4) и «помогают» тенеплёту блокировать проход.
	for m in find_mob(world.dungeon_zone, "mob_"):
		park_far(m)
	for m in find_mob(world.dungeon_zone, "brute"):  # brute.gd — не «mob_*»!
		park_far(m)
	for m in find_mob(world.dungeon_zone, "slime"):
		park_far(m)
	var wraiths: Array = find_mob(world.dungeon_zone, "mob_wraith")
	check("WR0: тенеплёт в пещере найден", wraiths.size() >= 1)
	if wraiths.is_empty():
		return
	w = wraiths[0]
	w.set_physics_process(true)  # единственный живой в пещере
	world.apply_zone(true, false)  # пещера активна, героя не телепортируем

## Снятые с игры юниты уезжают в отстойник: park() только выключает
## физику, а коллайдер остаётся в коридоре — именно он расплющивал драйвер S2.
func park_far(m: Node) -> void:
	park(m)
	(m as Node2D).global_position = Vector2(-9000.0, -9000.0)

## S1: игрок прижат вплотную. Держим заглушку на 6px правее якоря каждый кадр:
## d<24 гарантированно -> на HEAD рывок не стартует НИКОГДА (репро бага).
func section_close() -> void:
	if w == null:
		return
	var anchor: Vector2 = w.global_position
	stub.global_position = anchor + Vector2(6, 0)
	var dl: Array = stub.get("dmg_log")
	var dmg0 := dl.size()
	var prev := int(w.state)
	var mats := 0
	var eth_in := 0
	var eth_max := 0.0
	var hurt_eth_done := false
	var hurt_eth_ok := false
	var hurt_mat_done := false
	var hp_after_mat_hurt := -1
	var pha_done := false
	var pha_ok := false
	for i in range(PIN_FRAMES):
		stub.global_position = anchor + Vector2(6, 0)
		GameState.hp = GameState.max_hp
		GameState.input_locked = false
		await get_tree().physics_frame
		var t := i + 1
		var st := int(w.state)
		if st != prev:
			trans.append([t, prev, st])
			if st == MAT:
				mats += 1
			if prev == ETH:
				eth_max = maxf(eth_max, float(t - eth_in) / 60.0)
			if st == ETH:
				eth_in = t
			prev = st
		if i == 5 and int(w.state) == ETH and not hurt_eth_done:
			w.hurt(3, Vector2.ZERO)
			hurt_eth_done = true
			hurt_eth_ok = int(w.hp) == 8
		if st == PHA and not pha_done:
			pha_done = true
			var h0 := int(w.hp)
			w.hurt(3, Vector2.ZERO)
			pha_ok = int(w.hp) == h0
		if st == MAT and not hurt_mat_done:
			w.hurt(2, Vector2.ZERO)
			hurt_mat_done = true
			hp_after_mat_hurt = int(w.hp)
	if prev == ETH:
		eth_max = maxf(eth_max, float(PIN_FRAMES - eth_in) / 60.0)
	check("WR0: вплотную 15с — материализаций >=3 (n=%d)" % mats, mats >= 3)
	check("WR0: hurt() в эфире НЕ принят (hp=8)", hurt_eth_done and hurt_eth_ok)
	check("WR0: hurt() в фазе НЕ принят", (not pha_done) or pha_ok)
	check("WR0: hurt() в окне материализации ПРИНЯТ (hp 8->6, hp=%d)" % hp_after_mat_hurt,
		hurt_mat_done and hp_after_mat_hurt == 6)
	check("WR0: ETHEREAL ограничен по длительности (max=%.3fс, норма <=3.6)" % eth_max, eth_max <= 3.6)
	var contacts := dl.size() - dmg0
	print("WR0 INFO | контактов-урона в окнах (справочно): %d" % contacts)

## S2: проход сквозь «эфирное» тело. Заморозка канонически выбрасывает в
## ETHEREAL и обнуляет движение — получаем неподвижного призрака без окон.
func section_pass() -> void:
	if w == null:
		return
	var dz: Node = world.dungeon_zone
	var best_run := 0
	var best_row := -1
	var best_x := -1
	for y in range(int(dz.map_h)):
		var run := 0
		for x in range(int(dz.map_w)):
			if cave_tile_walkable(Vector2i(x, y)):
				run += 1
				if run > best_run:
					best_run = run
					best_x = x - run + 1
					best_row = y
			else:
				run = 0
	if best_run < 12:
		check("WR0: найден коридор >=12 тайлов для прохода (найдено %d)" % best_run, false)
		return
	check("WR0: коридор найден y=%d x=[%d..%d] len=%d" % [best_row, best_x, best_x + best_run - 1, best_run], true)
	w.freeze_t = 600.0
	await pump(3)
	w.velocity = Vector2.ZERO
	check("WR0: замороженный тенеплёт в ETHEREAL", int(w.state) == ETH)
	var t_wraith := Vector2i(best_x + 5, best_row)
	var t_drv := Vector2i(best_x + 1, best_row)
	w.global_position = cave_global(world, t_wraith)
	w.last_safe = w.global_position
	w.home = w.global_position
	drv = DriveBody.new()
	world.add_child(drv)
	drv.global_position = cave_global(world, t_drv)
	var x0 := drv.global_position.x
	var wx0: float = w.global_position.x
	var min_gap := 1e20
	var all_eth := true
	drv.drive = Vector2(60.0, 0.0)
	for i in range(PASS_FRAMES):
		GameState.hp = GameState.max_hp
		await get_tree().physics_frame
		if int(w.state) != ETH:
			all_eth = false
		var gap: float = absf(drv.global_position.x - w.global_position.x)
		if gap < min_gap:
			min_gap = gap
	var moved := drv.global_position.x - x0
	var crossed: bool = drv.global_position.x > wx0 + 16.0
	check("WR0: тенеплёт всё время прохода в ETHEREAL", all_eth)
	check("WR0: герой ПРОШЁЛ сквозь призрака (dx=%.1fpx, пересёк=%s, min_gap=%.1fpx)" % [moved, crossed, min_gap],
		crossed and min_gap < 6.0)
	print("WR0 INFO | move-вектор 60.0 px/s, факт позиции %.1f px за %.1fс (~%.1f px/s; блок = стойка ~0 после упора)" % [moved, PASS_FRAMES / 60.0, moved / (PASS_FRAMES / 60.0)])
	park(w)
	if drv != null:
		drv.drive = Vector2.ZERO
		drv.velocity = Vector2.ZERO

func print_table() -> void:
	print("WR0 TBL | таблица переходов фаз S1 (t от старта, 60 fps):")
	if trans.is_empty():
		print("WR0 TBL | переходов НЕТ — вечный эфир (%dс)" % (PIN_FRAMES / 60))
		return
	var prev_f := 0
	var prev_s: int = int(trans[0][1])
	for tr in trans:
		var t := float(tr[0])
		print("WR0 TBL | %7.3fs | %s -> %s | сегмент %s = %.3fs" % [t / 60.0, S_NAMES[prev_s], S_NAMES[tr[2]], S_NAMES[prev_s], (t - float(prev_f)) / 60.0])
		prev_f = int(tr[0])
		prev_s = int(tr[2])
	print("WR0 TBL | хвостовой сегмент %s до %.1fs" % [S_NAMES[prev_s], float(PIN_FRAMES) / 60.0])

class DriveBody extends CharacterBody2D:
	## Тело-двигатель: слои/форма как у hero (player.gd: layer 1, mask 2|4,
	## shape 10x8) — именно mask 2|4 на HEAD не даёт протиснуться сквозь
	## тенеплёта (его слой 4). Едет сам в _physics_process, как player.gd;
	## стенд лишь выставляет drive (move_and_slide вне physics-тика не едет).
	var drive := Vector2.ZERO
	func _ready() -> void:
		collision_layer = 1
		collision_mask = 2 | 4
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(10, 8)
		cs.shape = sh
		add_child(cs)
	func _physics_process(_delta: float) -> void:
		velocity = drive
		move_and_slide()
