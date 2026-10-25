class_name LakesideMaterials
extends RefCounted
const WOOD_SHADER: Shader = preload("res://shaders/aged_wood.gdshader")
const STONE_SHADER: Shader = preload("res://shaders/creek_stone.gdshader")
const SIGN_SHADER: Shader = preload("res://shaders/aged_sign_face.gdshader")
const WOOD_TEX: String = "res://assets/textures/lakeside_polish/bridge_wood.png"
const STONE_TEX: String = "res://assets/textures/lakeside_polish/creek_stone.png"
const REFINED_STONE_TEX: String = "res://assets/textures/material_refine_20261011/creek_stone.png"
static var _stone_materials: Dictionary = {}
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
    SurfaceFinish.decorate_timber(root)
    preload("res://scripts/world/farm_timber.gd").apply(root,"P_bridge")
    root.set_meta("bridge_wood_aged",true)
static func stone(root: Node3D,index: int) -> void:
    if root==null:return
    var water_y: float=(root.get_parent() as Node3D).global_position.y+LakesideLayout.WATER_Y
    var texture_path: String=REFINED_STONE_TEX if ResourceLoader.exists(REFINED_STONE_TEX) else STONE_TEX
    var key: String="%s/%d/%.4f"%[texture_path,index%4,water_y]
    if not _stone_materials.has(key):
        var painted: ShaderMaterial=ShaderMaterial.new()
        painted.shader=STONE_SHADER
        painted.set_shader_parameter("painted_tex",load(texture_path) as Texture2D)
        painted.set_shader_parameter("tint",[Color(.91,.95,1),Color(1,.96,.89),Color(.83,.89,.92),Color(.93,.91,.85)][index%4])
        painted.set_shader_parameter("water_level",water_y)
        painted.set_shader_parameter("wet_darkening",.72)
        painted.set_shader_parameter("wet_band_height",.028)
        painted.set_shader_parameter("grain_scale",1.15)
        _stone_materials[key]=painted
    var material: ShaderMaterial=_stone_materials[key] as ShaderMaterial
    for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):mesh.material_override=material
static func sign_face() -> ShaderMaterial:
    var material: ShaderMaterial=ShaderMaterial.new()
    material.shader=SIGN_SHADER
    material.set_shader_parameter("painted_tex",load(SIGN_TEX) as Texture2D)
    return material
