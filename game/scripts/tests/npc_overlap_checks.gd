extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func run() -> void:
	var actor: NPC=main.npcs.aoi
	var neighbour: NPC=main.npcs.ren
	var a_position: Vector3=actor.global_position;var b_position: Vector3=neighbour.global_position
	var a_home: bool=actor.home;var b_home: bool=neighbour.home
	actor.set_home(false);neighbour.set_home(false)
	var start:=Vector3(-25,0,-11)
	actor.place(start,0);neighbour.place(start+Vector3(.5,0,0),0)
	await t.frames(3)
	actor._safe_walk=false
	t.check("NPC_OVERLAP","ordinary walking can retreat from an existing actor overlap",actor._safe_position(start-Vector3(.12,0,0)))
	t.check("NPC_OVERLAP","retreat permission cannot move farther into the other actor",not actor._safe_position(start+Vector3(.12,0,0)))
	actor._safe_walk=true
	t.check("NPC_OVERLAP","strict project trials still reject an overlapping start",not actor._safe_position(start-Vector3(.12,0,0)))
	actor._safe_walk=false
	neighbour.place(start+Vector3(5,0,0),0)
	actor.place(start,0)
	var player_at: Vector3=main.player.global_position
	main.player.global_position=start+Vector3(0,.05,1.5)
	await t.frames(2)
	var planned: Array[Vector3]=actor.MOTION_ROUTE.query(actor,start,start+Vector3(0,0,3))
	var clear_path: bool=not planned.is_empty()
	var route_probe:=PhysicsShapeQueryParameters3D.new();route_probe.shape=actor.MOTION_ROUTE.capsule();route_probe.exclude=[actor.body.get_rid()];route_probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
	for index: int in maxi(0,planned.size()-1):
		route_probe.transform=Transform3D(Basis.IDENTITY,planned[index]+Vector3.UP*.8);route_probe.motion=planned[index+1]-planned[index]
		var cast: PackedFloat32Array=actor.get_world_3d().direct_space_state.cast_motion(route_probe)
		if cast.size()==2 and cast[0]<.99:clear_path=false
	t.check("NPC_OVERLAP","the planned detour sweeps clear of a player standing on the direct route",clear_path)
	main.player.global_position=player_at
	actor.walk.call_deferred([start+Vector3(0,0,2)],true)
	await t.frames(3)
	actor.set_talking(true)
	var held_at: Vector3=actor.global_position
	await t.frames(12)
	t.check("NPC_OVERLAP","ordinary scheduled walking pauses for first meeting and conversation",actor.global_position.distance_to(held_at)<.001 and actor.is_moving())
	actor.set_talking(false)
	await t.frames(12)
	t.check("NPC_OVERLAP","ordinary scheduled walking resumes after the conversation",actor.global_position.distance_to(held_at)>.05)
	actor.place(start,0);actor.sched_i=2
	actor.walk.call_deferred([start+Vector3(0,0,2)],true)
	await t.frames(2)
	actor.set_process(false)
	var obstruction:=StaticBody3D.new();obstruction.collision_layer=WorldBuilder.L_PLACED
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.8,1.8,.8);collider.shape=shape;collider.position.y=.9;obstruction.add_child(collider)
	main.add_child(obstruction);obstruction.global_position=actor.global_position+Vector3(0,0,.4)
	await t.frames(2)
	actor._blocked_seconds=8.1
	actor._frame_delta=.02
	actor._safe_position(actor.global_position+Vector3(0,0,.12))
	t.check("NPC_OVERLAP","a blocked scheduled walk releases its schedule cache for the next retry",not actor.is_moving() and actor.sched_i==-1,"moving=%s schedule=%s scheduled_walk=%s blocked=%s"%[actor.is_moving(),actor.sched_i,actor._scheduled_walk,actor._blocked_seconds])
	obstruction.queue_free();actor.set_process(true)
	actor.place(a_position,0);neighbour.place(b_position,0);actor.set_home(a_home);neighbour.set_home(b_home)
