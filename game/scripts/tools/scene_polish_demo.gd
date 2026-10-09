extends Node
## Native evidence of parked arrival, actual E interactions, motion phases and six save controls.
var main: Node
var folder: String=""
var failures: Array[String]=[]
var checks: Dictionary={}
var camera: Camera3D

func _ready() -> void:
	main=get_parent()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):folder=argument.substr(11)
	if folder=="":folder="/tmp/harumachi-scene-polish-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	if GameState.flags.get("polish_demo_reload",false):
		var file:=FileAccess.open(folder.path_join("verification.json"),FileAccess.READ)
		var previous: Dictionary=JSON.parse_string(file.get_as_text());file.close();checks=previous.checks;failures.assign(previous.failures)
		checks["loaded_slot_four"]=SaveDB.active_slot==4 and GameState.coins==444 and GameState.day==4
		if not checks.loaded_slot_four:failures.append("keyboard loading slot four failed")
		await shot("slots_loaded");finish();return
	GameState.new_game();GameState.clock_paused=true;main.ui.auto=false
	main.player.global_position=Layout.SPAWN;main.world.bus.arrival(main)
	await get_tree().create_timer(1.7).timeout;await shot("arrival_approach")
	await get_tree().create_timer(1.65).timeout;await shot("arrival_door")
	while GameState.input_locked():await frames(1)
	var parked: Vector3=main.world.bus.position
	await get_tree().create_timer(2.0).timeout
	checks["parked_after_arrival"]=main.world.bus.visible and main.world.bus.position.is_equal_approx(parked) and not main.world.bus.travelling
	if not checks.parked_after_arrival:failures.append("bus did not remain parked")
	camera=Camera3D.new();camera.name="EvidenceCamera";add_child(camera);camera.make_current()
	main.photo_mode=true;main.ui.ambient_layer.visible=false;main.marker.visible=false;main.player.model_root.visible=false
	await view(Vector3(-38.5,1.9,-8),Vector3(-44.8,1.1,-11.3));await shot("bus_glass")
	await view(Vector3(-3,3.7,-2),Vector3(4,3.4,7))
	for time_value in [0.0,2.0,4.0]:
		set_motion_time(time_value);await frames(8);await shot("tree_phase_%d"%int(time_value))
	set_motion_time(-1.0)
	await view(Vector3(-1,2.75,-7.4),Vector3(-1,2.65,-5));GameState.minute=603;await frames(8);await shot("clock_hour_1003")
	GameState.minute=630;await frames(8);await shot("clock_hour_1030")
	for index in main.life.cats.size():
		var cat: Node3D=main.life.cats[index].node
		main.in_room=false;main.world.set_region("farm" if cat.global_position.x>200 else "town")
		main.player.model_root.visible=true;main.photo_mode=false;main.ui.ambient_layer.visible=true
		main.player.global_position=Vector3(cat.global_position.x-1.0,.08,cat.global_position.z+.85);main.player.velocity=Vector3.ZERO;main.player.face_towards(cat.global_position)
		await frames(12);var count_before:=int(GameState.flags.get("ambient_cat_pets",0));await tap(KEY_E);await frames(8)
		var response:=int(GameState.flags.get("ambient_cat_pets",0))==count_before+1 and Audio._last.has("cat_meow")
		checks["cat_%d_meows_on_E"%index]=response
		if not response:failures.append("E did not pet cat %d"%index)
		main.photo_mode=true;main.player.model_root.visible=false;main.ui.ambient_layer.visible=false
		await view(cat.global_position+Vector3(-.65,.35,.75),cat.global_position+Vector3(0,.16,0));await shot("cat_%d_contact"%index)
	main.world.set_region("farm");main.player.global_position=FarmBuilder.ORIGIN+Vector3(56,.1,23)
	await view(FarmBuilder.ORIGIN+Vector3(49,2.5,26),FarmBuilder.ORIGIN+Vector3(59,0,23))
	for time_value in [0.0,1.0,2.0,7.99,8.01]:
		set_motion_time(time_value);await frames(8);await shot("river_phase_%03d"%int(time_value*100))
	set_motion_time(-1.0)
	await view(FarmBuilder.ORIGIN+Vector3(87,3.8,49),FarmBuilder.ORIGIN+Vector3(103,0,18));await shot("lake_surface")
	main.world.set_region("town");main.photo_mode=false;main.player.model_root.visible=true;main.ui.ambient_layer.visible=true
	main.player.global_position=Vector3(-43.8,.08,-9.6);main.player.velocity=Vector3.ZERO
	var driver:=main.world.bus.get_node("BusDriver") as Interactable;main.player.face_towards(driver.global_position);await view(Vector3(-38.5,1.9,-8),Vector3(-44.8,1.1,-11.3));await frames(12)
	await tap(KEY_E);await frames(15);await tap(KEY_E);await frames(8);await shot("driver_conversation")
	checks["driver_dialogue"]=main.ui.conversation_active and main.ui.dlg_text.get_parsed_text().contains("暂时")
	if not checks.driver_dialogue:failures.append("driver dialogue not reached with E")
	await tap(KEY_E);await frames(10)
	for slot in range(1,7):
		GameState.new_game();GameState.day=slot;GameState.coins=111*slot
		GameState.flags["polish_demo_reload"]=slot==4
		GameState.save_to_slot(slot)
	main.ui.open_save_slots("save");await frames(12);await shot("six_save_slots")
	var panel:=main.ui.modal_layer.find_child("SaveSlotsPanel",true,false) as SaveSlotsPanel
	var button:=panel.buttons[2];button.grab_focus();await tap(KEY_SPACE);await frames(8);await shot("slot_overwrite_confirmation")
	checks["overwrite_confirmation"]=panel.pending_slot==3 and main.ui.modal=="save_slots"
	main.ui.close_modal();await frames(8)
	main.ui.open_save_slots("load");await frames(12);await shot("six_load_slots")
	DisplayServer.window_set_size(Vector2i(1920,1080));await frames(12);await shot("six_load_slots_1920")
	DisplayServer.window_set_size(Vector2i(1280,720));await frames(12)
	var load_panel:=main.ui.modal_layer.find_child("SaveSlotsPanel",true,false) as SaveSlotsPanel
	load_panel.buttons[3].grab_focus();write_report(false);await tap(KEY_SPACE)

func set_motion_time(value: float) -> void:
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(main.world):
		for surface in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_surface_override_material(surface)
			if material==null:material=mesh.mesh.surface_get_material(surface)
			if material is ShaderMaterial and (material as ShaderMaterial).shader.resource_path in ["res://shaders/foliage_sway.gdshader","res://shaders/water.gdshader","res://shaders/lakeside_water.gdshader"]:(material as ShaderMaterial).set_shader_parameter("animation_time",value)

func view(at: Vector3,focus: Vector3) -> void:
	camera.global_position=at;camera.look_at(focus);camera.fov=54;await frames(8)
func frames(count: int) -> void:
	for index in count:await get_tree().process_frame
func tap(code: Key) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;Input.parse_input_event(event);Input.flush_buffered_events();await frames(2)
	event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=false;Input.parse_input_event(event);Input.flush_buffered_events();await frames(2)
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw;get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png"));print("POLISH_SHOT ",label)
func write_report(done: bool) -> void:
	var file:=FileAccess.open(folder.path_join("verification.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"passed":done and failures.is_empty(),"failures":failures,"checks":checks},"  "));file.close()
func finish() -> void:
	write_report(true);Audio.silence();await frames(4);get_tree().quit(0 if failures.is_empty() else 1)
