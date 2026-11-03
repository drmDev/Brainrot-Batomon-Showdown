extends "test_runner.gd"
## Replays JSON fixtures from dev/fixtures/ through the evaluator.
##
## Two fixture shapes are supported:
##   - Curated: {"steps": [ {kind, trainer_id, current_round, team, bench,
##       battle_over, battle_units, expect: [...]} ]}. Each step asserts the exact
##       set of award ids ("expect") so the rules are pinned to documented data.
##   - Captured: a flat snapshot written by the BRAINROT_DUMP_DIR hook (a single
##       {kind, ...} object, no "steps"/"expect"). These assert only that the
##       evaluator accepts the real shape without crashing.
##
## Fixture steps are converted straight into the snapshot Dictionaries the evaluator
## consumes, so the fixture format doubles as the snapshot contract.

const AchievementEvaluator = preload("../achievements/achievement_evaluator.gd")
const TestHelpers = preload("test_helpers.gd")


func _mod_root() -> String:
	var path := str(get_script().resource_path)
	if path.is_empty():
		return ""
	if path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	return path.get_base_dir().get_base_dir()


func _fixture_files() -> Array:
	var dir_path := _mod_root().path_join("dev/fixtures")
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			out.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _monsters(list) -> Array:
	var out: Array = []
	if list is Array:
		for item in list:
			if item is Dictionary:
				out.append({
					"name_key": str(item.get("name_key", "")),
					"level": int(item.get("level", 1)),
				})
	return out


func _units(list) -> Array:
	var out: Array = []
	if list is Array:
		for unit in list:
			if unit is Dictionary:
				out.append({
					"team_id": int(unit.get("team_id", 0)),
					"slot_index": int(unit.get("slot_index", 0)),
					"shield_granted": float(unit.get("shield_granted", 0.0)),
				})
	return out


func _run_snapshot(step: Dictionary) -> Dictionary:
	return {
		"kind": "run",
		"trainer_id": str(step.get("trainer_id", "")),
		"current_round": int(step.get("current_round", 0)),
		"team": _monsters(step.get("team", [])),
		"bench": _monsters(step.get("bench", [])),
	}


func _battle_snapshot(step: Dictionary) -> Dictionary:
	var snapshot := _run_snapshot(step)
	snapshot["kind"] = "battle"
	snapshot["battle_over"] = bool(step.get("battle_over", true))
	snapshot["battle_units"] = _units(step.get("battle_units", []))
	return snapshot


func _sorted_ids(earned: Array) -> Array:
	var out: Array = []
	for achievement in earned:
		if achievement is Dictionary:
			out.append(str(achievement.get("id", "")))
	out.sort()
	return out


func _sorted_expected(step: Dictionary) -> Array:
	var out: Array = []
	var raw = step.get("expect", [])
	if raw is Array:
		for id in raw:
			out.append(str(id))
	out.sort()
	return out


func test_curated_fixtures_replay() -> void:
	var files := _fixture_files()
	for path in files:
		_replay_file(path)


func _replay_file(path: String) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "fixture parse failed: " + path)
	if not parsed is Dictionary:
		return

	var steps: Array = []
	if parsed.get("steps") is Array:
		steps = parsed["steps"]
	else:
		steps = [parsed]

	var evaluator = AchievementEvaluator.new()

	for step in steps:
		if not step is Dictionary:
			continue
		var earned: Array
		if str(step.get("kind", "run")) == "battle":
			earned = evaluator.poll_battle(_battle_snapshot(step))
		else:
			earned = evaluator.poll(_run_snapshot(step))

		if step.has("expect"):
			assert_eq(_sorted_ids(earned), _sorted_expected(step), "fixture step: " + path)
		else:
			assert_true(earned is Array, "captured fixture returned non-array: " + path)
