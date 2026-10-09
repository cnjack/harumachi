extends RefCounted
var t: Node
func _init(runner: Node) -> void:t=runner
func check(label: String,ok: bool) -> void:t.check("SAVE_SLOTS",label,ok)
func run() -> void:
	var supports:=SaveDB.has_method("list_slots") and GameState.has_method("save_to_slot")
	if not supports:
		for label in ["legacy progress migrates only into position one","new position does not duplicate into empty position one","active position survives a store restart","invalid zero and negative positions preserve saves","corrupt position cannot overwrite live progress","other positions survive one corrupt position","overwriting needs a second explicit selection","switching position resets the working backup history"]:check(label,false)
		return
	var state: Dictionary=GameState.to_dict().duplicate(true)
	var original: String=SaveDB.directory
	var folder: String="/tmp/harumachi-slots-regression-"+str(Time.get_ticks_usec())
	SaveDB.set_directory(folder);GameState.new_game();GameState.coins=400
	GameState.call("save_to_slot",4)
	var rows: Array=SaveDB.call("list_slots")
	check("new position does not duplicate into empty position one",bool(rows[0].empty) and not bool(rows[3].empty))
	SaveDB.set_directory(folder);rows=SaveDB.call("list_slots");GameState.coins=411;GameState.save_game()
	rows=SaveDB.call("list_slots")
	check("active position survives a store restart",SaveDB.active_slot==4 and int(rows[3].coins)==411 and bool(rows[0].empty))
	var before: Array=rows.duplicate(true)
	check("invalid zero and negative positions preserve saves",not bool(GameState.call("save_to_slot",0)) and not bool(GameState.call("save_to_slot",-1)) and before==SaveDB.call("list_slots"))
	GameState.coins=120;GameState.call("save_to_slot",2)
	var candidates: Array=SaveDB.load_candidates()
	check("switching position resets the working backup history",candidates.size()==1 and candidates[0].slot=="current")
	var sqlite:=SQLite.new();sqlite.path=SaveDB.database_path;sqlite.open_db();sqlite.query("UPDATE save_slots SET checksum='bad' WHERE slot=2");sqlite.close_db()
	GameState.coins=777
	check("corrupt position cannot overwrite live progress",not bool(GameState.call("load_slot",2)) and GameState.coins==777)
	check("other positions survive one corrupt position",bool(GameState.call("load_slot",4)) and GameState.coins==411)
	if ResourceLoader.exists("res://scripts/ui/save_slots_panel.gd"):
		var panel: Control=load("res://scripts/ui/save_slots_panel.gd").new();t.add_child(panel);panel.call("setup","save")
		var selected: Array[int]=[];panel.connect("slot_chosen",func(slot: int):selected.append(slot))
		panel.call("_choose",4);var first: bool=selected.is_empty();panel.call("_choose",4)
		check("overwriting needs a second explicit selection",first and selected==[4]);panel.queue_free();await t.frames(3)
	else:check("overwriting needs a second explicit selection",false)
	# An old SQLite database containing only the current snapshot stays readable.
	SaveDB.set_directory(folder+"-legacy");GameState.new_game();var payload:=JSON.stringify(GameState.to_dict())
	var legacy:=SQLite.new();legacy.path=SaveDB.database_path;legacy.open_db();legacy.query("CREATE TABLE snapshots(slot TEXT PRIMARY KEY,version INTEGER,payload TEXT,checksum TEXT,saved_at INTEGER)")
	legacy.query_with_bindings("INSERT INTO snapshots VALUES ('current',4,?,'bad',1)",[payload]);legacy.query_with_bindings("INSERT INTO snapshots VALUES ('previous',4,?,?,1)",[payload,payload.sha256_text()]);legacy.close_db()
	rows=SaveDB.call("list_slots")
	check("legacy progress migrates only into position one",not bool(rows[0].empty) and bool(rows[0].valid) and rows.slice(1).all(func(row: Dictionary):return bool(row.empty)))
	SaveDB.set_directory(original);GameState.from_dict(state)
