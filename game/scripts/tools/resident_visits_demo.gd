extends "res://scripts/tools/activity_visual_demo.gd"
## Declared prior-market fixture; all new doors, pictures, choices and the walking trial use real input.
var _captured: Dictionary={}
var first_route: Dictionary={}
var standpoints: Array=[]

func _ready() -> void:
	main=get_parent()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):folder=arg.substr(11)
	if folder=="":folder="/tmp/harumachi-resident-visits"
	DirAccess.make_dir_recursive_absolute(folder);await frames(25)
	GameState.new_game();GameState.clock_paused=true;GameState.flags.erase("arrival_home");GameState._ui_locks.clear()
	GameState.quests.Q00={"state":"done","step":2};GameState.quests.Q05={"state":"done","step":5}
	GameState.quests.Q10={"state":"done","step":2};Progress.find("col_photo2011");Progress.find("col_letter")
	GameState.day=5;GameState.minute=18*60;GameState.phase="prep"
	NPC.roam_enabled=false;Progress.quiet=true;main.ui.instant=false;main.ui.auto=false
	main.world.sync_festivals();main._restore();ResidentVisits.invite_after_market()
	await use_visit("visit_home_haru_door",[])
	check("real E enters Haru's invited home",main.in_room and main.room_kind=="home_haru")
	if not main.in_room:await finish();return
	await shot("01_haru_home_entered")
	await use_visit("visit_home_haru_memory",[])
	check("real image reading leads to the tool-room invitation",ResidentVisits.state().blueprint_seen and ResidentVisits.unlocked("toolshed"))
	await use_visit("visit_home_haru_exit",[])
	await use_visit("east_end",[])
	check("the real farm gate changes region before the tool-room trip",main.world.region=="farm" and not main.in_room)
	await use_visit("visit_toolshed_door",[])
	check("toolshed entry uses its own real door",main.room_kind=="toolshed")
	await use_visit("visit_toolshed_memory",[0])
	check("measuring and the actual first option promise tomorrow",ResidentVisits.state().measured and ResidentVisits.state().promise.get("day",0)==6)
	await shot("02_measured_tools_and_promise")
	await use_visit("visit_toolshed_exit",[])
	check("leaving the tool-room restores farm weather and region",not main.in_room and main.world.region=="farm")
	await use_visit("farm_exit",[])
	await use_visit("visit_trial",[0])
	check("a real menu choice places the near chair",ResidentVisits.state().scheme=="near" and not ResidentVisits.bench().is_empty())
	await shot("03_chair_placed")
	# Date fixture avoids claiming an automated scene measures a natural day of play.
	GameState.day=6;GameState.minute=17.5*60;main.world.sync_festivals();main.update_npcs(true)
	await use_visit("visit_trial",[2])
	check("actual native NPC walking and seating fulfill the appointment",not ResidentVisits.state().trial.is_empty() and ResidentVisits.state().promise.get("status","")=="kept")
	check("the saved photograph is a real render of this trial",ResidentVisits.state().photo_rendered and FileAccess.file_exists(str(ResidentVisits.state().photo_path)))
	await shot("04_trial_result")
	await use_visit("center_door",[])
	await use_visit("visit_photo_room_door",[])
	await use_visit("visit_photo_room_memory",[])
	check("two real picture panels lead to Mio's private invitation",ResidentVisits.state().photo_compared and ResidentVisits.unlocked("home_mio"))
	await shot("05_photos_compared")
	GameState.save_game();var before: Dictionary=ResidentVisits.state().duplicate(true)
	GameState.flags.clear();GameState.load_game();main._restore();await frames(4)
	check("SQLite reload keeps the same photograph and visit room",main.room_kind=="photo_room" and ResidentVisits.state().photo_path==before.photo_path and ResidentVisits.state().bench_uid==int(before.bench_uid))
	await use_visit("visit_photo_room_exit",[])
	check("photo side-room returns to the community room",main.room_kind=="workroom")
	await use_visit("workroom_exit",[])
	GameState.minute=18.5*60
	await use_visit("visit_home_mio_door",[])
	check("the actual street door enters Mio's home from a clear ground standpoint",main.in_room and main.room_kind=="home_mio")
	if not main.in_room or main.room_kind!="home_mio":await finish();return
	await use_visit("visit_home_mio_memory",[0])
	check("a chosen named invitation is written in Mio's actual home",ResidentVisits.state().followups.has("invitation_written"))
	await shot("06_mio_private_home")
	await use_visit("visit_home_mio_exit",[])
	GameState.day=7;GameState.minute=11*60
	await use_visit("visit_post_door",[])
	check("the actual post-office door enters its public interior",main.in_room and main.room_kind=="post")
	if not main.in_room or main.room_kind!="post":await finish();return
	await use_visit("visit_post_memory",[0])
	check("ordinary post-office input really sends this letter",ResidentVisits.state().followups.has("letter_sent"))
	await shot("07_letter_posted")
	first_route=ResidentVisits.state().duplicate(true)
	await use_visit("visit_post_exit",[])
	# Alternate-branch fixture: replay the outstanding appointment with the other real layout.
	ResidentVisits.state().trial={};ResidentVisits.state().photo_rendered=false;ResidentVisits.state().phase="measured"
	ResidentVisits.state().resident_setup=false;_captured.erase("seated")
	await use_visit("visit_trial",[1])
	check("the alternate real choice leaves an east-side chair",ResidentVisits.state().scheme=="path")
	var chair_uid: int=ResidentVisits.state().bench_uid
	await use_visit("visit_trial",[4])
	check("cancelling keeps the chair and exposes the neighbours' actual fallback",ResidentVisits.state().bench_uid==chair_uid and main.story.visits.view.fallback.visible)
	await shot("08_cancelled_neighbour_setup")
	await use_visit("visit_trial",[3,0])
	GameState.day=int(ResidentVisits.state().promise.day);GameState.minute=20*60;ResidentVisits.tick();main.story.visits.view.sync_state()
	check("a missed appointment retains its real chair and offers another date",ResidentVisits.state().promise.status=="missed" and ResidentVisits.state().bench_uid==chair_uid)
	await shot("09_missed_appointment")
	await use_visit("visit_trial",[3,0])
	GameState.day=int(ResidentVisits.state().promise.day);GameState.minute=17.5*60;main.world.sync_festivals();main.update_npcs(true)
	await use_visit("visit_trial",[2])
	check("the east-side route also works after cancellation and a missed occasion",ResidentVisits.state().trial.get("scheme","")=="path" and ResidentVisits.state().photo_rendered)
	await shot("10_alternate_trial")
	await finish()

func use_visit(id: String,picks: Array) -> void:
	var point: Interactable=null
	for candidate: Interactable in get_tree().get_nodes_in_group("interactables"):
		if candidate.id==id:point=candidate;break
	if point==null:failures.append("missing interactable "+id);return
	var options: Array[Vector3]=[Vector3.LEFT,Vector3.RIGHT,Vector3.BACK,Vector3.FORWARD]
	if id.ends_with("_exit") or id=="workroom_exit":options=[Vector3.FORWARD,Vector3.LEFT,Vector3.RIGHT]
	var targeted:=false
	var candidates: Array[Vector3]=[]
	for distance: float in [.95,1.25,1.45]:
		for direction: Vector3 in options:candidates.append(Vector3(point.global_position.x,.1,point.global_position.z)+direction*distance)
	for candidate: Vector3 in candidates:
		var probe:=PhysicsShapeQueryParameters3D.new();probe.shape=NPC.MOTION_ROUTE.capsule()
		probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_BLOCK
		probe.transform=Transform3D(Basis.IDENTITY,candidate+Vector3.UP*.8)
		if not main.get_world_3d().direct_space_state.intersect_shape(probe,1).is_empty():continue
		main.player.global_position=candidate
		main.player.velocity=Vector3.ZERO;main.player.face_towards(point.global_position);main.rig.snap();await frames(10)
		if main.player.target==point:targeted=true;break
	if not targeted:failures.append("E cannot target "+id+" got "+(main.player.target.id if main.player.target else "none"));return
	standpoints.append({"id":id,"y":main.player.global_position.y})
	if main.player.global_position.y>.35:failures.append("interaction stands on furniture "+id);return
	await tap(KEY_E)
	var remaining: Array=picks.duplicate();var deadline: int=Time.get_ticks_msec()+110000
	while (main.story.busy or main._transition) and Time.get_ticks_msec()<deadline:
		if main.ui.modal!="":
			var key: String=id+"_"+str(main.ui.modal)
			if not _captured.has(key):await shot(key);_captured[key]=true
			await tap(KEY_ESCAPE)
		elif main.ui.dlg.visible:
			if main.ui.dlg_choices.visible:
				var selected: int=int(remaining.pop_front()) if not remaining.is_empty() else 0
				await tap(KEY_1+selected)
			else:
				if main.npcs.haru.get_meta("resident_seated",false) and not _captured.has("seated"):
					await frames(18);await shot("trial_haru_really_seated_"+str(ResidentVisits.state().scheme));_captured.seated=true
				await frames(9);await tap(KEY_E)
		await frames(3)
	if main.story.busy or main._transition:failures.append("interaction timeout "+id)

func finish() -> void:
	check("dialogue, camera and player control restored",not main.story.busy and not main._transition and not GameState.input_locked() and get_viewport().get_camera_3d()==main.rig.cam)
	var report:=FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"shots":shots,"standpoints":standpoints,"facts":ResidentVisits.state(),"first_route":first_route,"scope":"prior-market/day/position fixtures with free ground-level capsules; actual E, numeric choices, picture close, physical NPC route/seat, rendered photograph, nested doors and SQLite; not human fun or natural-duration evidence"},"  "))
	Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)
