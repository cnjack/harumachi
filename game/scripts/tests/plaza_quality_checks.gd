extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void: t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void: t.check("PLAZA_QUALITY",label,ok,detail)

func roof_coverage(pergola: Node3D) -> float:
	var triangles:=PackedVector3Array()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(pergola):
		if mesh.name.begins_with("Foliage"): continue
		var local: Transform3D=pergola.global_transform.affine_inverse()*mesh.global_transform
		var vertices: PackedVector3Array=mesh.mesh.get_faces()
		for index in range(0,vertices.size(),3):
			var a: Vector3=local*vertices[index]
			var b: Vector3=local*vertices[index+1]
			var c: Vector3=local*vertices[index+2]
			if maxf(a.y,maxf(b.y,c.y))<2.65: continue
			triangles.append_array(PackedVector3Array([a,b,c]))
	var hits:=0
	for row in 11:
		for col in 11:
			var a:=Vector3(-1.45+col*.29,3.6,-1.45+row*.29)
			var b:=a-Vector3(0,1.0,0)
			for index in range(0,triangles.size(),3):
				var result: Variant=Geometry3D.segment_intersects_triangle(a,b,triangles[index],triangles[index+1],triangles[index+2])
				if result!=null:
					hits+=1;break
	return float(hits)/121.0

func run() -> void:
	var world: WorldBuilder=main.world
	var pergola:=world.get_node("P01") as Node3D
	var coverage: float=roof_coverage(pergola)
	check("pergola has real timber roof openings",coverage>.12 and coverage<.70,str(coverage))
	check("grape foliage is separate from load bearing timber",pergola.find_children("Foliage*","MeshInstance3D",true,false).size()>0)
	var drum: Node3D=world.taiko_drum
	var drum_materials: Dictionary={}
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(drum):
		for surface in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_active_material(surface)
			if material!=null: drum_materials[material.get_instance_id()]=true
	check("drum hide shell studs and stand have independent materials",drum_materials.size()>=4,str(drum_materials.size()))
	var transparent_water:=false
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(world.goldfish_tank):
		for surface in mesh.mesh.get_surface_count():
			var material:=mesh.get_active_material(surface) as StandardMaterial3D
			if material!=null and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a<.75: transparent_water=true
	check("goldfish tank uses an actual transparent water surface",transparent_water)
	var fish_box: AABB=WorldBuilder.local_aabb(world.goldfish_tank)
	check("fish parts retain their centimetre scale inside the existing tray footprint",fish_box.size.x<=1.55 and fish_box.size.z<=1.25 and fish_box.size.y<=.52,str(fish_box.size))
	var footing_ok:=true
	for wall: MeshInstance3D in world.find_children("BoundaryWall_*","MeshInstance3D",false,false):
		var footing:=wall.get_node_or_null("StoneFooting") as MultiMeshInstance3D
		if footing==null or footing.multimesh==null:
			footing_ok=false;continue
		var size: Vector3=footing.multimesh.mesh.get_aabb().size
		footing_ok=footing_ok and size.z>wall.mesh.get_aabb().size.z+.04 and size.y>=.20
	check("stone footing has real projecting thickness on every boundary wall",footing_ok)
	var transitions:=0
	for node: Node in world.get_children():
		if not node is MeshInstance3D or not node.get_meta("plaza_lawn_transition",false): continue
		var material: ShaderMaterial=node.get("material_override") as ShaderMaterial
		if material!=null and float(material.get_shader_parameter("feather"))>.5: transitions+=1
	check("plaza lawn borders retain their transition after material selection",transitions==2,str(transitions))
	check("flower clusters and fringe leave actual activity clearances",int(world.get_meta("plaza_flower_clumps",0))>=12 and int(world.get_meta("plaza_fringe_clumps",0))>10)
