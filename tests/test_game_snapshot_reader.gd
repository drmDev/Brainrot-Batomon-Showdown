extends "test_runner.gd"
## Unit tests for achievements/game_snapshot_reader.gd.

const GameSnapshotReader = preload("../achievements/game_snapshot_reader.gd")
const TestHelpers = preload("test_helpers.gd")

const RHIZUKA := "monster.name.rhizuka"
const CINNABARK := "monster.name.cinnabark"


func _new_reader():
	return GameSnapshotReader.new(func(obj, prop): return TestHelpers.probe(obj, prop))


# --- read_run ---

func test_read_run_null_returns_empty() -> void:
	assert_empty(_new_reader().read_run(null))


func test_read_run_captures_identity_and_day() -> void:
	var run = TestHelpers.run("gentleman", 4, [TestHelpers.monster(RHIZUKA, 2)])
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_eq(snapshot.get("kind"), "run")
	assert_eq(snapshot.get("trainer_id"), "gentleman")
	assert_eq(snapshot.get("current_round"), 4)


func test_read_run_keeps_team_and_bench_separate() -> void:
	var run = TestHelpers.run(
		"twins", 3,
		[TestHelpers.monster(RHIZUKA, 2)],
		[TestHelpers.monster(CINNABARK, 3)]
	)
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_eq(snapshot.get("team").size(), 1)
	assert_eq(snapshot.get("bench").size(), 1)
	assert_eq(snapshot["team"][0].get("name_key"), RHIZUKA)
	assert_eq(snapshot["bench"][0].get("name_key"), CINNABARK)


func test_read_run_monster_fields() -> void:
	var run = TestHelpers.run("gentleman", 3, [TestHelpers.monster(RHIZUKA, 2)])
	var entry: Dictionary = _new_reader().read_run(run)["team"][0]
	assert_eq(entry.get("name_key"), RHIZUKA)
	assert_eq(entry.get("level"), 2)


func test_read_run_missing_keys_stay_absent() -> void:
	var run = TestHelpers.FakeObject.new({"current_round": 3})
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_false(snapshot.has("trainer_id"), "missing trainer_id must stay absent")
	assert_false(snapshot.has("team"), "missing team must stay absent")
	assert_false(snapshot.has("bench"), "missing bench must stay absent")
	assert_eq(snapshot.get("current_round"), 3)


func test_read_run_monster_missing_level_stays_absent() -> void:
	var run = TestHelpers.run("gentleman", 3, [
		TestHelpers.FakeObject.new({"data": TestHelpers.FakeObject.new({"name_key": RHIZUKA})}),
	])
	var entry: Dictionary = _new_reader().read_run(run)["team"][0]
	assert_eq(entry.get("name_key"), RHIZUKA)
	assert_false(entry.has("level"), "missing level must stay absent")


func test_read_run_monster_without_data_keeps_level_only() -> void:
	var run = TestHelpers.run("gentleman", 3, [TestHelpers.FakeObject.new({"level": 2})])
	var team: Array = _new_reader().read_run(run)["team"]
	assert_eq(team.size(), 1)
	assert_false(team[0].has("name_key"), "missing data must not invent a species")
	assert_eq(team[0].get("level"), 2)


func test_read_run_null_monster_preserves_position() -> void:
	var run = TestHelpers.run("gentleman", 3, [null, TestHelpers.monster(RHIZUKA, 2)])
	var team: Array = _new_reader().read_run(run)["team"]
	assert_eq(team.size(), 2)
	assert_empty(team[0])
	assert_eq(team[1].get("name_key"), RHIZUKA)


func test_read_run_non_array_team_becomes_empty_array() -> void:
	var run = TestHelpers.FakeObject.new({"trainer_id": "gentleman", "team": "nope", "bench": []})
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_true(snapshot.get("team") is Array)
	assert_empty(snapshot.get("team"))


# --- read_run: run identity ---

func test_read_run_captures_run_id() -> void:
	var run = TestHelpers.FakeObject.new({"run_id": 12345, "trainer_id": "musician"})
	assert_eq(_new_reader().read_run(run).get("run_id"), "12345")


func test_read_run_missing_run_id_stays_absent() -> void:
	var run = TestHelpers.FakeObject.new({"trainer_id": "musician"})
	assert_false(_new_reader().read_run(run).has("run_id"))


# --- read_run: numeric progress fields ---

func test_read_run_captures_lives_and_wins() -> void:
	var run = TestHelpers.FakeObject.new({
		"trainer_id": "musician",
		"current_round": 4,
		"lives": 6,
		"current_wins": 7,
	})
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_eq(snapshot.get("lives"), 6)
	assert_eq(snapshot.get("current_wins"), 7)


func test_read_run_missing_lives_and_wins_stay_absent() -> void:
	var run = TestHelpers.FakeObject.new({"trainer_id": "musician", "current_round": 4})
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_false(snapshot.has("lives"))
	assert_false(snapshot.has("current_wins"))


func test_read_run_null_numeric_values_stay_absent() -> void:
	var run = TestHelpers.FakeObject.new({
		"current_round": null,
		"lives": null,
		"current_wins": null,
	})
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_false(snapshot.has("current_round"), "null current_round must not raise or match")
	assert_false(snapshot.has("lives"))
	assert_false(snapshot.has("current_wins"))


func test_read_run_non_numeric_values_stay_absent() -> void:
	var run = TestHelpers.FakeObject.new({
		"current_round": "4",
		"lives": "6",
		"current_wins": true,
	})
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_false(snapshot.has("current_round"))
	assert_false(snapshot.has("lives"))
	assert_false(snapshot.has("current_wins"))


func test_read_run_float_numeric_values_are_truncated() -> void:
	var run = TestHelpers.FakeObject.new({"lives": 6.0, "current_wins": 7.0})
	var snapshot: Dictionary = _new_reader().read_run(run)
	assert_eq(snapshot.get("lives"), 6)
	assert_eq(snapshot.get("current_wins"), 7)


# --- read_run: derived shop income ---

func test_read_run_income_uses_day_and_passive_bonuses() -> void:
	var run = TestHelpers.FakeObject.new({
		"current_round": 4,
		"_active_passives": [
			TestHelpers.FakeObject.new({"gold_gain": 10}),
			TestHelpers.FakeObject.new({"gold_gain": 7}),
		],
	})
	# BASE_INCOME + INCOME_PER_DAY * (day - 1) + passive bonuses.
	assert_eq(_new_reader().read_run(run).get("income"), 35 + 5 * 3 + 17)


func test_read_run_income_is_base_schedule_without_passives() -> void:
	var run = TestHelpers.FakeObject.new({"current_round": 1})
	assert_eq(_new_reader().read_run(run).get("income"), 35)


func test_read_run_income_absent_without_day() -> void:
	var run = TestHelpers.FakeObject.new({
		"_active_passives": [TestHelpers.FakeObject.new({"gold_gain": 10})],
	})
	assert_false(_new_reader().read_run(run).has("income"))


func test_read_run_income_ignores_invalid_passives() -> void:
	var run = TestHelpers.FakeObject.new({
		"current_round": 2,
		"_active_passives": [
			null,
			TestHelpers.FakeObject.new({}),
			TestHelpers.FakeObject.new({"gold_gain": 5.0}),
			TestHelpers.FakeObject.new({"gold_gain": 3}),
		],
	})
	# Invalid entries contribute nothing; numeric floats truncate like int(value).
	assert_eq(_new_reader().read_run(run).get("income"), 35 + 5 + 5 + 3)


func test_read_battle_includes_derived_income() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var snapshot: Dictionary = _new_reader().read_battle(TestHelpers.FakeObject.new({}), run)
	assert_eq(snapshot.get("income"), 35 + 5 * 2)


# --- read_battle ---

func test_read_battle_null_state_returns_empty() -> void:
	var run = TestHelpers.run("musician", 3, [])
	assert_empty(_new_reader().read_battle(null, run))


func test_read_battle_merges_run_and_battle_fields() -> void:
	var run = TestHelpers.run("musician", 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 1200000.0)])
	var snapshot: Dictionary = _new_reader().read_battle(state, run)
	assert_eq(snapshot.get("kind"), "battle")
	assert_eq(snapshot.get("trainer_id"), "musician")
	assert_eq(snapshot.get("current_round"), 3)
	assert_eq(snapshot.get("team").size(), 1)
	assert_eq(snapshot.get("battle_over"), true)
	assert_eq(snapshot.get("battle_units").size(), 1)


func test_read_battle_unit_fields() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 1, 1200000.0)])
	var unit: Dictionary = _new_reader().read_battle(state, run)["battle_units"][0]
	assert_eq(unit.get("team_id"), 0)
	assert_eq(unit.get("slot_index"), 1)
	assert_eq(unit.get("shield_granted"), 1200000.0)


func test_read_battle_unit_accumulated_metrics() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var unit = TestHelpers.battle_unit_metrics(0, 2, {
		"damage_dealt": 67.0,
		"healing_done": 12.0,
		"shield_granted": 5.0,
	})
	var state = TestHelpers.battle_state([unit])
	var entry: Dictionary = _new_reader().read_battle(state, run)["battle_units"][0]
	assert_eq(entry.get("damage_dealt"), 67.0)
	assert_eq(entry.get("healing_done"), 12.0)
	assert_eq(entry.get("shield_granted"), 5.0)


func test_read_battle_unit_status_counters() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var unit = TestHelpers.battle_unit_metrics(0, 0, {
		"burn_inflicted": 67,
		"poison_inflicted": 3,
		"shock_inflicted": 0,
	})
	var state = TestHelpers.battle_state([unit])
	var entry: Dictionary = _new_reader().read_battle(state, run)["battle_units"][0]
	assert_eq(entry.get("burn_inflicted"), 67)
	assert_eq(entry.get("poison_inflicted"), 3)
	assert_eq(entry.get("shock_inflicted"), 0)


func test_read_battle_unit_missing_metrics_stay_absent() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 1.0)])
	var entry: Dictionary = _new_reader().read_battle(state, run)["battle_units"][0]
	assert_false(entry.has("damage_dealt"))
	assert_false(entry.has("healing_done"))
	assert_false(entry.has("burn_inflicted"))
	assert_false(entry.has("poison_inflicted"))
	assert_false(entry.has("shock_inflicted"))


func test_read_battle_unit_null_metrics_stay_absent() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var unit = TestHelpers.FakeObject.new({
		"team_id": 0,
		"slot_index": 0,
		"shield_granted": null,
		"damage_dealt": null,
		"healing_done": "nope",
	})
	var state = TestHelpers.battle_state([unit])
	var entry: Dictionary = _new_reader().read_battle(state, run)["battle_units"][0]
	assert_false(entry.has("shield_granted"))
	assert_false(entry.has("damage_dealt"))
	assert_false(entry.has("healing_done"))


func test_read_battle_unit_status_counters_absent_when_missing() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 1.0)])
	var entry: Dictionary = _new_reader().read_battle(state, run)["battle_units"][0]
	assert_false(entry.has("burn_inflicted"))
	assert_false(entry.has("poison_inflicted"))
	assert_false(entry.has("shock_inflicted"))


func test_read_battle_missing_simulation_keeps_run_fields() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var snapshot: Dictionary = _new_reader().read_battle(TestHelpers.FakeObject.new({}), run)
	assert_eq(snapshot.get("kind"), "battle")
	assert_eq(snapshot.get("trainer_id"), "musician")
	assert_false(snapshot.has("battle_over"))
	assert_false(snapshot.has("battle_units"))


func test_read_battle_missing_battle_over_stays_absent() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var data = TestHelpers.FakeObject.new({"battle_units": []})
	var state = TestHelpers.FakeObject.new({"simulation": TestHelpers.FakeObject.new({"data": data})})
	var snapshot: Dictionary = _new_reader().read_battle(state, run)
	assert_false(snapshot.has("battle_over"))
	assert_true(snapshot.get("battle_units") is Array)


func test_read_battle_null_unit_skipped() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var state = TestHelpers.battle_state([null, TestHelpers.battle_unit(0, 0, 1.0)])
	assert_eq(_new_reader().read_battle(state, run)["battle_units"].size(), 1)


func test_read_battle_non_array_units_becomes_empty_array() -> void:
	var run = TestHelpers.run("musician", 3, [])
	var data = TestHelpers.FakeObject.new({"battle_units": "nope", "battle_over": true})
	var state = TestHelpers.FakeObject.new({"simulation": TestHelpers.FakeObject.new({"data": data})})
	var snapshot: Dictionary = _new_reader().read_battle(state, run)
	assert_true(snapshot.get("battle_units") is Array)
	assert_empty(snapshot.get("battle_units"))


func test_read_battle_without_run_still_captures_battle_fields() -> void:
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 1.0)])
	var snapshot: Dictionary = _new_reader().read_battle(state, null)
	assert_eq(snapshot.get("kind"), "battle")
	assert_false(snapshot.has("trainer_id"))
	assert_eq(snapshot.get("battle_over"), true)


# --- is_battle_snapshot_usable ---

func test_usable_requires_trainer_team_and_units() -> void:
	var reader = _new_reader()
	var run = TestHelpers.run("musician", 3, [TestHelpers.monster(CINNABARK, 3)])
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 1.0)])
	assert_true(reader.is_battle_snapshot_usable(reader.read_battle(state, run)))


func test_usable_false_for_empty_snapshot() -> void:
	assert_false(_new_reader().is_battle_snapshot_usable({}))


func test_usable_false_without_trainer() -> void:
	var reader = _new_reader()
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 1.0)])
	assert_false(reader.is_battle_snapshot_usable(reader.read_battle(state, null)))


func test_usable_false_without_team() -> void:
	var reader = _new_reader()
	var run = TestHelpers.FakeObject.new({"trainer_id": "musician"})
	var state = TestHelpers.battle_state([TestHelpers.battle_unit(0, 0, 1.0)])
	assert_false(reader.is_battle_snapshot_usable(reader.read_battle(state, run)))


func test_usable_false_without_battle_units() -> void:
	var reader = _new_reader()
	var run = TestHelpers.run("musician", 3, [])
	var snapshot: Dictionary = reader.read_battle(TestHelpers.FakeObject.new({}), run)
	assert_false(reader.is_battle_snapshot_usable(snapshot))


# --- read_battle: committed outcome (promoted run) ---

func _replay(overrides: Dictionary = {}):
	var base := {"run_id": "run-1", "current_round": 5, "current_wins": 9, "lives": 10}
	base.merge(overrides, true)
	return TestHelpers.FakeObject.new(base)


func _committed(overrides: Dictionary = {}):
	var base := {
		"run_id": "run-1",
		"current_round": 5,
		"current_wins": 10,
		"lives": 10,
		"pending_round_start": true,
		"pending_battle_opponent": [],
	}
	base.merge(overrides, true)
	return TestHelpers.FakeObject.new(base)


func test_read_battle_includes_committed_outcome_when_guards_pass() -> void:
	var snapshot: Dictionary = _new_reader().read_battle(
		TestHelpers.FakeObject.new({}), _replay(), _committed()
	)
	assert_eq(snapshot.get("outcome"), {"wins": 10, "lives": 10})


func test_read_battle_outcome_absent_without_committed_run() -> void:
	var snapshot: Dictionary = _new_reader().read_battle(
		TestHelpers.FakeObject.new({}), _replay()
	)
	assert_false(snapshot.has("outcome"))


func test_read_battle_outcome_absent_for_same_instance() -> void:
	var replay = _replay()
	var snapshot: Dictionary = _new_reader().read_battle(
		TestHelpers.FakeObject.new({}), replay, replay
	)
	assert_false(snapshot.has("outcome"))


func test_read_battle_outcome_absent_on_run_identity_mismatch() -> void:
	var state = TestHelpers.FakeObject.new({})
	var snapshot: Dictionary = _new_reader().read_battle(
		state, _replay(), _committed({"run_id": "run-2"})
	)
	assert_false(snapshot.has("outcome"), "run_id mismatch")
	snapshot = _new_reader().read_battle(
		state, _replay(), _committed({"current_round": 6})
	)
	assert_false(snapshot.has("outcome"), "round mismatch")


func test_read_battle_outcome_absent_when_round_not_pending() -> void:
	var snapshot: Dictionary = _new_reader().read_battle(
		TestHelpers.FakeObject.new({}), _replay(), _committed({"pending_round_start": false})
	)
	assert_false(snapshot.has("outcome"))


func test_read_battle_outcome_absent_with_pending_opponent() -> void:
	var snapshot: Dictionary = _new_reader().read_battle(
		TestHelpers.FakeObject.new({}), _replay(), _committed({"pending_battle_opponent": [{"id": "x"}]})
	)
	assert_false(snapshot.has("outcome"))


func test_read_battle_outcome_absent_for_non_numeric_totals() -> void:
	var state = TestHelpers.FakeObject.new({})
	var snapshot: Dictionary = _new_reader().read_battle(
		state, _replay(), _committed({"current_wins": "10"})
	)
	assert_false(snapshot.has("outcome"), "string wins")
	snapshot = _new_reader().read_battle(
		state, _replay(), _committed({"lives": null})
	)
	assert_false(snapshot.has("outcome"), "null lives")


