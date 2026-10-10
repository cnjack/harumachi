class_name ShopLife
extends Node3D
## Quiet ambient welcomes and real keeper errands; story/dialogue always has priority.
var main: Node
var content: ShopContent
var elapsed := 0.0
var last_greeting := {"store":-999.0,"bakery":-999.0}
var greeting_count := 0
var completed_trips := 0
var work_distance := 0.0
var _lines := {}
var _near := {"store":false,"bakery":false}
var _work_wait := 10.0
var _working := false
var _forced_work := false
var _actor: NPC
var _generation := 0
var _caption: Label3D
var _caption_left := 0.0
var _greeting_actor: NPC
var _last_voice := ""

func setup(scene: Node) -> void:
	main=scene
	content=ShopContent.new();content.build(main.world)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/shop_life.json"))
	for line: Dictionary in data.lines:_lines[line.id]=line
	_caption=Label3D.new();_caption.name="ShopGreetingCaption"
	_caption.font=load("res://assets/fonts/LXGWWenKai-Medium.ttf");_caption.font_size=36;_caption.pixel_size=.0026
	_caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED;_caption.modulate=Color(.98,.95,.83);_caption.outline_modulate=Color(.24,.26,.36);_caption.outline_size=6
	_caption.visible=false;add_child(_caption);tick(0.0)

func _process(delta: float) -> void:
	if main!=null:tick(delta)

func tick(delta: float) -> void:
	elapsed+=delta;content.update(elapsed)
	_caption_left=maxf(0.0,_caption_left-delta)
	_caption.visible=_caption_left>0.0 and not main.story.busy and main.ui.modal==""
	if is_instance_valid(_greeting_actor):_caption.global_position=_greeting_actor.global_position+Vector3(0,1.9,0)
	if _working and (main.story.busy or main.ui.modal!="" or _actor.talking):cancel_work()
	if not main.loading_ready or main.ui.instant:return
	if main.in_room:
		if main.room_kind not in ["store","bakery"]:return
		_work_wait-=delta
		if not _working and _work_wait<=0.0 and not main.story.busy and main.ui.modal=="":
			_work_wait=20.0;perform_work(main.room_kind)
	else:
		for kind: String in ["store","bakery"]:
			var distance: float=main.player.global_position.distance_to(InteriorBuilder.spec_for(kind).exit)
			if distance<4.0 and not bool(_near[kind]):greet(kind,false)
			_near[kind]=distance<7.0

func opened(kind: String) -> bool:
	var shop: Dictionary=GameState.shop(kind)
	return GameState.hour()>=float(shop.open) and GameState.hour()<float(shop.close) and GameState.weekday()!=int(shop.get("closed_weekday",-1))

func on_enter(kind: String) -> void:
	_generation+=1;_work_wait=8.0
	if kind in ["store","bakery"]:greet(kind,true)

func on_exit() -> void:
	cancel_work();_caption_left=0.0;_caption.visible=false
	if Audio._voice.stream!=null and Audio._voice.stream.resource_path==_last_voice:Audio.stop_voice()

func greet(kind: String,inside: bool) -> bool:
	if kind not in ["store","bakery"] or not opened(kind) or main.story.busy or main.story.cutscene or main.ui.modal!="" or Audio.voice_playing():return false
	if elapsed-float(last_greeting[kind])<45.0:return false
	var npc: NPC=main.npcs["ren" if kind=="bakery" else "kazuko"]
	if npc.home or npc.talking:return false
	if not inside and npc.global_position.distance_to(InteriorBuilder.spec_for(kind).exit)>7.0:return false
	var key: String=kind+ ("_morning" if GameState.hour()<12.0 else "_later")
	var line: Dictionary=_lines[key]
	last_greeting[kind]=elapsed;greeting_count+=1;_greeting_actor=npc
	npc.face(main.player.global_position);npc.gesture("wave" if kind=="bakery" else "bow")
	_caption.text="欢迎光临！\n"+{"store_morning":"今天的菜刚送到。","store_later":"缺什么就跟我说。","bakery_morning":"面包刚出炉。","bakery_later":"甜甜圈和蛋糕也有。"}[key]
	_caption_left=maxf(2.6,Audio.voice(line.who,line.text))
	_last_voice="res://assets/audio/voice/%s/%s.ogg"%[line.who,str(line.text).md5_text()]
	return true

func controls_keeper(id: String) -> bool:
	return _working and is_instance_valid(_actor) and _actor.npc_id==id

func cancel_work() -> void:
	_generation+=1
	if _working and is_instance_valid(_actor) and _actor._safe_walk:_actor.cancel_safe_walk()
	_working=false;_forced_work=false;_work_wait=12.0

func perform_work(kind: String,force: bool=false) -> bool:
	if _working or main.story.busy or main.ui.modal!="" or not opened(kind) or not main.in_room or main.room_kind!=kind:return false
	var npc: NPC=main.npcs["ren" if kind=="bakery" else "kazuko"]
	if npc.home or npc.talking or (npc.anim.busy() and not force):return false
	var spec: Dictionary=InteriorBuilder.spec_for(kind)
	var counter: Vector3=spec.origin+spec.keeper
	if not force and main.player.global_position.distance_to(counter)<2.4:return false
	var work_at: Vector3=spec.origin+spec.work_at
	var route: Array[Vector3]=NPC.MOTION_ROUTE.query(npc,npc.global_position,work_at)
	if route.is_empty():return false
	_working=true;_forced_work=force;_actor=npc
	var generation: int=_generation
	var beginning: Vector3=npc.global_position
	npc._end_idle="tend";npc._end_yaw=deg_to_rad(0.0 if kind=="bakery" else 90.0)
	var arrived: bool=await npc.walk_safe(route)
	if generation!=_generation or not arrived:_working=false;return false
	work_distance+=npc.global_position.distance_to(beginning)
	npc.set_pose("tend")
	await get_tree().create_timer(.15 if main.ui.instant else 2.0).timeout
	if generation!=_generation or main.story.busy:_working=false;return false
	content.replenish(kind,elapsed)
	var returning: Array[Vector3]=NPC.MOTION_ROUTE.query(npc,npc.global_position,counter)
	if returning.is_empty():_working=false;return false
	npc._end_idle="idle";npc._end_yaw=deg_to_rad(float(spec.keeper_yaw))
	var returned: bool=await npc.walk_safe(returning)
	_working=false;_forced_work=false;_work_wait=22.0
	if generation==_generation and returned:
		completed_trips+=1;content.update(elapsed);return true
	return false
