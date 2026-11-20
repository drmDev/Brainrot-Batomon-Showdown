extends RefCounted
## Shop Memories button controller for Brain Rot.
##
## Extracted from mod_main.gd. Attaches the rainbow-brain button to the game's
## HudButtons bar while the shop is active, and keeps the Memories panel in sync
## with the current high-score store.

const MOD_BASE_DIR := "res://mods/BrainRot"
const BRAIN_ICON_FILE := "assets/icons/rainbowBrain.png"

const NodeUtils = preload("../catalog/node_utils.gd")

var _memories_panel = null
var _logger = null
var _button = null
var _button_host_id := 0


func _init(memories_panel, logger) -> void:
	_memories_panel = memories_panel
	_logger = logger


## Show the button only while the shop is active, and keep the panel's table in
## sync with the current high-score store.
func update(is_shop: bool, state, high_scores: Dictionary) -> void:
	if _memories_panel == null:
		return
	if is_shop:
		_memories_panel.set_scores(high_scores)
		_sync_button(state)
	else:
		_detach_button()
		_memories_panel.hide_panel()


## Attach the rainbow-brain button to the game's HudButtons bar. Re-attaches when
## the shop view is recreated (new instance id). The button opens the Memories
## popup; the game's own bar handles its layout and show/hide.
##
## Multi-mod safety: the button is inserted at a deterministic index among any
## other mod buttons (sorted by node name) rather than always at index 0, and the
## bar's left edge is recomputed from all children instead of being decremented,
## so several mods can extend the bar without clobbering each other.
func _sync_button(state) -> void:
	var view = state.get("view") if NodeUtils.has_property(state, "view") else null
	if not is_instance_valid(view):
		_logger.log_event("MEMORIES BUTTON | no shop view")
		_detach_button()
		return
	var hud_buttons = view.get_node_or_null("HudButtons")
	if hud_buttons == null:
		_logger.log_event("MEMORIES BUTTON | no HudButtons node")
		_detach_button()
		return
	var host_id: int = hud_buttons.get_instance_id()
	if _button != null and is_instance_valid(_button) and _button_host_id == host_id:
		return
	_detach_button()
	_button = _make_button()
	if _button == null:
		_logger.log_event("MEMORIES BUTTON | button creation failed")
		return
	hud_buttons.add_child(_button)
	_insert_button(hud_buttons)
	_button_host_id = host_id
	_widen_hud_buttons(hud_buttons)
	_logger.log_event("MEMORIES BUTTON | attached (visible=%s)" % str(_button.visible))


## Place the brain button among the bar's children in a stable, name-sorted order
## so multiple mods' buttons do not fight over the leftmost slot.
func _insert_button(hud_buttons) -> void:
	var target := str(_button.name)
	var index := 0
	for i in range(hud_buttons.get_child_count()):
		var child = hud_buttons.get_child(i)
		if child == _button:
			continue
		if str(child.name) < target:
			index = i + 1
	hud_buttons.move_child(_button, index)


## Recompute the bar's left edge from the total width of its children so the
## game's buttons keep their positions while mod buttons extend the bar leftward.
## Idempotent: repeated calls produce the same result.
func _widen_hud_buttons(hud_buttons) -> void:
	var separation: int = hud_buttons.get_theme_constant("separation")
	var total := 0.0
	for i in range(hud_buttons.get_child_count()):
		var child = hud_buttons.get_child(i)
		if child is Control:
			total += child.get_combined_minimum_size().x
		if i > 0:
			total += separation
	# The bar is right-anchored; keep its right edge fixed and extend leftward.
	hud_buttons.offset_left = hud_buttons.offset_right - total


## Build the small rounded brain button that opens the Memories popup.
func _make_button():
	var Styles = load(MOD_BASE_DIR.path_join("hud/styles.gd"))
	var button := Button.new()
	button.name = "BrainRotButton"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(24, 24)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.expand_icon = true
	var icon := _load_icon()
	if icon != null:
		button.icon = icon
	else:
		_logger.log_event("MEMORIES BUTTON | brain icon failed to load")
	if Styles != null:
		var style: StyleBoxFlat = Styles.make_compact_button_style()
		style.set_content_margin_all(3)
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)
	button.pressed.connect(_on_button_pressed)
	return button


## Load the loose rainbowBrain.png icon (not imported by the game).
func _load_icon() -> Texture2D:
	var path := MOD_BASE_DIR.path_join(BRAIN_ICON_FILE)
	var image := Image.load_from_file(path)
	if image == null:
		_logger.log_event("MEMORIES BUTTON | cannot load icon: %s" % path)
		return null
	return ImageTexture.create_from_image(image)


func _on_button_pressed() -> void:
	if _memories_panel != null:
		_memories_panel.open_panel()


func _detach_button() -> void:
	if _button != null and is_instance_valid(_button):
		_button.free()
	_button = null
	_button_host_id = 0
