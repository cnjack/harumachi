extends RefCounted
## Native hand detail cameras use the final applied bone sample for framing.

func position(bones: Array, suffix: String) -> Vector3:
	for bone: Dictionary in bones:
		if str(bone.name).ends_with(suffix):
			var values: Array = bone.position
			return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.INF

func capture(qa: Node) -> void:
	qa.call("outdoors")
	for id: String in qa.get("ids"):
		qa.call("choose", id, Vector3(-8, .03, -10))
		for clip: String in qa.get("hand_clips"):
			var phase: float = 0.0 if clip == "idle" else .625 if clip == "wave" else .5
			qa.call("pose", clip, phase)
			await qa.call("snapshot", {"id": id, "action": clip, "phase": phase, "scene": "hand_reference", "kind": "authored_pose_seek"}, "front")
			var rows: Array = qa.get("rows")
			var bones: Array = rows.back().get("bones", [])
			for side: String in ["Left", "Right"]:
				var wrist: Vector3 = position(bones, side + "Hand")
				var middle: Vector3 = position(bones, side + "HandMiddle1")
				var index: Vector3 = position(bones, side + "HandIndex1")
				var pinky: Vector3 = position(bones, side + "HandPinky1")
				if not wrist.is_finite() or not middle.is_finite() or not index.is_finite() or not pinky.is_finite():
					qa.get("failures").append(id + ": missing final hand detail landmarks")
					continue
				var centre: Vector3 = wrist.lerp(middle, .75)
				var normal: Vector3 = (index - wrist).cross(pinky - wrist).normalized()
				if normal.length_squared() < .5:
					qa.get("failures").append(id + ": degenerate hand detail plane")
					continue
				for sign_value: float in [1.0, -1.0]:
					qa.set("camera_override", true)
					var camera: Camera3D = qa.get("camera") as Camera3D
					camera.size = .30
					camera.global_position = centre + normal * sign_value * .55
					var up: Vector3 = (middle - wrist).normalized()
					camera.look_at(centre, up)
					await qa.call("snapshot", {"id": id, "action": clip, "phase": phase, "scene": "hand_%s_%s" % [side, "a" if sign_value > 0 else "b"], "kind": "authored_hand_detail", "camera_landmarks_from_final_pose": true}, "front")
					qa.set("camera_override", false)
