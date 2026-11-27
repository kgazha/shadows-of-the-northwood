"""t33: финальные правки меры — честное «дошли/не дошли», чистая ходьба без дрожжи,
защита от освобождённых ссылок."""
import io

P = r"diag-t33/census_t33.gd"
s = io.open(P, encoding="utf-8").read()

# 1) падение на освобождённом враге (Godot 4 не даёт присвоить freed в тип Node)
old = """	for id in recs.keys():
		var rec: Dictionary = recs[id]
		var e: Node = rec["node"]
		if not is_instance_valid(e):
			continue"""
new = """	for id in recs.keys():
		var rec: Dictionary = recs[id]
		var e: Variant = rec["node"]
		if not (e is Node2D) or not is_instance_valid(e):
			continue"""
assert old in s, "освобождённая ссылка не найдена"
s = s.replace(old, new, 1)

# 2) «дошли»: приказ игры, который она sama сняла, прибытием не считается
old2 = """func _arrived() -> bool:
	if goal_pos != Vector2.ZERO and player != null \\
			and player.global_position.distance_to(goal_pos) < 12.0:
		return true
	if ordered and not _cm_driving():
		return true
	return not path_cells.is_empty() and path_idx >= path_cells.size()"""
new2 = """func _arrived() -> bool:
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
	return not path_cells.is_empty() and path_idx >= path_cells.size()"""
assert old2 in s, "_arrived не найден"
s = s.replace(old2, new2, 1)

# 3) переприказ: живой игрок жмёт ПКМ ещё раз, а не зачёркивает плечо
old3 = """func _steer() -> void:"""
new3 = """func _order_pump() -> void:
\tif goal_pos == Vector2.ZERO or player == null:
\t\treturn
\tif _cm_driving():
\t\torder_retry = 0
\t\treturn
\tif not ordered:
\t\t# свой BFS: там перекладку делает _walk_clock/_unstick
\t\treturn
\tif player.global_position.distance_to(goal_pos) < 40.0:
\t\torder_retry = 0
\t\treturn
\tif frame < reissue_at:
\t\treturn
\treissue_at = frame + 240
\torder_retry += 1
\tif order_retry < 3:
\t\t_retarget_pos()
\t\treturn
\torder_retry = 0
\torder_fails += 1
\t_note("не дошли до «%s»: игра трижды сняла приказ у %s" % [goal_kind, _s(goal_pos)])
\tif _s(cfg.get("mode", "march")) == "march":
\t\t_next_leg()
\telse:
\t\t_retarget_cell(_random_cell())


func _steer() -> void:"""
assert old3 in s, "_steer не найден"
s = s.replace(old3, new3, 1)

old4 = "var orders := 0"
new4 = "var orders := 0\nvar order_fails := 0\nvar order_retry := 0\nvar reissue_at := 0"
assert old4 in s
s = s.replace(old4, new4, 1)

old5 = """		"orders": orders,"""
new5 = """		"orders": orders,
		"order_fails": order_fails,"""
assert old5 in s
s = s.replace(old5, new5, 1)

# 4) чистая ходьба: дрожать у стены — не ходить
old6 = """	if moved > 0.03:
		last_pos = pos
		_add(z_walk_px, area_now, moved)
		if engaged_now.is_empty():
			t_walk_pure += DT"""
new6 = """	if moved > 0.03:
		last_pos = pos
		_add(z_walk_px, area_now, moved)
		# в «чистую ходьбу» идут только кадры настоящей езды (>0.3 px/кадр = 18 px/с):
		# иначе дрожь у стены превращалась минуты ходьбы (243 с «ходьбы» на 4,7 тыс. px)
		if moved > 0.3 and engaged_now.is_empty():
			t_walk_pure += DT"""
assert old6 in s, "ходьба не найдена"
s = s.replace(old6, new6, 1)

# 5) вызов переприказа — перед политикой движения
old7 = """	if _s(cfg.get("mode", "march")) == "march" and leg >= 0:
		leg_t += DT
	_policy()"""
new7 = """	if _s(cfg.get("mode", "march")) == "march" and leg >= 0:
		leg_t += DT
	_order_pump()
	_policy()"""
assert old7 in s, "вызов политики не найден"
s = s.replace(old7, new7, 1)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("правки применены")
