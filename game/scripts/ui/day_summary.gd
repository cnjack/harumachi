class_name DaySummary
extends CanvasLayer
signal dismissed
var report: Dictionary={}
var _done:=false

static func capture() -> Dictionary:
	return {"day":GameState.day,"date":GameState.date_text(),"income":int(GameState.ledger.get("in",0)),"expense":int(GameState.ledger.get("out",0)),"xp":int(GameState.daily.get("xp",0)),"sold":GameState.daily.get("sold_n",{}).duplicate(true),"fish":GameState.daily.get("fish_items",{}).duplicate(true),"harvest":GameState.daily.get("harvest_items",{}).duplicate(true),"talked":GameState.daily.get("talked",{}).size(),"gifted":GameState.daily.get("gifted",{}).size()}

func setup(snapshot: Dictionary) -> void:
	report=snapshot.duplicate(true);layer=30
	var root:=Control.new();root.theme=UITheme.make();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(root)
	var shade:=ColorRect.new();shade.color=Color(.055,.12,.21,.91);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(shade)
	var centre:=CenterContainer.new();centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(centre)
	var card:=PanelContainer.new();card.custom_minimum_size=Vector2(760,0);card.add_theme_stylebox_override("panel",UITheme.paper("modal",32));centre.add_child(card)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",16);card.add_child(body)
	var header:=HBoxContainer.new();header.add_child(UITheme.icon("w_night",58));header.add_child(UITheme.label(str(report.date)+"  ·  今日手账",32));body.add_child(header)
	var earnings:=HBoxContainer.new();earnings.add_theme_constant_override("separation",26);body.add_child(earnings)
	earnings.add_child(UITheme.icon("coin",46));earnings.add_child(UITheme.label("+%d"%int(report.income),42,UITheme.GOOD))
	earnings.add_child(UITheme.label("−%d"%int(report.expense),28,UITheme.INK_SOFT));earnings.add_child(UITheme.label("结余 %d"%(int(report.income)-int(report.expense)),26))
	for spec: Array in [["farm","收获",report.harvest],["fish","鱼获",report.fish],["store","售出",report.sold]]:
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);body.add_child(row)
		row.add_child(UITheme.icon(str(spec[0]),34));row.add_child(UITheme.label(str(spec[1]),23))
		var values: Dictionary=spec[2]
		var count:=0
		for item_id: String in values:
			count+=1
			if count>5:continue
			row.add_child(UITheme.icon(item_id,32));row.add_child(UITheme.label("×%d"%int(values[item_id]),22))
		if values.is_empty():row.add_child(UITheme.label("—",24,UITheme.INK_SOFT))
		if values.size()>5:row.add_child(UITheme.label("+%d 种"%(values.size()-5),20))
	var neighbours:=HBoxContainer.new();neighbours.add_theme_constant_override("separation",10);body.add_child(neighbours)
	neighbours.add_child(UITheme.icon("heart",32));neighbours.add_child(UITheme.label("街坊 %d  ·  赠礼 %d"%[int(report.talked),int(report.gifted)],23))
	neighbours.add_child(UITheme.icon("level_badge",32));neighbours.add_child(UITheme.label("+%d XP"%int(report.xp),24))
	var button:=Button.new();button.text="晚安   ↵";button.custom_minimum_size.y=50;UIKitComponents.style_button(button,"primary");body.add_child(button)
	button.pressed.connect(finish);button.grab_focus()
	card.modulate.a=0;card.create_tween().tween_property(card,"modulate:a",1.0,.6)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_SPACE,KEY_ESCAPE]:
		get_viewport().set_input_as_handled();finish()

func finish() -> void:
	if _done:return
	_done=true;dismissed.emit();queue_free()
