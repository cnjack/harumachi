extends Node
## Authoring-only sampler. Samples one flat floor; no gameplay saves or POC clips.
const NATURAL = preload("res://scripts/characters/natural_locomotion_pose.gd")
const SUPPORT = preload("res://scripts/characters/character_foot_support.gd")
var settings: Dictionary

func _ready() -> void:
	_run.call_deferred()

func _poses(sk: Skeleton3D) -> Dictionary:
	var result: Dictionary = {}
	for index: int in sk.get_bone_count():
		var p: Vector3 = sk.get_bone_pose_position(index)
		var q: Quaternion = sk.get_bone_pose_rotation(index)
		var s: Vector3 = sk.get_bone_pose_scale(index)
		result[sk.get_bone_name(index)] = {"translation":[p.x,p.y,p.z],"rotation":[q.x,q.y,q.z,q.w],"scale":[s.x,s.y,s.z]}
	return result

func _run() -> void:
	var config: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--config="): config = arg.trim_prefix("--config=")
	assert(not config.is_empty())
	settings = JSON.parse_string(FileAccess.get_file_as_string(config)) as Dictionary
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,.2,100)
	collision.shape = box
	collision.position.y = -.1
	floor_body.add_child(collision)
	get_tree().root.add_child(floor_body)
	for actor_id: String in settings.actors:
		var holder := Node3D.new()
		get_tree().root.add_child(holder)
		var source_path: String = str(settings.get("source_dir","res://assets/models")).path_join("CH_"+actor_id+".glb")
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(source_path,state) == OK)
		var model: Node3D = document.generate_scene(state,960.0,false,false) as Node3D
		holder.add_child(model)
		var sk: Skeleton3D = model.find_child("Skeleton3D",true,false) as Skeleton3D
		var ap: AnimationPlayer = model.find_child("AnimationPlayer",true,false) as AnimationPlayer
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var support: SkeletonModifier3D = SUPPORT.attach(model,ap)
		support.active = false
		SUPPORT.town_patches.clear()
		SUPPORT.town_curbs.clear()
		var natural: SkeletonModifier3D = NATURAL.attach(model,ap)
		natural.active = false
		# Run arm style stays in the game for this source-leg/neutral-pose batch.
		natural.set("running_arms_enabled",false)
		natural.set("running_hand_style_enabled",false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		ap.play("idle",0)
		ap.seek(0,true)
		ap.advance(0)
		natural.call("_remember",sk)
		var clips: Dictionary = {}
		for clip: String in settings.actors[actor_id]:
			var animation: Animation = ap.get_animation(clip)
			var rows: Array[Dictionary] = []
			var count: int = ceili(animation.length*120.0)
			for sample: int in count+1:
				var at: float = animation.length*float(sample)/count
				ap.play(clip,0)
				ap.seek(minf(at,animation.length-0.0001),true)
				ap.advance(0)
				sk.force_update_all_bone_transforms()
				var before: Dictionary = _poses(sk)
				natural.call("reset_contact")
				natural.call("_process_pose")
				if actor_id == "kazuko" and clip == "run":
					natural.call("_kazuko_running_recovery",sk,float(settings.get("extra_heel_recovery_m",0.0)),float(settings.get("extra_recovery_settle_end",1.0)))
				sk.force_update_all_bone_transforms()
				rows.append({"time":at,"evaluation_time":minf(at,animation.length-0.0001),"before":before,"after":_poses(sk)})
			clips[clip] = {"duration":animation.length,"rows":rows}
		var destination: String = str(settings.output).path_join(actor_id+"-native-source.json")
		var file := FileAccess.open(destination,FileAccess.WRITE)
		file.store_string(JSON.stringify({"actor":actor_id,"clips":clips,"floor_y":0,"fps":120,"terrain_baked":false,"running_arm_style_baked":false,"source_sha256":FileAccess.get_sha256(source_path)}))
		file.close()
		print("SOURCE_FOUNDATION_EXPORT ",actor_id)
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
