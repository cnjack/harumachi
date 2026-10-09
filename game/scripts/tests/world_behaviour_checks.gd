extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void: t=runner; main=runner.main
func check(label: String, ok: bool, detail: String = "") -> void: t.check("WORLD_BEHAVIOUR",label,ok,detail)
func same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index: int in a.size():
			if not same(a[index],b[index]): return false
		return true
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b)) < .000000001
	return a == b
func run() -> void:
	var original: Dictionary = GameState.to_dict().duplicate(true)
	var entries: Array = Dialogue.entries.duplicate(true)
	var old_auto_priority: bool = main.ui.auto_work_priority
	main.ui.auto_work_priority = false
	GameState.new_game(); GameState.clock_paused = true
	check("walking cats can persist and restore their actual behaviour",main.life.roaming_cats.size() >= 2 and main.life.roaming_cats[0].has_method("snapshot"))
	if main.life.roaming_cats.size() >= 2 and main.life.roaming_cats[0].has_method("snapshot"):
		var cat: CharacterBody3D = main.life.roaming_cats[0]
		cat.reset_behaviour(101)
		var saved: Dictionary = cat.snapshot().duplicate(true)
		cat._choose_destination()
		var first: Dictionary = cat.snapshot().duplicate(true)
		cat.reset_behaviour(101,saved)
		for index: int in 100: randf()
		cat._choose_destination()
		check("UI/global randomness cannot change the next cat decision",cat.snapshot() == first)
		cat.blocked_seconds = .9
		var blocked: Dictionary = cat.snapshot().duplicate(true)
		cat.blocked_seconds = 0
		cat.reset_behaviour(101,blocked)
		check("restoring a blocked cat preserves its actual yield timer",absf(cat.blocked_seconds-.9) < .001)
		var starts: Dictionary = {}
		var inside := true
		for seed_value: int in [11,29,43,73,97,101,137,151]:
			cat.reset_behaviour(seed_value)
			starts[str(cat.snapshot().position)] = true
			inside = inside and cat.habitat.has_point(Vector2(cat.global_position.x,cat.global_position.z)) and cat._clear(cat.global_position)
		check("different seeds produce varied safe starts within the familiar cat area",starts.size() > 1 and inside)
		var blockers: Array[StaticBody3D]=[]
		for route_index: int in cat.route.size():
			var obstruction:=StaticBody3D.new();obstruction.collision_layer=WorldBuilder.L_PLACED
			var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.30,.6,.30);collider.shape=shape;collider.position.y=.30;obstruction.add_child(collider)
			main.add_child(obstruction);obstruction.global_position=cat.route[route_index];blockers.append(obstruction)
		await t.frames(2)
		cat.reset_behaviour(313)
		check("all blocked cat anchors wait invisibly without an actor collider",cat.waiting_for_spawn and not cat.visible and cat.collision_layer==0)
		blockers[0].collision_layer=0
		await t.frames(2)
		var one_safe: bool=true
		for seed_value: int in range(20,40):
			cat.reset_behaviour(seed_value)
			one_safe=one_safe and not cat.waiting_for_spawn and cat.global_position.distance_to(cat.route[0])<.02
		check("every seed examines the only safe cat anchor before giving up",one_safe)
		for obstruction: StaticBody3D in blockers:obstruction.queue_free()
		await t.frames(2)
		GameState.flags.world_seed = 808
		main.life._sync_animal_seed(true)
		main.life.before_save()
		var snapshot: Dictionary = GameState.flags.animal_life.duplicate(true)
		cat.global_position += Vector3(.15,0,.15)
		main.life._sync_animal_seed(true)
		check("same-seed in-scene restoration reads the persisted cat position",cat.global_position.distance_to(main.life._from_array(snapshot.cats["0"].position)) < .002)
		check("animal RNG state is stored as exact text rather than JSON floating numbers",snapshot.cats["0"].rng_state is String and snapshot.flocks["0"].rng_state is String and snapshot.flyers["0"].rng_state is String)
		GameState.save_game()
		GameState.flags.erase("animal_life")
		var loaded: bool = GameState.load_game()
		if GameState.flags.get("animal_life",{}) != snapshot:
			for argument: String in OS.get_cmdline_user_args():
				if argument.begins_with("--out="):
					var file: FileAccess = FileAccess.open(argument.trim_prefix("--out=").get_base_dir().path_join("animal-roundtrip-debug.json"),FileAccess.WRITE)
					file.store_string(JSON.stringify({"expected":snapshot,"actual":GameState.flags.get("animal_life",{})},"  ",false,true))
		# Observed JSON decimal rounding is below 1e-12m; RNG and all discrete/string states remain exact.
		check("SQLite round-trips animal state without replacing it with a new roll",loaded and same(GameState.flags.get("animal_life",{}),snapshot))
	var insect: Dictionary=main.life.flyers[0]
	var air_obstruction:=StaticBody3D.new();air_obstruction.collision_layer=WorldBuilder.L_PLACED
	var air_collider:=CollisionShape3D.new();var air_shape:=BoxShape3D.new();air_shape.size=Vector3(.4,.4,.4);air_collider.shape=air_shape;air_obstruction.add_child(air_collider)
	main.add_child(air_obstruction);air_obstruction.global_position=insect.home
	insect.node.position=insect.home
	await t.frames(2)
	check("an insect born inside a prop enters at a clear point within its familiar area",main.life._prepare_flyer(insect) and main.life._air_clear(insect.node,insect.node.global_position) and insect.node.global_position.distance_to(insect.home)<3)
	air_obstruction.collision_layer=WorldBuilder.L_ACTORS
	await t.frames(2)
	check("airborne animals also reject character and roaming-cat colliders",not main.life._air_clear(insect.node,air_obstruction.global_position))
	var old_target: Vector3=insect.target
	insect.blocked_time=.7
	main.life._flyer_step(insect,air_obstruction.global_position,.2)
	check("a blocked insect replaces its target with a safe point rather than retrying forever",insect.target!=old_target and main.life._air_clear(insect.node,insect.target))
	air_obstruction.queue_free()
	var flock: Dictionary=main.life.flocks[0]
	var returning: Dictionary=flock.birds[0]
	var landing: Vector3=main.life._landing(returning.node,flock.home+returning.off)
	var bird_obstruction:=StaticBody3D.new();bird_obstruction.collision_layer=WorldBuilder.L_PLACED
	var bird_collider:=CollisionShape3D.new();var bird_shape:=BoxShape3D.new();bird_shape.size=Vector3(.4,.4,.4);bird_collider.shape=bird_shape;bird_obstruction.add_child(bird_collider)
	main.add_child(bird_obstruction);bird_obstruction.global_position=landing+Vector3.UP*.1
	returning.to=landing;returning.node.position=landing+Vector3.UP;returning.grounded=true
	flock.state="return";flock.timer=1.5
	main.life.set_process(false);await t.frames(2)
	main.life._update_flock(flock,0,Vector3(-100,0,-100))
	check("a blocked returning bird is hidden and reselects a landing instead of pecking in midair",not returning.grounded and not returning.node.visible)
	bird_obstruction.queue_free();main.life.set_process(true)
	var constants: Dictionary = main.story.get_script().get_script_constant_map()
	check("conversation has a shared actual-place and identity provider",constants.has("CONVERSATION"))
	if constants.has("CONVERSATION"):
		await main.finish_arrival_home(false)
		if main.in_room: await main.exit_room()
		var actor: NPC = main.npcs.mio
		actor.set_home(false); actor.place(Vector3(-6.4,0,-6.6),20)
		main.player.global_position = actor.global_position + Vector3(1, .05, 1)
		await main.story.CONVERSATION.introduce(main.story,"mio")
		main.ui.dialogue_end()
		check("first identity is recorded only after presentation without accepting a quest",GameState.flags.neighbour_identity.presented.has("mio") and GameState.qstate("Q01") == "available")
		var identity: Dictionary = GameState.flags.neighbour_identity.duplicate(true)
		await main.story.CONVERSATION.introduce(main.story,"mio")
		main.ui.dialogue_end()
		check("a second introduction does not replace the first presentation record",GameState.flags.neighbour_identity == identity)
		actor.place(Vector3(-1.4,0,21.4),180)
		check("conversation context follows the actual new position",main.story.CONVERSATION.context(main.story,"mio").place == "courtyard")
		var event: Dictionary = {"id":"audit_personal_event","who":"mio","event":true,"once":true,"priority":100,"when":{},"lines":[["narrator","","这是一条测试用的小事，不代表玩家完成了委托。"]]}
		Dialogue.entries.push_front(event)
		main.player.global_position = actor.global_position + Vector3(1,.05,1)
		GameState.quests.Q01 = {"state":"done","step":2}
		GameState.quests.Q05 = {"state":"done","step":7}
		main.ui.auto_choices = [1]
		await t.use("mio", [1])
		check("choosing another topic does not replay the same event through ordinary chat",not GameState.flags.get("dlg_once_audit_personal_event",false))
		GameState.quests.Q01 = {"state":"available","step":0}
		main.story.personal_event_skipped = ""
		main.ui.auto_choices = [2]
		await main.story.CONVERSATION.personal_event(main.story,"mio")
		check("deferring a personal event consumes neither the story nor the work",not GameState.flags.get("dlg_once_audit_personal_event",false) and GameState.qstate("Q01") == "available" and not Dialogue.matches(event,{}))
		GameState.day += 1
		check("the deferred story remains available on another day",Dialogue.matches(event,{}))
		main.story.personal_event_skipped = ""
		main.ui.auto_choices = [0]
		await main.story.CONVERSATION.personal_event(main.story,"mio")
		check("a heard personal event is marked while the unaccepted work remains available",GameState.flags.get("dlg_once_audit_personal_event",false) and GameState.qstate("Q01") == "available")
		GameState.flags.erase("neighbour_identity")
		GameState.flags.erase("met_ren")
		await main.story.CONVERSATION.introduce(main.story,"ren")
		check("legacy saves are not given invented new identity records",not GameState.flags.has("neighbour_identity"))
	check("Sunday and weekday bakery routines differ but keep the same principal opening workplace",Layout.daily_schedule("ren",6,"sunny").size() > Layout.daily_schedule("ren",4,"sunny").size() and Layout.daily_schedule("ren",6,"sunny")[0][2] == Layout.SCHEDULE.ren[0][2])
	check("rain preserves the known workplace routine",Layout.daily_schedule("ren",6,"rain") == Layout.SCHEDULE.ren)
	Dialogue.entries = entries
	main.ui.auto_choices.clear(); main.ui.auto_work_priority = old_auto_priority
	GameState.from_dict(original); main._restore(); GameState.clock_paused = true
