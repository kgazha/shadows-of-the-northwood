"""t33: зонд переходит на штатную ходьбу игры (ClickMove.order_to), BFS — запасной."""
import io

P = r"diag-t33/census_t33.gd"
s = io.open(P, encoding="utf-8").read()

# 1) предзагрузим класс ClickMove (статический синглтон I)
old = 'const OW := preload("res://scripts/open_world.gd")'
new = 'const OW := preload("res://scripts/open_world.gd")\nconst CM := preload("res://scripts/click_move.gd")'
assert old in s
s = s.replace(old, new, 1)

# 2) выдача приказа игре + запасной BFS
old2 = '''func _retarget_pos() -> void:
	if goal_pos == Vector2.ZERO:
		goal_kind = "нет цели"
		path_cells = []
		return
	path_cells = _bfs(goal_pos)
	if path_cells.is_empty():
		bfs_fail += 1
	path_idx = 0'''
new2 = '''func _cm() -> Node:
	var cm: Variant = CM.I
	if cm == null or not is_instance_valid(cm as Node):
		return null
	return cm as Node


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
	# и анти-встанку делает сама игра — тот же канал, что у живого человека
	var cm := _cm()
	if cm != null and bool(cm.call("order_to", goal_pos)):
		ordered = true
		path_cells = []
		return
	path_cells = _bfs(goal_pos)
	if path_cells.is_empty():
		bfs_fail += 1
	path_idx = 0'''
assert old2 in s
s = s.replace(old2, new2, 1)

# 3) var ordered
old3 = "var bfs_fail := 0"
new3 = "var bfs_fail := 0\nvar ordered := false\nvar orders := 0\nvar cm_frames := 0"
assert old3 in s
s = s.replace(old3, new3, 1)

# 4) счётчик приказов
old4 = """	if cm != null and bool(cm.call("order_to", goal_pos)):
		ordered = true
		path_cells = []
		return"""
new4 = """	if cm != null and bool(cm.call("order_to", goal_pos)):
		ordered = true
		orders += 1
		path_cells = []
		return"""
assert old4 in s
s = s.replace(old4, new4, 1)

# 5) руление: если ведёт игра — не мешаем
old5 = """func _steer() -> void:
	if frame < unstick_until and unstick_dir != Vector2.ZERO:
		_axis_press(unstick_dir)
		return"""
new5 = """func _steer() -> void:
	if _cm_driving():
		# приказ исполняет игра: свои клавиши отпускаем, иначе тянем вразнобой
		cm_frames += 1
		_release_moves()
		return
	if frame < unstick_until and unstick_dir != Vector2.ZERO:
		_axis_press(unstick_dir)
		return"""
assert old5 in s
s = s.replace(old5, new5, 1)

# 6) «пришли»: приказ игра считает выполненным, когда дошёл до цели или путь кончился
old6 = """func _arrived() -> bool:
	if goal_pos != Vector2.ZERO and player != null \\
			and player.global_position.distance_to(goal_pos) < 10.0:
		return true
	return not path_cells.is_empty() and path_idx >= path_cells.size()"""
new6 = """func _arrived() -> bool:
	if goal_pos != Vector2.ZERO and player != null \\
			and player.global_position.distance_to(goal_pos) < 12.0:
		return true
	if ordered and not _cm_driving():
		return true
	return not path_cells.is_empty() and path_idx >= path_cells.size()"""
assert old6 in s
s = s.replace(old6, new6, 1)

# 7) намерение идти учитывает приказ игры
old7 = """	var intends := false
	for a in held_moves.keys():
		if bool(held_moves[a]):
			intends = true"""
new7 = """	var intends := false
	for a in held_moves.keys():
		if bool(held_moves[a]):
			intends = true
	if _cm_driving():
		intends = true"""
assert old7 in s
s = s.replace(old7, new7, 1)

# 8) в итог
old8 = """		"bfs_fail": bfs_fail,"""
new8 = """		"bfs_fail": bfs_fail,
		"orders": orders,
		"cm_frames": cm_frames,"""
assert old8 in s
s = s.replace(old8, new8, 1)

# 9) трасса: показывать, кто ведёт
old9 = '''		print("  [бот] кадр %d зона=%s поз=%s цель=%s (%s) путь=%d/%d подсказок=%d hp=%d/%d вконтакте=%d" % [
				frame, area_now, _s(player.global_position), _s(goal_pos), goal_kind,
				path_idx, path_cells.size(), nr.size(), int(GameState.get("hp")),
				int(GameState.get("max_hp")), engaged_now.size()])'''
new9 = '''		print("  [бот] кадр %d зона=%s поз=%s цель=%s (%s) путь=%d/%d подсказок=%d hp=%d/%d вконтакте=%d кто_ведёт=%s" % [
				frame, area_now, _s(player.global_position), _s(goal_pos), goal_kind,
				path_idx, path_cells.size(), nr.size(), int(GameState.get("hp")),
				int(GameState.get("max_hp")), engaged_now.size(),
				"игра(ПКМ)" if _cm_driving() else ("приказ отдан" if ordered else "сам"))]'''
assert old9 in s
s = s.replace(old9, new9, 1)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("ходьба через штатный приказ игрока включена")
