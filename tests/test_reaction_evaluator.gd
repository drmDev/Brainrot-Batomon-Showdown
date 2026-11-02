extends "test_runner.gd"
## Unit tests for reactions/reaction_evaluator.gd.
##
## Battle reactions are data-driven: BATTLE_CASES mirrors the evaluator's
## BATTLE_REACTIONS table, so every battle test runs the same matrix for each value
## (67, 69, 420, 666). Adding a value reaction means one row here, not a new test block.

const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")
const AchievementStore = preload("../achievements/achievement_store.gd")

const SIX_SEVEN := "six_seven"
const SIX_NINE := "six_nine"
const FOUR_TWENTY := "four_twenty"
const SIX_SIX_SIX := "six_six_six"
const OVER_9000 := "over_9000"
const FLAWLESS_VICTORY := "flawless_victory"

const CINNABARK := "monster.name.cinnabark"
const RHIZUKA := "monster.name.rhizuka"

## One row per battle reaction: id + the exact final total that triggers it.
const BATTLE_CASES := [
	{"id": SIX_SEVEN, "value": 67},
	{"id": SIX_NINE, "value": 69},
	{"id": FOUR_TWENTY, "value": 420},
	{"id": SIX_SIX_SIX, "value": 666},
]

## One row per numeric income reaction: id + the shop income that triggers it.
const INCOME_CASES := [
	{"id": SIX_SEVEN, "income": 67},
	{"id": SIX_NINE, "income": 69},
	{"id": FOUR_TWENTY, "income": 420},
	{"id": SIX_SIX_SIX, "income": 666},
]

## Metric key -> log label, in the evaluator's BATTLE_METRICS order.
const BATTLE_METRICS := [
	{"key": "damage_dealt", "label": "damage"},
	{"key": "healing_done", "label": "heal"},
	{"key": "shield_granted", "label": "shield"},
	{"key": "burn_inflicted", "label": "burn"},
	{"key": "poison_inflicted", "label": "poison"},
	{"key": "shock_inflicted", "label": "shock"},
]


func _new_evaluator():
	return ReactionEvaluator.new()


## Run snapshot with the original lives/wins pair (Day absent).
func _snap(lives, wins) -> Dictionary:
	return {"kind": "run", "lives": lives, "current_wins": wins}


## Run snapshot with the shop's [Lives, Day, Wins] layout.
func _snap_layout(lives, day, wins) -> Dictionary:
	return {"kind": "run", "lives": lives, "current_round": day, "current_wins": wins}


## Run snapshot carrying only the derived shop income.
func _snap_income(income) -> Dictionary:
	return {"kind": "run", "income": income}


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


func _team_one() -> Array:
	return [{"name_key": CINNABARK, "level": 3}]


func _team_two() -> Array:
	return [
		{"name_key": CINNABARK, "level": 3},
		{"name_key": RHIZUKA, "level": 3},
	]


## Ids of the returned reactions, in order.
func _ids(reactions: Array) -> Array:
	var ids: Array = []
	for reaction in reactions:
		ids.append(str(reaction.get("id", "")))
	return ids


## The single expected detail line for a match.
func _detail(species: String, label: String, value: int) -> String:
	return "%s %s %d" % [_display_species(species), label, value]


## Test-side mirror of the evaluator's species display formatting.
func _display_species(species_key: String) -> String:
	if species_key.is_empty() or species_key == "?":
		return "Unknown"
	return species_key.split(".")[-1].capitalize()


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


# --- 1a. shop layout: Lives 6 + Day/Wins 7 or 9 ---

func test_lives6_day7_triggers_six_seven() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll(_snap_layout(6, 7, 0))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), SIX_SEVEN)
		assert_eq(str(earned[0].get("detail", "")), "Lives 6, Day 7")


func test_lives6_wins7_triggers_six_seven_with_layout() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll(_snap_layout(6, 1, 7))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), SIX_SEVEN)
		assert_eq(str(earned[0].get("detail", "")), "Lives 6, Wins 7")


func test_lives6_day9_triggers_six_nine() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll(_snap_layout(6, 9, 0))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), SIX_NINE)
		assert_eq(str(earned[0].get("detail", "")), "Lives 6, Day 9")


func test_lives6_wins9_triggers_six_nine() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll(_snap_layout(6, 1, 9))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), SIX_NINE)
		assert_eq(str(earned[0].get("detail", "")), "Lives 6, Wins 9")


func test_lives5_day9_does_not_trigger_six_nine() -> void:
	assert_empty(_new_evaluator().poll(_snap_layout(5, 9, 0)))


# --- 1b. income triggers for every numeric reaction ---

func test_income_values_trigger_each_numeric_reaction() -> void:
	for case in INCOME_CASES:
		var income := int(case["income"])
		var evaluator = _new_evaluator()
		var earned: Array = evaluator.poll(_snap_income(income))
		var label := str(case["id"])
		assert_eq(earned.size(), 1, label)
		if earned.size() == 1:
			assert_eq(str(earned[0].get("id", "")), label, label)
			assert_eq(str(earned[0].get("detail", "")), "Income %d" % income, label)


func test_income_near_misses_do_not_trigger() -> void:
	for case in INCOME_CASES:
		var income := int(case["income"])
		for delta in [-1, 1]:
			var evaluator = _new_evaluator()
			assert_empty(
				evaluator.poll(_snap_income(income + delta)),
				"%s %d" % [case["id"], income + delta]
			)


func test_over_9000_income_is_strictly_greater_than_9000() -> void:
	var evaluator = _new_evaluator()
	assert_empty(evaluator.poll(_snap_income(9000)))
	var earned: Array = evaluator.poll(_snap_income(9001))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), OVER_9000)
		assert_eq(str(earned[0].get("detail", "")), "Income 9001")


func test_layout_and_income_combine_detail() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll({
		"kind": "run",
		"lives": 6,
		"current_round": 7,
		"current_wins": 7,
		"income": 67,
	})
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("detail", "")), "Lives 6, Day 7, Wins 7, Income 67")


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


# --- 8. battle-scoped: any player unit metric exactly <value> ---
#
# Every test below loops over BATTLE_CASES, so each battle reaction gets the same
# coverage. The `label` argument on assertions names the case that failed.

func test_battle_each_metric_triggers_for_every_reaction() -> void:
	for case in BATTLE_CASES:
		var value := int(case["value"])
		for metric in BATTLE_METRICS:
			var label := "%s %s" % [case["id"], metric["key"]]
			var evaluator = _new_evaluator()
			var earned: Array = evaluator.poll_battle(_battle(_team_one(), [
				_unit(0, {str(metric["key"]): value}),
			]))
			assert_eq(earned.size(), 1, label)
			if earned.size() == 1:
				assert_eq(str(earned[0].get("id", "")), str(case["id"]), label)
				assert_eq(
					str(earned[0].get("detail", "")),
					_detail(CINNABARK, str(metric["label"]), value),
					label
				)


func test_battle_near_misses_do_not_trigger() -> void:
	for case in BATTLE_CASES:
		var value := int(case["value"])
		for delta in [-1, 1]:
			var evaluator = _new_evaluator()
			assert_empty(
				evaluator.poll_battle(_battle(_team_one(), [
					_unit(0, {"damage_dealt": value + delta}),
				])),
				"%s %d" % [case["id"], value + delta]
			)


func test_battle_enemy_side_ignored() -> void:
	for case in BATTLE_CASES:
		var evaluator = _new_evaluator()
		assert_empty(
			evaluator.poll_battle(_battle(_team_one(), [
				_unit(0, {"damage_dealt": int(case["value"])}, 1),
			])),
			str(case["id"])
		)


func test_battle_repeated_polls_do_not_retrigger() -> void:
	for case in BATTLE_CASES:
		var evaluator = _new_evaluator()
		var snapshot := _battle(_team_one(), [_unit(0, {"damage_dealt": int(case["value"])})])
		assert_eq(evaluator.poll_battle(snapshot).size(), 1, str(case["id"]))
		assert_empty(evaluator.poll_battle(snapshot), str(case["id"]))
		assert_empty(evaluator.poll_battle(snapshot), str(case["id"]))


func test_battle_lowest_slot_wins() -> void:
	for case in BATTLE_CASES:
		var value := int(case["value"])
		var evaluator = _new_evaluator()
		# Slot 2 is listed first but slot 1 is lower, so slot 1 wins.
		var earned: Array = evaluator.poll_battle(_battle(_team_two(), [
			_unit(2, {"damage_dealt": value}),
			_unit(1, {"healing_done": value}),
		]))
		assert_eq(earned.size(), 1, str(case["id"]))
		if earned.size() == 1:
			assert_eq(
				str(earned[0].get("detail", "")),
				_detail(RHIZUKA, "heal", value),
				str(case["id"])
			)


func test_battle_same_unit_multiple_metrics_fire_once_for_first_metric() -> void:
	for case in BATTLE_CASES:
		var value := int(case["value"])
		var evaluator = _new_evaluator()
		var earned: Array = evaluator.poll_battle(_battle(_team_one(), [
			_unit(0, {"damage_dealt": value, "shield_granted": value}),
		]))
		assert_eq(earned.size(), 1, str(case["id"]))
		if earned.size() == 1:
			assert_eq(
				str(earned[0].get("detail", "")),
				_detail(CINNABARK, "damage", value),
				str(case["id"])
			)


func test_battle_fires_once_even_with_many_matches() -> void:
	for case in BATTLE_CASES:
		var value := int(case["value"])
		var evaluator = _new_evaluator()
		var snapshot := _battle(_team_two(), [
			_unit(0, {"damage_dealt": value, "healing_done": value}),
			_unit(1, {"shield_granted": value}),
		])
		var earned: Array = evaluator.poll_battle(snapshot)
		assert_eq(earned.size(), 1, str(case["id"]))
		if earned.size() == 1:
			assert_eq(
				str(earned[0].get("detail", "")),
				_detail(CINNABARK, "damage", value),
				str(case["id"])
			)
		assert_empty(evaluator.poll_battle(snapshot), str(case["id"]))


func test_battle_mid_fight_snapshot_does_not_trigger() -> void:
	for case in BATTLE_CASES:
		var value := int(case["value"])
		var evaluator = _new_evaluator()
		assert_empty(
			evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"damage_dealt": value})], false)),
			str(case["id"])
		)
		# The same totals at battle_over do trigger.
		assert_eq(
			evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"damage_dealt": value})])).size(),
			1,
			str(case["id"])
		)


func test_battle_missing_battle_over_does_not_trigger() -> void:
	for case in BATTLE_CASES:
		var evaluator = _new_evaluator()
		var snapshot := {
			"kind": "battle",
			"team": _team_one(),
			"battle_units": [_unit(0, {"damage_dealt": int(case["value"])})],
		}
		assert_empty(evaluator.poll_battle(snapshot), str(case["id"]))


func test_battle_reset_battle_permits_another_trigger() -> void:
	for case in BATTLE_CASES:
		var evaluator = _new_evaluator()
		var snapshot := _battle(_team_one(), [_unit(0, {"damage_dealt": int(case["value"])})])
		assert_eq(evaluator.poll_battle(snapshot).size(), 1, str(case["id"]))
		evaluator.reset_battle()
		assert_eq(evaluator.poll_battle(snapshot).size(), 1, str(case["id"]))


func test_battle_reset_run_clears_battle_tracking() -> void:
	for case in BATTLE_CASES:
		var evaluator = _new_evaluator()
		var snapshot := _battle(_team_one(), [_unit(0, {"damage_dealt": int(case["value"])})])
		assert_eq(evaluator.poll_battle(snapshot).size(), 1, str(case["id"]))
		evaluator.reset_run()
		assert_eq(evaluator.poll_battle(snapshot).size(), 1, str(case["id"]))


func test_battle_missing_or_invalid_metrics_ignored() -> void:
	for case in BATTLE_CASES:
		var value := int(case["value"])
		var evaluator = _new_evaluator()
		assert_empty(evaluator.poll_battle(_battle(_team_one(), [_unit(0, {})])), str(case["id"]))
		assert_empty(
			evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"damage_dealt": null})])),
			str(case["id"])
		)
		assert_empty(
			evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"damage_dealt": str(value)})])),
			str(case["id"])
		)
		assert_empty(
			evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"damage_dealt": true})])),
			str(case["id"])
		)


func test_battle_empty_snapshot_does_not_trigger() -> void:
	assert_empty(_new_evaluator().poll_battle({}))


func test_battle_unknown_species_logs_unknown() -> void:
	for case in BATTLE_CASES:
		var value := int(case["value"])
		var evaluator = _new_evaluator()
		var earned: Array = evaluator.poll_battle(_battle([], [_unit(3, {"damage_dealt": value})]))
		assert_eq(earned.size(), 1, str(case["id"]))
		if earned.size() == 1:
			assert_eq(
				str(earned[0].get("detail", "")),
				_detail("?", "damage", value),
				str(case["id"])
			)


# --- 8b. battle reactions are tracked independently ---

func test_battle_all_reactions_fire_in_one_battle() -> void:
	var evaluator = _new_evaluator()
	var team := [
		{"name_key": CINNABARK, "level": 3},
		{"name_key": RHIZUKA, "level": 3},
		{"name_key": "monster.name.onsetra", "level": 3},
		{"name_key": "monster.name.beetbud", "level": 3},
	]
	var earned: Array = evaluator.poll_battle(_battle(team, [
		_unit(0, {"damage_dealt": 67}),
		_unit(1, {"healing_done": 420}),
		_unit(2, {"shield_granted": 666}),
		_unit(3, {"poison_inflicted": 9002}),
	]))
	assert_eq(earned.size(), 4)
	var ids := _ids(earned)
	assert_true(ids.has(SIX_SEVEN))
	assert_true(ids.has(FOUR_TWENTY))
	assert_true(ids.has(SIX_SIX_SIX))
	assert_true(ids.has(OVER_9000))


func test_battle_same_unit_multiple_values_fire_all() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll_battle(_battle(_team_one(), [
		_unit(0, {
			"damage_dealt": 67,
			"shield_granted": 420,
			"burn_inflicted": 666,
			"poison_inflicted": 9002,
		}),
	]))
	assert_eq(earned.size(), 4)
	var ids := _ids(earned)
	assert_true(ids.has(SIX_SEVEN))
	assert_true(ids.has(FOUR_TWENTY))
	assert_true(ids.has(SIX_SIX_SIX))
	assert_true(ids.has(OVER_9000))


func test_battle_reactions_do_not_trigger_on_run_snapshot() -> void:
	# Battle reactions are battle-only: lives/wins never trigger them. (6/7 still
	# triggers six_seven's run condition, so assert on ids, not emptiness.)
	var evaluator = _new_evaluator()
	for snapshot in [_snap(6, 7), _snap(4, 20), _snap(666, 666), _snap(9002, 9002)]:
		var ids := _ids(evaluator.poll(snapshot))
		assert_false(ids.has(FOUR_TWENTY))
		assert_false(ids.has(SIX_SIX_SIX))
		assert_false(ids.has(OVER_9000))
	assert_eq(evaluator.occurrence_count(FOUR_TWENTY), 0)
	assert_eq(evaluator.occurrence_count(SIX_SIX_SIX), 0)
	assert_eq(evaluator.occurrence_count(OVER_9000), 0)


# --- 8c. over_9000: burn/poison/shock strictly above 9000 ---

const OVER_9000_METRICS := ["burn_inflicted", "poison_inflicted", "shock_inflicted"]


func test_over_9000_each_dot_metric_triggers_with_actual_total() -> void:
	for metric in BATTLE_METRICS:
		var key := str(metric["key"])
		if not OVER_9000_METRICS.has(key):
			continue
		var evaluator = _new_evaluator()
		var earned: Array = evaluator.poll_battle(_battle(_team_one(), [
			_unit(0, {key: 9002}),
		]))
		assert_eq(earned.size(), 1, key)
		if earned.size() == 1:
			assert_eq(str(earned[0].get("id", "")), OVER_9000, key)
			assert_eq(
				str(earned[0].get("detail", "")),
				_detail(CINNABARK, str(metric["label"]), 9002),
				key
			)


func test_over_9000_boundary_9000_does_not_trigger() -> void:
	for key in OVER_9000_METRICS:
		var evaluator = _new_evaluator()
		assert_empty(
			evaluator.poll_battle(_battle(_team_one(), [_unit(0, {key: 9000})])),
			key
		)


func test_over_9000_ignores_damage_heal_shield() -> void:
	for key in ["damage_dealt", "healing_done", "shield_granted"]:
		var evaluator = _new_evaluator()
		assert_empty(
			evaluator.poll_battle(_battle(_team_one(), [_unit(0, {key: 12000})])),
			key
		)


func test_over_9000_enemy_side_ignored() -> void:
	var evaluator = _new_evaluator()
	assert_empty(evaluator.poll_battle(_battle(_team_one(), [
		_unit(0, {"poison_inflicted": 9002}, 1),
	])))


func test_over_9000_repeated_polls_do_not_retrigger() -> void:
	var evaluator = _new_evaluator()
	var snapshot := _battle(_team_one(), [_unit(0, {"poison_inflicted": 9002})])
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)
	assert_empty(evaluator.poll_battle(snapshot))


func test_over_9000_lowest_slot_wins() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll_battle(_battle(_team_two(), [
		_unit(2, {"shock_inflicted": 12000}),
		_unit(1, {"poison_inflicted": 9001}),
	]))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("detail", "")), _detail(RHIZUKA, "poison", 9001))


func test_over_9000_first_dot_metric_wins_within_a_slot() -> void:
	# BATTLE_METRICS order is burn, poison, shock.
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll_battle(_battle(_team_one(), [
		_unit(0, {"shock_inflicted": 12000, "burn_inflicted": 9001}),
	]))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("detail", "")), _detail(CINNABARK, "burn", 9001))


func test_over_9000_mid_fight_snapshot_does_not_trigger() -> void:
	var evaluator = _new_evaluator()
	assert_empty(
		evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"poison_inflicted": 9002})], false))
	)
	assert_eq(
		evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"poison_inflicted": 9002})])).size(),
		1
	)


func test_over_9000_missing_battle_over_does_not_trigger() -> void:
	var evaluator = _new_evaluator()
	var snapshot := {
		"kind": "battle",
		"team": _team_one(),
		"battle_units": [_unit(0, {"poison_inflicted": 9002})],
	}
	assert_empty(evaluator.poll_battle(snapshot))


func test_over_9000_reset_battle_permits_another_trigger() -> void:
	var evaluator = _new_evaluator()
	var snapshot := _battle(_team_one(), [_unit(0, {"poison_inflicted": 9002})])
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)
	evaluator.reset_battle()
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)


func test_over_9000_reset_run_clears_battle_tracking() -> void:
	var evaluator = _new_evaluator()
	var snapshot := _battle(_team_one(), [_unit(0, {"poison_inflicted": 9002})])
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)
	evaluator.reset_run()
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)


func test_over_9000_invalid_values_ignored() -> void:
	var evaluator = _new_evaluator()
	assert_empty(evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"poison_inflicted": null})])))
	assert_empty(evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"poison_inflicted": "9002"})])))
	assert_empty(evaluator.poll_battle(_battle(_team_one(), [_unit(0, {"poison_inflicted": true})])))


func test_battle_unknown_comparison_never_matches() -> void:
	# A typo in a row's `comparison` must not silently behave as equality.
	var evaluator = _new_evaluator()
	var metric := {"key": "damage_dealt", "label": "damage"}
	var unit := _unit(0, {"damage_dealt": 67})
	assert_eq(evaluator._matching_total(unit, metric, {"id": "bogus", "value": 67, "comparison": "gte"}), null)
	assert_eq(evaluator._matching_total(unit, metric, {"id": "bogus", "value": 67, "comparison": "GT"}), null)
	# The two supported comparisons still work.
	assert_eq(evaluator._matching_total(unit, metric, {"id": "eq", "value": 67}), 67)
	assert_eq(evaluator._matching_total(unit, metric, {"id": "gt", "value": 66, "comparison": "gt"}), 67)


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


# --- 10. flawless_victory: committed post-battle wins/lives ---

func _battle_outcome(
	wins,
	lives,
	battle_over: bool = true,
	units: Array = [],
	team: Array = []
) -> Dictionary:
	return {
		"kind": "battle",
		"team": team,
		"battle_units": units,
		"battle_over": battle_over,
		"outcome": {"wins": wins, "lives": lives},
	}


func test_flawless_victory_triggers_at_ten_wins_and_ten_lives() -> void:
	var evaluator = _new_evaluator()
	var earned: Array = evaluator.poll_battle(_battle_outcome(10, 10))
	assert_eq(earned.size(), 1)
	if earned.size() == 1:
		assert_eq(str(earned[0].get("id", "")), FLAWLESS_VICTORY)
		assert_eq(str(earned[0].get("detail", "")), "Wins 10, Lives 10")
	assert_eq(evaluator.occurrence_count(FLAWLESS_VICTORY), 1)


func test_flawless_victory_near_misses_do_not_trigger() -> void:
	for pair in [[9, 10], [11, 10], [10, 9], [10, 11]]:
		assert_empty(
			_new_evaluator().poll_battle(_battle_outcome(pair[0], pair[1])),
			"%d/%d" % [pair[0], pair[1]]
		)


func test_flawless_victory_requires_a_valid_committed_outcome() -> void:
	assert_empty(_new_evaluator().poll_battle(_battle([], [], true)))
	for outcome in [
		{"wins": "10", "lives": 10},
		{"wins": 10, "lives": "10"},
		{"wins": 10.0, "lives": 10},
		{"wins": 10, "lives": null},
		{"wins": true, "lives": 10},
	]:
		var snapshot := _battle([], [], true)
		snapshot["outcome"] = outcome
		assert_empty(_new_evaluator().poll_battle(snapshot), str(outcome))


func test_flawless_victory_only_evaluated_at_battle_over() -> void:
	assert_empty(_new_evaluator().poll_battle(_battle_outcome(10, 10, false)))
	var snapshot := _battle_outcome(10, 10)
	snapshot.erase("battle_over")
	assert_empty(_new_evaluator().poll_battle(snapshot))


func test_flawless_victory_is_once_per_run_not_per_battle() -> void:
	var evaluator = _new_evaluator()
	var snapshot := _battle_outcome(10, 10)
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)
	assert_empty(evaluator.poll_battle(snapshot))
	evaluator.reset_battle()
	assert_empty(evaluator.poll_battle(snapshot), "reset_battle must not re-arm a run occurrence")
	evaluator.reset_run()
	assert_eq(evaluator.poll_battle(snapshot).size(), 1)


func test_flawless_victory_does_not_require_battle_units() -> void:
	var snapshot := _battle_outcome(10, 10)
	snapshot.erase("battle_units")
	assert_eq(_new_evaluator().poll_battle(snapshot).size(), 1)
	snapshot["battle_units"] = "not-an-array"
	assert_eq(_new_evaluator().poll_battle(snapshot).size(), 1)


func test_flawless_victory_does_not_trigger_on_run_snapshot() -> void:
	assert_empty(_new_evaluator().poll({
		"kind": "run",
		"lives": 10,
		"current_wins": 10,
		"current_round": 10,
	}))


func test_flawless_victory_coexists_with_unit_reactions() -> void:
	var earned: Array = _new_evaluator().poll_battle(_battle_outcome(
		10, 10, true, [_unit(0, {"damage_dealt": 67})], _team_one()
	))
	var ids := _ids(earned)
	assert_true(ids.has(SIX_SEVEN))
	assert_true(ids.has(FLAWLESS_VICTORY))


func test_registered_rows_include_the_outcome_scope() -> void:
	var found := false
	for entry in ReactionEvaluator.registered_rows():
		if str(entry["scope"]) == ReactionEvaluator.SCOPE_OUTCOME and str(entry["row"].get("id", "")) == FLAWLESS_VICTORY:
			found = true
	assert_true(found)
