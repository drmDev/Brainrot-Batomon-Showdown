extends "test_runner.gd"
## Unit tests for hud/memories_panel.gd.

const MemoriesPanel = preload("../hud/memories_panel.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")


func _panel():
	return MemoriesPanel.new()


func test_popup_title_is_brain_rot_memories() -> void:
	var panel = _panel()
	assert_eq(panel._popup_title(), "Brain Rot Memories")
	panel.free()


func test_table_has_metric_best_unit_columns() -> void:
	var panel = _panel()
	assert_eq(panel._table_header_labels(), ["Metric", "Best", "Unit", "Date Acquired"])
	assert_eq(panel._table_row_count(), Catalog.BATTLE_METRIC_ORDER.size())
	panel.free()


func test_cell_text_shows_metric_value_and_unit() -> void:
	var panel = _panel()
	panel.set_scores({
		"metrics": {
			"damage": {"value": 12345, "unit": "monster.name.cinnabark", "date_acquired": "11/18/26"},
		},
	})
	assert_eq(panel._table_cell_text(0, 0), "Damage")
	assert_eq(panel._table_cell_text(0, 1), "12.3K")
	assert_eq(panel._table_cell_text(0, 2), "Cinnabark")
	assert_eq(panel._table_cell_text(0, 3), "11/18/26")
	panel.free()


func test_cell_text_shows_dash_when_missing() -> void:
	var panel = _panel()
	panel.set_scores({"metrics": {}})
	assert_eq(panel._table_cell_text(0, 1), "\u2014")
	assert_eq(panel._table_cell_text(0, 2), "\u2014")
	assert_eq(panel._table_cell_text(0, 3), "\u2014")
	panel.free()


func test_open_and_close_toggle() -> void:
	var panel = _panel()
	assert_false(panel.is_open())
	assert_false(panel.visible)
	panel.open_panel()
	assert_true(panel.is_open())
	assert_true(panel.visible)
	panel.close_panel()
	assert_false(panel.is_open())
	assert_false(panel.visible)
	panel.free()


func test_default_tab_is_high_scores() -> void:
	var panel = _panel()
	assert_eq(panel.current_tab(), MemoriesPanel.TAB_HIGH_SCORES)
	panel.free()


func test_open_resets_to_high_scores() -> void:
	var panel = _panel()
	panel.set_tab(MemoriesPanel.TAB_CHEEVOS)
	assert_eq(panel.current_tab(), MemoriesPanel.TAB_CHEEVOS)
	panel.open_panel()
	assert_eq(panel.current_tab(), MemoriesPanel.TAB_HIGH_SCORES)
	panel.free()


func test_set_tab_switches_and_ignores_invalid() -> void:
	var panel = _panel()
	panel.set_tab(MemoriesPanel.TAB_CHEEVOS)
	assert_eq(panel.current_tab(), MemoriesPanel.TAB_CHEEVOS)
	panel.set_tab(MemoriesPanel.TAB_HIGH_SCORES)
	assert_eq(panel.current_tab(), MemoriesPanel.TAB_HIGH_SCORES)
	panel.set_tab(99)
	assert_eq(panel.current_tab(), MemoriesPanel.TAB_HIGH_SCORES)
	panel.set_tab(-1)
	assert_eq(panel.current_tab(), MemoriesPanel.TAB_HIGH_SCORES)
	panel.free()


func test_cheevo_entries_match_catalog_reactions() -> void:
	var panel = _panel()
	var entries = panel._cheevo_entries()
	var expected := 0
	for entry in Catalog.reactions():
		if str(entry.get("kind", "")) == Catalog.KIND_REACTION:
			expected += 1
	assert_eq(entries.size(), expected)
	panel.free()


func test_cheevo_titles_match_catalog() -> void:
	var panel = _panel()
	var entries = panel._cheevo_entries()
	var titles: Array = []
	for entry in entries:
		titles.append(str(entry.get("title", "")))
	assert_true(titles.has("IT'S OVER 9000!"))
	assert_true(titles.has("BIG DOG, BEST DOG!"))
	panel.free()


func test_cheevo_display_titles_are_title_case() -> void:
	var panel = _panel()
	assert_eq(panel._cheevo_display_title({"title": "IT'S OVER 9000!"}), "It's Over 9000!")
	assert_eq(panel._cheevo_display_title({"title": "APES TOGETHER, STRONG!"}), "Apes Together, Strong!")
	assert_eq(panel._cheevo_display_title({"title": "Double Rainbow!"}), "Double Rainbow!")
	assert_eq(panel._cheevo_display_title({"title": "BIG DOG, BEST DOG!"}), "Big Dog, Best Dog!")
	panel.free()


func test_scroll_offset_clamps_at_both_ends() -> void:
	var panel = _panel()
	panel.set_tab(MemoriesPanel.TAB_CHEEVOS)
	var max_offset := panel._max_scroll_offset()
	assert_eq(panel._scroll_offset, 0)
	# Wheel down past the end clamps to max.
	for _i in range(max_offset + 5):
		panel._scroll_offset = mini(panel._scroll_offset + 1, panel._max_scroll_offset())
	assert_eq(panel._scroll_offset, max_offset)
	# Wheel up past the start clamps to 0.
	for _i in range(max_offset + 5):
		panel._scroll_offset = maxi(panel._scroll_offset - 1, 0)
	assert_eq(panel._scroll_offset, 0)
	panel.free()


func test_high_scores_cell_text_unchanged() -> void:
	var panel = _panel()
	panel.set_scores({
		"metrics": {
			"damage": {"value": 12345, "unit": "monster.name.cinnabark", "date_acquired": "11/18/26"},
		},
	})
	assert_eq(panel._table_cell_text(0, 0), "Damage")
	assert_eq(panel._table_cell_text(0, 1), "12.3K")
	assert_eq(panel._table_cell_text(0, 2), "Cinnabark")
	assert_eq(panel._table_cell_text(0, 3), "11/18/26")
	panel.free()


func test_popup_height_identical_across_tabs() -> void:
	var panel = _panel()
	var high_scores_h := panel._popup_height()
	panel.set_tab(MemoriesPanel.TAB_CHEEVOS)
	var cheevos_h := panel._popup_height()
	assert_eq(high_scores_h, cheevos_h)
	panel.free()


func test_content_rect_offsets_by_tab_row_only() -> void:
	var panel = _panel()
	var r := Rect2(Vector2(10, 20), Vector2(320, 200))
	var content := panel._content_rect(r)
	assert_eq(content.position.y, r.position.y + MemoriesPanel.TAB_BAR_H + MemoriesPanel.TAB_GAP)
	assert_eq(content.size.y, r.size.y - MemoriesPanel.TAB_BAR_H - MemoriesPanel.TAB_GAP)
	panel.free()
