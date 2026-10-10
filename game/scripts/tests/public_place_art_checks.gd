extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("PUBLIC_ART",label,ok,detail)

func run() -> void:
 var supports:=0;var supported:=true;var clear_workspace:=false
 var windows:=0;var night_ok:=true
 var sunlight: Dictionary={}
 for kind: String in ["workroom","bakery","store"]:
  var room: InteriorBuilder=main.world.interiors[kind]
  var floor: MeshInstance3D=room.get_node_or_null("PublicPlankFloor") as MeshInstance3D
  var boards:=false
  if floor:
   var mat:=floor.material_override as ShaderMaterial
   boards=mat!=null and mat.shader.resource_path.ends_with("public_planks.gdshader") and mat.get_shader_parameter("grain_tex") is Texture2D and float(mat.get_shader_parameter("board_width"))>=.24
  check(kind+" has quiet metre-scale floorboards using its actual imagegen material",boards)
  var openings: Array=room.find_children("PublicWindow_*","Node3D",false,false)
  var aperture: bool=not openings.is_empty()
  for window: Node3D in openings:
   var span: Vector2=window.get_meta("window_aperture",Vector2.ZERO)
   var start: Vector3=window.to_global(Vector3(span.x*.32,-.24,.35))
   var finish: Vector3=window.to_global(Vector3(span.x*.32,-.24,-.35))
   var ray:=PhysicsRayQueryParameters3D.create(start,finish,WorldBuilder.L_SOLID|WorldBuilder.L_PLACED)
   var hit: Dictionary=room.get_world_3d().direct_space_state.intersect_ray(ray)
   aperture=aperture and hit.is_empty() and window.get_node_or_null("Sill")!=null and window.find_children("Mullion_*","MeshInstance3D",false,false).size()==3
   var glass:=window.get_node_or_null("Glass") as MeshInstance3D
   aperture=aperture and glass!=null and (glass.material_override as StandardMaterial3D).transparency==BaseMaterial3D.TRANSPARENCY_ALPHA
  check(kind+" windows are real open wall apertures with glass and projecting joinery",aperture,str(openings.size()))
  sunlight[kind]=0
  if not openings.is_empty():
   main.world.set_indoor_look(true,kind)
   sunlight[kind]=sun_paths(room)
  var root:=room.get_node_or_null("PublicPlaceArt") as Node3D
  if root:
   for node: Node3D in root.find_children("*","Node3D",true,false):
    if not node.has_meta("art_support"):continue
    supports+=1
    var support:=node.get_node_or_null(node.get_meta("art_support")) as Node3D
    if support==null:supported=false;continue
    var bounds: AABB=node.global_transform*WorldBuilder.local_aabb(node)
    var height: float=WorldBuilder.surface_height(support,Vector2(node.global_position.x,node.global_position.z),bounds.position.y+.06)
    supported=supported and is_finite(height) and absf(bounds.position.y-height)<.012
   if kind=="workroom":
    var cutting:=root.get_node_or_null("CuttingMat") as MeshInstance3D
    if cutting:
     var bounds: AABB=cutting.transform*cutting.get_aabb()
     var footprint:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
     clear_workspace=not footprint.intersects(Rect2(Vector2(-3.16,-1.86),Vector2(.72,.72)))
  main.world.update_time(21.0*60.0,"sunny",true)
  for view: MeshInstance3D in room.find_children("SummerView","MeshInstance3D",true,false):
   windows+=1;night_ok=night_ok and is_zero_approx(float((view.material_override as ShaderMaterial).get_shader_parameter("daylight")))
  main.world.update_time(GameState.minute,GameState.weather,true)
 main.world.set_indoor_look(false)
 check("real sunlight reaches the floor through windows in all three public rooms",sunlight.values().all(func(value: int):return value>0),JSON.stringify(sunlight))
 check("new materials, food and tools sit on the actual rendered support surfaces",supports>=15 and supported,str(supports))
 check("the shared worktable retains clear space for the real representative lantern",clear_workspace)
 var town: WorldBuilder=main.world
 var notice: Node=town.get_node_or_null("S06/PublicStreetArt/CommunityNoticeCase")
 check("community notices have actual paper, a timber case and a rain hood",notice!=null and notice.get_node_or_null("RainHood")!=null and notice.find_children("CraftSketch","MeshInstance3D",true,false).size()==2)
 for id: String in ["S02","S01"]:
  var art: Node=town.get_node_or_null(id+"/PublicStreetArt")
  var supports_present: bool=art!=null and art.find_children("AwningBrace_*","MeshInstance3D",false,false).size()==2
  var woven:=false
  for mesh: MeshInstance3D in WorldBuilder.find_meshes(town.get_node(id)):
   for index in mesh.mesh.get_surface_count():
    var material:=mesh.get_active_material(index) as ShaderMaterial
    if material!=null and material.shader.resource_path.ends_with("public_facade_finish.gdshader") and material.get_shader_parameter("weave_tex") is Texture2D:woven=true
  check(id+" keeps real awning supports and the generated fabric finish",supports_present and woven)
 check("every window view darkens with the actual world night state",windows>=6 and night_ok,str(windows))
 var paths_clear:=true
 var blocked_routes: Array[String]=[]
 var destinations: Dictionary={}
 for kind: String in ["store","bakery","workroom"]:
  destinations[kind]=[]
  for item: Array in InteriorBuilder.spec_for(kind).points:
   if str(item[0]).ends_with("exit"):continue
   destinations[kind].append(Vector3(float(item[1]),0,float(item[3])))
 for kind: String in destinations:
  var room: InteriorBuilder=town.interiors[kind]
  for destination: Vector3 in destinations[kind]:
   var route: PackedVector3Array=NPC.MOTION_ROUTE.query(main.player,InteriorBuilder.door_point(kind),room.origin+destination)
   paths_clear=paths_clear and not route.is_empty()
   if route.is_empty():blocked_routes.append(kind+str(destination))
 check("all three entrances retain real routes to the existing work and shopping points",paths_clear,str(blocked_routes))
 var plants:=0;var grounded:=true
 for id: String in ["S06","S02","S01"]:
  var art: Node=town.get_node_or_null(id+"/PublicStreetArt")
  if art==null:continue
  for node: Node3D in art.get_children():
   if not node.get_meta("art_grounded",false):continue
   plants+=1
   var bounds: AABB=node.global_transform*WorldBuilder.local_aabb(node)
   var top: float=float(node.get_meta("support_y",-99))
   grounded=grounded and absf(bounds.position.y-(top-.006))<.008
 check("porch plants rest on the measured pavement or building footing",plants>=5 and grounded,str(plants))

func sun_paths(room: InteriorBuilder) -> int:
 var count:=0
 var source: Vector3=room.wb.sun.global_basis.z.normalized()
 for window: Node3D in room.find_children("PublicWindow_*","Node3D",false,false):
  var span: Vector2=window.get_meta("window_aperture")
  for offset: float in [-.32,-.13,.13,.32]:
   var opening: Vector3=window.to_global(Vector3(span.x*offset,-.24,0))
   var floor_at: Vector3=opening-source*((opening.y-.02)/source.y)
   var local: Vector3=room.to_local(floor_at)
   if absf(local.x)>=float(room.spec.size.x)*.5-.05 or absf(local.z)>=float(room.spec.size.y)*.5-.05:continue
   var target: Vector3=floor_at+source*8.0
   var blocked:=false
   for mesh: MeshInstance3D in WorldBuilder.find_meshes(room):
    if mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:continue
    var bounds: AABB=mesh.global_transform*mesh.get_aabb()
    if bounds.intersects_segment(floor_at,target)==null:continue
    var faces: PackedVector3Array=mesh.mesh.get_faces()
    for triangle in range(0,faces.size(),3):
     var hit: Variant=Geometry3D.segment_intersects_triangle(floor_at,target,mesh.to_global(faces[triangle]),mesh.to_global(faces[triangle+1]),mesh.to_global(faces[triangle+2]))
     if hit!=null and floor_at.distance_to(hit as Vector3)>.02:blocked=true;break
    if blocked:break
   if not blocked:count+=1
 return count
