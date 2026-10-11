extends RefCounted
## Two native GPU frames using the actual production rain shader and measured
## roof map. Bright cyan fixed streaks make clipping independently measurable.
## Normal rain/noon art acceptance is still captured by the ordinary scene QA.
const SHELTER_PARAMETERS: Array[String]=["shelter_enabled","shelter_world_to_local","shelter_rect","shelter_height","shelter_surface_margin"]

func uniform_snapshot(material: ShaderMaterial) -> Dictionary:
	var result: Dictionary={}
	for key: String in SHELTER_PARAMETERS:
		var value: Variant=material.get_shader_parameter(key)
		if value is Texture2D:
			var tex: Texture2D=value as Texture2D
			var image: Image=tex.get_image()
			result[key]={"type":"Texture2D","instance":tex.get_instance_id(),"size":[tex.get_width(),tex.get_height()],"format":image.get_format(),"metre_samples":[image.get_pixel(0,0).r,image.get_pixel(int(image.get_width()*.5),int(image.get_height()*.5)).r,image.get_pixel(image.get_width()-1,image.get_height()-1).r]}
		elif value is Transform3D:
			var matrix: Transform3D=value as Transform3D
			result[key]={"type":"Transform3D","value":str(matrix),"origin":[matrix.origin.x,matrix.origin.y,matrix.origin.z]}
		elif value is Projection:
			var projection: Projection=value as Projection
			var columns: Array[Array]=[]
			for index: int in 4:
				var column: Vector4=projection[index]
				columns.append([column.x,column.y,column.z,column.w])
			result[key]={"type":"Projection","columns":columns}
		elif value is Vector4:
			var vector: Vector4=value as Vector4
			result[key]={"type":"Vector4","value":[vector.x,vector.y,vector.z,vector.w]}
		else:result[key]={"type":type_string(typeof(value)),"value":value}
	return result

func capture(main: Node,output: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(output)
	var fx: WeatherFX=main.weather_fx
	var stall: Node3D=main.world.get_node("P09") as Node3D
	var saved_region: String=main.world.region
	main.world.set_region("town")
	fx.prepare_stall_shelter()
	var source: ShaderMaterial=fx.get("_rain_material") as ShaderMaterial
	var diagnostic:=source.duplicate() as ShaderMaterial
	var source_uniforms: Dictionary=uniform_snapshot(source)
	var duplicate_uniforms: Dictionary=uniform_snapshot(diagnostic)
	diagnostic.set_shader_parameter("rain_color",Color(.08,.62,1.0,1.0))
	var previous_camera: Camera3D=main.get_viewport().get_camera_3d()
	var rain_visible: bool=fx.rain.visible
	fx.rain.visible=false
	var owner:=Node3D.new()
	owner.name="FixedStallRainProof"
	main.add_child(owner)
	var camera:=Camera3D.new()
	owner.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3.25
	camera.global_position=stall.to_global(Vector3(0,1.55,6))
	camera.look_at(stall.to_global(Vector3(0,1.55,0)))
	camera.make_current()
	var viewport_size: Vector2=main.get_viewport().get_visible_rect().size
	var probes: Array[Dictionary]=[]
	for lane: String in ["below","above","outside"]:
		var positions: Array[Vector3]=[]
		if lane=="outside":positions.assign([Vector3(-1.48,1.25,.20),Vector3(1.48,1.25,.20)])
		else:
			for x: float in [-.6,-.4,-.2,0.0,.2,.4,.6]:positions.append(Vector3(x,1.25 if lane=="below" else 2.17,.20))
		for at: Vector3 in positions:
			var mesh:=MeshInstance3D.new()
			var quad:=QuadMesh.new()
			quad.size=Vector2(.024,.28)
			quad.material=diagnostic
			mesh.mesh=quad
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			owner.add_child(mesh)
			mesh.global_position=stall.to_global(at)
			var screen: Vector2=camera.unproject_position(mesh.global_position)
			probes.append({"lane":lane,"world":[mesh.global_position.x,mesh.global_position.y,mesh.global_position.z],"screen_viewport":[screen.x,screen.y]})
	var files: Array[String]=[]
	var images: Array[Dictionary]=[]
	var png_size:=Vector2i.ZERO
	var explicit_uniforms: Dictionary={}
	for explicit_copy: bool in [false,true]:
		if explicit_copy:
			for parameter: String in SHELTER_PARAMETERS:diagnostic.set_shader_parameter(parameter,source.get_shader_parameter(parameter))
			explicit_uniforms=uniform_snapshot(diagnostic)
		for enabled: bool in [false,true]:
			diagnostic.set_shader_parameter("shelter_enabled",enabled)
			# Wait five complete process/render pairs after every uniform change.
			for _settle_frame: int in 5:
				await main.get_tree().process_frame
				await RenderingServer.frame_post_draw
			var filename: String="roof_clip_enabled.png" if enabled else "roof_clip_disabled_control.png"
			if explicit_copy:filename="explicit_"+filename
			var pixels: Image=main.get_viewport().get_texture().get_image()
			png_size=pixels.get_size()
			pixels.save_png(output.path_join(filename))
			files.append(filename)
			images.append({"file":filename,"sha256":FileAccess.get_sha256(output.path_join(filename)),"png_size":[png_size.x,png_size.y],"explicit_uniform_copy":explicit_copy,"requested_enabled":enabled})
	for probe: Dictionary in probes:
		var logical: Array=probe.screen_viewport
		var png_point:=Vector2(float(logical[0]),float(logical[1]))*Vector2(png_size)/viewport_size
		probe["screen_png"]=[png_point.x,png_point.y]
		probe["screen"]=[png_point.x,png_point.y]
	var result: Dictionary={"files":files,"images":images,"viewport_size":[viewport_size.x,viewport_size.y],"png_size":[png_size.x,png_size.y],"settle_render_frames_per_state":5,"uniform_dump":{"source":source_uniforms,"duplicate_before_copy":duplicate_uniforms,"duplicate_after_explicit_copy":explicit_uniforms},"probes":probes,"height_map":fx.rain_shelter_status(),"shader_sha256":FileAccess.get_sha256("res://shaders/rain_streak.gdshader"),"note":"Four GPU diagnostic frames compare defaultduplicate against explicitcopy of all5shelter parameters, eachwith disabledcontrol andenabled. Actual production shader and numeric roof texture; only colour and fixed quads are diagnostic. screen/screen_png are PNG pixels;screen_viewport is logical projection."}
	var file:=FileAccess.open(output.path_join("native-roof-clip.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	fx.rain.visible=rain_visible
	main.world.set_region(saved_region)
	fx.prepare_stall_shelter()
	if is_instance_valid(previous_camera):previous_camera.make_current()
	owner.queue_free()
	await main.get_tree().process_frame
	return result
