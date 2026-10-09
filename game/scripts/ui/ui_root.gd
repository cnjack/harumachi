class_name GameUI
extends CanvasLayer
## All in-game UI built in code: HUD, dialogue, inventory, quests, shop, notice board,
## pause/settings, placement bar, ending card, toasts and fades.
## Dialogue and panels are coroutines (await ui.say(...)), which keeps story scripts linear.

signal dialogue_advance
signal choice_made(index: int)
signal panel_closed
signal ending_chosen(action: String)
signal place_item_selected(item_id: String)
signal title_requested

const SPEAKERS := {
	"mio": "澪", "ren": "莲", "haru": "春", "sora": "我", "tanaka": "田中爷爷", "aoi": "小葵",
	"florist": "花店的千代", "zakka": "杂货铺的阿健", "narrator": "", "kazuko": "和子阿姨",
}

var root := Control.new()
var ambient_layer := Control.new()
var conversation_active := false
var _pending_toasts: Array[String] = []
var _dialogue_tags: Array[Dictionary] = []
var auto := false
var auto_work_priority := false
var instant := false   # tests: dialogue and panels resolve on the next frame
var auto_choices: Array = []
var modal := ""
var panels: GamePanels
var book: BookPanel
var minimap: GameMinimap
var world_main: Node
var _fishing_tags: Array[Dictionary]=[]
var fishing_panel: FishingPanel
var level_label: Label
var xp_bar: ProgressBar
var weather_icon: TextureRect
var fest_label: Label
var coin_pop: Label
var map_destination: Dictionary={}
var map_panel: WorldMapPanel
var objective_panel: PanelContainer
var resource_panel: PanelContainer
var clock_panel: PanelContainer
var shortcuts_bar: PanelContainer
var date_label: Label

# HUD
var hud := Control.new()
var obj_title: Label
var obj_text: Label
var coin_label: Label
var token_label: Label
var area_label: Label
var clock_label: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var hint_label: Label
var toast_box: VBoxContainer
# dialogue
var dlg: Control
var dlg_name_panel: PanelContainer
var dlg_name: Label
var dlg_text: RichTextLabel
var dlg_portrait: TextureRect
var dlg_choices: VBoxContainer
var dlg_arrow: Label
var _typing: Tween
var _dlg_shown_at := 0
# modal panels
var modal_layer := Control.new()
var dim: ColorRect
var fade: ColorRect
var place_bar: PanelContainer
var place_items: HBoxContainer
var place_msg: Label
var place_hint: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.theme = UITheme.make()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	ambient_layer.name = "AmbientUI"
	ambient_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	ambient_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ambient_layer)
	_build_hud()
	_build_dialogue()
	_build_place_bar()
	dim = ColorRect.new()
	dim.color = Color(0.10, 0.18, 0.15, 0.38)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	root.add_child(dim)
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(modal_layer)
	fade = ColorRect.new()
	fade.color = Color(0.06, 0.05, 0.08, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	panels = GamePanels.new(self)
	book = BookPanel.new(self)
	Progress.unlocked.connect(_on_achievement)
	Progress.keepsake_found.connect(_on_keepsake)
	GameState.state_changed.connect(refresh_hud)
	GameState.toast.connect(toast)
	GameState.coins_changed.connect(_coin_popup)
	GameState.level_up.connect(_on_level_up)
	GameState.time_changed.connect(func(_m): refresh_clock())
	refresh_hud()


## Offsets are relative to the anchors, so this stays correct whatever size the parent has now.
## (Setting .position is parent-relative and breaks centred, grow-both panels.)
static func _dock(c: Control, left: float, right: float, top: float) -> void:
	c.offset_left = left
	c.offset_right = right
	c.offset_top = top
	c.offset_bottom = top


# ================================================================== HUD
func _build_hud() -> void:
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ambient_layer.add_child(hud)
	HUDLayout.build(self)


func refresh_clock() -> void:
	var G := GameState
	clock_label.text = G.clock_text()
	date_label.text = "%s · %s · %s" % [G.date_text(), G.weekday_name(), G.weather_name()]
	var night := G.hour() >= 19.4 or G.hour() < 5.5
	var fid := G.festival_on(G.day)
	var ic := "w_festival" if G.festival_now() != "" else ("w_rain" if G.weather == "rain" else ("w_night" if night else ("w_cloudy" if G.weather == "cloudy" else "w_sunny")))
	if weather_icon:
		weather_icon.texture = UITheme.icon_texture(ic)
	if fest_label:
		fest_label.visible = fid != ""
		if fid != "":
			var f := G.festival(fid)
			fest_label.text = "今天：%s %02d:%02d–%02d:%02d" % [f.name, int(f.start), int(fmod(float(f.start), 1.0) * 60), int(f.end), int(fmod(float(f.end), 1.0) * 60)]


func _on_level_up(lv: int, perks: Array) -> void:
	panels.card("种植等级 %d！" % lv, perks.map(func(x): return "解锁：" + str(x)), "level_badge", "", 6.0)
	Audio.sting("quest_done")


func _coin_popup(delta: int) -> void:
	if coin_pop == null or not hud.visible:
		return
	coin_pop.text = ("+%d" % delta) if delta > 0 else ("%d" % delta)
	coin_pop.add_theme_color_override("font_color", UITheme.GOOD if delta > 0 else UITheme.BAD)
	coin_pop.position = Vector2(80, resource_panel.position.y + 8)
	coin_pop.modulate.a = 1.0
	var tw := coin_pop.create_tween().set_parallel(true)
	tw.tween_property(coin_pop, "position:y", resource_panel.position.y - 20, 1.2)
	tw.tween_property(coin_pop, "modulate:a", 0.0, 1.2).set_delay(0.4)


func refresh_hud() -> void:
	refresh_clock()
	var q := GameState.tracked_quest
	obj_title.text = "「%s」" % GameState.quest_title(q) if q != "" and GameState.qstate(q) == "active" else ("集市进行中" if GameState.phase == "market" else "晴町的日常")
	obj_text.text = GameState.objective_text()
	if SummerProjects.state().tracked:
		obj_title.text = "一小篮的合作"
		obj_text.text = SummerProjects.hint()
	var request: Dictionary = GameState.request()
	if GameState.flags.get("request_tracked", false) and not request.is_empty() and not request.get("done", false):
		obj_title.text = "街坊的小事 · %s" % GameState.npc_display(str(request.who))
		obj_text.text = "%s ×%d · 可交 %d · 改天也行" % [GameState.item_name(str(request.item)), int(request.n), mini(GameState.unreserved_count(str(request.item)), int(request.n))]
	var life_id: String = str(DailyLife.state().tracked)
	if life_id != "" and not DailyLife.done(life_id):
		obj_title.text = DailyLife.title(life_id)
		var house_room: String = world_main.world.house.current_room if world_main != null and world_main.in_room and world_main.room_kind == "house" else ""
		obj_text.text = DailyLife.hint(life_id, house_room)
	coin_label.text = "%d" % GameState.coins
	token_label.text = "%d / 3" % GameState.count("support_token")
	if SummerProjects.uses_cooperation_mainline():
		token_label.text = "试吃 %d / 2" % SummerProjects.current_batch().get("tasters", {}).size() if not SummerProjects.opening().batches.is_empty() else "准备一小篮"
		token_label.tooltip_text = "两位试吃 → 决定份量 → 实际试走 → 开摊招待"
	if level_label:
		var pr := GameState.level_progress()
		level_label.text = "Lv%d" % GameState.level()
		xp_bar.max_value = maxi(1, int(pr[1]))
		xp_bar.value = int(pr[0]) if int(pr[1]) > 0 else 1


func set_area(text: String) -> void:
	if area_label.text != text:
		area_label.text = text


func set_prompt(text: String) -> void:
	prompt_panel.visible = text != "" and dlg != null and not dlg.visible and modal == ""
	if text != "":
		prompt_label.text = "[E] " + text


func set_hud_visible(v: bool) -> void:
	hud.visible = v


func toast(text: String) -> void:
	if conversation_active:
		if not _pending_toasts.has(text):_pending_toasts.append(text)
		while _pending_toasts.size()>5:_pending_toasts.pop_front()
		return
	for c in toast_box.get_children():
		if c.has_meta("text") and c.get_meta("text") == text and not c.is_queued_for_deletion():
			return
	var p := PanelContainer.new()
	p.set_meta("text", text)
	p.add_theme_stylebox_override("panel", UIKitStyles.notice())
	var l := UITheme.label(text, 22, UIKitTokens.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(425, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).free()
	var tw := p.create_tween()
	p.modulate.a = 0.0
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


# ================================================================== dialogue
func _build_dialogue() -> void:
	dlg = Control.new()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.visible = false
	root.add_child(dlg)
	dlg_portrait = TextureRect.new()
	dlg_portrait.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dlg_portrait.position = Vector2(120, -660)
	dlg_portrait.size = Vector2(420, 420)
	dlg_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dlg_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dlg_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.add_child(dlg_portrait)
	var panel := PanelContainer.new()
	panel.name = "DialogueCard"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dock(panel, -760, 760, -280)
	panel.custom_minimum_size = Vector2(1520, 240)
	panel.add_theme_stylebox_override("panel", UITheme.paper("modal",36))
	panel.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_advance())
	dlg.add_child(panel)
	var tv := VBoxContainer.new()
	panel.add_child(tv)
	dlg_text = RichTextLabel.new()
	dlg_text.bbcode_enabled = true
	dlg_text.fit_content = true
	dlg_text.scroll_active = false
	dlg_text.custom_minimum_size = Vector2(1400, 150)
	dlg_text.add_theme_font_size_override("normal_font_size", 32)
	dlg_text.add_theme_constant_override("line_separation", 10)
	dlg_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(dlg_text)
	dlg_arrow = UITheme.label("▼  E / 点击 继续", 20, UITheme.INK_SOFT)
	dlg_arrow.size_flags_horizontal = Control.SIZE_SHRINK_END
	tv.add_child(dlg_arrow)
	dlg_name_panel = PanelContainer.new()
	dlg_name_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dlg_name_panel.position = Vector2(-720, -318)
	dlg_name_panel.add_theme_stylebox_override("panel", UITheme.paper("hud",22))
	dlg_name = UITheme.label("", 30, UITheme.INK)
	dlg_name_panel.add_child(dlg_name)
	dlg.add_child(dlg_name_panel)
	dlg_choices = VBoxContainer.new()
	dlg_choices.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dlg_choices.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dlg_choices.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dock(dlg_choices, -700, -140, -330)
	dlg_choices.custom_minimum_size = Vector2(560, 0)
	dlg_choices.add_theme_constant_override("separation", 10)
	dlg_choices.visible = false
	dlg.add_child(dlg_choices)


func dialogue_begin() -> void:
	GameState.lock_input("dialogue")
	if conversation_active:return
	conversation_active = true
	# A fresh entry may open straight into choices. Only this boundary clears
	# context; choices following a line in the same conversation retain it.
	if _typing:_typing.kill()
	dlg_text.text=""
	dlg_text.visible_ratio=1.0
	dlg_name.text=""
	dlg_name_panel.visible=false
	dlg_portrait.texture=null
	dlg_portrait.visible=false
	(dlg.get_node("DialogueCard") as Control).visible=false
	ambient_layer.visible = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused and ambient_layer.is_ancestor_of(focused):focused.release_focus()
	_dialogue_tags.clear()
	for neighbour: NPC in NPC.everyone:
		if is_instance_valid(neighbour) and is_instance_valid(neighbour.tag):
			_dialogue_tags.append({"node":neighbour.tag,"visible":neighbour.tag.visible})
			neighbour.tag.visible = false


func dialogue_end() -> void:
	dlg.visible = false
	dlg_choices.visible = false
	if _typing:_typing.kill()
	Audio.stop_voice()
	GameState.unlock_input("dialogue")
	if not conversation_active:return
	conversation_active = false
	ambient_layer.visible = true
	for entry: Dictionary in _dialogue_tags:
		if is_instance_valid(entry.node):entry.node.visible = entry.visible
	_dialogue_tags.clear()
	var queued: Array[String] = _pending_toasts.duplicate()
	_pending_toasts.clear()
	for text: String in queued:toast(text)
	panels.flush_dialogue_cards()


func say(who: String, mood: String, text: String) -> void:
	dialogue_begin()
	dlg.visible = true
	(dlg.get_node("DialogueCard") as Control).visible=true
	prompt_panel.visible = false
	var nm: String = SPEAKERS.get(who, who)
	dlg_name_panel.visible = nm != ""
	dlg_name.text = nm
	var por := "res://assets/ui/portraits/%s_%s.png" % [who, mood]
	dlg_portrait.visible = ResourceLoader.exists(por)
	if dlg_portrait.visible:
		dlg_portrait.texture = load(por)
	dlg_text.text = text
	if instant:
		dlg_text.visible_ratio = 1.0
		await get_tree().process_frame
		return
	var vlen := Audio.voice(who, text)
	dlg_text.visible_characters = 0
	dlg_arrow.visible = false
	dlg_choices.visible = false
	var n := dlg_text.get_total_character_count()
	if _typing:
		_typing.kill()
	_typing = create_tween()
	_typing.tween_property(dlg_text, "visible_characters", n, n * 0.028)
	_typing.tween_callback(func(): dlg_arrow.visible = true)
	_dlg_shown_at = Time.get_ticks_msec()
	if auto:
		# the autoplay waits for the voice to finish before it moves on
		get_tree().create_timer(maxf(1.0 + n * 0.042, vlen + 0.45)).timeout.connect(func(): _finish_and_emit(), CONNECT_ONE_SHOT)
	await dialogue_advance


func _finish_and_emit() -> void:
	if _typing:
		_typing.kill()
	dlg_text.visible_ratio = 1.0
	Audio.ui("next")
	dialogue_advance.emit()


func _advance() -> void:
	if not dlg.visible or dlg_choices.visible:
		return
	if Time.get_ticks_msec() - _dlg_shown_at < 150:
		return
	if _typing and _typing.is_running():
		_typing.kill()
		dlg_text.visible_ratio = 1.0
		dlg_arrow.visible = true
		return
	Audio.ui("next")
	dialogue_advance.emit()


func choose(options: Array) -> int:
	dialogue_begin()
	dlg.visible = true
	(dlg.get_node("DialogueCard") as Control).visible=not dlg_text.text.is_empty()
	dlg_arrow.visible = false
	for c in dlg_choices.get_children():
		c.queue_free()
	var i := 0
	var first: Button = null
	for o in options:
		var b := Button.new()
		b.text = "%d.  %s" % [i + 1, o]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 28)
		var idx := i
		b.pressed.connect(func(): choice_made.emit(idx))
		dlg_choices.add_child(b)
		if first == null:
			first = b
		i += 1
	dlg_choices.visible = true
	if instant:
		await get_tree().process_frame
		dlg_choices.visible = false
		return auto_choices.pop_front() if not auto_choices.is_empty() else 0
	if first:
		first.call_deferred("grab_focus")
	if auto:
		var pick: int = auto_choices.pop_front() if not auto_choices.is_empty() else 0
		get_tree().create_timer(1.0).timeout.connect(func(): choice_made.emit(pick), CONNECT_ONE_SHOT)
	var r: int = await choice_made
	dlg_choices.visible = false
	return r


## Short keyboard-friendly pages keep every inventory choice reachable.
func choose_paged(options: Array, cancel_text: String = "算了") -> int:
	var offset := 0
	while true:
		var page: Array = options.slice(offset, offset + 4)
		var count_on_page: int = page.size()
		var next_index := -1
		var previous_index := -1
		if offset + count_on_page < options.size():
			next_index = page.size()
			page.append("下一页")
		if offset > 0:
			previous_index = page.size()
			page.append("上一页")
		page.append(cancel_text)
		var selected: int = await choose(page)
		if selected >= 0 and selected < count_on_page:
			return offset + selected
		if selected == next_index and next_index >= 0:
			offset += 4
		elif selected == previous_index and previous_index >= 0:
			offset = maxi(0, offset - 4)
		else:
			return -1
	return -1


# ================================================================== modal helpers
func _open_modal(name_id: String, lock: bool = true) -> PanelContainer:
	close_modal(false)
	if name_id != "ending":
		Audio.ui("open")
	modal = name_id
	dim.visible = true
	if lock:
		GameState.lock_input("modal")
	prompt_panel.visible = false
	var p := PanelContainer.new()
	_anchor_center(p)
	modal_layer.add_child(p)
	if name_id in ["inventory","calendar","settings"]:
		p.add_child(UIKitComponents.resting_cat(76,.52 if name_id=="inventory" else .80))
	return p


## Centre a panel on the screen whatever its final size is: anchors and pivot at the centre,
## zero offsets and growth in both directions, so each time the container's minimum size
## changes (it is only known after its children are sorted, possibly several frames later,
## and differently while the tree is paused) it expands evenly around the middle.
func _anchor_center(p: Control) -> void:
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = 0.0
	p.offset_top = 0.0
	p.offset_right = 0.0
	p.offset_bottom = 0.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH


func _center(p: Control) -> void:
	if not is_instance_valid(p):
		return
	_anchor_center(p)
	p.reset_size()


func close_modal(emit: bool = true) -> void:
	for c in modal_layer.get_children():
		c.queue_free()
	var was := modal
	modal = ""
	dim.visible = false
	GameState.unlock_input("modal")
	if was in ["pause","save_slots"]:
		get_tree().paused = false
	if emit and was != "":
		Audio.ui("close")
		panel_closed.emit()


func _header(text: String, icon_id: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	if icon_id != "":
		h.add_child(UITheme.icon(icon_id, 52))
	h.add_child(UITheme.label(text, 38))
	return h


func _close_button(text: String = "关闭") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func(): close_modal())
	return b


func _unhandled_input(event: InputEvent) -> void:
	if dlg.visible:
		if event.is_action_pressed("interact") and not event.is_echo():
			get_viewport().set_input_as_handled()
			if dlg_choices.visible:
				var f := get_viewport().gui_get_focus_owner()
				if f is Button and dlg_choices.is_ancestor_of(f):
					(f as Button).pressed.emit()
			else:
				_advance()
		elif event is InputEventKey and event.pressed and dlg_choices.visible:
			var k := (event as InputEventKey).keycode
			if k >= KEY_1 and k <= KEY_9 and k - KEY_1 < dlg_choices.get_child_count():
				get_viewport().set_input_as_handled()
				Audio.ui("click")
				choice_made.emit(k - KEY_1)
		return
	if modal != "":
		if modal in ["ending", "minigame", "fishing", "arrival_retry"]:
			return
		if event.is_action_pressed("pause") or event.is_action_pressed("cancel") \
				or (modal == "inventory" and event.is_action_pressed("inventory")) \
				or (modal == "quests" and event.is_action_pressed("quests")) \
				or (modal == "calendar" and event.is_action_pressed("calendar")) \
				or (modal == "book" and event.is_action_pressed("book")) \
				or (modal == "map" and event.is_action_pressed("world_map")):
			get_viewport().set_input_as_handled()
			close_modal()
		return
	if GameState.input_locked():
		return
	if event.is_action_pressed("world_map"):
		get_viewport().set_input_as_handled()
		open_world_map()
	elif event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		open_inventory()
	elif event.is_action_pressed("quests"):
		get_viewport().set_input_as_handled()
		open_quests()
	elif event.is_action_pressed("calendar"):
		get_viewport().set_input_as_handled()
		panels.open_calendar()
	elif event.is_action_pressed("book"):
		get_viewport().set_input_as_handled()
		book.open()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		open_pause()


func setup_world_map(main: Node) -> void:
	world_main=main
	minimap=GameMinimap.new()
	hud.add_child(minimap)
	minimap.setup(main)

func open_world_map() -> void:
	if world_main==null or GameState.input_locked():return
	var panel:=_open_modal("map")
	map_panel=WorldMapPanel.new();panel.add_child(map_panel);map_panel.setup(self);_center(panel)

func open_fishing(spot: String,view: FishingView) -> void:
	close_modal(false)
	modal="fishing";dim.visible=false;GameState.lock_input("modal")
	ambient_layer.visible=false
	_fishing_tags.clear()
	for npc: NPC in world_main.npcs.values():_fishing_tags.append({"tag":npc.tag,"shown":npc.tag.visible});npc.tag.visible=false
	prompt_panel.visible=false
	fishing_panel=FishingPanel.new();modal_layer.add_child(fishing_panel);fishing_panel.setup(spot,view)
	await fishing_panel.closed
	fishing_panel=null
	for entry: Dictionary in _fishing_tags:
		if is_instance_valid(entry.tag):entry.tag.visible=entry.shown
	_fishing_tags.clear()
	ambient_layer.visible=true
	close_modal()

# ================================================================== v0.6 achievements & keepsakes
func _on_achievement(id: String) -> void:
	if Progress.quiet:
		return
	var a: Dictionary = Progress.ach_by_id.get(id, {})
	Audio.sting("fanfare")
	panels.card("成就解锁：%s" % a.get("name", id), [str(a.get("desc", "")), "按 K 打开图鉴查看。"], "res://assets/ui/badges/%s.png" % id, "", 5.0)


func _on_keepsake(id: String) -> void:
	if Progress.quiet:
		return
	var c := Progress.keepsake(id)
	Audio.sting("item")
	panels.card("找到晴町旧物：%s" % c.get("name", id), ["已收进图鉴的“晴町旧物”一栏（K）。"], "res://assets/ui/collection/%s.jpg" % id, "", 5.0)


# ================================================================== notice board
func show_notice(title: String, lines: Array, footer: String = "") -> void:
	var p := _open_modal("notice")
	p.add_theme_stylebox_override("panel", UITheme.paper("modal",44))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	v.add_child(_header(title, "checklist"))
	for ln in lines:
		var l := UITheme.label(str(ln), 28)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(820, 0)
		v.add_child(l)
	if footer != "":
		v.add_child(UITheme.label(footer, 22, UITheme.INK_SOFT))
	var b := _close_button("好的")
	v.add_child(b)
	b.call_deferred("grab_focus")
	_center(p)
	if instant:
		await get_tree().process_frame
		close_modal(false)
		return
	if auto:
		get_tree().create_timer(2.2).timeout.connect(func(): if modal == "notice": close_modal(), CONNECT_ONE_SHOT)
	await panel_closed


# ================================================================== inventory
func open_inventory() -> void:
	panels.open_bag()


func _slot(id: String, n: int, desc: Label, size: int) -> PanelContainer:
	var s := PanelContainer.new()
	s.custom_minimum_size = Vector2(size, size)
	s.add_theme_stylebox_override("panel", UIKitStyles.slot("normal" if id!="" else "empty"))
	if id == "":
		return s
	var it := GameState.item(id)
	var ov := Control.new()
	s.add_child(ov)
	var ic := UITheme.icon(str(it.get("icon", id)), size - 16)
	ov.add_child(ic)
	if n > 1:
		var c := UITheme.label("×%d" % n, 22)
		c.position = Vector2(size - 54, size - 40)
		ov.add_child(c)
	s.tooltip_text = str(it.get("name", id))
	s.mouse_entered.connect(func(): desc.text = "%s — %s" % [it.get("name", id), it.get("desc", "")])
	return s


# ================================================================== quests
func open_quests() -> void:
	var p := _open_modal("quests")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(_header("委托", "quest"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(380, 0)
	list.add_theme_constant_override("separation", 8)
	var quest_scroll := ScrollContainer.new()
	quest_scroll.custom_minimum_size = Vector2(400, 480)
	quest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	quest_scroll.add_child(list)
	h.add_child(quest_scroll)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(620, 480)
	detail.add_theme_constant_override("separation", 10)
	h.add_child(detail)
	var shown := 0
	var first_btn: Button = null
	var request: Dictionary = GameState.request()
	if GameState.qstate("Q01") == "done":
		var project_button := Button.new()
		project_button.text = "一小篮的合作 · " + ("尚未商量" if SummerProjects.phase() == "invitation" else "已完成" if SummerProjects.phase() == "done" else "进行中")
		project_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		project_button.pressed.connect(func(): _project_detail(detail))
		project_button.focus_entered.connect(func(): _project_detail(detail))
		list.add_child(project_button)
		if SummerProjects.state().tracked or first_btn == null: first_btn = project_button
		shown += 1
	if not request.is_empty():
		var request_button := Button.new()
		request_button.text = "街坊的小事 · %s\n%s ×%d" % [("已交付" if request.get("done", false) else GameState.npc_display(str(request.who))), GameState.item_name(str(request.item)), int(request.n)]
		request_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		request_button.pressed.connect(func(): _request_detail(detail))
		request_button.focus_entered.connect(func(): _request_detail(detail))
		list.add_child(request_button)
		first_btn = request_button
		shown += 1
	for life_id: String in DailyLife.IDS:
		var life_event: Dictionary = DailyLife.event(life_id)
		if GameState.qstate("Q00") != "done" or GameState.day < int(DailyLife.state().introduced_day) + int(DailyLife.DAYS[life_id]):
			continue
		var life_button := Button.new()
		var life_tag := "已完成" if DailyLife.done(life_id) else ("改天也行" if str(life_event.state) == "pending" else "在做的生活小事")
		life_button.text = "%s · %s" % [DailyLife.title(life_id), life_tag]
		life_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var selected_life: String = life_id
		life_button.pressed.connect(func(): _life_detail(detail, selected_life))
		life_button.focus_entered.connect(func(): _life_detail(detail, selected_life))
		list.add_child(life_button)
		if first_btn == null or str(DailyLife.state().tracked) == life_id:
			first_btn = life_button
		shown += 1
	for q in GameState.quest_order:
		var st := GameState.qstate(q)
		if st == "locked":
			continue
		var tag: String = {"available": "可接受", "active": "进行中", "done": "已完成"}.get(st, st)
		var b := Button.new()
		b.text = "%s  ·  %s" % [GameState.quest_title(q), tag]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var qid: String = q
		b.pressed.connect(func(): _quest_detail(detail, qid))
		b.focus_entered.connect(func(): _quest_detail(detail, qid))
		list.add_child(b)
		if first_btn == null or (q == GameState.tracked_quest and not GameState.flags.get("request_tracked", false) and str(DailyLife.state().tracked) == "" and not SummerProjects.state().tracked):
			first_btn = b
		shown += 1
	if shown == 0:
		list.add_child(UITheme.label("还没有委托。", 24, UITheme.INK_SOFT))
	v.add_child(_close_button())
	if first_btn:
		first_btn.call_deferred("grab_focus")
		first_btn.pressed.emit()
	_center(p)


func _quest_detail(box: VBoxContainer, qid: String) -> void:
	for c in box.get_children():
		c.queue_free()
	var q: Dictionary = GameState.quests_db[qid]
	box.add_child(UITheme.label(str(q.title), 34))
	var giver: String = SPEAKERS.get(str(q.get("giver", "")), "")
	if giver != "":
		box.add_child(UITheme.label("委托人：" + giver, 22, UITheme.INK_SOFT))
	var st := GameState.qstate(qid)
	if GameState.flags.get("town_finished_" + qid, false):
		box.add_child(UITheme.label("街坊已完成这项准备。", 22, UITheme.INK_SOFT))
	var cur := GameState.qstep(qid)
	var i := 0
	for s in q.steps:
		var done := st == "done" or (st == "active" and i < cur)
		var now := st == "active" and i == cur
		var mark := "✓ " if done else ("▶ " if now else "· ")
		var l := UITheme.label(mark + (GameState.quest_step_text(qid) if now else GameState.quest_step_description(qid, i)), 25, UITheme.GOOD if done else (UITheme.INK if now else UITheme.INK_SOFT))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(600, 0)
		box.add_child(l)
		i += 1
	var r: Dictionary = q.get("rewards", {})
	var parts := []
	for id in r.get("key_items", {}):
		parts.append(GameState.item_name(id))
	for id in r.get("items", {}):
		parts.append(GameState.item_name(id))
	if int(r.get("coins", 0)) > 0:
		parts.append("%d 生活币" % int(r.coins))
	if not parts.is_empty():
		box.add_child(UITheme.label("报酬：" + "、".join(parts), 22, UITheme.INK_SOFT))
	if st == "available":
		var b := Button.new()
		b.text = "接受委托"
		b.custom_minimum_size = Vector2(200, 54)
		b.pressed.connect(func():
			GameState.flags.erase("request_tracked")
			GameState.start_quest(qid)
			_quest_detail(box, qid))
		box.add_child(b)
	elif st == "active" and (SummerProjects.state().tracked or GameState.tracked_quest != qid or GameState.flags.get("request_tracked", false) or str(DailyLife.state().tracked) != ""):
		var t := Button.new()
		t.text = "设为追踪"
		t.custom_minimum_size = Vector2(200, 54)
		t.pressed.connect(func():
			GameState.track_quest(qid)
			GameState.save_game()
			_quest_detail(box, qid))
		box.add_child(t)


func _life_detail(box: VBoxContainer, id: String) -> void:
	for child in box.get_children():
		child.queue_free()
	box.add_child(UITheme.label(DailyLife.title(id), 34))
	var description := UITheme.label("做完后的小物和聊天会留下来。" if DailyLife.done(id) else DailyLife.hint(id), 25)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(600, 0)
	box.add_child(description)
	box.add_child(UITheme.label("不必赶在今天，也可以先去忙自己的事。", 22, UITheme.INK_SOFT))
	if not DailyLife.done(id):
		var track := Button.new()
		track.text = "去看看 · 设为追踪"
		track.custom_minimum_size = Vector2(260, 54)
		track.pressed.connect(func():
			DailyLife.track(id)
			GameState.save_game())
		box.add_child(track)


func _request_detail(box: VBoxContainer) -> void:
	for child in box.get_children():
		child.queue_free()
	box.add_child(UITheme.label("街坊的小事", 34))
	for line in GameState.request_lines():
		var label := UITheme.label(line, 25)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(600, 0)
		box.add_child(label)
	var request: Dictionary = GameState.request()
	if not request.is_empty() and not request.get("done", false):
		var track := Button.new()
		track.text = "带齐后当面交 · 设为追踪"
		track.pressed.connect(func():
			DailyLife.clear_tracking()
			SummerProjects.clear_tracking()
			GameState.flags["request_tracked"] = true
			GameState.state_changed.emit())
		box.add_child(track)


# ================================================================== shop
var _shop_rows: VBoxContainer
var _shop_ids: Array = []
var _shop_status: Label
var _shop_money: Label


func open_shop(title: String, keeper: String, line: String, ids: Array) -> void:
	var p := _open_modal("shop")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(_header(title, "coin"))
	v.add_child(UITheme.label("%s：「%s」" % [keeper, line], 24, UITheme.INK_SOFT))
	_shop_rows = VBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 10)
	v.add_child(_shop_rows)
	_shop_ids = ids
	_shop_status = UITheme.label("", 24)
	_shop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_status.custom_minimum_size = Vector2(860, 0)
	_shop_money = UITheme.label("", 24)
	_shop_refresh()
	v.add_child(_shop_money)
	v.add_child(_shop_status)
	var cb := _close_button("走了")
	v.add_child(cb)
	cb.call_deferred("grab_focus")
	_center(p)
	if instant:
		await get_tree().process_frame
		var buys: Array = auto_choices.pop_front() if not auto_choices.is_empty() else []
		for id in buys:
			shop_buy(id)
		close_modal(false)
		return
	if auto:
		get_tree().create_timer(1.6).timeout.connect(_shop_auto, CONNECT_ONE_SHOT)
	await panel_closed


func _shop_auto() -> void:
	if modal != "shop":
		return
	var buys: Array = auto_choices.pop_front() if not auto_choices.is_empty() else []
	for id in buys:
		shop_buy(id)
	get_tree().create_timer(1.6).timeout.connect(func(): if modal == "shop": close_modal(), CONNECT_ONE_SHOT)


func shop_buy(id: String) -> void:
	var err := GameState.buy(id)
	_shop_status.text = ("买好了：%s（在庭院布置区按 B 摆放）" % GameState.item_name(id)) if err == "" else err
	_shop_status.add_theme_color_override("font_color", UITheme.GOOD if err == "" else UITheme.BAD)
	_shop_refresh()


func _shop_refresh() -> void:
	for c in _shop_rows.get_children():
		c.queue_free()
	var kinds := GameState.decor_kinds()
	_shop_money.text = "现有 %d 生活币 · 装饰最多选两种（已有：%s）" % [GameState.coins, "、".join(kinds.map(func(k): return GameState.item_name(k))) if not kinds.is_empty() else "无"]
	for id in _shop_ids:
		var it := GameState.item(id)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIKitStyles.row("normal",14))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		row.add_child(h)
		h.add_child(UITheme.icon(str(it.get("icon", id)), 84))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UITheme.label("%s   %d 生活币" % [it.name, int(it.get("price", 0))], 28))
		var d := UITheme.label(str(it.get("desc", "")), 21, UITheme.INK_SOFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(520, 0)
		tv.add_child(d)
		h.add_child(tv)
		var b := Button.new()
		b.text = "买下"
		b.custom_minimum_size = Vector2(130, 56)
		var iid: String = id
		b.pressed.connect(func(): shop_buy(iid))
		h.add_child(b)
		_shop_rows.add_child(row)


# ================================================================== pause / settings
func open_save_slots(mode: String) -> void:
	var panel:=_open_modal("save_slots");get_tree().paused=true
	var slots:=SaveSlotsPanel.new();panel.add_child(slots);slots.setup(mode)
	slots.cancelled.connect(close_modal)
	slots.slot_chosen.connect(func(slot: int):
		if mode=="save":
			if GameState.save_to_slot(slot):Audio.sting("save");close_modal()
			else:slots.status.text=GameState.last_error
		else:
			if GameState.load_slot(slot):
				GameState.clock_paused = false
				GameState.load_on_enter=true;close_modal(false);get_tree().paused=false
				Loading.change_scene("res://scenes/main.tscn","回到晴町")
			else:slots.status.text=GameState.last_error)


func open_pause() -> void:
	var p := _open_modal("pause")
	get_tree().paused = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(460, 0)
	p.add_child(v)
	v.add_child(_header("暂停", "settings"))
	var info := UITheme.label("游玩时间 %s" % _fmt_time(GameState.play_time), 22, UITheme.INK_SOFT)
	v.add_child(info)
	var status := UITheme.label("", 22)
	var mk := func(t: String, f: Callable) -> Button:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(420, 58)
		b.pressed.connect(f)
		v.add_child(b)
		return b
	var first: Button = mk.call("继续", func(): close_modal())
	mk.call("保存进度", func(): open_save_slots("save"))
	mk.call("读取进度", func(): open_save_slots("load"))
	mk.call("设置", func(): open_settings())
	mk.call("日历与节日", func(): panels.open_calendar())
	mk.call("晴町图鉴", func(): book.open())
	mk.call("小游戏记录", func(): open_minigame_records())
	mk.call("回到标题", func():
		close_modal(false)
		get_tree().paused = false
		title_requested.emit())
	mk.call("退出游戏", func(): get_tree().quit())
	v.add_child(status)
	first.call_deferred("grab_focus")
	_center(p)

func open_arrival_retry(retry: Callable) -> void:
	var panel: PanelContainer = _open_modal("arrival_retry")
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	content.add_child(_header("搬入进度尚未保存", "settings"))
	var message := UITheme.label(GameState.last_error + "\n这次搬入没有完成。重试会接着当前阶段继续。", 24)
	message.custom_minimum_size = Vector2(660, 0)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message)
	var again := Button.new(); again.text = "重试保存并继续搬入"; again.custom_minimum_size.y = 58
	again.pressed.connect(func(): close_modal(false); retry.call_deferred(false))
	content.add_child(again)
	var back := Button.new(); back.text = "回到标题"; back.custom_minimum_size.y = 58
	back.pressed.connect(func(): close_modal(false); title_requested.emit())
	content.add_child(back)
	again.call_deferred("grab_focus")
	_center(panel)


func open_settings() -> void:
	var was_pause := modal == "pause"
	var p := _open_modal("settings")
	if was_pause:
		get_tree().paused = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.custom_minimum_size = Vector2(620, 0)
	p.add_child(v)
	v.add_child(_header("设置", "settings"))
	build_settings_rows(v)
	var b := _close_button("完成")
	b.pressed.connect(func():
		if was_pause:
			open_pause.call_deferred())
	v.add_child(b)
	_center(p)


static func build_settings_rows(v: VBoxContainer) -> void:
	var s: Dictionary = GameState.settings
	var slider := func(label_text: String, key: String, lo: float, hi: float, step: float, pct := false):
		var h := HBoxContainer.new()
		var l := UITheme.label(label_text, 26)
		l.custom_minimum_size = Vector2(220, 0)
		h.add_child(l)
		var sl := HSlider.new()
		sl.min_value = lo
		sl.max_value = hi
		sl.step = step
		sl.value = float(s.get(key, 1.0))
		sl.custom_minimum_size = Vector2(300, 40)
		var fmt := func(x: float) -> String: return ("%d%%" % roundi(x * 100.0)) if pct else ("%.1f" % x)
		var val := UITheme.label(fmt.call(sl.value), 24)
		sl.value_changed.connect(func(x):
			val.text = fmt.call(x)
			s[key] = x
			GameState.save_settings())
		h.add_child(sl)
		h.add_child(val)
		v.add_child(h)
	slider.call("界面缩放", "text_scale", 0.8, 1.4, 0.1)
	slider.call("鼠标灵敏度", "mouse_sens", 0.3, 2.0, 0.1)
	slider.call("总音量", "vol_master", 0.0, 1.0, 0.05, true)
	slider.call("音乐", "vol_music", 0.0, 1.0, 0.05, true)
	slider.call("音效与环境声", "vol_sfx", 0.0, 1.0, 0.05, true)
	slider.call("角色语音", "vol_voice", 0.0, 1.0, 0.05, true)
	for pair in [["反转垂直视角", "invert_y"], ["全屏", "fullscreen"]]:
		var cb := CheckBox.new()
		cb.text = pair[0]
		cb.button_pressed = bool(s.get(pair[1], false))
		var key: String = pair[1]
		cb.toggled.connect(func(on):
			s[key] = on
			GameState.save_settings())
		v.add_child(cb)


static func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	return "%d 分 %02d 秒" % [m, int(t) % 60]


# ================================================================== placement bar
func _build_place_bar() -> void:
	place_bar = PanelContainer.new()
	place_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	place_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dock(place_bar, -700, 700, -250)
	place_bar.custom_minimum_size = Vector2(1400, 0)
	place_bar.visible = false
	ambient_layer.add_child(place_bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	place_bar.add_child(v)
	var h := HBoxContainer.new()
	h.add_child(UITheme.label("布置模式", 30))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(24, 0)
	h.add_child(sp)
	place_msg = UITheme.label("", 26)
	h.add_child(place_msg)
	v.add_child(h)
	place_items = HBoxContainer.new()
	place_items.add_theme_constant_override("separation", 12)
	v.add_child(place_items)
	place_hint = UITheme.label("鼠标选位置 · 左键放下 · Q / E 旋转 · 1-5 换物品 · F 收回鼠标下的物件 · Z 撤销 · 右键 / Esc 退出", 21, UITheme.INK_SOFT)
	v.add_child(place_hint)


func show_placement(entries: Array, selected: String) -> void:
	place_bar.visible = true
	hud.visible = false
	for c in place_items.get_children():
		c.queue_free()
	var i := 1
	for e in entries:
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 72)
		b.icon = load("res://assets/ui/icons/%s.png" % GameState.item(e.id).get("icon", e.id))
		b.expand_icon = true
		b.text = "%d %s ×%d" % [i, GameState.item_name(e.id), e.n]
		b.toggle_mode = true
		b.button_pressed = e.id == selected
		b.focus_mode = Control.FOCUS_NONE
		var id: String = e.id
		b.pressed.connect(func(): place_item_selected.emit(id))
		place_items.add_child(b)
		i += 1
	if entries.is_empty():
		place_items.add_child(UITheme.label("背包里没有可摆放的东西了。可以把鼠标移到已放的物件上按 F 收回。", 24, UITheme.INK_SOFT))


func set_place_message(text: String, ok: bool) -> void:
	place_msg.text = text
	place_msg.add_theme_color_override("font_color", UITheme.GOOD if ok else UITheme.BAD)


func hide_placement() -> void:
	place_bar.visible = false
	hud.visible = true


# ================================================================== ending
func show_ending(lines: Array) -> String:
	var p := _open_modal("chapter_summary")
	p.add_theme_stylebox_override("panel", UITheme.paper("modal",56))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.custom_minimum_size = Vector2(900, 0)
	p.add_child(v)
	var t := UITheme.label("第一场集市 · 试营业结束", 46)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for ln in lines:
		var l := UITheme.label(str(ln), 27)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(880, 0)
		v.add_child(l)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	for pair in [["继续夏季生活", "continue"], ["保存后回标题", "title"]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(240, 62)
		var act: String = pair[1]
		b.pressed.connect(func():
			close_modal(false)
			ending_chosen.emit(act))
		h.add_child(b)
		if act == "continue":
			b.call_deferred("grab_focus")
	v.add_child(h)
	_center(p)
	if instant:
		await get_tree().process_frame
		close_modal(false)
		return "continue"
	if auto:
		get_tree().create_timer(6.0).timeout.connect(func():
			if modal == "chapter_summary":
				close_modal(false)
				ending_chosen.emit("continue"), CONNECT_ONE_SHOT)
	var r: String = await ending_chosen
	return r


# ================================================================== mini-games
var mg_skill := 0.85          # tests (instant mode): skill passed to MiniGame.run_instant
var active_mg: MiniGame


## Run one mini-game full screen until the player leaves. Returns the last round's result.
func play_minigame(id: String, context: Dictionary = {}) -> Dictionary:
	var path := "res://scripts/minigames/mg_%s.gd" % id
	if not ResourceLoader.exists(path):
		return {"id": id, "completed": false, "score": 0, "stars": 0}
	close_modal(false)
	var mg: MiniGame = load(path).new()
	mg.id = id
	mg.name = "MiniGame_" + id
	mg.auto = auto
	mg.context = context.duplicate(true)
	mg.best = int(GameState.mg_record(id).best)
	if str(context.get("mode", "free")) == "free":
		mg.reward_cb = func(game_id: String, points: int, stars: int) -> Dictionary:
			return GameState.record_minigame(game_id, points, stars, mg.mg_outcome())
	modal = "minigame"
	GameState.lock_input("modal")
	hud.visible = false
	prompt_panel.visible = false
	dlg.visible = false
	active_mg = mg
	root.add_child(mg)
	root.move_child(mg, fade.get_index())
	var mute := bool(mg.info.get("mute_bgm", false))
	var prev_music := Audio.music_name
	if mute and not instant:
		Audio.stop_music(0.8)
	var res: Dictionary
	if instant:
		await get_tree().process_frame
		res = mg.run_instant(mg_skill)
	else:
		res = await mg.closed
	mg.queue_free()
	active_mg = null
	modal = ""
	GameState.unlock_input("modal")
	hud.visible = true
	if mute and prev_music != "" and not instant:
		Audio.play_music(prev_music, 1.5)
	refresh_hud()
	return res


func open_book(tab: String = "") -> void:
	book.open(tab)


func open_book_col() -> void:
	book.open("col")


func open_minigame_records() -> void:
	var was_pause := modal == "pause"
	var p := _open_modal("records")
	if was_pause:
		get_tree().paused = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(760, 0)
	p.add_child(v)
	v.add_child(_header("遇见的活动", "quest"))
	v.add_child(UITheme.label("自由练习共 %d 颗星 · 生活里的成果另外记在手账" % GameState.mg_total_stars(), 22, UITheme.INK_SOFT))
	var known_count := 0
	for id in GameState.MINIGAMES:
		if not StoryKnowledge.activity_known(id): continue
		known_count += 1
		var inf: Dictionary = GameState.MINIGAMES[id]
		var rec := GameState.mg_record(id)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIKitStyles.row("normal",14))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		row.add_child(h)
		var ic := TextureRect.new()
		var ip := "res://assets/minigames/%s/icon.png" % id
		if ResourceLoader.exists(ip):
			ic.texture = load(ip)
		ic.custom_minimum_size = Vector2(64, 64)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(ic)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UITheme.label(str(inf.name), 28))
		tv.add_child(UITheme.label(str(inf.place), 20, UITheme.INK_SOFT))
		h.add_child(tv)
		var st := int(rec.stars)
		h.add_child(UITheme.label("★".repeat(st) + "☆".repeat(3 - st), 34, UITheme.ACCENT))
		var bl := UITheme.label(("最好 %d" % int(rec.best)) if int(rec.plays) > 0 else "还没玩过", 22, UITheme.INK_SOFT)
		bl.custom_minimum_size = Vector2(130, 0)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(bl)
		v.add_child(row)
	if known_count == 0:
		v.add_child(UITheme.label("还没有记下活动。先在晴町走走，看看桌面和摊位上的东西。", 24, UITheme.INK_SOFT))
	var b := _close_button("好的")
	b.pressed.connect(func():
		if was_pause:
			open_pause.call_deferred())
	v.add_child(b)
	b.call_deferred("grab_focus")
	_center(p)


# ================================================================== v0.6 chapter titles and the camera flash
## A chapter title across the middle of the screen (non-blocking, about 4 s).
func chapter_card(title: String, sub: String = "") -> void:
	var band := ColorRect.new()
	band.color = Color(0.08, 0.07, 0.09, 0.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.36
	band.anchor_bottom = 0.64
	ambient_layer.add_child(band)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(v)
	var t := UITheme.label(title, 64, Color(1.0, 0.96, 0.88))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if sub != "":
		var l := UITheme.label(sub, 28, Color(0.95, 0.88, 0.74))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	v.modulate.a = 0.0
	Audio.sting("sparkle")
	var tw := band.create_tween()
	tw.set_parallel(true)
	tw.tween_property(band, "color:a", 0.62, 0.7)
	tw.tween_property(v, "modulate:a", 1.0, 0.9)
	tw.chain().tween_interval(0.2 if instant else 3.0)
	tw.chain().set_parallel(true)
	tw.tween_property(band, "color:a", 0.0, 0.8)
	tw.tween_property(v, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(band.queue_free)


## A white camera flash.
func flash() -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.9)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.5)
	tw.tween_callback(r.queue_free)


# ================================================================== fades
func fade_out(t: float = 0.45) -> void:
	if instant:
		t = 0.01
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, t)
	await tw.finished


func fade_in(t: float = 0.45) -> void:
	if instant:
		t = 0.01
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, t)
	await tw.finished
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

func celebrate(title: String, icon_id: String, detail: String="") -> void:
	if instant:return
	var burst:=Celebration.new();root.add_child(burst);burst.setup(title,icon_id,detail)

func _project_detail(box: VBoxContainer) -> void:
	for child in box.get_children(): child.queue_free()
	box.add_child(UITheme.label("一小篮的合作", 34))
	var note := UITheme.label(SummerProjects.notes(), 23)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(600, 0)
	box.add_child(note)
	var button := Button.new()
	button.text = "先放下追踪" if SummerProjects.state().tracked else "继续这件事 · 设为追踪"
	button.custom_minimum_size = Vector2(280, 54)
	button.pressed.connect(func():
		if SummerProjects.state().tracked: SummerProjects.clear_tracking()
		else: SummerProjects.track()
		GameState.state_changed.emit()
		GameState.save_game()
		_project_detail(box))
	box.add_child(button)
