extends RefCounted
## A loading-time height map of actual canopy surface triangles. This is numeric render
## data (metres), not a colour bitmap or an authored replacement texture.
const SIZE := Vector2i(65,25)
const INVALID_HEIGHT := -1000.0
const EDGE_INSET := .002
const SURFACE_MARGIN := .002
var model_ref: WeakRef
var rectangle := Rect2()
var heights := PackedFloat32Array()
var texture: ImageTexture
var samples := 0
var valid_samples := 0
var triangles := 0

func build(model: Node3D) -> bool:
	model_ref=weakref(model)
	var bounds: AABB=WorldBuilder.local_aabb(model)
	var minimum_y: float=bounds.end.y-.18
	var faces:=PackedVector3Array()
	var low:=Vector2(INF,INF)
	var high:=Vector2(-INF,-INF)
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
		if mesh.mesh==null:continue
		var relative: Transform3D=model.global_transform.affine_inverse()*mesh.global_transform
		var source: PackedVector3Array=mesh.mesh.get_faces()
		for index: int in range(0,source.size()-2,3):
			var a: Vector3=relative*source[index]
			var b: Vector3=relative*source[index+1]
			var c: Vector3=relative*source[index+2]
			var normal: Vector3=(b-a).cross(c-a).normalized()
			# Mesh winding varies by importer; both cloth skins are real geometry.
			# The downward query takes the highest surface, never the underside.
			if absf(normal.y)<.5 or minf(a.y,minf(b.y,c.y))<minimum_y:continue
			faces.append_array(PackedVector3Array([a,b,c]))
			for point: Vector3 in [a,b,c]:
				low=low.min(Vector2(point.x,point.z))
				high=high.max(Vector2(point.x,point.z))
	triangles=int(faces.size()/3.0)
	if faces.is_empty():return false
	low+=Vector2.ONE*EDGE_INSET
	high-=Vector2.ONE*EDGE_INSET
	rectangle=Rect2(low,high-low)
	if not rectangle.has_area():return false
	var tree:=TriangleMesh.new()
	tree.create_from_faces(faces)
	heights.resize(SIZE.x*SIZE.y)
	heights.fill(INVALID_HEIGHT)
	samples=0
	valid_samples=0
	for row: int in SIZE.y:
		for column: int in SIZE.x:
			var uv:=Vector2(float(column)/float(SIZE.x-1),float(row)/float(SIZE.y-1))
			var xz: Vector2=rectangle.position+uv*rectangle.size
			var hit: Dictionary=tree.intersect_segment(Vector3(xz.x,bounds.end.y+.10,xz.y),Vector3(xz.x,minimum_y,xz.y))
			samples+=1
			if not hit.is_empty():
				heights[row*SIZE.x+column]=(hit.position as Vector3).y
				valid_samples+=1
	if valid_samples==0:return false
	var image:=Image.create_from_data(SIZE.x,SIZE.y,false,Image.FORMAT_RF,heights.to_byte_array())
	texture=ImageTexture.create_from_image(image)
	return true

func model() -> Node3D:
	return model_ref.get_ref() as Node3D if model_ref!=null else null

func local_height(point: Vector2) -> float:
	if texture==null or not rectangle.has_point(point):return -INF
	var grid: Vector2=(point-rectangle.position)/rectangle.size*Vector2(SIZE-Vector2i.ONE)
	var column: int=clampi(int(floorf(grid.x)),0,SIZE.x-2)
	var row: int=clampi(int(floorf(grid.y)),0,SIZE.y-2)
	var fraction: Vector2=grid-Vector2(column,row)
	var a: float=heights[row*SIZE.x+column]
	var b: float=heights[row*SIZE.x+column+1]
	var c: float=heights[(row+1)*SIZE.x+column]
	var d: float=heights[(row+1)*SIZE.x+column+1]
	# A missing real triangle never becomes an invented interpolated shelter.
	if minf(minf(a,b),minf(c,d))<0:return -INF
	return lerpf(lerpf(a,b,fraction.x),lerpf(c,d,fraction.x),fraction.y)

func sheltered_at(world_point: Vector3) -> bool:
	var node: Node3D=model()
	if not is_instance_valid(node) or not node.is_visible_in_tree():return false
	var point: Vector3=node.to_local(world_point)
	var height: float=local_height(Vector2(point.x,point.z))
	return is_finite(height) and point.y<height-SURFACE_MARGIN

func metadata() -> Dictionary:
	return {"samples":samples,"valid_samples":valid_samples,"triangles":triangles,"rectangle":rectangle,"size":SIZE,"edge_inset_m":EDGE_INSET,"surface_margin_m":SURFACE_MARGIN}
