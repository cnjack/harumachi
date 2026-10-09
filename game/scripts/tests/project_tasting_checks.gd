extends RefCounted
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t=runner;main=runner.main

func fresh(menu: String="sandwich") -> Dictionary:
	GameState.new_game();GameState.clock_paused=true
	GameState.quests.Q01={"state":"done","step":2}
	SummerProjects.accept("host");SummerProjects.choose_plan(menu,"shop");SummerProjects.claim_kit();SummerProjects.shop_prepares()
	return SummerProjects.current_batch()

func usage(batch: Dictionary,who: String,presentation: String) -> Dictionary:
	return {"batch_id":int(batch.id),"menu":str(batch.menu),"presentation":presentation,"purpose":SummerProjects.tasting_purpose(who),"completed":true}

func run() -> void:
	var original: Dictionary=GameState.to_dict().duplicate(true)
	material_checks()
	for menu: String in ["sandwich","focaccia"]:
		for presentation: String in ["paper","plate"]:
			var batch: Dictionary=fresh(menu)
			var evidence: Dictionary=usage(batch,"mio",presentation)
			SummerProjects.taste("mio",true,evidence)
			t.check("TASTING_USE","%s/%s commits one actual sample and its purpose"%[menu,presentation],GameState.count(str(batch.iid))==2 and batch.get("usage_feedback",[]).size()==1 and str(batch.usage_feedback[0].menu)==menu and str(batch.usage_feedback[0].presentation)==presentation and str(batch.usage_feedback[0].purpose)==SummerProjects.tasting_purpose("mio"))
			SummerProjects.taste("mio",true,evidence)
			t.check("TASTING_USE","repeated %s/%s cannot duplicate feedback or consume another sample"%[menu,presentation],GameState.count(str(batch.iid))==2 and batch.usage_feedback.size()==1)
	var batch: Dictionary=fresh()
	var bad: Dictionary=usage(batch,"mio","paper");bad.completed=false
	t.check("TASTING_USE","unfinished presentation preserves all three samples and the first opinion",SummerProjects.taste("mio",true,bad)!="" and GameState.count(str(batch.iid))==3 and batch.tasters.is_empty())
	bad=usage(batch,"mio","paper");bad.batch_id=99
	t.check("TASTING_USE","a scene from another batch cannot consume the current batch",SummerProjects.taste("mio",true,bad)!="" and GameState.count(str(batch.iid))==3)
	bad=usage(batch,"mio","paper");bad.menu="focaccia"
	t.check("TASTING_USE","the displayed menu must match the batch",SummerProjects.taste("mio",true,bad)!="" and batch.tasters.is_empty())
	bad=usage(batch,"mio","paper");bad.purpose=SummerProjects.tasting_purpose("haru")
	t.check("TASTING_USE","one person's purpose cannot be attributed to another",SummerProjects.taste("mio",true,bad)!="" and batch.tasters.is_empty())
	t.check("TASTING_USE","a vanished taster cannot complete a finished table cut",SummerProjects.taste("mio",false,usage(batch,"mio","plate"))!="" and GameState.count(str(batch.iid))==3)
	var receipt: Dictionary=usage(batch,"haru","paper");receipt.mode="received";receipt.reference_who="mio"
	t.check("TASTING_RECEIPT","a second opinion cannot invent a first witnessed tasting",SummerProjects.taste("haru",true,receipt)!="" and GameState.count(str(batch.iid))==3)
	SummerProjects.taste("mio",true,usage(batch,"mio","paper"))
	GameState.save_game();GameState.load_game();batch=SummerProjects.current_batch()
	t.check("TASTING_SAVE","SQLite retains exactly the first menu, presentation and everyday purpose",batch.usage_feedback.size()==1 and batch.usage_feedback[0].presentation=="paper" and batch.usage_feedback[0].purpose==SummerProjects.tasting_purpose("mio") and GameState.count(str(batch.iid))==2)
	receipt=usage(batch,"haru","paper");receipt.mode="received";receipt.reference_who="mio"
	SummerProjects.taste("haru",true,receipt)
	t.check("TASTING_RECEIPT","a nearby second recipient adds a distinct use without fabricating another table tasting",batch.received_feedback.size()==1 and batch.usage_feedback.size()==1 and str(batch.received_feedback[0].reference_who)=="mio" and GameState.count(str(batch.iid))==1)
	DailyLife.eat_food(str(batch.iid))
	t.check("TASTING_USE","two distinct purposes leave the third portion honestly available for self eating",batch.usage_feedback.size()+batch.received_feedback.size()==2 and SummerProjects.phase()=="decision" and int(batch.self_eaten)==1 and GameState.count(str(batch.iid))==0)
	t.check("TASTING_USE","the good first menu needs no compulsory remake after useful feedback",SummerProjects.confirm_plan("bite","paper")=="" and SummerProjects.opening().batches.size()==1)
	t.check("TASTING_NOTES","paper notes retain the menu, serving and both concrete uses",SummerProjects.notes().contains(SummerProjects.tasting_purpose("mio")) and SummerProjects.notes().contains(SummerProjects.tasting_purpose("haru")) and SummerProjects.notes().contains("纸托"))
	batch=fresh();SummerProjects.taste("mio",true);batch.erase("usage_feedback")
	var legacy: Dictionary=GameState.to_dict().duplicate(true);GameState.from_dict(legacy)
	t.check("TASTING_LEGACY","old opinions retain their taster without inventing a witnessed table use",SummerProjects.current_batch().tasters.has("mio") and SummerProjects.current_batch().usage_feedback.is_empty())
	batch=fresh()
	var old_database: String=SaveDB.database_path;var old_backup: String=SaveDB.backup_path
	var blocked: String=SaveDB.directory.path_join("blocked-tasting.db")
	DirAccess.make_dir_recursive_absolute(blocked)
	SaveDB.database_path=blocked;SaveDB.backup_path=SaveDB.directory.path_join("missing-tasting-backup.db")
	var failed_save: String=SummerProjects.taste("mio",true,usage(batch,"mio","plate"))
	SaveDB.database_path=old_database;SaveDB.backup_path=old_backup;DirAccess.remove_absolute(blocked)
	t.check("TASTING_SAVE","failed SQLite commit reports failure and restores the exact undecided sample",failed_save!="" and not GameState.last_error.is_empty() and GameState.count(str(batch.iid))==3 and batch.tasters.is_empty() and batch.usage_feedback.is_empty() and SummerProjects.phase()=="feedback")
	var retried: String=SummerProjects.taste("mio",true,usage(batch,"mio","plate"))
	t.check("TASTING_SAVE","retry after storage recovers commits once without duplicate portions",retried=="" and GameState.count(str(batch.iid))==2 and batch.usage_feedback.size()==1)
	var empty:=Node3D.new();main.add_child(empty);empty.position.y=.7
	t.check("TASTING_SUPPORT","an empty raised node has no supporting triangles",not is_finite(WorldBuilder.rendered_support_height(empty,empty.global_position,INF,true)) and not ProjectTasting.patch_supported(empty,empty.global_position))
	empty.queue_free()
	if main.in_room:
		if main.room_kind=="house":await main.exit_room()
		else:await main.exit_interior()
	batch=fresh();await t.frames(3)
	var view:=ProjectTasting.new();main.add_child(view);view.s=main.story
	t.check("TASTING_SUPPORT","the existing P09 has a complete sample patch clear of its basket",view.find_surface("mio") and ProjectTasting.patch_supported(view.support,view.surface))
	var edge: Vector3=view.surface+Vector3(0,0,.4)
	t.check("TASTING_SUPPORT","a paper corner or plate edge beyond the actual counter fails",not ProjectTasting.patch_supported(view.support,edge))
	for style: String in ["paper","plate"]:
		var cut:=LivingAction.new();main.add_child(cut);cut.surface_at=view.surface;cut.meal_presentation=style;cut.setup(main.player,"eat",str(batch.iid))
		t.check("TASTING_MESH","%s uses a solid serving base and a real food mesh without a hand pose"%style,cut.meal_food!=null and cut.pose==null and cut.hand==-1 and (cut.prop.get_node_or_null("PaperBase")!=null if style=="paper" else cut.prop.get_node_or_null("Plate")!=null))
		cut.clock=cut.duration*.7;cut._process(0)
		t.check("TASTING_MESH","%s retains its empty serving base when only this portion disappears"%style,not cut.meal_food.visible and cut.prop.visible and GameState.count(str(batch.iid))==3)
		cut.queue_free()
	view.queue_free();await t.frames(2)
	await movement_checks()
	GameState.from_dict(original);GameState.clock_paused=true

func movement_checks() -> void:
	var batch: Dictionary=fresh()
	var actor: NPC=main.npcs.mio
	actor.home=false;actor.visible=true;actor.place(Vector3(3.6,0,13.5),0)
	main.player.global_position=Vector3(4.6,.05,12.5)
	main.story.busy=true;main.player.frozen=true;main.ui.dialogue_begin()
	var instant: bool=main.ui.instant;main.ui.instant=false
	var view:=ProjectTasting.new();main.add_child(view)
	var shown: Dictionary=await view.run(main.story,"mio","paper")
	t.check("TASTING_WALK","a frozen dialogue really walks both characters by collision to distinct stops",not shown.has("error") and view.player_trace.size()>5 and view.npc_trace.size()>5 and main.player.global_position.distance_to(Vector3(4.6,.05,12.5))>.5 and actor.global_position.distance_to(main.player.global_position)>.65,str(shown))
	t.check("TASTING_WALK","completed presentation restores the dialogue freeze, movement and camera without yet consuming",main.player.frozen and main.player.auto_move==Vector3.ZERO and get_camera()==main.rig.cam and GameState.count(str(batch.iid))==3 and not GameState._ui_locks.has("project_tasting"))
	view.queue_free();await t.frames(2)
	# Cancel after real movement begins; neither teleport back nor consume a sample.
	actor.place(Vector3(3.6,0,13.5),0);main.player.global_position=Vector3(4.6,.05,12.5)
	var cancelled:=ProjectTasting.new();main.add_child(cancelled)
	cancelled.run(main.story,"mio","plate")
	await t.frames(8)
	cancelled.aborted=true;actor.cancel_safe_walk()
	while cancelled.active:await t.frames(1)
	t.check("TASTING_CANCEL","a mid-walk cancellation keeps food and opinions and releases the owned lock",GameState.count(str(batch.iid))==3 and batch.tasters.is_empty() and main.player.frozen and main.player.auto_move==Vector3.ZERO and not GameState._ui_locks.has("project_tasting") and not actor._moving)
	cancelled.queue_free();main.ui.instant=instant;main.ui.dialogue_end();main.player.frozen=false;main.story.busy=false
	await interruption_checks()

func interruption_checks() -> void:
	var batch: Dictionary=fresh()
	var actor: NPC=main.npcs.mio
	main.story.busy=true;main.player.frozen=true;main.ui.dialogue_begin()
	var instant: bool=main.ui.instant;main.ui.instant=false
	for phase: String in ["eat","empty"]:
		actor.home=false;actor.visible=true;actor.place(Vector3(1.1,0,14.1),0)
		main.player.global_position=Vector3(2.7,.05,14.1)
		var view:=ProjectTasting.new();main.add_child(view);view.run(main.story,"mio","paper")
		var deadline: int=Time.get_ticks_msec()+6000
		while view.active and view.stage!=phase and Time.get_ticks_msec()<deadline:await t.frames(1)
		var reached: bool=view.stage==phase
		var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.physical_keycode=KEY_ESCAPE;event.pressed=true;Input.parse_input_event(event)
		await t.frames(2);event.pressed=false;Input.parse_input_event(event)
		while view.active:await t.frames(1)
		t.check("TASTING_CANCEL","Esc during %s preserves the sample and restores the camera and freeze"%phase,reached and view.aborted and batch.tasters.is_empty() and GameState.count(str(batch.iid))==3 and main.player.frozen and main.player.auto_move==Vector3.ZERO and get_camera()==main.rig.cam)
		view.queue_free();await t.frames(2)
	actor.place(Vector3(1.1,0,14.1),0);main.player.global_position=Vector3(2.7,.05,14.1)
	var occupied:=ProjectTasting.new();main.add_child(occupied);occupied.run(main.story,"mio","plate")
	while occupied.active and occupied.stage!="eat":await t.frames(1)
	var obstacle:=MeshInstance3D.new();obstacle.name="NewTastingObstacle"
	var box:=BoxMesh.new();box.size=Vector3(.14,.12,.14);obstacle.mesh=box;obstacle.material_override=LivingAction.matte(Color.RED)
	main.add_child(obstacle);obstacle.global_position=occupied.surface+Vector3.UP*.06
	while occupied.active:await t.frames(1)
	t.check("TASTING_SUPPORT","new geometry occupying the portion stops the scene before a use can be committed",occupied.aborted and batch.tasters.is_empty() and GameState.count(str(batch.iid))==3 and get_camera()==main.rig.cam)
	obstacle.queue_free();occupied.queue_free();await t.frames(2)
	# A distinct test actor can be removed without destroying the game's actual neighbour.
	var removed:=NPC.new();main.add_child(removed);removed.setup("mio",Layout.NPC.mio);removed.player=main.player
	removed.home=false;removed.visible=true;removed.place(Vector3(7,0,12),0)
	main.npcs.mio=removed;main.story.npcs.mio=removed
	main.player.global_position=Vector3(5.5,.05,12)
	var absent:=ProjectTasting.new();main.add_child(absent);absent.run(main.story,"mio","plate")
	var removal_started: bool=absent.active and absent.stage=="walk"
	await t.frames(3);main.npcs.mio=actor;main.story.npcs.mio=actor;removed.queue_free();await t.frames(2)
	while absent.active:await t.frames(1)
	t.check("TASTING_CANCEL","a freed actor during the noninstant walking camera safely cancels without consuming",removal_started and absent.aborted and not absent.active and batch.tasters.is_empty() and GameState.count(str(batch.iid))==3 and main.player.frozen and get_camera()==main.rig.cam,"started=%s aborted=%s active=%s frozen=%s camera=%s"%[removal_started,absent.aborted,absent.active,main.player.frozen,get_camera()==main.rig.cam])
	main.npcs.mio=actor;main.story.npcs.mio=actor;absent.queue_free()
	main.ui.instant=instant;main.ui.dialogue_end();main.player.frozen=false;main.story.busy=false

func get_camera() -> Camera3D:
	return main.get_viewport().get_camera_3d()

func material_checks() -> void:
	var root:=Node3D.new();main.add_child(root)
	var matte_mesh:=MeshInstance3D.new();matte_mesh.mesh=BoxMesh.new();matte_mesh.material_override=LivingAction.matte(Color.WHITE);root.add_child(matte_mesh)
	var original_matte: Material=matte_mesh.material_override
	HouseBuilder.toonify(root)
	t.check("TASTING_MATERIAL","already matte food keeps one geometry override without a second surface reference",matte_mesh.material_override==original_matte and matte_mesh.get_surface_override_material(0)==null)
	var source:=StandardMaterial3D.new();source.metallic=.8
	var overridden:=MeshInstance3D.new();overridden.mesh=BoxMesh.new();overridden.material_override=source;root.add_child(overridden)
	HouseBuilder.toonify(root)
	t.check("TASTING_MATERIAL","whole-mesh conversion clones only the winning override and preserves shared input",overridden.material_override!=source and overridden.get_surface_override_material(0)==null and is_equal_approx(source.metallic,.8) and (overridden.material_override as StandardMaterial3D).metallic==0)
	var surface_mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.material=source;surface_mesh.mesh=box;root.add_child(surface_mesh)
	HouseBuilder.toonify(root)
	t.check("TASTING_MATERIAL","an imported surface still receives an isolated toon material without geometry override",surface_mesh.material_override==null and surface_mesh.get_surface_override_material(0)!=source and (surface_mesh.get_surface_override_material(0) as StandardMaterial3D).diffuse_mode==BaseMaterial3D.DIFFUSE_TOON and is_equal_approx(source.metallic,.8))
	var bridge: Node3D=main.world.farm.get_node_or_null("P_bridge")
	var dual:=false;var aged:=false
	if bridge!=null:
		for part: MeshInstance3D in WorldBuilder.find_meshes(bridge):
			for index: int in part.mesh.get_surface_count():
				var override: Material=part.get_surface_override_material(index)
				if override is ShaderMaterial and (override as ShaderMaterial).shader==LakesideMaterials.WOOD_SHADER:
					aged=true
					if part.material_override!=null:dual=true
	t.check("TASTING_MATERIAL","the real aged bridge preserves surface shading without a second whole-mesh override",aged and not dual)
	root.queue_free()
