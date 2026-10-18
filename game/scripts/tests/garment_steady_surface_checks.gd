extends RefCounted
## Explicit opt-in source counterfactual: selected NPC, 128 phases per steady clip.
## It disables only the garment contact solver during this fixture and records
## actual final bones/morphs. It changes no production bypass policy and is not
## part of the default garment checks or a transition/performance acceptance.
const PHASE_COUNT := 128
const ACTOR_LABELS: Dictionary = {"ren": "Ren", "mio": "Mio", "kazuko": "Kazuko"}
const CERTIFICATE = preload("res://scripts/characters/garment_model_certificate.gd")
const ALLOWED_MODIFIER_SCRIPTS: Array[String] = [
	"res://scripts/characters/natural_locomotion_pose.gd",
	"res://scripts/characters/character_foot_support.gd",
	"res://scripts/characters/character_garment_support.gd",
	"res://scripts/tools/garment_qa_pose_probe.gd",
	"res://scripts/tools/character_qa_pose_probe.gd",
]
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func safe_state_rejections(measured: Dictionary, clip: String, actor_id: String = "ren") -> Array[String]:
	var rejected: Array[String] = []
	var context: Dictionary = measured.get("pose_context", {})
	if not bool(context.get("actor_is_npc", false)) or str(context.get("npc_id", "")) != actor_id or str(measured.get("id", "")) != actor_id: rejected.append("selected NPC identity mismatch")
	if clip not in ["idle", "walk", "run"] or str(measured.get("clip", "")) != clip or str(context.get("char_anim_state", "")) != clip: rejected.append("clip/controller mismatch")
	if str(context.get("char_anim_oneshot", "missing")) != "": rejected.append("oneshot active or missing")
	if bool(context.get("resident_seated", true)): rejected.append("resident seated or missing")
	var duration: float = float(context.get("natural_transition_duration", -1.0))
	var elapsed: float = float(context.get("natural_transition_elapsed", -1.0))
	if not is_finite(duration) or not is_finite(elapsed) or duration < 0 or elapsed < 0 or (duration > 0 and elapsed < duration): rejected.append("Natural transition unfinished or missing")
	var active: Array = context.get("active_modifiers", [])
	if active.is_empty(): rejected.append("active modifier inventory missing")
	var required: Dictionary = {"res://scripts/characters/natural_locomotion_pose.gd": false, "res://scripts/characters/character_foot_support.gd": false, "res://scripts/characters/character_garment_support.gd": false}
	for modifier: Dictionary in active:
		var modifier_script: String = str(modifier.get("script", ""))
		if modifier_script not in ALLOWED_MODIFIER_SCRIPTS: rejected.append("additional active modifier: %s %s" % [str(modifier.get("name", "")), modifier_script])
		if required.has(modifier_script) and float(modifier.get("influence", -1.0)) == 1.0: required[modifier_script] = true
	for required_script: String in required:
		if not bool(required[required_script]): rejected.append("required full-influence modifier missing: " + required_script)
	return rejected

func maximum_local_weight(measured: Dictionary, mesh_name: String, owned_names: Array[String]) -> float:
	var maximum := 0.0
	var found: int = 0
	var shapes: Dictionary = (measured.get("blend_shape_values", {}) as Dictionary).get(mesh_name, {})
	if owned_names.is_empty(): return INF
	for name: String in shapes:
		if not name.begins_with("Garment_Local_"): continue
		if name not in owned_names or not is_finite(float(shapes[name])): return INF
		found += 1
		maximum = maxf(maximum, absf(float(shapes[name])))
	return maximum if found == owned_names.size() else INF

func source_domain_audit(probe: SkeletonModifier3D, source_mesh: MeshInstance3D) -> Dictionary:
	if probe.get("mesh") != source_mesh: return {"valid": false, "error": "probe and production source mesh differ"}
	var geometry: ArrayMesh = source_mesh.mesh as ArrayMesh
	var arrays: Array = geometry.surface_get_arrays(0)
	var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var source_points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var source_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var original_anchors: PackedInt32Array = probe.get("body")
	var anchor_labels: Dictionary = {}
	var anchor_records: Array[Dictionary] = []
	for anchor: int in original_anchors:
		if anchor < 0 or anchor >= source_points.size() or anchor >= source_uv.size(): return {"valid": false, "error": "source body anchor index out of range"}
		anchor_labels[anchor] = true
		var point: Vector3 = source_points[anchor]
		var uv: Vector2 = source_uv[anchor]
		anchor_records.append({"imported_surface_vertex_index": anchor, "rest_position": [point.x, point.y, point.z], "uv": [uv.x, uv.y]})
	var pure_faces: Dictionary = {}
	var pure_face_indices: Array[int] = []
	for offset: int in range(0, source_indices.size(), 3):
		if anchor_labels.has(source_indices[offset]) and anchor_labels.has(source_indices[offset + 1]) and anchor_labels.has(source_indices[offset + 2]):
			var pure_face: int = offset / 3
			pure_faces[pure_face] = true
			pure_face_indices.append(pure_face)
	var expected_barycentrics: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(.5, .5, 0), Vector3(.5, 0, .5), Vector3(0, .5, .5), Vector3.ONE / 3.0]
	var masks: Dictionary = {}
	var mixed_faces: Dictionary = {}
	var malformed: int = 0
	var duplicates: int = 0
	var witnesses: Array = probe.get("surface_witnesses")
	for witness: Dictionary in witnesses:
		var witness_face: int = int(witness.get("source_surface_triangle_index", -1))
		if int(witness.get("labelled_corners", -1)) != 3:
			mixed_faces[witness_face] = true
			continue
		if not pure_faces.has(witness_face):
			malformed += 1
			continue
		var barycentric: Vector3 = witness.get("barycentric", Vector3.INF)
		var barycentric_slot: int = expected_barycentrics.find(barycentric)
		if barycentric_slot < 0:
			malformed += 1
			continue
		var previous_mask: int = int(masks.get(witness_face, 0))
		var bit: int = 1 << barycentric_slot
		if (previous_mask & bit) != 0: duplicates += 1
		masks[witness_face] = previous_mask | bit
	var incomplete_faces: Array[int] = []
	for expected_face: int in pure_faces:
		if int(masks.get(expected_face, 0)) != 127: incomplete_faces.append(expected_face)
	var mixed_face_indices: Array[int] = []
	for mixed_face: int in mixed_faces: mixed_face_indices.append(mixed_face)
	return {"valid": not original_anchors.is_empty() and original_anchors.size() == anchor_labels.size() and not pure_faces.is_empty() and incomplete_faces.is_empty() and malformed == 0 and duplicates == 0, "body_anchor_count": original_anchors.size(), "body_anchor_records": anchor_records, "fully_labelled_body_source_triangles": pure_faces.size(), "fully_labelled_body_source_face_indices": pure_face_indices, "incomplete_pure_source_face_indices": incomplete_faces, "malformed_pure_witnesses": malformed, "duplicate_pure_witnesses": duplicates, "mixed_source_face_indices": mixed_face_indices, "witness_count": witnesses.size(), "pigment_source_face_indices": probe.get("pigment_source_face_indices"), "local_support_source_face_indices": probe.get("support_source_face_indices"), "cloth_domain_preparation": probe.get("cloth_domain_preparation"), "surface_preparation": probe.get("surface_witness_preparation"), "scope": "Exact imported surface0 body anchors with rest/UV, every pure body face with exactly3 corners/3 edge midpoints/centroid, mixed witness faces and both full original cloth domains. No source classification or ray/normal/depth formula changed. Independent GLB-domain mapping remains a separate source acceptance."}

func run() -> void:
	var actor_id: String = "ren"
	var fixture_root_y: float = .010
	var actor_options: int = 0
	var height_options: int = 0
	var configuration_errors: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--garment-surface-actor="):
			actor_options += 1
			actor_id = argument.trim_prefix("--garment-surface-actor=")
		if argument == "--garment-surface-root-zero":
			height_options += 1
			fixture_root_y = 0.0
		if argument.begins_with("--garment-surface-root-y="):
			height_options += 1
			var height_text: String = argument.trim_prefix("--garment-surface-root-y=")
			if not height_text.is_valid_float(): configuration_errors.append("invalid root height")
			else: fixture_root_y = height_text.to_float()
	if actor_options > 1 or actor_id not in ACTOR_LABELS: configuration_errors.append("actor must be one of ren/mio/kazuko, specified at most once")
	if height_options > 1 or not is_finite(fixture_root_y) or fixture_root_y not in [0.0, .010]: configuration_errors.append("root height must be exactly0 or.010, specified at most once")
	if not main.npcs.has(actor_id): configuration_errors.append("selected NPC unavailable")
	if SaveDB.directory.is_empty() or SaveDB.directory == "user://": configuration_errors.append("isolated HARUMACHI_SAVE_DIR or --test-db required")
	if not configuration_errors.is_empty():
		t.check("GARMENT_STEADY_SURFACE", "source qualification fixture configuration", false, JSON.stringify(configuration_errors))
		return
	var actor_label: String = str(ACTOR_LABELS[actor_id])
	var npc: NPC = main.npcs[actor_id]
	var support: Node = npc.model.find_child("CharacterGarmentSupport", true, false)
	if support == null:
		t.check("GARMENT_STEADY_SURFACE", actor_label + " production garment support exists", false)
		return
	var skeleton: Skeleton3D = npc.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var source_mesh: MeshInstance3D = support.get("mesh") as MeshInstance3D
	if skeleton == null or source_mesh == null or not source_mesh.mesh is ArrayMesh or npc.anim == null or npc.anim.ap == null:
		t.check("GARMENT_STEADY_SURFACE", actor_label + " complete source rig exists", false)
		return
	var owned_names: Array[String] = []
	var owned_indices: PackedInt32Array = support.get("local_indices")
	for owned_index: int in owned_indices: owned_names.append(str((source_mesh.mesh as ArrayMesh).get_blend_shape_name(owned_index)))
	var source_root_transform: Transform3D = support.get("steady_asset_root_transform")
	# Unsigned actors intentionally have no runtime steady fingerprint. Compute
	# the independent source identity without installing/refreshing any proof.
	var actual_fingerprint: String = CERTIFICATE.fingerprint(source_mesh, skeleton, npc.anim.ap, npc.model, source_root_transform)
	var saved: Dictionary = {"position": npc.global_position, "home": npc.home, "process": npc.is_processing(), "physics_process": npc.is_physics_processing(), "yaw": npc._yaw, "clip": npc.anim.ap.current_animation, "time": npc.anim.ap.current_animation_position, "speed": npc.anim.ap.speed_scale, "state": npc.anim._state, "oneshot": npc.anim._oneshot, "idle": npc.anim.idle_clip, "solver_enabled": support.get("enabled"), "region": main.world.region, "in_room": main.in_room, "room_kind": main.room_kind, "player_in_room": GameState.player_in_room}
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	npc.set_process(false)
	npc.set_physics_process(false)
	npc.set_home(false)
	npc.global_position = Vector3(-8, fixture_root_y, -10)
	npc.set_yaw(0)
	npc.anim._oneshot = ""
	npc.anim.idle_clip = "idle"
	support.set("enabled", false)
	var probe: SkeletonModifier3D = load("res://scripts/tools/garment_qa_pose_probe.gd").new()
	probe.name = actor_label + "SteadySurfaceCounterfactual"
	probe.set("measure_surface_witnesses", true)
	skeleton.add_child(probe)
	probe.call("prepare", npc.model)
	var domain: Dictionary = source_domain_audit(probe, source_mesh)
	var sampler: RefCounted = load("res://scripts/tests/garment_local_checks.gd").new(t)
	var rows: Array[Dictionary] = []
	var summaries: Array[Dictionary] = []
	for clip: String in ["idle", "walk", "run"]:
		# Use the real controller to establish state. Direct seeking below is
		# explicitly a steady-pose fixture; it proves no blend/route behaviour.
		npc.anim.update(0.0 if clip == "idle" else 1.0 if clip == "walk" else 4.0)
		var all_fresh := true
		var all_safe_zero := true
		var coverage: bool = bool(domain.get("valid", false))
		var maximum_vertex := 0.0
		var maximum_surface := 0.0
		var bad: Array[Dictionary] = []
		for phase_index: int in PHASE_COUNT:
			var phase: float = float(phase_index) / PHASE_COUNT
			var measured: Dictionary = await sampler.call("sample", npc, probe, clip, phase)
			var rejected: Array[String] = safe_state_rejections(measured, clip, actor_id)
			var local_max: float = maximum_local_weight(measured, str(source_mesh.name), owned_names)
			var surface: Dictionary = measured.get("surface_witnesses", {})
			all_fresh = all_fresh and bool(measured.get("fresh", false))
			var internal_amounts: PackedFloat32Array = support.get("amounts")
			var internal_zero: bool = internal_amounts.size() == owned_names.size()
			for internal_value: float in internal_amounts:
				internal_zero = internal_zero and is_finite(internal_value) and absf(internal_value) <= .0000001
			all_safe_zero = all_safe_zero and rejected.is_empty() and local_max <= .0000001 and internal_zero and not bool(support.get("enabled"))
			var preparation: Dictionary = surface.get("preparation", {})
			var pure_faces: int = int(preparation.get("fully_labelled_body_source_triangles", 0))
			var pure_selected: int = int((preparation.get("selected_source_triangles_by_labelled_corner_count", {}) as Dictionary).get("3", -1))
			var sample_coverage: bool = bool(domain.get("valid", false)) and bool(surface.get("enabled", false)) and bool(surface.get("supported", false)) and str(preparation.get("supported_character", "")) == actor_id and pure_faces == int(domain.get("fully_labelled_body_source_triangles", -1)) and pure_selected == pure_faces and int(preparation.get("witness_count", 0)) == int(domain.get("witness_count", -2)) and int(measured.get("body_vertices", 0)) == int(domain.get("body_anchor_count", -1))
			for layer: String in ["front", "back"]:
				var panel: Dictionary = (surface.get("layers", {}) as Dictionary).get(layer, {})
				sample_coverage = sample_coverage and int(panel.get("witness_queries", -1)) == int(preparation.get("witness_count", -2)) and int(panel.get("covered_witnesses", 0)) > 0
			coverage = coverage and sample_coverage
			var vertex_depth: float = float(measured.get("vertex_max_penetration_m", INF))
			var surface_depth: float = float(surface.get("max_penetration_m", INF))
			if not is_finite(vertex_depth): vertex_depth = INF
			if not is_finite(surface_depth): surface_depth = INF
			maximum_vertex = maxf(maximum_vertex, vertex_depth)
			maximum_surface = maxf(maximum_surface, surface_depth)
			if not rejected.is_empty() or not sample_coverage or not internal_zero or local_max > .0000001 or vertex_depth > .005 or surface_depth > .005 or not bool(measured.get("fresh", false)):
				bad.append({"phase": phase, "vertex_depth_m": vertex_depth, "surface_depth_m": surface_depth, "max_actual_local_weight": local_max, "owned_internal_local_zero": internal_zero, "safe_state_rejections": rejected, "coverage": sample_coverage, "fresh": measured.get("fresh", false)})
			var row: Dictionary = {"id": actor_id, "clip": clip, "phase": phase, "phase_index": phase_index, "fixture_root_y": fixture_root_y, "garment_solver_enabled": support.get("enabled"), "owned_local_shape_count": owned_names.size(), "owned_internal_local_zero": internal_zero, "max_actual_local_weight": local_max, "safe_state_rejections": rejected, "measurement": measured}
			rows.append(row)
			print("GARMENT_STEADY_SURFACE_SAMPLE ", JSON.stringify(row))
		var summary: Dictionary = {"id": actor_id, "clip": clip, "samples": PHASE_COUNT, "all_fresh": all_fresh, "all_safe_and_zero_local": all_safe_zero, "coverage": coverage, "max_vertex_penetration_m": maximum_vertex, "max_surface_penetration_m": maximum_surface, "bad": bad}
		summaries.append(summary)
		t.check("GARMENT_STEADY_SURFACE", actor_label + " " + clip + " all128 final-pose samples are fresh", all_fresh)
		t.check("GARMENT_STEADY_SURFACE", actor_label + " " + clip + " fixture has eligible steady state and actual zero local weights", all_fresh and all_safe_zero, JSON.stringify(summary))
		t.check("GARMENT_STEADY_SURFACE", actor_label + " " + clip + " original vertices and added surface witnesses retain original5mm gate", all_fresh and all_safe_zero and coverage and maximum_vertex <= .005 and maximum_surface <= .005, JSON.stringify(summary))
	var output: String = SaveDB.directory.path_join("garment-steady-surface.json")
	if actor_id != "ren": output = SaveDB.directory.path_join("garment-steady-surface-%s-root-%s.json" % [actor_id, "zero" if fixture_root_y == 0.0 else "010"])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--garment-surface-out="): output = arg.trim_prefix("--garment-surface-out=")
	var support_performance: Dictionary = support.call("performance")
	var report: Dictionary = {"id": actor_id, "mode": actor_label + " idle/walk/run zero-local steady final-surface counterfactual", "source_qualification_only": true, "proof_file_changed": false, "certificate_helper_version": CERTIFICATE.VERSION, "imported_content_sha256": actual_fingerprint, "source_identity_computed_independently": true, "support_performance": support_performance, "fixture_root_y": fixture_root_y, "phase_count_per_clip": PHASE_COUNT, "expected_sample_count": PHASE_COUNT * 3, "owned_local_shape_names": owned_names, "source_domain": domain, "samples": rows, "summaries": summaries, "scope": "Discrete complete source vertices plus all7 witnesses on every fully-labelled body triangle; original per-actor semantic and mixed-UV domain retained. Current final SkeletonModifier bones and actual source morphs; owned Local residuals must all be zero, solver disabled only by test fixture. One selected flat-ground height per invocation: both0 and.010 require separate384-sample runs. No new certificate, production bypass, automatic naturalness, continuous-surface proof, transition, NPC-route or performance PASS. Default garment checks remain separate."}
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	var written := file != null
	if file != null:
		file.store_string(JSON.stringify(report))
		written = file.get_error() == OK
		file.close()
	t.check("GARMENT_STEADY_SURFACE", actor_label + "384-sample counterfactual report saved", written and actual_fingerprint.length() == 64 and rows.size() == PHASE_COUNT * 3, output)
	probe.queue_free()
	support.set("enabled", bool(saved.solver_enabled))
	npc.global_position = saved.position
	npc.set_yaw(float(saved.yaw))
	npc.set_home(bool(saved.home))
	npc.set_process(bool(saved.process))
	npc.set_physics_process(bool(saved.physics_process))
	npc.anim._state = str(saved.state)
	npc.anim._oneshot = str(saved.oneshot)
	npc.anim.idle_clip = str(saved.idle)
	npc.anim.ap.play(str(saved.clip), 0)
	npc.anim.ap.seek(float(saved.time), true)
	npc.anim.ap.speed_scale = float(saved.speed)
	main.in_room = saved.in_room
	main.room_kind = saved.room_kind
	GameState.player_in_room = saved.player_in_room
	main.world.set_region(str(saved.region))
	main.world.set_indoor_look(bool(saved.in_room))
