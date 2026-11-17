extends RefCounted
## ReactionPlayer - presents a triggered reaction.
##
## Logs the reaction line (console and session log), submits a NotificationRequest
## so the shared toast queue shows it, and forwards the reaction id to an optional
## sound sink (the caller decides which sounds to play).
## Logging is independent of toast queuing and dedupe: every reaction logs once.
##
## Log format: "Brain Rot: REACTION | <id> | <detail>"
##   e.g. "Brain Rot: REACTION | six_seven | Lives 6, Wins 7"

const NotificationRequest = preload("../notifications/notification_request.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")

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


## Play one reaction. A reaction without an id is skipped.
func play(reaction: Dictionary) -> void:
	var id := str(reaction.get("id", ""))
	if id.is_empty():
		push_warning("Brain Rot: reaction without id ignored")
		return
	var detail := str(reaction.get("detail", ""))
	var species_key := str(reaction.get("species_key", ""))
	_log("Brain Rot: REACTION | %s | %s" % [id, detail])
	_submit(id, detail, species_key)
	if _sound_fn.is_valid():
		_sound_fn.call(id)


## Play every reaction in the list, once each.
func play_all(reactions: Array) -> void:
	for reaction in reactions:
		if reaction is Dictionary:
			play(reaction)


func _submit(id: String, detail: String, species_key: String) -> void:
	if not _submit_fn.is_valid():
		return
	var request = NotificationRequest.new(
		NotificationRequest.KIND_REACTION,
		id,
		Catalog.title_for(id),
		detail,
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
