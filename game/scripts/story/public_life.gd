class_name PublicLife
extends RefCounted
## Optional everyday uses share existing purchases and food, without advancing a quest clock.
var s: Story
var current_seat: Interactable
var pose: PublicSeatPose
var standing_at := Vector3.ZERO
func _init(story: Story) -> void:s=story
func handles(id: String) -> bool:return id.begins_with("public_")
func prompt(id: String) -> String:
	if current_seat!=null:return "站起来" if id==current_seat.id else ""
	if id.begins_with("public_reading"):return "坐下来读一会儿"
	if id.begins_with("public_cafe_") and id!="public_cafe_order":return "在咖啡桌旁坐一会儿"
	match id:
		"public_tea":return "给自己倒杯茶"
		"public_news":return "翻翻街坊小报"
		"public_shared_seat":return "在共用桌坐一会儿"
		"public_cafe_order":return "咖啡与拿铁"
	return ""

func sit(point: Interactable) -> bool:
	if not point.has_meta("seat_position"):return false
	standing_at=point.get_parent().to_global(point.get_meta("stand_position"))
	current_seat=point;s.player.seated=true;s.player.seat_target=point;s.player.velocity=Vector3.ZERO
	s.player.global_position=point.get_parent().to_global(point.get_meta("seat_position"))
	s.player.set_facing(deg_to_rad(float(point.get_meta("seat_yaw"))))
	var skeleton:=s.player.model.find_child("Skeleton3D",true,false) as Skeleton3D
	if skeleton==null:
		var skeletons: Array[Node]=s.player.model.find_children("*","Skeleton3D",true,false)
		if not skeletons.is_empty():skeleton=skeletons[0] as Skeleton3D
	if skeleton!=null:
		pose=PublicSeatPose.new();pose.actor=s.player;skeleton.add_child(pose)
	s.player.reset_physics_interpolation();s.main.rig.snap()
	return true

func safe_standing() -> Vector3:
	if current_seat==null:return s.player.global_position
	var room: InteriorBuilder=s.world.interiors[s.main.room_kind]
	for offset: Vector3 in [Vector3.ZERO,Vector3(.45,0,0),Vector3(-.45,0,0),Vector3(0,0,.45),Vector3(0,0,-.45)]:
		var at: Vector3=standing_at+offset
		var local: Vector3=room.to_local(at)
		if absf(local.x)>float(room.spec.size.x)*.5-.35 or absf(local.z)>float(room.spec.size.y)*.5-.35:continue
		var query:=PhysicsShapeQueryParameters3D.new();var shape:=CapsuleShape3D.new();shape.height=1.6;shape.radius=.31;query.shape=shape
		query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
		query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.8);query.exclude=[s.player.get_rid()]
		if s.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return at
	return Vector3.INF

func stand(force: bool=false) -> void:
	if current_seat==null:return
	var at: Vector3=safe_standing()
	if not at.is_finite() and not force:GameState.toast.emit("等身边的人走过，再站起来");return
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
	if item_id!="" and not GameState.remove_item(item_id,1):return false
	var action:=LivingAction.new();s.main.add_child(action);action.setup(s.player,"sip",item_id)
	while not action.finished:await s.main.get_tree().process_frame
	action.queue_free();return true

func handle(point: Interactable) -> void:
	if current_seat!=null:stand();return
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
		await drink();await s.say("narrator","","焙茶还温着。用过的杯子放回水槽边，给下一位街坊留一只干净的。")
		return
	if point.id=="public_news":
		await news();return
	if not sit(point):return
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
