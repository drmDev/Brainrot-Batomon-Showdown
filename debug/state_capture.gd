extends RefCounted
## StateCapture - optional debug dump of run/battle snapshots.
##
## When the configured environment variable holds an absolute directory, each changed
## snapshot is written there as JSON for replay under tests/ (see dev/QUALITY.md).
## Unset during normal play, so nothing is written.
##
## The snapshot is the same Dictionary the evaluator consumes (produced by
## achievements/game_snapshot_reader.gd), so the dump doubles as a written contract
## for the game data the rules depend on.
##
## File names: state_<counter>_<ticks_ms>.json, written only when the serialized
## snapshot differs from the previous one.

const DEFAULT_ENV_VAR := "BRAINROT_DUMP_DIR"

var _env_var: String
var _dump_dir := ""
var _dir_resolved := false
var _last_signature := ""
var _counter := 0


## env_var: environment variable holding the dump directory.
## dump_dir_override: when non-empty, used instead of the environment (tests).
func _init(env_var: String = DEFAULT_ENV_VAR, dump_dir_override: String = "") -> void:
	_env_var = env_var
	if not dump_dir_override.is_empty():
		_dump_dir = dump_dir_override
		_dir_resolved = true


## Is capture active? Resolves the directory on first call.
func is_enabled() -> bool:
	_resolve_dir()
	return not _dump_dir.is_empty()


## Write the snapshot when capture is enabled and it changed since the last write.
## Returns the written path, or "" when nothing was written.
func capture(snapshot: Dictionary) -> String:
	if not is_enabled():
		return ""

	var signature := JSON.stringify(snapshot)
	if signature == _last_signature:
		return ""
	_last_signature = signature
	_counter += 1

	var file_path := _dump_dir.path_join("state_%06d_%d.json" % [_counter, Time.get_ticks_msec()])
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_warning("Brain Rot: cannot write state dump: " + file_path)
		return ""
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	return file_path


## Directory in use ("" when capture is disabled).
func dump_dir() -> String:
	_resolve_dir()
	return _dump_dir


func _resolve_dir() -> void:
	if _dir_resolved:
		return
	_dir_resolved = true
	_dump_dir = OS.get_environment(_env_var)
	if _dump_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_dump_dir)
