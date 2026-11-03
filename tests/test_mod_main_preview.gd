extends "test_runner.gd"
## Regression tests for the dev toast preview's presentation wiring.
##
## The preview previously bypassed the reaction sound sink, so previewing a sound
## reaction was silent while gameplay played it. It must use the same table.

const ModMain = preload("../mod_main.gd")
const ToastCatalog = preload("../notifications/toast_catalog.gd")
const ReactionSounds = preload("../audio/reaction_sounds.gd")
const ReactionDefinitions = preload("../reactions/reaction_definitions.gd")


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


func _preview(entry_id: String):
	var mod = ModMain.new()
	var sounds = FakeSoundRegistry.new()
	mod._reaction_sounds = sounds
	mod._toast_catalog_script = ToastCatalog
	mod._notification_host = FakeHost.new()
	var entry := ToastCatalog.find(
		ToastCatalog.entries(),
		ToastCatalog.KIND_REACTION,
		entry_id,
	)
	mod._preview_toast(entry)
	return {"mod": mod, "sounds": sounds, "entry": entry}


func test_preview_over_9000_plays_sound_and_submits_toast() -> void:
	var result = _preview(ReactionDefinitions.OVER_9000)
	assert_false(result["entry"].is_empty(), "over_9000 must be in the catalog")
	assert_eq(result["sounds"].played, [ReactionDefinitions.OVER_9000])
	assert_eq(result["mod"]._notification_host.submitted.size(), 1)
	result["mod"].free()


func test_preview_seven_or_more_lives_plays_fanfare_and_submits_toast() -> void:
	var result = _preview(ReactionDefinitions.SEVEN_OR_MORE_LIVES)
	assert_false(result["entry"].is_empty(), "7_or_more_lives must be in the catalog")
	assert_eq(result["sounds"].played, [ReactionDefinitions.SEVEN_OR_MORE_LIVES])
	assert_eq(result["mod"]._notification_host.submitted.size(), 1)
	result["mod"].free()


func test_preview_other_reaction_stays_silent_but_submits_toast() -> void:
	var result = _preview(ReactionDefinitions.SIX_SEVEN)
	assert_false(result["entry"].is_empty(), "six_seven must be in the catalog")
	assert_empty(result["sounds"].played)
	assert_eq(result["mod"]._notification_host.submitted.size(), 1)
	result["mod"].free()


func test_reaction_sound_mapping_is_table_driven() -> void:
	var mod = ModMain.new()
	var sounds = FakeSoundRegistry.new()
	mod._reaction_sounds = sounds
	mod._play_reaction_sound(ReactionDefinitions.OVER_9000)
	mod._play_reaction_sound(ReactionDefinitions.SEVEN_OR_MORE_LIVES)
	mod._play_reaction_sound(ReactionDefinitions.SIX_NINE)
	assert_eq(
		sounds.played,
		[ReactionDefinitions.OVER_9000, ReactionDefinitions.SEVEN_OR_MORE_LIVES],
	)
	mod.free()
