class_name ResidentialLife
extends RefCounted
const GARDEN_WALL_COUNT:=12
static func build(world: WorldBuilder) -> void:
	for index in 6:
		var east:=index%2==0
		var z: float=43+17*int(index/2)
		var x:=23.8 if east else 14.8
		world.spawn("A14_hydrangea_pot",Vector3(x,0,z-3.6),90 if east else -90,2)
		world.spawn("A15_potted_plant",Vector3(x,0,z+3.4),30*index,2)
		var path:=WorldBuilder.ground_material("gravel")
		world.call("_plane",[22.4 if east else 10.0,z-1.35,26.0 if east else 17.0,z+1.35],path,.009)
		var shrub_x:=36.7 if east else -1.6
		world.spawn("M12b_shrub",Vector3(shrub_x,0,z-4.1),index*61,0,null,.9)
		world.spawn("M12d_flower_bush",Vector3(shrub_x,0,z+3.9),index*45,0,null,.85)
		if index in [1,4]:world.spawn("A11_bicycle",Vector3(24.2 if east else 13.2,0,z+2),-90 if east else 90,0)
		var garden:=ShaderMaterial.new();garden.shader=load("res://shaders/blockwall.gdshader");garden.set_shader_parameter("plaster",true)
		for sign_z in [-5.8,5.8]:
			var wall:=WorldBuilder.add_wall(Vector3(24.2 if east else -.2,0,z+sign_z),Vector3(38.4 if east else 14.3,0,z+sign_z),.5,garden.duplicate(),world)
			wall.name="GardenWall_%d_%d"%[index,int(sign_z*10)]
			JapaneseArchitecture.courtyard_coping(wall,14.2 if east else 14.5,.5)
		var mail: Node3D=world.spawn("H07",Vector3(x,0,z-1.9),-90 if east else 90,2,null,.8)
		if mail:mail.name="NeighbourMailbox_%d"%index
	for index in 4:
		var z: float=38+13*index
		var tree:=world.spawn("T03_round_ginkgo",Vector3(-1.7,0,z),index*72,0,null,.46)
		if tree:WorldBuilder.rest_on_terrain(tree,.008)
	for index in 3:
		var z: float=38+19*index
		world.spawn("R08a",Vector3(17,0,z),90,2)
		var light:=OmniLight3D.new();light.position=Vector3(17,2.5,z);light.omni_range=6;light.light_color=Color(1,.70,.39);light.light_energy=0
		world.add_child(light);world.lamp_lights.append(light)

	# Give every added model a stable unique name before any later path lookup.
	for child: Node in world.get_children():
		if not child is Node3D or not child.has_meta("model_id"):continue
		var location: Vector3=(child as Node3D).position
		if location.z>32.2 and location.z<85.2 and location.x>-4.0 and location.x<42.7:
			child.name="South_%s_%d_%d"%[str(child.get_meta("model_id")),roundi(location.x*100),roundi(location.z*100)]
