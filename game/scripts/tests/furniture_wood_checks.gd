extends RefCounted
## Run this unchanged in the frozen predecessor: absent finish bindings fail normally.
## GPU appearance is reviewed separately in the same close views before and after.
const FINISH: String = "res://shaders/furniture_wood.gdshader"
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("FURNITURE_WOOD", label, ok, detail)

func parameter(material: Material, key: String, fallback: Variant = null) -> Variant:
	if not finished(material): return fallback
	for declaration: Dictionary in (material as ShaderMaterial).shader.get_shader_uniform_list():
		if str(declaration.name) == key:
			var value: Variant = (material as ShaderMaterial).get_shader_parameter(key)
			return value if value != null else fallback
	return fallback

func finished(material: Material) -> bool:
	return material is ShaderMaterial and (material as ShaderMaterial).shader != null and (material as ShaderMaterial).shader.resource_path == FINISH

func models(ids: Array[String]) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in main.world.find_children("*", "Node3D", true, false):
		if str(node.get_meta("model_id", "")) in ids: found.append(node as Node3D)
	return found

func timber_coverage(ids: Array[String], minimum: int) -> Dictionary:
	var roots: Array[Node3D] = models(ids)
	var errors: Array[String] = []
	var samples: int = 0
	for root: Node3D in roots:
		var local_count: int = 0
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
			for surface: int in mesh.mesh.get_surface_count():
				var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if source == null: continue
				var role: String = source.resource_name.to_lower()
				if not (role.contains("wood") or role.contains("cedar") or role.contains("oak")): continue
				local_count += 1
				samples += 1
				var material: Material = mesh.get_active_material(surface)
				if not finished(material): errors.append(str(mesh.get_path()) + "/" + role)
				if root.get_meta("model_id", "") in ["P_cafe_table", "P_reading_chair"]:
					var tone: Color = parameter(material, "finish_tint", Color.WHITE)
					var dark: bool = role.contains("dark")
					if not bool(parameter(material, "has_finish_tint", false)) or (tone.r > .55 if dark else tone.r < .70 or tone.r > .80): errors.append(str(mesh.get_path()) + " lost warm-top/dark-frame colour hierarchy")
		if local_count == 0: errors.append(str(root.get_path()) + " no measurable timber")
	return {"ok": roots.size() >= minimum and samples > 0 and errors.is_empty(), "models": roots.size(), "surfaces": samples, "errors": errors}

func run() -> void:
	for entry: Array in [
		["both shop counters retain timber with local polish", ["I04_shop_counter"], 2],
		["the cafe tables include their actual chair timber", ["P_cafe_table"], 2],
		["all nine existing outdoor benches keep their aged boards", ["A12_bench"], 9],
		["the potting bench retains refined working timber", ["P08"], 1],
		["the market stall finishes only its cedar frame and serving counter", ["P09"], 1],
		["the public reading chairs and shared table have a quiet used finish", ["P_reading_chair", "P_community_table"], 3],
		["the real community handwork table retains its oak and joinery", ["W13_cedar_worktable"], 1],
	]:
		var ids: Array[String] = []
		ids.assign(entry[1])
		var coverage: Dictionary = timber_coverage(ids, int(entry[2]))
		check(str(entry[0]), bool(coverage.ok), str(coverage))
	var rooms: Dictionary = main.world.interiors
	var procedural: Array[String] = []
	var profiles: Dictionary = {}
	for pair: Array in [["toolshed", "DirtyWorkBench", 2], ["zakka", "RepairWorkbench", 2], ["post", "PostalCounter", 0], ["home_haru", "FamilyLowTable", 1], ["photo_room", "PhotoComparisonDesk", 1], ["library", "MapReadingDesk", 1]]:
		var room: Node3D = rooms.get(str(pair[0])) as Node3D
		var board: MeshInstance3D = room.find_child(str(pair[1]), true, false) as MeshInstance3D if room != null else null
		if board == null or not finished(board.material_override): procedural.append(str(pair[1]) + " missing finished top")
		else: profiles[str(pair[1])] = int(parameter(board.material_override, "use_profile", -1))
		if board != null and int(parameter(board.material_override, "use_profile", -1)) != int(pair[2]): procedural.append(str(pair[1]) + " wrong purpose")
	check("resident workshop, post and family furniture use their actual distinct purposes", procedural.is_empty() and profiles.size() == 6, str({"profiles": profiles, "errors": procedural}))
	var textures: Array[String] = []
	var matrices: Array[String] = []
	var components: Array[String] = []
	var restrained: Array[String] = []
	var bindings: int = 0
	var preserved_images: int = 0
	var preserved_fallback_grains: int = 0
	var transformed: int = 0
	var top_board: bool = false
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(main):
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface)
			if not finished(material): continue
			bindings += 1
			var shader_material: ShaderMaterial = material as ShaderMaterial
			var label: String = str(mesh.get_path()) + " surface%d" % surface
			var source: StandardMaterial3D = shader_material.get_meta("furniture_source_material", null) as StandardMaterial3D
			if source == null:
				textures.append(label + " missing original material")
			else:
				if source.albedo_texture != null:
					preserved_images += 1
					if parameter(material, "albedo_tex") != source.albedo_texture: textures.append(label + " replaced diffuse image")
				elif source.resource_name.to_lower().contains("oak"):
					preserved_fallback_grains += 1
					if parameter(material, "grain_tex") != SurfaceFinish.GRAIN or absf(float(parameter(material, "grain_strength", 0.)) - 1.0) > .00001: textures.append(label + " lost authored oak fallback grain or contrast")
				if parameter(material, "uv_scale") != Vector2(source.uv1_scale.x, source.uv1_scale.y) or parameter(material, "uv_offset") != Vector2(source.uv1_offset.x, source.uv1_offset.y): textures.append(label + " changed source UV mapping")
				if parameter(material, "base_color") != source.albedo_color: textures.append(label + " replaced source tint")
			var value: Variant = parameter(material, "wood_transform")
			var root: Node3D = instance_from_id(int(shader_material.get_meta("furniture_model_root", 0))) as Node3D
			if not value is Projection or root == null:
				matrices.append(label + " no actual Projection/root")
			else:
				var actual: Projection = value as Projection
				var expected := Projection(root.global_transform.affine_inverse() * mesh.global_transform)
				var error: float = 0.
				var identity_error: float = 0.
				for column: int in 4:
					for row: int in 4:
						error = maxf(error, absf(actual[column][row] - expected[column][row]))
						identity_error = maxf(identity_error, absf(expected[column][row] - Projection.IDENTITY[column][row]))
				if identity_error > .000001: transformed += 1
				var local: Vector3 = mesh.get_aabb().get_center() + mesh.get_aabb().size * Vector3(.13, .07, -.19)
				var mapped: Vector4 = actual * Vector4(local.x, local.y, local.z, 1.)
				var target: Vector3 = root.to_local(mesh.to_global(local))
				if error > .00001 or Vector3(mapped.x, mapped.y, mapped.z).distance_to(target) > .0002 or absf(mapped.w - 1.) > .00001: matrices.append(label + " incorrect wood space")
			var minima: PackedVector4Array = parameter(material, "component_min", PackedVector4Array())
			var maxima: PackedVector4Array = parameter(material, "component_max", PackedVector4Array())
			var count: int = int(parameter(material, "component_count", 0))
			if count < 1 or count != minima.size() or count != maxima.size(): components.append(label + " no per-board bounds")
			for index: int in mini(minima.size(), maxima.size()):
				var extent: Vector4 = maxima[index] - minima[index]
				if extent.x < -.0001 or extent.y < -.0001 or extent.z < -.0001: components.append(label + " reversed board")
				if root != null and root.get_meta("model_id", "") == "P08" and extent.x > 2.5 and extent.z > 1.2 and extent.y > .07 and extent.y < .09: top_board = true
			var wear: float = float(parameter(material, "wear_strength", 0.))
			var sheen: float = float(parameter(material, "sheen_strength", 0.))
			if wear <= 0. or wear > .65 or sheen <= 0. or sheen > .5: restrained.append(label + " unbounded finish")
	check("finished timber preserves original images, UVs and untextured oak fallback grain", bindings > 30 and preserved_images > 15 and preserved_fallback_grains > 1 and textures.is_empty(), str({"bindings": bindings, "images": preserved_images, "oak_fallbacks": preserved_fallback_grains, "errors": textures}))
	check("every wood mat4 is a real Projection matching all16 root-space elements and points", bindings > 30 and transformed > 0 and matrices.is_empty(), str({"bindings": bindings, "nonidentity": transformed, "errors": matrices}))
	check("joined wooden parts carry individual bounds including the measured80mm potting top", bindings > 30 and components.is_empty() and top_board, str({"potting_top": top_board, "errors": components}))
	check("all finish intensities stay within restrained anime material limits", bindings > 30 and restrained.is_empty(), str(restrained))
	var nonwood: Array[String] = []
	var skipped: int = 0
	for root: Node3D in models(["I04_shop_counter", "I02_cake_showcase", "P_reading_chair", "P_coffee_station", "P09"]):
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
			for surface: int in mesh.mesh.get_surface_count():
				var source: Material = mesh.mesh.surface_get_material(surface)
				if source == null: continue
				var role: String = source.resource_name.to_lower()
				if role.contains("wood") or role.contains("cedar") or role.contains("oak"): continue
				skipped += 1
				if finished(mesh.get_active_material(surface)): nonwood.append(str(mesh.get_path()) + "/" + role)
	check("actual glass, seat fabric, canvas and appliance metal never receive the timber shader", skipped > 10 and nonwood.is_empty(), str({"nonwood_surfaces": skipped, "errors": nonwood}))
	var atlas: Array[String] = []
	var atlas_count: int = 0
	var atlas_extras: int = 0
	for root: Node3D in models(["J03_dining_set", "J05_dish_cabinet", "G07_hall_cabinet", "I03_bookshelf"]):
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
			for surface: int in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_active_material(surface)
				var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				# The live home adds KitchenMemo/Board below J05 after spawning.
				# Its paper is an override on an unmaterialled BoxMesh, not the GLB atlas.
				if source == null or source.albedo_texture == null or not source.resource_name.begins_with("M_" + str(root.get_meta("model_id", ""))):
					atlas_extras += 1
					if finished(material): atlas.append(str(mesh.get_path()) + " non-atlas addition was painted as timber")
					continue
				atlas_count += 1
				if not finished(material) or int(parameter(material, "atlas_mode", 0)) < 1: atlas.append(str(root.get_path()) + " missing mixed-image protection")
	check("old mixed-atlas furniture retains a selective timber mask while added paper stays separate", atlas_count > 5 and atlas_extras > 0 and atlas.is_empty(), str({"atlas_surfaces": atlas_count, "non_atlas_additions": atlas_extras, "errors": atlas}))
	var workroom: Node3D = rooms.get("workroom") as Node3D
	var tea: MeshInstance3D = workroom.find_child("NeighbourTeaStation", true, false) as MeshInstance3D if workroom != null else null
	var leg: MeshInstance3D = workroom.find_child("NeighbourTeaStationLeg_*", true, false) as MeshInstance3D if workroom != null else null
	check("procedural tea furniture keeps a used tabletop and quiet structural legs", tea != null and leg != null and finished(tea.material_override) and finished(leg.material_override) and not bool(parameter(tea.material_override, "structural", true)) and bool(parameter(leg.material_override, "structural", false)))
	var shader: Shader = load(FINISH) as Shader if ResourceLoader.exists(FINISH) else null
	check("the actual wood shader carries direct and weak real-environment satin reflection", shader != null and shader.code.contains("SPECULAR_LIGHT +=") and shader.code.contains("LIGHT + VIEW") and shader.code.contains("finish_polish * sheen_strength") and shader.code.contains("SPECULAR = clamp(sheen_strength * finish_polish * environment_sheen") and not shader.code.contains("EMISSION"))
	grain_and_contact_checks()
	await fixture_checks()

func grain_and_contact_checks() -> void:
	var grain_errors: Array[String] = []
	var grain_samples: int = 0
	var with_original_image: int = 0
	for grain_root: Node3D in models(["P_cafe_table", "P_reading_chair", "W13_cedar_worktable"]):
		for grain_mesh: MeshInstance3D in WorldBuilder.find_meshes(grain_root):
			for grain_surface: int in grain_mesh.mesh.get_surface_count():
				var source: StandardMaterial3D = grain_mesh.mesh.surface_get_material(grain_surface) as StandardMaterial3D
				if source == null: continue
				var role: String = source.resource_name.to_lower()
				if not (role.contains("cedar") or role.contains("oak")): continue
				grain_samples += 1
				if source.albedo_texture != null: with_original_image += 1
				var grain_material: Material = grain_mesh.get_active_material(grain_surface)
				if parameter(grain_material, "grain_tex") != SurfaceFinish.GRAIN or absf(float(parameter(grain_material, "grain_strength", 0.)) - 1.) > .00001 or not bool(parameter(grain_material, "has_finish_tint", false)):
					grain_errors.append(str(grain_mesh.get_path()) + " lost the existing game grain layer")
	check("cafe and reader retain the actual game grain even when their GLB has a separate image", grain_samples > 30 and with_original_image > 20 and grain_errors.is_empty(), str({"surfaces": grain_samples, "with_GLB_image": with_original_image, "errors": grain_errors}))
	var contact_errors: Array[String] = []
	var seen: Dictionary = {}
	var contact_samples: int = 0
	var matte_samples: int = 0
	# These are measured model parts, not arbitrary ratio fixtures. In particular
	# the real armrest is55x55x510mm and must not fail a min(width,depth) test.
	var expected: Dictionary = {"RoundTop":true, "ChairLeftSeat":true, "ChairRightSeat":true, "ChairLeftBack":false, "ChairRightBack":false, "Foot":false, "Pedestal":false, "ReadingChairArm":true, "ReadingChairArm_001":true}
	for contact_root: Node3D in models(["P_cafe_table", "P_reading_chair"]):
		for contact_mesh: MeshInstance3D in WorldBuilder.find_meshes(contact_root):
			var label: String = str(contact_mesh.name)
			if not expected.has(label): continue
			seen[label] = true
			for contact_surface: int in contact_mesh.mesh.get_surface_count():
				var contact_material: Material = contact_mesh.get_active_material(contact_surface)
				var maxima: PackedVector4Array = parameter(contact_material, "component_max", PackedVector4Array())
				var horizontal: bool = false
				for part: Vector4 in maxima: horizontal = horizontal or part.w > .5
				var receives_polish: bool = horizontal and not bool(parameter(contact_material, "structural", true))
				if bool(expected[label]): contact_samples += 1
				else: matte_samples += 1
				if maxima.is_empty() or receives_polish != bool(expected[label]): contact_errors.append(str(contact_mesh.get_path()) + " incorrectly classified contact surface")
				var ambient: float = float(parameter(contact_material, "environment_sheen", 0.))
				if ambient <= 0. or ambient > .25: contact_errors.append(str(contact_mesh.get_path()) + " lacks bounded real-environment reflection")
	check("real round tops, seats and narrow armrests catch light while backs and dark bases stay matte", seen.size() == expected.size() and contact_samples > 5 and matte_samples > 5 and contact_errors.is_empty(), str({"seen":seen.keys(), "contact":contact_samples, "matte":matte_samples, "errors":contact_errors}))

func fixture_checks() -> void:
	var available: bool = ResourceLoader.exists("res://scripts/world/furniture_wood_finish.gd")
	var api: Script = load("res://scripts/world/furniture_wood_finish.gd") as Script if available else null
	var holder := Node3D.new()
	main.add_child(holder)
	holder.visible = false
	var scene: PackedScene = WorldBuilder.model_scene("P_cafe_table")
	var cafe: Node3D = scene.instantiate() as Node3D
	holder.add_child(cafe)
	cafe.position = Vector3(2, 1, -3)
	cafe.rotation.y = .37
	var before: Dictionary = {}
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(cafe): before[mesh.get_instance_id()] = mesh.mesh.get_faces().duplicate()
	if api != null: api.call("apply", cafe, "P_cafe_table")
	var geometry: bool = api != null
	var identity: Dictionary = {}
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(cafe):
		geometry = geometry and before.get(mesh.get_instance_id()) == mesh.mesh.get_faces()
		for surface: int in mesh.mesh.get_surface_count(): identity["%d/%d" % [mesh.get_instance_id(), surface]] = mesh.get_active_material(surface)
	check("finishing a transformed real cafe model leaves vertices and support geometry unchanged", geometry)
	if api != null: api.call("apply", cafe, "P_cafe_table")
	var stable: bool = api != null
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(cafe):
		for surface: int in mesh.mesh.get_surface_count(): stable = stable and identity["%d/%d" % [mesh.get_instance_id(), surface]] == mesh.get_active_material(surface)
	check("reapplying furniture finish reuses the active material without accumulating passes", stable)
	var glass := MeshInstance3D.new()
	var box := BoxMesh.new()
	var clear := StandardMaterial3D.new()
	clear.resource_name = "WoodenCabinetGlass"
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.albedo_color = Color(1, .8, .5, .2)
	box.material = clear
	glass.mesh = box
	holder.add_child(glass)
	if api != null: api.call("apply", glass, "I04_shop_counter")
	check("even a warm-tinted transparent material with wood in its name stays transparent", glass.get_active_material(0) == clear and not finished(glass.get_active_material(0)))
	holder.queue_free()
	await t.frames(1)
