class_name ResidentVisitView
extends Node3D
var s: Story
var fallback: Node3D
var seated_pose: PublicSeatPose
var trace: Array=[]
var walking: NPC
var _photo_stamp := ""
var trial_camera: Camera3D
var previous_camera: Camera3D
var shared_meal: Node3D

func setup(story: Story) -> void:
	s=story
	fallback=s.world.spawn("A12_bench",Vector3(.3,0,23.3),180,1,self)
	fallback.name="NeighbourTemporarySeat"
	fallback.set_meta("owner","tanaka")
	GameState.state_changed.connect(sync_state)
	GameState.time_changed.connect(func(_minute: int):ResidentVisits.tick();sync_state())
	GameState.day_changed.connect(func(_day: int):ResidentVisits.tick();sync_state())
	sync_state()

func _process(_delta: float) -> void:
	if is_instance_valid(walking) and is_instance_valid(trial_camera):
		trial_camera.global_position=walking.global_position+Vector3(3.5,3.2,-4.5)
		trial_camera.look_at(walking.global_position+Vector3.UP*.9)
	if is_instance_valid(walking) and (trace.is_empty() or LayoutValidity.point(trace.back()).distance_to(walking.global_position)>.08):trace.append(LayoutValidity.position(walking.global_position))

func sync_state() -> void:
	if not is_instance_valid(fallback):return
	var p: Dictionary=ResidentVisits.state()
	var outside: bool=not s.main.in_room and s.world.region=="town"
	_set_active(fallback,bool(p.resident_setup) and p.trial.is_empty() and outside)
	var keys: Dictionary={"Blueprint":p.blueprint_seen,"newdrawing":p.blueprint_seen,"repairedtool":p.followups.has("tool_repaired"),"seedpack":p.followups.has("tanaka_supper") and GameState.day>int(p.followups.get("tanaka_supper",{}).get("day",GameState.day)) and not p.followups.has("seed_received"),"travelbag":true,"packing":p.followups.has("packing_chosen"),"oldtags":p.followups.has("tags_sorted"),"flowergift":p.followups.has("flower_delivered"),"repairedpart":p.followups.has("cushion_fixed"),"replyletter":p.followups.has("letter_sent") and GameState.day>=int(p.followups.get("letter_sent",{}).get("day",GameState.day))+2,"maptrace":p.followups.has("map_traced"),"ActualPhoto":p.photo_rendered}
	for room: Node3D in s.world.interiors.values():
		var group: Node3D=room.get_node_or_null("StoryState")
		if group==null:continue
		for node: Node3D in group.get_children():
			var key: String=str(node.get_meta("story_state_key",node.name))
			if keys.has(key):node.visible=bool(keys[key])
			if key=="seedpack":node.visible=node.visible and room==s.world.interiors.get("home_tanaka")
			if key=="packing":node.set_meta("presentation",p.choices.get("packing_chosen",""))
			if key=="flowergift":
				node.set_meta("flower_choice",p.choices.get("flower_pick",""))
				node.visible=p.followups.has("flower_delivered") if room==s.world.interiors.get("home_haru") else p.followups.has("flower_pick") and not p.followups.has("flower_delivered")
			if key=="repairedtool":node.visible=node.visible and room==s.world.interiors.get("toolshed")
			if key=="ActualPhoto" and node is Sprite3D:
				var stamp: String=str(p.photo_path)+":"+str(FileAccess.get_modified_time(str(p.photo_path))) if FileAccess.file_exists(str(p.photo_path)) else ""
				if not p.photo_rendered or not FileAccess.file_exists(str(p.photo_path)):
					node.visible=false;(node as Sprite3D).texture=null;_photo_stamp=""
				elif _photo_stamp!=stamp or (node as Sprite3D).texture==null:
					var pixels: Image=ResidentVisits.load_photo()
					(node as Sprite3D).texture=ImageTexture.create_from_image(pixels) if pixels!=null else null
					node.visible=pixels!=null;_photo_stamp=stamp

		ResidentInteriorBuilder.sync_state(room)
	var bench_node: Node3D=s.placement.placed_nodes.get(int(p.bench_uid))
	if is_instance_valid(bench_node):
		var cushion: Node3D=bench_node.get_node_or_null("ResidentCushion")
		if p.followups.has("cushion_fixed") and GameState.day>int(p.followups.cushion_fixed.day) and cushion==null:
			var top: float=WorldBuilder.rendered_support_height(bench_node,bench_node.global_position,.8)
			if top>.2 and top<.8:
				var fabric:=MeshInstance3D.new();fabric.name="ResidentCushion"
				var mesh:=BoxMesh.new();mesh.size=Vector3(.58,.055,.40);fabric.mesh=mesh
				fabric.material_override=LivingAction.matte(Color(.61,.73,.58));bench_node.add_child(fabric)
				fabric.global_position=bench_node.global_position+Vector3(0,top-bench_node.global_position.y+.028,0)

func _set_active(node: Node3D,on: bool) -> void:
	node.visible=on
	for body: CollisionObject3D in node.find_children("*","CollisionObject3D",true,false):body.collision_layer=WorldBuilder.L_SOLID if on else 0

func trial() -> void:
	if not ResidentVisits.appointment_now():
		await s.say("narrator","",ResidentVisits.promise_text() if not ResidentVisits.state().promise.is_empty() else "先在纸签约一次傍晚试坐。");return
	var bench: Dictionary=ResidentVisits.bench()
	if bench.is_empty():await s.say("narrator","","先挑一种观看位置，摆下真正的长椅。");return
	if GameState.phase=="market" or GameState.festival_now()!="":await s.say("narrator","","会场正在使用，先别移动街坊。纸签可以改约，长椅保留。");return
	var actor: NPC=s.npcs.haru;var child: NPC=s.npcs.aoi
	var stop: Vector3=ResidentVisits.stop_point()
	var start: Vector3=Vector3(13.6,0,16.5)
	var plan: Dictionary=ProjectRoute.query(s.world,start,stop)
	if not plan.ok:await s.say("narrator","",str(plan.reason));return
	var model: Node3D=s.placement.placed_nodes.get(int(bench.uid))
	if model==null:return
	var support: float=WorldBuilder.rendered_support_height(model,Vector3(bench.x,0,bench.z),.8)
	if support<.2 or support>.8:await s.say("narrator","","椅面没有放平，先把长椅重新摆好。");return
	var previous_cutscene: bool=s.cutscene;s.cutscene=true
	await s.ui.fade_out(.2)
	actor.set_home(false);child.set_home(false)
	actor.place(start,180);child.place(SummerSpace.DEMO,0);child.set_pose("idle")
	previous_camera=get_viewport().get_camera_3d()
	trial_camera=Camera3D.new();trial_camera.fov=56;add_child(trial_camera)
	trial_camera.global_position=start+Vector3(3.5,3.2,-4.5);trial_camera.look_at(start+Vector3.UP*.9);trial_camera.make_current()
	await s.ui.fade_in(.2)
	await s.say("haru","neutral","先别照着照片挤满。我走过去看看，小葵，你站到前边去。")
	trace=[LayoutValidity.position(start)];walking=actor
	s.ui.dlg.hide()
	var arrived: bool=true
	if s.ui.instant:
		actor.place(stop,180)
		for waypoint: Vector3 in plan.path:trace.append(LayoutValidity.position(waypoint))
	else:arrived=await actor.walk_safe(plan.path)
	walking=null;trace.append(LayoutValidity.position(actor.global_position))
	s.ui.dialogue_begin()
	var eye: Vector3=Vector3(float(bench.x),support+1.0,float(bench.z))
	var target: Vector3=child.global_position+Vector3.UP*1.15
	var ray:=PhysicsRayQueryParameters3D.create(eye,target,WorldBuilder.L_SOLID|WorldBuilder.L_PLACED)
	var sight_hit: Dictionary=s.world.get_world_3d().direct_space_state.intersect_ray(ray)
	var clear: bool=sight_hit.is_empty()
	if not clear:print("RESIDENT_SIGHT_BLOCK ",sight_hit.get("collider").get_parent().name," at ",sight_hit.get("position"))
	if not arrived or not clear:
		await s.say("haru","neutral","这里走不过去，或还是看不清。先挪一挪挡路的东西，我们还有时间。")
		_restore_camera();s.cutscene=previous_cutscene;s.main.update_npcs(true);return
	await s.ui.fade_out(.15)
	actor.place(Vector3(float(bench.x),0,float(bench.z)),int(bench.rot)*90)
	actor.set_meta("resident_seated",true)
	var skeleton: Skeleton3D=actor.model.find_child("Skeleton3D",true,false) as Skeleton3D
	if skeleton==null:
		var skeletons: Array[Node]=actor.model.find_children("*","Skeleton3D",true,false)
		if not skeletons.is_empty():skeleton=skeletons[0] as Skeleton3D
	if skeleton!=null:
		seated_pose=PublicSeatPose.new();seated_pose.actor=actor;seated_pose.seat_height=support;skeleton.add_child(seated_pose)
	child.gesture("wave")
	_frame_seat(trial_camera,bench)
	_serve_shared_meal(bench)
	await s.ui.fade_in(.15)
	await get_tree().process_frame
	var result: Dictionary={"arrived":arrived,"seated":seated_pose!=null,"sight_clear":clear,"path":trace.duplicate(true),"bench_anchor":JSON.stringify(LayoutValidity.anchor(bench)),"seat_height":support,"eye":LayoutValidity.position(eye),"look_at":LayoutValidity.position(target)}
	var why: String=ResidentVisits.record_trial(result)
	if why=="":
		await s.say("haru","happy","看得见。你看，她也知道我坐在哪儿。原来我想留下的是这个。")
		await s.say("aoi","happy","那我再跳一次！明年回来，也坐这里好不好？")
		child.set_pose("dance")
		await get_tree().create_timer(.01 if s.ui.instant else 1.1).timeout
		await capture_photo()
		await s.say("narrator","","和子准备了小份餐食，照明由街坊照看。你选的这一张椅子留在场地里。去社区照片侧室，把今天给澪看看。")
	else:await s.say("narrator","",why)
	await s.ui.fade_out(.15)
	if is_instance_valid(seated_pose):seated_pose.queue_free()
	seated_pose=null;actor.remove_meta("resident_seated")
	_restore_camera()
	if is_instance_valid(shared_meal):shared_meal.queue_free()
	shared_meal=null
	s.cutscene=previous_cutscene;s.main.update_npcs(true)
	await s.ui.fade_in(.15)

func _restore_camera() -> void:
	if is_instance_valid(previous_camera):previous_camera.make_current()
	if is_instance_valid(trial_camera):trial_camera.queue_free()
	trial_camera=null;previous_camera=null

func _frame_seat(camera: Camera3D,bench: Dictionary) -> void:
	var seat:=Vector3(float(bench.x),0,float(bench.z))
	var focus: Vector3=(seat+SummerSpace.DEMO)*.5+Vector3.UP*.85
	var distance: float=clampf(seat.distance_to(SummerSpace.DEMO)*1.15,5.3,12.0)
	# Stay inside the south wall and in front of the seat, so the photograph shows its users.
	camera.global_position=focus+Vector3(.6,.65,-1).normalized()*distance
	if int(bench.rot)==3:
		# The east-side view must stay south of the old tree canopy, whose leaves have no walk collision.
		camera.global_position=Vector3(1.95,7.5,26.5);focus=Vector3(1.95,.9,19.5)
	camera.look_at(focus);camera.fov=62 if int(bench.rot)==3 else 56

func _serve_shared_meal(bench: Dictionary) -> void:
	if is_instance_valid(shared_meal):shared_meal.free()
	shared_meal=Node3D.new();shared_meal.name="KazukoTrialSnack";add_child(shared_meal)
	shared_meal.position=Vector3(float(bench.x),0,float(bench.z))+(Vector3(-.4,0,1.4) if int(bench.rot)==3 else Vector3(-1.3,0,-1.3))
	shared_meal.set_meta("contributor","kazuko")
	# A carried folding stool and two paper-wrapped portions; removed when everyone leaves.
	var wood:=Color(.53,.35,.21)
	MealModels.part(shared_meal,"TrayTop","box",Vector3(.54,.055,.42),Vector3(0,.46,0),wood)
	for side: int in 2:
		for front: int in 2:
			MealModels.part(shared_meal,"Leg%d%d"%[side,front],"box",Vector3(.045,.45,.045),Vector3((side-.5)*.42,.225,(front-.5)*.31),wood)
	MealModels.part(shared_meal,"ServingPaper","box",Vector3(.47,.004,.34),Vector3(0,.490,0),Color(.94,.88,.70))
	for portion: int in 2:
		var food: Node3D=MealModels.spawn(s.world,shared_meal,"onigiri",.16)
		if food!=null:food.position+=Vector3((portion-.5)*.23,.492,0)
	MealModels.part(shared_meal,"Teacup","disk",Vector3(.065,.07,.065),Vector3(.18,.525,.13),Color(.68,.77,.63))

func capture_photo() -> bool:
	if DisplayServer.get_name()=="headless":return false
	var bench: Dictionary=ResidentVisits.bench()
	if bench.is_empty():return false
	var old: Camera3D=get_viewport().get_camera_3d()
	var camera:=Camera3D.new();add_child(camera)
	_frame_seat(camera,bench);camera.make_current()
	var labels: Array=[]
	for label: Label3D in s.main.find_children("*","Label3D",true,false):
		if label.visible:labels.append(label);label.visible=false
	var ui_was: bool=s.ui.root.visible;s.ui.root.visible=false
	var marker_was: bool=s.main.marker.visible;s.main.marker.visible=false;s.main.photo_mode=true
	await RenderingServer.frame_post_draw
	var pixels:=get_viewport().get_texture().get_image()
	var folder: String=GameState.photo_path().get_base_dir()
	var path: String=folder.path_join("resident-seat-day%d-%d.png"%[GameState.day,Time.get_ticks_msec()])
	var ok: bool=DirAccess.make_dir_recursive_absolute(folder)==OK and pixels!=null
	if ok:ok=pixels.save_png(path)==OK
	for label: Label3D in labels:if is_instance_valid(label):label.visible=true
	s.ui.root.visible=ui_was;s.main.marker.visible=marker_was;s.main.photo_mode=false
	if is_instance_valid(old):old.make_current()
	camera.queue_free()
	if ok:
		ResidentVisits.state().photo_path=path;ResidentVisits.state().photo_rendered=true
		ResidentVisits.state().photo_day=GameState.day;ResidentVisits.state().photo_context="trial" if s.npcs.haru.get_meta("resident_seated",false) else "revisit"
		ResidentVisits.commit()
	else:GameState.toast.emit("这次照片没有保存，纸签保留重拍入口")
	return ok

func show_photo(compare: bool=false) -> void:
	var p: Dictionary=ResidentVisits.state()
	var pixels: Image=ResidentVisits.load_photo()
	if pixels==null:
		await s.say("narrator","","还没有保存现场照片。试坐结果已经记下；回到庭院纸签可以重拍。")
		return
	var panel: PanelContainer=s.ui._open_modal("resident_photo")
	var column:=VBoxContainer.new();panel.add_child(column)
	column.add_child(UITheme.label("第%d天 · %s"%[int(p.get("photo_day",GameState.day)),"共同试坐" if p.get("photo_context","")=="trial" else "场地补拍"],26))
	var images:=HBoxContainer.new();images.add_theme_constant_override("separation",20);column.add_child(images)
	if compare:
		var old_column:=VBoxContainer.new();images.add_child(old_column)
		old_column.add_child(UITheme.label("2011 · 那年夏祭",22))
		var old_picture:=TextureRect.new();old_picture.texture=load("res://assets/ui/collection/col_photo2011.jpg")
		old_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;old_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;old_picture.custom_minimum_size=Vector2(448,310);old_column.add_child(old_picture)
	var new_column:=VBoxContainer.new();images.add_child(new_column)
	if compare:new_column.add_child(UITheme.label("今年 · 一起试过的位置",22))
	var picture:=TextureRect.new();picture.texture=ImageTexture.create_from_image(pixels)
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.custom_minimum_size=Vector2(448,310) if compare else Vector2(800,430);new_column.add_child(picture)
	var caption: String="这次，春坐着也看得见小葵。" if str(ResidentVisits.state().photo_context)=="trial" else "后来补拍的庭院。椅子还留在我们选的位置。"
	column.add_child(UITheme.label(caption,22))
	column.add_child(s.ui._close_button("收好照片"));s.ui._center(panel)
	if s.ui.instant:await get_tree().process_frame;s.ui.close_modal(false)
	else:await s.ui.panel_closed
