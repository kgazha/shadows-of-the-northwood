extends Node2D
## QA-харнесс миникарты (песочница sand_z2mm, в дифф НЕ входит).
## Прогон: godot --headless res://qa_mm.tscn
## Покрывает: деревня/пещера без регрессов (формат подписи, размеры, POI),
## Пепелище: гейт по y, своя сетка ashen_grid, подписи «a|», блипы портал/сундук,
## Ведьма живым босс-циклом (смерть -> блип гаснет), взятие сундука, герой в
## локальных координатах, сборка без ashen_grid без падения, M-тумблер и
## персист user://minimap_cfg.json, пересборка мира (мёртвая ведьма/взятый
## сундук не возрождаются на радаре).
## ВИДИМОСТЬ (юзер-баг «не отображается миникарта» при зелёном стенде): данные
## зелёные не значат, что контрол рисуется — проверяем _radar.visible,
## is_visible_in_tree() и фактическое срабатывание _draw радара в деревне и в
## обеих ПРОЦЕДУРНЫХ зонах (cave/ashen), а также в фазе M-тумблера.
##
## t49 (второй юзер-баг того же класса: «мир виден, радар пустой», окно): стенд
## подтверждал данные и вызов _draw, но НЕ подтверждал, что тайловую подложку
## видно. В окне её целиком перекрывала непрозрачная сердцевина 9-slice рамки:
## Panel — ребёнок радара, а дети CanvasItem рисуются ПОСЛЕ его _draw(). Фаза
## _phase_backing закрывает дыру: непустой ИСТОЧНИК подложки (залит каждый тайл,
## пол/стены различимы) в трёх зонах, блипы внутри поля + регресс POI, и аудит
## детей радара — никто не имеет права рисовать непрозрачным ПОВЕРХ paint().

const Main := "res://scenes/main.tscn"
const SAVE_PATH := "user://save_morkheim.json"
const CFG_PATH := "user://minimap_cfg.json"

var pass_n := 0
var fail_n := 0
var world: Node2D
var mm: Node
var radar_draws := 0   # счётчик сработавших _draw у контрола радара

func chk(cond: bool, name: String) -> void:
	if cond:
		pass_n += 1
		print("qa_mm ok: ", name)
	else:
		fail_n += 1
		print("qa_mm FAIL: ", name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _repoll() -> void:
	mm._poll_t = 0.0
	# 6 кадров: поллинг живёт в idle (_process), а ждём мы physics — запас
	await _frames(6)

## paint() легален только внутри _draw — зондим через Control-пробу.
func _paint_ok(tag: String) -> void:
	var probe := Control.new()
	probe.set_process(false)
	add_child(probe)
	var done := [false]
	probe.draw.connect(func() -> void:
		mm.paint(probe)
		done[0] = true)
	probe.queue_redraw()
	for i in 10:
		await get_tree().physics_frame
		if done[0]:
			break
	chk(bool(done[0]), "paint() %s: _draw отработал без ошибок" % tag)
	probe.queue_free()

func _poi_of(c: Color) -> Array:
	var out: Array = []
	for p in mm._pois:
		if p["c"] == c:
			out.append(p)
	return out

## Счётчик реальной отрисовки: signal draw у контрола радара. В headless _draw
## тоже происходит (тот же механизм, что у пробы _paint_ok) — но ТОЛЬКО пока
## контрол видим в дереве, поэтому скрытый _radar даёт 0.
func _hook_draws() -> void:
	radar_draws = 0
	if mm != null and mm._radar != null:
		mm._radar.draw.connect(func() -> void: radar_draws += 1)

## Видимость радара «по-настоящему»: флаг, дерево, и что _draw реально firing.
func _vis_ok(tag: String) -> void:
	chk(bool(mm._radar.visible), "%s: _radar.visible == true" % tag)
	chk(bool(mm._radar.is_visible_in_tree()), "%s: радар в видимом дереве" % tag)
	var d0 := radar_draws
	await _frames(4)
	chk(radar_draws > d0, "%s: _draw радара срабатывает (%d -> %d)" % [tag, d0, radar_draws])

func _ready() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if FileAccess.file_exists(CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	GameState.seen_cave_intro = true
	GameState.elder_quest = 0
	await _frames(2)
	world = load(Main).instantiate()
	add_child(world)
	await _frames(4)
	mm = Minimap.I
	chk(mm != null, "Minimap.I назначен")
	_hook_draws()
	await _phase_village()
	await _phase_cave()
	await _phase_ashen()
	await _phase_events()
	await _phase_nozone()
	await _phase_toggle()
	await _phase_rebuild()
	await _phase_backing()
	var total: int = pass_n + fail_n
	print("QA_MM %d/%d" % [pass_n, total])
	get_tree().quit(0 if fail_n == 0 else 1)

# ---------------------------------------------------------------- деревня
func _phase_village() -> void:
	await _repoll()
	chk(mm._zone == "village", "зона village")
	chk(mm._sig == "v|" + str(world.map_rows), "подпись v|+rows (формат прежний)")
	chk(int(mm._grid_w) == int(world.map_w) and int(mm._grid_h) == int(world.map_h), "сетка 48x30")
	chk(bool(mm._zone_seen), "сетка собрана")
	var ports := _poi_of(Minimap.C_PORTAL)
	var has_cave := false
	var has_ashen := false
	for p in ports:
		if p["t"] == Vector2i(world.CAVE_ENTRANCE_TILE):
			has_cave = true
		if p["t"] == Vector2i(45, 20):
			has_ashen = true
	chk(has_cave, "деревня: блип входа в пещеру")
	chk(has_ashen, "деревня: блип аршины Пепелища (45,20)")
	chk(_poi_of(Minimap.C_FIRE).size() > 0, "деревня: костры на месте")
	chk(_poi_of(Minimap.C_NPC).size() > 0, "деревня: NPC на месте")
	var pt: Vector2i = mm._tile_of(world.player.global_position, Vector2.ZERO, 16.0)
	chk(pt.x >= 0 and pt.y >= 0 and pt.x < mm._grid_w and pt.y < mm._grid_h, "герой в поле сетки")
	await _vis_ok("деревня")

# ---------------------------------------------------------------- пещера
func _phase_cave() -> void:
	world.apply_area("cave", true)
	await _repoll()
	chk(bool(GameState.in_cave), "in_cave выставлен")
	chk(mm._zone == "cave", "зона cave")
	chk(mm._sig == "c|" + str(world.map_rows), "подпись c|+rows (экс-квирк сохранён)")
	var dz = world.dungeon_zone
	chk(int(mm._grid_w) == int(dz.map_w) and int(mm._grid_h) == int(dz.map_h), "сетка пещеры из dungeon_zone")
	chk(_poi_of(Minimap.C_PORTAL).size() >= 1, "пещера: лестница-блип")
	await _vis_ok("пещера proc")
	world.apply_area("village", true)
	await _repoll()
	chk(mm._zone == "village" and mm._sig.begins_with("v|"), "обратно: village")

# ---------------------------------------------------------------- Пепелище
func _phase_ashen() -> void:
	world.apply_area("ashen", true)
	await _frames(2)
	chk(world.player.global_position.y > world.ASHEN_OFFSET.y, "гейт: y героя > ASHEN_OFFSET.y")
	await _repoll()
	var az = world.ashen_grid
	chk(mm._zone == "ashen", "зона ashen")
	chk(mm._sig == "a|" + str(az.map_rows), "третья подпись a|+ashen rows")
	chk(int(mm._grid_w) == int(az.map_w) and int(mm._grid_h) == int(az.map_h), "сетка 40x30 из ashen_grid")
	chk(bool(mm._zone_seen), "ashen-сетка собрана")
	# портал: тайл = приведение мировых координат к локальным
	var ptl: Vector2i = mm._tile_of(az.portal_node.global_position, world.ASHEN_OFFSET, 16.0)
	var ports := _poi_of(Minimap.C_PORTAL)
	chk(ports.size() == 1 and ports[0]["t"] == ptl, "блип портала на своём тайле")
	var chests := _poi_of(Minimap.C_CHEST)
	chk(chests.size() == 1, "блип сундука есть")
	# герой: локальные координаты внутри 40x30 (доказательство вычета ASHEN_OFFSET)
	var pt: Vector2i = mm._tile_of(world.player.global_position, mm._zone_base(), 16.0)
	chk(mm._zone_base() == world.ASHEN_OFFSET, "база ashen = ASHEN_OFFSET")
	chk(pt.x >= 0 and pt.y >= 0 and pt.x < 40 and pt.y < 30, "герой в локальных тайлах 40x30")
	# живой цикл: мобы + Ведьма в группах
	var bosses := _bosses_in_ashen()
	chk(bosses.size() == 1, "Ведьма в группе boss (блип s=4)")
	var enemies := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and (e as Node2D).global_position.y > world.ASHEN_OFFSET.y:
			enemies += 1
	chk(enemies >= 5, "enemy-мобы Пепелища на радаре (%d)" % enemies)
	await _vis_ok("Пепелище proc")
	await _paint_ok("ashen")

func _bosses_in_ashen() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and (b as Node2D).global_position.y > world.ASHEN_OFFSET.y:
			out.append(b)
	return out

# ---------------------------------------------------------------- события
func _phase_events() -> void:
	var az = world.ashen_grid
	# сундук взят: узел снят + флаг; «раунд-трип» зон — тот же путь, что у
	# F9/смены зоны, при котором деревенские/пещерные POI тоже пересобираются
	GameState.set_flag("ashen.chest", "taken")
	az.chest_node.queue_free()
	await _frames(4)
	world.apply_area("village", true)
	await _repoll()
	world.apply_area("ashen", true)
	await _repoll()
	chk(_poi_of(Minimap.C_CHEST).is_empty(), "сундук взят — блип погас (после смены зоны)")
	chk(_poi_of(Minimap.C_PORTAL).size() == 1, "раунд-трип: портал снова один")
	# смерть Ведьмы -> живой цикл снимает блип, флаг dead
	var witch = az.boss_node
	witch.hurt(999, witch.global_position + Vector2(0, 20))
	await _frames(6)
	chk(String(GameState.flags.get("ashen.boss", "")) == "dead", "флаг ashen.boss=dead")
	chk(_bosses_in_ashen().is_empty(), "Ведьма вне группы boss — блип погас")
	await _paint_ok("после смерти Ведьмы")

# ---------------------------------------------------------------- мир без Пепелища
func _phase_nozone() -> void:
	var az = world.ashen_grid
	world.ashen_grid = null
	await _repoll()
	chk(mm._zone == "ashen" and not bool(mm._zone_seen), "нет az: тихо, без сетки, без падения")
	chk(mm._grid_tex == null, "нет az: _grid_tex сброшена")
	await _paint_ok("без az")
	world.ashen_grid = az
	await _repoll()
	chk(bool(mm._zone_seen) and int(mm._grid_w) == 40, "az вернули — сетка собралась")

# ---------------------------------------------------------------- M-тумблер
func _phase_toggle() -> void:
	Minimap.set_on(false)
	chk(not Minimap.is_on(), "set_on(false)")
	await _frames(2)
	chk(not bool(mm._layer.visible), "радар скрыт на следующий кадр")
	chk(not bool(mm._radar.is_visible_in_tree()), "M off: радар вне видимого дерева")
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	chk(f != null, "cfg-файл записан")
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		chk(typeof(d) == TYPE_DICTIONARY and d.get("on") == false, "cfg: on=false на диске")
	mm.toggle()
	chk(Minimap.is_on(), "toggle -> вкл")
	await _frames(2)
	chk(bool(mm._layer.visible), "радар виден")
	chk(bool(mm._radar.is_visible_in_tree()), "M on: радар вернулся в видимое дерево")
	f = FileAccess.open(CFG_PATH, FileAccess.READ)
	if f != null:
		var d2: Variant = JSON.parse_string(f.get_as_text())
		chk(d2.get("on") == true, "cfg: on=true на диске")

# ---------------------------------------------------------------- пересборка
func _phase_rebuild() -> void:
	world.queue_free()
	await _frames(4)
	world = load(Main).instantiate()
	add_child(world)
	await _frames(4)
	mm = Minimap.I
	_hook_draws()
	await _repoll()
	chk(mm._zone == "village" and mm._sig.begins_with("v|"), "новый мир: деревня как раньше")
	world.apply_area("ashen", true)
	await _repoll()
	chk(mm._zone == "ashen", "новый мир: ashen определяется")
	chk(_poi_of(Minimap.C_PORTAL).size() == 1, "новый мир: портал на месте")
	chk(_poi_of(Minimap.C_CHEST).is_empty(), "новый мир: взятый сундук не возродился")
	chk(_bosses_in_ashen().is_empty(), "новый мир: мёртвая Ведьма не заспавнена")

# ================================================== t49: подложку видно, не только собрана

func _b8(v: float) -> int:
	return int(round(v * 255.0))

## Побайтовое сравнение: после 8-битной квантизации цвет тайла не равен константе
## палитры (0.176 vs 45/255 -> float ==Color== Color лжёт), сравниваем байты ±2.
func _close8(c: Color, k: Color) -> bool:
	return absi(_b8(c.r) - _b8(k.r)) <= 2 and absi(_b8(c.g) - _b8(k.g)) <= 2 \
		and absi(_b8(c.b) - _b8(k.b)) <= 2

func _expected_grid() -> Vector2i:
	if mm._zone == "ashen" and world.ashen_grid != null:
		return Vector2i(int(world.ashen_grid.map_w), int(world.ashen_grid.map_h))
	if mm._zone == "cave" and world.dungeon_zone != null:
		return Vector2i(int(world.dungeon_zone.map_w), int(world.dungeon_zone.map_h))
	return Vector2i(int(world.map_w), int(world.map_h))

## Источник подложки и блипы ТЕКУЩЕЙ зоны: «непустая подложка» = залит КАЖДЫЙ
## тайл, при этом проходимый пол различим от стен (иначе радар был бы чёрным
## квадратом при зелёных размерах).
func _backing(tag: String) -> void:
	var exp := _expected_grid()
	chk(bool(mm._zone_seen) and mm._grid_tex != null
			and int(mm._grid_w) == exp.x and int(mm._grid_h) == exp.y,
		"%s: подложка собрана из карты зоны (%dx%d)" % [tag, exp.x, exp.y])
	var floor_px := 0
	var painted := 0
	var total := exp.x * exp.y
	if mm._grid_tex != null:
		var ti: Image = mm._grid_tex.get_image()
		ti = ti.duplicate()
		ti.convert(Image.FORMAT_RGBA8)
		for y in ti.get_height():
			for x in ti.get_width():
				var c := ti.get_pixel(x, y)
				if _close8(c, Minimap.C_FLOOR):
					floor_px += 1
					painted += 1
				elif _close8(c, Minimap.C_WALL):
					painted += 1
	chk(floor_px > 0, "%s: источник непустой — проходимый пол %d px" % [tag, floor_px])
	chk(painted > 0 and painted == total,
		"%s: залит каждый тайл источника (%d/%d)" % [tag, painted, total])
	var inb := 0
	for p in mm._pois:
		var t: Vector2i = p["t"]
		if t.x >= 0 and t.y >= 0 and t.x < int(mm._grid_w) and t.y < int(mm._grid_h):
			inb += 1
	chk(mm._pois.size() > 0 and inb == mm._pois.size(),
		"%s: POI %d/%d внутри поля — блипы не теряются" % [tag, inb, mm._pois.size()])
	var ht: Vector2i = mm._tile_of(world.player.global_position, mm._zone_base(), float(world.TILE))
	chk(ht.x >= 0 and ht.y >= 0 and ht.x < int(mm._grid_w) and ht.y < int(mm._grid_h),
		"%s: герой в поле сетки (%s)" % [tag, str(ht)])

## Аудит детей радара: никто не имеет права рисовать непрозрачным ПОВЕРХ paint().
## Так и умер радар в окне: сердцевина 9-slice панели (panel_frame.png, 99.6 %
## пикселей с a=1) рисуется StyleBox'ом, а Panel — ребёнок контрола радара, т.е.
## после его _draw(). Кольцо волны 3 проверено тем же тестом — центр обязан быть
## прозрачным.
func _overlay_audit() -> void:
	var covered: Array = []
	var frame := false
	var nine := false
	for c in mm._radar.get_children():
		if c is Panel:
			frame = true
			var sb: StyleBox = (c as Control).get_theme_stylebox("panel")
			if sb != null and sb.draw_center:
				covered.append("рамка рисует центр (draw_center=true)")
			if sb is StyleBoxTexture:
				var st := sb as StyleBoxTexture
				nine = st.texture != null and st.texture_margin_left > 0.0 \
					and st.texture_margin_top > 0.0
		elif c is TextureRect:
			var tex: Texture2D = (c as TextureRect).texture
			if tex == null:
				continue
			var im: Image = tex.get_image().duplicate()
			im.convert(Image.FORMAT_RGBA8)
			var a := im.get_pixelv(Vector2(im.get_width() / 2.0, im.get_height() / 2.0)).a
			if a > 0.5:
				covered.append("%s непрозрачно в центре (a=%.2f)" % [String(c.name), a])
	chk(frame, "у радара есть рамка-Panel (внешний вид контракта не теряем)")
	chk(nine, "рамка осталась 9-slice с полями (кайма рисуется)")
	chk(covered.is_empty(), "поле радара не перекрыто непрозрачным [%s]"
		% ("чисто" if covered.is_empty() else ", ".join(PackedStringArray(covered))))

func _phase_backing() -> void:
	world.apply_area("village", true)
	await _repoll()
	_backing("деревня")
	_overlay_audit()
	world.apply_area("cave", true)
	await _repoll()
	_backing("пещера")
	world.apply_area("ashen", true)
	await _repoll()
	_backing("Пепелище")
