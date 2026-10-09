class_name ProjectTasting
extends Node3D
## One existing sample, on an existing measured surface. No hand or mouth animation.
var s: Story
var actor: NPC
var active := false
var aborted := false
var stage := ""
var surface := Vector3.INF
var support: Node3D
var action: LivingAction
var camera: Camera3D
var prior_camera: Camera3D
var player_trace: Array[Vector3] = []
var npc_trace: Array[Vector3] = []
var saved_frozen := true
var saved_auto := Vector3.ZERO
var saved_run := false
var saved_talking := false
var saved_speed := 1.5
var sample_id := ""
var sample_batch := -1
var location := ""
var checked_at := -1.0
var checked_surface := false

func _input(event: InputEvent) -> void:
	if active and (event.is_action_pressed("cancel") or event.is_action_pressed("pause")):
		aborted = true
		if is_instance_valid(actor): actor.cancel_safe_walk()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not active: return
	if not present():
		aborted = true
		if is_instance_valid(actor): actor.cancel_safe_walk()
		return
	if stage == "walk" and is_instance_valid(camera):
		var focus: Vector3 = s.player.global_position.lerp(actor.global_position,.5) + Vector3.UP*.6
		var distance: float = s.player.global_position.distance_to(actor.global_position)
		camera.global_position = focus + Vector3(5,7+distance*.2,9+distance*.4)
		camera.look_at(focus)
	if stage == "eat" and is_instance_valid(action):
		stage = "empty" if action.meal_food != null and not action.meal_food.visible else "eat"
	if stage == "empty" and not surface_valid(): aborted = true

func present() -> bool:
	return is_instance_valid(actor) and not actor.home and actor.is_visible_in_tree() and location == s.main.room_kind and s.world.region == "town"

func surface_valid() -> bool:
	if not is_instance_valid(support) or not support.is_visible_in_tree(): return false
	var now: float=Time.get_ticks_msec()/1000.0
	if now-checked_at<.2:return checked_surface
	checked_at=now;checked_surface=patch_supported(support,surface) and patch_clear(support,surface)
	return checked_surface

static func patch_supported(model: Node3D, at: Vector3) -> bool:
	if not is_instance_valid(model) or not at.is_finite(): return false
	for offset: Vector3 in [Vector3.ZERO,Vector3(-.09,0,-.09),Vector3(.09,0,-.09),Vector3(-.09,0,.09),Vector3(.09,0,.09),Vector3(-.09,0,0),Vector3(.09,0,0),Vector3(0,0,-.09),Vector3(0,0,.09)]:
		var height: float = WorldBuilder.rendered_support_height(model,at+offset,at.y+.03,true)
		if not is_finite(height) or absf(height-at.y)>.014: return false
	return true

func patch_clear(model: Node3D, at: Vector3) -> bool:
	var box := AABB(at+Vector3(-.10,.004,-.10),Vector3(.20,.10,.20))
	# Generated counters may include joined produce bins. The root's model_id is
	# not a reason to ignore geometry above its supporting face.
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
		if mesh.mesh==null:continue
		for index_surface: int in mesh.mesh.get_surface_count():
			var arrays: Array=mesh.mesh.surface_get_arrays(index_surface)
			if arrays.is_empty():continue
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var count: int=indices.size() if not indices.is_empty() else vertices.size()
			for face: int in range(0,count-2,3):
				var a: Vector3=mesh.global_transform*vertices[indices[face] if not indices.is_empty() else face]
				var b: Vector3=mesh.global_transform*vertices[indices[face+1] if not indices.is_empty() else face+1]
				var c: Vector3=mesh.global_transform*vertices[indices[face+2] if not indices.is_empty() else face+2]
				var triangle: AABB=AABB(a,Vector3.ZERO).expand(b).expand(c)
				if box.intersects(triangle):return false
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(s.main):
		if not mesh.is_visible_in_tree() or model==mesh or model.is_ancestor_of(mesh): continue
		if is_instance_valid(action) and action.is_ancestor_of(mesh): continue
		if mesh.mesh != null and box.intersects(mesh.global_transform*mesh.get_aabb()): return false
	return true

func find_surface(who: String) -> bool:
	var models: Array[Node3D] = []
	if who=="haru" and s.neighbours.table_available(): models.append(s.neighbours.view.table_model)
	for node: Node in s.main.find_children("*","Node3D",true,false):
		if not node.has_meta("model_id") or not (node as Node3D).is_visible_in_tree(): continue
		var id: String = str(node.get_meta("model_id"))
		if not s.main.in_room and id=="P09": models.append(node as Node3D)
		elif who=="kazuko" and s.main.in_room and s.main.room_kind=="store" and id=="I04_shop_counter": models.append(node as Node3D)
	for model: Node3D in models:
		var bounds: AABB = model.global_transform*WorldBuilder.local_aabb(model)
		for dx: float in [.6,.25,-.25,-.6,0.0,.9,-.9]:
			for dz: float in [-.35,0.0,.35,-.7,.7]:
				var candidate: Vector3 = bounds.get_center()+Vector3(dx,0,dz)
				# P09's usable face is the narrow front counter, not the roof.
				if str(model.get_meta("model_id",""))=="P09": candidate=Vector3(model.global_position.x+dx,0,model.global_position.z+dz)
				candidate.y=WorldBuilder.rendered_support_height(model,candidate,1.35,true)
				if not is_finite(candidate.y) or candidate.y<.4 or candidate.y>1.35: continue
				if patch_supported(model,candidate) and patch_clear(model,candidate):
					support=model;surface=candidate;return true
	return false

func run(story: Story, who: String, presentation: String) -> Dictionary:
	s=story;actor=s.npcs.get(who);location=s.main.room_kind
	var batch: Dictionary=SummerProjects.current_batch()
	if batch.is_empty():return {"error":"先把这一份做出来，再请街坊尝。"}
	sample_id=str(batch.iid);sample_batch=int(batch.id)
	if not present() or not find_surface(who): return {"error":"附近还没有留出能放下小份的空面。这份先收着。"}
	if not MealModels.can_display(sample_id):return {"error":"这一小份还没摆好，先收着。"}
	saved_frozen=s.player.frozen;saved_auto=s.player.auto_move;saved_run=s.player.auto_run
	saved_talking=actor.talking;saved_speed=actor.speed
	active=true;GameState.lock_input("project_tasting");actor.set_talking(true);actor.speed=Player.WALK
	prior_camera=s.get_viewport().get_camera_3d()
	if not s.ui.instant:
		camera=Camera3D.new();add_child(camera);camera.fov=48;camera.make_current()
	s.ui.dlg.hide();stage="walk"
	var reached: bool=await reach_surface()
	if not reached or aborted or not surface_valid() or not patch_clear(support,surface):
		cleanup();return {"error":"这次先停在这里，小份还在。等桌边空下来再尝。"}
	actor.face(s.player.global_position);s.player.face_towards(actor.global_position)
	action=LivingAction.new();s.main.add_child(action)
	action.surface_at=surface;action.meal_presentation=presentation
	action.duration=.08 if s.ui.instant else 2.2
	action.setup(actor,"eat",sample_id)
	if action.meal_food==null:cleanup();return {"error":"这一小份还没摆好，先收着。"}
	stage="eat"
	if is_instance_valid(camera):
		camera.global_position=surface+Vector3(.12,.72,.36);camera.look_at(surface+Vector3.UP*.025);camera.fov=40
		if not portion_visible():
			cleanup();return {"error":"小份被挡住了，先收着。换一块能看清的空面再尝。"}
	while not action.finished and not aborted:
		if not surface_valid():aborted=true
		await s.get_tree().process_frame
	checked_at=-1.0
	var complete: bool=not aborted and present() and surface_valid() and patch_clear(support,surface) and at_surface()
	cleanup()
	if not complete:return {"error":"这份还没尝完，先收着，下回接着来。"}
	return {"completed":true,"batch_id":sample_batch,"menu":str(batch.menu),"presentation":presentation,"purpose":SummerProjects.tasting_purpose(who)}

func portion_visible() -> bool:
	if not is_instance_valid(camera):return true
	var start: Vector3=camera.global_position
	for offset: Vector3 in [Vector3.ZERO,Vector3(-.045,0,0),Vector3(.045,0,0),Vector3(0,0,-.035),Vector3(0,0,.035)]:
		var finish: Vector3=surface+Vector3.UP*.04+offset
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(s.main):
			if mesh.mesh==null or not mesh.is_visible_in_tree() or is_instance_valid(action) and action.is_ancestor_of(mesh):continue
			var bounds: AABB=mesh.global_transform*mesh.get_aabb()
			if bounds.intersects_segment(start,finish)==null:continue
			for index_surface: int in mesh.mesh.get_surface_count():
				var arrays: Array=mesh.mesh.surface_get_arrays(index_surface)
				if arrays.is_empty():continue
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
				var count: int=indices.size() if not indices.is_empty() else vertices.size()
				for face: int in range(0,count-2,3):
					var a: Vector3=mesh.global_transform*vertices[indices[face] if not indices.is_empty() else face]
					var b: Vector3=mesh.global_transform*vertices[indices[face+1] if not indices.is_empty() else face+1]
					var c: Vector3=mesh.global_transform*vertices[indices[face+2] if not indices.is_empty() else face+2]
					var hit: Variant=Geometry3D.segment_intersects_triangle(start,finish,a,b,c)
					if hit is Vector3 and (hit as Vector3).distance_to(finish)>.012:return false
	return true

func at_surface() -> bool:
	return present() and actor.global_position.distance_to(surface)<2.6 and s.player.global_position.distance_to(surface)<2.6 and actor.global_position.distance_to(s.player.global_position)>.65

func reach_surface() -> bool:
	if at_surface():return true
	if s.main.in_room:return false # Keep shopkeepers at the authored counter; never switch rooms for a sample.
	var stops: Array = [[Vector3(-.5,0,-1.0),Vector3(.5,0,-1.0)],[Vector3(-.5,0,1.0),Vector3(.5,0,1.0)],[Vector3(-1,0,-.5),Vector3(-1,0,.5)]]
	for pair: Array in stops:
		var npc_at: Vector3=Vector3(surface.x,0,surface.z)+pair[0]
		var player_at: Vector3=Vector3(surface.x,0,surface.z)+pair[1]
		var npc_path: Array[Vector3]=NPC.MOTION_ROUTE.query(actor,actor.global_position,npc_at)
		if npc_path.is_empty():continue
		if NPC.MOTION_ROUTE.query(s.player,s.player.global_position,player_at).is_empty():continue
		# Both endpoints are distinct and checked with the complete capsule.
		var end_probe:=PhysicsShapeQueryParameters3D.new()
		end_probe.shape=NPC.MOTION_ROUTE.capsule();end_probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS|WorldBuilder.L_BLOCK
		end_probe.exclude=[s.player.get_rid(),actor.body.get_rid()]
		end_probe.transform=Transform3D(Basis.IDENTITY,player_at+Vector3.UP*.8)
		if not s.world.get_world_3d().direct_space_state.intersect_shape(end_probe,1).is_empty():continue
		npc_trace.append(actor.global_position)
		if s.ui.instant:actor.place(npc_at,0)
		else:
			actor.walk_safe(npc_path) # Monitor the owned walk so Esc has a bounded cancellation path.
			var seconds:=0.0
			while is_instance_valid(actor) and actor._moving and not aborted and seconds<35:
				await s.get_tree().physics_frame
				seconds+=s.get_physics_process_delta_time()
				if is_instance_valid(actor):npc_trace.append(actor.global_position)
			if not is_instance_valid(actor):return false
			if actor._moving:actor.cancel_safe_walk()
			if aborted:return false
			if not actor.walk_succeeded:continue
		npc_trace.append(actor.global_position)
		var player_path: Array[Vector3]=NPC.MOTION_ROUTE.query(s.player,s.player.global_position,player_at)
		if player_path.is_empty():continue
		if not await walk_player(player_path):
			if aborted:return false
			continue
		return at_surface()
	return false

func walk_player(path: Array[Vector3]) -> bool:
	player_trace.append(s.player.global_position)
	if s.ui.instant:
		s.player.global_position=path.back();player_trace.append(s.player.global_position);return true
	s.player.frozen=false;s.player.auto_run=false
	var elapsed:=0.0
	var stalled:=0.0
	for point: Vector3 in path:
		while Vector2(s.player.global_position.x-point.x,s.player.global_position.z-point.z).length()>.12:
			if aborted or not present() or elapsed>35 or stalled>.8:
				stop_player();return false
			var before: Vector3=s.player.global_position
			s.player.auto_move=Vector3(point.x-before.x,0,point.z-before.z).normalized()
			await s.get_tree().physics_frame
			var dt: float=s.get_physics_process_delta_time();elapsed+=dt
			stalled=stalled+dt if s.player.global_position.distance_to(before)<.001 else 0.0
			player_trace.append(s.player.global_position)
	stop_player();return true

func stop_player() -> void:
	s.player.auto_move=Vector3.ZERO;s.player.auto_run=saved_run;s.player.frozen=saved_frozen
	s.player.velocity.x=0;s.player.velocity.z=0

func cleanup() -> void:
	if not active:return
	active=false;stage=""
	stop_player();s.player.auto_move=saved_auto
	if is_instance_valid(actor):
		actor.cancel_safe_walk();actor.speed=saved_speed;actor.set_talking(saved_talking)
		if not s.main.in_room: actor.sched_i=-1
	if is_instance_valid(action):action.queue_free()
	if is_instance_valid(prior_camera):prior_camera.make_current()
	if is_instance_valid(camera):camera.queue_free()
	GameState.unlock_input("project_tasting");s.ui.dialogue_begin()

func _exit_tree() -> void:
	cleanup()
