extends SkeletonModifier3D
## Test-only, complete source cloth and independent body triangle witnesses.
## Independent pigment faces are retained unchanged. Every original source face
## affected by Local POSITION targets is a supplementary cloth domain. The main
## gate uses the true exterior of their union, never a simplified LOD surface.
## TriangleMesh snaps vertices at .0001 and applies an absolute determinant
## epsilon. Internal ray coordinates use centimetres to retain small folds.
## Returned positions are restored to metres before existing normal/depth gates.
const RAY_COORDINATE_SCALE := 100.0
const BODY_CLASSIFIER = preload("res://scripts/characters/garment_body_classifier.gd")
var pending := false
var request_id := 0
var completed_request := -1
var request_frame := -1
var expected_clip := ""
var expected_time := -1.0
var result: Dictionary = {}
var mesh: MeshInstance3D
var animation: AnimationPlayer
var character := ""
var records: Dictionary = {}
var body := PackedInt32Array()
var cloth := PackedInt32Array()
var faces: Dictionary = {"front": [], "back": []}
var pigment_faces: Dictionary = {"front": [], "back": []}
var pigment_source_face_indices: Dictionary = {"front": [], "back": []}
var support_faces: Dictionary = {"front": [], "back": []}
var support_source_face_indices: Dictionary = {"front": [], "back": []}
var cloth_domain_preparation: Dictionary = {}
var body_local_support: Dictionary = {"front": PackedFloat32Array(), "back": PackedFloat32Array()}
var body_classification_preparation: Dictionary = {}
var local_shapes := PackedInt32Array()
var cloth_snapshot := PackedVector3Array()
var body_template_delta_max := 0.0
var seam_template_gap_max := 0.0
var model_source: Node3D
var source_face_indices: Dictionary = {"front": [], "back": []}
# Original body vertices remain. Every fully labelled source body triangle also
# contributes its3 corners,3 edge midpoints and centroid. Ren additionally keeps
# UV-classified samples on mixed-label source faces. The same5mm/.35 gates apply.
var measure_surface_witnesses := true
var surface_witnesses: Array[Dictionary] = []
var surface_witness_preparation: Dictionary = {}

func seam_key(index: int, points: PackedVector3Array, binds: PackedInt32Array, weights: PackedFloat32Array, influences: int) -> PackedByteArray:
	var key: PackedByteArray = PackedVector3Array([points[index]]).to_byte_array()
	key.append_array(binds.slice(index * influences, (index + 1) * influences).to_byte_array())
	key.append_array(weights.slice(index * influences, (index + 1) * influences).to_byte_array())
	return key

func complete_pigment_mask(points: PackedVector3Array, colours: Array[Color], binds: PackedInt32Array, weights: PackedFloat32Array, influences: int, height: float) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(points.size())
	if character not in ["mio", "kazuko"]: return mask
	var buckets: Dictionary = {}
	var queue := PackedInt32Array()
	for paint_index: int in points.size():
		var p: Vector3 = points[paint_index]
		var cell := Vector3i(floori(p.x * 1000000.0), floori(p.y * 1000000.0), floori(p.z * 1000000.0))
		if not buckets.has(cell): buckets[cell] = PackedInt32Array()
		var cell_vertices: PackedInt32Array = buckets[cell]
		cell_vertices.append(paint_index)
		buckets[cell] = cell_vertices
		var colour: Color = colours[paint_index]
		var painted: bool = colour.b > colour.r * 1.08 and colour.b > colour.g * 1.04 and colour.r + colour.g + colour.b < 1.0 if character == "mio" else colour.r > colour.g * .95 and colour.r < colour.g * 1.9 and colour.b < colour.g * .65 and colour.g > .18
		if painted:
			mask[paint_index] = 1
			queue.append(paint_index)
	var cursor := 0
	while cursor < queue.size():
		var original: int = queue[cursor]
		cursor += 1
		for copy: int in BODY_CLASSIFIER.physical_uv_copies(original, points, binds, weights, influences, buckets):
			if mask[copy] != 0: continue
			mask[copy] = 1
			queue.append(copy)
	for bounded_index: int in points.size():
		var point: Vector3 = points[bounded_index]
		if absf(point.x) >= .24 * height or point.y <= .20 * height or point.y >= .59 * height: mask[bounded_index] = 0
	return mask

func request(clip: String = "", time: float = -1.0) -> int:
	request_id += 1
	request_frame = Engine.get_process_frames()
	expected_clip = clip
	expected_time = time
	pending = true
	return request_id

func prepare(model: Node3D) -> void:
	model_source = model
	var rig: Node = model.find_child("Rig", true, false)
	if rig == null or not rig.has_meta("extras"): return
	character = str((rig.get_meta("extras") as Dictionary).get("character_id", ""))
	animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for candidate: MeshInstance3D in WorldBuilder.find_meshes(model):
		if candidate.skin == null or not candidate.mesh is ArrayMesh or str(candidate.name).begins_with("Sleeve") or str(candidate.name).begins_with("HiddenArm"): continue
		if mesh == null or candidate.mesh.surface_get_array_len(0) > mesh.mesh.surface_get_array_len(0): mesh = candidate
	if mesh == null: return
	var sk: Skeleton3D = get_skeleton()
	var geometry: ArrayMesh = mesh.mesh as ArrayMesh
	var arrays: Array = geometry.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var shapes: Array = geometry.surface_get_blend_shape_arrays(0)
	var relative: bool = geometry.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	var support_amplitudes: Dictionary = {"front": PackedFloat32Array(), "back": PackedFloat32Array()}
	for support_layer: String in ["front", "back"]:
		var initialized_amplitudes := PackedFloat32Array()
		initialized_amplitudes.resize(points.size())
		support_amplitudes[support_layer] = initialized_amplitudes
		body_local_support[support_layer] = initialized_amplitudes.duplicate()
	for shape_index: int in geometry.get_blend_shape_count():
		var shape_name: String = str(geometry.get_blend_shape_name(shape_index))
		if not shape_name.begins_with("Garment_Local_"): continue
		local_shapes.append(shape_index)
		var side: String = "front" if shape_name.contains("_Front_") else "back"
		var local_points: PackedVector3Array = shapes[shape_index][Mesh.ARRAY_VERTEX]
		var shape_amplitudes: PackedFloat32Array = support_amplitudes[side]
		var shape_z_amplitudes: PackedFloat32Array = body_local_support[side]
		for support_vertex: int in points.size():
			var support_delta: Vector3 = local_points[support_vertex] if relative else local_points[support_vertex] - points[support_vertex]
			shape_amplitudes[support_vertex] += support_delta.length()
			shape_z_amplitudes[support_vertex] += absf(support_delta.z)
		support_amplitudes[side] = shape_amplitudes
		body_local_support[side] = shape_z_amplitudes
	var material: BaseMaterial3D = mesh.get_active_material(0) as BaseMaterial3D
	if material == null or material.albedo_texture == null: return
	var atlas: Image = material.albedo_texture.get_image()
	if atlas.is_compressed(): atlas.decompress()
	var colours: Array[Color] = []
	var height := 0.0
	for point: Vector3 in points: height = maxf(height, point.y)
	for texture_uv: Vector2 in uv: colours.append(atlas.get_pixel(posmod(int(texture_uv.x * atlas.get_width()), atlas.get_width()), posmod(int(texture_uv.y * atlas.get_height()), atlas.get_height())))
	var skin_samples := PackedVector3Array()
	for index: int in points.size():
		var colour: Color = colours[index]
		if points[index].y > .20 * height and points[index].y < .36 * height and colour.r > colour.g * 1.10 and colour.g > colour.b * 1.02 and colour.r > .30: skin_samples.append(Vector3(colour.r, colour.g, colour.b))
	var skin_rgb := Vector3(.92, .73, .63)
	if not skin_samples.is_empty():
		skin_rgb = Vector3.ZERO
		for value: Vector3 in skin_samples: skin_rgb += value
		skin_rgb /= skin_samples.size()
	var flags: Dictionary = {"front": PackedByteArray(), "back": PackedByteArray()}
	for layer: String in ["front", "back"]:
		var mask: PackedByteArray = flags[layer]
		mask.resize(points.size())
		flags[layer] = mask
	var influences: int = binds.size() / points.size()
	var hip_z: float = sk.get_bone_global_rest(LivingPose.bone(sk, "hips")).origin.z
	var yellow_seams: Dictionary = {}
	var non_black_seams: Dictionary = {}
	if character == "kazuko":
		for seam_index: int in points.size():
			var pigment: Color = colours[seam_index]
			if pigment.r > pigment.g * .95 and pigment.r < pigment.g * 1.9 and pigment.b < pigment.g * .65 and pigment.g > .18: yellow_seams[seam_key(seam_index, points, binds, weights, influences)] = true
			if maxf(pigment.r, maxf(pigment.g, pigment.b)) >= .36 or maxf(pigment.r, maxf(pigment.g, pigment.b)) - minf(pigment.r, minf(pigment.g, pigment.b)) >= .08: non_black_seams[seam_key(seam_index, points, binds, weights, influences)] = true
	for index: int in points.size():
		var point: Vector3 = points[index]
		if absf(point.x) > .24 * height or point.y < .20 * height or point.y > .59 * height: continue
		var colour: Color = colours[index]
		var garment: bool = colour.b > colour.r * 1.08 and colour.b > colour.g * 1.04 and colour.r + colour.g + colour.b < 1.0 if character == "mio" else colour.r > colour.g * .95 and colour.r < colour.g * 1.9 and colour.b < colour.g * .65 and colour.g > .18 if character == "kazuko" else minf(colour.r, minf(colour.g, colour.b)) > .50 and maxf(colour.r, maxf(colour.g, colour.b)) - minf(colour.r, minf(colour.g, colour.b)) < .10
		if character == "kazuko" and yellow_seams.has(seam_key(index, points, binds, weights, influences)): garment = true
		if character == "ren" and colour.r > colour.g * 1.04 and colour.g > colour.b * 1.08: garment = false
		if garment:
			for layer: String in ["front", "back"]:
				var sign_z: float = 1.0 if layer == "front" else -1.0
				if (point.z - hip_z) * sign_z <= .025: continue
				var mask: PackedByteArray = flags[layer]
				mask[index] = 1
				flags[layer] = mask
		if absf(point.x) > .16 * height or point.y > .55 * height: continue
		var is_body: bool = maxf(colour.r, maxf(colour.g, colour.b)) < .36
		if character == "ren": is_body = colour.r > colour.g * 1.04 and colour.g > colour.b * 1.08
		if character == "kazuko": is_body = is_body and maxf(colour.r, maxf(colour.g, colour.b)) - minf(colour.r, minf(colour.g, colour.b)) < .08
		if character == "mio":
			var leg_share := 0.0
			for slot: int in influences:
				var bind: int = binds[index * influences + slot]
				var bone: int = mesh.skin.get_bind_bone(bind)
				var name: String = sk.get_bone_name(bone) if bone >= 0 else String(mesh.skin.get_bind_name(bind))
				if "UpLeg" in name or name.ends_with("Leg") or "Foot" in name or "Toe" in name: leg_share += weights[index * influences + slot]
			is_body = colour.r > colour.g * 1.10 and colour.g > colour.b * 1.02 and colour.r > .30 and leg_share > .65 and Vector3(colour.r, colour.g, colour.b).distance_to(skin_rgb) < .12
		if is_body and not non_black_seams.has(seam_key(index, points, binds, weights, influences)): body.append(index)
	if character == "ren":
		body_classification_preparation = BODY_CLASSIFIER.classify(body, body_local_support, points, indices, uv, binds, weights, influences, colours, flags)
		body = body_classification_preparation.retained_indices
		body_classification_preparation.erase("retained_indices")
	var needed: Dictionary = {}
	var garment_vertices: Dictionary = {}
	var complete_paint: PackedByteArray = complete_pigment_mask(points, colours, binds, weights, influences, height)
	var original_pigment_counts: Dictionary = {"front": 0, "back": 0}
	var complete_paint_additions: Dictionary = {"front": 0, "back": 0}
	if measure_surface_witnesses and character in ["mio", "kazuko", "ren"]:
		prepare_surface_witnesses(points, indices, uv, atlas, height, needed)
	for offset: int in range(0, indices.size(), 3):
		var triangle := PackedInt32Array([indices[offset], indices[offset + 1], indices[offset + 2]])
		var has_original_side := false
		for original_side: String in ["front", "back"]:
			var original_mask: PackedByteArray = flags[original_side]
			var original_support: PackedFloat32Array = support_amplitudes[original_side]
			if (original_mask[triangle[0]] and original_mask[triangle[1]] and original_mask[triangle[2]]) or (original_support[triangle[0]] >= .000001 and original_support[triangle[1]] >= .000001 and original_support[triangle[2]] >= .000001): has_original_side = true
		var extra_paint_side := ""
		if not has_original_side and complete_paint[triangle[0]] and complete_paint[triangle[1]] and complete_paint[triangle[2]]:
			var centre_z: float = (points[triangle[0]].z + points[triangle[1]].z + points[triangle[2]].z) / 3.0
			extra_paint_side = "front" if centre_z > hip_z else "back"
			complete_paint_additions[extra_paint_side] += 1
		for layer: String in ["front", "back"]:
			var mask: PackedByteArray = flags[layer]
			var pigment_eligible: bool = mask[triangle[0]] != 0 and mask[triangle[1]] != 0 and mask[triangle[2]] != 0
			if pigment_eligible: original_pigment_counts[layer] += 1
			pigment_eligible = pigment_eligible or layer == extra_paint_side
			var face_amplitudes: PackedFloat32Array = support_amplitudes[layer]
			var support_eligible: bool = face_amplitudes[triangle[0]] >= .000001 and face_amplitudes[triangle[1]] >= .000001 and face_amplitudes[triangle[2]] >= .000001
			if pigment_eligible:
				(pigment_faces[layer] as Array).append(triangle)
				(pigment_source_face_indices[layer] as Array).append(offset / 3)
			if support_eligible:
				(support_faces[layer] as Array).append(triangle)
				(support_source_face_indices[layer] as Array).append(offset / 3)
			if not pigment_eligible and not support_eligible: continue
			(faces[layer] as Array).append(triangle)
			(source_face_indices[layer] as Array).append(offset / 3)
			for vertex: int in triangle:
				needed[vertex] = true
				garment_vertices[vertex] = true
	for domain_layer: String in ["front", "back"]:
		cloth_domain_preparation[domain_layer] = {"independent_pigment_source_triangles": (pigment_faces[domain_layer] as Array).size(), "all_local_support_source_triangles": (support_faces[domain_layer] as Array).size(), "supplementary_source_triangles_not_in_pigment": (faces[domain_layer] as Array).size() - (pigment_faces[domain_layer] as Array).size(), "union_source_triangles": (faces[domain_layer] as Array).size()}
		cloth_domain_preparation[domain_layer]["original_sided_pigment_source_triangles"] = original_pigment_counts[domain_layer]
		cloth_domain_preparation[domain_layer]["additional_complete_pigment_source_triangles"] = complete_paint_additions[domain_layer]
	cloth_domain_preparation["complete_pigment_policy"] = "Mio/Kazuko complete painted source faces in the original height/width region, including the old hip-depth gap. Paint labels close over rest<=1micrometre/same binds/weights<1e-7 physical UV copies. Existing sided pigment and Local-support faces retain their side; new complete painted faces use rest centroid relative to hips. Original body anchors/faces and gates are unchanged."
	cloth_domain_preparation["support_policy"] = "Every original LOD0 source face whose three corners each sum to at least1micrometre of actual Local POSITION delta magnitude on this side; per-side sum is basis-count independent. Independent pigment faces are never removed, even outside Local support."
	for vertex: int in body: needed[vertex] = true
	for vertex: int in garment_vertices: cloth.append(vertex)
	var physical_seams: Dictionary = {}
	for seam_vertex: int in points.size():
		var physical_key: PackedByteArray = seam_key(seam_vertex, points, binds, weights, influences)
		if physical_seams.has(physical_key):
			var other_vertex: int = physical_seams[physical_key]
			for local_shape: int in local_shapes:
				var seam_points: PackedVector3Array = shapes[local_shape][Mesh.ARRAY_VERTEX]
				seam_template_gap_max = maxf(seam_template_gap_max, seam_points[seam_vertex].distance_to(seam_points[other_vertex]))
		else: physical_seams[physical_key] = seam_vertex
	for shape: int in local_shapes:
		var vertices: PackedVector3Array = shapes[shape][Mesh.ARRAY_VERTEX]
		for vertex: int in body:
			var delta: Vector3 = vertices[vertex] if relative else vertices[vertex] - points[vertex]
			body_template_delta_max = maxf(body_template_delta_max, delta.length())
	for vertex: int in needed:
		var chain: Array[Dictionary] = []
		for slot: int in influences:
			var weight: float = weights[vertex * influences + slot]
			if weight <= 0: continue
			var bind: int = binds[vertex * influences + slot]
			var bone: int = mesh.skin.get_bind_bone(bind)
			if bone < 0: bone = sk.find_bone(mesh.skin.get_bind_name(bind))
			chain.append({"bone": bone, "inverse_bind": mesh.skin.get_bind_pose(bind), "weight": weight})
		var deltas: Array[Vector3] = []
		for shape: Array in shapes:
			var values: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
			deltas.append(values[vertex] if relative else values[vertex] - points[vertex])
		records[vertex] = {"point": points[vertex], "uv": uv[vertex], "colour": colours[vertex], "chain": chain, "deltas": deltas}
	result = {"prepared": true, "body_vertices": body.size(), "cloth_vertices": cloth.size()}

func prepare_surface_witnesses(points: PackedVector3Array, indices: PackedInt32Array, uv: PackedVector2Array, atlas: Image, height: float, needed: Dictionary) -> void:
	var body_labels: Dictionary = {}
	for vertex: int in body: body_labels[vertex] = true
	var mixed_faces := 0
	var fully_labelled_faces := 0
	var selected_faces: Dictionary = {}
	var selected_mixed_faces: Dictionary = {}
	var selected_corner_labels: Dictionary = {}
	var excluded_mixed_clothing := 0
	var excluded_mixed_faces: Dictionary = {}
	var maximum_excluded_local_support := 0.0
	var full_barycentrics: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(.5, .5, 0), Vector3(.5, 0, .5), Vector3(0, .5, .5), Vector3.ONE / 3.0]
	var mixed_barycentrics: Array[Vector3] = [Vector3(.5, .5, 0), Vector3(.5, 0, .5), Vector3(0, .5, .5), Vector3.ONE / 3.0]
	for offset: int in range(0, indices.size(), 3):
		var triangle := PackedInt32Array([indices[offset], indices[offset + 1], indices[offset + 2]])
		var labels := 0
		for vertex: int in triangle:
			if body_labels.has(vertex): labels += 1
		if labels == 3: fully_labelled_faces += 1
		elif labels > 0: mixed_faces += 1
		if labels != 3 and character != "ren": continue
		var barycentrics: Array[Vector3] = full_barycentrics if labels == 3 else mixed_barycentrics
		for witness_index: int in barycentrics.size():
			var barycentric: Vector3 = barycentrics[witness_index]
			var rest: Vector3 = points[triangle[0]] * barycentric.x + points[triangle[1]] * barycentric.y + points[triangle[2]] * barycentric.z
			if absf(rest.x) > .16 * height or rest.y < .20 * height or rest.y > .55 * height: continue
			var texture_uv: Vector2 = uv[triangle[0]] * barycentric.x + uv[triangle[1]] * barycentric.y + uv[triangle[2]] * barycentric.z
			var colour: Color = atlas.get_pixel(posmod(int(texture_uv.x * atlas.get_width()), atlas.get_width()), posmod(int(texture_uv.y * atlas.get_height()), atlas.get_height()))
			# Fully labelled physical body faces retain every geometric witness.
			# Mixed Ren faces additionally use the existing warm-khaki rule at the
			# interpolated UV, preserving hips-weighted and pigment-border trousers.
			if labels != 3 and not (colour.r > colour.g * 1.04 and colour.g > colour.b * 1.08): continue
			if labels != 3:
				var local_clothing_support := 0.0
				for layer: String in ["front", "back"]:
					var side_support: PackedFloat32Array = body_local_support[layer]
					var interpolated: float = side_support[triangle[0]] * barycentric.x + side_support[triangle[1]] * barycentric.y + side_support[triangle[2]] * barycentric.z
					local_clothing_support = maxf(local_clothing_support, interpolated)
				if local_clothing_support > .000001:
					excluded_mixed_clothing += 1
					excluded_mixed_faces[offset / 3] = true
					maximum_excluded_local_support = maxf(maximum_excluded_local_support, local_clothing_support)
					continue
			var source_face: int = offset / 3
			var kind: String = "centroid"
			if labels == 3 and witness_index < 3: kind = "corner_%d" % witness_index
			elif witness_index < barycentrics.size() - 1: kind = "edge_midpoint_%d" % (witness_index - 3 if labels == 3 else witness_index)
			surface_witnesses.append({"triangle": triangle, "source_surface_triangle_index": source_face, "barycentric": barycentric, "kind": kind, "labelled_corners": labels, "rest_position": rest, "uv": texture_uv, "colour": colour})
			selected_faces[source_face] = true
			selected_corner_labels[source_face] = labels
			if labels > 0 and labels < 3: selected_mixed_faces[source_face] = true
			for corner: int in triangle: needed[corner] = true
	var selected_label_histogram: Dictionary = {"0": 0, "1": 0, "2": 0, "3": 0}
	for selected_face_index: int in selected_corner_labels:
		var label_count: String = str(selected_corner_labels[selected_face_index])
		selected_label_histogram[label_count] += 1
	surface_witness_preparation = {"supported_character": character, "source_triangles_total": indices.size() / 3, "fully_labelled_body_source_triangles": fully_labelled_faces, "mixed_corner_source_triangles": mixed_faces, "selected_source_triangles": selected_faces.size(), "selected_mixed_corner_source_triangles": selected_mixed_faces.size(), "selected_source_triangles_by_labelled_corner_count": selected_label_histogram, "witness_count": surface_witnesses.size(), "excluded_additional_mixed_uv_witnesses_on_clothing": excluded_mixed_clothing, "excluded_mixed_uv_clothing_source_triangles": excluded_mixed_faces.size(), "maximum_excluded_mixed_uv_local_z_support_m": maximum_excluded_local_support, "mixed_uv_clothing_policy": "Only additional mixed-label UV samples are excluded when any side's Local z-envelope interpolated from the final source triangle corners exceeds1micrometre; every pure body face retains all7 geometric samples regardless of this label", "sampling": "all3 corners,3 edge midpoints and centroid on every fully labelled source body triangle; Ren mixed-label faces additionally use4 midpoint/centroid witnesses selected by original rest ROI and barycentric UV warm-khaki rule; all original body vertices remain separate"}

func pose_context() -> Dictionary:
	var actor: Node = model_source
	while actor.get_parent() != null and not actor is NPC and not actor is Player: actor = actor.get_parent()
	var context: Dictionary = {"actor_is_npc": actor is NPC, "actor_is_player": actor is Player, "resident_seated": bool(actor.get_meta("resident_seated", false)), "char_anim_state": "", "char_anim_oneshot": "", "natural_transition_elapsed": -1.0, "natural_transition_duration": -1.0, "active_modifiers": []}
	if actor is NPC:
		var npc: NPC = actor as NPC
		context["char_anim_state"] = npc.anim._state
		context["char_anim_oneshot"] = npc.anim._oneshot
		context["npc_id"] = npc.npc_id
	var sk: Skeleton3D = get_skeleton()
	for child: Node in sk.get_children():
		if not child is SkeletonModifier3D: continue
		var modifier: SkeletonModifier3D = child as SkeletonModifier3D
		var script: Script = modifier.get_script() as Script
		var path: String = script.resource_path if script != null else ""
		if path == "res://scripts/characters/natural_locomotion_pose.gd":
			context["natural_transition_elapsed"] = float(modifier.get("_transition_elapsed"))
			context["natural_transition_duration"] = float(modifier.get("_transition_duration"))
		if modifier.is_active(): (context.active_modifiers as Array).append({"name": str(modifier.name), "script": path, "class": modifier.get_class(), "influence": modifier.get_influence()})
	return context

func measure_surface(posed: Dictionary, panel_trees: Dictionary, domain_faces: Dictionary = {}, domain_sources: Dictionary = {}) -> Dictionary:
	var report: Dictionary = {"enabled": measure_surface_witnesses, "supported": character in ["mio", "kazuko", "ren"], "preparation": surface_witness_preparation, "layers": {}, "max_penetration_m": 0.0}
	if not measure_surface_witnesses or character not in ["mio", "kazuko", "ren"]: return report
	for layer: String in ["front", "back"]:
		if not domain_faces.is_empty() and (domain_faces[layer] as Array).is_empty():
			(report.layers as Dictionary)[layer] = {"witness_queries": surface_witnesses.size(), "covered_witnesses": 0, "no_hit": surface_witnesses.size(), "normal_rejected": 0, "witnesses_over_original_5mm_gate": 0, "max_penetration_m": 0.0, "worst_hit": {}}
			continue
		var sign_z: float = 1.0 if layer == "front" else -1.0
		var tree: TriangleMesh = panel_trees[layer]
		var maximum := 0.0
		var covered := 0
		var missed := 0
		var normal_rejected := 0
		var above_gate := 0
		var worst: Dictionary = {}
		for witness: Dictionary in surface_witnesses:
			var triangle: PackedInt32Array = witness.triangle
			var barycentric: Vector3 = witness.barycentric
			# Interpolate the actual deformed triangle, not skinned midpoint
			# weights: mixed skin weights make those different surfaces.
			var point: Vector3 = (posed[triangle[0]] as Vector3) * barycentric.x + (posed[triangle[1]] as Vector3) * barycentric.y + (posed[triangle[2]] as Vector3) * barycentric.z
			var hit: Dictionary = ray_hit(tree, point, sign_z, RAY_COORDINATE_SCALE)
			if hit.is_empty():
				missed += 1
				continue
			if absf((hit.normal as Vector3).z) < .35:
				normal_rejected += 1
				continue
			covered += 1
			var depth: float = sign_z * (point.z - (hit.position as Vector3).z)
			if depth > .005: above_gate += 1
			if depth > maximum:
				maximum = depth
				worst = hit_record(layer, triangle[0], posed, hit, depth, domain_faces, domain_sources)
				worst.erase("body")
				var corners: Array[Dictionary] = []
				for corner: int in triangle: corners.append(vertex_record(corner, posed))
				var texture_uv: Vector2 = witness.uv
				var colour: Color = witness.colour
				worst["body_surface_witness"] = {"source_surface_triangle_index": witness.source_surface_triangle_index, "source_triangle_vertices": corners, "barycentric": vector(barycentric), "kind": witness.kind, "labelled_corners": witness.labelled_corners, "rest_position": vector(witness.rest_position as Vector3), "uv": [texture_uv.x, texture_uv.y], "source_colour_rgb": [colour.r, colour.g, colour.b], "posed_skeleton_position": vector(point)}
		(report.layers as Dictionary)[layer] = {"witness_queries": surface_witnesses.size(), "covered_witnesses": covered, "no_hit": missed, "normal_rejected": normal_rejected, "witnesses_over_original_5mm_gate": above_gate, "max_penetration_m": maximum, "worst_hit": worst}
		report["max_penetration_m"] = maxf(float(report.max_penetration_m), maximum)
	return report

func measure_cloth_domain(posed: Dictionary, domain_faces: Dictionary, domain_sources: Dictionary) -> Dictionary:
	var trees: Dictionary = {}
	var vertex_layers: Dictionary = {}
	var maximum := 0.0
	for layer: String in ["front", "back"]:
		var source_points := PackedVector3Array()
		for triangle: PackedInt32Array in domain_faces[layer]:
			for corner: int in triangle: source_points.append((posed[corner] as Vector3) * RAY_COORDINATE_SCALE)
		var tree := TriangleMesh.new()
		if not source_points.is_empty(): tree.create_from_faces(source_points)
		trees[layer] = tree
		if source_points.is_empty():
			vertex_layers[layer] = {"source_triangles": 0, "covered_body_vertices": 0, "vertices_over_original_5mm_gate": 0, "max_penetration_m": 0.0, "worst_hit": {}}
			continue
		var sign_z: float = 1.0 if layer == "front" else -1.0
		var layer_maximum := 0.0
		var covered := 0
		var above_gate := 0
		var worst: Dictionary = {}
		for vertex: int in body:
			var point: Vector3 = posed[vertex]
			var hit: Dictionary = ray_hit(tree, point, sign_z, RAY_COORDINATE_SCALE)
			if hit.is_empty() or absf((hit.normal as Vector3).z) < .35: continue
			covered += 1
			var depth: float = sign_z * (point.z - (hit.position as Vector3).z)
			if depth > .005: above_gate += 1
			if depth > layer_maximum:
				layer_maximum = depth
				worst = hit_record(layer, vertex, posed, hit, depth, domain_faces, domain_sources)
		maximum = maxf(maximum, layer_maximum)
		vertex_layers[layer] = {"source_triangles": (domain_faces[layer] as Array).size(), "covered_body_vertices": covered, "vertices_over_original_5mm_gate": above_gate, "max_penetration_m": layer_maximum, "worst_hit": worst}
	var surface: Dictionary = measure_surface(posed, trees, domain_faces, domain_sources)
	return {"vertex_max_penetration_m": maximum, "surface_max_penetration_m": float(surface.max_penetration_m), "max_penetration_m": maxf(maximum, float(surface.max_penetration_m)), "vertex_layers": vertex_layers, "surface_witnesses": surface}

func vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func transform_record(value: Transform3D) -> Dictionary:
	return {"position": vector(value.origin), "basis": [vector(value.basis.x), vector(value.basis.y), vector(value.basis.z)]}

func vertex_record(index: int, posed: Dictionary) -> Dictionary:
	var record: Dictionary = records[index]
	var uv: Vector2 = record.uv
	var colour: Color = record.colour
	return {"imported_surface_vertex_index": index, "rest_position": vector(record.point as Vector3), "uv": [uv.x, uv.y], "source_colour_rgb": [colour.r, colour.g, colour.b], "posed_skeleton_position": vector(posed[index] as Vector3)}

func ray_hit(tree: TriangleMesh, point: Vector3, sign_z: float, coordinate_scale: float) -> Dictionary:
	var hit: Dictionary = tree.intersect_ray((point + Vector3(0, 0, sign_z)) * coordinate_scale, Vector3(0, 0, -sign_z))
	if not hit.is_empty(): hit["position"] = (hit.position as Vector3) / coordinate_scale
	return hit

func hit_record(layer: String, index: int, posed: Dictionary, hit: Dictionary, depth: float, domain_faces: Dictionary = {}, domain_sources: Dictionary = {}) -> Dictionary:
	var filtered_face: int = int(hit.get("face_index", -1))
	var description: Dictionary = {"depth_m": depth, "body": vertex_record(index, posed), "hit_skeleton_position": vector(hit.position as Vector3), "hit_skeleton_normal": vector(hit.normal as Vector3), "normal_abs_z": absf((hit.normal as Vector3).z), "normal_gate_accepted": absf((hit.normal as Vector3).z) >= .35, "filtered_panel_face_index": filtered_face, "source_surface_triangle_index": -1}
	var lookup_faces: Dictionary = faces if domain_faces.is_empty() else domain_faces
	var lookup_sources: Dictionary = source_face_indices if domain_sources.is_empty() else domain_sources
	if filtered_face >= 0 and filtered_face < (lookup_faces[layer] as Array).size():
		description["source_surface_triangle_index"] = int((lookup_sources[layer] as Array)[filtered_face])
		var original_triangle: PackedInt32Array = (lookup_faces[layer] as Array)[filtered_face]
		var triangle_records: Array[Dictionary] = []
		for corner_vertex: int in original_triangle: triangle_records.append(vertex_record(corner_vertex, posed))
		description["source_triangle_vertices"] = triangle_records
	return description

func _process_modification() -> void:
	if not pending or mesh == null: return
	var applied_frame: int = Engine.get_process_frames()
	if applied_frame <= request_frame: return
	if expected_clip != "" and animation.current_animation != expected_clip: return
	if expected_time >= 0 and absf(animation.current_animation_position - expected_time) >= .0001: return
	pending = false
	var sk: Skeleton3D = get_skeleton()
	var geometry: ArrayMesh = mesh.mesh as ArrayMesh
	var values := PackedFloat32Array()
	for shape: int in geometry.get_blend_shape_count(): values.append(mesh.get_blend_shape_value(shape))
	var matrices: Dictionary = {}
	var posed: Dictionary = {}
	var base: Dictionary = {}
	for vertex: int in records:
		var record: Dictionary = records[vertex]
		var point: Vector3 = record.point
		var without_local: Vector3 = point
		for shape: int in values.size():
			point += record.deltas[shape] * values[shape]
			if not local_shapes.has(shape): without_local += record.deltas[shape] * values[shape]
		var actual := Vector3.ZERO
		var original := Vector3.ZERO
		for influence: Dictionary in record.chain:
			var bone: int = influence.bone
			if not matrices.has(bone): matrices[bone] = sk.get_bone_global_pose(bone)
			var transform: Transform3D = matrices[bone] * influence.inverse_bind
			actual += (transform * point) * influence.weight
			original += (transform * without_local) * influence.weight
		posed[vertex] = actual
		base[vertex] = original
	var deepest := 0.0
	var legacy_deepest := 0.0
	var covered := 0
	var layers: Dictionary = {}
	var area := 0.0
	var moved_area := 0.0
	var panel_trees: Dictionary = {}
	for layer: String in ["front", "back"]:
		var triangle_points := PackedVector3Array()
		var legacy_triangle_points := PackedVector3Array()
		for triangle: PackedInt32Array in faces[layer]:
			var a: Vector3 = base[triangle[0]]
			var b: Vector3 = base[triangle[1]]
			var c: Vector3 = base[triangle[2]]
			var triangle_area: float = (b - a).cross(c - a).length() * .5
			area += triangle_area
			var moving := false
			for vertex: int in triangle:
				triangle_points.append((posed[vertex] as Vector3) * RAY_COORDINATE_SCALE)
				legacy_triangle_points.append(posed[vertex])
				moving = moving or (posed[vertex] as Vector3).distance_to(base[vertex]) > .001
			if moving: moved_area += triangle_area
		var tree := TriangleMesh.new()
		tree.create_from_faces(triangle_points)
		var legacy_tree := TriangleMesh.new()
		legacy_tree.create_from_faces(legacy_triangle_points)
		panel_trees[layer] = tree
		var sign_z: float = 1.0 if layer == "front" else -1.0
		var maximum := 0.0
		var hits := 0
		var worst: Dictionary = {}
		var legacy_maximum := 0.0
		var legacy_hits := 0
		var legacy_worst: Dictionary = {}
		for vertex: int in body:
			var point: Vector3 = posed[vertex]
			var legacy_hit: Dictionary = ray_hit(legacy_tree, point, sign_z, 1.0)
			if not legacy_hit.is_empty() and absf((legacy_hit.normal as Vector3).z) >= .35:
				var legacy_depth: float = sign_z * (point.z - (legacy_hit.position as Vector3).z)
				if legacy_depth > legacy_maximum:
					legacy_maximum = legacy_depth
					legacy_worst = hit_record(layer, vertex, posed, legacy_hit, legacy_depth)
				legacy_hits += 1
			var hit: Dictionary = ray_hit(tree, point, sign_z, RAY_COORDINATE_SCALE)
			if hit.is_empty() or absf((hit.normal as Vector3).z) < .35: continue
			var depth: float = sign_z * (point.z - (hit.position as Vector3).z)
			if depth > maximum:
				maximum = depth
				worst = hit_record(layer, vertex, posed, hit, depth)
			hits += 1
		var legacy_worst_precision_replay: Dictionary = {}
		if not legacy_worst.is_empty():
			var legacy_index: int = int((legacy_worst.body as Dictionary).imported_surface_vertex_index)
			var legacy_point: Vector3 = posed[legacy_index]
			var precision_hit: Dictionary = ray_hit(tree, legacy_point, sign_z, RAY_COORDINATE_SCALE)
			if not precision_hit.is_empty(): legacy_worst_precision_replay = hit_record(layer, legacy_index, posed, precision_hit, sign_z * (legacy_point.z - (precision_hit.position as Vector3).z))
		deepest = maxf(deepest, maximum)
		legacy_deepest = maxf(legacy_deepest, legacy_maximum)
		covered += hits
		layers[layer] = {"full_source_triangles": (faces[layer] as Array).size(), "covered_body_vertices": hits, "max_penetration_m": maximum, "worst_hit": worst, "legacy_unscaled": {"covered_body_vertices": legacy_hits, "max_penetration_m": legacy_maximum, "worst_hit": legacy_worst}, "precision_nearest_hit_at_legacy_worst": legacy_worst_precision_replay}
	# A second classified layer can occlude an inner fold after deformation.
	# These four diagnostic rays change neither the acceptance measure nor its
	# source labels. Union hits distinguish a layer-envelope artefact from a
	# body point outside both classified source panels; other omitted geometry
	# still requires an independent all-source replay.
	for diagnostic_layer: String in ["front", "back"]:
		var diagnostic_worst: Dictionary = (layers[diagnostic_layer] as Dictionary).get("worst_hit", {})
		if diagnostic_worst.is_empty(): continue
		var coordinates: Array = (diagnostic_worst.body as Dictionary).posed_skeleton_position
		var body_point := Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		var ray_sign: float = 1.0 if diagnostic_layer == "front" else -1.0
		var nearest_distance := INF
		var nearest: Dictionary = {}
		for candidate_layer: String in ["front", "back"]:
			var candidate_tree: TriangleMesh = panel_trees[candidate_layer]
			var candidate_hit: Dictionary = ray_hit(candidate_tree, body_point, ray_sign, RAY_COORDINATE_SCALE)
			if candidate_hit.is_empty(): continue
			var ray_distance: float = ray_sign * (body_point.z + ray_sign - (candidate_hit.position as Vector3).z)
			if ray_distance < 0 or ray_distance >= nearest_distance: continue
			nearest_distance = ray_distance
			nearest = {"layer": candidate_layer, "depth_m": ray_sign * (body_point.z - (candidate_hit.position as Vector3).z), "hit_skeleton_position": vector(candidate_hit.position as Vector3), "hit_skeleton_normal": vector(candidate_hit.normal as Vector3), "normal_abs_z": absf((candidate_hit.normal as Vector3).z), "filtered_panel_face_index": int(candidate_hit.get("face_index", -1))}
		diagnostic_worst["classified_panel_union_nearest_hit"] = nearest
	var distances := PackedFloat32Array()
	var maximum_displacement := 0.0
	var affected := 0
	cloth_snapshot.clear()
	for vertex: int in cloth:
		var displacement: float = (posed[vertex] as Vector3).distance_to(base[vertex])
		maximum_displacement = maxf(maximum_displacement, displacement)
		if displacement > .000001: distances.append(displacement)
		if displacement > .001: affected += 1
		cloth_snapshot.append(posed[vertex])
	distances.sort()
	var p95: float = distances[mini(distances.size() - 1, int(ceil(distances.size() * .95)) - 1)] if not distances.is_empty() else 0.0
	var final_bones: Array[Dictionary] = []
	for bone_index: int in sk.get_bone_count():
		var world: Transform3D = sk.global_transform * sk.get_bone_global_pose(bone_index)
		final_bones.append({"name": sk.get_bone_name(bone_index), "parent": sk.get_bone_parent(bone_index), "position": vector(world.origin), "basis": [vector(world.basis.x), vector(world.basis.y), vector(world.basis.z)]})
	var actual_shapes: Dictionary = {}
	for shape_index: int in geometry.get_blend_shape_count(): actual_shapes[str(geometry.get_blend_shape_name(shape_index))] = values[shape_index]
	result = {"request_id": request_id, "request_frame": request_frame, "applied_frame": applied_frame, "process_frame": applied_frame, "bone_pose_hash": hash(matrices.values()), "cloth_snapshot_hash": hash(cloth_snapshot.to_byte_array()), "clip": animation.current_animation, "clip_time": animation.current_animation_position, "layers": layers, "body_vertices": body.size(), "cloth_vertices": cloth.size(), "body_local_template_delta_max_m": body_template_delta_max, "uv_seam_template_gap_max_m": seam_template_gap_max, "covered_body_vertices": covered, "max_penetration_m": deepest, "max_local_displacement_m": maximum_displacement, "p95_local_displacement_m": p95, "affected_cloth_vertex_fraction_over_1mm": float(affected) / maxi(cloth.size(), 1), "affected_cloth_area_fraction_over_1mm": moved_area / maxf(area, .000001), "id": character, "position": vector(model_source.global_position), "model_transform": transform_record(model_source.global_transform), "skeleton_transform": transform_record(sk.global_transform), "mesh_transform": transform_record(mesh.global_transform), "mesh_name": str(mesh.name), "mesh_resource": geometry.resource_path, "blend_shape_values": {str(mesh.name): actual_shapes}, "bones": final_bones, "diagnostic_scope": "Actual same-callback world bone bases and morph scalars. Main acceptance includes the per-side true exterior union of unchanged independent pigment faces and complete Local-affected original source faces, then original.35 normal and5mm gates. Pigment and support metrics remain separate. Body/triangle indices refer to imported surface0; rest/UV identify GLB vertices; original unfiltered source face indices are retained."}
	result["ray_coordinate_scale"] = RAY_COORDINATE_SCALE
	result["legacy_unscaled_max_penetration_m"] = legacy_deepest
	# Retain the original vertex measurement separately. Acceptance also includes
	# the triangle interiors under exactly the original normal/depth thresholds.
	result["vertex_max_penetration_m"] = deepest
	result["surface_max_penetration_m"] = 0.0
	if measure_surface_witnesses:
		var surface_measurement: Dictionary = measure_surface(posed, panel_trees)
		result["surface_witnesses"] = surface_measurement
		result["surface_max_penetration_m"] = float(surface_measurement.max_penetration_m)
		result["max_penetration_m"] = maxf(deepest, float(surface_measurement.max_penetration_m))
		result["pose_context"] = pose_context()
	var union_measurement: Dictionary = {"vertex_max_penetration_m": deepest, "surface_max_penetration_m": float(result.surface_max_penetration_m), "max_penetration_m": float(result.max_penetration_m), "vertex_layers": layers, "surface_witnesses": result.get("surface_witnesses", {})}
	var pigment_measurement: Dictionary = union_measurement if pigment_source_face_indices == source_face_indices else measure_cloth_domain(posed, pigment_faces, pigment_source_face_indices)
	var support_measurement: Dictionary = union_measurement if support_source_face_indices == source_face_indices else measure_cloth_domain(posed, support_faces, support_source_face_indices)
	result["body_classification"] = body_classification_preparation
	result["cloth_domains"] = {"preparation": cloth_domain_preparation, "main_gate": "nearest exterior of pigment plus Local-support original source face union per side; normal gate applies only after exterior selection", "independent_pigment": pigment_measurement, "complete_local_support": support_measurement, "union": union_measurement}
	result["ray_precision_scope"] = "Tree and ray origins use scale 100, hit positions return to metres before unchanged .35 normal and 5 mm gates. Original unscaled trees use identical final bones, morphs, source faces, and body vertices in the same callback; their legacy measurements are retained per layer. This correction is independent of missing surface-witness or garment-classification coverage."
	completed_request = request_id
