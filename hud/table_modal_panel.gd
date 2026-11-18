extends "shop_modal_panel.gd"
## TableModalPanel - shared row-table layout for the shop's table modals.
##
## Subclasses describe their rows and column colours; this base owns the header
## row, column widths, divider, and the cell drawing loop.
##
## Adapted from Creature Comforts (hud/table_modal_panel.gd).

const HEADER_ROW_H := 16.0
const HEADER_GAP := 2.0
const ROW_H := 14.0

const HEADER_FONT_SIZE := 8
const BODY_FONT_SIZE := 8

const HIGHLIGHT_COLOR := Color(0.95, 0.61, 0.07, 0.15)


# --- Subclass table description ---------------------------------------------

func _table_row_count() -> int:
	return 0


func _table_column_fractions() -> Array:
	return []


func _table_header_labels() -> Array:
	return []


func _table_header_color(_column: int) -> Color:
	return HEADER_COLOR


func _table_current_row_color(_column: int) -> Color:
	return TITLE_COLOR


func _table_current_row() -> int:
	return -1


func _table_cell_text(_row_index: int, _column: int) -> String:
	return ""


# --- Shared layout ----------------------------------------------------------

func _popup_height() -> float:
	return TITLE_H + POPUP_PADDING + HEADER_ROW_H + HEADER_GAP \
		+ _table_row_count() * ROW_H + POPUP_PADDING


func _draw_content(rect: Rect2) -> void:
	_draw_table(rect)


func _draw_table(rect: Rect2) -> void:
	var inner_left := rect.position.x + POPUP_PADDING
	var inner_w := rect.size.x - POPUP_PADDING * 2.0
	var header_y := rect.position.y + TITLE_H + POPUP_PADDING

	var fractions := _table_column_fractions()
	var labels := _table_header_labels()
	var columns := fractions.size()

	var x := inner_left
	for column in range(columns):
		var cw: float = inner_w * fractions[column]
		_draw_text_shadow(
			Vector2(x, header_y + HEADER_ROW_H - TEXT_BASELINE_OFFSET),
			labels[column], _table_header_color(column), HEADER_FONT_SIZE,
			HORIZONTAL_ALIGNMENT_CENTER, cw)
		x += cw

	draw_line(
		Vector2(inner_left, header_y + HEADER_ROW_H),
		Vector2(inner_left + inner_w, header_y + HEADER_ROW_H),
		BORDER_COLOR, 1.0)

	var current := _table_current_row()
	var row_y := header_y + HEADER_ROW_H + HEADER_GAP
	for row in range(_table_row_count()):
		var is_current := row == current
		if is_current:
			draw_rect(Rect2(Vector2(inner_left, row_y), Vector2(inner_w, ROW_H)), HIGHLIGHT_COLOR)
		var cx := inner_left
		for column in range(columns):
			var cw: float = inner_w * fractions[column]
			var color: Color = _table_current_row_color(column) if is_current else DESCRIPTION_COLOR
			_draw_cell(Rect2(Vector2(cx, row_y), Vector2(cw, ROW_H)), row, column, color)
			cx += cw
		row_y += ROW_H


## Draw one body cell. Subclasses can override this to draw icons or custom
## content instead of plain centered text.
func _draw_cell(cell_rect: Rect2, row: int, column: int, color: Color) -> void:
	_draw_text_shadow(
		Vector2(cell_rect.position.x, cell_rect.position.y + cell_rect.size.y - TEXT_BASELINE_OFFSET),
		_table_cell_text(row, column), color, BODY_FONT_SIZE,
		HORIZONTAL_ALIGNMENT_CENTER, cell_rect.size.x)
