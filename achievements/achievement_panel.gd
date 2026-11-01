extends "../hud/comfort_panel.gd"
## Fixed-width toast. Explicit label layout avoids hidden Container sizing.

const TOAST_WIDTH := 220.0
const INTERNAL_PADDING := 8.0
const LABEL_SPACING := 4.0
const DISPLAY_DURATION_MS := 4000
const MARGIN_RIGHT := 8.0
const MARGIN_BOTTOM := 8.0

var _header_label: Label
var _title_label: Label
var _description_label: Label
var _panel_style: StyleBoxFlat
var _hide_at_ms := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG_COLOR
	_panel_style.border_color = BORDER_COLOR
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(3)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Segoe UI", "Arial"])
	_header_label = _make_label(font, 9, Color("#f39c12"))
	_title_label = _make_label(font, 12, Color.WHITE)
	_description_label = _make_label(font, 9, Color("#c8ced8"))
	_header_label.text = "ACHIEVEMENT UNLOCKED!"


func _ready() -> void:
	_connect_viewport_resize(_on_viewport_resized)


func _make_label(font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func show_achievement(title: String, description: String) -> void:
	_title_label.text = title
	_description_label.text = description
	_layout_labels()
	_anchor_bottom_right()
	_hide_at_ms = Time.get_ticks_msec() + DISPLAY_DURATION_MS
	show()


func _layout_labels() -> void:
	var available_width := maxf(1.0, get_viewport_rect().size.x - MARGIN_RIGHT * 2.0)
	var width := minf(TOAST_WIDTH, available_width)
	var text_width := maxf(1.0, width - INTERNAL_PADDING * 2.0)
	var y := INTERNAL_PADDING
	for label: Label in [_header_label, _title_label, _description_label]:
		# Establish width BEFORE requesting the wrapped minimum height.
		label.size = Vector2(text_width, 0.0)
		var height := label.get_minimum_size().y
		label.position = Vector2(INTERNAL_PADDING, y)
		label.size = Vector2(text_width, height)
		y += height + LABEL_SPACING
	size = Vector2(width, y - LABEL_SPACING + INTERNAL_PADDING)
	queue_redraw()


func _draw() -> void:
	_panel_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))


func _anchor_bottom_right() -> void:
	var bounds := get_viewport_rect()
	position = bounds.end - size - Vector2(MARGIN_RIGHT, MARGIN_BOTTOM)


func _on_viewport_resized() -> void:
	if visible:
		_layout_labels()
		_anchor_bottom_right()


func hide_panel() -> void:
	_hide_at_ms = 0
	hide()


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() >= _hide_at_ms:
		hide_panel()
