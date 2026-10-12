extends Node
## Native character QA in the real world, with unchanged materials and sleeve modifiers.
## res://scenes/main.tscn -- --qa-characters --out=<dir> [--pilot]
## [--mode=poses,indoor,seats,motion,lighting] [--actors=sora,ren] [--clips=idle,wave]
## Poses seek authored clips; motion uses Player/NPC locomotion and records displacement.

const IDS: Array[String] = ["sora", "ren", "haru", "mio", "aoi", "tanaka", "kazuko"]
const CLIPS: Array[String] = ["idle", "walk", "run", "wave", "bow", "look", "stretch", "tend", "talk", "cheer", "dance"]
const VIEWS: Dictionary = {"front": Vector3(0, 1.15, 4.5), "right": Vector3(4.5, 1.15, 0), "back": Vector3(0, 1.15, -4.5), "left": Vector3(-4.5, 1.15, 0)}
const EXTRA_VIEWS: Dictionary = {"oblique_front": Vector3(1.1, 1.5, 1.2), "oblique_back": Vector3(-1.1, 1.5, -1.2), "high": Vector3(1.1, 3.0, 1.2), "low": Vector3(-1.1, .35, 1.2)}
const STREET := Vector3(-8, .03, -10)
var output := ""
var pilot := false
var modes: PackedStringArray = ["poses", "indoor", "seats", "motion", "lighting"]
var ids: PackedStringArray = PackedStringArray(IDS)
var clips: PackedStringArray = PackedStringArray(CLIPS)
var main: Node3D
var camera: Camera3D
var actor: Node3D
var model: Node3D
var anim: CharAnim
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var started_at := 0
var camera_override := false
var support_audit: RefCounted
var floor_meshes: Array[MeshInstance3D] = []
var floor_cache: Dictionary = {}
var pending_images: Array[Dictionary] = []
var phases: Array[float] = [.2, .5, .8]
var perf_active := false
var perf_skip_frames := 0
var perf_last_usec := 0
var perf_frames: Array[float] = []
var perf_excluded := 0
var measure_motion_soles := false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.substr(6)
		if argument.begins_with("--mode="): modes = argument.substr(7).split(",")
		if argument.begins_with("--actors="): ids = argument.substr(9).split(",")
		if argument.begins_with("--clips="): clips = argument.substr(8).split(",")
		if argument.begins_with("--phases="):
			phases.clear()
			for value: String in argument.substr(9).split(","): phases.append(float(value))
		if argument == "--pilot": pilot = true
		if argument == "--measure-motion-soles": measure_motion_soles = true
	if output.is_empty():
		push_error("character_visual_qa requires --out=<directory>")
		get_tree().quit(2)
		return
	if pilot:
		ids = ["sora", "kazuko"]
		clips = ["idle", "wave"]
	DirAccess.make_dir_recursive_absolute(output)
	started_at = Time.get_ticks_msec()
	GameState.new_game()
	GameState.clock_paused = true
	GameState.minute = 630
	NPC.roam_enabled = false
	main = get_parent() as Node3D
	await settle(40)
	support_audit = load("res://scripts/tests/placement_checks.gd").new(self)
	floor_meshes = WorldBuilder.find_meshes(main.world)
	main.set_process(false)
	main.set_physics_process(false)
	main.rig.set_process(false)
	main.player.set_physics_process(false)
	main.ui.visible = false
	main.marker.visible = false
	if main.shop_life: main.shop_life.set_process(false)
	for npc: NPC in main.npcs.values():
		npc.set_process(false)
		npc.tag.visible = false
		npc.set_home(true)
	for existing: Node in main.find_children("*", "Camera3D", true, false):
		(existing as Camera3D).current = false
	camera = Camera3D.new()
	camera.name = "CharacterQACamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.05
	camera.near = .02
	main.add_child(camera)
	camera.current = true
	main.weather_fx.rig = camera
	if "poses" in modes: await capture_poses()
	if "indoor" in modes: await capture_indoor()
	if "seats" in modes: await capture_seats()
	if "apron" in modes: await capture_apron()
	if "motion" in modes: await capture_motion()
	if "lighting" in modes: await capture_lighting()
	if "lighting-lamp" in modes: await capture_lighting(true)
	if "angles" in modes: await capture_angles()
	if "hand-tone" in modes: await capture_hand_tone()
	if "context-motion" in modes: await capture_context_motion()
	if "slope-contact" in modes: await capture_context_motion(true)
	if "town-contact" in modes: await capture_context_motion(false, true)
	if "hand-compare" in modes: await capture_hand_compare()
	if "static-support" in modes: await capture_static_support()
	if "fishing" in modes: await capture_fishing()
	var expected: int = 0
	if "poses" in modes: expected += ids.size() * clips.size() * phases.size() * 4
	if "indoor" in modes: expected += ids.size() * (1 if pilot else 4) * 8
	if "seats" in modes: expected += 18 if pilot else 72
	if "motion" in modes: expected += (2 + 1 if pilot else ids.size() + (1 if "sora" in ids else 0)) * 12
	if "lighting" in modes: expected += ids.size() * 18
	if "lighting-lamp" in modes: expected += ids.size() * 3
	if "angles" in modes: expected += ids.size() * 32
	if "hand-tone" in modes: expected += 24
	if "context-motion" in modes: expected += 72
	if "slope-contact" in modes: expected += 12
	if "town-contact" in modes: expected += 48
	if "hand-compare" in modes: expected += 8
	if "static-support" in modes: expected += 12
	if "fishing" in modes: expected += 48
	if "apron" in modes: expected += 36 if pilot else 72
	if rows.size() != expected: failures.append("incomplete capture: expected %d, got %d" % [expected, rows.size()])
	var report: Dictionary = {"engine": Engine.get_version_info().string, "images": rows.size(), "expected_images": expected, "elapsed_seconds": (Time.get_ticks_msec() - started_at) / 1000.0, "pilot": pilot, "failures": failures, "shots": rows, "notes": ["Authored pose samples use seek and leave skeleton modifiers running; these alone do not validate locomotion.", "Native motion samples use Player auto_move or NPC walk; each includes actual positions and clip.", "NPC sitting is unsupported by the current game; real seat checks cover the player."]}
	FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CHARACTER_VISUAL_QA ", JSON.stringify({"images": rows.size(), "failures": failures, "output": output}))
	get_tree().quit(0 if failures.is_empty() else 1)

func settle(frames: int = 8) -> void:
	for frame: int in range(frames): await get_tree().process_frame

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if perf_active:
		if perf_skip_frames > 0:
			perf_skip_frames -= 1
			perf_excluded += 1
		elif perf_last_usec > 0: perf_frames.append((now - perf_last_usec) / 1000.0)
	perf_last_usec = now

func render_performance() -> Dictionary:
	var total := 0.0
	var longest := 0.0
	for frame: float in perf_frames:
		total += frame
		longest = maxf(longest, frame)
	return {"frames": perf_frames.size(), "fps": 1000.0 * perf_frames.size() / maxf(total, .001), "longest_frame_ms": longest, "excluded_measurement_frames": perf_excluded, "excludes_screenshot_measurement": true}

func choose(id: String, at: Vector3) -> void:
	var support: Dictionary = rendered_floor(at)
	if support.has("render_height"): at.y = float(support.render_height)
	main.player.visible = false
	main.player.set_physics_process(false)
	main.player.auto_move = Vector3.ZERO
	main.player.auto_run = false
	for npc: NPC in main.npcs.values():
		npc.set_process(false)
		npc.set_home(true)
	if id == "sora":
		actor = main.player
		model = main.player.model
		anim = main.player.anim
		actor.visible = true
		actor.global_position = at
		main.player.set_facing(0)
	else:
		actor = main.npcs[id]
		model = (actor as NPC).model
		anim = (actor as NPC).anim
		(actor as NPC).set_home(false)
		(actor as NPC).place(at, 0)
		(actor as NPC).hold = true
		(actor as NPC)._greeted_day = GameState.day
		(actor as NPC)._idle_t = 10000
	if not anim.valid(): failures.append(id + ": missing actual CharAnim")
	actor.set_meta("qa_floor_support", support)

func look(view: String, focus_height: float = .98) -> void:
	if camera_override: return
	var yaw: float = main.player.model_root.global_rotation.y if actor is Player else model.global_rotation.y
	camera.size = 2.05 if main.in_room else 2.30
	if not main.in_room: focus_height = 1.05
	var offset: Vector3 = VIEWS[view] if VIEWS.has(view) else EXTRA_VIEWS[view]
	# Orthographic framing needs no long lens distance; stay inside nearby walls/signs.
	if VIEWS.has(view):
		offset.x *= .32
		offset.z *= .32
	camera.global_position = actor.global_position + offset.rotated(Vector3.UP, yaw)
	camera.look_at(actor.global_position + Vector3.UP * focus_height)

func snapshot(row: Dictionary, view: String) -> void:
	if perf_active: perf_skip_frames = 3
	var probe: SkeletonModifier3D
	var skeleton_nodes: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if not skeleton_nodes.is_empty():
		var skeleton: Skeleton3D = skeleton_nodes[0] as Skeleton3D
		probe = skeleton.get_node_or_null("CharacterQAPoseProbe") as SkeletonModifier3D
		if probe == null:
			probe = load("res://scripts/tools/character_qa_pose_probe.gd").new()
			probe.name = "CharacterQAPoseProbe"
			skeleton.add_child(probe)
			probe.call("prepare", model)
		skeleton.move_child(probe, skeleton.get_child_count() - 1)
		probe.set("measure_feet", row.action in ["sit", "seated_sip", "stand_after_seat", "indoor_idle"] or str(row.action).begins_with("idle") or row.kind == "native_context_locomotion" or (measure_motion_soles and (str(row.action).begins_with("walk") or str(row.action).begins_with("run"))))
		probe.set("support_rect_enabled", false)
		if row.get("scene", "") == "context_town_curb":
			for curb: MeshInstance3D in floor_meshes:
				if not curb.mesh is BoxMesh: continue
				if not (curb.mesh as BoxMesh).size.is_equal_approx(Vector3(94.9, .06, .22)) or absf(curb.global_position.z + 8) > .001: continue
				var box: AABB = curb.global_transform * curb.get_aabb()
				probe.set("support_rect", Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
				probe.set("support_height", box.end.y)
				probe.set("base_support_height", .010)
				probe.set("support_rect_enabled", true)
	look(view)
	await settle(int(row.get("settle_frames", 8)))
	var apron_probe: Node = model.find_child("ApronQAPoseProbe", true, false)
	var apron_request := -1
	if apron_probe != null:
		apron_request = apron_probe.call("request")
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var stem: String = "%s-%s-%s-p%02d-%s" % [row.get("scene", "street"), row.id, row.action, roundi(float(row.get("phase", 0)) * 100), view]
	if row.has("time"): stem += "-t%04d" % int(row.time)
	if row.has("sample"): stem += "-s%03d" % int(row.sample)
	var file: String = stem + ".png"
	# Read the actual rendered frame now; encode only after a native short route ends.
	# PNG compression must not consume the available walking/running distance.
	var captured: Image = get_viewport().get_texture().get_image()
	var info: Dictionary = row.duplicate(true)
	info["file"] = file
	info["view"] = view
	info["position"] = vector(actor.global_position)
	info["camera"] = vector(camera.global_position)
	info["camera_orthographic_size"] = camera.size
	info["floor_support"] = actor.get_meta("qa_floor_support", {})
	if row.kind == "native_context_locomotion": info["visible_ground"] = rendered_floor(actor.global_position)
	info["clip"] = anim.ap.current_animation
	info["clip_time"] = anim.ap.current_animation_position
	if apron_probe != null:
		info["apron"] = (apron_probe.get("result") as Dictionary).duplicate(true)
		if int(info.apron.get("request_id", -2)) != apron_request: failures.append("apron measurement did not consume its capture request")
	var apron_support: Node = model.find_child("CharacterApronSupport", true, false)
	if apron_support != null: info["apron_support"] = apron_support.call("performance")
	var grounding: Node = model.find_child("CharacterFootSupport", true, false)
	if grounding != null:
		info["foot_constraint_performance"] = grounding.call("performance")
		info["foot_constraint_correction"] = (grounding.get("correction") as Dictionary).duplicate()
	if probe != null:
		info["joints"] = (probe.get("joints") as Dictionary).duplicate(true)
		if bool(probe.get("measure_feet")): info["rendered_shoe_soles"] = (probe.get("soles") as Dictionary).duplicate(true)
		probe.set("measure_feet", false)
	if anim.clothing and anim.clothing.limiter:
		info["sleeve_samples"] = anim.clothing.limiter.get("samples")
		info["sleeve_max_degrees"] = anim.clothing.limiter.get("max_output_degrees")
	rows.append(info)
	if row.kind == "native_context_locomotion":
		pending_images.append({"file": file, "image": captured})
	else:
		captured.save_png(output.path_join(file))
	print("CHARACTER_SHOT ", file)

func save_pending_images() -> void:
	for pending: Dictionary in pending_images:
		var error: Error = (pending.image as Image).save_png(output.path_join(str(pending.file)))
		if error != OK: failures.append("could not encode native context frame: " + str(pending.file))
	pending_images.clear()

func pose(clip: String, phase: float) -> void:
	anim.ap.play(clip, 0)
	anim.ap.speed_scale = 0
	anim.ap.seek(anim.ap.get_animation(clip).length * phase, true)
	if anim.clothing: anim.clothing.reset()

func outdoors() -> void:
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	GameState.minute = 630
	GameState.weather = "sunny"
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	main.world.update_time(GameState.minute, GameState.weather, true)
	main.weather_fx.set_weather(GameState.weather, false)

func capture_poses() -> void:
	outdoors()
	for id: String in ids:
		choose(id, STREET)
		for clip: String in clips:
			if not anim.has(clip):
				failures.append(id + ": missing clip " + clip)
				continue
			for phase: float in phases:
				pose(clip, phase)
				for view: String in VIEWS:
					await snapshot({"id": id, "action": clip, "phase": phase, "scene": "street", "kind": "authored_pose_seek", "weather": "sunny"}, view)

func capture_indoor() -> void:
	var rooms: Array[String] = ["house", "workroom", "store", "bakery"]
	if pilot: rooms = ["bakery"]
	for room: String in rooms:
		var room_local: Vector3 = Vector3(1.3, .05, 2) if room == "bakery" else Vector3(0, .05, 2)
		var at: Vector3 = HouseBuilder.ORIGIN + Vector3(2.2, .05, .1) if room == "house" else InteriorBuilder.SPECS[room].origin + room_local
		main.in_room = true
		main.room_kind = room
		GameState.player_in_room = true
		main.world.set_indoor_look(true, "" if room == "house" else room)
		if room == "house": main.world.house.track_player(at)
		for minute: int in [630, 1260]:
			GameState.minute = minute
			main.world.update_time(minute, "sunny", true)
			main.weather_fx.set_weather("sunny", true)
			for id: String in ids:
				choose(id, at)
				pose("idle", .5)
				for view: String in VIEWS:
					await snapshot({"id": id, "action": "indoor_idle", "phase": .5, "scene": room, "time": minute, "kind": "authored_pose_seek"}, view)

func capture_seats() -> void:
	main.in_room = true
	main.room_kind = "bakery"
	GameState.player_in_room = true
	GameState.minute = 630
	main.world.set_indoor_look(true, "bakery")
	main.world.update_time(630, "sunny", true)
	var seat_ids: Array[String] = ["public_reading_0", "public_shared_seat", "public_cafe_0", "public_cafe_1"]
	if pilot: seat_ids = ["public_cafe_1"]
	for seat_id: String in seat_ids:
		main.room_kind = "workroom" if seat_id in ["public_reading_0", "public_shared_seat"] else "bakery"
		main.world.set_indoor_look(true, main.room_kind)
		choose("sora", InteriorBuilder.SPECS[main.room_kind].origin + Vector3(0, .05, 2))
		pose("idle", .5)
		var point: Interactable
		for candidate: Node in get_tree().get_nodes_in_group("interactables"):
			if candidate.get("id") == seat_id:
				point = candidate as Interactable
				break
		if point == null or not main.story.public_life.sit(point):
			failures.append("missing real seat: " + seat_id)
			continue
		await settle(15)
		for view: String in VIEWS:
			await snapshot({"id": "sora", "action": "sit", "phase": .5, "scene": seat_id, "kind": "real_seat_modifier", "hip_height": main.story.public_life.pose.measured_hip_height, "knee_forward": main.story.public_life.pose.measured_knee_forward}, view)
		var drink := LivingAction.new()
		main.add_child(drink)
		drink.setup(main.player, "sip", "coffee")
		drink.duration = 1000
		for phase: float in [.25, .5, .75]:
			drink.clock = phase * 1000
			await settle(8)
			for view: String in VIEWS:
				await snapshot({"id": "sora", "action": "seated_sip", "phase": phase, "scene": seat_id, "kind": "real_seat_and_living_action"}, view)
		drink.queue_free()
		await get_tree().process_frame
		main.story.public_life.stand(true)
		await settle(10)
		for view: String in ["front", "right"]:
			await snapshot({"id": "sora", "action": "stand_after_seat", "scene": seat_id, "kind": "real_stand_transition"}, view)

func capture_motion() -> void:
	outdoors()
	var motion_ids: PackedStringArray = PackedStringArray(["sora", "kazuko"]) if pilot else ids
	for id: String in motion_ids:
		var actions: Array[String] = ["walk"]
		if id == "sora": actions.append("run")
		for action: String in actions:
			for heading: int in [0, 90, 180, 270]:
				var direction: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(heading))
				choose(id, STREET - direction * 1.6)
				anim.ap.speed_scale = 1
				anim.set_idle("idle")
				var start: Vector3 = actor.global_position
				if actor is Player:
					(actor as Player).frozen = false
					(actor as Player).velocity = Vector3.ZERO
					(actor as Player).set_facing(atan2(direction.x, direction.z))
					(actor as Player).auto_move = direction
					(actor as Player).auto_run = action == "run"
					actor.set_physics_process(true)
				else:
					main.player.global_position = Vector3(-41, .1, -9.5)
					var npc: NPC = actor as NPC
					npc.hold = false
					# Keep the actual resident's gait/speed profile in motion evidence.
					npc.set_yaw(atan2(direction.x, direction.z))
					npc.set_process(true)
					npc.walk([start + direction * 5])
				var began: int = Time.get_ticks_msec()
				for sample: int in range(90):
					look("right")
					await get_tree().physics_frame
					if sample in [18, 40, 65]:
						var elapsed: float = (Time.get_ticks_msec() - began) / 1000.0
						var displacement: float = actor.global_position.distance_to(start)
						await snapshot({"id": id, "action": action + "_heading_%d" % heading, "sample": sample, "scene": "street", "kind": "native_locomotion", "displacement": displacement, "elapsed": elapsed, "mean_speed": displacement / maxf(elapsed, .001)}, "right" if sample != 40 else "front")
						var capture_elapsed: float = (Time.get_ticks_msec() - began) / 1000.0
						var capture_distance: float = actor.global_position.distance_to(start)
						rows[-1]["elapsed"] = capture_elapsed
						rows[-1]["displacement"] = capture_distance
						rows[-1]["mean_speed"] = capture_distance / maxf(capture_elapsed, .001)
				var distance: float = actor.global_position.distance_to(start)
				if distance < .6: failures.append("native " + id + " " + action + " heading %d travelled only %.3fm" % [heading, distance])
				if actor is Player:
					(actor as Player).auto_move = Vector3.ZERO
					actor.set_physics_process(false)
				else: actor.set_process(false)
				anim.ap.speed_scale = 0

func capture_lighting(lamp_only: bool = false) -> void:
	outdoors()
	var minutes: Array[int] = [390, 1110, 1260]
	if lamp_only: minutes = [1260]
	for weather: String in ["sunny", "cloudy", "rain"]:
		for minute: int in minutes:
			GameState.minute = minute
			GameState.weather = weather
			main.world.update_time(minute, weather, true)
			main.weather_fx.set_weather(weather, false)
			if weather == "rain": main.weather_fx.rain.restart()
			for id: String in ids:
				for view: String in ["front", "right"]:
					if lamp_only and view != "front": continue
					var under_lamp: bool = minute == 1260 and view == "front"
					var at: Vector3 = Vector3(-15.3, .03, -7.5) if under_lamp else STREET
					choose(id, at)
					pose("idle", .5)
					look(view)
					await settle(20)
					await snapshot({"id": id, "action": "idle_" + weather, "phase": .5, "scene": "lighting", "time": minute, "weather": weather, "rain_emitting": main.weather_fx.rain.emitting, "rain_visible": main.weather_fx.rain.visible, "sun_energy": main.world.sun.light_energy, "fixture": "existing_street_lamp" if under_lamp else "ordinary_street_ambient", "kind": "real_world_light_weather"}, view)

func capture_angles() -> void:
	outdoors()
	for id: String in ids:
		choose(id, STREET)
		for clip: String in ["idle", "wave", "walk", "run"]:
			for phase: float in [.3, .7]:
				pose(clip, phase)
				for view: String in EXTRA_VIEWS:
					await snapshot({"id": id, "action": clip, "phase": phase, "scene": "extra_angles", "kind": "authored_pose_seek"}, view)

func capture_hand_tone() -> void:
	outdoors()
	choose("aoi", STREET)
	for clip: String in ["wave", "cheer", "stretch"]:
		pose(clip, .5)
		await settle(10)
		for view: String in ["front", "oblique_front"]:
			await snapshot({"id": "aoi", "action": clip, "phase": .5, "scene": "hand_body", "kind": "authored_pose_seek"}, view)
			camera_override = true
			var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var hand: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(LivingPose.bone(skeleton, "hand.R")).origin)
			camera.size = .36
			camera.global_position = hand + (Vector3(0, .10, .70) if view == "front" else Vector3(.5, .12, .65))
			camera.look_at(hand)
			await snapshot({"id": "aoi", "action": clip, "phase": .5, "scene": "hand_close", "kind": "authored_pose_seek"}, view)
			camera_override = false
	for distance: float in [2.0, 8.0]:
		choose("aoi", STREET)
		var npc: NPC = actor as NPC
		npc.set_process(true)
		anim.ap.speed_scale = 1
		# Each distance starts a new real gesture, rather than resuming the
		# previous wave near its end when AnimationPlayer still names that clip.
		anim.set_idle("idle", true)
		anim.ap.stop()
		npc.gesture("wave")
		var previous_wave_time: float = -1.0
		for sample: int in range(80):
			camera_override = true
			camera.size = .90 if distance == 2.0 else 2.30
			camera.global_position = actor.global_position + Vector3(distance, 1.35, .8)
			camera.look_at(actor.global_position + Vector3(0, 1.2, 0))
			await get_tree().physics_frame
			if sample in [8, 20, 32, 44, 56, 68]:
				await snapshot({"id": "aoi", "action": "native_wave_distance_%d" % int(distance), "sample": sample, "scene": "hand_stability", "kind": "native_gesture", "hand_tone_stats": model.get_meta("hand_tone_stats", {})}, "right")
				var actual_wave: Dictionary = rows[-1]
				if str(actual_wave.clip) != "wave" or float(actual_wave.clip_time) <= previous_wave_time:
					failures.append("hand gesture did not supply an advancing wave: distance=%s sample=%d clip=%s time=%s" % [distance, sample, actual_wave.clip, actual_wave.clip_time])
				previous_wave_time = float(actual_wave.clip_time)
		camera_override = false
		npc.set_process(false)

func ground_at(at: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 4, at - Vector3.UP * 6, WorldBuilder.L_GROUND)
	var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {}
	return {"height": (hit.position as Vector3).y, "normal": vector(hit.normal), "collider": str(hit.collider.name)}

func rendered_floor(at: Vector3) -> Dictionary:
	var key := Vector2(at.x, at.z)
	if floor_cache.has(key): return floor_cache[key]
	var collision: Dictionary = ground_at(at)
	if collision.is_empty():
		failures.append("no actual ground below character fixture: " + str(at))
		return {}
	var height: float = -INF
	var support_name := ""
	# Include bridge models; the collider there is the hidden curved deck, not terrain.
	# Five footprint samples avoid mistaking a narrow plank gap for a missing board.
	for mesh: MeshInstance3D in floor_meshes:
		if not mesh.is_visible_in_tree(): continue
		if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		var support_node: Node = mesh
		var furniture := false
		while support_node != null and support_node != main.world:
			if support_node.name == "Sunbeams":
				furniture = true
				break
			if support_node.has_meta("model_id"):
				furniture = str(support_node.get_meta("model_id")) != "P_bridge"
				break
			support_node = support_node.get_parent()
		if furniture: continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if at.x < box.position.x - .05 or at.x > box.end.x + .05 or at.z < box.position.z - .05 or at.z > box.end.z + .05: continue
		if box.position.y > float(collision.height) + .12: continue
		# Exclude known optical overlays. Alpha-feathered paths remain valid support.
		var opaque := true
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface)
			if material is BaseMaterial3D and (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: opaque = false
			if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
				var shader_file: String = (material as ShaderMaterial).shader.resource_path.get_file()
				if shader_file in ["house_beam.gdshader", "shop_window.gdshader", "ghost.gdshader", "cat_contact_shadow.gdshader", "foliage_sway.gdshader", "moss_pile.gdshader", "bus_glass.gdshader", "shop_glass.gdshader", "lakeside_water.gdshader", "water.gdshader"]: opaque = false
		if not opaque: continue
		for offset: Vector2 in [Vector2.ZERO, Vector2(.045, 0), Vector2(-.045, 0), Vector2(0, .045), Vector2(0, -.045)]:
			var hit: float = float(support_audit.call("vertical_hit", mesh, key + offset, float(collision.height) + .12))
			if hit > height:
				height = hit
				support_name = str(mesh.name)
	if not is_finite(height):
		failures.append("no rendered support below fixture: " + str(at))
		return collision
	var result: Dictionary = {"collision_height": collision.height, "render_height": height, "mesh": support_name, "nominal_fixture_height": at.y, "adjustment": height - at.y, "samples": 5}
	floor_cache[key] = result
	return result

func clear_segment(first: Vector3, second: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.6
	shape.radius = .30
	query.shape = shape
	query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED | WorldBuilder.L_BLOCK
	for sample: int in range(13):
		var at: Vector3 = first.lerp(second, sample / 12.0)
		var ground: Dictionary = ground_at(at)
		if ground.is_empty(): return false
		at.y = float(ground.height) + .81
		query.transform = Transform3D(Basis.IDENTITY, at)
		if not main.player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	return true

func capture_context_motion(slope_only: bool = false, town_only: bool = false) -> void:
	var locations: Array[Dictionary] = [
		{"id": "house", "first": Vector3(4.5, 0, -.5), "second": Vector3(4.5, 0, -2.4)},
		{"id": "workroom", "first": Vector3(0, 0, 2.6), "second": Vector3(0, 0, .4)},
		{"id": "store", "first": Vector3(-1.9, 0, 2.1), "second": Vector3(1.9, 0, 2.1)},
		{"id": "bakery", "first": Vector3(1.1, 0, 2), "second": Vector3(3.5, 0, 2)},
		{"id": "farm_bridge", "first": Vector3(0, 0, 14), "second": Vector3(0, 0, 20)},
		{"id": "lake_slope", "first": Vector3(105, 0, -12), "second": Vector3(111, 0, -11.4)}]
	if slope_only: locations = [{"id": "lake_north_slope", "first": Vector3(105, 0, -12.5625), "second": Vector3(110, 0, -11.9)}]
	if town_only: locations = [
		{"id": "town_street", "first": Vector3(-11, 0, -10), "second": Vector3(-5, 0, -10)},
		{"id": "town_plaza", "first": Vector3(-3, 0, 12.2), "second": Vector3(3, 0, 12.2)},
		{"id": "town_grass", "first": Vector3(-49, 0, .5), "second": Vector3(-45, 0, .5)},
		{"id": "town_curb", "first": Vector3(0, 0, -9.2), "second": Vector3(0, 0, -6.8)}]
	for location: Dictionary in locations:
		var indoor: bool = location.id in ["house", "workroom", "store", "bakery"]
		var town: bool = str(location.id).begins_with("town_")
		main.in_room = indoor
		main.room_kind = str(location.id) if indoor else ""
		GameState.player_in_room = indoor
		GameState.minute = 630
		GameState.weather = "sunny"
		main.world.set_region("town" if indoor or town else "farm")
		main.world.set_indoor_look(indoor, "" if location.id == "house" or not indoor else str(location.id))
		main.world.update_time(630, "sunny", true)
		main.weather_fx.set_weather("sunny", indoor)
		var origin: Vector3 = Vector3.ZERO if town else HouseBuilder.ORIGIN if location.id == "house" else InteriorBuilder.SPECS[location.id].origin if indoor else FarmBuilder.ORIGIN
		var first: Vector3 = origin + (location.first as Vector3)
		var second: Vector3 = origin + (location.second as Vector3)
		if location.id == "house": main.world.house.track_player(first)
		if not clear_segment(first, second): failures.append("context preflight blocked: " + str(location.id))
		for action: String in ["walk", "run"]:
			for reverse: int in [0, 1]:
				var motion_view: String = "oblique_back" if location.id == "town_grass" and reverse == 1 else "oblique_front"
				var start: Vector3 = first if reverse == 0 else second
				var finish: Vector3 = second if reverse == 0 else first
				var direction: Vector3 = (finish - start).normalized()
				var length: float = start.distance_to(finish)
				var floor: Dictionary = ground_at(start)
				if floor.is_empty():
					failures.append("missing context ground: " + str(location.id))
					continue
				start.y = float(floor.height) + .04
				choose("sora", start)
				anim.ap.speed_scale = 1
				anim.set_idle("idle")
				main.player.velocity = Vector3.ZERO
				main.player.frozen = false
				main.player.set_facing(atan2(direction.x, direction.z))
				main.player.set_physics_process(true)
				for frame: int in range(10): await get_tree().physics_frame
				main.player.auto_move = direction
				main.player.auto_run = action == "run"
				var grounding: Node = model.find_child("CharacterFootSupport", true, false)
				if grounding != null: grounding.call("reset_performance")
				var first_row: int = rows.size()
				perf_frames.clear()
				perf_excluded = 0
				perf_skip_frames = 0
				perf_last_usec = Time.get_ticks_usec()
				perf_active = true
				var sample_index := 0
				var began: int = Time.get_ticks_msec()
				for frame: int in range(360):
					look(motion_view)
					await get_tree().physics_frame
					var flat: Vector3 = actor.global_position - start
					flat.y = 0
					var progress: float = flat.dot(direction) / length
					if sample_index < 3 and progress >= [.20, .50, .80][sample_index]:
						var current_ground: Dictionary = ground_at(actor.global_position)
						await snapshot({"id": "sora", "action": action + "_direction_%d" % reverse, "sample": sample_index, "scene": "context_" + str(location.id), "kind": "native_context_locomotion", "settle_frames": 0, "ground": current_ground, "progress": progress, "elapsed": (Time.get_ticks_msec() - began) / 1000.0, "is_on_floor": main.player.is_on_floor(), "velocity": vector(main.player.velocity), "blocked": Vector2(main.player.velocity.x, main.player.velocity.z).length() < .15}, motion_view)
						var soles: Dictionary = rows[-1].get("rendered_shoe_soles", {})
						var gaps: Dictionary = {}
						for side: String in ["L", "R"]:
							if not soles.has("point_" + side): continue
							var point: Array = soles["point_" + side]
							var below: Dictionary = ground_at(Vector3(point[0], point[1], point[2]))
							gaps[side] = {"sole": soles[side], "ground": below, "gap": float(soles[side]) - float(below.get("height", 0))}
							if town:
								gaps[side]["visible_gap"] = float(soles.get("ground_gap_" + side, float(soles[side]) - float(rows[-1].visible_ground.render_height))) if location.id == "town_curb" else float(soles[side]) - float(rows[-1].visible_ground.render_height)
						rows[-1]["shoe_ground_gaps"] = gaps
						sample_index += 1
					if progress >= .90: break
				main.player.auto_move = Vector3.ZERO
				main.player.set_physics_process(false)
				perf_active = false
				var performance_report: Dictionary = render_performance()
				for index_row: int in range(first_row, rows.size()): rows[index_row]["route_render_performance"] = performance_report
				save_pending_images()
				if sample_index != 3: failures.append("context route did not supply three moving frames: %s %s %d (%d)" % [location.id, action, reverse, sample_index])

func capture_hand_compare() -> void:
	outdoors()
	choose("aoi", STREET)
	pose("wave", .5)
	await settle(100)
	var body: MeshInstance3D = WorldBuilder.find_meshes(model)[0]
	var fixed: Mesh = body.mesh
	var fixed_materials: Array[Material] = []
	for surface: int in body.mesh.get_surface_count(): fixed_materials.append(body.get_active_material(surface))
	var original: Mesh = body.get_meta("hand_tone_original_mesh") as Mesh
	var original_materials: Array = body.get_meta("hand_tone_original_materials")
	for framing: String in ["body", "hand"]:
		camera_override = false
		look("front")
		if framing == "hand":
			var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var hand: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(LivingPose.bone(skeleton, "hand.R")).origin)
			camera.size = .36
			camera.global_position = hand + Vector3(0, .10, .70)
			camera.look_at(hand)
		camera_override = true
		for sample: int in range(4):
			var corrected: bool = sample % 2 == 1
			body.mesh = fixed if corrected else original
			for surface: int in body.mesh.get_surface_count(): body.set_surface_override_material(surface, fixed_materials[surface] if corrected else original_materials[surface])
			await snapshot({"id": "aoi", "action": "corrected" if corrected else "original", "phase": .5, "sample": sample, "scene": "same_process_" + framing, "kind": "fixed_clock_material_swap", "hand_tone_stats": model.get_meta("hand_tone_stats", {})}, "front")
		camera_override = false

func capture_static_support() -> void:
	var fixtures: Array[Dictionary] = [
		{"id": "house_standing", "at": Vector3(2.2, 0, .1), "house": true},
		{"id": "house_beam_0", "at": Vector3(4.5, 0, -1.4), "house": true},
		{"id": "house_beam_1", "at": Vector3(4.5, 0, -.83), "house": true},
		{"id": "bridge_support", "at": Vector3(0, 0, 17), "house": false},
		{"id": "north_slope_0", "at": Vector3(105, 0, -12.5625), "house": false},
		{"id": "north_slope_1", "at": Vector3(110, 0, -11.9), "house": false}]
	for fixture: Dictionary in fixtures:
		var indoor: bool = bool(fixture.house)
		main.in_room = indoor
		main.room_kind = "house" if indoor else ""
		GameState.player_in_room = indoor
		GameState.minute = 630
		GameState.weather = "sunny"
		main.world.set_region("town" if indoor else "farm")
		main.world.set_indoor_look(indoor)
		main.world.update_time(630, "sunny", true)
		main.weather_fx.set_weather("sunny", indoor)
		var at: Vector3 = (HouseBuilder.ORIGIN if indoor else FarmBuilder.ORIGIN) + (fixture.at as Vector3)
		if indoor: main.world.house.track_player(at)
		choose("sora", at)
		pose("idle", .5)
		for view: String in ["front", "right"]:
			await snapshot({"id": "sora", "action": "idle_support", "phase": .5, "scene": fixture.id, "kind": "static_rendered_support_fixture"}, view)

func capture_fishing() -> void:
	main.in_room=false;main.room_kind="";GameState.player_in_room=false
	main.world.set_region("farm");main.world.set_indoor_look(false)
	main.world.update_time(630,"sunny",true);main.weather_fx.set_weather("sunny",false)
	choose("sora",FarmBuilder.ORIGIN+Vector3(94,.56,37.7))
	main.player.set_facing(PI);pose("idle",.5)
	var sk: Skeleton3D = model.find_child("Skeleton3D",true,false) as Skeleton3D
	var fishing:=FishingView.new();main.add_child(fishing)
	fishing.setup(main.player,FarmBuilder.ORIGIN+Vector3(94,LakesideLayout.WATER_Y,32))
	var probe: SkeletonModifier3D = load("res://scripts/tools/fishing_qa_pose_probe.gd").new()
	sk.add_child(probe);probe.call("prepare",model);probe.set("view",fishing)
	var session:=FishingSession.new("fish_lake")
	var samples: Array[Dictionary] = [
		{"name":"ready","state":FishingSession.State.READY,"clock":0.0},
		{"name":"cast","state":FishingSession.State.CAST,"clock":.2},
		{"name":"wait","state":FishingSession.State.WAIT,"clock":.4},
		{"name":"reel_0","state":FishingSession.State.REEL,"clock":0.0},
		{"name":"reel_1","state":FishingSession.State.REEL,"clock":.34},
		{"name":"reel_2","state":FishingSession.State.REEL,"clock":.68},
		{"name":"landed","state":FishingSession.State.LANDED,"clock":1.0},
		{"name":"closed","state":FishingSession.State.CLOSED,"clock":1.0}]
	for sample: Dictionary in samples:
		session.state=int(sample.state);session.timer=.3;session.reel_progress=.4
		if sample.name=="closed":fishing.queue_free();await settle(3)
		else:
			fishing.set("_clock",float(sample.clock));fishing.update_view(session,0)
		await settle(4)
		for direction: String in ["front","right","back","left","oblique_front","oblique_back"]:
			await snapshot({"id":"sora","action":sample.name,"phase":float(sample.clock),"scene":"fishing","kind":"native_fishing_modifier","fixture":"real Sora rig and FishingView, held state/phase for diagnostic camera"},direction)
			var info: Dictionary = rows[-1]
			var joint_data: Dictionary = {}
			for key: String in (probe.get("joints") as Dictionary):joint_data[key]=vector((probe.get("joints") as Dictionary)[key])
			info["fishing_joints"]=joint_data
			var hand_data: Dictionary = {}
			for side: String in (probe.get("hand_centres") as Dictionary):hand_data[side]=vector((probe.get("hand_centres") as Dictionary)[side])
			info["skinned_hand_centres"]=hand_data
			info["rod_present"]=is_instance_valid(fishing)
			if is_instance_valid(fishing):
				info["rod_handle"]=vector(fishing.rod.to_global(Vector3(0,-.925,0)))
				info["rod_skin_gap"]=probe.get("rod_skin_gap")
				info["modifier_updates"]=fishing.pose.updates
				if sample.name not in ["landed","closed"] and float(probe.get("rod_skin_gap"))>.055:failures.append("fishing rod misses actual hand: "+str(sample.name))
	probe.queue_free()

func vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func capture_apron() -> void:
	outdoors()
	choose("kazuko", STREET)
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	var probe: SkeletonModifier3D = load("res://scripts/tools/apron_qa_pose_probe.gd").new()
	probe.name = "ApronQAPoseProbe"
	skeleton.add_child(probe)
	probe.call("prepare", model)
	var floor_enabled: bool = not "--apron-no-floor" in OS.get_cmdline_user_args()
	var grounding: Node = model.find_child("CharacterFootSupport", true, false)
	if grounding != null: grounding.set("enabled", floor_enabled)
	var apron_clips: Array = ["walk", "run", "dance"] if pilot else CLIPS
	for clip: String in apron_clips:
		var samples: Array = [.2, .5, .8] if clip in ["walk", "run", "dance"] else [.5]
		for phase: float in samples:
			pose(clip, phase)
			for view: String in VIEWS:
				await snapshot({"id": "kazuko", "action": clip, "phase": phase, "scene": "apron", "kind": "authored_pose_seek", "foot_support_enabled": floor_enabled}, view)
	if not pilot:
		pose("idle", .5)
		for view: String in VIEWS:
			await snapshot({"id": "kazuko", "action": "idle_restored", "phase": .5, "scene": "apron", "kind": "authored_pose_seek", "foot_support_enabled": floor_enabled}, view)
	if grounding != null: grounding.set("enabled", true)
