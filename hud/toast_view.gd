extends Control
## ToastView - presentation-only toast. The NotificationManager owns timing.
##
## Fixed width, explicit label layout (avoids hidden Container sizing),
## dark-navy/gold style box. The host calls present()/dismiss() and places the
## view; this script never schedules.
##
## Layout: a left-aligned rounded badge (the request's icon text) spans the full
## height, with the three text lines (header, title, description) to its right.

const Styles = preload("styles.gd")

var _header_label: Label
var _title_label: Label
var _description_label: Label
var _badge_label: Label
var _badge_texture: Texture2D = null
var _panel_style: StyleBoxFlat
var _badge_style: StyleBoxFlat
var _badge_rect := Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel_style = Styles.make_panel_style()
	_badge_style = Styles.make_badge_style()
	var font := Styles.make_font()
	_header_label = _make_label(font, Styles.HEADER_FONT_SIZE, Styles.HEADER_COLOR)
	_title_label = _make_label(font, Styles.TITLE_FONT_SIZE, Styles.TITLE_COLOR)
	_description_label = _make_label(font, Styles.DESCRIPTION_FONT_SIZE, Styles.DESCRIPTION_COLOR)
	_badge_label = _make_badge_label(font)


func _make_label(font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _make_badge_label(font: Font) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", Styles.BADGE_FONT_SIZE)
	label.add_theme_color_override("font_color", Styles.BADGE_TEXT_COLOR)
	add_child(label)
	return label


## Fill the toast from a NotificationRequest and make it visible. The host owns
## placement and expiry; this only renders.
func present(request) -> void:
	_header_label.text = str(request.header)
	_title_label.text = str(request.title)
	_description_label.text = str(request.description)
	var icon := str(request.icon)
	if icon.is_empty():
		icon = "?"
	_badge_label.text = icon
	_badge_label.add_theme_font_size_override(
		"font_size",
		Styles.BADGE_FONT_SIZE if icon.length() <= 2 else Styles.BADGE_FONT_SIZE_SMALL,
	)
	_badge_texture = request.icon_texture if request.icon_texture is Texture2D else null
	_badge_label.visible = _badge_texture == null
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
	var text_x := Styles.INTERNAL_PADDING + Styles.BADGE_SIZE + Styles.BADGE_GAP
	var text_width := maxf(1.0, width - text_x - Styles.INTERNAL_PADDING)
	var y := Styles.INTERNAL_PADDING
	for label: Label in [_header_label, _title_label, _description_label]:
		# Establish width BEFORE requesting the wrapped minimum height.
		label.size = Vector2(text_width, 0.0)
		var height := label.get_minimum_size().y
		label.position = Vector2(text_x, y)
		label.size = Vector2(text_width, height)
		y += height + Styles.LABEL_SPACING
	var text_height := y - Styles.LABEL_SPACING
	var content_height := maxf(text_height, Styles.BADGE_SIZE)
	size = Vector2(width, content_height + Styles.INTERNAL_PADDING * 2.0)

	# Center the badge vertically against the text block.
	_badge_rect = Rect2(
		Vector2(Styles.INTERNAL_PADDING, Styles.INTERNAL_PADDING + (content_height - Styles.BADGE_SIZE) * 0.5),
		Vector2(Styles.BADGE_SIZE, Styles.BADGE_SIZE),
	)
	_badge_label.position = _badge_rect.position
	_badge_label.size = _badge_rect.size
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
	_badge_style.draw(get_canvas_item(), _badge_rect)
	if _badge_texture is Texture2D:
		_draw_texture_fit(_badge_texture, _badge_rect)


## Draw a texture inside `rect` at its natural aspect ratio (contain), centred.
func _draw_texture_fit(tex: Texture2D, rect: Rect2) -> void:
	if tex == null:
		return
	var tex_size := tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale := minf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var draw_size := tex_size * scale
	var pos := rect.position + (rect.size - draw_size) * 0.5
	pos.y -= 2.0 # move it up a couple pixels for better alignment
	draw_texture_rect(tex, Rect2(pos, draw_size), false)
