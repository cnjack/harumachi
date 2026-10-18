extends RefCounted
## A/B real rendered frame intervals with all three garment solvers in the same town scene.
const IDS: Array[String] = ["mio", "ren", "kazuko"]
const WALK_SPEEDS: Dictionary = {"mio": 1.25, "ren": 1.5, "kazuko": 1.5}
const RUN_SPEEDS: Dictionary = {"mio": 3.2, "ren": 3.2, "kazuko": 3.6}
var blocks: Array[Dictionary] = []
var failures: Array[String] = []
var originals: Dictionary = {}
var driver_deadline := 0

func vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func capture(qa: Node, output: String) -> void:
	var began: int = Time.get_ticks_msec()
	driver_deadline = began + 85000
	var previous_freeze: bool = NPC.freeze
	var previous_roaming: bool = NPC.roam_enabled
	var previous_camera_override: bool = bool(qa.get("camera_override"))
	NPC.freeze = false
	NPC.roam_enabled = false
	qa.call("outdoors")
	var game: Node3D = qa.get("main") as Node3D
	var player: Player = game.get("player") as Player
	player.visible = false
	player.set_physics_process(false)
	player.auto_move = Vector3.ZERO
	player.global_position = Vector3(-41, .1, -9.5)
	for unused: NPC in game.get("npcs").values():
		unused.set_process(false)
		unused.set_home(true)
	for id: String in IDS:
		var npc: NPC = game.get("npcs")[id]
		var support: SkeletonModifier3D = npc.model.find_child("CharacterGarmentSupport", true, false) as SkeletonModifier3D
		originals[id] = {"speed": npc.speed, "support_active": support.active if support != null else false, "support_enabled": bool(support.get("enabled")) if support != null else false}
		if support == null: failures.append(id + ": missing CharacterGarmentSupport in candidate")
	qa.set("camera_override", true)
	for round_index: int in 2:
		for scenario_index: int in 3:
			var action: String = ["idle", "walk", "run"][scenario_index]
			var order: Array[bool] = [true, false]
			if (round_index + scenario_index) % 2 != 0: order.reverse()
			for enabled: bool in order:
				if Time.get_ticks_msec() >= driver_deadline:
					failures.append("multi-character driver exceeded its 85 second capture budget")
					break
				await capture_block(qa, action, enabled, round_index)
	for restore_id: String in IDS:
		var restore_npc: NPC = game.get("npcs")[restore_id]
		restore_npc.cancel_safe_walk()
		restore_npc.speed = float(originals[restore_id].speed)
		restore_npc.set_process(false)
		var restore_support: SkeletonModifier3D = restore_npc.model.find_child("CharacterGarmentSupport", true, false) as SkeletonModifier3D
		if restore_support != null:
			restore_support.set("enabled", bool(originals[restore_id].support_enabled))
			restore_support.active = bool(originals[restore_id].support_active)
	qa.set("camera_override", previous_camera_override)
	NPC.freeze = previous_freeze
	NPC.roam_enabled = previous_roaming
	var report: Dictionary = {"engine": Engine.get_version_info().string, "elapsed_seconds": (Time.get_ticks_msec() - began) / 1000.0, "scope": "Mio, Ren and Kazuko simultaneously idle, walk or run using real NPC routes on three separate street lanes. Actor roots use ordinary authored town Y=0; visible ground remains handled by FootSupport. Two repetitions alternate solver-on/off ordering; each block warms up before measurement.", "control": "OFF first clears all local garment targets through enabled=false, then uses SkeletonModifier3D.active=false. Source geometry, materials, lighting, camera, three actors and routes are otherwise the same. OFF images would not be clothing-quality acceptance.", "timing": "Wall-clock intervals between consecutive native frame_post_draw callbacks. No screenshots, mesh probes or PNG encoding run during measured intervals. CPU solver timings are reported separately from native frame intervals. Idle animations continue at real playback speed.", "run_fixture": "Mio/Ren 3.2m/s match courtyard quick movement; Kazuko 3.6m/s is an explicit diagnostic fixture, not daily schedule use.", "interpretation": "Measured paired differences are reported without an assumed whole-scene performance PASS threshold. Warmup and order reversal reduce startup bias but do not establish a device-independent frame budget.", "failures": failures, "summary": summarize(), "blocks": blocks}
	var file: FileAccess = FileAccess.open(output.path_join("multi-character-performance.json"), FileAccess.WRITE)
	if file == null: failures.append("could not write multi-character-performance.json")
	else: file.store_string(JSON.stringify(report, "\t"))
	for failure: String in failures: qa.get("failures").append(failure)
	print("CHARACTER_MULTI_PERFORMANCE_QA ", JSON.stringify({"blocks": blocks.size(), "elapsed_seconds": report.elapsed_seconds, "failures": failures, "summary": report.summary, "output": output}))

func capture_block(qa: Node, action: String, enabled: bool, round_index: int) -> void:
	var game: Node3D = qa.get("main") as Node3D
	var actors: Array[NPC] = []
	var supports: Dictionary = {}
	for index: int in IDS.size():
		var id: String = IDS[index]
		var npc: NPC = game.get("npcs")[id]
		npc.cancel_safe_walk()
		npc.set_process(false)
		npc.set_home(false)
		# Ordinary town placements author their actor root at zero. The final
		# FootSupport modifier handles the separate visible painted ground.
		var at := Vector3(-14, 0, -9.7 - index * 1.3)
		npc.place(at, 90)
		npc.hold = false
		npc.talking = false
		npc._idle_t = 10000
		npc.set_pose("idle")
		npc.anim._oneshot = ""
		npc.anim.set_idle("idle", true)
		npc.anim.ap.speed_scale = 1.0
		npc.speed = float(RUN_SPEEDS[id] if action == "run" else WALK_SPEEDS[id])
		var support: SkeletonModifier3D = npc.model.find_child("CharacterGarmentSupport", true, false) as SkeletonModifier3D
		if support != null:
			supports[id] = support
			support.active = true
			support.set("enabled", enabled)
		actors.append(npc)
	# Allow the disabled solver to write zero weights before disabling callbacks;
	# inactive alone would keep the preceding ON block's corrective shape values.
	for clearing_frame: int in 3: await qa.get_tree().process_frame
	if not enabled:
		for disable_id: String in supports:
			var disabled: SkeletonModifier3D = supports[disable_id]
			var weights: PackedFloat32Array = disabled.get("amounts")
			for weight: float in weights:
				if absf(weight) > .000001: failures.append(disable_id + ": OFF control retained a nonzero local corrective")
			disabled.active = false
	for moving: NPC in actors:
		moving.set_process(true)
		if action != "idle": moving.walk_safe([moving.global_position + Vector3.RIGHT * 22.0])
	var warmup_began: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup_began < 1150000 and Time.get_ticks_msec() < driver_deadline:
		follow(qa, actors)
		await qa.get_tree().process_frame
		await RenderingServer.frame_post_draw
	for reset_id: String in supports: (supports[reset_id] as Node).call("reset_performance")
	var started_positions: Dictionary = {}
	for started_actor: NPC in actors: started_positions[started_actor.npc_id] = started_actor.global_position
	var began: int = Time.get_ticks_usec()
	var previous_usec := 0
	var intervals: Array[float] = []
	var frames: Array[Dictionary] = []
	var clips: Dictionary = {}
	while Time.get_ticks_usec() - began < 1500000 and Time.get_ticks_msec() < driver_deadline:
		follow(qa, actors)
		await qa.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		var interval: float = (now - previous_usec) / 1000.0 if previous_usec > 0 else 0.0
		if previous_usec > 0: intervals.append(interval)
		previous_usec = now
		var actual: Dictionary = {}
		for measured_actor: NPC in actors:
			var measured_clip: String = measured_actor.anim.ap.current_animation
			actual[measured_actor.npc_id] = {"position": vector(measured_actor.global_position), "clip": measured_clip, "clip_time": measured_actor.anim.ap.current_animation_position, "playback_scale": measured_actor.anim.ap.speed_scale, "moving": measured_actor.is_moving()}
			var clip_key: String = measured_actor.npc_id + "/" + measured_clip
			clips[clip_key] = int(clips.get(clip_key, 0)) + 1
		frames.append({"process_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(), "elapsed_s": (now - began) / 1000000.0, "render_interval_ms": interval if interval > 0 else null, "actors": actual})
	var statistics: Dictionary = {}
	var travel: Dictionary = {}
	for finished_actor: NPC in actors:
		var finished_id: String = finished_actor.npc_id
		travel[finished_id] = finished_actor.global_position.distance_to(started_positions[finished_id] as Vector3)
		if action != "idle" and float(travel[finished_id]) < .5: failures.append("%s %s round %d solver %s travelled less than .5m" % [finished_id, action, round_index, str(enabled)])
		if not clips.has(finished_id + "/" + action): failures.append("%s %s round %d solver %s never played requested actual clip" % [finished_id, action, round_index, str(enabled)])
		if supports.has(finished_id):
			var performance: Dictionary = (supports[finished_id] as Node).call("performance")
			performance["uncached_updates"] = int(performance.get("updates", 0)) - int(performance.get("pose_cache_hits", 0))
			performance["modifier_active"] = (supports[finished_id] as SkeletonModifier3D).active
			statistics[finished_id] = performance
		finished_actor.cancel_safe_walk()
		finished_actor.set_process(false)
	if frames.size() < 10: failures.append("%s round %d solver %s has fewer than ten rendered frames" % [action, round_index, str(enabled)])
	var block: Dictionary = {"scenario": action, "round": round_index, "solvers_enabled": enabled, "warmup_seconds": (began - warmup_began) / 1000000.0, "capture_seconds": (Time.get_ticks_usec() - began) / 1000000.0, "interval_statistics": interval_summary(intervals), "frame_intervals_ms": intervals, "frames": frames, "actual_travel_m": travel, "actual_clips": clips, "solvers": statistics}
	blocks.append(block)
	print("CHARACTER_MULTI_PERFORMANCE_BLOCK ", JSON.stringify({"scenario": action, "round": round_index, "enabled": enabled, "interval_statistics": block.interval_statistics, "actual_travel_m": travel, "solvers": statistics}))

func follow(qa: Node, actors: Array[NPC]) -> void:
	var centre := Vector3.ZERO
	for actor: NPC in actors: centre += actor.global_position
	centre /= maxi(actors.size(), 1)
	var camera: Camera3D = qa.get("camera") as Camera3D
	camera.size = 4.8
	camera.global_position = centre + Vector3(5.6, 2.3, 1.8)
	camera.look_at(centre + Vector3.UP)

func interval_summary(intervals: Array[float]) -> Dictionary:
	if intervals.is_empty(): return {"samples": 0}
	var ordered: Array[float] = intervals.duplicate()
	ordered.sort()
	var total := 0.0
	for interval: float in ordered: total += interval
	var mean: float = total / ordered.size()
	return {"samples": ordered.size(), "mean_ms": mean, "median_ms": ordered[ordered.size() / 2], "p95_ms": ordered[mini(ordered.size() - 1, ceili(ordered.size() * .95) - 1)], "maximum_ms": ordered.back(), "mean_fps": 1000.0 / mean if mean > 0 else 0.0}

func summarize() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for action: String in ["idle", "walk", "run"]:
		var enabled_intervals: Array[float] = []
		var disabled_intervals: Array[float] = []
		var pairs: Array[Dictionary] = []
		for repetition: int in 2:
			var enabled: Dictionary = {}
			var disabled: Dictionary = {}
			for block: Dictionary in blocks:
				if str(block.scenario) != action or int(block.round) != repetition: continue
				if bool(block.solvers_enabled):
					enabled = block
					enabled_intervals.append_array(block.frame_intervals_ms as Array[float])
				else:
					disabled = block
					disabled_intervals.append_array(block.frame_intervals_ms as Array[float])
			if not enabled.is_empty() and not disabled.is_empty():
				var enabled_stats: Dictionary = enabled.interval_statistics
				var disabled_stats: Dictionary = disabled.interval_statistics
				if enabled_stats.has("p95_ms") and disabled_stats.has("p95_ms"):
					pairs.append({"round": repetition, "on_minus_off_mean_ms": float(enabled_stats.mean_ms) - float(disabled_stats.mean_ms), "on_minus_off_p95_ms": float(enabled_stats.p95_ms) - float(disabled_stats.p95_ms), "on_over_off_p95": float(enabled_stats.p95_ms) / maxf(float(disabled_stats.p95_ms), .0001)})
		summaries.append({"scenario": action, "solver_on": interval_summary(enabled_intervals), "solver_off": interval_summary(disabled_intervals), "paired_repetitions": pairs})
	return summaries
