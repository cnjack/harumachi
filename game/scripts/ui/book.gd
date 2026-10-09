class_name BookPanel
extends RefCounted
## v0.6 图鉴: achievements (成就), 晴町旧物 keepsakes, crops and dishes the player has made.
## Opened with K or from the pause menu; one modal with four tabs.

var ui: GameUI
var _tab := "notes"
var _body: Control
var _detail: Label
var _pic: TextureRect
var _count: Label
const TABS := [["notes", "手账"], ["ach", "成就"], ["col", "晴町旧物"], ["crops", "作物"], ["dishes", "料理"], ["fish", "鱼类"], ["homage", "远方小记"]]


func _init(root: GameUI) -> void:
	ui = root


func open(tab: String = "") -> void:
	if tab != "":
		_tab = tab
	var p := ui._open_modal("book")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(ui._header("晴町图鉴", "book"))
	var spc := Control.new()
	spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spc)
	_count = UITheme.label("", 22, UITheme.INK_SOFT)
	top.add_child(_count)
	v.add_child(top)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.custom_minimum_size = Vector2(130, 48)
		var tid: String = t[0]
		b.pressed.connect(func(): _set_tab(tid))
		tabs.add_child(b)
	v.add_child(tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(760, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	(_body as VBoxContainer).add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	row.add_child(sc)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	_pic = TextureRect.new()
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pic.custom_minimum_size = Vector2(340, 300)
	side.add_child(_pic)
	_detail = UITheme.label("", 21)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(340, 150)
	side.add_child(_detail)
	row.add_child(side)
	v.add_child(row)
	v.add_child(ui._close_button())
	_refresh()
	ui._center(p)


func _set_tab(t: String) -> void:
	_tab = t
	_refresh()


func _refresh() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		c.queue_free()
	_pic.texture = null
	_detail.text = ""
	var G := GameState
	match _tab:
		"notes":
			_notes()
		"ach":
			_count.text = "成就 %d / %d" % [Progress.count(), Progress.ach_db.size()]
			var grid := _grid(2)
			for a in Progress.ach_db:
				grid.add_child(_ach_row(a))
			_detail.text = "把鼠标移到一项上查看说明。没点亮的成就会显示进度。"
		"col":
			_count.text = "旧物 %d / %d" % [G.collection.size(), Progress.col_db.size()]
			var grid := _grid(4)
			for c in Progress.col_db:
				grid.add_child(_keepsake_tile(c))
			_detail.text = "找到的旧物收在这里。没见过的物件，先留一页空白。"
		"homage":
			_count.text = "小记 %d / %d" % [Homage.count(), Homage.entries().size()]
			var homage_grid := _grid(3)
			for entry: Dictionary in Homage.entries():
				homage_grid.add_child(_homage_tile(entry))
			_detail.text = "散步时留心那些不起眼的小东西。发现之前，只显示一条线索。"
		"crops":
			_count.text = "作物 %d / %d" % [G.zukan.crops.size(), G.crops_db.size()]
			var grid := _grid(5)
			for cid in G.crops_db:
				var n := int(G.zukan.crops.get(cid, 0))
				grid.add_child(_item_tile(cid, n > 0, "%s　收获过 %d 个" % [G.item_name(cid), n] if n > 0 else "还没种出来：%s级可以种" % str(G.crop_def(cid).get("level", 1))))
		"fish":
			_count.text="鱼类 %d / %d · 钓起 %d 条" % [G.fishing.caught.size(),G.fish_db.size(),int(G.fishing.landed)]
			var fish_grid:=_grid(3)
			for fish_id:String in G.fish_db:
				var definition:Dictionary=G.fish_db[fish_id]
				var caught:=int(G.fishing.caught.get(fish_id,0))
				var waters:Array=[]
				for habitat:String in definition.habitats:waters.append("晴川" if habitat=="river" else "镜波湖")
				var hours:Array=[]
				for interval:Array in definition.hours:hours.append("%02d:00–%02d:00" % [int(interval[0]),int(interval[1])])
				var detail:="%s\n%s\n常见时间：%s\n%s\n钓起 %d 条 · 最长 %.1f cm" % [G.item_name(fish_id)," / ".join(waters),"、".join(hours),definition.desc,caught,float(G.fishing.best_cm.get(fish_id,0))]
				fish_grid.add_child(_item_tile(fish_id,caught>0,detail))
		"dishes":
			_count.text = "料理 %d / %d" % [G.zukan.dishes.size(), G.recipes_db.size()]
			var grid := _grid(5)
			for rid in G.recipes_db:
				var r: Dictionary = G.recipes_db[rid]
				var out: String = r.output.keys()[0]
				var n := int(G.zukan.dishes.get(rid, 0))
				var where: String = {"kitchen": "家里的厨房", "oven": "莲的烤箱", "mill": "石磨"}.get(str(r.station), "")
				grid.add_child(_item_tile(out, n > 0, "%s　在%s做过 %d 次" % [G.item_name(out), where, n] if n > 0 else "还没做过（%s）" % where))


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	_body.add_child(g)
	return g


func _ach_row(a: Dictionary) -> Control:
	var got := Progress.has(a.id)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKitStyles.row("selected" if got else "disabled",6))
	p.custom_minimum_size = Vector2(370, 72)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var tr := TextureRect.new()
	tr.texture = load("res://assets/ui/badges/%s.png" % a.id) if ResourceLoader.exists("res://assets/ui/badges/%s.png" % a.id) else null
	tr.custom_minimum_size = Vector2(60, 60)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not got:
		tr.modulate = Color(0.35, 0.35, 0.35, 0.55)
	h.add_child(tr)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UITheme.label(str(a.name), 22, UITheme.INK if got else UITheme.INK_SOFT))
	var sub := str(a.desc)
	if got:
		sub = "第 %d 天达成 · %s" % [int(GameState.achievements[a.id]), a.desc]
	else:
		var pr := Progress.progress(a.id)
		if pr >= 0.0:
			sub += "（%d%%）" % int(pr * 100.0)
	var l := UITheme.label(sub, 17, UITheme.INK_SOFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(280, 0)
	v.add_child(l)
	h.add_child(v)
	p.mouse_entered.connect(func():
		_pic.texture = tr.texture
		_detail.text = "%s\n%s" % [a.name, sub])
	return p


func _keepsake_tile(c: Dictionary) -> Control:
	var got := Progress.found(c.id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(176, 176)
	var path := "res://assets/ui/collection/%s.jpg" % c.id
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if c.id == "col_photo_new" and FileAccess.file_exists(GameState.photo_path()):
		tex = ImageTexture.create_from_image(Image.load_from_file(GameState.photo_path()))
	b.icon = tex if got else null
	b.expand_icon = true
	b.text = "" if got else "？"
	b.tooltip_text = str(c.name) if got else "还没找到"
	var show := func():
		_pic.texture = tex if got else null
		_detail.text = "%s\n%s" % [c.name, c.text] if got else "这一页还空着。现在的约定和去处可以在 J 查看。"
		if got and c.id == "col_photo_new":
			_detail.text += "\n第 %d 天，和澪在水槽旁合影。" % int(GameState.flags.get("photo_taken_day", GameState.collection[c.id]))
	b.mouse_entered.connect(show)
	b.pressed.connect(show)
	return b

func _notes() -> void:
	_count.text = "已经经历的生活与记忆"
	var any_note := false
	for meal_note: String in NeighbourMeals.notes():
		any_note=true
		var meal_label:=UITheme.label(meal_note,24);meal_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(meal_label)
	if SummerProjects.phase() != "invitation":
		any_note = true
		var project_line := UITheme.label("一小篮的合作\n" + SummerProjects.notes(), 24)
		project_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(project_line)
	var workshop: Dictionary = WorkshopProject.state()
	if workshop.phase != "invitation":
		any_note = true
		var craft_note := UITheme.label("代表灯笼 · %s\n%s灯体；空决定用途；接头%d/3\n用途：%s；纸面：%s；现场：%s" % [{"assembly": "固定接头", "assembled": "待试挂", "tested": "试挂后待决定", "retained": "方案已收好"}.get(str(workshop.phase), "待商量"), "空组装" if workshop.maker == "player" else "街坊准备" if workshop.maker == "town" else "尚未完成", int(workshop.joints), "入口指路" if workshop.purpose == "guide" else "树下碰头", "榉叶" if workshop.pattern == "leaf" else "水纹", "已实际安装" if not workshop.installed.is_empty() else "尚未安装"], 24)
		craft_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(craft_note)
	for id: String in DailyLife.IDS:
		var life: Dictionary = DailyLife.event(id)
		if str(life.state) == "pending": continue
		any_note = true
		var line := DailyLife.title(id)
		if id == "meal" and DailyLife.done(id):
			line += " · 吃了一份，收好另一份" if life.get("ate", false) else " · 两份都包好了"
		elif id == "tea" and DailyLife.done(id):
			line += " · 和春一起喝过麦茶"
		elif id == "card" and DailyLife.done(id):
			var card_choice: int = int(life.get("choice", 2))
			line += {0: " · 帮莲扶正纸牌", 1: " · 尝过莲的小面包", 2: " · 和莲聊过纸牌", 3: " · 首次集市已经一起开过"}.get(card_choice, " · 记下了这次见面")
		else: line += " · " + DailyLife.hint(id)
		var label := UITheme.label(line, 24)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(label)
	for memory: Dictionary in StoryKnowledge.fragments():
		if not StoryKnowledge.presented(str(memory.id)): continue
		any_note = true
		var entry := Button.new()
		entry.text = "回想 · " + str(memory.title)
		entry.custom_minimum_size = Vector2(720, 58)
		entry.pressed.connect(func():
			_pic.texture = load("res://assets/ui/prologue/%s.jpg" % memory.img)
			_detail.text = str(memory.text))
		_body.add_child(entry)
	if not any_note:
		var empty_note := "刚到晴町。先把行李放好，给自己弄点吃的。" if GameState.qstate("Q00") != "done" else "手账还没记下新的生活片段。找到过的旧物可以在旁边查看。"
		_body.add_child(UITheme.label(empty_note, 24, UITheme.INK_SOFT))
	_detail.text = "生活里的选择慢慢记在这里。回想只翻看已经呈现的内容。"


func _item_tile(iid: String, got: bool, text: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(138, 110)
	var ic: String = str(GameState.item(iid).get("icon", iid))
	var p := "res://assets/ui/icons/%s.png" % ic
	b.icon = load(p) if ResourceLoader.exists(p) else null
	b.expand_icon = true
	b.text = GameState.item_name(iid) if got else "？"
	if not got:
		b.modulate = Color(0.5, 0.5, 0.5, 0.7)
	b.mouse_entered.connect(func():
		_pic.texture = b.icon if got else null
		_detail.text = text)
	return b


func _homage_tile(entry: Dictionary) -> Control:
	var got := Homage.found(str(entry.id))
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(235, 176)
	var texture: Texture2D = load(Homage.image_path(entry)) if got else null
	tile.tooltip_text = str(entry.name) if got else "还没发现"
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8
	content.offset_right = -8
	content.offset_top = 8
	content.offset_bottom = -8
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(content)
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(210, 112)
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(picture)
	var caption := UITheme.label(str(entry.name) if got else "？", 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(caption)
	var show := func():
		_pic.texture = texture
		_detail.text = "%s\n%s\n\n远方回声：%s" % [entry.name, entry.text, entry.source] if got else "还没发现。线索：%s" % str(entry.where)
	tile.mouse_entered.connect(show)
	tile.pressed.connect(show)
	return tile
