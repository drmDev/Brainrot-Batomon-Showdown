extends RefCounted
## ReactionPlayer - presents a triggered reaction.
##
## Logs the reaction line (console and session log) and, when a submit sink is
## provided, submits a NotificationRequest so the shared toast queue shows it.
## Logging is independent of toast queuing and dedupe: every reaction logs once.
##
## Log format: "Brain Rot: REACTION | <id> | <detail>"
##   e.g. "Brain Rot: REACTION | six_seven | Lives 6, Wins 7"

const NotificationRequest = preload("../notifications/notification_request.gd")

## Toast titles per reaction id. Unknown ids fall back to the id itself.
const REACTION_TITLES := {
	"six_seven": "6 7",
	"six_nine": "6 9",
	"four_twenty": "Blaze It",
	"six_six_six": "Number of the Beast",
	"over_9000": "It's Over 9000!",
}

var _log_fn: Callable
var _submit_fn: Callable


## log_fn: optional sink (tests inject a collector). Defaults to print().
## submit_fn: optional notification sink; receives a NotificationRequest.
func _init(log_fn: Callable = Callable(), submit_fn: Callable = Callable()) -> void:
	_log_fn = log_fn
	_submit_fn = submit_fn


## Play one reaction. A reaction without an id is skipped.
func play(reaction: Dictionary) -> void:
	var id := str(reaction.get("id", ""))
	if id.is_empty():
		push_warning("Brain Rot: reaction without id ignored")
		return
	var detail := str(reaction.get("detail", ""))
	_log("Brain Rot: REACTION | %s | %s" % [id, detail])
	_submit(id, detail)


## Play every reaction in the list, once each.
func play_all(reactions: Array) -> void:
	for reaction in reactions:
		if reaction is Dictionary:
			play(reaction)


func _submit(id: String, detail: String) -> void:
	if not _submit_fn.is_valid():
		return
	_submit_fn.call(NotificationRequest.new(
		NotificationRequest.KIND_REACTION,
		id,
		str(REACTION_TITLES.get(id, id)),
		detail,
	))


func _log(line: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(line)
		return
	print(line)
