extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool) -> void:t.check("HERO_TREE",label,ok)
func run() -> void:
	var hero: Node3D=null
	for node: Node in main.world.get_children():
		if node.get_meta("model_id","")=="T05_old_shade_tree":hero=node as Node3D;break
	check("courtyard uses a distinct reference-built old tree",hero!=null)
	var box: AABB=hero.global_transform*WorldBuilder.local_aabb(hero) if hero else AABB()
	check("old tree has a wide spreading canopy",hero!=null and box.size.x>11 and box.size.z>10 and box.size.y>8)
	var thick:=false
	if hero:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(hero):
			if mesh.name.begins_with("Trunk"):
				var arrays: Array=mesh.mesh.surface_get_arrays(0);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var xs: Array[float]=[]
				for vertex: Vector3 in vertices:
					if vertex.y>.85 and vertex.y<1.05:xs.append(vertex.x)
				if not xs.is_empty():thick=float(xs.max())-float(xs.min())>1.7
	check("the reference trunk is thick at standing height",thick)
	check("root clearance is protected during placement",float(Layout.NOGO_CIRCLES[0][1])>=2.4)
	var shade_seats: Array=main.world.find_children("OldTreeSeat_*","Node3D",false,false)
	check("old tree shade has benches on both sides",shade_seats.size()==2)
	check("tree interaction stays reachable beyond its trunk",t.point("zelkova")!=null and t.point("zelkova").global_position.distance_to(Vector3(4,1.2,7))>1.4)
	check("reference tree export is still in the model library",ResourceLoader.exists("res://assets/models/T05_old_shade_tree.glb"))
