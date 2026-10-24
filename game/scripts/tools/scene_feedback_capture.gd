extends RefCounted
## Fixed cameras for the October 24 player-reported scene defects.

static func capture_views() -> Dictionary:
	var views: Dictionary = {
		"feedback_stop_front": {"player": Vector3(-41,.1,-8), "camera_at": Vector3(-42.65,2.25,-7.6), "camera_focus": Vector3(-42.65,2.18,-5.64), "fov": 43.0},
		"feedback_stop_bracket": {"player": Vector3(-41,.1,-8), "camera_at": Vector3(-44.2,2.15,-5.2), "camera_focus": Vector3(-43.55,2.26,-5.55), "fov": 43.0},
		"feedback_tree_roots": {"player": Vector3(-18,.1,-13), "camera_at": Vector3(-16.4,.7,-14.5), "camera_focus": Vector3(-18,.17,-16.2), "fov": 42.0},
		"truck_town_side": {"player": Vector3(34,.1,-10), "camera_at": Vector3(33.8,2,-6.8), "camera_focus": Vector3(33.8,.95,-12.85), "fov": 40.0},
		"truck_town_cab_close": {"player": Vector3(34,.1,-10), "camera_at": Vector3(36.4,1.8,-10.25), "camera_focus": Vector3(34.85,1.22,-12.85), "fov": 40.0},
		"truck_town_tailgate_close": {"player": Vector3(34,.1,-10), "camera_at": Vector3(30.3,1.5,-10.45), "camera_focus": Vector3(32.3,.91,-12.85), "fov": 40.0},
		"bus_cabin_side": {"player": Vector3(-42,0.1,-8.5), "time": 10.5, "camera_at": Vector3(-44.2,1.8,-6.5), "camera_focus": Vector3(-44.5,1.25,-11.3), "bus_doors": 0.0},
		"bus_cabin_door_open": {"player": Vector3(-42,0.1,-8.5), "time": 10.5, "camera_at": Vector3(-42.0,1.75,-7.8), "camera_focus": Vector3(-43.9,1.15,-10.8), "bus_doors": 1.0},
		"bus_route_close": {"player": Vector3(-42,0.1,-8.5), "time": 10.5, "camera_at": Vector3(-40.6,2.6,-9.6), "camera_focus": Vector3(-42.75,1.91,-11.3), "bus_doors": 0.0},
		"bus_cabin_rear": {"player": Vector3(-42,0.1,-8.5), "time": 10.5, "camera_at": Vector3(-49.7,2.0,-8.6), "camera_focus": Vector3(-46.2,1.25,-11.3), "bus_doors": 0.0},
		"feedback_freezer_top": {"interior": "store", "at": Vector3(2.8,.05,2.4), "inside_camera": Vector3(2.75,2.75,2.6), "inside_focus": Vector3(4.537,.66,1.267), "fov": 40.0},
		"feedback_freezer_side": {"interior": "store", "at": Vector3(2.8,.05,2.4), "inside_camera": Vector3(2.2,1.35,.25), "inside_focus": Vector3(4.537,.65,1.267), "fov": 43.0},
		"feedback_store_exterior": {"player": Vector3(-36,.1,-13), "camera_at": Vector3(-39,2.4,-11.5), "camera_focus": Vector3(-36,1.3,-16.3), "actors": true},
		"feedback_board_back": {"player": Vector3(-5,.1,-4), "camera_at": Vector3(-4.4,2.4,-3.8), "camera_focus": Vector3(-8.5,1.4,-5.7), "fov": 48.0},
		"feedback_plaza_signs": {"player": Vector3(-1,.1,-3), "camera_at": Vector3(-6,3.4,-6), "camera_focus": Vector3(3,1.3,7), "fov": 55.0},
		"feedback_plaza_wood": {"player": Vector3(-1,.1,3), "camera_at": Vector3(-6,2.6,2), "camera_focus": Vector3(.3,.9,8.5), "fov": 48.0},
		"feedback_farm_approach": {"player": Vector3(34,.1,-10), "camera_at": Vector3(29,2.8,-10.5), "camera_focus": Vector3(45,1.8,-11), "fov": 48.0},
		"feedback_street_tree": {"player": Vector3(-18,.1,-11), "camera_at": Vector3(-16.0,2.2,-10.1), "camera_focus": Vector3(-18,1.6,-16.2), "fov": 43.0},
		"feedback_stall": {"player": Vector3(4,.1,12), "camera_at": Vector3(6.4,2.3,11.2), "camera_focus": Vector3(2,1.1,15.5), "fov": 48.0},
		"feedback_slide": {"player": Vector3(-6,.1,4), "camera_at": Vector3(-5.6,2.4,3.4), "camera_focus": Vector3(-10.4,1.2,7), "fov": 45.0},
		"feedback_festival_daily": {"player": Vector3(-5,.1,17), "camera_at": Vector3(-3.5,3.2,15.4), "camera_focus": Vector3(-9.6,.7,20), "fov": 50.0},
		"feedback_festival_night": {"player": Vector3(-5,.1,17), "camera_at": Vector3(-3.5,3.2,15.4), "camera_focus": Vector3(-9.6,.7,20), "fov": 50.0, "time": 20.0},
	}
	var festival_moments: Dictionary = {"daily": [2, 10.5, "daily"], "night": [2, 20.0, "daily"], "construction": [16, 10.5, "preparing"], "ready": [17, 16.25, "resident_fallback"], "open": [17, 19.5, "opening"], "cleanup": [17, 22.1, "cleanup"], "closed": [17, 22.7, "cleanup"], "next_day": [18, 10.5, "after"], "borrowed": [2, 10.5, "practice"]}
	for moment: String in festival_moments:
		var spec: Array = festival_moments[moment]
		views["feedback_festival_" + moment] = {"player": Vector3(-5,.1,17), "camera_at": Vector3(-3.5,3.2,15.4), "camera_focus": Vector3(-9.6,.7,20), "fov": 50.0, "day": spec[0], "time": spec[1], "lifecycle_fixture": spec[2]}
	var stall_moments: Dictionary = {"daily": [2, 10.5, "daily"], "delivered": [3, 11.0, "bread_delivered"], "stored": [4, 11.0, "bread_stored"], "open": [17, 19.5, "opening"]}
	for moment: String in stall_moments:
		var stall_spec: Array = stall_moments[moment]
		views["feedback_stall_" + moment] = {"player": Vector3(4,.1,12), "camera_at": Vector3(6.4,2.3,11.2), "camera_focus": Vector3(2,1.1,15.5), "fov": 48.0, "day": stall_spec[0], "time": stall_spec[1], "lifecycle_fixture": stall_spec[2]}
	for key: String in views:
		var view: Dictionary = views[key]
		view["day"] = view.get("day", 2)
		view["phase"] = view.get("phase", "prep")
		view["time"] = view.get("time", 10.5)
		view["weather"] = "sunny"
		view["settle_seconds"] = .7
	return views
