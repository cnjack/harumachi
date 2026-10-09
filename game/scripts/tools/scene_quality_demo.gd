extends Node
var main: Node
var results: Dictionary={}
func _ready() -> void:
	main=get_parent();await run()
func argument(name_value: String) -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with(name_value+"="):return value.trim_prefix(name_value+"=")
	return "user://scene-quality"
func sample_frames() -> Dictionary:
	var times: Array[float]=[]
	for index: int in 35:await get_tree().process_frame
	var previous: int=Time.get_ticks_usec()
	for index: int in 150:
		await get_tree().process_frame
		var now: int=Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now
	var total: float=0
	for time_value: float in times:total+=time_value
	times.sort()
	return {"frames":times.size(),"mean_ms":total/times.size(),"p95_ms":times[142],"p99_ms":times[148],"max_ms":times[-1]}
func run() -> void:
	var out: String=argument("--scene-quality-demo");DirAccess.make_dir_recursive_absolute(out)
	GameState.clock_paused=true;Audio.game_on=true
	main.story.busy=true;main.ui.set_hud_visible(false)
	await main.enter_interior("workroom")
	main.player.global_position=InteriorBuilder.SPECS.workroom.origin+Vector3(-1.2,.05,1.0)
	main.rig.snap()
	results.workroom_static=await sample_frames()
	var beginning: Vector3=main.player.global_position
	main.player.auto_move=Vector3(-1,0,0)
	results.workroom_walk=await sample_frames();main.player.auto_move=Vector3.ZERO
	results.walk_metres=main.player.global_position.distance_to(beginning)
	# Record the actual engine mix: left and right sources, a distant silent source,
	# then the existing sip and food-to-empty-plate animation at its own cue phase.
	Audio._set_bus("Music",0);Audio._set_bus("Ambience",0);Audio._set_bus("SFX",0);Audio._set_bus("Voice",0)
	Audio._set_bus("Foley",.8)
	var record:=AudioEffectRecord.new();var bus: int=AudioServer.get_bus_index("Foley")
	AudioServer.add_bus_effect(bus,record);record.set_recording_active(true)
	var ears: AudioListener3D=main.player.ears
	var right: Vector3=ears.global_basis.x
	Audio.fx_at("dish_place",ears.global_position-right*2,-5)
	await get_tree().create_timer(.65).timeout
	Audio.fx_at("dish_place",ears.global_position+right*2,-5)
	await get_tree().create_timer(.65).timeout
	Audio.fx_at("dish_place",ears.global_position+right*30,-5)
	await get_tree().create_timer(.65).timeout
	var drink:=LivingAction.new();main.add_child(drink);drink.setup(main.player,"sip")
	while not drink.finished:await get_tree().process_frame
	results.sip_cue_played=bool(drink.get_meta("foley_played",false));drink.queue_free()
	await get_tree().create_timer(.3).timeout
	record.set_recording_active(false)
	var audio: AudioStreamWAV=record.get_recording();results.audio_saved=audio.save_to_wav(out.path_join("spatial-tabletop.wav"))==OK
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	main.story.busy=false;GameState.quests.Q11={"state":"done","step":3};GameState.quests.Q12={"state":"available","step":0}
	WorkshopProject.start("plan","guide","wave");await get_tree().process_frame
	main.player.global_position=InteriorBuilder.SPECS.workroom.origin+Vector3(1.8,.05,3.25)
	main.rig.pitch=46;main.rig.dist=9.4;main.rig.snap()
	results.workroom_with_lantern=await sample_frames()
	get_viewport().get_texture().get_image().save_png(out.path_join("workroom-in-progress.png"))
	var file:=FileAccess.open(out.path_join("runtime.json"),FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
	Audio.silence();get_tree().quit()
