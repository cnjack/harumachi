class_name CharAnim
extends RefCounted
## Drives the "idle" / "walk" / "run" clips baked into the rigged character GLBs (art/tools/rig_char.py).
## Playback follows measured stride speed. Rebuilt clips are authored for real game
## speeds; legacy clips retain their existing playback range.
## Callers keep their procedural bob when the model has no AnimationPlayer (valid() == false).

const BLEND := 0.22
const REBUILT_WALK_RUN_ENTER := 1.35
const REBUILT_WALK_RUN_EXIT := 1.20
const HAND_TONE = preload("res://scripts/characters/character_hand_tone.gd")
const FOOT_SUPPORT = preload("res://scripts/characters/character_foot_support.gd")
const APRON_SUPPORT = preload("res://scripts/characters/character_apron_support.gd")
const NATURAL_POSE = preload("res://scripts/characters/natural_locomotion_pose.gd")

## Emitted at each heel strike of the walk / run clips (clip phases 0 and 0.5), for footsteps.
signal stepped

var clothing: CharacterClothing
var ap: AnimationPlayer
var walk_speed := 1.45   # ground speed (m/s) at which each clip plays at 1x; read from the rig's glTF extras
var run_speed := 2.4
var run_above := 2.85    # switch walk -> run above this speed
var rebuilt_clips: Array=[]
var _natural_pose: SkeletonModifier3D
var _foot_support: SkeletonModifier3D
var _pending_gesture := ""
var _pending_gesture_scale := 1.0
var _pending_gesture_loop := false
var _idle_gesture_hold := false
var _state := ""
var _prev_ph := -1.0
var idle_clip := "idle"   # the standing loop: idle, tend (crouched over plants) or talk
var _oneshot := ""        # a gesture playing once (wave, bow, look, stretch, cheer)


func _init(model: Node) -> void:
	if model == null:
		return
	_filter_materials(model)
	HAND_TONE.apply(model)
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null or not ap.has_animation("walk") or not ap.has_animation("idle"):
		ap = null
		return
	var rig := model.find_child("Rig", true, false)
	if rig and rig.has_meta("extras"):
		var ex: Dictionary = rig.get_meta("extras")
		walk_speed = float(ex.get("walk_speed", walk_speed))
		run_speed = float(ex.get("run_speed", run_speed))
		rebuilt_clips=(ex.get("locomotion_rebuild",{}) as Dictionary).get("rebuilt_clips",[])
	for n in ["walk", "run", "idle", "tend", "talk", "dance"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in ["wave", "bow", "look", "stretch", "cheer"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_NONE
	var natural: SkeletonModifier3D=NATURAL_POSE.attach(model as Node3D,ap)
	_natural_pose=natural
	if natural!=null and str(natural.get("profile"))=="mio" and "walk" not in rebuilt_clips:walk_speed*=.85
	clothing = CharacterClothing.attach(model)
	_foot_support = FOOT_SUPPORT.attach(model as Node3D, ap)
	APRON_SUPPORT.attach(model as Node3D, ap)
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
	_pending_gesture = ""
	_pending_gesture_loop = false
	_idle_gesture_hold = false
	if clip in ["wave", "bow"] and _foot_support != null and bool(_foot_support.call("prepare_gesture_pose")):
		_go("idle", 1.0)
		_oneshot = clip
		_pending_gesture = clip
		_pending_gesture_scale = scale
		return true
	if _foot_support != null: _foot_support.call("release_gesture_pose")
	_start_oneshot(clip, scale)
	return true


func _start_oneshot(clip: String, scale: float) -> void:
	_oneshot = clip
	_state = clip
	if _natural_pose!=null:_natural_pose.call("begin_transition",clip,BLEND)
	ap.play(clip, BLEND)
	if clothing: clothing.reset()
	ap.speed_scale = scale


func busy() -> bool:
	return _oneshot != "" or _pending_gesture != ""


func set_idle(clip: String, interrupt: bool = false) -> void:
	idle_clip = clip if has(clip) else "idle"
	if idle_clip not in ["wave", "bow"]: _idle_gesture_hold = false
	if _pending_gesture_loop and _pending_gesture != idle_clip:
		_pending_gesture = ""
		_pending_gesture_loop = false
		_oneshot = ""
		if _foot_support != null: _foot_support.call("release_gesture_pose")
	if interrupt and ap != null:
		_pending_gesture = ""
		_pending_gesture_loop = false
		_oneshot = ""
		if _foot_support != null: _foot_support.call("release_gesture_pose")
		if idle_clip in ["wave", "bow"]:
			play_once(idle_clip)
			_pending_gesture_loop = _pending_gesture != ""
			_idle_gesture_hold = _pending_gesture_loop
		else:
			_go(idle_clip, 1.0)


func update(speed: float) -> void:
	if ap == null:
		return
	# Explicit controller fixture/reset writes to _oneshot also cancel a
	# deferred request; it must not reappear when processing resumes.
	if _pending_gesture != "" and _oneshot != _pending_gesture:
		_pending_gesture = ""
		_pending_gesture_loop = false
		if _foot_support != null: _foot_support.call("release_gesture_pose")
	if _pending_gesture != "" and (_foot_support == null or not bool(_foot_support.call("gesture_request_active"))):
		_pending_gesture = ""
		_pending_gesture_loop = false
		_oneshot = ""
	if _pending_gesture != "":
		if speed >= .25:
			_pending_gesture = ""
			_pending_gesture_loop = false
			if _foot_support != null: _foot_support.call("release_gesture_pose")
		else:
			_go("idle", 1.0)
			if _foot_support != null and bool(_foot_support.call("gesture_pose_ready")):
				var clip: String = _pending_gesture
				var scale: float = _pending_gesture_scale
				_pending_gesture = ""
				_pending_gesture_loop = false
				_foot_support.call("hold_gesture_pose")
				_start_oneshot(clip, scale)
			return
	if speed >= .25 and _foot_support != null: _foot_support.call("release_gesture_pose")
	# A persistent standing gesture can outlive its first one-shot. If a
	# turn/placement invalidated its hold, acquire a fresh standing context.
	if _idle_gesture_hold and _oneshot == idle_clip and _foot_support != null and not bool(_foot_support.call("gesture_pose_held")):
		_oneshot = ""
	if _oneshot != "":
		if speed >= 0.25 or ap.current_animation != _oneshot or not ap.is_playing():
			_oneshot = ""
		else:
			return
	if speed < 0.25:
		if idle_clip in ["wave", "bow"] and _foot_support != null:
			if bool(_foot_support.call("gesture_pose_held")):
				_idle_gesture_hold = true
			elif _state != idle_clip or _idle_gesture_hold:
				_foot_support.call("release_gesture_pose")
				play_once(idle_clip)
				_pending_gesture_loop = _pending_gesture != ""
				# Seated/disabled support can decline preparation. Preserve
				# pure AP fallback playback without retrying it every frame.
				_idle_gesture_hold = _pending_gesture_loop
				return
		_go(idle_clip, 1.0)
	elif speed > _run_threshold() and ap.has_animation("run"):
		_go("run", speed / run_speed if "run" in rebuilt_clips else clampf(speed / run_speed, 0.8, 1.45))
	else:
		_go("walk", speed / walk_speed if "walk" in rebuilt_clips else clampf(speed / walk_speed, 0.6, 1.35))
	_check_step()


func _run_threshold() -> float:
	var threshold: float = run_above
	if "walk" in rebuilt_clips:
		# Compact walks cannot carry a child/adult at the old universal 2.85m/s
		# boundary. Enter a low-speed jog before the walk spins too quickly;
		# retain it while slowing until a natural walk cadence is reachable.
		threshold = minf(threshold, walk_speed * (REBUILT_WALK_RUN_EXIT if _state == "run" else REBUILT_WALK_RUN_ENTER))
	return threshold


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
		# Locomotion clips describe the same alternating legs. Continue their
		# cycle when changing speed: restarting at phase zero can crossfade a
		# high swing foot directly into the other clip's planted pose.
		var retain_gait_phase: bool = state in ["walk", "run"] and _state in ["walk", "run"] and ap.current_animation == _state
		var gait_phase: float = fposmod(ap.current_animation_position / maxf(ap.current_animation_length, .001), 1.0) if retain_gait_phase else 0.0
		if retain_gait_phase and _natural_pose != null: gait_phase = float(_natural_pose.call("match_gait_phase", state, gait_phase))
		if _natural_pose!=null:_natural_pose.call("begin_transition",state,BLEND)
		ap.play(state, BLEND)
		if retain_gait_phase:
			ap.seek(gait_phase * ap.get_animation(state).length, false)
			# Seeking to the matched pose is not a heel strike. Start the
			# detector at the actual new phase; subsequent crossings still emit.
			_prev_ph = fmod(ap.current_animation_position / maxf(ap.current_animation_length, .001), 1.0)
		if clothing: clothing.reset()
		_state = state
	elif state == idle_clip and state in ["wave", "bow"] and not ap.is_playing():
		# Repeat the standing gesture directly. Its existing lower-body hold
		# spans every loop, without another idle transition or a permanent busy.
		ap.play(state, 0.0)
	ap.speed_scale = scale
