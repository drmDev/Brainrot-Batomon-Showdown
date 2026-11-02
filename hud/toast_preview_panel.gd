extends Control
## ToastPreviewPanel - developer-only UI for replaying existing toasts.
##
## A small "Preview" button opens a panel with a dropdown of every registered
## achievement/reaction plus Play and Close buttons. Presentation only: it forwards
## the selected entry to an injected play callable and never touches achievement
## progress, saves, or game state.
##
## Godot's default control theme is large relative to the toast scale: buttons,
## labels and especially the OptionButton popup need explicit font-size and compact
## stylebox overrides (same approach as Creature Comforts' HUD panels).

signal entry_played(entry)

const Styles = preload("styles.gd")

const BUTTON_WIDTH := 38.0
const BUTTON_HEIGHT := 11.0
const BUTTON_TOP_RATIO := 0.20
const MARGIN := 4.0

const PANEL_WIDTH := 170.0
const PANEL_HEIGHT := 64.0
const PANEL_TOP := 20.0
const PANEL_PADDING := 4
const CONTENT_GAP := 2
const CONTROL_HEIGHT := 10

# Half the toast scale, per the developer panel's compact footprint.
const TITLE_FONT_SIZE := 6
const BODY_FONT_SIZE := 5

var _entries: Array = []
var _play_fn: Callable
var _font: Font

var _open_button: Button
var _panel: PanelContainer
var _option: OptionButton
var _play_button: Button
var _close_button: Button


## entries: ToastCatalog.entries(). play_fn: receives the selected entry Dictionary.
func _init(entries: Array = [], play_fn: Callable = Callable()) -> void:
	_entries = entries.duplicate(true)
	_play_fn = play_fn
	_font = Styles.make_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	_populate()
	close_panel()


func _build_ui() -> void:
	_open_button = Button.new()
	_open_button.name = "PreviewButton"
	_open_button.text = "Preview"
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.tooltip_text = "Preview an achievement or reaction toast"
	_open_button.anchor_left = 1.0
	_open_button.anchor_right = 1.0
	_open_button.anchor_top = BUTTON_TOP_RATIO
	_open_button.anchor_bottom = BUTTON_TOP_RATIO
	_open_button.offset_left = -MARGIN - BUTTON_WIDTH
	_open_button.offset_top = 0.0
	_open_button.offset_right = -MARGIN
	_open_button.offset_bottom = BUTTON_HEIGHT
	_apply_compact_control(_open_button, BODY_FONT_SIZE)
	_open_button.pressed.connect(open_panel)
	add_child(_open_button)

	_panel = PanelContainer.new()
	_panel.name = "PreviewPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -PANEL_WIDTH * 0.5
	_panel.offset_right = PANEL_WIDTH * 0.5
	_panel.offset_top = PANEL_TOP
	_panel.offset_bottom = PANEL_TOP + PANEL_HEIGHT
	_panel.add_theme_stylebox_override("panel", Styles.make_panel_style())

	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, PANEL_PADDING)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", CONTENT_GAP)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Toast Preview"
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Styles.HEADER_COLOR)
	content.add_child(title)

	_option = OptionButton.new()
	_option.name = "ToastSelector"
	_option.focus_mode = Control.FOCUS_NONE
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	_apply_compact_control(_option, BODY_FONT_SIZE)
	content.add_child(_option)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", CONTENT_GAP)
	content.add_child(buttons)

	_play_button = _make_button("PlayButton", "Play", BODY_FONT_SIZE)
	_play_button.pressed.connect(play_selected)
	buttons.add_child(_play_button)

	_close_button = _make_button("CloseButton", "Close", BODY_FONT_SIZE)
	_close_button.pressed.connect(close_panel)
	buttons.add_child(_close_button)

	add_child(_panel)


## Apply the tiny font and compact stylebox to a native control. Without the
## stylebox override, Godot's default theme padding dwarfs the small font.
func _apply_compact_control(control: Control, font_size: int) -> void:
	control.add_theme_font_override("font", _font)
	control.add_theme_font_size_override("font_size", font_size)
	var style := Styles.make_compact_button_style()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		control.add_theme_stylebox_override(state, style)


func _make_button(node_name: String, text: String, font_size: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	_apply_compact_control(button, font_size)
	return button


func _populate() -> void:
	_option.clear()
	for entry in _entries:
		_option.add_item(_label_for(entry))
	if _option.item_count > 0:
		_option.select(0)
	_play_button.disabled = _option.item_count == 0
	_style_option_popup()


## The OptionButton popup is a separate PopupMenu with its own theme, so it needs
## the font overrides too; otherwise its rows render at the default (huge) size.
func _style_option_popup() -> void:
	var popup := _option.get_popup()
	popup.add_theme_font_override("font", _font)
	popup.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	popup.add_theme_constant_override("v_separation", 0)


func _label_for(entry: Dictionary) -> String:
	var label := str(entry.get("label", ""))
	if not label.is_empty():
		return label
	var title := str(entry.get("title", ""))
	if not title.is_empty():
		return title
	return str(entry.get("id", "Unknown"))


## Show the selection panel.
func open_panel() -> void:
	_panel.visible = true


## Hide the selection panel.
func close_panel() -> void:
	_panel.visible = false


func is_open() -> bool:
	return _panel.visible


## Number of entries available in the dropdown.
func entry_count() -> int:
	return _option.item_count


## Select a dropdown entry by index (out-of-range indices are ignored).
func select_index(index: int) -> void:
	if index >= 0 and index < _option.item_count:
		_option.select(index)


## The currently selected entry, or {} when the dropdown is empty.
func selected_entry() -> Dictionary:
	var index := _option.selected
	if index < 0 or index >= _entries.size():
		return {}
	return _entries[index]


## Forward the selected entry to the play callback. Safe to call repeatedly:
## the preview path does not consult completion state or dedupe cooldowns.
func play_selected() -> void:
	var entry := selected_entry()
	if entry.is_empty():
		return
	if _play_fn.is_valid():
		_play_fn.call(entry)
	entry_played.emit(entry)
