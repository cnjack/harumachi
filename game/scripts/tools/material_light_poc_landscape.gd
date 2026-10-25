extends RefCounted
## Reversible crown normals / paint plus local, collision-free grass for this study.
var bindings: Array[Dictionary] = []
var extras: Node3D
var clumps: int = 0
var ground_shaders: Dictionary = {}
const FOLIAGE: Shader = preload("res://shaders/material_poc_foliage.gdshader")

func prepare(world: WorldBuilder, owner: Node) -> void:
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(world):
		if mesh.mesh == null: continue
		var slots: Array[int] = []
		if mesh.material_override: slots.append(-1)
		if slots.is_empty():
			for index: int in range(mesh.mesh.get_surface_count()): slots.append(index)
		for index: int in slots:
			var source: ShaderMaterial = (mesh.material_override if index == -1 else mesh.get_active_material(index)) as ShaderMaterial
			if source == null: continue
			var material: ShaderMaterial
			var path: String = source.shader.resource_path
			var tree: bool = false
			var ancestor: Node = mesh
			while ancestor != world and ancestor != null:
				if str(ancestor.get_meta("wind_model_id",ancestor.get_meta("model_id",""))).begins_with("T0"): tree = true
				ancestor = ancestor.get_parent()
			var role: int = int(source.get_shader_parameter("part_role")) if path.ends_with("foliage_sway.gdshader") else -1
			if path.ends_with("foliage_sway.gdshader") and (role == 1 or (tree and role == 2)):
				material = source.duplicate() as ShaderMaterial
				material.shader = FOLIAGE
				var bounds: AABB = mesh.mesh.get_aabb()
				material.set_shader_parameter("crown_center", bounds.get_center())
				material.set_shader_parameter("crown_radius", bounds.size * .5)
				material.set_shader_parameter("mixed_tree", role == 2)
			elif path.ends_with("distant_meadow.gdshader") or (path.ends_with("material_options/surface.gdshader") and str(world.get_path_to(mesh)).begins_with("Farm/Lakeside/")):
				material = source.duplicate() as ShaderMaterial
				material.shader = _ground(path)
			if material:
				bindings.append({"mesh":mesh,"index":index,"original":mesh.material_override if index == -1 else mesh.get_surface_override_material(index),"candidate":material})
	# Separate from WorldBuilder: the original meshes and collisions remain inspectable.
	extras = Node3D.new()
	extras.name = "POC_LakesideGrass"
	owner.add_child(extras)
	extras.position = FarmBuilder.ORIGIN
	var grass: GrassField = GrassField.new()
	extras.add_child(grass)
	var keep: Callable = func(p: Vector2) -> bool: return LakesideLayout.water_distance(p) > .85 and LakesideLayout.path_distance(p) > 1.4 and not (absf(p.x-94.)<2.05 and p.y>35. and p.y<49.)
	var height_at: Callable = func(p: Vector2) -> float: return LakesideLayout.height_at(p)
	clumps = grass.lawn([[78,28,118,57]],[],"lawn",9.3,20261025,0.,height_at,keep)
	for node: Node in owner.get_tree().current_scene.find_children("*","MultiMeshInstance3D",true,false):
		var multi: MultiMeshInstance3D = node as MultiMeshInstance3D
		if multi.get_meta("landscape_tree",false) and multi.multimesh.mesh.get_surface_count() == 1:
			var tree_source: ShaderMaterial = multi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
			if tree_source and int(tree_source.get_shader_parameter("part_role")) == 1:
				var canopy: ShaderMaterial = tree_source.duplicate() as ShaderMaterial
				canopy.shader = FOLIAGE
				var tree_bounds: AABB = multi.multimesh.mesh.get_aabb()
				canopy.set_shader_parameter("crown_center",tree_bounds.get_center())
				canopy.set_shader_parameter("crown_radius",tree_bounds.size*.5)
				bindings.append({"mesh":multi,"index":-1,"original":multi.material_override,"candidate":canopy})
		if not multi.material_override is ShaderMaterial: continue
		var source: ShaderMaterial = multi.material_override as ShaderMaterial
		var grass_path: String = source.shader.resource_path
		if not grass_path.ends_with("grass_blade.gdshader") and not grass_path.ends_with("material_options/grass.gdshader"): continue
		var painted: ShaderMaterial = source.duplicate() as ShaderMaterial
		if not ground_shaders.has(grass_path):
			var blade_code: String = FileAccess.get_file_as_string(source.shader.resource_path)
			blade_code = blade_code.replace("void vertex()", "uniform float poc_night=0.;\nvoid vertex()")
			blade_code = blade_code.replace("ALBEDO = c * brightness;", "ALBEDO = c * brightness * mix(vec3(1),vec3(.65,.72,1.10),poc_night);")
			blade_code = blade_code.replace("ALBEDO = color*brightness;", "ALBEDO = color*brightness * mix(vec3(1),vec3(.65,.72,1.10),poc_night);")
			blade_code = blade_code.replace("vec3(0.28, 0.34, 0.12)","vec3(0.055, 0.075, 0.025)")
			blade_code = blade_code.replace("vec3(0.09, 0.10, 0.05)","vec3(0.025, 0.032, 0.009)")
			var blade_shader: Shader = Shader.new()
			blade_shader.code = blade_code
			ground_shaders[grass_path] = blade_shader
		painted.shader = ground_shaders[grass_path] as Shader
		if grass_path.ends_with("grass_blade.gdshader"):
			painted.set_shader_parameter("root_col",Color(.22,.38,.23))
			painted.set_shader_parameter("fresh_col",Color(.58,.73,.28))
			painted.set_shader_parameter("deep_col",Color(.27,.47,.28))
			painted.set_shader_parameter("dry_amount",.035)
		bindings.append({"mesh":multi,"index":-1,"original":source,"candidate":painted})
	extras.visible = false

func _ground(path: String) -> Shader:
	if ground_shaders.has(path): return ground_shaders[path] as Shader
	var code: String = FileAccess.get_file_as_string(path)
	if path.ends_with("distant_meadow.gdshader"):
		code = code.replace("varying vec3 meadow_world;","#include \"res://shaders/material_poc_meadow.gdshaderinc\"\nvarying vec3 meadow_world;")
		code = code.replace("meadow_colour(meadow_world.xz)","poc_meadow(meadow_world.xz)")
	else:
		code = code.replace("varying vec3 wp;","#include \"res://shaders/meadow_colour.gdshaderinc\"\n#include \"res://shaders/material_poc_meadow.gdshaderinc\"\nvarying vec3 wp;")
		code = code.replace("if(landscape_contours){", "if(surface_kind==4)col=poc_meadow(p);\n if(landscape_contours){")
	var shader: Shader = Shader.new()
	shader.code = code
	ground_shaders[path] = shader
	return shader

func apply(enabled: bool, region: String, night: bool = false) -> void:
	for binding: Dictionary in bindings:
		(binding.candidate as ShaderMaterial).set_shader_parameter("poc_night",1.0 if night else 0.0)
		var material: Material = binding.candidate if enabled else binding.original
		if int(binding.index) == -1: (binding.mesh as GeometryInstance3D).material_override = material
		else: (binding.mesh as MeshInstance3D).set_surface_override_material(binding.index, material)
	extras.visible = enabled and region == "farm"
