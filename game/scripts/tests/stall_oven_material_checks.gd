extends RefCounted
## Geometry-backed checks for the two locally refined props. No report metadata
## is used as a substitute for the actual imported triangles or materials.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t=runner
	main=runner.main

func check(label: String,ok: bool,detail: String="") -> void:
	t.check("STALL_OVEN_MATERIAL",label,ok,detail)

func local_triangles(model: Node3D,minimum_y: float=-INF,skip_glass: bool=false) -> PackedVector3Array:
	var result:=PackedVector3Array()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
		if mesh.mesh==null:continue
		var relative: Transform3D=model.global_transform.affine_inverse()*mesh.global_transform
		for surface: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D=mesh.get_active_material(surface) as StandardMaterial3D
			if skip_glass and material!=null and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
			var arrays: Array=mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var count: int=indices.size() if not indices.is_empty() else vertices.size()
			for face: int in range(0,count-2,3):
				var a: Vector3=relative*vertices[indices[face] if not indices.is_empty() else face]
				var b: Vector3=relative*vertices[indices[face+1] if not indices.is_empty() else face+1]
				var c: Vector3=relative*vertices[indices[face+2] if not indices.is_empty() else face+2]
				if maxf(a.y,maxf(b.y,c.y))>=minimum_y:result.append_array(PackedVector3Array([a,b,c]))
	return result

func bvh(model: Node3D,minimum_y: float=-INF,skip_glass: bool=false) -> TriangleMesh:
	var tree:=TriangleMesh.new()
	tree.create_from_faces(local_triangles(model,minimum_y,skip_glass))
	return tree

func sampled_roof(tree: TriangleMesh) -> Dictionary:
	var hits:=0
	var samples:=0
	var longest_hole:=0
	for z: float in [-.44,-.22,0.0,.22,.44]:
		var hole:=0
		for col: int in 257:
			var x: float=-1.28+2.56*float(col)/256.0
			var hit: Dictionary=tree.intersect_segment(Vector3(x,1.93,z),Vector3(x,1.735,z))
			samples+=1
			if hit.is_empty():
				hole+=1
				longest_hole=maxi(longest_hole,hole)
			else:
				hits+=1
				hole=0
	return {"hits":hits,"samples":samples,"coverage":float(hits)/samples,"longest_open_width_m":longest_hole*.01}

func run() -> void:
	var stall: Node3D=main.world.get_node_or_null("P09")
	if stall==null:
		check("serving stall exists for geometry checks",false)
		return
	var roof_tree: TriangleMesh=bvh(stall,1.735)
	var roof: Dictionary=sampled_roof(roof_tree)
	check("stall canvas has continuous rain and shadow coverage across former slat seams",float(roof.coverage)>.998 and float(roof.longest_open_width_m)<.008,str(roof))
	var thicknesses: Array[float]=[]
	for x: float in [-1.10,-.84,-.58,-.32,-.06,.20,.46,.72,.98,1.20]:
		var top: Dictionary=roof_tree.intersect_segment(Vector3(x,1.94,0),Vector3(x,1.76,0))
		var underside: Dictionary=roof_tree.intersect_segment(Vector3(x,1.76,0),Vector3(x,1.94,0))
		if not top.is_empty() and not underside.is_empty():
			thicknesses.append(absf((top.position as Vector3).y-(underside.position as Vector3).y))
	thicknesses.sort()
	var median: float=thicknesses[int(thicknesses.size()*.5)] if not thicknesses.is_empty() else INF
	check("canopy is a thin folded cloth rather than five-centimetre rounded boards",thicknesses.size()==10 and median>=.0015 and median<=.010,str(thicknesses))
	var counter_tree: TriangleMesh=bvh(stall)
	var counter_heights: Array[float]=[]
	for x: float in [-.9,-.6,-.3,0.0,.3,.6,.9]:
		for z: float in [-.25,0.0,.25]:
			var support: Dictionary=counter_tree.intersect_segment(Vector3(x,1.35,z),Vector3(x,.35,z))
			if not support.is_empty():counter_heights.append((support.position as Vector3).y)
	counter_heights.sort()
	var support_ok: bool=counter_heights.size()==21 and counter_heights[0]>.45 and counter_heights[-1]<.9 and counter_heights[-1]-counter_heights[0]<.014
	check("the original complete serving counter remains level and unobstructed below the canopy",support_ok,str(counter_heights))
	var oven: Node3D=null
	for node: Node in main.find_children("*","Node3D",true,false):
		if str(node.get_meta("model_id",""))=="P_deck_oven":
			oven=node as Node3D
			break
	if oven==null:
		check("bakery oven exists for geometry checks",false)
		return
	var oven_tree: TriangleMesh=bvh(oven,-INF,true)
	var planes: Array[float]=[]
	var handles: Array[float]=[]
	for height: float in [.905,1.465]:
		for x: float in [-.59,-.43,-.27,-.11,.05,.21,.36]:
			# Exported Blender -Y is Godot +Z: query real front face toward back.
			var plane_hit: Dictionary=oven_tree.intersect_segment(Vector3(x,height+.22,.70),Vector3(x,height+.22,.30))
			if not plane_hit.is_empty():planes.append((plane_hit.position as Vector3).z)
		for x: float in [-.45,-.30,-.15,0.0,.15,.22]:
			var handle_hit: Dictionary=oven_tree.intersect_segment(Vector3(x,height+.170,.70),Vector3(x,height+.170,.47))
			if not handle_hit.is_empty():handles.append((handle_hit.position as Vector3).z)
	planes.sort()
	handles.sort()
	check("both oven door frames have straight coplanar front rails",planes.size()==14 and planes[-1]-planes[0]<.0015,str(planes))
	check("both oven pull bars share a straight level axis and project clear of the doors",handles.size()==12 and handles[0]>.502 and handles[-1]-handles[0]<.0015,str(handles))
	var dial_faces: Array[float]=[]
	for height: float in [.905,1.465]:
		for offset: float in [.071,-.112]:
			for dx: float in [-.018,.018]:
				for dy: float in [-.008,.008]:
					var dial_hit: Dictionary=oven_tree.intersect_segment(Vector3(.585+dx,height+offset+dy,.60),Vector3(.585+dx,height+offset+dy,.45))
					if not dial_hit.is_empty():dial_faces.append((dial_hit.position as Vector3).z)
	dial_faces.sort()
	check("four round control knobs have complete aligned flat faces instead of warped painted blobs",dial_faces.size()==16 and dial_faces[0]>.476 and dial_faces[-1]-dial_faces[0]<.003,str(dial_faces))
	var roles: Dictionary={}
	var glass_count:=0
	var warm_count:=0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(oven):
		for surface: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D=mesh.get_active_material(surface) as StandardMaterial3D
			if material==null:continue
			roles[material.resource_name]=true
			if material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a<.5:glass_count+=1
			if material.emission_enabled and material.emission_energy_multiplier>0:warm_count+=1
	check("oven enamel seals controls glass and cavity have independent real materials",roles.size()>=7 and glass_count>=2 and warm_count>=2,str({"materials":roles.keys(),"glass":glass_count,"warm":warm_count}))
	var recesses: Array[float]=[]
	for height: float in [.905,1.465]:
		var inside: Dictionary=oven_tree.intersect_segment(Vector3(-.115,height-.037,.43),Vector3(-.115,height-.037,-.10))
		if not inside.is_empty():recesses.append(.43-(inside.position as Vector3).z)
	check("two oven windows reveal actual recessed cavities behind their glass",recesses.size()==2 and recesses[0]>.12 and recesses[1]>.12,str(recesses))
