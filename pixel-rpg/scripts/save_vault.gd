class_name SaveVault
extends RefCounted
## Хранилище сейва: экспорт/импорт переносимой строки (docs/RETENTION_NG_PLUS.md §5.2).
## У VK Play нет cloud save, а IndexedDB (user:// в WebGL) живёт до чистки браузера —
## текстовый бэкап единственный способ не потерять Пепел и NG+ без сервера.
##
## Формат: "TSNL1:" + base64(байты user://save_morkheim.json как есть). Никакой
## своей интерпретации полей: что лежит в сейве, то и едет — совместимость со
## всеми будущими полями (Пепел, NG+) по построению.
##
## Железное правило импорта: save_morkheim.json заменяется ТОЛЬКО после успешной
## записи автобэкапа save_backup_auto.json. Порядок: валидация -> tmp -> бэкап
## текущего -> rename(tmp поверх сейва). На любом провале текущий сейв нетронут;
## rename поверх существующего атомарен (Win: MoveFileEx REPLACE_EXISTING), так
## что файла-полудура не бывает.

const MAGIC := "TSNL1:"
const SAVE_PATH := "user://save_morkheim.json"
const TMP_PATH := "user://save_import.tmp"
const AUTO_BACKUP_PATH := "user://save_backup_auto.json"
## Хотя бы один ключ обязан присутствовать — иначе это не наш сейв.
## Ключи сверены с game_state.to_dict(): gold, hp, flags есть в каждой записи v2.
const KNOWN_KEYS := ["gold", "hp", "flags"]
## Защитный потолок: реальный сейв ~КБ; мегабайты base64 — мусор или атака.
const MAX_RAW_BYTES := 1 << 20  # 1 MiB

## Текстовый бэкап текущего сейва. "" — сейва ещё нет (или не читается):
## вызывающий UI показывает «экспортировать нечего».
static func export_text() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SaveVault: не открывается %s (err=%d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return ""
	var raw := f.get_buffer(f.get_length())
	f.close()
	return MAGIC + Marshalls.raw_to_base64(raw)

## Импорт строки из export_text(). OK — сейв заменён (старый в AUTO_BACKUP_PATH).
## ERR_INVALID_DATA — не наш формат (битый base64/JSON/чужие данные): файл НЕ тронут.
static func import_text(s: String) -> Error:
	var t := s.strip_edges()
	if not t.begins_with(MAGIC):
		return ERR_INVALID_DATA
	# Вставка из браузера иногда приезжает перенесённой по ширине — режем весь whitespace.
	var b64 := t.substr(MAGIC.length()).replace("\r", "").replace("\n", "").replace(" ", "").replace("\t", "")
	var raw := Marshalls.base64_to_raw(b64)  # strict-режим по умолчанию
	if raw.is_empty() or raw.size() > MAX_RAW_BYTES:
		return ERR_INVALID_DATA
	var data: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	var known := false
	for k: String in KNOWN_KEYS:
		if data.has(k):
			known = true
			break
	if not known:
		push_warning("SaveVault: JSON без известных ключей сейва — отказ")
		return ERR_INVALID_DATA
	var dir := DirAccess.open("user://")
	if dir == null:
		push_warning("SaveVault: не открывается каталог user:// — отказ")
		return ERR_CANT_OPEN
	# 1) Декод в tmp: до этой точки сейв на диске не касались ни разу.
	var ft := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if ft == null:
		push_warning("SaveVault: не создаётся %s (err=%d)" % [TMP_PATH, FileAccess.get_open_error()])
		return ERR_CANT_OPEN
	ft.store_buffer(raw)
	ft.close()
	# 2) Автобэкап ТЕКУЩЕГО сейва (байты в памяти из файла, не из импорта).
	if FileAccess.file_exists(SAVE_PATH):
		var fc := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var cur := PackedByteArray()
		if fc == null:
			dir.remove("save_import.tmp")
			push_warning("SaveVault: текущий сейв не читается — импорт отменён (сейв цел)")
			return ERR_CANT_OPEN
		cur = fc.get_buffer(fc.get_length())
		fc.close()
		var fb := FileAccess.open(AUTO_BACKUP_PATH, FileAccess.WRITE)
		if fb == null or fb.get_error() != OK:
			dir.remove("save_import.tmp")
			push_warning("SaveVault: автобэкап не записался — импорт отменён (сейв цел)")
			return ERR_CANT_OPEN
		fb.store_buffer(cur)
		fb.close()
		if not FileAccess.file_exists(AUTO_BACKUP_PATH):
			dir.remove("save_import.tmp")
			push_warning("SaveVault: автобэкап не появился на диске — импорт отменён (сейв цел)")
			return ERR_CANT_OPEN
	# 3) Только теперь замена: rename tmp поверх сейва (атомарно, с перезаписью).
	if dir.rename("save_import.tmp", "save_morkheim.json") != OK:
		dir.remove("save_import.tmp")
		push_warning("SaveVault: rename tmp->save не удался — импорт отменён (сейв цел, бэкап есть)")
		return ERR_CANT_OPEN
	return OK
