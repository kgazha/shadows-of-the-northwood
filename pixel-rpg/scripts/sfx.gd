class_name Sfx
extends Node
## Звук v1 (t31): движок процедурных эффектов. Синглтон по образцу GameAudio:
## world.gd создаёт узел в _ready() (I ставит _enter_tree); вне мира — Sfx.ensure()
## навешивает хост на root (QA-стенды). GameAudio остаётся на своих Кенни-сэмплах
## для фоновых событий (шаги, свитки, музыка); процедурный каталог Sfx забирает
## ключевые события боя/экономики/UI — в точках хука прежний GameAudio.sfx ЗАМЕНЁН,
## а не задвоен, значит двух звуков на одно событие нет.
##
## Гарантии:
##  * буферы каталога собраны ОДИН раз при рождении узла — в кадре не считаем
##    ничего (FPS на 640x360 не двигается: ни _process, ни аллокаций на выстрел);
##  * тишина при бездействии: плееры молчат, таймеров нет;
##  * троттл: не чаще THROTTLE_MS на ключ + жёсткий потолок MAX_VOICES
##    одновременных голосов («как Juice» — лишние вызовы отбрасываются, не ждут);
##  * шины Master/SFX/Music идемпотентны (совместимы с GameAudio._ensure_bus);
##  * громкости: живое зеркало GameAudio.I, НО источник истины между запусками —
##    meta-хранилище GameState.flags с ключами audio.master/audio.sfx/audio.music
##    (нейтральный префикс: rs./meta.vd/meta.mb не трогает; вайп круга audio.*
##    переживает — он чистит только q./ashen./ng.boss_/tal./rs.).
##    При старте meta перезаписывает user://audio_cfg.json (мета вечна), запись
##    cfg на драг слайдера остаётся как было (пин qa_s2).

const POOL := 8                 # плееров в пуле (аллокаций на выстрел — ноль)
const MAX_VOICES := 6           # контракт: не более ~6 одновременных голосов
const DEFAULT_THROTTLE_MS := 40
const KEY_THROTTLE := {         # окно троттла под характер события
	"hit_a": 60, "hit_b": 60, "hurt": 120,
	"mob_die": 40, "mob_die_elite": 120,
	"grom_windup": 300, "grom_slam": 120,
	"potion": 120, "coin": 60,
	"ui_click": 30, "panel_open": 150, "dialog_step": 90,
	"altar": 250, "levelup": 300, "player_death": 800,
}

static var I: Sfx = null

var master_vol := GameAudio.DEF_VOL
var music_vol := GameAudio.DEF_VOL
var sfx_vol := GameAudio.DEF_VOL

var _streams := {}              # key -> AudioStreamWAV (каталог, собран при старте)
var _players: Array[AudioStreamPlayer] = []
var _until: Array[int] = []     # мс «до» занятости слота (модель голосов — своя,
								# не зависит от аудиодрайвера: headless предсказуем)
var _last := {}                 # key -> мс последнего запуска (троттл)
var _rr := 0
var _gen_ms := 0                # длительность сборки каталога (замер — qa_snd)
var _clock_shift := 0           # сдвиг часов для стенда (debug_advance)

func _enter_tree() -> void:
	# Последний рождённый — главный: при перезапуске мира новый Sfx вступает
	# ДО освобождения старого (old.free() в конце кадра), иначе I повис бы
	# пустым после _exit_tree старого узла.
	I = self

func _exit_tree() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.stop()
	if I == self:
		I = null

func _ready() -> void:
	_ensure_bus("SFX")
	_ensure_bus("Music")
	var t0 := Time.get_ticks_msec()
	_streams = SfxCatalog.build_all()
	_gen_ms = Time.get_ticks_msec() - t0
	for i in SfxCatalog.KEYS.size():
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
		_until.append(0)
	# громкости: зеркало GameAudio (он прочитал audio_cfg.json раньше нас),
	# затем meta audio.* поверх — она вечна и является источником истины.
	if GameAudio.I != null:
		master_vol = GameAudio.I.master_vol
		music_vol = GameAudio.I.music_vol
		sfx_vol = GameAudio.I.sfx_vol
	reload_from_meta()

# ---------------------------------------------------------------------------
# Статические обёртки: хукам не нужна проверка I (нет узла — тихий пропуск)
# ---------------------------------------------------------------------------

## Ленивое рождение хоста (QA-стенды без мира). В мире узел создаёт world._ready.
static func ensure() -> Sfx:
	if I != null and is_instance_valid(I):
		return I
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var h := tree.root.get_node_or_null("SfxHost")
	if h == null:
		h = Sfx.new()
		h.name = "SfxHost"
		# root может быть занят сборкой сцены — deferred (урок Juice); стенды
		# дожидаются кадра перед проверками.
		tree.root.add_child.call_deferred(h)
	return h as Sfx

## Запуск ключа каталога. true — звук взят в голос; false — нет узла/ключа,
## троттл или потолок голосов (спам запрещён контрактом).
static func play(key: String) -> bool:
	return I != null and is_instance_valid(I) and I._play(key)

static func keys() -> Array:
	return SfxCatalog.KEYS.duplicate()

static func stream(key: String) -> AudioStreamWAV:
	return I._streams.get(key) if I != null else null

static func gen_ms() -> int:
	return I._gen_ms if I != null else -1

# --- громкости -------------------------------------------------------------

## kind: "master" | "music" | "sfx". Применить сразу + (save) persist в meta.
static func set_volume(kind: String, v: float, save: bool = true) -> void:
	if I == null or not is_instance_valid(I):
		return
	I._set_volume(kind, v, save)

static func get_volume(kind: String) -> float:
	if I == null:
		return GameAudio.DEF_VOL
	match kind:
		"master": return I.master_vol
		"music": return I.music_vol
		"sfx": return I.sfx_vol
	return GameAudio.DEF_VOL

## Тройная запись из settings_menu (по отпусканию слайдера и «Сбросу»).
static func persist_volumes(master: float, music: float, sfx: float) -> void:
	if I != null and is_instance_valid(I):
		I.master_vol = clampf(master, 0.0, 1.0)
		I.music_vol = clampf(music, 0.0, 1.0)
		I.sfx_vol = clampf(sfx, 0.0, 1.0)
		I._apply_buses()
		I._persist()
	else:
		# хоста нет — meta всё равно должна пережить запуск
		GameState.flags["audio.master"] = clampf(master, 0.0, 1.0)
		GameState.flags["audio.music"] = clampf(music, 0.0, 1.0)
		GameState.flags["audio.sfx"] = clampf(sfx, 0.0, 1.0)
		GameState.save_game()

## «Перезапуск»: достать audio.* из meta и применить к шинам (вызывается из
## _ready; стенд проверяет имитацию нового запуска прямым вызовом).
static func reload_from_meta() -> void:
	if I != null and is_instance_valid(I):
		I._reload_from_meta()

# --- QA-инспекция (стенд qa_snd) ---------------------------------------------

static func debug_active() -> int:
	return I._active_voices() if I != null else 0

## Освободить все голоса и окна троттла (стенд прогоняет ключи по одному).
static func debug_clear() -> void:
	if I == null:
		return
	for i in I._until.size():
		I._until[i] = 0
	I._last.clear()

## Сдвинуть внутреннее часы на ms (стенд «перематывает» троттл и затухание
## голосов без реальных пауз — headless-тики не привязаны к wall-clock).
static func debug_advance(ms: int) -> void:
	if I != null:
		I._clock_shift += ms

# ---------------------------------------------------------------------------
# Внутренности
# ---------------------------------------------------------------------------

func _now() -> int:
	return Time.get_ticks_msec() + _clock_shift

func _play(key: String) -> bool:
	var s: AudioStreamWAV = _streams.get(key)
	if s == null:
		push_warning("Sfx: нет ключа в каталоге: %s" % key)
		return false
	var now := _now()
	var win := int(KEY_THROTTLE.get(key, DEFAULT_THROTTLE_MS))
	if now - int(_last.get(key, -1000000)) < win:
		return false                       # троттл: шквал одинаковых событий глушится
	if _active_voices() >= MAX_VOICES:
		return false                       # потолок голосов: лишний — тише, чем стыднее
	var idx := -1
	for i in _until.size():
		var j := (_rr + i) % _until.size()
		if _until[j] <= now:
			idx = j
			break
	if idx < 0:
		return false
	_rr = (idx + 1) % _until.size()
	var p := _players[idx]
	p.stream = s
	p.volume_db = linear_to_db(maxf(float(SfxCatalog.GAIN.get(key, 0.8)), 0.0001))
	p.pitch_scale = 1.0 + (randf() * 0.06 - 0.03)   # живой разброс повторов
	p.play()
	_until[idx] = now + int(ceilf(s.get_length() * 1000.0)) + 25
	_last[key] = now
	return true

func _active_voices() -> int:
	var now := _now()
	var n := 0
	for u in _until:
		if u > now:
			n += 1
	return n

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var idx := AudioServer.get_bus_count()
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _set_volume(kind: String, v: float, save: bool) -> void:
	var c := clampf(v, 0.0, 1.0)
	match kind:
		"master": master_vol = c
		"music": music_vol = c
		"sfx": sfx_vol = c
		_: return
	_apply_buses()
	if save:
		_persist()

## Владелец шин — GameAudio, когда он есть (его set_volumes обновляет и его
## var'ы, и аудио_cfg.json-наследование не ломает); без мира — пишем в AudioServer.
func _apply_buses() -> void:
	if GameAudio.I != null and is_instance_valid(GameAudio.I):
		GameAudio.I.set_volumes(music_vol, sfx_vol, master_vol, false)
		return
	var pairs := [["Master", master_vol], ["Music", music_vol], ["SFX", sfx_vol]]
	for pair in pairs:
		var idx := AudioServer.get_bus_index(String(pair[0]))
		if idx < 0:
			continue
		var v := float(pair[1])
		AudioServer.set_bus_mute(idx, v <= 0.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))

func _persist() -> void:
	GameState.flags["audio.master"] = master_vol
	GameState.flags["audio.music"] = music_vol
	GameState.flags["audio.sfx"] = sfx_vol
	GameState.save_game()   # прецедент Ash.spend: meta-изменение обязано пережить выход

func _reload_from_meta() -> void:
	var f: Dictionary = GameState.flags
	var applied := false
	if f.has("audio.master"):
		master_vol = clampf(GameState._numf(f["audio.master"], master_vol), 0.0, 1.0)
		applied = true
	if f.has("audio.music"):
		music_vol = clampf(GameState._numf(f["audio.music"], music_vol), 0.0, 1.0)
		applied = true
	if f.has("audio.sfx"):
		sfx_vol = clampf(GameState._numf(f["audio.sfx"], sfx_vol), 0.0, 1.0)
		applied = true
	if applied:
		_apply_buses()
