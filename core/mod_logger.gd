extends RefCounted
## Session log file and log-line helpers for Brain Rot.
##
## Extracted from mod_main.gd. Owns the open FileAccess handle and the startup
## banner so collaborators can log without mod_main passing a handle around.
##
## The log file is optional: when it cannot be opened, every log call no-ops and
## the mod still runs.

const OUTPUT_DIR := "user://brain_rot"
const LOG_FILE := "inspect.log"

var _log_path := ""
var _log_file: FileAccess = null  # Kept open for the session; avoids open/close per line


## Create the output directory and open the append handle, then write the
## startup banner. Returns the absolute log path on success, or "" when the log
## could not be opened.
func open(version: String) -> String:
	var dir_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		push_error("Brain Rot: Failed to create directory %s: %s" % [dir_path, error_string(dir_result)])
		return ""

	_log_path = OUTPUT_DIR.path_join(LOG_FILE)
	var abs_log_path := ProjectSettings.globalize_path(_log_path)

	if not FileAccess.file_exists(_log_path):
		var file := FileAccess.open(_log_path, FileAccess.WRITE)
		if file == null:
			push_error("Brain Rot: Cannot create log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
			return ""
		file.close()

	# Keep one append handle open for the session instead of reopening per line.
	_log_file = FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if _log_file == null:
		push_error("Brain Rot: Cannot open log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
		return ""
	_log_file.seek_end()

	log_message("=".repeat(80))
	log_message("Brain Rot %s" % version)
	log_message("Initialized at %s" % get_timestamp())
	log_message("Log file: %s" % abs_log_path)
	log_message("=".repeat(80))
	return abs_log_path


func close() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null


## Write one line to the session log. No-ops when the log file is unavailable.
func log_message(message: String) -> void:
	if _log_file == null:
		return
	_log_file.store_line(message)
	_log_file.flush()


## Timestamped diagnostic line: file only, "[HH:MM:SS] message".
func log_event(message: String) -> void:
	log_message("[%s] %s" % [get_time_short(), message])


## User-visible line: console and file, no timestamp prefix.
func print_notice(message: String) -> void:
	print(message)
	log_message(message)


func get_timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system(false)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]


func get_time_short() -> String:
	var dt := Time.get_datetime_dict_from_system(false)
	return "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]
