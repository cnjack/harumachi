extends RefCounted
var t: Node
var G: Node
var m: Node
func _init(test: Node) -> void:t=test;G=test.G;m=test.main
func check(title: String,ok: bool,detail: String="") -> void:t.check("RESIDENT_VISITS",title,ok,detail)
func fresh() -> void:
	G.new_game();G.clock_paused=true;G._ui_locks.clear();G.phase="prep";G.day=5;G.minute=18*60
	G.flags.erase("arrival_home");G.quests.Q00={"state":"done","step":2};G.quests.Q05={"state":"done","step":5}
	m.in_room=false;m.room_kind="";m.world.set_region("town");m.world.set_indoor_look(false);m.ui.instant=true
	m.player.global_position=ResidentVisits.TRIAL_POINT;m.story.cutscene=false;m.story.busy=false
	m.placement.rebuild();m.update_npcs(true);ResidentVisits.invite_after_market()

func run() -> void:
	var saved: Dictionary=G.to_dict().duplicate(true)
	await _rooms()
	await _appointments()
	await _two_routes()
	await _followups()
	await _settled_revisits()
	G.from_dict(saved);m._restore()

func _rooms() -> void:
	fresh()
	check("the first shared market invites three real households without buying friendship",ResidentVisits.unlocked("home_haru") and ResidentVisits.unlocked("home_ren") and ResidentVisits.unlocked("home_kazuko") and not ResidentVisits.unlocked("home_mio"))
	check("a workshop invitation never silently grants a private home",not ResidentVisits.unlocked("toolshed") and not ResidentVisits.unlocked("home_tanaka"))
	var identity: int=m.npcs.haru.get_instance_id()
	await m.story.visits.handle("visit_home_haru_door")
	check("the ordinary invited door enters Haru's actual room with the same actor",m.in_room and m.room_kind=="home_haru" and m.npcs.haru.get_instance_id()==identity and m.npcs.haru.global_position.distance_to(ResidentPlaces.SPECS.home_haru.origin)<6)
	await m.story.visits.handle("visit_home_haru_memory")
	check("only inspecting the picture introduces the material trip",ResidentVisits.state().blueprint_seen and ResidentVisits.unlocked("toolshed") and Progress.found("col_blueprint"))
	G.save_game();var where: Vector3=m.player.global_position;G.flags.clear();G.load_game();m._restore()
	check("SQLite restores the room, invitation and same resident without cloning",m.room_kind=="home_haru" and m.player.global_position.distance_to(where)<.15 and m.npcs.haru.get_instance_id()==identity and ResidentVisits.state().blueprint_seen)
	await m.exit_interior()

	check("the household exit returns to its own street address",not m.in_room and m.player.global_position.distance_to(ResidentPlaces.SPECS.home_haru.exit)<.2)
	G.minute=22*60
	check("an invited but closed home explains when to return",ResidentVisits.access_reason("home_haru").contains("10:00"))
	m.update_npcs(true)
	check("going home uses the resident's real private room rather than a hidden street spot",m.npcs.haru.home and m.npcs.haru.global_position.distance_to(ResidentPlaces.SPECS.home_haru.origin)<6 and m.npcs.tanaka.global_position.distance_to(ResidentPlaces.SPECS.home_tanaka.origin)<6)
	G.minute=18*60
	await m.enter_interior("home_ren");await m.exit_interior()
	check("a shop back-room exits inside the original bakery, not onto the street",m.in_room and m.room_kind=="bakery" and m.player.global_position.distance_to(ResidentPlaces.SPECS.home_ren.exit)<.2)
	await m.exit_interior()
	G.has_player_pos=true;G.player_in_room=false;G.player_region="farm";G.player_pos=FarmBuilder.ORIGIN+Vector3(0,.1,-.4)
	var outdoor: Dictionary=G.to_dict().duplicate(true)
	await m.enter_interior("home_haru")
	G.from_dict(outdoor);m._restore()
	check("loading an outside save from a visited room restores outdoor region, camera and weather",not m.in_room and m.room_kind=="" and not m.world.indoor and m.world.region=="farm" and not m.rig.fixed and m.rig.collide)

func _appointments() -> void:
	fresh();ResidentVisits.see_blueprint();ResidentVisits.measure()
	check("shared measuring gives a separate supper invitation",ResidentVisits.unlocked("home_tanaka") and ResidentPlaces.room_for("tanaka")=="home_tanaka")
	check("an appointment cannot be retroactively promised for today",ResidentVisits.arrange(0)!="" and ResidentVisits.state().promise.is_empty())
	check("the appointment picker skips festival evenings",not ResidentVisits.date_free(4))
	var saturday: int=1
	while G.weekday(saturday)!=G.SATURDAY:saturday+=1
	check("a completed market reserves Saturday evenings for the market",not ResidentVisits.date_free(saturday))
	ResidentVisits.arrange(1)
	check("a promise has the following day and a visible three-hour window",int(ResidentVisits.state().promise.day)==6 and ResidentVisits.promise_text().contains("17:00—20:00"))
	ResidentVisits.choose_scheme("near");var uid: int=ResidentVisits.state().bench_uid
	ResidentVisits.cancel();m.story.visits.view.sync_state()
	check("cancellation keeps the actual loan and shows the neighbours' simpler setup",ResidentVisits.state().bench_uid==uid and not ResidentVisits.bench().is_empty() and m.story.visits.view.fallback.visible)
	ResidentVisits.arrange(2);G.day=7;G.minute=20*60;ResidentVisits.tick()
	check("missing this occasion records a miss without deleting work or claiming a trial",ResidentVisits.state().promise.status=="missed" and ResidentVisits.state().trial.is_empty() and ResidentVisits.state().bench_uid==uid)
	var inventory: int=G.count("bench");ResidentVisits.arrange(1);ResidentVisits.choose_scheme("path")
	check("rescheduling moves the same loan without duplicating borrowed chairs",G.placed_count("bench")==1 and G.count("bench")==inventory)
	var schema: Dictionary=ResidentVisits.state().duplicate(true);G.save_game();G.flags.erase("resident_visits");G.load_game()
	check("save restoration retains date, cancellation history, placement and contribution",ResidentVisits.state().promise==schema.promise and ResidentVisits.state().promise_history==schema.promise_history and ResidentVisits.state().bench_uid==schema.bench_uid,JSON.stringify(ResidentVisits.state().promise)+" / "+JSON.stringify(schema.promise))

func _two_routes() -> void:
	for key: String in ["near","path"]:
		fresh();ResidentVisits.see_blueprint();ResidentVisits.measure();ResidentVisits.arrange(1)
		var why: String=ResidentVisits.choose_scheme(key)
		check(key+" layout places a real reachable chair",why=="" and not ResidentVisits.bench().is_empty(),why)
		G.day=6;G.minute=17.5*60;G.phase="prep";m.world.sync_festivals();m.update_npcs(true)
		await t.frames(3)
		await m.story.visits.view.trial()
		var trial: Dictionary=ResidentVisits.state().trial
		check(key+" completes only after the real route, seat surface and line of sight pass",not trial.is_empty() and trial.get("seated",false) and trial.get("sight_clear",false),str(trial))
		check(key+" succeeds without a personally crafted lamp or meal",not trial.is_empty() and trial.get("food_author","")=="kazuko" and trial.get("light_author","")=="neighbours" and WorkshopProject.state().phase=="invitation")
		check(key+" records its different location and leads to a photo-room invitation",trial.get("scheme","")==key and ResidentVisits.unlocked("photo_room") and ResidentVisits.state().promise.get("status","")=="kept")
		var camera:=Camera3D.new();m.add_child(camera)
		m.story.visits.view._frame_seat(camera,ResidentVisits.bench())
		var camera_clear: bool=true
		for target: Vector3 in [Vector3(float(ResidentVisits.bench().x),1.2,float(ResidentVisits.bench().z)),SummerSpace.DEMO+Vector3.UP]:
			var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,target,WorldBuilder.L_SOLID|WorldBuilder.L_PLACED)
			camera_clear=camera_clear and m.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		check(key+" photograph sees both seat and child without the boundary wall",camera_clear)
		camera.free()
		check("headless never substitutes a generic illustration for a new scene photograph",not ResidentVisits.state().photo_rendered)
		var compared: bool=ResidentVisits.compare_photo()
		check("an unrendered or missing photograph cannot invent a comparison and private invitation",not compared and not ResidentVisits.unlocked("home_mio") and ResidentPlaces.room_for("mio")=="home_mio")

func _followups() -> void:
	fresh();ResidentVisits.see_blueprint();ResidentVisits.measure()
	ResidentVisits.followup("invitation_written","aoi")
	await m.enter_interior("post");m.ui.auto_choices=[0];await m.story.visits.handle("visit_post_memory")
	check("posting actually records the chosen addressee and today's date",ResidentVisits.state().followups.has("letter_sent") and ResidentVisits.state().followups.letter_sent.choice=="aoi")
	await m.story.visits.handle("visit_post_memory")
	check("the reply is not awarded before the declared two days",not ResidentVisits.state().followups.has("letter_reply"))
	G.day+=2;await m.story.visits.handle("visit_post_memory")
	check("returning later gives an actionable reply and preserves the outgoing letter",ResidentVisits.state().followups.has("letter_reply") and ResidentVisits.state().followups.has("letter_sent"))
	var old_day: int=int(ResidentVisits.state().followups.get("letter_sent",{}).get("day",-1))
	G.quests.Q15={"state":"done","step":4};MainlineProgress.choose_direction(2,"home")
	m.ui.auto_choices=[0];await m.story.visits.handle("visit_post_memory")
	check("the ending direction requires a new mailing and does not reuse an old letter",MainlineProgress.direction().get("action_done",false) and ResidentVisits.state().followups.has("next_summer_letter") and ResidentVisits.state().followups.letter_sent.day==old_day)
	await m.exit_interior()

func _settled_revisits() -> void:
	fresh();ResidentVisits.see_blueprint();ResidentVisits.measure()
	ResidentVisits.choose_scheme("near")
	# A previously compared save is a monotonic fact. Native capture is verified separately.
	var p: Dictionary=ResidentVisits.state()
	p.photo_compared=true;p.phase="settled";p.trial={"day":G.day,"scheme":"near"}
	ResidentVisits.invite("home_mio","already compared photograph")
	ResidentVisits.followup("invitation_written","mio")
	ResidentVisits.followup("letter_sent","mio")
	var followups: Dictionary=p.followups.duplicate(true)
	var inventory: Dictionary=G.inventory.duplicate(true)
	var coins: int=G.coins
	var later: int=ResidentVisits.next_free_day(G.day)
	var why: String=ResidentVisits.arrange(later-G.day)
	check("a later trial appointment preserves the already compared story and current letter goal",why=="" and ResidentVisits.state().phase=="settled" and ResidentVisits.hud().target=="visit_post_door" and ResidentVisits.promise_text().contains("17:00—20:00"))
	ResidentVisits.cancel()
	check("cancelling an optional repeat never sends completed correspondence back to the photo room",ResidentVisits.state().phase=="settled" and ResidentVisits.hud().target=="visit_post_door" and ResidentVisits.state().promise.status=="cancelled")
	ResidentVisits.arrange(later-G.day)
	G.day=later;G.minute=20*60;ResidentVisits.tick()
	check("missing an optional repeat keeps the letter goal while showing the missed promise",ResidentVisits.state().phase=="settled" and ResidentVisits.hud().target=="visit_post_door" and ResidentVisits.state().promise.status=="missed")
	later=ResidentVisits.next_free_day(G.day);ResidentVisits.arrange(later-G.day)
	G.day=later;G.minute=17.5*60;m.world.sync_festivals();m.update_npcs(true)
	await t.frames(3)
	await m.story.visits.view.trial()
	check("a real repeated walking trial retains the completed comparison and correspondence",ResidentVisits.state().promise.status=="kept" and ResidentVisits.state().phase=="settled" and ResidentVisits.hud().target=="visit_post_door" and ResidentVisits.state().followups==followups)
	# Simulate a save written by the earlier implementation after an optional repeat.
	ResidentVisits.state().phase="photo"
	G.save_game()
	var stored_phase: String=str(SaveDB.load_candidates()[0].data.flags.resident_visits.phase)
	G.flags.clear();G.load_game()
	var repaired: Dictionary=ResidentVisits.state().duplicate(true)
	var repaired_again: Dictionary=ResidentVisits.state().duplicate(true)
	check("loading an older regressed phase restores completed progress idempotently",stored_phase=="photo" and repaired.phase=="settled" and repaired==repaired_again and repaired.followups==followups and ResidentVisits.unlocked("home_mio"),JSON.stringify({"stored_phase":stored_phase,"phase":repaired.phase,"idempotent":repaired==repaired_again,"followups":repaired.followups,"original_followups":followups,"invited":ResidentVisits.unlocked("home_mio")}))
	check("restoring completed progress never repeats rewards or issues another loan",G.inventory==inventory and G.coins==coins and G.placed_count("bench")==1)
