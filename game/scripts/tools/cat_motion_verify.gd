extends SceneTree
## Imported-asset regression for the actual two game cat resources.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output: String = OS.get_cmdline_user_args()[0]
	var rows: Array[Dictionary] = []
	var baseline: bool = OS.get_cmdline_user_args().has("--baseline")
	var all_passed: bool = true
	for who: String in ["orange", "calico"]:
		var model: Node3D = (load("res://assets/models/AN_cat_%s_walk.glb" % who) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var eight_surfaces: int = 0
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var instance: MeshInstance3D = node as MeshInstance3D
			for surface: int in instance.mesh.get_surface_count():
				if (instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0: eight_surfaces += 1
		var yaw_values: Array[float] = []
		var tail_x: Array[float] = []
		var tail_landmark: Dictionary = face_landmarks(model, skeleton, true)
		player.play("Walk", 0)
		player.speed_scale = 0
		for sample: int in range(61):
			player.seek(player.get_animation("Walk").length * sample / 60.0, true)
			await process_frame
			skeleton.force_update_all_bone_transforms()
			var head_index: int = skeleton.find_bone("Head")
			var relative: Basis = skeleton.get_bone_global_pose(head_index).basis * skeleton.get_bone_global_rest(head_index).basis.inverse()
			yaw_values.append(relative.get_euler().y)
			var tip: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("Tail_11")).origin
			var base: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("Tail_00")).origin
			tail_x.append(skin_center(tail_landmark.back, tail_landmark.skin, skeleton).x - base.x)
		var metadata_node: Node = skeleton
		var native_speed: float = 0
		while metadata_node != null:
			var extras: Dictionary = metadata_node.get_meta("extras", {})
			if extras.has("walk_speed"):
				native_speed = float(extras["walk_speed"])
				break
			if metadata_node.has_meta("walk_speed"):
				native_speed = float(metadata_node.get_meta("walk_speed"))
				break
			if metadata_node == model: break
			metadata_node = metadata_node.get_parent()
		var row: Dictionary = {"cat": who, "joints": skeleton.get_bone_count(), "eight_influence_surfaces": eight_surfaces,
			"source_sha256": FileAccess.get_sha256("res://assets/models/AN_cat_%s_walk.glb" % who),
			"walk_seconds": player.get_animation("Walk").length, "idle_seconds": player.get_animation("Idle").length,
			"native_speed": native_speed,
			"full_clip_set": player.has_animation("SitDown") and player.has_animation("StandUp") and player.has_animation("Stretch") and player.has_animation("Run") and player.has_animation("Jump") and player.has_animation("Sneak"),
			"head_yaw_range_degrees": rad_to_deg(yaw_values.max() - yaw_values.min()),
			"tail_swing_m": tail_x.max() - tail_x.min()}
		row["passed"] = row.joints == 59 and bool(row.full_clip_set) and eight_surfaces > 0 and absf(float(row.walk_seconds) - 10) < .01 and absf(float(row.idle_seconds) - 8) < .01 and absf(float(row.native_speed) - .12) < .0001 and float(row.tail_swing_m) > .06
		var landmarks: Dictionary = face_landmarks(model, skeleton)
		var look: SkeletonModifier3D
		var attention_samples: Array[Dictionary] = []
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
		if not baseline:
			look = (load("res://scripts/animals/cat_look.gd") as GDScript).new() as SkeletonModifier3D
			look.set("attention_time", 0.0)
			skeleton.add_child(look)
			look.modification_processed.connect(func() -> void:
				var facial_direction: Vector3 = skin_center(landmarks.front, landmarks.skin, skeleton) - skin_center(landmarks.back, landmarks.skin, skeleton)
				attention_samples.append({"time": look.get("attention_time"), "face_yaw": atan2(facial_direction.x, facial_direction.z), "clip": player.current_animation}))
		for frame: int in range(720):
			var seconds: float = frame / 60.0
			var clip: String = "Walk" if int(seconds / 1.5) % 2 == 0 else "Idle"
			if player.current_animation != clip: player.play(clip, 0)
			player.speed_scale = 0
			player.seek(fmod(seconds, 1.5), true)
			await process_frame
			if baseline:
				var direction: Vector3 = skin_center(landmarks.front, landmarks.skin, skeleton) - skin_center(landmarks.back, landmarks.skin, skeleton)
				attention_samples.append({"time": seconds, "face_yaw": atan2(direction.x, direction.z), "clip": clip})
		var face_angles: Array[float] = []
		for sample: Dictionary in attention_samples: face_angles.append(float(sample.face_yaw))
		row["visible_face_yaw_range_degrees"] = rad_to_deg(face_angles.max() - face_angles.min())
		row["attention_survives_clip_restarts"] = float(row.visible_face_yaw_range_degrees) > 55 and (baseline or float(look.get("attention_time")) > 11.9)
		row["attention_samples"] = attention_samples
		row["passed"] = bool(row.passed) and bool(row.attention_survives_clip_restarts)
		all_passed = all_passed and bool(row.passed)
		rows.append(row)
		model.queue_free()
		await process_frame
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"passed": all_passed, "assets": rows}, "\t"))
	print("CAT_MOTION_ASSETS passed=", all_passed, " baseline=", baseline)
	quit(0 if (not all_passed if baseline else all_passed) else 1)

func face_landmarks(model: Node3D, skeleton: Skeleton3D, tail: bool = false) -> Dictionary:
	var points: Array[Dictionary] = []
	var skin: Skin
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.skin == null: continue
		skin = instance.skin
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var count: int = bones.size() / vertices.size()
			for index: int in vertices.size():
				var head_weight: float = 0.0
				for influence_index: int in count:
					var bind_index: int = bones[index * count + influence_index]
					var name: String = String(skin.get_bind_name(bind_index))
					if (name.begins_with("Tail_") if tail else name == "Head"): head_weight += weights[index * count + influence_index]
				if head_weight > .95:
					points.append({"point": vertices[index], "bones": bones.slice(index * count, (index + 1) * count), "weights": weights.slice(index * count, (index + 1) * count)})
	assert(points.size() > 100)
	points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.point as Vector3).z < (b.point as Vector3).z)
	var cap: int = maxi(10, points.size() / 20)
	return {"front": points.slice(points.size() - cap), "back": points.slice(0, cap), "skin": skin}

func skin_center(points: Array, skin: Skin, skeleton: Skeleton3D) -> Vector3:
	var center := Vector3.ZERO
	for landmark: Dictionary in points:
		var position := Vector3.ZERO
		var bones: PackedInt32Array = landmark.bones
		var weights: PackedFloat32Array = landmark.weights
		for index: int in bones.size():
			if weights[index] < .00001: continue
			var bind_index: int = bones[index]
			var bone_index: int = skeleton.find_bone(String(skin.get_bind_name(bind_index)))
			if bone_index < 0: bone_index = skin.get_bind_bone(bind_index)
			var transform_pose: Transform3D = skeleton.get_bone_global_pose(bone_index) * skin.get_bind_pose(bind_index)
			position += (transform_pose * (landmark.point as Vector3)) * weights[index]
		center += position
	return center / points.size()
