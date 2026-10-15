extends RefCounted
## Runs unchanged against the old game: detects placeholder boards and box cubbies.
var t: Node
var main: Node
const IDS := ["MS01_signpost","MS02_arrow_board","MS03_garden_board","MS04_wall_plaque","MS05_table_sign","MS06_bus_pole","MS07_timetable_case","MS08_storage_bay","MS09_archive_box","MS10_wrapping_rolls","MS11_archive_drawer","MS12_linen_frame","MS13_picture_frame"]
const CABINETS := [["post","MailRouteSorting",15],["photo_room","DatedArchive",12],["florist","DryFlowerPaperStorage",6],["zakka","AwaitingRepair",6],["home_kazuko","BorrowReturnCabinet",4]]
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("MODULAR_PROPS",label,ok,detail)
func run() -> void:
 for id: String in IDS:check(id+" is a real exported model",ResourceLoader.exists("res://assets/models/"+id+".glb"))
 for row: Array in CABINETS:
  var room: Node=main.world.interiors[row[0]]
  var group:=room.find_child(row[1],true,false) as Node3D
  check(str(row[1])+" uses individually reusable open compartments",group!=null and group.get_meta("modular_cabinet",false) and group.find_children("Bay_*","Node3D",false,false).size()==int(row[2]))
  if group==null:continue
  var invalid: Array[String]=[]
  for content: Node3D in group.find_children("Contents_*","Node3D",false,false):
   var owner_id: int=int(content.get_meta("cabinet_bay",0))
   var bay: Node3D=instance_from_id(owner_id) as Node3D if owner_id!=0 else null
   if bay==null:invalid.append(str(content.name));continue
   var inside: AABB=bay.global_transform*WorldBuilder.local_aabb(bay)
   var object: AABB=content.global_transform*WorldBuilder.local_aabb(content)
   if object.position.x<inside.position.x-.003 or object.end.x>inside.end.x+.003 or object.position.z<inside.position.z-.003 or object.end.z>inside.end.z+.003 or object.end.y>inside.end.y-.008:invalid.append(str(content.name))
   var top: float=WorldBuilder.surface_height(bay,Vector2(content.global_position.x,content.global_position.z),inside.position.y+inside.size.y*.30)
   if not is_finite(top) or absf(object.position.y-top)>.009:invalid.append(str(content.name)+" support")
  check(str(row[1])+" contents fit and rest on actual generated compartment floors",invalid.is_empty(),str(invalid))
 var floating: Array[String]=[]
 for label: String in ["VisitDoorPlaque","VisitDoorPlaquePost","ToolshedDoorName","FamilyNames","WetDry","ArchiveRule","RepairQueue","PostRoutes","ReadingName","RoomName"]:
  for node: Node in main.world.find_children(label,"Node",true,false):floating.append(str(node.get_path()))
 check("door and room instructions no longer create physical reminder plates",floating.is_empty(),str(floating))
 var bakery: Node=main.world.interiors.bakery
 var stand:=bakery.find_child("BakeryTrialStand",true,false) as Node3D
 check("bakery tabletop sign uses the actual generated frame",stand!=null and stand.get_meta("modular_source","")=="MS05_table_sign")
 check("bakery sign rests on the actual counter",stand!=null and stand.has_meta("support_surface") and PropAudit.mount_supported(stand,stand.get_node_or_null(stand.get_meta("support_surface")) as Node3D))
 check("bakery quest instructions remain available through the existing interaction",main.story.bakery.prompt("bakery_orders")!=null)
 var tags: Array[Node]=bakery.find_children("BreadTag_*","Node",true,false)+bakery.find_children("TrayPrice_*","Node",true,false)+bakery.find_children("ShelfPriceSign","Node",true,false)
 check("bread shelves no longer have floating text boards",tags.is_empty(),str(tags.size()))
 var engraved:=0
 for root: Node in main.world.find_children("*","Node3D",true,false):
  if root.get_meta("engraved_surfaces",0)>0:engraved+=1
 check("wayfinding and shelf lettering is projected into actual timber",engraved>=15,str(engraved))
 for root: Node3D in [main.world.get_node("R09"),main.world.get_node("P_signpost"),main.world.farm.get_node("P_signpost"),main.world.farm.lakeside.get_node("P_signpost")]:
  var parts: Array[Node]=root.find_children("Arrow_*","Node3D",true,false)
  var good: bool=parts.size()==3
  for part: Node in parts:good=good and part.get_meta("engraved_surfaces",0)>0 and part.get_meta("engraving_two_sided",false)
  check(str(root.get_path())+" has three independent arrows with front and back engraving",good)
 var linen:=main.world.interiors.home_ren.find_child("DryingLinenFrame",true,false) as Node3D
 check("linen drying rack has generated draped cloth geometry",linen!=null and linen.get_meta("modular_source","")=="MS12_linen_frame")
 for index: int in 3:
  var drawer:=main.world.interiors.photo_room.find_child("ArchiveDrawer_%d"%index,true,false) as Node3D
  check("archive drawer %d uses generated open tray and real handle"%index,drawer!=null and drawer.get_meta("modular_source","")=="MS11_archive_drawer")
  if drawer:
   var bounds: AABB=drawer.global_transform*WorldBuilder.local_aabb(drawer)
   var support: Node3D=drawer.get_node_or_null(str(drawer.get_meta("support_surface","")))
   var contact: float=WorldBuilder.rendered_support_height(support,drawer.global_position,.5,true) if support else INF
   check("archive drawer %d rests on the real lower shelf"%index,support!=null and is_finite(contact) and absf(bounds.position.y-contact)<.009)
 var stop: Node=main.world.get_node("R06")
 var shelter_box: AABB=WorldBuilder.local_aabb(stop as Node3D)
 # Descendants include the newly attached sign, so inspect only the source shelter mesh.
 var old_pole_gone:=true
 for mesh: MeshInstance3D in WorldBuilder.find_meshes(stop):
  var node: Node=mesh
  var added:=false
  while node!=stop and node!=null:
   if node.has_meta("modular_source") or node.name in ["StopName","RouteBacking"]:added=true
   node=node.get_parent()
  if not added and mesh.get_parent()==stop:
   old_pole_gone=old_pole_gone and (stop.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()).end.x<1.60
 check("old disconnected blue bus-stop pole is removed instead of hidden behind the new sign",old_pole_gone and shelter_box.size.x>3.)
 for key: String in ["BusStopPole","Timetable","RouteMap"]:
  var part:=stop.get_node_or_null(key) as Node3D
  check("bus stop "+key+" uses a separate reusable generated asset",part!=null and str(part.get_meta("modular_source","")).begins_with("MS"))

 for row: Array in [["home_haru","FamilyMemoryFrame"],["photo_room","PhotoWall_0"],["photo_room","PhotoWall_1"]]:
  var picture:=main.world.interiors[row[0]].find_child(row[1],true,false) as Node3D
  var touching: bool=picture!=null and PropAudit.wall_supported(picture)
  var rejects_gap:=false
  if picture:
   var original: Vector3=picture.position
   picture.position.x-=.03
   rejects_gap=not PropAudit.wall_supported(picture)
   picture.position=original
  check(str(row[1])+" has real wall contact and rejects a 3cm gap",touching and rejects_gap)

  var inset:=false
  if picture:
   var sheet:=picture.get_node_or_null("ExistingStoryPicture") as MeshInstance3D
   if sheet and sheet.mesh is QuadMesh:
    var extent: Vector2=(sheet.mesh as QuadMesh).size
    var inner: float=-INF
    var rim: float=-INF
    for mesh: MeshInstance3D in WorldBuilder.find_meshes(picture):
     if mesh==sheet:continue
     var transform: Transform3D=picture.global_transform.affine_inverse()*mesh.global_transform
     for vertex: Vector3 in mesh.mesh.get_faces():
      var point: Vector3=transform*vertex
      rim=maxf(rim,point.z)
      if absf(point.x-sheet.position.x)<extent.x*.5 and absf(point.y-sheet.position.y)<extent.y*.5:inner=maxf(inner,point.z)
    inset=is_finite(inner) and sheet.position.z>inner+.0002 and sheet.position.z<rim-.003
  check(str(row[1])+" printed image sits within the actual raised wooden rim",inset)
