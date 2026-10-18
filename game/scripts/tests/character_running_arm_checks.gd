extends RefCounted
## Measure the user's running-arm feedback at the end of the real modifier chain.
## Limits describe visible motion; no production arm solver or helper is called here.
const IDS: Array[String] = ["sora", "ren", "haru", "mio", "aoi", "tanaka", "kazuko"]
const PRESERVED: Array[String] = ["hips", "chest", "head", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]
const UPPER_SPAN_LIMIT: Dictionary = {"sora": 50.0, "ren": 46.0, "haru": 53.0, "mio": 50.0, "aoi": 54.0, "tanaka": 47.0, "kazuko": 50.0}
const WRIST_SHOULDER_LIMIT: Dictionary = {"sora": -.10, "ren": -.10, "haru": -.16, "mio": -.10, "aoi": -.08, "tanaka": -.10, "kazuko": -.10}
const MIN_ELBOW_SPAN := 6.0
const MAX_ELBOW_SPAN := 16.0
const PHASE_STEPS := 32
const FIRST_CORRECTION_FRACTION := .25
const FIRST_ROTATION_NUMERIC_GUARD := .5
const INTERPOLATION_ARM_FRACTION := .01
const INTERPOLATION_ANGLE_LIMIT := 2.0
var t: Node
var main: Node

class BeforeNaturalArmProbe:
	extends SkeletonModifier3D
	var model: Node3D
	var serial := 0
	var frame := -1
	var relative_points: Dictionary = {}
	var local_rotations: Dictionary = {}

	func _process_modification() -> void:
		var skeleton: Skeleton3D = get_skeleton()
		relative_points.clear()
		local_rotations.clear()
		for side: String in ["L", "R"]:
			var shoulder: int = LivingPose.bone(skeleton, "upper." + side)
			var shoulder_point: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(shoulder).origin)
			for label: String in ["upper." + side, "fore." + side]:
				local_rotations[label] = skeleton.get_bone_pose_rotation(LivingPose.bone(skeleton, label))
			for point_label: String in ["fore." + side, "hand." + side]:
				var point: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(LivingPose.bone(skeleton, point_label)).origin)
				relative_points[point_label] = model.global_basis.inverse() * (point - shoulder_point)
		serial += 1
		frame = Engine.get_process_frames()

class TransitionFinalArmProbe:
	extends SkeletonModifier3D
	var model: Node3D
	var animation: AnimationPlayer
	var before: BeforeNaturalArmProbe
	var natural: Node
	var request_id := 0
	var request_frame := -1
	var request_raw_serial := -1
	var rows: Array[Dictionary] = []
	var result: Dictionary = {}

	func request() -> int:
		request_id += 1
		request_frame = Engine.get_process_frames()
		request_raw_serial = before.serial
		rows.clear()
		return request_id

	func _process_modification() -> void:
		var skeleton: Skeleton3D = get_skeleton()
		var frame: int = Engine.get_process_frames()
		var deltas: Dictionary = {}
		var rotations: Dictionary = {}
		var final_points: Dictionary = {}
		var final_rotations: Dictionary = {}
		var finite := true
		for side: String in ["L", "R"]:
			var shoulder: int = LivingPose.bone(skeleton, "upper." + side)
			var shoulder_point: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(shoulder).origin)
			for label: String in ["upper." + side, "fore." + side]:
				var source_rotation: Quaternion = before.local_rotations.get(label, Quaternion.IDENTITY)
				var final_rotation: Quaternion = skeleton.get_bone_pose_rotation(LivingPose.bone(skeleton, label))
				final_rotations[label] = final_rotation
				var rotation_delta: Quaternion = source_rotation.inverse() * final_rotation
				rotations[label] = rotation_delta.normalized()
				finite = finite and is_finite(rotation_delta.x) and is_finite(rotation_delta.y) and is_finite(rotation_delta.z) and is_finite(rotation_delta.w)
			for point_label: String in ["fore." + side, "hand." + side]:
				var point: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(LivingPose.bone(skeleton, point_label)).origin)
				var source: Vector3 = before.relative_points.get(point_label, Vector3.INF)
				var final_relative: Vector3 = model.global_basis.inverse() * (point - shoulder_point)
				final_points[point_label] = final_relative
				var delta: Vector3 = final_relative - source
				deltas[point_label] = delta
				finite = finite and delta.is_finite()
		var fresh: bool = before.frame == frame and before.serial > request_raw_serial and frame > request_frame and finite and deltas.size() == 4 and rotations.size() == 4
		var natural_diagnostic: Dictionary = {"elapsed_s": float(natural.get("_transition_elapsed")), "duration_s": float(natural.get("_transition_duration")), "transition_clip": str(natural.get("_transition_clip"))} if natural != null else {}
		result = {"request_id": request_id, "request_frame": request_frame, "frame": frame, "raw_frame": before.frame, "raw_serial": before.serial, "fresh": fresh, "clip": animation.current_animation, "clip_time": animation.current_animation_position, "speed_scale": animation.speed_scale, "wall_usec": Time.get_ticks_usec(), "delta_s": get_process_delta_time(), "points": deltas, "rotations": rotations, "raw_relative_points": before.relative_points.duplicate(true), "final_relative_points": final_points, "raw_local_rotations": before.local_rotations.duplicate(true), "final_local_rotations": final_rotations, "natural_diagnostic_only": natural_diagnostic}
		if not fresh: return
		# Keep the last callback of each rendered frame, just as the final pose
		# probe does. Forced and normal AP callbacks can share one process frame.
		if not rows.is_empty() and int(rows[-1].frame) == frame:
			rows[-1] = result.duplicate(true)
		else:
			rows.append(result.duplicate(true))

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, passed: bool, detail: Dictionary) -> void:
	t.check("CHARACTER_RUNNING_ARMS", label, passed, JSON.stringify(detail))

func has_property(source: Object, label: String) -> bool:
	for property: Dictionary in source.get_property_list():
		if str(property.name) == label: return true
	return false

func position(pose: Dictionary, skeleton: Skeleton3D, label: String) -> Vector3:
	var index: int = LivingPose.bone(skeleton, label)
	if index < 0 or index >= (pose.bones as Array).size(): return Vector3.INF
	var value: Array = pose.bones[index].position
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func basis(pose: Dictionary, skeleton: Skeleton3D, label: String) -> Basis:
	var index: int = LivingPose.bone(skeleton, label)
	if index < 0 or index >= (pose.bones as Array).size(): return Basis()
	var columns: Array = pose.bones[index].basis
	var first: Array = columns[0]
	var second: Array = columns[1]
	var third: Array = columns[2]
	return Basis(Vector3(float(first[0]), float(first[1]), float(first[2])), Vector3(float(second[0]), float(second[1]), float(second[2])), Vector3(float(third[0]), float(third[1]), float(third[2])))

func finite_bones(pose: Dictionary, expected_count: int) -> bool:
	var bones: Array = pose.get("bones", [])
	if bones.size() != expected_count: return false
	for bone: Dictionary in bones:
		var location: Array = bone.get("position", [])
		var axes: Array = bone.get("basis", [])
		if location.size() != 3 or axes.size() != 3: return false
		for coordinate: float in location:
			if not is_finite(coordinate): return false
		for axis: Array in axes:
			if axis.size() != 3: return false
			for component: float in axis:
				if not is_finite(component): return false
	return true

func sample(controller: CharAnim, phase: float, probe: SkeletonModifier3D, expected_count: int) -> Dictionary:
	controller.ap.play("run", 0.0)
	controller.ap.speed_scale = 0.0
	var animation: Animation = controller.ap.get_animation("run")
	var expected_time: float = fposmod(animation.length * phase, animation.length)
	controller.ap.seek(expected_time, true)
	controller.ap.advance(0.0)
	var natural: Node = probe.get_skeleton().get_node_or_null("NaturalLocomotionPose")
	if natural != null and natural.has_method("finish_transition"): natural.call("finish_transition")
	# Headless process waits alone can observe a prior restored skeleton. Require
	# the existing last modifier to acknowledge this exact request on a later frame.
	for settle_frame: int in 3: await t.get_tree().process_frame
	var requested: int = int(probe.call("request", "run", expected_time))
	var measured: Dictionary = {}
	for capture_frame: int in 8:
		await t.get_tree().process_frame
		if int(probe.get("completed_request")) != requested: continue
		measured = (probe.get("result") as Dictionary).duplicate(true)
		if int(measured.get("request_id", -1)) == requested: break
	var fresh: bool = int(measured.get("request_id", -1)) == requested and str(measured.get("clip", "")) == "run" and absf(float(measured.get("clip_time", INF)) - expected_time) < .0001 and int(measured.get("applied_frame", -1)) > int(measured.get("request_frame", -1)) and bool(measured.get("measure_bones", false)) and finite_bones(measured, expected_count)
	measured["fresh"] = fresh
	if fresh:
		print("RUNNING_ARM_FINAL_SAMPLE ", JSON.stringify({"skeleton": str(probe.get_skeleton().get_path()), "request_id": requested, "phase": phase, "clip_time": measured.clip_time, "request_frame": measured.request_frame, "applied_frame": measured.applied_frame, "bone_count": expected_count, "bone_pose_hash": measured.bone_pose_hash}))
	else:
		print("RUNNING_ARM_SAMPLE_TIMEOUT ", JSON.stringify({"requested_id": requested, "phase": phase, "expected_time": expected_time, "completed_request": probe.get("completed_request"), "result": measured}))
	return measured

func correlation(first: Array, second: Array) -> float:
	if first.size() != second.size() or first.size() < 2: return 1.0
	var first_mean := 0.0
	var second_mean := 0.0
	for index: int in first.size():
		first_mean += float(first[index]) / first.size()
		second_mean += float(second[index]) / second.size()
	var covariance := 0.0
	var first_variance := 0.0
	var second_variance := 0.0
	for sample_index: int in first.size():
		var a: float = float(first[sample_index]) - first_mean
		var b: float = float(second[sample_index]) - second_mean
		covariance += a * b
		first_variance += a * a
		second_variance += b * b
	return covariance / sqrt(first_variance * second_variance) if first_variance * second_variance > .000000001 else 1.0

func new_statistics() -> Dictionary:
	return {"pitch_min": INF, "pitch_max": -INF, "wrist_above_shoulder_max": -INF, "flex_min": INF, "flex_max": -INF, "length_error_max": 0.0, "hand_forward": [], "foot_forward": []}

func accumulate(stats: Dictionary, pose: Dictionary, skeleton: Skeleton3D, model: Node3D, side: String, include_correlation: bool) -> void:
	var shoulder: Vector3 = position(pose, skeleton, "upper." + side)
	var elbow: Vector3 = position(pose, skeleton, "fore." + side)
	var wrist: Vector3 = position(pose, skeleton, "hand." + side)
	var hips: Vector3 = position(pose, skeleton, "hips")
	var foot: Vector3 = position(pose, skeleton, "foot." + side)
	var upper_vector: Vector3 = model.global_basis.inverse() * (elbow - shoulder)
	var wrist_vector: Vector3 = model.global_basis.inverse() * (wrist - shoulder)
	var pitch: float = rad_to_deg(atan2(upper_vector.z, -upper_vector.y))
	var elbow_flex: float = 180.0 - rad_to_deg((shoulder - elbow).angle_to(wrist - elbow))
	stats.pitch_min = minf(float(stats.pitch_min), pitch)
	stats.pitch_max = maxf(float(stats.pitch_max), pitch)
	stats.wrist_above_shoulder_max = maxf(float(stats.wrist_above_shoulder_max), wrist_vector.y)
	stats.flex_min = minf(float(stats.flex_min), elbow_flex)
	stats.flex_max = maxf(float(stats.flex_max), elbow_flex)
	for pair: Array in [["upper." + side, "fore." + side], ["fore." + side, "hand." + side]]:
		var first: int = LivingPose.bone(skeleton, str(pair[0]))
		var second: int = LivingPose.bone(skeleton, str(pair[1]))
		var rest_length: float = (skeleton.global_basis * (skeleton.get_bone_global_rest(second).origin - skeleton.get_bone_global_rest(first).origin)).length()
		var actual_length: float = position(pose, skeleton, str(pair[0])).distance_to(position(pose, skeleton, str(pair[1])))
		stats.length_error_max = maxf(float(stats.length_error_max), absf(actual_length - rest_length))
	if include_correlation:
		(stats.hand_forward as Array).append((model.global_basis.inverse() * (wrist - hips)).z)
		(stats.foot_forward as Array).append((model.global_basis.inverse() * (foot - hips)).z)

func preserved_difference(first: Dictionary, second: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	var position_error := 0.0
	var angle_error := 0.0
	for label: String in PRESERVED:
		position_error = maxf(position_error, position(first, skeleton, label).distance_to(position(second, skeleton, label)))
		var first_rotation: Quaternion = basis(first, skeleton, label).orthonormalized().get_rotation_quaternion()
		var second_rotation: Quaternion = basis(second, skeleton, label).orthonormalized().get_rotation_quaternion()
		angle_error = maxf(angle_error, rad_to_deg(first_rotation.angle_to(second_rotation)))
	return {"position_m": position_error, "rotation_deg": angle_error}

func global_transform_from_sample(pose: Dictionary, index: int) -> Transform3D:
	var bone: Dictionary = pose.bones[index]
	var location: Array = bone.position
	var axes: Array = bone.basis
	var x: Array = axes[0]
	var y: Array = axes[1]
	var z: Array = axes[2]
	return Transform3D(Basis(Vector3(float(x[0]), float(x[1]), float(x[2])), Vector3(float(y[0]), float(y[1]), float(y[2])), Vector3(float(z[0]), float(z[1]), float(z[2]))), Vector3(float(location[0]), float(location[1]), float(location[2])))

func hand_local_difference(first: Dictionary, second: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	# Reconstruct child-local transforms from independently captured world poses.
	# Every descendant of each hand is included, covering Thumb/Finger names in
	# both the procedural rig and Mixamo imports without a name-only whitelist.
	var hands: Array[int] = [LivingPose.bone(skeleton, "hand.L"), LivingPose.bone(skeleton, "hand.R")]
	var position_error := 0.0
	var rotation_error := 0.0
	var scale_error := 0.0
	var counted := 0
	for index: int in skeleton.get_bone_count():
		var ancestor: int = index
		var belongs := false
		while ancestor >= 0:
			if ancestor in hands:
				belongs = true
				break
			ancestor = skeleton.get_bone_parent(ancestor)
		if not belongs: continue
		var parent: int = skeleton.get_bone_parent(index)
		if parent < 0: continue
		var first_local: Transform3D = global_transform_from_sample(first, parent).affine_inverse() * global_transform_from_sample(first, index)
		var second_local: Transform3D = global_transform_from_sample(second, parent).affine_inverse() * global_transform_from_sample(second, index)
		position_error = maxf(position_error, first_local.origin.distance_to(second_local.origin))
		rotation_error = maxf(rotation_error, rad_to_deg(first_local.basis.orthonormalized().get_rotation_quaternion().angle_to(second_local.basis.orthonormalized().get_rotation_quaternion())))
		scale_error = maxf(scale_error, first_local.basis.get_scale().distance_to(second_local.basis.get_scale()))
		counted += 1
	return {"position_m": position_error, "rotation_deg": rotation_error, "scale": scale_error, "hand_and_finger_bones": counted}

func fixture_options() -> Dictionary:
	var actors: Array[String] = IDS.duplicate()
	var transitions_only := false
	var fps := 120
	var valid := true
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--running-arm-transitions-only": transitions_only = true
		elif argument.begins_with("--running-arm-transition-actors="):
			actors.clear()
			for actor_part: String in argument.trim_prefix("--running-arm-transition-actors=").split(","):
				var actor_id: String = actor_part.strip_edges()
				if actor_id not in IDS:
					valid = false
				elif actor_id not in actors:
					actors.append(actor_id)
		elif argument.begins_with("--running-arm-transition-fps="):
			var requested_fps: String = argument.trim_prefix("--running-arm-transition-fps=")
			valid = valid and requested_fps.is_valid_int()
			fps = int(requested_fps)
			valid = valid and fps in [120, 240]
	return {"actors": actors, "transitions_only": transitions_only, "fps": fps, "valid": valid and not actors.is_empty()}

func json_trace_value(value: Variant) -> Variant:
	if value is Vector3:
		var vector: Vector3 = value
		return [vector.x, vector.y, vector.z]
	if value is Quaternion:
		var rotation: Quaternion = value
		return [rotation.x, rotation.y, rotation.z, rotation.w]
	if value is Dictionary:
		var source_dictionary: Dictionary = value
		var converted_dictionary: Dictionary = {}
		for key: Variant in source_dictionary:
			converted_dictionary[str(key)] = json_trace_value(source_dictionary[key])
		return converted_dictionary
	if value is Array:
		var source_array: Array = value
		var converted_array: Array = []
		for item: Variant in source_array: converted_array.append(json_trace_value(item))
		return converted_array
	return value

func run() -> void:
	var saved_max_fps: int = Engine.max_fps
	var options: Dictionary = fixture_options()
	if not bool(options.valid):
		check("running arm fixture requires known actors and a supported diagnostic frame rate", false, options)
		return
	for id: String in options.actors:
		var actor: Node3D = main.player if id == "sora" else main.npcs[id]
		var model: Node3D = actor.get("model") as Node3D
		var controller: CharAnim = actor.get("anim") as CharAnim
		var animation: AnimationPlayer = controller.ap
		var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
		var natural: Node = skeleton.get_node_or_null("NaturalLocomotionPose")
		var has_switch: bool = natural != null and has_property(natural, "running_arms_enabled")
		var saved: Dictionary = {"position": actor.global_position, "visible": actor.visible, "process": actor.is_processing(), "physics": actor.is_physics_processing(), "model_transform": model.transform, "clip": animation.current_animation, "time": animation.current_animation_position, "speed": animation.speed_scale, "state": controller._state, "oneshot": controller._oneshot, "idle": controller.idle_clip, "arms_enabled": bool(natural.get("running_arms_enabled")) if has_switch else false}
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.visible = true
		actor.global_position = Vector3(-8.0, 0.0, -10.0)
		model.rotation.x = 0.0
		if has_switch: natural.set("running_arms_enabled", true)
		var probe: SkeletonModifier3D = load("res://scripts/tools/character_qa_pose_probe.gd").new()
		probe.name = "RunningArmRegressionFinalProbe"
		skeleton.add_child(probe)
		probe.call("prepare", model)
		probe.set("measure_bones", true)
		if not bool(options.transitions_only): await actor_contract(id, model, skeleton, natural, has_switch, controller, probe)
		Engine.max_fps = int(options.fps)
		await transition_contracts(id, model, skeleton, natural, controller)
		Engine.max_fps = saved_max_fps
		if has_switch: natural.set("running_arms_enabled", bool(saved.arms_enabled))
		probe.queue_free()
		actor.global_position = saved.position
		model.transform = saved.model_transform
		animation.play(str(saved.clip), 0.0)
		animation.seek(float(saved.time), true)
		animation.speed_scale = float(saved.speed)
		controller._state = str(saved.state)
		controller._oneshot = str(saved.oneshot)
		controller.idle_clip = str(saved.idle)
		actor.visible = bool(saved.visible)
		actor.set_process(bool(saved.process))
		actor.set_physics_process(bool(saved.physics))
		if actor is Player: (actor as Player).reset_physics_interpolation()

func actor_contract(id: String, model: Node3D, skeleton: Skeleton3D, natural: Node, has_switch: bool, controller: CharAnim, probe: SkeletonModifier3D) -> void:
	var expected_count: int = 66 if id in ["sora", "mio"] else 54
	var statistics: Dictionary = {"L": new_statistics(), "R": new_statistics()}
	var fresh_samples := 0
	var baseline_samples := 0
	var preserve_position_max := 0.0
	var preserve_rotation_max := 0.0
	var hand_position_max := 0.0
	var hand_rotation_max := 0.0
	var hand_scale_max := 0.0
	var hand_bone_count := 0
	for index: int in range(PHASE_STEPS + 1):
		var phase: float = float(index) / PHASE_STEPS
		if has_switch: natural.set("running_arms_enabled", true)
		var actual: Dictionary = await sample(controller, phase, probe, expected_count)
		if has_switch: natural.set("running_arms_enabled", false)
		var baseline: Dictionary = await sample(controller, phase, probe, expected_count)
		if bool(baseline.get("fresh", false)): baseline_samples += 1
		if not bool(actual.get("fresh", false)): continue
		fresh_samples += 1
		for side: String in ["L", "R"]:
			accumulate(statistics[side], actual, skeleton, model, side, index < PHASE_STEPS)
		if bool(baseline.get("fresh", false)):
			var difference: Dictionary = preserved_difference(actual, baseline, skeleton)
			preserve_position_max = maxf(preserve_position_max, float(difference.position_m))
			preserve_rotation_max = maxf(preserve_rotation_max, float(difference.rotation_deg))
			var hand_difference: Dictionary = hand_local_difference(actual, baseline, skeleton)
			hand_position_max = maxf(hand_position_max, float(hand_difference.position_m))
			hand_rotation_max = maxf(hand_rotation_max, float(hand_difference.rotation_deg))
			hand_scale_max = maxf(hand_scale_max, float(hand_difference.scale))
			hand_bone_count = int(hand_difference.hand_and_finger_bones)
	if has_switch: natural.set("running_arms_enabled", true)
	var fresh: bool = fresh_samples == PHASE_STEPS + 1
	var left: Dictionary = statistics.L
	var right: Dictionary = statistics.R
	var left_span: float = float(left.pitch_max) - float(left.pitch_min)
	var right_span: float = float(right.pitch_max) - float(right.pitch_min)
	var left_flex_span: float = float(left.flex_max) - float(left.flex_min)
	var right_flex_span: float = float(right.flex_max) - float(right.flex_min)
	var left_opposition: float = correlation(left.hand_forward, left.foot_forward)
	var right_opposition: float = correlation(right.hand_forward, right.foot_forward)
	var coverage: Dictionary = {"actual_final_samples": fresh_samples, "baseline_final_samples": baseline_samples, "expected_each": PHASE_STEPS + 1, "expected_bones": expected_count}
	check(id + " running arm measurements use fresh complete final modifier poses", fresh and baseline_samples == PHASE_STEPS + 1, coverage)
	check(id + " running upper arms keep a compact role-specific forward and backward swing", fresh and left_span <= float(UPPER_SPAN_LIMIT[id]) and right_span <= float(UPPER_SPAN_LIMIT[id]), {"L_span_deg": left_span, "R_span_deg": right_span, "limit_deg": UPPER_SPAN_LIMIT[id], "coverage": coverage})
	check(id + " running wrists stay below their own shoulder peaks", fresh and float(left.wrist_above_shoulder_max) <= float(WRIST_SHOULDER_LIMIT[id]) and float(right.wrist_above_shoulder_max) <= float(WRIST_SHOULDER_LIMIT[id]), {"L_peak_m": left.wrist_above_shoulder_max, "R_peak_m": right.wrist_above_shoulder_max, "limit_m": WRIST_SHOULDER_LIMIT[id], "coverage": coverage})
	check(id + " running elbows change gently instead of holding a frozen right angle", fresh and minf(float(left.flex_min), float(right.flex_min)) >= 60.0 and maxf(float(left.flex_max), float(right.flex_max)) <= 110.0 and minf(left_flex_span, right_flex_span) >= MIN_ELBOW_SPAN and maxf(left_flex_span, right_flex_span) <= MAX_ELBOW_SPAN, {"L_min_deg": left.flex_min, "L_max_deg": left.flex_max, "R_min_deg": right.flex_min, "R_max_deg": right.flex_max, "L_span_deg": left_flex_span, "R_span_deg": right_flex_span, "span_limits_deg": [MIN_ELBOW_SPAN, MAX_ELBOW_SPAN], "coverage": coverage})
	check(id + " running arm correction preserves upper and forearm bone lengths", fresh and maxf(float(left.length_error_max), float(right.length_error_max)) < .001, {"max_length_error_m": maxf(float(left.length_error_max), float(right.length_error_max)), "limit_m": .001, "coverage": coverage})
	check(id + " running hands still oppose the same-side foot movement", fresh and left_opposition < -.65 and right_opposition < -.65, {"L_correlation": left_opposition, "R_correlation": right_opposition, "maximum": -.65, "coverage": coverage})
	var seam_error := 0.0
	var seam_fresh := 0
	for cycle: int in 2:
		var before: Dictionary = await sample(controller, .9999, probe, expected_count)
		var after: Dictionary = await sample(controller, .0001, probe, expected_count)
		if bool(before.get("fresh", false)): seam_fresh += 1
		if bool(after.get("fresh", false)): seam_fresh += 1
		if not bool(before.get("fresh", false)) or not bool(after.get("fresh", false)): continue
		for seam_label: String in ["upper.L", "fore.L", "hand.L", "upper.R", "fore.R", "hand.R"]:
			seam_error = maxf(seam_error, position(before, skeleton, seam_label).distance_to(position(after, skeleton, seam_label)))
	check(id + " running elbows and wrists close across two cycle boundaries", seam_fresh == 4 and seam_error < .004, {"fresh_final_samples": seam_fresh, "expected": 4, "max_position_error_m": seam_error, "limit_m": .004})
	check(id + " running arm changes preserve legs torso and local hand finger articulation", fresh and baseline_samples == PHASE_STEPS + 1 and preserve_position_max < .001 and preserve_rotation_max < .1 and hand_bone_count >= 4 and hand_position_max < .00005 and hand_rotation_max < .1 and hand_scale_max < .0001, {"arm_correction_switch_available": has_switch, "max_position_error_m": preserve_position_max, "max_rotation_error_deg": preserve_rotation_max, "limits": {"position_m": .001, "rotation_deg": .1}, "preserved_bones": PRESERVED, "local_hand_finger_trs": {"bones": hand_bone_count, "position_m": hand_position_max, "rotation_deg": hand_rotation_max, "scale": hand_scale_max, "limits": {"position_m": .00005, "rotation_deg": .1, "scale": .0001}}, "coverage": coverage})

func live_settle(controller: CharAnim, probe: TransitionFinalArmProbe, clip: String, speed: float, seconds: float) -> Dictionary:
	var requested: int = probe.request()
	var deadline: int = Time.get_ticks_usec() + int(seconds * 1000000.0)
	controller.update(speed)
	while Time.get_ticks_usec() < deadline:
		await t.get_tree().process_frame
		controller.update(speed)
	var measured: Dictionary = probe.result.duplicate(true)
	measured["settled"] = bool(measured.get("fresh", false)) and int(measured.get("request_id", -1)) == requested and str(measured.get("clip", "")) == clip and probe.rows.size() >= 12
	return measured

func vector_diameter(values: Array) -> float:
	var diameter := 0.0
	for first_index: int in values.size():
		for second_index: int in range(first_index):
			diameter = maxf(diameter, (values[first_index] as Vector3).distance_to(values[second_index] as Vector3))
	return diameter

func rotation_diameter(values: Array) -> float:
	var diameter := 0.0
	for first_index: int in values.size():
		for second_index: int in range(first_index):
			diameter = maxf(diameter, rad_to_deg((values[first_index] as Quaternion).angle_to(values[second_index] as Quaternion)))
	return diameter

func transition_statistics(reference: Dictionary, rows: Array[Dictionary], request: int, target: String, clip_length: float, activation: Dictionary) -> Dictionary:
	var point_paths: Dictionary = {"fore.L": [], "hand.L": [], "fore.R": [], "hand.R": []}
	var rotation_paths: Dictionary = {"upper.L": [], "fore.L": [], "upper.R": [], "fore.R": []}
	var reference_valid: bool = bool(reference.get("fresh", false)) and bool(reference.get("settled", false))
	var fresh := reference_valid
	var correct_clip := str(activation.get("clip", "")) == target
	var arm_lengths: Dictionary = {"L": 0.0, "R": 0.0}
	var geometry_valid := reference_valid
	if reference_valid:
		for reference_point: String in point_paths: (point_paths[reference_point] as Array).append(reference.points[reference_point])
		for reference_rotation: String in rotation_paths: (rotation_paths[reference_rotation] as Array).append(reference.rotations[reference_rotation])
		for arm_side: String in ["L", "R"]:
			var source_elbow: Vector3 = reference.raw_relative_points["fore." + arm_side]
			var source_wrist: Vector3 = reference.raw_relative_points["hand." + arm_side]
			var chain_length: float = source_elbow.length() + source_elbow.distance_to(source_wrist)
			arm_lengths[arm_side] = chain_length
			geometry_valid = geometry_valid and is_finite(chain_length) and chain_length > .1
	var clock_intervals: Array[float] = []
	var elapsed_times: Array[float] = []
	var clock_travel := 0.0
	var positive_clock_steps := 0
	var valid_clock := clip_length > 0.0
	var previous_clock: float = float(activation.get("clip_time", 0.0))
	var previous_frame: int = int(reference.get("frame", -1))
	var previous_serial: int = int(reference.get("raw_serial", -1))
	for measured: Dictionary in rows:
		fresh = fresh and bool(measured.get("fresh", false)) and int(measured.get("request_id", -1)) == request and int(measured.get("frame", -1)) > int(measured.get("request_frame", -1)) and int(measured.get("raw_frame", -1)) == int(measured.get("frame", -1)) and int(measured.frame) > previous_frame and int(measured.raw_serial) > previous_serial
		correct_clip = correct_clip and str(measured.get("clip", "")) == target
		for point_label: String in point_paths: (point_paths[point_label] as Array).append(measured.points[point_label])
		for rotation_label: String in rotation_paths: (rotation_paths[rotation_label] as Array).append(measured.rotations[rotation_label])
		# AP position is the actual playback clock. Callback finish timestamps
		# jitter with solver cost and are retained only as diagnostic wall time.
		var clock_step: float = fposmod(float(measured.clip_time) - previous_clock, clip_length) if clip_length > 0.0 else 0.0
		var clock_step_valid: bool = clock_step > .000001 and clock_step < clip_length * .5
		valid_clock = valid_clock and clock_step_valid
		clock_intervals.append(clock_step)
		if clock_step_valid:
			clock_travel += clock_step
			positive_clock_steps += 1
		elapsed_times.append(clock_travel)
		previous_clock = float(measured.clip_time)
		previous_frame = int(measured.frame)
		previous_serial = int(measured.raw_serial)
	var point_diameters: Dictionary = {}
	var rotation_diameters: Dictionary = {}
	var max_point_diameter := 0.0
	var max_rotation_diameter := 0.0
	for diameter_point: String in point_paths:
		var point_diameter: float = vector_diameter(point_paths[diameter_point])
		point_diameters[diameter_point] = point_diameter
		max_point_diameter = maxf(max_point_diameter, point_diameter)
	for diameter_rotation: String in rotation_paths:
		var angle_diameter: float = rotation_diameter(rotation_paths[diameter_rotation])
		rotation_diameters[diameter_rotation] = angle_diameter
		max_rotation_diameter = maxf(max_rotation_diameter, angle_diameter)
	var first_step_qualified: bool = reference_valid and not rows.is_empty() and not clock_intervals.is_empty() and clock_intervals[0] > .000001 and clock_intervals[0] <= CharAnim.BLEND / 6.0
	var first_step_details: Dictionary = {}
	var maximum_first_angle_excess := 0.0
	if first_step_qualified:
		var first_row: Dictionary = rows[0]
		for first_label: String in rotation_paths:
			var first_angle: float = rad_to_deg((first_row.rotations[first_label] as Quaternion).angle_to(reference.rotations[first_label] as Quaternion))
			var path_angle: float = float(rotation_diameters[first_label])
			var allowed_first_angle: float = path_angle * FIRST_CORRECTION_FRACTION + FIRST_ROTATION_NUMERIC_GUARD
			maximum_first_angle_excess = maxf(maximum_first_angle_excess, first_angle - allowed_first_angle)
			first_step_details[first_label] = {"step_deg": first_angle, "path_diameter_deg": path_angle, "fraction": first_angle / maxf(path_angle, .000001), "limit_deg": allowed_first_angle, "clock_interval_s": clock_intervals[0]}
	var qualified_triplets := 0
	var early_triplets := 0
	var tail_triplets := 0
	var crossing_triplets := 0
	var steady_triplets := 0
	var maximum_position_added := 0.0
	var maximum_rotation_added := 0.0
	var maximum_position_excess := 0.0
	var maximum_rotation_excess := 0.0
	var maximum_raw_position := 0.0
	var maximum_final_position := 0.0
	var maximum_raw_rotation := 0.0
	var maximum_final_rotation := 0.0
	var worst_position: Dictionary = {}
	var worst_rotation: Dictionary = {}
	var interpolation_trace: Array[Dictionary] = []
	# The entry step has its own local-correction rule. Interior interpolation
	# uses three actual samples of the same target clip; the preceding clip's
	# different playback rate/phase is never treated as target-clock time.
	for sample_index: int in range(1, rows.size() - 1):
		var left: Dictionary = rows[sample_index - 1]
		var centre: Dictionary = rows[sample_index]
		var right: Dictionary = rows[sample_index + 1]
		var left_dt: float = clock_intervals[sample_index]
		var right_dt: float = clock_intervals[sample_index + 1]
		var eligible: bool = bool(left.fresh) and bool(centre.fresh) and bool(right.fresh) and str(left.clip) == target and str(centre.clip) == target and str(right.clip) == target and left_dt > .000001 and right_dt > .000001 and maxf(left_dt, right_dt) <= CharAnim.BLEND / 6.0
		var entry: Dictionary = {"frame": centre.frame, "clip_time": centre.clip_time, "elapsed_ap_s": elapsed_times[sample_index], "left_clock_interval_s": left_dt, "right_clock_interval_s": right_dt, "eligible": eligible}
		if not eligible:
			interpolation_trace.append(entry)
			continue
		qualified_triplets += 1
		var elapsed: float = elapsed_times[sample_index]
		if elapsed <= CharAnim.BLEND: early_triplets += 1
		if absf(elapsed - CharAnim.BLEND) <= .04: tail_triplets += 1
		if elapsed_times[sample_index - 1] <= CharAnim.BLEND and elapsed_times[sample_index + 1] >= CharAnim.BLEND: crossing_triplets += 1
		if elapsed >= CharAnim.BLEND + .04: steady_triplets += 1
		var weight: float = left_dt / (left_dt + right_dt)
		var point_residuals: Dictionary = {}
		var rotation_residuals: Dictionary = {}
		for interpolation_point: String in point_paths:
			var raw_prediction: Vector3 = (left.raw_relative_points[interpolation_point] as Vector3).lerp(right.raw_relative_points[interpolation_point] as Vector3, weight)
			var final_prediction: Vector3 = (left.final_relative_points[interpolation_point] as Vector3).lerp(right.final_relative_points[interpolation_point] as Vector3, weight)
			var raw_error: float = raw_prediction.distance_to(centre.raw_relative_points[interpolation_point] as Vector3)
			var final_error: float = final_prediction.distance_to(centre.final_relative_points[interpolation_point] as Vector3)
			var added_error: float = maxf(0.0, final_error - raw_error)
			var point_side: String = "L" if interpolation_point.ends_with(".L") else "R"
			var allowed_position: float = float(arm_lengths[point_side]) * INTERPOLATION_ARM_FRACTION
			maximum_raw_position = maxf(maximum_raw_position, raw_error)
			maximum_final_position = maxf(maximum_final_position, final_error)
			maximum_position_excess = maxf(maximum_position_excess, added_error - allowed_position)
			point_residuals[interpolation_point] = {"raw_m": raw_error, "final_m": final_error, "added_m": added_error, "limit_m": allowed_position}
			if added_error > maximum_position_added:
				maximum_position_added = added_error
				worst_position = {"joint": interpolation_point, "frame": centre.frame, "clip_time": centre.clip_time, "raw_m": raw_error, "final_m": final_error, "added_m": added_error, "limit_m": allowed_position, "left_clock_interval_s": left_dt, "right_clock_interval_s": right_dt}
		for interpolation_rotation: String in rotation_paths:
			var raw_rotation: Quaternion = (left.raw_local_rotations[interpolation_rotation] as Quaternion).slerp(right.raw_local_rotations[interpolation_rotation] as Quaternion, weight).normalized()
			var final_rotation: Quaternion = (left.final_local_rotations[interpolation_rotation] as Quaternion).slerp(right.final_local_rotations[interpolation_rotation] as Quaternion, weight).normalized()
			var raw_angle: float = rad_to_deg(raw_rotation.angle_to(centre.raw_local_rotations[interpolation_rotation] as Quaternion))
			var final_angle: float = rad_to_deg(final_rotation.angle_to(centre.final_local_rotations[interpolation_rotation] as Quaternion))
			var added_angle: float = maxf(0.0, final_angle - raw_angle)
			maximum_raw_rotation = maxf(maximum_raw_rotation, raw_angle)
			maximum_final_rotation = maxf(maximum_final_rotation, final_angle)
			maximum_rotation_excess = maxf(maximum_rotation_excess, added_angle - INTERPOLATION_ANGLE_LIMIT)
			rotation_residuals[interpolation_rotation] = {"raw_deg": raw_angle, "final_deg": final_angle, "added_deg": added_angle, "limit_deg": INTERPOLATION_ANGLE_LIMIT}
			if added_angle > maximum_rotation_added:
				maximum_rotation_added = added_angle
				worst_rotation = {"joint": interpolation_rotation, "frame": centre.frame, "clip_time": centre.clip_time, "raw_deg": raw_angle, "final_deg": final_angle, "added_deg": added_angle, "limit_deg": INTERPOLATION_ANGLE_LIMIT, "left_clock_interval_s": left_dt, "right_clock_interval_s": right_dt}
		entry["points"] = point_residuals
		entry["rotations"] = rotation_residuals
		interpolation_trace.append(entry)
	var effect_observed: bool = max_point_diameter >= .005 or max_rotation_diameter >= 2.0
	var coverage: bool = reference_valid and fresh and correct_clip and geometry_valid and valid_clock and rows.size() >= 16 and positive_clock_steps >= 8 and clock_travel >= CharAnim.BLEND + .12 and first_step_qualified and qualified_triplets >= 8 and early_triplets >= 3 and tail_triplets >= 2 and crossing_triplets >= 1 and steady_triplets >= 3 and effect_observed
	return {"ok": coverage and maximum_first_angle_excess <= .001 and maximum_position_excess <= .000001 and maximum_rotation_excess <= .001, "coverage": coverage, "reference_valid": reference_valid, "fresh": fresh, "target_clip_observed_throughout": correct_clip, "valid_actual_ap_clock": valid_clock, "fresh_frame_samples": rows.size(), "positive_actual_ap_clock_steps": positive_clock_steps, "actual_ap_clock_advance_s": clock_travel, "first_step_qualified": first_step_qualified, "first_step": first_step_details, "maximum_first_rotation_limit_excess_deg": maximum_first_angle_excess, "qualified_triplets": qualified_triplets, "early_blend_triplets": early_triplets, "blend_tail_triplets": tail_triplets, "blend_crossing_triplets": crossing_triplets, "steady_tail_triplets": steady_triplets, "correction_effect_observed": effect_observed, "arm_chain_lengths_m": arm_lengths, "point_path_diameters_m": point_diameters, "rotation_path_diameters_deg": rotation_diameters, "maximum_raw_interpolation_position_m": maximum_raw_position, "maximum_final_interpolation_position_m": maximum_final_position, "maximum_added_interpolation_position_m": maximum_position_added, "maximum_raw_interpolation_rotation_deg": maximum_raw_rotation, "maximum_final_interpolation_rotation_deg": maximum_final_rotation, "maximum_added_interpolation_rotation_deg": maximum_rotation_added, "maximum_position_limit_excess_m": maximum_position_excess, "maximum_rotation_limit_excess_deg": maximum_rotation_excess, "worst_position": worst_position, "worst_rotation": worst_rotation, "interpolation_trace": interpolation_trace, "continuity_policy": "New arm corrections must not increase discrete impulses: first qualified local correction step <=25% of its measured rotation path +0.5 degree; actual AP-clock three-point final residual minus raw residual <=1% of that side's complete arm length and <=2 degrees. Entry, fresh triplets, blend interior, blend-end crossing and steady tail must all be sampled. Raw/final absolute residuals remain reported; this does not qualify the original AP as jump-free."}

func live_transition(id: String, controller: CharAnim, probe: TransitionFinalArmProbe, reference: Dictionary, source_clip: String, target_clip: String, speed: float) -> Dictionary:
	var requested: int = probe.request()
	var deadline: int = Time.get_ticks_usec() + 600000
	controller.update(speed)
	var activation: Dictionary = {"clip": controller.ap.current_animation, "clip_time": controller.ap.current_animation_position, "speed_scale": controller.ap.speed_scale, "frame": Engine.get_process_frames(), "wall_usec": Time.get_ticks_usec()}
	while Time.get_ticks_usec() < deadline:
		await t.get_tree().process_frame
		controller.update(speed)
	var captured: Array[Dictionary] = probe.rows.duplicate(true)
	var statistics: Dictionary = transition_statistics(reference, captured, requested, target_clip, controller.ap.get_animation(target_clip).length, activation)
	var interpolation_trace: Array = statistics.get("interpolation_trace", [])
	statistics.erase("interpolation_trace")
	statistics["source_clip"] = source_clip
	statistics["target_clip"] = target_clip
	statistics["reference_clip"] = reference.get("clip", "")
	statistics["api"] = "Real CharAnim.update; no AnimationPlayer play/seek/advance in the live transition fixture"
	statistics["ok"] = bool(statistics.ok) and str(reference.get("clip", "")) == source_clip
	# Preserve actual raw/final points and quaternions for independent finite-
	# difference review. Diagnostic Natural clock fields never decide a pass.
	print("RUNNING_ARM_FRAME_TRACE ", JSON.stringify(json_trace_value({"character": id, "transition": source_clip + "_to_" + target_clip, "configured_max_fps": Engine.max_fps, "activation": activation, "reference": reference, "frames": captured, "first_step": statistics.first_step, "interpolation": interpolation_trace})))
	print("RUNNING_ARM_CONTINUOUS ", JSON.stringify({"character": id, "transition": source_clip + "_to_" + target_clip, "measurement": statistics}))
	return statistics

func transition_contracts(id: String, model: Node3D, skeleton: Skeleton3D, natural: Node, controller: CharAnim) -> void:
	var before := BeforeNaturalArmProbe.new()
	before.name = "RunningArmBeforeNaturalReadOnlyProbe"
	before.model = model
	skeleton.add_child(before)
	if natural != null: skeleton.move_child(before, natural.get_index())
	var final_probe := TransitionFinalArmProbe.new()
	final_probe.name = "RunningArmContinuousFinalReadOnlyProbe"
	final_probe.model = model
	final_probe.animation = controller.ap
	final_probe.before = before
	final_probe.natural = natural
	skeleton.add_child(final_probe)
	# Static sampling left AP on run while the controller retained its former
	# state. Reset the fixture's state once, then let the public controller
	# establish idle and every subsequent switch through real AP playback.
	controller._state = ""
	controller._oneshot = ""
	controller.set_idle("idle", true)
	var idle_reference: Dictionary = await live_settle(controller, final_probe, "idle", 0.0, .55)
	var run_speed: float = maxf(controller.run_speed, controller.run_above + .25)
	var walk_speed: float = minf(controller.walk_speed, controller.run_above * .6)
	var idle_run: Dictionary = await live_transition(id, controller, final_probe, idle_reference, "idle", "run", run_speed)
	check(id + " real idle to run avoids adding a discrete arm correction impulse", bool(idle_run.ok), idle_run)
	# Analysis/logging can consume part of a frame. Acquire a fresh steady run
	# reference after that work so the first transition interval stays measured.
	var running_reference: Dictionary = await live_settle(controller, final_probe, "run", run_speed, .20)
	var run_walk: Dictionary = await live_transition(id, controller, final_probe, running_reference, "run", "walk", walk_speed)
	check(id + " real run to walk avoids adding a discrete arm correction impulse", bool(run_walk.ok), run_walk)
	var run_reference: Dictionary = await live_settle(controller, final_probe, "run", run_speed, .55)
	var run_idle: Dictionary = await live_transition(id, controller, final_probe, run_reference, "run", "idle", 0.0)
	check(id + " real run to idle avoids adding a discrete arm correction impulse", bool(run_idle.ok), run_idle)
	before.queue_free()
	final_probe.queue_free()
