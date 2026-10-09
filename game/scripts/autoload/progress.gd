extends Node
## v0.6 achievements (data/achievements.json) and 晴町旧物 keepsakes (data/collection.json).
## GameState keeps what was earned (achievements / collection / zukan, saved in v4); this node knows
## the rules. Conditions are re-checked (at most once a frame) whenever the game state changes.

signal unlocked(id: String)
signal keepsake_found(id: String)

var ach_db: Array = []
var ach_by_id := {}
var col_db: Array = []
var col_by_id := {}
var _dirty := false
var quiet := false            # tests switch the cards off
const FEST_KEYS := ["tanabata_wish", "contest_entry", "bon_odori", "hanabi", "toro", "tsukimi"]
const MG_IDS := ["onigiri", "puzzle", "goldfish", "taiko"]


func _ready() -> void:
	ach_db = _load("res://data/achievements.json")
	col_db = _load("res://data/collection.json")
	for a in ach_db:
		ach_by_id[a.id] = a
	for c in col_db:
		col_by_id[c.id] = c
	GameState.state_changed.connect(func(): _dirty = true)


func _load(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	return d.get("items", []) if typeof(d) == TYPE_DICTIONARY else []


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		check()


# ------------------------------------------------------------------ achievements
func has(id: String) -> bool:
	return GameState.achievements.has(id)


func count() -> int:
	return GameState.achievements.size()


## Unlock everything whose condition now holds. Returns the ids unlocked by this call.
func check() -> Array:
	var got := []
	for a in ach_db:
		if not GameState.achievements.has(a.id) and holds(str(a.cond)):
			GameState.achievements[a.id] = GameState.day
			got.append(a.id)
			unlocked.emit(a.id)
	return got


func value(key: String) -> float:
	var G := GameState
	match key:
		"crops_grown":
			return G.zukan.crops.size()
		"dishes_made":
			return G.zukan.dishes.size()
		"level":
			return G.level()
		"coins":
			return G.coins
		"hearts_max":
			return G.affinity.values().max() if not G.affinity.is_empty() else 0
		"hearts_min":
			return G.affinity.values().min() if not G.affinity.is_empty() else 0
		"fests":
			return FEST_KEYS.filter(func(k): return G.flags.get("fest_" + k, false)).size()
		"mg_all":
			var m := 3
			for id in MG_IDS:
				m = mini(m, int(G.minigames.get(id, {}).get("stars", 0)))
			return m
		"memories":
			return G.collection.size()
	return 0.0


func holds(cond: String) -> bool:
	var G := GameState
	if cond == "zukan_full":
		return G.zukan.crops.size() >= G.crops_db.size() and G.zukan.dishes.size() >= G.recipes_db.size()
	var colon := cond.find(":")
	if colon > 0:
		var kind := cond.substr(0, colon)
		var rest := cond.substr(colon + 1)
		match kind:
			"q":
				return G.qstate(rest) == "done"
			"item":
				return G.has(rest)
			"fest":
				return bool(G.flags.get("fest_" + rest, false))
			"flag":
				return bool(G.flags.get(rest, false))
			"stat":
				var p := rest.split(">=")
				return float(G.flags.get(p[0], 0)) >= float(p[1])
			"mg":
				var p := rest.split(">=")
				return int(G.minigames.get(p[0], {}).get("stars", 0)) >= int(p[1])
	if cond.contains(">="):
		var p := cond.split(">=")
		return value(p[0]) >= float(p[1])
	return false


## 0..1 progress toward an achievement, for the list's little bar (-1 when it has no counter).
func progress(id: String) -> float:
	var a: Dictionary = ach_by_id.get(id, {})
	var cond := str(a.get("cond", ""))
	if not cond.contains(">="):
		return -1.0
	var p := cond.split(">=")
	var goal := float(p[1])
	var cur: float
	if p[0].begins_with("stat:"):
		cur = float(GameState.flags.get(p[0].substr(5), 0))
	elif p[0].begins_with("mg:"):
		cur = float(GameState.minigames.get(p[0].substr(3), {}).get("stars", 0))
	else:
		cur = value(p[0])
	return clampf(cur / maxf(goal, 1.0), 0.0, 1.0)


# ------------------------------------------------------------------ keepsakes
func found(id: String) -> bool:
	return GameState.collection.has(id)


## Add a keepsake to the collection (once). Returns true the first time.
func find(id: String) -> bool:
	if not col_by_id.has(id) or GameState.collection.has(id):
		return false
	GameState.collection[id] = GameState.day
	keepsake_found.emit(id)
	GameState.state_changed.emit()
	return true


func keepsake(id: String) -> Dictionary:
	return col_by_id.get(id, {})
