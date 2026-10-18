extends Node
## Native before/after inspection of source GLB animations, with no game modifiers.
var settings: Dictionary
var output: String
var panels: Array[Dictionary] = []
var caption: Label
var rows: Array[Dictionary] = []

func _ready() -> void:
	# Keep the native render size independent of macOS window clamping on a
	# smaller screen. The window may scale; the captured viewport stays 1080p.
	get_tree().root.content_scale_size = Vector2i(1920,1080)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://preview.json")) as Dictionary
	output = str(settings.output)
	DirAccess.make_dir_recursive_absolute(output)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("e9edf1")
	background.size = Vector2(1920,1080)
	canvas.add_child(background)
	_label(canvas, Vector2(26,12), str(settings.title), 30)
	caption = _label(canvas, Vector2(26,58), "", 23)
	_label(canvas, Vector2(26,1044), "原模型材质 · 原生骨骼动画 · 关闭全部游戏步态 / 接地 / 衣物修正器", 20)
	for index: int in 2:
		panels.append(_panel(canvas, index))
	if OS.get_cmdline_user_args().has("--record"):
		_record.call_deferred()
	else:
		_capture.call_deferred()

func _label(parent: Node, at: Vector2, text: String, size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_override("font", load("res://font.ttf") as Font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("243849"))
	parent.add_child(label)
	return label

func _panel(canvas: Node, index: int) -> Dictionary:
	var container := SubViewportContainer.new()
	container.position = Vector2(24 + index * 948,100)
	container.size = Vector2(924,930)
	container.stretch = true
	canvas.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(924,930)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8295a4")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("e5e9f0")
	env.environment.ambient_light_energy = .65
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-30,0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	(ground.mesh as PlaneMesh).size = Vector2(10,10)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("93a4af")
	ground.material_override = material
	stage.add_child(ground)
	var model: Node3D = (load("res://assets/" + ("before" if index == 0 else "after") + ".glb") as PackedScene).instantiate() as Node3D
	stage.add_child(model)
	var animation := model.find_child("AnimationPlayer",true,false) as AnimationPlayer
	var skeleton := model.find_child("Skeleton3D",true,false) as Skeleton3D
	assert(animation != null and skeleton != null)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.05
	stage.add_child(camera)
	camera.current = true
	_label(canvas, Vector2(42 + index * 948,112), "修前 · 源模型" if index == 0 else "候选 · 基础修复", 24)
	return {"model":model, "animation":animation, "skeleton":skeleton, "camera":camera}

func _apply_sample(sample: Dictionary) -> void:
	caption.text = str(sample.label)
	for panel: Dictionary in panels:
		var animation: AnimationPlayer = panel.animation
		var clip: String = str(sample.clip)
		assert(animation.has_animation(clip), clip)
		animation.play(clip,0)
		animation.seek(float(sample.time),true)
		animation.advance(0)
		var skeleton: Skeleton3D = panel.skeleton
		skeleton.force_update_all_bone_transforms()
		var target := Vector3(0,.90,0)
		var directions: Dictionary = {"front":Vector3(0,.10,1),"right":Vector3(1,.10,0),"back":Vector3(0,.10,-1),"left":Vector3(-1,.10,0),"top":Vector3(0,1,.001)}
		var direction: Vector3 = directions.get(str(sample.view),Vector3(.7,.10,.7))
		var camera: Camera3D = panel.camera
		camera.position = target + direction.normalized() * 4
		camera.look_at(target)

func _capture() -> void:
	for sample: Dictionary in settings.samples:
		_apply_sample(sample)
		await get_tree().process_frame
		# macOS can suppress the normal window draw signal while MovieMaker
		# still writes cached frames. Render this native viewport explicitly.
		RenderingServer.force_draw(false)
		var path: String = output.path_join(str(sample.id) + ".png")
		get_viewport().get_texture().get_image().save_png(path)
		var states: Array[Dictionary] = []
		for panel: Dictionary in panels:
			var skeleton: Skeleton3D = panel.skeleton
			var bones: Dictionary = {}
			for index: int in skeleton.get_bone_count():
				var pose: Transform3D = skeleton.get_bone_global_pose(index)
				bones[skeleton.get_bone_name(index)] = [pose.origin.x,pose.origin.y,pose.origin.z,pose.basis.x.x,pose.basis.x.y,pose.basis.x.z,pose.basis.y.x,pose.basis.y.y,pose.basis.y.z,pose.basis.z.x,pose.basis.z.y,pose.basis.z.z]
			states.append({"bones":bones,"clip":(panel.animation as AnimationPlayer).current_animation,"time":(panel.animation as AnimationPlayer).current_animation_position,"game_modifiers":0})
		rows.append({"sample":sample,"file":path,"states":states})
	var receipt := {"samples":rows,"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info(),"no_focus":DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS)}
	var file := FileAccess.open(output.path_join("native-poses.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"  "))
	file.close()
	print("LEG_FOUNDATION_CAPTURE_COMPLETE ",rows.size())
	get_tree().quit(0)

func _record() -> void:
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	var frames: Array[Dictionary] = []
	var stills: Array[Dictionary] = []
	var sections: Array[Dictionary] = []
	for clip: String in ["walk","run","binding_probe"]:
		var count: int = 360 if clip == "binding_probe" else 180
		sections.append({"motion_id":clip,"frames":count})
		for index: int in count:
			var view: String = ["front","right"][index / 180] if clip == "binding_probe" else ["front","right","back"][index / 60]
			var animation: AnimationPlayer = panels[0].animation
			var time: float = fposmod(float(index)/30.0,animation.get_animation(clip).length)
			var sample: Dictionary = {"clip":clip,"time":time,"view":view,"label":clip+" · "+view+" · 源动画原速；左右使用相同时间"}
			_apply_sample(sample)
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			var drawn: int = Engine.get_frames_drawn()
			var states: Array[Dictionary] = []
			for panel: Dictionary in panels:
				var skeleton: Skeleton3D = panel.skeleton
				var bones: Dictionary = {}
				for bone: int in skeleton.get_bone_count():
					var bone_name: String = skeleton.get_bone_name(bone)
					if "Leg" not in bone_name and "Foot" not in bone_name:continue
					var point: Vector3 = skeleton.get_bone_global_pose(bone).origin
					bones[bone_name] = [point.x,point.y,point.z]
				states.append({"clip":(panel.animation as AnimationPlayer).current_animation,"time":(panel.animation as AnimationPlayer).current_animation_position,"legs":bones})
			var frame_file: String = "frames/%04d.png" % frames.size()
			var pixels: Image = get_viewport().get_texture().get_image()
			assert(pixels.get_size() == Vector2i(1920,1080), "Native capture resolution changed")
			pixels.save_png(output.path_join(frame_file))
			frames.append({"sample_index":frames.size(),"file":frame_file,"process_frame":Engine.get_process_frames(),"window_draw_counter":drawn,"clip":clip,"time":time,"view":view,"states":states})
			if index % 60 == 30:
				var filename: String = "%s-%03d-%s.png" % [clip,index,view]
				pixels.save_png(output.path_join(filename))
				stills.append({"file":filename,"view":view,"sample_index":frames.size()-1,"process_frame":Engine.get_process_frames(),"window_draw_counter":drawn})
	var receipt: Dictionary = {"fps":30,"frames":frames,"sections":sections,"sources":settings.sources,"game_modifiers":0,"explicit_native_viewport_draw":true,"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info(),"no_focus":DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS)}
	var journal := FileAccess.open(output.path_join("movie-journal.json"),FileAccess.WRITE)
	journal.store_string(JSON.stringify(receipt))
	journal.close()
	var still_file := FileAccess.open(output.path_join("native-stills.json"),FileAccess.WRITE)
	still_file.store_string(JSON.stringify({"shots":stills}))
	still_file.close()
	print("LEG_FOUNDATION_MOVIE_COMPLETE ",frames.size())
	get_tree().quit(0)
