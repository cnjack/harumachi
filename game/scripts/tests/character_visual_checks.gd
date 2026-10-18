extends RefCounted
## Actual skinned shoe support while seated and resting, including every public seat type.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func run() -> void:
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	var original_position: Vector3 = main.player.global_position
	var original_facing: float = main.player._face_yaw
	var skeleton: Skeleton3D = main.player.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var probe: SkeletonModifier3D = load("res://scripts/tools/character_qa_pose_probe.gd").new()
	probe.name = "CharacterVisualTestProbe"
	skeleton.add_child(probe)
	probe.call("prepare", main.player.model)
	probe.set("measure_feet", true)
	var hip_support := true
	var standing_restored := true
	var details: Array[String] = []
	for seat_id: String in ["public_reading_0", "public_shared_seat", "public_cafe_0", "public_cafe_1"]:
		var room: String = "workroom" if seat_id.begins_with("public_reading") or seat_id == "public_shared_seat" else "bakery"
		if main.in_room: await main.exit_interior()
		await main.enter_interior(room)
		await t.frames(10)
		var seat: Interactable = main.world.interiors[room].find_child(seat_id, true, false) as Interactable
		var seated: bool = seat != null and main.story.public_life.sit(seat)
		skeleton.move_child(probe, skeleton.get_child_count() - 1)
		await t.frames(20)
		var soles: Dictionary = (probe.get("soles") as Dictionary).duplicate()
		var actor_y: float = main.player.global_position.y
		var left: float = float(soles.get("L", INF)) - actor_y
		var right: float = float(soles.get("R", INF)) - actor_y
		var foot_support: bool = seated and absf(left) < .02 and absf(right) < .02 and float(soles.get("pitch_error_L", INF)) < 8.0 and float(soles.get("pitch_error_R", INF)) < 8.0
		var drink := LivingAction.new()
		main.add_child(drink)
		drink.setup(main.player, "sip", "coffee")
		drink.duration = 1000
		drink.clock = 500
		skeleton.move_child(probe, skeleton.get_child_count() - 1)
		await t.frames(10)
		var sip_soles: Dictionary = probe.get("soles")
		foot_support = foot_support and absf(float(sip_soles.get("L", INF)) - actor_y) < .02 and absf(float(sip_soles.get("R", INF)) - actor_y) < .02 and float(sip_soles.get("pitch_error_L", INF)) < 8.0 and float(sip_soles.get("pitch_error_R", INF)) < 8.0
		foot_support = foot_support and drink.pose == null and drink.hand < 0
		t.check("CHARACTER_VISUAL", "both rendered shoes stay flat during seated rest without a hand-held drink at " + seat_id, foot_support, "L %.4fm / R %.4fm; pitch errors %.2f / %.2f deg; rest %.4f / %.4f" % [left, right, float(soles.get("pitch_error_L", INF)), float(soles.get("pitch_error_R", INF)), float(sip_soles.get("L", INF)) - actor_y, float(sip_soles.get("R", INF)) - actor_y])
		hip_support = hip_support and absf(main.story.public_life.pose.measured_hip_height - .57) < .02 and main.story.public_life.pose.measured_knee_forward > .20
		details.append("%s hips %.3f" % [seat_id, main.story.public_life.pose.measured_hip_height])
		drink.queue_free()
		await t.frames(1)
		main.story.public_life.stand(true)
		await t.frames(20)
		var joints: Dictionary = probe.get("joints")
		var hips: Array = joints.get("hips", [0, 0, 0])
		standing_restored = standing_restored and not main.player.seated and main.story.public_life.pose == null and float(hips[1]) - main.player.global_position.y > .75
	t.check("CHARACTER_VISUAL", "planting seated shoes keeps hips supported on all four chairs", hip_support, str(details))
	t.check("CHARACTER_VISUAL", "standing after each chair restores the actual standing skeleton", standing_restored)
	probe.queue_free()
	if main.in_room: await main.exit_interior()
	GameState.from_dict(saved)
	main.player.global_position = original_position
	main.player.set_facing(original_facing)
	main.player.reset_physics_interpolation()
	hand_tone_contract()
	await foot_support_contract()
	await dance_transition_contract()
	await bon_dancer_visibility_contract()
	road_paint_contract()
	await fishing_pose_contract()
	await apron_clearance_contract()

func fishing_pose_contract() -> void:
	var player: Player = main.player
	var original_position: Vector3 = player.global_position
	var original_facing: float = player._face_yaw
	var original_frozen: bool = player.frozen
	var original_physics: bool = player.is_physics_processing()
	var ap: AnimationPlayer = player.anim.ap
	var saved_clip: String = ap.current_animation
	var saved_time: float = ap.current_animation_position
	var saved_speed: float = ap.speed_scale
	player.set_physics_process(false)
	player.global_position=Vector3(-8,0,-10)
	player.set_facing(0)
	ap.play("idle",0);ap.speed_scale=0;ap.seek(.5,true)
	var sk: Skeleton3D = player.model.find_child("Skeleton3D",true,false) as Skeleton3D
	var probe: SkeletonModifier3D = load("res://scripts/tools/fishing_qa_pose_probe.gd").new()
	sk.add_child(probe);probe.call("prepare",player.model)
	await t.frames(3)
	var baseline: Dictionary = (probe.get("hand_centres") as Dictionary).duplicate()
	var view:=FishingView.new();main.add_child(view);view.setup(player,player.global_position+Vector3(0,-.3,3))
	probe.set("view",view);sk.move_child(probe,sk.get_child_count()-1)
	var session:=FishingSession.new("fish_river")
	var valid: bool = int(view.get("_hand_bone"))>=0
	var max_gap := 0.0
	var moved := true
	var sides_ok := true
	var min_right := INF
	var max_left := -INF
	var min_separation := INF
	for state: int in [FishingSession.State.READY,FishingSession.State.CAST,FishingSession.State.WAIT,FishingSession.State.REEL]:
		session.state=state;session.timer=.3
		view.update_view(session,.13)
		await t.frames(3)
		max_gap=maxf(max_gap,float(probe.get("rod_skin_gap")))
		var centres: Dictionary = probe.get("hand_centres")
		for side: String in ["L","R"]:moved=moved and centres.has(side) and (centres[side] as Vector3).distance_to(baseline[side])>.10
		var actual: Dictionary = probe.get("joints")
		var shoulder_centre: Vector3 = (actual["upper.R"] as Vector3).lerp(actual["upper.L"],.5)
		# Derive anatomical right from the real shoulders, independently of the
		# fishing solver's direction formula. Skinned hands must not swap sides.
		var anatomical_right: Vector3 = ((actual["upper.R"] as Vector3)-(actual["upper.L"] as Vector3)).normalized()
		var projected_r: float = ((centres.R as Vector3)-shoulder_centre).dot(anatomical_right)
		var projected_l: float = ((centres.L as Vector3)-shoulder_centre).dot(anatomical_right)
		min_right=minf(min_right,projected_r);max_left=maxf(max_left,projected_l);min_separation=minf(min_separation,projected_r-projected_l)
		sides_ok=sides_ok and projected_r>.035 and projected_l<0 and projected_r-projected_l>.10
	var first_crank: Vector3 = (probe.get("hand_centres") as Dictionary).L
	view.update_view(session,.42);await t.frames(3)
	var crank_delta: float = first_crank.distance_to((probe.get("hand_centres") as Dictionary).L)
	session.state=FishingSession.State.LANDED;view.update_view(session,0);await t.frames(3)
	var landed: Dictionary = (probe.get("hand_centres") as Dictionary).duplicate()
	view.queue_free();await t.frames(3)
	var closed: Dictionary = probe.get("hand_centres")
	var restored := true
	for side: String in ["L","R"]:restored=restored and (landed[side] as Vector3).distance_to(baseline[side])<.003 and (closed[side] as Vector3).distance_to(baseline[side])<.003
	t.check("CHARACTER_VISUAL","real Sora skin grips the rod without crossed arms reels with the other hand and restores after fishing",valid and moved and sides_ok and max_gap<.055 and crank_delta>.02 and restored,"hand resolved %s; arms move %s; sides %s (R %.4f L %.4f separation %.4f); rod/skin %.4fm; crank %.4fm; restored %s"%[valid,moved,sides_ok,min_right,max_left,min_separation,max_gap,crank_delta,restored])
	probe.queue_free()
	player.global_position=original_position;player.set_facing(original_facing);player.frozen=original_frozen;player.set_physics_process(original_physics)
	ap.play(saved_clip,0);ap.seek(saved_time,true);ap.speed_scale=saved_speed
	player.reset_physics_interpolation()

func real_curb(mesh: MeshInstance3D) -> bool:
	if not mesh.mesh is BoxMesh: return false
	var size: Vector3 = (mesh.mesh as BoxMesh).size
	return absf(size.x - 94.9) < .001 and absf(size.y - .06) < .001 and absf(size.z - .22) < .001

func visible_floor_height(at: Vector3) -> float:
	var audit: RefCounted = load("res://scripts/tests/placement_checks.gd").new(t)
	var height := -INF
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(main.world):
		if not mesh.is_visible_in_tree() or mesh.mesh.get_surface_count() == 0: continue
		var material: ShaderMaterial = mesh.get_active_material(0) as ShaderMaterial
		var ground: bool = material != null and material.shader != null and (material.shader.resource_path == "res://shaders/ground.gdshader" or (material.shader.resource_path == "res://shaders/material_options/surface.gdshader" and material.get_shader_parameter("surface_kind") == 4))
		if not ground and not real_curb(mesh): continue
		height = maxf(height, float(audit.call("vertical_hit", mesh, Vector2(at.x, at.z), .10)))
	return height

func road_paint_contract() -> void:
	var count := 0
	var valid := true
	var gaps: Array[float] = []
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(main.world):
		if not mesh.mesh is PlaneMesh: continue
		var size: Vector2 = (mesh.mesh as PlaneMesh).size
		if not size.is_equal_approx(Vector2(2.6, .14)): continue
		count += 1
		var gap: float = mesh.global_position.y - visible_floor_height(mesh.global_position)
		gaps.append(gap)
		valid = valid and gap >= -.0001 and gap <= .002
	t.check("CHARACTER_VISUAL", "real road paint PlaneMesh fragments stay within two millimetres of visible paving", valid and count > 10, "%d fragments; offsets %s" % [count, gaps])

func bon_dancer_visibility_contract() -> void:
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	var position: Vector3 = main.player.global_position
	var camera_state := Vector3(main.rig.yaw, main.rig.pitch, main.rig.dist)
	var instant: bool = main.ui.instant
	GameState.day = 17
	GameState.minute = 20.1 * 60
	GameState.phase = "prep"
	GameState.quests.Q00 = {"state": "done", "step": 2}
	main.ui.instant = true
	main.world.set_region("town")
	main.world.sync_festivals()
	main.update_npcs(true)
	var kazuko: NPC = main.npcs.kazuko
	kazuko.set_home(true)
	main.bon_odori_scene()
	var deadline: int = Time.get_ticks_msec() + 4000
	while kazuko.fest_key != "natsumatsuri:dance" and Time.get_ticks_msec() < deadline: await t.frames(1)
	var entered: bool = not kazuko.home and kazuko.is_visible_in_tree() and kazuko.anim.ap.current_animation == "dance"
	var ring_position: Vector3 = kazuko.global_position
	main.update_npcs(true)
	await t.frames(2)
	var stays: bool = main.dancing and not kazuko.home and kazuko.is_visible_in_tree() and kazuko.global_position.distance_to(ring_position) < .02 and kazuko.fest_key == "natsumatsuri:dance"
	while (main.dancing or main.story.cutscene) and Time.get_ticks_msec() < deadline: await t.frames(1)
	var returns: bool = not main.dancing and not main.story.cutscene and kazuko.home and not kazuko.visible and kazuko.fest_key == "" and not GameState.input_locked()
	t.check("CHARACTER_VISUAL", "a resident at home joins the real bon dance visibly survives schedule refresh and returns home afterward", entered and stays and returns, "entered %s; stays %s; returns %s" % [entered, stays, returns])
	GameState.from_dict(saved)
	main.player.global_position = position
	main.rig.yaw = camera_state.x
	main.rig.pitch = camera_state.y
	main.rig.dist = camera_state.z
	main.rig.snap()
	main.ui.instant = instant
	main.world.sync_festivals()
	main.update_npcs(true)

func dance_transition_contract() -> void:
	var npc: NPC = main.npcs.mio
	var controller: CharAnim = npc.anim
	var saved: Dictionary = {"clip": controller.ap.current_animation, "time": controller.ap.current_animation_position, "speed": controller.ap.speed_scale, "idle": controller.idle_clip, "state": controller._state, "oneshot": controller._oneshot, "fest": npc.fest_key, "greeted": npc._greeted_day, "position": npc.global_position, "home": npc.home, "talking": npc.talking, "moving": npc._moving, "process": npc.is_processing(), "yaw": npc._yaw, "idle_t": npc._idle_t, "end_idle": npc._end_idle}
	npc.set_process(false)
	npc._moving = false
	controller.play_once("look")
	npc.set_pose("dance")
	t.check("CHARACTER_VISUAL", "joining bon dance immediately cancels a previous single gesture", controller.ap.current_animation == "dance" and not controller.busy(), controller.ap.current_animation)
	npc.global_position = main.player.global_position + Vector3(2, 0, 0)
	npc.home = false
	npc.talking = false
	npc._moving = false
	npc.fest_key = "qa:dance"
	npc._greeted_day = GameState.day - 1
	controller._oneshot = ""
	controller._state = ""
	controller.idle_clip = "dance"
	controller.ap.play("dance", 0)
	npc._idle_life(.016)
	var protected: bool = controller.ap.current_animation == "dance" and npc._greeted_day != GameState.day
	npc.fest_key = ""
	controller._oneshot = ""
	controller._state = ""
	controller.idle_clip = "idle"
	controller.ap.play("idle", 0)
	npc._idle_life(.016)
	var greeting_queued: bool = npc._greeted_day == GameState.day and controller.busy()
	# The greeting must face the player and settle its final standing legs
	# before the upper-body gesture. This fixture disables NPC processing, so
	# drive its real controller until the deferred request actually plays.
	var greeting_deadline: int = Time.get_ticks_msec() + 2000
	while controller.ap.current_animation != "wave" and Time.get_ticks_msec() < greeting_deadline:
		controller.update(0)
		await t.get_tree().process_frame
	var greeting_returns: bool = controller.ap.current_animation == "wave" and npc._greeted_day == GameState.day
	t.check("CHARACTER_VISUAL", "group dancing defers the first greeting and restores it after the dance", protected and greeting_queued and greeting_returns, "protected %s; greeting queued %s; actual greeting restored %s" % [protected, greeting_queued, greeting_returns])
	await t.frames(20)
	controller.set_idle("idle", true)
	npc.fest_key = str(saved.fest)
	npc._greeted_day = int(saved.greeted)
	npc.global_position = saved.position
	npc.home = bool(saved.home)
	npc.talking = bool(saved.talking)
	npc._moving = bool(saved.moving)
	npc._idle_t = float(saved.idle_t)
	npc._end_idle = str(saved.end_idle)
	npc.set_yaw(float(saved.yaw))
	npc.set_process(bool(saved.process))
	controller.idle_clip = str(saved.idle)
	controller._state = str(saved.state)
	controller._oneshot = str(saved.oneshot)
	controller.ap.play(str(saved.clip), 0)
	controller.ap.seek(float(saved.time), true)
	controller.ap.speed_scale = float(saved.speed)

func support_sample(animation: CharAnim, clip: String, phase: float, probe: SkeletonModifier3D) -> Dictionary:
	animation.ap.play(clip, 0)
	animation.ap.speed_scale = 0
	var resource: Animation = animation.ap.get_animation(clip)
	var at: float = resource.length * phase
	if resource.loop_mode != Animation.LOOP_NONE: at = fposmod(at, resource.length)
	animation.ap.seek(at, true)
	animation.ap.advance(0)
	var natural: Node = probe.get_skeleton().get_node_or_null("NaturalLocomotionPose")
	if natural != null and natural.has_method("finish_transition"): natural.call("finish_transition")
	# Physics ticks can repeat an earlier modifier snapshot in headless tests.
	# Require the final modifier to acknowledge this exact source time later.
	for settle_frame: int in 3: await t.get_tree().process_frame
	var requested: int = probe.call("request", clip, at)
	var measured: Dictionary = {}
	for capture_frame: int in 8:
		await t.get_tree().process_frame
		if int(probe.get("completed_request")) != requested: continue
		measured = (probe.get("result") as Dictionary).duplicate(true)
		if int(measured.get("request_id", -1)) == requested: break
	var fresh: bool = int(measured.get("request_id", -1)) == requested and str(measured.get("clip", "")) == clip and absf(float(measured.get("clip_time", INF)) - at) < .0001 and int(measured.get("applied_frame", -1)) > int(measured.get("request_frame", -1))
	return {"soles": measured.get("soles", {}), "joints": measured.get("joints", {}), "fresh": fresh}

func foot_support_contract() -> void:
	var gait_ok := true
	var standing_ok := true
	var upper_ok := true
	var swing_ok := true
	var samples_fresh := true
	var gait_details: Array[String] = []
	var standing_details: Array[String] = []
	var invariant_details: Array[String] = []
	var swings := 0
	var fixtures: Array[Dictionary] = [
		{"name": "street", "at": Vector3(-8, 0, -10)},
		{"name": "plaza", "at": Vector3(0, 0, 12.2)},
		{"name": "grass", "at": Vector3(-47, 0, .5)},
		{"name": "curb", "at": Vector3(0, 0, -8)}]
	for measure_fixture: Dictionary in fixtures: measure_fixture["height"] = visible_floor_height(measure_fixture.at)
	var curb_box := AABB()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(main.world):
		if real_curb(mesh) and absf(mesh.global_position.z + 8) < .001: curb_box = mesh.global_transform * mesh.get_aabb()
	for id: String in ["sora", "ren", "haru", "mio", "aoi", "tanaka", "kazuko"]:
		var target: Node3D = main.player if id == "sora" else main.npcs[id]
		var source: Node3D = target.get("model") as Node3D
		var source_rig: Node = source.find_child("Rig", true, false)
		var flat_source: Dictionary = (source_rig.get_meta("extras", {}) as Dictionary).get("source_flat_floor_contact", {}) if source_rig != null else {}
		var verified_run: bool = int(flat_source.get("version", 0)) == 1 and "run" in flat_source.get("verified_flat_clips", [])
		var controller: CharAnim = target.get("anim") as CharAnim
		var saved: Dictionary = {"position": target.global_position, "visible": target.visible, "process": target.is_processing(), "physics": target.is_physics_processing(), "model_transform": source.transform, "clip": controller.ap.current_animation, "time": controller.ap.current_animation_position, "speed": controller.ap.speed_scale}
		target.set_process(false)
		target.set_physics_process(false)
		target.visible = true
		target.global_position = Vector3(-8, 0, -10)
		source.rotation.x = 0
		var sk: Skeleton3D = source.find_child("Skeleton3D", true, false) as Skeleton3D
		var support: SkeletonModifier3D = sk.get_node_or_null("CharacterFootSupport") as SkeletonModifier3D
		var probe: SkeletonModifier3D = load("res://scripts/tools/character_qa_pose_probe.gd").new()
		probe.name = "CharacterGroundingTestProbe"
		sk.add_child(probe)
		probe.call("prepare", source)
		probe.set("measure_feet", true)
		for fixture: Dictionary in fixtures:
			target.global_position = fixture.at
			probe.set("support_rect_enabled", fixture.name == "curb")
			probe.set("support_rect", Rect2(curb_box.position.x, curb_box.position.z, curb_box.size.x, curb_box.size.z))
			probe.set("support_height", curb_box.end.y)
			probe.set("base_support_height", float(fixtures[0].height))
			var lowest := INF
			for clip: String in ["walk", "run"]:
				for index: int in range(17):
					var gait_sample: Dictionary = await support_sample(controller, clip, index / 16.0, probe)
					samples_fresh = samples_fresh and bool(gait_sample.fresh)
					var gait_left: float = float(gait_sample.soles.get("ground_gap_L", float(gait_sample.soles.L) - float(fixture.height))) if fixture.name == "curb" else float(gait_sample.soles.L) - float(fixture.height)
					var gait_right: float = float(gait_sample.soles.get("ground_gap_R", float(gait_sample.soles.R) - float(fixture.height))) if fixture.name == "curb" else float(gait_sample.soles.R) - float(fixture.height)
					lowest = minf(lowest, minf(gait_left, gait_right))
			gait_ok = gait_ok and lowest >= -.005
			gait_details.append("%s/%s %.4fm" % [id, fixture.name, lowest])
			var standing_lowest := INF
			for clip: String in ["idle", "wave", "bow", "cheer", "tend", "dance"]:
				for phase: float in ([.25, .75] if clip == "dance" else [.5]):
					var standing_sample: Dictionary = await support_sample(controller, clip, phase, probe)
					samples_fresh = samples_fresh and bool(standing_sample.fresh)
					var standing_left: float = float(standing_sample.soles.get("ground_gap_L", float(standing_sample.soles.L) - float(fixture.height))) if fixture.name == "curb" else float(standing_sample.soles.L) - float(fixture.height)
					var standing_right: float = float(standing_sample.soles.get("ground_gap_R", float(standing_sample.soles.R) - float(fixture.height))) if fixture.name == "curb" else float(standing_sample.soles.R) - float(fixture.height)
					standing_lowest = minf(standing_lowest, minf(standing_left, standing_right))
			standing_ok = standing_ok and standing_lowest >= -.005
			standing_details.append("%s/%s %.4fm" % [id, fixture.name, standing_lowest])
		target.global_position = fixtures[0].at
		probe.set("support_rect_enabled", false)
		for phase: float in [.25, .75]:
			if support != null: support.set("enabled", false)
			var original: Dictionary = await support_sample(controller, "run", phase, probe)
			if support != null: support.set("enabled", true)
			var corrected: Dictionary = await support_sample(controller, "run", phase, probe)
			samples_fresh = samples_fresh and bool(original.fresh) and bool(corrected.fresh)
			# This fixture is the measured uniform street, away from curbs. An
			# independently bounded whole-skeleton lift must preserve relative
			# source poses. The cached 26-point envelope is not the full shoe, so
			# measure the actual shared lift rather than inventing an exact value.
			# Unsupported sources retain the absolute gate.
			var needed_rise: float = maxf(0.0, .008 + float(fixtures[0].height) - minf(float(original.soles.L), float(original.soles.R)))
			var before_root: Array = original.joints.hips
			var after_root: Array = corrected.joints.hips
			var actual_root_shift: Vector3 = Vector3(after_root[0], after_root[1], after_root[2]) - Vector3(before_root[0], before_root[1], before_root[2])
			var source_lift_allowed: bool = verified_run and needed_rise <= .025
			var common_valid: bool = actual_root_shift.y >= -.0001 and absf(actual_root_shift.x) < .0001 and absf(actual_root_shift.z) < .0001 and actual_root_shift.y <= minf(.025, needed_rise) + .001
			if source_lift_allowed and needed_rise > .0002: common_valid = common_valid and actual_root_shift.y > .0002
			if not source_lift_allowed: common_valid = actual_root_shift.length() < .001
			var common_shift: Vector3 = Vector3.UP * actual_root_shift.y if source_lift_allowed else Vector3.ZERO
			upper_ok = upper_ok and common_valid
			swing_ok = swing_ok and common_valid
			invariant_details.append("%s/%.2f full-shoe lift upper bound %.6fm; actual %s; valid %s" % [id, phase, needed_rise, actual_root_shift, common_valid])
			for joint: String in ["hips", "head", "hand.R"]:
				var before: Array = original.joints[joint]
				var after: Array = corrected.joints[joint]
				upper_ok = upper_ok and (Vector3(after[0], after[1], after[2]) - Vector3(before[0], before[1], before[2]) - common_shift).length() < .001
			for side: String in ["L", "R"]:
				if float(original.soles[side]) > .06 + float(fixtures[0].height):
					swings += 1
					swing_ok = swing_ok and absf(float(corrected.soles[side]) - float(original.soles[side]) - common_shift.y) < .001
				for pair: Array in [["thigh." + side, "shin." + side], ["shin." + side, "foot." + side]]:
					var old_first: Array = original.joints[pair[0]]
					var old_second: Array = original.joints[pair[1]]
					var new_first: Array = corrected.joints[pair[0]]
					var new_second: Array = corrected.joints[pair[1]]
					var old_length: float = Vector3(old_first[0], old_first[1], old_first[2]).distance_to(Vector3(old_second[0], old_second[1], old_second[2]))
					var new_length: float = Vector3(new_first[0], new_first[1], new_first[2]).distance_to(Vector3(new_second[0], new_second[1], new_second[2]))
					upper_ok = upper_ok and absf(old_length - new_length) < .001
		if support != null:
			var landmarks: Dictionary = support.get("samples")
			invariant_details.append("%s probes %d/%d" % [id, (landmarks.L as Array).size(), (landmarks.R as Array).size()])
			upper_ok = upper_ok and (landmarks.L as Array).size() <= 26 and (landmarks.R as Array).size() <= 26
		probe.queue_free()
		target.global_position = saved.position
		source.transform = saved.model_transform
		controller.ap.play(str(saved.clip), 0)
		controller.ap.seek(float(saved.time), true)
		controller.ap.speed_scale = float(saved.speed)
		target.visible = bool(saved.visible)
		target.set_process(bool(saved.process))
		target.set_physics_process(bool(saved.physics))
	t.check("CHARACTER_VISUAL", "all seven walk and run clips clear actual visible street plaza grass and curbs at seventeen phases", samples_fresh and gait_ok, str(gait_details))
	t.check("CHARACTER_VISUAL", "standing gestures and idle clear actual visible street plaza grass and curbs for all seven actors", samples_fresh and standing_ok, str(standing_details))
	t.check("CHARACTER_VISUAL", "shoe support preserves upper body relative to bounded paving lift and leg lengths using at most 26 probes per foot", samples_fresh and upper_ok, str(invariant_details))
	t.check("CHARACTER_VISUAL", "shoe support preserves raised swing feet relative to bounded paving lift and leaves running flight untouched", samples_fresh and swing_ok and swings >= 7, "%d raised shoes checked; fresh %s; original1mm relative gate and independent full-shoe/root lift bound" % [swings, samples_fresh])

func hand_tone_contract() -> void:
	var model: Node3D = main.npcs.aoi.model
	var stats: Dictionary = model.get_meta("hand_tone_stats", {})
	var targeted: bool = int(stats.get("left_vertices", 0)) > 100 and int(stats.get("right_vertices", 0)) > 100
	for id: String in ["ren", "haru", "mio", "tanaka", "kazuko"]:
		targeted = targeted and not main.npcs[id].model.has_meta("hand_tone_stats")
	targeted = targeted and not main.player.model.has_meta("hand_tone_stats")
	t.check("CHARACTER_VISUAL", "palm tone repair targets both Aoi hands and no other character", targeted, str(stats))
	var body: MeshInstance3D = WorldBuilder.find_meshes(model)[0]
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var original: Mesh = body.get_meta("hand_tone_original_mesh", body.mesh) as Mesh
	var geometry: bool = body.mesh == original
	var mask_is_local := true
	var skin_is_identical := true
	var shader_is_opaque := false
	var stream_details: Array[String] = []
	for surface: int in original.get_surface_count():
		var old_data: Dictionary = RenderingServer.mesh_get_surface(original.get_rid(), surface)
		var new_data: Dictionary = RenderingServer.mesh_get_surface(body.mesh.get_rid(), surface)
		for field: String in ["vertex_data", "skin_data", "index_data", "lods"]:
			geometry = geometry and old_data.get(field) == new_data.get(field)
			if old_data.get(field) != new_data.get(field):
				if field == "lods": stream_details.append("LOD counts %d / %d; old %s new %s" % [(old_data.get(field, []) as Array).size(), (new_data.get(field, []) as Array).size(), str((old_data.get(field, []) as Array).map(func(item): return [item.edge_length, (item.index_data as PackedByteArray).size()])), str((new_data.get(field, []) as Array).map(func(item): return [item.edge_length, (item.index_data as PackedByteArray).size()]))])
				else:
					var old_bytes: PackedByteArray = old_data.get(field, PackedByteArray())
					var new_bytes: PackedByteArray = new_data.get(field, PackedByteArray())
					var count := 0
					for offset: int in mini(old_bytes.size(), new_bytes.size()):
						if old_bytes[offset] != new_bytes[offset]: count += 1
					stream_details.append("%s bytes %d / %d (%d changed)" % [field, old_bytes.size(), new_bytes.size(), count])
		var old_arrays: Array = original.surface_get_arrays(surface)
		var new_arrays: Array = body.mesh.surface_get_arrays(surface)
		geometry = geometry and old_arrays[Mesh.ARRAY_TEX_UV] == new_arrays[Mesh.ARRAY_TEX_UV]
		if old_arrays[Mesh.ARRAY_TEX_UV] != new_arrays[Mesh.ARRAY_TEX_UV]: stream_details.append("UV arrays differ")
		skin_is_identical = skin_is_identical and old_arrays[Mesh.ARRAY_BONES] == new_arrays[Mesh.ARRAY_BONES] and old_arrays[Mesh.ARRAY_WEIGHTS] == new_arrays[Mesh.ARRAY_WEIGHTS]
		var material: ShaderMaterial = body.get_active_material(surface) as ShaderMaterial
		var bind_mask: PackedFloat32Array = material.get_shader_parameter("hand_bind_mask") if material != null and material.get_shader_parameter("hand_bind_mask") != null else PackedFloat32Array()
		var bones: PackedInt32Array = old_arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = old_arrays[Mesh.ARRAY_WEIGHTS]
		var positions: PackedVector3Array = old_arrays[Mesh.ARRAY_VERTEX]
		var per: int = bones.size() / positions.size()
		if bind_mask.size() != 128: mask_is_local = false
		else:
			for vertex: int in positions.size():
				var hand := 0.0
				var actual_mask := 0.0
				for influence: int in per:
					var bind: int = bones[vertex * per + influence]
					var bone_index: int = body.skin.get_bind_bone(bind)
					var name: String = skeleton.get_bone_name(bone_index) if bone_index >= 0 else String(body.skin.get_bind_name(bind))
					if name.contains("Hand"): hand += weights[vertex * per + influence]
					actual_mask += bind_mask[bind] * weights[vertex * per + influence]
				if hand < .01 and actual_mask > .01: mask_is_local = false
		if material != null:
			shader_is_opaque = not material.shader.code.contains("ALPHA =") and not material.shader.code.contains("VERTEX +=") and material.get_shader_parameter("diffuse") != null
	t.check("CHARACTER_VISUAL", "palm correction keeps original vertex skin index UV and every LOD stream", geometry, str(stream_details))
	t.check("CHARACTER_VISUAL", "skin correction has zero non-hand mask and uses one opaque surface without depth offset", mask_is_local and shader_is_opaque and body.mesh.get_surface_count() == original.get_surface_count())
	var digest: String = FileAccess.get_sha256("res://assets/models/CH_aoi.glb")
	t.check("CHARACTER_VISUAL", "palm tone preserves the accepted Aoi source GLB and imported skin weights", skin_is_identical and digest == accepted_source_digest("aoi"), digest)

func accepted_source_digest(id: String) -> String:
	var path: String = "res://assets/models/_stats/CH_" + id + ".json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return str((parsed as Dictionary).get("sha256", "")) if parsed is Dictionary else ""

func apron_sample_matches(measured: Dictionary, requested_id: int, requested_frame: int, clip: String, requested_time: float) -> bool:
	return int(measured.get("request_id", -1)) == requested_id and int(measured.get("request_frame", -1)) == requested_frame and int(measured.get("applied_frame", -1)) > requested_frame and str(measured.get("clip", "")) == clip and absf(float(measured.get("clip_time", INF)) - requested_time) < .0001

func await_apron_sample(probe: SkeletonModifier3D, clip: String, requested_time: float) -> Dictionary:
	var requested_id: int = probe.call("request", clip, requested_time)
	var requested_frame: int = int(probe.get("request_frame"))
	var measured: Dictionary = {}
	# Several physics ticks may pass without a process/modifier callback in
	# headless runs. Wait for this request's later final pose, never a prepared
	# record or the preceding phase. Timeout remains a failed measurement.
	for capture_frame: int in 8:
		await t.get_tree().process_frame
		measured = (probe.get("result") as Dictionary).duplicate(true)
		if apron_sample_matches(measured, requested_id, requested_frame, clip, requested_time): break
	measured["fresh"] = apron_sample_matches(measured, requested_id, requested_frame, clip, requested_time)
	if not bool(measured.fresh):
		print("APRON_SAMPLE_TIMEOUT ", JSON.stringify({"requested_id": requested_id, "requested_frame": requested_frame, "requested_clip": clip, "requested_time": requested_time, "actual_id": measured.get("request_id", -1), "applied_frame": measured.get("applied_frame", -1), "actual_clip": measured.get("clip", ""), "actual_time": measured.get("clip_time", -1.0)}))
	return measured

func sample_apron_pose(npc: NPC, probe: SkeletonModifier3D, clip: String, phase: float) -> Dictionary:
	var animation: Animation = npc.anim.ap.get_animation(clip)
	var requested_time: float = animation.length * phase
	if animation.loop_mode != Animation.LOOP_NONE: requested_time = fposmod(requested_time, animation.length)
	npc.anim.ap.play(clip, 0)
	npc.anim.ap.speed_scale = 0
	npc.anim.ap.seek(requested_time, true)
	npc.anim.ap.advance(0)
	return await await_apron_sample(probe, clip, requested_time)

func apron_clearance_contract() -> void:
	var context: Dictionary = {"region": main.world.region, "in_room": main.in_room, "room_kind": main.room_kind, "player_in_room": GameState.player_in_room}
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	var npc: NPC = main.npcs.kazuko
	var saved: Dictionary = {"position": npc.global_position, "home": npc.home, "process": npc.is_processing(), "yaw": npc._yaw, "clip": npc.anim.ap.current_animation, "time": npc.anim.ap.current_animation_position, "speed": npc.anim.ap.speed_scale}
	npc.set_process(false)
	npc.set_home(false)
	npc.global_position = Vector3(-8, .010, -10)
	npc.set_yaw(0)
	var sk: Skeleton3D = npc.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var probe: SkeletonModifier3D = load("res://scripts/tools/apron_qa_pose_probe.gd").new()
	probe.name = "ApronRegressionProbe"
	sk.add_child(probe)
	probe.call("prepare", npc.model)
	var actual_mesh: MeshInstance3D = probe.get("mesh") as MeshInstance3D
	var original_model: Node3D = load("res://assets/models/CH_kazuko.glb").instantiate()
	var original_mesh: MeshInstance3D = original_model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh_preserved: bool = actual_mesh != null and apron_mesh_preserved(actual_mesh.mesh as ArrayMesh, original_mesh.mesh as ArrayMesh)
	var actual_records: Dictionary = probe.get("records")
	for index: int in (probe.get("pants") as PackedInt32Array):
		var vertex: Dictionary = actual_records[index]
		for shape: int in range((original_mesh.mesh as ArrayMesh).get_blend_shape_count(), (vertex.deltas as Array).size()):
			mesh_preserved = mesh_preserved and (vertex.deltas[shape] as Vector3).length() < .000001
	# Contact may legitimately need a nonzero local target at rest. Record the
	# actual idle geometry before movement and require the same values on return.
	var idle_sample: Dictionary = await sample_apron_pose(npc, probe, "idle", .5)
	var idle_reference := PackedFloat32Array()
	for shape: int in (actual_mesh.mesh as ArrayMesh).get_blend_shape_count():
		idle_reference.append(actual_mesh.get_blend_shape_value(shape))
	var clear := true
	var coverage: bool = bool(idle_sample.get("fresh", false))
	var max_depth := 0.0
	var bad: Array[String] = []
	for clip: String in ["walk", "run", "dance", "idle", "wave", "bow", "look", "stretch", "tend", "talk", "cheer"]:
		var phases: Array[float] = [.5]
		if clip in ["walk", "run", "dance"]:
			phases.clear()
			for sample: int in 17: phases.append(float(sample) / 16.0)
			# Preserve the precise native counterexamples as well as the grid.
			phases.append(.2)
			phases.append(.8)
			phases.sort()
		for phase: float in phases:
			var measured: Dictionary = await sample_apron_pose(npc, probe, clip, phase)
			var fresh: bool = bool(measured.get("fresh", false))
			coverage = coverage and fresh and int(measured.get("apron_triangles", 0)) > 1000 and int(measured.get("pants_vertices", 0)) > 1000 and int(measured.get("covered_vertices", 0)) > 500
			var layers: Dictionary = measured.get("layers", {})
			for layer: String in ["front", "back"]:
				var panel: Dictionary = layers.get(layer, {})
				coverage = coverage and int(panel.get("apron_triangles", 0)) > 200 and int(panel.get("covered_vertices", 0)) > 100
			print("APRON_SAMPLE ", JSON.stringify({"requested_clip": clip, "phase": phase, "fresh": fresh, "actual": measured}))
			var depth: float = float(measured.get("max_penetration_m", INF))
			max_depth = maxf(max_depth, depth)
			if depth > .005:
				clear = false
				bad.append("%s p%.4f %.4fm" % [clip, phase, depth])
	# Blend shapes are node properties, so repeated modifier ticks must not accumulate.
	var stability_sample: Dictionary = await sample_apron_pose(npc, probe, "walk", .2)
	var stability_time: float = npc.anim.ap.current_animation_position
	var first: PackedFloat32Array = []
	var actual_geometry: ArrayMesh = actual_mesh.mesh as ArrayMesh
	for shape: int in actual_geometry.get_blend_shape_count(): first.append(actual_mesh.get_blend_shape_value(shape))
	var stable: bool = bool(stability_sample.get("fresh", false))
	for frame: int in 20:
		var repeated_sample: Dictionary = await await_apron_sample(probe, "walk", stability_time)
		stable = stable and bool(repeated_sample.get("fresh", false))
		for shape: int in first.size(): stable = stable and absf(actual_mesh.get_blend_shape_value(shape) - first[shape]) < .001
	var restored_sample: Dictionary = await sample_apron_pose(npc, probe, "idle", .5)
	var restored: bool = bool(restored_sample.get("fresh", false)) and idle_reference.size() == actual_geometry.get_blend_shape_count()
	for shape: int in idle_reference.size(): restored = restored and absf(actual_mesh.get_blend_shape_value(shape) - idle_reference[shape]) < .001
	var digest: String = FileAccess.get_sha256("res://assets/models/CH_kazuko.glb")
	mesh_preserved = mesh_preserved and digest == accepted_source_digest("kazuko")
	t.check("CHARACTER_VISUAL", "actual Kazuko apron encloses the final IK legs through gait dance gestures and stable restoration", coverage and clear and stable and restored and mesh_preserved, "coverage %s; max %.5fm; stable %s; restored %s; original mesh %s; bad %s" % [coverage, max_depth, stable, restored, mesh_preserved, str(bad)])
	original_model.free()
	probe.queue_free()
	npc.global_position = saved.position
	npc.set_yaw(float(saved.yaw))
	npc.set_home(bool(saved.home))
	npc.set_process(bool(saved.process))
	npc.anim.ap.play(str(saved.clip), 0)
	npc.anim.ap.seek(float(saved.time), true)
	npc.anim.ap.speed_scale = float(saved.speed)
	main.in_room = bool(context.in_room)
	main.room_kind = str(context.room_kind)
	GameState.player_in_room = bool(context.player_in_room)
	main.world.set_region(str(context.region))
	main.world.set_indoor_look(bool(context.in_room), "" if context.room_kind == "house" else str(context.room_kind))

func run_apron_only() -> void:
	await apron_clearance_contract()

func apron_mesh_preserved(actual: ArrayMesh, original: ArrayMesh) -> bool:
	if actual == null or original == null or actual.get_surface_count() != original.get_surface_count(): return false
	if actual.blend_shape_mode != original.blend_shape_mode: return false
	if actual.get_blend_shape_count() < original.get_blend_shape_count(): return false
	for shape: int in original.get_blend_shape_count():
		if actual.get_blend_shape_name(shape) != original.get_blend_shape_name(shape): return false
	for surface: int in original.get_surface_count():
		var old: Dictionary = RenderingServer.mesh_get_surface(original.get_rid(), surface)
		var now: Dictionary = RenderingServer.mesh_get_surface(actual.get_rid(), surface)
		for field: String in ["vertex_data", "attribute_data", "skin_data", "index_data", "format", "vertex_count", "index_count", "aabb", "bone_aabbs", "lods", "uv_scale", "material"]:
			if old.get(field) != now.get(field): return false
		var old_shapes: PackedByteArray = old.get("blend_shape_data", PackedByteArray())
		var now_shapes: PackedByteArray = now.get("blend_shape_data", PackedByteArray())
		if old_shapes.is_empty() or now_shapes.size() < old_shapes.size() or now_shapes.slice(0, old_shapes.size()) != old_shapes: return false
	return true
