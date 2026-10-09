class_name Dialogue
extends RefCounted
## Picks everyday lines from data/dialogue.json. Each entry lists conditions (time of day, weather,
## weekday, hearts, flags, quest state, region, market); the most specific entry not yet heard
## today wins, one-time heart events outrank everything once their conditions hold.

static var entries: Array = []


static func load_db() -> void:
	if not entries.is_empty():
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue.json"))
	if typeof(d) == TYPE_DICTIONARY:
		entries = d.get("entries", [])


static func _list(v) -> Array:
	return v if typeof(v) == TYPE_ARRAY else [v]


static func matches(e: Dictionary, ctx: Dictionary) -> bool:
	var G := GameState
	var w: Dictionary = e.get("when", {})
	var who: String = e.who
	if w.has("period") and not _list(w.period).has(G.period()):
		return false
	if w.has("weather") and not _list(w.weather).has(G.weather):
		return false
	if w.has("weekday") and not _list(w.weekday).map(func(x): return int(x)).has(G.weekday()):
		return false
	var aff := int(G.affinity.get(who, 0))
	if aff < int(w.get("aff_min", 0)) or aff > int(w.get("aff_max", 99)):
		return false
	for f in _list(w.get("flag", [])):
		if not G.flags.get(f, false):
			return false
	for f in _list(w.get("not_flag", [])):
		if G.flags.get(f, false):
			return false
	for keepsake in _list(w.get("found", [])):
		if not Progress.found(str(keepsake)): return false
	for keepsake in _list(w.get("not_found", [])):
		if Progress.found(str(keepsake)): return false
	var fm: Dictionary = w.get("flag_min", {})
	for k in fm:
		if int(G.flags.get(k, 0)) < int(fm[k]):
			return false
	var equals: Dictionary = w.get("flag_equals", {})
	for k in equals:
		if not G.flags.has(k) or G.flags[k] != equals[k]:
			return false
	for q in _list(w.get("done", [])):
		if G.qstate(q) != "done":
			return false
	for q in _list(w.get("not_done", [])):
		if G.qstate(q) == "done":
			return false
	for q in _list(w.get("active", [])):
		if G.qstate(q) != "active":
			return false
	if G.day < int(w.get("day_min", 0)):
		return false
	if w.has("region") and str(w.region) != str(ctx.get("region", "town")):
		return false
	if w.has("place") and not _list(w.place).has(str(ctx.get("place", ""))): return false
	if e.get("event", false) and int(G.flags.get("dlg_deferred", {}).get(str(e.id), -1)) == G.day: return false
	if w.has("phase") and str(w.phase) != G.phase:
		return false
	if w.has("festival") and G.festival_now() != str(w.festival):
		return false
	if w.has("fest_day") and G.festival_on(G.day) != str(w.fest_day):
		return false
	if w.has("level_min") and G.level() < int(w.level_min):
		return false
	if e.get("once", false) and G.flags.get("dlg_once_" + str(e.id), false):
		return false
	return true


## Best entry for this speaker right now, or {} when nothing fits.
static func pick(who: String, ctx: Dictionary = {}) -> Dictionary:
	load_db()
	var G := GameState
	var seen: Dictionary = G.flags.get("dlg_seen", {})
	var best: Array = []
	var best_score := -1.0
	for e in entries:
		if str(e.id) == str(ctx.get("skip_entry", "")): continue
		if e.who != who or not matches(e, ctx):
			continue
		var today := int(seen.get(e.id, -1)) == G.day
		if today and not e.get("event", false):
			continue
		var w: Dictionary = e.get("when", {})
		var score := float(w.size()) + float(e.get("priority", 0))
		# situational lines (rain, a festival, the time of day) beat general ones
		# (quest-progress gates count half, so chapter lines join the rotation without drowning out rain or festival lines)
		score += (1.0 if w.has("weather") else 0.0) + (2.0 if w.has("festival") else 0.0) + (0.3 if w.has("period") else 0.0)
		score -= 0.5 * float(int(w.has("done")) + int(w.has("not_done")) + int(w.has("active")))
		if not seen.has(e.id):
			score += 0.5   # prefer lines the player has never heard
		if score > best_score + 0.01:
			best_score = score
			best = [e]
		elif absf(score - best_score) <= 0.01:
			best.append(e)
	if best.is_empty():
		return {}
	return best[(G.day * 7 + int(G.minute) / 30 + who.length()) % best.size()]


static func mark(e: Dictionary) -> void:
	var G := GameState
	var seen: Dictionary = G.flags.get("dlg_seen", {})
	seen[e.id] = G.day
	G.flags["dlg_seen"] = seen
	if e.get("once", false):
		G.flags["dlg_once_" + str(e.id)] = true
	if e.has("set"):
		G.flags[str(e.set)] = true
