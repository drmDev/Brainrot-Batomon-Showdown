extends RefCounted
## Run-transition detector for Brain Rot.
##
## Extracted from mod_main.gd. Pure logic: compares snapshots and returns a
## reason string when a new run is detected, or "" when nothing changed. The
## caller owns the side effects (resetting reactions, battle completion, etc.).

var _tracking: Dictionary = {}


## Detect a run transition from data we already read. Returns a reason string
## ("run id changed", "new run object", "trainer changed", "day went backwards")
## or "" when nothing changed.
##
## No verified run-start/run-end signal exists (Creature Comforts only compares
## trainer_id between snapshots), so transitions are inferred from:
##   - a different run_id (the game's own run identity),
##   - a different run object instance (only when run_id is unavailable),
##   - a different trainer_id,
##   - current_round going backwards.
##
## run_id is the primary identity because the game promotes RunManager.data to a NEW
## RunData object when a battle starts (verified in BatomonHelperBridge: it compares
## completed.run_id to the replay run's run_id). Comparing object instances alone
## produced a false "new run object" reset at every battle start.
##
## An unavailable run (menu, transition) does NOT clear tracking: the comparison on
## return is what detects a new run. Clearing here would hide a new run whose only
## evidence was the gap, and would re-arm reactions after a menu round-trip.
func check(run, run_snapshot: Dictionary) -> String:
	if run_snapshot.is_empty():
		return ""

	var run_id := str(run_snapshot.get("run_id", ""))
	var instance_id: int = run.get_instance_id() if is_instance_valid(run) else 0
	var trainer_id := str(run_snapshot.get("trainer_id", ""))
	var current_round := int(run_snapshot.get("current_round", 0))

	var tracking := {
		"run_id": run_id,
		"run_instance_id": instance_id,
		"trainer_id": trainer_id,
		"current_round": current_round,
	}
	if _tracking.is_empty():
		_tracking = tracking
		return ""

	var reason := ""
	var tracked_run_id := str(_tracking.get("run_id", ""))
	if not run_id.is_empty() and not tracked_run_id.is_empty():
		if run_id != tracked_run_id:
			reason = "run id changed"
	elif instance_id != int(_tracking.get("run_instance_id", 0)):
		reason = "new run object"
	if reason.is_empty() and trainer_id != str(_tracking.get("trainer_id", "")):
		reason = "trainer changed"
	if reason.is_empty() and current_round < int(_tracking.get("current_round", 0)):
		reason = "day went backwards"

	_tracking = tracking
	return reason
