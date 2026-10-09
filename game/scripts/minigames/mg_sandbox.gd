extends Node
## Standalone runner for one mini-game (development, codex checks and tests).
##   $GODOT --headless --path game res://scenes/mg_sandbox.tscn -- --mg=<id> --selftest
##   $GODOT --path game res://scenes/mg_sandbox.tscn -- --mg=<id> [--auto] [--shots=/tmp/dir]
## --selftest prints every mg_self_test() check plus mg_simulate() at several skill levels and
## exits with code 1 if anything failed. Without it, the game runs through GameUI.play_minigame
## (a real round; --auto lets the demo AI play) and quits when the player leaves.

var _shots_dir := ""
var _shot_t := 0.0
var _shot_n := 0


func _ready() -> void:
	var id := ""
	var auto := false
	var selftest := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mg="):
			id = a.substr(5)
		elif a == "--auto":
			auto = true
		elif a == "--selftest":
			selftest = true
		elif a.begins_with("--shots="):
			_shots_dir = a.substr(8)
	if id == "" or not GameState.MINIGAMES.has(id):
		push_error("mg_sandbox: pass --mg=<id>")
		get_tree().quit(2)
		return
	var bg := CanvasLayer.new()
	bg.layer = -1
	var cr := ColorRect.new()
	cr.color = Color(0.55, 0.62, 0.5)
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(cr)
	add_child(bg)
	if selftest:
		await _selftest(id)
		return
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	var ui := GameUI.new()
	add_child(ui)
	ui.auto = auto
	Audio.game_on = true
	await get_tree().process_frame
	var res: Dictionary = await ui.play_minigame(id)
	print("MG RESULT ", JSON.stringify(res))
	Audio.silence()
	get_tree().quit(0)


func _process(delta: float) -> void:
	if _shots_dir == "":
		return
	_shot_t += delta
	if _shot_t >= 1.5:
		_shot_t = 0.0
		_shot_n += 1
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png("%s/%03d.png" % [_shots_dir, _shot_n])


func _selftest(id: String) -> void:
	var path := "res://scripts/minigames/mg_%s.gd" % id
	if not ResourceLoader.exists(path):
		print("FAIL script missing: ", path)
		get_tree().quit(1)
		return
	var holder := CanvasLayer.new()
	add_child(holder)
	var root := Control.new()
	root.theme = UITheme.make()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(root)
	var mg: MiniGame = load(path).new()
	mg.id = id
	root.add_child(mg)
	await get_tree().process_frame
	var fails := 0
	var checks: Array = mg.mg_self_test()
	for c in checks:
		var ok := bool(c[1])
		print("%s %s" % ["PASS" if ok else "FAIL", str(c[0])])
		if not ok:
			fails += 1
	if checks.size() < 6:
		print("FAIL fewer than 6 self-test checks (%d)" % checks.size())
		fails += 1
	var th: Array = mg.info.get("stars", [])
	var ok_th := th.size() == 3 and int(th[0]) > 0 and int(th[0]) < int(th[1]) and int(th[1]) < int(th[2])
	print("%s star thresholds %s" % ["PASS" if ok_th else "FAIL", str(th)])
	if not ok_th:
		fails += 1
	var prev := -1.0
	var mono := true
	for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var tot := 0.0
		for seed in range(1, 9):
			tot += mg.mg_simulate(s, seed)
		var avg := tot / 8.0
		var st := mg.stars_for(int(avg))
		print("SIM skill %.2f avg %.1f stars %d" % [s, avg, st])
		if avg + 0.001 < prev:
			mono = false
		prev = avg
	var s1 := mg.stars_for(mg.mg_simulate(1.0, 3))
	var s0 := mg.stars_for(mg.mg_simulate(0.0, 3))
	var a := mg.mg_simulate(0.6, 11)
	var b := mg.mg_simulate(0.6, 11)
	for pair in [["simulate skill 1.0 gives 3 stars", s1 == 3], ["simulate skill 0.0 gives 0 stars", s0 == 0],
			["simulate is deterministic", a == b], ["simulate average rises with skill", mono]]:
		print("%s %s" % ["PASS" if pair[1] else "FAIL", pair[0]])
		if not pair[1]:
			fails += 1
	print("SELFTEST %s %s (%d failed)" % [id, "ALL PASS" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
