extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool) -> void:t.check("FOLIAGE_LIB",label,ok)
func run() -> void:
	var tree: Node3D=main.world.get_node_or_null("T01_courtyard_tree")
	var stats: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/_stats/T01_courtyard_tree.json"))
	check("regular tree is the fitted CC0 source",str(stats.get("src","")).contains("free_foliage_20261004/ready"))
	var leaves: Array[MeshInstance3D]=[];var trunks: Array[MeshInstance3D]=[]
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(tree):
		if mesh.name.begins_with("Foliage"):leaves.append(mesh)
		if mesh.name.begins_with("Trunk"):trunks.append(mesh)
	check("tree crown and trunk remain distinct parts",not leaves.is_empty() and not trunks.is_empty())
	var alpha:=false;var roles:=true
	for mesh: MeshInstance3D in leaves:
		for surface in mesh.mesh.get_surface_count():
			var material:=mesh.get_surface_override_material(surface) as ShaderMaterial
			if material:
				var texture: Texture2D=material.get_shader_parameter("albedo_tex")
				alpha=alpha or (texture!=null and texture.get_image().detect_alpha()!=Image.ALPHA_NONE)
				roles=roles and int(material.get_shader_parameter("part_role"))==1
	check("tree leaf textures retain their alpha channel",alpha)
	check("foliage uses its own wind role",roles)
	var shader:=FileAccess.get_file_as_string("res://shaders/foliage_sway.gdshader")
	check("leaf cutouts are rendered with alpha scissor",shader.contains("ALPHA_SCISSOR_THRESHOLD"))
	check("new nature assets are available in the game",ResourceLoader.exists("res://assets/models/V01_fern.glb") and ResourceLoader.exists("res://assets/models/V02_wildflowers.glb") and ResourceLoader.exists("res://assets/models/V03_grass_clump.glb"))
	check("courtyard nature accents are actually placed",int(main.world.get_meta("nature_accent_count",0))>=12)
	var bounds:=WorldBuilder.local_aabb(tree)
	check("tree stays in the intended metre scale",bounds.size.y>6.2 and bounds.size.y<6.8)
	var textures_only:=true
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(tree):
		for surface in mesh.mesh.get_surface_count():
			var material:=mesh.get_surface_override_material(surface)
			if material is StandardMaterial3D:textures_only=textures_only and not material.normal_enabled and material.metallic==0.0
	check("CC0 tree has no inherited PBR maps",textures_only)
