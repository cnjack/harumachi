extends RefCounted
var t: Node
var main: Node
var G: Node
func _init(runner: Node) -> void: t=runner;main=runner.main;G=GameState
func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	G.new_game()
	G.clock_paused = true
	G.quests.Q05 = {"state":"done","step":5}
	DailyLife.track("meal")
	main.story.lore.checks()
	t.check("SUMMER_FLOW","the first market can lead to the personal box without an empty overnight wait",G.qstate("Q10")=="available" and G.day==1 and DailyLife.state().tracked=="meal")
	G.new_game()
	G.clock_paused = true
	G.day=17
	G.minute=17*60
	G.quests.Q14={"state":"active","step":1}
	main.world.set_region("town")
	main.world.sync_festivals()
	main.in_room=false
	main.ui.auto_choices=[0]
	await main.story.fest.handle("yagura")
	t.check("SUMMER_FLOW","an explicit stage-side rest advances to the real dance instead of forcing two empty hours",int(G.minute)==20*60 and G.flags.get("fest_bon_odori",false))
	G.new_game();G.clock_paused=true
	t.check("SUMMER_FLOW","an unplayed ending cannot invent a future note",not MainlineProgress.choose_direction(0,"hanabi") and MainlineProgress.direction().is_empty())
	G.quests.Q15={"state":"done","step":2}
	t.check("SUMMER_FLOW","old completed summers do not receive a backfilled personal intention",MainlineProgress.direction().is_empty() and not main.world.house.future_note.visible)
	var coins: int=G.coins
	t.check("SUMMER_FLOW","all four future intentions are equal choices without a reward or season unlock",MainlineProgress.choose_direction(3,"home") and int(MainlineProgress.direction().choice)==3 and G.coins==coins and not G.flags.get("spring_open",false))
	var note: Node3D=main.world.house.future_note
	var desk: Node3D=main.world.house.get_node("I02_desk")
	var support: float=WorldBuilder.rendered_support_height(desk,note.global_position,1.2)
	t.check("SUMMER_FLOW","the chosen intention appears as a real supported note on the home desk",note.visible and support>.4 and absf(note.global_position.y-support-.012)<.003)
	G.save_game();var intention: Dictionary=MainlineProgress.direction().duplicate(true);G.flags.clear();G.load_game()
	t.check("SUMMER_FLOW","SQLite retains the personal intention and actual note",MainlineProgress.direction()==intention and main.world.house.future_note.visible)
	main.world.set_region("farm");main.in_room=false
	main.player.global_position=FarmBuilder.ORIGIN+Vector3(9.6,.05,10)
	var standing: Vector3=main.player.global_position
	await main.hanabi_scene("mio")
	t.check("SUMMER_FLOW","fireworks return the player to the reachable standing position instead of inside the bench",main.player.global_position.distance_to(standing)<.05 and not G.input_locked())
	main.world.set_region("town")
	G.new_game();G.clock_paused=true;G.quests.Q11={"state":"done","step":3}
	main.placement.rebuild();await t.frames(3)
	WorkshopProject.start("plan","meeting","leaf")
	var view: WorkroomView=main.world.interiors.workroom.get_node("WorkroomProject")
	var work_id: String=WorkshopProject.state().work_id
	WorkshopProject.configure(1.55,0,"path");await t.frames(3)
	var low_path: Dictionary=view.trial()
	t.check("LANTERN_CHOICE","the original low aisle position still physically blocks the fixed main path",not low_path.clear)
	WorkshopProject.configure(1.55,0,"side");await t.frames(3)
	var low_side: Dictionary=view.trial();WorkshopProject.record_trial(low_side)
	t.check("LANTERN_CHOICE","a low side hanging is safe and useful for near lettering despite the distant paper obstruction",low_side.clear and low_side.near_text_visible and not low_side.far_marker_visible and WorkshopProject.retain()=="",JSON.stringify(low_side))
	WorkshopProject.configure(2.4,0,"path");await t.frames(3)
	var high: Dictionary=view.trial();WorkshopProject.record_trial(high)
	t.check("LANTERN_CHOICE","a high aisle hanging is safe and visible on approach while the low side letters subtend a larger near angle",high.clear and high.far_marker_visible and float(low_side.near_letter_angle)>float(high.near_letter_angle) and WorkshopProject.retain()=="",JSON.stringify(high))
	WorkshopProject.configure(1.55,180,"side");await t.frames(3)
	var reverse: Dictionary=view.trial();WorkshopProject.record_trial(reverse)
	t.check("LANTERN_CHOICE","turning a low side paper away loses its usable observation without forcing new materials",not reverse.readable and WorkshopProject.retain()!="" and WorkshopProject.state().work_id==work_id and G.count("washi")==0)
	WorkshopProject.configure(1.55,0,"side");await t.frames(3);WorkshopProject.record_trial(view.trial());WorkshopProject.retain()
	G.day=17;G.minute=19*60;main.world.sync_festivals();WorkshopProject.begin_site();await t.frames(3)
	var used: Dictionary=view.trial(true)
	t.check("LANTERN_CHOICE","the same low side work can be used outdoors without becoming a high-only answer",WorkshopProject.install(used)=="" and WorkshopProject.state().installed.work_id==work_id,JSON.stringify(used))
	WorkshopProject.configure(2.4,0,"path")
	t.check("LANTERN_CHOICE","changing the hanging invalidates current installation while preserving past use and the work",WorkshopProject.state().installed.is_empty() and WorkshopProject.state().use_history.size()==1 and WorkshopProject.state().work_id==work_id)
	WorkshopProject.stow()
	WorkshopProject.restore_to_rack();await t.frames(3)
	t.check("LANTERN_CHOICE","a stored work returns to the trial rack with the same parameters and no repeated material cost",not WorkshopProject.state().stored and is_instance_valid(view.trial_lantern) and WorkshopProject.state().work_id==work_id and G.count("washi")==0)
	WorkshopProject.configure(2.4,0,"path");await t.frames(3);WorkshopProject.record_trial(view.trial());WorkshopProject.retain()
	WorkshopProject.begin_site();WorkshopProject.configure(2.4,180,"path");await t.frames(3)
	var reversed_high: Dictionary=view.trial(true)
	t.check("LANTERN_CHOICE","a reversed high lamp stays visible even when its paper face is away",reversed_high.far_marker_visible and not reversed_high.far_paper_visible)
	WorkshopProject.configure(2.4,0,"side");await t.frames(3)
	var high_side: Dictionary=view.trial(true)
	t.check("LANTERN_CHOICE","a useful high side combination is not rejected to force only two answers",high_side.clear and high_side.readable)
	G.new_game();G.clock_paused=true;G.quests.Q00={"state":"done","step":2}
	await main.enter_room()
	main.player.global_position=HouseBuilder.ORIGIN+Vector3(-4.6,.05,-.6)
	await t.frames(3)
	var driver: Node=load("res://scripts/tools/autoplay.gd").new();driver.main=main
	var route:=SummerAutoplay.new(driver)
	var path: Array[Vector3]=route.path_to(HouseBuilder.ORIGIN+Vector3(5,.05,3.1))
	var walked: bool=await route.walk(path) if not path.is_empty() else false
	t.check("SUMMER_FLOW","the strict driver walks from the real wake position around low living-room furniture",walked and main.player.global_position.distance_to(HouseBuilder.ORIGIN+Vector3(5,.05,3.1))<.3)
	driver.free()
	await main.exit_room()
	G.from_dict(original.duplicate(true))
	G.clock_paused=true
	main.placement.rebuild()
	main._restore()
