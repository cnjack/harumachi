extends RefCounted
var runner: Node
func _init(value: Node) -> void: runner=value
func run() -> void:
    var main: Node = runner.get("main") as Node
    var world: WorldBuilder = main.get("world") as WorldBuilder
    var centres: Array[float] = []
    var widths: Array[float] = []
    for sample: float in [-24.0,-16.0,-8.0,0.0,8.0,16.0,24.0]:
        centres.append(LakesideLayout.river_z(sample))
        widths.append(LakesideLayout.river_half(sample))
    runner.call("check","LAKESIDE_POLISH","bridge-side watercourse has a real meander",float(centres.max())-float(centres.min())>.9,str(centres))
    runner.call("check","LAKESIDE_POLISH","banks widen and narrow instead of staying parallel",float(widths.max())-float(widths.min())>.35,str(widths))
    var flowers: int = 0
    for candidate: Node in world.farm.find_children("*","Node3D",true,false):
        if str(candidate.get_meta("model_id",""))=="C07_sunflower" and (candidate as Node3D).position.z>16.0: flowers+=1
    runner.call("check","LAKESIDE_POLISH","far-bank sunflowers form sparse groups",flowers<=4,str(flowers))
    var stones_rooted: bool=true
    var creek_count: int=0
    for stone_node: Node in world.farm.lakeside.get_children():
        if not stone_node.has_meta("creek_stone"):continue
        var creek: Node3D=stone_node as Node3D
        var base: float=PropAudit.base_y(creek)
        var probe: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(creek.global_position+Vector3(0,1.5,0),creek.global_position-Vector3(0,3,0),WorldBuilder.L_GROUND)
        var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(probe)
        if hit.is_empty() or absf(base-(hit.position as Vector3).y)>.04:stones_rooted=false
        creek_count+=1
    runner.call("check","LAKESIDE_POLISH","real creek stones meet the physical stream bed",creek_count>=12 and stones_rooted,str(creek_count))
    var shallow: Variant = world.farm.water_mat.get_shader_parameter("shallow_opacity")
    runner.call("check","LAKESIDE_POLISH","water exposes shallows instead of one opaque surface",shallow!=null and float(shallow)<.85)
    var bridge_texture: bool = false
    var bridge: Node3D = world.farm.get_node_or_null("P_bridge") as Node3D
    if bridge != null:
        for mesh: MeshInstance3D in WorldBuilder.find_meshes(bridge):
            for surface: int in mesh.mesh.get_surface_count():
                var material: ShaderMaterial=mesh.get_active_material(surface) as ShaderMaterial
                if material!=null and material.get_shader_parameter("wear_strength")!=null and material.get_shader_parameter("painted_tex")!=null:bridge_texture=true
    runner.call("check","LAKESIDE_POLISH","bridge timber has painted wear and board variation",bridge_texture)
    var sign: Node = world.farm.get_node_or_null("FarmNameSign")
    runner.call("check","LAKESIDE_POLISH","allotment sign has a decorated aged face",sign!=null and sign.has_meta("decorated_sign"))
    var path_wear: bool = false
    for path: Node in world.farm.lakeside.find_children("Shore_or_path_*","MeshInstance3D",true,false):
        var path_material: ShaderMaterial = (path as MeshInstance3D).material_override as ShaderMaterial
        if path_material!=null and path_material.get_shader_parameter("wear_strength")!=null and float(path_material.get_shader_parameter("wear_strength"))>.1:path_wear=true
    runner.call("check","LAKESIDE_POLISH","paths include dry wear and local colour variation",path_wear)
