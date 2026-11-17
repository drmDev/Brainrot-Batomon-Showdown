extends "test_runner.gd"
## Unit tests for reactions/reaction_player.gd.

const ReactionPlayer = preload("../reactions/reaction_player.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")


## Build a player whose log sink appends to the returned Array.
func _new_player(lines: Array):
	return ReactionPlayer.new(func(line): lines.append(str(line)))


func test_play_logs_exact_line() -> void:
	var lines: Array = []
	_new_player(lines).play({"id": Catalog.SIX_SEVEN, "detail": "Lives 6, Wins 7"})
	assert_eq(lines.size(), 1)
	assert_eq(
		str(lines[0]),
		"Brain Rot: REACTION | %s | Lives 6, Wins 7" % Catalog.SIX_SEVEN,
	)


func test_play_all_dispatches_once_per_reaction() -> void:
	var lines: Array = []
	_new_player(lines).play_all([
		{"id": Catalog.SIX_SEVEN, "detail": "Lives 6, Wins 7"},
		{"id": "other", "detail": "x"},
	])
	assert_eq(lines.size(), 2)
	assert_eq(
		str(lines[0]),
		"Brain Rot: REACTION | %s | Lives 6, Wins 7" % Catalog.SIX_SEVEN,
	)
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
	_new_player(lines).play_all([
		null,
		"nope",
		{"id": Catalog.SIX_SEVEN, "detail": "d"},
	])
	assert_eq(lines.size(), 1)


func test_missing_detail_logs_empty_detail() -> void:
	var lines: Array = []
	_new_player(lines).play({"id": Catalog.SIX_SEVEN})
	assert_eq(lines.size(), 1)
	assert_eq(
		str(lines[0]),
		"Brain Rot: REACTION | %s | " % Catalog.SIX_SEVEN,
	)


func test_play_forwards_reaction_id_to_sound_sink() -> void:
	var sounds: Array = []
	var player = ReactionPlayer.new(
		Callable(),
		Callable(),
		func(id): sounds.append(str(id)),
	)
	player.play({
		"id": Catalog.OVER_9000,
		"detail": "slot 0 monster.name.x poison 9002",
	})
	assert_eq(sounds, [Catalog.OVER_9000])


func test_play_all_forwards_every_reaction_id_to_sound_sink() -> void:
	var sounds: Array = []
	var player = ReactionPlayer.new(
		Callable(),
		Callable(),
		func(id): sounds.append(str(id)),
	)
	player.play_all([
		{"id": Catalog.SIX_SEVEN, "detail": "Lives 6, Wins 7"},
		{
			"id": Catalog.OVER_9000,
			"detail": "slot 0 monster.name.x poison 9002",
		},
	])
	assert_eq(sounds, [Catalog.SIX_SEVEN, Catalog.OVER_9000])


func test_play_resolves_species_icon_and_sets_request_texture() -> void:
	var submitted: Array = []
	var tex := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	var player = ReactionPlayer.new(
		Callable(),
		func(request): submitted.append(request),
		Callable(),
		func(species_key): return tex if species_key == "monster.name.cinnabark" else null,
	)
	player.play({
		"id": Catalog.OVER_9000,
		"detail": "Cinnabark contributed 9.0K poison in battle!",
		"species_key": "monster.name.cinnabark",
	})
	assert_eq(submitted.size(), 1)
	if submitted.size() == 1:
		assert_eq(submitted[0].icon_texture, tex)


func test_play_without_species_key_leaves_icon_texture_null() -> void:
	var submitted: Array = []
	var player = ReactionPlayer.new(
		Callable(),
		func(request): submitted.append(request),
		Callable(),
		func(_species_key): return null,
	)
	player.play({"id": Catalog.SIX_SEVEN, "detail": "Lives 6, Wins 7"})
	assert_eq(submitted.size(), 1)
	if submitted.size() == 1:
		assert_eq(submitted[0].icon_texture, null)


func test_play_icon_miss_leaves_icon_texture_null() -> void:
	var submitted: Array = []
	var player = ReactionPlayer.new(
		Callable(),
		func(request): submitted.append(request),
		Callable(),
		func(_species_key): return null,
	)
	player.play({
		"id": Catalog.OVER_9000,
		"detail": "x",
		"species_key": "monster.name.missing",
	})
	assert_eq(submitted.size(), 1)
	if submitted.size() == 1:
		assert_eq(submitted[0].icon_texture, null)
