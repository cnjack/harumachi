extends SkeletonModifier3D
## Anatomy-specific corrections on existing clips; mesh, weights and gestures stay intact.
var model: Node3D
var actor: Node3D
var animation: AnimationPlayer
var profile: String=""
var rebuilt_clips: Array=[]
var authored_walk_knee_plane:=false
var source_foundation: Dictionary={}
var references: Dictionary={}
var reference_hips:=Vector3.ZERO
var ready_reference:=false
var last_position:=Vector3.INF
var last_phase: float=-1.0
var anchors: Dictionary={}
var was_stance: Dictionary={}
var corrections: Dictionary={}
const NAMES: Array[String]=["hips","chest","thigh.L","thigh.R","shin.L","shin.R","upper.L","upper.R"]
const TRANSITION_BONES: Array[String]=["hips","chest","head","thigh.L","thigh.R","shin.L","shin.R","foot.L","foot.R","upper.L","upper.R","fore.L","fore.R","hand.L","hand.R"]
var _last_delta: Dictionary={}
var _blend_from: Dictionary={}
var _transition_clip: String=""
var _observed_clip: String=""
var _transition_elapsed: float=0.0
var _transition_duration: float=0.0
var _transition_frame: int=-1
var _pose_actor_position:=Vector3.INF
# Run-only style correction; the switch is used by final-pose A/B audits.
var running_arms_enabled:=true
var running_hand_style_enabled:=true
# Source pitch min/max, desired pitch min/max, elbow at forward/backward peak.
# These are per-character art targets for a relaxed run, not anatomy limits.
const RUN_ARM_STYLE: Dictionary={
 "sora":[-29.0,39.0,-21.0,26.0,74.0,86.0],
 "ren":[-26.96,36.96,-19.0,24.0,74.0,85.0],
 "haru":[-55.9,17.8,-31.0,19.0,76.0,86.0],
 "mio":[-24.92,34.92,-21.0,26.0,76.0,86.0],
 "aoi":[-32.4,42.4,-24.0,27.0,78.0,88.0],
 "tanaka":[-20.16,30.16,-18.0,26.0,78.0,86.0],
 "kazuko":[-24.24,34.24,-21.0,26.0,76.0,86.0]
}
# Maximum inward Hand correction at the forward stroke, left/right degrees.
# Preserve Mio's already inward left fist and Tanaka's coat clearance; these
# are small style changes, not a common wrist pose or a new finger curl.
const RUN_HAND_STYLE: Dictionary={
 "sora":[14.0,14.0],"ren":[16.0,13.0],"haru":[5.0,8.0],
 "mio":[0.0,12.0],"aoi":[5.0,16.0],"tanaka":[15.0,15.0],
 "kazuko":[5.0,8.0]
}
var qa_trace_enabled:=false
var qa_trace: Dictionary={}
const GAIT_MATCH_WEIGHTS: Dictionary={"hips":.25,"thigh.L":2.0,"thigh.R":2.0,"shin.L":1.0,"shin.R":1.0,"foot.L":.25,"foot.R":.25}
const GAIT_MATCH_SAMPLES:=64
const NORMALIZED_GAIT_DIRECTIONS: Dictionary={"haru":["walk","run"],"mio":["walk"],"aoi":["walk"]}
var _gait_phase_cache: Dictionary={}
var _last_raw_pose: Dictionary={}
var _last_phase_match: Dictionary={}

func _prepare_phase_cache() -> void:
 # Read interpolation tracks directly once. Never seek/play the live skeleton,
 # and never skin a mesh while finding a locomotion entry phase.
 var sk: Skeleton3D=get_skeleton()
 var wanted: Dictionary={}
 for name: String in GAIT_MATCH_WEIGHTS:
  var bone: int=LivingPose.bone(sk,name)
  if bone>=0:wanted[bone]=float(GAIT_MATCH_WEIGHTS[name])
 for clip_name: String in ["walk","run"]:
  if not animation.has_animation(clip_name):continue
  var resource: Animation=animation.get_animation(clip_name)
  var tracks: Dictionary={}
  for track: int in resource.get_track_count():
   if resource.track_get_type(track)!=Animation.TYPE_ROTATION_3D:continue
   var path: NodePath=resource.track_get_path(track)
   if path.get_subname_count()==0:continue
   var label: String=str(path.get_subname(0))
   var track_bone: int=sk.find_bone(label)
   if track_bone<0:track_bone=sk.find_bone(label.replace("mixamorig:","mixamorig_"))
   if wanted.has(track_bone):tracks[track_bone]=track
  # A partial match could choose the wrong contact leg. Fall back to the
  # normalized phase if this imported resource lacks a required bone track.
  if tracks.size()!=wanted.size() or wanted.size()!=GAIT_MATCH_WEIGHTS.size():continue
  var entries: Array[Dictionary]=[]
  for sample: int in GAIT_MATCH_SAMPLES:
   var phase: float=float(sample)/GAIT_MATCH_SAMPLES
   var rotations: Dictionary={}
   for sampled_bone: int in tracks:rotations[sampled_bone]=resource.rotation_track_interpolate(int(tracks[sampled_bone]),phase*resource.length).normalized()
   entries.append({"phase":phase,"rotations":rotations})
  _gait_phase_cache[clip_name]={"entries":entries,"weights":wanted}

func match_gait_phase(next_clip: String,fallback_phase: float) -> float:
 # Native A/B exposed regressions in these directions despite a lower local
 # rotation cost. Preserve their preceding normalized phase instead.
 if next_clip in NORMALIZED_GAIT_DIRECTIONS.get(profile,[]):
  _last_phase_match={"from_clip":animation.current_animation,"to_clip":next_clip,"normalized_phase":fallback_phase,"matched_phase":fallback_phase,"cache_samples":0,"fallback_reason":"normalized direction retained after native A/B"}
  return fallback_phase
 if not _gait_phase_cache.has(next_clip) or _last_raw_pose.is_empty():
  _last_phase_match={"to_clip":next_clip,"normalized_phase":fallback_phase,"matched_phase":fallback_phase,"cache_samples":0,"fallback_reason":"missing complete animation tracks or preceding raw pose"}
  return fallback_phase
 var cache: Dictionary=_gait_phase_cache[next_clip]
 var entries: Array=cache.entries
 var best_phase: float=fallback_phase
 var best_cost:=INF
 for entry: Dictionary in entries:
  var cost:=0.0
  for index: int in cache.weights:
   if not _last_raw_pose.has(index):return fallback_phase
   var source: Quaternion=_last_raw_pose[index].rotation
   var target: Quaternion=entry.rotations[index]
   var angle: float=2.0*acos(clampf(absf(source.dot(target)),0.0,1.0))
   cost+=float(cache.weights[index])*angle*angle
  # Only break essentially equal pose ties by the preceding cycle position.
  var separation: float=absf(float(entry.phase)-fallback_phase)
  var cycle_distance: float=minf(separation,1.0-separation)
  var best_separation: float=absf(best_phase-fallback_phase)
  if cost<best_cost-.000001 or (absf(cost-best_cost)<=.000001 and cycle_distance<minf(best_separation,1.0-best_separation)):
   best_cost=cost;best_phase=float(entry.phase)
 _last_phase_match={"from_clip":animation.current_animation,"to_clip":next_clip,"normalized_phase":fallback_phase,"matched_phase":best_phase,"angular_cost":best_cost,"cache_samples":entries.size()}
 return best_phase

func begin_transition(next_clip: String,duration: float) -> void:
 _transition_clip=next_clip
 _blend_from=_last_delta.duplicate(true)
 _transition_elapsed=0.0
 _transition_frame=Engine.get_process_frames()
 # A placement can clear correction history while AnimationPlayer still has
 # its preceding clip. Keep the same blend clock even without old deltas;
 # zero correction is the starting pose, not proof that the AP blend ended.
 _transition_duration=maxf(duration,0.0)

func finish_transition() -> void:
 # Frozen pose audits seek directly and ask for the steady result. Real
 # CharAnim playback uses begin_transition and never calls this method.
 _transition_duration=0.0
 _blend_from.clear()

func _local_poses(sk: Skeleton3D) -> Dictionary:
 var poses: Dictionary={}
 for name: String in TRANSITION_BONES:
  var index: int=LivingPose.bone(sk,name)
  if index>=0:poses[index]={"position":sk.get_bone_pose_position(index),"rotation":sk.get_bone_pose_rotation(index)}
 return poses

func _pose_deltas(sk: Skeleton3D,raw: Dictionary) -> Dictionary:
 var deltas: Dictionary={}
 for index: int in raw:
  var base: Dictionary=raw[index]
  deltas[index]={"position":sk.get_bone_pose_position(index)-(base.position as Vector3),"rotation":(base.rotation as Quaternion).inverse()*sk.get_bone_pose_rotation(index)}
 return deltas

func _apply_deltas(sk: Skeleton3D,raw: Dictionary,deltas: Dictionary) -> void:
 for index: int in raw:
  var base: Dictionary=raw[index]
  var delta: Dictionary=deltas.get(index,{"position":Vector3.ZERO,"rotation":Quaternion.IDENTITY})
  sk.set_bone_pose_position(index,(base.position as Vector3)+(delta.position as Vector3))
  sk.set_bone_pose_rotation(index,((base.rotation as Quaternion)*(delta.rotation as Quaternion)).normalized())

func _qa_joints(sk: Skeleton3D) -> Dictionary:
 var result: Dictionary={}
 for name: String in ["hips","foot.L","foot.R"]:
  var index: int=LivingPose.bone(sk,name)
  if index<0:continue
  var point: Vector3=sk.to_global(sk.get_bone_global_pose(index).origin)
  result[name]=[point.x,point.y,point.z]
 return result

func _process_modification() -> void:
 if model==null or animation==null or not model.is_visible_in_tree():return
 var at: Vector3=actor.global_position
 # NPC.place/set_home reset explicitly. Player/world teleports can arrive
 # through interpolation resets; discard local correction history on a real
 # discontinuity, with a delta-scaled bound well above any walking/running speed.
 if _pose_actor_position.is_finite() and _pose_actor_position.distance_to(at)>maxf(.5,get_process_delta_time()*12.0):reset_contact()
 _pose_actor_position=at
 if actor is Player and (actor as Player).seated or actor.get_meta("resident_seated",false):
  finish_transition();_last_delta.clear();return
 var sk: Skeleton3D=get_skeleton()
 var raw: Dictionary=_local_poses(sk)
 _last_raw_pose=raw
 var clip: String=animation.current_animation
 if qa_trace_enabled:qa_trace={"frame":Engine.get_process_frames(),"clip":clip,"clip_time":animation.current_animation_position,"before":_qa_joints(sk),"transition_elapsed":_transition_elapsed,"transition_duration":_transition_duration,"process_delta_s":get_process_delta_time()}
 if qa_trace_enabled:qa_trace["phase_match"]=_last_phase_match.duplicate()
 if clip=="":
  # A completed one-shot can expose an empty clip for one process frame
  # before the controller starts idle. Keep the last correction on that pose.
  _apply_deltas(sk,raw,_last_delta)
  if qa_trace_enabled:qa_trace["after"]=_qa_joints(sk)
  return
 if clip!=_observed_clip:
  if clip!=_transition_clip:finish_transition()
  _observed_clip=clip
 _process_pose()
 if qa_trace_enabled:
  qa_trace["desired"]=_qa_joints(sk);qa_trace["corrections"]=corrections.duplicate()
  qa_trace["contact_anchors_active"]={"L":anchors.has("L"),"R":anchors.has("R")}
 var desired: Dictionary=_pose_deltas(sk,raw)
 if _transition_duration>0 and _transition_frame!=Engine.get_process_frames():
  # AnimationPlayer consumes its blend clock at abs(speed_scale)*delta.
  # Follow that same clock, including pause/time_scale and cadence changes.
  _transition_elapsed+=get_process_delta_time()*absf(animation.speed_scale)
  _transition_frame=Engine.get_process_frames()
 if _transition_duration>0 and _transition_elapsed<_transition_duration:
  var weight: float=clampf(_transition_elapsed/_transition_duration,0.0,1.0)
  # Smooth correction deltas, alongside AnimationPlayer's source-pose blend.
  # Local rotations preserve bone lengths; FootSupport still owns floor safety.
  weight=weight*weight*(3.0-2.0*weight)
  var blended: Dictionary={}
  for index: int in raw:
   var previous: Dictionary=_blend_from.get(index,{"position":Vector3.ZERO,"rotation":Quaternion.IDENTITY})
   var target: Dictionary=desired[index]
   blended[index]={"position":(previous.position as Vector3).lerp(target.position as Vector3,weight),"rotation":(previous.rotation as Quaternion).slerp(target.rotation as Quaternion,weight)}
  _apply_deltas(sk,raw,blended)
  _last_delta=blended
 else:
  _last_delta=desired
  _transition_duration=0.0
 if qa_trace_enabled:qa_trace["after"]=_qa_joints(sk)

func reset_contact() -> void:
 anchors.clear();was_stance.clear();corrections.clear();last_phase=-1.0;last_position=Vector3.INF
 finish_transition()
 _last_delta.clear();_transition_clip="";_observed_clip=""
 _last_raw_pose.clear();_last_phase_match.clear()
 _transition_elapsed=0.0;_transition_frame=-1;_pose_actor_position=Vector3.INF

static func attach(source: Node3D,player: AnimationPlayer) -> SkeletonModifier3D:
 var rig: Node=source.find_child("Rig",true,false)
 var extras: Dictionary=rig.get_meta("extras",{}) if rig!=null else {}
 var who: String=str(extras.get("character_id",""))
 if who not in ["sora","ren","haru","mio","aoi","tanaka","kazuko"]:return null
 var sk: Skeleton3D=source.find_child("Skeleton3D",true,false) as Skeleton3D
 if sk==null:return null
 var modifier: SkeletonModifier3D=load("res://scripts/characters/natural_locomotion_pose.gd").new()
 modifier.set("rebuilt_clips",(extras.get("locomotion_rebuild",{}) as Dictionary).get("rebuilt_clips",[]))
 modifier.set("source_foundation",extras.get("source_pose_foundation",{}))
 modifier.set("authored_walk_knee_plane",bool((extras.get("leg_foundation",{}) as Dictionary).get("walk_knee_plane_authored",false)))
 modifier.name="NaturalLocomotionPose";modifier.set("model",source);modifier.set("actor",source.get_parent());modifier.set("animation",player);modifier.set("profile",who)
 var actor_root: Node3D=source
 while actor_root.get_parent() is Node3D and not(actor_root is Player or actor_root is NPC):actor_root=actor_root.get_parent() as Node3D
 modifier.set("actor",actor_root)
 sk.add_child(modifier)
 modifier.call("_prepare_phase_cache")
 return modifier

func _remember(sk: Skeleton3D) -> void:
 for name: String in NAMES:
  var index: int=LivingPose.bone(sk,name)
  if index>=0:references[name]=sk.get_bone_pose_rotation(index)
 var hips: int=LivingPose.bone(sk,"hips")
 reference_hips=sk.get_bone_pose_position(hips)
 ready_reference=true

func _soften(sk: Skeleton3D,name: String,amount: float) -> void:
 var index: int=LivingPose.bone(sk,name)
 if index>=0 and references.has(name):sk.set_bone_pose_rotation(index,(references[name] as Quaternion).slerp(sk.get_bone_pose_rotation(index),amount))

func _aim(sk: Skeleton3D,joint: int,end: int,target: Vector3) -> void:
 var pose: Transform3D=sk.get_bone_global_pose(joint)
 var current: Vector3=sk.get_bone_global_pose(end).origin-pose.origin
 if current.length_squared()<.000001 or target.length_squared()<.000001:return
 pose.basis=Basis(Quaternion(current.normalized(),target.normalized()))*pose.basis
 sk.set_bone_global_pose(joint,pose)

func _place_ankle(sk: Skeleton3D,side: String,target: Vector3,pole_outward: float=.08) -> void:
 var thigh: int=LivingPose.bone(sk,"thigh."+side);var shin: int=LivingPose.bone(sk,"shin."+side);var foot: int=LivingPose.bone(sk,"foot."+side)
 if mini(thigh,mini(shin,foot))<0:return
 var hip: Vector3=sk.to_global(sk.get_bone_global_pose(thigh).origin)
 var knee: Vector3=sk.to_global(sk.get_bone_global_pose(shin).origin)
 var ankle: Vector3=sk.to_global(sk.get_bone_global_pose(foot).origin)
 var foot_basis: Basis=sk.get_bone_global_pose(foot).basis
 var upper: float=hip.distance_to(knee);var lower: float=knee.distance_to(ankle)
 if minf(upper,lower)<.001:return
 var direction: Vector3=(target-hip).normalized()
 var reach: float=clampf(target.distance_to(hip),absf(upper-lower)+.0001,upper+lower-.0001)
 var along: float=(upper*upper-lower*lower+reach*reach)/(2.0*reach)
 var bend: float=sqrt(maxf(0.0,upper*upper-along*along))
 var pole: Vector3=model.global_basis.z+model.global_basis.x*(pole_outward if side=="L" else -pole_outward)
 pole-=direction*pole.dot(direction)
 if pole.length_squared()<.000001:return
 var goal: Vector3=hip+direction*along+pole.normalized()*bend
 _aim(sk,thigh,shin,sk.global_basis.inverse()*(goal-hip))
 var new_knee: Vector3=sk.to_global(sk.get_bone_global_pose(shin).origin)
 _aim(sk,shin,foot,sk.global_basis.inverse()*(target-new_knee))
 var pose: Transform3D=sk.get_bone_global_pose(foot);pose.basis=foot_basis;sk.set_bone_global_pose(foot,pose)

func _ground_gap(sk: Skeleton3D,side: String,support: Node,prepared_points: Array=[]) -> float:
 var foot: int=LivingPose.bone(sk,"foot."+side)
 var floor: Dictionary=support.call("floor_below",sk.to_global(sk.get_bone_global_pose(foot).origin))
 if floor.is_empty() or (floor.normal as Vector3).y<.5:return INF
 var gap: float=INF
 var points: Array=prepared_points if not prepared_points.is_empty() else support.call("points",sk,side)
 for point: Vector3 in points:
  var plane_gap: float=(floor.normal as Vector3).dot(point-(floor.position as Vector3))/(floor.normal as Vector3).y
  var painted: float=support.call("visible_town_height",Vector2(point.x,point.z))
  if is_finite(painted):plane_gap=minf(plane_gap,point.y-painted)
  gap=minf(gap,plane_gap)
 return gap

func _tanaka_arm_clearance(sk: Skeleton3D,clip: String) -> void:
 if clip not in ["idle","walk","wave","bow","stretch"]:return
 var weight: float=1.0
 if clip=="stretch":
  var phase: float=clampf(animation.current_animation_position/maxf(animation.current_animation_length,.001),0.0,1.0)
  weight=1.0-smoothstep(0.0,.2,phase)+smoothstep(.85,1.0,phase)
 var upper: int=LivingPose.bone(sk,"upper.L")
 if upper<0 or weight<=0.0:return
 # Only the left upper arm was buried beside the coat. Leave the already
 # qualified run, right arm and local forearm/hand articulation untouched.
 var pose: Transform3D=sk.get_bone_global_pose(upper)
 var axis: Vector3=(sk.global_basis.inverse()*model.global_basis.z).normalized()
 pose.basis=Basis(axis,deg_to_rad(14.0)*weight)*pose.basis
 sk.set_bone_global_pose(upper,pose)

func _kazuko_running_recovery(sk: Skeleton3D,recovery_lift: float=.20,settle_end: float=1.0) -> void:
 var phase: float=fposmod(animation.current_animation_position/maxf(animation.current_animation_length,.001),1.0)
 for side: String in ["L","R"]:
  var leg_phase: float=fposmod(phase+(0.0 if side=="L" else .5),1.0)
  # Keep the planted path and fore/aft foot timing. Recover the heel upwards
  # so the knee lifts forward without forcing the whole thigh into the apron.
  if leg_phase<=.28:continue
  var pulse: float=pow(sin(PI*(leg_phase-.28)/.72),2.0)
  # Settle the heel during the last quarter before the next plant. Holding
  # it high into late swing folds the thigh against the apron boundary.
  # Earlier knee lift and the planted path remain unchanged.
  pulse*=pow(1.0-smoothstep(.75,settle_end,leg_phase),2.0)
  if pulse<.000001:continue
  var foot: int=LivingPose.bone(sk,"foot."+side)
  if foot<0:continue
  var target: Vector3=sk.to_global(sk.get_bone_global_pose(foot).origin)
  target+=Vector3.UP*(recovery_lift*pulse)
  _place_ankle(sk,side,target,.035)

func _relaxed_running_arms(sk: Skeleton3D) -> void:
 if not running_arms_enabled or not RUN_ARM_STYLE.has(profile):return
 var style: Array=RUN_ARM_STYLE[profile]
 var to_model: Basis=model.global_basis.inverse()*sk.global_basis
 var to_skeleton: Basis=to_model.inverse()
 for side: String in ["L","R"]:
  var upper: int=LivingPose.bone(sk,"upper."+side)
  var fore: int=LivingPose.bone(sk,"fore."+side)
  var hand: int=LivingPose.bone(sk,"hand."+side)
  if mini(upper,mini(fore,hand))<0:continue
  var shoulder: Vector3=sk.get_bone_global_pose(upper).origin
  var elbow: Vector3=sk.get_bone_global_pose(fore).origin
  var original: Vector3=to_model*(elbow-shoulder)
  if original.length_squared()<.000001:continue
  var pitch: float=rad_to_deg(atan2(original.z,-original.y))
  # Map the actual authored pitch, preserving each arm's phase, including
  # Haru's original clip. Rotating around model X retains lateral clearance.
  var forward: float=clampf((pitch-float(style[0]))/(float(style[1])-float(style[0])),0.0,1.0)
  var desired: float=lerpf(float(style[2]),float(style[3]),forward)
  var target: Vector3=original.rotated(Vector3.RIGHT,deg_to_rad(pitch-desired))
  _aim(sk,upper,fore,to_skeleton*target)
  shoulder=sk.get_bone_global_pose(upper).origin
  elbow=sk.get_bone_global_pose(fore).origin
  var wrist: Vector3=sk.get_bone_global_pose(hand).origin
  var upper_direction: Vector3=elbow-shoulder
  var fore_direction: Vector3=wrist-elbow
  var hinge: Vector3=upper_direction.cross(fore_direction)
  if hinge.length_squared()<.000001:continue
  var flex: float=acos(clampf(upper_direction.normalized().dot(fore_direction.normalized()),-1.0,1.0))
  var relaxed_flex: float=deg_to_rad(lerpf(float(style[5]),float(style[4]),forward))
  # Keep the measured three-dimensional bend plane. In particular, Tanaka's
  # two arms have different authored clearance and must not be sagittalized.
  var pose: Transform3D=sk.get_bone_global_pose(fore)
  pose.basis=Basis(hinge.normalized(),relaxed_flex-flex)*pose.basis
  sk.set_bone_global_pose(fore,pose)
  if profile=="tanaka" and side=="L":
   # Lowering the recovering hand exposes a coat crossing not seen by the
   # paired-volume query. Keep a small measured clearance for this whole chain.
   var clearance: Transform3D=sk.get_bone_global_pose(upper)
   var outward_axis: Vector3=(sk.global_basis.inverse()*model.global_basis.z).normalized()
   clearance.basis=Basis(outward_axis,deg_to_rad(3.0))*clearance.basis
   sk.set_bone_global_pose(upper,clearance)
  # All finger local transforms retain the qualified source shape.

func _running_hand_style(sk: Skeleton3D) -> void:
 if not running_hand_style_enabled or not RUN_HAND_STYLE.has(profile):return
 var chest: int=LivingPose.bone(sk,"chest")
 if chest<0:return
 var arm_style: Array=RUN_ARM_STYLE[profile]
 var hand_style: Array=RUN_HAND_STYLE[profile]
 var to_model: Basis=model.global_basis.inverse()*sk.global_basis
 for side_index: int in range(2):
  var side: String="L" if side_index==0 else "R"
  var imported_side: String="Left" if side_index==0 else "Right"
  var upper: int=LivingPose.bone(sk,"upper."+side)
  var fore: int=LivingPose.bone(sk,"fore."+side)
  var hand: int=LivingPose.bone(sk,"hand."+side)
  if mini(upper,mini(fore,hand))<0:continue
  var wrist: Vector3=sk.get_bone_global_pose(hand).origin
  var elbow: Vector3=sk.get_bone_global_pose(fore).origin
  var fore_direction: Vector3=wrist-elbow
  if fore_direction.length_squared()<.000001:continue
  fore_direction=fore_direction.normalized()
  var knuckles:=Vector3.ZERO
  var count:=0
  for finger: String in ["Index","Middle","Ring","Pinky"]:
   var knuckle: int=LivingPose.bone(sk,imported_side+"Hand"+finger+"1")
   if knuckle>=0:
    knuckles+=sk.get_bone_global_pose(knuckle).origin
    count+=1
  if count!=4:continue
  var fist_direction: Vector3=knuckles/float(count)-wrist
  var inward: Vector3=sk.get_bone_global_pose(chest).origin-wrist
  inward-=fore_direction*inward.dot(fore_direction)
  if fist_direction.length_squared()<.000001 or inward.length_squared()<.000001:continue
  fist_direction=fist_direction.normalized();inward=inward.normalized()
  # Correct only deviation in the forearm/chest plane. Preserve the other
  # authored component and palm roll; a universal local X/Y axis would not.
  var deviation: float=atan2(fist_direction.dot(inward),fist_direction.dot(fore_direction))
  var correction: float=clampf(deg_to_rad(3.0)-deviation,0.0,deg_to_rad(float(hand_style[side_index])))
  var upper_direction: Vector3=to_model*(elbow-sk.get_bone_global_pose(upper).origin)
  var pitch: float=rad_to_deg(atan2(upper_direction.z,-upper_direction.y))
  var range_start: int=2 if running_arms_enabled else 0
  var forward: float=clampf((pitch-float(arm_style[range_start]))/(float(arm_style[range_start+1])-float(arm_style[range_start])),0.0,1.0)
  correction*=smoothstep(.15,.85,forward)
  if correction<.000001:continue
  # Rotate about the existing wrist. Elbow/wrist paths and finger local TRS
  # stay unchanged, and the backward stroke returns to its source hand pose.
  var pose: Transform3D=sk.get_bone_global_pose(hand)
  pose.basis=Basis(fore_direction.cross(inward).normalized(),correction)*pose.basis
  sk.set_bone_global_pose(hand,pose)

func _process_pose() -> void:
 corrections.clear()
 if model==null or animation==null or not model.is_visible_in_tree():return
 var clip: String=animation.current_animation
 var sk: Skeleton3D=get_skeleton()
 if profile=="tanaka" and not bool(source_foundation.get("tanaka_arm",false)):_tanaka_arm_clearance(sk,clip)
 if clip=="run":
  _relaxed_running_arms(sk)
  _running_hand_style(sk)
 # User-rejected neutral legs share the same pose in idle, wave and bow. The
 # former safety IK raised ankles under a fixed low pelvis and chose the old
 # knee plane, which made straight legs bow sideways or bend behind the calf.
 if bool(source_foundation.get("standing",false)) and clip in ["idle","talk","wave","bow","look","stretch","cheer"]:
  return
 if profile in ["sora","ren","aoi","tanaka","kazuko"] and clip in ["idle","talk","wave","bow","look","stretch","cheer"]:
  _standing_support(sk)
  return
 if profile in ["sora","kazuko"] and clip=="walk":
  if authored_walk_knee_plane or bool(source_foundation.get("walk",false)):
   # The source GLB now owns its bend plane. Ground/terrain assistance runs
   # separately; do not replace the authored leg pose on every walking frame.
   anchors.clear();was_stance.clear();last_phase=-1.0;last_position=actor.global_position
   return
  # The old walk bends sideways; ground support then amplifies that inward
  # knee pole. Reorient the two-bone bend at the unchanged authored ankle,
  # preserving segment lengths, foot orientation, pelvis and upper-body motion.
  for side: String in ["L","R"]:
   var foot: int=LivingPose.bone(sk,"foot."+side)
   if foot>=0:_place_ankle(sk,side,sk.to_global(sk.get_bone_global_pose(foot).origin),.02 if profile=="kazuko" else .08)
  anchors.clear();was_stance.clear();last_phase=-1.0;last_position=actor.global_position
  return
 if profile=="kazuko" and clip=="run":
  if not bool(source_foundation.get("kazuko_run",false)):_kazuko_running_recovery(sk)
  anchors.clear();was_stance.clear();last_phase=-1.0;last_position=actor.global_position
  return
 if clip in rebuilt_clips:
  anchors.clear();was_stance.clear();last_phase=-1.0;last_position=actor.global_position
  return
 if not ready_reference:
  if clip=="idle":_remember(sk)
  else:return
 if (clip=="walk" and bool(source_foundation.get("walk",false))) or (clip=="idle" and bool(source_foundation.get("idle",false))):return
 var active_walk: bool=profile=="mio" and clip=="walk"
 var active_idle: bool=(profile in ["mio","aoi"] and clip=="idle") or (profile=="aoi" and clip=="talk")
 if not active_walk and not active_idle:
  anchors.clear();was_stance.clear();last_phase=-1.0;last_position=actor.global_position;return
 var phase: float=fposmod(animation.current_animation_position/maxf(animation.current_animation_length,.001),1.0)
 var moved: float=0.0 if not last_position.is_finite() else last_position.distance_to(actor.global_position)
 var actual_motion: bool=moved>.0001 and moved<.35 and actor.has_method("is_moving") and bool(actor.call("is_moving"))
 if moved>=.35 or (last_phase>=0.0 and absf(phase-last_phase)>.20 and not(last_phase>.85 and phase<.15)):
  anchors.clear();was_stance.clear()
 last_position=actor.global_position;last_phase=phase
 var hips: int=LivingPose.bone(sk,"hips")
 if active_walk:
  for name: String in ["thigh.L","thigh.R"]:_soften(sk,name,.85)
  for name: String in ["shin.L","shin.R"]:_soften(sk,name,.78)
  for name: String in ["upper.L","upper.R"]:_soften(sk,name,.68)
  _soften(sk,"hips",.65);_soften(sk,"chest",.70)
  var position: Vector3=sk.get_bone_pose_position(hips)
  position.x=lerpf(reference_hips.x,position.x,.55);position.y=lerpf(reference_hips.y,position.y,.72)
  sk.set_bone_pose_position(hips,position)
 else:
  var idle_position: Vector3=sk.get_bone_pose_position(hips);idle_position.y-=.002 if profile=="mio" else .006;sk.set_bone_pose_position(hips,idle_position)
  var head: int=LivingPose.bone(sk,"head")
  if head>=0 and profile=="aoi" and clip=="idle":sk.set_bone_pose_rotation(head,sk.get_bone_pose_rotation(head)*Quaternion(Vector3.UP,sin(phase*TAU)*.04))
 var support: Node=sk.get_node_or_null("CharacterFootSupport")
 for side: String in ["L","R"]:
  var foot: int=LivingPose.bone(sk,"foot."+side)
  var ankle: Vector3=sk.to_global(sk.get_bone_global_pose(foot).origin)
  var local: Vector3=model.to_local(ankle)
  var width: float=.085 if active_walk or profile=="mio" else .075
  local.x=lerpf(local.x,width if side=="L" else -width,.82 if active_walk else 1.0)
  var target: Vector3=model.to_global(local)
  var stance: bool=active_idle or (phase<.5 if side=="L" else phase>=.5)
  if active_walk and stance and actual_motion:
   if not bool(was_stance.get(side,false)) or not anchors.has(side):
    # Incoming walk can still contain a high outgoing run swing while the
    # AnimationPlayer blends. A phase label alone is not physical contact:
    # pinning that airborne point keeps the ankle unreachable for half a
    # cycle, then releases it abruptly at the stance boundary.
    var observed_gap: float=_ground_gap(sk,side,support) if support!=null else INF
    if qa_trace_enabled:
     if not qa_trace.has("contact_observations"):qa_trace["contact_observations"]={}
     qa_trace["contact_observations"][side]=observed_gap if is_finite(observed_gap) else null
    if is_finite(observed_gap) and observed_gap<=.020:anchors[side]=target
   if anchors.has(side):
    target.x=(anchors[side] as Vector3).x;target.z=(anchors[side] as Vector3).z
  elif not stance or not actual_motion:anchors.erase(side)
  was_stance[side]=stance
  _place_ankle(sk,side,target)
  if stance and support!=null:
   var gap: float=_ground_gap(sk,side,support)
   if is_finite(gap):
    var rise: float=clampf(.008-gap,-.12,.12);target.y+=rise;_place_ankle(sk,side,target);corrections[side]=rise
    var remaining: float=_ground_gap(sk,side,support)
    if active_walk and is_finite(remaining) and remaining>.011:
     # A narrower, gentler stride can need a few millimetres of pelvis drop
     # before the planted ankle is reachable. Do not leave both shoes afloat.
     var hip_pose: Transform3D=sk.get_bone_global_pose(hips)
     hip_pose.origin-=sk.global_basis.inverse()*Vector3.UP*minf(remaining-.008,.035)
     sk.set_bone_global_pose(hips,hip_pose)
     _place_ankle(sk,side,target)
 sk.set_meta("natural_locomotion_profile",profile)


func _standing_pelvis_height(sk: Skeleton3D,targets: Dictionary) -> float:
 var hips: int=LivingPose.bone(sk,"hips")
 var root_world: Vector3=sk.to_global(sk.get_bone_global_pose(hips).origin)
 var hip_height: float=INF
 for side: String in ["L","R"]:
  var thigh: int=LivingPose.bone(sk,"thigh."+side)
  var shin: int=LivingPose.bone(sk,"shin."+side)
  var foot: int=LivingPose.bone(sk,"foot."+side)
  var hip: Vector3=sk.to_global(sk.get_bone_global_pose(thigh).origin)
  var knee: Vector3=sk.to_global(sk.get_bone_global_pose(shin).origin)
  var ankle: Vector3=sk.to_global(sk.get_bone_global_pose(foot).origin)
  var target: Vector3=targets[side]
  var upper: float=hip.distance_to(knee)
  var lower: float=knee.distance_to(ankle)
  var flex: float=deg_to_rad(12.0 if profile=="tanaka" else 9.0)
  var reach_squared: float=upper*upper+lower*lower+2.0*upper*lower*cos(flex)
  var horizontal_squared: float=Vector2(target.x-hip.x,target.z-hip.z).length_squared()
  var vertical: float=sqrt(maxf(.002,reach_squared-horizontal_squared))
  hip_height=minf(hip_height,target.y+vertical-(hip.y-root_world.y))
 return hip_height

func _standing_place(sk: Skeleton3D,targets: Dictionary) -> void:
 var hips: int=LivingPose.bone(sk,"hips")
 var height: float=_standing_pelvis_height(sk,targets)
 var root: Transform3D=sk.get_bone_global_pose(hips)
 var root_world: Vector3=sk.to_global(root.origin)
 root_world.y=height
 root.origin=sk.to_local(root_world)
 sk.set_bone_global_pose(hips,root)
 for side: String in ["L","R"]:_place_ankle(sk,side,targets[side])

func _standing_support(sk: Skeleton3D) -> void:
 # These five IDs were flagged by the human review. Haru/Mio's accepted
 # standing actions are deliberately outside this correction.
 if actor is Player and (actor as Player).seated or actor.get_meta("resident_seated",false):return
 var support: Node=sk.get_node_or_null("CharacterFootSupport")
 if support==null:return
 var hips: int=LivingPose.bone(sk,"hips")
 if hips<0:return
 var targets: Dictionary={}
 for side: String in ["L","R"]:
  var thigh: int=LivingPose.bone(sk,"thigh."+side)
  var shin: int=LivingPose.bone(sk,"shin."+side)
  var foot: int=LivingPose.bone(sk,"foot."+side)
  if mini(thigh,mini(shin,foot))<0:return
  var ankle: Vector3=sk.to_global(sk.get_bone_global_pose(foot).origin)
  var local: Vector3=model.to_local(ankle)
  var rest_hip: Vector3=sk.get_bone_global_rest(thigh).origin
  var half_width: float=clampf(absf(rest_hip.x)*.75,.073,.102)
  var shoe_min_x: float=INF
  var shoe_max_x: float=-INF
  var shoe_points: Array=support.call("points",sk,side)
  for shoe_point: Vector3 in shoe_points:
   var shoe_x: float=model.to_local(shoe_point).x
   shoe_min_x=minf(shoe_min_x,shoe_x)
   shoe_max_x=maxf(shoe_max_x,shoe_x)
  var shoe_centre_x: float=(shoe_min_x+shoe_max_x)*.5 if is_finite(shoe_min_x) else local.x
  # A fitted ankle pivot can be off-centre inside the boot. Move the complete
  # shoe to the stance track, retaining that measured pivot-to-surface offset.
  local.x+=(half_width if side=="L" else -half_width)-shoe_centre_x
  var target: Vector3=model.to_global(local)
  var gap: float=_ground_gap(sk,side,support,shoe_points)
  if is_finite(gap):target.y+=clampf(.008-gap,-.16,.16)
  targets[side]=target
 _standing_place(sk,targets)
 # A few millimetres of weighted-sole calibration can consume all the slack
 # of a nearly straight leg. Recompute pelvis height as well as both ankles;
 # do not extend a foot under a pelvis fixed for the preceding target.
 for _iteration: int in range(2):
  var changed: bool=false
  for planted_side: String in ["L","R"]:
   var final_gap: float=_ground_gap(sk,planted_side,support)
   if is_finite(final_gap) and absf(final_gap-.008)>.0003:
    var adjusted_target: Vector3=targets[planted_side]
    adjusted_target.y+=clampf(.008-final_gap,-.025,.025)
    targets[planted_side]=adjusted_target
    corrections[planted_side]=.008-final_gap
    changed=true
  if not changed:break
  _standing_place(sk,targets)
 sk.set_meta("natural_locomotion_profile",profile)
