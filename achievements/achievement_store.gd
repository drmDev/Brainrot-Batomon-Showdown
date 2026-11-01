extends RefCounted
## AchievementStore - simple JSON persistence for achievement completion state.
##
## The file lives at the mod root (next to mod_main.gd) as achievements.json.
## Structure:
## {
##   "achievements": {
##     "oh_yeah": {"completed": true, "completed_at": "2026-10-28T03:00:00Z"}
##   }
## }
## An id that is absent (or has completed=false) is treated as not completed.
##
## The mod loader mounts the external Mods directory, so the mod root is writable.
## mod_main passes its own base directory so the JSON stays at the mod root even
## though this script lives in achievements/.

const FILE_NAME := "achievements.json"

var _path := ""
var _data: Dictionary = {"achievements": {}}


## base_dir: absolute or res:// directory to store the JSON in. When empty, falls
## back to this script's own directory (useful for standalone tests).
func _init(base_dir: String = "") -> void:
	if base_dir.is_empty():
		base_dir = str(get_script().resource_path).get_base_dir()
	_path = ProjectSettings.globalize_path(base_dir.path_join(FILE_NAME))
	_load()


## Has this achievement already been completed?
func is_completed(id: String) -> bool:
	var achievements: Dictionary = _data.get("achievements", {})

	# No saved record for this id means it has never been completed.
	if not achievements.has(id):
		return false

	var entry = achievements[id]

	# A malformed record is treated as not completed.
	if not entry is Dictionary:
		return false

	# We save "completed": true when earned. A missing or non-bool value is treated
	# as not completed; the typeof guard avoids a runtime error on malformed saves
	# (String compared with bool raises "Invalid operands" in GDScript).
	var completed = entry.get("completed", false)
	return typeof(completed) == TYPE_BOOL and completed


## Mark an achievement completed and persist. Returns true if the state changed.
func mark_completed(id: String) -> bool:
	if is_completed(id):
		return false
	var achievements = _data.get("achievements", {})
	if not achievements is Dictionary:
		achievements = {}
	achievements[id] = {
		"completed": true,
		"completed_at": Time.get_datetime_string_from_system(true),
	}
	_data["achievements"] = achievements
	_save()
	return true


func _load() -> void:
	if not FileAccess.file_exists(_path):
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		push_warning("Brain Rot: cannot read achievements file: " + _path)
		return
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = parsed
		if not (_data.get("achievements") is Dictionary):
			_data["achievements"] = {}
	else:
		push_warning("Brain Rot: invalid achievements JSON, starting fresh: " + _path)


func _save() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("Brain Rot: cannot write achievements file: " + _path)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
