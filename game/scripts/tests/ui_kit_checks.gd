extends RefCounted
## Introspects live controls and resources; also runs on the pre-kit project.
var t: Node
var ui: Node
func _init(runner: Node) -> void:
	t=runner;ui=runner.main.ui
func check(name: String,ok: bool,detail: String="") -> void:
	t.check("UI_KIT",name,ok,detail)
func panels(root: Node) -> Array[PanelContainer]:
	var result: Array[PanelContainer]=[]
	if root is PanelContainer:result.append(root)
	for child: Node in root.get_children():result.append_array(panels(child))
	return result
func skin_count(root: Node,prefix: String) -> int:
	var count:=0
	for panel: PanelContainer in panels(root):
		if panel.get_theme_stylebox("panel").resource_name.begins_with(prefix):count+=1
	return count
func run() -> void:
	var catalog: Dictionary={}
	if FileAccess.file_exists("res://ui_kit/catalog.json"):
		catalog=JSON.parse_string(FileAccess.get_file_as_string("res://ui_kit/catalog.json"))
	var entries: Dictionary=catalog.get("assets",{})
	var icons:=0;var controls:=0;var surfaces:=0
	var bounded:=not entries.is_empty();var transparent:=bounded
	var cropped:=bounded;var resources:=bounded
	for id: String in entries:
		var spec: Dictionary=entries[id]
		match spec.category:
			"icon":icons+=1
			"control":controls+=1
			_:surfaces+=1
		var texture: Texture2D=load("res://ui_kit/assets/"+spec.sheet)
		var source: Image=texture.get_image()
		if source.is_compressed():source.decompress()
		var rect:=Rect2i(Vector2i.ZERO,source.get_size()) if spec.rect==null else Rect2i(spec.rect[0],spec.rect[1],spec.rect[2],spec.rect[3])
		bounded=bounded and Rect2i(Vector2i.ZERO,source.get_size()).encloses(rect) and rect.size.x>0 and rect.size.y>0
		transparent=transparent and source.detect_alpha()!=Image.ALPHA_NONE
		if spec.category in ["icon","control"]:
			var png_path: String="res://ui_kit/png/"+("icon_" if spec.category=="icon" else "control_")+id+".png"
			cropped=cropped and ResourceLoader.exists(png_path)
			if ResourceLoader.exists(png_path):
				var exported: Image=(load(png_path) as Texture2D).get_image()
				if exported.is_compressed():exported.decompress()
				cropped=cropped and exported.get_size()==rect.size and exported.get_data()==source.get_region(rect).get_data()
		if spec.category=="icon":resources=resources and ResourceLoader.exists("res://ui_kit/resources/icon_"+id+".tres")
	check("catalog covers 33 icons, 16 controls and 3 surfaces",icons==33 and controls==16 and surfaces==3)
	check("every catalog rectangle stays inside its original atlas",bounded)
	check("all nine source images preserve alpha",transparent)
	check("49 separate PNGs preserve the exact original region pixels",cropped)
	var illustrated:=not entries.is_empty()
	for id: String in entries:
		if entries[id].category!="icon":continue
		var icon: TextureRect=UITheme.icon(id,32)
		illustrated=illustrated and icon.texture is AtlasTexture and icon.texture.resource_name=="UIKitIcon/"+id
		icon.free()
	check("all 33 icons resolve through the shared game catalog",illustrated)
	check("editor theme and all icon resources can be loaded",resources and ResourceLoader.exists("res://ui_kit/resources/theme.res") and load("res://ui_kit/resources/theme.res") is Theme)
	var theme: Theme=UITheme.make()
	var state_styles:=true;var widths: Array[float]=[];var textures: Array[Texture2D]=[]
	for state: String in ["normal","hover","pressed","disabled"]:
		var style: StyleBox=theme.get_stylebox(state,"Button")
		state_styles=state_styles and style is StyleBoxTexture and style.resource_name=="UIKitStyle/secondary_"+state
		widths.append(style.get_minimum_size().x)
		if style is StyleBoxTexture:textures.append(style.texture)
	check("button states use four different generated artworks",state_styles and textures.size()==4 and textures[0]!=textures[1] and textures[1]!=textures[2] and textures[2]!=textures[3])
	check("hover, press and disable do not move button content",state_styles and widths.all(func(width: float):return is_equal_approx(width,widths[0])))
	var focus: StyleBox=theme.get_stylebox("focus","Button")
	check("keyboard focus has a visible outline without obscuring text",focus is StyleBoxFlat and not focus.draw_center and focus.get_border_width(SIDE_LEFT)>=2)
	var serialized:=not entries.is_empty()
	for role: String in ["primary","secondary"]:
		for state: String in ["normal","hover","pressed","disabled"]:
			var style_path: String="res://ui_kit/resources/button_"+role+"_"+state+".res"
			serialized=serialized and ResourceLoader.exists(style_path)
			if ResourceLoader.exists(style_path):serialized=serialized and (load(style_path) as StyleBox).resource_name=="UIKitStyle/"+role+"_"+state
	check("primary and secondary state resources are editor-ready",serialized)
	var track: StyleBox=ui.xp_bar.get_theme_stylebox("background")
	var fill: StyleBox=ui.xp_bar.get_theme_stylebox("fill")
	check("live HUD uses the shared generated progress skins",track.resource_name=="UIKitStyle/progress_track" and fill.resource_name=="UIKitStyle/progress_fill")
	var safe_bar:=track is StyleBoxTexture
	if safe_bar:safe_bar=track.get_texture_margin(SIDE_TOP)+track.get_texture_margin(SIDE_BOTTOM)<float(track.texture.get_height())
	check("thin progress strips leave a stretchable centre",safe_bar)
	ui.close_modal();ui.open_inventory();await t.frames(5)
	check("live backpack uses the shared generated item slots",skin_count(ui.modal_layer,"UIKitStyle/slot_")>=10)
	ui.close_modal();ui.panels.open_calendar();await t.frames(5)
	check("calendar highlights exactly one day with the shared selected skin",skin_count(ui.modal_layer,"UIKitStyle/slot_selected")==1 and skin_count(ui.modal_layer,"UIKitStyle/slot_normal")>=20)
	ui.close_modal();ui.toast("UI 素材库验证");await t.frames(3)
	check("live notifications use the shared generated notice card",skin_count(ui.root,"UIKitStyle/notice_info")>0)
	var coherent:=true
	for file: String in ["panels.gd","book.gd","ui_root.gd","hud_layout.gd","fishing_panel.gd","world_map_panel.gd","minimap.gd"]:
		var source:=FileAccess.get_file_as_string("res://scripts/ui/"+file)
		coherent=coherent and not source.contains("UITheme.box(") and not source.contains("StyleBoxFlat.new()")
	for file: String in ["minigame.gd","mg_onigiri.gd","mg_goldfish.gd","mg_puzzle.gd"]:
		var minigame_source:=FileAccess.get_file_as_string("res://scripts/minigames/"+file)
		coherent=coherent and not minigame_source.contains("UITheme.box(")
	check("game panels and minigame frames do not reintroduce local skins",coherent)
	ui.close_modal();await t.frames(3)
