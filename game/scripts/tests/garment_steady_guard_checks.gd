extends RefCounted
## Actual final-modifier branch regression for Ren's certified zero-local path.
## No observational modifier is attached: it must not change the eligibility
## inventory it measures. Only the support's real callback counters acknowledge
## completion; absent instrumentation is a failure, never an empty success.

class UntrustedModifier:
	extends SkeletonModifier3D
	func _process_modification() -> void:
		pass

class LibrarySignalRecorder:
	extends RefCounted
	var list_changes := 0
	var library_changes := 0
	var original_animation_changes := 0
	func on_list_changed() -> void: list_changes += 1
	func on_libraries_updated() -> void: library_changes += 1
	func on_original_changed() -> void: original_animation_changes += 1

const CASE_NAMES: Array[String] = [
	"Ren idle actual callback takes certified fast path and clears all local shapes",
	"Ren walk actual callback takes certified fast path and clears all local shapes",
	"Ren run actual callback takes certified fast path and clears all local shapes",
	"Ren unfinished real CharAnim transition falls back without steady bypass",
	"Ren pending oneshot on an otherwise eligible idle falls back",
	"Ren seated actor falls back without steady bypass",
	"Ren additional active modifier falls back without steady bypass",
	"Ren wrong fingerprint certificate falls back without changing product bools",
	"Ren restored real certificate resumes certified callback and zero local shapes",
	"Ren same-resource mesh carrier translation falls back",
	"Ren same-resource skeleton carrier translation falls back",
	"Ren in-place inactive walk animation content change invalidates proof",
	"Ren in-place skin bind-pose change invalidates proof",
	"Ren same-resource mesh changed notification invalidates proof",
	"Ren in-place skeleton rest change invalidates proof",
	"Ren restored model content and explicit verification resume certified callback",
	"Ren read-only continuous observer preserves the certified production branch",
	"Ren same-name AnimationLibrary replacement invalidates proof and explicit restoration resumes certified callback",
	"Ren real place then controller idle keeps unfinished AP blend outside certified bypass even after contact reset",
]
var t: Node
var main: Node
var npc: NPC
var support: Node
var skeleton: Skeleton3D

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check_case(index: int, passed: bool, detail: Dictionary) -> void:
	t.check("GARMENT_STEADY_GUARDS", CASE_NAMES[index], passed, JSON.stringify(detail))

func clear_pose_cache() -> void:
	var matrices: Array = support.get("cached_matrices")
	matrices.clear()

func configure(clip: String, phase: float = .375) -> void:
	npc.anim._oneshot = ""
	npc.anim._go(clip, 1.0)
	npc.anim.ap.play(clip, 0)
	npc.anim.ap.speed_scale = 0
	npc.anim.ap.seek(npc.anim.ap.get_animation(clip).length * phase, true)
	npc.anim.ap.advance(0)
	var natural: Node = skeleton.get_node_or_null("NaturalLocomotionPose")
	if natural != null: natural.call("finish_transition")
	clear_pose_cache()

func fresh_callback() -> Dictionary:
	var request_frame: int = Engine.get_process_frames()
	var result: Dictionary = {}
	for frame_attempt: int in 8:
		await t.get_tree().process_frame
		result = (support.call("performance") as Dictionary).duplicate(true)
		if int(result.get("last_callback_frame", -1)) > request_frame:
			result["fresh"] = true
			result["request_frame"] = request_frame
			return result
	result["fresh"] = false
	result["request_frame"] = request_frame
	return result

func weights_are_zero() -> Dictionary:
	var amounts: PackedFloat32Array = support.get("amounts")
	var indices: PackedInt32Array = support.get("local_indices")
	var mesh: MeshInstance3D = support.get("mesh")
	var maximum_amount := 0.0
	var maximum_render_weight := 0.0
	for amount: float in amounts: maximum_amount = maxf(maximum_amount, absf(amount))
	for shape: int in indices: maximum_render_weight = maxf(maximum_render_weight, absf(mesh.get_blend_shape_value(shape)))
	return {"local_count": indices.size(), "amount_count": amounts.size(), "max_amount": maximum_amount, "max_render_weight": maximum_render_weight, "all_zero": indices.size() == 24 and amounts.size() == 24 and maximum_amount == 0.0 and maximum_render_weight == 0.0}

func seed_local_weights() -> void:
	var mesh: MeshInstance3D = support.get("mesh")
	var indices: PackedInt32Array = support.get("local_indices")
	var seeded: PackedFloat32Array = support.get("amounts")
	seeded.fill(.25)
	support.set("amounts", seeded)
	for shape: int in indices: mesh.set_blend_shape_value(shape, .25)
	clear_pose_cache()

func fast_result(previous: Dictionary, measured: Dictionary) -> bool:
	return bool(measured.get("fresh", false)) and bool(measured.get("steady_proof_match", false)) and int(measured.get("steady_fast_updates", 0)) > int(previous.get("steady_fast_updates", 0)) and str(measured.get("last_branch", "")) == "steady_fast"

func fallback_result(previous: Dictionary, measured: Dictionary, reason: String) -> bool:
	# A missing proof must not accidentally stand in for the seated/transition/
	# oneshot/modifier predicate this particular negative fixture exercises.
	var proof_state: bool = bool(measured.get("steady_proof_match", false))
	var valid_proof_expected: bool = reason not in ["unverified model content", "asset carrier transform changed", "certified resource changed"]
	return bool(measured.get("fresh", false)) and proof_state == valid_proof_expected and int(measured.get("steady_fast_updates", -1)) == int(previous.get("steady_fast_updates", -2)) and str(measured.get("last_branch", "")) in ["full", "pose_cache"] and str(measured.get("last_steady_reason", "")) == reason

func corrupt_fingerprint(value: Variant, fingerprint: String) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key: Variant in value: dictionary[key] = corrupt_fingerprint(value[key], fingerprint)
		return dictionary
	if value is Array:
		var array: Array = []
		for item: Variant in value: array.append(corrupt_fingerprint(item, fingerprint))
		return array
	if value is String and value == fingerprint: return "0".repeat(64)
	return value

func raw_rotation_difference(left: Dictionary, right: Dictionary) -> Dictionary:
	var shared_bones: int = 0
	var maximum_angle: float = 0.0
	for bone: int in left:
		if not right.has(bone): continue
		var left_rotation: Quaternion = (left[bone] as Dictionary).get("rotation", Quaternion.IDENTITY)
		var right_rotation: Quaternion = (right[bone] as Dictionary).get("rotation", Quaternion.IDENTITY)
		# atan2 avoids acos(dot) cancellation for the identical frozen poses.
		var rotation_delta: Quaternion = left_rotation.normalized().inverse() * right_rotation.normalized()
		var angle: float = 2.0 * atan2(Vector3(rotation_delta.x, rotation_delta.y, rotation_delta.z).length(), absf(rotation_delta.w))
		maximum_angle = maxf(maximum_angle, angle)
		shared_bones += 1
	return {"shared_bones": shared_bones, "maximum_angle_rad": maximum_angle}

func run() -> void:
	npc = main.npcs["ren"]
	support = npc.model.find_child("CharacterGarmentSupport", true, false)
	skeleton = npc.model.find_child("Skeleton3D", true, false) as Skeleton3D
	if support == null or skeleton == null or not support.has_method("refresh_steady_proof"):
		for missing_case: int in CASE_NAMES.size(): check_case(missing_case, false, {"reason": "production steady guard/callback interface absent"})
		return
	var isolated: String = SaveDB.directory
	if isolated == "user://" or isolated.is_empty():
		for isolated_case: int in CASE_NAMES.size(): check_case(isolated_case, false, {"reason": "isolated HARUMACHI_SAVE_DIR or --test-db required for certificate fixture"})
		return
	# Explicit verification below must not conceal an invalidated startup proof.
	var startup_performance: Dictionary = support.call("performance")
	var saved: Dictionary = {"position": npc.global_position, "home": npc.home, "process": npc.is_processing(), "physics_process": npc.is_physics_processing(), "yaw": npc._yaw, "clip": npc.anim.ap.current_animation, "time": npc.anim.ap.current_animation_position, "speed": npc.anim.ap.speed_scale, "state": npc.anim._state, "oneshot": npc.anim._oneshot, "idle": npc.anim.idle_clip, "region": main.world.region, "in_room": main.in_room, "room_kind": main.room_kind, "player_in_room": GameState.player_in_room, "enabled": support.get("enabled"), "proof_path": support.get("steady_proof_path"), "seated_present": npc.has_meta("resident_seated"), "seated": npc.get_meta("resident_seated", false)}
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	npc.set_process(false)
	npc.set_physics_process(false)
	npc.set_home(false)
	npc.global_position = Vector3(-8, .010, -10)
	npc.set_yaw(0)
	npc.set_meta("resident_seated", false)
	npc.anim.idle_clip = "idle"
	support.set("enabled", true)
	support.call("refresh_steady_proof")
	for safe_case: int in 3:
		var clip: String = ["idle", "walk", "run"][safe_case]
		configure(clip)
		seed_local_weights()
		var before: Dictionary = support.call("performance")
		var measured: Dictionary = await fresh_callback()
		var zero: Dictionary = weights_are_zero()
		check_case(safe_case, fast_result(before, measured) and bool(zero.all_zero) and (safe_case != 0 or bool(startup_performance.get("steady_proof_match", false))), {"performance": measured, "weights": zero, "startup_performance": startup_performance if safe_case == 0 else {}})
	# A real controller transition starts both AP and Natural blending. Freeze
	# its clock only after starting, so this rejection cannot expire while waiting.
	configure("idle")
	await fresh_callback()
	npc.anim._go("walk", 1.0)
	npc.anim.ap.speed_scale = 0
	clear_pose_cache()
	var transition_before: Dictionary = support.call("performance")
	var transition_after: Dictionary = await fresh_callback()
	check_case(3, fallback_result(transition_before, transition_after, "transition"), {"performance": transition_after})
	# Keep a real pending one-shot while bringing AP/state to idle. This tests
	# the oneshot guard independently of an already-excluded gesture clip name.
	npc.anim.play_once("wave", 1.0)
	npc.anim._go("idle", 1.0)
	npc.anim.ap.speed_scale = 0
	var natural: Node = skeleton.get_node_or_null("NaturalLocomotionPose")
	if natural != null: natural.call("finish_transition")
	clear_pose_cache()
	var oneshot_before: Dictionary = support.call("performance")
	var oneshot_after: Dictionary = await fresh_callback()
	check_case(4, npc.anim.busy() and fallback_result(oneshot_before, oneshot_after, "non-steady controller state"), {"performance": oneshot_after, "oneshot": npc.anim._oneshot})
	configure("idle")
	npc.set_meta("resident_seated", true)
	var seated_before: Dictionary = support.call("performance")
	var seated_after: Dictionary = await fresh_callback()
	check_case(5, fallback_result(seated_before, seated_after, "seated"), {"performance": seated_after})
	npc.set_meta("resident_seated", false)
	configure("idle")
	var extra := UntrustedModifier.new()
	extra.name = "UntrustedSteadyGuardModifier"
	extra.active = true
	extra.influence = 1.0
	skeleton.add_child(extra)
	var modifier_before: Dictionary = support.call("performance")
	var modifier_after: Dictionary = await fresh_callback()
	check_case(6, fallback_result(modifier_before, modifier_after, "additional pose modifier"), {"performance": modifier_after})
	skeleton.remove_child(extra)
	extra.free()
	configure("idle")
	var original_certificate: String = FileAccess.get_file_as_string(str(saved.proof_path))
	var original_document: Variant = JSON.parse_string(original_certificate)
	var proof_before: Dictionary = support.call("performance")
	var fingerprint: String = str(proof_before.get("steady_model_fingerprint", ""))
	var bad_document: Variant = corrupt_fingerprint(original_document, fingerprint)
	var wrong_path: String = isolated.path_join("garment-wrong-proof-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var wrong_file: FileAccess = FileAccess.open(wrong_path, FileAccess.WRITE)
	var valid_wrong_fixture: bool = wrong_file != null and fingerprint.length() == 64 and JSON.stringify(bad_document) != JSON.stringify(original_document)
	if wrong_file != null:
		wrong_file.store_string(JSON.stringify(bad_document))
		wrong_file.close()
		support.set("steady_proof_path", wrong_path)
		support.call("refresh_steady_proof")
		clear_pose_cache()
	var proof_after: Dictionary = await fresh_callback()
	check_case(7, valid_wrong_fixture and fallback_result(proof_before, proof_after, "unverified model content"), {"performance": proof_after, "wrong_fixture_created": valid_wrong_fixture})
	support.set("steady_proof_path", saved.proof_path)
	support.call("refresh_steady_proof")
	if FileAccess.file_exists(wrong_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(wrong_path))
	configure("idle")
	seed_local_weights()
	var restore_before: Dictionary = support.call("performance")
	var restore_after: Dictionary = await fresh_callback()
	var restored_weights: Dictionary = weights_are_zero()
	check_case(8, fast_result(restore_before, restore_after) and bool(restored_weights.all_zero), {"performance": restore_after, "weights": restored_weights})
	var source_mesh: MeshInstance3D = support.get("mesh")
	configure("idle")
	await fresh_callback()
	var mesh_carrier_original: Transform3D = source_mesh.transform
	var mesh_carrier_before: Dictionary = support.call("performance")
	source_mesh.position += Vector3(.002, 0, 0)
	clear_pose_cache()
	var mesh_carrier_after: Dictionary = await fresh_callback()
	check_case(9, fallback_result(mesh_carrier_before, mesh_carrier_after, "asset carrier transform changed"), {"performance": mesh_carrier_after, "actual_local_translation_delta_m": (source_mesh.transform.origin - mesh_carrier_original.origin).length()})
	source_mesh.transform = mesh_carrier_original
	support.call("refresh_steady_proof")
	configure("idle")
	await fresh_callback()
	var skeleton_carrier_original: Transform3D = skeleton.transform
	var skeleton_carrier_before: Dictionary = support.call("performance")
	skeleton.position += Vector3(.002, 0, 0)
	clear_pose_cache()
	var skeleton_carrier_after: Dictionary = await fresh_callback()
	check_case(10, fallback_result(skeleton_carrier_before, skeleton_carrier_after, "asset carrier transform changed"), {"performance": skeleton_carrier_after, "actual_local_translation_delta_m": (skeleton.transform.origin - skeleton_carrier_original.origin).length()})
	skeleton.transform = skeleton_carrier_original
	support.call("refresh_steady_proof")
	configure("idle")
	await fresh_callback()
	# Editing an inactive covered clip must also invalidate the startup identity.
	var walk_resource: Animation = npc.anim.ap.get_animation("walk")
	var original_loop_mode: Animation.LoopMode = walk_resource.loop_mode
	var animation_before: Dictionary = support.call("performance")
	walk_resource.loop_mode = Animation.LOOP_NONE if original_loop_mode != Animation.LOOP_NONE else Animation.LOOP_LINEAR
	clear_pose_cache()
	var animation_after: Dictionary = await fresh_callback()
	check_case(11, fallback_result(animation_before, animation_after, "certified resource changed"), {"performance": animation_after, "active_clip": npc.anim.ap.current_animation, "modified_clip": "walk", "loop_mode_changed": walk_resource.loop_mode != original_loop_mode})
	walk_resource.loop_mode = original_loop_mode
	support.call("refresh_steady_proof")
	configure("idle")
	await fresh_callback()
	var source_skin: Skin = source_mesh.skin
	var original_bind: Transform3D = source_skin.get_bind_pose(0)
	var modified_bind: Transform3D = original_bind
	modified_bind.origin.x += .0001
	var skin_before: Dictionary = support.call("performance")
	source_skin.set_bind_pose(0, modified_bind)
	clear_pose_cache()
	var skin_after: Dictionary = await fresh_callback()
	check_case(12, fallback_result(skin_before, skin_after, "certified resource changed"), {"performance": skin_after, "bind_origin_delta_m": (source_skin.get_bind_pose(0).origin - original_bind.origin).length()})
	source_skin.set_bind_pose(0, original_bind)
	support.call("refresh_steady_proof")
	configure("idle")
	await fresh_callback()
	var mesh_resource_before: Dictionary = support.call("performance")
	# This explicitly tests the resource's notification contract; no claim is
	# made that an arbitrary GPU buffer edit emits a changed notification.
	source_mesh.mesh.emit_changed()
	clear_pose_cache()
	var mesh_resource_after: Dictionary = await fresh_callback()
	check_case(13, fallback_result(mesh_resource_before, mesh_resource_after, "certified resource changed"), {"performance": mesh_resource_after, "scope": "real same-resource changed signal; geometry bytes left intact"})
	support.call("refresh_steady_proof")
	configure("idle")
	await fresh_callback()
	var rest_bone: int = LivingPose.bone(skeleton, "head")
	var original_rest: Transform3D = skeleton.get_bone_rest(rest_bone)
	var modified_rest: Transform3D = original_rest
	modified_rest.origin.x += .0001
	var rest_before: Dictionary = support.call("performance")
	skeleton.set_bone_rest(rest_bone, modified_rest)
	clear_pose_cache()
	var rest_after: Dictionary = await fresh_callback()
	check_case(14, fallback_result(rest_before, rest_after, "certified resource changed"), {"performance": rest_after, "bone": skeleton.get_bone_name(rest_bone), "rest_origin_delta_m": (skeleton.get_bone_rest(rest_bone).origin - original_rest.origin).length()})
	skeleton.set_bone_rest(rest_bone, original_rest)
	# Force restoration through the real skeleton before explicitly hashing it;
	# a deferred rest_updated must not invalidate a freshly restored proof later.
	skeleton.get_bone_global_rest(rest_bone)
	clear_pose_cache()
	await fresh_callback()
	support.call("refresh_steady_proof")
	configure("idle")
	seed_local_weights()
	var identity_restore_before: Dictionary = support.call("performance")
	var identity_restore_after: Dictionary = await fresh_callback()
	var identity_restored_weights: Dictionary = weights_are_zero()
	check_case(15, fast_result(identity_restore_before, identity_restore_after) and bool(identity_restored_weights.all_zero), {"performance": identity_restore_after, "weights": identity_restored_weights})
	# The continuous reviewer only reads final bones/morphs. Attaching it must
	# preserve the same certified branch that runs without QA instrumentation.
	var observer: SkeletonModifier3D = load("res://scripts/tools/character_continuous_probe.gd").new()
	observer.name = "CertifiedReadOnlyObserverRegression"
	skeleton.add_child(observer)
	observer.call("prepare", npc.model, npc, npc.anim.ap, .010)
	observer.call("begin")
	configure("walk")
	seed_local_weights()
	var observer_before: Dictionary = support.call("performance")
	var observer_after: Dictionary = await fresh_callback()
	var observer_weights: Dictionary = weights_are_zero()
	check_case(16, fast_result(observer_before, observer_after) and bool(observer_weights.all_zero) and not (observer.get("rows") as Array).is_empty(), {"performance": observer_after, "weights": observer_weights, "observer_rows": (observer.get("rows") as Array).size()})
	skeleton.remove_child(observer)
	observer.free()
	# Replacing an inactive covered resource changes the content identity even
	# though the old Animation object itself never emits Resource.changed.
	# Mutate only the isolated instance's library and always restore the original.
	configure("idle")
	var replacement_before: Dictionary = support.call("performance")
	var replacement_baseline: Dictionary = await fresh_callback()
	var replacement_original: Animation = npc.anim.ap.get_animation("walk")
	var replacement_original_loop: Animation.LoopMode = replacement_original.loop_mode
	var replacement_library_name: StringName = npc.anim.ap.find_animation_library(replacement_original)
	var replacement_library: AnimationLibrary = npc.anim.ap.get_animation_library(replacement_library_name)
	var replacement_clone: Animation = replacement_original.duplicate(true) as Animation
	replacement_clone.loop_mode = Animation.LOOP_NONE if replacement_original_loop != Animation.LOOP_NONE else Animation.LOOP_LINEAR
	var replacement_events := LibrarySignalRecorder.new()
	var replacement_list_callback := Callable(replacement_events, "on_list_changed")
	var replacement_libraries_callback := Callable(replacement_events, "on_libraries_updated")
	var replacement_original_callback := Callable(replacement_events, "on_original_changed")
	npc.anim.ap.animation_list_changed.connect(replacement_list_callback)
	npc.anim.ap.animation_libraries_updated.connect(replacement_libraries_callback)
	replacement_original.changed.connect(replacement_original_callback)
	replacement_library.remove_animation(&"walk")
	var replacement_add_error: Error = replacement_library.add_animation(&"walk", replacement_clone)
	clear_pose_cache()
	var replacement_measured: Dictionary = await fresh_callback()
	var replacement_fixture_valid: bool = replacement_add_error == OK and npc.anim.ap.get_animation("walk") == replacement_clone and replacement_clone != replacement_original and replacement_clone.loop_mode != replacement_original_loop and replacement_original.loop_mode == replacement_original_loop and replacement_events.list_changes > 0 and replacement_events.original_animation_changes == 0
	var replacement_invalidated: bool = bool(replacement_measured.get("fresh", false)) and not bool(replacement_measured.get("steady_proof_match", true)) and int(replacement_measured.get("steady_fast_updates", -1)) == int(replacement_baseline.get("steady_fast_updates", -2)) and str(replacement_measured.get("last_branch", "")) in ["full", "pose_cache"] and not str(replacement_measured.get("last_steady_reason", "")).is_empty()
	npc.anim.ap.animation_list_changed.disconnect(replacement_list_callback)
	npc.anim.ap.animation_libraries_updated.disconnect(replacement_libraries_callback)
	replacement_original.changed.disconnect(replacement_original_callback)
	replacement_library.remove_animation(&"walk")
	var replacement_restore_error: Error = replacement_library.add_animation(&"walk", replacement_original)
	configure("idle")
	var replacement_refresh_ok: bool = bool(support.call("refresh_steady_proof"))
	seed_local_weights()
	var replacement_restore_before: Dictionary = support.call("performance")
	var replacement_restore_after: Dictionary = await fresh_callback()
	var replacement_restore_weights: Dictionary = weights_are_zero()
	check_case(17, fast_result(replacement_before, replacement_baseline) and replacement_fixture_valid and replacement_invalidated and replacement_restore_error == OK and replacement_refresh_ok and fast_result(replacement_restore_before, replacement_restore_after) and bool(replacement_restore_weights.all_zero), {"baseline": replacement_baseline, "changed": replacement_measured, "restored": replacement_restore_after, "restored_weights": replacement_restore_weights, "fixture_valid": replacement_fixture_valid, "add_error": replacement_add_error, "restore_error": replacement_restore_error, "original_animation_id": replacement_original.get_instance_id(), "replacement_animation_id": replacement_clone.get_instance_id(), "animation_list_changed_signals": replacement_events.list_changes, "animation_libraries_updated_signals": replacement_events.library_changes, "original_resource_changed_signals": replacement_events.original_animation_changes, "active_clip": npc.anim.ap.current_animation, "modified_clip": "walk", "library": str(replacement_library_name)})
	# Configure only the two stable baselines. After the real place/controller
	# calls below there is no seek, advance, finish_transition or direct reset.
	# Frozen AP speed keeps the actual .22s blend pending while final callbacks
	# prove which raw input the Natural modifier truly received.
	if natural == null:
		check_case(18, false, {"reason": "Natural raw-pose/real-placement fixture unavailable"})
	else:
		configure("idle", 0.0)
		var placement_idle_before: Dictionary = support.call("performance")
		var placement_idle_after: Dictionary = await fresh_callback()
		var placement_idle_raw: Dictionary = (natural.get("_last_raw_pose") as Dictionary).duplicate(true)
		configure("walk", .375)
		var placement_walk_before: Dictionary = support.call("performance")
		var placement_walk_after: Dictionary = await fresh_callback()
		var placement_walk_raw: Dictionary = (natural.get("_last_raw_pose") as Dictionary).duplicate(true)
		var placement_baseline_separation: Dictionary = raw_rotation_difference(placement_idle_raw, placement_walk_raw)
		var placement_before: Dictionary = support.call("performance")
		var placement_frame: int = Engine.get_process_frames()
		npc.place(npc.global_position, rad_to_deg(npc._yaw))
		var placement_delta_cleared: bool = (natural.get("_last_delta") as Dictionary).is_empty()
		npc.anim.update(0.0)
		npc.anim.ap.speed_scale = 0.0
		var placement_calls_same_frame: bool = Engine.get_process_frames() == placement_frame
		var placement_duration_after_go: float = float(natural.get("_transition_duration"))
		clear_pose_cache()
		var placement_after: Dictionary = await fresh_callback()
		var placement_blending_raw: Dictionary = (natural.get("_last_raw_pose") as Dictionary).duplicate(true)
		var placement_from_walk: Dictionary = raw_rotation_difference(placement_walk_raw, placement_blending_raw)
		var placement_from_idle: Dictionary = raw_rotation_difference(placement_idle_raw, placement_blending_raw)
		var placement_has_raw_blend: bool = placement_walk_raw.size() > 0 and int(placement_baseline_separation.shared_bones) == placement_walk_raw.size() and int(placement_from_walk.shared_bones) == placement_walk_raw.size() and int(placement_from_idle.shared_bones) == placement_walk_raw.size() and float(placement_baseline_separation.maximum_angle_rad) > .01 and float(placement_from_walk.maximum_angle_rad) < .001 and float(placement_from_idle.maximum_angle_rad) > .01
		var placement_fixture_valid: bool = placement_calls_same_frame and placement_delta_cleared and placement_has_raw_blend and npc.anim._state == "idle" and npc.anim.ap.current_animation == "idle" and npc.anim.ap.is_playing() and npc.anim.ap.speed_scale == 0.0
		check_case(18, fast_result(placement_idle_before, placement_idle_after) and fast_result(placement_walk_before, placement_walk_after) and placement_fixture_valid and fallback_result(placement_before, placement_after, "transition"), {"fixture_valid": placement_fixture_valid, "actual_pending_blend_observed": placement_has_raw_blend, "calls_in_one_process_frame": placement_calls_same_frame, "contact_reset_cleared_delta": placement_delta_cleared, "stable_idle": placement_idle_after, "stable_walk": placement_walk_after, "after_place_and_controller_idle": placement_after, "raw_idle_walk_separation": placement_baseline_separation, "actual_raw_distance_from_walk": placement_from_walk, "actual_raw_distance_from_idle": placement_from_idle, "natural_duration_immediately_after_go": placement_duration_after_go, "natural_duration_after_callback": natural.get("_transition_duration"), "natural_elapsed_after_callback": natural.get("_transition_elapsed"), "active_clip": npc.anim.ap.current_animation, "clip_time": npc.anim.ap.current_animation_position, "speed_scale": npc.anim.ap.speed_scale, "post_transition_seek_or_advance": false})
	# Restore the isolated fixture even after failed checks; no product settings
	# or save files are changed by this regression module.
	support.set("enabled", saved.enabled)
	clear_pose_cache()
	npc.anim._state = str(saved.state)
	npc.anim._oneshot = str(saved.oneshot)
	npc.anim.idle_clip = str(saved.idle)
	npc.anim.ap.play(str(saved.clip) if str(saved.clip) != "" else "idle", 0)
	npc.anim.ap.seek(float(saved.time), true)
	npc.anim.ap.speed_scale = float(saved.speed)
	npc.global_position = saved.position
	npc.set_yaw(float(saved.yaw))
	npc.set_home(bool(saved.home))
	npc.set_process(bool(saved.process))
	npc.set_physics_process(bool(saved.physics_process))
	if bool(saved.seated_present): npc.set_meta("resident_seated", saved.seated)
	else: npc.remove_meta("resident_seated")
	main.in_room = saved.in_room
	main.room_kind = saved.room_kind
	GameState.player_in_room = saved.player_in_room
	main.world.set_region(str(saved.region))
	main.world.set_indoor_look(bool(saved.in_room))
