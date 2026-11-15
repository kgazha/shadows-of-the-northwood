extends SceneTree
## c22/c23: попиксельная карта перекраски персонажей на PixelPalette.
## Утверждена вердиктом пользователя по листу c22 (sheet на вердикт).
## Таблица корзин B — ЕДИНСТВЕННЫЙ источник карты (606 соответствий легаси-цвет
## -> канон для 13 атласов описи c17 §1). Здесь же: режим --rebake (перепёк
## ассетов в игре, c23) и режим листа (c22, на вердикт).
## Детерминировано: обход по отсортированным ключам, никаких randf.
## Альфа переносится побайтово; пиксели не добавляются и не удаляются.

const SHEET_W := 1180

# 13 атласов описи c17 §1 (имя атласа -> файл ассета).
const ASSETS := {
	"class_warrior": "res://assets/class_warrior.png",
	"class_archer": "res://assets/class_archer.png",
	"class_mage": "res://assets/class_mage.png",
	"npc_elder": "res://assets/npc_elder.png",
	"npc_farmer": "res://assets/npc_farmer.png",
	"npc_hermit": "res://assets/npc_hermit.png",
	"npc_merchant": "res://assets/npc_merchant.png",
	"npc_smith": "res://assets/npc_smith.png",
	"slime": "res://assets/slime.png",
	"swarmling": "res://assets/mobs_swarmling.png",
	"mob_archer": "res://assets/mobs_archer.png",
	"wraith": "res://assets/mobs_wraith.png",
	"brute": "res://assets/brute.png",
}

# --- спецификация корзин ------------------------------------------------------
# [ atlas, name, h0, h1, s0, s1, v0, v1, ramp_hi, ramp_lo_or_"", vlo ]
const B := [
	# герой-воин: сталь/холодное, кожа, кожа-тень, красная ткань, тёплое, нейтральное
	["class_warrior", "steel", 200, 250, 0.06, 1.0, 0.0, 1.0, "IRON", "", 0.0],
	["class_warrior", "neutral", 0, 360, 0.0, 0.06, 0.0, 1.0, "IRON", "CHAR", 0.30],
	["class_warrior", "red", 350, 12, 0.35, 1.0, 0.0, 1.0, "HP_RED", "", 0.0],
	["class_warrior", "skin", 15, 33, 0.30, 0.55, 0.55, 1.0, "BONE", "", 0.0],
	["class_warrior", "skin_shadow", 5, 33, 0.20, 1.0, 0.0, 0.55, "PATH", "CHAR", 0.22],
	["class_warrior", "warm_mid", 0, 40, 0.06, 1.0, 0.30, 1.0, "WOOD", "CHAR", 0.25],
	["class_warrior", "red_low", 350, 15, 0.10, 1.0, 0.0, 0.40, "HP_RED", "", 0.0],
	["class_warrior", "warm_dark", 0, 60, 0.10, 1.0, 0.0, 0.30, "CHAR", "", 0.0],
	# герой-лучник: листва, кожа, золото, кожа-тень, дерево, оливковый низ, нейтральное
	["class_archer", "leaf", 85, 165, 0.15, 1.0, 0.0, 1.0, "LEAF", "", 0.0],
	["class_archer", "skin", 20, 33, 0.30, 0.50, 0.55, 1.0, "BONE", "", 0.0],
	["class_archer", "gold", 40, 48, 0.08, 0.25, 0.60, 1.0, "HUD_GOLD", "", 0.0],
	["class_archer", "skin_shadow", 0, 35, 0.20, 1.0, 0.0, 0.55, "PATH", "CHAR", 0.20],
	["class_archer", "wood", 22, 40, 0.25, 1.0, 0.25, 1.0, "WOOD", "", 0.0],
	["class_archer", "olive_low", 40, 70, 0.10, 1.0, 0.0, 0.40, "PINE", "CHAR", 0.20],
	["class_archer", "cool_low", 165, 210, 0.10, 1.0, 0.0, 0.35, "CAVE_WATER", "", 0.0],
	["class_archer", "neutral", 0, 360, 0.0, 0.10, 0.0, 1.0, "STONE", "CHAR", 0.25],
	# маг: мантия-фиолет -> UI_BLUE, золото оторочки, кожа, кожа-тень, подбой
	["class_mage", "gold", 36, 44, 0.40, 1.0, 0.0, 1.0, "HUD_GOLD", "", 0.0],
	["class_mage", "purple", 245, 300, 0.15, 1.0, 0.30, 1.0, "UI_BLUE", "", 0.0],
	["class_mage", "purple_low", 245, 300, 0.10, 1.0, 0.0, 0.30, "UI_BLUE", "INK", 0.16],
	["class_mage", "skin", 20, 33, 0.30, 0.50, 0.55, 1.0, "BONE", "", 0.0],
	["class_mage", "skin_shadow", 0, 35, 0.20, 1.0, 0.0, 0.55, "PATH", "CHAR", 0.20],
	["class_mage", "warm", 30, 45, 0.30, 0.50, 0.0, 1.0, "BRONZE", "CHAR", 0.22],
	["class_mage", "warm_low", 0, 30, 0.15, 1.0, 0.0, 0.30, "CHAR", "", 0.0],
	["class_mage", "cool_gray", 240, 340, 0.05, 0.20, 0.0, 1.0, "CAVE_ROCK", "", 0.0],
	# жители: специфичное по атласу, затем общие кожа/тень/нейтраль/тёмное
	["npc_elder", "blue_white", 220, 250, 0.0, 0.10, 0.55, 1.0, "STONE", "", 0.0],
	["npc_elder", "robe", 220, 300, 0.10, 1.0, 0.0, 1.0, "UI_BLUE", "", 0.0],
	["npc_farmer", "green", 85, 165, 0.15, 1.0, 0.0, 1.0, "GRASS", "", 0.0],
	["npc_merchant", "gold", 38, 48, 0.25, 1.0, 0.35, 1.0, "BRONZE", "", 0.0],
	["npc_smith", "apron_warm", 190, 250, 0.20, 1.0, 0.0, 1.0, "WOOD", "", 0.0],
	["npc_smith", "beard_warm", 15, 30, 0.40, 1.0, 0.30, 1.0, "BONE", "", 0.0],
	["npc_hermit", "cloak_cool", 200, 260, 0.02, 0.20, 0.0, 1.0, "BONE", "STONE", 0.45],
	["npc_elder", "skin", 15, 33, 0.25, 0.55, 0.55, 1.0, "BONE", "", 0.0],
	["npc_farmer", "skin", 15, 33, 0.25, 0.55, 0.55, 1.0, "BONE", "", 0.0],
	["npc_hermit", "skin", 15, 33, 0.20, 0.55, 0.55, 1.0, "BONE", "", 0.0],
	["npc_merchant", "skin", 15, 33, 0.25, 0.55, 0.55, 1.0, "BONE", "", 0.0],
	["npc_smith", "skin", 15, 33, 0.35, 0.55, 0.60, 1.0, "BONE", "", 0.0],
	["npc_elder", "skin_shadow", 0, 35, 0.20, 1.0, 0.0, 0.55, "PATH", "CHAR", 0.20],
	["npc_farmer", "skin_shadow", 0, 35, 0.20, 1.0, 0.0, 0.55, "PATH", "CHAR", 0.20],
	["npc_hermit", "skin_shadow", 0, 40, 0.15, 1.0, 0.0, 0.55, "PATH", "CHAR", 0.20],
	["npc_merchant", "skin_shadow", 0, 35, 0.20, 1.0, 0.0, 0.55, "PATH", "CHAR", 0.20],
	["npc_smith", "skin_shadow", 0, 35, 0.20, 1.0, 0.0, 0.60, "PATH", "CHAR", 0.20],
	["npc_elder", "neutral", 0, 360, 0.0, 0.10, 0.0, 1.0, "STONE", "CHAR", 0.30],
	["npc_farmer", "neutral", 0, 360, 0.0, 0.10, 0.0, 1.0, "STONE", "CHAR", 0.30],
	["npc_hermit", "neutral", 0, 360, 0.0, 0.02, 0.0, 1.0, "STONE", "CHAR", 0.30],
	["npc_merchant", "neutral", 0, 360, 0.0, 0.10, 0.0, 1.0, "STONE", "CHAR", 0.30],
	["npc_smith", "neutral", 0, 360, 0.0, 0.35, 0.0, 1.0, "STONE", "CHAR", 0.20],
	["npc_elder", "warm_low", 0, 60, 0.10, 1.0, 0.0, 0.45, "CHAR", "", 0.0],
	["npc_farmer", "warm_low", 0, 60, 0.10, 1.0, 0.0, 0.45, "CHAR", "", 0.0],
	["npc_hermit", "warm_low", 0, 60, 0.10, 1.0, 0.0, 0.45, "CHAR", "", 0.0],
	["npc_merchant", "warm_low", 0, 60, 0.10, 1.0, 0.0, 0.45, "CHAR", "", 0.0],
	["npc_smith", "warm_low", 0, 60, 0.35, 1.0, 0.0, 0.45, "CHAR", "", 0.0],
	# слайм: тело-зелень, кристальные блики (ледяной отклик), холодный низ
	["slime", "teal", 160, 185, 0.20, 1.0, 0.30, 1.0, "CRYSTAL", "", 0.0],
	["slime", "body", 85, 155, 0.15, 1.0, 0.0, 1.0, "GRASS", "", 0.0],
	["slime", "cool_low", 155, 210, 0.10, 1.0, 0.0, 0.30, "GRASS", "CAVE_WATER", 0.17],
	["slime", "neutral", 0, 360, 0.0, 0.10, 0.0, 1.0, "GRASS", "CHAR", 0.20],
	# мглокрыс: «тень-крыс» — угольное тело (паритет с теневой природой; бурые
	# лучники-легаси теперь WOOD/PATH), бирюза свечения, кость
	["swarmling", "teal", 160, 185, 0.20, 1.0, 0.0, 1.0, "WATER", "", 0.0],
	["swarmling", "light_bone", 30, 60, 0.0, 0.15, 0.60, 1.0, "BONE", "", 0.0],
	["swarmling", "cool", 200, 260, 0.10, 1.0, 0.0, 1.0, "CHAR", "", 0.0],
	["swarmling", "body", 0, 60, 0.05, 1.0, 0.30, 1.0, "CHAR", "", 0.0],
	["swarmling", "body_low", 0, 60, 0.05, 1.0, 0.0, 0.30, "CHAR", "", 0.0],
	["swarmling", "neutral", 0, 360, 0.0, 0.06, 0.0, 1.0, "CAVE_ROCK", "CHAR", 0.20],
	# моб-лучник: листва плаща, дерево/кожа, красная перевязь, кожа, сталь
	["mob_archer", "leaf", 85, 165, 0.15, 1.0, 0.0, 1.0, "LEAF", "", 0.0],
	["mob_archer", "red", 350, 15, 0.30, 1.0, 0.0, 1.0, "HP_RED", "", 0.0],
	["mob_archer", "wood", 24, 40, 0.28, 1.0, 0.25, 1.0, "WOOD", "", 0.0],
	["mob_archer", "skin", 20, 35, 0.25, 0.45, 0.55, 1.0, "BONE", "", 0.0],
	["mob_archer", "cool_low", 165, 210, 0.10, 1.0, 0.0, 0.30, "PINE", "CAVE_WATER", 0.16],
	["mob_archer", "olive_low", 40, 85, 0.10, 1.0, 0.0, 0.42, "PINE", "CHAR", 0.20],
	["mob_archer", "neutral_light", 0, 360, 0.0, 0.15, 0.35, 1.0, "IRON", "", 0.0],
	["mob_archer", "skin_shadow", 0, 30, 0.15, 1.0, 0.0, 0.55, "PATH", "CHAR", 0.19],
	["mob_archer", "neutral", 0, 360, 0.0, 0.20, 0.0, 0.45, "CAVE_ROCK", "CHAR", 0.22],
	# тенеплёт: мистика -> холодный камень пещеры; светлый акцент; контур
	["wraith", "purple_hi", 250, 290, 0.20, 1.0, 0.45, 1.0, "CAVE_ROCK", "", 0.0],
	["wraith", "purple_mid", 250, 290, 0.20, 1.0, 0.20, 0.45, "CAVE_ROCK", "CAVE_ROCK", 0.0],
	["wraith", "purple_low", 240, 300, 0.10, 1.0, 0.0, 0.20, "CAVE_ROCK", "CHAR", 0.10],
	["wraith", "neutral", 0, 360, 0.0, 0.16, 0.0, 1.0, "ASH_GROUND", "CHAR", 0.40],
	# брутал/ведьма: тело — светящийся мох (легаси-зелень), магия — синь,
	# красный ярости, кость/светлое, угольное
	["brute", "magic_hi", 250, 290, 0.20, 1.0, 0.60, 1.0, "UI_BLUE", "", 0.0],
	["brute", "magic_mid", 250, 290, 0.20, 1.0, 0.0, 0.60, "UI_BLUE", "", 0.0],
	["brute", "body", 80, 120, 0.15, 1.0, 0.0, 1.0, "MOSS_GLOW", "", 0.0],
	["brute", "red", 348, 8, 0.40, 1.0, 0.0, 1.0, "HP_RED", "", 0.0],
	["brute", "light", 30, 60, 0.0, 0.15, 0.60, 1.0, "BONE", "", 0.0],
	["brute", "neutral", 0, 360, 0.0, 0.22, 0.0, 1.0, "CHAR", "", 0.0],
	["brute", "warm_low", 10, 30, 0.22, 1.0, 0.0, 0.30, "CHAR", "", 0.0],
]

# ---------------------------------------------------------------- статическое ядро карты
static func _lum_s(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

static func _col_s(k: int) -> Color:
	return Color(((k >> 16) & 255) / 255.0, ((k >> 8) & 255) / 255.0, (k & 255) / 255.0)

static func _k_s(c: Color) -> int:
	return int(((int(round(c.a * 255.0)) << 24) | (int(round(c.r * 255.0)) << 16)
		| (int(round(c.g * 255.0)) << 8) | int(round(c.b * 255.0))))

static func _in_band_s(v: float, lo: float, hi: float) -> bool:
	if lo <= hi:
		return v >= lo and v <= hi
	return v >= lo or v <= hi  # оборотная полоса hue

static func _bucket_for_s(atlas: String, k: int) -> Dictionary:
	var c := _col_s(k)
	var hdeg := c.h * 360.0
	for bd in B:
		if String(bd[0]) != atlas:
			continue
		if not _in_band_s(hdeg, float(bd[2]), float(bd[3])):
			continue
		if not _in_band_s(c.s, float(bd[4]), float(bd[5])):
			continue
		if not _in_band_s(c.v, float(bd[6]), float(bd[7])):
			continue
		return {"name": String(bd[1]), "hi": String(bd[8]), "lo": String(bd[9]), "vlo": float(bd[10])}
	return {}

static func _ramp_used_s(b: Dictionary, c: Color) -> String:
	if String(b["lo"]) != "" and c.v < float(b["vlo"]):
		return String(b["lo"])
	return String(b["hi"])

static func _bucket_target_s(b: Dictionary, c: Color) -> Color:
	var rn := _ramp_used_s(b, c)
	if not PixelPalette.RAMPS.has(rn):
		return PixelPalette.FLATS[rn]
	var ramp: Array = PixelPalette.RAMPS[rn]
	var best: Color = ramp[0]
	var bd2 := 9e9
	for t in ramp.size():
		var rc: Color = ramp[t]
		var d := absf(_lum_s(rc) - _lum_s(c))
		if d < bd2:
			bd2 = d
			best = rc
	return best

static func _nearest_s(c: Color) -> Color:
	var bi := -1
	var bd := 9e9
	var cl := _lum_s(c)
	var i := -1
	for rn in PixelPalette.RAMPS:
		var ramp: Array = PixelPalette.RAMPS[rn]
		for rc0 in ramp:
			i += 1
			var rc: Color = rc0
			var d: float = (c.r - rc.r) * (c.r - rc.r) * 3.0 \
				+ (c.g - rc.g) * (c.g - rc.g) * 4.0 \
				+ (c.b - rc.b) * (c.b - rc.b) * 2.0 + absf(cl - _lum_s(rc)) * 0.15
			if d < bd:
				bd = d
				bi = i
	i = -1
	for fn in PixelPalette.FLATS:
		var c2: Color = PixelPalette.FLATS[fn]
		i += 1
		var d2: float = (c.r - c2.r) * (c.r - c2.r) * 3.0 \
			+ (c.g - c2.g) * (c.g - c2.g) * 4.0 \
			+ (c.b - c2.b) * (c.b - c2.b) * 2.0 + absf(cl - _lum_s(c2)) * 0.15
		if d2 < bd:
			bd = d2
			bi = 1000 + i
	if bi < 1000:
		var rr := 0
		for rn2 in PixelPalette.RAMPS:
			var ramp2: Array = PixelPalette.RAMPS[rn2]
			for rc2 in ramp2:
				if rr == bi:
					return rc2
				rr += 1
	var ff := 0
	for fn2 in PixelPalette.FLATS:
		if ff == bi - 1000:
			return PixelPalette.FLATS[fn2]
		ff += 1
	return Color(0, 0, 0)

## Единая точка карты: легаси-цвет атласа -> {t: argb цели, b: подпись корзины}.
static func target_for(atlas: String, k_rgb: int) -> Dictionary:
	var k := int(0xFF000000) | (k_rgb & 0x00FFFFFF)
	var c := _col_s(k)
	var idx := PixelPalette.color_index()
	if idx.has(k):
		return {"t": k, "b": "on-palette"}
	var b := _bucket_for_s(atlas, k)
	if b.is_empty():
		var nf := _nearest_s(c)
		return {"t": _k_s(Color(nf.r, nf.g, nf.b, 1.0)), "b": "fallback"}
	var tgt := _bucket_target_s(b, c)
	return {"t": _k_s(Color(tgt.r, tgt.g, tgt.b, 1.0)),
		"b": String(b["name"]) + ":" + _ramp_used_s(b, c)}

## Побайтовая перекраска кадра: альфа сохраняется, геометрия не меняется.
static func recolor_atlas(atlas: String, img: Image) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var e: Dictionary = target_for(atlas, _k_s(Color(c.r, c.g, c.b, 1.0)) & 0x00FFFFFF)
			var t := _col_s(int(e["t"]))
			out.set_pixel(x, y, Color(t.r, t.g, t.b, c.a))
	return out

## Перепёк ассетов в игре (c23). save=false — только отчёт.
static func rebake_all(save: bool) -> Dictionary:
	var res := {}
	var cidx := PixelPalette.color_index()
	for a in ASSETS:
		var bytes := FileAccess.get_file_as_bytes(String(ASSETS[a]))
		var img := Image.new()
		if img.load_png_from_buffer(bytes) != OK:
			res[a] = {"err": "load"}
			continue
		var off_b := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0 and not cidx.has(_k_s(Color(c.r, c.g, c.b, 1.0))):
					off_b += 1
		var out := recolor_atlas(String(a), img)
		var alpha_ok := out.get_width() == img.get_width() and out.get_height() == img.get_height()
		if alpha_ok:
			for y in img.get_height():
				for x in img.get_width():
					if int(round(img.get_pixel(x, y).a * 255.0)) != int(round(out.get_pixel(x, y).a * 255.0)):
						alpha_ok = false
		var off_a := 0
		for y in out.get_height():
			for x in out.get_width():
				var c2 := out.get_pixel(x, y)
				if c2.a > 0.0 and not cidx.has(_k_s(Color(c2.r, c2.g, c2.b, 1.0))):
					off_a += 1
		var wrote := -1
		if save and off_a == 0 and alpha_ok:
			wrote = out.save_png(String(ASSETS[a]))
		res[a] = {"off_before": off_b, "off_after": off_a, "alpha_ok": alpha_ok, "saved": wrote}
	return res

# ---------------------------------------------------------------- CLI
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--rebake"):
		var r := rebake_all(true)
		var ok := true
		for a in r:
			print("REBAKE ", a, " ", r[a])
			var e: Dictionary = r[a]
			if int(e.get("off_after", -1)) != 0 or not bool(e.get("alpha_ok", false)) \
					or int(e.get("saved", -1)) != OK:
				ok = false
		print("CHECK rebake_all=", ok)
		quit(0 if ok else 2)
		return
	# режим листа на вердикт (c22): c22_recolor.gd -- out.png
	_sheet_mode(String(args[0]) if args.size() > 0 and not args.has("--rebake") else "res://_c22_sheet.png")

# ----- лист на вердикт (режим c22; тот же код, что дал утверждённый лист) ----
var idx := {}
var canon_list := []
var map := {}
var legacy_colors := {}

func _sheet_mode(out_path: String) -> void:
	idx = PixelPalette.color_index()
	for rn in PixelPalette.RAMPS:
		var ramp: Array = PixelPalette.RAMPS[rn]
		for t in ramp.size():
			var c: Color = ramp[t]
			canon_list.append({"col": c, "lum": _lum(c), "ramp": rn, "tone": t})
	for fn in PixelPalette.FLATS:
		var c2: Color = PixelPalette.FLATS[fn]
		canon_list.append({"col": c2, "lum": _lum(c2), "ramp": fn, "tone": -1})
	var atlases := ASSETS.keys()
	atlases.sort()
	var total_off := {}
	for a in atlases:
		var img := Image.new()
		if img.load(String(ASSETS[a])) != OK:
			print("FAIL load ", a); quit(1); return
		var cs := {}
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a == 0.0:
					continue
				var k := _k(c)
				cs[k] = cs.get(k, 0) + 1
				if not idx.has(k):
					total_off[k] = true
		legacy_colors[a] = cs
	var off_mapped := 0
	for a in atlases:
		var keys: Array = legacy_colors[a].keys()
		keys.sort()
		for k in keys:
			var c := _col(int(k))
			var tgt: Color
			var label := ""
			if idx.has(int(k)):
				tgt = c
				label = "on-palette"
			else:
				var b := _bucket_for(String(a), int(k))
				if b.is_empty():
					tgt = _nearest(c)
					label = "fallback"
				else:
					tgt = _bucket_target(b, c)
					label = String(b["name"]) + ":" + _ramp_used(b, c)
				off_mapped += 1
			map["%s|%d" % [a, k]] = {"t": tgt.to_argb32(), "b": label}
	print("METRIC off_union=", total_off.size(), " off_colors_mapped=", off_mapped)
	var recol := {}
	var alpha_ok := true
	var pure_ok := true
	for a in atlases:
		var src := Image.new()
		src.load(String(ASSETS[a]))
		var dst := recolor_atlas(String(a), src)
		recol[a] = dst
	for a in atlases:
		var src2 := Image.new()
		src2.load(String(ASSETS[a]))
		var dst2: Image = recol[a]
		for y in src2.get_height():
			for x in src2.get_width():
				var cs2 := src2.get_pixel(x, y)
				var cd: Color = dst2.get_pixel(x, y)
				if int(round(cs2.a * 255.0)) != int(round(cd.a * 255.0)):
					alpha_ok = false
				if cs2.a > 0.0 and not idx.has(_k(Color(cd.r, cd.g, cd.b, 1.0))):
					pure_ok = false
	print("CHECK alpha_bytes_preserved=", alpha_ok)
	print("CHECK palette_pure_recolor=", pure_ok)
	if not (alpha_ok and pure_ok):
		print("ABORT"); quit(2); return
	_sheet(atlases, recol, out_path)
	print("OK sheet=", out_path)
	quit(0)

func _k(c: Color) -> int:
	return _k_s(c)

func _col(k: int) -> Color:
	return _col_s(k)

func _lum(c: Color) -> float:
	return _lum_s(c)

func _bucket_for(atlas: String, k: int) -> Dictionary:
	return _bucket_for_s(atlas, k)

func _ramp_used(b: Dictionary, c: Color) -> String:
	return _ramp_used_s(b, c)

func _bucket_target(b: Dictionary, c: Color) -> Color:
	return _bucket_target_s(b, c)

func _nearest(c: Color) -> Color:
	return _nearest_s(c)

func _sheet(atlases: Array, recol: Dictionary, out_path: String) -> void:
	var bg: Color = PixelPalette.SHEET["BG"]
	var line: Color = PixelPalette.SHEET["LINE"]
	var txtc: Color = PixelPalette.SHEET["TEXT"]
	var total_h := 20
	var secs := {}
	for a in atlases:
		var im: Image = recol[a]
		var hh := im.get_height()
		var fw := 32 if String(a) == "brute" else 16
		secs[a] = total_h
		total_h += 20 + hh + 6 + fw * 3 + 12
	var sheet := Image.create(SHEET_W, total_h, false, Image.FORMAT_RGBA8)
	sheet.fill(bg)
	for a in atlases:
		var src := Image.new()
		src.load(String(ASSETS[a]))
		var dst: Image = recol[a]
		var hh := dst.get_height()
		var y0 := int(secs[a])
		var ytxt := y0 + 20
		_text(sheet, 8, y0, String(a), 2, txtc)
		_text(sheet, 8, y0 + 12, "LEGACY", 1, line)
		_text(sheet, 118, y0 + 12, "RECOLOR X1", 1, line)
		for y in src.get_height():
			for x in src.get_width():
				var c := src.get_pixel(x, y)
				if c.a > 0.0:
					sheet.set_pixel(8 + x, ytxt + y, Color(c.r, c.g, c.b, c.a))
		for y in dst.get_height():
			for x in dst.get_width():
				var c: Color = dst.get_pixel(x, y)
				if c.a > 0.0:
					sheet.set_pixel(118 + x, ytxt + y, Color(c.r, c.g, c.b, c.a))
		var fw := 32 if String(a) == "brute" else 16
		var frames := int(floor(float(dst.get_width()) / float(fw)))
		var mcount := mini(frames, 4)
		_text(sheet, 360, y0 + 12, "MASTER X3 - KEY FRAMES", 1, line)
		var mx := 360
		var my := ytxt + hh + 6
		for fi in mcount:
			var m3 := Image.create(fw * 3, fw * 3, false, Image.FORMAT_RGBA8)
			for y in fw * 3:
				for x in fw * 3:
					var c2: Color = dst.get_pixel(fi * fw + int(x / 3), int(y / 3))
					m3.set_pixel(x, y, c2)
			for y in m3.get_height():
				for x in m3.get_width():
					var c3: Color = m3.get_pixel(x, y)
					if c3.a > 0.0:
						sheet.set_pixel(mx + x, my + y, Color(c3.r, c3.g, c3.b, c3.a))
			for y in fw * 3 + 2:
				_px(sheet, mx - 3, my - 1 + y, line)
				_px(sheet, mx + fw * 3 + 2, my - 1 + y, line)
			_text(sheet, mx + 1, my - 8, "F%d" % fi, 1, txtc)
			mx += fw * 3 + 14
		for x in SHEET_W:
			_px(sheet, x, y0 - 5, line)
	var err := sheet.save_png(out_path)
	print("SHEET_SAVE=", err, " size=", sheet.get_width(), "x", sheet.get_height())

# ------------------------------------------------------------------ шрифт (копия FONT из sheet_ashen_v1.gd)
const FONT := {
	"A": ["111", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["111", "100", "100", "100", "111"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "111", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["111", "100", "101", "101", "111"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "111"],
	"K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "101", "101", "101"], "N": ["110", "101", "101", "101", "101"],
	"O": ["111", "101", "101", "101", "111"], "P": ["111", "101", "111", "100", "100"],
	"Q": ["111", "101", "101", "111", "011"], "R": ["111", "101", "110", "101", "101"],
	"S": ["111", "000", "111", "001", "111"], "T": ["111", "010", "010", "010", "010"],
	"U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
	"W": ["101", "101", "101", "111", "101"], "X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "111", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "001", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "001"],
	" ": ["000", "000", "000", "000", "000"], "-": ["000", "000", "111", "000", "000"],
	"+": ["000", "010", "111", "010", "000"], "=": ["000", "111", "000", "111", "000"],
	".": ["000", "000", "000", "000", "010"], "~": ["000", "011", "110", "000", "000"],
	"/": ["001", "001", "010", "100", "100"], ":": ["000", "010", "000", "010", "000"],
}

func _text(img: Image, x0: int, y0: int, txt: String, sc: int, col: Color) -> int:
	var x := x0
	for ch in txt.to_upper():
		var g = FONT.get(ch)
		if g != null:
			for r in 5:
				for c in 3:
					if String(g[r])[c] == "1":
						for dy in sc:
							for dx in sc:
								_px(img, x + c * sc + dx, y0 + r * sc + dy, col)
		x += 4 * sc
	return x - x0 - sc

func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)
