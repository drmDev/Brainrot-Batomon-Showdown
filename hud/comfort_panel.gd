extends Control
## ComfortPanel - shared foundation for Batomon Achievements HUD panels.
##
## Provides the common dark-navy/gold palette, the Consolas-with-fallbacks font,
## shadowed text drawing, and viewport-resize plumbing used by the drawing panels.
## Subclasses keep their own layout, styles, and drawing; this only removes the
## duplicated boilerplate.

# Shared palette (matches the game's dark-navy/gold panel look)
const BG_COLOR := Color("#1a2332")       # Dark navy
const BORDER_COLOR := Color("#f39c12")   # Gold
const LABEL_COLOR := Color("#d4d8e0")    # Dimmer label text
const VALUE_COLOR := Color("#ecf0f1")    # Bright value text
const SHADOW_COLOR := Color("#2c3e50")   # Dark shadow

const FALLBACK_FONTS := [
	"res://assets/ui/fonts/NotoSansJP-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansKR-ExtraBold.ttf",
	"res://assets/ui/fonts/NotoSansSC-ExtraBold.ttf",
]
const SYSTEM_FALLBACKS := ["Leelawadee UI", "Tahoma", "Segoe UI", "Noto Sans Thai", "Noto Sans", "Arial Unicode MS", "Droid Sans Fallback"]

var _text_font: Font


## Build the shared Consolas font with the game's font fallbacks.
func _build_panel_font() -> Font:
	var fallbacks: Array[Font] = []
	for font_path in FALLBACK_FONTS:
		if ResourceLoader.exists(font_path):
			var font_resource = load(font_path)
			if font_resource is Font:
				fallbacks.append(font_resource)
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(SYSTEM_FALLBACKS)
	fallbacks.append(system_font)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas"])
	font.fallbacks = fallbacks
	return font


## Connect the viewport resize signal once (safe to call from _ready).
func _connect_viewport_resize(handler: Callable) -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(handler):
		viewport.size_changed.connect(handler)


## Draw text with a light shadow for readability (shared panel look).
func _draw_text_shadow(pos: Vector2, text: String, color: Color, font_size: int, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_text_font, pos + Vector2(0.0, 1.0), text, align, width, font_size, SHADOW_COLOR)
	draw_string(_text_font, pos, text, align, width, font_size, color)
