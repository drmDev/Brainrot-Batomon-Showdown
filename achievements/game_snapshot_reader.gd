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
##       "income": int,                   # derived shop income (see _read_income)
##       "team": [monster, ...],          # only when the run exposes it
##       "bench": [monster, ...],         # only when the run exposes it
##     }
##   battle snapshot: the run snapshot fields plus
##     {
##       "kind": "battle",
##       "battle_over": bool,             # only when the simulation data exposes it
##       "battle_units": [unit, ...],     # only when the simulation data exposes it
##       "outcome": {"wins": int, "lives": int},
##                                        # COMMITTED post-battle totals from the
##                                        # promoted RunManager.data run; absent
##                                        # when a safe committed read is not possible
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
## Verified field names:
##   run: run_id, trainer_id, current_round, lives, current_wins, team, bench,
##        _active_passives[].gold_gain (income derivation only),
##        pending_round_start, pending_battle_opponent (promoted-run outcome guards;
##        verified in BatomonHelperBridge read_battle_outcome)
##   monster: data.name_key, level
##   battle: simulation.data.battle_over,
##           simulation.data.battle_units[].{team_id, slot_index, shield_granted,
##             damage_dealt, healing_done, burn_inflicted, poison_inflicted,
##             shock_inflicted}
##   (Verified in examples/MyBattleStats, the BatomonHelperBridge mod, and a live
##   field probe of a real battle.)

const KIND_RUN := "run"
const KIND_BATTLE := "battle"

## Shop income schedule, copied from Creature Comforts' _compute_daily_income:
## BASE_INCOME + INCOME_PER_DAY * (day - 1), plus each active passive's gold_gain.
const BASE_INCOME := 35
const INCOME_PER_DAY := 5

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
##
## replay_run is the battle state's pre-battle template copy (does NOT contain the
## post-battle win count). committed_run is the promoted RunManager.data run; when
## its identity and pending state prove it is the same battle's committed result,
## the snapshot gains an `outcome` with the post-battle wins/lives.
func read_battle(state, replay_run, committed_run = null) -> Dictionary:
	if not _is_live(state):
		return {}
	var snapshot := _read_run_fields(replay_run, KIND_BATTLE) if _is_live(replay_run) else {"kind": KIND_BATTLE}
	var outcome := _read_outcome(replay_run, committed_run)
	if not outcome.is_empty():
		snapshot["outcome"] = outcome

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
	var day = snapshot.get("current_round")
	if day is int:
		snapshot["income"] = _read_income(run, int(day))
	for list_name in ["team", "bench"]:
		if _has_prop.call(run, list_name):
			snapshot[list_name] = _read_monsters(run.get(list_name))
	return snapshot


## Derived shop income for the run: the game's daily schedule plus passive bonuses.
## Mirrors Creature Comforts' _compute_daily_income exactly. Emitted only when the
## day is known; without it the schedule cannot be computed.
func _read_income(run, day: int) -> int:
	var income := BASE_INCOME + INCOME_PER_DAY * maxi(day - 1, 0)
	if not _has_prop.call(run, "_active_passives"):
		return income
	var passives = run.get("_active_passives")
	if not passives is Array:
		return income
	for passive in passives:
		if not _is_live(passive):
			continue
		var gain = _read_int(passive, "gold_gain")
		if gain != null:
			income += gain
	return income


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


## Committed post-battle totals, only when the promoted run is provably the same
## battle's result. Guards mirror BatomonHelperBridge read_battle_outcome (verified):
## same run_id and round, pending_round_start true, no pending battle opponent.
## The replay template copy and the promoted run are never the same instance.
## Returns {} when any guard fails or wins/lives are not numeric.
func _read_outcome(replay_run, committed_run) -> Dictionary:
	if not _is_live(replay_run) or not _is_live(committed_run):
		return {}
	if replay_run == committed_run:
		return {}

	if _has_prop.call(replay_run, "run_id") and _has_prop.call(committed_run, "run_id"):
		if str(replay_run.get("run_id")) != str(committed_run.get("run_id")):
			return {}

	var replay_round = _read_int(replay_run, "current_round")
	var committed_round = _read_int(committed_run, "current_round")
	if replay_round != null and committed_round != null and replay_round != committed_round:
		return {}

	if _has_prop.call(committed_run, "pending_round_start") and not bool(committed_run.get("pending_round_start")):
		return {}
	if _has_prop.call(committed_run, "pending_battle_opponent"):
		var opponent = committed_run.get("pending_battle_opponent")
		if opponent is Dictionary and not opponent.is_empty():
			return {}
		if opponent is Array and not opponent.is_empty():
			return {}

	var wins = _read_int(committed_run, "current_wins")
	var lives = _read_int(committed_run, "lives")
	if wins == null or lives == null:
		return {}
	return {"wins": wins, "lives": lives}


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
