class_name FoliageBackdrop
extends RefCounted
## Low meadow and uneven shrub groups join the real tree ring to the distant hills.
const BANDS: Array = [[44.0,1.0,83.0,91.0],[-57.0,-67.0,50.0,-27.0],[-85.0,-49.0,-54.0,18.0],[-8.0,94.0,52.0,128.0]]

static func _rise(point: Vector2) -> float:
	var shoulder: float=smoothstep(52.0,100.0,point.x)*(1.0-smoothstep(124.0,180.0,point.x))
	var ends: float=smoothstep(0.0,18.0,point.y)*(1.0-smoothstep(105.0,132.0,point.y))
	return -.03+shoulder*ends*(2.4+.55*sin(point.y*.13)+.25*sin(point.x*.09+point.y*.08))

static func height_at(point: Vector2) -> float:
	if point.x<52.0 or point.x>180.0 or point.y<0.0 or point.y>132.0: return -.03
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

static func keep_open(point: Vector2) -> bool:
	if WorldBuilder.EXIT_CUT.grow(2.0).has_point(point): return false
	if point.x < -52.0 and point.y > -18.0 and point.y < -3.5: return false
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
