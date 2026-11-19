extends RefCounted
## ModConfig - Brain Rot's one numeric user setting: mod sound volume.
##
## The community Mod Loader can only draw declared mod.json settings as a
## left/right stepper, so volume is NOT declared in mod.json. mod_main draws it as
## an HSlider via make_custom_settings_menu_entries() and this module persists it
## in the mod's own file.

const MOD_ID := "brain_rot"
const STORE_PATH := "user://brain_rot/settings.cfg"
const STORE_SECTION := "settings"

const KEY_MOD_VOLUME := "mod_volume"
const MOD_VOLUME_MIN := 0
const MOD_VOLUME_MAX := 100
const DEFAULT_MOD_VOLUME := 100

var _loader = null
var _store_path := ""
var _mod_volume := DEFAULT_MOD_VOLUME


## Bind to the Mod Loader (may be null when running standalone).
func setup(loader) -> void:
	_loader = loader


## Bind the mod's own file and read the persisted volume. A missing, unreadable,
## or malformed file leaves the default in place.
func use_store(path: String) -> void:
	_store_path = path
	_mod_volume = DEFAULT_MOD_VOLUME
	if path.is_empty():
		return
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	var value = file.get_value(STORE_SECTION, KEY_MOD_VOLUME, null)
	if value is int or value is float:
		_mod_volume = _clamp_volume(int(value))


## Current volume, 0-100.
func mod_volume() -> int:
	return _mod_volume


## Store a new volume (clamped to 0-100). Setting the current value is a no-op.
func set_mod_volume(value: int) -> void:
	var clamped := _clamp_volume(value)
	if clamped == _mod_volume:
		return
	_mod_volume = clamped
	_save_store()


func _clamp_volume(value: int) -> int:
	return clampi(value, MOD_VOLUME_MIN, MOD_VOLUME_MAX)


func _save_store() -> void:
	if _store_path.is_empty():
		return
	var file := ConfigFile.new()
	file.load(_store_path)
	file.set_value(STORE_SECTION, KEY_MOD_VOLUME, _mod_volume)
	DirAccess.make_dir_recursive_absolute(_store_path.get_base_dir())
	var error := file.save(_store_path)
	if error != OK:
		push_warning("Brain Rot: cannot save settings (%s): %s" % [_store_path, error_string(error)])
