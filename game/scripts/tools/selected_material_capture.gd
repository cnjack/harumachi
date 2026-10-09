extends Node
const SPOTS: Array[Dictionary] = preload("res://scripts/tools/material_options_controller.gd").SPOTS
const NAMES: Array[String] = ["ground_A","water_B","grass_B","sand_A","wood_A","stone_A"]
const EXPECTED: Dictionary = {"ground":"A","water":"B","grass":"B","sand":"A","wood_floor":"A","stone_floor":"A"}

func _ready() -> void:
    _capture.call_deferred()

func _capture() -> void:
    if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
        printerr("Selected material capture requires an isolated save directory")
        get_tree().quit(2)
        return
    var output: String = ""
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--out="): output=argument.substr(6)
    DirAccess.make_dir_recursive_absolute(output)
    var state: Node = get_tree().root.get_node("GameState")
    state.set("clock_paused",true)
    var main: Node3D = get_parent() as Node3D
    var world: WorldBuilder = main.get("world") as WorldBuilder
    var chosen: Dictionary = world.get_meta("material_selection",{})
    var counts: Dictionary = world.get_meta("material_selection_counts",{})
    var valid: bool = chosen==EXPECTED and int(counts.get("water",0))>0 and int(counts.get("grass_blades",0))>0 and int(counts.get("grass_ground",0))>0 and bool(world.get_meta("material_selection_geometry_unchanged",false))
    if not valid:
        printerr("Normal Main did not apply the selected material profile: ",chosen," ",counts)
        get_tree().quit(4)
        return
    state.set("clock_paused",true)
    state.set("minute",630.0)
    state.set("weather","sunny")
    var ui: Node = main.get("ui") as Node
    ui.call("set_hud_visible",false)
    (ui.get("panels") as RefCounted).call("set_cards_visible",false)
    var player: Node3D = main.get("player") as Node3D
    player.visible=false
    player.process_mode=Node.PROCESS_MODE_DISABLED
    for npc: Node3D in (main.get("npcs") as Dictionary).values():
        npc.visible=false
        npc.process_mode=Node.PROCESS_MODE_DISABLED
    var rig: CameraRig = main.get("rig") as CameraRig
    rig.process_mode=Node.PROCESS_MODE_DISABLED
    var captures: Array[String] = []
    for kind: int in range(6):
        var spot: Dictionary = SPOTS[kind]
        var origin: Vector3 = FarmBuilder.ORIGIN if spot.region=="farm" else (HouseBuilder.ORIGIN if spot.region=="house" else Vector3.ZERO)
        if spot.region=="house":
            main.call("_put_in_room",origin+spot.at)
            world.house.update_cutaway("bedroom",false)
        else:
            main.set("in_room",false)
            main.set("room_kind","")
            state.set("player_in_room",false)
            world.set_indoor_look(false)
            world.set_region(str(spot.region))
            player.global_position=origin+spot.at
        rig.process_mode=Node.PROCESS_MODE_DISABLED
        rig.cam.fov=48.0
        var focus: Vector3 = origin+spot.focus
        var offset: Vector3 = origin+spot.camera-focus
        world.update_time(630.0,"sunny",true)
        for frame: int in range(60):
            rig.cam.global_position=focus+offset.rotated(Vector3.UP,(float(frame)/60.0-.5)*.035)
            rig.cam.look_at(focus)
            await RenderingServer.frame_post_draw
            if frame==30:
                var path: String = output.path_join(NAMES[kind]+".png")
                get_viewport().get_texture().get_image().save_png(path)
                captures.append(path)
    var file: FileAccess = FileAccess.open(output.path_join("verification.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"actual_scene":"res://scenes/main.tscn","default_profile_applied":valid,"selection":chosen,"counts":counts,"geometry_unchanged":world.get_meta("material_selection_geometry_unchanged"),"captures":captures,"review_controller_loaded":main.get_node_or_null("MaterialOptions")!=null,"isolated_save_dir":OS.get_environment("HARUMACHI_SAVE_DIR")},"\t"))
    print("SELECTED_DEFAULT_MATERIALS verified=",valid," selection=",chosen," counts=",counts)
    (get_tree().root.get_node("Audio") as Node).call("silence")
    get_tree().quit(0)
