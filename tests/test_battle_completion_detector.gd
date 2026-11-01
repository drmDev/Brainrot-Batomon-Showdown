extends "test_runner.gd"
## Unit tests for achievements/battle_completion_detector.gd.

const BattleCompletionDetector = preload("../achievements/battle_completion_detector.gd")
const TestHelpers = preload("test_helpers.gd")


func test_poll_null_returns_false() -> void:
	var detector = BattleCompletionDetector.new()
	assert_false(detector.poll(null))


func test_not_over_returns_false() -> void:
	var detector = BattleCompletionDetector.new()
	assert_false(detector.poll(TestHelpers.battle_state([], false)))


func test_over_reports_once() -> void:
	var detector = BattleCompletionDetector.new()
	var state = TestHelpers.battle_state([], true)
	assert_true(detector.poll(state))
	assert_false(detector.poll(state))


func test_new_state_reports_again() -> void:
	var detector = BattleCompletionDetector.new()
	assert_true(detector.poll(TestHelpers.battle_state([], true)))
	assert_true(detector.poll(TestHelpers.battle_state([], true)))


func test_reset_reports_again() -> void:
	var detector = BattleCompletionDetector.new()
	var state = TestHelpers.battle_state([], true)
	assert_true(detector.poll(state))
	detector.reset()
	assert_true(detector.poll(state))


func test_missing_simulation_returns_false() -> void:
	var detector = BattleCompletionDetector.new()
	assert_false(detector.poll(TestHelpers.FakeObject.new({})))


func test_missing_data_returns_false() -> void:
	var detector = BattleCompletionDetector.new()
	var state = TestHelpers.FakeObject.new({"simulation": TestHelpers.FakeObject.new({})})
	assert_false(detector.poll(state))


# --- is_pending / consume (non-consuming completion) ---

func test_is_pending_does_not_consume() -> void:
	var detector = BattleCompletionDetector.new()
	var state = TestHelpers.battle_state([], true)
	assert_true(detector.is_pending(state))
	assert_true(detector.is_pending(state))
	assert_true(detector.consume())
	assert_false(detector.is_pending(state))


func test_consume_without_pending_returns_false() -> void:
	var detector = BattleCompletionDetector.new()
	assert_false(detector.consume())


func test_consume_twice_reports_once() -> void:
	var detector = BattleCompletionDetector.new()
	var state = TestHelpers.battle_state([], true)
	assert_true(detector.is_pending(state))
	assert_true(detector.consume())
	assert_false(detector.consume())


func test_pending_survives_repeated_polls_until_consumed() -> void:
	# Models mod_main retrying while the snapshot is not yet usable.
	var detector = BattleCompletionDetector.new()
	var state = TestHelpers.battle_state([], true)
	for i in range(5):
		assert_true(detector.is_pending(state))
	assert_true(detector.consume())
	assert_false(detector.is_pending(state))


func test_is_pending_false_before_battle_over() -> void:
	var detector = BattleCompletionDetector.new()
	var state = TestHelpers.battle_state([], false)
	assert_false(detector.is_pending(state))
	assert_false(detector.consume())


func test_is_pending_null_resets() -> void:
	var detector = BattleCompletionDetector.new()
	var state = TestHelpers.battle_state([], true)
	assert_true(detector.is_pending(state))
	assert_false(detector.is_pending(null))
	assert_true(detector.is_pending(state))
