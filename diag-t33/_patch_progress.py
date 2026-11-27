"""t33: правка порога прогресса движения (пер-кадр, не пер-секунду)."""
import io

P = r"diag-t33/census_t33.gd"
s = io.open(P, encoding="utf-8").read()

old = """	if moved > 2.0:
		last_moved_frame = frame"""
new = """	if moved > 0.3:
		# 0.3 px/кадр = 18 px/с: герой реально едет, а не дрожит на месте
		last_moved_frame = frame"""
assert old in s, "порог прогресса не найден"
s = s.replace(old, new)

old2 = """	if frame - last_moved_frame > 600:
		# десять секунд без двух пикселей пути: всё, тут встанка"""
new2 = """	if intends and frame - last_moved_frame > 600:
		# десять секунд нажатых клавиш без хода: всё, это встанка"""
assert old2 in s, "встанка не найдена"
s = s.replace(old2, new2)

old3 = """	last_pos = player.global_position"""
new3 = """	last_pos = player.global_position
	last_moved_frame = frame"""
assert old3 in s, "инициализация позиции не найдена"
s = s.replace(old3, new3)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("порог прогресса поправлен")
