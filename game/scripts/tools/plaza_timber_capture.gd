extends RefCounted
## The same daylight and exposure for the original feedback and adjacent timber.
static var _placements: Array = []
static var _remembered: bool = false

static func capture_views() -> Dictionary:
	var views: Dictionary = {
		"plaza_timber_day": {"camera_at": Vector3(-6, 2.6, 2), "camera_focus": Vector3(.3, .9, 8.5), "fov": 48.0},
		"plaza_timber_close": {"camera_at": Vector3(-5.4, 1.8, 3.7), "camera_focus": Vector3(-.4, .65, 6.5), "fov": 48.0},
		"plaza_timber_pergola": {"camera_at": Vector3(-4.7, 2.5, 9.6), "camera_focus": Vector3(-9.8, 1.2, 13.2), "fov": 48.0},
		"plaza_timber_stage": {"camera_at": Vector3(-3.5, 2.8, 16.2), "camera_focus": Vector3(-9.8, .9, 20.4), "fov": 48.0, "day": 17, "time": 16.25, "lifecycle_fixture": "resident_fallback"},
		"plaza_timber_rain": {"camera_at": Vector3(-6, 2.6, 2), "camera_focus": Vector3(.3, .9, 8.5), "fov": 48.0, "weather": "rain"},
		"plaza_timber_evening": {"camera_at": Vector3(-6, 2.6, 2), "camera_focus": Vector3(.3, .9, 8.5), "fov": 48.0, "time": 18.5},
	}
	for key: String in views:
		var view: Dictionary = views[key]
		view["day"] = view.get("day", 2)
		view["time"] = view.get("time", 10.5)
		view["phase"] = "prep"
		view["weather"] = view.get("weather", "sunny")
		view["settle_seconds"] = .7
		view["player"] = Vector3(-1, .1, 3)
		view["timber_fixture"] = true
	return views

static func prepare(main: Node) -> bool:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
		push_error("Timber comparison requires an isolated HARUMACHI_SAVE_DIR")
		return false
	if not _remembered:
		_placements = GameState.placements.duplicate(true)
		_remembered = true
	GameState.placements = _placements.duplicate(true)
	GameState.placements.append({"uid": -424, "item": "picnic_table", "x": -2.0, "z": 5.5, "rot": 1})
	GameState.placements_changed.emit()
	main.world.sync_festivals()
	return true
