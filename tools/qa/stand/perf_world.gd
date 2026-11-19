extends Node2D
## t3 «Мир v1» — перф-стенд допуска ×1,3 (контракт perf_мира).
## Метод v2 (t10, 19.11): ДО пула — полноценный warm-up-раунд всех четырёх зон
## без замеров (240 кадров на зону). Причина: ленивая сборка (t3) платит хвостом
## при ПЕРВОМ switch зоны (worldmap строит ~171мс, снежная ещё и спавнит мобов);
## в v1 этот хвост попадал в раунд 1 того же пула и тянул медиану (worldmap/снег
## по 31-33мс против честных 18.8к мкс; воспроизв. ratio 1.52-1.61 на 57c068f).
## Метрика без изменений: кадры под обычным пейсингом 60 fps, метрика — МЕДИАНА
## Performance.TIME_PROCESS по пулу прогретых раундов [деревня, мир, снег, замок].
## t10 интерливинг v3: 6 раундов × 60 кадров на зону (пул те же 360): короткие
## чередующиеся сегменты снимают чувствительность к дрейфу внешней нагрузки —
## любой всплеск CPU накрывает все четыре зоны в одном окне равными долями
## (120-кадровые сегменты давали snow +9мкс, когда соседний сегмент деревни
## ловил тишину: ratio 1.42 при прогретых зонах), а медиана пула съедает 1-2
## испорченных сегмента из шести. Медиана по пулу, а не min/P10: min и перцентиль
## «читаются» первыми тёплыми кадрами (замерено: деревенский P10=3.0мс против
## честной медианы 14.6 — warm-up хвост). Медиана пула нечитаема и сравнивает
## зоны поштучно в одном процессе. Сравниваются зоны ОДНОГО мира: база — кадр
## деревни (канон). Warm-up греет не только генератор: apply_area не сбрасывает
## собранные зоны (switch только меняет active_area/видимость), поэтому
## ленивые сборки и первый спавн мобов целиком остаются за мерной частью.
## Запуск (файл в корень копии проекта, как делает run_all.js):
##   godot --headless --path <copy> res://perf_world.tscn
## Формат: "QA_PERFWORLD x/y" (manifest mode "xy").
const MAIN_SCENE := "res://scenes/main.tscn"
const N := 60
const ROUNDS := 6
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
	var zones: Array = ["village", "worldmap", "loc_snow", "loc_castle"]
	# warm-up-раунд (t10): полный круг без замеров, 240 кадров на зону — ленивые
	# сборки worldmap/локаций, первый спавн мобов и все первичные аллокации
	# уходят сюда, в пул не попадают.
	for z in zones:
		w.apply_area(z)
		for i in 240:
			await get_tree().process_frame
	var pool := {"village": [], "worldmap": [], "snow": [], "castle": []}
	var keys := {"village": "village", "worldmap": "worldmap",
			"loc_snow": "snow", "loc_castle": "castle"}
	for rd in ROUNDS:
		for z in zones:
			w.apply_area(z)
			await get_tree().process_frame
			await _harvest(pool[keys[z]])
	# последний раунд завершаем в деревне — чистое состояние при выходе
	w.apply_area("village")
	var pv: float = _med(pool["village"])
	var pm: float = _med(pool["worldmap"])
	var ps: float = _med(pool["snow"])
	var pc: float = _med(pool["castle"])
	print("QA_PERFWORLD med village=%.1f worldmap=%.1f snow=%.1f castle=%.1f (мкс, медиана пула, %d кадров на зону, warm-up v2)" % [
			pv, pm, ps, pc, N * ROUNDS])
	var worst: float = maxf(pm, maxf(ps, pc))
	var r: float = worst / maxf(pv, 0.5)
	chk(r <= TOLERANCE, "PERF.x кадр худшей новой зоны к деревне = %.2f <= %.1f" % [r, TOLERANCE])
	chk(pm < 1e11 and ps < 1e11 and pc < 1e11, "PERF.x замеры состоялись (зоны живые)")
	print("QA_PERFWORLD %d/%d" % [pass_n, total])
	get_tree().quit(0 if pass_n == total else 1)
