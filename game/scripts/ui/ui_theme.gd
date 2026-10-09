class_name UITheme
## Warm paper-card theme shared by the title screen and in-game UI.

const INK := UIKitTokens.INK
const INK_SOFT := UIKitTokens.MUTED
const PAPER := UIKitTokens.PAPER
const EDGE := UIKitTokens.EDGE
const ACCENT := UIKitTokens.SAGE
const GOOD := UIKitTokens.GOOD
const BAD := UIKitTokens.BAD

static func paper(kind: String="modal",margin: int=24) -> StyleBoxTexture:
	return UIKitStyles.surface(kind,margin)

static func box(bg: Color,border: Color,bw: int=0,radius: int=20,margin: int=20,shadow: bool=true) -> StyleBoxFlat:
	return UIKitStyles.flat(bg,border,bw,radius,margin,shadow)

static func make() -> Theme:
	return UIKitStyles.theme()


static func label(text: String, size: int = 26, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func icon_texture(id: String) -> Texture2D:
	var fish: Texture2D=FishArt.texture(id)
	if fish:return fish
	var illustrated: Texture2D=UIIcons.texture(id)
	if illustrated:return illustrated
	var p := id if id.begins_with("res://") else "res://assets/ui/icons/%s.png" % id
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

static func icon(id: String, size: int = 48) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icon_texture(id)
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
