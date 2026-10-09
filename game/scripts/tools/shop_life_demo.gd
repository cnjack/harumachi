extends Node
## Native movie and temporal evidence from real visits, voice playback and collision-checked work.
var main: Node
var directory := ""
var samples: Array[Dictionary] = []

func _ready() -> void:
	main=get_parent()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shop-life-demo="):directory=argument.trim_prefix("--shop-life-demo=")
	DirAccess.make_dir_recursive_absolute(directory)
	await get_tree().process_frame
	GameState.clock_paused=true;GameState.day=1;GameState.minute=600;GameState.weather="sunny";Audio.game_on=true
	main.ui.set_hud_visible(false);main.ui.panels.set_cards_visible(false)
	await main.enter_interior("store");main.shop_life._work_wait=999.0
	main.player.global_position=InteriorBuilder.SPECS.store.origin+Vector3(.6,.05,1.9)
	if OS.get_cmdline_user_args().has("--shop-display-review"):
		await display_review();return
	camera("store",Vector3(1.2,4.8,6.2),Vector3(-1.4,1.0,0));await hold("store_welcome",5)
	var before: int=main.shop_life.completed_trips
	main.shop_life.perform_work("store",true)
	await hold("store_work",6)
	main.shop_life._work_wait=999.0
	camera("store",Vector3(1.85,1.05,4.3),Vector3(1.85,.63,3.0));await hold("sushi_bento",3)
	camera("store",Vector3(3.9,1.95,-.78),Vector3(5.05,1.92,-.8));await hold("television_town",3)
	main.shop_life.elapsed=12.0;GameState.weather="rain";main.shop_life.tick(0.0);await hold("television_weather",3)
	await main.exit_room();GameState.weather="sunny";GameState.minute=540;Audio.stop_voice()
	await main.enter_interior("bakery");main.shop_life._work_wait=999.0
	main.player.global_position=InteriorBuilder.SPECS.bakery.origin+Vector3(0,.05,2)
	camera("bakery",Vector3(.8,4.4,6.0),Vector3(.6,1.0,0));await hold("bakery_welcome",5)
	main.shop_life.perform_work("bakery",true);await hold("bakery_work",6);main.shop_life._work_wait=999.0
	camera("bakery",Vector3(.48,1.45,2.15),Vector3(.48,.83,.53));await hold("cake_case",4)
	camera("bakery",Vector3(-2.7,1.20,1.15),Vector3(-2.7,.76,-.3));await hold("pastry_shelf",3)
	var file:=FileAccess.open(directory.path_join("motion.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"greetings":main.shop_life.greeting_count,"new_work_trips":main.shop_life.completed_trips-before,"work_distance":main.shop_life.work_distance,"replenishments":main.shop_life.content.restock_count,"samples":samples},"  "))
	Audio.silence();get_tree().quit(0)

func camera(kind: String,at: Vector3,focus: Vector3) -> void:
	main.player.visible=false;main.rig.process_mode=Node.PROCESS_MODE_DISABLED
	main.rig.cam.global_position=InteriorBuilder.spec_for(kind).origin+at
	main.rig.cam.look_at(InteriorBuilder.spec_for(kind).origin+focus)

func display_review() -> void:
	Audio.stop_voice();main.shop_life._caption_left=0.0
	main.ui.set_hud_visible(false);main.ui.panels.set_cards_visible(false)
	main.shop_life.elapsed=8.25;main.shop_life.tick(0.0)
	camera("store",Vector3(3.9,1.95,-.78),Vector3(5.05,1.92,-.8));await hold("crt_signal",7)
	camera("store",Vector3(4.20,2.05,.02),Vector3(5.05,1.93,-.8));await hold("crt_curved_side",3)
	camera("store",Vector3(-.96,1.18,.7),Vector3(-.96,.78,-.8));await hold("varied_groceries",3)
	await main.exit_room();GameState.minute=540;await main.enter_interior("bakery")
	Audio.stop_voice();main.shop_life._caption_left=0.0;main.shop_life._work_wait=999.0
	main.ui.set_hud_visible(false);main.ui.panels.set_cards_visible(false)
	camera("bakery",Vector3(-2.7,1.20,1.15),Vector3(-2.7,.76,-.3));await hold("varied_pastries",3)
	var file:=FileAccess.open(directory.path_join("display-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"samples":samples,"fixture":"fixed date and cameras; real CRT shader time and shop displays"},"  "))
	Audio.silence();get_tree().quit(0)

func hold(label: String,seconds: int) -> void:
	for second: int in seconds:
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("%s_%02d.png"%[label,second]))
		samples.append({"label":label,"second":second,"ren":str(main.npcs.ren.global_position),"kazuko":str(main.npcs.kazuko.global_position),"ren_clip":main.npcs.ren.anim.ap.current_animation,"kazuko_clip":main.npcs.kazuko.anim.ap.current_animation,"voice_playing":Audio.voice_playing(),"completed_trips":main.shop_life.completed_trips,"broadcast_channel":main.shop_life.content.televisions[0].screen.material_override.get_shader_parameter("channel"),"snow_amount":main.shop_life.content.televisions[0].screen.material_override.get_shader_parameter("snow_amount"),"rain":GameState.weather})
