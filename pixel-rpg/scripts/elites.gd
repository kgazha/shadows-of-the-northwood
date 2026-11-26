class_name Elites
extends RefCounted
## I1 «Элиты» (t34, 26.11, волна «Интерес v1»; вердикт 26.11: «12% мобов должны
## заставлять игрока остановиться и подумать „тяну я это или нет“»).
## Ставка в каждой встрече БЕЗ нового контента: ~12% мировых мобов роллят элиту
## детерминированным shash-каноном мира (тот же FNV-1a32, что аффиксы t17 и
## seam-пины): "elite:<seed>:<зона>:<x>,<y>:<ordinal>". Ролл не хранится в
## сейве и не может разъехаться: моб пересобирается из мета-таблицы генератора
## тем же ordinal-ом на той же клетке -> та же монета (детерминизм пилен в
## qa_lp T47). Мирные/квестовые (деревня — глава Драна) и мини-боссы сюда не
## допущены СО СТРУКТУРЫ: apply() вызывают только biome_zone и ashen_zone.
## Статы: hp x2, урон x1.5 (у кого множитель — там), СКОРОСТЬ та же (иначе
## «тяну/не тяну» превращается в «догнали»). Награда — в loot.gd (серебро x3,
## доп. гарантированный предмет, pity-кредит GameState.elite_pity под I4).
## Аура и подпись — только если тумблер GameState.bold_fx включён (закон t23):
## выключенный тумблер глушит украшение, но НЕ статы и НЕ награду.

const BFX := preload("res://scripts/bold_fx.gd")   # примитивы кадров + enabled()
const OW := preload("res://scripts/open_world.gd") # shash — FNV-1a32 канон мира

const RATE_PCT := 12               # 12% мировой популяции (BALANCE строка I1)
const HP_MULT := 2.0
const DMG_MULT := 1.5
const GOLD_MULT := 3.0             # серебро x3 — применяется в loot.gd
const PREFIX := "Элитный "         # все имена мобов муж. рода — склонять нечего

## Имена для подписи: семейства (реестр AchvCatalog.MOBS тот же); виды-обличья
## t26 читаются из kill_kind -> AchvCatalog.MOBS (Снежный шептун и пр.).
const FAM_NAME := {
	"slime": "Слайм", "swarmling": "Мглокрыс", "archer": "Лесокров-лучник",
	"brute": "Тлель-вепрь", "wraith": "Тенеплёт",
}
## Ключ ролла по имени скрипта (spawner-agnostic — ординал даёт хозяин-спавнер).
const FAM_BY_SCRIPT := {
	"slime": "slime", "brute": "brute", "mob_swarmling": "swarmling",
	"mob_archer": "archer", "mob_wraith": "wraith",
}

## Канон ролла: младшая пара децимал shash — тот же приём, что корзина аффиксов.
static func roll(run_seed: int, salt: String, tile: Vector2i, ordinal: int) -> bool:
	var cell := "%s:%d,%d:%d" % [salt, tile.x, tile.y, ordinal]
	return OW.shash("elite:%d:%s" % [run_seed, cell]) % 100 < RATE_PCT

## Точка вставки ПОСЛЕ всех поясных/круговых множителе спавнера (паттерн
## _apply_ng_stats): элита масштабирует итог. Возвращает true, если моб стал
## элитным (флаг meta "elite" — источник истины для loot.gd и подписи).
static func apply(mob: Node, salt: String, tile: Vector2i, ordinal: int) -> bool:
	if mob == null or not is_instance_valid(mob):
		return false
	var base := String(mob.get_script().resource_path.get_file().get_basename())
	var fam := String(FAM_BY_SCRIPT.get(base, ""))
	if fam == "":
		return false  # не моб (страж/босс-обёртка/нечто чужое) — мимо
	if not roll(int(GameState.run_seed), salt, tile, ordinal):
		return false
	mob.set_meta("elite", true)
	if "hp" in mob:
		mob.hp = maxi(1, int(round(int(mob.hp) * HP_MULT)))
	if "max_hp" in mob:
		mob.max_hp = maxi(1, int(round(int(mob.max_hp) * HP_MULT)))
	# урон — по channel'у семейства, ровно один множитель на моба:
	# slime/brute бьют var dmg; стая/лучник/тенеплёт — через dmg_mult (стрелы
	# mob_archer.gd:251 и контакт/вселение mob_wraith.gd считают 2.0*dmg_mult).
	match fam:
		"slime", "brute":
			if "dmg" in mob:
				mob.dmg = maxi(1, int(round(int(mob.dmg) * DMG_MULT)))
		"swarmling", "archer", "wraith":
			if "dmg_mult" in mob:
				mob.dmg_mult = float(mob.dmg_mult) * DMG_MULT
	# скорость НЕ трогаем — вердикт (t34): тягость элиты в туче hp и ударе.
	_decorate(mob, fam)
	return true

## Украшение: золотое пульсирующее кольцо (смелое — тумблер bold_fx) и кодо-
## подпись над головой. Оба — дети моба: живут и умирают вместе с ним, в
## save/load не лезут (пересборка перерисует по флагу meta на apply).
static func _decorate(mob: Node, fam: String) -> void:
	if not BFX.enabled():
		return
	var spr := AnimatedSprite2D.new()
	spr.name = "EliteAura"
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("aura")
	# три кадра пульса: тонок/жирно/тонок — рампа HUD_GOLD (канон палитры).
	var radii := [7.0, 8.0, 7.0]
	var tones := [2, 0, 1]
	for f in 3:
		var im := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		BFX._ring(im, 10.0, 10.0, radii[f], BFX._c("HUD_GOLD", tones[f]), 1)
		frames.add_frame("aura", ImageTexture.create_from_image(im))
	frames.set_animation_speed("aura", 3.0)
	frames.set_animation_loop("aura", true)
	spr.sprite_frames = frames
	spr.z_index = -1          # под спрайтом моба: ободок у ног, не visor-линза
	spr.offset = Vector2(0, 2)
	mob.add_child(spr)
	# подпись: kill_kind (вид t26) -> имя вида, иначе имя семейства.
	var lbl := Label.new()
	lbl.name = "ElitePlate"
	var nm := String(FAM_NAME.get(fam, fam))
	var kk := String(mob.get("kill_kind")) if "kill_kind" in mob else ""
	if kk != "" and AchvCatalog.MOBS.has(kk):
		nm = String(AchvCatalog.MOBS[kk])
	lbl.text = PREFIX + nm
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_color", BFX._c("HUD_GOLD", 0))
	var fnt := UIFont.get_font()
	if fnt != null:
		lbl.add_theme_font_override("font", fnt)
	lbl.position = Vector2(-34, -34)
	lbl.z_index = 40
	mob.add_child(lbl)
