extends RefCounted
## Shared settings regression. Persistence uses a fresh child of the caller's isolated save directory.

var t: Object

func _init(runner: Object) -> void:
	t = runner

func check(label: String, passed: bool) -> void:
	t.check("VOICE_DEFAULT", label, passed)

func run() -> void:
	var isolated: String = OS.get_environment("HARUMACHI_SAVE_DIR")
	var explicit_test_db: bool = Array(OS.get_cmdline_user_args()).any(func(arg: String) -> bool: return arg.begins_with("--test-db="))
	if isolated.is_empty() and not explicit_test_db:
		check("voice settings checks require an explicitly isolated save directory", false)
		return
	var state: Node = GameState
	var audio: Node = Audio
	var store: Node = SaveDB
	var saved_state: Dictionary = state.to_dict().duplicate(true)
	var saved_settings: Dictionary = state.settings.duplicate(true)
	var saved_internal: Dictionary = {}
	for key: String in ["_last_min", "calendar_pending_save", "has_player_pos", "last_error", "_ui_locks", "_fishing_ticket"]:
		var value: Variant = state.get(key)
		saved_internal[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	var saved_context: String = PlacementSystem.project_context
	var saved_store: Dictionary = {"directory": store.directory, "database_path": store.database_path, "backup_path": store.backup_path}
	var saved_audio: Dictionary = {"voice": audio.get("_voice_vol"), "music": audio.get("_music_vol")}
	var saved_buses: Array[Dictionary] = []
	for index: int in AudioServer.bus_count:
		saved_buses.append({"index": index, "volume": AudioServer.get_bus_volume_db(index), "mute": AudioServer.is_bus_mute(index)})
	var settings_directory: String = str(store.directory).path_join("voice-default-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(settings_directory))
	store.directory = settings_directory
	store.database_path = settings_directory.path_join("voice.db")
	store.backup_path = settings_directory.path_join("voice.backup.db")
	# Construct the actual initializer without _ready, so earlier suite settings cannot alter defaults.
	var fresh: Node = (load("res://scripts/autoload/game_state.gd") as Script).new()
	var defaults: Dictionary = fresh.settings.duplicate(true)
	fresh.free()
	check("a new profile defaults to silent character voices", is_zero_approx(float(defaults.vol_voice)))
	check("default music and effects remain audible", float(defaults.vol_music) > 0 and float(defaults.vol_sfx) > 0)
	audio.apply_volumes({})
	check("missing legacy voice volume falls back to silent", AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")))
	state.settings = defaults
	state.settings.vol_voice = 0.65
	state.settings.vol_music = 0.31
	state.save_settings()
	state.settings.vol_voice = 0.0
	state.load_settings()
	check("an explicit saved voice choice survives loading", is_equal_approx(float(state.settings.vol_voice), 0.65) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")))
	state.new_game()
	check("starting a new game preserves the explicit voice choice", is_equal_approx(float(state.settings.vol_voice), 0.65))
	check("other saved volumes retain their choices", is_equal_approx(float(state.settings.vol_music), 0.31))
	state.settings.vol_voice = 0.0
	state.save_settings()
	state.settings.vol_voice = 0.65
	state.load_settings()
	check("an explicit zero persists and mutes the voice bus", is_zero_approx(float(state.settings.vol_voice)) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")))
	check("muted dialogue has no voice duration or music ducking", is_zero_approx(float(audio.voice("ren", "今天的第一炉是菠萝包。你闻到了吗？整条街都是黄油味。"))) and not audio.voice_playing())
	state.from_dict(saved_state)
	state.settings = saved_settings
	for key: String in saved_internal: state.set(key, saved_internal[key])
	PlacementSystem.project_context = saved_context
	for key: String in saved_store: store.set(key, saved_store[key])
	audio.set("_voice_vol", saved_audio.voice)
	audio.set("_music_vol", saved_audio.music)
	for bus: Dictionary in saved_buses:
		AudioServer.set_bus_volume_db(int(bus.index), float(bus.volume))
		AudioServer.set_bus_mute(int(bus.index), bool(bus.mute))
	await state.get_tree().process_frame
