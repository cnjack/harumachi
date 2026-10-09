class_name SummerSpace
extends RefCounted
## One layout identity, three different needs, then the same layout in shared use.
const AREA := [-11.5, 12.0, 11.5, 24.0]
const DANCE_CENTER := Vector2(-2.6, 18.8)
const DANCE_RADIUS := 3.6
const DEMO := Vector3(-2.6, 0, 22.0)
const ENTRY := Vector3(-3.0, 0, -3.0)
const HARU_START := Vector3(13.6, 0, 16.5)
const FOOD_START := Vector3(2.0, 0, 13.0)
const FUTURE_RECTS := [Rect2(-4.5, 16.9, 3.8, 4.35), Rect2(4.53, 19.74, 2.54, 2.3), Rect2(7.93, 19.74, 2.54, 2.3)]
const SCHEMES := {
	"east": {"name": "东侧供餐走外侧，附近可放盘", "style": "plate", "bench": [6.5, 23.5, 2], "table": [2.5, 19.0, 0]},
	"west": {"name": "西侧看得近，纸包在北侧取", "style": "paper", "bench": [-4.5, 23.5, 2], "table": [-6.5, 14.0, 2]}}

static func state() -> Dictionary:
	var defaults := {"version": 1, "phase": "invitation", "mode": "", "priority": "haru", "style": "paper", "kit_received": false,
		"invited": {}, "trials": {}, "scheme": "", "owned_uids": [], "bench_uid": -1, "table_uid": -1,
		"plan_id": "summer-space-1", "retained_revision": "", "application": {}, "application_history": [], "past_heard": false}
	if not GameState.flags.get("summer_space", {}) is Dictionary: GameState.flags["summer_space"] = {}
	var p: Dictionary = GameState.flags.get("summer_space", {})
	if int(p.get("version", 0)) != 1:
		GameState.flags["summer_space"] = defaults.duplicate(true)
		p = GameState.flags.summer_space
	p.merge(defaults, false)
	p.version = 1
	p.bench_uid = int(p.bench_uid)
	p.table_uid = int(p.table_uid)
	for index in p.owned_uids.size(): p.owned_uids[index] = int(p.owned_uids[index])
	for who: String in p.invited: p.invited[who] = int(p.invited[who])
	for trial: Dictionary in p.trials.values():
		if trial.has("day"): trial.day = int(trial.day)
		if trial.has("scope_version"):trial.scope_version=int(trial.scope_version)
	for application: Dictionary in p.application_history + [p.application]:
		if application.has("day"): application.day = int(application.day)
		for result: Dictionary in application.get("people", {}).values():
			if result.has("day"): result.day = int(result.day)
			if result.has("scope_version"):result.scope_version=int(result.scope_version)
	return p

static func start(mode: String, source: String) -> String:
	var G := GameState
	var p: Dictionary = state()
	if G.qstate("Q11") != "done": return "先把旧图纸的事情问清楚，再安排今年的场地。"
	if mode not in ["manual", "light"] or source not in ["loan", "own"]: return "先选怎么安排这块空地。"
	if p.phase != "invitation": return "这份方案已经开工，可以接着调整，不重新发桌椅。"
	if source == "loan":
		if not G.can_add_bundle({"picnic_table": 1, "bench": 1}): return "背包先留出桌和长椅的位置，也可以用已有桌椅。"
		G.add_item("picnic_table", 1, true)
		G.add_item("bench", 1, true)
		p.kit_received = true
	p.mode = mode
	p.style = str(SummerProjects.opening().final.get("presentation", "paper"))
	p.phase = "arranging"
	if G.qstate("Q13") == "available": G.start_quest("Q13")
	if SummerProjects.uses_cooperation_mainline(): G.advance("Q13", "ask_tanaka")
	_commit()
	return ""

static func set_style(style: String) -> void:
	if style not in ["paper", "plate"] or state().style == style: return
	state().style = style
	state().phase = "arranging"
	_commit()

static func choose_target(kind: String, uid: int) -> String:
	if kind not in ["bench", "picnic_table"]: return "选一张已经摆下的桌子或长椅。"
	var found := false
	for p: Dictionary in project_furniture(kind):
		if int(p.uid) == uid: found = true
	if not found: return "这件桌椅已经收起或不在这片场地，再选一次。"
	state()["bench_uid" if kind == "bench" else "table_uid"] = uid
	state().phase = "arranging"
	_commit()
	return ""

static func project_furniture(kind: String) -> Array:
	var out: Array = []
	for p: Dictionary in GameState.placements:
		if str(p.item) == kind and Rect2(AREA[0], AREA[1], AREA[2] - AREA[0], AREA[3] - AREA[1]).has_point(Vector2(p.x, p.z)): out.append(p)
	return out

static func furniture(kind: String) -> Dictionary:
	var options: Array = project_furniture(kind)
	var uid: int = int(state().bench_uid if kind == "bench" else state().table_uid)
	for p: Dictionary in options:
		if int(p.uid) == uid: return p
	return options[0] if options.size() == 1 else {}

static func stop_for(kind: String) -> Vector3:
	var p: Dictionary = furniture(kind)
	if p.is_empty(): return Vector3.INF
	var direction: Vector3 = Vector3.BACK.rotated(Vector3.UP, int(p.rot) * PI / 2.0)
	return Vector3(float(p.x), 0, float(p.z)) + direction * (.9 if kind == "bench" else 1.6)

static func invite(who: String, present: bool) -> String:
	if who not in ["mio", "haru", "ren"] or not present: return "先去跟本人约好，请他来庭院试试。"
	state().invited[who] = GameState.day
	_commit()
	return ""

static func revision() -> String:
	var p: Dictionary = state()
	return JSON.stringify([LayoutValidity.anchor(furniture("bench")),LayoutValidity.anchor(furniture("picnic_table")),p.style,FUTURE_RECTS.size(),DANCE_RADIUS]).sha256_text()

static func dependency(who: String) -> String:
	var anchors: Array=[]
	if who=="haru":anchors=[LayoutValidity.anchor(furniture("bench")),DEMO]
	elif who=="ren":
		anchors=[LayoutValidity.anchor(furniture("picnic_table")),state().style]
		if state().style=="plate":anchors.append(LayoutValidity.anchor(furniture("bench")))
	else:anchors=[ENTRY,DEMO]
	return JSON.stringify(anchors).sha256_text()

static func trial_current(who: String,application: bool=false) -> bool:
	var p: Dictionary=state()
	if application:
		var context: String=SummerGathering.context()
		if context=="":context="shared_rehearsal"
		if p.application.get("context","")!=context or int(p.application.get("day",0))!=GameState.day:return false
	var entry: Dictionary=p.application.get("people",{}).get(who,{}) if application else p.trials.get(who,{})
	if entry.is_empty():return false
	if int(entry.get("scope_version",0))!=1:
		return str(entry.get("revision",""))==JSON.stringify([GameState.placements,p.style,int(p.bench_uid),int(p.table_uid),FUTURE_RECTS.size(),DANCE_RADIUS]).sha256_text() and LayoutValidity.path_clear(entry.get("path",[])) and LayoutValidity.sight_clear(entry.get("sight",{}))
	if not LayoutValidity.measured(entry.get("path",[]),entry.get("sight",{}),who=="haru"):return false
	if str(entry.get("dependency",""))!=dependency(who):return false
	if not LayoutValidity.path_clear(entry.get("path",[])) or not LayoutValidity.sight_clear(entry.get("sight",{})):return false
	return who!="ren" or p.style!="plate" or stop_for("bench").distance_to(stop_for("picnic_table"))<=5.0

static func crosses_dance(path: Array) -> bool:
	for position: Vector3 in path:
		if Vector2(position.x, position.z).distance_to(DANCE_CENTER) < DANCE_RADIUS: return true
	return false

static func record(who: String, result: Dictionary, application: bool = false) -> String:
	var p: Dictionary = state()
	if not p.invited.has(who) or not result.get("present", false): return "这次人还没到，保留方案，之后再约。"
	if str(result.get("revision", "")) != revision(): return "布局或供餐方式变了，按现在的方案再看一次。"
	if not result.get("arrived", false): return str(result.get("reason", "半路被挡住了，挪开挡路的东西再走一遍。"))
	var target: Vector3 = DEMO if who == "mio" else stop_for("bench" if who == "haru" else "picnic_table")
	var actual: Dictionary = result.get("position", {})
	var position := Vector3(float(actual.get("x", INF)), float(actual.get("y", INF)), float(actual.get("z", INF)))
	if not target.is_finite() or position.distance_to(target) > .7: return "还没到这一次选的停点。"
	if who == "haru" and not result.get("visible_demo", false): return "春在这里看不到示范点，挪一下观看处，再看看视线。"
	if who == "ren" and p.style == "plate" and stop_for("bench").distance_to(target) > 5.0: return "放盘子的桌子离长椅超过5米，往近处挪一点。"
	if application and who != "mio" and result.get("crossed_dance", false): return "这条路穿过跳舞的地方。先不动桌椅，试试从外边绕。"
	if not LayoutValidity.measured(result.get("path",[]),result.get("sight",{}),who=="haru"):return "先把这一趟走完，春的观看处也要亲眼看看。"
	if LayoutValidity.point(result.path[-1]).distance_to(position)>.2:return "这趟还没走到选好的位置，先把剩下的一小段走完。"
	if not LayoutValidity.path_clear(result.get("path",[])) or not LayoutValidity.sight_clear(result.get("sight",{})):return "这一处刚被挡住了。原来的经历留着，先把眼前的障碍挪开。"
	if application:
		var context: String = SummerGathering.context()
		if context == "": context = "shared_rehearsal"
		var session: String = context + ":" + str(GameState.day)
		if p.application.get("context","")!=context or int(p.application.get("day",0))!=GameState.day:
			if not p.application.is_empty(): p.application_history.append(p.application.duplicate(true))
			p.application = {"revision": revision(), "people": {}, "context": context, "day": GameState.day, "session": session, "activity_id":context + ":" + str(GameState.day)}
		p.application.people[who] = result.duplicate(true)
	else: p.trials[who] = result.duplicate(true)
	var stored: Dictionary=p.application.people[who] if application else p.trials[who]
	stored["scope_version"]=1;stored["dependency"]=dependency(who)
	_commit()
	return ""

static func retain() -> String:
	var p: Dictionary = state()
	for who: String in ["mio", "haru", "ren"]:
		if not trial_current(who): return "%s这边还需要再看一眼，其余试过的安排留着。"%GameState.npc_display(who)
	p.retained_revision = revision()
	p.phase = "retained"
	if SummerProjects.uses_cooperation_mainline(): GameState.advance("Q13", "carry_wood")
	_commit()
	return ""

static func ready() -> bool:
	return str(state().phase)=="retained" and not str(state().retained_revision).is_empty() and ["mio","haru","ren"].all(func(who: String):return trial_current(who))

static func check_footprint(center: Vector2, fp: Vector2) -> String:
	var r := Rect2(center - fp / 2.0, fp)
	for rect: Rect2 in FUTURE_RECTS:
		if r.grow(-.01).intersects(rect): return "这里预留给舞台或夏祭屋台；占地已经显示在地上。"
	var nearest := Vector2(clampf(DANCE_CENTER.x, r.position.x, r.end.x), clampf(DANCE_CENTER.y, r.position.y, r.end.y))
	if nearest.distance_to(DANCE_CENTER) < DANCE_RADIUS + .1: return "给盆舞圈留出完整空地，桌椅放在圈外。"
	var views: Array[Node] = GameState.get_tree().get_nodes_in_group("summer_space_views")
	if not views.is_empty():
		var world: Node3D = views[0].get("world") as Node3D
		var query := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(fp.x * .98, 1.25, fp.y * .98)
		query.shape = box
		query.transform = Transform3D(Basis.IDENTITY, Vector3(center.x, .7, center.y))
		query.collision_mask = WorldBuilder.L_SOLID
		var contacts: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query, 4)
		if not contacts.is_empty():
			for contact: Dictionary in contacts: print("SPACE_BLOCK ", center, " ", contact.collider.get_parent().name)
			return "这里碰到现有的棚、台子或固定设施，先换一小片空处。"
	return ""

static func hint() -> String:
	if state().phase == "invitation": return "带图纸找田中。他和街坊搭台子，你来安排长椅和餐桌。"
	if ready(): return "摆法记下了。跟田中说说，等夏祭再请三位一起试。"
	return "庭院南侧场地纸签：安排长椅与桌面，当面约澪、春和莲，分别看入场、观看与供餐。"

static func _commit() -> void:
	GameState.state_changed.emit()
	GameState.save_game()

static func placement_added(uid: int, kind: String) -> void:
	var p: Dictionary = state()
	if p.phase == "invitation" or kind not in ["bench", "picnic_table"]: return
	if not p.owned_uids.has(uid): p.owned_uids.append(uid)
	if kind == "bench" and int(p.bench_uid) < 0: p.bench_uid = uid
	if kind == "picnic_table" and int(p.table_uid) < 0: p.table_uid = uid
	if uid==int(p.bench_uid) or uid==int(p.table_uid):p.phase = "arranging"

static func placement_removed(uid: int) -> void:
	var p: Dictionary = state()
	p.owned_uids.erase(uid)
	if int(p.bench_uid) == uid: p.bench_uid = -1
	if int(p.table_uid) == uid: p.table_uid = -1
