class_name ClearSignage
extends RefCounted
## Physical lettering with oversampled glyphs; keep world size while increasing raster detail.
static func label(text: String,at: Vector3,yaw: float,em: float=.12,colour: Color=Color(.24,.30,.30)) -> Label3D:
	var glyph:=Label3D.new();glyph.text=text;glyph.font=load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	glyph.font_size=144;glyph.pixel_size=em/144.0;glyph.outline_size=0;glyph.modulate=colour;glyph.double_sided=false
	glyph.position=at;glyph.rotation.y=yaw;glyph.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	glyph.set_meta("clear_lettering",true);return glyph

static func paper_tag(parent: Node3D,name_value: String,text: String,at: Vector3,extent: Vector2,yaw: float=0.0,em: float=.095) -> Label3D:
	var tag:=plate(parent,name_value,extent,at,yaw,Color(.97,.93,.82))
	var surface: StandardMaterial3D=(tag.get_node("Board") as MeshInstance3D).material_override as StandardMaterial3D
	surface.albedo_texture=load("res://assets/ui/paper.jpg") if ResourceLoader.exists("res://assets/ui/paper.jpg") else load("res://assets/ui/paper.png")
	var ink:=label(text,Vector3(0,0,.012),0,em,Color(.25,.28,.26));ink.name="Ink";tag.add_child(ink)
	ink.shaded=true;return ink

static func upgrade_existing(world: WorldBuilder) -> int:
	var count:=0
	for node: Node in world.find_children("*","Label3D",true,false):
		var text:=node as Label3D
		if text.billboard!=BaseMaterial3D.BILLBOARD_DISABLED:continue
		var old_size:=text.font_size
		if old_size<128:
			text.font_size=144;text.pixel_size*=float(old_size)/144.0
		text.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		text.set_meta("clear_lettering",true);count+=1
	return count

static func plate(parent: Node3D,label_name: String,extent: Vector2,at: Vector3,yaw: float,colour: Color) -> Node3D:
	var root:=Node3D.new();root.name=label_name;root.position=at;root.rotation.y=yaw;parent.add_child(root)
	var board:=MeshInstance3D.new();board.name="Board";var mesh:=BoxMesh.new();mesh.size=Vector3(extent.x,extent.y,.018)
	board.mesh=mesh;board.material_override=JapaneseArchitecture._flat(colour);root.add_child(board);return root

static func arrow(parent: Node3D,name_value: String,at: Vector3,left: bool,colour: Color) -> Node3D:
	var root:=Node3D.new();root.name=name_value;root.position=at;parent.add_child(root)
	var corners: Array[Vector2]=[Vector2(-.62,-.11),Vector2(-.62,.11),Vector2(.44,.11),Vector2(.63,0),Vector2(.44,-.11)]
	if left:
		for index: int in corners.size():corners[index].x=-corners[index].x
		corners.reverse()
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: float in [1.0,-1.0]:
		for index: int in corners.size():
			var a: Vector2=corners[index];var b: Vector2=corners[(index+1)%corners.size()]
			for point: Vector2 in ([Vector2.ZERO,a,b] if face>0 else [Vector2.ZERO,b,a]):
				surface.set_normal(Vector3(0,0,face));surface.set_uv(Vector2(point.x+.62,point.y+.11));surface.add_vertex(Vector3(point.x,point.y,face*.014))
	for index: int in corners.size():
		var a: Vector2=corners[index];var b: Vector2=corners[(index+1)%corners.size()]
		var edge: Vector2=b-a;var normal: Vector3=Vector3(-edge.y,edge.x,0).normalized()
		var front_a:=Vector3(a.x,a.y,.014);var back_a:=Vector3(a.x,a.y,-.014)
		var front_b:=Vector3(b.x,b.y,.014);var back_b:=Vector3(b.x,b.y,-.014)
		for point: Vector3 in [front_a,back_a,back_b,front_a,back_b,front_b]:
			surface.set_normal(normal);surface.set_uv(Vector2(point.x+.62,point.y+.11));surface.add_vertex(point)
	var node:=MeshInstance3D.new();node.name="ArrowBoard";node.mesh=surface.commit();root.add_child(node)
	var finish:=ShaderMaterial.new();finish.shader=SurfaceFinish.SHADER;finish.set_shader_parameter("wood_tex",SurfaceFinish.GRAIN)
	finish.set_shader_parameter("part_transform",Transform3D.IDENTITY);finish.set_shader_parameter("base_color",colour);finish.set_shader_parameter("grain_strength",.6)
	node.material_override=finish;return root
