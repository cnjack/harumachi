extends Node3D
## P09 is borrowed for deliveries, route preparation, tasting and real service.
## Permanent pergolas, bicycle and recycling shelters are not portable stalls.
var lifecycle: Node
var world: Node
var counter: Node3D
var preparation: Node3D
var preparation_supported := false
var project_food: Node3D
var _frame_parts: Array[Node3D] = []
var _loans: Dictionary = {}
var _next_loan := 0

func setup(owner_lifecycle: Node) -> void:
	lifecycle = owner_lifecycle; world = lifecycle.world
	name = "StallLifecycle"
	counter = world.get_node("P09")
	for child: Node in counter.get_children():
		if child is Node3D and child.visible and not child is CollisionObject3D:
			_frame_parts.append(child as Node3D)
	_build_preparation()

func begin_tasting(owner_scene: Node) -> int:
	if not is_instance_valid(owner_scene) or world.region != "town" or world.indoor: return -1
	_next_loan += 1
	_loans[_next_loan] = {"owner": weakref(owner_scene), "day": GameState.day, "flags": GameState.flags}
	lifecycle.sync_state()
	return _next_loan

func end_tasting(token: int) -> void:
	_loans.erase(token)
	lifecycle.sync_state()

func _tasting() -> bool:
	for token: int in _loans.keys():
		var loan: Dictionary = _loans[token]
		var owner_scene: Node = (loan.owner as WeakRef).get_ref() as Node
		if not is_instance_valid(owner_scene) or not owner_scene.is_inside_tree() or int(loan.day) != GameState.day or not is_same(loan.flags, GameState.flags):
			_loans.erase(token)
	return not _loans.is_empty()

func snapshot(market: bool) -> Dictionary:
	var opening: Dictionary = GameState.flags.get("summer_projects", {}).get("opening", {})
	var service: Dictionary = opening.get("service", {})
	var remaining: int = maxi(0, int(service.get("remaining", 0)))
	var serving: bool = remaining > 0 or service.has("pending")
	var delivery: Dictionary = GameState.flags.get("scene_lifecycle", {}).get("deliveries", {}).get("bread", {})
	var delivered: bool = int(delivery.get("day", -1)) == GameState.day and GameState.minute >= float(delivery.get("minute", 0.0)) and GameState.hour() < 20.0
	# An exhausted cooperative batch stays exhausted; an open market must not
	# refill its counter by substituting a second, unrecorded basket of bread.
	var bread: String = "delivered" if delivered else "resident_market" if market and service.is_empty() else "stored"
	var tasting: bool = _tasting()
	var preparing: bool = GameState.at_step("Q02", "deliver_basket") and GameState.has("bread_basket")
	# An unaccepted job or an unfinished sample does not reserve an empty stall.
	# Confirmed serving plans need the actual frame while testing their approach.
	preparing = preparing or str(opening.get("phase", "invitation")) in ["site", "ready"]
	# Keep the now-empty tray while the player closes an actual service. Once
	# that paper is filed, only real leftovers can keep the counter in use.
	preparing = preparing or str(opening.get("phase", "")) == "applied" and not service.is_empty()
	preparing = preparing or GameState.at_step("Q05", "place_seats") or GameState.at_step("Q05", "invite") or GameState.at_step("Q05", "start")
	var state: String = "stored"
	if market: state = "market"
	elif serving: state = "serving"
	elif delivered: state = "delivered"
	elif tasting: state = "tasting"
	elif preparing: state = "preparing"
	return {"state": state, "bread": bread, "remaining": remaining, "tasting": tasting,
		"preparation": state != "stored" and bread == "stored" and remaining == 0}

func available() -> bool:
	return world.region == "town" and not world.indoor and counter.is_visible_in_tree() and str(counter.get_meta("lifecycle_state", "stored")) != "stored"

func sync_state(state: Dictionary, local_town: bool) -> void:
	var deployed: bool = str(state.state) != "stored" and local_town
	lifecycle.activate(counter, deployed)
	# set_region restores top-level visible. Keep the imported frame's children
	# in the same state, so a generic top-level restore cannot flash an empty roof.
	for part: Node3D in _frame_parts: part.visible = deployed
	counter.set_meta("lifecycle_state", state.state)
	preparation.visible = deployed and bool(state.preparation) and preparation_supported
	world.stall_bread.visible = deployed and str(state.bread) != "stored"
	world.stall_bread.set_meta("lifecycle_state", state.bread)
	if is_instance_valid(project_food): project_food.visible = deployed and int(state.remaining) > 0

func _build_preparation() -> void:
	preparation = Node3D.new(); preparation.name = "ServingPreparation"; add_child(preparation)
	var at: Vector3 = world.stall_bread_surface
	if not at.is_finite(): return
	var tray: Node3D = world.spawn("W12_cedar_tray", Vector3.ZERO, 0, 0, preparation)
	tray.name = "PreparationTray"
	var bounds: AABB = tray.global_transform * WorldBuilder.local_aabb(tray)
	tray.global_position += at - Vector3(bounds.get_center().x, bounds.position.y - .002, bounds.get_center().z)
	bounds = tray.global_transform * WorldBuilder.local_aabb(tray)
	preparation_supported = true
	for x: float in [bounds.position.x, bounds.end.x]:
		for z: float in [bounds.position.z, bounds.end.z]:
			var height: float = WorldBuilder.rendered_support_height(counter, Vector3(x, 0, z), 1.35, true)
			if not is_finite(height) or absf(height - at.y) > .015: preparation_supported = false
	var paper_at: Vector3 = at
	paper_at.y = WorldBuilder.rendered_support_height(tray, at, at.y + .1, true)
	if not paper_at.is_finite(): preparation_supported = false; return
	for index: int in 3:
		var paper: MeshInstance3D = MealModels.part(preparation, "CleanPaper_%d" % index, "box", Vector3(.18, .002, .15), paper_at + Vector3(index * .003, .003 + index * .003, 0), Color(.97, .94, .85))
		paper.rotation.y = .035 * (index - 1)
	preparation.set_meta("purpose", "clean serving tray and paper; no food before delivery")
