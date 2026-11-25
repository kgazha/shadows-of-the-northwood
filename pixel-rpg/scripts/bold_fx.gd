class_name BoldFx
extends Node2D
## t23 «Интеграция VFX смело» (вердикт пользователя 25.11: «Ощущение v2 — VFX
## смело мне нравится», лист diag-w5b/sheet_fx_v2.png, md5 F428813674375338DE01CEF32F4832A1).
##
## Носители — РОВНО таблица PINS_W5B §4, без новых архитектур:
## волна — AtlasTexture-подобный спрайт + покадровый Tween (как env-арт);
## брызги — CPUParticles2D (носитель Fx.hit); виньетка — CanvasLayer ColorRect;
## комбо — Label из пула DmgNumbers; добивание — Juice (кадровый dip);
## след/остаток стрелы, сгусток, лучи — Sprite2D+Tween и существующие пулы;
## свист — дуга-спрайт; тень-лужа — Sprite2D+Tween, цвет под биом.
## Кадры-изображения копированы из sheet_fx_v2.gd БУКВАЛЬНО (волна/сгусток/
## лучи) — FNV рантайм-кадров совпадает с пином листа (метод W7.1); кадры,
## у которых лист рисовал мокап-фон (виньетка/лужа/след/дуга), в рантайме —
## те же пиксели эффекта БЕЗ подложки (пол рисует террейн), они запинены
## отдельно в qa_dn (D-B3).
## Тумблер «Смелые эффекты» (GameState.bold_fx, по умолчанию ВКЛ): OFF — эти
## эффекты молчат; числа/искры/тряска/hit-stop/t18-виньетка живут как сегодня.

const P := preload("res://scripts/pixel_palette.gd")

# Тайминги — зеркало const листа sheet_fx_v2.gd (строка в строку, PINS_W5B §1).
# QA-стенд qa_dn D-B6 сверяет эти числа с литеральной таблицей листа.
const T_WAVE_MS := 40
const T_SPLAT_MS := 40
const T_VIGN_MS := 70
const T_COMBO_MS := 50
const T_FINISH_SLOW := 60      # мс игрового времени ~ кадровый dip в Juice
const T_FINISH_FLASH := 100
const T_FLY_MS := 45
const T_QUIVER_MS := 60
const T_BOLT_MS := 60
const T_BURST_MS := 40
const T_SWISH_MS := 50
const T_SHAD_MS := 70

const COMBO_WINDOW_MS := 900   # окно серии: попадание-попадание (визуал, в хэши не входит)

static var _inst: BoldFx = null
static var _tex_cache := {}
static var _combo_n := 0
static var _combo_ms := -100000

static func enabled() -> bool:
	return GameState.bold_fx

## Хост-узел эффектов (ленивый, как DmgNumbers): z=28 — над спрайтами мобов
## (0..20) и частицами Fx (20), под числами урона (90).
static func host() -> BoldFx:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null or not is_instance_valid(tree.current_scene):
		return null
	var n := BoldFx.new()
	n.name = "BoldFx"
	n.z_index = 28
	tree.current_scene.add_child(n)
	_inst = n
	return n

# ============================================================ палитра/примитивы
# Копи-паст примитивов sheet_fx_v2.gd: совпадение байтов кадров = совпадение FNV.

static func _c(rn: String, t: int) -> Color:
	return P.RAMPS[rn][t]

static func _im(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func _put(im: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, col)

static func _span(im: Image, x0: int, x1: int, y: int, col: Color) -> void:
	for x in range(x0, x1 + 1):
		_put(im, x, y, col)

static func _rect16(im: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_put(im, x, y, col)

static func _ring(im: Image, cx: float, cy: float, r: float, col: Color, step: int) -> void:
	var n := int(maxf(12.0, TAU * r))
	for i in range(0, n, step):
		var a := TAU * float(i) / float(n)
		_put(im, int(round(cx + r * cos(a))), int(round(cy + r * sin(a))), col)

static func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

# ================================================== кадры (буква листа W5B)

static func _frame_wave(f: int) -> Image:
	var im := _im(16, 16)
	match f:
		0:
			_ring(im, 8, 8, 3, _c("BONE", P.T_LIGHT), 1)
		1:
			_ring(im, 8, 8, 6, _c("BONE", P.T_MID), 1)
		2:
			_ring(im, 8, 8, 9, _c("BONE", P.T_DARK), 2)
			_put(im, 8, 8, _c("BONE", P.T_LIGHT))
	return im

static func _frame_bolt(f: int) -> Image:
	var im := _im(16, 16)
	if f == 0:
		_rect16(im, 7, 7, 9, 9, _c("CRYSTAL", P.T_MID))
		for d in [[6, 8], [10, 8], [8, 6], [8, 10], [6, 6], [10, 6], [6, 10], [10, 10]]:
			_put(im, d[0], d[1], _c("CRYSTAL", P.T_DARK))
	else:
		_rect16(im, 7, 7, 9, 9, _c("CRYSTAL", P.T_LIGHT))
		for d in [[6, 8], [10, 8], [8, 6], [8, 10]]:
			_put(im, d[0], d[1], _c("VIOLET", P.T_MID))
		for d in [[6, 6], [10, 6], [6, 10], [10, 10]]:
			_put(im, d[0], d[1], _c("VIOLET", P.T_DARK))
	return im

static func _frame_burst(f: int) -> Image:
	var im := _im(16, 16)
	var C := 8
	match f:
		0:
			for d in [[1, 0], [2, 0], [3, 0], [-1, 0], [-2, 0], [-3, 0], [0, 1], [0, 2], [0, 3], [0, -1], [0, -2], [0, -3]]:
				_put(im, C + d[0], C + d[1], _c("CRYSTAL", P.T_LIGHT))
			for d in [[1, 1], [-1, 1], [1, -1], [-1, -1], [2, 2], [-2, 2], [2, -2], [-2, -2]]:
				_put(im, C + d[0], C + d[1], _c("VIOLET", P.T_LIGHT))
		1:
			for s in 5:
				for sgn in [1, -1]:
					_put(im, C + sgn * s, C, _c("CRYSTAL", P.T_LIGHT if s == 4 else P.T_MID))
					_put(im, C, C + sgn * s, _c("CRYSTAL", P.T_LIGHT if s == 4 else P.T_MID))
			for s in 3:
				for d in [[1, 1], [-1, 1], [1, -1], [-1, -1]]:
					_put(im, C + d[0] * s, C + d[1] * s, _c("VIOLET", P.T_MID))
		2:
			for d in [[6, 0], [-6, 0], [0, 6], [0, -6]]:
				_put(im, C + d[0], C + d[1], _c("CRYSTAL", P.T_DARK))
			_put(im, 13, 3, _c("VIOLET", P.T_DARK))
			_put(im, 14, 2, _c("VIOLET", P.T_MID))
			_put(im, 3, 12, _c("VIOLET", P.T_DARK))
			_put(im, 2, 13, _c("VIOLET", P.T_MID))
			_put(im, 12, 13, _c("CRYSTAL", P.T_DARK))
			_put(im, 4, 3, _c("CRYSTAL", P.T_DARK))
	return im

## Кадр листа _puddle(fam) БЕЗ полосы-подложки (её рисует живой террейн):
## те же пиксели лужи — тёмное пятно + светлые капли по краям.
static func _frame_puddle(fam: String) -> Image:
	var im := _im(16, 16)
	_span(im, 3, 12, 12, _c(fam, P.T_DARK))
	_span(im, 4, 11, 11, _c(fam, P.T_DARK))
	_put(im, 3, 11, _c(fam, P.T_LIGHT))
	_put(im, 12, 11, _c(fam, P.T_LIGHT))
	return im

## Стадии растекания (тот же ритм 4->10 px, что тень-лужа листа, 3 кадра).
static func _frame_shad(f: int, fam: String) -> Image:
	var im := _im(16, 16)
	match f:
		0:
			_span(im, 7, 9, 12, _c(fam, P.T_DARK))
		1:
			_span(im, 5, 11, 12, _c(fam, P.T_DARK))
			_span(im, 6, 10, 11, _c(fam, P.T_DARK))
		_:
			return _frame_puddle(fam)
	return im

## Хвост стрелы (2к): те же точки PATH M->D и тот же шаг, что след strela-кадров
## листа; в рантайме — только точки позади древка (древко рисует снаряд).
static func _frame_tail(f: int) -> Image:
	var im := _im(16, 16)
	if f == 0:
		_put(im, 10, 8, _c("PATH", P.T_MID))
		_put(im, 6, 7, _c("PATH", P.T_MID))
		_put(im, 2, 7, _c("PATH", P.T_DARK))
	else:
		_put(im, 11, 8, _c("PATH", P.T_DARK))
		_put(im, 7, 7, _c("PATH", P.T_DARK))
	return im

## Свист-дуга промаха: пунктир CRYSTAL_MID + искра HUD_GOLD_M (те же точки,
## что svist-кадр листа; болванка-мишень в рантайм не переносится).
static func _frame_arc() -> Image:
	var im := _im(16, 16)
	var n := 16
	for i in range(0, n, 2):
		var a := deg_to_rad(lerpf(100.0, 20.0, float(i) / float(n)))
		_put(im, int(round(2 + 11 * cos(a))), int(round(14 - 11 * sin(a))), _c("CRYSTAL", P.T_MID))
	_put(im, 12, 4, _c("HUD_GOLD", P.T_MID))
	return im

## Витрина кадров для стенда (qa_dn D-B3): имя -> FNV сверяется с пином.
## тень-лужа параметризована рампом поля: "shad_GRASS"/"shad_PATH"/…
static func frame(nm: String, f: int) -> Image:
	match nm:
		"wave":
			return _frame_wave(f)
		"bolt":
			return _frame_bolt(f)
		"burst":
			return _frame_burst(f)
		"tail":
			return _frame_tail(f)
		"arc":
			return _frame_arc()
	if nm.begins_with("shad_"):
		return _frame_shad(f, nm.trim_prefix("shad_"))
	if nm.begins_with("puddle_"):
		return _frame_puddle(nm.trim_prefix("puddle_"))
	return _im(1, 1)

static func _tex(nm: String, f: int) -> Texture2D:
	var key := "%s_%d" % [nm, f]
	if _tex_cache.has(key) and is_instance_valid(_tex_cache[key]):
		return _tex_cache[key]
	var t := ImageTexture.create_from_image(frame(nm, f))
	_tex_cache[key] = t
	return t

# ================================================================ аниматор кадра

class FxAnim:
	extends Sprite2D
	## Покадровый спрайт-вещатель: кадры ms миллисекунд игрового времени
	## (time_scale честно замедляет и эффект). loops=0 — до гибели родителя.
	var frames: Array = []
	var ms := 40.0
	var loops := 1
	var hold_s := 0.0
	var fade_s := 0.0
	var _t := 0.0
	var _done := false

	func _ready() -> void:
		centered = true
		add_to_group("boldfx")

	func _process(delta: float) -> void:
		if frames.is_empty():
			queue_free()
			return
		_t += delta * 1000.0
		var anim_ms := frames.size() * ms
		if _t < anim_ms:
			texture = frames[int(_t / ms) % frames.size()]
		elif loops == 0:
			_t = 0.0
			texture = frames[0]
		elif _t < anim_ms + hold_s * 1000.0:
			if not _done:
				texture = frames[frames.size() - 1]
				_done = true
		elif fade_s > 0.0:
			if not _done:
				texture = frames[frames.size() - 1]
				_done = true
			var ft := (_t - anim_ms - hold_s * 1000.0) / (fade_s * 1000.0)
			if ft >= 1.0:
				queue_free()   # fade закончился — нода обязана умереть (дренаж T8.8)
				return
			modulate.a = clampf(1.0 - ft, 0.0, 1.0)
		else:
			queue_free()

static func _anim(nm: String, count: int, ms: float, pos: Vector2, rot := 0.0,
		z := 24, loops := 1, hold_s := 0.0, fade_s := 0.0, parent: Node2D = null) -> void:
	var h := host()
	if h == null:
		return
	var a := FxAnim.new()
	a.name = "Bfx_" + nm
	for f in count:
		a.frames.append(_tex(nm, f))
	a.texture = a.frames[0]
	a.ms = ms
	a.loops = loops
	a.hold_s = hold_s
	a.fade_s = fade_s
	a.rotation = rot
	a.z_index = z
	var p := parent if parent != null and is_instance_valid(parent) else h
	p.add_child(a)
	a.global_position = pos

# ==================================================================== эффекты

## Волна тяжёлого удара: кольцо BONE L->M->D, 3x40 мс (PINS_W5B §1/§4).
static func wave(pos: Vector2) -> void:
	if not enabled():
		return
	_anim("wave", 3, float(T_WAVE_MS), pos)

## Брызги-осколки по вектору удара: CPUParticles2D (носитель Fx.hit), 6 точек,
## золото->огонь->уголёк, жизнь ~3x40 мс (PINS_W5B §2 «брызги»).
static func splat(pos: Vector2, dir: Vector2, parent: Node2D) -> void:
	if not enabled():
		return
	var d := dir.normalized() if dir != Vector2.ZERO else Vector2.UP
	var ramp := Fx._ramp(_c("HUD_GOLD", P.T_LIGHT), _c("FIRE", P.T_MID),
			Color(_c("CHAR", P.T_MID).r, _c("CHAR", P.T_MID).g, _c("CHAR", P.T_MID).b, 0.0))
	# lifetime = 3 кадра по 40 мс = 120 мс (крупные точки живут полный цикл,
	# мелкие — половину, так что «5-7 точек» на любом кадре кадра)
	Fx._make(parent, pos, {
		"tex": Fx.TEX_DOT, "amount": 6, "life": 0.18, "explode": 1.0,
		"dir": d, "spread": 55.0, "gravity": Vector2(0, 120),
		"vmin": 40.0, "vmax": 90.0, "damp_min": 40.0, "damp_max": 90.0,
		"smin": 0.5, "smax": 1.0, "ramp": ramp, "z": 26,
	})

## Виньетка получения: рамка CanvasLayer (4 ColorRect) HP_RED MID 2px +
## светлые углы, 70 мс, затем 1px DARK ещё 70 мс. t18-импульс hud не тронут —
## эта рамка аддитивна и живёт только при тумблере ВКЛ.
static func vignette() -> void:
	if not enabled():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var cl := CanvasLayer.new()
	cl.name = "BfxVignette"
	cl.layer = 50
	tree.root.add_child(cl)
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var mid := _c("HP_RED", P.T_MID)
	var rects: Array[ColorRect] = []
	for r in [Rect2(0, 0, w, 2), Rect2(0, h - 2, w, 2), Rect2(0, 2, 2, h - 4), Rect2(w - 2, 2, 2, h - 4)]:
		var rc := ColorRect.new()
		rc.color = mid
		rc.position = r.position
		rc.size = r.size
		rc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(rc)
		rects.append(rc)
	var lig := _c("HP_RED", P.T_LIGHT)
	for d in [Vector2(0, 0), Vector2(w - 2, 0), Vector2(0, h - 2), Vector2(w - 2, h - 2)]:
		var cr := ColorRect.new()
		cr.color = lig
		cr.position = d
		cr.size = Vector2(2, 2)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(cr)
	var tw := cl.create_tween()
	tw.tween_interval(T_VIGN_MS / 1000.0)
	tw.tween_callback(func() -> void:
		# к1 листа: рамка гаснет в 1px HP_RED_DARK (геометрия 2px -> 1px, не только цвет)
		var dk := _c("HP_RED", P.T_DARK)
		rects[0].size = Vector2(w, 1)
		rects[1].position = Vector2(0, h - 1); rects[1].size = Vector2(w, 1)
		rects[2].position = Vector2(0, 1); rects[2].size = Vector2(1, h - 2)
		rects[3].position = Vector2(w - 1, 1); rects[3].size = Vector2(1, h - 2)
		for rc in rects:
			rc.color = dk
		for ch in cl.get_children():
			if ch is ColorRect and ch.color == lig:
				ch.queue_free())
	tw.tween_interval(T_VIGN_MS / 1000.0)
	tw.tween_callback(cl.queue_free)

## Комбо: серия попаданий подряд (окно 900 мс реального времени — чистый
## визуал, в детерминированные хэши не входит). С 3-го подряд — метка «xN»
## из пула DmgNumbers (носитель листа: 2-й Label пула), HUD_GOLD + щепотка
## золотых искр (§2 листа: «искры GOLD_MID», ритм 3x50 мс).
static func note_hit(pos: Vector2, parent: Node2D = null) -> void:
	var now := Time.get_ticks_msec()
	_combo_n = _combo_n + 1 if now - _combo_ms <= COMBO_WINDOW_MS else 1
	_combo_ms = now
	if enabled() and _combo_n >= 3:
		DmgNumbers.combo(pos, _combo_n)
		var p := parent if parent != null and is_instance_valid(parent) else host()
		if p != null:
			Fx._make(p, pos, {
				"tex": Fx.TEX_STAR, "amount": 4, "life": 0.15, "explode": 1.0,
				"vmin": 18.0, "vmax": 42.0, "gravity": Vector2(0, 60),
				"smin": 0.5, "smax": 0.8, "z": 26,
				"ramp": Fx._ramp(_c("HUD_GOLD", P.T_LIGHT), _c("HUD_GOLD", P.T_MID),
						Color(_c("CHAR", P.T_DARK).r, _c("CHAR", P.T_DARK).g, _c("CHAR", P.T_DARK).b, 0.0)),
			})

static func note_whiff() -> void:
	_combo_n = 0

## Добивание: кадровый dip Juice (механика hit-stop с гарантиями возврата —
## juice.gd) + белый флеш 1 кадр-вспышка. Единственный эффект, трогающий шаг
## времени; вне тумблера не существует (PINS_W5B §5).
static func finisher(pos: Vector2) -> void:
	if not enabled():
		return
	Juice.finisher_pulse()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var cl := CanvasLayer.new()
	cl.name = "BfxFlash"
	cl.layer = 60
	tree.root.add_child(cl)
	var rc := ColorRect.new()
	rc.color = Color(_c("BONE", P.T_LIGHT), 0.9)
	rc.set_anchors_preset(Control.PRESET_FULL_RECT)
	rc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(rc)
	var tw := cl.create_tween()
	tw.tween_property(rc, "modulate:a", 0.0, T_FINISH_FLASH / 1000.0)
	tw.tween_callback(cl.queue_free)

## След хвоста стрелы: второй спрайт-анимация на снаряде (носитель листа —
## 2-й AtlasTexture projectile), хвост 2x45 мс, цикл до гибели снаряда.
static func arrow_tail(proj: Node2D) -> void:
	if not enabled():
		return
	var a := FxAnim.new()
	a.name = "Bfx_tail"
	a.frames = [_tex("tail", 0), _tex("tail", 1)]
	a.texture = a.frames[0]
	a.ms = float(T_FLY_MS)
	a.loops = 0          # мигает, пока живёт снаряд
	a.offset = Vector2(-10, 0)
	a.z_index = -1       # позади древка
	proj.add_child(a)

## Попадание стрелы: остаток с дрожанием оперения (±1 px, 2x60 мс — носитель
## «Tween-посылка на остатке») + пылевой блип Fx.dust; затем гаснет.
static func arrow_stub(pos: Vector2, rot: float, idx: int, parent: Node2D) -> void:
	if not enabled():
		return
	var h := host()
	if h == null:
		return
	var s := Sprite2D.new()
	s.name = "Bfx_stub"
	s.add_to_group("boldfx")
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/projectiles.png")
	at.region = Rect2(clampi(idx, 0, 3) * 16, 0, 16, 16)
	s.texture = at
	s.rotation = rot
	s.z_index = 24
	h.add_child(s)
	s.global_position = pos
	var tw := s.create_tween()
	var base := s.position
	tw.tween_property(s, "position", base + Vector2(1, 0), T_QUIVER_MS / 1000.0)
	tw.tween_property(s, "position", base + Vector2(0, -1), T_QUIVER_MS / 1000.0)
	tw.tween_property(s, "position", base, T_QUIVER_MS / 1000.0)
	tw.tween_property(s, "modulate:a", 0.0, 0.15)
	tw.tween_callback(s.queue_free)
	Fx.dust(pos, parent)

## Сгусток магии: мерцающий кадр болта (носитель листа — кадр болта + Tween).
static func bolt_spr(proj: Sprite2D) -> void:
	if not enabled():
		return
	var a := FxAnim.new()
	a.name = "Bfx_bolt"
	a.frames = [_tex("bolt", 0), _tex("bolt", 1)]
	a.texture = a.frames[0]
	a.ms = float(T_BOLT_MS)
	a.loops = 0          # мерцает, пока летит
	proj.add_child(a)

## Удар магии: лучи 4+4 крест-накрест (3к x40) + осколки TEX_SHARD (пул Fx).
static func magic_burst(pos: Vector2, parent: Node2D) -> void:
	if not enabled():
		return
	_anim("burst", 3, float(T_BURST_MS), pos, 0.0, 26)
	Fx._make(parent, pos, {
		"tex": Fx.TEX_SHARD, "amount": 8, "life": 0.3, "explode": 1.0,
		"vmin": 20.0, "vmax": 55.0, "gravity": Vector2(0, 90),
		"smin": 0.5, "smax": 0.9, "ramp": Fx._ice_ramp(), "z": 26,
	})

## Свист промаха: дуга-пунктир за клинком (промах ВИДЕН), 2x50 мс.
static func swish(pos: Vector2, rot: float) -> void:
	if not enabled():
		return
	var h := host()
	if h == null:
		return
	var a := FxAnim.new()
	a.name = "Bfx_swish"
	a.frames = [_tex("arc", 0)]
	a.texture = a.frames[0]
	a.ms = float(T_SWISH_MS) * 2.0   # один кадр держим ритм двух
	a.rotation = rot
	a.z_index = 26
	h.add_child(a)
	a.global_position = pos

## Тень-лужа смерти: расползается 4->10 px (3x70 мс), потом держится и гаснет.
## Палитра поля — по зоне сейва: лес GRASS, поле/степь PATH, Пепелище ASH_GROUND,
## камень/снег/подземелье STONE (лист рисовал les/pole/pepelishche — тот же приём).
static func death_shadow(pos: Vector2) -> void:
	if not enabled():
		return
	var fam := _fam_for_area(String(GameState.area))
	_anim("shad_" + fam, 3, float(T_SHAD_MS), pos + Vector2(0, 6), 0.0, -2, 1, 0.25, 0.2, null)

static func _fam_for_area(area: String) -> String:
	if area.contains("ash"):
		return "ASH_GROUND"
	if area.contains("steppe") or area.contains("desert") or area.contains("field") \
			or area.contains("pole"):
		return "PATH"
	if area.contains("snow") or area.contains("castle") or area.contains("dungeon") \
			or area.contains("cave") or area.contains("stone"):
		return "STONE"
	return "GRASS"

## Для стендов: сколько живых bold-эффектов в дереве.
static func live_count() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	return tree.get_nodes_in_group("boldfx").size()

## Для стендов: сброс состояния тумблера/комбо между прокторами.
static func reset_state() -> void:
	_combo_n = 0
	_combo_ms = -100000
