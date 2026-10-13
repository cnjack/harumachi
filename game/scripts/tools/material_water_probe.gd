extends SceneTree
## Native renderer diagnostic, deliberately labelled fixtures rather than player screenshots.
## Run only with HARUMACHI_SAVE_DIR, --out=<directory>; no default save access.
var main: Node3D
var world: Node3D
var farm: Node3D
var water: ShaderMaterial
var camera: Camera3D
var output: String
var rows: Array[Dictionary]=[]
var analysis_focus: Vector3
var analysis_span:=Vector2(3.0,3.0)

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
		printerr("Material water probe requires an isolated save directory")
		quit(2);return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.substr(6)
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var state: Node=root.get_node("GameState")
	state.set("clock_paused",true)
	main=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main);current_scene=main
	var warm: int=0
	while not bool(main.get("loading_ready")) and warm<1200:
		await process_frame;warm+=1
	if not bool(main.get("loading_ready")):quit(3);return
	for settle: int in 8:await process_frame
	world=main.get("world") as Node3D
	farm=world.get("farm") as Node3D
	water=farm.get("water_mat") as ShaderMaterial
	var rig: Node=main.get("rig") as Node
	rig.process_mode=Node.PROCESS_MODE_DISABLED
	camera=rig.get("cam") as Camera3D
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	(main.get("ui") as Node).call("set_hud_visible",false)
	((main.get("ui") as Node).get("panels") as RefCounted).call("set_cards_visible",false)
	var player: Node3D=main.get("player") as Node3D
	player.visible=false;player.process_mode=Node.PROCESS_MODE_DISABLED
	for npc: Node3D in (main.get("npcs") as Dictionary).values():
		npc.visible=false;npc.process_mode=Node.PROCESS_MODE_DISABLED
	main.process_mode=Node.PROCESS_MODE_DISABLED
	world.call("set_region","farm")
	world.call("set_indoor_look",false)
	camera.near=.05;camera.fov=42.0;camera.keep_aspect=Camera3D.KEEP_HEIGHT
	# All paired frames use identical geometry, sky, camera, phase and exposure.
	# Each light gate isolates the contribution of the real production water shader.
	world.call("update_time",720.0,"sunny",true)
	var focus: Vector3=farm.global_position+Vector3(104,-.28,17)
	var sunlight: Vector3=water.get_shader_parameter("sun_direction") as Vector3
	var sun_view:=Vector3(-sunlight.x,absf(sunlight.y),-sunlight.z).normalized()
	_point(focus,focus+sun_view*15.0,false)
	water.set_shader_parameter("animation_time",10.0)
	water.set_shader_parameter("wave_strength",1.0)
	water.set_shader_parameter("rain_amount",0.0)
	water.set_shader_parameter("sunlight_amount",1.0)
	await _shot("sun_on","isolated_solar_contribution")
	water.set_shader_parameter("sunlight_amount",0.0)
	await _shot("sun_off","same_frame_solar_disabled")
	water.set_shader_parameter("sunlight_amount",1.0)
	water.set_shader_parameter("animation_time",10.7)
	await _shot("sun_next","solar_motion_after_0.7_seconds")
	# Ordinary near-bank angle using the production TIME clock, without a
	# frozen phase override. All scene actors remain paused to isolate water.
	var live_focus: Vector3=farm.global_position+Vector3(8.5,-.28,16.4)
	_point(live_focus,farm.global_position+Vector3(5.5,1.5,12.5),false)
	analysis_span=Vector2(1.4,.45)
	water.set_shader_parameter("animation_time",-1.0)
	await _shot("live_wave_0","production_render_clock_near_bank")
	await create_timer(.7).timeout
	await _shot("live_wave_07","production_render_clock_after_0.7_seconds")
	# Whole-water top view: 4.2 metres tall, so ripple components can be measured in metres.
	var rain_focus: Vector3=farm.global_position+Vector3(20,-.28,17.6)
	_point(rain_focus,rain_focus+Vector3.UP*7.0,true)
	analysis_span=Vector2(2.4,1.7)
	camera.size=4.2
	water.set_shader_parameter("animation_time",12.0)
	water.set_shader_parameter("sunlight_amount",0.0)
	water.set_shader_parameter("shallow_opacity",1.0)
	water.set_shader_parameter("rain_amount",0.0)
	await _shot("rain_off","opaque_water_control_no_rings")
	water.set_shader_parameter("rain_amount",1.0)
	await _shot("rain_on","isolated_shader_rings_no_rain_particles")
	water.set_shader_parameter("rain_amount",0.0)
	water.set_shader_parameter("shallow_opacity",.34)
	world.call("update_time",1260.0,"sunny",true)
	water.set_shader_parameter("animation_time",10.0)
	water.set_shader_parameter("lamp_amount",0.0)
	var moon: Node3D=world.get("moon") as Node3D
	var moon_position: Vector3=moon.global_position
	water.set_shader_parameter("moon_position",moon_position)
	var moon_ray: Vector3=(moon_position-focus).normalized()
	_point(focus,focus+Vector3(-moon_ray.x,absf(moon_ray.y),-moon_ray.z)*16.0,false)
	water.set_shader_parameter("moonlight_amount",1.0)
	await _shot("moon_on","actual_moon_direction_reflection")
	water.set_shader_parameter("moonlight_amount",0.0)
	await _shot("moon_off","same_frame_moon_disabled")
	var lamp_position: Vector3=Vector3.ZERO
	var nearest: float=INF
	var lamp_focus: Vector3=farm.global_position+Vector3(2.4,-.28,15.7)
	for lamp: OmniLight3D in farm.get("lamp_lights") as Array:
		# Keep the original full-strength bank lamp in the regression fixture;
		# the newly added small bridge lanterns must not displace it.
		if absf(float(lamp.get_meta("outdoor_energy_scale",1.0))-1.0)>.0001:continue
		if lamp.global_position.distance_to(lamp_focus)<nearest:
			nearest=lamp.global_position.distance_to(lamp_focus);lamp_position=lamp.global_position
	var lamp_ray: Vector3=(lamp_position-lamp_focus).normalized()
	_point(lamp_focus,lamp_focus+Vector3(-lamp_ray.x,absf(lamp_ray.y),-lamp_ray.z)*7.0,false)
	analysis_span=Vector2(.42,.78)
	water.set_shader_parameter("lamp_amount",1.0)
	await _shot("lamp_on","actual_bridge_lamp_reflection")
	water.set_shader_parameter("lamp_amount",0.0)
	await _shot("lamp_off","same_frame_bridge_lamp_disabled")
	# Isolate one real bridge lamp three ways. A shader that ignores its
	# production 0.35 scale would produce identical on/unit images.
	var original_weights: PackedFloat32Array=water.get_shader_parameter("reflection_lamp_weights")
	var lamp_positions: PackedVector3Array=water.get_shader_parameter("reflection_lamps")
	var bridge_index: int=-1
	var bridge_position:=Vector3.ZERO
	var bridge_weight: float=0.0
	for lamp: OmniLight3D in farm.get("lamp_lights") as Array:
		if not lamp.has_meta("outdoor_energy_scale"):continue
		for index: int in int(water.get_shader_parameter("reflection_lamp_count")):
			if lamp_positions[index].distance_to(lamp.global_position)<.001:
				bridge_index=index;bridge_position=lamp.global_position;bridge_weight=float(lamp.get_meta("outdoor_energy_scale"));break
		if bridge_index>=0:break
	if bridge_index<0:printerr("Weighted bridge lamp fixture missing");quit(5);return
	var bridge_focus: Vector3=bridge_position+Vector3(-.55 if bridge_position.x<farm.global_position.x else .55,0,0)
	bridge_focus.y=farm.global_position.y+LakesideLayout.WATER_Y
	var bridge_ray: Vector3=(bridge_position-bridge_focus).normalized()
	_point(bridge_focus,bridge_focus+Vector3(-bridge_ray.x,absf(bridge_ray.y),-bridge_ray.z)*5.0,false)
	analysis_span=Vector2(.30,.50)
	var isolated_weights:=PackedFloat32Array();isolated_weights.resize(8)
	isolated_weights[bridge_index]=bridge_weight
	water.set_shader_parameter("reflection_lamp_weights",isolated_weights)
	water.set_shader_parameter("lamp_amount",1.0)
	await _shot("bridge_scale_on","one_real_bridge_light_at_actual_outdoor_energy_scale")
	isolated_weights[bridge_index]=0.0;water.set_shader_parameter("reflection_lamp_weights",isolated_weights)
	await _shot("bridge_scale_off","same_frame_selected_bridge_light_disabled")
	isolated_weights[bridge_index]=1.0;water.set_shader_parameter("reflection_lamp_weights",isolated_weights)
	await _shot("bridge_scale_unit","same_frame_selected_bridge_light_at_unit_scale")
	water.set_shader_parameter("reflection_lamp_weights",original_weights)
	world.call("update_time",720.0,"sunny",true)
	_point(farm.global_position+Vector3(8.2,-.15,14.8),farm.global_position+Vector3(5.5,1.45,10.8),false)
	water.set_shader_parameter("animation_time",10.0)
	water.set_shader_parameter("shallow_opacity",.34)
	await _shot("actual_creek_stones","production_geometry_stone_support_and_transparency")
	var sources: Array[Dictionary]=[]
	for path: String in ["res://shaders/lakeside_water.gdshader","res://shaders/water_motion.gdshaderinc","res://shaders/creek_stone.gdshader","res://scripts/world/lakeside_builder.gd","res://scripts/world/lakeside_materials.gd"]:
		sources.append({"file":path,"sha256":FileAccess.get_sha256(path)})
	for dependency: String in ["res://shaders/lakeside_water_surface.gdshaderinc","res://shaders/material_options/water.gdshader","res://scripts/world/material_choice_profile.gd"]:
		if FileAccess.file_exists(dependency):sources.append({"file":dependency,"sha256":FileAccess.get_sha256(dependency)})
	var serialized_lamps: Array[Array]=[]
	for position_value: Vector3 in lamp_positions:serialized_lamps.append(_vector(position_value))
	var report: Dictionary={"actual_shader":water.shader.resource_path,"schema_version":1,"scope":"native isolated water-shader diagnostic fixtures, not ordinary gameplay screenshots","engine":Engine.get_version_info(),"shots":rows,"sources":sources,"rain_view_height_metres":4.2,"actual_lamp_position":_vector(lamp_position),"moon_position":_vector(moon_position),"reflection_lamp_count":water.get_shader_parameter("reflection_lamp_count"),"reflection_lamps":serialized_lamps,"reflection_lamp_weights":original_weights,"bridge_lamp_position":_vector(bridge_position),"bridge_outdoor_energy_scale":bridge_weight}
	FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	(root.get_node("Audio") as Node).call("silence")
	quit(0)

func _point(target: Vector3,position: Vector3,top: bool) -> void:
	analysis_focus=target
	analysis_span=Vector2(3.0,3.0)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL if top else Camera3D.PROJECTION_PERSPECTIVE
	camera.global_position=position
	camera.look_at(target,Vector3.FORWARD if top else Vector3.UP)
	camera.force_update_transform()
	camera.reset_physics_interpolation()

func _vector(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func _shot(label: String,purpose: String) -> void:
	# Main is paused to isolate water pixels; refresh the passive panorama
	# explicitly so a night fixture does not carry its previous noon colour.
	for mountains: Node in world.find_children("DistantMountains","Node3D",true,false):mountains.call("_update_look")
	for settle: int in 3:await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	var path: String=output.path_join(label+".png")
	var error: Error=image.save_png(path)
	if error!=OK:printerr("Water probe PNG failed ",path);quit(4);return
	var logical: Vector2=root.get_visible_rect().size
	var png_scale:=Vector2(float(image.get_width())/logical.x,float(image.get_height())/logical.y)
	var quad: Array[Array]=[]
	for corner: Vector2 in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,1),Vector2(1,-1)]:
		var point: Vector3=analysis_focus+Vector3(corner.x*analysis_span.x,0,corner.y*analysis_span.y)
		var projected: Vector2=camera.unproject_position(point)*png_scale
		quad.append([projected.x,projected.y])
	rows.append({"file":label+".png","sha256":FileAccess.get_sha256(path),"purpose":purpose,"png_size_px":[image.get_width(),image.get_height()],"camera_position":_vector(camera.global_position),"camera_basis":[_vector(camera.global_basis.x),_vector(camera.global_basis.y),_vector(camera.global_basis.z)],"projection":camera.projection,"ortho_height_metres":camera.size if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else 0.0,"animation_time":water.get_shader_parameter("animation_time"),"monotonic_render_time_ms":Time.get_ticks_msec(),"analysis_water_quad_png_px":quad,"analysis_water_quad_world_center":_vector(analysis_focus),"analysis_water_quad_world_half_span":[analysis_span.x,analysis_span.y],"logical_viewport_units":[logical.x,logical.y],"png_px_per_viewport_unit":[png_scale.x,png_scale.y]})
	print("MATERIAL_WATER_PROBE ",label)
