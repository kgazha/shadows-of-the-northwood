extends Node
## Эмуляция контракта фичи ClickMove (af8f49d): is_on()/set_on() + персист
## user://clickmove_cfg.json. Только для QA-харнесса s2, в диффы не входит.

var _on := false

func _ready() -> void:
	_load()

func is_on() -> bool:
	return _on

func set_on(v: bool) -> void:
	_on = v
	_save()

func _save() -> void:
	var f := FileAccess.open("user://clickmove_cfg.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"on": _on}))

func _load() -> void:
	if FileAccess.file_exists("user://clickmove_cfg.json"):
		var f := FileAccess.open("user://clickmove_cfg.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_on = bool(d.get("on", false))
