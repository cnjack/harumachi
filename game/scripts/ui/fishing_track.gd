class_name FishingTrack
extends Control
var session: FishingSession
func _process(_delta: float) -> void:queue_redraw()
func _draw() -> void:
	if session==null:return
	var left:=24.0;var width:=size.x-48.0;var y:=size.y*.55
	draw_line(Vector2(left,y),Vector2(left+width,y),Color(.24,.45,.52,.4),6,true)
	var c:=Vector2(left+width*session.cursor,y)
	var band:=session.track_width*width
	draw_style_box(UIKitStyles.progress("fill",UITheme.GOOD if session.tracking() else UITheme.BAD),Rect2(c-Vector2(band*.5,19),Vector2(band,38)))
	var f:=Vector2(left+width*session.fish_position,y)
	draw_texture_rect(UITheme.icon_texture("fish"),Rect2(f-Vector2(18,18),Vector2(36,36)),false)
	for i in 5:draw_line(Vector2(left+width*i*.25,y+25),Vector2(left+width*i*.25,y+29),UITheme.INK_SOFT,1,true)
