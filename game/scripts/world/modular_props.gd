class_name ModularProps
extends RefCounted
## Reusable Hyper3D single parts. Text is projected into real wood, never a paper plate.
const SIZES := {
 "MS01_signpost":Vector3(.16,2.2,.16), "MS02_arrow_board":Vector3(1.1,.26,.05),
 "MS03_garden_board":Vector3(1.15,1.5,.12), "MS04_wall_plaque":Vector3(1.2,.24,.04),
 "MS05_table_sign":Vector3(.44,.30,.18), "MS06_bus_pole":Vector3(.38,2.3,.16),
 "MS07_timetable_case":Vector3(1.1,1.0,.08), "MS08_storage_bay":Vector3(.62,.48,.4),
 "MS09_archive_box":Vector3(.35,.16,.29), "MS10_wrapping_rolls":Vector3(.38,.32,.3),
 "MS11_archive_drawer":Vector3(.52,.18,.65), "MS12_linen_frame":Vector3(.72,1.45,.38),
 "MS13_picture_frame":Vector3(.65,.50,.05),
}
static var masks: Dictionary = {}

static func part(wb: WorldBuilder,parent: Node3D,id: String,label: String,at: Vector3,size: Vector3=Vector3.ZERO,yaw: float=0.) -> Node3D:
 var node: Node3D=wb.spawn(id,at,yaw,0,parent)
 if node==null:return null
 node.name=label
 if size!=Vector3.ZERO:node.scale=size/(SIZES[id] as Vector3)
 node.set_meta("modular_source",id)
 node.set_meta("modular_batch","20261015")
 return node

static func engrave(root: Node3D,text: String,rect: Vector4,two_sided: bool=false,strength: float=.70) -> void:
 if root==null:return
 var key: String=text.md5_text()
 if not masks.has(key):masks[key]=load("res://assets/textures/engraving/"+key+".png")
 var changed:=0
 for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
  for surface: int in mesh.mesh.get_surface_count():
   var source: Material=mesh.get_active_material(surface)
   if not source is ShaderMaterial or source.shader!=FurnitureWoodFinish.SHADER:continue
   var ink: ShaderMaterial=source.duplicate() as ShaderMaterial
   ink.set_meta("engraving_root",root.get_instance_id())
   ink.set_shader_parameter("engraving_enabled",true)
   ink.set_shader_parameter("engraving_mask",masks[key])
   ink.set_shader_parameter("engraving_rect",rect)
   ink.set_shader_parameter("engraving_transform",Projection(root.global_transform.affine_inverse()*mesh.global_transform))
   ink.set_shader_parameter("engraving_two_sided",two_sided)
   ink.set_shader_parameter("engraving_strength",strength)
   mesh.material_override=null;mesh.set_surface_override_material(surface,ink);changed+=1
 root.set_meta("engraved_text",text);root.set_meta("engraving_rect",rect)
 root.set_meta("engraving_two_sided",two_sided);root.set_meta("engraved_surfaces",changed)

static func directions(root: Node3D,captions: Array[String]) -> void:
 var post:=root.find_child("Post",true,false) as Node3D
 if post:post.set_meta("modular_source","MS01_signpost")
 for index: int in mini(3,captions.size()):
  var arrow:=root.find_child("Arrow_%d"%index,true,false) as Node3D
  if arrow:
   arrow.set_meta("modular_source","MS02_arrow_board")
   engrave(arrow,captions[index],Vector4(.12,.13,.46,.14),true)
 root.set_meta("supported_direction_count",mini(3,captions.size()))
 root.set_meta("modular_signpost",true)

static func cubbies(room: InteriorBuilder,parent: Node3D,label: String,at: Vector3,width: float,height: float,columns: int,rows: int,filled: bool=true) -> void:
 var group:=Node3D.new();group.name=label;group.position=at;parent.add_child(group)
 group.set_meta("modular_cabinet",true);group.set_meta("grid",Vector2i(columns,rows))
 var bay_size:=Vector3(width/columns,height/rows,.40)
 for row: int in rows:
  for column: int in columns:
   var bay_at:=Vector3(-width*.5+(column+.5)*bay_size.x,row*bay_size.y,0)
   var bay: Node3D=part(room.wb,group,"MS08_storage_bay","Bay_%d_%d"%[row,column],bay_at,bay_size)
   if not filled or (row*columns+column)%4==3:continue
   var content: String="MS09_archive_box"
   if room.kind=="florist":content="MS10_wrapping_rolls"
   elif room.kind=="zakka":content=["N01_enamel_kettle","W21_tea_tin","W16_handtools_board"][column%3]
   elif room.kind=="home_kazuko":content=["W21_tea_tin","W12_cedar_tray","W25_salt_box"][column%3]
   var content_at: Vector3=bay_at+Vector3(0,bay_size.y*.075,.005)
   var object: Node3D
   if SIZES.has(content):
    var nominal: Vector3=SIZES[content]
    var factor: float=minf((bay_size.x-.07)/nominal.x,minf((bay_size.y-.07)/nominal.y,.30/nominal.z))
    object=part(room.wb,group,content,"Contents_%d_%d"%[row,column],content_at,nominal*minf(1.,factor))
   else:
    object=room.wb.spawn(content,content_at,0,0,group,.40)
    if object:
     var box: AABB=WorldBuilder.local_aabb(object)
     var scale_factor: float=minf((bay_size.x-.08)/box.size.x,minf((bay_size.y-.08)/box.size.y,.29/box.size.z))
     object.scale=Vector3.ONE*minf(.7,scale_factor);object.name="Contents_%d_%d"%[row,column]
   if object:
    var floor_y: float=WorldBuilder.surface_height(bay,Vector2(object.global_position.x,object.global_position.z),bay.global_position.y+bay_size.y*.30)
    WorldBuilder.rest_on(object,floor_y if is_finite(floor_y) else group.global_position.y+content_at.y)
    PublicPlaceArt.supported(object,bay)
    object.set_meta("cabinet_bay",bay.get_instance_id())
 var body:=StaticBody3D.new();body.name=label+"Collision";body.collision_layer=WorldBuilder.L_SOLID;body.collision_mask=0;body.set_meta("model_part",true)
 var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(width,height,.40);shape.shape=box
 body.position=Vector3(0,height*.5,0);body.add_child(shape);group.add_child(body)

static func frame(room: InteriorBuilder,parent: Node3D,label: String,at: Vector3,size: Vector2,image: String,yaw: float=0.) -> void:
 var picture: Node3D=part(room.wb,parent,"MS13_picture_frame",label,at,Vector3(size.x,size.y,.05),rad_to_deg(yaw))
 if picture==null:return
 # Hang the physical rear rim on the actual east wall, with no air gap.
 if is_equal_approx(yaw,-PI*.5):
  picture.position.x=room.spec.size.x*.5-.025
  for wall: MeshInstance3D in WorldBuilder.find_meshes(room):
   if wall.mesh is BoxMesh and wall.get_parent()==room and wall.position.x>room.spec.size.x*.5 and absf(wall.position.z-at.z)<wall.get_aabb().size.z*.5:
    picture.set_meta("wall_mount_surface",picture.get_path_to(wall));break
 var painting:=MeshInstance3D.new();painting.name="ExistingStoryPicture";var quad:=QuadMesh.new();quad.size=Vector2(.65*.75,.50*.70);painting.mesh=quad
 painting.position=Vector3(0,.25,.016)
 var mat:=PublicPlaceArt.matte(Color.WHITE);mat.albedo_texture=load("res://assets/ui/collection/"+image+".jpg");painting.material_override=mat;picture.add_child(painting)
