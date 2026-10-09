extends Node
## Global game state: quests, inventory, placements, crop, phase, settings and save/load.
## All mutations go through this node so rules (atomic delivery, one-time rewards,
## key-item protection, decor limits) live in one place.

signal state_changed
signal toast(text: String)
signal quest_changed(qid: String)
signal inventory_changed
signal placements_changed
signal crop_changed(stage: int)
signal phase_changed(phase: String)
signal time_changed(minute: int)
signal day_changed(day: int)
signal save_finished(success: bool,automatic: bool)
signal plots_changed
signal late_night
signal coins_changed(delta: int)
signal level_up(level: int, perks: Array)
signal xp_gained(n: int)

const SAVE_VERSION := 4
var SAVE_PATH := "user://harumachi.db"
const SAVE_TMP := "user://save.tmp"
var SAVE_BAK := "user://harumachi.backup.db"
const SETTINGS_PATH := "user://settings.json"
const INV_SLOTS := 20              # starting backpack (upgrades to 30 / 40)
const STACK_MAX := 99
const STORAGE_SLOTS := 60
const MAX_DECOR_KINDS := 2
const START_COINS := 100
const MG_COINS_PER_STAR := 5
const MAX_AFF := 5
const WARMTH_PER_HEART := 4

# ---- time (see docs/game-design/FARMING.md)
const MIN_PER_SEC := 1.5            # game minutes per real second -> a 06:00-24:00 day is ~12 min
const WAKE_MIN := 6 * 60 + 30
const START_MIN := 9 * 60           # moving day starts at 09:00
const DAY_END := 24 * 60
const WEEKDAYS := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
const FIRST_WEEKDAY := 3            # day 1 is a Thursday, so the first Saturday is day 3
const SATURDAY := 5
const MARKET_OPEN := 16 * 60 + 30
const MARKET_CLOSE := 21 * 60
const NAP_UNTIL := 16 * 60 + 30
const WEATHERS := {"sunny": "晴", "cloudy": "多云", "rain": "小雨"}

# ---- farming
const CAN_CAP := 5                 # the old can; copper 10, gold 20
const COMPOST_PER_BAG := 3
const FARM_EXPAND_COST := [200, 600]
const FARM_EXPAND_LV := [2, 4]
const STAND_RATE := 1.0
const MARKET_RATE := 1.3
const FESTIVAL_STALL_RATE := 2.0
const GLUT_N := 12                  # a buyer pays full price for the first 12 of an item per day
const GLUT_RATE := 0.7
## Farming experience (see docs/game-design/BALANCE.md; art/tools/balance_sim.py uses the same table)
const LEVELS := [0, 30, 90, 190, 340, 550, 830, 1190, 1640, 2200]
const XP_TILL := 2
const XP_SOW := 1
const XP_WATER := 1
const LEVEL_PERKS := {
	2: ["番茄、黄瓜、土豆种子", "金平胡萝卜、萝卜炖菜配方", "可向田中爷爷扩租 4 块地"],
	3: ["毛豆、洋葱、小麦种子", "土豆可乐饼配方", "商店的铜洒水壶（10 次）", "小院扩建"],
	4: ["茄子、玉米种子", "味噌烤茄子、玉米浓汤配方", "可再扩租 4 块地"],
	5: ["草莓苗（种子铺）", "蔬菜天妇罗、夏日咖喱配方", "旅行背包（40 格）"],
	6: ["南瓜种子", "南瓜煮物配方", "温室扩建"],
	7: ["西瓜种子", "西瓜切块配方", "金洒水壶（20 次）"],
	8: ["收获时有 25% 的机会多收 1 个"],
	9: ["堆肥让作物当晚多长 2 天"],
	10: ["称号「晴町农人」", "作物卖价 +10%"],
}
## Mini-games: id -> display name and where they are played.
const MINIGAMES := {
	"onigiri": {"name": "捏饭团", "place": "家 · 厨房"},
	"puzzle": {"name": "晴町地图拼图", "place": "家 · 卧室书桌"},
	"goldfish": {"name": "捞金鱼", "place": "庭院 · 金鱼池"},
	"taiko": {"name": "祭典太鼓", "place": "庭院 · 小舞台"},
}

var items_db: Dictionary = {}
var quests_db: Dictionary = {}
var crops_db: Dictionary = {}
var recipes_db: Dictionary = {}
var shops_db: Dictionary = {}
var festivals_db: Dictionary = {}
var fish_db: Dictionary = {}
var fishing: Dictionary = {"casts":0,"landed":0,"caught":{},"best_cm":{}}
var _fishing_ticket: Dictionary = {}
var _fishing_serial := 0
var quest_order: Array = []

var coins := START_COINS
var inventory: Dictionary = {}   # normal item -> count
var key_items: Dictionary = {}   # key item -> count
var quests: Dictionary = {}      # qid -> {"state": String, "step": int}
var flags: Dictionary = {}
var affinity: Dictionary = {"mio": 0, "ren": 0, "haru": 0, "tanaka": 0, "aoi": 0}
var warmth: Dictionary = {}      # who -> points toward the next heart
var placements: Array = []       # [{uid, item, x, z, rot}]
var next_uid := 1
var crop_stage := 0              # 0 empty, 1 seeded, 2 sprout, 3 grown  (the Q03 story planter)
var phase := "prep"              # prep | market
var day := 1
var minute := float(START_MIN)
var weather := "sunny"
var clock_paused := false        # tests and cut-scenes freeze the clock
var time_scale := 1.0
var plots: Dictionary = {}       # plot id -> {open, tilled, crop, days, water, fert, boost}
var can_water := 0
var compost := 0                 # materials waiting in the bin
var compost_ready := 0           # fertilizer bags ready to take out
var farm_expansions := 0
var daily: Dictionary = {}       # reset every morning: talked, gifted, request, sold
var player_region := "town"      # town | farm (the house is tracked by player_in_room)
var farm_xp := 0
var bag_cap := INV_SLOTS
var can_level := 0               # 0 old can (5), 1 copper (10), 2 gold (20)
var storage: Dictionary = {}     # the chest at home: item -> count
var recipes_known: Dictionary = {}  # recipes learned from cards
var ledger: Dictionary = {"in": 0, "out": 0}   # today's money, shown when going to bed
var player_pos := Vector3.ZERO
var player_yaw := 0.0
var player_in_room := false
var has_player_pos := false
var tracked_quest := ""
var play_time := 0.0
var load_on_enter := false
var minigames: Dictionary = {}   # id -> {"best": int, "stars": int, "plays": int}
# v0.6: achievements (id -> day unlocked), 晴町旧物 found (id -> day), picture book (crops grown, dishes made)
var achievements: Dictionary = {}
var collection: Dictionary = {}
var zukan: Dictionary = {"crops": {}, "dishes": {}}

var settings: Dictionary = {"text_scale": 1.0, "mouse_sens": 1.0, "fullscreen": false, "invert_y": false,
		"vol_master": 1.0, "vol_music": 0.75, "vol_sfx": 0.8, "vol_voice": 0.9}
var _ui_locks := {}
var last_error := ""
var calendar_pending_save := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-db="):
			var test_path: String = arg.trim_prefix("--test-db=")
			SaveDB.set_directory(test_path.get_base_dir())
			SaveDB.database_path = test_path
			SaveDB.backup_path = test_path.get_basename() + ".backup.db"
	SAVE_PATH = SaveDB.database_path
	SAVE_BAK = SaveDB.backup_path
	items_db = _read_json("res://data/items.json")
	quests_db = _read_json("res://data/quests.json")
	crops_db = _read_json("res://data/crops.json")
	recipes_db = _read_json("res://data/recipes.json")
	shops_db = _read_json("res://data/shops.json")
	festivals_db = _read_json("res://data/festivals.json")
	fish_db = _read_json("res://data/fish.json")
	quest_order = quests_db.keys()
	quest_order.sort_custom(func(a, b): return int(quests_db[a].get("order", 0)) < int(quests_db[b].get("order", 0)))
	_setup_input()
	load_settings()
	new_game()


var _last_min := -1

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	play_time += delta
	if not time_running():
		return
	minute = minf(minute + delta * MIN_PER_SEC * time_scale, float(DAY_END))
	_tick_minute()


func _tick_minute() -> void:
	var m := int(minute)
	if m == _last_min:
		return
	var prev := _last_min
	_last_min = m
	time_changed.emit(m)
	if qstate("Q05") == "done" and weekday() == SATURDAY:
		if phase == "prep" and prev < MARKET_OPEN and m >= MARKET_OPEN and m < MARKET_CLOSE:
			set_phase("market")
		elif phase == "market" and m >= MARKET_CLOSE:
			set_phase("prep")
	if m >= DAY_END and not daily.get("late_sent", false):
		daily["late_sent"] = true
		late_night.emit()


# ---------------------------------------------------------------- input map
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "interact": [KEY_E, KEY_SPACE], "inventory": [KEY_TAB, KEY_I],
		"quests": [KEY_J], "pause": [KEY_ESCAPE], "rotate_ccw": [KEY_Q], "rotate_cw": [KEY_E],
		"undo": [KEY_Z], "pickup": [KEY_F], "cam_left": [KEY_COMMA], "cam_right": [KEY_PERIOD],
		"build": [KEY_B], "calendar": [KEY_C], "book": [KEY_K],
		"world_map": [KEY_M],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {"click": MOUSE_BUTTON_LEFT, "cancel": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)


# ---------------------------------------------------------------- UI locks
func lock_input(owner_id: String) -> void:
	_ui_locks[owner_id] = true

func unlock_input(owner_id: String) -> void:
	_ui_locks.erase(owner_id)

func input_locked() -> bool:
	return not _ui_locks.is_empty()

func clear_locks() -> void:
	_ui_locks.clear()


# ---------------------------------------------------------------- new game
func new_game() -> void:
	calendar_pending_save = -1
	PlacementSystem.project_context = ""
	coins = START_COINS
	inventory = {}
	key_items = {}
	quests = {}
	for q in quests_db:
		quests[q] = {"state": "locked", "step": 0}
	quests["Q00"] = {"state": "active", "step": 0}
	tracked_quest = "Q00"
	flags = {"arrival_home": {"version": 1, "phase": "bus", "origin_day": 1}, "world_seed": randi(), "neighbour_identity": {"version": 1, "presented": {}}}
	affinity = {"mio": 0, "ren": 0, "haru": 0, "tanaka": 0, "aoi": 0}
	warmth = {}
	placements = []
	next_uid = 1
	crop_stage = 0
	phase = "prep"
	day = 1
	minute = float(START_MIN)
	_last_min = -1
	weather = weather_for(1)
	plots = _fresh_plots()
	can_water = 0
	compost = 0
	compost_ready = 0
	farm_expansions = 0
	daily = {}
	player_region = "town"
	farm_xp = 0
	bag_cap = INV_SLOTS
	can_level = 0
	storage = {}
	recipes_known = {}
	ledger = {"in": 0, "out": 0}
	player_pos = Vector3.ZERO
	player_yaw = 0.0
	player_in_room = false
	has_player_pos = false
	play_time = 0.0
	minigames = {}
	achievements = {}
	collection = {}
	zukan = {"crops": {}, "dishes": {}}
	fishing = {"casts":0,"landed":0,"caught":{},"best_cm":{}}
	_fishing_ticket.clear()
	DailyLife.initialize(true)
	SummerProjects.initialize(true)
	SummerGathering.state()
	FoodPurpose.register_meal()
	NeighbourMeals.register()
	MainlineProgress.initialize()
	StoryKnowledge.initialize()
	clear_locks()
	state_changed.emit()


# ---------------------------------------------------------------- mini-games
func mg_record(id: String) -> Dictionary:
	return minigames.get(id, {"best": 0, "stars": 0, "plays": 0})


## Called by a finished round. New stars pay coins once; the first cleared round (1+ star) of each
## game also changes the world a little (tidy living room, framed map, goldfish at home...).
func record_minigame(id: String, score: int, stars: int, outcome: Dictionary = {}) -> Dictionary:
	var rec: Dictionary = mg_record(id).duplicate()
	var old_stars := int(rec.stars)
	var new_best := score > int(rec.best)
	rec.plays = int(rec.plays) + 1
	rec.best = maxi(int(rec.best), score)
	rec.stars = maxi(old_stars, stars)
	minigames[id] = rec
	if not outcome.is_empty():
		rec["outcome"] = outcome.duplicate(true)
		rec["last_day"] = day
	StoryKnowledge.observe_activity(id)
	var lines: Array = []
	var gained := maxi(stars - old_stars, 0)
	var pay := gained * MG_COINS_PER_STAR
	if pay > 0:
		earn(pay, "小游戏")
		lines.append("新拿到 %d 颗星：+%d 生活币" % [gained, pay])
	if stars >= 1:
		match id:
			"onigiri":
				if add_item("onigiri", stars, true):
					lines.append("饭团 ×%d 放进了背包，和邻居说话时可以送一个" % stars)
			"unpack":
				if not flags.get("house_tidy", false):
					flags["house_tidy"] = true
					lines.append("客厅的纸箱都收拾好了，屋子一下子像个家了")
			"taiko":
				if not flags.get("taiko_cleared", false):
					flags["taiko_cleared"] = true
					lines.append("这次练习的节奏记下来了")
	elif stars == 0:
		lines.append("这一局记下了。想再试，随时可以")
	if id == "puzzle" and outcome.get("solved", false) and not flags.get("map_framed", false):
		flags["map_framed"] = true
		lines.append("拼好的地图装进相框，挂在了卧室墙上")
	if id == "goldfish" and int(outcome.get("caught", 0)) > 0 and not flags.get("goldfish_home", false):
		flags["goldfish_home"] = true
		lines.append("带回一尾小金鱼，养在缘侧的金鱼缸里")
	state_changed.emit()
	return {"coins": pay, "lines": lines, "new_best": new_best, "best": int(rec.best)}


func mg_total_stars() -> int:
	var n := 0
	for id in MINIGAMES:
		n += int(minigames.get(id,{}).get("stars", 0))
	return n


# ---------------------------------------------------------------- items
func item(id: String) -> Dictionary:
	return items_db.get(id, {})

func item_name(id: String) -> String:
	return item(id).get("name", id)

func is_key_item(id: String) -> bool:
	return bool(item(id).get("key", false))

func count(id: String) -> int:
	return int(key_items.get(id, 0)) if is_key_item(id) else int(inventory.get(id, 0))

func has(id: String, n: int = 1) -> bool:
	return count(id) >= n

static func _slots_for(n: int) -> int:
	return int(ceil(float(n) / STACK_MAX)) if n > 0 else 0

func slots_used() -> int:
	var n := 0
	for id in inventory:
		n += _slots_for(int(inventory[id]))
	return n

func can_add(id: String, n: int = 1) -> bool:
	if is_key_item(id):
		return true
	var have := int(inventory.get(id, 0))
	return slots_used() - _slots_for(have) + _slots_for(have + n) <= bag_cap

func add_item(id: String, n: int = 1, quiet: bool = false) -> bool:
	if not items_db.has(id) or n <= 0:
		return false
	if is_key_item(id):
		key_items[id] = int(key_items.get(id, 0)) + n
	else:
		if not can_add(id, n):
			toast.emit("背包满了（%d 格），先放一些到家里的收纳箱吧" % bag_cap)
			return false
		inventory[id] = int(inventory.get(id, 0)) + n
	if not quiet:
		toast.emit("获得 %s ×%d" % [item_name(id), n])
		Audio.sting("item")
	inventory_changed.emit()
	state_changed.emit()
	return true

func remove_item(id: String, n: int = 1) -> bool:
	if count(id) < n or n <= 0:
		return false
	var d: Dictionary = key_items if is_key_item(id) else inventory
	d[id] = int(d[id]) - n
	if d[id] <= 0:
		d.erase(id)
	inventory_changed.emit()
	state_changed.emit()
	return true

## Removes every requirement or nothing at all.
func take_all(req: Dictionary) -> bool:
	for id in req:
		if count(id) < int(req[id]):
			return false
	for id in req:
		remove_item(id, int(req[id]))
	return true


# ---------------------------------------------------------------- shop / decor
func decor_kinds() -> Array:
	var kinds := {}
	for id in inventory:
		if item(id).get("placeable", "") == "decor":
			kinds[id] = true
	for p in placements:
		if item(p.item).get("placeable", "") == "decor":
			kinds[p.item] = true
	if flags.get("bought_kinds"):
		for k in flags["bought_kinds"]:
			kinds[k] = true
	return kinds.keys()

## Returns "" on success or a reason string.
func buy(id: String) -> String:
	var it := item(id)
	var price := int(it.get("price", 0))
	var is_decor: bool = it.get("placeable", "") == "decor"
	if phase != "prep" and it.has("placeable"):
		return "集市已经开始了"
	var kinds := decor_kinds()
	if it.get("placeable", "") == "decor" and not kinds.has(id) and kinds.size() >= MAX_DECOR_KINDS:
		return "装饰最多选两种，已经选了：%s" % "、".join(kinds.map(func(k): return item_name(k)))
	if coins < price:
		return "生活币不够（需要 %d，现有 %d）" % [price, coins]
	if not can_add(id):
		return "背包满了"
	spend(price, "买东西")
	if is_decor:
		var bk: Array = flags.get("bought_kinds", [])
		if not bk.has(id):
			bk.append(id)
		flags["bought_kinds"] = bk
	add_item(id, 1, true)
	toast.emit("买下 %s（-%d 生活币）" % [item_name(id), price])
	Audio.sting("coin")
	return ""


# ---------------------------------------------------------------- quests
func qstate(qid: String) -> String:
	return quests.get(qid, {}).get("state", "locked")

func qstep(qid: String) -> int:
	return int(quests.get(qid, {}).get("step", 0))

func qstep_id(qid: String) -> String:
	var steps: Array = quests_db.get(qid, {}).get("steps", [])
	var s := qstep(qid)
	return steps[s].id if s < steps.size() else ""

func at_step(qid: String, step_id: String) -> bool:
	return qstate(qid) == "active" and qstep_id(qid) == step_id

func quest_title(qid: String) -> String:
	return quests_db.get(qid, {}).get("title", qid)

func start_quest(qid: String) -> bool:
	if qstate(qid) != "available":
		return false
	DailyLife.clear_tracking()
	SummerProjects.clear_tracking()
	flags.erase("request_tracked")
	quests[qid] = {"state": "active", "step": 0}
	if qid == "Q16":
		recipes_known["veg_sandwich"] = true
	tracked_quest = qid
	toast.emit("接受委托：「%s」" % quest_title(qid))
	Audio.sting("quest_accept")
	quest_changed.emit(qid)
	state_changed.emit()
	return true

## Move a quest from `step_id` to its next step (guarded, so repeats do nothing).
func advance(qid: String, step_id: String) -> bool:
	if not at_step(qid, step_id):
		return false
	var steps: Array = quests_db[qid].steps
	var s := qstep(qid) + 1
	if s >= steps.size():
		return complete_quest(qid)
	quests[qid].step = s
	tracked_quest = qid
	Audio.sting("step")
	quest_changed.emit(qid)
	state_changed.emit()
	return true

func complete_quest(qid: String, player_completed: bool = true, save_now: bool = true) -> bool:
	if qstate(qid) == "done":
		return false
	quests[qid] = {"state": "done", "step": quests_db[qid].steps.size()}
	var r: Dictionary = quests_db[qid].get("rewards", {})
	if player_completed and int(r.get("coins", 0)) > 0:
		earn(int(r.get("coins", 0)), "委托")
	if player_completed:
		for id in r.get("items", {}):
			add_item(id, int(r.items[id]), true)
		for id in r.get("key_items", {}):
			add_item(id, int(r.key_items[id]), true)
		for who in r.get("affinity", {}):
			add_affinity(who, int(r.affinity[who]))
		toast.emit("完成委托：「%s」" % quest_title(qid))
		Audio.sting("quest_done")
	else:
		toast.emit("街坊已完成准备：「%s」" % quest_title(qid))
	for u in quests_db[qid].get("unlocks", []):
		if qstate(u) == "locked":
			quests[u] = {"state": "available", "step": 0}
	if not SummerProjects.uses_cooperation_mainline() and qid in ["Q02", "Q03", "Q04"] and qstate("Q05") == "locked" \
			and qstate("Q02") == "done" and qstate("Q03") == "done" and qstate("Q04") == "done":
		quests["Q05"] = {"state": "available", "step": 0}
		toast.emit("三枚邻里支持标记集齐了！去找澪吧")
	if crop_stage == 2 and qid != "Q03":
		set_crop(3)
	_retrack()
	MainlineProgress.initialize()
	quest_changed.emit(qid)
	state_changed.emit()
	if save_now:
		save_game()
	return true

func _retrack() -> void:
	if qstate(tracked_quest) == "active":
		return
	tracked_quest = ""
	for q in quest_order:
		if qstate(q) == "active":
			tracked_quest = q
			return

func active_quests() -> Array:
	return quest_order.filter(func(q): return qstate(q) == "active")

func objective_text() -> String:
	var q := tracked_quest
	if qstate(q) != "active":
		_retrack()
		q = tracked_quest
	if q == "":
		for a in quest_order:
			if qstate(a) == "available":
				return "有新的委托可以接受（按 J 查看）"
		return "随意走走，和邻居聊聊天吧" if phase == "market" else "四处逛逛"
	return quest_step_text(q)


func quest_step_text(qid: String) -> String:
	var step := qstep_id(qid)
	if qid == "Q05" and SummerProjects.uses_cooperation_mainline():
		if step == "talk_plan": return "把已经试过的菜单与取餐方案告诉澪"
		if step == "chat" and not SummerProjects.market_used(): return "开摊后备好这一篮，招待一位来摊边的街坊，再和大家聊聊"
	if qid == "Q14" and step in ["go_fest", "bon_odori14"] and (day > 17 or (day == 17 and hour() >= 22.0)):
		return "夏祭已经散场，找澪另约一晚，补上金鱼与合影"
	if qid == "Q15" and step == "watch_hanabi" and (day > 24 or (day == 24 and hour() >= 21.0)):
		return "去河边长椅听田中讲那晚的花火，继续这个夏天的故事"
	if qid == "Q16" and step == "bakery_supply":
		return "第 %d 天周六傍晚，交给莲番茄 2、黄瓜 1；可去试吃纸签改约或取消" % int(flags.get("bakery_due_day", next_market_day()))
	var steps: Array = quests_db[qid].steps
	return quest_step_description(qid, mini(qstep(qid), steps.size() - 1))

func add_affinity(who: String, n: int) -> void:
	var before := int(affinity.get(who, 0))
	affinity[who] = clampi(before + n, 0, MAX_AFF)
	if int(affinity[who]) > before and before >= 3:
		toast.emit("和%s更熟了：%s" % [npc_display(who), hearts_text(int(affinity[who]))])


func npc_display(who: String) -> String:
	return {"mio": "澪", "ren": "莲", "haru": "春", "tanaka": "田中爷爷", "aoi": "小葵", "kazuko": "和子阿姨"}.get(who, who)


static func hearts_text(n: int) -> String:
	return "♥".repeat(n) + "♡".repeat(MAX_AFF - n)


## Friendship beyond the story: every WARMTH_PER_HEART points turn into one heart.
func add_warmth(who: String, n: int) -> void:
	if n <= 0:
		return
	var w := int(warmth.get(who, 0)) + n
	while w >= WARMTH_PER_HEART and int(affinity.get(who, 0)) < MAX_AFF:
		w -= WARMTH_PER_HEART
		affinity[who] = int(affinity.get(who, 0)) + 1
		toast.emit("和%s更熟了：%s" % [npc_display(who), hearts_text(int(affinity[who]))])
		Audio.sting("sparkle")
	warmth[who] = w if int(affinity.get(who, 0)) < MAX_AFF else 0
	state_changed.emit()


## First chat of the day with a neighbour warms things up a little. Returns true the first time.
func note_talk(who: String) -> bool:
	var t: Dictionary = daily.get("talked", {})
	if t.has(who):
		return false
	t[who] = true
	daily["talked"] = t
	add_warmth(who, 1)
	return true


# ================================================================ money, experience
func earn(n: int, _why: String = "") -> void:
	if n <= 0:
		return
	coins += n
	ledger["in"] = int(ledger.get("in", 0)) + n
	coins_changed.emit(n)


func spend(n: int, _why: String = "") -> void:
	if n <= 0:
		return
	coins -= n
	ledger["out"] = int(ledger.get("out", 0)) + n
	coins_changed.emit(-n)


static func level_for(xp: int) -> int:
	var lv := 0
	for t in LEVELS:
		if xp >= int(t):
			lv += 1
	return lv


func level() -> int:
	return level_for(farm_xp)


## [xp into this level, xp needed for the next] (next = 0 at the top level)
func level_progress() -> Array:
	var lv := level()
	if lv >= LEVELS.size():
		return [farm_xp - int(LEVELS[-1]), 0]
	return [farm_xp - int(LEVELS[lv - 1]), int(LEVELS[lv]) - int(LEVELS[lv - 1])]


func add_xp(n: int) -> void:
	if n <= 0:
		return
	var before := level()
	farm_xp += n
	daily["xp"] = int(daily.get("xp", 0)) + n
	xp_gained.emit(n)
	var after := level()
	for lv in range(before + 1, after + 1):
		level_up.emit(lv, LEVEL_PERKS.get(lv, []))


func can_cap() -> int:
	return [CAN_CAP, 10, 20][clampi(can_level, 0, 2)]


# ================================================================ shops, selling, upgrades
func shop(sid: String) -> Dictionary:
	return shops_db.get(sid, {})


## "" when open, otherwise why not (closed day / hours).
func shop_closed_reason(sid: String) -> String:
	var sh := shop(sid)
	if sh.is_empty():
		return "没有这家店"
	if int(sh.get("closed_weekday", -1)) == weekday():
		return "今天是%s的定休日" % sh.name
	var h := hour()
	if h < float(sh.open) or h >= float(sh.close):
		return "%s的营业时间是 %d:00–%d:00" % [sh.name, int(sh.open), int(sh.close)]
	return ""


## Items a shop offers right now (seasonal items appear only around their festival).
func shop_stock(sid: String) -> Array:
	var out := []
	for iid in shop(sid).get("stock", []):
		if iid == "toro" and not (day >= 38 and day <= 43):
			continue
		if iid in ["sparklers", "candy_apple"] and day < 14:
			continue
		if iid == "seed_strawberry" and sid == "shed" and qstate("Q07") != "done":
			continue
		if iid in ["up_bag30", "up_bag40"] and bag_cap >= int(item(iid).get("cap", 0)):
			continue
		if iid in ["can_copper", "can_gold"] and can_level >= (1 if iid == "can_copper" else 2):
			continue
		if iid.begins_with("card_") and recipes_known.has(str(item(iid).get("recipe", ""))):
			continue
		if iid in ["up_yard", "up_gh"] and flags.get("owned_" + iid, false):
			continue
		out.append(iid)
	return out


func item_level(iid: String) -> int:
	var it := item(iid)
	if it.has("seed"):
		return int(crop_def(it.seed).get("level", 1))
	return int(it.get("level", 1))


## "" when the item can be bought now, otherwise the reason.
func buy_block(iid: String, n: int = 1) -> String:
	var it := item(iid)
	if it.is_empty():
		return "没有这种东西"
	if level() < item_level(iid):
		return "种植等级 %d 解锁" % item_level(iid)
	if iid == "can_gold" and can_level < 1:
		return "先买铜洒水壶"
	if iid == "up_bag40" and bag_cap < 30:
		return "先买大号背包"
	var price := int(it.get("price", 0)) * n
	if coins < price:
		return "生活币不够（需要 %d）" % price
	if not it.has("upgrade") and not it.has("recipe") and not can_add(iid, n):
		return "背包满了"
	return ""


## General shop purchase (seeds, ingredients, cards, upgrades). Decor still goes through buy().
func buy_item(iid: String, n: int = 1) -> String:
	var it := item(iid)
	if it.get("placeable", "") != "":
		return buy(iid)
	var r := buy_block(iid, n)
	if r != "":
		return r
	spend(int(it.get("price", 0)) * n, "买东西")
	match str(it.get("upgrade", "")):
		"bag":
			bag_cap = maxi(bag_cap, int(it.cap))
			toast.emit("背包扩到了 %d 格" % bag_cap)
		"can":
			can_level = maxi(can_level, 1 if iid == "can_copper" else 2)
			can_water = can_cap()
			if not has("farm_can"):
				add_item("farm_can", 1, true)
			toast.emit("换上了%s（%d 次）" % [it.name, can_cap()])
		"yard":
			flags["owned_" + iid] = true
			open_plots(["yard4", "yard5"])
			toast.emit("小院多了两块菜地")
		"gh":
			flags["owned_" + iid] = true
			open_plots(["gh2", "gh3"], true)
			toast.emit("第二间温室盖好了")
		_:
			if it.has("recipe"):
				recipes_known[str(it.recipe)] = true
				toast.emit("学会了「%s」" % recipe_name(str(it.recipe)))
			else:
				add_item(iid, n, true)
				toast.emit("买下 %s ×%d（-%d 生活币）" % [item_name(iid), n, int(it.get("price", 0)) * n])
	Audio.sting("coin")
	state_changed.emit()
	return ""


func sellable(iid: String) -> bool:
	var it := item(iid)
	return not is_key_item(iid) and int(it.get("sell", 0)) > 0 and it.get("placeable", "") == ""


## What a buyer pays for one more of this item right now (daily glut after GLUT_N sold).
func unit_price(iid: String, rate: float) -> int:
	var sold := int(daily.get("sold_n", {}).get(iid, 0))
	var mult := GLUT_RATE if sold >= GLUT_N else 1.0
	var bonus := 1.1 if level() >= 10 and item(iid).has("crop") else 1.0
	return int(round(float(item(iid).get("sell", 0)) * rate * mult * bonus))


func sale_value(iid: String, n: int, rate: float) -> int:
	var sold := int(daily.get("sold_n", {}).get(iid, 0))
	var full := clampi(GLUT_N - sold, 0, n)
	var base := float(item(iid).get("sell", 0)) * rate * (1.1 if level() >= 10 and item(iid).has("crop") else 1.0)
	return int(round(base)) * full + int(round(base * GLUT_RATE)) * (n - full)


## Which of the bag's items this buyer takes: "crop", "dish" (kitchen), "oven", "ingredient", "seed".
func buys_item(sid: String, iid: String) -> bool:
	var it := item(iid)
	if not sellable(iid):
		return false
	for kind in shop(sid).get("buys", []):
		match kind:
			"crop":
				if it.has("crop"):
					return true
			"dish":
				if it.has("dish"):
					return true
			"oven":
				if str(it.get("dish", "")) == "oven":
					return true
			"ingredient":
				if it.get("ingredient", false):
					return true
			"fish":
				if it.get("fish",false):
					return true
			"seed":
				if it.has("seed"):
					return true
	return false


# ================================================================ recipes and cooking
func recipe(rid: String) -> Dictionary:
	return recipes_db.get(rid, {})


func recipe_name(rid: String) -> String:
	return str(recipe(rid).get("name", rid))


func recipe_known(rid: String) -> bool:
	var u: Dictionary = recipe(rid).get("unlock", {})
	if u.get("default", false) or recipes_known.has(rid):
		return true
	if u.has("level") and level() >= int(u.level):
		return true
	if u.has("heart") and int(affinity.get(str(u.heart[0]), 0)) >= int(u.heart[1]):
		return true
	return false


func recipe_hint(rid: String) -> String:
	var u: Dictionary = recipe(rid).get("unlock", {})
	if rid in ["first_home_onigiri", "plain_onigiri"]:
		return "在家看看食材便笺，做完自己的饭"
	var ways := []
	if u.has("level"):
		ways.append("种植等级 %d" % int(u.level))
	if u.has("heart"):
		ways.append("和%s ♥%d" % [npc_display(str(u.heart[0])), int(u.heart[1])])
	if u.has("card"):
		ways.append("在面包店买配方卡（%d）" % int(u.card))
	return " 或 ".join(ways)


func station_recipes(station: String) -> Array:
	var out := []
	for rid in recipes_db:
		if not SummerProjects.active_recipe(str(rid)): continue
		if rid == "first_home_onigiri" and (not DailyLife.event("meal").get("parcel_claimed", false) or DailyLife.done("meal")):
			continue
		if str(recipes_db[rid].station) == station or (station == "oven" and str(recipes_db[rid].station) == "mill"):
			out.append(rid)
	return out


func craft_max(rid: String) -> int:
	if NeighbourMeals.rice_recipe(rid) and not NeighbourMeals.can_rice_craft(rid,1):return 0
	if rid==FoodPurpose.NEXT_RECIPE and not FoodPurpose.can_craft(1): return 0
	if rid == SummerProjects.TRIAL_RECIPE and (SummerProjects.phase() != "trial" or SummerProjects.opening().role != "food"): return 0
	var r := recipe(rid)
	var n := 99
	for k in r.inputs:
		var held := 0 if rid == "veg_sandwich" and at_step("Q16", "bakery_bake") else reserved_count(k)
		n = mini(n, maxi(0, count(k) - held) / int(r.inputs[k]))
	return mini(n, 1) if rid in [SummerProjects.TRIAL_RECIPE,FoodPurpose.NEXT_RECIPE] or NeighbourMeals.rice_recipe(rid) else n


## "" when n batches can be made now, otherwise why not.
func craft_block(rid: String, n: int = 1) -> String:
	if NeighbourMeals.rice_recipe(rid) and not NeighbourMeals.can_rice_craft(rid,n):return "这一顿只做两份饭团。想多做，用普通饭团配方就行。"
	if rid==FoodPurpose.NEXT_RECIPE and not FoodPurpose.can_craft(n): return "这张便笺先做两份饭团。想多做，换普通饭团配方。"
	if rid == SummerProjects.TRIAL_RECIPE and (n != 1 or SummerProjects.phase() != "trial" or SummerProjects.opening().role != "food"):
		return "这次试吃做一份，切成三小份。想换味道，到纸签上另选一种。"
	var r := recipe(rid)
	if r.is_empty():
		return "没有这个配方"
	if not recipe_known(rid):
		return "还没学会（%s）" % recipe_hint(rid)
	var miss := []
	for k in r.inputs:
		var held := 0 if rid == "veg_sandwich" and at_step("Q16", "bakery_bake") else reserved_count(k)
		var free := maxi(0, count(k) - held)
		if free < int(r.inputs[k]) * n:
			miss.append("%s ×%d%s" % [item_name(k), int(r.inputs[k]) * n - free, "（%s）" % reservation_note(k) if held > 0 else ""])
	if not miss.is_empty():
		return "还差：" + "、".join(miss)
	if minute + float(r.minutes) * n > float(DAY_END) - 30.0:
		return "太晚了，明天再做吧"
	for k in r.output:
		if not can_add(k, int(r.output[k]) * n):
			return "背包满了"
	return ""


## Cook / bake / mill: takes the recipe's time on the clock. Returns "" on success.
func craft(rid: String, n: int = 1) -> String:
	var why := craft_block(rid, n)
	if why != "":
		return why
	var r := recipe(rid)
	for k in r.inputs:
		remove_item(k, int(r.inputs[k]) * n)
	for k in r.output:
		add_item(k, int(r.output[k]) * n, true)
	flags["crafted"] = int(flags.get("crafted", 0)) + n
	zukan.dishes[rid] = int(zukan.dishes.get(rid, 0)) + n
	if str(r.station) == "kitchen":
		flags["cooked"] = int(flags.get("cooked", 0)) + n
	elif str(r.station) == "oven":
		flags["baked"] = int(flags.get("baked", 0)) + n
	if rid == "veg_sandwich" and at_step("Q16", "bakery_bake"):
		flags["bakery_trial_baked"] = true
	skip_to(minute + float(r.minutes) * n)
	DailyLife.record_craft(rid)
	SummerProjects.record_craft(rid)
	FoodPurpose.record_craft(rid)
	NeighbourMeals.record_craft(rid,n)
	state_changed.emit()
	return ""


# ================================================================ storage chest at home
func storage_used() -> int:
	var n := 0
	for id in storage:
		n += _slots_for(int(storage[id]))
	return n


func store_in(iid: String, n: int) -> bool:
	if is_key_item(iid) or count(iid) < n or n <= 0:
		return false
	var have := int(storage.get(iid, 0))
	if storage_used() - _slots_for(have) + _slots_for(have + n) > STORAGE_SLOTS:
		return false
	remove_item(iid, n)
	storage[iid] = have + n
	state_changed.emit()
	return true


func take_out(iid: String, n: int) -> bool:
	if int(storage.get(iid, 0)) < n or n <= 0 or not can_add(iid, n):
		return false
	storage[iid] = int(storage[iid]) - n
	if int(storage[iid]) <= 0:
		storage.erase(iid)
	add_item(iid, n, true)
	return true


# ================================================================ calendar and festivals
## Day 1 is 7月4日 (a Thursday).
static func date_of(d: int) -> Vector2i:
	var m := 7
	var dd := 3 + d
	var lens := {7: 31, 8: 31, 9: 30, 10: 31, 11: 30, 12: 31}
	while dd > int(lens.get(m, 30)):
		dd -= int(lens.get(m, 30))
		m += 1
	return Vector2i(m, dd)


func date_text(d: int = -1) -> String:
	var dt := date_of(day if d < 0 else d)
	return "%d月%d日" % [dt.x, dt.y]


func festival_on(d: int) -> String:
	for fid in festivals_db:
		if int(festivals_db[fid].day) == d:
			return fid
	return ""


func festival(fid: String) -> Dictionary:
	return festivals_db.get(fid, {})


## The festival whose event hours are running right now, or "".
func festival_now() -> String:
	var fid := festival_on(day)
	if fid == "":
		return ""
	var f := festival(fid)
	return fid if hour() >= float(f.start) and hour() < float(f.end) else ""


## Festivals whose decorations are up today (from the prep day through the day itself).
func festivals_decorated() -> Array:
	var out := []
	for fid in festivals_db:
		var f: Dictionary = festivals_db[fid]
		if day >= int(f.get("prep_day", f.day)) and day <= int(f.day):
			out.append(fid)
	return out


func next_festival() -> String:
	var best := ""
	for fid in festivals_db:
		var d := int(festivals_db[fid].day)
		if d >= day and (best == "" or d < int(festivals_db[best].day)):
			best = fid
	return best


# ================================================================ time & weather
func time_running() -> bool:
	return not clock_paused and not get_tree().paused and not input_locked()


func weekday(d: int = -1) -> int:
	return ((day if d < 0 else d) - 1 + FIRST_WEEKDAY) % 7


func weekday_name(d: int = -1) -> String:
	return WEEKDAYS[weekday(d)]


func clock_text() -> String:
	var m := int(minute)
	return "%02d:%02d" % [mini(m / 60, 24), m % 60]


func hour() -> float:
	return minute / 60.0


## morning 06-10, day 10-16, evening 16-18:30, dusk 18:30-20, night 20-
func period() -> String:
	var h := hour()
	if h < 10.0:
		return "morning"
	if h < 16.0:
		return "day"
	if h < 18.5:
		return "evening"
	if h < 20.0:
		return "dusk"
	return "night"


func is_market_time() -> bool:
	return weekday() == SATURDAY and minute >= MARKET_OPEN and minute < MARKET_CLOSE


## Deterministic per day. The first three days and every Saturday are sunny (晴町 lives up to its name).
const FESTIVAL_DAYS := [4, 11, 17, 24, 43, 76]   # data/festivals.json (tests check they match)

static func weather_for(d: int) -> String:
	if d <= 3 or ((d - 1 + FIRST_WEEKDAY) % 7) == SATURDAY or FESTIVAL_DAYS.has(d):
		return "sunny"
	var rng := RandomNumberGenerator.new()
	rng.seed = d * 7919 + 13
	var r := rng.randf()
	return "sunny" if r < 0.6 else ("cloudy" if r < 0.85 else "rain")


func weather_name() -> String:
	return WEATHERS.get(weather, "晴")


## Jump the clock forward within today (never backwards, never past midnight).
func skip_to(m: float) -> void:
	if m <= minute:
		return
	minute = minf(m, float(DAY_END) - 1.0)
	_tick_minute()
	state_changed.emit()


## Sleep: crops grow from yesterday's watering, compost matures, a new day and its weather begin.
func advance_day(wake_at: float = WAKE_MIN) -> bool:
	if calendar_pending_save == day and not save_game(true):
		return false
	flags["last_day_summary"]=DaySummary.capture()
	for id in plots:
		var p: Dictionary = plots[id]
		if not p.open or p.crop == "":
			p.water = false
			continue
		var grow: int = int(crop_def(p.crop).get("days", 3))
		if p.water and int(p.days) < grow:
			var boost := (3 if level() >= 9 else 2) if p.get("boost", false) else 1
			p.days = mini(int(p.days) + boost, grow)
			p.boost = false
		p.water = false
	if compost >= COMPOST_PER_BAG:
		compost_ready += compost / COMPOST_PER_BAG
		compost %= COMPOST_PER_BAG
	day += 1
	minute = clampf(wake_at, float(WAKE_MIN), float(DAY_END - 1))
	_last_min = -1
	weather = weather_for(day)
	if weather == "rain":
		for id in plots:
			if plots[id].open and plot_region(id) != "greenhouse":
				plots[id].water = true
	flags["last_ledger"] = {"in": int(ledger.get("in", 0)), "out": int(ledger.get("out", 0)), "xp": int(daily.get("xp", 0))}
	ledger = {"in": 0, "out": 0}
	var pending_request: Dictionary = request().duplicate(true)
	daily = {}
	if not pending_request.is_empty() and not pending_request.get("done", false):
		daily["request"] = pending_request
	# the first market ended before the chats: hold it again next Saturday
	if at_step("Q05", "chat"):
		var steps: Array = quests_db.Q05.steps
		for i in steps.size():
			if steps[i].id == "start":
				quests.Q05.step = i
		for who in ["mio", "ren", "haru"]:
			flags.erase("chat_" + who)
		toast.emit("集市那天没来得及和大家聊完……澪说下周六再办一次")
	if phase == "market":
		phase = "prep"
		phase_changed.emit(phase)
	_new_request()
	day_changed.emit(day)
	plots_changed.emit()
	state_changed.emit()
	var written: bool = save_game(true)
	if not written: calendar_pending_save = day
	return written


func set_phase(p: String) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(phase)
	state_changed.emit()


# ================================================================ farming
## Plot ids and where they are: the Q03 planter, the home yard, the riverside allotment, the greenhouse.
static func plot_ids() -> Array:
	var ids := ["court"]
	for i in 6:
		ids.append("yard%d" % i)
	for i in 12:
		ids.append("farm%d" % i)
	for i in 4:
		ids.append("gh%d" % i)
	return ids


static func plot_region(id: String) -> String:
	if id == "court":
		return "courtyard"
	if id.begins_with("yard"):
		return "yard"
	if id.begins_with("gh"):
		return "greenhouse"
	return "farm"


func _fresh_plots() -> Dictionary:
	var d := {}
	for id in plot_ids():
		d[id] = {"open": false, "tilled": false, "crop": "", "days": 0, "water": false, "fert": false, "boost": false, "regrown": false}
	return d


func crop_def(cid: String) -> Dictionary:
	return crops_db.get(cid, {})


func open_plots(ids: Array, tilled: bool = false) -> void:
	for id in ids:
		if plots.has(id):
			plots[id].open = true
			if tilled:
				plots[id].tilled = true
	plots_changed.emit()
	state_changed.emit()


## locked | wild | tilled | seeded | sprout | growing | ripe
func plot_state(id: String) -> String:
	var p: Dictionary = plots.get(id, {})
	if p.is_empty() or not p.open:
		return "locked"
	if not p.tilled:
		return "wild"
	if p.crop == "":
		return "tilled"
	var grow: int = int(crop_def(p.crop).get("days", 3))
	var d := int(p.days)
	if d >= grow:
		return "ripe"
	if p.get("regrown", false):
		return "growing"
	if d == 0:
		return "seeded"
	if d < int(ceil(grow / 2.0)):
		return "sprout"
	return "growing"


## Returns "" on success or a reason string (same convention as buy()).
func till(id: String) -> String:
	if plot_state(id) != "wild":
		return "这块地不用翻"
	if not has("hoe"):
		return "土硬邦邦的，得先借一把锄头"
	plots[id].tilled = true
	add_item("weeds", 2, true)
	add_xp(XP_TILL)
	Audio.fx("soil")
	plots_changed.emit()
	state_changed.emit()
	return ""


func seeds_owned(for_plot: String = "") -> Array:
	var out := []
	for iid in inventory:
		var cid: String = item(iid).get("seed", "")
		if cid == "":
			continue
		if for_plot != "" and bool(crop_def(cid).get("greenhouse", false)) != (plot_region(for_plot) == "greenhouse"):
			continue
		out.append(iid)
	return out


func sow(id: String, seed_item: String) -> String:
	if plot_state(id) != "tilled":
		return "这里现在不能播种"
	var cid: String = item(seed_item).get("seed", "")
	if cid == "" or not has(seed_item):
		return "背包里没有这种种子"
	var gh := plot_region(id) == "greenhouse"
	if bool(crop_def(cid).get("greenhouse", false)) and not gh:
		return "草莓苗怕雨，要种在温室里"
	if gh and not bool(crop_def(cid).get("greenhouse", false)):
		return "温室的地是留给草莓的"
	remove_item(seed_item, 1)
	var p: Dictionary = plots[id]
	p.crop = cid
	p.days = 0
	p.regrown = false
	add_xp(XP_SOW)
	if weather == "rain" and not gh:
		p.water = true
	Audio.fx("soil")
	plots_changed.emit()
	state_changed.emit()
	return ""


func water_plot(id: String) -> String:
	var s := plot_state(id)
	if s in ["locked", "wild", "tilled"]:
		return "这里还没有种东西"
	if plots[id].water:
		return "今天已经浇透了"
	if not has("farm_can"):
		return "需要洒水壶"
	if can_water <= 0:
		return "壶里没水了，去手压泵或饮水台装水吧"
	can_water -= 1
	plots[id].water = true
	add_xp(XP_WATER)
	Audio.fx("water_pour")
	plots_changed.emit()
	state_changed.emit()
	return ""


func refill_can() -> bool:
	if not has("farm_can"):
		return false
	can_water = can_cap()
	Audio.fx("water_tap")
	state_changed.emit()
	return true


func fertilize(id: String) -> String:
	var s := plot_state(id)
	if s in ["locked", "wild", "tilled", "ripe"]:
		return "要先种下作物再施肥"
	if plots[id].fert:
		return "已经施过肥了"
	if not has("fertilizer"):
		return "背包里没有堆肥"
	remove_item("fertilizer", 1)
	plots[id].fert = true
	plots[id].boost = true
	Audio.fx("soil")
	plots_changed.emit()
	state_changed.emit()
	return ""


## Returns {"item": id, "n": count} or {} when nothing was harvested (e.g. bag full).
func harvest(id: String) -> Dictionary:
	if plot_state(id) != "ripe":
		return {}
	var p: Dictionary = plots[id]
	var c := crop_def(p.crop)
	var n := int(c.get("yield", 1)) + (1 if p.fert else 0)
	if level() >= 8 and randf() < 0.25:
		n += 1
	var pid: String = p.crop
	if not add_item(pid, n, true):
		return {}
	var regrow := int(c.get("regrow", 0))
	if regrow > 0:
		p.days = int(c.days) - regrow
		p.regrown = true
	else:
		p.crop = ""
		p.days = 0
		p.regrown = false
	p.fert = false
	p.boost = false
	flags["harvests"] = int(flags.get("harvests", 0)) + n
	zukan.crops[pid] = int(zukan.crops.get(pid, 0)) + n
	add_xp(int(c.get("xp", 3)))
	Audio.sting("item")
	plots_changed.emit()
	state_changed.emit()
	var todays_harvest: Dictionary=daily.get("harvest_items",{})
	todays_harvest[pid]=int(todays_harvest.get(pid,0))+n;daily["harvest_items"]=todays_harvest
	return {"item": pid, "n": n}


func compost_add(iid: String) -> int:
	var it := item(iid)
	if not (it.get("compost", false) or it.has("crop")) or not has(iid):
		return 0
	var n := count(iid)
	remove_item(iid, n)
	compost += n
	Audio.fx("soil")
	state_changed.emit()
	return n


func compost_take() -> int:
	var n := compost_ready
	if n <= 0 or not add_item("fertilizer", n, true):
		return 0
	compost_ready = 0
	flags["fertilizer_made"] = int(flags.get("fertilizer_made", 0)) + n
	return n


func produce_owned() -> Array:
	return inventory.keys().filter(func(iid): return item(iid).has("crop"))


## Sell produce only (never key items or decor). Returns coins earned.
func sell_produce(iid: String, n: int, rate: float) -> int:
	var it := item(iid)
	if not sellable(iid) or n <= 0 or count(iid) < n:
		return 0
	n = mini(n, unreserved_count(iid))
	if n <= 0:
		toast.emit("%s：%s" % [item_name(iid), reservation_note(iid)])
		return 0
	var pay := sale_value(iid, n, rate)
	remove_item(iid, n)
	var sold: Dictionary = daily.get("sold_n", {})
	sold[iid] = int(sold.get(iid, 0)) + n
	daily["sold_n"] = sold
	earn(pay, "卖东西")
	daily["sold"] = int(daily.get("sold", 0)) + n
	flags["sold_total"] = int(flags.get("sold_total", 0)) + n
	if rate > 1.0:
		flags["sold_market"] = int(flags.get("sold_market", 0)) + n
	Audio.sting("coin")
	state_changed.emit()
	return pay


func farm_expand_cost() -> int:
	return FARM_EXPAND_COST[farm_expansions] if farm_expansions < FARM_EXPAND_COST.size() else -1


func expand_farm() -> String:
	var cost := farm_expand_cost()
	if cost < 0:
		return "农园已经全部租下来了"
	if level() < int(FARM_EXPAND_LV[farm_expansions]):
		return "种植等级 %d 以后田中爷爷才肯再租给你" % int(FARM_EXPAND_LV[farm_expansions])
	if coins < cost:
		return "生活币不够（需要 %d）" % cost
	spend(cost, "扩租农园")
	var base := 4 + farm_expansions * 4
	farm_expansions += 1
	var ids := []
	for i in range(base, base + 4):
		ids.append("farm%d" % i)
	open_plots(ids)
	Audio.sting("coin")
	return ""


## A neighbour's gift: liked crops count double. One gift per person per day.
func give_gift(who: String, iid: String) -> int:
	var g: Dictionary = daily.get("gifted", {})
	if g.has(who) or unreserved_count(iid) < 1 or is_key_item(iid):
		return 0
	remove_item(iid, 1)
	g[who] = iid
	daily["gifted"] = g
	flags["gifts"] = int(flags.get("gifts", 0)) + 1
	var pts := gift_points(who, iid)
	add_warmth(who, pts)
	return pts


## Warmth a gift is worth: produce 1 (liked 2), home-made dishes and bread 2 (liked 3).
func gift_points(who: String, iid: String) -> int:
	var it := item(iid)
	var liked: Array = it.get("liked_by", crop_def(str(it.get("crop", ""))).get("liked_by", []))
	var dish: bool = it.has("dish") or iid in ["onigiri", "candy_apple", "melon_pan"]
	return (2 if dish else 1) + (1 if liked.has(who) else 0)


func giftables() -> Array:
	return inventory.keys().filter(func(iid): return unreserved_count(iid) > 0 and ((sellable(iid) and not item(iid).get("ingredient", false) and not item(iid).has("seed")) or iid == "candy_apple"))


func dishes_owned() -> Array:
	return inventory.keys().filter(func(iid): return item(iid).has("dish"))


func gifted_today(who: String) -> bool:
	return daily.get("gifted", {}).has(who)


## One small request per day on the board once the allotment is running.
func _new_request() -> void:
	if qstate("Q06") != "done":
		return
	if not request().is_empty() and not request().get("done", false):
		return
	var who_pool := ["mio", "ren", "haru", "tanaka"]
	if flags.get("met_aoi", false):
		who_pool.append("aoi")
	var crop_pool: Array = ["radish", "komatsuna", "tomato", "cucumber", "edamame"].filter(func(cid): return int(crop_def(cid).get("level", 1)) <= level())
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 131 + 7
	var who: String = who_pool[rng.randi() % who_pool.size()]
	var cid: String = crop_pool[rng.randi() % crop_pool.size()]
	var liked_first := []
	for c in crop_pool:
		if (crop_def(c).get("liked_by", []) as Array).has(who):
			liked_first.append(c)
	if not liked_first.is_empty() and rng.randf() < 0.6:
		cid = liked_first[rng.randi() % liked_first.size()]
	var n := 1 + rng.randi() % 3
	daily["request"] = {"who": who, "item": cid, "n": n, "done": false,
			"reward": int(crop_def(cid).get("sell", 20)) * n + 20, "issued_day": day}


func request() -> Dictionary:
	return daily.get("request", {})


func request_lines() -> Array[String]:
	var r: Dictionary = request()
	if r.is_empty():
		return []
	if r.get("done", false):
		return ["✓ %s收到%s ×%d了。" % [npc_display(str(r.who)), item_name(str(r.item)), int(r.n)]]
	return [
		"街坊的小事：%s想要%s ×%d。" % [npc_display(str(r.who)), item_name(str(r.item)), int(r.n)],
		"可交 %d/%d · 谢礼 %d 生活币" % [mini(unreserved_count(str(r.item)), int(r.n)), int(r.n), int(r.reward)],
		"不赶今天，备齐后当面交给街坊；改天也行。按 J 可以查看。",
	]


func fulfil_request(who: String) -> int:
	var r := request()
	if r.is_empty() or r.done or r.who != who or unreserved_count(r.item) < int(r.n):
		return 0
	remove_item(r.item, int(r.n))
	r.done = true
	NeighbourMeals.record_request(r)
	flags.erase("request_tracked")
	earn(int(r.reward), "公告栏委托")
	add_warmth(who, 2)
	flags["requests_done"] = int(flags.get("requests_done", 0)) + 1
	Audio.sting("coin")
	state_changed.emit()
	return int(r.reward)


# ---------------------------------------------------------------- crop
func set_crop(stage: int) -> void:
	if stage <= crop_stage:
		return
	crop_stage = clampi(stage, 0, 3)
	crop_changed.emit(crop_stage)
	state_changed.emit()


# ---------------------------------------------------------------- placement
func add_placement(item_id: String, x: float, z: float, rot: int) -> int:
	if not remove_item(item_id, 1):
		return -1
	var uid := next_uid
	next_uid += 1
	placements.append({"uid": uid, "item": item_id, "x": x, "z": z, "rot": rot})
	if PlacementSystem.project_context == "space": SummerSpace.placement_added(uid, item_id)
	Audio.fx("place")
	placements_changed.emit()
	state_changed.emit()
	return uid

func remove_placement(uid: int) -> bool:
	if phase != "prep" and PlacementSystem.project_context != "space":
		return false
	for i in placements.size():
		if int(placements[i].uid) == uid:
			var it: String = placements[i].item
			if not can_add(it):
				toast.emit("背包满了，收不回来")
				return false
			placements.remove_at(i)
			SummerSpace.placement_removed(uid)
			add_item(it, 1, true)
			Audio.fx("pickup")
			placements_changed.emit()
			state_changed.emit()
			return true
	return false

func placed_count(item_id: String) -> int:
	return placements.filter(func(p): return p.item == item_id).size()

func seating_ready() -> bool:
	return placed_count("picnic_table") >= 1 and placed_count("bench") >= 1

func placed_decor() -> Array:
	var kinds := {}
	for p in placements:
		if item(p.item).get("placeable", "") == "decor":
			kinds[p.item] = true
	return kinds.keys()


# ---------------------------------------------------------------- market
func invited(who: String) -> bool:
	return bool(flags.get("invited_" + who, false))

func market_ready_reasons() -> Array:
	var r := []
	if not seating_ready():
		r.append("庭院里还没摆好野餐桌和长椅")
	if SummerProjects.uses_cooperation_mainline() and not SummerProjects.ready():
		r.append("菜单或现在的取餐路线还没有试好")
	if not invited("ren"):
		r.append("还没邀请莲")
	if not invited("haru"):
		r.append("还没邀请春")
	return r

func start_market() -> bool:
	if not at_step("Q05", "start") or not market_ready_reasons().is_empty() or not is_market_time():
		return false
	phase = "market"
	advance("Q05", "start")
	if crop_stage > 0: set_crop(3)
	for p in placed_decor():
		var who: String = item(p).get("liked_by", "")
		if who != "":
			add_affinity(who, 1)
	phase_changed.emit(phase)
	state_changed.emit()
	save_game()
	return true


# ---------------------------------------------------------------- fishing
func borrow_fishing_kit() -> String:
	if has("fishing_rod"):
		return ""
	if not can_add("fishing_bait",10):
		return "背包先空出一格，才能领取鱼饵"
	add_item("fishing_rod",1,true)
	if not flags.get("fishing_kit_received",false):
		add_item("fishing_bait",10,true)
		flags["fishing_kit_received"]=true
		toast.emit("借到晴川钓竿和 10 份鱼饵。第一次抛竿前会说明操作")
	state_changed.emit()
	return ""

func fish_pool(habitat: String, at_hour: float = -1.0, in_weather: String = "") -> Array:
	var result: Array = []
	var h := hour() if at_hour<0 else at_hour
	var sky := weather if in_weather=="" else in_weather
	for id: String in fish_db:
		var definition: Dictionary=fish_db[id]
		if not habitat in definition.habitats:continue
		var available := false
		for interval: Array in definition.hours:
			if h>=float(interval[0]) and h<float(interval[1]):available=true
		if available:
			result.append({"id":id,"weight":float(definition.weight)*(float(definition.get("rain_bonus",1.0)) if sky=="rain" else 1.0)})
	return result

func spot_fish_pool(spot_id: String, at_hour: float = -1.0, in_weather: String = "") -> Array:
	if not LakesideLayout.SPOTS.has(spot_id):return []
	var spec: Dictionary=LakesideLayout.SPOTS[spot_id]
	return fish_pool(str(spec.habitat),at_hour,in_weather).filter(func(row: Dictionary):return str(row.id) in spec.species)

func begin_fishing(spot_id: String, roll: float = -1.0, size_roll: float = -1.0) -> Dictionary:
	if not _fishing_ticket.is_empty():return {"error":"已经抛下了一竿"}
	if not LakesideLayout.SPOTS.has(spot_id):return {"error":"这里没有钓点"}
	if not has("fishing_rod"):return {"error":"先到湖畔补给处借一支钓竿"}
	if not has("fishing_bait"):return {"error":"鱼饵用完了，商店和湖畔补给处都有卖"}
	if minute+12.0>DAY_END-30.0:return {"error":"夜深了，明天再来钓鱼吧"}
	var pool := spot_fish_pool(spot_id)
	if pool.is_empty():return {"error":"现在水面很安静，换个时间再试吧"}
	var total := 0.0
	for candidate: Dictionary in pool:total+=float(candidate.weight)
	var ticket_roll := clampf(randf() if roll<0 else roll,0.0,.999999)*total
	var fish_id := str(pool[-1].id)
	for candidate: Dictionary in pool:
		ticket_roll-=float(candidate.weight)
		if ticket_roll<=0:
			fish_id=str(candidate.id)
			break
	if not can_add(fish_id,1):return {"error":"背包满了，先留一格给钓到的鱼"}
	remove_item("fishing_bait",1)
	_fishing_serial+=1
	_fishing_ticket={"ticket":_fishing_serial,"fish":fish_id,"roll":randf() if size_roll<0 else clampf(size_roll,0,1)}
	fishing.casts=int(fishing.casts)+1
	skip_to(minute+12.0)
	state_changed.emit()
	return {"ticket":_fishing_serial,"difficulty":float(fish_db[fish_id].difficulty),"behaviour":str(fish_db[fish_id].get("behaviour","steady"))}

func cancel_fishing(ticket: int) -> void:
	if int(_fishing_ticket.get("ticket",-1))==ticket:
		_fishing_ticket.clear()

func land_fish(ticket: int, quality: float) -> Dictionary:
	if ticket<=0 or _fishing_ticket.is_empty() or int(_fishing_ticket.get("ticket",-1))!=ticket:return {"error":"这一竿已经结束"}
	var saved := _fishing_ticket.duplicate()
	_fishing_ticket.clear() # inventory signals must not allow the same fish twice
	var id := str(saved.fish)
	if not add_item(id,1,true):return {"error":"背包装满了，这条鱼已放回水里"}
	var range_cm: Array=fish_db[id].cm
	var size_value := snappedf(lerpf(float(range_cm[0]),float(range_cm[1]),clampf(float(saved.roll)*.85+clampf(quality,0,1)*.15,0,1)),.1)
	fishing.landed=int(fishing.landed)+1
	daily["fish_n"]=int(daily.get("fish_n",0))+1
	var todays_fish: Dictionary=daily.get("fish_items",{})
	todays_fish[id]=int(todays_fish.get(id,0))+1;daily["fish_items"]=todays_fish
	fishing.caught[id]=int(fishing.caught.get(id,0))+1
	var record := size_value>float(fishing.best_cm.get(id,0))
	fishing.best_cm[id]=maxf(size_value,float(fishing.best_cm.get(id,0)))
	state_changed.emit()
	return {"fish":id,"cm":size_value,"new_record":record,"sell":int(item(id).sell)}

# ---------------------------------------------------------------- save / load
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION, "saved_at": Time.get_datetime_string_from_system(),
		"coins": coins, "inventory": inventory, "key_items": key_items, "quests": quests,
		"flags": flags, "affinity": affinity, "placements": placements, "next_uid": next_uid,
		"crop_stage": crop_stage, "phase": phase, "tracked_quest": tracked_quest,
		"player": {"x": player_pos.x, "y": player_pos.y, "z": player_pos.z, "yaw": player_yaw, "in_room": player_in_room},
		"play_time": play_time, "minigames": minigames,
		"day": day, "minute": minute, "weather": weather, "plots": plots, "can_water": can_water,
		"compost": compost, "compost_ready": compost_ready, "farm_expansions": farm_expansions,
		"warmth": warmth, "daily": daily, "region": player_region,
		"farm_xp": farm_xp, "bag_cap": bag_cap, "can_level": can_level, "storage": storage,
		"recipes_known": recipes_known, "ledger": ledger,
		"achievements": achievements, "collection": collection, "zukan": zukan,
		"fishing": fishing,
	}

func from_dict(d: Dictionary) -> bool:
	calendar_pending_save = -1
	var ver := int(d.get("version", -1))
	if ver < 1 or ver > SAVE_VERSION:
		last_error = "存档版本不兼容（%s），无法读取。" % str(d.get("version", "?"))
		return false
	coins = int(d.coins)
	inventory = _int_dict(d.inventory)
	key_items = _int_dict(d.key_items)
	quests = {}
	for q in quests_db:
		var src: Dictionary = d.quests.get(q, {"state": "locked", "step": 0})
		quests[q] = {"state": str(src.state), "step": int(src.step)}
	flags = d.flags
	affinity = {"mio": 0, "ren": 0, "haru": 0, "tanaka": 0, "aoi": 0}
	affinity.merge(_int_dict(d.affinity), true)
	placements = []
	for p in d.placements:
		placements.append({"uid": int(p.uid), "item": str(p.item), "x": float(p.x), "z": float(p.z), "rot": int(p.rot)})
	next_uid = int(d.next_uid)
	crop_stage = int(d.crop_stage)
	phase = str(d.phase)
	tracked_quest = str(d.get("tracked_quest", ""))
	var pl: Dictionary = d.player
	player_pos = Vector3(float(pl.x), float(pl.y), float(pl.z))
	player_yaw = float(pl.yaw)
	player_in_room = bool(pl.get("in_room", false))
	has_player_pos = true
	play_time = float(d.get("play_time", 0.0))
	minigames = {}
	var mg = d.get("minigames", {})
	if typeof(mg) == TYPE_DICTIONARY:
		for k in mg:
			var r = mg[k]
			if typeof(r) == TYPE_DICTIONARY:
				minigames[str(k)] = {"best": int(r.get("best", 0)), "stars": clampi(int(r.get("stars", 0)), 0, 3), "plays": int(r.get("plays", 0))}
				if r.get("outcome", null) is Dictionary:
					var outcome: Dictionary = r.outcome.duplicate(true)
					for count_key: String in ["caught", "served"]:
						if outcome.has(count_key): outcome[count_key] = maxi(int(outcome[count_key]), 0)
					minigames[str(k)]["outcome"] = outcome
					if r.has("last_day"): minigames[str(k)]["last_day"] = int(r.last_day)
	# v2: clock, weather and farming (v1 saves start on moving day at 09:00 with every plot closed)
	day = int(d.get("day", 1))
	minute = float(d.get("minute", START_MIN))
	_last_min = -1
	weather = str(d.get("weather", weather_for(day)))
	plots = _fresh_plots()
	var sp = d.get("plots", {})
	if typeof(sp) == TYPE_DICTIONARY:
		for id in sp:
			if plots.has(id) and typeof(sp[id]) == TYPE_DICTIONARY:
				var src: Dictionary = sp[id]
				var p: Dictionary = plots[id]
				for k in p:
					if src.has(k):
						p[k] = int(src[k]) if typeof(p[k]) == TYPE_INT else (bool(src[k]) if typeof(p[k]) == TYPE_BOOL else str(src[k]))
	can_water = int(d.get("can_water", 0))
	compost = int(d.get("compost", 0))
	compost_ready = int(d.get("compost_ready", 0))
	farm_expansions = int(d.get("farm_expansions", 0))
	warmth = _int_dict(d.get("warmth", {}))
	daily = d.get("daily", {}) if typeof(d.get("daily", {})) == TYPE_DICTIONARY else {}
	if minute >= DAY_END: daily.erase("late_sent")
	player_region = str(d.get("region", "town"))
	# v3: experience, bigger bags, the home chest, recipes
	farm_xp = int(d.get("farm_xp", 0))
	bag_cap = maxi(INV_SLOTS, int(d.get("bag_cap", INV_SLOTS)))
	can_level = int(d.get("can_level", 0))
	storage = _int_dict(d.get("storage", {}))
	recipes_known = {}
	for k in d.get("recipes_known", {}):
		recipes_known[str(k)] = true
	ledger = {"in": 0, "out": 0}
	var lg = d.get("ledger", {})
	if typeof(lg) == TYPE_DICTIONARY:
		ledger = {"in": int(lg.get("in", 0)), "out": int(lg.get("out", 0))}
	# v4: achievements, 晴町旧物, picture book
	achievements = _int_dict(d.get("achievements", {}))
	collection = _int_dict(d.get("collection", {}))
	var zk = d.get("zukan", {})
	zukan = {"crops": {}, "dishes": {}}
	if typeof(zk) == TYPE_DICTIONARY:
		zukan.crops = _int_dict(zk.get("crops", {}))
		zukan.dishes = _int_dict(zk.get("dishes", {}))
	fishing = {"casts":0,"landed":0,"caught":{},"best_cm":{}}
	var old_fishing: Dictionary = d.get("fishing",{}) if d.get("fishing",{}) is Dictionary else {}
	fishing.casts = maxi(0,int(old_fishing.get("casts",0)))
	fishing.landed = maxi(0,int(old_fishing.get("landed",0)))
	for fish_id: String in fish_db:
		if old_fishing.get("caught",{}) is Dictionary:
			var amount := maxi(0,int(old_fishing.get("caught",{}).get(fish_id,0)))
			if amount>0:fishing.caught[fish_id]=amount
		if old_fishing.get("best_cm",{}) is Dictionary:
			var length := maxf(0,float(old_fishing.get("best_cm",{}).get(fish_id,0)))
			if length>0:fishing.best_cm[fish_id]=length
	_fishing_ticket.clear()
	clear_locks()
	DailyLife.initialize(false)
	SummerProjects.initialize(false, true)
	SummerGathering.state()
	FoodPurpose.register_meal()
	NeighbourMeals.register()
	SummerProjects.checks()
	MainlineProgress.initialize()
	StoryKnowledge.initialize()
	state_changed.emit()
	return true

func _int_dict(src) -> Dictionary:
	var out := {}
	for k in src:
		out[str(k)] = int(src[k])
	return out


## Photos follow the database's directory, including isolated test/review saves.
func photo_path() -> String:
	return SaveDB.directory.path_join("photo_natsumatsuri.png")


const BAKERY_KIT := {"tomato": 2, "cucumber": 1, "flour": 1, "butter": 1}
const BAKERY_ORDER := {"tomato": 2, "cucumber": 1}


func can_add_bundle(bundle: Dictionary) -> bool:
	var merged: Dictionary = inventory.duplicate()
	for iid in bundle:
		if not is_key_item(iid):
			merged[iid] = int(merged.get(iid, 0)) + int(bundle[iid])
	var slots := 0
	for iid in merged:
		slots += _slots_for(int(merged[iid]))
	return slots <= bag_cap


func bakery_claim_kit() -> bool:
	if not at_step("Q16", "bakery_bake") or flags.get("bakery_kit_claimed", false) or not can_add_bundle(BAKERY_KIT):
		return false
	for iid in BAKERY_KIT:
		add_item(iid, int(BAKERY_KIT[iid]), true)
	flags["bakery_kit_claimed"] = true
	state_changed.emit()
	save_game()
	return true


func bakery_taste(who: String) -> bool:
	var tasters: Dictionary = flags.get("bakery_tasters", {})
	if not at_step("Q16", "bakery_taste") or who not in ["mio", "haru", "kazuko"] or tasters.has(who) or not has("bakery_sample"):
		return false
	remove_item("bakery_sample", 1)
	tasters[who] = true
	flags["bakery_tasters"] = tasters
	state_changed.emit()
	return true


func next_market_day(future: bool = false) -> int:
	var days := (SATURDAY - weekday() + 7) % 7
	if days == 0 and (future or minute >= MARKET_CLOSE):
		days = 7
	return day + days


func bakery_accept_order() -> void:
	if not at_step("Q16", "bakery_menu") and qstate("Q16") != "done":
		return
	flags["bakery_order_active"] = true
	flags["bakery_shop_stock"] = false
	flags["bakery_due_day"] = next_market_day()
	state_changed.emit()
	save_game()


func bakery_order_ready() -> bool:
	return (at_step("Q16", "bakery_supply") or flags.get("bakery_order_active", false)) \
		and day >= int(flags.get("bakery_due_day", day + 1)) and weekday() == SATURDAY \
		and minute >= MARKET_OPEN and minute < MARKET_CLOSE


func reserved_count(iid: String) -> int:
	var life_held: int = DailyLife.held(iid) + SummerProjects.held(iid) + WorkshopProject.held(iid) + NeighbourMeals.held(iid)
	if at_step("Q16", "bakery_bake") and flags.get("bakery_kit_claimed", false) and not flags.get("bakery_trial_baked", false):
		return life_held + int(BAKERY_KIT.get(iid, 0))
	if (at_step("Q16", "bakery_bake") and flags.get("bakery_trial_baked", false)) or at_step("Q16", "bakery_trial"):
		return life_held + (1 if iid == "veg_sandwich" else 0)
	if flags.get("bakery_order_active", false):
		return life_held + int(BAKERY_ORDER.get(iid, 0))
	return life_held


func reservation_note(iid: String) -> String:
	if NeighbourMeals.held(iid)>0:return "和春这一顿留的一份饭团；在杯边一起吃"
	if WorkshopProject.held(iid) > 0: return "留给这一盏代表灯笼；固定第一个接头时消耗一次"
	if SummerProjects.held(iid) > 0: return "留给这一次合作的两位试吃者，剩下一小份可以自己吃"
	if DailyLife.held(iid) > 0:
		return "留给自己的第一顿饭，去饭桌决定怎么吃"
	return "预留给莲，可去试吃纸签改约或取消"


func unreserved_count(iid: String) -> int:
	return maxi(0, count(iid) - reserved_count(iid))


func bakery_deliver() -> String:
	if not bakery_order_ready() or phase != "market" or not flags.get("bakery_order_active", false):
		return "周六傍晚再交这一篮菜；取消过的订单可以用店里材料继续"
	for iid in BAKERY_ORDER:
		if count(iid) < int(BAKERY_ORDER[iid]):
			return "还差材料：番茄 2、黄瓜 1。可改约，也可让莲用店里材料"
	var pay := 0
	for iid in BAKERY_ORDER:
		pay += sale_value(iid, int(BAKERY_ORDER[iid]), MARKET_RATE)
	if not take_all(BAKERY_ORDER):
		return "材料还没齐"
	var sold: Dictionary = daily.get("sold_n", {})
	for iid in BAKERY_ORDER:
		sold[iid] = int(sold.get(iid, 0)) + int(BAKERY_ORDER[iid])
	daily["sold_n"] = sold
	daily["sold"] = int(daily.get("sold", 0)) + 3
	flags["sold_total"] = int(flags.get("sold_total", 0)) + 3
	flags["sold_market"] = int(flags.get("sold_market", 0)) + 3
	earn(pay, "莲的供货订单")
	flags["bakery_supplies"] = int(flags.get("bakery_supplies", 0)) + 1
	bakery_serve(true)
	toast.emit("交给莲番茄 2、黄瓜 1，+%d 生活币" % pay)
	return ""


func bakery_serve(supplied: bool) -> void:
	if not bakery_order_ready() or phase != "market":
		return
	var first := at_step("Q16", "bakery_supply")
	flags["bakery_order_active"] = false
	flags["bakery_shop_stock"] = false
	flags["bakery_first_served"] = true
	flags["bakery_served_day"] = day
	if first:
		flags["bakery_supplied_first"] = supplied
		advance("Q16", "bakery_supply")
	flags["bakery_offer_after"] = next_market_day(true)
	state_changed.emit()
	save_game()

func save_game(automatic: bool=false,slot: int=0) -> bool:
	get_tree().call_group("save_hooks", "before_save")
	if not SaveDB.save_snapshot(to_dict(),slot):
		last_error = SaveDB.error_message
		toast.emit(last_error)
		save_finished.emit(false,automatic)
		return false
	last_error = ""
	if calendar_pending_save == day: calendar_pending_save = -1
	toast.emit("一天结束，进度已自动保存" if automatic else "已保存")
	save_finished.emit(true,automatic)
	return true


func save_to_slot(slot: int) -> bool:
	if slot<1 or slot>SaveDB.MAX_SLOTS:
		last_error="存档位置应为 1 至 6";toast.emit(last_error);save_finished.emit(false,false);return false
	return save_game(false,slot)


func load_slot(slot: int) -> bool:
	var data:=SaveDB.load_slot(slot)
	if data.is_empty():last_error=SaveDB.error_message;return false
	if not from_dict(data):last_error="存档版本或内容不兼容";return false
	last_error="";return true

func has_save() -> bool:
	return SaveDB.has_save()

func load_game() -> bool:
	last_error = ""
	for candidate in SaveDB.load_candidates():
		if from_dict(candidate.data):
			if candidate.slot == "previous" or SaveDB.recovered_database:
				toast.emit("主存档损坏，已从上一份备份恢复")
			SaveDB.recovered_database = false
			return true
	if last_error == "":
		last_error = SaveDB.error_message if not SaveDB.error_message.is_empty() else "没有找到可读取的存档"
	return false


# ---------------------------------------------------------------- settings
func load_settings() -> void:
	var saved := SaveDB.load_settings()
	for key in saved:
		settings[key] = saved[key]
	apply_settings()

func save_settings() -> void:
	if not SaveDB.save_settings(settings):
		toast.emit(SaveDB.error_message)
	apply_settings()

func apply_settings() -> void:
	Audio.apply_volumes(settings)
	if DisplayServer.get_name() == "headless":
		return
	var fs := bool(settings.get("fullscreen", false))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and (fs or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
		DisplayServer.window_set_mode(mode)
	get_tree().root.content_scale_factor = float(settings.get("text_scale", 1.0))


# ---------------------------------------------------------------- utils
func _read_json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}

func track_quest(qid: String) -> void:
	if qstate(qid) != "active": return
	tracked_quest = qid
	DailyLife.clear_tracking()
	SummerProjects.clear_tracking()
	flags.erase("request_tracked")
	state_changed.emit()

func quest_step_description(qid: String, index: int) -> String:
	if SummerProjects.uses_cooperation_mainline():
		if qid == "Q05": return ["把试过的菜单和取餐方案告诉澪", "保留试过的桌椅摆放", "当面邀请莲和春", "周六傍晚请澪开摊", "递一份给来摊边的街坊，再和三位邻居聊聊"][index]
		if qid == "Q13": return ["从春那里拿图纸，看看今年场地的需要", "随时和田中确认搭台与场地分工", "摆好长椅与餐桌，留出入口，再请街坊来试试", "保留试过的方案，把结果告诉田中"][index]
		if qid == "Q12": return ["到工作间选这一盏的用途与和纸", "领取一份社区竹篾，其余由街坊准备", "接牢样灯，点亮试挂，看看认不认得出、会不会碰头", "告诉澪这盏挂在哪儿，刚才试得怎么样"][index]
	return str(quests_db[qid].steps[index].desc)
