extends CanvasLayer
## Persistent loading feedback: scene resources, incremental construction and transitions.

var scene_busy := false
var active := false
var full_screen := true
var root := Control.new()
var background := ColorRect.new()
var box := VBoxContainer.new()
var caption: Label
var detail: Label
var bar := ProgressBar.new()
var _clock_was_paused := false


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.make()
	root.add_child(background)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.967, 0.943, 0.88, 1.0)
	root.add_child(box)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	var lantern_holder := CenterContainer.new()
	var lantern := LoadingLantern.new()
	lantern.custom_minimum_size = Vector2(120, 145)
	lantern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lantern_holder.add_child(lantern)
	box.add_child(lantern_holder)
	caption = UITheme.label("", 34)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	detail = UITheme.label("", 23, UITheme.INK_SOFT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(detail)
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UIKitStyles.progress())
	bar.add_theme_stylebox_override("fill", UIKitStyles.progress("fill"))
	box.add_child(bar)
	root.resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	root.hide()
	_layout()


func _layout() -> void:
	root.size = get_viewport().get_visible_rect().size
	box.size = Vector2(minf(680.0, root.size.x - 80.0), 270)
	box.position = (root.size - box.size) / 2.0 if full_screen else Vector2((root.size.x - box.size.x) / 2.0, root.size.y - 310.0)


func begin(text: String, entire_screen: bool = true) -> void:
	if not active:
		_clock_was_paused = GameState.clock_paused
	active = true
	full_screen = entire_screen
	GameState.clock_paused = true
	GameState.lock_input("loading")
	caption.text = text
	detail.text = "请稍候，晴町正在准备中。" if entire_screen else ""
	bar.hide()
	background.visible = entire_screen
	root.show()
	_layout()


func progress(text: String, value: float) -> void:
	caption.text = text
	bar.visible = value >= 0.0
	bar.value = clampf(value, 0.0, 1.0) * 100.0
	detail.text = "%d%%" % int(bar.value) if bar.visible else ""


func finish() -> void:
	root.hide()
	if active:
		GameState.clock_paused = _clock_was_paused
		GameState.unlock_input("loading")
	active = false


func change_scene(path: String, text: String = "准备晴町") -> void:
	if scene_busy:
		return
	scene_busy = true
	begin(text)
	await get_tree().process_frame
	await get_tree().process_frame
	if path == "res://scenes/main.tscn":
		var files := DirAccess.get_files_at("res://assets/models")
		var models: Array[String] = []
		for file in files:
			var model_file := file.trim_suffix(".remap")
			if model_file.ends_with(".glb") and not models.has(model_file):
				models.append(model_file)
		for i in models.size():
			WorldBuilder.model_scene(models[i].trim_suffix(".glb"))
			progress("准备晴町的街景", 0.7 * float(i + 1) / float(models.size()))
			if i % 2 == 0:
				await get_tree().process_frame
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		finish()
		scene_busy = false
		GameState.toast.emit("无法打开场景，请重试。")
		return
	await get_tree().scene_changed
	if path == "res://scenes/main.tscn":
		while not bool(get_tree().current_scene.get("loading_ready")):
			await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	finish()
	scene_busy = false
