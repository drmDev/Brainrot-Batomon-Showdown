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
