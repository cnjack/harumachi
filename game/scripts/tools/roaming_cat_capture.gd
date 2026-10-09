extends SceneTree
## Real-world roaming smoke test and native closeups with isolated storage.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output: String=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var state_node: Node=root.get_node("GameState")
	state_node.new_game()
	state_node.clock_paused=true
	var npc_script: GDScript=load("res://scripts/npc/npc.gd") as GDScript
	npc_script.roam_enabled=false
	var main: Node3D=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	for frame: int in range(25):await process_frame
	var life: Node=main.get_node("AmbientLife")
	var cats: Array=life.roaming_cats
	assert(cats.size()==2,"Both standing cats must exist in the real world")
	var positions: Array[Vector3]=[]
	for cat: CharacterBody3D in cats:positions.append(cat.global_position)
	Engine.time_scale=4
	for frame: int in range(600):await physics_frame
	Engine.time_scale=1
	var results: Array[Dictionary]=[]
	for index: int in range(cats.size()):
		var cat: CharacterBody3D=cats[index] as CharacterBody3D
		var state: Dictionary=cat.telemetry()
		state["character"]="orange" if index==0 else "calico"
		state["displacement"] = positions[index].distance_to(cat.global_position)
		state["passed"] = float(state.travelled_m)>.5 and int(state.arrivals)>=2 and absf(cat.global_position.y)<.04
		results.append(state)
	for camera_node: Node in main.find_children("*","Camera3D",true,false):(camera_node as Camera3D).current=false
	var camera: Camera3D=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.1
	main.add_child(camera)
	camera.current=true
	for index: int in range(cats.size()):
		var cat: CharacterBody3D=cats[index] as CharacterBody3D
		camera.global_position=cat.global_position+Vector3(.65,.46,.85)
		camera.look_at(cat.global_position+Vector3(0,.15,0))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%s-world.png"%("orange" if index==0 else "calico")))
	var passed: bool=true
	for result: Dictionary in results:passed=passed and bool(result.passed)
	FileAccess.open(output.path_join("roam.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"results":results},"\t"))
	print("REAL_WORLD_CATS ",results)
	main.queue_free()
	await process_frame
	quit(0 if passed else 1)
