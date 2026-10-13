extends SceneTree
## Standalone, isolated-save entry for the physical prop lifecycle regression.
var main: Node
var results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for frame: int in count: await process_frame

func check(group: String, label: String, ok: bool, detail: String = "") -> void:
	results.append({"case": group, "name": label, "ok": ok, "detail": detail})
	print(("PASS " if ok else "FAIL ") + label + (" " + detail if not detail.is_empty() else ""))

func _run() -> void:
	assert(not OS.get_environment("HARUMACHI_SAVE_DIR").is_empty(), "An isolated save directory is required")
	var state: Node = root.get_node("GameState")
	state.new_game(); state.clock_paused = true
	var npc: GDScript = load("res://scripts/npc/npc.gd")
	npc.roam_enabled = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main); main.ui.instant = true
	await frames(10)
	await load("res://scripts/tests/props_lifecycle_checks.gd").new(self).run()
	var failed: int = results.filter(func(row: Dictionary) -> bool: return not row.ok).size()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE).store_string(JSON.stringify({"total": results.size(), "failed": failed, "results": results}, "\t"))
	print("PROPS_LIFECYCLE total=%d failed=%d" % [results.size(), failed])
	main.queue_free(); await process_frame
	quit(0 if failed == 0 else 1)
