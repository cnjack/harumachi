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

	static func fist_point(skeleton: Skeleton3D, side: String) -> Vector3:
		var sum := Vector3.ZERO
		var count := 0
		var side_name: String = "Left" if side == "L" else "Right"
		for finger_name: String in ["Index1", "Middle1", "Ring1", "Pinky1"]:
			for bone_index: int in skeleton.get_bone_count():
				if str(skeleton.get_bone_name(bone_index)).ends_with(side_name + "Hand" + finger_name):
					sum += skeleton.to_global(skeleton.get_bone_global_pose(bone_index).origin)
					count += 1
					break
		return sum / 4.0 if count == 4 else Vector3.INF

	func _process_modification() -> void:
		var skeleton: Skeleton3D = get_skeleton()
		relative_points.clear()
		local_rotations.clear()
		for side: String in ["L", "R"]:
			var shoulder: int = LivingPose.bone(skeleton, "upper." + side)
			var shoulder_point: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(shoulder).origin)
			for label: String in ["upper." + side, "fore." + side, "hand." + side]:
				local_rotations[label] = skeleton.get_bone_pose_rotation(LivingPose.bone(skeleton, label))
			for point_label: String in ["fore." + side, "hand." + side]:
				var point: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(LivingPose.bone(skeleton, point_label)).origin)
				relative_points[point_label] = model.global_basis.inverse() * (point - shoulder_point)
			relative_points["fist." + side] = model.global_basis.inverse() * (fist_point(skeleton, side) - shoulder_point)
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
			for label: String in ["upper." + side, "fore." + side, "hand." + side]:
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
			var fist: Vector3 = BeforeNaturalArmProbe.fist_point(skeleton, side)
			var final_fist: Vector3 = model.global_basis.inverse() * (fist - shoulder_point)
			final_points["fist." + side] = final_fist
			deltas["fist." + side] = final_fist - (before.relative_points.get("fist." + side, Vector3.INF) as Vector3)
			finite = finite and final_fist.is_finite() and (deltas["fist." + side] as Vector3).is_finite()
		var fresh: bool = before.frame == frame and before.serial > request_raw_serial and frame > request_frame and finite and deltas.size() == 6 and rotations.size() == 6
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

func sample(controller: CharAnim, phase: float, probe: SkeletonModifier3D, expected_count: int, clip: String = "run") -> Dictionary:
	controller.ap.play(clip, 0.0)
	controller.ap.speed_scale = 0.0
	var animation: Animation = controller.ap.get_animation(clip)
	var expected_time: float = fposmod(animation.length * phase, animation.length) if animation.loop_mode != Animation.LOOP_NONE else animation.length * phase
	controller.ap.seek(expected_time, true)
	controller.ap.advance(0.0)
	var natural: Node = probe.get_skeleton().get_node_or_null("NaturalLocomotionPose")
	if natural != null and natural.has_method("finish_transition"): natural.call("finish_transition")
	# Headless process waits alone can observe a prior restored skeleton. Require
	# the existing last modifier to acknowledge this exact request on a later frame.
	for settle_frame: int in 3: await t.get_tree().process_frame
	var requested: int = int(probe.call("request", clip, expected_time))
	var measured: Dictionary = {}
	for capture_frame: int in 8:
		await t.get_tree().process_frame
		if int(probe.get("completed_request")) != requested: continue
		measured = (probe.get("result") as Dictionary).duplicate(true)
		if int(measured.get("request_id", -1)) == requested: break
	var fresh: bool = int(measured.get("request_id", -1)) == requested and str(measured.get("clip", "")) == clip and absf(float(measured.get("clip_time", INF)) - expected_time) < .0001 and int(measured.get("applied_frame", -1)) > int(measured.get("request_frame", -1)) and bool(measured.get("measure_bones", false)) and finite_bones(measured, expected_count)
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
	var finger_rotation_error := 0.0
	var hand_rotation_error := 0.0
	var finger_count := 0
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
		var local_angle: float = rad_to_deg(first_local.basis.orthonormalized().get_rotation_quaternion().angle_to(second_local.basis.orthonormalized().get_rotation_quaternion()))
		if index in hands:
			hand_rotation_error = maxf(hand_rotation_error, local_angle)
		else:
			finger_rotation_error = maxf(finger_rotation_error, local_angle)
			finger_count += 1
		counted += 1
	return {"position_m": position_error, "rotation_deg": rotation_error, "scale": scale_error, "hand_rotation_deg": hand_rotation_error, "finger_rotation_deg": finger_rotation_error, "finger_bones": finger_count, "hand_and_finger_bones": counted}

func fixture_options() -> Dictionary:
	var actors: Array[String] = IDS.duplicate()
	var transitions_only := false
	var source_only := false
	var fps := 120
	var valid := true
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--running-arm-transitions-only": transitions_only = true
		elif argument == "--running-arm-source-only": source_only = true
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
	return {"actors": actors, "transitions_only": transitions_only, "source_only": source_only, "fps": fps, "valid": valid and not actors.is_empty()}

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
		var has_hand_switch: bool = natural != null and has_property(natural, "running_hand_style_enabled")
		var saved_hand_switch: bool = bool(natural.get("running_hand_style_enabled")) if has_hand_switch else false
		var saved: Dictionary = {"position": actor.global_position, "visible": actor.visible, "process": actor.is_processing(), "physics": actor.is_physics_processing(), "model_transform": model.transform, "clip": animation.current_animation, "time": animation.current_animation_position, "speed": animation.speed_scale, "state": controller._state, "oneshot": controller._oneshot, "idle": controller.idle_clip, "arms_enabled": bool(natural.get("running_arms_enabled")) if has_switch else false}
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.visible = true
		actor.global_position = Vector3(-8.0, 0.0, -10.0)
		model.rotation.x = 0.0
		if has_switch: natural.set("running_arms_enabled", true)
		if has_hand_switch: natural.set("running_hand_style_enabled", true)
		var probe: SkeletonModifier3D = load("res://scripts/tools/character_qa_pose_probe.gd").new()
		probe.name = "RunningArmRegressionFinalProbe"
		skeleton.add_child(probe)
		probe.call("prepare", model)
		probe.set("measure_bones", true)
		if not bool(options.transitions_only):
			await source_arm_contract(id, model, skeleton, controller, probe)
			if not bool(options.source_only):
				await actor_contract(id, model, skeleton, natural, has_switch, controller, probe)
				await hand_style_contract(id, model, skeleton, natural, has_hand_switch, controller, probe)
		Engine.max_fps = int(options.fps)
		if not bool(options.source_only): await transition_contracts(id, model, skeleton, natural, controller)
		Engine.max_fps = saved_max_fps
		if has_switch: natural.set("running_arms_enabled", bool(saved.arms_enabled))
		if has_hand_switch: natural.set("running_hand_style_enabled", saved_hand_switch)
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

func source_extras(model: Node3D) -> Dictionary:
	var rig: Node = model.find_child("Rig", true, false)
	return rig.get_meta("extras", {}) if rig != null else {}

func source_bone_count(id: String, model: Node3D) -> int:
	return 66 if id in ["sora", "mio"] else 54

func cross_chest_profile(model: Node3D) -> bool:
	var authored: Dictionary = source_extras(model).get("source_running_style", {})
	return int(authored.get("pose_revision", 0)) == 3 and str(authored.get("profile", "")) == "cross_chest_front_outward_rear"

func cross_chest_geometry(pose: Dictionary, skeleton: Skeleton3D, model: Node3D, side: String) -> Dictionary:
	# Angles come from captured bones, independently of the source recipe values.
	var hand: Dictionary = fist_geometry(pose, skeleton, model, side)
	var shoulder: Vector3 = position(pose, skeleton, "upper." + side)
	var elbow: Vector3 = position(pose, skeleton, "fore." + side)
	var wrist: Vector3 = position(pose, skeleton, "hand." + side)
	var chest: Vector3 = position(pose, skeleton, "chest")
	var up: Vector3 = (position(pose, skeleton, "Neck") - position(pose, skeleton, "hips")).normalized()
	var across: Vector3 = position(pose, skeleton, "upper.L") - position(pose, skeleton, "upper.R")
	var right: Vector3 = (across - up * across.dot(up)).normalized()
	var forward: Vector3 = right.cross(up).normalized()
	var sign_value: float = 1.0 if side == "L" else -1.0
	var upper: Vector3 = elbow - shoulder
	var fore: Vector3 = (wrist - elbow).normalized()
	var fist: Vector3 = hand.mcp_world
	return {"valid": hand.valid, "pitch_deg": hand.pitch_deg, "forearm_elevation_deg": rad_to_deg(asin(clampf(fore.dot(Vector3.UP), -1.0, 1.0))), "upper_frontal_deg": rad_to_deg(atan2(upper.dot(right) * sign_value, -upper.dot(up))), "elbow_flex_deg": rad_to_deg(upper.normalized().angle_to(fore)), "fist_own_side_m": (fist - chest).dot(right) * sign_value, "fist_above_chest_m": (fist - chest).dot(up), "elbow_forward_m": upper.dot(forward)}

func cross_chest_peaks_ok(peaks: Dictionary) -> bool:
	for side: String in ["L", "R"]:
		var front: Dictionary = peaks[side].front
		var rear: Dictionary = peaks[side].rear
		if front.is_empty() or rear.is_empty(): return false
		if not bool(front.valid) or not bool(rear.valid): return false
		if float(front.forearm_elevation_deg) < 30.0 or float(front.forearm_elevation_deg) > 45.0: return false
		if float(front.upper_frontal_deg) < -20.0 or float(front.upper_frontal_deg) > -10.0: return false
		if float(front.elbow_flex_deg) < 80.0 or float(front.elbow_flex_deg) > 100.0: return false
		if float(front.fist_own_side_m) > -.005 or float(front.fist_above_chest_m) < 0.0: return false
		if float(rear.elbow_forward_m) > -.03 or float(rear.upper_frontal_deg) < 10.0: return false
	return true

func accumulate_cross_chest(peaks: Dictionary, pose: Dictionary, skeleton: Skeleton3D, model: Node3D) -> void:
	for side: String in ["L", "R"]:
		var geometry: Dictionary = cross_chest_geometry(pose, skeleton, model, side)
		if (peaks[side].front as Dictionary).is_empty() or float(geometry.pitch_deg) > float(peaks[side].front.pitch_deg): peaks[side].front = geometry
		if (peaks[side].rear as Dictionary).is_empty() or float(geometry.pitch_deg) < float(peaks[side].rear.pitch_deg): peaks[side].rear = geometry

func source_arm_contract(id: String, model: Node3D, skeleton: Skeleton3D, controller: CharAnim, probe: SkeletonModifier3D) -> void:
	# Independently measure the imported source with every game modifier off.
	# The old source exceeds these art limits even if its runtime fix is enabled.
	var modifiers: Dictionary = {}
	for child: Node in skeleton.get_children():
		if child is SkeletonModifier3D and child != probe:
			modifiers[child] = (child as SkeletonModifier3D).active
			(child as SkeletonModifier3D).active = false
	var statistics: Dictionary = {"L": new_statistics(), "R": new_statistics()}
	var wrist_limits: Dictionary = {"sora": -.22, "ren": -.21, "haru": -.22, "mio": -.16, "aoi": -.14, "tanaka": -.20, "kazuko": -.18}
	var fresh := 0
	var hands_ok := true
	var minimum_inward := INF
	var maximum_wrist_angle := 0.0
	var cross_profile: bool = cross_chest_profile(model)
	var cross_peaks: Dictionary = {"L": {"front": {}, "rear": {}}, "R": {"front": {}, "rear": {}}}
	for index: int in range(PHASE_STEPS + 1):
		var source: Dictionary = await sample(controller, float(index) / PHASE_STEPS, probe, source_bone_count(id, model))
		if not bool(source.get("fresh", false)): continue
		fresh += 1
		if cross_profile: accumulate_cross_chest(cross_peaks, source, skeleton, model)
		for side: String in ["L", "R"]:
			accumulate(statistics[side], source, skeleton, model, side, false)
			var geometry: Dictionary = fist_geometry(source, skeleton, model, side)
			minimum_inward = minf(minimum_inward, float(geometry.signed_inward_deg))
			maximum_wrist_angle = maxf(maximum_wrist_angle, float(geometry.wrist_total_deg))
			hands_ok = hands_ok and bool(geometry.valid) and float(geometry.signed_inward_deg) >= 2.0 and float(geometry.wrist_total_deg) <= 10.0
	var geometry_ok: bool = fresh == PHASE_STEPS + 1
	for side_name: String in ["L", "R"]:
		var stats: Dictionary = statistics[side_name]
		var span: float = float(stats.pitch_max) - float(stats.pitch_min)
		geometry_ok = geometry_ok and span >= 25.0 and span <= 42.0 and float(stats.wrist_above_shoulder_max) <= float(wrist_limits[id])
		# Low wrists alone can still resemble carrying a tray. Require the elbow
		# to pass behind the shoulder and limit its forward pitch independently.
		geometry_ok = geometry_ok and float(stats.pitch_min) <= -20.0 and float(stats.pitch_max) <= 12.0
	var authored: Dictionary = source_extras(model).get("source_running_style", {})
	var declared_ok: bool = int(authored.get("version", 0)) == 1 and bool(authored.get("arms_authored", false)) and bool(authored.get("wrists_authored", false)) and bool(authored.get("grip_authored", false)) and not bool(authored.get("runtime_arm_style_required", true))
	if cross_profile:
		check(id + " source run reaches opposite upper chest with a diagonal forearm and rear outward elbow", declared_ok and fresh == PHASE_STEPS + 1 and cross_chest_peaks_ok(cross_peaks), {"fresh_samples": fresh, "peaks": cross_peaks, "forearm_elevation_limits_deg": [30, 45], "front_adduction_limits_deg": [10, 20], "elbow_flex_limits_deg": [80, 100], "all_game_modifiers_disabled": true})
	else:
		check(id + " source run keeps low compact arms without game modifiers", declared_ok and geometry_ok, {"fresh_samples": fresh, "expected": PHASE_STEPS + 1, "statistics": statistics, "upper_span_limits_deg": [25, 42], "rear_pitch_at_most_deg": -20, "forward_pitch_at_most_deg": 12, "wrist_shoulder_limit_m": wrist_limits[id], "source_profile": authored, "all_game_modifiers_disabled": true})
	check(id + " source running wrists stay neutral and slightly inward", declared_ok and fresh == PHASE_STEPS + 1 and hands_ok, {"fresh_samples": fresh, "minimum_inward_deg": minimum_inward, "maximum_wrist_angle_deg": maximum_wrist_angle, "limits_deg": {"minimum_inward": 2, "maximum_total": 10}})
	for modifier: Node in modifiers:
		(modifier as SkeletonModifier3D).active = bool(modifiers[modifier])

func actor_contract(id: String, model: Node3D, skeleton: Skeleton3D, natural: Node, has_switch: bool, controller: CharAnim, probe: SkeletonModifier3D) -> void:
	var expected_count: int = source_bone_count(id, model)
	var statistics: Dictionary = {"L": new_statistics(), "R": new_statistics()}
	var fresh_samples := 0
	var baseline_samples := 0
	var preserve_position_max := 0.0
	var preserve_rotation_max := 0.0
	var hand_position_max := 0.0
	var hand_rotation_max := 0.0
	var hand_scale_max := 0.0
	var finger_rotation_max := 0.0
	var hand_bone_count := 0
	var cross_profile: bool = cross_chest_profile(model)
	var cross_peaks: Dictionary = {"L": {"front": {}, "rear": {}}, "R": {"front": {}, "rear": {}}}
	for index: int in range(PHASE_STEPS + 1):
		var phase: float = float(index) / PHASE_STEPS
		if has_switch: natural.set("running_arms_enabled", true)
		var actual: Dictionary = await sample(controller, phase, probe, expected_count)
		if has_switch: natural.set("running_arms_enabled", false)
		var baseline: Dictionary = await sample(controller, phase, probe, expected_count)
		if bool(baseline.get("fresh", false)): baseline_samples += 1
		if not bool(actual.get("fresh", false)): continue
		fresh_samples += 1
		if cross_profile: accumulate_cross_chest(cross_peaks, actual, skeleton, model)
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
			finger_rotation_max = maxf(finger_rotation_max, float(hand_difference.finger_rotation_deg))
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
	if cross_profile:
		check(id + " running final arms retain the requested cross-chest and rear outward pose", fresh and cross_chest_peaks_ok(cross_peaks), {"peaks": cross_peaks, "coverage": coverage})
		check(id + " running final arm swing stays bounded on both sides", fresh and left_span >= 60.0 and right_span >= 60.0 and left_span <= 100.0 and right_span <= 100.0, {"L_span_deg": left_span, "R_span_deg": right_span, "limits_deg": [60, 100], "coverage": coverage})
		check(id + " running elbows stay approximately at a right angle", fresh and minf(float(left.flex_min), float(right.flex_min)) >= 80.0 and maxf(float(left.flex_max), float(right.flex_max)) <= 100.0 and minf(left_flex_span, right_flex_span) >= 4.0 and maxf(left_flex_span, right_flex_span) <= MAX_ELBOW_SPAN, {"L_min_deg": left.flex_min, "L_max_deg": left.flex_max, "R_min_deg": right.flex_min, "R_max_deg": right.flex_max, "coverage": coverage})
	else:
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
	check(id + " running arm changes preserve legs torso and local hand finger articulation", fresh and baseline_samples == PHASE_STEPS + 1 and preserve_position_max < .001 and preserve_rotation_max < .1 and hand_bone_count == 32 and hand_position_max < .00005 and hand_rotation_max <= 20.0 and finger_rotation_max < .1 and hand_scale_max < .0001, {"arm_correction_switch_available": has_switch, "max_position_error_m": preserve_position_max, "max_rotation_error_deg": preserve_rotation_max, "limits": {"position_m": .001, "rotation_deg": .1}, "preserved_bones": PRESERVED, "local_hand_finger_trs": {"bones": hand_bone_count, "position_m": hand_position_max, "hand_rotation_deg": hand_rotation_max, "finger_rotation_deg": finger_rotation_max, "scale": hand_scale_max, "limits": {"position_m": .00005, "hand_rotation_deg": 20.0, "finger_rotation_deg": .1, "scale": .0001}, "contract": "Hand translation/scale and all finger local TRS remain fixed; Hand rotation may turn the fist inward"}, "coverage": coverage})

func hand_descendant(skeleton: Skeleton3D, index: int) -> bool:
	var ancestor: int = index
	var left_hand: int = LivingPose.bone(skeleton, "hand.L")
	var right_hand: int = LivingPose.bone(skeleton, "hand.R")
	while ancestor >= 0:
		if ancestor == left_hand or ancestor == right_hand: return true
		ancestor = skeleton.get_bone_parent(ancestor)
	return false

func fist_geometry(pose: Dictionary, skeleton: Skeleton3D, model: Node3D, side: String) -> Dictionary:
	var sum := Vector3.ZERO
	var count := 0
	var side_name: String = "Left" if side == "L" else "Right"
	for finger_name: String in ["Index1", "Middle1", "Ring1", "Pinky1"]:
		for index: int in skeleton.get_bone_count():
			if str(skeleton.get_bone_name(index)).ends_with(side_name + "Hand" + finger_name):
				sum += global_transform_from_sample(pose, index).origin
				count += 1
				break
	var shoulder: Vector3 = position(pose, skeleton, "upper." + side)
	var elbow: Vector3 = position(pose, skeleton, "fore." + side)
	var wrist: Vector3 = position(pose, skeleton, "hand." + side)
	var chest: Vector3 = position(pose, skeleton, "chest")
	var mcp: Vector3 = sum / 4.0
	var fore: Vector3 = (wrist - elbow).normalized()
	var hand: Vector3 = (mcp - wrist).normalized()
	var inward: Vector3 = chest - wrist
	inward = (inward - fore * inward.dot(fore)).normalized()
	var upper: Vector3 = model.global_basis.inverse() * (elbow - shoulder)
	var lateral: Vector3 = model.global_basis.inverse() * (mcp - chest)
	return {"valid": count == 4 and mcp.is_finite() and (mcp - wrist).length() > .01 and inward.length() > .5, "mcp_world": mcp, "pitch_deg": rad_to_deg(atan2(upper.z, -upper.y)), "signed_inward_deg": rad_to_deg(atan2(hand.dot(inward), hand.dot(fore))), "wrist_total_deg": rad_to_deg(fore.angle_to(hand)), "midline_distance_m": absf(lateral.x), "hand_length_m": mcp.distance_to(wrist)}

func dynamic_sleeve_bones(model: Node3D, skeleton: Skeleton3D) -> Dictionary:
	# AP seek pauses clip time, not native spring integration. Identify only the
	# configured helper chains of the actual active simulator; no name-wide skip.
	var simulator: SpringBoneSimulator3D = skeleton.get_node_or_null("CharacterSleeveSpring") as SpringBoneSimulator3D
	var indices: Array[int] = []
	var names: Array[String] = []
	if simulator == null or not simulator.active: return {"valid": true, "indices": indices, "names": names}
	var rig: Node = model.find_child("Rig", true, false)
	if rig == null or not rig.has_meta("extras"): return {"valid": false, "indices": indices, "names": names}
	var extras: Dictionary = rig.get_meta("extras")
	var clothing: Dictionary = extras.get("character_clothing", {})
	var chains: Array = clothing.get("spring_chains", [])
	var valid: bool = not chains.is_empty() and int(simulator.setting_count) == chains.size()
	for chain: Dictionary in chains:
		var root_name: String = str(chain.get("root", ""))
		var end_name: String = str(chain.get("end", ""))
		var root_index: int = skeleton.find_bone(root_name)
		var end_index: int = skeleton.find_bone(end_name)
		var chain_indices: Array[int] = []
		var cursor: int = end_index
		while cursor >= 0 and chain_indices.size() <= skeleton.get_bone_count():
			chain_indices.append(cursor)
			if cursor == root_index: break
			cursor = skeleton.get_bone_parent(cursor)
		var connected: bool = root_index >= 0 and end_index >= 0 and not chain_indices.is_empty() and chain_indices[-1] == root_index
		valid = valid and connected
		for chain_index: int in chain_indices:
			var bone_name: String = str(skeleton.get_bone_name(chain_index))
			valid = valid and bone_name.begins_with("Cloth_")
			if connected and chain_index not in indices:
				indices.append(chain_index)
				names.append(bone_name)
	return {"valid": valid, "indices": indices, "names": names, "chains": chains, "simulator": str(simulator.get_path())}

func hand_style_contract(id: String, model: Node3D, skeleton: Skeleton3D, natural: Node, has_hand_switch: bool, controller: CharAnim, probe: SkeletonModifier3D) -> void:
	var expected_count: int = source_bone_count(id, model)
	var fresh_pairs := 0
	var geometry_ok := true
	var isolation_ok := true
	var sides: Dictionary = {"L": [], "R": []}
	var other_position_max := 0.0
	var other_rotation_max := 0.0
	var local_position_max := 0.0
	var local_scale_max := 0.0
	var hand_rotation_max := 0.0
	var finger_rotation_max := 0.0
	var observed_finger_bones := 0
	var dynamic: Dictionary = dynamic_sleeve_bones(model, skeleton)
	var dynamic_position_max := 0.0
	var dynamic_rotation_max := 0.0
	var worst_body_position: Dictionary = {}
	var worst_body_rotation: Dictionary = {}
	var worst_dynamic_position: Dictionary = {}
	var worst_dynamic_rotation: Dictionary = {}
	var body_bones_measured := 0
	for phase_index: int in range(PHASE_STEPS + 1):
		var phase: float = float(phase_index) / PHASE_STEPS
		if has_hand_switch: natural.set("running_hand_style_enabled", true)
		var actual: Dictionary = await sample(controller, phase, probe, expected_count)
		if has_hand_switch: natural.set("running_hand_style_enabled", false)
		var source: Dictionary = await sample(controller, phase, probe, expected_count)
		if not bool(actual.get("fresh", false)) or not bool(source.get("fresh", false)): continue
		fresh_pairs += 1
		var local: Dictionary = hand_local_difference(actual, source, skeleton)
		local_position_max = maxf(local_position_max, float(local.position_m))
		local_scale_max = maxf(local_scale_max, float(local.scale))
		hand_rotation_max = maxf(hand_rotation_max, float(local.hand_rotation_deg))
		finger_rotation_max = maxf(finger_rotation_max, float(local.finger_rotation_deg))
		observed_finger_bones = int(local.finger_bones)
		body_bones_measured = 0
		for bone_index: int in skeleton.get_bone_count():
			if hand_descendant(skeleton, bone_index): continue
			var first: Transform3D = global_transform_from_sample(actual, bone_index)
			var second: Transform3D = global_transform_from_sample(source, bone_index)
			var position_delta: float = first.origin.distance_to(second.origin)
			var angle_delta: float = rad_to_deg(first.basis.orthonormalized().get_rotation_quaternion().angle_to(second.basis.orthonormalized().get_rotation_quaternion()))
			var bone_detail: Dictionary = {"bone": str(skeleton.get_bone_name(bone_index)), "index": bone_index, "phase": phase, "position_m": position_delta, "rotation_deg": angle_delta}
			if bone_index in dynamic.indices:
				if position_delta > dynamic_position_max:
					dynamic_position_max = position_delta
					worst_dynamic_position = bone_detail
				if angle_delta > dynamic_rotation_max:
					dynamic_rotation_max = angle_delta
					worst_dynamic_rotation = bone_detail
				continue
			body_bones_measured += 1
			if position_delta > other_position_max:
				other_position_max = position_delta
				worst_body_position = bone_detail
			if angle_delta > other_rotation_max:
				other_rotation_max = angle_delta
				worst_body_rotation = bone_detail
		for side: String in ["L", "R"]:
			var before: Dictionary = fist_geometry(source, skeleton, model, side)
			var after: Dictionary = fist_geometry(actual, skeleton, model, side)
			geometry_ok = geometry_ok and bool(before.valid) and bool(after.valid) and float(after.wrist_total_deg) <= maxf(float(before.wrist_total_deg), 12.0) + 2.0 and float(after.signed_inward_deg) <= maxf(float(before.signed_inward_deg), 8.0) + .1
			var hand_index: int = LivingPose.bone(skeleton, "hand." + side)
			var hand_parent: int = skeleton.get_bone_parent(hand_index)
			var source_hand: Transform3D = global_transform_from_sample(source, hand_parent).affine_inverse() * global_transform_from_sample(source, hand_index)
			var actual_hand: Transform3D = global_transform_from_sample(actual, hand_parent).affine_inverse() * global_transform_from_sample(actual, hand_index)
			var hand_change: float = rad_to_deg(source_hand.basis.orthonormalized().get_rotation_quaternion().angle_to(actual_hand.basis.orthonormalized().get_rotation_quaternion()))
			(sides[side] as Array).append({"phase": phase, "before": before, "after": after, "local_hand_rotation_change_deg": hand_change})
	var side_details: Dictionary = {}
	var required_sides := 0
	var source_authored: bool = bool((source_extras(model).get("source_running_style", {}) as Dictionary).get("wrists_authored", false))
	for measured_side: String in ["L", "R"]:
		var entries: Array = sides[measured_side]
		if entries.size() != PHASE_STEPS + 1:
			geometry_ok = false
			continue
		var front: Dictionary = entries[0]
		var back: Dictionary = entries[0]
		var preserved_side_max := 0.0
		for entry: Dictionary in entries:
			if float(entry.before.pitch_deg) > float(front.before.pitch_deg): front = entry
			if float(entry.before.pitch_deg) < float(back.before.pitch_deg): back = entry
			preserved_side_max = maxf(preserved_side_max, float(entry.local_hand_rotation_change_deg))
		var outward_before: float = maxf(0.0, -float(front.before.signed_inward_deg))
		var outward_after: float = maxf(0.0, -float(front.after.signed_inward_deg))
		var required: bool = not source_authored and outward_before > 1.0 and not (id == "mio" and measured_side == "L")
		var improvement_required: float = minf(3.0, outward_before * .5) if required else 0.0
		var midline_gain: float = float(front.before.midline_distance_m) - float(front.after.midline_distance_m)
		var midline_required: float = float(front.before.hand_length_m) * .005 if required else 0.0
		if required:
			required_sides += 1
			geometry_ok = geometry_ok and outward_before - outward_after >= improvement_required and midline_gain >= midline_required
		if id == "mio" and measured_side == "L": geometry_ok = geometry_ok and preserved_side_max < .1
		geometry_ok = geometry_ok and float(back.local_hand_rotation_change_deg) < .2
		side_details[measured_side] = {"front": front, "back": back, "required_outward_improvement_deg": improvement_required, "outward_improvement_deg": outward_before - outward_after, "midline_gain_m": midline_gain, "required_midline_gain_m": midline_required, "all_phase_local_rotation_change_max_deg": preserved_side_max}
	print("RUNNING_HAND_GEOMETRY_TRACE ", JSON.stringify({"character": id, "hand_style_switch_available": has_hand_switch, "fresh_pairs": fresh_pairs, "sides": sides}))
	var complete: bool = fresh_pairs == PHASE_STEPS + 1
	isolation_ok = complete and bool(dynamic.valid) and (dynamic.indices as Array).size() == (12 if id in ["sora", "mio"] else 0) and body_bones_measured == 22 and observed_finger_bones == 30 and other_position_max < .00005 and other_rotation_max < .1 and local_position_max < .00005 and local_scale_max < .0001 and hand_rotation_max <= 20.0 and finger_rotation_max < .1
	check(id + " running forward fists reduce outward deviation without forcing a common wrist angle", complete and geometry_ok and (source_authored or required_sides > 0), {"hand_style_switch_available": has_hand_switch, "fresh_pairs": fresh_pairs, "expected_pairs": PHASE_STEPS + 1, "required_sides": required_sides, "sides": side_details, "source_authored": source_authored, "policy": "Independent final MCP-centroid/forearm geometry: outward error improves by min(3deg,half original), MCP moves inward by 0.5% hand length; full wrist angle <=max(original,12deg)+2deg; back swing returns original; Mio left stays original"})
	check(id + " running fist styling preserves arm centers body and all finger local articulation", isolation_ok, {"fresh_pairs": fresh_pairs, "other_bone_position_m": other_position_max, "other_bone_rotation_deg": other_rotation_max, "local_hand_finger_position_m": local_position_max, "local_hand_finger_scale": local_scale_max, "hand_local_rotation_change_deg": hand_rotation_max, "finger_local_rotation_change_deg": finger_rotation_max, "finger_bones": observed_finger_bones, "unchanged_body_bones": body_bones_measured, "worst_body_position": worst_body_position, "worst_body_rotation": worst_body_rotation, "dynamic_sleeves": dynamic, "dynamic_position_max_m": dynamic_position_max, "dynamic_rotation_max_deg": dynamic_rotation_max, "worst_dynamic_position": worst_dynamic_position, "worst_dynamic_rotation": worst_dynamic_rotation, "sampling_scope": "All original 54 bones protected: 22 non-Hand body bones at 50um/0.1deg plus both Hand T/S and 30 finger local TRS. Only validated GLB metadata chains of the actual active native spring are separately reported because their integration continues between paused-AP callbacks.", "limits": {"position_m": .00005, "rotation_deg": .1, "hand_rotation_deg": 20.0, "scale": .0001}})
	var nonrun_pairs := 0
	var nonrun_expected := 0
	var nonrun_ok := true
	var nonrun_position_max := 0.0
	var nonrun_rotation_max := 0.0
	var nonrun_scale_max := 0.0
	var clips: Array[String] = []
	for clip: String in controller.ap.get_animation_list():
		if clip == "run" or clip == "RESET": continue
		clips.append(clip)
		for nonrun_phase: float in [0.0, .125, .25, .5, .75, .875]:
			nonrun_expected += 1
			if has_hand_switch: natural.set("running_hand_style_enabled", true)
			var styled: Dictionary = await sample(controller, nonrun_phase, probe, expected_count, clip)
			if has_hand_switch: natural.set("running_hand_style_enabled", false)
			var original: Dictionary = await sample(controller, nonrun_phase, probe, expected_count, clip)
			if not bool(styled.get("fresh", false)) or not bool(original.get("fresh", false)):
				nonrun_ok = false
				continue
			nonrun_pairs += 1
			var nonrun_difference: Dictionary = hand_local_difference(styled, original, skeleton)
			nonrun_position_max = maxf(nonrun_position_max, float(nonrun_difference.position_m))
			nonrun_rotation_max = maxf(nonrun_rotation_max, float(nonrun_difference.rotation_deg))
			nonrun_scale_max = maxf(nonrun_scale_max, float(nonrun_difference.scale))
			nonrun_ok = nonrun_ok and int(nonrun_difference.hand_and_finger_bones) == 32
	check(id + " fist styling leaves every available non-running hand and finger pose intact", nonrun_ok and nonrun_pairs == nonrun_expected and clips.size() >= 3 and nonrun_expected >= 18 and nonrun_position_max < .00005 and nonrun_rotation_max < .1 and nonrun_scale_max < .0001, {"clips": clips, "fresh_pairs": nonrun_pairs, "expected_pairs": nonrun_expected, "max_local_position_m": nonrun_position_max, "max_local_rotation_deg": nonrun_rotation_max, "max_local_scale": nonrun_scale_max})
	if has_hand_switch: natural.set("running_hand_style_enabled", true)

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

func transition_statistics(reference: Dictionary, rows: Array[Dictionary], request: int, target: String, clip_length: float, activation: Dictionary, source_authored: bool) -> Dictionary:
	var point_paths: Dictionary = {"fore.L": [], "hand.L": [], "fist.L": [], "fore.R": [], "hand.R": [], "fist.R": []}
	var rotation_paths: Dictionary = {"upper.L": [], "fore.L": [], "hand.L": [], "upper.R": [], "fore.R": [], "hand.R": []}
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
	var source_point_diameter := 0.0
	var source_rotation_diameter := 0.0
	var maximum_applied_point := 0.0
	var maximum_applied_rotation := 0.0
	if source_authored:
		for source_point_label: String in point_paths:
			var source_point_path: Array = [reference.raw_relative_points[source_point_label]]
			for point_row: Dictionary in rows:
				source_point_path.append(point_row.raw_relative_points[source_point_label])
				maximum_applied_point = maxf(maximum_applied_point,(point_row.points[source_point_label] as Vector3).length())
			source_point_diameter = maxf(source_point_diameter,vector_diameter(source_point_path))
		for source_rotation_label: String in rotation_paths:
			var source_rotation_path: Array = [reference.raw_local_rotations[source_rotation_label]]
			for rotation_row: Dictionary in rows:
				source_rotation_path.append(rotation_row.raw_local_rotations[source_rotation_label])
				var delta: Quaternion = rotation_row.rotations[source_rotation_label]
				maximum_applied_rotation = maxf(maximum_applied_rotation,rad_to_deg(2.0*atan2(Vector3(delta.x,delta.y,delta.z).length(),absf(delta.w))))
			source_rotation_diameter = maxf(source_rotation_diameter,rotation_diameter(source_rotation_path))
	# Source style must move through real AP blending with no duplicate arm
	# correction. Legacy assets still require an observable runtime correction.
	var source_passthrough: bool = source_authored and (source_point_diameter >= .005 or source_rotation_diameter >= 2.0) and maximum_applied_point < .00005 and maximum_applied_rotation < .1
	var coverage: bool = reference_valid and fresh and correct_clip and geometry_valid and valid_clock and rows.size() >= 16 and positive_clock_steps >= 8 and clock_travel >= CharAnim.BLEND + .12 and first_step_qualified and qualified_triplets >= 8 and early_triplets >= 3 and tail_triplets >= 2 and crossing_triplets >= 1 and steady_triplets >= 3 and (source_passthrough if source_authored else effect_observed)
	return {"ok": coverage and maximum_first_angle_excess <= .001 and maximum_position_excess <= .000001 and maximum_rotation_excess <= .001, "coverage": coverage, "reference_valid": reference_valid, "fresh": fresh, "target_clip_observed_throughout": correct_clip, "valid_actual_ap_clock": valid_clock, "fresh_frame_samples": rows.size(), "positive_actual_ap_clock_steps": positive_clock_steps, "actual_ap_clock_advance_s": clock_travel, "first_step_qualified": first_step_qualified, "first_step": first_step_details, "maximum_first_rotation_limit_excess_deg": maximum_first_angle_excess, "qualified_triplets": qualified_triplets, "early_blend_triplets": early_triplets, "blend_tail_triplets": tail_triplets, "blend_crossing_triplets": crossing_triplets, "steady_tail_triplets": steady_triplets, "correction_effect_observed": effect_observed, "source_authored": source_authored, "source_motion_and_passthrough_verified": source_passthrough, "source_point_motion_diameter_m": source_point_diameter, "source_rotation_motion_diameter_deg": source_rotation_diameter, "maximum_duplicate_point_shift_m": maximum_applied_point, "maximum_duplicate_rotation_deg": maximum_applied_rotation, "arm_chain_lengths_m": arm_lengths, "point_path_diameters_m": point_diameters, "rotation_path_diameters_deg": rotation_diameters, "maximum_raw_interpolation_position_m": maximum_raw_position, "maximum_final_interpolation_position_m": maximum_final_position, "maximum_added_interpolation_position_m": maximum_position_added, "maximum_raw_interpolation_rotation_deg": maximum_raw_rotation, "maximum_final_interpolation_rotation_deg": maximum_final_rotation, "maximum_added_interpolation_rotation_deg": maximum_rotation_added, "maximum_position_limit_excess_m": maximum_position_excess, "maximum_rotation_limit_excess_deg": maximum_rotation_excess, "worst_position": worst_position, "worst_rotation": worst_rotation, "interpolation_trace": interpolation_trace, "continuity_policy": "New arm corrections must not increase discrete impulses: first qualified local correction step <=25% of its measured rotation path +0.5 degree; actual AP-clock three-point final residual minus raw residual <=1% of that side's complete arm length and <=2 degrees. Entry, fresh triplets, blend interior, blend-end crossing and steady tail must all be sampled. Raw/final absolute residuals remain reported; this does not qualify the original AP as jump-free."}

func live_transition(id: String, controller: CharAnim, probe: TransitionFinalArmProbe, reference: Dictionary, source_clip: String, target_clip: String, speed: float) -> Dictionary:
	var requested: int = probe.request()
	var deadline: int = Time.get_ticks_usec() + 600000
	controller.update(speed)
	var activation: Dictionary = {"clip": controller.ap.current_animation, "clip_time": controller.ap.current_animation_position, "speed_scale": controller.ap.speed_scale, "frame": Engine.get_process_frames(), "wall_usec": Time.get_ticks_usec()}
	while Time.get_ticks_usec() < deadline:
		await t.get_tree().process_frame
		controller.update(speed)
	var captured: Array[Dictionary] = probe.rows.duplicate(true)
	var authored: Dictionary = source_extras(probe.model).get("source_running_style", {})
	var source_authored: bool = bool(authored.get("arms_authored",false)) and bool(authored.get("wrists_authored",false))
	var statistics: Dictionary = transition_statistics(reference, captured, requested, target_clip, controller.ap.get_animation(target_clip).length, activation, source_authored)
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
