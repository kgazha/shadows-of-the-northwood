extends RefCounted
# mob_avoid.gd — «усы» для преследователей (запрос пользователя 16.11).
#
# Проблема: мобы гнали к игроку прямой (velocity = (player - self).normalized()),
# и когда игрок прятался за стеной, упёртый моб дрожал у камня. Здесь — локальный
# обходчик без сеточного поля: веер лучей (усы) по слою стен 2 выбирает направление
# с НАИМЕНЬШИМ отклонением от цели, которое не упирается в стену. Выпуклые стены
# (камни пещер, заборы деревни, пепелищные гряды) обходятся; вогнутые ловушки —
# не гарантия (для них нужен flow field отдельной волной, записано в план).
#
# Канон:
#  * Призрак (mob_wraith) НЕ подключён — проход сквозь стены его фишка (шапка).
#  * Рывок Грома (rush_dir) и отход лучника — прямые: телеграфированный бросок
#    обязан быть честным щитом, отступление не нуждается в усах.
#  * Без class_name: регистрация глобальных классов требует import-кэша, а
#    домашний запуск идёт без редактора (урок ef64428) — подключаться preload.
#  * Лучи: слой 2 (стены), исключаем самого моба; стартовать от тела с margin,
#    длина усика — запас до следующего камня, не вся дистанция до цели.

const FAN := [0.0, 0.52, -0.52, 1.05, -1.05, 1.57, -1.57]  # рад: 0, ±30, ±60, ±90
const PROBE := 26.0   # длина уса, px: дальше следующего камня смотреть бессмысленно
const MIN_SQ := 1.0   # desired короче — не steerим (микродвижения, докаты)

## desired — желаемый вектор скорости (направление И величина). Возврат — вектор
## той же величины, повёрнутый к первому свободному усу; если свободно ничего —
## Vector2.ZERO (встать: дрожать в стену бессмысленно, цель за камнем).
static func steer(body: Node2D, desired: Vector2) -> Vector2:
	var mag := desired.length()
	if mag < 0.001 or desired.length_squared() < MIN_SQ:
		return desired
	var space := body.get_world_2d().direct_space_state
	var excl: Array[RID] = [body.get_rid()]
	var dir := desired / mag
	if _clear(body, space, excl, dir):
		return desired
	for ang in FAN:
		if ang == 0.0:
			continue
		var d2: Vector2 = dir.rotated(ang)
		if _clear(body, space, excl, d2):
			return d2 * mag
	return Vector2.ZERO

## Свободно ли направление: луч от тела на PROBE px по слою стен без касания.
static func _clear(body: Node2D, space: PhysicsDirectSpaceState2D, excl: Array[RID], dir: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(body.global_position, body.global_position + dir * PROBE, 2, excl)
	return space.intersect_ray(q).is_empty()

## 16.11 (второй юзер-фикс): прямая видимость. Агриться можно только на то, что
## физически видно: луч от тела к цели по слою стен 2 пуст. Стена закрывает и
## дистанцию, и лучнику (у того свой _has_los для выстрела был и раньше — теперь
## и у сближения).
static func los(from_body: Node2D, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from_body.global_position, to, 2, [from_body.get_rid()])
	return from_body.get_world_2d().direct_space_state.intersect_ray(q).is_empty()
