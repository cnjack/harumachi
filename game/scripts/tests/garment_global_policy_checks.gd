extends RefCounted
## Native global-shape policy contract. Requires Kazu's restored accepted walk
## curve (v89 or a successor preserving it), plus a real Mio Local garment rig.
## This checks actual production callbacks, not source cloth fit or certificates.
const AUTHORED_GUARD = preload("res://scripts/characters/garment_authored_shape_guard.gd")
const SUPPORT_SCRIPT = preload("res://scripts/characters/character_garment_support.gd")
const GROUP := "GARMENT_GLOBAL_POLICY"
const CASE_NAMES: Array[String] = [
	"Kazu source profile enables its nonzero accepted walk apron curve",
	"Kazu actual support excludes enabled Apron_Clearance from disabled indices",
	"Kazu later native callbacks retain positive apron values matching real AP interpolation",
	"Mio explicit default policy disables and clears Skirt_Clearance in a real callback",
	"Mio omitted policy field keeps the production default and clears an externally seeded skirt value",
]
var t: Node

func _init(runner: Node) -> void:
	t = runner

func check_case(index: int, passed: bool, detail: Dictionary) -> void:
	t.check(GROUP, CASE_NAMES[index], passed, JSON.stringify(detail))

func source_profile(npc: NPC) -> Dictionary:
	var rig: Node = npc.model.find_child("Rig", true, false)
	if rig == null: return {}
	var extras: Dictionary = rig.get_meta("extras", {})
	return (extras.get("garment_local_clearance", {}) as Dictionary).duplicate(true)

func save_npc(npc: NPC) -> Dictionary:
	return {"position": npc.global_position, "home": npc.home, "yaw": npc._yaw,
		"process": npc.is_processing(), "physics_process": npc.is_physics_processing(),
		"clip": npc.anim.ap.current_animation, "time": npc.anim.ap.current_animation_position,
		"speed": npc.anim.ap.speed_scale, "active": npc.anim.ap.active,
		"state": npc.anim._state, "oneshot": npc.anim._oneshot}

func configure(npc: NPC, phase: float) -> void:
	npc.set_process(false)
	npc.set_physics_process(false)
	npc.set_home(false)
	npc.global_position = Vector3(-8, .010, -10)
	npc.set_yaw(0)
	npc.anim._oneshot = ""
	npc.anim.ap.active = true
	npc.anim._go("walk", 1.0)
	npc.anim._state = "walk"
	# No remaining AP blend can masquerade as an authored-track discrepancy.
	npc.anim.ap.play("walk", 0.0)
	npc.anim.ap.speed_scale = 0.0
	npc.anim.ap.seek(npc.anim.ap.get_animation("walk").length * phase, true)
	npc.anim.ap.advance(0.0)
	var natural: Node = npc.model.find_child("NaturalLocomotionPose", true, false)
	if natural != null and natural.has_method("finish_transition"): natural.call("finish_transition")

func restore_npc(npc: NPC, saved: Dictionary) -> void:
	npc.global_position = saved.position
	npc.set_yaw(float(saved.yaw))
	npc.set_home(bool(saved.home))
	npc.anim._state = str(saved.state)
	npc.anim._oneshot = str(saved.oneshot)
	if not str(saved.clip).is_empty():
		npc.anim.ap.play(str(saved.clip), 0.0)
		npc.anim.ap.seek(float(saved.time), true)
	else:
		npc.anim.ap.stop()
	npc.anim.ap.speed_scale = float(saved.speed)
	npc.anim.ap.active = bool(saved.active)
	npc.set_process(bool(saved.process))
	npc.set_physics_process(bool(saved.physics_process))

func fresh_callback(support: Node) -> Dictionary:
	var requested_frame: int = Engine.get_process_frames()
	var measured: Dictionary = {}
	for attempt: int in 8:
		await t.get_tree().process_frame
		measured = (support.call("performance") as Dictionary).duplicate(true)
		if int(measured.get("last_callback_frame", -1)) > requested_frame:
			measured["fresh"] = true
			measured["request_frame"] = requested_frame
			return measured
	measured["fresh"] = false
	measured["request_frame"] = requested_frame
	return measured

func kazuko_contract() -> void:
	var npc: NPC = t.main.npcs["kazuko"]
	var support: Node = npc.model.find_child("CharacterGarmentSupport", true, false)
	if support == null or not support.has_method("performance"):
		for missing: int in 3: check_case(missing, false, {"reason": "real Kazu production support absent"})
		return
	var mesh: MeshInstance3D = support.get("mesh") as MeshInstance3D
	if mesh == null or not mesh.mesh is ArrayMesh:
		for missing_mesh: int in 3: check_case(missing_mesh, false, {"reason": "real Kazu imported mesh absent"})
		return
	var shape: int = mesh.find_blend_shape_by_name("Apron_Clearance")
	var profile: Dictionary = source_profile(npc)
	var disabled_names: Array = profile.get("disable_global_shapes", ["Skirt_Clearance", "Apron_Clearance"])
	var indices: PackedInt32Array = support.get("original_indices")
	var plan: Dictionary = AUTHORED_GUARD.prepare(mesh, npc.anim.ap, indices, ["walk"])
	var plan_valid: bool = bool(plan.get("valid", false))
	var source_slot: int = indices.find(shape)
	var source_track := -1
	if plan_valid and source_slot >= 0:
		var clip_plan: Dictionary = (plan.get("clips", {}) as Dictionary).get("walk", {})
		var tracks: PackedInt32Array = clip_plan.get("tracks", PackedInt32Array())
		if source_slot < tracks.size(): source_track = tracks[source_slot]
	var animation: Animation = npc.anim.ap.get_animation("walk")
	var imported_nonzero := false
	if source_track >= 0:
		for key: int in animation.track_get_key_count(source_track):
			imported_nonzero = imported_nonzero or float(animation.track_get_key_value(source_track, key)) > .01
	var fixture_valid: bool = shape >= 0 and plan_valid and source_track >= 0 and imported_nonzero and not disabled_names.has("Apron_Clearance")
	check_case(0, fixture_valid, {"profile_disabled_shapes": disabled_names, "shape_index": shape,
		"plan_valid": plan_valid, "plan_error": plan.get("error", ""), "source_track": source_track,
		"actual_imported_track_contains_positive_value": imported_nonzero,
		"fixture": "restored accepted Kazu walk, e.g. v89 ece35f85; old all-zero cb4 must fail this precondition"})
	var actual_disabled: PackedInt32Array = support.get("disabled_indices")
	check_case(1, fixture_valid and not actual_disabled.has(shape), {"actual_disabled_indices": Array(actual_disabled), "apron_index": shape})
	var saved: Dictionary = save_npc(npc)
	var valid_callbacks: bool = fixture_valid
	var samples: Array[Dictionary] = []
	for phase: float in [.125, .375, .625]:
		configure(npc, phase)
		var measured: Dictionary = await fresh_callback(support)
		var clip_time: float = npc.anim.ap.current_animation_position
		var expected: float = animation.blend_shape_track_interpolate(source_track, clip_time) if source_track >= 0 else NAN
		var actual: float = mesh.get_blend_shape_value(shape) if shape >= 0 else NAN
		var current := PackedFloat32Array()
		for original: int in indices: current.append(mesh.get_blend_shape_value(original))
		var mismatch: String = AUTHORED_GUARD.mismatch(plan, "walk", clip_time, current)
		var okay: bool = bool(measured.get("fresh", false)) and is_finite(expected) and is_finite(actual) and expected > .01 and actual > .01 and absf(actual - expected) <= AUTHORED_GUARD.VALUE_EPSILON and mismatch.is_empty()
		valid_callbacks = valid_callbacks and okay
		samples.append({"phase": phase, "clip": npc.anim.ap.current_animation, "clip_time": clip_time,
			"expected_from_imported_AP_track": expected, "actual_after_callback": actual,
			"authored_mismatch": mismatch, "fresh": measured.get("fresh", false),
			"request_frame": measured.get("request_frame", -1), "applied_frame": measured.get("last_callback_frame", -1)})
	check_case(2, valid_callbacks, {"samples": samples, "weight_epsilon": AUTHORED_GUARD.VALUE_EPSILON})
	restore_npc(npc, saved)

func mio_default_contract() -> void:
	var npc: NPC = t.main.npcs["mio"]
	var support: SkeletonModifier3D = npc.model.find_child("CharacterGarmentSupport", true, false) as SkeletonModifier3D
	var skeleton: Skeleton3D = npc.model.find_child("Skeleton3D", true, false) as Skeleton3D
	if support == null or skeleton == null or not support.has_method("performance"):
		check_case(3, false, {"reason": "real Mio support/skeleton absent"})
		check_case(4, false, {"reason": "real Mio support/skeleton absent"})
		return
	var mesh: MeshInstance3D = support.get("mesh") as MeshInstance3D
	if mesh == null:
		check_case(3, false, {"reason": "real Mio mesh absent"})
		check_case(4, false, {"reason": "real Mio mesh absent"})
		return
	var saved: Dictionary = save_npc(npc)
	configure(npc, .375)
	# Stop the mixer from independently overwriting our seed with an authored0.
	# Only the real production modifier may clear this controlled external edit.
	npc.anim.ap.active = false
	var shape: int = mesh.find_blend_shape_by_name("Skirt_Clearance")
	var profile: Dictionary = source_profile(npc)
	# The final Mio model may intentionally enable its accepted source curve.
	# Supply explicit default/omitted policies to NEW production instances over
	# this unchanged real mesh; do not make product metadata a test precondition.
	var original_active: bool = support.active
	support.active = false
	var explicit_profile: Dictionary = profile.duplicate(true)
	var configured_names: Array = ["Skirt_Clearance", "Apron_Clearance"]
	explicit_profile["disable_global_shapes"] = configured_names
	var configured: SkeletonModifier3D = SUPPORT_SCRIPT.new()
	configured.name = "GlobalPolicyExplicitProductionFixture"
	skeleton.add_child(configured)
	configured.call("prepare", npc.model, explicit_profile)
	var configured_mesh: MeshInstance3D = configured.get("mesh") as MeshInstance3D
	var configured_disabled: PackedInt32Array = configured.get("disabled_indices")
	if shape >= 0: mesh.set_blend_shape_value(shape, .713)
	var seeded: float = mesh.get_blend_shape_value(shape) if shape >= 0 else NAN
	var configured_callback: Dictionary = await fresh_callback(configured)
	var configured_actual: float = mesh.get_blend_shape_value(shape) if shape >= 0 else NAN
	check_case(3, configured_mesh == mesh and shape >= 0 and configured_names.has("Skirt_Clearance") and configured_disabled.has(shape) and seeded > .7 and not npc.anim.ap.active and bool(configured_callback.get("fresh", false)) and configured_actual == 0.0,
		{"explicit_fixture_disabled_shapes": configured_names, "uses_real_same_mesh": configured_mesh == mesh,
		"product_profile_has_field": profile.has("disable_global_shapes"), "product_disabled_shapes_not_a_precondition": profile.get("disable_global_shapes", []),
		"actual_disabled_indices": Array(configured_disabled), "seeded": seeded,
		"actual_after_callback": configured_actual, "mixer_active": npc.anim.ap.active,
		"fresh": configured_callback.get("fresh", false), "applied_frame": configured_callback.get("last_callback_frame", -1)})
	configured.active = false
	skeleton.remove_child(configured)
	configured.queue_free()
	# Exercise absence of the key through a genuine production prepare(), using
	# the real unchanged Mio mesh/skin. No shadow implementation or fake mesh is
	# allowed to stand in for the runtime's default expression.
	var fallback: SkeletonModifier3D = SUPPORT_SCRIPT.new()
	fallback.name = "GlobalPolicyDefaultProductionFixture"
	skeleton.add_child(fallback)
	var omitted_profile: Dictionary = profile.duplicate(true)
	omitted_profile.erase("disable_global_shapes")
	fallback.call("prepare", npc.model, omitted_profile)
	var fallback_mesh: MeshInstance3D = fallback.get("mesh") as MeshInstance3D
	var fallback_disabled: PackedInt32Array = fallback.get("disabled_indices")
	if shape >= 0: mesh.set_blend_shape_value(shape, .713)
	var fallback_seeded: float = mesh.get_blend_shape_value(shape) if shape >= 0 else NAN
	var fallback_callback: Dictionary = await fresh_callback(fallback)
	var fallback_actual: float = mesh.get_blend_shape_value(shape) if shape >= 0 else NAN
	check_case(4, not omitted_profile.has("disable_global_shapes") and fallback_mesh == mesh and shape >= 0 and fallback_disabled.has(shape) and fallback_seeded > .7 and not npc.anim.ap.active and bool(fallback_callback.get("fresh", false)) and fallback_actual == 0.0,
		{"omitted_profile_has_field": omitted_profile.has("disable_global_shapes"), "uses_real_same_mesh": fallback_mesh == mesh,
		"actual_disabled_indices": Array(fallback_disabled), "seeded": fallback_seeded,
		"actual_after_callback": fallback_actual, "mixer_active": npc.anim.ap.active,
		"fresh": fallback_callback.get("fresh", false), "applied_frame": fallback_callback.get("last_callback_frame", -1)})
	fallback.active = false
	skeleton.remove_child(fallback)
	fallback.queue_free()
	support.active = original_active
	restore_npc(npc, saved)

func run() -> void:
	var main: Node = t.main
	var context: Dictionary = {"region": main.world.region, "in_room": main.in_room,
		"room_kind": main.room_kind, "player_in_room": GameState.player_in_room}
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	await kazuko_contract()
	await mio_default_contract()
	main.in_room = context.in_room
	main.room_kind = context.room_kind
	GameState.player_in_room = context.player_in_room
	main.world.set_region(str(context.region))
	main.world.set_indoor_look(bool(context.in_room))
