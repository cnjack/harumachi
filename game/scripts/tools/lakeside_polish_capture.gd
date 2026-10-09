extends Node
const VIEWS: Array[Dictionary] = [
    {"name":"bridge_banks","camera":Vector3(13,4.6,8),"focus":Vector3(-1,.0,17)},
    {"name":"lake_overview","camera":Vector3(68,15,-28),"focus":Vector3(104,-.2,20)},
    {"name":"creek_stones","camera":Vector3(5.5,1.45,10.8),"focus":Vector3(8.2,-.15,14.8)},
    {"name":"path_and_sign","camera":Vector3(-17.7,1.9,3.6),"focus":Vector3(-22.0,.65,-1.0)},
    {"name":"sign_close","camera":Vector3(-20.5,1.6,.3),"focus":Vector3(-21.5,1.0,-2.4)},
    {"name":"bridge_wood","camera":Vector3(0,2.8,13.6),"focus":Vector3(0,.42,18.2)},
    {"name":"stone_street","town":true,"camera":Vector3(-18,2.9,-8.6),"focus":Vector3(-12,.08,-14.1)}
]
func _ready() -> void: _capture.call_deferred()
func _capture() -> void:
    var main: Node3D = get_parent() as Node3D
    var world: WorldBuilder = main.get("world") as WorldBuilder
    var player: Node3D = main.get("player") as Node3D
    var rig: CameraRig = main.get("rig") as CameraRig
    var output: String = ""
    var video: bool = false
    var selected_views: PackedStringArray = []
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--out="): output=argument.substr(6)
        elif argument=="--video": video=true
        elif argument.begins_with("--views="):selected_views=argument.substr(8).split(",")
    DirAccess.make_dir_recursive_absolute(output)
    GameState.clock_paused=true
    GameState.minute=630.0
    GameState.weather="sunny"
    var ui: Node = main.get("ui") as Node
    ui.call("set_hud_visible",false)
    (ui.get("panels") as RefCounted).call("set_cards_visible",false)
    player.visible=false
    player.process_mode=Node.PROCESS_MODE_DISABLED
    for npc: Node3D in (main.get("npcs") as Dictionary).values():
        npc.visible=false
        npc.process_mode=Node.PROCESS_MODE_DISABLED
    rig.process_mode=Node.PROCESS_MODE_DISABLED
    var images: Array[String] = []
    for view: Dictionary in VIEWS:
        if not selected_views.is_empty() and not selected_views.has(str(view.name)):continue
        var town: bool = bool(view.get("town",false))
        var origin: Vector3 = Vector3.ZERO if town else FarmBuilder.ORIGIN
        world.set_region("town" if town else "farm")
        world.set_indoor_look(false)
        player.global_position=origin+view.focus+Vector3(0,.6,-3)
        world.update_time(630.0,"sunny",true)
        var target: Vector3 = origin+view.focus
        var offset: Vector3 = origin+view.camera-target
        rig.cam.fov=48.0
        for frame: int in range(90 if video else 10):
            rig.cam.global_position=target+offset.rotated(Vector3.UP,(float(frame)/90.0-.5)*.035 if video else 0.0)
            rig.cam.look_at(target)
            await RenderingServer.frame_post_draw
            if frame==(45 if video else 8):
                var path: String = output.path_join(str(view.name)+".png")
                get_viewport().get_texture().get_image().save_png(path)
                images.append(path)
        print("LAKESIDE_POLISH_SHOT ",view.name)
    var flowers: int = 0
    for node: Node in world.farm.find_children("*","Node3D",true,false):
        if str(node.get_meta("model_id",""))=="C07_sunflower":flowers+=1
    var centre_samples: Array[float] = []
    var width_samples: Array[float] = []
    for sample_x: float in [-24.0,-16.0,-8.0,0.0,8.0,16.0,24.0]:
        centre_samples.append(LakesideLayout.river_z(sample_x))
        width_samples.append(LakesideLayout.river_half(sample_x))
    var report: Dictionary = {"engine":Engine.get_version_info(),"images":images,"sunflowers":flowers,"river_centres":centre_samples,"river_half_widths":width_samples,"isolated_save":SaveDB.database_path,"creek_stones":world.farm.lakeside.get_meta("creek_stone_count",0),"selection":world.get_meta("material_selection",{})}
    FileAccess.open(output.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
    Audio.silence()
    get_tree().quit(0)
