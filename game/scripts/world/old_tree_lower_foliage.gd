extends RefCounted
## Small leaf sprays attached to measured green lower-bough surfaces, not a filled crown.
const ATLAS_PATH := "res://assets/textures/tree_detail/old_tree_sprigs.png"
static var cached_mesh: ArrayMesh
static var cached_material: StandardMaterial3D
static var sprig_count:=0

static func _light_gap(point: Vector3) -> bool:
 var projected:=Vector2(point.x-.5165*(6.5-point.y),-point.z-.7375*(6.5-point.y))
 return pow((projected.x+1.7)/.90,2.0)+pow((projected.y-.8)/1.12,2.0)<1.0 or pow((projected.x-1.9)/.80,2.0)+pow((projected.y+1.3)/.95,2.0)<1.0

static func _build() -> void:
 var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/old_tree_lower_boughs.json"))
 var rng:=RandomNumberGenerator.new();rng.seed=121006
 var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array();var indices:=PackedInt32Array()
 for anchor: Dictionary in data.anchors:
  var at: Array=anchor.at;var point:=Vector3(float(at[0]),float(at[1]),float(at[2]))
  if _light_gap(point):continue
  var radial:=Vector3(point.x,0,point.z).normalized()
  for spray: int in 3:
   var centre: Vector3=point+radial*rng.randf_range(.04,.17)+Vector3(rng.randf_range(-.09,.09),rng.randf_range(-.13,.02),rng.randf_range(-.09,.09))
   if _light_gap(centre):continue
   var normal: Vector3=(radial.rotated(Vector3.UP,rng.randf_range(-.85,.85))+Vector3(0,-.25,0)).normalized()
   var right: Vector3=Vector3.UP.cross(normal).normalized();var up: Vector3=normal.cross(right).normalized()
   var angle: float=rng.randf_range(-.65,.65);right=right.rotated(normal,angle);up=up.rotated(normal,angle)
   var half_width: float=rng.randf_range(.16,.23);var half_height: float=half_width*.85;var first: int=vertices.size()
   vertices.append_array(PackedVector3Array([centre-right*half_width-up*half_height,centre+right*half_width-up*half_height,centre+right*half_width+up*half_height,centre-right*half_width+up*half_height]))
   for corner: int in 4:normals.append(normal)
   var u: float=float(rng.randi_range(0,1))*.5
   uvs.append_array(PackedVector2Array([Vector2(u+.025,.475),Vector2(u+.475,.475),Vector2(u+.475,.025),Vector2(u+.025,.025)]))
   indices.append_array(PackedInt32Array([first,first+1,first+2,first,first+2,first+3]));sprig_count+=1
 var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
 cached_mesh=ArrayMesh.new();cached_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 cached_material=StandardMaterial3D.new();cached_material.resource_name="LowerBoughExistingAlphaSprigs";cached_material.albedo_texture=load(ATLAS_PATH);cached_material.albedo_color=Color(.74,.86,.73,1)
 cached_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;cached_material.alpha_scissor_threshold=.42;cached_material.cull_mode=BaseMaterial3D.CULL_DISABLED;cached_material.roughness=1.;cached_material.metallic=0.
 cached_mesh.surface_set_material(0,cached_material)

static func attach(tree: Node3D) -> void:
 if cached_mesh==null:_build()
 var node:=MeshInstance3D.new();node.name="Foliage_LowerBoughSprigs";node.mesh=cached_mesh;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
 node.set_meta("branch_supported_sprigs",sprig_count);node.set_meta("keeps_original_light_shafts",true);tree.add_child(node)
 tree.set_meta("lower_foliage_sprigs",sprig_count)
