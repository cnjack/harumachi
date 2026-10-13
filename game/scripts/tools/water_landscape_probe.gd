extends SceneTree
## Isolated targeted runner; intentionally runs on the old scene before implementation.
var main: Node
var results: Array[Dictionary]=[]
func _initialize() -> void:_start.call_deferred()
func _start() -> void:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():quit(2);return
	root.get_node("GameState").call("new_game")
	root.get_node("GameState").set("clock_paused",true)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	var warm: int=0
	while not bool(main.get("loading_ready")) and warm<1200:
		await process_frame;warm+=1
	await frames(4)
	await load("res://scripts/tests/water_landscape_checks.gd").new(self).run()
	var out: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out=arg.substr(6)
	var failures: int=0
	for row: Dictionary in results:
		if not bool(row.ok):failures+=1
	if not out.is_empty():FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"checks":results,"total":results.size(),"failed":failures},"\t"))
	root.get_node("Audio").call("silence");quit(0 if failures==0 else 1)
func check(group: String,label: String,ok: bool,detail: String="") -> void:
	results.append({"case":group,"name":label,"ok":ok,"detail":detail});print("PASS " if ok else "FAIL ",label," ",detail)
func frames(count: int) -> void:
	for frame: int in count:await process_frame
