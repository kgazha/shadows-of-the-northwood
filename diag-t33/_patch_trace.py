"""t33: временная настройка трассировки (полоса отладки пути), одноразовая."""
import io

P = r"diag-t33/census_t33.gd"
s = io.open(P, encoding="utf-8").read()

# 1) трасса раз в секунду вместо раза в пять секунд
old = 'if int(cfg.get("trace", 0)) > 0 and frame % 300 == 0:'
new = 'if int(cfg.get("trace", 0)) > 0 and frame % 60 == 0 and frame < int(cfg.get("trace_until", 3600)):'
assert old in s, "трасса не найдена"
s = s.replace(old, new)

# 2) событие «застряли» в лог
old2 = """	if stuck_fr > 25:
		stuck_fr = 0
		retries += 1
		t_stuck += 0.5
		_unstick()"""
new2 = """	if stuck_fr > 25:
		stuck_fr = 0
		retries += 1
		t_stuck += 0.5
		print("  [застревание] к=%d поз=%s путь=%d/%d следующая=%s retries=%d цель=%s" % [
				frame, _s(player.global_position), path_idx, path_cells.size(),
				_s(path_cells[path_idx]) if path_idx < path_cells.size() else "нет",
				retries, goal_kind])
		_unstick()"""
assert old2 in s, "детектор застревания не найден"
s = s.replace(old2, new2)

# 3) перекладка пути при повторяющихся застреваниях
old3 = """	# точок, до которого не дошли, не ждём: перешагнули и идём к следующему
	if not path_cells.is_empty() and path_idx < path_cells.size():
		path_idx += 1"""
new3 = """	# точок, до которого не дошли, не ждём: перешагнули и идём к следующему
	if not path_cells.is_empty() and path_idx < path_cells.size():
		path_idx += 1
	# каждое третье застревание — путь устарел, перекладываем от текущей клетки
	if retries % 3 == 0 and goal_pos != Vector2.ZERO:
		_retarget_pos()"""
assert old3 in s, "anti-stuck не найден"
s = s.replace(old3, new3)

# 4) LEG_CAP и dwell
s = s.replace("const LEG_CAP := 150.0", "const LEG_CAP := 120.0")
s = s.replace('"dwell": 75.0', '"dwell": 60.0')
s = s.replace('"dwell": 45.0', '"dwell": 40.0')

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("трассировка/анти-застревание/LEG_CAP настроены")
