extends "test_runner.gd"
## Unit tests for achievements/achievement_store.gd (JSON persistence).

const AchievementStore = preload("../achievements/achievement_store.gd")

const TEMP_DIR := "user://achievement_store_test"
const FILE_NAME := "achievements.json"


func _json_path() -> String:
	return ProjectSettings.globalize_path(TEMP_DIR).path_join(FILE_NAME)


func _reset() -> void:
	var path := _json_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _write_raw(text: String) -> void:
	var dir_path := ProjectSettings.globalize_path(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(dir_path.path_join(FILE_NAME), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _new_store():
	return AchievementStore.new(TEMP_DIR)


func test_missing_file_is_not_completed() -> void:
	_reset()
	var store = _new_store()
	assert_false(store.is_completed("oh_yeah"))
	_reset()


func test_mark_completed_persists_and_is_idempotent() -> void:
	_reset()
	var store = _new_store()
	assert_true(store.mark_completed("oh_yeah"))
	assert_true(store.is_completed("oh_yeah"))
	assert_false(store.mark_completed("oh_yeah"))
	_reset()


func test_reload_reads_persisted_state() -> void:
	_reset()
	var first = _new_store()
	first.mark_completed("herd_u_liek_mudkipz")
	var second = _new_store()
	assert_true(second.is_completed("herd_u_liek_mudkipz"))
	_reset()


func test_corrupt_file_treated_as_empty() -> void:
	_reset()
	_write_raw("{ not valid json ")
	var store = _new_store()
	assert_false(store.is_completed("oh_yeah"))
	assert_true(store.mark_completed("oh_yeah"))
	_reset()


func test_malformed_record_not_completed() -> void:
	_reset()
	_write_raw("{\"achievements\": {\"oh_yeah\": {\"completed\": \"yes\"}}}")
	var store = _new_store()
	assert_false(store.is_completed("oh_yeah"))
	_reset()


func test_missing_achievements_key_normalized() -> void:
	_reset()
	_write_raw("{\"other\": 1}")
	var store = _new_store()
	assert_false(store.is_completed("oh_yeah"))
	assert_true(store.mark_completed("oh_yeah"))
	_reset()
