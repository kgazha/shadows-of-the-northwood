extends "res://mb_base.gd"
## qa_snd — t31 «звук v1»: процедурные SFX боя/UI/мира + аудио-шины + громкость
## в настройках. Мир НЕ поднимаем (паттерн qa_mb/qa_run): движок Sfx рождается
## через Sfx.ensure() на голом root — заодно проверяется прямой путь к шинам
## (GameAudio.I == null). GameAudio остаётся на своих Кенни-сэмплах для фоновых
## событий; стенд верифицирует: каталог >=12 ключей реальными буферами
## (не-тишина, анти-щелчок, «не чиптюн» по спектру), потолок 6 голосов, троттл,
## тишину при бездействии, шины Master/SFX/Music, громкости immediate + персист
## meta audio.* (переживает вайп круга и «перезапуск» узла) и разводку хуков
## по исходникам (замена, а не удвоение звука).
## t37 (фаза K, находки t36): робастность — грязный audio_cfg.json не роняет
## загрузку и не ломает шины (V-01), громкость имеет ОДИН источник истины —
## фактически применённый к шинам (V-03), пул голосов = ключи каталога, а не
## мёртвая константа (V-02).

const RATE := 22050             # канон каталога (sfx_catalog.gd)
const CFG_PATH := "user://audio_cfg.json"   # то же поле, что пишет/читает game_audio.gd
const HIGH_HZ := 4000.0         # порог «стеклянности»: выше — только тихие музыкальные частички
const HIGH_MAX := 0.15          # доля энергии >4кГц в ключе (замер каталога 0.119; калибровка — квадрат ниже)
const SQ_MIN := 0.25            # контрольный квадрат 2кГц обязан быть ярче этого
const SQ_SEP := 1.5             # …и не менее чем в столько раз ярче самого яркого ключа

var _hs_max := 0.0              # замер: самая «стеклянная» доля среди ключей

func _ready() -> void:
	GameState.toast.connect(func(t: String) -> void: toasts.append(t))
	Sfx.ensure()
	await get_tree().process_frame
	await get_tree().process_frame
	a_engine()
	b_buses()
	c_catalog()
	d_buffers()
	e_voices()
	f_throttle()
	g_playability()
	await h_restart()
	i_wiring()
	j_wipe()
	await k_robust()
	done()

# ---------------------------------------------------------------------------
# A: движок/хост

func a_engine() -> void:
	check("A: Sfx.ensure() вырастил хост (Sfx.I != null)", Sfx.I != null)
	check("A: повторный ensure() возвращает тот же хост", Sfx.ensure() == Sfx.I)
	var ks := Sfx.keys()
	check("A: каталог >= 12 ключей (контракт)", ks.size() >= 12)
	print("NOTE A: keys=%d gen_ms=%d" % [ks.size(), Sfx.gen_ms()])
	check("A: генерация каталога однократна и быстра (gen_ms < 1000)", Sfx.gen_ms() >= 0 and Sfx.gen_ms() < 1000)

# --- B: шины ---

func b_buses() -> void:
	var mi := AudioServer.get_bus_index("Master")
	var si := AudioServer.get_bus_index("SFX")
	var ui := AudioServer.get_bus_index("Music")
	check("B: шина SFX существует, send -> Master", si >= 0 and AudioServer.get_bus_send(si) == "Master")
	check("B: шина Music существует (stub-заглушка музыки), send -> Master", ui >= 0 and AudioServer.get_bus_send(ui) == "Master")
	check("B: шина Master существует", mi == 0)

# --- C: каталог/детерминизм ---

func c_catalog() -> void:
	var w1 := SfxCatalog.build("coin")
	var w2 := SfxCatalog.build("coin")
	check("C: детерминизм сборки (шум по seed): coin байт-в-байт", w1.data == w2.data)
	check("C: get_length() у coin совпал с данными",
		absf(w1.get_length() - float(w1.data.size()) / 2.0 / float(RATE)) < 0.001)

# --- D: каждый ключ — реальный тёплый буфер ---

func d_buffers() -> void:
	for key in Sfx.keys():
		var k := String(key)
		var w: AudioStreamWAV = Sfx.stream(k)
		if w == null:
			check("D[%s]: буфер построен" % k, false)
			continue
		var ok_meta: bool = w.format == AudioStreamWAV.FORMAT_16_BITS \
			and not w.stereo and w.mix_rate == RATE and SfxCatalog.GAIN.has(k)
		check("D[%s]: формат 16bit/mono/22050 + сведён в GAIN" % k, ok_meta)
		var s := _decode(w)
		var n := s.size()
		var pk := 0.0
		var e := 0.0
		for i in n:
			pk = maxf(pk, absf(s[i]))
			e += s[i] * s[i]
		var rms := sqrt(e / maxf(1.0, float(n)))
		var dur := float(n) / float(RATE)
		check("D[%s]: не-тишина и размер в рамках (dur=%.3f pk=%.3f rms=%.3f)" % [k, dur, pk, rms],
			n > 8 and dur >= 0.05 and dur <= 2.0 and pk > 0.02 and pk <= 0.93 and rms > 0.02 and rms < 0.70)
		# Анти-щелчок: ADSR гарантируют нули на стыках (щелчок = широкий спектр = «стекло»).
		check("D[%s]: анти-щелчок (начало %.5f, конец %.5f при пике %.3f)" % [k, absf(s[0]), absf(s[n - 1]), pk],
			absf(s[0]) <= 0.15 * pk and absf(s[n - 1]) <= 0.15 * pk)
		# Теплота: доля энергии выше 4кГц. Канон «тёплый, приглушённый»: шум только
		# сквозь ФНЧ, глисса низкие; контроль-квадрат 2кГц ниже обязан ломать порог.
		var hs := _high_share(s)
		_hs_max = maxf(_hs_max, hs)
		check("D[%s]: спектр приглушённый — энергия >4кГц = %.3f (<= %.2f)" % [k, hs, HIGH_MAX], hs <= HIGH_MAX)
	# Калибровка метрики: чиптюн-блип (квадрат 2кГц) обязан быть «стеклянным» —
	# иначе тест на «не чиптюн» ничего не проверяет.
	var sq := PackedFloat32Array()
	sq.resize(int(0.2 * RATE))
	for i in sq.size():
		sq[i] = 0.5 if fmod(float(i) * 2000.0 / float(RATE), 1.0) < 0.5 else -0.5
	var hs_sq := _high_share(sq)
	print("NOTE D: hs_max(keys)=%.3f hs_square=%.3f" % [_hs_max, hs_sq])
	check("D: метрика отличает чиптюн: квадрат 2кГц ярче %.2f (got %.3f)" % [SQ_MIN, hs_sq], hs_sq >= SQ_MIN)
	check("D: квадрат ярче самого яркого ключа в >= %.1f раз (%.3f vs %.3f)" % [SQ_SEP, hs_sq, _hs_max],
		hs_sq >= SQ_SEP * maxf(_hs_max, 0.001))

# --- E: потолок голосов (<= 6) и освобождение ---

func e_voices() -> void:
	Sfx.debug_clear()
	var played := 0
	for key in Sfx.keys():
		if Sfx.play(String(key)):
			played += 1
	check("E: шквал 15 разных ключей за кадр -> ровно 6 голосов (потолок контракта)",
		played == 6 and Sfx.debug_active() == 6)
	Sfx.debug_advance(4000)
	check("E: голоса гаснут по длительности (после перемотки активен 0)", Sfx.debug_active() == 0)

# --- F: троттл ключа ---

func f_throttle() -> void:
	Sfx.debug_clear()
	var t1 := Sfx.play("altar")
	var t2 := Sfx.play("altar")   # тот же ключ в том же окне — глушится
	Sfx.debug_advance(300)        # окно altar = 250 мс
	var t3 := Sfx.play("altar")
	check("F: троттл одного ключа (ok/glushit/ok)", t1 and not t2 and t3)
	Sfx.debug_clear()
	Sfx.debug_advance(4000)

# --- G: играбельность каждого ключа + тишина при бездействии ---

func g_playability() -> void:
	for key in Sfx.keys():
		var k := String(key)
		Sfx.debug_clear()
		check("G[%s]: запуск берётся в голос" % k, Sfx.play(k))
	Sfx.debug_clear()
	Sfx.debug_advance(4000)
	check("G: тишина при бездействии (после затухания активных голосов нет)", Sfx.debug_active() == 0)

# --- H: громкости: immediate + персист meta audio.* + «перезапуск» ---

func h_restart() -> void:
	var m_idx := AudioServer.get_bus_index("Master")
	var s_idx := AudioServer.get_bus_index("SFX")
	var u_idx := AudioServer.get_bus_index("Music")
	# immediate: шина дёргается сразу, без кадров и рестартов
	Sfx.set_volume("master", 0.4, true)
	check("H: master=0.4 применён сразу (шина Master db)",
		absf(AudioServer.get_bus_volume_db(m_idx) - linear_to_db(0.4)) < 0.01)
	check("H: master=0.4 отражён в get_volume", absf(Sfx.get_volume("master") - 0.4) < 0.001)
	check("H: persist=true записал audio.master в meta-флаги (и дефолты пары)",
		absf(float(GameState.flags.get("audio.master", -1.0)) - 0.4) < 0.001 \
		and absf(float(GameState.flags.get("audio.sfx", -1.0)) - GameAudio.DEF_VOL) < 0.001)
	var f := FileAccess.open("user://save_morkheim.json", FileAccess.READ)
	var txt := ""
	if f != null:
		txt = f.get_as_text()
		f.close()
	check("H: meta физически в сейве (audio.master в save_morkheim.json)", txt.contains("audio.master"))
	# save=false — только шины, meta не трогается
	Sfx.set_volume("sfx", 0.0, false)
	check("H: sfx=0 глушит шину SFX (mute) сразу", AudioServer.is_bus_mute(s_idx))
	check("H: save=false НЕ переписал audio.sfx в meta (там всё ещё дефолт)",
		absf(float(GameState.flags.get("audio.sfx", -1.0)) - GameAudio.DEF_VOL) < 0.001)
	# имитация нового запуска: «диск» (meta) диктует громкости
	GameState.flags["audio.sfx"] = 0.25
	GameState.flags["audio.music"] = 0.6
	Sfx.reload_from_meta()
	check("H: reload_from_meta вернул sfx=0.25 на шину",
		absf(Sfx.get_volume("sfx") - 0.25) < 0.001 \
		and absf(AudioServer.get_bus_volume_db(s_idx) - linear_to_db(0.25)) < 0.01)
	check("H: reload_from_meta вернул music=0.6 на шину Music",
		absf(Sfx.get_volume("music") - 0.6) < 0.001 \
		and absf(AudioServer.get_bus_volume_db(u_idx) - linear_to_db(0.6)) < 0.01)
	# настоящий «перезапуск»: убить хост, вырастить заново — meta переживает
	var old: Node = Sfx.I
	if old != null:
		old.free()
	await get_tree().process_frame
	var again := Sfx.ensure()
	await get_tree().process_frame
	check("H: хост переродился после free()", again != null and Sfx.I != null)
	check("H: после перезапуска громкости взяты из meta (0.4/0.6/0.25)",
		absf(Sfx.get_volume("master") - 0.4) < 0.001 and absf(Sfx.get_volume("music") - 0.6) < 0.001 \
		and absf(Sfx.get_volume("sfx") - 0.25) < 0.001)
	check("H: после перезапуска шина SFX снова на 0.25",
		absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.25)) < 0.01)

# --- I: разводка хуков по исходникам (замена, а не удвоение) ---

func i_wiring() -> void:
	var p := _src("res://scripts/player.gd")
	check("I: player.gd — два удара hit_a/hit_b чередованием",
		p.contains("Sfx.play(\"hit_a\" if _swing_alt else \"hit_b\")"))
	check("I: player.gd — получение урона hurt", p.contains("Sfx.play(\"hurt\""))
	check("I: player.gd — старый Kenney-удар СНЯТ (нет удвоения)", not p.contains("GameAudio.sfx(\"attack\")"))
	check("I: player.gd — пин qa_wr жив (ui_deny на отказе рывка)", p.contains("GameAudio.sfx(\"ui_deny\")"))
	var w := _src("res://scripts/world.gd")
	check("I: world.gd — смерть героя = низкий нисходящий тон", w.contains("Sfx.play(\"player_death\")"))
	check("I: world.gd — хост Sfx создаётся при старте мира", w.contains("Sfx.new()"))
	check("I: world.gd — старый «шлепок» смерти СНЯТ", not w.contains("GameAudio.sfx(\"drop\")"))
	var h := _src("res://scripts/hud.gd")
	check("I: hud.gd — продвинуть диалог", h.contains("Sfx.play(\"dialog_step\")"))
	check("I: hud.gd — уровень/ранг", h.contains("Sfx.play(\"levelup\")") and not h.contains("ui_levelup"))
	check("I: hud.gd — клик UI (зелье)", h.contains("Sfx.play(\"ui_click\")"))
	var sh := _src("res://scripts/shop.gd")
	check("I: shop.gd — открытие панели", sh.contains("Sfx.play(\"panel_open\")"))
	check("I: shop.gd — золото/покупка", sh.contains("Sfx.play(\"coin\")"))
	check("I: shop.gd — алтарь/благословение", sh.contains("Sfx.play(\"altar\")"))
	var al := _src("res://scripts/alchemy.gd")
	check("I: alchemy.gd — зелье (варка + глоток)", _count(al, "Sfx.play(\"potion\")") >= 2 \
		and not al.contains("GameAudio.sfx(\"potion\")"))
	var sl := _src("res://scripts/slime.gd")
	check("I: slime.gd — смерть моба (рядовая)", sl.contains("Sfx.play(\"mob_die\")") \
		and not sl.contains("GameAudio.sfx(\"drop\")"))
	var br := _src("res://scripts/brute.gd")
	check("I: brute.gd — телеграф замаха Грома", br.contains("Sfx.play(\"grom_windup\")"))
	check("I: brute.gd — удар Грома", br.contains("Sfx.play(\"grom_slam\")"))
	check("I: brute.gd — смерть элиты", br.contains("Sfx.play(\"mob_die_elite\""))
	var sm := _src("res://scripts/settings_menu.gd")
	check("I: settings_menu.gd — слайдеры Master/Music/SFX на месте",
		sm.contains("master_slider") and sm.contains("mus_slider") and sm.contains("sfx_slider"))
	check("I: settings_menu.gd — громкости уезжают в meta (drag_ended + reset)",
		_count(sm, "Sfx.persist_volumes") >= 2)
	var gs := _src("res://scripts/game_state.gd")
	check("I: game_state.gd — пин qa_tal жив (ui_deny)", gs.contains("GameAudio.sfx(\"ui_deny\")"))
	var sg := _src("res://scripts/sfx.gd")
	check("I: sfx.gd — жёсткий потолок 6 голосов в исходнике", sg.contains("MAX_VOICES := 6"))

# --- J: неймспейсы: audio.* вечен, чужие префиксы не тронуты ---

func j_wipe() -> void:
	GameState.flags["q.junk"] = "1"
	GameState.flags["rs.junk"] = "1"
	GameState._wipe_circle()
	check("J: audio.* переживает вайп круга (мета вечна)",
		GameState.flags.has("audio.master") and GameState.flags.has("audio.sfx"))
	check("J: вайп круга по-прежнему чистит q./rs. (чужой неймспейс не сломан)",
		not GameState.flags.has("q.junk") and not GameState.flags.has("rs.junk"))

# --- K: t37 робастность звука (находки t36 V-01/V-02/V-03) ---------------------

## K1 (V-01): user://audio_cfg.json правят руками/режет крах — нечисловые значения
## не имели права ронять _load_cfg ДО _apply_bus_volumes(). K2 (V-03): у громкости не
## должно быть двух хранилищ — слайдер обязан показывать ТО, ЧТО ЗВУЧИТ (шины).
## Фазы A..J стенд жил без GameAudio.I (Sfx-хост на root пишет шины напрямую) — это
## и есть конфигурация, в которой старый UI врал: он читал GameAudio.I, а звук
## диктовала meta audio.*. Порядок K0 -> K1 важен: сначала правда без GameAudio,
## потом старт GameAudio с грязным конфигом.
func k_robust() -> void:
	# ── K0: единый источник истины (V-03) ────────────────────────────────────
	check("K: GameAudio.I действительно ещё нет (Sfx-хост соло, как в фазах A..J)",
		GameAudio.I == null)
	# «слышимое» — то, что реально стоит на шинах; меню обязано показывать его.
	var aud_m := _bus_lin("Master")
	var aud_u := _bus_lin("Music")
	var aud_s := _bus_lin("SFX")
	check("K: на шинах пережитая громкость 0.40/0.60/0.25 (мера слышимого зафиксирована)",
		absf(aud_m - 0.4) < 0.011 and absf(aud_u - 0.6) < 0.011 and absf(aud_s - 0.25) < 0.011)
	var sm = SettingsMenu.new()      # не типизируем: поля меню читаем динамически (как qa_s2)
	add_child(sm)
	await get_tree().process_frame
	sm.call("_sync_audio")
	check("K: V-03 слайдеры = шины с точностью сетки шага 0.05 (master/music/sfx)",
		absf(float(sm.master_slider.value) - snappedf(aud_m, 0.05)) < 0.0001 \
		and absf(float(sm.mus_slider.value) - snappedf(aud_u, 0.05)) < 0.0001 \
		and absf(float(sm.sfx_slider.value) - snappedf(aud_s, 0.05)) < 0.0001)
	check("K: V-03 без GameAudio.I слайдеры НЕ показали дефолт 80% при звуке 40/60/25",
		absf(float(sm.master_slider.value) - GameAudio.DEF_VOL) > 0.05 \
		and absf(float(sm.mus_slider.value) - GameAudio.DEF_VOL) > 0.05 \
		and absf(float(sm.sfx_slider.value) - GameAudio.DEF_VOL) > 0.05)
	check("K: V-03 проценты меню совпадают с шинами (40/60/25)",
		String(sm.master_pct.text) == "40%" and String(sm.mus_pct.text) == "60%" \
		and String(sm.sfx_pct.text) == "25%")
	# ── K1: грязный cfg (V-01) ───────────────────────────────────────────────
	_write_cfg("{\"master\":\"abra\",\"music\":0.5,\"sfx\":\"kaboom\"}")
	var ga := GameAudio.new()
	add_child(ga)
	await get_tree().process_frame
	check("K: V-01 грязный cfg не уронил загрузку — GameAudio жив и стал синглтоном",
		is_instance_valid(ga) and GameAudio.I == ga)
	check("K: V-01 нечисловой master -> DEF_VOL (старый float(«abra») тут и падал)",
		absf(ga.master_vol - GameAudio.DEF_VOL) < 0.001)
	check("K: V-01 нечисловой sfx -> DEF_VOL, а читаемый music=0.5 всё же дочитан",
		absf(ga.sfx_vol - GameAudio.DEF_VOL) < 0.001 and absf(ga.music_vol - 0.5) < 0.001)
	check("K: V-01 шины всё равно применены (Master = DEF_VOL, а не заводские 0 дБ)",
		absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) \
			- linear_to_db(GameAudio.DEF_VOL)) < 0.01)
	check("K: V-01 шина Music доехала до 0.5 из обломанного cfg",
		absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) \
			- linear_to_db(0.5)) < 0.01)
	# safe-конверсия в лоб — ровно те значения, на которых спотыкался float()
	check("K: V-01 _vol_of: строка-мусор -> дефолт, числовая строка -> число",
		absf(ga._vol_of("abra", GameAudio.DEF_VOL) - GameAudio.DEF_VOL) < 0.001 \
		and absf(ga._vol_of("0.25", GameAudio.DEF_VOL) - 0.25) < 0.001)
	check("K: V-01 _vol_of: bool/null/массив/NaN/Inf -> дефолт, 42.0 -> кламп 1.0",
		absf(ga._vol_of(true, GameAudio.DEF_VOL) - GameAudio.DEF_VOL) < 0.001 \
		and absf(ga._vol_of(null, GameAudio.DEF_VOL) - GameAudio.DEF_VOL) < 0.001 \
		and absf(ga._vol_of([0.5], GameAudio.DEF_VOL) - GameAudio.DEF_VOL) < 0.001 \
		and absf(ga._vol_of(NAN, GameAudio.DEF_VOL) - GameAudio.DEF_VOL) < 0.001 \
		and absf(ga._vol_of(INF, GameAudio.DEF_VOL) - GameAudio.DEF_VOL) < 0.001 \
		and absf(ga._vol_of(42.0, GameAudio.DEF_VOL) - 1.0) < 0.001)
	# ── K2: старт GameAudio не должен рассинхронить меню и звук (V-03) ────────
	sm.call("_sync_audio")
	check("K: V-03 после старта GameAudio меню = шины (0.80/0.50/0.80), расхождения нет",
		absf(float(sm.master_slider.value) - 0.8) < 0.011 \
		and absf(float(sm.mus_slider.value) - 0.5) < 0.011 \
		and absf(float(sm.sfx_slider.value) - 0.8) < 0.011)
	sm.master_slider.value = 0.65          # штатный путь: value_changed -> _apply
	sm.call("_save_now")                   # drag_ended: cfg + meta + шины
	sm.call("_sync_audio")
	check("K: V-03 после записи громкости сошлись все три: меню 0.65 = шина = meta",
		absf(float(sm.master_slider.value) - 0.65) < 0.011 and absf(_bus_lin("Master") - 0.65) < 0.011 \
		and absf(float(GameState.flags.get("audio.master", -1.0)) - 0.65) < 0.011)
	check("K: V-03 и audio_cfg.json тоже 0.65 (cfg больше не «второе мнение»)",
		absf(_cfg_num("master") - 0.65) < 0.011)
	# ── K3: нормальные конфигы читаются как раньше ───────────────────────────
	_write_cfg("{\"master\":0.7,\"music\":0.6,\"sfx\":0.5}")
	ga.call("_load_cfg")
	check("K: чистый cfg читается точно (0.70/0.60/0.50)",
		absf(ga.master_vol - 0.7) < 0.001 and absf(ga.music_vol - 0.6) < 0.001 \
		and absf(ga.sfx_vol - 0.5) < 0.001)
	_write_cfg("{\"master\":0.9,\"music\":")        # обрезанный при крахе хвост
	ga.call("_load_cfg")
	check("K: обрезанный cfg -> дефолты без ошибки (ветка parse-null жива)",
		absf(ga.master_vol - GameAudio.DEF_VOL) < 0.001 and absf(ga.music_vol - GameAudio.DEF_VOL) < 0.001)
	_write_cfg("")
	ga.call("_load_cfg")
	check("K: пустой cfg -> дефолты, шины на дефолте (не 0 дБ и не прошлый разброс)",
		absf(ga.sfx_vol - GameAudio.DEF_VOL) < 0.001 \
		and absf(_bus_lin("SFX") - GameAudio.DEF_VOL) < 0.011)
	# ── K4: анти-регресс по исходникам (чтоб находки не вернулись молча) ─────
	var sg := _src("res://scripts/sfx.gd")
	# Ищем ИМЕННО объявление, а не вхождение подстроки: пояснение «const POOL удалена»
	# в комментарии обязано остаться и текстом пина не считаться «возврат константы».
	var pool_decl := false
	for line in sg.split("\n"):
		if String(line).strip_edges().begins_with("const POOL"):
			pool_decl = true
	check("K: V-02 мёртвая const POOL из sfx.gd удалена (объявления нет ни в одной строке)",
		not pool_decl)
	check("K: V-02 реальный размер пула документирован (по ключам каталога)",
		sg.contains("SfxCatalog.KEYS.size()"))
	check("K: V-02 пул голосов = число ключей каталога (15 слотов, а не обещанных 8)",
		Sfx.I != null and Sfx.I.get_child_count() == Sfx.keys().size())
	var gag := _src("res://scripts/game_audio.gd")
	check("K: V-01 в game_audio.gd есть гейд is_valid_float + явная гарантия шин",
		gag.contains("is_valid_float()") and gag.contains("_apply_bus_volumes()"))
	var sms := _src("res://scripts/settings_menu.gd")
	check("K: V-03 UI читает громкость с шин, а не только из cfg",
		sms.contains("AudioServer.get_bus_volume_db") and sms.contains("_applied_volume"))
	sm.free()
	ga.free()

# ---------------------------------------------------------------------------
# утилиты

func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

static func _count(hay: String, needle: String) -> int:
	var n := 0
	var i := hay.find(needle)
	while i >= 0:
		n += 1
		i = hay.find(needle, i + needle.length())
	return n

static func _decode(w: AudioStreamWAV) -> PackedFloat32Array:
	var d := w.data
	var n := d.size() / 2
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var v := int(d[i * 2]) | (int(d[i * 2 + 1]) << 8)
		if v >= 32768:
			v -= 65536
		s[i] = float(v) / 32768.0
	return s

## Доля энергии выше HIGH_HZ: каскад из двух однополюсников (круче -12 дБ/окт,
## чтобы музыкальные частички 2–3кГц почти не считались «стеклом»).
static func _high_share(s: PackedFloat32Array) -> float:
	var e := 0.0
	for i in s.size():
		e += s[i] * s[i]
	if e <= 0.0000001:
		return 0.0
	var k := 1.0 - exp(-TAU * HIGH_HZ / float(RATE))
	var y1 := 0.0
	var y2 := 0.0
	var el := 0.0
	for i in s.size():
		y1 += k * (s[i] - y1)
		y2 += k * (y1 - y2)
		el += y2 * y2
	return clampf((e - el) / e, 0.0, 1.0)

## t37: испортить/положить user://audio_cfg.json так же, как это делает игра.
func _write_cfg(txt: String) -> void:
	var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()

## t37: «слышимое» значение шины — мьют читается нулём, остальное обратно
## linear_to_db (именно так пишут шины GameAudio._apply_bus_volumes/Sfx._apply_buses).
func _bus_lin(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return -1.0
	if AudioServer.is_bus_mute(i):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(i))

## t37: число из audio_cfg.json (-1 — файла/ключа нет): проверить, что cfg не «второе
## мнение», разошедшееся с шиной и meta.
func _cfg_num(key: String) -> float:
	if not FileAccess.file_exists(CFG_PATH):
		return -1.0
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	if f == null:
		return -1.0
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY or not data.has(key):
		return -1.0
	return float(data[key])
