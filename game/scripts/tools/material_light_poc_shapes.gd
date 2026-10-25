extends RefCounted
## Authored candidates are shared; source meshes and all collision nodes remain restorable.
const IDS: Array[String] = ["T01_courtyard_tree","T02_summer_tree","T03_round_ginkgo","T04_slender_cedar"]
const FOLDER: String = "res://assets/material_light_poc/shape/"
var bindings: Array[Dictionary] = []
var report: Dictionary = {}
var enabled: bool = false
var leaf_materials: Dictionary = {}
var grass_material: ShaderMaterial
var architecture: Node3D
var source_building_body: MeshInstance3D
var source_body_visible: bool = true
var architecture_bindings: Array[Dictionary] = []
var finish_materials: Array[ShaderMaterial] = []

func prepare(world: WorldBuilder, owner: Node) -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"config.json"))
	var candidates: Dictionary = {}
	var inner_vertices: int = 0
	for id: String in IDS:
		var source: Node3D = (load(FOLDER+id+".glb") as PackedScene).instantiate() as Node3D
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(source):
			assert(mesh.transform.is_equal_approx(Transform3D.IDENTITY))
			if str(mesh.name).begins_with("Foliage"):
				candidates[id] = mesh.mesh
				if int(config.iteration)>=7:
					var arrays: Array = mesh.mesh.surface_get_arrays(0)
					var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					var core_count: int = 0
					for uv: Vector2 in coordinates:
						if uv.x<-.5:core_count+=1
					assert(core_count>100,"Tree LOD needs an exported, independently tagged inner crown")
					inner_vertices+=core_count
		source.free()
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = preload("res://shaders/material_poc_leaf.gdshader")
		material.set_shader_parameter("albedo_tex", load(FOLDER+"cedar_atlas.png" if id.begins_with("T04") else FOLDER+"leaf_atlas.png"))
		material.set_shader_parameter("height",(candidates[id] as Mesh).get_aabb().end.y)
		leaf_materials[id] = material
	var grass_candidates: Dictionary = {}
	var grass_root: Node3D = (load(FOLDER+"Grass_curved.glb") as PackedScene).instantiate() as Node3D
	var roots_checked: int = 0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(grass_root):
		grass_candidates[str(mesh.name)] = mesh.mesh
		if int(config.iteration) >= 6:
			var arrays: Array = mesh.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for index: int in vertices.size():
				if vertices[index].y < .0001:
					assert(absf(uvs[index].y) < .0001, "Grass roots must have zero wind weight after glTF conversion")
					roots_checked += 1
	grass_root.free()
	grass_material = ShaderMaterial.new()
	grass_material.shader = preload("res://shaders/material_poc_grass.gdshader")
	var trees: int = 0
	var grass: int = 0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(world):
		if not str(mesh.name).begins_with("Foliage"): continue
		var ancestor: Node = mesh
		var id: String = ""
		while ancestor != null and ancestor != world:
			id = str(ancestor.get_meta("model_id", ""))
			if id in IDS: break
			ancestor = ancestor.get_parent()
		if not id in IDS: continue
		bindings.append({"node":mesh,"original":mesh.mesh,"candidate":candidates[id],"material":leaf_materials[id],"original_override":mesh.material_override})
		trees += 1
	for node: Node in world.get_tree().current_scene.find_children("*","MultiMeshInstance3D",true,false):
		var multi: MultiMeshInstance3D = node as MultiMeshInstance3D
		var id: String = str(multi.get_meta("library_id",""))
		if multi.get_meta("landscape_tree",false) and id in IDS:
			var original: ShaderMaterial = multi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
			if original != null and int(original.get_shader_parameter("part_role")) == 1:
				bindings.append({"node":multi,"original":multi.multimesh.mesh,"candidate":candidates[id],"material":leaf_materials[id],"original_override":multi.material_override})
				trees += multi.multimesh.instance_count
		elif multi.has_meta("grass_style"):
			var style: String = str(multi.get_meta("grass_style"))
			var key: String = "Grass_%s_%d" % [style,grass%3]
			assert(grass_candidates.has(key))
			bindings.append({"node":multi,"original":multi.multimesh.mesh,"candidate":grass_candidates[key],"material":grass_material,"original_override":multi.material_override})
			var grass_binding: Dictionary = bindings[-1]
			grass_binding["original_shadow"] = multi.cast_shadow
			grass_binding["candidate_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key.ends_with("_2") and str(multi.get_path()).contains("POC_LakesideGrass") and multi.multimesh.get_aabb().get_center().distance_to(Vector3(94,0,44))<17.0 else multi.cast_shadow
			grass += 1
	for binding: Dictionary in bindings:
		binding["transform"] = (binding.node as Node3D).global_transform
		if binding.node is MultiMeshInstance3D: binding["buffer_hash"] = hash((binding.node as MultiMeshInstance3D).multimesh.buffer)
	report = {"iteration":config.iteration,"tree_instances":trees,"grass_batches":grass,"mesh_bindings":bindings.size(),"grass_root_vertices_checked":roots_checked,"inner_crown_vertices_checked":inner_vertices,"source_assets":"art/library/material_shape_poc_20261025/authoring","original_collisions":"retained"}
	report["architecture_active"] = bool(config.architecture)
	report["bakery_source_sha256"] = FileAccess.get_sha256("res://assets/models/S02.glb")
	if bool(config.architecture): _prepare_architecture(world,owner)
	var hashes: Dictionary = {}
	for id: String in IDS: hashes[id+".glb"] = FileAccess.get_sha256(FOLDER+id+".glb")
	for file: String in ["Grass_curved.glb","S02_refined.glb","leaf_atlas.png","cedar_atlas.png"]:
		if FileAccess.file_exists(FOLDER+file):hashes[file] = FileAccess.get_sha256(FOLDER+file)
	report["asset_sha256"] = hashes
	var mipmaps: Dictionary = {}
	for file: String in ["leaf_atlas.png","cedar_atlas.png"]:
		var texture: Texture2D = load(FOLDER+file) as Texture2D
		var picture: Image = texture.get_image()
		assert(picture != null and picture.has_mipmaps(),"3D foliage needs an imported mip chain")
		mipmaps[file] = picture.get_mipmap_count()
		hashes[file+".import"] = FileAccess.get_sha256(FOLDER+file+".import")
	report["atlas_mipmap_levels"] = mipmaps
	report["leaf_shader_sha256"] = (leaf_materials[IDS[0]] as ShaderMaterial).shader.code.sha256_text()
	report["grass_shader_sha256"] = grass_material.shader.code.sha256_text()
	report["meadow_include_sha256"] = FileAccess.get_sha256("res://shaders/material_poc_meadow.gdshaderinc")
	report["grass_shadow_batches"] = bindings.filter(func(item: Dictionary) -> bool:return item.has("candidate_shadow") and item.candidate_shadow != item.original_shadow).size()

func swap_meshes(value: bool) -> void:
	enabled = value
	for binding: Dictionary in bindings:
		if binding.has("original_shadow"): (binding.node as GeometryInstance3D).cast_shadow = binding.candidate_shadow if value else binding.original_shadow
		var mesh: Mesh = binding.candidate if value else binding.original
		if binding.node is MultiMeshInstance3D: (binding.node as MultiMeshInstance3D).multimesh.mesh = mesh
		else: (binding.node as MeshInstance3D).mesh = mesh

func apply(value: bool, condition: Dictionary, region: String) -> void:
	var night: bool = condition.id == "night"
	swap_meshes(value)
	if architecture:
		architecture.visible = value and region == "town"
		source_building_body.visible = source_body_visible and not value
		for binding: Dictionary in architecture_bindings:
			(binding.node as MeshInstance3D).set_surface_override_material(binding.surface,source_building_body.get_active_material(binding.source))
		for material: ShaderMaterial in finish_materials:
			material.set_shader_parameter("poc_night",1.0 if night else 0.0)
			material.set_shader_parameter("sky_storm",.9 if condition.weather == "rain" else (.6 if condition.weather == "cloudy" else 0.))
			material.set_shader_parameter("reflected_sky",load("res://assets/material_light_poc/sky_%s.png" % ("night" if night else ("dusk" if condition.id=="sunset" else "day"))))
	if not value:
		for binding: Dictionary in bindings:
			if binding.material != null: (binding.node as GeometryInstance3D).material_override = binding.original_override
		return
	for material: ShaderMaterial in leaf_materials.values(): material.set_shader_parameter("poc_night",1.0 if night else 0.0)
	grass_material.set_shader_parameter("poc_night",1.0 if night else 0.0)
	for binding: Dictionary in bindings:
		if binding.material != null: (binding.node as GeometryInstance3D).material_override = binding.material

func source_signature(world: WorldBuilder, bridge: RefCounted) -> String:
	var active: bool = enabled
	for binding: Dictionary in bindings:
		var live_mesh: Mesh = (binding.node as MultiMeshInstance3D).multimesh.mesh if binding.node is MultiMeshInstance3D else (binding.node as MeshInstance3D).mesh
		assert(live_mesh == (binding.candidate if active else binding.original),"Candidate mesh was replaced during rendering")
	swap_meshes(false)
	for binding: Dictionary in bindings:
		assert((binding.node as Node3D).global_transform.is_equal_approx(binding.transform), "Candidate must retain its placement")
		if binding.node is MultiMeshInstance3D:
			var multi: MultiMeshInstance3D = binding.node as MultiMeshInstance3D
			assert(multi.multimesh.mesh == binding.original)
			assert(hash(multi.multimesh.buffer) == int(binding.buffer_hash), "Candidate must retain original instance transforms and data")
		else: assert((binding.node as MeshInstance3D).mesh == binding.original)
	var result: String = bridge.source_signature(world)
	swap_meshes(active)
	return result

func _prepare_architecture(world: WorldBuilder, owner: Node) -> void:
	var source_building: Node3D = world.get_node("S02") as Node3D
	source_building_body = WorldBuilder.find_meshes(source_building).filter(func(mesh: MeshInstance3D) -> bool: return str(mesh.name) == "Rodin_S02_body")[0] as MeshInstance3D
	source_body_visible = source_building_body.visible
	architecture = Node3D.new()
	architecture.name = "POC_BakerySourceCandidate"
	owner.add_child(architecture)
	architecture.global_transform = source_building.global_transform
	# Reuse the normal spawn entry and semantic model marker for the source candidate.
	var display: Node3D = world.spawn("S02",Vector3.ZERO,0.0,0,architecture)
	var display_body: MeshInstance3D = WorldBuilder.find_meshes(display)[0]
	var source_slots: Dictionary = {}
	for index: int in source_building_body.mesh.get_surface_count(): source_slots[source_building_body.mesh.surface_get_material(index).resource_name] = index
	var packed: Node3D = (load(FOLDER+"S02_refined.glb") as PackedScene).instantiate() as Node3D
	var added: int = 0
	for part: MeshInstance3D in WorldBuilder.find_meshes(packed):
		var node: MeshInstance3D
		if str(part.name) == "Rodin_S02_body": node = display_body
		else:
			node = MeshInstance3D.new()
			node.name = part.name
			display.add_child(node)
			added += 1
		node.mesh = part.mesh
		node.transform = part.transform
		for index: int in node.mesh.get_surface_count():
			var source_material: StandardMaterial3D = node.mesh.surface_get_material(index) as StandardMaterial3D
			var title: String = source_material.resource_name
			if source_slots.has(title):
				architecture_bindings.append({"node":node,"surface":index,"source":source_slots[title]})
				node.set_surface_override_material(index,source_building_body.get_active_material(int(source_slots[title])))
			else:
				assert(title.begins_with("POC_"),"Unexpected source material: "+title)
				var finish: ShaderMaterial = ShaderMaterial.new()
				finish.shader = preload("res://shaders/material_poc_joinery.gdshader")
				finish.set_shader_parameter("base_colour",source_material.albedo_color)
				finish.set_shader_parameter("material_kind",3 if title == "POC_UpperGlass" else (2 if title == "POC_Canvas" else (1 if title == "POC_Timber" else 0)))
				node.set_surface_override_material(index,finish)
				finish_materials.append(finish)
	packed.free()
	architecture.visible = false
	report["architecture_added_parts"] = added
	report["architecture_material_bindings"] = architecture_bindings.size()
