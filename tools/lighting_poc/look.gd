extends Node
## Review-only look. Copied into a disposable project by run.py; never autoloaded.
var world: Node3D
var materials_seen: Dictionary = {}
var shaders: Dictionary = {}
var changed_materials := 0

func _ready() -> void:
	process_priority = 100

func _process(_delta: float) -> void:
	apply()

func apply() -> void:
	if not is_instance_valid(world): return
	var env: Environment = world.get("env") as Environment
	var sun: DirectionalLight3D = world.get("sun") as DirectionalLight3D
	var look: Dictionary = world.get("look") as Dictionary
	if env == null or look.is_empty(): return
	var inside: bool = bool(world.get("indoor"))
	var night: float = clampf(float(look.night), 0.0, 1.0)
	var dusk: float = clampf(float(look.dusk), 0.0, 1.0)
	# Derive values from the unmodified clock palette, never multiply last frame's output.
	if inside:
		var state: Node = get_tree().root.get_node("GameState")
		var minute: float = float(state.get("minute"))
		var evening: bool = minute >= 990.0 or minute < 378.0 or str(state.get("phase")) == "market"
		var weather: String = str(state.get("weather"))
		var direct: float = 0.0 if weather == "rain" else (.30 if weather == "cloudy" else 1.0)
		sun.light_energy = (1.4 if evening else 1.62) * lerpf(1.0, .05, night) * direct * 1.04
		env.ambient_light_energy = (.42 if evening else .58) * lerpf(1.0, .6, night) * .77
		env.ambient_light_sky_contribution = .40
		env.ambient_light_color = Color(.72, .76, .96)
		env.adjustment_saturation = (1.14 if evening else 1.1) + (0.0 if weather == "sunny" else (-.1 if weather == "cloudy" else -.2)) * .5
		env.glow_bloom = .025
	else:
		sun.light_energy = float(look.sun) * lerpf(1.0, .92, night)
		env.ambient_light_energy = float(look.amb) * lerpf(.77, .88, night)
		env.ambient_light_sky_contribution = lerpf(.58, .82, night)
		env.ambient_light_color = Color(.72, .79, 1.0).lerp(Color(.60, .64, .88), night)
		env.adjustment_saturation = float(look.sat) * .975
		env.fog_depth_begin = 95.0 * clampf(.0035 / maxf(float(look.fog_d), .0035), .55, 1.0)
		env.fog_depth_end = 215.0
		env.fog_depth_curve = 1.45
		env.fog_density = .88
		env.fog_light_color = (look.fog as Color) * .92
		env.glow_bloom = .02
	env.tonemap_exposure = 1.0
	env.adjustment_contrast = lerpf(1.065, 1.04, night)
	env.glow_intensity = lerpf(.34, .43, maxf(dusk, night))
	env.glow_hdr_threshold = 1.28
	# Keep 4096 shadows, half-resolution low SSAO and the existing effect count.
	env.ssao_radius = .65
	env.ssao_intensity = 1.05
	sun.directional_shadow_split_1 = .08
	sun.directional_shadow_split_2 = .22
	sun.directional_shadow_split_3 = .55
	sun.shadow_blur = 1.0

func install_materials() -> void:
	for node: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		_edit_material(geometry.material_override)
		if geometry is MeshInstance3D:
			var mesh_node: MeshInstance3D = geometry as MeshInstance3D
			if mesh_node.mesh != null:
				for surface: int in mesh_node.mesh.get_surface_count(): _edit_material(mesh_node.get_active_material(surface))
		elif geometry is MultiMeshInstance3D:
			var batch: MultiMeshInstance3D = geometry as MultiMeshInstance3D
			if batch.multimesh != null and batch.multimesh.mesh != null:
				for surface: int in batch.multimesh.mesh.get_surface_count(): _edit_material(batch.multimesh.mesh.surface_get_material(surface))

func _edit_material(material: Material) -> void:
	if not material is ShaderMaterial or materials_seen.has(material.get_instance_id()): return
	materials_seen[material.get_instance_id()] = true
	var sm: ShaderMaterial = material as ShaderMaterial
	if sm.shader == null: return
	var path: String = sm.shader.resource_path
	if path.ends_with("house_wall.gdshader") or path.ends_with("house_floor.gdshader") or path.ends_with("house_rug.gdshader"):
		sm.set_shader_parameter("shadow_fill", .10)
		changed_materials += 1
	elif path.ends_with("foliage_sway.gdshader") or path.ends_with("grass_blade.gdshader"):
		if not shaders.has(path):
			var code: String = sm.shader.code
			var old: String = "vec4(0,1,0,0)).xyz,.45)" if path.ends_with("foliage_sway.gdshader") else "NORMAL, 0.12)"
			var replacement: String = "vec4(0,1,0,0)).xyz,.24)" if path.ends_with("foliage_sway.gdshader") else "NORMAL, 0.20)"
			assert(code.contains(old), "POC shader source changed; review the edit before recording")
			var shader := Shader.new()
			shader.code = code.replace(old, replacement)
			shaders[path] = shader
		sm.shader = shaders[path] as Shader
		changed_materials += 1

func snapshot() -> Dictionary:
	var env: Environment = world.get("env") as Environment
	var sun: DirectionalLight3D = world.get("sun") as DirectionalLight3D
	return {"ambient": env.ambient_light_energy, "sun": sun.light_energy, "contrast": env.adjustment_contrast,
		"glow": env.glow_intensity, "bloom": env.glow_bloom, "ssao_radius": env.ssao_radius,
		"fog_begin": env.fog_depth_begin, "fog_end": env.fog_depth_end, "changed_materials": changed_materials}
