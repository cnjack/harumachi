extends RefCounted
var t: Node
var ui: Node
var _choice_result := -1
func _init(runner: Node) -> void:
	t=runner;ui=runner.main.ui
func check(name: String,ok: bool) -> void:
	t.check("DIALOGUE_UI",name,ok)
func contains_notice(root: Node,key: String,value: String) -> bool:
	for child: Node in root.get_children():
		if child.get_meta(key,"")==value:return true
	return false
func record_choice() -> void:
	_choice_result=await ui.choose(["留下聊聊","先去新家"])
func key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
		ui.get_viewport().push_input(event,true)
		await t.frames(2)
func run() -> void:
	ui.dialogue_end();ui.close_modal()
	var old_instant: bool=ui.instant;var old_auto: bool=ui.auto
	var old_hud: bool=ui.hud.visible;var old_place: bool=ui.place_bar.visible
	var card_box: Control=ui.panels.get("_card_box")
	var old_cards: bool=card_box.visible
	var tag_states: Array[Dictionary]=[]
	for neighbour: NPC in NPC.everyone:
		if is_instance_valid(neighbour) and is_instance_valid(neighbour.tag):tag_states.append({"tag":neighbour.tag,"visible":neighbour.tag.visible})
	if not tag_states.is_empty():tag_states[0].tag.visible=false
	ui.instant=false;ui.auto=false;ui.set_hud_visible(true);ui.panels.set_cards_visible(true)
	ui.toast("对话前已有的提示");ui.panels.card("对话前已有的卡片",["应在对话中隐藏"],"","",60)
	ui.place_bar.visible=true
	ui.dialogue_begin();ui.dialogue_begin();await t.frames(3)
	check("dialogue hides quest, resources, clock and shortcut HUD",not ui.objective_panel.is_visible_in_tree() and not ui.resource_panel.is_visible_in_tree() and not ui.clock_panel.is_visible_in_tree() and not ui.shortcuts_bar.is_visible_in_tree())
	check("portrait area is clear of minimap and movement hints",not ui.minimap.is_visible_in_tree() and not ui.hint_label.is_visible_in_tree())
	check("existing toast cards and placement bar stay hidden",not ui.toast_box.is_visible_in_tree() and not card_box.is_visible_in_tree() and not ui.place_bar.is_visible_in_tree())
	check("floating NPC names are hidden while talking",not tag_states.is_empty() and tag_states.all(func(entry: Dictionary):return not entry.tag.is_visible_in_tree()))
	ui.refresh_hud();ui.set_hud_visible(true);await t.frames(6)
	check("HUD refresh cannot show overlays during dialogue",not ui.hud.is_visible_in_tree() and not ui.minimap.is_visible_in_tree())
	ui.toast("对话期间收到的礼物");ui.toast("对话期间收到的礼物")
	ui.panels.card("对话期间的新成就",["结束后再显示"],"","",60)
	check("new rewards and achievement cards are deferred",not contains_notice(ui.toast_box,"text","对话期间收到的礼物") and not contains_notice(card_box,"title","对话期间的新成就"))
	ui.dialogue_end();await t.frames(2)
	var gifts:=0
	for child: Node in ui.toast_box.get_children():
		if child.get_meta("text","")=="对话期间收到的礼物":gifts+=1
	check("dialogue end replays a deferred toast once",gifts==1)
	check("dialogue end replays the deferred achievement card",contains_notice(card_box,"title","对话期间的新成就"))
	var tags_restored:=not tag_states.is_empty()
	for index in tag_states.size():tags_restored=tags_restored and tag_states[index].tag.visible==(false if index==0 else tag_states[index].visible)
	check("repeated begin preserves prior hidden NPC names on restore",tags_restored)
	ui.instant=true
	await ui.say("mio","neutral","只显示头像与对话框。")
	check("direct say also isolates dialogue and keeps its portrait",ui.dlg.is_visible_in_tree() and ui.dlg_portrait.is_visible_in_tree() and not ui.hud.is_visible_in_tree())
	ui.dialogue_end();ui.instant=false
	record_choice();await t.frames(3)
	check("a new choice-only conversation cannot reuse the prior speaker portrait or line",not ui.dlg_portrait.visible and ui.dlg_portrait.texture==null and not ui.dlg_name_panel.visible and ui.dlg_name.text=="" and ui.dlg_text.text=="")
	check("choice-only dialogue retains visible keyboard focus",ui.dlg_choices.is_visible_in_tree() and ui.dlg_choices.is_ancestor_of(ui.get_viewport().gui_get_focus_owner()) and not ui.hud.is_visible_in_tree())
	await key(KEY_M);await key(KEY_TAB)
	check("map and backpack shortcuts do not open during dialogue",ui.modal=="" and GameState.input_locked())
	await key(KEY_2);await t.frames(2)
	check("number key selects the second visible dialogue choice",_choice_result==1)
	ui.dialogue_end();ui.instant=true
	var fixture_who: String="ren"
	await ui.say(fixture_who,"happy","我把三明治放在这边。你想带走，还是现在尝？")
	var current_texture: Texture2D=ui.dlg_portrait.texture
	ui.instant=false;record_choice();await t.frames(3)
	check("a choice after a line in the same conversation retains its current speaker and question",ui.dlg_name.text=="莲" and ui.dlg_text.text=="我把三明治放在这边。你想带走，还是现在尝？" and ui.dlg_portrait.texture==current_texture and ui.dlg_portrait.visible)
	await key(KEY_2);await t.frames(2)
	ui.dialogue_end();ui.set_hud_visible(false);ui.panels.set_cards_visible(false)
	ui.dialogue_begin();ui.dialogue_end()
	check("dialogue end preserves HUD hidden by a cutscene",not ui.hud.visible and not card_box.visible and not ui.dlg_choices.visible)
	for entry: Dictionary in tag_states:
		if is_instance_valid(entry.tag):entry.tag.visible=entry.visible
	# These fixtures use long lifetimes; dispose their tweens before the runner exits.
	for card: Node in card_box.get_children():
		if card.get_meta("title","") in ["对话前已有的卡片","对话期间的新成就"]:
			(ui.panels.get("_cards") as Array).erase(card)
			card.queue_free()
	await t.frames(4)
	ui.instant=old_instant;ui.auto=old_auto;ui.set_hud_visible(old_hud);ui.panels.set_cards_visible(old_cards);ui.place_bar.visible=old_place
