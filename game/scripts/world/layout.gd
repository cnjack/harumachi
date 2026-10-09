class_name Layout
## Static layout of 晴町 (Hare-machi). Godot axes: +X east, +Z south, +Y up.
## Models face +Z by default, so yaw 180 faces north (-Z), yaw -90 faces west (-X), yaw 90 faces east.
##
##   north row shops     fronts at z = -15.5 (face south onto the street)
##   main street         road z -14 .. -8, sidewalks to -15.5 and -5.5 (10 m facade to facade)
##   south row + courtyard gate at z = -5.5
##   shared courtyard    x -13 .. 17, z -5.5 .. 24
##   residential lane    x 17.2 .. 22.2, z -5.5 .. 32 (player's house on its east side)

const STREET_Z := -11.0
const STREET_HALF := 3.0
const ROOM_ORIGIN := Vector3(0, 0, 400)

## [model_id, x, z, yaw, collide(0 none / 1 box / 2 small box)]
const BUILDINGS := [
	# north row
	["S01", -36.0, -19.3, 0, 1],
	["S02", -24.0, -19.3, 0, 1],     # bakery (Ren)
	["S03", -12.0, -19.7, 0, 1],     # florist (shop: flower pot)
	["S08", 0.0, -19.8, 0, 1],       # zakka shop (shop: bunting / lantern)
	["S05", 12.5, -20.3, 0, 1],      # post office
	["H02", 25.5, -18.4, 0, 1],      # apartment
	["M05_residential", 33.3, -16.9, 0, 1],
	["M01_timber_machiya", 38.2, -16.8, 0, 1],
	# south row (face north)
	["H03", -35.0, -3.0, 180, 1],
	["S06", -23.2, -0.1, 180, 1],    # community centre (event sign)
	# lane, east side (face west)
	["H01", 26.8, 5.5, -90, 1],      # player's house
	["H03", 24.9, 16.0, -90, 1],
	["M03_gable_house", 24.2, 26.5, -90, 1],
	["H04", 32.0, -3.9, 180, 1],     # garden gate on the street's south side, east of the lane
	# South residential street, with independent plots on both sides.
	["H03", 28.4, 43.0, -90, 1],
	["M03_gable_house", 6.4, 43.0, 90, 1],
	["M03_gable_house", 28.4, 60.0, -90, 1],
	["M05_residential", 6.4, 60.0, 90, 1],
	["M05_residential", 28.4, 77.0, -90, 1],
	["H03", 6.4, 77.0, 90, 1],
]

const PROPS := [
	# street furniture
	["R06", -43.0, -4.6, 180, 1],
	["R08a", -31.0, -6.0, 180, 2], ["R08a", -16.5, -6.0, 180, 2], ["R08a", 8.0, -6.0, 180, 2],
	["R08a", 30.0, -6.0, 180, 2], ["R08a", 17.8, 3.0, 90, 2], ["R08a", 17.8, 20.0, 90, 2],
	["M07_power_pole", -30.0, -14.9, 0, 2], ["M07_power_pole", -6.0, -14.9, 0, 2], ["M07_power_pole", 18.5, -14.9, 0, 2],
	["A10_vending_machine", 5.9, -15.95, 0, 1],
	["A11_bicycle", 19.2, -15.9, 12, 0],
	["A13_chalkboard", 9.5, -14.8, -15, 2],   # v0.7.2: was next to the bakery's bread cart; its baked soba-shop sign read wrong there
	["A16_planter_box", -14.3, -14.95, 0, 2], ["A16_planter_box", -9.7, -14.95, 0, 2],
	["A15_potted_plant", -4.0, -15.0, 0, 2], ["A15_potted_plant", 4.1, -15.0, 0, 2],
	["A14_hydrangea_pot", 21.8, 8.6, -90, 2], ["A14_hydrangea_pot", 21.9, 3.4, -90, 2],
	["H07", 21.86, 1.4, -90, 2],     # mailbox at the player's gate (v0.7.3: off the wall end)
	["R09", 22.6, -6.2, -90, 2],     # direction sign at the lane mouth
	# The old end bollards are removed; the lane continues to South Town.       # chain bollards closing the lane end
	["H05", -30.0, -21.9, 0, 0],     # bicycle shelter tucked between shops
	# courtyard
	["P02", -8.5, -6.05, 180, 2],    # notice board (Mio): on the pavement, its back against the low wall
	["P11", 4.0, -4.7, 180, 2],      # little free library
	["R11", -1.0, -5.0, 180, 2],     # clock at the courtyard entrance
	["P09", 2.0, 15.5, 180, 1],      # market stall
	["P01", -9.8, 13.2, 90, 2],      # pergola
	["P04", -10.4, 1.6, 90, 1],      # swing
	["P05", -10.4, 7.0, 90, 1],      # slide
	["P06", -6.8, 4.4, 90, 2],       # sandbox
	["P10", -9.8, 20.4, 90, 1],      # little stage
	["P07", 14.4, 21.4, 0, 1],       # raised vegetable beds
	["P08", 16.0, 15.2, -90, 1],     # potting bench
	["P12", 9.0, 22.9, 0, 2],        # drinking tap (fill the can)
	["R10", 3.4, 23.3, 180, 1],      # recycling station
	["H06", 15.4, 1.0, -90, 1],      # garden shed
	["A12_bench", -2.0, 23.3, 180, 2],
	["A16_planter_box", 11.0, -4.5, 180, 2], ["A16_planter_box", 14.6, -4.5, 180, 2],
	["A15_potted_plant", -12.2, -4.3, 0, 2],
	# v0.5: the general store, the bakery's cart, and odds and ends so open ground is not bare
	# v0.7.3: the shop front is at z -15.51; the levelled shelf and crates stood half inside it
	["G10_store_shelf", -33.8, -15.2, 0, 1], ["D03_veg_crates", -38.4, -15.15, 10, 1],
	["G11_bread_cart", -21.4, -15.4, -12, 1], ["D07_kei_truck", 33.8, -12.85, 90, 1],
	["D12_flower_planter", -11.1, -5.82, 180, 1], ["D12_flower_planter", 2.6, -5.82, 180, 1],
	["D04_stone_lantern", 15.9, 12.6, -90, 1], ["D10_rocks", 16.0, 11.0, 30, 1], # beside the garden lantern, clear of the side gate
	["D05_hokora", 21.3, 31.2, -90, 1], ["D02_rain_barrel", 23.4, 12.3, -90, 1], # in the house garden, not on the lane
	["D10_rocks", -12.3, 5.2, 30, 1], ["P_signpost", 40.0, -7.2, 0, 2],
]

## Trees / shrubs: [model, x, z, yaw, scale]
const PLANTS := [
	["T05_old_shade_tree", 4.0, 7.0, 20, 1.0],   # courtyard centre zelkova (no-build circle)
	["T01_courtyard_tree", -11.4, 22.6, 140, 0.52], ["T01_courtyard_tree", 15.6, 22.8, 250, 0.48],
	["T01_courtyard_tree", -47.5, -2.6, 90, 0.66], ["T01_courtyard_tree", 40.6, -3.6, 0, 0.62],
	["T01_courtyard_tree", 24.0, 10.8, 220, 0.46], ["T01_courtyard_tree", 24.2, 20.4, 30, 0.5],
	["T01_courtyard_tree", -18.0, -16.2, 10, 0.42], ["T01_courtyard_tree", 32.1, -28.2, 150, 0.42], # rear greenbelt; apartment stair is unobstructed
	["M12d_flower_bush", -11.6, -3.0, 200, 1.0], ["M12d_flower_bush", 16.1, -3.4, 70, 0.95],
	["M12d_flower_bush", 6.9, -16.3, 300, 0.9], ["M12d_flower_bush", -16.2, -3.0, 260, 0.9],
	["M12d_flower_bush", 16.3, 19.0, 40, 0.8], ["M12d_flower_bush", -12.2, 12.6, 100, 0.85],
	["M12b_shrub", 9.6, 18.8, 0, 1.0], ["M12b_shrub", -12.3, 9.8, 60, 1.0], ["M12b_shrub", -12.2, 17.0, 120, 0.9],
	["M12b_shrub", 12.0, 23.2, 200, 0.9], ["M12b_shrub", -7.2, -4.4, 30, 0.8], ["M12b_shrub", 6.6, -4.4, 90, 0.8],
]

## Ground patches: [material, x0, z0, x1, z1]  (drawn in order; later ones sit on top)
const GROUND := [
	["grass", -4.0, 32.2, 42.7, 85.2],
	["stone", 17.2, 32.0, 22.2, 85.2],
	["gravel", -1.0, 50.0, 39.0, 52.5],
	["gravel", -1.0, 67.0, 39.0, 69.5],
	["gravel", -52.2, -25.2, 42.7, 32.2],    # everything inside the boundary walls
	["stone", -52.2, -25.2, 42.7, -5.5],     # street, sidewalks and north lots
	["stone", 17.2, -5.5, 22.2, 32.0],       # lane
	["grass", -13.0, 10.0, -5.8, 24.0],      # lawn by pergola and stage
	["grass", 10.2, 18.6, 17.2, 24.0],       # garden lawn
	["grass", 22.2, -5.5, 42.7, 32.2],       # house gardens east of the lane
	["grass", -52.2, -2.0, -13.2, 1.5],      # back gardens of the south row
]

## Block walls: [x0, z0, x1, z1, height]
const WALLS := [
	[-13.2, -5.4, -13.2, 24.2, 1.5],         # courtyard west
	[-13.2, 24.2, 17.2, 24.2, 1.5],          # courtyard south
	[17.2, -5.4, 17.2, 7.0, 1.2],            # courtyard east (side gate 7..10)
	[17.2, 10.0, 17.2, 24.2, 1.2],
	[-13.2, -5.4, -6.0, -5.4, 0.7],          # low front wall west of the gate
	[0.0, -5.4, 17.2, -5.4, 0.7],            # low front wall east of the gate
	[17.2, 24.2, 17.2, 32.0, 1.4],           # lane west side beyond the courtyard
	[22.2, -5.4, 22.2, 1.0, 1.2],            # lane east side walls between houses
	[22.2, 9.2, 22.2, 12.0, 1.2],
	[22.2, 20.0, 22.2, 21.2, 1.2],
	[-52.2, -25.2, -52.2, -14.7, 1.6],         # west end of the street
	[42.7, -25.2, 42.7, -14.4, 1.6],         # east end, open where the street runs out under the farm gate
	[42.7, -7.6, 42.7, 85.2, 1.6],
	[-52.2, 1.5, -13.2, 1.5, 1.6],           # behind the south row (tight, so the models' roofs stay out of sight)
	[-52.2, -25.2, 42.7, -25.2, 1.6],        # behind the north row
	[-4.0, 85.2, 42.7, 85.2, 1.6],
	[-52.2, -7.3, -52.2, 1.5, 1.6],
]

## Interactables that are not NPCs: [id, x, z, y, radius]
const POINTS := [
	["mailbox", 21.3, 1.4, 1.0, 1.8],
	["home_door", 21.8, 5.9, 1.0, 2.0],
	["board", -8.5, -7.0, 1.2, 2.2],
	["stall", 2.0, 13.9, 1.0, 2.2],
	["planter", 12.0, 16.3, 0.5, 1.9],
	["tap", 9.0, 22.1, 0.8, 1.8],
	["center_door", -23.2, -6.0, 1.0, 2.4],
	["shop_florist", -12.0, -14.9, 1.0, 2.2],
	["shop_zakka", 0.0, -14.9, 1.0, 2.2],
	["bakery", -23.12, -14.9, 1.0, 1.6],
	["bus_stop", -43.0, -6.2, 1.0, 2.0],
	["vending", 5.9, -14.8, 1.0, 1.6],
	["library", 4.0, -6.1, 1.0, 1.8],
	["build_sign", -2.6, 1.0, 0.9, 2.0],
	["shop_store", -36.0, -14.9, 1.0, 2.4],
	
	["east_end", 44.3, -11.0, 1.1, 3.0],
	["west_end", -51.2, -11.0, 1.0, 3.0],
	["zelkova", 4.0, 4.6, 1.2, 2.6],
]

## Mini-game stations in the courtyard: [id, x, z, y, radius] (models placed by WorldBuilder).
const MG_POINTS := [
	["goldfish_pool", -7.4, 16.9, 0.6, 1.8],
	["taiko_drum", -6.9, 20.4, 0.9, 1.7],
]
const GOLDFISH_POS := Vector3(-8.1, 0, 16.9)
const TAIKO_POS := Vector3(-7.7, 0, 20.4)

## The interactive planter lives outside PROPS because its growth stages are separate meshes.
const PLANTER_POS := Vector3(12.0, 0, 17.4)
const PLANTER_YAW := 180.0
const BUILD_SIGN_POS := Vector3(-2.6, 0, 1.7)

## Placement zone (x0, z0, x1, z1) plus rules that keep walkways and the tree free.
const ZONE := [-1.5, 2.0, 9.5, 12.0]
const NOGO_RECTS := [
	[[-1.5, 2.0, 0.0, 12.0], "要留出从门口通往摊位的走道"],
]
const NOGO_CIRCLES := [[Vector2(4.0, 7.0), 2.4, "树下留出一圈空地，别压到树根"]]

const SPAWN := Vector3(-41.0, 0.1, -9.5)
const SPAWN_YAW := 90.0
const HOME_EXIT := Vector3(20.6, 0.1, 5.9)

## NPC stations and walking routes.
const NPC := {
	"mio": {"name": "澪", "model": "CH_mio", "prep": Vector3(-6.4, 0, -6.6), "prep_yaw": 20.0,
		"market": Vector3(-1.2, 0, 13.8), "market_yaw": 160.0,
		"route": [Vector3(-3.0, 0, -6.2), Vector3(-2.2, 0, 8.0), Vector3(-1.2, 0, 13.8)]},
	"ren": {"name": "莲", "model": "CH_ren", "prep": Vector3(-22.3, 0, -14.4), "prep_yaw": 0.0,
		"market": Vector3(3.9, 0, 13.8), "market_yaw": 200.0,
		"route_start": Vector3(-3.0, 0, -3.0),
		"route": [Vector3(-2.0, 0, 9.0), Vector3(1.0, 0, 12.2), Vector3(3.9, 0, 13.8)]},
	"haru": {"name": "春", "model": "CH_haru", "prep": Vector3(13.6, 0, 16.5), "prep_yaw": -120.0,
		"market": Vector3(7.4, 0, 13.6), "market_yaw": 200.0,
		"route": [Vector3(10.2, 0, 13.4), Vector3(7.4, 0, 13.6)]},
	"tanaka": {"name": "田中爷爷", "model": "CH_tanaka", "prep": FarmBuilder.ORIGIN + Vector3(-10.3, 0, -5.2), "prep_yaw": 0.0,
		"market": Vector3(10.8, 0, 11.2), "market_yaw": 230.0,
		"route_start": Vector3(16.2, 0, 8.6), "route": [Vector3(12.0, 0, 10.2), Vector3(10.8, 0, 11.2)]},
	"aoi": {"name": "小葵", "model": "CH_aoi", "prep": Vector3(12.2, 0, 18.2), "prep_yaw": -140.0,
		"market": Vector3(5.9, 0, 11.3), "market_yaw": 170.0,
		"route_start": Vector3(10.6, 0, 16.0), "route": [Vector3(8.4, 0, 11.8), Vector3(5.9, 0, 11.3)]},
	# v0.7.2: the general store's keeper stands behind her counter inside the shop (main.gd enter_interior
	# force-places her via InteriorBuilder "store" keeper spot); outside interior hours she's out front.
	"kazuko": {"name": "和子阿姨", "model": "CH_kazuko", "prep": Vector3(-35.2, 0, -14.4), "prep_yaw": 0.0,
		"market": Vector3(-5.0, 0, 13.8), "market_yaw": 110.0,
		"route_start": Vector3(-3.0, 0, -3.0), "route": [Vector3(-2.6, 0, 6.0), Vector3(-3.4, 0, 11.4), Vector3(-5.0, 0, 13.8)]},
}

## v0.6: what everyone does at the Saturday market once it is open. Stop 0 is NPC[id].market; each further stop is
## [position, yaw_deg, clip, dwell_s] and the loop goes round. Dwell spots keep ~1 m off the player's walkway
## (gate -> courtyard centre -> along z 12.6 past the stall), which the tests check.
const MARKET_ROAM := {
	"mio": [[Vector3(0.2, 0, 10.2), 30.0, "look", 5.0], [Vector3(-1.8, 0, 7.2), 180.0, "idle", 4.0]],
	"ren": [[Vector3(7.0, 0, 9.6), 150.0, "look", 5.0], [Vector3(4.2, 0, 10.2), 90.0, "talk", 4.0]],
	"haru": [[Vector3(8.6, 0, 14.4), 180.0, "bow", 7.0]],
	"tanaka": [[Vector3(12.6, 0, 9.4), 200.0, "look", 6.0]],
	"aoi": [[Vector3(-0.4, 0, 11.4), 180.0, "look", 3.0], [Vector3(-1.6, 0, 4.0), 0.0, "stretch", 4.0],
		[Vector3(6.8, 0, 4.6), 90.0, "cheer", 3.0], [Vector3(8.35, 0, 9.55), 135.0, "look", 2.0]],
	"kazuko": [[Vector3(-1.6, 0, 15.6), 90.0, "look", 6.0]],
}

## Daily routines: [from hour, region (town | farm | home), spot, yaw, standing pose, path to the spot].
## Farm spots are relative to FarmBuilder.ORIGIN. Before the first entry the NPC is at home.
const SCHEDULE := {
	"mio": [
		[6.5, "town", Vector3(-6.4, 0, -6.6), 20.0, "idle"],
		[12.0, "town", Vector3(-12.2, 0, -13.2), 180.0, "idle", [Vector3(-5.6, 0, -7.4), Vector3(-10.6, 0, -9.6)]],
		[13.3, "town", Vector3(-6.4, 0, -6.6), 20.0, "idle", [Vector3(-10.6, 0, -9.6), Vector3(-5.6, 0, -7.4)]],
		[18.2, "town", Vector3(-1.4, 0, 21.4), 180.0, "idle", [Vector3(-3.0, 0, -6.0), Vector3(-3.0, 0, 12.0)]],
		[21.0, "home"],
	],
	"ren": [
		[6.0, "town", Vector3(-22.3, 0, -14.4), 0.0, "idle"],
		[18.3, "town", Vector3(-3.8, 0, 21.2), 140.0, "idle",
			[Vector3(-22.3, 0, -12.0), Vector3(-3.2, 0, -11.0), Vector3(-3.0, 0, -5.8), Vector3(-3.0, 0, 12.5)]],
		[20.6, "home"],
	],
	"haru": [
		[6.0, "town", Vector3(13.6, 0, 16.5), -120.0, "idle"],
		[10.0, "town", Vector3(14.1, 0, 20.1), -90.0, "tend", [Vector3(13.8, 0, 18.4)]],
		[12.0, "town", Vector3(13.6, 0, 16.5), -120.0, "idle", [Vector3(13.8, 0, 18.4)]],
		[16.5, "town", Vector3(11.4, 0, 15.3), 10.0, "idle", [Vector3(12.8, 0, 15.8)]],
		[19.5, "home"],
	],
	"tanaka": [
		[5.5, "farm", Vector3(-10.3, 0, -5.2), 0.0, "idle"],
		[8.0, "farm", Vector3(-2.3, 0, -4.15), 0.0, "tend", [Vector3(-8.0, 0, -1.0), Vector3(-2.3, 0, -1.6)]],
		[10.5, "farm", Vector3(-10.3, 0, -5.2), 0.0, "idle", [Vector3(-2.3, 0, -1.6), Vector3(-8.0, 0, -1.0)]],
		[14.0, "farm", Vector3(2.3, 0, -4.15), 0.0, "tend", [Vector3(-8.0, 0, -1.0), Vector3(0.0, 0, -0.6), Vector3(2.3, 0, -1.6)]],
		[16.0, "farm", Vector3(-10.3, 0, -5.2), 0.0, "idle", [Vector3(2.3, 0, -1.6), Vector3(0.0, 0, -0.6), Vector3(-8.0, 0, -1.0)]],
		[17.3, "farm", Vector3(8.2, 0, 12.1), 0.0, "idle", [Vector3(-8.0, 0, 0.3), Vector3(8.0, 0, 0.8), Vector3(8.2, 0, 11.0)]],
		[19.3, "home"],
	],
	"aoi": [
		[7.5, "town", Vector3(12.2, 0, 18.2), -140.0, "idle"],
		[12.5, "farm", Vector3(4.6, 0, 12.3), 0.0, "idle"],
		[16.5, "town", Vector3(-5.9, 0, 6.3), 200.0, "idle"],
		[19.0, "home"],
	],
	"kazuko": [
		[7.8, "town", Vector3(-35.2, 0, -14.4), 0.0, "idle"],
		[19.2, "home"],
	],
}

## Familiar workplaces stay primary; a few dry-day errands vary by the week.
static func daily_schedule(id: String, weekday: int, weather: String) -> Array:
	var routine: Array = SCHEDULE.get(id, [])
	if weather == "rain": return routine
	if id == "mio" and weekday in [5,6]:
		return [routine[0], [12.0,"town",Vector3(-1.4,0,21.4),180.0,"idle",[Vector3(-3,0,-6),Vector3(-3,0,12)]],
			[13.3,"town",Vector3(-6.4,0,-6.6),20.0,"idle",[Vector3(-3,0,12),Vector3(-3,0,-6)]], routine[3], routine[4]]
	if id == "ren" and weekday == 6:
		return [routine[0], [12.0,"town",Vector3(-3.8,0,21.2),140.0,"idle",[Vector3(-22.3,0,-12),Vector3(-3.2,0,-11),Vector3(-3,0,12.5)]],
			[14.0,"town",Vector3(-22.3,0,-14.4),0.0,"idle",[Vector3(-3,0,12.5),Vector3(-3.2,0,-11),Vector3(-22.3,0,-12)]], routine[1], routine[2]]
	if id == "kazuko" and weekday == 2:
		return [routine[0], [15.0,"town",Vector3(-1.6,0,15.6),90.0,"idle",[Vector3(-35,0,-11),Vector3(-3,0,-11),Vector3(-3,0,12.5)]],
			[15.5,"town",Vector3(-35.2,0,-14.4),0.0,"idle",[Vector3(-3,0,12.5),Vector3(-3,0,-11),Vector3(-35,0,-11)]], routine[1]]
	return routine

## Where each neighbour stands during the Saturday market is NPC[id].market (above).
## Town lawns that get grass and flower tufts: [rect, keep-out list]
const LAWNS := [
	[[-12.9, 10.1, -5.9, 23.9], [[Vector2(-9.8, 13.2), 2.2], [Vector2(-9.8, 20.4), 2.0], [Vector2(-8.1, 16.9), 1.3], [Vector2(-7.7, 20.4), 1.0], [Vector2(-11.4, 22.6), 0.8], [Vector2(-12.2, 12.6), 0.8]]],
	[[10.3, 18.7, 17.1, 23.9], [[13.0, 20.0, 15.9, 22.9], [Vector2(9.0, 22.9), 1.0], [Vector2(15.6, 22.8), 0.8], [Vector2(12.0, 23.2), 0.6]]],
	[[22.3, -5.4, 42.6, 32.1], [[23.0, 1.5, 30.9, 9.5], [21.9, 12.3, 28.3, 19.8], [21.5, 23.5, 27.3, 29.6], [29.5, -6.0, 34.5, -1.8], [Vector2(24.0, 10.8), 0.8], [Vector2(24.2, 20.4), 0.8], [Vector2(40.6, -3.6), 0.9]]],
]
const AREAS := [
	["公交站", -52.2, -15.5, -38.0, 8.0],
	["晴町商店街", -52.2, -25.2, 42.7, -5.5],
	["共享庭院", -13.2, -5.5, 17.2, 24.2],
	["南町住宅街", -4.0, 32.2, 42.7, 85.2],
	["住宅支巷", 17.2, -5.5, 42.7, 32.2],
]


## Ground material under a point, for footstep sounds (later GROUND patches sit on top).
static func surface_at(p: Vector3, in_room: bool) -> String:
	if p.x>600 and not in_room:
		var local:=Vector2(p.x-700.0,p.z)
		return "gravel" if LakesideLayout.path_distance(local)<1.6 else "grass"
	if in_room:
		return HouseBuilder.surface_at(p)
	for i in range(GROUND.size() - 1, -1, -1):
		var g: Array = GROUND[i]
		if p.x >= g[1] and p.x <= g[3] and p.z >= g[2] and p.z <= g[4]:
			return g[0]
	return "stone"
