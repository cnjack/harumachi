class_name LakesideBuilder
extends Node3D
## Continuous extension of the allotment: one terrain and one connected water body.
var wb: WorldBuilder
var water_mat: ShaderMaterial
var ground_mesh: MeshInstance3D
var shore_bodies: Array[StaticBody3D] = []
var _serial := 0

func build(world: WorldBuilder) -> void:
	wb = world
	name = "Lakeside"
	_terrain()
	_water()
	_creek_stones()
	_paths_and_shores()
	_barriers()
	_deck()
	_greenery()
	_rest_places()
	_meadow()
	_seat_pier_marker.call_deferred()

func _seat_pier_marker() -> void:
	await get_tree().physics_frame
	var marker:=get_node_or_null("Fishing_marker_fish_pier") as MeshInstance3D
	if marker==null:return
	var p:Vector2=LakesideLayout.SPOTS["fish_pier"].stand
	var start:=global_position+Vector3(p.x,4,p.y)
	var query:=PhysicsRayQueryParameters3D.create(start,start-Vector3(0,8,0),WorldBuilder.L_GROUND)
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():marker.global_position.y=(hit.position as Vector3).y+.03

func _terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 1.5
	for ix in 166:
		for iz in 126:
			var x := -66.0 + float(ix) * step
			var z := -69.0 + float(iz) * step
			var near_water: bool=absf(LakesideLayout.water_distance(Vector2(x+step*.5,z+step*.5)))<5.0
			var divisions: int=3 if near_water else 1
			for cell_x: int in range(divisions):
				for cell_z: int in range(divisions):
					_terrain_cell(st,x+float(cell_x)*step/float(divisions),z+float(cell_z)*step/float(divisions),step/float(divisions))
	st.index()
	ground_mesh = MeshInstance3D.new()
	ground_mesh.name = "Continuous_walkable_terrain"
	ground_mesh.mesh = st.commit()
	var material := WorldBuilder.ground_material("grass")
	material.set_shader_parameter("feather",0.0)
	material.set_shader_parameter("lawn_mix",.64)
	material.set_shader_parameter("landscape_contours",true)
	material.set_shader_parameter("terrain_origin",FarmBuilder.ORIGIN)
	ground_mesh.material_override = material
	ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground_mesh)
	var distance_ground:=MeshInstance3D.new()
	distance_ground.name="Distant_grass_land"
	var distance_plane:=PlaneMesh.new();distance_plane.size=Vector2(1000,1000)
	distance_ground.mesh=distance_plane;distance_ground.material_override=material
	distance_ground.position=Vector3(55,-1.4,20)
	distance_ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(distance_ground)
	var body := StaticBody3D.new()
	body.name = "Terrain_collision"
	body.collision_layer = WorldBuilder.L_GROUND
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = ground_mesh.mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)

func _terrain_cell(st: SurfaceTool,x: float,z: float,step: float) -> void:
	var points: Array[Vector2]=[Vector2(x,z),Vector2(x,z+step),Vector2(x+step,z+step),Vector2(x+step,z)]
	for corner: int in [0,2,1,0,3,2]:
		var point: Vector2=points[corner]
		st.set_uv(point/5.0)
		var dx: float=LakesideLayout.height_at(point-Vector2(.1,0))-LakesideLayout.height_at(point+Vector2(.1,0))
		var dz: float=LakesideLayout.height_at(point-Vector2(0,.1))-LakesideLayout.height_at(point+Vector2(0,.1))
		st.set_normal(Vector3(dx,.2,dz).normalized())
		st.add_vertex(Vector3(point.x,LakesideLayout.height_at(point),point.y))

func _water() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-66,0,-69),Vector3(-66,0,120),Vector3(183,0,120),Vector3(183,0,-69)]
	for i: int in [0,2,1,0,3,2]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(points[i].x,points[i].z))
		st.add_vertex(points[i])
	var water := MeshInstance3D.new()
	water.name = "Connected_lake_and_river"
	water.mesh = st.commit()
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/lakeside_water.gdshader")
	water_mat.set_shader_parameter("shallow_opacity",.62)
	for sky_time in ["day","dusk","night"]:
		water_mat.set_shader_parameter("sky_"+sky_time,load("res://assets/textures/"+("sky_equirect.jpg" if sky_time=="day" else "sky_"+sky_time+".jpg")))
	water.material_override = water_mat
	water.position.y = LakesideLayout.WATER_Y
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func _ribbon(points: PackedVector2Array, width: float, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 0.0
	for i in points.size()-1:
		var a := points[i]
		var b := points[i+1]
		var middle: Vector2=(a+b)*.5
		var irregular_width: float=width*(.93+.055*sin(middle.x*.47+middle.y*.21)+.035*cos(middle.y*.79-middle.x*.13))
		var normal := Vector2(-(b-a).y,(b-a).x).normalized()*irregular_width*.5
		var count := maxi(1,ceili(a.distance_to(b)/1.0))
		for j in count:
			var start := a.lerp(b,float(j)/float(count))
			var end := a.lerp(b,float(j+1)/float(count))
			var corners := [start-normal,start+normal,end+normal,end-normal]
			var uv := [Vector2(0,length),Vector2(1,length),Vector2(1,length+1),Vector2(0,length+1)]
			for k: int in [0,2,1,0,3,2]:
				var p: Vector2 = corners[k]
				st.set_normal(Vector3.UP)
				st.set_uv(uv[k])
				st.add_vertex(Vector3(p.x,LakesideLayout.height_at(p)+.024,p.y))
			length+=start.distance_to(end)
	var mesh := MeshInstance3D.new()
	mesh.name = "Shore_or_path_%d" % _serial
	_serial+=1
	mesh.mesh = st.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _paths_and_shores() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/lakeside_path.gdshader")
	material.set_shader_parameter("albedo_tex",load("res://assets/textures/lakeside_polish/path.png"))
	material.set_shader_parameter("wear_strength",.30)
	for route: PackedVector2Array in LakesideLayout.walk_paths():
		_ribbon(route,2.6,material)
	var shore := LakesideLayout.lake_outline(120,.7)
	shore.append(shore[0])
	_ribbon(shore,1.7,material)
	for side in [-1.0,1.0]:
		var bank := PackedVector2Array()
		for i in 73:
			var x := -66.0 + i*2.0
			bank.append(Vector2(x,LakesideLayout.river_z(x)+side*(LakesideLayout.river_half(x)+.7)))
		_ribbon(bank,.82,material)

func _barrier(a: Vector2,b: Vector2) -> void:
	var body := StaticBody3D.new()
	body.name = "Water_edge_%d" % _serial
	_serial+=1
	body.collision_layer = WorldBuilder.L_BLOCK
	body.collision_mask = 0
	body.set_meta("shore_barrier",true)
	var mid := (a+b)*.5
	body.position = Vector3(mid.x,1.1,mid.y)
	body.rotation.y = atan2(-(b-a).y,(b-a).x)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(a.distance_to(b)+.06,3.0,.20)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	shore_bodies.append(body)

func _barriers() -> void:
	var outline := LakesideLayout.lake_outline(120,1.1)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var mid := (a+b)*.5
		# Water continues into the river; the only shore opening is the pier.
		if mid.x<76.0 and absf(mid.y-LakesideLayout.river_z(mid.x))<LakesideLayout.river_half(mid.x)+1.2:
			continue
		if absf(mid.x-94.0)<1.7 and mid.y>35.0:
			continue
		_barrier(a,b)
	for side in [-1.0,1.0]:
		for i in 52:
			var x := -30.0+i*2.0
			var a := Vector2(x,LakesideLayout.river_z(x)+side*(LakesideLayout.river_half(x)+1.0))
			var b := Vector2(x+2.0,LakesideLayout.river_z(x+2.0)+side*(LakesideLayout.river_half(x+2.0)+1.0))
			if x<1.3 and x+2.0> -1.3:
				# Split around the existing bank-to-bank bridge, not a four-metre gap.
				if x< -1.3:_barrier(a,Vector2(-1.3,a.y))
				if x+2.0>1.3:_barrier(Vector2(1.3,b.y),b)
				continue
			var q := ((a+b)*.5-LakesideLayout.LAKE_CENTER)/LakesideLayout.LAKE_RADII
			if q.length()<1.04:continue
			_barrier(a,b)

func _deck() -> void:
	# Reuse the hand-painted bridge asset as a small lakeside landing.
	var bridge := wb.spawn("P_bridge",Vector3(94,0,41),0,0,self)
	if bridge:
		LakesideMaterials.decorate_bridge(bridge)
		for mi in WorldBuilder.find_meshes(bridge):
			if str(mi.name).begins_with("deck") or str(mi.get_parent().name).begins_with("deck"):
				mi.visible=false
				var body := StaticBody3D.new()
				body.collision_layer=WorldBuilder.L_GROUND
				body.set_meta("model_part","P_bridge")
				var shape := CollisionShape3D.new()
				shape.shape=mi.mesh.create_trimesh_shape()
				body.add_child(shape)
				mi.add_child(body)
	_barrier(Vector2(93.0,35.9),Vector2(95.0,35.9))
	_barrier(Vector2(93.0,35.9),Vector2(93.0,46.0))
	_barrier(Vector2(95.0,35.9),Vector2(95.0,46.0))

func _greenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=1003
	var trees := [Vector2(33,-18),Vector2(50,-25),Vector2(69,-26),Vector2(85,-25),Vector2(109,-29),Vector2(129,-23),Vector2(141,-13),Vector2(146,5),Vector2(147,32),Vector2(138,49),Vector2(122,58),Vector2(103,60),Vector2(83,57),Vector2(64,49),Vector2(47,44),Vector2(32,37),Vector2(39,9),Vector2(60,-1),Vector2(79,-6),Vector2(114,-3)]
	for p: Vector2 in trees:
		if LakesideLayout.water_distance(p)<2.5:continue
		var tree := wb.spawn("T01_courtyard_tree",Vector3(p.x,LakesideLayout.height_at(p),p.y),rng.randf_range(-180,180),0,self,rng.randf_range(.9,1.25))
		if tree:
			WorldBuilder.rest_on_terrain(tree,LakesideLayout.height_at(p))
			wb._trunk_collider(tree,.35)
	var outline := LakesideLayout.lake_outline(64,1.8)
	for i in outline.size():
		var p := outline[i]
		if not ((i>=2 and i<=9) or (i>=23 and i<=30) or (i>=46 and i<=53)) or absf(p.x-94.0)<3.0 or LakesideLayout.path_distance(p)<1.8:continue
		p += Vector2(rng.randf_range(-.35,.35),rng.randf_range(-.35,.35))
		wb.spawn("D11_reeds",Vector3(p.x,LakesideLayout.height_at(p),p.y),rng.randf_range(0,360),0,self,rng.randf_range(.5,.8))
	for p: Vector2 in [Vector2(67,14),Vector2(124,42),Vector2(129,4),Vector2(78,36),Vector2(40,31)]:
		wb.spawn("D10_rocks",Vector3(p.x,LakesideLayout.height_at(p),p.y),rng.randf_range(0,360),0,self,.65)

func _rest_places() -> void:
	for p: Vector2 in [Vector2(78,-11),Vector2(114,47),Vector2(130,38)]:
		var toward := LakesideLayout.LAKE_CENTER-p
		var bench:=wb.spawn("A12_bench",Vector3(p.x,LakesideLayout.height_at(p),p.y),rad_to_deg(atan2(toward.x,toward.y)),1,self)
		if bench:WorldBuilder.rest_on_terrain(bench,LakesideLayout.height_at(p),0.0)
	var direction: Node3D=wb.spawn("P_signpost",Vector3(24,0,2.8),0,2,self,.85)
	if direction:LakesideMaterials.decorate_bridge(direction)
	_label("镜波湖  →\n沿河步道 · 钓鱼",Vector3(24,2.55,2.8),0)
	_label("晴町  ←",Vector3(72,2.2,-15.3),0)
	for id: String in LakesideLayout.SPOTS:
		var p: Vector2=LakesideLayout.SPOTS[id].stand
		var marker := MeshInstance3D.new()
		marker.name="Fishing_marker_"+id
		var ring := TorusMesh.new()
		ring.inner_radius=.40;ring.outer_radius=.46;ring.rings=20;ring.ring_segments=6
		marker.mesh=ring
		var material := StandardMaterial3D.new()
		material.albedo_color=Color(.80,.74,.43,.8)
		material.roughness=1.0
		marker.material_override=material
		marker.position=Vector3(p.x,.035 if id=="fish_pier" else LakesideLayout.height_at(p)+.035,p.y)
		add_child(marker)

func _creek_stones() -> void:
	var rng: RandomNumberGenerator=RandomNumberGenerator.new()
	rng.seed=1007
	var count: int=0
	for station: float in [-23.0,-17.0,-11.0,-6.5,7.5,12.5,18.5,24.0,35.0,42.0,59.0,67.0]:
		for bank: float in [-1.0,1.0]:
			var x: float=station+rng.randf_range(-.65,.65)
			var inward: float=rng.randf_range(.20,.70)
			var z: float=LakesideLayout.river_z(x)+bank*(LakesideLayout.river_half(x)-inward)
			var point: Vector2=Vector2(x,z)
			var clear: bool=true
			for spot_id: String in LakesideLayout.SPOTS:
				if point.distance_to(LakesideLayout.SPOTS[spot_id]["float"])<1.35:clear=false
			if not clear:continue
			if count>0 and rng.randf()<.16:continue
			var bottom: float=LakesideLayout.height_at(point)
			var rock: Node3D=wb.spawn("D10_rocks",Vector3(x,bottom,z),rng.randf_range(0,360),0,self,rng.randf_range(.52,.90))
			if rock:
				rock.scale.y*=rng.randf_range(.42,.62)
				rock.name="CreekStone_%02d"%count
				rock.set_meta("creek_stone",true)
				rock.set_meta("bed_point",point)
				LakesideMaterials.stone(rock,count)
				WorldBuilder.rest_on_terrain(rock,bottom,0.0)
				count+=1
	var lake_edge: PackedVector2Array=LakesideLayout.lake_outline(64,-.45)
	for shore_index: int in [2,7,12,18,24,30,37,43,50,57]:
		var shore_point: Vector2=lake_edge[shore_index]
		var lake_rock: Node3D=wb.spawn("D10_rocks",Vector3(shore_point.x,LakesideLayout.height_at(shore_point),shore_point.y),rng.randf_range(0,360),0,self,rng.randf_range(.58,.94))
		if lake_rock:
			lake_rock.scale.y*=rng.randf_range(.42,.62)
			lake_rock.name="CreekStone_%02d"%count
			lake_rock.set_meta("creek_stone",true)
			lake_rock.set_meta("bed_point",shore_point)
			LakesideMaterials.stone(lake_rock,count)
			count+=1
	set_meta("creek_stone_count",count)
	_seat_creek_stones.call_deferred()

func _seat_creek_stones() -> void:
	await get_tree().physics_frame
	for child: Node in get_children():
		if not child.has_meta("creek_stone"):continue
		var rock: Node3D=child as Node3D
		var point: Vector2=rock.get_meta("bed_point")
		var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(global_position+Vector3(point.x,2,point.y),global_position+Vector3(point.x,-6,point.y),WorldBuilder.L_GROUND)
		var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():WorldBuilder.rest_on(rock,(hit.position as Vector3).y,0.0)

func _label(text: String,p: Vector3,yaw: float) -> void:
	var label := Label3D.new()
	label.text=text;label.font=load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	label.font_size=44;label.pixel_size=.004
	label.modulate=Color(.98,.94,.79);label.outline_modulate=Color(.19,.29,.23);label.outline_size=7
	label.position=p;label.rotation.y=yaw;label.double_sided=true
	add_child(label)

func _meadow() -> void:
	var grass := GrassField.new()
	grass.name="Lakeside_meadow"
	add_child(grass)
	var height_fn := func(p:Vector2)->float:return LakesideLayout.height_at(p)
	var keep_fn := func(p:Vector2)->bool:return LakesideLayout.water_distance(p)>2.0 and LakesideLayout.path_distance(p)>1.45 and not (absf(p.x-94.0)<2.0 and p.y>35.0 and p.y<49.0)
	grass.lawn([[28,-34,142,62]],[],"meadow",1.5,1003,0.0,height_fn,keep_fn)
