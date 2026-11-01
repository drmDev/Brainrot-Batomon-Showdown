extends RefCounted
## BattleCompletionDetector - reports each battle's completion exactly once.
## Detection only: no UI, no logging, no achievement knowledge.
##
## This class owns WHEN battle-scoped evaluation happens. The caller asks
## is_pending(state); if true it builds a snapshot, and only once that snapshot is
## usable does it call consume(). A partial read therefore leaves the completion
## pending and it is retried on the next poll instead of being lost.
##
## Signal used (verified in examples/MyBattleStats/disabled_mod_main.gd):
##   battle_state.simulation.data.battle_over == true
## This flag is result-agnostic, so it covers wins, losses, and draws.
## Completion is never inferred from negative HP.


var _battle_state_id := 0  # instance id of the battle state being tracked
var _reported := false     # completion already reported for the current battle
var _pending := false      # is_pending() saw a completion that is not yet consumed


## Is this battle complete and not yet reported? Non-consuming: safe to call every
## poll. Returns false for a null/invalid state (and resets tracking).
func is_pending(state) -> bool:
	if state == null or not is_instance_valid(state):
		reset()
		return false

	var instance_id: int = state.get_instance_id()
	if instance_id != _battle_state_id:
		# New battle state instance (or first poll after a reset)
		_battle_state_id = instance_id
		_reported = false
		_pending = false

	if _reported:
		return false

	var sim = state.get("simulation")
	if sim == null or not is_instance_valid(sim):
		return false

	var data = sim.get("data")
	if data == null:
		return false

	_pending = bool(data.get("battle_over"))
	return _pending


## Mark the pending completion as reported. Call only after a usable snapshot has
## been obtained. Returns true when a completion was actually consumed.
func consume() -> bool:
	if _reported or not _pending:
		return false
	_reported = true
	_pending = false
	return true


## Convenience: is_pending() + consume(). Returns true exactly once per completed
## battle; false on any later poll for the same battle.
func poll(state) -> bool:
	if not is_pending(state):
		return false
	return consume()


## Clear tracking. Call when leaving the battle phase so a later battle is detected again.
func reset() -> void:
	_battle_state_id = 0
	_reported = false
	_pending = false
