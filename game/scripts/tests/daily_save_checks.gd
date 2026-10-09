extends RefCounted
var t: Node
var main: Node
var events: Array[Dictionary]=[]
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(name: String,ok: bool) -> void:t.check("DAILY_SAVE",name,ok)
func saved(slot: String="current") -> Dictionary:
	for entry: Dictionary in SaveDB.load_candidates():
		if entry.slot==slot:return entry.data
	return {}
func notice(ok: bool,automatic: bool) -> void:events.append({"ok":ok,"automatic":automatic})
func run() -> void:
	var snapshot: Dictionary=GameState.to_dict().duplicate(true)
	var position: Vector3=main.player.global_position
	var in_room: bool=main.in_room;var room_kind: String=main.room_kind
	var region: String=main.world.region
	var old_instant: bool=main.ui.instant
	main.ui.instant=true;main.ui.dialogue_end();main.ui.close_modal()
	GameState.new_game();GameState.clock_paused=true
	GameState.coins=377;GameState.ledger={"in":27,"out":3};GameState.daily={"xp":12}
	GameState.plots.farm0.open=true;GameState.plots.farm0.tilled=true;GameState.plots.farm0.crop="radish";GameState.plots.farm0.days=0;GameState.plots.farm0.water=true;GameState.plots.farm0.boost=false
	if GameState.has_signal("save_finished"):GameState.connect("save_finished",notice)
	var listener:=func(_day: int):GameState.flags["daily_save_listener"]=true
	GameState.day_changed.connect(listener)
	GameState.call("advance_day")
	GameState.day_changed.disconnect(listener)
	var direct:=saved()
	check("every date rollover creates a real SQLite autosave",int(direct.get("day",0))==2 and int(direct.get("coins",0))==377)
	check("autosave contains settled crops and yesterday's ledger",not direct.is_empty() and int(direct.plots.farm0.days)==1 and int(direct.flags.last_ledger.get("in",0))==27 and int(direct.flags.last_ledger.get("xp",0))==12)
	check("day-change listeners finish before the snapshot is committed",not direct.is_empty() and direct.flags.get("daily_save_listener",false))
	GameState.day=6;GameState.minute=21*60;GameState.save_game();events.clear()
	await main.sleep_now()
	var bedroom:=saved()
	check("normal overnight rest saves the next morning's home position",not bedroom.is_empty() and int(bedroom.day)==7 and bedroom.player.in_room and bedroom.region=="town" and Vector3(bedroom.player.x,bedroom.player.y,bedroom.player.z).distance_to(HouseBuilder.ORIGIN+Vector3(-4.6,.05,-.6))<.02)
	check("overnight rest writes once and retains the previous day",int(saved("previous").get("day",0))==6 and events.size()==1 and events[0].automatic and events[0].ok)
	GameState.day=8;GameState.minute=GameState.DAY_END;main.world.set_region("farm");GameState.player_region="farm";main.in_room=false;main.player.global_position=FarmBuilder.ORIGIN+Vector3(94,.2,44)
	GameState.save_game();events.clear()
	await main._on_late_night()
	var midnight:=saved()
	check("midnight from the lake saves tomorrow at home",not midnight.is_empty() and int(midnight.day)==9 and midnight.player.in_room and midnight.region=="town" and int(midnight.minute)==GameState.WAKE_MIN and int(saved("previous").get("day",0))==8)
	var old_database: String=SaveDB.database_path;var old_backup: String=SaveDB.backup_path
	var blocked: String=SaveDB.directory.path_join("blocked-daily.db")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked))
	SaveDB.database_path=blocked;SaveDB.backup_path=SaveDB.directory.path_join("missing-daily-test-backup.db")
	events.clear();GameState.call("advance_day")
	var failure: bool=not GameState.last_error.is_empty() and events.size()==1 and not events[0].ok and events[0].automatic
	SaveDB.database_path=old_database;SaveDB.backup_path=old_backup
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
	check("failed autosave keeps the committed snapshot and reports failure",failure and int(saved().get("day",0))==9)
	events.clear();GameState.save_game()
	check("manual saves retain a distinct successful notification",events.size()==1 and events[0].ok and not events[0].automatic)
	if GameState.has_signal("save_finished"):GameState.disconnect("save_finished",notice)
	GameState.from_dict(snapshot);main.player.global_position=position;main.in_room=in_room;main.room_kind=room_kind;main.world.set_region(region);main.ui.instant=old_instant
