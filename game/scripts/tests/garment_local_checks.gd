extends RefCounted
## Full-source final-IK cloth regression. The runner opts in after importing
## accepted candidate GLBs; this file deliberately does not change run_tests.gd.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func run() -> void:
	load("res://scripts/tests/character_ray_precision_checks.gd").new(t).run()
	var context: Dictionary = {"region": main.world.region, "in_room": main.in_room, "room_kind": main.room_kind, "player_in_room": GameState.player_in_room}
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	for id: String in ["mio", "ren", "kazuko"]:
		await character_contract(id)
	await load("res://scripts/tests/garment_steady_guard_checks.gd").new(t).run()
	main.in_room = context.in_room
	main.room_kind = context.room_kind
	GameState.player_in_room = context.player_in_room
	main.world.set_region(str(context.region))
	main.world.set_indoor_look(bool(context.in_room))

func sample(npc: NPC, probe: SkeletonModifier3D, clip: String, phase: float) -> Dictionary:
	# The fixture's controller must agree with its AP clip. Otherwise Ren takes
	# an artificial fallback solely because QA left the controller in idle.
	npc.anim._oneshot = ""
	npc.anim._go(clip, 1.0)
	npc.anim.ap.play(clip, 0)
	npc.anim.ap.speed_scale = 0
	var clip_data: Animation = npc.anim.ap.get_animation(clip)
	var expected_time: float = clip_data.length * phase
	if clip_data.loop_mode != Animation.LOOP_NONE: expected_time = fposmod(expected_time, clip_data.length)
	npc.anim.ap.seek(expected_time, true)
	npc.anim.ap.advance(0)
	if npc.anim.clothing: npc.anim.clothing.reset()
	# This contract samples steady clip poses. Real-time transition QA leaves
	# NaturalLocomotionPose's fade active and checks its intermediate poses.
	var natural: Node = probe.get_skeleton().get_node_or_null("NaturalLocomotionPose")
	if natural != null and natural.has_method("finish_transition"): natural.call("finish_transition")
	# SkeletonModifier3D executes on process frames. Physics ticks alone can
	# return an earlier pose in a fast headless test, unlike native screenshots.
	for settle_frame: int in 3: await t.get_tree().process_frame
	var requested: int = probe.call("request", clip, expected_time)
	var measured: Dictionary = {}
	for capture_frame: int in 6:
		await t.get_tree().process_frame
		measured = (probe.get("result") as Dictionary).duplicate(true)
		if int(probe.get("completed_request")) == requested: break
	measured["fresh"] = int(probe.get("completed_request")) == requested and int(measured.get("request_id", -1)) == requested and int(measured.get("applied_frame", -1)) > int(measured.get("request_frame", -1)) and str(measured.get("clip", "")) == clip and absf(float(measured.get("clip_time", INF)) - expected_time) < .0001
	return measured

func character_contract(id: String) -> void:
	var npc: NPC = main.npcs[id]
	var saved: Dictionary = {"position": npc.global_position, "home": npc.home, "process": npc.is_processing(), "yaw": npc._yaw, "clip": npc.anim.ap.current_animation, "time": npc.anim.ap.current_animation_position, "speed": npc.anim.ap.speed_scale, "state": npc.anim._state, "oneshot": npc.anim._oneshot}
	npc.set_process(false)
	npc.set_home(false)
	npc.global_position = Vector3(-8, .010, -10)
	npc.set_yaw(0)
	var skeleton: Skeleton3D = npc.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var support: Node = npc.model.find_child("CharacterGarmentSupport", true, false)
	var probe: SkeletonModifier3D = load("res://scripts/tools/garment_qa_pose_probe.gd").new()
	probe.name = "FullSourceGarmentRegression"
	skeleton.add_child(probe)
	probe.call("prepare", npc.model)
	var coverage := support != null
	var clear := true
	var bounded := true
	var max_depth := 0.0
	var max_shift := 0.0
	var max_area_fraction := 0.0
	var bad: Array[String] = []
	var count := 0
	for clip: String in ["walk", "run", "dance", "idle", "wave", "bow", "look", "stretch", "tend", "talk", "cheer"]:
		var phases: Array[float] = [.5]
		if clip in ["walk", "run", "dance"]:
			phases.clear()
			for index: int in 17: phases.append(float(index) / 16.0)
			phases.append(.2)
			phases.append(.8)
			phases.sort()
		for phase: float in phases:
			var measured: Dictionary = await sample(npc, probe, clip, phase)
			count += 1
			coverage = coverage and bool(measured.get("fresh", false)) and int(measured.get("body_vertices", 0)) > 500 and int(measured.get("cloth_vertices", 0)) > 500 and int(measured.get("covered_body_vertices", 0)) > 100
			coverage = coverage and float(measured.get("body_local_template_delta_max_m", INF)) < .000001
			coverage = coverage and float(measured.get("uv_seam_template_gap_max_m", INF)) < .0001
			var layers: Dictionary = measured.get("layers", {})
			for layer: String in ["front", "back"]:
				var panel: Dictionary = layers.get(layer, {})
				coverage = coverage and int(panel.get("full_source_triangles", 0)) > 200
				var domains: Dictionary = measured.get("cloth_domains", {})
				var domain_preparation: Dictionary = (domains.get("preparation", {}) as Dictionary).get(layer, {})
				var pigment_count: int = int(domain_preparation.get("independent_pigment_source_triangles", 0))
				var support_count: int = int(domain_preparation.get("all_local_support_source_triangles", 0))
				var union_count: int = int(domain_preparation.get("union_source_triangles", 0))
				coverage = coverage and pigment_count > 200 and support_count > 200 and union_count >= pigment_count and union_count >= support_count
			var depth: float = float(measured.get("max_penetration_m", INF))
			var displacement: float = float(measured.get("max_local_displacement_m", INF))
			max_depth = maxf(max_depth, depth)
			max_shift = maxf(max_shift, displacement)
			max_area_fraction = maxf(max_area_fraction, float(measured.get("affected_cloth_area_fraction_over_1mm", 0)))
			if depth > .005:
				clear = false
				bad.append("%s %.4f depth %.5f" % [clip, phase, depth])
			# A 12cm template is a hard displacement cap, never a skin gap claim.
			# Area/p95 are emitted for human silhouette review, not silently accepted.
			bounded = bounded and displacement <= .1205
			print("GARMENT_FULL_SOURCE ", JSON.stringify({"id": id, "clip": clip, "phase": phase, "measurement": measured}))
	# Preserve the standard65 sample set, and independently retain the actual
	# continuous source-frame7238 failure as an explicit extra phase. No face
	# IDs enter either the runtime or the source-cloth classification.
	if id == "kazuko":
		var observed_phase: float = 0.787565664367262
		var observed: Dictionary = await sample(npc, probe, "run", observed_phase)
		var observed_depth: float = float(observed.get("max_penetration_m", INF))
		coverage = coverage and bool(observed.get("fresh", false)) and observed.has("cloth_domains")
		max_depth = maxf(max_depth, observed_depth)
		if observed_depth > .005:
			clear = false
			bad.append("run %.9f extra observed source-frame7238 depth %.5f" % [observed_phase, observed_depth])
		bounded = bounded and float(observed.get("max_local_displacement_m", INF)) <= .1205
		print("GARMENT_FULL_SOURCE_EXTRA ", JSON.stringify({"id": id, "clip": "run", "phase": observed_phase, "observed_source_frame": 7238, "scope": "explicit real continuous failure phase alongside unchanged65 standard samples", "measurement": observed}))
	t.check("GARMENT_LOCAL", id + " uses real source cloth and real leg/trouser coverage at all65 final IK samples", coverage and count == 65, "samples %d" % count)
	t.check("GARMENT_LOCAL", id + " full source triangles keep final real legs within original5mm penetration gate", clear and coverage, "max %.6fm; bad %s" % [max_depth, str(bad)])
	t.check("GARMENT_LOCAL", id + " local correction stays inside explicit12cm template envelope", bounded and coverage, "max %.6fm; affected area fraction %.4f; silhouette approval remains native" % [max_shift, max_area_fraction])
	var first_idle: Dictionary = await sample(npc, probe, "idle", .5)
	var first_shape: PackedFloat32Array = (support.get("amounts") as PackedFloat32Array).duplicate() if support != null else PackedFloat32Array()
	var first_points: PackedVector3Array = (probe.get("cloth_snapshot") as PackedVector3Array).duplicate()
	await sample(npc, probe, "run", .375)
	var second_idle: Dictionary = await sample(npc, probe, "idle", .5)
	var second_points: PackedVector3Array = probe.get("cloth_snapshot")
	var restored: bool = bool(first_idle.get("fresh", false)) and bool(second_idle.get("fresh", false)) and first_points.size() == second_points.size() and first_points.size() > 500
	var max_restore := 0.0
	for index: int in mini(first_points.size(), second_points.size()): max_restore = maxf(max_restore, first_points[index].distance_to(second_points[index]))
	restored = restored and max_restore < .001 and float(first_idle.get("max_penetration_m", INF)) <= .005 and float(second_idle.get("max_penetration_m", INF)) <= .005
	var current_shape: PackedFloat32Array = support.get("amounts") if support != null else PackedFloat32Array()
	for index: int in mini(first_shape.size(), current_shape.size()): restored = restored and absf(first_shape[index] - current_shape[index]) < .001
	var first_weights: Array[float] = []
	var returned_weights: Array[float] = []
	for weight: float in first_shape: first_weights.append(weight)
	for weight: float in current_shape: returned_weights.append(weight)
	print("GARMENT_IDLE_RESTORE ", JSON.stringify({"id": id, "first": first_idle, "returned": second_idle, "first_weights": first_weights, "returned_weights": returned_weights, "maximum_geometry_difference_m": max_restore}))
	# A physically necessary idle target can be nonzero. Returning to exactly
	# the same final geometry proves cleanup more strongly than all-zero weights.
	t.check("GARMENT_LOCAL", id + " idle geometry and contact restore after locomotion without demanding artificial zero clearance", restored, "max return difference %.6fm; source bone hashes %s / %s" % [max_restore, str(first_idle.get("bone_pose_hash", "missing")), str(second_idle.get("bone_pose_hash", "missing"))])
	var frozen: PackedFloat32Array = current_shape.duplicate()
	var stable := support != null
	for tick: int in 20:
		await t.frames(1)
		var weights: PackedFloat32Array = support.get("amounts") if support != null else PackedFloat32Array()
		stable = stable and weights.size() == frozen.size()
		for index: int in mini(weights.size(), frozen.size()): stable = stable and absf(weights[index] - frozen[index]) < .001
	t.check("GARMENT_LOCAL", id + " fixed final pose never accumulates corrective weights", stable)
	# Measure a steadily advancing clip after a correctly synchronized steady
	# fixture. Real transition blending has separate native coverage.
	await sample(npc, probe, "run", 0.0)
	if support != null: support.call("reset_performance")
	npc.anim.ap.speed_scale = 1
	await t.frames(90)
	var performance: Dictionary = support.call("performance") if support != null else {}
	var full_solves: int = int(performance.get("full_solve_updates", -1))
	var steady_updates: int = int(performance.get("steady_fast_updates", 0))
	var full_budget: bool = full_solves == 0 or float(performance.get("solve_p95_usec_recent_240", INF)) < 8000.0
	var steady_budget: bool = steady_updates == 0 or (bool(performance.get("steady_proof_match", false)) and float(performance.get("p95_usec_recent_240", INF)) < 8000.0)
	t.check("GARMENT_LOCAL", id + " continuously changing run reports verified full-solve or steady-fast latency within frame budget", full_solves >= 0 and full_solves + steady_updates >= 60 and full_budget and steady_budget, JSON.stringify(performance))
	probe.queue_free()
	npc.global_position = saved.position
	npc.set_yaw(float(saved.yaw))
	npc.set_home(bool(saved.home))
	npc.set_process(bool(saved.process))
	npc.anim._oneshot = ""
	npc.anim._go(str(saved.state), 1.0)
	npc.anim._oneshot = str(saved.oneshot)
	npc.anim.ap.play(str(saved.clip), 0)
	npc.anim.ap.seek(float(saved.time), true)
	npc.anim.ap.speed_scale = float(saved.speed)
