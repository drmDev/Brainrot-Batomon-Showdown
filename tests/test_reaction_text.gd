extends "test_runner.gd"
## Unit tests for catalog/reaction_text.gd (the single source of reaction wording).

const ReactionText = preload("../catalog/reaction_text.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")


func test_every_registered_reaction_has_cases() -> void:
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		assert_gt(ReactionText.cases(id).size(), 0, "no cases for " + id)


func test_render_fills_battle_placeholders() -> void:
	var text := ReactionText.render("big_dog_best_dog", "battle", {
		"species_key": "monster.name.cinnabark",
		"metric": "shield",
		"value": 1234567,
	})
	assert_eq(text, "Cinnabark put up 1.2M shield in battle. What a good boy!")


func test_render_fills_level_placeholder() -> void:
	assert_eq(
		ReactionText.render("apes_together", "evolved", {}),
		"With Twins, made two Sunsages!",
	)


func test_render_leaves_no_unfilled_braces_for_known_cases() -> void:
	for id in ReactionText.TEMPLATES:
		for case_name in ReactionText.TEMPLATES[id]:
			var params := {
				"species_key": "monster.name.cinnabark",
				"metric": "damage",
				"value": 67,
				"level": 3,
				"income": 67,
				"lives": 6,
				"day": 7,
				"wins": 7,
			}
			var text := ReactionText.render(id, case_name, params)
			assert_false(text.contains("{"), "%s/%s left a placeholder: %s" % [id, case_name, text])
			assert_false(text.contains("}"), "%s/%s left a placeholder: %s" % [id, case_name, text])


func test_placeholders_reports_used_tokens() -> void:
	assert_eq(
		ReactionText.placeholders("big_dog_best_dog", "battle"),
		["species", "value"],
	)
	assert_empty(ReactionText.placeholders("apes_together", "evolved"))


func test_missing_case_falls_back_to_title() -> void:
	assert_eq(
		ReactionText.render("six_seven", "does_not_exist", {}),
		Catalog.title_for("six_seven"),
	)


func test_abbreviate_number() -> void:
	assert_eq(ReactionText.abbreviate_number(999), "999")
	assert_eq(ReactionText.abbreviate_number(1000), "1.0K")
	assert_eq(ReactionText.abbreviate_number(9002), "9.0K")
	assert_eq(ReactionText.abbreviate_number(1000000), "1.0M")
	assert_eq(ReactionText.abbreviate_number(1234567), "1.2M")


func test_format_species_name() -> void:
	assert_eq(ReactionText.format_species_name("monster.name.cinnabark"), "Cinnabark")
	assert_eq(ReactionText.format_species_name(""), "Unknown")


func test_metric_word() -> void:
	assert_eq(ReactionText.metric_word("heal"), "healing")
	assert_eq(ReactionText.metric_word("unknown"), "unknown")
