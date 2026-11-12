extends "res://scripts/brute.gd"
## Мини-босс «Ведьма Пепелища» — наследник «Осквернённого грома» (brute.gd),
## перекрашенного листом brute.png (новых ассетов не просили). Отличие от Грома:
## hp x2 (48), скорость x0.9 (~30.6), урон прежний (3), пепельно-сиренцевый
## тинт + чуть крупнее; РЫВОК ВЫКЛЮЧЕН (charge_cd = 0): унаследованный рывок
## эмитит тост «Гром бросается вперёд» прямо из _physics_process — переопределить
## одну строку нельзя, а врать игроку про Грома нельзя; ведьма берёт числом.
## Механика: на 50% hp РОВНО ОДИН раз поднимает РОВНО ДВОИХ мглокрысов-стражей
## (флаг guard_done; повторные пересечения порога и добивание — тише воды).
## Персист смерти — GameState.flags["ashen.boss"] = "dead" (cave_state и
## boss_defeated НЕ трогаем: это сейв-v2-совместимый флаг Пепелища).
## Лут — Loot.on_mob_death("boss2", ...): строка таблицы GearData.LOOT.

const WITCH_XP := 25           # ниже Грома (40): это мини-босс боковой зоны
const HP_SCALE := 2.0          # hp x2 от BOSS_HP
const SPEED_SCALE := 0.9       # скорость x0.9 от BOSS_SPEED
const GUARD_SWARM := "witch_guard"
const TINT_WITCH := Color(0.80, 0.70, 0.86)  # пепел + сиренцевая ведьмина дымка
const TINT_GUARD := Color(1.0, 0.78, 0.6)    # стража: искра из золы

var hp_full := 0               # порог «половина здоровья» считаем от него
var guard_done := false        # страж spawn'ится ровно один раз на инстанс
var home_tile := Vector2i.ZERO

func setup(p_world: Node2D, tile: Vector2i) -> void:
	boss = true                # крупный хитбокс, группа "boss", tension-тема
	hp = int(round(BOSS_HP * HP_SCALE))
	hp_full = hp
	dmg = BOSS_DMG             # урон не повышаем: зона проходима на 4–6 уровне
	speed = BOSS_SPEED * SPEED_SCALE
	charge_cd = 0.0            # см. шапку: без унаследованного рывка и его тоста
	boss_leash = 110.0         # сторожим арену: радиус 110 px (значение из
	# моб-наборов прошлых волн); прямолинейный
	# преслед без pathfinding в генераторной геометрии упирался в стены комнат
	hit_dist = 15.0            # бокс босса 18x16 + герой 10x8: пол контакта центр-в-центр
	# 14 px, база HIT_DIST_BOSS=12 была геометрически недостижима — удар не срабатывал
	base_tint = TINT_WITCH
	home_tile = tile
	super.setup(p_world, tile)
	if anim != null and not gen_art:
		# SCALE_CANON: Ведьма Пепелища = 1.6H = 51 px (32px-кадр × 1.59375).
		# s_old — прежний базис «главнее отпрысков» (+12%), от него считается
		# якорь по контент-стопу +11: стопы Ведьмы остаются там, где стояли.
		# (t17: на ген-ассете якорь уже посчитан в brute.setup через виртуалы.)
		var s_old := 1.12
		var s := 51.0 / 32.0
		anim.scale = Vector2.ONE * s
		anim.position = Vector2(0, 11.0 * (s_old - s))

# t17: ген-ассет Ведьмы (art_gen witch v2) — тот же канон 51 px, что ниже
# отпрысков Грома; линия ног старой Ведьмы на brute.png = 13.91375
# (12·1.59375 + 11·(1.12−1.59375), замер по старому кадру).
func gen_tex_path() -> String:
	return "res://assets/art/mob_witch.png"

func gen_canon_h() -> float:
	return 51.0

func gen_foot_old() -> float:
	return 13.91375

func hurt(dmg_in: int, from: Vector2) -> void:
	if dying:
		return  # труп не получает урон: XP, флаг и лут — ровно один раз
	GameState.entered_combat()
	hp -= dmg_in
	hurt_t = 0.3
	velocity = (global_position - from).normalized() * 50.0
	if not guard_done and hp > 0 and hp * 2 <= hp_full:
		guard_done = true      # до спавна: даже рекурсивный hurt стражей не повторит
		_spawn_guard()
	if hp <= 0:
		dying = true
		remove_from_group("enemy")
		remove_from_group("boss")
		GameState.set_flag("ashen.boss", "dead")  # персист: cave_state не трогаем
		Achv.on_witch_death()  # ачивка «Пепел ведьмы» (+1 Пепел, однократно; achv.gd)
		GameState.add_xp(WITCH_XP)
		GameState.toast.emit("Ведьма Пепелища осыпается пеплом! (+%d опыта)" % WITCH_XP)
		# tension смолкла: возвращаем тему Пепелища (трек "cave" — нет нового ассета)
		var area: Variant = world.get("active_area")
		if area == "ashen" or GameState.in_cave:
			GameAudio.music("cave")
		Loot.on_mob_death("boss2", global_position)
		GameState.quest_changed.emit()  # автосейв: флаг смерти осядет в сохранении
		queue_free()

## Ровно два мглокрыса-стража на свободных клетках вокруг арены (кольца 1..3),
## child'ятся в контейнер зоны — координаты локальные, как у всех мобов.
func _spawn_guard() -> void:
	GameState.toast.emit("Ведьма свистит — из золы поднимаются стражи!")
	var zone: Node = get_parent()
	var spawned := 0
	if zone != null and zone.has_method("free_neighbours") and zone.has_method("tile_to_world"):
		for t: Vector2i in zone.free_neighbours(home_tile, 2):
			var rt = load("res://scripts/mob_swarmling.gd").new()
			rt.swarm_id = GUARD_SWARM  # до setup: общий реестр стаи
			zone.add_child(rt)
			rt.setup(world, t)
			rt.self_modulate = TINT_GUARD
			spawned += 1
			if spawned >= 2:
				break
	if spawned < 2:
		# страховка: арена без свободных клеток (недостижимо на нашей карте) —
		# ставим стражей setup'ом на клетку ведьмы и разводим руками,
		# лишь бы механика «ровно двое» отработала
		for off: Vector2 in [Vector2(-14, 10), Vector2(14, 10)]:
			if spawned >= 2:
				break
			var rt = load("res://scripts/mob_swarmling.gd").new()
			rt.swarm_id = GUARD_SWARM
			if zone != null:
				zone.add_child(rt)
			else:
				add_child(rt)
			rt.setup(world, home_tile)
			rt.global_position = rt.global_position + off
			rt.self_modulate = TINT_GUARD
			spawned += 1
