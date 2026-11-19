extends Node2D
## t3 «Мир v1» — перф-стенд допуска ×1,3 (контракт perf_мира).
## Метод: кадры под обычным пейсингом 60 fps; метрика — МЕДИАНА
## Performance.TIME_PROCESS по всем кадрам трёх переплетённых раундов
## [деревня, мир, снег, замок] (3×120 на зону). Медиана по пулу, а не min/P10:
## min и перцентиль «читаются» первыми тёплыми кадрами деревни (замерено:
## деревенский P10=3.0мс против честной медианы 14.6 — warm-up хвост).
## Медиана пула нечитаема и сравнивает зоны поштучно в одном процессе.
## Сравниваются зоны ОДНОГО мира: база — кадр деревни (канон).
## Запуск (файл в корень копии проекта, как делает run_all.js):
##   godot --headless --path <copy> res://perf_world.tscn
## Формат: "QA_PERFWORLD x/y" (manifest mode "xy").
const MAIN_SCENE := "res://scenes/main.tscn"
const N := 120
const ROUNDS := 3
const TOLERANCE := 1.3

var total := 0
var pass_n := 0

func chk(cond: bool, name: String) -> void:
	total += 1
	if cond:
		pass_n += 1
	print("%s %s" % ["PASS" if cond else "FAIL", name])

func _harvest(arr: Array) -> void:
	for i in N:
		await get_tree().process_frame
		arr.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)

func _med(arr: Array) -> float:
	if arr.is_empty():
		return 1e12
	var s: Array = arr.duplicate()
	s.sort()
	return float(s[int(s.size() / 2)])

func _ready() -> void:
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.run_seed = 42
	var w: Node2D = load(MAIN_SCENE).instantiate()
	add_child(w)
	for i in 90:  # прогрев JIT/аллокаторов
		await get_tree().process_frame
	var pool := {"village": [], "worldmap": [], "snow": [], "castle": []}
	for rd in ROUNDS:
		w.apply_area("village")
		await get_tree().process_frame
		await _harvest(pool["village"])
		w.apply_area("worldmap")
		await get_tree().process_frame
		await _harvest(pool["worldmap"])
		w.apply_area("loc_snow")
		await get_tree().process_frame
		await _harvest(pool["snow"])
		w.apply_area("loc_castle")
		await get_tree().process_frame
		await _harvest(pool["castle"])
	# последний раунд завершаем в деревне — чистое состояние при выходе
	w.apply_area("village")
	var pv: float = _med(pool["village"])
	var pm: float = _med(pool["worldmap"])
	var ps: float = _med(pool["snow"])
	var pc: float = _med(pool["castle"])
	print("QA_PERFWORLD med village=%.1f worldmap=%.1f snow=%.1f castle=%.1f (мкс, медиана пула, %d кадров на зону)" % [
			pv, pm, ps, pc, N * ROUNDS])
	var worst: float = maxf(pm, maxf(ps, pc))
	var r: float = worst / maxf(pv, 0.5)
	chk(r <= TOLERANCE, "PERF.x кадр худшей новой зоны к деревне = %.2f <= %.1f" % [r, TOLERANCE])
	chk(pm < 1e11 and ps < 1e11 and pc < 1e11, "PERF.x замеры состоялись (зоны живые)")
	print("QA_PERFWORLD %d/%d" % [pass_n, total])
	get_tree().quit(0 if pass_n == total else 1)

