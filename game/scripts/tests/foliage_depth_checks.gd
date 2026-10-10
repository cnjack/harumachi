extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void: t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void: t.check("FOLIAGE_DEPTH",label,ok,detail)

func run() -> void:
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/_stats/_foliage_depth.json"))
	var models: Dictionary=report.get("models",{})
	var fresh:=true
	for asset_id: String in ["T02_summer_tree","T03_round_ginkgo","T04_slender_cedar","T05_old_shade_tree"]:
		fresh=fresh and models.get(asset_id,{}).get("sha256","")==FileAccess.get_sha256("res://assets/models/%s.glb"%asset_id)
	check("all near-tree optical measurements match the actual exported meshes",fresh)
	var hero: Dictionary=models.get("T05_old_shade_tree",{})
	var light: float=float(hero.get("sunlight_transmission",0))
	check("old-tree foliage leaves scattered real sunlight paths",light>=.15 and light<=.65,str(light))
	var profile: float=float(hero.get("outer_crown_height_range_m",0))
	check("outer old-tree crown has distinct high and low shelves",profile>=1.2,str(profile))
	var hero_node: Node3D=main.world.get_node("T05_old_shade_tree") as Node3D
	var piles: Array[MeshInstance3D]=[]
	var pile_triangles:=0
	var follows_bark:=true
	for pile: MeshInstance3D in WorldBuilder.find_meshes(hero_node):
		if not pile.name.begins_with("Moss_"): continue
		piles.append(pile)
		for surface in pile.mesh.get_surface_count():
			var indices: PackedInt32Array=pile.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			pile_triangles+=int(indices.size()/3.0)
			var material:=pile.get_active_material(surface) as ShaderMaterial
			follows_bark=follows_bark and material!=null and int(material.get_shader_parameter("part_role"))==0 and float(material.get_shader_parameter("height"))>6.0 and material.get_shader_parameter("albedo_tex")!=null
	piles.sort_custom(func(a: MeshInstance3D,b: MeshInstance3D): return str(a.name)<str(b.name))
	var relief: float=0.0
	if piles.size()>1: relief=piles[0].mesh.get_aabb().size.distance_to(piles[-1].mesh.get_aabb().size)
	check("moss is a fine raised pile that moves with the bark",piles.size()>=8 and pile_triangles>20000 and relief>.015 and relief<.12 and follows_bark,JSON.stringify({"layers":piles.size(),"triangles":pile_triangles,"layer_extent_m":relief}))
	var cedar: Dictionary=models.get("T04_slender_cedar",{})
	check("cedar uses small needle sprays down its lower boughs",float(cedar.get("max_leaf_triangle_edge_m",99))<1.3 and float(cedar.get("foliage_height_min_m",99))<3.0,JSON.stringify(cedar.duplicate().get("max_leaf_triangle_edge_m")))
	var terrain: Array=main.world.find_children("FarMeadow_*","MeshInstance3D",false,false)
	var painted: bool=terrain.size()==4
	for tile: MeshInstance3D in terrain:
		var material:=tile.material_override as ShaderMaterial
		painted=painted and material!=null and material.shader.resource_path.ends_with("distant_meadow.gdshader")
	check("every outer ground quadrant carries the meadow material",painted)
	var rise: MeshInstance3D=main.world.get_node_or_null("BackgroundMeadowRise") as MeshInstance3D
	var supported: bool=rise!=null
	var ground_samples: Array=[]
	if rise:
		var space: PhysicsDirectSpaceState3D=main.world.get_world_3d().direct_space_state
		var faces: PackedVector3Array=rise.mesh.get_faces()
		for point: Vector2 in [Vector2(65,31),Vector2(82,47),Vector2(102,58)]:
			var top:=Vector3(point.x,10,point.y)
			var bottom:=Vector3(point.x,-2,point.y)
			var query:=PhysicsRayQueryParameters3D.create(top,bottom,WorldBuilder.L_GROUND)
			var hit: Dictionary=space.intersect_ray(query)
			var rendered: float=-INF
			for triangle in range(0,faces.size(),3):
				var crossing: Variant=Geometry3D.segment_intersects_triangle(top,bottom,rise.to_global(faces[triangle]),rise.to_global(faces[triangle+1]),rise.to_global(faces[triangle+2]))
				if crossing!=null: rendered=maxf(rendered,(crossing as Vector3).y)
			var physical: float=(hit.get("position",Vector3(0,-INF,0)) as Vector3).y
			supported=supported and rendered>.08 and absf(physical-rendered)<.006
			ground_samples.append({"rendered":rendered,"collision":physical})
	check("the visible background rise has actual ground collision",supported,JSON.stringify(ground_samples))
	var meadow: Node=main.world.get_node_or_null("BackgroundMeadow")
	var shrubs: Node=main.world.get_node_or_null("BackgroundShrubGroups")
	var clumps:=0
	var clear:=true
	if meadow:
		for instance: MultiMeshInstance3D in meadow.find_children("*","MultiMeshInstance3D",false,false):
			clumps+=instance.multimesh.instance_count
	if shrubs:
		for plant: Node3D in shrubs.get_children():
			var bounds: AABB=plant.global_transform*WorldBuilder.local_aabb(plant)
			var footprint:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
			clear=clear and not footprint.intersects(WorldBuilder.EXIT_CUT.grow(.5))
	check("outer meadow has physical vegetation without covering the allotment lane",meadow!=null and shrubs!=null and clumps>2500 and shrubs.get_child_count()>60 and clear,str(clumps))
