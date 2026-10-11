class_name StreetMaintenance
extends RefCounted
## Maintained street corners: sparse dry leaves, tiny moss fibres and useful entrance brushes.
## These meshes have no physics. All player ground and interaction positions stay unchanged.
static func build(world: WorldBuilder) -> void:
	if world.get_node_or_null("StreetMaintenance")!=null:return
	var root:=Node3D.new();root.name="StreetMaintenance";world.add_child(root)
	var leaf_surface:=SurfaceTool.new();leaf_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng:=RandomNumberGenerator.new();rng.seed=711031
	# Sheltered wall corners, away from the central lane and shop thresholds.
	for centre: Vector2 in [Vector2(-12.91,23.92),Vector2(16.89,23.91),Vector2(22.48,20.92),Vector2(42.40,31.6),Vector2(-51.90,1.20)]:
		for index: int in 4:
			var at:=Vector3(centre.x+rng.randf_range(-.10,.10),0.,centre.y+rng.randf_range(-.10,.10))
			at.y=_paving_y(Vector2(at.x,at.z))+.001
			var angle: float=rng.randf_range(0,TAU)
			var length: float=rng.randf_range(.045,.075)
			var axis:=Vector3(cos(angle),0,sin(angle))*length*.5
			var cross_axis:=Vector3(-sin(angle),0,cos(angle))*length*.23
			var colour:=Color(.64,.55,.31) if index%3 else Color(.45,.49,.27)
			for point: Vector3 in [at-axis,at+cross_axis,at+axis,at-axis,at+axis,at-cross_axis]:
				leaf_surface.set_normal(Vector3.UP);leaf_surface.set_color(colour);leaf_surface.add_vertex(point)
	var leaves:=MeshInstance3D.new();leaves.name="ShelteredDryLeaves";leaves.mesh=leaf_surface.commit()
	var leaf_material: StandardMaterial3D=JapaneseArchitecture._flat(Color.WHITE);leaf_material.vertex_color_use_as_albedo=true;leaf_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	leaves.material_override=leaf_material;root.add_child(leaves)
	# Two small sole brushes rest at the facade edge, clear of the actual door approach.
	_brush(root,Vector3(-37.55,.010,-15.10),"StoreSoleBrush")
	_brush(root,Vector3(-25.30,.008,-5.92),"CommunitySoleBrush")
	_wall_fibres(world,root)

static func _brush(parent: Node3D,at: Vector3,title: String) -> void:
	var root:=Node3D.new();root.name=title;root.position=at;root.set_meta("entrance_use","sole_brush");parent.add_child(root)
	var base:=MeshInstance3D.new();base.name="CedarBase";var mesh:=BoxMesh.new();mesh.size=Vector3(.26,.025,.14);base.mesh=mesh
	base.position.y=.0125;base.material_override=SurfaceFinish.timber(mesh.get_aabb(),Color(.51,.39,.25),0);root.add_child(base)
	var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D
	var bristle:=BoxMesh.new();bristle.size=Vector3(.007,.032,.007);batch.mesh=bristle;batch.instance_count=84
	for row: int in 7:
		for col: int in 12:batch.set_instance_transform(row*12+col,Transform3D(Basis.IDENTITY,Vector3(-.105+col*.019,.040,-.048+row*.016)))
	var fibres:=MultiMeshInstance3D.new();fibres.name="CoconutBristles";fibres.multimesh=batch;fibres.material_override=JapaneseArchitecture._flat(Color(.53,.44,.27));root.add_child(fibres)

static func _wall_fibres(world: WorldBuilder,parent: Node3D) -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:=0
	for wall: MeshInstance3D in world.find_children("BoundaryWall_*","MeshInstance3D",false,false):
		if wall.get_index()%3!=0:continue
		var half_length: float=wall.mesh.get_aabb().size.x*.5
		for index: int in 9:
			var local:=Vector3(-half_length+.30+index*.017,-wall.mesh.get_aabb().size.y*.5+.021,.1235)
			var at: Vector3=wall.to_global(local)
			var height: float=.012+.004*float(index%3)
			var side: Vector3=wall.global_basis.x*.0035
			st.set_color(Color(.41,.48,.29) if index%2 else Color(.51,.57,.34))
			for vertex: Vector3 in [at-side,at+Vector3(0,height,0)+side*.35,at+side]:
				st.set_normal((wall.global_basis*Vector3(0,.5,1)).normalized());st.add_vertex(vertex)
			count+=1
	if count==0:return
	var fibres:=MeshInstance3D.new();fibres.name="SparseWallMossFibres";fibres.mesh=st.commit()
	var material: StandardMaterial3D=JapaneseArchitecture._flat(Color.WHITE);material.vertex_color_use_as_albedo=true;material.cull_mode=BaseMaterial3D.CULL_DISABLED
	fibres.material_override=material;parent.add_child(fibres)

static func _paving_y(at: Vector2) -> float:
	var height:=0.0
	for index: int in Layout.GROUND.size():
		var patch: Array=Layout.GROUND[index]
		if Rect2(float(patch[1]),float(patch[2]),float(patch[3])-float(patch[1]),float(patch[4])-float(patch[2])).has_point(at):height=maxf(height,.002*index)
	return height
