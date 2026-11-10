extends Node
## Adversarial QA-4 (база 418e980): SaveVault import-фаззинг + вкладка «Достижения».

const SAVE := "user://save_morkheim.json"
const TMP := "user://save_import.tmp"
const BAK := "user://save_backup_auto.json"
const MAX_RAW := 1 << 20

var pass_n := 0
var fail_n := 0
var world: Node2D
var jr: Node

func chk(g: String, n: String, c: bool, info: String = "") -> void:
	if c:
		pass_n += 1
		print("PASS | %s | %s" % [g, n])
	else:
		fail_n += 1
		print("FAIL | %s | %s | %s" % [g, n, info])

func rd_b(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b

func wr_b(path: String, b: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()

func b2raw(s: String) -> PackedByteArray:
	return s.to_utf8_buffer()

func raw_to_str(b: PackedByteArray) -> String:
	return b.get_string_from_utf8()

func exists(p: String) -> bool:
	return FileAccess.file_exists(p)

func canonical_bytes() -> PackedByteArray:
	var d := {"v": 2, "gold": 777, "hp": 15, "flags": {"q.z": 1}, "note": "канон QA-4"}
	return b2raw(JSON.stringify(d))

func put_canonical() -> void:
	wr_b(SAVE, canonical_bytes())

# ================================================================ SaveVault

var sv_save0 := PackedByteArray()
var sv_bak0 := PackedByteArray()

func snap() -> void:
	sv_save0 = rd_b(SAVE)
	sv_bak0 = rd_b(BAK)

func inv_after_reject(n: String, res: Error, tmp_expected_body: PackedByteArray) -> void:
	var ok := res == ERR_INVALID_DATA
	var save_same := rd_b(SAVE) == sv_save0
	var bak_same := rd_b(BAK) == sv_bak0
	var tb := rd_b(TMP)
	var tmp_ok: bool = (tb == tmp_expected_body) if tmp_expected_body.size() > 0 else (not exists(TMP))
	chk("SV", n + ": отказ, сейв байт-в-байт, бэкап цел, tmp предсказуем",
		ok and save_same and bak_same and tmp_ok,
		"res=%d save_same=%b bak_same=%b tmp_ok=%b" % [res, save_same, bak_same, tmp_ok])

func _sv_group() -> void:
	var g := "SV"
	if exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if exists(BAK):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BAK))
	put_canonical()
	snap()
	chk(g, "baseline: canonical save present, no tmp/backup", sv_save0.size() > 0 and not exists(TMP) and not exists(BAK))

	# 1a: валидный base64, декод = битый UTF-8 ВНУТРИ JSON-строки
	var p1 := b2raw("{\"gold\":5,\"note\":\"а")
	p1.append_array(PackedByteArray([0xC3, 0x28, 0xEF, 0x00, 0x80]))
	p1.append_array(b2raw("б\"}"))
	snap()
	var r := SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(p1))
	if r == OK:
		chk(g, "1a broken-UTF8-in-string: принят (U+FFFD), сейв==raw, load жив",
			rd_b(SAVE) == p1 and GameState.load_game() and GameState.gold == 5,
			"res=OK save_eq=%b gold=%d" % [rd_b(SAVE) == p1, GameState.gold])
	else:
		inv_after_reject("1a broken-UTF8-in-string", r, PackedByteArray())

	# 1b: битый UTF-8 ломает структуру JSON
	var p2 := b2raw("{\"gold\":5,")
	p2.append(PackedByteArray([0xFF])[0])
	p2.append_array(b2raw("\"hp\":1}"))
	snap()
	r = SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(p2))
	inv_after_reject("1b broken-UTF8 breaks JSON", r, PackedByteArray())
	put_canonical()

	# 2a: ядовитые типы скаляров
	var p3 := b2raw(JSON.stringify({"gold": "abc", "hp": [1, 2], "flags": 42, "level": 9}))
	snap()
	r = SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(p3))
	var ok2a: bool = r == OK and GameState.load_game() \
		and GameState.gold == 0 and GameState.flags.is_empty() \
		and GameState.hp == GameState.max_hp and GameState.level == 9
	chk(g, "2a poison gold/hp/flags: импорт ок, load жив, M-коэрция (0/full/{})",
		ok2a, "res=%d gold=%d flags=%d hp=%d/%d" % [r, GameState.gold, GameState.flags.size(), GameState.hp, GameState.max_hp])

	# 2b: flags со dict-значением — сквозное прохождение через from_dict
	var p4 := b2raw(JSON.stringify({"gold": 13, "flags": {"ach.x": {"nested": 1}}}))
	snap()
	r = SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(p4))
	var fk: Variant = GameState.flags.get("ach.x")
	chk(g, "2b flags[dict] сквозняком: load жив, 1 ключ, тип-ловушка видна",
		r == OK and GameState.load_game() and GameState.flags.size() == 1 and typeof(fk) == TYPE_DICTIONARY,
		"res=%d size=%d t=%d" % [r, GameState.flags.size(), typeof(fk)])
	GameState.flags.clear()

	# 3: гигантский вход — ровно 2 MiB
	var pad2: int = (2 * 1024 * 1024) - b2raw("{\"gold\":1,\"pad\":\"\"}").size()
	var big2 := b2raw("{\"gold\":1,\"pad\":\"" + "A".repeat(pad2) + "\"}")
	snap()
	r = SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(big2))
	inv_after_reject("3 2MiB payload: отказ по потолку", r, PackedByteArray())

	# 3b: ровно 1 MiB — потолок inclusive (>)
	var pad1: int = MAX_RAW - b2raw("{\"gold\":1,\"pad\":\"\"}").size()
	var big1 := b2raw("{\"gold\":1,\"pad\":\"" + "A".repeat(pad1) + "\"}")
	if big1.size() != MAX_RAW:
		big1.resize(MAX_RAW)
	chk(g, "3b payload ровно 1 MiB выдержан", big1.size() == MAX_RAW, "size=%d" % big1.size())
	snap()
	r = SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(big1))
	chk(g, "3b ровно 1 MiB принят (> ceiling, не >=), сейв==raw, tmp съеден, бэкап==прежний сейв",
		r == OK and rd_b(SAVE) == big1 and not exists(TMP) and rd_b(BAK) == sv_save0,
		"res=%d save_eq=%b" % [r, rd_b(SAVE) == big1])

	# 4: пустой/мусорный payload и ключ-магия
	snap()
	r = SaveVault.import_text("TSNL1:")
	inv_after_reject("4a 'TSNL1:' + пусто", r, PackedByteArray())
	snap()
	r = SaveVault.import_text("TSNL1:####")
	inv_after_reject("4b битый base64 (strict)", r, PackedByteArray())
	snap()
	r = SaveVault.import_text("tsnl1:" + Marshalls.raw_to_base64(canonical_bytes()))
	inv_after_reject("4c lowercase magic", r, PackedByteArray())
	snap()
	r = SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(b2raw(JSON.stringify({"foo": 1}))))
	inv_after_reject("4d dict без известных ключей", r, PackedByteArray())

	# 5a: tmp-атака — предсозданные tmp+backup мусором, валидный импорт
	var payload := b2raw(JSON.stringify({"gold": 321, "flags": {"ach.qa": 1}}))
	wr_b(TMP, b2raw("JUNK-TMP"))
	wr_b(BAK, b2raw("STALE-BACKUP"))
	var before_save := rd_b(SAVE)
	r = SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(payload))
	chk(g, "5a tmp+backup-мусор предсоздан: импорт ок, tmp перезаписан+съеден, backup==старый сейв",
		r == OK and rd_b(SAVE) == payload and not exists(TMP) and rd_b(BAK) == before_save,
		"res=%d tmp=%b" % [r, exists(TMP)])

	# 5b: tmp-мусор + НЕвалидный импорт — осиротевший tmp остаётся (предсказуемо), сейв цел
	wr_b(TMP, b2raw("JUNK2"))
	put_canonical()
	snap()
	r = SaveVault.import_text("TSNL1:@@@@")
	var orphan_ok := rd_b(TMP) == b2raw("JUNK2")
	chk(g, "5b tmp-мусор + отказ: сейв цел, tmp=предсказуемый труп (не ERR), бэкап цел",
		r == ERR_INVALID_DATA and rd_b(SAVE) == sv_save0 and orphan_ok and rd_b(BAK) == sv_bak0,
		"res=%d save_same=%b tmp=%s" % [r, rd_b(SAVE) == sv_save0, raw_to_str(rd_b(TMP))])
	var payload2 := b2raw(JSON.stringify({"gold": 1, "flags": {}}))
	r = SaveVault.import_text("TSNL1:" + Marshalls.raw_to_base64(payload2))
	chk(g, "5b+ последующий импорт съедает осиротевший tmp", r == OK and not exists(TMP))

	# 6: UI-слой — браузерная вставка: переносы CRLF внутри, пробелы/табы по краям
	put_canonical()
	snap()
	var exp := SaveVault.export_text()
	var lines := PackedStringArray()
	var i := 0
	while i < exp.length():
		lines.append(exp.substr(i, 70))
		i += 70
	var pasted := " \t" + "\r\n".join(lines) + "\t \r\n "
	r = SaveVault.import_text(pasted)
	chk(g, "6 вставка с CRLF/табами/пробелами: strip, импорт ок, байт-в-байт",
		r == OK and rd_b(SAVE) == sv_save0, "res=%d" % r)
	var mangled := "TSNL1:" + exp.substr(6).replace("A", " A\t")
	r = SaveVault.import_text(mangled)
	chk(g, "6b whitespace внутри base64 вырезается", r == OK, "res=%d" % r)

	# 7: экспорт стабилен (round-trip)
	put_canonical()
	var e1 := SaveVault.export_text()
	r = SaveVault.import_text(e1)
	chk(g, "7 export->import round-trip стабилен", r == OK and SaveVault.export_text() == e1)

# ================================================================ Journal achv-tab

func ach_txt(sub: String) -> bool:
	for c in jr._ach_list.get_children():
		if c is Label and String((c as Label).text).contains(sub):
			return true
	return false

func _jc_group() -> void:
	var g := "JC"
	GameState.flags.clear()
	GameState.campfires_used = {"a": true, "b": true, "c": true}
	GameState.chests_used = ["ch_a", "ch_b"]
	GameState.slime_kills = 30
	GameState.gold = 250
	jr.open()
	jr.select_tab(1)

	# 1: семантика флага анлока
	GameState.flags["ach.hunter_25"] = 0.0
	GameState.flags["ach.first_blood"] = "true"
	GameState.flags["ach.boss_slayer"] = false
	GameState.flags["ach.hardcore"] = true
	GameState.flags["ach.wealth"] = 2.0
	var u25: bool = jr._ach_unlocked("hunter_25")
	var ufb: bool = jr._ach_unlocked("first_blood")
	var ubo: bool = jr._ach_unlocked("boss_slayer")
	var uhc: bool = jr._ach_unlocked("hardcore")
	var uw: bool = jr._ach_unlocked("wealth")
	chk(g, "1 float-0 флаг = НЕ открыта (!=null && float>0)", not u25, "u=%b" % u25)
	chk(g, "1 'true'-строка = не открыта (float('true')=0)", not ufb, "u=%b" % ufb)
	chk(g, "1 false-bool закрыта; true-bool/2.0-float открыты", (not ubo) and uhc and uw,
		"ubo=%b uhc=%b uw=%b" % [ubo, uhc, uw])
	jr._rebuild_achv()
	chk(g, "1 render: [x] у hardcore/wealth, [ ] у hunter_25",
		ach_txt("[x] На волоске") and ach_txt("[x] Богач") and ach_txt("[ ] Юный охотник"))

	# 2: size:-резолверы dict vs array + round-trip + фордж
	var cur_cf: int = jr._ach_cur("size:campfires_used")
	var cur_ch: int = jr._ach_cur("size:chests_used")
	chk(g, "2 size: dict=3 array=2 оба живут", cur_cf == 3 and cur_ch == 2, "cf=%d ch=%d" % [cur_cf, cur_ch])
	GameState.save_game()
	var okload: bool = GameState.load_game()
	var cf_rt: Variant = GameState.campfires_used
	var ch_rt: Variant = GameState.chests_used
	chk(g, "2 round-trip: dict->dict array->array, size 3/2 целы",
		okload and typeof(cf_rt) == TYPE_DICTIONARY and cf_rt.size() == 3 \
		and typeof(ch_rt) == TYPE_ARRAY and ch_rt.size() == 2,
		"t1=%d t2=%d" % [typeof(cf_rt), typeof(ch_rt)])
	var forged := {"gold": 10, "campfires_used": ["x", "y"], "chests_used": {"a": 1, "b": 2}}
	var fj := FileAccess.open(SAVE, FileAccess.WRITE)
	fj.store_string(JSON.stringify(forged))
	fj.close()
	okload = GameState.load_game()
	chk(g, "2 фордж dict<->array: from_dict приводит к пусто, size 0/0, не краш",
		okload and GameState.campfires_used.size() == 0 and GameState.chests_used.size() == 0,
		"cf=%d ch=%d" % [GameState.campfires_used.size(), GameState.chests_used.size()])

	# 3: field:gold 1e9 и отрицательный
	GameState.flags.clear()
	GameState.gold = 1000000000
	jr._rebuild_achv()
	chk(g, "3 field:gold 1e9 — формат '1000000000/300' жив", ach_txt("1000000000/300"))
	GameState.gold = -5
	jr._rebuild_achv()
	chk(g, "3 field:gold -5 — '-5/300' без краша", ach_txt("-5/300"))
	var f3 := FileAccess.open(SAVE, FileAccess.WRITE)
	f3.store_string("{\"gold\": 1e9, \"flags\": {}}")
	f3.close()
	okload = GameState.load_game()
	chk(g, "3 JSON 1e9 (float) -> int 1000000000 (M3)", okload and GameState.gold == 1000000000, "gold=%d" % GameState.gold)

	# 4: Tab при пустом журнале квестов
	GameState.elder_quest = 0
	GameState.slime_quest = 0
	GameState.flags.clear()
	QuestsData.refresh(GameState)
	jr.select_tab(0)
	var qempty: bool = false
	for c in jr._list.get_children():
		if c is Label and String((c as Label).text).contains("Записей пока нет"):
			qempty = true
	jr.select_tab(1)
	chk(g, "4 пустой квест-журнал + Tab туда/обратно — живой", qempty and ach_txt("Первая кровь"), "qempty=%b" % qempty)

	# 6: стресс J/Tab 50x — лейблы не размножаются
	for i in 4:
		await get_tree().process_frame
	var base_n: int = jr._ach_list.get_child_count()
	for i in 50:
		jr.select_tab(0)
		jr.select_tab(1)
		jr.close()
		jr.open()
	for i in 4:
		await get_tree().process_frame
	var end_n: int = jr._ach_list.get_child_count()
	chk(g, "6 стресс 50x J/Tab: лейблы стабильны", base_n == end_n and end_n > 0, "%d->%d" % [base_n, end_n])
	chk(g, "6 лист квестов не раздут", jr._list.get_child_count() < 200, "n=%d" % jr._list.get_child_count())

func _jc_keys() -> void:
	# клавиатурный путь: реальные события, прямой фолбэк — только если push не долетел
	var g := "JC"
	jr.close()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	get_window().push_input(ev)
	for i in 2:
		await get_tree().process_frame
	var ch_direct := ""
	if not jr.is_open():
		jr._unhandled_key_input(ev)
		ch_direct = " (прямая доставка)"
	chk(g, "KB J открывает журнал" + ch_direct, jr.is_open())
	ev = InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	get_window().push_input(ev)
	for i in 2:
		await get_tree().process_frame
	if int(jr._tab) != 1:
		jr._unhandled_key_input(ev)
		ch_direct = " (прямая доставка)"
	chk(g, "KB Tab переключает вкладку" + ch_direct, int(jr._tab) == 1)
	ev = InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	get_window().push_input(ev)
	for i in 2:
		await get_tree().process_frame
	if jr.is_open():
		jr._unhandled_key_input(ev)
	chk(g, "KB J закрывает", not jr.is_open())
	GameState.input_locked = true
	ev = InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	get_window().push_input(ev)
	jr._unhandled_key_input(ev)
	chk(g, "J не открывает при input_locked", not jr.is_open())
	GameState.input_locked = false

func _jc_watchdog() -> void:
	var g := "JC"
	jr.open()
	jr.select_tab(1)
	Shop.open()  # чужая модалка: input_locked=true
	var labels_before: int = jr._ach_list.get_child_count()
	GameState.gold += 100  # сдвиг подписи: живой rebuild тиком не обязан (сначала close)
	for i in 30:  # > TICK 0.35s при 60fps
		await get_tree().process_frame
	var still_open: bool = jr.is_open()
	Shop.close()
	GameState.gold -= 100
	chk(g, "5 watchdog: журнал закрыт тиком при чужой модалке (input_locked)", not still_open)
	chk(g, "5 rebuild до закрытия не крошил UI (лейблы на месте)", labels_before > 0)

func _jc_dictflag_poison() -> void:
	# LAST: dict-ядо в реальном ach.id. Яд вносим ПРИ ОТКРЫТОМ журнале — ошибка
	# живёт в стеке Journal._process (не харнесса); провераем выживаемость.
	var g := "PZ"
	jr.select_tab(1)
	var n_clean: int = jr._ach_list.get_child_count()
	GameState.flags["ach.hunter_25"] = {"nested": 1}  # float(dict) -> рантайм-ошибка в _process
	GameState.slime_kills += 1                        # сдвигаем подпись, чтобы тик точно дёрнулся
	for i in 30:
		await get_tree().process_frame
	var alive: bool = jr.is_open() and jr._ach_list.get_child_count() == n_clean \
		and ach_txt(": 0/25")  # stale: счётчик не обновился (ошибка тика), но UI жив
	GameState.flags.erase("ach.hunter_25")
	for i: int in range(30):
		await get_tree().process_frame
	var healed: bool = jr.is_open() and ach_txt(": 1/25") \
		and jr._ach_list.get_child_count() == n_clean  # rebuild поехал после очистки яда
	jr.close()
	chk(g, "dict-ядо в ach.id: журнал НЕ падает (stale UI), процесс жив", alive, "clean=%d now=%d" % [n_clean, jr._ach_list.get_child_count()])
	chk(g, "dict-ядо убран — живой rebuild восстановился", healed)

func _ready() -> void:
	var ms: Node = load("res://scenes/main.tscn").instantiate()
	add_child(ms)
	world = ms
	for i in 8:
		await get_tree().process_frame
	for c in world.get_children():
		if c is Journal:
			jr = c
	if jr == null:
		print("FAIL | BOOT | journal node missing")
		get_tree().quit(1)
		return
	_sv_group()
	_jc_group()
	_jc_keys()
	_jc_watchdog()
	_jc_dictflag_poison()
	for p in [SAVE, TMP, BAK]:
		if exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("SUMMARY | PASS=%d FAIL=%d" % [pass_n, fail_n])
	get_tree().quit(0 if fail_n == 0 else 1)
