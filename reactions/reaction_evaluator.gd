extends RefCounted
## ReactionEvaluator - detects "reactions" from game snapshots.
##
## Rules only: consumes the plain snapshots produced by
## snapshots/game_snapshot_reader.gd and returns newly triggered reaction matches.
## It never touches live game objects, files, UI, or any persisted state, so a
## reaction fires purely from the current snapshot.
##
##   poll(run_snapshot)            -> run-scoped reaction matches
##   poll_battle(battle_snapshot)  -> battle-scoped reaction matches
##   reset_run()                   -> clear everything for a new run
##   reset_battle()                -> clear battle-scoped tracking for a new battle
##
## Each returned match is {"id": String, "case": String, "params": Dictionary,
## "species_key": String}. catalog/reaction_text.gd turns that into the user text.
##
## Reaction metadata and conditions live in catalog/brain_rot_catalog.gd. This file
## owns occurrence tracking and the battle tie-break; the catalog owns the
## per-reaction conditions.
##
## Occurrence semantics:
## - Run-scoped: triggers once per run, the first time a matching snapshot is seen.
##   Repeated matching polls, leaving and returning, and a menu round-trip (run
##   unavailable) do not retrigger. Only reset_run() clears it. mod_main calls
##   poll() only while the shop state is active (the start of a day), so a battle's
##   committed lives/wins cannot trigger it before the player sees the next day.
##   This evaluator stays phase-agnostic; the caller owns that timing.
## - Battle-scoped: evaluated only on the FINAL battle totals (battle_over), never
##   mid-fight. Each battle reaction fires at most ONCE per battle, even when several
##   units qualify: the lowest slot wins, and within that slot the first metric in
##   BATTLE_METRIC_ORDER. Different battle reactions are tracked independently, so
##   several of them can fire in the same battle. A battle rule may also restrict
##   matches to a species via its `species` key (Big Dog is Cinnabark-only).
## - An empty snapshot does NOT reset anything.
##
## LIMITATION: occurrence tracking is session-only. Restarting the game or the mod
## can allow a reaction to trigger again within a continuing run.

const Catalog = preload("../catalog/brain_rot_catalog.gd")

# Evaluation scope labels for registered_rows() (dev tooling / catalog).
const SCOPE_RUN := Catalog.SCOPE_RUN
const SCOPE_BATTLE := Catalog.SCOPE_BATTLE

const PLAYER_TEAM_ID := 0  # battle_units team_id used for the player's side


## Every registered reaction scope. Dev tooling and schema tests iterate this so a
## new reaction cannot be forgotten.
static func registered_rows() -> Array:
	return Catalog.registered_rows()


# Run-scoped occurrence count per reaction id. Presence means "already triggered".
var _occurrences: Dictionary = {}
# Battle-scoped: reaction ids that already fired for the current battle.
var _battle_fired: Dictionary = {}


## Poll a run snapshot. Returns newly triggered run-scoped matches (empty most polls).
func poll(run_snapshot: Dictionary) -> Array:
	var triggered: Array = []
	if run_snapshot.is_empty():
		return triggered

	for definition in Catalog.reactions():
		var id := str(definition.get("id", ""))
		if id.is_empty() or _occurrences.has(id):
			continue
		var match: Dictionary = Catalog.run_match(id, run_snapshot)
		if match.is_empty():
			continue
		_occurrences[id] = 1
		triggered.append({
			"id": id,
			"case": str(match.get("case", "")),
			"params": match.get("params", {}),
			"species_key": _species_key_from_definition(definition),
		})
	return triggered


## Poll a completed battle snapshot. Returns at most one reaction per battle
## reaction id: the lowest player-side slot with a metric satisfying that
## reaction's comparison. Mid-battle snapshots never match.
func poll_battle(battle_snapshot: Dictionary) -> Array:
	var triggered: Array = []
	if battle_snapshot.is_empty():
		return triggered
	if not bool(battle_snapshot.get("battle_over", false)):
		return triggered

	var units = battle_snapshot.get("battle_units")
	var team = battle_snapshot.get("team")
	if not team is Array:
		team = []

	if units is Array:
		for definition in Catalog.reactions():
			var id := str(definition.get("id", ""))
			if id.is_empty() or _battle_fired.has(id):
				continue
			var rule := Catalog.battle_rule(id)
			if rule.is_empty():
				continue
			var found := _find_battle_match(units, team, rule)
			if found.is_empty():
				continue
			_battle_fired[id] = true
			var species_key := _species_key_at(team, int(found.get("slot", -1)))
			triggered.append({
				"id": id,
				"case": "battle",
				"params": {
					"species_key": species_key,
					"metric": str(found.get("label", "")),
					"value": int(found.get("value", 0)),
				},
				"species_key": species_key,
			})

	return triggered


## Clear all tracking. Call at a verified run transition.
func reset_run() -> void:
	_occurrences.clear()
	_battle_fired.clear()


## Clear battle-scoped tracking. Call when entering a new battle.
func reset_battle() -> void:
	_battle_fired.clear()


## How many times this run-scoped reaction has triggered in the current run (0 or 1).
func occurrence_count(id: String) -> int:
	return int(_occurrences.get(id, 0))


## Lowest player-side slot with a metric satisfying `rule`, plus the first
## matching metric label in BATTLE_METRIC_ORDER and the actual total. Returns {}
## when nothing matches. When `rule` carries a `species` key, only units whose
## team slot resolves to that species name_key can match.
func _find_battle_match(units: Array, team: Array, rule: Dictionary) -> Dictionary:
	var expected := int(rule.get("value", 0))
	var strict := bool(rule.get("strict", false))
	var metric_labels = rule.get("metrics")
	if not metric_labels is Array:
		metric_labels = Catalog.BATTLE_METRIC_ORDER
	var species_filter := str(rule.get("species", ""))

	var best_slot := -1
	var best_label := ""
	var best_value := 0
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
		# Optional species filter: the unit's team slot must resolve to this
		# species (Big Dog is Cinnabark-only).
		if not species_filter.is_empty():
			if slot < 0 or slot >= team.size():
				continue
			var team_entry = team[slot]
			if not team_entry is Dictionary:
				continue
			if str(team_entry.get("name_key", "")) != species_filter:
				continue
		# A lower slot already matched, so this unit cannot win.
		if best_slot >= 0 and slot >= best_slot:
			continue
		for label in Catalog.BATTLE_METRIC_ORDER:
			if not metric_labels.has(label):
				continue
			var key := str(Catalog.BATTLE_METRICS.get(label, ""))
			var value = unit.get(key)
			# The reader emits floats for battle counters (e.g. heal=420.0), so
			# accept both numeric types and compare the integer total.
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				continue
			var actual := int(value)
			var matched := actual > expected if strict else actual == expected
			if matched:
				best_slot = slot
				best_label = label
				best_value = actual
				break
	if best_slot < 0:
		return {}
	return {"slot": best_slot, "label": best_label, "value": best_value}


## Species key of the monster in a team slot, or "" when unavailable. This is the
## value the presentation layer uses to look up the monster's icon.
func _species_key_at(team: Array, slot: int) -> String:
	if slot < 0 or slot >= team.size():
		return ""
	var entry = team[slot]
	if not entry is Dictionary:
		return ""
	return str(entry.get("name_key", ""))


## Static species key authored on a reaction definition, or "" when absent. Run
## reactions tied to a specific monster (apes/oh_yeah/herd) carry this metadata.
func _species_key_from_definition(definition: Dictionary) -> String:
	return str(definition.get("species", ""))
