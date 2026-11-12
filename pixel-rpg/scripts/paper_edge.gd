class_name PaperEdge
extends Control
## t20: вынесен из внутреннего класса Journal.PaperEdge (договор с капитаном —
## общий UI-компонент без copy-paste: журнал, экран смерти, мета-доска).
## Логика и дефолты — дословно из t24, поведение не меняется.
##
## t24: «масштабируемый 9-patch» бумажной кромки. NinePatchRect не годился:
## его марджины рисуются 1:1 нативному размеру текстуры (256-текстура = кромка
## уже даунскейллена 4x из 1024-оригинала и на окне 2x ещё и растянута ~2.6x
## по горизонтальным рёбрам — «размытый/растянутый» фон). Здесь источник —
## нативная 999² текстура, срез строго по границе hole (alpha=0, t24_measure),
## углы — равномерным скеем, рёбра — только даунскейл (1.15–1.98 texel/win px).
## Центр не рисуем вовсе: он transparent и под ним stylebox панели.

var tex: Texture2D
var src_margin := 95.0
var dst_margin := 24.0

func _draw() -> void:
	if tex == null:
		return
	var s := tex.get_size()
	var sm: float = minf(src_margin, minf(s.x, s.y) * 0.5 - 1.0)
	var dm: float = minf(dst_margin, minf(size.x, size.y) * 0.5 - 1.0)
	if sm <= 0.0 or dm <= 0.0 or size.x < 2.0 * dm or size.y < 2.0 * dm:
		return
	var iw: float = s.x - 2.0 * sm
	var ih: float = s.y - 2.0 * sm
	# углы — из нативных уголков, равномерный скей (без анаморфоза)
	draw_texture_rect_region(tex, Rect2(0, 0, dm, dm), Rect2(0, 0, sm, sm))
	draw_texture_rect_region(tex, Rect2(size.x - dm, 0, dm, dm), Rect2(s.x - sm, 0, sm, sm))
	draw_texture_rect_region(tex, Rect2(0, size.y - dm, dm, dm), Rect2(0, s.y - sm, sm, sm))
	draw_texture_rect_region(tex, Rect2(size.x - dm, size.y - dm, dm, dm),
		Rect2(s.x - sm, s.y - sm, sm, sm))
	# рёбра — единственной координатой вдоль ленты; оба фактора <=1 (даунскейл)
	var ew: float = size.x - 2.0 * dm
	var eh: float = size.y - 2.0 * dm
	draw_texture_rect_region(tex, Rect2(dm, 0, ew, dm), Rect2(sm, 0, iw, sm))
	draw_texture_rect_region(tex, Rect2(dm, size.y - dm, ew, dm), Rect2(sm, s.y - sm, iw, sm))
	draw_texture_rect_region(tex, Rect2(0, dm, dm, eh), Rect2(0, sm, sm, ih))
	draw_texture_rect_region(tex, Rect2(size.x - dm, dm, dm, eh), Rect2(s.x - sm, sm, sm, ih))
