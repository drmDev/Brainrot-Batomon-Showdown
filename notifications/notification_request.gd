extends RefCounted
## NotificationRequest - presentation data for one toast.
##
## Pure data: no scheduling state, no nodes, no repo dependencies. The
## NotificationManager owns when it is shown; the ToastView owns how it looks.
##
## Construct with .new(kind, id, title, description[, duration_ms, allow_duplicate]).
## The event key is kind-prefixed so an achievement and a reaction that happen to
## share an id string never collide in the dedupe check.

const KIND_ACHIEVEMENT := "achievement"
const KIND_REACTION := "reaction"

const HEADER_ACHIEVEMENT := "ACHIEVEMENT UNLOCKED!"
const HEADER_REACTION := "REACTION!"

const DEFAULT_DURATION_MS := 4000

var kind := ""
var event_key := ""
var header := ""
var title := ""
var description := ""
var duration_ms := DEFAULT_DURATION_MS
var allow_duplicate := false


func _init(
	kind_value: String = "",
	id: String = "",
	title_text: String = "",
	description_text: String = "",
	duration: int = DEFAULT_DURATION_MS,
	allow_dup: bool = false
) -> void:
	kind = kind_value
	event_key = key_for(kind_value, id)
	header = header_for(kind_value)
	title = title_text
	description = description_text
	duration_ms = duration if duration > 0 else DEFAULT_DURATION_MS
	allow_duplicate = allow_dup


## Dedupe identity for an event: "<kind>:<id>", or "" when either part is empty.
static func key_for(kind_value: String, id: String) -> String:
	if kind_value.is_empty() or id.is_empty():
		return ""
	return "%s:%s" % [kind_value, id]


## Small gold header line for a kind. Unknown kinds get an empty header.
static func header_for(kind_value: String) -> String:
	if kind_value == KIND_ACHIEVEMENT:
		return HEADER_ACHIEVEMENT
	if kind_value == KIND_REACTION:
		return HEADER_REACTION
	return ""


## A request needs an event key and a title; everything else is optional.
func is_valid() -> bool:
	return not event_key.is_empty() and not title.is_empty()
