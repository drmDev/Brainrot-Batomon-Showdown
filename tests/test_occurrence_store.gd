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
	store.save("run_1", ["six_seven", "over_9000"])
	assert_eq(store.load(), {"run_key": "run_1", "fired": ["six_seven", "over_9000"]})


func test_empty_when_no_record() -> void:
	_reset()
	var store = _store()
	assert_eq(store.load(), {})


func test_save_overwrites_previous_run() -> void:
	_reset()
	var store = _store()
	store.save("run_1", ["six_seven"])
	store.save("run_2", ["over_9000"])
	assert_eq(store.load(), {"run_key": "run_2", "fired": ["over_9000"]})


func test_empty_key_is_ignored() -> void:
	_reset()
	var store = _store()
	store.save("", ["six_seven"])
	assert_eq(store.load(), {})
