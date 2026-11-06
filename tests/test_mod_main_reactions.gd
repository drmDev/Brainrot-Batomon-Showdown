extends "test_runner.gd"
## Regression tests for the run-scoped reaction phase gate in mod_main.gd.
##
## The game promotes the completed run into RunManager.data before the visual
## battle ends (verified in BatomonHelperBridge read_battle_outcome), so the
## post-battle lives/wins are already visible while the battle plays. Run-scoped
## reactions (6 7, 6 9) must therefore be deferred to the shop (the start of the
## next day) so the player never sees them before the result.

const ModMain = preload("../mod_main.gd")
const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")
const ReactionDefinitions = preload("../reactions/reaction_definitions.gd")

const SIX_SEVEN := ReactionDefinitions.SIX_SEVEN
const SIX_NINE := ReactionDefinitions.SIX_NINE


## Records play_all() calls so a test can assert nothing fired.
class FakePlayer:
	extends RefCounted
	var played: Array = []

	func play_all(reactions: Array) -> void:
		for reaction in reactions:
			played.append(reaction)


## A ModMain with the reaction systems wired to fakes; no tree, log, or toasts.
func _new_mod():
	var mod = ModMain.new()
	mod._reaction_evaluator = ReactionEvaluator.new()
	mod._reaction_player = FakePlayer.new()
	return mod


## Run snapshot in the shop layout: lives + day + wins.
func _snap(lives: int, day: int, wins: int) -> Dictionary:
	return {
		"kind": "run",
		"lives": lives,
		"current_round": day,
		"current_wins": wins,
	}


func _ids(reactions: Array) -> Array:
	var ids: Array = []
	for reaction in reactions:
		ids.append(str(reaction.get("id", "")))
	return ids


# --- gate: only the shop evaluates run-scoped reactions ---

func test_run_reaction_skipped_outside_shop_even_when_matching() -> void:
	var mod = _new_mod()
	mod._poll_reactions(_snap(6, 7, 0), false)
	assert_empty(mod._reaction_player.played)
	mod.free()


func test_run_reaction_fires_in_shop_once() -> void:
	var mod = _new_mod()
	mod._poll_reactions(_snap(6, 7, 0), true)
	assert_eq(_ids(mod._reaction_player.played), [SIX_SEVEN])
	# Repeated matching shop polls must not retrigger.
	mod._poll_reactions(_snap(6, 7, 0), true)
	assert_eq(_ids(mod._reaction_player.played), [SIX_SEVEN])
	mod.free()


# --- the reported bug: 9 lives -> lose 3 -> 6 lives during a battle ---

func test_battle_then_shop_defers_six_seven_to_next_day() -> void:
	var mod = _new_mod()
	# Day 6 shop: still 9 lives, nothing fires.
	mod._poll_reactions(_snap(9, 6, 6), true)
	assert_empty(mod._reaction_player.played)

	# Battle/results: RunManager.data already shows the committed 6 lives, but the
	# battle phase must not evaluate run-scoped reactions.
	mod._poll_reactions(_snap(6, 6, 6), false)
	assert_empty(mod._reaction_player.played)

	# Next day's shop: 6 lives on day 7 fires 6 7.
	mod._poll_reactions(_snap(6, 7, 6), true)
	assert_eq(_ids(mod._reaction_player.played), [SIX_SEVEN])
	mod.free()


func test_battle_then_shop_defers_six_nine_to_next_day() -> void:
	var mod = _new_mod()
	mod._poll_reactions(_snap(9, 8, 8), true)
	assert_empty(mod._reaction_player.played)

	mod._poll_reactions(_snap(6, 8, 8), false)
	assert_empty(mod._reaction_player.played)

	mod._poll_reactions(_snap(6, 9, 8), true)
	assert_eq(_ids(mod._reaction_player.played), [SIX_NINE])
	mod.free()


func test_wins_path_also_defers_to_shop() -> void:
	# 6 lives with 7 wins can appear mid-battle because wins are committed there.
	var mod = _new_mod()
	mod._poll_reactions(_snap(6, 1, 7), false)
	assert_empty(mod._reaction_player.played)
	mod._poll_reactions(_snap(6, 1, 7), true)
	assert_eq(_ids(mod._reaction_player.played), [SIX_SEVEN])
	mod.free()
