class_name LakesideMaterials
extends RefCounted
const WOOD_SHADER: Shader = preload("res://shaders/aged_wood.gdshader")
const STONE_SHADER: Shader = preload("res://shaders/creek_stone.gdshader")
const SIGN_SHADER: Shader = preload("res://shaders/aged_sign_face.gdshader")
const WOOD_TEX: String = "res://assets/textures/lakeside_polish/bridge_wood.png"
const STONE_TEX: String = "res://assets/textures/lakeside_polish/creek_stone.png"
const SIGN_TEX: String = "res://assets/textures/lakeside_polish/sign_face.png"
static func wood(origin: Vector3,dark: bool=false,vertical: bool=false) -> ShaderMaterial:
    var material: ShaderMaterial=ShaderMaterial.new()
    material.shader=WOOD_SHADER
    material.set_shader_parameter("painted_tex",load(WOOD_TEX) as Texture2D)
    material.set_shader_parameter("reference_origin",origin)
    material.set_shader_parameter("tint",Color(.64,.68,.65) if dark else Color(.92,.88,.82))
    material.set_shader_parameter("vertical_grain",1.0 if vertical else 0.0)
    material.set_shader_parameter("wear_strength",.38)
    return material
static func decorate_bridge(root: Node3D) -> void:
    if root==null:return
    var light: ShaderMaterial=wood(root.global_position)
    var dark: ShaderMaterial=wood(root.global_position,true)
    for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
        if not mesh.visible:continue
        var all_wood: bool=true
        for surface: int in range(mesh.mesh.get_surface_count()):
            var original: Material=mesh.get_active_material(surface)
            var name: String=original.resource_name.to_lower() if original!=null else ""
            if name.contains("wood"):
                mesh.set_surface_override_material(surface,dark if name.contains("dark") else light)
            else:all_wood=false
        if all_wood:mesh.material_override=null
    root.set_meta("bridge_wood_aged",true)
static func stone(root: Node3D,index: int) -> void:
    if root==null:return
    var material: ShaderMaterial=ShaderMaterial.new()
    material.shader=STONE_SHADER
    material.set_shader_parameter("painted_tex",load(STONE_TEX) as Texture2D)
    material.set_shader_parameter("tint",[Color(.90,.94,1),Color(1,.96,.90),Color(.87,.90,.92)][index%3])
    material.set_shader_parameter("water_level",LakesideLayout.WATER_Y)
    for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):mesh.material_override=material
static func sign_face() -> ShaderMaterial:
    var material: ShaderMaterial=ShaderMaterial.new()
    material.shader=SIGN_SHADER
    material.set_shader_parameter("painted_tex",load(SIGN_TEX) as Texture2D)
    return material
