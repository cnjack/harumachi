extends "res://scripts/tools/autoplay.gd"
## Diagnostic-only date/material setup; approach uses the real player's collision.
func _ready() -> void:
	main=get_parent();G=GameState
	await get_tree().create_timer(.2).timeout
	G.new_game();G.clock_paused=true;G.quests.Q00={"state":"done","step":2};G.quests.Q01={"state":"done","step":2}
	NPC.roam_enabled=false
	await main.enter_interior("bakery")
	var route:=SummerAutoplay.new(self)
	var point: Interactable=route.point("opening_paper")
	print("PAPER_PROBE start=",main.player.global_position," target=",point.global_position)
	var arrived: bool=await route.approach(point)
	print("PAPER_PROBE arrived=",arrived," final=",main.player.global_position)
	var file:=FileAccess.open(OS.get_environment("HARUMACHI_SAVE_DIR").path_join("reach.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"arrived":arrived,"position":str(main.player.global_position),"point":str(point.global_position),"actual_target":main.player.target.id if main.player.target!=null else "none"},"  "))
	get_tree().quit(0 if arrived else 1)
