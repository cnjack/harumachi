extends SceneTree

func _initialize() -> void:
    _start.call_deferred()

func _start() -> void:
    if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
        printerr("Material preview requires an isolated HARUMACHI_SAVE_DIR; use its launcher.")
        quit(2)
        return
    var state: Node = root.get_node("GameState")
    state.set("clock_paused",true)
    var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
    var game: Node3D = packed.instantiate() as Node3D
    root.add_child(game)
    current_scene = game
    var ready_frames: int = 0
    while not bool(game.get("loading_ready")) and ready_frames < 1200:
        await process_frame
        ready_frames += 1
    if not bool(game.get("loading_ready")):
        printerr("Current Main scene did not finish building")
        quit(3)
        return
    for settle_frame: int in range(8): await process_frame
    var controller: Node = load("res://scripts/tools/material_options_controller.gd").new() as Node
    controller.name = "MaterialOptions"
    game.add_child(controller)
