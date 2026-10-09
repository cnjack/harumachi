class_name CircularMapButton
extends Button
func _has_point(point: Vector2) -> bool:
	return point.distance_to(size*.5)<minf(size.x,size.y)*.5-6
