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
