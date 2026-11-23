extends "shop_modal_panel.gd"
## MemoriesPanel - the shop's Brain Rot Memories modal.
##
## The rainbow brain button opens a two-tab panel, built from Godot Controls:
## - High Scores: a table of the best value per metric, with the unit or trainer
##   that set each record. Per-unit metrics show the species icon; the battle and
##   run records (longest battle, most trinkets) show the trainer portrait. Each
##   cell clips to its column so long names never push the other columns out of
##   place.
## - Cheevos: a ScrollContainer of reaction cards (icon, title, body, trophy).
##   Completed cards show the unlock description; locked ones show an italic
##   teaser. Default order is uncompleted first, then completed, each alphabetical.
##   The filter row holds a Completed Only toggle and the "BRAIN CELLS
##   COLLECTED" label, "X / Y" count, and a rainbow ProgressBar.
##
## Frame, title, close box, click-outside and Escape close come from
## shop_modal_panel.gd. This script only builds and fills the content tree.
##
## Adapted from Creature Comforts (hud/rank_odds_panel.gd) for the modal shape.

const HighScores = preload("../battle/high_scores.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")
const SpeciesIcons = preload("../catalog/species_icons.gd")
const TrainerIcons = preload("../catalog/trainer_icons.gd")
const AchievementStore = preload("../core/achievement_store.gd")
const ReactionText = preload("../catalog/reaction_text.gd")

# Matches the shared shop popup width so the table has room for unit names.
const PANEL_WIDTH := 320.0

# Header icons flanking the title (smilyBrainLeft/Right are 128x124, so draw_fit
# keeps their aspect ratio inside a square box).
const HEADER_ICON_SIZE := 18.0
const HEADER_ICON_GAP := 6.0

const FONT_SIZE := 8
const SMALL_FONT_SIZE := 6
const FILTER_FONT_SIZE := 7

# Gap between the tab row, the filter row / table, and the content below.
const SECTION_GAP := 6

# --- Tabs -------------------------------------------------------------------

const TAB_HIGH_SCORES := 0
const TAB_CHEEVOS := 1
const TAB_LABELS := ["High Scores", "Cheevos"]
const TAB_BAR_H := 16.0
const TAB_ICON_SIZE := 12
const TAB_SEPARATION := 2

# --- Filter row (Cheevos tab) -----------------------------------------------

const COMPLETED_ONLY_LABEL := "Completed Only"
const FILTER_BAR_H := 26.0
const FILTER_SEPARATION := 6
const CHECK_ICON_SIZE := 10
const CHECK_LABEL_GAP := 3
const PROGRESS_BAR_H := 6.0
const PROGRESS_LABEL_GAP := 3
const FILTER_RIGHT_PAD := 10.0

# --- High Scores table ------------------------------------------------------

# Column shares of the table width. The Unit column is widest so species names
# plus their icon stay legible; the Metric column is wide enough for the longest
# label ("Longest Battle") without clipping.
const COLUMN_FRACTIONS := [0.24, 0.15, 0.35, 0.26]

const COLUMN_ALIGNMENTS := [
	HORIZONTAL_ALIGNMENT_LEFT,
	HORIZONTAL_ALIGNMENT_LEFT,
	HORIZONTAL_ALIGNMENT_LEFT,
	HORIZONTAL_ALIGNMENT_LEFT,
]

const HEADER_ALIGNMENTS := [
	HORIZONTAL_ALIGNMENT_LEFT,
	HORIZONTAL_ALIGNMENT_LEFT,
	HORIZONTAL_ALIGNMENT_LEFT,
	HORIZONTAL_ALIGNMENT_LEFT,
]
const HEADER_LABELS := ["METRIC", "BEST", "UNIT / TRAINER", "SET ON"]
const CELL_PAD_X := 4.0
const TABLE_ROW_H := 17.0
const TABLE_ROW_GAP := 1
const UNIT_ICON_SIZE := 16
const UNIT_ICON_LIFT := 2.0
const UNIT_ICON_GAP := 3

# --- Cheevos cards ----------------------------------------------------------

const CHEEVO_ROW_GAP := 4
const CHEEVO_CARD_PAD_X := 8.0
const CHEEVO_CARD_PAD_Y := 3.0
const CHEEVO_ICON_SIZE := 19
const CHEEVO_ICON_LIFT := 1.0
const CHEEVO_TROPHY_SIZE := 18.0
const CHEEVO_TEXT_GAP := 8
const CHEEVO_TEXT_LINE_GAP := 1
const CHEEVO_SCROLLBAR_GAP := 8
const CHEEVO_DIM_COLOR := Color(0.55, 0.6, 0.68)
const TROPHY_LOCKED_COLOR := Color(0.45, 0.48, 0.55, 0.5)
const ICON_LOCKED_MODULATE := Color(1, 1, 1, 0.5)

# Game-packed gold trophy (verified in Creature Comforts hud/player_hud.gd).
const TROPHY_PATH := "res://assets/ui/textures/shop/wins_icon.png"

var _metrics: Dictionary = {}
var _achievements: Dictionary = {}
var _tab := TAB_HIGH_SCORES
var _completed_only := false
var _sorted_entries: Array = []

var _font: Font
var _italic_font: Font
var _card_done_style: StyleBoxFlat
var _card_locked_style: StyleBoxFlat
var _icon_cache: Dictionary = {}
var _panel_icon_cache: Dictionary = {}
var _trophy_texture: Texture2D = null
var _trophy_loaded := false

var _root: VBoxContainer
var _tab_group := ButtonGroup.new()
var _tab_buttons: Array = []
var _filter_row: HBoxContainer
var _completed_only_toggle: Button
var _progress_count: Label
var _progress_bar: ProgressBar
var _table: VBoxContainer
var _cheevo_scroll: ScrollContainer
var _cheevo_list: VBoxContainer


func _init() -> void:
	super._init()
	_font = Styles.make_font()
	var italic := Styles.make_font() as SystemFont
	italic.font_italic = true
	_italic_font = italic
	_card_done_style = _make_card_style(Color(0.95, 0.61, 0.07, 0.12), BORDER_COLOR)
	_card_locked_style = _make_card_style(Color(0.0, 0.0, 0.0, 0.18), Color(0.55, 0.6, 0.68, 0.5))
	# Catalog entries and their titles never change, so sort once.
	_sorted_entries = _cheevo_entries()
	_sorted_entries.sort_custom(_compare_by_title)
	_build_tree()
	_rebuild_table()
	_rebuild_cheevos()
	_refresh_progress()
	_sync_controls()


## Update the table from a high-score store. `store` is the same shape produced
## by battle/high_scores.gd. The table is rebuilt only when the metrics change,
## because the shop calls this on every poll.
func set_scores(store: Dictionary) -> void:
	var metrics = store.get("metrics")
	var next: Dictionary = metrics if metrics is Dictionary else {}
	if next == _metrics:
		return
	_metrics = next.duplicate(true)
	_rebuild_table()


## The earned-reaction store (core/achievement_store.gd). Kept by reference so
## earned state stays in sync as reactions fire during the session.
func set_achievements(store: Dictionary) -> void:
	_achievements = store
	_rebuild_cheevos()
	_refresh_progress()


## Switch the active tab. Out-of-range indices are ignored.
func set_tab(index: int) -> void:
	if index != TAB_HIGH_SCORES and index != TAB_CHEEVOS:
		return
	_tab = index
	_cheevo_scroll.scroll_vertical = 0
	_sync_controls()


## The active tab index (TAB_HIGH_SCORES or TAB_CHEEVOS).
func current_tab() -> int:
	return _tab


## Every open starts on High Scores and refreshes the Cheevos list from the store.
func open_panel() -> void:
	_tab = TAB_HIGH_SCORES
	_cheevo_scroll.scroll_vertical = 0
	_rebuild_cheevos()
	_refresh_progress()
	_sync_controls()
	super.open_panel()


func _popup_title() -> String:
	return "Brain Rot Memories"


func _popup_width() -> float:
	return PANEL_WIDTH


## The panel takes the full viewport height (clamped by the popup margin). The
## height is constant across tabs.
func _popup_height() -> float:
	return _viewport_size().y


func _anchor() -> void:
	super._anchor()
	_layout_content()


## Draw the title flanked by the left/right smilyBrain icons, facing away.
func _draw_popup() -> void:
	super._draw_popup()
	var left := _panel_icon("smilyBrainLeft.png")
	var right := _panel_icon("smilyBrainRight.png")
	if left == null and right == null:
		return
	var r := _popup_rect()
	var title := _popup_title()
	var tw := _text_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE).x
	var center_x := r.position.x + r.size.x * 0.5
	var y := r.position.y + (TITLE_H - HEADER_ICON_SIZE) * 0.5
	var left_x := center_x - tw * 0.5 - HEADER_ICON_GAP - HEADER_ICON_SIZE
	var right_x := center_x + tw * 0.5 + HEADER_ICON_GAP
	if left != null:
		PanelIcons.draw_fit(self, left, Rect2(Vector2(left_x, y), Vector2(HEADER_ICON_SIZE, HEADER_ICON_SIZE)))
	if right != null:
		PanelIcons.draw_fit(self, right, Rect2(Vector2(right_x, y), Vector2(HEADER_ICON_SIZE, HEADER_ICON_SIZE)))


# --- Node tree --------------------------------------------------------------

func _build_tree() -> void:
	_root = VBoxContainer.new()
	_root.name = "Content"
	_root.add_theme_constant_override("separation", SECTION_GAP)
	# Empty areas let clicks through to the modal, so a click outside the popup
	# still closes it; the controls inside keep their own input.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", TAB_SEPARATION)
	_root.add_child(tab_row)
	var tab_icons := [_panel_icon("sInvader.png"), _trophy()]
	for i in range(TAB_LABELS.size()):
		var b := Button.new()
		b.name = "TabButton%d" % i
		b.text = TAB_LABELS[i]
		b.toggle_mode = true
		b.button_group = _tab_group
		b.focus_mode = Control.FOCUS_NONE
		b.icon = tab_icons[i]
		b.custom_minimum_size = Vector2(0.0, TAB_BAR_H)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("icon_max_width", TAB_ICON_SIZE)
		b.add_theme_constant_override("h_separation", 2)
		_apply_button_chrome(b)
		b.pressed.connect(set_tab.bind(i))
		tab_row.add_child(b)
		_tab_buttons.append(b)

	_filter_row = HBoxContainer.new()
	_filter_row.name = "FilterRow"
	_filter_row.custom_minimum_size = Vector2(0.0, FILTER_BAR_H)
	_filter_row.add_theme_constant_override("separation", FILTER_SEPARATION)
	_root.add_child(_filter_row)

	# The toggle is a text Button with an icon, so Godot centers the icon and the
	# label on the same line. Sized to its content so the label sits right beside
	# the tick instead of floating in a wide column.
	_completed_only_toggle = Button.new()
	_completed_only_toggle.name = "CheevoCompletedOnly"
	_completed_only_toggle.text = COMPLETED_ONLY_LABEL
	_completed_only_toggle.toggle_mode = true
	_completed_only_toggle.focus_mode = Control.FOCUS_NONE
	_completed_only_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_completed_only_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_completed_only_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_completed_only_toggle.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_completed_only_toggle.add_theme_constant_override("icon_max_width", CHECK_ICON_SIZE)
	_completed_only_toggle.add_theme_constant_override("h_separation", CHECK_LABEL_GAP)
	_completed_only_toggle.add_theme_font_override("font", _font)
	_completed_only_toggle.add_theme_font_size_override("font_size", FILTER_FONT_SIZE)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		_completed_only_toggle.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_completed_only_toggle.add_theme_color_override(color_name, DESCRIPTION_COLOR)
	_completed_only_toggle.toggled.connect(_on_completed_only_toggled)
	_filter_row.add_child(_completed_only_toggle)

	# Right column: label and count on one line, right-aligned, then the bar.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", PROGRESS_LABEL_GAP)
	_filter_row.add_child(right)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_END
	header.add_theme_constant_override("separation", 6)
	right.add_child(header)
	header.add_child(_make_label("BRAIN CELLS COLLECTED", SMALL_FONT_SIZE, DESCRIPTION_COLOR, HORIZONTAL_ALIGNMENT_RIGHT))
	_progress_count = _make_label("", FONT_SIZE, HEADER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	header.add_child(_progress_count)

	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = false
	# Fixed width tuned to the label + count so the bar's left edge lines up
	# with the "B" in BRAIN CELLS COLLECTED.
	_progress_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	_progress_bar.custom_minimum_size = Vector2(_progress_bar_width(), PROGRESS_BAR_H)
	_progress_bar.add_theme_stylebox_override("background", _progress_background_style())
	_progress_bar.add_theme_stylebox_override("fill", _rainbow_fill_style())
	right.add_child(_progress_bar)

	# Right padding so the progress column does not touch the panel edge.
	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(FILTER_RIGHT_PAD, 0.0)
	_filter_row.add_child(right_pad)

	_table = VBoxContainer.new()
	_table.name = "HighScoresTable"
	_table.add_theme_constant_override("separation", TABLE_ROW_GAP)
	_root.add_child(_table)

	_cheevo_scroll = ScrollContainer.new()
	_cheevo_scroll.name = "CheevoScroll"
	_cheevo_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cheevo_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_cheevo_scroll)

	# Right margin keeps the cards clear of the scrollbar.
	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_right", CHEEVO_SCROLLBAR_GAP)
	_cheevo_scroll.add_child(scroll_margin)

	_cheevo_list = VBoxContainer.new()
	_cheevo_list.name = "CheevoList"
	_cheevo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cheevo_list.add_theme_constant_override("separation", CHEEVO_ROW_GAP)
	scroll_margin.add_child(_cheevo_list)


## The content tree fills the popup inside its padding and below the title bar.
func _layout_content() -> void:
	if _root == null:
		return
	var r := _popup_rect()
	_root.position = r.position + Vector2(POPUP_PADDING, TITLE_H + POPUP_PADDING)
	_root.size = Vector2(r.size.x - POPUP_PADDING * 2.0, r.size.y - TITLE_H - POPUP_PADDING * 2.0)


## Show the active tab's content, press its button, and sync the filter toggle.
func _sync_controls() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].button_pressed = (i == _tab)
	_table.visible = _tab == TAB_HIGH_SCORES
	_filter_row.visible = _tab == TAB_CHEEVOS
	_cheevo_scroll.visible = _tab == TAB_CHEEVOS
	_completed_only_toggle.set_pressed_no_signal(_completed_only)
	_refresh_check_icon()


## The tick icon matches the toggle state.
func _refresh_check_icon() -> void:
	var icon_file := "check_on.png" if _completed_only else "check_off.png"
	_completed_only_toggle.icon = _panel_icon(icon_file)


## Compact navy/gold tab chrome; the pressed tab reads as a gold-filled button.
func _apply_button_chrome(b: Button) -> void:
	var normal := Styles.make_compact_button_style()
	# Godot centers button text on the font's full line height, which sits ~1px
	# high for these compact buttons; nudge the top margin and the left margin
	# so the label and icon read centered.
	normal.content_margin_top += 1.0
	normal.content_margin_left += 1.0
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = BORDER_COLOR
	pressed.set_border_width_all(2)
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.add_theme_color_override("font_color", TITLE_COLOR)
	b.add_theme_color_override("font_hover_color", TITLE_COLOR)
	b.add_theme_color_override("font_pressed_color", BG_COLOR)
	b.add_theme_color_override("font_hover_pressed_color", BG_COLOR)


func _progress_background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.4)
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	return style


## Fixed bar width: the label plus a representative "X / Y" count and the gap
## between them, so the bar's left edge aligns with the label's first letter.
func _progress_bar_width() -> float:
	var label_w := _font.get_string_size("BRAIN CELLS COLLECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT_SIZE).x
	var count_w := _font.get_string_size("00 / 00", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return label_w + 6.0 + count_w


## Rainbow gradient used as the progress fill, built once from a Gradient.
func _rainbow_fill_style() -> StyleBoxTexture:
	var stops := 7
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in range(stops):
		var t := float(i) / float(stops - 1)
		offsets.append(t)
		colors.append(Color.from_hsv(t, 0.8, 1.0))
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	var style := StyleBoxTexture.new()
	style.texture = texture
	return style


func _make_card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = CHEEVO_CARD_PAD_X
	style.content_margin_right = CHEEVO_CARD_PAD_X
	style.content_margin_top = CHEEVO_CARD_PAD_Y
	style.content_margin_bottom = CHEEVO_CARD_PAD_Y
	return style


func _make_label(text: String, font_size: int, color: Color, align: HorizontalAlignment, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", font if font != null else _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


## A TextureRect that keeps its aspect ratio, centered. Callers set the size.
func _texture_rect(tex: Texture2D, tint: Color = Color.WHITE) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.modulate = tint
	return rect


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


# --- High Scores table ------------------------------------------------------

func _rebuild_table() -> void:
	_clear_children(_table)
	var header: Array = []
	for column in range(HEADER_LABELS.size()):
		var label := _table_label(HEADER_LABELS[column], FONT_SIZE, HEADER_COLOR, HEADER_ALIGNMENTS[column])
		header.append(_table_cell(label, column))
	_table.add_child(_table_row(header))
	for row in range(_table_row_count()):
		var cells: Array = []
		for column in range(COLUMN_FRACTIONS.size()):
			cells.append(_table_body_cell(row, column))
		_table.add_child(_table_row(cells))


## One table row: the cells side by side, sharing the table width by COLUMN_FRACTIONS.
func _table_row(cells: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	for cell in cells:
		row.add_child(cell)
	return row


## A column cell. Each cell is a plain Control with a zero minimum width and
## clip_contents, so the stretch ratio sets its width and long text is cut off
## at the column edge instead of widening the whole table.
func _table_cell(content: Control, column: int) -> Control:
	var cell := Control.new()
	cell.clip_contents = true
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = COLUMN_FRACTIONS[column]
	cell.custom_minimum_size = Vector2(0.0, TABLE_ROW_H)
	cell.add_child(content)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Inset the content so text never touches the column edge.
	content.offset_left = CELL_PAD_X
	content.offset_right = -CELL_PAD_X
	return cell


## A single-line label for a table cell, clipped to the cell.
func _table_label(text: String, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := _make_label(text, font_size, color, align)
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## A body cell. The Unit column prepends the species icon when one resolves.
func _table_body_cell(row: int, column: int) -> Control:
	if column == 2:
		var icon := _unit_icon(row)
		if icon != null:
			var box := HBoxContainer.new()
			box.alignment = BoxContainer.ALIGNMENT_BEGIN
			box.add_theme_constant_override("separation", UNIT_ICON_GAP)
			# Wrap the icon so a bottom margin lifts it slightly above the row's
			# center; the icons read low against the unit name beside them.
			var icon_holder := MarginContainer.new()
			icon_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon_holder.add_theme_constant_override("margin_bottom", int(UNIT_ICON_LIFT * 2.0))
			var icon_rect := _texture_rect(icon)
			icon_rect.custom_minimum_size = Vector2(UNIT_ICON_SIZE, UNIT_ICON_SIZE)
			icon_holder.add_child(icon_rect)
			box.add_child(icon_holder)
			var name_label := _table_label(_table_cell_text(row, column), FONT_SIZE, DESCRIPTION_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
			# Expand so the name takes the cell's remaining width instead of
			# collapsing to its clipped minimum and showing only the icon.
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(name_label)
			return _table_cell(box, column)
	var label := _table_label(_table_cell_text(row, column), FONT_SIZE, DESCRIPTION_COLOR, COLUMN_ALIGNMENTS[column])
	return _table_cell(label, column)


func _table_row_count() -> int:
	return Catalog.HIGH_SCORE_METRIC_ORDER.size()


## Text for one table cell. Pure: used by the table and by tests.
func _table_cell_text(row_index: int, column: int) -> String:
	var label := str(Catalog.HIGH_SCORE_METRIC_ORDER[row_index])
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
			return HighScores.format_metric_value(label, value) if value > 0 else "\u2014"
		2:
			return HighScores.format_unit(unit) if value > 0 else "\u2014"
		3:
			return date_acquired if value > 0 and not date_acquired.is_empty() else "\u2014"
	return ""


## The icon for a row's recorded unit or trainer, or null when there is none.
## Per-unit metrics use the species icon; trainer-attributed records use the
## trainer portrait.
func _unit_icon(row_index: int) -> Texture2D:
	var label := str(Catalog.HIGH_SCORE_METRIC_ORDER[row_index])
	var entry = _metrics.get(label)
	if not (entry is Dictionary):
		return null
	var unit := str(entry.get("unit", ""))
	if unit.is_empty():
		return null
	var meta = Catalog.HIGH_SCORE_METRICS.get(label, {})
	if str(meta.get("icon", Catalog.ICON_UNIT)) == Catalog.ICON_TRAINER:
		return TrainerIcons.icon_for(unit)
	return SpeciesIcons.icon_for(unit)


# --- Cheevos list -----------------------------------------------------------

func _rebuild_cheevos() -> void:
	_clear_children(_cheevo_list)
	for entry in _visible_cheevo_entries():
		var earned := _is_earned(str(entry.get("id", "")))
		_cheevo_list.add_child(_build_card(entry, earned))


## One reaction card: icon, title, body (description or teaser), and trophy.
## The card has no fixed height, so the body text is never squeezed out.
func _build_card(entry: Dictionary, earned: bool) -> PanelContainer:
	var id := str(entry.get("id", ""))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_done_style if earned else _card_locked_style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CHEEVO_TEXT_GAP)
	card.add_child(row)

	# Wrap the icon so a bottom margin lifts it slightly above the row's center;
	# many reaction icons read low against the text beside them.
	var icon_holder := MarginContainer.new()
	icon_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_holder.add_theme_constant_override("margin_bottom", int(CHEEVO_ICON_LIFT * 2.0))
	var icon := _texture_rect(_cheevo_icon(entry), Color.WHITE if earned else ICON_LOCKED_MODULATE)
	icon.custom_minimum_size = Vector2(CHEEVO_ICON_SIZE, CHEEVO_ICON_SIZE)
	icon_holder.add_child(icon)
	row.add_child(icon_holder)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", CHEEVO_TEXT_LINE_GAP)
	row.add_child(text)
	text.add_child(_make_label(
		_cheevo_display_title(entry), FONT_SIZE,
		TITLE_COLOR if earned else CHEEVO_DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT))
	var body_text := ReactionText.description_for(id) if earned else ReactionText.hint_for(id)
	var body := _make_label(
		body_text, SMALL_FONT_SIZE,
		DESCRIPTION_COLOR if earned else CHEEVO_DIM_COLOR, HORIZONTAL_ALIGNMENT_LEFT,
		_font if earned else _italic_font)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(body)

	row.add_child(_trophy_badge(earned))
	return card


## Gold trophy when earned; dimmed trophy with a red qMark overlay when locked.
func _trophy_badge(earned: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CHEEVO_TROPHY_SIZE, CHEEVO_TROPHY_SIZE)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var trophy := _texture_rect(_trophy(), Color.WHITE if earned else TROPHY_LOCKED_COLOR)
	trophy.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(trophy)
	if not earned:
		var q := _texture_rect(_panel_icon("qMark.png"))
		q.anchor_left = 0.2
		q.anchor_top = 0.2
		q.anchor_right = 0.8
		q.anchor_bottom = 0.8
		holder.add_child(q)
	return holder


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


## The Cheevos entries under the current sort. Default: uncompleted first, then
## completed. Completed Only: completed first. Each group stays alphabetical.
func _visible_cheevo_entries() -> Array:
	var not_done: Array = []
	var done: Array = []
	for entry in _sorted_entries:
		if _is_earned(str(entry.get("id", ""))):
			done.append(entry)
		else:
			not_done.append(entry)
	return done + not_done if _completed_only else not_done + done


## Case-insensitive alphabetical comparison by display title.
func _compare_by_title(a: Dictionary, b: Dictionary) -> bool:
	return _cheevo_display_title(a).to_lower() < _cheevo_display_title(b).to_lower()


## "X / Y" progress text: earned reactions vs the full catalog count.
func _cheevos_progress_label() -> String:
	return "%d / %d" % [AchievementStore.earned_count(_achievements), _sorted_entries.size()]


func _refresh_progress() -> void:
	_progress_count.text = _cheevos_progress_label()
	_progress_bar.max_value = maxf(float(_sorted_entries.size()), 1.0)
	_progress_bar.value = float(AchievementStore.earned_count(_achievements))


func _on_completed_only_toggled(pressed: bool) -> void:
	_completed_only = pressed
	_cheevo_scroll.scroll_vertical = 0
	_refresh_check_icon()
	_rebuild_cheevos()


## Title-case a reaction title for the Cheevos list (e.g. "IT'S OVER 9000!" ->
## "It's Over 9000!"). The catalog keeps its authored toast casing.
func _cheevo_display_title(entry: Dictionary) -> String:
	var title := str(entry.get("title", ""))
	var parts: PackedStringArray = []
	for word in title.split(" ", false):
		parts.append(word.substr(0, 1).to_upper() + word.substr(1).to_lower())
	return " ".join(parts)


## The reaction icon for a card: the entry's loose icon file when present,
## otherwise the species icon. Cached per id.
func _cheevo_icon(entry: Dictionary) -> Texture2D:
	var id := str(entry.get("id", ""))
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	var icon_file := str(entry.get("icon_file", ""))
	if not icon_file.is_empty():
		tex = _panel_icon(icon_file)
	if tex == null:
		var species := str(entry.get("species", ""))
		if not species.is_empty():
			tex = SpeciesIcons.icon_for(species)
	_icon_cache[id] = tex
	return tex



# --- Icons ------------------------------------------------------------------

## A loose mod icon from assets/icons/, loaded once and cached by file name.
func _panel_icon(file_name: String) -> Texture2D:
	if not _panel_icon_cache.has(file_name):
		_panel_icon_cache[file_name] = PanelIcons.load_icon(str(get_script().resource_path), file_name)
	return _panel_icon_cache[file_name]


## The game's gold trophy texture, loaded once. Guarded by ResourceLoader.exists
## so headless tests (no game PCK) skip it silently instead of logging an error.
func _trophy() -> Texture2D:
	if not _trophy_loaded:
		_trophy_loaded = true
		if ResourceLoader.exists(TROPHY_PATH):
			_trophy_texture = load(TROPHY_PATH)
	return _trophy_texture
