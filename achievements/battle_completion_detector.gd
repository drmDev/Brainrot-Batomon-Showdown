extends RefCounted
## BattleCompletionDetector - reports each battle's completion exactly once.
## Detection only: no UI, no logging, no achievement knowledge.
##
## Signal used (verified in examples/MyBattleStats/disabled_mod_main.gd):
##   battle_state.simulation.data.battle_over == true
## This flag is result-agnostic, so it covers wins, losses, and draws.
## Completion is never inferred from negative HP.


var _battle_state_id := 0  # instance id of the battle state being tracked
var _reported := false     # completion already reported for the current battle


## Poll the battle state. Returns true exactly once per completed battle;
## false on any later poll for the same battle.
func poll(state) -> bool:
	if state == null or not is_instance_valid(state):
		reset()
		return false

	var instance_id: int = state.get_instance_id()
	if instance_id != _battle_state_id:
		# New battle state instance (or first poll after a reset)
		_battle_state_id = instance_id
		_reported = false

	if _reported:
		return false

	var sim = state.get("simulation")
	if sim == null or not is_instance_valid(sim):
		return false

	var data = sim.get("data")
	if data == null:
		return false

	if not bool(data.get("battle_over")):
		return false

	_reported = true
	return true


## Clear tracking. Call when leaving the battle phase so a later battle is detected again.
func reset() -> void:
	_battle_state_id = 0
	_reported = false
