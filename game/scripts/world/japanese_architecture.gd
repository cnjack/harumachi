class_name JapaneseArchitecture
extends RefCounted
## Measured timber overlays and tiled courtyard coping. Existing door/keeper coordinates stay authoritative.
const COPING_PROFILE := [Vector2(-0.27,0.0),Vector2(-0.245,0.03),Vector2(-0.18,0.07),Vector2(-0.085,0.108),Vector2(-0.028,0.126),Vector2(0.0,0.13),Vector2(0.028,0.126),Vector2(0.085,0.108),Vector2(0.18,0.07),Vector2(0.245,0.03),Vector2(0.27,0.0)]
const COPING_LIFT := 0.025
static func coping_top(wall_height: float) -> float:
	var rise:=0.0
	for point: Vector2 in COPING_PROFILE:rise=maxf(rise,point.y)
	return wall_height+COPING_LIFT+rise


static func store_sidewalls(world: WorldBuilder, building: Node3D) -> void:
	# S01 ray measurements: ground-floor plaster sides x=+/-3.40, roof starts above 3 m.
	for side: float in [-1.0, 1.0]:
		var panel := world.spawn("P_store_sidepanel", Vector3(side * 3.445, 0.0, -0.08), side * 90.0, 0, building)
		if panel:
			panel.name = "SideJoinery_%s" % ("right" if side > 0.0 else "left")
			HouseBuilder.toonify(panel)


static func shop_frames(room: InteriorBuilder) -> void:
	var half_w: float = room.spec.size.x / 2.0
	var half_d: float = room.spec.size.y / 2.0
	for x: float in [-4.5, -2.7, 1.7, 3.5]:
		var frame := room.wb.spawn("P_shop_wall_frame", Vector3(x, 0.0, -half_d + 0.035), 0.0, 0, room)
		if frame:
			HouseBuilder.toonify(frame)
	for side: float in [-1.0, 1.0]:
		for z: float in [-2.7, -0.9, 0.9, 2.7]:
			var frame := room.wb.spawn("P_shop_wall_frame", Vector3(side * (half_w - 0.035), 0.0, z), -side * 90.0, 0, room)
			if frame:
				HouseBuilder.toonify(frame)


static func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	return m


static func courtyard_coping(wall: MeshInstance3D, length: float, height: float) -> void:
	var roof := MeshInstance3D.new()
	roof.name = "TileCoping"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Folded tiled cap: actual silhouette and projecting drip edges, not painted stripes.
	var profile: Array= COPING_PROFILE
	var n := ceili((length + 0.16) / 0.3)
	var start := -(length + 0.16) / 2.0
	var step_x := (length + 0.16) / n
	for i in n:
		var x0 := start + i * step_x
		var x1 := x0 + step_x - 0.006
		st.set_color(Color(0.23, 0.30, 0.41) * (0.97 if i % 3 == 0 else 1.0))
		for j in profile.size() - 1:
			var a := Vector3(x0, profile[j].y, profile[j].x)
			var b := Vector3(x1, profile[j].y, profile[j].x)
			var c := Vector3(x1, profile[j + 1].y, profile[j + 1].x)
			var d := Vector3(x0, profile[j + 1].y, profile[j + 1].x)
			for vertex: Vector3 in [a, c, b, a, d, c]:
				st.add_vertex(vertex)
	st.generate_normals()
	st.index()
	roof.mesh = st.commit()
	var mat := _flat(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	roof.material_override = mat
	roof.position.y = height / 2.0 + COPING_LIFT
	wall.add_child(roof)
	_tile_ends(wall,length,height)
	var pilaster_mat := _flat(Color(0.89, 0.86, 0.77))
	var count := ceili(length / 3.6)
	for i in count + 1:
		var post := MeshInstance3D.new()
		post.name = "PlasterPier_%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, height, 0.29)
		post.mesh = mesh
		post.material_override = pilaster_mat
		post.position.x = -length / 2.0 + length * float(i) / count
		wall.add_child(post)

static func _tile_ends(wall: MeshInstance3D,length: float,height: float) -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:=ceili((length+.16)/.3);var pitch: float=(length+.16)/count
	for index in count:
		var x: float=-(length+.16)*.5+(index+.5)*pitch
		for side in [-1.0,1.0]:
			var centre:=Vector3(x,height*.5+.026,side*.272)
			for segment in 12:
				var a:=TAU*float(segment)/12;var b:=TAU*float(segment+1)/12
				st.set_color(Color(.31,.39,.49));st.set_normal(Vector3(0,0,side))
				for point: Vector3 in [centre,centre+Vector3(cos(a)*.034,sin(a)*.034,0),centre+Vector3(cos(b)*.034,sin(b)*.034,0)]:st.add_vertex(point)
			for dot in 4:
				var at:=centre+Vector3(cos(dot*PI*.5)*.015,sin(dot*PI*.5)*.015,side*.001)
				st.set_color(Color(.12,.19,.27))
				for point: Vector3 in [at+Vector3(-.005,-.005,0),at+Vector3(.005,-.005,0),at+Vector3(0,.005,0)]:st.add_vertex(point)
	var caps:=MeshInstance3D.new();caps.name="CopingTileEndRosettes";caps.mesh=st.commit()
	var material:=_flat(Color.WHITE);material.vertex_color_use_as_albedo=true;material.cull_mode=BaseMaterial3D.CULL_DISABLED;caps.material_override=material
	wall.add_child(caps)
	wall.set_meta("detailed_coping",true)
