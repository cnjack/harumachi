extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=t.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("CAMERA_BODY",label,ok,detail)
func run() -> void:
	var original: Dictionary=GameState.to_dict().duplicate(true)
	if main.in_room:
		if main.room_kind=="house":await main.exit_room()
		else:await main.exit_interior()
	var old_view:=Vector3(main.rig.yaw,main.rig.pitch,main.rig.dist)
	var old_fixed: bool=main.rig.fixed
	var old_frozen: bool=main.player.frozen
	var layer: int=main.player.collision_layer;var mask: int=main.player.collision_mask
	main.player.frozen=true;main.rig.fixed=false;main.rig.collide=true
	main.rig.yaw=0;main.rig.pitch=30;main.rig.dist=7
	main.player.global_position=Vector3(3.106076,.00084,14.57309);main.player.velocity=Vector3.ZERO
	main.rig.cam.make_current();main.rig.snap();await t.frames(15)
	var distance: float=main.rig.cam.global_position.distance_to(main.player.global_position+Vector3.UP*1.25)
	var meshes: Array=WorldBuilder.find_meshes(main.player.model)
	check("the real tasting position retracts the follow camera inside the avatar",distance<.4,str(distance))
	check("a retracted camera hides every covering avatar mesh",not meshes.is_empty() and meshes.all(func(mesh: MeshInstance3D):return mesh.transparency>.99))
	main.player.global_position=Vector3(3.5,.05,-2);main.player.velocity=Vector3.ZERO;main.rig.snap();await t.frames(15)
	check("normal distance restores the same avatar meshes",meshes.all(func(mesh: MeshInstance3D):return mesh.transparency==0))
	var other:=Camera3D.new();main.add_child(other)
	other.global_position=main.player.global_position+Vector3(.4,1.3,.4);other.look_at(main.player.global_position+Vector3.UP);other.make_current();await t.frames(3)
	check("an authored eating or conversation camera does not inherit follow-camera fading",meshes.all(func(mesh: MeshInstance3D):return mesh.transparency==0))
	check("render visibility preserves the full physical character",main.player.collision_layer==layer and main.player.collision_mask==mask)
	main.rig.cam.make_current();other.queue_free()
	main.rig.yaw=old_view.x;main.rig.pitch=old_view.y;main.rig.dist=old_view.z;main.rig.fixed=old_fixed;main.player.frozen=old_frozen
	GameState.from_dict(original);GameState.clock_paused=true;main._restore();main.rig.snap()
