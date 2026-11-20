extends "test_runner.gd"
## Regression tests for the dev toast preview's presentation wiring.
##
## The preview uses the same ReactionPlayer as gameplay, so it must render text,
## submit a toast, and forward the reaction sound identically.

const ReactionCoordinator = preload("../reactions/reaction_coordinator.gd")
const ReactionPlayer = preload("../reactions/reaction_player.gd")
const ReactionSounds = preload("../audio/reaction_sounds.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")


## Mirrors the real registry's contract: only ids with a sound row are recorded.
class FakeSoundRegistry:
	extends RefCounted
	var played: Array = []

	func play_for(reaction_id: String) -> void:
		if ReactionSounds.REACTION_SOUNDS.has(reaction_id):
			played.append(reaction_id)


class FakeHost:
	extends RefCounted
	var submitted: Array = []

	func submit(request) -> int:
		submitted.append(request)
		return 0


func _preview(match: Dictionary):
	var coord = ReactionCoordinator.new()
	var sounds = FakeSoundRegistry.new()
	var host = FakeHost.new()
	var player = ReactionPlayer.new(
		Callable(),
		func(request): host.submit(request),
		func(id): sounds.play_for(id),
		Callable(),
	)
	coord._player = player
	coord.play_preview(match)
	return {"coord": coord, "sounds": sounds, "host": host}


func test_preview_over_9000_plays_sound_and_submits_toast() -> void:
	var result = _preview({
		"id": Catalog.OVER_9000,
		"case": "battle",
		"params": {"species_key": "monster.name.cinnabark", "metric": "poison", "value": 9002},
		"species_key": "monster.name.cinnabark",
	})
	assert_eq(result["sounds"].played, [Catalog.OVER_9000])
	assert_eq(result["host"].submitted.size(), 1)


func test_preview_other_reaction_stays_silent_but_submits_toast() -> void:
	var result = _preview({
		"id": Catalog.SIX_SEVEN,
		"case": "lives_wins",
		"params": {"lives": 6, "wins": 7},
	})
	assert_empty(result["sounds"].played)
	assert_eq(result["host"].submitted.size(), 1)


func test_reaction_sound_mapping_is_table_driven() -> void:
	var coord = ReactionCoordinator.new()
	var sounds = FakeSoundRegistry.new()
	coord._sounds = sounds
	coord._play_sound(Catalog.OVER_9000)
	coord._play_sound(Catalog.SIX_NINE)
	assert_eq(
		sounds.played,
		[Catalog.OVER_9000],
	)
