extends RefCounted
## The human rig review's rejected legs and running arms, measured after every modifier.
## Run this against the original assets/runtime as a negative control: old legs/loops fail.
var t: Node
var main: Node
const REBUILT: Dictionary = {"sora":["run"],"ren":["walk","run"],"haru":[],"mio":["run"],"aoi":["walk","run"],"tanaka":["walk","run"],"kazuko":["run"]}

func _init(runner: Node) -> void:
	t=runner
	main=runner.main

func check(label: String, result: bool, detail: String="") -> void:
	t.check("CHARACTER_GAIT",label,result,detail)

func point(sample: Dictionary, name: String) -> Vector3:
	var value: Array=sample.joints[name]
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func flex(a: Vector3,b: Vector3,c: Vector3) -> float:
	return 180.0-rad_to_deg((a-b).angle_to(c-b))

func bone_world_basis(pose: Dictionary,index: int) -> Basis:
	var columns: Array=pose.bones[index].basis
	var x: Array=columns[0]
	var y: Array=columns[1]
	var z: Array=columns[2]
	return Basis(Vector3(float(x[0]),float(x[1]),float(x[2])),Vector3(float(y[0]),float(y[1]),float(y[2])),Vector3(float(z[0]),float(z[1]),float(z[2])))

func lateral_roll(pose: Dictionary,index: int,model: Node3D,sk: Skeleton3D) -> float:
	var rest_world: Basis=sk.global_basis*sk.get_bone_global_rest(index).basis
	var deformation: Basis=model.global_basis.inverse()*bone_world_basis(pose,index)*rest_world.inverse()*model.global_basis
	return rad_to_deg(atan2(-deformation.y.x,deformation.y.y))

func correlation(first: Array[float],second: Array[float]) -> float:
	if first.size()!=second.size() or first.size()<2:return 1.0
	var mean_first: float=0
	var mean_second: float=0
	for index: int in first.size():
		mean_first+=first[index]/first.size()
		mean_second+=second[index]/second.size()
	var covariance: float=0
	var variance_first: float=0
	var variance_second: float=0
	for sample_index: int in first.size():
		var a: float=first[sample_index]-mean_first
		var b: float=second[sample_index]-mean_second
		covariance+=a*b
		variance_first+=a*a
		variance_second+=b*b
	return covariance/sqrt(variance_first*variance_second) if variance_first*variance_second>.000000001 else 1.0

func sample(controller: CharAnim,clip: String,phase: float,probe: SkeletonModifier3D) -> Dictionary:
	controller.ap.play(clip,0)
	controller.ap.speed_scale=0
	var animation: Animation=controller.ap.get_animation(clip)
	var expected_time: float=animation.length*phase
	if animation.loop_mode!=Animation.LOOP_NONE:expected_time=fposmod(expected_time,animation.length)
	controller.ap.seek(expected_time,true)
	controller.ap.advance(0)
	var natural: Node=probe.get_skeleton().get_node_or_null("NaturalLocomotionPose")
	if natural!=null and natural.has_method("finish_transition"):natural.call("finish_transition")
	# Modifier callbacks run on process frames; physics ticks can repeat an old
	# snapshot in headless runs. Let the chain settle, then require an explicit
	# acknowledgement from the last modifier on a later process frame.
	for settle_frame: int in 3:await t.get_tree().process_frame
	var requested: int=probe.call("request",clip,expected_time)
	var measured: Dictionary={}
	for capture_frame: int in 8:
		await t.get_tree().process_frame
		if int(probe.get("completed_request"))!=requested:continue
		measured=(probe.get("result") as Dictionary).duplicate(true)
		if int(measured.get("request_id",-1))==requested:break
	var fresh: bool=int(measured.get("request_id",-1))==requested and str(measured.get("clip",""))==clip and absf(float(measured.get("clip_time",INF))-expected_time)<.0001 and int(measured.get("applied_frame",-1))>int(measured.get("request_frame",-1)) and bool(measured.get("measure_feet",false)) and bool(measured.get("measure_bones",false))
	measured["fresh"]=fresh
	if fresh:
		print("GAIT_FINAL_SAMPLE ",JSON.stringify({"skeleton":str(probe.get_skeleton().get_path()),"request_id":requested,"clip":clip,"phase":phase,"clip_time":measured.clip_time,"request_frame":measured.request_frame,"applied_frame":measured.applied_frame,"bone_pose_hash":measured.bone_pose_hash}))
	else:
		print("GAIT_SAMPLE_TIMEOUT ",JSON.stringify({"requested_id":requested,"requested_clip":clip,"requested_phase":phase,"requested_time":expected_time,"completed_request":probe.get("completed_request"),"applied_frame":probe.get("applied_frame"),"last_clip":probe.get("clip"),"last_clip_time":probe.get("clip_time"),"result":measured}))
	return measured

func floor_height(support: Node,at: Vector3) -> float:
	var ground: Dictionary=support.call("floor_below",at)
	var height: float=float((ground.position as Vector3).y) if not ground.is_empty() else 0.0
	var painted: float=float(support.call("visible_town_height",Vector2(at.x,at.z)))
	return maxf(height,painted) if is_finite(painted) else height

func run() -> void:
	for id: String in ["sora","ren","haru","mio","aoi","tanaka","kazuko"]:
		var actor: Node3D=main.player if id=="sora" else main.npcs[id]
		var model: Node3D=actor.get("model") as Node3D
		var controller: CharAnim=actor.get("anim") as CharAnim
		var ap: AnimationPlayer=controller.ap
		var saved: Dictionary={"position":actor.global_position,"visible":actor.visible,"process":actor.is_processing(),"physics":actor.is_physics_processing(),"model_transform":model.transform,"clip":ap.current_animation,"time":ap.current_animation_position,"speed":ap.speed_scale,"state":controller._state,"oneshot":controller._oneshot}
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.visible=true
		actor.global_position=Vector3(-8,0,-10)
		model.rotation.x=0
		var sk: Skeleton3D=model.find_child("Skeleton3D",true,false) as Skeleton3D
		var support: Node=sk.get_node("CharacterFootSupport")
		var probe: SkeletonModifier3D=load("res://scripts/tools/character_qa_pose_probe.gd").new()
		probe.name="RigReviewGaitRegressionProbe"
		sk.add_child(probe)
		probe.call("prepare",model)
		probe.set("measure_feet",true)
		probe.set("measure_bones",true)
		if id in ["sora","ren","aoi","tanaka","kazuko"]:
			await standing_contract(id,model,sk,support,controller,probe)
		await gait_contract(id,model,sk,support,controller,probe)
		probe.queue_free()
		actor.global_position=saved.position
		model.transform=saved.model_transform
		ap.play(str(saved.clip),0)
		ap.seek(float(saved.time),true)
		ap.speed_scale=float(saved.speed)
		controller._state=str(saved.state)
		controller._oneshot=str(saved.oneshot)
		actor.visible=bool(saved.visible)
		actor.set_process(bool(saved.process))
		actor.set_physics_process(bool(saved.physics))
		if actor is Player:(actor as Player).reset_physics_interpolation()

func standing_contract(id: String,model: Node3D,sk: Skeleton3D,support: Node,controller: CharAnim,probe: SkeletonModifier3D) -> void:
	var min_forward: float=INF
	var max_sideways: float=0
	var max_flex: float=0
	var min_flex: float=INF
	var min_flex_case: String=""
	var min_gap: float=INF
	var max_gap: float=-INF
	var length_error: float=0
	var min_extension: float=INF
	var max_torso_shift: float=0
	var fresh_samples: int=0
	var natural: SkeletonModifier3D=sk.get_node_or_null("NaturalLocomotionPose") as SkeletonModifier3D
	for clip: String in ["idle","wave","bow"]:
		for phase: float in [0.0,.125,.375,.625,.875,.9999]:
			if natural!=null:natural.active=false
			var raw: Dictionary=await sample(controller,clip,phase,probe)
			if natural!=null:natural.active=true
			var actual: Dictionary=await sample(controller,clip,phase,probe)
			if bool(raw.get("fresh",false)):fresh_samples+=1
			if bool(actual.get("fresh",false)):fresh_samples+=1
			if not bool(raw.get("fresh",false)) or not bool(actual.get("fresh",false)):continue
			max_torso_shift=maxf(max_torso_shift,(point(actual,"head")-point(actual,"hips")).distance_to(point(raw,"head")-point(raw,"hips")))
			for side: String in ["L","R"]:
				var hip: Vector3=point(actual,"thigh."+side)
				var knee: Vector3=point(actual,"shin."+side)
				var ankle: Vector3=point(actual,"foot."+side)
				var line: Vector3=ankle-hip
				var offset: Vector3=knee-hip-line*(knee-hip).dot(line)/line.length_squared()
				var local_offset: Vector3=model.global_basis.inverse()*offset
				min_forward=minf(min_forward,local_offset.z)
				max_sideways=maxf(max_sideways,absf(local_offset.x))
				var angle: float=flex(hip,knee,ankle)
				if angle<min_flex:
					min_flex=angle
					min_flex_case="%s phase %.4f %s"%[clip,phase,side]
				max_flex=maxf(max_flex,angle)
				var thigh: int=LivingPose.bone(sk,"thigh."+side)
				var shin: int=LivingPose.bone(sk,"shin."+side)
				var foot: int=LivingPose.bone(sk,"foot."+side)
				var upper: float=(sk.global_basis*(sk.get_bone_global_rest(shin).origin-sk.get_bone_global_rest(thigh).origin)).length()
				var lower: float=(sk.global_basis*(sk.get_bone_global_rest(foot).origin-sk.get_bone_global_rest(shin).origin)).length()
				length_error=maxf(length_error,maxf(absf(hip.distance_to(knee)-upper),absf(knee.distance_to(ankle)-lower)))
				min_extension=minf(min_extension,line.length()/(upper+lower))
				var gap: float=float(actual.soles[side])-floor_height(support,ankle)
				min_gap=minf(min_gap,gap)
				max_gap=maxf(max_gap,gap)
	var fresh: bool=fresh_samples==36
	var coverage: String="; fresh final poses %d/36"%fresh_samples
	check(id+" rejected idle wave and bow knees bend forward within the leg plane",fresh and min_forward>=-.002 and max_sideways<=.018,"forward %.4fm; lateral %.4fm"%[min_forward,max_sideways]+coverage)
	check(id+" standing knees extend naturally without the former persistent squat",fresh and min_flex>=2 and max_flex<=24 and min_extension>.975,"flex %.2f..%.2f; extension %.5f; minimum at %s"%[min_flex,max_flex,min_extension,min_flex_case]+coverage)
	check(id+" full skinned standing shoes touch the visible street",fresh and min_gap>=-.004 and max_gap<=.025,"complete shoe gap %.4f..%.4fm"%[min_gap,max_gap]+coverage)
	check(id+" leg correction preserves original segment lengths and torso articulation",fresh and length_error<.001 and max_torso_shift<.002,"length error %.6fm; torso offset %.6fm"%[length_error,max_torso_shift]+coverage)

func gait_contract(id: String,model: Node3D,sk: Skeleton3D,support: Node,controller: CharAnim,probe: SkeletonModifier3D) -> void:
	var rest_left_foot: int=LivingPose.bone(sk,"foot.L")
	var rest_right_foot: int=LivingPose.bone(sk,"foot.R")
	var rest_track: Vector3=model.global_basis.inverse()*(sk.global_basis*(sk.get_bone_global_rest(rest_left_foot).origin-sk.get_bone_global_rest(rest_right_foot).origin))
	var track_sign: float=signf(rest_track.x)
	for clip: String in ["walk","run"]:
		var lowest: float=INF
		var flight: int=0
		var min_forward: float=INF
		var min_outward: float=INF
		var inward_case: String=""
		var recovery_raise: float=INF
		var recovery_heel_below_hip: float=0.0
		var left_wrist_out: float=INF
		var max_length_error: float=0
		var max_elbow_out: float=0
		var max_wrist_out: float=0
		var min_ankle_span: float=INF
		var max_foot_yaw: float=0
		var chest_roll_max: float=0
		var head_roll_max: float=0
		var shoulder_height_min: float=INF
		var shoulder_height_max: float=-INF
		var hand_forward: Dictionary={"L":[],"R":[]}
		var foot_forward: Dictionary={"L":[],"R":[]}
		var fresh_samples: int=0
		for index: int in range(33):
			var pose: Dictionary=await sample(controller,clip,float(index)/32.0,probe)
			if not bool(pose.get("fresh",false)):continue
			fresh_samples+=1
			if clip in (REBUILT[id] as Array):
				chest_roll_max=maxf(chest_roll_max,absf(lateral_roll(pose,LivingPose.bone(sk,"chest"),model,sk)))
				head_roll_max=maxf(head_roll_max,absf(lateral_roll(pose,LivingPose.bone(sk,"head"),model,sk)))
				var left_upper: int=LivingPose.bone(sk,"upper.L")
				var right_upper: int=LivingPose.bone(sk,"upper.R")
				var shoulder_dy: float=float(pose.bones[left_upper].position[1])-float(pose.bones[right_upper].position[1])
				shoulder_height_min=minf(shoulder_height_min,shoulder_dy)
				shoulder_height_max=maxf(shoulder_height_max,shoulder_dy)
				if index<32:
					for swing_side: String in ["L","R"]:
						(hand_forward[swing_side] as Array).append((model.global_basis.inverse()*(point(pose,"hand."+swing_side)-point(pose,"hips"))).z)
						(foot_forward[swing_side] as Array).append((model.global_basis.inverse()*(point(pose,"foot."+swing_side)-point(pose,"hips"))).z)
			var gaps: Array[float]=[]
			if id=="tanaka" and clip=="walk":left_wrist_out=minf(left_wrist_out,model.to_local(point(pose,"hand.L")).x)
			# Absolute separation would also accept feet that swapped sides.
			var ankle_span: float=(model.to_local(point(pose,"foot.L")).x-model.to_local(point(pose,"foot.R")).x)*track_sign
			min_ankle_span=minf(min_ankle_span,ankle_span)
			if id=="sora" and clip=="run":
				for arm_side: String in ["L","R"]:
					var upper_index: int=LivingPose.bone(sk,"upper."+arm_side)
					var fore_index: int=LivingPose.bone(sk,"fore."+arm_side)
					var arm_values: Array=pose.bones[upper_index].position
					var fore_values: Array=pose.bones[fore_index].position
					var upper_point: Vector3=model.to_local(Vector3(float(arm_values[0]),float(arm_values[1]),float(arm_values[2])))
					var fore_point: Vector3=model.to_local(Vector3(float(fore_values[0]),float(fore_values[1]),float(fore_values[2])))
					var hand_point: Vector3=model.to_local(point(pose,"hand."+arm_side))
					max_elbow_out=maxf(max_elbow_out,absf(fore_point.x-upper_point.x))
					max_wrist_out=maxf(max_wrist_out,absf(hand_point.x-upper_point.x))
			for side: String in ["L","R"]:
				var hip: Vector3=point(pose,"thigh."+side)
				var knee: Vector3=point(pose,"shin."+side)
				var ankle: Vector3=point(pose,"foot."+side)
				if id=="kazuko" and clip=="run" and ((index==8 and side=="R") or (index==24 and side=="L")):
					var recovery: Vector3=model.global_basis.inverse()*(knee-hip)
					recovery_raise=minf(recovery_raise,rad_to_deg(atan2(recovery.z,-recovery.y)))
					recovery_heel_below_hip=maxf(recovery_heel_below_hip,(model.global_basis.inverse()*(hip-ankle)).y)
				var toe_direction: Vector3=model.global_basis.inverse()*(point(pose,"toe."+side)-ankle)
				max_foot_yaw=maxf(max_foot_yaw,absf(rad_to_deg(atan2(toe_direction.x,toe_direction.z))))
				var line: Vector3=ankle-hip
				var knee_offset: Vector3=knee-hip-line*(knee-hip).dot(line)/line.length_squared()
				min_forward=minf(min_forward,(model.global_basis.inverse()*knee_offset).z)
				var outward: float=(model.global_basis.inverse()*knee_offset).x*track_sign*(1.0 if side=="L" else -1.0)
				if outward<min_outward:
					min_outward=outward
					inward_case="phase %.5f %s"%[float(index)/32.0,side]
				var gap: float=float(pose.soles[side])-floor_height(support,ankle)
				gaps.append(gap)
				lowest=minf(lowest,gap)
				for pair: Array in [["thigh."+side,"shin."+side],["shin."+side,"foot."+side]]:
					var first: int=LivingPose.bone(sk,str(pair[0]))
					var second: int=LivingPose.bone(sk,str(pair[1]))
					var rest_length: float=(sk.global_basis*(sk.get_bone_global_rest(second).origin-sk.get_bone_global_rest(first).origin)).length()
					max_length_error=maxf(max_length_error,absf(point(pose,str(pair[0])).distance_to(point(pose,str(pair[1])))-rest_length))
			if index<32 and gaps[0]>.025 and gaps[1]>.025:flight+=1
		var fresh: bool=fresh_samples==33
		var coverage: String="; fresh final poses %d/33"%fresh_samples
		check(id+" "+clip+" full skinned shoes clear the street at thirty three final poses",fresh and lowest>=-.005,"minimum complete shoe gap %.5fm"%lowest+coverage)
		check(id+" "+clip+" final leg segments preserve the source anatomy",fresh and max_length_error<.001,"maximum bone length error %.6fm"%max_length_error+coverage)
		if id=="sora" and clip=="walk":check("Sora walking knees do not collapse inward from their own hip to ankle line",fresh and min_outward>=-.010,"minimum directed outward knee offset %.5fm at %s"%[min_outward,inward_case]+coverage)
		if id=="kazuko" and clip=="walk":check("Kazuko walking shins do not turn the ankles outward from an inward knee plane",fresh and min_outward>=-.010,"minimum directed outward knee offset %.5fm at %s"%[min_outward,inward_case]+coverage)
		# A recovering heel may remain behind the hip during natural running.
		# Require visible forward knee lift and heel recovery, rather than the
		# former forward-ankle proxy which drove the thigh into the apron.
		if id=="kazuko" and clip=="run":check("Kazuko swing knees lift forward while the heel recovers upwards",fresh and recovery_raise>=30.0 and recovery_heel_below_hip<=.420,"mid-recovery minimum thigh raise %.2f degrees; maximum heel below hip %.5fm"%[recovery_raise,recovery_heel_below_hip]+coverage)
		if id=="tanaka" and clip=="walk":check("Tanaka left wrist stays beside the coat instead of buried against its centre",fresh and left_wrist_out>=.145,"minimum left wrist outside centre %.5fm"%left_wrist_out+coverage)
		if clip in (REBUILT[id] as Array):
			check(id+" "+clip+" knees stay forward after safety IK",fresh and min_forward>=-.004,"minimum forward knee offset %.5fm"%min_forward+coverage)
			if clip=="run":check(id+" running retains real simultaneous shoe flight after safety IK",fresh and flight>=2,"%d/32 phases both complete shoes >25mm"%flight+coverage)
		if id=="sora" and clip=="run":check("Sora running forearms stay beside the ribs instead of splaying outward",fresh and max_elbow_out<.050 and max_wrist_out<.060,"elbow %.4fm; wrist %.4fm outside shoulder"%[max_elbow_out,max_wrist_out]+coverage)
		if id=="mio" and clip=="run":check("Mio running ankles retain separated tracks instead of crossing inward",fresh and min_ankle_span>=.12,"minimum directed ankle track separation %.4fm; rest left/right sign %.0f; maximum toe forward yaw %.2f degrees"%[min_ankle_span,track_sign,max_foot_yaw]+coverage)
		if clip in (REBUILT[id] as Array):
			var left_hands: Array[float]=[]
			var right_hands: Array[float]=[]
			var left_feet: Array[float]=[]
			var right_feet: Array[float]=[]
			left_hands.assign(hand_forward.L)
			right_hands.assign(hand_forward.R)
			left_feet.assign(foot_forward.L)
			right_feet.assign(foot_forward.R)
			var left_opposition: float=correlation(left_hands,left_feet)
			var right_opposition: float=correlation(right_hands,right_feet)
			# Original walk chest/head peaks were1.81/.34deg; runs1.14/1.18.
			# Rebuilt torso inherited a counter-roll for a different pelvis:
			# walk8.61/6.60deg, runs5.92/4.41. Compact run recovery differs
			# from the walk curve: Aoi's unchanged opposition is about-.82.
			var head_roll_limit: float=1.0 if clip=="walk" else 2.0
			var opposition_limit: float=-.85 if clip=="walk" else -.75
			check(id+" "+clip+" chest head and shoulders stay balanced with opposite arm swing",fresh and chest_roll_max<3.0 and head_roll_max<head_roll_limit and shoulder_height_max-shoulder_height_min<.035 and left_opposition<opposition_limit and right_opposition<opposition_limit,"chest/head roll %.3f/%.3fdeg; shoulder height oscillation %.5fm; same-side hand-foot correlation %.4f/%.4f"%[chest_roll_max,head_roll_max,shoulder_height_max-shoulder_height_min,left_opposition,right_opposition]+coverage)
		var seam_error: float=0
		var seam_fresh: int=0
		for _cycle: int in range(2):
			var before: Dictionary=await sample(controller,clip,.9999,probe)
			var after: Dictionary=await sample(controller,clip,.0001,probe)
			if bool(before.get("fresh",false)):seam_fresh+=1
			if bool(after.get("fresh",false)):seam_fresh+=1
			if not bool(before.get("fresh",false)) or not bool(after.get("fresh",false)):continue
			for name: String in ["hips","shin.L","shin.R","foot.L","foot.R","toe.L","toe.R"]:
				seam_error=maxf(seam_error,point(before,name).distance_to(point(after,name)))
		check(id+" "+clip+" final knees ankles and toes close across two cycle boundaries",seam_fresh==4 and seam_error<.004,"maximum 99.99 to 0.01 percent seam %.6fm; fresh final poses %d/4"%[seam_error,seam_fresh])
