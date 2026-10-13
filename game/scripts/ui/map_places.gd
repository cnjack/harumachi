class_name MapPlaces
extends RefCounted
## Symbolic landmarks; positions are the same metres as the world interactions.
const TOWN := [
	{"id":"residential","name":"南町住宅街","icon":"home","at":Vector2(19.7,57),"info":"田中家须先接受邀请；其他未具名民居没有来访约定，门前有明确门牌"},
	{"id":"bus","name":"晴町公交站","icon":"exit","at":Vector2(-43,-6.2),"info":"晴町的乡间公交"},
	{"id":"home","name":"奶奶的家","icon":"home","at":Vector2(21.8,5.9),"info":"厨房、休息与小院"},
	{"id":"store","name":"晴町商店","icon":"store","at":Vector2(-36,-14.9),"info":"购买种子、出售作物和鲜鱼"},
	{"id":"bakery","name":"莲的面包店","icon":"bakery","at":Vector2(-23.12,-14.9),"info":"面包、烘焙与街坊三明治"},
	{"id":"florist","name":"千代花坊","icon":"florist","at":Vector2(-12,-14.9),"info":"花束与盆栽"},
	{"id":"zakka","name":"小町杂货","icon":"book","at":Vector2(0,-14.9),"info":"旧书与生活杂货"},
	{"id":"post","name":"晴町邮局","icon":"post","at":Vector2(12.5,-16.5),"info":"沿石板主街往东"},
	{"id":"hall","name":"町内公民馆","icon":"hall","at":Vector2(-23.2,-6),"info":"委托与夏祭准备"},
	{"id":"courtyard","name":"榉树庭院","icon":"tree","at":Vector2(-3.0,1.0),"info":"街坊休息与周末集市"},
	{"id":"farm_exit","name":"河边农园","icon":"exit","at":Vector2(44.3,-11),"info":"东侧小路，通向晴川与镜波湖"},
]
static func places(region: String) -> Array[Dictionary]:
	var out: Array[Dictionary]=[]
	if region=="town":
		for place: Dictionary in TOWN:out.append(place.duplicate())
		for id: String in ["home_haru","home_mio","home_tanaka","library"]:
			var spec: Dictionary=ResidentPlaces.SPECS[id]
			var doorway: Vector3=spec.exit
			out.append({"id":id,"name":spec.name,"icon":"book" if id=="library" else "home","at":Vector2(doorway.x,doorway.z),"info":"阅览、旧地图与邻里记录" if id=="library" else "先接受主人的邀请；门边标明拜访时间"})
	else:
		out.append({"id":"plots","name":"市民农园","icon":"farm","at":Vector2(0,-4),"info":"种植、浇水与收获"})
		out.append({"id":"supplies","name":"水岸补给","icon":"store","at":LakesideLayout.SUPPLIES,"info":"买鱼饵、卖鲜鱼"})
		out.append({"id":"town_exit","name":"返回晴町","icon":"exit","at":Vector2(-27.6,.3),"info":"西侧上坡小路"})
		out.append({"id":"toolshed","name":"田中的工具屋","icon":"hall","at":Vector2(-8.7,-6.2),"info":"侧门进工作屋；原种子铺仍在正门"})
		for spot_id: String in LakesideLayout.SPOTS:
			var spec: Dictionary=LakesideLayout.SPOTS[spot_id]
			out.append({"id":spot_id,"name":spec.name,"icon":"fish","at":spec.stand,"info":"晴川钓点" if spec.habitat=="river" else "镜波湖钓点"})
	for place: Dictionary in out:place["region"]=region
	return out

static func world_position(place: Dictionary) -> Vector3:
	var at: Vector2=place.at
	return Vector3(at.x,0,at.y)+(FarmBuilder.ORIGIN if place.region=="farm" else Vector3.ZERO)

static func navigation_target(main: Node) -> Dictionary:
	var selected: Dictionary=main.ui.map_destination
	if not selected.is_empty():return selected.duplicate()
	var quest: Variant=main.story.marker_target()
	if quest is Vector3:
		var world_at: Vector3=main.story.outdoor_marker(quest)
		var farm: bool=world_at.x>600 and world_at.x<1000
		var local_at: Vector3=world_at-FarmBuilder.ORIGIN if farm else world_at
		return {"id":"objective","name":"当前委托","icon":"quest","region":"farm" if farm else "town","at":Vector2(local_at.x,local_at.z)}
	return {}

static func next_target(main: Node) -> Dictionary:
	var target: Dictionary=navigation_target(main)
	var region: String=str(main.world.region)
	if not target.is_empty() and target.region!=region:
		for place: Dictionary in places(region):
			if place.id==("town_exit" if region=="farm" else "farm_exit"):
				place["info"]="先去这里，再前往"+str(target.name)
				return place
	return target
