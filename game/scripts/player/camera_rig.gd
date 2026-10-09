class_name CameraRig
extends Node3D
## Third-person high camera: limited pitch, free yaw (mouse drag / , .), wheel zoom,
## spring-arm collision so walls never come between camera and player.

const PITCH_MIN := 18.0
const PITCH_MAX := 58.0
const DIST_MIN := 3.5
const DIST_MAX := 10.0

var target: Node3D
var yaw := 0.0
var pitch := 35.0
var dist := 6.5
var fixed := false          # house mode: fixed yaw diorama view that still follows the player
var collide := true:        # the spring arm is off indoors (cut-away walls must not pull it in)
	set(v):
		collide = v
		arm.collision_mask = (WorldBuilder.L_SOLID | WorldBuilder.L_CAMERA) if v else 0
var _drag := false
var yaw_node := Node3D.new()
var pitch_node := Node3D.new()
var arm := SpringArm3D.new()
var cam := Camera3D.new()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	top_level = true
	add_child(yaw_node)
	yaw_node.add_child(pitch_node)
	pitch_node.add_child(arm)
	arm.add_child(cam)
	arm.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_CAMERA
	var sh := SphereShape3D.new()
	sh.radius = 0.25
	arm.shape = sh
	arm.margin = 0.1
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 1200.0
	cam.current = true


func exclude(body: CollisionObject3D) -> void:
	arm.add_excluded_object(body.get_rid())


func snap() -> void:
	if target:
		global_position = target.global_position + Vector3(0, 1.25, 0)
	_apply()
	if target: target.reset_physics_interpolation()
	reset_physics_interpolation()
	_update_body_fade()


func _apply() -> void:
	yaw_node.rotation.y = deg_to_rad(yaw)
	pitch_node.rotation.x = deg_to_rad(-pitch)
	arm.spring_length = dist


func _unhandled_input(event: InputEvent) -> void:
	if fixed or GameState.input_locked():
		_drag = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist - 0.5, DIST_MIN, DIST_MAX)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist + 0.5, DIST_MIN, DIST_MAX)
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		var s := 0.25 * float(GameState.settings.get("mouse_sens", 1.0))
		yaw -= mm.relative.x * s
		var inv := -1.0 if GameState.settings.get("invert_y", false) else 1.0
		pitch = clampf(pitch + mm.relative.y * s * inv, PITCH_MIN, PITCH_MAX)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	# Character and camera share physics snapshots; interpolation supplies the
	# rendered positions between ticks without making the avatar drift on screen.
	var want := target.global_position + Vector3(0, 1.25, 0)
	global_position = global_position.lerp(want, 1.0 - exp(-10.0 * delta))
	if not fixed and not GameState.input_locked():
		var k := Input.get_axis("cam_left", "cam_right")
		yaw -= k * 90.0 * delta
	_apply()


func _process(_delta: float) -> void:
	if target == null: return
	_update_body_fade()

func _update_body_fade() -> void:
	# Retraction under a roof can put the follow camera inside the avatar.
	# Change only this instance's rendering; its collision stays in place.
	if not target is Player or not is_instance_valid((target as Player).model):return
	var amount: float=0.0
	if get_viewport().get_camera_3d()==cam:
		var focus: Vector3=target.get_global_transform_interpolated().origin+Vector3.UP*1.25
		var camera_position: Vector3=cam.get_global_transform_interpolated().origin
		amount=clampf((1.8-camera_position.distance_to(focus))/.8,0.0,1.0)
	for mesh: MeshInstance3D in WorldBuilder.find_meshes((target as Player).model):mesh.transparency=amount


func forward_yaw() -> float:
	return deg_to_rad(yaw)
