extends SceneTree
func _initialize() -> void: _start.call_deferred()
func _start() -> void:
    if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
        printerr("Lakeside review requires isolated saves")
        quit(2)
        return
    (root.get_node("GameState") as Node).set("clock_paused",true)
    var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
    var main: Node3D = scene.instantiate() as Node3D
    root.add_child(main)
    current_scene=main
    var warmup: int = 0
    while not bool(main.get("loading_ready")) and warmup<1200:
        await process_frame
        warmup+=1
    if not bool(main.get("loading_ready")):
        quit(3)
        return
    for settle: int in range(8): await process_frame
    var capture: Node = load("res://scripts/tools/lakeside_polish_capture.gd").new() as Node
    main.add_child(capture)
