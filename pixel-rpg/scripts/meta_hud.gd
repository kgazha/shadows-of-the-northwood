class_name MetaHud
extends Control
## Мета-счётчики HUD (P2: docs/RETENTION_NG_PLUS.md §3.4 «иконку-счётчик в HUD — P2»
## + §4 «Пепел»): ГРАФИКА ЗАМОРОЖЕНА — только текст в пиксельной палитре HUD.
## Инстанцируется hud.gd (хук 2+1 строки) как child его CanvasLayer(layer=1);
## миникарта — чужой CanvasLayer(layer=0), правый верхний угол, 64 px:
## наши координаты левый нижний угол ВЫШЕ полосы диалогов (panel top -66),
## пересечений нет ни по слоям, ни по координатам.
##
## Чтение — строго GameState.flags.get(key, def) (§5.2: старые сейвы без ключей
## не должны падать). Ключи: "meta.ash" (канон хранения — ash.gd::KEY, читаем
## флаг напрямую — нулевая связность, паттерн achv.gd против ClassDB в Web-рантайме),
## "meta.*" — любые купленные алтарём улучшения (shop «Пепельный Алтарь»),
## "daily.stamp"/"daily.streak" — §3.1.
## Порог «сегодня» = тот же, что «тот же день» в achv.gd::_daily():
## (now - stamp) < 86400; откат часов (now < stamp) даёт < 86400 → «сегодня ✓»
## (награда по stamp уже выдана — показывать «пропуск» было бы враньём).
## Обновление — НЕ по сигналу (Пепел stats_changed не эмитит): дешёвая подпись
## раз в TICK секунд, паттерн journal.gd::_ach_sig.

const TICK := 0.5
const COL_ASH := Color(0.80, 0.77, 0.73)        # «пепельный» серый
const COL_NG := Color(0.95, 0.78, 0.45)         # янтарь «Круга» — тёплее пепла
const COL_DAILY_OK := Color(0.55, 0.85, 0.5)    # зелёный счётчика журнала
const COL_DAILY_MISS := Color(0.85, 0.5, 0.45)  # тревожный, но не кислотный

var _t := 0.0
var _sig := ""
var _ng_lbl: Label
var _ash_lbl: Label
var _daily_lbl: Label

func _ready() -> void:
	# нас не должно быть видно мышью никогда: вся ветка IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 8
	offset_top = -110  # выше полосы диалогов hud.panel (top -66); место под 3-ю строку NG+
	offset_right = 180
	offset_bottom = -70
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 1)
	_ng_lbl = _mk(COL_NG)
	_ash_lbl = _mk(COL_ASH)
	_daily_lbl = _mk(COL_DAILY_OK)
	vb.add_child(_ng_lbl)  # «Круг N» — над рядом Пепла (младший счётчик — выше)
	vb.add_child(_ash_lbl)
	vb.add_child(_daily_lbl)
	add_child(vb)
	_update()  # первый кадр без ожидания TICK

func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	_update()

func _mk(col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Есть ли хоть одно открытое meta.* (алтарные покупки переживают сброс сейва —
## счётчик Пепла виден и при нулевом балансе: «зачем возвращаться» не гаснет).
func _meta_open() -> bool:
	for k in GameState.flags:
		var key := String(k)
		if not key.begins_with("meta."):
			continue
		var v: Variant = GameState.flags[k]
		var t := typeof(v)
		if t == TYPE_BOOL or t == TYPE_INT or t == TYPE_FLOAT:
			if float(v) > 0.0:
				return true
	return false

func _update() -> void:
	var bal := int(GameState.flags.get("meta.ash", 0))
	var meta_open := _meta_open()
	var streak := int(GameState.flags.get("daily.streak", 0))
	var stamp := float(GameState.flags.get("daily.stamp", 0.0))
	var today := stamp > 0.0 and Time.get_unix_time_from_system() - stamp < 86400.0
	var wave := GameState.ng_wave()
	var sig := "%d|%d|%d|%d|%d" % [bal, streak, 1 if today else 0, 1 if meta_open else 0, wave]
	if sig == _sig:
		return
	_sig = sig
	# 0) Круг: только в NG+ (обычная игра — счётчика нет, HUD не пухнет)
	var ng_vis := wave > 0
	_ng_lbl.visible = ng_vis
	_ng_lbl.text = "Круг %d" % wave
	# 1) Пепел: при balance>0 ИЛИ открытом meta.* (новичку HUD не пухнет)
	var ash_vis := bal > 0 or meta_open
	_ash_lbl.visible = ash_vis
	_ash_lbl.text = "Пепел: %d" % bal
	# 2) Ежедневная серия: только при streak>0
	var daily_vis := streak > 0 and stamp > 0.0
	_daily_lbl.visible = daily_vis
	if daily_vis:
		if today:
			_daily_lbl.text = "Сегодня ✓ (%d/7)" % streak
			_daily_lbl.add_theme_color_override("font_color", COL_DAILY_OK)
		else:
			_daily_lbl.text = "Пропуск — серия сброшена"
			_daily_lbl.add_theme_color_override("font_color", COL_DAILY_MISS)
	visible = ng_vis or ash_vis or daily_vis
