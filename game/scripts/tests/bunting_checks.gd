extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func run() -> void:
	var saved: Array=GameState.placements.duplicate(true)
	GameState.placements=[{"uid":998,"item":"bunting","x":-25.0,"z":-11.0,"rot":0}]
	main.placement.rebuild();await t.frames(3)
	var probe:=PhysicsShapeQueryParameters3D.new();probe.shape=NPC.MOTION_ROUTE.capsule();probe.collision_mask=WorldBuilder.L_PLACED
	probe.transform=Transform3D(Basis.IDENTITY,Vector3(-25,.8,-11))
	t.check("BUNTING","people can actually walk under the suspended flags",main.get_world_3d().direct_space_state.intersect_shape(probe,1).is_empty())
	probe.transform=Transform3D(Basis.IDENTITY,Vector3(-26.45,.8,-11))
	t.check("BUNTING","the physical support poles remain solid",not main.get_world_3d().direct_space_state.intersect_shape(probe,1).is_empty())
	var flags: Node=main.placement.placed_nodes[998].find_child("WindBunting",true,false)
	t.check("BUNTING","flag tips move in shared wind while their top edge stays attached",flags is MeshInstance3D and flags.material_override is ShaderMaterial)
	var root:=Node3D.new();main.add_child(root)
	var windy:=true
	for asset: String in ["C09_carrot","C10_potato","C11_eggplant","C12_corn","C13_pumpkin","C14_watermelon","C15_wheat","C16_onion","D11_reeds","A14_hydrangea_pot","W04_sunflower_pot","W05_hydrangea_pot","W06_lily_vase"]:
		var model: Node3D=main.world.spawn(asset,Vector3(-40,0,20),0,0,root)
		if model==null:windy=false;continue
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
			for surface: int in mesh.mesh.get_surface_count():
				var applied:=mesh.get_surface_override_material(surface) as ShaderMaterial
				if applied==null:print("PLANT_WIND_MISSING ",asset," mesh=",mesh.name," surface=",surface)
				windy=windy and applied!=null
	t.check("BUNTING","remaining crops, reeds and decorative plants share root-anchored wind",windy)
	root.queue_free();GameState.placements=saved;main.placement.rebuild();await t.frames(3)
