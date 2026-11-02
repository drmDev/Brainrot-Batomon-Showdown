extends RefCounted
## Styles - shared visual constants and builders for Brain Rot HUD elements.
##
## Centralizes the palette, font, panel chrome, and toast layout metrics so
## presentation values live in one place. Pure data/builders: no nodes, no
## game-state knowledge.

# Palette (dark-navy/gold)
const BG_COLOR := Color("#1a2332")
const BORDER_COLOR := Color("#f39c12")
const HEADER_COLOR := Color("#f39c12")
const TITLE_COLOR := Color.WHITE
const DESCRIPTION_COLOR := Color("#c8ced8")

# Font
const FONT_NAMES := ["Consolas", "Segoe UI", "Arial"]
const HEADER_FONT_SIZE := 9
const TITLE_FONT_SIZE := 12
const DESCRIPTION_FONT_SIZE := 9

# Panel chrome
const PANEL_BORDER_WIDTH := 1
const PANEL_CORNER_RADIUS := 3

# Toast layout
const TOAST_WIDTH := 220.0
const INTERNAL_PADDING := 8.0
const LABEL_SPACING := 4.0
const MARGIN_RIGHT := 8.0
const MARGIN_BOTTOM := 8.0
const STACK_GAP := 4.0


## Build the toast font (Consolas with system fallbacks).
static func make_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	return font


## Build the toast panel background/border style.
static func make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(PANEL_BORDER_WIDTH)
	style.set_corner_radius_all(PANEL_CORNER_RADIUS)
	return style


## Compact button chrome for tool UI (dev toast preview). Godot's default Button
## content margins dominate a tiny font, so these controls need an explicit
## compact stylebox (mirrors Creature Comforts' HUD helpers).
static func make_compact_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(PANEL_BORDER_WIDTH)
	style.set_corner_radius_all(PANEL_CORNER_RADIUS)
	style.set_content_margin_all(1.0)
	return style
