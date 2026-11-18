extends "test_runner.gd"
## Unit tests for hud/memories_panel.gd.

const MemoriesPanel = preload("../hud/memories_panel.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")


func _panel():
	return MemoriesPanel.new()


func test_button_texture_loads() -> void:
	var panel = _panel()
	assert_true(panel.button_texture() is Texture2D, "rainbowBrain.png should load")
	panel.free()


func test_button_position_is_left_of_replay_button() -> void:
	var panel = _panel()
	var viewport := Vector2(1280, 720)
	var pos: Vector2 = panel._button_position(viewport)
	var replay_half := 10.0
	var replay_x := roundf(viewport.x * 0.80 - replay_half)
	var replay_y := roundf(viewport.y * 0.05 - replay_half)
	assert_true(pos.x < replay_x, "memories button must be left of the Replay button")
	assert_eq(pos.y, replay_y)
	panel.free()


func test_popup_title_is_brain_rot_memories() -> void:
	var panel = _panel()
	assert_eq(panel._popup_title(), "Brain Rot Memories")
	panel.free()


func test_table_has_metric_best_unit_columns() -> void:
	var panel = _panel()
	assert_eq(panel._table_header_labels(), ["Metric", "Best", "Unit"])
	assert_eq(panel._table_row_count(), Catalog.BATTLE_METRIC_ORDER.size())
	panel.free()


func test_cell_text_shows_metric_value_and_unit() -> void:
	var panel = _panel()
	panel.set_scores({
		"metrics": {
			"damage": {"value": 12345, "unit": "monster.name.cinnabark"},
		},
	})
	assert_eq(panel._table_cell_text(0, 0), "Damage")
	assert_eq(panel._table_cell_text(0, 1), "12.3K")
	assert_eq(panel._table_cell_text(0, 2), "Cinnabark")
	panel.free()


func test_cell_text_shows_dash_when_missing() -> void:
	var panel = _panel()
	panel.set_scores({"metrics": {}})
	assert_eq(panel._table_cell_text(0, 1), "\u2014")
	assert_eq(panel._table_cell_text(0, 2), "\u2014")
	panel.free()


func test_open_and_close_toggle() -> void:
	var panel = _panel()
	assert_false(panel.is_open())
	panel.open_panel()
	assert_true(panel.is_open())
	panel.close_panel()
	assert_false(panel.is_open())
	panel.free()


func test_show_button_and_hide_panel_toggle_visibility() -> void:
	var panel = _panel()
	assert_false(panel.visible)
	panel.show_button()
	assert_true(panel.visible)
	panel.hide_panel()
	assert_false(panel.visible)
	panel.free()
