class_name AmbientLife
extends Node3D
## Small life around the player: sparrow flocks that hop and peck and take off when you come
## close, cats (one asleep, one who turns to watch you), butterflies around flowers and
## dragonflies over the river. Everything is cheap procedural motion on static models.

const SPARROW_SPOTS := [
	["town",Vector3(19.7,0,56.0)],["town",Vector3(-1.0,0,69.0)],
	["town", Vector3(-8.8, 0, 11.0)], ["town", Vector3(6.2, 0, 19.6)], ["town", Vector3(-30.0, 0, -9.0)],
	["town", Vector3(26.0, 0, 16.0)], ["farm", Vector3(-1.0, 0, -0.6)], ["farm", Vector3(-17.0, 0, 3.0)],
]
const BUTTERFLY_SPOTS := [
	["town",Vector3(24.0,.8,46.0)],["town",Vector3(14.5,.8,62.0)],
	["town", Vector3(11.0, 0.8, 19.8)], ["town", Vector3(-11.4, 0.8, -3.2)], ["town", Vector3(-12.0, 0.8, 12.6)],
	["farm", Vector3(-4.0, 0.8, 12.0)], ["farm", Vector3(5.0, 0.8, 20.8)], ["farm", Vector3(1.5, 0.7, -5.5)],
]
const DRAGONFLY_SPOTS := [
	["farm", Vector3(-6.0, 1.2, 16.8)], ["farm", Vector3(6.5, 1.3, 17.2)], ["farm", Vector3(0.0, 1.5, -4.8)],
	["town", Vector3(-8.0, 1.6, 17.0)],
]

var wb: WorldBuilder
var player: Node3D
var flocks: Array = []
var flyers: Array = []
var cats: Array = []
const CAT_WALKER=preload("res://scripts/animals/cat_walker.gd")
var roaming_cats: Array[CharacterBody3D] = []
var _flap_cool := 0.0
var world_seed := -1


func setup(world: WorldBuilder, p: Node3D) -> void:
	wb = world
	player = p
	add_to_group("save_hooks")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameState.flags.get("world_seed", 5))
	for s in SPARROW_SPOTS:
		var home: Vector3 = s[1] + (FarmBuilder.ORIGIN if s[0] == "farm" else Vector3.ZERO)
		var birds := []
		for i in rng.randi_range(3, 5):
			var b := wb.spawn("A21_sparrow", home, rng.randf() * 360.0, 0, self, 1.0)
			if b == null:
				continue
			for mi in WorldBuilder.find_meshes(b):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var off := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
			b.set_meta("support_base_y", WorldBuilder.local_aabb(b).position.y)
			b.visible = false
			b.position = home + off
			birds.append({"node": b, "off": off, "t": rng.randf() * 1.5, "hop": 0.0, "from": b.position, "to": b.position, "vel": Vector3.ZERO, "anim": AnimalMotion.new(b,0), "peck":0.0})
		flocks.append({"region": s[0], "home": home, "birds": birds, "state": "ground", "timer": 0.0, "rng": _entity_rng("flock", flocks.size())})
	for s in BUTTERFLY_SPOTS:
		for i in 2:
			flyers.append(_butterfly(s[0], s[1] + (FarmBuilder.ORIGIN if s[0] == "farm" else Vector3.ZERO), rng))
	for s in DRAGONFLY_SPOTS:
		for i in 2:
			flyers.append(_dragonfly(s[0], s[1] + (FarmBuilder.ORIGIN if s[0] == "farm" else Vector3.ZERO), rng))
	# cats: the calico naps on the courtyard's low front wall, the tabby watches the lane from a wall top,
	# and another calico sleeps on the bench by the allotment gate
	for c in [["A20_cat_sleep", Vector3(12.6, 0.7, -5.42), 200.0, "sleep"], ["A22_cat_sit", Vector3(22.2, 1.2, 10.6), -90.0, "watch"],
			["A20_cat_sleep", FarmBuilder.ORIGIN + Vector3(-16.4, 0.46, -1.74), 90.0, "sleep"]]:
		var n := wb.spawn(c[0], c[1], c[2], 0, self, 1.0)
		if n:
			var support_y: float=(c[1] as Vector3).y
			if (c[1] as Vector3).x<200 and str(c[3])=="sleep":support_y=JapaneseArchitecture.coping_top(.7)
			elif (c[1] as Vector3).x>200:
				for bench: Node3D in wb.farm.find_children("*","Node3D",true,false):
					if bench.get_meta("model_id","")!="A12_bench" or bench.global_position.distance_to(n.global_position)>2.0:continue
					var seat:=WorldBuilder.surface_height(bench,Vector2(n.global_position.x,n.global_position.z),support_y+.30)
					if is_finite(seat):support_y=seat;break
			if (c[1] as Vector3).x<200:
				var wall: Node3D=wb.get_node("BoundaryWall_5/TileCoping" if str(c[3])=="sleep" else "BoundaryWall_8/TileCoping")
				var actual:=WorldBuilder.surface_height(wall,Vector2(n.global_position.x,n.global_position.z),2.0)
				if is_finite(actual):support_y=actual
			WorldBuilder.rest_on(n,support_y,-.003)
			n.name="AmbientCat_%d"%cats.size()
			var target:=Interactable.new();target.name="CatInteract_%d"%cats.size();target.id="ambient_cat_%d"%cats.size();target.radius=1.9
			target.position=n.position+Vector3(0,.34,0)
			if n.global_position.x<200:
				var owner_wall: Node=wb.get_node("BoundaryWall_5" if str(c[3])=="sleep" else "BoundaryWall_8")
				var bodies:=owner_wall.find_children("*","StaticBody3D",true,false)
				if not bodies.is_empty():target.body=bodies[0] as CollisionObject3D
			add_child(target)
			cats.append({"node": n, "mode": c[3], "yaw": deg_to_rad(c[2]), "t": rng.randf() * 5.0, "head":0.0, "anim":AnimalMotion.new(n,2 if str(c[3])=="sleep" else 1)})
	# New standing cats roam the open middle of the residential lane.
	for index: int in range(2):
		var model_id: String="AN_cat_orange_walk" if index==0 else "AN_cat_calico_walk"
		if not ResourceLoader.exists("res://assets/models/%s.glb"%model_id):continue
		var walker: CharacterBody3D=CAT_WALKER.new() as CharacterBody3D
		walker.name="RoamingCat_%d"%index
		walker.set_meta("audit_category", "animal")
		walker.set_meta("model_part","roaming_cat_body")
		walker.collision_layer=WorldBuilder.L_ACTORS
		walker.collision_mask=WorldBuilder.L_GROUND|WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
		add_child(walker)
		var collider: CollisionShape3D=CollisionShape3D.new()
		collider.name="RoamingCatCollider_%d"%index
		collider.set_meta("model_part","cat_body")
		var shape: BoxShape3D=BoxShape3D.new()
		shape.size=Vector3(.16,.24,.24)
		collider.shape=shape
		collider.position.y=.12
		walker.add_child(collider)
		var visual: Node3D=wb.spawn(model_id,Vector3(0,.009,0),0,0,walker)
		HouseBuilder.toonify(visual)
		var lane_z: float=55.0 if index==0 else 69.0
		walker.setup(visual,PackedVector3Array([Vector3(19.2,0,lane_z-.6),Vector3(20.4,0,lane_z-.6),Vector3(20.4,0,lane_z+.6),Vector3(19.2,0,lane_z+.6)]),.12)
		walker.attention.set("nearby_target", player)
		roaming_cats.append(walker)
	_sync_animal_seed()

func _entity_rng(kind: String, index: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = abs(hash("%s:%d:%d" % [kind, int(GameState.flags.get("world_seed", 5)), index]))
	return generator

func _sync_animal_seed(force: bool = false) -> void:
	var seed_value: int = int(GameState.flags.get("world_seed", 5))
	if world_seed == seed_value and not force: return
	world_seed = seed_value
	var snapshot: Dictionary = GameState.flags.get("animal_life", {})
	var saved: Dictionary = snapshot.get("cats", {})
	for index: int in roaming_cats.size():
		var walker: CharacterBody3D = roaming_cats[index]
		walker.reset_behaviour(abs(hash("cat:%d:%d" % [seed_value, index])), saved.get(str(index), {}))
	for index: int in flocks.size():
		var flock: Dictionary = flocks[index]
		flock.rng = _entity_rng("flock", index)
		var stored: Dictionary = snapshot.get("flocks", {}).get(str(index), {})
		if int(snapshot.get("world_seed", -1)) == seed_value and not stored.is_empty():
			flock.state = str(stored.state); flock.timer = float(stored.timer)
			flock.rng.state = str(stored.rng_state).to_int()
			for bird_index: int in mini(flock.birds.size(), stored.birds.size()):
				var bird: Dictionary = flock.birds[bird_index]; var data: Dictionary = stored.birds[bird_index]
				bird.node.position = _from_array(data.position)
				for field: String in ["from", "to", "vel", "off"]:
					if data.has(field): bird[field] = _from_array(data[field])
				for field: String in ["t", "hop", "peck"]: bird[field] = float(data[field])
				bird["grounded"] = bool(data.get("grounded", false)); bird["retry"] = float(data.get("retry", 0.0))
				bird.node.rotation.y = float(data.yaw)
	for index: int in flyers.size():
		var flyer: Dictionary = flyers[index]; flyer.rng = _entity_rng("flyer", index)
		var stored: Dictionary = snapshot.get("flyers", {}).get(str(index), {})
		if int(snapshot.get("world_seed", -1)) == seed_value and not stored.is_empty():
			flyer.node.position = _from_array(stored.position); flyer.target = _from_array(stored.target)
			for field: String in ["t", "hold", "dash"]:
				if flyer.has(field) and stored.has(field): flyer[field] = float(stored[field])
			flyer.rng.state = str(stored.rng_state).to_int()

func _array(at: Vector3) -> Array: return [at.x, at.y, at.z]
func _from_array(at: Array) -> Vector3: return Vector3(float(at[0]), float(at[1]), float(at[2]))

func before_save() -> void:
	_sync_animal_seed()
	var states: Dictionary = {}
	for index: int in roaming_cats.size(): states[str(index)] = roaming_cats[index].snapshot()
	var flock_states: Dictionary = {}
	for index: int in flocks.size():
		var flock: Dictionary = flocks[index]; var birds: Array = []
		for bird: Dictionary in flock.birds:
			birds.append({"position": _array(bird.node.position), "from": _array(bird.from), "to": _array(bird.to),
				"vel": _array(bird.vel), "off": _array(bird.off), "t": float(bird.t), "hop": float(bird.hop), "peck": float(bird.peck), "yaw": bird.node.rotation.y,
				"grounded": bool(bird.get("grounded", false)), "retry": float(bird.get("retry", 0.0))})
		flock_states[str(index)] = {"state": str(flock.state), "timer": float(flock.timer), "rng_state": str(flock.rng.state), "birds": birds}
	var flyer_states: Dictionary = {}
	for index: int in flyers.size():
		var flyer: Dictionary = flyers[index]
		var data: Dictionary = {"position": _array(flyer.node.position), "target": _array(flyer.target), "rng_state": str(flyer.rng.state)}
		for field: String in ["t", "hold", "dash"]:
			if flyer.has(field): data[field] = float(flyer[field])
		flyer_states[str(index)] = data
	GameState.flags["animal_life"] = {"version": 1, "world_seed": world_seed, "cats": states, "flocks": flock_states, "flyers": flyer_states}

func _air_bound(flyer: Dictionary, at: Vector3) -> Vector3:
	var home: Vector3 = flyer.home
	var span: float = 2.5 if flyer.kind == "butterfly" else 3.2
	return Vector3(clampf(at.x, home.x-span, home.x+span), clampf(at.y, home.y-.4, home.y+.75), clampf(at.z, home.z-span, home.z+span))

func _move_air(node: Node3D, at: Vector3) -> bool:
	var query: PhysicsShapeQueryParameters3D = _air_query(node,at)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	if node.visible:
		query.transform.origin -= at-node.global_position; query.motion = at - node.global_position
		var cast: PackedFloat32Array = space.cast_motion(query)
		if cast.size() == 2 and cast[0] < .999: return false
	node.position = at
	return true

func _air_query(node: Node3D,at: Vector3) -> PhysicsShapeQueryParameters3D:
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=SphereShape3D.new();shape.radius=.075
	query.shape=shape;query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
	var offset:=Vector3.ZERO
	if node.has_meta("model_id"):
		var bounds: AABB=node.global_transform*WorldBuilder.local_aabb(node)
		offset=Vector3(bounds.get_center().x,bounds.position.y+minf(.075,bounds.size.y*.45),bounds.get_center().z)-node.global_position
	query.transform=Transform3D(Basis.IDENTITY,at+offset)
	return query

func _air_clear(node: Node3D,at: Vector3) -> bool:
	return get_world_3d().direct_space_state.intersect_shape(_air_query(node,at),1).is_empty()

func _prepare_flyer(fl: Dictionary) -> bool:
	var node: Node3D=fl.node
	if _air_clear(node,node.global_position):return true
	node.hide()
	for attempt: int in 16:
		var candidate: Vector3=_air_bound(fl,fl.home+Vector3(fl.rng.randf_range(-1.6,1.6),fl.rng.randf_range(.15,.7),fl.rng.randf_range(-1.6,1.6)))
		if _move_air(node,candidate):
			fl.target=candidate;node.set_meta("motion_reason","animal_entry_relocated");return true
	return false

func _landing(node: Node3D, at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP*2.0, at - Vector3.UP*3.0, WorldBuilder.L_GROUND)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return Vector3.INF
	var point: Vector3 = hit.position
	point.y -= float(node.get_meta("support_base_y", 0.0))
	return point


func pet_cat(index: int) -> void:
	if index<0 or index>=cats.size():return
	Audio.sfx("cat_meow",-4.0,1.03 if index==0 else .96)
	GameState.flags["ambient_cat_pets"]=int(GameState.flags.get("ambient_cat_pets",0))+1
	var cat: Dictionary=cats[index];cat.head=.22
	(cat.anim as AnimalMotion).phase=0.0


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	return m


func _wing(size: Vector2, mat: Material, offset: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = offset
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _butterfly(region: String, home: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	root.name = "Butterfly_%d" % flyers.size(); root.set_meta("audit_category", "animal")
	root.hide()
	add_child(root)
	var col: Color = [Color(0.98, 0.97, 0.9), Color(1.0, 0.88, 0.35), Color(0.98, 0.97, 0.9), Color(0.6, 0.75, 1.0)][rng.randi() % 4]
	var m := _mat(col)
	var l := _wing(Vector2(0.07, 0.06), m, Vector3(-0.035, 0, 0))
	var r := _wing(Vector2(0.07, 0.06), m, Vector3(0.035, 0, 0))
	root.add_child(l)
	root.add_child(r)
	root.position = home
	return {"kind": "butterfly", "region": region, "node": root, "l": l, "r": r, "home": home, "target": home,
		"t": rng.randf() * 10.0, "speed": rng.randf_range(0.6, 0.9), "rate": rng.randf_range(9.0, 12.0), "rng": _entity_rng("flyer", flyers.size())}


func _dragonfly(region: String, home: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	root.name = "Dragonfly_%d" % flyers.size(); root.set_meta("audit_category", "animal")
	root.hide()
	add_child(root)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006
	cm.bottom_radius = 0.01
	cm.height = 0.1
	body.mesh = cm
	body.rotation.x = PI / 2.0
	body.material_override = _mat(Color(0.85, 0.22, 0.12) if rng.randf() < 0.6 else Color(0.2, 0.45, 0.7))
	root.add_child(body)
	var wm := _mat(Color(0.9, 0.95, 1.0, 0.45))
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var wings := []
	for z in [0.012, -0.004]:
		for side in [-1.0, 1.0]:
			var w := _wing(Vector2(0.07, 0.016), wm, Vector3(0.035 * side, 0, 0))
			w.position.z = z
			root.add_child(w)
			wings.append(w)
	root.position = home
	return {"kind": "dragonfly", "region": region, "node": root, "wings": wings, "home": home, "target": home,
		"t": rng.randf() * 10.0, "hold": 0.0, "dash": 0.0, "rng": _entity_rng("flyer", flyers.size())}


func _active_region() -> String:
	return wb.region if not wb.indoor else "house"


func _process(delta: float) -> void:
	_sync_animal_seed()
	var G := GameState
	var reg := _active_region()
	var h := G.hour()
	var daylight := h >= 5.5 and h < 19.3 and G.weather != "rain"
	var bugs := h >= 7.0 and h < 17.5 and G.weather == "sunny"
	for walker: CharacterBody3D in roaming_cats:
		var active: bool=reg=="town" and daylight
		walker.visible=active and not walker.waiting_for_spawn
		walker.collision_layer=WorldBuilder.L_ACTORS if walker.visible else 0
		walker.set_physics_process(active)
		walker.player.active=active
	var pp := player.global_position
	_flap_cool -= delta
	for f in flocks:
		var show: bool = f.region == reg and daylight
		for b in f.birds:
			if show and b.get("grounded",false) and not _air_clear(b.node,b.node.global_position):
				b["grounded"]=false;b.node.hide();b.retry=0.0
			if show and f.state == "ground" and not b.get("grounded", false):
				b["retry"] = maxf(0.0, float(b.get("retry", 0.0))-delta)
				if b.retry <= 0.0:
					for attempt: int in 8:
						var offset: Vector3 = b.off if attempt == 0 else Vector3(f.rng.randf_range(-1.2,1.2), 0, f.rng.randf_range(-1.2,1.2))
						var landing: Vector3 = _landing(b.node, f.home + offset)
						if landing.is_finite() and _move_air(b.node, landing):
							b.off = landing - f.home; b.from = landing; b.to = landing; b["grounded"] = true; break
					b.retry = 1.5
			(b.node as Node3D).visible = show and f.state != "gone" and (f.state != "ground" or bool(b.get("grounded", false))) and _air_clear(b.node,b.node.global_position)
		if not show:
			continue
		_update_flock(f, delta, pp)
	for fl in flyers:
		var n: Node3D = fl.node
		var on: bool = fl.region == reg and (bugs if fl.kind == "butterfly" else (daylight and h >= 9.0))
		n.visible = on and _prepare_flyer(fl)
		if on and n.global_position.distance_to(pp) < 40.0:
			_update_flyer(fl, delta)
	for c in cats:
		var n: Node3D = c.node
		c.t += delta
		var d: Vector3 = pp - n.global_position
		var want:=0.0
		if c.mode!="sleep" and Vector2(d.x,d.z).length()<7:
			want=clampf(wrapf(atan2(d.x,d.z)-float(c.yaw),-PI,PI),-.6,.6)
		c.head=lerpf(float(c.head),want,1.0-exp(-3.0*delta))
		(c.anim as AnimalMotion).update(delta,false,0.0,float(c.head))



func _update_flock(f: Dictionary, delta: float, pp: Vector3) -> void:
	var rng: RandomNumberGenerator = f.rng
	var home: Vector3 = f.home
	var dist := Vector2(pp.x - home.x, pp.z - home.z).length()
	for bird: Dictionary in f.birds:
		(bird.anim as AnimalMotion).update(delta,f.state in ["fly","return"],float(bird.peck))
		bird.peck=move_toward(float(bird.peck),0.0,delta*5.0)
	match f.state:
		"ground":
			if dist < 3.0:
				f.state = "fly"
				f.timer = 0.0
				if _flap_cool <= 0.0:
					_flap_cool = 1.0
					Audio.fx("flap", -6.0)
				for b in f.birds:
					var away: Vector3 = (b.node.global_position - pp)
					away.y = 0
					away = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
					b.vel = away * rng.randf_range(3.5, 5.0) + Vector3(0, rng.randf_range(2.5, 3.5), 0)
				return
			for b in f.birds:
				var n: Node3D = b.node
				if not b.get("grounded", false): continue
				b.t -= delta
				if b.hop > 0.0:
					b.hop = maxf(b.hop - delta * 3.2, 0.0)
					var k: float = 1.0 - b.hop
					if not _move_air(n, (b.from as Vector3).lerp(b.to, k) + Vector3(0, sin(k * PI) * 0.06, 0)): b.hop = 0.0
				elif b.t <= 0.0:
					b.t = rng.randf_range(0.5, 1.8)
					if rng.randf() < 0.6:
						var goal: Vector3 = home + b.off + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
						if goal.distance_to(home) > 1.6:
							goal = home + b.off * 0.5
						goal = _landing(n, goal)
						if not goal.is_finite(): continue
						var clear_neighbours := true
						for other: Dictionary in f.birds:
							if other.node != n and other.node.position.distance_to(goal) < .16: clear_neighbours = false
						if not clear_neighbours: continue
						b.from = n.position
						b.to = goal
						b.hop = 1.0
						n.rotation.y = atan2(goal.x - n.position.x, goal.z - n.position.z)
					else:
						b.peck = 1.0   # head peck, with grounded feet
				else:
					n.rotation.x = lerpf(n.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
		"fly":
			f.timer += delta
			for b in f.birds:
				var n: Node3D = b.node
				b.vel.y -= 1.2 * delta
				_move_air(n, n.position + b.vel * delta)
				n.rotation.y = atan2(b.vel.x, b.vel.z)
				n.rotation.x = -0.3
				n.rotation.z = sin(f.timer * 3.0) * 0.04
			if f.timer > 2.5:
				f.state = "gone"
				f.timer = rng.randf_range(18.0, 35.0)
		"gone":
			f.timer -= delta
			if f.timer <= 0.0 and dist > 9.0:
				f.state = "return";f.timer=0.0
				for b in f.birds:
					var n: Node3D = b.node
					b["grounded"]=false;n.hide()
					var landing: Vector3 = _landing(n, home + b.off)
					if not landing.is_finite(): f.state = "gone"; f.timer = 4.0; continue
					b.to = landing
					n.position = landing + Vector3(0, 2.0, 0)
					n.rotation = Vector3(0, rng.randf() * TAU, 0)
					b.hop = 0.0
		"return":
			f.timer+=delta
			for b: Dictionary in f.birds:
				var bird: Node3D=b.node
				_move_air(bird, b.to + Vector3(0, maxf(0.0, 2.0-f.timer*1.5), 0))
				bird.rotation.x=0.0
			if f.timer>=1.34:
				for b: Dictionary in f.birds:
					var bird: Node3D=b.node
					var landing: Vector3=_landing(bird,bird.global_position)
					b["grounded"]=landing.is_finite() and bird.global_position.distance_to(b.to)<.03 and bird.global_position.distance_to(landing)<.004 and _air_clear(bird,bird.global_position)
					if not b.grounded:bird.hide();b.retry=0.0
				f.state="ground"



func _update_flyer(fl: Dictionary, delta: float) -> void:
	var rng: RandomNumberGenerator = fl.rng
	var n: Node3D = fl.node
	fl.t += delta
	if fl.kind == "butterfly":
		var flap := sin(fl.t * fl.rate) * 1.1
		(fl.l as Node3D).rotation.z = flap
		(fl.r as Node3D).rotation.z = -flap
		var to: Vector3 = fl.target - n.position
		if to.length() < 0.2:
			fl.target = fl.home + Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(-0.4, 0.7), rng.randf_range(-2.2, 2.2))
		var v: Vector3 = to.normalized() * fl.speed + Vector3(sin(fl.t * 2.3) * 0.35, sin(fl.t * 3.1) * 0.45, cos(fl.t * 1.9) * 0.35)
		_flyer_step(fl,_air_bound(fl,n.position+v*delta),delta)
		n.rotation.y = lerp_angle(n.rotation.y, atan2(v.x, v.z), 1.0 - exp(-5.0 * delta))
	else:
		for i in fl.wings.size():
			(fl.wings[i] as Node3D).rotation.z = sin(fl.t * 55.0 + i) * 0.5
		if fl.hold > 0.0:
			fl.hold -= delta
			_move_air(n, _air_bound(fl, n.position + Vector3(0, sin(fl.t * 4.0) * .002, 0)))
			if fl.hold <= 0.0:
				fl.target = fl.home + Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-0.4, 0.5), rng.randf_range(-3.0, 3.0))
		else:
			var to: Vector3 = fl.target - n.position
			if to.length() < 0.1:
				fl.hold = rng.randf_range(0.6, 2.2)
			else:
				_flyer_step(fl,_air_bound(fl,n.position+to.normalized()*minf(to.length(),4.5*delta)),delta)
				n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), 1.0 - exp(-12.0 * delta))

func _flyer_step(fl: Dictionary,at: Vector3,delta: float) -> void:
	if _move_air(fl.node,at):fl["blocked_time"]=0.0;return
	fl["blocked_time"]=float(fl.get("blocked_time",0))+delta
	if float(fl.blocked_time)<.8:return
	fl.blocked_time=0.0
	for attempt: int in 12:
		var candidate: Vector3=_air_bound(fl,fl.home+Vector3(fl.rng.randf_range(-2,2),fl.rng.randf_range(-.3,.7),fl.rng.randf_range(-2,2)))
		if _air_clear(fl.node,candidate):fl.target=candidate;return
	fl.target=fl.node.position
