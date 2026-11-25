extends SceneTree
## t14 В«РћСЂСѓР¶РёРµ v1В» (РІРµСЂРґРёРєС‚ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ 25.11 В«СЃРїСЂР°Р№С‚С‹ РІРЅРµРґСЂСЏР№В», Р»РёСЃС‚
## diag-t10/sheet_weapons_v1.png + PINS_T10.md): РєРѕРґРѕ-Р±РµР№Рє РјРёСЂРѕРІРѕРіРѕ Р°С‚Р»Р°СЃР°
## РѕСЂСѓР¶РёСЏ assets/world/weapons_world_v1.png вЂ” 192x32, РґРІР° СЂСЏРґР° РїРѕ 12 СЃР»РѕС‚РѕРІ
## 16 px (WorldWeapons.SLOTS):
##   СЂСЏРґ 0 KORYAGA вЂ” РїРѕР»РЅС‹Р№ С†РІРµС‚ (СѓС‚РІРµСЂР¶РґС‘РЅРЅС‹Р№ РІРµСЂРґРёРєС‚РѕРј РјРёСЂРѕРІРѕР№ СЃС‚РёР»СЊ);
##   СЂСЏРґ 1 SILHOUETTE вЂ” CHAR DARK С‚РµР»Рѕ + СЃРІРµС‚РѕРІРѕР№ РєР°РЅС‚ BONE РїРѕ РѕС‚РєСЂС‹С‚С‹Рј
##   РІРµСЂС…Сѓ/Р»РµРІСѓ (Р·Р°РїР°СЃРЅРѕР№ СЂСЏРґ РїРѕРґ СЂР°Р·РІРѕСЂРѕС‚ РІРµСЂРґРёРєС‚Р°, РїРµСЂРµРєР»СЋС‡Р°С‚РµР»СЊ вЂ”
##   WorldWeapons.WORLD_ART_KORYAGA).
##
## РџРѕР±РёС‚РѕРІРѕРµ СЂР°РІРµРЅСЃС‚РІРѕ Р»РёСЃС‚Сѓ: 7 РЅРѕРІС‹С… РїРѕР·РёС†РёР№ (РїРѕСЃРѕС…Рё/Р»СѓРєРё/С‰РёС‚С‹) СЂРёСЃСѓСЋС‚СЃСЏ
## РўР•РњР Р–Р• СЂРёСЃРѕРІР°Р»РєР°РјРё UiIcons, С‡С‚Рѕ Рё Р»РёСЃС‚ (row-0 == СЃРµРєС†РёСЏ B Р»РёСЃС‚Р°
## РґРѕСЃР»РѕРІРЅРѕ), Рё РёС… FNV-1a32 Р·Р°С„РёРєСЃРёСЂРѕРІР°РЅС‹ РїРёРЅРѕРј РЅРёР¶Рµ (Р·РЅР°С‡РµРЅРёСЏ вЂ” PINS_T10,
## СЃРµРєС†РёСЏ B). Р›РµРіР°СЃРё-С‚СЂРёРѕ (sword/axe/rune_blade вЂ” РІ РёРєРѕРЅРєР°С… Р±С‹Р»Рё СЃРµСЂРѕР№
## Р·Р°РіР»СѓС€РєРѕР№) РЅР°СЂРёСЃРѕРІР°РЅРѕ Р·РґРµСЃСЊ РІ РµРґРёРЅРѕРј СЏР·С‹РєРµ РєРѕСЂСЏРіРё (С‚Рµ Р¶Рµ СЂР°РјРїС‹/РїСЂРёРјРёС‚РёРІС‹)
## Рё РїРёРЅРёС‚СЃСЏ СЃ СЂРѕР¶РґРµРЅРёСЏ СЃРІРѕРёРјРё FNV.
##
## Р—Р°РїСѓСЃРє:
##   Godot --headless --path pixel-rpg -s res://tools_art/weapons_world_v1.gd -- bake [out.png]
##   Godot --headless --path pixel-rpg -s res://tools_art/weapons_world_v1.gd -- check [out.png]
## Р’С‹С…РѕРґ 0 вЂ” РІСЃРµ СЃР°РјРѕРїСЂРѕРІРµСЂРєРё PASS (РёРЅР°С‡Рµ С„Р°Р№Р» РЅРµ РІС‹РєР»Р°РґС‹РІР°РµС‚СЃСЏ).

const P := preload("res://scripts/pixel_palette.gd")
const UI := preload("res://scripts/ui_icons.gd")
const WW := preload("res://scripts/world_weapons.gd")

## FNV-РїРёРЅС‹ Р»РёСЃС‚Р° В«РћСЂСѓР¶РёРµ v1В» (diag-t10/PINS_T10.md, СЃРµРєС†РёСЏ B). Р СЏРґ 0 KORYAGA:
const PIN_KORYAGA := {
	"staff_apprentice": "AD94FAAE", "staff_oak": "8A2D5D47", "staff_rune": "D92F1020",
	"bow_hunter": "716A18CF", "bow_heavy": "FA62C3CF",
	"shield_iron": "2C6EFA7E", "shield_raven": "AE747213",
}
## Р СЏРґ 1 SILHOUETTE (С‰РёС‚С‹ С…СЌС€-РІ-С…СЌС€ СЃРѕРІРїР°РґР°СЋС‚ РїРѕ РїРѕСЃС‚СЂРѕРµРЅРёСЋ вЂ” С„РѕСЂРјР° РѕР±С‰Р°СЏ):
const PIN_SILHOUETTE := {
	"staff_apprentice": "414EDA4B", "staff_oak": "B7E43346", "staff_rune": "FDC77A90",
	"bow_hunter": "C5B70EF2", "bow_heavy": "B1B0ED5E",
	"shield_iron": "C43D6FB6", "shield_raven": "C43D6FB6",
}
## Р›РµРіР°СЃРё-С‚СЂРёРѕ: СЂРёСЃСѓСЋС‚СЃСЏ СЌС‚РёРј РёРЅСЃС‚СЂСѓРјРµРЅС‚РѕРј, РїРёРЅ СЃ СЂРѕР¶РґРµРЅРёСЏ (25.11, t14):
const PIN_LEGACY := {
	"sword": "09B98076", "axe": "CBADE922", "rune_blade": "8EE56A39",
}
## Р‘Р°Р№С‚-С†РµР»РѕСЃС‚РЅРѕСЃС‚СЊ С„Р°Р№Р»Р° (md5 Р°СЂС‚РµС„Р°РєС‚Р° Р±РµР№РєР°; СЃРёРЅС…СЂРѕРЅРёР·РѕРІР°РЅ СЃ РїРёРЅРѕРј qa_lp C33):
const PIN_ATLAS_MD5 := "12a1052a2c859abf6c2f8cae788de1d8"

var _fails := 0
var _allowed := {}
var _cv: Image = null

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "bake"
	var target := String(WW.ATLAS_PATH)
	if args.size() > 0:
		mode = String(args[0])
	if args.size() > 1:
		target = String(args[1])
	_allowed = P.color_index()  # РјРёСЂРѕРІРѕР№ Р°С‚Р»Р°СЃ: RAMPS+FLATS, С‚РµС…С†РІРµС‚РѕРІ РЅРµС‚
	if mode == "bake":
		_bake(target)
	else:
		_check(target)
	print("[weapons] %s" % ("SELF-CHECK: PASS" if _fails == 0 else "SELF-CHECK: FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)

# ------------------------------------------------------------------ РєР°РґСЂС‹

## Р“РѕР»С‹Р№ РєР°РґСЂ id (16x16, РїСЂРѕР·СЂР°С‡РЅС‹Р№ С„РѕРЅ): 9 РїРѕР·РёС†РёР№ вЂ” СЂРёСЃРѕРІР°Р»РєРё UiIcons
## (РґРѕСЃР»РѕРІРЅРѕ РєР°Рє Р»РёСЃС‚, _bare_img), 3 Р»РµРіР°СЃРё вЂ” Р»РѕРєР°Р»СЊРЅС‹Рµ СЂРёСЃРѕРІР°Р»РєРё РєРѕСЂСЏРіРё.
## STATIC: qa_gear G9 СЃРІРµСЂСЏРµС‚ СЂР°РЅС‚Р°Р№Рј-Р°С‚Р»Р°СЃ СЃ Р­РўРРњ Р–Р• СЂРёСЃРѕРІР°Р»СЊС‰РёРєРѕРј.
static func _frame(id: String) -> Image:
	var img := Image.create(WW.SLOT, WW.SLOT, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match id:
		"shortsword", "nordsword", "staff_apprentice", "staff_oak", "staff_rune", "bow_hunter", "bow_heavy", "shield_iron", "shield_raven":
			UI._cv = img
			UI._cv_ox = 0
			match id:
				"shortsword": UI._ic_item_shortsword()
				"nordsword": UI._ic_item_nordsword()
				"staff_apprentice": UI._ic_item_staff_apprentice()
				"staff_oak": UI._ic_item_staff_oak()
				"staff_rune": UI._ic_item_staff_rune()
				"bow_hunter": UI._ic_item_bow_hunter()
				"bow_heavy": UI._ic_item_bow_heavy()
				"shield_iron": UI._ic_item_shield_iron()
				"shield_raven": UI._ic_item_shield_raven()
			UI._cv = null
			UI._cv_ox = 0
		"sword": _paint_sword(img)
		"axe": _paint_axe(img)
		"rune_blade": _paint_rune_blade(img)
		_:
			print("[FAIL] РЅРµРёР·РІРµСЃС‚РЅС‹Р№ СЃР»РѕС‚: %s" % id)
	return img

## SILHOUETTE-СЂСЏРґ вЂ” РґРѕСЃР»РѕРІРЅС‹Р№ РґРІРѕР№РЅРёРє sheet_weapons_v1._sil_img (25.11):
## С„РѕСЂРјР°, Р·Р°Р»РёС‚Р°СЏ CHAR DARK; СЃРІРµС‚РѕРІРѕР№ РєР°РЅС‚ BONE LIGHT, РіРґРµ СЃРІРµСЂС…Сѓ РёР»Рё СЃР»РµРІР°
## РїСѓСЃС‚РѕС‚Р° (РєР°РЅС‚ В«РѕС‚РєСЂС‹С‚РѕР№ РіСЂР°РЅРёВ»).
static func _sil(src: Image) -> Image:
	var img := Image.create(WW.SLOT, WW.SLOT, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body: Color = P.RAMPS["CHAR"][P.T_DARK]
	var rim: Color = P.RAMPS["BONE"][P.T_LIGHT]
	for y in WW.SLOT:
		for x in WW.SLOT:
			if src.get_pixel(x, y).a < 0.5:
				continue
			var up_empty := y == 0 or src.get_pixel(x, y - 1).a < 0.5
			var left_empty := x == 0 or src.get_pixel(x - 1, y).a < 0.5
			img.set_pixel(x, y, rim if (up_empty or left_empty) else body)
	return img

# ------------------------------------------------------- Р»РµРіР°СЃРё-С‚СЂРёРѕ РєРѕСЂСЏРіРё
# РЇР·С‹Рє вЂ” С‚РѕС‚ Р¶Рµ, С‡С‚Рѕ Сѓ Р»РёСЃС‚РѕРІС‹С… СЂРёСЃРѕРІР°Р»РѕРє UiIcons: СЂР°РјРїС‹ PixelPalette,
# РЎР—-СЃРІРµС‚ (LIGHT РІРµСЂС…/Р»РµРІРѕ, DARK РїСЂР°РІС‹Р№ Р±РѕРє, OUTLINE РЅРёР¶РЅРёР№ РєСЂР°Р№). РљРѕСЂСЏРіР°:
# СЂСѓРєРѕСЏС‚СЊ вЂ” СЃСѓС‡РєРѕРІР°С‚Р°СЏ РєРѕСЂР° BARK, СЃС‚Р°Р»СЊ IRON, Р»Р°С‚СѓРЅСЊ BRONZE.

static func _pt(img: Image, x: int, y: int, ramp: String, tone: int) -> void:
	if x < 0 or y < 0 or x >= WW.SLOT or y >= WW.SLOT:
		return
	img.set_pixel(x, y, P.c(ramp, tone))

static func _paint_sword(img: Image) -> void:
	# В«РњРµС‡ Р“СЂРёРёРјР°В»: РґР»РёРЅРЅРѕРµ РїСЂСЏРјРѕРµ РїРѕР»РѕС‚РЅРѕ, С€РёСЂРѕРєР°СЏ РіР°СЂРґР°, СЃСѓС‡РєРѕРІР°С‚РѕРµ РґСЂРµРІРєРѕ
	_pt(img, 8, 1, "IRON", P.T_LIGHT)
	for y in range(2, 8):
		_pt(img, 7, y, "IRON", P.T_LIGHT)
		_pt(img, 8, y, "IRON", P.T_MID)
		_pt(img, 9, y, "IRON", P.T_DARK)
	for x in range(5, 12):  # РіР°СЂРґР°
		_pt(img, x, 8, "IRON", P.T_OUTLINE)
	_pt(img, 5, 8, "BRONZE", P.T_LIGHT)
	_pt(img, 11, 8, "BRONZE", P.T_DARK)
	for y in range(9, 13):  # РґСЂРµРІРєРѕ-РєРѕСЂСЏРіР° (СЃСѓС‡РѕРє СЃР»РµРІР° РЅР° 11)
		_pt(img, 8, y, "BARK", P.T_MID if y % 2 == 0 else P.T_LIGHT)
	_pt(img, 7, 11, "BARK", P.T_DARK)
	_pt(img, 8, 13, "BRONZE", P.T_OUTLINE)

static func _paint_axe(img: Image) -> void:
	# В«Р‘РѕРµРІРѕР№ С‚РѕРїРѕСЂВ»: РёР·РѕРіРЅСѓС‚РѕРµ С‚РѕРїРѕСЂРёС‰Рµ-РєРѕСЂСЏРіР°, Р¶РµР»РµР·РЅР°СЏ РіРѕР»РѕРІР° СЃ РѕР±СѓС…РѕРј
	for y in range(3, 15):  # С‚РѕРїРѕСЂРёС‰Рµ РїРѕ РґРёР°РіРѕРЅР°Р»Рё РІРЅРёР·-РІР»РµРІРѕ
		var x := 9 if y < 8 else (8 if y < 12 else 7)
		_pt(img, x, y, "BARK", P.T_MID)
		_pt(img, x + 1, y, "BARK", P.T_DARK)
	_pt(img, 7, 14, "BARK", P.T_OUTLINE)
	_pt(img, 8, 14, "BARK", P.T_OUTLINE)
	# РіРѕР»РѕРІР°: РІРµСЂС…РЅРёР№ Р·СѓР± Рё Р±СЂСЋС…Рѕ СЃРїСЂР°РІР°
	for x in range(9, 13):
		_pt(img, x, 2, "IRON", P.T_LIGHT)
		_pt(img, x, 3, "IRON", P.T_MID)
	_pt(img, 12, 4, "IRON", P.T_MID)
	_pt(img, 11, 5, "IRON", P.T_MID)
	_pt(img, 12, 5, "IRON", P.T_DARK)
	_pt(img, 11, 6, "IRON", P.T_DARK)
	_pt(img, 12, 6, "IRON", P.T_OUTLINE)
	_pt(img, 9, 4, "IRON", P.T_OUTLINE)

static func _paint_rune_blade(img: Image) -> void:
	# В«РљР»РёРЅРѕРє СЂСѓРЅВ» (СЂСѓРЅРЅС‹Р№ РґРѕР·РѕСЂ Р СѓРЅРЅРѕРіРѕ РєР°РјРЅСЏ): РґРёР°РіРѕРЅР°Р»СЊ СЃС‚Р°Р»Рё, СЂСѓРЅС‹ CRYSTAL
	var diag := [[3, 12], [4, 11], [5, 10], [6, 9], [7, 8], [8, 7], [9, 6], [10, 5], [11, 4]]
	for p in diag:
		_pt(img, int(p[0]), int(p[1]), "IRON", P.T_MID)
		_pt(img, int(p[0]) + 1, int(p[1]), "IRON", P.T_DARK)
	_pt(img, 12, 3, "IRON", P.T_LIGHT)
	_pt(img, 13, 2, "IRON", P.T_LIGHT)
	_pt(img, 12, 4, "IRON", P.T_OUTLINE)
	_pt(img, 2, 13, "IRON", P.T_OUTLINE)
	# РіР°СЂРґР°-СѓРїРѕСЂ Рё РЅР°РІРµСЂС€РёРµ-РєРѕСЂСЏРіР°
	_pt(img, 4, 13, "IRON", P.T_OUTLINE)
	_pt(img, 3, 12, "BARK", P.T_MID)
	_pt(img, 2, 14, "BARK", P.T_OUTLINE)
	# СЂСѓРЅС‹ РЅР° РїРѕР»РѕС‚РЅРµ
	_pt(img, 6, 9, "CRYSTAL", P.T_LIGHT)
	_pt(img, 8, 7, "CRYSTAL", P.T_MID)
	_pt(img, 10, 5, "CRYSTAL", P.T_LIGHT)

# ------------------------------------------------------------------ Р°С‚Р»Р°СЃ

func _atlas() -> Image:
	var img := Image.create(WW.SLOT * WW.SLOTS.size(), WW.SLOT * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in WW.SLOTS.size():
		var id := String(WW.SLOTS[i])
		var bare := _frame(id)
		var sil := _sil(bare)
		for y in WW.SLOT:
			for x in WW.SLOT:
				img.set_pixel(i * WW.SLOT + x, y, bare.get_pixel(x, y))
				img.set_pixel(i * WW.SLOT + x, WW.SLOT + y, sil.get_pixel(x, y))
	return img

func _bake(target: String) -> void:
	var a := _atlas()
	var b := _atlas()
	if a.save_png_to_buffer() != b.save_png_to_buffer():
		_fails += 1
		print("[FAIL] double-bake СЂР°Р·РѕС€С‘Р»СЃСЏ")
	_print_frames(a)
	_scan(a)
	_pins_frames(a)
	if _fails > 0:
		return
	var err := a.save_png(target)
	print("[bake] %s %dx%d err=%d atlas-hash:%s" % [target, a.get_width(), a.get_height(), err, _fnv32_hex(a)])
	if err != OK:
		_fails += 1

func _check(target: String) -> void:
	if not ResourceLoader.exists(target):
		_fails += 1
		print("[FAIL] %s РЅРµС‚ РІ РґРµСЂРµРІРµ" % target)
		return
	var img: Image = load(target).get_image()
	var W := WW.SLOT * WW.SLOTS.size()
	if img.get_width() != W or img.get_height() != WW.SLOT * 2:
		_fails += 1
		print("[FAIL] РіРµРѕРјРµС‚СЂРёСЏ %dx%d (Р¶РґР°Р»Рё %dx%d)" % [img.get_width(), img.get_height(), W, WW.SLOT * 2])
	_scan(img)
	# РґРёР°Рі: РїРёРєСЃРµР»СЊРЅРѕРµ СЂР°РІРµРЅСЃС‚РІРѕ РґРµРєРѕРґРёСЂРѕРІР°РЅРЅРѕРіРѕ Р°С‚Р»Р°СЃР° РїР°РјСЏС‚Рё СЂРёСЃРѕРІР°Р»РєРё.
	# РЎРµРјР°РЅС‚РёРєР° В«СЂРёСЃСѓРЅРєР°В»: РіРґРµ alpha==0 вЂ” RGB РЅРµ РЅРµСЃС‘С‚ СЃРјС‹СЃР»Р° (PNG-С„РёР»СЊС‚СЂС‹
	# РґРѕСЃС‚СЂР°РёРІР°СЋС‚ РµРіРѕ РїРѕРґ РїСЂРѕР·СЂР°С‡РЅРѕСЃС‚СЊСЋ), СЃСЂР°РІРЅРёРІР°РµРј alpha-РјР°СЃРєСѓ Рё RGB С‚Р°Рј,
	# РіРґРµ РїРёРєСЃРµР»СЊ РЅРµРїСЂРѕР·СЂР°С‡РµРЅ.
	var px_diff_total := 0
	for i in WW.SLOTS.size():
		var id := String(WW.SLOTS[i])
		for row in 2:
			var a := _frame(id) if row == 0 else _sil(_frame(id))
			var b := _frame_of(img, i, row)
			var d := 0
			for y in WW.SLOT:
				for x in WW.SLOT:
					var ca: Color = a.get_pixel(x, y)
					var cb: Color = b.get_pixel(x, y)
					if (ca.a > 0.5) != (cb.a > 0.5):
						d += 1
					elif ca.a > 0.5 and (ca.to_rgba32() & 0xFFFFFF) != (cb.to_rgba32() & 0xFFFFFF):
						d += 1
			px_diff_total += d
	print("[pxeq] РґРµРєРѕРґРёСЂРѕРІР°РЅРЅС‹Р№ Р°С‚Р»Р°СЃ == СЂРёСЃРѕРІР°Р»РєР° (alpha+RGB): diff=%d %s" % [px_diff_total, "PASS" if px_diff_total == 0 else "FAIL"])
	if px_diff_total > 0:
		_fails += 1
	# РїРёРЅС‹ FNV вЂ” РїРµС‡Р°С‚Р°СЋС‚СЃСЏ РґР»СЏ СЃРїСЂР°РІРєРё: РїРѕР±Р°Р№С‚РѕРІРѕРµ СЂР°РІРµРЅСЃС‚РІРѕ Р»РёСЃС‚Сѓ РґРѕРєР°Р·С‹РІР°РµС‚
	# bake-СЂРµР¶РёРј (РёРЅ-РїР°РјСЏС‚Рё, С‚РѕС‚ Р¶Рµ СЌРЅРєРѕРґРµСЂ, С‡С‚Рѕ Рё Сѓ Р»РёСЃС‚Р°); СЂР°РЅС‚Р°Р№Рј Р¶Рµ РѕР±СЏР·Р°РЅ
	# СЃРѕРІРїР°РґР°С‚СЊ РџРћ РџРРљРЎР•Р›РЇРњ ([pxeq] РІС‹С€Рµ) + С„Р°Р№Р» РїРѕР±Р°Р№С‚РѕРІРѕ (md5 РЅРёР¶Рµ).
	_print_frames(img)
	var md5 := _md5_file(target)
	var ok_md5 := md5 == PIN_ATLAS_MD5
	if not ok_md5:
		_fails += 1
	print("[md5 ] %s want:%s got:%s %s" % [target.get_file(), PIN_ATLAS_MD5, md5, "PASS" if ok_md5 else "FAIL"])

## РљР°РґСЂ РёР· (РІРѕР·РјРѕР¶РЅРѕ, РґРµРєРѕРґРёСЂРѕРІР°РЅРЅРѕРіРѕ) Р°С‚Р»Р°СЃР° -> FNV РїРµСЂРµРєРѕРґРёСЂРѕРІР°РЅРЅРѕРіРѕ 16x16.
static func _frame_of(img: Image, i: int, row: int) -> Image:
	return img.get_region(Rect2i(i * WW.SLOT, row * WW.SLOT, WW.SLOT, WW.SLOT))

func _print_frames(img: Image) -> void:
	for i in WW.SLOTS.size():
		var id := String(WW.SLOTS[i])
		for row in 2:
			var fr := _frame_of(img, i, row)
			var n := 0
			for y in WW.SLOT:
				for x in WW.SLOT:
					if fr.get_pixel(x, y).a > 0.5:
						n += 1
			if n < 12:
				_fails += 1
			print("[frame] %s row%d px:%3d hash:%s %s" % [id, row, n, _fnv32_hex(fr), "PASS" if n >= 12 else "FAIL"])

func _pins_frames(img: Image) -> void:
	for id in PIN_KORYAGA:
		var i := WW.SLOTS.find(id)
		if _pin_one(img, i, 0, String(PIN_KORYAGA[id]), "KORYAGA " + id):
			pass
	for id in PIN_SILHOUETTE:
		var i := WW.SLOTS.find(id)
		_pin_one(img, i, 1, String(PIN_SILHOUETTE[id]), "SIL " + id)
	for id in PIN_LEGACY:
		var i := WW.SLOTS.find(id)
		_pin_one(img, i, 0, String(PIN_LEGACY[id]), "LEGACY " + id)

func _pin_one(img: Image, i: int, row: int, want: String, nm: String) -> bool:
	if i < 0:
		_fails += 1
		print("[FAIL] %s: СЃР»РѕС‚Р° РЅРµС‚ РІ SLOTS" % nm)
		return false
	var got := _fnv32_hex(_frame_of(img, i, row))
	var ok := got == want
	if not ok:
		_fails += 1
	print("[pin ] %-24s want:%s got:%s %s" % [nm, want, got, "PASS" if ok else "FAIL"])
	return ok

## РџР°Р»РёС‚СЂР° РјРёСЂРѕРІРѕРіРѕ Р°С‚Р»Р°СЃР°: С‚РѕР»СЊРєРѕ RAMPS/FLATS (С‚РµС…С†РІРµС‚РѕРІ СЃР»РѕС‚Р° Р±С‹С‚СЊ РЅРµ РјРѕР¶РµС‚).
func _scan(img: Image) -> void:
	var off := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a > 0.5 and not _allowed.has(P.key(col)):
				off += 1
	if off > 0:
		_fails += 1
	print("[scan] РїР°Р»РёС‚СЂР° off=%d %s" % [off, "PASS" if off == 0 else "FAIL"])

static func _fnv32_hex(img: Image) -> String:
	var h := 2166136261
	for b in img.save_png_to_buffer():
		h = int(((h ^ int(b)) * 16777619) & 0xFFFFFFFF)
	return "%08X" % h

func _md5_file(path: String) -> String:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var buf := f.get_buffer(65536)
	while buf.size() > 0:
		ctx.update(buf)
		buf = f.get_buffer(65536)
	return ctx.finish().hex_encode()
