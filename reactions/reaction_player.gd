extends RefCounted
## ReactionPlayer - presents a triggered reaction match.
##
## Takes a match Dictionary ({id, case, params, species_key}), renders the user-facing
## line via catalog/reaction_text.gd, logs it, submits a NotificationRequest so the
## shared toast queue shows it, and forwards the reaction id to an optional sound sink.
## Logging is independent of toast queuing and dedupe: every reaction logs once.
##
## The same play() is used by gameplay (preview = false) and the dev toast preview
## (preview = true), so the preview cannot drift from what players see.
##
## Log format: "Brain Rot: REACTION | <id> | <case> | <text>"
## Preview:   "Brain Rot: PREVIEW  | <id> | <case> | <text>"

const NotificationRequest = preload("../notifications/notification_request.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")
const ReactionText = preload("../catalog/reaction_text.gd")

var _log_fn: Callable
var _submit_fn: Callable
var _sound_fn: Callable
var _icon_fn: Callable


## log_fn: optional sink (tests inject a collector). Defaults to print().
## submit_fn: optional notification sink; receives a NotificationRequest.
## sound_fn: optional sink; receives the reaction id so the caller can play audio.
## icon_fn: optional sink; receives a species_key and returns a Texture2D (or null).
func _init(
	log_fn: Callable = Callable(),
	submit_fn: Callable = Callable(),
	sound_fn: Callable = Callable(),
	icon_fn: Callable = Callable()
) -> void:
	_log_fn = log_fn
	_submit_fn = submit_fn
	_sound_fn = sound_fn
	_icon_fn = icon_fn


## Play one reaction match. A match without an id is skipped.
func play(match: Dictionary, preview: bool = false) -> void:
	var id := str(match.get("id", ""))
	if id.is_empty():
		push_warning("Brain Rot: reaction without id ignored")
		return
	var case_name := str(match.get("case", ""))
	var params = match.get("params")
	if not params is Dictionary:
		params = {}
	var text := ReactionText.render(id, case_name, params)
	var species_key := str(match.get("species_key", ""))
	_log("Brain Rot: %s | %s | %s | %s" % [
		"PREVIEW" if preview else "REACTION",
		id,
		case_name,
		text,
	])
	_submit(id, text, species_key, preview)
	if _sound_fn.is_valid():
		_sound_fn.call(id)


## Play every match in the list, once each.
func play_all(matches: Array) -> void:
	for match in matches:
		if match is Dictionary:
			play(match)


func _submit(id: String, text: String, species_key: String, preview: bool) -> void:
	if not _submit_fn.is_valid():
		return
	var request = NotificationRequest.new(
		NotificationRequest.KIND_REACTION,
		id,
		Catalog.title_for(id),
		text,
		NotificationRequest.DEFAULT_DURATION_MS,
		preview,
	)
	if not species_key.is_empty() and _icon_fn.is_valid():
		var texture = _icon_fn.call(species_key)
		if texture is Texture2D:
			request.icon_texture = texture
	_submit_fn.call(request)


func _log(line: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(line)
		return
	print(line)
