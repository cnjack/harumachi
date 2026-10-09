class_name UIKitStyles
extends RefCounted
## Semantic styles: views choose a role, not colours, borders or texture paths.

static func _texture(id: String,width: int,edge_x: float,edge_y: float,margin: int=12) -> StyleBoxTexture:
	var style:=StyleBoxTexture.new();style.texture=UIKitAssets.render_texture(id,width)
	style.set_texture_margin(SIDE_LEFT,edge_x);style.set_texture_margin(SIDE_RIGHT,edge_x)
	style.set_texture_margin(SIDE_TOP,edge_y);style.set_texture_margin(SIDE_BOTTOM,edge_y)
	style.content_margin_left=margin;style.content_margin_right=margin
	style.content_margin_top=margin*.55;style.content_margin_bottom=margin*.55
	style.resource_name="UIKitStyle/"+id
	return style

static func surface(role: String="modal",margin: int=24) -> StyleBoxTexture:
	var hud:=role=="hud"
	var small:=hud and margin<=18
	var style: StyleBoxTexture=_texture("hud_paper" if hud else "modal_paper",128 if small else (256 if hud else 384),14 if small else (26 if hud else 64),14 if small else (26 if hud else 64),margin if hud else margin+10)
	style.content_margin_top=(margin if hud else margin+10)*.7
	style.content_margin_bottom=style.content_margin_top
	return style

static func button(role: String="secondary",state: String="normal",compact: bool=false) -> StyleBox:
	if state=="focus":
		var focus:=flat(Color.TRANSPARENT,UIKitTokens.GOLD,2,12,0,false);focus.draw_center=false;return focus
	if role=="icon":
		return _texture("slot_selected" if state in ["hover","pressed"] else "slot_empty",32,7,7,4)
	var primary:=role=="primary"
	var style: StyleBoxTexture=_texture(("primary_" if primary else "secondary_")+state,128,26,14,6 if compact else 16)
	if role=="quiet" and state=="normal":style.modulate_color.a=0
	return style

static func slot(role: String="normal",margin: int=6) -> StyleBoxTexture:
	return _texture("slot_"+role,96,17,17,margin)

static func row(role: String="normal",margin: int=12) -> StyleBoxTexture:
	return _texture("slot_"+("selected" if role=="selected" else ("disabled" if role=="disabled" else "empty")),64,12,12,margin)

static func notice(tone: String="info",margin: int=16) -> StyleBoxTexture:
	return _texture("notice_warning" if tone=="warning" else "notice_info",160,20,20,margin)

static func progress(part: String="track",colour: Color=UIKitTokens.SAGE) -> StyleBoxTexture:
	var style: StyleBoxTexture=_texture("progress_"+part,128,10,4,0)
	if part=="fill":style.modulate_color=colour
	return style

static func flat(bg: Color,border: Color,bw: int=0,radius: int=20,margin: int=20,shadow: bool=true) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=bg;style.border_color=border
	style.set_border_width_all(mini(bw,1) if shadow else bw);style.set_corner_radius_all(maxi(radius,20) if shadow else radius)
	style.content_margin_left=margin;style.content_margin_right=margin;style.content_margin_top=margin*.7;style.content_margin_bottom=margin*.7
	if shadow:
		style.shadow_color=Color(.12,.21,.17,.16);style.shadow_size=16;style.shadow_offset=Vector2(0,3)
	style.anti_aliasing=true;style.anti_aliasing_size=1.75;return style

static func theme() -> Theme:
	var theme:=Theme.new();theme.default_font=load(UIKitTokens.FONT);theme.default_font_size=26
	for kind: String in ["PanelContainer","Panel"]:theme.set_stylebox("panel",kind,surface())
	theme.set_color("font_color","Label",UIKitTokens.INK);theme.set_color("default_color","RichTextLabel",UIKitTokens.INK)
	theme.set_font_size("normal_font_size","RichTextLabel",26)
	for kind: String in ["Button","OptionButton"]:
		for state: String in ["normal","hover","pressed","disabled","focus"]:theme.set_stylebox(state,kind,button("secondary",state))
		for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:theme.set_color(state,kind,UIKitTokens.INK)
		theme.set_color("font_disabled_color",kind,UIKitTokens.MUTED);theme.set_constant("h_separation",kind,8)
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:theme.set_color(state,"CheckBox",UIKitTokens.INK)
	theme.set_stylebox("focus","CheckBox",button("secondary","focus"))
	theme.set_stylebox("slider","HSlider",progress())
	theme.set_stylebox("grabber_area","HSlider",progress("fill",UIKitTokens.SAGE))
	theme.set_stylebox("grabber_area_highlight","HSlider",progress("fill",UIKitTokens.GOLD))
	theme.set_stylebox("background","ProgressBar",progress());theme.set_stylebox("fill","ProgressBar",progress("fill"))
	return theme
