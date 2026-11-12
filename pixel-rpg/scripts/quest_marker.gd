extends CanvasLayer
## t19 (P0-2Б): стрелка активной цели квеста — отдельный мировой слой (прямое
## указание капитана: во время t23 в hud.gd не вписываться, маркер живёт своим
## слоем над миром). прежнее место — hud.gd::_update_marker — по той же причине
## навсегда погашен (строка вызова закомментирована).
##
## Правила (контракт P0-2Б):
##  • цель берётся у world.objective_pos(): NPC/босс/сундук/алтарь по активному
##    квесту, а если цель в другой зоне — переход (лестница/портал/вход) —
##    корректно на любой смене зоны (роутинг проверен и прежде, qa_z1);
##  • цель в кадре — стрелки нет;
##  • орбита — эллипс, вписанный в экран с отступами RX_PAD/RY_PAD: снизу он
##    не достаёт панели скиллов/зелий (полоса ~55 px), сверху — блока hp/маны/
##    опыта (боковые края эллипса уходят ниже ещё до x-блока), по бокам — только
##    средняя вертикаль, где HUD нет. Геометрия закреплена тестом qa_gb (M4).
##  • цвет — амбер (навигация к интерактиву, t18-дисциплина: красный=смерть,
##    золото=лут).

var world: Node2D
var arrow: Polygon2D
var _t := 0.0

const RX_PAD := 24.0   # отступ эллипса-орбиты по X (края экрана свободны от HUD)
const RY_PAD := 65.0   # по Y: снизу панель скиллов/зелий (~55 px) + запас, сверху — блок HUD

func setup(p_world: Node2D) -> void:
	world = p_world
	layer = 1  # тот же слой, что hud; добавляемся в world._ready после него
	arrow = Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(9, 0), Vector2(-6, -6), Vector2(-3, 0), Vector2(-6, 6)])
	arrow.color = Color(1.0, 0.7, 0.26, 0.9)  # амбер = интерактив/навигация
	arrow.visible = false
	add_child(arrow)

func _process(delta: float) -> void:
	if arrow == null or world == null or world.player == null:
		return
	var h: Variant = world.hud  # типизация hud — CanvasLayer, методы резолвим динамически
	if GameState.class_id == "" or GameState.input_locked \
			or (h != null and (h.is_dialog_open() or h.is_modal_open())):
		arrow.visible = false
		return
	var tp: Vector2 = world.objective_pos()
	if tp == Vector2.INF:
		arrow.visible = false
		return
	var vp: Viewport = world.get_viewport()
	var size: Vector2 = vp.get_visible_rect().size
	var p: Vector2 = vp.get_canvas_transform() * tp
	# цель в кадре — стрелка не нужна
	if p.x > 8.0 and p.x < size.x - 8.0 and p.y > 8.0 and p.y < size.y - 8.0:
		arrow.visible = false
		return
	var center := size * 0.5
	var d: Vector2 = p - center
	var rx: float = maxf(center.x - RX_PAD, 8.0)
	var ry: float = maxf(center.y - RY_PAD, 8.0)
	var k := sqrt(pow(d.x / rx, 2.0) + pow(d.y / ry, 2.0))
	if k < 0.001:
		arrow.visible = false
		return
	_t += delta
	arrow.position = center + d / k
	arrow.rotation = d.angle()
	arrow.color = Color(1.0, 0.7, 0.26, 0.75 + 0.2 * sin(_t * 5.0))
	arrow.visible = true
