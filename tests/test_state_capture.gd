extends "test_runner.gd"
## Unit tests for debug/state_capture.gd.
##
## Uses a temp directory override so no environment variable is required.

const StateCapture = preload("../debug/state_capture.gd")


func _temp_dir() -> String:
	var dir := OS.get_temp_dir().path_join("brainrot_capture_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _cleanup(dir: String) -> void:
	var handle := DirAccess.open(dir)
	if handle == null:
		return
	handle.list_dir_begin()
	var name := handle.get_next()
	while name != "":
		if not handle.current_is_dir():
			handle.remove(name)
		name = handle.get_next()
	handle.list_dir_end()
	DirAccess.remove_absolute(dir)


func _json_files(dir: String) -> Array:
	var out: Array = []
	var handle := DirAccess.open(dir)
	if handle == null:
		return out
	handle.list_dir_begin()
	var name := handle.get_next()
	while name != "":
		if not handle.current_is_dir() and name.ends_with(".json"):
			out.append(name)
		name = handle.get_next()
	handle.list_dir_end()
	return out


func test_disabled_without_env_or_override() -> void:
	var capture = StateCapture.new("BRAINROT_TEST_UNSET_ENV_VAR")
	assert_false(capture.is_enabled())
	assert_eq(capture.capture({"kind": "run"}), "")


func test_override_enables_capture() -> void:
	var dir := _temp_dir()
	var capture = StateCapture.new("BRAINROT_TEST_UNSET_ENV_VAR", dir)
	assert_true(capture.is_enabled())
	assert_eq(capture.dump_dir(), dir)
	_cleanup(dir)


func test_writes_changed_snapshot_once() -> void:
	var dir := _temp_dir()
	var capture = StateCapture.new("BRAINROT_TEST_UNSET_ENV_VAR", dir)
	var path := capture.capture({"kind": "run", "current_round": 1})
	assert_false(path.is_empty())
	assert_eq(_json_files(dir).size(), 1)
	_cleanup(dir)


func test_identical_snapshot_is_not_rewritten() -> void:
	var dir := _temp_dir()
	var capture = StateCapture.new("BRAINROT_TEST_UNSET_ENV_VAR", dir)
	var snapshot := {"kind": "run", "current_round": 1}
	assert_false(capture.capture(snapshot).is_empty())
	assert_eq(capture.capture(snapshot), "")
	assert_eq(_json_files(dir).size(), 1)
	_cleanup(dir)


func test_changed_snapshot_writes_again() -> void:
	var dir := _temp_dir()
	var capture = StateCapture.new("BRAINROT_TEST_UNSET_ENV_VAR", dir)
	assert_false(capture.capture({"kind": "run", "current_round": 1}).is_empty())
	assert_false(capture.capture({"kind": "run", "current_round": 2}).is_empty())
	assert_eq(_json_files(dir).size(), 2)
	_cleanup(dir)


func test_written_file_is_valid_json() -> void:
	var dir := _temp_dir()
	var capture = StateCapture.new("BRAINROT_TEST_UNSET_ENV_VAR", dir)
	var path := capture.capture({"kind": "battle", "battle_over": true})
	assert_false(path.is_empty())
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary)
	if parsed is Dictionary:
		assert_eq(parsed.get("kind"), "battle")
		assert_eq(parsed.get("battle_over"), true)
	_cleanup(dir)
