extends RefCounted
## Same entrance, direct bank view and high/photo views expose any replacement wall.

static func capture_views() -> Dictionary:
	var views: Dictionary = {
		"farm_approach_gate_eye": {"player": Vector3(42, .1, -11), "camera_at": Vector3(42.1, 1.65, -11), "camera_focus": Vector3(71, -1.8, -10.7), "fov": 58.0},
		"farm_approach_bank_close": {"player": Vector3(42, .1, -11), "camera_at": Vector3(50, .8, -16), "camera_focus": Vector3(59, -1.6, -14), "fov": 54.0},
		"farm_approach_photo_high": {"player": Vector3(42, .1, -11), "camera_at": Vector3(50, 18, -26), "camera_focus": Vector3(77, -2, -11), "fov": 65.0},
		"farm_approach_meadow_join": {"player": Vector3(42, .1, -11), "camera_at": Vector3(103, 6, -20), "camera_focus": Vector3(130, -.03, -7.2), "fov": 52.0},
	}
	for key: String in views:
		var view: Dictionary = views[key]
		view["day"] = 2
		view["phase"] = "prep"
		view["time"] = 10.5
		view["weather"] = "sunny"
		view["settle_seconds"] = .7
	return views
