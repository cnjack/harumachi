extends SceneTree
func _init():
	var G = root.get_node("/root/GameState")
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for d in [3, 4, 11, 17]:
		G.day = d
		main.world.sync_festivals()
		var vis = {}
		for fid in main.world.fest_nodes:
			vis[fid] = main.world.fest_nodes[fid].visible
		print("day ", d, " ", G.festivals_decorated(), " ", vis)
	quit()
