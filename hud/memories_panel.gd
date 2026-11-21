extends "table_modal_panel.gd"
## MemoriesPanel - the shop's Brain Rot Memories modal.
##
## The rainbow brain button opens a two-tab panel:
## - High Scores: a table of the best single-unit value per battle metric, with
##   the unit that set each record.
## - Cheevos: a scrollable list of every registered Reaction title. Each row has
##   a completion checkbox (filled with a check when earned), the title, and for
##   completed reactions a smaller unlock-condition description underneath.
##   Undiscovered reactions show only their titles, keeping conditions secret.
##   The tab row carries the "X of Y" progress label; a "Completed only"
##   checkbox on the row below filters the list (unchecked = all, checked =
##   completed only). The all view sorts completed reactions first.
##
## The tabs are real toggle Buttons styled like the Creature Comforts Watchlist
## (navy/gold compact chrome); the active one reads as a pressed gold button.
## Close the panel with the X box, by clicking outside the popup, or with Escape.
##
## Adapted from Creature Comforts (hud/rank_odds_panel.gd) for the modal shape.

const HighScores = preload("../battle/high_scores.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")
const SpeciesIcons = preload("../catalog/species_icons.gd")
const AchievementStore = preload("../core/achievement_store.gd")
const ReactionText = preload("../catalog/reaction_text.gd")

const UNIT_ICON_SIZE := 12.0
const UNIT_ICON_GAP := 3.0

const COLUMN_FRACTIONS := [0.24, 0.20, 0.32, 0.24]
const HEADER_LABELS := ["Metric", "Best", "Unit", "Date Acquired"]

# --- Tabs -------------------------------------------------------------------

const TAB_HIGH_SCORES := 0
const TAB_CHEEVOS := 1
const TAB_LABELS := ["High Scores", "Cheevos"]

# The tab buttons occupy their own compact row between the title and the
# content, so the tabs never overlap the table/list below them.
const TAB_BAR_H := 12.0
const TAB_GAP := 2.0
const TAB_PADDING_X := 12.0

# The "Completed only" checkbox sits on its own row under the tabs (Cheevos tab
# only), right-aligned below the X of Y label. It is smaller and dimmer than the
# main tabs.
const FILTER_BAR_H := 12.0
const FILTER_GAP := 2.0
const FILTER_FONT_SIZE := 7
const CHECKBOX_ICON_SIZE := 10

# Cheevos list layout. Rows are two lines tall (title + description) so the
# list is a fixed window of rows; scrolling shifts the window over the filtered
# catalog rather than clipping pixels.
const CHEEVO_VISIBLE_ROWS := 7
const CHEEVO_ROW_H := 22.0
const CHEEVO_TITLE_LINE_H := 14.0
const CHEEVO_DESC_FONT_SIZE := 6
const CHEEVO_CHECKBOX_SIZE := 10.0
const CHEEVO_CHECKBOX_GAP := 6.0

# Undiscovered titles are dimmed so completed ones stand out.
const CHEEVO_DIM_COLOR := Color(0.55, 0.6, 0.68)

var _metrics: Dictionary = {}
var _achievements: Dictionary = {}
var _tab := TAB_HIGH_SCORES
var _scroll_offset := 0
var _tab_buttons: Array = []
var _completed_only := false
var _completed_checkbox: CheckBox
var _italic_font: SystemFont


func _init() -> void:
	super._init()
	_build_tab_buttons()


## Update the table from a high-score store. `store` is the same shape produced
## by battle/high_scores.gd.
func set_scores(store: Dictionary) -> void:
	var metrics = store.get("metrics")
	_metrics = metrics if metrics is Dictionary else {}
	queue_redraw()


## The earned-reaction store (core/achievement_store.gd). Kept by reference so
## earned state stays in sync as reactions fire during the session.
func set_achievements(store: Dictionary) -> void:
	_achievements = store
	queue_redraw()


## Switch the active tab. Out-of-range indices are ignored.
func set_tab(index: int) -> void:
	if index != TAB_HIGH_SCORES and index != TAB_CHEEVOS:
		return
	if index == _tab:
		return
	_tab = index
	_scroll_offset = 0
	_sync_tab_buttons()
	queue_redraw()


## The active tab index (TAB_HIGH_SCORES or TAB_CHEEVOS).
func current_tab() -> int:
	return _tab


## Every open starts on High Scores, matching the original single-tab behavior.
func open_panel() -> void:
	_tab = TAB_HIGH_SCORES
	_scroll_offset = 0
	super.open_panel()


func _popup_title() -> String:
	return "Brain Rot Memories"


# --- Tab and filter controls -------------------------------------------------

## Build the tab toggles and the "Completed only" checkbox (Watchlist-style
## compact chrome). The active tab is gold-filled like a pressed toggle; the
## inactive one is navy with a gold border.
func _build_tab_buttons() -> void:
	var font := Styles.make_font()
	var normal := Styles.make_compact_button_style()
	# Godot centers button text on the font's full line height, which sits ~1px
	# high for these compact buttons; nudge the top margin so the label reads
	# vertically centered.
	normal.content_margin_top += 1.0
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = BORDER_COLOR
	for i in range(TAB_LABELS.size()):
		var b := Button.new()
		b.name = "TabButton%d" % i
		b.text = TAB_LABELS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		for state in ["normal", "hover", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, normal)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_color_override("font_color", TITLE_COLOR)
		b.add_theme_color_override("font_hover_color", TITLE_COLOR)
		b.add_theme_color_override("font_pressed_color", BG_COLOR)
		b.add_theme_color_override("font_hover_pressed_color", BG_COLOR)
		b.pressed.connect(set_tab.bind(i))
		add_child(b)
		_tab_buttons.append(b)

	# "Completed only" checkbox: fixed label, toggles the Cheevos view.
	_completed_checkbox = CheckBox.new()
	_completed_checkbox.name = "CheevoCompletedCheckbox"
	_completed_checkbox.text = "Completed only"
	_completed_checkbox.focus_mode = Control.FOCUS_NONE
	_completed_checkbox.add_theme_font_override("font", font)
	_completed_checkbox.add_theme_font_size_override("font_size", FILTER_FONT_SIZE)
	_completed_checkbox.add_theme_icon_override("checked", _make_check_icon(true))
	_completed_checkbox.add_theme_icon_override("unchecked", _make_check_icon(false))
	_completed_checkbox.add_theme_icon_override("checked_disabled", _make_check_icon(true))
	_completed_checkbox.add_theme_icon_override("unchecked_disabled", _make_check_icon(false))
	_completed_checkbox.add_theme_color_override("font_color", DESCRIPTION_COLOR)
	_completed_checkbox.add_theme_color_override("font_hover_color", DESCRIPTION_COLOR)
	_completed_checkbox.toggled.connect(_on_completed_checkbox_toggled)
	add_child(_completed_checkbox)
	_sync_tab_buttons()


## A small checkbox icon: a gold-filled square when checked, a gold outline when
## not. Built as a texture so the CheckBox stays compact at the HUD scale.
func _make_check_icon(filled: bool) -> ImageTexture:
	var size := CHECKBOX_ICON_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if filled:
		image.fill_rect(Rect2i(0, 0, size, size), BORDER_COLOR)
	else:
		image.fill_rect(Rect2i(0, 0, size, 1), BORDER_COLOR)
		image.fill_rect(Rect2i(0, size - 1, size, 1), BORDER_COLOR)
		image.fill_rect(Rect2i(0, 0, 1, size), BORDER_COLOR)
		image.fill_rect(Rect2i(size - 1, 0, 1, size), BORDER_COLOR)
	return ImageTexture.create_from_image(image)


## Keep the toggle states and visibility in sync with the active tab and the
## popup's open state. The checkbox only matters on the Cheevos tab.
func _sync_tab_buttons() -> void:
	for i in range(_tab_buttons.size()):
		var b: Button = _tab_buttons[i]
		b.button_pressed = (i == _tab)
		b.visible = _popup_open
	if _completed_checkbox != null:
		_completed_checkbox.button_pressed = _completed_only
		_completed_checkbox.visible = _popup_open and _tab == TAB_CHEEVOS


## Toggle the Cheevos view: checked = completed only, unchecked = all.
func _on_completed_checkbox_toggled(pressed: bool) -> void:
	_completed_only = pressed
	_scroll_offset = 0
	queue_redraw()


## Place the tab buttons on the first row under the title and the checkbox on a
## second row, right-aligned below the X of Y label (Cheevos tab only).
func _layout_tab_buttons() -> void:
	if _tab_buttons.is_empty():
		return
	var r := _popup_rect()
	var x := r.position.x + POPUP_PADDING
	var y := r.position.y + TITLE_H + POPUP_PADDING
	for i in range(_tab_buttons.size()):
		var b: Button = _tab_buttons[i]
		var width := _text_font.get_string_size(TAB_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_FONT_SIZE).x + TAB_PADDING_X
		b.position = Vector2(x, y)
		b.size = Vector2(width, TAB_BAR_H)
		x += width + TAB_GAP

	if _completed_checkbox != null:
		var fy := y + TAB_BAR_H + TAB_GAP
		var cw := _text_font.get_string_size(_completed_checkbox.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FILTER_FONT_SIZE).x + CHECKBOX_ICON_SIZE + 8.0
		_completed_checkbox.position = Vector2(r.position.x + r.size.x - POPUP_PADDING - cw, fy)
		_completed_checkbox.size = Vector2(cw, FILTER_BAR_H)


func _anchor() -> void:
	super._anchor()
	_layout_tab_buttons()


func _open_popup() -> void:
	super._open_popup()
	_sync_tab_buttons()


func _close_popup() -> void:
	super._close_popup()
	_sync_tab_buttons()


# --- High Scores table ------------------------------------------------------

func _table_row_count() -> int:
	return Catalog.BATTLE_METRIC_ORDER.size()


func _table_column_fractions() -> Array:
	return COLUMN_FRACTIONS


func _table_header_labels() -> Array:
	return HEADER_LABELS


func _table_cell_text(row_index: int, column: int) -> String:
	var label := str(Catalog.BATTLE_METRIC_ORDER[row_index])
	var entry = _metrics.get(label)
	var value := 0
	var unit := ""
	var date_acquired := ""
	if entry is Dictionary:
		value = int(entry.get("value", 0))
		unit = str(entry.get("unit", ""))
		date_acquired = str(entry.get("date_acquired", ""))
	elif entry is int or entry is float:
		value = int(entry)
	match column:
		0:
			return label.capitalize()
		1:
			return HighScores.format_value(value) if value > 0 else "\u2014"
		2:
			return HighScores.format_unit(unit) if value > 0 else "\u2014"
		3:
			return date_acquired if value > 0 and not date_acquired.is_empty() else "\u2014"
	return ""


## Draw the Unit column as [icon] [name] when the recorded unit resolves to a
## monster icon; otherwise fall back to the plain centered text.
func _draw_cell(cell_rect: Rect2, row: int, column: int, color: Color) -> void:
	if column != 2:
		super._draw_cell(cell_rect, row, column, color)
		return
	var label := str(Catalog.BATTLE_METRIC_ORDER[row])
	var entry = _metrics.get(label)
	var unit := ""
	if entry is Dictionary:
		unit = str(entry.get("unit", ""))
	if unit.is_empty():
		super._draw_cell(cell_rect, row, column, color)
		return
	var icon := SpeciesIcons.icon_for(unit)
	if icon == null:
		super._draw_cell(cell_rect, row, column, color)
		return
	var name := HighScores.format_unit(unit)
	var text_width := _text_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_FONT_SIZE).x
	var total := UNIT_ICON_SIZE + UNIT_ICON_GAP + text_width
	var start_x := cell_rect.position.x + (cell_rect.size.x - total) * 0.5
	var icon_rect := Rect2(
		Vector2(start_x, cell_rect.position.y + (cell_rect.size.y - UNIT_ICON_SIZE) * 0.5),
		Vector2(UNIT_ICON_SIZE, UNIT_ICON_SIZE))
	PanelIcons.draw_fit(self, icon, icon_rect)
	_draw_text_shadow(
		Vector2(start_x + UNIT_ICON_SIZE + UNIT_ICON_GAP, cell_rect.position.y + cell_rect.size.y - TEXT_BASELINE_OFFSET),
		name, color, BODY_FONT_SIZE,
		HORIZONTAL_ALIGNMENT_LEFT, text_width)


# --- Content routing --------------------------------------------------------

## The popup height is constant across tabs: the larger of the High Scores table
## and the Cheevos visible window (plus its checkbox row), so switching tabs
## never resizes the popup.
func _popup_height() -> float:
	var top := TITLE_H + POPUP_PADDING + TAB_BAR_H + TAB_GAP
	var high_scores_h := top + HEADER_ROW_H + HEADER_GAP + _table_row_count() * ROW_H + POPUP_PADDING
	var cheevos_h := top + FILTER_BAR_H + FILTER_GAP + CHEEVO_VISIBLE_ROWS * CHEEVO_ROW_H + POPUP_PADDING
	return maxf(high_scores_h, cheevos_h)


func _draw_content(rect: Rect2) -> void:
	var content := _content_rect(rect)
	if _tab == TAB_CHEEVOS:
		_draw_cheevos_progress(rect)
		_draw_cheevos(content)
	else:
		_draw_table(content)


## The content rect below the tab row (and the Cheevos checkbox row when on the
## Cheevos tab). The table's own drawing adds TITLE_H + POPUP_PADDING for its
## header, so this offsets by the rows only.
func _content_rect(rect: Rect2) -> Rect2:
	var offset := TAB_BAR_H + TAB_GAP
	if _tab == TAB_CHEEVOS:
		offset += FILTER_BAR_H + FILTER_GAP
	return Rect2(
		rect.position + Vector2(0.0, offset),
		rect.size - Vector2(0.0, offset))


# --- Cheevos list -----------------------------------------------------------

## Every registered Reaction entry, in catalog order.
func _cheevo_entries() -> Array:
	var out: Array = []
	for entry in Catalog.reactions():
		if str(entry.get("kind", "")) == Catalog.KIND_REACTION:
			out.append(entry)
	return out


## True when the reaction id is present in the earned-reaction store.
func _is_earned(id: String) -> bool:
	var reactions = _achievements.get("reactions")
	return reactions is Dictionary and reactions.has(id)


## The Cheevos entries shown under the current view. The all view shows
## completed reactions first, then the rest, preserving catalog order within
## each group; the completed-only view shows just the earned reactions.
func _visible_cheevo_entries() -> Array:
	var out: Array = []
	if _completed_only:
		for entry in _cheevo_entries():
			if _is_earned(str(entry.get("id", ""))):
				out.append(entry)
	else:
		var done: Array = []
		var not_done: Array = []
		for entry in _cheevo_entries():
			if _is_earned(str(entry.get("id", ""))):
				done.append(entry)
			else:
				not_done.append(entry)
		out = done + not_done
	return out


## "X of Y" progress text: earned reactions vs the full catalog count.
func _cheevos_progress_label() -> String:
	return "%d of %d" % [AchievementStore.earned_count(_achievements), _cheevo_entries().size()]


## Draw the "X of Y" progress label right-aligned on the tab row, without
## changing the popup height.
func _draw_cheevos_progress(rect: Rect2) -> void:
	var label := _cheevos_progress_label()
	var inner_left := rect.position.x + POPUP_PADDING
	var inner_w := rect.size.x - POPUP_PADDING * 2.0
	var y := rect.position.y + TITLE_H + POPUP_PADDING
	var text_width := _text_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_FONT_SIZE).x
	_draw_text_shadow(
		Vector2(inner_left + inner_w - text_width, y + TAB_BAR_H - TEXT_BASELINE_OFFSET),
		label, HEADER_COLOR, BODY_FONT_SIZE,
		HORIZONTAL_ALIGNMENT_LEFT, text_width)


## The maximum scroll offset for the Cheevos list (0 when everything fits).
func _max_scroll_offset() -> int:
	return maxi(_visible_cheevo_entries().size() - CHEEVO_VISIBLE_ROWS, 0)


## Title-case a reaction title for the Cheevos list (e.g. "IT'S OVER 9000!" ->
## "It's Over 9000!"). The catalog keeps its authored toast casing; only the
## list display is normalized.
func _cheevo_display_title(entry: Dictionary) -> String:
	var title := str(entry.get("title", ""))
	var parts: PackedStringArray = []
	for word in title.split(" ", false):
		parts.append(word.substr(0, 1).to_upper() + word.substr(1).to_lower())
	return " ".join(parts)


## Draw the Cheevos list: a completion checkbox, the title, and for completed
## reactions a smaller unlock-condition description underneath. Undiscovered
## reactions show only a dimmed title.
func _draw_cheevos(rect: Rect2) -> void:
	var inner_left := rect.position.x + POPUP_PADDING
	var inner_w := rect.size.x - POPUP_PADDING * 2.0
	var row_y := rect.position.y + TITLE_H + POPUP_PADDING
	var text_x := inner_left + CHEEVO_CHECKBOX_SIZE + CHEEVO_CHECKBOX_GAP
	var text_w := inner_w - CHEEVO_CHECKBOX_SIZE - CHEEVO_CHECKBOX_GAP

	var entries := _visible_cheevo_entries()
	for i in range(CHEEVO_VISIBLE_ROWS):
		var entry_index := _scroll_offset + i
		if entry_index >= entries.size():
			break
		var entry: Dictionary = entries[entry_index]
		var id := str(entry.get("id", ""))
		var earned := _is_earned(id)
		var title := _cheevo_display_title(entry)

		var box_rect := Rect2(
			Vector2(inner_left, row_y + (CHEEVO_TITLE_LINE_H - CHEEVO_CHECKBOX_SIZE) * 0.5),
			Vector2(CHEEVO_CHECKBOX_SIZE, CHEEVO_CHECKBOX_SIZE))
		if earned:
			draw_rect(box_rect, BORDER_COLOR)
			_draw_check(box_rect)
		else:
			draw_rect(box_rect, BORDER_COLOR, false, 1.0)

		var title_color: Color = TITLE_COLOR if earned else CHEEVO_DIM_COLOR
		_draw_text_shadow(
			Vector2(text_x, row_y + CHEEVO_TITLE_LINE_H - TEXT_BASELINE_OFFSET),
			title, title_color, BODY_FONT_SIZE,
			HORIZONTAL_ALIGNMENT_LEFT, text_w)

		if earned:
			var desc := ReactionText.description_for(id)
			if not desc.is_empty():
				_draw_text_shadow(
					Vector2(text_x, row_y + CHEEVO_ROW_H - TEXT_BASELINE_OFFSET),
					desc, DESCRIPTION_COLOR, CHEEVO_DESC_FONT_SIZE,
					HORIZONTAL_ALIGNMENT_LEFT, text_w)
		else:
			var hint := ReactionText.hint_for(id)
			if not hint.is_empty():
				_draw_hint_text(
					Vector2(text_x, row_y + CHEEVO_ROW_H - TEXT_BASELINE_OFFSET),
					hint, text_w)
		row_y += CHEEVO_ROW_H


## Draw an undiscovered row's teaser in italic. The italic font is a SystemFont
## variation built once; it falls back to the normal font where italic is missing.
func _draw_hint_text(pos: Vector2, text: String, width: float) -> void:
	if _italic_font == null:
		_italic_font = Styles.make_font()
		_italic_font.italic = true
	draw_string(_italic_font, pos + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, width, CHEEVO_DESC_FONT_SIZE, Color(0.0, 0.0, 0.0, 0.8))
	draw_string(_italic_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, CHEEVO_DESC_FONT_SIZE, CHEEVO_DIM_COLOR)


## Draw a white checkmark inside a filled checkbox.
func _draw_check(box_rect: Rect2) -> void:
	var cx := box_rect.position.x
	var cy := box_rect.position.y
	var s := CHEEVO_CHECKBOX_SIZE
	draw_line(Vector2(cx + s * 0.2, cy + s * 0.55), Vector2(cx + s * 0.45, cy + s * 0.8), Color.WHITE, 1.0)
	draw_line(Vector2(cx + s * 0.45, cy + s * 0.8), Vector2(cx + s * 0.8, cy + s * 0.2), Color.WHITE, 1.0)


# --- Input ------------------------------------------------------------------

func _gui_input(event) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and _tab == TAB_CHEEVOS:
			_scroll_offset = maxi(_scroll_offset - 1, 0)
			queue_redraw()
			accept_event()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and _tab == TAB_CHEEVOS:
			_scroll_offset = mini(_scroll_offset + 1, _max_scroll_offset())
			queue_redraw()
			accept_event()
			return
	super._gui_input(event)
