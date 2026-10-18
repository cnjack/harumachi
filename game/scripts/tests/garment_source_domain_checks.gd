extends RefCounted
## Independent imported-domain regression, without playing or sampling a pose.
## Exact expectations come from external source-face lists, not this probe's
## mask algorithm. Totals retain paint-only faces as well as Local support.
const EXPECTED: Dictionary = {
	"mio": {"total": 33290, "front": 14565, "back": 18725},
	"kazuko": {"total": 18466, "front": 10359, "back": 8107},
	"ren": {"total": 16778, "front": 13360, "back": 3418},
}
const PROBE = preload("res://scripts/tools/garment_qa_pose_probe.gd")
var t: Node

func _init(runner: Node) -> void:
	t = runner

func run() -> void:
	for actor_id: String in ["mio", "kazuko", "ren"]:
		var expected: Dictionary = EXPECTED[actor_id]
		var npc: NPC = t.main.npcs.get(actor_id) as NPC
		var skeleton: Skeleton3D = npc.model.find_child("Skeleton3D", true, false) as Skeleton3D if npc != null else null
		if skeleton == null:
			t.check("GARMENT_SOURCE_DOMAINS", actor_id + " imported complete cloth source domain", false, JSON.stringify({"id": actor_id, "expected": expected, "error": "selected imported NPC skeleton missing"}))
			continue
		var probe: SkeletonModifier3D = PROBE.new()
		probe.name = actor_id + "ImportedGarmentDomainRegression"
		# prepare() reads the actual imported mesh/skin/atlas/rest. The modifier
		# never runs, makes no requests, and cannot perturb source/bone/morph state.
		probe.active = false
		probe.set("measure_surface_witnesses", true)
		skeleton.add_child(probe)
		probe.call("prepare", npc.model)
		var preparation: Dictionary = probe.get("cloth_domain_preparation")
		var faces: Dictionary = probe.get("faces")
		var source_faces: Dictionary = probe.get("source_face_indices")
		var pigments: Dictionary = probe.get("pigment_faces")
		var supports: Dictionary = probe.get("support_faces")
		var surface: Dictionary = probe.get("surface_witness_preparation")
		var anchors: PackedInt32Array = probe.get("body")
		var witnesses: Array = probe.get("surface_witnesses")
		var measured: Dictionary = {}
		var total: int = 0
		var exact: bool = str(probe.get("character")) == actor_id
		for side: String in ["front", "back"]:
			var triangles: Array = faces.get(side, [])
			var original_ids: Array = source_faces.get(side, [])
			var independent: Array = pigments.get(side, [])
			var local_support: Array = supports.get(side, [])
			var metadata: Dictionary = preparation.get(side, {})
			var unique_ids: Dictionary = {}
			for source_face: int in original_ids: unique_ids[source_face] = true
			var count: int = triangles.size()
			total += count
			exact = exact and count == int(expected[side]) and original_ids.size() == count and unique_ids.size() == count and int(metadata.get("union_source_triangles", -1)) == count
			measured[side] = {"union_source_triangles": count, "unique_imported_source_face_indices": unique_ids.size(), "original_sided_pigment_source_triangles": int(metadata.get("original_sided_pigment_source_triangles", metadata.get("independent_pigment_source_triangles", -1))), "additional_complete_pigment_source_triangles": int(metadata.get("additional_complete_pigment_source_triangles", 0)), "independent_pigment_source_triangles": independent.size(), "all_local_support_source_triangles": local_support.size(), "supplementary_source_triangles_not_in_pigment": count - independent.size()}
		exact = exact and total == int(expected.total)
		var mesh: MeshInstance3D = probe.get("mesh") as MeshInstance3D
		var detail: Dictionary = {"id": actor_id, "expected_external_source_face_counts": expected, "actual_union_total": total, "layers": measured, "original_body_anchors": anchors.size(), "fully_labelled_body_source_triangles": int(surface.get("fully_labelled_body_source_triangles", 0)), "selected_source_triangles": int(surface.get("selected_source_triangles", 0)), "selected_mixed_corner_source_triangles": int(surface.get("selected_mixed_corner_source_triangles", 0)), "surface_witness_count": witnesses.size(), "declared_witness_count": int(surface.get("witness_count", 0)), "body_classification": probe.get("body_classification_preparation"), "skeleton_bone_count": skeleton.get_bone_count(), "scope": "Actual import preparation only; no pose request, animation seek, shader/render, contact/naturalness/performance acceptance, production solver or certificate change. Exact front/back union expectations include original independent paint plus Local support and externally confirmed complete-paint additions."}
		if mesh != null and mesh.mesh is ArrayMesh:
			var geometry: ArrayMesh = mesh.mesh as ArrayMesh
			detail["mesh_name"] = str(mesh.name)
			detail["mesh_resource"] = geometry.resource_path
			detail["surface0_vertices"] = geometry.surface_get_array_len(0)
			detail["surface0_indices"] = geometry.surface_get_array_index_len(0)
			detail["source_blend_shape_count"] = geometry.get_blend_shape_count()
		t.check("GARMENT_SOURCE_DOMAINS", actor_id + " imported complete cloth source domain", exact, JSON.stringify(detail))
		skeleton.remove_child(probe)
		probe.free()
