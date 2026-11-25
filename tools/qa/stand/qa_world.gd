extends Node2D
## qa_world — стенд t3 «Мир v1» (открытый мир: генератор, пояса, сейв,
## проводка, края, гигиена). Формат: "QA_WORLD x/y" + exit code
## (manifest: mode "xy", re "QA_WORLD (\d+)/(\d+)").
##
## Разделы:
##  W1 генератор: детерминизм (двойная генерация побайтово равна), золотые
##     пины composition (FNV-1a 64, сиды RUN_SEED + i*7919):
##     BFS-достижимость порталов/арки/сундуков, closed-run проходы >=2,
##     константность решёток;
##  W2 пояса: belt_mult/gold_mult таблицы, ДВОЙНОЙ пин таблицы порталов
##     (пересчёт Chebyshev != литеральные константы стенда), brute_tier;
##  W3 сейв: "area" в to_save, миграция без-area, roundtrip зон, wm.open;
##  W4 проводка: живой world — apply_area лимиты/ZoneVoid, цепочка
##     деревня->мир->локация->мир->деревня, скины/скайлинг/чекпоинт,
##     байт-целость деревни (t65-пины);
##  W5 края (t59-якорь): глухое кольцо 7 карт ×16 сидов, guard позиции,
##     camera-риг == пиксельный прямоугольник карты — выходов за край ноль;
##  W6 гигиена: системный хэш строки запрещён (F3), CJK — ноль, md5-пины
##     world-атласов и манифеста скинов.

const RUN_SEED := 97531            # мета-сид как в qa_pg: seed_i = RUN_SEED + i*7919
const SEEDS := 16                  # тяжёлая геометрия (BFS+holes) по 16 сидам;
                                   # золотые пины — свои 5 (GOLDEN_N)
const GOLDEN_N := 5

# GOLDEN-WM-PIN(19.11, причина: «W-P0-1 fix» — южные ворота мира перестали
# прорезать ряд 59, кольцо снизу замкнуто; ряд 18.11: 8645…/4246…/6360…/8408…/-4502…):
# FNV-1a 64 composition(run_seed) = канон мира целиком (worldmap + 6 локаций + пояса).
# Пересъёмка датированная при изменении генератора — с указанием причины
# (как GOLDEN-CAVE-PIN в qa_pg).
const GOLDEN_COMP_PINS := [
	-3144181420589087209,  # seed 97531
	1295891944235987713,   # seed 105450
	9108852878537949803,   # seed 113369
	-1282044995112029049,  # seed 121288
	-8037476502682230815,  # seed 129207
]
# Двойной пин таблицы порталов (стенд независим от OpenWorld.PORTAL_CELLS):
# клетка -> ожидаемый пояс (BALANCE.md «Мир v1» строки 11–14).
const BELT_TABLE_EXPECT := {"forest": 1, "steppe": 1, "dungeon": 2, "castle": 2, "snow": 3, "desert": 2}
const PORTAL_CELLS_STAND := {"forest": [20, 44], "steppe": [62, 46], "dungeon": [12, 32],
		"castle": [78, 18], "snow": [52, 8], "desert": [84, 36]}
const GATE_ANCHOR_STAND := [47, 58]
# мир-атласы (bake wire, 18.11): ПЕРЕПИН датированный — причина: +ARCH_NORTH,
# +ROAD_F1/F2, сдвиг упаковки (прежние w1: floor 8C599CCA…, props B31F054B…)
const WORLD_FLOOR_MD5 := "eb9d505235cedd38fe5dca843518ad0d"
const WORLD_PROPS_MD5 := "377a691a222238e2fdd9fa848d55c475"
const WORLD_REGIONS_MD5 := "6d72298ace3e1c4654a162786446c2f9"
## ^ ПЕРЕПИН 25.11 «Д2 disposition tile-12» (t3): в json добавлен только строковый
## ключ floor_slots_note (комментарий-аналог forest_note, по образцу JSON без
## синтаксических комментариев); floor_slots/props байт-в-байт прежние, читатели
## (worldmap_zone/biome_zone parsed.get) незнакомый ключ игнорируют. Прежний пин
## w1-wire: 429589588f6a1db711cee6752c7ad86a.
const MOBS_VARIANTS_MD5 := "89fed95c18bc32b6443d6d3d7b046e78"   # skins(15), bake 18.11 (шаг 3)
const VILLAGE_V4_MD5 := "3159f23a2da9303b8771099b09f23a21"     # t65-прецедент: деревня байт-цела
const FOREST_PROPS_MD5 := "f1451755ade072a458b077dbd946d255"

var total := 0
var pass_n := 0
var fail_n := 0
var OWg: Variant = null
var world = null  # Variant: живой world вызывается динамически (apply_area и пр.)

func chk(cond: bool, name: String) -> void:
	total += 1
	if cond:
		pass_n += 1
	else:
		fail_n += 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

func _seeds() -> Array:
	var out: Array = []
	for i in SEEDS:
		out.append(RUN_SEED + i * 7919)
	return out

# Мемоизация: W1 и W5.1 проходят по одним и тем же сидам — генератор чистый,
# кэш побайтово безопасен (детерминизм сам проверяется W1.1–W1.3 до кэша).
var _wm_cache := {}
var _loc_cache := {}

func _wm(s: int) -> Dictionary:
	if not _wm_cache.has(s):
		_wm_cache[s] = OWg.worldmap_map(s)
	return _wm_cache[s]

func _loc(s: int, z: String) -> Dictionary:
	var k := "%d|%s" % [s, z]
	if not _loc_cache.has(k):
		_loc_cache[k] = OWg.loc_map(s, z)
	return _loc_cache[k]

func _ready() -> void:
	print("[qa_world] begin")
	# хороший сосед: юзер-сейв может лежать от ЧУЖИХ прогонов в общем appdata
	# батареи — убираем до первого instantiate мира (иначе _ready резюмится)
	_wipe_save()
	if ResourceLoader.exists("res://scripts/open_world.gd"):
		OWg = load("res://scripts/open_world.gd")
	w1_generator(OWg)
	w2_belts(OWg)
	w3_save()
	await _frames(2)
	await w4_wiring()
	await w5_edges()
	w6_hygiene()
	# и после себя не оставляем: автосейвы чекпойнтов/фикстуры W3 — на диске
	_wipe_save()
	GameState.start_fresh_game()
	print("QA_WORLD %d/%d" % [pass_n, total])
	get_tree().quit(0 if fail_n == 0 else 1)

func _wipe_save() -> void:
	if FileAccess.file_exists("user://save_morkheim.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))

# физически согласованный y-этап зоны для roundtrip-сейвов (тот же пол,
# что у генератора: WM 14400, локации — LOC_OFFSET_Y, легаси — 0/4800/9600)
func _floor_of(z: String) -> float:
	match z:
		"cave": return 5100.0
		"ashen": return 9900.0
		"worldmap": return 14500.0
		"loc_snow": return 19300.0
		"loc_desert": return 24100.0
		"loc_steppe": return 28900.0
		"loc_forest": return 33700.0
		"loc_castle": return 38500.0
		"loc_dungeon": return 43300.0
		_: return 300.0  # village

# --- W1 генератор -------------------------------------------------------------

func w1_generator(ow: Variant) -> void:
	if ow == null:
		chk(false, "W1.0 open_world.gd — поставка не на месте")
		return
	chk(true, "W1.0 open_world.gd загружен")
	# W1.1 детерминизм: два вызова на одном сиде побайтово равны (worldmap + 6 локаций)
	var zs := RUN_SEED
	var a: Dictionary = ow.worldmap_map(zs)
	var b: Dictionary = ow.worldmap_map(zs)
	chk(str(a["grid"]) == str(b["grid"]), "W1.1 worldmap детерминистична (сетка)")
	chk(str(a["meta"]) == str(b["meta"]), "W1.2 worldmap meta детерминистична")
	var det_loc := true
	for z in ow.ZONES:
		var l1: Dictionary = ow.loc_map(zs, z)
		var l2: Dictionary = ow.loc_map(zs, z)
		if str(l1) != str(l2):
			det_loc = false
	chk(det_loc, "W1.3 loc_map детерминистична ×6 биомов")
	# W1.4 золотые пины composition
	var pin_ok := true
	for i in GOLDEN_N:
		var comp: Dictionary = ow.composition(RUN_SEED + i * 7919)
		var h: int = ow.hash_map(comp)
		if GOLDEN_COMP_PINS[i] == 0 or h != GOLDEN_COMP_PINS[i]:
			pin_ok = false
			print("  pin[%d] seed=%d fnv64=%d" % [i, RUN_SEED + i * 7919, h])
	chk(pin_ok, "W1.4 GOLDEN-WM-PIN composition ×%d" % GOLDEN_N)
	# W1.5 решётки: размеры/строки постоянны, алфавит легален
	var legal := "#.sdfcu-paMWCSirbtng"
	var shapes_ok := true
	var seed0: int = _seeds()[0]
	var wm0: Dictionary = ow.worldmap_map(seed0)
	if int(wm0["width"]) != ow.WM_W or int(wm0["height"]) != ow.WM_H or (wm0["grid"] as Array).size() != ow.WM_H:
		shapes_ok = false
	for rowv in wm0["grid"]:
		if String(rowv).length() != ow.WM_W:
			shapes_ok = false
		for cidx in String(rowv).length():
			if legal.find(String(rowv)[cidx]) < 0:
				shapes_ok = false
	chk(shapes_ok, "W1.5 worldmap %dx%d, алфавит легален" % [ow.WM_W, ow.WM_H])
	# W1.6–W1.8: сиды — BFS-достижимость, проходы >=2, константные порталы
	var bfs_ok := true
	var holes_ok := true
	var cells_ok := true
	for s in _seeds():
		var wm: Dictionary = _wm(s)
		var grid: Array = wm["grid"]
		var spawn: Array = wm["meta"]["spawn"]
		var seen: Dictionary = ow.reachable(grid, Vector2i(spawn[0], spawn[1]))
		for z in ow.PORTAL_CELLS:
			var pc: Vector2i = ow.PORTAL_CELLS[z]
			if not seen.has("%d,%d" % [pc.x, pc.y]):
				bfs_ok = false
			if ow.ch_at(grid, pc.x, pc.y) != "p":
				cells_ok = false
		var ar: Array = wm["meta"]["arch"]
		if not seen.has("%d,%d" % [ar[0], ar[1]]):
			bfs_ok = false
		if ow.cluster_holes(grid).size() > 0:
			holes_ok = false
			print("  holes worldmap seed=%d: %s" % [s, str(ow.cluster_holes(grid).slice(0, 4))])
	for z in ow.ZONES:
		for s in _seeds():
			var lm: Dictionary = _loc(s, String(z))
			var lgrid: Array = lm["grid"]
			var sp: Array = lm["meta"]["spawn"]
			var lseen: Dictionary = ow.reachable(lgrid, Vector2i(sp[0], sp[1]))
			var po: Array = lm["meta"]["portal_out"]
			var ch: Array = lm["meta"]["chest"]
			if not lseen.has("%d,%d" % [po[0], po[1]]) or not lseen.has("%d,%d" % [ch[0], ch[1]]):
				bfs_ok = false
				print("  BFS loc %s seed=%d lost portal_out/chest" % [z, s])
			if ow.cluster_holes(lgrid).size() > 0:
				holes_ok = false
				print("  holes loc %s seed=%d: %s" % [z, s, str(ow.cluster_holes(lgrid).slice(0, 4))])
	chk(cells_ok, "W1.6 порталы на константных проходимых клетках (p)")
	chk(bfs_ok, "W1.7 BFS ×%d сидов: 6 порталов+арка; в локациях портал/сундук" % SEEDS)
	chk(holes_ok, "W1.8 closed-run проходы >=2 клетки (7 карт ×%d сидов)" % SEEDS)
	# W1.9 ворота кольца — тупиковый коридор (W-P0-1, 19.11): клетки x=47..48
	# y=57..58 проходимы (коридор к арке), ПОСЛЕДНИЙ ряд 59 глух — кольцо замкнуто.
	var gate_ok := true
	for gy in range(ow.WM_H - 3, ow.WM_H - 1):
		for gx in range(ow.WM_GATE_X, ow.WM_GATE_X + 2):
			if not ow.walkable((wm0["grid"] as Array), gx, gy):
				gate_ok = false
	for gx in range(ow.WM_GATE_X, ow.WM_GATE_X + 2):
		if ow.walkable((wm0["grid"] as Array), gx, ow.WM_H - 1):
			gate_ok = false
			print("  W1.9: клетка (%d,%d) проходима — кольцо размкнуто (walk-out!)" % [gx, ow.WM_H - 1])
	chk(gate_ok, "W1.9 ворота: коридор x=47..48 y=57..58, ряд 59 глух (W-P0-1)")

# --- W2 пояса -----------------------------------------------------------------

func w2_belts(ow: Variant) -> void:
	if ow == null:
		chk(false, "W2.0 OpenWorld не загружен")
		return
	var want := [1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75]
	var ok := true
	for b in 8:
		if absf(ow.belt_mult(b) - want[b]) > 1e-9:
			ok = false
	chk(ok, "W2.1 belt_mult(0..7) = 1+0,25·b")
	var gw := [1.0, 1.15, 1.30, 1.45, 1.60, 1.75, 1.90, 2.05]
	var gok := true
	for b in 8:
		if absf(ow.gold_mult(b) - gw[b]) > 1e-9:
			gok = false
	chk(gok, "W2.2 gold_mult(0..7) = 1+0,15·b")
	# Двойной пин таблицы порталов: независимый пересчёт Chebyshev в стенде
	# (литералы стенда) против OpenWorld.portal_belt; пояс из констант листа.
	var table_ok := true
	for z in BELT_TABLE_EXPECT:
		var cell: Array = PORTAL_CELLS_STAND[z]
		var d := maxi(absi(cell[0] - GATE_ANCHOR_STAND[0]), absi(cell[1] - GATE_ANCHOR_STAND[1]))
		var b := d / 14
		if b != int(BELT_TABLE_EXPECT[z]) or ow.portal_belt(z) != int(BELT_TABLE_EXPECT[z]):
			table_ok = false
			print("  belt %s: stand=%d ow=%d expect=%d" % [z, b, ow.portal_belt(z), BELT_TABLE_EXPECT[z]])
	chk(table_ok, "W2.3 таблица порталов: Chebyshev/14 == литеральные пояса (двойной пин)")
	var tier_ok: bool = ow.brute_tier(0) == 1 and ow.brute_tier(1) == 1 and ow.brute_tier(2) == 2 and ow.brute_tier(3) == 3
	chk(tier_ok, "W2.4 brute_tier(0..3)=1,1,2,3")
	# W2.5 пояса в meta карт == портал-пояс (генератор не имеет права плыть)
	var meta_ok := true
	for z in ow.ZONES:
		var lm: Dictionary = ow.loc_map(RUN_SEED, z)
		if int(lm["meta"]["belt"]) != ow.portal_belt(z):
			meta_ok = false
	chk(meta_ok, "W2.5 meta.belt локаций == portal_belt")

# --- W3 сейв ------------------------------------------------------------------

func w3_save() -> void:
	# W3.1 to_save: явный ключ area (v4 аддитивно)
	GameState.area = "village"
	var ts: Dictionary = GameState.to_dict()
	chk(ts.has("area") and String(ts["area"]) == "village", "W3.1 to_save: ключ \"area\" (аддитивно к v4)")
	# W3.2 roundtrip по всем именам зон — ФИЗИЧЕСКИ СОГЛАСОВАННЫЕ v4-сейвы
	# (правилу резюме): зона подтверждена своим этажом/py (или флагом пещеры).
	var rt := true
	for z in ["village", "cave", "ashen", "worldmap", "loc_snow", "loc_desert",
			"loc_steppe", "loc_forest", "loc_castle", "loc_dungeon"]:
		GameState.area = z
		GameState.in_cave = (z == "cave")
		GameState.player_pos = Vector2(0.0, _floor_of(z))
		GameState.pos_valid = true
		var d: Dictionary = GameState.to_dict()
		GameState.area = "?"
		GameState.from_dict(d)
		if GameState.area != z:
			rt = false
			print("  roundtrip %s -> %s" % [z, GameState.area])
	chk(rt, "W3.2 roundtrip area: все имена зон")
	# W3.3 легаси-сейвы без ключа: цепочка in_cave/y-этажей (миграция без потерь)
	var mig := true
	var cases := [
		[true, 300.0, "cave"], [false, 10000.0, "ashen"], [false, 14500.0, "worldmap"],
		[false, 20000.0, "loc_snow"], [false, 25000.0, "loc_desert"], [false, 30000.0, "loc_steppe"],
		[false, 34000.0, "loc_forest"], [false, 39000.0, "loc_castle"], [false, 43300.0, "loc_dungeon"],
		[false, 500.0, "village"],
	]
	for c in cases:
		var f: Dictionary = GameState.to_dict()
		f.erase("area")
		f["in_cave"] = bool(c[0])
		f["py"] = float(c[1])
		f["pos_valid"] = true
		GameState.area = "?"
		GameState.from_dict(f)
		if GameState.area != String(c[2]):
			mig = false
			print("  legacy in_cave=%s py=%s -> %s (хотели %s)" % [c[0], c[1], GameState.area, c[2]])
	chk(mig, "W3.3 легаси без area: цепочка cave/ashen/7 этажей/village")
	# W3.3b сейв-без-позиции (автосейв достижений посреди фазы): ключ area есть,
	# доказательств нет — легаси-паритет: деревня («вышел к входу»).
	var f9: Dictionary = GameState.to_dict()
	f9["area"] = "ashen"
	f9["py"] = 0.0
	f9["pos_valid"] = false
	f9["in_cave"] = false
	GameState.from_dict(f9)
	chk(GameState.area == "village", "W3.3b сейв без позиции -> деревня (паритет до-t3)")
	# W3.4 старый fixture: остальные поля миграцию переживают
	var f7: Dictionary = GameState.to_dict()
	f7["gold"] = 123
	f7["v"] = 3
	f7.erase("area")
	f7["py"] = 500.0
	GameState.from_dict(f7)
	chk(GameState.gold == 123 and GameState.area == "village", "W3.4 legacy fixture: gold цел, area выведена")
	# W3.5 флаги wm.open.<biome> — аддитивны к v4 flags
	GameState.set_flag("wm.open.snow", "1")
	var f8: Dictionary = GameState.to_dict()
	GameState.flags.erase("wm.open.snow")
	GameState.from_dict(f8)
	chk(str(GameState.flags.get("wm.open.snow", "")) == "1", "W3.5 flags wm.open.<biome> roundtrip")
	GameState.flags.erase("wm.open.snow")

# --- W4 проводка ---------------------------------------------------------------

func w4_wiring() -> void:
	chk(_md5_file("res://assets/village/village_v4.png") == VILLAGE_V4_MD5,
			"W4.0 village_v4.png байт-цел (t65-прецедент)")
	chk(_md5_file("res://assets/forest/forest_props_v1.png") == FOREST_PROPS_MD5,
			"W4.0 forest_props_v1.png байт-цел")
	if OWg == null or not ResourceLoader.exists("res://scripts/worldmap_zone.gd") \
			or not ResourceLoader.exists("res://scripts/biome_zone.gd"):
		chk(false, "W4.1 зонные скрипты — поставка не на месте")
		return
	# чистый заход: сейв на диске не должен тащить прошлый забег
	if FileAccess.file_exists("user://save_morkheim.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_morkheim.json"))
	GameState.area = "village"
	world = load("res://scenes/main.tscn").instantiate()
	add_child(world)
	await _frames(4)
	var wg = world.get("worldmap_grid")
	chk(wg == null, "W4.1a старт без фриза: worldmap ленив (null сразу после _ready)")
	chk(world._ensure_worldmap(), "W4.1b _ensure_worldmap(): сетка построена по требованию")
	wg = world.get("worldmap_grid")
	chk(wg != null, "W4.1 worldmap_grid построен живым world")
	if wg == null:
		return
	# W4.2 apply_area("worldmap"): лимиты == grid*TILE, герой на этаже мира
	world.apply_area("worldmap")
	var cam: Camera2D = world.get("cam")
	var map_w: int = int(wg.map_w)
	var map_h: int = int(wg.map_h)
	chk(cam.limit_left == 0 and cam.limit_top == int(OWg.WM_OFFSET_Y) \
			and cam.limit_right == map_w * 16 and cam.limit_bottom == int(OWg.WM_OFFSET_Y) + map_h * 16,
			"W4.2 worldmap: camera-риг == 1536×960 пиксельный rect")
	chk(world.player.global_position.y >= float(OWg.WM_OFFSET_Y) \
			and world.player.global_position.y < float(OWg.WM_OFFSET_Y) + float(map_h * 16),
			"W4.2b teleport: герой в границах этажа мира")
	var vp: Polygon2D = world.get_node_or_null("ZoneVoid")
	var poly_ok := vp != null and vp.polygon.size() == 4
	if poly_ok:
		var bb := Rect2(vp.polygon[0], Vector2.ZERO)
		for ptx in vp.polygon:
			bb = bb.expand(ptx)
		poly_ok = bb.size.x >= float(map_w * 16) and bb.size.y >= float(map_h * 16)
	chk(poly_ok, "W4.2c ZoneVoid накрывает всю карту мира")
	# W4.3 цепочка: карта мира -> локация (полный переход с твином)
	world.enter_location("snow")
	var waited := 0
	while String(world.active_area) != "loc_snow" and waited < 300:
		await get_tree().process_frame
		waited += 1
	chk(String(world.active_area) == "loc_snow", "W4.3 мир -> Снежные пустоши (штатный переход)")
	await _frames(40)  # добить твин до конца: флаг первой встречи ставится в callback
	var sg = world.get("biome_grids")
	var snow = (sg as Dictionary).get("snow", null) if sg != null else null
	chk(snow != null and int(snow.belt) == int(BELT_TABLE_EXPECT["snow"]) \
			and world.player.global_position.y >= float(OWg.LOC_OFFSET_Y["snow"]),
			"W4.4 локация: постройка, пояс 3, герой на этаже 19200")
	chk(str(GameState.flags.get("wm.open.snow", "")) == "1", "W4.5 чекпоинт: флаг wm.open.snow + автосейв")
	# W4.6 наполнение: количество мобов == meta, скин биома применён, HP по поясу
	# Скайл сверяется с КОНТРОЛЬНЫМ мобом, собранным тем же setup-путём на этом
	# же GameState — независим от внутренних множителей волны/класса.
	var ctrl = load("res://scripts/slime.gd").new()
	world.get_node("Village").add_child(ctrl)
	ctrl.setup(world, world.get("spawn_tile") if world.get("spawn_tile") != null else Vector2i(24, 14))
	var base_hp := int(ctrl.hp)
	ctrl.queue_free()
	var mobs_n := 0
	var skinned := false
	var hp_ok := true
	var stack: Array = [snow]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var scr := n.get_script() as Script
		if scr == null:
			continue
		var p := String(scr.resource_path)
		if p.ends_with("slime.gd") or p.ends_with("brute.gd") or p.ends_with("mob_archer.gd") \
				or p.ends_with("mob_swarmling.gd") or p.ends_with("mob_wraith.gd"):
			mobs_n += 1
			if p.ends_with("slime.gd"):
				# belt 3 -> ×1,75 от канона того же setup
				if int(n.get("hp")) != int(round(float(base_hp) * OWg.belt_mult(3))):
					hp_ok = false
					print("  slime hp=%d, ждали %d (base %d ×1,75)" % [int(n.get("hp")),
							int(round(float(base_hp) * OWg.belt_mult(3))), base_hp])
				var sprs: Array = _find_anim(n)
				for fr in sprs:
					if String(fr).contains("mobs_slime_snow_v1"):
						skinned = true
	var meta_mobs: Array = (snow.get("mobs_meta") as Array) if snow.get("mobs_meta") != null else []
	chk(mobs_n == meta_mobs.size() and mobs_n > 0, "W4.6a мобы: spawned %d == meta %d" % [mobs_n, meta_mobs.size()])
	chk(skinned, "W4.6b скин: атлас slime -> mobs_slime_snow_v1 (c22-метод)")
	chk(hp_ok, "W4.6c поясной скайл: slime HP == base×1,75 (b3)")
	# W4.7 обратный ход: локация -> мир (отель у портала) -> деревня (арка)
	var hotel_before: Vector2 = world.get("loc_return").get("snow", Vector2.INF) if world.get("loc_return") != null else Vector2.INF
	world.exit_location()
	waited = 0
	while String(world.active_area) != "worldmap" and waited < 300:
		await get_tree().process_frame
		waited += 1
	chk(String(world.active_area) == "worldmap" \
			and hotel_before != Vector2.INF \
			and world.player.global_position.distance_to(hotel_before) < 0.01,
			"W4.7 локация -> мир: возврат ровно на отель входа")
	world.exit_worldmap()
	waited = 0
	while String(world.active_area) != "village" and waited < 300:
		await get_tree().process_frame
		waited += 1
	var arch_pos: Vector2 = world.tile_to_world(Vector2i(22, 2))
	chk(String(world.active_area) == "village" \
			and world.player.global_position.distance_to(arch_pos) < 0.01,
			"W4.8 мир -> деревня: выход к северной арке (22,2)")
	chk(String(GameState.area) == "village", "W4.9 GameState.area отслеживает цепочку")
	# W4.10 интерактор арки существует в деревне (без правки map_village.json).
	# Вложенный класс world.gd: get_script() у таких узлов null — опознаём по типу.
	var arch_found := false
	var WSC = load("res://scripts/world.gd")
	for ch2 in world.get_node("Village").get_children():
		if is_instance_of(ch2, WSC.WorldArchNorth):
			if ch2.has_method("try_interact") \
					and ch2.global_position.distance_to(arch_pos) < 0.01:
				arch_found = true
	chk(arch_found, "W4.10 северная арка — интерактор на (22,2), карта деревни не тронута")
	chk(FileAccess.get_file_as_string("res://data/map_village.json").length() > 0 \
			and _md5_file("res://data/map_village.json") == MAP_VILLAGE_MD5,
			"W4.11 map_village.json байт-цел от пина 25.11 «Д2 лес запад»")
	# W4.12 штатная цепочка вход/выход ДЛЯ КАЖДОГО из 6 порталов: мир -> локация
	# (полный твин, герой на своём этаже, мобы на месте) -> мир (отель).
	var chain_ok := true
	world.enter_worldmap()
	waited = 0
	while String(world.active_area) != "worldmap" and waited < 300:
		await get_tree().process_frame
		waited += 1
	for z in OWg.ZONES:
		var zz := String(z)
		world.enter_location(zz)
		waited = 0
		while String(world.active_area) != "loc_" + zz and waited < 300:
			await get_tree().process_frame
			waited += 1
		var gz2 = (world.get("biome_grids") as Dictionary).get(zz, null)
		var on_floor: bool = world.player.global_position.y >= float(OWg.LOC_OFFSET_Y[zz])
		if String(world.active_area) != "loc_" + zz or gz2 == null or not on_floor \
				or _count_mobs(gz2) <= 0:
			chain_ok = false
			print("  chain %s: area=%s floor=%s mobs=%d" % [zz, str(world.active_area),
					str(on_floor), _count_mobs(gz2) if gz2 != null else -1])
		world.exit_location()
		waited = 0
		while String(world.active_area) != "worldmap" and waited < 300:
			await get_tree().process_frame
			waited += 1
		if String(world.active_area) != "worldmap":
			chain_ok = false
	world.exit_worldmap()
	waited = 0
	while String(world.active_area) != "village" and waited < 300:
		await get_tree().process_frame
		waited += 1
	chk(chain_ok and String(world.active_area) == "village",
			"W4.12 полная цепочка вход/выход 6/6 порталов + возврат в деревню")

const MAP_VILLAGE_MD5 := "ad0734e6825052db9156a31a800c4c41"
	# ^ ПЕРЕПИН 25.11 «Д2 лес запад» (t3): row21 x5 «t»->«f» — пробита РОВНО одна
	# клетка глухой поляны (5,21), длина строк/сетка 59×37 бит-в-бит, роща 4->3.
	# Зеркала: qa_vlg PIN_MAP_ROWS/PIN_T 58/PIN_BASE_BLOCK 84, qa_lp T44_MAP_MD5.
	# Прежний пин: d7a25f92f296c02e1bbca2684a6a3826 (HEAD 8d917dc, git diff пуст).

# --- W5 края (t59-якорь) --------------------------------------------------------

func w5_edges() -> void:
	if OWg == null:
		chk(false, "W5 нет OpenWorld")
		return
	# W5.1 геометрия: глухое кольцо по периметру 7 карт × сиды. С 19.11 (W-P0-1)
	# ИСКЛЮЧЕНИЕ ДЛЯ ВОРОТ СНЯТО — нижняя стена карты мира глуха целиком; именно
	# это исключение слепило проверку и пропустило walk-out за край.
	var ring_ok := true
	for s in _seeds():
		var wm: Dictionary = _wm(s)
		var g: Array = wm["grid"]
		var h := g.size()
		var w0 := String(g[0]).length()
		for cidx in w0:
			if not (String(g[0])[cidx] in OWg.SOLID):
				ring_ok = false
			if not (String(g[h - 1])[cidx] in OWg.SOLID):
				ring_ok = false
		for ry in h:
			var row := String(g[ry])
			if not (String(row)[0] in OWg.SOLID) or not (String(row)[w0 - 1] in OWg.SOLID):
				ring_ok = false
		for z in OWg.ZONES:
			var lg: Array = (_loc(s, String(z)) as Dictionary)["grid"]
			var lh := lg.size()
			var lw := String(lg[0]).length()
			for cidx in lw:
				if not (String(lg[0])[cidx] in OWg.SOLID) or not (String(lg[lh - 1])[cidx] in OWg.SOLID):
					ring_ok = false
			for ry in lh:
				var lrow := String(lg[ry])
				if not (String(lrow)[0] in OWg.SOLID) or not (String(lrow)[lw - 1] in OWg.SOLID):
					ring_ok = false
	chk(ring_ok, "W5.1 глухое кольцо: периметр 7 карт ×%d сидов, БЕЗ исключений (W-P0-1)" % SEEDS)
	# W5.2 guard резюме: точки ЗА краем каждого из 8 этажей отклоняются world
	# (ни одна не станет позицией респауна/резюме — «выходов за край ноль»)
	var guard_ok := true
	var floors: Array = [OWg.WM_OFFSET_Y]
	for z in OWg.ZONES:
		floors.append(OWg.LOC_OFFSET_Y[z])
	if world != null and world.has_method("_pos_walkable"):
		for fy in floors:
			var fyy := float(fy)
			for probe in [Vector2(-8.0, fyy + 100.0), Vector2(4000.0, fyy + 8.0),
					Vector2(300.0, fyy - 4.0)]:
				if bool(world.call("_pos_walkable", probe)):
					guard_ok = false
					print("  guard pass: %s (floor %d)" % [str(probe), int(fyy)])
	else:
		guard_ok = false
	chk(guard_ok, "W5.2 resume-guard: точки за краем карты отклонены на 8 этажах")
	# W5.3 camera-риг каждой новой зоны == её пиксельный rect (мир > вида =>
	# полос нет; при малых окнах — ZoneVoid, W4.2c) — по живой сетке world.
	if world != null:
		var rig_ok := true
		for z in OWg.ZONES:
			world.apply_area("loc_" + String(z))
			var gz = (world.get("biome_grids") as Dictionary).get(z, null)
			var cam2: Camera2D = world.get("cam")
			if gz == null or cam2.limit_top != int(OWg.LOC_OFFSET_Y[z]) \
					or cam2.limit_right != int(gz.map_w) * 16 \
					or cam2.limit_bottom != int(OWg.LOC_OFFSET_Y[z]) + int(gz.map_h) * 16:
				rig_ok = false
				print("  rig %s: gz=%s top=%d want=%d right=%d want=%d bottom=%d want=%d" % [z,
						str(gz != null), cam2.limit_top, int(OWg.LOC_OFFSET_Y[z]), cam2.limit_right,
						int(gz.map_w) * 16 if gz != null else -1, cam2.limit_bottom,
						int(OWg.LOC_OFFSET_Y[z]) + (int(gz.map_h) * 16 if gz != null else 0)])
			# Контракт вида — 640×360 zoom1 (headless get_viewport_rect отдаёт
			# сырое окно 1280×720 — не ориентир). Зоны обязаны быть больше вида.
			if gz != null and (int(gz.map_w) * 16 <= 640 or int(gz.map_h) * 16 <= 360):
				rig_ok = false  # локация обязана быть больше вида (иначе — полосы)
		world.apply_area("village")
		chk(rig_ok, "W5.3 camera-риг 6 локаций == rect, каждая > вьюпорта (нет полос)")
	else:
		chk(false, "W5.3 нет живого world для rig-проверки")

# --- W6 гигиена -----------------------------------------------------------------

func w6_hygiene() -> void:
	for p: String in ["res://scripts/open_world.gd", "res://scripts/worldmap_zone.gd",
			"res://scripts/biome_zone.gd", "res://tools_art/world_paint.gd",
			"res://tools_art/mob_variants_v1.gd"]:
		if not FileAccess.file_exists(p):
			chk(false, "W6 %s — файл не на месте" % p.get_file())
			continue
		var t := FileAccess.get_file_as_string(p)
		chk(not t.contains(".hash("), "W6 %s: системный хэш строки не используется (F3)" % p.get_file())
		chk(_cjk(t) == 0, "W6 %s: CJK/лигатуры — ноль" % p.get_file())
	chk(_md5_file("res://assets/world/world_floor_v1.png") == WORLD_FLOOR_MD5,
			"W6 world_floor_v1.png по пину (перепин 18.11: +ROAD)")
	chk(_md5_file("res://assets/world/world_props_v1.png") == WORLD_PROPS_MD5,
			"W6 world_props_v1.png по пину (перепин 18.11: +ARCH_NORTH)")
	chk(_md5_file("res://assets/world/world_regions.json") == WORLD_REGIONS_MD5,
			"W6 world_regions.json по пину")
	chk(_md5_file("res://assets/world/mobs_variants.json") == MOBS_VARIANTS_MD5,
			"W6 mobs_variants.json по пину (bake 18.11)")
	var skins := 0
	var da := DirAccess.open("res://assets/world")
	if da != null:
		da.list_dir_begin()
		var fn := da.get_next()
		while fn != "":
			if fn.begins_with("mobs_") and fn.ends_with("_v1.png"):
				skins += 1
			fn = da.get_next()
	chk(skins == 15, "W6 листов скинов ровно 15 (5 семейств × 3 биомных набора)")

# --- хелперы ---------------------------------------------------------------------

func _count_mobs(gz) -> int:
	if gz == null:
		return -1
	var n := 0
	var stack: Array = [gz]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for cc in c.get_children():
			stack.append(cc)
		var scr := c.get_script() as Script
		if scr != null:
			var p := String(scr.resource_path)
			if p.ends_with("slime.gd") or p.ends_with("brute.gd") or p.ends_with("mob_archer.gd") \
					or p.ends_with("mob_swarmling.gd") or p.ends_with("mob_wraith.gd"):
				n += 1
	return n

func _find_anim(n: Node) -> Array:
	# пути текстур кадров всех AnimatedSprite2D поддерева (для skin-проверки)
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for cc in c.get_children():
			stack.append(cc)
		var as2 := c as AnimatedSprite2D
		if as2 != null and as2.sprite_frames != null:
			for an in as2.sprite_frames.get_animation_names():
				for i in as2.sprite_frames.get_frame_count(String(an)):
					var ft := as2.sprite_frames.get_frame_texture(String(an), i)
					var at := ft as AtlasTexture
					if at != null and at.atlas != null:
						out.append(String(at.atlas.resource_path))
	return out

func _md5_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_md5(path)

func _cjk(s: String) -> int:
	var n := 0
	for i in s.length():
		var u := s.unicode_at(i)
		if (u >= 0x2E80 and u <= 0x9FFF) or (u >= 0xFB00 and u <= 0xFB4F) or u == 0x200B or u == 0xFEFF:
			n += 1
	return n
