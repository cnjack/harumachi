extends Node
## Offline source authoring only. No character controller, foot IK or natural pose.
## The existing bounded contact tool supplies values; the GLB stores the result.
const CONTACT = preload("res://scripts/characters/character_garment_support.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var config_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--config="): config_path = argument.trim_prefix("--config=")
	assert(not config_path.is_empty())
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config_path)) as Dictionary
	for actor_id: String in config.actors:
		var holder := Node3D.new()
		add_child(holder)
		var source_path: String = str(config.source_dir).path_join("CH_" + actor_id + ".glb")
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(source_path, state) == OK)
		var model: Node3D = document.generate_scene(state, 960.0, false, false) as Node3D
		holder.add_child(model)
		var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
		var animation: AnimationPlayer = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var rig: Node = model.find_child("Rig", true, false)
		var profile: Dictionary = (rig.get_meta("extras") as Dictionary).get("garment_local_clearance", {})
		var contact: SkeletonModifier3D = CONTACT.new()
		contact.name = "OfflineSourceGarmentContact"
		skeleton.add_child(contact)
		contact.call("prepare", model, profile)
		contact.set("margin", float(config.get("authoring_margin_m", profile.get("clearance_margin_m", .006))))
		# Execute explicitly after each exact source sample. No process callback
		# may race the writer or apply an earlier solver result.
		contact.active = false
		var mesh: MeshInstance3D = contact.get("mesh") as MeshInstance3D
		assert(mesh != null)
		var indices: PackedInt32Array = contact.get("local_indices")
		var names: Array[String] = []
		for index: int in indices: names.append(str(mesh.mesh.get_blend_shape_name(index)))
		assert(names.size() == 96)
		var clips: Dictionary = {}
		for clip: String in config.actors[actor_id]:
			var resource: Animation = animation.get_animation(clip)
			var rows: Array[Dictionary] = []
			var count: int = int(config.get("phase_samples", 128))
			for sample: int in count + 1:
				var at: float = resource.length * float(sample) / count
				var evaluated: float = at if sample < count else 0.0
				animation.play(clip, 0.0)
				animation.seek(evaluated, true)
				animation.advance(0.0)
				skeleton.force_update_all_bone_transforms()
				contact.call("_process_modification")
				var values: Array[float] = []
				for index: int in indices: values.append(mesh.get_blend_shape_value(index))
				rows.append({"time": at, "evaluation_time": evaluated, "weights": values})
			clips[clip] = {"duration": resource.length, "rows": rows}
			print("SOURCE_GARMENT_CLIP ", actor_id, " ", clip, " ", rows.size())
		var output_path: String = str(config.output).path_join(actor_id + "-source-garment.json")
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"actor": actor_id, "source_sha256": FileAccess.get_sha256(source_path), "local_names": names, "clips": clips, "authoring_margin_m": contact.get("margin"), "scope": "Exact source AP samples with only offline garment contact; no Natural, FootSupport, controller, transitions or terrain", "performance": contact.call("performance")}))
		file.close()
		holder.free()
		await get_tree().process_frame
	get_tree().quit(0)
