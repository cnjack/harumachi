class_name HomageBuilder
extends RefCounted
## Small illustrated keepsakes among existing scenery; no new blocking collision.
static func build(world: WorldBuilder) -> void:
	var town_root := Node3D.new()
	town_root.name = "Homage_town"
	world.add_child(town_root)
	var farm_root := Node3D.new()
	farm_root.name = "Homage_farm"
	world.farm.add_child(farm_root)
	var metadata: Dictionary = {}
	if FileAccess.file_exists("res://data/homage_images.json"):
		metadata = JSON.parse_string(FileAccess.get_file_as_string("res://data/homage_images.json"))
	for entry: Dictionary in Homage.entries():
		var sprite := HomageDisplay.new()
		sprite.entry = entry
		sprite.name = "Keepsake_" + str(entry.id)
		sprite.texture = load(Homage.image_path(entry)) as Texture2D
		if sprite.texture == null:
			continue
		sprite.pixel_size = float(entry.width) / float(sprite.texture.get_width())
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.alpha_scissor_threshold = 0.25
		sprite.shaded = true
		sprite.double_sided = true
		sprite.set_meta("homage_id", str(entry.id))
		var local: Vector3 = Homage.world_position(entry)
		var info: Dictionary = metadata.get(str(entry.image), {})
		var bottom: float = float(info.get("bottom", sprite.texture.get_height()))
		local.y += (bottom - float(sprite.texture.get_height()) * 0.5) * sprite.pixel_size + 0.025
		if str(entry.id) == "egg_blue_feather":
			local.y += 0.48
		elif str(entry.id) == "egg_purple_shorts":
			local.y += 0.55
		elif str(entry.id) == "egg_cow_bell":
			local.y += 0.42
		if str(entry.region) == "farm":
			sprite.position = local - FarmBuilder.ORIGIN
			farm_root.add_child(sprite)
		else:
			sprite.position = local
			town_root.add_child(sprite)
		if str(entry.id) in ["egg_purple_shorts", "egg_cow_bell"]:
			var base: Vector3 = Homage.world_position(entry)
			var parent: Node3D = farm_root if str(entry.region) == "farm" else town_root
			if str(entry.region) == "farm":
				base -= FarmBuilder.ORIGIN
			var offsets: Array = [-0.24, 0.24] if str(entry.id) == "egg_purple_shorts" else [0.0]
			for index: int in offsets.size():
				var post := MeshInstance3D.new()
				post.name = "Support_%s_%d" % [str(entry.id), index]
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = .022
				cylinder.bottom_radius = .025
				cylinder.height = 1.10 if str(entry.id) == "egg_purple_shorts" else 0.90
				cylinder.radial_segments = 8
				post.mesh = cylinder
				post.position = base + Vector3(float(offsets[index]), cylinder.height * .5, -.015)
				var wood := StandardMaterial3D.new()
				wood.albedo_color = Color(.42, .26, .12)
				wood.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				wood.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				post.material_override = wood
				parent.add_child(post)
