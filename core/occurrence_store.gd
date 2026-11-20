extends RefCounted
## OccurrenceStore - persists the set of run-scoped reactions that have already
## fired for the single active run, so once-per-run survives Save & Quit.
##
## Only one run is active at a time, so this holds exactly one record
## (run_key + fired ids) rather than a growing per-run map.

const STORE_PATH := "user://brain_rot/occurrences.cfg"
const SECTION := "occurrences"
const KEY_RUN := "run_key"
const KEY_FIRED := "fired"

var _store_path := STORE_PATH


## Override the store path (tests use a temp path so they never touch the real one).
func use_store(path: String) -> void:
	_store_path = path


## The single persisted record: {"run_key": String, "fired": Array}. Empty when
## nothing has been saved yet.
func load() -> Dictionary:
	var file := ConfigFile.new()
	if file.load(_store_path) != OK:
		return {}
	var run_key := str(file.get_value(SECTION, KEY_RUN, ""))
	var fired = file.get_value(SECTION, KEY_FIRED, [])
	if not fired is Array:
		fired = []
	return {"run_key": run_key, "fired": fired}


## Overwrite the single record with the current run's fired ids.
func save(run_key: String, fired: Array) -> void:
	if run_key.is_empty():
		return
	var file := ConfigFile.new()
	file.load(_store_path)
	file.set_value(SECTION, KEY_RUN, run_key)
	file.set_value(SECTION, KEY_FIRED, fired)
	DirAccess.make_dir_recursive_absolute(_store_path.get_base_dir())
	file.save(_store_path)
