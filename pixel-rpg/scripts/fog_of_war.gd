## Туман открытия карты мира (t7, вердикт пользователя 25.11 «мировая карта
## сразу открыта — её должен исследовать»).
##
## ЧИСТЫЕ ДАННЫЕ без сцены и детерминизма-побочных эффектов: битовое поле
## discovered 96x60 (720 байт), бёра по Чебышёву, компактный сейв base64 —
## аддитивный ключ v4-сейва "wm_fog" (game_state.gd). Туман — не стена:
## проходимость/коллайдеры/геометрия его не видят (worldmap_zone immutable,
## GOLDEN-WM-PIN не двигается); герой ходит свободно, туман — незнание.
##
## Семантика (вердикт капитана, детали реализации — здесь):
##  * VIEW_R — радиус обзора героя при ходьбе (клетки, Chebyshev);
##  * ARC_R  — стартовая clearing у арки/спавна (первый вход на карту);
##  * PORTAL_R — при ВХОДЕ в локацию открываются её портал и окрестности;
##  * открытое не забывается; reset — только общий вайп круга (_wipe_circle).
## Оставлено без class_name: потребители держат preload (паттерн OW/ClickMove —
## устойчиво к stale global_script_class_cache в headless-стендах).

const OW := preload("res://scripts/open_world.gd")

const W := OW.WM_W                  # 96
const H := OW.WM_H                  # 60
const VIEW_R := 10                  # радиус обзора при ходьбе, клеток
const ARC_R := 10                   # стартовая clearing у спавна/арки
const PORTAL_R := 3                 # портал + окрестности при входе в локацию

var bits := PackedByteArray()       # row-major битовка W*H (720 байт)
var _n := 0                         # кэш числа открытых
var version := 0                    # растёт на каждом изменении (триггер слоёв)

func _init() -> void:
	bits.resize((W * H + 7) / 8)

func _idx(x: int, y: int) -> int:
	return y * W + x

func is_discovered(x: int, y: int) -> bool:
	# за краем поля — «известно»: слой тумана рисуется только по клеткам поля,
	# а POI-гейты интересуют только штатные клетки
	if x < 0 or y < 0 or x >= W or y >= H:
		return true
	var i := _idx(x, y)
	return (bits[i >> 3] >> (i & 7)) & 1 == 1

## true — клетка ОТКРЫЛАСЬ сейчас (раньше была в тумане).
func reveal_cell(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return false
	var i := _idx(x, y)
	var m := 1 << (i & 7)
	var b := (i >> 3)
	if bits[b] & m != 0:
		return false
	bits[b] = bits[b] | m
	_n += 1
	version += 1
	return true

## Диск Чебышёва радиуса r; возвращает число НОВЫХ открытых клеток.
func reveal_disk(c: Vector2i, r: int) -> int:
	var fresh := 0
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if reveal_cell(x, y):
				fresh += 1
	return fresh

## Сколько клеток открыто (кэш; инкремент в reveal_cell, пересчёт в from_b64).
func discovered_count() -> int:
	return _n

## Компактный сейв: base64 от 720 байт (аддитивный ключ v4).
func to_b64() -> String:
	return Marshalls.raw_to_base64(bits)

## Загрузка из base64. false и молчаливый игнор — пустая/битая строка или
## размер не по поля (легаси-сейв без ключа = туман с нуля, не поломка).
func from_b64(s: String) -> bool:
	if s == "":
		return false
	var raw := Marshalls.base64_to_raw(s)
	if raw.size() != (W * H + 7) / 8:
		return false
	bits = raw
	_n = 0
	for y in H:
		for x in W:
			if is_discovered(x, y):
				_n += 1
	version += 1
	return true
