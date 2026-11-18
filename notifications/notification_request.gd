extends RefCounted
## NotificationRequest - presentation data for one toast.
##
## Pure data: no scheduling state, no nodes, no game state. It may read catalog
## presentation metadata (title/icon) but never touches progress or saves. The
## NotificationManager owns when it is shown; the ToastView owns how it looks.
##
## Construct with .new(kind, id, title, description[, duration_ms, allow_duplicate]).

const Catalog = preload("../catalog/brain_rot_catalog.gd")
const PanelIcons = preload("../hud/panel_icons.gd")

const KIND_REACTION := "reaction"

const HEADER_UNLOCKED := "BRAIN ROT UNLOCKED"

const DEFAULT_DURATION_MS := 6000

var kind := ""
var event_key := ""
var header := ""
var title := ""
var description := ""
var id := ""
var icon := ""
var icon_texture: Texture2D = null
var icon_texture_adjust := false
var duration_ms := DEFAULT_DURATION_MS
var allow_duplicate := false


func _init(
	kind_value: String = "",
	id_value: String = "",
	title_text: String = "",
	description_text: String = "",
	duration: int = DEFAULT_DURATION_MS,
	allow_dup: bool = false
) -> void:
	kind = kind_value
	event_key = key_for(kind_value, id_value)
	header = header_for(kind_value)
	title = title_text
	description = description_text
	id = id_value
	icon = Catalog.icon_for(id_value)
	var icon_file := Catalog.icon_file_for(id_value)
	if not icon_file.is_empty():
		icon_texture = PanelIcons.load_icon(get_script().resource_path, icon_file)
		icon_texture_adjust = true
	duration_ms = duration if duration > 0 else DEFAULT_DURATION_MS
	allow_duplicate = allow_dup


## Dedupe identity for an event: "<kind>:<id>", or "" when either part is empty.
static func key_for(kind_value: String, id: String) -> String:
	if kind_value.is_empty() or id.is_empty():
		return ""
	return "%s:%s" % [kind_value, id]


## Small gold header line for a kind. Reactions use "BRAIN ROT UNLOCKED";
## unknown kinds get an empty header.
static func header_for(kind_value: String) -> String:
	if kind_value == KIND_REACTION:
		return HEADER_UNLOCKED
	return ""


## A request needs an event key and a title; everything else is optional.
func is_valid() -> bool:
	return not event_key.is_empty() and not title.is_empty()
