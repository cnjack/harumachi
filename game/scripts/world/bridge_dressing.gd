extends Node3D
## Permanent small lanterns hang outside the handrails; the full deck stays clear.
const PLANTERS: Array[Vector3] = [Vector3(-1.85,0,9.5),Vector3(1.85,0,22.65)]

static func ground_exclusions() -> Array:
	var exclusions: Array=[]
	for at: Vector3 in PLANTERS:exclusions.append([Vector2(at.x,at.z),.70])
	return exclusions

func build(farm: FarmBuilder,bridge: Node3D) -> void:
	name="BridgeDressing"
	var wood: Material=SurfaceFinish.timber(AABB(Vector3(-.03,-.03,-.25),Vector3(.06,.06,.50)),Color(.50,.37,.24),2)
	var cord:=StandardMaterial3D.new();cord.albedo_color=Color(.35,.28,.20);cord.roughness=1.0
	var number: int=0
	for side: float in [-1.0,1.0]:
		for along: float in [-2.3,2.3]:
			var post:=Vector3(side*.90,0,17.0+along)
			var top: float=WorldBuilder.surface_height(bridge,Vector2(farm.global_position.x+post.x,farm.global_position.z+post.z),3.0)
			if not is_finite(top):continue
			top-=farm.global_position.y
			var mount:=Node3D.new();mount.name="LanternMount_%d"%number;add_child(mount)
			mount.set_meta("rail_contact",Vector3(post.x,top,post.z))
			var start:=Vector3(post.x,top+.025,post.z)
			var hook:=Vector3(side*1.30,top+.20,post.z)
			_beam(mount,"PostClamp",start,Vector3(post.x,hook.y,post.z),.055,wood)
			_beam(mount,"OutboardArm",Vector3(post.x,hook.y,post.z),hook,.055,wood)
			_beam(mount,"DiagonalBrace",start,hook,.034,wood)
			var handle: Vector3=hook-Vector3(0,.14,0)
			_beam(mount,"HangingCord",hook,handle,.008,cord)
			var lantern: Node3D=farm.wb.spawn("N24_bamboo_lantern",handle-Vector3(0,.40,0),0.0,0,mount)
			if lantern:
				lantern.name="BridgeLantern_%d"%number
				mount.set_meta("handle_contact",handle)
				for light: OmniLight3D in lantern.find_children("*","OmniLight3D",true,false):
					light.light_energy=0.0;light.omni_range=2.0;light.set_meta("outdoor_energy_scale",.35);farm.lamp_lights.append(light)
			number+=1
	for index: int in PLANTERS.size():
		var at: Vector3=PLANTERS[index]
		var pot: Node3D=farm.wb.spawn("V21_white_hydrangea",at,35.0 if index==0 else -145.0,0,self)
		if pot:
			pot.name="BridgePlanter_%d"%index
			WorldBuilder.rest_on_terrain(pot,LakesideLayout.height_at(Vector2(at.x,at.z)),.008)
			var body: StaticBody3D=WorldBuilder.add_box_collider(pot,.90,WorldBuilder.L_SOLID)
			body.set_meta("model_part",true)

func _beam(parent: Node3D,label: String,start: Vector3,finish: Vector3,width: float,material: Material) -> void:
	var mesh:=MeshInstance3D.new();mesh.name=label
	var shape:=BoxMesh.new();shape.size=Vector3(width,width,start.distance_to(finish))
	mesh.mesh=shape;mesh.material_override=material;parent.add_child(mesh)
	mesh.position=(start+finish)*.5
	mesh.quaternion=Quaternion(Vector3.BACK,(finish-start).normalized())
	mesh.set_meta("beam_start",start);mesh.set_meta("beam_end",finish)
