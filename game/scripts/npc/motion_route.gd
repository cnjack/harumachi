extends RefCounted
## Lazy local A*: exact capsule sweeps, then safe line-of-sight smoothing.
const CELL := .4
const MAX_EXPANSIONS := 4000
const DIRECTIONS: Array[Vector2i]=[Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]

static func capsule() -> CapsuleShape3D:
 var shape:=CapsuleShape3D.new();shape.radius=.33;shape.height=1.6
 return shape

static func _context(actor: Node3D,start: Vector3,circles: Array,mask_override: int=-1,excluded: Array[RID]=[],radius: float=.33,bounds: Rect2=Rect2()) -> Dictionary:
 var parameters:=PhysicsShapeQueryParameters3D.new();var shape: CapsuleShape3D=capsule();shape.radius=radius;parameters.shape=shape;parameters.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
 if actor is CharacterBody3D:parameters.collision_mask|=WorldBuilder.L_BLOCK
 if mask_override>=0:parameters.collision_mask=mask_override
 var body: CollisionObject3D=actor as CollisionObject3D
 if body==null and mask_override<0:body=actor.get("body") as CollisionObject3D
 var exclude: Array[RID]=excluded.duplicate()
 if body!=null:exclude.append(body.get_rid())
 parameters.exclude=exclude;parameters.transform=Transform3D(Basis.IDENTITY,start+Vector3.UP*.8)
 var space: PhysicsDirectSpaceState3D=actor.get_world_3d().direct_space_state
 var overlaps: Array[Dictionary]=space.intersect_shape(parameters,16)
 return {"parameters":parameters,"space":space,"mask":parameters.collision_mask,"exclude":exclude,"start":start,"circles":circles,"points":{},"edges":{},"point_queries":0,"sweeps":0,"overlaps":overlaps,"radius":radius,"bounds":bounds}

static func _circle_blocks(start: Vector3,finish: Vector3,circles: Array,radius: float=.33) -> bool:
 var a:=Vector2(start.x,start.z);var b:=Vector2(finish.x,finish.z);var segment: Vector2=b-a
 for circle: Array in circles:
  var centre: Vector2=circle[0];var fraction: float=clampf((centre-a).dot(segment)/maxf(segment.length_squared(),.000001),0.,1.)
  if (a+segment*fraction).distance_to(centre)<float(circle[1])+radius:return true
 return false

static func _segment(context: Dictionary,start: Vector3,finish: Vector3) -> bool:
 if _circle_blocks(start,finish,context.circles,float(context.radius)):return false
 var parameters: PhysicsShapeQueryParameters3D=context.parameters
 parameters.collision_mask=int(context.mask);parameters.exclude=context.exclude;parameters.transform=Transform3D(Basis.IDENTITY,start+Vector3.UP*.8);parameters.motion=finish-start
 if start.is_equal_approx(context.start):
  var exclude: Array[RID]=(context.exclude as Array[RID]).duplicate()
  for hit: Dictionary in context.overlaps:
   var collider: CollisionObject3D=hit.collider as CollisionObject3D
   if collider==null:continue
   if (collider.collision_layer&(WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_BLOCK))!=0:return false
   var away:=Vector2(start.x-collider.global_position.x,start.z-collider.global_position.z)
   var motion:=Vector2(finish.x-start.x,finish.z-start.z)
   if away.dot(motion)<=.000001:return false
   exclude.append(collider.get_rid())
  parameters.exclude=exclude
 context.sweeps=int(context.sweeps)+1
 var space: PhysicsDirectSpaceState3D=context.space
 var fraction: PackedFloat32Array=space.cast_motion(parameters)
 return fraction.size()==2 and fraction[0]>=.99999

static func clear_segment(actor: Node3D,start: Vector3,finish: Vector3) -> bool:
 return _segment(_context(actor,start,[]),start,finish)

static func _point(context: Dictionary,cell: Vector2i) -> Vector3:
 var start: Vector3=context.start
 return start+Vector3(float(cell.x)*CELL,0,float(cell.y)*CELL)

static func _free(context: Dictionary,cell: Vector2i) -> bool:
 var cached: Dictionary=context.points
 if cached.has(cell):return bool(cached[cell])
 var at: Vector3=_point(context,cell)
 var bounds: Rect2=context.bounds
 if bounds.has_area() and not bounds.has_point(Vector2(at.x,at.z)):
  cached[cell]=false;return false
 var parameters: PhysicsShapeQueryParameters3D=context.parameters
 parameters.motion=Vector3.ZERO;parameters.exclude=context.exclude;parameters.collision_mask=int(context.mask)
 if cell==Vector2i.ZERO:parameters.collision_mask&=~WorldBuilder.L_ACTORS
 parameters.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.8)
 context.point_queries=int(context.point_queries)+1
 var space: PhysicsDirectSpaceState3D=context.space
 var free: bool=space.intersect_shape(parameters,1).is_empty() and not _circle_blocks(at,at,context.circles,float(context.radius))
 cached[cell]=free
 return free

static func _edge(context: Dictionary,from: Vector2i,to: Vector2i) -> bool:
 var key:=Vector4i(from.x,from.y,to.x,to.y);var edges: Dictionary=context.edges
 if edges.has(key):return bool(edges[key])
 var clear: bool=_segment(context,_point(context,from),_point(context,to))
 edges[key]=clear
 # Existing overlap may be escaped in one direction only.
 if from!=Vector2i.ZERO:edges[Vector4i(to.x,to.y,from.x,from.y)]=clear
 return clear

static func _heuristic(a: Vector2i,b: Vector2i) -> float:
 var delta:=Vector2i(absi(a.x-b.x),absi(a.y-b.y))
 return (float(maxi(delta.x,delta.y))+.41421356237*float(mini(delta.x,delta.y)))*CELL

static func _push(heap: Array[Dictionary],entry: Dictionary) -> void:
 heap.append(entry);var child: int=heap.size()-1
 while child>0:
  var parent: int=(child-1)/2
  if float(heap[parent].f)<=float(entry.f):break
  heap[child]=heap[parent];child=parent
 heap[child]=entry

static func _pop(heap: Array[Dictionary]) -> Dictionary:
 var result: Dictionary=heap[0];var last: Dictionary=heap.pop_back()
 if heap.is_empty():return result
 var parent:=0
 while parent*2+1<heap.size():
  var child: int=parent*2+1
  if child+1<heap.size() and float(heap[child+1].f)<float(heap[child].f):child+=1
  if float(last.f)<=float(heap[child].f):break
  heap[parent]=heap[child];parent=child
 heap[parent]=last
 return result

static func _smooth(context: Dictionary,raw: Array[Vector3]) -> Array[Vector3]:
 var result: Array[Vector3]=[];var anchor: Vector3=context.start;var next:=0
 while next<raw.size():
  var chosen: int=raw.size()-1
  while chosen>=next and not _segment(context,anchor,raw[chosen]):chosen-=1
  if chosen<next:return []
  result.append(raw[chosen]);anchor=raw[chosen];next=chosen+1
 return result

static func _record(actor: Node3D,context: Dictionary,began: int,method: String,expanded: int,raw: int,smoothed: int) -> void:
 actor.set_meta("motion_route_last",{"method":method,"point_queries":int(context.point_queries),"sweeps":int(context.sweeps),"expanded":expanded,"raw_points":raw,"smoothed_points":smoothed,"elapsed_usec":Time.get_ticks_usec()-began})

static func query(actor: Node3D,start: Vector3,finish: Vector3,circles: Array=[]) -> Array[Vector3]:
 return _plan(actor,_context(actor,start,circles),start,finish)

static func query_world(world: Node3D,start: Vector3,finish: Vector3,excluded: Array[RID],circles: Array,bounds: Rect2) -> Array[Vector3]:
 return _plan(world,_context(world,start,circles,WorldBuilder.L_SOLID|WorldBuilder.L_PLACED,excluded,.38,bounds),start,finish)

static func _plan(actor: Node3D,context: Dictionary,start: Vector3,finish: Vector3) -> Array[Vector3]:
 var began: int=Time.get_ticks_usec()
 if start.distance_to(finish)<.001:
  if _free(context,Vector2i.ZERO):return [finish]
  return []
 if _segment(context,start,finish):
  _record(actor,context,began,"direct_capsule",0,1,1);return [finish]
 var low:=Vector2i(floori((minf(start.x,finish.x)-start.x-3.)/CELL),floori((minf(start.z,finish.z)-start.z-3.)/CELL))
 var high:=Vector2i(ceili((maxf(start.x,finish.x)-start.x+3.)/CELL),ceili((maxf(start.z,finish.z)-start.z+3.)/CELL))
 var destination:=Vector2i(roundi((finish.x-start.x)/CELL),roundi((finish.z-start.z)/CELL))
 var goals: Dictionary={}
 for dx: int in [-1,0,1]:
  for dz: int in [-1,0,1]:
   var candidate: Vector2i=destination+Vector2i(dx,dz)
   if _free(context,candidate) and _segment(context,_point(context,candidate),finish):goals[candidate]=true
 if goals.is_empty() or not _free(context,Vector2i.ZERO):
  _record(actor,context,began,"unreachable",0,0,0);return []
 var heap: Array[Dictionary]=[];_push(heap,{"cell":Vector2i.ZERO,"g":0.,"f":_heuristic(Vector2i.ZERO,destination)})
 var costs: Dictionary={Vector2i.ZERO:0.};var parent: Dictionary={};var closed: Dictionary={};var arrived:=Vector2i(2147483647,2147483647);var expanded:=0
 while not heap.is_empty() and expanded<MAX_EXPANSIONS:
  var entry: Dictionary=_pop(heap);var cell: Vector2i=entry.cell
  if closed.has(cell) or float(entry.g)>float(costs.get(cell,INF))+.00001:continue
  if goals.has(cell):arrived=cell;break
  closed[cell]=true;expanded+=1
  for direction: Vector2i in DIRECTIONS:
   var neighbour: Vector2i=cell+direction
   if neighbour.x<low.x or neighbour.y<low.y or neighbour.x>high.x or neighbour.y>high.y or closed.has(neighbour) or not _free(context,neighbour):continue
   if direction.x!=0 and direction.y!=0 and (not _free(context,cell+Vector2i(direction.x,0)) or not _free(context,cell+Vector2i(0,direction.y))):continue
   if not _edge(context,cell,neighbour):continue
   var cost: float=float(costs[cell])+Vector2(direction).length()*CELL
   if parent.has(cell):
    var previous: Vector2i=cell-(parent[cell] as Vector2i)
    if previous!=direction:cost+=.035
   if cost>=float(costs.get(neighbour,INF))-.000001:continue
   costs[neighbour]=cost;parent[neighbour]=cell
   var heuristic: float=_heuristic(neighbour,destination)
   _push(heap,{"cell":neighbour,"g":cost,"f":cost+heuristic+heuristic*.00001})
 if arrived.x==2147483647:
  _record(actor,context,began,"unreachable",expanded,0,0);return []
 var raw: Array[Vector3]=[finish];var cursor: Vector2i=arrived
 while cursor!=Vector2i.ZERO:
  raw.push_front(_point(context,cursor));cursor=parent[cursor]
 var result: Array[Vector3]=_smooth(context,raw)
 _record(actor,context,began,"lazy_astar_capsule",expanded,raw.size(),result.size())
 return result
