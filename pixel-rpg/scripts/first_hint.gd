class_name FirstHint
extends CanvasLayer
## Контекстные подсказки первопроходцу (трек C, retention для VK Play).
##
## СОДЕРЖИМОЕ: одна строка текста внизу экрана по центру. Не HUD-панель:
## фон/рамка не заводим — пиксельный шрифт с чёрной обводкой читается на
## любой локации (тот же приём, что toast у hud и подписи meta_hud).
##
## ГЕОМЕТРИЯ (конфликтов нет ни по слоям, ни по координатам):
## - полоса диалогов/взаимодействия hud.panel: низ, top -66..-8 — наш текст
##   ВЫШЕ неё (полоса -96..-70), диалог не перекрывает;
## - meta_hud: левый нижний угол x 8..180, те же -96..-70 — мы по ЦЕНТРУ
##   (центр 300 px шириной: x 170..470 при дизайне 640), пересечения нет;
## - toast/ачивки-тосты: hud y=30 сверху — разные концы экрана;
## - миникарта: чужой CanvasLayer(0) правый верх — далеко.
## Слой: layer = 0 — между миром и hud (1): подсказка рисуется ПОД hud и
## под всем модальным (фейд 10, настройки 20), т.е. поверх диалога не лезет
## и мышью не перехватывается (вся ветка MOUSE_FILTER_IGNORE).
##
## API (контракт для интеграционных хуков):
##   FirstHint.I                — синглтон (init в world._ready по паттерну
##                                ClickMove/Minimap; _enter_tree — fallback);
##   FirstHint.I.show_hint(id, text) — показать ОДИН раз за сейв-жизнь.
## Дедуп — GameState.flags["hint."+id] (только чтение через .get с дефолтом,
## правило achv/meta_hud: старые сейвы не падают). Флаг ставится в момент
## фактического показа, т.е. «показан», а не «заявлен».
## ОЧЕРЕДЬ: показываем строго по одной подсказке; пока активна — новые
## копии того же id схлопываются, другие id ждут в очереди. При
## GameState.input_locked (диалог/модалка/фейд) показ замораживается:
## текущий не тратит секунды, следующий не стартует — первопроходцу не
## мешаем, свой бюджет 4 с досматривает после освобождения.
## Персистентность: flags целиком сериализуются сейвом v2 (game_state.gd
## "flags": flags.duplicate()) — whitelist не нужен, KnownKeys сейф-вольта
## ("gold","hp","flags") флаг закрывает; hint.* НЕ сбрасывается в start_ng_plus
## (там гасятся только q.*/ashen.*) — подсказки не показываются повторно.

const HIDE_AFTER := 4.0              # секунд показа одной строки
const COL_HINT := Color(1.0, 0.93, 0.65)  # «тёплое напутствие» — тон toast

static var I: FirstHint              # синглтон; назначает world._ready (fallback — _enter_tree)

var _label: Label
var _active := ""                    # id показываемой подсказки ("" — нет)
var _t := 0.0                        # остаток показа
var _queue: Array = []               # [[id, text], ...] — ждут своей очереди

func _enter_tree() -> void:
	if I == null:
		I = self

func _exit_tree() -> void:
	if I == self:
		I = null

func _ready() -> void:
	layer = 0                        # ниже hud(1): см. ГЕОМЕТРИЯ в шапке
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -150        # центральная полоса 300 px (дизайн 640)
	_label.offset_right = 150
	_label.offset_top = -96          # та же полоса, что meta_hud, но по центру
	_label.offset_bottom = -70       # ...и над hud.panel (-66)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", COL_HINT)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 3)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)

## Публичный вход: id — стабильный ключ дедупа (первый слайм, первый костёр,
## ...), text — одна строка на ~60 символов. Повтор того же id за сейв — no-op.
func show_hint(id: String, text: String) -> void:
	if String(GameState.flags.get("hint." + id, "")) != "":
		return                       # показан в этой сейв-жизни
	if _active == id:
		return
	for q in _queue:
		if String(q[0]) == id:
			return
	_queue.append([id, text])

func _process(delta: float) -> void:
	if _active != "":
		if GameState.input_locked:
			return                   # диалог/модалка/фейд: время стоит
		_t -= delta
		if _t <= 0.0:
			_active = ""
			_label.visible = false
	while _active == "" and not _queue.is_empty() and not GameState.input_locked:
		var q: Array = _queue.pop_front()
		var id := String(q[0])
		# вторая проверка дефолта: флаг мог встать за время ожидания в очереди
		if String(GameState.flags.get("hint." + id, "")) != "":
			continue
		_active = id
		GameState.set_flag("hint." + id, "1")
		_label.text = String(q[1])
		_label.visible = true
		_t = HIDE_AFTER
