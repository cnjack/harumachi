extends Node
## Browser controls and observable save feedback; no server account or shared save slot.

var _save_callback: JavaScriptObject
var _last_available := false


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	var window := JavaScriptBridge.get_interface("window")
	_save_callback = JavaScriptBridge.create_callback(_save_from_browser)
	window.harumachiSave = _save_callback
	GameState.save_finished.connect(_save_result)
	_sync_saved_state()

func _save_result(ok: bool,automatic: bool) -> void:
	_sync_saved_state()
	var message: String=("一天结束，已自动保存。" if automatic else "进度已保存在这个浏览器。") if ok else GameState.last_error
	JavaScriptBridge.eval("document.getElementById('save-status').textContent = %s; document.body.dataset.saveResult = %s; document.body.dataset.saveReason = %s; document.body.dataset.gameDay = %s;"%[JSON.stringify(message),JSON.stringify("saved" if ok else "error"),JSON.stringify("daily" if automatic else "manual"),JSON.stringify(str(GameState.day))])


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	var available: bool = scene != null and scene.get_script() != null and scene.get_script().resource_path == "res://scripts/world/main.gd" and bool(scene.get("loading_ready"))
	if available == _last_available:
		return
	_last_available = available
	JavaScriptBridge.eval("document.getElementById('web-save').disabled = %s; document.body.dataset.worldReady = %s;" % ["false" if available else "true", JSON.stringify(str(available))])
	if available:
		_sync_saved_state()


func _sync_saved_state() -> void:
	JavaScriptBridge.eval("document.body.dataset.hasSave = %s; document.body.dataset.saveStore = 'sqlite'; document.body.dataset.gameDay = %s;" % [JSON.stringify(str(GameState.has_save())),JSON.stringify(str(GameState.day))])


func _save_from_browser(_arguments: Array) -> void:
	if not _last_available or Loading.active:
		return
	Loading.begin("保存晴町的进度", false)
	await get_tree().process_frame
	var ok := GameState.save_game()
	Loading.finish()
	_sync_saved_state()
