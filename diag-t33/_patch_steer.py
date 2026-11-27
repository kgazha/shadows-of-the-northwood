"""t33: патч руления — мелкая ось тоже жмётся, перпендикуляр при упоре."""
import io

P = r"diag-t33/census_t33.gd"
s = io.open(P, encoding="utf-8").read()

old = '''func _axis_press(d: Vector2) -> void:
	var want := {"move_left": d.x <= -0.3, "move_right": d.x >= 0.3,
			"move_up": d.y <= -0.3, "move_down": d.y >= 0.3}'''
new = '''func _axis_press(d: Vector2) -> void:
	# порог маленький нарочно: при 0.3 герой упирался в стену, потому что
	# «малая» ось (0.06 от нормали) не нажималась и скользить было нечем
	if d.length() > 0.05:
		last_dir = d.normalized()
	var want := {"move_left": d.x <= -0.06, "move_right": d.x >= 0.06,
			"move_up": d.y <= -0.06, "move_down": d.y >= 0.06}'''
assert old in s, "руление не найдено"
s = s.replace(old, new)

old2 = """		if player.global_position.distance_to(p) < 7.0:"""
new2 = """		if player.global_position.distance_to(p) < 9.0:"""
assert old2 in s, "радиус захвата точки не найден"
s = s.replace(old2, new2)

old3 = """func _unstick() -> void:
	unstick_dir = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	unstick_until = frame + 14"""
new3 = """func _unstick() -> void:
	# упор: шагаем в перпендикуляр к тому направлению, куда упирались (стена
	# обычно вдоль него), знак выбирает сид; если направления нет — случайный
	if last_dir != Vector2.ZERO:
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		unstick_dir = Vector2(-last_dir.y, last_dir.x) * sgn
		if unstick_dir.length() < 0.2:
			unstick_dir = Vector2.RIGHT
	else:
		unstick_dir = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	unstick_until = frame + 20"""
assert old3 in s, "анти-упор не найден"
s = s.replace(old3, new3)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("руление/захват/анти-упор обновлены")
