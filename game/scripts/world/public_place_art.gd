class_name PublicPlaceArt
extends RefCounted
## Imagegen references are translated into real openings, supported objects and quiet materials.
const TEX := "res://assets/textures/three_places/"
const WINDOWS := {
 "workroom": [[-1.0,.7,1.7],[1.0,.0,1.7],[1.0,2.65,1.45,.85]],
 "bakery": [[-1.0,2.65,1.6,.85],[1.0,-1.8,1.35],[1.0,2.65,1.15]],
 "store": [[1.0,1.8,1.25]],
}

static func matte(colour: Color) -> StandardMaterial3D:
 var material:=StandardMaterial3D.new();material.albedo_color=colour
 material.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON;material.specular_mode=BaseMaterial3D.SPECULAR_DISABLED;material.roughness=1.0
 return material

static func wood(colour: Color=Color(.66,.49,.31)) -> StandardMaterial3D:
 var material:=matte(colour);material.albedo_texture=load(TEX+"quiet_pine_grain.png")
 material.uv1_scale=Vector3(.35,1.2,1)
 return material

static func canvas(colour: Color) -> ShaderMaterial:
 var material:=ShaderMaterial.new();material.shader=load("res://shaders/public_canvas.gdshader")
 material.set_shader_parameter("weave_tex",load(TEX+"linen_weave.png"));material.set_shader_parameter("tint",colour)
 return material

static func box(parent: Node3D,label: String,size: Vector3,at: Vector3,material: Material,solid: bool=false) -> MeshInstance3D:
 var mesh:=MeshInstance3D.new();mesh.name=label;var shape:=BoxMesh.new();shape.size=size
 mesh.mesh=shape;mesh.position=at;mesh.material_override=material;mesh.set_meta("model_part",true);parent.add_child(mesh)
 if solid:
  var body:=StaticBody3D.new();body.name="Collision";body.collision_layer=WorldBuilder.L_SOLID;body.collision_mask=0;body.set_meta("model_part",true)
  var collision:=CollisionShape3D.new();var volume:=BoxShape3D.new();volume.size=size;collision.shape=volume;body.add_child(collision);mesh.add_child(body)
 return mesh

static func cylinder(parent: Node3D,label: String,at: Vector3,radius: float,height: float,material: Material) -> MeshInstance3D:
 var mesh:=MeshInstance3D.new();mesh.name=label;var shape:=CylinderMesh.new();shape.top_radius=radius*.88;shape.bottom_radius=radius;shape.height=height;shape.radial_segments=16
 mesh.mesh=shape;mesh.position=at;mesh.material_override=material;parent.add_child(mesh);return mesh

static func overlaps_window(kind: String,side: float,z: float,half_width: float) -> bool:
 for opening: Array in WINDOWS[kind]:
  if float(opening[0])==side and absf(float(opening[1])-z)<float(opening[2])*.5+half_width:return true
 return false

static func side_walls(room: InteriorBuilder,material: Material) -> void:
 var half_w: float=room.spec.size.x*.5;var half_d: float=room.spec.size.y*.5
 for side: float in [-1.0,1.0]:
  var openings: Array=[]
  for entry: Array in WINDOWS[room.kind]:
   if float(entry[0])==side:openings.append(entry)
  openings.sort_custom(func(a: Array,b: Array):return a[1]<b[1])
  var cursor: float=-half_d
  for index in openings.size():
   var opening: Array=openings[index];var start: float=opening[1]-opening[2]*.5;var finish: float=opening[1]+opening[2]*.5
   if start>cursor:room._wall(Vector3(.16,room.ceiling_height,start-cursor),Vector3(side*(half_w+.08),room.ceiling_height*.5,(start+cursor)*.5),material)
   var sill: float=float(opening[3]) if opening.size()>3 else 1.25
   var head: float=2.45
   room._wall(Vector3(.16,sill,finish-start),Vector3(side*(half_w+.08),sill*.5,(start+finish)*.5),material)
   room._wall(Vector3(.16,room.ceiling_height-head,finish-start),Vector3(side*(half_w+.08),(head+room.ceiling_height)*.5,(start+finish)*.5),material)
   _window(room,side,float(opening[1]),float(opening[2]),index,sill,head)
   cursor=finish
  if cursor<half_d:room._wall(Vector3(.16,room.ceiling_height,half_d-cursor),Vector3(side*(half_w+.08),room.ceiling_height*.5,(cursor+half_d)*.5),material)

static func _window(room: InteriorBuilder,side: float,z: float,width: float,index: int,sill: float,head: float) -> void:
 var root:=Node3D.new();root.name="PublicWindow_%s_%d"%["West" if side<0 else "East",index];room.add_child(root)
 var height: float=head-sill
 root.position=Vector3(side*(float(room.spec.size.x)*.5+.02),(head+sill)*.5,z);root.rotation.y=-side*PI*.5
 root.set_meta("window_aperture",Vector2(width,height))
 var timber:=wood(Color(.53,.37,.22))
 for x: float in [-width*.5,width*.5]:box(root,"Jamb_%d"%int(x*100),Vector3(.065,height+.08,.18),Vector3(x,0,0),timber)
 for y: float in [-height*.5,height*.5]:box(root,"Rail_%d"%int(y*100),Vector3(width+.13,.07,.18),Vector3(0,y,0),timber)
 box(root,"Sill",Vector3(width+.20,.075,.28),Vector3(0,-height*.5-.04,.06),wood())
 for bar in 3:box(root,"Mullion_%d"%bar,Vector3(.027,height-.05,.07),Vector3(-width*.5+width*float(bar+1)/4.0,0,.035),timber)
 box(root,"Crossbar",Vector3(width,.027,.07),Vector3(0,-.08,.035),timber)
 var quad:=QuadMesh.new();quad.size=Vector2(width,height)
 var view:=MeshInstance3D.new();view.name="SummerView";view.mesh=quad;view.position.z=-.16;view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var image:=ShaderMaterial.new();image.shader=load("res://shaders/public_window_view.gdshader");image.set_shader_parameter("view_tex",load(TEX+"summer_window_view.png"));image.set_shader_parameter("daylight",1.0);view.material_override=image;root.add_child(view)
 var glass:=MeshInstance3D.new();glass.name="Glass";glass.mesh=quad;glass.position.z=.018;glass.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var clear:=matte(Color(.72,.85,.91,.07));clear.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;clear.cull_mode=BaseMaterial3D.CULL_DISABLED;glass.material_override=clear;root.add_child(glass)
 # Curtain stays at the top so the real opening and its cast lattice shadows remain visible.
 box(root,"LinenValance",Vector3(width*.98,.14,.035),Vector3(0,height*.5-.12,.075),canvas(Color(.88,.89,.79)))

static func set_evening(room: InteriorBuilder,_evening: bool) -> void:
 for view: MeshInstance3D in room.find_children("SummerView","MeshInstance3D",true,false):
  (view.material_override as ShaderMaterial).set_shader_parameter("daylight",1.0-clampf(float(room.wb.look.get("night",0.0)),0.0,1.0))

static func floor_material(room: InteriorBuilder) -> ShaderMaterial:
 var material:=ShaderMaterial.new();material.shader=load("res://shaders/public_planks.gdshader")
 material.set_shader_parameter("grain_tex",load(TEX+"quiet_pine_grain.png"));material.set_shader_parameter("room_origin",room.origin)
 material.set_shader_parameter("tint",{"workroom":Color(.70,.66,.57),"bakery":Color(.88,.80,.68),"store":Color(.62,.60,.53)}[room.kind])
 material.set_shader_parameter("board_width",.31 if room.kind=="workroom" else .27)
 material.set_shader_parameter("board_length",1.9 if room.kind=="workroom" else 1.65)
 material.set_shader_parameter("along_x",room.kind=="workroom")
 return material

static func supported(node: Node3D,support: Node3D) -> void:
 node.set_meta("art_support",node.get_path_to(support))
 node.set_meta("support_surface",node.get_path_to(support))
 var bounds: AABB=node.global_transform*WorldBuilder.local_aabb(node)
 node.set_meta("support_ceiling",bounds.position.y+.025)

static func prop(room: InteriorBuilder,parent: Node3D,id: String,at: Vector3,height: float,support: Node3D=null) -> Node3D:
 var node: Node3D=room.wb.spawn(id,at,0,0,parent)
 if node==null:return null
 var bounds: AABB=WorldBuilder.local_aabb(node)
 node.scale*=height/maxf(bounds.size.y,.001)
 WorldBuilder.rest_on(node,at.y)
 HouseBuilder.toonify(node)
 if support!=null:supported(node,support)
 return node

static func bench(parent: Node3D,label: String,at: Vector3,width: float,depth: float,height: float=.78) -> MeshInstance3D:
 var top:=box(parent,label,Vector3(width,.055,depth),at+Vector3(0,height-.0275,0),wood(),true)
 for x: float in [-width*.5+.08,width*.5-.08]:
  for z: float in [-depth*.5+.06,depth*.5-.06]:box(parent,label+"Leg_%d_%d"%[int(x*100),int(z*100)],Vector3(.065,height-.055,.065),at+Vector3(x,(height-.055)*.5,z),wood(Color(.51,.36,.24)))
 box(parent,label+"LowerBoard",Vector3(width-.05,.045,depth-.02),at+Vector3(0,.20,0),wood(Color(.58,.43,.29)))
 return top

static func folded_cloth(parent: Node3D,label: String,at: Vector3,tint: Color,support: Node3D) -> void:
 var linen:=canvas(tint)
 for layer in 3:
  var sheet:=box(parent,label+"_%d"%layer,Vector3(.42,.024,.28),at+Vector3(float(layer)*.007,.012+float(layer)*.024,0),linen)
  if layer==0:supported(sheet,support)
 box(parent,label+"Fold",Vector3(.018,.075,.27),at+Vector3(.21,.0375,0),linen)

static func tray(parent: Node3D,label: String,at: Vector3,size: Vector2,support: Node3D) -> MeshInstance3D:
 var base:=box(parent,label,Vector3(size.x,.025,size.y),at+Vector3(0,.0125,0),wood(Color(.66,.48,.30)));supported(base,support)
 for side: float in [-1.0,1.0]:
  box(parent,label+"Long_%d"%int(side),Vector3(size.x,.055,.025),at+Vector3(0,.0525,side*(size.y*.5-.0125)),wood())
  box(parent,label+"End_%d"%int(side),Vector3(.025,.055,size.y-.05),at+Vector3(side*(size.x*.5-.0125),.0525,0),wood())
 return base

static func sketch(parent: Node3D,label: String,at: Vector3,size: Vector2,cell: int,yaw: float=0.0) -> Node3D:
 var frame:=Node3D.new();frame.name=label;frame.position=at;frame.rotation.y=yaw;parent.add_child(frame)
 box(frame,"Board",Vector3(size.x+.06,size.y+.06,.035),Vector3.ZERO,wood(Color(.43,.30,.19)))
 var image:=MeshInstance3D.new();image.name="CraftSketch";var quad:=QuadMesh.new();quad.size=size;image.mesh=quad;image.position.z=.019
 var paper:=matte(Color.WHITE);paper.albedo_texture=load(TEX+"community_craft_sketches.png");paper.uv1_scale=Vector3(.5,.5,1);paper.uv1_offset=Vector3(float(cell%2)*.5,float(cell/2)*.5,0);image.material_override=paper;frame.add_child(image)
 for x: float in [-size.x*.43,size.x*.43]:cylinder(frame,"Pin_%d"%int(x*100),Vector3(x,size.y*.42,.025),.012,.012,matte(Color(.60,.28,.17))).rotation.x=PI*.5
 return frame

static func build(room: InteriorBuilder) -> void:
 var root:=Node3D.new();root.name="PublicPlaceArt";room.add_child(root)
 if room.kind=="workroom":_workroom(room,root)
 elif room.kind=="bakery":_bakery(room,root)
 else:_store(room,root)
 PublicRoomLife.build(room,root)

static func _workroom(room: InteriorBuilder,root: Node3D) -> void:
 var archive:=bench(root,"ArchiveWorkbench",Vector3(-4.0,0,-4.02),1.9,.70)
 folded_cloth(root,"IndigoArchiveCloth",Vector3(-4.45,.78,-4.02),Color(.23,.34,.43),archive)
 folded_cloth(root,"RustArchiveCloth",Vector3(-3.92,.78,-4.02),Color(.65,.37,.26),archive)
 prop(room,root,"W11_ceramic_set",Vector3(-3.32,.78,-4.02),.20,archive)
 for index in 3:
  var storage:=box(root,"ArchiveDrawer_%d"%index,Vector3(.55,.26,.56),Vector3(-4.64+index*.62,.3525,-4.02),matte(Color(.64,.51,.35)))
  supported(storage,root.get_node("ArchiveWorkbenchLowerBoard"))
  ClearSignage.paper_tag(storage,"Label",["试样","布料","修补"][index],Vector3(0,0,.288),Vector2(.30,.11),0,.06)
 sketch(root,"CraftJointStudy",Vector3(4.5,1.93,-4.38),Vector2(.78,.70),0)
 sketch(root,"FestivalClothStudy",Vector3(5.87,2.65,1.35),Vector2(.66,.63),2,-PI*.5)
 # Keep the centre of the actual table empty for RepresentativeLantern and player work.
 var table: Node3D=room.pieces[0]
 var top: float=WorldBuilder.surface_height(table,Vector2(room.origin.x,room.origin.z)+Vector2(-3.38,-1.5),2.0)
 if is_finite(top):
  var cutting:=box(root,"CuttingMat",Vector3(.33,.008,.30),Vector3(-3.38,top+.004,-1.35),canvas(Color(.27,.40,.34)));supported(cutting,table)
  for index in 4:box(root,"BambooOffcut_%d"%index,Vector3(.016,.008,.20),Vector3(-3.48+index*.048,top+.012,-1.35),wood(Color(.77,.67,.42)))
 var supply:=room.get_node("RoomIdentity/CommunityMaterialChest") as Node3D
 var chest_top: float=WorldBuilder.surface_height(supply,Vector2(room.origin.x,room.origin.z)+Vector2(4.7,-3.67),2.0)
 if is_finite(chest_top):folded_cloth(root,"RetainedFabric",Vector3(4.7,chest_top,-3.67),Color(.36,.43,.48),supply)

static func _bakery(room: InteriorBuilder,root: Node3D) -> void:
 var prep:=bench(root,"PrepShelf",Vector3(-2.05,0,-3.65),.90,.60,.84)
 prop(room,root,"W19_flour_bag",Vector3(-2.05,.84,-3.65),.45,prep)
 prop(room,root,"W19_flour_bag",Vector3(-2.05,.2225,-3.65),.32,root.get_node("PrepShelfLowerBoard"))
 sketch(root,"BreadCraftSketch",Vector3(-5.39,2.0,1.25),Vector2(.64,.61),2,PI*.5)
 # Cloth is draped over the existing preparation surface; all added pieces have real support.
 var prep_top: float=.89
 var support: Node3D=box(root,"KneadingBoard",Vector3(.48,.018,.46),Vector3(1.85,prep_top+.009,-3.2),wood(Color(.79,.62,.40)))
 folded_cloth(root,"BakingTowel",Vector3(1.85,prep_top+.018,-3.2),Color(.92,.81,.70),support)
 var ledge:=bench(root,"HerbLedge",Vector3(5.16,0,2.95),.54,.62,.84)
 prop(room,root,"A15_potted_plant",Vector3(5.16,.84,2.95),.42,ledge)
 var counter: Node3D=room.pieces[3]
 var counter_top: float=WorldBuilder.surface_height(counter,Vector2(room.origin.x,room.origin.z)+Vector2(2.80,.10),2.0)
 if is_finite(counter_top):
  var serving:=tray(root,"CounterServingTray",Vector3(2.80,counter_top,.10),Vector2(.40,.29),counter)
  prop(room,root,"B02_croissant",Vector3(2.80,counter_top+.025,.10),.11,serving)

static func _store(room: InteriorBuilder,root: Node3D) -> void:
 var wrap:=bench(root,"WrappingBench",Vector3(-4.35,0,2.3),.58,.68,.83)
 var sheet:=box(root,"BrownWrappingPaper",Vector3(.43,.009,.49),Vector3(-4.35,.8345,2.3),canvas(Color(.69,.51,.31)));supported(sheet,wrap)
 var counter: Node3D=room.pieces[0]
 var counter_top: float=WorldBuilder.surface_height(counter,Vector2(room.origin.x,room.origin.z)+Vector2(-4.10,.10),2.0)
 if is_finite(counter_top):
  var paper:=box(root,"CounterWrappingPaper",Vector3(.39,.01,.32),Vector3(-4.10,counter_top+.005,.10),canvas(Color(.76,.60,.39)));supported(paper,counter)
 var plant_stand:=bench(root,"PantryPlantStand",Vector3(-4.86,0,-3.60),.47,.48,.70)
 prop(room,root,"A15_potted_plant",Vector3(-4.86,.70,-3.60),.48,plant_stand)
 folded_cloth(root,"StoredApron",Vector3(-4.86,.20+.0225,-3.60),Color(.31,.41,.38),plant_stand.get_parent().get_node("PantryPlantStandLowerBoard"))
 var boxes:=bench(root,"BasketStation",Vector3(5.12,0,3.11),.48,.61,.48)
 prop(room,root,"W21_tea_tin",Vector3(5.12,.48,3.11),.24,boxes)
 ClearSignage.paper_tag(root,"WrappingHint","纸袋与包纸",Vector3(-5.39,1.35,2.3),Vector2(.78,.16),PI*.5,.08)

static func rod(parent: Node3D,label: String,from: Vector3,to: Vector3,radius: float,material: Material) -> MeshInstance3D:
 var mesh:=cylinder(parent,label,(from+to)*.5,radius,from.distance_to(to),material)
 mesh.quaternion=Quaternion(Vector3.UP,(to-from).normalized());return mesh

static func street(world: WorldBuilder) -> void:
 for id: String in ["S06","S02","S01"]:
  var building: Node3D=world.get_node(id)
  var root:=Node3D.new();root.name="PublicStreetArt";building.add_child(root)
  var kind: int=["S06","S02","S01"].find(id)
  for mesh: MeshInstance3D in WorldBuilder.find_meshes(building):
   if not str(mesh.name).begins_with("Rodin_"):continue
   for surface in mesh.mesh.get_surface_count():
    var original:=mesh.get_active_material(surface) as StandardMaterial3D
    if original==null or original.albedo_texture==null:continue
    var finish:=ShaderMaterial.new();finish.shader=load("res://shaders/public_facade_finish.gdshader")
    finish.set_shader_parameter("albedo_tex",original.albedo_texture);finish.set_shader_parameter("albedo_color",original.albedo_color)
    finish.set_shader_parameter("grain_tex",load(TEX+"quiet_pine_grain.png"));finish.set_shader_parameter("weave_tex",load(TEX+"linen_weave.png"))
    finish.set_shader_parameter("part_transform",building.global_transform.affine_inverse()*mesh.global_transform)
    finish.set_shader_parameter("building_kind",kind);mesh.set_surface_override_material(surface,finish)
  if id=="S06":_community_porch(world,root)
  else:_shop_porch(world,root,id)

static func _ground_prop(world: WorldBuilder,parent: Node3D,id: String,at: Vector3,height: float) -> Node3D:
 var node: Node3D=world.spawn(id,at,0,0,parent)
 if node==null:return null
 node.scale*=height/maxf(WorldBuilder.local_aabb(node).size.y,.001)
 var support_height: float=0.0
 var building: Node3D=parent.get_parent() as Node3D
 for mesh: MeshInstance3D in WorldBuilder.find_meshes(building):
  if parent.is_ancestor_of(mesh):continue
  var measured: float=WorldBuilder.surface_height(mesh,Vector2(node.global_position.x,node.global_position.z),.40)
  if is_finite(measured):support_height=maxf(support_height,measured)
 WorldBuilder.rest_on(node,support_height,.006)
 HouseBuilder.toonify(node);node.set_meta("art_grounded",true);return node

static func _community_porch(world: WorldBuilder,root: Node3D) -> void:
 _ground_prop(world,root,"W05_hydrangea_pot",Vector3(-4.6,0,3.5),.85)
 _ground_prop(world,root,"A15_potted_plant",Vector3(-5.18,0,3.32),.52)
 var board:=Node3D.new();board.name="CommunityNoticeCase";board.position=Vector3(4.72,1.68,2.72);root.add_child(board)
 box(board,"TimberCase",Vector3(1.30,1.13,.12),Vector3.ZERO,wood(Color(.46,.34,.23)))
 box(board,"GreenBacking",Vector3(1.17,1.0,.012),Vector3(0,0,.067),matte(Color(.35,.50,.42)))
 for index in 2:
  var page: Node3D=sketch(board,"NeighbourNote_%d"%index,Vector3(-.285+index*.57,.03,.085),Vector2(.48,.67),index)
  page.rotation.z=deg_to_rad(-2.0 if index==0 else 1.0)
 var hood:=box(board,"RainHood",Vector3(1.46,.055,.40),Vector3(0,.62,.06),wood(Color(.40,.30,.23)));hood.rotation.x=-.12
 ClearSignage.paper_tag(board,"NoticeTitle","夏祭一起做",Vector3(0,.44,.14),Vector2(.70,.13),0,.074)
 # Slatted umbrella holder against the wall, outside stair and accessible ramp footprints.
 var holder:=box(root,"UmbrellaHolder",Vector3(.28,.55,.28),Vector3(-3.7,.275,3.15),wood(Color(.43,.33,.24)))
 for index in 3:rod(root,"Umbrella_%d"%index,Vector3(-3.79+index*.08,.48,3.15),Vector3(-3.75+index*.08,.91,3.15),.012,matte(Color(.29,.37,.41)))
 holder.set_meta("porch_accessory",true)

static func _shop_porch(world: WorldBuilder,root: Node3D,id: String) -> void:
 var metal:=matte(Color(.28,.31,.29));var width: float=1.98 if id=="S02" else 3.25
 for side: float in [-1.0,1.0]:
  rod(root,"AwningBrace_%d"%int(side),Vector3(side*width,2.13,2.60),Vector3(side*width,2.60,3.65),.015,metal)
  rod(root,"AwningBracket_%d"%int(side),Vector3(side*width,2.13,2.60),Vector3(side*width,2.89,2.60),.018,metal)
 if id=="S02":
  _ground_prop(world,root,"A15_potted_plant",Vector3(-2.03,0,3.07),.54)
  _ground_prop(world,root,"W05_hydrangea_pot",Vector3(-2.02,0,3.56),.52)
 else:
  _ground_prop(world,root,"A15_potted_plant",Vector3(-3.38,0,2.68),.66)
  var bin:=box(root,"PaperBagBox",Vector3(.30,.32,.27),Vector3(3.23,.16,2.64),wood(Color(.56,.42,.27)))
  folded_cloth(root,"ReturnedShopCloth",Vector3(3.23,.32,2.64),Color(.30,.42,.36),bin)
