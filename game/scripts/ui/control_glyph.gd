class_name ControlGlyph
extends Control
## Vector input symbols stay readable at every window size. Tooltips carry the words.
var kind := "move"
var ink := Color(.25,.40,.40)

static func make(symbol: String, caption: String, extent: int = 32) -> ControlGlyph:
	var glyph := ControlGlyph.new()
	glyph.kind=symbol;glyph.tooltip_text=caption
	glyph.custom_minimum_size=Vector2(extent,extent)
	glyph.mouse_filter=Control.MOUSE_FILTER_PASS
	return glyph

func _draw() -> void:
	var c:=size*.5;var s:=minf(size.x,size.y)*.38
	match kind:
		"move":
			for direction: Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
				var tip:=c+direction*s;var side:=direction.orthogonal()*s*.27
				draw_line(c+direction*s*.2,tip,ink,2,true)
				draw_polyline(PackedVector2Array([tip-direction*s*.36+side,tip,tip-direction*s*.36-side]),ink,2,true)
		"run":
			draw_circle(c+Vector2(s*.20,-s*.70),s*.17,ink)
			for points: Array in [[Vector2(.1,-.4),Vector2(-.2,.1),Vector2(.5,.3),Vector2(.1,.85)],[Vector2(-.2,.1),Vector2(-.65,.65)],[Vector2(-.03,-.25),Vector2(-.55,-.4),Vector2(-.7,0)],[Vector2(.03,-.25),Vector2(.55,-.12),Vector2(.75,-.55)]]:
				var line:=PackedVector2Array();for p: Vector2 in points:line.append(c+p*s)
				draw_polyline(line,ink,2.2,true)
		"camera":
			draw_style_box(UIKitStyles.slot(),Rect2(c-Vector2(s,s*.67),Vector2(s*2,s*1.34)))
			draw_arc(c,s*.37,0,TAU,32,ink,2,true)
			draw_line(c+Vector2(-s*.5,-s*.67),c+Vector2(-s*.3,-s*.94),ink,3,true)
		"mouse":
			draw_arc(c,s*.65,0,TAU,32,ink,2,true);draw_line(c-Vector2(0,s*.65),c,ink,2,true)
			draw_line(c-Vector2(s*.62,0),c+Vector2(s*.62,0),ink,2,true)
		"zoom":
			draw_arc(c-Vector2(s*.2,s*.2),s*.55,0,TAU,32,ink,2,true)
			draw_line(c+Vector2(s*.2,s*.2),c+Vector2(s*.85,s*.85),ink,2.5,true)
			draw_line(c-Vector2(s*.45,s*.2),c+Vector2(s*.05,-s*.2),ink,2,true)
			return
