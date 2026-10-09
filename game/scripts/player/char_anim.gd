class_name CharAnim
extends RefCounted
## Drives the "idle" / "walk" / "run" clips baked into the rigged character GLBs (art/tools/rig_char.py).
## Playback speed follows ground speed so the planted foot does not slide; the scale is capped so
## legs never flail, accepting a little slide at the top speeds instead.
## Callers keep their procedural bob when the model has no AnimationPlayer (valid() == false).

const BLEND := 0.22

## Emitted at each heel strike of the walk / run clips (clip phases 0 and 0.5), for footsteps.
signal stepped

var clothing: CharacterClothing
var ap: AnimationPlayer
var walk_speed := 1.45   # ground speed (m/s) at which each clip plays at 1x; read from the rig's glTF extras
var run_speed := 2.4
var run_above := 2.85    # switch walk -> run above this speed
var _state := ""
var _prev_ph := -1.0
var idle_clip := "idle"   # the standing loop: idle, tend (crouched over plants) or talk
var _oneshot := ""        # a gesture playing once (wave, bow, look, stretch, cheer)


func _init(model: Node) -> void:
	if model == null:
		return
	_filter_materials(model)
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null or not ap.has_animation("walk") or not ap.has_animation("idle"):
		ap = null
		return
	var rig := model.find_child("Rig", true, false)
	if rig and rig.has_meta("extras"):
		var ex: Dictionary = rig.get_meta("extras")
		walk_speed = float(ex.get("walk_speed", walk_speed))
		run_speed = float(ex.get("run_speed", run_speed))
	for n in ["walk", "run", "idle", "tend", "talk", "dance"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in ["wave", "bow", "look", "stretch", "cheer"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_NONE
	clothing = CharacterClothing.attach(model)
	_go("idle", 1.0)
	# desynchronise characters that share the same clips
	ap.seek(randf() * ap.get_animation("idle").length, true)


static func _filter_materials(model: Node) -> void:
	# Keep painted face/clothing detail on oblique surfaces, retaining mipmaps.
	# Duplicate shared imported materials so other model instances are untouched.
	var filtered: Dictionary = {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface: int in mesh.mesh.get_surface_count():
			var source: BaseMaterial3D = mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
				continue
			var id: int = source.get_instance_id()
			if not filtered.has(id):
				var material := source.duplicate() as BaseMaterial3D
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				filtered[id] = material
			mesh.set_surface_override_material(surface, filtered[id])


func valid() -> bool:
	return ap != null


func has(clip: String) -> bool:
	return ap != null and ap.has_animation(clip)


## Play a gesture once, then fall back to the standing loop. Walking cancels it.
func play_once(clip: String, scale: float = 1.0) -> bool:
	if not has(clip):
		return false
	_oneshot = clip
	_state = clip
	ap.play(clip, BLEND)
	if clothing: clothing.reset()
	ap.speed_scale = scale
	return true


func busy() -> bool:
	return _oneshot != ""


func set_idle(clip: String) -> void:
	idle_clip = clip if has(clip) else "idle"


func update(speed: float) -> void:
	if ap == null:
		return
	if _oneshot != "":
		if speed >= 0.25 or ap.current_animation != _oneshot or not ap.is_playing():
			_oneshot = ""
		else:
			return
	if speed < 0.25:
		_go(idle_clip, 1.0)
	elif speed > run_above and ap.has_animation("run"):
		_go("run", clampf(speed / run_speed, 0.8, 1.45))
	else:
		_go("walk", clampf(speed / walk_speed, 0.6, 1.35))
	_check_step()


func _check_step() -> void:
	if _state != "walk" and _state != "run":
		_prev_ph = -1.0
		return
	var ln := ap.current_animation_length
	if ln <= 0.0:
		return
	var ph := fmod(ap.current_animation_position / ln, 1.0)
	if _prev_ph >= 0.0 and (ph < _prev_ph or (_prev_ph < 0.5 and ph >= 0.5)):
		stepped.emit()
	_prev_ph = ph


func _go(state: String, scale: float) -> void:
	if state != _state:
		ap.play(state, BLEND)
		if clothing: clothing.reset()
		_state = state
	ap.speed_scale = scale
