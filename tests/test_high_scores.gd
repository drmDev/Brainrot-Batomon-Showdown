extends "test_runner.gd"
## Unit tests for battle/high_scores.gd.

const HighScores = preload("../battle/high_scores.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")

const TEST_PATH := "user://brain_rot_test/high_scores.json"


func _battle(units: Array, team: Array = [], battle_over: bool = true) -> Dictionary:
	return {
		"kind": "battle",
		"team": team,
		"battle_units": units,
		"battle_over": battle_over,
	}


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
			"damage": {"value": 12345, "unit": "monster.name.cinnabark"},
			"heal": 6789,
			"shield": {"value": -5, "unit": "x"},
			"burn": {"value": "nope", "unit": "x"},
		},
	}))
	var metrics: Dictionary = store.get("metrics", {})
	assert_eq(int(metrics.get("damage", {}).get("value", 0)), 12345)
	assert_eq(str(metrics.get("damage", {}).get("unit", "")), "monster.name.cinnabark")
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
