extends SceneTree
## c27 (волна w1 добивки стиля, план c26): портреты 1+2 на PixelPalette.
## Единственный источник перекраски — эта карта (образец c22/c23): legacy ARGB ->
## палитра, чистый nearest по LAB(D65), прозрачные пиксели копируются байт-в-байт
## (альфа-маска кадра не меняется, кадров не добавляется). 137 цветов легаси ->
## 104 тона палитры; max dE=41.2 на фиолетовых 65 px (в палитре нет фиолета —
## факт в REPORT, кандидат фиолетовой рампы — отдельный вердикт).
## Запуск (bake): godot --headless --path pixel-rpg -s res://tools_art/c27_portraits.gd
## Само-повтор (idempotent): уже палитровые пиксели карта не трогает.

const PAL := preload("res://scripts/pixel_palette.gd")

const FILES := {
	"portraits": "res://assets/portraits.png",
	"portraits2": "res://assets/portraits2.png",
}

const MAP := {	0xff0f1510: 0xff191514,
	0xff151d14: 0xff191514,
	0xff161f17: 0xff191514,
	0xff18221a: 0xff292422,
	0xff192031: 0xff2b2f40,
	0xff1a241a: 0xff292422,
	0xff1c181c: 0xff191514,
	0xff1c261a: 0xff292422,
	0xff201611: 0xff191514,
	0xff202a1e: 0xff2c2623,
	0xff221c22: 0xff191514,
	0xff222e20: 0xff22391f,
	0xff222e21: 0xff22391f,
	0xff231f32: 0xff2b2f40,
	0xff241e2a: 0xff2b2f40,
	0xff252d3f: 0xff2b2f40,
	0xff262528: 0xff292422,
	0xff29334f: 0xff2b2f40,
	0xff2a2120: 0xff292422,
	0xff2a3756: 0xff203c52,
	0xff2c2221: 0xff292422,
	0xff2c3929: 0xff22391f,
	0xff2c3c60: 0xff203c52,
	0xff2d272d: 0xff292422,
	0xff2e3928: 0xff22391f,
	0xff33302d: 0xff2c2623,
	0xff333845: 0xff3a3e46,
	0xff34241c: 0xff33251a,
	0xff344430: 0xff22391f,
	0xff372b42: 0xff2b2f40,
	0xff393251: 0xff2b2f40,
	0xff3b4866: 0xff454a5f,
	0xff3c2819: 0xff453220,
	0xff3c362f: 0xff403733,
	0xff3c372f: 0xff403733,
	0xff3d3b40: 0xff3a3e46,
	0xff413559: 0xff454a5f,
	0xff423e38: 0xff443d3a,
	0xff42444d: 0xff3a3e46,
	0xff433533: 0xff403733,
	0xff433748: 0xff2b2f40,
	0xff464241: 0xff443d3a,
	0xff474037: 0xff464236,
	0xff47543d: 0xff5f584a,
	0xff4a3529: 0xff453220,
	0xff4a5c40: 0xff385c34,
	0xff4c3a64: 0xff454a5f,
	0xff4f4533: 0xff464236,
	0xff50525a: 0xff494d55,
	0xff514032: 0xff4f3a27,
	0xff521a20: 0xff4e1b15,
	0xff524235: 0xff4f3a27,
	0xff525b70: 0xff5f657c,
	0xff534d48: 0xff554a45,
	0xff535e44: 0xff5f584a,
	0xff544c42: 0xff554a45,
	0xff59466a: 0xff454a5f,
	0xff5e5340: 0xff5f584a,
	0xff604028: 0xff57402a,
	0xff60574b: 0xff5f584a,
	0xff61584b: 0xff5f584a,
	0xff667854: 0xff527f4a,
	0xff6b645b: 0xff6d6757,
	0xff6b6d7c: 0xff70747c,
	0xff6c5974: 0xff5f657c,
	0xff6d6d73: 0xff70747c,
	0xff70644e: 0xff6d6757,
	0xff715441: 0xff6e5238,
	0xff726858: 0xff6d6757,
	0xff73654a: 0xff7d6a4b,
	0xff756952: 0xff6d6757,
	0xff77593f: 0xff6e5238,
	0xff7a3e3e: 0xff6b4232,
	0xff7b4642: 0xff6b4232,
	0xff7b4b44: 0xff6b4232,
	0xff7b5d48: 0xff6e5238,
	0xff7c584a: 0xff6e5238,
	0xff7e6d67: 0xff7a706c,
	0xff7e6f54: 0xff7d6a4b,
	0xff806e5d: 0xff6d6757,
	0xff807052: 0xff7d6a4b,
	0xff80818c: 0xff838892,
	0xff818491: 0xff838892,
	0xff846046: 0xff8a6a4a,
	0xff86986e: 0xff6f9f63,
	0xff877b67: 0xff918a77,
	0xff888a8d: 0xff838892,
	0xff8a6c68: 0xff7a706c,
	0xff8b7964: 0xff948b77,
	0xff907f6b: 0xff948b77,
	0xff9668bc: 0xff7c8299,
	0xff96715f: 0xff8a6a4a,
	0xff988667: 0xff948b77,
	0xff997d6e: 0xff948b77,
	0xff9d745d: 0xff8a6a4a,
	0xff9e9fa8: 0xffa3a8b2,
	0xffa0745a: 0xffb0765a,
	0xffa1816c: 0xff948b77,
	0xffa1876a: 0xffa8825a,
	0xffa57a61: 0xffb0765a,
	0xffa678d0: 0xff7c8299,
	0xffa89388: 0xff948b77,
	0xffa98a74: 0xff948b77,
	0xffac8065: 0xffa8825a,
	0xffad8369: 0xffa8825a,
	0xffae9070: 0xffa8825a,
	0xffb09e78: 0xffb9a06e,
	0xffb0b0ba: 0xffb3b6bd,
	0xffb18366: 0xffa8825a,
	0xffb1937b: 0xff948b77,
	0xffb39782: 0xffb0a894,
	0xffb5a27d: 0xffb9a06e,
	0xffb98a6b: 0xffa8825a,
	0xffb9b5b8: 0xffb3b6bd,
	0xffbca984: 0xffb9a06e,
	0xffbdb8b7: 0xffb3b6bd,
	0xffbe9c81: 0xffb0a894,
	0xffc0b4aa: 0xffc0b69f,
	0xffc69674: 0xffa8825a,
	0xffc9bfb3: 0xffc0b69f,
	0xffcd9e7c: 0xffb9a06e,
	0xffcea07d: 0xffb9a06e,
	0xffceb296: 0xffc0b69f,
	0xffced2de: 0xffb3b6bd,
	0xffd3b395: 0xffc0b69f,
	0xffd4a683: 0xffb9a06e,
	0xffd4b395: 0xffc0b69f,
	0xffd5a885: 0xffb9a06e,
	0xffd6b6f4: 0xffa3a8b2,
	0xffd8b494: 0xffc0b69f,
	0xffd8d4c4: 0xffe2d8c2,
	0xffd9b494: 0xffc0b69f,
	0xffdcdee4: 0xffb3b6bd,
	0xffdddbda: 0xffe2d8c2,
	0xffdedad6: 0xffe2d8c2,
	0xffdfd6c8: 0xffe2d8c2,
	0xfff0f2f5: 0xffe2d8c2,
}

static func _pal_keys() -> Dictionary:
	var k := {}
	for rn in PAL.RAMPS:
		for t in PAL.RAMPS[rn]:
			k[(t as Color).to_argb32()] = true
	for fk in PAL.FLATS:
		k[(PAL.FLATS[fk] as Color).to_argb32()] = true
	return k

## Единственная точка перекраски (используется и пином qa_lp _t27).
static func bake(id: String, img: Image) -> Dictionary:
	var changed := 0
	var unknown := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var k := c.to_argb32()
			if ((k >> 24) & 0xFF) != 255:
				continue  # прозрачные — байт-в-байт
			if MAP.has(k):
				var tgt: int = MAP[k]
				if tgt != k:
					img.set_pixel(x, y, Color(
						float((tgt >> 16) & 0xFF) / 255.0,
						float((tgt >> 8) & 0xFF) / 255.0,
						float(tgt & 0xFF) / 255.0, 1.0))
					changed += 1
			elif not _pal_keys().has(k):
				unknown += 1
	return {"changed": changed, "unknown": unknown}

func _init() -> void:
	var fails := 0
	for id in FILES:
		var img := Image.load_from_file(String(FILES[id]))
		if img == null:
			print("BAKE FAIL: ", FILES[id])
			fails += 1
			continue
		var before_off := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var k := c.to_argb32()
				if ((k >> 24) & 0xFF) == 255 and not _pal_keys().has(k):
					before_off += 1
		var alpha_before: PackedByteArray = img.get_data()
		var st := bake(String(id), img)
		var after_off := 0
		for y in img.get_height():
			for x in img.get_width():
				var k2 := img.get_pixel(x, y).to_argb32()
				if ((k2 >> 24) & 0xFF) == 255 and not _pal_keys().has(k2):
					after_off += 1
		var alpha_after: PackedByteArray = img.get_data()
		var alpha_ok := alpha_before.size() == alpha_after.size()
		if alpha_ok:
			for i in range(3, alpha_after.size(), 4):
				if alpha_before[i] != alpha_after[i]:
					alpha_ok = false
					break
		var err := img.save_png(String(FILES[id]))
		print("BAKE %s off %d -> %d changed=%d unknown=%d alpha_ok=%s save=%d" % [
			id, before_off, after_off, st.changed, st.unknown, alpha_ok, err])
		if after_off != 0 or st.unknown != 0 or not alpha_ok or err != OK:
			fails += 1
	if fails > 0:
		print("SELF-CHECK FAIL: %d" % fails)
		quit(1)
	print("SELF-CHECK PASS")
	quit(0)