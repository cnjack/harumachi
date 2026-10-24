extends RefCounted
## Workplaces are NPC schedule state, not a side effect of entering a room.
const ROOMS := {"ren": "bakery", "kazuko": "store"}

static func room_for(who: String) -> String:
	return str(ROOMS.get(who, ""))

static func working_room(who: String) -> String:
	var kind: String = room_for(who)
	if kind.is_empty() or GameState.shop_closed_reason(kind) != "": return ""
	# A dry-day errand is still an errand during opening hours. Only the
	# workplace entry in the outdoor schedule maps to the actual counter.
	var routine: Array = Layout.daily_schedule(who, GameState.weekday(), GameState.weather)
	var entry: Array = []
	for candidate: Array in routine:
		if GameState.hour() >= float(candidate[0]): entry = candidate
	if entry.size() < 3 or str(entry[1]) != "town": return ""
	var goal: Vector3 = entry[2]
	return kind if goal.distance_to(Layout.NPC[who].prep) < .1 else ""

static func present(main: Node, kind: String) -> bool:
	var who: String = "ren" if kind == "bakery" else "kazuko" if kind == "store" else ""
	if who.is_empty() or not main.npcs.has(who): return false
	var actor: NPC = main.npcs[who]
	return not actor.home and InteriorBuilder.at(actor.global_position) == kind

static func show_in_room(actor: NPC, visible_here: bool) -> void:
	# NPCs are children of Main, not of the room that WorldBuilder hides.
	# Hide their label and interaction body with that room as well.
	actor.visible = visible_here
	actor.talk.radius = 2.3 if visible_here else 0.0
	actor.body.collision_layer = WorldBuilder.L_ACTORS if visible_here else 0
