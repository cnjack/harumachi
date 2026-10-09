extends Node
## Opt-in material choices on the real Main scene; game geometry and save state stay separate.
const FAMILIES: Array[String] = ["地面","水面","草地","沙地","木地板","石头地板"]
const LETTERS: Array[String] = ["A","B","C","D"]
const LOOKS: Array[String] = ["原始版本","清爽平涂","手绘夏日","清凉淡色"]
const SELECTION_KEYS: Array[String] = ["ground","water","grass","sand","wood_floor","stone_floor"]
const TEXTURES: Dictionary = {0:"dirt",3:"sand",4:"wood",5:"stone"}
const SURFACE_KINDS: Dictionary = {0:0,3:1,4:2,5:3,2:4}
const SURFACE: Shader = preload("res://shaders/material_options/surface.gdshader")
const GRASS: Shader = preload("res://shaders/material_options/grass.gdshader")
const WATER: Shader = preload("res://shaders/material_options/water.gdshader")
const SPOTS: Array[Dictionary] = [
    {"region":"farm","at":Vector3(-19,.1,.4),"camera":Vector3(-17,2.1,3.8),"focus":Vector3(-21,.06,.6)},
    {"region":"farm","at":Vector3(4,.1,11.7),"camera":Vector3(9,3.8,10.8),"focus":Vector3(4,.05,19)},
    {"region":"farm","at":Vector3(-14,.1,8),"camera":Vector3(-18,2.0,5),"focus":Vector3(-13,.28,10.7)},
    {"region":"town","at":Vector3(-6,.1,2.4),"camera":Vector3(-5.1,1.7,2),"focus":Vector3(-6.8,.30,4.4)},
    {"region":"house","at":Vector3(-4,.05,0),"camera":Vector3(-1.1,4.0,4.4),"focus":Vector3(-4,.05,-.1)},
    {"region":"town","at":Vector3(-16,.1,-11.5),"camera":Vector3(-18,2.9,-8.6),"focus":Vector3(-12,.08,-14.1)}
]
var main: Node3D
var world: WorldBuilder
var bindings: Array[Dictionary] = []
var choices: Array[int] = [0,0,0,0,0,0]
var family: int = 0
var panel: PanelContainer
var heading: Label
var caption: Label
var buttons: Array[Array] = []
var output: String = ""
var record_mode: bool = false
var still_mode: bool = false
var shot_seconds: float = 3.0
var camera_offset: Vector3
var camera_focus: Vector3
var samples: Array[Dictionary] = []
var geometry_contract: String = ""

func _ready() -> void:
    main = get_parent() as Node3D
    world = main.get("world") as WorldBuilder
    var selected: Dictionary = MaterialChoiceProfile.selection()
    for selection_index: int in range(6):
        choices[selection_index] = maxi(0,LETTERS.find(str(selected.get(SELECTION_KEYS[selection_index],"A"))))
    for argument: String in OS.get_cmdline_user_args():
        if argument == "--record": record_mode = true
        elif argument == "--still": still_mode = true
        elif argument.begins_with("--out="): output = argument.substr(6)
        elif argument.begins_with("--seconds="): shot_seconds = float(argument.substr(10))
        elif argument.begins_with("--family="): family = int(argument.substr(9))
        elif argument.begins_with("--variant="): choices.fill(int(argument.substr(10)))
    family = clampi(family,0,5)
    if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
    GameState.clock_paused = true
    GameState.minute = 630.0
    GameState.weather = "sunny"
    var ui: Node = main.get("ui") as Node
    ui.call("set_hud_visible",false)
    var ui_panels: RefCounted = ui.get("panels") as RefCounted
    ui_panels.call("set_cards_visible",false)
    (main.get("player") as Node3D).visible = false
    (main.get("player") as Node).process_mode = Node.PROCESS_MODE_DISABLED
    (main.get("rig") as Node).process_mode = Node.PROCESS_MODE_DISABLED
    for npc: Node3D in (main.get("npcs") as Dictionary).values():
        npc.visible = false
        npc.process_mode = Node.PROCESS_MODE_DISABLED
    _collect_bindings()
    geometry_contract = _geometry_contract()
    var totals: Array[int] = [0,0,0,0,0,0]
    for binding: Dictionary in bindings: totals[int(binding.family)] += 1
    for count: int in totals:
        if count == 0:
            push_error("A material family has no real-scene bindings: " + str(totals))
            get_tree().quit(3)
            return
    print("MATERIAL_OPTIONS bindings=",totals," engine=",Engine.get_version_info().string)
    _interface()
    for kind: int in range(6): _apply(kind,choices[kind])
    _focus(family)
    if record_mode: _record.call_deferred()
    elif still_mode: _still.call_deferred()

func _collect_bindings() -> void:
    for candidate: Node in world.find_children("*","GeometryInstance3D",true,false):
        var node: GeometryInstance3D = candidate as GeometryInstance3D
        var original: ShaderMaterial = node.material_override as ShaderMaterial
        if original == null or original.shader == null: continue
        var shader_path: String = original.shader.resource_path
        var kind: int = -1
        var blade: bool = false
        if shader_path.ends_with("lakeside_water.gdshader"): kind = 1
        elif shader_path.ends_with("grass_blade.gdshader"):
            kind = 2
            blade = true
        elif shader_path.ends_with("lakeside_path.gdshader"): kind = 0
        elif shader_path.ends_with("house_floor.gdshader"):
            var mode: Variant = original.get_shader_parameter("floor_mode")
            if mode == null or int(mode) in [0,3]: kind = 4
        elif shader_path.ends_with("ground.gdshader"):
            var lawn: Variant = original.get_shader_parameter("lawn_mode")
            var texture: Texture2D = original.get_shader_parameter("albedo_tex") as Texture2D
            if lawn != null and lawn == true: kind = 2
            elif node.name == "IncomingRoad": continue
            elif node.name == "SandpitSurface" or str(node.name).begins_with("RoadShoulder"): kind = 3
            elif texture != null and texture.resource_path.get_file().contains("stone"): kind = 5
            else: kind = 0
        if kind < 0: continue
        var binding: Dictionary = {"node":node,"original":original,"family":kind,"blade":blade,"margin":node.extra_cull_margin,"materials":[original]}
        for variant: int in range(1,4):
            (binding.materials as Array).append(_make_material(binding,variant))
        bindings.append(binding)

func _make_material(binding: Dictionary, variant: int) -> ShaderMaterial:
    var kind: int = int(binding.family)
    var material: ShaderMaterial = ShaderMaterial.new()
    if kind == 1:
        material = (binding.original as ShaderMaterial).duplicate(true) as ShaderMaterial
        material.shader = WATER
        var deep: Array[Color] = [Color(.10,.43,.51),Color(.06,.50,.58),Color(.055,.32,.48)]
        var shallow: Array[Color] = [Color(.34,.68,.62),Color(.35,.78,.69),Color(.24,.60,.65)]
        material.set_shader_parameter("deep_color",deep[variant-1])
        material.set_shader_parameter("shallow_color",shallow[variant-1])
        material.set_shader_parameter("foam_color",Color(.87,.97,.95))
        material.set_shader_parameter("flow_highlight",[.24,.48,.32][variant-1])
        material.set_shader_parameter("foam_amount",[.35,.63,.47][variant-1])
    elif bool(binding.blade):
        material.shader = GRASS
        material.set_shader_parameter("height_scale",[.70,1.22,1.62][variant-1])
        material.set_shader_parameter("wind_scale",[.70,1.15,.90][variant-1])
        material.set_shader_parameter("root_col",_linear_color(Vector3(.12,.27,.10)))
        material.set_shader_parameter("fresh_col",_linear_color([Vector3(.50,.74,.26),Vector3(.64,.87,.25),Vector3(.43,.73,.43)][variant-1]))
        material.set_shader_parameter("deep_col",_linear_color([Vector3(.24,.48,.21),Vector3(.20,.53,.25),Vector3(.16,.43,.32)][variant-1]))
    else:
        material.shader = SURFACE
        material.set_shader_parameter("surface_kind",int(SURFACE_KINDS[kind]))
        if variant >= 2 and TEXTURES.has(kind):
            var suffix: String = "c" if variant == 2 else "d"
            material.set_shader_parameter("albedo_tex",load("res://assets/textures/material_options/%s_%s.png" % [str(TEXTURES[kind]),suffix]))
            material.set_shader_parameter("use_paint",true)
            material.set_shader_parameter("base_color",Color.WHITE)
        else:
            var palette: Dictionary = {0:Color(.72,.57,.37),3:Color(.88,.82,.64),4:Color(.68,.46,.25),5:Color(.55,.59,.63),2:Color(.33,.50,.23)}
            var color: Color = palette[kind]
            if kind == 2: color = [Color(.37,.55,.23),Color(.40,.61,.23),Color(.29,.50,.35)][variant-1]
            material.set_shader_parameter("base_color",color)
        material.set_shader_parameter("tile",2.6 if kind != 4 else 2.2)
    return material

func _linear_color(value: Vector3) -> Vector3:
    var linear: Color = Color(value.x,value.y,value.z).srgb_to_linear()
    return Vector3(linear.r,linear.g,linear.b)

func _geometry_contract() -> String:
    var parts: PackedStringArray = []
    for mesh_node: Node in world.find_children("*","MeshInstance3D",true,false):
        var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
        if mesh_instance.mesh != null: parts.append("m:%d:%d" % [mesh_instance.get_instance_id(),mesh_instance.mesh.get_instance_id()])
    for multimesh_node: Node in world.find_children("*","MultiMeshInstance3D",true,false):
        var multimesh_instance: MultiMeshInstance3D = multimesh_node as MultiMeshInstance3D
        if multimesh_instance.multimesh != null: parts.append("g:%d:%d:%d" % [multimesh_instance.get_instance_id(),multimesh_instance.multimesh.get_instance_id(),multimesh_instance.multimesh.instance_count])
    for collision_node: Node in world.find_children("*","CollisionShape3D",true,false):
        var shape: CollisionShape3D = collision_node as CollisionShape3D
        if shape.shape != null: parts.append("c:%d:%d:%s" % [shape.get_instance_id(),shape.shape.get_instance_id(),str(shape.global_transform)])
    parts.sort()
    return str(hash(parts))

func _apply(kind: int, variant: int) -> void:
    choices[kind] = clampi(variant,0,3)
    for binding: Dictionary in bindings:
        if int(binding.family) != kind: continue
        var node: GeometryInstance3D = binding.node
        var material: ShaderMaterial = (binding.materials as Array)[choices[kind]] as ShaderMaterial
        node.material_override = material
        node.extra_cull_margin = float(binding.margin) if choices[kind] == 0 else maxf(float(binding.margin),.85)
        if kind == 1:
            world.farm.water_mat = material
            world.farm.lakeside.water_mat = material
    if _geometry_contract() != geometry_contract:
        push_error("Material switch changed original scene geometry or collision")
        get_tree().quit(4)
    _refresh_buttons()
    _save_choices()

func _choose(kind: int, variant: int) -> void:
    if record_mode: return
    _apply(kind,variant)
    if family != kind: _focus(kind)
    else: _refresh_caption()

func _focus(kind: int) -> void:
    family = kind
    var spec: Dictionary = SPOTS[kind]
    var rig: CameraRig = main.get("rig") as CameraRig
    var player: Node3D = main.get("player") as Node3D
    var origin: Vector3 = FarmBuilder.ORIGIN if str(spec.region)=="farm" else (HouseBuilder.ORIGIN if str(spec.region)=="house" else Vector3.ZERO)
    if str(spec.region)=="house":
        main.call("_put_in_room",origin+spec.at)
        world.house.update_cutaway("bedroom",false)
    else:
        main.set("in_room",false)
        main.set("room_kind","")
        GameState.player_in_room = false
        world.set_indoor_look(false)
        world.set_region(str(spec.region))
        player.global_position = origin+spec.at
    rig.process_mode = Node.PROCESS_MODE_DISABLED
    rig.cam.fov = 48.0
    camera_focus = origin+spec.focus
    camera_offset = origin+spec.camera-camera_focus
    _camera(0.0)
    world.update_time(GameState.minute,"sunny",true)
    _refresh_caption()
    _save_choices()

func _camera(angle: float) -> void:
    var rig: CameraRig = main.get("rig") as CameraRig
    rig.cam.global_position = camera_focus+camera_offset.rotated(Vector3.UP,angle)
    rig.cam.look_at(camera_focus,Vector3.UP)

func _interface() -> void:
    var layer: CanvasLayer = CanvasLayer.new()
    layer.layer = 80
    add_child(layer)
    panel = PanelContainer.new()
    panel.position = Vector2(22,22)
    panel.custom_minimum_size = Vector2(390,0)
    panel.theme = UIKitStyles.theme()
    panel.add_theme_stylebox_override("panel",UIKitStyles.surface("hud",18))
    layer.add_child(panel)
    var column: VBoxContainer = VBoxContainer.new()
    column.add_theme_constant_override("separation",10)
    panel.add_child(column)
    heading = UIKitComponents.label("当前场景 · 材质选择","body")
    column.add_child(heading)
    caption = UIKitComponents.label("","caption")
    column.add_child(caption)
    for kind: int in range(6):
        var row: HBoxContainer = HBoxContainer.new()
        row.add_theme_constant_override("separation",6)
        column.add_child(row)
        var category_button: Button = UIKitComponents.button(FAMILIES[kind],_focus.bind(kind),"quiet",true)
        category_button.custom_minimum_size = Vector2(112,36)
        row.add_child(category_button)
        var family_buttons: Array = []
        for variant: int in range(4):
            var button: Button = UIKitComponents.button(LETTERS[variant],_choose.bind(kind,variant),"secondary",true)
            button.custom_minimum_size = Vector2(52,36)
            button.tooltip_text = LOOKS[variant]
            row.add_child(button)
            family_buttons.append(button)
        buttons.append(family_buttons)
    column.add_child(UIKitComponents.label("A 原始  B 平涂  C 夏日  D 淡色","caption"))
    column.add_child(UIKitComponents.label("F1–F6 选表面 · 1–4 选风格\n右键拖动看角度 · 滚轮推近\nH 隐藏面板 · R 全部回到原始 A","caption"))

func _refresh_buttons() -> void:
    for kind: int in range(buttons.size()):
        for variant: int in range(4):
            UIKitComponents.style_button(buttons[kind][variant] as Button,"primary" if choices[kind]==variant else "secondary",true)
    _refresh_caption()

func _refresh_caption() -> void:
    if caption != null: caption.text = "%s · %s %s" % [FAMILIES[family],LETTERS[choices[family]],LOOKS[choices[family]]]

func _save_choices() -> void:
    if output.is_empty(): return
    var values: Dictionary = {}
    for kind: int in range(6): values[FAMILIES[kind]] = LETTERS[choices[kind]]
    var file: FileAccess = FileAccess.open(output.path_join("choices.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify({"choices":values,"focused_family":FAMILIES[family],"record_mode":record_mode},"\t"))

func _input(event: InputEvent) -> void:
    if record_mode: return
    if event is InputEventKey:
        var key: InputEventKey = event as InputEventKey
        if not key.pressed or key.echo: return
        if key.keycode >= KEY_F1 and key.keycode <= KEY_F6: _focus(int(key.keycode-KEY_F1))
        elif key.keycode >= KEY_1 and key.keycode <= KEY_4: _choose(family,int(key.keycode-KEY_1))
        elif key.keycode == KEY_LEFT: _choose(family,posmod(choices[family]-1,4))
        elif key.keycode == KEY_RIGHT: _choose(family,posmod(choices[family]+1,4))
        elif key.keycode == KEY_H: panel.visible = not panel.visible
        elif key.keycode == KEY_R:
            for kind: int in range(6): _apply(kind,0)
        else: return
        get_viewport().set_input_as_handled()
        _save_choices()
    elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_RIGHT:
        camera_offset = camera_offset.rotated(Vector3.UP,-(event as InputEventMouseMotion).relative.x*.005)
        _camera(0)
    elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
        var button: InputEventMouseButton = event as InputEventMouseButton
        if button.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
            camera_offset *= .91 if button.button_index==MOUSE_BUTTON_WHEEL_UP else 1.10
            camera_offset = camera_offset.normalized()*clampf(camera_offset.length(),1.8,15.0)
            _camera(0)

func _still() -> void:
    for settle: int in range(8): await get_tree().process_frame
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(output.path_join("scene.png"))
    _write_report(false)
    get_tree().quit(0)

func _record() -> void:
    for kind: int in range(6):
        for reset_kind: int in range(6): _apply(reset_kind,0)
        _focus(kind)
        for variant: int in range(4):
            _apply(kind,variant)
            _refresh_caption()
            var first_frame: int = Engine.get_frames_drawn()
            for frame: int in range(roundi(shot_seconds*30.0)):
                _camera((float(frame)/maxf(shot_seconds*30.0,1.0)-.5)*.045)
                await RenderingServer.frame_post_draw
                if frame == roundi(shot_seconds*15.0):
                    get_viewport().get_texture().get_image().save_png(output.path_join("%02d_%s.png" % [kind+1,LETTERS[variant]]))
            samples.append({"family":FAMILIES[kind],"variant":LETTERS[variant],"label":LOOKS[variant],"first_frame":first_frame,"last_frame":Engine.get_frames_drawn(),"geometry_unchanged":_geometry_contract()==geometry_contract})
            print("MATERIAL_CHOICE ",FAMILIES[kind]," ",LETTERS[variant]," frame=",Engine.get_frames_drawn())
    for restore_kind: int in range(6): _apply(restore_kind,0)
    var restored: bool = true
    for binding: Dictionary in bindings:
        if (binding.node as GeometryInstance3D).material_override != binding.original: restored = false
    _write_report(restored)
    Audio.silence()
    get_tree().quit(0 if restored else 5)

func _write_report(restored: bool) -> void:
    var totals: Array[int] = [0,0,0,0,0,0]
    for binding: Dictionary in bindings: totals[int(binding.family)] += 1
    var file: FileAccess = FileAccess.open(output.path_join("render-state.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"actual_scene":"res://scenes/main.tscn","bindings":totals,"material_choices":24,"samples":samples,"geometry_unchanged":_geometry_contract()==geometry_contract,"original_materials_restored":restored,"isolated_save_dir":OS.get_environment("HARUMACHI_SAVE_DIR")},"\t"))
