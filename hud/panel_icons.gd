extends RefCounted
## PanelIcons - shared loader and drawing helpers for Brain Rot's small panel icons.
##
## Loose mod assets are not imported by the game, so icons are read from disk
## relative to the calling script's directory. The icon files live in
## assets/icons/ at the mod root.
##
## Adapted from Creature Comforts (hud/panel_icons.gd).

const CLOSE := "close.png"

const ICON_DIR := "../assets/icons"


## Load an icon by file name. `script_path` is the caller's
## `get_script().resource_path`, so the path resolves from the caller's folder.
## Transparent padding is trimmed away so icons fill a button equally.
static func load_icon(script_path: String, file_name: String) -> Texture2D:
	var base_dir := script_path.get_base_dir()
	if base_dir.is_empty():
		return null
	var path := base_dir.path_join(ICON_DIR).path_join(file_name)
	var image := Image.load_from_file(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(_trim_transparent(image))


## Crop an image to its non-transparent bounding box. Fully transparent or
## already tight images are returned unchanged.
static func _trim_transparent(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return image
	if used.position == Vector2i.ZERO and used.size == image.get_size():
		return image
	return image.get_region(used)


## Draw a texture inside `rect` at its natural aspect ratio (contain), centred.
static func draw_fit(canvas: CanvasItem, tex: Texture2D, rect: Rect2) -> void:
	if canvas == null or tex == null:
		return
	var tex_size := tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale := minf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var draw_size := tex_size * scale
	var pos := rect.position + (rect.size - draw_size) * 0.5
	canvas.draw_texture_rect(tex, Rect2(pos, draw_size), false)
