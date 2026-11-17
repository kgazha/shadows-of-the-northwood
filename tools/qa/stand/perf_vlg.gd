extends Node2D
## g21b (t65) — измеритель производительности для вердикта «масштаб фазы 1».
## Задача требует: генерация карты и полный кадр не хуже ×1,3 к базе (замер
## харнессом), ноль новых аллокаций за кадр. База — коммит 9dec1db (карта
## 48×30), сравнивается с HEAD стенда (59×37). Запуск (из pixel-rpg, файлы
## скопированы в корень, как делает tools/qa/run_all.js):
##   godot --headless --path pixel-rpg res://perf_vlg.tscn
## Метрики (одна постройка мира на процесс; снаружи прогон повторяется,
## минимум/медиану считает вызывающий скрипт):
##  • gen_us   — время add_child(main) = весь synchronous build мира (тайлмап,
##               коллайдеры, POI, свай-регистры);
##  • frame_us — медиана Performance.TIME_PROCESS (мкс) за 240 кадров живого
##               мира после прогрева: стоимость полного кадра на стороне
##               движка (физика, скрипты, рассылка canvas-ивентов);
##  • obj_delta — узлы дерева (+_count_nodes) за 60 кадров прогрева после
##               замера: ноль новых объектов за кадр (аллокационный след).
const MAIN_SCENE := "res://scenes/main.tscn"

func _ready() -> void:
	GameState.class_id = "warrior"
	GameState.seen_intro = true
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.run_seed = 42
	var w: Node2D = load(MAIN_SCENE).instantiate()
	var t0 := Time.get_ticks_usec()
	add_child(w)
	var gen_us := Time.get_ticks_usec() - t0
	for i in 60:
		await get_tree().process_frame
	var frames: Array = []
	for i in 240:
		await get_tree().process_frame
		frames.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)
	var o0 := _count_nodes(get_tree().root)
	for i in 60:
		await get_tree().process_frame
	var o1 := _count_nodes(get_tree().root)
	frames.sort()
	var med: float = float(frames[int(frames.size() / 2)])
	print("QA_PERF_RESULT gen_us=%d frame_us=%.1f obj_delta=%d map=%dx%d" % [
		gen_us, med, o1 - o0, int(w.map_w), int(w.map_h)])
	get_tree().quit(0)

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
