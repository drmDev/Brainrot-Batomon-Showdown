extends RefCounted
## GameSnapshotReader - centralizes live game-object reads into small snapshots.
##
## The evaluator and the debug capture both consume these snapshots, so the set of
## game fields the mod depends on is defined in exactly one place. Snapshots are
## plain Dictionaries (JSON-serializable) with this shape:
##
##   run snapshot:
##     {
##       "kind": "run",
##       "run_id": String,                # only when the run exposes it
##       "trainer_id": String,            # only when the run exposes it
##       "current_round": int,            # only when the run exposes a number
##       "lives": int,                    # only when the run exposes a number
##       "current_wins": int,             # only when the run exposes a number
##       "team": [monster, ...],          # only when the run exposes it
##       "bench": [monster, ...],         # only when the run exposes it
##     }
##   battle snapshot: the run snapshot fields plus
##     {
##       "kind": "battle",
##       "battle_over": bool,             # only when the simulation data exposes it
##       "battle_units": [unit, ...],     # only when the simulation data exposes it
##     }
##
## monster: {"name_key": String, "level": int} with each key present only when the
## live monster exposes it. A null/invalid monster becomes {} so list positions are
## preserved (Big Dog resolves species by slot index).
## unit: {"team_id": int, "slot_index": int, "shield_granted": float,
##        "damage_dealt": float, "healing_done": float,
##        "burn_inflicted": int, "poison_inflicted": int, "shock_inflicted": int},
##   same rule. All are accumulated per-battle counters (verified against the game's
##   own battle numbers: burn_inflicted/poison_inflicted match the displayed totals,
##   while get_stat(4/5/6) is only the unit's stat and must not be used).
##
## Unknown values are represented by an ABSENT key, never a default. Defaults belong
## to the rules (the evaluator), not to the reader. Numeric fields are emitted only
## when the live value is a number: a missing, null, or non-numeric value is absent
## (and never raises, unlike a bare int(null)).
##
## Verified field names (see dev/QUALITY.md "Grounding fakes in real game data"):
##   run: run_id, trainer_id, current_round, lives, current_wins, team, bench
##   monster: data.name_key, level
##   battle: simulation.data.battle_over,
##           simulation.data.battle_units[].{team_id, slot_index, shield_granted,
##             damage_dealt, healing_done, burn_inflicted, poison_inflicted,
##             shock_inflicted}
##   (Verified in examples/MyBattleStats, the BatomonHelperBridge mod, and a live
##   field probe of a real battle.)

const KIND_RUN := "run"
const KIND_BATTLE := "battle"

# Shared property probe (mod_main passes its _has_property Callable).
var _has_prop: Callable


func _init(has_property_fn: Callable) -> void:
	_has_prop = has_property_fn


## Snapshot of the run. Returns {} when the run is null or invalid.
func read_run(run) -> Dictionary:
	if not _is_live(run):
		return {}
	return _read_run_fields(run, KIND_RUN)


## Snapshot of the run plus the battle simulation fields. Returns {} when the state
## is null or invalid. Run fields are omitted when the run is unavailable, so the
## battle fields can still be captured.
func read_battle(state, run) -> Dictionary:
	if not _is_live(state):
		return {}
	var snapshot := _read_run_fields(run, KIND_BATTLE) if _is_live(run) else {"kind": KIND_BATTLE}

	var sim = state.get("simulation") if _has_prop.call(state, "simulation") else null
	if not _is_live(sim):
		return snapshot
	var data = sim.get("data") if _has_prop.call(sim, "data") else null
	if not _is_live(data):
		return snapshot

	if _has_prop.call(data, "battle_over"):
		snapshot["battle_over"] = bool(data.get("battle_over"))
	if _has_prop.call(data, "battle_units"):
		snapshot["battle_units"] = _read_battle_units(data.get("battle_units"))
	return snapshot


## Is this battle snapshot complete enough to evaluate? Used before consuming the
## one-time battle-completion notification so a partial read is retried next poll.
func is_battle_snapshot_usable(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return false
	if not snapshot.has("trainer_id"):
		return false
	if not snapshot.get("team") is Array:
		return false
	if not snapshot.get("battle_units") is Array:
		return false
	return true


func _read_run_fields(run, kind: String) -> Dictionary:
	var snapshot := {"kind": kind}
	if not _is_live(run):
		return snapshot
	if _has_prop.call(run, "run_id"):
		snapshot["run_id"] = str(run.get("run_id"))
	if _has_prop.call(run, "trainer_id"):
		snapshot["trainer_id"] = str(run.get("trainer_id"))
	for number_name in ["current_round", "lives", "current_wins"]:
		var number = _read_int(run, number_name)
		if number != null:
			snapshot[number_name] = number
	for list_name in ["team", "bench"]:
		if _has_prop.call(run, list_name):
			snapshot[list_name] = _read_monsters(run.get(list_name))
	return snapshot


func _read_monsters(monsters) -> Array:
	var out: Array = []
	if not monsters is Array:
		return out
	for monster in monsters:
		var entry := {}
		if _is_live(monster):
			if _has_prop.call(monster, "data"):
				var data = monster.get("data")
				if _is_live(data) and _has_prop.call(data, "name_key"):
					entry["name_key"] = str(data.get("name_key"))
			var level = _read_int(monster, "level")
			if level != null:
				entry["level"] = level
		out.append(entry)
	return out


func _read_battle_units(units) -> Array:
	var out: Array = []
	if not units is Array:
		return out
	for unit in units:
		if not _is_live(unit):
			continue
		var entry := {}
		var team_id = _read_int(unit, "team_id")
		if team_id != null:
			entry["team_id"] = team_id
		var slot_index = _read_int(unit, "slot_index")
		if slot_index != null:
			entry["slot_index"] = slot_index
		for float_name in ["shield_granted", "damage_dealt", "healing_done"]:
			var value = _read_float(unit, float_name)
			if value != null:
				entry[float_name] = value
		for int_name in ["burn_inflicted", "poison_inflicted", "shock_inflicted"]:
			var int_value = _read_int(unit, int_name)
			if int_value != null:
				entry[int_name] = int_value
		out.append(entry)
	return out


## Integer value of a live object's property, or null when missing/null/non-numeric.
## Accepts int and float (floats are truncated) so a numeric field never raises.
func _read_int(obj, property: String):
	if not _has_prop.call(obj, property):
		return null
	var value = obj.get(property)
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		return int(value)
	return null


## Float value of a live object's property, or null when missing/null/non-numeric.
func _read_float(obj, property: String):
	if not _has_prop.call(obj, property):
		return null
	var value = obj.get(property)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return null


func _is_live(obj) -> bool:
	return obj != null and is_instance_valid(obj)
