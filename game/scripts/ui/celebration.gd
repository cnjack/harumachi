class_name Celebration
extends Control
## A brief anime impact frame: ink rays, warm petals and a large illustrated reward.
var elapsed := 0.0
var lifetime := 2.6
var _rays := 18

func effects_only() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE

func setup(title: String, icon_id: String, detail: String = "") -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var centre:=VBoxContainer.new();centre.alignment=BoxContainer.ALIGNMENT_CENTER
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.offset_left=-220;centre.offset_right=220;centre.offset_top=-230;centre.offset_bottom=40
	add_child(centre)
	var icon:=UITheme.icon(icon_id,176);icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;centre.add_child(icon)
	if icon.texture==null:icon.texture=UITheme.icon_texture("fish")
	var headline:=UITheme.label(title,44,Color(1,.95,.74));headline.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_color_override("font_outline_color",Color(.13,.27,.37));headline.add_theme_constant_override("outline_size",8);centre.add_child(headline)
	if detail!="":
		var caption:=UITheme.label(detail,26,Color(1,.98,.86));caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_outline_color",Color(.13,.27,.37));caption.add_theme_constant_override("outline_size",5);centre.add_child(caption)
	centre.pivot_offset=Vector2(220,135);centre.scale=Vector2(.35,.35)
	var tween:=create_tween();tween.tween_property(centre,"scale",Vector2.ONE,.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	elapsed+=delta
	modulate.a=clampf((lifetime-elapsed)/.4,0,1)
	queue_redraw()
	if elapsed>lifetime:queue_free()

func _draw() -> void:
	var centre:=size*.5-Vector2(0,100)
	var expansion:=1.0-exp(-elapsed*8)
	for i in _rays:
		var angle:=TAU*float(i)/_rays+.04*elapsed
		var dir:=Vector2.from_angle(angle)
		var inner:=centre+dir*110*expansion
		var outer:=centre+dir*(210+float(i%3)*28)*expansion
		draw_line(inner,outer,Color(1,.93,.65,.45),3,true)
	for i in 26:
		var angle:=float(i)*2.39996
		var radius: float=90+elapsed*(45+float(i%5)*12)
		var point:=centre+Vector2.from_angle(angle+elapsed*.15)*radius+Vector2(0,elapsed*elapsed*14)
		var petal:=Vector2.from_angle(angle+elapsed)*7
		draw_colored_polygon(PackedVector2Array([point+petal,point+petal.orthogonal()*.4,point-petal,point-petal.orthogonal()*.4]),Color(1,.78 if i%2==0 else .92,.64,.85))
