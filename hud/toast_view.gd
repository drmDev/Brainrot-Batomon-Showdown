extends Control
## ToastView - presentation-only toast. The NotificationManager owns timing.
##
## Same visuals as the original achievement toast: fixed width, explicit label
## layout (avoids hidden Container sizing), dark-navy/gold style box. The host
## calls present()/dismiss() and places the view; this script never schedules.

const Styles = preload("styles.gd")

var _header_label: Label
var _title_label: Label
var _description_label: Label
var _panel_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel_style = Styles.make_panel_style()
	var font := Styles.make_font()
	_header_label = _make_label(font, Styles.HEADER_FONT_SIZE, Styles.HEADER_COLOR)
	_title_label = _make_label(font, Styles.TITLE_FONT_SIZE, Styles.TITLE_COLOR)
	_description_label = _make_label(font, Styles.DESCRIPTION_FONT_SIZE, Styles.DESCRIPTION_COLOR)


func _make_label(font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


## Fill the toast from a NotificationRequest and make it visible. The host owns
## placement and expiry; this only renders.
func present(request) -> void:
	_header_label.text = str(request.header)
	_title_label.text = str(request.title)
	_description_label.text = str(request.description)
	layout()
	show()


func dismiss() -> void:
	hide()


## Recompute the wrapped label layout and the panel size. Safe to call when the
## view is not in the tree yet (the host restacks after adding it).
func layout() -> void:
	if not is_inside_tree():
		return
	var available_width := maxf(1.0, get_viewport_rect().size.x - Styles.MARGIN_RIGHT * 2.0)
	var width := minf(Styles.TOAST_WIDTH, available_width)
	var text_width := maxf(1.0, width - Styles.INTERNAL_PADDING * 2.0)
	var y := Styles.INTERNAL_PADDING
	for label: Label in [_header_label, _title_label, _description_label]:
		# Establish width BEFORE requesting the wrapped minimum height.
		label.size = Vector2(text_width, 0.0)
		var height := label.get_minimum_size().y
		label.position = Vector2(Styles.INTERNAL_PADDING, y)
		label.size = Vector2(text_width, height)
		y += height + Styles.LABEL_SPACING
	size = Vector2(width, y - Styles.LABEL_SPACING + Styles.INTERNAL_PADDING)
	queue_redraw()


## Anchor bottom-right, `stack_offset` pixels above the bottom margin. The host
## accumulates offsets so visible toasts stack instead of overlapping.
func place_bottom_right(stack_offset: float) -> void:
	if not is_inside_tree():
		return
	var bounds := get_viewport_rect()
	position = bounds.end - size - Vector2(Styles.MARGIN_RIGHT, Styles.MARGIN_BOTTOM + stack_offset)


func _draw() -> void:
	_panel_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
