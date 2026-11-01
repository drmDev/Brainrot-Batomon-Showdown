extends RefCounted
## ReactionEvaluator - detects "reactions" from game snapshots.
##
## Rules only: consumes the plain snapshots produced by
## achievements/game_snapshot_reader.gd and returns newly triggered reaction
## dictionaries. It never touches live game objects, files, UI, or the achievement
## store, so a completed achievement can never suppress a reaction.
##
##   poll(run_snapshot)            -> run-scoped reactions
##   poll_battle(battle_snapshot)  -> battle-scoped reactions
##   reset_run()                   -> clear everything for a new run
##   reset_battle()                -> clear battle-scoped tracking for a new battle
##
## Each returned reaction is {"id": String, "detail": String}.
##
## Occurrence semantics:
## - Run-scoped: triggers once per run, the first time a matching snapshot is seen.
##   Repeated matching polls, leaving and returning, and a menu round-trip (run
##   unavailable) do not retrigger. Only reset_run() clears it.
## - Battle-scoped: evaluated only on the FINAL battle totals (battle_over), never
##   mid-fight. Fires at most ONCE per battle, even when several units qualify: the
##   lowest slot wins, and within that slot the first metric in BATTLE_METRICS order.
## - An empty snapshot does NOT reset anything.
##
## LIMITATION: occurrence tracking is session-only. Restarting the game or the mod
## can allow a reaction to trigger again within a continuing run.
##
## Reactions:
## - "six_seven"
##   Run condition: remaining Lives == 6 AND committed cumulative Wins == 7.
##     A run starts with 10 lives, so this is 4 lives lost and 7 wins.
##     Fields: run.lives and run.current_wins (RunManager.data), read from the same
##     snapshot so both values come from one poll. Missing, null, or non-numeric
##     values never match.
##   Battle condition: any player-side unit's FINAL battle total is exactly 67 on one
##     of these metrics: damage, heal, shield, burn, poison, shock. Checked once the
##     battle is over, not while it is running. All six are accumulated per-battle
##     counters: damage_dealt, healing_done, shield_granted, burn_inflicted,
##     poison_inflicted, shock_inflicted. The log names the unit (slot + species) and
##     the metric. Only the lowest matching slot is reported.

const SIX_SEVEN_ID := "six_seven"
const SIX_SEVEN_LIVES := 6
const SIX_SEVEN_WINS := 7
const SIX_SEVEN_VALUE := 67

const PLAYER_TEAM_ID := 0  # battle_units team_id used for the player's side

## Run-scoped reaction table: one row per reaction. Add rows here rather than new
## classes; the condition code stays in _matches().
const REACTIONS := [
	{"id": SIX_SEVEN_ID, "lives": SIX_SEVEN_LIVES, "wins": SIX_SEVEN_WINS},
]

## Battle metrics checked against SIX_SEVEN_VALUE, in log order. All are accumulated
## per-battle counters on the unit record.
const BATTLE_METRICS := [
	{"key": "damage_dealt", "label": "damage"},
	{"key": "healing_done", "label": "heal"},
	{"key": "shield_granted", "label": "shield"},
	{"key": "burn_inflicted", "label": "burn"},
	{"key": "poison_inflicted", "label": "poison"},
	{"key": "shock_inflicted", "label": "shock"},
]

# Run-scoped occurrence count per reaction id. Presence means "already triggered".
var _occurrences: Dictionary = {}
# Battle-scoped: the reaction already fired for the current battle.
var _battle_fired := false


## Poll a run snapshot. Returns newly triggered run-scoped reactions (empty most polls).
func poll(run_snapshot: Dictionary) -> Array:
	var triggered: Array = []
	if run_snapshot.is_empty():
		return triggered

	for reaction in REACTIONS:
		var id := str(reaction.get("id", ""))
		if id.is_empty() or _occurrences.has(id):
			continue
		if not _matches(reaction, run_snapshot):
			continue
		_occurrences[id] = int(_occurrences.get(id, 0)) + 1
		triggered.append({
			"id": id,
			"detail": "Lives %d, Wins %d" % [
				int(run_snapshot.get("lives")),
				int(run_snapshot.get("current_wins")),
			],
		})
	return triggered


## Poll a completed battle snapshot. Returns at most one battle-scoped reaction per
## battle: the lowest player-side slot with a metric exactly SIX_SEVEN_VALUE. Mid-battle
## snapshots never match.
func poll_battle(battle_snapshot: Dictionary) -> Array:
	if _battle_fired or battle_snapshot.is_empty():
		return []
	if not bool(battle_snapshot.get("battle_over", false)):
		return []

	var units = battle_snapshot.get("battle_units")
	if not units is Array:
		return []
	var team = battle_snapshot.get("team")
	if not team is Array:
		team = []

	var best_slot := -1
	var best_metric: Dictionary = {}
	for unit in units:
		if not unit is Dictionary:
			continue
		var team_id = unit.get("team_id")
		if typeof(team_id) != TYPE_INT or int(team_id) != PLAYER_TEAM_ID:
			continue
		var slot_value = unit.get("slot_index")
		if typeof(slot_value) != TYPE_INT:
			continue
		var slot := int(slot_value)
		# A lower slot already matched, so this unit cannot win.
		if best_slot >= 0 and slot >= best_slot:
			continue
		for metric in BATTLE_METRICS:
			if _metric_is_six_seven(unit, metric):
				best_slot = slot
				best_metric = metric
				break

	if best_slot < 0:
		return []
	_battle_fired = true
	return [{
		"id": SIX_SEVEN_ID,
		"detail": "slot %d %s %s %d" % [
			best_slot,
			_species_at(team, best_slot),
			str(best_metric.get("label", "")),
			SIX_SEVEN_VALUE,
		],
	}]


## Clear all tracking. Call at a verified run transition.
func reset_run() -> void:
	_occurrences.clear()
	_battle_fired = false


## Clear battle-scoped tracking. Call when entering a new battle.
func reset_battle() -> void:
	_battle_fired = false


## How many times this run-scoped reaction has triggered in the current run (0 or 1).
func occurrence_count(id: String) -> int:
	return int(_occurrences.get(id, 0))


## Does the snapshot satisfy this run-scoped reaction's condition? Both fields must be
## present integers; anything else (absent, null, string, bool) does not match.
func _matches(reaction: Dictionary, run_snapshot: Dictionary) -> bool:
	var lives = run_snapshot.get("lives")
	var wins = run_snapshot.get("current_wins")
	if typeof(lives) != TYPE_INT or typeof(wins) != TYPE_INT:
		return false
	return int(lives) == int(reaction.get("lives")) and int(wins) == int(reaction.get("wins"))


## Is this unit's metric exactly SIX_SEVEN_VALUE? Non-numeric values never match.
func _metric_is_six_seven(unit: Dictionary, metric: Dictionary) -> bool:
	var value = unit.get(str(metric.get("key", "")))
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return int(value) == SIX_SEVEN_VALUE


## Species name_key of the team slot, or "?" when unavailable.
func _species_at(team: Array, slot: int) -> String:
	if slot < 0 or slot >= team.size():
		return "?"
	var entry = team[slot]
	if not entry is Dictionary:
		return "?"
	var key := str(entry.get("name_key", ""))
	return key if not key.is_empty() else "?"
