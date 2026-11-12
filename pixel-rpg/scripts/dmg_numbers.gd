class_name DmgNumbers
extends Node2D
## Всплывающие числа урона/лечения. Единый ленивый узел-пул на сцену:
## DamageNumbers.spawn(pos, amount, kind) при первом вызове цепляется к
## get_tree().current_scene (мир Main) с z_index 90 — выше спрайтов мобов и
## FX-частиц (z=20), но ПОД CanvasLayer-оком HUD (полоски/диалоги не перекрывает).
## В проекте y_sort нигде не включён (проверено), так что порядок рисования
## задаёт только z_index — отдельных CanvasLayer для чисел не нужно.
## Пул Label: не более MAX_ACTIVE активных, сверх лимита старейшая гасится и
## переиспользуется — на 100 ударов в кадр уходит ровно MAX_ACTIVE нод.
## kind: "normal" | "crit" | "heal"; amount<=0 у урона — маленькая метка «броня»
## (полное поглощение), у heal — тихо пропускаем (не спамим «+0»).

const MAX_ACTIVE := 12        # жёсткий потолок живых чисел (= размер пула)
const RISE := 14.0            # всплытие вверх, px
const RISE_TIME := 0.5        # длительность всплытия, с (за неё же число гаснет)
const POP_TIME := 0.12        # t18: overshoot-pop 1.3 -> (отскок) -> 1.0, с
const POP_FROM := 1.3
const X_JITTER := 6.0         # разброс по x, ±px
const COLORS := {
	# t18 цветовая дисциплина: красный = только смертельное. Золото крита
	# («e8c860») спорило с семантикой лута — крит переехал в алое семейство.
	"crit": Color("ff5a46"),    # алое — критический урон (смертельное = красное)
	"normal": Color("f0e6d2"),  # тёплая кость — обычный урон
	"heal": Color("5da24a"),    # зелёный лечения из палитры
	"block": Color("8f93a3"),   # сталь — метка «броня» (полное поглощение)
}
# t27 P1-1: тот же пиксельный шрифт, что и HUD (UIFont -> assets/fonts/handjet.ttf;
# дефолтный шрифт проекта не менялся). Ступени подняты на шаг: крит 11, обычное/
# лечение 9, «броня» 7 (минимальная читаемая ступень; мирная подсказка world.gd — 8).
const FONT_SIZES := {"crit": 11, "normal": 9, "heal": 9, "block": 7}

static var _inst: DmgNumbers = null

## Точка входа. pos — мировые координаты (Vector2.INF — над героем).
static func spawn(pos: Vector2, amount: int, kind: String = "normal") -> void:
	if amount < 0 or (kind == "heal" and amount == 0):
		return  # «-0» и «+0» на экране не нужны
	var host := _host()
	if host == null:
		return
	host._show(pos, amount, kind if COLORS.has(kind) else "normal")

## Ленивый узел-хозяин: создаётся в текущей сцене при первом spawn и живёт
## до её смены (со сменой сцены умирает честно — вместе с деревом).
static func _host() -> DmgNumbers:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null or not is_instance_valid(tree.current_scene):
		return null
	var n := DmgNumbers.new()
	n.name = "DmgNumbers"
	n.z_index = 90  # над спрайтами мобов/Fx; HUD — CanvasLayer, он всё равно сверху
	tree.current_scene.add_child(n)
	_inst = n
	return n

var _pool: Array[Label] = []  # освобождённые Label (переиспользуются)
var _active: Array = []       # [{"lbl": Label, "tw": Tween}] — по порядку появления

## Для харнессов/тестов: сколько чисел сейчас на экране.
func active_count() -> int:
	return _active.size()

func _show(pos: Vector2, amount: int, kind: String) -> void:
	if pos == Vector2.INF:
		pos = _player_pos()
	if pos == Vector2.INF:
		return  # героя нет на сцене — показывать не над чем
	# переполнение пула: гасим СТАРЕЙШЕЕ до взятия ноды — всего Label <= MAX_ACTIVE
	if _active.size() >= MAX_ACTIVE:
		var old: Dictionary = _active[0]
		old["tw"].kill()
		_retire(old["lbl"])
	var kind_key := "block" if (kind != "heal" and amount == 0) else kind
	var lbl := _acquire()
	lbl.text = ("+%d" % amount) if kind == "heal" else ("броня" if kind_key == "block" else str(amount))
	lbl.add_theme_font_size_override("font_size", int(FONT_SIZES[kind_key]))
	lbl.add_theme_color_override("font_color", COLORS[kind_key])
	lbl.modulate = Color.WHITE
	lbl.reset_size()
	var start := pos + Vector2(randf_range(-X_JITTER, X_JITTER), 0) - lbl.size * 0.5
	lbl.global_position = start
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2.ONE * POP_FROM
	lbl.visible = true
	var tw := create_tween()
	tw.set_parallel(true)
	# pop 1.3->1.0 за 0.12 с с overshoot-отскоком (TRANS_BACK: цифра «сядет»
	# на место и дрогнет); всплытие 14 px за 0.5 с; затухание — вторая половина жизни
	tw.tween_property(lbl, "scale", Vector2.ONE, POP_TIME)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "global_position", start + Vector2(0, -RISE), RISE_TIME)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, RISE_TIME * 0.45).set_delay(RISE_TIME * 0.55)
	tw.chain().tween_callback(_retire.bind(lbl))
	_active.append({"lbl": lbl, "tw": tw})

## Освобождение: скрыть и в пул (Node не удаляем — переиспользуем).
func _retire(lbl: Label) -> void:
	for i in _active.size():
		if _active[i]["lbl"] == lbl:
			_active.remove_at(i)
			break
	if not is_instance_valid(lbl):
		return
	lbl.visible = false
	lbl.modulate = Color.WHITE
	lbl.scale = Vector2.ONE
	if not _pool.has(lbl):
		_pool.append(lbl)

func _acquire() -> Label:
	if _pool.is_empty():
		var lbl := Label.new()
		lbl.name = "DmgNum"
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# контур как у world.hint_label / hud.hp_txt — читаемо на тёмном лесу
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		lbl.add_theme_constant_override("outline_size", 3)
		# t27 P1-1: Label под Node2D темы не наследуют — пиксельный шрифт в лоб
		var f := UIFont.get_font()
		if f != null:
			lbl.add_theme_font_override("font", f)
		add_child(lbl)
		return lbl
	return _pool.pop_back()

static func _player_pos() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Vector2.INF
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p):
			# −18: точка отсчёта — глобальная позиция героя; визуальная макушка
			# поднята масштабом 1.5 (t9), числа всплывают над головой, а не на уровне груди
			return (p as Node2D).global_position + Vector2(0, -18)
	return Vector2.INF
