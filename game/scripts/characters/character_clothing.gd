class_name CharacterClothing
extends RefCounted
## Local secondary motion shared by the player and NPCs; driven by GLB rig metadata.
const Follower=preload("res://scripts/characters/sleeve_follower.gd")
const Limiter=preload("res://scripts/characters/sleeve_limiter.gd")
var simulator: SpringBoneSimulator3D
var limiter: SkeletonModifier3D

static func _bone(sk: Skeleton3D,name: String) -> int:
	var index: int=sk.find_bone(name)
	if index<0:index=sk.find_bone(name.replace(":","_"))
	return index

static func attach(model: Node) -> CharacterClothing:
	var controller: CharacterClothing=CharacterClothing.new()
	var rig: Node=model.find_child("Rig",true,false)
	if rig==null or not rig.has_meta("extras"):return controller
	var extras: Dictionary=rig.get_meta("extras")
	var profile: Dictionary=extras.get("character_clothing",{})
	if profile.is_empty():return controller
	var skeleton: Skeleton3D=model.find_child("Skeleton3D",true,false) as Skeleton3D
	if skeleton==null:return controller
	if skeleton.has_node("CharacterSleeveSpring"):return controller
	skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	var follower: SkeletonModifier3D=Follower.new();follower.name="CharacterSleeveFollower";skeleton.add_child(follower)
	var spring: SpringBoneSimulator3D=SpringBoneSimulator3D.new();spring.name="CharacterSleeveSpring";skeleton.add_child(spring)
	var chains: Array=profile.get("spring_chains",[]);spring.setting_count=chains.size()
	for index: int in range(chains.size()):
		var chain: Dictionary=chains[index]
		var first: int=_bone(skeleton,str(chain.root));var last: int=_bone(skeleton,str(chain.end))
		if first<0 or last<0:continue
		spring.set_root_bone(index,first);spring.set_end_bone(index,last)
		spring.set_stiffness(index,12.0);spring.set_drag(index,.70);spring.set_gravity(index,.30)
		spring.set_gravity_direction(index,Vector3.DOWN);spring.set_radius(index,.008)
		spring.set_enable_all_child_collisions(index,true)
	var collisions: Array[Dictionary]=[]
	var sleeves: Dictionary=profile.get("sleeves",{})
	for side: String in ["Left","Right"]:
		for segment: String in ["Arm","ForeArm"]:
			var bone: int=_bone(skeleton,"mixamorig:"+side+segment)
			var next: int=_bone(skeleton,"mixamorig:"+side+("ForeArm" if segment=="Arm" else "Hand"))
			if bone<0 or next<0:continue
			var height: float=skeleton.get_bone_global_rest(bone).origin.distance_to(skeleton.get_bone_global_rest(next).origin)
			var collision: SpringBoneCollisionCapsule3D=SpringBoneCollisionCapsule3D.new()
			collision.name="SleeveBody_%s_%s" % [side,segment]
			collision.radius=float((sleeves.get(side,{}) as Dictionary).get("skin_radius",.02))*.90
			collision.height=maxf(height,.06);spring.add_child(collision)
			collisions.append({"node":collision,"bone":bone,"height":height})
	follower.set("colliders",collisions)
	var limit: SkeletonModifier3D=Limiter.new();limit.name="CharacterSleeveLimit";skeleton.add_child(limit)
	limit.set("angle_limit",deg_to_rad(12.0));controller.simulator=spring;controller.limiter=limit
	spring.reset()
	return controller

func reset() -> void:
	if is_instance_valid(simulator):simulator.reset()
