extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("HERO_TREE",label,ok,detail)

func basal_open_ratio(hero: Node3D) -> float:
	var vertex_ids: Dictionary={}
	var edge_uses: Dictionary={}
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(hero):
		if not mesh.name.begins_with("Trunk"): continue
		var local: Transform3D=hero.global_transform.affine_inverse()*mesh.global_transform
		var faces: PackedVector3Array=mesh.mesh.get_faces()
		for index in range(0,faces.size(),3):
			var points:=PackedVector3Array()
			var ids:=PackedInt32Array()
			for corner in 3:
				var point: Vector3=local*faces[index+corner]
				var key:=Vector3i(roundi(point.x*100000),roundi(point.y*100000),roundi(point.z*100000))
				if not vertex_ids.has(key): vertex_ids[key]=vertex_ids.size()
				points.append(point);ids.append(int(vertex_ids[key]))
			for side in 3:
				var next: int=(side+1)%3
				var height: float=(points[side].y+points[next].y)*.5
				if height<.3 or height>1.6: continue
				var edge:=Vector2i(mini(ids[side],ids[next]),maxi(ids[side],ids[next]))
				edge_uses[edge]=int(edge_uses.get(edge,0))+1
	var opened:=0
	for uses: int in edge_uses.values():
		if uses==1: opened+=1
	return float(opened)/maxi(edge_uses.size(),1)

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
	var open_ratio: float=basal_open_ratio(hero) if hero else 1.0
	check("old tree bark remains closed after mesh optimization",open_ratio<.001,str(open_ratio))
	var covered:=hero!=null
	var sampled:=0
	if hero:
		var body:=hero.get_node("TrunkCollision") as StaticBody3D
		var shapes: Array=body.find_children("*","CollisionShape3D",true,false)
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(hero):
			if not mesh.name.begins_with("Trunk"): continue
			for vertex: Vector3 in mesh.mesh.get_faces():
				var point: Vector3=hero.to_local(mesh.to_global(vertex))
				if point.y<.85 or point.y>1.05: continue
				sampled+=1
				var inside:=false
				for shape: CollisionShape3D in shapes:
					var cylinder:=shape.shape as CylinderShape3D
					if cylinder==null: continue
					var at: Vector3=shape.to_local(hero.to_global(point))
					if absf(at.y)<=cylinder.height*.5+.03 and Vector2(at.x,at.z).length()<=cylinder.radius+.03: inside=true
				covered=covered and inside
	check("tree collision covers real bark at walking height",covered and sampled>50,str(sampled))
	check("root clearance is protected during placement",float(Layout.NOGO_CIRCLES[0][1])>=2.4)
	var shade_seats: Array=main.world.find_children("OldTreeSeat_*","Node3D",false,false)
	check("old tree shade has benches on both sides",shade_seats.size()==2)
	check("tree interaction stays reachable beyond its trunk",t.point("zelkova")!=null and t.point("zelkova").global_position.distance_to(Vector3(4,1.2,7))>1.4)
	check("reference tree export is still in the model library",ResourceLoader.exists("res://assets/models/T05_old_shade_tree.glb"))
