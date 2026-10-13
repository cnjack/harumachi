extends RefCounted
## Shared native screenshot fixtures; every lifecycle uses the same camera transform.
static var _baseline: Dictionary = {}

static func capture_views() -> Dictionary:
	var catalog: Dictionary = {}
	var moments: Dictionary = {"daily": [2, 10.5], "early_build": [15, 10.5], "preparing": [16, 10.5], "deferred": [16, 10.5],
		"opening": [17, 19.5], "resident_fallback": [17, 16.25], "cleanup": [17, 22.1], "after": [18, 10.5]}
	for moment: String in moments:
		catalog["lifecycle_site_" + moment] = {"lifecycle_fixture": moment, "group": "prop_lifecycle", "day": moments[moment][0], "time": moments[moment][1], "phase": "prep",
			"player": Vector3(11, .1, 12), "camera_at": Vector3(-10.7, 5.8, 9.4), "camera_focus": Vector3(.5, 1.3, 19.0), "fov": 52.0}
	for moment: String in ["daily", "opening", "after"]:
		catalog["lifecycle_platform_" + moment] = {"lifecycle_fixture": moment, "group": "prop_lifecycle", "day": moments[moment][0], "time": moments[moment][1], "phase": "prep",
			"player": Vector3(-5.2, .1, 18.6), "camera_at": Vector3(-6.2, 2.4, 17.6), "camera_focus": Vector3(-9.5, .7, 20.4)}
	for moment: String in ["daily", "practice", "opening"]:
		catalog["lifecycle_drum_" + moment] = {"lifecycle_fixture": moment, "group": "prop_lifecycle", "day": 17 if moment == "opening" else 2, "time": 19.5 if moment == "opening" else 10.5, "phase": "prep",
			"player": Vector3(-5.2, .1, 18.6), "camera_at": Vector3(-6.5, 1.15, 19.05), "camera_focus": Vector3(-7.7, .72, 20.4)}
	for moment: String in ["daily", "opening"]:
		catalog["lifecycle_fish_" + moment] = {"lifecycle_fixture": moment, "group": "prop_lifecycle", "day": moments[moment][0], "time": moments[moment][1], "phase": "prep",
			"player": Vector3(-5.2, .1, 18.6), "camera_at": Vector3(-5.8, 1.0, 16.9), "camera_focus": Vector3(-8.1, .4, 16.9)}
	for moment: String in ["daily", "preparing", "after"]:
		catalog["lifecycle_wood_" + moment] = {"lifecycle_fixture": moment, "group": "prop_lifecycle", "farm": true, "day": moments[moment][0], "time": 10.5, "phase": "prep",
			"player": Vector3(-13.5, .1, -8.4), "camera_at": Vector3(-13.7, 1.5, -8.5), "camera_focus": Vector3(-15.2, .30, -9.8), "fov": 42.0}
	for moment: String in ["bread_delivered", "bread_stored"]:
		catalog["lifecycle_" + moment] = {"lifecycle_fixture": moment, "group": "prop_lifecycle", "day": 3 if moment == "bread_delivered" else 4, "time": 11.0, "phase": "prep",
			"player": Vector3(3.4, .1, 13.2), "camera_at": Vector3(3.4, 1.55, 13.9), "camera_focus": Vector3(1.45, .83, 15.5), "fov": 43.0}
	for moment: String in ["tea_ready", "tea_returned", "tea_stored", "tea_morning"]:
		catalog["lifecycle_" + moment] = {"lifecycle_fixture": moment, "group": "prop_lifecycle", "day": 4 if moment in ["tea_stored", "tea_morning"] else 3, "time": 8.0 if moment == "tea_morning" else 11.0, "phase": "prep",
			"player": Vector3(14.5, .1, 13.9), "camera_at": Vector3(14.5, 1.85, 14.3), "camera_focus": Vector3(15.8, 1.0, 15.15), "fov": 42.0}
	return catalog

static func prepare(main: Node, key: String) -> bool:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
		push_error("Lifecycle evidence requires an isolated HARUMACHI_SAVE_DIR")
		return false
	if _baseline.is_empty(): _baseline = GameState.to_dict().duplicate(true)
	var review_day: int = GameState.day
	var review_minute: float = GameState.minute
	GameState.from_dict(_baseline.duplicate(true))
	GameState.day = review_day; GameState.minute = review_minute; GameState.phase = "prep"; GameState.clock_paused = true
	for qid: String in ["Q00", "Q01", "Q04", "Q05", "Q10", "Q11"]:
		GameState.quests[qid] = {"state": "done", "step": GameState.quests_db[qid].steps.size()}
	GameState.flags.summer_projects.mainline_mode = "cooperation"
	GameState.flags["summer_space"] = {"version": 1, "phase": "invitation", "optional_wood": 0}
	GameState.flags.erase("scene_lifecycle")
	var life: Node = main.world.get_node_or_null("SceneLifecycle")
	if life: life.end_practice("taiko")
	if key in ["early_build", "preparing", "deferred", "opening", "cleanup", "after", "resident_fallback"]:
		GameState.flags.summer_space.phase = "arranging"
		GameState.flags.summer_space.optional_wood = 2 if key == "early_build" else 4 if key == "preparing" else 0
	if key in ["opening", "cleanup", "after"]:
		GameState.flags.summer_space.phase = "retained"; GameState.flags.summer_space.optional_wood = 6
		GameState.quests.Q13 = {"state": "done", "step": GameState.quests_db.Q13.steps.size()}
	if key == "practice" and life: life.begin_practice("taiko")
	if key in ["bread_delivered", "bread_stored"]:
		GameState.quests.Q02 = {"state": "done", "step": GameState.quests_db.Q02.steps.size()}
		GameState.flags["scene_lifecycle"] = {"version": 1, "deliveries": {"bread": {"day": 3, "minute": 600.0, "amount": 1}}}
	if key in ["tea_ready", "tea_returned", "tea_stored", "tea_morning"]:
		DailyLife.state().introduced_day = 1
		DailyLife.event("tea").state = "pending" if key == "tea_ready" else "done"
		DailyLife.event("tea").completed_day = 3 if key != "tea_ready" else -1
	main.world.sync_festivals()
	main._sync_props(); main.story.daily.view.sync_state(); main.story.space.view.sync_state()
	return true
