extends Node
## Fixture: starting inventory, poses and weather. All UI actions use real input events.
var main: Node
var folder := ""
var failures: Array[String]=[]
var checks: Array[Dictionary]=[]

func _ready() -> void:
	main=get_parent()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-demo-out="):folder=argument.substr(14)
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(40)
	for i in 1200:
		if not Loading.active and not GameState.input_locked():break
		await frames(1)
	if OS.get_cmdline_user_args().has("--ui-dialogue-demo"):
		await run_dialogue()
		return
	await run()

var _conversation_done := false
var _selected_choice := -1
func conversation() -> void:
	main.ui.dialogue_begin()
	await main.ui.say("mio","neutral","先回家放下行李吧！钥匙就在门口的信箱里。")
	_selected_choice=await main.ui.choose(["再聊一会儿","先去新家看看"])
	await main.ui.say("mio","happy","好呀，等你安顿好了，我们再慢慢聊。")
	main.ui.dialogue_end()
	_conversation_done=true

func run_dialogue() -> void:
	GameState.clock_paused=true;main.ui.auto=false;main.ui.instant=false
	main.ui.toast("对话开始前的提示");main.ui.panels.card("今日小记",["对话时也应隐藏这张卡片。"],"","",30)
	main.player.global_position=main.npcs.mio.global_position+Vector3(0,0,2)
	main.rig.yaw=185;main.rig.pitch=18;main.rig.dist=7;main.rig.snap()
	conversation();await frames(15)
	main.ui.toast("礼物已收进背包");main.ui.panels.card("新发现",["这张卡片在对话结束后出现。"],"","",30)
	verify("dialogue hides the HUD, minimap, notifications and floating names",not main.ui.hud.is_visible_in_tree() and not (main.ui.panels.get("_card_box") as Control).is_visible_in_tree() and main.npcs.values().all(func(neighbour: NPC):return not neighbour.tag.is_visible_in_tree()))
	await shot("01_dialogue_clean")
	var card: Control=main.ui.dlg.get_node("DialogueCard")
	await click(card);await click(card)
	verify("mouse advances dialogue to visible choices",main.ui.dlg_choices.visible)
	await shot("02_dialogue_choices")
	await key(KEY_2)
	verify("keyboard selects the second dialogue option",_selected_choice==1)
	await shot("03_dialogue_reply")
	await key(KEY_E);await key(KEY_E)
	verify("ending dialogue restores the HUD and input",_conversation_done and main.ui.hud.is_visible_in_tree() and not GameState.input_locked())
	verify("deferred reward messages appear after dialogue",main.ui.toast_box.get_children().any(func(child: Node):return child.get_meta("text","")=="礼物已收进背包") and (main.ui.panels.get("_card_box") as Control).get_children().any(func(child: Node):return child.get_meta("title","")=="新发现"))
	await shot("04_hud_restored")
	finish()

func frames(count: int=10) -> void:
	for i in count:await get_tree().process_frame

func verify(name: String,ok: bool) -> void:
	checks.append({"name":name,"passed":ok})
	if not ok:failures.append(name)
	print("UI_DEMO ",name," ",ok)

func key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
		get_viewport().push_input(event,true);await frames(3)
	await frames(8)

func click(control: Control,local_at: Vector2=Vector2.INF) -> void:
	var local: Vector2=control.size*.5 if local_at==Vector2.INF else local_at
	var pixel: Vector2=control.get_global_transform_with_canvas()*local
	get_viewport().notify_mouse_entered()
	var move:=InputEventMouseMotion.new();move.position=pixel;get_viewport().push_input(move,true)
	await frames(2)
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=pixel;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		get_viewport().push_input(event,true);await frames(3)
	await frames(10)

func shot(name: String) -> void:
	main.ui.refresh_hud();main.ui.set_area(main.area_name());main.world.update_time(GameState.minute,GameState.weather,true)
	await frames(15);await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(name+".png"))
	print("UI_SHOT ",name)

func run() -> void:
	GameState.clock_paused=true;GameState.minute=630;GameState.weather="sunny"
	for spec: Array in [["seed_radish",8],["radish",3],["tomato",2],["fish_ayu",2],["onigiri",1],["washi",6]]:GameState.add_item(spec[0],spec[1],true)
	main.player.global_position=Vector3(-30,.1,-10.5);main.rig.yaw=250;main.rig.pitch=22;main.rig.dist=8;main.rig.snap()
	await shot("01_hud_town")
	await click(main.ui.minimap.open_button)
	verify("clicking the minimap opens a locked full map",main.ui.modal=="map" and GameState.input_locked())
	if main.ui.modal!="map":finish();return
	await shot("02_map_town")
	await click(main.ui.map_panel.find_child("Region_farm",true,false) as Button)
	verify("region tab selects the water map",main.ui.map_panel.canvas.map_region()=="farm")
	main.ui.map_panel.canvas.configure_view()
	await click(main.ui.map_panel.canvas,main.ui.map_panel.canvas.project(Vector2(136.8,17)))
	verify("clicking a fishing icon selects its actual destination",main.ui.map_destination.get("id")=="fish_reeds")
	await shot("03_map_farm_selected")
	await key(KEY_M)
	verify("M closes the map and retains the chosen destination",main.ui.modal=="" and not GameState.input_locked() and main.ui.map_destination.get("id")=="fish_reeds")
	verify("town marker guides toward the farm entrance",main.ui.minimap.canvas.navigation_indicator().get("target",{}).get("id")=="farm_exit")
	await shot("04_route_from_town")
	await click(main.ui.shortcuts_bar.find_child("Shortcut_backpack",true,false) as Button)
	verify("backpack shortcut opens the populated inventory",main.ui.modal=="inventory")
	await shot("05_backpack")
	await key(KEY_ESCAPE)
	main.world.set_region("farm");GameState.player_region="farm";main.player.global_position=FarmBuilder.ORIGIN+Vector3(94,.1,45)
	main.rig.yaw=180;main.rig.pitch=24;main.rig.dist=9;main.rig.snap();GameState.minute=980
	await shot("06_hud_lake")
	await key(KEY_M)
	verify("M opens on the lake region after a region change",main.ui.modal=="map" and main.ui.map_panel.canvas.map_region()=="farm")
	if main.ui.modal=="map":
		await click(main.ui.map_panel.find_child("ClearDestination",true,false) as Button)
		verify("clear removes only the manual destination",main.ui.map_destination.is_empty())
		await shot("07_map_lake_clear")
		await key(KEY_ESCAPE)
	GameState.minute=1260;GameState.weather="sunny";await shot("08_hud_night")
	GameState.weather="rain";main.weather_fx.set_weather("rain",false);await shot("09_hud_rain")
	verify("all panels close and input is restored",main.ui.modal=="" and not GameState.input_locked())
	finish()

func finish() -> void:
	var file:=FileAccess.open(folder.path_join("demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"checks":checks,"fixture":"starting inventory, camera poses, regions and weather only; real mouse and keyboard input"},"  "))
	Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)
