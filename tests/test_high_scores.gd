extends "test_runner.gd"
## Unit tests for battle/high_scores.gd.

const HighScores = preload("../battle/high_scores.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")

const TEST_PATH := "user://brain_rot_test/high_scores.json"


func _battle(units: Array, team: Array = [], battle_over: bool = true, trainer_id: String = "", time_elapsed = null) -> Dictionary:
	var snapshot := {
		"kind": "battle",
		"team": team,
		"battle_units": units,
		"battle_over": battle_over,
	}
	if not trainer_id.is_empty():
		snapshot["trainer_id"] = trainer_id
	if time_elapsed != null:
		snapshot["time_elapsed"] = time_elapsed
	return snapshot


func _unit(slot: int, metrics: Dictionary, team_id: int = 0) -> Dictionary:
	var unit := {"team_id": team_id, "slot_index": slot}
	unit.merge(metrics, true)
	return unit


func _team() -> Array:
	return [
		{"name_key": "monster.name.cinnabark", "level": 3},
		{"name_key": "monster.name.rhizuka", "level": 3},
	]


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_empty_store_has_version_and_empty_metrics() -> void:
	var store := HighScores.empty_store()
	assert_eq(int(store.get("version", 0)), HighScores.VERSION)
	assert_eq(int(store.get("metrics", {}).size()), 0)


func test_parse_ignores_corrupt_or_wrongly_typed_data() -> void:
	assert_eq(HighScores.parse(""), HighScores.empty_store())
	assert_eq(HighScores.parse("not json"), HighScores.empty_store())
	assert_eq(HighScores.parse("[]"), HighScores.empty_store())
	assert_eq(HighScores.parse("{\"metrics\": []}"), HighScores.empty_store())


func test_parse_normalizes_metric_entries() -> void:
	var store := HighScores.parse(JSON.stringify({
		"version": 1,
		"metrics": {
			"damage": {"value": 12345, "unit": "monster.name.cinnabark", "date_acquired": "11/18/26"},
			"heal": 6789,
			"shield": {"value": -5, "unit": "x"},
			"burn": {"value": "nope", "unit": "x"},
		},
	}))
	var metrics: Dictionary = store.get("metrics", {})
	assert_eq(int(metrics.get("damage", {}).get("value", 0)), 12345)
	assert_eq(str(metrics.get("damage", {}).get("unit", "")), "monster.name.cinnabark")
	assert_eq(str(metrics.get("damage", {}).get("date_acquired", "")), "11/18/26")
	assert_eq(int(metrics.get("heal", {}).get("value", 0)), 6789)
	assert_false(metrics.has("shield"))
	assert_false(metrics.has("burn"))


func test_record_battle_uses_best_single_unit_per_metric() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_battle(store, _battle([
		_unit(0, {"damage_dealt": 100.0}),
		_unit(1, {"damage_dealt": 500.0}),
	], _team()))
	assert_eq(int(improved.get("damage", {}).get("value", 0)), 500)
	assert_eq(str(improved.get("damage", {}).get("unit", "")), "monster.name.rhizuka")
	assert_true(str(improved.get("damage", {}).get("date_acquired", "")).length() > 0)
	assert_eq(int(store.get("metrics", {}).get("damage", {}).get("value", 0)), 500)


func test_record_battle_ignores_enemy_team() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_battle(store, _battle([
		_unit(0, {"damage_dealt": 9999.0}, 1),
	], _team()))
	assert_empty(improved)


func test_record_battle_requires_battle_over() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_battle(store, _battle([
		_unit(0, {"damage_dealt": 100.0}),
	], _team(), false))
	assert_empty(improved)


func test_record_battle_keeps_previous_high_score() -> void:
	var store := HighScores.empty_store()
	HighScores.record_battle(store, _battle([_unit(0, {"damage_dealt": 500.0})], _team()))
	var improved := HighScores.record_battle(store, _battle([_unit(0, {"damage_dealt": 100.0})], _team()))
	assert_empty(improved)
	assert_eq(int(store.get("metrics", {}).get("damage", {}).get("value", 0)), 500)


func test_record_battle_updates_unit_when_value_improves() -> void:
	var store := HighScores.empty_store()
	HighScores.record_battle(store, _battle([_unit(0, {"damage_dealt": 500.0})], _team()))
	var improved := HighScores.record_battle(store, _battle([_unit(1, {"damage_dealt": 900.0})], _team()))
	assert_eq(int(improved.get("damage", {}).get("value", 0)), 900)
	assert_eq(str(improved.get("damage", {}).get("unit", "")), "monster.name.rhizuka")
	assert_eq(int(improved.get("damage", {}).get("previous", 0)), 500)


func test_record_battle_handles_missing_team_slot() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_battle(store, _battle([_unit(5, {"damage_dealt": 100.0})], _team()))
	assert_eq(int(improved.get("damage", {}).get("value", 0)), 100)
	assert_eq(str(improved.get("damage", {}).get("unit", "")), "")


func test_current_date_string_uses_mm_dd_yy() -> void:
	var date := HighScores.current_date_string()
	var regex := RegEx.new()
	regex.compile("^\\d{2}/\\d{2}/\\d{2}$")
	assert_true(regex.search(date) != null, date)


func test_format_value_abbreviates() -> void:
	assert_eq(HighScores.format_value(0), "0")
	assert_eq(HighScores.format_value(999), "999")
	assert_eq(HighScores.format_value(1000), "1.0K")
	assert_eq(HighScores.format_value(1000000), "1.0M")


func test_format_unit_strips_prefix_and_capitalizes() -> void:
	assert_eq(HighScores.format_unit("monster.name.cinnabark"), "Cinnabark")
	assert_eq(HighScores.format_unit(""), "Unknown")


func test_save_and_load_round_trip() -> void:
	_remove_test_file()
	var store := HighScores.empty_store()
	HighScores.record_battle(store, _battle([_unit(0, {"damage_dealt": 12345.0})], _team()))
	assert_true(HighScores.save_store(store, TEST_PATH))
	var loaded := HighScores.load_store(TEST_PATH)
	assert_eq(int(loaded.get("metrics", {}).get("damage", {}).get("value", 0)), 12345)
	assert_eq(str(loaded.get("metrics", {}).get("damage", {}).get("unit", "")), "monster.name.cinnabark")
	_remove_test_file()


# --- Longest battle ---

func test_record_battle_records_longest_battle_with_trainer() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_battle(store, _battle([], _team(), true, "gentleman", 12.6))
	assert_eq(int(improved.get("longest_battle", {}).get("value", 0)), 13)
	assert_eq(str(improved.get("longest_battle", {}).get("unit", "")), "gentleman")
	assert_eq(int(store.get("metrics", {}).get("longest_battle", {}).get("value", 0)), 13)


func test_record_battle_longest_battle_keeps_previous() -> void:
	var store := HighScores.empty_store()
	HighScores.record_battle(store, _battle([], _team(), true, "gentleman", 30.0))
	var improved := HighScores.record_battle(store, _battle([], _team(), true, "chef", 10.0))
	assert_false(improved.has("longest_battle"))
	assert_eq(str(store.get("metrics", {}).get("longest_battle", {}).get("unit", "")), "gentleman")


func test_record_battle_longest_battle_ignores_missing_time() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_battle(store, _battle([], _team(), true, "gentleman"))
	assert_false(improved.has("longest_battle"))


# --- Most casts ---

func test_record_battle_records_most_casts_with_unit() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_battle(store, _battle([
		_unit(0, {"cast_count": 3}),
		_unit(1, {"cast_count": 9}),
	], _team()))
	assert_eq(int(improved.get("most_casts", {}).get("value", 0)), 9)
	assert_eq(str(improved.get("most_casts", {}).get("unit", "")), "monster.name.rhizuka")


func test_record_battle_most_casts_ignores_enemy_team() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_battle(store, _battle([
		_unit(0, {"cast_count": 99}, 1),
	], _team()))
	assert_false(improved.has("most_casts"))


# --- Most trinkets (run-scoped) ---

func test_record_run_records_most_trinkets_with_trainer() -> void:
	var store := HighScores.empty_store()
	var improved := HighScores.record_run(store, {"trainer_id": "gentleman", "trinket_count": 4})
	assert_eq(int(improved.get("most_trinkets", {}).get("value", 0)), 4)
	assert_eq(str(improved.get("most_trinkets", {}).get("unit", "")), "gentleman")
	assert_eq(int(store.get("metrics", {}).get("most_trinkets", {}).get("value", 0)), 4)


func test_record_run_keeps_previous_trinkets() -> void:
	var store := HighScores.empty_store()
	HighScores.record_run(store, {"trainer_id": "gentleman", "trinket_count": 5})
	var improved := HighScores.record_run(store, {"trainer_id": "chef", "trinket_count": 2})
	assert_empty(improved)
	assert_eq(str(store.get("metrics", {}).get("most_trinkets", {}).get("unit", "")), "gentleman")


func test_record_run_ignores_missing_or_zero_count() -> void:
	var store := HighScores.empty_store()
	assert_empty(HighScores.record_run(store, {"trainer_id": "gentleman"}))
	assert_empty(HighScores.record_run(store, {"trainer_id": "gentleman", "trinket_count": 0}))
	assert_false(store.get("metrics", {}).has("most_trinkets"))


# --- Formatting ---

func test_format_metric_value_uses_duration_for_longest_battle() -> void:
	assert_eq(HighScores.format_metric_value("longest_battle", 12), "12s")
	assert_eq(HighScores.format_metric_value("longest_battle", 125), "2m 5s")


func test_format_metric_value_uses_number_for_other_metrics() -> void:
	assert_eq(HighScores.format_metric_value("most_casts", 7), "7")
	assert_eq(HighScores.format_metric_value("most_trinkets", 1200), "1.2K")


func test_parse_keeps_new_metrics() -> void:
	var store := HighScores.parse(JSON.stringify({
		"version": 1,
		"metrics": {
			"longest_battle": {"value": 42, "unit": "gentleman", "date_acquired": "11/18/26"},
			"most_casts": {"value": 9, "unit": "monster.name.rhizuka"},
			"most_trinkets": {"value": 6, "unit": "chef"},
		},
	}))
	var metrics: Dictionary = store.get("metrics", {})
	assert_eq(int(metrics.get("longest_battle", {}).get("value", 0)), 42)
	assert_eq(int(metrics.get("most_casts", {}).get("value", 0)), 9)
	assert_eq(int(metrics.get("most_trinkets", {}).get("value", 0)), 6)
