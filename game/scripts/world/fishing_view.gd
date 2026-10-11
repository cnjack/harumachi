class_name FishingView
extends Node3D
## Small rod, line, float and rings stay in the actual landscape while fishing.
var player: Player
var hook := Vector3.ZERO
var rod: MeshInstance3D
var bobber: MeshInstance3D
var ring: MeshInstance3D
var cord := MeshInstance3D.new()
var _line_material: StandardMaterial3D
var _clock := 0.0
var _skeleton: Skeleton3D
var _hand_bone := -1
var pose: FishingPose
var fish_sprite: Sprite3D
var _land_time:=0.0
var _session: FishingSession
var _reel_body: MeshInstance3D
var _reel_axle: MeshInstance3D
var _reel_arm: MeshInstance3D
var _reel_grip: MeshInstance3D
var _reel_mount: MeshInstance3D

func setup(who: Player,water: Vector3) -> void:
	player=who;hook=water
	if player.model:
		var skeletons:=player.model.find_children("*","Skeleton3D",true,false)
		if not skeletons.is_empty():
			_skeleton=skeletons[0] as Skeleton3D
			_hand_bone=LivingPose.bone(_skeleton,"hand.R")
			pose=FishingPose.new();_skeleton.add_child(pose)
			pose.prepare(player,hook)
	rod=MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius=.009;mesh.bottom_radius=.023;mesh.height=1.85;mesh.radial_segments=8
	rod.mesh=mesh
	var wood := StandardMaterial3D.new()
	wood.albedo_color=Color(.36,.24,.12);wood.roughness=1.0
	rod.material_override=wood;add_child(rod)
	_reel_body=_reel_piece(.055,.09)
	_reel_axle=_reel_piece(.008,.10)
	_reel_arm=_reel_piece(.008,.06)
	_reel_grip=_reel_piece(.019,.055)
	_reel_mount=_reel_piece(.008,.10)
	bobber=MeshInstance3D.new()
	var float_mesh := SphereMesh.new()
	float_mesh.radius=.09;float_mesh.height=.24;float_mesh.radial_segments=12;float_mesh.rings=6
	bobber.mesh=float_mesh
	var red := StandardMaterial3D.new()
	red.albedo_color=Color(.94,.32,.17);red.roughness=1.0;red.emission_enabled=true;red.emission=Color(.25,.04,.015)
	bobber.material_override=red;add_child(bobber)
	ring=MeshInstance3D.new()
	var ripple := TorusMesh.new()
	ripple.inner_radius=.28;ripple.outer_radius=.30;ripple.rings=32;ripple.ring_segments=6
	ring.mesh=ripple
	var white := StandardMaterial3D.new()
	white.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color=Color(.83,.95,.91,.66);white.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override=white;add_child(ring)
	_line_material=StandardMaterial3D.new();_line_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.albedo_color=Color(.84,.87,.76)
	add_child(cord)
	fish_sprite=Sprite3D.new();fish_sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED;fish_sprite.pixel_size=.0012;fish_sprite.visible=false;add_child(fish_sprite)
	if is_instance_valid(pose):pose.modification_processed.connect(_sync_from_pose)

func update_view(session: FishingSession,delta: float) -> void:
	_session=session
	_clock+=delta
	if session.state==FishingSession.State.LANDED:_land_time+=delta
	if is_instance_valid(pose):
		pose.phase=_clock;pose.amount=0.0 if session.state in [FishingSession.State.LANDED,FishingSession.State.MISSED,FishingSession.State.CLOSED] else 1.0
		pose.reel=1.0 if session.state==FishingSession.State.REEL else 0.0
	if not is_instance_valid(pose):_render_view(session)

func _reel_piece(radius: float,length: float) -> MeshInstance3D:
	var part:=MeshInstance3D.new();var shape:=CylinderMesh.new()
	shape.top_radius=radius;shape.bottom_radius=radius;shape.height=length;shape.radial_segments=12
	part.mesh=shape
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.22,.25,.24);material.roughness=.85
	part.material_override=material;add_child(part)
	return part

func _rod_segment(part: MeshInstance3D,from: Vector3,to: Vector3) -> void:
	part.global_position=(from+to)*.5
	var direction: Vector3=to-from
	if direction.length_squared()<.000001:return
	part.quaternion=Quaternion(Vector3.UP,direction.normalized())
	part.scale.y=direction.length()/(part.mesh as CylinderMesh).height

func _sync_from_pose() -> void:
	# Read while the modifier is applied: Skeleton3D restores its base poses later.
	if _session != null and is_instance_valid(rod):_render_view(_session)

func _render_view(session: FishingSession) -> void:
	fish_sprite.visible=session.state==FishingSession.State.LANDED and _land_time<2.8
	if session.state==FishingSession.State.LANDED:
		fish_sprite.texture=UITheme.icon_texture(str(session.result.get("fish","fish")))
		var k:=clampf(_land_time/.8,0,1)
		fish_sprite.global_position=hook.lerp(player.global_position+Vector3(0,1.65,0),k)+Vector3(0,sin(k*PI)*1.6,0)
		fish_sprite.rotation.z=sin(_clock*8)*.15
	else:_land_time=0.0
	var active := session.state in [FishingSession.State.CAST,FishingSession.State.WAIT,FishingSession.State.BITE,FishingSession.State.REEL]
	bobber.visible=active;ring.visible=active;cord.visible=active
	var forward := hook-player.global_position
	forward.y=0;forward=forward.normalized()
	var hand := player.global_position+Vector3(0,1.05,0)+Vector3(forward.z,0,-forward.x)*.22
	if is_instance_valid(pose) and pose.palm_world.has("R"):
		hand=pose.palm_world.R
	elif is_instance_valid(_skeleton) and _hand_bone>=0:
		hand=(_skeleton.global_transform*_skeleton.get_bone_global_pose(_hand_bone)).origin
	var lift := .82+.16*sin(_clock*1.4) if session.state==FishingSession.State.REEL else .72
	if session.state==FishingSession.State.CAST:lift=lerpf(1.7,.72,clampf(session.timer/.65,0,1))
	var tip := hand+forward*1.45+Vector3(0,lift,0)
	rod.global_position=(hand+tip)*.5
	rod.quaternion=Quaternion(Vector3.UP,(tip-hand).normalized())
	rod.scale.y=(tip-hand).length()/1.85
	var right: Vector3=forward.cross(Vector3.UP)
	var hub: Vector3=hand-right*.10+forward*.05-Vector3.UP*.035
	var crank: Vector3=hub-right*.14
	if is_instance_valid(pose) and pose.palm_world.has("L"):crank=pose.palm_world.L
	for part: MeshInstance3D in [_reel_body,_reel_axle,_reel_arm,_reel_grip,_reel_mount]:part.visible=session.state not in [FishingSession.State.LANDED,FishingSession.State.MISSED,FishingSession.State.CLOSED]
	_rod_segment(_reel_body,hub-right*.045,hub+right*.045)
	_rod_segment(_reel_mount,hand+(tip-hand).normalized()*.08,hub+right*.045)
	var axle: Vector3=hub-right*.14
	_rod_segment(_reel_axle,hub,axle)
	_rod_segment(_reel_arm,axle,crank)
	_rod_segment(_reel_grip,crank-right*.025,crank+right*.025)
	var float_pos := hook+Vector3(sin(_clock*1.1)*.04,.085+sin(_clock*2.5)*.023,0)
	if session.state==FishingSession.State.BITE:float_pos.y-=.11+.025*sin(_clock*14)
	if session.state==FishingSession.State.REEL:float_pos=hook.lerp(player.global_position+forward*.7,session.reel_progress*.75)+Vector3(0,.10,0)
	if session.state==FishingSession.State.CAST:float_pos=tip.lerp(hook,clampf(session.timer/.65,0,1))+Vector3(0,sin(session.timer/.65*PI),0)
	bobber.global_position=float_pos
	ring.global_position=Vector3(float_pos.x,LakesideLayout.WATER_Y+.018,float_pos.z)
	var wave := .75+fmod(_clock*(1.6 if session.state==FishingSession.State.BITE else .6),1.6)
	ring.scale=Vector3(wave,1,wave)
	var line := ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,_line_material)
	for i in 17:
		var t := float(i)/16.0
		line.surface_add_vertex(tip.lerp(float_pos,t)-Vector3(0,sin(t*PI)*(.10 if session.state==FishingSession.State.REEL else .3),0))
	line.surface_end();cord.mesh=line

func _exit_tree() -> void:
	if is_instance_valid(pose):pose.queue_free()
