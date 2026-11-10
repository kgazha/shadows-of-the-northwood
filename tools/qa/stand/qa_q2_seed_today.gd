extends Node
## Пиёт крафтовый v2-сейв с СЕГОДНЯШНИМ daily.stamp (streak=5) + режим «today».
const SAVE := "user://save_morkheim.json"

func _ready() -> void:
	var f := FileAccess.open("user://qa_q2_mode.txt", FileAccess.WRITE)
	f.store_string("today")
	f.close()
	var d := {
		"v": 2, "class_id": "warrior", "level": 3, "xp": 10, "xp_next": 40,
		"hp": 20, "mana": 10, "herbs": 7, "slime_kills": 0,
		"elder_quest": 0, "slime_quest": 0, "seen_intro": true,
		"cave_state": 0, "has_key": false, "has_amulet": false, "door_opened": false,
		"in_cave": false, "seen_cave_intro": false, "seen_boss_intro": false,
		"boss_defeated": false, "materials": {"suhotsvet": 0, "zhim": 0}, "brewed": 0,
		"campfires_used": {}, "chests_used": [],
		"gold": 100, "gear": {"weapon": "sword", "armor": ""},
		"flags": {"daily.stamp": Time.get_unix_time_from_system() - 60.0, "daily.streak": 5},
		"px": 300.0, "py": 220.0, "pos_valid": true,
	}
	var sf := FileAccess.open(SAVE, FileAccess.WRITE)
	sf.store_string(JSON.stringify(d))
	sf.close()
	print("SEED | today stamp written")
	get_tree().quit(0)
