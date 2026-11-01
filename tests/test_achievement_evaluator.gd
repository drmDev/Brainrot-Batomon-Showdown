extends "test_runner.gd"
## Unit tests for achievements/achievement_evaluator.gd.
##
## The evaluator consumes snapshot Dictionaries (see game_snapshot_reader.gd), so these
## tests build snapshots directly with TestHelpers.run_snapshot / battle_snapshot.

const AchievementEvaluator = preload("../achievements/achievement_evaluator.gd")
const TestHelpers = preload("test_helpers.gd")

const GENTLEMAN := "gentleman"
const TWINS := "twins"
const OTHER := "musician"

const RHIZUKA := "monster.name.rhizuka"
const BEETBUD := "monster.name.beetbud"
const BEETDOWN := "monster.name.beetdown"
const FRILLET := "monster.name.frillet"
const DEWLOTL := "monster.name.dewlotl"
const CINNABARK := "monster.name.cinnabark"

# Documented tuning values. Pinned here so changing the evaluator constants is an
# intentional, reviewable change (see test_tuning_constants_match_documented_values).
const EXPECTED_ARM_WINDOW_MS := 2000


## Build an evaluator. Pass a TestHelpers.TestClock to make time deterministic;
## otherwise the evaluator falls back to the engine clock.
func _new_evaluator(clock = null):
	if clock == null:
		return AchievementEvaluator.new()
	return AchievementEvaluator.new(clock.now)


## Assert exactly one achievement was earned and that its id matches. Guarded so an
## empty result records a failure instead of crashing the whole suite on `earned[0]`
## (GDScript has no try/catch, so an index error would abort every remaining test).
func assert_single_achievement(earned: Array, expected_id: String) -> void:
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), expected_id)


# --- poll: null / trainer gating ---

func test_poll_null_run_returns_empty() -> void:
	var evaluator = _new_evaluator()
	assert_empty(evaluator.poll({}))


func test_poll_other_trainer_returns_empty() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	assert_empty(evaluator.poll(run))


# --- Gentleman: "So I started blasting" ---

func test_gentleman_level2_rhizuka_on_day5_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 5, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	var earned: Array = evaluator.poll(run)
	assert_single_achievement(earned, "so_i_started_blasting")


func test_gentleman_rhizuka_on_bench_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 2, [], [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	var earned: Array = evaluator.poll(run)
	assert_single_achievement(earned, "so_i_started_blasting")


func test_gentleman_rhizuka_after_day5_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 6, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	assert_empty(evaluator.poll(run))


func test_gentleman_level1_rhizuka_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 3, [TestHelpers.monster_snapshot(RHIZUKA, 1)])
	assert_empty(evaluator.poll(run))


func test_gentleman_awards_only_once() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 3, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	assert_eq(evaluator.poll(run).size(), 1)
	assert_empty(evaluator.poll(run))


# --- Twins: evolution achievements ---

func test_twins_same_poll_double_beetdown_awards_oh_yeah() -> void:
	var evaluator = _new_evaluator()
	# Poll 1: level-2 Beetbud present, no Beetdown yet -> arms.
	var run1 = TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(BEETBUD, 2)])
	assert_empty(evaluator.poll(run1))
	# Poll 2: two level-3 Beetdowns appear -> award.
	var run2 = TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(BEETDOWN, 3),
		TestHelpers.monster_snapshot(BEETDOWN, 3),
	])
	var earned: Array = evaluator.poll(run2)
	assert_single_achievement(earned, "oh_yeah")


func test_twins_multi_poll_double_dewlotl_awards_mudkipz() -> void:
	var clock = TestHelpers.TestClock.new()
	var evaluator = _new_evaluator(clock)
	var run1 = TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(FRILLET, 2)])
	assert_empty(evaluator.poll(run1))
	# First Dewlotl appears on the next poll.
	clock.advance(500)
	var run2 = TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(FRILLET, 2),
		TestHelpers.monster_snapshot(DEWLOTL, 3),
	])
	assert_empty(evaluator.poll(run2))
	# Second Dewlotl appears on the following poll -> award.
	clock.advance(500)
	var run3 = TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(DEWLOTL, 3),
		TestHelpers.monster_snapshot(DEWLOTL, 3),
	])
	var earned: Array = evaluator.poll(run3)
	assert_single_achievement(earned, "herd_u_liek_mudkipz")


func test_twins_no_pre_evolution_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(DEWLOTL, 3),
		TestHelpers.monster_snapshot(DEWLOTL, 3),
	])
	assert_empty(evaluator.poll(run))


func test_twins_pre_evolution_without_evolution_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(BEETBUD, 2)])
	assert_empty(evaluator.poll(run))


func test_twins_single_evolution_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run1 = TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(BEETBUD, 2)])
	assert_empty(evaluator.poll(run1))
	var run2 = TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(BEETDOWN, 3)])
	assert_empty(evaluator.poll(run2))


# --- poll_battle: "Big Dog, Best Dog" ---

func test_big_dog_over_threshold_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(CINNABARK, 3)])
	var state = TestHelpers.battle_snapshot(OTHER, 3, run["team"], [
		TestHelpers.battle_unit_snapshot(0, 0, 1000001.0),
	])
	var earned: Array = evaluator.poll_battle(state)
	assert_single_achievement(earned, "big_dog_best_dog")


func test_big_dog_at_threshold_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(CINNABARK, 3)])
	var state = TestHelpers.battle_snapshot(OTHER, 3, run["team"], [
		TestHelpers.battle_unit_snapshot(0, 0, 1000000.0),
	])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_two_sub_threshold_units_in_one_slot_do_not_award() -> void:
	# Per-unit semantics: shield is NOT summed within a slot.
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(CINNABARK, 3)])
	var state = TestHelpers.battle_snapshot(OTHER, 3, run["team"], [
		TestHelpers.battle_unit_snapshot(0, 0, 600000.0),
		TestHelpers.battle_unit_snapshot(0, 0, 600000.0),
	])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_one_unit_over_threshold_among_sub_threshold_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(CINNABARK, 3)])
	var state = TestHelpers.battle_snapshot(OTHER, 3, run["team"], [
		TestHelpers.battle_unit_snapshot(0, 0, 600000.0),
		TestHelpers.battle_unit_snapshot(0, 0, 1200000.0),
	])
	var earned: Array = evaluator.poll_battle(state)
	assert_single_achievement(earned, "big_dog_best_dog")


func test_big_dog_non_cinnabark_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(RHIZUKA, 3)])
	var state = TestHelpers.battle_snapshot(OTHER, 3, run["team"], [
		TestHelpers.battle_unit_snapshot(0, 0, 2000000.0),
	])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_enemy_side_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(CINNABARK, 3)])
	var state = TestHelpers.battle_snapshot(OTHER, 3, run["team"], [
		TestHelpers.battle_unit_snapshot(1, 0, 2000000.0),
	])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_requires_battle_over() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(CINNABARK, 3)])
	var state = TestHelpers.battle_snapshot(OTHER, 3, run["team"], [
		TestHelpers.battle_unit_snapshot(0, 0, 2000000.0),
	], false)
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_is_stateless_across_calls() -> void:
	# The detector owns once-per-battle semantics; the evaluator is a pure rule check.
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(OTHER, 3, [TestHelpers.monster_snapshot(CINNABARK, 3)])
	var state = TestHelpers.battle_snapshot(OTHER, 3, run["team"], [
		TestHelpers.battle_unit_snapshot(0, 0, 2000000.0),
	])
	assert_eq(evaluator.poll_battle(state).size(), 1)
	assert_eq(evaluator.poll_battle(state).size(), 1)


# --- poll: run shape edge cases ---

func test_poll_run_missing_trainer_id_returns_empty() -> void:
	var evaluator = _new_evaluator()
	var run := {"current_round": 3, "team": [], "bench": []}
	assert_empty(evaluator.poll(run))


func test_poll_run_missing_team_and_bench_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run := {"trainer_id": GENTLEMAN, "current_round": 3}
	assert_empty(evaluator.poll(run))


func test_poll_monster_without_name_key_ignored() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 3, [{"level": 2}])
	assert_empty(evaluator.poll(run))


func test_poll_monster_missing_level_defaults_to_one() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 3, [{"name_key": RHIZUKA}])
	assert_empty(evaluator.poll(run))


# --- Gentleman: additional boundaries ---

func test_gentleman_day0_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 0, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	assert_empty(evaluator.poll(run))


func test_gentleman_day1_rhizuka_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 1, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	var earned: Array = evaluator.poll(run)
	assert_single_achievement(earned, "so_i_started_blasting")


func test_gentleman_level3_rhizuka_awards() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 3, [TestHelpers.monster_snapshot(RHIZUKA, 3)])
	var earned: Array = evaluator.poll(run)
	assert_single_achievement(earned, "so_i_started_blasting")


func test_gentleman_null_run_resets_award_flag() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 3, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	assert_eq(evaluator.poll(run).size(), 1)
	assert_empty(evaluator.poll({}))
	# The empty poll reset the once-per-run flag, so the same state awards again.
	assert_eq(evaluator.poll(run).size(), 1)


func test_gentleman_other_trainer_resets_award_flag() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 3, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	assert_eq(evaluator.poll(run).size(), 1)
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(OTHER, 3, [])))
	assert_eq(evaluator.poll(run).size(), 1)


# --- reset_run: explicit run transitions ---

func test_reset_run_clears_gentleman_flag() -> void:
	var evaluator = _new_evaluator()
	var run = TestHelpers.run_snapshot(GENTLEMAN, 3, [TestHelpers.monster_snapshot(RHIZUKA, 2)])
	assert_eq(evaluator.poll(run).size(), 1)
	assert_empty(evaluator.poll(run))
	# A new run with the same trainer must be able to award again.
	evaluator.reset_run()
	assert_eq(evaluator.poll(run).size(), 1)


func test_reset_run_clears_twins_baseline() -> void:
	var clock = TestHelpers.TestClock.new()
	var evaluator = _new_evaluator(clock)
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(FRILLET, 2)])))
	evaluator.reset_run()
	# The armed baseline is gone, so a double evolution no longer awards.
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(DEWLOTL, 3),
		TestHelpers.monster_snapshot(DEWLOTL, 3),
	])))


# --- Twins: arm-window and baseline semantics (deterministic clock) ---

func test_twins_arm_window_expires_without_award() -> void:
	var clock = TestHelpers.TestClock.new()
	var evaluator = _new_evaluator(clock)
	var run_armed = TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(FRILLET, 2)])
	assert_empty(evaluator.poll(run_armed))
	clock.advance(EXPECTED_ARM_WINDOW_MS + 1)
	# One evolution after the window closes: the arm expires, no award.
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(DEWLOTL, 3)])))
	# A second evolution later still does not award because the arm is gone.
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(DEWLOTL, 3),
		TestHelpers.monster_snapshot(DEWLOTL, 3),
	])))


func test_twins_arm_window_refreshes_while_pre_evolution_present() -> void:
	var clock = TestHelpers.TestClock.new()
	var evaluator = _new_evaluator(clock)
	var pre = TestHelpers.monster_snapshot(FRILLET, 2)
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [pre])))
	clock.advance(EXPECTED_ARM_WINDOW_MS - 500)
	# Still present near the edge: the window refreshes.
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [pre])))
	clock.advance(EXPECTED_ARM_WINDOW_MS - 500)
	# Past the original expiry but inside the refreshed window: arm survives.
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [pre])))
	clock.advance(1)
	var earned: Array = evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(DEWLOTL, 3),
		TestHelpers.monster_snapshot(DEWLOTL, 3),
	]))
	assert_single_achievement(earned, "herd_u_liek_mudkipz")


func test_twins_same_poll_baseline_from_prior_poll_awards() -> void:
	var clock = TestHelpers.TestClock.new()
	var evaluator = _new_evaluator(clock)
	# Prior poll: one evolved unit present, no pre-evolution. Baseline becomes 1.
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(BEETDOWN, 3)])))
	clock.advance(100)
	# The pre-evolution appears with three evolved units: 3 >= 1 + 2.
	var earned: Array = evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(BEETBUD, 2),
		TestHelpers.monster_snapshot(BEETDOWN, 3),
		TestHelpers.monster_snapshot(BEETDOWN, 3),
		TestHelpers.monster_snapshot(BEETDOWN, 3),
	]))
	assert_single_achievement(earned, "oh_yeah")


func test_twins_first_poll_pre_and_double_evolution_does_not_award() -> void:
	# Documents the current contract: with no prior baseline, a double landing in
	# the same poll as the pre-evolution is not recognized. Arming assumes the game
	# spreads the double across polls (see the evaluator's runtime-log note).
	# Revisit if gameplay shows the double can complete within one poll.
	var clock = TestHelpers.TestClock.new()
	var evaluator = _new_evaluator(clock)
	var run = TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(BEETBUD, 2),
		TestHelpers.monster_snapshot(BEETDOWN, 3),
		TestHelpers.monster_snapshot(BEETDOWN, 3),
	])
	assert_empty(evaluator.poll(run))


func test_twins_other_trainer_resets_evolution_state() -> void:
	var clock = TestHelpers.TestClock.new()
	var evaluator = _new_evaluator(clock)
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(FRILLET, 2)])))
	# A non-Gentleman, non-Twins run clears the armed baseline.
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(OTHER, 3, [])))
	var earned: Array = evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(DEWLOTL, 3),
		TestHelpers.monster_snapshot(DEWLOTL, 3),
	]))
	assert_empty(earned)


func test_twins_gentleman_run_resets_evolution_state() -> void:
	var clock = TestHelpers.TestClock.new()
	var evaluator = _new_evaluator(clock)
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [TestHelpers.monster_snapshot(FRILLET, 2)])))
	# Gentleman is not Twins: poll() clears evolution state at the end.
	assert_empty(evaluator.poll(TestHelpers.run_snapshot(GENTLEMAN, 3, [])))
	var earned: Array = evaluator.poll(TestHelpers.run_snapshot(TWINS, 3, [
		TestHelpers.monster_snapshot(DEWLOTL, 3),
		TestHelpers.monster_snapshot(DEWLOTL, 3),
	]))
	assert_empty(earned)


# --- poll_battle: Big Dog edge cases ---

func test_big_dog_two_slots_each_below_threshold_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var team := [
		TestHelpers.monster_snapshot(CINNABARK, 3),
		TestHelpers.monster_snapshot(CINNABARK, 3),
	]
	var state = TestHelpers.battle_snapshot(OTHER, 3, team, [
		TestHelpers.battle_unit_snapshot(0, 0, 600000.0),
		TestHelpers.battle_unit_snapshot(0, 1, 600000.0),
	])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_best_slot_awards() -> void:
	var evaluator = _new_evaluator()
	var team := [
		TestHelpers.monster_snapshot(CINNABARK, 3),
		TestHelpers.monster_snapshot(CINNABARK, 3),
	]
	var state = TestHelpers.battle_snapshot(OTHER, 3, team, [
		TestHelpers.battle_unit_snapshot(0, 0, 600000.0),
		TestHelpers.battle_unit_snapshot(0, 1, 1200000.0),
	])
	var earned: Array = evaluator.poll_battle(state)
	assert_single_achievement(earned, "big_dog_best_dog")


func test_big_dog_cinnabark_in_slot1_awards() -> void:
	var evaluator = _new_evaluator()
	var team := [
		TestHelpers.monster_snapshot(RHIZUKA, 3),
		TestHelpers.monster_snapshot(CINNABARK, 3),
	]
	var state = TestHelpers.battle_snapshot(OTHER, 3, team, [
		TestHelpers.battle_unit_snapshot(0, 1, 2000000.0),
	])
	var earned: Array = evaluator.poll_battle(state)
	assert_eq(earned.size(), 1)


func test_big_dog_slot_out_of_range_ignored() -> void:
	var evaluator = _new_evaluator()
	var team := [TestHelpers.monster_snapshot(CINNABARK, 3)]
	var state = TestHelpers.battle_snapshot(OTHER, 3, team, [
		TestHelpers.battle_unit_snapshot(0, 5, 2000000.0),
	])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_negative_slot_ignored() -> void:
	var evaluator = _new_evaluator()
	var team := [TestHelpers.monster_snapshot(CINNABARK, 3)]
	var state = TestHelpers.battle_snapshot(OTHER, 3, team, [
		TestHelpers.battle_unit_snapshot(0, -1, 2000000.0),
	])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_unit_missing_fields_ignored() -> void:
	var evaluator = _new_evaluator()
	var team := [TestHelpers.monster_snapshot(CINNABARK, 3)]
	var state = TestHelpers.battle_snapshot(OTHER, 3, team, [{"team_id": 0}])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_null_shield_ignored() -> void:
	var evaluator = _new_evaluator()
	var team := [TestHelpers.monster_snapshot(CINNABARK, 3)]
	var state = TestHelpers.battle_snapshot(OTHER, 3, team, [
		{"team_id": 0, "slot_index": 0, "shield_granted": null},
	])
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_null_unit_ignored() -> void:
	var evaluator = _new_evaluator()
	var team := [TestHelpers.monster_snapshot(CINNABARK, 3)]
	var state = TestHelpers.battle_snapshot(OTHER, 3, team, [
		null,
		TestHelpers.battle_unit_snapshot(0, 0, 2000000.0),
	])
	var earned: Array = evaluator.poll_battle(state)
	assert_eq(earned.size(), 1)


func test_big_dog_units_not_array_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var state := {
		"kind": "battle",
		"trainer_id": OTHER,
		"team": [TestHelpers.monster_snapshot(CINNABARK, 3)],
		"battle_over": true,
		"battle_units": "nope",
	}
	assert_empty(evaluator.poll_battle(state))


func test_big_dog_team_not_array_does_not_award() -> void:
	var evaluator = _new_evaluator()
	var state := {
		"kind": "battle",
		"trainer_id": OTHER,
		"team": "nope",
		"battle_over": true,
		"battle_units": [TestHelpers.battle_unit_snapshot(0, 0, 2000000.0)],
	}
	assert_empty(evaluator.poll_battle(state))


func test_poll_battle_empty_snapshot_returns_empty() -> void:
	var evaluator = _new_evaluator()
	assert_empty(evaluator.poll_battle({}))


func test_poll_battle_missing_battle_over_returns_empty() -> void:
	var evaluator = _new_evaluator()
	var state := {
		"kind": "battle",
		"trainer_id": OTHER,
		"team": [TestHelpers.monster_snapshot(CINNABARK, 3)],
		"battle_units": [TestHelpers.battle_unit_snapshot(0, 0, 2000000.0)],
	}
	assert_empty(evaluator.poll_battle(state))


# --- Achievement definition consistency ---

func test_achievement_ids_unique_and_well_formed() -> void:
	var definitions := [
		AchievementEvaluator.SO_I_STARTED_BLASTING,
		AchievementEvaluator.BIG_DOG,
		AchievementEvaluator.OH_YEAH,
		AchievementEvaluator.HERD_U_LIEK_MUDKIPZ,
	]
	var seen := {}
	for achievement in definitions:
		var id := str(achievement.get("id", ""))
		assert_false(id.is_empty(), "id must not be empty")
		assert_false(seen.has(id), "duplicate id: " + id)
		seen[id] = true
		assert_false(str(achievement.get("title", "")).is_empty(), "empty title: " + id)
		assert_false(str(achievement.get("description", "")).is_empty(), "empty description: " + id)
	assert_eq(definitions.size(), AchievementEvaluator.EVOLUTION_ACHIEVEMENTS.size() + 2)


func test_evolution_achievement_pairs_are_complete() -> void:
	for def in AchievementEvaluator.EVOLUTION_ACHIEVEMENTS:
		assert_false(str(def.get("pre_key", "")).is_empty(), "missing pre_key")
		assert_false(str(def.get("post_key", "")).is_empty(), "missing post_key")
		var achievement: Dictionary = def.get("achievement", {})
		assert_false(str(achievement.get("id", "")).is_empty(), "missing achievement id")


func test_tuning_constants_match_documented_values() -> void:
	assert_eq(AchievementEvaluator.EVOLUTION_ARM_WINDOW_MS, EXPECTED_ARM_WINDOW_MS)
	assert_eq(AchievementEvaluator.GENTLEMAN_DAY_LIMIT, 5)
	assert_eq(AchievementEvaluator.RHIZUKA_MIN_LEVEL, 2)
	assert_eq(AchievementEvaluator.PRE_EVOLVE_LEVEL, 2)
	assert_eq(AchievementEvaluator.BIG_DOG_SHIELD_THRESHOLD, 1000000.0)
	assert_eq(AchievementEvaluator.PLAYER_TEAM_ID, 0)
