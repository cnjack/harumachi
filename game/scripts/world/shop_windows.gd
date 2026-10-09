class_name ShopWindows
extends RefCounted
## Real thin glass in front of actual display rooms and individual 3D products.
##
## Rectangles are in the building's local frame (x right along the front, y up) and were measured
## from ray-cast depth maps of each model; z is inside the retained facade frame.
## The pane contains only glass; ShopDisplays builds the real room behind it.
## [x0, x1, y0, y1, z, room]

const WINDOWS := {
	"S01": [[-2.1, 2.22, 0.72, 2.16, 2.782, "store"]],
	"S02": [[-1.44, 0.145, 0.87, 2.29, 3.327, "bakery"], [0.61, 1.15, 1.08, 2.08, 2.944, "bakery"]],
	"S03": [[-2.23, -1.49, 1.1, 1.94, 3.041, "florist"], [0.03, 2.52, 0.24, 1.83, 3.74, "florist"]],
	"S05": [[-1.83, 0.39, 1.04, 2.58, 3.746, "post"]],
	"S08": [[-2.01, 0.39, 0.22, 2.18, 3.065, "zakka"], [0.57, 2.69, 0.91, 2.17, 3.012, "zakka"]],
}

static var _shader: Shader


## Adds the window quads to a spawned building; returns their materials (WorldBuilder drives `lamp`).
static func add(building: Node3D, id: String, world: WorldBuilder) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if not WINDOWS.has(id):
		return out
	if _shader == null:
		_shader = load("res://shaders/shop_glass.gdshader")
	var display_light := ShopDisplays.build(building, id, world)
	for wi in (WINDOWS[id] as Array).size():
		var w: Array = WINDOWS[id][wi]
		var x0: float = w[0]
		var x1: float = w[1]
		var y0: float = w[2]
		var y1: float = w[3]
		var room: String = w[5]
		var q := QuadMesh.new()
		q.size = Vector2(x1 - x0, y1 - y0)
		q.center_offset = Vector3((x1 - x0) / 2.0, (y1 - y0) / 2.0, 0.0)
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_meta("display_light", weakref(display_light))
		m.set_shader_parameter("lamp", .42)
		var mi := MeshInstance3D.new()
		mi.name = "ShopWindow_%s_%d" % [room, wi]
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(x0, y0, w[4])
		building.add_child(mi)
		out.append(m)
	return out


## Interior light for the time of day: dim by day (the street is brighter than the shop), lamps on
## in the evening, warm and bright at night. `lamp` is WorldBuilder's street-lamp level (0..2).
static func light(mats: Array[ShaderMaterial], street_lamp: float, sky: Color) -> void:
	var k := 0.42 + 0.42 * clampf(street_lamp / 1.6, 0.0, 1.0)
	for m in mats:
		m.set_shader_parameter("lamp", k)
		m.set_shader_parameter("sky_col", sky)
		var light_ref := m.get_meta("display_light", null) as WeakRef
		if light_ref:
			var light := light_ref.get_ref() as OmniLight3D
			if light:
				light.light_energy = .40 + street_lamp*.65
