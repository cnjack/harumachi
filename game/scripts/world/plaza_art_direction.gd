class_name PlazaArtDirection
extends RefCounted
## Implement the accepted screenshot paintover with local materials and clear walking space.
const ROOT_COLOUR := Color(.20,.34,.15)
const FRESH_COLOUR := Color(.61,.77,.29)
const DEEP_COLOUR := Color(.29,.49,.26)

static func build(world: WorldBuilder) -> void:
	for child: Node in world.get_children():
		if not child is MeshInstance3D: continue
		var ground:=child as MeshInstance3D
		if not ground.mesh is PlaneMesh or not ground.material_override is ShaderMaterial: continue
		if ground.position.x < -13 or ground.position.x > 17 or ground.position.z < 10 or ground.position.z > 24: continue
		var source:=ground.material_override as ShaderMaterial
		if source.get_shader_parameter("lawn_mode") != true: continue
		var material:=source.duplicate() as ShaderMaterial
		material.set_shader_parameter("root_col",ROOT_COLOUR)
		material.set_shader_parameter("fresh_col",FRESH_COLOUR)
		material.set_shader_parameter("deep_col",DEEP_COLOUR)
		material.set_shader_parameter("lawn_mix",.76)
		material.set_shader_parameter("painted_lawn_mix",.28)
		material.set_shader_parameter("feather",.82)
		ground.material_override=material
		ground.set_meta("plaza_lawn_transition",true)
	var pergola:=world.get_node_or_null("P01") as Node3D
	if pergola:
		for foliage: MeshInstance3D in pergola.find_children("Foliage*","MeshInstance3D",true,false):
			WorldBuilder.make_sway(foliage,.012,.8)
	var fringe:=GrassField.new();fringe.name="PlazaGrassFringe";world.add_child(fringe)
	var keep_out: Array=[]
	for lawn: Array in Layout.LAWNS:
		if float(lawn[0][0])<17: keep_out.append_array(lawn[1])
	var fringe_count:=fringe.lawn([[-6.05,10.3,-5.62,23.65],[10.0,19.0,10.55,23.75]],keep_out,"plaza",9.0,61009)
	world.set_meta("plaza_fringe_clumps",fringe_count)
	var root:=Node3D.new();root.name="PlazaFlowerPatches";world.add_child(root)
	var safety:=MeadowDetails.new();safety.owner_world=world
	var rng:=RandomNumberGenerator.new();rng.seed=109610
	var count:=0
	for patch: Vector2 in [Vector2(-12.55,11.0),Vector2(-12.50,15.9),Vector2(-12.5,18.2),Vector2(-11.8,23.55),Vector2(-6.35,22.7),Vector2(11.0,19.05),Vector2(16.8,20.0),Vector2(16.1,23.5)]:
		for index in 8:
			var at:=patch+Vector2(rng.randf_range(-.45,.45),rng.randf_range(-.70,.70))
			if safety._town_blocked(world,at): continue
			var ground_y:=.012 if at.x<0 else .014
			var plant:=world.spawn("V04_daisy_meadow",Vector3(at.x,ground_y,at.y),rng.randf()*360,0,root,rng.randf_range(.36,.78))
			if plant==null: continue
			plant.name="PlazaFlower_%d"%count
			for mesh: MeshInstance3D in WorldBuilder.find_meshes(plant):
				mesh.visibility_range_end=38;mesh.visibility_range_end_margin=5
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			count+=1
	world.set_meta("plaza_flower_clumps",count)
	world.set_meta("plaza_paintover_reference","20261009")
