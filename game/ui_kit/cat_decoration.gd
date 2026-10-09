extends Control
## Fixed resting body and a separate dangling tail; all original atlas pixels.

const BODY=preload("res://ui_kit/resources/cat_rest_body.tres")
const TAIL=preload("res://ui_kit/resources/cat_rest_tail.tres")
const FRAME_WIDTH: float=416.0
const FRAME_HEIGHT: float=440.0
const SUPPORT_Y: float=304.0
var display_width: float=80.0
var anchor_fraction: float=.78
var panel_edge: bool=true
var foot_point: Vector2=Vector2.ZERO
var mirrored: bool=false
var body: Sprite2D
var tail: AnimatedSprite2D
var phase: float=0.0
var tail_root_x: float=0.0

func _ready() -> void:
	name="RestingCat"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	process_mode=Node.PROCESS_MODE_ALWAYS
	tail_root_x=float(BODY.get_meta("tail_root_x"))
	body=Sprite2D.new()
	body.name="RestBody"
	body.texture=BODY
	body.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(body)
	tail=AnimatedSprite2D.new()
	tail.name="DanglingTail"
	tail.sprite_frames=TAIL
	tail.centered=false
	tail.offset=Vector2(-64,0)
	tail.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(tail)
	tail.play(&"sway")
	_layout()

func _process(delta: float) -> void:
	phase+=delta
	_layout()

func _layout() -> void:
	if body==null:return
	var factor: float=display_width/FRAME_WIDTH
	var edge: Vector2=foot_point
	if panel_edge:
		var inset: float=32.0
		if get_parent() is PanelContainer:inset=(get_parent() as PanelContainer).get_theme_stylebox("panel").get_content_margin(SIDE_TOP)
		edge=Vector2(size.x*anchor_fraction,-inset+5)
	body.scale=Vector2.ONE*factor
	body.flip_h=mirrored
	body.position=edge+Vector2(0,(FRAME_HEIGHT*.5-SUPPORT_Y)*factor)
	var root_offset: float=(tail_root_x-FRAME_WIDTH*.5)*factor
	tail.position=edge+Vector2(-root_offset if mirrored else root_offset,-factor)
	tail.scale=Vector2(-factor if mirrored else factor,factor*1.4)
	# A small continuous arc smooths the eight drawn tail phases at the root.
	tail.rotation=sin(phase*TAU/3.8)*.07*(-1 if mirrored else 1)

func telemetry() -> Dictionary:
	return {"mode":"fixed 2D body and dangling tail","tail_frame":tail.frame if tail else -1,"tail_rotation":tail.rotation if tail else 0,"body_texture":body.texture.resource_name if body else "","foot":[foot_point.x,foot_point.y]}
