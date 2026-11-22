extends "table_modal_panel.gd"
## MemoriesPanel - the shop's Brain Rot Memories modal.
##
## The rainbow brain button opens a two-tab panel:
## - High Scores: a table of the best single-unit value per battle metric, with
##   the unit that set each record.
## - Cheevos: a scrollable list of reaction cards. Each card shows a completion
##   checkbox, the reaction icon, the title, and (for completed reactions) the
##   unlock description; undiscovered reactions show a dim italic teaser. A gold
##   trophy marks completed cards, a dim "?" trophy marks locked ones. The tab
##   row carries the "X of Y" label; a progress bar and All / Completed Only pill
##   toggles sit on the row below. The all view sorts completed reactions first.
##
## The tabs and filter pills are real Buttons styled like the Creature Comforts
## Watchlist (navy/gold compact chrome); the active one reads as a pressed gold
## button. Close the panel with the X box, by clicking outside the popup, or with
## Escape.
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

# The Memories panel is wider than the other shop modals so the reaction cards
# fit an icon, two text lines, and a trophy without crowding.
const PANEL_WIDTH := 420.0

# --- Tabs -------------------------------------------------------------------

const TAB_HIGH_SCORES := 0
const TAB_CHEEVOS := 1
const TAB_LABELS := ["High Scores", "Cheevos"]

# The tab buttons occupy their own compact row between the title and the
# content, so the tabs never overlap the table/list below them.
const TAB_BAR_H := 16.0
const TAB_GAP := 2.0
const TAB_PADDING_X := 12.0
const TAB_ICON_SIZE := 12

# The All / Completed Only pill toggles and the progress bar sit on a second row
# under the tabs (Cheevos tab only).
const FILTER_LABELS := ["All", "Completed Only"]
const FILTER_BAR_H := 12.0
const FILTER_GAP := 2.0
const FILTER_FONT_SIZE := 7
const PROGRESS_BAR_W := 90.0
const PROGRESS_BAR_H := 6.0

# Cheevos card layout. Cards are two lines tall (title + description) with a
# reaction icon and a trophy; the list is a fixed window of cards.
const CHEEVO_VISIBLE_ROWS := 5
const CHEEVO_ROW_H := 30.0
const CHEEVO_ROW_GAP := 3.0
const CHEEVO_ICON_SIZE := 22.0
const CHEEVO_TROPHY_SIZE := 18.0
const CHEEVO_DESC_FONT_SIZE := 6
const CHEEVO_CHECKBOX_SIZE := 10.0

# Undiscovered titles are dimmed so completed ones stand out.
const CHEEVO_DIM_COLOR := Color(0.55, 0.6, 0.68)

# Game-packed gold trophy (verified in Creature Comforts hud/player_hud.gd).
const TROPHY_PATH := "res://assets/ui/textures/shop/wins_icon.png"
const MOD_ICON_DIR := "res://mods/BrainRot/assets/icons"

var _metrics: Dictionary = {}
var _achievements: Dictionary = {}
var _tab := TAB_HIGH_SCORES
var _scroll_offset := 0
var _tab_buttons: Array = []
var _completed_only := false
var _filter_buttons: Array = []
var _italic_font: SystemFont
var _icon_cache: Dictionary = {}
var _trophy_texture: Texture2D = null
var _trophy_loaded := false
var _card_done_style: StyleBoxFlat
var _card_locked_style: StyleBoxFlat


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


## The Memories panel is wider than the shared modal default.
func _popup_rect() -> Rect2:
	var viewport_size := _viewport_size()
	var w := minf(PANEL_WIDTH, viewport_size.x - VIEWPORT_MARGIN * 2.0)
	var h := minf(_popup_height(), viewport_size.y - VIEWPORT_MARGIN * 2.0)
	var x := roundf((viewport_size.x - w) * 0.5)
	var y := roundf((viewport_size.y - h) * 0.5)
	return Rect2(Vector2(x, y), Vector2(w, h))


# --- Tab and filter controls -------------------------------------------------

## Build the tab toggles (with icons) and the All / Completed Only pill toggles.
## The active control is gold-filled like a pressed toggle; the inactive ones are
## navy with a gold border.
func _build_tab_buttons() -> void:
	var font := Styles.make_font()
	var normal := Styles.make_compact_button_style()
	# Godot centers button text on the font's full line height, which sits ~1px
	# high for these compact buttons; nudge the top margin so the label reads
	# vertically centered.
	normal.content_margin_top += 1.0
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = BORDER_COLOR
	pressed.set_border_width_all(2)

	var tab_icons := [_make_bar_chart_icon(), _trophy()]
	for i in range(TAB_LABELS.size()):
		var b := Button.new()
		b.name = "TabButton%d" % i
		b.text = TAB_LABELS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		b.add_theme_constant_override("icon_max_width", TAB_ICON_SIZE)
		if tab_icons[i] != null:
			b.icon = tab_icons[i]
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

	# Pill-shaped All / Completed Only toggles.
	var pill_normal := StyleBoxFlat.new()
	pill_normal.bg_color = BG_COLOR
	pill_normal.border_color = BORDER_COLOR
	pill_normal.set_border_width_all(1)
	pill_normal.set_corner_radius_all(8)
	pill_normal.set_content_margin_all(2.0)
	var pill_pressed: StyleBoxFlat = pill_normal.duplicate()
	pill_pressed.bg_color = BORDER_COLOR
	for i in range(FILTER_LABELS.size()):
		var f := Button.new()
		f.name = "CheevoFilter%d" % i
		f.text = FILTER_LABELS[i]
		f.toggle_mode = true
		f.focus_mode = Control.FOCUS_NONE
		f.add_theme_font_override("font", font)
		f.add_theme_font_size_override("font_size", FILTER_FONT_SIZE)
		for state in ["normal", "hover", "focus", "disabled"]:
			f.add_theme_stylebox_override(state, pill_normal)
		f.add_theme_stylebox_override("pressed", pill_pressed)
		f.add_theme_color_override("font_color", DESCRIPTION_COLOR)
		f.add_theme_color_override("font_hover_color", DESCRIPTION_COLOR)
		f.add_theme_color_override("font_pressed_color", BG_COLOR)
		f.add_theme_color_override("font_hover_pressed_color", BG_COLOR)
		f.pressed.connect(_on_filter_pressed.bind(i))
		add_child(f)
		_filter_buttons.append(f)
	_sync_tab_buttons()


## A tiny bar-chart icon for the High Scores tab, drawn as a texture.
func _make_bar_chart_icon() -> ImageTexture:
	var size := TAB_ICON_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(1, 7, 2, 4), BORDER_COLOR)
	image.fill_rect(Rect2i(5, 4, 2, 7), BORDER_COLOR)
	image.fill_rect(Rect2i(9, 1, 2, 10), BORDER_COLOR)
	return ImageTexture.create_from_image(image)


## The game's gold trophy texture, loaded once. Guarded by ResourceLoader.exists
## so headless tests (no game PCK) skip it silently instead of logging an error.
func _trophy() -> Texture2D:
	if not _trophy_loaded:
		_trophy_loaded = true
		if ResourceLoader.exists(TROPHY_PATH):
			_trophy_texture = load(TROPHY_PATH)
	return _trophy_texture


## Keep the toggle states and visibility in sync with the active tab and the
## popup's open state. The filter pills only matter on the Cheevos tab.
func _sync_tab_buttons() -> void:
	for i in range(_tab_buttons.size()):
		var b: Button = _tab_buttons[i]
		b.button_pressed = (i == _tab)
		b.visible = _popup_open
	_sync_filter_buttons()


## Keep the filter pills' pressed state and visibility in sync.
func _sync_filter_buttons() -> void:
	for i in range(_filter_buttons.size()):
		var b: Button = _filter_buttons[i]
		b.button_pressed = ((i == 1) == _completed_only)
		b.visible = _popup_open and _tab == TAB_CHEEVOS


## Select a Cheevos view: index 0 = All, index 1 = Completed Only.
func _on_filter_pressed(index: int) -> void:
	var completed_only := (index == 1)
	if completed_only == _completed_only:
		return
	_completed_only = completed_only
	_scroll_offset = 0
	_sync_filter_buttons()
	queue_redraw()


## Place the tab buttons on the first row under the title and the filter pills on
## a second row (Cheevos tab only).
func _layout_tab_buttons() -> void:
	if _tab_buttons.is_empty():
		return
	var r := _popup_rect()
	var x := r.position.x + POPUP_PADDING
	var y := r.position.y + TITLE_H + POPUP_PADDING
	for i in range(_tab_buttons.size()):
		var b: Button = _tab_buttons[i]
		var width := _text_font.get_string_size(TAB_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_FONT_SIZE).x + TAB_PADDING_X + TAB_ICON_SIZE + 4.0
		b.position = Vector2(x, y)
		b.size = Vector2(width, TAB_BAR_H)
		x += width + TAB_GAP

	var fy := y + TAB_BAR_H + TAB_GAP
	var fx := r.position.x + POPUP_PADDING
	for i in range(_filter_buttons.size()):
		var f: Button = _filter_buttons[i]
		var fw := _text_font.get_string_size(FILTER_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FILTER_FONT_SIZE).x + TAB_PADDING_X
		f.position = Vector2(fx, fy)
		f.size = Vector2(fw, FILTER_BAR_H)
		fx += fw + TAB_GAP


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
## and the Cheevos visible window (plus its filter row), so switching tabs never
## resizes the popup.
func _popup_height() -> float:
	var top := TITLE_H + POPUP_PADDING + TAB_BAR_H + TAB_GAP
	var high_scores_h := top + HEADER_ROW_H + HEADER_GAP + _table_row_count() * ROW_H + POPUP_PADDING
	var cheevos_h := top + FILTER_BAR_H + FILTER_GAP + CHEEVO_VISIBLE_ROWS * CHEEVO_ROW_H + POPUP_PADDING
	return maxf(high_scores_h, cheevos_h)


func _draw_content(rect: Rect2) -> void:
	var content := _content_rect(rect)
	if _tab == TAB_CHEEVOS:
		_draw_cheevos_progress(rect)
		_draw_progress_bar(rect)
		_draw_cheevos(content)
	else:
		_draw_table(content)


## The content rect below the tab row (and the Cheevos filter row when on the
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


## Draw the "X of Y" progress label right-aligned on the tab row.
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


## Draw the completion progress bar right-aligned on the filter row.
func _draw_progress_bar(rect: Rect2) -> void:
	var inner_left := rect.position.x + POPUP_PADDING
	var inner_w := rect.size.x - POPUP_PADDING * 2.0
	var y := rect.position.y + TITLE_H + POPUP_PADDING + TAB_BAR_H + TAB_GAP
	var bar_x := inner_left + inner_w - PROGRESS_BAR_W
	var bar_y := y + (FILTER_BAR_H - PROGRESS_BAR_H) * 0.5
	var track := Rect2(Vector2(bar_x, bar_y), Vector2(PROGRESS_BAR_W, PROGRESS_BAR_H))
	draw_rect(track, Color(0.0, 0.0, 0.0, 0.4))
	draw_rect(track, BORDER_COLOR, false, 1.0)
	var total := _cheevo_entries().size()
	var earned := AchievementStore.earned_count(_achievements)
	if total > 0 and earned > 0:
		var frac := float(earned) / float(total)
		draw_rect(
			Rect2(Vector2(bar_x + 1.0, bar_y + 1.0), Vector2((PROGRESS_BAR_W - 2.0) * frac, PROGRESS_BAR_H - 2.0)),
			BORDER_COLOR)


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


## The reaction icon for a card: the entry's loose icon file when present,
## otherwise the species icon. Cached per id.
func _cheevo_icon(entry: Dictionary) -> Texture2D:
	var id := str(entry.get("id", ""))
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	var icon_file := str(entry.get("icon_file", ""))
	if not icon_file.is_empty():
		var image := Image.load_from_file(MOD_ICON_DIR.path_join(icon_file))
		if image != null:
			tex = ImageTexture.create_from_image(image)
	if tex == null:
		var species := str(entry.get("species", ""))
		if not species.is_empty():
			tex = SpeciesIcons.icon_for(species)
	_icon_cache[id] = tex
	return tex


## Draw the Cheevos list as cards: checkbox, reaction icon, title, description
## (or teaser), and a trophy.
func _draw_cheevos(rect: Rect2) -> void:
	var inner_left := rect.position.x + POPUP_PADDING
	var inner_w := rect.size.x - POPUP_PADDING * 2.0
	var row_y := rect.position.y + TITLE_H + POPUP_PADDING

	var entries := _visible_cheevo_entries()
	for i in range(CHEEVO_VISIBLE_ROWS):
		var entry_index := _scroll_offset + i
		if entry_index >= entries.size():
			break
		var entry: Dictionary = entries[entry_index]
		var card := Rect2(Vector2(inner_left, row_y), Vector2(inner_w, CHEEVO_ROW_H - CHEEVO_ROW_GAP))
		_draw_cheevo_card(card, entry, _is_earned(str(entry.get("id", ""))))
		row_y += CHEEVO_ROW_H


## Draw one reaction card.
func _draw_cheevo_card(card: Rect2, entry: Dictionary, earned: bool) -> void:
	_card_style(earned).draw(get_canvas_item(), card)
	var id := str(entry.get("id", ""))
	var pad := 6.0

	# Completion checkbox.
	var box := Rect2(
		Vector2(card.position.x + pad, card.position.y + (card.size.y - CHEEVO_CHECKBOX_SIZE) * 0.5),
		Vector2(CHEEVO_CHECKBOX_SIZE, CHEEVO_CHECKBOX_SIZE))
	if earned:
		draw_rect(box, BORDER_COLOR)
		_draw_check(box)
	else:
		draw_rect(box, CHEEVO_DIM_COLOR, false, 1.0)

	# Reaction icon.
	var icon_x := box.position.x + CHEEVO_CHECKBOX_SIZE + 6.0
	var icon_rect := Rect2(
		Vector2(icon_x, card.position.y + (card.size.y - CHEEVO_ICON_SIZE) * 0.5),
		Vector2(CHEEVO_ICON_SIZE, CHEEVO_ICON_SIZE))
	var icon := _cheevo_icon(entry)
	if icon != null:
		PanelIcons.draw_fit(self, icon, icon_rect)

	# Trophy on the right.
	var trophy_rect := Rect2(
		Vector2(card.position.x + card.size.x - pad - CHEEVO_TROPHY_SIZE, card.position.y + (card.size.y - CHEEVO_TROPHY_SIZE) * 0.5),
		Vector2(CHEEVO_TROPHY_SIZE, CHEEVO_TROPHY_SIZE))
	_draw_trophy(trophy_rect, earned)

	# Title and description / teaser.
	var text_x := icon_rect.position.x + CHEEVO_ICON_SIZE + 6.0
	var text_w := trophy_rect.position.x - 6.0 - text_x
	var title := _cheevo_display_title(entry)
	var title_color: Color = TITLE_COLOR if earned else CHEEVO_DIM_COLOR
	_draw_text_shadow(
		Vector2(text_x, card.position.y + 13.0),
		title, title_color, BODY_FONT_SIZE,
		HORIZONTAL_ALIGNMENT_LEFT, text_w)
	if earned:
		var desc := ReactionText.description_for(id)
		if not desc.is_empty():
			_draw_text_shadow(
				Vector2(text_x, card.position.y + 24.0),
				desc, DESCRIPTION_COLOR, CHEEVO_DESC_FONT_SIZE,
				HORIZONTAL_ALIGNMENT_LEFT, text_w)
	else:
		var hint := ReactionText.hint_for(id)
		if not hint.is_empty():
			_draw_hint_text(Vector2(text_x, card.position.y + 24.0), hint, text_w)


## The card background: a gold-tinted panel when earned, a dim panel when locked.
func _card_style(earned: bool) -> StyleBoxFlat:
	if earned:
		if _card_done_style == null:
			_card_done_style = StyleBoxFlat.new()
			_card_done_style.bg_color = Color(0.95, 0.61, 0.07, 0.12)
			_card_done_style.border_color = BORDER_COLOR
			_card_done_style.set_border_width_all(1)
			_card_done_style.set_corner_radius_all(4)
		return _card_done_style
	if _card_locked_style == null:
		_card_locked_style = StyleBoxFlat.new()
		_card_locked_style.bg_color = Color(0.0, 0.0, 0.0, 0.18)
		_card_locked_style.border_color = Color(0.55, 0.6, 0.68, 0.5)
		_card_locked_style.set_border_width_all(1)
		_card_locked_style.set_corner_radius_all(4)
	return _card_locked_style


## Draw the trophy: full colour when earned, dimmed with a "?" when locked.
func _draw_trophy(rect: Rect2, earned: bool) -> void:
	var tex := _trophy()
	if tex == null:
		return
	if earned:
		PanelIcons.draw_fit(self, tex, rect)
		return
	draw_texture_rect(tex, rect, false, Color(0.45, 0.48, 0.55, 0.5))
	var q := "?"
	var qw := _text_font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_FONT_SIZE).x
	draw_string(
		_text_font,
		Vector2(rect.position.x + (rect.size.x - qw) * 0.5, rect.position.y + rect.size.y * 0.72),
		q, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_FONT_SIZE, CHEEVO_DIM_COLOR)


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
