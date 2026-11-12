class_name GameAudio
extends Node
## Звуковая подсистема без autoload (project.godot не трогаем): единственный
## синглтон — static var I; world.gd создаёт узел в _ready() и присваивает I.
## Шины "Music" и "SFX" (обе в Master) создаются при старте; громкости живут в
## user://audio_cfg.json. Любое отсутствующее имя/файл — тихий пропуск, игра
## не падает (guarded ResourceLoader.exists + кэш потоков). Битый/рукописный
## audio_cfg.json (t37 V-01) переживает так же молча: нечисловые значения -> дефолт,
## шины применяются ВСЕГДА (_vol_of + явный _apply_bus_volumes в _ready).
## Kenney RPG-сэмплы: CC0, https://github.com/Boyquotes/kenney-rpg-audio-for-godot ;
## ui_*.ogg — собственный синтез (tools/gen_ui_sfx.js + ffmpeg libvorbis), original, CC0.

## Реестр эффектов: имя -> путь. Файл может отсутствовать (например "spell"
## готовит другая команда) — play_sfx это переживает молча.
const SFX := {
	"attack": "res://assets/sfx/knife_slice.ogg",
	"attack_alt": "res://assets/sfx/draw_knife_1.ogg",
	"step1": "res://assets/sfx/footstep_0.ogg",
	"step2": "res://assets/sfx/footstep_2.ogg",
	"roll": "res://assets/sfx/cloth_1.ogg",
	"drop": "res://assets/sfx/drop_leather.ogg",
	"coin": "res://assets/sfx/handle_coins_2.ogg",
	"belt": "res://assets/sfx/belt_handle_1.ogg",
	"book": "res://assets/sfx/book_open.ogg",
	"potion": "res://assets/sfx/metal_pot_2.ogg",
	"ui_click": "res://assets/sfx/ui_click.ogg",
	"ui_confirm": "res://assets/sfx/ui_confirm.ogg",
	"ui_deny": "res://assets/sfx/ui_deny.ogg",
	"ui_levelup": "res://assets/sfx/ui_levelup.ogg",
	"spell": "res://assets/sfx/spell.ogg",
}
## Реестр музыкальных тем (assets/music, готовые бесшовные лупы «loop-tail»).
const MUSIC := {
	# OGG вместо WAV: 21.5 МБ -> 1.5 МБ (ffmpeg libvorbis -q 5). Исходники WAV
	# исключены из экспорта фильтром в export_presets.cfg, в репозитории — эталон.
	"forest": "res://assets/music/theme_forest.ogg",
	"cave": "res://assets/music/theme_cave.ogg",
	"tension": "res://assets/music/theme_tension.ogg",
}

const CFG_PATH := "user://audio_cfg.json"
const DEF_VOL := 0.8           # громкость по умолчанию (0..1)
const SFX_POOL := 8            # фиксированный пул плееров: никаких аллокаций на выстрел
const CROSSFADE := 1.5         # сек. перетекания музыкальных тем
const MIN_LIN := 0.0001        # linear_to_db(0) = -inf, нижняя граница эквивалентна тишине

static var I: GameAudio        # синглтон; назначает world.gd (fallback — _enter_tree)

var music_vol := DEF_VOL
var sfx_vol := DEF_VOL
var master_vol := DEF_VOL       # шина Master (общая громкость); mute при 0 — как Music/SFX
var _players: Array[AudioStreamPlayer] = []   # пул SFX
var _rr := 0                                  # курсор переиспользования занятого пула
var _mus: Array[AudioStreamPlayer] = []       # плееры музыки (до 2 на кроссфейд)
var _mus_cur: AudioStreamPlayer = null
var _cur_music := ""
var _streams := {}                            # кэш path -> AudioStream|null (null = нет файла)
var _warned := {}                             # push_warning один раз на имя, не спамить в консоль

func _enter_tree() -> void:
	if I == null:
		I = self

## Уборка при выходе: остановить плееры, сбросить stream, отпустить кэш.
## Известный артефакт движка (Godot 4.7.2): при завершении процесса движок
## сам гасит воспроизведение ДО этой уборки, поэтому в конце лога может мелькнуть
## «WARNING: 2 ObjectDB instances leaked / 1 resources still in use»
## (AudioStreamPlaybackWAV + WAV). Предупреждение каскадно-косметическое: на геймплей,
## сохранения и звук в рантайме не влияет, SCRIPT ERROR нет ни при каком прогоне.
func _exit_tree() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in _mus:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_mus.clear()
	_streams.clear()
	if I == self:
		I = null

func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load_cfg()
	# t37 V-01 (гарантия вместо finally): шины обязан дёрнуть КАЖДЫЙ старт, даже
	# если загрузка конфига когда-нибудь оборвётся раньше — идемпотентно, копейки.
	_apply_bus_volumes()
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

# --- статические обёртки: хукам не нужна проверка I в каждом вызове ---

static func sfx(name: String, volume: float = 1.0, pitch: float = 1.0) -> void:
	if I != null:
		I.play_sfx(name, volume, pitch)

static func music(name: String) -> void:
	if I != null:
		I.play_music(name)

# --- эффекты: пул из 8 плееров ---

## true — поток найден и запущен; false — имя/файл отсутствует (тихий пропуск).
## Занятый плеер переиспользуется по кругу: «активных» никогда не больше SFX_POOL.
func play_sfx(name: String, volume: float = 1.0, pitch: float = 1.0) -> bool:
	var path := String(SFX.get(name, ""))
	if path == "":
		_warn_once(name, "Нет эффекта в реестре: %s" % name)
		return false
	var s := _stream(path)
	if s == null:
		_warn_once(name, "Нет файла звука: %s" % path)
		return false
	var p := _free_player()
	p.stream = s
	p.volume_db = linear_to_db(maxf(volume, MIN_LIN))
	p.pitch_scale = maxf(pitch, 0.05)
	p.play()
	return true

func _free_player() -> AudioStreamPlayer:
	# сначала свободный, иначе старейший по кругу (звук просто перезапустится)
	for i in SFX_POOL:
		var idx := (_rr + i) % SFX_POOL
		if not _players[idx].is_playing():
			_rr = (idx + 1) % SFX_POOL
			return _players[idx]
	var p := _players[_rr]
	_rr = (_rr + 1) % SFX_POOL
	return p

# --- музыка: кроссфейд CROSSFADE секунд, зацикливание ---

## Повторный вызов с той же играющей темой — no-op (плееры не плодятся).
func play_music(name: String) -> void:
	var path := String(MUSIC.get(name, ""))
	if path == "":
		_warn_once(name, "Нет темы в реестре: %s" % name)
		return
	var s := _stream(path)
	if s == null:
		_warn_once(name, "Нет файла музыки: %s" % path)
		return
	if _cur_music == name and _mus_cur != null and _mus_cur.playing:
		return
	_enforce_loop(s)
	# гасим прежнюю тему (если была) — и освобождаем её плеер кроссфейдом
	var old := _mus_cur
	if old != null:
		var tf := create_tween()
		tf.tween_property(old, "volume_db", linear_to_db(MIN_LIN), CROSSFADE)
		tf.tween_callback(func() -> void:
			if is_instance_valid(old):
				old.stop())
	var p := _music_player()
	p.stream = s
	p.volume_db = linear_to_db(MIN_LIN)
	_mus_cur = p
	_cur_music = name
	p.play()
	var t := create_tween()
	t.tween_property(p, "volume_db", 0.0, CROSSFADE)

func stop_music() -> void:
	_cur_music = ""
	var old := _mus_cur
	_mus_cur = null
	if old != null and old.is_playing():
		var t := create_tween()
		t.tween_property(old, "volume_db", linear_to_db(MIN_LIN), CROSSFADE)
		t.tween_callback(func() -> void:
			if is_instance_valid(old):
				old.stop())

## Плеер музыки: из «отдохнувших» (не играют), иначе один новый; их не больше
## двух одновременно (старый всегда гаснет за CROSSFADE и потом переиспользуется).
func _music_player() -> AudioStreamPlayer:
	for p in _mus:
		if not p.is_playing():
			return p
	var np := AudioStreamPlayer.new()
	np.bus = "Music"
	add_child(np)
	_mus.append(np)
	return np

## Зациклить без зависимости от настроек импорта: WAV — LOOP_FORWARD на весь
## файл (loop_end = ЧИСЛО КАДРОВ = length*mix_rate, вниз; для stereo это НЕ
## половина data.size()); Ogg — loop=true. Иные типы оставляем как есть.
static func _enforce_loop(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = maxi(int(w.get_length() * float(w.mix_rate)), 1)
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true

# --- громкости: шины + user://audio_cfg.json ---

## master < 0 — не менять общую громкость (обратная совместимость старых вызовов).
## save=false — применить к шинам без записи user://audio_cfg.json (перетаскивание
## слайдера: live-звук без IO на каждый шаг; сохранение — по отпусканию).
func set_volumes(music: float, sfx: float, master: float = -1.0, save: bool = true) -> void:
	music_vol = clampf(music, 0.0, 1.0)
	sfx_vol = clampf(sfx, 0.0, 1.0)
	if master >= 0.0:
		master_vol = clampf(master, 0.0, 1.0)
	_apply_bus_volumes()
	if save:
		_save_cfg()

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	# add_bus() в Godot 4 возвращает void: позицию считаем сами (вставка в конец)
	var idx := AudioServer.get_bus_count()
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	_apply_bus_volumes()

func _apply_bus_volumes() -> void:
	for pair in [["Master", master_vol], ["Music", music_vol], ["SFX", sfx_vol]]:
		var idx := AudioServer.get_bus_index(String(pair[0]))
		if idx < 0:
			continue
		var v := float(pair[1])
		AudioServer.set_bus_mute(idx, v <= 0.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, MIN_LIN)))

func _save_cfg() -> void:
	var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Не удалось записать %s" % CFG_PATH)
		return
	f.store_string(JSON.stringify({"master": master_vol, "music": music_vol, "sfx": sfx_vol}))

## t37 V-01: безопасная конверсия значения audio_cfg.json. В GDScript 4 float("abra")
## — рантайм-ошибка, и в старом коде она обрывала _load_cfg ДО _apply_bus_volumes():
## шины оставались на заводских 0 дБ, а music/sfx из конфига не дочитывались.
## Семантика — как GameState._numf (именно так Sfx клампит мусор в meta audio.*,
## sfx.gd:259-272): число — оно (NaN/Inf -> дефолт), числовая строка — число, всё
## прочее (bool/null/массив/текст) — дефолт; результат всегда в 0..1.
func _vol_of(v: Variant, def: float) -> float:
	var d := clampf(def, 0.0, 1.0)
	match typeof(v):
		TYPE_INT:
			return clampf(float(v), 0.0, 1.0)
		TYPE_FLOAT:
			return d if (is_nan(float(v)) or is_inf(float(v))) else clampf(float(v), 0.0, 1.0)
		TYPE_STRING:
			var s := String(v)
			if not s.is_valid_float():
				push_warning("audio_cfg.json: «%s» не число — берём %.2f" % [s, d])
				return d
			return clampf(s.to_float(), 0.0, 1.0)
		_:
			push_warning("audio_cfg.json: значение типа %d не число — берём %.2f" % [typeof(v), d])
			return d

func _load_cfg() -> void:
	# t37 V-01: полный сброс к дефолту (раньше master «доживал» значение прошлого
	# чтения, если ключа в конфиге нет) — загрузка конфига детерминирована.
	master_vol = DEF_VOL
	music_vol = DEF_VOL
	sfx_vol = DEF_VOL
	if FileAccess.file_exists(CFG_PATH):
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var data: Variant = JSON.parse_string(txt)
			if typeof(data) == TYPE_DICTIONARY:
				master_vol = _vol_of(data.get("master", DEF_VOL), DEF_VOL)
				music_vol = _vol_of(data.get("music", DEF_VOL), DEF_VOL)
				sfx_vol = _vol_of(data.get("sfx", DEF_VOL), DEF_VOL)
			# обрезанный при крахе/не-JSON файл: parse_string -> null -> тихий дефолт
	_apply_bus_volumes()

# --- кэш потоков: ResourceLoader.exists ДО load, повторные load дешевле ---

func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res is AudioStream:
			s = res
	if s == null:
		push_warning("Нет файла звука: %s" % path)
	_streams[path] = s
	return s

func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)
