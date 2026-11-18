extends "test_runner.gd"
## Unit tests for reactions/reaction_player.gd.

const ReactionPlayer = preload("../reactions/reaction_player.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")


## Build a player whose log sink appends to the returned Array.
func _new_player(lines: Array):
	return ReactionPlayer.new(func(line): lines.append(str(line)))


func test_play_logs_rendered_line() -> void:
	var lines: Array = []
	_new_player(lines).play({
		"id": Catalog.SIX_SEVEN,
		"case": "lives_wins",
		"params": {"lives": 6, "wins": 7},
	})
	assert_eq(lines.size(), 1)
	assert_eq(
		str(lines[0]),
		"Brain Rot: REACTION | six_seven | lives_wins | 6 lives left, 7 wins.",
	)


func test_play_all_dispatches_once_per_reaction() -> void:
	var lines: Array = []
	_new_player(lines).play_all([
		{"id": Catalog.SIX_SEVEN, "case": "lives_wins", "params": {"lives": 6, "wins": 7}},
		{"id": "other", "case": "x", "params": {}},
	])
	assert_eq(lines.size(), 2)
	assert_eq(
		str(lines[0]),
		"Brain Rot: REACTION | six_seven | lives_wins | 6 lives left, 7 wins.",
	)
	assert_eq(str(lines[1]), "Brain Rot: REACTION | other | x | other")


func test_play_all_empty_logs_nothing() -> void:
	var lines: Array = []
	_new_player(lines).play_all([])
	assert_empty(lines)


func test_play_without_id_logs_nothing() -> void:
	var lines: Array = []
	_new_player(lines).play({"case": "lives_wins", "params": {"lives": 6, "wins": 7}})
	assert_empty(lines)


func test_play_all_skips_non_dictionary_entries() -> void:
	var lines: Array = []
	_new_player(lines).play_all([
		null,
		"nope",
		{"id": Catalog.SIX_SEVEN, "case": "income", "params": {"income": 67}},
	])
	assert_eq(lines.size(), 1)


func test_missing_case_falls_back_to_title() -> void:
	var lines: Array = []
	_new_player(lines).play({"id": Catalog.SIX_SEVEN})
	assert_eq(lines.size(), 1)
	assert_eq(str(lines[0]), "Brain Rot: REACTION | six_seven |  | SIX SEVEN!")


func test_preview_logs_preview_marker() -> void:
	var lines: Array = []
	_new_player(lines).play({
		"id": Catalog.SIX_SEVEN,
		"case": "income",
		"params": {"income": 67},
	}, true)
	assert_eq(lines.size(), 1)
	assert_eq(
		str(lines[0]),
		"Brain Rot: PREVIEW | six_seven | income | Your shop income hit exactly 67.",
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
		"case": "battle",
		"params": {"species_key": "monster.name.x", "metric": "poison", "value": 9002},
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
		{"id": Catalog.SIX_SEVEN, "case": "lives_wins", "params": {"lives": 6, "wins": 7}},
		{"id": Catalog.OVER_9000, "case": "income", "params": {"income": 9002}},
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
		"case": "battle",
		"params": {"species_key": "monster.name.cinnabark", "metric": "poison", "value": 9002},
		"species_key": "monster.name.cinnabark",
	})
	assert_eq(submitted.size(), 1)
	if submitted.size() == 1:
		assert_eq(submitted[0].icon_texture, tex)


func test_play_without_species_key_uses_catalog_icon_texture() -> void:
	var submitted: Array = []
	var player = ReactionPlayer.new(
		Callable(),
		func(request): submitted.append(request),
		Callable(),
		func(_species_key): return null,
	)
	player.play({"id": Catalog.SIX_SEVEN, "case": "lives_wins", "params": {"lives": 6, "wins": 7}})
	assert_eq(submitted.size(), 1)
	if submitted.size() == 1:
		assert_true(submitted[0].icon_texture is Texture2D)


func test_play_species_icon_miss_leaves_icon_texture_null() -> void:
	var submitted: Array = []
	var player = ReactionPlayer.new(
		Callable(),
		func(request): submitted.append(request),
		Callable(),
		func(_species_key): return null,
	)
	player.play({
		"id": Catalog.APES_TOGETHER,
		"case": "owned",
		"params": {},
		"species_key": "monster.name.missing",
	})
	assert_eq(submitted.size(), 1)
	if submitted.size() == 1:
		assert_eq(submitted[0].icon_texture, null)
