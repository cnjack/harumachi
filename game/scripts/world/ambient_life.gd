class_name AmbientLife
extends Node3D
## Small life around the player: sparrow flocks that hop and peck and take off when you come
## close, two rigged street cats, butterflies around flowers and
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
const GOLDFISH_LIFE = preload("res://scripts/animals/goldfish_life.gd")
const INSECT_ART = preload("res://scripts/animals/insect_art.gd")
var _flap_cool := 0.0
var world_seed := -1
var _air_shape := SphereShape3D.new()
var _air_params := PhysicsShapeQueryParameters3D.new()


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
	# One cat keeps to the lane shoulder by home; the other lives down South Town.
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
		# The southern stone lane is rendered 12 mm above its broad ground collider.
		# Keep the soles on that visible surface without lifting the physics body.
		var visual: Node3D=wb.spawn(model_id,Vector3(0,.021 if index==0 else .009,0),0,0,walker)
		HouseBuilder.toonify(visual)
		var route: PackedVector3Array = PackedVector3Array([Vector3(20.65,0,14.3),Vector3(21.35,0,14.3),Vector3(21.35,0,17.3),Vector3(20.65,0,17.3)]) if index==0 else PackedVector3Array([Vector3(19.2,0,68.4),Vector3(20.4,0,68.4),Vector3(20.4,0,69.6),Vector3(19.2,0,69.6)])
		walker.setup(visual,route,.36)
		walker.attention.set("nearby_target", player)
		roaming_cats.append(walker)
		var target := Interactable.new()
		target.name = "CatInteract_%d" % index
		target.id = "ambient_cat_%d" % index
		target.radius = 1.9
		target.body = walker
		target.position = walker.position + Vector3(0, .3, 0)
		add_child(target)
		cats.append({"node": walker, "interact": target, "region": "town"})
	var bowl: Node3D = wb.house.goldfish
	if bowl != null and bowl.get_node_or_null("GoldfishLife") == null:
		var fish_life: Node3D = GOLDFISH_LIFE.new() as Node3D
		fish_life.name = "GoldfishLife"
		bowl.add_child(fish_life)
		fish_life.setup(bowl)
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
	_air_shape.radius=.075
	_air_params.shape=_air_shape
	_air_params.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
	_air_params.motion=Vector3.ZERO
	var offset:=Vector3.ZERO
	if node.has_meta("model_id"):
		var bounds: AABB=node.global_transform*WorldBuilder.local_aabb(node)
		offset=Vector3(bounds.get_center().x,bounds.position.y+minf(.075,bounds.size.y*.45),bounds.get_center().z)-node.global_position
	_air_params.transform=Transform3D(Basis.IDENTITY,at+offset)
	return _air_params

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
	if GameState.weather == "rain" or not (cats[index].node as Node3D).is_visible_in_tree(): return
	Audio.sfx("cat_meow",-4.0,1.03 if index==0 else .96)
	GameState.flags["ambient_cat_pets"]=int(GameState.flags.get("ambient_cat_pets",0))+1
	var walker: CharacterBody3D = cats[index].node
	if not walker.is_visible_in_tree(): return
	# The physical cat stays where it is and briefly looks up before resuming its route.
	walker.rest_left = maxf(walker.rest_left, 1.2)
	walker.rest_pose = "Idle"
	walker.pose_left = 0.0
	walker.attention.set("attention_time", 10.0)


func _butterfly(region: String, home: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	root.name = "Butterfly_%d" % flyers.size(); root.set_meta("audit_category", "animal")
	root.hide()
	add_child(root)
	var col: Color = [Color(0.98, 0.97, 0.9), Color(1.0, 0.88, 0.35), Color(0.98, 0.97, 0.9), Color(0.6, 0.75, 1.0)][rng.randi() % 4]
	var l: MeshInstance3D = INSECT_ART.butterfly_wing(-1.0,col)
	var r: MeshInstance3D = INSECT_ART.butterfly_wing(1.0,col)
	root.add_child(l)
	root.add_child(r)
	INSECT_ART.butterfly_body(root)
	root.position = home
	return {"kind": "butterfly", "region": region, "node": root, "l": l, "r": r, "home": home, "target": home,
		"t": rng.randf() * 10.0, "speed": rng.randf_range(0.6, 0.9), "rate": rng.randf_range(9.0, 12.0), "rng": _entity_rng("flyer", flyers.size())}


func _dragonfly(region: String, home: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	root.name = "Dragonfly_%d" % flyers.size(); root.set_meta("audit_category", "animal")
	root.hide()
	add_child(root)
	var body_color: Color = Color(0.85, 0.22, 0.12) if rng.randf() < 0.6 else Color(0.2, 0.45, 0.7)
	INSECT_ART.dragonfly_body(root,body_color)
	var wings := []
	for z in [0.012, -0.004]:
		for side in [-1.0, 1.0]:
			var w: MeshInstance3D = INSECT_ART.dragonfly_wing(side)
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
		# Weather and time change the activity, never the animal's presence or position.
		var present: bool = reg == "town" and not walker.waiting_for_spawn
		var active: bool = reg == "town" and daylight
		walker.visible = present
		walker.collision_layer = WorldBuilder.L_ACTORS if present else 0
		walker.set_roaming(active, present)
	var pp := player.global_position
	_flap_cool -= delta
	for f in flocks:
		var show: bool = f.region == reg and daylight
		for b in f.birds:
			var was_shown: bool=bool(b.get("was_shown",false))
			b["clear_t"]=float(b.get("clear_t",0.0))-delta
			if show and (float(b.clear_t)<=0.0 or not was_shown):
				b["clear_t"]=0.12+f.rng.randf()*0.08
				b["clear_ok"]=_air_clear(b.node,b.node.global_position)
			if show and b.get("grounded",false) and not bool(b.get("clear_ok",true)):
				b["grounded"]=false;b.node.hide();b.retry=0.0
			if show and f.state == "ground" and not b.get("grounded", false):
				b["retry"] = maxf(0.0, float(b.get("retry", 0.0))-delta)
				if b.retry <= 0.0:
					for attempt: int in 8:
						var offset: Vector3 = b.off if attempt == 0 else Vector3(f.rng.randf_range(-1.2,1.2), 0, f.rng.randf_range(-1.2,1.2))
						var landing: Vector3 = _landing(b.node, f.home + offset)
						if landing.is_finite() and _move_air(b.node, landing):
							b.off = landing - f.home; b.from = landing; b.to = landing; b["grounded"] = true; b["clear_ok"]=true; break
					b.retry = 1.5
			(b.node as Node3D).visible = show and f.state != "gone" and (f.state != "ground" or bool(b.get("grounded", false))) and bool(b.get("clear_ok",true))
			b["was_shown"]=show
		if not show:
			continue
		_update_flock(f, delta, pp)
	for fl in flyers:
		var n: Node3D = fl.node
		var on: bool = fl.region == reg and (bugs if fl.kind == "butterfly" else (daylight and h >= 9.0))
		var was_on: bool=bool(fl.get("was_on",false))
		fl["was_on"]=on
		if on:
			fl["clear_t"]=float(fl.get("clear_t",0.0))-delta
			if not was_on or float(fl.clear_t)<=0.0:
				fl["clear_t"]=0.15+fl.rng.randf()*0.1
				fl["clear_ok"]=_prepare_flyer(fl)
			n.visible=bool(fl.get("clear_ok",false))
		else:
			n.visible=false
			fl["clear_ok"]=false
		if on and n.visible and n.global_position.distance_to(pp) < 40.0:
			_update_flyer(fl, delta)
	for entry: Dictionary in cats:
		var walker: CharacterBody3D = entry.node
		var target: Interactable = entry.interact
		var can_pet: bool = walker.visible and G.weather != "rain"
		target.global_position = walker.global_position + Vector3(0, .3, 0)
		target.visible = can_pet
		target.radius = 1.9 if can_pet else 0.0
		target.body = walker if can_pet else null



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
				var horizontal_speed: float = Vector2(b.vel.x, b.vel.z).length()
				var flight_tilt: float = clampf(1.22 - atan2(b.vel.y, horizontal_speed), .3, 1.4)
				n.rotation.x = lerpf(n.rotation.x, flight_tilt, 1.0 - exp(-8.0 * delta))
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
