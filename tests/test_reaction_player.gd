extends "test_runner.gd"
## Unit tests for reactions/reaction_player.gd.

const ReactionPlayer = preload("../reactions/reaction_player.gd")


## Build a player whose log sink appends to the returned Array.
func _new_player(lines: Array):
	return ReactionPlayer.new(func(line): lines.append(str(line)))


func test_play_logs_exact_line() -> void:
	var lines: Array = []
	_new_player(lines).play({"id": "six_seven", "detail": "Lives 6, Wins 7"})
	assert_eq(lines.size(), 1)
	assert_eq(str(lines[0]), "Brain Rot: REACTION | six_seven | Lives 6, Wins 7")


func test_play_all_dispatches_once_per_reaction() -> void:
	var lines: Array = []
	_new_player(lines).play_all([
		{"id": "six_seven", "detail": "Lives 6, Wins 7"},
		{"id": "other", "detail": "x"},
	])
	assert_eq(lines.size(), 2)
	assert_eq(str(lines[0]), "Brain Rot: REACTION | six_seven | Lives 6, Wins 7")
	assert_eq(str(lines[1]), "Brain Rot: REACTION | other | x")


func test_play_all_empty_logs_nothing() -> void:
	var lines: Array = []
	_new_player(lines).play_all([])
	assert_empty(lines)


func test_play_without_id_logs_nothing() -> void:
	var lines: Array = []
	_new_player(lines).play({"detail": "Lives 6, Wins 7"})
	assert_empty(lines)


func test_play_all_skips_non_dictionary_entries() -> void:
	var lines: Array = []
	_new_player(lines).play_all([null, "nope", {"id": "six_seven", "detail": "d"}])
	assert_eq(lines.size(), 1)


func test_missing_detail_logs_empty_detail() -> void:
	var lines: Array = []
	_new_player(lines).play({"id": "six_seven"})
	assert_eq(lines.size(), 1)
	assert_eq(str(lines[0]), "Brain Rot: REACTION | six_seven | ")
