extends SkeletonModifier3D
## Bounded local contact correctives. Runs after final leg IK, preserving source
## cloth geometry, UVs and side openings; no whole-garment inflation is applied.
# TriangleMesh snaps vertices at 0.0001 units and uses an absolute triangle-ray
# determinant epsilon. Metre-sized characters contain smaller valid pleat faces.
# Scale the query space only: physical margins, normals and output stay in metres.
const RAY_SPACE_SCALE := 100.0
const CERTIFICATE = preload("res://scripts/characters/garment_model_certificate.gd")
const RISK_MAPPER = preload("res://scripts/characters/garment_risk_mapper.gd")
const BODY_CLASSIFIER = preload("res://scripts/characters/garment_body_classifier.gd")
const AUTHORED_SHAPES = preload("res://scripts/characters/garment_authored_shape_guard.gd")
const STEADY_CHARACTERS: Array[String] = ["ren", "mio", "kazuko"]
const STEADY_CLIPS: Array[String] = ["idle", "walk", "run"]
const STEADY_MODIFIERS: Array[String] = [
	"res://scripts/characters/natural_locomotion_pose.gd",
	"res://scripts/characters/character_foot_support.gd",
	"res://scripts/characters/character_garment_support.gd",
	"res://scripts/tools/garment_qa_pose_probe.gd",
	"res://scripts/tools/character_qa_pose_probe.gd",
	"res://scripts/tools/character_continuous_probe.gd",
]
var steady_proof_path := "res://data/character_garment_proofs.json"
var steady_model_fingerprint := ""
var steady_proof_match := false
var steady_morph_policy := "zero"
var steady_morph_plan: Dictionary = {}
var steady_fast_updates := 0
var last_callback_frame := -1
var last_branch := "unprepared"
var last_steady_reason := "not Ren"
var steady_animation: AnimationPlayer
var steady_natural: SkeletonModifier3D
var steady_foot: SkeletonModifier3D
var steady_actor: Node3D
var steady_model: Node3D
var steady_asset_root_transform := Transform3D.IDENTITY
var steady_mesh_id := 0
var steady_skin_id := 0
var steady_invalidation_reason := ""
var steady_carriers: Array[Node3D] = []
var steady_carrier_transforms: Array[Transform3D] = []
var steady_carrier_parents: Array[Node] = []
var steady_carrier_names: Array[StringName] = []
var steady_resources: Array[Resource] = []
var steady_watched_skeleton: Skeleton3D
var steady_watched_animation: AnimationPlayer
var mesh: MeshInstance3D
var character := ""
var body_rgb := Vector3(.92, .73, .63)
var body_rgb_tolerance := .12
var local_indices := PackedInt32Array()
var original_indices := PackedInt32Array()
var disabled_indices := PackedInt32Array()
var amounts := PackedFloat32Array()
var source_ids := PackedInt32Array()
var source_lookup: Dictionary = {}
var positions := PackedVector3Array()
var original_morph_vertices: Array[PackedInt32Array] = []
var original_morph_deltas: Array[PackedVector3Array] = []
var deforming_vertices := PackedInt32Array()
var patch_ids: Array[PackedInt32Array] = []
var patch_coefficients: Array[PackedFloat32Array] = []
var bone_offsets := PackedInt32Array()
var bone_slots := PackedInt32Array()
var bone_weights := PackedFloat32Array()
var bone_ids := PackedInt32Array()
var inverse_binds: Array[Transform3D] = []
var body := PackedInt32Array()
var body_surface_triangles := PackedInt32Array()
var body_surface_edges := PackedInt32Array()
var body_edge_min_rest_length_m := -1.0
var body_edge_policy := ""
var physical_body_anchors := 0
var body_classification_preparation: Dictionary = {}
var faces: Dictionary = {"front": PackedInt32Array(), "back": PackedInt32Array()}
var panel_vertices: Dictionary = {"front": PackedInt32Array(), "back": PackedInt32Array()}
var face_patch_ids: Dictionary = {"front": [], "back": []}
var layer_patch_ids: Dictionary = {"front": PackedInt32Array(), "back": PackedInt32Array()}
var enabled := true
var margin := .003
var maximum_weight := 1.0
var updates := 0
var total_usec := 0
var max_usec := 0
var max_contact_depth := 0.0
var saturated_constraints := 0
var max_displacement := 0.0
var active_targets := 0
var last_original_values := PackedFloat32Array()
var cached_matrices: Array[Transform3D] = []
var cached_original_values := PackedFloat32Array()
var cached_amounts := PackedFloat32Array()
var cached_enabled := true
var cache_hits := 0
var frame_times := PackedInt32Array()
var solve_times := PackedInt32Array()
var solve_total_usec := 0
var skin_total_usec := 0
var contact_total_usec := 0
var skin_max_usec := 0
var contact_max_usec := 0
var proxy_candidates: Array[Dictionary] = []
var total_ray_queries := 0
var total_broadphase_skips := 0
var frame_ray_queries := 0
var frame_broadphase_skips := 0
var total_iterations := 0
var total_tree_build_usec := 0
var total_bounds_usec := 0
var total_query_usec := 0
var total_tree_builds := 0
var total_face_cache_hits := 0
var total_face_cache_builds := 0
var proxy_target_triangles := 1400.0
var diagnostic_proxy_override := false
var diagnostic_fine_contact := false
var diagnostic_safe_face_cache := false
var diagnostic_fixed_layer_reuse := true
var diagnostic_skin_direction_skip := true
var diagnostic_layer_geometry_cache := false
var diagnostic_unique_panel_scaling := false
var total_fixed_layer_reuses := 0
var total_layer_geometry_cache_hits := 0
var total_tree_scale_inputs := 0
var total_tree_scale_multiplications_saved := 0
var diagnostic_risk_contact := false
var risk_mapping: Dictionary = {}
var risk_model: Node3D
var risk_animation: AnimationPlayer
var risk_asset_root_transform := Transform3D.IDENTITY
var risk_animation_clips: Array[String] = []
var risk_profile_identity := ""
var risk_model_fingerprint := ""
var risk_proof_match := false
var total_certified_ray_skips := 0
var total_certificate_tests := 0

func native_contact_original_performance() -> Dictionary:
	var ordered: PackedInt32Array = frame_times.duplicate()
	ordered.sort()
	var p95: int = ordered[mini(ordered.size() - 1, int(ceil(ordered.size() * .95)) - 1)] if not ordered.is_empty() else 0
	var solved: PackedInt32Array = solve_times.duplicate()
	solved.sort()
	var solve_p95: int = solved[mini(solved.size() - 1, int(ceil(solved.size() * .95)) - 1)] if not solved.is_empty() else 0
	var current: Array[float] = []
	for value: float in amounts: current.append(value)
	return {"updates": updates, "mean_usec": float(total_usec) / maxi(updates, 1), "max_usec": max_usec, "p95_usec_recent_240": p95, "solve_mean_usec": float(solve_total_usec) / maxi(updates - cache_hits - steady_fast_updates, 1), "solve_p95_usec_recent_240": solve_p95, "skin_mean_usec": float(skin_total_usec) / maxi(updates - cache_hits - steady_fast_updates, 1), "contact_mean_usec": float(contact_total_usec) / maxi(updates - cache_hits - steady_fast_updates, 1), "skin_max_usec": skin_max_usec, "contact_max_usec": contact_max_usec, "proxy_candidates": proxy_candidates,
		"steady_morph_policy": steady_morph_policy, "steady_morph_plan_valid": bool(steady_morph_plan.get("valid", false)), "steady_fast_updates": steady_fast_updates, "full_solve_updates": updates - cache_hits - steady_fast_updates, "last_callback_frame": last_callback_frame, "last_branch": last_branch, "last_steady_reason": last_steady_reason, "steady_proof_match": steady_proof_match, "steady_model_fingerprint": steady_model_fingerprint, "steady_invalidation_reason": steady_invalidation_reason, "steady_watched_carriers": steady_carriers.size(), "steady_watched_resources": steady_resources.size(),
		"iterations_mean": float(total_iterations) / maxi(updates - cache_hits - steady_fast_updates, 1), "tree_build_mean_usec": float(total_tree_build_usec) / maxi(updates - cache_hits - steady_fast_updates, 1), "bounds_mean_usec": float(total_bounds_usec) / maxi(updates - cache_hits - steady_fast_updates, 1), "query_constraints_mean_usec": float(total_query_usec) / maxi(updates - cache_hits - steady_fast_updates, 1), "tree_builds_mean": float(total_tree_builds) / maxi(updates - cache_hits - steady_fast_updates, 1),
		"proxy_target_triangles": proxy_target_triangles, "diagnostic_proxy_override": diagnostic_proxy_override, "diagnostic_fine_contact": diagnostic_fine_contact,
		"diagnostic_fixed_layer_reuse": diagnostic_fixed_layer_reuse, "diagnostic_skin_direction_skip": diagnostic_skin_direction_skip, "fixed_layer_reuses_mean": float(total_fixed_layer_reuses) / maxi(updates - cache_hits - steady_fast_updates, 1),
		"diagnostic_layer_geometry_cache": diagnostic_layer_geometry_cache, "diagnostic_unique_panel_scaling": diagnostic_unique_panel_scaling, "layer_geometry_cache_hits_mean": float(total_layer_geometry_cache_hits) / maxi(updates - cache_hits - steady_fast_updates, 1), "tree_scale_inputs_mean": float(total_tree_scale_inputs) / maxi(updates - cache_hits - steady_fast_updates, 1), "tree_scale_multiplications_saved_mean": float(total_tree_scale_multiplications_saved) / maxi(updates - cache_hits - steady_fast_updates, 1),
		"diagnostic_safe_face_cache": diagnostic_safe_face_cache, "certified_ray_skips_mean": float(total_certified_ray_skips) / maxi(updates - cache_hits - steady_fast_updates, 1), "certificate_triangle_tests_mean": float(total_certificate_tests) / maxi(updates - cache_hits - steady_fast_updates, 1),
		"diagnostic_risk_contact": diagnostic_risk_contact, "risk_mapping": risk_mapping, "support_mask_policy": "sum(abs(Local POSITION.z)) per side >=1micrometre",
		"risk_model_fingerprint": risk_model_fingerprint, "risk_profile_identity": risk_profile_identity, "risk_animation_clips": risk_animation_clips, "risk_proof_match": risk_proof_match, "risk_unverified_diagnostic_override": diagnostic_risk_contact and not risk_proof_match,
		"face_cache_hits_mean": float(total_face_cache_hits) / maxi(updates - cache_hits - steady_fast_updates, 1), "face_cache_builds_mean": float(total_face_cache_builds) / maxi(updates - cache_hits - steady_fast_updates, 1),
		"ray_space_scale": RAY_SPACE_SCALE,
		"character": character, "local_targets": amounts.size(), "active_targets": active_targets,
		"max_local_displacement_m": max_displacement, "max_contact_depth_m": max_contact_depth,
		"saturated_constraints": saturated_constraints, "body_anchors": body.size(), "physical_body_anchors": physical_body_anchors, "body_classification": body_classification_preparation, "body_surface_centroids": body_surface_triangles.size() / 3, "body_surface_edge_midpoints": body_surface_edges.size() / 2, "body_edge_min_rest_length_m": body_edge_min_rest_length_m, "body_edge_policy": body_edge_policy, "skinned_source_vertices": positions.size(), "nonzero_skin_influences": bone_weights.size(),
		"cloth_triangles_front": (faces.front as PackedInt32Array).size() / 3,
		"cloth_triangles_back": (faces.back as PackedInt32Array).size() / 3, "local_weights": current, "pose_cache_hits": cache_hits, "ray_queries_mean": float(total_ray_queries) / maxi(updates, 1), "broadphase_skips_mean": float(total_broadphase_skips) / maxi(updates, 1)}

func reset_performance() -> void:
	native_geometry_calls = 0
	native_geometry_fallbacks = 0
	native_contact_layers = 0
	native_contact_pack_usec = 0
	native_contact_eager_trees = 0
	native_contact_zero_query_trees = 0
	updates = 0
	total_usec = 0
	max_usec = 0
	cache_hits = 0
	frame_times.clear()
	solve_times.clear()
	solve_total_usec = 0
	skin_total_usec = 0
	contact_total_usec = 0
	skin_max_usec = 0
	contact_max_usec = 0
	total_ray_queries = 0
	total_broadphase_skips = 0
	total_iterations = 0
	total_tree_build_usec = 0
	total_bounds_usec = 0
	total_query_usec = 0
	total_tree_builds = 0
	total_face_cache_hits = 0
	total_face_cache_builds = 0
	total_certified_ray_skips = 0
	total_certificate_tests = 0
	total_fixed_layer_reuses = 0
	total_layer_geometry_cache_hits = 0
	total_tree_scale_inputs = 0
	total_tree_scale_multiplications_saved = 0
	steady_fast_updates = 0

func invalidate_steady_proof() -> void:
	steady_proof_match = false
	steady_invalidation_reason = "certified resource changed"
	# A previous certified/cache result must not hide the new guard outcome.
	cached_matrices.clear()

func prepare_steady_watchers() -> bool:
	var changed_callback := Callable(self, "invalidate_steady_proof")
	if is_instance_valid(steady_watched_animation) and steady_watched_animation.animation_list_changed.is_connected(changed_callback): steady_watched_animation.animation_list_changed.disconnect(changed_callback)
	for resource: Resource in steady_resources:
		if is_instance_valid(resource) and resource.changed.is_connected(changed_callback): resource.changed.disconnect(changed_callback)
	if is_instance_valid(steady_watched_skeleton):
		for signal_name: StringName in [&"rest_updated", &"bone_list_changed"]:
			if steady_watched_skeleton.has_signal(signal_name) and steady_watched_skeleton.is_connected(signal_name, changed_callback): steady_watched_skeleton.disconnect(signal_name, changed_callback)
	steady_resources.clear()
	steady_carriers.clear()
	steady_carrier_transforms.clear()
	steady_carrier_parents.clear()
	steady_carrier_names.clear()
	steady_watched_skeleton = get_skeleton()
	steady_watched_animation = steady_animation
	var visited: Dictionary = {}
	for carrier: Node3D in [mesh, steady_watched_skeleton]:
		var chain: Node = carrier
		while chain != steady_model:
			if chain == null: return false
			if chain is Node3D and not visited.has(chain.get_instance_id()):
				var spatial: Node3D = chain as Node3D
				visited[chain.get_instance_id()] = true
				steady_carriers.append(spatial)
				steady_carrier_transforms.append(spatial.transform)
				steady_carrier_parents.append(spatial.get_parent())
				steady_carrier_names.append(spatial.name)
			chain = chain.get_parent()
	for resource: Resource in [mesh.mesh, mesh.skin]: steady_resources.append(resource)
	for clip: String in STEADY_CLIPS:
		if not steady_animation.has_animation(clip): return false
		var animation: Animation = steady_animation.get_animation(clip)
		if not steady_resources.has(animation): steady_resources.append(animation)
	for resource: Resource in steady_resources:
		if not resource.changed.is_connected(changed_callback): resource.changed.connect(changed_callback)
	for signal_name: StringName in [&"rest_updated", &"bone_list_changed"]:
		if steady_watched_skeleton.has_signal(signal_name) and not steady_watched_skeleton.is_connected(signal_name, changed_callback): steady_watched_skeleton.connect(signal_name, changed_callback)
	if not steady_watched_animation.animation_list_changed.is_connected(changed_callback): steady_watched_animation.animation_list_changed.connect(changed_callback)
	return true

func refresh_steady_proof() -> bool:
	steady_proof_match = false
	steady_invalidation_reason = ""
	steady_morph_policy = "zero"
	steady_morph_plan.clear()
	if character not in STEADY_CHARACTERS or mesh == null or mesh.mesh == null or mesh.skin == null or steady_animation == null: return false
	if character != "ren":
		# New actors have no bypass until a complete source proof is installed.
		if not FileAccess.file_exists(steady_proof_path): return false
		var entries: Variant = JSON.parse_string(FileAccess.get_file_as_string(steady_proof_path))
		if not entries is Dictionary or not (entries as Dictionary).has(character): return false
	if not prepare_steady_watchers(): return false
	steady_model_fingerprint = CERTIFICATE.fingerprint(mesh, get_skeleton(), steady_animation, steady_model, steady_asset_root_transform)
	if not FileAccess.file_exists(steady_proof_path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(steady_proof_path))
	if not parsed is Dictionary: return false
	var proof: Dictionary = (parsed as Dictionary).get(character, {})
	steady_morph_policy = str(proof.get("morph_policy", "zero"))
	if character == "ren" and steady_morph_policy != "zero": return false
	if character != "ren" and steady_morph_policy != AUTHORED_SHAPES.POLICY: return false
	steady_proof_match = int(proof.get("certificate_version", 0)) == CERTIFICATE.VERSION and steady_model_fingerprint != "" and str(proof.get("imported_content_sha256", "")) == steady_model_fingerprint and proof.get("allowed_clips", []) == STEADY_CLIPS
	if steady_proof_match and steady_morph_policy == AUTHORED_SHAPES.POLICY:
		steady_morph_plan = AUTHORED_SHAPES.prepare(mesh, steady_animation, original_indices, STEADY_CLIPS)
		steady_proof_match = bool(steady_morph_plan.get("valid", false))
	if steady_proof_match:
		steady_mesh_id = mesh.mesh.get_instance_id()
		steady_skin_id = mesh.skin.get_instance_id()
	return steady_proof_match

func refresh_risk_proof() -> bool:
	risk_proof_match = false
	if not bool(risk_mapping.get("valid", false)) or risk_model == null or risk_animation == null: return false
	risk_model_fingerprint = CERTIFICATE.fingerprint(mesh, get_skeleton(), risk_animation, risk_model, risk_asset_root_transform, risk_animation_clips, risk_profile_identity)
	if not FileAccess.file_exists(steady_proof_path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(steady_proof_path))
	if not parsed is Dictionary: return false
	var proof_entry: Dictionary = (parsed as Dictionary).get(character, {})
	var proof: Dictionary = proof_entry.get("fine_risk_proxy", {})
	risk_proof_match = int(proof.get("certificate_version", 0)) == CERTIFICATE.VERSION and risk_model_fingerprint != "" and str(proof.get("imported_content_sha256", "")) == risk_model_fingerprint and str(proof.get("risk_profile_identity", "")) == risk_profile_identity and proof.get("allowed_clips", []) == risk_animation_clips
	return risk_proof_match

func steady_rejection(original_values: PackedFloat32Array) -> String:
	if character not in STEADY_CHARACTERS: return "unsupported steady character"
	if not steady_proof_match: return steady_invalidation_reason if steady_invalidation_reason != "" else "unverified model content"
	if mesh.mesh == null or mesh.skin == null or mesh.mesh.get_instance_id() != steady_mesh_id or mesh.skin.get_instance_id() != steady_skin_id:
		steady_proof_match = false
		steady_invalidation_reason = "mesh or skin resource changed"
		cached_matrices.clear()
		return steady_invalidation_reason
	for carrier_index: int in steady_carriers.size():
		var carrier: Node3D = steady_carriers[carrier_index]
		if not is_instance_valid(carrier) or carrier.transform != steady_carrier_transforms[carrier_index] or carrier.get_parent() != steady_carrier_parents[carrier_index] or carrier.name != steady_carrier_names[carrier_index]:
			steady_proof_match = false
			steady_invalidation_reason = "asset carrier transform changed"
			cached_matrices.clear()
			return steady_invalidation_reason
	if not is_instance_valid(steady_actor) or not steady_actor is NPC: return "not NPC"
	var npc: NPC = steady_actor as NPC
	if npc.npc_id != character or npc.anim == null or npc.anim.ap != steady_animation: return "controller mismatch"
	if npc.get_meta("resident_seated", false): return "seated"
	if not is_instance_valid(steady_model) or steady_model.position != steady_asset_root_transform.origin or not steady_model.global_basis.get_scale().is_equal_approx(Vector3.ONE) or steady_model.global_basis.y.normalized().dot(Vector3.UP) < .99999: return "model scale, tilt or offset"
	var clip: String = steady_animation.current_animation
	if clip not in STEADY_CLIPS or npc.anim._state != clip or npc.anim._oneshot != "": return "non-steady controller state"
	if not steady_animation.is_playing(): return "animation stopped"
	if not is_instance_valid(steady_natural) or not steady_natural.active or steady_natural.influence != 1.0: return "natural modifier unavailable"
	var duration: float = float(steady_natural.get("_transition_duration"))
	var elapsed: float = float(steady_natural.get("_transition_elapsed"))
	if duration > 0 and elapsed < duration: return "transition"
	if not is_instance_valid(steady_foot) or not steady_foot.active or steady_foot.influence != 1.0 or not bool(steady_foot.get("enabled")): return "foot support unavailable"
	# The proof samples cover the town's flat ground. Curbs, rooms and tilted
	# support planes can change final IK without changing the clip name.
	for side: String in ["L", "R"]:
		var bone: int = LivingPose.bone(get_skeleton(), "foot." + side)
		if bone < 0: return "missing foot"
		var ankle: Vector3 = get_skeleton().to_global(get_skeleton().get_bone_global_pose(bone).origin)
		var floor: Dictionary = steady_foot.call("floor_below", ankle)
		if floor.is_empty() or absf((floor.position as Vector3).y) > .0001 or (floor.normal as Vector3).dot(Vector3.UP) < .99999: return "outside certified flat ground"
		var painted: float = steady_foot.call("visible_town_height", Vector2(ankle.x, ankle.z))
		var root_height_error: float = minf(absf(npc.global_position.y), absf(npc.global_position.y - .010))
		if not is_finite(painted) or absf(painted - .010) > .0001 or root_height_error > .00001: return "outside certified ground height"
	if steady_morph_policy == AUTHORED_SHAPES.POLICY:
		var morph_rejection: String = AUTHORED_SHAPES.mismatch(steady_morph_plan, clip, steady_animation.current_animation_position, original_values)
		if morph_rejection != "": return morph_rejection
	else:
		for value: float in original_values:
			if value != 0: return "additional morph"
	for child: Node in get_skeleton().get_children():
		if not child is SkeletonModifier3D: continue
		var modifier: SkeletonModifier3D = child as SkeletonModifier3D
		if not modifier.active or modifier.influence <= 0: continue
		var script: Script = modifier.get_script() as Script
		if script == null or script.resource_path not in STEADY_MODIFIERS: return "additional pose modifier"
	return ""

func record_elapsed(began: int) -> void:
	var elapsed: int = Time.get_ticks_usec() - began
	updates += 1
	total_usec += elapsed
	max_usec = maxi(max_usec, elapsed)
	frame_times.append(elapsed)
	if frame_times.size() > 240: frame_times.remove_at(0)

func source_signature(index: int, points: PackedVector3Array, binds: PackedInt32Array, weights: PackedFloat32Array, influences: int) -> PackedByteArray:
	var signature: PackedByteArray = PackedVector3Array([points[index]]).to_byte_array()
	signature.append_array(binds.slice(index * influences, (index + 1) * influences).to_byte_array())
	signature.append_array(weights.slice(index * influences, (index + 1) * influences).to_byte_array())
	return signature

func prepare(model: Node3D, profile: Dictionary) -> void:
	native_contact_prepare()
	character = str(profile.get("character", ""))
	native_geometry_prepare()
	# Scale each shared cloth vertex once before rebuilding ordered face
	# corners. Kazu's changing leg pose needs full contact solves; this avoids
	# repeated multiplies without changing geometry or any body constraint.
	diagnostic_unique_panel_scaling = character == "kazuko"
	# Generic profile rule: retain every original body vertex and add
	# physical pure-body edge midpoints, without clip/phase/face IDs.
	var supplement_body_edges: bool = character == "mio"
	if supplement_body_edges:
		body_edge_min_rest_length_m = .015
		body_edge_policy = "mio: physical pure-body edges with rest length >15mm; no centroids"
	proxy_target_triangles = float(profile.get("proxy_target_triangles", 1400.0))
	var proxy_export_dir := ""
	for argument: String in OS.get_cmdline_user_args():
		if (argument == "--garment-risk-contact" and character in ["mio", "kazuko"]) or argument == "--garment-risk-contact-" + character:
			diagnostic_risk_contact = true
			diagnostic_proxy_override = true
		if argument == "--garment-fixed-layer-reuse":
			diagnostic_fixed_layer_reuse = true
			diagnostic_proxy_override = true
		if argument == "--garment-skin-direction-skip":
			diagnostic_skin_direction_skip = true
			diagnostic_proxy_override = true
		if argument == "--garment-layer-geometry-cache":
			diagnostic_layer_geometry_cache = true
			diagnostic_proxy_override = true
		if argument == "--garment-unique-panel-scaling":
			diagnostic_unique_panel_scaling = true
			diagnostic_proxy_override = true
		if argument == "--garment-safe-face-cache":
			diagnostic_safe_face_cache = true
			diagnostic_proxy_override = true
		if argument == "--garment-fine-contact" or argument == "--garment-fine-contact-" + character:
			diagnostic_fine_contact = true
			diagnostic_proxy_override = true
		var quality_flag: String = "--garment-proxy-" + character + "="
		if argument.begins_with(quality_flag):
			proxy_target_triangles = maxf(800.0, argument.trim_prefix(quality_flag).to_float())
			diagnostic_proxy_override = true
		if argument.begins_with("--garment-proxy-export-dir="): proxy_export_dir = argument.trim_prefix("--garment-proxy-export-dir=")
	var rgb: Array = profile.get("body_rgb_reference", [.92, .73, .63])
	body_rgb = Vector3(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	body_rgb_tolerance = float(profile.get("body_rgb_tolerance", .12))
	margin = float(profile.get("clearance_margin_m", .003))
	maximum_weight = float(profile.get("maximum_weight", 1.0))
	var prefix: String = str(profile.get("shape_prefix", "Garment_Local_"))
	for candidate: MeshInstance3D in WorldBuilder.find_meshes(model):
		if candidate.skin == null or not candidate.mesh is ArrayMesh: continue
		var candidate_geometry: ArrayMesh = candidate.mesh as ArrayMesh
		for shape: int in candidate_geometry.get_blend_shape_count():
			if str(candidate_geometry.get_blend_shape_name(shape)).begins_with(prefix):
				mesh = candidate
				break
		if mesh != null: break
	if mesh == null: return
	var geometry: ArrayMesh = mesh.mesh as ArrayMesh
	var arrays: Array = geometry.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bone_indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var imported_shapes: Array = geometry.surface_get_blend_shape_arrays(0)
	var local_deltas: Array[PackedVector3Array] = []
	var relative: bool = geometry.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	var disabled_global_shapes: Array = profile.get("disable_global_shapes", ["Skirt_Clearance", "Apron_Clearance"])
	for shape: int in geometry.get_blend_shape_count():
		var name: String = str(geometry.get_blend_shape_name(shape))
		if name in disabled_global_shapes:
			disabled_indices.append(shape)
			mesh.set_blend_shape_value(shape, 0)
		if name.begins_with(prefix):
			local_indices.append(shape)
			var vertices: PackedVector3Array = imported_shapes[shape][Mesh.ARRAY_VERTEX]
			var delta: PackedVector3Array = vertices.duplicate()
			if not relative:
				for index: int in delta.size(): delta[index] -= points[index]
			local_deltas.append(delta)
		else: original_indices.append(shape)
	amounts.resize(local_indices.size())
	var front_mask := PackedByteArray()
	var back_mask := PackedByteArray()
	front_mask.resize(points.size())
	back_mask.resize(points.size())
	var front_amplitudes := PackedFloat32Array()
	var back_amplitudes := PackedFloat32Array()
	front_amplitudes.resize(points.size())
	back_amplitudes.resize(points.size())
	for patch: int in local_indices.size():
		var front: bool = str(geometry.get_blend_shape_name(local_indices[patch])).contains("_Front_")
		for index: int in points.size():
			if front: front_amplitudes[index] += absf(local_deltas[patch][index].z)
			else: back_amplitudes[index] += absf(local_deltas[patch][index].z)
	# Qualification is independent of how many basis columns represent a panel.
	# Splitting one field into96 smaller columns must not silently drop support.
	for index: int in points.size():
		if front_amplitudes[index] >= .000001: front_mask[index] = 1
		if back_amplitudes[index] >= .000001: back_mask[index] = 1
	var levels: Array[PackedInt32Array] = []
	levels.append(arrays[Mesh.ARRAY_INDEX])
	var raw: Dictionary = (geometry.get("_surfaces") as Array)[0]
	var lods: Array = raw.get("lods", [])
	var bytes: int = 2 if points.size() <= 65536 else 4
	for offset: int in range(0, lods.size(), 2):
		var blob: PackedByteArray = lods[offset + 1]
		var indices := PackedInt32Array()
		indices.resize(blob.size() / bytes)
		for index: int in indices.size(): indices[index] = blob.decode_u16(index * bytes) if bytes == 2 else blob.decode_u32(index * bytes)
		levels.append(indices)
	var selected: Dictionary = {}
	var full_source_candidate: Dictionary = {}
	var best := INF
	var proxy_export_levels: Array[Dictionary] = []
	for level: PackedInt32Array in levels:
		var candidate: Dictionary = {"front": PackedInt32Array(), "back": PackedInt32Array()}
		for offset: int in range(0, level.size(), 3):
			var a: int = level[offset]
			var b: int = level[offset + 1]
			var c: int = level[offset + 2]
			for layer: String in ["front", "back"]:
				var mask: PackedByteArray = front_mask if layer == "front" else back_mask
				if mask[a] and mask[b] and mask[c]:
					var triangles: PackedInt32Array = candidate[layer]
					triangles.append_array(PackedInt32Array([a, b, c]))
					candidate[layer] = triangles
		var total: int = (candidate.front as PackedInt32Array).size() / 3 + (candidate.back as PackedInt32Array).size() / 3
		if full_source_candidate.is_empty(): full_source_candidate = candidate
		proxy_candidates.append({"total_triangles": total, "front": (candidate.front as PackedInt32Array).size() / 3, "back": (candidate.back as PackedInt32Array).size() / 3})
		if proxy_export_dir != "": proxy_export_levels.append(candidate)
		var score: float = absf(float(total) - proxy_target_triangles) if total >= 800 and (candidate.front as PackedInt32Array).size() >= 600 and (candidate.back as PackedInt32Array).size() >= 600 else INF
		if selected.is_empty() or score < best:
			selected = candidate
			best = score
	if diagnostic_fine_contact: selected = full_source_candidate
	if diagnostic_risk_contact:
		var mapped: Dictionary = RISK_MAPPER.map_proxy(mesh, get_skeleton(), profile.get("fine_risk_proxy", {}), arrays, imported_shapes, front_mask, back_mask)
		risk_mapping = mapped.duplicate()
		risk_mapping.erase("faces")
		if bool(mapped.valid): selected = mapped.faces
		else:
			# Invalid source identity never silently becomes a cheap positive run.
			# The diagnostic falls back to complete original fine cloth instead.
			selected = full_source_candidate
			diagnostic_fine_contact = true
		if bool(mapped.valid):
			body_edge_min_rest_length_m = float((profile.get("fine_risk_proxy", {}).get("body_query_policy", {}) as Dictionary).get("edge_rest_min_length_m", -1.0))
			risk_model = model
			risk_asset_root_transform = model.transform
			risk_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if risk_animation != null:
				for clip_name: String in risk_animation.get_animation_list():
					if clip_name != "" and clip_name != "RESET": risk_animation_clips.append(clip_name)
				risk_animation_clips.sort()
			risk_profile_identity = RISK_MAPPER.profile_identity(profile.get("fine_risk_proxy", {}))
			refresh_risk_proof()
	if selected.is_empty(): return
	if proxy_export_dir != "":
		# QA-only rest geometry export lets the independent auditor compare every
		# imported proxy level under one real final pose, without extra captures.
		var exported_points: Array = []
		var exported_uvs: Array = []
		for export_index: int in points.size():
			exported_points.append([points[export_index].x, points[export_index].y, points[export_index].z])
			exported_uvs.append([uv[export_index].x, uv[export_index].y])
		DirAccess.make_dir_recursive_absolute(proxy_export_dir)
		var export_file: FileAccess = FileAccess.open(proxy_export_dir.path_join("garment-proxy-" + character + ".json"), FileAccess.WRITE)
		if export_file != null: export_file.store_string(JSON.stringify({"character": character, "mesh": str(mesh.name), "positions": exported_points, "uv": exported_uvs, "levels": proxy_export_levels, "candidates": proxy_candidates, "selected_target_triangles": proxy_target_triangles}))
	var material: BaseMaterial3D = mesh.get_active_material(0) as BaseMaterial3D
	if material == null or material.albedo_texture == null: return
	var atlas: Image = material.albedo_texture.get_image()
	if atlas.is_compressed(): atlas.decompress()
	var height := 0.0
	for point: Vector3 in points: height = maxf(height, point.y)
	var needed: Dictionary = {}
	for layer: String in ["front", "back"]:
		for index: int in selected[layer]: needed[index] = true
	var body_source := PackedInt32Array()
	var dedup: Dictionary = {}
	var body_source_alias: Dictionary = {}
	var influences: int = bone_indices.size() / points.size()
	var non_black_seams: Dictionary = {}
	var original_ren_body := PackedInt32Array()
	if character == "kazuko":
		for seam_index: int in points.size():
			var seam_uv: Vector2 = uv[seam_index]
			var seam_colour: Color = atlas.get_pixel(posmod(int(seam_uv.x * atlas.get_width()), atlas.get_width()), posmod(int(seam_uv.y * atlas.get_height()), atlas.get_height()))
			if maxf(seam_colour.r, maxf(seam_colour.g, seam_colour.b)) >= .36 or maxf(seam_colour.r, maxf(seam_colour.g, seam_colour.b)) - minf(seam_colour.r, minf(seam_colour.g, seam_colour.b)) >= .08:
				non_black_seams[source_signature(seam_index, points, bone_indices, weights, influences)] = true
	for index: int in points.size():
		var point: Vector3 = points[index]
		if absf(point.x) > .16 * height or point.y < .20 * height or point.y > .55 * height: continue
		var colour: Color = atlas.get_pixel(posmod(int(uv[index].x * atlas.get_width()), atlas.get_width()), posmod(int(uv[index].y * atlas.get_height()), atlas.get_height()))
		var is_body: bool = colour.r > colour.g * 1.10 and colour.g > colour.b * 1.02 and colour.r > .30 if character == "mio" else maxf(colour.r, maxf(colour.g, colour.b)) < .36
		if character == "ren": is_body = colour.r > colour.g * 1.04 and colour.g > colour.b * 1.08
		if character == "kazuko": is_body = is_body and maxf(colour.r, maxf(colour.g, colour.b)) - minf(colour.r, minf(colour.g, colour.b)) < .08
		if not is_body: continue
		if character == "ren": original_ren_body.append(index)
		if character == "mio":
			var leg_share := 0.0
			for influence: int in influences:
				var bind: int = bone_indices[index * influences + influence]
				var bone: int = mesh.skin.get_bind_bone(bind)
				var bone_name: String = get_skeleton().get_bone_name(bone) if bone >= 0 else String(mesh.skin.get_bind_name(bind))
				if "UpLeg" in bone_name or bone_name.ends_with("Leg") or "Foot" in bone_name or "Toe" in bone_name: leg_share += weights[index * influences + influence]
			# Mio's tan shoulder bag also passes a skin-colour threshold. Real
			# legs must carry leg bindings; never treat the bag as a thigh.
			if leg_share <= .65: continue
			if Vector3(colour.r, colour.g, colour.b).distance_to(body_rgb) >= body_rgb_tolerance: continue
		# UV seam duplicates may be merged only with identical bind and weights.
		var signature: PackedByteArray = source_signature(index, points, bone_indices, weights, influences)
		if non_black_seams.has(signature): continue
		if dedup.has(signature):
			if diagnostic_fine_contact or diagnostic_risk_contact or supplement_body_edges: body_source_alias[index] = dedup[signature]
			continue
		dedup[signature] = index
		if diagnostic_fine_contact or diagnostic_risk_contact or supplement_body_edges: body_source_alias[index] = index
		body_source.append(index)
		needed[index] = true
	if character == "ren":
		var original_colours: Array[Color] = []
		for source_uv: Vector2 in uv:
			original_colours.append(atlas.get_pixel(posmod(int(source_uv.x * atlas.get_width()), atlas.get_width()), posmod(int(source_uv.y * atlas.get_height()), atlas.get_height())))
		var hip_z: float = get_skeleton().get_bone_global_rest(LivingPose.bone(get_skeleton(), "hips")).origin.z
		var independent_paint: Dictionary = BODY_CLASSIFIER.ren_pigment_flags(points, original_colours, height, hip_z)
		body_classification_preparation = BODY_CLASSIFIER.classify(original_ren_body, {"front": front_amplitudes, "back": back_amplitudes}, points, levels[0], uv, bone_indices, weights, influences, original_colours, independent_paint)
		var retained_source: PackedInt32Array = body_classification_preparation.retained_indices
		var retained_labels: Dictionary = {}
		for retained_vertex: int in retained_source: retained_labels[retained_vertex] = true
		var semantic_body := PackedInt32Array()
		for original_source: int in body_source:
			if retained_labels.has(original_source): semantic_body.append(original_source)
		body_source = semantic_body
		for alias_source: int in body_source_alias.keys():
			if not retained_labels.has(alias_source): body_source_alias.erase(alias_source)
		body_classification_preparation.erase("retained_indices")
	var skeleton: Skeleton3D = get_skeleton()
	var slots: Dictionary = {}
	for source: int in needed:
		var index: int = positions.size()
		source_ids.append(source)
		source_lookup[source] = index
		positions.append(points[source])
		var ids := PackedInt32Array()
		var coefficients := PackedFloat32Array()
		for patch: int in local_deltas.size():
			var coefficient: float = local_deltas[patch][source].z
			if absf(coefficient) < .0000001: continue
			ids.append(patch)
			coefficients.append(coefficient)
		patch_ids.append(ids)
		patch_coefficients.append(coefficients)
		if not ids.is_empty(): deforming_vertices.append(index)
		bone_offsets.append(bone_weights.size())
		for influence: int in influences:
			var weight: float = weights[source * influences + influence]
			if weight <= 0: continue
			var bind: int = bone_indices[source * influences + influence]
			if not slots.has(bind):
				slots[bind] = bone_ids.size()
				var bone: int = mesh.skin.get_bind_bone(bind)
				if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
				bone_ids.append(bone)
				inverse_binds.append(mesh.skin.get_bind_pose(bind))
			bone_slots.append(slots[bind])
			bone_weights.append(weight)
	bone_offsets.append(bone_weights.size())
	for original: int in original_indices:
		var values: PackedVector3Array = imported_shapes[original][Mesh.ARRAY_VERTEX]
		var shape_vertices := PackedInt32Array()
		var shape_deltas := PackedVector3Array()
		for compact: int in source_ids.size():
			var source: int = source_ids[compact]
			var delta: Vector3 = values[source] if relative else values[source] - points[source]
			if delta == Vector3.ZERO: continue
			shape_vertices.append(compact)
			shape_deltas.append(delta)
		original_morph_vertices.append(shape_vertices)
		original_morph_deltas.append(shape_deltas)
	for source: int in body_source: body.append(source_lookup[source])
	physical_body_anchors = body.size()
	if diagnostic_fine_contact or diagnostic_risk_contact or supplement_body_edges:
		# Original fine/risk modes keep their centroids; the default Mio supplement
		# adds only distinct sufficiently long physical pure-body edge midpoints.
		# Every fully classified physical body triangle contributes its centroid in diagnostics.
		# Interpolate its FINAL skinned corners at callback time. In particular,
		# interpolating rest coordinates/weights would give a different surface.
		var original_triangles: PackedInt32Array = levels[0]
		var seen_body_faces: Dictionary = {}
		var seen_body_edges: Dictionary = {}
		for body_offset: int in range(0, original_triangles.size(), 3):
			var body_a: int = original_triangles[body_offset]
			var body_b: int = original_triangles[body_offset + 1]
			var body_c: int = original_triangles[body_offset + 2]
			if not body_source_alias.has(body_a) or not body_source_alias.has(body_b) or not body_source_alias.has(body_c): continue
			var compact_body := PackedInt32Array([source_lookup[body_source_alias[body_a]], source_lookup[body_source_alias[body_b]], source_lookup[body_source_alias[body_c]]])
			var body_key: PackedInt32Array = compact_body.duplicate()
			body_key.sort()
			if seen_body_faces.has(body_key): continue
			seen_body_faces[body_key] = true
			if diagnostic_fine_contact or diagnostic_risk_contact:
				body.append(positions.size() + body_surface_triangles.size() / 3)
				body_surface_triangles.append_array(compact_body)
			if body_edge_min_rest_length_m > 0:
				for edge_corners: Vector2i in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]:
					var edge_a: int = compact_body[edge_corners.x]
					var edge_b: int = compact_body[edge_corners.y]
					if positions[edge_a].distance_to(positions[edge_b]) <= body_edge_min_rest_length_m: continue
					var edge_key := Vector2i(mini(edge_a, edge_b), maxi(edge_a, edge_b))
					if seen_body_edges.has(edge_key): continue
					seen_body_edges[edge_key] = true
					body_surface_edges.append_array(PackedInt32Array([edge_a, edge_b]))
		for edge_index: int in body_surface_edges.size() / 2:
			body.append(positions.size() + body_surface_triangles.size() / 3 + edge_index)
	for layer: String in ["front", "back"]:
		var triangles := PackedInt32Array()
		var vertices := PackedInt32Array()
		var visited: Dictionary = {}
		for source: int in selected[layer]:
			var index: int = source_lookup[source]
			triangles.append(index)
			if not visited.has(index):
				visited[index] = true
				vertices.append(index)
		faces[layer] = triangles
		panel_vertices[layer] = vertices
		# A triangle can affect only the union of its three corner supports.
		# Store that union in increasing patch order, preserving the original
		# floating-point constraint/update order while skipping exact zero terms.
		var triangle_patches: Array[PackedInt32Array] = []
		for offset: int in range(0, triangles.size(), 3):
			var present := PackedByteArray()
			present.resize(local_indices.size())
			for corner: int in 3:
				for patch: int in patch_ids[triangles[offset + corner]]: present[patch] = 1
			var active := PackedInt32Array()
			for patch: int in local_indices.size():
				if present[patch]: active.append(patch)
			triangle_patches.append(active)
		face_patch_ids[layer] = triangle_patches
		var layer_support := PackedByteArray()
		layer_support.resize(local_indices.size())
		for vertex: int in vertices:
			for patch: int in patch_ids[vertex]: layer_support[patch] = 1
		var ordered_layer_support := PackedInt32Array()
		for patch: int in local_indices.size():
			if layer_support[patch]: ordered_layer_support.append(patch)
		layer_patch_ids[layer] = ordered_layer_support
	native_contact_body_ordinals.resize(body.size())
	for native_ordinal: int in body.size(): native_contact_body_ordinals[native_ordinal] = native_ordinal
	if character in STEADY_CHARACTERS:
		steady_model = model
		steady_asset_root_transform = model.transform
		steady_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		steady_natural = get_skeleton().get_node_or_null("NaturalLocomotionPose") as SkeletonModifier3D
		steady_foot = get_skeleton().get_node_or_null("CharacterFootSupport") as SkeletonModifier3D
		steady_actor = steady_natural.get("actor") as Node3D if steady_natural != null else null
		steady_mesh_id = mesh.mesh.get_instance_id()
		steady_skin_id = mesh.skin.get_instance_id()
		refresh_steady_proof()

func contact_face_certificate(posed: PackedVector3Array, triangles: PackedInt32Array, face_index: int) -> Array:
	var offset: int = face_index * 3
	var origin: Vector3 = posed[triangles[offset]]
	var first3: Vector3 = posed[triangles[offset + 1]] - origin
	var second3: Vector3 = posed[triangles[offset + 2]] - origin
	var first := Vector2(first3.x, first3.y)
	var second := Vector2(second3.x, second3.y)
	var determinant: float = first.cross(second)
	var normal: Vector3 = first3.cross(second3)
	var eligible: bool = absf(determinant) >= .00000001 and absf(normal.z) >= normal.length() * .35
	var guard := Vector3.ZERO
	if eligible:
		# The source tree snaps by1 micrometre physically. Shrink all projected
		# triangle edges by2 micrometres; with the normal slope bound,20 extra
		# micrometres in depth conservatively reject numerical boundary cases.
		guard = Vector3((second - first).length(), second.length(), first.length()) * (.000002 / absf(determinant))
	return [origin, first, second, determinant, first3.z, second3.z, eligible, guard]

func patch_value_signature(values: PackedFloat32Array, support: PackedInt32Array) -> PackedByteArray:
	var selected := PackedFloat32Array()
	selected.resize(support.size())
	for slot: int in support.size(): selected[slot] = values[support[slot]]
	return selected.to_byte_array()

func _process_modification() -> void:
	if mesh == null or not mesh.is_visible_in_tree(): return
	var began: int = Time.get_ticks_usec()
	last_callback_frame = Engine.get_process_frames()
	frame_ray_queries = 0
	frame_broadphase_skips = 0
	for shape: int in disabled_indices: mesh.set_blend_shape_value(shape, 0)
	var skeleton: Skeleton3D = get_skeleton()
	var matrices: Array[Transform3D] = []
	for slot: int in bone_ids.size(): matrices.append(skeleton.get_bone_global_pose(bone_ids[slot]) * inverse_binds[slot])
	var original_values := PackedFloat32Array()
	for shape: int in original_indices: original_values.append(mesh.get_blend_shape_value(shape))
	last_steady_reason = steady_rejection(original_values)
	if enabled and last_steady_reason == "":
		amounts.fill(0)
		for patch: int in local_indices.size(): mesh.set_blend_shape_value(local_indices[patch], 0)
		cached_amounts = amounts.duplicate()
		cached_matrices = matrices
		cached_original_values = original_values
		cached_enabled = enabled
		max_contact_depth = 0.0
		max_displacement = 0.0
		saturated_constraints = 0
		active_targets = 0
		steady_fast_updates += 1
		last_branch = "steady_fast"
		record_elapsed(began)
		return
	if cached_matrices == matrices and cached_original_values == original_values and cached_enabled == enabled and cached_amounts.size() == local_indices.size():
		for patch: int in local_indices.size(): mesh.set_blend_shape_value(local_indices[patch], cached_amounts[patch])
		cache_hits += 1
		last_branch = "pose_cache"
		record_elapsed(began)
		return
	last_branch = "full"
	cached_matrices = matrices
	cached_original_values = original_values
	cached_enabled = enabled
	amounts.fill(0)
	max_contact_depth = 0.0
	saturated_constraints = 0
	max_displacement = 0.0
	active_targets = 0
	var skin_elapsed := 0
	var contact_elapsed := 0
	if enabled:
		var base := PackedVector3Array()
		var directions := PackedVector3Array()
		base.resize(positions.size())
		directions.resize(positions.size())
		last_original_values = original_values
		# Process only active morph tracks and their exact nonzero support. This
		# matters for action drape: two neighboring targets are active, while all
		# the other phase targets are zero. Per-vertex accumulation order remains
		# the original increasing shape order, with identical arithmetic.
		var morphed_rest: PackedVector3Array = positions.duplicate()
		for shape: int in original_values.size():
			var original_amount: float = original_values[shape]
			if original_amount == 0: continue
			for affected_index: int in original_morph_vertices[shape].size():
				var vertex: int = original_morph_vertices[shape][affected_index]
				morphed_rest[vertex] += original_morph_deltas[shape][affected_index] * original_amount
		for index: int in positions.size():
			var rest: Vector3 = morphed_rest[index]
			var point := Vector3.ZERO
			var direction := Vector3.ZERO
			var needs_direction: bool = not diagnostic_skin_direction_skip or not patch_ids[index].is_empty()
			for influence: int in range(bone_offsets[index], bone_offsets[index + 1]):
				var transform: Transform3D = matrices[bone_slots[influence]]
				var weight: float = bone_weights[influence]
				point += (transform * rest) * weight
				if needs_direction: direction += transform.basis.z * weight
			base[index] = point
			directions[index] = direction
		for surface_offset: int in range(0, body_surface_triangles.size(), 3):
			base.append((base[body_surface_triangles[surface_offset]] + base[body_surface_triangles[surface_offset + 1]] + base[body_surface_triangles[surface_offset + 2]]) / 3.0)
		for edge_offset: int in range(0, body_surface_edges.size(), 2):
			base.append((base[body_surface_edges[edge_offset]] + base[body_surface_edges[edge_offset + 1]]) * .5)
		skin_elapsed = Time.get_ticks_usec() - began
		var contact_began: int = Time.get_ticks_usec()
		var native_body_points := PackedVector3Array()
		if native_contact_ready and not diagnostic_safe_face_cache:
			var native_pack_began: int = Time.get_ticks_usec()
			native_body_points.resize(body.size())
			for native_slot: int in body.size(): native_body_points[native_slot] = base[body[native_slot]]
			native_contact_pack_usec += Time.get_ticks_usec() - native_pack_began
		var posed: PackedVector3Array = base.duplicate()
		# Callback-local only: geometry and body are immutable for these exact
		# support values. Never reuse a previous frame or a changed local field.
		var fixed_layers: Dictionary = {}
		# This second cache contains only immutable geometry-derived data. An
		# entry-amount change still runs every original body constraint in order.
		# Bone matrices and all original/global morphs are fixed within this call.
		var geometry_layers: Dictionary = {}
		for iteration: int in 4:
			total_iterations += 1
			var iteration_amounts: PackedFloat32Array = amounts.duplicate()
			# First iteration is already the base. Later iterations update only
			# cloth support; body anchors remain exact.
			if iteration > 0:
				for index: int in deforming_vertices:
					var distance := 0.0
					for slot: int in patch_ids[index].size(): distance += patch_coefficients[index][slot] * amounts[patch_ids[index][slot]]
					posed[index] = base[index] + directions[index] * distance
			var increased := false
			for layer: String in ["front", "back"]:
				var bounds_began: int = Time.get_ticks_usec()
				var triangles: PackedInt32Array = faces[layer]
				if triangles.is_empty(): continue
				var geometry_signature := PackedByteArray()
				var entry_signature := PackedByteArray()
				var layer_saturated_before: int = saturated_constraints
				if diagnostic_fixed_layer_reuse or diagnostic_layer_geometry_cache:
					var complete_support: PackedInt32Array = layer_patch_ids[layer]
					geometry_signature = patch_value_signature(iteration_amounts, complete_support)
				if diagnostic_fixed_layer_reuse:
					var fixed_support: PackedInt32Array = layer_patch_ids[layer]
					entry_signature = patch_value_signature(amounts, fixed_support)
					if fixed_layers.has(layer):
						var fixed: Dictionary = fixed_layers[layer]
						if fixed.geometry == geometry_signature and fixed.entry == entry_signature:
							saturated_constraints += int(fixed.saturated)
							total_fixed_layer_reuses += 1
							continue
				var sign_z: float = 1.0 if layer == "front" else -1.0
				var lower := Vector3(INF, INF, INF)
				var upper := Vector3(-INF, -INF, -INF)
				var columns := 0
				var rows := 0
				var depth_bounds := PackedFloat32Array()
				var tree: TriangleMesh
				var geometry_reused := false
				var geometry_entry: Dictionary = {}
				if diagnostic_layer_geometry_cache and geometry_layers.has(layer):
					geometry_entry = geometry_layers[layer]
					if geometry_entry.signature == geometry_signature:
						lower = geometry_entry.lower
						upper = geometry_entry.upper
						columns = int(geometry_entry.columns)
						rows = int(geometry_entry.rows)
						depth_bounds = geometry_entry.depth_bounds
						tree = geometry_entry.tree as TriangleMesh
						geometry_reused = true
						total_layer_geometry_cache_hits += 1
				if not geometry_reused:
					var native_geometry: Dictionary = {}
					if native_geometry_enabled and native_contact_ready and ClassDB.class_has_method(&"NativeTriangleFilter", &"build_layer_geometry"):
						var native_geometry_value: Variant = ClassDB.class_call_static(&"NativeTriangleFilter", &"build_layer_geometry", posed, panel_vertices[layer], triangles, sign_z)
						if native_geometry_value is Dictionary and native_geometry_valid(native_geometry_value as Dictionary): native_geometry = native_geometry_value
					if not native_geometry.is_empty():
						lower = native_geometry.lower
						upper = native_geometry.upper
						columns = int(native_geometry.columns)
						rows = int(native_geometry.rows)
						depth_bounds = native_geometry.depth_bounds
						native_geometry_calls += 1
					else:
						if native_geometry_enabled: native_geometry_fallbacks += 1
						for index: int in panel_vertices[layer]:
							lower = lower.min(posed[index])
							upper = upper.max(posed[index])
						columns = maxi(1, ceili((upper.x - lower.x) * 25.0) + 1)
						rows = maxi(1, ceili((upper.y - lower.y) * 25.0) + 1)
						depth_bounds.resize(columns * rows)
						depth_bounds.fill(INF)
						for offset: int in range(0, triangles.size(), 3):
							var triangle_a: Vector3 = posed[triangles[offset]]
							var triangle_b: Vector3 = posed[triangles[offset + 1]]
							var triangle_c: Vector3 = posed[triangles[offset + 2]]
							var triangle_lower: Vector3 = triangle_a.min(triangle_b).min(triangle_c)
							var triangle_upper: Vector3 = triangle_a.max(triangle_b).max(triangle_c)
							var signed_lower: float = minf(triangle_a.z * sign_z, minf(triangle_b.z * sign_z, triangle_c.z * sign_z))
							var first_x: int = clampi(floori((triangle_lower.x - lower.x - .000001) * 25), 0, columns - 1)
							var last_x: int = clampi(floori((triangle_upper.x - lower.x + .000001) * 25), 0, columns - 1)
							var first_y: int = clampi(floori((triangle_lower.y - lower.y - .000001) * 25), 0, rows - 1)
							var last_y: int = clampi(floori((triangle_upper.y - lower.y + .000001) * 25), 0, rows - 1)
							for cell_y: int in range(first_y, last_y + 1):
								for cell_x: int in range(first_x, last_x + 1):
									var cell: int = cell_y * columns + cell_x
									depth_bounds[cell] = minf(depth_bounds[cell], signed_lower)
				total_bounds_usec += Time.get_ticks_usec() - bounds_began
				var query_began: int = Time.get_ticks_usec()
				var layer_build_usec := 0
				var slopes := PackedFloat32Array()
				slopes.resize(amounts.size())
				var barycentric := PackedFloat32Array()
				barycentric.resize(3)
				var triangle_patches: Array = face_patch_ids[layer]
				# Posed face geometry is immutable for this layer/iteration. Many
				# dense body anchors hit the same proxy face; compute its Vector2
				# edges/cross only once, retaining the exact original arithmetic.
				var face_cache: Array = []
				if geometry_reused:
					face_cache = geometry_entry.face_cache
				else:
					face_cache.resize(triangles.size() / 3)
				var certificate_cells: Array = []
				if diagnostic_safe_face_cache: certificate_cells.resize(columns * rows)
				var native_layer: bool = native_contact_ready and not diagnostic_safe_face_cache
				var native_result: Dictionary = {}
				if native_layer:
					var eager_this_layer: bool = tree == null
					if tree == null:
						var native_tree_build_began: int = Time.get_ticks_usec()
						var native_tree_points := PackedVector3Array()
						native_tree_points.resize(triangles.size())
						if diagnostic_unique_panel_scaling:
							var native_tree_scaled_panel := PackedVector3Array()
							native_tree_scaled_panel.resize(posed.size())
							var native_tree_unique_panel: PackedInt32Array = panel_vertices[layer]
							for native_tree_panel_index: int in native_tree_unique_panel: native_tree_scaled_panel[native_tree_panel_index] = posed[native_tree_panel_index] * RAY_SPACE_SCALE
							for native_tree_scaled_corner: int in triangles.size(): native_tree_points[native_tree_scaled_corner] = native_tree_scaled_panel[triangles[native_tree_scaled_corner]]
							total_tree_scale_inputs += native_tree_unique_panel.size()
							total_tree_scale_multiplications_saved += triangles.size() - native_tree_unique_panel.size()
						else:
							for native_tree_face_corner: int in triangles.size(): native_tree_points[native_tree_face_corner] = posed[triangles[native_tree_face_corner]] * RAY_SPACE_SCALE
							total_tree_scale_inputs += triangles.size()
						tree = TriangleMesh.new()
						tree.create_from_faces(native_tree_points)
						layer_build_usec = Time.get_ticks_usec() - native_tree_build_began
						total_tree_build_usec += layer_build_usec
						total_tree_builds += 1
					if eager_this_layer: native_contact_eager_trees += 1
					native_result = NATIVE_CONTACT.filter_layer(tree, native_body_points, lower, upper, depth_bounds, columns, rows, sign_z, margin, RAY_SPACE_SCALE, max_contact_depth)
					if not NATIVE_CONTACT.valid_result(native_result, body.size(), triangles.size() / 3):
						native_layer = false
						native_contact_ready = false
						native_contact_reason = "invalid native output; full GD fallback"
					else:
						native_contact_layers += 1
						frame_ray_queries += int(native_result.raw_queries)
						frame_broadphase_skips += int(native_result.broadphase_skips)
						max_contact_depth = float(native_result.max_contact_depth)
						if eager_this_layer and int(native_result.raw_queries) == 0: native_contact_zero_query_trees += 1
				var query_ordinals: PackedInt32Array = native_contact_body_ordinals
				if native_layer: query_ordinals = native_result.indices
				var native_cursor := 0
				for body_ordinal: int in query_ordinals:
					var index: int = body[body_ordinal]
					var point: Vector3 = base[index]
					var hit: Dictionary = {}
					var depth := 0.0
					var certificate_cell := -1
					if native_layer:
						hit = (native_result.hits as Array)[native_cursor]
						depth = (native_result.depths as PackedFloat64Array)[body_ordinal]
						native_cursor += 1
					else:
						if point.x < lower.x or point.x > upper.x or point.y < lower.y or point.y > upper.y: continue
						if (sign_z > 0 and point.z < lower.z - margin) or (sign_z < 0 and point.z > upper.z + margin): continue
						var cell_x: int = clampi(floori((point.x - lower.x) * 25), 0, columns - 1)
						var cell_y: int = clampi(floori((point.y - lower.y) * 25), 0, rows - 1)
						if point.z * sign_z <= depth_bounds[cell_y * columns + cell_x] - margin:
							frame_broadphase_skips += 1
							continue
						certificate_cell = cell_y * columns + cell_x
						if diagnostic_safe_face_cache and certificate_cells[certificate_cell] != null:
							var certified := false
							var recent_faces: PackedInt32Array = certificate_cells[certificate_cell]
							for recent_face: int in recent_faces:
								var certificate: Array = face_cache[recent_face]
								if not bool(certificate[6]): continue
								var cert_origin: Vector3 = certificate[0]
								var cert_first: Vector2 = certificate[1]
								var cert_second: Vector2 = certificate[2]
								var cert_at := Vector2(point.x - cert_origin.x, point.y - cert_origin.y)
								var cert_det: float = certificate[3]
								var cert_u: float = cert_at.cross(cert_second) / cert_det
								var cert_v: float = cert_first.cross(cert_at) / cert_det
								var cert_guard: Vector3 = certificate[7]
								total_certificate_tests += 1
								if cert_u <= cert_guard.y or cert_v <= cert_guard.z or 1.0 - cert_u - cert_v <= cert_guard.x: continue
								var cert_z: float = cert_origin.z + cert_u * float(certificate[4]) + cert_v * float(certificate[5])
								if sign_z * (point.z - cert_z) < -margin - .00002:
									certified = true
									break
							if certified:
								total_certified_ray_skips += 1
								continue
						if tree == null:
							var build_began: int = Time.get_ticks_usec()
							var points := PackedVector3Array()
							points.resize(triangles.size())
							if diagnostic_unique_panel_scaling:
								var scaled_panel := PackedVector3Array()
								scaled_panel.resize(posed.size())
								var unique_panel: PackedInt32Array = panel_vertices[layer]
								for panel_index: int in unique_panel: scaled_panel[panel_index] = posed[panel_index] * RAY_SPACE_SCALE
								for scaled_corner: int in triangles.size(): points[scaled_corner] = scaled_panel[triangles[scaled_corner]]
								total_tree_scale_inputs += unique_panel.size()
								total_tree_scale_multiplications_saved += triangles.size() - unique_panel.size()
							else:
								for face_corner: int in triangles.size(): points[face_corner] = posed[triangles[face_corner]] * RAY_SPACE_SCALE
								total_tree_scale_inputs += triangles.size()
							tree = TriangleMesh.new()
							tree.create_from_faces(points)
							layer_build_usec = Time.get_ticks_usec() - build_began
							total_tree_build_usec += layer_build_usec
							total_tree_builds += 1
						frame_ray_queries += 1
						hit = tree.intersect_ray((point + Vector3(0, 0, sign_z)) * RAY_SPACE_SCALE, Vector3(0, 0, -sign_z))
						if hit.is_empty() or absf((hit.normal as Vector3).z) < .35: continue
						depth = sign_z * (point.z - (hit.position as Vector3).z / RAY_SPACE_SCALE)
						max_contact_depth = maxf(max_contact_depth, depth)
						if not diagnostic_safe_face_cache and depth < -margin + .00025: continue
					var offset: int = int(hit.face_index) * 3
					var a: int = triangles[offset]
					var b: int = triangles[offset + 1]
					var c: int = triangles[offset + 2]
					var cached_face: Variant = face_cache[int(hit.face_index)]
					if cached_face == null:
						if diagnostic_safe_face_cache:
							cached_face = contact_face_certificate(posed, triangles, int(hit.face_index))
						else:
							var cached_origin: Vector3 = posed[a]
							var cached_first := Vector2(posed[b].x - cached_origin.x, posed[b].y - cached_origin.y)
							var cached_second := Vector2(posed[c].x - cached_origin.x, posed[c].y - cached_origin.y)
							cached_face = [cached_origin, cached_first, cached_second, cached_first.cross(cached_second)]
						face_cache[int(hit.face_index)] = cached_face
						total_face_cache_builds += 1
					else: total_face_cache_hits += 1
					if diagnostic_safe_face_cache:
						if bool(cached_face[6]):
							var saved_faces := PackedInt32Array()
							if certificate_cells[certificate_cell] != null: saved_faces = certificate_cells[certificate_cell]
							var saved_index: int = saved_faces.find(int(hit.face_index))
							if saved_index >= 0: saved_faces.remove_at(saved_index)
							saved_faces.insert(0, int(hit.face_index))
							if saved_faces.size() > 2: saved_faces.resize(2)
							certificate_cells[certificate_cell] = saved_faces
						if depth < -margin + .00025: continue
					var origin: Vector3 = cached_face[0]
					var first: Vector2 = cached_face[1]
					var second: Vector2 = cached_face[2]
					var determinant: float = cached_face[3]
					var at := Vector2(point.x - origin.x, point.y - origin.y)
					if absf(determinant) < .00000001: continue
					var u: float = at.cross(second) / determinant
					var v: float = first.cross(at) / determinant
					slopes.fill(0)
					barycentric[0] = 1-u-v
					barycentric[1] = u
					barycentric[2] = v
					for corner: int in 3:
						var cloth: int = a if corner == 0 else b if corner == 1 else c
						var corner_ids: PackedInt32Array = patch_ids[cloth]
						var corner_coefficients: PackedFloat32Array = patch_coefficients[cloth]
						var corner_factor: float = barycentric[corner] * sign_z * directions[cloth].z
						for slot: int in corner_ids.size():
							var patch: int = corner_ids[slot]
							slopes[patch] += corner_factor * corner_coefficients[slot]
					var required: float = depth + margin
					var active_patches: PackedInt32Array = triangle_patches[int(hit.face_index)]
					for patch: int in active_patches: required -= slopes[patch] * (amounts[patch] - iteration_amounts[patch])
					if required <= .0001: continue
					var divisor := 0.0
					for patch: int in active_patches:
						if slopes[patch] > 0 and amounts[patch] < maximum_weight: divisor += slopes[patch] * slopes[patch]
					if divisor < .00000001:
						saturated_constraints += 1
						continue
					for patch: int in active_patches:
						if slopes[patch] <= 0: continue
						var new_amount: float = minf(maximum_weight, amounts[patch] + required * slopes[patch] / divisor)
						if new_amount > amounts[patch] + .000001: increased = true
						amounts[patch] = new_amount
				total_query_usec += Time.get_ticks_usec() - query_began - layer_build_usec
				if diagnostic_layer_geometry_cache:
					geometry_layers[layer] = {"signature": geometry_signature, "lower": lower, "upper": upper,
						"columns": columns, "rows": rows, "depth_bounds": depth_bounds, "tree": tree, "face_cache": face_cache}
				if diagnostic_fixed_layer_reuse:
					if patch_value_signature(amounts, layer_patch_ids[layer]) == entry_signature:
						fixed_layers[layer] = {"geometry": geometry_signature, "entry": entry_signature, "saturated": saturated_constraints - layer_saturated_before}
					else:
						fixed_layers.erase(layer)
			if not increased: break
		contact_elapsed = Time.get_ticks_usec() - contact_began
		for index: int in deforming_vertices:
			var distance := 0.0
			for slot: int in patch_ids[index].size(): distance += patch_coefficients[index][slot] * amounts[patch_ids[index][slot]]
			max_displacement = maxf(max_displacement, (directions[index] * distance).length())
	for patch: int in local_indices.size():
		mesh.set_blend_shape_value(local_indices[patch], amounts[patch])
		if amounts[patch] > .0001: active_targets += 1
	cached_amounts = amounts.duplicate()
	total_ray_queries += frame_ray_queries
	total_broadphase_skips += frame_broadphase_skips
	var solved_usec: int = Time.get_ticks_usec() - began
	solve_times.append(solved_usec)
	solve_total_usec += solved_usec
	skin_total_usec += skin_elapsed
	contact_total_usec += contact_elapsed
	skin_max_usec = maxi(skin_max_usec, skin_elapsed)
	contact_max_usec = maxi(contact_max_usec, contact_elapsed)
	if solve_times.size() > 240: solve_times.remove_at(0)
	record_elapsed(began)

# Shared production implementation: a single constraint body below both paths.
const NATIVE_CONTACT = preload("res://scripts/characters/garment_native_filter.gd")
var native_contact_ready := false
var native_contact_reason := "not prepared"
var native_contact_forced_off := false
var native_contact_body_ordinals := PackedInt32Array()
var native_contact_layers := 0
var native_contact_pack_usec := 0
var native_contact_eager_trees := 0
var native_contact_zero_query_trees := 0

func native_contact_prepare() -> void:
	native_contact_forced_off = OS.get_cmdline_user_args().has("--garment-native-filter=off")
	if native_contact_forced_off:
		native_contact_ready = false
		native_contact_reason = "explicit GD fallback"
		return
	var capability: Dictionary = NATIVE_CONTACT.prepare()
	native_contact_ready = bool(capability.ready)
	native_contact_reason = str(capability.reason)

func performance() -> Dictionary:
	var result: Dictionary = native_contact_original_performance()
	result["native_filter_ready"] = native_contact_ready
	result["native_filter_reason"] = native_contact_reason
	result["native_filter_layers"] = native_contact_layers
	result["native_filter_body_pack_usec_total"] = native_contact_pack_usec
	result["native_filter_body_pack_mean_usec"] = float(native_contact_pack_usec) / maxi(updates - cache_hits - steady_fast_updates, 1)
	result["native_filter_eager_tree_builds"] = native_contact_eager_trees
	result["native_filter_zero_query_eager_trees"] = native_contact_zero_query_trees
	result["native_geometry_enabled"] = native_geometry_enabled
	result["native_geometry_calls"] = native_geometry_calls
	result["native_geometry_fallbacks"] = native_geometry_fallbacks
	return result


# Optional native bounds/grid construction; old libraries retain full GD work.
var native_geometry_enabled := false
var native_geometry_calls := 0
var native_geometry_fallbacks := 0

func native_geometry_prepare() -> void:
	native_geometry_enabled = character == "kazuko"
	for native_geometry_argument: String in OS.get_cmdline_user_args():
		if native_geometry_argument == "--native-geometry=off": native_geometry_enabled = false

func native_geometry_valid(value: Dictionary) -> bool:
	if not bool(value.get("valid", false)): return false
	if not value.get("lower") is Vector3 or not value.get("upper") is Vector3: return false
	if typeof(value.get("columns")) != TYPE_INT or typeof(value.get("rows")) != TYPE_INT: return false
	if not value.get("depth_bounds") is PackedFloat32Array: return false
	var native_geometry_columns: int = int(value.columns)
	var native_geometry_rows: int = int(value.rows)
	var native_geometry_lower: Vector3 = value.lower
	var native_geometry_upper: Vector3 = value.upper
	return native_geometry_lower.is_finite() and native_geometry_upper.is_finite() and native_geometry_columns > 0 and native_geometry_rows > 0 and float(native_geometry_columns) <= 2147483647.0 / float(native_geometry_rows) and (value.depth_bounds as PackedFloat32Array).size() == native_geometry_columns * native_geometry_rows
