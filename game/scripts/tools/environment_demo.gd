extends Node
## Record real rendered movement with --write-movie and an isolated HARUMACHI_SAVE_DIR.
var main: Node
var evidence_directory := ""
var samples: Array[Dictionary] = []

func _ready() -> void:
	main=get_parent()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--environment-demo="):evidence_directory=argument.trim_prefix("--environment-demo=")
	await get_tree().process_frame
	GameState.clock_paused=true;GameState.minute=630.0
	Audio.game_on=true
	main.ui.set_hud_visible(false);main.ui.panels.set_cards_visible(false)
	main.rig.process_mode=Node.PROCESS_MODE_DISABLED;main.player.visible=false
	for npc: NPC in main.npcs.values():npc.visible=false
	await segment("chime","town","sunny",Vector3(-1,.1,-14),Vector3(-1.1,2.22,-14.3),Vector3(-1.25,2.22,-15.7),5.0)
	await segment("tree_leaves","town","sunny",Vector3(1.5,.1,4),Vector3(-1.5,1.9,1),Vector3(4,3.4,7),5.0)
	GameState.placements=[{"uid":990,"item":"bunting","x":5.5,"z":11.2,"rot":0},{"uid":991,"item":"lantern","x":9.5,"z":12.4,"rot":0}]
	main.placement.rebuild()
	await segment("bunting_lantern","town","sunny",Vector3(8,.1,10),Vector3(7,2.1,7.5),Vector3(7.5,1.8,12),5.0)
	await segment("walking_cat","town","sunny",Vector3(19.7,.1,56),Vector3(19,1,53.4),Vector3(19.8,.2,55.0),5.0)
	await segment("bank_breeze","farm","sunny",Vector3(137,.1,15),Vector3(139,1.6,15),Vector3(133,.5,17),5.0)
	await segment("bank_rain","farm","rain",Vector3(137,.1,15),Vector3(139,1.6,15),Vector3(133,.5,17),5.0)
	var file:=FileAccess.open(evidence_directory.path_join("native-motion.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"samples":samples,"plant_count":main.get_node("EnvironmentLife").plants.roots.size()},"  "))
	Audio.silence();get_tree().quit(0)

func segment(label: String,region: String,weather: String,at: Vector3,camera_at: Vector3,focus: Vector3,seconds: float) -> void:
	GameState.weather=weather;main.in_room=false;main.world.set_indoor_look(false);main.world.set_region(region)
	var origin: Vector3=FarmBuilder.ORIGIN if region=="farm" else Vector3.ZERO
	main.player.global_position=origin+at
	main.rig.global_position=origin+at
	main.rig.cam.global_position=origin+camera_at;main.rig.cam.look_at(origin+focus)
	main.world.update_time(GameState.minute,weather,true);main.weather_fx.set_weather(weather,false)
	Audio.play_amb(main.outdoor_amb(),.3)
	var life: EnvironmentLife=main.get_node("EnvironmentLife")
	for index: int in int(seconds):
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(evidence_directory.path_join("%s_%02d.png"%[label,index]))
		var cat: Node3D=main.life.roaming_cats[0]
		samples.append({"segment":label,"second":index,"chime_rotation":str(life.chimes[0].pivot.rotation),"wind":life.wind_power,
			"leaves":life.leaves.size(),"cloud_offset":str(main.world.sky_mat.get_shader_parameter("cloud_offset")),
			"cat_position":str(cat.global_position),"cat_animation":cat.player.current_animation,
			"chime_playing":life.chimes[0].sound.playing,
			"river_gain":life.river_gain,"river_playing":life.river_audio.playing,"wind_playing":life.wind_audio.playing})
