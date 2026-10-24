extends RefCounted
## Source aperture rays live in art/tools/check_bus_cabin.py; these checks cover
## the imported game asset and its actual articulation, ink and shader binding.
var t: Object
var main: Node

func _init(runner: Object) -> void:
	t=runner;main=runner.main

func check(label: String,ok: bool,detail: String="") -> void:
	t.check("BUS_CABIN",label,ok,detail)

func run() -> void:
	var bus: TownBus=main.world.get_node_or_null("CountryBus") as TownBus
	var model: Node3D=bus.get_node_or_null("B01_bus") as Node3D if bus else null
	if model==null:
		check("the repaired source bus is present",false)
		return
	var panes: Array[MeshInstance3D]=[]
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
		if str(mesh.name).begins_with("Glass_"):panes.append(mesh)
	check("thirteen source panes cover the cabin and both door leaves",panes.size()==13,str(panes.size()))
	var glass_errors: Array[String]=[]
	for glass_pane: MeshInstance3D in panes:
		var mat: ShaderMaterial=glass_pane.material_override as ShaderMaterial
		var faces: PackedVector3Array=glass_pane.mesh.get_faces()
		var area: float=0.0
		for offset: int in range(0,faces.size(),3):
			area+=(glass_pane.to_global(faces[offset+1])-glass_pane.to_global(faces[offset])).cross(glass_pane.to_global(faces[offset+2])-glass_pane.to_global(faces[offset])).length()*.5
		if mat==null or mat.shader==null or mat.shader.resource_path!="res://shaders/bus_glass.gdshader" or area<.10 or glass_pane.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			glass_errors.append(str(glass_pane.name))
	check("actual imported glazing has a clear untextured shader and physical area",glass_errors.is_empty(),str(glass_errors))
	var housing: MeshInstance3D=model.find_child("RouteHousing",true,false) as MeshInstance3D
	var display: MeshInstance3D=model.find_child("RouteDisplay",true,false) as MeshInstance3D
	var ink: Label3D=model.get_node_or_null("RouteLettering") as Label3D
	var mounts: Array[Node]=model.find_children("RouteRoofMount_*","MeshInstance3D",true,false)
	var support_ok: bool=housing!=null and display!=null and mounts.size()==2
	if support_ok:
		var housing_box: AABB=model.global_transform.affine_inverse()*housing.global_transform*housing.get_aabb()
		support_ok=housing_box.size.x>.20 and housing_box.size.y>.20 and housing_box.size.z>.90
		for mount_node: Node in mounts:
			var mount: MeshInstance3D=mount_node as MeshInstance3D
			var mount_box: AABB=model.global_transform.affine_inverse()*mount.global_transform*mount.get_aabb()
			support_ok=support_ok and mount_box.grow(.015).intersects(housing_box)
	check("route sign is a source housing joined to two real roof mounts",support_ok)
	var text_ok: bool=ink!=null and display!=null
	if text_ok:
		var display_box: AABB=model.global_transform.affine_inverse()*display.global_transform*display.get_aabb()
		var text_extent: Vector2=ink.get_meta("physical_ink_size",Vector2.INF)
		text_ok=ink.shaded and ink.position.x-display_box.end.x>=0.0 and ink.position.x-display_box.end.x<.012 and text_extent.x<.81 and text_extent.y<.135
	check("route lettering is fitted to the physical rollsign face",text_ok)
	var door_panes: Array[MeshInstance3D]=[]
	var closed_at: Array[Vector3]=[]
	for leaf: Node3D in bus.doors:
		var found: Array[Node]=leaf.find_children("Glass_Door_*","MeshInstance3D",true,false)
		if found.size()==1:
			var door_pane: MeshInstance3D=found[0] as MeshInstance3D
			door_panes.append(door_pane);closed_at.append(door_pane.to_global(door_pane.get_aabb().get_center()))
	bus.open_doors(1.0)
	var follows: bool=door_panes.size()==2
	for open_index: int in door_panes.size():
		follows=follows and closed_at[open_index].distance_to(door_panes[open_index].to_global(door_panes[open_index].get_aabb().get_center()))>.08
	bus.open_doors(0.0)
	var restored: bool=door_panes.size()==2
	for close_index: int in door_panes.size():
		restored=restored and closed_at[close_index].distance_to(door_panes[close_index].to_global(door_panes[close_index].get_aabb().get_center()))<.001
	check("glass moves with both doors instead of remaining across the entrance",follows)
	check("closing the door restores the glass precisely to its seals",restored)
	var tyre_errors: Array[String]=[]
	for wheel: Node3D in bus.wheels:
		var wheel_box: AABB=wheel.global_transform*WorldBuilder.local_aabb(wheel)
		if absf(wheel_box.position.y-bus.global_position.y)>.015:tyre_errors.append("%s bottom=%.4f"%[wheel.name,wheel_box.position.y])
	check("all four articulated tyres stand on the same road level",bus.wheels.size()==4 and tyre_errors.is_empty(),str(tyre_errors))
	var driver: Node3D=model.get_node_or_null("SeatedDriver") as Node3D
	var interact: Interactable=bus.get_node_or_null("BusDriver") as Interactable
	check("driver and original driver interaction remain connected",driver!=null and interact!=null and interact.body!=null and interact.id=="bus_driver")
