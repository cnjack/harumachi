extends RefCounted
var t: Node
var main: Node
var G: Node
func _init(runner: Node) -> void:t=runner;main=runner.main;G=GameState
func check(label: String,ok: bool,detail: String="") -> void:t.check("MEAL_ROUTES",label,ok,detail)
func fixture() -> void:
	G.new_game();G.clock_paused=true;G.day=4;G.minute=12*60;G.quests.Q00={"state":"done","step":2};G.recipes_known.plain_onigiri=true
	DailyLife.event("tea").state="done";DailyLife.event("tea").drank=true;DailyLife.event("tea").completed_day=2
	main.world.set_region("town");main.in_room=false;G.player_in_room=false;main.player.frozen=false;main.ui.dialogue_end()
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0);main.player.global_position=Vector3(15.1,.05,16.65);G.state_changed.emit()
func run() -> void:
	var original: Dictionary=G.to_dict().duplicate(true);var instant: bool=main.ui.instant;main.ui.instant=true
	fixture()
	await t.use("life_tea",[0,4,0])
	var entry: Dictionary=NeighbourMeals.current();var rice: String=NeighbourMeals.rice_id(entry)
	check("the actual rice-role conversation prepares Haru's side and opens only the current meal recipe",entry.role=="rice" and entry.stage=="prepared" and entry.author=="haru" and G.recipe_known(rice) and entry.rice_made==0)
	var audit_issues: Array=PropAudit.run(main.world,Layout.WALLS)
	var table_issues: Array=audit_issues.filter(func(issue:Dictionary):return str(issue.get("a","")).contains("HaruMealTable") or str(issue.get("b","")).contains("HaruMealTable") or str(issue.get("a","")).contains("W13_cedar_worktable") or str(issue.get("b","")).contains("W13_cedar_worktable"))
	check("the active new meal table passes real town placement audit",table_issues.is_empty(),JSON.stringify(table_issues))
	check("choosing to cook grants no rice salt or finished rice balls",G.count("rice")==0 and G.count("salt")==0 and G.count(rice)==0 and G.craft(rice)!="")
	G.add_item("rice",2,true);G.add_item("salt",1,true)
	var multi_blocked: bool=G.craft(rice,2)!=""
	main.ui.instant=false;main.ui.panels.open_craft("kitchen");await t.frames(3)
	for button: Button in main.ui.modal_layer.find_children("*","Button",true,false):
		if button.get_meta("recipe_id","")==rice and not button.disabled:button.pressed.emit();break
	var correct_icon: bool=false
	for child: Node in main.ui.root.get_children():
		if child is Celebration:
			for icon: TextureRect in child.find_children("*","TextureRect",true,false):
				if icon.texture and icon.texture.get_image().get_data()==UITheme.icon_texture("onigiri").get_image().get_data():correct_icon=true
	check("dynamic rice cooking celebrates the real onigiri icon rather than a fallback fish",correct_icon)
	main.ui.close_modal(false);main.ui.instant=true
	check("the meal recipe is limited to one real batch of two",multi_blocked and G.count(rice)==2 and G.count("rice")==0 and G.count("salt")==0)
	check("successful cooking closes only this meal recipe and retains ordinary rice cooking",not G.recipes_db.has(rice) and G.recipe_known("plain_onigiri") and G.craft(rice)!="")
	check("one actual rice ball is protected for Haru",G.reserved_count(rice)==1 and G.unreserved_count(rice)==1 and G.reservation_note(rice).contains("春"))
	main.story.neighbours.view.sync_state()
	check("cooked rice is not falsely shown as already brought to the tea table",not entry.rice_brought and main.story.neighbours.view.dish.get_node_or_null("Rice_0")==null)
	G.store_in(rice,2)
	check("putting the meal in storage keeps receipt and blocks a fictional cup-side presentation",G.count(rice)==0 and entry.rice_made==2 and NeighbourMeals.present_rice(true)!="" and main.story.neighbours.view.dish.get_node_or_null("Rice_0")==null)
	G.take_out(rice,2)
	var before_load: Dictionary=NeighbourMeals.state().duplicate(true)
	G.save_game();G.flags.clear();G.load_game();entry=NeighbourMeals.current()
	check("SQLite keeps real cooking and the protected portion without reopening production",JSON.stringify(before_load)==JSON.stringify(NeighbourMeals.state()) and G.reserved_count(rice)==1 and not G.recipe_known(rice))
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0)
	await t.use("life_tea",[0])
	check("the real meal consumes one rice and side portion for each person",entry.rice_given==1 and entry.rice_eaten==1 and entry.npc_ate and entry.player_ate and entry.remaining==0 and G.count(rice)==0 and entry.rice_known_by_haru)
	check("Rice role cannot receive a second gift after completion",NeighbourMeals.take("pack",true)!="" and NeighbourMeals.give_rice(true)!="")
	fixture();await t.use("life_tea",[0,4,1]);entry=NeighbourMeals.current();rice=NeighbourMeals.rice_id(entry)
	G.add_item("rice",2,true);G.add_item("salt",1,true);G.craft(rice)
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0)
	await t.use("life_tea",[0,1])
	check("packing keeps the player's original rice and one side without copying either",entry.rice_given==1 and entry.rice_eaten==0 and G.count(rice)==1 and G.count(NeighbourMeals.gift_id(entry))==1 and G.reserved_count(rice)==0)
	DailyLife.eat_food(rice)
	check("later private rice eating does not claim Haru witnessed it",entry.rice_eaten==1 and not entry.rice_known_by_haru)
	fixture();G.recipes_known.erase("plain_onigiri");NeighbourMeals.invite(true)
	check("unlearned rice is not fabricated and the serving route stays available",NeighbourMeals.start("rice","thin",true)!="" and NeighbourMeals.start("serve","thin",true)=="")
	entry=NeighbourMeals.current();await main.story.neighbours.view.watch_prepare();NeighbourMeals.finish(true)
	check("serving preserves Haru's cooking and waits for real arrangement",entry.stage=="portioning" and not entry.arranged and entry.remaining==2)
	check("the valid initial arrangement can be retained without compulsory rework",main.story.neighbours.view.layout_reason()=="",main.story.neighbours.view.layout_reason())
	var arrangement:=MealArrangement.new();main.add_child(arrangement);await arrangement.run(main.story);arrangement.queue_free();main.ui.dialogue_end()
	check("the arrangement controller retains an actual layout and distinct authorship",entry.stage=="prepared" and entry.arranged and entry.author=="haru_cooked_player_portioned")
	NeighbourMeals.eat_haru(true);main.story.neighbours.view.sync_state()
	var player_bowl: Node3D=main.story.neighbours.view.dish.get_node_or_null("Bowl_1")
	check("Haru eating removes only her bowl and preserves the player's exact position",main.story.neighbours.view.dish.get_node_or_null("Bowl_0")==null and player_bowl!=null and absf(player_bowl.global_position.x-float(entry.bowls[1].x))<.001)
	fixture();NeighbourMeals.invite(true);NeighbourMeals.start("serve","chunk",true);entry=NeighbourMeals.current();await main.story.neighbours.view.watch_prepare();NeighbourMeals.finish(true)
	NeighbourMeals.move_bowl(1,main.story.neighbours.view.bowl_at(0))
	check("overlapping bowls are rejected without losing food",main.story.neighbours.view.layout_reason()!="" and NeighbourMeals.retain_layout(main.story.neighbours.view.layout_reason(),true)!="" and entry.remaining==2)
	NeighbourMeals.move_bowl(1,NeighbourMeals.TABLE_CENTER+Vector3(0,0,-.30))
	check("a bowl cannot cover the tea tray",main.story.neighbours.view.layout_reason()!="")
	NeighbourMeals.move_bowl(1,Vector3(17,0,16))
	check("outside a real supported surface is rejected",main.story.neighbours.view.layout_reason()!="")
	NeighbourMeals.move_bowl(1,NeighbourMeals.TABLE_CENTER+Vector3(.3,0,.1))
	var positions: Array=entry.bowls.duplicate(true);G.save_game();G.flags.clear();G.load_game();entry=NeighbourMeals.current()
	var positions_same: bool=true
	for index in 2:
		if absf(float(entry.bowls[index].x)-float(positions[index].x))>.00001 or absf(float(entry.bowls[index].z)-float(positions[index].z))>.00001:positions_same=false
	check("half-arranged individual bowl positions survive SQLite with unchanged quantities",entry.stage=="portioning" and positions_same and entry.remaining==2 and not entry.arranged)
	main.ui.instant=false
	var mouse_arrangement:=MealArrangement.new();main.add_child(mouse_arrangement);mouse_arrangement.run(main.story);await t.frames(4)
	var screen_rect: Rect2=main.get_viewport().get_visible_rect()
	var controls_rect: Rect2=mouse_arrangement.panel.get_global_rect()
	check("the complete arrangement title and controls fit inside the actual viewport",controls_rect.position.y>=0 and controls_rect.end.y<=screen_rect.end.y+.5,str(controls_rect)+" / "+str(screen_rect))
	mouse_arrangement.dragging=true
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=mouse_arrangement.panel.get_global_rect().get_center()
	mouse_arrangement._input(release)
	check("releasing a dragged bowl over the control panel always ends dragging",not mouse_arrangement.dragging)
	var unmoved: Array=entry.bowls.duplicate(true)
	mouse_arrangement.dragging=true
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(200,300);motion.button_mask=0;mouse_arrangement._input(motion)
	check("mouse motion after releasing cannot secretly move or save a bowl",not mouse_arrangement.dragging and entry.bowls==unmoved)
	mouse_arrangement.act("leave");await t.frames(3);mouse_arrangement.queue_free();main.ui.dialogue_end();main.ui.instant=true
	check("leaving the arrangement saves the same half-layout and clears its input lock",entry.stage=="portioning" and entry.bowls==unmoved and not G.input_locked() and main.ui.modal=="")
	fixture();await t.use("life_tea",[0,5,0,1]);entry=NeighbourMeals.state().sessions[0]
	check("the real serving choice can reach arrangement and packing in the same interaction",entry.arranged and entry.npc_ate and entry.player_received and G.count(NeighbourMeals.gift_id(entry))==1)
	check("the actual eating cut uses the arranged Haru bowl position instead of a generic table centre",main.story.neighbours.view.last_meal_surface.distance_to(Vector3(float(entry.bowls[0].x),main.story.neighbours.view.surface().y,float(entry.bowls[0].z)))<.001)
	check("the clean meal table remains available for later personal meals after receiving food",main.story.neighbours.view.table_model.visible and main.story.neighbours.view.table_model.get_meta("model_id","")=="W13_cedar_worktable")
	check("the outer serving interaction restores camera modal and input",main.ui.modal=="" and not G.input_locked() and main.get_viewport().get_camera_3d()==main.rig.cam)
	G.from_dict(original.duplicate(true));G.clock_paused=true;main.ui.instant=instant;main._restore()
