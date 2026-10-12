extends SkeletonModifier3D
## Anatomy-specific corrections on existing clips; mesh, weights and gestures stay intact.
var model: Node3D
var actor: Node3D
var animation: AnimationPlayer
var profile: String=""
var references: Dictionary={}
var reference_hips:=Vector3.ZERO
var ready_reference:=false
var last_position:=Vector3.INF
var last_phase: float=-1.0
var anchors: Dictionary={}
var was_stance: Dictionary={}
var corrections: Dictionary={}
const NAMES: Array[String]=["hips","chest","thigh.L","thigh.R","shin.L","shin.R","upper.L","upper.R"]

func reset_contact() -> void:
 anchors.clear();was_stance.clear();corrections.clear();last_phase=-1.0;last_position=Vector3.INF

static func attach(source: Node3D,player: AnimationPlayer) -> SkeletonModifier3D:
 var rig: Node=source.find_child("Rig",true,false)
 var extras: Dictionary=rig.get_meta("extras",{}) if rig!=null else {}
 var who: String=str(extras.get("character_id",""))
 if who not in ["mio","aoi"]:return null
 var sk: Skeleton3D=source.find_child("Skeleton3D",true,false) as Skeleton3D
 if sk==null:return null
 var modifier: SkeletonModifier3D=load("res://scripts/characters/natural_locomotion_pose.gd").new()
 modifier.name="NaturalLocomotionPose";modifier.set("model",source);modifier.set("actor",source.get_parent());modifier.set("animation",player);modifier.set("profile",who)
 sk.add_child(modifier)
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

func _place_ankle(sk: Skeleton3D,side: String,target: Vector3) -> void:
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
 var pole: Vector3=model.global_basis.z+model.global_basis.x*(.08 if side=="L" else -.08)
 pole-=direction*pole.dot(direction)
 if pole.length_squared()<.000001:return
 var goal: Vector3=hip+direction*along+pole.normalized()*bend
 _aim(sk,thigh,shin,sk.global_basis.inverse()*(goal-hip))
 var new_knee: Vector3=sk.to_global(sk.get_bone_global_pose(shin).origin)
 _aim(sk,shin,foot,sk.global_basis.inverse()*(target-new_knee))
 var pose: Transform3D=sk.get_bone_global_pose(foot);pose.basis=foot_basis;sk.set_bone_global_pose(foot,pose)

func _ground_gap(sk: Skeleton3D,side: String,support: Node) -> float:
 var foot: int=LivingPose.bone(sk,"foot."+side)
 var floor: Dictionary=support.call("floor_below",sk.to_global(sk.get_bone_global_pose(foot).origin))
 if floor.is_empty() or (floor.normal as Vector3).y<.5:return INF
 var gap: float=INF
 var points: Array=support.call("points",sk,side)
 for point: Vector3 in points:
  var plane_gap: float=(floor.normal as Vector3).dot(point-(floor.position as Vector3))/(floor.normal as Vector3).y
  var painted: float=support.call("visible_town_height",Vector2(point.x,point.z))
  if is_finite(painted):plane_gap=minf(plane_gap,point.y-painted)
  gap=minf(gap,plane_gap)
 return gap

func _process_modification() -> void:
 corrections.clear()
 if model==null or animation==null or not model.is_visible_in_tree():return
 var clip: String=animation.current_animation
 var sk: Skeleton3D=get_skeleton()
 if not ready_reference:
  if clip=="idle":_remember(sk)
  else:return
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
   if not bool(was_stance.get(side,false)) or not anchors.has(side):anchors[side]=target
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
