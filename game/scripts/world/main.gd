extends Node3D
## Game scene root: builds the town, player, camera, NPCs, UI and story, then keeps the
## world in sync with GameState (phase look, bread/poster, crop, NPC stations).

var world: WorldBuilder
var player: Player
var rig: CameraRig
var calendar: CalendarAdvance
var ui: GameUI
var story: Story
var placement: PlacementSystem
var npcs := {}
var marker: Sprite3D
var in_room := false
var _transition := false
var loading_ready := false
var _marker_t := 0.0
var weather_fx: WeatherFX
var photo: PhotoMode
var life: AmbientLife
var shop_life: ShopLife
var _amb_check := 0.0
var _last_fest := ""
var dancing := false
const FEST_POINTS := [
	["tanabata_bamboo", -1.1, -3.0, 1.0, 2.6], ["contest_table", -6.2, 8.0, 1.0, 2.0], ["yagura", -2.6, 16.1, 1.0, 2.4],
	["yatai", 5.8, 19.5, 1.0, 1.7], ["yatai", 9.2, 19.5, 1.0, 1.7], ["offer_stand", -1.4, -1.4, 0.6, 1.6],
]


func _ready() -> void:
	# Player and follow camera opt in; world props, UI and existing scripted
	# resident actions keep their current update timing.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("save_hooks")
	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	if Loading.scene_busy:
		await world.build_async()
	else:
		world.build()
	if not "--material-options" in OS.get_cmdline_user_args():
		MaterialChoiceProfile.apply(world)
	for p in Layout.POINTS:
		_add_point(p[0], Vector3(p[1], p[3], p[2]), p[4])
	for p in HouseBuilder.POINTS:
		_add_point(p[0], HouseBuilder.ORIGIN + Vector3(p[1], p[2], p[3]), p[4])
	for p in Layout.MG_POINTS:
		_add_point(p[0], Vector3(p[1], p[3], p[2]), p[4])
	for p in FarmBuilder.POINTS:
		_add_point(p[0], FarmBuilder.ORIGIN + Vector3(p[1], p[3], p[2]), p[4])
	HomageBuilder.build(world)
	for entry: Dictionary in Homage.entries():
		_add_point(str(entry.id), Homage.world_position(entry) + Vector3(0, 0.7, 0), 1.35)
	for spot_id:String in LakesideLayout.SPOTS:
		var at:Vector2=LakesideLayout.SPOTS[spot_id].stand
		_add_point(spot_id,FarmBuilder.ORIGIN+Vector3(at.x,.95 if spot_id=="fish_pier" else LakesideLayout.height_at(at)+.95,at.y),1.8)
	_add_point("lakeside_supplies",FarmBuilder.ORIGIN+Vector3(LakesideLayout.SUPPLIES.x,1.0,LakesideLayout.SUPPLIES.y),2.0)
	for p in FEST_POINTS:
		_add_point(p[0], Vector3(p[1], p[3], p[2]), p[4])
	_add_point("bridge_toro", FarmBuilder.ORIGIN + Vector3(0.0, 1.2, 15.4), 1.8)
	for id in world.farm.plot_views:
		_add_point("plot_" + id, (world.farm.plot_views[id] as Node3D).global_position + Vector3(0, 0.55, 0), 1.3)
	for id in world.house.yard_plots:
		_add_point("plot_" + id, (world.house.yard_plots[id] as Node3D).global_position + Vector3(0, 0.55, 0), 1.25)

	placement = PlacementSystem.new()
	placement.name = "Placement"
	add_child(placement)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.target = player
	rig.exclude(player)
	player.rig = rig
	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	story = Story.new()
	story.name = "Story"
	add_child(story)
	story.main = self
	story.ui = ui
	story.world = world
	story.player = player
	story.placement = placement
	placement.ui = ui
	placement.player = player
	player.story = story
	for id in Layout.NPC:
		var n := NPC.new()
		add_child(n)
		n.setup(id, Layout.NPC[id])
		n.player = player
		npcs[id] = n
		rig.exclude(n.body)
	story.npcs = npcs
	calendar = CalendarAdvance.new()
	add_child(calendar)
	calendar.setup(self)
	story.daily.build()
	story.morning=ResidentMorning.new()
	add_child(story.morning)
	story.morning.setup(story)
	_add_point("resident_morning",Vector3(15.1,.9,16.55),1.35)
	story.neighbours.build()
	_add_point("shared_meal_table",NeighbourMeals.TABLE_CENTER+Vector3(0,1.05,.1),1.9)
	story.space.build()
	_add_point("space_plan", Vector3(10.0, 1.0, 12.0), 1.6)
	story.space.view.sync_state()
	_add_point("opening_paper", InteriorBuilder.SPECS.bakery.origin + Vector3(-1.1, .9, 1.8), 1.4)
	_add_point("opening_site", Vector3(4.3, .9, 13.2), 1.4)
	var project_view := ProjectView.new()
	add_child(project_view)
	project_view.setup(story)
	_add_point("festival_work", Vector3(-3.0, 1.0, -3.8), 1.5)
	_add_point("gathering_paper", Vector3(8.5, 1.0, 10.4), 1.4)
	story.gathering.build()
	_add_point("life_tea", Vector3(15.1, .9, 15.5), 1.35)
	_add_point("life_bakery_card", Vector3(-20.6, .9, -14.25), 1.35)
	_add_point("life_bakery_card_in", InteriorBuilder.SPECS.bakery.origin + Vector3(1.0, .9, 1.8), 1.35)
	ui.setup_world_map(self)
	weather_fx = WeatherFX.new()
	weather_fx.name = "WeatherFX"
	add_child(weather_fx)
	weather_fx.rig = rig
	life = AmbientLife.new()
	life.name = "AmbientLife"
	add_child(life)
	life.setup(world, player)
	var environment_life:=EnvironmentLife.new()
	environment_life.name="EnvironmentLife"
	add_child(environment_life)
	environment_life.setup(world,player)
	shop_life=ShopLife.new();shop_life.name="ShopLife";add_child(shop_life);shop_life.setup(self)
	photo=PhotoMode.new();photo.name="PhotoMode";add_child(photo);photo.setup(self)

	marker = Sprite3D.new()
	marker.texture = load("res://assets/ui/icons/map_pin.png")
	marker.pixel_size = 0.0045
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.render_priority = 5
	marker.modulate = Color(1, 1, 1, 0.92)
	add_child(marker)

	player.interact_requested.connect(story.interact)
	GameState.crop_changed.connect(func(s): world.set_crop_stage(s))
	GameState.plots_changed.connect(refresh_plots)
	GameState.time_changed.connect(_on_minute)
	GameState.day_changed.connect(_on_new_day)
	GameState.phase_changed.connect(_on_phase)
	GameState.late_night.connect(_on_late_night)
	GameState.state_changed.connect(_sync_props)
	GameState.state_changed.connect(func(): world.house.sync_state())
	ui.title_requested.connect(go_title)
	_restore()
	_start_audio()
	for a in OS.get_cmdline_user_args():
		if a=="--resident-morning-demo":add_child(load("res://scripts/tools/resident_morning_demo.gd").new())
		if a=="--bakery-reach-probe":add_child(load("res://scripts/tools/bakery_reach_probe.gd").new())
		if a=="--meal-routes-demo":add_child(load("res://scripts/tools/meal_route_demo.gd").new())
		if a=="--neighbour-meal-demo":add_child(load("res://scripts/tools/neighbour_meal_demo.gd").new())
		if a=="--food-purpose-demo": add_child(load("res://scripts/tools/food_purpose_demo.gd").new())
		if a=="--lantern-choice-demo": add_child(load("res://scripts/tools/lantern_choice_demo.gd").new())
		if a == "--gathering-demo":
			add_child(load("res://scripts/tools/gathering_demo.gd").new())
		if a == "--calendar-demo":
			add_child(load("res://scripts/tools/calendar_demo.gd").new())
		if a == "--space-demo":
			add_child(load("res://scripts/tools/space_demo.gd").new())
		if a == "--abstract-meal-demo":
			add_child(load("res://scripts/tools/abstract_meal_demo.gd").new())
		if a == "--project-tasting-demo":
			add_child(load("res://scripts/tools/project_tasting_demo.gd").new())
		if a == "--workshop-demo":
			add_child(load("res://scripts/tools/workshop_demo.gd").new())
		if a == "--cooperation-demo":
			var cooperation_demo = load("res://scripts/tools/cooperation_demo.gd").new()
			add_child(cooperation_demo)
		if a == "--summer-foundation-demo":
			var summer_demo = load("res://scripts/tools/summer_foundation_demo.gd").new()
			add_child(summer_demo)
		if a == "--daily-life-demo":
			var daily_demo = load("res://scripts/tools/daily_life_demo.gd").new()
			add_child(daily_demo)
		if a == "--scene-polish-demo":
			var polish_demo=load("res://scripts/tools/scene_polish_demo.gd").new();add_child(polish_demo)
		if a == "--living-demo":
			var living_demo=load("res://scripts/tools/living_demo.gd").new();add_child(living_demo)
		if a == "--homage-demo":
			var homage_demo = load("res://scripts/tools/homage_demo.gd").new()
			add_child(homage_demo)
		if a == "--bakery-demo":
			var demo = load("res://scripts/tools/bakery_demo.gd").new()
			add_child(demo)
		if a == "--lake-demo":
			var lake_demo=load("res://scripts/tools/lake_demo.gd").new()
			add_child(lake_demo)
		if a == "--ui-demo":
			var ui_demo=load("res://scripts/tools/ui_demo.gd").new()
			add_child(ui_demo)
		if a.begins_with("--shots="):
			var sh = load("res://scripts/tools/shots.gd").new()
			sh.name = "Shots"
			add_child(sh)
		if a.begins_with("--scene-quality-demo="):
			var quality_demo=load("res://scripts/tools/scene_quality_demo.gd").new();add_child(quality_demo)
	if "--showcase" in OS.get_cmdline_user_args():
		var sc = load("res://scripts/tools/showcase.gd").new()
		sc.name = "Autoplay"
		add_child(sc)
	elif "--autoplay" in OS.get_cmdline_user_args():
		var ap = load("res://scripts/tools/autoplay.gd").new()
		ap.name = "Autoplay"
		add_child(ap)
	loading_ready = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--ordinary-report="):
			var play_observer: Node=load("res://scripts/tools/ordinary_play_observer.gd").new()
			add_child(play_observer);play_observer.setup(self,argument.trim_prefix("--ordinary-report="))
		if argument.begins_with("--shop-life-demo="):
			add_child(load("res://scripts/tools/shop_life_demo.gd").new())
		if argument.begins_with("--environment-demo="):
			add_child(load("res://scripts/tools/environment_demo.gd").new())
		if argument.begins_with("--spatial-report="):
			var observer: Node = load("res://scripts/tools/world_runtime_audit.gd").new()
			add_child(observer)
			observer.setup(self, argument.trim_prefix("--spatial-report="))
	if "--world-audit" in OS.get_cmdline_user_args():
		add_child(load("res://scripts/tools/world_audit_driver.gd").new())
	if "--arrival-entry-demo" in OS.get_cmdline_user_args():
		add_child(load("res://scripts/tools/arrival_entry_demo.gd").new())
	var entry_arguments: Array[String]=[]
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--ordinary-report="):entry_arguments.append(argument)
	var normal_entry: bool = entry_arguments.is_empty() or "--newgame" in entry_arguments
	if normal_entry and get_tree().current_scene == self:
		while Loading.scene_busy: await get_tree().process_frame
		await finish_arrival_home(true)

func finish_arrival_home(show_bus: bool = true) -> bool:
	var controller: RefCounted = load("res://scripts/story/arrival_home.gd").new(self)
	var success: bool = await controller.run(show_bus)
	if not success and not ui.instant and not ui.auto:
		await ui.fade_in(.3)
		ui.open_arrival_retry(finish_arrival_home)
	return success


## v0.6 background music: every festival has its own piece; rain, night, the farm and the shops too.
func music_for_now() -> String:
	var m := _music_pick()
	return m if ResourceLoader.exists("res://assets/audio/music/%s.ogg" % m) else ("market" if GameState.phase == "market" else "day")


func _music_pick() -> String:
	var G := GameState
	if in_room and room_kind in ["store", "bakery", "workroom"]:
		return "shop"
	var now := G.festival_now()
	if now == "natsumatsuri":
		return "bon_odori" if dancing or G.hour() >= 20.0 else "natsumatsuri"
	if now in ["hanabi", "obon"]:
		return now if world.region == "farm" else "night"
	if now in ["tanabata", "contest", "tsukimi"]:
		return now
	if G.phase == "market":
		return "market"
	var h := G.hour()
	if h >= 19.8 or h < 5.0:
		return "night"
	if G.weather == "rain":
		return "rain"
	if world.region == "farm":
		return "farm"
	return "day"


func _music_tick() -> void:
	if story.cutscene or ui.modal in ["ending", "minigame"] or Audio.music_name in ["ending", "title", "prologue", "taiko", "memory"]:
		return
	Audio.play_music(music_for_now(), 3.0)


func outdoor_amb() -> String:
	var G := GameState
	if G.phase == "market":
		return "evening"
	if G.weather == "rain":
		return "rain"
	if G.hour() >= 19.4 or G.hour() < 5.5:
		return "night"
	return "farm" if world.region == "farm" else "day"


func refresh_plots() -> void:
	world.farm.refresh_plots()
	world.house.refresh_plots()
	world.sync_court()


## Once a game minute: NPC routines. Market evenings keep everyone at the stalls.
func _on_minute(_m: int) -> void:
	sync_festival_state()
	if story.cutscene:
		return
	update_npcs(false)


## Festival start cards, fireworks and lanterns follow the clock.
func sync_festival_state() -> void:
	var G := GameState
	var now := G.festival_now()
	if now != _last_fest:
		_last_fest = now
		if now != "":
			var f := G.festival(now)
			ui.panels.card(str(f.name), [str(f.desc)], "w_festival", str(f.banner), 7.0)
			Audio.sting("fanfare")
			_music_tick()
	var fx: FestivalFX = world.farm.fx
	fx.fireworks_on = now == "hanabi" and world.region == "farm"
	fx.lanterns_on = now == "obon" and world.region == "farm"


func bon_odori_scene() -> void:
	var G := GameState
	story.cutscene = true
	dancing = true
	G.lock_input("cutscene")
	await ui.fade_out(0.5)
	var c := WorldBuilder.YAGURA_POS
	var back := player.global_position
	var back_yaw: float = rig.yaw
	var ids := ["mio", "ren", "haru", "aoi", "tanaka", "kazuko"]   # v0.7.3: Kazuko's raised arms no longer drag her apron
	for i in ids.size():
		var a := TAU * i / 7.0
		var n: NPC = npcs[ids[i]]
		n.fest_key = "natsumatsuri:dance"
		n.place(c + Vector3(cos(a), 0, sin(a)) * 3.6, rad_to_deg(a + PI / 2.0))
		n.set_pose("dance")
	player.global_position = c + Vector3(cos(TAU * 6.0 / 7.0), 0, sin(TAU * 6.0 / 7.0)) * 3.6 + Vector3(0, 0.1, 0)
	player.set_facing(TAU * 6.0 / 7.0 + PI / 2.0)
	if player.anim and player.anim.valid():
		player.anim.set_idle("dance")
	rig.yaw = 200.0
	rig.pitch = 30.0
	rig.dist = 10.0
	rig.snap()
	await ui.fade_in(0.5)
	var t := 0.2 if ui.instant else 9.0
	var tw := create_tween()
	tw.tween_property(rig, "yaw", 290.0, t)
	await get_tree().create_timer(t).timeout
	await ui.fade_out(0.5)
	if player.anim and player.anim.valid():
		player.anim.set_idle("idle")
	for id in ids:
		(npcs[id] as NPC).set_pose("idle")
	dancing = false
	for id in ids:
		(npcs[id] as NPC).fest_key = ""
	update_npcs(true)
	# step back out of the ring to where the player joined, looking at the yagura
	player.global_position = back
	player.face_towards(c)
	rig.yaw = back_yaw
	rig.snap()
	await ui.fade_in(0.5)
	G.unlock_input("cutscene")
	story.cutscene = false


func hanabi_scene(who: String) -> void:
	var G := GameState
	var standing: Vector3=player.global_position
	var saved_yaw: float=rig.yaw
	var saved_pitch: float=rig.pitch
	var saved_dist: float=rig.dist
	G.lock_input("cutscene")
	await ui.fade_out(0.5)
	var seat := FarmBuilder.ORIGIN + Vector3(9.2, 0.1, 11.4)
	player.global_position = seat
	player.set_facing(0.0)
	var n: NPC = npcs[who]
	n.fest_key = "hanabi:watch"
	n.place(seat + Vector3(1.0, -0.1, 0.1), 0.0)
	rig.yaw = 200.0
	rig.pitch = 8.0
	rig.dist = 5.0
	rig.snap()
	var fx: FestivalFX = world.farm.fx
	fx.fireworks_on = true
	fx.rate = 2.6
	await ui.fade_in(0.5)
	var tw := create_tween()
	tw.tween_property(rig, "pitch", -9.0, 3.0)      # looking up at the sky from the mown patch behind the bench
	await get_tree().create_timer(0.2 if ui.instant else 11.0).timeout
	fx.rate = 1.0
	await ui.fade_out(0.4)
	player.global_position=standing
	player.velocity=Vector3.ZERO
	n.fest_key=""
	update_npcs(true)
	rig.yaw=saved_yaw
	rig.pitch=saved_pitch
	rig.dist=saved_dist
	rig.snap()
	await ui.fade_in(0.4)
	G.unlock_input("cutscene")


func update_npcs(force: bool) -> void:
	var G := GameState
	var fid := G.festival_on(G.day)
	var f := G.festival(fid)
	var fest_on: bool = fid != "" and G.hour() >= float(f.get("start", 0)) - 0.5 and G.hour() < float(f.get("end", 0))
	for id in npcs:
		var n: NPC = npcs[id]
		# Main owns indoor keeper placement. Festival and outdoor schedules must wait until exit.
		var keeper_id: String = {"bakery": "ren", "store": "kazuko"}.get(room_kind, "")
		if in_room and id == keeper_id:
			if shop_life and shop_life.controls_keeper(id):
				if force:shop_life.cancel_work()
				else:continue
			var keeper_spec: Dictionary = InteriorBuilder.spec_for(room_kind)
			n.set_home(false)
			if force or n.fest_key != room_kind + ":counter":
				n.place(keeper_spec.origin + keeper_spec.keeper, keeper_spec.keeper_yaw)
			n.fest_key = room_kind + ":counter"
			continue
		if fest_on and (f.get("npc", {}) as Dictionary).has(id) and not (id == "aoi" and G.day < 2):
			if not dancing:
				n.apply_fest(f.npc[id], fid)
			continue
		if n.fest_key != "":
			n.fest_key = ""
			n.sched_i = -1
			force = true
		if G.phase == "market":
			continue
		if id == "aoi" and G.day < 2:
			n.set_home(true)
			continue
		if story.busy and n.talking:
			continue
		n.apply_schedule(G.hour(), player.global_position, force)


func _on_new_day(_d: int) -> void:
	world.sync_festivals()
	var G := GameState
	var fid := G.festival_on(G.day)
	var led: Dictionary = G.flags.get("last_ledger", {})
	var lines := ["昨天：收入 +%d · 支出 −%d · 种植经验 +%d" % [int(led.get("in", 0)), int(led.get("out", 0)), int(led.get("xp", 0))]]
	if fid != "":
		var f := G.festival(fid)
		lines.append("今天是%s！%02d:%02d 开始。" % [f.name, int(f.start), int(fmod(float(f.start), 1.0) * 60)])
	else:
		var nf := G.next_festival()
		if nf != "":
			lines.append("下一个节日：%s（%s）" % [G.festival(nf).name, G.date_text(int(G.festival(nf).day))])
	if DailyLife.available("tea") and G.day == int(DailyLife.state().introduced_day) + 1:
		lines.append("育苗台旁备了麦茶，春有空时可以去看看（J）。")
	elif DailyLife.available("card") and G.day == int(DailyLife.state().introduced_day) + 2:
		lines.append("面包店或推车边的小纸牌，莲有空时去看看（J）。")
	if not G._ui_locks.has("arrival"):
		ui.panels.card("%s（%s）· %s" % [G.date_text(), G.weekday_name().substr(1), G.weather_name()], lines, "calendar", str(G.festival(fid).get("banner", "")) if fid != "" else "", 6.0)
	for id in npcs:
		(npcs[id] as NPC).sched_i = -1
	update_npcs(true)
	world.update_time(GameState.minute, GameState.weather, true)
	refresh_plots()


## Weekly markets after the first one open by themselves at 16:30 on Saturdays.
func _on_phase(p: String) -> void:
	if story.cutscene:
		return
	if p == "market":
		to_market_positions(false)
		Audio.play_music(music_for_now(), 3.0)
		if GameState.festival_on(GameState.day) == "natsumatsuri":
			GameState.toast.emit("夏祭开始了！今晚庭院摊位的料理按 2 倍价卖出")
		else:
			GameState.toast.emit("周六的集市开张了！庭院的摊位可以卖菜了")
	else:
		for id in npcs:
			(npcs[id] as NPC).sched_i = -1
		update_npcs(true)
		Audio.play_music(music_for_now(), 3.0)
	world.apply_phase(p, false)
	_sync_props()


## Midnight: the player nods off wherever they are and wakes up at home.
func _on_late_night() -> void:
	while story.busy or _transition:
		await get_tree().process_frame
	_transition = true
	GameState.lock_input("transition")
	await ui.fade_out(1.0)
	var rested: bool = await sleep_now(true)
	await ui.fade_in(0.8)
	GameState.unlock_input("transition")
	_transition = false
	if rested: GameState.toast.emit("昨晚太晚了……迷迷糊糊地回到家就睡着了")


## Advance to the next morning in the bedroom (screen is already dark). Saves.
func sleep_now(_late: bool = false) -> bool:
	# The preceding settlement already happened. Save it before showing a new day's summary.
	if GameState.calendar_pending_save == GameState.day and not GameState.save_game(true):
		GameState.toast.emit("这一日还没有保存，先停在今天。按C重试保存后再休息。")
		return false
	var summary:=DaySummary.new();summary.name="DaySummary";add_child(summary);summary.setup(DaySummary.capture())
	if not ui.instant and not ui.auto:await summary.dismissed
	elif is_instance_valid(summary):summary.finish()
	await ui.fade_out(.6)
	if world.region == "farm":
		world.set_region("town")
		GameState.player_region = "town"
	_put_in_room(HouseBuilder.ORIGIN + Vector3(-4.6, 0.05, -0.6))
	Audio.set_indoor(true)
	var written: bool = GameState.advance_day()
	weather_fx.set_weather(GameState.weather, in_room)
	Audio.play_music(music_for_now(), 2.0)
	return written


## Town <-> riverside allotment (east end of the main street).
func go_farm() -> void:
	if _transition:
		return
	_transition = true
	GameState.lock_input("transition")
	await _loading_region("前往河边农园")
	await ui.fade_out(0.45)
	world.set_region("farm")
	GameState.player_region = "farm"
	player.global_position = FarmBuilder.ORIGIN + FarmBuilder.ENTRY
	player.velocity = Vector3.ZERO
	sync_festival_state()
	player.set_facing(deg_to_rad(90.0))
	rig.yaw = -90.0
	rig.pitch = 30.0
	rig.dist = 7.5
	rig.snap()
	Audio.play_amb(outdoor_amb(), 0.8)
	await ui.fade_in(0.45)
	Loading.finish()
	GameState.unlock_input("transition")
	_transition = false


func leave_farm() -> void:
	if _transition:
		return
	_transition = true
	GameState.lock_input("transition")
	await _loading_region("回到晴町街道")
	await ui.fade_out(0.45)
	world.set_region("town")
	GameState.player_region = "town"
	# just inside the lantern gate at the east end, walking back up into the street
	player.global_position = WorldBuilder.EXIT_GATE + Vector3(-2.4, 0.1, 0.0)
	player.velocity = Vector3.ZERO
	sync_festival_state()
	player.set_facing(deg_to_rad(-90.0))
	rig.yaw = 90.0
	rig.pitch = 24.0
	rig.dist = 7.0
	rig.snap()
	Audio.play_amb(outdoor_amb(), 0.8)
	await ui.fade_in(0.45)
	Loading.finish()
	GameState.unlock_input("transition")
	_transition = false


func start_fishing(spot_id:String) -> void:
	if not LakesideLayout.SPOTS.has(spot_id) or world.region!="farm":return
	var why:=GameState.borrow_fishing_kit()
	if why!="":
		GameState.toast.emit(why)
		return
	var spot:Dictionary=LakesideLayout.SPOTS[spot_id]
	var at:Vector2=spot["float"]
	var water:=FarmBuilder.ORIGIN+Vector3(at.x,LakesideLayout.WATER_Y,at.y)
	player.face_towards(water)
	var old_view:=Vector3(rig.yaw,rig.pitch,rig.dist)
	var direction:=water-player.global_position
	rig.yaw=rad_to_deg(atan2(-direction.x,-direction.z))+22.0;rig.pitch=25.0;rig.dist=7.4;rig.snap()
	var view:=FishingView.new();view.name="Fishing_view";add_child(view);view.setup(player,water)
	await ui.open_fishing(spot_id,view)
	rig.yaw=old_view.x;rig.pitch=old_view.y;rig.dist=old_view.z;rig.snap()

func _start_audio() -> void:
	Audio.play_music(music_for_now(), 2.5)
	Audio.set_indoor(in_room, outdoor_amb())
	# gameplay stingers stay silent while the save is being restored
	get_tree().create_timer(0.5).timeout.connect(func(): Audio.game_on = true)


func _add_point(id: String, pos: Vector3, radius: float) -> void:
	var it := Interactable.new()
	it.id = id
	it.radius = radius
	it.position = pos
	it.name = "P_" + id
	add_child(it)


func _restore() -> void:
	var G := GameState
	G.load_on_enter = false
	world.bus.park_at_stop()
	world.set_region("farm" if G.player_region == "farm" and not G.player_in_room else "town")
	world.apply_phase(G.phase, false)
	world.set_crop_stage(G.crop_stage, false)
	refresh_plots()
	world.sync_festivals()
	to_market_positions(false) if G.phase == "market" else _to_prep_positions()
	_sync_props()
	if G.has_player_pos:
		if G.player_in_room:
			_put_in_room(G.player_pos + Vector3(0, 0.05, 0))
			player.set_facing(G.player_yaw)
		else:
			player.global_position = G.player_pos + Vector3(0, 0.05, 0)
			player.set_facing(G.player_yaw)
			rig.yaw = rad_to_deg(G.player_yaw) + 180.0
	else:
		player.global_position = Layout.SPAWN
		player.set_facing(deg_to_rad(Layout.SPAWN_YAW))
		rig.yaw = -Layout.SPAWN_YAW + 180.0 + 180.0
		if not G.flags.has("arrival_home"):
			G.toast.emit("欢迎来到晴町。先去支巷里的新家看看信箱吧")
	if life != null: life._sync_animal_seed(true)
	rig.snap()


func _sync_props() -> void:
	var G := GameState
	world.stall_bread.visible = G.qstate("Q02") == "done" or G.phase == "market"
	world.poster.visible = G.qstate("Q04") == "done" or G.phase == "market"


## v0.6: activity loops. At a festival each neighbour on the bill wanders between its spot and the stops in
## festivals.json "roam"; at the Saturday market they browse (Layout.MARKET_ROAM). Anything else stops the loop.
func _sync_roams() -> void:
	var G := GameState
	var fid := G.festival_on(G.day)
	var f := G.festival(fid)
	for id in npcs:
		var n: NPC = npcs[id]
		var key := ""
		var stops: Array = []
		if n.fest_key != "" and n.fest_key == fid and not dancing:
			var extra: Array = (f.get("roam", {}) as Dictionary).get(id, [])
			if not extra.is_empty():
				var e: Array = f.npc[id]
				var off := FarmBuilder.ORIGIN if str(e[0]) == "farm" else Vector3.ZERO
				var p: Array = e[1]
				key = "fest:" + fid
				stops.append([Vector3(float(p[0]), float(p[1]), float(p[2])) + off, float(e[2]), str(e[3]), 6.0])
				for st in extra:
					var q: Array = st[0]
					stops.append([Vector3(float(q[0]), float(q[1]), float(q[2])) + off, float(st[1]), str(st[2]), float(st[3])])
		elif G.phase == "market" and not story.cutscene and n.fest_key == "" and Layout.MARKET_ROAM.has(id) and not n.home:
			var info: Dictionary = Layout.NPC[id]
			key = "market"
			stops.append([info.market, float(info.market_yaw), "talk" if id == "mio" else "idle", 8.0])
			stops.append_array(Layout.MARKET_ROAM[id])
		n.set_roam(key, stops)


func _to_prep_positions() -> void:
	for id in npcs:
		(npcs[id] as NPC).sched_i = -1
	update_npcs(true)


## During the market cut-scene NPCs are moved to the start of their walk while the screen is dark.
func to_market_positions(for_walk: bool) -> void:
	for id in npcs:
		var info: Dictionary = Layout.NPC[id]
		var n: NPC = npcs[id]
		n.set_home(false)
		n.set_pose("idle")
		if for_walk:
			n.place(info.get("route_start", info.prep), info.prep_yaw)
		else:
			n.place(info.market, info.market_yaw)


func before_save() -> void:
	GameState.player_pos = story.public_life.save_position()
	GameState.player_yaw = player._face_yaw
	GameState.player_in_room = in_room


func _put_in_room(at: Vector3 = HouseBuilder.spawn_point()) -> void:
	var saved_kind: String = InteriorBuilder.at(at)
	if saved_kind != "":
		in_room = true
		room_kind = saved_kind
		GameState.player_in_room = true
		player.global_position = at
		player.velocity = Vector3.ZERO
		world.set_indoor_look(true)
		rig.fixed = true
		rig.collide = false
		rig.yaw = 0.0
		rig.pitch = 46.0
		rig.dist = 8.6
		rig.snap()
		update_npcs(true)
		ui.refresh_hud()
		return
	in_room = true
	room_kind = "house"
	GameState.player_in_room = true
	var l := at - HouseBuilder.ORIGIN
	if HouseBuilder.room_at(l).is_empty():
		at = HouseBuilder.spawn_point()
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.set_facing(PI)
	world.set_indoor_look(true)
	world.house.update_cutaway(str(HouseBuilder.room_at(at - HouseBuilder.ORIGIN).get("id", "genkan")), false)
	rig.fixed = true
	rig.collide = false
	rig.yaw = 0.0
	rig.pitch = 50.0
	rig.dist = 9.2
	rig.snap()
	ui.refresh_hud()


## v0.6: which room the player is in while in_room: "house", "store" or "bakery".
var room_kind := ""
var photo_mode := false       # the festival photo is being taken: keep the quest pin hidden


## The general store and the bakery: fade in through the shop door, fixed diorama camera inside.
func enter_interior(k: String) -> void:
	if _transition:
		return
	_transition = true
	GameState.lock_input("transition")
	await _loading_region("走进" + str(InteriorBuilder.spec_for(k).name))
	Audio.fx_at("door",player.global_position,-8)
	await ui.fade_out(0.35)
	in_room = true
	room_kind = k
	GameState.player_in_room = true
	player.global_position = InteriorBuilder.door_point(k)
	player.velocity = Vector3.ZERO
	player.set_facing(PI)
	world.set_indoor_look(true,k)
	rig.fixed = true
	rig.collide = false
	rig.yaw = 0.0
	rig.pitch = 46.0
	rig.dist = 8.6
	rig.snap()
	if k == "bakery" and not npcs.ren.home:
		var sp := InteriorBuilder.spec_for("bakery")
		npcs.ren.place(sp.origin + sp.keeper, sp.keeper_yaw)
		npcs.ren.fest_key = "bakery:counter"
	elif k == "store" and not npcs.kazuko.home:
		var sp2 := InteriorBuilder.spec_for("store")
		npcs.kazuko.place(sp2.origin + sp2.keeper, sp2.keeper_yaw)
		npcs.kazuko.fest_key = "store:counter"
	Audio.set_indoor(true)
	Audio.play_music("shop", 1.5)
	await ui.fade_in(0.35)
	Loading.finish()
	GameState.unlock_input("transition")
	_transition = false
	if shop_life:shop_life.on_enter(k)


func exit_interior() -> void:
	story.public_life.stand(true)
	if _transition:
		return
	if shop_life:shop_life.on_exit()
	_transition = true
	GameState.lock_input("transition")
	await _loading_region("回到晴町街道")
	Audio.fx_at("door",player.global_position,-8)
	await ui.fade_out(0.35)
	var sp := InteriorBuilder.spec_for(room_kind)
	Audio.set_indoor(false, outdoor_amb())
	Audio.play_music(music_for_now(), 1.5)
	in_room = false
	room_kind = ""
	GameState.player_in_room = false
	world.set_indoor_look(false)
	rig.collide = true
	player.global_position = sp.exit
	player.velocity = Vector3.ZERO
	player.set_facing(0.0)
	rig.fixed = false
	rig.yaw = 0.0
	rig.pitch = 30.0
	rig.dist = 7.0
	rig.snap()
	if npcs.ren.fest_key == "bakery:counter":
		npcs.ren.fest_key = ""
		npcs.ren.sched_i = -1
		update_npcs(true)
	if npcs.kazuko.fest_key == "store:counter":
		npcs.kazuko.fest_key = ""
		npcs.kazuko.sched_i = -1
		update_npcs(true)
	await ui.fade_in(0.35)
	Loading.finish()
	GameState.unlock_input("transition")
	_transition = false


func enter_room() -> void:
	if _transition:
		return
	_transition = true
	GameState.lock_input("transition")
	await _loading_region("走进奶奶的家")
	Audio.fx_at("door",player.global_position,-8)
	await ui.fade_out(0.35)
	_put_in_room()
	Audio.set_indoor(true)
	await ui.fade_in(0.35)
	Loading.finish()
	GameState.unlock_input("transition")
	_transition = false


func exit_room() -> void:
	story.public_life.stand(true)
	if _transition:
		return
	_transition = true
	GameState.lock_input("transition")
	await _loading_region("回到晴町街道")
	Audio.fx_at("door",player.global_position,-8)
	await ui.fade_out(0.35)
	Audio.set_indoor(false, outdoor_amb())
	in_room = false
	room_kind = ""
	GameState.player_in_room = false
	world.set_indoor_look(false)
	rig.collide = true
	ui.refresh_hud()
	player.global_position = Layout.HOME_EXIT
	player.velocity = Vector3.ZERO
	player.set_facing(-PI / 2.0)
	rig.fixed = false
	rig.yaw = 90.0
	rig.pitch = 35.0
	rig.dist = 6.5
	rig.snap()
	await ui.fade_in(0.35)
	Loading.finish()
	GameState.unlock_input("transition")
	_transition = false


func _loading_region(text: String) -> void:
	if ui.instant:
		return
	Loading.begin(text, false)
	await get_tree().process_frame


func go_title() -> void:
	Audio.game_on = false
	GameState.clear_locks()
	GameState.clock_paused = false
	get_tree().paused = false
	Loading.change_scene("res://scenes/title.tscn", "回到晴町的开始")


func area_name() -> String:
	if in_room and room_kind != "house" and room_kind != "":
		return str(InteriorBuilder.spec_for(room_kind).name)
	if in_room:
		return world.house.room_name(player.global_position)
	if world.region == "farm":
		var q := player.global_position - FarmBuilder.ORIGIN
		if q.x>67.0:return "镜波湖"
		if q.x>28.0:return "晴川河湾"
		return "河边" if q.z > 10.0 else "河边市民农园"
	var p := player.global_position
	for a in Layout.AREAS:
		if p.x >= a[1] and p.x <= a[3] and p.z >= a[2] and p.z <= a[4]:
			return a[0]
	return "晴町"


func _process(delta: float) -> void:
	if not loading_ready:
		return
	world.update_time(GameState.minute, GameState.weather)
	NPC.freeze = story.busy or story.cutscene or dancing or _transition or GameState.input_locked()
	var pp := player.global_position
	RenderingServer.global_shader_parameter_set("grass_push", Vector4(pp.x, pp.y, pp.z, 0.85))
	_amb_check -= delta
	if _amb_check <= 0.0:
		_amb_check = 1.0
		if not in_room and not _transition:
			Audio.play_amb(outdoor_amb(), 3.0)
		weather_fx.set_weather(GameState.weather, in_room)
		_music_tick()
		if not story.busy:
			story.lore.checks()
			story.bakery.checks()
		_sync_roams()
	ui.set_area(area_name())
	var t := player.target
	ui.set_prompt(story.prompt_for(t.id) if t and not GameState.input_locked() else "")
	_marker_t += delta
	var mt = story.marker_target()
	marker.visible = mt != null and (not in_room or player.global_position.distance_to(mt) < 22.0) and not placement.active and ui.modal == "" and not photo_mode and not (photo!=null and photo.active) and not GameState._ui_locks.has("arrival")
	if marker.visible:
		var mp: Vector3 = mt
		marker.global_position = mp + Vector3(0, 0.12 * sin(_marker_t * 3.0), 0)
		var d := mp.distance_to(player.global_position)
		marker.modulate.a = clampf((d - 1.5) / 3.0, 0.25, 0.95)


var _safe_pos := Vector3.INF     # where the player last stood on solid ground (fall rescue)
var _safe_t := 0.0

func _physics_process(delta: float) -> void:
	if not loading_ready:
		return
	if in_room and room_kind == "house" and not _transition:
		var l := player.global_position - HouseBuilder.ORIGIN
		var previous_house_room: String = world.house.current_room
		world.house.track_player(player.global_position)
		if previous_house_room != world.house.current_room: ui.refresh_hud()
		if l.z > HouseBuilder.EXIT_Z and l.x > HouseBuilder.DOOR_X[0] - 0.3 and l.x < HouseBuilder.DOOR_X[1] + 0.3:
			exit_room()
	# v0.6: walking out through a shop's door goes back to the street, like the house's front door
	if in_room and InteriorBuilder.SPECS.has(room_kind) and not _transition \
			and InteriorBuilder.walked_out(room_kind, player.global_position):
		exit_interior()
	if _transition:
		_safe_t = 0.0
		return
	if player.is_on_floor():
		_safe_t += delta
		if _safe_t > 0.4:
			_safe_t = 0.0
			_safe_pos = player.global_position
	elif player.global_position.y < -3.0:
		_fall_rescue()


## Anywhere (street, farm, house, shops): whoever drops below the ground is put back where they last stood.
func _fall_rescue() -> void:
	var p := player.global_position
	var to := _safe_pos
	if to == Vector3.INF or Vector2(to.x - p.x, to.z - p.z).length() > 40.0:
		if in_room and room_kind != "house":
			to = InteriorBuilder.door_point(room_kind)
		elif in_room:
			to = HouseBuilder.spawn_point()
		elif world.region == "farm":
			to = FarmBuilder.ORIGIN + FarmBuilder.ENTRY
		else:
			to = Layout.SPAWN
	print("RESCUE fell at %s -> %s" % [p, to])
	player.global_position = to + Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	_safe_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if player.seated and event.is_action_pressed("ui_cancel") and not story.busy:
		story.public_life.stand();get_viewport().set_input_as_handled();return
	if not loading_ready:
		return
	if event.is_action_pressed("build") and not in_room:
		get_viewport().set_input_as_handled()
		story.try_build()
