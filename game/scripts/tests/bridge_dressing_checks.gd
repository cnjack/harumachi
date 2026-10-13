extends RefCounted
var t: Object
var main: Node
func _init(runner: Object) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("BRIDGE_DRESSING",label,ok,detail)
func run() -> void:
	var farm: FarmBuilder=main.world.farm
	var dressing: Node3D=farm.get_node_or_null("BridgeDressing")
	check("bridge has permanent dressing independent of festival state",dressing!=null)
	var lanterns: Array[Node3D]=[];var pots: Array[Node3D]=[];var mounts: Array[Node3D]=[]
	if dressing:
		for node: Node3D in dressing.get_children():
			if str(node.name).begins_with("LanternMount_"):mounts.append(node)
			if node.get_meta("model_id","")=="V21_white_hydrangea":pots.append(node)
		for node: Node3D in dressing.find_children("BridgeLantern_*","Node3D",true,false):lanterns.append(node)
	check("four complete bamboo lanterns and two existing hydrangea pots are reused",lanterns.size()==4 and pots.size()==2)
	var contacts: bool=mounts.size()==4
	var suspension: bool=mounts.size()==4
	for mount: Node3D in mounts:
		var contact: Vector3=mount.get_meta("rail_contact",Vector3.INF)
		var actual: float=WorldBuilder.surface_height(farm.get_node("P_bridge"),Vector2(farm.global_position.x+contact.x,farm.global_position.z+contact.z),3.0)
		contacts=contacts and is_finite(actual) and absf(actual-farm.global_position.y-contact.y)<.003
		var clamp: Node3D=mount.get_node("PostClamp")
		contacts=contacts and (clamp.get_meta("beam_start") as Vector3).distance_to(contact+Vector3.UP*.025)<.001
		var cord: Node3D=mount.get_node("HangingCord")
		var lantern: Node3D=mount.get_node("BridgeLantern_%s"%str(mount.name).get_slice("_",1))
		var bounds: AABB=lantern.transform*WorldBuilder.local_aabb(lantern)
		suspension=suspension and absf(bounds.end.y-(cord.get_meta("beam_end") as Vector3).y)<.012
	check("every solid bracket is attached to a measured handrail surface",contacts)
	check("hanging cords meet the actual tops of the lantern handles",suspension)
	var outside: bool=lanterns.size()==4
	for lantern: Node3D in lanterns:
		var box: AABB=farm.global_transform.affine_inverse()*lantern.global_transform*WorldBuilder.local_aabb(lantern)
		outside=outside and (box.position.x>1.12 or box.end.x< -1.12)
	check("all lantern geometry stays outside the 1.9 metre walkable deck",outside)
	var rooted: bool=pots.size()==2
	var grass_clear: bool=pots.size()==2
	for pot: Node3D in pots:
		var bounds: AABB=pot.global_transform*WorldBuilder.local_aabb(pot)
		rooted=rooted and absf(bounds.position.y-float(pot.get_meta("support_y",INF))+.008)<.003
		var local: Vector3=pot.position
		grass_clear=grass_clear and absf(local.x)>1.6 and pot.find_children("*","CollisionShape3D",true,false).size()==1
	check("planter bases rest on real rendered ground",rooted)
	check("bridge approaches remain clear and planters have simple solid colliders",grass_clear)
	var managed: bool=lanterns.size()==4
	for lantern: Node3D in lanterns:
		var lights: Array[Node]=lantern.find_children("*","OmniLight3D",true,false)
		managed=managed and lights.size()==1
		for light: OmniLight3D in lights:managed=managed and light in main.world.lamp_lights and not light.shadow_enabled
	check("lantern lighting follows the real outdoor day and night lamp controls",managed)
	var intrusions: int=0;var inspected: int=0;var submitted_ok: bool=true
	for child: Node in farm.get_node("Meadow").get_children():
		var batch: MultiMeshInstance3D=child as MultiMeshInstance3D
		if batch==null:continue
		var points: PackedVector3Array=batch.get_meta("submitted_grass_positions",PackedVector3Array())
		submitted_ok=submitted_ok and points.size()==batch.multimesh.instance_count
		for index: int in batch.multimesh.instance_count:
			if points.size()<=index:continue
			var point: Vector3=batch.global_transform*(points[index] if DisplayServer.get_name()=="headless" else batch.multimesh.get_instance_transform(index).origin)
			inspected+=1
			for pot: Node3D in pots:
				var bounds: AABB=pot.global_transform*WorldBuilder.local_aabb(pot)
				if Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).has_point(Vector2(point.x,point.z)):intrusions+=1
	check("actual submitted grass and flower instances leave both planter bodies clear",pots.size()==2 and submitted_ok and inspected>1000 and intrusions==0,"intrusions=%d inspected=%d"%[intrusions,inspected])
	var capsule:=CapsuleShape3D.new();capsule.radius=.28;capsule.height=1.5
	var route_clear: bool=dressing!=null
	for step: int in 49:
		for lane: float in [-.45,0.0,.45]:
			var at:=Vector3(lane,0,11.0+step*.25)
			var height: float=WorldBuilder.surface_height(farm.get_node("P_bridge"),Vector2(farm.global_position.x+at.x,farm.global_position.z+at.z),1.2)
			if not is_finite(height):height=LakesideLayout.height_at(Vector2(at.x,at.z))
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_BLOCK
			query.transform=Transform3D(Basis.IDENTITY,Vector3(farm.global_position.x+at.x,height+.77,farm.global_position.z+at.z))
			route_clear=route_clear and farm.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	check("three full player-width routes across bridge and both approaches remain unblocked",route_clear)
	var prior_indoor: bool=main.world.indoor
	main.world.indoor=false
	var responsive: bool=managed
	for hour: float in [12.0,21.0]:
		main.world.update_time(hour*60.0,"sunny",true)
		for lantern: Node3D in lanterns:
			for light: OmniLight3D in lantern.find_children("*","OmniLight3D",true,false):responsive=responsive and (is_zero_approx(light.light_energy) if hour==12.0 else light.light_energy>=.5 and light.light_energy<=.8)
	main.world.indoor=prior_indoor
	main.world.update_time(GameState.minute,GameState.weather,true)
	check("real lighting updates switch bridge lamps off by day and gently on by night",responsive)
	# Low props can sit below a torso-height sphere while blocking real legs.
	# Sweep the complete body through every authored farm festival stop and leg.
	var activity_samples: int=0;var blocked: Array[String]=[]
	var loops: Array=t.call("_all_loops")
	for cycle: Array in loops:
		var stops: Array=cycle[2]
		for stop_index: int in stops.size():
			var start: Vector3=stops[stop_index][0]
			var finish: Vector3=stops[(stop_index+1)%stops.size()][0]
			if start.x<300.0 or finish.x<300.0:continue
			var subdivisions: int=maxi(1,ceili(start.distance_to(finish)/.25))
			for segment: int in subdivisions+1:
				var activity_at: Vector3=start.lerp(finish,float(segment)/float(subdivisions))
				var activity_query:=PhysicsShapeQueryParameters3D.new();activity_query.shape=capsule;activity_query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED
				activity_query.transform=Transform3D(Basis.IDENTITY,activity_at+Vector3.UP*.77)
				activity_samples+=1
				for hit: Dictionary in farm.get_world_3d().direct_space_state.intersect_shape(activity_query,16):
					if dressing and dressing.is_ancestor_of(hit.collider):blocked.append("%s/%s stop_or_leg%d sample%d"%[cycle[0],cycle[1],stop_index,segment])
	check("full resident capsules clear both planters at every farm festival stop and along every leg",dressing!=null and activity_samples>30 and blocked.is_empty(),"samples=%d blocked=%s"%[activity_samples,str(blocked.slice(0,12))])
