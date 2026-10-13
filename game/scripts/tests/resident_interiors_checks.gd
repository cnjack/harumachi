extends RefCounted
## Checks the built rooms and actual capsule routes, including the old missing-room failure.
var t: Object
var main: Node
const IDS := ["home_haru","home_mio","home_tanaka","home_ren","home_kazuko","toolshed","photo_room","florist","zakka","post","library"]
func _init(runner: Object) -> void:
	t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:
	t.check("RESIDENT_INTERIORS",label,ok,detail)
func run() -> void:
	for id: String in IDS:
		var room: Node3D=main.world.interiors.get(id)
		check(id+" is a real built walkable interior",room!=null and WorldBuilder.find_meshes(room).size()>=12 if room!=null else false,"specs=%s built=%s meshes=%d"%[InteriorBuilder.SPECS.keys(),main.world.interiors.keys(),WorldBuilder.find_meshes(room).size() if room!=null else 0])
		if room==null:continue
		var spec: Dictionary=InteriorBuilder.spec_for(id)
		var entry: Vector3=InteriorBuilder.door_point(id)
		var floor_hit: Dictionary=main.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(entry+Vector3.UP,entry-Vector3.UP,WorldBuilder.L_GROUND))
		check(id+" entry has actual physical floor",not floor_hit.is_empty() and absf((floor_hit.get("position",entry) as Vector3).y-entry.y)<.15)
		var unreachable: Array[String]=[]
		for point: Array in spec.points:
			var finish: Vector3=spec.origin+Vector3(float(point[1]),0.05,float(point[3]))
			if NPC.MOTION_ROUTE.query(main.player,entry,finish).is_empty():unreachable.append(str(point[0]))
		check(id+" actual player capsule reaches every story station",unreachable.is_empty(),str(unreachable))
		var point_ids: Array[String]=[]
		for interactable: Interactable in room.find_children("*","Interactable",true,false):point_ids.append(interactable.id)
		var missing: Array[String]=[]
		for point: Array in spec.points:
			if str(point[0]) not in point_ids:missing.append(str(point[0]))
		check(id+" has real exit and story interactables",missing.is_empty() and point_ids.has("visit_"+id+"_exit"),str(missing))
		check(id+" saved position resolves to the same room",InteriorBuilder.at(entry)==id and InteriorBuilder.walked_out(id,spec.origin+Vector3(float(spec.door_x),0,float(spec.size.y)*.5+.31)))
		var unsupported: Array[String]=[]
		for prop: Node3D in room.find_children("*","Node3D",true,false):
			if not prop.has_meta("support_surface"):continue
			var support: Node3D=prop.get_node_or_null(prop.get_meta("support_surface")) as Node3D
			if support==null:unsupported.append(prop.name);continue
			var bottom: float=(prop.global_transform*WorldBuilder.local_aabb(prop)).position.y
			var top: float=WorldBuilder.rendered_support_height(support,prop.global_position,2.5,true)
			if not is_finite(top) or absf(bottom-top)>.035:unsupported.append("%s gap=%.4f"%[prop.name,bottom-top])
		check(id+" reusable tabletop props have measured real support",unsupported.is_empty(),str(unsupported))
		var bad_seats: Array[String]=[]
		for who: String in spec.seats:
			var seat: Dictionary=spec.seats[who];var support: Node3D=room.get_node_or_null(str(seat.support))
			var anchor: Vector3=room.origin+(seat.at as Vector3)
			if support==null or absf(WorldBuilder.rendered_support_height(support,anchor,1.0,true)-anchor.y)>.015:bad_seats.append(who)
		check(id+" resident seats have an actual matching support surface",bad_seats.is_empty(),str(bad_seats))
		var doorway: Interactable=null
		for candidate: Interactable in main.find_children("*","Interactable",true,false):
			if candidate.id==str(spec.door_id):doorway=candidate;break
		check(id+" real exterior or parent-room door matches the registry",doorway!=null and doorway.global_position.distance_to(spec.outside_point)<.015)
		var shape:=PhysicsShapeQueryParameters3D.new();shape.shape=NPC.MOTION_ROUTE.capsule();shape.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_BLOCK
		shape.transform=Transform3D(Basis.IDENTITY,(spec.exit as Vector3)+Vector3(0,.8,0))
		var blocked: Array[Dictionary]=main.world.get_world_3d().direct_space_state.intersect_shape(shape,8)
		check(id+" return standpoint is physically clear for the player capsule",blocked.is_empty(),str(blocked))
		var buried_windows: Array[String]=_window_obstructions(room)
		check(id+" real window openings are clear of furniture and pasted labels",buried_windows.is_empty(),str(buried_windows))
	var gallery: GDScript=load("res://scripts/tools/resident_interiors_visual.gd")
	check("native gallery script compiles before opening a renderer",gallery!=null and gallery.can_instantiate())
	for who: String in ["haru","tanaka"]:
		var address: Dictionary=ResidentPlaces.HOMES[who];var door_spec: Dictionary=ResidentPlaces.SPECS[address.room]
		var actual_door: Vector3=Vector3.INF
		for building: Node in main.world.get_children():
			if not building is Node3D or building.get_meta("model_id","")!="H03" or (building as Node3D).position.distance_to(address.building_at)>.05:continue
			for mesh: MeshInstance3D in WorldBuilder.find_meshes(building):
				if str(mesh.name).begins_with("DoorFrame_1"):
					actual_door=mesh.global_transform*mesh.get_aabb().get_center();break
		var door_distance: float=Vector2(actual_door.x,actual_door.z).distance_to(Vector2(door_spec.outside_point.x,door_spec.outside_point.z))
		check(who+" exterior invitation point targets the actual rendered door module",is_finite(door_distance) and door_distance<.18,"real door=%s registered=%s XZ gap=%.3f"%[actual_door,door_spec.outside_point,door_distance])
	_check_ordinary_door_targets()

func _check_ordinary_door_targets() -> void:
	var saved_flags: Dictionary=GameState.flags.duplicate(true);var saved_locks: Dictionary=GameState._ui_locks.duplicate(true)
	var saved_day: int=GameState.day;var saved_minute: int=GameState.minute;var saved_phase: String=GameState.phase
	var saved_region: String=GameState.player_region;var saved_inside: bool=GameState.player_in_room
	var previous_region: String=main.world.region;var previous_look: bool=main.world.indoor;var previous_public: String=main.world.public_interior_kind
	var previous_room: String=main.room_kind;var previous_in_room: bool=main.in_room
	var saved_at: Vector3=main.player.global_position;var saved_velocity: Vector3=main.player.velocity;var saved_yaw: float=main.player._face_yaw
	var saved_mode: int=main.player.process_mode;var saved_frozen: bool=main.player.frozen
	var saved_target: Interactable=main.player.target
	main.player.process_mode=Node.PROCESS_MODE_DISABLED;main.player.frozen=false
	GameState.clear_locks();GameState.day=5;GameState.phase="prep"
	for id: String in IDS:
		var spec: Dictionary=ResidentPlaces.SPECS[id];var point: Interactable=null
		for candidate: Interactable in main.get_tree().get_nodes_in_group("interactables"):
			if candidate.id==str(spec.door_id):point=candidate;break
		ResidentVisits.invite(id,"实际门口可达性回归")
		GameState.minute=int((float(spec.open)+.5)*60)
		var region: String=str(spec.entry_region);var parent_room: String=str(spec.return_room)
		main.in_room=parent_room!="";main.room_kind=parent_room;GameState.player_in_room=main.in_room;GameState.player_region=region
		main.world.set_region(region);main.world.set_indoor_look(main.in_room,parent_room)
		var result: Dictionary=_grounded_target(point,spec.exit) if point else {"ok":false,"detail":"missing door"}
		check(id+" ordinary grounded E can target its real door",bool(result.ok),str(result.detail))
	GameState.flags=saved_flags;GameState._ui_locks=saved_locks;GameState.day=saved_day;GameState.minute=saved_minute;GameState.phase=saved_phase
	GameState.player_region=saved_region;GameState.player_in_room=saved_inside;main.in_room=previous_in_room;main.room_kind=previous_room
	main.world.set_region(previous_region);main.world.set_indoor_look(previous_look,previous_public)
	main.player.global_position=saved_at;main.player.velocity=saved_velocity;main.player.set_facing(saved_yaw)
	main.player.frozen=saved_frozen;main.player.target=saved_target;main.player.process_mode=saved_mode;main.player.reset_physics_interpolation()

func _grounded_target(point: Interactable,exit_at: Vector3) -> Dictionary:
	var starts: Array[Vector3]=[exit_at]
	for distance: float in [.65,.95,1.25,1.45,maxf(.1,point.radius-.05)]:
		for direction: Vector3 in [Vector3.LEFT,Vector3.RIGHT,Vector3.BACK,Vector3.FORWARD,Vector3(-1,0,-1).normalized(),Vector3(-1,0,1).normalized(),Vector3(1,0,-1).normalized(),Vector3(1,0,1).normalized()]:
			starts.append(Vector3(point.global_position.x,.05,point.global_position.z)+direction*distance)
	var actual_capsule: Shape3D
	for child: Node in main.player.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:actual_capsule=child.shape;break
	if actual_capsule==null:return {"ok":false,"detail":"missing actual player capsule"}
	var rejected: Array[String]=[];var space: PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
	for candidate: Vector3 in starts:
		var ground: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*1.5,candidate-Vector3.UP*.5,WorldBuilder.L_GROUND))
		if ground.is_empty():continue
		var feet: Vector3=(ground.position as Vector3)+Vector3.UP*.02
		if absf(feet.y)>.35:continue
		var shape:=PhysicsShapeQueryParameters3D.new();shape.shape=actual_capsule;shape.exclude=[main.player.get_rid()]
		shape.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_BLOCK|WorldBuilder.L_ACTORS;shape.transform=Transform3D(Basis.IDENTITY,feet+Vector3.UP*.8)
		if not space.intersect_shape(shape,1).is_empty():continue
		main.player.global_position=feet;main.player.velocity=Vector3.ZERO;main.player.face_towards(point.global_position);main.player._update_target()
		var flat: float=Vector2(feet.x-point.global_position.x,feet.z-point.global_position.z).length()
		if main.player.target==point:return {"ok":true,"detail":"feet=%s ground_y=%.3f flat_distance=%.3f radius=%.2f actual target=%s"%[feet,feet.y,flat,point.radius,point.id]}
		if rejected.size()<8:
			var ray:=PhysicsRayQueryParameters3D.create(feet+Vector3.UP*1.1,point.global_position,WorldBuilder.L_SOLID|WorldBuilder.L_PLACED)
			ray.exclude=[main.player.get_rid()]
			if point.body:ray.exclude.append(point.body.get_rid())
			var hit: Dictionary=space.intersect_ray(ray)
			rejected.append("feet=%s d=%.3f target=%s LOSgap=%.4f prompt=%s"%[feet,flat,main.player.target.id if main.player.target else "none",(hit.position as Vector3).distance_to(point.global_position) if not hit.is_empty() else 0.0,main.story.prompt_for(point.id)])
	return {"ok":false,"detail":str(rejected)}

func _window_obstructions(room: Node3D) -> Array[String]:
	var bad: Array[String]=[]
	var furnishings: Node3D=room.get_node("ResidentInterior")
	var meshes: Array[MeshInstance3D]=WorldBuilder.find_meshes(furnishings)
	for window: MeshInstance3D in room.find_children("SummerView","MeshInstance3D",true,false):
		var pane:=window.mesh as QuadMesh
		if pane==null:continue
		var blocked: int=0
		for column: int in 9:
			for row: int in 7:
				var point:=Vector3((float(column)/8.0-.5)*pane.size.x*.90,(float(row)/6.0-.5)*pane.size.y*.90,0)
				var begin: Vector3=window.to_global(point+Vector3(0,0,.04));var finish: Vector3=window.to_global(point+Vector3(0,0,.80))
				var covered:=false
				for mesh: MeshInstance3D in meshes:
					var inverse: Transform3D=mesh.global_transform.affine_inverse()
					var local_begin: Vector3=inverse*begin;var local_finish: Vector3=inverse*finish
					if mesh.get_aabb().intersects_segment(local_begin,local_finish)==null:continue
					var faces: PackedVector3Array=mesh.mesh.get_faces()
					for triangle: int in range(0,faces.size(),3):
						if Geometry3D.segment_intersects_triangle(local_begin,local_finish,faces[triangle],faces[triangle+1],faces[triangle+2])!=null:
							covered=true;break
					if covered:break
				if covered:blocked+=1
		if blocked>7:bad.append("%s %d/63 actual sight rays hit furnishings"%[window.get_path(),blocked])
	return bad
