extends RefCounted
## Compare certified source morphs with the real imported animation at its clock.
## Local solver residuals are excluded by the caller. Geometry is never changed.
const POLICY := "authored-track-v1"
# Two millionths of weight is at most .24 micrometres for a 120 mm corrective.
# Native evaluation must verify this bound before qualifying a source model.
const VALUE_EPSILON := .000002

static func prepare(mesh: MeshInstance3D, player: AnimationPlayer, indices: PackedInt32Array, clips: Array[String]) -> Dictionary:
	if mesh == null or not mesh.mesh is ArrayMesh or player == null: return {"valid": false, "error": "missing source morph resource"}
	var geometry: ArrayMesh = mesh.mesh as ArrayMesh
	var root: Node = player.get_node_or_null(player.root_node)
	if root == null: return {"valid": false, "error": "missing animation root"}
	var slots: Dictionary = {}
	for source_slot: int in indices.size():
		var shape_name: String = str(geometry.get_blend_shape_name(indices[source_slot]))
		if slots.has(shape_name): return {"valid": false, "error": "duplicate source shape name"}
		slots[shape_name] = source_slot
	var plans: Dictionary = {}
	for clip: String in clips:
		if not player.has_animation(clip): return {"valid": false, "error": "missing source clip"}
		var animation: Animation = player.get_animation(clip)
		var tracks := PackedInt32Array()
		tracks.resize(indices.size())
		tracks.fill(-1)
		for track: int in animation.get_track_count():
			var path: NodePath = animation.track_get_path(track)
			var target: Node = root.get_node_or_null(NodePath(path.get_concatenated_names()))
			if target != mesh: continue
			var track_type: int = animation.track_get_type(track)
			if track_type == Animation.TYPE_VALUE and str(path.get_concatenated_subnames()).begins_with("blend_shapes/"):
				return {"valid": false, "error": "source shape uses unsupported value track"}
			if track_type != Animation.TYPE_BLEND_SHAPE: continue
			if path.get_subname_count() != 1: return {"valid": false, "error": "ambiguous source shape path"}
			var name: String = str(path.get_subname(0))
			if not slots.has(name):
				# Importers may retain all-zero Local tracks. A nonzero authored
				# Local would compete with the solver and is never qualified.
				if name.begins_with("Garment_Local_"):
					for key: int in animation.track_get_key_count(track):
						if float(animation.track_get_key_value(track, key)) != 0.0: return {"valid": false, "error": "animation writes solver residual"}
					continue
				return {"valid": false, "error": "unresolved source shape"}
			var slot: int = int(slots[name])
			if tracks[slot] != -1: return {"valid": false, "error": "duplicate source shape track"}
			if not animation.track_is_enabled(track): continue
			if animation.track_get_key_count(track) == 0 or animation.track_get_interpolation_type(track) != Animation.INTERPOLATION_LINEAR:
				return {"valid": false, "error": "unsupported source shape interpolation"}
			tracks[slot] = track
		plans[clip] = {"animation": animation, "tracks": tracks}
	return {"valid": true, "error": "", "clips": plans, "shape_count": indices.size()}

static func mismatch(plan: Dictionary, clip: String, time: float, actual: PackedFloat32Array) -> String:
	if not bool(plan.get("valid", false)) or not is_finite(time): return "source morph plan unavailable"
	var clips: Dictionary = plan.get("clips", {})
	if not clips.has(clip): return "source morph clip unavailable"
	var current: Dictionary = clips[clip]
	var animation: Animation = current.animation
	var tracks: PackedInt32Array = current.tracks
	if actual.size() != tracks.size(): return "source morph inventory changed"
	for slot: int in tracks.size():
		var value: float = actual[slot]
		if not is_finite(value): return "nonfinite source morph"
		if tracks[slot] < 0:
			if value != 0.0: return "additional morph"
			continue
		var expected: float = animation.blend_shape_track_interpolate(tracks[slot], time)
		if not is_finite(expected) or absf(value - expected) > VALUE_EPSILON: return "authored morph value mismatch"
	return ""
