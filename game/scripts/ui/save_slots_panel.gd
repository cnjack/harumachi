class_name SaveSlotsPanel
extends VBoxContainer
signal slot_chosen(slot: int)
signal cancelled
var mode: String="load"
var pending_slot:=0
var status: Label
var buttons: Array[Button]=[]
var rows: Array[Dictionary]=[]

func setup(action: String) -> void:
	mode=action;name="SaveSlotsPanel";custom_minimum_size=Vector2(840,0);add_theme_constant_override("separation",14)
	var heading:=UITheme.label({"load":"读取存档","save":"保存进度","new":"选择新旅程的位置"}.get(mode,"存档"),34);add_child(heading)
	status=UITheme.label("每日结束会自动保存到当前的位置",21,UITheme.INK_SOFT);add_child(status)
	var grid:=GridContainer.new();grid.name="SlotGrid";grid.columns=2;grid.add_theme_constant_override("h_separation",16);grid.add_theme_constant_override("v_separation",14);add_child(grid)
	rows=SaveDB.list_slots()
	for record: Dictionary in rows:
		var slot:=int(record.slot);var box:=PanelContainer.new();box.name="SlotCard_%d"%slot;box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_stylebox_override("panel",UIKitStyles.row("normal",18));grid.add_child(box)
		var content:=VBoxContainer.new();content.custom_minimum_size=Vector2(380,0);content.add_theme_constant_override("separation",8);box.add_child(content)
		content.add_child(UITheme.label("%02d%s"%[slot,"  ·  当前" if slot==SaveDB.active_slot else ""],24,UITheme.INK))
		var description: String="空位置"
		if not bool(record.empty):
			var minutes:=int(record.get("minute",480));description="第 %d 天  ·  %02d:%02d  ·  %d 币"%[int(record.day),int(minutes/60.0),minutes%60,int(record.coins)]
			if not bool(record.get("valid",false)):description="存档无法读取 · 可选择覆盖"
		content.add_child(UITheme.label(description,21,UITheme.INK_SOFT))
		var button:=Button.new();button.name="SlotButton_%d"%slot;button.custom_minimum_size=Vector2(380,48)
		button.text="读取" if mode=="load" else ("开始" if mode=="new" else "存入")
		button.disabled=mode=="load" and (bool(record.empty) or not bool(record.get("valid",false)))
		button.pressed.connect(_choose.bind(slot));content.add_child(button);buttons.append(button)
	var cancel:=Button.new();cancel.name="SlotsCancel";cancel.text="返回  Esc";cancel.custom_minimum_size.y=48;cancel.pressed.connect(func():cancelled.emit());add_child(cancel)
	var first: Button=null
	for button: Button in buttons:
		if not button.disabled:first=button;break
	(first if first else cancel).call_deferred("grab_focus")

func _choose(slot: int) -> void:
	var row: Dictionary=rows[slot-1]
	if mode!="load" and not bool(row.empty) and pending_slot!=slot:
		pending_slot=slot;status.text="再次点击确认覆盖位置 %02d 的进度"%slot;buttons[slot-1].text="确认覆盖";return
	slot_chosen.emit(slot)
