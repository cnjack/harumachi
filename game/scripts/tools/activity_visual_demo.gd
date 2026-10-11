extends "res://scripts/tools/daily_life_demo.gd"
## Scene-specific framing on the shared optional capture pipeline. All native
## targeting, keyboard/mouse checks and watchdogs are inherited unchanged.

func _daily_qa_focus(label: String) -> Vector3:
	return _qa_focus(label)

func _qa_focus(_label: String) -> Vector3:
	return Vector3.INF
