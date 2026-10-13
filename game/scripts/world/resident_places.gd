class_name ResidentPlaces
extends RefCounted
## Actual addresses and visiting rooms. Workplaces never stand in for private homes.
const LEGACY_DOORS := {"shop_florist":"florist","shop_zakka":"zakka"}
const HOMES := {
	"haru":{"room":"home_haru","model":"H03","building_at":Vector3(24.9,0,16),"yaw":-90.0},
	"aoi":{"room":"home_haru","model":"H03","building_at":Vector3(24.9,0,16),"yaw":-90.0},
	"mio":{"room":"home_mio","model":"M03_gable_house","building_at":Vector3(24.2,0,26.5),"yaw":-90.0},
	"tanaka":{"room":"home_tanaka","model":"H03","building_at":Vector3(28.4,0,43),"yaw":-90.0},
	"ren":{"room":"home_ren","parent_room":"bakery"},
	"kazuko":{"room":"home_kazuko","parent_room":"store"},
}
static var SPECS: Dictionary=_specs()

static func _room(id: String,title: String,index: int,size: Vector2,owners: Array,privacy: String,door_at: Vector3,entry_region: String="town",return_room: String="") -> Dictionary:
	var origin:=Vector3(150+index*32,0,400)
	return {"id":id,"name":title,"origin":origin,"size":size,"ceiling_height":2.55,
		"floor":"wood","wall":"plaster","back_wall":"plaster","door_x":0.0,
		"entry":origin+Vector3(0,.05,size.y*.5-.65),"exit":door_at,"exit_yaw":0.0,
		"outside_point":door_at+Vector3(0,.9,0),"entry_region":entry_region,"return_room":return_room,
		"door_id":"visit_"+id+"_door","owners":owners,"privacy":privacy,"open":9.0,"close":20.0,
		"keeper":Vector3(1.45,0,.3),"keeper_yaw":-90.0,"rest_spots":{},"seats":{},
		"camera_pitch":49.0,"camera_dist":maxf(size.x,size.y)*.85+2.0,"camera_yaw":0.0,
		"memory_at":Vector3(-1.3,.9,0),"points":[["visit_"+id+"_exit",0,.9,size.y*.5-.4,1.35],["visit_"+id+"_memory",-1.3,.9,0,1.55]],
		"furniture":[],"lamps":[Vector3(-1.5,2.25,0),Vector3(1.6,2.25,-1.4)]}

static func _specs() -> Dictionary:
	var out: Dictionary={}
	out.home_haru=_room("home_haru","春与小葵的家",0,Vector2(10,8),["haru","aoi"],"private",Vector3(21.55,.1,17.205))
	out.home_mio=_room("home_mio","澪的家",1,Vector2(7,7),["mio"],"private",Vector3(19.8,.1,27.9))
	out.home_tanaka=_room("home_tanaka","田中的家",2,Vector2(8,7),["tanaka"],"private",Vector3(24.75,.1,44.205))
	out.home_ren=_room("home_ren","莲的店后住处",3,Vector2(7,8),["ren"],"private",Vector3(79.175,.05,397.0),"town","bakery")
	out.home_kazuko=_room("home_kazuko","和子的店后住处",4,Vector2(8,7),["kazuko"],"private",Vector3(49.725,.05,397.0),"town","store")
	out.toolshed=_room("toolshed","田中的工具屋",5,Vector2(7,7),["tanaka"],"work",Vector3(691.3,.1,-6.2),"farm")
	out.photo_room=_room("photo_room","澪的照片侧室",6,Vector2(5.8,8),["mio"],"work",Vector3(110,.05,396.4),"town","workroom")
	out.florist=_room("florist","千代花坊",7,Vector2(8,8),[],"public",Vector3(-12,.1,-13.4))
	out.zakka=_room("zakka","小町杂货铺",8,Vector2(7,10),[],"public",Vector3(0,.1,-13.4))
	out.post=_room("post","晴町邮局",9,Vector2(9,7),[],"public",Vector3(12.5,.1,-14.9))
	out.library=_room("library","晴町小阅览室",10,Vector2(8,8),[],"public",Vector3(-35,.1,-6.2))
	for private_id: String in ["home_haru","home_mio","home_tanaka","home_ren","home_kazuko"]:
		out[private_id].open={"home_haru":10.0,"home_mio":18.0,"home_tanaka":17.0,"home_ren":16.0,"home_kazuko":16.0}[private_id]
		out[private_id].close=20.0 if private_id in ["home_haru","home_ren","home_kazuko"] else 21.0
	for shop_id: String in ["florist","zakka"]:
		out[shop_id].door_id="shop_"+shop_id;out[shop_id].open=9.0;out[shop_id].close=18.0 if shop_id=="florist" else 19.0
	out.toolshed.open=6.0;out.toolshed.close=19.0
	out.post.open=9.0;out.post.close=18.0;out.library.open=9.0;out.library.close=20.0
	out.photo_room.open=7.0;out.photo_room.close=21.0
	out.home_haru.outside_point=Vector3(23.20,1.1,17.205)
	out.home_mio.outside_point=Vector3(21.05,1.1,27.9)
	out.home_tanaka.outside_point=Vector3(26.72,1.1,44.205)
	out.home_ren.outside_point=Vector3(79.175,1.0,396.42)
	out.home_kazuko.outside_point=Vector3(49.725,1.0,396.42)
	out.photo_room.outside_point=Vector3(110,1.0,395.6)
	out.florist.outside_point=Vector3(-12,1,-14.9);out.zakka.outside_point=Vector3(0,1,-14.9)
	out.post.outside_point=Vector3(12.5,1,-16.1);out.library.outside_point=Vector3(-35,1,-5.05)
	out.toolshed.outside_point=Vector3(690.65,1.1,-7.35)
	for id: String in ["home_haru","home_mio","home_tanaka","home_ren","toolshed","photo_room"]:
		out[id].memory_at=Vector3(-.75,.9,0)
		out[id].points[1][1]=-.75
	for id: String in out:
		var room: Dictionary=out[id]
		for who: String in room.owners:
			var index: int=(room.owners as Array).find(who)
			room.rest_spots[who]={"at":Vector3(1.25+index*.85,0,.35),"yaw":-90.0}
			room.seats[who]={"at":Vector3(1.25+index*.85,.31,-.65),"yaw":180.0,"support":"ResidentInterior/VisitSeat_"+who,"height":.31}
	out.home_haru.rest_spots.haru={"at":Vector3(-.70,0,-1.30),"yaw":180.0}
	out.home_haru.rest_spots.aoi={"at":Vector3(-3.55,0,.45),"yaw":90.0}
	return out

static func room_for(who: String) -> String:
	return str(HOMES.get(who,{}).get("room",""))
static func room_for_door(id: String) -> String:
	for key: String in SPECS:
		if str(SPECS[key].door_id)==id:return key
	return ""
static func build_doors(world: WorldBuilder) -> void:
	# Layout owns outdoor town points. The old farm_shed shop/Q15 point stays intact.
	if world.farm and world.farm.get_node_or_null("visit_toolshed_door")==null:
		var tool_door:=Interactable.new();tool_door.name="visit_toolshed_door";tool_door.id=tool_door.name;tool_door.radius=1.45
		world.farm.add_child(tool_door);tool_door.global_position=SPECS.toolshed.outside_point
		var frame:=Node3D.new();frame.name="ToolShedSideEntry";world.farm.add_child(frame)
		frame.global_position=Vector3(690.55,0,-7.35);frame.rotation.y=PI*.5
		var wood:=PublicPlaceArt.wood(Color(.57,.43,.28))
		for side: float in [-1.0,1.0]:PublicPlaceArt.box(frame,"Post_%d"%int(side),Vector3(.065,2.05,.12),Vector3(side*.43,1.025,0),wood)
		PublicPlaceArt.box(frame,"Lintel",Vector3(.93,.08,.14),Vector3(0,2.06,0),wood)
		PublicPlaceArt.box(frame,"SideDoor",Vector3(.78,1.90,.035),Vector3(0,.95,.02),PublicPlaceArt.matte(Color(.42,.52,.42)))
		ClearSignage.paper_tag(frame,"ToolshedDoorName","工具屋 · 工作入口",Vector3(0,1.68,.05),Vector2(.72,.15),0,.065)
	for id: String in ["home_ren","home_kazuko","photo_room"]:
		var spec: Dictionary=SPECS[id]
		var parent: Node3D=world.interiors.get(str(spec.return_room))
		if parent==null or parent.find_child(str(spec.door_id),true,false)!=null:continue
		var door:=Interactable.new();door.name=str(spec.door_id);door.id=str(spec.door_id);door.radius=1.45
		parent.add_child(door);door.global_position=spec.outside_point
		ClearSignage.paper_tag(parent,"ResidentDoorLabel_"+id,str(spec.name),parent.to_local(spec.outside_point)+Vector3(0,.75,-.12),Vector2(1.1,.2),0,.09)
	for who: String in HOMES:
		var address: Dictionary=HOMES[who]
		if not address.has("building_at"):continue
		for child: Node in world.get_children():
			if child is Node3D and child.get_meta("model_id","")==address.model and (child as Node3D).position.distance_to(address.building_at)<.05:
				var owners: Array=child.get_meta("residents",[])
				if who not in owners:owners.append(who)
				child.set_meta("residents",owners);child.set_meta("resident_room",address.room)
				if who=="mio":
					# This assembled house uses a solid whole-building proxy. Its front
					# box face sits .677m before the recessed visible door, so the ordinary
					# chest ray must ignore this target's own body, as Interactable allows.
					# Main creates Layout points after this builder, hence bind both existing
					# points and later children without changing the building's collisions.
					for part: Node in child.get_children():
						if not part is StaticBody3D:continue
						var owned_proxy:=part as StaticBody3D
						if not owned_proxy.collision_layer & WorldBuilder.L_SOLID:continue
						var host: Node=world.get_parent()
						for existing: Node in host.get_children():_bind_mio_door(existing,owned_proxy)
						if not child.get_meta("door_body_hook",false):
							host.child_entered_tree.connect(_bind_mio_door.bind(owned_proxy))
							child.set_meta("door_body_hook",true)
						break
	for building: Node in world.get_children():
		if not building is Node3D:continue
		var model: String=str(building.get_meta("model_id",""))
		if model not in ["H02","H03","M03_gable_house","M05_residential","M01_timber_machiya"]:continue
		if building.get_node_or_null("VisitDoorPlaque")!=null:continue
		var bounds: AABB=WorldBuilder.local_aabb(building as Node3D)
		var at: Vector3=(building as Node3D).position
		var assigned: String=str(building.get_meta("resident_room",""))
		var title: String="普通民居 · 无来访约定"
		if assigned!="":title=str(SPECS[assigned].name)+" · 先约后访"
		elif model=="H02":title="普通公寓 · 无来访约定"
		elif at.distance_to(Vector3(-35,0,-3))<.05:
			title="晴町小阅览室 · 09–20时";building.set_meta("public_room","library")
		ClearSignage.paper_tag(building as Node3D,"VisitDoorPlaque",title,Vector3(-.55,1.45,bounds.end.z+.028),Vector2(1.5,.22),0,.085)
		# Roof overhangs define the front AABB, so support this yard plaque with
		# its own timber stake instead of pretending it touches a recessed wall.
		PublicPlaceArt.box(building as Node3D,"VisitDoorPlaquePost",Vector3(.055,1.50,.055),Vector3(-.55,.75,bounds.end.z+.005),PublicPlaceArt.wood())
		building.set_meta("door_visit_status","invitation" if assigned!="" else ("public" if title.begins_with("晴町小") else "background"))

static func _bind_mio_door(added: Node,owned_proxy: StaticBody3D) -> void:
	if added is Interactable and added.id=="visit_home_mio_door":
		added.body=owned_proxy
		added.set_meta("door_proxy_owner","M03_gable_house")
