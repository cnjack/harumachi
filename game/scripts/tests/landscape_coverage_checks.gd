extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool) -> void:t.check("LANDSCAPE",label,ok)
func run() -> void:
	check("follow camera clips unseen distance",main.rig.cam.far<=220.0)
	check("photo camera uses same distance",main.photo.camera.far<=220.0 if "photo" in main else false)
	check("distance haze fully hides geometry before clipping",main.world.env.fog_mode==Environment.FOG_MODE_DEPTH and main.world.env.fog_density==1.0 and main.world.env.fog_depth_end<main.rig.cam.far)
	for region: String in ["town","farm"]:
		var parent: Node=main.world if region=="town" else main.world.farm
		var landscape: Node=parent.get_node_or_null("LandscapeCoverage")
		check(region+" has continuous outer terrain",landscape!=null and landscape.has_node("Terrain"))
		check(region+" has layered real tree coverage",landscape!=null and int(landscape.get_meta("tree_count",0))>=250)
		check(region+" uses every recommended vegetation kind",landscape!=null and int(landscape.get_meta("plant_varieties",0))>=10)
	var flat_cards:=0
	for node: Node in main.world.farm.find_children("*","MeshInstance3D",true,false):
		if str(node.get_meta("backdrop_tex","")).begins_with("bg_tree"):flat_cards+=1
	check("farm tree horizon no longer depends on flat tree walls",flat_cards==0)
	for id: String in ["V06_fine_grass","V07_grass_card","V08_blade_rosette","V09_fern_cluster","V10_leaf_shrub","V11_fallen_leaf","V12_tulip","V13_pampas","V14_broad_grass","V15_wheat_stem","P_library_carton","P_library_bucket","P_library_stool","V16_path_pebble","V17_path_pebble","V18_path_pebble","V19_distant_cliff"]:
		check(id+" exported",ResourceLoader.exists("res://assets/models/"+id+".glb"))
	var alpha_ok:=true
	var vertices_ok:=true
	for id: String in LandscapeCoverage.PLANTS:
		var scene: PackedScene=WorldBuilder.model_scene(id)
		if scene==null:alpha_ok=false;continue
		var model: Node3D=scene.instantiate();main.add_child(model)
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
			for surface in mesh.mesh.get_surface_count():
				var material:=mesh.get_active_material(surface) as StandardMaterial3D
				if material==null or material.albedo_texture==null:alpha_ok=false;continue
				var image: Image=material.albedo_texture.get_image()
				alpha_ok=alpha_ok and image.detect_alpha()!=Image.ALPHA_NONE
				var box: AABB=mesh.mesh.get_aabb()
				vertices_ok=vertices_ok and box.size.length()<5.0 and box.position.y>=-.04
		model.free()
	check("all foliage masks are true alpha textures rather than opaque JPEG cards",alpha_ok)
	check("library plants have grounded metre-scale geometry",vertices_ok)
	var installed:=true
	for parent: Node in [main.world,main.world.farm]:
		var root: Node=parent.get_node_or_null("ReviewedLibrary")
		installed=installed and root!=null
		if root:
			var expected: Array[String] = ["P_library_stool"]
			if parent == main.world.farm: expected.assign(["P_library_carton","P_library_bucket","P_library_stool"])
			for id: String in expected:
				var model: Node3D=root.get_node_or_null(id)
				installed=installed and model!=null and model.has_meta("library_finish")
	installed=installed and not main.world.has_node("ReviewedLibrary/P_library_carton") and not main.world.has_node("ReviewedLibrary/P_library_bucket")
	check("reviewed work props have specific uses instead of duplicate material display kits",installed)
	var packed_cloth: Node3D=main.world.farm.get_node_or_null("ReviewedLibrary/PicnicCloth")
	check("reviewed plaid cloth remains packed until a real picnic invitation exists",packed_cloth!=null and not packed_cloth.visible and packed_cloth is MeshInstance3D and packed_cloth.material_override is ShaderMaterial)
	check("garden ground extends beyond the free-photo horizon",main.world.house.has_node("GardenTreeCoverage"))
	var terrain_covered:=true
	var rooted:=true
	var actual_instances:=0
	for farm: bool in [false,true]:
		var parent: Node3D=main.world.farm if farm else main.world
		var coverage: Node3D=parent.get_node("LandscapeCoverage")
		for point: Vector2 in ([Vector2(-62,-55),Vector2(160,-55),Vector2(165,95),Vector2(-55,95),Vector2(210,60),Vector2(65,150)] if farm else [Vector2(-100,-50),Vector2(120,-60),Vector2(115,115),Vector2(-95,120),Vector2(25,170),Vector2(-190,15)]):
			var global_point:=Vector2(parent.global_position.x+point.x,parent.global_position.z+point.y)
			var rendered: float=WorldBuilder.surface_height(coverage,global_point,100.0,true)
			terrain_covered=terrain_covered and is_finite(rendered) and absf(rendered-LandscapeCoverage.height_at(point,farm))<.01
		var unique: Dictionary={}
		for node: Node in coverage.get_children():
			if not node is MultiMeshInstance3D or not node.get_meta("landscape_tree",false):continue
			for index in node.multimesh.instance_count:
				var part: Transform3D=node.get_meta("part_transform")
				var submitted: Array=node.get_meta("submitted_transforms")
				var placement: Transform3D=submitted[index] if DisplayServer.get_name()=="headless" else node.multimesh.get_instance_transform(index)*part.affine_inverse()
				var origin: Vector3=placement.origin
				var key: Vector2=Vector2(origin.x,origin.z)
				unique[key]=true
				rooted=rooted and absf(origin.y-LandscapeCoverage.height_at(key,farm)+.02)<.02
		actual_instances+=unique.size()
	check("rendered outer terrain matches sampled supports on every side",terrain_covered)
	check("tree batch roots follow rendered terrain (native run also reads renderer transforms)",rooted)
	check("both maps submit complete tree transforms, not count-only metadata",actual_instances>=1000)
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/reviewed_library.json"))
	var isolated:=true
	for asset: Dictionary in manifest.assets:
		var stats: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/_stats/"+str(asset.id)+".json"))
		isolated=isolated and int(stats.get("tris",9999999))<=int(asset.base_triangles)+2
	check("each export contains only its intended asset, never earlier selected objects",isolated)
	check("placement camera shares the clipped horizon",main.placement.cam.far==LandscapeCoverage.FAR)
	var road: MeshInstance3D=main.world.get_node("IncomingRoad")
	check("incoming road continues beyond every town photo view",(road.global_transform*road.get_aabb()).position.x<LandscapeCoverage.TOWN_PHOTO.position.x-LandscapeCoverage.FAR)
	var water: MeshInstance3D=main.world.farm.lakeside.get_node("Connected_lake_and_river")
	check("river surface continues beyond the farm horizon",water.get_aabb().position.x<LandscapeCoverage.FARM_PHOTO.position.x-LandscapeCoverage.FAR)
	main.world.set_indoor_look(true)
	var original_fog: bool=main.world.env.fog_enabled
	main.photo.toggle()
	var photo_fog: bool=main.photo.active and main.world.env.fog_enabled
	main.photo.finish()
	check("indoor free photo hides its far clipping edge and restores the room haze",photo_fog and main.world.env.fog_enabled==original_fog)
	main.world.set_indoor_look(false)
