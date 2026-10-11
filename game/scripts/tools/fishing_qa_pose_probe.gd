extends SkeletonModifier3D
## QA only: inspect the rendered pose and real skinned hand vertices in modifier time.
var view: Node3D
var joints: Dictionary = {}
var hand_centres: Dictionary = {}
var rod_skin_gap := INF
var samples: Dictionary = {"L": [], "R": []}

static func joint(sk: Skeleton3D, name: String) -> int:
	var direct: int = sk.find_bone(name)
	if direct >= 0:return direct
	var imported: String = {"upper.R":"RightArm","fore.R":"RightForeArm","hand.R":"RightHand","upper.L":"LeftArm","fore.L":"LeftForeArm","hand.L":"LeftHand","hips":"Hips","head":"Head"}.get(name,name)
	var index: int = sk.find_bone("mixamorig:"+imported)
	return index if index>=0 else sk.find_bone("mixamorig_"+imported)

func prepare(source: Node3D) -> void:
	var sk: Skeleton3D = get_skeleton()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(source):
		if mesh.skin==null:continue
		var binds: Array[int] = []
		for bind: int in mesh.skin.get_bind_count():
			var bone: int = mesh.skin.get_bind_bone(bind)
			binds.append(bone if bone>=0 else sk.find_bone(mesh.skin.get_bind_name(bind)))
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			if vertices.is_empty() or bones.is_empty():continue
			var count: int = bones.size()/vertices.size()
			for vertex: int in vertices.size():
				var hands: Dictionary = {"L":0.0,"R":0.0}
				var chain: Array[Dictionary] = []
				for influence: int in count:
					var weight: float = weights[vertex*count+influence]
					if weight<=0:continue
					var bind: int = bones[vertex*count+influence]
					var name: String = sk.get_bone_name(binds[bind])
					if name.contains("RightHand") or name=="hand.R":hands.R+=weight
					if name.contains("LeftHand") or name=="hand.L":hands.L+=weight
					chain.append({"bone":binds[bind],"inverse_bind":mesh.skin.get_bind_pose(bind),"weight":weight})
				for side: String in ["L","R"]:
					if float(hands[side])>.65:samples[side].append({"position":vertices[vertex],"chain":chain})

func _process_modification() -> void:
	var sk: Skeleton3D = get_skeleton()
	joints.clear()
	for name: String in ["upper.R","fore.R","hand.R","upper.L","fore.L","hand.L","hips","head"]:
		var bone: int = joint(sk,name)
		if bone>=0:joints[name]=sk.to_global(sk.get_bone_global_pose(bone).origin)
	var handle := Vector3.INF
	if is_instance_valid(view) and is_instance_valid(view.get("rod")):
		handle=(view.get("rod") as MeshInstance3D).to_global(Vector3(0,-.925,0))
	rod_skin_gap=INF
	hand_centres.clear()
	for side: String in ["L","R"]:
		var total := Vector3.ZERO
		for sample: Dictionary in samples[side]:
			var point := Vector3.ZERO
			for influence: Dictionary in sample.chain:
				var transform: Transform3D = sk.get_bone_global_pose(influence.bone)*(influence.inverse_bind as Transform3D)
				point+=(transform*(sample.position as Vector3))*float(influence.weight)
			point=sk.to_global(point)
			total+=point
			if side=="R":rod_skin_gap=minf(rod_skin_gap,point.distance_to(handle))
		if not (samples[side] as Array).is_empty():hand_centres[side]=total/(samples[side] as Array).size()
