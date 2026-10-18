extends RefCounted
## Optional acceleration only. Missing/unsupported native code keeps GD contact.
const CLASS := &"NativeTriangleFilter"
const EXTENSION := "res://addons/character_contact_filter/character_contact_filter.gdextension"
const LIBRARY := "res://addons/character_contact_filter/bin/libnative_triangle_filter.arm64.dylib"
const METHOD_HASH := 3648293151

static func prepare() -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	if int(version.get("major", 0)) != 4 or int(version.get("minor", 0)) != 8 or str(version.get("status", "")) != "dev7" or not str(version.get("hash", "")).begins_with("c971f93e7"):
		return {"ready": false, "reason": "engine pin mismatch"}
	if OS.get_name() != "macOS" or Engine.get_architecture_name() != "arm64":
		return {"ready": false, "reason": "platform uses GD"}
	if not ClassDB.class_exists(CLASS):
		if not FileAccess.file_exists(EXTENSION) or not FileAccess.file_exists(LIBRARY):
			return {"ready": false, "reason": "optional native package missing"}
		GDExtensionManager.load_extension(EXTENSION)
	if not ClassDB.class_exists(CLASS) or not ClassDB.class_has_method(CLASS, &"filter_layer") or not ClassDB.class_has_method(CLASS, &"configure_method_hash"):
		return {"ready": false, "reason": "native class unavailable"}
	if not bool(ClassDB.class_call_static(CLASS, &"configure_method_hash", METHOD_HASH)):
		return {"ready": false, "reason": "engine ray method unavailable"}
	return {"ready": true, "reason": "pinned native filter"}

static func filter_layer(tree: TriangleMesh, points: PackedVector3Array, lower: Vector3, upper: Vector3, bounds: PackedFloat32Array, columns: int, rows: int, sign_z: float, margin: float, scale: float, initial_depth: float) -> Dictionary:
	var value: Variant = ClassDB.class_call_static(CLASS, &"filter_layer", tree, points, lower, upper, bounds, columns, rows, sign_z, margin, scale, initial_depth)
	return value as Dictionary if value is Dictionary else {}

static func valid_result(result: Dictionary, body_count: int, face_count: int) -> bool:
	# Validate before committing counters or running any constraint. Failure can
	# safely run the full GD filter because the C filter only reads the tree.
	if not result.get("indices") is PackedInt32Array or not result.get("hits") is Array or not result.get("depths") is PackedFloat64Array: return false
	if not result.get("flags") is PackedByteArray or not result.get("origins") is PackedVector3Array: return false
	var indices: PackedInt32Array = result.indices
	var hits: Array = result.hits
	var depths: PackedFloat64Array = result.depths
	if indices.size() != hits.size() or depths.size() != body_count or (result.flags as PackedByteArray).size() != body_count or (result.origins as PackedVector3Array).size() != body_count: return false
	if typeof(result.get("raw_queries")) != TYPE_INT or typeof(result.get("broadphase_skips")) != TYPE_INT or typeof(result.get("max_contact_depth")) != TYPE_FLOAT: return false
	if int(result.raw_queries) < 0 or int(result.broadphase_skips) < 0 or int(result.raw_queries) + int(result.broadphase_skips) > body_count or not is_finite(float(result.max_contact_depth)): return false
	var previous := -1
	for slot: int in indices.size():
		var ordinal: int = indices[slot]
		if ordinal <= previous or ordinal < 0 or ordinal >= body_count or not is_finite(depths[ordinal]): return false
		if not hits[slot] is Dictionary: return false
		var hit: Dictionary = hits[slot]
		if typeof(hit.get("face_index")) != TYPE_INT or not hit.get("position") is Vector3 or not hit.get("normal") is Vector3: return false
		if int(hit.face_index) < 0 or int(hit.face_index) >= face_count: return false
		previous = ordinal
	return true
