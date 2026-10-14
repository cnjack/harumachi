class_name PublicLife
extends RefCounted
## Optional everyday uses share existing purchases and food, without advancing a quest clock.
var s: Story
var current_seat: Interactable
var pose: PublicSeatPose
var standing_at := Vector3.ZERO
var outdoor: RefCounted
var _transition: Tween
var _transition_generation := 0
func _init(story: Story) -> void:
	s=story

func setup() -> void:
	outdoor = load("res://scripts/world/outdoor_seating.gd").new()
	outdoor.setup(s)
func handles(id: String) -> bool:
	return id.begins_with("public_") or (id=="farm_bench" and (current_seat!=null or (not s.lore.pending(id) and not s.fest.handles(id))))
func prompt(id: String) -> String:
	if current_seat!=null:return "站起来" if id==current_seat.id else ""
	if id.begins_with("public_rest_") or id=="farm_bench":return "坐下歇一会儿"
	if id.begins_with("public_reading"):return "坐下来读一会儿"
	if id.begins_with("public_cafe_") and id!="public_cafe_order":return "在咖啡桌旁坐一会儿"
	match id:
		"public_tea":return "给自己倒杯茶"
		"public_news":return "翻翻街坊小报"
		"public_shared_seat":return "在共用桌坐一会儿"
		"public_cafe_order":return "咖啡与拿铁"
	return ""

func sit(point: Interactable) -> bool:
	if not is_instance_valid(point) or not point.has_meta("seat_position") or current_seat!=null:return false
	var seat_at: Vector3 = point.get_parent().to_global(point.get_meta("seat_position"))
	standing_at=point.get_parent().to_global(point.get_meta("stand_position"))
	# Outdoor seats are close interactions on existing benches, never a remote
	# pull from across the farm. Check a complete capsule before taking the place.
	if point.has_meta("rest_region"):
		if s.player.global_position.distance_to(standing_at)>1.3 or not _seat_available(point,seat_at):return false
	current_seat=point;s.player.seated=true;s.player.seat_target=point;s.player.velocity=Vector3.ZERO
	s.player.global_position=seat_at
	s.player.set_facing(deg_to_rad(float(point.get_meta("seat_yaw"))))
	var skeleton:=s.player.model.find_child("Skeleton3D",true,false) as Skeleton3D
	if skeleton==null:
		var skeletons: Array[Node]=s.player.model.find_children("*","Skeleton3D",true,false)
		if not skeletons.is_empty():skeleton=skeletons[0] as Skeleton3D
	if skeleton!=null:
		pose=PublicSeatPose.new();pose.actor=s.player;pose.seat_height=float(point.get_meta("seat_height",.48));skeleton.add_child(pose)
	s.player.reset_physics_interpolation();s.main.rig.snap()
	return true

func _seat_available(point: Interactable, at: Vector3) -> bool:
	var excluded: Array[RID] = [s.player.get_rid()]
	var support: Node = s.main.get_node_or_null(point.get_meta("seat_support", NodePath()))
	if support==null or not support is Node3D:return false
	for body: CollisionObject3D in support.find_children("*","CollisionObject3D",true,false):excluded.append(body.get_rid())
	var query:=PhysicsShapeQueryParameters3D.new();var capsule:=CapsuleShape3D.new();capsule.height=1.5;capsule.radius=.28
	query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.8)
	query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS;query.exclude=excluded
	return s.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func sit_down(point: Interactable) -> bool:
	var before: Vector3=s.player.global_position
	if not sit(point):return false
	if s.ui.instant or pose==null:return true
	var destination: Vector3=s.player.global_position
	s.player.global_position=before;pose.blend=0.0
	_transition=s.main.create_tween().set_parallel(true)
	_transition_generation+=1
	var generation: int=_transition_generation
	var transition: Tween=_transition
	_transition.tween_property(s.player,"global_position",destination,.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_property(pose,"blend",1.0,.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while transition.is_valid() and transition.is_running() and generation==_transition_generation:
		await s.main.get_tree().process_frame
	if generation!=_transition_generation or current_seat!=point:return false
	_transition=null
	return true

func safe_standing() -> Vector3:
	if current_seat==null:return s.player.global_position
	var room: InteriorBuilder=s.world.interiors.get(s.main.room_kind) if s.main.in_room else null
	for offset: Vector3 in [Vector3.ZERO,Vector3(.45,0,0),Vector3(-.45,0,0),Vector3(0,0,.45),Vector3(0,0,-.45)]:
		var at: Vector3=standing_at+offset
		if room!=null:
			var local: Vector3=room.to_local(at)
			if absf(local.x)>float(room.spec.size.x)*.5-.35 or absf(local.z)>float(room.spec.size.y)*.5-.35:continue
		var ground:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.45,at-Vector3.UP*.65,WorldBuilder.L_GROUND)
		var floor_hit: Dictionary=s.player.get_world_3d().direct_space_state.intersect_ray(ground)
		if floor_hit.is_empty():continue
		at.y=(floor_hit.position as Vector3).y
		var query:=PhysicsShapeQueryParameters3D.new();var shape:=CapsuleShape3D.new();shape.height=1.6;shape.radius=.31;query.shape=shape
		query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
		query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.8);query.exclude=[s.player.get_rid()]
		if s.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return at
	return Vector3.INF

func stand(force: bool=false) -> void:
	if current_seat==null:return
	if _transition!=null and _transition.is_valid():
		if not force:return
		_transition_generation+=1;_transition.kill();_transition=null
	var at: Vector3=safe_standing()
	if not at.is_finite() and not force:GameState.toast.emit("等身边的人走过，再站起来");return
	if not force and not s.ui.instant and is_instance_valid(pose):
		_transition=s.main.create_tween().set_parallel(true)
		_transition_generation+=1
		var generation: int=_transition_generation
		var transition: Tween=_transition
		_transition.tween_property(pose,"blend",0.0,.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_transition.tween_property(s.player,"global_position",at,.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		while transition.is_valid() and transition.is_running() and generation==_transition_generation:
			await s.main.get_tree().process_frame
		if generation!=_transition_generation or current_seat==null:return
		_transition=null
	if is_instance_valid(pose):pose.queue_free()
	pose=null
	if s.player.has_meta("seated_mouth"):s.player.remove_meta("seated_mouth")
	s.player.seated=false;s.player.seat_target=null;s.player.global_position=at if at.is_finite() else standing_at;s.player.velocity=Vector3.ZERO
	s.player.reset_physics_interpolation();s.main.rig.snap();current_seat=null

func save_position() -> Vector3:
	if current_seat==null:return s.player.global_position
	var at: Vector3=safe_standing()
	return at if at.is_finite() else standing_at

func buy_drink(id: String) -> String:
	if id not in ["coffee","cafe_latte"]:return "柜台没有这杯饮品"
	if not s.main.in_room or s.main.room_kind!="bakery" or not s.main.shop_life.opened("bakery"):return "现在不在咖啡营业时间"
	return GameState.buy_item(id,1)

func drink(item_id: String="") -> bool:
	if item_id!="" and not GameState.has(item_id):return false
	var action:=LivingAction.new();s.main.add_child(action)
	action.allow_cancel=true;action.duration=.08 if s.ui.instant else 1.4
	if is_instance_valid(current_seat) and current_seat.has_meta("table_position"):
		action.surface_at=current_seat.get_parent().to_global(current_seat.get_meta("table_position"))
	action.setup(s.player,"sip",item_id)
	while not action.finished:await s.main.get_tree().process_frame
	var completed: bool=not action.cancelled
	action.queue_free()
	if not completed:return false
	return item_id=="" or GameState.remove_item(item_id,1)

func handle(point: Interactable) -> void:
	if current_seat!=null:await stand();return
	if point.id=="public_cafe_order":
		if not s.main.shop_life.opened("bakery"):
			await s.say("narrator","","咖啡机已经清洗好了。明早七点再来，座位现在仍可以坐。");return
		var choice: int=await s.ui.choose(["咖啡 · %d生活币"%int(GameState.item("coffee").price),"拿铁 · %d生活币"%int(GameState.item("cafe_latte").price),"先看看"])
		if choice<0 or choice>1:return
		var id: String="coffee" if choice==0 else "cafe_latte"
		var error: String=buy_drink(id)
		if error!="":await s.say("narrator","",error)
		else:await s.say("narrator","","杯子装进了随身袋。可以带走，也可以在窗边坐下来喝。")
		return
	if point.id=="public_tea":
		if await drink():await s.say("narrator","","焙茶还温着。用过的杯子放回水槽边，给下一位街坊留一只干净的。")
		return
	if point.id=="public_news":
		await news();return
	if not await sit_down(point):return
	if point.id=="farm_bench":
		var rest_choice: int=await s.ui.choose(["坐着看一小时河水","起身","就在这里歇一会儿"])
		if rest_choice==0:
			await s.ui.fade_out(.25)
			GameState.skip_to(minf(GameState.minute+60.0,23.0*60.0))
			s.world.update_time(GameState.minute,GameState.weather,true)
			await s.ui.fade_in(.25)
		if rest_choice in [0,1]:await stand();return
		GameState.toast.emit("坐着歇一会儿 · E或Esc站起来")
		return
	if point.id.begins_with("public_rest_"):
		await s.say("narrator","",str(point.get_meta("rest_description","先放松肩膀，在这里坐一会儿。")))
		GameState.toast.emit("坐着歇一会儿 · E或Esc站起来")
		return
	if point.id.begins_with("public_reading"):
		await s.say("narrator","","《晴町小志》翻到了旧车站那一页：夏天的末班车晚半小时，好让看完烟火的人慢慢走回来。页角还夹着一片干叶。")
	elif point.id=="public_shared_seat":
		await news()
	else:
		var category: int=await s.ui.choose(["坐着看看窗外","喝带来的咖啡","吃带来的甜点","吃带来的面包"])
		var available: Array[String]=[]
		var options: Array[String]=[]
		var groups: Array=[[],["coffee","cafe_latte"],["shortcake","chocolate_cake","basque_cheesecake","fruit_tart"],["donut","cream_bun","croissant","anpan","melon_pan","curry_pan"]]
		if category>0 and category<groups.size():
			for id: String in groups[category]:
				if GameState.has(id):available.append(id);options.append(GameState.item_name(id))
			if available.is_empty():await s.say("narrator","","随身袋里还没带这一类。柜台可以挑选，座位留给你慢慢坐。")
			else:
				options.append("先放着")
				var choice: int=await s.ui.choose(options)
				if choice>=0 and choice<available.size():
					var id: String=available[choice]
					if id in ["coffee","cafe_latte"]:await drink(id)
					elif GameState.remove_item(id,1):
						var action:=LivingAction.new();s.main.add_child(action)
						action.surface_at=point.get_parent().to_global(point.get_meta("table_position"));action.setup(s.player,"eat",id)
						while not action.finished:await s.main.get_tree().process_frame
						action.queue_free()
	GameState.toast.emit("坐着歇一会儿 · E或Esc站起来")

func news() -> void:
	var notice: String=["图书交换：看完的书请放回窗边书架，扉页写了名字的先别带走。","周日下午修伞。坏伞和松了把手的篮子，都可以带来一起想办法。","茶水角今天用的是和子阿姨送来的焙茶。杯子不够时，请把洗好的倒扣晾着。"][posmod(GameState.day-1,3)]
	await s.say("narrator","","《街坊小报》\n"+notice)
