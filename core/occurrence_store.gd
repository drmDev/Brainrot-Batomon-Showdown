extends RefCounted
## OccurrenceStore - persists the set of run-scoped reactions that have already
## fired, keyed by run identity, so once-per-run survives Save & Quit.
##
## The evaluator's occurrence tracking is otherwise session-only; this store lets
## the coordinator restore it after a restart. Each run key maps to the list of
## reaction ids that fired for that run.

const STORE_PATH := "user://brain_rot/occurrences.cfg"
const SECTION := "occurrences"

var _store_path := STORE_PATH


## Override the store path (tests use a temp path so they never touch the real one).
func use_store(path: String) -> void:
	_store_path = path


## The fired reaction ids for a run key, or an empty array when none are recorded.
func load_fired(run_key: String) -> Array:
	if run_key.is_empty():
		return []
	var file := ConfigFile.new()
	if file.load(_store_path) != OK:
		return []
	var value = file.get_value(SECTION, run_key, null)
	if value is Array:
		return value
	return []


## Save the fired reaction ids for a run key. An empty array clears the record.
func save_fired(run_key: String, fired: Array) -> void:
	if run_key.is_empty():
		return
	var file := ConfigFile.new()
	file.load(_store_path)
	file.set_value(SECTION, run_key, fired)
	DirAccess.make_dir_recursive_absolute(_store_path.get_base_dir())
	file.save(_store_path)
