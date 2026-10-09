extends SceneTree
func _initialize() -> void:
 var texture: Texture2D=load("res://ui_kit/assets/controls/camera.svg")
 var pixels: Image=texture.get_image()
 pixels.save_png("res://ui_kit/png/icon_camera.png")
 quit()
