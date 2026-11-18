extends "test_runner.gd"
## Unit tests for hud/toast_preview_panel.gd.
##
## The panel builds the same match Dictionary the evaluator produces, so Play
## forwards a match through the real presentation path.

const ToastPreviewPanel = preload("../hud/toast_preview_panel.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")
const ReactionText = preload("../catalog/reaction_text.gd")


func test_panel_starts_closed_with_populated_dropdowns() -> void:
	var panel = ToastPreviewPanel.new(Catalog.reactions(), Callable())
	assert_false(panel.is_open())
	assert_gt(panel.reaction_count(), 0)
	assert_eq(panel.selected_id(), Catalog.SIX_SEVEN)
	assert_eq(panel.selected_case(), "lives_day_wins")
	panel.free()


func test_open_and_close_toggle_the_panel() -> void:
	var panel = ToastPreviewPanel.new(Catalog.reactions(), Callable())
	panel.open_panel()
	assert_true(panel.is_open())
	panel.close_panel()
	assert_false(panel.is_open())
	panel.free()


func test_select_reaction_changes_selected_id_and_cases() -> void:
	var panel = ToastPreviewPanel.new(Catalog.reactions(), Callable())
	panel.select_reaction(1)
	assert_eq(panel.selected_id(), Catalog.SIX_NINE)
	assert_true(panel.case_count() > 0)
	panel.free()


func test_select_case_rebuilds_inputs() -> void:
	var panel = ToastPreviewPanel.new(Catalog.reactions(), Callable())
	panel.select_reaction(0)
	panel.select_case(4)
	assert_eq(panel.selected_case(), "battle")
	var match := panel.selected_match()
	assert_eq(str(match.get("id", "")), Catalog.SIX_SEVEN)
	assert_eq(str(match.get("case", "")), "battle")
	var params = match.get("params")
	assert_true(params is Dictionary)
	if params is Dictionary:
		assert_true(params.has("species_key"))
		assert_true(params.has("metric"))
	panel.free()


func test_play_forwards_match_and_allows_repeats() -> void:
	var played: Array = []
	var panel = ToastPreviewPanel.new(Catalog.reactions(), func(match): played.append(match))
	panel.select_reaction(0)
	panel.select_case(2)
	panel.play_selected()
	panel.play_selected()
	assert_eq(played.size(), 2)
	assert_eq(str(played[0].get("id", "")), Catalog.SIX_SEVEN)
	assert_eq(str(played[0].get("case", "")), "lives_wins")
	assert_eq(str(played[1].get("id", "")), Catalog.SIX_SEVEN)
	panel.free()


func test_play_with_no_entries_does_nothing() -> void:
	var played: Array = []
	var panel = ToastPreviewPanel.new([], func(match): played.append(match))
	assert_eq(panel.reaction_count(), 0)
	assert_eq(panel.selected_id(), "")
	panel.play_selected()
	assert_empty(played)
	panel.free()


func test_every_reaction_can_build_a_selected_match() -> void:
	var panel = ToastPreviewPanel.new(Catalog.reactions(), Callable())
	for i in range(panel.reaction_count()):
		panel.select_reaction(i)
		for j in range(panel.case_count()):
			panel.select_case(j)
			var match := panel.selected_match()
			assert_eq(str(match.get("id", "")), panel.selected_id())
			assert_eq(str(match.get("case", "")), panel.selected_case())
			var text := ReactionText.render(
				panel.selected_id(),
				panel.selected_case(),
				match.get("params"),
			)
			assert_false(text.is_empty())
	panel.free()
