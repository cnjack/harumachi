extends Control
## Same assets and factories as the game, also runnable in the standalone kit.
var _body: VBoxContainer
var _title: Label
var _page := 0
var _tabs: Array[Button] = []
const PAGES := ["组件与状态","图标素材","组合示例"]

func _ready() -> void:
	theme=UIKitStyles.theme();set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Color(.78,.84,.77);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var card:=PanelContainer.new();card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left=42;card.offset_right=-42;card.offset_top=30;card.offset_bottom=-30;add_child(card)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",18);card.add_child(column)
	var heading:=HBoxContainer.new();heading.add_theme_constant_override("separation",14);column.add_child(heading)
	heading.add_child(UIKitComponents.icon("map",46));heading.add_child(UIKitComponents.label("晴町和纸 UI 素材库","title"))
	var gap:=Control.new();gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(gap)
	heading.add_child(UIKitComponents.label("v1.0  ·  32 图标 / 16 控件底图 / 3 背景","caption",UIKitTokens.MUTED))
	var tabs:=HBoxContainer.new();tabs.add_theme_constant_override("separation",12);column.add_child(tabs)
	for index in PAGES.size():
		var id:=index
		var button:=UIKitComponents.button(PAGES[index],func():show_page(id),"primary" if index==0 else "secondary")
		button.custom_minimum_size.x=230;tabs.add_child(button)
		_tabs.append(button)
	_title=UIKitComponents.label("","section");column.add_child(_title)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	_body=VBoxContainer.new();_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_body.add_theme_constant_override("separation",18);scroll.add_child(_body)
	column.add_child(UIKitComponents.label("原始 PNG 保留透明通道  ·  统一色彩 / 字号 / 间距  ·  状态素材与游戏共享","caption",UIKitTokens.MUTED))
	show_page(0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--kit-gallery-out="):capture(argument.substr(18));break

func show_page(index: int) -> void:
	_page=index;_title.text=PAGES[index]
	for tab_index in _tabs.size():
		UIKitComponents.style_button(_tabs[tab_index],"primary" if tab_index==index else "secondary")
	for child: Node in _body.get_children():child.free()
	match index:
		0:primitives()
		1:icons()
		2:recipes()

func caption(text: String) -> void:
	_body.add_child(UIKitComponents.label(text,"body",UIKitTokens.MUTED))

func primitives() -> void:
	caption("按钮状态：普通 / 悬停 / 按下 / 禁用（键盘焦点另有金色轮廓）")
	for role: String in ["primary","secondary"]:
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",16);_body.add_child(row)
		for state: String in ["normal","hover","pressed","disabled"]:
			var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(250,64);panel.add_theme_stylebox_override("panel",UIKitStyles.button(role,state))
			var label:=UIKitComponents.label(("主要" if role=="primary" else "次要")+" · "+state,"body");label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			panel.add_child(label);row.add_child(panel)
	caption("物品格与语义状态")
	var slots:=HBoxContainer.new();slots.add_theme_constant_override("separation",20);_body.add_child(slots)
	for state: String in ["normal","selected","disabled","empty"]:
		var column:=VBoxContainer.new();slots.add_child(column)
		var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(96,96);panel.add_theme_stylebox_override("panel",UIKitStyles.slot(state));column.add_child(panel)
		if state!="empty":panel.add_child(UIKitComponents.icon("florist" if state=="selected" else "coin",56))
		column.add_child(UIKitComponents.label(state,"caption"))
	var bars:=VBoxContainer.new();bars.custom_minimum_size.x=380;slots.add_child(bars)
	for colour: Color in [UIKitTokens.SAGE,UIKitTokens.GOLD,UIKitTokens.CORAL]:
		var bar:=UIKitComponents.progress(360,18,colour);bar.value=62;bars.add_child(bar)
	caption("提示卡与文字层级")
	var notices:=HBoxContainer.new();notices.add_theme_constant_override("separation",20);_body.add_child(notices)
	for tone: String in ["info","warning"]:
		var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(400,90);panel.add_theme_stylebox_override("panel",UIKitStyles.notice(tone));notices.add_child(panel)
		var label:=UIKitComponents.label("已收进背包" if tone=="info" else "鱼线张力偏高，请松开收线","body");label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(label)
	var typography:=HBoxContainer.new();typography.add_theme_constant_override("separation",24);_body.add_child(typography)
	for role: String in ["caption","body","section","title"]:typography.add_child(UIKitComponents.label(role+" 晴町",role))

func icons() -> void:
	var grid:=GridContainer.new();grid.columns=8;grid.add_theme_constant_override("h_separation",16);grid.add_theme_constant_override("v_separation",18);_body.add_child(grid)
	for id: String in UIKitCatalog.ENTRIES:
		if UIKitCatalog.ENTRIES[id][2]!="icon":continue
		var column:=VBoxContainer.new();column.custom_minimum_size=Vector2(180,105);grid.add_child(column)
		column.add_child(UIKitComponents.icon(id,56));var text:=UIKitComponents.label(id,"caption",UIKitTokens.MUTED);text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;column.add_child(text)

func recipes() -> void:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",24);_body.add_child(row)
	var inventory:=PanelContainer.new();inventory.custom_minimum_size=Vector2(660,480);inventory.add_theme_stylebox_override("panel",UIKitStyles.surface());row.add_child(inventory)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",16);inventory.add_child(body)
	body.add_child(UIKitComponents.label("背包","title"));body.add_child(UIKitComponents.label("同一套按钮、物品格、图标与间距","caption",UIKitTokens.MUTED))
	var tabs:=HBoxContainer.new();body.add_child(tabs)
	for name: String in ["全部","种子","作物"]:tabs.add_child(UIKitComponents.button(name,Callable(),"primary" if name=="全部" else "secondary",true))
	var items:=GridContainer.new();items.columns=5;items.add_theme_constant_override("h_separation",12);items.add_theme_constant_override("v_separation",12);body.add_child(items)
	for index in 10:
		var slot:=PanelContainer.new();slot.custom_minimum_size=Vector2(96,96);slot.add_theme_stylebox_override("panel",UIKitStyles.slot("selected" if index==1 else ("normal" if index<4 else "empty")));items.add_child(slot)
		if index<4:slot.add_child(UIKitComponents.icon(["coin","florist","gift","fish"][index],58))
	body.add_child(UIKitComponents.button("收起背包",Callable(),"secondary"))
	var side:=VBoxContainer.new();side.custom_minimum_size.x=560;side.add_theme_constant_override("separation",16);row.add_child(side)
	for spec: Array in [["今日委托","去水岸看看钓点"],["16:20 · 晴","镜波湖 · 芦苇东岸"]]:
		var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",UIKitStyles.surface("hud",24));side.add_child(panel)
		var text:=VBoxContainer.new();text.add_child(UIKitComponents.label(spec[0],"section"));text.add_child(UIKitComponents.label(spec[1],"body",UIKitTokens.MUTED));panel.add_child(text)
	var message:=PanelContainer.new();message.add_theme_stylebox_override("panel",UIKitStyles.notice());side.add_child(message);message.add_child(UIKitComponents.label("获得 2 条香鱼 · 可以出售或做料理","body"))
	var ring:=TextureRect.new();ring.texture=UIKitAssets.artwork("minimap_ring");ring.custom_minimum_size=Vector2(200,200);ring.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;ring.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;side.add_child(ring)

func capture(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for index in PAGES.size():
		show_page(index)
		for frame in 25:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("%02d.png"%index))
	get_tree().quit()
