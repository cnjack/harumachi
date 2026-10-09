class_name FishingPose
extends SkeletonModifier3D
var phase:=0.0
var amount:=0.0
var reel:=0.0

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton:=get_skeleton()
	if skeleton==null:return
	for spec: Array in [["upper.R",Vector3.RIGHT,-.70],["fore.R",Vector3.RIGHT,-.82],["upper.L",Vector3.RIGHT,-.45],["fore.L",Vector3.RIGHT,-.76],["chest",Vector3.RIGHT,.08]]:
		var bone: int=skeleton.find_bone(str(spec[0]))
		if bone<0:continue
		var angle: float=float(spec[2])*amount
		if str(spec[0])=="fore.R":angle+=sin(phase*4.6)*.12*reel
		var original: Quaternion=skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone,original*Quaternion(spec[1],angle))
