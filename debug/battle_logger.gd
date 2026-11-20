extends RefCounted
## Debug logging for Brain Rot.
##
## Extracted from mod_main.gd. One line per battle probe, per player-side unit,
## and per run-progress change. Run-progress logging is gated behind state
## capture being enabled.

const NodeUtils = preload("../catalog/node_utils.gd")

var _logger = null
var _state_capture = null
var _last_progress_signature := ""


func _init(logger, state_capture) -> void:
	_logger = logger
	_state_capture = state_capture


## One line per battle describing what the battle state exposes.
func log_battle_probe(state) -> void:
	var sim = state.get("simulation") if NodeUtils.has_property(state, "simulation") else null
	var data = sim.get("data") if sim != null and NodeUtils.has_property(sim, "data") else null
	var units = data.get("battle_units") if data != null and NodeUtils.has_property(data, "battle_units") else null
	var over = data.get("battle_over") if data != null and NodeUtils.has_property(data, "battle_over") else null
	var replay = state.get("_replay_p1_data") if NodeUtils.has_property(state, "_replay_p1_data") else null
	_logger.log_event("BATTLE PHASE | sim=%s data=%s over=%s units=%s replay_run=%s" % [
		str(sim != null),
		str(data != null),
		str(over),
		str(units.size()) if units is Array else "absent",
		str(replay != null),
	])


## Log the run's day/lives/wins whenever the triple changes. Verifies the field
## mapping, the starting lives value, and when wins/lives are committed.
func log_run_progress(run_snapshot: Dictionary) -> void:
	if _state_capture == null or not _state_capture.is_enabled():
		return
	if run_snapshot.is_empty():
		return
	var day := str(run_snapshot.get("current_round", "?"))
	var lives := str(run_snapshot.get("lives", "?"))
	var wins := str(run_snapshot.get("current_wins", "?"))
	var signature := "%s|%s|%s" % [day, lives, wins]
	if signature == _last_progress_signature:
		return
	_last_progress_signature = signature
	_logger.log_event("RUN PROGRESS | Day %s, Lives %s, Wins %s" % [day, lives, wins])


## One line per player-side unit with the final metrics the reaction reads.
func log_battle_units(battle_snapshot: Dictionary) -> void:
	var units = battle_snapshot.get("battle_units")
	if not units is Array:
		return
	var team = battle_snapshot.get("team")
	if not team is Array:
		team = []
	for unit in units:
		if not unit is Dictionary:
			continue
		if int(unit.get("team_id", -1)) != 0:
			continue
		var slot := int(unit.get("slot_index", -1))
		var species := "?"
		if slot >= 0 and slot < team.size() and team[slot] is Dictionary:
			var key := str(team[slot].get("name_key", ""))
			if not key.is_empty():
				species = key
		_logger.log_event("BATTLE UNIT | slot %d %s dmg=%s heal=%s shield=%s burn=%s poison=%s shock=%s" % [
			slot,
			species,
			str(unit.get("damage_dealt", "?")),
			str(unit.get("healing_done", "?")),
			str(unit.get("shield_granted", "?")),
			str(unit.get("burn_inflicted", "?")),
			str(unit.get("poison_inflicted", "?")),
			str(unit.get("shock_inflicted", "?")),
		])
