extends Node3D
## A separate in-engine comparison stage. It never changes the playable street or a save.
## Godot --path game -t --position 3100,1990 res://scenes/architecture_review.tscn -- --out=/tmp/architecture-review

var world := WorldBuilder.new()
var camera := Camera3D.new()
var label := Label.new()
var target := Vector3(6.0, 3.0, 0.0)
var yaw := 30.0
var distance := 13.0
var height := 5.7


func _ready() -> void:
	GameState.clock_paused = true
	Audio.silence()
	add_child(world)
	world._build_environment()
	world.update_time(10.5 * 60.0, "sunny", true)
	world._plane([-30.0, -18.0, 30.0, 22.0], WorldBuilder.ground_material("stone"))
	var original := world.spawn("S01", Vector3(-6, 0, 0), 0.0, 0)
	ShopWindows.add(original, "S01", world)
	JapaneseArchitecture.store_sidewalls(world, original)
	var sample := world.spawn("J01_machiya", Vector3(6, 0, 0), 0.0, 0)
	HouseBuilder.toonify(sample)
	add_child(camera)
	camera.current = true
	camera.fov = 48.0
	camera.near = 0.1
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(label)
	label.theme = UITheme.make()
	label.position = Vector2(22, 18)
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", UITheme.INK)
	label.add_theme_color_override("font_outline_color", Color(0.98, 0.95, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	label.text = "町屋建筑样件 · Hyper3D\n方向键旋转，1 原商店 / 2 新町屋 / 3 对比"
	_move_camera()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			await _shots(argument.substr(6))
			get_tree().quit()
			return


func _move_camera() -> void:
	var angle := deg_to_rad(yaw)
	camera.global_position = target + Vector3(sin(angle) * distance, height - target.y, cos(angle) * distance)
	camera.look_at(target)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_LEFT: yaw -= 15.0
		KEY_RIGHT: yaw += 15.0
		KEY_UP: height = minf(12.0, height + 0.5)
		KEY_DOWN: height = maxf(2.0, height - 0.5)
		KEY_1: target.x = -6.0; distance = 13.0
		KEY_2: target.x = 6.0; distance = 13.0
		KEY_3: target.x = 0.0; distance = 24.0
		KEY_ESCAPE: get_tree().quit()
	_move_camera()


func _shots(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	label.hide()
	for shot: Array in [["machiya_front_right", 6.0, 30.0, 13.0], ["machiya_front", 6.0, 0.0, 13.0],
		["machiya_back", 6.0, 180.0, 13.0], ["machiya_left", 6.0, -70.0, 13.0], ["pair", 0.0, 15.0, 25.0]]:
		target.x = float(shot[1])
		yaw = float(shot[2])
		distance = float(shot[3])
		_move_camera()
		for frame in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(directory.path_join(str(shot[0]) + ".png"))
		print("ARCHITECTURE_SHOT ", shot[0])
