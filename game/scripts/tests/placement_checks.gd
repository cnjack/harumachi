extends RefCounted
## Checks rendered support geometry, including loose animals/trees omitted by the legacy audit.
var t: Node
var main: Node
func _init(runner: Node) -> void:
	t=runner;main=runner.main
func check(name: String,ok: bool,detail: String="") -> void:t.check("PLACEMENT",name,ok,detail)
func models(root: Node,out: Array[Node3D]) -> void:
	if root is Node3D and root.has_meta("model_id"):out.append(root)
	for child: Node in root.get_children():models(child,out)
func bounds(node: Node3D) -> AABB:return node.global_transform*WorldBuilder.local_aabb(node)
func rectangle(box: AABB) -> Rect2:return Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))
func primitives(root: Node,out: Array[MeshInstance3D]) -> void:
	if root.has_meta("model_id"):return
	if root is MeshInstance3D:out.append(root)
	for child: Node in root.get_children():primitives(child,out)
func vertical_hit(mesh: MeshInstance3D,at: Vector2,ceiling: float) -> float:
	var box: AABB=mesh.global_transform*mesh.get_aabb()
	if not rectangle(box).grow(.001).has_point(at):return -INF
	var best: float=-INF
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array=mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count: int=indices.size() if not indices.is_empty() else vertices.size()
		for index in range(0,count-2,3):
			var a: Vector3=mesh.global_transform*vertices[indices[index] if not indices.is_empty() else index]
			var b: Vector3=mesh.global_transform*vertices[indices[index+1] if not indices.is_empty() else index+1]
			var c: Vector3=mesh.global_transform*vertices[indices[index+2] if not indices.is_empty() else index+2]
			var normal: Vector3=(b-a).cross(c-a)
			if absf(normal.y)<.0000001:continue
			var y: float=a.y-(normal.x*(at.x-a.x)+normal.z*(at.y-a.z))/normal.y
			if y>ceiling:continue
			var hit:=Vector3(at.x,y,at.y)
			var tolerance: float=normal.length_squared()*.002
			if normal.dot((b-a).cross(hit-a))>=-tolerance and normal.dot((c-b).cross(hit-b))>=-tolerance and normal.dot((a-c).cross(hit-c))>=-tolerance:best=maxf(best,y)
	return best
func support(root: Node,at: Vector2,ceiling: float) -> float:
	var best: float=-INF
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		for sample: Vector2 in [at,at+Vector2(.012,0),at-Vector2(.012,0)]:best=maxf(best,vertical_hit(mesh,sample,ceiling))
	return best
func run() -> void:
	var all: Array[Node3D]=[];models(main,all)
	var barrel: Node3D
	var stone: Node3D
	var apartment: Node3D
	var cats: Array[Node3D]=[];var trees: Array[Node3D]=[]
	for model: Node3D in all:
		var id: String=model.get_meta("model_id")
		if id=="D02_rain_barrel" and model.global_position.x<200:barrel=model
		if id=="D10_rocks" and model.global_position.x>14 and model.global_position.x<18:stone=model
		if id=="H02":apartment=model
		if id in ["A20_cat_sleep","A22_cat_sit"]:cats.append(model)
		if id.begins_with("T0"):trees.append(model)
	check("deep census includes nested shop stock and AmbientLife",all.size()>550 and cats.size()==3,"%d tagged models; %d cats"%[all.size(),cats.size()])
	check("rain barrel stands in the garden clear of the residential lane",barrel!=null and bounds(barrel).position.x>=22.35)
	var barrel_clear:=barrel!=null
	for model: Node3D in all:
		if model.get_meta("model_id")=="H03" and model.global_position.x>22 and model.global_position.x<30:barrel_clear=barrel_clear and not bounds(barrel).intersects(bounds(model))
	check("relocated barrel does not enter the neighbouring house",barrel_clear)
	check("moss rocks leave the full side-gate approach open",stone!=null and not rectangle(bounds(stone)).intersects(Rect2(15.6,7.0,1.6,3.0)))
	check("rocks belong to the garden lantern group",stone!=null and Vector2(stone.global_position.x-15.9,stone.global_position.z-12.6).length()<2.0)
	var cat_bad: Array[String]=[];var sleep_clear:=false
	for cat: Node3D in cats:
		var cat_box:=bounds(cat);var contact: float=-INF
		if cat.global_position.x<20:
			var cap: Node=main.world.get_node("BoundaryWall_5/TileCoping")
			contact=support(cap,Vector2(cat.global_position.x,cat.global_position.z),2.0)
			sleep_clear=cat_box.position.y>=contact-.005 and cat_box.position.y<=contact+.025
		elif cat.global_position.x<200:contact=support(main.world.get_node("BoundaryWall_8/TileCoping"),Vector2(cat.global_position.x,cat.global_position.z),2.0)
		else:
			for bench: Node3D in all:
					if bench.get_meta("model_id")=="A12_bench" and bench.global_position.distance_to(cat.global_position)<2.0:contact=support(bench,Vector2(cat.global_position.x,cat.global_position.z),.76)
		if not is_finite(contact) or cat_box.position.y<contact-.008 or cat_box.position.y>contact+.025:cat_bad.append("%s base %.3f support %.3f"%[cat.get_meta("model_id"),cat_box.position.y,contact])
	check("sleeping cat is above the actual tiled coping",sleep_clear)
	check("all three ambient cats rest on rendered supports",cats.size()==3 and cat_bad.is_empty(),str(cat_bad))
	var ground_meshes: Array[MeshInstance3D]=[];primitives(main.world,ground_meshes)
	var tree_bad: Array[String]=[]
	for tree: Node3D in trees:
		var tree_box:=bounds(tree);var floor_y: float=-INF
		for mesh: MeshInstance3D in ground_meshes:floor_y=maxf(floor_y,vertical_hit(mesh,Vector2(tree.global_position.x,tree.global_position.z),tree_box.position.y+.40))
		if not is_finite(floor_y) or tree_box.position.y>floor_y+.012 or tree_box.position.y<floor_y-.12:tree_bad.append("%s base %.3f ground %.3f at %s"%[tree.get_meta("model_id"),tree_box.position.y,floor_y,str(tree.global_position)])
	check("all model tree roots meet the rendered terrain",trees.size()>=60 and tree_bad.is_empty(),str(tree_bad))
	var stair_clear:=apartment!=null
	if apartment:
		var apartment_box:=bounds(apartment)
		var stair_area:=Rect2(apartment_box.end.x-1.8,apartment_box.end.z-2.0,2.8,2.7)
		for tree: Node3D in trees:stair_clear=stair_clear and not rectangle(bounds(tree)).intersects(stair_area)
	check("apartment stairs are clear of trunks and tree crowns",stair_clear)
	check("street-lamp offering box and interaction are removed",main.world.get_node_or_null("Homage_town/Keepsake_egg_star_box")==null and t.point("egg_star_box")==null and Homage.definition("egg_star_box").is_empty())
	var bench_bad: Array[String]=[]
	for model: Node3D in all:
		if model.get_meta("model_id")=="A12_bench" and model.global_position.x>600:
			var floor_y: float=-INF
			for mesh: MeshInstance3D in ground_meshes:floor_y=maxf(floor_y,vertical_hit(mesh,Vector2(model.global_position.x,model.global_position.z),bounds(model).position.y+.30))
			if not is_finite(floor_y) or absf(bounds(model).position.y-floor_y)>.025:bench_bad.append("%s at %s base %.4f floor %.4f"%[str(model.get_path()),str(model.global_position),bounds(model).position.y,floor_y])
	check("all farm benches sit on the ground",bench_bad.is_empty(),str(bench_bad))
	check("remaining discoveries retain working world interactions",Homage.entries().size()==4 and Homage.entries().all(func(entry: Dictionary):return t.point(str(entry.id))!=null))
