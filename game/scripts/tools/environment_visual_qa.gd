extends RefCounted
## Complementary environment cameras for the repeatable visual QA matrix.
## All coordinates are local to the region named by the shot, as in shots.gd.
## Diagnostic low/reverse cameras inspect surfaces hidden by the normal follow camera.


static func get_views() -> Dictionary:
	var views: Dictionary = {}
	# Each home room has its normal playable diorama and two opposite eye-level views.
	var rooms: Array = [
		["bedroom", "卧室", Vector3(-3.6, 0, -.4), Vector3(-2.0, 1.65, .5), Vector3(-4.4, .95, -2), Vector3(-6.0, 1.65, -2.7), Vector3(-2.8, .9, .2)],
		["living", "客厅", Vector3(2.2, 0, .1), Vector3(5.7, 1.65, .6), Vector3(.5, .85, -1.6), Vector3(-.8, 1.65, -2.8), Vector3(4.5, .9, -.2)],
		["kitchen", "厨房", Vector3(-3.2, 0, 3.5), Vector3(-.1, 1.65, 4.1), Vector3(-4.5, .9, 2.2), Vector3(-5.6, 1.65, 1.7), Vector3(-1.8, .9, 3.5)],
		["hall", "走廊", Vector3(1.8, 0, 2.8), Vector3(.7, 1.9, 4.2), Vector3(2.4, .85, 1.3), Vector3(3.2, 1.8, 1.35), Vector3(.9, .85, 3.9)],
		["genkan", "玄关", Vector3(5, 0, 3.6), Vector3(3.1, 1.75, 4.0), Vector3(6.0, .65, 2.8), Vector3(5.9, 1.55, 1.7), Vector3(4.5, .5, 4.0)],
		["engawa", "缘侧", Vector3(1.7, 0, -3.85), Vector3(-.8, 1.55, -4.15), Vector3(4.8, .8, -3.75), Vector3(5.9, 1.55, -3.95), Vector3(.1, .7, -3.9)],
		["yard", "小院", Vector3(1.5, -.4, -6.2), Vector3(.1, 1.3, -7.9), Vector3(4.9, .05, -5.7), Vector3(6.1, 1.3, -7.5), Vector3(.2, .15, -5.3)],
	]
	for room: Array in rooms:
		var scene: String = "home_" + str(room[0])
		views["qa_" + scene + "_diorama"] = _home(scene, str(room[1]) + " · 游戏机位", room[2])
		var left: Dictionary = _home(scene, str(room[1]) + " · 西南低机位", room[2])
		left["house_camera"] = room[3]
		left["house_focus"] = room[4]
		left["camera_role"] = "diagnostic"
		views["qa_" + scene + "_left"] = left
		var right: Dictionary = _home(scene, str(room[1]) + " · 对侧低机位", room[2])
		right["house_camera"] = room[5]
		right["house_focus"] = room[6]
		right["camera_role"] = "diagnostic"
		views["qa_" + scene + "_right"] = right

	views["qa_home_front"] = _outside("home_exterior", "自家 · 门前斜侧", Vector3(20, .1, 5.5), Vector3(17.9, 3.65, 0), Vector3(26.8, 2.8, 5.5))
	views["qa_home_back"] = _outside("home_exterior", "自家 · 后院与背面", Vector3(20, .1, 5.5), Vector3(36.8, 3.0, 10.5), Vector3(26.8, 2.0, 5.5))
	views["qa_home_gate_low"] = _outside("home_exterior", "自家 · 门框与门槛", Vector3(20, .1, 5.5), Vector3(21.2, 1.7, 8.2), Vector3(24.2, 1.0, 5.5))

	views["qa_community_diorama"] = _inside("community", "社区中心 · 游戏机位", "workroom", Vector3(0, .05, 2.6))
	views["qa_community_reverse"] = _inside_detail("community", "社区中心 · 北侧回望共用桌", "workroom", Vector3(0, .05, 2.6), Vector3(4.8, 2.05, -3.7), Vector3(-2, .85, 1.5))
	views["qa_community_reading_low"] = _inside_detail("community", "社区中心 · 阅读角侧面", "workroom", Vector3(0, .05, 2.6), Vector3(.7, 1.55, 3.8), Vector3(4.6, .8, 1.7))
	views["qa_community_front"] = _outside("community_exterior", "社区中心 · 门前", Vector3(-23.2, .1, -8.4), Vector3(-28, 3.5, -12), Vector3(-23.2, 2.1, -.1))
	views["qa_community_back"] = _outside("community_exterior", "社区中心 · 背面", Vector3(-30, .1, 10), Vector3(-32, 3.5, 12), Vector3(-23.2, 2, 0))
	views["qa_community_side"] = _outside("community_exterior", "社区中心 · 东侧与门廊", Vector3(-16.5, .1, -4), Vector3(-14.8, 2.2, -3.8), Vector3(-23, 1.7, 0))

	views["qa_plaza_gate"] = _outside("plaza", "广场 · 入口与树冠", Vector3(-1, .1, 2), Vector3(-10, 6, -10), Vector3(4, 4.2, 7))
	views["qa_plaza_reverse"] = _outside("plaza", "广场 · 南侧回望", Vector3(1, .1, 19), Vector3(12, 5, 22), Vector3(-3, 2, 6))
	views["qa_plaza_playground"] = _outside("plaza", "广场 · 棚架与游乐区侧面", Vector3(-5.2, .1, 18.6), Vector3(-3.4, 2.4, 9), Vector3(-9, 1.6, 15))
	views["qa_plaza_roots_low"] = _outside("plaza", "广场 · 树根与透光低机位", Vector3(-1, .1, 2), Vector3(1.3, 1.25, 3.5), Vector3(4, 1, 7))

	views["qa_street_west_east"] = _outside("street_west", "商业街西段 · 朝东", Vector3(-30, .1, -10), Vector3(-42, 3.3, -8.5), Vector3(-15, 2.5, -17))
	views["qa_street_west_reverse"] = _outside("street_west", "商业街西段 · 朝西", Vector3(-30, .1, -10), Vector3(-14, 2.0, -12.5), Vector3(-43, 1.5, -10.3))
	views["qa_street_west_bus"] = _outside("street_west", "商业街西段 · 车站低机位", Vector3(-41, .1, -9.5), Vector3(-39, 1.8, -5.9), Vector3(-45, 1.3, -11.3))
	views["qa_street_east_main"] = _outside("street_east", "商业街东段 · 朝东", Vector3(28, .1, -11), Vector3(10, 2.6, -9), Vector3(39, 2, -17))
	views["qa_street_east_reverse"] = _outside("street_east", "商业街东段 · 朝西", Vector3(34, .1, -11), Vector3(42, 2, -12), Vector3(9, 1.7, -13))
	views["qa_street_east_lane"] = _outside("street_east", "商业街东段 · 巷口与路牌", Vector3(20.2, .1, -5.8), Vector3(16.2, 1.8, -9.8), Vector3(22.6, 1.4, 3))
	views["qa_lane_forward"] = _outside("street_lane", "住宅支巷 · 向南", Vector3(19.7, .1, 10.6), Vector3(19.1, 2.3, -.8), Vector3(20, 1.7, 24))
	views["qa_lane_reverse"] = _outside("street_lane", "住宅支巷 · 向北", Vector3(19.7, .1, 21), Vector3(19.1, 2.6, 23.8), Vector3(19.7, 1.6, 7))
	views["qa_lane_garden_low"] = _outside("street_lane", "住宅支巷 · 花园门与墙帽", Vector3(19.7, .1, 12.4), Vector3(18.8, 1.7, 16.2), Vector3(23.4, .85, 12.3))
	views["qa_street_south_forward"] = _outside("street_south", "住宅街 · 朝南", Vector3(19.7, .1, 56), Vector3(19.7, 3.4, 34), Vector3(20, 2.8, 65))
	views["qa_street_south_reverse"] = _outside("street_south", "住宅街 · 朝北", Vector3(19.7, .1, 60), Vector3(19.7, 2.2, 68), Vector3(20, 2.5, 39))
	views["qa_street_south_crossing"] = _outside("street_south", "住宅街 · 横巷低机位", Vector3(19.7, .1, 51), Vector3(34, 1.7, 51.2), Vector3(8, 1.5, 50.8))

	views["qa_store_diorama"] = _inside("store", "商店 · 游戏机位", "store", Vector3(0, .05, 2.6))
	views["qa_store_reverse"] = _inside_detail("store", "商店 · 后侧货架与柜台", "store", Vector3(0, .05, 2.6), Vector3(4.2, 1.7, -2.2), Vector3(-3.2, .9, .6))
	views["qa_store_aisle_low"] = _inside_detail("store", "商店 · 过道低机位与冷藏", "store", Vector3(0, .05, 2.6), Vector3(-2.8, 1.6, 2.9), Vector3(3.1, .85, -1.9))
	views["qa_store_front"] = _outside("store_exterior", "商店 · 门前", Vector3(-36, .1, -10), Vector3(-41, 3.2, -10.5), Vector3(-36, 2, -19.3))
	views["qa_store_back"] = _outside("store_exterior", "商店 · 背面", Vector3(-36, .1, -24), Vector3(-40, 2.4, -26), Vector3(-36, 2, -20))
	views["qa_store_side_low"] = _outside("store_exterior", "商店 · 橱窗与摊架侧面", Vector3(-36, .1, -13), Vector3(-31.3, 1.7, -14), Vector3(-35.1, 1.15, -16.7))

	views["qa_bakery_diorama"] = _inside("bakery", "面包房 · 游戏机位", "bakery", Vector3(1.5, .05, 2.9))
	views["qa_bakery_reverse"] = _inside_detail("bakery", "面包房 · 后吧回望陈列与座位", "bakery", Vector3(1.5, .05, 2.9), Vector3(4.1, 1.7, -2.3), Vector3(-2, .85, 1.65))
	views["qa_bakery_cafe_low"] = _inside_detail("bakery", "面包房 · 座位与甜品侧面", "bakery", Vector3(1.5, .05, 2.9), Vector3(-3.9, 1.6, 3.6), Vector3(1.2, .85, .1))
	views["qa_bakery_front"] = _outside("bakery_exterior", "面包房 · 门前", Vector3(-24, .1, -10), Vector3(-29, 3.2, -11), Vector3(-24, 2, -19.3))
	views["qa_bakery_back"] = _outside("bakery_exterior", "面包房 · 背面", Vector3(-24, .1, -25), Vector3(-28, 2.4, -27), Vector3(-24, 2, -21))
	views["qa_bakery_side_low"] = _outside("bakery_exterior", "面包房 · 布篷与推车侧面", Vector3(-24, .1, -13), Vector3(-19.1, 1.65, -13.8), Vector3(-23.4, 1.15, -16.7))

	for shop: Array in [["florist", "花店", -12.0, -19.7], ["zakka", "杂货店", 0.0, -19.8], ["post", "邮局", 12.5, -20.3]]:
		var shop_id: String = str(shop[0])
		var shop_x: float = float(shop[2])
		var shop_z: float = float(shop[3])
		views["qa_" + shop_id + "_front"] = _outside(shop_id, str(shop[1]) + " · 正面斜侧", Vector3(shop_x, .1, -13), Vector3(shop_x - 3.8, 2.1, -13.1), Vector3(shop_x, 1.6, shop_z))
		views["qa_" + shop_id + "_back"] = _outside(shop_id, str(shop[1]) + " · 背面斜侧", Vector3(shop_x, .1, -24), Vector3(shop_x + 4.0, 2.5, -26.2), Vector3(shop_x, 1.6, shop_z))
	# The post office extends farther back than the neighbouring two shop models.
	views["qa_post_back"]["camera_at"] = Vector3(19.5, 8, -24.8)
	views["qa_post_back"]["camera_focus"] = Vector3(12.5, 2.5, -20.3)
	views["qa_post_back"]["label"] = "邮局 · 背侧屋顶结构"

	views["qa_river_nearbank"] = _farm("river", "河边 · 北岸向桥", Vector3(3, .1, 11.6), Vector3(9, 2.1, 10.4), Vector3(0, .6, 18))
	views["qa_river_farbank"] = _farm("river", "河边 · 对岸向农场", Vector3(0, .1, 24), Vector3(-8, 2.3, 25), Vector3(3, .6, 15))
	views["qa_river_bridge_low"] = _farm("river", "河边 · 桥面与栏杆低机位", Vector3(0, .8, 16), Vector3(-3.7, 1.7, 20.5), Vector3(0, .6, 16.2))
	views["qa_river_bend_near"] = _farm("river_bend", "河湾 · 近岸", Vector3(48, .2, 19.4), Vector3(38, 3.5, 12), Vector3(58, 0, 26))
	views["qa_river_bend_reverse"] = _farm("river_bend", "河湾 · 对岸回望", Vector3(48, .2, 32), Vector3(58, 2.2, 36), Vector3(43, .1, 22))
	views["qa_river_bend_bank_low"] = _farm("river_bend", "河湾 · 浅滩与溪石", Vector3(48, .2, 19.4), Vector3(48.4, 1.3, 19.7), Vector3(51, -.1, 25))
	views["qa_farm_entry"] = _farm("farm", "农场 · 入口与全景", Vector3(-19, .1, .4), Vector3(-24, 4.5, 5), Vector3(0, .8, -4))
	views["qa_farm_field"] = _farm("farm", "农场 · 菜地近景", Vector3(0, .1, -.4), Vector3(7.4, 2.8, -.4), Vector3(-1, .45, -5.2))
	views["qa_farm_field_reverse"] = _farm("farm", "农场 · 菜地背面", Vector3(0, .1, -10.5), Vector3(-7.5, 2.0, -12), Vector3(2.4, .5, -4))
	views["qa_farm_greenhouse"] = _farm("farm", "农场 · 温室侧面", Vector3(14, .1, -2.6), Vector3(18, 2.0, -4), Vector3(11.8, 1.3, -8))
	views["qa_farm_shed"] = _farm("farm", "农场 · 工具房与杂物", Vector3(-10.6, .1, -4), Vector3(-15.8, 1.8, -3.2), Vector3(-10.6, 1, -8.2))
	views["qa_lake_pier"] = _farm("lake", "湖边 · 栈桥", Vector3(94, .2, 44.5), Vector3(87, 3.8, 49), Vector3(99, 0, 21))
	views["qa_lake_reverse"] = _farm("lake", "湖边 · 对侧向湖湾", Vector3(115, .2, 48), Vector3(126, 4.5, 52), Vector3(100, 0, 17))
	views["qa_lake_reeds_low"] = _farm("lake", "湖边 · 芦苇东岸", Vector3(137, .1, 15), Vector3(139, 1.6, 15), Vector3(133, .5, 17))
	views["qa_background_n"] = _outside("background_n", "镇外北侧 · 草坡与林缘", Vector3(-6,.1,-13), Vector3(-6,6,-23), Vector3(-6,3,-72))
	views["qa_background_ne"] = _outside("background_ne", "镇外东北 · 草坡与林缘", Vector3(36,.1,-11), Vector3(38,6,-22), Vector3(86,3,-70))
	views["qa_background_e"] = _outside("background_e", "镇外东侧 · 草坡与林缘", Vector3(19.7,.1,15), Vector3(41,6,15), Vector3(95,3,15))
	views["qa_background_se"] = _outside("background_se", "镇外东南 · 草坡与林缘", Vector3(19.7,.1,77), Vector3(38,6,80), Vector3(90,3,130))
	views["qa_background_s"] = _outside("background_s", "镇外南侧 · 草坡与林缘", Vector3(19.7,.1,77), Vector3(20,6,84), Vector3(20,3,145))
	views["qa_background_sw"] = _outside("background_sw", "广场高机位向西南 · 夏祭反向背景", Vector3(-2.6,.1,18.8), Vector3(1.62618,4,9.73692), Vector3(-2.6,1,18.8))
	views["qa_background_w"] = _outside("background_w", "镇外西侧 · 草坡与林缘", Vector3(-43,.1,-9), Vector3(-50,6,-1), Vector3(-110,3,35))
	views["qa_background_nw"] = _outside("background_nw", "镇外西北 · 草坡与林缘", Vector3(-43,.1,-9), Vector3(-50,6,-23), Vector3(-108,3,-75))
	return views


static func get_activity_views() -> Dictionary:
	var views: Dictionary = {
		"qa_activity_market_front": _outside("activity_market", "集市 · 入口", Vector3(-3, .1, 11), Vector3(-8, 3, 3), Vector3(2, 1, 15)),
		"qa_activity_market_back": _outside("activity_market", "集市 · 摊位背面", Vector3(3.4, .1, 12.6), Vector3(9, 2.0, 20), Vector3(0, 1, 12)),
		"qa_activity_tanabata_front": _outside("activity_tanabata", "七夕 · 广场入口", Vector3(-1, .1, 1.6), Vector3(-8, 3.2, -3), Vector3(4, 2, 8)),
		"qa_activity_tanabata_back": _outside("activity_tanabata", "七夕 · 树后回望", Vector3(1, .1, 15), Vector3(12, 2.2, 18), Vector3(0, 1.8, 6)),
		"qa_activity_natsu_front": _outside("activity_natsu", "夏祭 · 摊位与树下", Vector3(-2, .1, 11), Vector3(-8, 3.0, 5), Vector3(3, 1.5, 15)),
		"qa_activity_natsu_back": _outside("activity_natsu", "夏祭 · 舞台侧面", Vector3(0, .1, 18), Vector3(8.5, 3.6, 15.4), Vector3(-2.6, 1.5, 18.8)),
		"qa_activity_fireworks_front": _farm("activity_fireworks", "花火 · 河岸正面", Vector3(4, .1, 11.2), Vector3(10, 2.4, 8), Vector3(0, 4, 24)),
		"qa_activity_fireworks_back": _farm("activity_fireworks", "花火 · 河岸背面", Vector3(4, .1, 11.2), Vector3(-7, 2.2, 11), Vector3(7, 3.4, 24)),
		"qa_activity_obon_bridge": _farm("activity_obon", "盂兰盆 · 桥与河灯", Vector3(2, .1, 11.8), Vector3(-6, 2.4, 10), Vector3(3, .4, 19)),
		"qa_activity_obon_farbank": _farm("activity_obon", "盂兰盆 · 对岸河灯", Vector3(0, .1, 24), Vector3(7, 1.8, 25), Vector3(-3, .2, 17)),
		"qa_activity_reading_side": _inside_detail("activity_reading", "阅读 · 椅子与身体侧面", "workroom", Vector3(3.5, .05, 1.35), Vector3(1.5, 1.9, 4.3), Vector3(4.35, .85, 2.1)),
		"qa_activity_reading_back": _inside_detail("activity_reading", "阅读 · 座椅后侧", "workroom", Vector3(3.5, .05, 1.35), Vector3(5.2, 1.55, -.2), Vector3(4.35, .85, 1.35)),
		"qa_activity_cafe_sip_side": _inside_detail("activity_cafe", "咖啡 · 持杯与桌沿", "bakery", Vector3(.2, .05, 3.4), Vector3(-1.8, 1.55, 3.9), Vector3(.2, .95, 2.55)),
		"qa_activity_cafe_sip_reverse": _inside_detail("activity_cafe", "咖啡 · 持杯背侧", "bakery", Vector3(.2, .05, 3.4), Vector3(.8, 1.65, .8), Vector3(.2, .95, 2.55)),
	}
	for id: String in views:
		var view: Dictionary = views[id]
		view["group"] = "activities"
		view["actors"] = true
		view["show_actor"] = true
		view["settle_seconds"] = 2.0
		if id.contains("market"):
			view["phase"] = "market"
			view["day"] = 10
			view["time"] = 18.0
		elif id.contains("tanabata"):
			view["day"] = 4
			view["time"] = 19.8
		elif id.contains("natsu"):
			view["day"] = 17
			view["time"] = 20.3
		elif id.contains("fireworks"):
			view["day"] = 24
			view["time"] = 19.8
			view["fireworks"] = true
		elif id.contains("obon"):
			view["day"] = 43
			view["time"] = 19.5
			view["lanterns"] = true
		elif id.contains("reading"):
			view["seat_id"] = "public_reading_0"
			view["time"] = 10.5
		elif id.contains("cafe"):
			view["seat_id"] = "public_cafe_1"
			view["sip"] = "coffee"
			view["time"] = 10.5
	return views


static func _home(scene: String, label: String, at: Vector3) -> Dictionary:
	return {"scene":scene, "group":"environments", "label":label, "camera_role":"playable", "house":at, "pitch":50.0, "dist":9.2, "face":180.0, "show_actor":true, "demo":true}


static func _inside(scene: String, label: String, interior: String, at: Vector3) -> Dictionary:
	return {"scene":scene, "group":"environments", "label":label, "camera_role":"playable", "interior":interior, "at":at, "pitch":48.0, "dist":9.2, "face":180.0, "show_actor":true}


static func _inside_detail(scene: String, label: String, interior: String, at: Vector3, camera: Vector3, focus: Vector3) -> Dictionary:
	var view: Dictionary = _inside(scene, label, interior, at)
	view["inside_camera"] = camera
	view["inside_focus"] = focus
	view["camera_role"] = "diagnostic"
	return view


static func _outside(scene: String, label: String, player: Vector3, camera: Vector3, focus: Vector3) -> Dictionary:
	return {"scene":scene, "group":"environments", "label":label, "camera_role":"diagnostic", "player":player, "camera_at":camera, "camera_focus":focus, "actors":true}


static func _farm(scene: String, label: String, player: Vector3, camera: Vector3, focus: Vector3) -> Dictionary:
	var view: Dictionary = _outside(scene, label, player, camera, focus)
	view["farm"] = true
	view["demo"] = true
	return view
