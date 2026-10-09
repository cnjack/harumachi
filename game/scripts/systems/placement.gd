class_name PlacementSystem
extends Node3D
## Courtyard layout mode: overhead camera, 0.5 m grid, 90° rotation, red/green ghost with a
## written reason, no-go areas, undo, pick-up. All state changes go through GameState.

signal exited

const GRID := 0.5
static var project_context := ""

var ui: GameUI
var player: Player
var active := false
var cam := Camera3D.new()
var prev_cam: Camera3D
var placed_root := Node3D.new()
var placed_nodes := {}
var lantern_lights: Array[OmniLight3D] = []
var ghost: Node3D
var ghost_mat := ShaderMaterial.new()
var foot := MeshInstance3D.new()
var foot_mat := StandardMaterial3D.new()
var overlay := Node3D.new()
var item_id := ""
var rot := 0
var center := Vector2.ZERO
var valid := false
var session_uids: Array[int] = []
var _mouse := Vector2.ZERO


func _ready() -> void:
	placed_root.name = "Placed"
	add_child(placed_root)
	cam.fov = 48.0
	cam.far = 800.0
	add_child(cam)
	ghost_mat.shader = load("res://shaders/ghost.gdshader")
	foot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foot_mat.no_depth_test = true
	foot_mat.render_priority = 2
	var fm := PlaneMesh.new()
	fm.size = Vector2.ONE
	foot.mesh = fm
	foot.material_override = foot_mat
	foot.visible = false
	add_child(foot)
	_build_overlay()
	overlay.visible = false
	add_child(overlay)
	GameState.placements_changed.connect(rebuild)
	GameState.phase_changed.connect(func(_p): _update_lanterns())
	rebuild()


# ------------------------------------------------------------------ models for placeables
func make_item_model(id: String) -> Node3D:
	var it := GameState.item(id)
	var mid: String = it.get("model", id)
	if mid == "bunting":
		return _bunting()
	if id == "lantern":
		return _lantern_stand()
	var ps := WorldBuilder.model_scene(mid)
	if ps:
		var instance: Node3D=ps.instantiate()
		instance.set_meta("wind_model_id",mid)
		if WorldBuilder.SWAY.has(mid):WorldBuilder.make_sway(instance,WorldBuilder.SWAY[mid][0],WorldBuilder.SWAY[mid][1])
		return instance
	var n := Node3D.new()
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var fp: Array = it.get("footprint", [1, 1])
	bm.size = Vector3(fp[0] * 0.9, 0.8, fp[1] * 0.9)
	b.mesh = bm
	b.position.y = 0.4
	n.add_child(b)
	return n


func _wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.38, 0.24)
	m.roughness = 0.9
	return m


func _bunting() -> Node3D:
	var n := Node3D.new()
	var wood := _wood()
	for x in [-1.45, 1.45]:
		var p := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.045
		c.height = 2.5
		p.mesh = c
		p.material_override = wood
		p.position = Vector3(x, 1.25, 0)
		n.add_child(p)
	var cols := [Color(0.95, 0.42, 0.35), Color(0.98, 0.8, 0.3), Color(0.4, 0.7, 0.9), Color(0.5, 0.78, 0.45), Color(0.96, 0.6, 0.72)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 11
	for i in count:
		var t0 := float(i) / count
		var t1 := (i + 0.8) / count
		var x0 := lerpf(-1.4, 1.4, t0)
		var x1 := lerpf(-1.4, 1.4, t1)
		var sag := func(t: float) -> float: return 2.42 - 0.35 * sin(t * PI)
		var y0: float = sag.call(t0)
		var y1: float = sag.call(t1)
		var c: Color = cols[i % cols.size()]
		st.set_color(c.srgb_to_linear())
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(0,0))
		st.add_vertex(Vector3(x0, y0, 0))
		st.set_uv(Vector2(1,0))
		st.add_vertex(Vector3(x1, y1, 0))
		st.set_uv(Vector2(.5,1))
		st.add_vertex(Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0 - 0.3, 0))
	var flags := MeshInstance3D.new()
	flags.name="WindBunting"
	flags.mesh = st.commit()
	var fm := ShaderMaterial.new()
	fm.shader=load("res://shaders/bunting_flutter.gdshader")
	flags.material_override = fm
	n.add_child(flags)
	var rope := MeshInstance3D.new()
	var rm := ImmediateMesh.new()
	rm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 21:
		var t := i / 20.0
		rm.surface_add_vertex(Vector3(lerpf(-1.45, 1.45, t), 2.42 - 0.35 * sin(t * PI), 0))
	rm.surface_end()
	rope.mesh = rm
	var ropem := StandardMaterial3D.new()
	ropem.albedo_color = Color(0.9, 0.88, 0.8)
	ropem.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope.material_override = ropem
	n.add_child(rope)
	return n


func _lantern_stand() -> Node3D:
	var n := Node3D.new()
	var wood := _wood()
	var post := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.09, 2.0, 0.09)
	post.mesh = pb
	post.material_override = wood
	post.position = Vector3(0, 1.0, 0)
	n.add_child(post)
	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.07, 0.07, 0.5)
	arm.mesh = ab
	arm.material_override = wood
	arm.position = Vector3(0, 1.95, 0.22)
	n.add_child(arm)
	var base := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.4, 0.08, 0.4)
	base.mesh = bb
	base.material_override = wood
	base.position.y = 0.04
	n.add_child(base)
	var ps := WorldBuilder.model_scene("P_chochin_red")
	if ps:
		var l: Node3D = ps.instantiate()
		l.position = Vector3(0, 1.93, 0.4)
		l.scale = Vector3.ONE * 1.25
		n.add_child(l)
		var world:=get_parent().get("world") as WorldBuilder
		if world:world.swing.append([l,0.0,0.0])
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.36)
	light.omni_range = 5.0
	light.light_energy = 0.0
	light.position = Vector3(0, 1.62, 0.4)
	n.add_child(light)
	lantern_lights.append(light)
	return n


func _update_lanterns() -> void:
	var e := 1.8 if GameState.phase == "market" else 0.0
	for l in lantern_lights:
		if is_instance_valid(l):
			l.light_energy = e


static func footprint(id: String, r: int) -> Vector2:
	var fp: Array = GameState.item(id).get("footprint", [1.0, 1.0])
	return Vector2(fp[1], fp[0]) if r % 2 == 1 else Vector2(fp[0], fp[1])


func rebuild() -> void:
	for c in placed_root.get_children():
		c.queue_free()
	placed_nodes.clear()
	lantern_lights.clear()
	for p in GameState.placements:
		var n := make_item_model(p.item)
		n.position = Vector3(p.x, 0, p.z)
		n.rotation.y = deg_to_rad(90.0 * int(p.rot))
		placed_root.add_child(n)
		for mi in WorldBuilder.find_meshes(n):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if p.item=="bunting":
			for side_index: int in 2:
				var pole_body:=StaticBody3D.new();pole_body.name="BuntingSupport_%d"%side_index
				pole_body.collision_layer=WorldBuilder.L_PLACED;pole_body.set_meta("model_part","bunting_support")
				pole_body.position=Vector3(-1.45 if side_index==0 else 1.45,1.25,0)
				var pole_shape:=CollisionShape3D.new();var pole_box:=BoxShape3D.new();pole_box.size=Vector3(.11,2.5,.11)
				pole_shape.shape=pole_box;pole_body.add_child(pole_shape);n.add_child(pole_body)
			placed_nodes[int(p.uid)]=n
			continue
		var body := StaticBody3D.new()
		body.collision_layer = WorldBuilder.L_PLACED
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		var fp := footprint(p.item, 0)
		sh.size = Vector3(fp.x * 0.85, 1.0, fp.y * 0.85)
		cs.shape = sh
		cs.position.y = 0.5
		body.add_child(cs)
		n.add_child(body)
		placed_nodes[int(p.uid)] = n
	_update_lanterns()


# ------------------------------------------------------------------ overlay
func _build_overlay() -> void:
	var z: Array = zone()
	var grid := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(z[2] - z[0], z[3] - z[1])
	grid.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
uniform float cell = 0.5;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wp.xz / cell + 0.5) - 0.5) * cell;
	float line = 1.0 - smoothstep(0.0, 0.03, min(g.x, g.y));
	vec2 e = min(UV, 1.0 - UV) * vec2(12.5, 12.0);
	float edge = 1.0 - smoothstep(0.0, 0.06, min(e.x, e.y));
	ALBEDO = mix(vec3(1.0, 0.97, 0.85), vec3(1.0, 0.8, 0.35), edge);
	ALPHA = max(line * 0.35, edge * 0.9) + 0.06;
}
"""
	var gm := ShaderMaterial.new()
	gm.shader = sh
	grid.material_override = gm
	grid.position = Vector3((z[0] + z[2]) / 2.0, 0.03, (z[1] + z[3]) / 2.0)
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.add_child(grid)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.95, 0.3, 0.25, 0.35)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for r in Layout.NOGO_RECTS:
		var q := MeshInstance3D.new()
		var qm := PlaneMesh.new()
		var a: Array = r[0]
		qm.size = Vector2(a[2] - a[0], a[3] - a[1])
		q.mesh = qm
		q.material_override = red
		q.position = Vector3((a[0] + a[2]) / 2.0, 0.035, (a[1] + a[3]) / 2.0)
		overlay.add_child(q)
	for c in Layout.NOGO_CIRCLES:
		var q := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = c[1]
		cm.bottom_radius = c[1]
		cm.height = 0.01
		q.mesh = cm
		q.material_override = red
		q.position = Vector3(c[0].x, 0.035, c[0].y)
		overlay.add_child(q)


# ------------------------------------------------------------------ mode
func entries() -> Array:
	var out := []
	for id in GameState.inventory:
		if GameState.item(id).get("placeable", "") != "":
			out.append({"id": id, "n": int(GameState.inventory[id])})
	return out


func can_enter() -> bool:
	return (GameState.phase == "prep" or project_context == "space") and (not entries().is_empty() or not GameState.placements.is_empty())


func enter(project_id: String = "") -> void:
	if active: return
	project_context = project_id
	if not can_enter():
		return
	active = true
	_rebuild_overlay()
	Audio.ui("open")
	GameState.lock_input("placement")
	session_uids.clear()
	prev_cam = get_viewport().get_camera_3d()
	var z: Array = zone()
	var c := Vector3((z[0] + z[2]) / 2.0, 0, (z[1] + z[3]) / 2.0)
	cam.global_position = c + Vector3(0, 14.5, 12.5)
	cam.look_at(c + Vector3(0, 0, 0.6), Vector3.UP)
	cam.current = true
	overlay.visible = true
	var e := entries()
	item_id = e[0].id if not e.is_empty() else ""
	rot = 0
	ui.place_item_selected.connect(_select)
	_refresh_bar()
	_make_ghost()


func exit() -> void:
	if not active:
		return
	active = false
	Audio.ui("close")
	if ui.place_item_selected.is_connected(_select):
		ui.place_item_selected.disconnect(_select)
	if ghost:
		ghost.queue_free()
		ghost = null
	foot.visible = false
	overlay.visible = false
	if prev_cam:
		prev_cam.current = true
	ui.hide_placement()
	GameState.unlock_input("placement")
	project_context = ""
	_rebuild_overlay()
	GameState.save_game()
	exited.emit()


func _select(id: String) -> void:
	item_id = id
	_refresh_bar()
	_make_ghost()


func _refresh_bar() -> void:
	var e := entries()
	if not e.any(func(x): return x.id == item_id):
		item_id = e[0].id if not e.is_empty() else ""
		_make_ghost()
	ui.show_placement(e, item_id)


func _make_ghost() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
	if item_id == "":
		foot.visible = false
		return
	ghost = make_item_model(item_id)
	add_child(ghost)
	for mi in WorldBuilder.find_meshes(ghost):
		mi.material_override = ghost_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for l in ghost.find_children("*", "OmniLight3D", true, false):
		l.queue_free()
	foot.visible = true
	_update()


func _mouse_ground() -> Variant:
	var o := cam.project_ray_origin(_mouse)
	var d := cam.project_ray_normal(_mouse)
	if absf(d.y) < 1e-4:
		return null
	var t := -o.y / d.y
	if t < 0:
		return null
	var p := o + d * t
	return Vector2(p.x, p.z)


static func _snap_axis(v: float, size: float) -> float:
	var cells := int(round(size / GRID))
	if cells % 2 == 1:
		return floor(v / GRID) * GRID + GRID / 2.0
	return round(v / GRID) * GRID


## Returns "" when the rectangle may be used, otherwise a player-facing reason.
static func check_rect(c: Vector2, fp: Vector2, ignore_uid: int = -1, player_xz: Variant = null) -> String:
	var z: Array = zone()
	var r := Rect2(c - fp / 2.0, fp)
	var eps := 0.01
	if r.position.x < z[0] - eps or r.position.y < z[1] - eps or r.end.x > z[2] + eps or r.end.y > z[3] + eps:
		return "超出布置区域了（只能放在黄色格子里）"
	if project_context == "space":
		var space_reason: String = SummerSpace.check_footprint(c, fp)
		if space_reason != "": return space_reason
	for n in ([] if project_context == "space" else Layout.NOGO_RECTS):
		var a: Array = n[0]
		if r.grow(-eps).intersects(Rect2(a[0], a[1], a[2] - a[0], a[3] - a[1])):
			return n[1]
	for cc in Layout.NOGO_CIRCLES:
		var cp: Vector2 = cc[0]
		var q := Vector2(clampf(cp.x, r.position.x, r.end.x), clampf(cp.y, r.position.y, r.end.y))
		if q.distance_to(cp) < cc[1]:
			return cc[2]
	for p in GameState.placements:
		if int(p.uid) == ignore_uid:
			continue
		var pf := footprint(p.item, int(p.rot))
		var pr := Rect2(Vector2(p.x, p.z) - pf / 2.0, pf)
		if r.grow(-eps).intersects(pr):
			return "和已经摆好的%s重叠了" % GameState.item_name(p.item)
	if player_xz != null:
		var pp: Vector2 = player_xz
		var q2 := Vector2(clampf(pp.x, r.position.x, r.end.x), clampf(pp.y, r.position.y, r.end.y))
		if q2.distance_to(pp) < 0.45:
			return "你正站在这里，先挪开一点"
	return ""


func _update() -> void:
	if not active or item_id == "":
		return
	var m = _mouse_ground()
	if m == null:
		return
	var fp := footprint(item_id, rot)
	center = Vector2(_snap_axis(m.x, fp.x), _snap_axis(m.y, fp.y))
	var reason := check_rect(center, fp, -1, Vector2(player.global_position.x, player.global_position.z))
	valid = reason == ""
	if ghost:
		ghost.position = Vector3(center.x, 0.02, center.y)
		ghost.rotation.y = deg_to_rad(90.0 * rot)
	ghost_mat.set_shader_parameter("color", Color(0.35, 1.0, 0.5, 0.5) if valid else Color(1.0, 0.35, 0.3, 0.5))
	foot.position = Vector3(center.x, 0.05, center.y)
	foot.scale = Vector3(fp.x, 1, fp.y)
	foot_mat.albedo_color = Color(0.3, 0.9, 0.45, 0.4) if valid else Color(0.95, 0.3, 0.25, 0.45)
	ui.set_place_message(("可以放在这里：%s" % GameState.item_name(item_id)) if valid else reason, valid)


func hovered_uid() -> int:
	var m = _mouse_ground()
	if m == null:
		return -1
	for p in GameState.placements:
		var pf := footprint(p.item, int(p.rot))
		if Rect2(Vector2(p.x, p.z) - pf / 2.0, pf).has_point(m):
			return int(p.uid)
	return -1


func try_place() -> bool:
	if item_id == "" or not valid:
		return false
	var uid := GameState.add_placement(item_id, center.x, center.y, rot)
	if uid < 0:
		return false
	session_uids.append(uid)
	_refresh_bar()
	_update()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		_update()
		return
	var handled := true
	if event.is_action_pressed("click"):
		_mouse = (event as InputEventMouseButton).position
		_update()
		if not try_place() and item_id != "":
			Audio.ui("invalid")
			ui.set_place_message(check_rect(center, footprint(item_id, rot), -1, Vector2(player.global_position.x, player.global_position.z)), false)
	elif event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		exit()
	elif event.is_action_pressed("rotate_ccw"):
		rot = (rot + 3) % 4
		Audio.ui("rotate")
		_update()
	elif event.is_action_pressed("rotate_cw"):
		rot = (rot + 1) % 4
		Audio.ui("rotate")
		_update()
	elif event.is_action_pressed("undo"):
		if not session_uids.is_empty() and GameState.remove_placement(session_uids.pop_back()):
			GameState.toast.emit("撤销了上一次摆放")
			_refresh_bar()
			_update()
	elif event.is_action_pressed("pickup"):
		var u := hovered_uid()
		if u >= 0 and GameState.remove_placement(u):
			session_uids.erase(u)
			GameState.toast.emit("收回背包了")
			_refresh_bar()
			_update()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode >= KEY_1 and (event as InputEventKey).keycode <= KEY_5:
		var i := (event as InputEventKey).keycode - KEY_1
		var e := entries()
		if i < e.size():
			_select(e[i].id)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Used by autoplay/tests: place at explicit coordinates through the same rules.
func place_at(id: String, x: float, z: float, r: int) -> bool:
	var fp := footprint(id, r)
	var c := Vector2(_snap_axis(x, fp.x), _snap_axis(z, fp.y))
	if check_rect(c, fp) != "" or not GameState.has(id):
		return false
	item_id = id
	rot = r
	center = c
	valid = true
	var uid := GameState.add_placement(id, c.x, c.y, r)
	if uid >= 0:
		session_uids.append(uid)
		if active:
			_refresh_bar()
			_make_ghost()
	return uid >= 0

static func zone() -> Array:
	return SummerSpace.AREA if project_context == "space" else Layout.ZONE

func _rebuild_overlay() -> void:
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	_build_overlay()
