extends Node2D

## QA-харнесс t64 «камера следует за героем» (песочница, в дифф игры НЕ входит).
## Прогон: godot --headless res://qa_cam.tscn
##
## Пинит контракт рига (pixel-rpg/scripts/camera_rig.gd + world.gd):
##   C01..C07 устройство: камера — ребёнок героя, текущая, зум 1, сглаждение
##        включено, скорость = FOLLOW_LERP*60 (0.20 кадра => 12.0), limit_smoothed,
##        пиксельный снап трансформ (субпиксельный догон не должен shimmer-ить);
##   C08..C11 лимиты = пиксельные границы каждой зоны, взяты из ФАКТИЧЕСКИХ
##        размеров карт (не хардкод), плюс возврат в деревню;
##   C12..C17 метрика «100 % карты, ноль пустоты»: все 8 крайних видов деревни
##        целиком внутри карты, их объединение = карта целиком, герой в центре
##        экрана в середине карты, на краю мира вид упирается ровно в границу;
##   C18..C23 «запределье» (Polygon2D ZoneVoid): в дереве, под миром, не pickable,
##        цвет = самый тёмный тон своего материала зоны, и его прямоугольник
##        покрывает вид во всех 9 позах малой зоны (пещера 480×352 < 640×360) —
##        это геометрический эквивалент скана кадра на clear/pure black;
##   C24..C30 снап: смена зоны, арка (g18b), возрождение, крупный прыжок без
##        явного snap() (страховка рига) и — контролей — обычная ходьба ДОГОНЯЕТ
##        (сглаживание настоящее), хвост гаснет;
##   C31..C40 регресс контура, который живёт на world-координатах: прицел
##        (мировая точка под центром экрана), клик-движение (цель = мировая точка,
##        не сдвинутая камерой), миникарта (радар экранно-закреплён, маркер = тайл
##        героя), PointLight2D факелов, тряска Juice (пишет cam.offset, а не канвас),
##        и смоук 6 смен зон.
##
## Пиксельный скан кадра (8 крайних поз, pure black/clear) живёт в прогоне
## scratch_cm/t64: headless-рендер не рисует, поэтому здесь — эквивалент по
## геометрии, а по кадрам меряется оконным прогоном пробы.

const Main := "res://scenes/main.tscn"
const SAVE_PATH := "user://save_morkheim.json"
const RIG := preload("res://scripts/camera_rig.gd")
const PAL := preload("res://scripts/pixel_palette.gd")

var pass_n := 0
var fail_n := 0
var world: Node2D
var cam: Camera2D

func chk(cond: bool, name: String) -> void:
	if cond:
		pass_n += 1
		print("qa_cam ok: ", name)
	else:
		fail_n += 1
		print("qa_cam FAIL: ", name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _frames2(n: int) -> void:
	# и физика, и idle: сглаживание Camera2D догоняет в idle-кадре
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.start_fresh_game()   # чистая meta/сейв-база (паттерн qa_dr): иначе чужой user:// поднимает модалки
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	GameState.seen_cave_intro = true
	GameState.in_cave = false
	GameState.run_seed = 42
	# headless-окно по умолчанию не каноническое (64×64 => вьюпорт 640×640), а
	# геометрия клампа камеры зависит от размера вьюпорта: пиним дизайн 640×360 —
	# то самое «одно окно», в котором меряется и оконный прогон кадров.
	get_window().size = Vector2i(640, 360)
	await _frames2(3)
	world = await _spawn_world()
	cam = world.cam
	await _phase_rig()
	await _phase_limits()
	await _phase_metric()
	await _phase_void()
	await _phase_snap()
	await _phase_regression()
	await _phase_smoke()
	print("RESULT: %d pass / %d fail" % [pass_n, fail_n])
	get_tree().quit(0 if fail_n == 0 else 1)

func _spawn_world() -> Node2D:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var w: Node2D = load(Main).instantiate()
	add_child(w)
	await _frames2(3)
	return w

# --- помощники меры -------------------------------------------------------------

## Размер вьюпорта в базовых координатах (стретч canvas_items: 640×360 при каноне).
func _view() -> Vector2:
	return world.get_viewport_rect().size

## Центр вида, каким он обязан быть при данных лимитах: hero, клампнутый в
## [limit+полувьюпорта, limit-полувьюпорта]; если мир меньше вьюпорта по оси —
## центр лимит-прямоугольника (Godot именно центрирует, клампить нечего).
func _ideal_center(p: Vector2) -> Vector2:
	var hw: Vector2 = _view() * 0.5 / cam.zoom
	var lo := Vector2(float(cam.limit_left), float(cam.limit_top)) + hw
	var hi := Vector2(float(cam.limit_right), float(cam.limit_bottom)) - hw
	var rc := (Vector2(float(cam.limit_left), float(cam.limit_top))
			+ Vector2(float(cam.limit_right), float(cam.limit_bottom))) * 0.5
	if hi.x < lo.x:
		lo.x = rc.x
		hi.x = rc.x
	if hi.y < lo.y:
		lo.y = rc.y
		hi.y = rc.y
	return Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))

## Чем камера реально «смотрит» (центр экрана после клампа и сглаживания).
func _center() -> Vector2:
	return cam.get_screen_center_position()

## Позиция героя на экране (базовые координаты вьюпорта).
func _hero_screen() -> Vector2:
	return world.get_viewport().get_canvas_transform() * (world.player as Node2D).global_position

func _view_rect() -> Rect2:
	var hw: Vector2 = _view() * 0.5
	return Rect2(_center() - hw, _view())

func _map_rect(area: String) -> Rect2:
	if area == "cave":
		var dz = world.dungeon_zone
		return Rect2(world.CAVE_OFFSET, Vector2(dz.map_w, dz.map_h) * 16.0)
	if area == "ashen":
		var az = world.ashen_grid
		return Rect2(world.ASHEN_OFFSET, Vector2(az.map_w, az.map_h) * 16.0)
	return Rect2(Vector2.ZERO, Vector2(world.map_w, world.map_h) * 16.0)

## 8 крайних + центральная поза героя внутри зоны (отступ 18 px от края карты —
## чтобы герой оставался проходимым и не залезал в стену).
func _poses(area: String) -> Array:
	var r := _map_rect(area)
	var m := 18.0
	var cx: float = r.position.x + r.size.x * 0.5
	var cy: float = r.position.y + r.size.y * 0.5
	return [
		r.position + Vector2(m, m),
		Vector2(r.end.x - m, r.position.y + m),
		Vector2(r.position.x + m, r.end.y - m),
		r.end - Vector2(m, m),
		Vector2(cx, r.position.y + m),
		Vector2(cx, r.end.y - m),
		Vector2(r.position.x + m, cy),
		Vector2(r.end.x - m, cy),
		Vector2(cx, cy),
	]

func _place(p: Vector2) -> void:
	world.player.global_position = p
	cam.call("snap")

# ------------------------------------------------------------------ устройство
func _phase_rig() -> void:
	chk(cam != null and cam.is_current(), "C01 камера есть и текущая")
	chk(cam.get_parent() == world.player, "C02 камера — ребёнок героя (следует за ним)")
	chk(cam.has_method("snap"), "C02b на камере висит риг camera_rig.gd, а не голый Camera2D")
	chk(cam.zoom == Vector2.ONE, "C03 зум 1 (инвариант SCALE_CANON/OPEN_WORLD)")
	chk(bool(cam.position_smoothing_enabled), "C04 сглаживание следования включено")
	var lerp: float = float(RIG.FOLLOW_LERP)
	chk(lerp >= 0.15 and lerp <= 0.25, "C05 доля кадра %.2f в заказанных 0.15..0.25" % lerp)
	chk(absf(float(cam.position_smoothing_speed) - lerp * 60.0) < 0.001,
		"C06 скорость = доля*60 = %.1f (Godot считает delta*speed)" % cam.position_smoothing_speed)
	chk(bool(cam.limit_smoothed), "C07 limit_smoothed: кламп по сглаженной позиции (иначе догоняющий кадр за мир)")
	chk(bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel")),
		"C07b пиксельный снап трансформ включён (субпиксельный догон без shimmer)")
	chk(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 640
			and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 360,
		"C07c окно 640×360 — один экран не меняется")
	chk(_view() == Vector2(640, 360), "C07d фактический вьюпорт стенда = дизайн 640×360 (%s) — иначе геометрия клампа мерялась бы не в том окне" % str(_view()))
	print("qa_cam note: runtime viewport=%s, зона-карта деревни=%s" % [str(_view()), str(_map_rect("village").size)])

# ------------------------------------------------------------------ лимиты зон
func _phase_limits() -> void:
	var rv := _map_rect("village")
	chk(Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left,
			cam.limit_bottom - cam.limit_top) == rv,
		"C08 деревня: лимиты = пиксельные границы карты %s" % str(rv))
	world.apply_area("cave", true)
	await _frames2(2)
	var rc := _map_rect("cave")
	chk(Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left,
			cam.limit_bottom - cam.limit_top) == rc,
		"C09 пещера: лимиты = границы зал %s (меньше экрана по обеим осям)" % str(rc.size))
	world.apply_area("ashen", true)
	await _frames2(2)
	var ra := _map_rect("ashen")
	chk(Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left,
			cam.limit_bottom - cam.limit_top) == ra,
		"C10 Пепелище: лимиты = границы выжженной карты %s" % str(ra.size))
	world.apply_area("village", true)
	await _frames2(2)
	chk(Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left,
			cam.limit_bottom - cam.limit_top) == rv, "C11 обратно в деревню: лимиты вернулись")

# ------------------------------------------------- метрика: 100 % карты, ноль пустоты
func _phase_metric() -> void:
	var r := _map_rect("village")
	var poses := _poses("village")
	var inside := true
	var union := Rect2()
	for p in poses:
		_place(p as Vector2)
		# 6 кадров: физика выталкивает героя из стены у самого края карты, а
		# сглаженная камера догоняет вытеснение; мерим в установившемся состоянии
		await _frames2(6)
		var vr := _view_rect()
		if not r.encloses(vr):
			inside = false
		union = vr if union.size == Vector2.ZERO else union.merge(vr)
	chk(inside, "C12 деревня: все 8 крайних видов целиком ВНУТРИ карты 768×480 => ноль пустых пикселей по кромке")
	chk(union.position.distance_to(r.position) < 0.501 and union.end.distance_to(r.end) < 0.501,
		"C13 объединение крайних видов = карта целиком (%s vs %s) => скролл показывает 100 %% карты"
			% [str(union), str(r)])
	_place(r.position + r.size * 0.5)
	await _frames2(6)
	chk(_hero_screen().distance_to(_view() * 0.5) <= 1.0,
		"C14 в середине карты герой в центре экрана (отклонение %.2f px)" % _hero_screen().distance_to(_view() * 0.5))
	_place(Vector2(r.position.x + 18.0, r.position.y + r.size.y * 0.5))
	await _frames2(6)
	chk(absf(_view_rect().position.x) < 0.501 and absf(_center().x - (r.position.x + _view().x * 0.5)) < 0.501,
		"C15 у левого края мира вид упирается ровно в границу (0 px запаса, camera clamp работает)")
	_place(Vector2(r.end.x - 18.0, r.position.y + r.size.y * 0.5))
	await _frames2(6)
	chk(absf(_view_rect().end.x - r.end.x) < 0.501, "C16 у правого края — то же самое, правый край впритык")
	var ic := _ideal_center((world.player as Node2D).global_position)
	chk(_center().distance_to(ic) <= 1.0,
		"C17 фактический центр вида = эталонный для этих лимитов (центр=%s эталон=%s lag=%.2f hero=%s cam.pos=%s off=%s)"
			% [str(_center()), str(ic), _center().distance_to(ic),
				str((world.player as Node2D).global_position), str(cam.position), str(cam.offset)])

# ----------------------------------------------------------- «запределье» зоны
func _phase_void() -> void:
	var poly = world.get("_void_poly")
	chk(poly != null and is_instance_valid(poly) and poly.is_inside_tree(),
		"C18 ZoneVoid: полигон пустоты собран и в дереве")
	chk(poly.get_parent() == world, "C19 ZoneVoid — ребёнок мира (подпадает под CanvasModulate цветокор, тон совпадает с зоной)")
	chk(int(poly.z_index) < 0, "C20 ZoneVoid рисуется под тайлмапами зоны (z_index=%d)" % int(poly.z_index))
	chk(not (poly is Control) and not (poly is CollisionObject2D),
		"C21 ZoneVoid — не Control и не CollisionObject2D: глотать клик-прицел/ПКМ-движение нечем (практику пинит C33)")
	for z in ["village", "cave", "ashen"]:
		world.apply_area(z, true)
		await _frames2(2)
		var spec: Array = world.VOID_RAMP.get(z, world.VOID_RAMP["village"])
		var want: Color = PAL.c(String(spec[0]), int(spec[1]))
		chk((poly.color as Color) == want,
			"C22 %s: цвет пустоты = канон-тон %s[%d] %s (никаких внепалитрных цветов)"
				% [z, String(spec[0]), int(spec[1]), str(wide_hex(want))])
		var covered := true
		var prect := _poly_rect(poly as Polygon2D)
		chk((poly as Polygon2D).polygon.size() == 4, "C22b %s: у пустоты ровно 4 вершины (четырехугольник, не мусор)" % z)
		for p in _poses(z as String):
			_place(p as Vector2)
			await _frames2(6)   # та же усадка: вытеснение из стены + догон камеры
			if not prect.encloses(_view_rect()):
				covered = false
		var sz := _map_rect(z as String).size
		chk(covered, "C23 %s (карта %s): прямоугольник пустоты покрывает вид во всех 9 позах => clear-полоса невозможна"
			% [z, str(sz)])
	world.apply_area("village", true)
	await _frames2(2)

## AABB полигона: в Godot 4.7 у Polygon2D нет get_rect() (проверено на факте —
## «Nonexistent function 'get_rect'»), считаем сами.
func _poly_rect(p: Polygon2D) -> Rect2:
	if p == null or p.polygon.is_empty():
		return Rect2()
	var r := Rect2(p.polygon[0], Vector2.ZERO)
	for i in range(1, p.polygon.size()):
		r = r.expand(p.polygon[i])
	return r

## 0xRRGGBB для лога (Color в консоль нечитабелен в cp866).
func wide_hex(c: Color) -> String:
	return "%02X%02X%02X" % [int(c.r8), int(c.g8), int(c.b8)]

# ------------------------------------------------------------------ снап-контракт
func _phase_snap() -> void:
	var hero: Node2D = world.player
	# эталонная точка вдали от лимитов: середина карты деревни (свободный ход 64×60)
	var mid: Vector2 = _map_rect("village").position + _map_rect("village").size * 0.5
	world.apply_area("village", true)
	await _frames2(2)
	# C24: смена зоны = телепорт на 4800 px: за один кадр камера обязана сесть на героя
	world.apply_area("cave", true)
	await _frames2(1)
	chk(_center().distance_to(_ideal_center(hero.global_position)) <= 1.0,
		"C24 смена зоны в деревня->пещера: лаг %.2f px за 1 кадр (старый край карты не показан)"
			% _center().distance_to(_ideal_center(hero.global_position)))
	world.apply_area("village", true)
	await _frames2(2)
	# C25/C26: арка (g18b «вынесло к входу») — реальный путь резюме, не имитация
	GameState.in_cave = true
	world.village_return_pos = world.tile_to_world(world.CAVE_ENTRANCE_TILE)
	world._place_resumed_player()
	await _frames2(1)
	var rc25 := _map_rect("cave")
	chk(rc25.grow(8.0).has_point(hero.global_position),
		"C25 resume в пещере: герой внутри её карты, %s" % str(hero.global_position))
	chk(_center().distance_to(_ideal_center(hero.global_position)) <= 1.0,
		"C26 resume у арки: камера уже на герое (g18b: старый край не показываем), лаг %.2f px"
			% _center().distance_to(_ideal_center(hero.global_position)))
	GameState.in_cave = false
	# C27: возрождение
	world.respawn_player()
	await _frames2(1)
	chk(_center().distance_to(_ideal_center(hero.global_position)) <= 1.0,
		"C27 возрождение = телепорт: лаг %.2f px (догонять нечего)"
			% _center().distance_to(_ideal_center(hero.global_position)))
	world.apply_area("village", true)
	await _frames2(2)
	# C28: контролей — обычная ходьба ДОГОНЯЕТ (сглаживание настоящее), а не телепорт
	_place(mid)
	await _frames2(3)
	var before: Vector2 = hero.global_position
	hero.global_position = before + Vector2(2.0, 0.0)   # шаг ~2 px, порог телепорта не берёт
	await _frames2(1)
	var lag: float = _center().distance_to(_ideal_center(hero.global_position))
	chk(lag > 0.4 and lag < 2.0,
		"C28 шаг 2 px: камера догоняет плавно (лаг %.2f px > 0 и < шага) — это не жёсткая привязка" % lag)
	var frames := 0
	while frames < 60 and _center().distance_to(_ideal_center(hero.global_position)) > 0.5:
		await _frames2(1)
		frames += 1
	chk(_center().distance_to(_ideal_center(hero.global_position)) <= 0.5,
		"C29 хвост сглаживания гаснет за %d кадров (< 0.5 px)" % frames)
	# C30: страховка рига — крупный прыжок без явного snap(). Страховка живёт в
	# _physics_process рига, поэтому меряем после двух кадров (физика+idle): на
	# первом физическом тике она и обязана сработать; явный snap() (C24..C27)
	# работает в том же кадре, без ожидания тика.
	_place(mid)
	await _frames2(2)
	hero.global_position = mid + Vector2(40.0, 0.0)     # без snap: только TELEPORT_PX-страховка
	await _frames2(2)
	chk(_center().distance_to(_ideal_center(hero.global_position)) <= 1.0,
		"C30 прыжок 40 px без snap(): страховка рига снапает за тик (лаг %.2f px)"
			% _center().distance_to(_ideal_center(hero.global_position)))

# ------------------------------------------------------------- регресс контура
func _phase_regression() -> void:
	var hero: Node2D = world.player
	var r := _map_rect("village")
	_place(r.position + r.size * 0.5)
	await _frames2(2)
	# прицел: мировая точка под центром экрана = герой (get_global_mouse_position тот же путь)
	var vp: Viewport = world.get_viewport()
	var world_at_center: Vector2 = vp.get_canvas_transform().affine_inverse() * (_view() * 0.5)
	chk(world_at_center.distance_to(hero.global_position) <= 1.0,
		"C31 прицел: мировая точка под центром экрана = герой (%.2f px) — world-coords не съехали"
			% world_at_center.distance_to(hero.global_position))
	# C32: мировой указатель в headless — заглушка DisplayServer (Input.get_mouse_position
	# не обновляется push_input), поэтому пиним не сам курсор, а то, от чего он зависит:
	# канвас-матрица честно следует за камерой на любом зуме — тот же путь, что у
	# get_global_mouse_position() у прицела (player.gd:214/228) и у ПКМ-движения.
	var z0: Vector2 = cam.zoom
	for z in [Vector2(2, 2), Vector2(0.5, 0.5)]:
		cam.zoom = z
		cam.call("snap")
		await _frames2(2)
		var wpt: Vector2 = world.get_viewport().get_canvas_transform().affine_inverse() * (_view() * 0.5)
		chk(wpt.distance_to(hero.global_position) <= 1.0,
			"C32 зум %s: центр экрана по-прежнему смотрит на героя (%.2f px) — world<->screen не съезжает"
				% [str(z), wpt.distance_to(hero.global_position)])
	cam.zoom = z0
	cam.call("snap")
	await _frames2(2)
	chk(cam.zoom == Vector2.ONE, "C32b зум мира возвращён в 1")
	# клик-движение: цель = мировая точка, а не «экранная, сдвинутая камерой».
	# Берём ПРОХОДИМУЮ клетку рядом с героем (тот же критерий, что у самого ClickMove),
	# иначе тест зависел бы от того, попал ли офсет в дерево.
	var cm = ClickMove.I
	var was_on: bool = ClickMove.is_on()
	ClickMove.set_on(true)
	var base0: Vector2 = world.CAVE_OFFSET if GameState.in_cave else Vector2.ZERO
	var goal := Vector2.INF
	for d in [Vector2(48, 0), Vector2(-48, 0), Vector2(0, 48), Vector2(0, -48),
			Vector2(32, 32), Vector2(-32, 32), Vector2(32, -32), Vector2(-32, -32)]:
		var cand: Vector2 = hero.global_position + d
		var tile := Vector2i(int(floor((cand.x - base0.x) / 16.0)), int(floor((cand.y - base0.y) / 16.0)))
		if bool(cm.call("_tile_walkable", tile)):
			goal = base0 + world.tile_to_world(tile)
			break
	var ok: bool = goal != Vector2.INF and bool(cm.call("order_to", goal))
	var got_goal: Vector2 = cm.get("_goal")
	chk(ok and got_goal.distance_to(goal) <= 0.501,
		"C33 клик-движение: цель приказа = world-точка под курсором (%s vs %s)" % [str(got_goal), str(goal)])
	hero.cancel_orders()
	cm.call("cancel")
	# миникарта: радар экранно-закреплён, маркер = тайл героя (не позиция камеры)
	var mm = Minimap.I
	var rect0: Rect2 = mm.get("_radar").get_global_rect()
	_place(r.position + Vector2(30.0, r.size.y * 0.5))
	await _frames2(2)
	chk(rect0 == mm.get("_radar").get_global_rect(),
		"C34 миникарта: радар не двигается вместе с камерой (HUD-слой, экранная привязка)")
	var base: Vector2 = mm.call("_zone_base")
	var t_hero: Vector2i = mm.call("_tile_of", hero.global_position, base, 16.0)
	chk(t_hero == Vector2i(int(floor((hero.global_position.x - base.x) / 16.0)),
			int(floor((hero.global_position.y - base.y) / 16.0))),
		"C35 миникарта: маркер считается из тайла героя (%s), а не из центра камеры" % str(t_hero))
	mm.get("_radar").queue_redraw()   # штатный перерисов-кадр (маркер рисуется в _Radar._draw)
	await _frames2(2)
	# PointLight2D (факелы/алтарь/костёр): живёт в мировых координатах своей зоны,
	# риг его не «теряет». Берём ВСЕ источники и идём в зону первого — иначе пин
	# зависел бы от того, в какой зоне зона-строитель создал свет первым.
	var lights := _collect_lights(world)
	chk(not lights.is_empty(), "C36 в мире есть Light2D (факелы/алтарь/костёр): %d шт" % lights.size())
	if not lights.is_empty():
		var light: Node2D = lights[0]
		var lp: Vector2 = light.global_position
		var lz := "village"
		if lp.y >= world.ASHEN_OFFSET.y:
			lz = "ashen"
		elif lp.y >= world.CAVE_OFFSET.y:
			lz = "cave"
		world.apply_area(lz, true)
		await _frames2(2)
		chk(_map_rect(lz).has_point(lp),
			"C36b Light2D %s лежит в своей зоне %s (%s) — риг свет не уводит"
				% [str(lp), lz, str(_map_rect(lz).size)])
		hero.global_position = lp
		cam.call("snap")
		await _frames2(2)
		var ls: Vector2 = world.get_viewport().get_canvas_transform() * lp
		chk(Rect2(Vector2.ZERO, _view()).grow(2.0).has_point(ls),
			"C37 свет рядом с героем в кадре (%s при экране %s)" % [str(ls), str(_view())])
		world.apply_area("village", true)
		await _frames2(2)
	# тряска: пишется в cam.offset, мир (и герой) на месте, по окончании — ноль
	var hp: Vector2 = hero.global_position
	Juice.shake(2.0, 0.2)
	await _frames2(1)
	var off: Vector2 = cam.offset
	chk(off != Vector2.ZERO, "C38 тряска пишет смещение в cam.offset (%s)" % str(off))
	chk(hero.global_position.distance_to(hp) < 0.001,
		"C39 тряска не двигает мир/героя и не сдвигает канвас — только камеру (перевод на камеру не потребовался)")
	var tt := 0
	while tt < 40 and cam.offset != Vector2.ZERO:
		await get_tree().create_timer(0.05).timeout   # тряска живёт по времени, не по кадрам
		tt += 1
	await _frames2(2)
	chk(cam.offset == Vector2.ZERO, "C40 тряска завершилась, offset обнулён за %.2f с (не залипла)" % (tt * 0.05))
	ClickMove.set_on(was_on)

func _collect_lights(n: Node, acc: Array = []) -> Array:
	for c in n.get_children():
		if c is Light2D:
			acc.append(c)
		_collect_lights(c, acc)
	return acc

# ------------------------------------------------------------------ смоук
func _phase_smoke() -> void:
	var hero: Node2D = world.player
	var flips := 0
	for i in 6:
		var z := "village"
		if i % 3 == 1:
			z = "cave"
		elif i % 3 == 2:
			z = "ashen"
		world.apply_area(z, true)
		await _frames2(2)
		var want := _map_rect(z)
		var got := Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left,
				cam.limit_bottom - cam.limit_top)
		if got == want and _center().distance_to(_ideal_center(hero.global_position)) <= 1.0:
			flips += 1
	chk(flips == 6, "C41 смоук: 6 смен зон — лимиты и посадка камеры каждый раз верные (%d/6)" % flips)
	chk(is_instance_valid(world) and is_instance_valid(hero), "C42 смоук: мир и герой живы после 6 смен зон")
