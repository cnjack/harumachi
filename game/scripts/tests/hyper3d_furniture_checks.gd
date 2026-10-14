extends RefCounted
## Real imported meshes, visible supports and live material bindings.
const LIBRARY := ["HFF01_cafe_chair","HFF02_round_table","HFF03_rect_table","HFF04_low_table","HFF05_utility_stand","HFF06_indoor_bench","HFF07_sage_counter","HFF08_bread_rack4","HFF09_bread_rack3","HFF10_wall_shelf","HFF11_glass_case","HFF12_reading_armchair","HFF13_espresso_station","HFF14_outdoor_bench"]
const REPLACED := ["P_cafe_table","P_community_table","P_reading_chair","I04_shop_counter","I05_bread_shelf","W17_display_shelf","I02_cake_showcase","P_coffee_station","A12_bench","J03_dining_set","J07_kotatsu","P_low_bookcase","P_gondola"]
var t: Node
var main: Node
func _init(runner: Node) -> void: t=runner;main=runner.main
func check(label: String, ok: bool, detail: String="") -> void:t.check("HYPER3D_FURNITURE",label,ok,detail)
func generated_area(root: Node3D) -> float:
	var area: float=0.
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		for surface: int in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D=mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source==null or source.albedo_texture==null or not source.resource_name.to_lower().begins_with("hyper3d_"):continue
			var arrays: Array=mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			if uv.size()!=vertices.size():continue
			var count: int=indices.size() if not indices.is_empty() else vertices.size()
			for offset: int in range(0,count-2,3):
				var a: int=indices[offset] if not indices.is_empty() else offset
				var b: int=indices[offset+1] if not indices.is_empty() else offset+1
				var c: int=indices[offset+2] if not indices.is_empty() else offset+2
				if absf((uv[b]-uv[a]).cross(uv[c]-uv[a]))<.00000001:continue
				area+=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).length()*.5
	return area
func first(id: String) -> Node3D:
	for node: Node in main.world.find_children("*","Node3D",true,false):
		if str(node.get_meta("model_id",""))==id:return node as Node3D
	return null
func run() -> void:
	var missing: Array[String]=[]
	var fixture:=Node3D.new();fixture.visible=false;main.add_child(fixture)
	for id: String in LIBRARY:
		var path: String="res://assets/models/"+id+".glb"
		if not ResourceLoader.exists(path):missing.append(id);continue
		var node: Node3D=(load(path) as PackedScene).instantiate();fixture.add_child(node)
		if generated_area(node)<.20:missing.append(id+" no mapped generated principal geometry")
	check("fourteen reusable singles contain actual textured generated principal meshes",missing.is_empty(),str(missing))
	var aliases: Array[String]=[]
	for id: String in REPLACED:
		var scene: PackedScene=WorldBuilder.model_scene(id)
		if scene==null:aliases.append(id);continue
		var node: Node3D=scene.instantiate();fixture.add_child(node)
		if generated_area(node)<.20:aliases.append(id)
	check("all thirteen installed furniture groups use real generated geometry",aliases.is_empty(),str(aliases))
	var bakery: Node3D=main.world.interiors.bakery
	var supports: Array[String]=[]
	for label: String in ["DoughWorktable","PrepShelf","HerbLedge","CafeReturnStation"]:
		var top: MeshInstance3D=bakery.find_child(label,true,false) as MeshInstance3D
		if top==null or not top.get_parent() is Node3D or generated_area(top.get_parent())<.20:supports.append(label)
	var wall: Node3D=bakery.find_child("WallStockShelf_0",true,false)
	if wall==null or generated_area(wall)<.20:supports.append("wall flour rack")
	check("bakery worktable wall rack prep stand herb stand and returns use generated furniture",supports.is_empty(),str(supports))
	var mounted: Node3D=wall.find_child("HFF10_wall_shelf",true,false) as Node3D if wall!=null else null
	var audit: Script=load("res://scripts/tests/prop_audit.gd") as Script
	var mount_api: bool=false
	for method: Dictionary in audit.get_script_method_list():
		if str(method.name)=="wall_supported":mount_api=true
	var attached: bool=false
	if mounted!=null and mount_api:
		attached=bool(audit.call("wall_supported",mounted))
		var before: Vector3=mounted.position
		mounted.position.z+=.10
		attached=attached and not bool(audit.call("wall_supported",mounted))
		mounted.position=before
	check("actual wall rack rear wood meets its wall and a ten centimetre gap fails",attached)
	var inventory: Array[Dictionary]=[]
	var model_inventory: Array[Dictionary]=[]
	for placed: Node in main.world.find_children("*","Node3D",true,false):
		var id: String=str(placed.get_meta("model_id",""))
		if id in LIBRARY or id in REPLACED:model_inventory.append({"model_id":id,"path":str(placed.get_path())})
	var flat_errors: Array[String]=[]
	var finish_errors: Array[String]=[]
	for node: Node in main.world.find_children("*","Node3D",true,false):
		if not node.has_meta("hyper3d_reuse"):continue
		var label: String=str(node.get_meta("hyper3d_reuse"))
		var top: MeshInstance3D=node.find_child(label,true,false) as MeshInstance3D
		if top==null:flat_errors.append(label+" missing actual top");continue
		var bounds: AABB=top.global_transform*top.get_aabb()
		var expected: float=bounds.end.y
		for x: float in [-.25,0.,.25]:
			for z: float in [-.25,0.,.25]:
				var at: Vector2=Vector2(bounds.get_center().x+x*bounds.size.x,bounds.get_center().z+z*bounds.size.z)
				var actual: float=WorldBuilder.surface_height(top,at,expected+.003)
				if not is_finite(actual) or absf(actual-expected)>.006:flat_errors.append(label+" "+str(actual-expected))
		var finish: ShaderMaterial=top.get_active_material(0) as ShaderMaterial
		var source: StandardMaterial3D=top.mesh.surface_get_material(0) as StandardMaterial3D
		if finish==null or source==null or finish.get_shader_parameter("albedo_tex")!=source.albedo_texture or int(finish.get_shader_parameter("use_profile"))!=FurnitureWoodFinish.profile_for(label):finish_errors.append(label)
		inventory.append({"path":str(node.get_path()),"model_id":node.get_meta("model_id"),"use":label,"size_m":[bounds.size.x,bounds.size.y,bounds.size.z],"top_y":expected})
	check("resident and public fixtures reuse generated singles across at least forty actual placements",inventory.size()>=40,str(inventory.size()))
	check("all reused tabletops have nine real support probes within six millimetres",flat_errors.is_empty(),str(flat_errors))
	check("reused furniture binds its imported atlas and each real use profile",finish_errors.is_empty(),str(finish_errors))
	var narrow: Node3D
	var wide: Node3D
	var smallest: float=INF
	var largest: float=-INF
	for row: Dictionary in inventory:
		if row.model_id!="HFF05_utility_stand":continue
		var node: Node3D=main.get_node(row.path)
		var span: float=WorldBuilder.local_aabb(node).size.x
		if span<smallest:smallest=span;narrow=node
		if span>largest:largest=span;wide=node
	var cache_ok: bool=narrow!=null and wide!=null and largest-smallest>1.
	if cache_ok:
		for node: Node3D in [narrow,wide]:
			var vertices: PackedVector3Array=PropAudit.tris(node)
			var measured:=AABB(vertices[0],Vector3.ZERO)
			for point: Vector3 in vertices:measured=measured.expand(point)
			var actual: AABB=WorldBuilder.local_aabb(node)
			cache_ok=cache_ok and measured.position.distance_to(actual.position)<.001 and measured.size.distance_to(actual.size)<.001
	check("placement cache measures different fitted sizes of the same generated source independently",cache_ok)
	var rest_errors: Array[String]=[]
	for point: Interactable in main.world.find_children("*","Interactable",true,false):
		if not point.has_meta("seat_support"):continue
		var support: Node3D=main.get_node_or_null(point.get_meta("seat_support")) as Node3D
		if support==null:rest_errors.append(point.id);continue
		var at: Vector3=point.get_parent().to_global(point.get_meta("seat_position"))
		var actual: float=WorldBuilder.surface_height(support,Vector2(at.x,at.z),support.global_position.y+.60)-support.global_position.y
		if not is_finite(actual) or absf(actual-float(point.get_meta("seat_height")))>.004:rest_errors.append(point.id)
	check("outdoor sitting follows the real curved seat at its actual biased position",rest_errors.is_empty(),str(rest_errors))
	var cabinet: Node3D=first("I02_cake_showcase")
	var panes: int=0
	var glass_ok: bool=cabinet!=null
	if cabinet!=null:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(cabinet):
			if not str(mesh.name).begins_with("Glass"):continue
			panes+=1
			var size: Vector3=mesh.get_aabb().size
			var finish: ShaderMaterial=mesh.get_active_material(0) as ShaderMaterial
			glass_ok=glass_ok and absf(size[size.min_axis_index()]-.006)<.0003 and finish!=null and finish.shader.resource_path=="res://shaders/shop_glass.gdshader"
	check("cake cabinet has five separate real six millimetre glass panes with the live glass shader",glass_ok and panes==5,str(panes))
	var coffee: Node3D=first("P_coffee_station")
	var hopper: MeshInstance3D=coffee.find_child("HopperGlass",true,false) as MeshInstance3D if coffee!=null else null
	var beans: Node3D=coffee.find_child("CoffeePile",true,false) as Node3D if coffee!=null else null
	var clear: bool=false
	if hopper!=null:
		var finish: ShaderMaterial=hopper.get_active_material(0) as ShaderMaterial
		clear=finish!=null and finish.shader.resource_path=="res://shaders/appliance_hopper_glass.gdshader" and float(finish.get_shader_parameter("opacity"))<.20 and finish.shader.code.contains("cull_back")
	check("espresso keeps a separate clear hopper and settled visible coffee pile",clear and beans!=null)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file:=FileAccess.open(arg.trim_prefix("--out=").get_basename()+".furniture-inventory.json",FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify({"fixtures":inventory,"models":model_inventory,"native_acceptance":false},"  "))
	fixture.queue_free()
