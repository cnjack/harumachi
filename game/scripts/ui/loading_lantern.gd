class_name LoadingLantern
extends Control

var elapsed := 0.0
var paper := UITheme.box(Color(0.93, 0.32, 0.23), Color(0.49, 0.22, 0.15), 3, 14, 0, false)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	var sway := sin(elapsed * 2.4) * 0.055
	draw_set_transform(Vector2(60, 14), sway)
	draw_line(Vector2.ZERO, Vector2(0, 27), UITheme.INK_SOFT, 2.0, true)
	draw_style_box(paper, Rect2(-24, 27, 48, 64))
	for x in [-14, -7, 0, 7, 14]:
		draw_line(Vector2(x, 34), Vector2(x, 84), Color(1.0, 0.77, 0.47, 0.7), 2.0, true)
	draw_line(Vector2(-18, 27), Vector2(18, 27), UITheme.INK_SOFT, 4.0, true)
	draw_line(Vector2(-18, 91), Vector2(18, 91), UITheme.INK_SOFT, 4.0, true)
	draw_line(Vector2(0, 92), Vector2(0, 107), UITheme.INK_SOFT, 2.0, true)
	draw_set_transform(Vector2.ZERO)
	for i in 3:
		var alpha := 0.3 + 0.6 * (sin(elapsed * 3.0 - float(i)) + 1.0) / 2.0
		draw_circle(Vector2(46 + i * 14, 128), 3.0, Color(0.65, 0.36, 0.2, alpha))
