extends "test_runner.gd"
## Unit tests for hud/toast_preview_panel.gd.
##
## The panel is presentation-only: verify open/close, dropdown population,
## selection, and that Play forwards the selected entry every time.

const ToastPreviewPanel = preload("../hud/toast_preview_panel.gd")
const ReactionDefinitions = preload("../reactions/reaction_definitions.gd")


func _entries() -> Array:
	return [
		{
			"kind": "achievement",
			"id": "oh_yeah",
			"label": "Achievement - Oh Yeah!",
			"title": "Oh Yeah!",
			"description": "Made double kool aid man level 3s at once !",
		},
		{
			"kind": "reaction",
			"id": ReactionDefinitions.SIX_SEVEN,
			"label": "Reaction - 6 7",
			"title": "6 7",
			"description": "Lives 6, Wins 7",
		},
	]


func test_panel_starts_closed_with_populated_dropdown() -> void:
	var panel = ToastPreviewPanel.new(_entries(), Callable())
	assert_false(panel.is_open())
	assert_eq(panel.entry_count(), 2)
	assert_eq(str(panel.selected_entry().get("id", "")), "oh_yeah")
	panel.free()


func test_open_and_close_toggle_the_panel() -> void:
	var panel = ToastPreviewPanel.new(_entries(), Callable())
	panel.open_panel()
	assert_true(panel.is_open())
	panel.close_panel()
	assert_false(panel.is_open())
	panel.free()


func test_select_index_changes_the_selected_entry() -> void:
	var panel = ToastPreviewPanel.new(_entries(), Callable())
	panel.select_index(1)
	assert_eq(str(panel.selected_entry().get("id", "")), ReactionDefinitions.SIX_SEVEN)
	# Out-of-range selections are ignored.
	panel.select_index(99)
	assert_eq(str(panel.selected_entry().get("id", "")), ReactionDefinitions.SIX_SEVEN)
	panel.free()


func test_play_forwards_entry_and_allows_repeats() -> void:
	var played: Array = []
	var panel = ToastPreviewPanel.new(_entries(), func(entry): played.append(entry))
	panel.select_index(1)
	panel.play_selected()
	panel.play_selected()
	assert_eq(played.size(), 2)
	assert_eq(str(played[0].get("id", "")), ReactionDefinitions.SIX_SEVEN)
	assert_eq(str(played[1].get("id", "")), ReactionDefinitions.SIX_SEVEN)
	panel.free()


func test_play_with_no_entries_does_nothing() -> void:
	var played: Array = []
	var panel = ToastPreviewPanel.new([], func(entry): played.append(entry))
	assert_eq(panel.entry_count(), 0)
	assert_empty(panel.selected_entry())
	panel.play_selected()
	assert_empty(played)
	panel.free()
