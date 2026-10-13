extends Node3D
## Render existing story facts with the same physical props, not a second quest ledger.
const MESH_PARTS = preload("res://scripts/world/scene_lifecycle_meshes.gd")
var world: Node
var stage_parts: Array[Node3D] = []
var stage: Node3D
var stage_collision: StaticBody3D
var stage_daily_bounds: AABB
var stage_event_bounds: AABB
var stockpile: Node3D
var stockpile_meshes: Array[MeshInstance3D] = []
var remaining_beams: Array[Node3D] = []
var delivered_beams: Array[Node3D] = []
var work: Node3D
var scaffold: Node3D
var seedling: Node3D
var harvest: Node3D
var taiko_cover: MeshInstance3D
var taiko_sticks: Node3D
var _taiko_practice := 0
var _last: Dictionary = {}
var _poster_texture: Texture2D
var _poster_photo_path := ""
var _tick := 0.0

func setup(owner_world: Node) -> void:
	world = owner_world; name = "SceneLifecycle"
	stage = world.get_node("P10")
	stage_parts = MESH_PARTS.prepare_stage(stage)
	stage_event_bounds = MESH_PARTS.visible_bounds(stage)
	for part: Node3D in stage_parts: part.visible = false
	stage_daily_bounds = MESH_PARTS.visible_bounds(stage)
	for body: StaticBody3D in stage.find_children("*", "StaticBody3D", true, false):
		stage_collision = body; break
	stockpile = world.farm.get_node("D09_log_pile")
	stockpile_meshes = WorldBuilder.find_meshes(stockpile)
	_build_wood()
	_build_taiko_cover()
	seedling = world.get_node_or_null("ModelDiversity/N17_seedling_tray")
	harvest = world.farm.get_node_or_null("ModelDiversity/N18_harvest_basket")
	for child: Node in world.poster.get_children():
		if child is MeshInstance3D:
			_poster_texture = (child.material_override as StandardMaterial3D).albedo_texture; break
	GameState.state_changed.connect(sync_state, CONNECT_DEFERRED)
	GameState.time_changed.connect(func(_minute: int): sync_state())
	GameState.plots_changed.connect(sync_state)
	sync_state()

func begin_practice(kind: String) -> void:
	if kind == "taiko": _taiko_practice += 1; sync_state()

func end_practice(kind: String) -> void:
	if kind == "taiko": _taiko_practice = maxi(0, _taiko_practice - 1); sync_state()

func _process(delta: float) -> void:
	_tick += delta
	if _tick >= .5:
		_tick = 0.0; sync_state()

## Called only after actual delivery/sale, so loading an old completed quest invents no fresh food.
func record_delivery(kind: String, amount: int = 1) -> void:
	if kind not in ["bread", "harvest"] or amount <= 0: return
	if not GameState.flags.get("scene_lifecycle", {}) is Dictionary: GameState.flags["scene_lifecycle"] = {}
	var record: Dictionary = GameState.flags.get("scene_lifecycle", {})
	record.version = 1
	if not record.get("deliveries", {}) is Dictionary: record.deliveries = {}
	var deliveries: Dictionary = record.get("deliveries", {})
	deliveries[kind] = {"day": GameState.day, "minute": GameState.minute, "amount": amount}
	record.deliveries = deliveries; GameState.flags.scene_lifecycle = record
	sync_state()

static func tea_state() -> String:
	var daily: Dictionary = GameState.flags.get("daily_life", {})
	var tea: Dictionary = daily.get("events", {}).get("tea", {})
	if str(tea.get("state", "pending")) == "in_progress": return "drinking"
	# The same physical tray is used while Haru and Aoi tend the nursery in
	# the morning, even after the one-off tea conversation has been completed.
	if GameState.day >= int(daily.get("introduced_day", GameState.day)) + 1 and GameState.qstate("Q00") == "done" and GameState.phase == "prep" and GameState.minute >= 450 and GameState.minute < 600:
		return "preparing"
	if str(tea.get("state", "pending")) == "done":
		return "returned" if int(tea.get("completed_day", -1)) == GameState.day and GameState.hour() < 20.0 else "stored"
	if GameState.day < int(daily.get("introduced_day", GameState.day)) + 1: return "stored"
	return "ready" if GameState.hour() >= 9.0 and GameState.hour() < 17.5 and GameState.weather != "rain" else "stored"

func snapshot() -> Dictionary:
	var festival: Dictionary = GameState.festival("natsumatsuri")
	var festival_day: int = int(festival.get("day", 17))
	var prep_day: int = int(festival.get("prep_day", festival_day - 1))
	var space: Dictionary = GameState.flags.get("summer_space", {})
	var moved: int = clampi(int(space.get("optional_wood", 0)), 0, 6)
	if not SummerProjects.uses_cooperation_mainline():
		moved = 6 if GameState.qstate("Q13") == "done" or GameState.at_step("Q13", "give_wood") else mini(6, GameState.count("wood")) if GameState.at_step("Q13", "carry_wood") else 0
	var resident_finished: bool = bool(GameState.flags.get("town_finished_Q13", false))
	var retained: bool = str(space.get("phase", "invitation")) == "retained" or GameState.qstate("Q13") == "done" and not resident_finished
	var window: bool = GameState.day >= prep_day and GameState.day <= festival_day
	var now: String = GameState.festival_now()
	var phase: String = "stored"
	if window:
		if now == "natsumatsuri": phase = "open"
		elif GameState.day == festival_day and GameState.hour() >= float(festival.get("end", 22.0)):
			phase = "cleanup" if GameState.hour() < float(festival.get("end", 22.0)) + .5 else "stored"
		elif retained or GameState.day == festival_day and GameState.hour() >= float(festival.get("start", 17.0)) - 1.0:
			phase = "ready"
		elif moved > 0 or str(space.get("phase", "invitation")) != "invitation" or resident_finished: phase = "building"
	elif GameState.day < prep_day and (moved > 0 or str(space.get("phase", "invitation")) != "invitation"):
		phase = "building"
	var opening: Dictionary = GameState.flags.get("summer_projects", {}).get("opening", {})
	var service: Dictionary = opening.get("service", {})
	var deliveries: Dictionary = GameState.flags.get("scene_lifecycle", {}).get("deliveries", {})
	var bread_delivery: Dictionary = deliveries.get("bread", {})
	var harvest_delivery: Dictionary = deliveries.get("harvest", {})
	var market: bool = GameState.phase == "market" or now == "natsumatsuri"
	var bread: String = "stored"
	# Cooperative portions already have a real batch/remaining count in ProjectView.
	# This basket is the resident's legacy bread stock, not a duplicate of that food.
	if service.is_empty():
		if market: bread = "resident_market"
		elif int(bread_delivery.get("day", -1)) == GameState.day and GameState.minute >= float(bread_delivery.get("minute", 0.0)) and GameState.hour() < 20.0: bread = "delivered"
	var court: Dictionary = GameState.plots.get("court", {})
	var nursery: bool = GameState.qstate("Q03") == "active" and str(court.get("crop", "")).is_empty()
	var sale: bool = int(harvest_delivery.get("day", -1)) == GameState.day and GameState.minute >= float(harvest_delivery.get("minute", 0.0)) and GameState.hour() >= 8.0 and GameState.hour() < 19.0
	var sign: String = "stored"
	if GameState.qstate("Q01") == "done" and GameState.qstate("Q05") != "done": sign = "market_planning"
	elif GameState.day <= festival_day and (str(space.get("phase", "invitation")) != "invitation" or resident_finished and window): sign = "summer_planning"
	if market or phase in ["ready", "open"]: sign = "open"
	if phase == "cleanup": sign = "cleanup"
	return {"festival": phase, "resident_finished": resident_finished, "wood_moved": moved, "wood_used": retained or phase in ["ready", "open", "cleanup"] or GameState.day > festival_day,
		"public_equipment": market, "taiko_practice": _taiko_practice > 0, "bread": bread, "nursery": nursery, "harvest": sale, "tea": tea_state(), "sign": sign,
		"poster": GameState.qstate("Q04") == "done" or GameState.qstate("Q05") == "done" or market,
		"market_day": GameState.next_market_day(), "day": GameState.day, "region": str(world.region), "indoor": bool(world.indoor)}

func sync_state() -> void:
	if not is_instance_valid(world): return
	var state: Dictionary = snapshot()
	var local_town: bool = world.region == "town" and not world.indoor
	for part: Node3D in stage_parts: part.visible = bool(state.public_equipment)
	var drum_in_use: bool = bool(state.public_equipment) or bool(state.taiko_practice)
	taiko_cover.visible = not drum_in_use
	if taiko_sticks: taiko_sticks.visible = drum_in_use
	world.taiko_drum.set_meta("lifecycle_state", "practice" if state.taiko_practice else "open" if state.public_equipment else "covered")
	stage.set_meta("lifecycle_state", "event" if state.public_equipment else "daily")
	if stage_collision and (_last.is_empty() or bool(_last.get("public_equipment", false)) != bool(state.public_equipment)):
		var shape: CollisionShape3D = stage_collision.get_child(0) as CollisionShape3D
		var bounds: AABB = stage_event_bounds if state.public_equipment else stage_daily_bounds
		if shape and shape.shape is BoxShape3D:
			if not shape.has_meta("lifecycle_unique"):
				shape.shape = shape.shape.duplicate(); shape.set_meta("lifecycle_unique", true)
			shape.shape.size = bounds.size * .90; shape.position = bounds.get_center()
	_sync_festival(state, local_town)
	_sync_wood(state, local_town)
	world.stall_bread.visible = str(state.bread) != "stored" and world.region == "town"
	world.stall_bread.set_meta("lifecycle_state", state.bread)
	_sync_poster(state)
	var sign: Node3D = world.get_node("BuildSign")
	activate(sign, str(state.sign) != "stored" and local_town)
	var caption: String = {"market_planning": "小集市试摆\n桌椅 · 取餐", "summer_planning": "今年的场地\n先试走 · 再搭台", "open": "今天在这里\n坐一会儿 · 慢慢尝", "cleanup": "一起收好\n下次还用"}.get(str(state.sign), "")
	if str(state.sign) == "summer_planning" and int(state.wood_moved) > 0: caption = "田中正在搭台\n木料到场 %d / 6" % int(state.wood_moved)
	if str(state.sign) == "summer_planning" and bool(state.resident_finished): caption = "田中与街坊在搭台\n先留出通道"
	if str(state.sign) == "open" and str(state.festival) == "ready" and str(world.fest_nodes.natsumatsuri.get_meta("assembled_by", "")) == "residents": caption = "田中与街坊已搭好\n今晚一起过来"
	for label: Label3D in sign.find_children("*", "Label3D", true, false):
		if label.text != caption:
			label.text = caption
			# Each caption starts at the intended em before fitting; a short later
			# caption must recover its size after a longer resident-work notice.
			label.pixel_size = .1584 / float(label.font_size)
			ClearSignage.fit(label, Vector2(1.1, .62), .06)
	if seedling:
		activate(seedling, bool(state.nursery)); seedling.set_meta("lifecycle_state", "ready" if state.nursery else "stored")
	if harvest:
		activate(harvest, bool(state.harvest)); harvest.set_meta("lifecycle_state", "delivered" if state.harvest else "stored")
	var cloth: Node3D = world.farm.get_node_or_null("ReviewedLibrary/PicnicCloth")
	if cloth: activate(cloth, false) # No current game event actually invites anyone to this display cloth.
	_last = state

func _sync_festival(state: Dictionary, local_town: bool) -> void:
	var group: Node3D = world.fest_nodes.natsumatsuri
	var phase: String = str(state.festival)
	activate(group, phase in ["ready", "open", "cleanup"] and local_town)
	for child: Node in group.get_children():
		if not child is Node3D: continue
		var prop: Node3D = child
		var structural: bool = str(prop.get_meta("model_id", "")) in ["P_yagura", "E01_yatai"]
		# During cleanup the substantial frames remain briefly while decoration is put away.
		activate(prop, group.visible and (phase in ["ready", "open"] or phase == "cleanup" and structural))
	group.set_meta("lifecycle_state", phase)
	group.set_meta("assembled_by", "player_and_residents" if GameState.qstate("Q13") == "done" and not state.resident_finished or str(GameState.flags.get("summer_space", {}).get("phase", "")) == "retained" else "residents")
	if scaffold: activate(scaffold, phase == "building" and (int(state.wood_moved) >= 2 or state.resident_finished) and local_town)
	var scene: Node = world.get_parent()
	if scene and scene.get("story") != null and scene.story.space.view != null and (_last.get("festival", "") != phase or _last.get("region", "") != world.region or _last.get("indoor", false) != world.indoor or int(_last.get("day", -1)) != GameState.day):
		scene.story.space.view.sync_state()

func _sync_wood(state: Dictionary, local_town: bool) -> void:
	var moved: int = int(state.wood_moved)
	stockpile.set_meta("remaining_logs", 6 - moved)
	for mesh: MeshInstance3D in stockpile_meshes: mesh.visible = moved == 0
	for index: int in remaining_beams.size(): remaining_beams[index].visible = moved > 0 and index < 6 - moved
	# Reuse the same original stockpile collision footprint until its last beam is removed.
	for body: StaticBody3D in stockpile.find_children("*", "StaticBody3D", true, false):
		if not body.has_meta("lifecycle_layer"): body.set_meta("lifecycle_layer", body.collision_layer)
		body.collision_layer = int(body.get_meta("lifecycle_layer")) if moved < 6 else 0
	work.set_meta("delivered_logs", moved)
	activate(work, moved > 0 and not state.wood_used and local_town)
	for index: int in delivered_beams.size(): activate(delivered_beams[index], index < moved and work.visible)

func _sync_poster(state: Dictionary) -> void:
	world.poster.visible = bool(state.poster) and world.region == "town"
	var caption: String = "周六小集市\n第%d天 · 傍晚" % int(state.market_day)
	if state.public_equipment: caption = "今天开摊\n庭院 · 慢慢尝"
	elif str(state.festival) == "building": caption = "今年的夏祭\n场地试摆中"
	elif GameState.day > 17 and Progress.found("col_photo_new"): caption = "今年一起留下的照片\n下次，还在树下"
	for child: Node in world.poster.get_children():
		if child is Label3D: child.text = caption
		if child is MeshInstance3D:
			var material: StandardMaterial3D = child.material_override
			var path: String = GameState.photo_path() if Progress.found("col_photo_new") and GameState.day > 17 and FileAccess.file_exists(GameState.photo_path()) else ""
			if path != _poster_photo_path:
				material.albedo_texture = _poster_texture if path.is_empty() else ImageTexture.create_from_image(Image.load_from_file(path))
				_poster_photo_path = path
	world.poster.set_meta("lifecycle_caption", caption)

static func activate(prop: Node3D, enabled: bool) -> void:
	prop.visible = enabled
	if not prop.has_meta("lifecycle_bodies"):
		prop.set_meta("lifecycle_bodies", prop.find_children("*", "StaticBody3D", true, false))
	for body: StaticBody3D in prop.get_meta("lifecycle_bodies"):
		if not is_instance_valid(body): continue
		if not body.has_meta("lifecycle_layer"): body.set_meta("lifecycle_layer", body.collision_layer)
		body.collision_layer = int(body.get_meta("lifecycle_layer")) if enabled else 0

func _build_wood() -> void:
	var reserve := Node3D.new(); reserve.name = "RemainingBeams"; stockpile.add_child(reserve)
	work = Node3D.new(); work.name = "ConstructionWood"; add_child(work)
	work.position = Vector3(-3.8, 0, 20.3)
	for index: int in 6:
		var at := Vector3((index % 3 - 1) * .24, .07 + (index / 3) * .14, 0)
		var remaining: Node3D = _beam(reserve, "Beam_%d" % index, at, Vector3(.20, .13, .56))
		remaining_beams.append(remaining)
		var delivered: Node3D = _beam(work, "Beam_%d" % index, at, Vector3(.20, .13, 1.15), true)
		delivered_beams.append(delivered)
	scaffold = Node3D.new(); scaffold.name = "StageFramework"; add_child(scaffold)
	scaffold.position = WorldBuilder.YAGURA_POS
	for index: int in 4:
		var at := Vector3(-1.1 if index % 2 == 0 else 1.1, .55, -.9 if index < 2 else .9)
		_beam(scaffold, "Upright_%d" % index, at, Vector3(.12, 1.1, .12), true)
	for side: float in [-1.0, 1.0]:
		_beam(scaffold, "Crossbar_%d" % int(side + 1), Vector3(0, 1.05, side * .9), Vector3(2.32, .12, .12), true)
	# These fit wholly within the three reserved future occupancy boxes; their
	# physical keep-out is owned by SpaceView until the real structures take over.

func _beam(parent: Node3D, label: String, at: Vector3, size: Vector3, solid: bool = false) -> MeshInstance3D:
	var model := MeshInstance3D.new(); model.name = label; model.position = at
	var mesh := BoxMesh.new(); mesh.size = size; model.mesh = mesh
	model.material_override = SurfaceFinish.timber(mesh.get_aabb(), Color(.62, .47, .29), 1)
	parent.add_child(model)
	if solid:
		var body := StaticBody3D.new(); body.collision_layer = WorldBuilder.L_SOLID; body.set_meta("model_part", true)
		var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = size
		collision.shape = box; body.add_child(collision); model.add_child(body)
	return model

func _build_taiko_cover() -> void:
	taiko_sticks = world.taiko_drum.find_child("CedarAge_1", true, false)
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[float] = [-.34, -.26, .26, .34]
	for row: int in 3:
		for column: int in 16:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var x: float = -.38 + float(column + corner.x) * .0475
				var z: float = rows[row + corner.y]
				var y: float = .42 if absf(z) > .30 else .765 + sqrt(maxf(0.0, .365 * .365 - x * x))
				surface.set_uv(Vector2(float(column + corner.x) / 16.0, float(row + corner.y) / 3.0))
				surface.add_vertex(Vector3(x, y, z))
	surface.generate_normals()
	taiko_cover = MeshInstance3D.new(); taiko_cover.name = "PracticeClothCover"; taiko_cover.mesh = surface.commit()
	# A draped cloth is a thin surface: both the near and far hanging panels
	# must render. Keep the shared wood/linen shader untouched elsewhere.
	var cloth_shader := Shader.new()
	cloth_shader.code = SurfaceFinish.SHADER.code.replace("specular_disabled;", "specular_disabled, cull_disabled;")
	var fabric := ShaderMaterial.new(); fabric.shader = cloth_shader
	fabric.set_shader_parameter("part_transform", Projection(Transform3D.IDENTITY))
	fabric.set_shader_parameter("finish_kind", 1); fabric.set_shader_parameter("base_color", Color(.43, .55, .70))
	taiko_cover.material_override = fabric; world.taiko_drum.add_child(taiko_cover)
