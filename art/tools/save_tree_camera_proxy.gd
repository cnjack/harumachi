extends SceneTree
func _initialize() -> void:_start.call_deferred()
func _start() -> void:
 var input: String="";var output: String=""
 for arg: String in OS.get_cmdline_user_args():
  if arg.begins_with("--input="):input=arg.substr(8)
  if arg.begins_with("--out="):output=arg.substr(6)
 if input.is_empty() or output.is_empty():quit(2);return
 var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input));var faces:=PackedVector3Array()
 for index: Variant in data.indices:
  var point: Array=data.vertices[int(index)];faces.append(Vector3(float(point[0]),float(point[1]),float(point[2])))
 var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);shape.backface_collision=true
 shape.set_meta("visual_bark_sha256",str(data.source_sha256));shape.set_meta("camera_proxy_triangles",faces.size()/3)
 shape.set_meta("visual_to_proxy_p99_m",float(data.metrics.visual_to_proxy_p99_m));shape.set_meta("visual_to_proxy_max_m",float(data.metrics.visual_to_proxy_max_m));shape.set_meta("proxy_to_visual_max_m",float(data.metrics.proxy_to_visual_max_m))
 DirAccess.make_dir_recursive_absolute(output.get_base_dir());var result: Error=ResourceSaver.save(shape,output)
 if result!=OK:quit(3);return
 print("TREE_CAMERA_RESOURCE ",faces.size()/3," triangles");quit(0)
