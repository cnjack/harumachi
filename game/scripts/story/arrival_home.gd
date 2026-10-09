extends RefCounted
## Authored arrival cuts. Stage checkpoints are distinct from player cooking or meeting neighbours.
var main: Node
func _init(scene: Node) -> void: main = scene

func run(show_bus: bool) -> bool:
	var G := GameState
	var flow: Dictionary = G.flags.get("arrival_home", {})
	if int(flow.get("version", 0)) != 1 or str(flow.get("phase", "done")) == "done": return true
	if not flow.has("clock_was_paused"): flow["clock_was_paused"] = G.clock_paused
	var paused: bool = bool(flow.clock_was_paused)
	G.clock_paused = true
	G.lock_input("arrival")
	main.player.frozen = true
	main.story.cutscene = true
	main.ui.ambient_layer.visible = false
	main.marker.visible = false
	if str(flow.phase) == "bus":
		if not G.save_game(): return _release(paused, false)
		if show_bus and not G.flags.get("bus_arrival_seen", false):
			main.player.frozen = false
			await main.world.bus.arrival(main, true)
			main.player.frozen = true
		flow.phase = "home"
		if not G.save_game(): return _release(paused, false)
	if str(flow.phase) == "home":
		await main.ui.fade_out(.5)
		if G.at_step("Q00", "mailbox"):
			if not G.has("house_key"): G.add_item("house_key", 1, true)
			if not G.has("welcome_note"): G.add_item("welcome_note", 1, true)
			G.advance("Q00", "mailbox")
		main._put_in_room(HouseBuilder.ORIGIN + Vector3(-4.6, .05, -.6))
		Audio.set_indoor(true)
		G.minute = 20.0 * 60.0
		main.world.update_time(G.minute, G.weather, true)
		flow.phase = "bed"
		if G.at_step("Q00", "enter_home"): G.complete_quest("Q00", true, false)
		if not G.save_game(): return _release(paused, false)
		await main.ui.fade_in(.5)
		main.ui.dialogue_begin()
		await main.story.say("narrator", "", "钥匙和澪留下的便笺放在玄关。行李收进屋里时，天已经暗了。")
		await main.story.say("narrator", "", "今晚先睡吧。那些还没拆开的纸箱，明天再慢慢来。")
		main.ui.dialogue_end()
	if str(flow.phase) in ["bed", "wake"]:
		await main.ui.fade_out(.5)
		main._put_in_room(HouseBuilder.ORIGIN + Vector3(-4.6, .05, -.6))
		DailyLife.track("meal")
		# The committed next-day snapshot is already 'done'; a failed write remains retryable in memory.
		flow.phase = "done"
		var written: bool
		if G.day < int(flow.origin_day) + 1: written = G.advance_day()
		else: written = G.save_game(true)
		if not written:
			flow.phase = "wake"
			return _release(paused, false)
		main.weather_fx.set_weather(G.weather, true)
		main.world.update_time(G.minute, G.weather, true)
		Audio.play_music(main.music_for_now(), 1.0)
		await main.ui.fade_in(.5)
		main.ui.dialogue_begin()
		await main.story.say("narrator", "", "第二天，窗外的蝉声把空叫醒了。屋子里还带着纸箱和木头的气味。")
		await main.story.say("narrator", "", "碗柜上留着食材便笺。先做顿早饭，或者带上钥匙出门看看，都可以。")
		main.ui.dialogue_end()
	return _release(paused, true)

func _release(paused: bool, success: bool) -> bool:
	GameState.clock_paused = paused if success else true
	GameState.unlock_input("arrival")
	main.story.cutscene = false
	main.player.frozen = not success
	main.ui.ambient_layer.visible = true
	return success
