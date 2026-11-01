extends RefCounted
## ReactionPlayer - plays a triggered reaction.
##
## Today it only logs to the console. This is the future audio/visual integration
## point: no assets, overlay, queue, cooldown, or randomness yet.
##
## Log format: "Brain Rot: REACTION | <id> | <detail>"
##   e.g. "Brain Rot: REACTION | six_seven | Lives 6, Wins 7"

var _log_fn: Callable


## log_fn: optional sink (tests inject a collector). Defaults to print().
func _init(log_fn: Callable = Callable()) -> void:
	_log_fn = log_fn


## Play one reaction. A reaction without an id is skipped.
func play(reaction: Dictionary) -> void:
	var id := str(reaction.get("id", ""))
	if id.is_empty():
		push_warning("Brain Rot: reaction without id ignored")
		return
	var detail := str(reaction.get("detail", ""))
	_log("Brain Rot: REACTION | %s | %s" % [id, detail])


## Play every reaction in the list, once each.
func play_all(reactions: Array) -> void:
	for reaction in reactions:
		if reaction is Dictionary:
			play(reaction)


func _log(line: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(line)
		return
	print(line)
