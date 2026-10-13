extends Node3D
## Existing cliff models form a genuine 3D skyline behind the clipped tree belt.
## Only this panorama uses a sky-depth shader; ordinary scene clipping is unchanged.
var world: WorldBuilder
var materials: Array[ShaderMaterial]=[]
var _look_signature: int=0

func build(owner_world: WorldBuilder,farm: bool) -> void:
	world=owner_world;name="DistantMountains"
	var rng:=RandomNumberGenerator.new();rng.seed=131026+int(farm)*77
	var center:=Vector3(58,0,22) if farm else Vector3(0,0,25)
	for layer: int in 2:
		var count: int=10 if layer==0 else 8
		for index: int in count:
			var angle: float=float(index)*TAU/float(count)+float(layer)*.19
			var radius: float=640.0+float(layer)*230.0+rng.randf_range(-35.0,35.0)
			var at: Vector3=center+Vector3(cos(angle)*radius,-24.0-float(layer)*7.0,sin(angle)*radius)
			# The broad X axis follows the ring tangent, rather than pointing at
			# the viewer and reducing every distant ridge to a narrow stone tower.
			var ridge: Node3D=world.spawn("V19_distant_cliff",at,rad_to_deg(-angle-PI*.5),0,self)
			if ridge==null:continue
			ridge.name="Ridge_%d_%02d"%[layer,index]
			# Broad horizontal forms retain the accepted rock silhouette and faces.
			ridge.scale=Vector3(rng.randf_range(60.0+layer*32.0,88.0+layer*40.0),rng.randf_range(5.0+layer*3.0,8.0+layer*3.0),rng.randf_range(20.0,28.0))
			var material:=ShaderMaterial.new();material.shader=load("res://shaders/distant_mountain.gdshader")
			material.set_shader_parameter("distance_layer",float(layer))
			materials.append(material)
			for mesh: MeshInstance3D in WorldBuilder.find_meshes(ridge):
				var bounds: AABB=mesh.mesh.get_aabb()
				material.set_shader_parameter("ridge_x_center",bounds.get_center().x)
				material.set_shader_parameter("ridge_x_radius",bounds.size.x*.5)
				material.set_shader_parameter("ridge_y_bottom",bounds.position.y)
				mesh.material_override=material
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# CPU frustum clipping must include geometry deliberately drawn at sky depth.
				mesh.extra_cull_margin=1800.0
	_update_look()

func _process(_delta: float) -> void:
	if is_visible_in_tree():_update_look()

func _update_look() -> void:
	var look: Dictionary=world.look
	var haze: Color=look.get("fog",Color(.72,.82,.93))
	var night: float=clampf(float(look.get("night",0.0)),0.0,1.0)
	var dusk: float=clampf(float(look.get("dusk",0.0)),0.0,1.0)
	var sun_ray: Vector3=Basis.from_euler((look.get("rot",Vector3(-48,-35,0)) as Vector3)*PI/180.0).z.normalized()
	var signature: int=hash([haze,night,dusk,sun_ray])
	if signature==_look_signature:return
	_look_signature=signature
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("haze_color",haze)
		material.set_shader_parameter("night_amount",night)
		material.set_shader_parameter("dusk_amount",dusk)
		material.set_shader_parameter("sun_direction",sun_ray)

static func capture_views() -> Dictionary:
	var views: Dictionary={}
	for farm: bool in [false,true]:
		for direction: int in [0,1,2,3]:
			var at:=Vector3(9,2.0,11) if farm else Vector3(15,2.1,20)
			var ray:=Vector3(cos(direction*PI*.5),.04,sin(direction*PI*.5))
			for high: bool in [false,true]:
				var camera_at: Vector3=at+Vector3.UP*22.0 if high else at
				views["mountains_%s_%d%s"%["farm" if farm else "town",direction,"_high" if high else ""]]={"farm":farm,"time":10.5,"player":at,"camera_at":camera_at,"camera_focus":camera_at+ray*60.0,"fov":62.0}
	for weather: String in ["sunny","rain"]:
		for hour: float in [12.0,17.3,21.0]:
			views["water_life_%s_%d"%[weather,int(hour*10)]]={"farm":true,"time":hour,"weather":weather,"player":Vector3(5.5,.1,12.4),"camera_at":Vector3(4.8,1.5,12.5),"camera_focus":Vector3(9.0,-.12,16.4),"fov":48.0}
	views["river_fish_close"]={"farm":true,"time":12.0,"weather":"sunny","player":Vector3(7,.1,12.8),"camera_at":Vector3(8.1,2.0,14.0),"camera_focus":Vector3(8,-.25,16.15),"fov":42.0}
	views["river_fish_general"]={"farm":true,"time":12.0,"weather":"sunny","player":Vector3(10.8,.1,13.0),"camera_at":Vector3(10.8,1.6,13.0),"camera_focus":Vector3(8.5,-.15,16.3),"fov":50.0}
	return views
