class_name MaterialChoiceProfile
extends RefCounted
## User-selected default look. The review tool keeps its original A/B/C/D references.
const GRASS: Shader = preload("res://shaders/material_options/grass.gdshader")
const WATER: Shader = preload("res://shaders/material_options/water.gdshader")
const SURFACE: Shader = preload("res://shaders/material_options/surface.gdshader")

static func selection() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/material_selection.json"))
    return parsed as Dictionary if parsed is Dictionary else {}

static func _linear(value: Vector3) -> Vector3:
    var color: Color = Color(value.x,value.y,value.z).srgb_to_linear()
    return Vector3(color.r,color.g,color.b)

static func apply(world: WorldBuilder) -> Dictionary:
    var before_geometry: String = _geometry_signature(world)
    var chosen: Dictionary = selection()
    var cache: Dictionary = {}
    var counts: Dictionary = {"water":0,"grass_blades":0,"grass_ground":0}
    for candidate: Node in world.find_children("*","GeometryInstance3D",true,false):
        var node: GeometryInstance3D = candidate as GeometryInstance3D
        var original: ShaderMaterial = node.material_override as ShaderMaterial
        if original == null or original.shader == null: continue
        var path: String = original.shader.resource_path
        var kind: String = ""
        if chosen.get("water","A") == "B" and path.ends_with("lakeside_water.gdshader"): kind = "water"
        elif chosen.get("grass","A") == "B" and path.ends_with("grass_blade.gdshader"): kind = "grass_blades"
        elif chosen.get("grass","A") == "B" and path.ends_with("ground.gdshader"):
            var lawn: Variant = original.get_shader_parameter("lawn_mode")
            if lawn != null and lawn == true: kind = "grass_ground"
        if kind.is_empty(): continue
        var key: String = "%s:%d" % [kind,original.get_instance_id()]
        var material: ShaderMaterial
        if cache.has(key): material = cache[key] as ShaderMaterial
        else:
            material = ShaderMaterial.new()
            if kind == "water":
                material = original.duplicate(true) as ShaderMaterial
                material.shader = WATER
                material.set_shader_parameter("deep_color",Color(.035,.21,.34))
                material.set_shader_parameter("shallow_color",Color(.43,.79,.70))
                material.set_shader_parameter("foam_color",Color(.87,.97,.95))
                material.set_shader_parameter("flow_highlight",.24)
                material.set_shader_parameter("foam_amount",.35)
                material.set_shader_parameter("shallow_opacity",.62)
            elif kind == "grass_blades":
                material.shader = GRASS
                material.set_shader_parameter("height_scale",.70)
                material.set_shader_parameter("wind_scale",.70)
                material.set_shader_parameter("root_col",_linear(Vector3(.12,.27,.10)))
                material.set_shader_parameter("fresh_col",_linear(Vector3(.50,.74,.26)))
                material.set_shader_parameter("deep_col",_linear(Vector3(.24,.48,.21)))
            else:
                material.shader = SURFACE
                material.set_shader_parameter("surface_kind",4)
                material.set_shader_parameter("base_color",Color(.37,.55,.23))
                material.set_shader_parameter("tile",2.6)
                if original.get_shader_parameter("landscape_contours")==true:
                    material.set_shader_parameter("landscape_contours",true)
                    material.set_shader_parameter("terrain_origin",original.get_shader_parameter("terrain_origin"))
            cache[key] = material
        node.material_override = material
        node.extra_cull_margin = maxf(node.extra_cull_margin,.85)
        counts[kind] = int(counts[kind])+1
        if kind == "water":
            world.farm.water_mat = material
            world.farm.lakeside.water_mat = material
    world.set_meta("material_selection",chosen)
    world.set_meta("material_selection_counts",counts)
    world.set_meta("material_selection_geometry_unchanged",before_geometry==_geometry_signature(world))
    return counts

static func _geometry_signature(world: WorldBuilder) -> String:
    var signature: PackedStringArray = []
    for mesh_node: Node in world.find_children("*","MeshInstance3D",true,false):
        var mesh: MeshInstance3D = mesh_node as MeshInstance3D
        if mesh.mesh != null: signature.append("m:%d:%d" % [mesh.get_instance_id(),mesh.mesh.get_instance_id()])
    for multimesh_node: Node in world.find_children("*","MultiMeshInstance3D",true,false):
        var instance: MultiMeshInstance3D = multimesh_node as MultiMeshInstance3D
        if instance.multimesh != null: signature.append("g:%d:%d:%d" % [instance.get_instance_id(),instance.multimesh.get_instance_id(),instance.multimesh.instance_count])
    for collision_node: Node in world.find_children("*","CollisionShape3D",true,false):
        var shape: CollisionShape3D = collision_node as CollisionShape3D
        if shape.shape != null: signature.append("c:%d:%d:%s" % [shape.get_instance_id(),shape.shape.get_instance_id(),str(shape.global_transform)])
    signature.sort()
    return str(hash(signature))
