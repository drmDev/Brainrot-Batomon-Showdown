extends "test_runner.gd"
## Regression tests for the run-scoped reaction phase gate in the coordinator.
##
## The game promotes the completed run into RunManager.data before the visual
## battle ends (verified in BatomonHelperBridge read_battle_outcome), so the
## post-battle lives/wins are already visible while the battle plays. Run-scoped
## reactions (6 7, 6 9) must therefore be deferred to the shop (the start of the
## next day) so the player never sees them before the result.

const ReactionCoordinator = preload("../reactions/reaction_coordinator.gd")
const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")
const OccurrenceStore = preload("../core/occurrence_store.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")

const SIX_SEVEN := Catalog.SIX_SEVEN
const SIX_NINE := Catalog.SIX_NINE


## Records play_all() calls so a test can assert nothing fired.
class FakePlayer:
	extends RefCounted
	var played: Array = []

	func play_all(reactions: Array) -> void:
		for reaction in reactions:
			played.append(reaction)


## A coordinator with the reaction systems wired to fakes; no tree, log, or toasts.
func _new_coordinator():
	var coord = ReactionCoordinator.new()
	coord._evaluator = ReactionEvaluator.new()
	coord._player = FakePlayer.new()
	return coord


## Run snapshot in the shop layout: lives + day + wins.
func _snap(lives: int, day: int, wins: int) -> Dictionary:
	return {
		"kind": "run",
		"lives": lives,
		"current_round": day,
		"current_wins": wins,
	}


## Run snapshot with an explicit run_id (for persistence tests).
func _snap_with_run(run_id: String, lives: int, day: int, wins: int) -> Dictionary:
	var snap := _snap(lives, day, wins)
	snap["run_id"] = run_id
	return snap


func _ids(reactions: Array) -> Array:
	var ids: Array = []
	for reaction in reactions:
		ids.append(str(reaction.get("id", "")))
	return ids


# --- gate: only the shop evaluates run-scoped reactions ---

func test_run_reaction_skipped_outside_shop_even_when_matching() -> void:
	var coord = _new_coordinator()
	coord.poll_reactions(_snap(6, 7, 0), false)
	assert_empty(coord._player.played)


func test_run_reaction_fires_in_shop_once() -> void:
	var coord = _new_coordinator()
	coord.poll_reactions(_snap(6, 7, 0), true)
	assert_eq(_ids(coord._player.played), [SIX_SEVEN])
	# Repeated matching shop polls must not retrigger.
	coord.poll_reactions(_snap(6, 7, 0), true)
	assert_eq(_ids(coord._player.played), [SIX_SEVEN])


# --- the reported bug: 9 lives -> lose 3 -> 6 lives during a battle ---

func test_battle_then_shop_defers_six_seven_to_next_day() -> void:
	var coord = _new_coordinator()
	# Day 6 shop: still 9 lives, nothing fires.
	coord.poll_reactions(_snap(9, 6, 6), true)
	assert_empty(coord._player.played)

	# Battle/results: RunManager.data already shows the committed 6 lives, but the
	# battle phase must not evaluate run-scoped reactions.
	coord.poll_reactions(_snap(6, 6, 6), false)
	assert_empty(coord._player.played)

	# Next day's shop: 6 lives on day 7 fires 6 7.
	coord.poll_reactions(_snap(6, 7, 6), true)
	assert_eq(_ids(coord._player.played), [SIX_SEVEN])


func test_battle_then_shop_defers_six_nine_to_next_day() -> void:
	var coord = _new_coordinator()
	coord.poll_reactions(_snap(9, 8, 8), true)
	assert_empty(coord._player.played)

	coord.poll_reactions(_snap(6, 8, 8), false)
	assert_empty(coord._player.played)

	coord.poll_reactions(_snap(6, 9, 8), true)
	assert_eq(_ids(coord._player.played), [SIX_NINE])


func test_wins_path_also_defers_to_shop() -> void:
	# 6 lives with 7 wins can appear mid-battle because wins are committed there.
	var coord = _new_coordinator()
	coord.poll_reactions(_snap(6, 1, 7), false)
	assert_empty(coord._player.played)
	coord.poll_reactions(_snap(6, 1, 7), true)
	assert_eq(_ids(coord._player.played), [SIX_SEVEN])


func test_persistence_prevents_retrigger_after_restart() -> void:
	# A reaction that fired in a prior session must not re-fire after Save & Quit.
	var path := "user://brain_rot_test/coord_occurrences.cfg"
	var abs := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs)

	var store = OccurrenceStore.new()
	store.use_store(path)

	# First session: the reaction fires and is persisted under the run id.
	var coord1 = ReactionCoordinator.new()
	coord1._store = store
	coord1._evaluator = ReactionEvaluator.new()
	coord1._player = FakePlayer.new()
	coord1.poll_reactions(_snap_with_run("run_1", 6, 7, 0), true)
	assert_eq(_ids(coord1._player.played), [SIX_SEVEN])

	# Second session (restart): same run id, so the reaction must stay silent.
	var coord2 = ReactionCoordinator.new()
	coord2._store = store
	coord2._evaluator = ReactionEvaluator.new()
	coord2._player = FakePlayer.new()
	coord2.poll_reactions(_snap_with_run("run_1", 6, 7, 0), true)
	assert_empty(coord2._player.played)

	DirAccess.remove_absolute(abs)
