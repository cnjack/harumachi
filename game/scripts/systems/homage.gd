class_name Homage
extends RefCounted
## Optional discoveries use existing SQLite-backed flags, separate from town history.
const STATE_KEY := "homage"
static var _entries: Array = []
static var _mutating := false

static func entries() -> Array:
	if _entries.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/homage.json"))
		if parsed is Dictionary:
			_entries = parsed.get("items", [])
	return _entries

static func definition(id: String) -> Dictionary:
	for entry: Dictionary in entries():
		if str(entry.id) == id:
			return entry
	return {}

static func state() -> Dictionary:
	var value: Variant = GameState.flags.get(STATE_KEY, {})
	return value if value is Dictionary else {}

static func found(id: String) -> bool:
	return not definition(id).is_empty() and int(entry_state(id).get("found_day", 0)) > 0

static func entry_state(id: String) -> Dictionary:
	var value: Variant = state().get(id, {})
	return value if value is Dictionary else {}

static func count() -> int:
	var total := 0
	for entry: Dictionary in entries():
		if found(str(entry.id)):
			total += 1
	return total

static func paid(id: String) -> Array:
	var value: Variant = entry_state(id).get("paid", [])
	var result: Array = []
	if value is Array:
		for item_id: Variant in value:
			if definition(id).get("requires", []).has(item_id) and not result.has(item_id):
				result.append(item_id)
	return result

static func remaining(id: String) -> Array:
	var result: Array = []
	for item_id: String in definition(id).get("requires", []):
		if not paid(id).has(item_id):
			result.append(item_id)
	return result

static func discover(id: String) -> bool:
	var entry := definition(id)
	if _mutating or entry.is_empty() or found(id) or not entry.get("requires", []).is_empty():
		return false
	var saved := state().duplicate(true)
	saved[id] = {"found_day": GameState.day, "paid": []}
	GameState.flags[STATE_KEY] = saved
	GameState.state_changed.emit()
	return true

static func donate(id: String, item_id: String) -> bool:
	if _mutating or found(id) or not remaining(id).has(item_id) or not GameState.has(item_id):
		return false
	_mutating = true
	var saved := state().duplicate(true)
	var offered := paid(id).duplicate()
	offered.append(item_id)
	var required: Array = definition(id).get("requires", [])
	saved[id] = {"paid": offered, "found_day": GameState.day if offered.size() == required.size() else 0}
	# Commit before inventory signals: a callback cannot donate the same slot twice.
	GameState.flags[STATE_KEY] = saved
	var removed := GameState.remove_item(item_id, 1)
	_mutating = false
	GameState.state_changed.emit()
	return removed

static func world_position(entry: Dictionary, for_stand: bool = false) -> Vector3:
	var coordinates: Array = entry.stand if for_stand else entry.at
	var p := Vector2(float(coordinates[0]), float(coordinates[1]))
	var farm_region: bool = str(entry.region) == "farm"
	return (FarmBuilder.ORIGIN if farm_region else Vector3.ZERO) + Vector3(p.x, LakesideLayout.height_at(p) if farm_region else 0.0, p.y)

static func image_path(entry: Dictionary) -> String:
	return "res://assets/ui/homage/%s.png" % str(entry.image)
