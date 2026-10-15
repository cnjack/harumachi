extends RefCounted
## Independent scene checks. This file can run unchanged against the pre-refinement game.
var t: Node
var main: Node
var ink_failures: Array[Dictionary]=[]
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("MATERIAL_REFINEMENT",label,ok,detail)

func parameter(material: Material,key: String,fallback: Variant=null) -> Variant:
	if not material is ShaderMaterial:return fallback
	var shader: Shader=material.shader
	for item: Dictionary in shader.get_shader_uniform_list():
		if str(item.name)==key:
			var value: Variant=material.get_shader_parameter(key)
			return value if value!=null else fallback
	return fallback

func backed_ink(root: Node3D,glyph: Label3D) -> bool:
	if glyph.font==null:return false
	var max_width:=0.0
	var lines: PackedStringArray=glyph.text.split("\n")
	for line: String in lines:max_width=maxf(max_width,glyph.font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,glyph.font_size).x)
	var height: float=(glyph.font.get_height(glyph.font_size)*lines.size()+maxi(0,lines.size()-1)*glyph.line_spacing)*glyph.pixel_size
	var width: float=max_width*glyph.pixel_size
	var direction: Vector3=glyph.global_basis.z.normalized()
	for corner: Vector2 in [Vector2.ZERO,Vector2(-.49,-.49),Vector2(-.49,.49),Vector2(.49,-.49),Vector2(.49,.49)]:
		var point: Vector3=glyph.to_global(Vector3(corner.x*width,corner.y*height,0))
		var nearest:=INF
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
			var inverse: Transform3D=mesh.global_transform.affine_inverse()
			var a: Vector3=inverse*(point+direction*.015)
			var b: Vector3=inverse*(point-direction*.10)
			var faces: PackedVector3Array=mesh.mesh.get_faces()
			for index: int in range(0,faces.size(),3):
				var hit: Variant=Geometry3D.segment_intersects_triangle(a,b,faces[index],faces[index+1],faces[index+2])
				if hit is Vector3:nearest=minf(nearest,point.distance_to(mesh.to_global(hit)))
		if nearest>.016:
			ink_failures.append({"glyph":str(glyph.get_path()),"corner":str(corner),"world_point":str(point),"nearest_m":str(nearest)})
			return false
	return true

func directions(root: Node) -> Dictionary:
	var all_supported:=true
	var count:=0
	for node: Node in root.find_children("*","Node3D",true,false):
		if node.get_meta("model_id","")!="P_signpost":continue
		var local_count:=0
		for glyph: Label3D in node.find_children("SupportedDirection_*","Label3D",true,false):
			all_supported=all_supported and backed_ink(node,glyph)
			local_count+=1
		count+=local_count
		all_supported=all_supported and local_count==6
	return {"count":count,"supported":all_supported,"failures":ink_failures.duplicate()}

func run() -> void:
	var world: WorldBuilder=main.world
	var walls: Array[Node]=world.find_children("BoundaryWall_*","MeshInstance3D",false,false)
	var bases_ok: bool=walls.size()==Layout.WALLS.size()
	var footing_ok:=true
	var pier_count:=0
	for wall: MeshInstance3D in walls:
		var h: float=wall.mesh.get_aabb().size.y
		var bottom: float=wall.global_position.y-h*.5
		var material: Material=wall.material_override
		bases_ok=bases_ok and bool(parameter(material,"local_weathering",false)) and absf(float(parameter(material,"wall_base",INF))-bottom)<.0001 and absf(float(parameter(material,"wall_top",INF))-(bottom+h))<.0001
		var footing:=wall.get_node_or_null("StoneFooting") as MultiMeshInstance3D
		if footing==null:footing_ok=false
		else:
			footing_ok=footing_ok and bool(parameter(footing.material_override,"footing_only",false)) and bool(parameter(footing.material_override,"local_weathering",false)) and footing.multimesh.mesh.get_aabb().size.y>=.20
		for pier: MeshInstance3D in wall.find_children("PlasterPier_*","MeshInstance3D",false,false):
			pier_count+=1
			footing_ok=footing_ok and absf(float(parameter(pier.material_override,"wall_base",INF))-bottom)<.0001
	check("all boundary finishes use their actual bottom and top rather than a global grey strip",bases_ok,str(walls.size()))
	check("projecting stone bases and plaster piers share the same local weathering height",footing_ok and pier_count>0,str(pier_count))
	var street: ShaderMaterial=WorldBuilder.ground_material("stone")
	var grass: ShaderMaterial=WorldBuilder.ground_material("grass")
	var entry_value: Variant=parameter(street,"entrances",PackedVector4Array())
	var entries: PackedVector4Array=entry_value if entry_value is PackedVector4Array else PackedVector4Array()
	var entry_ok: bool=entries.size()==8 and int(parameter(street,"entrance_count",0))==8
	for entry: Vector4 in entries:
		var found:=false
		for point: Array in Layout.POINTS:
			if Vector2(float(point[1]),float(point[2])).distance_to(Vector2(entry.x,entry.y))<.001:found=true
		entry_ok=entry_ok and found and entry.z>0. and entry.w>0.
	check("matte street wear follows eight real entrances and does not modify lawns",entry_ok and bool(parameter(street,"street_detail",false)) and not bool(parameter(grass,"street_detail",false)) and float(parameter(street,"wet",1.))==0.,str({"count":entries.size(),"uniform_count":parameter(street,"entrance_count",0),"entry_type":typeof(entry_value),"entry_ok":entry_ok,"street_detail":parameter(street,"street_detail",false),"grass_detail":parameter(grass,"street_detail",false),"wet":parameter(street,"wet",1.)}))
	var edge_value: Variant=parameter(street,"wall_edges",PackedVector4Array())
	var edges: PackedVector4Array=edge_value if edge_value is PackedVector4Array else PackedVector4Array()
	var edge_ok: bool=edges.size()==Layout.WALLS.size()
	for index: int in mini(edges.size(),Layout.WALLS.size()):
		var edge: Vector4=edges[index];var original: Array=Layout.WALLS[index]
		edge_ok=edge_ok and edge.distance_to(Vector4(float(original[0]),float(original[1]),float(original[2]),float(original[3])))<.001
	check("street corner dust is bounded by actual wall segments while old paving remains the base texture",edge_ok and parameter(street,"albedo_tex") is Texture2D and parameter(street,"street_paint") is Texture2D)
	var details:=world.get_node_or_null("StreetMaintenance") as Node3D
	var clear: bool=details!=null
	var brushes:=0
	if details:
		clear=details.find_children("*","CollisionObject3D",true,false).is_empty()
		for brush: Node3D in details.get_children():
			if brush.get_meta("entrance_use","")!="sole_brush":continue
			brushes+=1
			var box: AABB=brush.global_transform*WorldBuilder.local_aabb(brush)
			for point: Array in Layout.POINTS:
				var at:=Vector3(float(point[1]),0.,float(point[2]))
				var nearest:=Vector2(clampf(at.x,box.position.x,box.end.x),clampf(at.z,box.position.z,box.end.z))
				clear=clear and Vector2(at.x,at.z).distance_to(nearest)>.65
	check("useful door brushes introduce no blockers and leave real capsule approaches clear",clear and brushes==2,str(brushes))
	var moss: MeshInstance3D=details.get_node_or_null("SparseWallMossFibres") as MeshInstance3D if details else null
	var moss_ok: bool=moss!=null and moss.mesh.get_faces().size()>=27 and moss.mesh.get_faces().size()<=240
	var moss_min:=INF;var moss_max: float=-INF
	if moss:
		for vertex: Vector3 in moss.mesh.get_faces():
			moss_min=minf(moss_min,vertex.y);moss_max=maxf(moss_max,vertex.y)
			moss_ok=moss_ok and vertex.is_finite() and vertex.y>=.020 and vertex.y<=.045
	check("wall moss has a few actual centimetre fibre silhouettes rather than a painted green band",moss_ok,str({"vertices":moss.mesh.get_faces().size() if moss else 0,"min_y":str(moss_min),"max_y":str(moss_max)}))
	var farm: Node3D=world.farm
	var sign:=farm.get_node_or_null("FarmNameSign") as Node3D
	var sign_original: bool=false
	if sign:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(sign):
			for surface: int in mesh.mesh.get_surface_count():
				var mat: Material=mesh.get_active_material(surface)
				sign_original=sign_original or parameter(mat,"albedo_tex") is Texture2D
	check("farm sign retains the real generated joined board, posts and painted grain",sign!=null and sign.get_meta("modular_source","")=="MS03_garden_board" and sign_original)
	check("farm lettering is incised into the same physical wood instead of floating labels",sign!=null and sign.get_meta("engraved_surfaces",0)>0 and sign.get_meta("engraving_two_sided",false) and sign.find_children("*","Label3D",true,false).is_empty())
	var engraved_arrows:=0
	var arrow_support:=true
	for node: Node in world.find_children("*","Node3D",true,false):
		if not node.get_meta("modular_signpost",false):continue
		for arrow: Node3D in node.find_children("Arrow_*","Node3D",true,false):
			engraved_arrows+=1
			arrow_support=arrow_support and arrow.get_meta("engraved_surfaces",0)>0 and arrow.get_meta("engraving_two_sided",false)
			var ink_rect: Vector4=arrow.get_meta("engraving_rect",Vector4.ZERO)
			var wood_box: AABB=WorldBuilder.local_aabb(arrow)
			arrow_support=arrow_support and ink_rect.z>0 and ink_rect.w>0 and ink_rect.x-ink_rect.z*.5>=wood_box.position.x and ink_rect.x+ink_rect.z*.5<=wood_box.end.x and ink_rect.y-ink_rect.w*.5>=wood_box.position.y and ink_rect.y+ink_rect.w*.5<=wood_box.end.y
	check("town farm and lake arrows carry front/back lettering on the actual generated wood",engraved_arrows>=12 and arrow_support,str(engraved_arrows))
	var build:=world.get_node_or_null("BuildSign") as Node3D
	var build_face:=build.find_child("EventBoard",true,false) as Node3D if build else null
	check("build-area sign combines reusable generated posts and an engraved real board",build_face!=null and build_face.get_meta("engraved_surfaces",0)>0 and build.find_children("*","Label3D",true,false).is_empty())
	var joined_axes:=0
	var joined_ok:=true
	for node: Node in farm.find_children("*","Node3D",true,false):
		if node.get_meta("model_id","") not in ["P_farm_gate","P_bridge"]:continue
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(node):
			for surface: int in mesh.mesh.get_surface_count():
				var material: Material=mesh.get_active_material(surface)
				var minima_value: Variant=parameter(material,"component_min",PackedVector4Array())
				var maxima_value: Variant=parameter(material,"component_max",PackedVector4Array())
				if not minima_value is PackedVector4Array or not maxima_value is PackedVector4Array:continue
				var minima: PackedVector4Array=minima_value;var maxima: PackedVector4Array=maxima_value
				for index: int in mini(minima.size(),maxima.size()):
					var low: Vector4=minima[index];var high: Vector4=maxima[index]
					var size:=Vector3(high.x-low.x,high.y-low.y,high.z-low.z)
					var expected: int=1 if size.y>maxf(size.x,size.z) else (2 if size.z>size.x else 0)
					joined_ok=joined_ok and int(low.w)==expected and size.is_finite()
					joined_axes|=1<<int(low.w)
	check("joined bridge and gate timbers retain measured per-piece long axes without repacking source meshes",joined_ok and (joined_axes&3)==3,str(joined_axes))
