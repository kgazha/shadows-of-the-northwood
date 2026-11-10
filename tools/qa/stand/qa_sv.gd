extends Node
## QA хранилища сейва (sand_sv, база 604212f). НЕ для мержа.
## user:// изолирован редиректом APPDATA (tools/appdata_sv) — реальный
## tools/appdata/Godot не касамся. Все проверки — на реальном диске user://.

var fails := 0

func _ready() -> void:
	_no_save_yet()
	var exp := _round_trip()
	await _ui(exp)
	print("QA SV: fails=", fails, " -> ", ("ALL PASS" if fails == 0 else "FAILS!"))
	get_tree().quit(0 if fails == 0 else 1)

func _read(p: String) -> PackedByteArray:
	if not FileAccess.file_exists(p):
		return PackedByteArray()
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b

func _no_save_yet() -> void:
	# пустой каталог user:// -> экспорт пустой, импорт пустоты — отказ
	_check(SaveVault.export_text() == "", "export of absent save -> ''")
	_check(SaveVault.import_text("") == ERR_INVALID_DATA, "import '' -> ERR_INVALID_DATA")

func _round_trip() -> String:
	# --- состояние A: gold/hp/flags + «Пепел» (meta.ash — ключ флагов, achv.grant_ash) ---
	GameState.level = 3
	GameState.recalc_max_hp()
	GameState.gold = 777
	GameState.hp = GameState.max_hp - 1
	GameState.flags = {"qa.marker": 7, "ng.boss_0": 1, "meta.ash": 3}
	_check(GameState.save_game(), "save A")
	var raw_a := _read("user://save_morkheim.json")
	var exp: String = SaveVault.export_text()
	_check(exp.begins_with("TSNL1:"), "export has TSNL1: magic")
	_check(Marshalls.base64_to_raw(exp.substr(6)) == raw_a, "base64 == raw bytes of save")
	# --- состояние B: портим сейв, затем импорт A ---
	GameState.gold = 5
	GameState.save_game()
	var raw_b := _read("user://save_morkheim.json")
	_check(raw_b != raw_a, "state B differs from A")
	_check(SaveVault.import_text(exp) == OK, "import_text -> OK")
	_check(_read("user://save_backup_auto.json") == raw_b, "AUTO-BACKUP == pre-import save (создан до замены)")
	_check(_read("user://save_morkheim.json") == raw_a, "save file == exported bytes")
	_check(not FileAccess.file_exists("user://save_import.tmp"), "tmp consumed")
	_check(GameState.load_game(), "load_game after import")
	_check(GameState.gold == 777, "gold round-trip 777")
	_check(GameState.hp == GameState.max_hp - 1, "hp round-trip")
	_check(int(GameState.flags.get("qa.marker", 0)) == 7, "flags round-trip qa.marker")
	_check(int(GameState.flags.get("meta.ash", 0)) == 3, "ash round-trip meta.ash=3")
	_check(int(GameState.flags.get("ng.boss_0", 0)) == 1, "ng.boss_0 round-trip")
	# --- мусор: файл байт-в-байт прежний, автобэкап не перезаписан ---
	var pre := _read("user://save_morkheim.json")
	_check(SaveVault.import_text("hello") == ERR_INVALID_DATA, "garbage 'hello' -> ERR_INVALID_DATA")
	_check(SaveVault.import_text("XXXX1:QUJD") == ERR_INVALID_DATA, "foreign prefix -> ERR_INVALID_DATA")
	var cut: String = exp.substr(0, exp.length() - 6)
	_check(SaveVault.import_text(cut) == ERR_INVALID_DATA, "truncated base64 -> ERR_INVALID_DATA")
	var foreign: String = "TSNL1:" + Marshalls.raw_to_base64(String('{"nope": 1}').to_utf8_buffer())
	_check(SaveVault.import_text(foreign) == ERR_INVALID_DATA, "valid JSON w/o save keys -> ERR_INVALID_DATA")
	_check(SaveVault.import_text("TSNL1:@@@@not base64@@@@" + exp.substr(6, 40)) == ERR_INVALID_DATA, "corrupt base64 -> ERR_INVALID_DATA")
	_check(_read("user://save_morkheim.json") == pre, "save byte-for-byte untouched by failures")
	_check(_read("user://save_backup_auto.json") == raw_b, "backup untouched by failures")
	_check(not FileAccess.file_exists("user://save_import.tmp"), "tmp not left after failures")
	return exp

func _ui(exp: String) -> void:
	var menu := SettingsMenu.new()
	add_child(menu)
	await get_tree().physics_frame
	_check(menu.sv_export.editable == false, "UI: export LineEdit readonly")
	menu._on_sv_export()  # сейв на диске есть -> текст + best-effort буфер (headless: фолбэк)
	_check(menu.sv_export.text.begins_with("TSNL1:"), "UI export fills line edit")
	_check(String(menu.sv_msg.text) != "", "UI export prints status")
	# пустой ввод — без краша, файл не тронут
	var pre := _read("user://save_morkheim.json")
	menu.sv_import.text = ""
	menu._on_sv_import()
	_check(_read("user://save_morkheim.json") == pre, "UI empty input: file untouched")
	# мусорный ввод — текст отказа
	menu.sv_import.text = "hello"
	menu._on_sv_import()
	_check(menu.sv_msg.text == "Не похоже на наш сейв", "UI garbage -> «Не похоже на наш сейв»")
	_check(_read("user://save_morkheim.json") == pre, "UI garbage: file untouched")
	# валидный ввод — успех и канонический тост
	menu.sv_import.text = exp
	menu._on_sv_import()
	_check(menu.sv_msg.text == "Сейв восстановлен. Перезайдите (F9) или перезапустите", "UI success toast")
	GameState.load_game()
	_check(GameState.gold == 777, "UI import: gold 777 after load")
	menu.queue_free()

func _check(ok: bool, name: String) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		fails += 1
