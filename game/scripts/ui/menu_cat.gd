extends Control
## Small cat on the heading: walk, lie down, dangle its tail, get up.

const WALK=preload("res://ui_kit/resources/title_cat.tres")
const REST=preload("res://ui_kit/resources/title_cat_rest.tres")
const REST_WIDGET=preload("res://ui_kit/cat_decoration.gd")
var sprite: AnimatedSprite2D
var resting: Control
var progress: float=.52
var direction: float=1.0
var rest_left: float=0.0
var travelled: float=0.0
var turns: int=0
var state: String="walk"
var heading: Label

func _ready() -> void:
	name="MenuCat"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	heading=get_parent().get_node("TitleHeading") as Label
	sprite=AnimatedSprite2D.new()
	sprite.name="CatSprite"
	sprite.sprite_frames=WALK
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	sprite.animation_finished.connect(_finished)
	resting=REST_WIDGET.new() as Control
	resting.panel_edge=false
	resting.display_width=83.2
	add_child(resting)
	resting.visible=false
	sprite.play(&"walk")
	_layout()

func _layout() -> void:
	if sprite==null:return
	position=heading.position+Vector2(0,-110)
	size=Vector2(heading.get_combined_minimum_size().x,170)
	var scale_factor: float=.20
	var support: Vector2=Vector2(size.x*progress,128)
	var source_height: float=362 if sprite.sprite_frames==WALK else 440
	var source_offset_x: float=0 if sprite.sprite_frames==WALK else 16*scale_factor
	sprite.scale=Vector2.ONE*scale_factor
	sprite.position=support+Vector2(source_offset_x,(source_height*.5-304)*scale_factor)
	resting.foot_point=support+Vector2(16*scale_factor,0)
	resting.mirrored=sprite.flip_h

func _process(delta: float) -> void:
	if sprite==null:return
	if state=="walk":
		var movement: float=delta*21.0/maxf(1,size.x)*direction
		progress=clampf(progress+movement,.20,.78)
		travelled+=absf(movement)*size.x
		if progress<=.20 or progress>=.78:
			state="lie_down"
			sprite.sprite_frames=REST
			sprite.play(&"lie_down")
	elif state=="rest":
		rest_left=maxf(0,rest_left-delta)
		if rest_left==0:
			state="get_up"
			resting.visible=false
			sprite.visible=true
			sprite.play(&"get_up")
	_layout()

func _finished() -> void:
	if state=="lie_down":
		state="rest"
		rest_left=7.0
		sprite.play(&"rest")
		sprite.visible=false
		resting.visible=true
	elif state=="get_up":
		direction=-direction
		turns+=1
		state="walk"
		sprite.sprite_frames=WALK
		sprite.flip_h=direction<0
		sprite.play(&"walk")

func telemetry() -> Dictionary:
	return {"mode":"2D heading cat","state":state,"animation":String(sprite.animation) if sprite else "","travelled_px":travelled,"turns":turns,"progress":progress,"rest":resting.telemetry() if resting else {}}
