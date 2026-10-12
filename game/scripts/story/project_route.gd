class_name ProjectRoute
extends RefCounted
## Project trials retain their courtyard boundary and revision, using the shared swept planner.
const ORIGIN := Vector2(-43.5,-15.5)
const CELL := .5
const SIZE := Vector2i(127,83)
const ROUTE=preload("res://scripts/npc/motion_route.gd")

static func query(world: Node3D,start: Vector3,finish: Vector3,excluded: Array[RID]=[],stamp: String="",circles: Array=[]) -> Dictionary:
 var revision: String=stamp if stamp!="" else SummerProjects.layout_fingerprint()
 var bounds:=Rect2(ORIGIN,Vector2(SIZE)*CELL)
 if not bounds.has_point(Vector2(start.x,start.z)) or not bounds.has_point(Vector2(finish.x,finish.z)):
  return {"ok":false,"reason":"试走只检查这片庭院，先到摊位附近再试。","revision":revision}
 var shape: CapsuleShape3D=ROUTE.capsule();shape.radius=.38
 var parameters:=PhysicsShapeQueryParameters3D.new();parameters.shape=shape;parameters.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED;parameters.exclude=excluded
 var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
 for point: Vector3 in [start,finish]:
  parameters.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.8)
  var occupied: bool=not space.intersect_shape(parameters,1).is_empty()
  for circle: Array in circles:
   if Vector2(point.x,point.z).distance_to(circle[0])<float(circle[1])+.38:occupied=true
  if occupied:return {"ok":false,"reason":"起点或取餐停点被挡住，给人留出一小片站立的位置。","revision":revision}
 var planned: Array[Vector3]=ROUTE.query_world(world,start,finish,excluded,circles,bounds)
 if planned.is_empty():return {"ok":false,"reason":"入口到取餐停点还没有连通，试着把挡路的桌椅收回或转一下。","revision":revision}
 var path: Array=[start];var length:=0.0;var last: Vector3=start
 for point: Vector3 in planned:
  path.append(point);length+=last.distance_to(point);last=point
 return {"ok":true,"revision":revision,"path":path,"length":length,"start":{"x":start.x,"z":start.z},"finish":{"x":finish.x,"z":finish.z},"planner":"lazy_capsule"}
