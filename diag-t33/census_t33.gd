extends Node2D
## t33 — базовая ПЕРЕПИСЬ СКУЧНОСТИ (I0). Свой проигрыватель: инстансит игру
## (res://scenes/main.tscn) и играет марионеткой. Каналы ввода — те же, чем
## пользуется игрок: ходьба синтезом WASD (Input.action_press/release — её
## player.gd опрашивает get_vector-ом), а E/Q/листание диалогов/выбор класса/
## атака — ПРЯМЫМ вызовом ровно тех функций, которые дёргает соответствующая
## ветка ввода (near[0].try_interact(), world.drink_potion(), hud.advance(),
## hud._pick_class(), player.attack_at()). Это не читерство, а следствие того,
## что Input.action_press в Godot 4 меняет состояние действия, но не гоняет
## InputEvent через _unhandled_input: без прямых вызовов зонд вообще не смог бы
## ничего открыть. Ноль правок в дереве игры: зонд живёт в своей сцене и своей
## копии HEAD.

const GAME_SCENE := "res://scenes/main.tscn"
const DT := 1.0 / 60.0

# тег прогона (CENSUS_TAG) разводит конфиг/итог параллельных прогонов в одном стейдже
var tag := "default"
var cfg_path := "res://census_cfg.json"
var out_path := "res://census_out.json"
const CONTACT_R := 48.0        # 3 клетки: ровно дистанция агро (CHASE_DIST у слизня)
const RELEASE_FR := 180        # 3 с вне радиуса и без урона — контакт снят
const MELEE_PX := 9.0          # встать вплотную: центр мили = поза +12 px, радиус 13
const ENGAGE_SHOOT_R := 190.0  # с этого зонд сам лезет в драку
const DISENGAGE_T := 40.0      # секунд плеча, после которых марш не даёт себя вязать
const FLEE_HP := 0.25          # порог побега
const HEAL_HP := 0.45          # порог глотка
const LEG_CAP := 120.0         # секунд на плечо маршрута

const GD := preload("res://scripts/gear_data.gd")
const OW := preload("res://scripts/open_world.gd")
const CM := preload("res://scripts/click_move.gd")

var cfg := {}
var game: Node = null
var world: Node = null
var player: Node = null
var rng := RandomNumberGenerator.new()

var frame := 0
var total_frames := 0
var restart_at := -1

# времена
var t_total := 0.0
var t_locked := 0.0
var t_dialog := 0.0
var t_modal := 0.0
var t_lock_other := 0.0
var t_lock_shop := 0.0          # t39: лавка (Shop.is_open) — окно без модалки
var t_lock_inv := 0.0           # t39: инвентарь
var t_lock_board := 0.0         # t39: доска пепла (MetaBoard)
var t_lock_summary := 0.0       # t39: экран забега (RunSummary, смерть)
var panel_frames := {}          # t39: кто сколько кадров держал залоченный ввод
var panels_closed := 0          # t39: сколько раз зонд закрыл окно игровым close()
const SHOP := preload("res://scripts/shop.gd")
const INV := preload("res://scripts/inventory.gd")
const BOARD := preload("res://scripts/meta_board.gd")
const RSUM := preload("res://scripts/run_summary.gd")
var t_in_contact := 0.0
var t_walk_pure := 0.0
var t_stuck := 0.0
var t_stuck_geom := 0.0      # t42: реально зажатый ввод, локов нет, герой не едет
var t_stuck_plan := 0.0      # t42: простой с input_locked (диалог/модалка/переход)
var dry_max := 0.0
var dry_sum := 0.0
var cur_dry := 0.0

# зоны
var z_t := {}
var z_dry_cur := {}
var z_dry_max := {}
var z_contacts := {}
var z_enemies := {}
var z_dmg_taken := {}
var z_dmg_dealt := {}
var z_loot := {}
var z_heals := {}
var z_interacts := {}
var z_walk_px := {}

# контакты
var recs := {}
var contact_events := 0
var encounter_groups := 0
var in_encounter := false
var encounter_end := -1
var engaged_now := []
var decisions := 0
var decisions_fled := 0
var bets := 0

# урон
var hp_prev := 0
var herbs_prev := 0
var dmg_taken := 0
var dmg_dealt := 0
var kills := 0
var deaths := 0
var death_log := []

# лут и прогресс
var gear_prev := 0
var chests_prev := 0
var gold_prev := 0
var gold_total := 0
var best_quality := 0
var wow_frame := -1.0
var wow_item := ""
var wow_zone := ""
var dungeons := 0
var dungeons_before_wow := -1
var levels := 0

# переходы
var area_now := ""
var area_log := []
var interact_presses := 0

# бот
var goal_kind := "нет цели"
var goal_pos := Vector2.ZERO
var path_cells := []
var path_idx := 0
var hold_until := -1
var last_pos := Vector2.ZERO
var last_dir := Vector2.ZERO
var last_moved_frame := 0
var stuck_fr := 0
var unstick_dir := Vector2.ZERO
var unstick_until := 0
var retries := 0
var roam_until := 0
var drift_at := 1800
var bfs_fail := 0
var ordered := false
var orders := 0
var order_fails := 0
var order_retry := 0
var reissue_at := 0
var cm_frames := 0
# t45-аддендум (27.11, qa-gate): собственные счётчики плана ClickMove. Прежний
# trace печатал только НАШ план (path_cells), который легально пуст, когда приказ
# делегирован игре, и «путь=0/0 следующая=нет» читалось как «в игре нет пути».
# Разбор t45 показал обратное: из той же точки игра строит путь в 5 точек.
var cm_path_n := 0
var cm_path_idx := 0
var cm_stall_rp_max := 0
var leg_max := 0
var wp_hits := 0
var leg := -1
var leg_t := 0.0
var leg_notes := []
var flee_until := 0
var heal_cd := 0.0
var interact_cd := 0.0
var advance_cd := 0.0
var held_moves := {}


func _s(v: Variant) -> String:
	return "" if v == null else str(v)


func _r2(v: float) -> float:
	return round(v * 100.0) / 100.0


func _r3(v: float) -> float:
	return round(v * 1000.0) / 1000.0


func _add(d: Dictionary, k: String, n: float) -> void:
	d[k] = float(d.get(k, 0.0)) + n


# ------------------------------------------------------------------ старт
func _ready() -> void:
	tag = OS.get_environment("CENSUS_TAG")
	if tag == "":
		tag = "default"
	cfg_path = "res://census_cfg_%s.json" % tag
	out_path = "res://census_out_%s.json" % tag
	cfg = {}
	if FileAccess.file_exists(cfg_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(cfg_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			cfg = parsed
	if cfg.is_empty():
		cfg = {"mode": "roam", "seed": 7, "seconds": 30, "cls": "warrior"}
	total_frames = int(float(cfg.get("seconds", 600)) / DT)
	rng.seed = int(cfg.get("seed", 7))
	print("=== t33 перепись: режим=%s сид=%d бюджет=%.0f с класс=%s ===" % [
			_s(cfg.get("mode")), int(cfg.get("seed")), float(cfg.get("seconds")),
			_s(cfg.get("cls"))])
	await _fresh_game(75)
	await _census()
	await _finish()


func _fr(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _fresh_game(wait_frames: int) -> void:
	# class_id НЕ выставляем: честная fresh-игра сама покажет модалку «Создание
	# героя», там зонд и кликнёт карточку — иначе герой остаётся без класса
	GameState.set("run_seed", int(cfg.get("seed", 7)))
	game = (load(GAME_SCENE) as PackedScene).instantiate()
	add_child(game)
	world = game
	var guard := 0
	while guard < 3000 and world.get("player") == null:
		await get_tree().physics_frame
		guard += 1
	player = world.get("player")
	if player == null:
		print("  !! герой не поднялся за %d кадров — перепись невозможна" % guard)
		get_tree().quit()
		return
	# Штатная модалка «Создание героя» (world.gd гейтит по class_id == ""):
	# живой игрок кликает карточку мыши — здесь ровно тот же обработчик клика.
	var hud0: Node = world.get("hud")
	var cls := _s(cfg.get("cls", "warrior"))
	for i in 180:
		if hud0 != null and bool(hud0.get("modal_shown")):
			if hud0.has_method("_pick_class"):
				hud0.call("_pick_class", cls)
			print("  класс выбран штатно (модалка): %s, hp=%d/%d, зона=%s" % [
					cls, int(GameState.get("hp")), int(GameState.get("max_hp")),
					_s(world.get("active_area"))])
			break
		if i > 90 and _s(GameState.get("class_id")) == "":
			# модалка так и не открылась (не штатный путь) — применяем класс напрямую
			GameState.call("set_class", cls)
			if player.has_method("apply_class"):
				player.call("apply_class")
			print("  класс выставлен напрямую (модалки нет): %s, hp=%d/%d" % [
					cls, int(GameState.get("hp")), int(GameState.get("max_hp"))])
			break
		await get_tree().physics_frame
	# вступительный диалог читаем со скорости ~2 страницы в секунду: locked_sec
	# меряет именно время, украденное окнами, а не скорость чтения зонда
	for i in 60:
		if hud0 == null or not bool(hud0.call("is_dialog_open")):
			break
		hud0.call("advance")
		await _fr(30)
	# страховка world.gd: замок живёт только под диалогом/модалкой/инвентарём
	if hud0 != null and bool(GameState.get("input_locked")) \
			and not bool(hud0.call("is_dialog_open")) \
			and not bool(hud0.call("is_modal_open")):
		GameState.set("input_locked", false)
	hp_prev = int(GameState.get("hp"))
	herbs_prev = int(GameState.get("herbs"))
	gold_prev = int(GameState.get("gold"))
	gear_prev = (GameState.get("owned_gear") as Array).size()
	chests_prev = (GameState.get("chests_used") as Array).size()
	area_now = _s(world.get("active_area"))
	last_pos = player.global_position
	last_moved_frame = frame
	print("  игра поднята (%d кадров): зона=%s герой=%s hp=%d/%d сид=%d" % [
			guard, area_now, _s(player.global_position), int(GameState.get("hp")),
			int(GameState.get("max_hp")), int(GameState.get("run_seed"))])
	await _fr(wait_frames)


var soft_pending := false  # t38: мягкая смерть ждёт пересборки мира внутри зонда
# t39 (27.11): CENSUS_KILL_AT=N — страховка перед пятичасовым пакетом. На N-й
# секунде прогон сам себя отправляет через ШТАТНЫЙ world.on_player_death(): так
# проверяется, что мягкая смерть t38 не убивает длинный прогон зонда (штраф
# списывает игра, зонд вспыхивает у костра и идёт дальше). 0 = выключено.
var kill_at := float(OS.get_environment("CENSUS_KILL_AT"))
# t39: CENSUS_OPEN_SHOP_AT=N — самопроверка классификатора окон: на N-й
# секунде ЗОНД открывает игровую лавку и смотрит, узнаёт ли она себя в локе и
# умеет ли его закрыть штатным close(). 0 = выключено.
var shop_at := float(OS.get_environment("CENSUS_OPEN_SHOP_AT"))
var shop_forced := false


func _soft_rebuild() -> void:
	# t38 I5: мягкая смерть БЕЗ перезагрузки сцены. Штраф списан самой игрой; здесь
	# только штатный respawn_after_death() (деревня, полный hp, in_cave=false, сейв)
	# и пересборка мира тем же путём, что у свежей игры, но БЕЗ start_new_run():
	# забег продолжается, все счётчики переписи остаются на месте.
	GameState.call("respawn_after_death")
	if is_instance_valid(game):
		game.queue_free()
	world = null
	player = null
	_release_moves()
	leg = -1
	leg_t = 0.0
	path_cells = []
	goal_kind = "нет цели"
	flee_until = 0
	GameState.set("input_locked", false)
	await _fr(5)
	await _fresh_game(45)
	print("  мягкая смерть: герой вспыхнул у костра, кадр %d (%.1f с), зона=%s, hp=%d/%d, серебро=%d" % [
			frame, float(frame) * DT, _s(world.get("active_area")),
			int(GameState.get("hp")), int(GameState.get("max_hp")), int(GameState.get("gold"))])


func _restart_run() -> void:
	# ровно как кнопка «Вспыхнуть заново»: штатный start_new_run(), затем чистая
	# пересборка сцены (тот же путь, что у свежей игры) с тем же сидом
	GameState.call("start_new_run")
	_clear_taken_flags("рестарт после мягкой смерти")
	GameState.set("run_seed", int(cfg.get("seed", 7)))
	if GameState.has_method("recalc_max_hp"):
		GameState.call("recalc_max_hp")
	if GameState.has_method("recalc_max_mana"):
		GameState.call("recalc_max_mana")
	GameState.call("heal_full")
	if is_instance_valid(game):
		game.queue_free()
	world = null
	player = null
	_release_moves()
	leg = -1
	leg_t = 0.0
	path_cells = []
	goal_kind = "нет цели"
	flee_until = 0
	await _fr(5)
	await _fresh_game(45)


# ------------------------------------------------------------------ цикл
func _census() -> void:
	while frame < total_frames:
		await get_tree().physics_frame
		_tick()
		if restart_at > 0 and frame >= restart_at:
			restart_at = -1
			if soft_pending:
				soft_pending = false
				await _soft_rebuild()
			else:
				await _restart_run()
		frame += 1
	print("  бюджет выбран: %d кадров (%.1f с)" % [frame, float(frame) * DT])


func _tick() -> void:
	if world == null or player == null or not is_instance_valid(player):
		return
	t_total += DT
	if shop_at > 0.0 and not shop_forced and t_total >= shop_at:
		shop_forced = true
		print("  САМОПРОВЕРКА t39: игровая лавка открыта принудительно на %.0f с" % t_total)
		SHOP.open("smith")
	if kill_at > 0.0 and deaths == 0 and restart_at < 0 and t_total >= kill_at:
		print("  САМОПРОВЕРКА t39: штатная смерть на %.0f с (зона %s, серебро %d)" % [
				t_total, _s(world.get("active_area")), int(GameState.get("gold"))])
		GameState.set("hp", 0)
		world.call("on_player_death")
	var area := _s(world.get("active_area"))
	if area != area_now:
		area_log.append([frame, area_now, area])
		if area == "cave" or area.begins_with("mini_"):
			dungeons += 1
		area_now = area
	_add(z_t, area, DT)

	if int(GameState.get("hp")) <= 0 and restart_at < 0:
		deaths += 1
		death_log.append([frame, area])
		print("  СМЕРТЬ #%d: кадр %d (%.1f с), зона %s" % [
				deaths, frame, float(frame) * DT, area])
		# t38 I5 (27.11): смерть стала МЯГКОЙ — забег не гаснет. Штраф игра списала
		# сама (world.on_player_death -> GameState.soft_death) и подняла диалог +
		# модалку «Вспыхнуть у костра»; штатный обработчик этой кнопки делает
		# reload_current_scene(), что для 10-минутного зонда означало бы потерю
		# прогона. Значит: то же GameState.respawn_after_death(), но пересборка
		# мира внутри зонда, без перезагрузки сцены. Повторный soft_death() НЕ
		# вызываем — иначе штраф списался бы дважды.
		soft_pending = true
		restart_at = frame + 20

	var locked := bool(GameState.get("input_locked"))
	var hud: Node = world.get("hud")
	var dlg := false
	if hud != null:
		if hud.has_method("is_dialog_open"):
			dlg = bool(hud.call("is_dialog_open"))
		if hud.has_method("is_modal_open"):
			dlg = dlg or bool(hud.call("is_modal_open"))
	if locked or dlg:
		t_locked += DT
		var dlgo := false
		var modl := false
		if hud != null:
			if hud.has_method("is_dialog_open"):
				dlgo = bool(hud.call("is_dialog_open"))
			if hud.has_method("is_modal_open"):
				modl = bool(hud.call("is_modal_open"))
		if dlgo:
			t_dialog += DT
		elif modl:
			t_modal += DT
		else:
			t_lock_other += DT
			# t39: залочен, а ни диалога, ни модалки — значит панель (лавка/инвентарь/
			# доска пепла/экран забега). Раньше зонд просто сидел в ней до конца прогона
			# (roam 777: 581 с из 600) и мерил не интерес, а закрытое окно.
			var who := ""
			if SHOP.is_open():
				who = "лавка"
			elif INV.is_open():
				who = "инвентарь"
			elif BOARD.is_open():
				who = "доска пепла"
			elif RSUM.is_open():
				who = "экран забега"
			if who == "лавка":
				t_lock_shop += DT
			elif who == "инвентарь":
				t_lock_inv += DT
			elif who == "доска пепла":
				t_lock_board += DT
			elif who == "экран забега":
				t_lock_summary += DT
			if who != "":
				panel_frames[who] = int(panel_frames.get(who, 0)) + 1
				if who != "экран забега" and int(panel_frames[who]) == 420:
					panels_closed += 1
					_note("зонд закрыл окно «%s»: ввод залочен %.0f с без диалога/модалки (игровой close)" % [who, 420 * DT])
					if who == "лавка":
						SHOP.close()
					elif who == "инвентарь":
						INV.close()
					elif who == "доска пепла":
						BOARD.close_panel()
					panel_frames[who] = 0
		if frame >= advance_cd:
			advance_cd = frame + 30
			if hud != null and bool(hud.call("is_dialog_open")) and hud.has_method("advance"):
				hud.call("advance")
			elif hud != null and bool(hud.get("modal_shown")) and hud.has_method("_pick_class"):
				hud.call("_pick_class", _s(cfg.get("cls", "warrior")))
		_release_moves()
		_observe_loot()
		return

	_observe_enemies()
	_observe_damage()
	_observe_loot()
	if _s(cfg.get("mode", "march")) == "march" and leg >= 0:
		leg_t += DT
	_order_pump()
	_policy()
	_cm_stats()
	_walk_clock()
	if int(cfg.get("trace", 0)) > 0 and frame % 60 == 0 and frame < int(cfg.get("trace_until", 3600)):
		var nr: Array = world.get("near") as Array
		print("  [бот] кадр %d зона=%s поз=%s цель=%s (%s) путь=%d/%d план_игры=%d/%d подсказок=%d hp=%d/%d вконтакте=%d кто_ведёт=%s" % [
				frame, area_now, _s(player.global_position), _s(goal_pos), goal_kind,
				path_idx, path_cells.size(), cm_path_idx, cm_path_n, nr.size(), int(GameState.get("hp")),
				int(GameState.get("max_hp")), engaged_now.size(),
				"игра(ПКМ)" if _cm_driving() else ("приказ отдан" if ordered else "сам")])


# ------------------------------------------------------------------ наблюдение
func _observe_enemies() -> void:
	engaged_now = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if bool(e.get("dying")):
			continue
		var d: float = (e as Node2D).global_position.distance_to(player.global_position)
		var id: int = e.get_instance_id()
		if not recs.has(id):
			recs[id] = {"node": e, "kind": _kind_of(e), "zone": area_now,
					"engaged": false, "last_in": -9999, "last_hit": -9999,
					"me_hit": false, "it_hit": false, "first_strike": false,
					"forced_heal": false, "forced_flee": false, "counted": false,
					"hp_prev": int(e.get("hp"))}
		var rec: Dictionary = recs[id]
		var near := d <= CONTACT_R
		var hot := frame - int(rec["last_hit"]) < RELEASE_FR
		if near or hot:
			rec["last_in"] = frame
		if bool(rec["engaged"]) and frame - int(rec["last_in"]) > RELEASE_FR:
			rec["engaged"] = false
		if bool(rec["engaged"]):
			engaged_now.append(id)
		if near and not bool(rec["engaged"]):
			rec["engaged"] = true
			contact_events += 1
			if not bool(rec["counted"]):
				rec["counted"] = true
				_add_count(z_enemies, area_now)
			engaged_now.append(id)
			_on_contact()
	if in_encounter and frame > encounter_end:
		in_encounter = false
	if engaged_now.is_empty():
		cur_dry += DT
		_add(z_dry_cur, area_now, DT)
		if float(z_dry_cur.get(area_now, 0.0)) > float(z_dry_max.get(area_now, 0.0)):
			z_dry_max[area_now] = z_dry_cur.get(area_now)
	else:
		t_in_contact += DT
		if cur_dry > dry_max:
			dry_max = cur_dry
		dry_sum += cur_dry
		cur_dry = 0.0


func _on_contact() -> void:
	_add_count(z_contacts, area_now)
	if not in_encounter:
		encounter_groups += 1
		in_encounter = true
		# каждая стычка — решение «драться или бежать»; ставка — когда чем рисковать
		decisions += 1
		if _decision_context():
			bets += 1
	encounter_end = frame + RELEASE_FR


func _decision_context() -> bool:
	var mx: int = int(GameState.get("max_hp"))
	if mx > 0 and float(GameState.get("hp")) / float(mx) < 0.7:
		return true
	if engaged_now.size() >= 2:
		return true
	for id in engaged_now:
		if _s(recs[id]["kind"]).contains("boss"):
			return true
	return false


func _observe_damage() -> void:
	var hp: int = int(GameState.get("hp"))
	var herbs: int = int(GameState.get("herbs"))
	if hp < hp_prev:
		var d := hp_prev - hp
		dmg_taken += d
		_add(z_dmg_taken, area_now, float(d))
		for id in engaged_now:
			var rec: Dictionary = recs[id]
			rec["it_hit"] = true
			rec["last_hit"] = frame
			if not bool(rec["me_hit"]):
				rec["first_strike"] = true
	elif hp > hp_prev and herbs < herbs_prev:
		# глоток трав под ударом = «заставили лечиться»; если в контакте никого
		# (стрелок бьёт из-за радиуса контакта), приписываем ближайшему врагу
		var who := engaged_now.duplicate()
		if who.is_empty():
			var nb := _nearest_enemy(240.0)
			if nb != null:
				who = [nb.get_instance_id()]
		for id in who:
			if recs.has(id):
				recs[id]["forced_heal"] = true
		_add(z_heals, area_now, 1.0)
	hp_prev = hp
	herbs_prev = herbs
	for id in recs.keys():
		var rec: Dictionary = recs[id]
		var e: Variant = rec["node"]
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var ehp := int(e.get("hp"))
		if ehp < int(rec["hp_prev"]):
			var dd := int(rec["hp_prev"]) - ehp
			dmg_dealt += dd
			_add(z_dmg_dealt, area_now, float(dd))
			rec["me_hit"] = true
			rec["last_hit"] = frame
			if ehp <= 0:
				kills += 1
		rec["hp_prev"] = ehp


func _observe_loot() -> void:
	var gear: Array = GameState.get("owned_gear") as Array
	if gear.size() > gear_prev:
		for i in range(gear_prev, gear.size()):
			var id := _s(gear[i])
			var q := int(GD.quality_of(GameState, id))
			if q > best_quality:
				best_quality = q
			_add(z_loot, area_now, 1.0)
			if q >= 2 and wow_frame < 0.0:
				wow_frame = float(frame) * DT
				wow_item = id
				wow_zone = area_now
				dungeons_before_wow = dungeons
				print("  ВАУ-ЛУТ: %s (качество %d) на %.1f с, зона %s, подземелий до него %d" % [
						id, q, wow_frame, area_now, dungeons])
		gear_prev = gear.size()
	chests_prev = (GameState.get("chests_used") as Array).size()
	var gold: int = int(GameState.get("gold"))
	if gold > gold_prev:
		gold_total += gold - gold_prev
	gold_prev = gold
	var lvl := int(GameState.get("level"))
	if lvl > levels:
		levels = lvl


func _kind_of(e: Node) -> String:
	var scr: Variant = e.get_script()
	var p := "нет_скрипта"
	if scr != null:
		p = _s((scr as Resource).resource_path).get_file().get_basename()
	var kk := _s(e.get("kill_kind"))
	if kk == "":
		kk = "обычный"
	return p + "/" + kk


func _walk_clock() -> void:
	var pos: Vector2 = player.global_position
	var moved: float = last_pos.distance_to(pos)
	if moved > 0.03:
		last_pos = pos
		_add(z_walk_px, area_now, moved)
		# в «чистую ходьбу» идут только кадры настоящей езды (>0.3 px/кадр = 18 px/с):
		# иначе дрожь у стены превращалась минуты ходьбы (243 с «ходьбы» на 4,7 тыс. px)
		if moved > 0.3 and engaged_now.is_empty():
			t_walk_pure += DT
	if moved > 0.3:
		# 0.3 px/кадр = 18 px/с: герой реально едет, а не дрожит на месте
		last_moved_frame = frame
	# намерение идти = хоть одна ось зажата; если при этом герой не едет, он
	# уткнулся: считаем застревание НЕЗАВИСИМО от наличия цели (иначе слепая
	# точка без цели превращала бы простояние в «тихую прогулку»)
	# t42: намерение идём берём из РЕАЛЬНОГО состояния ввода, а не из своей
	# бухгалтерии held_moves: игра и ClickMove при отмене снимают действия сами,
	# и на устаревшей бухгалтерии прошлый пакет писал «встанку» посреди свободной
	# клетки (проверено t42: точка (90.6, 346.1) свободна в 6 направлениях).
	var intends := false
	for a in held_moves.keys():
		if Input.is_action_pressed(String(a)):
			intends = true
	if _cm_driving():
		intends = true
	if intends and moved < 0.06 and frame > unstick_until:
		stuck_fr += 1
	else:
		stuck_fr = 0
	if stuck_fr > 25:
		stuck_fr = 0
		retries += 1
		t_stuck += 0.5
		# t42: прежний stuck_sec не трогаем (с ним снята база t39), но заводим
		# раздельные корзины: геометрическая встанка (ввод реально зажат, локов
		# нет, герой не едет) против «мешает состояние/планирование».
		if GameState.input_locked:
			t_stuck_plan += 0.5
		else:
			t_stuck_geom += 0.5
		print("  [застревание] к=%d поз=%s путь=%d/%d следующая=%s план_игры=%d/%d перекладок_игры=%d retries=%d цель=%s" % [
				frame, _s(player.global_position), path_idx, path_cells.size(),
				_s(path_cells[path_idx]) if path_idx < path_cells.size() else "нет",
				cm_path_idx, cm_path_n, cm_stall_rp_max, retries, goal_kind])
		_unstick()
	# t45-аддендум: предел вастдога поднят над ЗАКОННЫМ простоем у цели.
	# Максимальный hold в списке марша — 12 с = 720 кадров; прежний порог 600
	# кадров (10 с) срабатывал раньше конца законной задержки и записывал её
	# как «встанку». Учёт stuck_sec НЕ изменён (окна по 25 кадров), поэтому
	# браковка сравнима с базой; изменился только момент «цель сброшена».
	# t46-аддендум: отдельной ветки «боевой wall-pin» здесь нет намеренно —
	# после того как боевая ветка перестала жать клавиши под ведущим приказом,
	# ложных intends из боя больше не возникает (проверено дымовым прогоном ниже).
	if hold_until < 0 and intends and frame - last_moved_frame > 840:
		# десять секунд нажатых клавиш без хода: всё, это встанка
		last_moved_frame = frame
		_note("встанка у %s: цели сброшены, идём дальше" % _s(player.global_position))
		goal_kind = "нет цели"
		path_cells = []
		if _s(cfg.get("mode", "march")) == "march":
			_next_leg()


## t45-аддендум (27.11): прогон обязан начинаться с ЖИВЫми точками интереса.
## Разбор t45: на марш-прогоне 777 бот маршировал к поляне, чей флаг fw.glade_taken
## уже был снят сбором, — держание у пустой цели мерка записывала как геометрическую
## встанку. Снимаем только флаги сбора (*_taken), ничего больше.
func _clear_taken_flags(why: String) -> void:
	var cleared: Array = []
	for k in GameState.flags.keys():
		if String(k).ends_with("_taken") and int(GameState.flags[k]) != 0:
			GameState.flags[k] = 0
			cleared.append(String(k))
	if not cleared.is_empty():
		_note("мерка: сняты флаги сбора (%s): %s" % [why, ", ".join(cleared)])


func _add_count(d: Dictionary, k: String) -> void:
	d[k] = int(d.get(k, 0)) + 1


# ------------------------------------------------------------------ политики
func _policy() -> void:
	heal_cd = maxf(0.0, heal_cd - 1.0)
	interact_cd = maxf(0.0, interact_cd - 1.0)
	var mx: int = int(GameState.get("max_hp"))
	var frac := 1.0
	if mx > 0:
		frac = float(GameState.get("hp")) / float(mx)

	if flee_until > frame:
		_steer()
		_try_interact()
		return
	var crowd := engaged_now.size() >= 3
	if frac < FLEE_HP or (frac < 0.4 and crowd):
		if flee_until <= frame:
			decisions_fled += 1
			for id in engaged_now:
				recs[id]["forced_flee"] = true
			print("  ПОБЕГ на %.1f с: hp=%.0f%%, врагов в контакте=%d" % [
					float(frame) * DT, frac * 100.0, engaged_now.size()])
			_flee()
		_steer()
		_try_interact()
		return

	var tgt: Node = _nearest_enemy(ENGAGE_SHOOT_R)
	if frac < HEAL_HP and int(GameState.get("herbs")) > 0 and heal_cd <= 0.0 \
			and (tgt != null or not engaged_now.is_empty()):
		heal_cd = 90
		world.call("drink_potion")
		return

	# марш не даёт себя вязать: пока плечо молодое — дерёмся, после DISENGAGE_T
	# секунд игрок бьёт только тех, кто вплотную, и идёт по маршруту
	var march := _s(cfg.get("mode", "march")) == "march"
	var disengage := march and (leg < 0 or leg_t > DISENGAGE_T)
	if tgt != null and not disengage:
		var d: float = (tgt as Node2D).global_position.distance_to(player.global_position)
		if _cm_driving():
			# t46-аддендум (27.11): под ведущим приказом ClickMove свои клавиши
			# движения НЕ жмём — раньше боевая ветка тянула их сама и выходила из
			# _policy() до _steer(), который единственный отпускает синтез;
			# планировщик и я расходились во владении действием, герой вставал
			# (wall-pin), а мерка писала это в stuck_geom_sec. Сближение делает
			# игра, мы бьём то, что видим.
			_release_moves()
		elif d > MELEE_PX:
			_steer_to((tgt as Node2D).global_position)
		else:
			_release_moves()
		player.call("attack_at", (tgt as Node2D).global_position)
		_try_interact()
		return
	if tgt != null:
		var d2: float = (tgt as Node2D).global_position.distance_to(player.global_position)
		if d2 < 30.0:
			player.call("attack_at", (tgt as Node2D).global_position)
	if march:
		_march()
	else:
		_roam()
	_steer()
	_try_interact()


func _nearest_enemy(r: float) -> Node:
	var best: Node = null
	var bd := r
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D) or bool(e.get("dying")):
			continue
		var d: float = (e as Node2D).global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _flee() -> void:
	flee_until = frame + 210
	var best: Vector2 = player.global_position
	var bd := -1.0
	for i in 40:
		var c := _random_cell()
		if c == Vector2i.MIN:
			continue
		var w := _cell_world(c)
		var dmin := 1e9
		for id in engaged_now:
			var e: Node = recs[id]["node"]
			if is_instance_valid(e):
				dmin = minf(dmin, w.distance_to((e as Node2D).global_position))
		if dmin > bd:
			bd = dmin
			best = w
	goal_pos = best
	goal_kind = "побег"
	hold_until = -1
	_retarget_pos()


func _roam() -> void:
	if hold_until > 0:
		_hold_tick()
		return
	if goal_kind == "нет цели" or _arrived() or frame >= roam_until:
		# раз в минуту бродяга ищет выход: брод обязан пересекать зоны,
		# иначе «10 минут свободного брода» превращаются в 10 минут одной клетки
		if frame >= drift_at:
			drift_at = frame + 3600
			var ex := _find_interactable(["арка", "К карте мира", "портал", "ход", "пещер"])
			if ex != null:
				goal_kind = "брод: ищу выход"
				goal_pos = (ex as Node2D).global_position
				_retarget_pos()
				roam_until = frame + 900
				return
		var c := _random_cell()
		if c == Vector2i.MIN:
			goal_kind = "нет цели (карта пустая)"
			return
		goal_kind = "брод"
		goal_pos = _cell_world(c)
		_retarget_pos()
		roam_until = frame + 360 + rng.randi_range(0, 600)


# ------------------------------------------------------------------ маршрут
func _legs() -> Array:
	return [
		{"zone": "village", "cell": Vector2i(5, 21), "hold": 12.0,
			"note": "деревня: ПОИ «лес запад» (5,21) — Д2"},
		{"zone": "village", "hints": ["арка"], "into": "worldmap", "note": "деревня -> северная арка"},
		{"zone": "worldmap", "portal": "forest", "into": "loc_forest", "note": "карта мира -> портал чащи"},
		{"zone": "loc_forest", "dwell": 60.0, "note": "чаща: обход"},
		{"zone": "loc_forest", "hints": ["пещер", "лестниц"], "into": "cave", "note": "чаща -> пещера"},
		{"zone": "cave", "dwell": 60.0, "into": "loc_forest", "note": "пещера: обход"},
		{"zone": "loc_forest", "holes": true, "into": "mini_forest", "note": "чаща -> ход в микро-подземелье"},
		{"zone": "mini_forest", "dwell": 60.0, "into": "loc_forest", "note": "микро-подземелье: обход"},
		{"zone": "loc_forest", "hints": ["К карте мира"], "into": "worldmap", "note": "выход из чащи к карте"},
		{"zone": "worldmap", "hints": ["Пепелище"], "into": "ashen", "note": "карта мира -> Пепелище"},
		{"zone": "ashen", "dwell": 60.0, "into": "worldmap", "note": "Пепелище: обход"},
		{"zone": "worldmap", "hints": ["арка"], "into": "village", "note": "обратная арка в деревню"},
		{"zone": "village", "dwell": 40.0, "note": "деревня: обход"},
	]


func _march() -> void:
	var legs: Array = _legs()
	if leg < 0:
		leg = 0
		leg_t = 0.0
	if leg >= legs.size():
		_roam()
		return
	var l: Dictionary = legs[leg]
	var area := area_now
	if l.has("into") and area == _s(l.get("into")):
		# штатный переход случился — плечо закрыто, идём дальше (без программных костылей)
		_next_leg()
		if leg >= legs.size():
			_roam()
			return
		l = legs[leg]
		area = area_now
	if area != _s(l.get("zone")):
		if leg_t > 30.0:
			_prog_transition(l, "зона не та (%s), ждём transition %.0f с" % [area, leg_t])
		return
	if leg_t > LEG_CAP:
		_prog_transition(l, "плечо «%s» исчерпано по времени (%.0f с)" % [_s(l.get("note")), leg_t])
		return
	if hold_until > 0:
		_hold_tick()
		if hold_until < 0:
			# у цели постояли/взяли — плечо закрыто независимо от того, был ли у
			# него штатный переход (у ПОИ перехода нет: это точка интереса)
			_note("плечо «%s» пройдено, у цели простояли %s с" % [
					_s(l.get("note")), _s(l.get("hold"))])
			_next_leg()
		return
	if goal_kind == "нет цели" or _arrived():
		var t := _leg_target(l)
		if t != Vector2.ZERO:
			goal_kind = "плечо: " + _s(l.get("note"))
			goal_pos = t
			_retarget_pos()
		elif l.has("dwell") or l.has("hold"):
			goal_kind = "обход зоны"
			_retarget_cell(_random_cell())
		else:
			_prog_transition(l, "не нашли цель плеча «%s»" % _s(l.get("note")))
			return
	if _arrived() and l.has("hold") and hold_until < 0:
		hold_until = frame + int(float(l.get("hold")) / DT)
		goal_kind = "ждём у цели: " + _s(l.get("note"))
		return
	if _arrived() and l.has("dwell"):
		goal_kind = "обход зоны"
		_retarget_cell(_random_cell())


func _leg_target(l: Dictionary) -> Vector2:
	if l.has("cell"):
		var c: Vector2i = l["cell"]
		return _cell_world(c)
	if l.has("portal"):
		var key := _s(l.get("portal"))
		var wm: Node = world.get("worldmap_grid")
		if wm != null:
			var pn: Variant = wm.get("portal_nodes")
			if typeof(pn) == TYPE_DICTIONARY and (pn as Dictionary).has(key):
				var nd: Node = (pn as Dictionary)[key]
				if is_instance_valid(nd):
					return (nd as Node2D).global_position
			var pc: Variant = OW.PORTAL_CELLS.get(key, null)
			if pc != null and wm.has_method("tile_to_world"):
				return Vector2(wm.call("tile_to_world", pc as Vector2i)) + _zone_base()
	if l.has("holes"):
		var b := area_now.substr(4)
		var holes: Variant = world.get("mini_holes")
		if typeof(holes) == TYPE_DICTIONARY and (holes as Dictionary).has(b):
			var h: Node = (holes as Dictionary)[b]
			if is_instance_valid(h):
				return (h as Node2D).global_position
	if l.has("hints"):
		var nd2 := _find_interactable(l["hints"] as Array)
		if nd2 != null:
			return (nd2 as Node2D).global_position
		if area_now == "cave":
			var dz: Node = world.get("dungeon_zone")
			if dz != null and dz.get("stairs_node") != null:
				return (dz.get("stairs_node") as Node2D).global_position
		if area_now == "ashen":
			var ag: Node = world.get("ashen_grid")
			if ag != null and ag.get("portal_node") != null:
				return (ag.get("portal_node") as Node2D).global_position
	return Vector2.ZERO


func _next_leg() -> void:
	leg += 1
	leg_max = maxi(leg_max, leg)
	leg_t = 0.0
	hold_until = -1
	goal_kind = "нет цели"


func _prog_transition(l: Dictionary, why: String) -> void:
	var into := _s(l.get("into"))
	if into == "":
		goal_kind = "обход зоны"
		_retarget_cell(_random_cell())
		_note(why + " — дальше бродим здесь")
		_next_leg()
		return
	var called := ""
	if into == "worldmap":
		if world.has_method("exit_location"):
			world.call("exit_location")
			called = "exit_location()"
		elif world.has_method("apply_area"):
			world.call("apply_area", "worldmap")
			called = "apply_area(worldmap)"
	elif into.begins_with("loc_"):
		world.call("enter_location", into.substr(4))
		called = "enter_location(%s)" % into.substr(4)
	elif into == "cave":
		world.call("enter_cave")
		called = "enter_cave()"
	elif into.begins_with("mini_"):
		world.call("enter_mini", into.substr(5))
		called = "enter_mini(%s)" % into.substr(5)
	elif into == "ashen":
		world.call("enter_ashen")
		called = "enter_ashen()"
	elif into == "village":
		world.call("apply_area", "village")
		called = "apply_area(village)"
	_note("%s — программный переход %s" % [why, called])
	_next_leg()


func _find_interactable(keys: Array) -> Node:
	# ищем БЛИЖАЙШИЙ интерактор с нужной подсказкой и только внутри текущей
	# сетки: чужие зоны живут на других «этажах» (кратных 4800), но узлы их
	# живые, поэтому близость + попадание в клеточное поле обязательны
	if world == null or player == null:
		return null
	var gnode := _grid_node()
	var gw := 0
	var gh := 0
	if gnode != null:
		gw = int(gnode.get("map_w"))
		gh = int(gnode.get("map_h"))
	var best: Node = null
	var bd := 1e9
	var stack: Array = [world]
	var guard := 0
	while not stack.is_empty() and guard < 30000:
		guard += 1
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node2D) or not n.has_method("get_hint"):
			continue
		var h := _s(n.call("get_hint")).to_lower()
		if h == "":
			continue
		var hit := false
		for k in keys:
			if h.contains(_s(k).to_lower()):
				hit = true
				break
		if not hit:
			continue
		var p: Vector2 = (n as Node2D).global_position
		var d: float = p.distance_to(player.global_position)
		if d > 2600.0 or d >= bd:
			continue
		if gnode != null and gw > 0:
			var rel := p - _zone_base()
			var cc := Vector2i(int(floor(rel.x / 16.0)), int(floor(rel.y / 16.0)))
			if cc.x < 0 or cc.y < 0 or cc.x >= gw or cc.y >= gh:
				continue
		best = n
		bd = d
	return best


func _note(s: String) -> void:
	leg_notes.append([frame, s])
	print("  ~ %s" % s)


# ------------------------------------------------------------------ сетка/путь
func _grid_node() -> Node:
	if area_now == "village":
		return world
	if area_now == "cave":
		return world.get("dungeon_zone")
	if area_now == "ashen":
		return world.get("ashen_grid")
	if area_now == "worldmap":
		return world.get("worldmap_grid")
	if area_now.begins_with("mini_"):
		return (world.get("mini_grids") as Dictionary).get(area_now.substr(5), null)
	if area_now.begins_with("loc_"):
		return (world.get("biome_grids") as Dictionary).get(area_now.substr(4), null)
	return null


func _zone_base() -> Vector2:
	if area_now == "cave":
		return Vector2(0.0, 4800.0)
	if area_now == "ashen":
		return Vector2(0.0, 9600.0)
	if area_now == "worldmap":
		return Vector2(0.0, float(OW.WM_OFFSET_Y))
	if area_now.begins_with("loc_"):
		return Vector2(0.0, float(OW.LOC_OFFSET_Y.get(area_now.substr(4), 0)))
	if area_now.begins_with("mini_"):
		var mg: Node = (world.get("mini_grids") as Dictionary).get(area_now.substr(5), null)
		if mg != null and mg.get_parent() != null:
			return (mg.get_parent() as Node2D).global_position
	return Vector2.ZERO


func _dims() -> Vector2i:
	var w: Node = _grid_node()
	if w == null:
		return Vector2i.ZERO
	return Vector2i(int(w.get("map_w")), int(w.get("map_h")))


func _walkable_f() -> Callable:
	# единый доступ к проходимости: у деревни он приватный _village_walkable,
	# у всех прочих зон — публичный cell_walkable
	if area_now == "village":
		return Callable(world, "_village_walkable")
	var w: Node = _grid_node()
	if w != null and w.has_method("cell_walkable"):
		return Callable(w, "cell_walkable")
	return Callable()


func _cell_world(c: Vector2i) -> Vector2:
	var w: Node = _grid_node()
	if w == null or not w.has_method("tile_to_world"):
		return Vector2.ZERO
	return Vector2(w.call("tile_to_world", c)) + _zone_base()


func _hero_cell() -> Vector2i:
	var lp: Vector2 = player.global_position - _zone_base()
	return Vector2i(int(floor(lp.x / 16.0)), int(floor(lp.y / 16.0)))


func _random_cell() -> Vector2i:
	var dm := _dims()
	var walk := _walkable_f()
	if dm.x < 4 or dm.y < 4 or not walk.is_valid():
		return Vector2i.MIN
	for i in 60:
		var c := Vector2i(rng.randi_range(1, dm.x - 2), rng.randi_range(1, dm.y - 2))
		if bool(walk.call(c)):
			return c
	return Vector2i.MIN


func _retarget_cell(c: Vector2i) -> void:
	if c == Vector2i.MIN:
		goal_kind = "нет цели (карта пустая)"
		return
	goal_pos = _cell_world(c)
	_retarget_pos()


func _cm() -> Node:
	var cm: Variant = CM.I
	if cm == null or not is_instance_valid(cm as Node):
		return null
	return cm as Node


func _cm_stats() -> void:
	# t45-аддендум: снимаем внутренности плана игры в свои счётчики каждый кадр.
	cm_path_n = 0
	cm_path_idx = 0
	var cm := _cm()
	if cm == null:
		return
	var p: Array = cm.get("_path") as Array
	cm_path_n = p.size()
	cm_path_idx = int(cm.get("_idx"))
	cm_stall_rp_max = maxi(cm_stall_rp_max, int(cm.get("_stall_rp")))


func _cm_driving() -> bool:
	var cm := _cm()
	if cm == null:
		return false
	var p: Array = cm.get("_path") as Array
	var i := int(cm.get("_idx"))
	return i < p.size()


func _retarget_pos() -> void:
	if goal_pos == Vector2.ZERO:
		goal_kind = "нет цели"
		path_cells = []
		return
	ordered = false
	# сначала пробуем штатный приказ игрока мышью (ПКМ): pathfinding, перекладку
	# и анти-встанку делает сама игра — тот же канал, что у живого человека.
	# ВАЖНО: order_to возвращает true и когда A* игры не дошёл («Туда не дойти.»),
	# поэтому верим только если приказ реально вылился в живой путь
	var cm := _cm()
	if cm != null and bool(cm.call("order_to", goal_pos)) and _cm_driving():
		ordered = true
		orders += 1
		path_cells = []
		return
	path_cells = _bfs(goal_pos)
	if path_cells.is_empty():
		bfs_fail += 1
	path_idx = 0


func _bfs(to_world: Vector2) -> Array:
	var dm := _dims()
	var walk := _walkable_f()
	if dm.x <= 0 or dm.y <= 0 or not walk.is_valid():
		return []
	var gw := dm.x
	var gh := dm.y
	var base := _zone_base()
	var from_cell := _hero_cell()
	var to_cell := Vector2i(int(floor((to_world.x - base.x) / 16.0)),
			int(floor((to_world.y - base.y) / 16.0)))
	if from_cell.x < 0 or from_cell.y < 0 or from_cell.x >= gw or from_cell.y >= gh:
		return []
	if not bool(walk.call(from_cell)):
		# герой стоит на декорации/цвете: стартуем с ближайшей проходимой клетки
		var found_start := false
		for r in range(1, 4):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var cand: Vector2i = from_cell + Vector2i(dx, dy)
					if cand.x < 0 or cand.y < 0 or cand.x >= gw or cand.y >= gh:
						continue
					if bool(walk.call(cand)):
						from_cell = cand
						found_start = true
						break
				if found_start:
					break
			if found_start:
				break
		if not found_start:
			return []
	var prev := {}
	var q := [from_cell]
	prev[from_cell] = from_cell
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var found := false
	while head < q.size() and q.size() < 26000:
		var c: Vector2i = q[head]
		head += 1
		if c == to_cell:
			found = true
			break
		for d in dirs:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= gw or n.y >= gh:
				continue
			if prev.has(n) or not bool(walk.call(n)):
				continue
			prev[n] = c
			q.append(n)
	if not found:
		var best := from_cell
		var bd := 1e18
		for k in prev.keys():
			var dd: float = (k as Vector2i).distance_to(to_cell)
			if dd < bd:
				bd = dd
				best = k
		if bd > 14.0:
			return []
		return _trace(prev, best, from_cell, base)
	return _trace(prev, to_cell, from_cell, base)


func _trace(prev: Dictionary, from_tail: Vector2i, start: Vector2i, base: Vector2) -> Array:
	var out := []
	var cur := from_tail
	var guard := 0
	while cur != start and out.size() < 4000 and guard < 4000:
		guard += 1
		out.push_front(Vector2(base.x + float(cur.x) * 16.0 + 8.0,
				base.y + float(cur.y) * 16.0 + 8.0))
		if not prev.has(cur):
			break
		cur = prev[cur]
	return out


func _arrived() -> bool:
	if goal_pos == Vector2.ZERO or player == null:
		return false
	var d: float = player.global_position.distance_to(goal_pos)
	if d < 12.0:
		return true
	if ordered and not _cm_driving():
		# игра сама сняла приказ (своя анти-встанка, «Туда не дойти.», конец пути).
		# Считаем прибытием, только если до цели оставалось рукой подать, иначе это
		# недосыл — см. _order_pump(): иначе марш рисует прогресс на пустом месте
		return d < 40.0
	return not path_cells.is_empty() and path_idx >= path_cells.size()


func _next_waypoint() -> Vector2:
	while path_idx < path_cells.size():
		var p: Vector2 = path_cells[path_idx]
		if player.global_position.distance_to(p) < 9.0:
			path_idx += 1
			wp_hits += 1
			continue
		return p
	return Vector2.ZERO


func _order_pump() -> void:
	if goal_pos == Vector2.ZERO or player == null:
		return
	if _cm_driving():
		order_retry = 0
		return
	if not ordered:
		# свой BFS: там перекладку делает _walk_clock/_unstick
		return
	if player.global_position.distance_to(goal_pos) < 40.0:
		order_retry = 0
		return
	if frame < reissue_at:
		return
	reissue_at = frame + 240
	order_retry += 1
	if order_retry < 3:
		_retarget_pos()
		return
	order_retry = 0
	order_fails += 1
	_note("не дошли до «%s»: игра трижды сняла приказ у %s" % [goal_kind, _s(goal_pos)])
	if _s(cfg.get("mode", "march")) == "march":
		_next_leg()
	else:
		_retarget_cell(_random_cell())


func _steer() -> void:
	if _cm_driving():
		# приказ исполняет игра: свои клавиши отпускаем, иначе тянем вразнобой
		cm_frames += 1
		_release_moves()
		return
	if frame < unstick_until and unstick_dir != Vector2.ZERO:
		_axis_press(unstick_dir)
		return
	var wp := _next_waypoint()
	if wp != Vector2.ZERO:
		_steer_to(wp)
		return
	if goal_pos != Vector2.ZERO:
		_steer_to(goal_pos)
		return
	_release_moves()


func _steer_to(p: Vector2) -> void:
	if p == Vector2.ZERO:
		return
	_axis_press((p - player.global_position).normalized())


func _axis_press(d: Vector2) -> void:
	# порог маленький нарочно: при 0.3 герой упирался в стену, потому что
	# «малая» ось (0.06 от нормали) не нажималась и скользить было нечем
	if d.length() > 0.05:
		last_dir = d.normalized()
	var want := {"move_left": d.x <= -0.06, "move_right": d.x >= 0.06,
			"move_up": d.y <= -0.06, "move_down": d.y >= 0.06}
	for a in want.keys():
		if _synth_holds(String(a)):
			# t46-аддендум: действие занято синтезом ClickMove — не лезем ни нажать,
			# ни отпустить; свою бухгалтерию помечаем свободной, чтобы stale-флаг
			# позже не отпустил то, что держит планировщик.
			held_moves[a] = false
			continue
		if bool(want[a]) and not bool(held_moves.get(a, false)):
			Input.action_press(a)
			held_moves[a] = true
		elif not bool(want[a]) and bool(held_moves.get(a, false)):
			Input.action_release(a)
			held_moves[a] = false


func _synth_holds(a: String) -> bool:
	# t46-аддендум: держит ли действие сам планировщик (ClickMove._held).
	var cm := _cm()
	if cm == null:
		return false
	var h: Dictionary = cm.get("_held") as Dictionary
	if h.is_empty():
		return false
	return bool(h.get(a, false))


func _release_moves() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		if _synth_holds(a):
			# t46-аддендум: занято синтезом — отпускает тоже он, не мы.
			held_moves[a] = false
			continue
		if bool(held_moves.get(a, false)):
			Input.action_release(a)
		held_moves[a] = false


func _unstick() -> void:
	# упор: шагаем в перпендикуляр к тому направлению, куда упирались (стена
	# обычно вдоль него), знак выбирает сид; если направления нет — случайный
	if last_dir != Vector2.ZERO:
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		unstick_dir = Vector2(-last_dir.y, last_dir.x) * sgn
		if unstick_dir.length() < 0.2:
			unstick_dir = Vector2.RIGHT
	else:
		unstick_dir = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	unstick_until = frame + 20
	# точок, до которого не дошли, не ждём: перешагнули и идём к следующему
	if not path_cells.is_empty() and path_idx < path_cells.size():
		path_idx += 1
	# каждое третье застревание — путь устарел, перекладываем от текущей клетки
	if retries % 3 == 0 and goal_pos != Vector2.ZERO:
		_retarget_pos()
	if retries > 8:
		goal_kind = "нет цели"
		retries = 0


func _hold_tick() -> void:
	if hold_until < 0:
		return
	if frame >= hold_until:
		hold_until = -1
		return
	_axis_press(Vector2(cos(float(frame) * 0.06), sin(float(frame) * 0.06)))
	_try_interact()


func _try_interact() -> void:
	if interact_cd > 0.0:
		return
	var near: Array = world.get("near") as Array
	if near.is_empty():
		return
	var obj: Node = near[0]
	if obj == null or not is_instance_valid(obj) or not obj.has_method("try_interact"):
		return
	interact_cd = 24
	interact_presses += 1
	_add_count(z_interacts, area_now)
	# ровно то же действие, что ветка E в world._unhandled_input: near[0].try_interact()
	obj.call("try_interact")


# ------------------------------------------------------------------ итог
func _result() -> Dictionary:
	var minutes := t_total / 60.0
	var threats := 0
	var fs := 0
	var fh := 0
	var ff := 0
	var met := 0
	for id in recs.keys():
		var rec: Dictionary = recs[id]
		if not bool(rec["counted"]):
			continue
		met += 1
		if bool(rec["first_strike"]) or bool(rec["forced_heal"]) or bool(rec["forced_flee"]):
			threats += 1
		if bool(rec["first_strike"]):
			fs += 1
		if bool(rec["forced_heal"]):
			fh += 1
		if bool(rec["forced_flee"]):
			ff += 1
	var zones_out := {}
	for z in z_t.keys():
		var zs := float(z_t[z])
		zones_out[z] = {
			"sec": _r2(zs),
			"contacts": int(z_contacts.get(z, 0)),
			"contacts_per_min": _r2(float(z_contacts.get(z, 0)) / maxf(0.05, zs / 60.0)),
			"dry_max_sec": _r2(float(z_dry_max.get(z, 0.0))),
			"dry_sec": _r2(float(z_dry_cur.get(z, 0.0))),
			"enemies_met": int(z_enemies.get(z, 0)),
			"dmg_taken": int(z_dmg_taken.get(z, 0)),
			"dmg_dealt": int(z_dmg_dealt.get(z, 0)),
			"loot_items": int(z_loot.get(z, 0)),
			"heals": int(z_heals.get(z, 0)),
			"interacts": int(z_interacts.get(z, 0)),
			"walk_px": _r2(float(z_walk_px.get(z, 0.0))),
		}
	return {
		"cfg": cfg,
		"frames": frame,
		"sec_total": _r2(t_total),
		"minutes": _r2(minutes),
		"walk_pure_min": _r2(t_walk_pure / 60.0),
		"locked_sec": _r2(t_locked),
		"dialog_sec": _r2(t_dialog),
		"modal_sec": _r2(t_modal),
		"lock_other_sec": _r2(t_lock_other),
		"lock_shop_sec": _r2(t_lock_shop),
		"lock_inv_sec": _r2(t_lock_inv),
		"lock_board_sec": _r2(t_lock_board),
		"lock_summary_sec": _r2(t_lock_summary),
		"panels_closed": panels_closed,
		"cm_stall_rp_max": cm_stall_rp_max,
		"wp_hits": wp_hits,
		"stuck_sec": _r2(t_stuck),
		# t42: прежняя метрика осталась (с ней снята база), рядом — честные корзины
		"stuck_geom_sec": _r2(t_stuck_geom),
		"stuck_lock_sec": _r2(t_stuck_plan),
		"in_contact_sec": _r2(t_in_contact),
		"dry_max_sec": _r2(maxf(dry_max, cur_dry)),
		"dry_sum_sec": _r2(dry_sum + cur_dry),
		"contact_events": contact_events,
		"encounter_groups": encounter_groups,
		"contacts_per_min": _r2(float(contact_events) / maxf(0.05, minutes)),
		"enemies_met": met,
		"threats": threats,
		"threat_share": _r3(float(threats) / float(maxi(1, met))),
		"first_strike": fs,
		"forced_heal": fh,
		"forced_flee": ff,
		"deaths": deaths,
		"death_log": death_log,
		"decisions": decisions,
		"bets": bets,
		"decisions_fled": decisions_fled,
		"dmg_taken": dmg_taken,
		"dmg_dealt": dmg_dealt,
		"kills": kills,
		"levels": levels,
		"gold_total": gold_total,
		"chests": chests_prev,
		"gear_items": gear_prev,
		"best_quality": best_quality,
		"wow_sec": _r2(wow_frame),
		"wow_item": wow_item,
		"wow_zone": wow_zone,
		"dungeons": dungeons,
		"dungeons_before_wow": dungeons_before_wow,
		"interacts": interact_presses,
		"retries": retries,
		"bfs_fail": bfs_fail,
		"orders": orders,
		"order_fails": order_fails,
		"cm_frames": cm_frames,
		"leg_max": leg_max,
		"areas": area_log,
		"zones": zones_out,
		"notes": leg_notes,
	}


func _finish() -> void:
	var res := _result()
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(res, "  "))
		f.close()
	var l1 := "=== ИТОГ %.0f с: контактов %d (%.2f/мин), стычек %d, врагов встречено %d, угроз %d (доля %.3f), смертей %d" % [
			res["sec_total"], res["contact_events"], res["contacts_per_min"],
			res["encounter_groups"], res["enemies_met"], res["threats"],
			res["threat_share"], res["deaths"]]
	var l2 := "    решений драться/бежать %d (ставочных %d, побегами %d); сухой кусок макс %.0f с, без контакта %.0f с, чистой ходьбы %.2f мин, в диалогах/локах %.0f с" % [
			res["decisions"], res["bets"], res["decisions_fled"], res["dry_max_sec"],
			res["dry_sum_sec"], res["walk_pure_min"], res["locked_sec"]]
	var l3 := "    вау-лут: %s на %.1f с (зона %s, подземелий до него %d), лучшее качество %d, вещей %d, сундуков %d" % [
			wow_item if wow_item != "" else "НЕ БЫЛО", wow_frame,
			wow_zone if wow_zone != "" else "-", dungeons_before_wow,
			best_quality, res["gear_items"], res["chests"]]
	var l4 := "    урона получил %d, нанёс %d, убил %d, уровней %d, золота +%d, тычков E %d, застряний %d" % [
			res["dmg_taken"], res["dmg_dealt"], res["kills"], res["levels"],
			res["gold_total"], res["interacts"], res["retries"]]
	print(l1)
	print(l2)
	print(l3)
	print(l4)
	var zl := []
	for z in res["zones"].keys():
		var zd: Dictionary = res["zones"][z]
		zl.append("    зона %-13s %6.1f с | конт. %3d (%5.2f/мин) | сух.макс %6.1f с | врагов %3d | урон %4d/%4d | лут %d | E %d" % [
				z, zd["sec"], zd["contacts"], zd["contacts_per_min"], zd["dry_max_sec"],
				zd["enemies_met"], zd["dmg_taken"], zd["dmg_dealt"], zd["loot_items"],
				zd["interacts"]])
	zl.sort()
	for s in zl:
		print(s)
	print("===CENSUS_DONE===")
	await _fr(2)
	get_tree().quit()
