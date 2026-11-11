extends CharacterBody2D
## Босс «Осквернённый гром» (boss=true) и «отпрыски гнили» (boss=false) —
## моб пещеры трёх ярусов, которых world.gd расставляет по глубине (CAVE_MOB_BANDS).
## Лист assets/brute.png — 64x32, два кадра 32x32.
## Баланс (правка пещеры): герой 3–5 уровня проходит ярусы с потерями, но живым;
## пик сложности — босс. Было: hp 12 / dmg 2 / speed 30 / рывок раз в 4.5 с.

const HIT_DIST_BOSS := 12.0
const HIT_DIST_MOB := 9.0
## Рывок: босс каждые 4.0 с, ярусы 2–3 — реже; ярус 1 не рывкует (cd=0).
const CHARGE_SPEED := 80.0
const CHARGE_TIME := 0.7
const CHARGE_MIN_DIST := 26.0
const LEASH := 64.0        # моб преследует героя только в этом радиусе
const WANDER_R := 24.0     # и бродит не дальше этого от точки появления
const BOSS_HP := 24
const BOSS_DMG := 3
const BOSS_SPEED := 34.0
const BOSS_CHARGE_CD := 4.0
const BOSS_XP := 40
## Дроп алхимических материалов с обычных мобов — то же правило, что у слайма
## (slime.gd): один бросок со смерти, шанс 25%, suhotsvet/zhim 50/50. Босс
## материалов не даёт (материалы — за гринд мобов, не за босса).
const MAT_DROP_CHANCE := 0.25
const MAT_DROP_TABLE := ["suhotsvet", "zhim"]
## Ярусы мобов: чем глубже, тем жирнее, злее и быстрее (xp — за убийство).
const TIERS := {
	1: {"hp": 6, "dmg": 1, "speed": 24.0, "xp": 6, "cd": 0.0, "scale": 0.72},
	2: {"hp": 9, "dmg": 2, "speed": 29.0, "xp": 8, "cd": 6.0, "scale": 0.85},
	3: {"hp": 12, "dmg": 2, "speed": 33.0, "xp": 10, "cd": 4.5, "scale": 1.0},
}

## §D «Пепельные венцы» (NG+ P3): накопительные аффиксы Громы — один за круг,
## на волне w активны венец 1..w (w5 — все пять). Только боевые примитивы:
## контактный ожог / скорость / кибек / агрессия рывка / призыв мглокрысов.
## Новых ассетов и звуков нет; Ведьма исключена фильтром get_script() ниже,
## тир-мобы — веткой boss. Имена — только в код (никаких UI-индикаторов).
const AFFIX_NAMES := ["Тлеющая плоть", "Пепельный ветер", "Костяная кора", "Пепельная ярость", "Улей из золы"]
const AFFIX_SMOLDER := 1      # w1: удар в мили-контакт обжигает атакующего
const AFFIX_ASHWIND := 2      # w2: +20% к скорости преследования
const AFFIX_BONEBARK := 4     # w3: отбрасывание от удара почти не чувствуется
const AFFIX_FURY := 8         # w4: рывок заметно чаще
const AFFIX_SWARM := 16       # w5: из золы поднимаются мглокрысы
const SMOLDER_DMG := 1
const SMOLDER_REACH := 22.0   # «рука, занёсшая меч» — дальность ответного ожога
const ASHWIND_MULT := 1.2
const BONEBARK_KNOCK := 15.0  # базовый кибек в hurt() — 50.0
const FURY_CD := 2.2          # базовый BOSS_CHARGE_CD — 4.0
const SWARM_CD := 6.0         # период подъёма золы
const SWARM_ALIVE_CAP := 2    # живых призывов одновременно — не больше

var world: Node2D
var boss := true           # false — обычный моб (ставит world.gd до setup)
var tier := 3              # актуален только при boss=false
var hp := BOSS_HP
var dmg := BOSS_DMG
var speed := BOSS_SPEED
var charge_cd := BOSS_CHARGE_CD
var kill_xp := BOSS_XP
var hit_dist := HIT_DIST_BOSS
var anim: AnimatedSprite2D
var hurt_t := 0.0
## Заморозка («Морозная нова» мага): >0 — не двигается и не бьёт, синий тинт.
var freeze_t := 0.0
var charge_t := 2.5
var rush_t := 0.0
var rush_dir := Vector2.ZERO
## Страж повторной смерти: queue_free откладывается до конца кадра, и залп
## (volley) успевал «убить» моба 2–3 раза — двойной XP и quest_changed (фикс T3).
var dying := false
## Однократный флаг на инстанс босса: первый заход героя в радиус агрессии
## (LEASH) включает tension-тему. Обычные мобы её НЕ триггерят.
var tension_played := false
var home := Vector2.ZERO
var wander_t := 0.0
var wander_dir := Vector2.ZERO
var base_tint := Color.WHITE
## §D: битовая маска активных венцов (0 — чистый босс) и учёт «Улья из золы».
var affix_mask := 0
var ash_tile := Vector2i.ZERO
var ash_timer := 0.0
var ash_summons: Array = []   # инстансы поднятой золы (учёт SWARM_ALIVE_CAP)

func setup(p_world: Node2D, tile: Vector2i) -> void:
	world = p_world
	if not boss:
		var cfg: Dictionary = TIERS[tier]
		hp = int(cfg.hp)
		dmg = int(cfg.dmg)
		speed = float(cfg.speed)
		charge_cd = float(cfg.cd)
		kill_xp = int(cfg.xp)
		hit_dist = HIT_DIST_MOB
		base_tint = Color(0.86, 0.92, 1.0) if tier == 1 else (Color(1.0, 0.96, 0.86) if tier == 2 else Color(0.94, 0.84, 1.0))
	# NG+ §1.3: скейл базы (tier/boss) по волне при инициализации. Скорость,
	# рывок и XP не скейлятся — читаемость ударов и баланс прокачки.
	# Исключение: Ведьма Пепелища (mob_boss2.gd, зовёт super.setup) — конечна
	# флагу ashen.boss, вне круга: её скейлить = тихо ломать баланс зоны-2.
	if get_script() == load("res://scripts/brute.gd"):
		var w := GameState.ng_wave()
		hp = int(round(hp * GameState.hp_mult(w)))
		dmg += GameState.dmg_bonus(w)
		# §D: венец носит настоящая Грома: тир-мобы — не боссы, Ведьма не проходит
		# фильтр get_script() выше. hp_mult здесь НЕ применяется повторно — база
		# уже проскейлена двумя строками выше; аффиксы живут на примитивах.
		if boss and w >= 1:
			ash_tile = tile
			affix_mask = (1 << mini(w, AFFIX_NAMES.size())) - 1
			if (affix_mask & AFFIX_ASHWIND) != 0:
				speed *= ASHWIND_MULT
			if (affix_mask & AFFIX_FURY) != 0:
				charge_cd = FURY_CD
			if (affix_mask & AFFIX_SWARM) != 0:
				ash_timer = SWARM_CD
	position = world.tile_to_world(tile)
	home = position
	collision_layer = 4
	collision_mask = 2 | 4  # слой героя (1) убран: вместо взаимной блокировки — мягкое выталкивание (_push_from_hero)
	add_to_group("enemy")
	if boss:
		add_to_group("boss")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(18, 16) if boss else Vector2(10, 8)  # моб проходит узкие проходы
	cs.shape = sh
	add_child(cs)
	anim = AnimatedSprite2D.new()
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	fr.add_animation("walk")
	fr.set_animation_loop("walk", true)
	fr.set_animation_speed("walk", 2.5)
	if ResourceLoader.exists("res://assets/brute.png"):
		var tex := load("res://assets/brute.png")
		for col in [0, 1]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(col * 32, 0, 32, 32)
			fr.add_frame("walk", at, 0.0)
		anim.sprite_frames = fr
		add_child(anim)
		anim.play("walk")
		if not boss:
			anim.scale = Vector2.ONE * float(TIERS[tier].scale)  # ярус 1 мельче, ярус 3 полный
	else:
		push_warning("Нет ассета: assets/brute.png — у босса цветная заглушка")
		var ph := ColorRect.new()
		ph.color = Color(0.45, 0.28, 0.5)
		ph.size = Vector2(24, 22)
		ph.position = Vector2(-12, -11)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ph)
	modulate = base_tint

func _physics_process(delta: float) -> void:
	if dying:
		return
	hurt_t = maxf(0.0, hurt_t - delta)
	freeze_t = maxf(0.0, freeze_t - delta)
	if hurt_t > 0.0:
		modulate = Color(1, 0.5, 0.5)
	elif freeze_t > 0.0:
		modulate = Color(0.55, 0.75, 1.0)
	else:
		modulate = base_tint
	if GameState.input_locked or world.player == null or GameState.hp <= 0:
		velocity = Vector2.ZERO
		return
	if freeze_t > 0.0:
		velocity = Vector2.ZERO
		_push_from_hero()  # мёрзлый гром тоже уступает место герою, не лежит под ним
		return
	var player: CharacterBody2D = world.player
	var d := global_position.distance_to(player.global_position)
	if boss and not tension_played and d <= LEASH:
		# герой впервые подошёл к боссу вплотную — саспенс-тема (кроссфейд внутри GameAudio)
		tension_played = true
		GameAudio.music("tension")
	# §D w5 «Улей из золы»: пока герой в радиусе агрессии, зола поднимает мглокрыса
	# раз в SWARM_CD; живых призывов не больше SWARM_ALIVE_CAP (учёт в _spawn_ash).
	if boss and (affix_mask & AFFIX_SWARM) != 0 and d <= LEASH:
		ash_timer -= delta
		if ash_timer <= 0.0:
			ash_timer = SWARM_CD
			_spawn_ash()
	if not boss and d > LEASH:
		# героя далеко нет — не идём на весь cave, а сторожим свою часть пещеры
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(1.0, 2.4)
			var off := global_position - home
			if off.length() > WANDER_R or randf() < 0.3:
				wander_dir = -off.normalized()
			else:
				wander_dir = Vector2(randf() - 0.5, randf() - 0.5).normalized()
		velocity = wander_dir * speed * 0.4
		move_and_slide()
		if global_position.distance_to(player.global_position) < hit_dist:
			player.take_damage(dmg)
		return
	if rush_t > 0.0:
		rush_t -= delta
		if hurt_t <= 0.0 and freeze_t <= 0.0:
			modulate = Color(1.15, 0.7, 0.55)
		velocity = rush_dir * CHARGE_SPEED
	else:
		charge_t -= delta
		if charge_cd > 0.0 and charge_t <= 0.0 and d > CHARGE_MIN_DIST:
			charge_t = charge_cd
			rush_t = CHARGE_TIME
			rush_dir = (player.global_position - global_position).normalized()
			if boss:
				GameState.toast.emit("Гром бросается вперёд — отходи!")
		else:
			velocity = (player.global_position - global_position).normalized() * speed
	move_and_slide()
	_push_from_hero()  # до проверки урона: оценка боя идёт на равновесном контакте, как при живой стене
	if global_position.distance_to(player.global_position) < hit_dist:
		player.take_damage(dmg)

## «Стенка без пиления» (дребезг экрана вплотную): герой (слой 1) убран из маски —
## два CharacterBody2D при упоре друг в друга пилят каждый кадр в противофазе, а
## камера висит на герое. Гром уступает сам: отход вдоль оси наименьшего
## проникновения боксов до старого физического контакта (моб 10x8, босс 18x16) —
## пороги hit_dist (9/12) ведут себя ровно как на живой стене. Стены для отхода —
## препятствия: в углу герой может влезть в грома, дребезга при этом нет.
func _push_from_hero() -> void:
	if world == null or world.player == null:
		return
	var d: Vector2 = global_position - world.player.global_position
	var mb := Vector2(18, 16) if boss else Vector2(10, 8)
	var ox := (mb.x + 10.0) * 0.5 - absf(d.x)
	var oy := (mb.y + 8.0) * 0.5 - absf(d.y)
	if ox <= 0.0 or oy <= 0.0:
		return
	if ox < oy:
		var sx := signf(d.x)
		if sx == 0.0:
			sx = 1.0  # точное совпадение центров — отход вправо
		move_and_collide(Vector2(sx * (ox + 0.05), 0.0))
	else:
		var sy := signf(d.y)
		if sy == 0.0:
			sy = -1.0  # точное совпадение центров — отход вверх
		move_and_collide(Vector2(0.0, sy * (oy + 0.05)))

func hurt(dmg_in: int, from: Vector2) -> void:
	if dying:
		return  # труп не получает урон: XP и quest_changed — ровно один раз (фикс T3)
	GameState.entered_combat()  # контакт с врагом — реген паузится
	DmgNumbers.spawn(global_position + Vector2(0, -12), dmg_in, "normal")
	hp -= dmg_in
	hurt_t = 0.3
	# §D w3 «Костяная кора»: удар почти не сносит Грому с места (база — 50.0).
	velocity = (global_position - from).normalized() * (BONEBARK_KNOCK if (affix_mask & AFFIX_BONEBARK) != 0 else 50.0)
	# §D w1 «Тлеющая плоть»: ударивший в мили-контакт обжигается пеплом.
	# Ай-фреймы героя гасят повторные ожоги — сдвоенного урона не будет.
	if (affix_mask & AFFIX_SMOLDER) != 0 and world.player != null \
			and global_position.distance_to(world.player.global_position) <= SMOLDER_REACH:
		world.player.take_damage(SMOLDER_DMG)
	if hp <= 0:
		dying = true
		remove_from_group("enemy")  # мёртвый моб больше не бьёт и не целивается
		if boss:
			GameState.boss_defeated = true
			Achv.on_boss_death()  # ачивки «Убийца босса» / «хардкор» (achv.gd)
			# §4.1: +3 Пепла ровно один раз за круг — гейт флагом ng.boss_<волна>
			var boss_key := "ng.boss_%d" % GameState.ng_wave()
			if int(GameState.flags.get(boss_key, 0)) == 0:
				GameState.set_flag(boss_key, 1)
				# Талант «Шёпот алтаря» (whisper, CONTRACT_TALENTS §3): +1 пепла
				# за убитого босса круга; дедуп ng.boss_ выше не трогаем.
				Achv.grant_ash(3 + (1 if GameState.tal_rank("whisper") > 0 else 0))
			GameState.add_xp(BOSS_XP)
			GameState.toast.emit("Гниль отступает!")
			# tension смолкла: возвращаем тему пещеры, только если герой ещё в ней;
			# при выходе из пещеры «forest» поставит world.apply_zone как обычно
			if GameState.in_cave:
				GameAudio.music("cave")
		else:
			GameState.add_xp(kill_xp)
			GameState.toast.emit("Отпрыск гнили повержен! (+%d опыта)" % kill_xp)
			_roll_mat_drop()
		var loot_kind := "boss" if boss else ("brute" if tier == 1 else "brute_t%d" % tier)
		Loot.on_mob_death(loot_kind, global_position)
		GameState.quest_changed.emit()
		queue_free()

## Один бросок на материал со смерти моба — копия правила slime.gd; при полном
## рюкзаке — трофей теряется (дефицит). Зовётся ровно раз: hurt() по dying не проходит.
func _roll_mat_drop() -> void:
	# Талант «Травничество» (herblore, CONTRACT_TALENTS §3): шанс дропа 0.25 -> 0.32.
	if randf() >= (0.32 if GameState.tal_rank("herblore") > 0 else MAT_DROP_CHANCE):
		return
	var mid := String(MAT_DROP_TABLE[randi() % MAT_DROP_TABLE.size()])
	if not GameState.add_material(mid):
		GameState.toast.emit("Рюкзак полон — %s потерян" % GameState.mat_name(mid))
		return
	GameState.toast.emit("Трофей: %s (%d/%d)" % [GameState.mat_name(mid), GameState.mat_count(mid), GameState.MAT_CAP])

## §D w5: один мглокрыс из золы. Существующий mob_swarmling со СВОИМ id стаи —
## общий «испуг» не смешивает его с зональными стаями; трюк размещения — как у
## стражей Ведьмы: в контейнер зоны босса, setup на клетку босса, затем ручной
## оффсет (у пещерной зоны free_neighbours нет — поэтому сразу точкой).
func _spawn_ash() -> void:
	var alive := 0
	for r in ash_summons:
		if is_instance_valid(r):
			alive += 1
	if alive >= SWARM_ALIVE_CAP:
		return  # зола не затапливает арену: потолок живых призывов
	var rt = load("res://scripts/mob_swarmling.gd").new()
	rt.swarm_id = "brute_ash_%d" % get_instance_id()
	var zone: Node = get_parent()
	if zone != null:
		zone.add_child(rt)
	else:
		add_child(rt)
	rt.setup(world, ash_tile)
	rt.global_position = global_position + Vector2(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0))
	rt.self_modulate = Color(1.0, 0.82, 0.55)  # пепельный оттенок — приём Ведьмы, без нового ассета
	ash_summons.append(rt)
