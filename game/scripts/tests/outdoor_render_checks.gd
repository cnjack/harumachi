extends RefCounted
## Keep the rendered grass triangles and the complete cloth solve unchanged.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("OUTDOOR_RENDER", label, ok, detail)

static func mesh_signature(mesh: ArrayMesh) -> String:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var stream := PackedByteArray()
	for corner: int in (indices.size() if not indices.is_empty() else vertices.size()):
		var index: int = indices[corner] if not indices.is_empty() else corner
		var colour: Color = arrays[Mesh.ARRAY_COLOR][index] if arrays[Mesh.ARRAY_COLOR] != null else Color.WHITE
		stream.append_array(var_to_bytes([vertices[index], normals[index], uvs[index], colour]))
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(stream)
	return digest.finish().hex_encode()

func run() -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/tests/fixtures/grass_geometry.json"))
	var matches := true
	var indexed := true
	var measured: Dictionary = {}
	for style: String in GrassField.STYLES:
		for variant: int in 3:
			var mesh: ArrayMesh = GrassField.clump_mesh(style, variant)
			var key: String = "%s%d" % [style, variant]
			var blades: int = int(GrassField.STYLES[style].n)
			matches = matches and mesh_signature(mesh) == str(reference.get(key, ""))
			indexed = indexed and mesh.surface_get_array_len(0) == blades * 7 and mesh.surface_get_array_index_len(0) == blades * 15
			measured[key] = {"vertices": mesh.surface_get_array_len(0), "corners": mesh.surface_get_array_index_len(0)}
	check("all15 grass variants preserve every ordered position normal UV and colour", matches and measured.size() == 15)
	check("grass reuses seven vertices per blade without removing any triangle", indexed, JSON.stringify(measured))
	var tufts: ArrayMesh = GrassField.mesh()
	check("wildflower crossed quads preserve all corners while sharing identical vertices", mesh_signature(tufts) == str(reference.get("tufts", "")) and tufts.surface_get_array_len(0) == 8 and tufts.surface_get_array_index_len(0) == 12)
	var defaults := true
	var explicitly_disabled: bool = OS.get_cmdline_user_args().has("--native-geometry=off")
	for id: String in ["mio", "ren", "kazuko"]:
		var support: Node = main.npcs[id].model.find_child("CharacterGarmentSupport", true, false)
		defaults = defaults and bool(support.get("native_geometry_enabled")) == (not explicitly_disabled)
	check("all three clothed residents select acceleration with the explicit GD fallback intact", defaults)
	var context: Dictionary = {"region": main.world.region, "in_room": main.in_room, "room_kind": main.room_kind, "player_in_room": GameState.player_in_room}
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	for id: String in ["mio", "ren", "kazuko"]:
		await _compare_complete_solves(id)
	main.in_room = context.in_room
	main.room_kind = context.room_kind
	GameState.player_in_room = context.player_in_room
	main.world.set_region(str(context.region))
	main.world.set_indoor_look(bool(context.in_room))

func _solve_snapshot(support: Node, use_native: bool) -> PackedByteArray:
	support.set("native_geometry_enabled", use_native)
	(support.get("cached_matrices") as Array).clear()
	support.call("_process_modification")
	var mesh: MeshInstance3D = support.get("mesh") as MeshInstance3D
	var weights := PackedFloat32Array()
	for shape: int in support.get("local_indices"):
		weights.append(mesh.get_blend_shape_value(shape))
	return var_to_bytes([support.get("last_branch"), support.get("amounts"), weights, support.get("max_contact_depth"), support.get("max_displacement"), support.get("active_targets"), support.get("saturated_constraints"), support.get("frame_ray_queries"), support.get("frame_broadphase_skips")])

func _compare_complete_solves(id: String) -> void:
	var npc: NPC = main.npcs[id]
	var support: Node = npc.model.find_child("CharacterGarmentSupport", true, false)
	var saved: Dictionary = {"position": npc.global_position, "home": npc.home, "process": npc.is_processing(), "yaw": npc._yaw, "clip": npc.anim.ap.current_animation, "time": npc.anim.ap.current_animation_position, "speed": npc.anim.ap.speed_scale, "state": npc.anim._state, "oneshot": npc.anim._oneshot, "native": support.get("native_geometry_enabled"), "proof": support.get("steady_proof_match"), "tolerance": support.get("pose_cache_tolerance_m")}
	npc.set_process(false)
	npc.set_home(false)
	npc.global_position = Vector3(-8, .010, -10)
	npc.set_yaw(0)
	# Both paths must actually solve the same pose, never compare two cache hits.
	support.set("steady_proof_match", false)
	support.set("pose_cache_tolerance_m", 0.0)
	var count := 0
	var native_layers := 0
	var bad: Array[String] = []
	for clip: String in ["idle", "walk", "run", "dance", "bow", "tend", "stretch"]:
		for phase: float in [0.0, .125, .25, .5, .75, .875]:
			npc.anim._oneshot = ""
			npc.anim._go(clip, 1.0)
			npc.anim.ap.play(clip, 0)
			npc.anim.ap.speed_scale = 0
			npc.anim.ap.seek(npc.anim.ap.get_animation(clip).length * phase, true)
			npc.anim.ap.advance(0)
			if npc.anim.clothing: npc.anim.clothing.reset()
			var natural: Node = support.get_skeleton().get_node_or_null("NaturalLocomotionPose")
			if natural != null: natural.call("finish_transition")
			for settle_frame: int in 3: await t.get_tree().process_frame
			var reference: PackedByteArray = _solve_snapshot(support, false)
			var before: int = int(support.get("native_geometry_calls"))
			var accelerated: PackedByteArray = _solve_snapshot(support, true)
			native_layers += int(support.get("native_geometry_calls")) - before
			count += 1
			if reference != accelerated or str(support.get("last_branch")) != "full": bad.append("%s %.3f" % [clip, phase])
	var available: bool = bool(support.get("native_contact_ready")) and ClassDB.class_has_method(&"NativeTriangleFilter", &"build_layer_geometry")
	check(id + " native and GD complete solves match byte for byte across42 poses", count == 42 and bad.is_empty() and (native_layers >= 84 if available else native_layers == 0), JSON.stringify({"poses": count, "native_layers": native_layers, "native_available": available, "different": bad}))
	support.set("native_geometry_enabled", saved.native)
	support.set("steady_proof_match", saved.proof)
	support.set("pose_cache_tolerance_m", saved.tolerance)
	(support.get("cached_matrices") as Array).clear()
	npc.global_position = saved.position
	npc.set_yaw(float(saved.yaw))
	npc.set_home(bool(saved.home))
	npc.set_process(bool(saved.process))
	npc.anim._oneshot = ""
	npc.anim._go(str(saved.state), 1.0)
	npc.anim._oneshot = str(saved.oneshot)
	npc.anim.ap.play(str(saved.clip), 0)
	npc.anim.ap.seek(float(saved.time), true)
	npc.anim.ap.speed_scale = float(saved.speed)
