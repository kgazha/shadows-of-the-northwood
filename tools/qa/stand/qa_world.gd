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
##     world-атласов и манифеста скинов;
##  W7 «Среда v1» (t11): кадры среды == лист, водная геометрия, тик-скинер B;
##  W8 «Туман открытия» (t7, вердикт 25.11): арифметика discovered-поля,
##     base64-сейв, live-посев у арки, обзор ходьбы, гейт туманных порталов,
##     reveal при входе в локацию, roundtrip тумана через disk, независимость
##     геометрии от тумана.

const RUN_SEED := 97531            # мета-сид как в qa_pg: seed_i = RUN_SEED + i*7919
const SEEDS := 16                  # тяжёлая геометрия (BFS+holes) по 16 сидам;
                                   # золотые пины — свои 5 (GOLDEN_N)
const GOLDEN_N := 5

# GOLDEN-WM-PIN(25.11, причина: «Среда v1» — водная геометрия локаций: река
# Чащи с 1-клеточными бродами на штатных дорогах, озеро Снежника, зеркало-
# оазис Пустоши; вода SOLID- block, периметр t59 и worldmap не тронуты.
# Ряд 19.11 «W-P0-1 fix»: -3144…/1295…/9108…/-1282…/-8037…; ряд 18.11:
# 8645…/4246…/6360…/8408…/-4502…).
# FNV-1a 64 composition(run_seed) = канон мира целиком (worldmap + 6 локаций + пояса).
# Пересъёмка датированная при изменении генератора — с указанием причины
# (как GOLDEN-CAVE-PIN в qa_pg).
const GOLDEN_COMP_PINS := [
	3667740230982545934,    # seed 97531
	-223799754728817763,    # seed 105450
	-6968745053202592759,   # seed 113369
	-4388011758957587721,   # seed 121288
	-8369543153597366183,   # seed 129207
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
## ^ ПЕРЕПИН 25.11 «Тлель-вепрь» (t13, замена брютов по листу «Замена v1»):
## носитель семейства brute перепечён с кодо-бейка assets/mobs_boar_v1.png
## (boar_sprite_v1.gd), геомет 64x32 и skins(15) не изменились; в json сменился
## только src шести brute-скинов. Прежний bake 18.11: 89fed95c18bc32b6443d6d3d7b046e78.
## ^ ПЕРЕПИН 26.11 «Бестиарий v2» (t26, вердикт 26.11 «принимаем всех»):
## +6 kind-строк (вид/пояс/носитель/ряд) + починка честного факта t21 №1
## (snow/wraith — silent no-op снежного мини-босса); легаси-строки побайтно
## целы (diff = только добавления + строка status). Прежний bake 25.11:
## 6f167c6dd078aaadf30071110f8fc61f (skins(15), brute->вепрь).
const MOBS_VARIANTS_MD5 := "d3be6b872419900661a9b5c493e1c8db"   # skins(22), бестиарий v2 (26.11)
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
	w7_env(OWg)
	await w8_fog(OWg)
	w9_boar()
	await w10_mini()
	await w11_minis()
	await w12_bestiary()
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
			"W6 mobs_variants.json по пину (перепин 26.11: skins(22), бестиарий v2)")
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

# --- W7 «Среда v1» (t11, вердикт 25.11) ----------------------------------------
# Паритет рантайм-циклов с утверждённым листом (FNV-пины PINS_W4), геометрия
# воды (река/озеро/оазис: наличие, непроходимость, переправы, отсутствие
# воды в чужих биомах и у периметра), детерминизм тик-скиннера варианта B,
# ноль новых растров.

const ENVW := preload("res://scripts/env_art.gd")

func w7_env(ow: Variant) -> void:
	if ow == null:
		chk(false, "W7.0 OpenWorld не загружен")
		return
	# W7.1 кадры == лист: FNV по PNG-байтам каждого кадра всех 10 циклов +
	# палитра RAMPS/FLATS без отклонений (self_check пустой).
	var mismatch := ENVW.self_check()
	chk(mismatch.is_empty(), "W7.1 кадрантайма == лист «Среда v1» (FNV-пины PINS_W4, палитра) %s"
			% ("" if mismatch.is_empty() else str(mismatch.slice(0, 3))))
	# W7.2 геометрия: вода только в трёх биомах; переправа в реке; периметр чист
	var geo_ok := true
	var ford_ok := true
	var river_ok := true
	for s in _seeds():
		var counts := {"snow": 0, "desert": 0, "forest": 0, "steppe": 0, "castle": 0, "dungeon": 0}
		for z in counts.keys():
			var lm: Dictionary = _loc(s, String(z))
			var g: Array = lm["grid"]
			var wcells := 0
			for y in g.size():
				var row := String(g[y])
				if row.find("w") >= 0 and (y <= 1 or y >= g.size() - 2):
					geo_ok = false  # вода у периметра — запрещена (t59)
				for x in row.length():
					if String(row[x]) == "w":
						wcells += 1
						if ow.walkable(g, x, y):
							geo_ok = false  # вода обязана быть непроходима
			counts[z] = wcells
			if String(z) != "snow" and String(z) != "desert" and String(z) != "forest" and wcells > 0:
				geo_ok = false
		if int(counts["snow"]) < 12 or int(counts["desert"]) < 8 or int(counts["forest"]) < 3:
			geo_ok = false
			print("  W7.2 seed=%d counts=%s" % [s, str(counts)])
		# река: брод — проходимая дорога '-' с водой слева и справа (или сверху
		# и снизу — вертикальная дорога к сундуку)
		var fg: Array = _loc(s, "forest")["grid"]
		var found := false
		for y in range(2, fg.size() - 2):
			var r := String(fg[y])
			for x in range(2, r.length() - 2):
				if String(r[x]) != "-":
					continue
				if (String(r[x - 1]) == "w" and String(r[x + 1]) == "w") \
						or (String(fg[y - 1])[x] == "w" and String(fg[y + 1])[x] == "w"):
					found = true
		if not found:
			river_ok = false
			ford_ok = false
	chk(geo_ok, "W7.2 вода: только снег/пустошь/лес, непроходима, >=12/8/3 клеток, периметр чист")
	chk(river_ok and ford_ok, "W7.3 река Чащи: 1-клеточный брод на штатной дороге (все сиды)")
	# W7.4 скинер варианта B: int((t+фаза)/K)%N — детерминирован, фазы клеток
	# разнесены, цикл замкнут (t = K*N возвращает кадр 0).
	var det_ok := true
	var phases := {}
	for i in 24:
		var ph := ENVW.cell_phase(i, 7, ENVW.T_WATER, 4)
		phases[ph] = true
		if ENVW.cell_frame(ENVW.T_WATER * 4, ph, ENVW.T_WATER, 4) \
				!= ENVW.cell_frame(0, ph, ENVW.T_WATER, 4):
			det_ok = false
		if ENVW.cell_frame(ENVW.T_WATER * 4 + 18, ph, ENVW.T_WATER, 4) \
				!= ENVW.cell_frame(18, ph, ENVW.T_WATER, 4):
			det_ok = false
	chk(det_ok and phases.size() >= 8,
		"W7.4 тик-скинер B: int((t+фаза)/K) по кадрам детерминирован, цикл замкнут, фазы разнесены")
	# W7.5 ноль растров: EnvArt не читает растровых ресурсов (только RAMPS-код)
	var src := FileAccess.get_file_as_string("res://scripts/env_art.gd")
	chk(not src.contains(".png") and not src.contains("ResourceLoader") \
			and not src.contains("_load_tex"),
			"W7.5 env_art.gd: ни одного растрового ресурса (кодо-бейк из PixelPalette)")

func _md5_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_md5(path)

# --- W8 «Туман открытия» (t7, вердикт пользователя 25.11) ---------------------
# Модель — fog_of_war.gd (preload без class_name); поток — живой world:
# посев clearing на входе, тик обзора в world._process, гейт в WorldPortal.

const FOGW := preload("res://scripts/fog_of_war.gd")

func w8_fog(ow) -> void:
	# W8.1 арифметика поля: диск, край, «открытое не забывается»
	var f = FOGW.new()
	chk(f.discovered_count() == 0 and not f.is_discovered(0, 0), "W8.1a свежий туман — поле пустое")
	chk(f.reveal_disk(Vector2i(48, 30), 2) == 25, "W8.1b диск r=2 ровно 25 клеток")
	chk(f.reveal_disk(Vector2i(48, 30), 2) == 0, "W8.1c повторный reveal — ноль нового (не забывается)")
	chk(f.reveal_disk(Vector2i(0, 0), 10) == 121, "W8.1d краевой диск клампится (11x11)")
	chk(f.is_discovered(-3, -3) and f.is_discovered(96, 60), "W8.1e за полем — «известно»")
	# W8.2 base64-сейв (компактный: 720 байт поля)
	var b64: String = f.to_b64()
	chk(b64.length() == 960, "W8.2a base64 720 байт поля = 960 символов")
	var f2 = FOGW.new()
	chk(f2.from_b64(b64) and f2.discovered_count() == f.discovered_count() \
			and f2.is_discovered(48, 30) and f2.to_b64() == b64,
			"W8.2b roundtrip discovered по base64 побайтово")
	var f3 = FOGW.new()
	chk(not f3.from_b64(Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))) \
			and f3.discovered_count() == 0,
			"W8.2c баш base64 (размер не по поля) — туман с нуля, легаси не ломается")
	if world == null or ow == null:
		chk(false, "W8.3 живой world не готов")
		return
	# живой поток: вернулись в деревню, модель — к состоянию «новый круг»
	var waited := 0
	while String(world.active_area) != "village" and waited < 600:
		if String(world.active_area) == "worldmap":
			world.exit_worldmap()
		elif String(world.active_area).begins_with("loc_"):
			world.exit_location()
		await get_tree().process_frame
		waited += 1
	GameState.wm_fog = FOGW.new()
	var toasts: Array = []
	var glue := func(s): toasts.append(String(s))
	GameState.toast.connect(glue)
	# W8.3 посев: только clearing у спавна (47,56), r=ARC_R=10 => x37..57, y46..59
	world.enter_worldmap()
	waited = 0
	while String(world.active_area) != "worldmap" and waited < 300:
		await get_tree().process_frame
		waited += 1
	var wg = world.get("worldmap_grid")
	var fog = GameState.wm_fog
	chk(fog != null and fog.discovered_count() == 21 * 14,
			"W8.3 spawn-clearing 294 клетки (21x14 у южного края), север — туман")
	chk(fog.is_discovered(48, 58) and fog.is_discovered(47, 56), "W8.3b арка и спавн видимы")
	var portals_fogged := true
	for z in PORTAL_CELLS_STAND:
		var pc: Array = PORTAL_CELLS_STAND[z]
		if fog.is_discovered(int(pc[0]), int(pc[1])):
			portals_fogged = false
	chk(portals_fogged and not fog.is_discovered(0, 0),
			"W8.3c все шесть порталов и север — в тумане")
	chk(wg.get("fog_spr") is Sprite2D, "W8.3d туман — Sprite2D-вуаль (ImageTexture, без геометрии)")
	# W8.4 обзор ходьбы: телепорт в дальнюю проходную клетку — тик обязан
	# открыть ровно квадрат 21x21. Допустимая клетка (детерминированный скан):
	#  * cheb > 25 до спавна — диски r=10 непересекаемы, пробы cheb=14 чисты;
	#  * cheb > 10 до порталов Чащи/Снежника — они останутся туманными для
	#    W8.5/W8.7 (кольцо Снежника и угол (48,4) — вне диска: y подопытной >= 14).
	var c := Vector2i.ZERO
	var found := false
	for y in range(14, 46):
		for x in range(14, 82):
			if not ow.walkable(wg.map_rows, x, y):
				continue
			if ow.cheb(Vector2i(x, y), Vector2i(47, 56)) <= 25:
				continue
			if ow.cheb(Vector2i(x, y), Vector2i(20, 44)) <= 10 \
					or ow.cheb(Vector2i(x, y), Vector2i(52, 8)) <= 10:
				continue
			c = Vector2i(x, y)
			found = true
			break
		if found:
			break
	chk(found, "W8.4a найдена подопытная клетка в туманной дали")
	if found:
		var before: int = fog.discovered_count()
		world.player.global_position = Vector2(0.0, ow.WM_OFFSET_Y) + wg.tile_to_world(c)
		await _frames(3)
		var disk_ok := true
		for dy in range(-10, 11):
			for dx in range(-10, 11):
				if not fog.is_discovered(c.x + dx, c.y + dy):
					disk_ok = false
		chk(fog.discovered_count() == before + 441 and disk_ok,
				"W8.4b герой открыл ровно 441 клетку (квадрат r=10, непересечения)")
		chk(not fog.is_discovered(c.x - 14, c.y) and not fog.is_discovered(c.x, c.y - 14),
				"W8.4c за радиусом обзора — туман (пробы cheb=14)")
		# W8.5 туманный портал: E не срабатывает, подсказка «место туманное»
		var fp = (wg.get("portal_nodes") as Dictionary).get("forest", null)
		chk(fp != null and wg.portal_fogged("forest"), "W8.5a портал Чащи ещё в тумане")
		if fp != null:
			var area_before := String(world.active_area)
			toasts.clear()
			chk(String(fp.get_hint()) == "Место туманное", "W8.5b подсказка туманного портала")
			fp.try_interact()
			await _frames(2)
			var denied := false
			for t in toasts:
				if String(t).contains("туманное"):
					denied = true
			chk(String(world.active_area) == area_before and denied,
					"W8.5c E в тумане НЕ срабатывает + тост-подсказка")
			# W8.6 открытая клетка — портал штатно работает; возврат дозволен
			fog.reveal_disk(Vector2i(20, 44), 0)
			chk(not wg.portal_fogged("forest") and String(fp.get_hint()) == "Чаща — войти",
					"W8.6a после reveal подсказка вернулась")
			# отель = где стояли на карте мира перед входом (loc_return)
			var hotel: Vector2 = world.player.global_position
			world.enter_location("forest")
			waited = 0
			while String(world.active_area) != "loc_forest" and waited < 300:
				await get_tree().process_frame
				waited += 1
			chk(String(world.active_area) == "loc_forest", "W8.6b вход в открытую локацию штатен")
			world.exit_location()
			waited = 0
			while String(world.active_area) != "worldmap" and waited < 300:
				await get_tree().process_frame
				waited += 1
			chk(String(world.active_area) == "worldmap" \
					and world.player.global_position.distance_to(hotel) < 2.0,
					"W8.6c возврат из локации всегда дозволен (отель у портала)")
			# W8.7 вход в локацию открывает её портал и окрестности (PORTAL_R=3)
			chk(not fog.is_discovered(52, 8), "W8.7a портал Снежника ещё туманен")
			world.enter_location("snow")
			waited = 0
			while String(world.active_area) != "loc_snow" and waited < 300:
				await get_tree().process_frame
				waited += 1
			chk(fog.is_discovered(52, 8) and fog.is_discovered(49, 5) and fog.is_discovered(55, 11) \
					and not fog.is_discovered(48, 4),
					"W8.7b вход в локацию открыл портал + кольцо r=3 (угол cheb=4 — туман)")
			world.exit_location()
			waited = 0
			while String(world.active_area) != "worldmap" and waited < 300:
				await get_tree().process_frame
				waited += 1
		# W8.8 сейв: to_dict/v4 аддитивно, легаси без ключа, roundtrip диска
		var snap: Dictionary = GameState.to_dict()
		var fog_b64 := String(snap.get("wm_fog", ""))
		var cnt_saved: int = fog.discovered_count()
		chk(fog_b64 != "" and fog_b64.length() == 960,
				"W8.8a to_dict: ключ wm_fog (base64 720 байт), v остаётся 4")
		var legacy: Dictionary = snap.duplicate(true)
		legacy.erase("wm_fog")
		GameState.from_dict(legacy)
		chk(GameState.wm_fog == null and int(GameState.to_dict().get("v", 0)) == 4 \
				and String(GameState.to_dict().get("wm_fog", "x")) == "",
				"W8.8b легаси-сейв без ключа: туман ВЫКЛ (null), v4, ключ круглит пустым")
		GameState.from_dict(snap)
		chk(GameState.wm_fog.discovered_count() == cnt_saved \
				and GameState.wm_fog.is_discovered(52, 8) and GameState.wm_fog.is_discovered(47, 56) \
				and not GameState.wm_fog.is_discovered(0, 0),
				"W8.8c discovered восстановлен из сейва (roundtrip в памяти)")
		var saved_ok: bool = GameState.save_game()
		GameState.wm_fog.reveal_disk(Vector2i(0, 0), 20)
		GameState.load_game()
		chk(saved_ok and GameState.wm_fog.discovered_count() == cnt_saved \
				and not GameState.wm_fog.is_discovered(0, 0),
				"W8.8d disk roundtrip: туман с диска перечеркнул послесейв-правки")
		# W8.9 геометрия тумана не видит: walkable == генератор, слой — Sprite2D
		var geo_ok := true
		for y in range(0, int(wg.map_h), 7):
			for x in range(0, int(wg.map_w), 5):
				if wg.cell_walkable(Vector2i(x, y)) != ow.walkable(wg.map_rows, x, y):
					geo_ok = false
		chk(geo_ok and wg.fog_spr != null and not (wg.fog_spr is CollisionObject2D),
				"W8.9 проходимость не зависит от тумана; вуаль без коллайдеров")
	if GameState.toast.is_connected(glue):
		GameState.toast.disconnect(glue)

func _cjk(s: String) -> int:
	var n := 0
	for i in s.length():
		var u := s.unicode_at(i)
		if (u >= 0x2E80 and u <= 0x9FFF) or (u >= 0xFB00 and u <= 0xFB4F) or u == 0x200B or u == 0xFEFF:
			n += 1
	return n

# --- W9 «Тлель-вепрь» (t13, замена брютов 25.11, лист «Замена v1») --------------
# Механический слот не двигался (brute_tier — W2.4 выше; TIERS — qa_lp T11/qa_ng;
# рывок-механика босса — qa_gb). Здесь: носитель, палитра, силуэт-антикупол,
# перескин всех биомов и «легаси больше нигде не рисуется».

func w9_boar() -> void:
	var PAL = load("res://scripts/pixel_palette.gd")
	var idx: Dictionary = PAL.color_index()
	if not ResourceLoader.exists("res://assets/mobs_boar_v1.png"):
		chk(false, "W9.1 носитель assets/mobs_boar_v1.png есть")
		return
	chk(true, "W9.1 носитель assets/mobs_boar_v1.png есть (кодо-бейк boar_sprite_v1.gd)")
	var img: Image = load("res://assets/mobs_boar_v1.png").get_image()
	chk(img.get_width() == 64 and img.get_height() == 32,
			"W9.2 геометрия листа 64x32 == легаси (regions/TIERS.scale не плывут)")
	var off := 0
	for y in 32:
		for x in 64:
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and not idx.has(PAL.key(c)):
				off += 1
	chk(off == 0, "W9.3 палитра носителя чиста (RAMPS off=%d)" % off)
	var lo_x := 99
	var hi_x := -1
	var lo_y := 99
	var hi_y := -1
	var bone := 0
	var eye := 0
	var bone_k: int = PAL.key(PAL.c("BONE", PAL.T_LIGHT))
	var eye_k: int = PAL.key(PAL.c("HP_RED", PAL.T_MID))
	for y in 32:
		for x in 32:
			var p := img.get_pixel(x, y)
			if p.a > 0.5:
				lo_x = mini(lo_x, x)
				hi_x = maxi(hi_x, x)
				lo_y = mini(lo_y, y)
				hi_y = maxi(hi_y, y)
				var k: int = p.to_argb32()
				if k == bone_k:
					bone += 1
				elif k == eye_k:
					eye += 1
	var w := hi_x - lo_x + 1
	var h := maxi(hi_y - lo_y + 1, 1)
	chk(w == 30 and h == 20,
			"W9.4 K0 огранычок %dx%d == 30x20 (лист-канон, x2 с 16px-дизайна)" % [w, h])
	# Анти-трапеция по ветке «читается пропорцией» (вепрь — низкий широкий таран):
	# у купола-брюта огранычок 27x22 (w/h~1.23, да и тот шире к НИЗУ); вепрь — 1.50.
	chk(float(w) / float(h) >= 1.4,
			"W9.5 пропорция w/h=%.2f >= 1.4 — низкий широкий, не купол" % (float(w) / float(h)))
	chk(bone >= 2 and eye >= 2,
			"W9.6 опознаки K0: клык BONE=%d, глаз HP_RED=%d (К0)" % [bone, eye])
	var mf: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/mobs_variants.json"))
	var srcs_ok := true
	var n_brute := 0
	if typeof(mf) == TYPE_DICTIONARY:
		var skins: Dictionary = (mf as Dictionary).get("skins", {})
		for key in skins:
			if String(key).ends_with("/brute"):
				n_brute += 1
				if String((skins[key] as Dictionary)["src"]) != "res://assets/mobs_boar_v1.png":
					srcs_ok = false
	chk(n_brute == 6 and srcs_ok,
			"W9.7 все 6 биомных brute-скинов пестуются с mobs_boar_v1.png")
	var src_txt := FileAccess.get_file_as_string("res://scripts/brute.gd")
	chk(not src_txt.contains("assets/brute.png"),
			"W9.8 рантайм brute.gd не грузит легаси-лист (пиксель-канон: нигде не рисуется)")

# --- W10 микро-подземелье «Лес» (t19 «Глубина v2 §2а», 25.11) ------------------
# Пины контракта t19: вход/выход тем же интерактором, сундук один раз,
# мини-босс в дальней комнате, перф-прогрев (утечки/раунд-трипы). Ген
# (связность ×8 сидов) — в qa_pg PG12; здесь — живая проводка world.

func w10_mini() -> void:
	if world == null:
		chk(false, "W10.0 живой world не поставлен")
		return
	var MD := load("res://scripts/mini_dungeon.gd")
	GameState.start_fresh_game()
	var gz = world.biome_grids.get("forest", null)
	if gz == null:
		chk(false, "W10.0 loc_forest не собрана (wire-секции не дошли?)")
		return
	# W10.1 ход в локации: есть, клетка == детерминированный pick_hole, 'f' проходима
	var hole = world.mini_holes.get("forest", null)
	chk(hole != null and is_instance_valid(hole), "W10.1a ход «Чащи» стоит в локации")
	if hole == null:
		return
	var want: Vector2i = MD.pick_hole(gz.map_rows, gz.spawn_tile, gz.chest_tile,
			gz.portal_out_tile, "forest")
	var hole_tile := Vector2i(int(floor(hole.position.x / 16.0)),
			int(floor((hole.position.y - 2.0) / 16.0)))
	chk(hole_tile == want, "W10.1b клетка хода = pick_hole-ожидание (%s == %s)" % [hole_tile, want])
	chk(gz.cell_walkable(hole_tile), "W10.1c клетка хода проходима")
	# W10.2 вход: зона, позиция, лимиты камеры, геометрия
	world.enter_mini("forest")
	await _frames(40)
	chk(String(world.active_area) == "mini_forest",
			"W10.2a enter_mini -> active_area mini_forest")
	var mz = world.mini_grids.get("forest", null)
	chk(mz != null and mz.map_w == 40 and mz.map_h == 24,
			"W10.2b внутренняя карта 40×24 собрана")
	if mz == null:
		return
	var spawn_w: Vector2 = Vector2(0.0, float(MD.MINI_Y)) + mz.spawn_world_pos()
	chk(world.player.global_position.distance_to(spawn_w) < 0.75,
			"W10.2c герой на спавне хода (клетка выхода)")
	var cam = world.cam
	chk(cam.limit_top == int(MD.MINI_Y) and cam.limit_bottom == int(MD.MINI_Y) + 24 * 16
			and cam.limit_right == 40 * 16,
			"W10.2d лимиты камеры = границы хода (этаж 48000)")
	chk(mz.exit_node != null and is_instance_valid(mz.exit_node),
			"W10.2e выход «тем же интерактором» стоит на спавне")
	# W10.3 мини-босс: якорь = meta.far (тот же чистый generate), статы — пин
	var regen: Dictionary = MD.generate(GameState.run_seed, "forest")
	var bmeta: Array = regen["meta"]["boss"]
	chk(mz.boss_tile == Vector2i(int(bmeta[0]), int(bmeta[1])) and mz.boss_node != null,
			"W10.3a мини-босс в дальней комнате (якорь генератора)")
	# лесной пояс = 1 (PORTAL_CELLS), ярус 1: hp round(round(6×1,25)×2,5)=20,
	# dmg max(2, round(round(1×1,25)×1,5))=2, xp 6×3=18 (BALANCE §«Микро-подземелья»)
	var boss = mz.boss_node
	chk(boss != null and int(boss.hp) == 20 and int(boss.dmg) == 2 and int(boss.kill_xp) == 18
			and int(boss.tier) == 1 and bool(boss.boss) == false,
			"W10.3b статы мини-босса 20/2/18 ярус1×пояс1×мини-вилка (пин t19)")
	# W10.4 сундук: реликт ровно один раз
	var chest = mz.chest_node
	chk(chest != null and String(chest.get_hint()) == "Открыть сундук",
			"W10.4a сундук хода ждёт E")
	if chest != null:
		var owned_before: Array = GameState.owned_gear.duplicate()
		var gold0: int = int(GameState.gold)
		chest.try_interact()
		var gained: Array = []
		for k in GameState.owned_gear:
			if not owned_before.has(k):
				gained.append(String(k))
		var aff_ok: bool = false
		for g in gained:
			var aff: Array = GameState.affixes.get(g, []) as Array
			if aff.size() == 2:
				aff_ok = true
		chk(gained.size() == 1 and aff_ok,
				"W10.4b открытый сундук = ровно 1 вещь пула, реликтовая (2 аффикса)")
		chest.try_interact()
		chk(int(GameState.gold) == gold0 and GameState.owned_gear.size() == owned_before.size() + 1
				and GameState.chests_used.has("chest@mini_forest:%d,%d" % [mz.chest_tile.x, mz.chest_tile.y]),
				"W10.4c повторный тычок — ноль награды (сундук один раз за круг)")
	# W10.5 смерть мини-босса = «ход закрыт» (q.bm.forest; watch против teardown)
	if boss != null:
		boss.dying = true
		boss.queue_free()
		await _frames(4)
		chk(int(GameState.get_flag("q.bm.forest", 0)) == 1,
				"W10.5a смерть мини-босса закрывает ход (q.bm.forest=1)")
	# W10.6 выход тем же интерактором: ровно на клетку хода в локации
	world.exit_mini("forest")
	await _frames(40)
	chk(String(world.active_area) == "loc_forest"
			and world.player.global_position.distance_to((hole as Node2D).global_position) < 0.75,
			"W10.6 выход из хода ставит героя на клетку хода")
	# W10.7 резолвер зоны резюме (сейв внутри хода переживает рестарт процесса)
	GameState.area = "mini_forest"
	chk(String(GameState.resolve_resume_zone("mini_forest")) == "mini_forest",
			"W10.7 резолвер зон пропускает mini_forest")
	GameState.area = "village"
	# W10.8 перф-прогрев: три туда-обратно — утечек нод нет, контейнер один
	var cnt0: int = world.find_children("*", "", true, false).size()
	for _r in 3:
		world.enter_mini("forest")
		await _frames(40)
		world.exit_mini("forest")
		await _frames(40)
	var cnt1: int = world.find_children("*", "", true, false).size()
	chk(cnt1 == cnt0 and (world.mini_cont as Dictionary).size() == 1,
			"W10.8 прогресс-раунды хода×3: утечек нод 0, сцена переиспользуется")
	# W10.9 (t25, 25.11, находка t22 diag-t22/mini_save_probe): сейв ВНУТРИ хода
	# обязан резюмироваться в ход — и по F9-пути (do_quickload), и по полному
	# рестарту сцены (_ready loaded->apply_zone->_place_resumed_player).
	# До фикса RED: apply_zone затирает GameState.area до чтения ключа резюме.
	world.enter_mini("forest")
	await _frames(40)
	GameState.player_pos = world.player.global_position
	GameState.pos_valid = true
	var mini_sv: bool = GameState.save_game()
	chk(mini_sv and String(GameState.area) == "mini_forest",
			"W10.9a сейв в ходу записан (area в сейве mini_forest)")
	world.do_quickload()
	await _frames(40)
	chk(String(world.active_area) == "mini_forest" and String(GameState.area) == "mini_forest",
			"W10.9b quickload возвращает в ход (active/area mini_forest), не в деревню")
	var mzp: Vector2 = world.player.global_position
	chk(mzp.distance_to(GameState.player_pos) < 0.5 and mzp.y >= float(MD.MINI_Y),
			"W10.9c поза = поза сейва на этаже хода (y>=%.0f)" % float(MD.MINI_Y))
	# W10.9d полный рестарт сцены: новый инстанс main.tscn проходит ровно ветку
	# _ready(loaded=true) — тот же код, что перезапуск приложения
	var old_w: Node = world
	var fresh: Node = load("res://scenes/main.tscn").instantiate()
	old_w.queue_free()
	add_child(fresh)
	await _frames(30)
	world = fresh
	chk(world != null and String(world.active_area) == "mini_forest"
			and world.player.global_position.distance_to(GameState.player_pos) < 0.5
			and String(GameState.area) == "mini_forest",
			"W10.9d рестарт сцены резюмирует в ход (area/active/поза)")
	# соседям — чистый старт: сейв стёрт, мир возвращён в деревню (как до W10)
	_wipe_save()
	GameState.pos_valid = false
	world.apply_area("village")
	await _frames(10)

# --- W11 микро-подземелья x5 (t20 «Глубина v2 §2б», 25.11) --------------------
# Лес разобран подробно в W10; здесь — ОБОД каждый открытый MD.BIOMES биом:
# ход == pick_hole-ожидание, вход на свой этаж (лимиты камеры = этаж,
# резюме-резолвер), мини-босс = ожидаемая шкура и статы по формуле (базы
# семей — скриптовые константы, TIERS брута — её конста), сундук, выход
# ровно на клетку хода. Обход дополнительно служит утечкой-щупом.

const W11_BASE := {
	"archer": {"hp": 4, "xp": 9},
	"swarmling": {"hp": 2, "xp": 3},
	"wraith": {"hp": 8, "xp": 15},
}
const W11_FAM := {"steppe": "archer", "desert": "swarmling", "snow": "wraith",
		"castle": "brute", "dungeon": "wraith"}

func w11_minis() -> void:
	if world == null:
		chk(false, "W11.0 живой world не поставлен")
		return
	var MD := load("res://scripts/mini_dungeon.gd")
	var BR := load("res://scripts/brute.gd")
	# Разогрев: ПЕРВЫЙ вход в каждый ход строит его сцену (легитимные ноды —
	# тилы/стены/сундук/босс/вотчер), утечкой не является. Щуп снимаем на
	# раунде ПОВТОРНОГО использования (t20: наивный замер до прогона ловил
	# сборки 5 сцен как «+136 нод»).
	for b0 in MD.BIOMES:
		if String(b0) == "forest":
			continue
		world.enter_mini(String(b0))
		await _frames(40)
		world.exit_mini(String(b0))
		await _frames(40)
	var cnt0: int = world.find_children("*", "", true, false).size()
	for b in MD.BIOMES:
		var bio := String(b)
		if bio == "forest":
			continue  # лес — подробная разделка W10
		var gz = world.biome_grids.get(bio, null)
		var hole = world.mini_holes.get(bio, null)
		if gz == null or hole == null:
			chk(false, "W11[%s] ход/локация не стоят" % bio)
			continue
		var want: Vector2i = MD.pick_hole(gz.map_rows, gz.spawn_tile, gz.chest_tile,
				gz.portal_out_tile, bio)
		var hp0 := (hole as Node2D).position
		var ht := Vector2i(int(floor(hp0.x / 16.0)), int(floor((hp0.y - 2.0) / 16.0)))
		chk(ht == want and gz.cell_walkable(want),
				"W11[%s]a ход локации = pick_hole-ожидание и проходим" % bio)
		world.enter_mini(bio)
		await _frames(40)
		var mz = world.mini_grids.get(bio, null)
		var fy := int(MD.mini_y(bio))
		var ok_in: bool = String(world.active_area) == "mini_" + bio and mz != null \
				and world.cam.limit_top == fy and world.cam.limit_bottom == fy + 24 * 16 \
				and world.player.global_position.distance_to(
						Vector2(0.0, MD.mini_y(bio)) + mz.spawn_world_pos()) < 0.75 \
				and String(GameState.resolve_resume_zone("mini_" + bio)) == "mini_" + bio
		chk(ok_in, "W11[%s]b вход на этаж хода %d (лимиты/позиция/резолвер)" % [bio, fy])
		if mz == null:
			continue
		var fam := String(W11_FAM.get(bio, "brute"))
		var want_path := ("res://scripts/mob_" + fam + ".gd") if fam != "brute" \
				else "res://scripts/brute.gd"
		var boss = mz.boss_node
		var belt := int(OWg.zone_belt(bio))
		var mult: float = OWg.belt_mult(belt)
		var ok_b: bool = boss != null and String(boss.get_script().resource_path) == want_path
		if boss != null:
			if fam == "brute":
				var tb: Dictionary = BR.TIERS[int(OWg.brute_tier(belt))]
				ok_b = ok_b and int(boss.hp) == maxi(1, int(round(int(round(float(int(tb["hp"])) * mult)) * 2.5))) \
						and int(boss.kill_xp) == int(tb["xp"]) * 3
			else:
				var bb: Dictionary = W11_BASE[fam]
				ok_b = ok_b and int(boss.hp) == maxi(1, int(round(int(round(float(int(bb["hp"])) * mult)) * 2.5))) \
						and int(boss.kill_xp) == int(bb["xp"]) * 3 \
						and absf(float(boss.dmg_mult) - mult * 1.5) < 1e-6
		chk(ok_b, "W11[%s]c мини-босс=%s и статы по формуле (пояс %d)" % [bio, fam, belt])
		# t26 (26.11 «Бестиарий v2», вердикт «принимаем всех»): мини-босс едет
		# ЛИСТОМ КОЖЕЙ — face атласа равенства + kind-атрибуция убийцы. Статы
		# выше (W11]c) не двигнуты ни на единицу: пины 20/2/18 и 35/45 в силе.
		if boss != null:
			var fbx = boss.get("anim")
			var fbt := false
			if fbx != null and fbx.sprite_frames != null:
				var fban := "walk" if fam == "brute" else "walk_down"
				if fbx.sprite_frames.has_animation(fban) \
						and fbx.sprite_frames.get_frame_count(fban) > 0:
					var fbat := fbx.sprite_frames.get_frame_texture(fban, 0) as AtlasTexture
					fbt = fbat != null and fbat.atlas != null \
							and String(fbat.atlas.resource_path).ends_with("mobs_bestiary_v2.png")
			chk(fbt and String(boss.get("kill_kind")) == String(OWg.KIND_BY_BIOME.get(bio, "")),
					"W11[%s]f мини-босс в обличье вида (лицо==лист, kind-атрибуция)" % bio)
		var chest = mz.chest_node
		chk(chest != null and String(chest.get_hint()) == "Открыть сундук",
				"W11[%s]d реликтовый сундук стоит" % bio)
		world.exit_mini(bio)
		await _frames(40)
		chk(String(world.active_area) == "loc_" + bio
				and world.player.global_position.distance_to((hole as Node2D).global_position) < 0.75,
				"W11[%s]e выход на клетку хода" % bio)
	var cnt1: int = world.find_children("*", "", true, false).size()
	chk(cnt1 == cnt0, "W11.x обход биомов: утечек нод нет (%d == %d)" % [cnt1, cnt0])

## t26 «Бестиарий v2» (26.11, вердикт пользователя «принимаем бестиарий всех»):
## спавн-пины поясов. BESTIARY/loc_map-метки и GOLDEN побайтно целы — вид
## подменяет детерминированную сущность на слое спавна (biome_zone), поэтому
## стенд проверяет ЖИВОЙ пояс: ровно один вид биома, скрипт-носитель, лицо из
## атласа равенства, лут семейный, статы = семейство × множитель пояса (та же
## control-методика, что W4.6a/c), плюс починка честного факта t21 №1.
func w12_bestiary() -> void:
	if world == null:
		chk(false, "t26: живой world не поставлен — спавн не проверен")
		return
	for bio in OWg.ZONES:
		world.enter_location(String(bio))
		var waited := 0
		while String(world.active_area) != "loc_" + String(bio) and waited < 300:
			await get_tree().process_frame
			waited += 1
		await _frames(20)
		var zn = (world.get("biome_grids") as Dictionary).get(String(bio), null)
		if zn == null:
			chk(false, "t26[%s]: локация не построена" % bio)
			continue
		var kind := String(OWg.KIND_BY_BIOME.get(String(bio), ""))
		var want_fam := String(OWg.KIND_FAMILY.get(kind, ""))
		var found := 0
		var sp = null
		var face_ok := false
		var stack: Array = [zn]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			var scr := n.get_script() as Script
			if scr == null or not String(scr.resource_path).ends_with(want_fam + ".gd"):
				continue
			if String(n.get("kill_kind")) != kind:
				continue
			found += 1
			sp = n
			var aspr = n.get("anim")
			if aspr != null and aspr.sprite_frames != null:
				var aname := "walk" if want_fam == "brute" else "walk_down"
				if aspr.sprite_frames.has_animation(aname) \
						and aspr.sprite_frames.get_frame_count(aname) > 0:
					var at := aspr.sprite_frames.get_frame_texture(aname, 0) as AtlasTexture
					face_ok = at != null and at.atlas != null \
							and String(at.atlas.resource_path).ends_with("mobs_bestiary_v2.png")
		chk(found == 1 and face_ok,
				"t26[%s]: вид %s один в поясе и одет в атлас равенства" % [bio, kind])
		if found == 1 and sp != null:
			var belt12 := int(OWg.zone_belt(String(bio)))
			var loot_ok: bool
			if want_fam == "brute":
				loot_ok = String(sp.belt_loot) == "brute_t%d@b%d" % [int(sp.tier), belt12]
			else:
				loot_ok = String(sp.loot_kind) == "%s@b%d" % [want_fam, belt12]
			var m2 = load("res://scripts/" + ("brute.gd" if want_fam == "brute"
					else "mob_" + want_fam + ".gd")).new()
			world.get_node("Village").add_child(m2)
			if want_fam == "brute":
				m2.boss = false
				m2.tier = int(sp.tier)
			m2.setup(world, Vector2i(2, 2))
			var want_hp := maxi(1, int(round(float(int(m2.hp)) * float(OWg.belt_mult(belt12)))))
			# Ветка элит (26.11, каноn t41): ролл Elites мог накрыть носителя вида —
			# тогда BALANCE-формула честно ожидаем hp x2 (meta «elite» ставит Elites.apply).
			if bool(sp.get_meta("elite", false)):
				want_hp = maxi(1, int(round(float(want_hp) * 2.0)))
			m2.queue_free()
			chk(loot_ok and int(sp.hp) == want_hp,
					"t26[%s]: статы/лут вида = семейство × пояс (BALANCE-формула, не новая строка)" % bio)
	# Починка честного факта t21 №1: ГОЛЫЙ apply_biome_skin носителя надевает
	# face (snow/wraith больше не silent no-op) — без всякой явной выдачи.
	var wfix = load("res://scripts/mob_wraith.gd").new()
	world.get_node("Village").add_child(wfix)
	wfix.setup(world, Vector2i(2, 2))
	OWg.apply_biome_skin(wfix, "snow")
	var wtx := false
	if wfix.anim != null and wfix.anim.sprite_frames != null \
			and wfix.anim.sprite_frames.has_animation("idle_down"):
		var wat := wfix.anim.sprite_frames.get_frame_texture("idle_down", 0) as AtlasTexture
		wtx = wat != null and wat.atlas != null \
				and String(wat.atlas.resource_path).ends_with("mobs_bestiary_v2.png")
	wfix.queue_free()
	chk(wtx, "t26: ПОЧИНКА — apply_biome_skin(snow) на носителе даёт face шептуна (был no-op)")
	# Правило «plain > kind»: подземельный wraith сохраняет свой plain-remap —
	# рудокоп надевается только явной выдачей спавну вида.
	var wpl = load("res://scripts/mob_wraith.gd").new()
	world.get_node("Village").add_child(wpl)
	wpl.setup(world, Vector2i(2, 2))
	OWg.apply_biome_skin(wpl, "dungeon")
	var ptx := false
	if wpl.anim != null and wpl.anim.sprite_frames != null \
			and wpl.anim.sprite_frames.has_animation("idle_down"):
		var pat := wpl.anim.sprite_frames.get_frame_texture("idle_down", 0) as AtlasTexture
		ptx = pat != null and pat.atlas != null \
				and String(pat.atlas.resource_path).ends_with("mobs_wraith_dungeon_v1.png")
	wpl.queue_free()
	chk(ptx, "t26: plain-remap старший — скин dungeon/wraith лицом вида не заменён")
