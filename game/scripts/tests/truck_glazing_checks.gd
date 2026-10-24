extends RefCounted
## Built-instance geometry checks. Native front/side/night images remain the visual authority.
var t: Object
var main: Node
var faces_cache: Dictionary={}
const PANES := ["Glass_Windshield","Glass_Left","Glass_Right","Glass_Rear"]
const TYRES := ["Tyre_Front_Left","Tyre_Front_Right","Tyre_Rear_Left","Tyre_Rear_Right"]
# 5x5 pixel means from the predecessor's actual 2048px diffuse atlas, at a 4x4 UV grid.
# Re-encoding/compression is allowed; replacing the good cargo texture with flat paint is not.
const ATLAS := [Vector3(.4264,.4111,.4342),Vector3(.9465,.9398,.9310),Vector3(.5004,.4913,.4905),Vector3(.9506,.9445,.9523),Vector3(.7151,.4649,.1550),Vector3(.7856,.6322,.4723),Vector3(.7355,.4764,.1725),Vector3(.1600,.1667,.1882),Vector3(.1655,.1694,.1898),Vector3(.5867,.6002,.6450),Vector3(.7868,.6500,.4609),Vector3(.8712,.8510,.8124),Vector3(.9569,.9529,.9404),Vector3(.5410,.5434,.5473),Vector3(.2919,.2822,.2861),Vector3(.7898,.3010,.0515)]

func _init(runner: Object) -> void:
	t=runner;main=runner.main

func check(label: String,failures: Array[String]) -> void:
	t.check("TRUCK_GLAZING",label,failures.is_empty(),str(failures))

func run() -> void:
	var trucks: Array[Node3D]=[]
	for node: Node in main.world.find_children("*","Node3D",true,false):
		if node.get_meta("model_id","")=="D07_kei_truck":trucks.append(node as Node3D)
	var errors: Array[String]=[]
	if trucks.size()!=2:errors.append("actual D07 instances=%d"%trucks.size())
	check("town approach and farm each contain one actual truck",errors)
	var dimensions: Array[String]=[];var glazing: Array[String]=[];var holes: Array[String]=[];var interiors: Array[String]=[]
	var wheels: Array[String]=[];var textures: Array[String]=[];var cargo_shape: Array[String]=[];var solids: Array[String]=[]
	var formed_body: Array[String]=[]
	for truck: Node3D in trucks:
		var label: String="farm" if truck.global_position.x>600 else "town"
		var bounds: AABB=WorldBuilder.local_aabb(truck)
		if bounds.size.x>2.05 or bounds.size.x<1.4 or bounds.size.z>3.50 or bounds.size.z<3.25 or bounds.size.y>1.89 or bounds.size.y<1.7:dimensions.append("%s real XYZ=%s"%[label,bounds.size])
		var all: Array[MeshInstance3D]=WorldBuilder.find_meshes(truck)
		formed_body.append_array(_formed_body_errors(truck,all,label))
		var wind: MeshInstance3D=_named(all,"Glass_Windshield")
		for pane_name: String in PANES:
			var pane: MeshInstance3D=_named(all,pane_name)
			if pane==null or _area(pane)<.20 or not _transparent(pane):
				glazing.append(label+" "+pane_name+" lacks real translucent surface");holes.append(label+" "+pane_name+" has no inspectable aperture");continue
			var points: Array[Vector3]=_pane_points(pane)
			var normal: Vector3=_outward(pane,truck)
			for point: Vector3 in points:
				var aperture_hit: Dictionary=_first_opaque(all,point+normal*.20,point-normal*.20,true)
				if not aperture_hit.is_empty():holes.append("%s %s blocked by %s %.3fm behind glazing"%[label,pane_name,aperture_hit.mesh.name,point.distance_to(aperture_hit.at)]);break
		for interior_name: String in ["Seat_Left","Seat_Right","Seatback_Left","Seatback_Right","SteeringWheel"]:
			var piece: MeshInstance3D=_named(all,interior_name)
			if piece==null or _area(piece)<.025:interiors.append(label+" missing actual interior surface "+interior_name);continue
			if interior_name.begins_with("Seatback") or interior_name=="SteeringWheel":
				if wind==null:interiors.append(label+" cannot look through an actual windshield");continue
				var start: Vector3=wind.global_transform*wind.get_aabb().get_center()+_outward(wind,truck)*.45
				var target: Vector3=piece.global_transform*piece.get_aabb().get_center()
				if interior_name=="SteeringWheel":
					var vertices: PackedVector3Array=_faces(piece)
					target=piece.to_global((vertices[0]+vertices[1]+vertices[2])/3.0)
				var interior_hit: Dictionary=_first_opaque(all,start,target)
				var world_box: AABB=piece.global_transform*piece.get_aabb()
				if not interior_hit.is_empty() and not world_box.grow(.10).has_point(interior_hit.at):interiors.append("%s %s hidden by %s"%[label,interior_name,interior_hit.mesh.name])
		var centres: Array[Vector3]=[]
		for tyre_name: String in TYRES:
			var tyre: MeshInstance3D=_named(all,tyre_name)
			if tyre==null or _area(tyre)<.30:wheels.append(label+" missing physical tyre "+tyre_name);continue
			var tyre_box: AABB=tyre.global_transform*tyre.get_aabb();var centre: Vector3=tyre_box.get_center();centres.append(truck.to_local(centre))
			var ground: Dictionary=main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(centre+Vector3.UP,centre-Vector3.UP*1.5,WorldBuilder.L_GROUND))
			if ground.is_empty() or absf(tyre_box.position.y-(ground.position as Vector3).y)>.025:wheels.append("%s %s bottom=%0.4f ground=%s"%[label,tyre_name,tyre_box.position.y,ground.get("position","missing")])
		if centres.size()==4:
			for a: int in centres.size():
				for b: int in range(a+1,centres.size()):
					if centres[a].distance_to(centres[b])<1.0:wheels.append(label+" tyre positions duplicate or axles collapse")
		var cargo: MeshInstance3D=_named(all,"TexturedBedAndCargo")
		if cargo==null:
			textures.append(label+" no retained textured bed/cargo mesh");cargo_shape.append(label+" no retained cargo geometry")
		else:
			var cargo_local: AABB=truck.global_transform.affine_inverse()*cargo.global_transform*cargo.get_aabb()
			if cargo_local.end.z>.201 or cargo_local.position.y<.56 or cargo_local.size.y<.65 or _faces(cargo).size()<4500:cargo_shape.append("%s retained bounds=%s triangles=%d"%[label,cargo_local,_faces(cargo).size()/3])
			var image: Image=_cargo_image(cargo)
			if image==null or image.get_width()<1024:textures.append(label+" actual cargo material lost its original large diffuse atlas")
			else:
				if image.is_compressed():image.decompress()
				var error: float=_atlas_error(image)
				var arrays: Array=cargo.mesh.surface_get_arrays(0);var uv: PackedVector2Array=[]
				if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:uv=arrays[Mesh.ARRAY_TEX_UV]
				if error>.10 or uv.size()<1500:textures.append("%s original atlas mean RGB error=%.4f real UV entries=%d"%[label,error,uv.size()])
		var solid_probe:=PhysicsShapeQueryParameters3D.new();solid_probe.shape=NPC.MOTION_ROUTE.capsule();solid_probe.exclude=[main.player.get_rid()]
		solid_probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED;solid_probe.transform=Transform3D(Basis.IDENTITY,truck.global_position+Vector3.UP*.8)
		if main.get_world_3d().direct_space_state.intersect_shape(solid_probe,1).is_empty():solids.append(label+" truck centre has no actual solid body")
	check("real dimensions retain the compact street footprint",dimensions)
	check("all eight actual panes use translucent untextured glazing",glazing)
	check("window sight segments are not sealed by opaque predecessor or body faces",holes)
	check("actual seat backs and steering are visible through the windshield",interiors)
	check("four separate tyres per truck meet rendered physical ground",wheels)
	check("roof crown, rounded tyre shoulders and four rolled arches use actual shaped surfaces",formed_body)
	check("retained cargo material preserves the predecessor diffuse atlas and UVs",textures)
	check("retained textured cargo stays behind the cab and above the rebuilt chassis",cargo_shape)
	check("the rebuilt vehicle still blocks an ordinary player capsule",solids)
	var routes: Array[String]=[]
	for segment: Array in [[Vector3(31,.02,-10.8),Vector3(37,.02,-10.8)],[FarmBuilder.ORIGIN+Vector3(-13,.02,.3),FarmBuilder.ORIGIN+Vector3(-7,.02,.3)]]:
		var lane_probe:=PhysicsShapeQueryParameters3D.new();lane_probe.shape=NPC.MOTION_ROUTE.capsule();lane_probe.exclude=[main.player.get_rid()]
		lane_probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_BLOCK;lane_probe.transform=Transform3D(Basis.IDENTITY,segment[0]+Vector3.UP*.8)
		lane_probe.motion=segment[1]-segment[0]
		var sweep: PackedFloat32Array=main.get_world_3d().direct_space_state.cast_motion(lane_probe)
		if not main.get_world_3d().direct_space_state.intersect_shape(lane_probe,1).is_empty() or sweep[0]<.999:routes.append("%s to %s fraction=%s"%[segment[0],segment[1],sweep])
	check("both existing pedestrian lanes remain clear for a full capsule sweep",routes)

func _formed_body_errors(truck: Node3D,meshes: Array[MeshInstance3D],label: String) -> Array[String]:
	var errors: Array[String]=[]
	var roof_heights: Array[float]=[]
	for x: float in [0.0,-.58,.58]:
		var roof_hit: Dictionary=_first_opaque(meshes,truck.to_global(Vector3(x,2,.83)),truck.to_global(Vector3(x,1.73,.83)))
		if roof_hit.is_empty():roof_heights.append(0.0)
		else:roof_heights.append(truck.to_local(roof_hit.at as Vector3).y)
	if roof_heights[0]-maxf(roof_heights[1],roof_heights[2])<.018:errors.append(label+" roof is a flat slab: "+str(roof_heights))
	for tyre_name: String in TYRES:
		var tyre: MeshInstance3D=_named(meshes,tyre_name)
		if tyre==null:errors.append(label+" missing shaped tyre "+tyre_name);continue
		var local_transform: Transform3D=truck.global_transform.affine_inverse()*tyre.global_transform
		var local_box: AABB=local_transform*tyre.get_aabb()
		var centre: Vector3=local_box.get_center()
		var half_width: float=local_box.size.x*.5
		var middle_radius: float=0.0;var outer_radius: float=0.0
		for vertex: Vector3 in _faces(tyre):
			var offset: Vector3=local_transform*vertex-centre
			var radius: float=Vector2(offset.y,offset.z).length()
			if absf(offset.x)<half_width*.30:middle_radius=maxf(middle_radius,radius)
			if absf(offset.x)>half_width*.88:outer_radius=maxf(outer_radius,radius)
		if middle_radius-outer_radius<.025:errors.append("%s %s flat sidewall radii=%s/%s"%[label,tyre_name,middle_radius,outer_radius])
	for side: float in [-1.0,1.0]:
		for axle: String in ["Front","Rear"]:
			var arch_name: String="WheelArch_"+axle+("_Left" if side<0 else "_Right")
			var arch: MeshInstance3D=_named(meshes,arch_name)
			if arch==null:errors.append(label+" missing rolled arch "+arch_name);continue
			var axle_z: float=1.075 if axle=="Front" else -1.11
			var arch_meshes: Array[MeshInstance3D]=[arch]
			for degrees: float in [25.0,55.0,90.0,125.0,155.0]:
				var angle: float=deg_to_rad(degrees)
				var at: Vector3=Vector3(side,.325+.365*sin(angle),axle_z+.365*cos(angle))
				var end: Vector3=Vector3(side*.60,at.y,at.z)
				if _first_opaque(arch_meshes,truck.to_global(at),truck.to_global(end)).is_empty():
					errors.append("%s %s has no physical lip at %s degrees"%[label,arch_name,degrees])
	return errors

func _named(meshes: Array[MeshInstance3D],label: String) -> MeshInstance3D:
	for mesh: MeshInstance3D in meshes:
		if str(mesh.name)==label:return mesh
	return null

func _faces(mesh: MeshInstance3D) -> PackedVector3Array:
	if not faces_cache.has(mesh):faces_cache[mesh]=mesh.mesh.get_faces()
	return faces_cache[mesh]

func _area(mesh: MeshInstance3D) -> float:
	var vertices: PackedVector3Array=_faces(mesh);var area:=0.0
	for index: int in range(0,vertices.size(),3):area+=(mesh.to_global(vertices[index+1])-mesh.to_global(vertices[index])).cross(mesh.to_global(vertices[index+2])-mesh.to_global(vertices[index])).length()*.5
	return area

func _transparent(mesh: MeshInstance3D) -> bool:
	for surface: int in mesh.mesh.get_surface_count():
		var material: Material=mesh.get_active_material(surface)
		if material is ShaderMaterial:
			var shader: Shader=(material as ShaderMaterial).shader
			if shader==null or shader.resource_path!="res://shaders/truck_glass.gdshader" or not shader.code.contains("ALPHA") or not shader.code.contains("blend_mix"):return false
		elif material is StandardMaterial3D:
			if material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_color.a>.40 or material.albedo_texture!=null:return false
		else:return false
	return true

func _outward(mesh: MeshInstance3D,truck: Node3D) -> Vector3:
	var vertices: PackedVector3Array=_faces(mesh)
	var normal: Vector3=(mesh.to_global(vertices[1])-mesh.to_global(vertices[0])).cross(mesh.to_global(vertices[2])-mesh.to_global(vertices[0])).normalized()
	var centre: Vector3=mesh.global_transform*mesh.get_aabb().get_center()
	if normal.dot(centre-truck.to_global(Vector3(0,1.4,.8)))<0:normal=-normal
	return normal

func _pane_points(mesh: MeshInstance3D) -> Array[Vector3]:
	var vertices: PackedVector3Array=_faces(mesh);var points: Array[Vector3]=[]
	for index: int in range(0,vertices.size(),3):
		for weights: Vector3 in [Vector3(.2,.4,.4),Vector3(.4,.2,.4),Vector3(.4,.4,.2)]:points.append(mesh.to_global(vertices[index]*weights.x+vertices[index+1]*weights.y+vertices[index+2]*weights.z))
	return points

func _first_opaque(meshes: Array[MeshInstance3D],start: Vector3,finish: Vector3,skip_interior: bool=false) -> Dictionary:
	var best: Dictionary={};var distance:=INF
	for mesh: MeshInstance3D in meshes:
		if _transparent(mesh):continue
		if skip_interior and (str(mesh.name).begins_with("Seat") or str(mesh.name).begins_with("Headrest") or str(mesh.name)=="SteeringWheel"):continue
		var inverse: Transform3D=mesh.global_transform.affine_inverse();var a: Vector3=inverse*start;var b: Vector3=inverse*finish
		if mesh.get_aabb().intersects_segment(a,b)==null:continue
		var vertices: PackedVector3Array=_faces(mesh)
		for index: int in range(0,vertices.size(),3):
			var hit: Variant=Geometry3D.segment_intersects_triangle(a,b,vertices[index],vertices[index+1],vertices[index+2])
			if hit==null:continue
			var at: Vector3=mesh.to_global(hit as Vector3);var d: float=start.distance_to(at)
			if d<distance:distance=d;best={"mesh":mesh,"at":at,"distance":d}
	return best

func _cargo_image(mesh: MeshInstance3D) -> Image:
	for surface: int in mesh.mesh.get_surface_count():
		var material: Material=mesh.get_active_material(surface)
		if material is StandardMaterial3D and material.albedo_texture!=null:return material.albedo_texture.get_image()
	return null

func _atlas_error(image: Image) -> float:
	var error:=0.0
	for row: int in 4:
		for column: int in 4:
			var x: int=int((.125+column*.25)*image.get_width());var y: int=int((.125+row*.25)*image.get_height());var mean:=Vector3.ZERO
			for dy: int in range(-2,3):
				for dx: int in range(-2,3):
					var pixel: Color=image.get_pixel(x+dx,y+dy);mean+=Vector3(pixel.r,pixel.g,pixel.b)
			mean/=25.0;var delta: Vector3=(mean-ATLAS[row*4+column]).abs();error+=(delta.x+delta.y+delta.z)/3.0
	return error/16.0
