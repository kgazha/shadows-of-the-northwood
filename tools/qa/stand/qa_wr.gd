extends Node
## QA-WR: стенд воинских правок п.6–7 (база HEAD f3aa4c9, песочница sand_wr).
## Проверяет ПОВЕДЕНИЕ player.gd после sand_wr.diff:
##   п.6 power_strike — без цели в радиусе атаки НЕ активируется (cd не тронут,
##       тост «Нет цели рядом», ui_deny+вспышка в коде), догнать-режима нет;
##   п.7 second_wind -> «Рывок вепря» — мгновенный рывок к ближайшему врагу
##       (радиус 72 px, сквозь врагов, НЕ сквозь стены), оглушение freeze_t
##       (mob-механика frost_nova: не двигается и не атакует) 0.7 с / босс 0.35,
##       1x удар в конце; без цели — не тратится (правило п.6);
##   execute — цель умерла от казни => +3 HP (heal, кламп по max_hp) + тост
##       «+3 HP»; не-добивание — 1.5x без хила;
##   регресс: вихрь 1.5x по площади и pierce-выстрел лучника не тронуты.
## xp_next завышен — level-up/heal_full не искажают hp-ассерты.
## Запуск: godot --headless --fixed-fps 60 --path pixel-rpg res://qa_wr.tscn
## Ожидание: fails=0, quit(0). Прогон ДВАЖДЫ — вывод детерминирован (md5 совпадает).

const PLAYER := preload("res://scripts/player.gd")
const SLIME := preload("res://scripts/slime.gd")
const BRUTE := preload("res://scripts/brute.gd")
const PROJ := preload("res://scripts/projectile.gd")

var fails := 0
var checks := 0
var toasts: Array = []
var world: Node2D
var hero = null  # НЕ typизируем: cast_skill/skill_cd —Members player.gd, доступ динамический

# Заглушка world.gd ровно под контракты мобов/героя: player, tile_to_world
# (мир как в world.gd: TILE=16, +2 по Y), on_player_death.
class WrWorld extends Node2D:
	var player: Node2D = null
	func tile_to_world(t: Vector2i) -> Vector2:
		return Vector2((t.x + 0.5) * 16.0, (t.y + 0.5) * 16.0 + 2.0)
	func on_player_death() -> void:
		pass

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	print("=== QA WR START (HEAD f3aa4c9 + sand_wr) ===")
	await _frame()
	sect_a()
	await sect_b()
	await sect_c()
	await sect_d()
	sect_e_text_wiring()
	free_world()
	print("=== QA WR DONE: checks=%d fails=%d ===" % [checks, fails])
	get_tree().quit(0 if fails == 0 else 1)

# --- харнесс ---

func ck(what: String, cond: bool, info := "") -> void:
	checks += 1
	if cond:
		print("PASS | %s" % what)
	else:
		fails += 1
		print("FAIL | %s | %s" % [what, info])

func any_toast(frag: String) -> bool:
	for t in toasts:
		if String(t).contains(frag):
			return true
	return false

func _frame(n := 1) -> void:
	for _i in n:
		await get_tree().physics_frame

func file_src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()

## Воин 4-го уровня (все 4 скилла открыты), xp_next завышен: казни не апнут
#  уровень и не зальют hp через heal_full — ассерты по HP честные.
func reset_warrior() -> void:
	GameState.from_dict({"v": 2, "level": 4, "xp": 0, "xp_next": 10000, "class_id": "warrior"})
	GameState.hp = GameState.max_hp
	GameState.input_locked = false
	toasts.clear()

func free_world() -> void:
	if world != null and is_instance_valid(world):
		world.free()
	world = null
	hero = null

func new_world() -> Node2D:
	var w := WrWorld.new()
	add_child(w)
	var p = PLAYER.new()
	w.add_child(p)
	w.player = p
	world = w
	hero = p
	return w

func spawn_slime(pos: Vector2):  # Variant: hp/dying/freeze_t — поля slime.gd
	var s = SLIME.new()
	world.add_child(s)
	s.setup(world, Vector2i(0, 0))
	s.global_position = pos
	return s

func spawn_boss(pos: Vector2):  # Variant: hp/freeze_t — поля brute.gd
	var b = BRUTE.new()
	world.add_child(b)
	b.setup(world, Vector2i(0, 0))
	b.global_position = pos
	return b

func add_wall(center: Vector2, size: Vector2) -> void:
	var sb := StaticBody2D.new()
	sb.collision_layer = 2  # слой стен как в world.gd (TileMapLayer body)
	sb.collision_mask = 0
	sb.position = center
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	world.add_child(sb)

func count_projectiles() -> int:
	var n := 0
	for c in world.get_children():
		if c.get_script() == PROJ:
			n += 1
	return n

# --- A: power_strike (п.6) ---

func sect_a() -> void:
	print("--- A: power_strike — без цели не тратится, догнать-режима нет ---")
	# A1: враг в 40 px (радиус атаки воина 18) — каст отклонён
	reset_warrior()
	new_world()
	hero.global_position = Vector2.ZERO
	var s = spawn_slime(Vector2(40, 0))
	var hp0 := int(s.hp)
	var ok: bool = hero.cast_skill(0)
	ck("A1 без цели в радиусе: cast=false", not ok)
	ck("A1 кулдаун НЕ потрачен", absf(float(hero.skill_cd[0])) < 0.001, "cd=%f" % hero.skill_cd[0])
	ck("A1 урона нет", int(s.hp) == hp0, "hp=%d (было %d)" % [s.hp, hp0])
	ck("A1 тост «Нет цели рядом»", any_toast("Нет цели рядом"))
	ck("A1 «догнать-режим» убран (pending_mult=1)", absf(hero.pending_mult - 1.0) < 0.001)
	ok = hero.cast_skill(0)
	ck("A1 повторный каст тоже false, cd по-прежнему 0", not ok and absf(float(hero.skill_cd[0])) < 0.001)
	free_world()
	# A3: цель в радиусе (16 px) — мгновенный 2x, как раньше
	reset_warrior()
	new_world()
	hero.global_position = Vector2.ZERO
	var t = spawn_slime(Vector2(16, 0))
	hp0 = int(t.hp)
	var dmg := int(GameState.damage)
	ok = hero.cast_skill(0)
	ck("A3 с целью в радиусе: cast=true", ok)
	ck("A3 мгновенный 2x (списано round(dmg*2)=%d)" % int(round(dmg * 2.0)),
		int(t.hp) == hp0 - int(round(dmg * 2.0)), "hp=%d (было %d, dmg=%d)" % [t.hp, hp0, dmg])
	ck("A3 кулдаун 4.0 потрачен", absf(float(hero.skill_cd[0]) - 4.0) < 0.001, "cd=%f" % hero.skill_cd[0])
	ok = hero.cast_skill(0)
	ck("A4 на кулдауне: false, урон не повторён", not ok and int(t.hp) == hp0 - int(round(dmg * 2.0)))
	free_world()

# --- B: «Рывок вепря» (second_wind rework) ---

func sect_b() -> void:
	print("--- B: рывок вепря — цель 70px, оглушение, 1x удар; стены/боссы/без цели ---")
	# B1: враг в 90 px (> радиуса рывка 72) — не активируется, не тратится
	reset_warrior()
	new_world()
	hero.global_position = Vector2.ZERO
	var far = spawn_slime(Vector2(0, -90))
	var hp0 := int(far.hp)
	var ok: bool = hero.cast_skill(2)
	ck("B1 без цели в радиусе 72: cast=false", not ok)
	ck("B1 кулдаун слота 2 не потрачен", absf(float(hero.skill_cd[2])) < 0.001, "cd=%f" % hero.skill_cd[2])
	ck("B1 урона нет", int(far.hp) == hp0)
	ck("B1 тост «Нет цели рядом»", any_toast("Нет цели рядом"))
	free_world()
	# B2: цель в 70 px — рывок: финал в радиусе удара, stun 0.7, 1x урон, хила нет
	reset_warrior()
	new_world()
	hero.global_position = Vector2.ZERO
	far = spawn_slime(Vector2(70, 0))
	hp0 = int(far.hp)
	var dmg := int(GameState.damage)
	var gh0 := int(GameState.hp)
	ok = hero.cast_skill(2)
	var dfin: float = hero.global_position.distance_to(far.global_position)
	ck("B2 cast=true, цель в 70 px найдена", ok)
	ck("B2 финальная дистанция в радиусе удара (≤18)", dfin <= 18.0 and dfin >= 11.0,
		"dist=%.2f" % dfin)
	ck("B2 герой реально переместился (x≥40)", hero.global_position.x >= 40.0,
		"x=%.1f" % hero.global_position.x)
	ck("B2 цель оглушена freeze_t≈0.7", float(far.freeze_t) > 0.65 and float(far.freeze_t) <= 0.7,
		"freeze_t=%f" % far.freeze_t)
	ck("B2 урон 1x (списано round(dmg)=%d)" % dmg, int(far.hp) == hp0 - dmg,
		"hp=%d (было %d)" % [far.hp, hp0])
	ck("B2 рывок НЕ лечит (hp героя не вырос)", int(GameState.hp) == gh0)
	ck("B2 кулдаун 20 потрачен", absf(float(hero.skill_cd[2]) - 20.0) < 0.001)
	# B3: оглушённая цель не двигается и не атакует (mob-механика freeze_t)
	var spos: Vector2 = far.global_position
	gh0 = int(GameState.hp)
	await _frame(20)  # 20 кадров: freeze 0.7 с = 42 кадра — запас
	ck("B3 в оглушении моб НЕ сдвинулся (20 кадров)",
		far.global_position.distance_to(spos) < 0.01, "сдвиг=%.3f" % far.global_position.distance_to(spos))
	ck("B3 в оглушении моб НЕ атаковал (hp героя не тронут)", int(GameState.hp) == gh0)
	ck("B3 stun ещё жив на 20-м кадре (0.7>20/60)", float(far.freeze_t) > 0.3)
	# B4: босс — оглушение вдвое короче (канон brute: держит удар, но не резист)
	# (68 px: строго ближе «far»-слайма B2 на 70 px — без тай-ничейности цели)
	var boss = spawn_boss(Vector2(0, -68))
	var bhp0 := int(boss.hp)
	var bdmg := int(GameState.damage)
	hero.global_position = Vector2.ZERO
	hero.skill_cd[2] = 0.0
	ok = hero.cast_skill(2)
	var bdfin: float = hero.global_position.distance_to(boss.global_position)
	ck("B4 босс: cast=true, рывок выполнен (дистанция ≤22)", ok and bdfin <= 22.0,
		"dist=%.2f" % bdfin)
	ck("B4 босс: stun короче — freeze_t≈0.35", float(boss.freeze_t) > 0.3 and float(boss.freeze_t) <= 0.35,
		"freeze_t=%f" % boss.freeze_t)
	ck("B4 босс получил 1x (%d)" % bdmg, int(boss.hp) == bhp0 - bdmg, "hp=%d (было %d)" % [boss.hp, bhp0])
	boss.free()
	# B5: стена между — рывок упирается, ни stun, ни удара; кулдаун потрачен
	var wslime = spawn_slime(Vector2(60, 0))
	add_wall(Vector2(35, 0), Vector2(8, 80))  # стена x∈[31..39]
	hero.global_position = Vector2.ZERO
	hero.skill_cd[2] = 0.0
	toasts.clear()
	var whp0 := int(wslime.hp)
	ok = hero.cast_skill(2)
	ck("B5 стена: cast=true (цель была в радиусе — семантика: каст состоялся)", ok)
	ck("B5 герой НЕ прошёл сквозь стену (x<31)", hero.global_position.x < 31.0,
		"x=%.1f" % hero.global_position.x)
	ck("B5 цель вне досягаемости: НЕ оглушена", absf(float(wslime.freeze_t)) < 0.001,
		"freeze_t=%f" % wslime.freeze_t)
	ck("B5 удара не было", int(wslime.hp) == whp0)
	ck("B5 тост про стену", any_toast("Стена помешала"))
	ck("B5 кулдаун при этом потрачен", float(hero.skill_cd[2]) > 0.0)
	free_world()

# --- C: execute-хил ---

func sect_c() -> void:
	print("--- C: казнь-килл => +3 HP с клампом; не-килл => без хила ---")
	reset_warrior()
	new_world()
	hero.global_position = Vector2.ZERO
	# C1: цель 1/3 HP (<=25%, минимум 1) — казнь, герой 11/18 => 14
	GameState.hp = GameState.max_hp - 7
	var gh0 := int(GameState.hp)
	var s = spawn_slime(Vector2(16, 0))
	s.hp = 1
	var ok: bool = hero.cast_skill(3)
	ck("C1 казнь сработала (цель мертва)", ok and bool(s.dying))
	ck("C1 герой +3 HP (11->14 при макс %d)" % GameState.max_hp, int(GameState.hp) == gh0 + 3,
		"hp=%d (было %d)" % [GameState.hp, gh0])
	ck("C1 тост «+3 HP»", any_toast("+3 HP"))
	ck("C1 кулдаун 12 потрачен", absf(float(hero.skill_cd[3]) - 12.0) < 0.001)
	free_world()
	# C2: кламп — 17/18 => ровно 18
	reset_warrior()
	new_world()
	hero.global_position = Vector2.ZERO
	GameState.hp = GameState.max_hp - 1
	var s2 = spawn_slime(Vector2(-16, 0))
	s2.hp = 1
	ok = hero.cast_skill(3)
	ck("C2 кламп по max_hp: hp==max_hp (%d)" % GameState.max_hp,
		ok and bool(s2.dying) and int(GameState.hp) == int(GameState.max_hp),
		"hp=%d max=%d" % [GameState.hp, GameState.max_hp])
	free_world()
	# C3: не-добивание — 1.5x, хила нет
	reset_warrior()
	new_world()
	hero.global_position = Vector2.ZERO
	GameState.hp = 5
	var s3 = spawn_slime(Vector2(16, 0))
	s3.hp = 4  # > max(1, int(3*0.25))=1 => НЕ казнь: 1.5x
	var dmg := int(GameState.damage)
	var want3 := int(round(dmg * 1.5))
	ok = hero.cast_skill(3)
	ck("C3 не-казнь: 1.5x урон (списано %d)" % want3,
		ok and int(s3.hp) == 4 - want3, "hp=%d" % s3.hp)
	ck("C3 хила нет (hp=5, тоста «+3 HP» нет)", int(GameState.hp) == 5 and not any_toast("+3 HP"))
	free_world()

# --- D: регресс (1 чек) ---

func sect_d() -> void:
	print("--- D: регресс — вихрь и выстрелы лучника не тронуты (1 чек) ---")
	reset_warrior()
	new_world()
	hero.global_position = Vector2.ZERO
	var a = spawn_slime(Vector2(20, 0))
	var b = spawn_slime(Vector2(-20, 0))
	var ah0 := int(a.hp)
	var bh0 := int(b.hp)
	var dmg := int(GameState.damage)
	var want := int(round(dmg * 1.5))
	var ok: bool = hero.cast_skill(1)  # вихрь 1.5x по площади
	var wh_ok: bool = ok and int(a.hp) == ah0 - want and int(b.hp) == bh0 - want \
		and absf(float(hero.skill_cd[1]) - 8.0) < 0.001
	# лучник: pierce обязан выпустить ровно 1 снаряд
	GameState.from_dict({"v": 2, "level": 4, "xp": 0, "xp_next": 10000, "class_id": "archer"})
	GameState.hp = GameState.max_hp
	hero.apply_class()
	spawn_slime(Vector2(40, 0))
	hero.skill_cd[0] = 0.0
	var p0 := count_projectiles()
	ok = hero.cast_skill(0)  # pierce
	var arch_ok: bool = ok and count_projectiles() == p0 + 1
	ck("D1 вихрь 1.5x по 2 целям (−%d каждому) И pierce лучника = +1 снаряд" % want,
		wh_ok and arch_ok, "wh=%s arch=%s" % [str(wh_ok), str(arch_ok)])
	free_world()

# --- E: текстовая проводка (скилл-тултипы подхватывают classes_data) ---

func sect_e_text_wiring() -> void:
	print("--- E: тексты/проводка ---")
	var cd := file_src("res://scripts/classes_data.gd")
	var pl := file_src("res://scripts/player.gd")
	var hd := file_src("res://scripts/hud.gd")
	ck("E1 classes_data: «Мгновенно лечит 4 HP» больше нет", not cd.contains("лечит 4"))
	ck("E1 second_wind переименован в «Рывок вепря»", cd.contains("Рывок вепря"))
	ck("E1 desc рывка: догнать/оглушить/ударить", cd.contains("оглушить на 0.7 с и ударить"))
	ck("E1 desc казни обещает +3 HP воину", cd.contains("+3 HP воину"))
	ck("E2 отказ в player.gd = ui_deny + тост", pl.contains('GameAudio.sfx("ui_deny")') \
		and pl.contains("Нет цели рядом"))
	ck("E2 хил-скилл выведен из warrior-хуков (heal(4) удалён)", not pl.contains("GameState.heal(4)"))
	ck("E3 hud не правился: тултип читает sd.name/sd.desc из classes_data", hd.contains("sd.name") and hd.contains("sd.desc"))
	ck("E4 execute-награда клампится через GameState.heal", pl.contains("GameState.heal(EXEC_HEAL)"))
