extends "test_runner.gd"
## Validates the achievements.json schema and that saved ids match the evaluator's
## definitions. Guards against typos and stale ids drifting from the code.

const AchievementEvaluator = preload("../achievements/achievement_evaluator.gd")


func _known_ids() -> Array:
	return [
		str(AchievementEvaluator.SO_I_STARTED_BLASTING["id"]),
		str(AchievementEvaluator.BIG_DOG["id"]),
		str(AchievementEvaluator.OH_YEAH["id"]),
		str(AchievementEvaluator.HERD_U_LIEK_MUDKIPZ["id"]),
	]


## Mod root = parent of this tests/ directory.
func _mod_root() -> String:
	var script_path := str(get_script().resource_path)
	if script_path.is_empty():
		return ""
	if script_path.begins_with("res://"):
		script_path = ProjectSettings.globalize_path(script_path)
	return script_path.get_base_dir().get_base_dir()


func _validate(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	assert_false(text.is_empty(), label + ": empty or unreadable file")
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary, label + ": not a JSON object")
	if not parsed is Dictionary:
		return
	var achievements = parsed.get("achievements", null)
	assert_true(achievements is Dictionary, label + ": missing achievements object")
	if not achievements is Dictionary:
		return
	var known := _known_ids()
	for id in achievements.keys():
		assert_true(known.has(str(id)), label + ": unknown achievement id " + str(id))
		var entry = achievements[id]
		assert_true(entry is Dictionary, label + ": record is not an object: " + str(id))
		if entry is Dictionary and entry.get("completed", false) == true:
			assert_true(
				str(entry.get("completed_at", "")).length() > 0,
				label + ": completed without completed_at: " + str(id)
			)


func test_sample_fixture_schema() -> void:
	var path := _mod_root().path_join("tests/fixtures/achievements_sample.json")
	assert_true(FileAccess.file_exists(path), "sample fixture missing: " + path)
	_validate(path, "sample")


func test_live_save_schema_if_present() -> void:
	var root := _mod_root()
	if root.is_empty():
		return
	var path := root.path_join("achievements.json")
	if not FileAccess.file_exists(path):
		return
	_validate(path, "live")
