class_name LandscapeCoverage
extends RefCounted
## Continuous terrain and staggered 3D tree belts through the shared camera horizon.
const FAR := 210.0
const HAZE_BEGIN := 85.0
const HAZE_END := 190.0
const TILE := 32.0
const PLANTS := ["V06_fine_grass","V07_grass_card","V08_blade_rosette","V09_fern_cluster","V10_leaf_shrub","V11_fallen_leaf","V12_tulip","V13_pampas","V14_broad_grass","V15_wheat_stem"]
const TOWN_PHOTO := Rect2(-58,-35,106,125)
const FARM_PHOTO := Rect2(-35,-40,185,110)

static func configure_haze(environment: Environment,weather_density: float=.0035) -> void:
	environment.fog_mode=Environment.FOG_MODE_DEPTH
	environment.fog_density=1.0
	environment.fog_depth_begin=HAZE_BEGIN*clampf(.0035/maxf(weather_density,.0035),.55,1.0)
	environment.fog_depth_end=HAZE_END
	environment.fog_depth_curve=1.35

static func build(world: WorldBuilder,parent: Node3D,farm: bool) -> void:
	var root:=Node3D.new();root.name="LandscapeCoverage";parent.add_child(root)
	var bounds: Rect2=FARM_PHOTO if farm else TOWN_PHOTO
	var extent: Rect2=bounds.grow(FAR+32.0)
	var material:=ShaderMaterial.new();material.shader=load("res://shaders/distant_meadow.gdshader")
	var terrain:=Node3D.new();terrain.name="Terrain";root.add_child(terrain)
	for z: int in range(int(floorf(extent.position.y/TILE)),int(ceilf(extent.end.y/TILE))):
		for x: int in range(int(floorf(extent.position.x/TILE)),int(ceilf(extent.end.x/TILE))):
			_terrain_tile(terrain,Vector2(x,z)*TILE,farm,material)
	var batches: Dictionary={}
	var rng:=RandomNumberGenerator.new();rng.seed=261012+int(farm)*73
	var count:=0
	# A jittered two-dimensional forest remains solid when viewed sideways or
	# from the 24 m photo camera, unlike a single ring of billboard cards.
	for z: int in range(int(extent.position.y),int(extent.end.y),12):
		for x: int in range(int(extent.position.x),int(extent.end.x),12):
			var point:=Vector2(x+rng.randf_range(-3,3),z+rng.randf_range(-3,3))
			if not _tree_allowed(point,farm) or rng.randf()<.15:continue
			var id: String=WorldBuilder.NEAR_TREES[rng.randi()%3]
			var scale_f: float=rng.randf_range(.80,1.40)
			var transform:=Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(scale_f,scale_f*rng.randf_range(.85,1.1),scale_f)),Vector3(point.x,height_at(point,farm)-.02,point.y))
			_queue(batches,id,transform)
			count+=1
	_emit(world,root,batches,true)
	root.set_meta("tree_count",count)
	root.set_meta("terrain_extent",extent)
	_add_plants(world,root,farm)
	_add_rocks(world,root,farm)
	var mountains: Node3D=load("res://scripts/world/distant_mountains.gd").new()
	root.add_child(mountains);mountains.call("build",world,farm)

static func _distance(point: Vector2,rect: Rect2) -> float:
	return Vector2(maxf(maxf(rect.position.x-point.x,point.x-rect.end.x),0),maxf(maxf(rect.position.y-point.y,point.y-rect.end.y),0)).length()

static func _terrain_allowed(point: Vector2,farm: bool) -> bool:
	if farm:return not LakesideLayout.BOUNDS.grow(1.0).has_point(point)
	for rect: Rect2 in FoliageBackdrop.PLAY_RECTS:
		if rect.grow(4).has_point(point):return false
	if WorldBuilder.EXIT_CUT.grow(5).has_point(point):return false
	if Rect2(-160,-21,115,22).has_point(point):return false
	return true

static func _tree_allowed(point: Vector2,farm: bool) -> bool:
	if farm:
		if LakesideLayout.BOUNDS.grow(7).has_point(point):return false
		if point.x < -20 and absf(point.y-FarmBuilder.LANE_Z)<9:return false
		if point.x < -30 and LakesideLayout.water_distance(point)<7.0:return false
		return true
	if point.x < -52 and absf(point.y+11)<10:return false
	if not _terrain_allowed(point,false):return false
	for rect: Rect2 in FoliageBackdrop.PLAY_RECTS:
		if rect.grow(12).has_point(point):return false
	return not WorldBuilder.EXIT_CUT.grow(12).has_point(point)

static func _rise(point: Vector2,farm: bool) -> float:
	var rolling: float=2.8+2.1*sin(point.x*.021+point.y*.012)+1.7*cos(point.y*.029-point.x*.015)
	if farm:
		var existing:=Rect2(-66,-69,249,189)
		if existing.has_point(point):return LakesideLayout.height_at(point)-.02
		var edge_point:=Vector2(clampf(point.x,existing.position.x,existing.end.x),clampf(point.y,existing.position.y,existing.end.y))
		var ground: float=lerpf(LakesideLayout.height_at(edge_point)-.02,rolling,smoothstep(0.0,50.0,point.distance_to(edge_point)))
		if point.x < -66:
			var river_distance: float=absf(point.y-LakesideLayout.river_z(point.x))-LakesideLayout.river_half(point.x)
			ground=lerpf(-.85,ground,smoothstep(1.5,7.0,river_distance))
		return ground
	if point.x < -52 and absf(point.y+11)<10:return -.04
	var existing:=Rect2(FoliageBackdrop.OUTER_ORIGIN,FoliageBackdrop.OUTER_SIZE)
	if existing.has_point(point):return FoliageBackdrop.height_at(point)-.04
	return lerpf(-.07,rolling,smoothstep(0.0,55.0,_distance(point,existing)))

static func height_at(point: Vector2,farm: bool) -> float:
	# Match the exact rendered 4 m triangles, including points on chunk seams.
	var origin:=Vector2(floorf(point.x/4),floorf(point.y/4))*4.0
	var f: Vector2=(point-origin)/4.0
	var a: float=_rise(origin,farm)
	var b: float=_rise(origin+Vector2(0,4),farm)
	var c: float=_rise(origin+Vector2(4,4),farm)
	var d: float=_rise(origin+Vector2(4,0),farm)
	return a*(1-f.y)+b*(f.y-f.x)+c*f.x if f.y>=f.x else a*(1-f.x)+c*f.y+d*(f.x-f.y)

static func _terrain_tile(root: Node3D,origin: Vector2,farm: bool,material: Material) -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:=0
	for z in 8:
		for x in 8:
			var p: Vector2=origin+Vector2(x,z)*4.0
			if not _terrain_allowed(p+Vector2(2,2),farm):continue
			var corners: Array[Vector2]=[p,p+Vector2(0,4),p+Vector2(4,4),p+Vector2(4,0)]
			for index: int in [0,2,1,0,3,2]:
				var v: Vector2=corners[index];st.set_uv(v*.1);st.add_vertex(Vector3(v.x,_rise(v,farm),v.y))
			count+=1
	if count==0:return
	st.generate_normals()
	var mesh:=MeshInstance3D.new();mesh.name="Land_%d_%d"%[int(origin.x),int(origin.y)];mesh.mesh=st.commit();mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(mesh)

static func _queue(batches: Dictionary,id: String,transform: Transform3D) -> void:
	var chunk: float=64.0 if id.begins_with("T") else TILE
	var key: String="%s|%d|%d"%[id,int(floorf(transform.origin.x/chunk)),int(floorf(transform.origin.z/chunk))]
	if not batches.has(key):batches[key]={"id":id,"transforms":[]}
	batches[key].transforms.append(transform)

static func _emit(world: WorldBuilder,root: Node3D,batches: Dictionary,trees: bool) -> void:
	var templates: Dictionary={}
	var quiet_materials: Dictionary={}
	for key: String in batches:
		var batch: Dictionary=batches[key]
		var id: String=batch.id
		if not templates.has(id):
			# Assets enter via the same import/material path as every other prop.
			var template: Node3D=world.spawn(id,Vector3.ZERO,0,0,root)
			if template==null:continue
			template.visible=false;templates[id]=template
		var template: Node3D=templates[id]
		var transforms: Array=batch.transforms
		for part: MeshInstance3D in WorldBuilder.find_meshes(template):
			var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=part.mesh;mm.instance_count=transforms.size()
			var relative: Transform3D=template.global_transform.affine_inverse()*part.global_transform
			for i in transforms.size():mm.set_instance_transform(i,transforms[i]*relative)
			var node:=MultiMeshInstance3D.new();node.name="Batch_%d"%root.get_child_count();node.multimesh=mm
			# A surface-specific mesh retains leaf/trunk overrides; no material
			# state is written back into the cached original resource.
			var copied: Mesh=part.mesh.duplicate()
			for surface in copied.get_surface_count():copied.surface_set_material(surface,part.get_active_material(surface))
			mm.mesh=copied
			if trees:
				for surface in copied.get_surface_count():
					var foliage:=copied.surface_get_material(surface) as ShaderMaterial
					if foliage!=null:
						var material_key: int=foliage.get_instance_id()
						if not quiet_materials.has(material_key):
							var quiet:=foliage.duplicate() as ShaderMaterial
							quiet.set_shader_parameter("meadow_foliage",int(quiet.get_shader_parameter("part_role"))==1)
							quiet_materials[material_key]=quiet
						copied.surface_set_material(surface,quiet_materials[material_key])
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if trees else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			node.set_meta("submitted_transforms",transforms);node.set_meta("part_transform",relative)
			node.set_meta("library_id",id);node.set_meta("landscape_tree",trees);root.add_child(node)
	for template: Node3D in templates.values():template.free()

static func _add_plants(world: WorldBuilder,root: Node3D,farm: bool) -> void:
	var batches: Dictionary={}
	var rng:=RandomNumberGenerator.new();rng.seed=121026+int(farm)
	for index in 520:
		var point:=Vector2(rng.randf_range(-75,175) if farm else rng.randf_range(-100,95),rng.randf_range(-70,105) if farm else rng.randf_range(-65,130))
		if not _terrain_allowed(point,farm):continue
		var id: String=PLANTS[index%PLANTS.size()]
		var scale_f: float=rng.randf_range(.8,1.35)*(.3 if id=="V11_fallen_leaf" else 1.0)
		_queue(batches,id,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_f),Vector3(point.x,height_at(point,farm)+.015,point.y)))
	_emit(world,root,batches,false)
	root.set_meta("plant_varieties",PLANTS.size())

static func _add_rocks(world: WorldBuilder,root: Node3D,farm: bool) -> void:
	for index in 5:
		var point: Vector2=Vector2(45+index*24,-68-index%2*14) if farm else Vector2(-115+index*48,-74-index%2*14)
		var rock: Node3D=world.spawn("V19_distant_cliff",Vector3(point.x,height_at(point,farm)-.3,point.y),float(index)*71,0,root,.7+index*.12)
		if rock:rock.name="DistantCliff_%d"%index

static func build_garden(world: WorldBuilder,house: Node3D,floor_y: float=HouseBuilder.GROUND_Y,add_ground: bool=false) -> void:
	var root:=Node3D.new();root.name="GardenTreeCoverage";house.add_child(root)
	if add_ground:
		var ground:=MeshInstance3D.new();ground.name="ContextGround"
		var plane:=PlaneMesh.new();plane.size=Vector2(560,560);ground.mesh=plane;ground.position.y=floor_y-.03
		var material:=ShaderMaterial.new();material.shader=load("res://shaders/distant_meadow.gdshader");ground.material_override=material;ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(ground)
	var batches: Dictionary={}
	var rng:=RandomNumberGenerator.new();rng.seed=912610
	for z: int in range(-200,201,14):
		for x: int in range(-200,201,14):
			var point:=Vector2(x+rng.randf_range(-3,3),z+rng.randf_range(-3,3))
			if Rect2(-18,-16,36,35).has_point(point):continue
			if rng.randf()<.3:continue
			var scale_f: float=rng.randf_range(.7,1.2)
			_queue(batches,WorldBuilder.NEAR_TREES[rng.randi()%3],Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_f),Vector3(point.x,floor_y-.02,point.y)))
	_emit(world,root,batches,true)

static func capture_views() -> Dictionary:
	var views: Dictionary={}
	for farm: bool in [false,true]:
		var points: Array[Vector2]=[Vector2(-48,-20),Vector2(41,-11),Vector2(-46,26),Vector2(39,79)]
		if farm:points=[Vector2(-28,-15),Vector2(22,-13),Vector2(139,15),Vector2(113,54)]
		for point_index in points.size():
			var point: Vector2=points[point_index]
			for angle_index in 8:
				var direction:=Vector2(cos(angle_index*TAU/8),sin(angle_index*TAU/8))
				for high: bool in [false,true]:
					var id: String="coverage_%s_%d_%d_%s"%["farm" if farm else "town",point_index,angle_index,"high" if high else "low"]
					views[id]={"fov":85.0 if high else 50.0,"farm":farm,"player":Vector3(point.x,.1,point.y),"time":10.5,"camera_at":Vector3(point.x,24 if high else 2.2,point.y),"camera_focus":Vector3(point.x+direction.x*50,1 if high else 2,point.y+direction.y*50)}
	views["library_town"]={"player":Vector3(12,.1,15),"time":10.5,"camera_at":Vector3(12.5,2.2,12),"camera_focus":Vector3(15.7,.5,14.5)}
	views["library_farm"]={"farm":true,"player":Vector3(-9,.1,-2),"time":10.5,"camera_at":Vector3(-6,2.0,-2),"camera_focus":Vector3(-9.5,.35,-4.4)}
	views["library_fern"]={"player":Vector3(-10,.1,20),"time":10.5,"camera_at":Vector3(-10.3,1.2,20.6),"camera_focus":Vector3(-11.8,.25,21.6)}
	views["library_cloth"]={"farm":true,"player":Vector3(79,.1,52),"time":16,"camera_at":Vector3(78,3,51),"camera_focus":Vector3(80.5,.4,54.5)}
	for weather: String in ["rain","sunny"]:
		for hour: float in [6.5,17.3,21.0]:
			for farm: bool in [false,true]:
				var at:=Vector3(110,2.0,53) if farm else Vector3(37,2.0,73)
				var id: String="coverage_%s_%s_%d"%["farm" if farm else "town",weather,int(hour*10)]
				views[id]={"farm":farm,"weather":weather,"time":hour,"player":at,"camera_at":at,"camera_focus":at+Vector3(20,0,35)}
	views["library_carton"]={"player":Vector3(12,.1,4),"time":10.5,"camera_at":Vector3(12.5,1.2,5),"camera_focus":Vector3(14.0,.25,3.5)}
	views["library_bucket_close"]={"player":Vector3(14,.1,12),"time":10.5,"camera_at":Vector3(15.8,.95,13.4),"camera_focus":Vector3(16.45,.20,13.85)}
	var plant_points: Array[Vector2]=[Vector2(-24,8),Vector2(-22.5,8.5),Vector2(-19,10),Vector2(-23.5,10.7),Vector2(20,-10),Vector2(-15.5,-7.5),Vector2(4.9,4.2),Vector2(133,46),Vector2(135,39),Vector2(22,6)]
	for index in plant_points.size():
		var p: Vector2=plant_points[index]
		var ground: float=LakesideLayout.height_at(p)
		views["plant_%02d"%index]={"farm":true,"player":Vector3(p.x-2,.1,p.y),"time":10.5,"camera_at":Vector3(p.x+1.25,ground+.95,p.y+1.25),"camera_focus":Vector3(p.x,ground+.25,p.y)}
	for high: bool in [false,true]:
		views["context_home_photo_"+("high" if high else "low")]={"house":Vector3(1,0,-3),"face":180.0,"pitch":40.0,"dist":8.0,"time":10.5,"house_photo":true,"house_camera":Vector3(1,24 if high else 2,-7),"house_focus":Vector3(0,0,-60)}
	for kind: String in ["store","bakery","workroom"]:
		views["context_"+kind+"_window"]={"interior":kind,"at":Vector3(0,.05,1),"time":10.5,"inside_camera":Vector3(0,1.7,1.6),"inside_focus":Vector3(7,1.7,1.6)}
	return views
