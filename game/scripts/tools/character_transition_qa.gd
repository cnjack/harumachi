extends RefCounted
## Native controller transitions. Never seeks animation time or edits a runtime pose.
const CONTINUOUS = preload("res://scripts/tools/character_continuous_probe.gd")
const BONES = preload("res://scripts/tools/character_qa_pose_probe.gd")
const IDS: Array[String] = ["sora", "ren", "haru", "mio", "aoi", "tanaka", "kazuko"]
const RUN_SPEEDS: Dictionary = {"ren": 3.2, "haru": 4.5, "mio": 3.2, "aoi": 3.1, "tanaka": 3.4, "kazuko": 3.6}
const WATCH: Array[String] = ["hips", "foot.L", "foot.R"]
var reports: Array[Dictionary] = []
var failures: Array[String] = []
var driver_deadline := 0

func vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func point(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func capture(qa: Node, output: String) -> void:
	var began: int = Time.get_ticks_msec()
	driver_deadline = began + 85000
	var previous_freeze: bool = NPC.freeze
	var previous_roaming: bool = NPC.roam_enabled
	NPC.freeze = false
	NPC.roam_enabled = false
	qa.call("outdoors")
	for id: String in IDS:
		if id not in qa.get("ids"): continue
		if Time.get_ticks_msec() >= driver_deadline:
			failures.append("transition driver exceeded its 85 second capture budget before " + id)
			break
		await capture_character(qa, id, output)
	NPC.freeze = previous_freeze
	NPC.roam_enabled = previous_roaming
	var report: Dictionary = {"engine": Engine.get_version_info().string, "elapsed_seconds": (Time.get_ticks_msec() - began) / 1000.0, "scope": "Seven real Player/NPC controllers: idle -> walk -> run -> walk -> stop, then complete wave and bow with their natural return to idle. No animation seek or pose writes. The 85 second budget covers capture, not process startup or final JSON encoding.", "sampling": "One final continuous modifier row per rendered process frame; full bone positions and bases come from a later-frame acknowledgement on the same skeleton and are paired by applied_frame. World and actor-relative deltas are measurements, not an automatic judgement of natural motion.", "full_bone_encoding": "Each case stores bone_layout (name and parent) once. Every full_bone_samples entry stores bone_transforms in that order; each transform is 12 floats: world position XYZ, basis X XYZ, basis Y XYZ, basis Z XYZ. This is complete world-pose data with repeated labels removed.", "npc_run_fixture": "NPC run speeds are explicit diagnostic fixtures. Mio/Ren 3.2m/s and Haru 4.5m/s match the courtyard quick option; Aoi/Tanaka/Kazuko runs do not claim daily schedule use.", "image_policy": "Native viewport readbacks resized to 320x180; PNG encoding occurs only after that character's recording has stopped. Intervals include readback cost and are not performance benchmarks.", "failures": failures, "cases": reports}
	var file: FileAccess = FileAccess.open(output.path_join("transition-gait.json"), FileAccess.WRITE)
	if file == null:
		failures.append("could not write transition-gait.json")
	else:
		file.store_string(JSON.stringify(report))
	for failure: String in failures: qa.get("failures").append(failure)
	print("CHARACTER_TRANSITION_QA ", JSON.stringify({"cases": reports.size(), "elapsed_seconds": report.elapsed_seconds, "failures": failures, "output": output}))

func capture_character(qa: Node, id: String, output: String) -> void:
	qa.call("choose", id, Vector3(-14, .03, -10))
	var actor: Node3D = qa.get("actor") as Node3D
	var model: Node3D = qa.get("model") as Node3D
	var controller: CharAnim = qa.get("anim") as CharAnim
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or not controller.valid():
		failures.append(id + ": missing actual rig or animation controller")
		return
	var original_speed := 0.0
	if actor is Player:
		var player: Player = actor as Player
		player.frozen = false
		player.velocity = Vector3.ZERO
		player.auto_move = Vector3.ZERO
		player.auto_run = false
		player.set_facing(PI * .5)
		player.set_physics_process(true)
	else:
		var npc: NPC = actor as NPC
		original_speed = npc.speed
		npc.hold = false
		npc.talking = false
		npc._idle_t = 10000
		npc.set_yaw(PI * .5)
		npc.set_process(true)
		var hidden_player: Player = (qa.get("main") as Node3D).get("player") as Player
		hidden_player.global_position = Vector3(-41, .1, -9.5)
	controller._oneshot = ""
	controller.set_idle("idle", true)
	controller.ap.speed_scale = 1.0
	for warmup_frame: int in 4:
		await qa.get_tree().process_frame
	var continuous: SkeletonModifier3D = CONTINUOUS.new()
	continuous.name = "CharacterTransitionFinalRootProbe"
	skeleton.add_child(continuous)
	var ground: Dictionary = actor.get_meta("qa_floor_support", {})
	continuous.call("prepare", model, actor, controller.ap, float(ground.get("render_height", actor.global_position.y)))
	var bone_probe: SkeletonModifier3D = BONES.new()
	bone_probe.name = "CharacterTransitionFinalBoneProbe"
	skeleton.add_child(bone_probe)
	bone_probe.call("prepare", model)
	bone_probe.set("measure_bones", true)
	continuous.call("begin")
	var foot_debug: Node = model.find_child("CharacterFootSupport", true, false)
	if foot_debug != null: foot_debug.set("qa_trace_enabled", true)
	var natural_debug: Node = model.find_child("NaturalLocomotionPose", true, false)
	if natural_debug != null: natural_debug.set("qa_trace_enabled", true)
	var record: Dictionary = {"character": id, "fixture": "real_player_auto_move" if actor is Player else "real_NPC_walk_safe_and_cancel_with_explicit_run_speed", "run_speed_fixture_mps": RUN_SPEEDS.get(id, null), "commands": [], "bone_layout": [], "full_bone_samples": [], "images": [], "sampling_failures": 0, "start_position": vector(actor.global_position)}
	var images: Array[Dictionary] = []
	record["expected_bone_count"] = skeleton.get_bone_count()
	await stage(qa, actor, controller, continuous, bone_probe, record, images, "idle", .25, original_speed)
	await stage(qa, actor, controller, continuous, bone_probe, record, images, "walk", .70, original_speed)
	await stage(qa, actor, controller, continuous, bone_probe, record, images, "run", 1.05, original_speed)
	await stage(qa, actor, controller, continuous, bone_probe, record, images, "walk_after_run", .90, original_speed)
	await stage(qa, actor, controller, continuous, bone_probe, record, images, "stop", .55, original_speed)
	for gesture: String in ["wave", "bow"]:
		# Include the stationary preparation and full return to idle; requesting
		# the next gesture while the previous return still blends hides its end.
		var duration: float = controller.ap.get_animation(gesture).length + 1.0
		await stage(qa, actor, controller, continuous, bone_probe, record, images, gesture, duration, original_speed)
	continuous.set("recording", false)
	if foot_debug != null: foot_debug.set("qa_trace_enabled", false)
	if natural_debug != null: natural_debug.set("qa_trace_enabled", false)
	stop(actor)
	if actor is NPC:
		(actor as NPC).speed = original_speed
		actor.set_process(false)
	else:
		actor.set_physics_process(false)
	var frames: Array = (continuous.get("rows") as Array).duplicate(true)
	record["frames"] = frames
	record["end_position"] = vector(actor.global_position)
	record["summary"] = summarize(frames)
	if frames.size() < 30: failures.append(id + ": fewer than 30 final transition samples")
	if int(record.sampling_failures) > 0: failures.append(id + ": full bone/continuous probe frame pairing failed %d times" % int(record.sampling_failures))
	var seen: Dictionary = (record.summary as Dictionary).get("clips", {})
	for required: String in ["idle", "walk", "run", "wave", "bow"]:
		if not seen.has(required): failures.append(id + ": actual transition fixture never played " + required)
	continuous.queue_free()
	bone_probe.queue_free()
	var image_folder: String = output.path_join("transitions-" + id)
	DirAccess.make_dir_recursive_absolute(image_folder)
	for image_index: int in images.size():
		var image_record: Dictionary = images[image_index]
		var filename: String = "%04d.png" % image_index
		var save_error: Error = (image_record.image as Image).save_png(image_folder.path_join(filename))
		if save_error != OK: failures.append(id + ": could not encode transition image " + filename)
		image_record.erase("image")
		image_record["file"] = filename
		(record.images as Array).append(image_record)
	record["image_folder"] = image_folder.get_file()
	reports.append(record)
	print("CHARACTER_TRANSITION_CASE ", JSON.stringify({"character": id, "frames": frames.size(), "full_bone_samples": (record.full_bone_samples as Array).size(), "images": images.size(), "sampling_failures": record.sampling_failures, "clips": record.summary.clips, "largest_consecutive_frame_deltas": record.summary.largest_consecutive_frame_deltas}))

func stop(actor: Node3D) -> void:
	if actor is Player:
		(actor as Player).auto_move = Vector3.ZERO
		(actor as Player).auto_run = false
	else:
		(actor as NPC).cancel_safe_walk()

func stage(qa: Node, actor: Node3D, controller: CharAnim, continuous: SkeletonModifier3D, bone_probe: SkeletonModifier3D, record: Dictionary, images: Array[Dictionary], action: String, duration: float, walk_speed: float) -> void:
	if Time.get_ticks_msec() >= driver_deadline: return
	var began: int = Time.get_ticks_usec()
	var record_origin: int = int(continuous.get("began_usec"))
	(record.commands as Array).append({"action": action, "elapsed_s": (began - record_origin) / 1000000.0, "position": vector(actor.global_position), "clip_before_command": controller.ap.current_animation, "duration_requested_s": duration})
	if action == "walk":
		if actor is Player:
			(actor as Player).auto_move = Vector3.RIGHT
			(actor as Player).auto_run = false
		else:
			var walking: NPC = actor as NPC
			walking.speed = walk_speed
			walking.walk_safe([walking.global_position + Vector3.RIGHT * 22.0])
	elif action == "run":
		if actor is Player: (actor as Player).auto_run = true
		else: (actor as NPC).speed = float(RUN_SPEEDS[str(record.character)])
	elif action == "walk_after_run":
		if actor is Player: (actor as Player).auto_run = false
		else: (actor as NPC).speed = walk_speed
	elif action == "stop":
		stop(actor)
	elif action in ["wave", "bow"]:
		if actor is NPC: (actor as NPC).gesture(action)
		else: controller.play_once(action)
	var last_image_usec := 0
	var previous_clip := ""
	while Time.get_ticks_usec() - began < int(duration * 1000000.0) and Time.get_ticks_msec() < driver_deadline:
		var requested: int = bone_probe.call("request")
		qa.call("look", "right")
		await qa.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var applied: Dictionary = (bone_probe.get("result") as Dictionary).duplicate(true)
		var continuous_rows: Array = continuous.get("rows")
		var latest: Dictionary = continuous_rows.back() if not continuous_rows.is_empty() else {}
		var same_frame: bool = int(bone_probe.get("completed_request")) == requested and int(applied.get("request_id", -1)) == requested and int(applied.get("applied_frame", -1)) > int(applied.get("request_frame", -1)) and int(applied.get("applied_frame", -1)) == int(latest.get("frame", -2)) and int(latest.get("frame", -2)) == Engine.get_process_frames()
		same_frame = same_frame and str(applied.get("clip", "")) == str(latest.get("clip", "")) and absf(float(applied.get("clip_time", INF)) - float(latest.get("clip_time", -INF))) < .00001
		if same_frame:
			applied["commanded_action"] = action
			applied["root_position"] = latest.actor_position
			var bone_layout: Array = record.bone_layout
			var first_layout: bool = bone_layout.is_empty()
			var transforms: Array = []
			for bone_row: Dictionary in applied.bones:
				if first_layout: bone_layout.append({"name": bone_row.name, "parent": bone_row.parent})
				var transform: Array = []
				transform.append_array(bone_row.position as Array)
				for axis: Array in bone_row.basis: transform.append_array(axis)
				transforms.append(transform)
			var continuous_transforms: Array = latest.get("bone_transforms", [])
			var pose_difference := 0.0
			if continuous_transforms.size() != transforms.size() or transforms.size() != int(record.expected_bone_count): pose_difference = INF
			else:
				for bone_index: int in transforms.size():
					if (transforms[bone_index] as Array).size() != 12 or (continuous_transforms[bone_index] as Array).size() != 12:
						pose_difference = INF
						break
					for component: int in 12:
						pose_difference = maxf(pose_difference, absf(float(transforms[bone_index][component]) - float(continuous_transforms[bone_index][component])))
			applied["maximum_transform_difference_from_continuous"] = pose_difference
			if pose_difference > .00001: record["sampling_failures"] = int(record.sampling_failures) + 1
			applied["bone_transforms"] = transforms
			applied.erase("bones")
			(record.full_bone_samples as Array).append(applied)
		else:
			record["sampling_failures"] = int(record.sampling_failures) + 1
		var now: int = Time.get_ticks_usec()
		var actual_clip: String = str(latest.get("clip", ""))
		if same_frame and (now - last_image_usec >= 90000 or actual_clip != previous_clip):
			var image: Image = qa.get_viewport().get_texture().get_image()
			image.resize(320, 180, Image.INTERPOLATE_LANCZOS)
			images.append({"image": image, "elapsed_s": (now - record_origin) / 1000000.0, "commanded_action": action, "clip": actual_clip, "phase": latest.get("phase", null), "final_process_frame": latest.frame, "render_process_frame": Engine.get_process_frames(), "position": latest.actor_position})
			last_image_usec = now
		previous_clip = actual_clip

func summarize(frames: Array) -> Dictionary:
	var events: Array[Dictionary] = []
	var clips: Dictionary = {}
	var maxima: Dictionary = {}
	var path_length := 0.0
	for watched: String in WATCH: maxima[watched] = {"actor_relative_step_m": 0.0, "world_step_m": 0.0, "vertical_step_m": 0.0}
	for index: int in frames.size():
		var current: Dictionary = frames[index]
		var clip: String = str(current.clip)
		clips[clip] = int(clips.get(clip, 0)) + 1
		if index == 0: continue
		var previous: Dictionary = frames[index - 1]
		var root_delta: Vector3 = point(current.actor_position) - point(previous.actor_position)
		path_length += root_delta.length()
		var dt: float = float(current.elapsed_s) - float(previous.elapsed_s)
		var deltas: Dictionary = {"dt_s": dt, "root_step_m": root_delta.length(), "joints": {}}
		for joint: String in WATCH:
			if not current.joints.has(joint) or not previous.joints.has(joint): continue
			var world_delta: Vector3 = point(current.joints[joint]) - point(previous.joints[joint])
			var relative_delta: Vector3 = world_delta - root_delta
			var values: Dictionary = {"world_step_m": world_delta.length(), "actor_relative_step_m": relative_delta.length(), "vertical_step_m": relative_delta.y, "actor_relative_velocity_mps": relative_delta.length() / dt if dt > .000001 else null}
			deltas.joints[joint] = values
			var maximum: Dictionary = maxima[joint]
			maximum.world_step_m = maxf(float(maximum.world_step_m), world_delta.length())
			maximum.actor_relative_step_m = maxf(float(maximum.actor_relative_step_m), relative_delta.length())
			maximum.vertical_step_m = maxf(float(maximum.vertical_step_m), absf(relative_delta.y))
		current["delta_from_previous"] = deltas
		if clip != str(previous.clip):
			events.append({"from": previous.clip, "to": clip, "elapsed_s": current.elapsed_s, "before_frame": previous.frame, "after_frame": current.frame, "before_phase": previous.phase, "after_phase": current.phase, "immediate_delta": deltas, "window_deltas": []})
	for event: Dictionary in events:
		for frame: Dictionary in frames:
			if absf(float(frame.elapsed_s) - float(event.elapsed_s)) <= .25 and frame.has("delta_from_previous"):
				(event.window_deltas as Array).append({"frame": frame.frame, "elapsed_s": frame.elapsed_s, "clip": frame.clip, "delta": frame.delta_from_previous})
	return {"frame_count": frames.size(), "actual_path_length_m": path_length, "clips": clips, "clip_changes": events, "largest_consecutive_frame_deltas": maxima, "interpretation": "No motion-quality threshold is assumed. Compare native images and both root-relative jump magnitude and elapsed frame time, especially the +/-250ms windows around actual clip changes."}
