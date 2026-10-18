extends RefCounted
## Exact source folds that TriangleMesh's metre-scale epsilon skipped.
## Expected old-scale inner hits are diagnostics, not passing assertions.
const CharacterGarmentSupport = preload("res://scripts/characters/character_garment_support.gd")
const FIXTURE := "res://scripts/tests/fixtures/character_ray_precision.json"
const MAX_HIT_ERROR_M := 0.00003
var t: Node

func _init(runner: Node) -> void:
	t = runner

func vertex(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func ray_sample(case: Dictionary, coordinate_scale: float) -> Dictionary:
	var points := PackedVector3Array()
	for triangle: String in ["outer_triangle", "inner_triangle"]:
		for corner: Variant in case[triangle]: points.append(vertex(corner) * coordinate_scale)
	var tree := TriangleMesh.new()
	tree.create_from_faces(points)
	var point: Vector3 = vertex(case.query)
	var sign_z: float = float(case.sign)
	var hit: Dictionary = tree.intersect_ray((point + Vector3(0, 0, sign_z)) * coordinate_scale, Vector3(0, 0, -sign_z))
	if hit.is_empty(): return {"hit": false, "coordinate_scale": coordinate_scale}
	var restored: Vector3 = (hit.position as Vector3) / coordinate_scale
	var expected: Vector3 = vertex(case.expected_outer_hit)
	var depth: float = sign_z * (point.z - restored.z)
	return {"hit": true, "coordinate_scale": coordinate_scale, "face_index": int(hit.face_index), "source_face": int(case.source_outer_face) if int(hit.face_index) == 0 else int(case.source_inner_face), "position_m": [restored.x, restored.y, restored.z], "signed_depth_m": depth, "normal_abs_z": absf((hit.normal as Vector3).z), "distance_to_exact_outer_m": restored.distance_to(expected), "depth_error_m": absf(depth - float(case.expected_outer_depth_m))}

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var fixture: Dictionary = parsed if parsed is Dictionary else {}
	var cases: Array = fixture.get("cases", [])
	var production_scale: float = float(CharacterGarmentSupport.RAY_SPACE_SCALE)
	for case_index: int in 4:
		if case_index >= cases.size():
			t.check("GARMENT_LOCAL", "source ray precision fixture %d exists" % case_index, false, "Expected four actual-source cases")
			continue
		var case: Dictionary = cases[case_index]
		var actual: Dictionary = ray_sample(case, production_scale)
		var old_scale_negative: Dictionary = ray_sample(case, 1.0)
		var correct: bool = cases.size() == 4 and bool(actual.get("hit", false)) and int(actual.get("face_index", -1)) == 0 and float(actual.get("distance_to_exact_outer_m", INF)) <= MAX_HIT_ERROR_M and float(actual.get("depth_error_m", INF)) <= MAX_HIT_ERROR_M
		var detail: Dictionary = {"case": case.name, "production": actual, "old_scale_negative_control": old_scale_negative, "old_scale_scope": "Expected wrong inner hit; this observation is never a PASS condition", "maximum_hit_error_m": MAX_HIT_ERROR_M, "model_sha256": fixture.get("model_sha256", "missing")}
		print("GARMENT_RAY_PRECISION_SAMPLE ", JSON.stringify(detail))
		t.check("GARMENT_LOCAL", str(case.name) + " production ray hits nearest outer cloth and restores metres within30um", correct, JSON.stringify(detail))
