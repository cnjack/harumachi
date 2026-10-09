class_name ResidentMorning
extends Node3D
## Optional residents' scene. Only the existing P08 tea tray changes position.
const PLACES: Array[Vector3] = [Vector3(15.8,0,15.45),Vector3(15.8,0,15.75)]
var s: Story
var bubble: Label3D
var original_tray := Vector3.ZERO
var active := false
var aborted := false
var tick := 0.0
var seen_seconds := 0.0
var placed_now := false
var static_signature := ""
var static_faces: PackedVector3Array
var static_boxes: Array[AABB] = []
var support_cache: Dictionary = {}
var nearby_meshes: Array[MeshInstance3D] = []
var meshes_dirty := true
var ambient_faces: Dictionary = {}

func setup(story: Story) -> void:
	s=story
	original_tray=s.daily.view.tea_root.global_position
	bubble=Label3D.new();bubble.name="MorningNeighbours"
	bubble.font=load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	bubble.font_size=40;bubble.pixel_size=.0042;bubble.outline_size=8
	bubble.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	bubble.position=Vector3(15.8,2.7,15.15)
	add_child(bubble)
	get_tree().node_added.connect(func(node: Node):
		if node is MeshInstance3D:meshes_dirty=true)
	get_tree().node_removed.connect(func(node: Node):
		if node is MeshInstance3D:meshes_dirty=true)
	var base: float=height_at(original_tray)
	if is_finite(base):original_tray.y=base-WorldBuilder.local_aabb(_tray()).position.y+.001
	sync_tray()

func _tray() -> Node3D:
	if not is_instance_valid(s) or not is_instance_valid(s.daily.view):return null
	return s.daily.view.tea_root if is_instance_valid(s.daily.view.tea_root) else null

func _support() -> Node3D:
	return s.world.get_node_or_null("P08") if is_instance_valid(s) and is_instance_valid(s.world) else null

func refresh_geometry() -> bool:
	var model: Node3D=_support()
	if model==null:return false
	var meshes: Array=WorldBuilder.find_meshes(model)
	var signature: String=str(model.global_transform)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh!=null:signature+="|"+str(mesh.global_transform)+":"+str(mesh.mesh.get_instance_id())
	if signature==static_signature:return true
	static_signature=signature;static_faces.clear();static_boxes.clear();support_cache.clear()
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh==null:continue
		var local_faces: PackedVector3Array=mesh.mesh.get_faces()
		for face: int in range(0,local_faces.size()-2,3):
			var first: Vector3=mesh.global_transform*local_faces[face]
			var second: Vector3=mesh.global_transform*local_faces[face+1]
			var third: Vector3=mesh.global_transform*local_faces[face+2]
			static_faces.append_array(PackedVector3Array([first,second,third]))
			static_boxes.append(AABB(first,Vector3.ZERO).expand(second).expand(third))
	return true

func height_at(at: Vector3) -> float:
	if not refresh_geometry():return -INF
	var key:=Vector2(at.x,at.z)
	if support_cache.has(key):return float(support_cache[key])
	var height: float=-INF
	for index: int in static_boxes.size():
		var bounds: AABB=static_boxes[index]
		if at.x<bounds.position.x-.001 or at.x>bounds.end.x+.001 or at.z<bounds.position.z-.001 or at.z>bounds.end.z+.001:continue
		var first: Vector3=static_faces[index*3]
		var second: Vector3=static_faces[index*3+1]
		var third: Vector3=static_faces[index*3+2]
		var normal: Vector3=(second-first).cross(third-first)
		if absf(normal.y)<normal.length()*.85:continue
		var den: float=(second.z-third.z)*(first.x-third.x)+(third.x-second.x)*(first.z-third.z)
		if absf(den)<.000001:continue
		var u: float=((second.z-third.z)*(at.x-third.x)+(third.x-second.x)*(at.z-third.z))/den
		var v: float=((third.z-first.z)*(at.x-third.x)+(first.x-third.x)*(at.z-third.z))/den
		if u>=-.001 and v>=-.001 and u+v<=1.001:
			var found: float=first.y*u+second.y*v+third.y*(1-u-v)
			if found<=1.4:height=maxf(height,found)
	support_cache[key]=height
	return height

func facts() -> Dictionary:
	if not GameState.flags.get("resident_morning",{}) is Dictionary or not GameState.flags.has("resident_morning"):
		GameState.flags["resident_morning"]={}
	var data: Dictionary=GameState.flags.resident_morning
	data.merge({"observed":false,"asked":false,"helped":false,"place":-1,"helped_day":-1},false)
	data.place=int(data.place);data.helped_day=int(data.helped_day)
	return data

func together() -> bool:
	if s.main.in_room or s.world.region!="town" or GameState.phase!="prep":return false
	if GameState.qstate("Q00")!="done" or GameState.day<int(DailyLife.state().introduced_day)+1:return false
	var tray: Node3D=_tray()
	if GameState.minute<450 or GameState.minute>=600 or tray==null:return false
	if not tray.is_visible_in_tree() and not tray.get_meta("morning_blocked",false):return false
	for who: String in ["haru","aoi"]:
		var actor: NPC=s.npcs.get(who)
		if not is_instance_valid(actor) or actor.home or not actor.is_visible_in_tree() or actor.fest_key!="" or actor._moving:return false
		if actor.global_position.distance_to(Vector3(15.1,0,16.0))>5.5:return false
	return true

func prompt() -> String:
	if not together():return ""
	if facts().helped:return "看看苗台留出的空处" if placed_now else "苗台又放了东西 · 可以看看"
	return "春和小葵在看苗 · 可以问一句"

func _process(delta: float) -> void:
	if not is_instance_valid(s) or not is_instance_valid(bubble):return
	tick+=delta
	if active and not together():aborted=true
	if bubble.visible and not s.busy and readable():
		seen_seconds+=delta
		if seen_seconds>=2.0:facts().observed=true
	else:seen_seconds=0.0
	if tick<.5:return
	tick=0.0
	var near: bool=s.player.global_position.distance_to(Vector3(13.2,0,17.25))<6.0
	var show_exchange: bool=together() and near and not s.busy and not facts().helped
	if show_exchange and not bubble.visible:
		for who: String in ["haru","aoi"]:
			var actor: NPC=s.npcs[who]
			if not actor.talking:
				ambient_faces[who]={"yaw":actor._yaw,"generation":actor._placement_generation}
				actor.face(s.npcs["aoi" if who=="haru" else "haru"].global_position)
	elif not show_exchange and bubble.visible:
		for who: String in ambient_faces:
			var actor: NPC=s.npcs.get(who)
			if is_instance_valid(actor) and not actor._moving and not actor.talking and actor._placement_generation==int(ambient_faces[who].generation):actor.face_yaw(float(ambient_faces[who].yaw))
		ambient_faces.clear()
	bubble.visible=show_exchange
	if bubble.visible:
		bubble.text="小葵：现在能浇水吗？\n春：先摸摸土，湿着就先不浇。"
	if not active:sync_tray()

func readable() -> bool:
	if not together():return false
	var camera: Camera3D=get_viewport().get_camera_3d()
	if not is_instance_valid(camera):return false
	var targets: Array[Vector3]=[bubble.global_position]
	for who: String in ["haru","aoi"]:targets.append(s.npcs[who].global_position+Vector3.UP*1.3)
	for at: Vector3 in targets:
		if not camera.is_position_in_frustum(at):return false
		var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,at,WorldBuilder.L_SOLID|WorldBuilder.L_PLACED)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return false
	return true

func _input(event: InputEvent) -> void:
	if active and (event.is_action_pressed("cancel") or event.is_action_pressed("pause")):
		aborted=true;get_viewport().set_input_as_handled()

func _say(who: String,mood: String,text: String) -> void:
	await s.say(who,mood,text)

func handle() -> void:
	if not together():return
	var saved_talking: Dictionary={}
	var previous_camera: Camera3D=get_viewport().get_camera_3d()
	var camera: Camera3D=null
	if not s.ui.instant:
		camera=Camera3D.new();s.main.add_child(camera)
		camera.global_position=Vector3(10.4,4.5,23.8);camera.fov=46
		camera.look_at(Vector3(14.4,1.0,16.8));camera.make_current()
	for who: String in ["haru","aoi"]:
		saved_talking[who]=s.npcs[who].talking
		s.npcs[who].set_talking(true)
		s.npcs[who].face(s.player.global_position)
	await Story.CONVERSATION.introduce(s,"haru")
	if not GameState.flags.get("met_aoi",false) and together():
		await _say("aoi","happy","你就是新搬来的邻居？我叫小葵！是春奶奶的孙女，暑假来晴町住！")
		if together():
			GameState.flags["met_aoi"]=true
			GameState.state_changed.emit()
	if facts().helped:
		if placed_now:await _say("haru","neutral","上回留的空处还在。照苗不必每天多浇一点，先看看土就好。")
		else:await _say("haru","neutral","苗台上又放了东西。上回留空的办法还记得，今天先按现在的地方慢慢做。")
	else:
		await _say("aoi","neutral","春奶奶说，不能看见苗就浇水。我还以为多一点总是好的。")
		await _say("haru","neutral","这几棵先让我照看。想帮忙，就先摸摸土。杯子倒占了手边的地方。")
		var choice: int=await s.ui.choose(["问问怎么知道土还湿着","托盘往里挪一点，留出手边","托盘挪到另一头，多留一块空面","先去忙自己的事"])
		if choice==0 and together():
			var prior: Dictionary=facts().duplicate(true)
			await _say("haru","neutral","指尖碰一下表层，凉凉的、会粘一点土，就先不浇。播种又是另一回事，等你想学时再慢慢来。")
			await _say("aoi","happy","原来可以先等等。我今天就只看这几棵。")
			if together():
				facts().observed=true;facts().asked=true
				if not GameState.save_game():
					GameState.flags.resident_morning=prior
					await _say("narrator","","刚才的话还没有保存下来："+GameState.last_error)
				GameState.state_changed.emit()
		elif choice in [1,2] and together():
			var why: String=await move_tray(choice-1)
			if why!="":await _say("narrator","",why)
			else:
				await _say("aoi","happy","这下手边空出来了。杯子还都在托盘里。")
				await _say("haru","neutral","就这样放着吧。下回喝茶，也给做事的人留一点地方。")
	for who: String in saved_talking:
		if is_instance_valid(s.npcs.get(who)):s.npcs[who].set_talking(bool(saved_talking[who]))
	if is_instance_valid(camera):
		if is_instance_valid(previous_camera):previous_camera.make_current()
		camera.queue_free()

func target_at(index: int) -> Vector3:
	if index<0 or index>=PLACES.size():return Vector3.INF
	var at: Vector3=PLACES[index]
	var tray: Node3D=_tray()
	if tray==null:return Vector3.INF
	var height: float=height_at(at)
	if not is_finite(height):return Vector3.INF
	var box: AABB=WorldBuilder.local_aabb(tray)
	at.y=height-box.position.y+.001
	return at

func legal(at: Vector3) -> bool:
	if not at.is_finite():return false
	var tray: Node3D=_tray()
	var model: Node3D=_support()
	if tray==null or model==null or not refresh_geometry():return false
	var box: AABB=WorldBuilder.local_aabb(tray)
	var base_y: float=at.y+box.position.y
	# Full existing tray/cup footprint, not just a centre ray.
	for xx: float in [box.position.x,box.get_center().x,box.end.x]:
		for zz: float in [box.position.z,box.get_center().z,box.end.z]:
			var height: float=height_at(at+Vector3(xx,0,zz))
			if not is_finite(height) or absf(height-base_y)>.008:return false
	var occupied:=AABB(Vector3(at.x+box.position.x,base_y+.006,at.z+box.position.z),Vector3(box.size.x,box.size.y,box.size.z))
	# P08's joined plants are real obstructions even though they share its model ID.
	for bounds: AABB in static_boxes:
		if occupied.intersects(bounds):return false
	if meshes_dirty:
		nearby_meshes.clear()
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(s.main):
			if not model.is_ancestor_of(mesh) and not tray.is_ancestor_of(mesh):nearby_meshes.append(mesh)
		meshes_dirty=false
	for mesh: MeshInstance3D in nearby_meshes:
		if not is_instance_valid(mesh):continue
		if mesh.mesh==null or not mesh.is_visible_in_tree() or model.is_ancestor_of(mesh) or tray.is_ancestor_of(mesh):continue
		if occupied.intersects(mesh.global_transform*mesh.get_aabb()):return false
	# Keep the existing evening food location on this bench available.
	return not occupied.grow(.09).has_point(Vector3(15.8,base_y+.03,14.6))

func sync_tray() -> void:
	var tray: Node3D=_tray()
	if active or tray==null:return
	var data: Dictionary=facts()
	var target: Vector3=target_at(int(data.place)) if data.helped else original_tray
	placed_now=data.helped and legal(target)
	var usable: bool=placed_now or legal(original_tray)
	tray.set_meta("morning_blocked",not usable)
	if placed_now:tray.global_position=target
	elif usable:tray.global_position=original_tray
	else:tray.visible=false

func move_tray(index: int) -> String:
	if facts().helped:return "托盘已经挪过。后来放的东西先留着，按现在的空处慢慢来。"
	var target: Vector3=target_at(index)
	if not together() or not legal(target):return "这边还放着东西。先留着托盘，不挤到苗或桌沿上。"
	var tray: Node3D=_tray()
	var before: Vector3=tray.global_position
	# Validate the swept footprint too; the visible slide must not cross a plant.
	for step: int in range(1,9):
		if not legal(before.lerp(target,float(step)/8.0)):return "挪过去会碰到东西，先保持原来的位置。"
	var prior: Dictionary=facts().duplicate(true)
	active=true;aborted=false
	if s.ui.instant:tray.global_position=target
	else:
		var tween: Tween=create_tween()
		tween.tween_property(tray,"global_position",target,.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		while tween.is_running() and not aborted:
			await get_tree().process_frame
			if not is_instance_valid(tray) or _support()==null:aborted=true
			elif not together() or not legal(tray.global_position):aborted=true
		if tween.is_running():tween.kill()
	if aborted or not is_instance_valid(tray) or not together() or tray.global_position.distance_to(target)>.003 or not legal(target):
		if is_instance_valid(tray):tray.global_position=before
		active=false
		return "先把托盘留回原处，等两个人有空再挪。"
	facts().observed=true;facts().helped=true;facts().place=index;facts().helped_day=GameState.day
	if not GameState.save_game():
		GameState.flags.resident_morning=prior;tray.global_position=before;active=false
		GameState.state_changed.emit()
		return "托盘放回原处了。进度还没有保存："+GameState.last_error
	active=false;placed_now=true;GameState.state_changed.emit()
	for who: String in ["haru","aoi"]:s.npcs[who].face(Vector3(15.8,.99,15.15))
	Audio.fx_at("dish_place",tray.global_position,-8)
	return ""
