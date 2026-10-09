extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("LAYOUT_VALIDITY",label,ok,detail)
func run() -> void:
	var saved: Dictionary=GameState.to_dict().duplicate(true)
	GameState.new_game();GameState.clock_paused=true
	GameState.add_item("picnic_table",1,true);GameState.add_item("bench",1,true)
	GameState.add_placement("picnic_table",-3,10,0);GameState.add_placement("bench",-3,14,0)
	await t.frames(3)
	var p: Dictionary=SummerProjects.opening();p.phase="site";p.final={"menu":"sandwich","portion":"bite","presentation":"paper","trial_batch":1}
	var trial_actor: NPC=main.npcs.mio;trial_actor.set_home(false);trial_actor.place(Vector3(-3,0,1),0)
	main.player.global_position=Vector3(-10,.05,-4);await t.frames(3)
	var actual_path: Array[Vector3]=trial_actor.MOTION_ROUTE.query(trial_actor,trial_actor.global_position,Vector3(2,0,13))
	var route: Dictionary={"ok":not actual_path.is_empty(),"revision":SummerProjects.layout_fingerprint(),"path":actual_path}
	check("fixture uses a real clear cooperation route",route.ok and LayoutValidity.path_clear(actual_path),str(actual_path))
	var accepted: String=SummerProjects.record_layout(route,"mio",true)
	check("actual trial initially remains usable",accepted=="" and SummerProjects.ready(),accepted)
	if not route.ok or accepted!="":GameState.from_dict(saved);main._restore();return
	var empty_trial: Dictionary=route.duplicate(true);empty_trial.path=[]
	check("a new empty route cannot replace actual cooperation travel",SummerProjects.record_layout(empty_trial,"mio",true)!="")
	var short_trial: Dictionary=route.duplicate(true);short_trial.path=[actual_path[0]]
	check("a half-route cannot become a reached serving point",SummerProjects.record_layout(short_trial,"mio",true)!="")
	GameState.add_item("flower_pot",1,true)
	var remote: int=GameState.add_placement("flower_pot",8,4,0)
	await t.frames(3)
	check("a remote flower pot does not cancel the actual cooperation trial",SummerProjects.ready())
	GameState.placements.reverse();main.placement.rebuild();await t.frames(3)
	check("array order cannot invalidate identical furniture and travel",SummerProjects.ready())
	GameState.remove_placement(remote);GameState.placements.reverse();main.placement.rebuild();await t.frames(3)
	var obstruction:=StaticBody3D.new();obstruction.collision_layer=WorldBuilder.L_SOLID
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.7,1.8,.7);collider.shape=shape;collider.position.y=.9;obstruction.add_child(collider)
	main.add_child(obstruction);obstruction.global_position=LayoutValidity.point(route.path[route.path.size()/2])
	await t.frames(3)
	check("a new static obstruction on the saved route blocks reuse without changing participation",not SummerProjects.ready() and str(p.layout_trial.who)=="mio")
	obstruction.queue_free();await t.frames(3)
	check("removing that obstruction restores applicability without another arrival",SummerProjects.ready())
	GameState.new_game();GameState.clock_paused=true;GameState.quests.Q11={"state":"done","step":3}
	SummerSpace.start("light","loan");main.story.space.apply_scheme("west");await t.frames(3)
	var records: Dictionary={}
	for who: String in ["mio","haru","ren"]:
		var actor: NPC=main.npcs[who];actor.set_home(false)
		var finish: Vector3=SummerSpace.DEMO if who=="mio" else SummerSpace.stop_for("bench" if who=="haru" else "picnic_table")
		var start: Vector3=SummerSpace.ENTRY if who=="mio" else (SummerSpace.HARU_START if who=="haru" else SummerSpace.FOOD_START)
		actor.place(start,0);await t.frames(2)
		var path: Array[Vector3]=actor.MOTION_ROUTE.query(actor,start,finish)
		actor.place(finish,0)
		var result: Dictionary={"revision":SummerSpace.revision(),"present":true,"arrived":true,"visible_demo":true,"crossed_dance":false,"position":LayoutValidity.position(finish),"path":[],"day":GameState.day}
		for point: Vector3 in path:result.path.append(LayoutValidity.position(point))
		if who=="haru":result["sight"]={"from":LayoutValidity.position(main.story.space.view.eye(actor)),"to":LayoutValidity.position(main.story.space.view.eye(main.npcs.mio))}
		SummerSpace.invite(who,true);records[who]=result
		check(who+" has a real complete clear route",not path.is_empty() and LayoutValidity.path_clear(path))
		check(who+" records current use",SummerSpace.record(who,result)=="")
	check("all three needs can be retained",SummerSpace.retain()=="" and SummerSpace.ready())
	var no_travel: Dictionary=records.ren.duplicate(true);no_travel.path=[]
	check("a new missing path cannot become a current serving record",SummerSpace.record("ren",no_travel)!="")
	no_travel.path=[LayoutValidity.position(SummerSpace.FOOD_START)]
	check("a claimed arrival does not promote an unfinished serving path",SummerSpace.record("ren",no_travel)!="")
	var no_sight: Dictionary=records.haru.duplicate(true);no_sight.erase("sight")
	check("Haru cannot acquire a scoped viewing record without measured eyes",SummerSpace.record("haru",no_sight)!="")
	no_sight["sight"]={"from":{"x":1},"to":{"z":2}}
	check("incomplete coordinates cannot stand in for an actual viewing ray",SummerSpace.record("haru",no_sight)!="")
	var original_mio: Dictionary=SummerSpace.state().trials.mio.duplicate(true)
	var legacy_mio: Dictionary=original_mio.duplicate(true);legacy_mio.erase("scope_version");legacy_mio.erase("dependency")
	legacy_mio.revision=JSON.stringify([GameState.placements,SummerSpace.state().style,int(SummerSpace.state().bench_uid),int(SummerSpace.state().table_uid),SummerSpace.FUTURE_RECTS.size(),SummerSpace.DANCE_RADIUS]).sha256_text()
	SummerSpace.state().trials.mio=legacy_mio
	var legacy_blocker:=StaticBody3D.new();legacy_blocker.collision_layer=WorldBuilder.L_SOLID
	var legacy_collider:=CollisionShape3D.new();var legacy_shape:=BoxShape3D.new();legacy_shape.size=Vector3(.7,1.8,.7);legacy_collider.shape=legacy_shape;legacy_collider.position.y=.9;legacy_blocker.add_child(legacy_collider)
	main.add_child(legacy_blocker);legacy_blocker.global_position=LayoutValidity.point(legacy_mio.path[legacy_mio.path.size()/2])
	await t.frames(3)
	check("legacy hashes still check saved paths against new fixed obstacles",not SummerSpace.trial_current("mio") and not SummerSpace.state().trials.mio.has("scope_version"))
	legacy_blocker.queue_free();await t.frames(3);SummerSpace.state().trials.mio=original_mio
	GameState.add_item("flower_pot",1,true)
	var outside: int=GameState.add_placement("flower_pot",8,4,0);await t.frames(3)
	check("remote decoration preserves all three actual witnesses",SummerSpace.ready())
	var vision_obstruction:=StaticBody3D.new();vision_obstruction.collision_layer=WorldBuilder.L_SOLID
	var vision_collider:=CollisionShape3D.new();var vision_shape:=BoxShape3D.new();vision_shape.size=Vector3(.22,.22,.22);vision_collider.shape=vision_shape;vision_obstruction.add_child(vision_collider)
	main.add_child(vision_obstruction);vision_obstruction.global_position=LayoutValidity.point(records.haru.sight.from).lerp(LayoutValidity.point(records.haru.sight.to),.1)
	await t.frames(3)
	check("blocking the observed sightline requires Haru without erasing Mio or Ren",not LayoutValidity.sight_clear(records.haru.sight) and not SummerSpace.trial_current("haru") and SummerSpace.trial_current("mio") and SummerSpace.trial_current("ren"),"mio=%s haru=%s ren=%s sight=%s"%[SummerSpace.trial_current("mio"),SummerSpace.trial_current("haru"),SummerSpace.trial_current("ren"),records.haru.sight])
	vision_obstruction.queue_free();await t.frames(3)
	check("clearing the sightline restores the same observation",SummerSpace.ready())
	SummerSpace.set_style("plate")
	check("changing serving format preserves entry and viewing but requires the serving check",SummerSpace.trial_current("mio") and SummerSpace.trial_current("haru") and not SummerSpace.trial_current("ren"))
	SummerSpace.set_style("paper");SummerSpace.retain()
	var old_table: Dictionary=SummerSpace.furniture("picnic_table").duplicate(true)
	GameState.remove_placement(int(old_table.uid));var replacement: int=GameState.add_placement("picnic_table",float(old_table.x),float(old_table.z)+.5,int(old_table.rot))
	SummerSpace.state().table_uid=replacement;await t.frames(3)
	check("moving only the paper-serving table keeps Mio and Haru but requires Ren",SummerSpace.trial_current("mio") and SummerSpace.trial_current("haru") and not SummerSpace.trial_current("ren"))
	check("old witnesses retain their original participation data",SummerSpace.state().trials.mio.position==records.mio.position and SummerSpace.state().trials.haru.position==records.haru.position)
	GameState.remove_placement(outside)
	GameState.from_dict(saved);main._restore();main.placement.rebuild();GameState.clock_paused=true
