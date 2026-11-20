extends RefCounted
## Mod Volume slider row and volume access for Brain Rot.
##
## Extracted from mod_main.gd. Owns the volume read/commit, the slider row the
## Mod Loader draws, and the one-shot preview player. The loader calls
## make_custom_settings_menu_entries() on the mod node, which delegates here.

const SLIDER_STEP := 5
## The loader's own text theme; generic Labels added by a mod do not inherit it.
const SETTINGS_TEXT_THEME := "res://assets/ui/themes/text/description_text.tres"

var _config = null
var _preview = null  # one-shot UiSound preview player (created on first release)


func _init(config) -> void:
	_config = config


func set_config(config) -> void:
	_config = config


## Current volume for the sound players, 0-100. Read on every play so moving the
## slider affects the next sound without rebuilding any player.
func current_volume() -> int:
	if _config != null:
		return _config.mod_volume()
	return 100


## Released, focus-out, and tree-exit all commit; set_mod_volume() clamps and
## skips the file write when the value did not change, so only the first counts.
func commit_volume(value: int) -> void:
	if _config == null:
		return
	_config.set_mod_volume(value)


func volume_text(value: int) -> String:
	return "Mod Volume: %d%%" % value


## Play a sound at the newly saved volume so the slider can be judged by ear.
func preview_sound(host: Node) -> void:
	if _config == null:
		return
	if _preview == null:
		var UiSound = load("res://mods/BrainRot/audio/ui_sound.gd")
		if UiSound == null:
			return
		_preview = UiSound.new()
		_preview.setup(host, "click.ogg", Callable(), Callable(self, "current_volume"))
	_preview.play()


## Build the Mod Volume slider row the Mod Loader appends to the settings menu.
func make_settings_entries(host: Node) -> Array:
	var ModConfig = load("res://mods/BrainRot/core/mod_config.gd")
	var Styles = load("res://mods/BrainRot/hud/styles.gd")
	if ModConfig == null or Styles == null:
		return []

	var volume := current_volume()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var label := Label.new()
	label.name = "ModVolumeLabel"
	label.theme = load(SETTINGS_TEXT_THEME)
	label.text = volume_text(volume)
	box.add_child(label)

	var slider := HSlider.new()
	slider.name = "ModVolumeSlider"
	slider.min_value = float(ModConfig.MOD_VOLUME_MIN)
	slider.max_value = float(ModConfig.MOD_VOLUME_MAX)
	slider.step = float(SLIDER_STEP)
	slider.value = float(volume)
	# The menu treats a VBox row's second child as the navigable control, so the
	# label must stay first and the slider second.
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(160, 22)
	slider.tooltip_text = "Volume of the sounds Brain Rot plays."
	Styles.apply_slider(slider)
	box.add_child(slider)

	# Text follows the drag; the file is written once on release (or when focus
	# leaves the slider, which covers gamepad/keyboard changes).
	slider.value_changed.connect(func(value: float):
		label.text = volume_text(int(value)))
	slider.drag_ended.connect(func(_value_changed: bool):
		commit_volume(int(slider.value))
		preview_sound(host))
	slider.focus_exited.connect(func():
		commit_volume(int(slider.value)))
	slider.tree_exiting.connect(func():
		commit_volume(int(slider.value)))

	return [box]
