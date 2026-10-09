class_name HomageDisplay
extends Sprite3D
var entry: Dictionary

func _ready() -> void:
	GameState.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var key: String = str(entry.image)
	if not entry.requires.is_empty() and not Homage.found(str(entry.id)):
		key += "_empty"
	var path := "res://assets/ui/homage/%s.png" % key
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
