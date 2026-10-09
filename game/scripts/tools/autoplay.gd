extends Node
## Scripted full playthrough for evidence and the gameplay video.
##   godot --path game -- --autoplay [--shots-dir=<dir>]
## Movie:  godot --path game --write-movie out.avi --fixed-fps 30 -- --autoplay
## The character walks between stops on a small waypoint graph; all actions go through the
## same Story.interact() the keyboard uses, with dialogue auto-advancing.

var main: Node
var G: Node
var shot_dir := ""
var shot_n := 0
var astar := AStar2D.new()
var fastar := AStar2D.new()
var _fnames := {}

const NODES := {
	"bus": Vector2(-41.0, -10.2), "s0": Vector2(-36.0, -10.6), "s1": Vector2(-24.0, -10.6), "s2": Vector2(-12.0, -10.6),
	"s3": Vector2(-3.0, -10.6), "s4": Vector2(8.0, -10.6), "s5": Vector2(19.7, -10.6),
	"gate": Vector2(-3.0, -6.4), "c0": Vector2(-3.0, -2.6), "c1": Vector2(-3.0, 0.2),
	"c1b": Vector2(-4.4, 1.7), "c2": Vector2(-3.4, 12.6), "c3": Vector2(1.0, 12.6), "c4": Vector2(10.4, 12.6),
	"g1": Vector2(10.6, 15.6), "g2": Vector2(10.6, 20.4), "sgi": Vector2(15.6, 8.5),
	"sgo": Vector2(19.7, 8.5), "l0": Vector2(19.7, -6.6), "l1": Vector2(19.7, 1.4), "l2": Vector2(19.7, 5.9),
	"s6": Vector2(30.0, -10.6), "s7": Vector2(39.4, -10.6),
}
## The riverside allotment, in farm-local metres (FarmBuilder.ORIGIN is added).
const FNODES := {
	"f_in": Vector2(-25.5, 0.3), "f_w": Vector2(-16.0, 0.3), "f_shed": Vector2(-10.3, 0.3), "f_pump": Vector2(-7.2, 0.3),
	"f_mid": Vector2(0.0, 0.3), "f_stand": Vector2(6.5, 0.3), "f_e": Vector2(12.0, 0.3), "f_river": Vector2(0.0, 10.8),
	"f_bench": Vector2(8.0, 10.8),
}
const FEDGES := [["f_in", "f_w"], ["f_w", "f_shed"], ["f_shed", "f_pump"], ["f_pump", "f_mid"], ["f_mid", "f_stand"],
	["f_stand", "f_e"], ["f_mid", "f_river"], ["f_river", "f_bench"]]
const HOUSE_KITCHEN_STAND := Vector3(-4.7, 0.05, 2.7)
const FSTAND := {
	"plot_farm0": [Vector2(-3.45, -1.85), "f_mid"], "plot_farm1": [Vector2(-1.15, -1.85), "f_mid"],
	"plot_farm2": [Vector2(1.15, -1.85), "f_mid"], "plot_farm3": [Vector2(3.45, -1.85), "f_mid"],
	"farm_pump": [Vector2(-7.2, -2.2), "f_pump"], "farm_bench": [Vector2(9.6, 10.9), "f_bench"],
	"veggie_stand": [Vector2(6.5, 1.4), "f_stand"], "farm_exit": [Vector2(-27.2, 0.3), "f_in"],
}
const EDGES := [
	["bus", "s0"], ["s0", "s1"], ["s1", "s2"], ["s2", "s3"], ["s3", "s4"], ["s4", "s5"], ["s3", "gate"], ["gate", "c0"],
	["c0", "c1"], ["c1", "c1b"], ["c1b", "c2"], ["c2", "c3"], ["c3", "c4"], ["c4", "g1"], ["g1", "g2"], ["c4", "sgi"],
	["sgi", "sgo"], ["sgo", "l2"], ["l2", "l1"], ["l1", "l0"], ["l0", "s5"], ["s5", "s6"], ["s6", "s7"],
]
## Where to stand for each target, and which graph node leads there.
const STAND := {
	"mailbox": [Vector2(20.2, 1.4), "l1"], "home_door": [Vector2(20.4, 5.9), "l2"],
	"board": [Vector2(-8.4, -7.5), "s2"], "stall": [Vector2(2.0, 12.8), "c3"],
	"planter": [Vector2(12.0, 15.5), "g1"], "tap": [Vector2(9.0, 21.1), "g2"],
	"center_door": [Vector2(-23.2, -7.4), "s1"], "shop_zakka": [Vector2(0.0, -13.7), "s3"],
	"shop_florist": [Vector2(-12.0, -13.7), "s2"], "build_sign": [Vector2(-2.6, -0.3), "c1"],
	"mio": [Vector2(-5.9, -8.0), "s3"], "ren": [Vector2(-22.3, -12.9), "s1"], "haru": [Vector2(13.0, 15.1), "g1"],
	"mio_m": [Vector2(-0.8, 11.8), "c2"], "ren_m": [Vector2(3.2, 12.6), "c3"], "haru_m": [Vector2(6.9, 12.5), "c3"],
	"goldfish_pool": [Vector2(-6.0, 16.9), "c2"], "east_end": [Vector2(43.6, -11.0), "s7"],
	"shop_store": [Vector2(-36.0, -13.4), "s0"], "bakery": [Vector2(-23.12, -13.4), "s1"],
	"tanabata_bamboo": [Vector2(-1.1, -1.6), "c0"], "offer_stand": [Vector2(-1.2, -0.4), "c0"],
	"contest_stand": [Vector2(-6.2, 6.9), "c1"], "yagura_stand": [Vector2(-2.6, 15.0), "c2"],
}
## Walks inside the house, in house-local metres (x east, z south).
const HOUSE_TOUR := [Vector2(5.0, 2.4), Vector2(5.0, 0.3), Vector2(4.2, -1.9), Vector2(3.2, -2.4)]
const HOUSE_TO_KITCHEN := [Vector2(2.4, -0.2), Vector2(1.9, 0.5), Vector2(1.9, 1.7), Vector2(1.6, 2.6), Vector2(-0.3, 2.6), Vector2(-0.8, 1.95), Vector2(-4.35, 2.05)]
const HOUSE_TO_DOOR := [Vector2(-0.8, 1.95), Vector2(-0.2, 2.6), Vector2(2.0, 2.7), Vector2(4.2, 3.2), Vector2(5.0, 3.9)]


func _ready() -> void:
	main = get_parent()
	G = GameState
	main.ui.auto = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			shot_dir = a.substr(12)
	if shot_dir != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
	var ids := {}
	var i := 0
	for k in NODES:
		ids[k] = i
		astar.add_point(i, NODES[k])
		i += 1
	for e in EDGES:
		astar.connect_points(ids[e[0]], ids[e[1]])
	var fi := 0
	for k in FNODES:
		_fnames[k] = fi
		fastar.add_point(fi, FNODES[k] + Vector2(FarmBuilder.ORIGIN.x, FarmBuilder.ORIGIN.z))
		fi += 1
	for e in FEDGES:
		fastar.connect_points(_fnames[e[0]], _fnames[e[1]])
	await get_tree().create_timer(1.5).timeout
	main.ui.auto_work_priority = true
	if SummerProjects.uses_cooperation_mainline():
		var full_route:=SummerAutoplay.new(self)
		var passed: bool=await full_route.run()
		get_tree().call_group("spatial_audits", "finish")
		Audio.silence()
		get_tree().quit(0 if passed else 1)
		return
	await play()
	await get_tree().create_timer(2.0).timeout
	print("AUTOPLAY DONE  time=%.1fs  Q05=%s" % [G.play_time, G.qstate("Q05")])
	get_tree().call_group("spatial_audits", "finish")
	Audio.silence()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()


func shot(name: String) -> void:
	shot_n += 1
	# the movie timeline (fixed fps) follows the frame count; the highlight reel cuts by these marks
	print("AP  mark %s  frame=%d  t=%.2f" % [name, Engine.get_frames_drawn(), Time.get_ticks_msec() / 1000.0])
	if shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	print("AP  shot %02d %s" % [shot_n, name])
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [shot_dir, shot_n, name])


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


# ------------------------------------------------------------------ movement
func _nearest(p: Vector2) -> int:
	return astar.get_closest_point(p)


func _farm() -> bool:
	return main.world.region == "farm"


func walk_to(stand: Vector2, via: String, run: bool = true) -> void:
	var p := Vector2(main.player.global_position.x, main.player.global_position.z)
	var g: AStar2D = fastar if _farm() else astar
	var goal: int = g.get_closest_point(stand) if via == "" else (_fnames[via] if _farm() else astar.get_closest_point(NODES[via]))
	var path: PackedVector2Array = g.get_point_path(g.get_closest_point(p), goal)
	var pts: Array = []
	for q in path:
		pts.append(q)
	# skip the first node if we are already past it toward the second
	if pts.size() >= 2 and p.distance_to(pts[1]) < pts[0].distance_to(pts[1]):
		pts.pop_front()
	pts.append(stand)
	for q in pts:
		await drive(q, run)
	main.player.auto_move = Vector3.ZERO


func drive(target: Vector2, run: bool) -> void:
	var stuck := 0.0
	var last := Vector2(INF, INF)
	var t := 0.0
	while true:
		var p := Vector2(main.player.global_position.x, main.player.global_position.z)
		var d := target - p
		if d.length() < 0.3:
			break
		main.player.auto_run = run and d.length() > 2.0
		main.player.auto_move = Vector3(d.x, 0, d.y).normalized()
		# keep the camera behind the character, softly (the house diorama keeps its fixed view)
		if not main.rig.fixed:
			var want := rad_to_deg(atan2(d.x, d.y)) + 180.0
			main.rig.yaw = rad_to_deg(lerp_angle(deg_to_rad(main.rig.yaw), deg_to_rad(want), 0.03))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if p.distance_to(last) < 0.02:
			stuck += get_physics_process_delta_time()
		else:
			stuck = 0.0
		last = p
		if t > 25.0:
			print("AP  drive gave up at %s -> %s" % [p, target])
			main.player.global_position = Vector3(target.x, main.player.global_position.y, target.y)
			break
		if stuck > 1.2:
			# blocked by something unexpected: step aside, then continue
			print("AP  stuck at %s -> %s, stepping aside" % [p, target])
			main.player.global_position += Vector3(-d.y, 0, d.x).normalized() * 0.6
			stuck = 0.0
	main.player.auto_move = Vector3.ZERO


func point(id: String) -> Interactable:
	if main.npcs.has(id):
		return (main.npcs[id] as NPC).talk
	for n in get_tree().get_nodes_in_group("interactables"):
		if (n as Interactable).id == id:
			return n
	return null


func use(id: String, choices: Array = [], stand_key: String = "") -> void:
	var sk := stand_key if stand_key != "" else id
	print("AP  use %s  t=%.1f  day %d %s" % [sk, G.play_time, G.day, G.clock_text()])
	var held: NPC = main.npcs.get(id)
	if held:
		held.hold = true      # v0.6: an NPC on an activity loop waits where it is while we walk over
	if main.npcs.has(id) and (stand_key == "" or held.roaming()):
		# neighbours follow their routines: go to wherever they are now
		var n: NPC = main.npcs[id]
		while n.is_moving() and not n._roam_leg:
			await wait(0.3)
		var np := Vector2(n.global_position.x, n.global_position.z)
		var g: AStar2D = fastar if _farm() else astar
		var via := g.get_point_position(g.get_closest_point(np))
		var off := (via - np)
		off = off.normalized() * 1.3 if off.length() > 0.2 else Vector2(0, 1.3)
		var stand := np + off
		if _farm():
			var l := np - Vector2(FarmBuilder.ORIGIN.x, FarmBuilder.ORIGIN.z)
			if absf(l.x) < 5.4 and l.y < -1.6 and l.y > -9.4:
				stand = Vector2(np.x, FarmBuilder.ORIGIN.z - 1.7)     # in the bed aisles: talk from the path
			elif l.x < -8.0 and l.y < -2.0:
				stand = np + Vector2(0.0, 1.3)                         # in front of the shed
		await walk_to(stand, "")
	elif _farm() and FSTAND.has(sk):
		var f: Array = FSTAND[sk]
		await walk_to(f[0] + Vector2(FarmBuilder.ORIGIN.x, FarmBuilder.ORIGIN.z), f[1])
	elif STAND.has(sk):
		await walk_to(STAND[sk][0], STAND[sk][1])
	var it := point(id)
	main.player.face_towards(it.global_position)
	for i in 30:
		await get_tree().physics_frame
		if main.player.target == it:
			break
	await wait(0.25)
	main.ui.auto_choices = choices.duplicate()
	await main.story.interact(it)
	await wait(0.4)
	if held:
		held.hold = false


## v0.6: walk into a shop, along `path` (interior-local x/z) to a point, use it, and walk out again.
const SHOP_PATHS := {
	"store_counter": ["store", [Vector2(0.0, 2.2), Vector2(-1.5, 1.95)]],
	"bakery_counter": ["bakery", [Vector2(1.6, 2.2), Vector2(1.95, 1.75)]],
	"bakery_oven": ["bakery", [Vector2(1.6, 2.2), Vector2(-1.2, 1.6), Vector2(-1.2, -1.3), Vector2(2.2, -1.25)]],
}


func shop_visit(door: String, pt: String, choices: Array = [], shot_name: String = "") -> void:
	await use(door)
	await wait(0.8)
	if not main.in_room:
		return
	var info: Array = SHOP_PATHS[pt]
	var o: Vector3 = InteriorBuilder.spec_for(info[0]).origin
	for q in info[1]:
		await drive(Vector2(o.x + q.x, o.z + q.y), false)
	main.player.auto_move = Vector3.ZERO
	var it := point(pt)
	main.player.face_towards(it.global_position)
	await wait(0.5)
	if shot_name != "":
		shot_later(1.2, shot_name)
	main.ui.auto_choices = choices.duplicate()
	await main.story.interact(it)
	await wait(0.4)
	var back: Array = (info[1] as Array).duplicate()
	back.reverse()
	for q in back:
		await drive(Vector2(o.x + q.x, o.z + q.y), false)
	main.player.auto_move = Vector3.ZERO
	var ex := point("bakery_exit" if info[0] == "bakery" else "store_exit")
	main.player.face_towards(ex.global_position)
	await wait(0.3)
	main.ui.auto_choices = []
	await main.story.interact(ex)
	await wait(0.8)


## Take a screenshot a little later without blocking (used while a mini-game is running).
func shot_later(t: float, name: String) -> void:
	await wait(t)
	await shot(name)


func house_walk(pts: Array, run: bool = false) -> void:
	for q in pts:
		var w: Vector3 = HouseBuilder.ORIGIN + Vector3(q.x, 0, q.y)
		await drive(Vector2(w.x, w.z), run)
	main.player.auto_move = Vector3.ZERO


func look(yaw: float, pitch: float, dist: float, t: float = 1.2) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(main.rig, "yaw", yaw, t).set_trans(Tween.TRANS_SINE)
	tw.tween_property(main.rig, "pitch", pitch, t).set_trans(Tween.TRANS_SINE)
	tw.tween_property(main.rig, "dist", dist, t).set_trans(Tween.TRANS_SINE)
	await tw.finished


# ------------------------------------------------------------------ the day
func play() -> void:
	await look(250.0, 24.0, 7.5, 0.01)
	await wait(1.0)
	await shot("arrival")
	await look(290.0, 30.0, 6.5, 2.0)
	# Q00 — walk down the street to the lane and the new house
	await use("mailbox")
	await shot("mailbox")
	await use("home_door")
	await shot("room")
	await wait(0.8)
	# the house: through the living room (light through the engawa doors), then the kitchen,
	# where the rice cooker starts the onigiri mini-game
	await house_walk(HOUSE_TOUR)
	await wait(1.2)
	await shot("house_living")
	await house_walk(HOUSE_TO_KITCHEN)
	shot_later(30.0, "onigiri_play")
	await use("house_rice")
	await shot("onigiri_done")
	await house_walk(HOUSE_TO_DOOR)
	main.player.auto_move = Vector3(0, 0, 1)
	while main.in_room:
		await get_tree().physics_frame
	main.player.auto_move = Vector3.ZERO
	await wait(1.0)
	# Q01 — meet Mio and read the board
	await use("mio", [0])
	await shot("meet_mio")
	await use("board")
	await shot("checklist_done")
	# Q04 first leg: sign from the community centre
	await use("center_door")
	# Q02 — Ren's basket
	await use("ren", [0])
	await shot("bakery")
	# Q04 second leg: post the sign
	await use("board")
	await shot("poster")
	await use("stall")
	await shot("bread_on_stall")
	# courtyard station: scoop goldfish at the practice tank
	shot_later(26.0, "goldfish_play")
	await use("goldfish_pool")
	await shot("goldfish_done")
	# Q03 — Haru's planter
	await use("haru", [0])
	await use("planter")
	await use("tap")
	await use("planter")
	await shot("watered")
	await use("haru")
	# Q05 — plan with Mio, buy decor, lay out the courtyard
	await use("mio")
	await use("shop_zakka", [["lantern"]])
	await shot("shop")
	await walk_to(STAND["build_sign"][0], STAND["build_sign"][1])
	var sign := point("build_sign")
	main.player.face_towards(sign.global_position)
	await wait(0.5)
	main.story.interact(sign)
	await wait(1.2)
	var pl: PlacementSystem = main.placement
	var plan := [["picnic_table", 6.5, 4.0, 0], ["bench", 6.5, 6.2, 0], ["bench", 2.5, 10.0, 0],
		["flower_pot", 2.0, 4.0, 0], ["lantern", 8.8, 10.5, 0]]
	for step in plan:
		pl._select(step[0])
		pl.rot = step[3]
		await wait(0.4)
		await _glide_mouse(pl, Vector3(step[1], 0, step[2]))
		await wait(0.35)
		pl.try_place()
		await wait(0.5)
	await shot("placement")
	await wait(0.8)
	pl.exit()
	await wait(1.0)
	await use("ren", [0])
	await use("haru", [0])
	# v0.4: the market waits for Saturday evening. Meanwhile: the riverside allotment.
	await use("mio")
	await shot("mio_saturday")
	await use("haru")
	await shot("haru_letter")
	# v0.5: the general store at the west end of the street (seeds, flour, sugar...)
	await shop_visit("shop_store", "store_counter", [{"buy": {"seed_carrot": 1, "rice": 2, "sugar": 1, "miso": 1}}], "general_store")
	await use("east_end")
	await wait(1.0)
	await shot("farm_arrival")
	await look(-90.0, 26.0, 8.5, 1.6)
	await use("tanaka")
	await shot("tanaka")
	await use("plot_farm0")
	await use("plot_farm0", _seed_choices("seed_komatsuna"))
	await use("plot_farm0")
	await shot("first_seeds")
	await use("plot_farm1")
	await use("plot_farm1", [0])
	await use("plot_farm1")
	await use("tanaka")
	await shot("q06_done")
	# sunset over the river: let the clock run fast for a few seconds
	await use("farm_bench", [1])
	await look(135.0, 12.0, 7.0, 2.0)
	G.skip_to(maxf(G.minute, 16.8 * 60.0))
	G.time_scale = 18.0
	await wait(3.6)
	await shot("river_sunset")
	await wait(3.4)
	G.time_scale = 1.0
	await shot("river_night")
	# home through the lamp-lit town, and to bed
	await use("farm_exit")
	await wait(1.0)
	await look(90.0, 26.0, 7.0, 1.0)
	await use("home_door")
	await wait(0.6)
	await shot("night_home")
	await sleep_in_bed()
	await shot("morning_day2")
	# breakfast: tsukimi dango from yesterday's shopping, in the home kitchen
	await main.ui.fade_out(0.3)
	main.player.global_position = HouseBuilder.ORIGIN + HOUSE_KITCHEN_STAND
	await main.ui.fade_in(0.3)
	var stove := point("house_stove")
	main.player.face_towards(stove.global_position)
	await wait(0.6)
	main.ui.auto_choices = [{"craft": {"dango": 1}}]
	shot_later(1.0, "kitchen_cooking")
	await main.story.interact(stove)
	await wait(0.6)
	await leave_house()
	# Friday: Haru's granddaughter has arrived
	while G.hour() < 7.7:
		await wait(0.3)
	await use("aoi", [0])
	await shot("meet_aoi")
	await use("east_end")
	await wait(0.8)
	await use("farm_pump")
	await use("plot_farm0")
	await use("plot_farm1")
	await use("plot_farm2")
	await use("plot_farm2", _seed_choices("seed_sunflower"))
	await use("plot_farm2")
	await shot("farm_day2")
	await look(180.0, 34.0, 9.0, 1.5)
	await wait(2.5)
	await shot("tanaka_tending")
	await use("farm_exit")
	# the bakery: Ren's shelves, the oven and the little mill
	await shop_visit("bakery", "bakery_oven", [{}], "bakery_oven")
	G.skip_to(maxf(G.minute, 21.5 * 60.0))
	await wait(0.5)
	await use("home_door")
	await sleep_in_bed()
	await shot("morning_saturday")
	await leave_house()
	# Saturday: the first harvest, a gift, then the market
	await use("east_end")
	await wait(0.6)
	await use("farm_pump")
	await use("plot_farm0")
	await shot("harvest")
	await use("plot_farm1")
	await use("plot_farm2")
	await use("farm_exit")
	await use("ren", [0, 0])
	await shot("gift_ren")
	await use("mio", [0, 0])
	await wait(1.0)
	await shot("market_evening")
	await use("mio", [], "mio_m")
	await use("ren", [], "ren_m")
	await use("haru", [], "haru_m")
	await wait(3.0)
	await shot("ending")
	while main.ui.modal == "chapter_summary":
		await wait(0.2)
	# from the east side of the courtyard, clear of the zelkova's canopy
	await look(90.0, 26.0, 9.0, 3.0)
	await wait(2.0)
	await shot("finale")
	# the market goes on: sell the day's harvest and the dango at the stall
	await use("stall", [mini(main.story.farm._market_goods().size(), 4)], "stall")
	await shot("market_stall")
	# Sunday is Tanabata: sleep, then the evening under the bamboo
	await use("home_door")
	await sleep_in_bed()
	await shot("morning_tanabata")
	# v0.6 chapter 3 starts this morning: grandma's box in the bedroom closet, then Mio
	await wait(4.0)
	await house_walk([Vector2(-4.6, 0.3)])
	var cl := point("room_closet")
	main.player.face_towards(cl.global_position)
	await wait(0.4)
	main.ui.auto_choices = []
	shot_later(9.0, "grandma_box")
	await main.story.interact(cl)
	await wait(0.6)
	await leave_house()
	await use("mio", [0])
	await shot("mio_photo")
	await main.ui.fade_out(0.6)
	G.skip_to(17.6 * 60.0)
	main.world.update_time(G.minute, G.weather, true)
	await main.ui.fade_in(0.6)
	await use("tanabata_bamboo", [0])
	await shot("tanabata_wish")
	await look(20.0, 12.0, 9.0, 3.0)
	G.time_scale = 12.0
	await wait(4.0)
	G.time_scale = 1.0
	await shot("tanabata_night")


func _seed_choices(sid: String) -> Array:
	var seeds: Array = G.seeds_owned()
	seeds.sort_custom(func(a, b): return G.count(a) > G.count(b))
	var index: int = maxi(seeds.find(sid), 0)
	var choices: Array = []
	for page in range(index / 4):
		choices.append(4)
	choices.append(index % 4)
	return choices


## In the house: step to the bed and sleep through to the next morning.
func sleep_in_bed() -> void:
	await wait(0.4)
	var bed := point("room_bed")
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(-4.2, 0.05, -1.1)
	main.player.face_towards(bed.global_position)
	await wait(0.6)
	main.ui.auto_choices = [0]
	await main.story.interact(bed)
	await wait(1.5)


func leave_house() -> void:
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(5.0, 0.05, 2.6)
	await wait(0.3)
	main.player.auto_move = Vector3(0, 0, 1)
	while main.in_room:
		await get_tree().physics_frame
	main.player.auto_move = Vector3.ZERO
	await wait(0.8)


func _glide_mouse(pl: PlacementSystem, world: Vector3) -> void:
	var to := pl.cam.unproject_position(world)
	var from := pl._mouse if pl._mouse != Vector2.ZERO else get_viewport().get_visible_rect().size / 2.0
	for i in 20:
		pl._mouse = from.lerp(to, (i + 1) / 20.0)
		pl._update()
		await get_tree().process_frame
