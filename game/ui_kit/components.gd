class_name UIKitComponents
extends RefCounted

static func resting_cat(width: float=80,anchor_fraction: float=.78) -> Control:
	var control: Control=preload("res://ui_kit/cat_decoration.gd").new() as Control
	control.display_width=width
	control.anchor_fraction=anchor_fraction
	return control

static func style_button(control: Button,role: String="secondary",compact: bool=false) -> void:
	control.set_meta("ui_kit_role",role)
	control.custom_minimum_size.y=UIKitTokens.COMPACT_BUTTON_HEIGHT if compact else UIKitTokens.BUTTON_HEIGHT
	for state: String in ["normal","hover","pressed","disabled","focus"]:control.add_theme_stylebox_override(state,UIKitStyles.button(role,state,compact))
	control.add_theme_font_size_override("font_size",UIKitTokens.TYPE_SCALE.caption if compact else UIKitTokens.TYPE_SCALE.body)
	control.add_theme_constant_override("h_separation",8)

static func button(text: String,callback: Callable=Callable(),role: String="secondary",compact: bool=false) -> Button:
	var control:=Button.new();control.text=text;style_button(control,role,compact)
	if callback.is_valid():control.pressed.connect(callback)
	return control

static func label(text: String,role: String="body",colour: Color=UIKitTokens.INK) -> Label:
	var control:=Label.new();control.text=text;control.set_meta("ui_kit_role",role)
	control.add_theme_font_size_override("font_size",UIKitTokens.TYPE_SCALE[role]);control.add_theme_color_override("font_color",colour)
	return control

static func icon(id: String,size: int=32) -> TextureRect:
	var control:=TextureRect.new();control.texture=UIKitAssets.icon(id);control.custom_minimum_size=Vector2(size,size)
	control.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;control.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	control.mouse_filter=Control.MOUSE_FILTER_IGNORE;return control

static func progress(width: float=240,height: float=16,colour: Color=UIKitTokens.SAGE) -> ProgressBar:
	var control:=ProgressBar.new();control.custom_minimum_size=Vector2(width,height);control.show_percentage=false
	control.add_theme_stylebox_override("background",UIKitStyles.progress());control.add_theme_stylebox_override("fill",UIKitStyles.progress("fill",colour))
	return control
