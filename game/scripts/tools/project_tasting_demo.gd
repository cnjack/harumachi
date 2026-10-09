extends "res://scripts/tools/daily_life_demo.gd"
## Explicit material/date/standing fixtures. E/choices and subsequent collision walking are real.
func _ready() -> void:
	main=get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):folder=arg.substr(11)
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	NPC.roam_enabled=false;Progress.quiet=true;main.ui.instant=false;main.ui.auto=false
	if main.in_room:await main.exit_room()
	var facts: Array=[]
	for menu: String in ["sandwich","focaccia"]:
		for style: String in ["paper","plate"]:
			setup_batch(menu)
			var batch: Dictionary=SummerProjects.current_batch()
			var label: String=menu+"_"+style
			main.npcs.mio.place(Vector3(3.6,0,12.5),0);main.npcs.mio.home=false;main.npcs.mio.visible=true
			seen_actions.clear()
			await use_point("mio",[0,0 if style=="paper" else 1])
			check(label+" first taste uses the chosen solid serving and commits one sample",batch.usage_feedback.size()==1 and str(batch.usage_feedback[0].presentation)==style and GameState.count(str(batch.iid))==2 and seen_actions.has("eat") and seen_actions.has("eat_empty"))
			for stage_label: String in ["action_eat","action_eat_after"]:
				DirAccess.copy_absolute(folder.path_join(stage_label+".png"),folder.path_join(label+"_"+stage_label+".png"))
			await shot(label+"_feedback")
			main.npcs.haru.place(Vector3(4.8,0,12.5),0);main.npcs.haru.home=false;main.npcs.haru.visible=true
			var haru_start: Vector3=main.npcs.haru.global_position
			seen_actions.clear();await use_point("haru",[0])
			check(label+" second opinion receives exactly one sample without another forced table walk",batch.received_feedback.size()==1 and batch.usage_feedback.size()==1 and GameState.count(str(batch.iid))==1 and SummerProjects.phase()=="decision" and seen_actions.is_empty() and main.npcs.haru.global_position.distance_to(haru_start)<.2)
			check(label+" good first plan remains without another bake",SummerProjects.confirm_plan("bite",style)=="" and SummerProjects.opening().batches.size()==1)
			facts.append(batch.duplicate(true));await shot(label+"_second_use")
	check("all dialogue cameras and controls return",not main.story.busy and not GameState.input_locked() and main.player.auto_move==Vector3.ZERO and get_viewport().get_camera_3d()==main.rig.cam)
	var file:=FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"facts":facts,"shots":shots,"input":"E and numeric choices; collision-driven authored travel","scope":"material/date/initial standing fixtures; technical presentation, not ordinary player fun or natural duration"},"  "))
	Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)

func setup_batch(menu: String) -> void:
	GameState.new_game();GameState.clock_paused=true
	GameState.quests.Q00={"state":"done","step":2};GameState.quests.Q01={"state":"done","step":2}
	GameState.flags.met_mio=true;GameState.flags.met_haru=true
	GameState.flags.dlg_deferred={}
	for entry: Dictionary in Dialogue.entries:
		if entry.get("event",false):GameState.flags.dlg_deferred[str(entry.id)]=GameState.day
	SummerProjects.accept("host");SummerProjects.choose_plan(menu,"shop");SummerProjects.claim_kit();SummerProjects.shop_prepares()
