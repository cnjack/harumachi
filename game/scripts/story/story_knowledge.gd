class_name StoryKnowledge
extends RefCounted
## Player knowledge is based on presented information, not affection, stars or dates.
static func initialize() -> void:
	var G := GameState
	if not G.flags.get("story_knowledge", {}) is Dictionary or G.flags.get("story_knowledge", {}).get("version", 0) != 1:
		G.flags["story_knowledge"] = {"version": 1, "activities": {}, "fragments": {}}
	G.flags.story_knowledge["version"] = 1
	for fragment_id: String in G.flags.story_knowledge.fragments:
		G.flags.story_knowledge.fragments[fragment_id] = int(G.flags.story_knowledge.fragments[fragment_id])
	# Old records prove familiarity, but cannot prove an audience or a particular catch.
	for id: String in G.MINIGAMES:
		if int(G.mg_record(id).plays) > 0 or G.flags.get({"onigiri": "rice_seen", "goldfish": "goldfish_seen", "taiko": "taiko_seen", "puzzle": "map_framed"}.get(id, ""), false):
			G.flags.story_knowledge.activities[id] = true

static func activity_known(id: String) -> bool:
	initialize()
	return bool(GameState.flags.story_knowledge.activities.get(id, false))

static func observe_activity(id: String) -> void:
	initialize()
	GameState.flags.story_knowledge.activities[id] = true
	GameState.state_changed.emit()

static func fragments() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story_fragments.json"))
	return data.get("items", [])

static func presented(id: String) -> bool:
	initialize()
	return GameState.flags.story_knowledge.fragments.has(id)

static func remember(id: String) -> void:
	initialize()
	if not presented(id):
		GameState.flags.story_knowledge.fragments[id] = GameState.day
		GameState.state_changed.emit()

static func fragment(id: String) -> Dictionary:
	for entry: Dictionary in fragments():
		if str(entry.id) == id: return entry
	return {}
