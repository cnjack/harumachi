extends SceneTree
## Neutral front/back inventory pictures at a consistent camera and light.
## --script res://scripts/tools/model_stage.gd -- --out=/abs/path [--ids=H01,H02]

func _initialize() -> void:
	_run.call_deferred()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_meshes(child))
	return result


func _run() -> void:
	var output := "/tmp/model_stage"
	var ids: PackedStringArray = []
	var house_survey := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.substr(6)
		elif arg.begins_with("--ids="):
			ids = arg.substr(6).split(",")
		elif arg == "--house-survey":
			house_survey = true
	DirAccess.make_dir_recursive_absolute(output)
	if ids.is_empty():
		for file in DirAccess.get_files_at("res://assets/models"):
			if file.ends_with(".glb"):
				ids.append(file.get_basename())
	ids.sort()
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("dce5ef")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("cbd5ec")
	env.environment.ambient_light_energy = 0.65
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = house_survey
	stage.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(cam)
	cam.current = true
	var report: Dictionary = {}
	for id in ids:
		var scene := load("res://assets/models/%s.glb" % id) as PackedScene
		if scene == null:
			continue
		var model := scene.instantiate() as Node3D
		stage.add_child(model)
		var bound := AABB()
		var first := true
		for mi in _meshes(model):
			var box: AABB = mi.global_transform * mi.get_aabb()
			bound = box if first else bound.merge(box)
			first = false
		cam.size = maxf(bound.size.length() * 1.08, 0.1)
		var focus: Vector3 = bound.get_center()
		var views: Array[Vector3] = [Vector3(1, 0.55, 1.7), Vector3(-1, 0.55, -1.7)]
		var view_names: Array[String] = ["front", "back"]
		if house_survey:
			views.append_array([Vector3(-1.7, 0.55, 1), Vector3(1.7, 0.55, -1)])
			view_names.append_array(["left", "right"])
		for vi in views.size():
			cam.position = focus + views[vi].normalized() * maxf(bound.size.length() * 2, 1.0)
			cam.look_at(focus)
			await process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("%s_%s.png" % [id, view_names[vi]]))
		if house_survey:
			cam.size = 3.2
			var low_y: float = minf(bound.position.y + bound.size.y * 0.48, 1.85)
			var upper_y: float = maxf(low_y, bound.end.y - 1.55)
			var crops: Array[Dictionary] = [
				{"name": "near_front", "focus": Vector3(focus.x, low_y, bound.end.z - 0.6), "at": Vector3(focus.x + 0.6, low_y + 0.15, bound.end.z + 2.0)},
				{"name": "near_back", "focus": Vector3(focus.x, low_y, bound.position.z + 0.6), "at": Vector3(focus.x - 0.6, low_y + 0.15, bound.position.z - 2.0)},
				{"name": "near_left", "focus": Vector3(bound.position.x + 0.4, low_y, focus.z), "at": Vector3(bound.position.x - 2.0, low_y + 0.15, focus.z + 0.6)},
				{"name": "near_right", "focus": Vector3(bound.end.x - 0.4, low_y, focus.z), "at": Vector3(bound.end.x + 2.0, low_y + 0.15, focus.z - 0.6)},
				{"name": "near_eaves", "focus": Vector3(focus.x, upper_y, bound.end.z - 0.35), "at": Vector3(focus.x + 0.5, upper_y + 0.3, bound.end.z + 2.1)},
			]
			for crop in crops:
				cam.position = crop.at
				cam.look_at(crop.focus)
				await process_frame
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("%s_%s.png" % [id, crop.name]))
		report[id] = {"size": [bound.size.x, bound.size.y, bound.size.z]}
		stage.remove_child(model)
		model.free()
		print("STAGE ", id)
	var file := FileAccess.open(output.path_join("stage.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	quit()
