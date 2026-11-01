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
