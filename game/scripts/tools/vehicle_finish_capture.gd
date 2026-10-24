extends RefCounted
## Fixed native cameras keep small hardware and glass readable in comparison.

static func capture_views() -> Dictionary:
	var views: Dictionary = {
		"finish_bus_lamps": {"camera_at": Vector3(-40.4, 1.05, -9.6), "camera_focus": Vector3(-42.4, .76, -10.8), "fov": 34.0},
		"finish_bus_wheel": {"camera_at": Vector3(-42.2, .9, -8.8), "camera_focus": Vector3(-43.5, .45, -10.5), "fov": 33.0},
		"finish_bus_night": {"camera_at": Vector3(-39.5, 2.6, -7.6), "camera_focus": Vector3(-44.1, 1.2, -11.3), "fov": 43.0, "time": 20.0},
		"finish_bus_rain": {"camera_at": Vector3(-39.5, 2.6, -7.6), "camera_focus": Vector3(-44.1, 1.2, -11.3), "fov": 43.0, "weather": "rain"},
		"finish_truck_wheel": {"camera_at": Vector3(35.9, .82, -10.4), "camera_focus": Vector3(34.8, .36, -12.05), "fov": 33.0},
		"finish_truck_bed": {"camera_at": Vector3(31.7, 3.5, -10.5), "camera_focus": Vector3(33, .85, -12.8), "fov": 40.0},
		"finish_truck_night": {"camera_at": Vector3(38, 2.1, -9.3), "camera_focus": Vector3(33.8, 1, -12.85), "fov": 43.0, "time": 20.0},
		"finish_truck_rain": {"camera_at": Vector3(38, 2.1, -9.3), "camera_focus": Vector3(33.8, 1, -12.85), "fov": 43.0, "weather": "rain"},
	}
	for key: String in views:
		var view: Dictionary = views[key]
		view["player"] = Vector3(-42, .1, -8.5) if key.contains("bus") else Vector3(34, .1, -10)
		view["day"] = 2
		view["phase"] = "prep"
		view["time"] = view.get("time", 10.5)
		view["weather"] = view.get("weather", "sunny")
		view["bus_doors"] = 0.0
		view["settle_seconds"] = .7
	return views
