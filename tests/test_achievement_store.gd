extends "test_runner.gd"
## Unit tests for core/achievement_store.gd.

const AchievementStore = preload("../core/achievement_store.gd")

const TEST_PATH := "user://brain_rot_test/achievements.json"


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_empty_store_has_version_and_empty_reactions() -> void:
	var store := AchievementStore.empty_store()
	assert_eq(int(store.get("version", 0)), AchievementStore.VERSION)
	assert_eq(int(store.get("reactions", {}).size()), 0)


func test_parse_ignores_corrupt_or_wrongly_typed_data() -> void:
	assert_eq(AchievementStore.parse(""), AchievementStore.empty_store())
	assert_eq(AchievementStore.parse("not json"), AchievementStore.empty_store())
	assert_eq(AchievementStore.parse("[]"), AchievementStore.empty_store())
	assert_eq(AchievementStore.parse("{\"reactions\": []}"), AchievementStore.empty_store())


func test_parse_normalizes_reaction_entries() -> void:
	var store := AchievementStore.parse(JSON.stringify({
		"version": 1,
		"reactions": {
			"over_9000": {"first_date": "11/18/26", "first_run": "run_1", "runs": 3, "last_run": "run_3"},
			"broken": "not a dict",
			"empty": {},
		},
	}))
	var reactions: Dictionary = store.get("reactions", {})
	assert_eq(reactions.size(), 1)
	var entry: Dictionary = reactions.get("over_9000", {})
	assert_eq(str(entry.get("first_date", "")), "11/18/26")
	assert_eq(str(entry.get("first_run", "")), "run_1")
	assert_eq(int(entry.get("runs", 0)), 3)
	assert_eq(str(entry.get("last_run", "")), "run_3")


func test_record_sets_first_fields_once() -> void:
	var store := AchievementStore.empty_store()
	assert_true(AchievementStore.record(store, "over_9000", "run_1", "11/18/26"))
	var entry: Dictionary = store.get("reactions", {}).get("over_9000", {})
	assert_eq(str(entry.get("first_date", "")), "11/18/26")
	assert_eq(str(entry.get("first_run", "")), "run_1")
	assert_eq(int(entry.get("runs", 0)), 1)
	# Same run again: no change, first fields preserved.
	assert_false(AchievementStore.record(store, "over_9000", "run_1", "11/19/26"))
	assert_eq(str(entry.get("first_date", "")), "11/18/26")
	assert_eq(int(entry.get("runs", 0)), 1)


func test_record_increments_runs_once_per_run() -> void:
	var store := AchievementStore.empty_store()
	AchievementStore.record(store, "over_9000", "run_1", "11/18/26")
	AchievementStore.record(store, "over_9000", "run_1", "11/18/26")
	AchievementStore.record(store, "over_9000", "run_2", "11/19/26")
	AchievementStore.record(store, "over_9000", "run_2", "11/19/26")
	AchievementStore.record(store, "over_9000", "run_3", "11/20/26")
	var entry: Dictionary = store.get("reactions", {}).get("over_9000", {})
	assert_eq(int(entry.get("runs", 0)), 3)
	assert_eq(str(entry.get("last_run", "")), "run_3")


func test_record_ignores_empty_id_or_run_key() -> void:
	var store := AchievementStore.empty_store()
	assert_false(AchievementStore.record(store, "", "run_1", "11/18/26"))
	assert_false(AchievementStore.record(store, "over_9000", "", "11/18/26"))
	assert_eq(AchievementStore.earned_count(store), 0)


func test_earned_count_counts_reactions() -> void:
	var store := AchievementStore.empty_store()
	AchievementStore.record(store, "over_9000", "run_1", "11/18/26")
	AchievementStore.record(store, "big_dog_best_dog", "run_1", "11/18/26")
	assert_eq(AchievementStore.earned_count(store), 2)


func test_save_and_load_round_trip() -> void:
	_remove_test_file()
	var store := AchievementStore.empty_store()
	AchievementStore.record(store, "over_9000", "run_1", "11/18/26")
	assert_true(AchievementStore.save_store(store, TEST_PATH))
	var loaded := AchievementStore.load_store(TEST_PATH)
	assert_eq(AchievementStore.earned_count(loaded), 1)
	var entry: Dictionary = loaded.get("reactions", {}).get("over_9000", {})
	assert_eq(str(entry.get("first_run", "")), "run_1")
	assert_eq(int(entry.get("runs", 0)), 1)
	_remove_test_file()


func test_load_missing_file_returns_empty_store() -> void:
	_remove_test_file()
	var store := AchievementStore.load_store(TEST_PATH)
	assert_eq(AchievementStore.earned_count(store), 0)