class_name FoliageBackdrop
extends RefCounted
## Low meadow and uneven shrub groups join the real tree ring to the distant hills.
const BANDS: Array = [[-110.0,-85.0,110.0,-28.0],[-110.0,-28.0,-55.0,145.0],[-55.0,33.0,-7.0,145.0],[-7.0,88.0,45.0,145.0],[45.0,-28.0,110.0,145.0]]
const PLAY_RECTS := [Rect2(-52.2,-25.2,94.9,57.4),Rect2(-4.0,32.0,46.7,53.2)]
const OUTER_ORIGIN := Vector2(-148,-120)
const OUTER_SIZE := Vector2(328,312)

static func _rise(point: Vector2) -> float:
	var shoulder: float=smoothstep(52.0,100.0,point.x)*(1.0-smoothstep(124.0,180.0,point.x))
	var ends: float=smoothstep(0.0,18.0,point.y)*(1.0-smoothstep(105.0,132.0,point.y))
	return -.03+shoulder*ends*(2.4+.55*sin(point.y*.13)+.25*sin(point.x*.09+point.y*.08))

static func height_at(point: Vector2) -> float:
	if point.x<52.0 or point.x>180.0 or point.y<0.0 or point.y>132.0: return _outer_height_at(point)
	var cell: Vector2=(point-Vector2(52,0))/4.0
	var base:=Vector2(floorf(cell.x),floorf(cell.y))
	var fraction: Vector2=cell-base
	var origin: Vector2=Vector2(52,0)+base*4.0
	var a: float=_rise(origin)
	var b: float=_rise(origin+Vector2(0,4))
	var c: float=_rise(origin+Vector2(4,4))
	var d: float=_rise(origin+Vector2(4,0))
	if fraction.y>=fraction.x: return a*(1.0-fraction.y)+b*(fraction.y-fraction.x)+c*fraction.x
	return a*(1.0-fraction.x)+c*fraction.y+d*(fraction.x-fraction.y)

static func _outer_rise(point: Vector2) -> float:
	if Rect2(52,0,128,132).has_point(point):return _rise(point)
	var distance: float=INF
	for rect: Rect2 in PLAY_RECTS:
		var dx: float=maxf(maxf(rect.position.x-point.x,point.x-rect.end.x),0.0)
		var dz: float=maxf(maxf(rect.position.y-point.y,point.y-rect.end.y),0.0)
		distance=minf(distance,Vector2(dx,dz).length())
	for opening: Rect2 in [WorldBuilder.EXIT_CUT,Rect2(-148,-18,96,14.5)]:
		var opening_dx: float=maxf(maxf(opening.position.x-point.x,point.x-opening.end.x),0.0)
		var opening_dz: float=maxf(maxf(opening.position.y-point.y,point.y-opening.end.y),0.0)
		distance=minf(distance,Vector2(opening_dx,opening_dz).length())
	var edge: float=minf(minf(point.x-OUTER_ORIGIN.x,OUTER_ORIGIN.x+OUTER_SIZE.x-point.x),minf(point.y-OUTER_ORIGIN.y,OUTER_ORIGIN.y+OUTER_SIZE.y-point.y))
	var ridge: float=2.1+.55*sin(point.x*.043+point.y*.031)+.32*cos(point.y*.071-point.x*.023)
	return -.03+smoothstep(8.0,26.0,distance)*smoothstep(0.0,20.0,edge)*ridge

static func _outer_cell_present(cell: Rect2) -> bool:
	if Rect2(52,0,128,132).encloses(cell) or WorldBuilder.EXIT_CUT.grow(2.0).intersects(cell):return false
	for rect: Rect2 in PLAY_RECTS:
		if rect.grow(3.0).intersects(cell):return false
	return not Rect2(-148,-18,96,14.5).intersects(cell)

static func _outer_height_at(point: Vector2) -> float:
	if not Rect2(OUTER_ORIGIN,OUTER_SIZE).has_point(point):return -.03
	var cell: Vector2=(point-OUTER_ORIGIN)/4.0
	var base:=Vector2(floorf(cell.x),floorf(cell.y))
	var fraction: Vector2=cell-base
	var origin: Vector2=OUTER_ORIGIN+base*4.0
	if not _outer_cell_present(Rect2(origin,Vector2(4,4))):return -.03
	var a: float=_outer_rise(origin)
	var b: float=_outer_rise(origin+Vector2(0,4))
	var c: float=_outer_rise(origin+Vector2(4,4))
	var d: float=_outer_rise(origin+Vector2(4,0))
	if fraction.y>=fraction.x:return a*(1.0-fraction.y)+b*(fraction.y-fraction.x)+c*fraction.x
	return a*(1.0-fraction.x)+c*fraction.y+d*(fraction.x-fraction.y)

static func build_ground(world: WorldBuilder,material: Material) -> void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 33:
		for column in 32:
			var x: float=52.0+column*4.0
			var z: float=row*4.0
			var corners: Array[Vector2]=[Vector2(x,z),Vector2(x,z+4),Vector2(x+4,z+4),Vector2(x+4,z)]
			for index: int in [0,2,1,0,3,2]:
				var point: Vector2=corners[index]
				surface.set_uv(point*.1)
				surface.add_vertex(Vector3(point.x,_rise(point),point.y))
	surface.generate_normals()
	var mesh:=MeshInstance3D.new();mesh.name="BackgroundMeadowRise";mesh.mesh=surface.commit();mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mesh)
	var body:=StaticBody3D.new();body.collision_layer=WorldBuilder.L_GROUND;body.collision_mask=0
	body.set_meta("model_part","background_meadow")
	var shape:=CollisionShape3D.new();shape.shape=mesh.mesh.create_trimesh_shape();body.add_child(shape);mesh.add_child(body)
	_build_outer_ground(world,material)

static func _build_outer_ground(world: WorldBuilder,material: Material) -> void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var starts: Dictionary={}
	var vertex_count: int=0
	for row in 78:
		for column in 82:
			var origin: Vector2=OUTER_ORIGIN+Vector2(column,row)*4.0
			var cell:=Rect2(origin,Vector2(4,4))
			if not _outer_cell_present(cell):continue
			starts[Vector2i(column,row)]=vertex_count
			var corners: Array[Vector2]=[origin,origin+Vector2(0,4),origin+Vector2(4,4),origin+Vector2(4,0)]
			for index: int in [0,2,1,0,3,2]:
				var point: Vector2=corners[index]
				surface.set_uv(point*.1);surface.add_vertex(Vector3(point.x,_outer_rise(point),point.y))
				vertex_count+=1
	surface.generate_normals()
	# Keep the original vertices, UVs and globally smoothed normals exactly. Only
	# split their draw/physics bounds: one cross-town AABB falsely blocked every
	# tabletop even though its actual triangles deliberately avoid the town.
	var complete: ArrayMesh=surface.commit()
	var arrays: Array=complete.surface_get_arrays(0)
	var root:=Node3D.new();root.name="BackgroundMeadowSkirts";world.add_child(root)
	for chunk_row: int in range(0,78,4):
		for chunk_column: int in range(0,82,4):
			_outer_chunk(root,material,Rect2i(chunk_column,chunk_row,mini(4,82-chunk_column),mini(4,78-chunk_row)),starts,arrays)


static func _outer_chunk(root: Node3D,material: Material,region: Rect2i,starts: Dictionary,arrays: Array) -> void:
	var cells: Array[Vector2i]=[]
	var bounds:=Rect2()
	for row: int in range(region.position.y,region.end.y):
		for column: int in range(region.position.x,region.end.x):
			var cell_key:=Vector2i(column,row)
			if not starts.has(cell_key):continue
			var cell:=Rect2(OUTER_ORIGIN+Vector2(cell_key)*4.0,Vector2(4,4))
			bounds=cell if cells.is_empty() else bounds.merge(cell)
			cells.append(cell_key)
	if cells.is_empty():return
	var open_rects: Array[Rect2]=[Rect2(52,0,128,132),WorldBuilder.EXIT_CUT.grow(2.0),Rect2(-148,-18,96,14.5)]
	for play: Rect2 in PLAY_RECTS:open_rects.append(play.grow(3.0))
	var crosses_open_space: bool=false
	for opening: Rect2 in open_rects:
		if bounds.intersects(opening):crosses_open_space=true;break
	if crosses_open_space and (region.size.x>1 or region.size.y>1):
		var half_x: int=maxi(1,region.size.x >> 1)
		var half_y: int=maxi(1,region.size.y >> 1)
		for z: int in range(region.position.y,region.end.y,half_y):
			for x: int in range(region.position.x,region.end.x,half_x):
				_outer_chunk(root,material,Rect2i(x,z,mini(half_x,region.end.x-x),mini(half_y,region.end.y-z)),starts,arrays)
		return
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var patch:=SurfaceTool.new();patch.begin(Mesh.PRIMITIVE_TRIANGLES)
	for kept_key: Vector2i in cells:
		var start: int=int(starts[kept_key])
		for corner: int in 6:
			patch.set_uv(uvs[start+corner]);patch.set_normal(normals[start+corner]);patch.add_vertex(vertices[start+corner])
	var mesh:=MeshInstance3D.new();mesh.name="Meadow_%d_%d_%d_%d"%[region.position.x,region.position.y,region.size.x,region.size.y]
	mesh.mesh=patch.commit();mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(mesh)
	var body:=StaticBody3D.new();body.collision_layer=WorldBuilder.L_GROUND;body.collision_mask=0
	body.set_meta("model_part","outer_meadow")
	var shape:=CollisionShape3D.new();shape.shape=mesh.mesh.create_trimesh_shape();body.add_child(shape);mesh.add_child(body)

static func keep_open(point: Vector2) -> bool:
	for rect: Rect2 in PLAY_RECTS:
		if rect.grow(3.0).has_point(point):return false
	if WorldBuilder.EXIT_CUT.grow(2.0).has_point(point): return false
	if point.x < -52.0 and point.y > -18.0 and point.y < -3.5: return false
	if not Rect2(52,0,128,132).has_point(point):
		var cell: Vector2=(point-OUTER_ORIGIN)/4.0
		var base:=Vector2(floorf(cell.x),floorf(cell.y))
		if not _outer_cell_present(Rect2(OUTER_ORIGIN+base*4.0,Vector2(4,4))):return false
	return true

static func build(world: WorldBuilder) -> void:
	var meadow:=GrassField.new()
	meadow.name="BackgroundMeadow"
	world.add_child(meadow)
	var total: int=meadow.lawn(BANDS,[],"backdrop",.60,101011,-.03,height_at,keep_open)
	var shrubs:=Node3D.new();shrubs.name="BackgroundShrubGroups";world.add_child(shrubs)
	var rng:=RandomNumberGenerator.new();rng.seed=74101
	var count:=0
	var materials: Dictionary={}
	for band_index in BANDS.size():
		var band: Array=BANDS[band_index]
		for cluster_index in 15:
			var centre:=Vector2(rng.randf_range(band[0]+1.0,band[2]-1.0),rng.randf_range(band[1]+1.0,band[3]-1.0))
			for member in rng.randi_range(2,4):
				var point: Vector2=centre+Vector2(rng.randf_range(-1.7,1.7),rng.randf_range(-1.5,1.5))
				if not keep_open(point): continue
				var plant: Node3D=world.spawn("M12b_shrub",Vector3(point.x,-.03,point.y),rng.randf()*360,0,shrubs,rng.randf_range(.80,1.9))
				if plant==null: continue
				plant.name="BackgroundShrub_%d"%count
				plant.set_meta("background_band",band_index)
				WorldBuilder.rest_on(plant,height_at(point))
				for mesh: MeshInstance3D in WorldBuilder.find_meshes(plant):
					mesh.visibility_range_end=115.0
					mesh.visibility_range_end_margin=15.0
					for surface in mesh.mesh.get_surface_count():
						var source:=mesh.get_active_material(surface) as ShaderMaterial
						if source==null: continue
						var key: int=source.get_instance_id()
						if not materials.has(key):
							var green:=source.duplicate() as ShaderMaterial
							green.set_shader_parameter("meadow_foliage",int(source.get_shader_parameter("part_role"))==1)
							materials[key]=green
						mesh.set_surface_override_material(surface,materials[key])
				count+=1
	world.set_meta("background_meadow_clumps",total)
	world.set_meta("background_shrubs",count)
	_build_tree_groups(world,materials)

static func _build_tree_groups(world: WorldBuilder,materials: Dictionary) -> void:
	var trees:=Node3D.new();trees.name="BackgroundTreeGroups";world.add_child(trees)
	var rng:=RandomNumberGenerator.new();rng.seed=741018
	for cluster in 32:
		var angle: float=TAU*float(cluster)/32.0
		var radial:=Vector2(sin(angle),-cos(angle))
		var centre:=Vector2(-5,30)+radial*Vector2(98,118)*(1.0+rng.randf_range(-.035,.035))
		var tangent:=Vector2(-radial.y,radial.x)
		for member in 3:
			var point: Vector2=centre+tangent*(float(member-1)*5.2)+radial*rng.randf_range(-3.0,3.0)
			var clear: bool=keep_open(point)
			for rect: Rect2 in PLAY_RECTS:
				if rect.grow(7.0).has_point(point):clear=false
			if not clear:continue
			var id: String=WorldBuilder.NEAR_TREES[(cluster+member)%3]
			var tree: Node3D=world.spawn(id,Vector3(point.x,0,point.y),rng.randf_range(0,360),0,trees,rng.randf_range(.95,1.30))
			if tree==null:continue
			tree.name="BackgroundTree_%d_%d"%[cluster,member]
			WorldBuilder.rest_on(tree,height_at(point))
			for mesh: MeshInstance3D in WorldBuilder.find_meshes(tree):
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.visibility_range_end=260.0;mesh.visibility_range_end_margin=24.0
				for surface_index in mesh.mesh.get_surface_count():
					var source:=mesh.get_active_material(surface_index) as ShaderMaterial
					if source==null:continue
					var key: int=source.get_instance_id()
					if not materials.has(key):
						var green:=source.duplicate() as ShaderMaterial
						green.set_shader_parameter("meadow_foliage",int(source.get_shader_parameter("part_role"))==1)
						materials[key]=green
					mesh.set_surface_override_material(surface_index,materials[key])
