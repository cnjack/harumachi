extends Node
## Read-only visual audit: installed only into a temporary copy of the game.
var main: Node
var camera: Camera3D
var folder := ""
var filter := ""
var rows: Array[Dictionary] = []
var failures: Array[String] = []
const TARGETS := [
 ["S01","town","R09","支巷三向路标","fixed",Vector3(19.6,1.6,-5.7),Vector3(22.6,1.4,-6.2)],
 ["S02","town","P_signpost","小镇东侧路标","fixed",Vector3(40,1.65,-4.4),Vector3(40.25,1.35,-7.2)],
 ["S03","farm","FarmNameSign","市民农园名牌","auto"],
 ["S05","farm","P_signpost","农园路标","auto"],
 ["S06","lake","P_signpost","镜波湖入口路标","fixed",Vector3(22,1.8,5.6),Vector3(24,1.4,2.8)],
 ["S07","town","BuildSign","组合活动木牌","fixed",Vector3(-2.6,1.35,3.2),Vector3(-2.6,1.05,1.0)],
 ["S13","town","R06","公交站名牌与路线表","auto"],
 ["S14","bakery","BakeryTrialStand","烘焙店桌面立牌","auto"],
 ["S19","home_haru","FamilyMemoryFrame","春家生活画框","auto"],
 ["S20","toolshed","RaisedSeedCounter","工具屋：移除说明条","fixed",Vector3(-1.5,2.4,1.8),Vector3(.2,.9,-1.5)],
 ["S21","photo_room","PhotoWall_0","照片墙：移除说明条","auto"],
 ["S22","zakka","AwaitingRepair","寄修区：移除说明条","fixed",Vector3(0,3.6,4.4),Vector3(-1,.9,-1.6)],
 ["S23","post","MailRouteSorting","邮局：移除说明条","fixed",Vector3(.5,3.5,3),Vector3(.5,.6,-2)],
 ["S24","library","MapReadingDesk","阅览室：移除说明条","fixed",Vector3(1,3.2,2.8),Vector3(-1.8,.8,-2.3)],
 ["P01","post","MailRouteSorting","邮局分拣格柜","auto"],
 ["P02","photo_room","DatedArchive","照片档案格柜","auto"],
 ["P03","florist","DryFlowerPaperStorage","花店纸材收纳格柜","auto"],
 ["P04","zakka","AwaitingRepair","杂货铺待修柜","auto"],
 ["P05","home_kazuko","BorrowReturnCabinet","和子家借还柜","auto"],
 ["P06","home_ren","DryingLinenFrame","莲家晾布架","auto"],
 ["P07","photo_room","ArchiveDrawers","照片室档案屉","auto"],
 ["S01_back","town","R09","支巷路标背面","fixed",Vector3(25.5,1.7,-6.4),Vector3(22.6,1.4,-6.2)],
 ["S02_back","town","P_signpost","小镇路标背面","fixed",Vector3(40,1.65,-10),Vector3(40,1.4,-7.2)],
 ["S03_back","farm","FarmNameSign","农园名牌背面","fixed",Vector3(-21.5,1.4,-5.2),Vector3(-21.5,.95,-2.4)],
 ["S07_back","town","BuildSign","活动牌背面","fixed",Vector3(-2.6,1.35,-1.3),Vector3(-2.6,1.0,1)],
 ["S01_night","town","R09","支巷路标夜间","fixed",Vector3(19.6,1.6,-5.7),Vector3(22.6,1.4,-6.2)],
 ["S14_night","bakery","BakeryTrialStand","桌面立牌夜间","auto"],
 ["bakery_shelves","bakery","LivingDisplayShelf","烘焙货架刻字","auto"],
 ["home_door","town","H03","住宅门口不再竖提醒牌","fixed",Vector3(19.0,1.7,17.5),Vector3(21.7,1.3,17.2)],
]
func _ready() -> void:
 main=get_parent()
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--scope-filter="):filter=arg.trim_prefix("--scope-filter=")
  if arg.begins_with("--furniture-review-out="):folder=arg.trim_prefix("--furniture-review-out=")
 _run.call_deferred()

func frames(count: int) -> void:
 for index: int in count:await get_tree().process_frame

func find(root: Node,key: String,region: String) -> Node3D:
 if region=="farm" and root==main.world.farm.lakeside:return null
 if root is Node3D and (str(root.name)==key or str(root.get_meta("model_id",""))==key):
  if region!="town" or (root as Node3D).global_position.x<500:return root as Node3D
 for child: Node in root.get_children():
  var found: Node3D=find(child,key,region)
  if found!=null:return found
 return null

func vec(value: Vector3) -> Array[float]:return [value.x,value.y,value.z]

func _run() -> void:
 if folder.is_empty() or OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():get_tree().quit(2);return
 print("ISOLATED_RENDER_SCREEN ",DisplayServer.window_get_current_screen()," WINDOW ",DisplayServer.window_get_position()," NO_FOCUS ",DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS)," AUDIO ",AudioServer.get_driver_name())
 DirAccess.make_dir_recursive_absolute(folder)
 while not main.loading_ready or Loading.scene_busy:await frames(1)
 GameState.new_game();GameState.clock_paused=true;GameState._ui_locks.clear()
 GameState.quests.Q00={"state":"done","step":2};GameState.quests.Q01={"state":"done","step":2}
 GameState.flags.erase("arrival_home");GameState.day=2;GameState.minute=660;GameState.weather="sunny"
 Progress.quiet=true;NPC.roam_enabled=false;main.ui.instant=true;main.ui.auto=true
 main._restore();main.ui.dialogue_end();main.player.process_mode=Node.PROCESS_MODE_DISABLED
 main.rig.process_mode=Node.PROCESS_MODE_DISABLED
 camera=Camera3D.new();camera.near=.025;camera.far=210;camera.fov=43;main.add_child(camera)
 for sample: Array in TARGETS:
  if not filter.is_empty() and str(sample[0]) not in filter.split(","):continue
  var id: String=sample[0];var region: String=sample[1];var key: String=sample[2];var mode: String=sample[4]
  var scope: Node=main.world
  if InteriorBuilder.SPECS.has(region):
   if main.room_kind!=region:await main.enter_interior(region)
   scope=main.world.interiors[region]
  elif region=="house":scope=main.world.house;main._put_in_room(scope.global_position+Vector3(0,.1,2))
  else:
   if main.in_room:await main.exit_interior()
   main.in_room=false;main.room_kind="";GameState.player_in_room=false
   main.world.set_region("town" if region=="town" else "farm");main.world.set_indoor_look(false)
   if region=="farm":scope=main.world.farm
   if region=="lake":scope=main.world.farm.lakeside
  GameState.minute=1185 if id.ends_with("_night") else 660
  main.world.update_time(GameState.minute,"sunny",true);main._sync_weather()
  main.ui.root.visible=false;main.marker.visible=false;main.player.visible=false
  main.shop_life._caption_left=0.0;main.shop_life._caption.visible=false
  for npc: Node3D in main.npcs.values():npc.visible=false
  var item: Node3D=find(scope,key,region)
  var bounds: AABB
  var basis: Basis=Basis.IDENTITY
  var centre: Vector3
  var size: Vector3
  var parts: Array[String]=[]
  if mode=="prefix":
   var started:=false
   for mesh: MeshInstance3D in WorldBuilder.find_meshes(scope):
    if str(mesh.name).begins_with(key):
     var box: AABB=mesh.global_transform*mesh.get_aabb()
     bounds=box if not started else bounds.merge(box);started=true;parts.append(str(mesh.get_path()))
   if not started:failures.append(id+": missing group "+key);continue
   centre=bounds.get_center();size=bounds.size
  else:
   if item==null:failures.append(id+": missing "+key);continue
   bounds=item.get_aabb() if item is MeshInstance3D else WorldBuilder.local_aabb(item)
   centre=item.to_global(bounds.get_center());size=bounds.size*item.global_basis.get_scale().abs()
   basis=item.global_basis.orthonormalized();parts.append(str(item.get_path()))
  var extent: float=maxf(.65,maxf(size.x,maxf(size.y,size.z)))
  var offset: Vector3=basis*Vector3(.24,.32,1.58)*extent
  if mode=="model":offset=basis*Vector3(.65,.65,1.45)*extent
  if mode=="prefix":offset=Vector3(.14,.55,1.57)*extent
  if mode=="label":
   centre=item.global_position-Vector3(0,.13,0);offset=item.global_basis*Vector3(.05,.22,1.05)
  if id in ["P09","P11"]:offset=Vector3(1.45,.45,.25)*extent
  if id=="S03":offset=Vector3(.45,.22,2.5);centre=item.global_position+Vector3(0,.95,0)
  if id=="S05":offset=Vector3(1.5,.5,3.2);centre=item.global_position+Vector3(.3,1.35,0)
  if id=="S13":offset=basis*Vector3(.1,.2,1.25)*extent
  camera.fov=43
  if mode=="fixed":
   camera.global_position=scope.to_global(sample[5]);centre=scope.to_global(sample[6])
  else:camera.global_position=centre+offset
  if id=="S16":camera.global_position=item.global_position+Vector3(-1.10,-.16,0);centre=item.global_position
  if id=="P05":camera.fov=83;camera.global_position=scope.to_global(Vector3(-3.15,.60,3.30));centre=scope.to_global(Vector3(-3.2,.55,2.6))
  if id=="P07":camera.global_position=scope.to_global(Vector3(.7,1.6,.9));centre=scope.to_global(Vector3(2.35,.80,.1))
  if id=="P09":camera.global_position=scope.to_global(Vector3(2.85,1.15,3.25));centre=item.global_position+Vector3(0,.6,0)
  if id=="P11":camera.global_position=scope.to_global(Vector3(-2.9,1.45,3.5));centre=item.global_position+Vector3(0,.85,0)
  if id=="P13":centre=item.global_position+Vector3(0,.28,0);camera.global_position=centre+Vector3(1.0,.35,-.65)
  if id=="P14":centre=item.global_position+Vector3(0,.43,0);camera.global_position=centre+Vector3(-1.0,.6,1.7)
  camera.look_at(centre);camera.make_current();camera.reset_physics_interpolation()
  await frames(20);await RenderingServer.frame_post_draw
  var error: Error=get_viewport().get_texture().get_image().save_png(folder.path_join(id+".png"))
  if error!=OK:failures.append(id+": png error "+str(error))
  var captions: Array[String]=[]
  if item is Label3D:captions.append((item as Label3D).text)
  if item!=null:
   for label: Label3D in item.find_children("*","Label3D",true,false):captions.append(label.text)
  rows.append({"id":id,"file":id+".png","title":sample[3],"region":region,"key":key,"parts":parts,"captions":captions,"camera":vec(camera.global_position),"focus":vec(centre),"size":vec(size),"visible":item.is_visible_in_tree() if item!=null else true})
  print("SCOPE_SHOT ",id," ",sample[3]," error=",error)
 FileAccess.open(folder.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"kind":"current_scene_scope_review","passed":failures.is_empty(),"failures":failures,"screenshots":rows},"\t"))
 write_inventory()
 Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)

func write_inventory() -> void:
 var uses: Array[Dictionary]=[]
 for node: Node in main.world.find_children("*","Node3D",true,false):
  var id: String=str(node.get_meta("modular_source",node.get_meta("model_id","")))
  if not id.begins_with("MS") and id not in ["P_signpost","R09","R06"]:continue
  var ancestor: Node=node.get_parent()
  var duplicate_source:=false
  while ancestor!=null and ancestor!=main.world:
   if ancestor.get_meta("model_id","")==id or ancestor.get_meta("modular_source","")==id:duplicate_source=true;break
   ancestor=ancestor.get_parent()
  if duplicate_source:continue
  var object:=node as Node3D
  uses.append({"id":id,"path":str(main.world.get_path_to(node)),"position":vec(object.global_position),"scale":vec(object.scale),"engraved_text":str(object.get_meta("engraved_text",""))})
 FileAccess.open(folder.path_join("runtime-uses.json"),FileAccess.WRITE).store_string(JSON.stringify(uses,"\t"))
