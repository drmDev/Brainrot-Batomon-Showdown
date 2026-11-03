extends "test_runner.gd"
## Unit tests for audio/reaction_sounds.gd (table-driven reaction audio).
##
## Every row is validated against the reaction registry, and every registered
## sound file is loaded, so adding a reaction sound cannot silently drift.

const ReactionSounds = preload("../audio/reaction_sounds.gd")
const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")
const ReactionDefinitions = preload("../reactions/reaction_definitions.gd")


func _registered_ids() -> Dictionary:
	var ids := {}
	for entry in ReactionEvaluator.registered_rows():
		ids[str(entry["row"].get("id", ""))] = true
	return ids


func test_every_sound_id_is_a_registered_reaction() -> void:
	var ids := _registered_ids()
	for id in ReactionSounds.REACTION_SOUNDS:
		assert_true(ids.has(str(id)), "unregistered reaction sound id: " + str(id))


func test_expected_sounds_are_mapped() -> void:
	assert_eq(
		ReactionSounds.REACTION_SOUNDS[ReactionDefinitions.OVER_9000]["file"],
		"over-9000.ogg",
	)
	assert_eq(
		ReactionSounds.REACTION_SOUNDS[ReactionDefinitions.SEVEN_OR_MORE_LIVES]["file"],
		"ff_fanfare.ogg",
	)


func test_every_sound_file_exists_and_loads() -> void:
	var host := Node.new()
	var sounds = ReactionSounds.new(host)
	for id in ReactionSounds.REACTION_SOUNDS:
		var file_name := sounds.file_for(str(id))
		assert_false(file_name.is_empty(), str(id))
		var sound = sounds._player_for(file_name)
		assert_true(FileAccess.file_exists(sound._path), "sound not found: " + sound._path)
		assert_true(sound._load_stream() != null, "cannot load: " + sound._path)
	host.free()


func test_unknown_reaction_is_a_no_op() -> void:
	var host := Node.new()
	var sounds = ReactionSounds.new(host)
	assert_false(sounds.has_sound("nope"))
	assert_eq(sounds.file_for("nope"), "")
	sounds.play_for("nope")
	assert_eq(host.get_child_count(), 0)
	host.free()


func test_same_file_reuses_one_sound() -> void:
	var host := Node.new()
	var sounds = ReactionSounds.new(host)
	var first = sounds._player_for("over-9000.ogg")
	var second = sounds._player_for("over-9000.ogg")
	assert_true(first == second, "rows sharing a file must share a player")
	host.free()


func test_enabled_gate_blocks_play() -> void:
	var host := Node.new()
	var called := [false]
	var sounds = ReactionSounds.new(host, func():
		called[0] = true
		return false)
	sounds.play_for(ReactionDefinitions.OVER_9000)
	assert_true(called[0])
	assert_eq(host.get_child_count(), 0)
	host.free()
