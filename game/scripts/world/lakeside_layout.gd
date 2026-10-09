class_name LakesideLayout
extends RefCounted
## Shared physical coordinates for terrain, water, fishing and both maps.
const OLD_BOUNDS := Rect2(-30.0, -16.0, 58.0, 47.0)
const BOUNDS := Rect2(-30.0, -34.0, 172.0, 96.0)
const ORIGINAL_TOWN_BOUNDS := Rect2(-52.2, -25.2, 94.9, 57.4)
const TOWN_BOUNDS := Rect2(-52.2, -25.2, 94.9, 110.4)
const LAKE_CENTER := Vector2(101.0, 18.0)
const LAKE_RADII := Vector2(32.0, 23.0)
const WATER_Y := -0.28
const PATHS := [
	[Vector2(19, .3), Vector2(31, -1), Vector2(42, -9), Vector2(58, -12), Vector2(75, -15), Vector2(95, -13), Vector2(115, -11), Vector2(135, 0), Vector2(138, 19), Vector2(131, 40), Vector2(113, 51), Vector2(94, 48), Vector2(74, 43), Vector2(62, 35), Vector2(48, 32), Vector2(28, 26), Vector2(10, 25.4)],
	[Vector2(42, -9), Vector2(42, 5), Vector2(47, 15), Vector2(48, 19.5)],
	[Vector2(94, 48), Vector2(94, 45)],
]
const SPOTS := {
	"fish_river": {"species": ["fish_crucian", "fish_ayu"], "name": "晴川浅滩", "habitat": "river", "stand": Vector2(10.0, 12.0), "float": Vector2(10.8, 16.2)},
	"fish_bend": {"species": ["fish_trout", "fish_ayu", "fish_eel"], "name": "柳影河湾", "habitat": "river", "stand": Vector2(48.0, 19.4), "float": Vector2(50.0, 24.8)},
	"fish_pier": {"species": ["fish_carp", "fish_bass"], "name": "镜波湖栈桥", "habitat": "lake", "stand": Vector2(94.0, 37.7), "float": Vector2(94.5, 32.5)},
	"fish_reeds": {"species": ["fish_crucian", "fish_bass", "fish_eel"], "name": "芦苇东岸", "habitat": "lake", "stand": Vector2(136.8, 17.0), "float": Vector2(129.0, 17.5)},
}
const SUPPLIES := Vector2(24.0, 1.8)

static func river_z(x: float) -> float:
	var t := clampf((x - 28.0) / 46.0, 0.0, 1.0)
	var anchor: float = smoothstep(4.0,13.0,absf(x))
	var meander: float = (1.7*sin(x*.11)+.5*sin(x*.24-.6))*anchor*(1.0-smoothstep(28.0,48.0,x))
	return 17.0 + meander + 8.0 * sin(t * PI) * smoothstep(28.0, 40.0, x) + t

static func river_half(x: float) -> float:
	var anchor: float = smoothstep(4.0,13.0,absf(x))
	return 3.0 + .75 * sin(clampf((x - 28.0) / 46.0, 0.0, 1.0) * PI)+(.38*sin(x*.17)+.22*cos(x*.07))*anchor

static func lake_radius(angle: float) -> float:
	return 1.0 + .095 * sin(angle * 3.0) + .055 * cos(angle * 5.0) + .035 * sin(angle * 7.0)

static func water_depth_at(p: Vector2) -> float:
	var inward: float = maxf(0.0,-water_distance(p))
	var lake_weight: float = smoothstep(74.0,92.0,p.x)
	return .14+(1.05+1.25*lake_weight)*smoothstep(0.0,3.2+10.0*lake_weight,inward)

static func water_distance(p: Vector2) -> float:
	var q := (p - LAKE_CENTER) / LAKE_RADII
	var lake := (q.length() - lake_radius(q.angle())) * LAKE_RADII.y
	var river := absf(p.y - river_z(p.x)) - river_half(p.x)
	if p.x > 74.0:
		river = p.distance_to(Vector2(74.0, 18.0)) - 3.0
	return minf(lake, river)

static func height_at(p: Vector2) -> float:
	var water := water_distance(p)
	if water < 1.3:
		return WATER_Y-water_depth_at(p) if water < 0.0 else lerpf(WATER_Y-.14,0.0,smoothstep(0.0,1.3,water))
	var north := 3.2 * exp(-pow((p.x - 115.0) / 29.0, 2.0) - pow((p.y + 30.0) / 16.0, 2.0))
	var south := 1.7 * exp(-pow((p.x - 62.0) / 25.0, 2.0) - pow((p.y - 58.0) / 13.0, 2.0))
	return (north + south) * smoothstep(28.0, 48.0, p.x) * smoothstep(1.3, 9.0, water)

static func lake_outline(n: int = 96, outward: float = 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in n:
		var angle := TAU * float(i) / float(n)
		result.append(LAKE_CENTER + Vector2(cos(angle), sin(angle)) * (LAKE_RADII * lake_radius(angle) + Vector2.ONE * outward))
	return result

static func river_outline() -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in 57:
		var x := -36.0 + float(i) * 2.0
		result.append(Vector2(x, river_z(x) - river_half(x)))
	for i in range(56, -1, -1):
		var x := -36.0 + float(i) * 2.0
		result.append(Vector2(x, river_z(x) + river_half(x)))
	return result

static var _smooth_routes: Array[PackedVector2Array] = []

static func walk_paths() -> Array[PackedVector2Array]:
	if not _smooth_routes.is_empty():return _smooth_routes
	for route:Array in PATHS:
		var samples:=PackedVector2Array()
		for i in route.size()-1:
			var a:Vector2=route[maxi(0,i-1)]
			var b:Vector2=route[i]
			var c:Vector2=route[i+1]
			var d:Vector2=route[mini(route.size()-1,i+2)]
			for j in 6:
				var t:=float(j)/6.0
				samples.append(.5*((2.0*b)+(-a+c)*t+(2.0*a-5.0*b+4.0*c-d)*t*t+(-a+3.0*b-3.0*c+d)*t*t*t))
		samples.append(route[-1]);_smooth_routes.append(samples)
	return _smooth_routes

static func path_distance(p: Vector2) -> float:
	var result := INF
	for route: PackedVector2Array in walk_paths():
		for i in route.size() - 1:
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var t := clampf((p - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
			result = minf(result, p.distance_to(a.lerp(b, t)))
	return result

static func outdoors_area(rect: Rect2, old: bool = false) -> float:
	var count := 0
	for x in range(int(rect.position.x), int(rect.end.x)):
		for z in range(int(rect.position.y), int(rect.end.y)):
			var p := Vector2(x + .5, z + .5)
			if (absf(p.y - 17.0) > 4.3) if old else water_distance(p) > 1.3:
				count += 1
	return float(count)

static func expansion_ratio() -> float:
	return (TOWN_BOUNDS.get_area() + outdoors_area(BOUNDS)) / (ORIGINAL_TOWN_BOUNDS.get_area() + outdoors_area(OLD_BOUNDS, true))
