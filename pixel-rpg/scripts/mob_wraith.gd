extends CharacterBody2D
## Тенеплёт: медленный призрак пещеры. В «эфирном» состоянии полупрозрачен,
## неуязвим и проходит сквозь стены КОРОТКИМИ РЫВКАМИ-фазами (0.35 с). Перед
## ударом ОБЯЗАН материализоваться: 1.1 с уплотнения (альфа 0.35 -> 1.0 как
## телеграф), и только в материализации получает урон и бьёт контактом.
## Нечестного «неуязвимого тарана» нет: фаза не наносит урона вовсе.
## «Вечного призрака» нет: в эфире/фазе тело прозрачно для героя (слой 0,
## маска без слоя 1), а ETHEREAL ограничен ETH_MAX_TIME — дальше форс-окно.
## HP 8, урон 2. НИША ПЕЩЕРЫ СНЯТА вердиктом 26.11 (т28, «Тень-заимка»):
## в пещере и деревне тенеплётов нет и не было с c21 (qa_wr0 ноль-пины);
## живут Пепелище (ashen_zone, координаты mobs.wraiths, row=4 — часть вердикта)
## и подземелье (biome_zone/BESTIARY). Лист assets/mobs_wraith.png — 48x64:
## 3 кадра (парение / взмах / материализация) на 4 ряда (вниз / влево / вправо / вверх);
## состояния «Тень-заимка» — отдельный носитель assets/mobs_wraith_state_v1.png.

enum { ETHEREAL, PHASING, MATERIALIZING }

const LEASH := 110.0          # радиус интереса: дальше — бродит у ниши
const DASH_SPEED := 95.0
const DASH_TIME := 0.35       # длительность фазы сквозь стены
const DASH_CD_MIN := 1.8      # новый рывок не чаще этого
const DASH_CD_JITTER := 0.6
const MAT_TIME := 1.1         # окно материализации: окно уязвимости и удара
const SPEED_DRIFT := 22.0     # блуждание в эфире
const SPEED_MAT := 26.0       # медлителен в материализации — наказуем
const HIT_DIST := 10.0
const ALPHA_ETH := 0.45
const ALPHA_PHASE := 0.3
const MAX_HP := 8
const ETH_MAX_TIME := 3.5     # кап «вечного эфира»: принудительное окно уязвимости
## t51 (возврат «до Крупного мира»): тенеплёт 16 px 1:1 (коллайдер 10x8,
## фазы/скорости — прежние). Якорь ZERO, призрак «парит» там же, где был.
const VISUAL_SCALE := 1.0

# ---------------------------------------------------------------------------
# t28 «Ощущение v1» C «Тень-заимка» (26.11, вердикт «принимай пока что слизня
# и призрака»; лист W5 §4, PINS_W5.md). ОПТ-ИН: feel_v1=true выставляют
# спавнеры базовых тенеплётов — ashen_zone (Пепелище, row=4) и biome_zone
# (подземелье). Носители видов t26 ( whisperer/miner) и мини-боссы ездят на
# ЛЕГАСИ-движке: лицо вида — не смена механики (закон листа). Ядро ETHEREAL/
# PHASING/MATERIALIZING ниже не тронуто — прежние пины qa_wr/qa_wr0 зелёные.
# Автомат (ФИНАЛЬНЫЕ числа — правки вердиктов 26.11, в т.ч. 11:26; первичные
# окна листа W5 §4 1.5/6.0/2.0 заменены, история — BALANCE и PINS_W5 §8):
# CHASE (3.0 c, видим, уязвим, контакт бьёт) -> FLIGHT (1.0 c,
# ВСЕГДА фаза сквозь стены, кадр possess 4x180мс — окно наказания) ->
# OCCUPIED (3.5 c в хозяине: кант occupied 2x300мс, дымка мерцает, хозяин урон
# x1.5 скорость x1.4, призрак не достать; ХОЗЯИН сквозь стены НЕ ходит) ->
# урон по хозяину или его смерть = BANISH (3x60мс, тряска banish 1.0px/100мс
# из таблицы §3) -> STUN 2.5 c (звёзды stun 2x250мс, без фазы, честное
# анти-окно: бьётся freely для игрока, сам не бьёт) -> CHASE + анти-захватный
# замок G_REPOS_S 2.5 c. Вход в любое уязвимое состояние помечен золотым бликом
# FLASH_MAT 0.15 c + звук spell — «можно бить» читается без гадания (11:26,
# п.3). Факел при герое (GameState.torches, t30): в 72 px вселение срывается,
# у огня не преследует и не хватает, из хозяина выкуривает за 0.8 c. Хозяин:
# ближайший моб/слизень в G_HOST_R=96, живой, не призрак, не занятый чужим.
# Фаза — ТОЛЬКО в полёте вселения.
# ---------------------------------------------------------------------------
var feel_v1 := false
enum { F_CHASE, F_FLIGHT, F_OCCUPIED, F_STUN }
const G_CHASE_S := 3.0      # погоня не дольше; дальше ищет хозяина
const G_FLIGHT_S := 1.0     # полёт вселения: окно урона, фаза сквозь стены
                            # ^ правка вердикта 26.11 11:26: 1.5 -> 1.0 (доля уязвимого времени)
const G_HOLD_S := 3.5       # оккупация: хозяин buff, призрак в нём
                            # ^ правка вердикта 26.11 11:26: 6.0 -> 3.5 (там же)
const G_STUN_S := 2.5       # изгнание: отшатнулся, без фазы
                            # ^ правка вердикта 26.11 11:26: 2.0 -> 2.5 (там же)
const G_REPOS_S := 2.5      # анти-захватный замок: после изгнания/выкуривания
                            # не тянется к хозяину — игрок видит открытую фигуру
const G_TORCH_R := 72.0     # факел в руках героя: радиус выкуривания/устрашения
const G_SMOKE_S := 0.8      # факел: задержка выкуривания из хозяина
const FLASH_MAT := 0.15     # золотой блик ВХОДА в уязвимость (правка 11:26, п.3)
const G_HOST_R := 96.0      # радиус поиска хозяина
const G_BUFF_DMG := 1.5     # хозяин: урон (round)
const G_BUFF_SPD := 1.4     # хозяин: скорость (где var speed есть)
const G_FLIGHT_SPEED := 80.0
const ALPHA_OCC := 0.18     # в хозяине: призрак — дымка-намёк
var f_state := F_CHASE
var f_t := 0.0
var f_host: Node2D = null
var f_host_hp := 0
var f_dir := Vector2.ZERO
var f_ovl: AnimatedSprite2D = null   # кадры листа C: mobs_wraith_state_v1.png
var f_lock := 0.0     # анти-захватный замок (правка вердикта 26.11 11:26)
var f_flash := 0.0    # >0 — золотой блик входа в уязвимость (тот же пункт)
var f_smoke := 0.0    # отсчёт выкуривания факелом из хозяина

var world: Node2D
var hp := MAX_HP
var max_hp := MAX_HP
## t3 «Мир v1» (локации): kind дропа с поясом и множитель урона — по умолчанию
## канон ("wraith", ×1).
var loot_kind := ""
var kill_kind := ""  # t26 «Бестиарий v2»: имя вида (шептун/рудокоп); пусто — «wraith»
var dmg_mult := 1.0
var anim: AnimatedSprite2D
var hurt_t := 0.0
## Заморозка («Морозная нова» мага): >0 — замирает (и фаза прерывается), синий тинт.
var freeze_t := 0.0
var state := ETHEREAL
var dash_cd := 1.0
var dash_t := 0.0
var dash_dir := Vector2.ZERO
var mat_t := 0.0
var eth_t := 0.0              # время в текущем ETHEREAL (кап ETH_MAX_TIME)
var facing := "down"
var home := Vector2.ZERO
var wander_t := 0.0
var wander_dir := Vector2.ZERO
var last_safe := Vector2.ZERO # последняя проходимая точка — выход из фазы в стене
var dying := false            # страж повторной смерти: XP — ровно один раз
var kill_xp := 15             # t20: XP со смерти (мини-боссы ×3; дефолт = прежняя конста)
var _shape: CollisionShape2D

func setup(p_world: Node2D, tile: Vector2i) -> void:
	world = p_world
	position = world.tile_to_world(tile)
	home = position
	last_safe = position
	add_to_group("enemy")
	_enter_ethereal()  # старт — эфир: тело прозрачно для героя
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(10, 8)
	cs.shape = sh
	add_child(cs)
	_shape = cs
	anim = AnimatedSprite2D.new()
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	if ResourceLoader.exists("res://assets/mobs_wraith.png"):
		var tex := load("res://assets/mobs_wraith.png")
		var rows := {"down": 0, "left": 1, "right": 2, "up": 3}
		for dir_name: String in rows.keys():
			var row: int = int(rows[dir_name])
			for kind: Array in [["idle", [0, 1], true, 2.0], ["walk", [0, 1], true, 4.0], ["act", [2], false, 0.0]]:
				var an := "%s_%s" % [String(kind[0]), dir_name]
				fr.add_animation(an)
				fr.set_animation_loop(an, bool(kind[2]))
				if bool(kind[2]):
					fr.set_animation_speed(an, float(kind[3]))
				for col: int in kind[1]:
					var at := AtlasTexture.new()
					at.atlas = tex
					at.region = Rect2(col * 16, row * 16, 16, 16)
					fr.add_frame(an, at, 0.0)
		anim.sprite_frames = fr
		add_child(anim)
		anim.scale = Vector2.ONE * VISUAL_SCALE
		anim.position = Vector2.ZERO  # t51 «было»: якорь в центре ноды
		anim.play("idle_down")
	else:
		push_warning("Нет ассета: assets/mobs_wraith.png — у тенеплёта цветная заглушка")
		var ph := ColorRect.new()
		ph.color = Color(0.45, 0.32, 0.6)
		ph.size = Vector2(11, 13)
		ph.position = Vector2(-5, -7)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ph)
	modulate = Color(1, 1, 1, ALPHA_ETH)
	if feel_v1:
		feel_start()

func _physics_process(delta: float) -> void:
	if dying:
		return
	hurt_t = maxf(0.0, hurt_t - delta)
	freeze_t = maxf(0.0, freeze_t - delta)
	if feel_v1:
		# t28 «Тень-заимка»: собственный автомат; заморозка — тот же стоп-кадр,
		# что у легаси (окно урона не отменяется: в OCCUPIED мороз не прячет).
		if GameState.input_locked or world.player == null or GameState.hp <= 0:
			velocity = Vector2.ZERO
			return
		_tick_feel(0.0 if freeze_t > 0.0 else delta)
		if hurt_t > 0.0:
			modulate = Color(1.8, 0.62, 0.55, modulate.a)
		return
	if GameState.input_locked or world.player == null or GameState.hp <= 0:
		velocity = Vector2.ZERO
		return
	if freeze_t > 0.0:
		# заморозка «выбрасывает» тенеплёта из фазы обратно в эфир
		_enter_ethereal()
		modulate = Color(0.55, 0.75, 1.0, ALPHA_ETH)
		velocity = Vector2.ZERO
		return
	var player: CharacterBody2D = world.player
	match state:
		PHASING:
			_tick_phase(delta)
		MATERIALIZING:
			_tick_materialize(delta, player)
		_:
			_tick_ethereal(delta, player)
	if hurt_t > 0.0:
		modulate = Color(1.8, 0.62, 0.55, modulate.a)  # t18: горячая вспышка ≤0.1 с

## Эфир: полупрозрачное блуждание, подпускание героя; рывок-фаза по кулдауну.
func _tick_ethereal(delta: float, player: CharacterBody2D) -> void:
	eth_t += delta
	if eth_t >= ETH_MAX_TIME:
		# анти-«вечный призрак»: рывок заводится лишь при d>24 — если герой
		# прижался вплотную, фаза не наступит никогда и неуязвимое тело
		# заблокирует проход. Материализуемся принудительно: у игрока всегда
		# есть окно урона (дальний цикл в кап не попадает: кулдаун 1.8..2.4).
		_enter_materialize()
		velocity = Vector2.ZERO
		return
	var d := global_position.distance_to(player.global_position)
	if d > LEASH:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(1.4, 3.0)
			var off := global_position - home
			if off.length() > 28.0 or randf() < 0.3:
				wander_dir = -off.normalized() if off != Vector2.ZERO else Vector2.ZERO
			else:
				wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		velocity = wander_dir * SPEED_DRIFT * 0.6
	else:
		velocity = (player.global_position - global_position).normalized() * SPEED_DRIFT
		dash_cd -= delta
		if dash_cd <= 0.0 and d > 24.0:
			# рывок сквозь стены: сквозь камень, но без урона — урон только «в теле»
			dash_dir = (player.global_position - global_position).normalized()
			_enter_phase()  # стены (2) и герой (1) игнорируются только на время фазы
			GameAudio.sfx("roll")   # шелест «уходящей» тени
	dash_cd = maxf(dash_cd, 0.0)
	_remember_safe()
	_face(player.global_position - global_position)
	_anim(false)
	move_and_slide()
	modulate = Color(1, 1, 1, ALPHA_ETH) if hurt_t <= 0.0 else modulate

## Фаза: короткий бросок сквозь камень. Урона нет; в конце — материализация.
func _tick_phase(delta: float) -> void:
	dash_t -= delta
	velocity = dash_dir * DASH_SPEED
	move_and_slide()
	modulate = Color(0.85, 0.7, 1.0, ALPHA_PHASE)
	if dash_t <= 0.0:
		# влезли в камень — откат на последнюю проходимую точку
		if not _tile_walkable(global_position):
			global_position = last_safe
		_enter_materialize()
		velocity = Vector2.ZERO

## Материализация: уплотнение (альфа-телеграф), медленное сближение, контакт-удар.
## Только здесь тенеплёт уязвим — hurt() вне этого состояния урон не принимает.
func _tick_materialize(delta: float, player: CharacterBody2D) -> void:
	mat_t -= delta
	var k := clampf(1.0 - mat_t / MAT_TIME, 0.0, 1.0)
	modulate = Color(1, 1, 1, lerpf(ALPHA_PHASE, 1.0, k)) if hurt_t <= 0.0 else modulate
	var to_p := player.global_position - global_position
	velocity = to_p.normalized() * SPEED_MAT if mat_t > 0.0 else Vector2.ZERO
	_face(to_p)
	_anim(true)
	move_and_slide()
	_push_from_hero()  # только «в теле»: эфирное прошлое тело героя не трогает и не пилит
	if to_p.length() < HIT_DIST:
		player.take_damage(maxi(1, int(round(2.0 * dmg_mult))), (kill_kind if kill_kind != "" else "wraith"))  # t20: kind убийцы для экрана смерти
	if mat_t <= 0.0:
		_enter_ethereal()
		dash_cd = DASH_CD_MIN + randf_range(0.0, DASH_CD_JITTER)

## Точки входа в состояния — единственный «канал» слоёв/масок. В «прозрачных»
## состояниях (ETHEREAL/PHASING) слой обнулён: призрак не блокирует героя, а
## герой — призрака (в фазе он, как и прежде, идёт сквозь камень); маска
## не видит слой героя (1), стены (2) и соседей (4) — по-прежнему ощутимы.
## Физическое тело и контактный урон «отрастают» только в MATERIALIZING.
func _enter_ethereal() -> void:
	state = ETHEREAL
	eth_t = 0.0
	dash_t = 0.0
	collision_layer = 0
	collision_mask = 2 | 4

func _enter_phase() -> void:
	state = PHASING
	dash_t = DASH_TIME
	collision_layer = 0
	collision_mask = 4

func _enter_materialize() -> void:
	state = MATERIALIZING
	mat_t = MAT_TIME
	dash_t = 0.0
	collision_layer = 4
	collision_mask = 2 | 4  # герой (1) — вне маски и в «теле»: стенку даёт _push_from_hero, не физический спор

## «Стенка без пиления» — только для MATERIALIZING (единственного телесного
## состояния): герой (слой 1) убран из маски материализации, иначе два
## CharacterBody2D при упоре пилят каждый кадр в противофазе и камера дребезжит.
## Отход вдоль оси наименьшего проникновения боксов до старого контакта (10x8);
## эфир и фаза остаются прозрачными для героя — «проход сквозь дымку» не трогали.
func _push_from_hero() -> void:
	if world == null or world.player == null:
		return
	var d: Vector2 = global_position - world.player.global_position
	var mb := Vector2(10, 8)
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

func _hurt_flash() -> void:
	modulate = Color(1, 0.5, 0.5, modulate.a)

## Помечаем проходимую точку, чтобы фаза, кончившаяся в породе, «выплевывалась» наружу.
func _remember_safe() -> void:
	if _tile_walkable(global_position):
		last_safe = global_position

## Проходимость тайла под центром: зона (пещера/деревня) сама знает свою карту.
## Позицию переводим в локальные координаты зоны — cave_zone несёт CAVE_OFFSET.
func _tile_walkable(pos: Vector2) -> bool:
	if get_parent() != null and get_parent().has_method("cell_walkable"):
		var z: Node2D = get_parent()
		var lp := z.to_local(pos)
		var t := Vector2i(floori(lp.x / 16.0), floori((lp.y - 2.0) / 16.0))
		return bool(z.call("cell_walkable", t))
	var lp2 := to_local(pos)
	var t2 := Vector2i(floori(lp2.x / 16.0), floori((lp2.y - 2.0) / 16.0))
	return bool(world.call("_village_walkable", t2))

func _face(dvec: Vector2) -> void:
	if absf(dvec.x) > absf(dvec.y):
		facing = "right" if dvec.x > 0.0 else "left"
	else:
		facing = "up" if dvec.y < 0.0 else "down"

func _anim(mat: bool) -> void:
	if anim == null or anim.sprite_frames == null or not anim.sprite_frames.has_animation("idle_down"):
		return
	var want := "act" if mat else ("walk" if velocity.length_squared() > 1.0 else "idle")
	var an := "%s_%s" % [want, facing]
	if anim.animation != an:
		anim.play(an)

func hurt(dmg: int, from: Vector2) -> void:
	if dying:
		return  # труп не получает урон: XP и quest_changed — ровно один раз
	GameState.entered_combat()  # контакт с врагом — реген паузится
	if feel_v1 and f_state == F_OCCUPIED:
		# t28: в хозяине призрак не достать — клинок проходит дымкой.
		# Изгнание рождает удар ПО ХОЗЯИНУ (poll его hp в _tick_feel).
		_hurt_flash()
		return
	if not feel_v1 and state != MATERIALIZING:
		# эфир и фаза неуязвимы: клинок проходит сквозь дымку — только вспыхнет
		_hurt_flash()
		return
	hp -= dmg
	hurt_t = 0.09  # t18: вспышка цели ≤0.1 с
	Juice.hit()    # t18 «сочность»: hitstop + мазок (гарантии восстановления — juice.gd)
	Juice.shake(0.8, 0.09)
	BoldFx.splat(global_position + Vector2(0, -4), global_position - from, world)  # t23 W5B брызги
	velocity = (global_position - from).normalized() * 40.0
	if hp <= 0:
		dying = true
		BoldFx.death_shadow(global_position)  # t23 W5B: тень-лужа в палитре поля
		remove_from_group("enemy")
		GameAudio.sfx("drop")
		GameState.add_xp(kill_xp)
		Achv.count("kill_wraith")  # счётчик убийств (achv.gd)
		GameAudio.sfx("coin")
		GameState.toast.emit("Тенеплёт рассеян! (+15 опыта)")
		Loot.on_mob_death(loot_kind if loot_kind != "" else "wraith", global_position, world)
		GameState.quest_changed.emit()
		queue_free()

# ============================================================ t28 «Тень-заимка»
# Автомат feel_v1 (см. константы выше). Кадры — лист W5 секция C, рантайм-носитель
# assets/mobs_wraith_state_v1.png (кодо-бейк feel_v1_bake.gd, FNV-равен листу).

func feel_start() -> void:
	# вызывается спавнером ДО/ПОСЛЕ setup(): состояние стартует с погони.
	f_state = F_CHASE
	f_t = G_CHASE_S
	f_host = null
	f_lock = 0.0
	f_flash = 0.0
	f_smoke = G_SMOKE_S
	feel_build_state_frames()

static func feel_state_frames(fr: SpriteFrames, tex: Texture2D) -> void:
	# Единый раскладка-канон носителя (см. feel_v1_bake.gd): ряды 16px-клеток.
	var defs := {
		"possess": [[0, 0], [1, 0], [2, 0], [3, 0]],
		"occupied": [[0, 1], [1, 1]],
		"banish": [[2, 1], [3, 1], [0, 2]],
		"stun": [[1, 2], [2, 2]],
	}
	var speeds := {"possess": 5.556, "occupied": 3.333, "banish": 16.667, "stun": 4.0}
	for an: String in defs:
		fr.add_animation(an)
		fr.set_animation_loop(an, an != "banish")
		fr.set_animation_speed(an, float(speeds[an]))
		for cell: Array in defs[an]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(int(cell[0]) * 16, int(cell[1]) * 16, 16, 16)
			fr.add_frame(an, at, 0.0)

func feel_build_state_frames() -> void:
	if f_ovl != null or not ResourceLoader.exists("res://assets/mobs_wraith_state_v1.png"):
		return
	var fr := SpriteFrames.new()
	fr.remove_animation("default")
	feel_state_frames(fr, load("res://assets/mobs_wraith_state_v1.png"))
	f_ovl = AnimatedSprite2D.new()
	f_ovl.sprite_frames = fr
	add_child(f_ovl)
	f_ovl.z_index = 5
	f_ovl.visible = false

func _feel_hostable(n: Node) -> bool:
	if n == self or not (n is Node2D):
		return false
	if not n.has_method("hurt"):
		return false
	var scres: Script = n.get_script()
	if scres != null and String(scres.resource_path).ends_with("mob_wraith.gd"):
		return false  # призрак хозяином не бывает (и чужим тенеплётом тоже)
	var bossv: Variant = n.get("boss")
	if bossv != null and bool(bossv):
		return false  # боссы не заимуются: лицо вида/боя не ломаем
	var hpv: Variant = n.get("hp")
	if hpv == null or int(hpv) <= 0:
		return false
	var dyv: Variant = n.get("dying")
	if dyv != null and bool(dyv):
		return false
	if n.has_meta("feel_prev"):
		return false  # уже занят чужим призраком
	return true

func _feel_find_host() -> Node2D:
	var best: Node2D = null
	var bd := G_HOST_R
	for n: Node in get_tree().get_nodes_in_group("enemy"):
		if not _feel_hostable(n):
			continue
		var d: float = global_position.distance_to((n as Node2D).global_position)
		if d < bd:
			bd = d
			best = n as Node2D
	return best

func _tick_feel(delta: float) -> void:
	if delta <= 0.0:
		velocity = Vector2.ZERO  # заморозка: автомат ждёт (окно урона сохраняется)
		return
	match f_state:
		F_CHASE:
			_feel_chase(delta)
		F_FLIGHT:
			_feel_flight(delta)
		F_OCCUPIED:
			_feel_occupied(delta)
		F_STUN:
			_feel_stun(delta)
	if f_lock > 0.0:
		f_lock = maxf(0.0, f_lock - delta)  # тикает всегда: замок считается по часам
	if f_flash > 0.0:
		f_flash = maxf(0.0, f_flash - delta)
	if hurt_t <= 0.0 and f_state != F_OCCUPIED:
		if f_state == F_FLIGHT:
			modulate = Color(0.85, 0.7, 1.0, ALPHA_PHASE)
		elif f_flash > 0.0:
			modulate = Color(1.0, 0.93, 0.55, 1.0)  # блик ВХОДА в уязвимость (11:26, п.3)
		else:
			modulate = Color(1, 1, 1, 1.0)

func _feel_chase(delta: float) -> void:
	# видимая медленная погоня героя; гость в радиусе хозяев -> выбор цели.
	collision_layer = 4
	collision_mask = 2 | 4
	if anim != null:
		anim.visible = true
	f_t -= delta
	var player: CharacterBody2D = world.player
	var to_p := player.global_position - global_position
	if _feel_torch() and to_p.length() <= G_TORCH_R:
		# правка вердикта 26.11 11:26 (п.2): огонь в руках — призрак боится
		# пламени: не преследует и не хватает хозяина, стоит открыто у огня.
		# Факел — существующая система с гейтами (Дран/Гриим, подземелье);
		# «зажжённый» = факел в руках (единый носитель, new не плодим), не сгорает.
		f_lock = maxf(f_lock, 0.5)
		velocity = -to_p.normalized() * SPEED_MAT
		_face(-to_p)
		_anim(true)
		move_and_slide()
		return
	# под анти-захватным замком хозяина не ищем (11:26, п.2)
	var h := _feel_find_host() if f_lock <= 0.0 else null
	if h != null:
		_feel_start_flight(h)
		return
	if f_t <= 0.0 and global_position.distance_to(home) > 10.0:
		# «дальше ищет хозяина»: не висит у героя, возвращается к своей нише
		velocity = (home - global_position).normalized() * SPEED_DRIFT
	else:
		velocity = to_p.normalized() * SPEED_MAT if to_p.length() <= LEASH else Vector2.ZERO
	_face(to_p)
	_anim(true)
	move_and_slide()
	_push_from_hero()
	if to_p.length() < HIT_DIST:
		player.take_damage(maxi(1, int(round(2.0 * dmg_mult))), (kill_kind if kill_kind != "" else "wraith"))
	modulate = Color(1, 1, 1, 1.0)

func _feel_start_flight(h: Node2D) -> void:
	f_state = F_FLIGHT
	f_t = G_FLIGHT_S
	f_host = h
	f_host_hp = int(h.get("hp"))
	f_dir = (h.global_position - global_position).normalized()
	collision_layer = 0
	collision_mask = 4  # фаза сквозь стены — единственное такое состояние
	if anim != null:
		anim.visible = false
	if f_ovl != null:
		f_ovl.visible = true
		f_ovl.play("possess")
	GameAudio.sfx("roll")

func _feel_flight(delta: float) -> void:
	f_t -= delta
	if _feel_torch() and world.player != null \
			and global_position.distance_to(world.player.global_position) <= G_TORCH_R:
		# 11:26 (п.2): вселение срывается у огня — приземляется открытой фигурой
		_feel_end_flight_to_chase()
		return
	if f_host == null or not is_instance_valid(f_host) or int(f_host.get("hp")) <= 0 or (f_host.get("dying") != null and bool(f_host.get("dying"))):
		f_host = null
		_feel_end_flight_to_chase()
		return
	velocity = (f_host.global_position - global_position).normalized() * G_FLIGHT_SPEED
	move_and_slide()
	if f_ovl != null and f_ovl.visible:
		f_ovl.position = f_host.global_position - global_position
	if f_t <= 0.0:
		if global_position.distance_to(f_host.global_position) <= 16.0:
			_feel_occupy()
		else:
			_feel_end_flight_to_chase()

func _feel_end_flight_to_chase() -> void:
	if not _tile_walkable(global_position):
		global_position = last_safe
	f_host = null
	f_state = F_CHASE
	f_t = G_CHASE_S
	collision_layer = 4
	collision_mask = 2 | 4
	if anim != null:
		anim.visible = true
	if f_ovl != null:
		f_ovl.visible = false
	dash_cd = 0.8  # сразу не взлетает: герой видит открытую фигуру
	f_lock = maxf(f_lock, 1.0)  # и секунду не хватает хозяина (11:26, п.2)
	_feel_mark_materialize()  # 11:26 (п.3): маркер ВХОДА в уязвимость — блик+звук

func _feel_occupy() -> void:
	f_state = F_OCCUPIED
	f_t = G_HOLD_S
	f_host_hp = int(f_host.get("hp"))
	_feel_apply_buff(true)
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 2 | 4
	if anim != null:
		anim.visible = false
	modulate = Color(1, 1, 1, ALPHA_OCC)
	if f_ovl != null:
		f_ovl.visible = true
		f_ovl.play("occupied")
		f_ovl.position = f_host.global_position - global_position

func _feel_occupied(delta: float) -> void:
	if f_host == null or not is_instance_valid(f_host):
		f_host = null
		_feel_enter_stun(Vector2.ZERO)  # хозяин испарился — призрак вылетает ошмётком
		return
	global_position = f_host.global_position  # «в хозяине»: тело дышит рядом
	velocity = Vector2.ZERO
	# 11:26 (п.1): дымка НЕ статична — мерцание читается как «прячется, не достать»
	modulate = Color(1, 1, 1, ALPHA_OCC + 0.10 * absf(sin(f_t * 9.0)))
	if f_ovl != null:
		f_ovl.position = f_host.global_position - global_position
	var hp_now := int(f_host.get("hp"))
	if (f_host.get("dying") != null and bool(f_host.get("dying"))) or hp_now < f_host_hp:
		feel_banish()  # удар по занятому изгоняет (полл hp — ноль правок в хостах)
		return
	f_host_hp = hp_now
	# 11:26 (п.2): факел выкуривает — у огня призрак принудительно вылетает
	# из хозяина (короткое окно; тот же канал изгнания, что у удара по хозяину)
	if _feel_torch() and world.player != null \
			and world.player.global_position.distance_to(global_position) <= G_TORCH_R:
		f_smoke -= delta
		if f_smoke <= 0.0:
			f_smoke = G_SMOKE_S
			GameState.toast.emit("Факел выкуривает тень!")
			feel_banish()
			return
	else:
		f_smoke = G_SMOKE_S
	f_t -= delta
	if f_t <= 0.0:
		_feel_apply_buff(false)
		# «resurfaces near host» — выныривает у хозяина, без фазы
		var off := Vector2(0, -12)
		if not _tile_walkable(f_host.global_position + off):
			off = Vector2(12, 0)
		global_position = f_host.global_position + off
		f_host = null
		f_state = F_CHASE
		f_t = G_CHASE_S
		collision_layer = 4
		collision_mask = 2 | 4
		f_lock = G_REPOS_S  # 11:26 (п.2): вынырнул — и стоит открыто, не хватает
		_feel_mark_materialize()  # 11:26 (п.3): вынырнул = уязвим — блик+звук
		if anim != null:
			anim.visible = true
		if f_ovl != null:
			f_ovl.visible = false
		dash_cd = 0.8

func feel_banish() -> void:
	if f_state != F_OCCUPIED or f_host == null or not is_instance_valid(f_host):
		return
	var hpos: Vector2 = f_host.global_position
	_feel_apply_buff(false)
	_feel_pop_at(hpos, "banish")  # 3 кадра x 60 мс — вспышка на хозяине
	Juice.shake(1.0, 0.10)              # строка banish таблицы тряски (лист §3)
	GameAudio.sfx("roll")
	var away := (global_position - hpos)
	_feel_enter_stun(away.normalized() * 70.0 if away != Vector2.ZERO else Vector2(0, -70))

func _feel_enter_stun(kick: Vector2) -> void:
	f_state = F_STUN
	f_t = G_STUN_S
	# 11:26 (п.2): анти-захватный замок переживает оглушение — игрок получает
	# честное окно: stun 2.5 с + погоня без захвата ~2.5 с
	f_lock = G_STUN_S + G_REPOS_S
	f_host = null
	velocity = kick
	collision_layer = 4
	collision_mask = 2 | 4
	if anim != null:
		anim.visible = true
	if f_ovl != null:
		f_ovl.visible = true
		f_ovl.play("stun")
		f_ovl.position = Vector2.ZERO
	_feel_mark_materialize()  # 11:26 (п.3): изгнание = вход в честное окно — блик+звук

func _feel_stun(delta: float) -> void:
	f_t -= delta
	velocity = velocity.move_toward(Vector2.ZERO, 140.0 * delta)
	_anim(false)
	move_and_slide()
	if f_ovl != null:
		f_ovl.position = Vector2.ZERO
	if f_t <= 0.0:
		if f_ovl != null:
			f_ovl.visible = false
		f_state = F_CHASE
		f_t = G_CHASE_S
		_feel_mark_materialize()  # 11:26 (п.3): из оглушения — тоже вход в окно

func _feel_torch() -> bool:
	# правка вердикта 26.11 11:26 (п.2): дополнительный способ достать призрака —
	# факел в руках героя. Факел — существующая система с гейтами (GameState.torches:
	# покупка у Драна/крафт у Гриима, подземельный кредит); нового состояния
	# «горение/рука» не заводим: факел при себе = огонь под рукой. Не сгорает.
	return world != null and world.player != null and int(GameState.torches) > 0

func _feel_mark_materialize() -> void:
	# пункт 3 той же правки: маркер ВХОДА в уязвимость — золотой блик FLASH_MAT
	# (modulate, читается в _tick_feel) + существующий звук "spell" (pitch 1.3).
	# Новых ассетов/систем нет.
	f_flash = FLASH_MAT
	GameAudio.sfx("spell", 0.7, 1.3)

func _feel_pop_at(pos: Vector2, an: String) -> void:
	# одноразовый кадр-вспышка в мировой точке (изгнание вспыхивает на хозяине)
	if f_ovl == null:
		return
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = f_ovl.sprite_frames
	sp.z_index = 6
	get_parent().add_child(sp)
	sp.global_position = pos
	sp.play(an)
	# самоуборка по последнему кадру: без SceneTreeTimer — он не висит над
	# уничтоженным миром (урок «Lambda capture was freed» из qa_wr0)
	sp.animation_finished.connect(func() -> void: sp.queue_free())

func _feel_apply_buff(on: bool) -> void:
	if f_host == null or not is_instance_valid(f_host):
		return
	if on:
		var prev := {}
		for v: String in ["speed", "dmg", "dmg_mult", "feel_spd_mult"]:
			var cur: Variant = f_host.get(v)
			if cur != null:
				prev[v] = cur
				if v == "dmg":
					f_host.set(v, int(round(int(cur) * G_BUFF_DMG)))
				elif v == "speed" or v == "feel_spd_mult":
					f_host.set(v, float(cur) * G_BUFF_SPD)
				else:
					f_host.set(v, float(cur) * G_BUFF_DMG)
		f_host.set_meta("feel_prev", prev)
	else:
		if f_host.has_meta("feel_prev"):
			var prev2: Dictionary = f_host.get_meta("feel_prev")
			for v: String in prev2:
				f_host.set(v, prev2[v])
			f_host.remove_meta("feel_prev")