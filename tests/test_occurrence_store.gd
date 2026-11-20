extends "test_runner.gd"
## Unit tests for core/occurrence_store.gd.

const OccurrenceStore = preload("../core/occurrence_store.gd")

const TMP_PATH := "user://brain_rot_test/occurrences.cfg"


func _store():
	var store = OccurrenceStore.new()
	store.use_store(TMP_PATH)
	return store


func _reset() -> void:
	var abs := ProjectSettings.globalize_path(TMP_PATH)
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(abs)


func test_round_trip() -> void:
	_reset()
	var store = _store()
	store.save_fired("run_1", ["six_seven", "over_9000"])
	assert_eq(store.load_fired("run_1"), ["six_seven", "over_9000"])


func test_unknown_key_is_empty() -> void:
	_reset()
	var store = _store()
	assert_empty(store.load_fired("no_such_run"))


func test_empty_array_clears() -> void:
	_reset()
	var store = _store()
	store.save_fired("run_1", ["six_seven"])
	store.save_fired("run_1", [])
	assert_empty(store.load_fired("run_1"))


func test_empty_key_is_ignored() -> void:
	_reset()
	var store = _store()
	store.save_fired("", ["six_seven"])
	assert_empty(store.load_fired(""))
