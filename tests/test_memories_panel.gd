extends "test_runner.gd"
## Unit tests for hud/memories_panel.gd.

const MemoriesPanel = preload("../hud/memories_panel.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")
const ReactionText = preload("../catalog/reaction_text.gd")


func _panel():
	return MemoriesPanel.new()


# --- Popup and tables -------------------------------------------------------

func test_popup_title_is_brain_rot_memories() -> void:
	var panel = _panel()
	assert_eq(panel._popup_title(), "Brain Rot Memories")
	panel.free()


func test_popup_width_is_memories_width() -> void:
	var panel = _panel()
	assert_eq(panel._popup_width(), MemoriesPanel.PANEL_WIDTH)
	panel.free()


func test_table_has_metric_best_unit_columns() -> void:
	assert_eq(MemoriesPanel.HEADER_LABELS, ["METRIC", "BEST", "UNIT / TRAINER", "SET ON"])
	var panel = _panel()
	assert_eq(panel._table_row_count(), Catalog.HIGH_SCORE_METRIC_ORDER.size())
	panel.free()


func test_table_grid_has_header_and_body_cells() -> void:
	var panel = _panel()
	assert_eq(panel._table.get_child_count(), 1 + panel._table_row_count())
	for row in panel._table.get_children():
		assert_eq(row.get_child_count(), MemoriesPanel.HEADER_LABELS.size())
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


func test_cell_text_shows_longest_battle_duration() -> void:
	var panel = _panel()
	panel.set_scores({
		"metrics": {
			"longest_battle": {"value": 125, "unit": "gentleman", "date_acquired": "11/18/26"},
		},
	})
	assert_eq(panel._table_cell_text(6, 0), "Longest Battle")
	assert_eq(panel._table_cell_text(6, 1), "2m 5s")
	assert_eq(panel._table_cell_text(6, 2), "Gentleman")
	panel.free()


func test_cell_text_shows_most_casts() -> void:
	var panel = _panel()
	panel.set_scores({
		"metrics": {
			"most_casts": {"value": 9, "unit": "monster.name.rhizuka", "date_acquired": "11/18/26"},
		},
	})
	assert_eq(panel._table_cell_text(7, 0), "Most Casts")
	assert_eq(panel._table_cell_text(7, 1), "9")
	assert_eq(panel._table_cell_text(7, 2), "Rhizuka")
	panel.free()


func test_cell_text_shows_most_trinkets() -> void:
	var panel = _panel()
	panel.set_scores({
		"metrics": {
			"most_trinkets": {"value": 6, "unit": "chef", "date_acquired": "11/18/26"},
		},
	})
	assert_eq(panel._table_cell_text(8, 0), "Most Trinkets")
	assert_eq(panel._table_cell_text(8, 1), "6")
	assert_eq(panel._table_cell_text(8, 2), "Chef")
	panel.free()


func test_popup_height_identical_across_tabs() -> void:
	var panel = _panel()
	var high_scores_h := panel._popup_height()
	panel.set_tab(MemoriesPanel.TAB_CHEEVOS)
	var cheevos_h := panel._popup_height()
	assert_eq(high_scores_h, cheevos_h)
	panel.free()


# --- Open, close, tabs ------------------------------------------------------

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


func test_tab_buttons_share_exclusive_group() -> void:
	var panel = _panel()
	assert_eq(panel._tab_buttons.size(), MemoriesPanel.TAB_LABELS.size())
	for b in panel._tab_buttons:
		assert_true(b.button_group == panel._tab_group)
	panel.set_tab(MemoriesPanel.TAB_CHEEVOS)
	assert_true(panel._tab_buttons[MemoriesPanel.TAB_CHEEVOS].button_pressed)
	assert_false(panel._tab_buttons[MemoriesPanel.TAB_HIGH_SCORES].button_pressed)
	panel.free()


func test_tab_visibility_follows_active_tab() -> void:
	var panel = _panel()
	assert_true(panel._table.visible)
	assert_false(panel._filter_row.visible)
	assert_false(panel._cheevo_scroll.visible)
	panel.set_tab(MemoriesPanel.TAB_CHEEVOS)
	assert_false(panel._table.visible)
	assert_true(panel._filter_row.visible)
	assert_true(panel._cheevo_scroll.visible)
	panel.free()


# --- Cheevos data -----------------------------------------------------------

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
	var titles: Array = []
	for entry in panel._cheevo_entries():
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


func test_cheevo_list_has_one_card_per_visible_entry() -> void:
	var panel = _panel()
	assert_true(panel._cheevo_scroll is ScrollContainer)
	assert_eq(panel._cheevo_list.get_child_count(), panel._visible_cheevo_entries().size())
	panel.free()


func test_cheevos_progress_label_counts_earned() -> void:
	var panel = _panel()
	panel.set_achievements({"version": 1, "reactions": {"over_9000": {}, "big_dog_best_dog": {}}})
	var expected := "2 / %d" % panel._cheevo_entries().size()
	assert_eq(panel._cheevos_progress_label(), expected)
	assert_eq(panel._progress_count.text, expected)
	panel.free()


func test_cheevos_progress_label_starts_at_zero() -> void:
	var panel = _panel()
	panel.set_achievements({"version": 1, "reactions": {}})
	var expected := "0 / %d" % panel._cheevo_entries().size()
	assert_eq(panel._cheevos_progress_label(), expected)
	panel.free()


func test_progress_bar_tracks_earned_count() -> void:
	var panel = _panel()
	panel.set_achievements({"version": 1, "reactions": {"over_9000": {}}})
	assert_eq(panel._progress_bar.value, 1.0)
	assert_eq(panel._progress_bar.max_value, float(panel._cheevo_entries().size()))
	panel.free()


func test_is_earned_reflects_store() -> void:
	var panel = _panel()
	panel.set_achievements({"version": 1, "reactions": {"over_9000": {}}})
	assert_true(panel._is_earned("over_9000"))
	assert_false(panel._is_earned("big_dog_best_dog"))
	panel.free()


func test_visible_cheevo_entries_order() -> void:
	var panel = _panel()
	panel.set_achievements({"version": 1, "reactions": {"over_9000": {}}})
	# Default: uncompleted first, completed last.
	var default_entries: Array = panel._visible_cheevo_entries()
	assert_eq(default_entries.size(), panel._cheevo_entries().size())
	assert_eq(str(default_entries[default_entries.size() - 1].get("id", "")), "over_9000")
	# Completed Only: completed first, uncompleted after.
	panel._completed_only = true
	var toggled: Array = panel._visible_cheevo_entries()
	assert_eq(toggled.size(), panel._cheevo_entries().size())
	assert_eq(str(toggled[0].get("id", "")), "over_9000")
	panel.free()


func test_completed_only_toggle() -> void:
	var panel = _panel()
	assert_false(panel._completed_only)
	panel._on_completed_only_toggled(true)
	assert_true(panel._completed_only)
	panel._on_completed_only_toggled(false)
	assert_false(panel._completed_only)
	panel.free()


func test_completed_only_toggle_drives_filter() -> void:
	var panel = _panel()
	panel._completed_only_toggle.button_pressed = true
	assert_true(panel._completed_only)
	panel._completed_only_toggle.button_pressed = false
	assert_false(panel._completed_only)
	panel.free()


func test_all_filter_sorts_uncompleted_first_alphabetical() -> void:
	var panel = _panel()
	panel.set_achievements({"version": 1, "reactions": {"over_9000": {}, "six_seven": {}}})
	var entries: Array = panel._visible_cheevo_entries()
	# Uncompleted first, alphabetical: "Apes Together, Strong!" then "Big Dog, Best Dog!".
	assert_eq(str(entries[0].get("id", "")), "apes_together")
	assert_eq(str(entries[1].get("id", "")), "big_dog_best_dog")
	# Completed last, alphabetical: "It's Over 9000!" then "Six Seven!".
	assert_eq(str(entries[entries.size() - 2].get("id", "")), "over_9000")
	assert_eq(str(entries[entries.size() - 1].get("id", "")), "six_seven")
	panel.free()


func test_cheevo_description_for_known_and_unknown() -> void:
	assert_eq(ReactionText.description_for("over_9000"), "Hit 9000+ of a battle metric or over 9000 shop income.")
	assert_eq(ReactionText.description_for("big_dog_best_dog"), "Put up over 1,000,000 shield with a Cinnabark.")
	assert_eq(ReactionText.description_for("nope"), "")
