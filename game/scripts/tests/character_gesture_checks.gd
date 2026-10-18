extends RefCounted
## Real controller playback and final modifier poses, including an immediate
## run/stop/gesture request. No animation seek or manual animation advance.
const IDS: Array[String] = ["sora", "ren", "haru", "mio", "aoi", "tanaka", "kazuko"]
const LOWER: Array[String] = ["hips", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]
const UPPER: Array[String] = ["chest", "head", "upper.L", "fore.L", "hand.L", "upper.R", "fore.R", "hand.R"]
const POSITION_LIMIT := .001
const ANGLE_LIMIT := .2
var t: Node
var main: Node

class FinalGestureProbe:

	extends SkeletonModifier3D
	var actor: Node3D
	var animation: AnimationPlayer
	var frame := -1
	var result: Dictionary = {}

	func _process_modification() -> void:
		var skeleton: Skeleton3D = get_skeleton()
		var lower: Dictionary = {}
		var upper: Dictionary = {}
		for label: String in ["hips", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]:
			var index: int = LivingPose.bone(skeleton, label)
			if index < 0: continue
			lower[label] = {"position": skeleton.to_global(skeleton.get_bone_global_pose(index).origin) - actor.global_position, "rotation": skeleton.get_bone_pose_rotation(index)}
		for upper_label: String in ["chest", "head", "upper.L", "fore.L", "hand.L", "upper.R", "fore.R", "hand.R"]:
			var upper_index: int = LivingPose.bone(skeleton, upper_label)
			if upper_index >= 0: upper[upper_label] = skeleton.get_bone_pose_rotation(upper_index)
		frame = Engine.get_process_frames()
		result = {"frame": frame, "clip": animation.current_animation, "time": animation.current_animation_position, "lower": lower, "upper": upper, "root": actor.global_position}

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, passed: bool, detail: Dictionary) -> void:
	t.check("CHARACTER_GESTURES", label, passed, JSON.stringify(detail))

func sample(controller: CharAnim, probe: FinalGestureProbe, speed: float = 0.0) -> Dictionary:
	var requested: int = Engine.get_process_frames()
	controller.update(speed)
	for attempt: int in 8:
		await t.get_tree().process_frame
		controller.update(speed)
		if probe.frame > requested:
			var measured: Dictionary = probe.result.duplicate(true)
			measured["fresh"] = measured.lower.size() == LOWER.size() and measured.upper.size() == UPPER.size()
			return measured
	return {"fresh": false}

func settle(controller: CharAnim, probe: FinalGestureProbe, seconds: float, speed: float = 0.0) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var last: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		last = await sample(controller, probe, speed)
	return last

func difference(reference: Dictionary, measured: Dictionary) -> Dictionary:
	if not bool(reference.get("fresh", false)) or not bool(measured.get("fresh", false)):
		return {"position_m": INF, "rotation_deg": INF}
	var position := 0.0
	var angle := 0.0
	for label: String in LOWER:
		position = maxf(position, (reference.lower[label].position as Vector3).distance_to(measured.lower[label].position as Vector3))
		angle = maxf(angle, rad_to_deg((reference.lower[label].rotation as Quaternion).angle_to(measured.lower[label].rotation as Quaternion)))
	return {"position_m": position, "rotation_deg": angle}

func gesture(controller: CharAnim, probe: FinalGestureProbe, reference: Dictionary, clip: String) -> Dictionary:
	if not bool(reference.get("fresh", false)):
		return {"ok": false, "reason": "no fresh final neutral reference"}
	var accepted: bool = controller.play_once(clip)
	var busy_on_request: bool = controller.busy()
	var length: float = controller.ap.get_animation(clip).length
	var deadline: int = Time.get_ticks_msec() + int((length + 1.8) * 1000.0)
	var saw_clip := false
	var completed := false
	var fresh := bool(reference.get("fresh", false))
	var samples := 0
	var empty_samples := 0
	var max_time := 0.0
	var max_position := 0.0
	var max_rotation := 0.0
	var upper_motion := 0.0
	var returning_since := -1
	while Time.get_ticks_msec() < deadline:
		var pose: Dictionary = await sample(controller, probe)
		fresh = fresh and bool(pose.get("fresh", false))
		if not bool(pose.get("fresh", false)): continue
		if str(pose.clip) == clip:
			saw_clip = true
			max_time = maxf(max_time, float(pose.time))
			for label: String in UPPER:
				upper_motion = maxf(upper_motion, rad_to_deg((reference.upper[label] as Quaternion).angle_to(pose.upper[label] as Quaternion)))
		if not saw_clip: continue
		var error: Dictionary = difference(reference, pose)
		max_position = maxf(max_position, float(error.position_m))
		max_rotation = maxf(max_rotation, float(error.rotation_deg))
		samples += 1
		if str(pose.clip) == "": empty_samples += 1
		if str(pose.clip) == "idle" and not controller.busy():
			if returning_since < 0: returning_since = Time.get_ticks_msec()
			if Time.get_ticks_msec() - returning_since >= 300:
				completed = true
				break
	var passed: bool = accepted and busy_on_request and fresh and saw_clip and completed and samples >= 10 and max_time > length * .6 and upper_motion > 5.0 and max_position <= POSITION_LIMIT and max_rotation <= ANGLE_LIMIT
	return {"ok": passed, "accepted": accepted, "busy_on_request": busy_on_request, "fresh": fresh, "saw_clip": saw_clip, "completed_to_idle": completed, "samples": samples, "empty_samples": empty_samples, "actual_clip_time_max": max_time, "clip_length": length, "upper_motion_deg": upper_motion, "max_lower_position_m": max_position, "max_lower_local_rotation_deg": max_rotation, "limits": {"position_m": POSITION_LIMIT, "rotation_deg": ANGLE_LIMIT}}

func wait_gesture(controller: CharAnim, probe: FinalGestureProbe, clip: String) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + 1800
	var last: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		last = await sample(controller, probe)
		if bool(last.get("fresh", false)) and str(last.clip) == clip and float(last.time) > .15: return last
	return last

func loop_gesture(controller: CharAnim, probe: FinalGestureProbe, support: Node, reference: Dictionary, clip: String) -> Dictionary:
	# Exercise NPC.set_pose's persistent set_idle path, with real playback.
	# Three observed time wraps prove three complete cycles, not a long wait
	# on a stopped first clip. The fourth cycle must keep the same hold.
	controller.set_idle(clip)
	controller.update(0.0)
	var busy_on_request: bool = controller.busy()
	var length: float = controller.ap.get_animation(clip).length
	var deadline: int = Time.get_ticks_msec() + int((length * 3.8 + 2.0) * 1000.0)
	var saw_clip := false
	var fresh: bool = bool(reference.get("fresh", false))
	var cycles := 0
	var samples := 0
	var last_time := -1.0
	var max_position := 0.0
	var max_rotation := 0.0
	var upper_motion := 0.0
	var held_throughout := true
	var busy_after_first := false
	var idle_after_start := 0
	while Time.get_ticks_msec() < deadline and cycles < 3:
		var measured: Dictionary = await sample(controller, probe)
		fresh = fresh and bool(measured.get("fresh", false))
		if not bool(measured.get("fresh", false)): continue
		if str(measured.clip) == clip:
			saw_clip = true
			var at: float = float(measured.time)
			if last_time > length * .6 and at < length * .4 and at < last_time - length * .5:
				cycles += 1
			last_time = at
			for label: String in UPPER:
				upper_motion = maxf(upper_motion, rad_to_deg((reference.upper[label] as Quaternion).angle_to(measured.upper[label] as Quaternion)))
		if not saw_clip: continue
		var error: Dictionary = difference(reference, measured)
		max_position = maxf(max_position, float(error.position_m))
		max_rotation = maxf(max_rotation, float(error.rotation_deg))
		held_throughout = held_throughout and support.has_method("gesture_pose_held") and bool(support.call("gesture_pose_held"))
		if cycles >= 1: busy_after_first = busy_after_first or controller.busy()
		if str(measured.clip) == "idle": idle_after_start += 1
		samples += 1
	var passed: bool = busy_on_request and fresh and saw_clip and cycles >= 3 and samples >= 30 and held_throughout and not busy_after_first and idle_after_start == 0 and controller.idle_clip == clip and upper_motion > 5.0 and max_position <= POSITION_LIMIT and max_rotation <= ANGLE_LIMIT
	return {"ok": passed, "entry": "set_idle(" + clip + ")", "busy_on_request": busy_on_request, "fresh": fresh, "saw_clip": saw_clip, "complete_cycles": cycles, "samples": samples, "clip_length": length, "held_throughout": held_throughout, "busy_after_first_cycle": busy_after_first, "idle_frames_between_loops": idle_after_start, "upper_motion_deg": upper_motion, "max_lower_position_m": max_position, "max_lower_local_rotation_deg": max_rotation, "limits": {"position_m": POSITION_LIMIT, "rotation_deg": ANGLE_LIMIT}}

func exit_loop_gesture(controller: CharAnim, probe: FinalGestureProbe, support: Node, reference: Dictionary) -> Dictionary:
	# No interrupt/reset: the public standing target returns through the
	# normal idle blend, after which FootSupport must release the held cache.
	controller.set_idle("idle")
	var deadline: int = Time.get_ticks_msec() + 1400
	var returned_since := -1
	var released := false
	var fresh := true
	var samples := 0
	var measured: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		measured = await sample(controller, probe)
		fresh = fresh and bool(measured.get("fresh", false))
		if not bool(measured.get("fresh", false)): continue
		var held: bool = support.has_method("gesture_pose_held") and bool(support.call("gesture_pose_held"))
		if str(measured.clip) == "idle" and not controller.busy() and not held and not bool(support.call("gesture_request_active")):
			if returned_since < 0: returned_since = Time.get_ticks_msec()
			if Time.get_ticks_msec() - returned_since >= 300:
				released = true
				break
		else:
			returned_since = -1
		samples += 1
	var error: Dictionary = difference(reference, measured)
	var passed: bool = fresh and released and controller.idle_clip == "idle" and float(error.position_m) <= POSITION_LIMIT and float(error.rotation_deg) <= ANGLE_LIMIT
	return {"ok": passed, "entry": "set_idle(idle) without interrupt", "fresh": fresh, "released_to_stable_idle": released, "samples": samples, "clip": measured.get("clip", ""), "busy": controller.busy(), "lower_idle_error": error}

func run() -> void:
	var old_max_fps: int = Engine.max_fps
	Engine.max_fps = 120
	for id: String in IDS:
		var actor: Node3D = main.player if id == "sora" else main.npcs[id]
		var model: Node3D = actor.get("model") as Node3D
		var controller: CharAnim = actor.get("anim") as CharAnim
		var fixture_run_speed: float = maxf(controller.run_speed, controller.run_above + .25)
		var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
		var support: Node = skeleton.get_node("CharacterFootSupport")
		var saved: Dictionary = {"position": actor.global_position, "visible": actor.visible, "process": actor.is_processing(), "physics": actor.is_physics_processing(), "model_transform": model.transform, "clip": controller.ap.current_animation, "time": controller.ap.current_animation_position, "speed": controller.ap.speed_scale, "state": controller._state, "oneshot": controller._oneshot, "idle": controller.idle_clip}
		if actor is Player:
			saved["model_root"] = (actor as Player).model_root.transform
			(actor as Player).model_root.rotation = Vector3.ZERO
		else:
			saved["home"] = (actor as NPC).home
			saved["moving"] = (actor as NPC)._moving
			saved["path"] = (actor as NPC)._path.duplicate()
			saved["move_speed"] = (actor as NPC)._move_speed
			saved["move_heading"] = (actor as NPC)._move_heading
			saved["yaw"] = (actor as NPC)._yaw
			(actor as NPC).home = false
			(actor as NPC)._moving = false
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.visible = true
		actor.global_position = Vector3(-8, .01, -10)
		model.rotation = Vector3.ZERO
		var probe := FinalGestureProbe.new()
		probe.name = "CharacterGestureFinalProbe"
		probe.actor = actor
		probe.animation = controller.ap
		skeleton.add_child(probe)
		for clip: String in ["wave", "bow"]:
			controller.set_idle("idle", true)
			var reference: Dictionary = await settle(controller, probe, .65)
			var idle_result: Dictionary = await gesture(controller, probe, reference, clip)
			check(id + " idle to " + clip + " keeps one lower pose through the actual gesture and idle return", bool(idle_result.ok), idle_result)
			controller.set_idle("idle", true)
			reference = await settle(controller, probe, .65)
			await settle(controller, probe, .40, fixture_run_speed)
			controller.update(0.0)
			var moving_result: Dictionary = await gesture(controller, probe, reference, clip)
			check(id + " run stop same-frame " + clip + " request waits for neutral legs before the upper gesture", bool(moving_result.ok), moving_result)
		controller.set_idle("idle", true)
		var cancellation_reference: Dictionary = await settle(controller, probe, .65)
		controller.play_once("wave")
		var before_cancel: Dictionary = await wait_gesture(controller, probe, "wave")
		var running: Dictionary = await settle(controller, probe, .35, fixture_run_speed)
		var cancel_error: Dictionary = difference(cancellation_reference, running) if bool(running.get("fresh", false)) else {}
		var cancel_stats: Dictionary = support.call("performance")
		check(id + " moving cancels the gesture and releases its lower-body hold", bool(before_cancel.get("fresh", false)) and bool(running.get("fresh", false)) and str(running.get("clip", "")) == "run" and not controller.busy() and not bool(cancel_stats.get("gesture_lock_active", false)) and float(cancel_error.get("position_m", 0)) > .01, {"fresh": running.get("fresh", false), "clip": running.get("clip", ""), "busy": controller.busy(), "lock_active": cancel_stats.get("gesture_lock_active", false), "leg_motion": cancel_error})
		controller.set_idle("idle", true)
		await settle(controller, probe, .65)
		controller.play_once("bow")
		var before_place: Dictionary = await wait_gesture(controller, probe, "bow")
		var destination: Vector3 = actor.global_position + Vector3(1.5, 0, 0)
		if actor is NPC: (actor as NPC).place(destination, 0)
		else: actor.global_position = destination
		var placed: Dictionary = await sample(controller, probe)
		var placed_stats: Dictionary = support.call("performance")
		check(id + " placement invalidates the gesture hold instead of reusing the old ground context", bool(before_place.get("fresh", false)) and bool(placed.get("fresh", false)) and not bool(placed_stats.get("gesture_lock_active", false)) and (placed.root as Vector3).distance_to(destination) < .0001, {"fresh": placed.get("fresh", false), "root": placed.get("root"), "destination": destination, "lock_active": placed_stats.get("gesture_lock_active", false)})
		if id == "sora":
			controller.set_idle("idle", true)
			await settle(controller, probe, .65)
			var skipped_accepted: bool = controller.play_once("wave", 1000.0)
			var skipped_busy: bool = controller.busy()
			var skipped_deadline: int = Time.get_ticks_msec() + 1100
			var skipped_support: SkeletonModifier3D = support as SkeletonModifier3D
			var skipped_original_active: bool = skipped_support.active
			var skipped_started := false
			var skipped_resumed := false
			var skipped_hold_before_resume := false
			var skipped_updates_before := -1
			var skipped_updates_during := -1
			var skipped_begin_frame := -1
			var skipped_resume_frame := -1
			var skipped_fresh := true
			var skipped_saw_clip := false
			var skipped_samples := 0
			var skipped_pose: Dictionary = {}
			var skipped_request_frame: int = Engine.get_process_frames()
			var skipped_last_frame: int = skipped_request_frame
			while Time.get_ticks_msec() < skipped_deadline:
				controller.update(0)
				if not skipped_started and controller._pending_gesture == "" and controller._oneshot == "wave" and controller.ap.current_animation == "wave":
					# Test-only missed-callback injection. Pause synchronously after
					# real hold/start, before this frame's modifier can see wave.
					skipped_started = true
					skipped_begin_frame = Engine.get_process_frames()
					skipped_updates_before = int((support.call("performance") as Dictionary).updates)
					skipped_support.active = false
				if skipped_started and not skipped_resumed and not controller.busy() and controller.ap.current_animation == "idle":
					var skipped_before_resume: Dictionary = support.call("performance")
					skipped_updates_during = int(skipped_before_resume.updates) - skipped_updates_before
					skipped_hold_before_resume = bool(skipped_before_resume.get("gesture_lock_active", false))
					skipped_resume_frame = Engine.get_process_frames()
					skipped_resumed = true
					skipped_support.active = skipped_original_active
				await t.get_tree().process_frame
				if probe.frame > skipped_last_frame:
					skipped_pose = probe.result.duplicate(true)
					skipped_fresh = skipped_fresh and (skipped_pose.lower as Dictionary).size() == LOWER.size() and (skipped_pose.upper as Dictionary).size() == UPPER.size()
					skipped_saw_clip = skipped_saw_clip or str(skipped_pose.get("clip", "")) == "wave"
					skipped_samples += 1
					skipped_last_frame = probe.frame
			skipped_support.active = skipped_original_active
			var skipped_stats: Dictionary = support.call("performance")
			check("sora injected missed FootSupport callbacks still release the hold after real gesture completion", skipped_accepted and skipped_busy and skipped_original_active and skipped_started and skipped_resumed and skipped_hold_before_resume and skipped_updates_during == 0 and skipped_resume_frame > skipped_begin_frame and skipped_fresh and skipped_samples >= 10 and str(skipped_pose.get("clip", "")) == "idle" and not controller.busy() and not bool(skipped_stats.get("gesture_lock_active", false)), {"fixture": "Test-only FootSupport.active=false after synchronous real controller start, restored only after natural AP completion and normal idle return; no seek/advance or interrupt reset", "accepted": skipped_accepted, "busy_on_request": skipped_busy, "fresh": skipped_fresh, "samples": skipped_samples, "requested_scale": 1000.0, "started": skipped_started, "resumed_after_idle": skipped_resumed, "hold_before_resume": skipped_hold_before_resume, "foot_updates_while_omitted": skipped_updates_during, "begin_frame": skipped_begin_frame, "resume_frame": skipped_resume_frame, "independent_final_probe_saw_wave": skipped_saw_clip, "final_clip": skipped_pose.get("clip", ""), "busy": controller.busy(), "lock_active": skipped_stats.get("gesture_lock_active", false)})
		if id == "mio":
			for loop_clip: String in ["wave", "bow"]:
				controller.set_idle("idle", true)
				var loop_reference: Dictionary = await settle(controller, probe, .65)
				var loop_result: Dictionary = await loop_gesture(controller, probe, support, loop_reference, loop_clip)
				check("mio persistent " + loop_clip + " keeps nine neutral lower bones through at least three real cycles", bool(loop_result.ok), loop_result)
				var loop_exit: Dictionary = await exit_loop_gesture(controller, probe, support, loop_reference)
				check("mio persistent " + loop_clip + " releases its lower hold on normal set_idle idle", bool(loop_exit.ok), loop_exit)
		probe.queue_free()
		controller.set_idle("idle", true)
		actor.global_position = saved.position
		model.transform = saved.model_transform
		if actor is Player:
			(actor as Player).model_root.transform = saved.model_root
			(actor as Player).reset_physics_interpolation()
		else:
			(actor as NPC).home = bool(saved.home)
			(actor as NPC)._moving = bool(saved.moving)
			(actor as NPC)._path.assign(saved.path)
			(actor as NPC)._move_speed = float(saved.move_speed)
			(actor as NPC)._move_heading = saved.move_heading
			(actor as NPC)._yaw = float(saved.yaw)
		controller.ap.play(str(saved.clip), 0)
		controller.ap.seek(float(saved.time), true)
		controller.ap.speed_scale = float(saved.speed)
		controller._state = str(saved.state)
		controller._oneshot = str(saved.oneshot)
		controller.idle_clip = str(saved.idle)
		actor.visible = bool(saved.visible)
		actor.set_process(bool(saved.process))
		actor.set_physics_process(bool(saved.physics))
	Engine.max_fps = old_max_fps
