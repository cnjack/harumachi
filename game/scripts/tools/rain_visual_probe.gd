extends Node
## Native GPU regression: the shipping rain quad at known camera distances.
var output := ""
var shader_override := ""
var viewport: SubViewport
var camera: Camera3D
var weather: WeatherFX
var records: Array[Dictionary] = []

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--shader="): shader_override = arg.trim_prefix("--shader=")
	if output.is_empty():
		push_error("rain_visual_probe requires --out=<directory>")
		get_tree().quit(2)
		return
	call_deferred("run")

func frames(count: int) -> void:
	for index: int in count: await get_tree().process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(environment)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = .05
	viewport.add_child(camera)
	camera.make_current()
	weather = WeatherFX.new()
	viewport.add_child(weather)
	await frames(3)
	weather.set_weather("rain",false)
	if not shader_override.is_empty():
		var shader := Shader.new()
		shader.code = FileAccess.get_file_as_string(shader_override)
		var candidate := ShaderMaterial.new()
		candidate.shader = shader
		var quad: QuadMesh = weather.rain.draw_pass_1 as QuadMesh
		quad.material = candidate
	# Keep the real production draw-pass/material. Only particle motion/emission
	# is replaced so each photograph has a reproducible single particle centre.
	weather.rain.amount = 1
	weather.rain.lifetime = 60.0
	weather.rain.preprocess = 0.0
	weather.rain.explosiveness = 1.0
	var still := ParticleProcessMaterial.new()
	still.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	still.direction = Vector3.DOWN
	still.initial_velocity_min = 0.0
	still.initial_velocity_max = 0.0
	still.gravity = Vector3.ZERO
	still.scale_min = 1.0
	still.scale_max = 1.0
	weather.rain.process_material = still
	# Warm the actual GPU particle/process shader before measuring near fade.
	weather.rain.global_position = Vector3(0,0,-8)
	weather.rain.restart()
	await frames(60)
	for pitch: float in [0.0,35.0]:
		camera.rotation.x = deg_to_rad(-pitch)
		for distance: float in [.4,1.5,3.0,8.0]:
			weather.rain.global_position = camera.to_global(Vector3(0,0,-distance))
			await settle_particle()
			var filename: String = "rain_pitch_%02d_distance_%03d.png" % [int(pitch),int(distance*10)]
			await capture(filename,pitch,distance)
	camera.rotation = Vector3.ZERO
	for clip_side: String in ["inside","outside"]:
		var rain_quad: QuadMesh = weather.rain.draw_pass_1 as QuadMesh
		if rain_quad.material is ShaderMaterial:
			var rain_material: ShaderMaterial = rain_quad.material as ShaderMaterial
			rain_material.set_shader_parameter("clip_region",true)
			rain_material.set_shader_parameter("clip_rect",Vector4(-1,-9,1,-7) if clip_side == "inside" else Vector4(4,-9,6,-7))
		weather.rain.global_position = camera.to_global(Vector3(0,0,-8))
		await settle_particle()
		await capture("rain_clip_" + clip_side + ".png",0.0,8.0,clip_side)
	var checks := 0
	var failed := 0
	for measurement: Dictionary in records:
		if measurement.has("clip_case"):
			checks += 1
			if str(measurement.clip_case) == "inside" and int(measurement.lit_pixels) <= 20: failed += 1
			if str(measurement.clip_case) == "outside" and int(measurement.lit_pixels) != 0: failed += 1
		elif float(measurement.distance) <= 1.5:
			checks += 1
			if int(measurement.width) > 4 or int(measurement.height) > 160: failed += 1
		elif float(measurement.distance) == 8.0:
			checks += 1
			if int(measurement.lit_pixels) <= 20 or int(measurement.width) < 1 or int(measurement.width) > 4 or int(measurement.height) <= 20: failed += 1
	var report: Dictionary = {"shots":records,"resolution":[1280,720],"shader_override":shader_override,
		"checks":checks,"failed":failed,"passed":failed == 0,
		"scope":"Actual shipping GPUParticles3D draw pass, one static particle; motion and emission replaced solely for distance reproducibility."}
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	get_tree().quit(0 if failed == 0 else 1)

func capture(filename: String,pitch: float,distance: float,clip_case: String = "") -> Dictionary:
	await frames(12)
	await RenderingServer.frame_post_draw
	var picture: Image = viewport.get_texture().get_image()
	var error: Error = picture.save_png(output.path_join(filename))
	if error != OK:
		push_error("Unable to save rain probe " + filename)
		get_tree().quit(2)
		return {}
	var lit := 0
	var left := picture.get_width()
	var top := picture.get_height()
	var right := -1
	var bottom := -1
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			var pixel: Color = picture.get_pixel(x,y)
			if maxf(pixel.r,maxf(pixel.g,pixel.b)) < .025: continue
			lit += 1
			left = mini(left,x);right = maxi(right,x)
			top = mini(top,y);bottom = maxi(bottom,y)
	var row: Dictionary = {"file":filename,"pitch":pitch,"distance":distance,
		"lit_pixels":lit,"width":maxi(0,right-left+1),"height":maxi(0,bottom-top+1)}
	if not clip_case.is_empty(): row["clip_case"] = clip_case
	records.append(row)
	print("RAIN_PROBE ",row)
	return row

func settle_particle() -> void:
	# Upload the emitter transform before spawning world-space particles. Two
	# restarts also discard a first particle from a previous GPU buffer layout.
	await frames(2)
	for reset_index: int in 2:
		weather.rain.restart()
		await frames(4)
