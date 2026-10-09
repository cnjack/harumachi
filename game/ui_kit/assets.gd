class_name UIKitAssets
extends RefCounted
const ROOT := "res://ui_kit/assets/"
const ALIASES := {"tab_all":"backpack","tab_seed":"level_badge","tab_crop":"farm","tab_dish":"bakery","tab_material":"store","tab_key":"post"}
static var _icons: Dictionary={}
static var _renders: Dictionary={}

static func icon(id: String) -> Texture2D:
	var key: String=ALIASES.get(id,id)
	if not UIKitCatalog.ENTRIES.has(key):return null
	if _icons.has(key):return _icons[key]
	var entry: Array=UIKitCatalog.ENTRIES[key]
	var texture:=AtlasTexture.new();texture.atlas=load(ROOT+str(entry[0]));texture.region=entry[1]
	texture.filter_clip=true;texture.resource_name="UIKitIcon/"+key;_icons[key]=texture
	return texture

static func artwork(id: String) -> Texture2D:
	return load(ROOT+str(UIKitCatalog.ENTRIES[id][0])) as Texture2D

static func render_texture(id: String,width: int) -> Texture2D:
	var key:=id+"@"+str(width)
	if _renders.has(key):return _renders[key]
	var entry: Array=UIKitCatalog.ENTRIES[id]
	var source: Texture2D=load(ROOT+str(entry[0]));var image: Image=source.get_image()
	if image.is_compressed():image.decompress()
	var region: Rect2i=entry[1]
	if region.has_area():image=image.get_region(region)
	var height:=roundi(width*image.get_height()/float(image.get_width()))
	image.resize(width,maxi(1,height),Image.INTERPOLATE_LANCZOS)
	var texture:=ImageTexture.create_from_image(image);texture.resource_name="UIKitArtwork/"+key
	_renders[key]=texture;return texture
