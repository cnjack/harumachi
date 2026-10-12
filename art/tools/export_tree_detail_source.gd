extends SceneTree
func _initialize() -> void:_start.call_deferred()
func _start() -> void:
 var output: String=""
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--out="):output=arg.substr(6)
 if output.is_empty():quit(2);return
 var tree: Node3D=(load("res://assets/models/T05_old_shade_tree.glb") as PackedScene).instantiate()
 var bark: MeshInstance3D=tree.find_child("Trunk*",true,false) as MeshInstance3D
 if bark==null:quit(3);return
 var arrays: Array=bark.mesh.surface_get_arrays(0)
 var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var vertices: Array=[]
 for point: Vector3 in points:vertices.append([point.x,point.y,point.z])
 var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
 var uvs: Array=[]
 for point: Vector2 in uv:uvs.append([point.x,point.y])
 var material: StandardMaterial3D=bark.get_active_material(0) as StandardMaterial3D
 if material!=null and material.albedo_texture!=null:material.albedo_texture.get_image().save_png(output.get_base_dir().path_join("bark-source-albedo.png"))
 var file:=FileAccess.open(output,FileAccess.WRITE)
 file.store_string(JSON.stringify({"source_sha256":FileAccess.get_sha256("res://assets/models/T05_old_shade_tree.glb"),"node":str(bark.name),"vertices":vertices,"indices":Array(indices),"uv":uvs,"faces":indices.size()/3,"coordinate_space":"actual Godot bark local vertices and winding"}));file.close();tree.free();quit(0)
