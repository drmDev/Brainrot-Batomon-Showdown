extends "test_runner.gd"
## Unit tests for reactions/reaction_evaluator.gd.

const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")
const AchievementStore = preload("../achievements/achievement_store.gd")

const SIX_SEVEN := "six_seven"


func _new_evaluator():
	return ReactionEvaluator.new()


## Run snapshot with the two fields the reaction reads.
func _snap(lives, wins) -> Dictionary:
	return {"kind": "run", "lives": lives, "current_wins": wins}


func _temp_dir() -> String:
	var dir := OS.get_temp_dir().path_join("brainrot_reaction_test_%d" % Time.get_ticks_usec())
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


# --- 1. matching snapshot triggers exactly once ---

func test_lives6_wins7_triggers_once() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll(_snap(6, 7))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), SIX_SEVEN)
		assert_eq(str(earned[0].get("detail", "")), "Lives 6, Wins 7")
	assert_eq(evaluator.occurrence_count(SIX_SEVEN), 1)


# --- 2. near misses do not trigger ---

func test_lives6_wins6_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll(_snap(6, 6)))


func test_lives7_wins6_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll(_snap(7, 6)))


func test_lives7_wins7_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll(_snap(7, 7)))


func test_lives5_wins7_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll(_snap(5, 7)))


# --- 3. missing / invalid values do not trigger ---

func test_missing_lives_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll({"kind": "run", "current_wins": 7}))


func test_missing_wins_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll({"kind": "run", "lives": 6}))


func test_null_values_do_not_trigger() -> void:
	assert_empty(_new_evaluator().poll(_snap(null, null)))
	assert_empty(_new_evaluator().poll(_snap(6, null)))
	assert_empty(_new_evaluator().poll(_snap(null, 7)))


func test_string_values_do_not_trigger() -> void:
	assert_empty(_new_evaluator().poll(_snap("6", "7")))


func test_float_values_do_not_trigger() -> void:
	# The reader emits ints; a float here means the value was not a clean number.
	assert_empty(_new_evaluator().poll(_snap(6.0, 7.0)))


func test_bool_values_do_not_trigger() -> void:
	assert_empty(_new_evaluator().poll(_snap(true, true)))


func test_empty_snapshot_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll({}))


# --- 4. nonmatching -> matching triggers ---

func test_nonmatching_then_matching_triggers() -> void:
	var evaluator = _new_evaluator()
	assert_empty(evaluator.poll(_snap(8, 5)))
	assert_empty(evaluator.poll(_snap(7, 6)))
	var earned: Array = evaluator.poll(_snap(6, 7))
	assert_eq(earned.size(), 1)


# --- 5. repeated matching polls do not retrigger ---

func test_repeated_matching_polls_do_not_retrigger() -> void:
	var evaluator = _new_evaluator()
	assert_eq(evaluator.poll(_snap(6, 7)).size(), 1)
	assert_empty(evaluator.poll(_snap(6, 7)))
	assert_empty(evaluator.poll(_snap(6, 7)))
	assert_eq(evaluator.occurrence_count(SIX_SEVEN), 1)


# --- 6. matching -> nonmatching -> matching stays suppressed ---

func test_returning_to_condition_does_not_retrigger() -> void:
	var evaluator = _new_evaluator()
	assert_eq(evaluator.poll(_snap(6, 7)).size(), 1)
	assert_empty(evaluator.poll(_snap(9, 7)))
	assert_empty(evaluator.poll(_snap(6, 7)))
	assert_eq(evaluator.occurrence_count(SIX_SEVEN), 1)


func test_run_unavailable_does_not_rearm() -> void:
	var evaluator = _new_evaluator()
	assert_eq(evaluator.poll(_snap(6, 7)).size(), 1)
	# A menu round-trip (empty snapshot) must not clear occurrence tracking.
	assert_empty(evaluator.poll({}))
	assert_empty(evaluator.poll(_snap(6, 7)))


# --- 7. explicit new-run reset permits another trigger ---

func test_reset_run_permits_another_trigger() -> void:
	var evaluator = _new_evaluator()
	assert_eq(evaluator.poll(_snap(6, 7)).size(), 1)
	evaluator.reset_run()
	assert_eq(evaluator.occurrence_count(SIX_SEVEN), 0)
	assert_eq(evaluator.poll(_snap(6, 7)).size(), 1)


# --- battle-scoped: any player unit metric exactly 67 ---

const CINNABARK := "monster.name.cinnabark"


func _battle(team: Array, units: Array, battle_over: bool = true) -> Dictionary:
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


func test_battle_damage_67_triggers_with_unit_and_metric() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	var earned: Array = evaluator.poll_battle(_battle(team, [_unit(0, {"damage_dealt": 67.0})]))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), SIX_SEVEN)
		assert_eq(str(earned[0].get("detail", "")), "slot 0 %s damage 67" % CINNABARK)


func test_battle_each_metric_67_triggers() -> void:
	for metric in ["damage_dealt", "healing_done", "shield_granted", "burn_inflicted", "poison_inflicted", "shock_inflicted"]:
		var evaluator = _new_evaluator()
		var team := [{"name_key": CINNABARK, "level": 3}]
		var earned: Array = evaluator.poll_battle(_battle(team, [_unit(0, {metric: 67})]))
		assert_eq(earned.size(), 1, "metric %s should trigger" % metric)


func test_battle_metric_66_and_68_do_not_trigger() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	assert_empty(evaluator.poll_battle(_battle(team, [_unit(0, {"damage_dealt": 66.0})])))
	assert_empty(evaluator.poll_battle(_battle(team, [_unit(0, {"damage_dealt": 68.0})])))


func test_battle_enemy_side_ignored() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	assert_empty(evaluator.poll_battle(_battle(team, [_unit(0, {"damage_dealt": 67.0}, 1)])))


func test_battle_repeated_polls_do_not_retrigger() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	var snapshot := _battle(team, [_unit(0, {"damage_dealt": 67.0})])
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)
	assert_empty(evaluator.poll_battle(snapshot))
	assert_empty(evaluator.poll_battle(snapshot))


func test_battle_multiple_units_fire_once_for_lowest_slot() -> void:
	var evaluator = _new_evaluator()
	var team := [
		{"name_key": CINNABARK, "level": 3},
		{"name_key": "monster.name.rhizuka", "level": 3},
	]
	var earned: Array = evaluator.poll_battle(_battle(team, [
		_unit(0, {"damage_dealt": 67.0}),
		_unit(1, {"healing_done": 67.0}),
	]))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("detail", "")), "slot 0 %s damage 67" % CINNABARK)


func test_battle_lowest_slot_wins_regardless_of_unit_order() -> void:
	var evaluator = _new_evaluator()
	var team := [
		{"name_key": CINNABARK, "level": 3},
		{"name_key": "monster.name.rhizuka", "level": 3},
	]
	# Slot 3 is listed first but slot 1 is lower, so slot 1 wins.
	var earned: Array = evaluator.poll_battle(_battle(team, [
		_unit(3, {"damage_dealt": 67.0}),
		_unit(1, {"healing_done": 67.0}),
	]))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("detail", "")), "slot 1 monster.name.rhizuka heal 67")


func test_battle_same_unit_multiple_metrics_fire_once_for_first_metric() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	var earned: Array = evaluator.poll_battle(_battle(team, [
		_unit(0, {"damage_dealt": 67.0, "shield_granted": 67.0}),
	]))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("detail", "")), "slot 0 %s damage 67" % CINNABARK)


func test_battle_fires_once_even_with_many_matches() -> void:
	var evaluator = _new_evaluator()
	var team := [
		{"name_key": CINNABARK, "level": 3},
		{"name_key": "monster.name.rhizuka", "level": 3},
		{"name_key": "monster.name.onsetra", "level": 3},
	]
	var snapshot := _battle(team, [
		_unit(0, {"damage_dealt": 67.0, "healing_done": 67.0}),
		_unit(1, {"shield_granted": 67.0, "burn_inflicted": 67}),
		_unit(2, {"poison_inflicted": 67, "shock_inflicted": 67}),
	])
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)
	assert_empty(evaluator.poll_battle(snapshot))


func test_battle_reset_battle_permits_another_trigger() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	var snapshot := _battle(team, [_unit(0, {"damage_dealt": 67.0})])
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)
	evaluator.reset_battle()
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)


func test_battle_reset_run_clears_battle_tracking() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	var snapshot := _battle(team, [_unit(0, {"damage_dealt": 67.0})])
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)
	evaluator.reset_run()
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)


func test_battle_missing_or_invalid_metrics_ignored() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	assert_empty(evaluator.poll_battle(_battle(team, [_unit(0, {})])))
	assert_empty(evaluator.poll_battle(_battle(team, [_unit(0, {"damage_dealt": null})])))
	assert_empty(evaluator.poll_battle(_battle(team, [_unit(0, {"damage_dealt": "67"})])))
	assert_empty(evaluator.poll_battle(_battle(team, [_unit(0, {"damage_dealt": true})])))


func test_battle_empty_snapshot_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll_battle({}))


func test_battle_mid_fight_snapshot_does_not_trigger() -> void:
	# Only the final battle totals count; an in-progress battle never matches.
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	var snapshot := _battle(team, [_unit(0, {"damage_dealt": 67.0})], false)
	assert_empty(evaluator.poll_battle(snapshot))
	# The same totals at battle_over do trigger.
	assert_eq(evaluator.poll_battle(_battle(team, [_unit(0, {"damage_dealt": 67.0})])).size(), 1)


func test_battle_missing_battle_over_does_not_trigger() -> void:
	var evaluator = _new_evaluator()
	var team := [{"name_key": CINNABARK, "level": 3}]
	var snapshot := {"kind": "battle", "team": team, "battle_units": [_unit(0, {"damage_dealt": 67.0})]}
	assert_empty(evaluator.poll_battle(snapshot))


func test_battle_unknown_species_logs_question_mark() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll_battle(_battle([], [_unit(3, {"damage_dealt": 67.0})]))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("detail", "")), "slot 3 ? damage 67")


# --- 9. achievement completion state does not suppress reactions ---

func test_achievement_completion_does_not_suppress_reaction() -> void:
	var dir := _temp_dir()
	var store = AchievementStore.new(dir)
	store.mark_completed(SIX_SEVEN)
	store.mark_completed("oh_yeah")
	assert_true(store.is_completed(SIX_SEVEN))

	# The reaction evaluator takes no store, so completion cannot affect it.
	var evaluator = _new_evaluator()
	assert_eq(evaluator.poll(_snap(6, 7)).size(), 1)
	_cleanup(dir)
