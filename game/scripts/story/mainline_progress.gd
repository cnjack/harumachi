class_name MainlineProgress
extends RefCounted
const DIRECTION_OPTIONS := ["留在晴町，先照料一块小菜地", "和街坊商量，再一起开一次摊", "以后再回来，把这个家好好留着", "先不决定，慢慢想一想"]
const DIRECTION_NOTES := ["先照料一块小菜地，够自己吃，也能分一点。", "下次开摊前，先问问街坊想吃什么、怎样拿着方便。", "以后再回来。钥匙和这个夏天的记忆，好好留着。", "今年先记到这里。下一步，我再慢慢想。"]
const DIRECTION_CAPTIONS := ["种点菜","再开摊","再回来","慢慢想"]
## `ended` is the legacy first-weekend milestone, never the end of summer.
static func initialize() -> void:
	var G := GameState
	var data: Dictionary = G.flags.get("mainline_progress", {})
	data["version"] = 1
	data["first_weekend"] = G.qstate("Q05") == "done" or bool(G.flags.get("ended", false))
	data["summer_complete"] = G.qstate("Q15") == "done"
	G.flags["mainline_progress"] = data

static func summer_complete() -> bool:
	initialize()
	return bool(GameState.flags.mainline_progress.summer_complete)

static func weekend_complete() -> void:
	GameState.flags["ended"] = true
	initialize()

static func direction() -> Dictionary:
	var data: Dictionary = GameState.flags.get("summer_direction",{})
	if data.has("choice"): data.choice=int(data.choice)
	if data.has("day"): data.day=int(data.day)
	return data

static func choose_direction(choice: int, origin: String) -> bool:
	if choice<0 or choice>=DIRECTION_OPTIONS.size(): return false
	if origin=="hanabi" and not GameState.flags.get("fest_hanabi",false): return false
	if origin=="record" and not GameState.flags.get("hanabi_revisit",false): return false
	if origin=="home" and GameState.qstate("Q15")!="done": return false
	if origin not in ["hanabi","record","home"]: return false
	GameState.flags["summer_direction"]={"choice":choice,"day":GameState.day,"origin":origin}
	GameState.state_changed.emit()
	GameState.save_game()
	return true
