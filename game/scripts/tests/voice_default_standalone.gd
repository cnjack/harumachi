extends SceneTree
## Run with HARUMACHI_SAVE_DIR set to a temporary directory; shared checks never quit a suite.

var results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(_case_id: String, label: String, passed: bool) -> void:
	results.append({"name": label, "passed": passed})

func _run() -> void:
	await load("res://scripts/tests/voice_default_checks.gd").new(self).run()
	var passed: bool = results.all(func(entry: Dictionary) -> bool: return bool(entry.passed))
	var output: String = OS.get_environment("HARUMACHI_SAVE_DIR").path_join("voice-default.json")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"passed": passed, "checks": results.size(), "results": results}, "\t"))
	print("VOICE_DEFAULT_CHECKS ", passed, " ", results)
	quit(0 if passed else 1)
