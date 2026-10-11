extends SkeletonModifier3D
## Keep the existing gait and airborne swing, correcting only a shoe that crosses the floor.
## Original mesh/clip bytes are untouched; 26 cached extreme points per shoe replace a mesh scan.
var model: Node3D
var actor: Node3D
var animation: AnimationPlayer
var samples: Dictionary = {"L": [], "R": []}
var correction: Dictionary = {}
var enabled := true
var updates := 0
var total_usec := 0
var max_usec := 0
static var town_patches: Array[Dictionary] = []
static var town_curbs: Array[Dictionary] = []
# A sparse shoe envelope misses small curved/weighted edges by a few millimetres.
const FLOOR_MARGIN := .008

func performance() -> Dictionary:
	return {"updates": updates, "mean_usec": float(total_usec) / maxi(updates, 1), "max_usec": max_usec, "landmarks_L": (samples.L as Array).size(), "landmarks_R": (samples.R as Array).size()}

func reset_performance() -> void:
	updates = 0
	total_usec = 0
	max_usec = 0

static func attach(source: Node3D, player: AnimationPlayer) -> SkeletonModifier3D:
	var sk: Skeleton3D = source.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null: return null
	var support: SkeletonModifier3D = load("res://scripts/characters/character_foot_support.gd").new()
	support.name = "CharacterFootSupport"
	sk.add_child(support)
	support.call("prepare", source, player)
	return support

func prepare(source: Node3D, player: AnimationPlayer) -> void:
	model = source
	animation = player
	if town_patches.is_empty():
		for z: float in [Layout.STREET_Z - Layout.STREET_HALF, Layout.STREET_Z + Layout.STREET_HALF]:
			var curb: Dictionary = {"rect": Rect2(-52.2, z - .11, 94.9, .22), "height": .06, "feather": 0.0}
			town_curbs.append(curb)
			town_patches.append(curb)
		var material_b: bool = MaterialChoiceProfile.selection().get("grass", "A") == "B"
		for index: int in range(Layout.GROUND.size() - 1, -1, -1):
			var patch: Array = Layout.GROUND[index]
			var rectangle := Rect2(float(patch[1]), float(patch[2]), float(patch[3]) - float(patch[1]), float(patch[4]) - float(patch[2]))
			var centre: Vector2 = rectangle.get_center()
			var plaza_lawn: bool = patch[0] == "grass" and centre.x >= -13 and centre.x <= 17 and centre.y >= 10 and centre.y <= 24
			var feather: float = .82 if plaza_lawn else .35 if patch[0] == "grass" and not material_b else 0.0
			town_patches.append({"rect": rectangle, "height": .002 * index, "feather": feather, "second_frequency": 6.8 if material_b else 7.0, "first_weight": .65 if material_b else .6})
	actor = source
	while actor.get_parent() is Node3D and not (actor is Player or actor is NPC): actor = actor.get_parent() as Node3D
	var sk: Skeleton3D = get_skeleton()
	var candidates: Dictionary = {"L": [], "R": []}
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
		if mesh.skin == null: continue
		var binds: Array[int] = []
		var sides: Array[String] = []
		for index: int in mesh.skin.get_bind_count():
			var bone: int = mesh.skin.get_bind_bone(index)
			if bone < 0: bone = sk.find_bone(mesh.skin.get_bind_name(index))
			binds.append(bone)
			var label: String = sk.get_bone_name(bone) if bone >= 0 else ""
			sides.append("L" if label.contains("LeftFoot") or label.contains("LeftToe") or label in ["foot.L", "toe.L"] else "R" if label.contains("RightFoot") or label.contains("RightToe") or label in ["foot.R", "toe.R"] else "")
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty(): continue
			var influences: int = bones.size() / vertices.size()
			for vertex: int in vertices.size():
				var foot_weights: Dictionary = {"L": 0.0, "R": 0.0}
				for influence: int in influences:
					var bind: int = bones[vertex * influences + influence]
					if sides[bind] != "": foot_weights[sides[bind]] += weights[vertex * influences + influence]
				var side: String = "L" if float(foot_weights.L) > float(foot_weights.R) else "R"
				if float(foot_weights[side]) < .35: continue
				var chain: Array[Dictionary] = []
				for influence: int in influences:
					var weight: float = weights[vertex * influences + influence]
					if weight <= 0: continue
					var bind: int = bones[vertex * influences + influence]
					chain.append({"bone": binds[bind], "inverse_bind": mesh.skin.get_bind_pose(bind), "weight": weight})
				candidates[side].append({"position": vertices[vertex], "chain": chain})
	# Only startup reads the full original mesh. Runtime skins these directional extrema.
	for side: String in ["L", "R"]:
		var selected: Dictionary = {}
		for x: int in [-1, 0, 1]:
			for y: int in [-1, 0, 1]:
				for z: int in [-1, 0, 1]:
					if x == 0 and y == 0 and z == 0: continue
					var direction := Vector3(x, y, z).normalized()
					var best := -INF
					var best_index := -1
					for index: int in (candidates[side] as Array).size():
						var point: Vector3 = candidates[side][index].position
						var projection: float = point.dot(direction)
						if projection > best:
							best = projection
							best_index = index
					if best_index >= 0: selected[best_index] = true
		for index: int in selected: samples[side].append(candidates[side][index])

func points(sk: Skeleton3D, side: String) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var matrices: Dictionary = {}
	for sample: Dictionary in samples[side]:
		var point := Vector3.ZERO
		for influence: Dictionary in sample.chain:
			var bone: int = int(influence.bone)
			if not matrices.has(bone): matrices[bone] = sk.get_bone_global_pose(bone)
			var transform: Transform3D = (matrices[bone] as Transform3D) * (influence.inverse_bind as Transform3D)
			point += (transform * (sample.position as Vector3)) * float(influence.weight)
		result.append(sk.to_global(point))
	return result

func floor_below(ankle: Vector3) -> Dictionary:
	var from := Vector3(ankle.x, actor.global_position.y + .35, ankle.z)
	var to := Vector3(ankle.x, actor.global_position.y - .50, ankle.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, WorldBuilder.L_GROUND)
	return actor.get_world_3d().direct_space_state.intersect_ray(query)

static func shader_hash(point: Vector2) -> float:
	# The ground shader uses float32 dot/sin/product; round those stages before fract.
	var wave: float = PackedFloat32Array([sin(point.dot(Vector2(127.1, 311.7)))])[0]
	var value: float = PackedFloat32Array([wave * 43758.546875])[0]
	return value - floorf(value)

static func shader_noise(point: Vector2) -> float:
	var cell := Vector2(floorf(point.x), floorf(point.y))
	var fraction: Vector2 = point - cell
	fraction = fraction * fraction * (Vector2(3, 3) - fraction * 2)
	return lerpf(lerpf(shader_hash(cell), shader_hash(cell + Vector2.RIGHT), fraction.x), lerpf(shader_hash(cell + Vector2.DOWN), shader_hash(cell + Vector2.ONE), fraction.x), fraction.y)

static func visible_town_height(point: Vector2) -> float:
	# Rooms (z=400), farm (x=700), the exit slope and all higher physical supports keep their rays.
	if point.x < -52.2 or point.x > 42.7 or point.y < -25.2 or point.y > 85.2: return -INF
	for patch: Dictionary in town_patches:
		var rectangle: Rect2 = patch.rect
		if not rectangle.has_point(point): continue
		var feather: float = float(patch.feather)
		if feather > 0:
			var distance: float = minf(minf(point.x - rectangle.position.x, rectangle.end.x - point.x), minf(point.y - rectangle.position.y, rectangle.end.y - point.y))
			if distance < feather:
				var first_weight: float = float(patch.first_weight)
				var noise: float = shader_noise(point * 2.3) * first_weight + shader_noise(point * float(patch.second_frequency) + Vector2(3, 3)) * (1.0 - first_weight)
				if distance < feather * noise: continue
		return float(patch.height)
	return -INF

func rise_required(sk: Skeleton3D, side: String, floor: Dictionary) -> float:
	var normal: Vector3 = floor.normal
	if normal.y < .5: return 0.0
	var shoe_points: Array[Vector3] = points(sk, side)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for shoe_point: Vector3 in shoe_points:
		minimum = Vector2(minf(minimum.x, shoe_point.x), minf(minimum.y, shoe_point.z))
		maximum = Vector2(maxf(maximum.x, shoe_point.x), maxf(maximum.y, shoe_point.z))
	var footprint := Rect2(minimum, maximum - minimum).grow(.002)
	var curb_top := -INF
	# A narrow curb can pass through the sole between the sparse outer landmarks.
	# Use the shoe's projected envelope, keeping feet already above the step untouched.
	for curb: Dictionary in town_curbs:
		if footprint.intersects(curb.rect): curb_top = maxf(curb_top, float(curb.height))
	var required := 0.0
	for point: Vector3 in shoe_points:
		var gap: float = normal.dot(point - (floor.position as Vector3)) / normal.y
		var painted_height: float = visible_town_height(Vector2(point.x, point.z))
		if is_finite(painted_height): gap = minf(gap, point.y - painted_height)
		if is_finite(curb_top): gap = minf(gap, point.y - curb_top)
		required = maxf(required, FLOOR_MARGIN - gap)
	return required

func aim(sk: Skeleton3D, joint: int, end: int, toward: Vector3) -> void:
	var pose: Transform3D = sk.get_bone_global_pose(joint)
	var current: Vector3 = sk.get_bone_global_pose(end).origin - pose.origin
	if current.length_squared() < .000001 or toward.length_squared() < .000001: return
	pose.basis = Basis(Quaternion(current.normalized(), toward.normalized())) * pose.basis
	sk.set_bone_global_pose(joint, pose)

func lift_ankle(sk: Skeleton3D, side: String, rise: float) -> void:
	var thigh: int = LivingPose.bone(sk, "thigh." + side)
	var shin: int = LivingPose.bone(sk, "shin." + side)
	var foot: int = LivingPose.bone(sk, "foot." + side)
	if thigh < 0 or shin < 0 or foot < 0: return
	var hip: Vector3 = sk.to_global(sk.get_bone_global_pose(thigh).origin)
	var knee: Vector3 = sk.to_global(sk.get_bone_global_pose(shin).origin)
	var ankle: Vector3 = sk.to_global(sk.get_bone_global_pose(foot).origin)
	var foot_basis: Basis = sk.get_bone_global_pose(foot).basis
	var upper: float = hip.distance_to(knee)
	var lower: float = knee.distance_to(ankle)
	if upper < .001 or lower < .001: return
	var target: Vector3 = ankle + Vector3.UP * minf(rise, .22)
	var direction: Vector3 = (target - hip).normalized()
	var distance: float = clampf(target.distance_to(hip), absf(upper - lower) + .0001, upper + lower - .0001)
	var along: float = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var bend: float = sqrt(maxf(0.0, upper * upper - along * along))
	var toward: Vector3 = knee - hip
	toward -= direction * toward.dot(direction)
	if toward.length_squared() < .000001:
		toward = model.global_basis.z
		toward -= direction * toward.dot(direction)
	var goal: Vector3 = hip + direction * along + toward.normalized() * bend
	aim(sk, thigh, shin, sk.global_basis.inverse() * (goal - hip))
	var placed_knee: Vector3 = sk.to_global(sk.get_bone_global_pose(shin).origin)
	aim(sk, shin, foot, sk.global_basis.inverse() * (target - placed_knee))
	var pose: Transform3D = sk.get_bone_global_pose(foot)
	pose.basis = foot_basis
	sk.set_bone_global_pose(foot, pose)

func _process_modification() -> void:
	correction.clear()
	if not enabled or model == null or not model.is_visible_in_tree() or animation == null: return
	if animation.current_animation not in ["idle", "walk", "run", "wave", "bow", "look", "stretch", "tend", "talk", "cheer", "dance"]: return
	# PublicSeatPose owns hips/legs/soles during seated idle and seated drinking.
	if actor is Player and (actor as Player).seated: return
	var began: int = Time.get_ticks_usec()
	var sk: Skeleton3D = get_skeleton()
	for side: String in ["L", "R"]:
		var foot: int = LivingPose.bone(sk, "foot." + side)
		if foot < 0 or (samples[side] as Array).is_empty(): continue
		var floor: Dictionary = floor_below(sk.to_global(sk.get_bone_global_pose(foot).origin))
		if floor.is_empty(): continue
		var total := 0.0
		for iteration: int in range(3):
			var rise: float = rise_required(sk, side, floor)
			if rise < .0002: break
			lift_ankle(sk, side, rise)
			total += rise
		correction[side] = total
	var elapsed: int = Time.get_ticks_usec() - began
	updates += 1
	total_usec += elapsed
	max_usec = maxi(max_usec, elapsed)
