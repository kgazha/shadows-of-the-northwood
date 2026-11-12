class_name SfxCatalog
extends RefCounted
## Звук v1 (t31): каталог ПРОЦЕДУРНЫХ звуков — без единого внешнего ассета.
##
## Буферы генерируются один раз при старте мира (Sfx.ensure -> build_all),
## дальше только переигрывание готовых AudioStreamWAV: нулевая стоимость в
## кадре, FPS не проседает. Канон палитры — «тёплый, приглушённый, северный»:
## синусы и редкие гармоники, шум сквозь однополюсный ФНЧ, медленные глисса,
## tanh-насыщение для «маслянистой» теплоты. Никаких квадратных/пилообразных
## «чиптюн»-блипов: спектр каждого ключа снизу-тяжёлый (замер — стенд qa_snd).
##
## Формат: 22 050 Гц, моно, 16 бит. Найквист 11 кГц для приглушённой палитры
## за глаза; половина стоимости генерации и памяти против 44,1 к. Детерминизм:
## шум — по фиксированному seed, повторная сборка байт-в-байт.

const RATE := 22050
const PEAK := 0.92            # нормализация пика: одинаковая громкость сборки
const ATT := 0.003            # все щели ADSR в секундах
const TAIL := 0.008

## Каталог: key -> функция сборки (build()). 15 ключей >= контрактных 12.
const KEYS := ["hit_a", "hit_b", "hurt", "mob_die", "mob_die_elite",
	"grom_windup", "grom_slam", "potion", "coin", "ui_click", "panel_open",
	"dialog_step", "altar", "levelup", "player_death"]

## Сведение каталога: относительная громкость ключа при воспроизведении
## (шина SFX и Master — поверх, см. sfx.gd).
const GAIN := {
	"hit_a": 0.90, "hit_b": 0.90, "hurt": 0.85,
	"mob_die": 0.80, "mob_die_elite": 0.92,
	"grom_windup": 0.72, "grom_slam": 1.00,
	"potion": 0.75, "coin": 0.60,
	"ui_click": 0.50, "panel_open": 0.55, "dialog_step": 0.50,
	"altar": 0.62, "levelup": 0.75, "player_death": 1.00,
}

## Собрать весь каталог: key -> AudioStreamWAV.
static func build_all() -> Dictionary:
	var out := {}
	for k in KEYS:
		out[String(k)] = build(String(k))
	return out

static func build(key: String) -> AudioStreamWAV:
	return _wav(_compose(key), _drive(key))

static func _drive(key: String) -> float:
	match key:
		"grom_slam": return 4.0
		"hurt": return 3.2
		"ui_click", "mob_die_elite", "panel_open": return 2.8
		"hit_b", "player_death": return 2.6
		"dialog_step": return 2.4
		"hit_a", "mob_die", "coin", "grom_windup": return 2.2
		"potion", "levelup": return 1.8
		"altar": return 1.5
		_: return 2.0

# ---------------------------------------------------------------------------
# Композиции ключей. Приёмы: короткий тональный «удар» + шум сквозь ФНЧ,
# экспоненциальный спад (D/R в ADSR), нарастание для телеграфов, медленные
# нисходящие глисса для смертей; tanh-скраб (drive) добавляет чётных гармоник
# — «масло», а не стекло.
# ---------------------------------------------------------------------------

static func _compose(key: String) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	match key:
		"hit_a":
			b = _buf(0.14)
			_tone(b, 0.0, 0.12, 150.0, 72.0, 1.0, 0.045)
			_tone(b, 0.0, 0.06, 340.0, 200.0, 0.45, 0.03)
			_noise(b, 0.0, 0.09, 0.55, 0.03, 950.0, 11)
		"hit_b":
			b = _buf(0.16)
			_tone(b, 0.0, 0.14, 118.0, 56.0, 1.0, 0.05)
			_tone(b, 0.004, 0.08, 240.0, 150.0, 0.40, 0.035)
			_noise(b, 0.0, 0.11, 0.60, 0.04, 760.0, 12)
		"hurt":
			b = _buf(0.30)
			_tone(b, 0.0, 0.26, 96.0, 46.0, 1.0, 0.09)
			_tone(b, 0.0, 0.12, 190.0, 90.0, 0.5, 0.05)
			_noise(b, 0.0, 0.20, 0.70, 0.07, 430.0, 21)
		"mob_die":
			b = _buf(0.42)
			_tone(b, 0.0, 0.40, 320.0, 105.0, 1.0, 0.13, 0.25)
			_tone(b, 0.0, 0.08, 540.0, 300.0, 0.30, 0.03)
			_noise(b, 0.0, 0.25, 0.40, 0.08, 820.0, 31)
		"mob_die_elite":
			b = _buf(0.72)
			_tone(b, 0.0, 0.68, 190.0, 50.0, 1.0, 0.22, 0.20)
			_tone(b, 0.0, 0.60, 95.0, 38.0, 0.8, 0.26)
			_noise(b, 0.0, 0.40, 0.50, 0.14, 480.0, 41)
		"grom_windup":
			# телеграф замаха (WINDUP_TIME = 0.5): нарастающий гул с тремоло —
			# звук «набирающейся массы», а не сигнал тревоги.
			b = _buf(0.56)
			_swell(b, 0.0, 0.54, 52.0, 135.0, 1.0, 17.0, 0.30)
			_swell_noise(b, 0.0, 0.50, 0.55, 420.0, 51)
		"grom_slam":
			b = _buf(0.62)
			_tone(b, 0.0, 0.55, 47.0, 30.0, 1.2, 0.20)
			_tone(b, 0.0, 0.25, 110.0, 45.0, 0.7, 0.07)
			_tone(b, 0.0, 0.03, 300.0, 180.0, 0.35, 0.015)
			_noise(b, 0.0, 0.35, 0.95, 0.10, 300.0, 61)
		"potion":
			# три тёплых «булька» вверх + вибрирующий осадок
			b = _buf(0.46)
			_tone(b, 0.00, 0.09, 300.0, 390.0, 0.9, 0.045)
			_tone(b, 0.09, 0.09, 430.0, 540.0, 0.85, 0.045)
			_tone(b, 0.18, 0.12, 580.0, 700.0, 0.80, 0.06)
			_tone(b, 0.26, 0.20, 250.0, 235.0, 0.35, 0.10, 0.0, 6.0, 0.30)
			_noise(b, 0.02, 0.16, 0.25, 0.05, 1300.0, 71)
		"coin":
			# приглушённый металлический дуэт: не «стеклянный» чиптюн-звон, а тёплое
			# серебро — негармонические частички тихие и коротко живущие.
			b = _buf(0.34)
			_tone(b, 0.00, 0.28, 910.0, 895.0, 0.50, 0.09, 0.18)
			_tone(b, 0.00, 0.12, 2512.0, 2470.0, 0.12, 0.04)
			_tone(b, 0.06, 0.26, 1150.0, 1132.0, 0.45, 0.10, 0.15)
			_tone(b, 0.06, 0.10, 3174.0, 3120.0, 0.08, 0.03)
		"ui_click":
			# деревянная «щёл-книжка»: щёлк ФНЧ-шумом + низкий корпус
			b = _buf(0.06)
			_noise(b, 0.0, 0.022, 0.90, 0.008, 1150.0, 101)
			_tone(b, 0.0, 0.05, 195.0, 160.0, 0.7, 0.014)
		"panel_open":
			# скрип кожи/дерева: короткий глисс вверх + шорох
			b = _buf(0.22)
			_tone(b, 0.00, 0.18, 128.0, 186.0, 0.75, 0.07)
			_tone(b, 0.05, 0.12, 150.0, 205.0, 0.35, 0.06)
			_noise(b, 0.0, 0.15, 0.50, 0.05, 620.0, 111)
		"dialog_step":
			# мягкий постук «далее» — тихий и короткий, чтобы не утомлять
			b = _buf(0.075)
			_tone(b, 0.0, 0.06, 262.0, 205.0, 0.7, 0.018)
			_noise(b, 0.0, 0.028, 0.45, 0.01, 880.0, 121)
		"altar":
			# аккорд A–E–A (+октава-подсветка): северная ладовая пустота,
			# медленная атака ~0.2 с — «алтарь дышит»
			b = _buf(0.92)
			_tone(b, 0.0, 0.88, 110.0, 110.0, 0.70, 0.40, 0.15, 0.0, 0.0, 0.22)
			_tone(b, 0.0, 0.88, 165.0, 165.0, 0.60, 0.42, 0.10, 0.0, 0.0, 0.24)
			_tone(b, 0.0, 0.88, 220.0, 220.0, 0.45, 0.45, 0.08, 0.0, 0.0, 0.26)
			_tone(b, 0.0, 0.86, 330.0, 330.0, 0.16, 0.50, 0.0, 4.0, 0.50, 0.30)
			_noise(b, 0.0, 0.50, 0.18, 0.30, 340.0, 81)
		"levelup":
			# G–C–G квартёвый подъём — тепло, без фанфарного «дзынь»
			b = _buf(0.74)
			_tone(b, 0.00, 0.50, 196.0, 196.0, 0.75, 0.16, 0.30)
			_tone(b, 0.11, 0.50, 261.63, 261.63, 0.70, 0.16, 0.28)
			_tone(b, 0.22, 0.45, 392.0, 392.0, 0.70, 0.15, 0.22)
			_tone(b, 0.34, 0.40, 196.0, 196.0, 0.35, 0.18)
			_tone(b, 0.34, 0.40, 261.63, 261.63, 0.30, 0.18)
			_tone(b, 0.34, 0.40, 392.0, 392.0, 0.25, 0.18)
		"player_death":
			# низкий нисходящий тон контракта: 110 -> 40 Гц за 1.5 с, с квинтой
			b = _buf(1.62)
			_tone(b, 0.0, 1.55, 110.0, 40.0, 1.0, 0.55, 0.0, 5.0, 0.25, 0.02)
			_tone(b, 0.0, 1.40, 82.4, 30.0, 0.55, 0.60, 0.0, 0.0, 0.0, 0.05)
			_noise(b, 0.0, 0.90, 0.25, 0.40, 230.0, 91)
		_:
			push_warning("SfxCatalog: неизвестный ключ %s" % key)
	return b

# ---------------------------------------------------------------------------
# Синтезные строительные блоки
# ---------------------------------------------------------------------------

static func _buf(dur_s: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(8, int(dur_s * float(RATE))))
	return b

## Тональный компонент ADSR: атака att_s, экспоненциальный спад tau_s, хвост
## tail_s; глисса частоты f0->f1; harm — доля 2-й гармоники; тремоло trem.
static func _tone(buf: PackedFloat32Array, at_s: float, dur_s: float,
		f0: float, f1: float, amp: float, tau_s: float,
		harm: float = 0.0, trem_hz: float = 0.0, trem_depth: float = 0.0,
		att_s: float = ATT) -> void:
	var rate := float(RATE)
	var n := int(dur_s * rate)
	var off := int(at_s * rate)
	if n <= 2:
		return
	var att_n := clampi(int(att_s * rate), 2, n - 1)
	var tail_n := clampi(int(TAIL * rate), 2, n - 1)
	var dec := exp(-1.0 / (maxf(tau_s, 0.001) * rate))
	var a := amp
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		ph += (f0 + (f1 - f0) * u) / rate
		var val := sin(TAU * ph)
		if harm > 0.0:
			val += harm * sin(TAU * ph * 2.0)
		var e := a
		if i < att_n:
			e = a * float(i) / float(att_n)
		elif i > n - tail_n:
			e = a * float(n - i) / float(tail_n)
		if trem_hz > 0.0:
			e *= 1.0 + trem_depth * sin(TAU * trem_hz * float(i) / rate)
		var j := off + i
		if j < buf.size():
			buf[j] += val * e
		a *= dec

## Шумовой компонент сквозь однополюсный ФНЧ (cutoff_hz) — тот же ADSR.
static func _noise(buf: PackedFloat32Array, at_s: float, dur_s: float,
		amp: float, tau_s: float, cutoff_hz: float, seed: int) -> void:
	var rate := float(RATE)
	var n := int(dur_s * rate)
	var off := int(at_s * rate)
	if n <= 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var att_n := clampi(int(0.001 * rate), 2, n - 1)
	var tail_n := clampi(int(TAIL * rate), 2, n - 1)
	var dec := exp(-1.0 / (maxf(tau_s, 0.001) * rate))
	var k := clampf(1.0 - exp(-TAU * cutoff_hz / rate), 0.0001, 1.0)
	var a := amp * 2.2               # ФНЧ съедает энергию шума — компенсируем
	var y := 0.0
	for i in n:
		y += k * ((rng.randf() * 2.0 - 1.0) - y)
		var e := a
		if i < att_n:
			e = a * float(i) / float(att_n)
		elif i > n - tail_n:
			e = a * float(n - i) / float(tail_n)
		var j := off + i
		if j < buf.size():
			buf[j] += y * e
		a *= dec

## Нарастание (телеграфы): огибающая u^1.8, глисса вверх, тремоло «вибрация».
static func _swell(buf: PackedFloat32Array, at_s: float, dur_s: float,
		f0: float, f1: float, amp: float,
		trem_hz: float, trem_depth: float) -> void:
	var rate := float(RATE)
	var n := int(dur_s * rate)
	var off := int(at_s * rate)
	if n <= 2:
		return
	var head := clampi(int(ATT * rate), 2, n - 1)
	var tail := clampi(int(0.02 * rate), 2, n - 1)
	var ph := 0.0
	for i in n:
		var u := float(i) / float(n)
		ph += (f0 + (f1 - f0) * (u * u)) / rate   # частота растёт быстрее амплитуды
		var e := amp * pow(u, 1.8)
		if i < head:
			e *= float(i) / float(head)
		elif i > n - tail:
			e *= float(n - i) / float(tail)
		if trem_hz > 0.0:
			e *= 1.0 + trem_depth * sin(TAU * trem_hz * float(i) / rate)
		var j := off + i
		if j < buf.size():
			buf[j] += sin(TAU * ph) * e

static func _swell_noise(buf: PackedFloat32Array, at_s: float, dur_s: float,
		amp: float, cutoff_hz: float, seed: int) -> void:
	var rate := float(RATE)
	var n := int(dur_s * rate)
	var off := int(at_s * rate)
	if n <= 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var head := clampi(int(ATT * rate), 2, n - 1)
	var tail := clampi(int(0.02 * rate), 2, n - 1)
	var k := clampf(1.0 - exp(-TAU * cutoff_hz / rate), 0.0001, 1.0)
	var y := 0.0
	for i in n:
		y += k * ((rng.randf() * 2.0 - 1.0) - y)
		var e := amp * 2.2 * pow(float(i) / float(n), 1.8)
		if i < head:
			e *= float(i) / float(head)
		elif i > n - tail:
			e *= float(n - i) / float(tail)
		var j := off + i
		if j < buf.size():
			buf[j] += y * e

## Обработка собранного буфера: tanh-скраб (теплота), страховочное затухание
## последних 10 мс и нормализация к PEAK — ровный сведённый каталог.
static func _post(buf: PackedFloat32Array, drive: float) -> void:
	if drive > 1.001:
		var c := tanh(drive)
		for i in buf.size():
			buf[i] = tanh(drive * buf[i]) / c
	var m := buf.size()
	var tail := mini(m, int(0.01 * float(RATE)))
	for i in tail:
		buf[m - 1 - i] *= float(i) / float(tail)
	var mx := 0.0
	for i in m:
		mx = maxf(mx, absf(buf[i]))
	if mx > 0.0001:
		var s := PEAK / mx
		for i in m:
			buf[i] *= s

## PackedFloat32Array -> AudioStreamWAV 16 бит mono (little-endian).
static func _wav(buf: PackedFloat32Array, drive: float) -> AudioStreamWAV:
	_post(buf, drive)
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		var v := clampi(int(buf[i] * 32767.0), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = false
	w.mix_rate = RATE
	w.data = data
	return w
