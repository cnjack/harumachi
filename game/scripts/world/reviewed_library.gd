class_name ReviewedLibrary
extends RefCounted
## Selected source geometry gets a specific use and remains clear of circulation.
static func finish(root: Node3D,kind: int) -> void:
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		for surface in mesh.mesh.get_surface_count():
			var original:=mesh.get_active_material(surface) as StandardMaterial3D
			var material:=ShaderMaterial.new();material.shader=load("res://shaders/library_finish.gdshader")
			material.set_shader_parameter("pattern",kind)
			material.set_shader_parameter("tint",original.albedo_color if original!=null else Color(.57,.43,.26))
			material.set_shader_parameter("light_steps",2 if kind==0 else 3)
			mesh.set_surface_override_material(surface,material)
	root.set_meta("library_finish",kind)

static func build(world: WorldBuilder) -> void:
	var town:=Node3D.new();town.name="ReviewedLibrary";world.add_child(town)
	var farm:=Node3D.new();farm.name="ReviewedLibrary";world.farm.add_child(farm)
	# Containers belong to the working shed/potting area, never to a shop door.
	# One garden stool belongs beside Haru's potting bench. The farm keeps the
	# working carton and filled bucket; do not duplicate the same display kit.
	for entry: Array in [["P_library_stool",Vector3(15.1,0,13.7),12,1]]:
		_place(world,town,entry,false)
	for entry: Array in [["P_library_carton",Vector3(-12.2,0,-5.0),-18,0],
		["P_library_bucket",Vector3(-8.1,0,-4.0),20,0],["P_library_stool",Vector3(-9.0,0,-4.3),-12,1]]:
		_place(world,farm,entry,true)
	# Each foliage kind is present in both the horizon and inspectable foreground.
	var town_points: Array[Vector2]=[Vector2(-12.4,16.2),Vector2(-12.3,17.5),Vector2(16.4,18.9),Vector2(-11.8,21.6),Vector2(16.1,22.3),Vector2(-12.5,23.4),Vector2(-14.9,-15.1),Vector2(16.5,24.6),Vector2(16.3,26.5),Vector2(15.6,23.6)]
	var farm_points: Array[Vector2]=[Vector2(-24,8),Vector2(-22.5,8.5),Vector2(-19,10),Vector2(-23.5,10.7),Vector2(20,-10),Vector2(-15.5,-7.5),Vector2(4.9,4.2),Vector2(133,46),Vector2(135,39),Vector2(22,6)]
	for index in LandscapeCoverage.PLANTS.size():
		for is_farm: bool in [false,true]:
			var at: Vector2=farm_points[index] if is_farm else town_points[index]
			var parent: Node3D=farm if is_farm else town
			var plant: Node3D=world.spawn(LandscapeCoverage.PLANTS[index],Vector3(at.x,0,at.y),index*49,0,parent,.3 if index==5 else 1.0)
			if plant:
				plant.name="ForegroundPlant_%d"%index
				WorldBuilder.rest_on_terrain(plant,LakesideLayout.height_at(at) if is_farm else .01,.003)
	for index in 12:
		var at:=Vector2(36.0+index*3.0,-6.0-index*.29)
		var rock: Node3D=world.spawn("V%02d_path_pebble"%(16+index%3),Vector3(at.x,LakesideLayout.height_at(at),at.y),index*71,0,farm)
		if rock:rock.name="PathPebble_%d"%index;WorldBuilder.rest_on_terrain(rock,LakesideLayout.height_at(at),.02)
	# Retain the reviewed cloth for a future real invitation, packed away until
	# that event exists. Merely selecting a material never starts a picnic.
	var cloth:=SurfaceTool.new();cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in 8:
		for x in 12:
			var p:=Vector2(80.0+x*.13,54.0+z*.13)
			for q: Vector2 in [p,p+Vector2(.13,.13),p+Vector2(0,.13),p,p+Vector2(.13,0),p+Vector2(.13,.13)]:
				cloth.set_normal(Vector3.UP);cloth.add_vertex(Vector3(q.x,LakesideLayout.height_at(q)+.025,q.y))
	var cloth_node:=MeshInstance3D.new();cloth_node.name="PicnicCloth";cloth_node.mesh=cloth.commit();farm.add_child(cloth_node)
	cloth_node.visible=false
	var cloth_material:=ShaderMaterial.new();cloth_material.shader=load("res://shaders/library_finish.gdshader");cloth_material.set_shader_parameter("pattern",2);cloth_material.set_shader_parameter("tint",Color(.34,.53,.60));cloth_node.material_override=cloth_material

static func _place(world: WorldBuilder,parent: Node3D,entry: Array,farm: bool) -> void:
	var model: Node3D=world.spawn(entry[0],entry[1],float(entry[2]),0,parent)
	if model==null:return
	var at: Vector3=entry[1]
	WorldBuilder.rest_on_terrain(model,LakesideLayout.height_at(Vector2(at.x,at.z)) if farm else .01,.001)
	finish(model,int(entry[3]))
	if farm: preload("res://scripts/world/farm_timber.gd").apply(model, str(entry[0]))
	if str(entry[0])=="P_library_bucket":
		var water:=MeshInstance3D.new();water.name="ShallowWater"
		var disk:=CylinderMesh.new();disk.top_radius=.142;disk.bottom_radius=.142;disk.height=.004;disk.radial_segments=32
		water.mesh=disk;water.position=Vector3(0,.273,0)
		var material:=ShaderMaterial.new();material.shader=load("res://shaders/library_water.gdshader");water.material_override=material;model.add_child(water)
	WorldBuilder.add_box_collider(model,.85,WorldBuilder.L_SOLID)
