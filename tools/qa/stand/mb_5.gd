extends "res://mb_base.gd"
## Кейс 3d: сейв с убитым боссом — при заходе в пещеру новых тенеплётов быть не должно.

func _ready() -> void:
	await boot(save_for(3))  # cave_state=3: босс мёртв, ключ отдан
	check("B: сейв загружен, boss_defeated=true", GameState.boss_defeated == true)
	var wraiths: Array = find_mob(world.dungeon_zone, "mob_wraith")
	check("B: на boss_defeated-сейве тенеплёты НЕ построены (f=%d)" % wraiths.size(), wraiths.size() == 0)
	var boss_ok: bool = world.dungeon_zone.boss_node == null or not is_instance_valid(world.dungeon_zone.boss_node)
	check("B: на boss_defeated-сейве босс НЕ построен", boss_ok)
	world.apply_zone(true, false)
	await pump(30)
	var w2: Array = find_mob(world.dungeon_zone, "mob_wraith")
	check("B: при заходе в пещеру тенеплёты по-прежнему отсутствуют", w2.size() == 0)
	done()
