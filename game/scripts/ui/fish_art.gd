class_name FishArt
extends RefCounted
## Imagegen cel-shaded fish cutouts. Atlas regions retain the original alpha.
const REGIONS := {
	"fish_crucian":Rect2(26,156,474,278),
	"fish_carp":Rect2(500,134,515,305),
	"fish_ayu":Rect2(1035,187,484,239),
	"fish_trout":Rect2(16,610,484,254),
	"fish_bass":Rect2(504,596,531,288),
	"fish_eel":Rect2(1046,564,480,274),
}
static var _cache: Dictionary={}
static func texture(id: String) -> Texture2D:
	if not REGIONS.has(id):return null
	if _cache.has(id):return _cache[id]
	var icon:=AtlasTexture.new();icon.atlas=load("res://assets/ui/fish/anime_atlas_20261004.png");icon.region=REGIONS[id]
	icon.filter_clip=true;icon.resource_name="AnimeFish/"+id;_cache[id]=icon;return icon
