extends RefCounted
## Fixed review cameras and real quest/activity states for the reported sign defects.
static var _baseline: Dictionary = {}

static func capture_views() -> Dictionary:
	var views: Dictionary = {
		"sign_poster_front": {"signage_fixture":"posted", "camera_at":Vector3(-10.3,1.7,-8.2), "camera_focus":Vector3(-8.75,1.2,-6.15), "fov":43.0},
		"sign_poster_back": {"signage_fixture":"posted", "camera_at":Vector3(-4.4,2.4,-3.8), "camera_focus":Vector3(-8.5,1.4,-5.7), "fov":48.0},
		"sign_poster_edge": {"signage_fixture":"posted", "camera_at":Vector3(-10.5,1.6,-6.6), "camera_focus":Vector3(-8.75,1.18,-6.14), "fov":39.0},
		"signs_daily": {"signage_fixture":"daily", "camera_at":Vector3(-6,3.4,-6), "camera_focus":Vector3(3,1.3,7), "fov":55.0},
		"signs_preparing": {"signage_fixture":"preparing", "day":16, "camera_at":Vector3(-6.2,1.6,-5.8), "camera_focus":Vector3(-4.4,.75,-3.8), "fov":43.0},
		"signs_festival_front": {"signage_fixture":"festival", "day":17, "time":19.0, "camera_at":Vector3(-6.2,1.6,-5.8), "camera_focus":Vector3(-4.4,.75,-3.8), "fov":43.0},
		"signs_festival_rear": {"signage_fixture":"festival", "day":17, "time":19.0, "camera_at":Vector3(4.2,1.5,11.9), "camera_focus":Vector3(3.1,.7,9.8), "fov":41.0},
		"signs_reunion": {"signage_fixture":"reunion", "day":20, "time":18.5, "camera_at":Vector3(1.5,1.5,7.5), "camera_focus":Vector3(3.1,.7,9.8), "fov":41.0},
		"signs_after": {"signage_fixture":"after", "day":18, "camera_at":Vector3(-6,3.4,-6), "camera_focus":Vector3(3,1.3,7), "fov":55.0},
	}
	for key: String in views:
		var view: Dictionary = views[key]
		view["day"] = view.get("day", 2)
		view["time"] = view.get("time", 10.5)
		view["phase"] = "prep"
		view["weather"] = "sunny"
		view["settle_seconds"] = .7
		view["player"] = Vector3(-1,.1,-3)
	return views

static func prepare(main: Node, key: String) -> bool:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
		push_error("Signage review requires an isolated HARUMACHI_SAVE_DIR")
		return false
	if _baseline.is_empty(): _baseline = GameState.to_dict().duplicate(true)
	var day: int = GameState.day
	var minute: float = GameState.minute
	GameState.from_dict(_baseline.duplicate(true))
	GameState.day = day
	GameState.minute = minute
	GameState.phase = "prep"
	GameState.clock_paused = true
	GameState.flags.summer_workshop = {}
	GameState.flags.summer_gathering = {}
	for id: String in ["Q01", "Q04", "Q05", "Q11", "Q13"]:
		GameState.quests[id] = {"state":"locked", "step":0}
	if key == "posted": GameState.quests.Q04 = {"state":"done", "step":3}
	if key == "preparing": GameState.quests.Q13 = {"state":"active", "step":0}
	if key in ["festival", "after", "reunion"]:
		for id: String in ["Q01", "Q04", "Q05", "Q11", "Q13"]:
			GameState.quests[id] = {"state":"done", "step":GameState.quests_db[id].steps.size()}
	if key == "reunion": SummerGathering.state().reunion_day = GameState.day
	main.world.sync_festivals()
	(main.world.interiors.workroom.get_node("WorkroomProject") as WorkroomView).sync_state()
	return true
