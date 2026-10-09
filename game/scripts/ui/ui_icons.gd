class_name UIIcons
extends RefCounted
## Original imagegen alpha is retained; regions only select each illustrated icon.
const REGIONS := {
	"home": ["navigation_atlas.png", Rect2(41,81,263,236)],
	"store": ["navigation_atlas.png", Rect2(351,91,251,225)],
	"bakery": ["navigation_atlas.png", Rect2(654,108,252,217)],
	"florist": ["navigation_atlas.png", Rect2(959,72,252,258)],
	"post": ["navigation_atlas.png", Rect2(81,365,213,249)],
	"hall": ["navigation_atlas.png", Rect2(335,380,280,231)],
	"farm": ["navigation_atlas.png", Rect2(649,448,273,149)],
	"fish": ["navigation_atlas.png", Rect2(973,363,233,250)],
	"tree": ["navigation_atlas.png", Rect2(42,651,262,244)],
	"exit": ["navigation_atlas.png", Rect2(376,653,228,241)],
	"quest": ["navigation_atlas.png", Rect2(660,658,221,231)],
	"book": ["navigation_atlas.png", Rect2(944,692,272,183)],
	"backpack": ["navigation_atlas.png", Rect2(46,926,257,260)],
	"calendar": ["navigation_atlas.png", Rect2(361,932,224,241)],
	"map": ["navigation_atlas.png", Rect2(649,949,265,224)],
	"coin": ["navigation_atlas.png", Rect2(986,957,208,211)],
	"w_sunny": ["weather_atlas.png", Rect2(62,82,349,340)],
	"w_night": ["weather_atlas.png", Rect2(527,113,281,281)],
	"w_cloudy": ["weather_atlas.png", Rect2(921,99,360,305)],
	"w_rain": ["weather_atlas.png", Rect2(1390,120,323,305)],
	"w_festival": ["weather_atlas.png", Rect2(118,476,232,323)],
	"level_badge": ["weather_atlas.png", Rect2(502,538,332,256)],
	"support_token": ["weather_atlas.png", Rect2(958,501,297,297)],
	"compass": ["weather_atlas.png", Rect2(1405,501,289,290)],
}
const ALIASES := {"tab_all":"backpack","tab_seed":"level_badge","tab_crop":"farm","tab_dish":"bakery","tab_material":"store","tab_key":"post"}
static func texture(id: String) -> Texture2D:
	return UIKitAssets.icon(id)
