extends Control
## ShopModalPanel - shared scaffolding for the shop's small icon-button modals.
##
## Owns the modal frame, close box, viewport anchoring, and input. Subclasses
## provide the popup title and height, and the popup content. The button that
## opens the modal is owned by the game's HUD (see mod_main), not by this panel.
##
## Adapted from Creature Comforts (hud/shop_modal_panel.gd and
## hud/comfort_panel.gd), restyled with Brain Rot's hud/styles.gd palette.

const Styles = preload("styles.gd")
const PanelIcons = preload("panel_icons.gd")

const POPUP_WIDTH := 320.0
const POPUP_PADDING := 8.0
const TITLE_H := 22.0
const CLOSE_BTN := 14.0
const VIEWPORT_MARGIN := 8.0
const TEXT_BASELINE_OFFSET := 4.0
const FALLBACK_VIEWPORT_SIZE := Vector2(1280, 720)

const TITLE_FONT_SIZE := 11

const BG_COLOR := Styles.BG_COLOR
const BORDER_COLOR := Styles.BORDER_COLOR
const HEADER_COLOR := Styles.HEADER_COLOR
const TITLE_COLOR := Styles.TITLE_COLOR
const DESCRIPTION_COLOR := Styles.DESCRIPTION_COLOR
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.5)

var _popup_open := false

var _text_font: Font
var _close_texture: Texture2D = null
var _popup_style: StyleBoxFlat
var _header_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false
	_setup_styles()
	_text_font = Styles.make_font()
	_close_texture = PanelIcons.load_icon(str(get_script().resource_path), PanelIcons.CLOSE)


func _ready() -> void:
	_connect_viewport_resize(_on_viewport_resized)
	_anchor()


# --- Subclass hooks ---------------------------------------------------------

func _popup_title() -> String:
	return ""


func _popup_height() -> float:
	return TITLE_H + POPUP_PADDING * 2.0


func _draw_content(_rect: Rect2) -> void:
	pass


# --- Public lifecycle (mod_main and tests) ----------------------------------

func hide_panel() -> void:
	_close_popup()


func open_panel() -> void:
	_open_popup()


func close_panel() -> void:
	_close_popup()


func is_open() -> bool:
	return _popup_open


# --- Lifecycle --------------------------------------------------------------

func _setup_styles() -> void:
	_popup_style = StyleBoxFlat.new()
	_popup_style.bg_color = BG_COLOR
	_popup_style.border_color = BORDER_COLOR
	_popup_style.set_border_width_all(2)
	_popup_style.set_corner_radius_all(4)

	_header_style = StyleBoxFlat.new()
	_header_style.bg_color = BG_COLOR
	_header_style.border_color = BORDER_COLOR
	_header_style.set_border_width_all(1)
	_header_style.set_corner_radius_all(4)


func _anchor() -> void:
	var viewport_size := _viewport_size()
	position = Vector2.ZERO
	size = viewport_size
	queue_redraw()


func _on_viewport_resized() -> void:
	_anchor()


func _viewport_size() -> Vector2:
	var viewport := get_viewport()
	return viewport.get_visible_rect().size if viewport != null else FALLBACK_VIEWPORT_SIZE


func _open_popup() -> void:
	if _popup_open:
		return
	_popup_open = true
	visible = true
	_anchor()
	if is_inside_tree():
		grab_focus()
	queue_redraw()


func _close_popup() -> void:
	if not _popup_open:
		return
	_popup_open = false
	visible = false
	queue_redraw()


# --- Layout -----------------------------------------------------------------

func _popup_rect() -> Rect2:
	var viewport_size := _viewport_size()
	var w := minf(POPUP_WIDTH, viewport_size.x - VIEWPORT_MARGIN * 2.0)
	var h := minf(_popup_height(), viewport_size.y - VIEWPORT_MARGIN * 2.0)
	var x := roundf((viewport_size.x - w) * 0.5)
	var y := roundf((viewport_size.y - h) * 0.5)
	return Rect2(Vector2(x, y), Vector2(w, h))


func _close_rect() -> Rect2:
	var r := _popup_rect()
	return Rect2(
		Vector2(r.position.x + r.size.x - POPUP_PADDING - CLOSE_BTN, r.position.y + (TITLE_H - CLOSE_BTN) * 0.5),
		Vector2(CLOSE_BTN, CLOSE_BTN)
	)


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if _text_font == null:
		return
	if _popup_open:
		_draw_popup()


func _draw_popup() -> void:
	draw_rect(Rect2(Vector2.ZERO, _viewport_size()), DIM_COLOR)

	var r := _popup_rect()
	_popup_style.draw(get_canvas_item(), r)

	var title_rect := Rect2(r.position, Vector2(r.size.x, TITLE_H))
	_header_style.draw(get_canvas_item(), title_rect)
	_draw_text_shadow(
		Vector2(r.position.x, r.position.y + TITLE_H - 6.0),
		_popup_title(), HEADER_COLOR, TITLE_FONT_SIZE,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	var close := _close_rect()
	if _close_texture != null:
		PanelIcons.draw_fit(self, _close_texture, close)

	_draw_content(r)


# --- Input ------------------------------------------------------------------

func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _popup_open:
			if _close_rect().has_point(event.position):
				_close_popup()
			elif not _popup_rect().has_point(event.position):
				_close_popup()
			accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _popup_open:
		_close_popup()
		accept_event()


func _unhandled_input(event) -> void:
	if _popup_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_popup()
		get_viewport().set_input_as_handled()


# --- Helpers ----------------------------------------------------------------

func _connect_viewport_resize(handler: Callable) -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(handler):
		viewport.size_changed.connect(handler)


func _draw_text_shadow(pos: Vector2, text: String, color: Color, font_size: int, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_text_font, pos + Vector2(0.0, 1.0), text, align, width, font_size, Color(0.0, 0.0, 0.0, 0.8))
	draw_string(_text_font, pos, text, align, width, font_size, color)
