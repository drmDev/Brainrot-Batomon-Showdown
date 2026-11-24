extends Control
## ToastPreviewPanel - developer-only UI for previewing reaction text exactly as
## players see it.
##
## A small "Preview" button opens a panel with:
##   - a Reaction dropdown
##   - a Case dropdown (from catalog/reaction_text.gd)
##   - one input per placeholder the selected case's template uses
##   - Play and Close buttons
##
## Play builds the same match Dictionary the evaluator produces and forwards it to
## the injected play callable. Presentation only: it never touches progress, saves,
## or game state.
##
## Godot's default control theme is large relative to the toast scale: buttons,
## labels, OptionButton popups, and LineEdits all need explicit font-size and compact
## stylebox overrides (same approach as Creature Comforts' HUD panels).

const Styles = preload("styles.gd")
const ReactionText = preload("../catalog/reaction_text.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")

const BUTTON_WIDTH := 38.0
const BUTTON_HEIGHT := 11.0
const BUTTON_TOP_RATIO := 0.20
const MARGIN := 4.0

const PANEL_WIDTH := 260.0
const PANEL_HEIGHT := 140.0
const PANEL_TOP := 20.0
const PANEL_PADDING := 4
const CONTENT_GAP := 2
const CONTROL_HEIGHT := 10

const TITLE_FONT_SIZE := 6
const BODY_FONT_SIZE := 5

var _entries: Array = []
var _species_keys: Array = []
var _play_fn: Callable
var _font: Font

var _panel: PanelContainer
var _reaction: OptionButton
var _case: OptionButton
var _inputs: VBoxContainer
var _play_button: Button
var _input_controls: Dictionary = {}  # placeholder -> Control


## entries: Catalog.reactions(). play_fn: receives a match Dictionary.
## species_keys: optional species list for the species dropdown.
func _init(entries: Array = [], play_fn: Callable = Callable(), species_keys: Array = []) -> void:
	_entries = entries.duplicate(true)
	_species_keys = _build_species_keys(species_keys)
	_play_fn = play_fn
	_font = Styles.make_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	_populate()
	close_panel()


func _build_ui() -> void:
	var open_button := Button.new()
	open_button.name = "PreviewButton"
	open_button.text = "Preview"
	open_button.focus_mode = Control.FOCUS_NONE
	open_button.tooltip_text = "Preview a reaction toast"
	open_button.anchor_left = 1.0
	open_button.anchor_right = 1.0
	open_button.anchor_top = BUTTON_TOP_RATIO
	open_button.anchor_bottom = BUTTON_TOP_RATIO
	open_button.offset_left = -MARGIN - BUTTON_WIDTH
	open_button.offset_top = 0.0
	open_button.offset_right = -MARGIN
	open_button.offset_bottom = BUTTON_HEIGHT
	_apply_compact_control(open_button, BODY_FONT_SIZE)
	open_button.pressed.connect(open_panel)
	add_child(open_button)

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
	_apply_label(title, TITLE_FONT_SIZE, Styles.HEADER_COLOR)
	content.add_child(title)

	_reaction = OptionButton.new()
	_reaction.name = "ReactionSelector"
	_reaction.focus_mode = Control.FOCUS_NONE
	_reaction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reaction.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	_apply_compact_control(_reaction, BODY_FONT_SIZE)
	_reaction.item_selected.connect(_on_reaction_selected)
	content.add_child(_reaction)

	_case = OptionButton.new()
	_case.name = "CaseSelector"
	_case.focus_mode = Control.FOCUS_NONE
	_case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_case.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	_apply_compact_control(_case, BODY_FONT_SIZE)
	_case.item_selected.connect(_on_case_selected)
	content.add_child(_case)

	_inputs = VBoxContainer.new()
	_inputs.name = "Inputs"
	_inputs.add_theme_constant_override("separation", CONTENT_GAP)
	content.add_child(_inputs)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", CONTENT_GAP)
	content.add_child(buttons)

	_play_button = _make_button("PlayButton", "Play", BODY_FONT_SIZE)
	_play_button.pressed.connect(play_selected)
	buttons.add_child(_play_button)

	var close_button := _make_button("CloseButton", "Close", BODY_FONT_SIZE)
	close_button.pressed.connect(close_panel)
	buttons.add_child(close_button)

	add_child(_panel)


## Apply the tiny font and compact stylebox to a native control.
func _apply_compact_control(control: Control, font_size: int) -> void:
	control.add_theme_font_override("font", _font)
	control.add_theme_font_size_override("font_size", font_size)
	var style := Styles.make_compact_button_style()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		control.add_theme_stylebox_override(state, style)


func _apply_label(label: Label, font_size: int, color: Color) -> void:
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


func _make_button(node_name: String, text: String, font_size: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	_apply_compact_control(button, font_size)
	return button


func _style_option_popup(option: OptionButton) -> void:
	var popup := option.get_popup()
	popup.add_theme_font_override("font", _font)
	popup.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	popup.add_theme_constant_override("v_separation", 0)


func _populate() -> void:
	_reaction.clear()
	for entry in _entries:
		var id := str(entry.get("id", ""))
		_reaction.add_item(str(entry.get("title", id)))
	_play_button.disabled = _reaction.item_count == 0
	_style_option_popup(_reaction)
	if _reaction.item_count > 0:
		_reaction.select(0)
	_refresh_cases()


func _refresh_cases() -> void:
	_case.clear()
	for case_name in ReactionText.cases(selected_id()):
		_case.add_item(case_name)
	_style_option_popup(_case)
	if _case.item_count > 0:
		_case.select(0)
	_refresh_inputs()


func _refresh_inputs() -> void:
	for child in _inputs.get_children():
		_inputs.remove_child(child)
		child.queue_free()
	_input_controls.clear()

	var placeholders := ReactionText.placeholders(selected_id(), selected_case())
	for placeholder in placeholders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", CONTENT_GAP)
		_inputs.add_child(row)

		var label := Label.new()
		label.text = placeholder.capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_label(label, BODY_FONT_SIZE, Styles.TITLE_COLOR)
		row.add_child(label)

		var control := _make_input(placeholder)
		_input_controls[placeholder] = control
		row.add_child(control)


func _make_input(placeholder: String) -> Control:
	match placeholder:
		"species":
			return _make_species_option()
		"metric":
			return _make_metric_option()
		_:
			return _make_number_input(_default_number(placeholder))


func _make_species_option() -> OptionButton:
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	_apply_compact_control(option, BODY_FONT_SIZE)
	for key in _species_keys:
		option.add_item(ReactionText.format_species_name(key))
	_style_option_popup(option)
	var default_key := _default_species_key()
	var index := _species_keys.find(default_key)
	if index >= 0:
		option.select(index)
	return option


func _make_metric_option() -> OptionButton:
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	_apply_compact_control(option, BODY_FONT_SIZE)
	for label in Catalog.BATTLE_METRIC_ORDER:
		option.add_item(ReactionText.metric_word(label))
	_style_option_popup(option)
	var default_label := _default_metric_label()
	var index := Catalog.BATTLE_METRIC_ORDER.find(default_label)
	if index >= 0:
		option.select(index)
	return option


func _make_number_input(default_value: int) -> LineEdit:
	var line := LineEdit.new()
	line.focus_mode = Control.FOCUS_ALL
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	line.text = str(default_value)
	line.add_theme_font_override("font", _font)
	line.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	var style := Styles.make_compact_button_style()
	for state in ["normal", "focus"]:
		line.add_theme_stylebox_override(state, style)
	return line


func _on_reaction_selected(_index: int) -> void:
	_refresh_cases()


func _on_case_selected(_index: int) -> void:
	_refresh_inputs()


func _build_species_keys(explicit: Array) -> Array:
	var keys: Array = []
	for key in explicit:
		var text := str(key).strip_edges()
		if not text.is_empty() and not keys.has(text):
			keys.append(text)
	for entry in _entries:
		var species := str(entry.get("species", "")).strip_edges()
		if not species.is_empty() and not keys.has(species):
			keys.append(species)
	keys.sort()
	return keys


func _default_species_key() -> String:
	var entry := Catalog.entry(selected_id())
	var authored := str(entry.get("species", ""))
	if not authored.is_empty():
		return authored
	if not _species_keys.is_empty():
		return str(_species_keys[0])
	return ""


func _default_metric_label() -> String:
	var rule := Catalog.battle_rule(selected_id())
	var metrics = rule.get("metrics")
	if metrics is Array and not metrics.is_empty():
		return str(metrics[0])
	if not Catalog.BATTLE_METRIC_ORDER.is_empty():
		return str(Catalog.BATTLE_METRIC_ORDER[0])
	return ""


func _default_number(placeholder: String) -> int:
	match placeholder:
		"value":
			var rule := Catalog.battle_rule(selected_id())
			var value := int(rule.get("value", 0))
			return value + 1 if str(rule.get("op", "eq")) == "gt" else value
		"income":
			match selected_id():
				Catalog.SIX_NINE:
					return 69
				Catalog.FOUR_TWENTY:
					return 420
				Catalog.SIX_SIX_SIX:
					return 666
				Catalog.OVER_9000:
					return 9001
			return 67
	return 0


## The currently selected reaction id, or "".
func selected_id() -> String:
	var index := _reaction.selected
	if index < 0 or index >= _entries.size():
		return ""
	return str(_entries[index].get("id", ""))


## The currently selected case name, or "".
func selected_case() -> String:
	var cases := ReactionText.cases(selected_id())
	var index := _case.selected
	if index < 0 or index >= cases.size():
		return ""
	return str(cases[index])


## Number of reaction entries in the dropdown.
func reaction_count() -> int:
	return _reaction.item_count


## Number of cases for the selected reaction.
func case_count() -> int:
	return _case.item_count


## Select a reaction by index and refresh the case dropdown.
func select_reaction(index: int) -> void:
	if index >= 0 and index < _reaction.item_count:
		_reaction.select(index)
		_refresh_cases()


## Select a case by index and refresh the dynamic inputs.
func select_case(index: int) -> void:
	if index >= 0 and index < _case.item_count:
		_case.select(index)
		_refresh_inputs()


## Build the match the selected inputs describe, for tests and the play callback.
func selected_match() -> Dictionary:
	var id := selected_id()
	var case_name := selected_case()
	var params := {}
	var species_key := ""

	for placeholder in ReactionText.placeholders(id, case_name):
		var control: Control = _input_controls.get(placeholder)
		if control == null:
			continue
		var value = _read_input(placeholder, control)
		params[_param_key(placeholder)] = value
		if placeholder == "species":
			species_key = str(value)

	if species_key.is_empty():
		species_key = str(Catalog.entry(id).get("species", ""))

	return {
		"id": id,
		"case": case_name,
		"params": params,
		"species_key": species_key,
	}


func _param_key(placeholder: String) -> String:
	return "species_key" if placeholder == "species" else placeholder


func _read_input(placeholder: String, control: Control):
	if control is OptionButton:
		if placeholder == "species":
			var index := (control as OptionButton).selected
			if index >= 0 and index < _species_keys.size():
				return str(_species_keys[index])
			return ""
		var metric_index := (control as OptionButton).selected
		if metric_index >= 0 and metric_index < Catalog.BATTLE_METRIC_ORDER.size():
			return str(Catalog.BATTLE_METRIC_ORDER[metric_index])
		return ""
	if control is LineEdit:
		return int((control as LineEdit).text)
	return ""


## Show the selection panel.
func open_panel() -> void:
	_panel.visible = true


## Hide the selection panel.
func close_panel() -> void:
	_panel.visible = false


func is_open() -> bool:
	return _panel.visible


## Forward the current match to the play callback.
func play_selected() -> void:
	var match := selected_match()
	if str(match.get("id", "")).is_empty():
		return
	if _play_fn.is_valid():
		_play_fn.call(match)
