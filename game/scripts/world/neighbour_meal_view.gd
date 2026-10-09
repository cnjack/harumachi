class_name NeighbourMealView
extends Node3D
var s: Story
var dish: Node3D
var action_running: bool=false
var acting_portion: int=-1
var cached_surface: Vector3=Vector3.INF
var measured: bool=false
var spot_checks: Dictionary={}
var rice_scene_visible: bool=false
var tick: float=0.0
var last_meal_surface: Vector3=Vector3.INF
var table_model: Node3D
var tea: Node3D

func _process(delta: float) -> void:
	tick+=delta
	if tick<.2:return
	tick=0.0
	var entry: Dictionary=NeighbourMeals.current()
	var live: bool=not entry.is_empty() and entry.role=="rice" and entry.rice_brought and s.busy and s.neighbours.at_table()
	if live!=rice_scene_visible:sync_state()

func setup(story: Story) -> void:
	s=story;dish=Node3D.new();dish.name="HaruSharedSide";dish.set_meta("model_part",true);add_child(dish)
	table_model=s.world.spawn("W13_cedar_worktable",NeighbourMeals.TABLE_CENTER,0,1,s.world)
	table_model.name="HaruMealTable"
	tea=Node3D.new();tea.name="SharedMealTea";s.world.add_child(tea)
	var table_at: Vector3=surface()
	tea.global_position=table_at+Vector3(0,0,-.30)
	s.world.spawn("W12_cedar_tray",Vector3.ZERO,0,0,tea,.35)
	s.world.spawn("W11_ceramic_set",Vector3(0,.014,0),0,0,tea,.70)
	GameState.state_changed.connect(sync_state)
	GameState.time_changed.connect(func(_minute: int):sync_state())
	sync_state()

func surface() -> Vector3:
	if measured:return cached_surface
	var model: Node3D=table_model
	if not is_instance_valid(model): return Vector3.INF
	measured=true
	for at: Vector3 in [NeighbourMeals.TABLE_CENTER]:
		var height: float=WorldBuilder.rendered_support_height(model,at,1.1)
		var flat: bool=height>.35 and height<1.1
		if absf(WorldBuilder.rendered_support_height(model,at)-height)>.025:flat=false
		for offset: Vector3 in [Vector3(-.21,0,-.095),Vector3(.21,0,-.095),Vector3(-.21,0,.095),Vector3(.21,0,.095)]:
			if absf(WorldBuilder.rendered_support_height(model,at+offset,1.1)-height)>.022:flat=false
			if absf(WorldBuilder.rendered_support_height(model,at+offset)-height)>.025:flat=false
		if flat:
			cached_surface=Vector3(at.x,height+.014,at.z)
			return cached_surface
	return Vector3.INF

func sync_state() -> void:
	if not is_instance_valid(dish): return
	for child in dish.get_children(): dish.remove_child(child);child.queue_free()
	var entry: Dictionary=NeighbourMeals.current()
	var table_active: bool=(DailyLife.done("tea") or not NeighbourMeals.state().sessions.is_empty()) and s.world.region=="town" and not s.main.in_room
	table_model.visible=table_active;tea.visible=table_active
	for body: CollisionObject3D in table_model.find_children("*","CollisionObject3D",true,false):body.collision_layer=WorldBuilder.L_SOLID if table_active else 0
	rice_scene_visible=not entry.is_empty() and entry.role=="rice" and entry.rice_brought and s.busy and s.neighbours.at_table()
	var at: Vector3=surface()
	dish.visible=not entry.is_empty() and entry.stage in ["preparing","prepared","portioning"] and at.is_finite() and s.world.region=="town"
	if not dish.visible:return
	dish.global_position=at
	var ready: bool=entry.stage in ["prepared","portioning"]
	for portion_index in (2 if ready else 1):
		if action_running and portion_index==acting_portion:continue
		if ready and (portion_index==0 and entry.npc_ate or portion_index==1 and entry.player_received):continue
		var bowl:=MeshInstance3D.new();bowl.name="Bowl_%d"%portion_index
		var rim:=CylinderMesh.new();rim.top_radius=.095;rim.bottom_radius=.07;rim.height=.016;bowl.mesh=rim
		bowl.material_override=LivingAction.matte(Color(.92,.96,.98));bowl.position=Vector3((portion_index-.5)*.4 if ready else 0,.008,.1)
		if ready and entry.role=="serve" and entry.bowls.size()==2:bowl.position=Vector3(float(entry.bowls[portion_index].x)-at.x,.008,float(entry.bowls[portion_index].z)-at.z)
		dish.add_child(bowl)
		if ready and entry.role=="rice" and entry.rice_brought and s.busy and s.neighbours.at_table() and GameState.count(NeighbourMeals.rice_id(entry))>0 and (portion_index==0 and int(entry.rice_given)==0 or portion_index==1 and GameState.unreserved_count(NeighbourMeals.rice_id(entry))>0):
			# Keep rice beside the cucumber slices, entirely inside this person's bowl.
			var rice: Node3D = MealModels.spawn(s.world,dish,NeighbourMeals.rice_id(entry),.065)
			if rice != null:
				rice.name="Rice_%d"%portion_index
				rice.position+=bowl.position+Vector3(0,.009,.045)
		var slices: int=3 if ready else maxi(1,int(entry.cuts)+1)
		for slice_index in slices:
			var slice:=MeshInstance3D.new();slice.name="Cucumber_%d_%d"%[portion_index,slice_index]
			if entry.style=="thin":
				var thin:=CylinderMesh.new();thin.top_radius=.035;thin.bottom_radius=.035;thin.height=.008;slice.mesh=thin
			else:
				var chunk:=BoxMesh.new();chunk.size=Vector3(.045,.035,.04);slice.mesh=chunk
			var slice_height: float=.008 if entry.style=="thin" else .035
			slice.material_override=LivingAction.matte(Color(.48,.74,.32));slice.position=bowl.position+Vector3((slice_index-1)*.037,.009+slice_height/2,-.025 if entry.role=="rice" else 0);dish.add_child(slice)
		if entry.salted:
			var salt_mark:=MeshInstance3D.new();salt_mark.name="Salt_%d"%portion_index
			var grain:=SphereMesh.new();grain.radius=.004;grain.height=.008;salt_mark.mesh=grain;salt_mark.position=bowl.position+Vector3(.008,.013+(.008 if entry.style=="thin" else .035),-.025 if entry.role=="rice" else 0);salt_mark.material_override=LivingAction.matte(Color.WHITE);dish.add_child(salt_mark)
		if not entry.drained:
			var juice:=MeshInstance3D.new();juice.name="Juice_%d"%portion_index
			var water:=CylinderMesh.new();water.top_radius=.072;water.bottom_radius=.072;water.height=.002;juice.mesh=water;juice.position=bowl.position+Vector3(0,.01,0);juice.material_override=LivingAction.matte(Color(.70,.83,.53));dish.add_child(juice)

func bowl_at(index: int) -> Vector3:
	var entry: Dictionary=NeighbourMeals.current();var at: Vector3=surface()
	if entry.get("bowls",[]).size()!=2:return at+Vector3((index-.5)*.4,0,.1)
	return Vector3(float(entry.bowls[index].x),at.y,float(entry.bowls[index].z))

func spot_clear(at: Vector3) -> bool:
	var key: String="%.2f:%.2f"%[at.x,at.z]
	if spot_checks.has(key):return spot_checks[key]
	var model: Node3D=table_model
	var centre: Vector3=NeighbourMeals.TABLE_CENTER
	var good: bool=absf(at.x-centre.x)<=.72 and absf(at.z-centre.z)<=.30 and Vector2(at.x,at.z).distance_to(Vector2(centre.x,centre.z-.30))>.30
	for offset: Vector3 in [Vector3(-.095,0,-.095),Vector3(.095,0,-.095),Vector3(-.095,0,.095),Vector3(.095,0,.095)]:
		var h: float=WorldBuilder.rendered_support_height(model,at+offset)
		if absf(h-(surface().y-.014))>.025:good=false
	spot_checks[key]=good;return good

func layout_reason() -> String:
	var entry: Dictionary=NeighbourMeals.current()
	if entry.get("bowls",[]).size()!=2:return "先把两只碗放在这块空面上。"
	var left: Vector3=bowl_at(0);var right: Vector3=bowl_at(1)
	if left.distance_to(right)<.20:return "两只碗挤在一起，稍微分开一点。"
	if not spot_clear(left) or not spot_clear(right):return "这里伸出了桌面，或挡住取茶。把碗移回空面。"
	return ""

func play_eat(actor: Node3D,iid: String) -> String:
	if not MealModels.can_display(iid): return "这份先收着，还没有摆上桌。"
	var at: Vector3=spare_meal_surface()
	var entry: Dictionary=NeighbourMeals.current()
	acting_portion=-1
	if not entry.is_empty() and iid in [NeighbourMeals.gift_id(entry),NeighbourMeals.rice_id(entry)]:
		acting_portion=0 if actor==s.npcs.haru else 1
		at=bowl_at(acting_portion)
	if not at.is_finite():return "杯边还没留好碗的位置，先把小菜收着。"
	action_running=true;sync_state()
	var action:=LivingAction.new();s.main.add_child(action);action.surface_at=at;action.duration=.08 if s.ui.instant else 1.8;action.setup(actor,"eat",iid)
	if action.meal_food==null:
		action.queue_free();action_running=false;acting_portion=-1;sync_state()
		return "这份先收着，还没有摆上桌。"
	last_meal_surface=action.surface_at
	var camera: Camera3D=null;var original: Camera3D=s.get_viewport().get_camera_3d()
	if not s.ui.instant:
		camera=Camera3D.new();s.main.add_child(camera);camera.global_position=at+Vector3(.8,1.3,1.7);camera.look_at(at);camera.fov=40;camera.make_current();s.ui.dlg.hide()
	while not action.finished: await s.get_tree().process_frame
	action.queue_free();action_running=false;acting_portion=-1
	if is_instance_valid(camera):
		if is_instance_valid(original): original.make_current()
		camera.queue_free();s.ui.dialogue_begin()
	sync_state();return ""

func spare_meal_surface() -> Vector3:
	var entry: Dictionary=NeighbourMeals.current();var at: Vector3=surface()
	if not at.is_finite():return Vector3.INF
	for offset: Vector3 in [Vector3(-.6,0,.2),Vector3(.6,0,.2),Vector3(-.6,0,-.05),Vector3(.6,0,-.05)]:
		var candidate: Vector3=at+offset
		if not spot_clear(candidate):continue
		var clear: bool=true
		if not entry.is_empty() and entry.stage in ["prepared","portioning"]:
			for index: int in 2:
				if index==0 and entry.npc_ate or index==1 and entry.player_received:continue
				if candidate.distance_to(bowl_at(index))<.22:clear=false
		if clear:return candidate
	return Vector3.INF

func watch_prepare() -> bool:
	var at: Vector3=surface()
	if not at.is_finite() or not s.neighbours.at_table():return false
	var original: Camera3D=s.get_viewport().get_camera_3d();var camera: Camera3D=null
	if not s.ui.instant:
		camera=Camera3D.new();s.main.add_child(camera);camera.global_position=at+Vector3(.8,1.3,1.7);camera.look_at(at);camera.fov=40;camera.make_current();s.ui.dlg.hide()
	var complete: bool=true
	for step in range(int(NeighbourMeals.current().cuts)+1,4):
		if not NeighbourMeals.observe_step(step,s.neighbours.at_table()):complete=false;break
		Audio.fx_at("dish_place" if step==3 else "paper",at,-8)
		if not s.ui.instant:await s.get_tree().create_timer(.45).timeout
	if is_instance_valid(camera):
		if is_instance_valid(original):original.make_current()
		camera.queue_free();s.ui.dialogue_begin()
	return complete
